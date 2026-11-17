local ok, autosession = pcall(require, "auto-session")
if not ok then return end

-- Sessions are managed manually on both platforms.
autosession.setup({
    auto_save = false,
    auto_restore = false,
    cwd_change_handling = true,
})
