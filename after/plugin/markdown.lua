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

-- Reading is the default: markdown opens rendered. i/a/o (md-render's own)
-- and here every normal-mode edit (dd, x, p, u, ...) switch to the source
-- and do it there instead of failing on the read-only view. Leaving insert
-- mode renders again; after a normal-mode edit <leader>mr goes back.
local EDIT_KEYS = { "x", "X", "s", "S", "C", "D", "r", "R", "p", "P", "J", "d", "c", ">", "<", "=", "~",
    "u", "<C-r>", "." }

vim.keymap.set("n", "<leader>mr", "<Plug>(md-render-toggle)", { desc = "Markdown: rendered / source" })

vim.api.nvim_create_autocmd("BufEnter", {
    group = vim.api.nvim_create_augroup("MarkdownRenderEdits", { clear = true }),
    callback = function(event)
        if not vim.api.nvim_buf_get_name(event.buf):match(" %[render%]$") then return end
        if vim.b[event.buf].kaz_edit_keys then return end
        -- only on md-render's auto views (they map i/a/o the same way)
        local i_map = vim.fn.maparg("i", "n", false, true)
        if not (i_map.buffer == 1 and (i_map.desc or ""):find("^md%-render auto")) then return end
        vim.b[event.buf].kaz_edit_keys = true
        for _, key in ipairs(EDIT_KEYS) do
            vim.keymap.set("n", key, function()
                local count = vim.v.count > 0 and tostring(vim.v.count) or ""
                require("md-render").preview.toggle()
                vim.schedule(function()
                    vim.api.nvim_feedkeys(count .. vim.keycode(key), "n", false)
                end)
            end, { buffer = event.buf, desc = "Markdown: switch to the source, then " .. key })
        end
    end,
})
