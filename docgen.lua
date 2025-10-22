local cmd_parts = { "lemmy-help", "-l", '"compact"' } ---@type string[]
local files = { "plugin/qf-rancher.lua", "lua/qf-rancher/open.lua" } ---@type string[]
local output = { ">", "doc/nvim-qf-rancher.txt" } ---@type string[]

for _, file in ipairs(files) do
    cmd_parts[#cmd_parts + 1] = file
end

for _, out_part in ipairs(output) do
    cmd_parts[#cmd_parts + 1] = out_part
end

local cmd = table.concat(cmd_parts, " ") ---@type string
os.execute(cmd)
