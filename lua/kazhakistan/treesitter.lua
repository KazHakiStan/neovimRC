-- Treesitter (nvim-treesitter `main` branch): parsers + queries, highlighting.
-- Parsers are built locally, which needs the tree-sitter CLI and a C compiler
-- (setupRC installs both). Indentation stays with Vim's own indent scripts
-- (cindent for C/C++), treesitter indent is still experimental.
local M = {}

-- treesitter.parsers in the settings (~/.config/kazrc/nvim.lua)
M.parsers = require("kazhakistan.kazrc").get().treesitter.parsers

local function ts()
    local ok, mod = pcall(require, "nvim-treesitter")
    return ok and mod or nil
end

-- The tree-sitter CLI holds <cache>/tree-sitter/lock/<lang>.lock while it
-- builds a parser and removes it when done. A build cut short (nvim closed
-- mid-install) leaves it behind; the CLI clears such leftovers itself, except
-- on Windows, where it can't delete the file it holds open, and every later
-- build of that language fails. Remove them first: a lock a running build
-- holds can't be deleted on Windows, so this only takes the stale ones.
local function clear_stale_locks()
    if vim.fn.has("win32") ~= 1 or not vim.env.LOCALAPPDATA then return end
    local dir = vim.fs.joinpath(vim.env.LOCALAPPDATA, "tree-sitter", "lock")
    for name, kind in vim.fs.dir(dir) do
        if kind == "file" and name:match("%.lock$") then os.remove(vim.fs.joinpath(dir, name)) end
    end
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
    clear_stale_locks()
    return mod.install(M.parsers)
end

-- parsers of M.parsers that aren't installed (setupRC reports them)
function M.missing()
    local mod = ts()
    if not mod then return M.parsers end
    local have = {}
    for _, lang in ipairs(mod.get_installed("parsers")) do have[lang] = true end
    return vim.tbl_filter(function(lang) return not have[lang] end, M.parsers)
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
