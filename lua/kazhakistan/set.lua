require("kazhakistan.platform").setup_shell()

vim.opt.shada = "!,'100,<50,s10,h"

vim.opt.guicursor = {
  "n-v-c:block",
  "i-ci-ve:block",
  "r-cr-o:block",
  "sm:block",
}

vim.opt.swapfile = false
vim.opt.backup = false

vim.opt.incsearch = true

vim.opt.termguicolors = true

vim.opt.isfname:append("@-@")

vim.opt.showtabline = 2

vim.opt.sessionoptions = {
    "buffers",
    "curdir",
    "tabpages",
    "winsize",
    "folds",
    "help",
    "globals",
    "winpos",
    "terminal",
}

vim.g.db_ui_use_nerd_fonts = 1

-- numbers, indentation, wrap, scrolloff, ...: `options` in the settings
-- (defaults.lua, ~/.config/kazrc/nvim.lua), applied last so they win
require("kazhakistan.kazrc").apply_options()
