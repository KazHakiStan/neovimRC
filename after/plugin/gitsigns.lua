-- Git changes in the sign column (│ added/changed, _ deleted) and hunk actions.
-- <leader>gs stays fugitive's :Git.
local ok, gitsigns = pcall(require, "gitsigns")
if not ok then return end

gitsigns.setup({
    preview_config = { border = "rounded" },
    current_line_blame = require("kazhakistan.kazrc").get().git.line_blame,
    current_line_blame_opts = { delay = 300 },
    on_attach = function(buf)
        local function map(mode, lhs, rhs, desc)
            vim.keymap.set(mode, lhs, rhs, { buffer = buf, desc = desc })
        end
        map("n", "]h", function() gitsigns.nav_hunk("next") end, "Git: next change")
        map("n", "[h", function() gitsigns.nav_hunk("prev") end, "Git: previous change")
        map("n", "<leader>gp", gitsigns.preview_hunk, "Git: preview change")
        map("n", "<leader>ga", gitsigns.stage_hunk, "Git: stage / unstage change")
        map("v", "<leader>ga", function() gitsigns.stage_hunk({ vim.fn.line("."), vim.fn.line("v") }) end,
            "Git: stage selected lines")
        map("n", "<leader>gr", gitsigns.reset_hunk, "Git: undo change")
        map("v", "<leader>gr", function() gitsigns.reset_hunk({ vim.fn.line("."), vim.fn.line("v") }) end,
            "Git: undo selected lines")
        map("n", "<leader>gb", function() gitsigns.blame_line({ full = true }) end, "Git: blame line")
        map("n", "<leader>gB", gitsigns.toggle_current_line_blame, "Git: blame at end of every line")
        map("n", "<leader>gd", gitsigns.diffthis, "Git: diff file")
    end,
})
