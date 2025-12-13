local rt = Qfr_Defer_Require("qf-rancher.tools") ---@type QfrTools
local ru = Qfr_Defer_Require("qf-rancher.util") ---@type QfrUtil
local ry = Qfr_Defer_Require("qf-rancher.types") ---@type QfrTypes

local api = vim.api
local fn = vim.fn

---@param src_win integer|nil
---@param height? integer
---@return integer
local function resolve_height_for_list(src_win, height)
    -- No validation. Can be run in loops

    if height then
        return height
    end

    if not vim.g.qfr_auto_list_height then
        return QFR_MAX_HEIGHT
    end

    local size = rt._get_list(src_win, { nr = 0, size = 0 }).size ---@type integer
    return size == 0 and 1 or math.min(size, QFR_MAX_HEIGHT)
end

---@param list_win integer
---@param height? integer
---@return nil
local function resize_list_win(list_win, height)
    -- No validation. Can be called in loops

    local list_wintype = fn.win_gettype(list_win)
    local is_loclist = list_wintype == "loclist" ---@type boolean

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

---@param opts? qfr.util.FindLoclistWinOpts
---@return nil
local function close_loclists(opts)
    local wins = ru._find_ll_wins(opts)
    for _, win in ipairs(wins) do
        ru._with_checked_spk(function()
            ru._pwin_close(win, true)
        end)
    end
end

-- TODO: Remove the idea of scoping copen/lopen. The way to get there is too hacky and has
-- too many weird effects that will, at some point, have some weird side effect I'm not
-- anticipating

---@param opts qfr.window.OpenOpts
---@return nil
local function resolve_open_qf_win_opts(opts)
    vim.validate("opts", opts, "table")

    ry._validate_uint(opts.height, true)
    -- TODO: This logic is correct inasmuch as nil and 0 copen produce different results. But is
    -- this the right place to resolve this? I guess it is...
    local valid_height = type(opts.height) == "number" and opts.height >= 1 ---@type boolean
    opts.height = valid_height and opts.height or nil

    vim.validate("opts.split", opts.split, "string", true)
    if type(opts.split) == "nil" then
        opts.split = "botright"
    end
end

-- TODO: Not sure what to do here
-- The API needs to be such that the user can re-implement cwindow
-- You *can* do this with open_qf_win, I guess. But it's lame because then
-- you're basically calling the function to re-pull context in order to do the business
-- YOu could say that the base cwindow can just be a no-op if open, but what if you want to
-- make your own customized cwindow?
-- A goofy idea is that you could have on-List be close but that doesn't make sense with
-- keep_height
-- passing list/tab context is awkward
-- I guess you publicize resize_list_win?, since that's the only thing the open handle
-- does. But then I'd have to think about it more as an interface

---@param opts qfr.window.OpenOpts
---@return nil
local function handle_open_qf_win(qf_win, tabpage, opts)
    if not opts.keep_height then
        resize_list_win(qf_win, opts.height)
    end

    if type(opts.on_list) == "function" then
        opts.on_list(qf_win, tabpage)
    end
end

---@param tabpage integer
---@param opts qfr.window.OpenOpts
---@return nil
local function do_open_qf(tabpage, opts)
    if vim.g.qfr_debug_assertions then
        ry._validate_uint(tabpage)
        vim.validate("opts", opts, "table")
        ry._validate_uint(opts.height, true)
        vim.validate("opts.split", opts.split, "string")
    end

    local height = resolve_height_for_list(nil, opts.height) ---@type integer
    if opts.close_loclists then
        close_loclists({ tabpages = { tabpage } })
    end

    ru._with_checked_spk(function()
        ---@diagnostic disable-next-line: missing-fields
        api.nvim_cmd({ cmd = "copen", count = height, mods = { split = opts.split } }, {})
    end)

    if type(opts.on_open) == "function" then
        opts.on_open(tabpage)
    end
end

---@param opts qfr.window.CloseOpts|qfr.window.ToggleOpts
---@return nil
local function resolve_close_qf_opts(opts)
    vim.validate("opts", opts, "table")

    if opts.qf_win then
        ry._validate_uint(opts.qf_win)

        local wintype = fn.win_gettype(opts.qf_win)
        if wintype == "quickfix" then
            opts.tabpage = api.nvim_win_get_tabpage(opts.qf_win)
            return
        end

        opts.qf_win = nil
    end

    if opts.tabpage then
        ry._validate_uint(opts.tabpage)
        opts.qf_win = ru._find_qf_win({ opts.tabpage })
    end

    vim.validate("opts.silent", opts.silent, "boolean", true)
    vim.validate("opts.use_alt_win", opts.use_alt_win, "boolean", true)
end

-- TODO: Document an actual data type for opts

---@param opts table
---@return integer|nil
local function resolve_alt_win(opts)
    if vim.g.qfr_debug_assertions then
        vim.validate("opts", opts, "table")
        ry._validate_uint(opts.list_win)
        ry._validate_uint(opts.tabpage)
        vim.validate("opts.use_alt_win", opts.use_alt_win, "boolean")
    end

    if not opts.use_alt_win then
        return nil
    end

    local cur_win = api.nvim_get_current_win() ---@type integer
    if opts.list_win ~= cur_win then
        return nil
    end

    local tabnr = api.nvim_tabpage_get_number(opts.tabpage) ---@type integer
    local winnr = fn.tabpagewinnr(tabnr, "#") ---@type integer
    return winnr
end

---@return boolean, string|nil, string|nil
local function do_close_qf_win(opts)
    local alt_win = resolve_alt_win(opts) ---@type integer|nil
    local ok, err, hl = ru._with_checked_spk(function()
        ru._pwin_close(opts.qf_win, true)
    end)

    if not ok then
        return ok, err, hl
    end

    if alt_win and alt_win ~= 0 and api.nvim_win_is_valid(alt_win) then
        api.nvim_set_current_win(alt_win)
    end

    return true, nil, nil
end

---@mod Window Open, close, and resize list wins
---@tag qf-rancher-window
---@tag qfr-window
---@brief [[
---
---@brief ]]

--- @class qfr.Window
local Window = {}

-- keep win situations
-- already open > keep win
-- already open > focus list
-- opening > keep win
-- opening > focus list
-- I think callbacks have to be the move here. making keep_win do everything it's
-- supposed to do is contrived

-- TODO: Add typing to the callbacks

---@class qfr.window.OpenOpts
---@field close_loclists? boolean On open, close loclists in the same tab
---@field height? integer List height to open to
---@field keep_height? boolean Keep current height for already open lists
---@field on_list? function Callback to run if the list is open
---@field on_open? function Callback to run on list open
---@field split? ''|'botright'|'topleft'|'belowright'|'aboveleft'

---@param opts? qfr.window.OpenOpts
---@return nil
function Window.open_qf_win(opts)
    opts = opts or {}
    resolve_open_qf_win_opts(opts)

    local tabpage = api.nvim_get_current_tabpage() ---@type integer
    local qf_win = ru._find_qf_win({ tabpages = { tabpage } })
    if qf_win then
        handle_open_qf_win(qf_win, tabpage, opts)
        return
    end

    do_open_qf(tabpage, opts)
end

---@class qfr.window.CloseOpts
---@field qf_win? integer Qf win to close (overrides tabpage opt)
---@field silent? boolean Suppress messages
---@field tabpage? integer Tabpage to close a qf win in
---@field use_alt_win? boolean Go to the alternate window after closing?

---@param opts qfr.window.CloseOpts
---@return nil
function Window.close_qf_win(opts)
    opts = opts or {}
    resolve_close_qf_opts(opts)

    if not opts.qf_win then
        return
    end

    ---@type boolean, string|nil, string|nil
    local ok, err, hl = do_close_qf_win(opts)
    if not ok then
        ru._echo(opts.silent, err, hl)
    end
end

--TODO: document what opts are sent to the sub functions. Wait to see if this, perhaps, can be
--merged with the loclist one.

---@return nil
function Window.q_toggle()
    local tabpage = api.nvim_get_current_tabpage() ---@type integer
    local qf_win = ru._find_qf_win({ tabpage }) ---@type integer|nil
    if not qf_win then
        do_open_qf(tabpage, { close_loclists = true, split = "botright" })
        return
    end

    local ok, err, hl = do_close_qf_win({
        qf_win = qf_win,
        abpage = tabpage,
        use_alt_win = true,
    })

    if not ok then
        ru._echo(false, err, hl)
    end
end

-- closed and list > open
-- open and list > stay open
-- open and nolist > close
-- closed and nolist > noop

function Window.q_window(opts)
    local tabpage = api.nvim_get_current_tabpage() ---@type integer
    local list_win = ru._find_qf_win({ tabpage }) ---@type integer|nil
    local cur_items = fn.getqflist({ nr = 0, items = true }).items ---@type vim.quickfix.entry[]

    local has_win = type(list_win) == "number"
    local has_list = #cur_items > 0
    local open_items = has_win and has_list ---@type boolean
    local closed_noitems = not (has_win or has_list) ---@type boolean
    if open_items or closed_noitems then
        return
    end

    if (not has_win) and #cur_items > 0 then
        do_open_qf(opts)
    end

    -- TODO: or do you just make this default case
    if has_win and #cur_items == 0 then
        Window.do_close_qf_win(opts)
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

    local exit_win = resolve_alt_win(qf_win, cur_win) ---@type integer|nil
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
    local exit_win = vim.tbl_contains(ll_wins, cur_win) and resolve_alt_win(cur_win, cur_win)
        or nil

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

-- TODO: deprecate once removed from ftplugin

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
    resize_list_win(list_win, height)
end

-- MID: For any bulk operation that resizes, the views should be saved per-tabpage rather than
-- per-win for performance. On the other hand, this is really just an argument for temporarily
-- setting splitkeep

-- TODO: name to close qf wins

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

---@param opts? qfr.util.FindLoclistWinOpts
---@return nil
function Window._close_loclists(opts)
    close_loclists(opts)
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
