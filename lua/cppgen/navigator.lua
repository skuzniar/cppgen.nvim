local log = require('cppgen.log')
local val = require('cppgen.validator')

---------------------------------------------------------------------------------------------------
-- Generated code validator.
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Global parameters for code validation. Initialized in setup.
---------------------------------------------------------------------------------------------------
local G = {}

---------------------------------------------------------------------------------------------------
-- Local parameters
---------------------------------------------------------------------------------------------------
local L = {
    autogroup = vim.api.nvim_create_augroup('CppGenNavigator', {}),
}

--- Exported functions
local M = {}

-- setup auto_cmds
vim.api.nvim_create_autocmd({
    "CursorMoved",
    "CursorMovedI",
    "ModeChanged",
},
{
    group = L.autogroup,
    callback = function()
        M.preview()
    end
})

---------------------------------------------------------------------------------------------------
--- Initialization and lifecycle callbacks
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
--- Initialization callback. Capture relevant parts of the configuration.
---------------------------------------------------------------------------------------------------
function M.setup(opts)
    G.navigator = opts.navigator
end

--- LSP client attached callback
function M.attached(client, bufnr)
    log.info("Attached client", client.id, "buffer", bufnr)
end

--- Entering insert mode.
function M.insert_enter(bufnr)
    log.debug("Entered insert mode buffer:", bufnr)
end

--- Exiting insert mode.
function M.insert_leave(bufnr)
    log.debug("Exited insert mode buffer:", bufnr)
end

--- Wrote buffer
function M.after_write(bufnr)
    log.trace("Wrote buffer:", bufnr)
end

-- Calculate the longest length of lines of code
local function max_length(lines)
    local max_len = 0
    for _,l in ipairs(lines) do
            max_len = math.max(max_len, string.len(l))
    end
    return max_len
end

--- Diff preview window options, Record is a valid code/snippet entry.
local function options(record, bufnr)
    local opts = {
        relative  = 'cursor',
        style     = 'minimal',
        border    = 'rounded',
        noautocmd = true,
        title     = 'Current vs Generated',
        title_pos = 'center',
        width  = max_length(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)),
        height = vim.api.nvim_buf_line_count(bufnr),
        anchor = 'NW',
        row    = 0,
        col    = string.len(record.code[1])
    }
    return opts
end

--- Diff preview
function M.preview(srec)
    if L.win then
        vim.api.nvim_win_close(L.win, true)
        L.win = nil
    end
    if L.buf then
        vim.api.nvim_buf_delete(L.buf, {force = true})
        L.buf = nil
    end

    -- Show preview window if there is a difference
    if srec then
        if not val.same(srec) then
            L.buf = vim.api.nvim_create_buf(false, true)
            val.set_diffs(L.buf, srec)
            L.win = vim.api.nvim_open_win(L.buf, false, options(srec, L.buf))
        end
    end
end

--- Get the snippet record encloses the cursor
function M.get_enclosing(different)
    local srec = nil
    local line = vim.api.nvim_win_get_cursor(0)[1]
    for _,s in ipairs(val.results()) do
        if not different or not val.same(s) then
            if line >= s.span.first+1 and line <= s.span.last+1 then
                srec = s
                break
            elseif line < s.span.first+1 then
                break
            end
        end
    end
    return srec
end

--- Get the next snippet record relative to the cursor
function M.goto_next(different)
    local srec = nil
    local line = vim.api.nvim_win_get_cursor(0)[1]
    for _,s in ipairs(val.results()) do
        if not different or not val.same(s) then
            srec = s
            if s.span.first+1 > line then
                break
            end
        end
    end
    if srec then
        local row = srec.span.first + 1
        local _, col = vim.fn.getline(row):find('^%s*')
        vim.api.nvim_win_set_cursor(0, { row, col })
    end
end

--- Get the previous snippet record relative to the cursor
function M.goto_prev(different)
    local srec = nil
    local line = vim.api.nvim_win_get_cursor(0)[1]
    for _,s in ipairs(val.results()) do
        if not different or not val.same(s) then
            if s.span.first+1 >= line then
                break
            end
            srec = s
        end
    end
    if srec then
        local row = srec.span.first + 1
        local _, col = vim.fn.getline(row):find('^%s*')
        vim.api.nvim_win_set_cursor(0, { row, col })
    end
end

return M

