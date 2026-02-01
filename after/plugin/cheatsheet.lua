local ok, cs = pcall(require, "cheatsheet")
if not ok then
  vim.notify("cheatsheet not found: " .. tostring(cs), vim.log.levels.ERROR)
  return
end

cs.setup()

