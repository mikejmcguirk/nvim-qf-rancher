local api = vim.api

local rt = Qfr_Defer_Require("qf-rancher.tools") ---@type QfrTools
local ru = Qfr_Defer_Require("qf-rancher.util") ---@type QfrUtil
local rw = Qfr_Defer_Require("qf-rancher.window") ---@type QfrWins
local ry = Qfr_Defer_Require("qf-rancher.types") ---@type QfrTypes

---@param opts? qfr.stack.GotoHistoryOpts
---@return nil
local function validate_history_opts(opts)
    if type(opts) == "nil" then
        return
    end

    vim.validate("opts", opts, "table")
    vim.validate("opts.silent", opts.silent, "boolean", true)
end

---Does not perform input cleansing or validation
---@param src_win integer|nil
---@param count integer|nil
---@param opts qfr.stack.GotoHistoryOpts
---@return integer
local function run_history(src_win, count, opts)
    local cmd = src_win and "lhistory" or "chistory" ---@type string
    if src_win then
        api.nvim_win_call(src_win, function()
            ---@diagnostic disable-next-line: missing-fields
            api.nvim_cmd({ cmd = cmd, count = count, mods = { silent = opts.silent } }, {})
        end)
    else
        ---@diagnostic disable-next-line: missing-fields
        api.nvim_cmd({ cmd = cmd, count = count, mods = { silent = opts.silent } }, {})
    end

    local list_nr_after = rt._get_list(src_win, { nr = 0 }).nr ---@type integer
    return list_nr_after
end

---@param src_win integer|nil
---@param count integer|nil
---@param opts? qfr.stack.GotoHistoryOpts
---@return integer
local function goto_history(src_win, count, opts)
    opts = opts or {}
    ry._validate_win(src_win, true)
    ry._validate_uint(count, true)
    validate_history_opts(opts)

    local max_list_nr = rt._get_list(src_win, { nr = "$" }).nr ---@type integer
    if max_list_nr < 1 then
        api.nvim_echo({ { "No entries", "" } }, false, {})
        return -1
    end

    local adj_count = count and math.min(count, max_list_nr) or nil ---@type integer|nil
    ---@type integer|nil
    local fix_count = (function()
        if (not adj_count) or adj_count > 0 then
            return adj_count
        end

        local cur_list_nr = rt._get_list(src_win, { nr = 0 }).nr ---@type integer
        return cur_list_nr
    end)()

    return run_history(src_win, fix_count, opts)
end

---@param src_win integer|nil
---@param count integer
---@param opts? qfr.stack.GotoHistoryOpts
---@return integer
local function goto_prev(src_win, count, opts)
    opts = opts or {}
    ry._validate_win(src_win, true)
    ry._validate_uint(count)
    validate_history_opts(opts)

    local max_list_nr = rt._get_list(src_win, { nr = "$" }).nr ---@type integer
    if max_list_nr < 1 then
        api.nvim_echo({ { "No entries", "" } }, false, {})
        return -1
    end

    local cur_list_nr = rt._get_list(src_win, { nr = 0 }).nr ---@type integer
    local adj_count = math.max(count, 1) ---@type integer
    local new_list_nr = ru._wrapping_sub(cur_list_nr, adj_count, 1, max_list_nr) ---@type integer

    return run_history(src_win, new_list_nr, opts)
end

---@param src_win integer|nil
---@param count integer
---@param opts? qfr.stack.GotoHistoryOpts
---@return integer
local function goto_next(src_win, count, opts)
    opts = opts or {}
    ry._validate_win(src_win, true)
    ry._validate_uint(count)
    validate_history_opts(opts)

    local max_list_nr = rt._get_list(src_win, { nr = "$" }).nr ---@type integer
    if max_list_nr < 1 then
        api.nvim_echo({ { "No entries", "" } }, false, {})
        return -1
    end

    local cur_list_nr = rt._get_list(src_win, { nr = 0 }).nr ---@type integer
    local adj_count = math.max(count, 1) ---@type integer
    local new_list_nr = ru._wrapping_add(cur_list_nr, adj_count, 1, max_list_nr) ---@type integer

    return run_history(src_win, new_list_nr, opts)
end

---@mod Stack View and edit the list stack
---@tag qf-rancher-stack
---@tag qfr-stack
---@brief [[
---
---@brief ]]

--- @class QfrStack
local Stack = {}

-- NOGO: Keep this as an opt. It's flexible if I need to add things later
--
---@class qfr.stack.GotoHistoryOpts
---@field silent boolean Suppress messages

---If g:qfr_auto_list_height is true, the list will automatically resize
---@param count integer Wrapping count previous list to go to. Minimum 1
---@param opts? qfr.stack.GotoHistoryOpts See |qfr.stack.GotoHistoryOpts|
---@return nil
function Stack.q_older(count, opts)
    local cur_nr = vim.fn.getqflist({ nr = 0 }).nr ---@type integer
    local nr_after = goto_prev(nil, count, opts) ---@type integer

    local ran = nr_after > 0 ---@type boolean
    local changed = cur_nr ~= nr_after ---@type boolean
    local can_resize = ran and changed ---@type boolean
    if can_resize and vim.g.qfr_auto_list_height then
        Stack._resize_after_change()
    end
end

---If g:qfr_auto_list_height is true, the list will automatically resize
---@param count integer Wrapping count next list to go to. Minimum 1
---@param opts? qfr.stack.GotoHistoryOpts See |qfr.stack.GotoHistoryOpts|
---@return nil
function Stack.q_newer(count, opts)
    local cur_nr = vim.fn.getqflist({ nr = 0 }).nr ---@type integer
    local nr_after = goto_next(nil, count, opts) ---@type integer

    local ran = nr_after > 0 ---@type boolean
    local changed = cur_nr ~= nr_after ---@type boolean
    local can_resize = ran and changed ---@type boolean
    if can_resize and vim.g.qfr_auto_list_height then
        Stack._resize_after_change()
    end
end

---If g:qfr_auto_list_height is true, the list will automatically resize
---@param src_win integer Location list window context
---@param count integer Wrapping count previous list to go to. Minimum 1
---@param opts? qfr.stack.GotoHistoryOpts See |qfr.stack.GotoHistoryOpts|
---@return nil
function Stack.l_older(src_win, count, opts)
    local cur_nr = vim.fn.getloclist(src_win, { nr = 0 }).nr ---@type integer
    local nr_after = goto_prev(src_win, count, opts) ---@type integer

    local ran = nr_after > 0 ---@type boolean
    local changed = cur_nr ~= nr_after ---@type boolean
    local can_resize = ran and changed ---@type boolean
    if can_resize and vim.g.qfr_auto_list_height then
        Stack._resize_after_change(src_win)
    end
end

---If g:qfr_auto_list_height is true, the list will automatically resize
---@param src_win integer Location list window context
---@param count integer Wrapping count next list to go to. Minimum 1
---@param opts? qfr.stack.GotoHistoryOpts See |qfr.stack.GotoHistoryOpts|
---@return nil
function Stack.l_newer(src_win, count, opts)
    local cur_nr = vim.fn.getloclist(src_win, { nr = 0 }).nr ---@type integer
    local nr_after = goto_next(src_win, count, opts) ---@type integer

    local ran = nr_after > 0 ---@type boolean
    local changed = cur_nr ~= nr_after ---@type boolean
    local can_resize = ran and changed ---@type boolean
    if can_resize and vim.g.qfr_auto_list_height then
        Stack._resize_after_change(src_win)
    end
end

---If g:qfr_auto_list_height is true, the list will automatically resize
---@param count integer|nil List number to go to, nil to display the whole
---stack. A count of 0 shows the current list number (difference
---from core behavior)
---@param opts? qfr.stack.GotoHistoryOpts See |qfr.stack.GotoHistoryOpts|
---@return nil
function Stack.q_history(count, opts)
    local cur_nr = vim.fn.getqflist({ nr = 0 }).nr ---@type integer
    local nr_after = goto_history(nil, count, opts) ---@type integer

    local ran = nr_after > 0 ---@type boolean
    local changed = cur_nr ~= nr_after ---@type boolean
    local can_resize = ran and changed ---@type boolean
    if can_resize and vim.g.qfr_auto_list_height then
        Stack._resize_after_change()
    end
end

---If g:qfr_auto_list_height is true, the list will automatically resize
---@param src_win integer Location list window context
---@param count integer|nil List number to go to, nil to display the
---whole stack. A count of 0 shows the current list number
---(difference from core behavior)
---@param opts? qfr.stack.GotoHistoryOpts See |qfr.stack.GotoHistoryOpts|
---@return nil
function Stack.l_history(src_win, count, opts)
    local cur_nr = vim.fn.getloclist(src_win, { nr = 0 }).nr ---@type integer
    local nr_after = goto_history(src_win, count, opts) ---@type integer

    local ran = nr_after > 0 ---@type boolean
    local changed = cur_nr ~= nr_after ---@type boolean
    local can_resize = ran and changed ---@type boolean
    if can_resize and vim.g.qfr_auto_list_height then
        Stack._resize_after_change(src_win)
    end
end

---If the current list is cleared, and g:qfr_auto_list_height is true, the
---list will be resized
---@param count integer List number to delete. 0 for current
---@return nil
function Stack.q_del(count)
    ry._validate_uint(count)

    local result = rt._clear_list(nil, count)
    if result == -1 then
        return
    end

    local cur_list_nr = vim.fn.getqflist({ nr = 0 }).nr ---@type integer
    if (result == cur_list_nr) and vim.g.qfr_auto_list_height then
        Stack._resize_after_change()
    end
end

---If the current list is cleared, and g:qfr_auto_list_height is true, the
---list will be resized
---@param src_win integer Location list window context
---@param count integer List number to delete. 0 for current
---@return nil
function Stack.l_del(src_win, count)
    ry._validate_win(src_win)
    ry._validate_uint(count)

    local wintype = vim.fn.win_gettype(src_win)
    local qf_id = vim.fn.getloclist(src_win, { id = 0 }).id ---@type integer
    if qf_id == 0 and wintype ~= "loclist" then
        api.nvim_echo({ { "Window has no location list" } }, false, {})
        return
    end

    local result = rt._clear_list(src_win, count)
    if result == -1 then
        return
    end

    local cur_list_nr = vim.fn.getloclist(src_win, { nr = 0 }).nr ---@type integer
    if (result == cur_list_nr) and vim.g.qfr_auto_list_height then
        Stack._resize_after_change(src_win)
    end
end

---Delete the quickfix stack. If g:qfr_close_on_stack_clear is true, close
---all qfwins in all tabs
---@return nil
function Stack.q_del_all()
    local result = vim.fn.setqflist({}, "f") ---@type integer
    if result == 0 and vim.g.qfr_close_on_stack_clear then
        local tabpages = api.nvim_list_tabpages() ---@type integer[]
        rw._close_qflists(tabpages)
    end
end

-- MAYBE: At least as far as I know, it's not possible for a qf_id to be duplicated in multiple
-- loclist windows, so avoiding doing anything to handle that case until I see a way to produce it
--
---Delete a loclist stack. If g:qfr_close_on_stack_clear is true, close
---the location list window
---NOTE: When a location list stack is freed but the window is not closed,
---the qf_id of the location list window is set to zero. When this function
---is run, it searches for all qf_id 0 location list windows in all tabs and
---closes them. If the function is run from within a qf_id 0 location list
---window, it will always run a scan for others to close
---@param src_win integer Location list window context
---@return nil
function Stack.l_del_all(src_win)
    ry._validate_win(src_win)

    local wintype = vim.fn.win_gettype(src_win)
    local qf_id = vim.fn.getloclist(src_win, { id = 0 }).id ---@type integer
    if qf_id == 0 and wintype ~= "loclist" then
        api.nvim_echo({ { "Window has no location list" } }, false, {})
        return
    end

    local result = vim.fn.setloclist(src_win, {}, "f") ---@type integer
    local should_close = result == 0 and vim.g.qfr_close_on_stack_clear
    if qf_id == 0 or should_close then
        local tabpages = api.nvim_list_tabpages() ---@type integer[]
        rw._close_loclists({ qf_id = 0, tabpages = tabpages })
    end
end

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

---Qhistory cmd callback. Expects count = 0 in the user_command table
---@param cargs vim.api.keyset.create_user_command.command_args
---@return nil
function Stack.q_history_cmd(cargs)
    local count = cargs.count ---@type integer
    local range = cargs.range ---@type integer
    -- cargs.count shows zero if the user entered a count of 0 or if the user did not enter a
    -- count. Use range to check if the user actually entered a count
    local adj_count = range > 0 and count or nil ---@type integer|nil

    Stack.q_history(adj_count)
end

---Lhistory cmd callback. Expects count = 0 in the user_command table
---@param cargs vim.api.keyset.create_user_command.command_args
---@return nil
function Stack.l_history_cmd(cargs)
    local count = cargs.count ---@type integer
    local range = cargs.range ---@type integer
    -- cargs.count shows zero if the user entered a count of 0 or if the user did not enter a
    -- count. Use range to check if the user actually entered a count
    local adj_count = range > 0 and count or nil ---@type integer|nil
    local win = api.nvim_get_current_win()

    Stack.l_history(win, adj_count)
end

---Qdelete cmd callback. Expects count = 0 and nargs = "?" in the command
---table
---NOTE: If "all" is provided, any count is overridden
---A count of zero deletes the current list
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
---NOTE: If "all" is provided, any count is overridden
---A count of zero deletes the current list
---@param cargs vim.api.keyset.create_user_command.command_args
---@return nil
function Stack.l_delete_cmd(cargs)
    local cur_win = api.nvim_get_current_win()
    if cargs.args == "all" then
        Stack.l_del_all(cur_win)
        return
    end

    Stack.l_del(cur_win, cargs.count)
end

---@brief [[
---IMPLEMENTATION DETAIL:
---
---The history, prev, and next commands all use chistory/lhistory under the
---hood. For l_history, l_prev, and l_next, rancher uses nvim_win_call to match
---lhistory to the src_win context. The default maps and cmds all use the
---current win for src_win
---@brief ]]

---@export Stack

-- MAYBE: Just put the actual goto_history code in here
-- NOGO: Because this is an internal function: resizing, list opening, and window focus
-- should be handled by callers. Don't put that stuff here
---@param src_win integer|nil
---@param count integer|nil
---@param opts? qfr.stack.GotoHistoryOpts See |qfr.stack.GotoHistoryOpts|
---@return integer
function Stack._goto_history(src_win, count, opts)
    return goto_history(src_win, count, opts)
end

---@param src_win integer|nil
---@return nil
function Stack._resize_after_change(src_win)
    if src_win then
        local tabpage = api.nvim_win_get_tabpage(src_win) ---@type integer
        rw._resize_loclists({ src_win = src_win, tabpages = { tabpage } })
    else
        local tabpages = api.nvim_list_tabpages() ---@type integer[]
        rw._resize_qflists(tabpages)
    end
end

return Stack

-- MID: Centralize the stack size validity checks in the core logic and return the starting +
-- ending list numbers from there. As is, stack size validity is being needlessly checked
-- multiple times
-- MID: Right now, the outer interface functions are pulling cur_nr to check for resize, letting
-- the inner functions check stack size, then checking nr_after to see if they ran as if cur_nr
-- did not exist. Either the outer interface functions should be treated as pass-throughts,
-- meaning the inner functions need to also return cur_nr, or the outer functions need to perform
-- validation, and the inner functions should assume it is correct
-- If all the actual work happens in the inner functions, they also need to pass up errors for
-- the outer functions to report, rather than burying the echo behavior

-- LOW: The more clever way to do the history changes is to pass the wrapping math as a param
-- into a generalized function. Keeping it simple for now though

-- MAYBE: Make count an opt
