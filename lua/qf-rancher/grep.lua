local gl = Qfr_Defer_Require("qf-rancher.lib.grep-locs") ---@type qf-rancher.lib.GrepLocs
local gp = Qfr_Defer_Require("qf-rancher.lib.grep-prgs") ---@type qf-rancher.lib.GrepPrgs
local re = Qfr_Defer_Require("qf-rancher.system") ---@type qf-rancher.System
local ru = Qfr_Defer_Require("qf-rancher.util") ---@type qf-rancher.Util
local ry = Qfr_Defer_Require("qf-rancher.types") ---@type qf-rancher.Types

local api = vim.api
local fn = vim.fn

local executable = {} ---@type table<string, boolean>

---@param grep_opts qf-rancher.grep.GrepOpts
---@return nil
local function validate_grep_opts(grep_opts)
    vim.validate("grep_opts", grep_opts, "table")

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

-- MID: This logic is currently correct because regex is just regex. But if we allow case to
-- influence regex behavior, then we'd have to think about what to show. Issue: For external
-- interactions we can't necessarily know what casing behavior we get. Perhaps for vim regex you
-- show something specific, and for external regex you just show generic "Regex". I think trying
-- to solve the one-to-many problem of "which external regex are we using" is a mistake.
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

local function assemble_prompt(case, regex, grepprg, name)
    local display_input_type = get_display_input_type(case, regex)
    local which_grep = "[" .. grepprg .. "] " .. name .. " Grep "
    return which_grep .. "(" .. display_input_type .. "): "
end

---@param src_win integer|nil
---@param grepprg string
---@return boolean, string|nil, string|nil
local function check_runtime_input_data(src_win, grepprg)
    if src_win then
        local ok, msg, hl = ru._is_valid_loclist_win(src_win)
        if not ok then
            return false, msg, hl
        end
    end

    if not executable[grepprg] then
        local is_executable = fn.executable(grepprg) == 1
        if is_executable then
            executable[grepprg] = true
        else
            local msg = grepprg .. " is not executable"
            return false, msg, "ErrorMsg"
        end
    end

    return true, nil, nil
end

---@param src_win integer|nil
---@param action qf-rancher.types.Action
---@param what qf-rancher.types.What
---@param grep_opts qf-rancher.grep.GrepOpts
---@param sys_opts qf-rancher.SystemOpts
---@return nil
local function validate_grep_params(src_win, action, what, grep_opts, sys_opts)
    ry._validate_win(src_win, true)
    ry._validate_action(action)
    ry._validate_what(what)
    validate_grep_opts(grep_opts)
    re._validate_system_opts(sys_opts)
end

--- @class qf-rancher.Grep
local Grep = {}

---@mod Grep Grep items into the list
---@tag qf-rancher-grep
---@tag qfr-grep
---@brief [[
---
---@brief ]]

---@alias qf-rancher.grep.GrepPartsFunc fun(pattern: string, case: qf-rancher.types.Case, regex: boolean, locations: string[]):string[]

---
---@class qf-rancher.grep.GrepOpts
---
---"insensitive"|"sensitive"|"smartcase"|"vimcase"
---@field case? qf-rancher.types.Case
---A string list or a function
---returning a string list of locations to grep to.
---Pre-built location functions are available in
---"qf-rancher.lib.grep-locs"
---@field locations? string[]|fun():string[]
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
---@param src_win integer|nil Location list window context. Nil for
---qflist
---@param action qf-rancher.types.Action See |setqflist-action|
---@param what qf-rancher.types.What See |setqflist-what|
---@param grep_opts qf-rancher.grep.GrepOpts See |qf-rancher.grep.GrepOpts|
---@param sys_opts qf-rancher.SystemOpts See |QfrSystemOpts|
---@return nil
function Grep.grep(src_win, action, what, grep_opts, sys_opts)
    grep_opts = grep_opts or {}
    validate_grep_params(src_win, action, what, grep_opts, sys_opts)

    local grepprg = vim.g.qfr_grepprg ---@type string
    local ok_d, err, hl = check_runtime_input_data(src_win, grepprg)
    if not ok_d then
        ru._echo(false, err, hl)
        return
    end

    local locations = grep_opts.locations or gl.get_cwd
    -- Lua_Ls complains if this is a ternary
    locations = (function()
        if type(locations) == "function" then
            return locations()
        else
            return locations
        end
    end)()

    if #locations == 0 then
        api.nvim_echo({ { "No valid grep locations found" } }, false, {})
        return
    end

    local case = grep_opts.case or "vimcase" ---@type qf-rancher.types.Case
    case = ru._resolve_case(case)
    local name = grep_opts.name or ""
    local regex = ru._resolve_boolean_opt(grep_opts.regex, false)
    local ok_p, vmode, pattern, hl_p = ru._get_pattern(grep_opts.pattern, case, function()
        return assemble_prompt(case, regex, grepprg, name)
    end)

    if not (ok_p and pattern) then
        if pattern ~= "Keyboard interrupt" then
            ru._echo(false, pattern, hl_p)
        end

        return
    end

    if vmode then
        api.nvim_cmd({ cmd = "norm", args = { "\27" }, bang = true }, {})
    end

    local grep_parts = gp.get_full_parts[grepprg](pattern, case, regex, locations)
    if (not grep_parts) or #grep_parts == 0 then
        api.nvim_echo({ { "Unable to build " .. grepprg .. " cmd", "ErrorMsg" } }, true, {})
        return
    end

    what = vim.deepcopy(what, true)
    sys_opts = vim.deepcopy(sys_opts, true)

    local base_cmd = table.concat(gp.base_parts[grepprg], " ")
    what.title = name .. " " .. base_cmd .. "  " .. pattern
    local rt = require("qf-rancher.tools")
    action, what = rt._resolve_title_reuse(src_win, action, what)

    re._system_do(grep_parts, src_win, action, what, sys_opts)
end

---@class qf-rancher.grep.GrepInfo
---@field grep_opts qf-rancher.grep.GrepOpts See |QfrGrepOpts|
---@field sys_opts qf-rancher.SystemOpts See |QfrSystemOpts|

---@type table<string, qf-rancher.grep.GrepInfo>
local grep_cmds = {
    cwd = { grep_opts = { locations = gl.get_cwd, name = "CWD" }, sys_opts = {} },
    help = {
        grep_opts = { locations = gl.get_help_dirs, name = "Help" },
        sys_opts = { list_item_type = "\1" },
    },
    bufs = { grep_opts = { locations = gl.get_buflist, name = "Buf" }, sys_opts = {} },
    cbuf = { grep_opts = { locations = gl.get_cur_buf, name = "Cur Buf" }, sys_opts = {} },
}

-- LOW: Should be able to set the sys timeout from the cmd

---@param src_win? integer
---@param cargs vim.api.keyset.create_user_command.command_args
---@return nil
local function grep_cmd(src_win, cargs)
    cargs = cargs or {}
    local fargs = cargs.fargs ---@type string[]

    local grep_names = vim.tbl_keys(grep_cmds)
    local grep_name = ru._check_cmd_arg(fargs, grep_names, "cwd")

    local grep_info = vim.deepcopy(grep_cmds[grep_name], true) ---@type qf-rancher.grep.GrepInfo
    local grep_opts = grep_info.grep_opts ---@type qf-rancher.grep.GrepOpts
    grep_opts.pattern = ru._find_pattern_in_cmd(fargs)

    ---@type QfrInputType
    local input_type = ru._check_cmd_arg(fargs, ry._cmd_input_types, ry._default_input_type)
    -- TODO: Phase out input type and therefore this hack
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

    local action = cargs.count > 0 and "r" or " " ---@type qf-rancher.types.Action
    local nr = cargs.count > 0 and cargs.count or "$" ---@type integer|"$"

    Grep.grep(src_win, action, { nr = nr }, grep_opts, sys_opts)
end

-- MAYBE: Use bang to use regex. Or maybe a special character in front of the case arg

---@brief [[
---The callbacks to assign the Qgrep and Lgrep commands are below. They expect
---count = 0 and nargs = "*" to be present in the user_command table.
---
---They accept the following options:
---- A grep name (cwd|help|bufs|cbuf). cwd is default
---  NOTE: "bufs" searches all open bufs, excluding help bufs
---  NOTE: "cbuf" searches the current buf, including help buffers
---- A pattern starting with "/"
---- A |qfr-input-type| ("vimcase" by default)
---- "async" or "sync" to control system behavior (async by default)
---
---If a count is provided, then [count] list will be overwritten. Otherwise, a
---new list will be created at the end of the stack.
---
---The output list will be given a title based on the grep cmd and the query.
---If no count is provided, g:qfr_reuse_title is true, and a list with a
---matching title exists, it will be reused.
---
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
    local cur_win = api.nvim_get_current_win()
    grep_cmd(cur_win, cargs)
end

return Grep

---@export Grep

-- Escaping test line from From vim-grepper
-- ..ad\\f40+$':-# @=,!;%^&&*()_{}/ /4304\'""?`9$343%$ ^adfadf[ad)[(

-- MID: Add built-in logic for handling hidden files and git files. The base maps/cmds should
-- ignore hidden files. A separate map should be available for only searching git files.
-- MID: Would like to add a Qfuzzy cmd that acts as an interface with fzf and other fuzzy finding
-- programs. You could generalize out to a cmd like Qfind that works with greps and fuzzy finders,
-- but I like having both grepprg and fuzzyprg readily available. But that idea still influences
-- how this module should be written since we want the components to be as generalizable as
-- possible.
-- MID: Add a Qfuzzy cmd for fzf and other fuzzy finders. The code here should be generalizable for
-- the purposes of pattern acquisition and interfacing with the system module.
-- - Avoid abstracting all the way out to "Qfind". Grep and Fuzzy finding do different things, so
-- both could be readily available. Even under the hood, the concepts don't fully merge well
-- because Greps and Fuzzy finders use different settings

-- LOW: For currently open buffers, is it possible to send the file contents to the grepprg
-- directly rather than having the grepprg re-read from memory? More performant and allows for
-- searching on unsaved buffer state.
