local ra = Qfr_Defer_Require("qf-rancher.stack") ---@type QfrStack
local rt = Qfr_Defer_Require("qf-rancher.tools") ---@type QfrTools
local ru = Qfr_Defer_Require("qf-rancher.util") ---@type QfrUtil
local ry = Qfr_Defer_Require("qf-rancher.types") ---@type QfrTypes

local api = vim.api

---@mod System Send system cmd results to the list
---@tag qf-rancher-system
---@tag qfr-system
---@brief [[
---
---@brief ]]

---@class QfrSystem
local System = {}

local default_timeout = 2000 ---@type integer

---@param obj vim.SystemCompleted
---@param output_opts QfrOutputOpts
local function handle_output(obj, output_opts)
    if obj.code ~= 0 then
        ---@type string
        local err = (obj.stderr and #obj.stderr > 0) and "Error: " .. obj.stderr or ""
        local msg = (obj.code and "Exit code: " .. obj.code or "") .. " " .. err ---@type string
        vim.api.nvim_echo({ { msg, "ErrorMsg" } }, true, { err = true })
        return
    end

    local src_win = output_opts.src_win ---@type integer
    if src_win and not ru._valid_win_for_loclist(src_win) then return end

    local lines = vim.split(obj.stdout or "", "\n", { trimempty = true }) ---@type string[]
    if #lines == 0 then return end
    local lines_dict = vim.fn.getqflist({ lines = lines }) ---@type { items: table[] }
    if #lines_dict.items < 1 then
        api.nvim_echo({ { "No items", "" } }, false, {})
        return
    end

    table.sort(lines_dict.items, output_opts.sort_func)
    if output_opts.list_item_type then
        for _, item in pairs(lines_dict.items) do
            item.type = output_opts.list_item_type
        end
    end

    ---@type QfrWhat
    local what_set = vim.tbl_deep_extend("force", output_opts.what, { items = lines_dict.items })
    local dest_nr = rt._set_list(src_win, output_opts.action, what_set) ---@type integer
    if ru._get_g_var("qfr_auto_open_changes") then
        ra._get_history(src_win, dest_nr, {
            open_list = true,
            default = "cur_list",
            silent = true,
        })
    end
end

---Run a system command and sends the results to a list
---@param system_opts QfrSystemOpts See |qfr-system-opts|
---@param output_opts QfrOutputOpts See |qfr-output-opts|
---@return nil
function System.system_do(system_opts, output_opts)
    ry._validate_system_opts(system_opts)
    ry._validate_output_opts(output_opts)

    ---@type vim.SystemOpts
    local vim_system_opts = { text = true, timeout = system_opts.timeout or default_timeout }
    if system_opts.sync then
        local obj = vim.system(system_opts.cmd_parts, vim_system_opts)
            :wait(system_opts.timeout or default_timeout) ---@type vim.SystemCompleted
        handle_output(obj, output_opts)
    else
        vim.system(system_opts.cmd_parts, vim_system_opts, function(obj)
            vim.schedule(function()
                handle_output(obj, output_opts)
            end)
        end)
    end
end

return System
---@export System
