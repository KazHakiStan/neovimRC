local ok, autosession = pcall(require, "auto-session")
if not ok then return end

vim.g._as_restored_for_new_cwd = false

local function open_only_netrw()
    if vim.fn.argc() > 0 then
        return
    end
    vim.cmd("tabonly")
    vim.cmd("only")
    vim.cmd("enew")
    vim.cmd("Ex")
end

autosession.setup({
  allowed_dirs = {
      vim.fn.expand("/users/danila/projects/"),
      vim.fn.expand("/users/danila/.config"),
  },

  suppressed_dirs = {
  },

  auto_save = true,
  auto_restore = true,

  cwd_change_handling = true,

  no_restore_cmds = {
    open_only_netrw,
  },
})
