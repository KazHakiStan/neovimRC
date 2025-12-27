vim.g.copilot_no_tab_map = true

local ok, chat = pcall(require, "CopilotChat")
if not ok then return end

chat.setup({})

vim.keymap.set("n", "<leader>cc", "<cmd>CopilotChatToggle<cr>", { desc = "CopilotChat toggle" })
vim.keymap.set("n", "<leader>co", "<cmd>CopilotChatOpen<cr>",   { desc = "CopilotChat open" })
vim.keymap.set("n", "<leader>cx", "<cmd>CopilotChatReset<cr>",  { desc = "CopilotChat reset" })

vim.keymap.set("v", "<leader>ce", "<cmd>CopilotChatExplain<cr>", { desc = "CopilotChat explain selection" })
vim.keymap.set("v", "<leader>cf", "<cmd>CopilotChatFix<cr>",     { desc = "CopilotChat fix selection" })
vim.keymap.set("v", "<leader>cr", "<cmd>CopilotChatReview<cr>",  { desc = "CopilotChat review selection" })
