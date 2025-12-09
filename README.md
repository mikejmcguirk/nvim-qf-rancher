## Nvim Quickfix Rancher

#### NOTE:
This plugin is still experimental. APIs and defaults are subject to change without notice. Issues and PRs welcome.

Nvim Quickfix Rancher provides a stable of tools for taming the quickfix
and location lists:
- Auto opening, closing, and resizing of list windows at logical points and across tabpages
- Wrapping and convenience functions for list and stack navigation
- Autocommands to stop automatic copying of location lists to new windows, as well as putting location lists without a home window out to pasture
- Preview window for list items
- Built-in functions for lassoing diagnostics of all severities, including highest only
- Grep functions built on rg as a default, with grep available as a backup
- Filter and sort functions
- Capabilities are extensible and available from the cmd line

## Installation

#### lazy.nvim:

```lua
  "mikejmcguirk/nvim-qf-rancher",
  lazy = false,
  init = function()
      -- set g variables here
  end,
```

#### vim.pack (nightly):

```lua
    { src = "https://github.com/mikejmcguirk/nvim-qf-rancher" },
```

## Configuration

Key options are listed below. See the help file for more:

| Option | Description |
|--------|-------------|
| qfr_auto_list_height | (Default true) Resize the list based on its contents. Max automatic height is 10 |
| qfr_create_loclist_autocmds | (Default true) Automatically close orphan location lists and prevent them from duplicating |
| qfr_save_views | (Default true) Save views of other windows in the same tab when the list is open, closed, or resized. This option is ignored if splitkeep is set for screen or topline |
| qfr_ftplugin_demap | (Default true) Disable obtrusive defaults |
| qfr_ftplugin_keymap | (Default true) Set ack.vim style ftplugin list keymaps |
| qfr_ftplugin_set_opts | (Default true) Set list-specific options |
| qfr_grepprg | (Default "rg") Set the grepprg used for Rancher's grep functions "rg" and "grep" are available |
| qfr_preview_border | (Default "single") Set the preview window border |
| qfr_preview_show_title | (Default true) Show title in the preview window |
| qfr_qfsplit | (Default "botright") Set the split the quickfix list opens to |
| qfr_set_default_cmds | (Default true) Create Qfr's default commands |
| qfr_set_default_keymaps | (Default true) Set default keymaps (excluding ftplugin maps) |

## Keymaps

qf-rancher provides \<Plug> maps and defaults for accessing its capabilities. They are listed in the help file by section.

## Commands

Like the keymaps, default commands are also provided. They are listed in the help file by section.

## API

qf-rancher's functionality can be accessed directly using its API. See the help file for more info.
