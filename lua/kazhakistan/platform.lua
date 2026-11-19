local M = {}
M.is_windows = vim.fn.has("win32") == 1
M.is_macos = vim.fn.has("macunix") == 1

function M.setup_shell()
    if M.is_windows then
        vim.opt.shell = vim.fn.executable("pwsh") == 1 and "pwsh" or "powershell"
        vim.opt.shellcmdflag = "-NoLogo -NoProfile -ExecutionPolicy RemoteSigned -Command"
        vim.opt.shellquote = ""
        vim.opt.shellxquote = ""
        vim.opt.shellredir = "2>&1 | Out-File -Encoding UTF8 %s; exit $LastExitCode"
        vim.opt.shellpipe = "2>&1 | Out-File -Encoding UTF8 %s; exit $LastExitCode"
    elseif M.is_macos then
        vim.opt.shell = "/bin/zsh"
        vim.opt.shellcmdflag = "-c"
    end
end

function M.clangd_cmd()
    if M.is_windows then
        -- Keep clangd and the compiler driver in the same MSYS2 environment:
        -- the clangd on PATH (`path` in ~/.config/kazrc/nvim.lua) if its folder
        -- has gcc too, else the default MSYS2 install.
        local bins = {}
        local on_path = vim.fn.exepath("clangd")
        if on_path ~= "" then bins[1] = vim.fs.dirname(vim.fs.normalize(on_path)) .. "/" end
        for _, prefix in ipairs({ "C:/msys64/mingw64", "C:/msys64/ucrt64" }) do
            bins[#bins + 1] = prefix .. "/bin/"
        end
        for _, bin in ipairs(bins) do
            if vim.fn.executable(bin .. "clangd.exe") == 1 and vim.fn.executable(bin .. "g++.exe") == 1 then
                return {
                    bin .. "clangd.exe",
                    "--query-driver=" .. bin .. "g++.exe," .. bin .. "gcc.exe",
                }
            end
        end
    end
    return { "clangd" }
end

-- A JDK new enough for jdtls (21+): JAVA_HOME if it is one, else the usual
-- install places (macOS java_home, Scoop, Adoptium / Microsoft installers,
-- /usr/lib/jvm). nil when there's none.
local function java_major(home)
    local exe = home .. "/bin/java" .. (M.is_windows and ".exe" or "")
    if vim.fn.executable(exe) == 0 then return 0 end
    local out = vim.system({ exe, "-version" }, { text = true }):wait()
    return tonumber(((out.stderr or "") .. (out.stdout or "")):match('version "(%d+)')) or 0
end

function M.jdk(min)
    min = min or 21
    local candidates = {}
    if vim.env.JAVA_HOME then candidates[1] = vim.env.JAVA_HOME end
    if M.is_macos then
        local r = vim.system({ "/usr/libexec/java_home", "-v", min .. "+" }, { text = true }):wait()
        if r.code == 0 then table.insert(candidates, 1, vim.trim(r.stdout)) end
    end
    local globs = M.is_windows
        and { "~/scoop/apps/temurin*-jdk/current", "~/scoop/apps/openjdk*/current",
              "C:/Program Files/Eclipse Adoptium/jdk-*", "C:/Program Files/Microsoft/jdk-*" }
        or { "/usr/lib/jvm/*", "~/Library/Java/JavaVirtualMachines/*/Contents/Home",
             "/Library/Java/JavaVirtualMachines/*/Contents/Home" }
    for _, g in ipairs(globs) do
        vim.list_extend(candidates, vim.fn.glob(vim.fn.expand(g), false, true))
    end
    for _, home in ipairs(candidates) do
        if java_major(home) >= min then return home end
    end
end

return M
