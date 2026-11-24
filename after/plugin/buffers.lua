-- Closing buffers without closing windows: :bd takes the window with it and
-- breaks the splits, so every window showing the buffer first switches to
-- another one (the alternate buffer, else the previous listed, else an empty
-- one). Unsaved buffers are never closed.
-- Moving between buffers is built in: [b ]b, [B ]B, <C-^>; the list: <leader>pb.

local function listed(buf)
    return vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buflisted
end

-- what a window showing `buf` should show instead
local function replacement(win, buf)
    local alt = vim.api.nvim_win_call(win, function() return vim.fn.bufnr("#") end)
    if alt > 0 and alt ~= buf and listed(alt) then return alt end
    local best, best_used
    for _, info in ipairs(vim.fn.getbufinfo({ buflisted = 1 })) do
        if info.bufnr ~= buf and (not best_used or info.lastused > best_used) then
            best, best_used = info.bufnr, info.lastused
        end
    end
    return best
end

local function close(buf)
    if vim.bo[buf].modified then
        local why = vim.bo[buf].buftype == "terminal" and "still running" or "unsaved changes"
        vim.notify(vim.fn.bufname(buf) .. ": " .. why .. ", kept", vim.log.levels.WARN)
        return false
    end
    for _, win in ipairs(vim.fn.win_findbuf(buf)) do
        local other = replacement(win, buf)
        if other then
            vim.api.nvim_win_set_buf(win, other)
        else
            vim.api.nvim_win_call(win, function() vim.cmd.enew() end)
        end
    end
    if vim.api.nvim_buf_is_valid(buf) then
        -- terminals need force; a modified one was refused above
        vim.api.nvim_buf_delete(buf, { force = vim.bo[buf].buftype == "terminal" })
    end
    return true
end

vim.keymap.set("n", "<leader>k", function()
    close(vim.api.nvim_get_current_buf())
end, { desc = "Close buffer, keep the window" })

vim.keymap.set("n", "<leader>K", function()
    local current = vim.api.nvim_get_current_buf()
    local closed, kept = 0, 0
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if buf ~= current and listed(buf) then
            if vim.bo[buf].modified then
                kept = kept + 1
            elseif close(buf) then
                closed = closed + 1
            end
        end
    end
    vim.notify(("closed %d buffers%s"):format(closed, kept > 0 and (", kept " .. kept .. " unsaved") or ""))
end, { desc = "Close every other buffer (unsaved stay)" })
