local eo = Qfr_Defer_Require("qf-rancher.window") --- @type QfrWins

local api = vim.api
local bufmap = api.nvim_buf_set_keymap
local fn = vim.fn

local function bufmap_plug(mode, lhs, rhs, desc)
    vim.api.nvim_buf_set_keymap(0, mode, lhs, rhs, { noremap = true, nowait = true, desc = desc })
end

---@mod Ftplugin List buffer specific features
---@tag qf-rancher-ftplugin
---@tag qfr-ftplugin
---@brief [[
---
---@brief ]]

-- NOTE: To avoid requires, don't use util g_var function

---@brief [[
---If g:qfr_ftplugin_set_opts is true, the following will be set:
---
---- buflisted = false
---- colorcolumn = ""
---- list = false
---- spell = false
---@brief ]]
if vim.g.qfr_ftplugin_set_opts then
    api.nvim_set_option_value("buflisted", false, { buf = 0 })
    api.nvim_set_option_value("cc", "", { scope = "local" })
    api.nvim_set_option_value("list", false, { scope = "local" })
    api.nvim_set_option_value("spell", false, { scope = "local" })
end

---@brief [[
---If g:qfr_ftplugin_demap is true, disable the following defaults:
---
---- <C-w>s (split)
---- <C-w>v (vsplit)
---- <C-i> / <C-o> (jumplist navigation)
---@brief ]]
if vim.g.qfr_ftplugin_demap then
    bufmap(0, "n", "<C-w>v", "<nop>", { noremap = true, nowait = true })
    bufmap(0, "n", "<C-w><C-v>", "<nop>", { noremap = true, nowait = true })
    bufmap(0, "n", "<C-w>s", "<nop>", { noremap = true, nowait = true })
    bufmap(0, "n", "<C-w><C-s>", "<nop>", { noremap = true, nowait = true })

    bufmap(0, "n", "<C-i>", "<nop>", { noremap = true, nowait = true })
    bufmap(0, "n", "<C-o>", "<nop>", { noremap = true, nowait = true })
end

-- MID: Doc wise, it would be less awkward if the "<" and ">" maps were included in the ftplugin
-- maps table. But I'm not sure how you pass the list context through a plug map

---@brief [[
---The |qf-rancher-ftplugin-keymaps| will be set if g:qfr_ftplugin_keymap
---is true.
---
---Additionally, the "older" and "newer" functions will be mapped to "<" and ">"
---Like the standard keymaps, they take a wrapping count
---
---NOTE: The [count] for the ftplugin specific maps specifies which window
---number to open the entry to. If no count is provided, Qfr will emulate
---Neovim's default behavior. For Quickfix windows, this includes respecting
---"useopen", "usetab", and "uselast" switchbuf behavior (Location list
---windows use "useopen" only). Help entries will attempt to find a help
---window If a valid window cannot be found, a new split will always be
---created above the list
---@brief ]]
if not vim.g.qfr_ftplugin_keymap then return end

local in_loclist = fn.win_gettype(0) == "loclist" --- @type boolean

local qp = "q" ---@type string
local ql = "<leader>" .. qp ---@type string

local lp = "l" ---@type string
local ll = "<leader>" .. lp ---@type string

local ip = in_loclist and lp or qp
local il = in_loclist and ll or ql

for _, lhs in ipairs({ il .. ip, "q" }) do
    vim.keymap.set("n", lhs, function()
        eo._close_list(in_loclist and api.nvim_get_current_win() or nil)
    end, { buffer = true, nowait = true, desc = "Close the list" })
end

bufmap_plug("n", "dd", "<Plug>(qfr-list-del-one)", "Delete the current list line")
bufmap_plug("x", "d", "<Plug>(qfr-list-visual-del)", "Delete a visual line list selection")

bufmap_plug("n", "p", "<Plug>(qfr-list-toggle-preview)", "Toggle the list preview win")
bufmap_plug("n", "P", "<Plug>(qfr-list-update-preview-pos)", "Update the preview win position")

if in_loclist then
    bufmap_plug("n", "<", "<Plug>(qfr-ll-older)", "Go to an older location list")
    bufmap_plug("n", ">", "<Plug>(qfr-ll-newer)", "Go to a newer location list")
else
    bufmap_plug("n", "<", "<Plug>(qfr-qf-older)", "Go to an older qflist")
    bufmap_plug("n", ">", "<Plug>(qfr-qf-newer)", "Go to a newer qflist")
end

bufmap_plug("n", "{", "<Plug>(qfr-list-prev)", "Go to the previous list entry, keep list focus")
bufmap_plug("n", "}", "<Plug>(qfr-list-next)", "Go to the next list entry, keep list focus")

local d_focuswin_desc = "Open a list item" --- @type string
local d_focuslist_desc = "Open a list item, keep list focus" --- @type string
local s_focuswin_desc = "Open a list item in a split" --- @type string
local s_focuslist_desc = "Open a list item in a split, keep list focus" --- @type string
local vs_focuswin_desc = "Open a list item in a vsplit" --- @type string
local vs_focuslist_desc = "Open a list item in a vsplit, keep list focus" --- @type string
local t_focuswin_desc = "Open a list item in a new tab" --- @type string
local t_focuslist_desc = "Open a list item in a new tab, keep list focus" --- @type string

bufmap_plug("n", "o", "<Plug>(qfr-list-open-direct-focuswin)", d_focuswin_desc)
bufmap_plug("n", "<C-o>", "<Plug>(qfr-list-open-direct-focuslist)", d_focuslist_desc)
bufmap_plug("n", "s", "<Plug>(qfr-list-open-split-focuswin)", s_focuswin_desc)
bufmap_plug("n", "<C-s>", "<Plug>(qfr-list-open-split-focuslist)", s_focuslist_desc)
bufmap_plug("n", "v", "<Plug>(qfr-list-open-vsplit-focuswin)", vs_focuswin_desc)
bufmap_plug("n", "<C-v>", "<Plug>(qfr-list-open-vsplit-focuslist)", vs_focuslist_desc)
bufmap_plug("n", "x", "<Plug>(qfr-list-open-tabnew-focuswin)", t_focuswin_desc)
bufmap_plug("n", "<C-x>", "<Plug>(qfr-list-open-tabnew-focuslist)", t_focuslist_desc)

---@export Ftplugin

-- TODO: Tests

-- LOW: Add an undo_ftplugin script
