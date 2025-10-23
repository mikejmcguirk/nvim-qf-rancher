---@param map QfrMapData
---@param lines string[]
---@return nil
local function add_map(map, lines)
    lines[#lines + 1] = "---"
    local modes = table.concat(map[1], ", ") ---@type string
    local default = ", Default: " .. map[3] ---@type string
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
local paths = {} ---@type {[1]:string, [2]:string[] }[]

-- TODO: This procedure should be standardized across each map group. The grep_map_tbl should be
-- built first so it can be processed with the others

local win_map_tbl = maps_tbls.qfr_win_maps ---@type QfrMapData[]
local win_cmd_tbl = maps_tbls.qfr_win_cmds ---@type QfrCmdData[]

local win_lines = {} ---@type string[]
-- TODO the better way to do this would be to manually add a divider and the tags. Test on
-- windows first
win_lines[#win_lines + 1] = "---@mod qf-rancher-window-controls Qf Rancher Window Controls"
win_lines[#win_lines + 1] = "---@brief [["

for _, map in ipairs(win_map_tbl) do
    add_map(map, win_lines)
end

for _, cmd in ipairs(win_cmd_tbl) do
    add_cmd(cmd, win_lines)
end

win_lines[#win_lines + 1] = "---@brief ]]"
win_lines[#win_lines + 1] = "---@export qf-rancher-window-controls"

local win_path = "doc/win_maps.lua" ---@type string
paths[#paths + 1] = { win_path, win_lines }

for _, path in ipairs(paths) do
    local file, err = io.open(path[1], "w")
    if not file then error(err) end
    local lines = table.concat(path[2], "\n") .. "\n"
    file:write(lines)
    file:close()
end

-- TODO: Need a way to tie the module doc with the maps doc

local cmd_parts = {
    "lemmy-help",
    "-l",
    '"compact"',
    -- Files
    "plugin/qf-rancher.lua",
    "lua/qf-rancher/windows.lua",
} ---@type string[]

for _, path in ipairs(paths) do
    cmd_parts[#cmd_parts + 1] = path[1]
end

cmd_parts[#cmd_parts + 1] = ">"
cmd_parts[#cmd_parts + 1] = "doc/nvim-qf-rancher.txt"

local cmd = table.concat(cmd_parts, " ") ---@type string
os.execute(cmd)

for _, path in ipairs(paths) do
    os.remove(path[1])
end
