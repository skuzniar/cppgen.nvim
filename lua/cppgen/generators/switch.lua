local ast = require('cppgen.ast')
local lsp = require('cppgen.lsp')
local log = require('cppgen.log')
local utl = require('cppgen.generators.util')

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
local lspclient          = nil
local condition_ref_node = nil
local condition_def_node = nil

-- Apply parameters to the format string 
local function apply(format)
    format = string.gsub(format, "<default>",   P.default   or '')
    return utl.apply(P, format)
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

    P.default = G.switch.enum.default(ast.name(node), ast.name(condition_ref_node))
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
    condition_ref_node  = nil
    condition_def_node = nil
end

---------------------------------------------------------------------------------------------------
--- Generator will call this method with a node, optional type alias and a node location
---------------------------------------------------------------------------------------------------
function M.visit(node, alias, location)
    -- We can attempt to generate the switch statement if we are inside of a switch node
    if location == ast.Encloses and is_switch(node) then
        local cond = get_switch_condition_node(node)
        if cond then
            log.debug("visit:", "condition node", ast.details(cond))
            condition_ref_node = cond
            lsp.get_type_definition(lspclient, cond, function(n)
                log.debug("visit:", "def node", ast.details(n))
                condition_def_node = n
            end)
        end
    end
end

---------------------------------------------------------------------------------------------------
--- Generator will call this method to check if the module can generate code
---------------------------------------------------------------------------------------------------
function M.available()
    return condition_def_node ~= nil
end

---------------------------------------------------------------------------------------------------
-- Generate from string functions for an enum nodes.
---------------------------------------------------------------------------------------------------
function M.generate(strict)
    log.trace("generate:", ast.details(condition_def_node))

    local items = {}

    if ast.is_enum(condition_def_node) then
        table.insert(items, case_enum_item(condition_def_node))
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
    G.switch = opts.switch
end

return M
