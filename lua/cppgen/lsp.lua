local ast = require('cppgen.ast')
local log = require('cppgen.log')

---------------------------------------------------------------------------------------------------
--- LSP utilities
---------------------------------------------------------------------------------------------------

local M = {}

---------------------------------------------------------------------------------------------------
--- Get AST for the whole buffer and invoke callback on it.
---------------------------------------------------------------------------------------------------
function M.get_ast(client, callback, location)
	local params = { textDocument = vim.lsp.util.make_text_document_params() }
    if location then
        params.textDocument.uri = location.uri
    end
    if client then
        log.trace("Requesting AST for current buffer")
	    client.request("textDocument/ast", params, function(err, symbols, _)
            if err ~= nil then
                log.error(err)
            else
                log.info("Received AST data with", (symbols and symbols.children and #symbols.children or 0), "top level nodes")
                log.trace(symbols)
                callback(symbols)
		    end
	    end)
    end
end

--- Given a symbol tree, find a node whose definition starts at a given range
local function get_type_definition_node(symbols, range)
    log.trace("get_type_definition_node:", "symbols", symbols, "range", range)

    local node = nil
    ast.dfs(symbols,
        function(_)
            return not node
        end,
        function(n)
            if n.range and n.range['start'].line == range['start'].line then
                node = n
            end
        end
        )
    return node
end

--- Given a condition node location, request the AST for it
local function get_type_ast(client, location, callback)
    log.trace("get_type_ast:", location)

	local params = { textDocument = vim.lsp.util.make_text_document_params() }
    params.textDocument.uri = location.uri

    -- In case the definition is in different file
    local cb = vim.api.nvim_get_current_buf()
    vim.cmd.edit(location.uri)
    vim.api.nvim_set_current_buf(cb)

	client.request("textDocument/ast", params, function(err, symbols, _)
        if err ~= nil then
            log.error(err)
        else
            local node = get_type_definition_node(symbols, location.range)
            if node then
                callback(node)
	        end
	    end
	end)
end

--- Given a node, request the type information for it using supplied client and invoke the givan callback
function M.get_type_definition(client, node, callback)
    log.trace("get_type_definition:", ast.details(node))
    local params = vim.lsp.util.make_position_params();

    params.position.line      = node.range.start.line
    params.position.character = node.range.start.character
    log.trace("get_type_definition:", "params", params)

	client.request("textDocument/typeDefinition", params, function(err, symbols, _)
        if err ~= nil then
            log.error(err)
        else
            if next(symbols) ~= nil then
                get_type_ast(client, symbols[1], callback)
            end
	    end
	end)
end

return M
