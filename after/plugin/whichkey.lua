-- which-key: start a key sequence (<leader>, g, ], z, ", …), pause, and a
-- popup lists how it can continue. <leader>? lists this buffer's keys.
local ok, wk = pcall(require, "which-key")
if not ok then return end

wk.setup({
    preset = "helix",
    delay = require("kazhakistan.kazrc").get().key_hints_delay_ms,
    win = { border = "rounded" },
    icons = { mappings = false },
})

wk.add({
    { "<leader>c", group = "cheatsheet / code" },
    { "<leader>d", group = "database (or \"_d: delete without yanking)" },
    { "<leader>g", group = "git" },
    { "<leader>h", group = "harpoon" },
    { "<leader>m", group = "markdown" },
    { "<leader>p", group = "project / find" },
    { "<leader>q", group = "quickfix" },
    { "<leader>s", group = "split / session" },
    { "<leader>t", group = "terminal / tab" },
    { "<leader>w", group = "save / substitute" },
    { "<leader>x", group = "Xcode" },
    {
        "<leader>?",
        function() wk.show({ global = false }) end,
        desc = "Keys of this buffer",
    },
})
