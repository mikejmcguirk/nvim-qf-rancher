---@mod Types API Types
---@tag qf-rancher-types
---@tag qfr-types
---@tag qf-rancher-api-types
---@tag qfr-api-types
---@brief [[
---
---@brief ]]

--- @class qf-rancher.Types
local Types = {}

-- LOW: Create types for the what get and ret tables
-- PR: The built-in what annotation does not contain the user_data field

---@class qf-rancher.types.What : vim.fn.setqflist.what
---@field user_data? any

---@alias qf-rancher.types.Border ''|'bold'|'double'|'none'|'rounded'|'shadow'|'single'|'solid'

---@alias qf-rancher.types.Action 'a'|'f'|'r'|'u'|' '

---@alias qf-rancher.types.Case 'insensitive'|'sensitive'|'smartcase'|'vimcase'

---@export Types

---@param what qf-rancher.types.What
---@return nil
function Types._validate_what(what)
    vim.validate("what", what, "table")

    vim.validate("what.context", what.context, "table", true)
    vim.validate("what.efm", what.efm, "string", true)
    Types._validate_uint(what.id, true)
    Types._validate_uint(what.idx, true)
    vim.validate("what.items", what.items, "table", true)

    Types._validate_list(what.lines, { optional = true, item_type = "string" })

    vim.validate("what.nr", what.nr, { "number", "string" }, true)
    if type(what.nr) == "number" then
        ---@diagnostic disable-next-line: param-type-mismatch
        Types._validate_uint(what.nr)
    elseif type(what.nr) == "string" then
        vim.validate("what.nr", what.nr, function()
            return what.nr == "$"
        end)
    end

    vim.validate("what.quickfixtextfunc", what.quickfixtextfunc, { "callable", "string" }, true)
    vim.validate("what.title", what.title, "string", true)
end

---@type string[]
local valid_borders = { "", "bold", "double", "none", "rounded", "shadow", "single", "solid" }

---@param border qf-rancher.types.Border|string[]
---@param optional? boolean
---@return nil
function Types._validate_border(border, optional)
    if optional and type(border) == "nil" then
        return
    end

    vim.validate("border", border, { "string", "table" })
    if type(border) == "string" then
        vim.validate("border", border, function()
            return vim.tbl_contains(valid_borders, border)
        end)
    elseif type(border) == "table" then
        Types._validate_list(border, { len = 8, item_type = "string" })
    end
end

-- TODO: This should be deprecated

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

-- TODO: Deprecate

---@tag qf-rancher-input-opts
---@tag qfr-input-opts
---@class QfrInputOpts
---@field input_type QfrInputType
---@field prompt? string User prompt for entering pattern
---@field pattern? string The search pattern for the function

-- TODO: This should eventually be removed

---@tag qf-rancher-output-opts
---@tag qfr-output-opts
---@class QfrOutputOpts
---@field list_item_type? string Usually blank. "\1" for help buffers
---@field sort_func? function A function from the sort module
---@field src_win integer|nil Loclist win context. Quickfix if nil
---@field action qf-rancher.types.Action See |setqflist-action|
---@field what qf-rancher.types.What See |setqflist-what|

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

-- TODO: Deprecate this

---@class QfrFindWinInTabOpts
---@field buf? integer
---@field fin_winnr? integer
---@field skip_winnr? integer

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

-- LOW: Type should be able to take a function as a validator

---@class qf-rancher.types.ValidateListOpts
---@field len? integer
---@field max_len? integer
---@field optional? boolean
---@field item_type? string

---@param opts qf-rancher.types.ValidateListOpts
---@return nil
local function validate_validate_list_opts(opts)
    vim.validate("opts", opts, "table")
    Types._validate_uint(opts.len, true)
    vim.validate("opts.optional", opts.optional, "boolean", true)
    vim.validate("opts.item_type", opts.item_type, "string", true)
end

---@param list table
---@param opts qf-rancher.types.ValidateListOpts
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

    if opts.max_len then
        vim.validate("list", list, function()
            return #list <= opts.max_len
        end, "List length must be " .. opts.len)
    end
end

---@param item_type string|nil
---@param optional? boolean
---@return nil
function Types._validate_list_item_type(item_type, optional)
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

---@type table<integer, string>
Types._severity_map = {
    [vim.diagnostic.severity.ERROR] = "E",
    [vim.diagnostic.severity.WARN] = "W",
    [vim.diagnostic.severity.INFO] = "I",
    [vim.diagnostic.severity.HINT] = "H",
}

---@type table<integer, string>
Types._severity_map_plural = {
    [vim.diagnostic.severity.ERROR] = "errors",
    [vim.diagnostic.severity.WARN] = "warnings",
    [vim.diagnostic.severity.INFO] = "info",
    [vim.diagnostic.severity.HINT] = "hints",
}

---@type table<integer, string>
Types._severity_map_str = {
    [vim.diagnostic.severity.ERROR] = "Error",
    [vim.diagnostic.severity.WARN] = "Warning",
    [vim.diagnostic.severity.INFO] = "Info",
    [vim.diagnostic.severity.HINT] = "Hint",
}

---@type table<string, integer>
Types._severity_unmap = {
    E = vim.diagnostic.severity.ERROR,
    W = vim.diagnostic.severity.WARN,
    I = vim.diagnostic.severity.INFO,
    H = vim.diagnostic.severity.HINT,
}

---@param pos "left"|"center"|"right"
---@param optional? boolean
---@return nil
function Types._validate_title_pos(pos, optional)
    if optional and type(pos) == "nil" then
        return
    end

    vim.validate("pos", pos, "string")
    vim.validate("pos", pos, function()
        return pos == "left" or pos == "center" or pos == "right"
    end)
end

---@param title? string|[string,string|integer?][]
---@param optional? boolean
function Types._validate_title(title, optional)
    if optional and type(title) == "nil" then
        return
    end

    vim.validate("title", title, { "string", "table" })
    if type(title) == "table" then
        Types._validate_list(title, { item_type = "table" })
        for _, tuple in ipairs(title) do
            Types._validate_list(tuple, { max_len = 2, item_type = "string" })
        end
    end
end

Types._actions = { "a", "f", "r", "u", " " } ---@type string[]

---@param action qf-rancher.types.Action
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

local cases = { "insensitive", "sensitive", "smartcase", "vimcase" }

---@param case qf-rancher.types.Case|nil
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

-- TODO: Deprecate this. There are specific combinatorial problems for certain modules that
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

---@class qf-rancher.types.BufOpenOpts
---@field buftype? string
---@field clearjumps? boolean
---@field focus? boolean
---@field skip_set_cur_pos? boolean
---@field skip_zzze? boolean
---@field win? integer

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
        Types._validate_list(ns, { item_type = "number" })
    end

    Types._validate_uint(diag_getopts.lnum, true)

    vim.validate("diag_getopts.severity", diag_getopts.severity, { "number", "table" }, true)
    if type(diag_getopts.severity) == "number" then
        ---@diagnostic disable-next-line: param-type-mismatch
        Types._validate_diag_severity(diag_getopts.severity)
    elseif vim.islist(diag_getopts.severity) then
        ---@diagnostic disable-next-line: param-type-mismatch
        Types._validate_list(diag_getopts.severity, { item_type = "number" })
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

---@alias QfrGetItemFunc fun(integer?):vim.quickfix.entry|nil, integer|nil

---@alias QfrSplitType "none"|"split"|"tabnew"|"vsplit"

---@alias QfrFinishMethod "focusList"|"focusWin"
local valid_finishes = { "focusList", "focusWin" }

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

Types._sync_opts = { "sync", "async" }
Types._default_sync_opt = "async"

return Types

-- TODO: Stuff that's only used in one module needs to be moved to the module it's used in
-- TODO: Once broader refactoring is done, move the stuff that needs to be documented into the
-- public doc area.
