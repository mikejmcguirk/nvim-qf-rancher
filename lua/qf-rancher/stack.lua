local eo = Qfr_Defer_Require("qf-rancher.window") ---@type QfrWins
local et = Qfr_Defer_Require("qf-rancher.tools") ---@type QfrTools
local eu = Qfr_Defer_Require("qf-rancher.util") ---@type QfrUtil
local ey = Qfr_Defer_Require("qf-rancher.types") ---@type QfrTypes

local api = vim.api

---@mod Stack View and edit the list stack
---@tag qf-rancher-stack
---@tag qfr-stack
---@brief [[
---
---@brief ]]

--- @class QfrStack
local Stack = {}

-- ============
-- == LOCALS ==
-- ============

-- GENERAL --

---@param src_win integer|nil
---@return nil
local function resize_after_stack_change(src_win)
    if not eu._get_g_var("qfr_auto_list_height") then return end
    if src_win then
        local src_win_tabpage = api.nvim_win_get_tabpage(src_win) ---@type integer
        eo._resize_loclists_by_win(src_win, { tabpage = src_win_tabpage })
    else
        eo._resize_qfwins({ all_tabpages = true })
    end
end

-- CHANGE HISTORY --

---@param src_win integer|nil
---@param count integer
---@param wrapping function
---@return nil
local function change_history(src_win, count, wrapping)
    ey._validate_win(src_win, true)
    ey._validate_uint(count)
    vim.validate("arithmetic", wrapping, "callable")

    local stack_len = et._get_list(src_win, { nr = "$" }).nr ---@type integer
    if stack_len < 1 then
        api.nvim_echo({ { "No entries", "" } }, false, {})
        return
    end

    local cur_list_nr = et._get_list(src_win, { nr = 0 }).nr ---@type integer
    local count1 = eu._count_to_count1(count) ---@type integer
    local new_list_nr = wrapping(cur_list_nr, count1, 1, stack_len) ---@type integer

    local cmd = src_win and "lhistory" or "chistory" ---@type string
    api.nvim_cmd({ cmd = cmd, count = new_list_nr }, {})

    if cur_list_nr ~= new_list_nr then resize_after_stack_change(src_win) end
end

---@param count integer
---@param arithmetic function
---@return nil
local function l_change_history(win, count, arithmetic)
    eu._locwin_check(win, function()
        change_history(win, count, arithmetic)
    end)
end

-- ================
-- == PUBLIC API ==
-- ================

---@brief [[
---NOTE: If no list number is provided to next/previous commands, the default
---is to cycle by one list
---For commands that target a specific list, if no count is provided, the
---current list will be used
---NOTE: All navigation commands will re-size the list if it changes and
---g:qfr_auto_list_height is true
---@brief ]]

-- CHANGE HISTORY --

---@param count integer Wrapping count previous list to go to
---@return nil
function Stack.q_older(count)
    change_history(nil, count, eu._wrapping_sub)
end

---@param count integer Wrapping count next list to go to
---@return nil
function Stack.q_newer(count)
    change_history(nil, count, eu._wrapping_add)
end

---@param src_win integer Location list window context
---@param count integer Wrapping count previous list to go to
---@return nil
function Stack.l_older(src_win, count)
    l_change_history(src_win, count, eu._wrapping_sub)
end

---@param src_win integer Location list window context
---@param count integer Wrapping count next list to go to
---@return nil
function Stack.l_newer(src_win, count)
    l_change_history(src_win, count, eu._wrapping_add)
end

-- GET HISTORY --

---
---Whether to show the current list info or the entire stack
---(chistory/lhistory default) on 0 count
---@alias QfrHistoryDefaultOpt
---| 'cur_list'
---| 'show_stack'
---@class QfrHistoryOpts
---@field open_list? boolean Open the list after changing history
---@field default? QfrHistoryDefaultOpt
---@field keep_win? boolean If true, don't change window focus
---@field silent? boolean Suppress messages

---@param count integer List number to go to
---@param opts QfrHistoryOpts
---@return nil
function Stack.q_history(count, opts)
    Stack._get_history(nil, count, opts)
end

---@param src_win integer Location list window context
---@param opts QfrHistoryOpts
---@return nil
function Stack.l_history(src_win, count, opts)
    eu._locwin_check(src_win, function()
        Stack._get_history(src_win, count, opts)
    end)
end

-- DELETE --

---@param count integer List number to delete
---@return nil
function Stack.q_del(count)
    Stack._del(nil, count)
end

---@param src_win integer Location list window context
---@param count integer List number to delete
---@return nil
function Stack.l_del(src_win, count)
    eu._locwin_check(src_win, function()
        Stack._del(src_win, count)
    end)
end

-- DELETE ALL --

---@return nil
function Stack.q_del_all()
    et._set_list(nil, "f", {})
end

---@param src_win integer Location list window context
---@return nil
function Stack.l_del_all(src_win)
    et._set_list(src_win, "f", {})
end

-- CHANGE HISTORY --

---Qolder cmd callback. Expects count = 0 in the user_command table
---@param cargs vim.api.keyset.create_user_command.command_args
---@return nil
function Stack.q_older_cmd(cargs)
    Stack.q_older(cargs.count)
end

---Qnewer cmd callback. Expects count = 0 in the user_command table
---@param cargs vim.api.keyset.create_user_command.command_args
---@return nil
function Stack.q_newer_cmd(cargs)
    Stack.q_newer(cargs.count)
end

---Lolder cmd callback. Expects count = 0 in the user_command table
---@param cargs vim.api.keyset.create_user_command.command_args
---@return nil
function Stack.l_older_cmd(cargs)
    Stack.l_older(api.nvim_get_current_win(), cargs.count)
end

---Lnewer cmd callback. Expects count = 0 in the user_command table
---@param cargs vim.api.keyset.create_user_command.command_args
---@return nil
function Stack.l_newer_cmd(cargs)
    Stack.l_newer(api.nvim_get_current_win(), cargs.count)
end

-- GET HISTORY --

-- NOTE: In chistory/lhistory, a count of zero is treated the same as a count of 1. To show the
-- entire stack, the count must be nil. When using custom commands that take a count, a count of
-- zero is returned in cargs if none is provided. Counts of zero must be converted to nil

---Qhistory cmd callback. Expects count = 0 in the user_command table
---@param cargs vim.api.keyset.create_user_command.command_args
---@return nil
function Stack.q_history_cmd(cargs)
    Stack.q_history(cargs.count, { default = "show_stack" })
end

---Lhistory cmd callback. Expects count = 0 in the user_command table
---@param cargs vim.api.keyset.create_user_command.command_args
---@return nil
function Stack.l_history_cmd(cargs)
    Stack.l_history(api.nvim_get_current_win(), cargs.count, { default = "show_stack" })
end

-- DELETION --

---@brief [[
---NOTE: If "all" is provided, any count is overridden
---A count of zero deletes the current list
---@brief ]]

---Qdelete cmd callback. Expects count = 0 and nargs = "?" in the command
---table
---@param cargs vim.api.keyset.create_user_command.command_args
---@return nil
function Stack.q_delete_cmd(cargs)
    if cargs.args == "all" then
        Stack.q_del_all()
        return
    end

    Stack.q_del(cargs.count)
end

---Ldelete cmd callback. Expects count = 0 and nargs = "?" in the command
---table
---@param cargs vim.api.keyset.create_user_command.command_args
---@return nil
function Stack.l_delete_cmd(cargs)
    if cargs.args == "all" then
        Stack.l_del_all(api.nvim_get_current_win())
        return
    end

    Stack.l_del(api.nvim_get_current_win(), cargs.count)
end

---@export Stack

-- =================
-- == UNSUPPORTED ==
-- =================

---@param src_win integer|nil
---@param count integer
---@param opts QfrHistoryOpts
---@return nil
function Stack._get_history(src_win, count, opts)
    ey._validate_win(src_win, true)
    ey._validate_uint(count)
    ey._validate_history_opts(opts)

    local max_nr = et._get_list(src_win, { nr = "$" }).nr ---@type integer
    if max_nr < 1 then
        if not opts.silent then api.nvim_echo({ { "No entries", "" } }, false, {}) end
        return
    end

    local cur_nr = et._get_list(src_win, { nr = 0 }).nr ---@type integer
    local default = opts.default == "cur_list" and cur_nr or nil ---@type integer|nil
    local adj_count = count > 0 and math.min(count, max_nr) or default ---@type integer|nil

    local cmd = src_win and "lhistory" or "chistory" ---@type string
    ---@diagnostic disable-next-line: missing-fields
    api.nvim_cmd({ cmd = cmd, count = adj_count, mods = { silent = opts.silent } }, {})

    resize_after_stack_change(src_win)
    if opts.open_list then
        eo._open_list(src_win, { keep_win = opts.keep_win, nop_if_open = true })
    end
end

---@param src_win integer|nil Location list window context
---@param count integer List number to go to
---@return nil
function Stack._del(src_win, count)
    ey._validate_win(src_win, true)
    ey._validate_uint(count)

    local result = et._clear_list(src_win, count)
    if result == -1 then return end

    local cur_list_nr = et._get_list(src_win, { nr = 0 }).nr ---@type integer
    if result == cur_list_nr then resize_after_stack_change(src_win) end
end

return Stack

-- TODO: Testing

-- MID: Create a clean stack cmd/map that removes empty stacks and shifts down the remainders. You
-- should then be able to use the default setqflist " " behavior to delete the tail. You can then
-- make auto-consolidation a non-default option

-- LOW: Could help to save views in these commands so they don't just go to the current idx
-- Requires finding the qflist window though
