-- The Xcode tab: build output, debugger panels and the code the debugger
-- stops in live here, so the tab you edit in stays as it was.

local T = {}

local tab, code_win

local function valid_tab()
    return tab and vim.api.nvim_tabpage_is_valid(tab)
end

local function is_code(w)
    local b = vim.api.nvim_win_get_buf(w)
    return vim.api.nvim_win_get_config(w).relative == ""
        and (vim.bo[b].buftype == "" or vim.b[b].dap_source_buf)
end

-- switch to the Xcode tab, creating it (with the current file) on first use
function T.enter()
    if not valid_tab() then
        local buf = vim.api.nvim_get_current_buf()
        if vim.bo[buf].buftype == "" and vim.api.nvim_buf_get_name(buf) ~= "" then
            vim.cmd("tab sbuffer " .. buf)
        else
            vim.cmd("tabnew")
        end
        tab = vim.api.nvim_get_current_tabpage()
        code_win = vim.api.nvim_get_current_win()
        vim.t[tab].xcode = true
    end
    vim.api.nvim_set_current_tabpage(tab)
    return tab
end

function T.is_current()
    return valid_tab() and vim.api.nvim_get_current_tabpage() == tab
end

-- the editor window of the Xcode tab
function T.code_win()
    T.enter()
    if code_win and vim.api.nvim_win_is_valid(code_win)
        and vim.api.nvim_win_get_tabpage(code_win) == tab and is_code(code_win) then
        return code_win
    end
    for _, w in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
        if is_code(w) then
            code_win = w
            return w
        end
    end
    -- only panels left: give the code a window above them
    vim.api.nvim_set_current_win(vim.api.nvim_tabpage_list_wins(tab)[1])
    vim.cmd("topleft new")
    code_win = vim.api.nvim_get_current_win()
    return code_win
end

-- nvim-dap `switchbuf`: whatever frame it jumps to opens in the Xcode tab's
-- code window, never in your editing tab or a stray split
function T.show(bufnr, line, column)
    local w = T.code_win()
    vim.api.nvim_win_set_buf(w, bufnr)
    local last = vim.api.nvim_buf_line_count(bufnr)
    pcall(vim.api.nvim_win_set_cursor, w, { math.min(math.max(line, 1), last), math.max((column or 1) - 1, 0) })
    vim.api.nvim_set_current_win(w)
    vim.cmd("normal! zz")
end

return T
