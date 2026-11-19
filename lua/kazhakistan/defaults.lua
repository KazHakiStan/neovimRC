-- Default settings. Don't edit them here: ~/.config/kazrc/nvim.lua (created
-- on first start, :KazConfig opens it) overrides any of them, and this repo
-- stays clean for updates. Tables merge key by key; lists replace whole.
return {
    leader = " ",

    -- folders put in front of PATH for nvim and everything it starts (clangd,
    -- compilers for treesitter parsers, :make, the terminal), e.g. MSYS2 on
    -- Windows: { "C:/msys64/ucrt64/bin" }
    path = {},

    -- any vim option (:help option-list), set at startup and on save
    options = {
        number = true,
        relativenumber = true,
        tabstop = 4,
        softtabstop = 4,
        shiftwidth = 4,
        expandtab = true,
        wrap = true,
        scrolloff = 8,
        colorcolumn = "80",
        signcolumn = "yes",
        hlsearch = false,
        undofile = true,
        updatetime = 50,
    },

    theme = {
        -- :Theme cycles through these; keep them in step with WezTerm's
        -- (~/.config/kazrc/wezterm.lua) so both switch together
        order = { "ashen", "aegis-lavender", "aegis-gold", "metaphor-light" },
        default = "ashen",
    },

    completion = {
        -- Tab while the list is open: "select" moves through it (Enter accepts),
        -- "accept" takes the highlighted item. :CompletionTab switches for now.
        tab = "select",
        documentation_delay_ms = 300,
    },

    projects = {
        -- cd to the project of the file you open (Telescope, grep, :e search there)
        auto_cd = true,
        -- a project outside git is the nearest folder with one of these
        markers = { "Makefile", "package.json", "pyproject.toml", "*.sln" },
    },

    -- delay before which-key lists how a started key sequence continues
    key_hints_delay_ms = 400,

    git = {
        line_blame = false, -- blame at the end of every line (<leader>gB toggles)
    },

    lsp = {
        -- language servers to start (nvim-lspconfig names)
        servers = { "clangd", "jdtls", "pyright", "ts_ls", "lua_ls", "vimls", "html", "cssls",
            "rust_analyzer", "powershell_es" },
        -- the ones Mason installs (jdtls needs Java: install it yourself)
        install = { "clangd", "pyright", "ts_ls", "lua_ls", "vimls", "html", "cssls",
            "rust_analyzer", "powershell_es" },
        -- on top of any server's config (what vim.lsp.config takes), e.g.
        --   clangd = { cmd = { "clangd", "--query-driver=C:/msys64/ucrt64/bin/g++.exe" } },
        config = {},
    },

    treesitter = {
        -- installed up front; any other language installs when first opened
        parsers = { "bash", "c", "cpp", "objc", "c_sharp", "css", "html", "javascript", "json",
            "lua", "markdown", "markdown_inline", "python", "query", "rust", "typescript",
            "vim", "vimdoc" },
    },

    -- your own lazy.nvim plugin specs, added to the built-in ones, e.g.
    --   { "folke/flash.nvim", opts = {} },
    --   { "theprimeagen/vim-be-good", enabled = false },   -- drop a built-in one
    plugins = {},

    -- your own keymaps, autocmds, anything: runs last, after every plugin
    -- setup = function() vim.keymap.set("n", "<leader>z", "<cmd>ZenMode<cr>") end,
    setup = nil,
}
