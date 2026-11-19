-- XML indentation from the treesitter tree. Vim's indent/xml.vim counts tags
-- inside comments (<!-- <button> -->) as real ones, so closing tags after
-- such comments land at the wrong depth. Here a line is indented by the
-- elements around it: one shiftwidth per enclosing element, a closing tag at
-- its element's depth, comment bodies one level in from their <!--.
-- A half-typed tag (an ERROR in the tree) is stepped over; only when no
-- element can be found at all are the tags in the text above counted.
local M = {}

local function indent_of(row) -- row is 0-based
    return vim.fn.indent(row + 1)
end

-- For a tree too broken to read (a tag still being typed): count the tags
-- in the text above, comments / CDATA / <? ?> / <!DOCTYPE> left out.
local function scan_indent(lnum)
    local sw = vim.fn.shiftwidth()
    local lines = vim.api.nvim_buf_get_lines(0, 0, lnum - 1, false)
    local text = table.concat(lines, "\n")
        :gsub("<!%-%-.-%-%->", "")
        :gsub("<!%[CDATA%[.-%]%]>", "")
        :gsub("<%?.-%?>", "")
        :gsub("<![^>]*>", "")
    -- still inside an unclosed <!-- or an unfinished <tag ...: one level in
    -- from the line it starts on
    for _, pat in ipairs({ "()<!%-%-[^\n]*$", "()<!%-%-.*$", "()<[%w_:][^<>]*$" }) do
        local pos = text:match(pat)
        if pos then
            local _, nl = text:sub(1, pos):gsub("\n", "")
            local start_line = lines[nl + 1] or ""
            return #(start_line:match("^%s*")) + sw
        end
    end
    local depth = 0
    for close, selfclose in text:gmatch("<(/?)[%w_:][^>]-(/?)>") do
        if close == "/" then depth = depth - 1 elseif selfclose ~= "/" then depth = depth + 1 end
    end
    if vim.fn.getline(lnum):match("^%s*</") then depth = depth - 1 end
    return math.max(depth, 0) * sw
end

function M.get(lnum)
    local ok, parser = pcall(vim.treesitter.get_parser, 0, "xml")
    if not ok or not parser then return scan_indent(lnum) end
    local root = parser:parse()[1]:root()

    local row = lnum - 1
    local line = vim.fn.getline(lnum)
    local col = line:find("%S") or 1
    col = col - 1
    local sw = vim.fn.shiftwidth()

    local node = root:named_descendant_for_range(row, col, row, col)
    local closing = line:match("^%s*</") ~= nil

    while node do
        local t = node:type()
        local srow = node:start()
        if t == "Comment" and srow < row then
            return indent_of(srow) + (line:match("^%s*%-%->") and 0 or sw)
        end
        if t == "element" and srow < row then
            return indent_of(srow) + (closing and 0 or sw)
        end
        node = node:parent()
    end
    -- no element around: top level, or a tree too broken to tell
    return root:has_error() and scan_indent(lnum) or 0
end

return M
