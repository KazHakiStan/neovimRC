-- Android projects from nvim (macOS, Windows): Gradle sync, build, install
-- and run on a phone or an emulator, logcat, errors in quickfix.
--
-- Zero config: the Gradle project is the nearest folder with gradlew +
-- settings.gradle(.kts) above the current file, else the shallowest one in
-- the repo (games keep it in projects/android). The app module is the one
-- applying com.android.application, the variant `debug`. <leader>nv picks
-- another one and writes `.android.lua` next to gradlew (added to
-- .git/info/exclude). Every field is optional:
--
--   return {
--     module      = "app",
--     variant     = "freeDebug",
--     gradle_args = { "--offline" },
--     activity    = ".MainActivity",  -- launched instead of the launcher one
--   }
--
-- Gradle runs on Android Studio's own JDK when it's installed (as in Studio),
-- else on a JDK 17+. The SDK comes from ANDROID_HOME, local.properties or the
-- default install place. Keys: <leader>nh shows them all.

local M = {}

local platform = require("kazhakistan.platform")
local devices = require("kazhakistan.android.devices")
local logcat = require("kazhakistan.android.logcat")

local WIN = platform.is_windows
local EXE = WIN and ".exe" or ""
local SKIP_DIRS = { build = true, node_modules = true, [".gradle"] = true, [".cxx"] = true, Pods = true }

local state = {
    projects = {}, -- root -> project
    serial = nil,  -- device picked this session
    device = nil,  -- its name
    app = nil,     -- { id, serial } of the last run
}
local build = { job = nil, buf = nil, raw = {} }

local function notify(msg, level)
    vim.notify(msg, level or vim.log.levels.INFO, { title = "Android" })
end

local function exists(path)
    return path ~= nil and vim.uv.fs_stat(path) ~= nil
end

local function norm(path)
    return path and vim.fs.normalize(vim.fn.expand(path)) or nil
end

---------------------------------------------------------------- environment

local function local_properties(root)
    local props = {}
    local f = io.open(root .. "/local.properties")
    if not f then return props end
    for line in f:lines() do
        local k, v = line:match("^%s*([%w%.]+)%s*=%s*(.-)%s*$")
        if k then props[k] = v:gsub("\\(.)", "%1") end -- C\:\\Users -> C:\Users
    end
    f:close()
    return props
end

local function first_dir(candidates, probe)
    for _, c in ipairs(candidates) do
        local dir = norm(c)
        if dir and exists(dir .. (probe or "")) then return dir end
    end
end

-- Android Studio's JDK first (what the project builds with in Studio), else
-- JAVA_HOME / any JDK 17+
local function gradle_jdk()
    local studio = WIN and {
        "C:/Program Files/Android/Android Studio/jbr",
        (vim.env.LOCALAPPDATA or "") .. "/Programs/Android Studio/jbr",
    } or {
        "/Applications/Android Studio.app/Contents/jbr/Contents/Home",
        "~/Applications/Android Studio.app/Contents/jbr/Contents/Home",
        "/opt/android-studio/jbr",
    }
    return first_dir(studio, "/bin/java" .. EXE) or platform.jdk(17)
end

local env_cache = {}
-- { sdk, adb, emulator, jdk } for a project root
function M.env(root)
    if env_cache[root] then return env_cache[root] end
    local candidates = { vim.env.ANDROID_HOME, vim.env.ANDROID_SDK_ROOT, local_properties(root)["sdk.dir"] }
    local defaults = WIN and { (vim.env.LOCALAPPDATA or "") .. "/Android/Sdk" }
        or { "~/Library/Android/sdk", "~/Android/Sdk" }
    local list = {}
    for i = 1, 3 do
        if candidates[i] and candidates[i] ~= "" then list[#list + 1] = candidates[i] end
    end
    vim.list_extend(list, defaults)
    local sdk = first_dir(list, "/platform-tools")
    local e = { sdk = sdk, jdk = gradle_jdk() }
    local adb = sdk and (sdk .. "/platform-tools/adb" .. EXE)
    e.adb = exists(adb) and adb or (vim.fn.exepath("adb") ~= "" and vim.fn.exepath("adb") or nil)
    local emulator = sdk and (sdk .. "/emulator/emulator" .. EXE)
    e.emulator = exists(emulator) and emulator or nil
    env_cache[root] = e
    return e
end

---------------------------------------------------------------- project

local function is_gradle_root(dir)
    return exists(dir .. "/gradlew") and (exists(dir .. "/settings.gradle") or exists(dir .. "/settings.gradle.kts"))
end

local function find_root()
    local file = vim.api.nvim_buf_get_name(0)
    local start = (file ~= "" and vim.bo.buftype == "") and vim.fs.dirname(file) or vim.fn.getcwd()
    start = norm(start)
    if is_gradle_root(start) then return start end
    for dir in vim.fs.parents(start) do
        if is_gradle_root(dir) then return dir end
    end
    -- below the repo root, the shallowest one
    local top = vim.fs.root(start, ".git") or norm(vim.fn.getcwd())
    local best, best_depth
    for name, kind in vim.fs.dir(top, {
        depth = 4,
        skip = function(dir)
            local base = vim.fs.basename(dir)
            return not (SKIP_DIRS[base] or base:match("^%."))
        end,
    }) do
        if kind == "file" and (name:match("settings%.gradle$") or name:match("settings%.gradle%.kts$")) then
            local dir = vim.fs.dirname(top .. "/" .. name)
            local depth = select(2, name:gsub("/", ""))
            if is_gradle_root(dir) and (not best or depth < best_depth) then
                best, best_depth = dir, depth
            end
        end
    end
    return best
end

-- Gradle modules from settings.gradle(.kts): include ':app', include(":lib")
local function modules(root)
    local path = exists(root .. "/settings.gradle.kts") and (root .. "/settings.gradle.kts") or (root .. "/settings.gradle")
    local out = {}
    local f = io.open(path)
    if not f then return out end
    local src = f:read("*a")
    f:close()
    for stmt in src:gmatch("include[%s%(]([^\n]+)") do
        for m in stmt:gmatch("[\"'](:?[%w_%-%.:]+)[\"']") do
            out[#out + 1] = m:gsub("^:", "")
        end
    end
    return out
end

local function build_file(dir)
    for _, name in ipairs({ "build.gradle.kts", "build.gradle" }) do
        if exists(dir .. "/" .. name) then return dir .. "/" .. name end
    end
end

-- the modules that build an app (com.android.application)
local function app_modules(root)
    local out = {}
    for _, m in ipairs(modules(root)) do
        local f = io.open(build_file(root .. "/" .. m:gsub(":", "/")) or "")
        if f then
            local src = f:read("*a")
            f:close()
            if src:find("com.android.application", 1, true) or src:find("android.application", 1, true) then
                out[#out + 1] = m
            end
        end
    end
    return out
end

local function read_project_file(path)
    local src = vim.secure.read(path)
    if not src then return nil, path .. " is not trusted (open it and run :trust)" end
    local chunk, err = load(src, "@" .. path)
    if not chunk then return nil, err end
    local ok, res = pcall(chunk)
    if not ok then return nil, res end
    if type(res) ~= "table" then return nil, path .. " must return a table" end
    return res
end

function M.project()
    local root = find_root()
    if not root then return nil, "no Gradle project (gradlew + settings.gradle) here or in this repo" end
    if state.projects[root] then return state.projects[root] end
    local file = root .. "/.android.lua"
    local user = {}
    if exists(file) then
        local t, err = read_project_file(file)
        if not t then return nil, err end
        user = t
    else
        file = nil
    end
    local module = user.module or app_modules(root)[1]
    if not module then return nil, "no app module (com.android.application) in " .. root end
    local p = {
        root = root,
        repo = vim.fs.root(root, ".git") or root,
        file = file,
        module = module,
        module_dir = root .. "/" .. module:gsub(":", "/"),
        variant = user.variant or "debug",
        gradle_args = user.gradle_args or {},
        activity = user.activity,
    }
    state.projects[root] = p
    return p
end

local function with_project(cb)
    local p, err = M.project()
    if not p then return notify(err, vim.log.levels.ERROR) end
    local e = M.env(p.root)
    if not e.jdk then
        return notify("no JDK 17+ for Gradle: install Android Studio, or a JDK (brew install --cask temurin@21 / "
            .. "scoop install java/temurin21-jdk)", vim.log.levels.ERROR)
    end
    cb(p, e)
end

local function cap(s) return s:sub(1, 1):upper() .. s:sub(2) end

---------------------------------------------------------------- picking

local function pick(title, items, cb)
    local ok = pcall(require, "telescope.pickers")
    if not ok then
        return vim.ui.select(items, { prompt = title }, function(c) if c then cb(c) end end)
    end
    local pickers, finders = require("telescope.pickers"), require("telescope.finders")
    local conf = require("telescope.config").values
    local actions, action_state = require("telescope.actions"), require("telescope.actions.state")
    pickers.new(require("telescope.themes").get_dropdown({}), {
        prompt_title = title,
        finder = finders.new_table({ results = items }),
        sorter = conf.generic_sorter({}),
        attach_mappings = function(bufnr)
            actions.select_default:replace(function()
                local entry = action_state.get_selected_entry()
                actions.close(bufnr)
                if entry then cb(entry[1]) end
            end)
            return true
        end,
    }):find()
end

-- the device for this session: the one picked, else the only one connected,
-- else ask
local function with_device(e, cb)
    if not e.adb then
        return notify("adb not found: install the Android SDK (Android Studio) or set ANDROID_HOME",
            vim.log.levels.ERROR)
    end
    local online = {}
    for _, d in ipairs(devices.connected(e)) do
        if d.state == "device" then online[#online + 1] = d end
    end
    for _, d in ipairs(online) do
        if d.serial == state.serial then return cb(d.serial) end
    end
    if #online == 1 then
        state.serial, state.device = online[1].serial, online[1].name
        return cb(state.serial)
    end
    devices.pick(e, pick, function(serial, name)
        state.serial, state.device = serial, name
        notify("device: " .. name)
        cb(serial)
    end)
end

function M.pick_device()
    with_project(function(_, e)
        if not e.adb then return notify("adb not found", vim.log.levels.ERROR) end
        devices.pick(e, pick, function(serial, name)
            state.serial, state.device = serial, name
            notify("device: " .. name)
        end)
    end)
end

---------------------------------------------------------------- .android.lua

local function git(dir, args)
    local r = vim.system(vim.list_extend({ "git", "-C", dir }, args), { text = true }):wait()
    return r.code == 0, vim.trim(r.stdout or "")
end

-- an untracked, not yet ignored .android.lua goes into .git/info/exclude
local function exclude_from_git(file)
    local dir = vim.fs.dirname(file)
    local in_repo, top = git(dir, { "rev-parse", "--show-toplevel" })
    if not in_repo then return false end
    if git(dir, { "ls-files", "--error-unmatch", file }) then return false end
    if git(dir, { "check-ignore", "-q", file }) then return false end
    local _, exclude = git(dir, { "rev-parse", "--path-format=absolute", "--git-path", "info/exclude" })
    local old = vim.fn.filereadable(exclude) == 1 and table.concat(vim.fn.readfile(exclude, "b"), "\n") or ""
    local f = io.open(exclude, "a")
    if not f then return false end
    f:write((old ~= "" and not old:match("\n$")) and "\n" or "", "/", file:sub(#norm(top) + 2), "\n")
    f:close()
    return true
end

local function save_choice(p)
    local path = p.root .. "/.android.lua"
    local lines
    if p.file then
        lines = vim.fn.readfile(path)
        for _, key in ipairs({ "module", "variant" }) do
            local hit
            for i, l in ipairs(lines) do
                if l:match("^%s*" .. key .. "%s*=") then hit = i end
            end
            local new = ("    %s = %q,"):format(key, p[key])
            if hit then lines[hit] = new else table.insert(lines, 2, new) end
        end
    else
        lines = {
            "-- nvim Android settings (~/.config/nvim/lua/kazhakistan/android). Written by",
            "-- <leader>nv; edit freely, changes apply on the next <leader>n command.",
            "return {",
            ("    module = %q,"):format(p.module),
            ("    variant = %q,"):format(p.variant),
            '    -- gradle_args = { "--offline" },',
            '    -- activity = ".MainActivity",   -- launched instead of the launcher one',
            "}",
        }
    end
    vim.fn.writefile(lines, path)
    vim.secure.trust({ action = "allow", path = path })
    if not p.file then
        p.file = path
        if exclude_from_git(path) then notify("created " .. path .. "\n(added to .git/info/exclude)") end
    end
end

---------------------------------------------------------------- build window

local function parse_error(line, root)
    -- native build output comes as "C/C++: ...", Gradle's failure details as "> ..."
    local l = line:gsub("^C/C%+%+: ", ""):gsub("^> ", "")
    local f, ln, col, kind, msg
    -- Kotlin: e: file:///path/A.kt:12:5 message  (older: e: /path/A.kt: (12, 5): message)
    kind, f, ln, col, msg = l:match("^([ew]): file://(.-):(%d+):(%d+) (.*)$")
    if not kind then kind, f, ln, col, msg = l:match("^([ew]): (.-): %((%d+), (%d+)%): (.*)$") end
    if kind then
        f = f:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
        if f:match("^/%a:") then f = f:sub(2) end -- file:///C:/...
        return { filename = f, lnum = tonumber(ln), col = tonumber(col), text = msg, type = kind:upper() }
    end
    -- javac: /path/A.java:12: error: message
    f, ln, kind, msg = l:match("^(.-%.java):(%d+): (%a+): (.*)$")
    if f and (kind == "error" or kind == "warning") then
        return { filename = f, lnum = tonumber(ln), text = msg, type = kind == "error" and "E" or "W" }
    end
    -- AAPT: ERROR: /path/res/layout/a.xml:12: AAPT: error: message
    f, ln, msg = l:match("^ERROR:%s*(.-):(%d+): AAPT: error: (.*)$")
    if f then return { filename = f, lnum = tonumber(ln), text = msg, type = "E" } end
    -- clang / gcc (NDK), resource XML: /path/a.cpp:12:5: error: message
    f, ln, col, kind, msg = l:match("^(.-):(%d+):(%d+): (%a[%a ]-): (.*)$")
    kind = kind and kind:lower()
    if f and (kind == "error" or kind == "fatal error") then
        return { filename = f, lnum = tonumber(ln), col = tonumber(col), text = msg, type = "E" }
    elseif f and kind == "warning" and norm(f):sub(1, #root) == root then
        return { filename = f, lnum = tonumber(ln), col = tonumber(col), text = msg, type = "W" }
    end
    -- build scripts: Build file '/path/build.gradle' line: 12
    f, ln = l:match("^Build file '(.-)' line: (%d+)")
    if f then return { filename = f, lnum = tonumber(ln), text = "build script error", type = "E" } end
end

-- Gradle's plain console: keep the tasks that ran, errors, installs and the result
-- the steps worth seeing (compiling, native build, packaging, installing)
local function SHOW_TASK(task)
    local name = task:match("([^:]+)$"):lower()
    for _, w in ipairs({ "compile", "cmake", "native", "package", "install", "lint", "test" }) do
        if name:find(w, 1, true) and not name:find("resources", 1, true) and not name:find("navigation", 1, true) then
            return true
        end
    end
    return false
end
local SKIP_TASK = { ["UP-TO-DATE"] = true, ["NO-SOURCE"] = true, SKIPPED = true, ["FROM-CACHE"] = true }
local function pretty(line, st, root)
    if line == "" then
        st.wrong = false
        return nil
    end
    local task, outcome = line:match("^> Task (%S+)%s*(%S*)$")
    if task then
        if SKIP_TASK[outcome] or not SHOW_TASK(task) then return nil end
        return "  " .. task .. (outcome ~= "" and ("  " .. outcome) or "")
    end
    if line:match("^%* What went wrong") then st.wrong = true end
    if line:match("^%* Try:") then st.wrong = false end
    if st.wrong or line:match("^BUILD ") or line:match("^FAILURE") or line:match("^Installing APK")
        or line:match("^Installed on") or line:match("^%d+ actionable tasks") or parse_error(line, root) then
        return line
    end
end

local function build_buf()
    if build.buf and vim.api.nvim_buf_is_valid(build.buf) then return build.buf end
    local b = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(b, "gradle://output")
    vim.bo[b].bufhidden = "hide"
    vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = b, desc = "Close build output" })
    vim.keymap.set("n", "L", function() M.log() end, { buffer = b, desc = "Full build log" })
    build.buf = b
    return b
end

local function build_wins()
    local out = {}
    for _, w in ipairs(vim.api.nvim_list_wins()) do
        if build.buf and vim.api.nvim_win_get_buf(w) == build.buf then out[#out + 1] = w end
    end
    return out
end

local function show_build()
    local w = build_wins()[1]
    if w then return w end
    local cur = vim.api.nvim_get_current_win()
    vim.cmd("botright 12split")
    w = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(w, build_buf())
    for opt, val in pairs({ number = false, relativenumber = false, signcolumn = "no", winfixheight = true,
        wrap = false, colorcolumn = "",
        winbar = " gradle   q close · L full log · <leader>nk stop · <leader>qo errors" }) do
        vim.wo[w][opt] = val
    end
    vim.api.nvim_set_current_win(cur)
    return w
end

local function hide_build()
    for _, w in ipairs(build_wins()) do
        if #vim.api.nvim_tabpage_list_wins(vim.api.nvim_win_get_tabpage(w)) > 1 then
            pcall(vim.api.nvim_win_close, w, false)
        end
    end
end

local function append(lines)
    local b = build_buf()
    vim.api.nvim_buf_set_lines(b, -1, -1, false, lines)
    local n = vim.api.nvim_buf_line_count(b)
    for _, w in ipairs(build_wins()) do vim.api.nvim_win_set_cursor(w, { n, 0 }) end
end

local function set_quickfix(p, lines)
    local errors, warnings, seen = {}, {}, {}
    for _, l in ipairs(lines) do
        local item = parse_error(l, p.repo)
        local key = item and (item.filename .. ":" .. item.lnum .. ":" .. item.text)
        if item and not seen[key] then
            seen[key] = true
            table.insert(item.type == "E" and errors or warnings, item)
        end
    end
    vim.fn.setqflist({}, " ", { title = "gradle", items = vim.list_extend(vim.list_extend({}, errors), warnings) })
    return #errors, #warnings
end

local function gradle_argv(p, tasks)
    -- runs in p.root; on Windows by name, so a path with spaces needs no quoting
    -- for cmd.exe. `sh` on the others: gradlew may have lost its exec bit.
    local argv = WIN and { "cmd.exe", "/c", "gradlew.bat" } or { "sh", p.root .. "/gradlew" }
    vim.list_extend(argv, { "--console=plain" })
    vim.list_extend(argv, p.gradle_args)
    return vim.list_extend(argv, tasks)
end

local function gradle_env(e, serial)
    local env = { JAVA_HOME = e.jdk, ANDROID_SERIAL = serial }
    if e.sdk and not vim.env.ANDROID_HOME then env.ANDROID_HOME = e.sdk end
    return env
end

-- run Gradle tasks with the output in the build window; on_done(ok)
-- opts.report(p): after the build, puts its own results (tests, lint) in
-- quickfix and says how it went; returns false when it found nothing
local function run_gradle(p, e, label, tasks, serial, on_done, opts)
    if build.job then
        return notify("a build is already running (<leader>nk stops it)", vim.log.levels.WARN)
    end
    build.raw = {}
    vim.api.nvim_buf_set_lines(build_buf(), 0, -1, false, {
        ("▶ %s · :%s · %s%s"):format(label, p.module, p.variant, state.device and (" · " .. state.device) or ""), "",
    })
    show_build()

    local st, pending, scheduled = {}, {}, false
    local function flush()
        scheduled = false
        local out = {}
        for _, l in ipairs(pending) do out[#out + 1] = pretty(l, st, p.repo) end
        pending = {}
        if #out > 0 then append(out) end
    end
    local function reader()
        local rest = ""
        return function(_, data)
            if not data then return end
            rest = rest .. data
            while true do
                local i = rest:find("\n", 1, true)
                if not i then break end
                local l = rest:sub(1, i - 1):gsub("\r$", "")
                rest = rest:sub(i + 1)
                build.raw[#build.raw + 1] = l
                pending[#pending + 1] = l
                if not scheduled then
                    scheduled = true
                    vim.schedule(flush)
                end
            end
        end
    end

    local started = vim.uv.now()
    local ok, job = pcall(vim.system, gradle_argv(p, tasks), {
        cwd = p.root, env = gradle_env(e, serial), text = true, stdout = reader(), stderr = reader(),
    }, function(r)
        vim.schedule(function()
            flush()
            build.job = nil
            local n_err, n_warn = set_quickfix(p, build.raw)
            local success = r.code == 0
            local reported = n_err == 0 and r.signal == 0 and opts and opts.report and opts.report(p)
            local verdict = success and "✔ succeeded" or (r.signal ~= 0 and "■ stopped" or "✘ failed")
            append({ "", ("%s in %.1fs · %d errors, %d warnings"):format(verdict, (vim.uv.now() - started) / 1000,
                n_err, n_warn) })
            if not success and r.signal == 0 and not reported then
                notify(label .. " failed: " .. n_err .. " errors (quickfix)", vim.log.levels.ERROR)
                if n_err > 0 then vim.cmd("botright copen") end
            end
            if on_done then on_done(success) end
        end)
    end)
    if not ok then return notify("cannot run Gradle: " .. tostring(job), vim.log.levels.ERROR) end
    build.job = job
end

---------------------------------------------------------------- tests and lint

local frames = require("kazhakistan.android.frames")

local function unescape(s)
    return (s:gsub("&#(%d+);", function(n) return string.char(tonumber(n)) end)
        :gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&quot;", '"'):gsub("&apos;", "'"):gsub("&amp;", "&"))
end

local function attr(attrs, name)
    local v = attrs:match("%s" .. name .. '="(.-)"')
    return v and unescape(v)
end

-- JUnit XML reports (unit tests, device tests): every failed test in
-- quickfix, at the first line of its stack trace that's in the project
local function test_report(dir, title)
    return function(p)
        local ctx = { repo = p.repo, module_dir = p.module_dir }
        local items, total = {}, 0
        for _, path in ipairs(vim.fn.glob(dir .. "/**/*.xml", false, true)) do
            local xml = table.concat(vim.fn.readfile(path), "\n")
            local pos = 1
            while true do
                local s1, e1, attrs, closed = xml:find("<testcase(.-)(/?)>", pos)
                if not s1 then break end
                total = total + 1
                pos = e1 + 1
                if closed ~= "/" then
                    local s2, e2 = xml:find("</testcase>", pos, true)
                    local body = xml:sub(pos, (s2 or #xml + 1) - 1)
                    pos = (e2 or #xml) + 1
                    local fattrs, stack = body:match("<failure(.-)>(.-)</failure>")
                    if not fattrs then fattrs, stack = body:match("<error(.-)>(.-)</error>") end
                    if fattrs then
                        local name = ((attr(attrs, "classname") or ""):match("([^%.]+)$") or "?") .. "." .. (attr(attrs, "name") or "?")
                        local message = (attr(fattrs, "message") or unescape(stack):match("^[^\n]*")):match("^[^\n]*")
                        local item = { text = name .. ": " .. message, type = "E" }
                        for line in unescape(stack):gmatch("[^\n]+") do
                            local at = frames.resolve(line, ctx)
                            if at then
                                item.filename, item.lnum = at.filename, at.lnum
                                break
                            end
                        end
                        items[#items + 1] = item
                    end
                end
            end
        end
        if total == 0 then return false end
        vim.fn.setqflist({}, " ", { title = title, items = items })
        if #items == 0 then
            notify(("%s: all %d passed"):format(title, total))
        else
            notify(("%s: %d of %d failed (quickfix)"):format(title, #items, total), vim.log.levels.ERROR)
            vim.cmd("botright copen")
        end
        return true
    end
end

-- Android lint's XML report: every issue in quickfix, errors first
local function lint_report(p)
    local path = p.module_dir .. "/build/reports/lint-results-" .. p.variant .. ".xml"
    if vim.fn.filereadable(path) == 0 then return false end
    local xml = table.concat(vim.fn.readfile(path), "\n")
    local errors, warnings = {}, {}
    for attrs, body in xml:gmatch("<issue(%s.-)>(.-)</issue>") do -- not the <issues> around them
        local severity = attr(attrs, "severity") or "Warning"
        local loc = body:match("<location(.-)/?>") or ""
        local file = attr(loc, "file")
        if file and not file:match("^/") and not file:match("^%a:") then file = p.module_dir .. "/" .. file end
        local item = {
            filename = file, lnum = tonumber(attr(loc, "line")), col = tonumber(attr(loc, "column")),
            text = ("%s [%s]"):format(attr(attrs, "message") or "", attr(attrs, "id") or "lint"),
            type = (severity == "Error" or severity == "Fatal") and "E" or "W",
        }
        table.insert(item.type == "E" and errors or warnings, item)
    end
    local n_err, n_warn = #errors, #warnings
    vim.fn.setqflist({}, " ", { title = "lint", items = vim.list_extend(errors, warnings) })
    if n_err + n_warn == 0 then
        notify("lint: nothing found")
    else
        notify(("lint: %d errors, %d warnings (quickfix)"):format(n_err, n_warn),
            n_err > 0 and vim.log.levels.ERROR or vim.log.levels.WARN)
        vim.cmd("botright copen")
    end
    return true
end

---------------------------------------------------------------- the app

-- applicationId of the variant, from the APK's output-metadata.json
local function application_id(p)
    for _, path in ipairs(vim.fn.glob(p.module_dir .. "/build/outputs/apk/**/output-metadata.json", false, true)) do
        local ok, data = pcall(vim.json.decode, table.concat(vim.fn.readfile(path), "\n"))
        if ok and type(data) == "table" and data.variantName == p.variant then return data.applicationId end
    end
end

local function adb(e, serial, args)
    local argv = { e.adb, "-s", serial }
    vim.list_extend(argv, args)
    local r = vim.system(argv, { text = true }):wait()
    return r.code == 0, vim.trim(r.stdout or "")
end

-- the launcher activity (or `activity` from .android.lua)
local function component(p, e, serial, id)
    if p.activity then return id .. "/" .. p.activity end
    local _, out = adb(e, serial, { "shell", "cmd", "package", "resolve-activity", "--brief",
        "-a", "android.intent.action.MAIN", "-c", "android.intent.category.LAUNCHER", id })
    local last
    for line in out:gmatch("[^\r\n]+") do
        if line:find("/", 1, true) then last = vim.trim(line) end
    end
    return last
end

-- (re)start the app with a fresh logcat
local function launch(p, e, serial, id)
    adb(e, serial, { "shell", "am", "force-stop", id })
    logcat.start(e, serial, id, { repo = p.repo, module_dir = p.module_dir, sdk = e.sdk })
    local comp = component(p, e, serial, id)
    local ok
    if comp then
        ok = adb(e, serial, { "shell", "am", "start", "-n", comp })
    else
        ok = adb(e, serial, { "shell", "monkey", "-p", id, "-c", "android.intent.category.LAUNCHER", "1" })
    end
    if not ok then return notify("couldn't start " .. id, vim.log.levels.ERROR) end
    state.app = { id = id, serial = serial }
    vim.defer_fn(function()
        local _, pid = adb(e, serial, { "shell", "pidof", "-s", id })
        logcat.add_pid(pid)
    end, 1000)
    notify("started " .. id .. " on " .. (state.device or serial))
end

---------------------------------------------------------------- actions

-- The device has the app signed with another key (installed from another
-- machine or by Studio with a different keystore) or a newer version: like
-- Studio, offer to uninstall it (its data goes too) and install again.
local function install_conflict(lines)
    for i = #lines, 1, -1 do
        local id = lines[i]:match("INSTALL_FAILED_UPDATE_INCOMPATIBLE: Existing package (%S+) signatures")
            or lines[i]:match("INSTALL_FAILED_UPDATE_INCOMPATIBLE: Package (%S+) signatures")
        if id then return id, "is signed with another key" end
        if lines[i]:match("INSTALL_FAILED_VERSION_DOWNGRADE") then return true, "has a newer version" end
    end
end

-- build, install on the device, start, logcat
function M.run(retried)
    with_project(function(p, e)
        with_device(e, function(serial)
            run_gradle(p, e, "run", { ":" .. p.module .. ":install" .. cap(p.variant) }, serial, function(ok)
                local conflict, why = install_conflict(build.raw)
                if not ok and conflict and not retried then
                    local id = conflict == true and application_id(p) or conflict
                    if not id then return end
                    local answer = vim.fn.confirm(("%s on %s %s.\nUninstall it (with its data) and install again?")
                        :format(id, state.device or serial, why), "&Uninstall\n&Cancel", 2)
                    if answer ~= 1 then return end
                    adb(e, serial, { "uninstall", id })
                    return M.run(true)
                end
                if not ok then return end
                local id = application_id(p)
                if not id then return notify("installed, but no output-metadata.json to find the app id in",
                        vim.log.levels.ERROR) end
                hide_build()
                launch(p, e, serial, id)
            end)
        end)
    end)
end

-- start the installed app again, without building
function M.restart()
    with_project(function(p, e)
        with_device(e, function(serial)
            local id = application_id(p)
            if not id then return notify("not built yet: <leader>nr", vim.log.levels.WARN) end
            launch(p, e, serial, id)
        end)
    end)
end

function M.stop_app()
    if not state.app then return notify("nothing started from here") end
    with_project(function(_, e)
        adb(e, state.app.serial, { "shell", "am", "force-stop", state.app.id })
        notify("stopped " .. state.app.id)
    end)
end

-- the device's screen on the computer (scrcpy), mouse and keyboard included
function M.mirror()
    if vim.fn.executable("scrcpy") ~= 1 then
        return notify("scrcpy isn't installed: brew install scrcpy / scoop install scrcpy (setupRC has it)",
            vim.log.levels.WARN)
    end
    with_project(function(_, e)
        with_device(e, function(serial)
            local ok, err = pcall(vim.system, { "scrcpy", "-s", serial, "--window-title", state.device or serial,
                "--stay-awake" }, { detach = true, env = { ADB = e.adb } })
            if not ok then return notify("scrcpy: " .. tostring(err), vim.log.levels.ERROR) end
            notify("mirroring " .. (state.device or serial))
        end)
    end)
end

function M.build()
    with_project(function(p, e)
        run_gradle(p, e, "build", { ":" .. p.module .. ":assemble" .. cap(p.variant) }, state.serial)
    end)
end

-- unit tests (JVM, no device)
function M.test()
    with_project(function(p, e)
        local task = "test" .. cap(p.variant) .. "UnitTest"
        run_gradle(p, e, "unit tests", { ":" .. p.module .. ":" .. task }, nil, function(ok) if ok then hide_build() end end,
            { report = test_report(p.module_dir .. "/build/test-results/" .. task, "unit tests") })
    end)
end

-- instrumented tests on the device
function M.device_test()
    with_project(function(p, e)
        with_device(e, function(serial)
            run_gradle(p, e, "device tests", { ":" .. p.module .. ":connected" .. cap(p.variant) .. "AndroidTest" },
                serial, function(ok) if ok then hide_build() end end, {
                    report = test_report(p.module_dir .. "/build/outputs/androidTest-results/connected", "device tests"),
                })
        end)
    end)
end

function M.lint()
    with_project(function(p, e)
        run_gradle(p, e, "lint", { ":" .. p.module .. ":lint" .. cap(p.variant) }, nil, function(ok) if ok then hide_build() end end,
            { report = lint_report })
    end)
end

function M.clean()
    with_project(function(p, e) run_gradle(p, e, "clean", { "clean" }) end)
end

-- what Studio's sync does that matters here: configure every module and
-- resolve the variant's dependencies, so script and dependency errors show
function M.sync()
    with_project(function(p, e)
        run_gradle(p, e, "sync", { ":" .. p.module .. ":dependencies", "--configuration",
            p.variant .. "RuntimeClasspath" }, nil, function(ok)
            if ok then
                hide_build()
                notify("Gradle sync: ok")
            end
        end)
    end)
end

function M.stop_build()
    if build.job then build.job:kill(15) else notify("no build running") end
end

-- module and variant, from Gradle's install tasks
function M.pick_variant()
    with_project(function(p, e)
        local mods = app_modules(p.root)
        local function variants_of(module)
            notify("asking Gradle for the variants of :" .. module .. "…")
            vim.system(gradle_argv(p, { "-q", ":" .. module .. ":tasks", "--group", "install" }),
                { cwd = p.root, env = gradle_env(e), text = true }, function(r)
                    vim.schedule(function()
                        local list = {}
                        for v in ("\n" .. (r.stdout or "")):gmatch("\ninstall(%u%w*) %- ") do
                            if not v:match("AndroidTest$") and not v:match("UnitTest$") then
                                list[#list + 1] = v:sub(1, 1):lower() .. v:sub(2)
                            end
                        end
                        if #list == 0 then
                            return notify("Gradle listed no variants\n" .. (r.stderr or ""), vim.log.levels.ERROR)
                        end
                        pick("Variant · :" .. module, list, function(v)
                            p.module, p.module_dir, p.variant = module, p.root .. "/" .. module:gsub(":", "/"), v
                            save_choice(p)
                            notify(("variant: :%s %s"):format(module, v))
                        end)
                    end)
                end)
        end
        if #mods > 1 then
            pick("App module", mods, variants_of)
        else
            variants_of(p.module)
        end
    end)
end

function M.log()
    vim.cmd("tabnew")
    local b = vim.api.nvim_get_current_buf()
    vim.bo[b].buftype = "nofile"
    vim.bo[b].bufhidden = "wipe"
    vim.api.nvim_buf_set_lines(b, 0, -1, false, build.raw)
    vim.keymap.set("n", "q", "<cmd>tabclose<cr>", { buffer = b })
end

function M.info()
    local p, err = M.project()
    if not p then return notify(err, vim.log.levels.ERROR) end
    local e = M.env(p.root)
    notify(table.concat({
        "project:  " .. p.root,
        "settings: " .. (p.file or "(none, auto-detected)"),
        "module:   :" .. p.module .. "   variant: " .. p.variant,
        "device:   " .. (state.device and (state.device .. "  " .. state.serial) or "(not picked yet)"),
        "sdk:      " .. (e.sdk or "NOT FOUND"),
        "adb:      " .. (e.adb or "NOT FOUND"),
        "emulator: " .. (e.emulator or "not found"),
        "JDK:      " .. (e.jdk or "NOT FOUND"),
    }, "\n"))
end

---------------------------------------------------------------- keys & help

local KEYS = {
    { "<leader>nr", function() M.run() end, "Build + install + run (+ logcat)" },
    { "<leader>nR", function() M.restart() end, "Restart the app without building" },
    { "<leader>nx", function() M.stop_app() end, "Stop the app" },
    { "<leader>nb", function() M.build() end, "Build (assemble)" },
    { "<leader>ns", function() M.sync() end, "Gradle sync (configure + dependencies)" },
    { "<leader>nt", function() M.test() end, "Unit tests (failures in quickfix)" },
    { "<leader>nT", function() M.device_test() end, "Tests on the device (failures in quickfix)" },
    { "<leader>nn", function() M.lint() end, "Lint (issues in quickfix)" },
    { "<leader>nc", function() M.clean() end, "Clean" },
    { "<leader>nk", function() M.stop_build() end, "Stop the running build" },
    { "<leader>nd", function() M.pick_device() end, "Pick device / start an emulator" },
    { "<leader>nv", function() M.pick_variant() end, "Pick module and variant" },
    { "<leader>nl", function() logcat.toggle() end, "Show / hide logcat" },
    { "<leader>nm", function() M.mirror() end, "Mirror the device's screen (scrcpy)" },
    { "<leader>nL", function() M.log() end, "Full log of the last build" },
    { "<leader>ni", function() M.info() end, "Project, device, SDK, JDK" },
    { "<leader>nh", function() M.help() end, "This help" },
}

local help_win
function M.help()
    if help_win and vim.api.nvim_win_is_valid(help_win) then
        vim.api.nvim_win_close(help_win, true)
        help_win = nil
        return
    end
    local lines = { "Keys" }
    for _, k in ipairs(KEYS) do lines[#lines + 1] = ("  %-14s %s"):format(k[1], k[3]) end
    vim.list_extend(lines, {
        "",
        "Logcat window",
        "  <CR> open the stack frame     t   whole trace to quickfix",
        "  a   app only / everything    f   filter by text",
        "  c   clear                    q   close (keeps running)",
        "",
        "Devices (<leader>nd): ● connected, ○ emulator to start, ⇄ USB phone to Wi-Fi,",
        "  + pair a new phone over Wi-Fi (Android 11+, Wireless debugging)",
        "",
        "Build window: q close, L full log; errors go to quickfix (<leader>qo)",
        "Command: :Android run|restart|stop|build|sync|test|devicetest|lint|clean|device|variant|logcat|mirror|info",
    })
    local width = 0
    for _, l in ipairs(lines) do width = math.max(width, vim.fn.strdisplaywidth(l)) end
    local b = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(b, 0, -1, false, lines)
    vim.bo[b].modifiable = false
    vim.bo[b].bufhidden = "wipe"
    help_win = vim.api.nvim_open_win(b, true, {
        relative = "editor", style = "minimal", border = "rounded", title = " Android ", title_pos = "center",
        width = width + 2, height = #lines,
        row = math.floor((vim.o.lines - #lines) / 2) - 1, col = math.floor((vim.o.columns - width) / 2),
    })
    for _, key in ipairs({ "q", "<Esc>" }) do
        vim.keymap.set("n", key, function() M.help() end, { buffer = b, nowait = true })
    end
end

local COMMANDS = {
    run = M.run, restart = M.restart, stop = M.stop_app, build = M.build, sync = M.sync,
    clean = M.clean, test = M.test, devicetest = M.device_test, lint = M.lint, device = M.pick_device, mirror = M.mirror, variant = M.pick_variant, logcat = logcat.toggle,
    log = M.log, info = M.info, help = M.help,
}

function M.setup()
    for _, k in ipairs(KEYS) do vim.keymap.set("n", k[1], k[2], { desc = "Android: " .. k[3] }) end
    vim.api.nvim_create_user_command("Android", function(o)
        local fn = COMMANDS[o.args ~= "" and o.args or "help"]
        if not fn then return notify("unknown :Android " .. o.args, vim.log.levels.ERROR) end
        fn()
    end, {
        nargs = "?",
        complete = function() return vim.tbl_keys(COMMANDS) end,
        desc = "Android: run, build, sync, device, logcat…",
    })
    -- edits to .android.lua apply on the next command
    vim.api.nvim_create_autocmd("BufWritePost", {
        group = vim.api.nvim_create_augroup("AndroidProjectFile", { clear = true }),
        pattern = ".android.lua",
        callback = function(ev)
            vim.secure.trust({ action = "allow", bufnr = ev.buf })
            state.projects[vim.fs.dirname(vim.fs.normalize(ev.match))] = nil
        end,
    })
end

return M
