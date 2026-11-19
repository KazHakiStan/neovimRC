-- Closing tags: typing <button> adds </button> after the cursor, and editing
-- an opening tag's name renames the closing one too (xml, html, jsx, vue…).
local ok, autotag = pcall(require, "nvim-ts-autotag")
if not ok then return end

autotag.setup({
    opts = {
        enable_close = true,
        enable_rename = true,
        enable_close_on_slash = false, -- typing </ doesn't fill in the rest
    },
})

-- ...but not inside <!-- -->: a commented-out <button> gets no </button>.
-- Text, not the tree: while a comment is being typed the tree is broken.
local function in_comment()
    local row, col = unpack(vim.api.nvim_win_get_cursor(0))
    local lines = vim.api.nvim_buf_get_lines(0, math.max(0, row - 200), row, false)
    lines[#lines] = lines[#lines]:sub(1, col)
    for i = #lines, 1, -1 do
        local open, close = 0, 0
        for p in lines[i]:gmatch("()<!%-%-") do open = p end
        for p in lines[i]:gmatch("()%-%->") do close = p end
        if open > 0 or close > 0 then return open > close end
    end
    return false
end

local internal = require("nvim-ts-autotag.internal")
local close_tag = internal.close_tag
internal.close_tag = function(...)
    if in_comment() then return end
    return close_tag(...)
end
