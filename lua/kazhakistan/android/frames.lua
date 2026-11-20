-- Stack frames -> source lines: Kotlin / Java (at a.b.C.f(C.kt:12), found in
-- the repo) and native C++ (#05 pc 0012ab libgame.so, through the NDK's
-- llvm-symbolizer and the unstripped .so with the crash's BuildId).
local F = {}

local found = {} -- package path + file name -> path in the repo (or false)

-- at com.game.Foo$bar$1.invoke(Foo.kt:12) -> the file in the repo
local function java_frame(text, ctx)
    local class, file, line = text:match("at ([%w_%.$]+)%.[%w_$<>%-]+%(([%w_%-]+%.%a+):(%d+)%)")
    if not class then return nil end
    local dir = (class:match("^(.*)%.[^%.]+$") or ""):gsub("%.", "/")
    local key = ctx.repo .. ":" .. dir .. "/" .. file
    if found[key] == nil then
        local hits = vim.fs.find(file, { path = ctx.repo, type = "file", limit = 50 })
        local best = false
        -- not build output or hidden folders; the one in the package's folder first
        for _, h in ipairs(hits) do
            if not h:find("/build/", 1, true) and not h:find("/%.") then
                if h:find("/" .. dir .. "/" .. file, 1, true) then best = h break end
                best = best or h
            end
        end
        found[key] = best
    end
    if not found[key] then return nil, file .. " isn't in this repo (library or system code)" end
    return { filename = found[key], lnum = tonumber(line), text = class }
end

local ABI = { arm64 = "arm64-v8a", arm = "armeabi-v7a", x86_64 = "x86_64", x86 = "x86" }

local function symbolizer(sdk)
    local host = vim.fn.has("win32") == 1 and "windows-x86_64" or (vim.fn.has("mac") == 1 and "darwin-x86_64" or "linux-x86_64")
    local found = vim.fn.glob(sdk .. "/ndk/*/toolchains/llvm/prebuilt/" .. host .. "/bin/llvm-symbolizer*", false, true)
    -- the newest NDK first
    table.sort(found, function(a, b)
        return vim.version.gt(a:match("/ndk/([^/]+)/") or "0", b:match("/ndk/([^/]+)/") or "0")
    end)
    return found[1]
end

local function newest(paths)
    local best, best_t
    for _, p in ipairs(paths) do
        local st = vim.uv.fs_stat(p)
        if st and (not best_t or st.mtime.sec > best_t) then best, best_t = p, st.mtime.sec end
    end
    return best
end

-- GNU build id of a library (readelf from the same NDK), cached by mtime
local build_ids = {}
local function build_id(tool, so)
    local st = vim.uv.fs_stat(so)
    local key = so .. ":" .. (st and st.mtime.sec or 0)
    if build_ids[key] == nil then
        local readelf = tool:gsub("llvm%-symbolizer", "llvm-readelf")
        local r = vim.system({ readelf, "--notes", so }, { text = true }):wait()
        build_ids[key] = (r.stdout or ""):match("Build ID: (%x+)") or false
    end
    return build_ids[key]
end

-- #05 pc 000000000012abcd  /data/app/…/lib/arm64/libgame.so (…) -> file:line
local function native_frame(text, ctx, abi_hint)
    local pc, path = text:match("#%d+ pc (%x+)%s+(%S+%.so)")
    if not pc then return nil end
    local lib = vim.fs.basename(path):gsub("^.*!", "")
    local abi = ABI[path:match("/lib/([%w_]+)/") or ""] or abi_hint or "arm64-v8a"
    -- the unstripped library the build left behind: the one with the crash's
    -- BuildId, else the newest of the variants
    local tool = ctx.sdk and symbolizer(ctx.sdk)
    if not tool then return nil, "no llvm-symbolizer: install the NDK (Android Studio > SDK Manager)" end
    local candidates = vim.fn.glob(ctx.module_dir .. "/build/intermediates/cxx/*/*/obj/" .. abi .. "/" .. lib,
        false, true)
    local want = text:match("BuildId: (%x+)")
    local so
    if want then
        for _, c in ipairs(candidates) do
            if build_id(tool, c) == want then so = c end
        end
        if not so and #candidates > 0 then
            return nil, lib .. ": none of the local builds is the one that crashed (BuildId " .. want .. ")"
        end
    end
    so = so or newest(candidates)
    if not so then return nil, lib .. " isn't from this project's native build (" .. abi .. ")" end
    local r = vim.system({ tool, "--obj=" .. so, "0x" .. pc }, { text = true }):wait()
    local func, loc = (r.stdout or ""):match("^([^\n]*)\n([^\n]*)")
    local file, line = (loc or ""):match("^(.*):(%d+):%d+$")
    if not file then file, line = (loc or ""):match("^(.*):(%d+)$") end
    if not file or file == "??" or line == "0" then return nil, "no line info for " .. lib .. "+0x" .. pc end
    return { filename = file, lnum = tonumber(line), text = func }
end

-- a stack frame line -> { filename, lnum, text } in the project, or nil + why
-- ctx = { repo, module_dir, sdk }; abi: the device's, for native frames
function F.resolve(text, ctx, abi)
    if not ctx then return nil end
    local item, err = java_frame(text, ctx)
    if item or err then return item, err end
    return native_frame(text, ctx, abi)
end

function F.is_frame(text)
    return text:match("%sat [%w_%.$]+%.[%w_$<>%-]+%(") or text:match("#%d+ pc %x+") ~= nil
end


return F
