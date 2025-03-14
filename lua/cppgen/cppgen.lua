local log = require('cppgen.log')
local gen = require('cppgen.generator')
local val = require('cppgen.validator')
local nav = require('cppgen.navigator')

---------------------------------------------------------------------------------------------------
-- Code generation module. Forwards events to the code completion module
---------------------------------------------------------------------------------------------------
local M = {}

---------------------------------------------------------------------------------------------------
--- Initialization callback
---------------------------------------------------------------------------------------------------
function M.setup(opts)
    gen.setup(opts)
    val.setup(opts)
    nav.setup(opts)
end

---------------------------------------------------------------------------------------------------
--- Callback invoked when the LSP client has been attache to the buffer
---------------------------------------------------------------------------------------------------
function M.attached(client, bufnr)
    log.trace("Attached client", client.id, "buffer", bufnr)
	gen.attached(client, bufnr)
	val.attached(client, bufnr)
	nav.attached(client, bufnr)
end

---------------------------------------------------------------------------------------------------
--- Callback invoked when we enter insert mode in the buffer
---------------------------------------------------------------------------------------------------
function M.insert_enter(bufnr)
    log.trace("Entered insert mode buffer:", bufnr)
	gen.insert_enter(bufnr)
	val.insert_enter(bufnr)
	nav.insert_enter(bufnr)
end

---------------------------------------------------------------------------------------------------
--- Callback invoked when we leave insert mode in the buffer
---------------------------------------------------------------------------------------------------
function M.insert_leave(bufnr)
    log.trace("Exited insert mode buffer:", bufnr)
	gen.insert_leave(bufnr)
	val.insert_leave(bufnr)
	nav.insert_leave(bufnr)
end

---------------------------------------------------------------------------------------------------
--- Callback invoked when we wrote the buffer
---------------------------------------------------------------------------------------------------
function M.after_write(bufnr)
    log.trace("Wrote buffer:", bufnr)
	gen.after_write(bufnr)
	val.after_write(bufnr)
	nav.after_write(bufnr)
end

---------------------------------------------------------------------------------------------------
--- Code generator is a source for the completion engine
---------------------------------------------------------------------------------------------------
function M.source()
    log.trace("source")
    return gen.source()
end

-- Calculate the longest length of the first two element in the records
local function max_lengths(records)
    local max_1st_len = 0
    local max_2nd_len = 0

    for _,r in ipairs(records) do
        max_1st_len = math.max(max_1st_len, r[1] and string.len(r[1]) or 0)
        max_2nd_len = math.max(max_2nd_len, r[2] and string.len(r[2]) or 0)
    end
    return max_1st_len, max_2nd_len
end

local function pad(s, len)
    return s .. string.rep(' ', len - string.len(s))
end

local function show_help()
    local info = gen.info()

    if #info > 0 then
        local header = { 'Completion trigger', 'Generated code snippet'}
        local maxlen, _ = max_lengths(info)
        maxlen = math.max(maxlen, string.len(header[1]))

        local lines = { { (' %s   %s\n'):format(pad(header[1], maxlen), header[2]), 'Special' } }

        local prev  = nil
        for _, record in ipairs(info) do
            if (prev == nil) or (prev ~= record[1]) then
                table.insert(lines, { (' %s - %s\n'):format(pad(record[1], maxlen), record[2]), 'Normal' })
            else
                table.insert(lines, { (' %s   %s\n'):format(pad('',        maxlen), record[2]), 'Normal' })
            end
            prev = record[1]
        end
        vim.api.nvim_echo(lines, false, {})
    end
end

-- Show generated snippets
local function show_snippets()
    val.show_snippets()
end

-- Preview current snippet, only when different
local function preview()
    nav.preview(nav.get_enclosing(true))
end

-- Go the the next snippet
local function next_snippet()
    nav.goto_next(false)
end

-- Go the the next different snippet
local function next_different_snippet()
    nav.goto_next(true)
end

-- Go the the previous snippet
local function prev_snippet()
    nav.goto_prev(false)
end

-- Go the the previous different snippet
local function prev_different_snippet()
    nav.goto_prev(true)
end

---------------------------------------------------------------------------------------------------
-- User commands dispatch table
---------------------------------------------------------------------------------------------------
local calls =
{
    help = show_help,
    show = show_snippets,
    next = next_snippet,
    Next = next_different_snippet,
    prev = prev_snippet,
    Prev = prev_different_snippet,
    view = preview,
}

local function get_keys(t)
  local keys={}
  for key,_ in pairs(t) do
    table.insert(keys, key)
  end
  return keys
end

vim.api.nvim_create_user_command('CppGen',
    function(opts)
        local f = calls[opts.fargs[1] or 'help']
        if f then
            f()
        end
    end,
    {
        nargs = 1,
        complete = function(ArgLead, CmdLine, CursorPos)
            return get_keys(calls)
        end,
        desc = 'CppGen commands.'
    }
)

return M
