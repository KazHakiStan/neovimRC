-- Shared themes (synced with wezterm): ashen, aegis-lavender, aegis-gold, demifiend, atomic-heart, illusive-man, smtvv-taito, persona4-tv, cyberpunk-songbird, metaphor-light
--   :Theme            cycle                (:T is the same command, shorter)
--   :Theme <name>     set, by name or alias: :T mint = :Theme demifiend
--   :Theme list       show all with aliases (current marked with *)
--   :Theme blur       blur the WezTerm picture on/off (themes that have one)
local theme = require("kazhakistan.theme")

-- TODO: your own colours inside the shared theme system. These helpers set
-- a colorscheme (rose-pine, gruvbox-material, oxocarbon, monochrome...) past
-- :Theme and WezTerm; to come back as user themes defined in kazRC and shared
-- by both (see weztermRC themes.lua).
-- function ColorMyPencils(color)
--     color = color or theme.default
--     if theme.themes[color] then
--         theme.apply(color)
--         return
--     end
--     vim.cmd.colorscheme(color)
--     vim.api.nvim_set_hl(0, "Normal", { bg = "none" })
--     vim.api.nvim_set_hl(0, "NormalFloat", { bg = "none" })
-- end

-- function SwitchTheme(mode)
--     vim.o.background = mode or "dark"
--     vim.api.nvim_set_hl(0, "Normal", { bg = "none" })
--     vim.api.nvim_set_hl(0, "NormalFloat", { bg = "none" })
-- end

-- function C(color) ColorMyPencils(color) end
-- function S(mode) SwitchTheme(mode) end
-- function Sl() SwitchTheme("light") end
-- function Sd() SwitchTheme("dark") end

theme.setup()
