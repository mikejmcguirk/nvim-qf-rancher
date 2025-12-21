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

-- LOW: It would be neat if a what table were passed in instead of just the nr, but I would have to
-- think through how to merge the old list into the what table

---@tag qf-rancher-sort-predicate
---@tag qfr-sort-predicate
---Parameters:
---- vim.qflist.item (first item to sort)
---- vim.qflist.item (second item to sort)
---Return: Boolean
---@alias qf-rancher.sort.Predicate fun(vim.qflist.item, vim.qflist.item): boolean

---@param pred qf-rancher.sort.Predicate A function to sort the list items
---@param src_win integer|nil Optional location list window context
---@param action qf-rancher.types.Action What action to take when setting the list
---@param nr integer|'$' Which list nr to operate on
---@return nil
function Sort.sort(pred, src_win, action, nr)
    vim.validate("pred", pred, "function")
    ry._validate_win(src_win, true)
    ry._validate_action(action)
    ry._validate_list_nr(nr)

    if src_win and not ru._is_valid_loclist_win(src_win) then
        return
    end

    local what_ret = rt._get_list(src_win, { nr = nr, all = true }) ---@type table
    if what_ret.size <= 1 then
        api.nvim_echo({ { "Not enough entries to sort", "" } }, false, {})
        return
    end

    local what_set = rt._what_ret_to_set(what_ret)
    table.sort(what_set.items, pred)
    what_set.nr = nr

    local dest_nr = rt._set_list(src_win, action, what_set)
    if dest_nr > 0 and vim.g.qfr_auto_open_changes then
        local cur_nr, nr_after, _ = ra._goto_history(src_win, dest_nr, { silent = true })
        if cur_nr ~= nr_after and vim.g.qfr_auto_list_height then
            ra._resize_after_change(src_win)
        end

        rw._open_list(src_win, {
            close_others = true,
            silent = true,
            on_list = function(list_win, _)
                api.nvim_set_current_win(list_win)
            end,
        })
    end
end

---@tag qf-rancher-sort-info
---@tag qfr-sort-info
---@class qf-rancher.sort.Info
---@field asc qf-rancher.sort.Predicate Predicate for asc Sort.sorts
---@field desc qf-rancher.sort.Predicate Predicate for desc Sort.sorts

---Sorts available to the Qsort and Lsort cmds. The string table key can be
---fed to those cmds as an argument to use the sorts. Because this table is
---public, sorts can be directly added or removed
---Pre-built sorts are available in "qf-rancher.lib.sort"
---@type table<string, qf-rancher.sort.Info>
Sort.sorts = {
    fname = { asc = lib.sort_fname_asc, desc = lib.sort_fname_desc },
    fname_diag = { asc = lib.sort_fname_diag_asc, desc = lib.sort_fname_diag_desc },
    severity = { asc = lib.sort_severity_asc, desc = lib.sort_severity_desc },
    text = { asc = lib.sort_text_asc, desc = lib.sort_text_desc },
    type = { asc = lib.sort_type_asc, desc = lib.sort_type_desc },
}

---@alias QfrSortDir 'asc'|'desc'

---@param src_win integer|nil
---@param cargs vim.api.keyset.create_user_command.command_args
---@return nil
local function sort_cmd(src_win, cargs)
    local sort_names = vim.tbl_keys(Sort.sorts) ---@type string[]
    if #sort_names < 1 then
        api.nvim_echo({ { "No sorts available" } }, true, {})
        return
    end

    ---@type string
    local default_sort = vim.tbl_contains(sort_names, "fname") and "fname" or sort_names[1]
    local sort_name = ru._check_cmd_arg(cargs.fargs, sort_names, default_sort) ---@type string
    local dir = cargs.bang and "desc" or "asc" ---@type QfrSortDir
    ---@type qf-rancher.types.Action
    local action = ru._check_cmd_arg(cargs.fargs, ry._actions, "u")

    Sort.sort(Sort.sorts[sort_name][dir], src_win, action, cargs.count)
end

---@brief [[
---The callbacks to assign the Qsort and Lsort commands are below. They
---expect count = 0 and nargs = 1 to be present in the user_command table.
---They accept the following options:
---- A registered sort name (fname|fname_diag|severity|text|type)
---  fname is the default
---  NOTE: fname_diag Sort.sorts by filename, with subsorting by diagnostic
---  severity
---- A |setqflist-action| can also be provided (default "u")
---- If a bang is provided, the sort will be in descending order
---- If a count is provided, that list nr will be used. Default is the current
---  list
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

---@export Sort

return Sort
