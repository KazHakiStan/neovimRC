-- Ctrl-h/j/k/l across nvim splits and WezTerm panes (weztermRC keymaps.lua):
-- nvim tells WezTerm it is running (user var IS_NVIM), so WezTerm hands it
-- those keys; at the edge of nvim the move goes on to the WezTerm pane beyond.
-- Outside WezTerm it is plain window moves.
local M = {}

local pane = vim.env.WEZTERM_PANE
local DIR = { h = "Left", j = "Down", k = "Up", l = "Right" }

-- OSC 1337 SetUserVar, through the terminal nvim draws on
local function user_var(name, value)
    if #vim.api.nvim_list_uis() == 0 then return end -- headless: no terminal
    vim.fn.chansend(vim.v.stderr, ("\027]1337;SetUserVar=%s=%s\007"):format(name, vim.base64.encode(value)))
end

-- the CLI: `wezterm` next to the GUI (WEZTERM_EXECUTABLE is wezterm-gui,
-- which has no `cli`), else whatever is on PATH
local function cli()
    local dir = vim.env.WEZTERM_EXECUTABLE_DIR
    local exe = dir and (dir .. "/wezterm" .. (vim.fn.has("win32") == 1 and ".exe" or ""))
    return (exe and vim.fn.executable(exe) == 1) and exe or "wezterm"
end

function M.move(key)
    local win = vim.api.nvim_get_current_win()
    vim.cmd.wincmd(key)
    if vim.api.nvim_get_current_win() ~= win or not pane then return end
    vim.system({ cli(), "cli", "activate-pane-direction", "--pane-id", pane, DIR[key] }, { text = true },
        function(r)
            if r.code ~= 0 then
                vim.schedule(function()
                    vim.notify("wezterm cli: " .. vim.trim(r.stderr or ""), vim.log.levels.WARN)
                end)
            end
        end)
end

function M.setup()
    for key, dir in pairs(DIR) do
        vim.keymap.set("n", "<C-" .. key .. ">", function() M.move(key) end,
            { desc = "Window: " .. dir:lower() .. " (or the WezTerm pane beyond)" })
    end
    if not pane then return end
    local group = vim.api.nvim_create_augroup("KazWezterm", { clear = true })
    vim.api.nvim_create_autocmd({ "VimEnter", "VimResume" }, {
        group = group,
        callback = function() user_var("IS_NVIM", "true") end,
    })
    vim.api.nvim_create_autocmd({ "VimLeavePre", "VimSuspend" }, {
        group = group,
        callback = function() user_var("IS_NVIM", "") end,
    })
    if vim.v.vim_did_enter == 1 then user_var("IS_NVIM", "true") end
end

return M
