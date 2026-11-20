-- Logcat of the app being run: its own processes (followed across restarts
-- through ActivityManager's "Start proc" lines) plus crash reports, which
-- come from other processes (native crash dumps). In the window:
--   a  app only / everything      f  filter by text (empty = none)
--   c  clear                      q  close (logcat keeps running)
-- It scrolls along while the cursor is on the last line.
local L = {}

local MAX = 20000 -- entries kept; older ones drop off
local CRASH_TAGS = { DEBUG = true, tombstoned = true, crash_dump = true }
local LEVEL_HL = {
    V = "Comment", D = "Comment", I = nil, W = "DiagnosticWarn", E = "DiagnosticError",
    F = "ErrorMsg", A = "ErrorMsg",
}

local s = {
    job = nil, buf = nil, package = nil, pids = {},
    entries = {}, all = false, filter = nil,
}
local ns = vim.api.nvim_create_namespace("android_logcat")

local function notify(msg, level)
    vim.notify(msg, level or vim.log.levels.INFO, { title = "Android" })
end

-- "11-20 12:00:00.123  1234  1250 E Tag     : message"
local function parse(line)
    local time, pid, level, tag, msg = line:match("^%d+%-%d+ (%d+:%d+:%d+%.%d+)%s+(%d+)%s+%d+ (%a) (.-)%s*: (.*)$")
    if not time then return nil end
    return { time = time, pid = pid, level = level, tag = tag, msg = msg }
end

local function is_app(e)
    if s.pids[e.pid] or CRASH_TAGS[e.tag] then return true end
    -- ActivityManager about the app: died, ANR, killed
    return e.tag == "ActivityManager" and s.package and e.msg:find(s.package, 1, true) ~= nil
end

local function visible(e)
    if not s.all and not is_app(e) then return false end
    if s.filter and not (e.tag .. ": " .. e.msg):lower():find(s.filter, 1, true) then return false end
    return true
end

local function text(e)
    return ("%s %s %s: %s"):format(e.time, e.level, e.tag, e.msg)
end

local function wins()
    local out = {}
    if not (s.buf and vim.api.nvim_buf_is_valid(s.buf)) then return out end
    for _, w in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_buf(w) == s.buf then out[#out + 1] = w end
    end
    return out
end

local function title()
    local what = s.all and "everything" or (s.package or "app")
    local filter = s.filter and ("  filter: " .. s.filter) or ""
    return (" logcat · %s%s   a app/all · f filter · c clear · q close"):format(what, filter)
end

local function append(list)
    local b = s.buf
    if not (b and vim.api.nvim_buf_is_valid(b)) or #list == 0 then return end
    -- follow along only where the cursor sits on the last line
    local follow = {}
    local last = vim.api.nvim_buf_line_count(b)
    for _, w in ipairs(wins()) do
        if vim.api.nvim_win_get_cursor(w)[1] >= last then follow[#follow + 1] = w end
    end
    local empty = last == 1 and vim.api.nvim_buf_get_lines(b, 0, 1, false)[1] == ""
    local lines = {}
    for i, e in ipairs(list) do lines[i] = text(e) end
    vim.bo[b].modifiable = true
    vim.api.nvim_buf_set_lines(b, empty and 0 or -1, -1, false, lines)
    vim.bo[b].modifiable = false
    local first = empty and 0 or last
    for i, e in ipairs(list) do
        local hl = LEVEL_HL[e.level]
        if hl then vim.api.nvim_buf_set_extmark(b, ns, first + i - 1, 0, { line_hl_group = hl }) end
    end
    local n = vim.api.nvim_buf_line_count(b)
    for _, w in ipairs(follow) do vim.api.nvim_win_set_cursor(w, { n, 0 }) end
end

local function redraw()
    if not (s.buf and vim.api.nvim_buf_is_valid(s.buf)) then return end
    vim.bo[s.buf].modifiable = true
    vim.api.nvim_buf_set_lines(s.buf, 0, -1, false, {})
    vim.api.nvim_buf_clear_namespace(s.buf, ns, 0, -1)
    vim.bo[s.buf].modifiable = false
    local list = {}
    for _, e in ipairs(s.entries) do
        if visible(e) then list[#list + 1] = e end
    end
    append(list)
    for _, w in ipairs(wins()) do
        vim.wo[w].winbar = title()
        vim.api.nvim_win_set_cursor(w, { vim.api.nvim_buf_line_count(s.buf), 0 })
    end
end

local function buf()
    if s.buf and vim.api.nvim_buf_is_valid(s.buf) then return s.buf end
    local b = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(b, "logcat://")
    vim.bo[b].bufhidden = "hide"
    vim.bo[b].modifiable = false
    local function map(lhs, fn, desc) vim.keymap.set("n", lhs, fn, { buffer = b, nowait = true, desc = desc }) end
    map("q", "<cmd>close<cr>", "Close logcat")
    map("a", function()
        s.all = not s.all
        redraw()
    end, "Logcat: app only / everything")
    map("f", function()
        vim.ui.input({ prompt = "Logcat filter (empty = none): ", default = s.filter or "" }, function(v)
            if v == nil then return end
            s.filter = vim.trim(v) ~= "" and vim.trim(v):lower() or nil
            redraw()
        end)
    end, "Logcat: filter by text")
    map("c", function()
        s.entries = {}
        redraw()
    end, "Logcat: clear")
    s.buf = b
    return b
end

function L.show()
    local w = wins()[1]
    if w then return w end
    local cur = vim.api.nvim_get_current_win()
    vim.cmd("botright 15split")
    w = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(w, buf())
    for opt, val in pairs({ number = false, relativenumber = false, signcolumn = "no", wrap = false,
        colorcolumn = "", winfixheight = true, winbar = title() }) do
        vim.wo[w][opt] = val
    end
    vim.api.nvim_win_set_cursor(w, { vim.api.nvim_buf_line_count(s.buf), 0 })
    vim.api.nvim_set_current_win(cur)
    return w
end

function L.toggle()
    local open = wins()
    if #open > 0 then
        for _, w in ipairs(open) do pcall(vim.api.nvim_win_close, w, false) end
    else
        L.show()
    end
end

function L.stop()
    if s.job then
        pcall(function() s.job:kill(15) end)
        s.job = nil
    end
end

-- the app's processes; called after launch with what `pidof` says
function L.add_pid(pid)
    if pid and pid ~= "" then s.pids[pid] = true end
end

-- follow `package` on `serial` from now on (new log, old entries kept)
function L.start(env, serial, package)
    L.stop()
    s.package, s.pids = package, {}
    buf()
    L.show()
    for _, w in ipairs(wins()) do vim.wo[w].winbar = title() end

    local pending, scheduled, rest = {}, false, ""
    local crashed = false
    local function flush()
        scheduled = false
        local list = {}
        for _, e in ipairs(pending) do
            s.entries[#s.entries + 1] = e
            if visible(e) then list[#list + 1] = e end
        end
        pending = {}
        if #s.entries > MAX then
            s.entries = vim.list_slice(s.entries, #s.entries - MAX + 2001)
            return redraw()
        end
        append(list)
    end
    local function on_line(line)
        local e = parse(line:gsub("\r$", ""))
        if not e then return end
        -- the app (re)started: follow its new process
        if e.tag == "ActivityManager" and s.package then
            local pid, proc = e.msg:match("Start proc (%d+):([^/%s]+)")
            if pid and (proc == s.package or proc:sub(1, #s.package + 1) == s.package .. ":") then
                s.pids[pid] = true
            end
        end
        if not crashed and s.pids[e.pid] and (e.msg:match("^FATAL EXCEPTION") or e.msg:match("^Fatal signal")) then
            crashed = true
            vim.schedule(function()
                notify(package .. " crashed (logcat)", vim.log.levels.ERROR)
                L.show()
            end)
        end
        pending[#pending + 1] = e
        if not scheduled then
            scheduled = true
            vim.schedule(flush)
        end
    end
    local ok, job = pcall(vim.system, { env.adb, "-s", serial, "logcat", "-v", "threadtime", "-T", "1" }, {
        text = true,
        stdout = function(_, data)
            if not data then return end
            rest = rest .. data
            while true do
                local i = rest:find("\n", 1, true)
                if not i then break end
                on_line(rest:sub(1, i - 1))
                rest = rest:sub(i + 1)
            end
        end,
    })
    if not ok then return notify("cannot run adb logcat: " .. tostring(job), vim.log.levels.ERROR) end
    s.job = job
end

return L
