local api = vim.api
local fn = vim.fn

--- @class QfrLibGrepLocs
local Locs = {}

-- LOW: Trivial, but why can't I use uv.cwd here?
---@return string[]
function Locs.get_cwd()
    return { fn.getcwd() }
end

-- MID: Printing the error here is a bad pattern
-- LOW: How does FzfLua handle Lazy.nvim unloaded paths?
---@return string[]|nil
function Locs.get_help_dirs()
    local doc_files = api.nvim_get_runtime_file("doc/*.txt", true) ---@type string[]
    if #doc_files > 0 then
        return doc_files
    end

    api.nvim_echo({ { "No doc files found", "ErrorMsg" } }, true, { err = true })
    return nil
end

-- MID: Printing the error here is a bad pattern
-- LOW: Since this has to check fs_access for multiple bufs, would be neat if it were async
---@return string[]|nil
function Locs.get_buflist()
    local bufs = api.nvim_list_bufs() ---@type integer[]
    local fnames = {} ---@type string[]

    ---@param buf integer
    ---@return boolean
    local function is_buf_valid(buf)
        local bt = api.nvim_get_option_value("bt", { buf = buf }) ---@type string
        if bt ~= "" then
            return false
        end

        local bl = api.nvim_get_option_value("bl", { buf = buf }) ---@type boolean
        return bl
    end

    for _, buf in pairs(bufs) do
        if is_buf_valid(buf) then
            local fname = api.nvim_buf_get_name(buf) ---@type string
            local fs_access = vim.uv.fs_access(fname, 4) ---@type boolean|nil
            if fname ~= "" and fs_access then
                fnames[#fnames + 1] = fname
            end
        end
    end

    if #fnames > 0 then
        return fnames
    end

    api.nvim_echo({ { "No valid bufs found", "" } }, false, {})
    return nil
end

-- MID: Same as others - Should not print error here
---@return string[]|nil
function Locs.get_cur_buf()
    local buf = api.nvim_get_current_buf() ---@type integer
    local bl = api.nvim_get_option_value("bl", { buf = buf })
    if not bl then
        api.nvim_echo({ { "Cur buf is not listed", "" } }, false, {})
        return nil
    end

    local bt = api.nvim_get_option_value("bt", { buf = buf }) ---@type string
    if not (bt == "" or bt == "help") then
        api.nvim_echo({ { "Buftype " .. bt .. " is not valid", "" } }, false, {})
        return nil
    end

    local fname = api.nvim_buf_get_name(buf) ---@type string
    local fs_access = vim.uv.fs_access(fname, 4) ---@type boolean|nil
    if fname ~= "" and fs_access then
        return { fname }
    end

    api.nvim_echo({ { "Current buffer is not a valid file", "" } }, false, {})
    return nil
end

return Locs
