local ra = Qfr_Defer_Require("qf-rancher.stack") ---@type QfrStack
local rt = Qfr_Defer_Require("qf-rancher.tools") ---@type QfrTools
local ru = Qfr_Defer_Require("qf-rancher.util") ---@type QfrUtil
local ry = Qfr_Defer_Require("qf-rancher.types") ---@type QfrTypes

local api = vim.api
local fn = vim.fn

---@mod Sort Sends diags to the qf list
---@tag qf-rancher-sort
---@tag qfr-sort
---@brief [[
---
---@brief ]]

--- @class QfRancherSort
local Sort = {}

-- =============
-- == Wrapper ==
-- =============

---@param sort_info QfrSortInfo
---@param sort_opts QfrSortOpts
---@param output_opts QfrOutputOpts
---@return nil
local function sort_wrapper(sort_info, sort_opts, output_opts)
    ry._validate_sort_info(sort_info)
    ry._validate_sort_opts(sort_opts)
    ry._validate_output_opts(output_opts)

    local src_win = output_opts.src_win ---@type integer|nil
    if src_win and not ru._valid_win_for_loclist(src_win) then return end

    local what_ret = rt._get_list(src_win, { nr = output_opts.what.nr, all = true }) ---@type table
    if what_ret.size <= 1 then
        api.nvim_echo({ { "Not enough entries to sort", "" } }, false, {})
        return
    end

    ---@type QfrSortPredicate
    local predicate = sort_opts.dir == "asc" and sort_info.asc_func or sort_info.desc_func
    local what_set = rt._what_ret_to_set(what_ret) ---@type QfrWhat
    table.sort(what_set.items, predicate)
    what_set.nr = output_opts.what.nr

    local dest_nr = rt._set_list(src_win, output_opts.action, what_set) ---@type integer
    if ru._get_g_var("qfr_auto_open_changes") then
        ra._get_history(src_win, dest_nr, {
            open_list = true,
            default = "cur_list",
            silent = true,
        })
    end
end

-- ================
-- == Sort Parts ==
-- ================

-- NOTE: Do not use ternaries here, as it causes logical errors

---@type QfrCheckFunc
local function check_asc(a, b)
    return a < b
end

---@type QfrCheckFunc
local function check_desc(a, b)
    return a > b
end

---@param a any
---@param b any
---@param check QfrCheckFunc
---@return boolean|nil
local function a_b_check(a, b, check)
    if not (a and b) then return nil end

    if a == b then
        return nil
    else
        return check(a, b)
    end
end

---@param a table
---@param b table
---@return string|nil, string|nil
local function get_fnames(a, b)
    if not (a.bufnr and b.bufnr) then return nil, nil end

    local fname_a = fn.bufname(a.bufnr) ---@type string|nil
    local fname_b = fn.bufname(b.bufnr) ---@type string|nil
    return fname_a, fname_b
end

---@param a table
---@param b table
---@param check QfrCheckFunc
---@return boolean|nil
local function check_fname(a, b, check)
    local fname_a, fname_b = get_fnames(a, b) ---@type string|nil, string|nil
    return a_b_check(fname_a, fname_b, check)
end

---@param a table
---@param b table
---@param check QfrCheckFunc
---@return boolean|nil
local function check_lcol(a, b, check)
    local checked_lnum = a_b_check(a.lnum, b.lnum, check) ---@type boolean|nil
    if type(checked_lnum) == "boolean" then return checked_lnum end

    local checked_col = a_b_check(a.col, b.col, check) ---@type boolean|nil
    if type(checked_col) == "boolean" then return checked_col end

    local checked_end_lnum = a_b_check(a.end_lnum, b.end_lnum, check) ---@type boolean|nil
    if type(checked_end_lnum) == "boolean" then return checked_end_lnum end

    return a_b_check(a.end_col, b.end_col, check) -- Return the nil here if we get it
end

---@param a table
---@param b table
---@return boolean|nil
local function check_fname_lcol(a, b, check)
    local checked_fname = check_fname(a, b, check) ---@type boolean|nil
    if type(checked_fname) == "boolean" then return checked_fname end

    return check_lcol(a, b, check) -- Allow the nil to pass through
end

---@param a table
---@param b table
---@param check QfrCheckFunc
---@return boolean|nil
local function check_lcol_type(a, b, check)
    local checked_lcol = check_lcol(a, b, check) ---@type boolean|nil
    if type(checked_lcol) == "boolean" then return checked_lcol end

    return a_b_check(a.type, b.type, check)
end

---@type table<string, integer>
local severity_unmap = ry._severity_unmap

---@param a table
---@param b table
---@return integer|nil, integer|nil
local function get_severities(a, b)
    if not (a.type and b.type) then return nil, nil end

    local severity_a = severity_unmap[a.type] or nil ---@type integer|nil
    local severity_b = severity_unmap[b.type] or nil ---@type integer|nil
    return severity_a, severity_b
end

---@param a table
---@param b table
---@return boolean|nil
local function check_severity(a, b, check)
    local severity_a, severity_b = get_severities(a, b) ---@type integer|nil, integer|nil
    return a_b_check(severity_a, severity_b, check)
end

---@param a table
---@param b table
---@return boolean|nil
local function check_lcol_severity(a, b, check)
    local checked_lcol = check_lcol(a, b, check) ---@type boolean|nil
    if type(checked_lcol) == "boolean" then return checked_lcol end

    return check_severity(a, b, check) -- Allow the nil to pass through
end

-- ===============
-- == Sort Info ==
-- ===============

---@param a vim.quickfix.entry
---@param b vim.quickfix.entry
---@param check QfrCheckFunc
---@return boolean
local function sort_fname(a, b, check)
    if not (a and b) then return false end

    local checked_fname = check_fname(a, b, check) ---@type boolean|nil
    if type(checked_fname) == "boolean" then return checked_fname end

    local checked_lcol_type = check_lcol_type(a, b, check_asc) ---@type boolean|nil
    if type(checked_lcol_type) == "boolean" then
        return checked_lcol_type
    else
        return false
    end
end

---@param a vim.quickfix.entry
---@param b vim.quickfix.entry
---@param check QfrCheckFunc
---@return boolean
local function sort_text(a, b, check)
    if not (a and b) then return false end

    local a_trim = a.text:gsub("^%s*(.-)%s*$", "%1") ---@type string
    local b_trim = b.text:gsub("^%s*(.-)%s*$", "%1") ---@type string

    local checked_text = a_b_check(a_trim, b_trim, check) ---@type boolean|nil
    if type(checked_text) == "boolean" then return checked_text end

    local checked_fname_lcol = check_fname_lcol(a, b, check_asc) ---@type boolean|nil
    if type(checked_fname_lcol) == "boolean" then
        return checked_fname_lcol
    else
        return false
    end
end

---@param a vim.quickfix.entry
---@param b vim.quickfix.entry
---@param check QfrCheckFunc
---@return boolean
local function sort_type(a, b, check)
    if not (a and b) then return false end

    local checked_type = a_b_check(a.type, b.type, check) ---@type boolean|nil
    if type(checked_type) == "boolean" then return checked_type end

    local checked_fname_lcol = check_fname_lcol(a, b, check_asc) ---@type boolean|nil
    if type(checked_fname_lcol) == "boolean" then
        return checked_fname_lcol
    else
        return false
    end
end

---@param a vim.quickfix.entry
---@param b vim.quickfix.entry
---@param check QfrCheckFunc
---@return boolean
local function sort_severity(a, b, check)
    if not (a and b) then return false end

    local checked_severity = check_severity(a, b, check) ---@type boolean|nil
    if type(checked_severity) == "boolean" then return checked_severity end

    local checked_fname_lcol = check_fname_lcol(a, b, check_asc) ---@type boolean|nil
    checked_fname_lcol = checked_fname_lcol == nil and false or checked_fname_lcol
    if type(checked_fname_lcol) == "boolean" then
        return checked_fname_lcol
    else
        return false
    end
end

---@param a vim.quickfix.entry
---@param b vim.quickfix.entry
---@param check QfrCheckFunc
---@return boolean
local function sort_diag_fname(a, b, check)
    if not (a and b) then return false end

    local checked_fname = check_fname(a, b, check) ---@type boolean|nil
    if type(checked_fname) == "boolean" then return checked_fname end

    local checked_lcol_severity = check_lcol_severity(a, b, check_asc) ---@type boolean|nil
    if type(checked_lcol_severity) == "boolean" then
        return checked_lcol_severity
    else
        return false
    end
end

-- =========
-- == API ==
-- =========

---@tag qf-rancher-sort-predicate
---@tag qfr-sort-predicate
---Parameters:
---- vim.qflist.item (first item to sort)
---- vim.qflist.item (second item to sort)
---Return: Boolean
---@alias QfrSortPredicate fun(vim.qflist.item, vim.qflist.item): boolean

---@tag qf-rancher-sort-info
---@tag qfr-sort-info
---@class QfrSortInfo
---@field name string The name of the sort
---@field asc_func QfrSortPredicate Predicate for asc sorts
---@field desc_func QfrSortPredicate Predicate for desc sorts

---@tag qf-rancher-sort-opts
---@tag qfr-sort-opts
---@class QfrSortOpts
---@field dir QfrSortDir "asc"|"desc"

-- MID: The sort predicates are here first so they load properly into the sorts table. This is
-- not the best presentation

---@brief [[
---The below sort predicates are exposed for use in other functions. All have
---the type |QfrSortPredicate|
---@brief ]]

---@type QfrSortPredicate
---Sort by filename asc. Break ties with line and column numbers
function Sort.sort_fname_asc(a, b)
    return sort_fname(a, b, check_asc)
end

---@type QfrSortPredicate
---Sort by filename desc. Break ties with line and column numbers
function Sort.sort_fname_desc(a, b)
    return sort_fname(a, b, check_desc)
end

---@type QfrSortPredicate
---Sort by text asc
function Sort.sort_text_asc(a, b)
    return sort_text(a, b, check_asc)
end

---@type QfrSortPredicate
---Sort by text desc
function Sort.sort_text_desc(a, b)
    return sort_text(a, b, check_desc)
end

---@type QfrSortPredicate
---Sort by list item type asc
function Sort.sort_type_asc(a, b)
    return sort_type(a, b, check_asc)
end

---@type QfrSortPredicate
---Sort by list item type desc
function Sort.sort_type_desc(a, b)
    return sort_type(a, b, check_desc)
end

---@type QfrSortPredicate
---Sort by filename asc, break ties by diagnostic severity
function Sort.sort_fname_diag_asc(a, b)
    return sort_diag_fname(a, b, check_asc)
end

---@type QfrSortPredicate
---Sort by filename desc, break ties by diagnostic severity
function Sort.sort_fname_diag_desc(a, b)
    return sort_diag_fname(a, b, check_desc)
end

---@type QfrSortPredicate
---Sort by diagnostic severity asc
function Sort.sort_severity_asc(a, b)
    return sort_severity(a, b, check_asc)
end

---@type QfrSortPredicate
---Sort by diagnostic severity desc
function Sort.sort_severity_desc(a, b)
    return sort_severity(a, b, check_desc)
end

local sorts = {
    fname = { name = "fname", asc_func = Sort.sort_fname_asc, desc_func = Sort.sort_fname_desc },
    fname_diag = {
        name = "fname_diag",
        asc_func = Sort.sort_fname_diag_asc,
        desc_func = Sort.sort_fname_diag_desc,
    },
    severity = {
        name = "severity",
        asc_func = Sort.sort_severity_asc,
        desc_func = Sort.sort_severity_desc,
    },
    text = { name = "text", asc_func = Sort.sort_text_asc, desc_func = Sort.sort_text_desc },
    type = { name = "type", asc_func = Sort.sort_type_asc, desc_func = Sort.sort_type_desc },
} ---@type table<string, QfrSortInfo>

---Run a registered sort
---@param name string Which registered sort to run
---@param sort_opts QfrSortOpts See |qfr-sort-opts|
---@param output_opts QfrOutputOpts See |qfr-output-opts|
---@return nil
function Sort.sort(name, sort_opts, output_opts)
    local sort_info = sorts[name] ---@type QfrSortInfo
    if not sort_info then
        api.nvim_echo({ { "Invalid sort", "ErrorMsg" } }, true, { err = true })
    end

    sort_wrapper(sort_info, sort_opts, output_opts)
end

---@return string[]
local function get_sort_names()
    return vim.tbl_keys(sorts)
end

---Register a sort for use in commands and API calls
---@param sort_info QfrSortInfo See |qfr-sort-info| The sort will be
---registered under the name provided in this table
---@return nil
function Sort.register_sort(sort_info)
    sorts[sort_info.name] = sort_info
end

--- Clears the function name from the registered sorts
---@param name string
function Sort.clear_sort(name)
    if #vim.tbl_keys(sorts) <= 1 then
        api.nvim_echo({ { "Cannot remove the last sort method" } }, false, {})
        return
    end

    if sorts[name] then
        sorts[name] = nil
        api.nvim_echo({ { name .. " removed from the sort list", "" } }, true, {})
    else
        api.nvim_echo({ { name .. " is not a registered sort", "" } }, true, {})
    end
end

-- ===============
-- == CMD FUNCS ==
-- ===============

---@param src_win integer|nil
---@param cargs vim.api.keyset.create_user_command.command_args
---@return nil
local function sort_cmd(src_win, cargs)
    local fargs = cargs.fargs

    local sort_names = get_sort_names() ---@type string[]
    assert(#sort_names >= 1, "No sort functions available")
    ---@type string
    local default_sort = vim.tbl_contains(sort_names, "fname") and "fname" or sort_names[1]
    local sort_name = ru._check_cmd_arg(fargs, sort_names, default_sort) ---@type string
    local dir = cargs.bang and "desc" or "asc"

    ---@type QfrAction
    local action = ru._check_cmd_arg(fargs, ry._actions, "u")
    ---@type QfrOutputOpts
    local output_opts = { src_win = src_win, action = action, what = { nr = cargs.count } }

    Sort.sort(sort_name, { dir = dir }, output_opts)
end

---@brief [[
---The callbacks to assign the Qsort and Lsort commands are below. They
---expect count = 0 and nargs = 1 to be present in the user_command table.
---They accept the following options:
---- A registered sort name (fname|fname_diag|severity|text|type)
---  fname is the default
---  NOTE: fname_diag sorts by filename, with subsorting by diagnostic
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

return Sort
---@export Sort
