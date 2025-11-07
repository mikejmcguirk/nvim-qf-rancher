local api = vim.api
local fn = vim.fn

require("plugin.qf-rancher") -- Load globals
local rt = require("qf-rancher.filter")

describe("qf-rancher.filter", function()
    local function create_temp_buf(name)
        local buf = api.nvim_create_buf(false, true)
        api.nvim_buf_set_name(buf, name)
        return buf
    end

    local function get_test_entries()
        local buf1 = create_temp_buf("filter_file1.lua")
        local buf2 = create_temp_buf("filter_file2.txt")
        local buf3 = create_temp_buf("filter_error_file.md")
        return {
            { bufnr = buf1, lnum = 10, text = "Error in code", type = "E" },
            { bufnr = buf2, lnum = 20, text = "warning message", type = "W" },
            { bufnr = buf3, lnum = 30, text = "info", type = "I" },
            { bufnr = 0, lnum = 40, text = "no file associated", type = "" },
        }
    end

    before_each(function()
        vim.g.qfr_auto_open_changes = 0
    end)

    after_each(function()
        api.nvim_cmd({ cmd = "cclose" }, {})
        api.nvim_cmd({ cmd = "lclose" }, {})
        fn.setqflist({}, "f")
        fn.setloclist(0, {}, "f")
    end)

    describe("cfilter (emulation)", function()
        it("keeps matches in text or filename, sensitive, quickfix", function()
            local entries = get_test_entries()
            fn.setqflist(entries, "r")

            local input_opts = { input_type = "sensitive", pattern = "Error" }
            local output_opts = { action = "u", what = { nr = 0 } }
            rt.filter("cfilter", true, input_opts, output_opts)

            local result = fn.getqflist()
            assert.are.equal(1, #result)
            assert.are.equal("Error in code", result[1].text)
        end)
    end)
end)
