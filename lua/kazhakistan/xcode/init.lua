-- Xcode projects from nvim (macOS): build, run, debug under lldb-dap.
--
-- Works with zero config: the first .xcworkspace (else .xcodeproj) under the
-- repo root (else cwd) is used. The first command asks for a scheme and then
-- writes `.xcode.lua` there (added to .git/info/exclude); <leader>xs changes
-- the scheme in it. Every field is optional, relative paths are relative to
-- the file:
--
--   return {
--     workspace     = "apple/App.xcworkspace", -- or project = "App.xcodeproj"
--     scheme        = "macOS",
--     configuration = "Debug",
--     destination   = "platform=macOS",        -- passed to -destination
--     derived_data  = "~/.cache/nvim/xcode/App",
--     run_cwd       = "res",                   -- working dir of the app
--     args          = { "--verbose" },
--     env           = { NSUnbufferedIO = "YES" },
--     xcodebuild_args = { "-quiet" },
--     setup = function(x) end,                 -- project commands; x.root, x.path(rel)
--   }
--
-- The file is Lua and gets executed, so nvim asks once to trust it (:trust).
-- Build output and the debugger live in their own tab (tab.lua).
-- Keys: <leader>xh shows them all.

local M = {}

local CACHE_DIR = vim.fn.stdpath("cache") .. "/xcode"
local SKIP_DIRS = { Pods = true, build = true, DerivedData = true, node_modules = true, ["third-party"] = true }

local state = {
    projects = {}, -- root -> resolved project
    scheme = {},   -- root -> scheme picked this session
    apps = {},     -- root|scheme|config -> app paths from build settings
}
local build = { job = nil, buf = nil, raw = {} }

local function notify(msg, level)
    vim.notify(msg, level or vim.log.levels.INFO, { title = "Xcode" })
end

---------------------------------------------------------------- project

local function abs(root, p)
    if not p then return nil end
    p = vim.fs.normalize(p)
    if p:sub(1, 1) ~= "/" then p = root .. "/" .. p end
    return p
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

-- shallowest .xcworkspace (else .xcodeproj) under root, skipping Pods & build dirs
local function find_container(root)
    local best = {}
    for name, kind in vim.fs.dir(root, {
        depth = 4,
        skip = function(dir)
            local base = vim.fs.basename(dir)
            return not (SKIP_DIRS[base] or base:match("^%.") or base:match("%.xc%a+$") or base:match("%.app$"))
        end,
    }) do
        if kind == "directory" then
            local ext = name:match("%.(xcworkspace)$") or name:match("%.(xcodeproj)$")
            if ext then
                local depth = select(2, name:gsub("/", ""))
                if not best[ext] or depth < best[ext].depth then
                    best[ext] = { path = root .. "/" .. name, depth = depth }
                end
            end
        end
    end
    if best.xcworkspace then return best.xcworkspace.path, nil end
    if best.xcodeproj then return nil, best.xcodeproj.path end
end

local function relative(root, path)
    if path and path:sub(1, #root + 1) == root .. "/" then return path:sub(#root + 2) end
    return path
end

local function git(root, args)
    local r = vim.system(vim.list_extend({ "git", "-C", root }, args), { text = true }):wait()
    return r.code == 0, vim.trim(r.stdout or "")
end

-- keep .xcode.lua out of git unless it is committed on purpose: an untracked,
-- not-yet-ignored file goes into .git/info/exclude (local to this clone)
local function exclude_from_git(file)
    local dir = vim.fs.dirname(file)
    local in_repo, top = git(dir, { "rev-parse", "--show-toplevel" })
    if not in_repo then return false end
    if git(dir, { "ls-files", "--error-unmatch", file }) then return false end -- tracked
    if git(dir, { "check-ignore", "-q", file }) then return false end         -- already ignored
    local _, exclude = git(dir, { "rev-parse", "--path-format=absolute", "--git-path", "info/exclude" })
    vim.fn.mkdir(vim.fs.dirname(exclude), "p")
    local old = vim.fn.filereadable(exclude) == 1 and table.concat(vim.fn.readfile(exclude, "b"), "\n") or ""
    local f = io.open(exclude, "a")
    if not f then return false end
    f:write((old ~= "" and not old:match("\n$")) and "\n" or "", "/", relative(top, file), "\n")
    f:close()
    return true
end

-- first scheme pick in a project without .xcode.lua: write what was detected,
-- with the optional fields commented out
local function create_project_file(p, scheme)
    local path = p.root .. "/.xcode.lua"
    if vim.uv.fs_stat(path) then return end
    local container = p.workspace and ("workspace = %q,"):format(relative(p.root, p.workspace))
        or ("project = %q,"):format(relative(p.root, p.project))
    vim.fn.writefile({
        "-- nvim Xcode settings (~/.config/nvim/lua/kazhakistan/xcode). Generated on the first",
        "-- scheme pick; edit freely. Paths are relative to this file; saved changes apply",
        "-- on the next <leader>x command.",
        "return {",
        "    " .. container,
        ("    scheme = %q,"):format(scheme),
        ("    configuration = %q,"):format(p.configuration),
        '    -- destination = "platform=macOS",      -- passed to -destination',
        '    -- derived_data = "~/.cache/nvim/xcode/' .. vim.fs.basename(p.root) .. '",',
        '    -- run_cwd = "res",                     -- working dir of the app',
        '    -- args = { "--flag" },',
        '    -- env = { NSUnbufferedIO = "YES" },',
        '    -- xcodebuild_args = { "-quiet" },',
        "    -- setup = function(x) end,             -- project commands; x.root, x.path(rel)",
        "}",
    }, path)
    vim.secure.trust({ action = "allow", path = path }) -- we wrote it ourselves
    p.file, p.scheme = path, scheme
    local excluded = exclude_from_git(path)
    notify("created " .. path .. (excluded and "\n(added to .git/info/exclude)" or ""))
end

-- <leader>xs in a project with .xcode.lua: rewrite its `scheme = "..."` line
local function save_scheme(p, scheme)
    local lines = vim.fn.readfile(p.file)
    local hits = {}
    for i, l in ipairs(lines) do
        if l:match('^%s*scheme%s*=%s*"[^"]*"') then hits[#hits + 1] = i end
    end
    if #hits ~= 1 then
        return notify("scheme " .. scheme .. " is for this session only (no single scheme line in .xcode.lua)")
    end
    lines[hits[1]] = lines[hits[1]]:gsub('^(%s*scheme%s*=%s*)"[^"]*"', function(lhs) return lhs .. ("%q"):format(scheme) end)
    vim.fn.writefile(lines, p.file)
    vim.secure.trust({ action = "allow", path = p.file })
    p.scheme = scheme
end

function M.project()
    local cwd = vim.fn.getcwd()
    local file = vim.fs.find(".xcode.lua", { upward = true, path = cwd, type = "file" })[1]
    -- without a file the project lives at the repo root (where it will be created)
    local root = file and vim.fs.dirname(file) or vim.fs.root(cwd, ".git") or cwd
    if state.projects[root] then return state.projects[root] end
    if file and exclude_from_git(file) then
        notify(".xcode.lua added to .git/info/exclude")
    end

    local user = {}
    if file then
        local t, err = read_project_file(file)
        if not t then return nil, err end
        user = t
    end

    local p = {
        root = root,
        file = file,
        workspace = abs(root, user.workspace),
        project = abs(root, user.project),
        scheme = user.scheme,
        configuration = user.configuration or "Debug",
        destination = user.destination,
        derived_data = abs(root, user.derived_data)
            or (CACHE_DIR .. "/" .. vim.fs.basename(root) .. "-" .. vim.fn.sha256(root):sub(1, 8)),
        run_cwd = abs(root, user.run_cwd),
        args = user.args or {},
        env = user.env or {},
        xcodebuild_args = user.xcodebuild_args or {},
    }
    if not p.workspace and not p.project then
        p.workspace, p.project = find_container(root)
        if not p.workspace and not p.project then
            return nil, "no .xcworkspace / .xcodeproj under " .. root
        end
    end
    state.projects[root] = p

    if user.setup then
        local x = { root = root, path = function(rel) return abs(root, rel) end }
        local ok, err = pcall(user.setup, x)
        if not ok then notify(".xcode.lua setup(): " .. tostring(err), vim.log.levels.ERROR) end
    end
    return p
end

local function container_args(p)
    if p.workspace then return { "-workspace", p.workspace } end
    return { "-project", p.project }
end

local function xcodebuild_argv(p, scheme, tail)
    local argv = { "xcodebuild" }
    vim.list_extend(argv, container_args(p))
    vim.list_extend(argv, { "-scheme", scheme, "-configuration", p.configuration, "-derivedDataPath", p.derived_data })
    if p.destination then vim.list_extend(argv, { "-destination", p.destination }) end
    vim.list_extend(argv, p.xcodebuild_args)
    vim.list_extend(argv, tail)
    return argv
end

---------------------------------------------------------------- scheme

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

-- schemes defined by the projects themselves (not by CocoaPods targets)
local function own_schemes(p)
    local projects = {}
    if p.project then
        projects = { p.project }
    else
        local f = io.open(p.workspace .. "/contents.xcworkspacedata")
        if f then
            local data = f:read("*a")
            f:close()
            for loc in data:gmatch('location%s*=%s*"[%a]+:([^"]+%.xcodeproj)"') do
                if not loc:match("Pods") then
                    projects[#projects + 1] = abs(vim.fs.dirname(p.workspace), loc)
                end
            end
        end
    end
    local own = {}
    for _, proj in ipairs(projects) do
        for _, pattern in ipairs({ "/xcshareddata/xcschemes/*.xcscheme", "/xcuserdata/*/xcschemes/*.xcscheme" }) do
            for _, path in ipairs(vim.fn.glob(proj .. pattern, false, true)) do
                own[vim.fn.fnamemodify(path, ":t:r")] = true
            end
        end
    end
    return own
end

local function choose_scheme(p, cb)
    local ok, err = pcall(vim.system, vim.list_extend({ "xcodebuild", "-list", "-json" }, container_args(p)),
        { text = true }, function(r)
            vim.schedule(function()
                local okj, data = pcall(vim.json.decode, r.stdout or "")
                local list = okj and type(data) == "table" and (data.workspace or data.project or {}).schemes
                if r.code ~= 0 or type(list) ~= "table" or #list == 0 then
                    return notify("xcodebuild -list failed\n" .. (r.stderr or ""), vim.log.levels.ERROR)
                end
                local own, first, rest = own_schemes(p), {}, {}
                for _, s in ipairs(list) do table.insert(own[s] and first or rest, s) end
                local items = vim.list_extend(first, rest)
                local function done(s)
                    state.scheme[p.root] = s
                    if p.file then
                        save_scheme(p, s)
                    else
                        create_project_file(p, s)
                    end
                    notify("scheme: " .. s)
                    cb(s)
                end
                if #items == 1 then return done(items[1]) end
                pick("Scheme · " .. vim.fs.basename(p.workspace or p.project), items, done)
            end)
        end)
    if not ok then notify("cannot run xcodebuild: " .. tostring(err), vim.log.levels.ERROR) end
end

local function with_scheme(p, cb)
    local s = state.scheme[p.root] or p.scheme
    if s then return cb(s) end
    choose_scheme(p, cb)
end

local function with_project(cb)
    local p, err = M.project()
    if not p then return notify(err, vim.log.levels.ERROR) end
    with_scheme(p, function(s) cb(p, s) end)
end

-- the .app a scheme produces, from xcodebuild -showBuildSettings (cached)
local function app_of(p, scheme, cb)
    local key = table.concat({ p.root, scheme, p.configuration }, "|")
    if state.apps[key] then return cb(state.apps[key]) end
    vim.system(xcodebuild_argv(p, scheme, { "-showBuildSettings", "-json" }), { text = true }, function(r)
        vim.schedule(function()
            local ok, data = pcall(vim.json.decode, r.stdout or "")
            if r.code ~= 0 or not ok or type(data) ~= "table" then
                return cb(nil, "-showBuildSettings failed\n" .. (r.stderr or ""))
            end
            for _, t in ipairs(data) do
                local s = t.buildSettings or {}
                if s.PRODUCT_TYPE == "com.apple.product-type.application" then
                    local app = {
                        name = s.FULL_PRODUCT_NAME,
                        bundle = s.TARGET_BUILD_DIR .. "/" .. s.FULL_PRODUCT_NAME,
                        exe = s.TARGET_BUILD_DIR .. "/" .. s.EXECUTABLE_PATH,
                        platform = s.PLATFORM_NAME,
                    }
                    state.apps[key] = app
                    return cb(app)
                end
            end
            cb(nil, "scheme " .. scheme .. " builds no application")
        end)
    end)
end

---------------------------------------------------------------- build window

-- xcodebuild prints every compiler invocation; keep the steps, errors and the result
local STEPS = {
    CompileC = "compile", CompileSwift = "compile", SwiftCompile = "compile",
    CompileAssetCatalog = "assets", CompileStoryboard = "storyboard", CompileXIB = "xib",
    Ld = "link", CodeSign = "sign", PhaseScriptExecution = "script", CpResource = "copy",
}

local function pretty(line)
    if line == "" then return nil end
    if line:match("^\t") then return line end -- "The following build commands failed:" list
    if line:match("^%s") then return nil end  -- command lines, source snippets
    if line:match(": error: ") or line:match(": fatal error: ") or line:match(": warning: ")
        or line:match("^%*%* ") or line:match("^error:") or line:match("^ld: ")
        or line:match("^Undefined symbols") or line:match("^The following build commands") then
        return line
    end
    local step, rest = line:match("^(%a+) (.*)$")
    if step and STEPS[step] then
        local target = rest:match("%(in target '([^']+)'") or ""
        local what
        if STEPS[step] == "compile" then
            what = rest:match("/([^/]-) normal ") or rest:match("/([^/]-%.swift)")
        elseif step == "PhaseScriptExecution" then
            what = rest:match("^(.-) /")
        else
            what = rest:match("/([^/]-) %(in target") or rest:match("/([^/]-)$")
        end
        what = what and what:gsub("\\ ", " "):gsub(" normal$", "")
        return string.format("  %-10s %s  [%s]", STEPS[step], what or "", target)
    end
    return nil
end

local function build_buf()
    if build.buf and vim.api.nvim_buf_is_valid(build.buf) then return build.buf end
    local b = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(b, "xcodebuild://output")
    vim.bo[b].bufhidden = "hide"
    vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = b, desc = "Close build output" })
    vim.keymap.set("n", "L", function() M.log() end, { buffer = b, desc = "Full build log" })
    build.buf = b
    return b
end

local function build_wins()
    local wins = {}
    for _, w in ipairs(vim.api.nvim_list_wins()) do
        if build.buf and vim.api.nvim_win_get_buf(w) == build.buf then wins[#wins + 1] = w end
    end
    return wins
end

local function restore_panels()
    if not package.loaded.dapui then return end
    for _, w in ipairs(vim.api.nvim_list_wins()) do
        if vim.bo[vim.api.nvim_win_get_buf(w)].filetype:find("^dapui_") then
            return require("dapui").open({ reset = true })
        end
    end
end

local function show_build()
    require("kazhakistan.xcode.tab").enter()
    local b = build_buf()
    local tab_wins = vim.api.nvim_tabpage_list_wins(0)
    for _, w in ipairs(tab_wins) do
        if vim.api.nvim_win_get_buf(w) == b then return w end
    end
    local cur = vim.api.nvim_get_current_win()
    vim.cmd("botright 12split")
    local w = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(w, b)
    for opt, val in pairs({ number = false, relativenumber = false, signcolumn = "no",
        winfixheight = true, wrap = false, colorcolumn = "",
        winbar = " xcodebuild   q close · L full log · <leader>xk stop · <leader>qo errors" }) do
        vim.wo[w][opt] = val
    end
    -- the split squeezes the debugger panels; give them their sizes back
    -- once it closes (q, or a debug launch hiding it)
    vim.api.nvim_create_autocmd("WinClosed", {
        pattern = tostring(w),
        once = true,
        callback = function() vim.schedule(restore_panels) end,
    })
    vim.api.nvim_set_current_win(cur)
    return w
end

local function hide_build()
    for _, w in ipairs(build_wins()) do
        if #vim.api.nvim_tabpage_list_wins(vim.api.nvim_win_get_tabpage(w)) > 1 then
            vim.api.nvim_win_close(w, false)
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
        local f, ln, col, kind, msg = l:match("^(/[^:]+):(%d+):(%d+): (%a[%a ]-): (.*)$")
        if f and not seen[l] then
            seen[l] = true
            local item = { filename = f, lnum = tonumber(ln), col = tonumber(col), text = msg }
            if kind == "error" or kind == "fatal error" then
                item.type = "E"
                errors[#errors + 1] = item
            elseif kind == "warning" and f:sub(1, #p.root) == p.root and not f:match("/Pods/") then
                item.type = "W"
                warnings[#warnings + 1] = item
            end
        end
    end
    vim.fn.setqflist({}, " ", { title = "xcodebuild", items = vim.list_extend(vim.list_extend({}, errors), warnings) })
    return #errors, #warnings
end

local function line_reader(on_line)
    local rest = ""
    return function(_, data)
        if not data then
            if rest ~= "" then on_line(rest) end
            rest = ""
            return
        end
        rest = rest .. data
        while true do
            local i = rest:find("\n", 1, true)
            if not i then break end
            on_line(rest:sub(1, i - 1))
            rest = rest:sub(i + 1)
        end
    end
end

local function run_xcodebuild(p, scheme, action, on_done)
    if build.job then
        return notify("a build is already running (<leader>xk stops it)", vim.log.levels.WARN)
    end
    build.raw = {}
    vim.api.nvim_buf_set_lines(build_buf(), 0, -1, false, {
        string.format("▶ %s · %s · %s · %s", action, scheme, p.configuration, vim.fs.basename(p.workspace or p.project)), "",
    })
    show_build()

    local pending, scheduled = {}, false
    local function flush()
        scheduled = false
        local out = {}
        for _, l in ipairs(pending) do out[#out + 1] = pretty(l) end
        pending = {}
        if #out > 0 then append(out) end
    end
    local function on_line(l)
        l = l:gsub("\r", "")
        build.raw[#build.raw + 1] = l
        pending[#pending + 1] = l
        if not scheduled then
            scheduled = true
            vim.schedule(flush)
        end
    end

    local started = vim.uv.now()
    local ok, job = pcall(vim.system, xcodebuild_argv(p, scheme, { action }), {
        text = true, stdout = line_reader(on_line), stderr = line_reader(on_line),
    }, function(r)
        vim.schedule(function()
            flush()
            build.job = nil
            local n_err, n_warn = set_quickfix(p, build.raw)
            local secs = (vim.uv.now() - started) / 1000
            local success = r.code == 0
            local verdict = success and "✔ succeeded" or (r.signal ~= 0 and "■ stopped" or "✘ failed")
            append({ "", string.format("%s in %.1fs · %d errors, %d warnings", verdict, secs, n_err, n_warn) })
            if not success and r.signal == 0 then
                notify(action .. " failed: " .. n_err .. " errors (quickfix)", vim.log.levels.ERROR)
                if n_err > 0 then vim.cmd("botright copen") end
            end
            if on_done then on_done(success) end
        end)
    end)
    if not ok then
        notify("cannot run xcodebuild: " .. tostring(job), vim.log.levels.ERROR)
        return
    end
    build.job = job
end

---------------------------------------------------------------- actions

function M.build(action, after)
    with_project(function(p, scheme)
        run_xcodebuild(p, scheme, action or "build", function(ok)
            if ok and after then after(p, scheme) end
        end)
    end)
end

local function with_app(after)
    M.build("build", function(p, scheme)
        app_of(p, scheme, function(app, err)
            if not app then return notify(err, vim.log.levels.ERROR) end
            after(p, app)
        end)
    end)
end

function M.debug()
    local dbg = require("kazhakistan.xcode.debug")
    if not dbg.setup() then return end
    dbg.stop()
    with_app(function(p, app)
        if app.platform ~= "macosx" then
            return notify("debugging runs macOS apps only (scheme builds for " .. tostring(app.platform) .. ")",
                vim.log.levels.WARN)
        end
        hide_build()
        dbg.launch({
            name = app.name,
            program = app.exe,
            cwd = p.run_cwd or vim.fs.dirname(app.bundle),
            args = p.args,
            env = p.env,
        })
    end)
end

function M.open()
    with_app(function(_, app)
        vim.system({ "open", app.bundle })
        notify("opened " .. app.name)
    end)
end

function M.stop_build()
    if build.job then
        build.job:kill(15)
    else
        notify("no build running")
    end
end

function M.pick_scheme()
    local p, err = M.project()
    if not p then return notify(err, vim.log.levels.ERROR) end
    choose_scheme(p, function() end)
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
    local lines = {
        "root:          " .. p.root,
        "config file:   " .. (p.file or "(none, auto-detected)"),
        "container:     " .. (p.workspace or p.project),
        "scheme:        " .. (state.scheme[p.root] or p.scheme or "(not picked yet)"),
        "configuration: " .. p.configuration,
        "derived data:  " .. p.derived_data,
        "run cwd:       " .. (p.run_cwd or "(app folder)"),
    }
    notify(table.concat(lines, "\n"))
end

---------------------------------------------------------------- keys & help

local function dap_call(fn)
    return function()
        local dbg = require("kazhakistan.xcode.debug")
        if dbg.setup() then dbg[fn]() end
    end
end

local KEYS = {
    { "Build", "<leader>xr", function() M.debug() end, "Build + debug (lldb)" },
    { "Build", "<leader>xo", function() M.open() end, "Build + run without debugger" },
    { "Build", "<leader>xb", function() M.build("build") end, "Build" },
    { "Build", "<leader>xc", function() M.build("clean") end, "Clean" },
    { "Build", "<leader>xk", function() M.stop_build() end, "Stop the running build" },
    { "Build", "<leader>xl", function() M.log() end, "Full log of the last build" },
    { "Build", "<leader>xs", function() M.pick_scheme() end, "Pick scheme" },
    { "Debug", "<F5>", dap_call("continue"), "Continue (starts build + debug if idle)", "<leader>xg" },
    { "Debug", "<S-F5>", dap_call("stop"), "Stop debugging", "<leader>xq" },
    { "Debug", "<F9>", dap_call("toggle_breakpoint"), "Toggle breakpoint", "<leader>b" },
    { "Debug", "<leader>B", dap_call("conditional_breakpoint"), "Conditional breakpoint / logpoint" },
    { "Debug", "<leader>xB", dap_call("clear_breakpoints"), "Remove all breakpoints" },
    { "Debug", "<F10>", dap_call("step_over"), "Step over", "<leader>xn" },
    { "Debug", "<F11>", dap_call("step_into"), "Step into", "<leader>xi" },
    { "Debug", "<F12>", dap_call("step_out"), "Step out", "<leader>xu" },
    { "Debug", "<leader>xC", dap_call("run_to_cursor"), "Run to cursor" },
    { "Debug", "<leader>xe", dap_call("eval"), "Value under cursor / selection", modes = { "n", "v" } },
    { "Debug", "<leader>xd", dap_call("toggle_ui"), "Show / hide debugger panels" },
    { "Debug", "<leader>xv", dap_call("toggle_values"), "Show / hide values next to the code" },
    { "Debug", "<leader>xt", function() require("kazhakistan.xcode.tab").enter() end, "Go to the Xcode tab" },
    { "Debug", "<leader>xh", function() M.help() end, "This help" },
}

local TIPS = {
    "Everything opens in its own Xcode tab (gt / <M-.> to switch back)",
    "Left: stack (<CR> jump to frame), breakpoints, watches; bottom: variables (e edit)",
    "Console (bottom right): app output + lldb, i to type:",
    "  x->y + 1         evaluate an expression in the current frame",
    "  `bt              any lldb command: prefix it with a backtick",
    "  `frame variable  all locals         `thread list   all threads",
    "  `br list         breakpoints        `image lookup -a <addr>",
    "  `watchpoint set variable score      break when a variable changes",
    "  .next .into .out .c .frames         nvim-dap shortcuts (.help)",
    "F11/F12 are macOS shortcuts by default; the <leader>x… keys always work",
}

local help_win
function M.help()
    if help_win and vim.api.nvim_win_is_valid(help_win) then
        vim.api.nvim_win_close(help_win, true)
        help_win = nil
        return
    end
    local lines, section = {}, nil
    for _, k in ipairs(KEYS) do
        if k[1] ~= section then
            section = k[1]
            if #lines > 0 then lines[#lines + 1] = "" end
            lines[#lines + 1] = section
        end
        local lhs = k[5] and (k[2] .. " / " .. k[5]) or k[2]
        lines[#lines + 1] = string.format("  %-24s %s", lhs, k[4])
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "LLDB"
    for _, t in ipairs(TIPS) do lines[#lines + 1] = "  " .. t end

    local width = 0
    for _, l in ipairs(lines) do width = math.max(width, vim.fn.strdisplaywidth(l)) end
    local b = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(b, 0, -1, false, lines)
    vim.bo[b].modifiable = false
    vim.bo[b].bufhidden = "wipe"
    help_win = vim.api.nvim_open_win(b, true, {
        relative = "editor", style = "minimal", border = "rounded",
        title = " Xcode · LLDB ", title_pos = "center",
        width = width + 2, height = #lines,
        row = math.floor((vim.o.lines - #lines) / 2) - 1,
        col = math.floor((vim.o.columns - width) / 2),
    })
    for _, key in ipairs({ "q", "<Esc>", "?" }) do
        vim.keymap.set("n", key, function() M.help() end, { buffer = b, nowait = true })
    end
end

function M.setup()
    for _, k in ipairs(KEYS) do
        local modes = k.modes or "n"
        vim.keymap.set(modes, k[2], k[3], { desc = k[4] })
        if k[5] then vim.keymap.set(modes, k[5], k[3], { desc = k[4] }) end
    end

    local cmds = {
        XBuild = function() M.build("build") end,
        XClean = function() M.build("clean") end,
        XDebug = M.debug,
        XRun = M.open,
        XStop = M.stop_build,
        XScheme = M.pick_scheme,
        XLog = M.log,
        XInfo = M.info,
        XHelp = M.help,
    }
    for name, fn in pairs(cmds) do
        vim.api.nvim_create_user_command(name, function() fn() end, {})
    end

    -- edits to .xcode.lua apply on the next command
    vim.api.nvim_create_autocmd("BufWritePost", {
        group = vim.api.nvim_create_augroup("XcodeProjectFile", { clear = true }),
        pattern = ".xcode.lua",
        callback = function(ev)
            -- saved by hand from nvim: keep it trusted instead of asking again
            vim.secure.trust({ action = "allow", bufnr = ev.buf })
            state.projects[vim.fs.dirname(vim.fs.normalize(ev.match))] = nil
            state.apps = {}
        end,
    })
end

return M
