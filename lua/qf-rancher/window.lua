local ru = Qfr_Defer_Require("qf-rancher.util") ---@type qf-rancher.Util
local ry = Qfr_Defer_Require("qf-rancher.types") ---@type qf-rancher.Types

local api = vim.api
local fn = vim.fn

---@param src_win integer|nil
---@param height? integer
---@return integer
local function resolve_height_for_list(src_win, height)
    local valid_height = height and height > 0
    local adj_height = valid_height and height or nil
    if adj_height then
        return adj_height
    end

    if not vim.g.qfr_auto_list_height then
        return QF_RANCHER_MAX_HEIGHT
    end

    local rt = require("qf-rancher.tools")
    local size = rt._get_list(src_win, { nr = 0, size = 0 }).size ---@type integer
    return size == 0 and 1 or math.min(size, QF_RANCHER_MAX_HEIGHT)
end

---@param list_win integer
---@param height? integer
---@return nil
local function resize_list_win(list_win, height)
    local list_wintype = fn.win_gettype(list_win)
    local is_loclist = list_wintype == "loclist"

    local cur_height = api.nvim_win_get_height(list_win)
    local src_win = is_loclist and list_win or nil
    local new_height = resolve_height_for_list(src_win, height)
    if cur_height == new_height then
        return
    end

    ru._with_checked_spk(function()
        api.nvim_win_set_height(list_win, new_height)
    end)
end

---@param tabpages? integer[]
---@return nil
local function close_qf_wins(tabpages)
    local wins = ru._find_qf_wins(tabpages)
    for _, win in ipairs(wins) do
        ru._with_checked_spk(function()
            ru._pwin_close(win, true)
        end)
    end
end

---@param opts? qf-rancher.util.FindLoclistWinOpts
---@return nil
local function close_ll_wins(opts)
    local wins = ru._find_ll_wins(opts)
    for _, win in ipairs(wins) do
        ru._with_checked_spk(function()
            ru._pwin_close(win, true)
        end)
    end
end

---@param list_win integer
---@param tabpage integer
---@param opts qf-rancher.window.CloseOpts
---@return integer|nil
local function resolve_alt_win(list_win, tabpage, opts)
    if not opts.use_alt_win then
        return nil
    end

    local cur_win = api.nvim_get_current_win()
    if list_win ~= cur_win then
        return nil
    end

    local tabnr = api.nvim_tabpage_get_number(tabpage)
    local winnr = fn.tabpagewinnr(tabnr, "#")
    return winnr
end

---@param list_win integer
---@param tabpage integer
---@param opts qf-rancher.window.CloseOpts
---@return boolean, string|nil, string|nil
local function do_close_list_win(list_win, tabpage, opts)
    local alt_win = resolve_alt_win(list_win, tabpage, opts)
    local ok, err, hl = ru._with_checked_spk(function()
        ru._pwin_close(list_win, true)
    end)

    if not ok then
        return ok, err, hl
    end

    if alt_win and alt_win ~= 0 then
        local is_alt_win_valid = api.nvim_win_is_valid(alt_win)
        if is_alt_win_valid then
            api.nvim_set_current_win(alt_win)
        end
    end

    return true, nil, nil
end

---@param opts qf-rancher.window.CloseOpts
---@return nil
local function validate_close_opts(opts)
    vim.validate("opts", opts, "table")

    ry._validate_uint(opts.tabpage, true)
    vim.validate("opts.silent", opts.silent, "boolean", true)
    vim.validate("opts.use_alt_win", opts.use_alt_win, "boolean", true)
end

---@param tabpage integer
---@param opts qf-rancher.window.OpenOpts
---@return nil
local function do_open_qf(tabpage, opts)
    local height = resolve_height_for_list(nil, opts.height)
    if opts.close_others then
        close_ll_wins({ tabpages = { tabpage } })
    end

    local split = opts.split or "botright"
    ru._with_checked_spk(function()
        ---@diagnostic disable-next-line: missing-fields
        api.nvim_cmd({ cmd = "copen", count = height, mods = { split = split } }, {})
    end)

    if opts.on_open then
        opts.on_open(tabpage)
    end
end

---@param win integer
---@param tabpage integer
---@param opts qf-rancher.window.OpenOpts
---@return nil
local function do_open_ll(win, tabpage, opts)
    local height = resolve_height_for_list(win, opts.height)
    if opts.close_others then
        close_qf_wins({ tabpage })
    end

    ru._with_checked_spk(function()
        api.nvim_cmd({ cmd = "lopen", count = height }, {})
    end)

    if opts.on_open then
        opts.on_open(tabpage)
    end
end

---@param opts qf-rancher.window.OpenOpts
---@return nil
local function validate_open_list_win_opts(opts)
    vim.validate("opts", opts, "table")

    vim.validate("opts.close_others", opts.close_others, "boolean", true)
    ry._validate_uint(opts.height, true)
    vim.validate("opts.on_list", opts.on_list, "callable", true)
    vim.validate("opts.on_open", opts.on_open, "callable", true)
end

---@param opts qf-rancher.window.OpenOpts
---@return nil
local function validate_open_qf_win_opts(opts)
    validate_open_list_win_opts(opts)
    vim.validate("opts.split", opts.split, "string", true)
end

---@param opts qf-rancher.window.OpenOpts
---@return nil
local function validate_open_ll_win_opts(opts)
    validate_open_list_win_opts(opts)
    vim.validate("opts.silent", opts.silent, "boolean", true)
end

---@param items vim.quickfix.entry[]
---@param count integer|nil
---@param list_win integer
---@param tabpage integer
---@return boolean, string|nil, string|nil
local function do_window_cmd_has_list(items, count, list_win, tabpage)
    if #items > 0 then
        resize_list_win(list_win, count)
        local cur_win = api.nvim_get_current_win()
        if cur_win ~= list_win then
            api.nvim_set_current_win(list_win)
        end

        return true, nil, nil
    end

    local ok, err, hl = do_close_list_win(list_win, tabpage, { use_alt_win = true })
    return ok, err, hl
end

---@mod Window Open, close, and resize list wins
---@tag qf-rancher-window
---@tag qfr-window
---@brief [[
---
---@brief ]]

--- @class qf-rancher.Window
local Window = {}

-- MAYBE: Add a "before_open" callback

---@class qf-rancher.window.OpenOpts
---
---If opening the Quickfix list, close all location
---lists in the current tab. The reverse if opening the
---Location list.
---
---@field close_others? boolean
---
---@field height? integer List height to open to
---
---Callback to run if the list is already open
---
---@field on_list? fun(list_win: integer, tabpage: integer)
---
---Callback to run on list open
---
---@field on_open? fun(tabpage: integer)
---
---Suppress messages (only applies to location lists)
---
---@field silent? boolean
---
---Default "botright". Only applies to opening the
---quickfix list
---
---@field split? ''|'botright'|'topleft'|'belowright'|'aboveleft'

---@param opts? qf-rancher.window.OpenOpts See |qf-rancher.window.OpenOpts|
---
---If height is not provided, the list will be automatically
---sized if qfr_auto_list_height is true, otherwise set to the
---max height
---@return nil
function Window.open_qf_win(opts)
    opts = opts or {}
    validate_open_qf_win_opts(opts)

    local tabpage = api.nvim_get_current_tabpage()
    local qf_win = ru._find_qf_win({ tabpage })
    if qf_win then
        if opts.on_list then
            opts.on_list(qf_win, tabpage)
        end

        return
    end

    do_open_qf(tabpage, opts)
end

---@param opts? qf-rancher.window.OpenOpts See |qf-rancher.window.OpenOpts|
---
---If height is not provided, the list will be automatically
---sized if qfr_auto_list_height is true, otherwise set to
---the max height
---
---@return nil
function Window.open_ll_win(opts)
    opts = opts or {}
    validate_open_ll_win_opts(opts)

    local win = api.nvim_get_current_win()
    local qf_id = fn.getloclist(win, { id = 0 }).id ---@type integer
    if qf_id == 0 then
        ru._echo(opts.silent, QF_RANCHER_NO_LL, "")
        return
    end

    local tabpage = api.nvim_get_current_tabpage()
    local ll_win = ru._find_ll_win({ qf_id = qf_id, tabpages = { tabpage } })
    if ll_win then
        if opts.on_list then
            opts.on_list(ll_win, tabpage)
        end

        return
    end

    do_open_ll(win, tabpage, opts)
end

---@class qf-rancher.window.CloseOpts
---@field silent? boolean Suppress messages
---@field tabpage? integer Tabpage to close a list win in
---@field use_alt_win? boolean Go to the alternate window after closing

---@param opts? qf-rancher.window.CloseOpts See |qf-rancher.window.CloseOpts|
---
---If no tabpage opt is provided, the current tabpage will be
---used
---@return nil
function Window.close_qf_win(opts)
    opts = opts or {}
    validate_close_opts(opts)

    local tabpage = opts.tabpage or api.nvim_get_current_tabpage()
    local qf_win = ru._find_qf_win({ tabpage })
    if not qf_win then
        return
    end

    local ok, err, hl = do_close_list_win(qf_win, tabpage, opts)
    if not ok then
        ru._echo(opts.silent, err, hl)
    end
end

-- MID: It would be better if this function closed all loclist wins in the current tabpage, or
-- maybe all tabpages, based on qf_id.

---@param src_win integer
---@param opts? qf-rancher.window.CloseOpts
---
---See |qf-rancher.window.CloseOpts|
---
---If no tabpage opt is provided, the current tabpage will be
---used
---@return nil
function Window.close_ll_win(src_win, opts)
    opts = opts or {}
    validate_close_opts(opts)

    ry._validate_uint(src_win)
    local valid_src_win = api.nvim_win_is_valid(src_win)
    if not valid_src_win then
        ru._echo(opts.silent, "Source win " .. src_win .. " is invalid", "")
        return
    end

    local wintype = fn.win_gettype(src_win)
    local qf_id = fn.getloclist(src_win, { id = 0 }).id ---@type integer
    if qf_id == 0 and wintype ~= "loclist" then
        ru._echo(opts.silent, QF_RANCHER_NO_LL, "")
        return
    end

    local tabpage = opts.tabpage or api.nvim_get_current_tabpage()
    local ll_win = ru._find_ll_win({ qf_id = qf_id, tabpages = { tabpage } })
    if not ll_win then
        return
    end

    local ok, err, hl = do_close_list_win(ll_win, tabpage, opts)
    if not ok then
        ru._echo(opts.silent, err, hl)
    end
end

---
---Toggle the Quickfix list.
---
---On open, any open location lists in the current tabpage will be closed
---
---If the list is closed, and the alternate window can be found, it will be
---focused after closing.
---
---@param count integer|nil Height on open. nil will autosize
---@return nil
function Window.q_toggle(count)
    local tabpage = api.nvim_get_current_tabpage()
    local qf_win = ru._find_qf_win({ tabpage })

    if not qf_win then
        do_open_qf(tabpage, {
            close_others = true,
            height = count,
            split = "botright",
        })

        return
    end

    local ok, err, hl = do_close_list_win(qf_win, tabpage, { use_alt_win = true })
    if not ok then
        ru._echo(false, err, hl)
    end
end

-- MID: It would be better if this function checked wintype like close_ll does

---
---Toggle the Location list.
---
---On open, any open Quickfix lists in the current tabpage will be closed
---
---If the list is closed, and the alternate window can be found, it will be
---focused after closing.
---
---@param count integer|nil Height on open. nil will autosize
---@return nil
function Window.l_toggle(count)
    local cur_win = api.nvim_get_current_win()
    local qf_id = fn.getloclist(cur_win, { id = 0 }).id ---@type integer
    if qf_id == 0 then
        ru._echo(false, QF_RANCHER_NO_LL, "")
        return
    end

    local tabpage = api.nvim_get_current_tabpage()
    local ll_win = ru._find_ll_win({ qf_id = qf_id, tabpages = { tabpage } })
    if not ll_win then
        do_open_ll(cur_win, tabpage, {
            close_others = true,
            height = count,
        })

        return
    end

    local ok, err, hl = do_close_list_win(ll_win, tabpage, { use_alt_win = true })
    if not ok then
        ru._echo(false, err, hl)
    end
end

---
---Open/keep open the Quickfix window when there are recognized errors.
---Close/keep closed otherwise.
---
---On open, any open location lists in the current tabpage will be closed.
---
---If the list is already open and should stay open, it will be focused.
---
---If the list is already open and should stay open, it will be resized based
---on count and the value of qfr_auto_list_height.
---
---If the list should be closed, and the alternate window can be found, it
---will be focused after closing.
---
---@param count integer|nil Height on open. Nil autosizes
---@return nil
function Window.q_window(count)
    local tabpage = api.nvim_get_current_tabpage()
    local qf_win = ru._find_qf_win({ tabpage })
    local items = fn.getqflist({ nr = 0, items = true }).items ---@type vim.quickfix.entry[]

    if not qf_win then
        if #items == 0 then
            ru._echo(false, "Current quickfix list is empty", "")
            return
        end

        do_open_qf(tabpage, {
            close_others = true,
            height = count,
            split = "botright",
        })

        return
    end

    local ok, err, hl = do_window_cmd_has_list(items, count, qf_win, tabpage)
    if not ok then
        ru._echo(false, err, hl)
    end
end

---
---Open/keep open the Loclist window when there are recognized errors.
---Close/keep closed otherwise.
---
---On open, any open quickfix lists in the current tabpage will be closed.
---
---If the list is already open and should stay open, it will be focused.
---
---If the list is already open and should stay open, it will be resized based
---on count and the value of qfr_auto_list_height.
---
---If the list should be closed, and the alternate window can be found, it
---will be focused after closing.
---
---@param count integer|nil Height on open. Nil autosizes
---@return nil
function Window.l_window(count)
    local cur_win = api.nvim_get_current_win()
    local qf_id = fn.getloclist(cur_win, { id = 0 }).id ---@type integer
    if qf_id == 0 then
        ru._echo(false, QF_RANCHER_NO_LL, "")
        return
    end

    local tabpage = api.nvim_get_current_tabpage()
    local ll_win = ru._find_ll_win({ qf_id = qf_id, tabpages = { tabpage } })
    ---@type vim.quickfix.entry[]
    local items = fn.getloclist(cur_win, { nr = 0, items = true }).items

    if not ll_win then
        if #items == 0 then
            ru._echo(false, "Current location list is empty", "")
            return
        end

        do_open_ll(cur_win, tabpage, {
            close_others = true,
            height = count,
        })

        return
    end

    local ok, err, hl = do_window_cmd_has_list(items, count, ll_win, tabpage)
    if not ok then
        ru._echo(false, err, hl)
    end
end

---
---Resize a list window. Handles both Quickfix and Location lists.
---
---If g:qfr_always_keep_topline is true, the list will be resized with |'splitkeep'| set
---to "topline"
---
---@param list_win integer The list win to resize
---
---If nil, the new height will be based on the list contents
---@param height? integer
---@return nil
function Window.resize_list_win(list_win, height)
    ry._validate_win(list_win)
    ry._validate_uint(height, true)
    resize_list_win(list_win, height)
end

-- MID: For the open cmds, add a max or maxheight arg, or maybe use a bang, to always open to the
-- max height even when auto-resizing is enabled

---
---Qopen cmd callback. Expects count = 0 in the user_command table
---@param cargs vim.api.keyset.create_user_command.command_args
---@return nil
function Window.q_open_cmd(cargs)
    Window.open_qf_win({
        height = cargs.count,
        on_list = function(qf_win, _)
            resize_list_win(qf_win, vim.v.count)
            api.nvim_set_current_win(qf_win)
        end,
    })
end

---
---Lopen cmd callback. Expects count = 0 in the user_command table
---@param cargs vim.api.keyset.create_user_command.command_args
---@return nil
function Window.l_open_cmd(cargs)
    Window.open_ll_win({
        height = cargs.count,
        on_list = function(qf_win, _)
            resize_list_win(qf_win, vim.v.count)
            api.nvim_set_current_win(qf_win)
        end,
    })
end

---
---Qclose cmd callback
---@return nil
function Window.q_close_cmd()
    Window.close_qf_win({ use_alt_win = true })
end

---
---Lclose cmd callback
---@return nil
function Window.l_close_cmd()
    Window.close_ll_win(api.nvim_get_current_win())
end

---
---Qtoggle cmd callback. Expects count = 0 in the user_command table
---@param cargs vim.api.keyset.create_user_command.command_args
---@return nil
function Window.q_toggle_cmd(cargs)
    Window.q_toggle(cargs.count)
end

---
---Ltoggle cmd callback. Expects count = 0 in the user_command table
---@param cargs vim.api.keyset.create_user_command.command_args
---@return nil
function Window.l_toggle_cmd(cargs)
    Window.l_toggle(cargs.count)
end

---
---Qwindow cmd callback. Expects count = 0 in the user_command table
---@param cargs vim.api.keyset.create_user_command.command_args
---@return nil
function Window.q_window_cmd(cargs)
    Window.q_window(cargs.count)
end

---
---Lwindow cmd callback. Expects count = 0 in the user_command table
---@param cargs vim.api.keyset.create_user_command.command_args
---@return nil
function Window.l_window_cmd(cargs)
    Window.l_window(cargs.count)
end

---@export Window

---@param src_win? integer
---@param opts? qf-rancher.window.OpenOpts
---@return nil
function Window._open_list(src_win, opts)
    ry._validate_win(src_win, true)
    if src_win then
        Window.open_ll_win(opts)
    else
        Window.open_qf_win(opts)
    end
end

---@param tabpages? integer[]
---@return nil
function Window._close_qf_wins(tabpages)
    close_qf_wins(tabpages)
end

---@param opts? qf-rancher.util.FindLoclistWinOpts
---@return nil
function Window._close_ll_wins(opts)
    close_ll_wins(opts)
end

---@param tabpages? integer[]
---@return nil
function Window._resize_qf_wins(tabpages)
    local wins = ru._find_qf_wins(tabpages)
    for _, win in ipairs(wins) do
        resize_list_win(win, nil)
    end
end

---@param opts? qf-rancher.util.FindLoclistWinOpts
---@return nil
function Window._resize_ll_wins(opts)
    local wins = ru._find_ll_wins(opts)
    for _, win in ipairs(wins) do
        resize_list_win(win, nil)
    end
end

---@param list_win integer
---@param height? integer
---@return nil
function Window._resize_list_win(list_win, height)
    resize_list_win(list_win, height)
end

---@param src_win integer|nil
---@param tabpages? integer[]
---@return nil
function Window._resize_list_wins(src_win, tabpages)
    if src_win then
        Window._resize_ll_wins({ src_win = src_win, tabpages = tabpages })
    else
        Window._resize_qf_wins(tabpages)
    end
end

return Window

-- MID: For fugitive, I would like an API to close all loclists in the current tabpage, without
-- any cmdline feedback
-- MID: Break back the vars for use_alt_win, close_other_lists, and default_qf_split
-- - Because both behaviors apply to multiple functions, providing a variable to control them is
-- better than forcing the user to create multiple re-mappings
-- - Unlike the on_list/on_open behaviors, this should not create exploding combinatorial
-- complexity. They are pocketed fairly discretely
-- - If the opt is nil, the g:var should be used.

-- LOW: Make get_list_height work consistently without nowrap

-- FUTURE: Would be good to make qopen/copen responsive to tab/window context. But right now
-- doing that is hacky because you have to move the cursor around
