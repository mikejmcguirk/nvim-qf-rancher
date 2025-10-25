_G.QFR_MAX_HEIGHT = 10

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

-- TODO: Go through all the defer requires in the project and rename them
local rw = Qfr_Defer_Require("qf-rancher.window") ---@type QfrWins

local api = vim.api
local fn = vim.fn

-- TODO: Add a credits/inspiration section
-- LOW: The g variable docs could also be automatically generated

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
---- Built-in functions for lassoing diagnostics by all severities, including
---  highest only
---- Filter and sort functions
---- A variey of grep functions built on rg as a default, with grep available
---  as a backup
---- Capabilities are extensible and available from the cmd line
---@brief ]]


---@mod qf-rancher-installation Installation
---@tag qfr-installation
---TODO:

---@mod qf-rancher-config Configuration
---@tag qfr-config

---@brief [[
---
---Qfr is configured using vim.g variables. For lazy.nvim users, make sure to
---set thse in the "init" section of your plugin spec
---@brief ]]

-- MID: Create specific validator functions for these where appropriate
-- MID: For deferred keymaps, could add an option to control the event(s) or
-- if there should be an event at all

-- stylua: ignore
_G._QFR_G_VAR_MAP = {
---
---(Default true) Qfr commands will auto-center opened buffers
---@alias qfr_auto_center_result string
qfr_auto_center_result = { { "boolean" }, false },
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
---(Default false) Enables extra type checking and logical assertions. This
---can affect performance, as individual list items will have extra
---validation
---@alias qfr_debug_assertions boolean
qfr_debug_assertions = { { "boolean" }, false },
---
---(Default true) Save views of other windows in the same tab when
---the list is open, closed, or resized. This option is ignored if
---splitkeep is set for screen or topline
---@alias qfr_save_views boolean
qfr_save_views = { { "boolean" }, true },
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
---Control the preview window with the options below
---TODO: link to preview win section
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
---(Default "botright") Set the split the quickfix list opens to
---@alias qfr_qfsplit
---| 'aboveleft'
---| 'belowright'
---| 'topleft'
---| 'botright'
qfr_qfsplit = { { "string" }, "botright" },
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
    if not vim.tbl_contains(v[1], type(cur_g_val)) then vim.api.nvim_set_var(k, v[2]) end
end

if vim.g.qfr_create_loclist_autocmds then
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
                rw._close_loclists_by_qf_id(qf_id, { all_tabpages = true })
            end)
        end,
    })
end

-- TODO: This is not a good place for this. Should be after ftplugin, but unsure how to swing
-- that in the docgen

---@tag qf-rancher-api-types
---@tag qfr-api-types
---@brief [[
---
---@brief ]]
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
---@field pattern? string The search pattern for the function

---@tag qf-rancher-system-opts
---@tag qfr-system-opts
---@class QfrSystemOpts
---@field sync? boolean Run the operation syncrhonously
---@field cmd_parts? string[] String parts to build the command from
---@field timeout? integer How long to wait. Default 2000 (sync and async)

---@tag qf-rancher-output-opts
---@tag qfr-output-opts
---@class QfrOutputOpts
---@field list_item_type? string Usually blank. "\1" for help buffers
---@field sort_func? function A function from the sort module
---@field src_win integer|nil Loclist win context. Quickfix if nil
---@field action QfrAction See |setqflist-action|
---@field what QfrWhat See |setqflist-what|

---@export nvim-qf-rancher

-- NOTE: In order for the defer require to work, all function calls must be inside of
-- anonymous functions. If you pass, for example, eo.closeqflist as a function reference, eo
-- needs to be evaluated at command creation

------------------------
-- Map and Cmd Pieces --
------------------------

-- LOW: The maps are put into their own file so that the docgen script can access them
-- This is sub-optimal because it necessitates a require during startup
-- The long-term solution is for the keymaps code itself to be autogenerated with the rest of the
-- /plugin file. This would have the additional benefit of being able to put the keymap defs into
-- a struct of arrays organization, which would save a small amount of time, especially if more
-- defaults are added

-- TODO: I think these table listings can be created in the maps file itself, but want to
-- do a few more in case a gotcha comes up

local maps = require("qf-rancher.maps")
local tbls_for_plugs = {
    maps.qfr_buf_maps,
    maps.qfr_win_maps,
    maps.qfr_nav_maps,
    maps.qfr_stack_maps,
    maps.qfr_ftplugin_maps,
    maps.qfr_grep_maps,
}

-- Create plug maps
for _, tbl in ipairs(tbls_for_plugs) do
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
    local tbls_for_uienter = {
        maps.qfr_win_maps,
        maps.qfr_grep_maps,
    }

    for _, tbl in ipairs(tbls_for_uienter) do
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

    local tbls_for_bufevent = {
        maps.qfr_nav_maps,
        maps.qfr_stack_maps,
        maps.qfr_grep_buf_maps,
        maps.qfr_buf_maps,
    }

    -- Defer creation of maps that can wait for a buffer to be opened
    local bufgroup = "qfr-buf-maps"
    api.nvim_create_autocmd({ "BufNew", "BufReadPre" }, {
        group = api.nvim_create_augroup(bufgroup, {}),
        callback = function()
            for _, tbl in ipairs(tbls_for_bufevent) do
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
    local cmd_tbls = {
        maps.cmds,
        maps.qfr_win_cmds,
        maps.qfr_nav_cmds,
        maps.qfr_stack_cmds,
        maps.qfr_grep_cmds,
    }

    for _, tbl in ipairs(cmd_tbls) do
        for _, cmd in ipairs(tbl) do
            api.nvim_create_user_command(cmd[1], cmd[2], cmd[3])
        end
    end
end

-- TODO: Move to vimcats: https://github.com/mrcjkb/vimcats
-- TODO: https://luajit.org/extensions.html
-- I know some of these functions are in here. They either need to be removed or this needs to be
-- advertised as a LuaJIT exclusive plugin

-- DOCUMENT: For cmd mappings, document what cmd opts they expect to be available. Can do this
-- in docgen with a k, v loop

-- TEST: Start nvim and check package.loaded to verify no extra modules have required

-- MID: Alias wintype annotations?
-- MID: Publish Qf items as diagnostics. Would make other ideas more useful
-- MID: Applies to close and cwin - If closing the window and the stack is empty, schedule a
-- stack clear?
-- MID: Remaining Commands to handle:
-- - cwin/lwin: count is height. Get #items in the current list. If there are items, open/focus/
--   resize the list. If no items, close the list or do nothing
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
-- LOW: The in-process LSP idea is interesting for how to work with the qflist. You could make
-- code actions based on LSP entries. For example, rather than having to run a filter cmd, you
-- could use gra then chose to remove all entries from that buffer. Or you could put sorts behind
-- code actions. It would be useful to see them all in a menu. The idea of having hover windows
-- in the qflist is also interesting, to show more info about the entry, but I'm not sure you
-- need the lsp for that

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
