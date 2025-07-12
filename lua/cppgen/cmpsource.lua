local log = require('cppgen.log')
local ast = require('cppgen.ast')
local lsp = require('cppgen.lsp')

local gen = require('cppgen.generator')

local cmp = require('cmp')

---------------------------------------------------------------------------------------------------
-- Context sensitive code completion source. When the user enters insert mode we capture current
-- line number and send AST request. When the AST arrives we locate relevant nodes and try to
-- generate code from them. For the code completion there are two kinds of relevant nodes. The
-- first are the proximity nodes, one being the smallest enclosing node and the othet the
-- immediately preceding node. The second kind are all the preceding nodes. We use the proximity
-- nodes to build context sensitive code completion. The second kind is suitable for bulk code
-- generation.
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Global parameters for code generation. Initialized in setup.
---------------------------------------------------------------------------------------------------
local G = {}

---------------------------------------------------------------------------------------------------
-- Local parameters. LSP client instance and current editor context.
---------------------------------------------------------------------------------------------------
local L = {
    lspclient          = nil,
    line               = nil,
    proximity_snippets = {},
    preceding_snippets = {},
}

--- Exported functions
local M = {}

--- Scan current AST, find immediately preceding and smallest enclosing relevant nodes.
local function find_proximity_nodes(symbols, line)
    log.trace("find_proximity_nodes at line", line)
    local preceding, enclosing = nil, nil
    ast.dfs(symbols,
        function(node)
            log.trace("Looking at node", ast.details(node), "phantom=", ast.phantom(node), "encloses=",
                ast.encloses(node, line))
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
    log.debug("Found proximity node(s):", ast.details(preceding), ast.details(enclosing))
    return preceding, enclosing
end

--- Scan current AST, find immediately preceding and smallest enclosing relevant nodes.
local function find_preceding_nodes(symbols, line)
    log.trace("find_preceding_nodes at line", line)
    local nodes = {}
    ast.dfs(symbols,
        function(node)
            log.trace("Looking at node", ast.details(node), "phantom=", ast.phantom(node), "encloses=",
                ast.encloses(node, line))
            return true
        end,
        function(node)
            if gen.is_relevant(node) then
                table.insert(nodes, node)
            end
        end
    )
    log.debug("Found", #nodes, "preceding node(s)")
    return nodes
end

--- Locate immediately preceding and smallest enclosing nodes and invoke given callback on them.
local function visit_proximity_nodes(symbols, line, callback)
    log.trace("Looking for proximity nodes at line", line)
    local preceding, enclosing = find_proximity_nodes(symbols, line)
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

--- Locate immediately preceding and smallest enclosing nodes and invoke given callback on them.
local function visit_preceding_nodes(symbols, line, callback)
    log.trace("Looking for preceding nodes at line", line)
    for _, p in ipairs(find_preceding_nodes(symbols, line)) do
        log.debug("Selected preceding node", ast.details(p))
        local aliastype = ast.alias_type(p)
        if aliastype and L.lspclient then
            lsp.get_type_definition(L.lspclient, aliastype, function(node)
                log.debug("Resolved type alias:", ast.details(p), "using:", ast.details(node), " line:", line)
                callback(node, p, ast.Other)
            end)
        else
            callback(p, nil, ast.Other)
        end
    end
end

---------------------------------------------------------------------------------------------------
--- Visit AST nodes in two passes, looking for proximity and preceding nodes.
---------------------------------------------------------------------------------------------------
local function visit(symbols, line)
    log.trace("visit line:", line)
    visit_proximity_nodes(symbols, line,
        function(node, alias, scope)
            gen.generate(node, alias, scope, function(snippet)
                table.insert(L.proximity_snippets, snippet)
                log.debug("Collected", #L.proximity_snippets, "proximity snippet(s)")
            end)
        end
    )
    if G.batchmode.enabled then
        visit_preceding_nodes(symbols, line,
            function(node, alias, scope)
                gen.generate(node, alias, scope, function(snippet)
                    table.insert(L.preceding_snippets, snippet)
                    log.debug("Collected", #L.preceding_snippets, "preceding snippet(s)")
                end)
            end
        )
    end
end

---------------------------------------------------------------------------------------------------
--- Generate code completion items.
---------------------------------------------------------------------------------------------------
local function generate()
    local total = {}
    -- Completion snippets triggered by snippet name and optionally trigger
    for _, s in ipairs(L.proximity_snippets) do
        if s.name then
            table.insert(total,
                {
                    label            = s.name,
                    kind             = cmp.lsp.CompletionItemKind.Snippet,
                    insertTextMode   = 2,
                    insertTextFormat = cmp.lsp.InsertTextFormat.Snippet,
                    insertText       = table.concat(s.lines, '\n'),
                    documentation    = table.concat(s.lines, '\n'),
                    --lines            = s.lines,
                })
        end
        if s.trigger and s.trigger ~= s.name then
            table.insert(total,
                {
                    label            = s.trigger,
                    kind             = cmp.lsp.CompletionItemKind.Snippet,
                    insertTextMode   = 2,
                    insertTextFormat = cmp.lsp.InsertTextFormat.Snippet,
                    insertText       = table.concat(s.lines, '\n'),
                    documentation    = table.concat(s.lines, '\n'),
                })
        end
    end
    log.info("Collected", #total, "completion items using proximity snippets")

    -- Batch mode code generation
    if G.batchmode.enabled then
        -- Group all snippets by trigger
        local groups = {}
        for _, s in ipairs(L.preceding_snippets) do
            local key = s.trigger or s.name
            if G.batchmode.trigger then
                key = G.batchmode.trigger(key)
            end
            if groups[key] == nil then
                groups[key] = {}
            end
            table.insert(groups[key], table.concat(s.lines, '\n'))
        end

        for k, v in pairs(groups) do
            table.insert(total,
                -- Batch snippet
                {
                    label            = k,
                    kind             = cmp.lsp.CompletionItemKind.Snippet,
                    insertTextMode   = 2,
                    insertTextFormat = cmp.lsp.InsertTextFormat.Snippet,
                    insertText       = table.concat(v, '\n'),
                    documentation    = table.concat(v, '\n'),
                    --lines            = lines,
                })
        end
        log.info("Collected", #total, "completion items using proximity and preceding snippets")
    end

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
    return next(L.proximity_snippets) ~= nil or next(L.preceding_snippets) ~= nil
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
    G.batchmode = opts.batchmode

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

    L.proximity_snippets = {}
    L.preceding_snippets = {}
    L.line               = vim.api.nvim_win_get_cursor(0)[1] - 1

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
