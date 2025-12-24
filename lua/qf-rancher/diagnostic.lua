local rs_lib = Qfr_Defer_Require("qf-rancher.lib.sort") ---@type qf-rancher.lib.Sort
local rt = Qfr_Defer_Require("qf-rancher.tools") ---@type qf-rancher.Tools
local ru = Qfr_Defer_Require("qf-rancher.util") ---@type qf-rancher.Util
local rw = Qfr_Defer_Require("qf-rancher.window") ---@type qf-rancher.Window
local ry = Qfr_Defer_Require("qf-rancher.types") ---@type qf-rancher.Types

local api = vim.api
local ds = vim.diagnostic.severity

-- LOW: I assume there is a more performant way to do this

---@param diags vim.Diagnostic[]
---@return vim.Diagnostic[]
local function filter_diags_top_severity(diags)
    local ds_error = ds.ERROR ---@type vim.diagnostic.Severity
    local top_severity = ds.HINT ---@type vim.diagnostic.Severity

    for _, diag in ipairs(diags) do
        if diag.severity < top_severity then
            top_severity = diag.severity
        end

        if top_severity == ds_error then
            break
        end
    end

    local filtered = {} ---@type vim.Diagnostic[]
    for _, diag in ipairs(diags) do
        if diag.severity == top_severity then
            filtered[#filtered + 1] = diag
        end
    end

    return filtered
end

local severity_map = ry._severity_map ---@type table<integer, string>

---@param diag vim.Diagnostic
---@return vim.quickfix.entry
local function convert_diag(diag)
    local source = diag.source and diag.source .. ": " or ""
    return {
        bufnr = diag.bufnr,
        col = diag.col and (diag.col + 1) or nil,
        end_col = diag.end_col and (diag.end_col + 1) or nil,
        end_lnum = diag.end_lnum and (diag.end_lnum + 1) or nil,
        lnum = diag.lnum + 1,
        nr = tonumber(diag.code),
        text = source .. (diag.message or ""),
        type = severity_map[diag.severity] or "E",
        valid = 1,
    }
end

---@param getopts? vim.diagnostic.GetOpts
---@return string
local function get_empty_msg(getopts)
    local default = "No diagnostics"
    if not (getopts and getopts.severity) then
        return default
    end

    if type(getopts.severity) == "number" then
        local plural = ry._severity_map_plural[getopts.severity] ---@type string|nil
        if plural then
            return "No " .. plural
        end

        return default
    end

    local min = getopts.severity.min ---@type integer|nil
    local max = getopts.severity.max ---@type integer|nil
    if not (min or max) then
        return default
    end

    local min_hint = min == ds.HINT
    local max_error = type(max) == "nil" or max == ds.ERROR
    if min_hint and max_error then
        return default
    end

    local min_txt = min and ry._severity_map_str[min]
    local max_txt = max and ry._severity_map_str[max]
    if not (min_txt or max_txt) then
        return default
    end

    local parts = {}
    if min_txt then
        parts[#parts + 1] = "Min: " .. min_txt
    end

    if max_txt then
        parts[#parts + 1] = "Max: " .. max_txt
    end

    local minmax_txt = table.concat(parts, " ,")
    return default .. " (" .. minmax_txt .. ")"
end

---@param diag_opts qf-rancher.diag.DiagOpts
---@return boolean
local function should_clear(diag_opts)
    if not (diag_opts.getopts and diag_opts.getopts.severity) then
        return true
    elseif diag_opts.getopts.severity == { min = ds.INFO } then
        return true
    elseif diag_opts.getopts.severity == { min = nil } then
        return true
    end

    return false
end

---@param src_win integer|nil
---@param title string
---@param diag_opts qf-rancher.diag.DiagOpts
---@return string, string
local function handle_no_diags(src_win, title, diag_opts)
    local msg = get_empty_msg(diag_opts.getopts)
    local hl = ""

    if not vim.g.qfr_reuse_title then
        return msg, hl
    end

    local cur_nr = rt._find_list_with_title(src_win, title)
    if not cur_nr then
        return msg, hl
    end

    local do_clear = should_clear(diag_opts)
    if not do_clear then
        return msg, hl
    end

    local max_nr = rt._get_list(src_win, { nr = "$" }).nr ---@type integer
    if max_nr == 1 then
        rt._set_list(src_win, "f", {})
        rw._close_list(src_win, { silent = true, use_alt_win = true })
        return msg, hl
    end

    local result = rt._clear_list(src_win, cur_nr)
    if not (vim.g.qfr_auto_list_height and result >= 0) then
        return msg, hl
    end

    local tabpage = src_win and api.nvim_win_get_tabpage(src_win) or api.nvim_get_current_tabpage()
    rw._resize_list_wins(src_win, { tabpage })
    return msg, hl
end

---@param diag_opts qf-rancher.diag.DiagOpts
---@return nil
local function validate_diag_opts(diag_opts)
    vim.validate("diag_opts", diag_opts, "table")
    vim.validate("diag_opts.disp_func", diag_opts.disp_func, "callable", true)
    vim.validate("diag_opts.sort_func", diag_opts.sort_func, "callable", true)
    vim.validate("diag_opts.top", diag_opts.top, "boolean", true)
    ry._validate_diag_getopts(diag_opts.getopts, true)
end

---@param src_win integer|nil
---@param action qf-rancher.types.Action
---@param what qf-rancher.types.What
---@param diag_opts qf-rancher.diag.DiagOpts
---@return nil
local function validate_diags_to_list_params(src_win, action, what, diag_opts)
    ry._validate_win(src_win, true)
    ry._validate_action(action)
    ry._validate_what(what)
    validate_diag_opts(diag_opts)
end

---@mod Diag Sends diags to the qf list
---@tag qf-rancher-diagnostics
---@tag qfr-diagnostics
---@brief [[
---
---@brief ]]

--- @class QfRancherDiagnostics
local Diag = {}

---@class qf-rancher.diag.DiagOpts
---
---List entry conversion function
---@field disp_func? fun(diag: vim.Diagnostic):vim.quickfix.entry
---@field getopts? vim.diagnostic.GetOpts See |vim.diagnostic.Getopts|
---
---See |qf-rancher.sort.Predicate|
---@field sort_func? qf-rancher.sort.Predicate
---@field top? boolean If true, only show top severity

---
---Convert diagnostics into list entries.
---
---In line with Neovim's default, the list title will be "Diagnostics".
---
---If g:qfr_reuse_title is true, action is " ", and a list with the title
---"Diagnostics" already exists, it will be re-used.
---
---If a query is made for all diagnostics in a scope, and no results return,
---the "Diagnostics" list will be automatically cleared.
---
---@param src_win integer|nil Location list window context. Nil for
---qflist
---@param action qf-rancher.types.Action See |setqflist-action|
---@param what? qf-rancher.types.What See |setqflist-what|
---@param diag_opts? qf-rancher.diag.DiagOpts See |qf-rancher.diag.DiagOpts|
---@return nil
function Diag.diags_to_list(src_win, action, what, diag_opts)
    what = what and vim.deepcopy(what, true) or {}
    diag_opts = diag_opts and vim.deepcopy(diag_opts, true) or {}
    validate_diags_to_list_params(src_win, action, what, diag_opts)

    if src_win then
        local ok, msg, hl = ru._is_valid_loclist_win(src_win)
        if not ok then
            api.nvim_echo({ { msg, hl } }, false, {})
            return
        end
    end

    local buf = src_win and api.nvim_win_get_buf(src_win) or nil ---@type integer|nil
    local raw_diags = vim.diagnostic.get(buf, diag_opts.getopts)
    local title = "Diagnostics"
    if #raw_diags == 0 then
        local msg, hl = handle_no_diags(src_win, title, diag_opts)
        ru._echo(false, msg, hl)
        return
    end

    if diag_opts.top then
        raw_diags = filter_diags_top_severity(raw_diags)
    end

    local disp_func = diag_opts.disp_func or convert_diag
    local converted_diags = {} ---@type vim.quickfix.entry[]
    for _, diag in ipairs(raw_diags) do
        local converted = disp_func(diag)
        converted_diags[#converted_diags + 1] = converted
    end

    local predicate = diag_opts.sort_func or rs_lib.sort_fname_diag_asc
    table.sort(converted_diags, predicate)
    what.items = converted_diags

    what.title = title
    action, what = rt._resolve_title_reuse(src_win, action, what)
    local dest_nr = rt._set_list(src_win, action, what)
    if dest_nr < 1 then
        api.nvim_echo({ { "Unable to set list", "ErrorMsg" } }, true, {})
        return
    end

    if not vim.g.qfr_auto_open_changes then
        return
    end

    local ra = require("qf-rancher.stack")
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

---@type table <string, vim.diagnostic.Severity>
local level_map = { hint = ds.HINT, info = ds.INFO, warn = ds.WARN, error = ds.ERROR }

-- MID: Prefix the severity with some kind of special character

---@param src_win integer|nil
---@param cargs vim.api.keyset.create_user_command.command_args
---@return nil
local function diag_cmd(src_win, cargs)
    ry._validate_win(src_win, true)

    local fargs = cargs.fargs ---@type string[]
    local top = vim.tbl_contains(fargs, "top") and true or false ---@type boolean
    local getopts = (function()
        if top then
            return { severity = nil }
        end

        local levels = vim.tbl_keys(level_map) ---@type string[]
        local level = ru._check_cmd_arg(fargs, levels, "hint") ---@type string
        local severity = level_map[level] ---@type vim.diagnostic.Severity|nil

        if cargs.bang then
            return { severity = severity }
        end

        if severity == ds.HINT then
            severity = nil
        end

        return { severity = { min = severity } }
    end)() ---@type vim.diagnostic.GetOpts

    local diag_opts = { top = top, getopts = getopts } ---@type qf-rancher.diag.DiagOpts

    local nr = cargs.count > 0 and cargs.count or "$"
    local what = { nr = nr }
    local action = nr > 0 and "r" or " " ---@type qf-rancher.types.Action

    Diag.diags_to_list(src_win, action, what, diag_opts)
end

---@brief [[
---The callbacks to assign the Qdiag and Ldiag commands are below. They expect
---count = 0, nargs = "*", and bang = true to be in the user_command table.
---
---Qdiag checks all open buffers. Ldiag checks the current buffer
---
---They accept the following option:
---- A diagnostic severity ("error"|"warn"|"hint"|"info") or "top"
---
---If a bang is provided, only the specified severity will be shown
---
---If a count is provided, then [count] list will be overwritten. Otherwise, a
---new list will be created at the end of the stack.
---
---The output list will be given the title "Diagnostics". If no count is
---provided, g:qfr_reuse_title is true, and a list with that title exists, it
---will be reused.
---
---Examples:
---Qdiag error [show all errors]
---Ldiag! warn [show only warnings from the current buffer]
---@brief ]]

---@param cargs vim.api.keyset.create_user_command.command_args
---@return nil
function Diag.q_diag_cmd(cargs)
    diag_cmd(nil, cargs)
end

---@param cargs vim.api.keyset.create_user_command.command_args
---@return nil
function Diag.l_diag_cmd(cargs)
    local cur_win = api.nvim_get_current_win()
    diag_cmd(cur_win, cargs)
end

return Diag

---@export Diag

-- MAYBE: Add on_diag callback if #raw_diags > 0
