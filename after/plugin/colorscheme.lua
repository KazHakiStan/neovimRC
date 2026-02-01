-- themes: ashen, gruvbox-material, rose-pine, oxocarbon, monochrome
function ColorMyPencils(color)
	color = color or 'ashen'
	vim.cmd.colorscheme(color)

	vim.api.nvim_set_hl(0, "Normal", { bg = "none" })
	vim.api.nvim_set_hl(0, "NormalFloat", { bg = "none" })

    if color == 'ashen' then
        vim.api.nvim_set_hl(0, "StatusLineNC", { bg = "#121212", fg = "#6f2929", bold = true })
        vim.api.nvim_set_hl(0, "LineNr", { fg = "#aaaaaa", bg = "#121212" })
    end
end

function SwitchTheme(theme)
    theme = theme or "dark"

    vim.o.background = theme
	vim.api.nvim_set_hl(0, "Normal", { bg = "none" })
	vim.api.nvim_set_hl(0, "NormalFloat", { bg = "none" })
end

function C(color)
    ColorMyPencils(color)
end

function S(theme)
    SwitchTheme(theme)
end

function Sl()
    SwitchTheme("light")
end

function Sd()
    SwitchTheme("dark")
end

ColorMyPencils()
