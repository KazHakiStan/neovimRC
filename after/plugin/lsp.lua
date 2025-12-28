local ok_mason, mason = pcall(require, "mason")
local ok_mason_lsp, mason_lspconfig = pcall(require, "mason-lspconfig")
if not (ok_mason and ok_mason_lsp) then
  return
end

mason.setup()

-- Install servers with Mason, but DON'T auto-enable yet.
-- We'll configure first, then enable explicitly.
mason_lspconfig.setup({
  ensure_installed = {
    "clangd",        -- C/C++
    "omnisharp",     -- C#
    "jdtls",         -- Java
    "pyright",       -- Python
    "ts_ls",         -- JS/TS (new config name)
    "lua_ls",        -- Lua
    "vimls",         -- Vimscript
    "html",          -- HTML
    "cssls",         -- CSS
    "rust_analyzer", -- Rust
  },
  automatic_enable = false,
})

-- Keymaps when LSP attaches (native way)
vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(args)
    local bufnr = args.buf

    local nmap = function(keys, func, desc)
      vim.keymap.set("n", keys, func, { buffer = bufnr, desc = desc })
    end

    nmap("gd", vim.lsp.buf.definition, "Go to definition")
    nmap("gD", vim.lsp.buf.declaration, "Go to declaration")
    nmap("gr", vim.lsp.buf.references, "References")
    nmap("gi", vim.lsp.buf.implementation, "Go to implementation")
    nmap("K", vim.lsp.buf.hover, "Hover")
    nmap("<leader>rn", vim.lsp.buf.rename, "Rename")
    nmap("<leader>ca", vim.lsp.buf.code_action, "Code action")
    nmap("[d", vim.diagnostic.goto_prev, "Prev diagnostic")
    nmap("]d", vim.diagnostic.goto_next, "Next diagnostic")
    nmap("<leader>e", vim.diagnostic.open_float, "Line diagnostic")
  end,
})

-- Capabilities (optional: improves completion if you use nvim-cmp)
local capabilities = vim.lsp.protocol.make_client_capabilities()
local ok_cmp, cmp_nvim_lsp = pcall(require, "cmp_nvim_lsp")
if ok_cmp then
  capabilities = cmp_nvim_lsp.default_capabilities(capabilities)
end

local servers = {
  "clangd",
  "omnisharp",
  "jdtls",
  "pyright",
  "ts_ls",
  "lua_ls",
  "vimls",
  "html",
  "cssls",
  "rust_analyzer",
}

-- Extend each server config with your local defaults.
-- (These configs are provided by nvim-lspconfig under runtimepath, and Neovim merges them.)
for _, name in ipairs(servers) do
  vim.lsp.config(name, {
    capabilities = capabilities,
  })
end

-- Lua-specific tweak so lua_ls knows about `vim`
vim.lsp.config("lua_ls", {
  settings = {
    Lua = {
      diagnostics = { globals = { "vim" } },
    },
  },
})

vim.lsp.config("clangd", {
    cmd = {
        "clangd",
        "--query-driver=C:/msys64/ucrt64/bin/g++.exe,C:/msys64/ucrt64/bin/gcc.exe",
    }
})

-- Finally enable all configs
vim.lsp.enable(servers)

vim.diagnostic.config({
    virtual_text = false,
    signs = true,
    underline = true,
    update_in_insert = false,
    severity_sort = true,
    float = { border = "rounded", source = "if_many" },
})

