-- Completion (blink.cmp): LSP, snippets, paths and words from open buffers.

-- What Tab does while the completion list is open:
--   "select"  Tab / S-Tab move through the list, <CR> accepts
--   "accept"  Tab accepts the highlighted item
-- Switch for this session: :CompletionTab [select|accept]
local TAB = "select"

-- With the list closed Tab always indents: it never jumps between snippet
-- fields (that's <C-l> / <C-h>), which used to throw the cursor elsewhere.
local ok, blink = pcall(require, "blink.cmp")
if not ok then return end

vim.g.completion_tab = vim.g.completion_tab or TAB

local function on_tab(cmp)
    if not cmp.is_menu_visible() then return end
    if vim.g.completion_tab == "accept" then return cmp.accept() end
    return cmp.select_next()
end

local function on_shift_tab(cmp)
    if vim.g.completion_tab == "select" and cmp.is_menu_visible() then return cmp.select_prev() end
end

blink.setup({
    keymap = {
        preset = "none",
        ["<C-space>"] = { "show", "show_documentation", "hide_documentation" },
        ["<C-e>"] = { "hide", "fallback" },
        ["<CR>"] = { "accept", "fallback" },
        ["<C-y>"] = { "select_and_accept" },
        ["<Tab>"] = { on_tab, "fallback" },
        ["<S-Tab>"] = { on_shift_tab, "fallback" },
        ["<C-n>"] = { "select_next", "fallback" },
        ["<C-p>"] = { "select_prev", "fallback" },
        ["<Down>"] = { "select_next", "fallback" },
        ["<Up>"] = { "select_prev", "fallback" },
        ["<C-b>"] = { "scroll_documentation_up", "fallback" },
        ["<C-f>"] = { "scroll_documentation_down", "fallback" },
        -- jump between the fields of an expanded snippet
        ["<C-l>"] = { "snippet_forward", "fallback" },
        ["<C-h>"] = { "snippet_backward", "fallback" },
    },
    completion = {
        documentation = { auto_show = true, auto_show_delay_ms = 300, window = { border = "rounded" } },
        menu = { border = "rounded" },
    },
    signature = { enabled = true, window = { border = "rounded" } },
    sources = {
        default = { "lsp", "path", "snippets", "buffer" },
        per_filetype = {
            sql = { "dadbod", "snippets", "buffer" },
            mysql = { "dadbod", "snippets", "buffer" },
            plsql = { "dadbod", "snippets", "buffer" },
        },
        providers = {
            dadbod = { name = "Dadbod", module = "vim_dadbod_completion.blink" },
        },
    },
    -- the prebuilt Rust matcher when it's there, the Lua one otherwise
    fuzzy = { implementation = "prefer_rust" },
})

vim.api.nvim_create_user_command("CompletionTab", function(o)
    local mode = o.args ~= "" and o.args or (vim.g.completion_tab == "accept" and "select" or "accept")
    if mode ~= "select" and mode ~= "accept" then
        return vim.notify("CompletionTab: select or accept", vim.log.levels.ERROR)
    end
    vim.g.completion_tab = mode
    vim.notify(mode == "accept" and "Tab accepts the completion" or "Tab moves through the completion list")
end, { nargs = "?", complete = function() return { "select", "accept" } end, desc = "What Tab does in the completion list" })
