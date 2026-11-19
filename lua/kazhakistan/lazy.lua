-- Plugins (lazy.nvim). Their settings live in after/plugin/<name>.lua, which
-- runs after every plugin here has loaded. Exact versions: lazy-lock.json
-- (committed); :Lazy update moves them, :Lazy restore goes back to the lock.

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
    local out = vim.fn.system({
        "git", "clone", "--filter=blob:none", "--branch=stable",
        "https://github.com/folke/lazy.nvim.git", lazypath,
    })
    if vim.v.shell_error ~= 0 then
        vim.api.nvim_echo({ { "Failed to clone lazy.nvim:\n", "ErrorMsg" }, { out, "WarningMsg" } }, true, {})
        return
    end
end
vim.opt.rtp:prepend(lazypath)

local spec = {
    -- Telescope
    { "nvim-telescope/telescope.nvim", branch = "master", dependencies = { "nvim-lua/plenary.nvim" } },

    -- Colorschemes (kazhakistan.theme picks one)
    { "rose-pine/neovim", name = "rose-pine" },
    "nyoom-engineering/oxocarbon.nvim",
    "kdheepak/monochrome.nvim",
    "ficd0/ashen.nvim",
    { "sainnhe/gruvbox-material", name = "gruvbox" },

    -- Treesitter: new API; parsers via lua/kazhakistan/treesitter.lua
    { "nvim-treesitter/nvim-treesitter", branch = "main", build = ":TSUpdate" },

    "kazhakistan/cheatsheet.nvim",

    "theprimeagen/vim-be-good",
    { "theprimeagen/harpoon", branch = "harpoon2", dependencies = { "nvim-lua/plenary.nvim" } },
    "mbbill/undotree",
    "tpope/vim-fugitive",

    -- LSP
    "neovim/nvim-lspconfig",
    "williamboman/mason.nvim",
    "williamboman/mason-lspconfig.nvim",
    "seblyng/roslyn.nvim",
    "jlcrochet/vim-razor",

    -- completion: LSP, paths, words, snippets (friendly-snippets) in one plugin;
    -- a release version so it downloads its prebuilt matcher
    { "saghen/blink.cmp", version = "1.*", dependencies = { "rafamadriz/friendly-snippets" } },
    "windwp/nvim-autopairs",
    -- <button> gets its </button>; renaming a tag renames its pair (xml, html, jsx…)
    "windwp/nvim-ts-autotag",

    -- popup listing what the keys you started typing can continue into
    "folke/which-key.nvim",

    -- formatting: <leader>f, and on save where the project has a formatter config
    "stevearc/conform.nvim",

    -- changed lines in the sign column, hunk preview / stage / blame
    "lewis6991/gitsigns.nvim",

    "rmagatti/auto-session",

    -- databases
    "tpope/vim-dadbod",
    "kristijanhusak/vim-dadbod-ui",
    "kristijanhusak/vim-dadbod-completion",

    { "delphinus/md-render.nvim", dependencies = { "nvim-tree/nvim-web-devicons" } },

    -- Debugger UI (lldb-dap for Xcode projects: lua/kazhakistan/xcode)
    { "rcarriga/nvim-dap-ui", dependencies = { "mfussenegger/nvim-dap", "nvim-neotest/nvim-nio" } },
    -- variable values next to the code while stopped in the debugger
    { "theHamsta/nvim-dap-virtual-text", dependencies = { "mfussenegger/nvim-dap" } },
}

-- your own specs (plugins in ~/.config/kazrc/nvim.lua): extra plugins, or
-- { "<built-in>", enabled = false } to drop one
vim.list_extend(spec, require("kazhakistan.kazrc").get().plugins)

require("lazy").setup(spec, {
    -- everything loads at startup, like packer did
    defaults = { lazy = false },
    install = { missing = true },
    -- no colorscheme during the first install: kazhakistan.theme sets it
    ui = { border = "rounded" },
    change_detection = { notify = false },
    checker = { enabled = false },
    rocks = { enabled = false },
})
