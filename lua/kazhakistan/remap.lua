vim.g.mapleader = " "
vim.keymap.set("n", "<leader>pv", vim.cmd.Ex)

vim.keymap.set("t", "<Esc>", [[<C-\><C-n>]], { desc = "Terminal: normal mode" })

vim.keymap.set("n", "<leader>tt", function ()
    vim.cmd("botright split | resize 12 | terminal")
    vim.cmd("startinsert")
end, { desc = "Terminal: open (split)" })

vim.keymap.set("n", "<leader>tv", function ()
    vim.cmd("botright vsplit | terminal")
    vim.cmd("startinsert")
end, { desc = "Terminal: open (vsplit)" })

vim.keymap.set("v", "J", ":m '>+1<CR>gv=gv")
vim.keymap.set("v", "K", ":m '<-2<CR>gv=gv")

vim.keymap.set("n", "J", "mzJ`z")

vim.keymap.set("n", "<C-d>", "<C-d>zz")
vim.keymap.set("n", "<C-u>", "<C-u>zz")

vim.keymap.set("n", "n", "nzzzv")
vim.keymap.set("n", "N", "Nzzzv")

vim.keymap.set("x", "<leader>p", [["_dP]])
vim.keymap.set({"n", "v"}, "<leader>y", [["+y]])
vim.keymap.set("n", "<leader>Y", [["+Y]])

vim.keymap.set({"n", "v"}, "<leader>d", [["_d]])

vim.keymap.set("i", "<C-c>", "<Esc>")

vim.keymap.set("n", "<leader>s", [[:%s/\<<C-r><C-w>\>/<C-r><C-w>/gI<Left><Left><Left>]])

vim.keymap.set("n", "<M-h>", "<cmd>vertical resize -2<cr>", { desc = "Resize: narrower" })
vim.keymap.set("n", "<M-l>", "<cmd>vertical resize +2<cr>", { desc = "Resize: wider" })
vim.keymap.set("n", "<M-j>", "<cmd>resize -1<cr>", { desc = "Resize: taller" })
vim.keymap.set("n", "<M-k>", "<cmd>resize +1<cr>", { desc = "Resize: shorter" })

vim.keymap.set("n", "<leader>=", "<C-w>=", { desc = "Resize: equalize" })

vim.keymap.set("n", "<leader>sv", "<cmd>vsplit<cr>", { desc = "Split: vertical" })
vim.keymap.set("n", "<leader>sh", "<cmd>split<cr>", { desc = "Split: horizontal" })

vim.keymap.set("n", "<C-h>", "<C-w>h", { desc = "Window: left" })
vim.keymap.set("n", "<C-j>", "<C-w>j", { desc = "Window: down" })
vim.keymap.set("n", "<C-k>", "<C-w>k", { desc = "Window: up" })
vim.keymap.set("n", "<C-l>", "<C-w>l", { desc = "Window: right" })

vim.keymap.set("n", "<leader>tn", "<cmd>tabnew<cr>", { desc = "Tab: new" })
vim.keymap.set("n", "<leader>tc", "<cmd>tabclose<cr>", { desc = "Tab: close" })
vim.keymap.set("n", "<leader>to", "<cmd>tabonly<cr>", { desc = "Tab: close others" })
vim.keymap.set("n", "<M-,>", "gT", { desc = "Tab: next" })
vim.keymap.set("n", "<M-.>", "gv", { desc = "Tab: prev" })
