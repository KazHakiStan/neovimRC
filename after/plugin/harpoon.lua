-- harpoon2 with groups: up to 9 lists of files per project, one per task
-- (build files, the lobby and its layout, a manager and what it touches...),
-- each with a name if you like.
--   <leader>1..9  open group N's menu (and make it the active group)
--   <leader>a     add this file: pick the group with a digit
--   <leader>hl    name a group (pick it, type the name; empty = no name)
--   <leader>hh    all groups: a digit opens one
--   <C-e>         menu of the active group
--   <leader>hp / hn  previous / next file of the active group
--   <leader>hr    remove this file from the active group
--   in a menu: <CR> open, <C-v> vsplit, <C-x> split, <C-t> tab, dd / reorder
--   lines, saved on close. Files remember where the cursor was.
local ok, harpoon = pcall(require, "harpoon")
if not ok then return end

local GROUPS = 9

-- markdown opens rendered (md-render) in a buffer named "<file> [render]":
-- add the file itself, not that view
local default_item = require("harpoon.config").get_default_config().default.create_list_item
local function create_list_item(config, name)
    if not name then
        local source = vim.api.nvim_buf_get_name(0):match("^(.*) %[render%]$")
        if source then
            name = require("plenary.path"):new(source):make_relative(config.get_root_dir())
        end
    end
    return default_item(config, name)
end

harpoon:setup({
    settings = { save_on_toggle = true, sync_on_ui_close = true },
    default = { create_list_item = create_list_item },
})

-- the active group, for <C-e> / hp / hn / hr (this session; group 1 at start)
local active = 1
local function list(n) return harpoon:list(tostring(n or active)) end

-- group names, per project (harpoon keys its lists by the working directory)
local names_file = vim.fn.stdpath("data") .. "/harpoon-groups.json"
local function all_names()
    local ok_read, data = pcall(function() return vim.json.decode(table.concat(vim.fn.readfile(names_file), "\n")) end)
    return ok_read and type(data) == "table" and data or {}
end
local function names() return all_names()[vim.uv.cwd()] or {} end
local function set_name(n, name)
    local data = all_names()
    local project = data[vim.uv.cwd()] or {}
    project[tostring(n)] = name ~= "" and name or nil
    data[vim.uv.cwd()] = next(project) and project or nil
    pcall(vim.fn.writefile, { vim.json.encode(data) }, names_file)
end
local function label(n)
    local name = names()[tostring(n)]
    return name and (" %d · %s "):format(n, name) or (" %d "):format(n)
end

local function files(n)
    local out = {}
    local l = list(n)
    for i = 1, l:length() do
        local item = l:get(i)
        if item then out[#out + 1] = vim.fs.basename(item.value) end
    end
    return out
end

local function menu(n)
    active = n
    local hint = list(n):length() == 0 and " empty: <leader>a adds the file you're in " or ""
    harpoon.ui:toggle_quick_menu(list(n), { border = "rounded", title = " Harpoon" .. label(n) .. hint })
end

-- a small window listing the groups; a digit picks one, anything else cancels
local function pick_group(title, mark, on_pick)
    local nm = names()
    local lines = {}
    for n = 1, GROUPS do
        local fs = files(n)
        local name = nm[tostring(n)] or ""
        lines[n] = (" %d %s %-14s %s"):format(n, mark(n) and "✓" or " ", name,
            #fs > 0 and table.concat(fs, ", ") or "·")
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = " 1-9 pick · any other key cancels"
    local width = 20
    for _, l in ipairs(lines) do width = math.max(width, vim.fn.strdisplaywidth(l) + 1) end
    width = math.min(width, vim.o.columns - 4)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
    local win = vim.api.nvim_open_win(buf, false, {
        relative = "editor", style = "minimal", border = "rounded", title = title, title_pos = "center",
        width = width, height = #lines,
        row = math.floor((vim.o.lines - #lines) / 2) - 1, col = math.floor((vim.o.columns - width) / 2),
    })
    vim.api.nvim_buf_set_extmark(buf, vim.api.nvim_create_namespace("harpoon_groups"), #lines - 1, 0,
        { line_hl_group = "Comment" })
    vim.cmd.redraw()
    local ok_key, key = pcall(vim.fn.getcharstr)
    pcall(vim.api.nvim_win_close, win, true)
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
    local n = ok_key and tonumber(key)
    if n and n >= 1 and n <= GROUPS then on_pick(n) end
end

local map = vim.keymap.set

for n = 1, GROUPS do
    map("n", "<leader>" .. n, function() menu(n) end, { desc = "Harpoon: group " .. n })
end

local function current_value() return create_list_item(list().config).value end

map("n", "<leader>a", function()
    local value = current_value()
    pick_group(" Add " .. vim.fs.basename(value) .. " to group ", function(n)
        return list(n):get_by_value(value) ~= nil
    end, function(n)
        active = n
        list(n):add()
        vim.notify(("harpoon: %s →%s(%d files)"):format(vim.fs.basename(value), label(n), list(n):length()))
    end)
end, { desc = "Harpoon: add file to a group" })

map("n", "<leader>hl", function()
    pick_group(" Name which group? ", function() return false end, function(n)
        vim.ui.input({ prompt = ("Group %d name (empty = none): "):format(n), default = names()[tostring(n)] or "" },
            function(name)
                if name then set_name(n, vim.trim(name)) end
            end)
    end)
end, { desc = "Harpoon: name a group" })
map("n", "<leader>hr", function() list():remove() end, { desc = "Harpoon: remove file from the active group" })
map("n", "<C-e>", function() menu(active) end, { desc = "Harpoon: menu of the active group" })

-- from the file you're in (harpoon's own prev/next keep a counter of their
-- own), wrapping around
local function step(delta)
    local l = list()
    local count = l:length()
    if count == 0 then return end
    local _, idx = l:get_by_value(create_list_item(l.config).value)
    idx = idx or (delta > 0 and 0 or 1)
    l:select((idx - 1 + delta) % count + 1)
end
map("n", "<leader>hp", function() step(-1) end, { desc = "Harpoon: previous file in the group" })
map("n", "<leader>hn", function() step(1) end, { desc = "Harpoon: next file in the group" })

-- every group with its name and files; a digit opens its menu
map("n", "<leader>hh", function()
    pick_group(" Harpoon groups ", function(n) return n == active end, menu)
end, { desc = "Harpoon: all groups" })

-- open the entry under the cursor in a split / vsplit / new tab from the menu
harpoon:extend({
    UI_CREATE = function(cx)
        local function open(how)
            return function() harpoon.ui:select_menu_item({ [how] = true }) end
        end
        map("n", "<C-v>", open("vsplit"), { buffer = cx.bufnr })
        map("n", "<C-x>", open("split"), { buffer = cx.bufnr })
        map("n", "<C-t>", open("tabedit"), { buffer = cx.bufnr })
    end,
})
