-- ===========================
-- == NVIM QUICKFIX RANCHER ==
-- ===========================

---https://github.com/tjdevries/lazy-require.nvim/blob/master/lua/lazy-require.lua
---@param require_path string
---@return table
function _G.Qfr_Defer_Require(require_path)
    return setmetatable({}, {
        __index = function(_, key)
            return require(require_path)[key]
        end,

        __newindex = function(_, key, value)
            require(require_path)[key] = value
        end,
    })
end

local ea = Qfr_Defer_Require("qf-rancher.stack") ---@type QfrStack
local ed = Qfr_Defer_Require("qf-rancher.diag") ---@type QfRancherDiagnostics
local ef = Qfr_Defer_Require("qf-rancher.filter") ---@type QfrFilter
local ei = Qfr_Defer_Require("qf-rancher.filetype-funcs") ---@type QfRancherFiletypeFuncs
local eg = Qfr_Defer_Require("qf-rancher.grep") ---@type QfrGrep
local en = Qfr_Defer_Require("qf-rancher.nav-action") ---@type QfRancherNav
local eo = Qfr_Defer_Require("qf-rancher.open") ---@type QfrOpen
local ep = Qfr_Defer_Require("qf-rancher.preview") ---@type QfRancherPreview
local es = Qfr_Defer_Require("qf-rancher.sort") ---@type QfRancherSort

_G.QFR_MAX_HEIGHT = 10

local api = vim.api
local fn = vim.fn

---@mod nvim-qf-rancher.txt Error list husbandry
---@brief [[
---Nvim Quickfix Rancher provides a stable of tools for taming the quickfix
---and location lists:
---- Auto opening and closing of list windows at logical points across
---  tabpages
---- Wrapping and convenience functions for list and stack navigation
---- Autocommands to stop automatic copying of location lists to new windows,
---  as well as putting location lists without a home window out to pasture
---- Preview window for list items
---- Built-in functions for lassoing diagnostics by all severities, including
---  highest only
---- Filter and sort functions
---- A variey of grep functions built on rg as a default, with grep available
---  as a backup
---- Capabilities are extensible and available from the cmd line
---@brief ]]

-- ============
-- == G VARS ==
-- ============

-- MID: Create specific validator functions for these where appropriate

---@mod qf-rancher-installation Installation
---TODO:

---@mod qf-rancher-config Configuration

---@brief [[
---Qfr is configured using vim.g variables. For lazy.nvim users, make sure to
---set thse in the "init" section of your plugin spec
---TODO: aliases should work for var docs
---qfr_auto_open_changes (boolean, default true): Always open the list when
---its contents are changed
---@brief ]]
-- stylua: ignore
_G._QFR_G_VAR_MAP = {
qfr_auto_open_changes = { { "boolean" }, true },

    qfr_auto_list_height = { { "boolean" }, true },
    -- DOCUMENT:
    -- - If splitkeep is set to screen or topline, that will take precedence
    -- - If splitkeep is set for cursor, and this option is true, rancher will save and restore
    --      views where necessary
    -- - If this is off and splitkeep is set for cursor, you get Nvim default behavior
    qfr_always_save_views = { { "boolean" }, true },
    qfr_debug_assertions = { { "boolean" }, false },
    qfr_close_on_stack_clear = { { "boolean" }, true },
    qfr_create_autocmds = { { "boolean" }, true },

    qfr_ftplugin_demap = { { "boolean" }, true },
    qfr_ftplugin_keymap = { { "boolean" }, true },
    qfr_ftplugin_set_opts = { { "boolean" }, true },

    qfr_grepprg = { { "string" }, "rg" },

    qfr_map_set_defaults = { { "boolean" }, true },
    qfr_map_ll_prefix = { { "string" }, "l" },
    qfr_map_qf_prefix = { { "string" }, "q" },
    qfr_map_diag_prefix = { { "string" }, "i" },
    qfr_map_keep_prefix = { { "string" }, "k" },
    qfr_map_remove_prefix = { { "string" }, "r" },
    qfr_map_grep_prefix = { { "string" }, "g" },
    qfr_map_sort_prefix = { { "string" }, "t" },

    qfr_preview_border = { { "string", "table" }, "single" },
    -- DOCUMENT: Default is 100 to accomodate slower systems/HDs. 50 should be fine if you have an
    -- SSD/reasonably fast computer. Below that more risk of things getting choppy
    qfr_preview_debounce = { { "number" }, 100 },
    qfr_preview_show_title = { { "boolean" }, true },
    qfr_preview_title_pos = { { "string" }, "left" },
    qfr_preview_winblend = { { "number" }, 0 },

    qfr_qfsplit = { { "string" }, "botright" },
    qfr_reuse_same_title = { { "boolean" }, true },
    qfr_set_default_cmds = { { "boolean" }, true },
    qfr_skip_zzze = { { "boolean" }, false },
} ---@type table<string, {[1]:string[], [2]: any}>

for k, v in pairs(_QFR_G_VAR_MAP) do
    local cur_g_val = vim.g[k] ---@type any
    if not vim.tbl_contains(v[1], type(cur_g_val)) then vim.api.nvim_set_var(k, v[2]) end
end

if vim.g.qfr_create_autocmds then
    local qfr_loclist_group = vim.api.nvim_create_augroup("qfr-loclist-group", { clear = true })

    api.nvim_create_autocmd("WinNew", {
        group = qfr_loclist_group,
        callback = function()
            vim.fn.setloclist(0, {}, "f")
        end,
    })

    api.nvim_create_autocmd("WinClosed", {
        group = qfr_loclist_group,
        callback = function(ev)
            local win = tonumber(ev.match) ---@type number?
            if not win then return end

            if not api.nvim_win_is_valid(win) then return end

            local config = vim.api.nvim_win_get_config(win) ---@type vim.api.keyset.win_config
            if config.relative and config.relative ~= "" then return end

            local qf_id = fn.getloclist(win, { id = 0 }).id ---@type integer
            if qf_id < 1 then return end

            local buf = vim.api.nvim_win_get_buf(win) ---@type integer
            if api.nvim_get_option_value("buftype", { buf = buf }) == "quickfix" then return end

            vim.schedule(function()
                eo._close_loclists_by_qf_id(qf_id, { all_tabpages = true })
            end)
        end,
    })
end

-- NOTE: The mappings and user commands are all here in order to avoid eagerly requiring every
-- module during startup

-- NOTE: In order for the defer require to work, all function calls must be inside of
-- anonymous functions. If you pass, for example, eo.closeqflist as a function reference, eo
-- needs to be evaluated at command creation

------------------------
-- Map and Cmd Pieces --
------------------------

local nn = { "n" } ---@type string[]
local nx = { "n", "x" } ---@type string[]

-- DOCUMENT: how prefixes are validated

---@param prefix string
---@return boolean
local function validate_prefix(prefix)
    if #prefix ~= 1 then return false end
    if prefix:match("^[%a]+$") == nil then return false end
    return true
end

-- MID: Not the greatest way to do this. If this gets combined with the main setup file, then
-- try to put together the validations more

local qp = string.lower(vim.g.qfr_map_qf_prefix) ---@type string
qp = validate_prefix(qp) and qp or _QFR_G_VAR_MAP["qfr_map_qf_prefix"][2]
local ql = "<leader>" .. qp ---@type string
local qP = string.upper(qp) ---@type string

local lp = string.lower(vim.g.qfr_map_ll_prefix) ---@type string
lp = validate_prefix(lp) and lp or _QFR_G_VAR_MAP["qfr_map_ll_prefix"][2]
local ll = "<leader>" .. lp ---@type string
local lP = string.upper(lp) ---@type string

local dp = string.lower(vim.g.qfr_map_diag_prefix) ---@type string
dp = validate_prefix(dp) and dp or _QFR_G_VAR_MAP["qfr_map_diag_prefix"][2]
local kp = string.lower(vim.g.qfr_map_keep_prefix) ---@type string
kp = validate_prefix(kp) and kp or _QFR_G_VAR_MAP["qfr_map_keep_prefix"][2]
local rp = string.lower(vim.g.qfr_map_remove_prefix) ---@type string
rp = validate_prefix(rp) and rp or _QFR_G_VAR_MAP["qfr_map_remove_prefix"][2]
local gp = string.lower(vim.g.qfr_map_grep_prefix) ---@type string
gp = validate_prefix(gp) and gp or _QFR_G_VAR_MAP["qfr_map_grep_prefix"][2]
local sp = string.lower(vim.g.qfr_map_sort_prefix) ---@type string
sp = validate_prefix(sp) and sp or _QFR_G_VAR_MAP["qfr_map_sort_prefix"][2]

local sc = " (smartcase)" ---@type string
local rx = " (regex)" ---@type string

local vimcase = { input_type = "vimcase" } ---@type QfrInputOpts
local regex = { input_type = "regex" } ---@type QfrInputOpts

local ds = vim.diagnostic.severity

local sys_opt = { timeout = 4000 } ---@type QfrSystemOpts

---@return integer
local function cur_win()
    return api.nvim_get_current_win()
end

---@param action QfrAction
---@param src_win integer|nil
---@return QfrOutputOpts
local function get_output_opts(src_win, action)
    -- MID: This is reasonable default behavior, but not the best place to define it
    local nr = action == " " and "$" or 0 ---@type integer|"$"
    if vim.v.count > 0 then nr = vim.v.count end
    return { src_win = src_win, action = action, what = { nr = nr } }
end

---@return QfrOutputOpts
local function new_qflist()
    return get_output_opts(nil, " ")
end

---@return QfrOutputOpts
local function replace_qflist()
    return get_output_opts(nil, "u")
end

---@return QfrOutputOpts
local function new_loclist()
    return get_output_opts(cur_win(), " ")
end

---@return QfrOutputOpts
local function replace_loclist()
    return get_output_opts(cur_win(), "u")
end

--- Mode(s), Plug Map, User Map, Desc, Action
---@alias QfRancherMapData{[1]:string[], [2]:string, [3]:string, [4]: string, [5]: function}

-- stylua: ignore
---@type QfRancherMapData[]
local qfr_maps = {
    -- ==========
    -- == GREP ==
    -- ==========

    { nx, "<Plug>(qfr-grep-cwd)",    ql..gp.."d", "Qgrep CWD"..sc,       function() eg.grep("cwd", vimcase, sys_opt, new_qflist()) end },
    { nx, "<Plug>(qfr-grep-cwdX)",   ql..gp.."D", "Qgrep CWD"..rx,       function() eg.grep("cwd", regex, sys_opt, new_qflist()) end },
    { nx, "<Plug>(qfr-grep-help)",   ql..gp.."h", "Qgrep help"..sc,      function() eg.grep("help", vimcase, sys_opt, new_qflist()) end },
    { nx, "<Plug>(qfr-grep-helpX)",  ql..gp.."H", "Qgrep help"..rx,      function() eg.grep("help", regex, sys_opt, new_qflist()) end },

    { nx, "<Plug>(qfr-lgrep-cwd)",   ll..gp.."d", "Lgrep CWD"..sc,       function() eg.grep("cwd", vimcase, sys_opt, new_loclist()) end },
    { nx, "<Plug>(qfr-lgrep-cwdX)",  ll..gp.."D", "Lgrep CWD"..rx,       function() eg.grep("cwd", regex, sys_opt, new_loclist()) end },
    { nx, "<Plug>(qfr-lgrep-help)",  ll..gp.."h", "Lgrep help"..sc,      function() eg.grep("help", vimcase, sys_opt, new_loclist()) end },
    { nx, "<Plug>(qfr-lgrep-helpX)", ll..gp.."H", "Lgrep help"..rx,      function() eg.grep("help", regex, sys_opt, new_loclist()) end },

    -- =======================
    -- == OPEN/CLOSE/RESIZE ==
    -- =======================

    { nn, "<Plug>(qfr-open-qf-list)",     ql.."p", "Open the quickfix list",               function() eo._open_qflist({ height = vim.v.count }) end },
    { nn, "<Plug>(qfr-open-qf-list-max)", ql.."P", "Open the quickfix list to max height", function() eo._open_qflist({ height = QFR_MAX_HEIGHT }) end },
    { nn, "<Plug>(qfr-close-qf-list)",    ql.."o", "Close the quickfix list",              function() eo._close_qflist() end },
    { nn, "<Plug>(qfr-toggle-qf-list)",   ql..qp, "Toggle the quickfix list",             function() eo._toggle_qflist({})  end },
    { nn, "<Plug>(qfr-open-loclist)",     ll.."p", "Open the location list",               function() eo._open_loclist(cur_win(), { height = vim.v.count }) end },
    { nn, "<Plug>(qfr-open-loclist-max)", ll.."P", "Open the location list to max height", function() eo._open_loclist(cur_win(), { height = QFR_MAX_HEIGHT }) end },
    { nn, "<Plug>(qfr-close-loclist)",    ll.."o", "Close the location list",              function() eo._close_loclist(cur_win()) end },
    { nn, "<Plug>(qfr-toggle-loclist)",   ll..lp, "Toggle the location list",             function() eo._toggle_loclist(cur_win(), {}) end },
}

-- stylua: ignore
---@type QfRancherMapData[]
local qfr_buf_maps = {
    -- =================
    -- == DIAGNOSTICS ==
    -- =================

    { nn, "<Plug>(qfr-Qdiags-hint)",  ql..dp.."n", "All buffer diagnostics min hint",     function() ed.diags_to_list({ getopts = { severity = nil } }, new_qflist()) end },
    { nn, "<Plug>(qfr-Qdiags-info)",  ql..dp.."f", "All buffer diagnostics min info",     function() ed.diags_to_list({ getopts = { severity = { min = ds.INFO } } }, new_qflist()) end },
    { nn, "<Plug>(qfr-Qdiags-warn)",  ql..dp.."w", "All buffer diagnostics min warn",     function() ed.diags_to_list({ getopts = { severity = { min = ds.WARN } } }, new_qflist()) end },
    { nn, "<Plug>(qfr-Qdiags-error)", ql..dp.."e", "All buffer diagnostics min error",    function() ed.diags_to_list({ getopts = { severity = { min = ds.ERROR } } }, new_qflist()) end },
    { nn, "<Plug>(qfr-Qdiags-top)",   ql..dp.."t", "All buffer diagnostics top severity", function() ed.diags_to_list({ top = true }, new_qflist()) end },

    { nn, "<Plug>(qfr-Qdiags-HINT)",  ql..dp.."N", "All buffer diagnostics only hint",    function() ed.diags_to_list({ getopts = { severity = ds.HINT } }, new_qflist()) end },
    { nn, "<Plug>(qfr-Qdiags-INFO)",  ql..dp.."F", "All buffer diagnostics only info",    function() ed.diags_to_list({ getopts = { severity = ds.INFO } }, new_qflist()) end },
    { nn, "<Plug>(qfr-Qdiags-WARN)",  ql..dp.."W", "All buffer diagnostics only warn",    function() ed.diags_to_list({ getopts = { severity = ds.WARN } }, new_qflist()) end },
    { nn, "<Plug>(qfr-Qdiags-ERROR)", ql..dp.."E", "All buffer diagnostics only error",   function() ed.diags_to_list({ getopts = { severity = ds.ERROR } }, new_qflist()) end },

    { nn, "<Plug>(qfr-Ldiags-hint)",  ll..dp.."n", "Cur buf diagnostics min hint",        function() ed.diags_to_list({ getopts = { severity = nil } }, new_loclist()) end },
    { nn, "<Plug>(qfr-Ldiags-info)",  ll..dp.."f", "Cur buf diagnostics min info",        function() ed.diags_to_list({ getopts = { severity = { min = ds.INFO } } }, new_loclist()) end },
    { nn, "<Plug>(qfr-Ldiags-warn)",  ll..dp.."w", "Cur buf diagnostics min warn",        function() ed.diags_to_list({ getopts = { severity = { min = ds.WARN } } }, new_loclist()) end },
    { nn, "<Plug>(qfr-Ldiags-error)", ll..dp.."e", "Cur buf diagnostics min error",       function() ed.diags_to_list({ getopts = { severity = { min = ds.ERROR } } }, new_loclist()) end },
    { nn, "<Plug>(qfr-Ldiags-top)",   ll..dp.."t", "Cur buf diagnostics top severity",    function() ed.diags_to_list({ top = true }, new_loclist()) end },

    { nn, "<Plug>(qfr-Ldiags-HINT)",  ll..dp.."N", "Cur buf diagnostics only hint",       function() ed.diags_to_list({ getopts = { severity = ds.HINT } }, new_loclist()) end },
    { nn, "<Plug>(qfr-Ldiags-INFO)",  ll..dp.."F", "Cur buf diagnostics only info",       function() ed.diags_to_list({ getopts = { severity = ds.INFO } }, new_loclist()) end },
    { nn, "<Plug>(qfr-Ldiags-WARN)",  ll..dp.."W", "Cur buf diagnostics only warn",       function() ed.diags_to_list({ getopts = { severity = ds.WARN } }, new_loclist()) end },
    { nn, "<Plug>(qfr-Ldiags-ERROR)", ll..dp.."E", "Cur buf diagnostics only error",      function() ed.diags_to_list({ getopts = { severity = ds.ERROR } }, new_loclist()) end },

    -- ============
    -- == FILTER ==
    -- ============

    -- Cfilter --

    { nx, "<Plug>(qfr-Qfilter-cfilter)",   ql..kp.."l", "Qfilter cfilter"..sc,  function() ef.filter("cfilter", true, vimcase, replace_qflist()) end },
    { nx, "<Plug>(qfr-Qfilter!-cfilter)",  ql..rp.."l", "Qfilter! cfilter"..sc, function() ef.filter("cfilter", false, vimcase, replace_qflist()) end },
    { nx, "<Plug>(qfr-Qfilter-cfilterX)",  ql..kp.."L", "Qfilter cfilter"..rx,  function() ef.filter("cfilter", true, regex, replace_qflist()) end },
    { nx, "<Plug>(qfr-Qfilter!-cfilterX)", ql..rp.."L", "Qfilter! cfilter"..rx, function() ef.filter("cfilter", false, regex, replace_qflist()) end },

    { nx, "<Plug>(qfr-Lfilter-cfilter)",   ll..kp.."l", "Lfilter cfilter"..sc,  function() ef.filter("cfilter", true, vimcase, replace_loclist()) end },
    { nx, "<Plug>(qfr-Lfilter!-cfilter)",  ll..rp.."l", "Lfilter! cfilter"..sc, function() ef.filter("cfilter", false, vimcase, replace_loclist()) end },
    { nx, "<Plug>(qfr-Lfilter-cfilterX)",  ll..kp.."L", "Lfilter cfilter"..rx,  function() ef.filter("cfilter", true, regex, replace_loclist()) end },
    { nx, "<Plug>(qfr-Lfilter!-cfilterX)", ll..rp.."L", "Lfilter! cfilter"..rx, function() ef.filter("cfilter", false, regex, replace_loclist()) end },

    -- Fname --

    { nx, "<Plug>(qfr-Qfilter-fname)",     ql..kp.."f", "Qfilter fname"..sc,    function() ef.filter("fname", true, vimcase, replace_qflist()) end },
    { nx, "<Plug>(qfr-Qfilter!-fname)",    ql..rp.."f", "Qfilter! fname"..sc,   function() ef.filter("fname", false, vimcase, replace_qflist()) end },
    { nx, "<Plug>(qfr-Qfilter-fnameX)",    ql..kp.."F", "Qfilter fname"..rx,    function() ef.filter("fname", true, regex, replace_qflist()) end },
    { nx, "<Plug>(qfr-Qfilter!-fnameX)",   ql..rp.."F", "Qfilter! fname"..rx,   function() ef.filter("fname", false, regex, replace_qflist()) end },

    { nx, "<Plug>(qfr-Lfilter-fname)",     ll..kp.."f", "Lfilter fname"..sc,    function() ef.filter("fname", true, vimcase, replace_loclist()) end },
    { nx, "<Plug>(qfr-Lfilter!-fname)",    ll..rp.."f", "Lfilter! fname"..sc,   function() ef.filter("fname", false, vimcase, replace_loclist()) end },
    { nx, "<Plug>(qfr-Lfilter-fnameX)",    ll..kp.."F", "Lfilter fname"..rx,    function() ef.filter("fname", true, regex, replace_loclist()) end },
    { nx, "<Plug>(qfr-Lfilter!-fnameX)",   ll..rp.."F", "Lfilter! fname"..rx,   function() ef.filter("fname", false, regex, replace_loclist()) end },

    -- Text --

    { nx, "<Plug>(qfr-Qfilter-text)",      ql..kp.."e", "Qfilter text"..sc,     function() ef.filter("text", true, vimcase, replace_qflist()) end },
    { nx, "<Plug>(qfr-Qfilter!-text)",     ql..rp.."e", "Qfilter! text"..sc,    function() ef.filter("text", false, vimcase, replace_qflist()) end },
    { nx, "<Plug>(qfr-Qfilter-textX)",     ql..kp.."E", "Qfilter text"..rx,     function() ef.filter("text", true, regex, replace_qflist()) end },
    { nx, "<Plug>(qfr-Qfilter!-textX)",    ql..rp.."E", "Qfilter! text"..rx,    function() ef.filter("text", false, regex, replace_qflist()) end },

    { nx, "<Plug>(qfr-Lfilter-text)",      ll..kp.."e", "Lfilter text"..sc,     function() ef.filter("text", true, vimcase, replace_loclist()) end },
    { nx, "<Plug>(qfr-Lfilter!-text)",     ll..rp.."e", "Lfilter! text"..sc,    function() ef.filter("text", false, vimcase, replace_loclist()) end },
    { nx, "<Plug>(qfr-Lfilter-textX)",     ll..kp.."E", "Lfilter text"..rx,     function() ef.filter("text", true, regex, replace_loclist()) end },
    { nx, "<Plug>(qfr-Lfilter!-textX)",    ll..rp.."E", "Lfilter! text"..rx,    function() ef.filter("text", false, regex, replace_loclist()) end },

    -- Lnum --

    { nx, "<Plug>(qfr-Qfilter-lnum)",      ql..kp.."n", "Qfilter lnum"..sc,     function() ef.filter("lnum", true, vimcase, replace_qflist()) end },
    { nx, "<Plug>(qfr-Qfilter!-lnum)",     ql..rp.."n", "Qfilter! lnum"..sc,    function() ef.filter("lnum", false, vimcase, replace_qflist()) end },
    { nx, "<Plug>(qfr-Qfilter-lnumX)",     ql..kp.."N", "Qfilter lnum"..rx,     function() ef.filter("lnum", true, regex, replace_qflist()) end },
    { nx, "<Plug>(qfr-Qfilter!-lnumX)",    ql..rp.."N", "Qfilter! lnum"..rx,    function() ef.filter("lnum", false, regex, replace_qflist()) end },

    { nx, "<Plug>(qfr-Lfilter-lnum)",      ll..kp.."n", "Lfilter lnum"..sc,     function() ef.filter("lnum", true, vimcase, replace_loclist()) end },
    { nx, "<Plug>(qfr-Lfilter!-lnum)",     ll..rp.."n", "Lfilter! lnum"..sc,    function() ef.filter("lnum", false, vimcase, replace_loclist()) end },
    { nx, "<Plug>(qfr-Lfilter-lnumX)",     ll..kp.."N", "Lfilter lnum"..rx,     function() ef.filter("lnum", true, regex, replace_loclist()) end },
    { nx, "<Plug>(qfr-Lfilter!-lnumX)",    ll..rp.."N", "Lfilter! lnum"..rx,    function() ef.filter("lnum", false, regex, replace_loclist()) end },

    -- Type --

    { nx, "<Plug>(qfr-Qfilter-type)",      ql..kp.."t", "Qfilter type"..sc,     function() ef.filter("type", true, vimcase, replace_qflist()) end },
    { nx, "<Plug>(qfr-Qfilter!-type)",     ql..rp.."t", "Qfilter! type"..sc,    function() ef.filter("type", false, vimcase, replace_qflist()) end },
    { nx, "<Plug>(qfr-Qfilter-typeX)",     ql..kp.."T", "Qfilter type"..rx,     function() ef.filter("type", true, regex, replace_qflist()) end },
    { nx, "<Plug>(qfr-Qfilter!-typeX)",    ql..rp.."T", "Qfilter! type"..rx,    function() ef.filter("type", false, regex, replace_qflist()) end },

    { nx, "<Plug>(qfr-Lfilter-type)",      ll..kp.."t", "Lfilter type"..sc,     function() ef.filter("type", true, vimcase, replace_loclist()) end },
    { nx, "<Plug>(qfr-Lfilter!-type)",     ll..rp.."t", "Lfilter! type"..sc,    function() ef.filter("type", false, vimcase, replace_loclist()) end },
    { nx, "<Plug>(qfr-Lfilter-typeX)",     ll..kp.."T", "Lfilter type"..rx,     function() ef.filter("type", true, regex, replace_loclist()) end },
    { nx, "<Plug>(qfr-Lfilter!-typeX)",    ll..rp.."T", "Lfilter! type"..rx,    function() ef.filter("type", false, regex, replace_loclist()) end },

    -- ==========
    -- == GREP ==
    -- ==========

    { nx, "<Plug>(qfr-grep-bufs)",   ql..gp.."u", "Qgrep open bufs"..sc, function() eg.grep("bufs", vimcase, sys_opt, new_qflist()) end },
    { nx, "<Plug>(qfr-grep-bufsX)",  ql..gp.."U", "Qgrep open bufs"..rx, function() eg.grep("bufs", regex, sys_opt, new_qflist()) end },
    { nx, "<Plug>(qfr-lgrep-cbuf)",  ll..gp.."u", "Lgrep cur buf"..sc,   function() eg.grep("cbuf", vimcase, sys_opt, new_loclist()) end },
    { nx, "<Plug>(qfr-lgrep-cbufX)", ll..gp.."U", "Lgrep cur buf"..rx,   function() eg.grep("cbuf", regex, sys_opt, new_loclist()) end },

    -- ================
    -- == NAVIGATION ==
    -- ================

    { nn, "<Plug>(qfr-qf-prev)",  "["..qp,         "Go to a previous qf entry",       function() en._q_prev(vim.v.count, {}) end },
    { nn, "<Plug>(qfr-qf-next)",  "]"..qp,         "Go to a later qf entry",          function() en._q_next(vim.v.count, {}) end },
    { nn, "<Plug>(qfr-qf-rewind)","["..qP,         "Go to the first qf entry",        function() en._q_rewind(vim.v.count) end },
    { nn, "<Plug>(qfr-qf-last)",  "]"..qP,         "Go to the last qf entry",         function() en._q_last(vim.v.count) end },
    { nn, "<Plug>(qfr-qf-pfile)", "[<C-"..qp..">", "Go to the previous qf file",      function() en._q_pfile(vim.v.count) end },
    { nn, "<Plug>(qfr-qf-nfile)", "]<C-"..qp..">", "Go to the next qf file",          function() en._q_nfile(vim.v.count) end },
    { nn, "<Plug>(qfr-ll-prev)",  "["..lp,         "Go to a previous loclist entry",  function() en._l_prev(cur_win(), vim.v.count, {}) end },
    { nn, "<Plug>(qfr-ll-next)",  "]"..lp,         "Go to a later loclist entry",     function() en._l_next(cur_win(), vim.v.count, {}) end },
    { nn, "<Plug>(qfr-ll-rewind)","["..lP,         "Go to the first loclist entry",   function() en._l_rewind(cur_win(), vim.v.count) end },
    { nn, "<Plug>(qfr-ll-last)",  "]"..lP,         "Go to the last loclist entry",    function() en._l_last(cur_win(), vim.v.count) end },
    { nn, "<Plug>(qfr-ll-pfile)", "[<C-"..lp..">", "Go to the previous loclist file", function() en._l_pfile(cur_win(), vim.v.count) end },
    { nn, "<Plug>(qfr-ll-nfile)", "]<C-"..lp..">", "Go to the next loclist file",     function() en._l_nfile(cur_win(), vim.v.count) end },

    -- ==========
    -- == SORT ==
    -- ==========

    { nn, "<Plug>(qfr-qsort-fname-asc)",       ql..sp.."f",     "Qsort by fname asc",       function() es.sort("fname", { dir = "asc" }, replace_qflist()) end },
    { nn, "<Plug>(qfr-qsort-fname-desc)",      ql..sp.."F",     "Qsort by fname desc",      function() es.sort("fname", { dir = "desc" }, replace_qflist()) end },
    { nn, "<Plug>(qfr-qsort-fname-diag-asc)",  ql..sp..dp.."f", "Qsort by fname_diag asc",  function() es.sort("fname_diag", { dir = "asc" }, replace_qflist()) end },
    { nn, "<Plug>(qfr-qsort-fname-diag-desc)", ql..sp..dp.."F", "Qsort by fname_diag desc", function() es.sort("fname_diag", { dir = "desc" }, replace_qflist()) end },
    { nn, "<Plug>(qfr-qsort-severity-asc)",    ql..sp..dp.."s", "Qsort by severity asc",    function() es.sort("severity", { dir = "asc" }, replace_qflist()) end },
    { nn, "<Plug>(qfr-qsort-severity-desc)",   ql..sp..dp.."S", "Qsort by severity desc",   function() es.sort("severity", { dir = "desc" }, replace_qflist()) end },
    { nn, "<Plug>(qfr-qsort-text-asc)",        ql..sp.."e",     "Qsort by text asc",        function() es.sort("text", { dir = "asc" }, replace_qflist()) end },
    { nn, "<Plug>(qfr-qsort-text-desc)",       ql..sp.."E",     "Qsort by text desc",       function() es.sort("text", { dir = "desc" }, replace_qflist()) end },
    { nn, "<Plug>(qfr-qsort-type-asc)",        ql..sp.."t",     "Qsort by type asc",        function() es.sort("type", { dir = "asc" }, replace_qflist()) end },
    { nn, "<Plug>(qfr-qsort-type-desc)",       ql..sp.."T",     "Qsort by type desc",       function() es.sort("type", { dir = "desc" }, replace_qflist()) end },

    { nn, "<Plug>(qfr-lsort-fname-asc)",       ll..sp.."f",     "Lsort by fname asc",       function() es.sort("fname", { dir = "asc" }, replace_loclist()) end },
    { nn, "<Plug>(qfr-lsort-fname-desc)",      ll..sp.."F",     "Lsort by fname desc",      function() es.sort("fname", { dir = "desc" }, replace_loclist()) end },
    { nn, "<Plug>(qfr-lsort-fname-diag-asc)",  ll..sp..dp.."f", "Lsort by fname_diag asc",  function() es.sort("fname_diag", { dir = "asc" }, replace_loclist()) end },
    { nn, "<Plug>(qfr-lsort-fname-diag-desc)", ll..sp..dp.."F", "Lsort by fname_diag desc", function() es.sort("fname_diag", { dir = "desc" }, replace_loclist()) end },
    { nn, "<Plug>(qfr-lsort-severity-asc)",    ll..sp..dp.."s", "Lsort by severity asc",    function() es.sort("severity", { dir = "asc" }, replace_loclist()) end },
    { nn, "<Plug>(qfr-lsort-severity-desc)",   ll..sp..dp.."S", "Lsort by severity desc",   function() es.sort("severity", { dir = "desc" }, replace_loclist()) end },
    { nn, "<Plug>(qfr-lsort-text-asc)",        ll..sp.."e",     "Lsort by text asc",        function() es.sort("text", { dir = "asc" }, replace_loclist()) end },
    { nn, "<Plug>(qfr-lsort-text-desc)",       ll..sp.."E",     "Lsort by text desc",       function() es.sort("text", { dir = "desc" }, replace_loclist()) end },
    { nn, "<Plug>(qfr-lsort-type-asc)",        ll..sp.."t",     "Lsort by type asc",        function() es.sort("type", { dir = "asc" }, replace_loclist()) end },
    { nn, "<Plug>(qfr-lsort-type-desc)",       ll..sp.."T",     "Lsort by type desc",       function() es.sort("type", { dir = "desc" }, replace_loclist()) end },

    -- ===========
    -- == STACK ==
    -- ===========

    -- DOCUMENT: older/newer are meant for cycling. so 2<leader>q[ will go back two lists
    -- The history commands are meant for targeting specific lists. So 2<leader>qQ will go to
    -- list two
    -- NOTE: For history, the open command is the more cumbersome map of the two. This is to
    -- align with the default behavior, where history only changes the list_nr, but does not
    -- open. If, in field testing, there are more cases where we want to open the list than
    -- just change, this can be swapped

    { nn, "<Plug>(qfr-qf-older)",        ql.."[", "Go to an older qflist",                                function() ea._q_older(vim.v.count) end },
    { nn, "<Plug>(qfr-qf-newer)",        ql.."]", "Go to a newer qflist",                                 function() ea._q_newer(vim.v.count) end },
    { nn, "<Plug>(qfr-qf-history)",      ql..qP, "View or jump within the quickfix history",              function() ea._q_history(vim.v.count, { default = "cur_list" }) end },
    { nn, "<Plug>(qfr-qf-history-open)", ql.."<C-"..qp..">", "Open and jump within the quickfix history", function() ea._q_history(vim.v.count, { open_list = true, default = "cur_list" }) end },
    { nn, "<Plug>(qfr-qf-del)",          ql.."e", "Delete a list from the quickfix stack",                function() ea._q_del(vim.v.count) end },
    { nn, "<Plug>(qfr-qf-del-all)",      ql.."E", "Delete all items from the quickfix stack",             function() ea._q_del_all() end },
    { nn, "<Plug>(qfr-ll-older)",        ll.."[", "Go to an older location list",                         function() ea._l_older(cur_win(), vim.v.count) end },
    { nn, "<Plug>(qfr-ll-newer)",        ll.."]", "Go to a newer location list",                          function() ea._l_newer(cur_win(), vim.v.count) end },
    { nn, "<Plug>(qfr-ll-history)",      ll..lP, "View or jump within the loclist history",               function() ea._l_history(cur_win(), vim.v.count, { default = "cur_list" }) end },
    { nn, "<Plug>(qfr-ll-history-open)", ll.."<C-"..lp..">", "Open and jump within the loclist history",  function() ea._l_history(cur_win(), vim.v.count, { open_list = true, default = "cur_list" }) end },
    { nn, "<Plug>(qfr-ll-del)",          ll.."e", "Delete a list from the loclist stack",                 function() ea._l_del(cur_win(), vim.v.count) end },
    { nn, "<Plug>(qfr-ll-del-all)",      ll.."E", "Delete all items from the loclist stack",              function() ea._l_del_all(cur_win()) end },
}

-- NOTE: This table needs to be separate or else the plug mapping pass will map "<nop>", which
-- causes multiple problems

-- stylua: ignore
---@type QfRancherMapData[]
local rancher_keymap_default_rm = {
    { nx, "<nop>", ql,     "Avoid falling back to defaults", nil },
    { nx, "<nop>", ll,     "Avoid falling back to defaults", nil },

    { nx, "<nop>", ql..dp, "Avoid falling back to defaults", nil },
    { nx, "<nop>", ll..dp, "Avoid falling back to defaults", nil },

    { nx, "<nop>", ql..kp, "Avoid falling back to defaults", nil },
    { nx, "<nop>", ql..rp, "Avoid falling back to defaults", nil },
    { nx, "<nop>", ll..kp, "Avoid falling back to defaults", nil },
    { nx, "<nop>", ll..rp, "Avoid falling back to defaults", nil },

    { nx, "<nop>", ql..gp, "Avoid falling back to defaults", nil },
    { nx, "<nop>", ll..gp, "Avoid falling back to defaults", nil },

    { nn, "<nop>", ql..sp, "Avoid falling back to defaults", nil },
    { nn, "<nop>", ll..sp, "Avoid falling back to defaults", nil },
}

for _, map in ipairs(qfr_maps) do
    for _, mode in ipairs(map[1]) do
        api.nvim_set_keymap(mode, map[2], "", {
            callback = map[5],
            desc = map[4],
            noremap = true,
        })
    end
end

for _, map in ipairs(qfr_buf_maps) do
    for _, mode in ipairs(map[1]) do
        api.nvim_set_keymap(mode, map[2], "", {
            callback = map[5],
            desc = map[4],
            noremap = true,
        })
    end
end

-- Don't use the util g_var wrapper here to avoid a require
if vim.g.qfr_map_set_defaults then
    for _, map in ipairs(qfr_maps) do
        for _, mode in ipairs(map[1]) do
            api.nvim_set_keymap(mode, map[3], map[2], {
                desc = map[4],
                noremap = true,
            })
        end
    end

    for _, map in ipairs(rancher_keymap_default_rm) do
        for _, mode in ipairs(map[1]) do
            api.nvim_set_keymap(mode, map[3], map[2], {
                desc = map[4],
                noremap = true,
            })
        end
    end

    api.nvim_create_autocmd({ "BufNew", "BufReadPre" }, {
        group = api.nvim_create_augroup("qfr-buf-maps", {}),
        callback = function()
            for _, map in ipairs(qfr_buf_maps) do
                for _, mode in ipairs(map[1]) do
                    api.nvim_set_keymap(mode, map[3], map[2], {
                        desc = map[4],
                        noremap = true,
                    })
                end
            end

            api.nvim_del_augroup_by_name("qfr-buf-maps")
        end,
    })
end

-- ===================
-- == FTPLUGIN MAPS ==
-- ===================

vim.keymap.set("n", "<Plug>(qfr-list-del-one)", function()
    ei._del_one_list_item()
end, { desc = "Delete the current list line" })

vim.keymap.set("x", "<Plug>(qfr-list-visual-del)", function()
    ei._visual_del()
end, { desc = "Delete a visual line selection" })

vim.keymap.set("n", "<Plug>(qfr-list-toggle-preview)", function()
    ep.toggle_preview_win(api.nvim_get_current_win())
end, { desc = "Toggle the preview win" })

vim.keymap.set("n", "<Plug>(qfr-list-update-preview-pos)", function()
    ep.update_preview_win_pos()
end, { desc = "Update the preview win position" })

vim.keymap.set("n", "<Plug>(qfr-list-open-direct-focuswin)", function()
    ei._open_direct_focuswin()
end, { desc = "Open a list item and focus on it" })

vim.keymap.set("n", "<Plug>(qfr-list-open-direct-focuslist)", function()
    ei._open_direct_focuslist()
end, { desc = "Open a list item, keep list focus" })

vim.keymap.set("n", "<Plug>(qfr-list-prev)", function()
    ei._open_prev_focuslist()
end, { desc = "Go to a previous qf entry, keep window focus" })

vim.keymap.set("n", "<Plug>(qfr-list-next)", function()
    ei._open_next_focuslist()
end, { desc = "Go to a later qf entry, keep window focus" })

vim.keymap.set("n", "<Plug>(qfr-list-open-split-focuswin)", function()
    ei._open_split_focuswin()
end, { desc = "Open a list item in a split and focus on it" })

vim.keymap.set("n", "<Plug>(qfr-list-open-split-focuslist)", function()
    ei._open_split_focuslist()
end, { desc = "Open a list item in a split, keep list focus" })

vim.keymap.set("n", "<Plug>(qfr-list-open-vsplit-focuswin)", function()
    ei._open_vsplit_focuswin()
end, { desc = "Open a list item in a vsplit and focus on it" })

vim.keymap.set("n", "<Plug>(qfr-list-open-vsplit-focuslist)", function()
    ei._open_vsplit_focuslist()
end, { desc = "Open a list item in a vsplit, keep list focus" })

vim.keymap.set("n", "<Plug>(qfr-list-open-tabnew-focuswin)", function()
    ei._open_tabnew_focuswin()
end, { desc = "Open a list item in a new tab and focus on it" })

vim.keymap.set("n", "<Plug>(qfr-list-open-tabnew-focuslist)", function()
    ei._open_tabnew_focuslist()
end, { desc = "Open a list item in a new tab, keep list focus" })

-- ==========
-- == CMDS ==
-- ==========

-- Don't use the util g_var wrapper here to avoid a require
if vim.g.qfr_set_default_cmds then
    -- ===========
    -- == DIAGS ==
    -- ===========

    api.nvim_create_user_command("Qdiag", function(cargs)
        ed.q_diag_cmd(cargs)
    end, { bang = true, count = 0, nargs = "*", desc = "Send diags to the Quickfix list" })

    api.nvim_create_user_command("Ldiag", function(cargs)
        ed.l_diag_cmd(cargs)
    end, { bang = true, count = 0, nargs = "*", desc = "Send buf diags to the Location list" })

    -- ============
    -- == FILTER ==
    -- ============

    api.nvim_create_user_command("Qfilter", function(cargs)
        ef.q_filter_cmd(cargs)
    end, { bang = true, count = true, nargs = "*", desc = "Sort quickfix items" })

    api.nvim_create_user_command("Lfilter", function(cargs)
        ef.l_filter_cmd(cargs)
    end, { bang = true, count = true, nargs = "*", desc = "Sort loclist items" })

    -- ==========
    -- == GREP ==
    -- ==========

    api.nvim_create_user_command("Qgrep", function(cargs)
        eg.q_grep_cmd(cargs)
    end, { count = true, nargs = "*", desc = "Grep to the quickfix list" })

    api.nvim_create_user_command("Lgrep", function(cargs)
        eg.l_grep_cmd(cargs)
    end, { count = true, nargs = "*", desc = "Grep to the location list" })

    -- =======================
    -- == OPEN/CLOSE/TOGGLE ==
    -- =======================

    api.nvim_create_user_command("Qopen", function(cargs)
        eo.open_qflist_cmd(cargs)
    end, { count = 0, desc = "Open the Quickfix list" })

    api.nvim_create_user_command("Lopen", function(cargs)
        eo.open_loclist_cmd(cargs)
    end, { count = 0, desc = "Open the Location List" })

    api.nvim_create_user_command("Qclose", function()
        eo.close_qflist_cmd()
    end, { desc = "Close the Quickfix list" })

    api.nvim_create_user_command("Lclose", function()
        eo.close_loclist_cmd()
    end, { desc = "Close the Location List" })

    api.nvim_create_user_command("Qtoggle", function(cargs)
        eo.toggle_qflist_cmd(cargs)
    end, { count = 0, desc = "Toggle the Quickfix list" })

    api.nvim_create_user_command("Ltoggle", function(cargs)
        eo.toggle_loclist_cmd(cargs)
    end, { count = 0, desc = "Toggle the Location List" })

    -- ================
    -- == NAV/ACTION ==
    -- ================

    api.nvim_create_user_command("Qprev", function(cargs)
        en.q_prev_cmd(cargs)
    end, { count = 0, desc = "Go to a previous qf entry" })

    api.nvim_create_user_command("Qnext", function(cargs)
        en.q_next_cmd(cargs)
    end, { count = 0, desc = "Go to a later qf entry" })

    api.nvim_create_user_command("Qrewind", function(cargs)
        en.q_rewind_cmd(cargs)
    end, { count = 0, desc = "Go to the first or count qf entry" })

    api.nvim_create_user_command("Qlast", function(cargs)
        en.q_last_cmd(cargs)
    end, { count = 0, desc = "Go to the last or count qf entry" })

    api.nvim_create_user_command("Qq", function(cargs)
        en.q_q_cmd(cargs)
    end, { count = 0, desc = "Go to the current qf entry" })

    api.nvim_create_user_command("Qpfile", function(cargs)
        en.q_pfile_cmd(cargs)
    end, { count = 0, desc = "Go to the previous qf file" })

    api.nvim_create_user_command("Qnfile", function(cargs)
        en.q_nfile_cmd(cargs)
    end, { count = 0, desc = "Go to the next qf file" })

    api.nvim_create_user_command("Lprev", function(cargs)
        en.l_prev_cmd(cargs)
    end, { count = 0, desc = "Go to a previous loclist entry" })

    api.nvim_create_user_command("Lnext", function(cargs)
        en.l_next_cmd(cargs)
    end, { count = 0, desc = "Go to a later loclist entry" })

    api.nvim_create_user_command("Lrewind", function(cargs)
        en.l_rewind_cmd(cargs)
    end, { count = 0, desc = "Go to the first or count loclist entry" })

    api.nvim_create_user_command("Llast", function(cargs)
        en.l_last_cmd(cargs)
    end, { count = 0, desc = "Go to the last or count loclist entry" })

    api.nvim_create_user_command("Ll", function(cargs)
        en.l_l_cmd(cargs)
    end, { count = 0, desc = "Go to the current loclist entry" })

    api.nvim_create_user_command("Lpfile", function(cargs)
        en.l_pfile_cmd(cargs)
    end, { count = 0, desc = "Go to the previous loclist file" })

    api.nvim_create_user_command("Lnfile", function(cargs)
        en.l_nfile_cmd(cargs)
    end, { count = 0, desc = "Go to the next loclist file" })

    -- ==========
    -- == SORT ==
    -- ==========

    api.nvim_create_user_command("Qsort", function(cargs)
        es.q_sort(cargs)
    end, { bang = true, count = 0, nargs = 1 })

    api.nvim_create_user_command("Lsort", function(cargs)
        es.l_sort(cargs)
    end, { bang = true, count = 0, nargs = 1 })

    -- ===========
    -- == STACK ==
    -- ===========

    api.nvim_create_user_command("Qolder", function(cargs)
        ea.q_older_cmd(cargs)
    end, { count = 0, desc = "Go to an older qflist" })

    api.nvim_create_user_command("Qnewer", function(cargs)
        ea.q_newer_cmd(cargs)
    end, { count = 0, desc = "Go to a newer qflist" })

    api.nvim_create_user_command("Qhistory", function(cargs)
        ea.q_history_cmd(cargs)
    end, { count = 0, desc = "View or jump within the quickfix history" })

    api.nvim_create_user_command("Qdelete", function(cargs)
        ea.q_delete_cmd(cargs)
    end, { count = 0, nargs = "?", desc = "Delete one or all lists from the quickfix stack" })

    api.nvim_create_user_command("Lolder", function(cargs)
        ea._l_older_cmd(cargs)
    end, { count = 0, desc = "Go to an older location list" })

    api.nvim_create_user_command("Lnewer", function(cargs)
        ea._l_newer_cmd(cargs)
    end, { count = 0, desc = "Go to a newer location list" })

    api.nvim_create_user_command("Lhistory", function(cargs)
        ea.l_history_cmd(cargs)
    end, { count = 0, desc = "View or jump within the loclist history" })

    api.nvim_create_user_command("Ldelete", function(cargs)
        ea.l_delete_cmd(cargs)
    end, { count = 0, nargs = "?", desc = "Delete one or all lists from the loclist stack" })
end

---@export nvim-qf-rancher

-- NOTES:
-- - Any space breaks in annotation comments are intentional to make lemmy-ehlp ignore them

-- TODO: Create docgen script. 'lemmy-help -l "compact" [fnames] > output.txt'

-- DOCUMENT: For cmd mappings, document what cmd opts they expect to be available

-- TEST: Put a confirm statement in every file. None of them should fire on startup
-- Smarter way would be to inspect the cache of loaded modules

-- MID: Alias wintype annotations?
-- MID: Publish Qf items as diagnostics. Would make other ideas more useful
-- MID: Remaining Commands to handle:
-- - cexpr
-- - cbuffer/cgetbuffer/caddbuffer
-- - cfile
-- - clist
-- - cabove/cbelow
-- MID: How to make the list more useful with compilers. Possible starting points:
-- - https://github.com/Zeioth/compiler.nvim
-- - https://github.com/ahmedkhalf/project.nvim
-- - https://github.com/stevearc/overseer.nvim
-- - :h :make_makeprg
-- - :h compiler-select
-- MID: Add ftplugin files that use rancher, such as make commands piped to the system module
-- MID: The open mappings and such should work in visual mode
-- LOW: If we explore the idea of editing the qf buffer, the best way to do it seems to be to
-- treat "edit mode" as a distinct thing, where it can then be saved and propagate the changes
-- - https://github.com/gabrielpoca/replacer.nvim
-- - https://github.com/stefandtw/quickfix-reflector.vim

-- LOW: A way to copy/replace/merge whole lists
-- LOW: Is there a way to bridge lists between the qf and loclists?
-- LOW: View adjustments should take into account scrolloff and screenlines so that if the
-- user re-enters the window, it doesn't shift to meet scrolloff requirements
-- LOW: How to improve on cdo/cfdo? Random errors on substitution are bad
-- cfdo is fairly feasible because you can win_call or buf_call on every file behind a pcall
-- But then how to show errors
-- LOW: Smoother way to run cmds from visual mode without manually removing the marks. I don't
-- want the cmds to accept then throw away a range. Deceptive UI
-- LOW: Better error format. The default masking of certain error types hides info from the
-- user. Would also be helpful if pipe cols were more consistent
-- LOW: ts-context integration in preview wins
-- LOW: scrolling in preview wins
-- LOW: Allow customizing windows to skip when looking for open targets:
-- - https://github.com/kevinhwang91/nvim-bqf/issues/78
-- LOW: Incremental preview of cdo/cfdo changes
-- LOW: General cmd parsing: https://github.com/niuiic/quickfix.nvim
-- LOW: Somehow auto-generate the keymaps. Would help with docgen
-- LOW: Use a g:var to control regex case sensitivity

-- DOCUMENT: vim.regex currently uses case sensitive default behavior
-- DOCUMENT: cmds are not designed to be run in visual mode
-- DOCUMENT: How default counts are treated in cmds and maps
-- DOCUMENT: Buf greps use external grep
-- DOCUMENT: qf Buf Grep is all bufs, ll Buf Grep is current buf only
-- DOCUMENT: rg handles true multi-line greps. For programs that don't, or is used as a fallback
-- DOCUMENT: The following are non-goals:
-- - Creating persistent state beyond what is necessary to make the preview win work
-- - Dynamically modifying buffers within the qflist
-- - Providing additional context within the list itself. Covered by the preview win
-- - No Fuzzy finding type stuff. FzfLua does this. And as far as I know, all the major finders
--   have the ability to search the qflists
-- - No annotations. Should be able to filter down to key items
-- - Dynamic behavior. Trouble has to create a whole async runtime and data model to manage this
-- - "Modernizing" the feel of the qflist. The old school feel is part of the charm
-- DOCUMENT: Cmds don't accept ranges
-- DOCUMENT: The open functions double as resizers, as per the default cmd behavior
-- DOCUMENT: If open is run and the list is open, go to the list
-- DOCUMENT: underline functions are not supported
-- DOCUMENT: What types of regex are used where. Grep cmds have their own regex. Regex filters use
-- vim regex
-- DOCUMENT: The README should include alternatives, including quicker

-- PR: Fix wintype annotations
-- PR: It should be possible to output vimgrep to a list so it can be used by internal scripting
-- PR: It would be better if cmd marks produced rows and columns

-- RESOURCES --
-- https://github.com/romainl/vim-qf
-- https://github.com/kevinhwang91/nvim-bqf
-- https://github.com/arsham/listish.nvim
-- https://github.com/itchyny/vim-qfedit -- Simple version of quicker
-- https://github.com/mileszs/ack.vim
-- https://github.com/stevearc/qf_helper.nvim
-- https://github.com/niuiic/quickfix.nvim
-- https://github.com/mhinz/vim-grepper
-- https://github.com/ten3roberts/qf.nvim

-- PREVIEWERS --
-- https://github.com/r0nsha/qfpreview.nvim
-- https://github.com/bfrg/vim-qf-preview
