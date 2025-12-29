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

  use({ "sainnhe/gruvbox-material", as = "gruvbox" })

  -- Treesitter
  use({
    "nvim-treesitter/nvim-treesitter",
    run = ":TSUpdate",
  })

  use('theprimeagen/harpoon')

  use('mbbill/undotree')

  use('tpope/vim-fugitive')

  use('neovim/nvim-lspconfig')

  use('williamboman/mason.nvim')

  use('williamboman/mason-lspconfig.nvim')
  use('hrsh7th/nvim-cmp')
  use('hrsh7th/cmp-buffer')
  use('hrsh7th/cmp-path')
  use('hrsh7th/cmp-nvim-lsp')
  use('hrsh7th/cmp-nvim-lua')
  use('L3MON4D3/LuaSnip')
  use('saadparwaiz1/cmp_luasnip')
  use('rafamadriz/friendly-snippets')

  use('windwp/nvim-autopairs')

  use('github/copilot.vim')

  use({'CopilotC-Nvim/CopilotChat.nvim', requires = { 'nvim-lua/plenary.nvim' } })

  use({ "rmagatti/auto-session" })

  use ({ 'ahmedkhalf/project.nvim' })
  if packer_bootstrap then
    require("packer").sync()
  end
end)

