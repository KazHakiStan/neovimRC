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

    -- Neovim's own LSP keys work too: grr references, grn rename, gra code
    -- action, gri implementation, grt type definition, gO symbols, K hover,
    -- [d / ]d diagnostics, <C-s> signature help in insert mode
    nmap("gd", vim.lsp.buf.definition, "Go to definition")
    nmap("gD", vim.lsp.buf.declaration, "Go to declaration")
    -- gs is :sleep by default, nothing worth keeping
    nmap("gs", function() vim.cmd("vsplit") vim.lsp.buf.definition() end, "Definition in a vertical split")
    nmap("gS", function() vim.cmd("vsplit") vim.lsp.buf.declaration() end, "Declaration in a vertical split")
    nmap("<leader>rn", vim.lsp.buf.rename, "Rename")
    nmap("<leader>ca", vim.lsp.buf.code_action, "Code action")
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
local servers = vim.tbl_filter(function(name)
  -- powershell_es runs through pwsh: without it (macOS by default) opening a
  -- .ps1 would throw instead of just going without a server
  return name ~= "powershell_es" or vim.fn.executable("pwsh") == 1
end, lsp_settings.servers)

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

-- jdtls runs on Java 21+, which may not be the system Java: found when the
-- first .java file opens, and handed to jdtls as its JAVA_HOME
local java_wanted = vim.tbl_contains(servers, "jdtls")
servers = vim.tbl_filter(function(name) return name ~= "jdtls" end, servers)
if java_wanted then
  vim.api.nvim_create_autocmd("FileType", {
    pattern = "java",
    once = true,
    callback = function()
      local jdk = require("kazhakistan.platform").jdk(21)
      if not jdk then
        vim.notify("jdtls needs Java 21+ (setupRC installs it: temurin@21 / temurin21-jdk)", vim.log.levels.WARN)
        return
      end
      vim.lsp.config("jdtls", { cmd_env = { JAVA_HOME = jdk } })
      vim.lsp.enable("jdtls")
    end,
  })
end

-- Finally enable all configs
vim.lsp.enable(servers)

vim.diagnostic.config({
    virtual_text = false,
    -- the message under the line, only on the cursor's line: readable without
    -- cluttering the code
    virtual_lines = { current_line = true },
    signs = true,
    underline = true,
    update_in_insert = false,
    severity_sort = true,
    float = { border = "rounded", source = "if_many" },
})

-- :LspRestart, :LspInfo come from nvim-lspconfig
