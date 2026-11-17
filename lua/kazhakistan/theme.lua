-- Shared theme switching between nvim and wezterm.
-- Source of truth: ~/.config/theme.json -> {"theme":"<name>"}
-- wezterm watches the same file, so switching here re-themes the terminal
-- and switching in wezterm (LEADER t) re-themes every running nvim.

local M = {}

M.state_file = vim.fn.expand("~/.config/theme.json")
M.order = { "ashen", "aegis-lavender", "light" }
M.default = "ashen"
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

local function hl(name, spec)
    vim.api.nvim_set_hl(0, name, spec)
end

local function transparent()
    hl("Normal", { bg = "none" })
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
    ["light"] = function()
        vim.o.background = "light"
        vim.cmd.colorscheme("gruvbox-material")
        transparent()
    end,
}

local function read_state()
    local ok, lines = pcall(vim.fn.readfile, M.state_file)
    if not ok or #lines == 0 then
        return nil
    end
    local ok2, data = pcall(vim.json.decode, table.concat(lines, "\n"))
    if ok2 and type(data) == "table" and M.themes[data.theme] then
        return data.theme
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
        write_state(M.default)
    end
    M.sync()
    M.watch()

    vim.api.nvim_create_user_command("Theme", function(opts)
        if opts.args == "" then
            M.cycle()
        else
            M.set(opts.args)
        end
    end, {
        nargs = "?",
        complete = function()
            return M.order
        end,
        desc = "Set shared nvim/wezterm theme (no arg = cycle)",
    })
end

return M
