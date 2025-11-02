local rt = Qfr_Defer_Require("qf-rancher.tools") ---@type QfrTools
local ru = Qfr_Defer_Require("qf-rancher.util") ---@type QfrUtil
local ry = Qfr_Defer_Require("qf-rancher.types") ---@type QfrTypes

local api = vim.api
local fn = vim.fn

---@mod Window Open, close, and resize list wins
---@tag qf-rancher-window
---@tag qfr-window
---@brief [[
---
---@brief ]]

--- @class QfrWins
local Window = {}

-- ============
-- == LOCALS ==
-- ============

---@param views vim.fn.winsaveview.ret[]
---@return nil
local function restore_views(views)
    for win, view in pairs(views) do
        if not api.nvim_win_is_valid(win) then return end

        api.nvim_win_call(win, function()
            if fn.line("w0") ~= view.topline then fn.winrestview(view) end
        end)
    end
end

---@param wins integer[]
---@return vim.fn.winsaveview.ret[]
local function get_views(wins)
    local views = {} ---@type vim.fn.winsaveview.ret[]
    if not ru._get_g_var("qfr_save_views") then return views end

    ---@type string
    local splitkeep = api.nvim_get_option_value("splitkeep", { scope = "global" })
    if splitkeep == "screen" or splitkeep == "topline" then return views end

    for _, win in pairs(wins) do
        if not views[win] then
            local wintype = fn.win_gettype(win)
            if wintype == "" or wintype == "loclist" or wintype == "quickfix" then
                views[win] = api.nvim_win_call(win, fn.winsaveview)
            end
        end
    end

    return views
end

---@param src_win integer|nil
---@param height? integer
---@return integer
local function resolve_height_for_list(src_win, height)
    ry._validate_win(src_win, true)
    vim.validate("height", height, "number", true)

    if height then return height end

    if not ru._get_g_var("qfr_auto_list_height") then return QFR_MAX_HEIGHT end

    local size = rt._get_list(src_win, { nr = 0, size = 0 }).size ---@type integer
    if not size then return QFR_MAX_HEIGHT end
    size = math.max(size, 1)
    size = math.min(size, QFR_MAX_HEIGHT)

    return size
end

---@param opts QfrListOpenOpts
---@return nil
local function validate_and_clean_open_opts(opts)
    ry._validate_open_opts(opts)
    -- Let zero count fall back to default behavior
    if opts.height and opts.height < 1 then opts.height = nil end
end

-- MID: It would be useful when handling loclist orphans if the loclist open function returned
-- the loclist number after opening. This should be possible since lopen jumps to the list by
-- default

---@param list_win integer
---@param opts QfrListOpenOpts
---@return boolean
local function handle_open_list_win(list_win, opts)
    validate_and_clean_open_opts(opts)

    if opts.nop_if_open then return false end

    if opts.height or ru._get_g_var("qfr_auto_list_height") then
        Window._resize_list_win(list_win, opts.height)
    end

    if not opts.keep_win then api.nvim_set_current_win(list_win) end

    return true
end

---@param views vim.fn.winsaveview.ret[]
---@param keep_win boolean
---@param cur_win integer
---@return boolean
local function open_cleanup(views, keep_win, cur_win)
    restore_views(views)
    if keep_win then api.nvim_set_current_win(cur_win) end
    return true
end

---@param list_win integer
---@param cur_win integer
---@return integer|nil
local function get_alt_win(list_win, cur_win)
    ry._validate_win(list_win)
    ry._validate_win(cur_win)

    if list_win ~= cur_win then return nil end
    ---@type string
    local switchbuf = api.nvim_get_option_value("switchbuf", { scope = "global" })
    local uselast = string.find(switchbuf, "uselast", 1, true) ---@type integer|nil
    if not uselast then return nil end

    local alt_winnr = fn.winnr("#") ---@type integer
    return fn.win_getid(alt_winnr)
end

-- ================
-- == PUBLIC API ==
-- ================

---@class QfrListOpenOpts
---@field height? integer Height the list should be set to
---@field keep_win? boolean Stay in current window when opening the list?
---@field nop_if_open? boolean Do not print messages or focus on the list win

-- MID: Outline this at some point. Unsure if modules should be split based on function or
-- data type
local valid_splits = { "aboveleft", "belowright", "topleft", "botright" } ---@type string[]
local function get_qfsplit()
    local g_split = ru._get_g_var("qfr_qfsplit")
    return vim.tbl_contains(valid_splits, g_split) and g_split or "botright"
end

-- MID: "get_filtered_tabpage_wins" might be a useful util function

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
    local list_win = ru._get_qf_win({ tabpage = tabpage }) ---@type integer|nil

    if list_win then return handle_open_list_win(list_win, opts) end

    local ll_wins = ru._get_all_loclist_wins({ tabpage = tabpage }) ---@type integer[]
    local tabpage_wins = api.nvim_tabpage_list_wins(tabpage) ---@type integer[]
    tabpage_wins = vim.tbl_filter(function(win)
        return not vim.tbl_contains(ll_wins, win)
    end, tabpage_wins)

    local views = get_views(tabpage_wins) ---@type vim.fn.winsaveview.ret[]
    for _, ll_win in ipairs(ll_wins) do
        ru._pclose_and_rm(ll_win, true, true)
    end

    local height = resolve_height_for_list(nil, opts.height)
    ---@diagnostic disable: missing-fields
    api.nvim_cmd({ cmd = "copen", count = height, mods = { split = get_qfsplit() } }, {})
    return open_cleanup(views, opts.keep_win, cur_win)
end

-- MID: Applies to close_loclist as well - Might want to drop src_win as a param. It muddies the
-- context between what src_win the function is called for and the user's current win
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
    local ll_win = ru._get_loclist_win_by_qf_id(qf_id, { tabpage = tabpage }) ---@type integer|nil
    if ll_win then return handle_open_list_win(ll_win, opts) end

    local tabpage_wins = api.nvim_tabpage_list_wins(tabpage) ---@type integer[]
    local qf_win = ru._get_qf_win({ tabpage = tabpage }) ---@type integer|nil
    if qf_win then
        tabpage_wins = vim.tbl_filter(function(win)
            return win ~= qf_win
        end, tabpage_wins)
    end

    local views = get_views(tabpage_wins) ---@type vim.fn.winsaveview.ret[]
    local height = resolve_height_for_list(src_win, opts.height) ---@type integer
    if qf_win then ru._pclose_and_rm(qf_win, true, true) end

    -- NOTE: Do not win call because Nvim will not properly jump to the opened win
    ---@diagnostic disable: missing-fields
    api.nvim_cmd({ cmd = "lopen", count = height }, {})
    return open_cleanup(views, opts.keep_win, src_win)
end

---- If switchbuf contains uselast, focus will be changed to the alternate
---  window if it is available
---@return boolean
function Window.close_qflist()
    local cur_win = api.nvim_get_current_win() ---@type integer
    local tabpage = api.nvim_win_get_tabpage(cur_win) ---@type integer

    local qf_win = ru._get_qf_win({ tabpage = tabpage }) ---@type integer|nil
    if not qf_win then return false end

    local tabpage_wins = api.nvim_tabpage_list_wins(tabpage) ---@type integer[]
    if #tabpage_wins == 1 then
        api.nvim_echo({ { "Cannot close the last window" } }, false, {})
        return false
    end

    tabpage_wins = vim.tbl_filter(function(win)
        return win ~= qf_win
    end, tabpage_wins)

    local exit_win = get_alt_win(qf_win, cur_win) ---@type integer|nil
    local views = get_views(tabpage_wins) ---@type vim.fn.winsaveview.ret[]

    api.nvim_cmd({ cmd = "cclose" }, {})
    restore_views(views)
    if exit_win and api.nvim_win_is_valid(exit_win) then api.nvim_set_current_win(exit_win) end
    return true
end

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
    local ll_wins = ru._get_ll_wins_by_qf_id(qf_id, { tabpage = tabpage }) ---@type integer[]
    if #ll_wins < 1 then return false end

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

    local views = get_views(tabpage_wins) ---@type vim.fn.winsaveview.ret[]
    api.nvim_win_call(src_win, function()
        api.nvim_cmd({ cmd = "lclose" }, {}) -- Fire QuickFixCmd event
    end)

    for _, ll_win in ipairs(ll_wins) do
        ru._pclose_and_rm(ll_win, true, true) -- Will skip lclosed window
    end

    restore_views(views)
    if exit_win and api.nvim_win_is_valid(exit_win) then api.nvim_set_current_win(exit_win) end
    return true
end

---opts.nop_if_open will be automatically set to true
---@param opts QfrListOpenOpts
---@return nil
function Window.toggle_qflist(opts)
    local toggle_opts = vim.tbl_extend("force", opts, { nop_if_open = true })
    if not Window.open_qflist(toggle_opts) then Window.close_qflist() end
end

---opts.nop_if_open will be automatically set to true
---@param src_win integer
---@param opts QfrListOpenOpts
---@return nil
function Window.toggle_loclist(src_win, opts)
    ry._validate_win(src_win)

    local toggle_opts = vim.tbl_extend("force", opts, { nop_if_open = true })
    local opened = Window.open_loclist(src_win, toggle_opts)
    if not opened then Window.close_loclist(src_win) end
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

-- =================
-- == UNSUPPORTED ==
-- =================

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

---@param win integer
---@return boolean
function Window._close_win_save_views(win)
    ry._validate_win(win, false)

    local tabpage = api.nvim_win_get_tabpage(win) ---@type integer
    local tabpage_wins = api.nvim_tabpage_list_wins(tabpage) ---@type integer[]
    tabpage_wins = vim.tbl_filter(function(t_win)
        return t_win ~= win
    end, tabpage_wins)

    local views = get_views(tabpage_wins) ---@type vim.fn.winsaveview.ret[]
    local result = ru._pclose_and_rm(win, true, true)
    if result >= 0 then restore_views(views) end

    return true
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
    if not (is_loclist or is_qflist) then return end

    local old_height = api.nvim_win_get_height(list_win) ---@type integer
    local src_win = is_loclist and list_win or nil ---@type integer|nil
    local new_height = resolve_height_for_list(src_win, height) ---@type integer
    if old_height == new_height then return end

    local tabpage = api.nvim_win_get_tabpage(list_win) ---@type integer
    local tabpage_wins = api.nvim_tabpage_list_wins(tabpage) ---@type integer[]
    tabpage_wins = vim.tbl_filter(function(win)
        return win ~= list_win
    end, tabpage_wins)

    local views = get_views(tabpage_wins) ---@type vim.fn.winsaveview.ret[]
    api.nvim_win_set_height(list_win, new_height)
    restore_views(views)
end

-- LOW: For these operations, and anything similar in utils, the closing/saving should be done on
-- a per tabpage basis rather than a per listwin basis, so that for tabs where multiple
-- location lists are opened, the views can be saved and restored once. Low priority because the
-- most likely case of this issue occuring, opening a QfList, already works this way

---@param opts QfrTabpageOpts
---@return nil
function Window._close_qfwins(opts)
    ry._validate_tabpage_opts(opts)

    local qfwins = ru._get_qf_wins(opts) ---@type integer[]
    for _, list in ipairs(qfwins) do
        Window._close_win_save_views(list)
    end
end

---@param opts QfrTabpageOpts
---@return nil
function Window._resize_qfwins(opts)
    ry._validate_tabpage_opts(opts)

    local qfwins = ru._get_qf_wins(opts) ---@type integer[]
    for _, list in ipairs(qfwins) do
        Window._resize_list_win(list, nil)
    end
end

---@param src_win integer
---@param opts QfrTabpageOpts
---@return nil
function Window._resize_loclists_by_win(src_win, opts)
    ry._validate_win(src_win, false)
    ry._validate_tabpage_opts(opts)

    ---@type integer[]
    local loclists = ru._get_loclist_wins_by_win(src_win, opts)
    for _, list_win in ipairs(loclists) do
        Window._resize_list_win(list_win, nil)
    end
end

---@param src_win integer|nil
---@param opts QfrTabpageOpts
---@return nil
function Window._resize_lists_by_win(src_win, opts)
    ry._validate_win(src_win, true)
    if src_win then
        Window._resize_loclists_by_win(src_win, opts)
    else
        Window._resize_qfwins(opts)
    end
end

---@param qf_id integer
---@param opts QfrTabpageOpts
---@return nil
function Window._close_loclists_by_qf_id(qf_id, opts)
    ry._validate_uint(qf_id)
    ry._validate_tabpage_opts(opts)

    ---@type integer[]
    local llists = ru._get_ll_wins_by_qf_id(qf_id, opts)
    for _, list in ipairs(llists) do
        Window._close_win_save_views(list)
    end
end

return Window

-- TODO: Tests

-- MID: Implement a feature where, if you open list to a blank one, do a wrapping search forward or
--     backward for a list with items
-- - Or less obstrusively, showing history on blank lists or a statusline component

-- LOW: Make get_list_height work without nowrap
-- LOW: Make a Neovim tools repo that has the pwin close function
