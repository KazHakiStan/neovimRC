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
        -- Keep clangd and the compiler driver in the same MSYS2 environment.
        for _, prefix in ipairs({ "C:/msys64/mingw64", "C:/msys64/ucrt64" }) do
            local bin = prefix .. "/bin/"
            if vim.fn.executable(bin .. "clangd.exe") == 1 then
                return {
                    bin .. "clangd.exe",
                    "--query-driver=" .. bin .. "g++.exe," .. bin .. "gcc.exe",
                }
            end
        end
    end
    return { "clangd" }
end

return M
