-- Projects: the root of every file you open is remembered, nvim's working
-- directory follows it, and <leader>pp switches between recent ones.
--
-- A root is the OUTERMOST git repo above the file, so third-party/ submodules
-- (each with its own .git) belong to the game they live in. Outside git:
-- the nearest folder with one of projects.markers (Makefile, *.sln, ...).

local M = {}

-- auto_cd and the markers: `projects` in the settings (~/.config/kazrc/nvim.lua)
local function settings() return require("kazhakistan.kazrc").get().projects end
local MAX = 100

-- "Makefile" matches by name, "*.sln" as a glob
local function is_marker(name)
    for _, m in ipairs(settings().markers) do
        if m == name or (m:find("[*?]") and vim.glob.to_lpeg(m):match(name)) then return true end
    end
    return false
end

local history_file = vim.fn.stdpath("data") .. "/projects.json"
local history -- { path, ... } most recent first

local home = vim.fs.normalize(vim.uv.os_homedir())

function M.root(path)
    if not path or path == "" then return end
    path = vim.fs.normalize(path)
    local dir = vim.fn.isdirectory(path) == 1 and path or vim.fs.dirname(path)
    local git
    for d in vim.fs.parents(dir .. "/x") do
        if d == home or d == "/" then break end
        if vim.uv.fs_stat(d .. "/.git") then git = d end
    end
    if git then return git end
    return vim.fs.root(dir, is_marker)
end

local function save()
    pcall(vim.fn.writefile, { vim.json.encode(history) }, history_file)
end

-- project.nvim's history, mapped onto real roots, on the first run
local function import_old()
    local old = vim.fn.stdpath("data") .. "/project_nvim/project_history"
    if vim.fn.filereadable(old) == 0 then return {} end
    local list, seen = {}, {}
    for _, p in ipairs(vim.fn.readfile(old)) do
        local r = vim.fn.isdirectory(p) == 1 and M.root(p)
        if r and not seen[r] then
            seen[r] = true
            list[#list + 1] = r
        end
    end
    return list
end

local function load()
    if history then return history end
    local ok, data = pcall(function() return vim.json.decode(table.concat(vim.fn.readfile(history_file), "\n")) end)
    history = ok and type(data) == "table" and data or nil
    if not history then
        history = import_old()
        save()
    end
    return history
end

function M.remember(root)
    load()
    for i, p in ipairs(history) do
        if p == root then
            if i == 1 then return end
            table.remove(history, i)
            break
        end
    end
    table.insert(history, 1, root)
    while #history > MAX do table.remove(history) end
    save()
end

function M.forget(root)
    load()
    history = vim.tbl_filter(function(p) return p ~= root end, history)
    save()
end

function M.list()
    return vim.tbl_filter(function(p) return vim.fn.isdirectory(p) == 1 end, load())
end

local function cd(root)
    if vim.fn.getcwd(-1, -1) ~= root then vim.cmd.cd(vim.fn.fnameescape(root)) end
end

-- Telescope picker: <CR> cd + find files, <C-d> forget the project
function M.pick()
    local ok = pcall(require, "telescope")
    if not ok then
        return vim.ui.select(M.list(), { prompt = "Project" }, function(p)
            if p then cd(p) end
        end)
    end
    local pickers, finders = require("telescope.pickers"), require("telescope.finders")
    local actions, state = require("telescope.actions"), require("telescope.actions.state")
    local conf = require("telescope.config").values
    local function finder()
        return finders.new_table({
            results = M.list(),
            entry_maker = function(p)
                local name = vim.fs.basename(p)
                local where = vim.fn.fnamemodify(p, ":~")
                return {
                    value = p,
                    ordinal = name .. " " .. where,
                    display = ("%-24s %s"):format(name, where),
                }
            end,
        })
    end
    pickers.new(require("telescope.themes").get_dropdown({ previewer = false }), {
        prompt_title = "Projects   <CR> open · <C-d> forget",
        finder = finder(),
        sorter = conf.generic_sorter({}),
        attach_mappings = function(buf, map)
            actions.select_default:replace(function()
                local e = state.get_selected_entry()
                actions.close(buf)
                if not e then return end
                cd(e.value)
                M.remember(e.value)
                require("telescope.builtin").find_files({ cwd = e.value })
            end)
            map({ "i", "n" }, "<C-d>", function()
                local e = state.get_selected_entry()
                if not e then return end
                M.forget(e.value)
                state.get_current_picker(buf):refresh(finder(), { reset_prompt = false })
            end)
            return true
        end,
    }):find()
end

function M.setup()
    vim.api.nvim_create_autocmd("BufEnter", {
        group = vim.api.nvim_create_augroup("KazProjects", { clear = true }),
        callback = function(ev)
            if vim.bo[ev.buf].buftype ~= "" then return end
            local name = vim.api.nvim_buf_get_name(ev.buf)
            if name == "" or name:match("^%w+://") then return end
            local root = M.root(name)
            if not root then return end
            M.remember(root)
            if settings().auto_cd then cd(root) end
        end,
    })
    vim.api.nvim_create_user_command("Projects", M.pick, { desc = "Switch project" })
end

return M
