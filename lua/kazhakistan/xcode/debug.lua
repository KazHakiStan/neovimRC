-- lldb-dap (ships with Xcode) + nvim-dap-ui for kazhakistan.xcode, laid out
-- like Xcode's debugger in the Xcode tab (tab.lua):
--
--   ┌ stack ──────┬ code ───────────────────────────┐
--   │ breakpoints │                                 │
--   │ watches     │                                 │
--   ├ variables ──┴─────────┬ console ──────────────┤
--   │ key hint (winbar)     │ app output + (lldb)   │
--   └───────────────────────┴───────────────────────┘

local M = {}

local HINT = " F5 ▶ continue  F10 over  F11 into  F12 out  F9 ● breakpoint  S-F5 ■ stop   <leader>xh help"

local ready = false

local function notify(msg, level)
    vim.notify(msg, level or vim.log.levels.INFO, { title = "Xcode debug" })
end

local function lldb_dap()
    local r = vim.system({ "xcrun", "-f", "lldb-dap" }, { text = true }):wait()
    if r.code == 0 and r.stdout ~= "" then return vim.trim(r.stdout) end
end

-- key hint above the variables (dap-ui recreates windows on every open)
local function decorate()
    for _, w in ipairs(vim.api.nvim_list_wins()) do
        if vim.bo[vim.api.nvim_win_get_buf(w)].filetype == "dapui_scopes" then
            vim.wo[w].winbar = HINT
        end
    end
end

-- Frames whose debug info points at a file that isn't here (prebuilt Firebase
-- / ads SDKs record paths from their build machine, /private/var/folders/...)
-- lose their source, so a stop shows the nearest frame of your own code
-- instead of an empty buffer. The stack panel still lists them.
local on_disk = {}
local function strip_missing_sources(_, err, response)
    if err or not response or not response.stackFrames then return end
    for _, f in ipairs(response.stackFrames) do
        local s = f.source
        if s and (s.sourceReference or 0) == 0 and s.path then
            if on_disk[s.path] == nil then on_disk[s.path] = vim.uv.fs_stat(s.path) ~= nil end
            if not on_disk[s.path] then
                f.name = ("%s  (%s:%d)"):format(f.name, vim.fs.basename(s.path), f.line or 0)
                f.source = nil
            end
        end
    end
end

-- NSLog prefixes every line with "2026-11-18 10:17:49.133826+0100 App[pid:tid] ";
-- Xcode's console hides it, so does this one
local NSLOG_PREFIX = "\n%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d%.%d+[+-]%d%d%d%d [^\n]-%[%d+:%d+%] "

local function on_output(_, body)
    if body.category == "telemetry" then return end
    local text = body.output or ""
    if body.category == "stdout" or body.category == "stderr" then
        text = ("\n" .. text):gsub(NSLOG_PREFIX, "\n"):sub(2)
    end
    require("dap.repl").append(text, "$", { newline = false })
end

function M.setup()
    if ready then return true end
    local ok_dap, dap = pcall(require, "dap")
    local ok_ui, dapui = pcall(require, "dapui")
    if not (ok_dap and ok_ui) then
        notify("nvim-dap / nvim-dap-ui missing: run :PackerSync", vim.log.levels.ERROR)
        return false
    end
    local cmd = lldb_dap()
    if not cmd then
        notify("lldb-dap not found (is Xcode selected? xcode-select -p)", vim.log.levels.ERROR)
        return false
    end
    dap.adapters["lldb-dap"] = { type = "executable", command = cmd, name = "lldb-dap" }
    dap.defaults["lldb-dap"].switchbuf = require("kazhakistan.xcode.tab").show
    dap.listeners.before.stackTrace.xcode = strip_missing_sources
    dap.defaults["lldb-dap"].on_output = on_output

    dapui.setup({
        -- dap-ui stacks elements bottom-up / right-to-left: listed in reverse
        layouts = {
            {
                position = "left",
                size = 40,
                elements = {
                    { id = "watches", size = 0.2 },
                    { id = "breakpoints", size = 0.25 },
                    { id = "stacks", size = 0.55 },
                },
            },
            {
                position = "bottom",
                size = 15,
                elements = {
                    { id = "repl", size = 0.55 },
                    { id = "scopes", size = 0.45 },
                },
            },
        },
        controls = { enabled = true, element = "repl" },
        floating = { border = "rounded" },
    })

    vim.fn.sign_define("DapBreakpoint", { text = "●", texthl = "DiagnosticError" })
    vim.fn.sign_define("DapBreakpointCondition", { text = "◆", texthl = "DiagnosticError" })
    vim.fn.sign_define("DapLogPoint", { text = "◇", texthl = "DiagnosticInfo" })
    vim.fn.sign_define("DapBreakpointRejected", { text = "○", texthl = "DiagnosticHint" })
    vim.fn.sign_define("DapStopped", { text = "▶", texthl = "DiagnosticWarn", linehl = "CursorLine" })

    -- panels open with the session and stay after it ends, so the output can
    -- still be read; <leader>xd hides them
    dap.listeners.after.event_initialized.xcode = function()
        require("kazhakistan.xcode.tab").code_win()
        dapui.open()
        vim.schedule(decorate)
    end
    dap.listeners.after.event_exited.xcode = function(_, body)
        notify("app exited with code " .. tostring(body and body.exitCode))
    end
    vim.api.nvim_create_autocmd({ "FileType", "BufWinEnter" }, {
        group = vim.api.nvim_create_augroup("XcodeDapHint", { clear = true }),
        callback = function() vim.schedule(decorate) end,
    })

    ready = true
    return true
end

function M.launch(o)
    local env = {}
    for k, v in pairs(o.env or {}) do env[#env + 1] = k .. "=" .. tostring(v) end
    require("dap.repl").clear()
    require("dap").run({
        type = "lldb-dap",
        request = "launch",
        name = o.name,
        program = o.program,
        cwd = o.cwd,
        args = o.args or {},
        env = env,
        stopOnEntry = false,
    })
end

local function session()
    return require("dap").session()
end

function M.continue()
    if session() then
        require("dap").continue()
    else
        require("kazhakistan.xcode").debug()
    end
end

function M.stop()
    if session() then require("dap").terminate() end
end

local function in_session(fn)
    return function()
        if not session() then return notify("not debugging (<leader>xr starts)", vim.log.levels.WARN) end
        fn()
    end
end

M.step_over = in_session(function() require("dap").step_over() end)
M.step_into = in_session(function() require("dap").step_into() end)
M.step_out = in_session(function() require("dap").step_out() end)
M.run_to_cursor = in_session(function() require("dap").run_to_cursor() end)
M.eval = in_session(function() require("dapui").eval(nil, { enter = true }) end)

function M.toggle_breakpoint()
    require("dap").toggle_breakpoint()
end

function M.conditional_breakpoint()
    vim.ui.input({ prompt = "Condition (empty = none): " }, function(cond)
        if cond == nil then return end
        vim.ui.input({ prompt = "Log message, {expr} interpolated (empty = stop): " }, function(msg)
            if msg == nil then return end
            require("dap").set_breakpoint(cond ~= "" and cond or nil, nil, msg ~= "" and msg or nil)
        end)
    end)
end

function M.clear_breakpoints()
    require("dap").clear_breakpoints()
    notify("breakpoints cleared")
end

function M.toggle_ui()
    require("kazhakistan.xcode.tab").code_win()
    require("dapui").toggle()
    vim.schedule(decorate)
end

return M
