local rt = Qfr_Defer_Require("qf-rancher.tools") ---@type qf-rancher.Tools
local ru = Qfr_Defer_Require("qf-rancher.util") ---@type qf-rancher.Util
local ry = Qfr_Defer_Require("qf-rancher.types") ---@type qf-rancher.Types

local api = vim.api
local fn = vim.fn

---@param src_win integer|nil
---@param new_idx integer
---@return nil
local function goto_list_entry(src_win, new_idx)
    local cmd = src_win and "ll" or "cc"
    api.nvim_cmd({ cmd = cmd, count = new_idx }, {})

    local cur_win = api.nvim_get_current_win()
    ru._do_zzze(cur_win)
end

---@param src_win integer|nil
---@param count integer
---@return nil
local function goto_specific_idx(src_win, count)
    local size = rt._get_list(src_win, { size = 0 }).size ---@type integer
    if not size or size < 1 then
        api.nvim_echo({ { QF_RANCHER_E42, "" } }, false, {})
        return nil
    end

    if count > 0 then
        local adj_count = math.min(count, size)
        goto_list_entry(src_win, adj_count)
        return
    end

    local cur_win = src_win or api.nvim_get_current_win()
    local wintype = fn.win_gettype(cur_win)
    local checked_type = src_win and "loclist" or "quickfix"
    if wintype == checked_type then
        local row = api.nvim_win_get_cursor(cur_win)[1]
        local adj_count = math.min(row, size)
        goto_list_entry(src_win, adj_count)
        return
    end

    local cur_idx = rt._get_list(src_win, { idx = 0 }).idx ---@type integer
    goto_list_entry(src_win, cur_idx)
end

---@param count integer
---@param cmd string
---@return nil
local function bookends(count, cmd)
    local adj_count = count >= 1 and count or nil
    local ok, err = pcall(api.nvim_cmd, { cmd = cmd, count = adj_count }, {})
    if ok then
        local cur_win = api.nvim_get_current_win()
        ru._do_zzze(cur_win)
        return
    end

    local msg = err:sub(#"Vim:" + 1)
    if string.find(err, "E42", 1, true) then
        api.nvim_echo({ { msg, "" } }, false, {})
    else
        api.nvim_echo({ { msg, "ErrorMsg" } }, true, {})
    end
end

---@param src_win integer|nil
---@param count integer
---@param cmd string
---@param backup_cmd string
---@return nil
local function file_nav_wrap(src_win, count, cmd, backup_cmd)
    local size = rt._get_list(src_win, { size = 0 }).size ---@type integer
    if not size or size < 1 then
        api.nvim_echo({ { "E42: No Errors", "" } }, false, {})
        return nil
    end

    local adj_count = math.max(count, 1) ---@type integer

    local ok, err = pcall(api.nvim_cmd, { cmd = cmd, count = adj_count }, {})
    local e42 = string.find(err, "E42", 1, true)
    local e776 = string.find(err, "E776", 1, true)
    if (not ok) and (e42 or e776) then
        local err_text = err:sub(#"Vim:" + 1)
        api.nvim_echo({ { err_text, "" } }, false, {})
        return
    end

    local e553 = string.find(err, "E553", 1, true)
    if (not ok) and e553 then
        ok, err = pcall(api.nvim_cmd, { cmd = backup_cmd }, {})
    end

    if not ok then
        local msg = err and err:sub(#"Vim:" + 1) or "Unknown qf file error"
        api.nvim_echo({ { msg, "ErrorMsg" } }, true, {})
        return
    end

    local cur_win = api.nvim_get_current_win()
    ru._do_zzze(cur_win)
end

---@mod Nav Navigate lists
---@tag qf-rancher-nav
---@tag qfr-nav
---@brief [[
---
---@brief ]]

--- @class qf-rancher.Nav
local Nav = {}

---@param count integer Wrapping count previous entry to navigate to
---@return nil
function Nav.q_prev(count)
    ry._validate_uint(count)

    local ok, new_idx, hl = ru._get_wrapping_sub(nil, count)
    if not ok or type(new_idx) ~= "number" then
        ru._echo(false, new_idx, hl)
        return
    end

    goto_list_entry(nil, new_idx)
end

---@param count integer Wrapping count next entry to navigate to
---@return nil
function Nav.q_next(count)
    ry._validate_uint(count)

    local ok, new_idx, hl = ru._get_wrapping_add(nil, count)
    if not ok or type(new_idx) ~= "number" then
        ru._echo(false, new_idx, hl)
        return
    end

    goto_list_entry(nil, new_idx)
end

---@param src_win integer Location list window context
---@param count integer Wrapping count previous entry to navigate to
---@return nil
function Nav.l_prev(src_win, count)
    ry._validate_win(src_win)
    ry._validate_uint(count)

    local qf_id = fn.getloclist(src_win, { id = 0 }).id
    if qf_id == 0 then
        api.nvim_echo({ { QF_RANCHER_NO_LL } }, false, {})
        return
    end

    local ok, new_idx, hl = ru._get_wrapping_sub(src_win, count)
    if not ok or type(new_idx) ~= "number" then
        ru._echo(false, new_idx, hl)
        return
    end

    goto_list_entry(src_win, new_idx)
end

---@param src_win integer Location list window context
---@param count integer Wrapping count next entry to navigate to
---@return nil
function Nav.l_next(src_win, count)
    ry._validate_win(src_win)
    ry._validate_uint(count)

    local qf_id = fn.getloclist(src_win, { id = 0 }).id
    if qf_id == 0 then
        api.nvim_echo({ { QF_RANCHER_NO_LL } }, false, {})
        return
    end

    local ok, new_idx, hl = ru._get_wrapping_add(src_win, count)
    if not ok or type(new_idx) ~= "number" then
        ru._echo(false, new_idx, hl)
        return
    end

    goto_list_entry(src_win, new_idx)
end

-- MID: [Q]Q is a bit awkward for going to a specific index

---If a count is provided, that list entry will be opened
---If no count is provided, and the window focus is on a list, the list item
---under the cursor will be opened (different from default cc/ll behavior)
---If the focus is not in a list, the current list idx will be used
---@param count integer Count entry to navigate to
---@return nil
function Nav.q_q(count)
    ry._validate_uint(count)
    goto_specific_idx(nil, count)
end

---@param src_win integer Count entry to navigate to
---@param count integer
---@return nil
function Nav.l_l(src_win, count)
    ry._validate_win(src_win, true)
    ry._validate_uint(count)

    local qf_id = fn.getloclist(src_win, { id = 0 }).id
    if qf_id == 0 then
        api.nvim_echo({ { QF_RANCHER_NO_LL } }, false, {})
        return
    end

    goto_specific_idx(src_win, count)
end

---@param count integer Entry to navigate to. First if no count
---@return nil
function Nav.q_rewind(count)
    ry._validate_uint(count)
    bookends(count, "crewind")
end

---@param count integer Entry to navigate to. Last if no count
---@return nil
function Nav.q_last(count)
    ry._validate_uint(count)
    bookends(count, "clast")
end

---@param src_win integer Location list window context
---@param count integer Entry to navigate to. First if no count
---@return nil
function Nav.l_rewind(src_win, count)
    ry._validate_win(src_win)
    ry._validate_uint(count)

    local qf_id = fn.getloclist(src_win, { id = 0 }).id
    if qf_id == 0 then
        api.nvim_echo({ { QF_RANCHER_NO_LL } }, false, {})
        return
    end

    bookends(count, "lrewind")
end

---@param src_win integer Location list window context
---@param count integer Entry to navigate to. Last if no count
---@return nil
function Nav.l_last(src_win, count)
    ry._validate_win(src_win)
    ry._validate_uint(count)

    local qf_id = fn.getloclist(src_win, { id = 0 }).id
    if qf_id == 0 then
        api.nvim_echo({ { QF_RANCHER_NO_LL } }, false, {})
        return
    end

    bookends(count, "llast")
end

---@brief [[
---NOTE: While the p/nfile commands will wrap to the first or last file
---when trying to navigate past the end, the count cannot be used to wrap to a
---specific entry like with the next/prev commands
---@brief ]]

---@param count integer Count previous file to navigate to
---@return nil
function Nav.q_pfile(count)
    ry._validate_uint(count)
    file_nav_wrap(nil, count, "cpfile", "clast")
end

---@param count integer
---@return nil
function Nav.q_nfile(count)
    ry._validate_uint(count)
    file_nav_wrap(nil, count, "cnfile", "crewind")
end

---@param src_win integer Location list window context
---@param count integer Count previous file to navigate to
---@return nil
function Nav.l_pfile(src_win, count)
    ry._validate_win(src_win)
    ry._validate_uint(count)

    local qf_id = fn.getloclist(src_win, { id = 0 }).id
    if qf_id == 0 then
        api.nvim_echo({ { QF_RANCHER_NO_LL } }, false, {})
        return
    end

    file_nav_wrap(src_win, count, "lpfile", "llast")
end

---@param src_win integer Location list window context
---@param count integer Count next file to navigate to
---@return nil
function Nav.l_nfile(src_win, count)
    ry._validate_win(src_win)
    ry._validate_uint(count)

    local qf_id = fn.getloclist(src_win, { id = 0 }).id
    if qf_id == 0 then
        api.nvim_echo({ { QF_RANCHER_NO_LL } }, false, {})
        return
    end

    file_nav_wrap(src_win, count, "lnfile", "lrewind")
end

---Qprev cmd callback. Expects count = 0 in the user_command table
---@param cargs vim.api.keyset.create_user_command.command_args
---@return nil
function Nav.q_prev_cmd(cargs)
    Nav.q_prev(cargs.count)
end

---Qnext cmd callback. Expects count = 0 in the user_command table
---@param cargs vim.api.keyset.create_user_command.command_args
---@return nil
function Nav.q_next_cmd(cargs)
    Nav.q_next(cargs.count)
end

---Lprev cmd callback. Expects count = 0 in the user_command table
---@param cargs vim.api.keyset.create_user_command.command_args
---@return nil
function Nav.l_prev_cmd(cargs)
    local cur_win = api.nvim_get_current_win()
    Nav.l_prev(cur_win, cargs.count)
end

--Lnext cmd callback. Expects count = 0 in the user_command table
---@param cargs vim.api.keyset.create_user_command.command_args
---@return nil
function Nav.l_next_cmd(cargs)
    local cur_win = api.nvim_get_current_win()
    Nav.l_next(cur_win, cargs.count)
end

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
    local cur_win = api.nvim_get_current_win()
    Nav.l_l(cur_win, cargs.count)
end

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
    local cur_win = api.nvim_get_current_win()
    Nav.l_rewind(cur_win, cargs.count)
end

---Llast cmd callback. Expects count = 0 in the user_command table
---@param cargs vim.api.keyset.create_user_command.command_args
---@return nil
function Nav.l_last_cmd(cargs)
    local cur_win = api.nvim_get_current_win()
    Nav.l_last(cur_win, cargs.count)
end

---Qpfile cmd callback. Expects count = 0 in the user_command table
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
    local cur_win = api.nvim_get_current_win()
    Nav.l_pfile(cur_win, cargs.count)
end

---Lnfile cmd callback. Expects count = 0 in the user_command table
---@param cargs vim.api.keyset.create_user_command.command_args
---@return nil
function Nav.l_nfile_cmd(cargs)
    local cur_win = api.nvim_get_current_win()
    Nav.l_nfile(cur_win, cargs.count)
end

return Nav
---@export Nav

-- MID: The idea has been noted elsewhere, but the list navigation should be re-built from the
-- ground up. Two important advantages:
-- - Control over where the file opens. I would like to prevent [q]q from being responsive to
-- switchbuf.
-- - The location list functions would allow for more granular control over list/win context
-- Additionally, I might finally be able to build up some common logic that can be used between
-- nav, the ftplugin funcs, and system

-- MAYBE: Have a qf_rancher_ignore_useopen_on_scroll option or
-- qf_rancher_nav_use_cur_win
-- But would have to think about it in broader context
