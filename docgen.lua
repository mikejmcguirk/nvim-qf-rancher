---@param map QfrMapData
---@param lines string[]
---@return nil
local function add_map(map, lines)
    lines[#lines + 1] = "---"
    local modes = table.concat(map[1], ", ") ---@type string
    local default = ', Default: "' .. map[3] .. '"' ---@type string
    lines[#lines + 1] = "---Modes: { " .. modes .. " }, Plug: " .. map[2] .. default
    lines[#lines + 1] = "--- Desc: " .. map[4]
end

---@param cmd QfrCmdData
---@param lines string[]
---@return nil
local function add_cmd(cmd, lines)
    lines[#lines + 1] = "---"
    lines[#lines + 1] = "---Cmd: " .. cmd[1]
    lines[#lines + 1] = "---Desc: " .. cmd[3].desc
end

local maps_tbls = require("lua.qf-rancher.maps")
local doc_tbls = maps_tbls.doc_tbls ---@type { [1]: string, [2]:QfrMapData[], [3]: QfrCmdData[] }[]
local doc_paths = {} ---@type {[1]:string, [2]:string[] }[]
local cmd_parts = { "lemmy-help", "-l", '"compact"', "plugin/qf-rancher.lua" } ---@type string[]

local qf = "qf"

for _, tbl in ipairs(doc_tbls) do
    local map_tbl = tbl[2] ---@type QfrMapData[]
    local cmd_tbl = tbl[3] ---@type QfrCmdData[]

    local lines = {} ---@type string[]
    ---@type string
    local modname = tbl[1] == qf and "ftplugin" or tbl[1]
    local modtag = "qf-rancher-" .. modname .. "-controls" ---@type string
    local modtag_map = "qfr-" .. modname .. "-keymaps" ---@type string
    local modtag_cmd = "qfr-" .. modname .. "-commands" ---@type string
    local titlecase = string.upper(string.sub(modname, 1, 1)) .. string.sub(modname, 2)

    lines[#lines + 1] = "---@mod " .. modtag .. " Qfr " .. titlecase .. " controls"
    lines[#lines + 1] = "---@tag " .. modtag_map
    if tbl[1] ~= qf then lines[#lines + 1] = "---@tag " .. modtag_cmd end
    lines[#lines + 1] = "---@brief [["
    lines[#lines + 1] = "---"

    for _, map in ipairs(map_tbl) do
        add_map(map, lines)
    end

    for _, cmd in ipairs(cmd_tbl) do
        add_cmd(cmd, lines)
    end

    lines[#lines + 1] = "---@brief ]]"
    lines[#lines + 1] = "---@export " .. modtag

    local path = "doc/" .. tbl[1] .. "_maps.lua" ---@type string
    doc_paths[#doc_paths + 1] = { path, lines }
    cmd_parts[#cmd_parts + 1] = path
    local dir = tbl[1] == qf and "after/ftplugin/" or "lua/qf-rancher/"
    cmd_parts[#cmd_parts + 1] = dir .. tbl[1] .. ".lua"
end

cmd_parts[#cmd_parts + 1] = "lua/qf-rancher/system.lua"
cmd_parts[#cmd_parts + 1] = "lua/qf-rancher/preview.lua"
cmd_parts[#cmd_parts + 1] = "lua/qf-rancher/types.lua"

for _, path in ipairs(doc_paths) do
    local file, err = io.open(path[1], "w") ---@type file*?, string?
    if not file then error(err) end
    local doc_lines = table.concat(path[2], "\n") .. "\n" ---@type string
    file:write(doc_lines)
    file:close()
end

cmd_parts[#cmd_parts + 1] = "> doc/nvim-qf-rancher.txt"
local cmd = table.concat(cmd_parts, " ") ---@type string
os.execute(cmd)

for _, path in ipairs(doc_paths) do
    os.remove(path[1])
end

-- LOW: Auto-generate the variable docs
