vim.keymap.set("n", "<leader>mp", "<Plug>(md-render-preview)", { desc = "Markdown preview" })
vim.keymap.set("n", "<leader>mt", "<Plug>(md-render-preview-tab)", { desc = "Markdown preview in tab" })

vim.api.nvim_create_autocmd("FileType", {
    group = vim.api.nvim_create_augroup("MarkdownAutoRender", { clear = true }),
    pattern = "markdown",
    callback = function(event)
        -- Wait until file loading and the other FileType handlers have finished.
        local win = vim.api.nvim_get_current_win()
        vim.schedule(function()
            if not vim.api.nvim_win_is_valid(win)
                or vim.api.nvim_win_get_buf(win) ~= event.buf
                or vim.bo[event.buf].buftype ~= "" then
                return
            end
            local ok, renderer = pcall(require, "md-render")
            if ok then
                vim.api.nvim_win_call(win, function()
                    renderer.preview.auto_on()
                end)
            end
        end)
    end,
})
