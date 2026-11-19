local caps = vim.lsp.protocol.make_client_capabilities()
local ok_blink, blink = pcall(require, "blink.cmp")
if ok_blink then
  caps = blink.get_lsp_capabilities(caps)
end

vim.lsp.config("roslyn", {
  capabilities = caps,
})

vim.lsp.enable("roslyn")

