-- Updates of this config (neovimRC). Releases are tags (v1.2.0) on master;
-- this clone stays on master and moves forward to them, so a plain `git pull`
-- still works. Once in a while (updates.check_hours) nvim fetches in the
-- background and says on start when there's something new; :KazUpdate takes
-- it and syncs plugins and parsers to it.
--   updates.follow = "release"  tagged versions (default)
--                    "latest"   every commit on master
--                    "off"      no checks
-- Your own changes live in ~/.config/kazrc; changes made in this repo stop an
-- update (it names the files) rather than being overwritten.
local M = {}

M.dir = vim.fn.stdpath("config")
M.name = "neovimRC"

local kazrc = require("kazhakistan.kazrc")
local FOLLOW = { release = true, latest = true, off = true }

local function settings()
    local s = kazrc.get().updates
    if not FOLLOW[s.follow] then
        return { follow = "release", check_hours = s.check_hours }
    end
    return s
end

local function say(msg, level)
    vim.notify(msg, level or vim.log.levels.INFO, { title = M.name })
end

-- git in M.dir, from inside a coroutine: ok, stdout, stderr (trimmed)
local function git(args)
    local co = coroutine.running()
    local cmd = { "git", "-C", M.dir }
    vim.list_extend(cmd, args)
    local spawned, err = pcall(vim.system, cmd, {
        text = true,
        -- never stop for a password or a passphrase
        env = { GIT_TERMINAL_PROMPT = "0", GIT_SSH_COMMAND = "ssh -o BatchMode=yes" },
    }, function(r) vim.schedule(function() coroutine.resume(co, r) end) end)
    if not spawned then return false, "", tostring(err) end
    local r = coroutine.yield()
    return r.code == 0, vim.trim(r.stdout or ""), vim.trim(r.stderr or "")
end

-- the repos are public: fetch a GitHub SSH origin over HTTPS, so a key with a
-- passphrase (or none at all) doesn't matter
local function fetch_url(origin)
    local path = origin:match("^git@github%.com:(.+)$") or origin:match("^ssh://git@github%.com/(.+)$")
    return path and ("https://github.com/" .. path) or origin
end

local function fetch(branch)
    local ok, origin = git({ "remote", "get-url", "origin" })
    if not ok then return false end
    return (git({ "fetch", "--quiet", "--tags", "--force", fetch_url(origin),
        ("+refs/heads/%s:refs/remotes/origin/%s"):format(branch, branch) }))
end

-- What an update would bring: { target, label, current, count }, or nil and
-- why not (nil, nil = up to date).
local function status(do_fetch)
    local on_branch, branch = git({ "symbolic-ref", "--quiet", "--short", "HEAD" })
    if not on_branch then return nil, "the repo isn't on a branch" end
    if do_fetch and not fetch(branch) then return nil, "couldn't reach the repo" end
    local _, current = git({ "describe", "--tags", "--abbrev=0", "--match", "v*" })
    local s = { current = current ~= "" and current or nil }
    local target
    if settings().follow == "latest" then
        target = "origin/" .. branch
    else
        local _, tags = git({ "tag", "--list", "v*", "--sort=-v:refname" })
        target = tags:match("^[^\n]+")
        if not target then return nil, "no releases yet" end
        s.label = target
    end
    local _, count = git({ "rev-list", "--count", "HEAD.." .. target })
    count = tonumber(count) or 0
    if count == 0 then return nil end -- up to date, or ahead of it
    if not git({ "merge-base", "--is-ancestor", "HEAD", target }) then
        return nil, "this clone has commits of its own (git log " .. target .. "..HEAD)"
    end
    s.target, s.count = target, count
    s.label = s.label or (count == 1 and "1 new commit" or (count .. " new commits"))
    return s
end

local function fetched_long_ago()
    local st = vim.uv.fs_stat(M.dir .. "/.git/FETCH_HEAD")
    return not st or os.time() - st.mtime.sec > settings().check_hours * 3600
end

-- on start: fetch if it's time, say so if there's an update (one line)
function M.check()
    if settings().follow == "off" or not vim.uv.fs_stat(M.dir .. "/.git") then return end
    coroutine.wrap(function()
        local s = status(fetched_long_ago())
        if not s then return end
        local have = s.current and (" (you have " .. s.current .. ")") or ""
        say(("%s: %s%s, :KazUpdate takes it"):format(M.name, s.label, have))
    end)()
end

-- plugins at the new lazy-lock.json and the parsers it lists, by a fresh nvim
-- that loads the new config
local function sync(done)
    vim.system({ vim.v.progpath, "--headless", "+Lazy! restore",
        "+lua local t = require('kazhakistan.treesitter').install() if t then t:wait(1800000) end",
        "+quitall" }, { text = true }, function(r) vim.schedule(function() done(r.code == 0) end) end)
end

function M.update()
    coroutine.wrap(function()
        say("checking for updates…")
        local s, why = status(true)
        if not s then
            if why then return say("not updated: " .. why, vim.log.levels.WARN) end
            local _, current = git({ "describe", "--tags", "--match", "v*" })
            return say(M.name .. " is up to date" .. (current ~= "" and (" (" .. current .. ")") or ""))
        end
        -- lazy rewrites lazy-lock.json; the repo's copy is the one to keep
        local _, changed = git({ "diff", "--name-only", "HEAD" })
        local files = {}
        for file in changed:gmatch("[^\n]+") do
            if file ~= "lazy-lock.json" then files[#files + 1] = file end
        end
        if #files > 0 then
            return say(("not updated: changed in %s: %s. Move your changes to ~/.config/kazrc "
                .. "(:KazConfig), then `git checkout .` there"):format(M.dir, table.concat(files, ", ")),
                vim.log.levels.WARN)
        end
        local _, log = git({ "log", "--reverse", "--format=• %s", "HEAD.." .. s.target })
        git({ "checkout", "--", "lazy-lock.json" })
        local ok, _, err = git({ "merge", "--ff-only", "--quiet", s.target })
        if not ok then return say("not updated: " .. err, vim.log.levels.ERROR) end
        say(("%s: %s, syncing plugins and parsers…"):format(M.name, s.label))
        sync(function(synced)
            local tail = synced and "" or "\n(plugin sync failed: :Lazy restore after the restart)"
            vim.api.nvim_echo({ { ("%s updated to %s. Restart nvim to use it.\n%s%s"):format(
                M.name, s.label, log, tail) } }, true, {})
        end)
    end)()
end

function M.setup()
    if not FOLLOW[kazrc.get().updates.follow] then
        kazrc.problem("`updates.follow` should be \"release\", \"latest\" or \"off\"")
    end
    vim.api.nvim_create_user_command("KazUpdate", M.update, { desc = "Update neovimRC (and its plugins)" })
    vim.api.nvim_create_autocmd("VimEnter", {
        once = true,
        callback = function()
            -- not in headless runs (setupRC, the sync above)
            if #vim.api.nvim_list_uis() > 0 then vim.defer_fn(M.check, 1500) end
        end,
    })
end

return M
