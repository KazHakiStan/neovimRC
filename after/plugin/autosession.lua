-- Sessions, by hand only: <leader>ss save, <leader>sr restore, <leader>sd
-- delete (:AutoSession search lists them). Nothing is saved, restored,
-- created or switched on its own; automation goes on top of this later.
local ok, autosession = pcall(require, "auto-session")
if not ok then return end

autosession.setup({
    enabled = false, -- no automatic create / save / restore
    auto_save = false,
    auto_restore = false,
    auto_create = false,
    auto_restore_last_session = false,
    -- projects.auto_cd changes directory all the time: leave sessions alone
    cwd_change_handling = false,
})
