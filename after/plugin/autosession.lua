local ok, autosession = pcall(require, "auto-session")
if not ok then return end

vim.g._as_restored_for_new_cwd = false

local function open_only_netrw()
  vim.cmd("tabonly")
  vim.cmd("only")
  vim.cmd("enew")
  vim.cmd("Ex")
end

autosession.setup({
  allowed_dirs = {
      "C:/projects/*/*", "C:/projects/*",
  },

  suppressed_dirs = {
    "C:/projects/_templates",
    "C:/Users/User/AppData/Local/nvim"
  },

  auto_save = true,
  auto_restore = true,

  cwd_change_handling = true,

  no_restore_cmds = {
    open_only_netrw,
  },
})

