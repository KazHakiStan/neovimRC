local lsp_settings = require("kazhakistan.kazrc").get().lsp

local ok_mason, mason = pcall(require, "mason")
local ok_mason_lsp, mason_lspconfig = pcall(require, "mason-lspconfig")
if not (ok_mason and ok_mason_lsp) then
  return
end

mason.setup({
    registries = {
        "github:mason-org/mason-registry",
        "github:Crashdummyy/mason-registry",
    }
})

-- Install servers with Mason, but DON'T auto-enable yet.
-- We'll configure first, then enable explicitly.
mason_lspconfig.setup({
  -- lsp.install in the settings (~/.config/kazrc/nvim.lua)
  ensure_installed = lsp_settings.install,
  automatic_enable = false,
})

-- Keymaps when LSP attaches (native way)
vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(args)
    local bufnr = args.buf

    local nmap = function(keys, func, desc)
      vim.keymap.set("n", keys, func, { buffer = bufnr, desc = desc })
    end

    nmap("sd", function() vim.cmd("vsplit") vim.lsp.buf.definition() end, "Split the definition")
    nmap("gd", vim.lsp.buf.definition, "Go to definition")
    nmap("sD", function() vim.cmd("vsplit") vim.lsp.buf.declaration() end, "Split the declaration")
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

-- Capabilities: what blink.cmp's completion supports
local capabilities = vim.lsp.protocol.make_client_capabilities()
local ok_blink, blink = pcall(require, "blink.cmp")
if ok_blink then
  capabilities = blink.get_lsp_capabilities(capabilities)
end

-- lsp.servers in the settings (~/.config/kazrc/nvim.lua)
local servers = lsp_settings.servers

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
        runtime = { version = "LuaJIT" },
        diagnostics = { globals = { "vim" } },
        workspace = {
            checkThirdParty = false,
            library = {
                vim.env.VIMRUNTIME,
                -- vim.fn.stdpath("config") .. "/lua"
            },
        },
        completion = {
            callSnippet = "Replace",
        },
        telemetry = { enable = false },
    },
  },
})

vim.lsp.config("powershell_es", {
    bundle_path = vim.fn.stdpath("data") .. "/mason/packages/powershell-editor-services",
    shell = "pwsh",
})

vim.lsp.config("clangd", { cmd = require("kazhakistan.platform").clangd_cmd() })

-- yours last, so they win: lsp.config in ~/.config/kazrc/nvim.lua
for name, cfg in pairs(lsp_settings.config) do
  vim.lsp.config(name, cfg)
end

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

vim.api.nvim_create_user_command("LspRestart", function()
    local clients = vim.lsp.get_clients({ bufnr = 0 })

    for _, client in ipairs(clients) do
        client:stop()
    end

    vim.defer_fn(function()
        vim.cmd("edit")
    end, 500)
end, {})

vim.api.nvim_create_user_command("LspInfo", function()
    vim.cmd("checkhealth vim.lsp")
end, {})
