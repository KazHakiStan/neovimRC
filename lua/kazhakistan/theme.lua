-- Shared theme switching between nvim and wezterm.
-- Source of truth: ~/.config/kazrc/theme.json -> {"theme":"<name>"}
-- wezterm watches the same file, so switching here re-themes the terminal
-- and switching in wezterm (LEADER t) re-themes every running nvim.

local M = {}

M.state_file = vim.fn.expand("~/.config/kazrc/theme.json")
local legacy_file = vim.fn.expand("~/.config/theme.json") -- before kazrc
-- order and default: ~/.config/kazrc/themes.lua, shared with WezTerm
M.order = require("kazhakistan.kazrc").themes().order
M.default = require("kazhakistan.kazrc").themes().default
M.current = nil

-- ashen palette keys remapped to the aegis-lavender picture
-- (lavender #cc9cfc, violet #6c3c84, neon cyan #3cfcfc, teal #0c6c6c)
local lavender = {
    red_flame         = "#FF5FA2", -- errors: neon pink so they still pop
    red_glowing       = "#E4A8FC", -- strings
    red_ember         = "#B98AF0", -- main accent / ANSI red
    orange_glow       = "#3CF0F0", -- CurSearch / ANSI green
    orange_blaze      = "#6FC8E8", -- constants
    orange_smolder    = "#E08CD8", -- ANSI yellow
    orange_golden     = "#F0B0D8", -- warnings
    red_kindling      = "#C99AF5",
    red_burnt_crimson = "#A57FD6",
    red_brick         = "#7A5A9E",
    red_deep_ember    = "#6C3C84",
    red_ashen         = "#543C6C",
    blue              = "#2FB8C0",
    blue_dark         = "#0C6C6C",
}

-- Metaphor-like gold (assets/aegis-gold.png in wezterm): amber gold, parchment,
-- one cool jade for contrast; errors stay a warm red-orange so they read as errors
local gold = {
    red_flame         = "#FF6B4A", -- errors
    red_glowing       = "#F0D58A", -- strings: light gold
    red_ember         = "#D4A13F", -- main accent / ANSI red
    orange_glow       = "#F2E6C4", -- CurSearch / ANSI green: parchment
    orange_blaze      = "#C98A3A", -- constants: bronze
    orange_smolder    = "#E0A040", -- ANSI yellow: amber
    orange_golden     = "#F0B030", -- warnings
    red_kindling      = "#D9B25A",
    red_burnt_crimson = "#B08A40",
    red_brick         = "#8A6A30",
    red_deep_ember    = "#7A5A24",
    red_ashen         = "#5A4520",
    blue              = "#5F9E8F", -- jade
    blue_dark         = "#3A6E60",
}

-- metaphor-light: gruvbox-material recoloured for the parchment print in wezterm.
-- Full Metaphor palette (also the terminal ANSI colours in wezterm):
local mp = {
    ink = "#3b2a1a", ink_deep = "#2c1f12", crimson = "#a30d1f", sienna = "#96461a",
    gold = "#7a5806", laurel = "#4f5e1e", jade = "#24605a", royal = "#2b5585",
    plum = "#7a3c6c", sepia = "#74624a", sepia_dark = "#62523c", gold_leaf = "#f0d38c",
}
-- Code uses only ink + crimson + gold ("mono"): with treesitter, gruvbox-material
-- paints keyword red, function green bold, string aqua, field blue, type yellow
-- italic, number/boolean purple, operator orange, comment grey1 italic.
local metaphor_light = {
    fg0    = { mp.ink, "237" },
    fg1    = { mp.ink_deep, "237" },
    red    = { mp.crimson, "88" },      -- keywords
    purple = { mp.crimson, "88" },      -- numbers, booleans, builtins
    aqua   = { mp.gold, "136" },        -- strings
    yellow = { mp.gold, "136" },        -- types (italic)
    green  = { mp.ink_deep, "237" },    -- functions (bold: shape, not colour)
    blue   = { mp.ink, "237" },         -- fields, properties
    orange = { mp.sepia_dark, "243" },  -- operators, quiet
    grey0  = { "#8a7758", "246" },
    grey1  = { mp.sepia, "245" },       -- comments (italic)
    grey2  = { mp.sepia_dark, "243" },
    bg3    = { mp.gold_leaf, "223" },   -- Visual
}

-- the mono override also hits UI groups that share those palette slots; give
-- git, diagnostics and :terminal their meaningful colours back
local function metaphor_light_semantics()
    local function fg(names, color)
        for _, n in ipairs(names) do
            local h = vim.api.nvim_get_hl(0, { name = n, link = false })
            h.fg = color
            vim.api.nvim_set_hl(0, n, h)
        end
    end
    fg({ "Added", "diffAdded", "GitSignsAdd", "DiagnosticOk", "DiagnosticSignOk" }, mp.laurel)
    fg({ "Changed", "diffChanged", "GitSignsChange" }, mp.royal)
    fg({ "DiagnosticInfo", "DiagnosticSignInfo", "DiagnosticVirtualTextInfo", "DiagnosticFloatingInfo" }, mp.royal)
    fg({ "DiagnosticHint", "DiagnosticSignHint", "DiagnosticVirtualTextHint", "DiagnosticFloatingHint" }, mp.jade)
    -- gruvbox-material draws these with bg5 (#ddccab): fine on flat parchment,
    -- invisible over the print (contrast ~1.1)
    fg({ "LineNr", "LineNrAbove", "LineNrBelow", "FoldColumn" }, mp.sepia)
    fg({ "WinSeparator", "VertSplit" }, mp.gold)
    vim.api.nvim_set_hl(0, "CursorLineNr", { fg = mp.gold, bold = true })
    local ansi = { "#fbf1c7", mp.crimson, mp.laurel, mp.gold, mp.royal, mp.plum, mp.jade, mp.sepia_dark,
        mp.sepia, mp.crimson, mp.laurel, mp.gold, mp.royal, mp.plum, mp.jade, mp.ink_deep }
    for i, c in ipairs(ansi) do
        vim.g["terminal_color_" .. (i - 1)] = c
    end
end

local function hl(name, spec)
    vim.api.nvim_set_hl(0, name, spec)
end

-- let the wezterm background show through, inactive windows (NormalNC) included
local function transparent()
    hl("Normal", { bg = "none" })
    hl("NormalNC", { bg = "none" })
    hl("NormalFloat", { bg = "none" })
end

-- ashen mutates its cached palette in place, so drop all of its modules
-- before re-running setup, otherwise colors leak between variants.
local function load_ashen(colors)
    for name in pairs(package.loaded) do
        if name == "ashen" or name:match("^ashen%.") then
            package.loaded[name] = nil
        end
    end
    require("ashen").setup({ colors = colors or {} })
    vim.o.background = "dark"
    vim.cmd.colorscheme("ashen")
end

M.themes = {
    ["ashen"] = function()
        load_ashen()
        transparent()
        hl("StatusLineNC", { bg = "#121212", fg = "#6f2929", bold = true })
        hl("LineNr", { fg = "#aaaaaa", bg = "#121212" })
    end,
    ["aegis-lavender"] = function()
        load_ashen(lavender)
        transparent()
        hl("StatusLineNC", { bg = "#121212", fg = lavender.red_ashen, bold = true })
        hl("LineNr", { fg = "#aaaaaa", bg = "#121212" })
        hl("CursorLineNr", { fg = lavender.orange_glow, bold = true })
    end,
    ["aegis-gold"] = function()
        load_ashen(gold)
        transparent()
        hl("StatusLineNC", { bg = "#121212", fg = gold.red_ashen, bold = true })
        hl("LineNr", { fg = "#aaaaaa", bg = "#121212" })
        hl("CursorLineNr", { fg = gold.red_glowing, bold = true })
    end,
    -- legacy: gruvbox over the Silent Hunter 5 screenshot in WezTerm; to become
    -- a theme of its own in kazRC (and leave the defaults)
    ["silent-hunter"] = function()
        vim.o.background = "dark"
        vim.g.gruvbox_material_transparent_background = 1
        vim.cmd.colorscheme("gruvbox-material")
        vim.g.gruvbox_material_transparent_background = nil
        transparent()
    end,
    ["metaphor-light"] = function()
        vim.o.background = "light"
        vim.g.gruvbox_material_colors_override = metaphor_light
        vim.g.gruvbox_material_enable_bold = 1 -- bold functions: in mono they stand out by shape
        vim.g.gruvbox_material_transparent_background = 1 -- no fill on inactive windows, folds, signs
        vim.cmd.colorscheme("gruvbox-material")
        -- don't leak into a manual :C("gruvbox-material")
        vim.g.gruvbox_material_colors_override = nil
        vim.g.gruvbox_material_enable_bold = nil
        vim.g.gruvbox_material_transparent_background = nil
        transparent()
        metaphor_light_semantics()
    end,
}

-- names in themes.lua that this config has no theme for: skipped, reported
do
    local known = vim.tbl_filter(function(n)
        if M.themes[n] then return true end
        require("kazhakistan.kazrc").problem("themes.lua: no theme `" .. tostring(n) .. "` in nvim")
        return false
    end, M.order)
    M.order = #known > 0 and known or { "ashen" }
    if not M.themes[M.default] then
        require("kazhakistan.kazrc").problem("themes.lua: default `" .. tostring(M.default) .. "` isn't a theme")
        M.default = M.order[1]
    end
end

-- old names still found in theme.json
local legacy = { light = "metaphor-light" }

local function read_state()
    local ok, lines = pcall(vim.fn.readfile, M.state_file)
    if not ok or #lines == 0 then
        return nil
    end
    local ok2, data = pcall(vim.json.decode, table.concat(lines, "\n"))
    if ok2 and type(data) == "table" then
        local name = legacy[data.theme] or data.theme
        if M.themes[name] then
            return name
        end
    end
    return nil
end

local function write_state(name)
    vim.fn.mkdir(vim.fn.fnamemodify(M.state_file, ":h"), "p")
    vim.fn.writefile({ vim.json.encode({ theme = name }) }, M.state_file)
end

function M.apply(name)
    name = M.themes[name] and name or M.default
    M.themes[name]()
    M.current = name
end

-- set theme and publish it to wezterm
function M.set(name)
    if not M.themes[name] then
        vim.notify("Unknown theme: " .. tostring(name), vim.log.levels.ERROR)
        return
    end
    M.apply(name)
    write_state(name)
end

function M.cycle()
    local idx = 1
    for i, n in ipairs(M.order) do
        if n == M.current then
            idx = i
        end
    end
    M.set(M.order[idx % #M.order + 1])
end

-- print every available theme, current one marked with *
function M.list()
    local lines = {}
    for _, n in ipairs(M.order) do
        table.insert(lines, (n == M.current and "* " or "  ") .. n)
    end
    vim.api.nvim_echo({ { table.concat(lines, "\n") } }, false, {})
end

function M.sync()
    local name = read_state() or M.default
    if name ~= M.current then
        M.apply(name)
    end
end

-- re-arm after every event: some writers replace the file, which ends the watch
function M.watch()
    if M._watcher then
        return
    end
    local w = vim.uv.new_fs_event()
    if not w then
        return
    end
    M._watcher = w
    local function start()
        w:start(M.state_file, {}, function()
            w:stop()
            vim.defer_fn(function()
                M.sync()
                start()
            end, 100)
        end)
    end
    start()
end

function M.setup()
    if vim.fn.filereadable(M.state_file) == 0 then
        -- moved into ~/.config/kazrc: carry the old choice over once
        local old = vim.fn.filereadable(legacy_file) == 1 and vim.fn.readfile(legacy_file) or nil
        if old and #old > 0 then
            vim.fn.mkdir(vim.fn.fnamemodify(M.state_file, ":h"), "p")
            vim.fn.writefile(old, M.state_file)
        else
            write_state(M.default)
        end
    end
    M.sync()
    M.watch()

    vim.api.nvim_create_user_command("Theme", function(opts)
        if opts.args == "" then
            M.cycle()
        elseif opts.args == "list" then
            M.list()
        else
            M.set(opts.args)
        end
    end, {
        nargs = "?",
        complete = function()
            return vim.list_extend({ "list" }, M.order)
        end,
        desc = "Set shared nvim/wezterm theme (no arg = cycle, list = show all)",
    })
end

return M
