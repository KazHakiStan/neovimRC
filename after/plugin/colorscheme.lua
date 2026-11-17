-- Shared themes (synced with wezterm): ashen, aegis-lavender, aegis-gold, metaphor-light
--   :Theme            cycle
--   :Theme <name>     set
--   :Theme list       show all (current marked with *)
-- Ad-hoc (not synced): C("rose-pine"), S("light")
-- other schemes: gruvbox-material, rose-pine, oxocarbon, monochrome
local theme = require("kazhakistan.theme")

function ColorMyPencils(color)
    color = color or theme.default
    if theme.themes[color] then
        theme.apply(color)
        return
    end
    vim.cmd.colorscheme(color)
    vim.api.nvim_set_hl(0, "Normal", { bg = "none" })
    vim.api.nvim_set_hl(0, "NormalFloat", { bg = "none" })
end

function SwitchTheme(mode)
    vim.o.background = mode or "dark"
    vim.api.nvim_set_hl(0, "Normal", { bg = "none" })
    vim.api.nvim_set_hl(0, "NormalFloat", { bg = "none" })
end

function C(color) ColorMyPencils(color) end
function S(mode) SwitchTheme(mode) end
function Sl() SwitchTheme("light") end
function Sd() SwitchTheme("dark") end

theme.setup()
