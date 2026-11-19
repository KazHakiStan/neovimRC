local builtin_ok, builtin = pcall(require, 'telescope.builtin')
if not builtin_ok then return end
local image_preview = require("kazhakistan.image_preview")
image_preview.setup()
local default_maker = require("telescope.previewers").buffer_previewer_maker
require("telescope").setup({
    defaults = {
        buffer_previewer_maker = function(path, bufnr, opts)
            image_preview.clear()
            if image_preview.is_image(path) and opts.winid then
                image_preview.show(vim.fn.expand(path), bufnr, opts.winid)
            else
                default_maker(path, bufnr, opts)
            end
        end,
    },
})

vim.keymap.set('n', '<leader>pf', builtin.find_files, { desc = 'Telescope find files' })
vim.keymap.set('n', '<C-p>', builtin.git_files, { desc = 'Git find files' })
vim.keymap.set('n', '<leader>ps', function()
	builtin.live_grep();
end, { desc = 'Telescope grep' })
