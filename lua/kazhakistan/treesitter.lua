-- Treesitter (nvim-treesitter `main` branch): parsers + queries, highlighting.
-- Parsers are built locally, which needs the tree-sitter CLI and a C compiler
-- (setupRC installs both). Indentation stays with Vim's own indent scripts
-- (cindent for C/C++), treesitter indent is still experimental.
local M = {}

M.parsers = {
    "bash", "c", "cpp", "objc", "c_sharp", "css", "html", "javascript", "json",
    "lua", "markdown", "markdown_inline", "python", "query", "rust", "typescript",
    "vim", "vimdoc",
}

local function ts()
    local ok, mod = pcall(require, "nvim-treesitter")
    return ok and mod or nil
end

-- install whatever of M.parsers is missing; returns the async task (:wait() it)
function M.install()
    local mod = ts()
    if not mod then return end
    if vim.fn.executable("tree-sitter") ~= 1 then
        vim.notify("treesitter: tree-sitter CLI missing (brew install tree-sitter-cli / scoop install tree-sitter)",
            vim.log.levels.WARN)
        return
    end
    return mod.install(M.parsers)
end

-- Treesitter highlighting turns Vim's regex syntax off, but some of Vim's
-- indent scripts read it: XML's indents nothing without it. These keep it on
-- underneath (treesitter colours still win).
local KEEP_SYNTAX = { xml = true, xsd = true, xslt = true, svg = true, xhtml = true }

local function start(buf, lang)
    if not pcall(vim.treesitter.start, buf, lang) then return end
    local ft = vim.bo[buf].filetype
    if KEEP_SYNTAX[ft] then vim.bo[buf].syntax = ft end
    return true
end

function M.setup()
    local mod = ts()
    if not mod then return end
    M.install()

    local available
    vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("KazTreesitter", { clear = true }),
        callback = function(ev)
            local lang = vim.treesitter.language.get_lang(ev.match)
            if not lang or start(ev.buf, lang) then return end
            -- a language outside M.parsers: install it the first time it's opened
            available = available or mod.get_available()
            if not vim.tbl_contains(available, lang) or vim.fn.executable("tree-sitter") ~= 1 then return end
            mod.install({ lang }):await(function(err)
                if err then return end
                vim.schedule(function()
                    if vim.api.nvim_buf_is_valid(ev.buf) then start(ev.buf, lang) end
                end)
            end)
        end,
    })
end

return M
