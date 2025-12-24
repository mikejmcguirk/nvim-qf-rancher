-- local api = vim.api
local fn = vim.fn

---@class qf-rancher.Tools
local M = {}

---@param src_win integer|nil
---@param title string
---@return integer|nil
function M._find_list_with_title(src_win, title)
    local max_nr = M._get_list(src_win, { nr = "$" }).nr ---@type integer
    if src_win then
        for i = max_nr, 1, -1 do
            local title_i = fn.getloclist(src_win, { nr = i, title = 0 }).title ---@type string
            if title_i == title then
                return i
            end
        end
    else
        for i = max_nr, 1, -1 do
            local title_i = fn.getqflist({ nr = i, title = 0 }).title ---@type string
            if title_i == title then
                return i
            end
        end
    end

    return nil
end

-- LOW: The params/returns in this function are awkward. But don't want to re-inline because this
-- behavior is discrete enough to section out.

---@param src_win integer|nil
---@param cur_action qf-rancher.types.Action
---@param what qf-rancher.types.What
---@return qf-rancher.types.Action, qf-rancher.types.What
function M._resolve_title_reuse(src_win, cur_action, what)
    if not vim.g.qfr_reuse_title then
        return cur_action, what
    end

    local cur_list = M._find_list_with_title(src_win, what.title) ---@type integer|nil
    if not cur_list then
        return cur_action, what
    end

    what.nr = cur_list
    return "r", what
end

---@param src_win integer|nil
---@param nr integer|"$"|nil
---@return integer|"$"
local function resolve_list_nr(src_win, nr)
    if not nr then
        return 0
    end

    if nr == 0 or type(nr) == "string" then
        return nr
    end

    local max_nr = M._get_list(src_win, { nr = "$" }).nr ---@type integer
    return math.min(nr, max_nr)
end

-- NOTE: You can do something like vim.fn.setqflist({}) and no action will be passed. But, at
-- least for now, the tools interface requires an action to be passed, so we do not account for
-- nil action here.

---@param src_win integer|nil
---@param nr integer|"$"
---@param action qf-rancher.types.Action
---@return integer
local function get_result(src_win, nr, action)
    if action == "f" then
        return 0
    end

    local max_nr = M._get_list(src_win, { nr = "$" }).nr ---@type integer
    if type(nr) == "string" or action == " " then
        return max_nr
    end

    if nr == 0 then
        local cur_nr = M._get_list(src_win, { nr = 0 }).nr ---@type integer
        return cur_nr
    end

    return math.min(nr, max_nr)
end

---@param src_win integer|nil
---@param action qf-rancher.types.Action
---@param what qf-rancher.types.What
---@return integer
function M._set_list(src_win, action, what)
    local what_set = vim.deepcopy(what, true)
    what_set.nr = resolve_list_nr(src_win, what_set.nr)

    if what_set.idx then
        if what_set.items or what_set.lines then
            local items_len = what_set.items and #what_set.items or 0
            local lines_len = what_set.lines and #what_set.lines or 0
            local new_len = items_len + lines_len

            local new_idx = new_len > 0 and math.min(what_set.idx, new_len) or nil
            what_set.idx = new_idx
        else
            ---@type integer
            local cur_size = M._get_list(src_win, { nr = what_set.nr, size = 0 }).size
            local new_idx = math.min(what_set.idx, cur_size)
            what_set.idx = new_idx
        end
    end

    ---@type integer
    local result = src_win and fn.setloclist(src_win, {}, action, what_set)
        or fn.setqflist({}, action, what_set)

    if result == -1 then
        return result
    end

    local set_nr = get_result(src_win, what_set.nr, action)
    return set_nr
end

-- MID: This function should go to an active list. It should also handle freeing the stack and
-- closing the list if the list being cleared is the list one with items.

---@param src_win integer|nil
---@param list_nr integer|"$"|nil
---@return integer
function M._clear_list(src_win, list_nr)
    local nr = resolve_list_nr(src_win, list_nr) ---@type integer|"$"

    ---@type qf-rancher.types.What
    local what = { nr = nr, context = {}, items = {}, quickfixtextfunc = "", title = "" }
    local action = "r" ---@type qf-rancher.types.Action

    ---@type integer
    local result = src_win and fn.setloclist(src_win, {}, action, what)
        or fn.setqflist({}, action, what)

    if result == -1 then
        return result
    end

    local set_nr = get_result(src_win, what.nr, action)
    return set_nr
end

---@param src_win integer|nil
---@param what table
---@return any
function M._get_list(src_win, what)
    local what_get = vim.deepcopy(what, true) ---@type table
    what_get.nr = resolve_list_nr(src_win, what_get.nr)

    ---@type table
    local what_ret = src_win and fn.getloclist(src_win, what_get) or fn.getqflist(what_get)
    return what_ret
end

---@param src_win integer|nil
---@param stack qf-rancher.types.What[]
---@return boolean, string|nil, string|nil
function M._set_stack(src_win, stack)
    local ru = require("qf-rancher.util")

    if src_win then
        local ok, msg, hl = ru._is_valid_loclist_win(src_win)
        if not ok then
            return ok, msg, hl
        end

        fn.setloclist(src_win, {}, "f")
        for _, what in ipairs(stack) do
            fn.setloclist(src_win, {}, " ", what)
        end
    else
        fn.setqflist({}, "f")
        for _, what in ipairs(stack) do
            fn.setqflist({}, " ", what)
        end
    end

    return true, nil, nil
end

---@param what_ret table
---@return qf-rancher.types.What
function M._what_ret_to_set(what_ret)
    local what_set = {} ---@type qf-rancher.types.What

    what_set.context = type(what_ret.context) == "table" and what_ret.context or nil
    what_set.idx = type(what_ret.idx) == "number" and what_ret.idx or nil
    what_set.items = type(what_ret.items) == "table" and what_ret.items or {}

    local qftf = what_ret.quickfixtextfunc
    local is_qftf_func = type(qftf) == "function"
    local is_qftf_str = type(qftf) == "string" and #qftf > 0
    if is_qftf_func or is_qftf_str then
        what_set.quickfixtextfunc = qftf
    end

    local title = what_ret.title
    local is_title_str = type(what_ret.title) == "string" and #title > 0
    what_set.title = is_title_str and title or nil

    return what_set
end

---@param src_win integer
---@return qf-rancher.types.What[]
function M._get_stack(src_win)
    local stack = {} ---@type table
    local max_nr = M._get_list(src_win, { nr = "$" }).nr ---@type integer
    if max_nr < 1 then
        return stack
    end

    if src_win then
        for i = 1, max_nr do
            local what_ret = fn.getloclist(src_win, { nr = i, all = true }) ---@type table
            local what_set = M._what_ret_to_set(what_ret)
            what_set.nr = i
            stack[#stack + 1] = what_set
        end
    else
        for i = 1, max_nr do
            local what_ret = fn.getqflist({ nr = i, all = true }) ---@type table
            local what_set = M._what_ret_to_set(what_ret)
            what_set.nr = i
            stack[#stack + 1] = what_set
        end
    end

    return stack
end

return M

-- MAYBE: Ideas for list manipulation:
-- - Insert new lists in the middle, shifting lists below down and out
-- - Swap lists
-- - Copy lists
-- - Consolidate lists (remove blank gaps)
-- - For the various ideas - v:count1 would be one list and the current list would be the other.
-- I think you would use current list as source and count as target, so that way you could do
-- something like 10<leader>q{copy hotkey} to copy the current list to the end of the stack
-- - Move between loclist and qflist
-- - Merge and de-dupe lists
--   - Particular issue: The underlying file data might have changed
--   - Another issue, would have to find a way to efficiently check the text portion of the item
--   I suppose you would just hash it right in the de-duping algorithm
--   - On the other hand, you could set it to trigger on the "a" action, so it would fit naturally
--   with the default behavior
-- Problem 1: Making these behaviors interface with the defaults
-- Problem 2: More keymaps/interfaces/complexity for unknown use cases
-- Relevant note: " " actually frees the lists after rather than clearing them, which makes some of
-- the ideas above more useful.
-- A simple/useful cmd/keymap I think would be like Qhygiene or something, where you could
-- consolidate lists to remove gaps, then do a " " write at the end with the last list to clear
-- everything afterwards. If all lists are empty, just run setlist("f")
-- A good behavior to have behind an opt (default on), would be if we see the last list is empty,
-- always use a " " set to trim it

-- FUTURE: If there's ever any type of quickfixchanged autocmd, add a g:var to automatically free
-- the stack if all lists have zero items
