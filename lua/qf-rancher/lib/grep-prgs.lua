-- local api = vim.api
local fn = vim.fn

---@class qf-rancher.lib.GrepPrgs
local M = {}

M.base_parts = {
    rg = { "rg", "--vimgrep", "-uu" },
    grep = { "grep", "--recursive", "--with-filename", "--line-number", "-I" },
}

---@type qf-rancher.grep.GrepPartsFunc
local function get_full_parts_rg(pattern, case, regex, locations)
    local cmd = vim.deepcopy(M.base_parts.rg, true) ---@type string[]

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

---@type qf-rancher.grep.GrepPartsFunc
local function get_full_parts_grep(pattern, case, regex, locations)
    local cmd = vim.deepcopy(M.base_parts.grep) ---@type string[]

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

---@type table<string, qf-rancher.grep.GrepPartsFunc>
M.get_full_parts = {
    grep = get_full_parts_grep,
    rg = get_full_parts_rg,
}

return M

-- MID: This is okay because at least you can read the code and monkey patch it, but this still
-- isn't a good interface for the user to add their own grepprgs.
-- - How does vim-grepper handle this?

-- LOW: Support findstr
-- LOW: Support ack
-- LOW: When handling multiple locations, the grepprgs should build their arguments using
-- globbing rather than appending potentially dozens of locations
