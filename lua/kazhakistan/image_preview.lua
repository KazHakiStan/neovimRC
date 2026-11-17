-- Telescope images: iTerm2/OSC on Windows ConPTY, Kitty graphics on macOS.
-- Requires Neovim 0.12+ and ImageMagick; no shell or POSIX TTY dependency.
local M = {}
local active
local image_id = 7100000
local extensions = { png=true, jpg=true, jpeg=true, gif=true, webp=true,
    bmp=true, tif=true, tiff=true, avif=true, heic=true, ico=true }

function M.is_image(path)
    return extensions[(path:match("%.([^./\\]+)$") or ""):lower()] == true
end

local function send(data)
    vim.api.nvim_ui_send(data)
end

function M.clear()
    if active then
        if active.job then active.job:kill(15) end
        if active.osc and active.position then
            local p = active.position
            local lines = {}
            for row = 0, active.rows - 1 do
                lines[#lines + 1] = ("\27[%d;%dH\27[%dX"):format(p.row + row, p.col, active.cols)
            end
            send("\27[s" .. table.concat(lines) .. "\27[u")
        end
        if active.id and not active.osc then send(("\27_Ga=d,d=I,i=%d,q=2\27\\"):format(active.id)) end
        active = nil
    end
end

local function valid(state)
    return active == state and vim.api.nvim_win_is_valid(state.win)
        and vim.api.nvim_win_get_buf(state.win) == state.buf
end

local function message(state, text)
    if not valid(state) then return end
    vim.bo[state.buf].modifiable = true
    vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, vim.split(text, "\n", { plain = true }))
    vim.bo[state.buf].modifiable = false
end

function M.draw()
    local state = active
    if not state or not state.id or not valid(state) then return end
    local max_cols = math.max(1, vim.api.nvim_win_get_width(state.win) - 2)
    local max_rows = math.max(1, vim.api.nvim_win_get_height(state.win) - 1)
    state.cols = math.min(max_cols, math.max(1, math.floor(max_rows * state.ratio * state.width / state.height)))
    state.rows = math.min(max_rows, math.max(1, math.floor(state.cols * state.height / state.width / state.ratio)))
    if not state.osc then send(("\27_Ga=d,d=i,i=%d,q=2\27\\"):format(state.id)) end
    local pos = vim.fn.screenpos(state.win, 1, 1)
    if pos.row == 0 then return end
    if state.osc then
        -- OSC 1337 survives ConPTY, unlike Kitty's APC commands on Windows.
        -- Avoid retransmitting the PNG for every prompt cursor movement.
        local key = ("%d:%d:%d:%d"):format(pos.row, pos.col, state.cols, state.rows)
        if state.drawn == key then return end
        state.drawn, state.position = key, pos
        send(("\27[s\27[%d;%dH\27]1337;File=inline=1;size=%d;width=%d;height=%d;preserveAspectRatio=1;doNotMoveCursor=1:%s\7\27[u")
            :format(pos.row, pos.col, state.bytes, state.cols, state.rows, state.encoded))
        return
    end
    send(("\27[s\27[%d;%dH\27_Ga=p,i=%d,c=%d,r=%d,C=1,q=2\27\\\27[u")
        :format(pos.row, pos.col, state.id, state.cols, state.rows))
end

function M.show(path, buf, win)
    M.clear()
    local state = { buf = buf, win = win }
    active = state
    if not vim.api.nvim_ui_send then
        message(state, "Image preview requires Neovim 0.12+")
        return
    end
    if vim.env.TERM_PROGRAM ~= "WezTerm" and not vim.env.WEZTERM_EXECUTABLE
        and not vim.env.KITTY_WINDOW_ID and vim.env.TERM_PROGRAM ~= "ghostty" then
        message(state, "Image preview: open Neovim in WezTerm")
        return
    end
    local magick = vim.fn.exepath("magick")
    local env
    if magick == "" and vim.fn.has("win32") == 1 then
        local scoop = vim.fn.expand("~/scoop/apps/imagemagick/current/magick.exe")
        if vim.fn.executable(scoop) == 1 then
            magick = scoop
            local home = vim.fn.fnamemodify(scoop, ":h")
            env = {
                PATH = home .. ";" .. vim.env.PATH,
                MAGICK_HOME = home,
                MAGICK_CONFIGURE_PATH = home,
                MAGICK_CODER_MODULE_PATH = home .. "/modules/coders",
            }
        end
    end
    if magick == "" then
        message(state, "Install ImageMagick: scoop install imagemagick / brew install imagemagick")
        return
    end
    message(state, "Loading image...")
    -- Convert only the first frame, resize before transmission, and strip metadata.
    state.job = vim.system({
        magick, path .. "[0]", "-auto-orient", "-thumbnail", "1200x900>",
        "-strip", "png:-",
    }, { timeout = 10000, env = env }, vim.schedule_wrap(function(result)
        state.job = nil
        if not valid(state) then return end
        local png = result.stdout or ""
        if result.code ~= 0 or #png < 24 or png:sub(1, 8) ~= "\137PNG\13\10\26\10" then
            message(state, "Image preview failed: " .. vim.trim(result.stderr or "invalid PNG"))
            return
        end
        local function uint32(offset)
            local a, b, c, d = png:byte(offset, offset + 3)
            return ((a * 256 + b) * 256 + c) * 256 + d
        end
        local width, height = uint32(17), uint32(21)
        local max_cols = math.max(1, vim.api.nvim_win_get_width(win) - 2)
        local max_rows = math.max(1, vim.api.nvim_win_get_height(win) - 1)
        -- Cells are approximately twice as tall as wide. Exact cell sizes,
        -- when available, preserve the aspect ratio with custom fonts too.
        local cell_ratio = 2
        local ok, image = pcall(require, "md-render.image")
        if ok then
            local cell = image.get_cell_size()
            if cell then cell_ratio = cell.cell_h / cell.cell_w end
        end
        state.width, state.height, state.ratio = width, height, cell_ratio
        state.cols = math.min(max_cols, math.max(1, math.floor(max_rows * cell_ratio * width / height)))
        state.rows = math.min(max_rows, math.max(1, math.floor(state.cols * height / width / cell_ratio)))
        vim.bo[buf].modifiable = true
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.fn["repeat"]({ "" }, max_rows))
        vim.bo[buf].modifiable = false
        vim.wo[win].number = false
        vim.wo[win].relativenumber = false
        vim.wo[win].signcolumn = "no"
        vim.wo[win].wrap = false
        image_id = image_id + 1
        state.id = image_id
        -- Direct chunked data works across Windows paths and remote terminals.
        local encoded = vim.base64.encode(png)
        if vim.fn.has("win32") == 1 then
            state.osc, state.encoded, state.bytes = true, encoded, #png
            vim.defer_fn(M.draw, 80)
            return
        end
        for offset = 1, #encoded, 4096 do
            local more = offset + 4096 <= #encoded and 1 or 0
            local header = offset == 1
                and ("a=t,f=100,t=d,i=%d,q=2,m=%d"):format(state.id, more)
                or ("m=%d"):format(more)
            send("\27_G" .. header .. ";" .. encoded:sub(offset, offset + 4095) .. "\27\\")
        end
        vim.defer_fn(M.draw, 40)
    end))
end

function M.setup()
    local group = vim.api.nvim_create_augroup("TelescopeImagePreview", { clear = true })
    vim.api.nvim_create_autocmd("WinClosed", {
        group = group,
        callback = function(event)
            if active and active.win == tonumber(event.match) then M.clear() end
        end,
    })
    vim.api.nvim_create_autocmd({ "BufWipeout", "BufWinLeave" }, {
        group = group,
        callback = function(event)
            if active and active.buf == event.buf then M.clear() end
        end,
    })
    vim.api.nvim_create_autocmd({ "WinResized", "VimResized", "CursorMovedI" }, {
        group = group,
        callback = function() if active then vim.defer_fn(M.draw, 40) end end,
    })
    vim.api.nvim_create_autocmd("VimLeavePre", { group = group, callback = M.clear })
end

return M
