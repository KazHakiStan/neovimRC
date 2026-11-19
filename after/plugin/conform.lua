-- Formatting (conform.nvim): `format` in the settings (~/.config/kazrc/nvim.lua).
--   <leader>f       format the file (or the selection)
--   on save         when format.on_save, and only where the project has the
--                   formatter's config (.clang-format...)
--   :FormatToggle   formatting on save off / on for this session
local ok, conform = pcall(require, "conform")
if not ok then return end

local kazrc = require("kazhakistan.kazrc")
local util = require("conform.util")

conform.setup({
    formatters_by_ft = kazrc.get().format.by_filetype,
    formatters = {
        -- no .clang-format up the tree: leave the file alone
        clang_format = { require_cwd = true, cwd = util.root_file({ ".clang-format", "_clang-format" }) },
    },
    format_on_save = function()
        if not kazrc.get().format.on_save or vim.g.format_on_save_off then return end
        return { timeout_ms = 1500, lsp_format = "never" }
    end,
})

vim.keymap.set({ "n", "v" }, "<leader>f", function()
    conform.format({ async = true, lsp_format = "never" }, function(err, did_edit)
        if err and err:find("No formatters available") then
            vim.notify("format: nothing to format this with (no formatter for this filetype, or no .clang-format here)")
        elseif err then
            vim.notify("format: " .. err, vim.log.levels.WARN)
        end
    end)
end, { desc = "Format file / selection" })

vim.api.nvim_create_user_command("FormatToggle", function()
    vim.g.format_on_save_off = not vim.g.format_on_save_off
    vim.notify("format on save " .. (vim.g.format_on_save_off and "off" or "on"))
end, { desc = "Formatting on save off / on (this session)" })

-- clang-format from Mason where the system has none (Windows without LLVM)
if vim.fn.executable("clang-format") == 0 then
    local ok_reg, registry = pcall(require, "mason-registry")
    if ok_reg then
        registry.refresh(function()
            local ok_pkg, pkg = pcall(registry.get_package, "clang-format")
            if ok_pkg and not pkg:is_installed() then pkg:install() end
        end)
    end
end
