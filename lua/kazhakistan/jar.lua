-- jar:///…/lib.jar!/pkg/Name.class: where kotlin-lsp (and jdtls) send "go to
-- definition" for library code. nvim can't open those by itself; this shows
-- a sources file as is and a compiled class as its API (javap).
local M = {}

local platform = require("kazhakistan.platform")

local function javap()
    local studio = platform.is_windows and "C:/Program Files/Android/Android Studio/jbr"
        or "/Applications/Android Studio.app/Contents/jbr/Contents/Home"
    for _, home in ipairs({ studio, vim.env.JAVA_HOME, platform.jdk(11) }) do
        local exe = home and (home .. "/bin/javap" .. (platform.is_windows and ".exe" or ""))
        if exe and vim.fn.executable(exe) == 1 then return exe end
    end
    return vim.fn.executable("javap") == 1 and "javap" or nil
end

local function read(uri)
    local jar, inner = uri:match("^jar:/*(.-)!/(.+)$")
    if not jar then return nil, "not a jar uri: " .. uri end
    jar = jar:gsub("^file:/*", "")
    jar = (platform.is_windows and jar:match("^%a:")) and jar or ("/" .. jar)
    jar = jar:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
    if inner:match("%.class$") then
        local exe = javap()
        if not exe then return nil, "no javap (a JDK) to show " .. inner end
        local class = inner:gsub("%.class$", ""):gsub("/", ".")
        local r = vim.system({ exe, "-public", "-cp", jar, class }, { text = true }):wait()
        if r.code ~= 0 then return nil, r.stderr end
        return "// " .. class .. " (compiled, no sources: the public API from javap)\n" .. r.stdout, "java"
    end
    -- sources: macOS and Windows tar read zips, Linux has unzip
    local argv = vim.fn.has("linux") == 1 and { "unzip", "-p", jar, inner } or { "tar", "-xOf", jar, inner }
    local r = vim.system(argv, { text = true }):wait()
    if r.code ~= 0 then return nil, r.stderr end
    return r.stdout, vim.filetype.match({ filename = inner })
end

function M.setup()
    vim.api.nvim_create_autocmd("BufReadCmd", {
        group = vim.api.nvim_create_augroup("KazJar", { clear = true }),
        -- with a "/" in it, the pattern matches the whole name, not only its tail
        pattern = { "jar:/*", "jar:file:/*" },
        callback = function(ev)
            local text, ft = read(ev.match)
            if not text then
                vim.notify(ft or "can't open " .. ev.match, vim.log.levels.WARN)
                text, ft = "", nil
            end
            vim.bo[ev.buf].modifiable = true
            vim.api.nvim_buf_set_lines(ev.buf, 0, -1, false, vim.split(text, "\n", { plain = true }))
            vim.bo[ev.buf].buftype = "nofile"
            vim.bo[ev.buf].modifiable = false
            vim.bo[ev.buf].modified = false
            -- colours only: a real filetype would start jdtls / kotlin-lsp on it
            local lang = ft and vim.treesitter.language.get_lang(ft)
            if not (lang and pcall(vim.treesitter.start, ev.buf, lang)) and ft then
                vim.bo[ev.buf].syntax = ft
            end
        end,
    })
end

return M
