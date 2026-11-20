-- Android devices: phones over USB (or Wi-Fi adb) and emulators, running or
-- not. Picking an emulator that isn't running starts it and waits until it
-- has booted.
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
    if #items == 0 then
        return notify("no devices: plug in a phone with USB debugging on, or create an emulator "
            .. "in Android Studio (Device Manager)", vim.log.levels.WARN)
    end
    pick("Android device", items, function(choice) actions[choice]() end)
end

return D
