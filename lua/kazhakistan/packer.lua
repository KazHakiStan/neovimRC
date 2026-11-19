local ensure_packer = function()
  local fn = vim.fn
  local install_path = fn.stdpath("data") .. "/site/pack/packer/start/packer.nvim"
  if fn.empty(fn.glob(install_path)) > 0 then
    fn.system({
      "git",
      "clone",
      "--depth",
      "1",
      "https://github.com/wbthomason/packer.nvim",
      install_path,
    })
    vim.cmd("packadd packer.nvim")
    return true
  end
  return false
end

local packer_bootstrap = ensure_packer()

return require("packer").startup(function(use)
  use("wbthomason/packer.nvim")

  -- Telescope
  use({
    "nvim-telescope/telescope.nvim",
    branch = "master",
    requires = { "nvim-lua/plenary.nvim" },
  })

  -- Colorscheme
  use({ "rose-pine/neovim", as = "rose-pine" })
  use('nyoom-engineering/oxocarbon.nvim')
  use('kdheepak/monochrome.nvim')
  use({'ficd0/ashen.nvim'})
  use({ "sainnhe/gruvbox-material", as = "gruvbox" })

  -- Treesitter
  use({
    "nvim-treesitter/nvim-treesitter",
    branch = "main", -- new API; parsers via lua/kazhakistan/treesitter.lua
    run = ":TSUpdate",
  })

  -- Cheatsheet
  use('kazhakistan/cheatsheet.nvim')

  use('theprimeagen/vim-be-good')
  use('theprimeagen/harpoon')

  use('mbbill/undotree')

  use('tpope/vim-fugitive')

  use('neovim/nvim-lspconfig')

  use('williamboman/mason.nvim')

  use('williamboman/mason-lspconfig.nvim')
  -- completion: LSP, paths, words, snippets (friendly-snippets) in one plugin;
  -- a release tag so it downloads its prebuilt matcher
  use({ "saghen/blink.cmp", tag = "v1.*", requires = { "rafamadriz/friendly-snippets" } })

  -- popup listing what the keys you started typing can continue into
  use("folke/which-key.nvim")

  -- changed lines in the sign column, hunk preview / stage / blame
  use("lewis6991/gitsigns.nvim")

  use('windwp/nvim-autopairs')

  -- use('github/copilot.vim')
  --
  -- use({'CopilotC-Nvim/CopilotChat.nvim', requires = { 'nvim-lua/plenary.nvim' } })

  use({ "rmagatti/auto-session" })

  use ({ 'ahmedkhalf/project.nvim' })

  use({ "tpope/vim-dadbod" })
  use({ "kristijanhusak/vim-dadbod-ui" })
  use({ "kristijanhusak/vim-dadbod-completion" })

  use('jlcrochet/vim-razor')

  use({ "seblyng/roslyn.nvim" })

  use({
    "delphinus/md-render.nvim",
    requires = { "nvim-tree/nvim-web-devicons" },
  })

  -- Debugger UI (lldb-dap for Xcode projects: lua/kazhakistan/xcode)
  use({
    "rcarriga/nvim-dap-ui",
    requires = { "mfussenegger/nvim-dap", "nvim-neotest/nvim-nio" },
  })
  -- variable values next to the code while stopped in the debugger
  use({ "theHamsta/nvim-dap-virtual-text", requires = { "mfussenegger/nvim-dap" } })

  if packer_bootstrap then
    require("packer").sync()
  end
end)

