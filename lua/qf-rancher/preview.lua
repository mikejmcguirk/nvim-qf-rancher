local ru = Qfr_Defer_Require("qf-rancher.util") ---@type qf-rancher.Util
local ry = Qfr_Defer_Require("qf-rancher.types") ---@type qf-rancher.Types

local api = vim.api
local fn = vim.fn
local set_opt = api.nvim_set_option_value
local uv = vim.uv

local bufs = {} ---@type integer[]
local extmarks = {} ---@type integer[]
local parsers = {} ---@type boolean[]

local GROUP_NAME = "qfr-preview-group"
local group = api.nvim_create_augroup(GROUP_NAME, {})

local MAX_WIN_HEIGHT = 24
local MIN_WIN_HEIGHT = 6
local MIN_WIN_WIDTH = 79
local WIN_SCROLLOFF = 6

local hl_ns = api.nvim_create_namespace("qfr-preview-hl")
local HL_GROUP = "QfRancherPreviewRange"
local cur_hl = api.nvim_get_hl(0, { name = HL_GROUP })
local cur_hl_keys = vim.tbl_keys(cur_hl)
if (not cur_hl) or #cur_hl_keys == 0 then
    api.nvim_set_hl(0, HL_GROUP, { link = "CurSearch" })
end

local timer = nil ---@type uv.uv_timer_t|nil
local queued_update = false
local checked_clear_idle_handle = nil ---@type uv.uv_idle_t|nil

local function checked_stop_timer()
    if timer then
        timer:stop()
        timer:close()
        timer = nil
    end
end

---@private
---@class QfRancherPreviewState
---@field preview_win integer|nil
---@field list_win integer|nil
---@field set fun(self: QfRancherPreviewState, list_win: integer, preview_win: integer)
---@field is_open fun(self: QfRancherPreviewState): boolean
---@field clear fun(self: QfRancherPreviewState)

---@type QfRancherPreviewState
---@diagnostic disable-next-line: missing-fields
local win_state = {
    preview_win = nil,
    list_win = nil,
}

---@param self QfRancherPreviewState
---@param list_win integer
---@param preview_win integer
---@return nil
function win_state:set(list_win, preview_win)
    self.list_win = list_win
    self.preview_win = preview_win
end

---@param self QfRancherPreviewState
---@return boolean
function win_state:is_open()
    local list_win_uint = ry._is_uint(self.list_win)
    local preview_win_uint = ry._is_uint(self.preview_win)
    return list_win_uint and preview_win_uint
end

---@param self QfRancherPreviewState
---@return nil
function win_state:clear()
    self.preview_win = nil
    self.list_win = nil
end

---@return nil
local function close_preview_win()
    if win_state:is_open() then
        ru._pwin_close(win_state.preview_win, true)
        win_state:clear()
    end
end

---@return nil
local function clear_session_data()
    close_preview_win()

    -- MID: Could be useful to have an opt to keep caches for bufs over X integer file size
    for _, buf in pairs(bufs) do
        api.nvim_buf_delete(buf, { force = true })
    end

    bufs = {}
    extmarks = {}

    local autocmds = api.nvim_get_autocmds({ group = group })
    for _, autocmd in pairs(autocmds) do
        api.nvim_del_autocmd(autocmd.id)
    end
end

---@return boolean
local function has_list_wins()
    local tabpages = api.nvim_list_tabpages()
    local qf_wins = ru._find_qf_wins(tabpages)
    if #qf_wins > 0 then
        return true
    end

    local ll_wins = ru._find_ll_wins({ tabpages = tabpages })
    return #ll_wins > 0
end

---@return nil
local function checked_session_clear()
    local has_lists = has_list_wins()
    if not has_lists then
        clear_session_data()
    end
end

---@return nil
local function checked_clear_when_idle()
    if checked_clear_idle_handle then
        return
    end

    checked_clear_idle_handle = uv.new_idle()
    if not checked_clear_idle_handle then
        checked_session_clear()
        return
    end

    checked_clear_idle_handle:start(function()
        -- This has the side benefit of ensuring that closed windows are removed from the layout
        vim.schedule(function()
            checked_session_clear()
        end)

        checked_clear_idle_handle:stop()
        checked_clear_idle_handle:close()
        checked_clear_idle_handle = nil
    end)
end

-- MAYBE: For refreshing the preview_win, the opts table needs to be re-created from scratch in
-- update_preview_win_buf and update_preview_win_pos. It would save some heap allocs if the opts
-- were simply passed in as variables. Counterpoint - Opts is more flexible.

---@param item_buf integer|nil
---@param opts qf-rancher.preview.OpenOpts
---@return vim.api.keyset.win_config
local function get_title_config(item_buf, opts)
    if not opts.title_pos then
        return { title = nil }
    end

    if opts._title then
        return { title = opts._title, title_pos = opts.title_pos }
    end

    if not (item_buf and api.nvim_buf_is_valid(item_buf)) then
        return { title = "No buffer" }
    end

    local bufname = fn.bufname(item_buf)
    return { title = bufname, title_pos = opts.title_pos }
end

---@param opts qf-rancher.preview.OpenOpts
---@return qf-rancher.types.Border|string[]
local function get_win_border(opts)
    if opts.border then
        return opts.border
    end

    -- FUTURE: When v12 comes out, remove this check
    local has_v11 = fn.has("nvim-0.11")
    local winborder = has_v11 == 1 and api.nvim_get_option_value("winborder", { scope = "global" })
        or "single"

    return winborder ~= "" and winborder or "single"
end

---@param base_cfg table
---@param e_lines integer
---@param e_cols integer
---@param padding integer
---@param border_width integer
---@return vim.api.keyset.win_config
local function get_fallback_win_config(base_cfg, e_lines, e_cols, padding, border_width)
    local height = math.floor(e_lines * 0.4)
    height = math.min(height, MAX_WIN_HEIGHT)
    local width = e_cols - (padding * 2) - border_width
    ---@type vim.api.keyset.win_config
    local fallback_base = vim.tbl_extend("force", base_cfg, {
        relative = "tabline",
        height = height,
        width = width,
        col = 1,
    })

    fallback_base.win = nil
    local screenrow = fn.screenrow()
    local half_way = e_lines * 0.5
    if screenrow <= half_way then
        local row = math.floor(e_lines * 0.6)
        return vim.tbl_extend("force", fallback_base, { row = row })
    else
        return vim.tbl_extend("force", fallback_base, { row = 0 })
    end
end

-- MID: This function has the feeling of laying a bunch of pieces on the table without a coherent
-- sense of what they're driving toward, then suddenly arriving at a positioning to use. Data
-- should be introduced in a way that makes its purpose clear.
-- MID: If you use window sizing to artificially compress the editor height, goofy things happen
-- with the preview win position. Given that this is an outlier case, defer until the
-- position logic is cleaner.

---@param list_win integer
---@param item_buf integer?
---@param opts qf-rancher.preview.OpenOpts
---@return vim.api.keyset.win_config
local function create_win_cfg(list_win, item_buf, opts)
    local PADDING = 1
    local VIM_SEPARATOR = 1

    local border = get_win_border(opts)
    local has_border = border ~= "none" and border ~= ""
    local preview_border_cells = has_border and 2 or 0
    -- Disable diag because the win_config border annotation does not accept "bold" or ""
    ---@type vim.api.keyset.win_config
    ---@diagnostic disable-next-line: assign-type-mismatch
    local base_config = { border = border, focusable = false, relative = "win", win = list_win }
    base_config = (function()
        if item_buf then
            local title_config = get_title_config(item_buf, opts)
            -- MID: This works but feels like an unnecessarily heavy operation
            return vim.tbl_extend("force", base_config, title_config)
        else
            return base_config
        end
    end)()

    local list_win_pos = api.nvim_win_get_position(list_win)
    local list_win_width = api.nvim_win_get_width(list_win)
    local e_cols = api.nvim_get_option_value("columns", { scope = "global" }) ---@type integer

    local avail_x_left = math.max(list_win_pos[2] - VIM_SEPARATOR, 0)
    local avail_x_right = math.max(e_cols - (list_win_pos[2] + list_win_width + VIM_SEPARATOR), 0)
    local avail_width = list_win_width - (PADDING * 2) - preview_border_cells
    local avail_e_width = e_cols - (PADDING * 2) - preview_border_cells

    -- Window width and height only account for the inside of the window, not its borders. For
    -- consistency, track the target internal size of the window separately from the space needed
    -- to render the window plus the borders and padding
    local min_x = MIN_WIN_WIDTH + (PADDING * 2) + preview_border_cells

    -- NOTE: Prefer rendering previews with spill into other wins to keep the direction
    -- they appear as consistent as possible

    ---@param height integer
    ---@param row integer
    ---@return vim.api.keyset.win_config
    local function get_config_vert_spill(height, row)
        local x_diff = min_x - list_win_width
        local half_diff = math.ceil(x_diff * 0.5)
        local r_shift = math.max(half_diff - avail_x_left, 0)
        local l_shift = math.max(half_diff - avail_x_right, 0)
        return vim.tbl_extend("force", base_config, {
            height = height,
            row = row,
            width = math.min(MIN_WIN_WIDTH, avail_e_width),
            col = (half_diff * -1) + r_shift - l_shift + 1,
        })
    end

    ---@param height integer
    ---@param row integer
    ---@return vim.api.keyset.win_config
    local function use_avail_y(height, row)
        if list_win_width >= min_x then
            return vim.tbl_extend("force", base_config, {
                height = height,
                row = row,
                width = avail_width,
                col = 1,
            })
        else
            return get_config_vert_spill(height, row)
        end
    end

    local avail_y_above = math.max(list_win_pos[1] - VIM_SEPARATOR - 1, 0)
    local min_y = MIN_WIN_HEIGHT + preview_border_cells

    if avail_y_above >= min_y then
        local height = avail_y_above - preview_border_cells
        height = math.min(height, MAX_WIN_HEIGHT)
        local row = (height + preview_border_cells + VIM_SEPARATOR) * -1
        return use_avail_y(height, row)
    end

    local list_win_height = api.nvim_win_get_height(list_win)
    local e_lines = api.nvim_get_option_value("lines", { scope = "global" }) ---@type integer
    local avail_y_below = e_lines - (list_win_pos[1] + list_win_height + VIM_SEPARATOR + 1)

    if avail_y_below >= min_y then
        local height = avail_y_below - preview_border_cells
        height = math.min(height, MAX_WIN_HEIGHT)
        local row = list_win_height + VIM_SEPARATOR
        return use_avail_y(height, row)
    end

    local avail_height = list_win_height - (PADDING * 2) - preview_border_cells
    local avail_e_lines = e_lines - preview_border_cells
    local side_height = math.min(avail_height, MAX_WIN_HEIGHT)

    ---@param width integer
    ---@param col integer
    ---@return vim.api.keyset.win_config
    local function cfg_hor_spill(width, col)
        local y_diff = min_y - list_win_height
        local half_diff = math.floor(y_diff * 0.5)
        local u_shift = math.max(half_diff - avail_y_above, 0)
        local d_shift = math.max(half_diff - avail_y_below, 0)
        return vim.tbl_extend("force", base_config, {
            height = math.min(MIN_WIN_HEIGHT, avail_e_lines),
            row = (half_diff * -1) - u_shift + d_shift - 1,
            width = width,
            col = col,
        })
    end

    ---@param col integer
    ---@param avail_x integer
    ---@return vim.api.keyset.win_config
    local function use_avail_x(col, avail_x)
        local width = avail_x - (PADDING * 2) - preview_border_cells
        if list_win_height >= min_y then
            return vim.tbl_extend("force", base_config, {
                height = side_height,
                row = 0,
                width = width,
                col = col,
            })
        else
            return cfg_hor_spill(width, col)
        end
    end

    ---@return vim.api.keyset.win_config
    local function open_left()
        local col = (list_win_pos[2] - VIM_SEPARATOR) * -1
        return use_avail_x(col, avail_x_left)
    end

    ---@return vim.api.keyset.win_config
    local function open_right()
        local col = list_win_pos[2] + list_win_width + VIM_SEPARATOR + PADDING
        return use_avail_x(col, avail_x_right)
    end

    -- LOW: Unsure how to document this behavior without going into over-explanation
    local spr = api.nvim_get_option_value("spr", { scope = "global" }) ---@type boolean
    if spr then
        if avail_x_right >= min_x then
            return open_right()
        elseif avail_x_left >= min_x then
            return open_left()
        end
    else
        if avail_x_left >= min_x then
            return open_left()
        elseif avail_x_right >= min_x then
            return open_right()
        end
    end

    return get_fallback_win_config(base_config, e_lines, e_cols, PADDING, preview_border_cells)
end

---@return nil
local function update_preview_win_pos()
    if not win_state:is_open() then
        return
    end

    local cur_config = api.nvim_win_get_config(win_state.preview_win)
    local opts = {} ---@type qf-rancher.preview.OpenOpts
    opts.border = cur_config.border
    opts._title = cur_config.title
    opts.title_pos = cur_config.title_pos

    local win_cfg = create_win_cfg(win_state.list_win, nil, opts)
    api.nvim_win_set_config(win_state.preview_win, win_cfg)

    ru._do_zzze(win_state.preview_win, true)
end

---@param buf integer
---@return nil
local function setup_preview_buf(buf)
    set_opt("buflisted", false, { buf = buf })
    set_opt("buftype", "nofile", { buf = buf })
    set_opt("modifiable", false, { buf = buf })
    set_opt("readonly", true, { buf = buf })
    set_opt("swapfile", false, { buf = buf })
    set_opt("undofile", false, { buf = buf })
end

-- MAYBE: You could just create the fallback buf on module open and store it in memory. Feels
-- unnecessary though since I've never had to use it.

---@return integer
local function create_fallback_buf()
    local buf = api.nvim_create_buf(false, true)

    set_opt("bufhidden", "wipe", { buf = buf })
    setup_preview_buf(buf)

    local lines = { "No bufnr for this list entry" }
    api.nvim_buf_set_lines(buf, 0, 0, false, lines)

    return buf
end

-- LOW: If the buf needs to be read from disk, should be done async.
-- - Study Lua co-routines, built-in async lib, and lewis's async lib
-- - Trouble also uses a mini-async library
-- - Or maybe just wait for vim.async

---@param item_buf integer
---@return string[]
local function get_item_buf_lines(item_buf)
    if not api.nvim_buf_is_valid(item_buf) then
        return { item_buf .. " is not valid" }
    end

    if api.nvim_buf_is_loaded(item_buf) then
        return api.nvim_buf_get_lines(item_buf, 0, -1, false)
    end

    local full_path = api.nvim_buf_get_name(item_buf)
    if uv.fs_access(full_path, 4) then
        return fn.readfile(full_path, "")
    end

    return { "Unable to read lines for bufnr " .. item_buf }
end

-- LOW: It would be better if some kind of differential update were performed

---@param item_buf integer
---@param cache_buf integer
---@return nil
local function update_preview_buf(item_buf, cache_buf)
    -- This function should only called because of an update to a known valid buffer
    local lines = get_item_buf_lines(item_buf) ---@type string[]
    set_opt("modifiable", true, { buf = cache_buf })
    api.nvim_buf_set_lines(cache_buf, 0, -1, false, lines)
    set_opt("modifiable", false, { buf = cache_buf })
end

---@param item_buf integer
---@return integer
local function get_mtime(item_buf)
    local buf_fname = api.nvim_buf_get_name(item_buf)
    local stat = uv.fs_stat(buf_fname)
    return stat and stat.mtime.sec or 0
end

-- LOW: Getting mtime here could be async

---@param item_buf integer
---@param preview_buf integer
---@return nil
local function update_preview_buf_version(item_buf, preview_buf)
    local src_changedtick = api.nvim_buf_get_changedtick(item_buf)
    api.nvim_buf_set_var(preview_buf, "src_changedtick", src_changedtick)
    local src_mtime = get_mtime(item_buf)
    api.nvim_buf_set_var(preview_buf, "src_mtime", src_mtime)
end

---@param ft string
---@return string|nil
local function get_parsable_lang(ft)
    local lang = vim.treesitter.language.get_lang(ft) or ft ---@type string
    if parsers[lang] == true then
        return lang
    end

    -- Credit fzflua for this method
    local has_v11 = fn.has("nvim-0.11")
    local has_parser = has_v11 == 1 and vim.treesitter.language.add(lang)
        or pcall(vim.treesitter.language.add, lang)

    -- FUTURE: Once v12 is out and below v11 compatibility is removed, ts_parsers[lang] can
    -- just be set to the first return of vim.treesitter.language.add
    if has_parser then
        parsers[lang] = true
        return lang
    else
        parsers[lang] = false
        return nil
    end
end

---@param item_buf integer
---@return string
local function get_item_buf_ft(item_buf)
    local item_ft = api.nvim_get_option_value("ft", { buf = item_buf }) ---@type string
    if item_ft ~= "" then
        return item_ft
    end

    local match_ft = vim.filetype.match({ buf = item_buf })
    return match_ft or ""
end

---@param item_buf integer
---@return integer
local function create_preview_buf_from_item(item_buf)
    local lines = get_item_buf_lines(item_buf)
    local preview_buf = api.nvim_create_buf(false, true)
    api.nvim_buf_set_lines(preview_buf, 0, 0, false, lines)
    setup_preview_buf(preview_buf)

    update_preview_buf_version(item_buf, preview_buf)

    local item_ft = get_item_buf_ft(item_buf)
    local lang = get_parsable_lang(item_ft)
    if lang then
        pcall(vim.treesitter.start, preview_buf, lang)
    else
        set_opt("syntax", item_ft, { buf = preview_buf })
    end

    return preview_buf
end

---@param preview_buf integer
---@param item table
---@return Range4
local function range_qf_to_zero_(preview_buf, item)
    local row_0 = ru._checked_row_to_row_0(item.lnum, preview_buf)
    local start_line = api.nvim_buf_get_lines(preview_buf, row_0, row_0 + 1, false)[1]
    local col = ru._qf_col_1_to_col(item.col, item.vcol, start_line)

    local end_lnum = math.max(item.lnum, item.end_lnum) ---@type integer
    local fin_row_0 = end_lnum ~= item.lnum and ru._checked_row_to_row_0(end_lnum, preview_buf)
        or row_0

    local fin_line = fin_row_0 == row_0 and start_line
        or api.nvim_buf_get_lines(preview_buf, fin_row_0, fin_row_0 + 1, false)[1]

    -- MID: Figure out why this actually works
    local fin_col_ = (function()
        if item.end_col <= 0 then
            return #fin_line
        end

        if item.vcol == 1 then
            return ru._vcol_to_end_col_(item.col, fin_line)
        end

        local end_idx_ = math.min(item.end_col - 1, #fin_line)
        if fin_row_0 == row_0 and end_idx_ == col then
            end_idx_ = end_idx_ + 1
        end

        return end_idx_
    end)()

    return { row_0, col, fin_row_0, fin_col_ }
end

---@param preview_buf integer
---@param item vim.quickfix.entry
---@return nil
local function set_err_range_extmark(preview_buf, item)
    local hl_range = range_qf_to_zero_(preview_buf, item)
    if not hl_range then
        if extmarks[preview_buf] then
            api.nvim_buf_del_extmark(preview_buf, hl_ns, extmarks[preview_buf])
        end

        return
    end

    extmarks[preview_buf] =
        api.nvim_buf_set_extmark(preview_buf, hl_ns, hl_range[1], hl_range[2], {
            hl_group = "QfRancherPreviewRange",
            id = extmarks[preview_buf],
            end_row = hl_range[3],
            end_col = hl_range[4],
            priority = 200,
            strict = false,
        })
end

-- LOW: If the changedtick is updated, update_preview_buf right away without checking mtime, then
-- update mtime async

---@param item vim.quickfix.entry
---@return integer
local function get_preview_buf(item)
    local item_buf = item.bufnr
    if (not item_buf) or not api.nvim_buf_is_valid(item_buf) then
        return create_fallback_buf()
    end

    local cache_buf = bufs[item_buf]
    if cache_buf then
        if not api.nvim_buf_is_valid(cache_buf) then
            return create_fallback_buf()
        end

        local src_changedtick = api.nvim_buf_get_changedtick(item_buf)
        local old_changedtick = vim.b[cache_buf].src_changedtick
        local changedtick_updated = src_changedtick ~= old_changedtick
        local src_mtime = get_mtime(item_buf)
        local old_mtime = vim.b[cache_buf].src_mtime
        local mtime_updated = src_mtime ~= old_mtime

        if changedtick_updated or mtime_updated then
            api.nvim_buf_set_var(cache_buf, "src_changedtick", src_changedtick)
            api.nvim_buf_set_var(cache_buf, "src_mtime", src_mtime)
            update_preview_buf(item_buf, cache_buf)
        end
    else
        cache_buf = create_preview_buf_from_item(item_buf)
        bufs[item_buf] = cache_buf
    end

    set_err_range_extmark(cache_buf, item)

    return bufs[item_buf]
end

---@param debounce integer|nil
---@param cb function
---@return nil
local function start_timer(debounce, cb)
    debounce = debounce or 100
    timer = timer or uv.new_timer()
    if timer then
        timer:start(debounce, 0, cb)
    end
end

---@param debounce integer|nil
---@return nil
local function update_preview_win_buf(debounce)
    if timer and timer:get_due_in() > 0 then
        queued_update = true
        return
    end

    local is_open = win_state:is_open()
    if not is_open then
        return
    end

    local cur_win = api.nvim_get_current_win()
    if cur_win ~= win_state.list_win then
        return
    end

    local wintype = fn.win_gettype(win_state.list_win)
    local src_win = wintype == "loclist" and win_state.list_win or nil
    local ok, entry, hl = ru._only_get_item_under_cursor(src_win)
    if (not ok) or type(entry) == "string" then
        ru._echo(false, entry, hl)
        return
    end

    local preview_buf = get_preview_buf(entry)
    api.nvim_win_set_buf(win_state.preview_win, preview_buf)

    local cur_config = api.nvim_win_get_config(win_state.preview_win)
    local opts = {} ---@type qf-rancher.preview.OpenOpts
    opts.border = cur_config.border
    opts.title_pos = cur_config.title_pos

    local title_config = get_title_config(entry.bufnr, opts)
    api.nvim_win_set_config(win_state.preview_win, title_config)

    local cur_pos = ru._qf_pos_to_cur_pos(entry.lnum, entry.col, entry.vcol, entry.bufnr)
    ru._protected_set_cursor(win_state.preview_win, cur_pos)
    ru._do_zzze(win_state.preview_win, true)

    start_timer(debounce, function()
        if queued_update then
            queued_update = false
            vim.schedule(update_preview_win_buf)
        end

        checked_stop_timer()
    end)
end

---@param debounce integer|nil
---@return nil
local function create_autocmds(debounce)
    if #api.nvim_get_autocmds({ group = group }) > 0 then
        return
    end

    local list_win_buf = api.nvim_win_get_buf(win_state.list_win)

    api.nvim_create_autocmd({ "CursorMoved", "QuickFixCmdPost" }, {
        group = group,
        buffer = list_win_buf,
        callback = function()
            update_preview_win_pos()
            update_preview_win_buf(debounce)
        end,
    })

    api.nvim_create_autocmd("BufLeave", {
        group = group,
        buffer = list_win_buf,
        callback = function()
            close_preview_win()
            checked_clear_when_idle()
        end,
    })

    api.nvim_create_autocmd("WinClosed", {
        group = group,
        callback = function()
            checked_clear_when_idle()
        end,
    })

    -- Account for situations where WinLeave does not fire properly
    api.nvim_create_autocmd("WinEnter", {
        group = group,
        callback = function()
            local cur_win = api.nvim_get_current_win()
            if cur_win ~= win_state.list_win then
                close_preview_win()
            end
        end,
    })

    api.nvim_create_autocmd("WinLeave", {
        group = group,
        callback = function()
            local cur_win = api.nvim_get_current_win()
            if cur_win == win_state.list_win then
                close_preview_win()
            end
        end,
    })

    api.nvim_create_autocmd("WinResized", {
        group = group,
        callback = function()
            update_preview_win_pos()
        end,
    })
end

---@param preview_win integer
---@return nil
local function set_preview_win_opts(preview_win)
    set_opt("cc", "", { win = preview_win })
    set_opt("cul", true, { win = preview_win })

    set_opt("fdc", "0", { win = preview_win })
    set_opt("fdm", "manual", { win = preview_win })

    set_opt("list", false, { win = preview_win })

    set_opt("nu", true, { win = preview_win })
    set_opt("rnu", false, { win = preview_win })
    set_opt("scl", "no", { win = preview_win })
    set_opt("stc", "", { win = preview_win })

    set_opt("spell", false, { win = preview_win })

    set_opt("so", WIN_SCROLLOFF, { win = preview_win })
    set_opt("siso", WIN_SCROLLOFF, { win = preview_win })
end

---@param win_cfg vim.api.keyset.win_config
---@param preview_buf integer
---@return integer
local function create_preview_win(win_cfg, preview_buf)
    local preview_win = api.nvim_open_win(preview_buf, false, win_cfg) ---@type integer
    set_preview_win_opts(preview_win)

    return preview_win
end

---@param opts qf-rancher.preview.OpenOpts
---@return nil
local function validate_open_opts(opts)
    vim.validate("opts", opts, "table")

    ry._validate_uint(opts.debounce, true)
    ry._validate_title_pos(opts.title_pos, true)
    ry._validate_border(opts.border, true)
    -- ry._validate_title(opts._title, true)
end

---@param list_win integer List window context
---@param opts qf-rancher.preview.OpenOpts
---@return integer|nil
local function open_preview_win(list_win, opts)
    local wintype = fn.win_gettype(list_win)
    local src_win = wintype == "loclist" and list_win or nil
    local ok, entry, hl = ru._only_get_item_under_cursor(src_win)
    if (not ok) or type(entry) == "string" then
        ru._echo(false, entry, hl)
        return nil
    end

    local preview_buf = get_preview_buf(entry)
    local win_config = create_win_cfg(list_win, entry.bufnr, opts)
    local preview_win = create_preview_win(win_config, preview_buf)
    win_state:set(list_win, preview_win)

    local cur_pos = ru._qf_pos_to_cur_pos(entry.lnum, entry.col, entry.vcol, entry.bufnr)
    ru._protected_set_cursor(win_state.preview_win, cur_pos)
    ru._do_zzze(win_state.preview_win, true)
    create_autocmds(opts.debounce)

    start_timer(opts.debounce, function()
        if queued_update then
            queued_update = false
            vim.schedule(update_preview_win_buf)
        end

        checked_stop_timer()
    end)

    return preview_win
end

---@mod Preview Preview List Items
---@tag qf-rancher-preview
---@tag qfr-preview
---@brief [[
---
---@brief ]]
---
---@brief [[
---Highlight group: "QfRancherPreviewRange"
---Highlights the lnum/col range of the entry. Default link to |hl-CurSearch|
---]]

--- @class QfRancherPreview
local Preview = {}

---Re-snap the preview window to the list
---@return nil
function Preview.update_preview_win_pos()
    update_preview_win_pos()
end

-- LOW: Option to disable autocmds
-- LOW: Make the min/max window dimensions configurable
-- MAYBE: Add a list_win opt if this function needs to be used outside the window context it
-- will be opened in.
-- MAYBE: Add a silent opt

---@class qf-rancher.preview.OpenOpts
---
---(Default 100) Minimum interval in ms between preview
---window updates The default is 100 to accommodate slower
---systems/HDs. On a reasonable system, it should be
---possible to go down to 50ms before flicker/stutter start
---to appear. This behavior also depends on the size of
---the file(s) being scrolled through
---
---@field debounce? integer Buffer between preview buffer loads
---
---@field border? qf-rancher.types.Border|string[] See |'winborder'|
---@field title_pos? 'left'|'center'|'right' See |api-win_config|
---
---@field package _title? string|[string,string|integer?][]

---Open the preview window. Does nothing if the preview window is already
---open
---
---If opts.border is not provided, winborder will be used if it is not "". If
---winborder cannot be used as a fallback, "single" will be used
---
---If title_pos is nil, the window title will not be shown
---
---@param opts? qf-rancher.preview.OpenOpts
---@return integer|nil Preview |winid| if it was opened
function Preview.open_preview_win(opts)
    opts = opts or {}
    validate_open_opts(opts)

    local list_win = api.nvim_get_current_win()
    local win_buf = api.nvim_win_get_buf(list_win)
    local bt = api.nvim_get_option_value("bt", { buf = win_buf })
    if bt ~= "quickfix" then
        api.nvim_echo({ { "Current window is not an error list" } }, false, {})
        return nil
    end

    if win_state:is_open() then
        return nil
    end

    open_preview_win(list_win, opts)
end

---Close the preview window
---@return nil
function Preview.close_preview_win()
    close_preview_win()
end

---Toggle the preview window
---
---If the preview window is open in another list, move it to the current one
---
---@param opts? qf-rancher.preview.OpenOpts See |qf-rancher.preview.OpenOpts|
---@return integer|nil Preview |winid| if it was opened
function Preview.toggle_preview_win(opts)
    opts = opts or {}
    validate_open_opts(opts)

    local list_win = api.nvim_get_current_win()
    local win_buf = api.nvim_win_get_buf(list_win)
    local bt = api.nvim_get_option_value("bt", { buf = win_buf })
    if bt ~= "quickfix" then
        api.nvim_echo({ { "Current window is not an error list" } }, false, {})
        return nil
    end

    local started_open = win_state:is_open()
    local start_list_win = win_state.list_win
    if started_open then
        close_preview_win()
    end

    if started_open and list_win == start_list_win then
        return nil
    else
        return open_preview_win(list_win, opts)
    end
end

return Preview

---@export Preview

-- MID: Instead of storing preview state in the module, store as w:vars on list wins.
-- Challenges:
-- - How to handle maps since those are buffer local
-- - More iterative searching through w:vars (do not want to get into caching list wins)
-- - Possible changes to autocmd and buf cache handling
-- Advantages:
-- - Makes preview window state part of editor context, visible to the user and the whole plugin
-- - Data is still scoped to the list win
-- - De-couples data. Leverage point to further decoupling, which leads to more customization and
-- easier development
-- - Allows for scoping of open preview wins, such as having one per tabpage
-- MID: Checked Qf position conversion is done twice, once for the extmark and once for the
-- cursor. The checked conversion should only be done once, then just use arithmetic for the other
-- MID: Add an option for auto-showing the preview window. Unsure if this should be on by default
-- MID: The user should be able to set a custom title for the preview win

-- LOW: Add scrolling to preview win
-- - See https://github.com/bfrg/vim-qf-preview for relevant keymap controls
-- - bqf also has some interesting controls for preview wins
-- - Can also look at blink-cmp for how to make it work
-- LOW: Possibly re-create the public API to update_preview_win_buf

-- PR: in win_config:
-- - border does not contain bold
-- - title is not correct (any instead of string|[string,string|integer?][])
-- If doing a PR for these, double check that my annotation for title is correct. Also, check and
-- see if anything else is incorrect.
-- Also see if the type annotation is written in the C code or something, rather than having to
-- submit an issue for type annotations
-- PR: Kind of a long-shot feature request, but window local autocmds.
