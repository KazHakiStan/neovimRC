local builtin_ok, builtin = pcall(require, 'telescope.builtin')
if not builtin_ok then return end
vim.keymap.set('n', '<leader>pf', builtin.find_files, { desc = 'Telescope find files' })
vim.keymap.set('n', '<C-p>', builtin.git_files, { desc = 'Git find files' })
vim.keymap.set('n', '<leader>ps', function()
	builtin.live_grep();
end)

pcall(function()
  require("telescope").load_extension("projects")
end)

