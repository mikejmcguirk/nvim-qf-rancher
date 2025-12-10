local ls = Qfr_Defer_Require("qf-rancher.lib.sort") ---@type QfrLibSort
local ra = Qfr_Defer_Require("qf-rancher.stack") ---@type QfrStack
local rt = Qfr_Defer_Require("qf-rancher.tools") ---@type QfrTools
local ru = Qfr_Defer_Require("qf-rancher.util") ---@type QfrUtil
local rw = Qfr_Defer_Require("qf-rancher.window") ---@type QfrWins
local ry = Qfr_Defer_Require("qf-rancher.types") ---@type QfrTypes

local api = vim.api

---@mod System Send system cmd results to the list
---@tag qf-rancher-system
---@tag qfr-system
---@brief [[
---
---@brief ]]

--- @class QfrSystem
local System = {}

local default_timeout = 2000 ---@type integer

-- MID: Find the common composable pieces here with the ftplugin file and merge them together
---@param tabpage integer
---@return integer[]
local function get_numbered_wins_ordered(tabpage)
    local wins = api.nvim_tabpage_list_wins(tabpage) ---@type integer[]
    local configs = {} ---@type vim.api.keyset.win_config_ret[]
    for _, win in ipairs(wins) do
        configs[win] = api.nvim_win_get_config(win)
    end

    local numbered_wins = vim.tbl_filter(function(win)
        return configs[win].focusable and not configs[win].hide
    end, wins)

    local wins_pos = {} ---@type { [1]:integer, [2]:integer, [3]:integer }[]
    for _, win in ipairs(numbered_wins) do
        local pos = api.nvim_win_get_position(win) ---@type { [1]:integer, [2]:integer }
        local zindex = configs[win].zindex or 0 ---@type integer
        wins_pos[win] = { pos[1], pos[2], zindex }
    end

    table.sort(numbered_wins, function(a, b)
        if wins_pos[a][3] < wins_pos[b][3] then
            return true
        elseif wins_pos[a][3] > wins_pos[b][3] then
            return false
        elseif wins_pos[a][2] < wins_pos[b][2] then
            return true
        elseif wins_pos[a][2] > wins_pos[b][2] then
            return false
        else
            return wins_pos[a][1] < wins_pos[b][1]
        end
    end)

    return numbered_wins
end

-- MID: Probably gets merged with the code in the ft funcs
---@return integer
local function create_scratch_buf()
    local buf = api.nvim_create_buf(false, true)
    api.nvim_set_option_value("buflisted", false, { buf = buf })
    api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
    api.nvim_set_option_value("buftype", "nofile", { buf = buf })
    api.nvim_set_option_value("modifiable", false, { buf = buf })
    api.nvim_set_option_value("swapfile", false, { buf = buf })
    api.nvim_set_option_value("undofile", false, { buf = buf })

    return buf
end

---@param src_win integer
---@return integer
local function get_lhelp_win(src_win)
    local src_buf = api.nvim_win_get_buf(src_win) ---@type integer
    local src_bt = api.nvim_get_option_value("bt", { buf = src_buf }) ---@type string
    if src_bt == "help" then
        return src_win
    end

    local wins = get_numbered_wins_ordered(0) ---@type integer[]
    for _, win in ipairs(wins) do
        if win ~= src_win then
            local buf = api.nvim_win_get_buf(win) ---@type integer
            local bt = api.nvim_get_option_value("bt", { buf = buf }) ---@type string
            if bt == "help" then
                return win
            end
        end
    end

    local scratch_buf = create_scratch_buf() ---@type integer
    -- MID: Not sure why I wouldn't just do this in the ft-funcs
    -- MAYBE: I have this on split below because it's how the default works, but, will change if
    -- I don't like it
    return api.nvim_open_win(scratch_buf, false, { win = wins[1], split = "below" })
end

-- LOW: This function, and any callers, should be able to detect if the incoming command will
-- force a split if the current window cannot handle the location list output. The only use case I
-- know of for this though is lhelpgrep, and I don't want to make a major architectural change for
-- such a small thing. Would need to see more use cases.

---@param obj vim.SystemCompleted
---@param src_win integer|nil
---@param action QfrAction
---@param what QfrWhat
---@param system_opts QfrSystemOpts
local function set_output_to_list(obj, src_win, action, what, system_opts)
    if not (obj.code and obj.code == 0) then
        local code_str = obj.code and "Exit code: " .. obj.code or "" ---@type string
        local is_err = obj.stderr and #obj.stderr > 0 ---@type boolean?
        local err = is_err and "Error: " .. obj.stderr or "" ---@type string
        local msg = code_str .. " " .. err ---@type string

        api.nvim_echo({ { msg, "ErrorMsg" } }, true, { err = true })
        return
    end

    if src_win and not ru._is_valid_loclist_win(src_win) then
        return
    end

    local stdout = obj.stdout or "" ---@type string
    local lines = vim.split(stdout, "\n", { trimempty = true }) ---@type string[]
    if #lines == 0 then
        api.nvim_echo({ { "No output" } }, false, {})
        return
    end

    local lines_dict = vim.fn.getqflist({ lines = lines }) ---@type { items: vim.quickfix.entry[] }
    if #lines_dict.items < 1 then
        api.nvim_echo({ { "No items" } }, false, {})
        return
    end

    system_opts.sort_func = system_opts.sort_func or ls.sort_fname_asc
    table.sort(lines_dict.items, system_opts.sort_func)
    if system_opts.list_item_type then
        for _, item in ipairs(lines_dict.items) do
            item.type = system_opts.list_item_type
        end
    end

    local orig_src_win = src_win ---@type integer|nil
    if src_win and system_opts.list_item_type == "\1" then
        src_win = get_lhelp_win(src_win)
        if type(what.nr) == "number" then
            local max_nr = rt._get_list(src_win, { nr = "$" }).nr ---@type integer
            ---@diagnostic disable-next-line: param-type-mismatch
            what.nr = math.min(what.nr, max_nr)
        end
    end

    ---@type QfrWhat
    local what_set = vim.tbl_deep_extend("force", what, { items = lines_dict.items })
    local dest_nr = rt._set_list(src_win, action, what_set) ---@type integer
    if dest_nr < 0 then
        api.nvim_echo({ { "Unable to set list", "ErrorMsg" } }, true, {})
        return
    end

    if src_win and orig_src_win ~= src_win then
        -- MID: It should not be necessary to do this until the buf is opened, however, if we do
        -- not do this, the window context is not correct for the history and lopen functions
        -- below. lopen in particular cannot be win-called because the auto-focus logic fails
        -- (though I suppose that could be fixed/papered-over), and I'm not sure what effects if
        -- any win_call would have on history. Broader thing to put a pin on as everything in here
        -- is re-factored is - The various functions need to be able to take in and be responsive
        -- to context, rather than going along with implicit context
        api.nvim_set_current_win(src_win)
    end

    if vim.g.qfr_auto_open_changes then
        local cur_nr = rt._get_list(src_win, { nr = 0 }).nr ---@type integer
        local nr_after = ra._goto_history(src_win, dest_nr, { silent = true }) ---@type integer
        if cur_nr ~= nr_after and vim.g.qfr_auto_list_height then
            ra._resize_after_change(src_win)
        end

        rw._open_list(src_win, {})
    end

    if src_win and orig_src_win ~= src_win then
        local first_item = what_set.items[1] ---@type vim.quickfix.entry
        local dest_bt = system_opts.list_item_type == "\1" and "help" or "" ---@type string
        ru._open_item(first_item, src_win, { buftype = dest_bt, clearjumps = true, focus = true })
    end
end

---Run a system command and send the results to a list
---@param cmd_parts string[] Command to execute
---@param src_win integer|nil Location list window nr, or nil to set to
---the quickfix list
---@param action QfrAction See |setqflist-action|
---@param what QfrWhat See |setqflist-what|
---@param system_opts QfrSystemOpts See |qfr-system-opts|
---@return nil
function System.system_do(cmd_parts, src_win, action, what, system_opts)
    ry._validate_list(cmd_parts, { type = "string" })
    ry._validate_win(src_win, true)
    ry._validate_action(action)
    ry._validate_what(what)
    ry._validate_system_opts(system_opts)

    local timeout = system_opts.timeout or default_timeout ---@type integer
    local vim_system_opts = { text = true, timeout = timeout } ---@type vim.SystemOpts
    if system_opts.sync then
        ---@type vim.SystemCompleted
        local obj = vim.system(cmd_parts, vim_system_opts):wait(timeout)
        set_output_to_list(obj, src_win, action, what, system_opts)
    else
        vim.system(cmd_parts, vim_system_opts, function(obj)
            vim.schedule(function()
                set_output_to_list(obj, src_win, action, what, system_opts)
            end)
        end)
    end
end

return System
---@export System
