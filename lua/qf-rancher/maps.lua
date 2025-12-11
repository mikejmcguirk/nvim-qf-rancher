local M = {}

-- Create a local version of this function because the docgen can't see the global
local function maps_defer_require(path)
    return setmetatable({}, {
        __index = function(_, key)
            return require(path)[key]
        end,

        __newindex = function(_, key, value)
            require(path)[key] = value
        end,
    })
end

local ra_str = "stack" ---@type string
local ra = maps_defer_require("qf-rancher." .. ra_str) ---@type QfrStack
local rd_str = "diagnostic" ---@type string
local rd = maps_defer_require("qf-rancher." .. rd_str) ---@type QfRancherDiagnostics
local rf_str = "filter" ---@type string
local rf = maps_defer_require("qf-rancher." .. rf_str) ---@type QfrFilter
local rg_str = "grep" ---@type string
local rg = maps_defer_require("qf-rancher." .. rg_str) ---@type QfrGrep
local ri = maps_defer_require("qf-rancher.filetype-funcs") ---@type QfRancherFiletypeFuncs
local rn_str = "nav" ---@type string
local rn = maps_defer_require("qf-rancher." .. rn_str) ---@type QfRancherNav
local rw_str = "window" ---@type string
local rw = maps_defer_require("qf-rancher." .. rw_str) ---@type QfrWins
local rr = maps_defer_require("qf-rancher.preview") ---@type QfRancherPreview
local rs_str = "sort" ---@type string
local rs = maps_defer_require("qf-rancher." .. rs_str) ---@type QfRancherSort

local nn = { "n" } ---@type string[]
local xx = { "x" } ---@type string[]
local nx = { "n", "x" } ---@type string[]

local qp = "q" ---@type string
local ql = "<leader>" .. qp ---@type string
local qP = string.upper(qp) ---@type string

local lp = "l" ---@type string
local ll = "<leader>" .. lp ---@type string
local lP = string.upper(lp) ---@type string

local dp = "i" ---@type string
local kp = "k" ---@type string
local rp = "r" ---@type string
local gp = "g" ---@type string
local sp = "t" ---@type string

local vc = " (vimcase)" ---@type string
local rx = " (regex)" ---@type string

local vimcase = { input_type = "vimcase" } ---@type QfrInputOpts
local regex = { input_type = "regex" } ---@type QfrInputOpts

---@return integer
local function cur_win()
    return vim.api.nvim_get_current_win()
end

---@param action QfrAction
---@param src_win integer|nil
---@return QfrOutputOpts
local function get_output_opts(src_win, action)
    -- MID: This is reasonable default behavior, but not the best place to define it
    local nr = action == " " and "$" or 0 ---@type integer|"$"
    if vim.v.count > 0 then
        nr = vim.v.count
    end
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

-- NOTE: In order for the defer require to work, all function calls must be inside of
-- anonymous functions. If you pass, for example, eo.closeqflist as a function reference, eo
-- needs to be evaluated at command creation

-- Mode(s), Plug Map, User Map, Desc, Action
--- @alias QfrMapData{ [1]:string[], [2]:string, [3]:string, [4]: string, [5]: function }

-- Cmd, Function, cmd args
--- @alias QfrCmdData{ [1]:string, [2]:function, [3]:vim.api.keyset.user_command }

M.plug_tbls = {} ---@type QfrMapData[][]
M.uienter_tbls = {} ---@type QfrMapData[][]
M.bufevent_tbls = {} ---@type QfrMapData[][]
M.cmd_tbls = {} ---@type QfrCmdData[][]
M.doc_tbls = {} ---@type { [1]: string, [2]:QfrMapData[], [3]: QfrCmdData[] }[]

-- stylua: ignore
---@type QfrMapData[]
M.qfr_win_maps = {
{ nn, "<Plug>(qfr-open-qf-list)",     ql.."p", "Open the quickfix list to [count] height (focus if already open)", function() rw.open_qflist({ height = vim.v.count }) end },
{ nn, "<Plug>(qfr-close-qf-list)",    ql.."o", "Close the quickfix list",                                          function() rw.close_qflist() end },
{ nn, "<Plug>(qfr-toggle-qf-list)",   ql..qp,  "Toggle the quickfix list (count sets height on open)",             function() rw.toggle_qflist({})  end },
{ nn, "<Plug>(qfr-open-loclist)",     ll.."p", "Open the location list to [count] height (focus if already open)", function() rw.open_loclist(cur_win(), { height = vim.v.count }) end },
{ nn, "<Plug>(qfr-close-loclist)",    ll.."o", "Close the location list",                                          function() rw.close_loclist(cur_win()) end },
{ nn, "<Plug>(qfr-toggle-loclist)",   ll..lp,  "Toggle the location list (count sets height on open)",             function() rw.toggle_loclist(cur_win(), {}) end },
}

-- stylua: ignore
---@type QfrCmdData[]
M.qfr_win_cmds = {
{ "Qopen",   function(cargs) rw.open_qflist_cmd(cargs) end,    { count = 0, desc = "Open the quickfix list to [count] height (focus if already open)" } },
{ "Qclose",  function() rw.close_qflist_cmd() end,             { desc = "Close the Quickfix list" } },
{ "Qtoggle", function(cargs) rw.toggle_qflist_cmd(cargs) end,  { count = 0, desc = "Toggle the quickfix list (count sets height on open)" } },
{ "Lopen",   function(cargs) rw.open_loclist_cmd(cargs) end,   { count = 0, desc = "Open the location list to [count] height (focus if already open)" } },
{ "Lclose",  function() rw.close_loclist_cmd() end,            { desc = "Close the location List" } },
{ "Ltoggle", function(cargs) rw.toggle_loclist_cmd(cargs) end, { count = 0, desc = "Toggle the location list (count sets height on open)" } },
}

M.plug_tbls[#M.plug_tbls + 1] = M.qfr_win_maps
M.uienter_tbls[#M.uienter_tbls + 1] = M.qfr_win_maps
M.cmd_tbls[#M.cmd_tbls + 1] = M.qfr_win_cmds
M.doc_tbls[#M.doc_tbls + 1] = { rw_str, M.qfr_win_maps, M.qfr_win_cmds }

-- MID: Have/create a bespoke version of [q/]q and the like that ignores useopen. It's a nag when
-- trying to scroll through buffers and the open win changes because of that setting
-- This would apply to the ftplugin {} maps as well
-- It could be possible to only apply this logic to {}, but that is weird to reason about, whereas
-- "qfr_ignore_useopen_on_scroll" or something like that is mentally tractable
-- UPDATE: Should be an option to use the current window
-- qfr_quickfix_nav_use_cur_win is long though
-- Can't apply to location lists since they're window bound

-- stylua: ignore
---@type QfrMapData[]
M.qfr_nav_maps = {
{ nn, "<Plug>(qfr-qf-prev)",  "["..qp,         "Go to the [count] previous quickfix entry. Count is wrapping",      function() rn.q_prev(vim.v.count, {}) end },
{ nn, "<Plug>(qfr-qf-next)",  "]"..qp,         "Go to the [count] next quickfix entry. Count is wrapping",          function() rn.q_next(vim.v.count, {}) end },
{ nn, "<Plug>(qfr-qf-rewind)","["..qP,         "Go to the [count] quickfix entry, or the first if no count",        function() rn.q_rewind(vim.v.count) end },
{ nn, "<Plug>(qfr-qf-last)",  "]"..qP,         "Go to the [count] quickfix entry, or the last if no count",         function() rn.q_last(vim.v.count) end },
{ nn, "<Plug>(qfr-qf-pfile)", "[<C-"..qp..">", "Go to the [count] previous quickfix file. Wrap to the last file",   function() rn.q_pfile(vim.v.count) end },
{ nn, "<Plug>(qfr-qf-nfile)", "]<C-"..qp..">", "Go to the [count] next quickfix file. Wrap to the first file",      function() rn.q_nfile(vim.v.count) end },
{ nn, "<Plug>(qfr-ll-prev)",  "["..lp,         "Go to the [count] previous location list entry. Count is wrapping", function() rn.l_prev(cur_win(), vim.v.count, {}) end },
{ nn, "<Plug>(qfr-ll-next)",  "]"..lp,         "Go to the [count] next location list entry. Count is wrapping",     function() rn.l_next(cur_win(), vim.v.count, {}) end },
{ nn, "<Plug>(qfr-ll-rewind)","["..lP,         "Go to the [count] quickfix entry, or the first if no count",        function() rn.l_rewind(cur_win(), vim.v.count) end },
{ nn, "<Plug>(qfr-ll-last)",  "]"..lP,         "Go to the [count] quickfix entry, or the last if no count",         function() rn.l_last(cur_win(), vim.v.count) end },
{ nn, "<Plug>(qfr-ll-pfile)", "[<C-"..lp..">", "Go to the [count] previous quickfix file. Wrap to the last file",   function() rn.l_pfile(cur_win(), vim.v.count) end },
{ nn, "<Plug>(qfr-ll-nfile)", "]<C-"..lp..">", "Go to the [count] next quickfix file. Wrap to the first file",      function() rn.l_nfile(cur_win(), vim.v.count) end },
}

-- stylua: ignore
---@type QfrCmdData[]
M.qfr_nav_cmds = {
{ "Qprev",   function(cargs) rn.q_prev_cmd(cargs) end, { count = 0, desc = "Go to the [count] previous quickfix entry. Count is wrapping" } },
{ "Qnext",   function(cargs) rn.q_next_cmd(cargs) end, { count = 0, desc = "Go to the [count] next quickfix entry. Count is wrapping" } },
{ "Qrewind", function(cargs) rn.q_rewind_cmd(cargs) end, { count = 0, desc = "Go to the [count] quickfix entry, or the first if no count" } },
{ "Qq",      function(cargs) rn.q_q_cmd(cargs) end, { count = 0, desc = "Go to the [count] qf entry, or under the cursor, or current idx" } },
{ "Qlast",   function(cargs) rn.q_last_cmd(cargs) end, { count = 0, desc = "Go to the [count] quickfix entry, or the last if no count" } },
{ "Qpfile",  function(cargs) rn.q_pfile_cmd(cargs) end, { count = 0, desc = "Go to the [count] previous quickfix file. Wrap to the last file" } },
{ "Qnfile",  function(cargs) rn.q_nfile_cmd(cargs) end, { count = 0, desc = "Go to the [count] next quickfix file. Wrap to the first file" } },
{ "Lprev",   function(cargs) rn.l_prev_cmd(cargs) end, { count = 0, desc = "Go to the [count] previous location list entry. Count is wrapping" } },
{ "Lnext",   function(cargs) rn.l_next_cmd(cargs) end, { count = 0, desc = "Go to the [count] next location list entry. Count is wrapping" } },
{ "Ll",      function(cargs) rn.l_l_cmd(cargs) end, { count = 0, desc = "Go to the [count] loclist entry, or under the cursor, or current idx" } },
{ "Lrewind", function(cargs) rn.l_rewind_cmd(cargs) end, { count = 0, desc = "Go to the [count] quickfix entry, or the first if no count" } },
{ "Llast",   function(cargs) rn.l_last_cmd(cargs) end, { count = 0, desc = "Go to the [count] quickfix entry, or the last if no count" } },
{ "Lpfile",  function(cargs) rn.l_pfile_cmd(cargs) end, { count = 0, desc = "Go to the [count] previous quickfix file. Wrap to the last file" } },
{ "Lnfile",  function(cargs) rn.l_nfile_cmd(cargs) end, { count = 0, desc = "Go to the [count] next quickfix file. Wrap to the first file" } },
}

M.plug_tbls[#M.plug_tbls + 1] = M.qfr_nav_maps
M.bufevent_tbls[#M.bufevent_tbls + 1] = M.qfr_nav_maps
M.cmd_tbls[#M.cmd_tbls + 1] = M.qfr_nav_cmds
M.doc_tbls[#M.doc_tbls + 1] = { rn_str, M.qfr_nav_maps, M.qfr_nav_cmds }

-- stylua: ignore
---@type QfrMapData[]
M.qfr_stack_maps = {
{ nn, "<Plug>(qfr-qf-older)",     ql.."[", "Go to the [count] older quickfix list. Count is wrapping",            function() ra.q_older(vim.v.count1) end },
{ nn, "<Plug>(qfr-qf-newer)",     ql.."]", "Go to the [count] newer quickfix list. Count is wrapping",            function() ra.q_newer(vim.v.count1) end },
{ nn, "<Plug>(qfr-qf-history)",   ql..qP,  "Jump to [count] list in the quickfix stack or view the current list", function() ra.q_history(vim.v.count) end },
{ nn, "<Plug>(qfr-qf-clear)",     ql.."e", "Clear a list from the quickfix stack",                                function() ra.q_clear(vim.v.count) end },
{ nn, "<Plug>(qfr-qf-clear-all)", ql.."E", "Clear the quickfix stack",                                            function() ra.q_clear_all() end },
{ nn, "<Plug>(qfr-ll-older)",     ll.."[", "Go to the [count] older location list. Count is wrapping",            function() ra.l_older(cur_win(), vim.v.count1) end },
{ nn, "<Plug>(qfr-ll-newer)",     ll.."]", "Go to the [count] newer location list. Count is wrapping",            function() ra.l_newer(cur_win(), vim.v.count1) end },
{ nn, "<Plug>(qfr-ll-history)",   ll..lP,  "Jump to [count] list in the loclist stack or view the current list",  function() ra.l_history(cur_win(), vim.v.count) end },
{ nn, "<Plug>(qfr-ll-clear)",     ll.."e", "Clear a list from the loclist stack",                                 function() ra.l_clear(cur_win(), vim.v.count) end },
{ nn, "<Plug>(qfr-ll-clear-all)", ll.."E", "Clear the loclist stack",                                             function() ra.l_clear_all(cur_win()) end },
}

-- MID: instead of delete, "clear". Shorter

-- stylua: ignore
---@type QfrCmdData[]
M.qfr_stack_cmds = {
{ "Qolder",   function(cargs) ra.q_older_cmd(cargs) end, { count = 0, desc = "Go to the [count] older quickfix list. Count is wrapping" } },
{ "Qnewer",   function(cargs) ra.q_newer_cmd(cargs) end, { count = 0, desc = "Go to the [count] newer quickfix list. Count is wrapping" } },
{ "Qhistory", function(cargs) ra.q_history_cmd(cargs) end, { count = 0, desc = "Jump to [count] list in the quickfix stack or show the entire stack" } },
{ "Qdelete",  function(cargs) ra.q_clear_cmd(cargs) end, { count = 0, nargs = "?", desc = 'Delete [count] list "all" lists from the quickfix stack' } },
{ "Lolder",   function(cargs) ra.l_older_cmd(cargs) end, { count = 0, desc = "Go to the [count] older location list. Count is wrapping" } },
{ "Lnewer",   function(cargs) ra.l_newer_cmd(cargs) end, { count = 0, desc = "Go to the [count] newer location list. Count is wrapping" } },
{ "Lhistory", function(cargs) ra.l_history_cmd(cargs) end, { count = 0, desc = "Jump to [count] list in the loclist stack or show the entire stack" } },
{ "Ldelete",  function(cargs) ra.l_clear_cmd(cargs) end, { count = 0, nargs = "?", desc = 'Delete [count] list or "all" lists from the loclist stack' } },
}

M.plug_tbls[#M.plug_tbls + 1] = M.qfr_stack_maps
M.bufevent_tbls[#M.bufevent_tbls + 1] = M.qfr_stack_maps
M.cmd_tbls[#M.cmd_tbls + 1] = M.qfr_stack_cmds
M.doc_tbls[#M.doc_tbls + 1] = { ra_str, M.qfr_stack_maps, M.qfr_stack_cmds }

-- stylua: ignore
---@type QfrMapData[]
M.qfr_ftplugin_maps = {
{ nn, "<Plug>(qfr-list-del-one)",               "dd", "Delete the current list line",                      function() ri._del_one_list_item() end },
{ xx, "<Plug>(qfr-list-visual-del)",            "d", "Delete a visual line list selection",                function() ri._visual_del() end },
{ nn, "<Plug>(qfr-list-toggle-preview)",        "p", "Toggle the list preview win",                        function() rr.toggle_preview_win(cur_win()) end },
{ nn, "<Plug>(qfr-list-update-preview-pos)",    "P", "Update the preview win position",                    function() rr.update_preview_win_pos() end },
{ nn, "<Plug>(qfr-list-prev)",                  "{", "Go to the previous list entry, keep list focus",     function() ri._open_prev_focuslist() end },
{ nn, "<Plug>(qfr-list-next)",                  "}", "Go to the next list entry, keep list focus",         function() ri._open_next_focuslist() end },
{ nn, "<Plug>(qfr-list-open-direct-focuswin)",  "o", "Open a list item",                                   function() ri._open_direct_focuswin() end },
{ nn, "<Plug>(qfr-list-open-direct-focuslist)", "<C-o>", "Open a list item, keep list focus",              function() ri._open_direct_focuslist() end },
{ nn, "<Plug>(qfr-list-open-split-focuswin)",   "s", "Open a list item in a split",                        function() ri._open_split_focuswin() end },
{ nn, "<Plug>(qfr-list-open-split-focuslist)",  "<C-s>", "Open a list item in a split, keep list focus",   function() ri._open_split_focuslist() end },
{ nn, "<Plug>(qfr-list-open-vsplit-focuswin)",  "v", "Open a list item in a vsplit",                       function() ri._open_vsplit_focuswin() end },
{ nn, "<Plug>(qfr-list-open-vsplit-focuslist)", "<C-v>", "Open a list item in a vsplit, keep list focus",  function() ri._open_vsplit_focuslist() end },
{ nn, "<Plug>(qfr-list-open-tabnew-focuswin)",  "x", "Open a list item in a new tab",                      function() ri._open_tabnew_focuswin() end },
{ nn, "<Plug>(qfr-list-open-tabnew-focuslist)", "<C-x>", "Open a list item in a new tab, keep list focus", function() ri._open_tabnew_focuslist() end },
}

M.plug_tbls[#M.plug_tbls + 1] = M.qfr_ftplugin_maps
M.doc_tbls[#M.doc_tbls + 1] = { "qf", M.qfr_ftplugin_maps, {} }

local gl = maps_defer_require("qf-rancher.lib.grep_locs") ---@type QfrLibGrepLocs

-- stylua: ignore
local cwd_grep = function() return { name = "CWD" } end
-- stylua: ignore
local cwd_grepX = function() return { name = "CWD", regex = true } end
-- stylua: ignore
local help_grep = function() return { locations = gl.get_help_dirs(), name = "Help" } end
-- stylua: ignore
local help_grepX = function() return { locations = gl.get_help_dirs(), name = "Help", regex = true } end
-- stylua: ignore
local bufs_grep = function() return { locations = gl.get_buflist(), name = "Buf" } end
-- stylua: ignore
local bufs_grepX = function() return { locations = gl.get_buflist(), name = "Buf", regex = true } end
-- stylua: ignore
local cbuf_grep = function() return { locations = gl.get_cur_buf(), name = "Cur Buf" } end
-- stylua: ignore
local cbuf_grepX = function() return { locations = gl.get_cur_buf(), name = "Cur Buf", regex = true } end

-- stylua: ignore
---@type QfrMapData[]
M.qfr_grep_maps = {
{ nx, "<Plug>(qfr-qgrep-cwd)",    ql..gp.."d", "Quickfix grep CWD"..vc,  function() rg.grep(nil,       " ", { nr = vim.v.count }, cwd_grep(),   {}) end },
{ nx, "<Plug>(qfr-qgrep-cwdX)",   ql..gp.."D", "Quickfix grep CWD"..rx,  function() rg.grep(nil,       " ", { nr = vim.v.count }, cwd_grepX(),  {}) end },
{ nx, "<Plug>(qfr-lgrep-cwd)",   ll..gp.."d", "Loclist grep CWD"..vc,    function() rg.grep(cur_win(), " ", { nr = vim.v.count }, cwd_grep(),   {}) end },
{ nx, "<Plug>(qfr-lgrep-cwdX)",  ll..gp.."D", "Loclist grep CWD"..rx,    function() rg.grep(cur_win(), " ", { nr = vim.v.count }, cwd_grepX(),  {}) end },
{ nx, "<Plug>(qfr-lgrep-help)",  ll..gp.."h", "Loclist grep help"..vc,   function() rg.grep(cur_win(), " ", { nr = vim.v.count }, help_grep(),  { list_item_type = "\1" }) end },
{ nx, "<Plug>(qfr-lgrep-helpX)", ll..gp.."H", "Loclist grep help"..rx,   function() rg.grep(cur_win(), " ", { nr = vim.v.count }, help_grepX(), { list_item_type = "\1" }) end },
}

-- stylua: ignore
---@type QfrMapData[]
M.qfr_grep_buf_maps = {
{ nx, "<Plug>(qfr-qgrep-bufs)",  ql..gp.."u", "Quickfix grep open bufs"..vc, function() rg.grep(nil,       " ", { nr = vim.v.count }, bufs_grep(),  {}) end },
{ nx, "<Plug>(qfr-qgrep-bufsX)", ql..gp.."U", "Quickfix grep bufs"..rx,      function() rg.grep(nil,       " ", { nr = vim.v.count }, bufs_grepX(), {}) end },
{ nx, "<Plug>(qfr-lgrep-cbuf)",  ll..gp.."u", "Loclist grep cur buf"..vc,    function() rg.grep(cur_win(), " ", { nr = vim.v.count }, cbuf_grep(),  {}) end },
{ nx, "<Plug>(qfr-lgrep-cbufX)", ll..gp.."U", "Loclist grep cur buf"..rx,    function() rg.grep(cur_win(), " ", { nr = vim.v.count }, cbuf_grepX(), {}) end },
}

local all_greps = {}
for _, map in ipairs(M.qfr_grep_maps) do
    all_greps[#all_greps + 1] = map
end

for _, map in ipairs(M.qfr_grep_buf_maps) do
    all_greps[#all_greps + 1] = map
end

-- stylua: ignore
---@type QfrCmdData[]
M.qfr_grep_cmds = {
{ "Qgrep", function(cargs) rg.q_grep_cmd(cargs) end, { count = true, nargs = "*", desc = "Grep to the quickfix list" } },
{ "Lgrep", function(cargs) rg.l_grep_cmd(cargs) end, { count = true, nargs = "*", desc = "Grep to the location list" } },
}

M.plug_tbls[#M.plug_tbls + 1] = all_greps
M.uienter_tbls[#M.uienter_tbls + 1] = M.qfr_grep_maps
M.bufevent_tbls[#M.bufevent_tbls + 1] = M.qfr_grep_buf_maps
M.cmd_tbls[#M.cmd_tbls + 1] = M.qfr_grep_cmds
M.doc_tbls[#M.doc_tbls + 1] = { rg_str, all_greps, M.qfr_grep_cmds }

-- stylua: ignore
---@type QfrMapData[]
M.qfr_diag_maps = {
{ nn, "<Plug>(qfr-Qdiags-hint)",       ql..dp.."n", "All diagnostics to quickfix",                   function() rd.diags_to_list({ getopts = { severity = nil } }, new_qflist()) end },
{ nn, "<Plug>(qfr-Qdiags-info)",       ql..dp.."f", "Diagnostics to quickfix, min info",             function() rd.diags_to_list({ getopts = { severity = { min = 3 } } }, new_qflist()) end },
{ nn, "<Plug>(qfr-Qdiags-warn)",       ql..dp.."w", "Diagnostics to quickfix, min warn",             function() rd.diags_to_list({ getopts = { severity = { min = 2 } } }, new_qflist()) end },
{ nn, "<Plug>(qfr-Qdiags-error)",      ql..dp.."e", "Diagnostics to quickfix, min error",            function() rd.diags_to_list({ getopts = { severity = { min = 1 } } }, new_qflist()) end },
{ nn, "<Plug>(qfr-Qdiags-top)",        ql..dp.."t", "Diagnostics to quickfix, top severity",         function() rd.diags_to_list({ top = true }, new_qflist()) end },

{ nn, "<Plug>(qfr-Qdiags-hint-only)",  ql..dp.."N", "Diagnostics to quickfix, only hints",           function() rd.diags_to_list({ getopts = { severity = 4 } }, new_qflist()) end },
{ nn, "<Plug>(qfr-Qdiags-info-only)",  ql..dp.."F", "Diagnostics to quickfix, only info",            function() rd.diags_to_list({ getopts = { severity = 3 } }, new_qflist()) end },
{ nn, "<Plug>(qfr-Qdiags-warn-only)",  ql..dp.."W", "Diagnostics to quickfix, only warnings",        function() rd.diags_to_list({ getopts = { severity = 2 } }, new_qflist()) end },
{ nn, "<Plug>(qfr-Qdiags-error-only)", ql..dp.."E", "Diagnostics to quickfix, only errors",          function() rd.diags_to_list({ getopts = { severity = 1 } }, new_qflist()) end },

{ nn, "<Plug>(qfr-Ldiags-hint)",       ll..dp.."n", "All cur buf diagnostics to loclist",            function() rd.diags_to_list({ getopts = { severity = nil } }, new_loclist()) end },
{ nn, "<Plug>(qfr-Ldiags-info)",       ll..dp.."f", "Cur buf diagnostics to loclist, min info",      function() rd.diags_to_list({ getopts = { severity = { min = 3 } } }, new_loclist()) end },
{ nn, "<Plug>(qfr-Ldiags-warn)",       ll..dp.."w", "Cur buf diagnostics to loclist, min warn",      function() rd.diags_to_list({ getopts = { severity = { min = 2 } } }, new_loclist()) end },
{ nn, "<Plug>(qfr-Ldiags-error)",      ll..dp.."e", "Cur buf diagnostics to loclist, min error",     function() rd.diags_to_list({ getopts = { severity = { min = 1 } } }, new_loclist()) end },
{ nn, "<Plug>(qfr-Ldiags-top)",        ll..dp.."t", "Cur buf diagnostics to loclist, top severity",  function() rd.diags_to_list({ top = true }, new_loclist()) end },

{ nn, "<Plug>(qfr-Ldiags-hint-only)",  ll..dp.."N", "Cur buf diagnostics to loclist, only hints",    function() rd.diags_to_list({ getopts = { severity = 4 } }, new_loclist()) end },
{ nn, "<Plug>(qfr-Ldiags-info-only)",  ll..dp.."F", "Cur buf diagnostics to loclist, only info",     function() rd.diags_to_list({ getopts = { severity = 3 } }, new_loclist()) end },
{ nn, "<Plug>(qfr-Ldiags-warn-only)",  ll..dp.."W", "Cur buf diagnostics to loclist, only warnings", function() rd.diags_to_list({ getopts = { severity = 2 } }, new_loclist()) end },
{ nn, "<Plug>(qfr-Ldiags-error-only)", ll..dp.."E", "Cur buf diagnostics to loclist, only errors",   function() rd.diags_to_list({ getopts = { severity = 1 } }, new_loclist()) end },
}

-- stylua: ignore
---@type QfrCmdData[]
M.qfr_diag_cmds = {
{ "Qdiag", function(cargs) rd.q_diag_cmd(cargs) end, { bang = true, count = 0, nargs = "*", desc = "Send diags to the Quickfix list" } },
{ "Ldiag", function(cargs) rd.l_diag_cmd(cargs) end, { bang = true, count = 0, nargs = "*", desc = "Send buf diags to the Location list" } },
}

M.plug_tbls[#M.plug_tbls + 1] = M.qfr_diag_maps
M.bufevent_tbls[#M.bufevent_tbls + 1] = M.qfr_diag_maps
M.cmd_tbls[#M.cmd_tbls + 1] = M.qfr_diag_cmds
M.doc_tbls[#M.doc_tbls + 1] = { rd_str, M.qfr_diag_maps, M.qfr_diag_cmds }

-- MAYBE: Add filters by diagnostic severity. But not sure if this is faster than simply using a
-- a diagnostic cmd/map. And more default maps = more startup time

-- stylua: ignore
---@type QfrMapData[]
M.qfr_filter_maps = {
{ nx, "<Plug>(qfr-qfilter-cfilter)",   ql..kp.."l", "Qfilter keep cfilter"..vc,   function() rf.filter("cfilter", true, vimcase, replace_qflist()) end },
{ nx, "<Plug>(qfr-qfilter!-cfilter)",  ql..rp.."l", "Qfilter remove cfilter"..vc, function() rf.filter("cfilter", false, vimcase, replace_qflist()) end },
{ nx, "<Plug>(qfr-qfilter-cfilterX)",  ql..kp.."L", "Qfilter keep cfilter"..rx,   function() rf.filter("cfilter", true, regex, replace_qflist()) end },
{ nx, "<Plug>(qfr-qfilter!-cfilterX)", ql..rp.."L", "Qfilter remove cfilter"..rx, function() rf.filter("cfilter", false, regex, replace_qflist()) end },

{ nx, "<Plug>(qfr-lfilter-cfilter)",   ll..kp.."l", "Lfilter keep cfilter"..vc,   function() rf.filter("cfilter", true, vimcase, replace_loclist()) end },
{ nx, "<Plug>(qfr-lfilter!-cfilter)",  ll..rp.."l", "Lfilter remove cfilter"..vc, function() rf.filter("cfilter", false, vimcase, replace_loclist()) end },
{ nx, "<Plug>(qfr-lfilter-cfilterX)",  ll..kp.."L", "Lfilter keep cfilter"..rx,   function() rf.filter("cfilter", true, regex, replace_loclist()) end },
{ nx, "<Plug>(qfr-lfilter!-cfilterX)", ll..rp.."L", "Lfilter remove cfilter"..rx, function() rf.filter("cfilter", false, regex, replace_loclist()) end },

{ nx, "<Plug>(qfr-qfilter-fname)",     ql..kp.."f", "Qfilter keep fname"..vc,     function() rf.filter("fname", true, vimcase, replace_qflist()) end },
{ nx, "<Plug>(qfr-qfilter!-fname)",    ql..rp.."f", "Qfilter remove fname"..vc,   function() rf.filter("fname", false, vimcase, replace_qflist()) end },
{ nx, "<Plug>(qfr-qfilter-fnameX)",    ql..kp.."F", "Qfilter keep fname"..rx,     function() rf.filter("fname", true, regex, replace_qflist()) end },
{ nx, "<Plug>(qfr-qfilter!-fnameX)",   ql..rp.."F", "Qfilter remove fname"..rx,   function() rf.filter("fname", false, regex, replace_qflist()) end },

{ nx, "<Plug>(qfr-lfilter-fname)",     ll..kp.."f", "Lfilter keep fname"..vc,     function() rf.filter("fname", true, vimcase, replace_loclist()) end },
{ nx, "<Plug>(qfr-lfilter!-fname)",    ll..rp.."f", "Lfilter remove fname"..vc,   function() rf.filter("fname", false, vimcase, replace_loclist()) end },
{ nx, "<Plug>(qfr-lfilter-fnameX)",    ll..kp.."F", "Lfilter keep fname"..rx,     function() rf.filter("fname", true, regex, replace_loclist()) end },
{ nx, "<Plug>(qfr-lfilter!-fnameX)",   ll..rp.."F", "Lfilter remove fname"..rx,   function() rf.filter("fname", false, regex, replace_loclist()) end },

{ nx, "<Plug>(qfr-qfilter-text)",      ql..kp.."e", "Qfilter keep text"..vc,      function() rf.filter("text", true, vimcase, replace_qflist()) end },
{ nx, "<Plug>(qfr-qfilter!-text)",     ql..rp.."e", "Qfilter remove text"..vc,    function() rf.filter("text", false, vimcase, replace_qflist()) end },
{ nx, "<Plug>(qfr-qfilter-textX)",     ql..kp.."E", "Qfilter keep text"..rx,      function() rf.filter("text", true, regex, replace_qflist()) end },
{ nx, "<Plug>(qfr-qfilter!-textX)",    ql..rp.."E", "Qfilter remove text"..rx,    function() rf.filter("text", false, regex, replace_qflist()) end },

{ nx, "<Plug>(qfr-lfilter-text)",      ll..kp.."e", "Lfilter keep text"..vc,      function() rf.filter("text", true, vimcase, replace_loclist()) end },
{ nx, "<Plug>(qfr-lfilter!-text)",     ll..rp.."e", "Lfilter remove text"..vc,    function() rf.filter("text", false, vimcase, replace_loclist()) end },
{ nx, "<Plug>(qfr-lfilter-textX)",     ll..kp.."E", "Lfilter keep text"..rx,      function() rf.filter("text", true, regex, replace_loclist()) end },
{ nx, "<Plug>(qfr-lfilter!-textX)",    ll..rp.."E", "Lfilter remove text"..rx,    function() rf.filter("text", false, regex, replace_loclist()) end },

{ nx, "<Plug>(qfr-qfilter-lnum)",      ql..kp.."n", "Qfilter keep lnum"..vc,      function() rf.filter("lnum", true, vimcase, replace_qflist()) end },
{ nx, "<Plug>(qfr-qfilter!-lnum)",     ql..rp.."n", "Qfilter remove lnum"..vc,    function() rf.filter("lnum", false, vimcase, replace_qflist()) end },
{ nx, "<Plug>(qfr-qfilter-lnumX)",     ql..kp.."N", "Qfilter keep lnum"..rx,      function() rf.filter("lnum", true, regex, replace_qflist()) end },
{ nx, "<Plug>(qfr-qfilter!-lnumX)",    ql..rp.."N", "Qfilter remove lnum"..rx,    function() rf.filter("lnum", false, regex, replace_qflist()) end },

{ nx, "<Plug>(qfr-lfilter-lnum)",      ll..kp.."n", "Lfilter keep lnum"..vc,      function() rf.filter("lnum", true, vimcase, replace_loclist()) end },
{ nx, "<Plug>(qfr-lfilter!-lnum)",     ll..rp.."n", "Lfilter remove lnum"..vc,    function() rf.filter("lnum", false, vimcase, replace_loclist()) end },
{ nx, "<Plug>(qfr-lfilter-lnumX)",     ll..kp.."N", "Lfilter keep lnum"..rx,      function() rf.filter("lnum", true, regex, replace_loclist()) end },
{ nx, "<Plug>(qfr-lfilter!-lnumX)",    ll..rp.."N", "Lfilter remove lnum"..rx,    function() rf.filter("lnum", false, regex, replace_loclist()) end },
}

-- stylua: ignore
---@type QfrCmdData[]
M.qfr_filter_cmds = {
{ "Qfilter", function(cargs) rf.q_filter_cmd(cargs) end, { bang = true, count = true, nargs = "*", desc = "Filter quickfix items" } },
{ "Lfilter", function(cargs) rf.l_filter_cmd(cargs) end, { bang = true, count = true, nargs = "*", desc = "Filter location list items" } },
}

M.plug_tbls[#M.plug_tbls + 1] = M.qfr_filter_maps
M.bufevent_tbls[#M.bufevent_tbls + 1] = M.qfr_filter_maps
M.cmd_tbls[#M.cmd_tbls + 1] = M.qfr_filter_cmds
M.doc_tbls[#M.doc_tbls + 1] = { rf_str, M.qfr_filter_maps, M.qfr_filter_cmds }

-- stylua: ignore
---@type QfrMapData[]
M.qfr_sort_maps = {
{ nn, "<Plug>(qfr-qsort-fname-asc)",       ql..sp.."f",     "Sort quickfix by fname asc",            function() rs.sort(rs.sorts.fname.asc,       nil,       "r", vim.v.count) end },
{ nn, "<Plug>(qfr-qsort-fname-desc)",      ql..sp.."F",     "Sort quickfix by fname desc",           function() rs.sort(rs.sorts.fname.desc,      nil,       "r", vim.v.count) end },
{ nn, "<Plug>(qfr-qsort-fname-diag-asc)",  ql..sp..dp.."f", "Sort quickfix by fname_diag asc",       function() rs.sort(rs.sorts.fname_diag.asc,  nil,       "r", vim.v.count) end },
{ nn, "<Plug>(qfr-qsort-fname-diag-desc)", ql..sp..dp.."F", "Sort quickfix by fname_diag desc",      function() rs.sort(rs.sorts.fname_diag.desc, nil,       "r", vim.v.count) end },
{ nn, "<Plug>(qfr-qsort-severity-asc)",    ql..sp..dp.."s", "Sort quickfix by severity asc",         function() rs.sort(rs.sorts.severity.asc,    nil,       "r", vim.v.count) end },
{ nn, "<Plug>(qfr-qsort-severity-desc)",   ql..sp..dp.."S", "Sort quickfix by severity desc",        function() rs.sort(rs.sorts.severity.desc,   nil,       "r", vim.v.count) end },
{ nn, "<Plug>(qfr-qsort-text-asc)",        ql..sp.."e",     "Sort quickfix by text asc",             function() rs.sort(rs.sorts.text.asc,        nil,       "r", vim.v.count) end },
{ nn, "<Plug>(qfr-qsort-text-desc)",       ql..sp.."E",     "Sort quickfix by text desc",            function() rs.sort(rs.sorts.text.desc,       nil,       "r", vim.v.count) end },

{ nn, "<Plug>(qfr-lsort-fname-asc)",       ll..sp.."f",     "Sort location list by fname asc",       function() rs.sort(rs.sorts.fname.asc,       cur_win(), "r", vim.v.count) end },
{ nn, "<Plug>(qfr-lsort-fname-desc)",      ll..sp.."F",     "Sort location list by fname desc",      function() rs.sort(rs.sorts.fname.desc,      cur_win(), "r", vim.v.count) end },
{ nn, "<Plug>(qfr-lsort-fname-diag-asc)",  ll..sp..dp.."f", "Sort location list by fname_diag asc",  function() rs.sort(rs.sorts.fname_diag.asc,  cur_win(), "r", vim.v.count) end },
{ nn, "<Plug>(qfr-lsort-fname-diag-desc)", ll..sp..dp.."F", "Sort location list by fname_diag desc", function() rs.sort(rs.sorts.fname_diag.desc, cur_win(), "r", vim.v.count) end },
{ nn, "<Plug>(qfr-lsort-severity-asc)",    ll..sp..dp.."s", "Sort location list by severity asc",    function() rs.sort(rs.sorts.severity.asc,    cur_win(), "r", vim.v.count) end },
{ nn, "<Plug>(qfr-lsort-severity-desc)",   ll..sp..dp.."S", "Sort location list by severity desc",   function() rs.sort(rs.sorts.severity.desc,   cur_win(), "r", vim.v.count) end },
{ nn, "<Plug>(qfr-lsort-text-asc)",        ll..sp.."e",     "Sort location list by text asc",        function() rs.sort(rs.sorts.text.asc,        cur_win(), "r", vim.v.count) end },
{ nn, "<Plug>(qfr-lsort-text-desc)",       ll..sp.."E",     "Sort location list by text desc",       function() rs.sort(rs.sorts.text.desc,       cur_win(), "r", vim.v.count) end },
}

-- stylua: ignore
M.qfr_sort_cmds = {
{ "Qsort", function(cargs) rs.q_sort(cargs) end, { bang = true, count = 0, nargs = 1, desc = "Sort quickfix items" } },
{ "Lsort", function(cargs) rs.l_sort(cargs) end, { bang = true, count = 0, nargs = 1, desc = "Sort location list items" } },
}

M.plug_tbls[#M.plug_tbls + 1] = M.qfr_sort_maps
M.bufevent_tbls[#M.bufevent_tbls + 1] = M.qfr_sort_maps
M.cmd_tbls[#M.cmd_tbls + 1] = M.qfr_sort_cmds
M.doc_tbls[#M.doc_tbls + 1] = { rs_str, M.qfr_sort_maps, M.qfr_sort_cmds }

-- NOTE: This table needs to be separate or else the plug mapping pass will map "<nop>", which
-- causes multiple problems

-- stylua: ignore
---@type QfrMapData[]
M.default_masks = {
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

return M
