-- C++ (NDK) debugging of the app on a device, as Android Studio does it: the
-- NDK's lldb-server goes into the app's own folder (run-as: debug builds
-- only), lldb-dap on this machine connects to it and attaches to the app's
-- process, with symbols from the unstripped libraries of the local build.
-- Same panels and keys as Xcode debugging (kazhakistan/xcode/debug.lua).
--
-- Started from nvim, the app waits for a debugger first (am start -D), so
-- breakpoints in startup code hit too: the native side attaches, then the
-- Java side is let go.
local D = {}

local ARCH = { ["arm64-v8a"] = "aarch64", ["armeabi-v7a"] = "arm", x86_64 = "x86_64", x86 = "i386" }
local SOCKET = "nvim-lldb/platform.sock"

-- ART raises SIGSEGV / SIGBUS on purpose (null checks, suspend points) and
-- handles them itself: let them through without stopping, as Studio does. A
-- real crash still stops, in art_sigsegv_fault (the frames below it are yours).
local ART_SIGNALS = {
    "process handle SIGSEGV --notify false --pass true --stop false",
    "process handle SIGBUS --notify false --pass true --stop false",
    "breakpoint set --name art_sigsegv_fault",
}

local function notify(msg, level)
    vim.notify(msg, level or vim.log.levels.INFO, { title = "Android debug" })
end

local function adb(e, serial, args, cb)
    local argv = { e.adb, "-s", serial }
    vim.list_extend(argv, args)
    if cb then
        return vim.system(argv, { text = true }, function(r)
            vim.schedule(function() cb(r.code == 0, vim.trim(r.stdout or ""), vim.trim(r.stderr or "")) end)
        end)
    end
    local r = vim.system(argv, { text = true }):wait()
    return r.code == 0, vim.trim(r.stdout or ""), vim.trim(r.stderr or "")
end

-- the NDK's lldb-server for the device's CPU (newest NDK)
local function lldb_server(e, abi)
    local host = vim.fn.has("win32") == 1 and "windows-x86_64" or (vim.fn.has("mac") == 1 and "darwin-x86_64" or "linux-x86_64")
    local found = vim.fn.glob(e.sdk .. "/ndk/*/toolchains/llvm/prebuilt/" .. host .. "/lib/clang/*/lib/linux/"
        .. (ARCH[abi] or "aarch64") .. "/lldb-server", false, true)
    table.sort(found, function(a, b)
        return vim.version.gt(a:match("/ndk/([^/]+)/") or "0", b:match("/ndk/([^/]+)/") or "0")
    end)
    return found[1]
end

-- folder with the unstripped .so of the newest native build for this CPU
local function symbols_dir(p, abi)
    local best, best_t
    for _, dir in ipairs(vim.fn.glob(p.module_dir .. "/build/intermediates/cxx/*/*/obj/" .. abi, false, true)) do
        for _, so in ipairs(vim.fn.glob(dir .. "/*.so", false, true)) do
            local st = vim.uv.fs_stat(so)
            if st and (not best_t or st.mtime.sec > best_t) then best, best_t = dir, st.mtime.sec end
        end
    end
    return best
end

-- the server into the app's folder (only the app's own user may run there)
local function deploy(e, serial, id, abi)
    local server = lldb_server(e, abi)
    if not server then return nil, "no lldb-server in the NDK: install the NDK (Android Studio > SDK Manager)" end
    local ok, _, err = adb(e, serial, { "push", server, "/data/local/tmp/lldb-server" })
    if not ok then return nil, "adb push lldb-server: " .. err end
    local dir = "/data/data/" .. id .. "/lldb/bin"
    local out
    ok, out, err = adb(e, serial, { "shell", ("cat /data/local/tmp/lldb-server | run-as %s sh -c "
        .. "'mkdir -p %s && cat > %s/lldb-server && chmod 700 %s/lldb-server' && echo ok"):format(id, dir, dir, dir) })
    if not (ok and out:match("ok$")) then
        if (out .. err):match("not debuggable") then
            return nil, id .. " can't be debugged: not a debug build (pick one with <leader>nv)"
        end
        return nil, "couldn't put lldb-server on the device: " .. out .. err
    end
    return dir .. "/lldb-server"
end

local server_job

-- sync = before starting a new one (an async pkill could hit the new server)
local function stop_server(e, serial, id, sync)
    if server_job then
        pcall(function() server_job:kill(15) end)
        server_job = nil
    end
    adb(e, serial, { "shell", "run-as", id, "pkill", "-f", "lldb-server" }, (not sync) and function() end or nil)
    -- lldb forwards a port to the server and one to each debug connection
    -- (gdbserver.*) and leaves them behind
    local _, list = adb(e, serial, { "forward", "--list" })
    for line in list:gmatch("[^\r\n]+") do
        local s_, local_, remote = line:match("^(%S+)%s+(%S+)%s+(%S+)")
        if s_ == serial and (remote:find("/" .. id .. "/nvim-lldb/", 1, true) or remote:match("^localabstract:gdbserver%.")) then
            adb(e, serial, { "forward", "--remove", local_ }, function() end)
        end
    end
end

-- the app waits in "Waiting for debugger" (am start -D) until a Java
-- debugger shows up and does something: shake hands, ask the VM its version
-- (JDWP command set 1, command 1), hold on a moment, let go
local function release_java(e, serial, pid)
    local ok, port = adb(e, serial, { "forward", "tcp:0", "jdwp:" .. pid })
    port = ok and tonumber(port)
    if not port then return notify("couldn't reach the app's Java side (adb forward)", vim.log.levels.WARN) end
    local sock = vim.uv.new_tcp()
    local closed = false
    local function close()
        if closed then return end
        closed = true
        pcall(function() sock:read_stop() sock:close() end)
        vim.schedule(function() adb(e, serial, { "forward", "--remove", "tcp:" .. port }, function() end) end)
    end
    -- the app answers once it runs again (the native attach paused it): the
    -- handshake back (14 bytes) and the version reply; then a moment for it to
    -- see the debugger settle, and go
    local got = 0
    sock:connect("127.0.0.1", port, function(err)
        if err then return close() end
        sock:write("JDWP-Handshake")
        -- length 11, id 1, flags 0, command set 1 (VirtualMachine), command 1 (Version)
        sock:write(string.char(0, 0, 0, 11, 0, 0, 0, 1, 0, 1, 1))
        sock:read_start(function(rerr, data)
            if rerr or not data then return close() end
            got = got + #data
            if got >= 14 + 11 then
                local t = vim.uv.new_timer()
                t:start(1500, 0, function() t:close() close() end)
            end
        end)
    end)
    -- never hold it forever
    local guard = vim.uv.new_timer()
    guard:start(60000, 0, function() guard:close() close() end)
end

local function wait_pid(e, serial, id, cb, tries)
    tries = tries or 40
    adb(e, serial, { "shell", "pidof", "-s", id }, function(_, pid)
        if pid ~= "" then return cb(pid) end
        if tries <= 1 then return cb(nil) end
        vim.defer_fn(function() wait_pid(e, serial, id, cb, tries - 1) end, 250)
    end)
end

-- attach to the app `id` on `serial`; waiting = it was started with -D
function D.attach(p, e, serial, id, waiting)
    local dbg = require("kazhakistan.xcode.debug")
    if not dbg.setup() then return end
    local _, abi = adb(e, serial, { "shell", "getprop", "ro.product.cpu.abi" })
    local symbols = symbols_dir(p, abi)
    if not symbols then
        notify("no native build for " .. abi .. " in " .. p.module_dir .. "/build: only Java/Kotlin here?",
            vim.log.levels.WARN)
    end
    -- an old server (a session before) keeps its file busy
    stop_server(e, serial, id, true)
    local server, err = deploy(e, serial, id, abi)
    if not server then return notify(err, vim.log.levels.ERROR) end
    server_job = vim.system({ e.adb, "-s", serial, "shell", "run-as", id, server, "platform", "--server",
        "--listen", "unix-abstract:///" .. id .. "/" .. SOCKET }, { text = true })

    wait_pid(e, serial, id, function(pid)
        if not pid then return notify(id .. " isn't running", vim.log.levels.ERROR) end
        -- a serial with a port (Wi-Fi) goes in brackets in the connect URL
        local host = serial:find(":", 1, true) and ("[" .. serial .. "]") or serial
        local init = {
            "platform select remote-android",
            ("platform connect unix-abstract-connect://%s/%s/%s"):format(host, id, SOCKET),
        }
        if symbols then init[#init + 1] = "settings append target.exec-search-paths " .. symbols end
        dbg.starter = function() require("kazhakistan.android").debug() end
        if waiting then
            local dap = require("dap")
            dap.listeners.after.configurationDone.android = function()
                dap.listeners.after.configurationDone.android = nil
                release_java(e, serial, pid)
            end
        end
        notify(("attaching to %s (pid %s)…"):format(id, pid))
        -- the server needs a moment to listen
        vim.defer_fn(function()
            dbg.attach({ name = id, pid = tonumber(pid), initCommands = init, postRunCommands = ART_SIGNALS }, function()
                stop_server(e, serial, id)
            end)
        end, 700)
    end)
end

return D
