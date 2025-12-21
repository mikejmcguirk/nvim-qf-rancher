local ry = Qfr_Defer_Require("qf-rancher.types") ---@type qf-rancher.Types
local ru = Qfr_Defer_Require("qf-rancher.util") ---@type qf-rancher.Util

-- local api = vim.api
local fn = vim.fn

---@class qf-rancher.Tools
local M = {}

---@param src_win integer|nil
---@param title string
---@return integer|nil
function M._find_list_with_title(src_win, title)
    ry._validate_win(src_win, true)
    vim.validate("title", title, "string")

    local max_nr = M._get_list(src_win, { nr = "$" }).nr ---@type integer
    for i = max_nr, 1, -1 do
        if M._get_list(src_win, { nr = i, title = 0 }).title == title then
            return i
        end
    end

    return nil
end

---@param src_win integer|nil
---@param nr integer|"$"|nil
---@return integer|"$"
local function resolve_list_nr(src_win, nr)
    ry._validate_win(src_win, true)
    ry._validate_list_nr(nr, true)

    if not nr then
        return 0
    end

    if nr == 0 or type(nr) == "string" then
        return nr
    end

    local max_nr = M._get_list(src_win, { nr = "$" }).nr ---@type integer
    ---@diagnostic disable-next-line: param-type-mismatch, return-type-mismatch
    return math.min(nr, max_nr)
end

---@param src_win integer|nil
---@param nr integer|"$"
---@return integer
local function get_result(src_win, nr)
    ry._validate_win(src_win, true)
    ry._validate_list_nr(nr)

    if nr == 0 then
        return M._get_list(src_win, { nr = 0 }).nr
    end

    local max_nr = M._get_list(src_win, { nr = "$" }).nr
    if nr == "$" then
        return max_nr
    end

    assert(type(nr) == "number")
    return math.min(nr, max_nr)
end

---@param src_win integer|nil
---@param action qf-rancher.types.Action
---@param what qf-rancher.What
---@return integer
function M._set_list(src_win, action, what)
    ry._validate_win(src_win, true)
    ry._validate_action(action)
    ry._validate_what(what)

    local what_set = vim.deepcopy(what, true) ---@type qf-rancher.What
    what_set.nr = resolve_list_nr(src_win, what_set.nr)
    local idx = what_set.idx or 1

    if what_set.items or what_set.lines then
        local items_len = what_set.items and #what_set.items or 0
        local lines_len = what_set.lines and #what_set.lines or 0
        local new_len = items_len + lines_len
        what_set.idx = new_len > 0 and math.min(idx, new_len) or nil
    else
        local cur_size = M._get_list(src_win, { nr = what_set.nr, size = 0 }).size ---@type integer
        what_set.idx = math.min(idx, cur_size)
    end

    ---@type integer
    local result = src_win and fn.setloclist(src_win, {}, action, what_set)
        or fn.setqflist({}, action, what_set)

    return result == -1 and result or get_result(src_win, what_set.nr)
end

---@param src_win integer|nil
---@return integer
function M._add_blank_list(src_win)
    ---@type integer
    local result = src_win and fn.setloclist(src_win, {}, " ") or fn.setqflist({}, " ")
    -- TODO: This needs to get the proper list nr
    return result
end

---@param src_win integer|nil
---@param list_nr integer|"$"|nil
---@return integer
function M._clear_list(src_win, list_nr)
    local nr = resolve_list_nr(src_win, list_nr) ---@type integer|"$"

    ---@type qf-rancher.What
    local what = { nr = nr, context = {}, items = {}, quickfixtextfunc = "", title = "" }
    local result = src_win and fn.setloclist(src_win, {}, "r", what) or fn.setqflist({}, "r", what)
    return result == -1 and result or get_result(src_win, nr)
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
---@param stack qf-rancher.What[]
---@return nil
function M._set_stack(src_win, stack)
    if src_win and not ru._is_valid_loclist_win(src_win) then
        return
    end

    M._set_list(src_win, "f", {})
    for _, what in ipairs(stack) do
        M._set_list(src_win, " ", what)
    end
end

---@param what_ret table
---@return table
function M._what_ret_to_set(what_ret)
    local what_set = {} ---@type qf-rancher.What

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
---@return qf-rancher.What[]
function M._get_stack(src_win)
    local stack = {} ---@type table
    local max_nr = M._get_list(src_win, { nr = "$" }).nr ---@type integer
    if max_nr < 1 then
        return stack
    end

    for i = 1, max_nr do
        local what_ret = M._get_list(src_win, { nr = i, all = true }) ---@type table
        local what_set = M._what_ret_to_set(what_ret) ---@type qf-rancher.What
        what_set.nr = i
        stack[#stack + 1] = what_set
    end

    return stack
end

return M

-- LOW: It would be cool to have a free_stack_if_nolist g:var that automatically frees the stack if
-- all lists are empty. But I don't know what you tie it to. QuickfixCmdPost? Individual Rancher
-- functions? I feel like it would be inconsistent.

-- MAYBE: Ideas for list manipulation:
-- - Insert new lists in the middle, shifting lists below down and out
-- - Swap lists
-- - Copy lists
-- - Consolidate lists (remove blank gaps)
-- - Move between loclist and qflist
-- - Merge and de-dupe lists
--   - Particular issue: The underlying file data might have changed
--   - Another issue, would have to find a way to efficiently check the text portion of the item
--   I suppose you would just hash it right in the de-duping algorithm
--   - On the other hand, you could set it to trigger on the "a" action, so it would fit naturally
--   with the default behavior
-- Problem 1: Making these behaviors interface with the defaults
-- Problem 2: More keymaps/interfaces/complexity for unknown use cases
