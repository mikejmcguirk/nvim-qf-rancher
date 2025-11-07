local ra = Qfr_Defer_Require("qf-rancher.stack") ---@type QfrStack
local rt = Qfr_Defer_Require("qf-rancher.tools") ---@type QfrTools
local ru = Qfr_Defer_Require("qf-rancher.util") ---@type QfrUtil
local ry = Qfr_Defer_Require("qf-rancher.types") ---@type QfrTypes

local api = vim.api
local fn = vim.fn

---@mod Filter Filter list items
---@tag qf-rancher-filter
---@tag qfr-filter
---@brief [[
---
---@brief ]]

--- @class QfrFilter
local Filter = {}

---@param filter_info QfrFilterInfo
---@param keep boolean
---@param input_opts QfrInputOpts
---@param output_opts QfrOutputOpts
---@return nil
local function filter_wrapper(filter_info, keep, input_opts, output_opts)
    ry._validate_filter_info(filter_info)
    vim.validate("keep", keep, "boolean")
    ry._validate_input_opts(input_opts)
    ry._validate_output_opts(output_opts)

    local src_win = output_opts.src_win ---@type integer|nil
    if src_win and not ru._valid_win_for_loclist(src_win) then return end

    local what_ret = rt._get_list(src_win, { nr = output_opts.what.nr, all = true }) ---@type table
    if what_ret.size == 0 then
        api.nvim_echo({ { "No entries to filter", "" } }, false, {})
        return
    end

    local prompt = "Enter pattern to " .. (keep and "keep" or "remove") ---@type string
    local input_type = ru._resolve_input_vimcase(input_opts.input_type) ---@type QfrInputType
    local display_input_type = ru._get_display_input_type(input_type) ---@type string
    prompt = filter_info.name .. ": " .. prompt .. " (" .. display_input_type .. "): "

    local pattern = ru._resolve_pattern(prompt, input_opts.pattern, input_type) ---@type string|nil
    if not pattern then return end

    local regex = input_type == "regex" and vim.regex(pattern) or nil ---@type vim.regex|nil
    local lower_pattern = string.lower(pattern) ---@type string
    if input_type == "smartcase" then
        local is_smart_pattern = lower_pattern == pattern ---@type boolean
        input_type = is_smart_pattern and "insensitive" or "sensitive"
        pattern = is_smart_pattern and lower_pattern or pattern
    end

    local predicate = (function()
        if input_type == "regex" and regex then return filter_info.regex_func end
        if input_type == "sensitive" then return filter_info.sensitive_func end
        return filter_info.insensitive_func
    end)() ---@type QfrFilterPredicate

    what_ret.items = vim.tbl_filter(function(t)
        return predicate(t, keep, { pattern = pattern, regex = regex })
    end, what_ret.items) ---@type vim.quickfix.entry[]

    local what_set = rt._what_ret_to_set(what_ret) ---@type QfrWhat
    what_set.nr = output_opts.what.nr
    local dest_nr = rt._set_list(src_win, output_opts.action, what_set) ---@type integer
    if dest_nr >= 0 and ru._get_g_var("qfr_auto_open_changes") then
        ra._get_history(src_win, dest_nr, {
            open_list = true,
            default = "cur_list",
            silent = true,
        })
    end
end

-- NOTE: Insensitive functions assume the pattern is lowercase
-- NOTE: In line with Cfilter and the C code, bufname() is used for checking filenames
-- NOTE: x and y or z ternaries only work if y is truthy. Because keep can be either, don't use
-- ternaries here

-- LOW: Would like to eliminate the opts table from these functions entirely, but I'm not sure
-- what a less contrived way is to handle the possibilty of either pattern or regex being sent
-- to the predicate function

-- =======================
-- == BOILERPLATE LOGIC ==
-- =======================

---@param regex vim.regex
---@param comparison string
---@param keep boolean
---@return boolean
local function regex_filter(regex, comparison, keep)
    if regex:match_str(comparison) then return keep end
    return not keep
end

---@param pattern string
---@param comparison string
---@param keep boolean
---@return boolean
local function insensitive_filter(pattern, comparison, keep)
    local lower = string.lower(comparison) ---@type string
    if string.find(lower, pattern, 1, true) then return keep end
    return not keep
end

---@param pattern string
---@param comparison string
---@param keep boolean
---@return boolean
local function sensitive_filter(pattern, comparison, keep)
    if string.find(comparison, pattern, 1, true) then return keep end
    return not keep
end

-- =======================
-- == CFILTER EMULATION ==
-- =======================

---@type QfrFilterPredicate
local function cfilter_regex(item, keep, opts)
    if regex_filter(opts.regex, item.text, keep) == keep then return keep end
    if not item.bufnr then return false end
    return regex_filter(opts.regex, fn.bufname(item.bufnr), keep)
end

---@type QfrFilterPredicate
local function cfilter_insensitive(item, keep, opts)
    if insensitive_filter(opts.pattern, item.text, keep) == keep then return keep end
    if not item.bufnr then return false end
    return insensitive_filter(opts.pattern, fn.bufname(item.bufnr), keep)
end

---@type QfrFilterPredicate
local function cfilter_sensitive(item, keep, opts)
    if sensitive_filter(opts.pattern, item.text, keep) == keep then return keep end
    if not opts.bufnr then return false end
    return sensitive_filter(opts.pattern, fn.bufname(item.bufnr), keep)
end

-- ==============
-- == FILENAME ==
-- ==============

---@type QfrFilterPredicate
local function fname_regex(item, keep, opts)
    if not item.bufnr then return false end
    return regex_filter(opts.regex, fn.bufname(item.bufnr), keep)
end

---@type QfrFilterPredicate
local function fname_insensitive(item, keep, opts)
    if not item.bufnr then return false end
    return insensitive_filter(opts.pattern, fn.bufname(item.bufnr), keep)
end

---@type QfrFilterPredicate
local function fname_sensitive(item, keep, opts)
    if not item.bufnr then return false end
    return sensitive_filter(opts.pattern, fn.bufname(item.bufnr), keep)
end

-- ==========
-- == TEXT ==
-- ==========

---@type QfrFilterPredicate
local function text_regex(item, keep, opts)
    return regex_filter(opts.regex, item.text, keep)
end

---@type QfrFilterPredicate
local function text_insensitive(item, keep, opts)
    return insensitive_filter(opts.pattern, item.text, keep)
end

---@type QfrFilterPredicate
local function text_sensitive(item, keep, opts)
    return sensitive_filter(opts.pattern, item.text, keep)
end

-- ==========
-- == TYPE ==
-- ==========

---@type QfrFilterPredicate
local function type_regex(item, keep, opts)
    return regex_filter(opts.regex, item.type, keep)
end

---@type QfrFilterPredicate
local function type_insensitive(item, keep, opts)
    return insensitive_filter(opts.pattern, item.type, keep)
end

---@type QfrFilterPredicate
local function type_sensitive(item, keep, opts)
    return sensitive_filter(opts.pattern, item.type, keep)
end

-- =================
-- == LINE NUMBER ==
-- =================

---@type QfrFilterPredicate
local function lnum_regex(item, keep, opts)
    return regex_filter(opts.regex, tostring(item.lnum), keep)
end

---@type QfrFilterPredicate
local function lnum_insensitive(item, keep, opts)
    return insensitive_filter(opts.pattern, tostring(item.lnum), keep)
end

---@type QfrFilterPredicate
local function lnum_sensitive(item, keep, opts)
    if tostring(item.lnum) == opts.pattern then return keep end
    return not keep
end

-- =========
-- == API ==
-- =========

---@tag qf-rancher-predicate-opts
---@tag qfr-predicate-opts
---NOTE: Each predicate function will use only pattern or regex
---@class QfrPredicateOpts
---@field pattern? string Pattern to filter against
---@field regex? vim.regex Regex to filter against

---@tag qf-rancher-filter-predicate
---@tag qfr-filter-predicate
---Fields:
---- vim.qflist.entry
---- boolean (true for keep, false for remove)
---- QfrPredicateOpts |qfr-predicate-opts|
---Returns: boolean
---@alias QfrFilterPredicate fun(vim.qflist.entry, boolean, QfrPredicateOpts):boolean

---@tag qf-rancher-filter-info
---@tag qfr-filter-info
---NOTE: The filter logic will resolve vimcase and smartcase to either
---case-sensitive or insensitive
---@class QfrFilterInfo
---@field name string Name if the filter, used for cmds
---@field insensitive_func QfrFilterPredicate Case-insensitive predicate
---@field regex_func QfrFilterPredicate Regex predicate
---@field sensitive_func QfrFilterPredicate Case-sensitive predicate

local filters = {
    cfilter = {
        name = "cfilter",
        insensitive_func = cfilter_insensitive,
        sensitive_func = cfilter_sensitive,
        regex_func = cfilter_regex,
    },
    fname = {
        name = "filename",
        insensitive_func = fname_insensitive,
        sensitive_func = fname_sensitive,
        regex_func = fname_regex,
    },
    lnum = {
        name = "lnum",
        insensitive_func = lnum_insensitive,
        sensitive_func = lnum_sensitive,
        regex_func = lnum_regex,
    },
    text = {
        name = "text",
        insensitive_func = text_insensitive,
        sensitive_func = text_sensitive,
        regex_func = text_regex,
    },
    type = {
        name = "type",
        insensitive_func = type_insensitive,
        sensitive_func = type_sensitive,
        regex_func = type_regex,
    },
} ---@type table<string, QfrFilterInfo>

---@return string[]
local function get_filter_names()
    return vim.tbl_keys(filters)
end

---@param name string
---@param keep boolean If true, matched patterns will be
---kept in the list. If false, removed
---@param input_opts QfrInputOpts See |qfr-input-opts|
---If a pattern is provided, that will be used for the
---filter. If not, the user will be prompted for one in
---normal mode, or the current visual selection will be
---used
---@param output_opts QfrOutputOpts See |qfr-output-opts|
---If vim.v.count is > 0, that will be used to
---determine the list nr to be acted on
---@return nil
function Filter.filter(name, keep, input_opts, output_opts)
    if filters[name] then
        filter_wrapper(filters[name], keep, input_opts, output_opts)
    else
        api.nvim_echo({ { "Invalid filter", "ErrorMsg" } }, true, { err = true })
    end
end

---Register a fitler for use in commands and API Calls
---@param filter_info QfrFilterInfo The filter will be
---registered under the name provided in this table
---@return nil
function Filter.register_filter(filter_info)
    filters[filter_info.name] = filter_info
end

---Remove a registered filter. The last filer cannot be removed
---@param name string
---@return nil
function Filter.clear_filter(name)
    if #vim.tbl_keys(filters) <= 1 then
        api.nvim_echo({ { "Cannot remove the last filter method" } }, false, {})
        return
    end

    if filters[name] then
        filters[name] = nil
        api.nvim_echo({ { name .. " removed from filter list", "" } }, true, {})
    else
        api.nvim_echo({ { name .. " is not a registered filter", "" } }, true, {})
    end
end

-- ===============
-- == CMD FUNCS ==
-- ===============

---@param cargs vim.api.keyset.create_user_command.command_args
---@param src_win? integer
---@return nil
local function filter_cmd(cargs, src_win)
    local fargs = cargs.fargs ---@type string[]

    local filter_names = get_filter_names() ---@type string[]
    assert(#filter_names >= 1, "No filter functions available")
    local default_filter = vim.tbl_contains(filter_names, "cfilter") and "cfilter"
        or filter_names[1] ---@type string
    local filter_name = ru._check_cmd_arg(fargs, filter_names, default_filter) ---@type string

    ---@type QfrInputType
    local input_type = ru._check_cmd_arg(fargs, ry._cmd_input_types, ry._default_input_type)
    local pattern = ru._find_cmd_pattern(fargs) ---@type string|nil
    local input_opts = { input_type = input_type, pattern = pattern } ---@type QfrInputOpts

    ---@type QfrAction
    local action = ru._check_cmd_arg(fargs, ry._actions, "u")
    ---@type QfrOutputOpts
    local output_opts = { src_win = src_win, action = action, what = { nr = cargs.count } }

    filter_wrapper(filters[filter_name], not cargs.bang, input_opts, output_opts)
end

---@brief [[
---The callbacks to assign the Qfilter and Lfilter commands are below. They
---expect count = 0 and nargs = "*" to be present in the user_command table.
---They accept the following options:
---- A registered filter name. (cfilter|fname|lnum|text|type) cfilter is default
---  NOTE: The "cfilter" option is an emulation of the built-in Cfilter plugin
---  NOTE: For the "lnum" filter, the case-insensitive filter will function like
---     a "contains" filter, whereas the case-sensitive filter requires an exact
---     match
---- A pattern starting with "/"
---- A |qfr-input-type| ("vimcase" by default)
---- A |setqflist-action| (default "u")
---- If a bang is provided, the filter will remove instead of keeping matched
---  items
---- If a count is provided, that list number will be used. The default is the
---  current list
---Example: 3Qfilter! cfilter r vimcase /require
---@brief ]]

---@param cargs vim.api.keyset.create_user_command.command_args
---@return nil
function Filter.q_filter_cmd(cargs)
    filter_cmd(cargs, nil)
end

---@param cargs vim.api.keyset.create_user_command.command_args
---@return nil
function Filter.l_filter_cmd(cargs)
    filter_cmd(cargs, api.nvim_get_current_win())
end

return Filter
---@export Filter

-- MID: Make a filer for only valid error lines.
--  (buf_is_valid or fname_is_valid) and (lnum or pattern)
-- - With this, make an additional entry validation to check for valid errors only
-- MID: Make a filter for dotfiles/hidden files
-- MID: do qkie and so on syntactic sugar mappings for diagnostics
-- MID: Re-implement the view saving/restoration that calculates the new row based on how many
-- were removed above the current one

-- MID: Look again at how Cfilter works
