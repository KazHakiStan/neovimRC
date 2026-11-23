-- Settings = defaults.lua with ~/.config/kazrc/nvim.lua merged on top.
-- The user file is created on first start (every default, commented out) and
-- never breaks startup: a file that fails to load, an unknown setting or a
-- value of the wrong type is reported and skipped. Saving it applies options,
-- completion and project settings at once; plugins, LSP and parsers need a
-- restart.

local M = {}

M.dir = vim.fs.normalize(vim.fn.expand("~/.config/kazrc"))
M.file = M.dir .. "/nvim.lua"
M.themes_file = M.dir .. "/themes.lua"

-- Shared with WezTerm through ~/.config/kazrc/themes.lua (weztermRC writes the
-- same template; keep these defaults in step with its kazrc.lua).
local THEME_DEFAULTS = {
    order = { "ashen", "aegis-lavender", "aegis-gold", "demifiend", "atomic-heart", "illusive-man", "smtvv-taito", "persona4-tv", "cyberpunk-songbird", "metaphor-light", "silent-hunter" },
    default = "ashen",
    -- themes with a blurred (-glass) picture, and whether it is on by default;
    -- :T blur (nvim) and LEADER g (WezTerm) switch it for the current theme
    glass = {
        ["demifiend"] = true,
        ["atomic-heart"] = true,
        ["illusive-man"] = true,
        ["smtvv-taito"] = false,
        ["persona4-tv"] = false,
        ["cyberpunk-songbird"] = false,
    },
}
local THEMES_TEMPLATE = {
    "-- Themes shared by nvim and WezTerm (neovimRC + weztermRC). Below are the",
    "-- defaults, commented out: uncomment what you change. WezTerm applies it on",
    "-- save, nvim on the next start.",
    "return {",
    "--     -- LEADER t (WezTerm) and :Theme (nvim) cycle through these",
    '--     order = { "ashen", "aegis-lavender", "aegis-gold", "demifiend", "atomic-heart", "illusive-man", "smtvv-taito", "persona4-tv", "cyberpunk-songbird", "metaphor-light", "silent-hunter" },',
    "--     -- the theme before any is chosen",
    '--     default = "ashen",',
    "--     -- themes with a blurred (-glass) picture, and whether it is on by default;",
    "--     -- :T blur (nvim) and LEADER g (WezTerm) switch it for the current theme",
    "--     glass = {",
    '--         ["demifiend"] = true, ["atomic-heart"] = true, ["illusive-man"] = true,',
    '--         ["smtvv-taito"] = false, ["persona4-tv"] = false, ["cyberpunk-songbird"] = false,',
    "--     },",
    "}",
}

local function defaults_file()
    return vim.api.nvim_get_runtime_file("lua/kazhakistan/defaults.lua", false)[1]
end

-- tables whose keys are yours to add, and settings that default to nil
local OPEN = { options = true, ["lsp.config"] = true }
local OPTIONAL = { setup = "function" }

local problems = {}

local function is_list(t)
    return type(t) == "table" and (#t > 0 or next(t) == nil)
end

local function merge(base, over, path)
    local out = vim.deepcopy(base)
    for k, v in pairs(over) do
        local where = path == "" and tostring(k) or (path .. "." .. tostring(k))
        local d = base[k]
        if d == nil and OPTIONAL[where] then
            if type(v) ~= OPTIONAL[where] then
                problems[#problems + 1] = ("`%s` should be a %s"):format(where, OPTIONAL[where])
            else
                out[k] = v
            end
        elseif d == nil and OPEN[path] then
            if path == "options" and not pcall(vim.api.nvim_get_option_info2, k, {}) then
                problems[#problems + 1] = "unknown option `" .. k .. "`"
            else
                out[k] = v
            end
        elseif d == nil then
            problems[#problems + 1] = "unknown setting `" .. where .. "`"
        elseif type(v) ~= type(d) then
            problems[#problems + 1] = ("`%s` should be a %s, not a %s"):format(where, type(d), type(v))
        elseif type(v) == "table" and not is_list(d) then
            out[k] = merge(d, v, where)
        else
            out[k] = v
        end
    end
    return out
end

-- defaults.lua with every setting commented out, so the file documents itself
local function template(src)
    local body = src:match("\nreturn {\n(.*)\n}%s*$")
    if not body then return nil end
    local lines = {
        "-- Your nvim settings (neovimRC). Below is every default, commented out:",
        "-- uncomment what you want to change, together with the tables around it,",
        "-- e.g.   completion = {   tab = \"accept\",   },",
        "-- Saving applies path, options, completion and projects; plugins, LSP and",
        "-- parsers need a restart. Problems show up as a warning (:KazProblems).",
        "-- Defaults and what each setting does: " .. vim.fn.fnamemodify(defaults_file(), ":~"),
        "return {",
    }
    for line in (body .. "\n"):gmatch("([^\n]*)\n") do
        lines[#lines + 1] = line == "" and "" or ("-- " .. line)
    end
    lines[#lines + 1] = "}"
    return lines
end

local function create(src)
    if vim.uv.fs_stat(M.file) then return end
    local lines = template(src)
    if not lines then return end
    vim.fn.mkdir(M.dir, "p")
    pcall(vim.fn.writefile, lines, M.file)
end

local themes
-- { order, default } from ~/.config/kazrc/themes.lua over THEME_DEFAULTS
function M.themes()
    if themes then return themes end
    if not vim.uv.fs_stat(M.themes_file) then
        vim.fn.mkdir(M.dir, "p")
        pcall(vim.fn.writefile, THEMES_TEMPLATE, M.themes_file)
    end
    local user = {}
    local ok, res = pcall(dofile, M.themes_file)
    if not ok then
        problems[#problems + 1] = (tostring(res):gsub("^.-themes%.lua:", "themes.lua:"))
    elseif type(res) == "table" then
        user = res
    end
    themes = merge(THEME_DEFAULTS, user, "themes")
    return themes
end

function M.problem(msg)
    problems[#problems + 1] = msg
end

local settings
function M.get()
    if settings then return settings end
    problems = {}
    local file = defaults_file()
    local src = table.concat(vim.fn.readfile(file), "\n")
    local defaults = assert(loadstring(src, "@" .. file))()
    pcall(create, src)
    local user = {}
    if vim.uv.fs_stat(M.file) then
        local ok, res = pcall(dofile, M.file)
        if not ok then
            problems[#problems + 1] = (tostring(res):gsub("^.-nvim%.lua:", "nvim.lua:"))
        elseif type(res) ~= "table" then
            problems[#problems + 1] = "nvim.lua should `return { ... }`"
        else
            user = res
        end
    end
    settings = merge(defaults, user, "")
    return settings
end

-- one line (a longer message would stop startup at "Press ENTER"):
-- the first problem; :KazProblems lists them all
function M.report()
    if #problems == 0 then return end
    local more = #problems > 1 and ("  (+%d more: :KazProblems)"):format(#problems - 1) or ""
    local msg = "kazrc: " .. problems[1] .. more
    local width = vim.o.columns - 15
    if vim.fn.strdisplaywidth(msg) > width then
        msg = vim.fn.strcharpart(msg, 0, width - 1) .. "…"
    end
    vim.notify(msg, vim.log.levels.WARN)
end

function M.problems()
    if #problems == 0 then return vim.notify("kazrc: no problems") end
    vim.api.nvim_echo({ { "~/.config/kazrc/nvim.lua: these settings stay at their defaults\n  "
        .. table.concat(problems, "\n  "), "WarningMsg" } }, true, {})
end

-- vim options from `options`
function M.apply_options()
    for name, value in pairs(M.get().options) do
        local ok, err = pcall(function() vim.opt[name] = value end)
        if not ok then
            vim.notify(("kazrc: options.%s: %s"):format(name, err), vim.log.levels.WARN)
        end
    end
end

-- `path`: in front of PATH, once each (on save too)
function M.apply_path()
    local sep = vim.fn.has("win32") == 1 and ";" or ":"
    local current = vim.split(vim.env.PATH or "", sep, { plain = true })
    for i = #M.get().path, 1, -1 do
        local dir = vim.fs.normalize(vim.fn.expand(M.get().path[i]))
        if not vim.tbl_contains(current, dir) then
            if vim.fn.isdirectory(dir) == 0 then
                problems[#problems + 1] = "path: no folder " .. dir
            end
            table.insert(current, 1, dir)
        end
    end
    vim.env.PATH = table.concat(current, sep)
end

-- live parts on save; everything else on the next start
local function reload()
    settings = nil
    local s = M.get()
    M.apply_path()
    M.apply_options()
    vim.g.completion_tab = s.completion.tab
    if #problems > 0 then
        M.report()
    else
        vim.notify("Applied. Plugins, LSP servers and parsers change on the next start.",
            vim.log.levels.INFO, { title = "kazrc" })
    end
end

function M.setup()
    M.apply_path()
    local group = vim.api.nvim_create_augroup("Kazrc", { clear = true })
    vim.api.nvim_create_autocmd("BufWritePost", {
        group = group,
        pattern = M.file,
        callback = reload,
    })
    vim.api.nvim_create_autocmd("VimEnter", {
        group = group,
        once = true,
        callback = function()
            local s = M.get()
            if s.setup then
                local ok, err = pcall(s.setup)
                if not ok then problems[#problems + 1] = "setup(): " .. tostring(err) end
            end
            vim.schedule(M.report)
        end,
    })
    vim.api.nvim_create_user_command("KazProblems", M.problems, { desc = "What's wrong in ~/.config/kazrc/nvim.lua" })
    vim.api.nvim_create_user_command("KazConfig", function()
        vim.cmd.edit(vim.fn.fnameescape(M.file))
    end, { desc = "Edit your nvim settings (~/.config/kazrc/nvim.lua)" })
end

return M
