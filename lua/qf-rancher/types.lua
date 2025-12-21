---@mod Types API Types
---@tag qf-rancher-types
---@tag qfr-types
---@tag qf-rancher-api-types
---@tag qfr-api-types
---@brief [[
---
---@brief ]]

--- @class QfrTypes
local Types = {}

---@tag qf-rancher-input-type
---@tag qfr-input-type
---- "insensitive" will always treat the input as case insensitive
---- "regex" will use a regex search. The type of regex is cmd dependent
---- "sensitive" provides a case sensitive search
---- "smartcase" will be case insensitive only if the serach is all lowercase
---- "vimcase" respect the 'ignorecase' and 'smartcase' options
---@alias QfrInputType
---| 'insensitive'
---| 'regex'
---| 'sensitive'
---| 'smartcase'
---| 'vimcase'

---@tag qf-rancher-input-opts
---@tag qfr-input-opts
---@class QfrInputOpts
---@field input_type QfrInputType
---@field prompt? string User prompt for entering pattern
---@field pattern? string The search pattern for the function

---@tag qf-rancher-system-opts
---@tag qfr-system-opts
---@class QfrSystemOpts
---@field list_item_type? string Usually blank. "\1" for help buffers
---@field sort_func? function A function from the sort module
---@field sync? boolean Run the operation syncrhonously
---How long to wait.
---Default 2000 (sync and async)
---@field timeout? integer

-- MID: This should eventually be removed

---@tag qf-rancher-output-opts
---@tag qfr-output-opts
---@class QfrOutputOpts
---@field list_item_type? string Usually blank. "\1" for help buffers
---@field sort_func? function A function from the sort module
---@field src_win integer|nil Loclist win context. Quickfix if nil
---@field action QfrAction See |setqflist-action|
---@field what QfrWhat See |setqflist-what|

---@export Types

-- =======================
-- == SEMI-CUSTOM TYPES ==
-- =======================

-- MID: Triple check the source that the max is 10 and add that validation here. Would need to be
-- sure not to put it anywhere with an unchecked user count
-- MID: Should underline scope functions validate internals?

---@param nr? integer|"$"
---@param optional? boolean
---@return nil
function Types._validate_list_nr(nr, optional)
    vim.validate("optional", optional, "boolean", true)
    vim.validate("nr", nr, { "number", "string" }, optional)

    if type(nr) == "number" then
        Types._validate_uint(nr)
    end

    if type(nr) == "string" then
        vim.validate("nr", nr, function()
            return nr == "$"
        end)
    end
end

-- PR: The built-in what annotation does not contain the user_data field
-- PR: The built-in annotation does not allow string values for quickfixtextfunc

-- LOW: Create validations for the get and ret what tables

---@class QfrWhat : vim.fn.setqflist.what
---@field quickfixtextfunc? function|string
---@field user_data? any

---@param what QfrWhat
---@return nil
function Types._validate_what(what)
    vim.validate("what", what, "table")

    vim.validate("what.context", what.context, "table", true)
    vim.validate("what.efm", what.efm, "string", true)
    Types._validate_uint(what.id, true)
    Types._validate_uint(what.idx, true)
    vim.validate("what.items", what.items, "table", true)
    if vim.g.qfr_debug_assertions and type(what.items) == "table" then
        for _, item in ipairs(what.items) do
            Types._validate_list_item(item)
        end
    end

    Types._validate_list(what.lines, { optional = true, type = "string" })

    vim.validate("what.nr", what.nr, { "number", "string" }, true)
    if type(what.nr) == "number" then
        ---@diagnostic disable-next-line: param-type-mismatch
        Types._validate_uint(what.nr)
    end

    if type(what.nr) == "string" then
        vim.validate("what.nr", what.nr, function()
            return what.nr == "$"
        end)
    end

    vim.validate("what.quickfixtextfunc", what.quickfixtextfunc, "callable", true)
    vim.validate("what.title", what.title, "string", true)
end

-- LOW: Add validation for win config

---@class QfrFindWinInTabOpts
---@field buf? integer
---@field fin_winnr? integer
---@field skip_winnr? integer

---@param opts QfrFindWinInTabOpts
---@return nil
function Types._validate_find_win_in_tab_opts(opts)
    vim.validate("opts", opts, "table")
    Types._validate_uint(opts.buf, true)
    Types._validate_uint(opts.fin_winnr, true)
    vim.validate("opts.skip_winnr", opts.skip_winnr, "number", true)
end

-- ================
-- == PRIMITIVES ==
-- ================

---@param n integer|nil
---@param optional? boolean
---@return nil
function Types._validate_uint(n, optional)
    vim.validate("num", n, "number", optional)
    vim.validate("num", n, function()
        return n % 1 == 0
    end, optional, "Num is not an integer")

    vim.validate("num", n, function()
        return n >= 0
    end, optional, "Num is less than zero")
end

---@param n integer
---@return boolean
function Types._is_uint(n)
    if type(n) ~= "number" then
        return false
    end

    if n < 0 then
        return false
    end

    return n % 1 == 0
end

---@param num integer|nil
---@param optional? boolean
---@return nil
function Types._validate_int(num, optional)
    vim.validate("num", num, "number", optional)
    vim.validate("num", num, function()
        return num % 1 == 0
    end, optional, "Num is not an integer")
end

-- ===============
-- == BUILT-INS ==
-- ===============

-- MID: Perhaps create a separate validation for stack nrs limiting to between 0-10
-- How a huge deal since clamping is easy, but would enforce more type consistency

---@param win integer|nil
---@param optional? boolean
---@return nil
function Types._validate_win(win, optional)
    if optional and type(win) == "nil" then
        return
    end

    Types._validate_uint(win)
    if type(win) == "number" then
        vim.validate("win", win, function()
            return vim.api.nvim_win_is_valid(win)
        end, "Win " .. win .. " is not valid")
    else
        error("Win is not a number or nil")
    end
end

---@param buf integer|nil
---@param optional? boolean
---@return nil
function Types._validate_buf(buf, optional)
    Types._validate_uint(buf, optional)
    if optional and type(buf) == "nil" then
        return
    end

    if type(buf) == "number" then
        vim.validate("buf", buf, function()
            return vim.api.nvim_buf_is_valid(buf)
        end)
    else
        error("buf is not a number or nil")
    end
end

---@class QfrValidateListOpts
---@field len? integer
---@field optional? boolean
---@field type? string

---@param opts QfrValidateListOpts
---@return nil
local function validate_validate_list_opts(opts)
    vim.validate("opts", opts, "table")
    Types._validate_uint(opts.len, true)
    vim.validate("opts.optional", opts.optional, "boolean", true)
    vim.validate("opts.type", opts.type, "string", true)
end

---@param tabnr integer
function Types._validate_tabnr(tabnr)
    Types._validate_uint(tabnr)
    vim.validate("tabnr", tabnr, function()
        return tabnr <= vim.fn.tabpagenr("$")
    end)
end

-- MID: Type conflicts with the built-in type function
-- LOW: This should be able to take a function as a validator

---@param list table
---@param opts QfrValidateListOpts
---@return nil
function Types._validate_list(list, opts)
    validate_validate_list_opts(opts)
    if (not list) and opts.optional then
        return
    end

    vim.validate("list", list, vim.islist, "Must be a valid list")

    if opts.len then
        vim.validate("list", list, function()
            return #list == opts.len
        end, "List length must be " .. opts.len)
    end

    if opts.type and vim.g.qfr_debug_assertions then
        vim.validate("list", list, function()
            for _, value in ipairs(list) do
                if type(value) ~= opts.type then
                    return false
                end
            end

            return true
        end, "List values must be type " .. opts.type)
    end
end

---@param cur_pos {[1]: integer, [2]: integer}
---@return nil
function Types._validate_cur_pos(cur_pos)
    Types._validate_list(cur_pos, { len = 2, type = "number" })

    Types._validate_uint(cur_pos[1])
    vim.validate("row", cur_pos[1], function()
        return cur_pos[1] >= 1
    end, "Cursor row must be >= 1")

    Types._validate_uint(cur_pos[2])
end

-- MID: This and the utils module are getting bigger, and another split will be necessary
-- This function sits in the uncanny valley between validating data and validating program state
-- Feels like an anchor point for deciding what the new cut points are

---@param list_win integer|nil
---@param optional? boolean
---@return nil
function Types._validate_list_win(list_win, optional)
    if optional and type(list_win) == "nil" then
        return
    end

    Types._validate_win(list_win)
    ---@diagnostic disable-next-line: param-type-mismatch
    local list_win_buf = vim.api.nvim_win_get_buf(list_win) ---@type integer
    ---@type string
    local buftype = vim.api.nvim_get_option_value("buftype", { buf = list_win_buf })
    vim.validate("buftype", buftype, function()
        return buftype == "quickfix"
    end, optional, "Buftype must be quickfix")
end

---@param item_type string|nil
---@param optional? boolean
---@return nil
function Types._validate_list_item_type(item_type, optional)
    vim.validate("optional", optional, "boolean", true)
    if optional and type(item_type) == "nil" then
        return
    end

    vim.validate("item_type", item_type, "string", true)
    if type(item_type) == "string" then
        vim.validate("item_type", item_type, function()
            return #item_type <= 1
        end)
    end
end

---NOTE: This is designed for entries used to set qflists. The entries from getqflist() are
---not exactly the same
---@param item vim.quickfix.entry
---@return nil
function Types._validate_list_item(item)
    vim.validate("item", item, "table")

    vim.validate("item.bufnr", item.bufnr, "number", true)
    -- Cannot check if buf is valid here, because a valid buf at the time of list creation might
    -- have been deleted
    Types._validate_uint(item.bufnr, true)
    -- Cannot check if filename is valid here, because a valid filename at the time of list
    -- creation might have been moved or deleted
    vim.validate("item.filename", item.filename, "string", true)

    vim.validate("item.module", item.module, "string", true)
    Types._validate_int(item.nr, true)
    vim.validate("item.pattern", item.pattern, "string", true)
    Types._validate_uint(item.vcol, true)

    vim.validate("item.text", item.text, "string", true)

    -- MID: Figure out what the proper validation for this is
    -- vim.validate("item.valid", item.valid, { "boolean", "nil" })

    Types._validate_list_item_type(item.type, true)

    -- NOTE: While qf rows and cols are one indexed, 0 is used to represent non-values
    Types._validate_uint(item.lnum, true)
    Types._validate_uint(item.col, true)
    Types._validate_uint(item.end_lnum, true)
    Types._validate_uint(item.end_col, true)
end

Types._severity_map = {
    [vim.diagnostic.severity.ERROR] = "E",
    [vim.diagnostic.severity.WARN] = "W",
    [vim.diagnostic.severity.INFO] = "I",
    [vim.diagnostic.severity.HINT] = "H",
} ---@type table<integer, string>

Types._severity_map_plural = {
    [vim.diagnostic.severity.ERROR] = "errors",
    [vim.diagnostic.severity.WARN] = "warnings",
    [vim.diagnostic.severity.INFO] = "info",
    [vim.diagnostic.severity.HINT] = "hints",
} ---@type table<integer, string>

Types._severity_map_str = {
    [vim.diagnostic.severity.ERROR] = "Error",
    [vim.diagnostic.severity.WARN] = "Warning",
    [vim.diagnostic.severity.INFO] = "Info",
    [vim.diagnostic.severity.HINT] = "Hint",
} ---@type table<integer, string>

Types._severity_unmap = {
    E = vim.diagnostic.severity.ERROR,
    W = vim.diagnostic.severity.WARN,
    I = vim.diagnostic.severity.INFO,
    H = vim.diagnostic.severity.HINT,
} ---@type table<string, integer>

-- :h 'winborder'
-- PR: This feels like something you could put into vim.validate. Or at least a type annotation
-- NOTE/PR: The win config API keyset does not include "bold"
-- NOTE/PR: "" is also an acceptable option not noted in the keyset

---@alias QfrBorder ""|"bold"|"double"|"none"|"rounded"|"shadow"|"single"|"solid"|string[]

---@type string[]
local valid_borders = { "", "bold", "double", "none", "rounded", "shadow", "single", "solid" }

---@param border QfrBorder
---@return nil
function Types._validate_border(border)
    vim.validate("border", border, { "string", "table" })
    if type(border) == "string" then
        vim.validate("border", border, function()
            return vim.tbl_contains(valid_borders, border)
        end)
    elseif type(border) == "table" then
        Types._validate_list(border, { len = 8, type = "string" })
    end
end

---@alias QfrTitlePos "left"|"center"|"right"

---@param pos QfrTitlePos
---@return nil
function Types._validate_title_pos(pos)
    vim.validate("pos", pos, "string")
    vim.validate("pos", pos, function()
        return pos == "left" or pos == "center" or pos == "right"
    end)
end

---@param winblend integer
---@return nil
function Types._validate_winblend(winblend)
    Types._validate_uint(winblend)
    vim.validate("winblend", winblend, function()
        return winblend >= 0 and winblend <= 100
    end, false, "Winblend is not between 0 and 100")
end

-- =============================
-- == CUSTOM TYPES -- GENERAL ==
-- =============================

---@alias QfrAction "a"|"f"|"r"|"u"|" "

Types._actions = { "a", "f", "r", "u", " " } ---@type string[]

---@param action QfrAction
---@return nil
function Types._validate_action(action)
    vim.validate("action", action, "string")
    vim.validate("action", action, function()
        return vim.tbl_contains(Types._actions, action)
    end)
end

---@param output_opts QfrOutputOpts
---@return nil
function Types._validate_output_opts(output_opts)
    vim.validate("output_opts", output_opts, "table")
    Types._validate_list_item_type(output_opts.list_item_type, true)
    vim.validate("sort_func", output_opts.sort_func, "callable", true)
    Types._validate_win(output_opts.src_win, true)
    Types._validate_action(output_opts.action)
    Types._validate_what(output_opts.what)
end

-- MID: Deprecate this

---@type string[]
local input_types = { "insensitive", "regex", "sensitive", "smartcase", "vimcase" }
Types._default_input_type = "vimcase"
Types._cmd_input_types = vim.tbl_filter(function(t)
    return t ~= "vimcase"
end, input_types)

---@param input QfrInputType
---@return nil
function Types._validate_input_type(input)
    vim.validate("input", input, "string")
    vim.validate("input", input, function()
        return vim.tbl_contains(input_types, input)
    end, "Input type " .. input .. " is not valid")
end

---@alias QfrCase "insensitive"|"sensitive"|"smartcase"|"vimcase"

local cases = { "insensitive", "sensitive", "smartcase", "vimcase" }

---@param case QfrCase|nil
---@param optional boolean?
---@return nil
function Types._validate_case(case, optional)
    if optional and type(case) == "nil" then
        return
    end

    vim.validate("case", case, function()
        return vim.tbl_contains(cases, case)
    end)
end

-- MID: Deprecate this. There are specific combinatorial problems for certain modules that
-- require tables to answers, but adding in a generalized input table only adds another
-- combinatorial layer

---@param input_opts QfrInputOpts
---@return nil
function Types._validate_input_opts(input_opts)
    vim.validate("input_opts", input_opts, "table")
    Types._validate_input_type(input_opts.input_type)
    vim.validate("input_opts.pattern", input_opts.pattern, "string", true)
end

---@class qf-rancher.util.FindLoclistWinOpts
---@field tabpages? integer[]
---@field src_win? integer
---@field qf_id? integer

---@class QfrBufOpenOpts
---@field buftype? string
---@field clearjumps? boolean
---@field focus? boolean
---@field skip_set_cur_pos? boolean
---@field skip_zzze? boolean
---@field win? integer

---@param opts QfrBufOpenOpts
---@return nil
function Types._validate_open_buf_opts(opts)
    vim.validate("opts", opts, "table")
    vim.validate("opts.buftype", opts.buftype, "string", true)
    vim.validate("opts.clearjumps", opts.clearjumps, "boolean", true)
    vim.validate("opts.focus", opts.focus, "boolean", true)
    vim.validate("opts.skip_set_cur_pos", opts.skip_set_cur_pos, "boolean", true)
    vim.validate("opts.skip_zzze", opts.skip_zzze, "boolean", true)
    Types._validate_win(opts.win, true)
end

-- =========================
-- == CUSTOM TYPES - DIAG ==
-- =========================

---@alias QfrDiagDispFunc fun(vim.Diagnostic):vim.quickfix.entry

---@param diag_opts QfrDiagOpts
---@return nil
function Types._validate_diag_opts(diag_opts)
    vim.validate("diag_opts", diag_opts, "table")
    vim.validate("diag_opts.disp_func", diag_opts.disp_func, "callable", true)
    vim.validate("diag_opts.top", diag_opts.top, "boolean", true)
    Types._validate_diag_getopts(diag_opts.getopts, true)
end

---@param severity integer|nil
---@param optional? boolean
---@return nil
function Types._validate_diag_severity(severity, optional)
    vim.validate("optional", optional, "boolean", true)
    if optional and type(severity) == "nil" then
        return
    end

    Types._validate_uint(severity)
    vim.validate("severity", severity, function()
        return severity >= 1 and severity <= 4
    end, "Diagnostic severity must be between 1 and 4")
end

---@param diag_getopts? vim.diagnostic.GetOpts
---@param optional? boolean
---@return nil
function Types._validate_diag_getopts(diag_getopts, optional)
    vim.validate("optional", optional, "boolean", true)
    if optional and type(diag_getopts) == "nil" then
        return
    end

    vim.validate("diag_getopts", diag_getopts, "table")
    assert(type(diag_getopts) == "table")

    local ns = diag_getopts.namespace
    vim.validate("ns", ns, { "number", "table" }, true)
    ---@diagnostic disable-next-line: param-type-mismatch
    if type(ns) == "number" then
        Types._validate_uint(ns)
    end
    ---@diagnostic disable-next-line: param-type-mismatch
    if type(ns) == "table" then
        Types._validate_list(ns, { type = "number" })
    end

    Types._validate_uint(diag_getopts.lnum, true)

    vim.validate("diag_getopts.severity", diag_getopts.severity, { "number", "table" }, true)
    if type(diag_getopts.severity) == "number" then
        ---@diagnostic disable-next-line: param-type-mismatch
        Types._validate_diag_severity(diag_getopts.severity)
    elseif vim.islist(diag_getopts.severity) then
        ---@diagnostic disable-next-line: param-type-mismatch
        Types._validate_list(diag_getopts.severity, { type = "number" })
    elseif type(diag_getopts.severity) == "table" then
        Types._validate_diag_severity(diag_getopts.severity.min, true)
        Types._validate_diag_severity(diag_getopts.severity.max, true)
    end

    vim.validate("diag_getopts.enabled", diag_getopts.enabled, "boolean", true)
end

-- ============================
-- == CUSTOM TYPES -- FILTER ==
-- ============================

---@param filter_info QfrFilterInfo
---@return nil
function Types._validate_filter_info(filter_info)
    vim.validate("filter_info", filter_info, "table")
    vim.validate("filter_info.name", filter_info.name, "string")
    vim.validate("filter_info.insensitive_func", filter_info.insensitive_func, "callable")
    vim.validate("filter_info.regex_func", filter_info.regex_func, "callable")
    vim.validate("filter_info.sensitive_func", filter_info.sensitive_func, "callable")
end

-- ================
-- == OPEN TYPES ==
-- ================

---@param open_opts QfrListOpenOpts
---@return nil
function Types._validate_open_opts(open_opts)
    vim.validate("open_opts", open_opts, "table")
    vim.validate("open_opts.height", open_opts.height, "number", true)
    vim.validate("open_opts.keep_win", open_opts.keep_win, "boolean", true)
    vim.validate("open_opts.nop_if_open", open_opts.nop_if_open, "boolean", true)
end

---@alias QfrGetItemFunc fun(integer?):vim.quickfix.entry|nil, integer|nil

---@alias QfrSplitType "none"|"split"|"tabnew"|"vsplit"

local valid_splits = { "none", "split", "tabnew", "vsplit" }

---@alias QfrFinishMethod "focusList"|"focusWin"
local valid_finishes = { "focusList", "focusWin" }

---@param split QfrSplitType
---@return nil
function Types._validate_split(split)
    vim.validate("split", split, "string")
    vim.validate("split", split, function()
        return vim.tbl_contains(valid_splits, split)
    end, "Split type of " .. split .. " is invalid")
end

---@param finish QfrFinishMethod
---@return nil
function Types._validate_finish(finish)
    vim.validate("finish", finish, "string")
    vim.validate("finish", finish, function()
        return vim.tbl_contains(valid_finishes, finish)
    end, "Finish method of " .. finish .. " is invalid")
end

------------------
-- SYSTEM TYPES --
------------------

---@param system_opts QfrSystemOpts
---@return nil
function Types._validate_system_opts(system_opts)
    vim.validate("system_opts", system_opts, "table")

    Types._validate_list_item_type(system_opts.list_item_type, true)
    -- MID: Should this be a function? Are there other callables that should be a function?
    vim.validate("sort_func", system_opts.sort_func, "callable", true)
    vim.validate("system_opts.sync", system_opts.sync, "boolean", true)
    vim.validate("system_opts.timeout", system_opts.timeout, "number", true)
end

Types._sync_opts = { "sync", "async" }
Types._default_sync_opt = "async"

return Types

-- LOW: Create a type and validation for getqflist returns
