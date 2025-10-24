-- TODO:
-- While the best practices guide recommends using Luarocks/busted, I don't want to go down that
-- route for three reasons
-- 1. While there is a push to make this standard, as of right now it's still a major ask for
--     potential contributors
-- 2. I don't have Rocks installed, so this would be a significant environmental change
-- 3. Learning how to use it seems like a big task, and I don't want to get lost in that rabbit
--     hole
--
-- My instinct here is to go with Mini's test suite. While the learning curve seems a bit steeper
-- than Plenary's, it gives us a couple key advantages:
-- - It seems to be able to better handle process/state management between the parent and child
--     processes
-- - I think, bigger picture, Plenary needs to be sunsetted from the ecosystem. Having catch-all
-- plugins is bad
-- More info on mini.test (the top-level post is a personal experience, but echasnovski has a
-- reply with some technical detail):
-- https://www.reddit.com/r/neovim/comments/1ee8ko7/my_journey_to_unit_testing_in_neovim_plugin/
--
-- Something I have to deal with for this is - What tests to write and how many. I think the right
-- move here is to start out with high level tests. So for something like open_qf_list, just
-- handle the basics like "does this actually open the list and go to it", but leave out the
-- detail testing of the opts, as they might need to change.
-- And then we can also think about like, in a sense what has to be developed and how much
-- based on the circumstances. Like with something like open_qflist, if a problem is found, it's
-- not necessarily a huge deal and is probably easy to fix, whereas something like interacting
-- with the system could produce nasty problems, and needs baked in more

local function base_open_qflist()
    local start_wintype = vim.fn.win_gettype()
    assert(start_wintype ~= "quickfix")
    local start_win = vim.api.nvim_get_current_win()

    require("qf-rancher.window").open_qflist({ keep_win = false })

    assert(vim.fn.win_gettype() == "quickfix")
    assert(vim.api.nvim_get_current_win() ~= start_wintype)
end

local function open_qflist_keep_win()
    local start_wintype = vim.fn.win_gettype()
    assert(start_wintype ~= "quickfix")
    local start_win = vim.api.nvim_get_current_win()

    require("qf-rancher.window").open_qflist({ keep_win = true })

    assert(vim.fn.win_gettype() == start_wintype)
    assert(vim.api.nvim_get_current_win() == start_win)
end
