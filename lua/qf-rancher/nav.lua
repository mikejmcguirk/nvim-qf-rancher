local rt = Qfr_Defer_Require("qf-rancher.tools") ---@type QfrTools
local ru = Qfr_Defer_Require("qf-rancher.util") ---@type QfrUtil
local ry = Qfr_Defer_Require("qf-rancher.types") ---@type QfrTypes

local api = vim.api
local fn = vim.fn

---@mod Nav Navigate lists
---@tag qf-rancher-nav
---@tag qfr-nav
---@brief [[
---
---@brief ]]

--- @class QfRancherNav
local Nav = {}

-- ============
-- == LOCALS ==
-- ============

-- MID: These functions are not all that distinct from each other

---@param new_idx integer
---@param cmd string
---@param opts table
---@return boolean
local function goto_list_entry(new_idx, cmd, opts)
    ry._validate_uint(new_idx)
    vim.validate("cmd", cmd, "string")
    vim.validate("opts", opts, "table")

    ---@type boolean, string
    local ok, result = pcall(api.nvim_cmd, { cmd = cmd, count = new_idx }, {})
    if ok then
        ru._do_zzze(api.nvim_get_current_win())
        return true
    end

    local msg = result or ("Unknown error displaying list entry " .. new_idx) ---@type string
    api.nvim_echo({ { msg, "ErrorMsg" } }, true, { err = true })
    return false
end

---@param src_win integer|nil
---@param count integer
---@return nil
local function goto_specific_idx(src_win, count)
    ry._validate_win(src_win, true)
    ry._validate_uint(count)

    local size = rt._get_list(src_win, { size = 0 }).size ---@type integer
    if not size or size < 1 then
        api.nvim_echo({ { "E42: No Errors", "" } }, false, {})
        return nil
    end

    local cmd = src_win and "ll" or "cc" ---@type string
    if count > 0 then
        local adj_count = math.min(count, size) ---@type integer
        goto_list_entry(adj_count, cmd, {})
        return
    end

    -- If we're in a list, go to the entry under the cursor
    local cur_win = src_win or api.nvim_get_current_win() ---@type integer
    local wintype = fn.win_gettype(cur_win)
    local in_loclist = type(src_win) == "number" and wintype == "loclist" ---@type boolean
    local in_qflist = (not src_win) and wintype == "quickfix" ---@type boolean
    if in_loclist or in_qflist then
        local row = api.nvim_win_get_cursor(cur_win)[1] ---@type integer
        local adj_count = math.min(row, size) ---@type integer
        goto_list_entry(adj_count, cmd, {})
        return
    end

    local cur_idx = rt._get_list(src_win, { idx = 0 }).idx ---@type integer
    if cur_idx < 1 then return end

    goto_list_entry(cur_idx, cmd, {})
end

---@param count integer
---@param cmd string
---@return nil
local function bookends(count, cmd)
    ry._validate_uint(count)
    vim.validate("cmd", cmd, "string")

    local adj_count = count >= 1 and count or nil ---@type integer|nil
    ---@type boolean, string
    local ok, err = pcall(api.nvim_cmd, { cmd = cmd, count = adj_count }, {})
    if ok then
        ru._do_zzze(api.nvim_get_current_win())
        return
    end

    local msg = err:sub(#"Vim:" + 1) ---@type string
    if string.find(err, "E42", 1, true) then
        api.nvim_echo({ { msg, "" } }, false, {})
    else
        api.nvim_echo({ { msg, "ErrorMsg" } }, true, { err = true })
    end
end

---@param src_win integer|nil
---@param count integer
---@param cmd string
---@param backup_cmd string
---@return nil
local function file_nav_wrap(src_win, count, cmd, backup_cmd)
    ry._validate_win(src_win, true)
    ry._validate_uint(count)
    vim.validate("cmd", cmd, "string")
    vim.validate("backup_cmd", backup_cmd, "string")

    local size = rt._get_list(src_win, { size = 0 }).size ---@type integer
    if not size or size < 1 then
        api.nvim_echo({ { "E42: No Errors", "" } }, false, {})
        return nil
    end

    local adj_count = ru._count_to_count1(count) ---@type integer

    ---@type boolean, string
    local ok, err = pcall(api.nvim_cmd, { cmd = cmd, count = adj_count }, {})
    local e42 = string.find(err, "E42", 1, true) ---@type integer|nil
    local e776 = string.find(err, "E776", 1, true) ---@type integer|nil
    if (not ok) and (e42 or e776) then
        api.nvim_echo({ { err:sub(#"Vim:" + 1), "" } }, false, {})
        return
    end

    local e553 = string.find(err, "E553", 1, true) ---@type integer|nil
    if (not ok) and e553 then
        ok, err = pcall(api.nvim_cmd, { cmd = backup_cmd }, {})
    end

    if not ok then
        local msg = err and err:sub(#"Vim:" + 1) or "Unknown qf file error" ---@type string
        api.nvim_echo({ { msg, "ErrorMsg" } }, true, { err = true })
        return
    end

    ru._do_zzze(api.nvim_get_current_win())
end

-- ================
-- == PUBLIC API ==
-- ================

---@brief [[
---NOTE: All navigation commands will auto-center the buffer view if
---g:qfr_auto_center_result is true
---@brief ]]

---@param count integer Wrapping count previous entry to navigate to
---@param opts table Reserved for future use
---@return boolean
function Nav.q_prev(count, opts)
    local new_idx = ru._get_idx_wrapping_sub(nil, count) ---@type integer|nil
    if new_idx then return goto_list_entry(new_idx, "cc", opts) end
    return false
end

---@param count integer Wrapping count next entry to navigate to
---@param opts table Reserved for future use
---@return boolean
function Nav.q_next(count, opts)
    local new_idx = ru._get_idx_wrapping_add(nil, count) ---@type integer|nil
    if new_idx then return goto_list_entry(new_idx, "cc", opts) end
    return false
end

---@param src_win integer Location list window context
---@param count integer Wrapping count previous entry to navigate to
---@param opts table Reserved for future use
---@return boolean
function Nav.l_prev(src_win, count, opts)
    return ru._locwin_check(src_win, function()
        local new_idx = ru._get_idx_wrapping_sub(src_win, count) ---@type integer|nil
        if new_idx then goto_list_entry(new_idx, "ll", opts) end
    end)
end

---@param src_win integer Location list window context
---@param count integer Wrapping count next entry to navigate to
---@param opts table Reserved for future use
---@return boolean
function Nav.l_next(src_win, count, opts)
    return ru._locwin_check(src_win, function()
        local new_idx = ru._get_idx_wrapping_add(src_win, count) ---@type integer|nil
        if new_idx then goto_list_entry(new_idx, "ll", opts) end
    end)
end

-- GOTO SPECIFIC INDEX --

-- MID: [Q]Q is a bit awkward for going to a specific index

---If a count is provided, that list entry will be opened
---If no count is provided, and the window focus is on a list, the list item
---under the cursor will be opened (different from default cc/ll behavior)
---If the focus is not in a list, the current list idx will be used
---@param count integer Count entry to navigate to
---@return nil
function Nav.q_q(count)
    goto_specific_idx(nil, count)
end

---@param src_win integer Count entry to navigate to
---@param count integer
---@return nil
function Nav.l_l(src_win, count)
    ru._locwin_check(src_win, function()
        goto_specific_idx(src_win, count)
    end)
end

-- REWIND/LAST --

---@param count integer Entry to navigate to. First if no count
---@return nil
function Nav.q_rewind(count)
    bookends(count, "crewind")
end

---@param count integer Entry to navigate to. Last if no count
---@return nil
function Nav.q_last(count)
    bookends(count, "clast")
end

---@param src_win integer Location list window context
---@param count integer Entry to navigate to. First if no count
---@return nil
function Nav.l_rewind(src_win, count)
    ru._locwin_check(src_win, function()
        bookends(count, "lrewind")
    end)
end

---@param src_win integer Location list window context
---@param count integer Entry to navigate to. Last if no count
---@return nil
function Nav.l_last(src_win, count)
    ru._locwin_check(src_win, function()
        bookends(count, "llast")
    end)
end

-- FILE NAV --

---NOTE: While the p/nfile commands will wrap to the first or last file
---when trying to navigate past the end, the count cannot be used to wrap to a
---specific entry like with the next/prev commands
---@param count integer Count previous file to navigate to
---@return nil
function Nav.q_pfile(count)
    file_nav_wrap(nil, count, "cpfile", "clast")
end

---@param count integer
---@return nil
function Nav.q_nfile(count)
    file_nav_wrap(nil, count, "cnfile", "crewind")
end

---@param src_win integer Location list window context
---@param count integer Count previous file to navigate to
---@return nil
function Nav.l_pfile(src_win, count)
    ru._locwin_check(src_win, function()
        file_nav_wrap(src_win, count, "lpfile", "llast")
    end)
end

---@param src_win integer Location list window context
---@param count integer Count next file to navigate to
---@return nil
function Nav.l_nfile(src_win, count)
    ru._locwin_check(src_win, function()
        file_nav_wrap(src_win, count, "lnfile", "lrewind")
    end)
end

-- PREV/NEXT --

---Qprev cmd callback. Expects count = 0 in the user_command table
---@param cargs vim.api.keyset.create_user_command.command_args
---@return nil
function Nav.q_prev_cmd(cargs)
    Nav.q_prev(cargs.count, {})
end

---Qnext cmd callback. Expects count = 0 in the user_command table
---@param cargs vim.api.keyset.create_user_command.command_args
---@return nil
function Nav.q_next_cmd(cargs)
    Nav.q_next(cargs.count, {})
end

---Lprev cmd callback. Expects count = 0 in the user_command table
---@param cargs vim.api.keyset.create_user_command.command_args
---@return nil
function Nav.l_prev_cmd(cargs)
    Nav.l_prev(api.nvim_get_current_win(), cargs.count, {})
end

--Lnext cmd callback. Expects count = 0 in the user_command table
---@param cargs vim.api.keyset.create_user_command.command_args
---@return nil
function Nav.l_next_cmd(cargs)
    Nav.l_next(api.nvim_get_current_win(), cargs.count, {})
end

-- GOTO SPECIFIC INDEX --

---Qq cmd callback. Expects count = 0 in the user_command table
---@param cargs vim.api.keyset.create_user_command.command_args
---@return nil
function Nav.q_q_cmd(cargs)
    Nav.q_q(cargs.count)
end

--Ll cmd callback. Expects count = 0 in the user_command table
---@param cargs vim.api.keyset.create_user_command.command_args
---@return nil
function Nav.l_l_cmd(cargs)
    Nav.l_l(api.nvim_get_current_win(), cargs.count)
end

-- REWIND/LAST --

---Qrewind cmd callback. Expects count = 0 in the user_command table
---@param cargs vim.api.keyset.create_user_command.command_args
---@return nil
function Nav.q_rewind_cmd(cargs)
    Nav.q_rewind(cargs.count)
end

---Qlast cmd callback. Expects count = 0 in the user_command table
---@param cargs vim.api.keyset.create_user_command.command_args
---@return nil
function Nav.q_last_cmd(cargs)
    Nav.q_last(cargs.count)
end

---Lrewind cmd callback. Expects count = 0 in the user_command table
---@param cargs vim.api.keyset.create_user_command.command_args
---@return nil
function Nav.l_rewind_cmd(cargs)
    Nav.l_rewind(api.nvim_get_current_win(), cargs.count)
end

---Llast cmd callback. Expects count = 0 in the user_command table
---@param cargs vim.api.keyset.create_user_command.command_args
---@return nil
function Nav.l_last_cmd(cargs)
    Nav.l_last(api.nvim_get_current_win(), cargs.count)
end

-- FILE NAV --

---Qpfile cmd callback. Expects count = 0 in the user_command table
---NOTE: While the p/nfile commands will wrap to the first or last file
---when trying to navigate past the end, the count cannot be used to wrap to a
---specific entry like with the next/prev commands
---@param cargs vim.api.keyset.create_user_command.command_args
---@return nil
function Nav.q_pfile_cmd(cargs)
    Nav.q_pfile(cargs.count)
end

---Qnfile cmd callback. Expects count = 0 in the user_command table
---@param cargs vim.api.keyset.create_user_command.command_args
---@return nil
function Nav.q_nfile_cmd(cargs)
    Nav.q_nfile(cargs.count)
end

---Lpfile cmd callback. Expects count = 0 in the user_command table
---@param cargs vim.api.keyset.create_user_command.command_args
---@return nil
function Nav.l_pfile_cmd(cargs)
    Nav.l_pfile(api.nvim_get_current_win(), cargs.count)
end

---Lnfile cmd callback. Expects count = 0 in the user_command table
---@param cargs vim.api.keyset.create_user_command.command_args
---@return nil
function Nav.l_nfile_cmd(cargs)
    Nav.l_nfile(api.nvim_get_current_win(), cargs.count)
end

return Nav
---@export Nav

-- TODO: Testing
