local api = vim.api
local fn = vim.fn

local rt = Qfr_Defer_Require("qf-rancher.tools") ---@type QfrTools
local ru = Qfr_Defer_Require("qf-rancher.util") ---@type QfrUtil
local ry = Qfr_Defer_Require("qf-rancher.types") ---@type QfrTypes
local rw = Qfr_Defer_Require("qf-rancher.window") ---@type QfrWins

--- @class QfRancherFiletypeFuncs
local M = {}

-- LOW: Try doing these as operatorfuncs, using the `[`] marks to feed a qf delete function

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
    if #list.items < 1 then
        return
    end

    local row, col = unpack(api.nvim_win_get_cursor(list_win)) ---@type integer, integer
    local cur_idx = rt._get_list(src_win, { idx = 0 }).idx ---@type integer
    local new_idx = cur_idx > row and math.max(cur_idx - 1, 0) or cur_idx ---@type integer
    table.remove(list.items, row)
    local adj_idx = math.min(new_idx, #list.items) ---@type integer

    rt._set_list(src_win, "u", { nr = 0, items = list.items, idx = adj_idx })
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
    if #list.items < 1 then
        return
    end

    local cur = fn.getpos(".") ---@type [integer, integer, integer, integer]
    local fin = fn.getpos("v") ---@type [integer, integer, integer, integer]
    local selection = api.nvim_get_option_value("selection", { scope = "global" }) ---@type string
    --- @type [ [integer, integer, integer, integer], [integer, integer, integer, integer] ][]
    local region = fn.getregionpos(cur, fin, { type = mode, exclusive = selection == "exclusive" })
    ---@type Range4
    local vrange_4 =
        { region[1][1][2], region[1][1][3], region[#region][2][2], region[#region][2][3] }

    local cur_idx = rt._get_list(src_win, { idx = 0 }).idx ---@type integer
    local idx_dist = math.max(cur_idx - vrange_4[1], 0) ---@type integer
    local idx_move = math.min(idx_dist, vrange_4[3] - vrange_4[1] + 1) ---@type integer
    local new_idx = math.max(cur_idx - idx_move, 0) ---@type integer

    local col = vim.api.nvim_win_get_cursor(list_win)[2] ---@type integer
    api.nvim_cmd({ cmd = "normal", args = { "\27" }, bang = true }, {})
    for i = vrange_4[3], vrange_4[1], -1 do
        table.remove(list.items, i)
    end

    local adj_idx = math.min(new_idx, #list.items) ---@type integer
    rt._set_list(src_win, "u", {
        nr = 0,
        items = list.items,
        idx = adj_idx,
    })

    ru._protected_set_cursor(0, { vrange_4[1], col })
end

---@param list_win integer
---@param dest_win integer
---@param finish QfrFinishMethod
---@return nil
local function handle_orphan(list_win, dest_win, finish)
    if vim.g.qfr_debug_assertions then
        ry._validate_list_win(list_win)
        ry._validate_win(dest_win)
        ry._validate_finish(finish)
    end

    local dest_win_qf_id = fn.getloclist(dest_win, { id = 0 }).id ---@type integer
    if dest_win_qf_id > 0 then
        return
    end

    local stack = rt._get_stack(list_win) ---@type table[]
    rw._close_win_save_views(list_win)
    rt._set_stack(dest_win, stack)

    -- open_loclist uses :lopen, so must set win for proper context
    -- LOW: Does win_call provide proper context? Does it actually help the logic at all?
    api.nvim_set_current_win(dest_win)
    rw.open_loclist(dest_win, { keep_win = finish == "focusWin" })

    if vim.g.qfr_debug_assertions then
        local cur_win = api.nvim_get_current_win() ---@type integer
        if finish == "focusWin" then
            assert(cur_win == dest_win)
        end

        if finish == "focusList" then
            assert(fn.win_gettype(cur_win) == "loclist")
        end
    end
end

---@param buf integer
---@return boolean
local function is_buf_empty_noname(buf)
    if #api.nvim_buf_get_name(buf) > 0 then
        return false
    end

    local lines = api.nvim_buf_get_lines(buf, 0, -1, false) ---@type string[]
    if #lines > 1 or #lines[1] > 0 then
        return false
    end

    return true
end

-- MID: You could have an opt for whether to treat nonames like any other valid win or only use
-- them as a backup

---@param win integer
---@param dest_bt string
---@return boolean
--- NOTE: Because this runs in loops, skip validation
local function is_valid_dest_win(win, dest_bt)
    if fn.win_gettype(win) ~= "" then
        return false
    end

    local buf = api.nvim_win_get_buf(win) ---@type integer
    if api.nvim_get_option_value("bt", { buf = buf }) == dest_bt then
        return true
    end

    return is_buf_empty_noname(buf)
end

-- Can be run recursively in other loops. Skip validation
---@param tabnr integer
---@param dest_bt string
---@param opts QfrFindWinInTabOpts
---@return integer|nil
local function find_win_in_tab(tabnr, dest_bt, opts)
    if vim.g.qfr_debug_assertions then
        ry._validate_uint(tabnr)
        vim.validate("dest_buftype", dest_bt, "string")
        ry._validate_find_win_in_tab_opts(opts)
    end

    local max_winnr = fn.tabpagewinnr(tabnr, "$") ---@type integer
    local skip_winnr = opts.skip_winnr ---@type integer|nil
    for i = 1, max_winnr do
        if i ~= skip_winnr then
            local win = fn.win_getid(i, tabnr)
            local valid_buf = (function()
                if not opts.buf then
                    return true
                end

                return api.nvim_win_get_buf(win) == opts.buf
            end)()

            if valid_buf and is_valid_dest_win(win, dest_bt) then
                return win
            end
        end
    end

    return nil
end

-- MID: Another broad change will be done to how we acquire windows - mini.jump2d provides us a
-- way to guarantee that we can list winids in order. This will make it more manageable to
-- get win configs to filter for things like focusable or not floating or whatever. Will also
-- allow for less vim.fn use. Similarly to the location list finding, each element of scanning the
-- wins is a separate thing, and they should build on top of each other

-- -- MID: This would be an improvement
-- ---@param tabnr integer
-- ---@param winnrs integer[]
-- ---@param dest_bt string
-- ---@param but integer?
-- ---@return integer|nil
-- local function find_win_in_tab(tabnr, winnrs, dest_bt, buf)
--     if ru._get_g_var("qfr_debug_assertions") then
--         ry._validate_uint(tabnr)
--         ry._validate_list(winnrs, { type = "number" })
--         vim.validate("dest_buftype", dest_bt, "string")
--         ry._validate_uint(buf, true)
--     end
--
--     for _, n in ipairs(winnrs) do
--         local win = fn.win_getid(n, tabnr)
--         if is_valid_dest_win(win, dest_bt) then
--             if not buf then return win end
--             if buf and api.nvim_win_get_buf(win) == buf then return win end
--         end
--     end
--
--     return nil
-- end
--
-- local winnrs = { 1, 2, 3, 4 }
-- local list_winnr = 4
-- -- Or skip this if we want the list included
-- local winnrs_nolist = vim.tbl_map(function(w)
--     return w ~= list_winnr
-- end, winnrs)
--
-- local dest_bt = "help"
-- local tabnr = 1
-- local buf = nil
-- local dest_winnr = vim.iter(winnrs_nolist):find(function(n)
--     local win = fn.win_getid(n, tabnr)
--     if is_valid_dest_win(win, dest_bt) then
--         if not buf then return true end
--         return buf and api.nvim_win_get_buf(win) == buf
--     end
--
--     return false
-- end)
--
-- find_win_in_tab(1, winnrs_nolist, "help", nil)

---@param list_tabnr integer
---@param dest_buftype string
---@param buf integer|nil
---@return integer|nil
local function find_win_in_tabs(list_tabnr, dest_buftype, buf)
    if vim.g.qfr_debug_assertions then
        ry._validate_uint(list_tabnr)
        vim.validate("dest_buftype", dest_buftype, "string")
        ry._validate_uint(buf, true)
    end

    local test_tabnr = list_tabnr ---@type integer
    local max_tabnr = fn.tabpagenr("$") ---@type integer
    for _ = 1, 100 do
        test_tabnr = test_tabnr + 1
        if test_tabnr > max_tabnr then
            test_tabnr = 1
        end

        if test_tabnr == list_tabnr then
            break
        end

        ---@type integer|nil
        local tabpage_win = find_win_in_tab(test_tabnr, dest_buftype, { buf = buf })
        if tabpage_win then
            return tabpage_win
        end
    end

    return nil
end

-- LOW: This should be an optional subset of find_win_in_tab

---@param tabnr integer
---@param dest_buftype string
---@param opts QfrFindWinInTabOpts
---@return integer|nil
local function find_win_in_tab_reverse(tabnr, dest_buftype, opts)
    if vim.g.qfr_debug_assertions then
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
        if test_winnr <= 0 then
            test_winnr = max_winnr
        end

        if test_winnr ~= skip_winnr then
            -- Convert now because win_gettype does not support tab context
            local win = fn.win_getid(test_winnr, tabnr) ---@type integer
            if is_valid_dest_win(win, dest_buftype) then
                return win
            end
        end

        if test_winnr == fin_winnr then
            break
        end
    end

    return nil
end

---@param dest_buftype string
---@return integer|nil
local function get_vcount_win_id(dest_buftype)
    if vim.g.qfr_debug_assertions then
        vim.validate("dest_buftype", dest_buftype, "string")
    end

    if vim.v.count < 1 then
        return nil
    end

    local adj_count = math.min(vim.v.count, #api.nvim_tabpage_list_wins(0)) ---@type integer
    local target_win = fn.win_getid(adj_count) ---@type integer
    if is_valid_dest_win(target_win, dest_buftype) then
        return target_win
    end

    return nil
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

-- MID: Rename QfrSplit because it conflicts with win cfg split naming

---@param dest_win integer|nil
---@param split QfrSplitType
---@param list_win integer
local function get_resolved_split_win(dest_win, split, list_win)
    if vim.g.qfr_debug_assertions then
        ry._validate_win(dest_win, true)
        ry._validate_list_win(list_win)
        ry._validate_split(split)
    end

    if dest_win and split == "none" then
        return dest_win
    end

    local scratch = create_scratch_buf() ---@type integer
    if not dest_win then
        return api.nvim_open_win(scratch, false, { win = list_win, split = "above" })
    end

    local split_dir = (function()
        if split == "split" then
            ---@type boolean
            local sb = api.nvim_get_option_value("sb", { scope = "global" })
            return sb and "below" or "above" ---@type string
        else
            ---@type boolean
            local spr = api.nvim_get_option_value("spr", { scope = "global" })
            return spr and "right" or "left" ---@type string
        end
    end)() ---@type string

    return api.nvim_open_win(scratch, false, { win = dest_win, split = split_dir })
end

-- LOW: Use strategy pattern to merge with norm_win_ext
---@param list_tabnr integer
---@param list_winnr integer
---@param split QfrSplitType
---@return integer|nil
local function get_help_win_ext(list_tabnr, list_winnr, split)
    if vim.g.qfr_debug_assertions then
        ry._validate_uint(list_tabnr)
        ry._validate_uint(list_winnr)
        ry._validate_split(split)
    end

    local other_help_win = find_win_in_tab(list_tabnr, "help", { skip_winnr = list_winnr })
    if other_help_win then
        return other_help_win
    end

    if split == "none" then
        return nil
    end

    ---@type QfrFindWinInTabOpts
    local find_opts = { fin_winnr = list_winnr, skip_winnr = list_winnr }
    return find_win_in_tab_reverse(list_tabnr, "", find_opts)
end

---@return string, boolean, boolean
local function get_basic_swb()
    local swb = api.nvim_get_option_value("swb", { scope = "global" }) ---@type string
    local useopen = string.find(swb, "useopen", 1, true) ~= nil ---@type boolean
    local usetab = string.find(swb, "usetab", 1, true) ~= nil ---@type boolean
    return swb, useopen, usetab
end

---@param list_win integer
---@return integer, integer
local function get_list_win_nrs(list_win)
    if vim.g.qfr_debug_assertions then
        ry._validate_list_win(list_win)
    end

    local list_tabpage = api.nvim_win_get_tabpage(list_win) ---@type integer
    local list_tabnr = api.nvim_tabpage_get_number(list_tabpage) ---@type integer
    local list_winnr = api.nvim_win_get_number(list_win) ---@type integer
    return list_tabnr, list_winnr
end

---@param list_win integer
---@param origin integer?
---@param buf integer
---@param split QfrSplitType
---@return integer|nil
local function get_help_win_ll(list_win, origin, buf, split)
    if vim.g.qfr_debug_assertions then
        ry._validate_list_win(list_win)
        ry._validate_win(origin, true)
        ry._validate_buf(buf)
        ry._validate_split(split)
    end

    local dest_bt = "help"
    local vcount_win = get_vcount_win_id(dest_bt)
    if vcount_win then
        return vcount_win
    end

    if origin and is_valid_dest_win(origin, dest_bt) then
        return origin
    end

    local list_tabnr, list_winnr = get_list_win_nrs(list_win) ---@type integer, integer

    ---@type integer|nil
    local b_win = find_win_in_tab(list_tabnr, dest_bt, { buf = buf, skip_winnr = list_winnr })
    if b_win then
        return b_win
    end

    return get_help_win_ext(list_tabnr, list_winnr, split)
end

---@param list_win integer
---@param buf integer
---@param split QfrSplitType
---@return integer|nil
local function get_help_win_qf(list_win, buf, split)
    if vim.g.qfr_debug_assertions then
        ry._validate_list_win(list_win)
        ry._validate_buf(buf)
        ry._validate_split(split)
    end

    local dest_bt = "help"
    local vcount_win = get_vcount_win_id(dest_bt)
    if vcount_win then
        return vcount_win
    end

    local list_tabnr, list_winnr = get_list_win_nrs(list_win) ---@type integer, integer
    local _, useopen, usetab = get_basic_swb() ---@type string, boolean, boolean

    -- Deviation from core: respect switchbuf for finding a help win in the current tab
    if useopen or usetab then
        ---@type integer|nil
        local tabpage_buf_win =
            find_win_in_tab(list_tabnr, dest_bt, { buf = buf, skip_winnr = list_winnr })
        if tabpage_buf_win then
            return tabpage_buf_win
        end
    end

    return get_help_win_ext(list_tabnr, list_winnr, split)
end

---@param list_tabnr integer
---@param list_winnr integer
---@param split QfrSplitType?
---@return integer|nil
local function get_norm_win_ext(list_tabnr, list_winnr, split)
    ---@type QfrFindWinInTabOpts
    local rev_find_opts = { fin_winnr = list_winnr, skip_winnr = list_winnr }
    local other_win = find_win_in_tab_reverse(list_tabnr, "", rev_find_opts)
    if other_win then
        return other_win
    end

    if (not split) or split == "none" then
        return nil
    end

    return find_win_in_tab(list_tabnr, "help", { skip_winnr = list_winnr })
end

---@param list_win integer
---@param origin integer?
---@param buf integer
---@param split QfrSplitType
---@return integer|nil
local function find_norm_win_ll(list_win, origin, buf, split)
    if vim.g.qfr_debug_assertions then
        ry._validate_list_win(list_win)
        ry._validate_win(origin, true)
        ry._validate_buf(buf)
        ry._validate_split(split)
    end

    local dest_bt = ""
    local vcount_win = get_vcount_win_id(dest_bt)
    if vcount_win then
        return vcount_win
    end

    if origin and is_valid_dest_win(origin, dest_bt) then
        return origin
    end

    local list_tabnr, list_winnr = get_list_win_nrs(list_win) ---@type integer, integer

    ---@type integer|nil
    local tabpage_buf_win =
        find_win_in_tab(list_tabnr, dest_bt, { buf = buf, skip_winnr = list_winnr })
    if tabpage_buf_win then
        return tabpage_buf_win
    end

    return get_norm_win_ext(list_tabnr, list_winnr, split)
end

---@param list_win integer
---@param buf integer
---@param split QfrSplitType
---@return integer|nil
local function find_norm_win_qf(list_win, buf, split)
    if vim.g.qfr_debug_assertions then
        ry._validate_list_win(list_win)
        ry._validate_buf(buf)
        ry._validate_split(split)
    end

    local dest_bt = ""
    local vcount_win = get_vcount_win_id(dest_bt)
    if vcount_win then
        return vcount_win
    end

    local list_tabnr, list_winnr = get_list_win_nrs(list_win) ---@type integer, integer
    local swb, useopen, usetab = get_basic_swb() ---@type string, boolean, boolean

    if useopen or usetab then
        ---@type integer|nil
        local tabpage_buf_win =
            find_win_in_tab(list_tabnr, dest_bt, { buf = buf, skip_winnr = list_winnr })
        if tabpage_buf_win then
            return tabpage_buf_win
        end
    end

    if usetab then
        local usetab_win = find_win_in_tabs(list_tabnr, dest_bt, buf) ---@type integer|nil
        if usetab_win then
            return usetab_win
        end
    end

    if string.find(swb, "uselast", 1, true) ~= nil then
        local alt_win = fn.win_getid(fn.tabpagewinnr(list_tabnr, "#"), list_tabnr) ---@type integer
        if is_valid_dest_win(alt_win, dest_bt) then
            return alt_win
        end
    end

    return get_norm_win_ext(list_tabnr, list_winnr, split)
end

---@param is_orphan boolean|nil
---@param list_win integer
---@param split QfrSplitType
---@return boolean
local function should_resize_list_win(is_orphan, list_win, split)
    if vim.g.qfr_debug_assertions then
        vim.validate("is_orphan", is_orphan, "boolean", true)
        ry._validate_list_win(list_win)
    end

    if is_orphan then
        return false
    end -- Orphan lists are expected to be closed

    local list_win_tabpage = api.nvim_win_get_tabpage(list_win) ---@type integer
    if #api.nvim_tabpage_list_wins(list_win_tabpage) == 1 then
        return true
    end

    return split ~= "none" and vim.g.qfr_auto_list_height
end

---@param dest_bt string
---@param split QfrSplitType
---@param finish QfrFinishMethod
---@return QfrBufOpenOpts
local function get_open_opts(dest_bt, split, finish)
    return { buftype = dest_bt, clearjumps = split ~= "none", focus = finish == "focusWin" }
end

---@param is_orphan boolean?
---@param dir integer
---@param finish QfrFinishMethod
---@param list_win integer
---@param item vim.quickfix.entry
---@param new_idx integer
---@param dest_bt string
---@param pattern string
---@return nil
local function open_item_tabnew(is_orphan, dir, finish, list_win, item, new_idx, dest_bt, pattern)
    if vim.g.qfr_debug_assertions then
        vim.validate("is_orphan", is_orphan, "boolean", true)
        ry._validate_int(dir)
        ry._validate_finish(finish)
        ry._validate_list_win(list_win)
        ry._validate_list_item(item)
        ry._validate_uint(new_idx)
        vim.validate("dest_bt", dest_bt, "string")
        vim.validate("pattern", pattern, "string")
    end

    local max_tabnr = fn.tabpagenr("$") ---@type integer
    ---@type integer
    local range = vim.v.count <= 0 and max_tabnr or math.min(vim.v.count, fn.tabpagenr("$"))
    api.nvim_cmd({ cmd = "tabnew", range = { range } }, {})
    local dest_win = api.nvim_get_current_win() ---@type integer

    if (not is_orphan) and finish == "focusList" then
        api.nvim_set_current_win(list_win)
    end

    local tn_buf = api.nvim_win_get_buf(dest_win) ---@type integer
    if is_buf_empty_noname(tn_buf) then
        api.nvim_set_option_value("bufhidden", "wipe", { buf = tn_buf })
    end

    if (not is_orphan) and dir ~= 0 then
        local col = api.nvim_win_get_cursor(list_win)[2] ---@type integer
        api.nvim_win_set_cursor(list_win, { new_idx, col })
        ru._do_zzze(list_win)
    end

    rt._set_list(nil, "u", { nr = 0, idx = new_idx })
    ru._open_item(item, dest_win, get_open_opts(dest_bt, "tabnew", finish))
    if is_orphan then
        handle_orphan(list_win, dest_win, finish)
    end

    api.nvim_exec_autocmds("QuickFixCmdPost", { pattern = pattern })
end

---@param dir integer
---@param split QfrSplitType
---@param finish QfrFinishMethod
---@param list_win integer
---@param item vim.quickfix.entry
---@param new_idx integer
---@param dest_bt string
---@return nil
local function open_item_ll(dir, split, finish, list_win, item, new_idx, dest_bt)
    local pattern = "ll"
    api.nvim_exec_autocmds("QuickFixCmdPre", { pattern = pattern })
    local src_win = list_win ---@type integer
    local origin = ru._find_loclist_origin(src_win, { tabpage = 0 }) ---@type integer|nil
    local is_orphan = not origin ---@type boolean

    if split == "tabnew" then
        open_item_tabnew(is_orphan, dir, finish, list_win, item, new_idx, dest_bt, pattern)
        return
    end

    local orig_win = (function()
        if dest_bt == "help" then
            return get_help_win_ll(list_win, origin, item.bufnr, split)
        end
        return find_norm_win_ll(list_win, origin, item.bufnr, split)
    end)()

    local should_resize = should_resize_list_win(is_orphan, list_win, split) ---@type boolean
    if (not is_orphan) and dir ~= 0 then
        local col = api.nvim_win_get_cursor(list_win)[2] ---@type integer
        api.nvim_win_set_cursor(list_win, { new_idx, col })
    end

    rt._set_list(nil, "u", { nr = 0, idx = new_idx })
    local dest_win = get_resolved_split_win(orig_win, split, list_win) ---@type integer
    ru._open_item(item, dest_win, get_open_opts(dest_bt, split, finish))

    if is_orphan then
        handle_orphan(list_win, dest_win, finish)
    elseif should_resize then
        rw._resize_list_win(list_win)
        api.nvim_cmd({ cmd = "wincmd", args = { "=" } }, {})
    end

    if should_resize or dir ~= 0 then
        ru._do_zzze(list_win)
    end

    api.nvim_exec_autocmds("QuickFixCmdPost", { pattern = pattern })
end

---@param dir integer
---@param split QfrSplitType
---@param finish QfrFinishMethod
---@param list_win integer
---@param item vim.quickfix.entry
---@param new_idx integer
---@param dest_bt string
---@return nil
local function open_item_qf(dir, split, finish, list_win, item, new_idx, dest_bt)
    local pattern = "cc" ---@type string
    api.nvim_exec_autocmds("QuickFixCmdPre", { pattern = pattern })

    if split == "tabnew" then
        open_item_tabnew(nil, dir, finish, list_win, item, new_idx, dest_bt, pattern)
        return
    end

    ---@type integer|nil
    local orig_win = (function()
        if dest_bt == "help" then
            return get_help_win_qf(list_win, item.bufnr, split)
        end
        return find_norm_win_qf(list_win, item.bufnr, split)
    end)()

    ---@type boolean
    local should_resize = should_resize_list_win(nil, list_win, split) ---@type boolean

    if dir ~= 0 then
        local col = api.nvim_win_get_cursor(list_win)[2] ---@type integer
        api.nvim_win_set_cursor(list_win, { new_idx, col })
    end

    rt._set_list(nil, "u", { nr = 0, idx = new_idx })
    local dest_win = get_resolved_split_win(orig_win, split, list_win) ---@type integer
    ru._open_item(item, dest_win, get_open_opts(dest_bt, split, finish))

    if should_resize then
        rw._resize_list_win(list_win)
        -- MID: This behavior could be better abstracted or more finely controlled
        api.nvim_cmd({ cmd = "wincmd", args = { "=" } }, {})
    end

    if should_resize or dir ~= 0 then
        ru._do_zzze(list_win)
    end

    vim.api.nvim_exec_autocmds("QuickFixCmdPost", { pattern = pattern })
end

-- MID: This does too much. Getting the idx and getting the item should be handled separately
-- A technical issue as well - These functions get and discard data that is needed later

---@param dir integer
---@return nil
local function get_item_fn(dir, src_win)
    if dir == -1 then
        return ru._get_item_wrapping_sub(src_win)
    end

    if dir == 1 then
        return ru._get_item_wrapping_add(src_win)
    end

    return ru._get_item_under_cursor(src_win)
end

-- MID: Rather than finish type being a str, just use focus as a boolean
-- MID: Depending on what's most helpful, this could return the winid or the bufnr if the opened
-- item. Vaguely, the user could use the return to run some kind of custom function
-- LOW: If the item does not have a valid bufnr, there might be some way to hack together an
-- openable buf from the qf contents. But I don't have a concrete use case to work from
-- MAYBE: I'm not sure if bufname should be checked in this function or not

---@param dir integer
---@param split QfrSplitType
---@param finish QfrFinishMethod
---@return nil
local function open_list_item(dir, split, finish)
    ry._validate_finish(finish)

    local list_win = api.nvim_get_current_win() ---@type integer
    local wintype = fn.win_gettype(list_win)
    if not (wintype == "quickfix" or wintype == "loclist") then
        api.nvim_echo({ { "Not inside a list window", "" } }, false, {})
        return
    end

    local is_ll = wintype == "loclist" ---@type boolean
    local src_win = is_ll and list_win or nil
    local item, new_idx = get_item_fn(dir, src_win) ---@type vim.quickfix.entry|nil, integer|nil
    if not (item and new_idx) then
        api.nvim_echo({ { "No list entries" } }, false, {})
        return
    end

    if not (item.bufnr and api.nvim_buf_is_valid(item.bufnr)) then
        api.nvim_echo({ { "Item does not contain a valid bufnr" } }, true, { error = true })
        return
    end

    local dest_bt = item.type == "\1" and "help" or "" ---@type string
    if is_ll then
        open_item_ll(dir, split, finish, list_win, item, new_idx, dest_bt)
    else
        open_item_qf(dir, split, finish, list_win, item, new_idx, dest_bt)
    end
end

function M._open_direct_focuswin()
    open_list_item(0, "none", "focusWin")
end

function M._open_direct_focuslist()
    open_list_item(0, "none", "focusList")
end

function M._open_split_focuswin()
    open_list_item(0, "split", "focusWin")
end

function M._open_split_focuslist()
    open_list_item(0, "split", "focusList")
end

function M._open_vsplit_focuswin()
    open_list_item(0, "vsplit", "focusWin")
end

function M._open_vsplit_focuslist()
    open_list_item(0, "vsplit", "focusList")
end

function M._open_tabnew_focuswin()
    open_list_item(0, "tabnew", "focusWin")
end

function M._open_tabnew_focuslist()
    open_list_item(0, "tabnew", "focusList")
end

function M._open_prev_focuslist()
    open_list_item(-1, "none", "focusList")
end

function M._open_next_focuslist()
    open_list_item(1, "none", "focusList")
end

return M

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
