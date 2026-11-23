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

-- Demi-fiend (assets/demifiend.png in wezterm): jade markings and their mint
-- glow, the chartreuse eyes, Pixie's blue; errors a clear red against the green
local demifiend = {
    red_flame         = "#FF5F5F", -- errors
    red_glowing       = "#9EF0CC", -- strings: mint glow
    red_ember         = "#35B88A", -- main accent / ANSI red: jade
    orange_glow       = "#D8E070", -- CurSearch / ANSI green: the eyes
    orange_blaze      = "#4FD1C5", -- constants: teal
    orange_smolder    = "#E6C85A", -- ANSI yellow
    orange_golden     = "#F0C040", -- warnings
    red_kindling      = "#5CC9A0",
    red_burnt_crimson = "#2E9E78",
    red_brick         = "#24785C",
    red_deep_ember    = "#1F5A42",
    red_ashen         = "#174A35",
    blue              = "#5A9FD4", -- Pixie's blue
    blue_dark         = "#2A5E7A",
}

-- Atomic Heart (assets/atomic-heart.png in wezterm): Soviet red, gold,
-- brass, chrome and one cool steel blue
local atomic = {
    red_flame         = "#FF4A4A", -- errors
    red_glowing       = "#E0B562", -- strings: gold
    red_ember         = "#C8283C", -- main accent / ANSI red: the star
    orange_glow       = "#ECD9B0", -- CurSearch / ANSI green: pale gold
    orange_blaze      = "#D88A5A", -- constants: copper
    orange_smolder    = "#C8924A", -- ANSI yellow: brass
    orange_golden     = "#F0B030", -- warnings
    red_kindling      = "#D8485A",
    red_burnt_crimson = "#A82034",
    red_brick         = "#8A1E2E",
    red_deep_ember    = "#6B1F2A",
    red_ashen         = "#5A1A24",
    blue              = "#8FA3B8", -- steel
    blue_dark         = "#4F6378",
}

-- The Illusive Man (assets/illusive-man-glass.png in wezterm): Paragon blue,
-- the star's ice, a warm ember; errors in Renegade red
local illusive = {
    red_flame         = "#FF5F6A", -- errors: Renegade red
    red_glowing       = "#A4CEF9", -- strings: ice
    red_ember         = "#4A9FE0", -- main accent / ANSI red: Paragon blue
    orange_glow       = "#7FD8F0", -- CurSearch / ANSI green: cyan corona
    orange_blaze      = "#E8A050", -- constants: the ember
    orange_smolder    = "#E8C070", -- ANSI yellow
    orange_golden     = "#F0B040", -- warnings
    red_kindling      = "#6AB4EC",
    red_burnt_crimson = "#3A80C0",
    red_brick         = "#2E5E98",
    red_deep_ember    = "#2E476C",
    red_ashen         = "#1F3152",
    blue              = "#7A8CE0", -- indigo
    blue_dark         = "#46529A",
}

-- SMT V: Vengeance, Taito (assets/smtvv-taito.png in wezterm):
-- ultramarine, shafts of cyan light, a pale sand
local taito = {
    red_flame         = "#FF5F6A", -- errors
    red_glowing       = "#A0D7ED", -- strings: light shafts
    red_ember         = "#6F8CFF", -- main accent / ANSI red: ultramarine
    orange_glow       = "#7FE0F0", -- CurSearch / ANSI green: cyan
    orange_blaze      = "#B0C4FF", -- constants: pale blue
    orange_smolder    = "#E8D8A0", -- ANSI yellow: sand
    orange_golden     = "#F0C060", -- warnings
    red_kindling      = "#8CA4FF",
    red_burnt_crimson = "#4A67D0",
    red_brick         = "#3A4FB6",
    red_deep_ember    = "#2D33A1",
    red_ashen         = "#232A6E",
    blue              = "#4FB0E0",
    blue_dark         = "#2E6A9A",
}

-- Persona 4, the Midnight Channel studio (assets/persona4-tv.png in
-- wezterm): TV yellow, stage-light amber, the screens' blue glow
local p4 = {
    red_flame         = "#FF5A4A", -- errors
    red_glowing       = "#FBF250", -- strings: the screens' yellow
    red_ember         = "#F4C430", -- main accent / ANSI red: Persona 4 yellow
    orange_glow       = "#FFE89A", -- CurSearch / ANSI green: stage light
    orange_blaze      = "#E8873A", -- constants: amber
    orange_smolder    = "#D6A92C", -- ANSI yellow: gold
    orange_golden     = "#F0B030", -- warnings
    red_kindling      = "#F0D050",
    red_burnt_crimson = "#B5942A",
    red_brick         = "#976A1D",
    red_deep_ember    = "#76561D",
    red_ashen         = "#5A4515",
    blue              = "#5AA0D8", -- the screens' blue
    blue_dark         = "#2E5E8A",
}

-- Cyberpunk 2077: Phantom Liberty, Songbird before the red sphere
-- (assets/cyberpunk-songbird.png in wezterm): neon red, netrunner cyan, a
-- touch of Cyberpunk yellow; errors hot pink so they part from the accent
local songbird = {
    red_flame         = "#FF4D8D", -- errors: hot pink
    red_glowing       = "#5FC8D8", -- strings: netrunner cyan
    red_ember         = "#E62E4B", -- main accent / ANSI red: neon red
    orange_glow       = "#8FE0EC", -- CurSearch / ANSI green: pale cyan
    orange_blaze      = "#FF6A7E", -- constants: light red
    orange_smolder    = "#E8D44A", -- ANSI yellow: Cyberpunk yellow
    orange_golden     = "#F0B040", -- warnings
    red_kindling      = "#F04A62",
    red_burnt_crimson = "#D41F32",
    red_brick         = "#982129",
    red_deep_ember    = "#6E2A30",
    red_ashen         = "#562B2E",
    blue              = "#3F8FA8", -- cable teal
    blue_dark         = "#1A3A47",
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
    ["demifiend"] = function()
        load_ashen(demifiend)
        transparent()
        hl("StatusLineNC", { bg = "#121212", fg = demifiend.red_ashen, bold = true })
        hl("LineNr", { fg = "#aaaaaa", bg = "#121212" })
        hl("CursorLineNr", { fg = demifiend.orange_glow, bold = true })
    end,
    ["atomic-heart"] = function()
        load_ashen(atomic)
        transparent()
        hl("StatusLineNC", { bg = "#121212", fg = atomic.red_ashen, bold = true })
        hl("LineNr", { fg = "#aaaaaa", bg = "#121212" })
        hl("CursorLineNr", { fg = atomic.red_glowing, bold = true })
    end,
    ["illusive-man"] = function()
        load_ashen(illusive)
        transparent()
        hl("StatusLineNC", { bg = "#121212", fg = illusive.red_ashen, bold = true })
        hl("LineNr", { fg = "#aaaaaa", bg = "#121212" })
        hl("CursorLineNr", { fg = illusive.red_glowing, bold = true })
    end,
    ["smtvv-taito"] = function()
        load_ashen(taito)
        transparent()
        hl("StatusLineNC", { bg = "#121212", fg = taito.red_ashen, bold = true })
        hl("LineNr", { fg = "#aaaaaa", bg = "#121212" })
        hl("CursorLineNr", { fg = taito.orange_glow, bold = true })
    end,
    ["persona4-tv"] = function()
        load_ashen(p4)
        transparent()
        hl("StatusLineNC", { bg = "#121212", fg = p4.red_ashen, bold = true })
        hl("LineNr", { fg = "#aaaaaa", bg = "#121212" })
        hl("CursorLineNr", { fg = p4.red_glowing, bold = true })
    end,
    ["cyberpunk-songbird"] = function()
        load_ashen(songbird)
        transparent()
        hl("StatusLineNC", { bg = "#121212", fg = songbird.red_ashen, bold = true })
        hl("LineNr", { fg = "#aaaaaa", bg = "#121212" })
        hl("CursorLineNr", { fg = songbird.red_glowing, bold = true })
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

-- short names by colour (kazrc themes.lua aliases, shared with WezTerm):
-- :T mint = :T demifiend; themes that share one form a group
M.aliases = require("kazhakistan.kazrc").themes().aliases

-- a theme name or an alias -> the themes it means (in M.order)
function M.matches(name)
    if M.themes[name] then return { name } end
    return vim.tbl_filter(function(n) return M.aliases[n] == name end, M.order)
end

local function label(name)
    return M.aliases[name] and (name .. " (" .. M.aliases[name] .. ")") or name
end

-- theme.json: { theme = name, glass = { [theme] = bool } } (blur switched per
-- theme; WezTerm writes it too)
local function read_json()
    local ok, lines = pcall(vim.fn.readfile, M.state_file)
    if not ok or #lines == 0 then
        return {}
    end
    local ok2, data = pcall(vim.json.decode, table.concat(lines, "\n"))
    return (ok2 and type(data) == "table") and data or {}
end

local function read_state()
    local theme = read_json().theme
    return theme and M.matches(theme)[1] or nil
end

local function write_json(data)
    vim.fn.mkdir(vim.fn.fnamemodify(M.state_file, ":h"), "p")
    if type(data.glass) == "table" and next(data.glass) == nil then data.glass = nil end
    vim.fn.writefile({ vim.json.encode(data) }, M.state_file)
end

local function write_state(name)
    local data = read_json()
    data.theme = name
    write_json(data)
end

-- blur of the theme's WezTerm picture: nil if it has none (kazrc themes.lua
-- glass), else what was switched or its default
function M.glass(name)
    local default = require("kazhakistan.kazrc").themes().glass[name]
    if default == nil then return nil end
    local switched = (read_json().glass or {})[name]
    if switched ~= nil then return switched end
    return default
end

-- :T blur: the current theme's WezTerm picture blurred or not
function M.toggle_glass()
    local name = M.current
    local on = M.glass(name)
    if on == nil then
        return vim.notify(name .. " has no blurred picture", vim.log.levels.WARN)
    end
    local data = read_json()
    data.glass = type(data.glass) == "table" and data.glass or {}
    data.glass[name] = not on
    data.theme = name
    write_json(data)
    vim.notify(name .. ": blur " .. (on and "off" or "on"))
end

function M.apply(name)
    name = M.themes[name] and name or M.default
    M.themes[name]()
    M.current = name
end

-- choose a theme: arrows + <CR> in a Telescope dropdown (typing filters by
-- name or alias). Moving the selection previews the theme, in WezTerm too;
-- <Esc> goes back to the one before. Without Telescope: vim.ui.select.
local function pick(title, names)
    local function display(n)
        local glass = M.glass(n)
        return (n == M.current and "* " or "  ") .. label(n)
            .. (glass == nil and "" or (glass and "  · blur" or "  · blur off"))
    end
    if not pcall(require, "telescope.pickers") then
        return vim.ui.select(names, { prompt = title, format_item = display }, function(n)
            if n then M.set(n) end
        end)
    end
    local pickers, finders = require("telescope.pickers"), require("telescope.finders")
    local conf = require("telescope.config").values
    local actions, state = require("telescope.actions"), require("telescope.actions.state")
    local before, shown, chosen = M.current, M.current, false
    local function preview(n)
        if not n or n == shown then return end
        shown = n
        -- a short pause, so holding an arrow doesn't reload WezTerm on every step
        vim.defer_fn(function()
            if shown == n and not chosen then
                M.apply(n)
                write_state(n)
            end
        end, 120)
    end
    local current = vim.fn.index(names, M.current) + 1
    local picker = pickers.new(require("telescope.themes").get_dropdown({ previewer = false }), {
        prompt_title = title .. "   <CR> set · <Esc> back",
        finder = finders.new_table({
            results = names,
            entry_maker = function(n)
                return { value = n, ordinal = label(n), display = display(n) }
            end,
        }),
        sorter = conf.generic_sorter({}),
        default_selection_index = current > 0 and current or nil,
        attach_mappings = function(buf)
            actions.select_default:replace(function()
                local e = state.get_selected_entry()
                chosen = true
                actions.close(buf)
                if e then M.set(e.value) end
            end)
            -- closed any other way: back to the theme from before
            vim.api.nvim_create_autocmd("BufWipeout", {
                buffer = buf,
                once = true,
                callback = vim.schedule_wrap(function()
                    if not chosen and M.current ~= before then
                        M.apply(before)
                        write_state(before)
                    end
                end),
            })
            return true
        end,
    })
    local set_selection = picker.set_selection
    picker.set_selection = function(self, row)
        set_selection(self, row)
        local e = self:get_selection()
        if e then preview(e.value) end
    end
    picker:find()
end

-- set theme (a name, or an alias: a group asks which) and publish it to wezterm
function M.set(name)
    local found = M.matches(name)
    if #found == 0 then
        vim.notify("Unknown theme: " .. tostring(name) .. " (:Theme list)", vim.log.levels.ERROR)
    elseif #found > 1 then
        pick("Theme: " .. name, found)
    else
        M.apply(found[1])
        write_state(found[1])
    end
end

-- every theme to choose from (:T with no argument)
function M.choose()
    pick("Theme", M.order)
end

-- print every available theme, current one marked with *
function M.list()
    local lines = {}
    for _, n in ipairs(M.order) do
        local glass = M.glass(n)
        table.insert(lines, (n == M.current and "* " or "  ") .. label(n)
            .. (glass == nil and "" or (glass and "  · blur" or "  · blur off")))
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

    local function command(opts)
        if opts.args == "" then
            M.choose()
        elseif opts.args == "list" then
            M.list()
        elseif opts.args == "blur" then
            M.toggle_glass()
        else
            M.set(opts.args)
        end
    end
    local spec = {
        nargs = "?",
        complete = function(lead)
            local items = { "list", "blur" }
            for _, n in ipairs(M.order) do
                items[#items + 1] = n
                local alias = M.aliases[n]
                if alias and not vim.tbl_contains(items, alias) then items[#items + 1] = alias end
            end
            return vim.tbl_filter(function(i) return vim.startswith(i, lead) end, items)
        end,
        desc = "Set shared nvim/wezterm theme by name or alias (no arg = choose with a preview, list = show all, blur = toggle the picture's blur)",
    }
    vim.api.nvim_create_user_command("Theme", command, spec)
    -- short form; an exact name wins over the other T… commands
    vim.api.nvim_create_user_command("T", command, spec)
end

return M
