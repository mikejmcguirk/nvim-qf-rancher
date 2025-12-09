---@class QfrUtil
local M = {}

local rt = Qfr_Defer_Require("qf-rancher.tools") ---@type QfrTools
local ry = Qfr_Defer_Require("qf-rancher.types") ---@type QfrTypes

local api = vim.api
local fn = vim.fn

-- ===============
-- == CMD UTILS ==
-- ===============

---@param fargs string[]
---@return string|nil
function M._find_pattern_in_cmd(fargs)
    ry._validate_list(fargs, { type = "string" })

    for _, arg in ipairs(fargs) do
        if vim.startswith(arg, "/") then
            return string.sub(arg, 2) or ""
        end
    end

    return nil
end

---@param fargs string[]
---@param valid_args string[]
---@param default string
function M._check_cmd_arg(fargs, valid_args, default)
    ry._validate_list(fargs, { type = "string" })
    ry._validate_list(valid_args, { type = "string" })
    vim.validate("default", default, "string")

    for _, arg in ipairs(fargs) do
        if vim.tbl_contains(valid_args, arg) then
            return arg
        end
    end

    return default
end

-- =================
-- == INPUT UTILS ==
-- =================

---@param input QfrInputType
---@return string
---NOTE: This function assumes that an API input of "vimcase" has already been resolved
function M._get_display_input_type(input)
    if input == "regex" then
        return "Regex"
    elseif input == "sensitive" then
        return "Case Sensitive"
    elseif input == "smartcase" then
        return "Smartcase"
    else
        return "Case Insensitive"
    end
end

---@param input QfrInputType
---@return QfrInputType
function M._resolve_input_vimcase(input)
    ry._validate_input_type(input)

    if input ~= "vimcase" then
        return input
    end

    local ignorecase = api.nvim_get_option_value("ignorecase", { scope = "global" })
    local smartcase = api.nvim_get_option_value("smartcase", { scope = "global" })

    if ignorecase and smartcase then
        return "smartcase"
    end

    if ignorecase then
        return "insensitive"
    end

    return "sensitive"
end

-- MID: This should pass up the echo chunks rather than doing so here
-- - You could then pass up errors if there is a bad mode rather than creating an enter error
--   with vim.validate. But extui might make that irrelevant
-- MID: An empty selection is not an error and should not be treated as such
-- - Issue: Leaving visual mode after a valid selection is handled here. Do we want to do that if
--   the selection is empty?
---@param mode string
---@return string|nil
local function get_visual_pattern(mode)
    vim.validate("mode", mode, "string")
    vim.validate("mode", mode, function()
        return mode == "v" or mode == "V" or mode == "\22"
    end)

    local start_pos = fn.getpos(".") ---@type [integer, integer, integer, integer]
    local end_pos = fn.getpos("v") ---@type [integer, integer, integer, integer]
    local region = fn.getregion(start_pos, end_pos, { type = mode }) ---@type string[]
    if #region == 1 then
        local trimmed = region[1]:gsub("^%s*(.-)%s*$", "%1") ---@type string
        if #trimmed > 0 then
            api.nvim_cmd({ cmd = "normal", args = { "\27" }, bang = true }, {})
            return trimmed
        end
    elseif #region > 1 then
        for _, line in ipairs(region) do
            if line ~= "" then
                api.nvim_cmd({ cmd = "normal", args = { "\27" }, bang = true }, {})
                return table.concat(region, "\n")
            end
        end
    end

    api.nvim_echo({ { "get_visual_pattern: Empty selection", "" } }, false, {})
    return nil
end

-- MID: Should be ok, err pattern
---@param prompt string
---@return string|nil
local function get_input(prompt)
    vim.validate("prompt", prompt, "string")

    ---@type boolean, string
    local ok, pattern = pcall(fn.input, { prompt = prompt, cancelreturn = "" })
    if ok then
        return pattern
    end

    if pattern == "Keyboard interrupt" then
        return nil
    end

    local chunk = { (pattern or "Unknown error getting input"), "ErrorMsg" } ---@type string[]
    api.nvim_echo({ chunk }, true, { err = true })
    return nil
end

-- TODO: Deprecate
---@param prompt string
---@param input_pattern string|nil
---@param input_type QfrInputType
---@return string|nil
function M._resolve_pattern(prompt, input_pattern, input_type)
    vim.validate("prompt", prompt, "string")
    vim.validate("input_pattern", input_pattern, "string", true)
    ry._validate_input_type(input_type)

    if input_pattern then
        return input_pattern
    end

    local mode = string.sub(api.nvim_get_mode().mode, 1, 1) ---@type string
    local is_visual = mode == "v" or mode == "V" or mode == "\22" ---@type boolean
    if is_visual then
        return get_visual_pattern(mode)
    end

    local pattern = get_input(prompt) ---@type string|nil
    return (pattern and input_type == "insensitive") and string.lower(pattern) or pattern
end

---@param short_mode string
---@return string|nil
function M._get_visual_pattern(short_mode)
    return get_visual_pattern(short_mode)
end

---@param prompt string
---@param case QfrCase
---@param regex boolean
---@return string|nil
function M._get_input(prompt, case, regex)
    if vim.g.qfr_debug_assertions then
        vim.validate("prompt", prompt, "string")
        vim.validate("case", case, "string")
        vim.validate("regex", regex, "boolean")
    end

    local pattern = get_input(prompt) ---@type string|nil
    if not pattern then
        return nil
    end

    if case == "sensitive" then
        return pattern
    end

    local lower_pattern = string.lower(pattern) ---@type string
    if case == "smartcase" and pattern ~= lower_pattern then
        return pattern
    end

    return lower_pattern
end

------------------------
-- WRAPPING IDX FUNCS --
------------------------

---@param src_win integer|nil
---@param count integer
---@param wrapping_math function
---@return integer|nil
local function get_wrapping_idx(src_win, count, wrapping_math)
    ry._validate_win(src_win, true)
    ry._validate_uint(count)
    vim.validate("arithmetic", wrapping_math, "callable")

    local count1 = math.max(count, 1) ---@type integer
    local size = rt._get_list(src_win, { nr = 0, size = 0 }).size ---@type integer
    if size < 1 then
        api.nvim_echo({ { "E42: No Errors", "" } }, false, {})
        return nil
    end

    local cur_idx = rt._get_list(src_win, { nr = 0, idx = 0 }).idx ---@type integer
    if cur_idx < 1 then
        return nil
    end

    return wrapping_math(cur_idx, count1, 1, size)
end

---@param x integer
---@param y integer
---@param min integer
---@param max integer
---@return integer
function M._wrapping_add(x, y, min, max)
    local period = max - min + 1 ---@type integer
    return ((x - min + y) % period) + min
end

---@param x integer
---@param y integer
---@param min integer
---@param max integer
---@return integer
function M._wrapping_sub(x, y, min, max)
    local period = max - min + 1 ---@type integer
    return ((x - y - min) % period) + min
end

---@param src_win integer|nil
---@param count integer
---@return integer|nil
function M._get_idx_wrapping_sub(src_win, count)
    return get_wrapping_idx(src_win, count, M._wrapping_sub)
end

---@param src_win integer|nil
---@param count integer
---@return integer|nil
function M._get_idx_wrapping_add(src_win, count)
    return get_wrapping_idx(src_win, count, M._wrapping_add)
end

---------------------------
-- LIST IDX GETTER FUNCS --
---------------------------

-- TODO: These functions are bad because they mash up the idx finding and the item getting. Need
-- to be de-composed down

---@param src_win integer|nil
---@param idx integer
---@return vim.quickfix.entry|nil, integer|nil
local function get_item(src_win, idx)
    ry._validate_win(src_win, true)
    ry._validate_uint(idx)

    ---@type vim.quickfix.entry[]
    local items = rt._get_list(src_win, { nr = 0, idx = idx, items = true }).items
    if #items < 1 then
        return nil, nil
    end

    local item = items[1] ---@type vim.quickfix.entry
    if item.bufnr and api.nvim_buf_is_valid(item.bufnr) then
        return item, idx
    end

    api.nvim_echo({ { "List item bufnr is invalid", "ErrorMsg" } }, true, { err = true })
    return nil, nil
end

---@type QfrGetItemFunc
function M._get_item_under_cursor(src_win)
    return get_item(src_win, fn.line("."))
end

---@type QfrGetItemFunc
function M._get_item_wrapping_sub(src_win)
    local idx = M._get_idx_wrapping_sub(src_win, vim.v.count)
    if not idx then
        return nil, nil
    end

    return get_item(src_win, idx)
end

---@type QfrGetItemFunc
function M._get_item_wrapping_add(src_win)
    local idx = M._get_idx_wrapping_add(src_win, vim.v.count)
    if not idx then
        return nil, nil
    end

    return get_item(src_win, idx)
end

-------------------------
-- OPENING AND CLOSING --
-------------------------

---@param win integer
---@param cur_pos {[1]: integer, [2]: integer}
---@return nil
function M._protected_set_cursor(win, cur_pos)
    if vim.g.qfr_debug_assertions then
        ry._validate_win(win)
        ry._validate_cur_pos(cur_pos)
    end

    local buf = api.nvim_win_get_buf(win) ---@type integer

    local cursor_row = math.max(cur_pos[1], 1) ---@type integer
    local line_count = api.nvim_buf_line_count(buf) ---@type integer
    local row = math.min(cursor_row, line_count) ---@type integer

    local set_line = api.nvim_buf_get_lines(buf, row - 1, row, false)[1] ---@type string
    local set_line_len_0 = math.max(#set_line - 1, 0) ---@type integer
    local col = math.min(cur_pos[2], set_line_len_0) ---@type integer

    api.nvim_win_set_cursor(win, { row, col })
end

---@param win integer
---@param force boolean
---@return integer
function M._pwin_close(win, force)
    ry._validate_uint(win)
    vim.validate("force", force, "boolean")

    if not api.nvim_win_is_valid(win) then
        return -1
    end

    local tabpages = api.nvim_list_tabpages() ---@type integer[]
    local win_tabpage = api.nvim_win_get_tabpage(win) ---@type integer
    local win_tabpage_wins = api.nvim_tabpage_list_wins(win_tabpage) ---@type integer[]
    local buf = api.nvim_win_get_buf(win) ---@type integer
    if #tabpages == 1 and #win_tabpage_wins == 1 then
        return buf
    end

    local ok, _ = pcall(api.nvim_win_close, win, force) ---@type boolean, nil
    return ok and buf or -1
end

-- FUTURE: https://github.com/neovim/neovim/pull/33402
-- Redo this once this issue is resolved. Be sure to use has() for compatibility

-- Return an integer to stay consistent with pwin_close

---@param buf integer
---@param force boolean
---@param wipeout boolean
---@return integer
function M._pbuf_rm(buf, force, wipeout)
    ry._validate_uint(buf)
    vim.validate("force", force, "boolean")
    vim.validate("wipeout", wipeout, "boolean")

    if not api.nvim_buf_is_valid(buf) then
        return -1
    end

    local modifiable = api.nvim_get_option_value("modifiable", { buf = buf }) ---@type boolean
    if modifiable then
        api.nvim_buf_call(buf, function()
            ---@diagnostic disable-next-line: missing-fields
            api.nvim_cmd({ cmd = "update", mods = { silent = true } }, {})
        end)
    end

    if not wipeout then
        api.nvim_set_option_value("buflisted", false, { buf = buf })
    end

    local delete_opts = wipeout and { force = force } or { force = force, unload = true }
    local ok, _ = pcall(api.nvim_buf_delete, buf, delete_opts)
    return ok and 0 or -1
end

-- MAYBE: Additional validation, checking, and error messaging could be added here around if the
-- buf is the list one listed. But, since this is currently only used for deleting list wins, will
-- opt for simplicity

---@param win integer
---@param force boolean
---@param wipeout boolean
---@return integer
function M._pclose_and_rm(win, force, wipeout)
    local buf = M._pwin_close(win, force)
    if buf > 0 then
        -- MAYBE: Do when idle
        vim.schedule(function()
            if #fn.win_findbuf(buf) == 0 then
                M._pbuf_rm(buf, force, wipeout)
            end
        end)
    end

    return buf
end

---@param buf integer
---@param win integer
---@return nil
--- See :h help-buffer-options
--- NOTE: While the source is based on help buffers and their options, Vim's help model can be more
--- accurately understood as creating help *windows*. Thus, options are set at Window rather than
--- local scope. And this function should not be called for bufs/wins expected to be used normally
local function prep_help_buf(buf, win)
    if vim.g.qfr_debug_assertions then
        ry._validate_buf(buf)
        ry._validate_win(win)
    end

    api.nvim_set_option_value("bin", false, { buf = buf })
    api.nvim_set_option_value("bl", false, { buf = buf })
    api.nvim_set_option_value("isk", '!-~,^*,^|,^",192-255', { buf = buf })
    api.nvim_set_option_value("ma", false, { buf = buf })
    api.nvim_set_option_value("ts", 8, { buf = buf })

    api.nvim_set_option_value("arabic", false, { win = win })
    api.nvim_set_option_value("crb", false, { win = win })
    api.nvim_set_option_value("diff", false, { win = win })
    api.nvim_set_option_value("fen", false, { win = win })
    api.nvim_set_option_value("fdm", "manual", { win = win })
    api.nvim_set_option_value("list", false, { win = win })
    api.nvim_set_option_value("nu", false, { win = win })
    api.nvim_set_option_value("rl", false, { win = win })
    api.nvim_set_option_value("rnu", false, { win = win })
    api.nvim_set_option_value("scb", false, { win = win })
    api.nvim_set_option_value("spell", false, { win = win })

    api.nvim_set_option_value("bt", "help", { buf = buf })
    -- NOTE: Do not manually set filetype. Causes ftplugin files to work improperly
end

---@param item vim.quickfix.entry
---@param opts QfrBufOpenOpts
---@return boolean
function M._open_item(item, win, opts)
    if vim.g.qfr_debug_assertions then
        ry._validate_list_item(item)
        ry._validate_win(win)
        ry._validate_open_buf_opts(opts)
    end

    local buf = item.bufnr ---@type integer|nil
    if not (buf and api.nvim_buf_is_valid(buf)) then
        return false
    end

    local already_open = api.nvim_win_get_buf(win) == buf ---@type boolean
    if not already_open then
        if opts.buftype == "help" then
            prep_help_buf(buf, win)
        else
            api.nvim_set_option_value("bl", true, { buf = buf })
        end

        api.nvim_win_call(win, function()
            -- This loads the buf if necessary. Do not use bufload
            -- Have seen in FzfLua's docs that they've had problems with nvim_win_set_buf causing
            -- focus to change. win_call set_current_buf instead
            api.nvim_set_current_buf(buf)
            if opts.clearjumps then
                api.nvim_cmd({ cmd = "clearjumps" }, {})
            end
        end)
    end

    if not opts.skip_set_cur_pos then
        if already_open then
            api.nvim_buf_call(buf, function()
                api.nvim_cmd({ cmd = "normal", args = { "m'" }, bang = true }, {})
            end)
        end

        M._protected_set_cursor(win, M._qf_pos_to_cur_pos(item.lnum, item.col))
    end

    if not opts.skip_zzze then
        M._do_zzze(win)
    end

    api.nvim_win_call(win, function()
        api.nvim_cmd({ cmd = "normal", args = { "zv" }, bang = true }, {})
    end)

    if opts.focus then
        api.nvim_set_current_win(win)
    end

    return true
end

---@param win integer
---@param always? boolean
---@return nil
function M._do_zzze(win, always)
    ry._validate_win(win)

    if not (vim.g.qfr_auto_center or always) then
        return
    end

    api.nvim_win_call(win, function()
        api.nvim_cmd({ cmd = "normal", args = { "zz" }, bang = true }, {})
        api.nvim_cmd({ cmd = "normal", args = { "ze" }, bang = true }, {})
    end)
end

----------------------
-- POSITION HELPERS --
----------------------

-- PR: Why can't this be a part of Nvim core?
-- MID: This could be a binary search instead

---@param vcol integer
---@param line string
---@return boolean, integer, integer
function M._vcol_to_byte_bounds(vcol, line)
    ry._validate_uint(vcol)
    vim.validate("line", line, "string")

    if vcol == 0 or #line <= 1 then
        return true, 0, 0
    end

    local max_vcol = fn.strdisplaywidth(line) ---@type integer
    if vcol > max_vcol then
        return false, 0, 0
    end

    local charlen = fn.strcharlen(line) ---@type integer
    for char_idx = 0, charlen - 1 do
        local start_byte = fn.byteidx(line, char_idx) ---@type integer
        if start_byte == -1 then
            return false, 0, 0
        end

        local char = fn.strcharpart(line, char_idx, 1, true) ---@type string
        local fin_byte = start_byte + #char - 1 ---@type integer

        local test_str = line:sub(1, fin_byte + 1) ---@type string
        local test_vcol = fn.strdisplaywidth(test_str) ---@type integer
        if test_vcol >= vcol then
            return true, start_byte, fin_byte
        end
    end

    return false, 0, 0
end

---@param vcol integer
---@param line string
---@return integer
function M._vcol_to_end_col_(vcol, line)
    ry._validate_uint(vcol) ---@type QfrTypes
    vim.validate("line", line, "string")

    local ok, _, fin_byte = M._vcol_to_byte_bounds(vcol, line) ---@type boolean, integer
    if ok then
        return math.min(fin_byte + 1, #line)
    else
        return #line
    end
end

-- NOTE: Handle all validation here with built-ins to avoid looping code

---@param item_lnum integer
---@param item_col integer
---@return {[1]:integer, [2]:integer}
function M._qf_pos_to_cur_pos(item_lnum, item_col)
    local row = math.max(item_lnum, 1) ---@type integer
    local col = item_col - 1 ---@type integer
    col = math.max(col, 0)

    return { row, col }
end

-- ====================
-- == WINDOW FINDING ==
-- ====================

-- TODO: This data construct is bad. Everywhere it's used can just be a list of tabpages

---@param opts QfrTabpageOpts
---@return integer[]
function M._resolve_tabpages(opts)
    ry._validate_tabpage_opts(opts)

    if opts.all_tabpages then
        return api.nvim_list_tabpages()
    elseif opts.tabpages then
        return opts.tabpages
    elseif opts.tabpage then
        return { opts.tabpage }
    else
        return { api.nvim_get_current_tabpage() }
    end
end

-- NOTE: If searching for wins by qf_id, passing a zero id is allowed so
-- that orphans can be checked

---@param qf_id integer
---@param opts QfrTabpageOpts
---@return integer|nil
function M._get_loclist_win_by_qf_id(qf_id, opts)
    ry._validate_uint(qf_id)
    ry._validate_tabpage_opts(opts)

    local tabpages = M._resolve_tabpages(opts) ---@type integer[]
    for _, tabpage in ipairs(tabpages) do
        local tabpage_wins = api.nvim_tabpage_list_wins(tabpage) ---@type integer[]
        for _, t_win in ipairs(tabpage_wins) do
            local t_win_qf_id = fn.getloclist(t_win, { id = 0 }).id ---@type integer
            if t_win_qf_id == qf_id then
                local wintype = fn.win_gettype(t_win)
                if wintype == "loclist" then
                    return t_win
                end
            end
        end
    end

    return nil
end

---@param win integer
---@param opts QfrTabpageOpts
---@return integer[]
function M._get_loclist_wins_by_win(win, opts)
    ry._validate_win(win, false)

    local qf_id = fn.getloclist(win, { id = 0 }).id ---@type integer
    if qf_id == 0 then
        return {}
    end

    return M._get_ll_wins_by_qf_id(qf_id, opts)
end

---@param qf_id integer
---@param opts QfrTabpageOpts
---@return integer[]
function M._get_ll_wins_by_qf_id(qf_id, opts)
    ry._validate_uint(qf_id)
    ry._validate_tabpage_opts(opts)

    local wins = {} ---@type integer[]
    local tabpages = M._resolve_tabpages(opts) ---@type integer[]
    for _, tabpage in ipairs(tabpages) do
        local tabpage_wins = api.nvim_tabpage_list_wins(tabpage) ---@type integer[]
        for _, t_win in ipairs(tabpage_wins) do
            local t_win_qf_id = fn.getloclist(t_win, { id = 0 }).id ---@type integer
            if t_win_qf_id == qf_id then
                local wintype = fn.win_gettype(t_win)
                if wintype == "loclist" then
                    table.insert(wins, t_win)
                end
            end
        end
    end

    return wins
end

---@param opts QfrTabpageOpts
---@return integer[]
function M._get_all_loclist_wins(opts)
    local ll_wins = {} ---@type integer[]
    local tabpages = M._resolve_tabpages(opts) ---@type integer[]

    for _, tabpage in ipairs(tabpages) do
        local tabpage_wins = api.nvim_tabpage_list_wins(tabpage) ---@type integer[]
        for _, win in ipairs(tabpage_wins) do
            local wintype = fn.win_gettype(win)
            if wintype == "loclist" then
                table.insert(ll_wins, win)
            end
        end
    end

    return ll_wins
end

---@param opts QfrTabpageOpts
---@return integer[]
function M._get_qf_wins(opts)
    local wins = {} ---@type integer[]
    local tabpages = M._resolve_tabpages(opts) ---@type integer[]

    for _, tabpage in ipairs(tabpages) do
        local tabpage_wins = api.nvim_tabpage_list_wins(tabpage) ---@type integer[]
        for _, t_win in ipairs(tabpage_wins) do
            local wintype = fn.win_gettype(t_win)
            if wintype == "quickfix" then
                table.insert(wins, t_win)
            end
        end
    end

    return wins
end

---@param opts QfrTabpageOpts
---@return integer|nil
function M._get_qf_win(opts)
    local tabpages = M._resolve_tabpages(opts) ---@type integer[]

    for _, tabpage in ipairs(tabpages) do
        local tabpage_wins = api.nvim_tabpage_list_wins(tabpage) ---@type integer[]
        for _, t_win in ipairs(tabpage_wins) do
            local wintype = fn.win_gettype(t_win)
            if wintype == "quickfix" then
                return t_win
            end
        end
    end

    return nil
end

---@param list_win integer
---@param opts QfrTabpageOpts
---@return integer|nil
function M._find_loclist_origin(list_win, opts)
    ry._validate_list_win(list_win)

    local qf_id = fn.getloclist(list_win, { id = 0 }).id ---@type integer
    if qf_id == 0 then
        return nil
    end

    local tabpages = M._resolve_tabpages(opts) ---@type integer[]
    for _, tabpage in ipairs(tabpages) do
        local tabpage_wins = api.nvim_tabpage_list_wins(tabpage) ---@type integer[]
        for _, win in ipairs(tabpage_wins) do
            local win_qf_id = fn.getloclist(win, { id = 0 }).id ---@type integer
            local win_wintype = fn.win_gettype(win)
            if win_qf_id == qf_id and win_wintype == "" then
                return win
            end
        end
    end

    return nil
end

-- MID: Bad function naming
---@param win integer
---@param todo function
---@return any
function M._locwin_check(win, todo)
    ry._validate_win(win, false)

    local qf_id = fn.getloclist(win, { id = 0 }).id ---@type integer
    if qf_id == 0 then
        api.nvim_echo({ { "Current window has no location list", "" } }, false, {})
        return
    end

    return todo()
end

-- MID: Error should not be printed here
-- MID: Why would this function be able to accept a nil win at all? Feels like something the
-- caller should handle
---@param win integer
---@return boolean
function M._is_valid_loclist_win(win)
    ry._validate_win(win, true)
    if not win then
        return false
    end

    local wintype = fn.win_gettype(win)
    if wintype == "" or wintype == "loclist" then
        return true
    end

    ---@type string
    local text = "Window " .. win .. " with type " .. wintype .. " cannot contain a location list"
    api.nvim_echo({ { text, "ErrorMsg" } }, true, { err = true })
    return false
end

return M
