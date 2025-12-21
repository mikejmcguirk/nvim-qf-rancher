local api = vim.api
local ry = Qfr_Defer_Require("qf-rancher.types") ---@type qf-rancher.Types

---@class qf-rancher.lib.Sort
local M = {}

-- MID: Which works better, the strategy pattern here or how filter does it?

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
    if not (a and b) then
        return nil
    end

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
    if not (a.bufnr and b.bufnr) then
        return nil, nil
    end

    local fname_a = api.nvim_call_function("bufname", { a.bufnr }) ---@type string|nil
    local fname_b = api.nvim_call_function("bufname", { b.bufnr }) ---@type string|nil
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
    if type(checked_lnum) == "boolean" then
        return checked_lnum
    end

    local checked_col = a_b_check(a.col, b.col, check) ---@type boolean|nil
    if type(checked_col) == "boolean" then
        return checked_col
    end

    local checked_end_lnum = a_b_check(a.end_lnum, b.end_lnum, check) ---@type boolean|nil
    if type(checked_end_lnum) == "boolean" then
        return checked_end_lnum
    end

    return a_b_check(a.end_col, b.end_col, check) -- Return the nil here if we get it
end

---@param a table
---@param b table
---@return boolean|nil
local function check_fname_lcol(a, b, check)
    local checked_fname = check_fname(a, b, check) ---@type boolean|nil
    if type(checked_fname) == "boolean" then
        return checked_fname
    end

    return check_lcol(a, b, check) -- Allow the nil to pass through
end

---@param a table
---@param b table
---@param check QfrCheckFunc
---@return boolean|nil
local function check_lcol_type(a, b, check)
    local checked_lcol = check_lcol(a, b, check) ---@type boolean|nil
    if type(checked_lcol) == "boolean" then
        return checked_lcol
    end

    return a_b_check(a.type, b.type, check)
end

---@type table<string, integer>
local severity_unmap = ry._severity_unmap

---@param a table
---@param b table
---@return integer|nil, integer|nil
local function get_severities(a, b)
    if not (a.type and b.type) then
        return nil, nil
    end

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
    if type(checked_lcol) == "boolean" then
        return checked_lcol
    end

    return check_severity(a, b, check) -- Allow the nil to pass through
end

---@param a vim.quickfix.entry
---@param b vim.quickfix.entry
---@param check QfrCheckFunc
---@return boolean
local function sort_fname(a, b, check)
    if not (a and b) then
        return false
    end

    local checked_fname = check_fname(a, b, check) ---@type boolean|nil
    if type(checked_fname) == "boolean" then
        return checked_fname
    end

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
    if not (a and b) then
        return false
    end

    local a_trim = a.text:gsub("^%s*(.-)%s*$", "%1") ---@type string
    local b_trim = b.text:gsub("^%s*(.-)%s*$", "%1") ---@type string
    local checked_text = a_b_check(a_trim, b_trim, check) ---@type boolean|nil
    if type(checked_text) == "boolean" then
        return checked_text
    end

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
    if not (a and b) then
        return false
    end

    local checked_type = a_b_check(a.type, b.type, check) ---@type boolean|nil
    if type(checked_type) == "boolean" then
        return checked_type
    end

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
    if not (a and b) then
        return false
    end

    local checked_severity = check_severity(a, b, check) ---@type boolean|nil
    if type(checked_severity) == "boolean" then
        return checked_severity
    end

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
    if not (a and b) then
        return false
    end

    local checked_fname = check_fname(a, b, check) ---@type boolean|nil
    if type(checked_fname) == "boolean" then
        return checked_fname
    end

    local checked_lcol_severity = check_lcol_severity(a, b, check_asc) ---@type boolean|nil
    if type(checked_lcol_severity) == "boolean" then
        return checked_lcol_severity
    else
        return false
    end
end

-- MID: The sort predicates are here first so they load properly into the M.sorts table. This is
-- not the best presentation

---@brief [[
---The below sort predicates are exposed for use in other functions. All have
---the type |QfrSortPredicate|
---@brief ]]

---@type qf-rancher.sort.Predicate
---Sort by filename asc. Break ties with line and column numbers
function M.sort_fname_asc(a, b)
    return sort_fname(a, b, check_asc)
end

---@type qf-rancher.sort.Predicate
---Sort by filename desc. Break ties with line and column numbers
function M.sort_fname_desc(a, b)
    return sort_fname(a, b, check_desc)
end

---@type qf-rancher.sort.Predicate
---Sort by text asc
function M.sort_text_asc(a, b)
    return sort_text(a, b, check_asc)
end

---@type qf-rancher.sort.Predicate
---Sort by text desc
function M.sort_text_desc(a, b)
    return sort_text(a, b, check_desc)
end

---@type qf-rancher.sort.Predicate
---Sort by list item type asc
function M.sort_type_asc(a, b)
    return sort_type(a, b, check_asc)
end

---@type qf-rancher.sort.Predicate
---Sort by list item type desc
function M.sort_type_desc(a, b)
    return sort_type(a, b, check_desc)
end

---@type qf-rancher.sort.Predicate
---Sort by filename asc, break ties by diagnostic severity
function M.sort_fname_diag_asc(a, b)
    return sort_diag_fname(a, b, check_asc)
end

---@type qf-rancher.sort.Predicate
---Sort by filename desc, break ties by diagnostic severity
function M.sort_fname_diag_desc(a, b)
    return sort_diag_fname(a, b, check_desc)
end

---@type qf-rancher.sort.Predicate
---Sort by diagnostic severity asc
function M.sort_severity_asc(a, b)
    return sort_severity(a, b, check_asc)
end

---@type qf-rancher.sort.Predicate
---Sort by diagnostic severity desc
function M.sort_severity_desc(a, b)
    return sort_severity(a, b, check_desc)
end

return M
