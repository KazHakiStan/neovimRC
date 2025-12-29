local caps = vim.lsp.protocol.make_client_capabilities()
local ok_cmp, cmp_lsp = pcall(require, "cmp_nvim_lsp")
if ok_cmp then
  caps = cmp_lsp.default_capabilities(caps)
end

vim.lsp.config("roslyn", {
  capabilities = caps,
})

vim.lsp.enable("roslyn")

