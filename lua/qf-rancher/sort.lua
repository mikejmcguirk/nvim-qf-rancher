local lib = Qfr_Defer_Require("qf-rancher.lib.sort") ---@type qf-rancher.lib.Sort
local ra = Qfr_Defer_Require("qf-rancher.stack") ---@type qf-rancher.Stack
local rt = Qfr_Defer_Require("qf-rancher.tools") ---@type qf-rancher.Tools
local ru = Qfr_Defer_Require("qf-rancher.util") ---@type qf-rancher.Util
local ry = Qfr_Defer_Require("qf-rancher.types") ---@type qf-rancher.Types
local rw = Qfr_Defer_Require("qf-rancher.window") ---@type qf-rancher.Window

local api = vim.api

---@mod Sort Sort list items
---@tag qf-rancher-sort
---@tag qfr-sort
---@brief [[
---
---@brief ]]

--- @class qf-rancher.Sort
local Sort = {}

---@tag qf-rancher-sort-predicate
---@tag qfr-sort-predicate
---@alias qf-rancher.sort.Predicate fun(a:vim.quickfix.entry, b:vim.quickfix.entry): boolean

---@param predicate qf-rancher.sort.Predicate A function to sort the list
---items
---
---@param src_win integer|nil Optional location list window context
---
---@param action qf-rancher.types.Action
---
---What action to take when setting the list
---
---@param nr integer|'$' Which list nr to operate on
---@return nil
function Sort.sort(predicate, src_win, action, nr)
    vim.validate("pred", predicate, "function")
    ry._validate_win(src_win, true)
    ry._validate_action(action)
    ry._validate_list_nr(nr)

    if src_win then
        local ok, msg, hl = ru._is_valid_loclist_win(src_win)
        if not ok then
            api.nvim_echo({ { msg, hl } }, false, {})
            return
        end
    end

    local what_ret = rt._get_list(src_win, { nr = nr, all = true }) ---@type table
    if what_ret.size <= 1 then
        api.nvim_echo({ { "Not enough entries to sort", "" } }, false, {})
        return
    end

    local what_set = rt._what_ret_to_set(what_ret)
    table.sort(what_set.items, predicate)
    what_set.nr = nr

    local dest_nr = rt._set_list(src_win, action, what_set)
    if dest_nr < 1 then
        api.nvim_echo({ { "Unable to set list", "ErrorMsg" } }, true, {})
        return
    end

    if not vim.g.qfr_auto_open_changes then
        return
    end

    local _, _, _ = ra._goto_history(src_win, dest_nr, { silent = true })
    rw._open_list(src_win, {
        close_others = true,
        silent = true,
        on_list = function(list_win, _)
            api.nvim_set_current_win(list_win)
            rw._resize_list_win(list_win)
        end,
    })
end

---@package
---@class qf-rancher.sort.CmdInfo
---@field asc qf-rancher.sort.Predicate Predicate for asc Sort.sorts
---@field desc qf-rancher.sort.Predicate Predicate for desc Sort.sorts

---@type table<string, qf-rancher.sort.CmdInfo>
local sort_cmds = {
    fname = { asc = lib.sort_fname_asc, desc = lib.sort_fname_desc },
    fname_diag = { asc = lib.sort_fname_diag_asc, desc = lib.sort_fname_diag_desc },
    severity = { asc = lib.sort_severity_asc, desc = lib.sort_severity_desc },
    text = { asc = lib.sort_text_asc, desc = lib.sort_text_desc },
    type = { asc = lib.sort_type_asc, desc = lib.sort_type_desc },
}

---@param src_win integer|nil
---@param cargs vim.api.keyset.create_user_command.command_args
---@return nil
local function sort_cmd(src_win, cargs)
    local sort_names = vim.tbl_keys(sort_cmds) ---@type string[]

    local sort_name = ru._check_cmd_arg(cargs.fargs, sort_names, "fname")
    local dir = cargs.bang and "desc" or "asc" ---@type "asc"|"desc"
    local predicate = sort_cmds[sort_name][dir]
    local action = "u" ---@type qf-rancher.types.Action

    Sort.sort(predicate, src_win, action, cargs.count)
end

---@brief [[
---The callbacks to assign the Qsort and Lsort commands are below. They
---expect count = 0 and nargs = 1 to be present in the user_command table.
---
---They accept the following options:
---- A registered sort name (fname|fname_diag|severity|text|type)
---  fname is the default
---  NOTE: fname_diag Sort.sorts by filename, with subsorting by diagnostic
---  severity
---- If a bang is provided, the sort will be in descending order
---
---If a count is provided, that list nr will be used. Default is the current
---list
---Example: 4Qsort! fname r
---@brief ]]

---@param cargs vim.api.keyset.create_user_command.command_args
---@return nil
Sort.q_sort = function(cargs)
    sort_cmd(nil, cargs)
end

---@param cargs vim.api.keyset.create_user_command.command_args
---@return nil
Sort.l_sort = function(cargs)
    sort_cmd(api.nvim_get_current_win(), cargs)
end

return Sort

---@export Sort
