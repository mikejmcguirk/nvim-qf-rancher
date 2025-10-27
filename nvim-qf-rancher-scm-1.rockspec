rockspec_format = "3.0"
package = "nvim-qf-rancher"
version = "scm-1"
source = {
    url = "git+https://github.com/nvim-lua/nvim-lua-plugin-template",
}
dependencies = {
    -- Add runtime dependencies here
    -- e.g. "plenary.nvim",
}
test_dependencies = {
    "nlua",
}
build = {
    type = "builtin",
    copy_directories = {
        -- Add runtimepath directories, like
        -- 'plugin', 'ftplugin', 'doc'
        -- here. DO NOT add 'lua' or 'lib'.
    },
}
