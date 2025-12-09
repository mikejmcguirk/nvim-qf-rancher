local api = vim.api
local fn = vim.fn

require("plugin.qf-rancher") -- Load globals
local ra = require("qf-rancher.stack")

---@return integer|nil
local function find_qf_win_in_cur_tabpage()
    for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
        local wintype = vim.fn.win_gettype(win)
        if wintype == "quickfix" then
            return win
        end
    end

    return nil
end

describe("qf-rancher.stack", function()
    local function create_temp_buf(name)
        local buf = api.nvim_create_buf(false, true)
        api.nvim_buf_set_name(buf, name)
        return buf
    end

    local function get_test_entries()
        local buf1 = create_temp_buf("stack_file1.lua")
        local buf2 = create_temp_buf("stack_file2.txt")
        local buf3 = create_temp_buf("stack_error_file.md")
        return {
            { bufnr = buf1, lnum = 10, text = "Error in code", type = "E" },
            { bufnr = buf2, lnum = 20, text = "warning message", type = "W" },
            { bufnr = buf3, lnum = 30, text = "info", type = "I" },
            { bufnr = 0, lnum = 40, text = "no file associated", type = "" },
        }
    end

    after_each(function()
        api.nvim_cmd({ cmd = "cclose" }, {})
        api.nvim_cmd({ cmd = "lclose" }, {})
        fn.setqflist({}, "f")
        fn.setloclist(1000, {}, "f")
    end)

    describe("_get_history", function()
        it("does not change stack size if list nr does not change", function()
            local entries = get_test_entries()
            fn.setqflist(entries, "r")
            api.nvim_cmd({ cmd = "copen" }, {})

            local list_win = find_qf_win_in_cur_tabpage() ---@type integer|nil
            assert.is_not_nil(list_win)
            ---@diagnostic disable-next-line: param-type-mismatch
            local list_win_height = api.nvim_win_get_height(list_win) ---@type integer

            ra._get_history(nil, 0, { open_list = true, silent = true })
            ---@diagnostic disable-next-line: param-type-mismatch
            local height_after = api.nvim_win_get_height(list_win) ---@type integer
            assert.are.equal(list_win_height, height_after)
        end)
    end)
end)
