local rt = Qfr_Defer_Require("qf-rancher.tools") ---@type QfrTools
local ru = Qfr_Defer_Require("qf-rancher.util") ---@type QfrUtil
local ry = Qfr_Defer_Require("qf-rancher.types") ---@type QfrTypes

local api = vim.api
local fn = vim.fn

-- TODO: I think this logic is correct, just double check as it's folded into refactor
--
---@param src_win integer|nil
---@param height? integer
---@return integer
local function resolve_height_for_list(src_win, height)
    ry._validate_win(src_win, true)
    ry._validate_uint(height, true)

    if height then
        return height
    end

    if not vim.g.qfr_auto_list_height then
        return QFR_MAX_HEIGHT
    end

    local size = rt._get_list(src_win, { nr = 0, size = 0 }).size ---@type integer
    return size == 0 and 1 or math.min(size, QFR_MAX_HEIGHT)
end

-- TODO: Deprecate
--
---@param opts QfrListOpenOpts
---@return nil
local function validate_and_clean_open_opts(opts)
    ry._validate_open_opts(opts)
    -- Let zero count fall back to default behavior
    if opts.height and opts.height < 1 then
        opts.height = nil
    end
end

-- TODO: Deprecate
--
---@param keep_win boolean
---@param cur_win integer
---@return boolean
local function open_cleanup(keep_win, cur_win)
    if keep_win then
        api.nvim_set_current_win(cur_win)
    end

    return true
end

-- TODO: This should be configurable behavior
--
---@param list_win integer
---@param cur_win integer
---@return integer|nil
local function get_alt_win(list_win, cur_win)
    ry._validate_win(list_win)
    ry._validate_win(cur_win)

    if list_win ~= cur_win then
        return nil
    end

    ---@type string
    local switchbuf = api.nvim_get_option_value("switchbuf", { scope = "global" })
    if not string.find(switchbuf, "uselast", 1, true) then
        return nil
    end

    -- TODO: Might need to be called in some kind of context
    local alt_winnr = fn.winnr("#") ---@type integer
    return fn.win_getid(alt_winnr)
end

---@mod Window Open, close, and resize list wins
---@tag qf-rancher-window
---@tag qfr-window
---@brief [[
---
---@brief ]]

--- @class QfrWins
local Window = {}

-- TODO: Deprecate
--
---@param list_win integer
---@param opts QfrListOpenOpts
---@return boolean
local function handle_open_list_win(list_win, opts)
    validate_and_clean_open_opts(opts)

    if opts.nop_if_open then
        return false
    end

    if opts.height or vim.g.qfr_auto_list_height then
        Window._resize_list_win(list_win, opts.height)
    end

    if not opts.keep_win then
        api.nvim_set_current_win(list_win)
    end

    return true
end

-- TODO: Deprecate
--
---@class QfrListOpenOpts
---@field height? integer Height the list should be set to
---@field keep_win? boolean Stay in current window when opening the list?
---@field nop_if_open? boolean Do not print messages or focus on the list win

-- TODO: Deprecate and make sure documentation mentions the valid options
-- MID: Outline this at some point. Unsure if modules should be split based on function or
-- data type
local valid_splits = { "aboveleft", "belowright", "topleft", "botright" } ---@type string[]
local function get_qfsplit()
    local g_split = vim.g.qfr_qfsplit
    return vim.tbl_contains(valid_splits, g_split) and g_split or "botright"
end

-- TODO:
-- - copen
-- - cclose
-- - ctoggle
-- - cwindow
-- - lopen
-- - lclose
-- - ltoggle
-- - lwindow
-- The exterior interface, window state checks, and window actions are three separate layers
-- Adds a bit of conceptual complexity, but saves complexity downstream because concerns are
-- separated, and then the behaviors can be grouped together into easily followed functions

-- TODO: Actually write the functions first before baking in the opt types
--
---@class qfr.window.OpenOpts
---@field height integer List height to open to
---@field keep_height boolean Keep current height for already open lists?
---@field keep_win boolean Stay in the win the cmd is executed from?
---@field silent boolean Suppress messages

-- And for location lists you would need to track distinctly if the list failed to open due to
-- already being open or because no list exists
-- How list list height is handled needs to be considered very carefully, since for now these
-- behaviors cannot be de-coupled

-- TODO: Do you outline this and return cur_win, tabpage, list_win?
--
function Window.open_qf(opts)
    local cur_win = api.nvim_get_current_win() ---@type integer
    local tabpage = api.nvim_win_get_tabpage(cur_win) ---@type integer
    local list_win = ru._find_qf_win({ tabpage }) ---@type integer|nil
    if list_win then
        -- TODO: would add stuff here
        return
    end

    Window.do_open_qf(cur_win, tabpage, opts)
end

-- TODO: Similar to above, do you outline the step?
--
function Window.close_qf()
    local cur_win = api.nvim_get_current_win() ---@type integer
    local tabpage = api.nvim_win_get_tabpage(cur_win) ---@type integer
    local list_win = ru._find_qf_win({ tabpage }) ---@type integer|nil
    if list_win then
        Window.do_close_qf(list_win, cur_win, tabpage)
        return
    end
end

-- TODO: Where are messages/results handled here? With the stack module, they were propagated up
-- because resize_after_stack_change was a common behavior. Here, we can either keep_win or
-- use the alt_win target. I'm less concerned about propagating up because we aren't doing
-- toggle resolution. Another reason propagated error handling works in the stack module is
-- because qf/ll logic cleanly combines in the stack module. Here I'm not sure it does.
-- I also, conceptually, want to avoid complexity with the depth of the logic because of the
-- checked_spk calls. Not strictly relevant now, but it just seems cleaner here to follow a
-- pure chain of responsibility for any particular behavior, though that is somewhat complicated
-- by the validity checks
-- An idea to experiment with - What if creating interfaces isn't pre-mature. Imagine if
-- get_current_win() didn't exist. You would have to get the current tabpage, then iterate though
-- the tabpage wins and use some indicator to find the current win. You would obviously, and
-- immediately, abstract this logic. More complicated - pwin_close or get_input
-- What are data abstractions vs. conceptual abstractions? Do conceptual abstractions
-- actually exist? Or are "conceptual abstractions" just collections of data abstractions?
function Window.do_close_qf(qf_win, cur_win, tabpage)
    local tabpages = api.nvim_list_tabpages() ---@type integer[]
    local tabpage_wins = api.nvim_tabpage_list_wins(tabpage) ---@type integer[]
    if #tabpages == 1 and #tabpage_wins == 1 then
        api.nvim_echo({ { "Cannot close the last window" } }, false, {})
        return false
    end

    local exit_win = get_alt_win(qf_win, cur_win) ---@type integer|nil
    ru._with_checked_spk(function()
        api.nvim_cmd({ cmd = "cclose" }, {})
    end)

    if exit_win and api.nvim_win_is_valid(exit_win) then
        api.nvim_set_current_win(exit_win)
    end
end

function Window.toggle_qf()
    local cur_win = api.nvim_get_current_win() ---@type integer
    local tabpage = api.nvim_win_get_tabpage(cur_win) ---@type integer
    local list_win = ru._find_qf_win({ tabpage }) ---@type integer|nil
    if list_win then
        Window.do_close_qf(list_win, cur_win, tabpage)
        return
    end

    Window.do_open_qf(cur_win, tabpage)
end

function Window.qwin(opts)
    local cur_win = api.nvim_get_current_win() ---@type integer
    local tabpage = api.nvim_win_get_tabpage(cur_win) ---@type integer
    local list_win = ru._find_qf_win({ tabpage }) ---@type integer|nil
    local cur_list = vim.fn.getqflist({ nr = 0, items = true }).items ---@type vim.quickfix.entry[]

    local has_win = type(list_win) == "number"
    local has_list = #cur_list > 0
    local open_items = has_win and has_list ---@type boolean
    local closed_noitems = not (has_win or has_list) ---@type boolean
    if open_items or closed_noitems then
        return
    end

    if (not has_win) and #cur_list > 0 then
        Window.do_open_qf(cur_win, tabpage, opts)
    end

    -- TODO: or do you just make this default case
    if has_win and #cur_list == 0 then
        Window.do_close_qf(list_win, cur_win, tabpage)
    end
end

function Window.do_open_qf(cur_win, tabpage, opts)
    local ll_wins = ru._find_ll_wins({ tabpages = { tabpage } }) ---@type integer[]
    for _, ll_win in ipairs(ll_wins) do
        ru._with_checked_spk(function()
            ru._pwin_close(ll_win, true)
        end)
    end

    local height = resolve_height_for_list(nil, opts.height) ---@type integer
    ru._with_checked_spk(function()
        ---@diagnostic disable: missing-fields
        api.nvim_cmd({ cmd = "copen", count = height, mods = { split = get_qfsplit() } }, {})
    end)

    if opts.keep_win then
        api.nvim_set_current_win(cur_win)
    end
end

---- If any location lists are open in the same tabpage, they will be
---  automatically closed before the qflist is opened
---- If the quickfix list is already open, it will be focused
---- If a height is provided, and "nop_if_open" is not true, the qflist will
---  be resized regardless of whether or not it is already open
---@param opts QfrListOpenOpts
---@return boolean
function Window.open_qflist(opts)
    validate_and_clean_open_opts(opts)

    local cur_win = api.nvim_get_current_win() ---@type integer
    local tabpage = api.nvim_win_get_tabpage(cur_win) ---@type integer
    local list_win = ru._find_qf_win({ tabpage }) ---@type integer|nil
    if list_win then
        return handle_open_list_win(list_win, opts)
    end

    local ll_wins = ru._find_ll_wins({ tabpages = { tabpage } }) ---@type integer[]
    for _, ll_win in ipairs(ll_wins) do
        ru._with_checked_spk(function()
            ru._pwin_close(ll_win, true)
        end)
    end

    local height = resolve_height_for_list(nil, opts.height) ---@type integer
    ru._with_checked_spk(function()
        ---@diagnostic disable: missing-fields
        api.nvim_cmd({ cmd = "copen", count = height, mods = { split = get_qfsplit() } }, {})
    end)

    return open_cleanup(opts.keep_win, cur_win)
end

-- MID: In reversal from previous idea - This function needs to be responsive to remote
-- context. If called from outside the src_win context, it will not open. Unsure if a hack would
-- then be needed to make the list focus, or what else is being disrupted under the hood though
-- LOW: I don't love tying the no loclist msg to nop_if_open, but it seems to work

---- If no location list is present for the source window, the function will
---  exit
---- If the quickfix list is open in the same tabpage, it will be closed
---  before the location list is opened
---- If the location list is already open, it will be focused
---- If a height is provided, and "nop_if_open" is not true, the location
---  list will be resized regardless of whether or not it is already open
---@param src_win integer Location list window context
---@param opts QfrListOpenOpts
---@return boolean
function Window.open_loclist(src_win, opts)
    validate_and_clean_open_opts(opts)

    local qf_id = fn.getloclist(src_win, { id = 0 }).id ---@type integer
    if qf_id == 0 then
        if not opts.nop_if_open then
            api.nvim_echo({ { "Window has no location list", "" } }, false, {})
        end

        return false
    end

    local tabpage = api.nvim_win_get_tabpage(src_win) ---@type integer
    local ll_win = ru._find_ll_win({ qf_id = qf_id, tabpages = { tabpage } }) ---@type integer|nil
    if ll_win then
        return handle_open_list_win(ll_win, opts)
    end

    local height = resolve_height_for_list(src_win, opts.height) ---@type integer
    local qf_win = ru._find_qf_win({ tabpage }) ---@type integer|nil
    if qf_win then
        ru._with_checked_spk(function()
            ru._pwin_close(qf_win, true)
        end)
    end

    ru._with_checked_spk(function()
        -- NOTE: Do not win call because Nvim will not properly jump to the opened win
        ---@diagnostic disable: missing-fields
        api.nvim_cmd({ cmd = "lopen", count = height }, {})
    end)

    return open_cleanup(opts.keep_win, src_win)
end

-- TODO: This should be Window.q_close since it's meant to be a cclose emulation
-- TODO: The alt_win behavior should be configurable. At minimum, behind a g:var. Even better,
-- could provide a callback opt for determining the win after. Or a callback in general
--
---- If switchbuf contains uselast, focus will be changed to the alternate
---  window if it is available
---@return boolean
function Window.close_qflist()
    local cur_win = api.nvim_get_current_win() ---@type integer
    local tabpage = api.nvim_win_get_tabpage(cur_win) ---@type integer
    local qf_win = ru._find_qf_win({ tabpage }) ---@type integer|nil
    if not qf_win then
        return false
    end

    local tabpages = api.nvim_list_tabpages() ---@type integer[]
    local tabpage_wins = api.nvim_tabpage_list_wins(tabpage) ---@type integer[]
    if #tabpages == 1 and #tabpage_wins == 1 then
        api.nvim_echo({ { "Cannot close the last window" } }, false, {})
        return false
    end

    local exit_win = get_alt_win(qf_win, cur_win) ---@type integer|nil
    ru._with_checked_spk(function()
        api.nvim_cmd({ cmd = "cclose" }, {})
    end)

    if exit_win and api.nvim_win_is_valid(exit_win) then
        api.nvim_set_current_win(exit_win)
    end

    return true
end

-- MID: Unsure exactly where this goes, but for Fugitive, I want an API out of here that I can
-- use to close all loclists in the current window, and not display a nag if there aren't any

----If switchbuf contains uselast, focus will be changed to the alternate
--- window if it is available
---- All location list windows sharing a |quickfix-ID| with the current
---  window context will also be closed
---@param src_win integer Location list window context
---@return boolean
function Window.close_loclist(src_win)
    ry._validate_win(src_win)

    local wintype = fn.win_gettype(src_win)
    local qf_id = fn.getloclist(src_win, { id = 0 }).id ---@type integer
    if qf_id == 0 and wintype ~= "loclist" then
        api.nvim_echo({ { "Window has no loclist", "" } }, false, {})
        return false
    end

    local tabpage = api.nvim_win_get_tabpage(src_win) ---@type integer
    local ll_wins = ru._find_ll_wins({ qf_id = qf_id, tabpages = { tabpage } }) ---@type integer[]
    if #ll_wins < 1 then
        return false
    end

    local tabpage_wins = api.nvim_tabpage_list_wins(tabpage) ---@type integer[]
    if #tabpage_wins == 1 then
        api.nvim_echo({ { "Cannot close the last window" } }, false, {})
        return false
    end

    tabpage_wins = vim.tbl_filter(function(win)
        return not vim.tbl_contains(ll_wins, win)
    end, tabpage_wins)

    local cur_win = api.nvim_get_current_win() ---@type integer
    ---@type integer|nil
    local exit_win = vim.tbl_contains(ll_wins, cur_win) and get_alt_win(cur_win, cur_win) or nil

    ru._with_checked_spk(function()
        api.nvim_win_call(src_win, function()
            api.nvim_cmd({ cmd = "lclose" }, {}) -- Fire QuickFixCmd event
        end)
    end)

    for _, ll_win in ipairs(ll_wins) do
        ru._with_checked_spk(function()
            if api.nvim_win_is_valid(ll_win) then
                ru._pwin_close(ll_win, true)
            end
        end)
    end

    if exit_win and api.nvim_win_is_valid(exit_win) then
        api.nvim_set_current_win(exit_win)
    end

    return true
end

---opts.nop_if_open will be automatically set to true
---@param opts QfrListOpenOpts
---@return nil
function Window.toggle_qflist(opts)
    local toggle_opts = vim.tbl_extend("force", opts, { nop_if_open = true })
    if not Window.open_qflist(toggle_opts) then
        Window.close_qflist()
    end
end

---opts.nop_if_open will be automatically set to true
---@param src_win integer
---@param opts QfrListOpenOpts
---@return nil
function Window.toggle_loclist(src_win, opts)
    ry._validate_win(src_win)

    local toggle_opts = vim.tbl_extend("force", opts, { nop_if_open = true })
    local opened = Window.open_loclist(src_win, toggle_opts)
    if not opened then
        Window.close_loclist(src_win)
    end
end

-- MID: Add a "max" or "maxheight" arg, or maybe use bang, to open to max height from the cmd

---Qopen cmd callback. Expects count = 0 in the user_command table
---@param cargs vim.api.keyset.create_user_command.command_args
---@return nil
function Window.open_qflist_cmd(cargs)
    local count = cargs.count > 0 and cargs.count or nil ---@type integer|nil
    Window.open_qflist({ height = count })
end

---Lopen cmd callback. Expects count = 0 in the user_command table
---@param cargs vim.api.keyset.create_user_command.command_args
---@return nil
function Window.open_loclist_cmd(cargs)
    local count = cargs.count > 0 and cargs.count or nil ---@type integer|nil
    local src_win = api.nvim_get_current_win()
    Window.open_loclist(src_win, { height = count })
end

---Qclose cmd callback
---@return nil
function Window.close_qflist_cmd()
    Window.close_qflist()
end

---Lclose cmd callback
---@return nil
function Window.close_loclist_cmd()
    Window.close_loclist(api.nvim_get_current_win())
end

---Qtoggle cmd callback. Expects count = 0 in the user_command table
---@param cargs vim.api.keyset.create_user_command.command_args
---@return nil
function Window.toggle_qflist_cmd(cargs)
    local count = cargs.count > 0 and cargs.count or nil ---@type integer|nil
    Window.toggle_qflist({ height = count })
end

---Ltoggle cmd callback. Expects count = 0 in the user_command table
---@param cargs vim.api.keyset.create_user_command.command_args
---@return nil
function Window.toggle_loclist_cmd(cargs)
    local count = cargs.count > 0 and cargs.count or nil ---@type integer|nil
    Window.toggle_loclist(vim.api.nvim_get_current_win(), { height = count })
end

---@export Window

-- MID: The opts table should the optional

---@param src_win? integer
---@param opts QfrListOpenOpts
---@return boolean
function Window._open_list(src_win, opts)
    ry._validate_win(src_win, true)
    -- NOTE: Because these functions return booleans, cannot use the Lua ternary
    if src_win then
        return Window.open_loclist(src_win, opts)
    else
        return Window.open_qflist(opts)
    end
end

---@param src_win? integer
---@return nil
function Window._close_list(src_win)
    ry._validate_win(src_win, true)

    if src_win then
        Window.close_loclist(src_win)
    else
        Window.close_qflist()
    end
end

---@param list_win integer
---@param height? integer
---@return nil
function Window._resize_list_win(list_win, height)
    ry._validate_list_win(list_win)
    vim.validate("height", height, "number", true)

    local list_wintype = fn.win_gettype(list_win)
    local is_loclist = list_wintype == "loclist" ---@type boolean
    local is_qflist = list_wintype == "quickfix" ---@type boolean
    if not (is_loclist or is_qflist) then
        return
    end

    local old_height = api.nvim_win_get_height(list_win) ---@type integer
    local src_win = is_loclist and list_win or nil ---@type integer|nil
    local new_height = resolve_height_for_list(src_win, height) ---@type integer
    if old_height == new_height then
        return
    end

    ru._with_checked_spk(function()
        api.nvim_win_set_height(list_win, new_height)
    end)
end

-- MID: For any bulk operation that resizes, the views should be saved per-tabpage rather than
-- per-win for performance. On the other hand, this is really just an argument for temporarily
-- setting splitkeep

---@param tabpages? integer[]
---@return nil
function Window._close_qflists(tabpages)
    local wins = ru._find_qf_wins(tabpages)
    for _, win in ipairs(wins) do
        ru._with_checked_spk(function()
            ru._pwin_close(win, true)
        end)
    end
end

---@param opts qfr.util.FindLoclistWinOpts
---@return nil
function Window._close_loclists(opts)
    local wins = ru._find_ll_wins(opts)
    for _, win in ipairs(wins) do
        ru._with_checked_spk(function()
            ru._pwin_close(win, true)
        end)
    end
end

---@param tabpages? integer[]
---@return nil
function Window._resize_qflists(tabpages)
    local wins = ru._find_qf_wins(tabpages)
    for _, win in ipairs(wins) do
        Window._resize_list_win(win, nil)
    end
end

---@param opts qfr.util.FindLoclistWinOpts
---@return nil
function Window._resize_loclists(opts)
    local wins = ru._find_ll_wins(opts)
    for _, win in ipairs(wins) do
        Window._resize_list_win(win, nil)
    end
end

---@param src_win integer|nil
---@param tabpages integer[]
---@return nil
function Window._resize_lists(src_win, tabpages)
    if src_win then
        Window._resize_loclists({ src_win = src_win, tabpages = tabpages })
    else
        Window._resize_qflists(tabpages)
    end
end

return Window

-- LOW: Make get_list_height work without nowrap
