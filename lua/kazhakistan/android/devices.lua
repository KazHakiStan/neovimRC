-- Android devices: phones over USB or Wi-Fi and emulators, running or not.
-- Picking an emulator that isn't running starts it and waits until it has
-- booted. Wi-Fi: a USB phone can switch over (then unplug it), and a new phone
-- pairs with the code from Developer options > Wireless debugging (Android 11+).
local D = {}

local function notify(msg, level)
    vim.notify(msg, level or vim.log.levels.INFO, { title = "Android" })
end

local function run(argv)
    local ok, r = pcall(function() return vim.system(argv, { text = true }):wait() end)
    if not ok then return false, "" end
    return r.code == 0, r.stdout or ""
end

-- { serial, state, name, emulator } for everything adb sees
function D.connected(env)
    local ok, out = run({ env.adb, "devices", "-l" })
    if not ok then return {} end
    local list = {}
    for line in out:gmatch("[^\n]+") do
        local serial, st, rest = line:match("^(%S+)%s+(%S+)%s*(.*)$")
        if serial and serial ~= "List" and not line:match("^%*") then
            local d = { serial = serial, state = st, emulator = serial:match("^emulator%-") ~= nil }
            if d.emulator and st == "device" then
                local _, name = run({ env.adb, "-s", serial, "emu", "avd", "name" })
                d.avd = vim.trim(name:match("^[^\r\n]*") or "")
                d.name = d.avd ~= "" and d.avd or serial
            else
                d.name = ((rest:match("model:(%S+)") or serial):gsub("_", " "))
            end
            list[#list + 1] = d
        end
    end
    return list
end

-- emulator names (AVDs) from the SDK's emulator
function D.avds(env)
    if not env.emulator then return {} end
    local ok, out = run({ env.emulator, "-list-avds" })
    if not ok then return {} end
    local list = {}
    for line in out:gmatch("[^\r\n]+") do
        if not line:match("^INFO") and not line:match("^WARNING") and line:match("^%S+$") then
            list[#list + 1] = line
        end
    end
    return list
end

-- start an AVD, wait for it to boot, then cb(serial)
function D.start_avd(env, name, cb)
    notify("starting emulator " .. name .. "…")
    local ok, err = pcall(vim.system, { env.emulator, "-avd", name }, { detach = true, text = true })
    if not ok then return notify("cannot start the emulator: " .. tostring(err), vim.log.levels.ERROR) end
    local deadline = vim.uv.now() + 180000
    local serial
    local timer = vim.uv.new_timer()
    timer:start(2000, 2000, vim.schedule_wrap(function()
        if vim.uv.now() > deadline then
            timer:stop()
            timer:close()
            return notify("emulator " .. name .. " didn't come up in 3 minutes", vim.log.levels.ERROR)
        end
        if not serial then
            for _, d in ipairs(D.connected(env)) do
                if d.emulator and d.avd == name then serial = d.serial end
            end
            return
        end
        local _, booted = run({ env.adb, "-s", serial, "shell", "getprop", "sys.boot_completed" })
        if vim.trim(booted) == "1" then
            timer:stop()
            timer:close()
            notify("emulator " .. name .. " is up")
            cb(serial)
        end
    end))
end

-- the phone's address on Wi-Fi (wlan0), for adb connect
local function wifi_ip(env, serial)
    local _, out = run({ env.adb, "-s", serial, "shell", "ip", "-f", "inet", "addr", "show", "wlan0" })
    return out:match("inet (%d+%.%d+%.%d+%.%d+)")
end

-- a USB phone over Wi-Fi: adb listens on 5555 and connects to it
local function switch_to_wifi(env, d, cb)
    local ip = wifi_ip(env, d.serial)
    if not ip then return notify(d.name .. " isn't on Wi-Fi", vim.log.levels.WARN) end
    run({ env.adb, "-s", d.serial, "tcpip", "5555" })
    vim.defer_fn(function()
        local _, out = run({ env.adb, "connect", ip .. ":5555" })
        if not out:match("connected to") then
            return notify("adb connect " .. ip .. ":5555 failed: " .. vim.trim(out), vim.log.levels.ERROR)
        end
        notify(d.name .. " is on Wi-Fi (" .. ip .. ":5555): you can unplug it")
        cb(ip .. ":5555", d.name)
    end, 2000)
end

-- Wireless debugging (Android 11+): pair once with the code, then connect
local function pair(env, cb)
    vim.ui.input({ prompt = "Wireless debugging > Pair device with pairing code: IP:port " }, function(addr)
        if not addr or vim.trim(addr) == "" then return end
        vim.ui.input({ prompt = "Pairing code: " }, function(code)
            if not code or vim.trim(code) == "" then return end
            local _, out = run({ env.adb, "pair", vim.trim(addr), vim.trim(code) })
            if not out:match("Successfully paired") then
                return notify("adb pair failed: " .. vim.trim(out), vim.log.levels.ERROR)
            end
            local host = vim.trim(addr):match("^(.*):%d+$")
            -- adb usually connects by itself (mDNS) in a moment; else ask for the port
            vim.defer_fn(function()
                for _, d in ipairs(D.connected(env)) do
                    if d.state == "device" and (d.serial:find(host, 1, true) or d.serial:match("^adb%-")) then
                        notify("paired and connected: " .. d.name)
                        return cb(d.serial, d.name)
                    end
                end
                vim.ui.input({ prompt = "Paired. Wireless debugging > IP address & port: ", default = host .. ":" },
                    function(target)
                        if not target or vim.trim(target) == "" then return end
                        local _, res = run({ env.adb, "connect", vim.trim(target) })
                        if not res:match("connected to") then
                            return notify("adb connect failed: " .. vim.trim(res), vim.log.levels.ERROR)
                        end
                        cb(vim.trim(target), vim.trim(target))
                    end)
            end, 3000)
        end)
    end)
end

-- choose among connected devices and emulators that could be started
function D.pick(env, pick, cb)
    local items, actions = {}, {}
    local running = {}
    for _, d in ipairs(D.connected(env)) do
        local label
        if d.state == "device" then
            label = ("● %s  %s"):format(d.name, d.serial)
            actions[label] = function() cb(d.serial, d.name) end
        elseif d.state == "unauthorized" then
            label = ("! %s  allow USB debugging on the device, then pick again"):format(d.serial)
            actions[label] = function() end
        else
            label = ("! %s  %s"):format(d.serial, d.state)
            actions[label] = function() end
        end
        if d.avd then running[d.avd] = true end
        items[#items + 1] = label
        -- over USB (not an emulator, not already Wi-Fi): offer the switch
        if d.state == "device" and not d.emulator and not d.serial:match(":%d+$") and not d.serial:match("^adb%-") then
            local wifi = ("⇄ %s over Wi-Fi  then unplug it"):format(d.name)
            actions[wifi] = function() switch_to_wifi(env, d, cb) end
            items[#items + 1] = wifi
        end
    end
    for _, name in ipairs(D.avds(env)) do
        if not running[name] then
            local label = ("○ %s  start the emulator"):format(name)
            actions[label] = function()
                D.start_avd(env, name, function(serial) cb(serial, name) end)
            end
            items[#items + 1] = label
        end
    end
    local pair_label = "+ pair a phone over Wi-Fi  Android 11+: Developer options > Wireless debugging"
    actions[pair_label] = function() pair(env, cb) end
    items[#items + 1] = pair_label
    pick("Android device", items, function(choice) actions[choice]() end)
end

return D
