-- Escaping test line from From vim-grepper
-- ..ad\\f40+$':-# @=,!;%^&&*()_{}/ /4304\'""?`9$343%$ ^adfadf[ad)[(

local gl = Qfr_Defer_Require("qf-rancher.lib.grep_locs") ---@type qf-rancher.lib.GrepLocs
local re = Qfr_Defer_Require("qf-rancher.system") ---@type qf-rancher.System
local rt = Qfr_Defer_Require("qf-rancher.tools") ---@type qf-rancher.Tools
local ru = Qfr_Defer_Require("qf-rancher.util") ---@type qf-rancher.Util
local ry = Qfr_Defer_Require("qf-rancher.types") ---@type qf-rancher.Types

local api = vim.api
local fn = vim.fn

---@mod Grep Grep items into the list
---@tag qf-rancher-grep
---@tag qfr-grep
---@brief [[
---
---@brief ]]

--- @class qf-rancher.Grep
local Grep = {}

local base_parts = {
    rg = { "rg", "--vimgrep", "-uu" },
    grep = { "grep", "--recursive", "--with-filename", "--line-number", "-I" },
} ---@type table<string, string[]>

-- MID: Would be cool in the future to have an interface to add these
--- Fields:
--- - string pattern
--- - string See |QfrInputType|
--- - boolean Use regex
--- - QfrGrepLocs Locations to grep from
--- Returns: string[]
--- @alias QfrGrepPartsFunc fun(string, string, boolean, QfrGrepLocs):string[]

---@type QfrGrepPartsFunc
local function get_full_parts_rg(pattern, case, regex, locations)
    local cmd = vim.deepcopy(base_parts.rg, true) ---@type string[]

    if fn.has("win32") == 1 then
        cmd[#cmd + 1] = "--crlf"
    end

    if case == "smartcase" then
        cmd[#cmd + 1] = "--smart-case" -- or "-S"
    elseif case == "insensitive" then
        cmd[#cmd + 1] = "--ignore-case" -- or "-i"
    end

    if not regex then
        cmd[#cmd + 1] = "--fixed-strings" -- or "-F"
    end

    if string.find(pattern, "\n", 1, true) ~= nil then
        cmd[#cmd + 1] = "--multiline" -- or "-U"
    end

    cmd[#cmd + 1] = "--"
    cmd[#cmd + 1] = pattern
    vim.list_extend(cmd, locations)

    return cmd
end

---@type QfrGrepPartsFunc
local function get_full_parts_grep(pattern, case, regex, locations)
    local cmd = vim.deepcopy(base_parts.grep) ---@type string[]

    if regex then
        cmd[#cmd + 1] = "--extended-regexp" -- or "-E"
    else
        cmd[#cmd + 1] = "--fixed-strings" -- or "-F"
    end

    if case == "smartcase" or case == "insensitive" then
        cmd[#cmd + 1] = "--ignore-case" -- or "-i"
    end

    cmd[#cmd + 1] = "--"
    -- No multiline mode in vanilla grep, so fall back to or comparison
    local sub_pattern = string.gsub(pattern, "\n", "|")
    cmd[#cmd + 1] = sub_pattern
    vim.list_extend(cmd, locations)

    return cmd
end

local get_full_parts = {
    grep = get_full_parts_grep,
    rg = get_full_parts_rg,
} ---@type table<string, function>

---@param grep_opts QfrGrepOpts
---@return nil
local function validate_grep_opts(grep_opts)
    vim.validate("grep_opts", grep_opts, "table", true)
    if type(grep_opts) == "nil" then
        return
    end

    ry._validate_case(grep_opts.case, true)
    vim.validate("grep_opts.regex", grep_opts.regex, "boolean", true)
    vim.validate("grep_opts.name", grep_opts.name, "string", true)
    vim.validate("grep_opts.pattern", grep_opts.pattern, "string", true)

    if type(grep_opts.locations) == "nil" then
        return
    elseif type(grep_opts.locations) == "table" then
        ---@diagnostic disable-next-line: param-type-mismatch
        ry._validate_list(grep_opts.locations, { item_type = "string" })
    else
        vim.validate("grep_opts.locations", grep_opts.locations, "function")
    end
end

---@param grep_opts QfrGrepOpts
---@return nil
local function populate_grep_opts(grep_opts)
    grep_opts.case = grep_opts.case or "vimcase"
    if type(grep_opts.regex) == "nil" then
        grep_opts.regex = false
    end

    grep_opts.name = grep_opts.name or ""
    grep_opts.locations = grep_opts.locations or gl.get_cwd
end

---@param case qf-rancher.types.Case
---@return qf-rancher.types.Case
local function resolve_case(case)
    if case ~= "vimcase" then
        return case
    end

    local ic = api.nvim_get_option_value("ic", { scope = "global" })
    if ic then
        local scs = api.nvim_get_option_value("scs", { scope = "global" })
        if scs then
            return "smartcase"
        else
            return "insensitive"
        end
    else
        return "sensitive"
    end
end

---@param grep_opts QfrGrepOpts
---@return nil
local function resolve_grep_opts(grep_opts)
    grep_opts.case = resolve_case(grep_opts.case)
    if type(grep_opts.locations) == "function" then
        grep_opts.locations = grep_opts.locations()
    end
end

-- MID: Eventually put this into utils
---@param case qf-rancher.types.Case
---@param regex boolean
---@return string
local function get_display_input_type(case, regex)
    if regex then
        return "Regex"
    end

    if case == "sensitive" then
        return "Case Sensitive"
    elseif case == "smartcase" then
        return "Smartcase"
    else
        return "Case Insensitive"
    end
end

---@param case qf-rancher.types.Case
---@param regex boolean
---@param grepprg string
---@param name string
---@return boolean, string, string|nil
local function get_pattern_from_prompt(case, regex, grepprg, name)
    local display_input_type = get_display_input_type(case, regex)
    local which_grep = "[" .. grepprg .. "] " .. name .. " Grep "
    local prompt = which_grep .. "(" .. display_input_type .. "): "

    local ok, pattern, hl = ru._get_input(prompt, case)
    return ok, pattern, hl
end

---@alias QfrGrepLocsFunc fun():string[]

-- MID: Creates a conflict, becaue input type is exposed in the types module
-- MID: The case typedoc runs over the edge

---@class QfrGrepOpts
---@field case? qf-rancher.types.Case "insensitive"|"sensitive"|"smartcase"|"vimcase"
---A string list or a function
---returning a string list to provide locations to grep to.
---Pre-built location functions are available in
---"qf-rancher.lib.grep_locs"
---@field locations? string[]|QfrGrepLocsFunc
---@field name? string Display name of the grep for prompting
---Pattern to grep. If nil, either a prompt
---will display in normal mode or the selection will be
---used in visual mode
---@field pattern string|nil
---@field regex? boolean If false, use fixed strings when grepping

---Run a grep
---
---The list title will be set to:
---"[grep name] [base grep cmd] [pattern]"
---
---Use "checkhealth qf-rancher" to verify the status of the current
---g:qfr_grepprg value
---Note that this module will run an external grep, and thus must target
---valid files and directories
---
---If g:qfr_reuse_title is true, output_opts.action is " ", and a list
---with the grep's title already exists, that list will be reused
---
---If run in Visual mode, the selection will be used as the grep pattern.
---Nvim will return to Normal mode.
---
---This command uses the |qfr-system| module to run the grep and print
---results
---@param src_win integer|nil Location list window context. Nil for qflist
---@param action qf-rancher.types.Action See |setqflist-action|
---@param what qf-rancher.types.What See |setqflist-what|
---@param grep_opts QfrGrepOpts See |QfrGrepOpts|
---@param system_opts qf-rancher.SystemOpts See |QfrSystemOpts|
---@return nil
function Grep.grep(src_win, action, what, grep_opts, system_opts)
    ry._validate_win(src_win, true)
    ry._validate_action(action)
    ry._validate_what(what)
    validate_grep_opts(grep_opts)
    re._validate_system_opts(system_opts)

    if src_win then
        local ok, msg, hl = ru._is_valid_loclist_win(src_win)
        if not ok then
            api.nvim_echo({ { msg, hl } }, false, {})
            return
        end
    end

    local grepprg = vim.g.qfr_grepprg ---@type string
    if fn.executable(grepprg) ~= 1 then
        api.nvim_echo({ { grepprg .. " is not executable", "ErrorMsg" } }, true, {})
        return
    end

    grep_opts = grep_opts or {}
    populate_grep_opts(grep_opts)
    resolve_grep_opts(grep_opts)

    local pattern = grep_opts.pattern ---@type string|nil
    local case = grep_opts.case ---@type qf-rancher.types.Case
    local regex = grep_opts.regex ---@type boolean
    local locations = grep_opts.locations --[[@as string[]]

    if not pattern then
        local mode = api.nvim_get_mode().mode ---@type string
        local short_mode = string.sub(mode, 1, 1) ---@type string
        if short_mode == "v" or short_mode == "V" or short_mode == "\22" then
            pattern = ru._get_visual_pattern(short_mode)
        else
            local ok, input, hl = get_pattern_from_prompt(case, regex, grepprg, grep_opts.name)
            if ok then
                pattern = input
            else
                ru._echo(false, input, hl)
                return
            end
        end
    end

    local grep_parts = get_full_parts[grepprg](pattern, case, regex, locations) ---@type string[]
    if (not grep_parts) or #grep_parts == 0 then
        return
    end

    local sys_opts = vim.deepcopy(system_opts, true) ---@type qf-rancher.SystemOpts
    local base_cmd = table.concat(base_parts[grepprg], " ") ---@type string
    what.title = grep_opts.name .. " " .. base_cmd .. "  " .. pattern

    if vim.g.qfr_reuse_title and action == " " then
        local cur_list = rt._find_list_with_title(src_win, what.title) ---@type integer|nil
        if cur_list then
            action = "u"
            what.nr = cur_list
        end
    end

    re._system_do(grep_parts, src_win, action, what, sys_opts)
end

---@class QfrGrepInfo
---@field grep_opts QfrGrepOpts See |QfrGrepOpts|
---@field sys_opts qf-rancher.SystemOpts See |QfrSystemOpts|

---Greps available to the Qgrep and Lgrep cmds. The string table key can be
---used as an argument to specify the grep type. This table is public, and
---new greps can be added or removed directly
Grep.greps = {
    cwd = { grep_opts = { locations = gl.get_cwd, name = "CWD" }, sys_opts = {} },
    help = {
        grep_opts = { locations = gl.get_help_dirs, name = "Help" },
        sys_opts = { list_item_type = "\1" },
    },
    bufs = { grep_opts = { locations = gl.get_buflist, name = "Buf" }, sys_opts = {} },
    cbuf = { grep_opts = { locations = gl.get_cur_buf, name = "Cur Buf" }, sys_opts = {} },
} ---@type table<string, QfrGrepInfo>

-- LOW: Should be able to set the sys timeout from the cmd
---@param src_win? integer
---@param cargs vim.api.keyset.create_user_command.command_args
---@return nil
local function grep_cmd(src_win, cargs)
    cargs = cargs or {}
    local fargs = cargs.fargs ---@type string[]

    local action = ru._check_cmd_arg(fargs, ry._actions, " ") ---@type qf-rancher.types.Action

    local grep_names = vim.tbl_keys(Grep.greps) ---@type string[]
    assert(#grep_names > 1, "No grep commands available")
    local has_cwd = vim.tbl_contains(grep_names, "cwd") ---@type boolean
    local default_grep = has_cwd and "cwd" or grep_names[1] ---@type string
    local grep_name = ru._check_cmd_arg(fargs, grep_names, default_grep) ---@type string

    local grep_info = vim.deepcopy(Grep.greps[grep_name], true) ---@type QfrGrepInfo

    local grep_opts = grep_info.grep_opts ---@type QfrGrepOpts
    grep_opts.pattern = ru._find_pattern_in_cmd(fargs)

    ---@type QfrInputType
    local input_type = ru._check_cmd_arg(fargs, ry._cmd_input_types, ry._default_input_type)
    -- MID: Phase out input type and therefore this hack
    if input_type == "regex" then
        grep_opts.regex = true
    else
        ---@diagnostic disable-next-line: assign-type-mismatch
        grep_opts.case = input_type
    end

    local sys_opts = grep_info.sys_opts ---@type qf-rancher.SystemOpts
    ---@type "sync"|"async"
    local sync_str = ru._check_cmd_arg(fargs, ry._sync_opts, ry._default_sync_opt)
    local sync = sync_str == "sync" and true or false ---@type boolean
    sys_opts.sync = sync

    Grep.grep(src_win, action, { nr = cargs.count }, grep_opts, sys_opts)
end

---@brief [[
---The callbacks to assign the Qgrep and Lgrep commands are below. They expect
---count = 0 and nargs = "*" to be present in the user_command table.
---They accept the following options:
---- A registered grep name (cwd|help|bufs|cbuf). cwd is default
---  NOTE: "bufs" searches all open bufs, excluding help bufs
---  NOTE: "cbuf" searches the current buf, including help buffers
---  NOTE: The built in quickfix buf grep keymap searches all open bufs.
---  The location list grep searches the current buf
---- A pattern starting with "/"
---- A |qfr-input-type| ("vimcase" by default)
---- "async" or "sync" to control system behavior (async by default)
---- A |setqflist-action| (default " ")
---Example: 2Qgrep help r vimcase /setqflist
---@brief ]]

---@param cargs vim.api.keyset.create_user_command.command_args
---@return nil
function Grep.q_grep_cmd(cargs)
    grep_cmd(nil, cargs)
end

---@param cargs vim.api.keyset.create_user_command.command_args
---@return nil
function Grep.l_grep_cmd(cargs)
    grep_cmd(api.nvim_get_current_win(), cargs)
end

return Grep
---@export Grep

-- MID: Visual mode should be handled in its own functions. But other stuff should settle in first
-- MID: Check if grepprg is executable once and cache the result. Run the check if checkhealth is
-- run. Realistically, that status won't change while vim is open
-- MID: Grep a specific file. Could show this an an API example
-- MID: Grep in specific treesitter nodes. So qgtm would grep in function definitions. The llist
-- grep is easy because you do it in the current win buf. But for multiple bufs, how do you
-- handle different languages? This almost feels like it needs ts-textobjects
-- MID: Grep refactor:
-- - Put the grepprgs in their own module
-- - Each grepprg has a common type interface
-- - This, should, make it easier to register custom grepprgs or develop new ones
-- - Caveat: Creates a source of truth conflict with the g_var
-- - Look at vim-grepper for ideas
-- - grep_info should be renamed to grep_opts
-- - grep_opts should be used for specifying grep behavior, such as how to handle hidden and
-- git files. Should all be run through the grep interface

-- LOW: Support findstr
-- LOW: Support ack
-- LOW: When handling multiple locations, the grepprgs should build their arguments using
-- globbing rather than appending potentially dozens of locations
