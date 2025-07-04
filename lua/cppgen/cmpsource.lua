local log = require('cppgen.log')
local ast = require('cppgen.ast')
local lsp = require('cppgen.lsp')

local gen = require('cppgen.generator')

local cmp = require('cmp')

---------------------------------------------------------------------------------------------------
-- Context sensitive code completion source. When the user enters insert mode we capture current 
-- line number and send AST request. When the AST arrives we locate relevant nodes and try to 
-- generate code from them. For the code completion the only relevant nodes are the smallest 
-- enclosing node and the immediately preceding node, provided we can generate code from them.
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Local parameters. LSP client instance and current editor context.
---------------------------------------------------------------------------------------------------
local L = {
    lspclient  = nil,
    line       = nil,
    snippets   = {},
}

--- Exported functions
local M = {}

--- Scan current AST, find immediately preceding and smallest enclosing nodes that are relevant.
local function find_relevant_nodes(symbols, line)
    log.trace("find_relevant_nodes at line", line)
    local preceding, enclosing = nil, nil
    ast.dfs(symbols,
        function(node)
            log.trace("Looking at node", ast.details(node), "phantom=", ast.phantom(node), "encloses=", ast.encloses(node, line))
            return ast.encloses(node, line)
        end,
        function(node)
            if ast.encloses(node, line) and not ast.overlay(enclosing, node) then
                if gen.is_relevant(node) then
                    enclosing = node
                end
            end
        end,
        function(node)
            if ast.precedes(node, line) and not ast.overlay(preceding, node) then
                if gen.is_relevant(node) then
                    preceding = node
                end
            end
        end
    )
    log.trace("Found relavant nodes:", ast.details(preceding), ast.details(enclosing))
    return preceding, enclosing
end

--- Given preceding and closest enclosing nodes, invoke proper callback on them.
local function visit_relevant_nodes(symbols, line, callback)
    log.trace("Looking for relevant nodes at line", line)
    local preceding, enclosing = find_relevant_nodes(symbols, line)
    local scope = ast.is_class(enclosing) and ast.Class or ast.Other
    if preceding then
        log.debug("Selected preceding node", ast.details(preceding))
        local aliastype = ast.alias_type(preceding)
        if aliastype and L.lspclient then
            lsp.get_type_definition(L.lspclient, aliastype, function(node)
                log.debug("Resolved type alias:", ast.details(preceding), "using:", ast.details(node), " line:", line)
                callback(node, preceding, scope)
            end)
        else
            callback(preceding, nil, scope)
        end
    end
    if enclosing then
        log.debug("Selected enclosing node", ast.details(enclosing))
        callback(enclosing, nil, scope)
    end
end

---------------------------------------------------------------------------------------------------
--- Visit AST nodes
---------------------------------------------------------------------------------------------------
local function visit(symbols, line)
    log.trace("visit line:", line)
    visit_relevant_nodes(symbols, line,
        function(node, alias, scope)
            gen.generate(node, alias, scope, function(snippet)
                table.insert(L.snippets, snippet)
                log.info("Collected", #L.snippets, "snippet(s)")
            end)
        end
    )
end

---------------------------------------------------------------------------------------------------
--- Generate code completion items.
---------------------------------------------------------------------------------------------------
local function generate()
    local total = {}
    for _,s in ipairs(L.snippets) do
        table.insert(total,
            -- Completion snippet
            {
                label            = s.trigger,
                kind             = cmp.lsp.CompletionItemKind.Snippet,
                insertTextMode   = 2,
                insertTextFormat = cmp.lsp.InsertTextFormat.Snippet,
                insertText       = table.concat(s.lines, '\n'),
                documentation    = table.concat(s.lines, '\n'),
                lines            = s.lines,
            })
    end
    log.info("Collected", #total, "completion items")
    return total
end

---------------------------------------------------------------------------------------------------
-- Start of code completion source interface.
---------------------------------------------------------------------------------------------------

--- Return new source
function M.source()
    log.trace('source')
    return setmetatable({}, { __index = M })
end

---------------------------------------------------------------------------------------------------
--- Return whether this source is available in the current context or not (optional).
---------------------------------------------------------------------------------------------------
function M:is_available()
    log.trace('is_available')
    return next(L.snippets) ~= nil
end

---------------------------------------------------------------------------------------------------
--- Return the debug name of this source (optional).
---------------------------------------------------------------------------------------------------
--[[
function M:get_debug_name()
    log.trace('get_debug_name')
    return 'c++gen'
end
]]

---------------------------------------------------------------------------------------------------
--- Return LSP's PositionEncodingKind (optional).
---------------------------------------------------------------------------------------------------
--[[
function M:get_position_encoding_kind()
    log.trace('get_position_encoding_kind')
  return 'utf-16'
end
]]

---------------------------------------------------------------------------------------------------
--- Return the keyword pattern for triggering completion (optional).
---------------------------------------------------------------------------------------------------
--[[
function M:get_keyword_pattern()
    log.trace('get_keyword_pattern')
    return 'friend'
end
]]

---------------------------------------------------------------------------------------------------
--- Return trigger characters for triggering completion (optional).
---------------------------------------------------------------------------------------------------
--[[
function M:get_trigger_characters()
    log.trace('get_trigger_characters')
    return { '.' }
end
]]

---------------------------------------------------------------------------------------------------
--- Invoke completion (required).
---------------------------------------------------------------------------------------------------
function M:complete(params, callback)
    log.trace('complete:', params)
    local items = generate()
    if items then
        log.trace('complete:', items)
        callback(items)
    end
end

---------------------------------------------------------------------------------------------------
--- Resolve completion item (optional). This is called right before the completion is about to be displayed.
---------------------------------------------------------------------------------------------------
function M:resolve(completion_item, callback)
    log.trace('resolve:', completion_item)
    callback(completion_item)
end

---------------------------------------------------------------------------------------------------
--- Executed after the item was selected.
---------------------------------------------------------------------------------------------------
--[[
function M:execute(completion_item, callback)
    log.trace('execute')
    callback(completion_item)
end
]]

---------------------------------------------------------------------------------------------------
-- End of code completion source interface.
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
--- Initialization and lifecycle callbacks
---------------------------------------------------------------------------------------------------

--- Initialization callback
function M.setup(opts)
    log.trace("setup")
    gen.setup(opts)
end

--- LSP client attached callback
function M.attached(client, bufnr)
    log.trace("Attached client", client.id, "buffer", bufnr)
    L.lspclient = client
    gen.attached(client, bufnr)
end

--- Entering insert mode. Reset generators and request AST data. Upon completion visit AST nodes.
function M.insert_enter(bufnr)
    log.trace("Entered insert mode buffer:", bufnr)

    L.snippets = {}
    L.line     = vim.api.nvim_win_get_cursor(0)[1] - 1

    lsp.get_ast(L.lspclient, function(symbols)
        -- We may have left insert mode by the time AST arrives
        if L.line then
            visit(symbols, L.line)
		end
	end
    )
end

--- Exiting insert mode.
function M.insert_leave(bufnr)
    log.trace("Exited insert mode buffer:", bufnr)
    L.line = nil
end

--- Wrote buffer
function M.after_write(bufnr)
    log.trace("Wrote buffer:", bufnr)
end

--- Info callback
function M.info()
    return gen.info()
end

return M

