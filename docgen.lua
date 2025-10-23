local maps_tbls = require("lua.qf-rancher.maps")
local lines = {}

lines[#lines + 1] = "---@mod qf-rancher-keymaps Qf Rancher Keymaps"
lines[#lines + 1] = "---@brief [["

local function add_map(map)
    lines[#lines + 1] = "---"
    local modes = table.concat(map[1], ", ")
    local default = ", Default: " .. map[3]
    lines[#lines + 1] = "---Modes: { " .. modes .. " }, Plug: " .. map[2] .. default
    lines[#lines + 1] = "--- Desc: " .. map[4]
end

for _, map in ipairs(maps_tbls.qfr_maps) do
    add_map(map)
end

for _, map in ipairs(maps_tbls.qfr_buf_maps) do
    add_map(map)
end

lines[#lines + 1] = "---@brief ]]"
lines[#lines + 1] = "---@export qf-rancher-keymaps ]]"
local maps = table.concat(lines, "\n") .. "\n"

local maps_path = "doc/maps.lua"
local file, err = io.open(maps_path, "w")
if not file then error(err) end
file:write(maps)
file:close()

local cmd_parts = {
    "lemmy-help",
    "-l",
    '"compact"',
    -- Files
    "plugin/qf-rancher.lua",
    "lua/qf-rancher/open.lua",
    maps_path,
    -- Output
    ">",
    "doc/nvim-qf-rancher.txt",
} ---@type string[]

local cmd = table.concat(cmd_parts, " ") ---@type string
os.execute(cmd)

os.remove(maps_path)
