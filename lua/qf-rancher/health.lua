local M = {}

M.check = function()
    vim.health.start("Installation")
    if vim.fn.has("nvim-0.11") then
        vim.health.ok("Neovim version is at least 0.11")
    else
        vim.health.warn("Neovim version is below 0.11")
    end

    vim.health.start("Config")
    for v, t in pairs(_G._QFR_G_VAR_MAP) do
        local allowed = table.concat(t[1], ", ") ---@type string
        local val = vim.g[v] ---@type any
        local val_type = type(val) ---@type string
        -- NOTE: tostring being able to handle NaN and +/-inf is LuaJIT exclusive
        ---@type string
        local val_fmt = val_type == "table" and table.concat(val, ", ") or tostring(val)
        ---@type string
        local var_info = "g:" .. v .. " = " .. val_fmt .. " (Allowed: " .. allowed .. ")"

        if vim.tbl_contains(t[1], val_type) then
            vim.health.ok(var_info)
        else
            vim.health.error(var_info)
        end
    end

    -- MID: This would be better if it checked and reported on the status of all available
    -- grepprgs, highlighting the one currently selected. Defer this until grep module refactor

    vim.health.start("Grep")
    local grepprg = tostring(vim.g.qfr_grepprg) ---@type string
    if vim.fn.executable(grepprg) == 1 then
        vim.health.ok("Qfr grepprg " .. grepprg .. " is executable")
    else
        vim.health.error("Qfr grepprg " .. grepprg .. " is not executable")
    end
end

return M
