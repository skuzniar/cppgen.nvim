local ast = require('cppgen.ast')
local log = require('cppgen.log')

---------------------------------------------------------------------------------------------------
-- Switch statement generator.
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Global parameters for code generation. Initialized in setup.
---------------------------------------------------------------------------------------------------
local G = {}

---------------------------------------------------------------------------------------------------
-- Local parameters for code generation.
---------------------------------------------------------------------------------------------------
local P = {}

-- Capture parameters
local lspclient                 = nil
local condition_reference_node  = nil
local condition_definition_node = nil

-- Apply parameters to the format string 
local function apply(format)
    local result  = format

    result = string.gsub(result, "<label>",     P.label     or '')
    result = string.gsub(result, "<labelpad>",  P.labelpad  or '')
    result = string.gsub(result, "<value>",     P.value     or '')
    result = string.gsub(result, "<valuepad>",  P.valuepad  or '')
    result = string.gsub(result, "<specifier>", P.specifier or '')
    result = string.gsub(result, "<classname>", P.classname or '')
    result = string.gsub(result, "<fieldname>", P.fieldname or '')
    result = string.gsub(result, "<indent>",    P.indent    or '')
    result = string.gsub(result, "<default>",   P.default   or '')

    return result;
end

-- Collect names and values for an enum type node.
local function enum_labels_and_values(node)
    local records = {}
    ast.visit_children(node,
        function(n)
            if n.kind == "EnumConstant" then
                local record = {}
                record.label = ast.name(node) .. '::' .. ast.name(n)
                record.value = G.switch.enum.placeholder(ast.name(node), ast.name(n))
                table.insert(records, record)
            end
            return true
        end
    )
    return records
end

-- Calculate the longest length of labels and values
local function max_lengths(records)
    local max_lab_len = 0
    local max_val_len = 0
    for _,r in ipairs(records) do
        max_lab_len = math.max(max_lab_len, string.len(r.label))
        max_val_len = math.max(max_val_len, string.len(r.value))
    end
    return max_lab_len, max_val_len
end

---------------------------------------------------------------------------------------------------
-- Generate mock case statements for an enum type node.
---------------------------------------------------------------------------------------------------
local function case_enum_snippet(node)
    log.trace("case_enum_snippet:", ast.details(node))

    P.classname = ast.name(node)
    P.indent    = string.rep(' ', vim.lsp.util.get_effective_tabstop())

    local records = enum_labels_and_values(node)
    local maxllen, maxvlen = max_lengths(records)

    local lines = {}

    for _,r in ipairs(records) do
        P.label     = r.label
        P.value     = r.value
        P.labelpad  = string.rep(' ', maxllen - string.len(P.label))
        P.valuepad  = string.rep(' ', maxvlen - string.len(P.value))

        table.insert(lines, apply('case <label>:'))
        table.insert(lines, apply('<indent><value>;'))
        table.insert(lines, apply('<indent>break;'))
    end

    P.default = G.switch.enum.default(ast.name(node), ast.name(condition_reference_node))
    if P.default then
        table.insert(lines, apply('default:'))
        table.insert(lines, apply('<indent><default>;'))
        table.insert(lines, apply('<indent>break;'))
    end

    for _,l in ipairs(lines) do log.debug(l) end
    return lines
end

-- Generate mock case statements completion item for an enum type node.
local function case_enum_item(node)
    log.trace("case_enum_item:", ast.details(node))
    return { trigger = 'case', lines = case_enum_snippet(node) }
end

local function is_switch(node)
    return node and node.role == "statement" and node.kind == "Switch"
end

--- Given a switch statement node, find the embeded condition node
local function get_switch_condition_node(node)
    log.trace("get_switch_condition_node:", "for", ast.details(node))

    local cond = nil
    ast.dfs(node,
        function(_)
            return not cond
        end,
        function(n)
            if n.role == "expression" and n.kind == "DeclRef" then
                cond = n
            end
        end
        )
    return cond
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
    log.trace("get_type_definition_node:", node)
    return node
end

--- Given a condition node location, request the AST for it
local function get_switch_condition_type_ast(location)
    log.trace("get_switch_condition_type_ast:", location)

	local params = { textDocument = vim.lsp.util.make_text_document_params() }
    params.textDocument.uri = location.uri

    -- In case the definition is in different file
    local cb = vim.api.nvim_get_current_buf()
    vim.cmd.edit(location.uri)
    vim.api.nvim_set_current_buf(cb)

    if lspclient then
	    lspclient.request("textDocument/ast", params, function(err, symbols, _)
            if err ~= nil then
                log.error(err)
            else
                condition_definition_node = get_type_definition_node(symbols, location.range)
		    end
	    end)
    end
end

--- Given a condition node, request the type for it
local function get_switch_condition_type_definition(node)
    log.trace("get_switch_condition_type_definition:", ast.details(node))

    local params = vim.lsp.util.make_position_params();

    params.position.line      = node.range.start.line
    params.position.character = node.range.start.character
    log.trace("get_switch_condition_type_definition:", "params", params)

    if lspclient then
	    lspclient.request("textDocument/typeDefinition", params, function(err, symbols, _)
            if err ~= nil then
                log.error(err)
            else
                get_switch_condition_type_ast(symbols[1])
		    end
	    end)
    end
end

local M = {}

---------------------------------------------------------------------------------------------------
--- We need to capture a reference to the LSP client so we implement this callback
---------------------------------------------------------------------------------------------------
function M.attached(client, bufnr)
    log.trace("Attached client", client.id, "buffer", bufnr)
    lspclient = client
end

---------------------------------------------------------------------------------------------------
--- Generator will call this method to get kind of nodes that are of interest to each generator.
---------------------------------------------------------------------------------------------------
function M.digs()
    log.trace("digs:")
    return { "Switch" }
end

---------------------------------------------------------------------------------------------------
--- Generator will call this method before presenting a set of new candidate nodes
---------------------------------------------------------------------------------------------------
function M.reset()
    condition_reference_node  = nil
    condition_definition_node = nil
end

---------------------------------------------------------------------------------------------------
--- Generator will call this method with a node, optional type alias and a node location
---------------------------------------------------------------------------------------------------
function M.visit(node, alias, location)
    -- We can attempt to generate the switch statement if we are inside of a switch node
    if location == ast.Encloses and is_switch(node) then
        local cond = get_switch_condition_node(node)
        if cond then
            log.trace("visit:", "condition node", ast.details(cond))
            condition_reference_node = cond
            get_switch_condition_type_definition(cond)
        end
    end
end

---------------------------------------------------------------------------------------------------
--- Generator will call this method to check if the module can generate code
---------------------------------------------------------------------------------------------------
function M.available()
    return condition_definition_node ~= nil
end

---------------------------------------------------------------------------------------------------
-- Generate from string functions for an enum nodes.
---------------------------------------------------------------------------------------------------
function M.generate(strict)
    log.trace("generate:", ast.details(condition_definition_node))

    local items = {}

    if ast.is_enum(condition_definition_node) then
        table.insert(items, case_enum_item(condition_definition_node))
    end

    return items
end

---------------------------------------------------------------------------------------------------
--- Info callback
---------------------------------------------------------------------------------------------------
function M.info()
    return {
        { G.switch.enum.trigger, "Case switch statements" }
    }
end

---------------------------------------------------------------------------------------------------
--- Initialization callback
---------------------------------------------------------------------------------------------------
function M.setup(opts)
    G.switch     = opts.switch
end

return M
