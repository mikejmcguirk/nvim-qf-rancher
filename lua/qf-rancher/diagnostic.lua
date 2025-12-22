local ra = Qfr_Defer_Require("qf-rancher.stack") ---@type qf-rancher.Stack
local rs_lib = Qfr_Defer_Require("qf-rancher.lib.sort") ---@type qf-rancher.lib.Sort
local rt = Qfr_Defer_Require("qf-rancher.tools") ---@type qf-rancher.Tools
local ru = Qfr_Defer_Require("qf-rancher.util") ---@type qf-rancher.Util
local rw = Qfr_Defer_Require("qf-rancher.window") ---@type qf-rancher.Window
local ry = Qfr_Defer_Require("qf-rancher.types") ---@type qf-rancher.Types

local api = vim.api
local ds = vim.diagnostic.severity

---@mod Diag Sends diags to the qf list
---@tag qf-rancher-diagnostics
---@tag qfr-diagnostics
---@brief [[
---
---@brief ]]

--- @class QfRancherDiagnostics
local Diag = {}

-- ===================
-- == DIAGS TO LIST ==
-- ===================

-- LOW: I assume there is a more performant way to do this

---@param diags vim.Diagnostic[]
---@return vim.Diagnostic[]
local function filter_diags_top_severity(diags)
    -- LOW: Gate a validation of the individual diags behind the debug g:var
    vim.validate("diags", diags, "table")

    local top_severity = ds.HINT ---@type vim.diagnostic.Severity
    for _, diag in ipairs(diags) do
        if diag.severity < top_severity then
            top_severity = diag.severity
        end

        if top_severity == ds.ERROR then
            break
        end
    end

    return vim.tbl_filter(function(diag)
        return diag.severity == top_severity
    end, diags)
end

-- LOW: Does this actually help/matter?
local severity_map = ry._severity_map ---@type table<integer, string>

-- MID: The runtime's add function in get_diagnostics clamps the lnum values to buf_line_count
-- Awkward to add here because the conversion is outlined, and maybe not necessary, but does
-- help with safety for stale diags

---@type qf-rancher.diag.DisplayFunc
local function convert_diag(d)
    local source = d.source and d.source .. ": " or "" ---@type string
    return {
        bufnr = d.bufnr,
        col = d.col and (d.col + 1) or nil,
        end_col = d.end_col and (d.end_col + 1) or nil,
        end_lnum = d.end_lnum and (d.end_lnum + 1) or nil,
        lnum = d.lnum + 1,
        nr = tonumber(d.code),
        text = source .. (d.message or ""),
        type = severity_map[d.severity] or "E",
        valid = 1,
    }
end

---@param getopts? vim.diagnostic.GetOpts
---@return string
local function get_empty_msg(getopts)
    ry._validate_diag_getopts(getopts, true)

    local default = "No diagnostics" ---@type string

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

    local min_hint = min == ds.HINT ---@type boolean
    local max_error = type(max) == "nil" or max == ds.ERROR ---@type boolean
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
        parts[#parts + 1] = "max: " .. max_txt
    end

    local minmax_txt = table.concat(parts, " ,")
    return default .. " (" .. minmax_txt .. ")"
end

-- MID: I'm fine tossing the diag_opts here for now, but once that construct is gone or revised,
-- revisit what data is sent into here
---@param diag_opts qf-rancher.diag.DiagOpts
---@return boolean
local function should_clear(diag_opts)
    if not (diag_opts.getopts and diag_opts.getopts.severity) then
        return true
    elseif diag_opts.getopts.severity == { min = ds.INFO } then
        return true
    elseif diag_opts.getopts.severity == { min = nil } then
        return true
    else
        return false
    end
end

---@class qf-rancher.diag.DiagOpts
---
---List entry conversion function
---@field disp_func? qf-rancher.diag.DisplayFunc
---@field top? boolean If true, only show top severity
---@field getopts? vim.diagnostic.GetOpts See |vim.diagnostic.Getopts|

-- TODO: Remove output_opts. Re-evaluate diag_opts
-- TODO: When re-doing params, allow a custom sort function to be added in
-- TODO: Worth considering the lessons learned when redoing grep - A table allows for handling the
-- various combinatorial possibilities

---
---Convert diagnostics into list entries
---
---In line with Neovim's default, the list title will be "Diagnostics"
---
---If g:qfr_reuse_title is true, output_opts.action is " ", and a list with
---the title "Diagnostics" already exists, it will be re-used
---
---If a query is made for all diagnostics in a scope, and no results return,
---the "Diagnostics" list will be automatically cleared
---
---@param diag_opts qf-rancher.diag.DiagOpts
---@param output_opts QfrOutputOpts See |qfr-output-opts|
---@return nil
function Diag.diags_to_list(diag_opts, output_opts)
    ry._validate_diag_opts(diag_opts)
    ry._validate_output_opts(output_opts)
    diag_opts = vim.deepcopy(diag_opts, true)
    output_opts = vim.deepcopy(output_opts, true)

    local src_win = output_opts.src_win ---@type integer|nil
    if src_win then
        local ok, msg, hl = ru._is_valid_loclist_win(src_win)
        if not ok then
            api.nvim_echo({ { msg, hl } }, false, {})
            return
        end
    end

    local title = "Diagnostics" ---@type string
    output_opts.what.title = title

    local buf = src_win and api.nvim_win_get_buf(src_win) or nil ---@type integer|nil
    local raw_diags = vim.diagnostic.get(buf, diag_opts.getopts) ---@type vim.Diagnostic[]
    if #raw_diags == 0 then
        local msg = get_empty_msg(diag_opts.getopts)
        api.nvim_echo({ { msg, "" } }, false, {})
        if not vim.g.qfr_reuse_title then
            return
        end

        local cur_diag_nr = rt._find_list_with_title(src_win, title) ---@type integer|nil
        if not cur_diag_nr then
            return
        end

        if should_clear(diag_opts) then
            if cur_diag_nr then
                local max_nr = rt._get_list(src_win, { nr = "$" }).nr ---@type integer
                if max_nr == 1 then
                    rt._set_list(src_win, "f", {})
                else
                    -- MID: Should also go to an active list, but would need to write a func for
                    -- that
                    local result = rt._clear_list(src_win, cur_diag_nr)
                    if vim.g.qfr_auto_list_height and result >= 0 then
                        local tabpage = src_win and api.nvim_win_get_tabpage(src_win)
                            or api.nvim_get_current_tabpage()
                        rw._resize_list_wins(src_win, { tabpage })
                    end
                end
            end
        end

        return
    end

    if diag_opts.top then
        raw_diags = filter_diags_top_severity(raw_diags)
    end

    local disp_func = diag_opts.disp_func or convert_diag ---@type qf-rancher.diag.DisplayFunc
    local converted_diags = vim.tbl_map(disp_func, raw_diags) ---@type vim.quickfix.entry[]
    table.sort(converted_diags, rs_lib.sort_fname_diag_asc)

    if vim.g.qfr_reuse_title then
        local cur_diag_nr = rt._find_list_with_title(src_win, title) ---@type integer|nil
        if cur_diag_nr then
            output_opts.action = "u"
            output_opts.what.nr = cur_diag_nr
        end
    end

    local what_set = vim.tbl_deep_extend("force", output_opts.what, {
        items = converted_diags,
        title = title,
    }) ---@type qf-rancher.types.What

    local dest_nr = rt._set_list(src_win, output_opts.action, what_set) ---@type integer
    if dest_nr > 0 and vim.g.qfr_auto_open_changes then
        ---@type integer, integer, string|nil
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

-- ===============
-- == CMD FUNCS ==
-- ===============

-- LOW: Figure out how to customize diag cmd mappings. Could just do cmd registration, but that
-- would then sit on top of the default cmd structure. Feels more natural to figure out a
-- cmd syntax that allows for arriving at the various combinations of getopts
-- - NOTE: This would require adding validation for the registered diag filters

---@type table <string, vim.diagnostic.Severity>
local level_map = { hint = ds.HINT, info = ds.INFO, warn = ds.WARN, error = ds.ERROR }

---@param src_win integer|nil
---@param cargs vim.api.keyset.create_user_command.command_args
---@return nil
local function unpack_diag_cmd(src_win, cargs)
    ry._validate_win(src_win, true)

    local fargs = cargs.fargs ---@type string[]

    local top = vim.tbl_contains(fargs, "top") and true or false ---@type boolean

    local getopts = (function()
        if top then
            return { severity = nil }
        end

        local levels = vim.tbl_keys(level_map) ---@type string[]
        local level = ru._check_cmd_arg(fargs, levels, "hint") ---@type string
        local severity = level_map[level] ---@type vim.diagnostic.Severity

        if cargs.bang then
            return { severity = severity }
        end

        severity = severity == ds.HINT and nil or severity
        return { severity = { min = severity } }
    end)() ---@type vim.diagnostic.GetOpts

    local diag_opts = { top = top, getopts = getopts } ---@type qf-rancher.diag.DiagOpts

    ---@type qf-rancher.types.Action
    local action = ru._check_cmd_arg(fargs, ry._actions, " ")
    ---@type QfrOutputOpts
    local output_opts = { src_win = src_win, action = action, what = { nr = cargs.count } }

    Diag.diags_to_list(diag_opts, output_opts)
end

---@brief [[
---The callbacks to assign the Qdiag and Ldiag commands are below. They expect
---count = 0, nargs = "*", and bang = true to be in the user_command table.
---
---Qdiag checks all open buffers. Ldiag checks the current buffer
---
---They accept the following options:
---- A diagnostic severity ("error"|"warn"|"hint"|"info") or "top"
---- A |setqflist-action| (default " ")
---
---If a bang is provided, only the specified severity will be shown
---
---Examples:
---Qdiag error [show all errors]
---Ldiag! warn only [show only warnings from the current buffer]
---@brief ]]

---@param cargs vim.api.keyset.create_user_command.command_args
---@return nil
function Diag.q_diag_cmd(cargs)
    unpack_diag_cmd(nil, cargs)
end

---@param cargs vim.api.keyset.create_user_command.command_args
---@return nil
function Diag.l_diag_cmd(cargs)
    unpack_diag_cmd(api.nvim_get_current_win(), cargs)
end

return Diag
---@export Diag

-- MID: Ability to select/map based on namespace
-- MID: Possibly related to the above - query by diagnostic producer(s). Glancing at the built-in
-- code, each LSP has its own namespace. Should be able to make a convenience function to get
-- the namespace from the LSP name
