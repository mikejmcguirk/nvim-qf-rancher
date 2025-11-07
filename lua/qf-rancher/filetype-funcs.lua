local ro = Qfr_Defer_Require("qf-rancher.window") ---@type QfrWins
local rt = Qfr_Defer_Require("qf-rancher.tools") ---@type QfrTools
local ru = Qfr_Defer_Require("qf-rancher.util") ---@type QfrUtil
local ry = Qfr_Defer_Require("qf-rancher.types") ---@type QfrTypes

local api = vim.api
local fn = vim.fn

--- @class QfRancherFiletypeFuncs
local M = {}

-- LIST DELETION --

---@return nil
function M._del_one_list_item()
    local list_win = api.nvim_get_current_win() ---@type integer
    local wintype = fn.win_gettype(list_win)
    if not (wintype == "quickfix" or wintype == "loclist") then
        api.nvim_echo({ { "Not inside a list window", "" } }, false, {})
        return
    end

    local src_win = wintype == "loclist" and list_win or nil ---@type integer|nil
    local list = rt._get_list(src_win, { nr = 0, all = true }) ---@type table
    if #list.items < 1 then return end

    local row, col = unpack(api.nvim_win_get_cursor(list_win)) ---@type integer, integer
    table.remove(list.items, row)
    rt._set_list(src_win, "u", { nr = 0, items = list.items, idx = list.idx })

    ru._protected_set_cursor(0, { row, col })
end

function M._visual_del()
    local list_win = api.nvim_get_current_win() ---@type integer
    local wintype = fn.win_gettype(list_win)
    if not (wintype == "quickfix" or wintype == "loclist") then
        api.nvim_echo({ { "Not inside a list window", "" } }, false, {})
        return
    end

    local mode = string.sub(api.nvim_get_mode().mode, 1, 1) ---@type string
    if mode ~= "V" then
        api.nvim_echo({ { "Must be in visual line mode", "" } }, false, {})
        return
    end

    local src_win = wintype == "loclist" and list_win or nil ---@type integer|nil
    local list = rt._get_list(src_win, { nr = 0, all = true }) ---@type table
    if #list.items < 1 then return end
    local col = vim.api.nvim_win_get_cursor(list_win)[2] ---@type integer

    local cur = fn.getpos(".") ---@type [integer, integer, integer, integer]
    local fin = fn.getpos("v") ---@type [integer, integer, integer, integer]
    local selection = api.nvim_get_option_value("selection", { scope = "global" }) ---@type string
    local exclusive = selection == "exclusive" ---@type boolean
    --- @type [ [integer, integer, integer, integer], [integer, integer, integer, integer] ][]
    local region = fn.getregionpos(cur, fin, { type = mode, exclusive = exclusive })

    ---@type Range4
    local vrange_4 =
        { region[1][1][2], region[1][1][3], region[#region][2][2], region[#region][2][3] }
    api.nvim_cmd({ cmd = "normal", args = { "\27" }, bang = true }, {})
    for i = vrange_4[3], vrange_4[1], -1 do
        table.remove(list.items, i)
    end

    rt._set_list(src_win, "u", {
        nr = 0,
        items = list.items,
        idx = list.idx,
    })

    ru._protected_set_cursor(0, { vrange_4[1], col })
end

-- LIST OPEN HELPERS --

---@param list_win integer
---@param buf_win integer
---@param finish QfrFinishMethod
---@return nil
local function handle_orphan(list_win, buf_win, finish)
    ry._validate_list_win(list_win)
    ry._validate_win(buf_win)
    ry._validate_finish_method(finish)

    local buf_win_qf_id = fn.getloclist(buf_win, { id = 0 }).id ---@type integer
    if buf_win_qf_id > 0 then return end

    local stack = rt._get_stack(list_win) ---@type table[]
    ro._close_win_save_views(list_win)
    rt._set_stack(buf_win, stack)

    api.nvim_set_current_win(buf_win)
    ro.open_loclist(buf_win, { keep_win = finish == "focusWin" })

    if ru._get_g_var("qfr_debug_assertions") then
        local cur_win = api.nvim_get_current_win() ---@type integer
        if finish == "focusWin" then assert(cur_win == buf_win) end
        if finish == "focusList" then assert(fn.win_gettype(cur_win) == "loclist") end
    end
end

---@param win integer
---@param dest_buftype string
---@param buf? integer
---@return boolean
--- NOTE: Because this runs in loops, skip validation
local function is_valid_dest_win(win, dest_buftype, buf)
    local wintype = fn.win_gettype(win)
    local win_buf = api.nvim_win_get_buf(win) ---@type integer
    local win_buftype = api.nvim_get_option_value("buftype", { buf = win_buf }) ---@type string
    local has_buf = (function()
        if not buf then
            return true
        else
            return win_buf == buf
        end
    end)() ---@type boolean

    -- NOTE: Prefer being too restrictive about allowed wins. Handle edge cases as they come up
    local valid_buf = has_buf and win_buftype == dest_buftype ---@type boolean
    return wintype == "" and valid_buf
end

---@param tabnr integer
---@param dest_buftype string
---@param opts QfrFindWinInTabOpts
---@return integer|nil
local function find_win_in_tab(tabnr, dest_buftype, opts)
    if ru._get_g_var("qfr_debug_assertions") then
        ry._validate_uint(tabnr)
        vim.validate("dest_buftype", dest_buftype, "string")
        ry._validate_find_win_in_tab_opts(opts)
    end

    local max_winnr = fn.tabpagewinnr(tabnr, "$") ---@type integer
    local skip_winnr = opts.skip_winnr ---@type integer|nil
    for i = 1, max_winnr do
        if i ~= skip_winnr then
            -- Convert now because win_gettype does not support tab context
            local win = fn.win_getid(i, tabnr)
            if is_valid_dest_win(win, dest_buftype, opts.bufnr) then return win end
        end
    end

    return nil
end

---@param list_tabnr integer
---@param dest_buftype string
---@param buf integer|nil
---@return integer|nil
local function find_win_in_tabs(list_tabnr, dest_buftype, buf)
    if ru._get_g_var("qfr_debug_assertions") then
        ry._validate_uint(list_tabnr)
        vim.validate("dest_buftype", dest_buftype, "string")
        ry._validate_uint(buf, true)
    end

    local test_tabnr = list_tabnr ---@type integer
    local max_tabnr = #api.nvim_list_tabpages() ---@type integer
    for _ = 1, 100 do
        test_tabnr = test_tabnr + 1
        if test_tabnr > max_tabnr then test_tabnr = 1 end
        if test_tabnr == list_tabnr then break end

        ---@type integer|nil
        local tabpage_win = find_win_in_tab(test_tabnr, dest_buftype, { bufnr = buf })
        if tabpage_win then return tabpage_win end
    end

    return nil
end

---@param tabnr integer
---@param dest_buftype string
---@param opts QfrFindWinInTabOpts
---@return integer|nil
local function find_win_in_tab_reverse(tabnr, dest_buftype, opts)
    if ru._get_g_var("qfr_debug_assertions") then
        ry._validate_uint(tabnr)
        vim.validate("dest_buftype", dest_buftype, "string")
        ry._validate_find_win_in_tab_opts(opts)
    end

    local max_winnr = fn.tabpagewinnr(tabnr, "$") ---@type integer
    local fin_winnr = opts.fin_winnr or 1 ---@type integer
    local test_winnr = fin_winnr ---@type integer
    local skip_winnr = opts.skip_winnr ---@type integer|nil

    for _ = 1, 100 do
        test_winnr = test_winnr - 1
        if test_winnr <= 0 then test_winnr = max_winnr end
        if test_winnr ~= skip_winnr then
            -- Convert now because win_gettype does not support tab context
            local win = fn.win_getid(test_winnr, tabnr) ---@type integer
            if is_valid_dest_win(win, dest_buftype, opts.bufnr) then return win end
        end

        if test_winnr == fin_winnr then break end
    end

    return nil
end

-- TODO: If you open a help buffer into a non-buftype/wintype win, should just work. I think
-- you just set dest_buftype to zero, but unsure if Window type checks are needed too

---@param list_tabnr integer
---@param dest_buftype string
---@return integer|nil
local function get_count_win(list_tabnr, dest_buftype)
    if ru._get_g_var("qfr_debug_assertions") then
        ry._validate_uint(list_tabnr)
        vim.validate("dest_buftype", dest_buftype, "string")
    end

    local adj_count = math.min(vim.v.count, fn.tabpagewinnr(list_tabnr, "$")) ---@type integer
    local target_win = fn.win_getid(adj_count, list_tabnr) ---@type integer

    if is_valid_dest_win(target_win, dest_buftype) then return target_win end
    api.nvim_echo({ { "Winnr " .. adj_count .. " is not valid", "" } }, false, {})
    return nil
end

---@param list_win integer
---@param dest_buftype string
---@param buf integer
---@param is_loclist boolean
---@param loclist_origin? integer
---@param split QfrSplitType
---@return boolean, integer|nil
local function get_dest_win(list_win, dest_buftype, buf, is_loclist, loclist_origin, split)
    if ru._get_g_var("qfr_debug_assertions", true) then
        ry._validate_list_win(list_win)
        vim.validate("dest_buftype", dest_buftype, "string")
        ry._validate_buf(buf)
        vim.validate("is_loclist", is_loclist, "boolean")
        ry._validate_win(loclist_origin, true)
        ry._validate_split(split)
    end

    if split == "tabnew" then return true, nil end
    local list_tabpage = api.nvim_win_get_tabpage(list_win) ---@type integer
    local list_tabnr = api.nvim_tabpage_get_number(list_tabpage) ---@type integer
    if vim.v.count > 0 then
        local count_win = get_count_win(list_tabnr, dest_buftype)
        if count_win then return true, count_win end
        return false, nil
    end

    local list_winnr = api.nvim_win_get_number(list_win) ---@type integer
    if dest_buftype == "help" then
        ---@type integer|nil
        local win = find_win_in_tab(list_tabnr, dest_buftype, { skip_winnr = list_winnr })
        if win or split == "none" then return true, win end
    end

    local adj_dest_buftype = dest_buftype == "help" and "" or dest_buftype ---@type string
    if is_loclist and loclist_origin then return true, loclist_origin end
    local switchbuf = not is_loclist
            and api.nvim_get_option_value("switchbuf", { scope = "global" })
        or "" ---@type string

    if dest_buftype ~= "help" and (is_loclist or string.find(switchbuf, "useopen", 1, true)) then
        ---@type QfrFindWinInTabOpts
        local find_opts = { bufnr = buf, skip_winnr = list_winnr }
        ---@type integer|nil
        local tabpage_buf_win = find_win_in_tab(list_tabnr, adj_dest_buftype, find_opts)
        if tabpage_buf_win then return true, tabpage_buf_win end
    end

    local usetab = string.find(switchbuf, "usetab", 1, true)
    if dest_buftype ~= "help" and ((not is_loclist) and usetab) then
        local usetab_win = find_win_in_tabs(list_tabnr, adj_dest_buftype, buf) ---@type integer|nil
        if usetab_win then return true, usetab_win end
    end

    if (not is_loclist) and string.find(switchbuf, "uselast", 1, true) then
        local alt_winnr = fn.tabpagewinnr(list_tabnr, "#") ---@type integer
        local alt_win = fn.win_getid(alt_winnr, list_tabnr) ---@type integer
        if is_valid_dest_win(alt_win, adj_dest_buftype, buf) then return true, alt_win end
    end

    ---@type QfrFindWinInTabOpts
    local find_opts = { fin_winnr = list_winnr, skip_winnr = list_winnr }
    return true, find_win_in_tab_reverse(list_tabnr, adj_dest_buftype, find_opts)
end

-- =====================
-- == LIST OPEN FUNCS ==
-- =====================

---@param list_win integer
---@param dest_win integer|nil
---@param is_orphan boolean
---@return boolean
local function should_resize_list_win(list_win, dest_win, is_orphan)
    if ru._get_g_var("qfr_debug_assertions") then
        ry._validate_list_win(list_win)
        ry._validate_win(dest_win, true)
        vim.validate("is_orphan", is_orphan, "boolean")
    end

    if not ru._get_g_var("qfr_auto_list_height") then return false end
    if dest_win or is_orphan then return false end
    local win_tabpage = vim.api.nvim_win_get_tabpage(list_win) ---@type integer
    return #vim.api.nvim_tabpage_list_wins(win_tabpage) == 1
end

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

-- If splitting from the list_win, a scratch buffer needs to be created or else the list buffer
-- will be used. The destination buf cannot be used because it affects the buf open logic
-- Rather than sorting through when to use the origin win's buf, just always make a scratch buf

---@param dest_win integer|nil
---@param split QfrSplitType
---@param buf integer
---@param list_win integer
local function get_buf_win(dest_win, split, buf, list_win)
    if ru._get_g_var("qfr_debug_assertions") then
        ry._validate_win(dest_win, true)
        ry._validate_list_win(list_win)
        ry._validate_buf(buf)
        ry._validate_split(split)
    end

    if dest_win and split == "none" then return dest_win end
    local scratch = create_scratch_buf() ---@type integer
    if not dest_win then
        return api.nvim_open_win(scratch, false, { win = list_win, split = "above" })
    end

    local split_dir = (function()
        if split == "split" then
            ---@type boolean
            local splitbelow = api.nvim_get_option_value("splitbelow", { scope = "global" })
            return splitbelow and "below" or "above" ---@type string
        else
            ---@type boolean
            local splitright = api.nvim_get_option_value("splitright", { scope = "global" })
            return splitright and "right" or "left" ---@type string
        end
    end)() ---@type string

    return api.nvim_open_win(scratch, false, { win = dest_win, split = split_dir })
end

---@param finish QfrFinishMethod
---@return nil
local function tabnew_open(list_win, item, finish, is_orphan, pattern)
    ry._validate_list_win(list_win)
    ry._validate_list_item(item)
    ry._validate_finish_method(finish)
    vim.validate("is_orphan", is_orphan, "boolean")
    vim.validate("pattern", pattern, "string")

    local tab_count = fn.tabpagenr("$") ---@type integer
    ---@type integer
    local range = vim.v.count > 0 and math.min(vim.v.count, tab_count) or tab_count
    api.nvim_cmd({ cmd = "tabnew", range = { range } }, {})

    local buf_win = api.nvim_get_current_win() ---@type integer
    local dest_buftype = item.type == "\1" and "help" or "" ---@type string
    ru._open_item_to_win(item, { buftype = dest_buftype, win = buf_win })
    if finish == "focusList" and not is_orphan then vim.api.nvim_set_current_win(list_win) end

    if is_orphan then handle_orphan(list_win, buf_win, finish) end

    vim.api.nvim_exec_autocmds("QuickFixCmdPost", { pattern = pattern })
end

-- LOW: Should this logic be generalized to other modules?

---@param split QfrSplitType
---@param finish QfrFinishMethod
---@param idx_func QfrIdxFunc
---@return nil
local function open_item_from_list(split, finish, idx_func)
    ry._validate_split(split)
    ry._validate_finish_method(finish)
    vim.validate("idx_func", idx_func, "callable")

    local list_win = api.nvim_get_current_win() ---@type integer
    if not ru._is_in_list_win(list_win) then
        api.nvim_echo({ { "Not inside a list window", "" } }, false, {})
        return
    end

    local is_loclist = fn.win_gettype(list_win) == "loclist" ---@type boolean
    local src_win = is_loclist and list_win or nil ---@type integer|nil
    local loclist_origin = (is_loclist and src_win)
            and ru._find_loclist_origin(src_win, { all_tabpages = true })
        or nil ---@type integer|nil

    local is_orphan = is_loclist and not loclist_origin ---@type boolean
    local item, idx = idx_func(src_win) ---@type vim.quickfix.entry|nil, integer|nil
    if not (item and item.bufnr and item.type and idx) then return end

    local dest_buftype = item.type == "\1" and "help" or "" ---@type string
    ---@type boolean, integer|nil
    local ok, dest_win =
        get_dest_win(list_win, dest_buftype, item.bufnr, is_loclist, loclist_origin, split)
    if not ok then return end

    local pattern = src_win and "ll" or "cc"
    vim.api.nvim_exec_autocmds("QuickFixCmdPre", { pattern = pattern })
    rt._set_list(src_win, "u", { nr = 0, idx = idx })

    if split == "tabnew" then
        tabnew_open(list_win, item, finish, is_orphan, pattern)
        return
    end

    local should_resize = should_resize_list_win(list_win, dest_win, is_orphan) ---@type boolean
    local row, col = unpack(api.nvim_win_get_cursor(list_win)) ---@type integer, integer
    if row ~= idx then
        -- We don't know yet if handle_orphan will close the list_win, so don't skip this
        ru._protected_set_cursor(list_win, { idx, col })
        if not should_resize then ru._do_zzze(list_win) end
    end

    local buf_win = get_buf_win(dest_win, split, item.bufnr, list_win) ---@type integer
    local clearjumps = not (split == "none" and dest_win == buf_win) ---@type boolean
    local focus = finish == "focusWin" ---@type boolean
    ru._open_item_to_win(
        item,
        { buftype = dest_buftype, clearjumps = clearjumps, focus = focus, win = buf_win }
    )

    if should_resize then
        ro._resize_list_win(list_win)
        ru._do_zzze(list_win)
    end

    if is_orphan then handle_orphan(list_win, buf_win, finish) end
    vim.api.nvim_exec_autocmds("QuickFixCmdPost", { pattern = pattern })
end

-- MAPPING FUNCTIONS --

function M._open_direct_focuswin()
    open_item_from_list("none", "focusWin", ru._get_item_under_cursor)
end

function M._open_direct_focuslist()
    open_item_from_list("none", "focusList", ru._get_item_under_cursor)
end

function M._open_split_focuswin()
    open_item_from_list("split", "focusWin", ru._get_item_under_cursor)
end

function M._open_split_focuslist()
    open_item_from_list("split", "focusList", ru._get_item_under_cursor)
end

function M._open_vsplit_focuswin()
    open_item_from_list("vsplit", "focusWin", ru._get_item_under_cursor)
end

function M._open_vsplit_focuslist()
    open_item_from_list("vsplit", "focusList", ru._get_item_under_cursor)
end

function M._open_tabnew_focuswin()
    open_item_from_list("tabnew", "focusWin", ru._get_item_under_cursor)
end

function M._open_tabnew_focuslist()
    open_item_from_list("tabnew", "focusList", ru._get_item_under_cursor)
end

function M._open_prev_focuslist()
    open_item_from_list("none", "focusList", ru._get_item_wrapping_sub)
end

function M._open_next_focuslist()
    open_item_from_list("none", "focusList", ru._get_item_wrapping_add)
end

return M

-- TODO: tests

-- MAYBE: For some of the context switching, eventignore could be useful. But very bad if we error
-- with that option on

-- ================
-- == REFERENCES ==
-- ================

-- qf_view_result
-- ex_cc
-- qf_jump
-- qf_jump_newwin
-- qf_jump_open_window
-- jump_to_help_window
-- qf_jump_to_usable_window
-- qf_find_win_with_loclist
-- qf_open_new_file_win
-- qf_goto_win_with_ll_file
-- qf_goto_win_with_qfl_file
