local api = vim.api
local fn = vim.fn

require("plugin.qf-rancher") -- Load globals
local w = require("qf-rancher.window")

---@return integer|nil
local function find_qf_win_in_cur_tabpage()
    local tabpage = api.nvim_get_current_tabpage() ---@type integer
    local tabpage_wins = api.nvim_tabpage_list_wins(tabpage) ---@type integer[]
    for _, win in ipairs(tabpage_wins) do
        local wintype = vim.fn.win_gettype(win)
        if wintype == "quickfix" then return win end
    end

    return nil
end

---@return integer|nil
local function find_ll_win_in_cur_tabpage()
    local tabpage = api.nvim_get_current_tabpage() ---@type integer
    local tabpage_wins = api.nvim_tabpage_list_wins(tabpage) ---@type integer[]
    for _, win in ipairs(tabpage_wins) do
        local wintype = vim.fn.win_gettype(win)
        if wintype == "loclist" then return win end
    end

    return nil
end

describe("open_qflist", function()
    it("focuses the list on open", function()
        api.nvim_set_var("qfr_auto_list_height", true)
        w.open_qflist({})
        local wintype = vim.fn.win_gettype(0)

        assert.are.same("quickfix", wintype)
    end)

    it("automatically sizes the window", function()
        local height = api.nvim_win_get_height(0) ---@type integer

        assert.are.same(1, height)
    end)

    it("resizes the list if already open", function()
        w.open_qflist({ height = 10 })
        local height = api.nvim_win_get_height(0) ---@type integer

        assert.are.same(10, height)
    end)

    it("keeps the original window if specified", function()
        api.nvim_cmd({ cmd = "cclose" }, {})
        local start_win = api.nvim_get_current_win() ---@type integer
        w.open_qflist({ keep_win = true })
        local fin_win = api.nvim_get_current_win() ---@type integer

        assert.are.same(start_win, fin_win)
    end)

    it("focuses the list if it's already open", function()
        local list_win = find_qf_win_in_cur_tabpage() ---@type integer|nil

        assert.is_not_nil(list_win)

        w.open_qflist({})
        local fin_win = api.nvim_get_current_win() ---@type integer|nil

        assert.are.same(list_win, fin_win)
    end)
end)

describe("close_qflist", function()
    it("closes the quickfix list", function()
        local list_win = find_qf_win_in_cur_tabpage() ---@type integer|nil

        assert.is_not_nil(list_win)

        w.close_qflist()
        local list_win_after = find_qf_win_in_cur_tabpage() ---@type integer|nil

        assert.Nil(list_win_after)
    end)
end)

describe("toggle_qflist", function()
    it("opens the quickfix list if it's closed", function()
        local list_win = find_qf_win_in_cur_tabpage() ---@type integer|nil

        assert.Nil(list_win)

        w.toggle_qflist({})

        local list_win_after = find_qf_win_in_cur_tabpage() ---@type integer|nil

        assert.is_not_nil(list_win_after)
    end)

    it("closes the quickfix list if it's open", function()
        local list_win = find_qf_win_in_cur_tabpage() ---@type integer|nil

        assert.is_not_nil(list_win)

        w.toggle_qflist({})
        local list_win_after = find_qf_win_in_cur_tabpage() ---@type integer|nil

        assert.Nil(list_win_after)
    end)
end)

describe("open_loclist", function()
    local src_win = 0

    it("does nothing if no location list", function()
        src_win = api.nvim_get_current_win() ---@type integer
        local qf_id = fn.getloclist(src_win, { id = 0 }).id ---@type integer

        assert.Equal(0, qf_id)

        local opened = w.open_loclist(src_win, {}) ---@type boolean
        assert.False(opened)
    end)

    it("focuses the list on open", function()
        fn.setloclist(0, { { text = "test item" } })
        api.nvim_set_var("qfr_auto_list_height", true)
        w.open_loclist(src_win, {})
        local wintype = vim.fn.win_gettype(0)

        assert.are.same(wintype, "loclist")
    end)

    it("automatically sizes the window", function()
        local height = api.nvim_win_get_height(0) ---@type integer

        assert.are.same(height, 1)
    end)

    it("resizes the list if already open", function()
        w.open_loclist(src_win, { height = 10 })
        local height = api.nvim_win_get_height(0) ---@type integer

        assert.are.same(height, 10)
    end)

    it("keeps the original window if specified", function()
        api.nvim_cmd({ cmd = "lclose" }, {})
        local start_win = api.nvim_get_current_win() ---@type integer
        w.open_loclist(src_win, { keep_win = true })
        local fin_win = api.nvim_get_current_win() ---@type integer

        assert.are.same(start_win, fin_win)
    end)

    it("focuses the list if it's already open", function()
        local list_win = find_ll_win_in_cur_tabpage() ---@type integer|nil

        assert.is_not_nil(list_win)

        w.open_loclist(src_win, {})
        local fin_win = api.nvim_get_current_win() ---@type integer|nil

        assert.are.same(list_win, fin_win)
    end)
end)

describe("close_loclist", function()
    local src_win = 0 ---@type integer

    it("closes the location list", function()
        src_win = api.nvim_get_current_win()
        local list_win = find_ll_win_in_cur_tabpage() ---@type integer|nil

        assert.is_not_nil(list_win)

        w.close_loclist(src_win)
        list_win = find_ll_win_in_cur_tabpage() ---@type integer|nil

        assert.Nil(list_win)
    end)
end)

describe("toggle_loclist", function()
    local src_win = 0 ---@type integer

    it("opens the location list if it's closed", function()
        src_win = api.nvim_get_current_win()
        local list_win = find_ll_win_in_cur_tabpage() ---@type integer|nil

        assert.Nil(list_win)

        w.toggle_loclist(src_win, {})
        local list_win_after = find_ll_win_in_cur_tabpage() ---@type integer|nil

        assert.is_not_nil(list_win_after)
    end)

    it("closes the quickfix list if it's open", function()
        local list_win = find_ll_win_in_cur_tabpage() ---@type integer|nil

        assert.is_not_nil(list_win)

        w.toggle_loclist(src_win, {})
        local list_win_after = find_ll_win_in_cur_tabpage() ---@type integer|nil

        assert.Nil(list_win_after)
    end)
end)
