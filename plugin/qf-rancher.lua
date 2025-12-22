_G.QF_RANCHER_E42 = "E42: No Errors"
_G.QF_RANCHER_MAX_HEIGHT = 10
_G.QF_RANCHER_NOLISTWIN = "Not inside a list window"
_G.QF_RANCHER_NO_LL = "Window has no location list"

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

local api = vim.api
local fn = vim.fn

-- MID: Set to the most useful defaults for the most users. The README should then document
-- default behaviors that deviate from the Neovim defaults

---@mod nvim-qf-rancher.txt Error list husbandry
---@brief [[
---Nvim Quickfix Rancher provides a stable of tools for taming the quickfix
---and location lists:
---- Auto opening, closing, and resizing of list windows at logical points
---  and across tabpages
---- Wrapping and convenience functions for list and stack navigation
---- Autocommands to stop automatic copying of location lists to new windows,
---  as well as putting location lists without a home window out to pasture
---- Preview window for list items
---- Built-in functions for lassoing diagnostics of all severities, including
---  highest only
---- Grep functions built on rg as a default, with grep available
---  as a backup
---- Filter and sort functions
---- Capabilities are extensible and available from the cmd line
---@brief ]]

-- MID: It would be better to have a more formal Neovim versioning system
-- NOTE: Support is capped at v0.11 due to diagnostic severity filtering

---@mod qf-rancher-installation Installation
---@tag qfr-installation
---@brief [[
---Neovim 0.11+ is supported
---
---Lazy.nvim:
--->
---    "mikejmcguirk/nvim-qf-rancher",
---    lazy = false,
---    init = function()
---        -- set g variables here
---    end,
---<
---vim.pack spec (v0.12+):
--->
---    { src = "https://github.com/mikejmcguirk/nvim-qf-rancher" },
---<
---Verify installation and settings with ":checkhealth qf-rancher"
---@brief ]]

---@mod qf-rancher-config Configuration
---@tag qfr-config

---@brief [[
---
---Qfr is configured using vim.g variables. For lazy.nvim users, make sure to
---set these in the "init" section of your plugin spec
---
---The current settings can be verified with "checkhealth qf-rancher"
---@brief ]]

-- TODO: Deprecate debug assertions. Locals should not have validations
-- MID: Create specific validator functions for these where appropriate

-- stylua: ignore
_G._QFR_G_VAR_MAP = {
---
---(Default true) Qfr commands will auto-center opened buffers
---@alias qfr_auto_center boolean
qfr_auto_center = { { "boolean" }, true },
---
---(Default true) Always open the list when its contents are changed
---@alias qfr_auto_open_changes boolean
qfr_auto_open_changes = { { "boolean" }, true },
---
---(Default true) When the list is opened, its contents changed, or the
---stack number changed, re-size it to match the amount of entries. Max
---automatic height is 10
---@alias qfr_auto_list_height boolean
qfr_auto_list_height = { { "boolean" }, true },
---
---(Default true) Automatically close the list if the entire stack is cleared
---@alias qfr_close_on_stack_clear boolean
qfr_close_on_stack_clear = { { "boolean" }, true },
---
---(Default true) On startup, create autocmds to manage the following:
---- Prevent split windows from inheriting the original window's location
---  list
---- When a non-list window is closed, automatically close and clear its
---  associated location lists
---These autocmds are contained in the augroup "qfr-loclist-group"
---@alias qfr_create_loclist_autocmds boolean
qfr_create_loclist_autocmds = { { "boolean" }, true },
---
---(Default true) Temporarily set splitkeep to topline when
---the list is open, closed, or resized. This option is ignored if
---splitkeep is already set for screen or topline
---@alias qfr_always_keep_topline boolean
qfr_always_keep_topline = { { "boolean" }, true },
---@brief [[
---Qf Rancher provides a qf.lua after/ftplugin file to customize list behavior
---Customize which |qfr-ftplugin| features to use with the options below
---@brief ]]
---
---(Default true) Disable obtrusive defaults
---@alias qfr_ftplugin_demap boolean
qfr_ftplugin_demap = { { "boolean" }, true },
---
---(Default true) Set ack.vim style ftplugin list keymaps
---@alias qfr_ftplugin_keymap boolean
qfr_ftplugin_keymap = { { "boolean" }, true },
---
---(Default true) Set list-specific options
---@alias qfr_ftplugin_set_opts boolean
qfr_ftplugin_set_opts = { { "boolean" }, true },
---
---(Default "rg") Set the grepprg used for Rancher's grep functions
---"rg" and "grep" are available
---@alias qfr_grepprg string
qfr_grepprg = { { "string" }, "rg" },
---@brief [[
---Control the preview window (|qfr-preview|) with the options below
---@brief ]]
---
---(Default "single") Set the preview window border. See :h 'winborder' for
---more info
---@alias qfr_preview_border
---| ''
---| 'bold'
---| 'double'
---| 'none'
---| 'rounded'
---| 'shadow'
---| 'single'
---| 'solid'
---| 'An eight element string[] table'
qfr_preview_border = { { "string", "table" }, "single" },
---
---(Default 100) Minimum interval in ms between preview window updates
---The default is 100 to accommodate slower systems/HDs. On a reasonable
---system, it should be possible to go down to 50ms before flicker/stutter
---start to appear. This behavior also depends on the size of the file(s)
---being scrolled through
---@alias qfr_preview_debounce string
qfr_preview_debounce = { { "number" }, 100 },
---
---(Default true) Show title in the preview window
---@alias qfr_preview_show_title string
qfr_preview_show_title = { { "boolean" }, true },
---
---(Default "left") If show_title is true, control where it shows
---@alias qfr_preview_title_pos string "center"|"left"|"right"
qfr_preview_title_pos = { { "string" }, "left" },
---
---(Default 0) Set the winblend of the preview win (see :h winblend)
---@alias qfr_preview_winblend integer
qfr_preview_winblend = { { "number" }, 0 },
---
---(Default true) When running a Qfr cmd to gather new entries, look for
---destination lists to re-use based on title
---@alias qfr_reuse_title boolean
qfr_reuse_title = { { "boolean" }, true },
---
---(Default true) Create Qfr's default commands
---@alias qfr_set_default_cmds boolean
qfr_set_default_cmds = { { "boolean" }, true },
---
---(Default true) Set default keymaps (excluding ftplugin maps)
---NOTE: All <Plug> maps are created at startup regardless of this option's
---value. If this option is true, The Window maps (|qfr-window-controls|) and
---and the grep maps (|qfr-grep-maps|) for CWD and help will be created at
---startup. The others will be deferred until BufNew or BufReadPre
---@alias qfr_set_default_keymaps boolean
qfr_set_default_keymaps = { { "boolean" }, true },
} ---@type table<string, {[1]:string[], [2]: any}>

for k, v in pairs(_QFR_G_VAR_MAP) do
    local cur_g_val = vim.g[k] ---@type any
    if not vim.tbl_contains(v[1], type(cur_g_val)) then
        api.nvim_set_var(k, v[2])
    end
end

if vim.g.qfr_create_loclist_autocmds then
    local qfr_loclist_group = api.nvim_create_augroup("qfr-loclist-group", {})

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
            if not win then
                return
            end

            if not api.nvim_win_is_valid(win) then
                return
            end

            local config = api.nvim_win_get_config(win)
            if config.relative and config.relative ~= "" then
                return
            end

            local qf_id = fn.getloclist(win, { id = 0 }).id ---@type integer
            if qf_id < 1 then
                return
            end

            local buf = api.nvim_win_get_buf(win)
            if api.nvim_get_option_value("buftype", { buf = buf }) == "quickfix" then
                return
            end

            vim.schedule(function()
                local tabpages = api.nvim_list_tabpages()
                local rw = require("qf-rancher.window")
                rw._close_ll_wins({ qf_id = qf_id, tabpages = tabpages })
            end)
        end,
    })
end

---@export nvim-qf-rancher

------------------------
-- Map and Cmd Pieces --
------------------------

-- DOCUMENT: The default mappings use vim.v.count for the listnr. The various functions treat
-- 0 as the current list

local maps = require("qf-rancher.maps")
for _, tbl in ipairs(maps.plug_tbls) do
    for _, map in ipairs(tbl) do
        for _, mode in ipairs(map[1]) do
            api.nvim_set_keymap(mode, map[2], "", {
                callback = map[5],
                desc = map[4],
                noremap = true,
            })
        end
    end
end

if vim.g.qfr_set_default_keymaps then
    for _, tbl in ipairs(maps.uienter_tbls) do
        for _, map in ipairs(tbl) do
            for _, mode in ipairs(map[1]) do
                api.nvim_set_keymap(mode, map[3], map[2], {
                    desc = map[4],
                    noremap = true,
                })
            end
        end
    end

    for _, map in ipairs(maps.default_masks) do
        for _, mode in ipairs(map[1]) do
            api.nvim_set_keymap(mode, map[3], map[2], {
                desc = map[4],
                noremap = true,
            })
        end
    end

    local bufgroup = "qfr-buf-maps"
    api.nvim_create_autocmd({ "BufNew", "BufReadPre" }, {
        group = api.nvim_create_augroup(bufgroup, {}),
        callback = function()
            for _, tbl in ipairs(maps.bufevent_tbls) do
                for _, map in ipairs(tbl) do
                    for _, mode in ipairs(map[1]) do
                        api.nvim_set_keymap(mode, map[3], map[2], {
                            desc = map[4],
                            noremap = true,
                        })
                    end
                end
            end

            api.nvim_del_augroup_by_name(bufgroup)
        end,
    })
end

if vim.g.qfr_set_default_cmds then
    for _, tbl in ipairs(maps.cmd_tbls) do
        for _, cmd in ipairs(tbl) do
            api.nvim_create_user_command(cmd[1], cmd[2], cmd[3])
        end
    end
end

-- TODO: Check all TODO comments and make sure they are not connected to functions or exported
-- definitions. Lua_Ls includes them in hover info
-- TODO: Organize the modules so that the actual exported module tables start where the
-- user-facing functions start, rather than at the locals, and then the underline functions
-- should be after the doc export
-- TODO: General refactoring strategy:
-- NOTE: Anything containing nested echos or bad error reporting needs to be addressed as it's
-- found. This will mean creating temporary duplicate utils. The originals can be cleaned as
-- they are fully obsoleted.
-- - window
-- - preview
-- - grep
-- - diags
-- - filter
-- - system
-- - remove output opts
-- - filetype funcs
-- - types
--   - more thorough renaming
--   - obsolete unneeded ones
-- - recheck for bad utils
-- - maps file

-- MID: Publish Qfitems as diagnostics
-- - How would you then be able to manipulate/delete them once they were out there?
-- MID: Qsystem
-- - Wait for other refactoring
-- - Feels like there should be some way to specify qftf
-- MID: How to make the list more useful with compilers. Possible starting points:
-- - https://github.com/Zeioth/compiler.nvim
-- - https://github.com/ahmedkhalf/project.nvim
-- - https://github.com/stevearc/overseer.nvim
-- - :h :make_makeprg
-- - :h compiler-select
-- MID: Behavior of cmds in visual mode is still a fuzzy question
-- MID: Re-check which mappings should work in visual mode
-- MID: Send marks to list. Bufmarks to location list. Global marks to qflist
-- - https://github.com/chentoast/marks.nvim?tab=readme-ov-file
-- - Or look at how Fzflua or another picker pulls marks
-- - lm (buf marks), qm (all buf marks), qM (all marks, including global marks)
-- https://github.com/arsham/listish.nvim
-- - The functionality to add notes to lists here is cool, and pairs well with diagnostics
-- - You could even have a way of giving them a diagnostic priority
-- https://github.com/neovim/neovim/issues/15950 - Discussion related to qf formatting

-- LOW: If we explore the idea of editing the qf buffer, the best way to do it seems to be to
-- treat "edit mode" as a distinct thing, where it can then be saved and propagate the changes
-- - https://github.com/gabrielpoca/replacer.nvim
-- - https://github.com/stefandtw/quickfix-reflector.vim
-- LOW: It would be cool to have a canned way to take cdo/cfdo and export the results to a
-- scratch buf. But would need to test with something like the c substitute option
-- LOW: Add a callback opt to preview win opening/closing. This would allow users to hook in
-- ts-context or other desired features
-- LOW: scrolling in preview wins
-- LOW: docgen
-- - Cmd documentation could be improved. Unsure how to approach this because the info lives
-- in so many places. Hard to programmatically bring together
-- - Would be really cool if the whole thing were auto-generated. Could then put the actual
-- code execution into a struct of arrays
-- LOW: cwin/lwin
-- - Wait for Window module refactor
-- - Map to qw/lw
-- - Make a plug/default for these
-- - Like copen, count sets height
-- - Oddity: Does not focus the win if already open. Add for rancher?
-- - Are the benefits of cwin better addressed by making toggle smarter? Problem there: If the
-- window doesn't open, it might be perceived as it not working
-- LOW: cexpr/cgetexpr
-- - Very general/difficult/don't understand use case
-- LOW: cbuffer/cgetbuffer/caddbuffer
-- LOW: cfile/cgetfile/caddfile
-- LOW: cabove/cbelow
-- - unimpaired + diagnostic navigation address this IMO

-- MAYBE: Add ftplugin files that use rancher, such as make commands piped to the system module

-- DOCUMENT: vim.regex currently uses case sensitive default behavior
-- DOCUMENT: How default counts are treated in cmds and maps
-- DOCUMENT: rg handles true multi-line greps. For programs that don't, or is used as a fallback
-- DOCUMENT: What types of regex are used where. Grep cmds have their own regex. Regex filters use
-- vim regex

-- PR: Make the fields in vim.api.keyset.cmd.mods optional. Verify it is possible to use an
-- empty table
-- PR: Add "uint" to vim.validate
-- PR: Fix wintype annotations
-- PR: It should be possible to output vimgrep to a list so it can be used by internal scripting
-- PR: It would be better if cmd marks produced rows and columns

-- FUTURE: If it becomes possible to add metatables to g:vars, could use to put validations on
-- g:var sets

-- NOGO: clist
-- NOGO: Persistent state must be minimal
-- NOGO: Additional context within the list itself. Any info like that should be covered by the
-- preview win or additional floating wins or cmds
-- NOGO: Anything Fuzzy Finder related. FzfLua does this
-- NOGO: Any sort of annotation scheme. Should be able to use filtering
-- NOGO: Dynamic behavior. Trouble has to create a whole runtime to manage this
-- NOGO: "Modernizing" the feel of the qflist. The old school feel is part of the charm
