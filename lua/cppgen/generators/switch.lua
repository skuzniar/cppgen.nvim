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
-- Private parameters for code generation.
---------------------------------------------------------------------------------------------------
local P = {}

-- Capture parameters
local L = {
    lspclient = nil
}

-- Apply parameters to the format string
local function apply(format)
    format = string.gsub(format, "<default>", P.default or '')
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
                record.value = G.enum.switch.placeholder(ast.name(node), ast.name(n))
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
    for _, r in ipairs(records) do
        max_lab_len = math.max(max_lab_len, string.len(r.label))
        max_val_len = math.max(max_val_len, string.len(r.value))
    end
    return max_lab_len, max_val_len
end

---------------------------------------------------------------------------------------------------
-- Generate mock case statements for an enum type node.
---------------------------------------------------------------------------------------------------
local function case_enum_snippet(defnode, refnode)
    log.trace("case_enum_snippet:", ast.details(defnode))

    P.classname            = ast.name(defnode)
    P.indent               = string.rep(' ', vim.lsp.util.get_effective_tabstop())

    local records          = enum_labels_and_values(defnode)
    local maxllen, maxvlen = max_lengths(records)

    local lines            = {}

    for _, r in ipairs(records) do
        P.label    = r.label
        P.value    = r.value
        P.labelpad = string.rep(' ', maxllen - string.len(P.label))
        P.valuepad = string.rep(' ', maxvlen - string.len(P.value))

        table.insert(lines, apply('case <label>:'))
        table.insert(lines, apply('<indent><value>;'))
        table.insert(lines, apply('<indent>break;'))
    end

    P.default = G.enum.switch.default(ast.name(defnode), ast.name(refnode))
    if P.default then
        table.insert(lines, apply('default:'))
        table.insert(lines, apply('<indent><default>;'))
        table.insert(lines, apply('<indent>break;'))
    end

    for _, l in ipairs(lines) do log.debug(l) end
    return lines
end

-- Generate mock case statements completion item for an enum type node.
local function case_enum_item(defnode, refnode)
    log.trace("case_enum_item:", ast.details(node))
    return
    {
        { trigger = G.enum.switch.trigger, lines = case_enum_snippet(defnode, refnode) }
    }
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

---------------------------------------------------------------------------------------------------
--- Public interface.
---------------------------------------------------------------------------------------------------
local M = {}

---------------------------------------------------------------------------------------------------
--- We need to capture a reference to the LSP client so we implement this callback
---------------------------------------------------------------------------------------------------
function M.attached(client, bufnr)
    log.trace("Attached client", client.id, "buffer", bufnr)
    L.lspclient = client
end

---------------------------------------------------------------------------------------------------
--- Generator will call this method to get kind of nodes that are of interest to each generator.
---------------------------------------------------------------------------------------------------
function M.digs()
    log.trace("digs:")
    return { "Switch" }
end

---------------------------------------------------------------------------------------------------
-- Generate from string functions for an enum nodes.
---------------------------------------------------------------------------------------------------
function M.generate(node, alias, scope, acceptor)
    log.trace("generate:", ast.details(node))

    if G.enum.switch.enabled then
        local cond = get_switch_condition_node(node)
        if cond then
            log.debug("generate:", "condition node", ast.details(cond))
            lsp.get_type_definition(L.lspclient, cond, function(n)
                log.debug("generate:", "definition node", ast.details(n))
                for _, item in ipairs(case_enum_item(n, cond)) do
                    acceptor(item)
                end
            end)
        end
    end
end

---------------------------------------------------------------------------------------------------
--- Info callback
---------------------------------------------------------------------------------------------------
function M.info()
    log.trace("info")
    local info = {}

    if G.enum.switch.enabled then
        table.insert(info, { G.enum.switch.trigger, "Case switch statements from enumeration" })
    end

    return info
end

---------------------------------------------------------------------------------------------------
--- Initialization callback
---------------------------------------------------------------------------------------------------
function M.setup(opts)
    log.trace("setup")
    G.enum = opts.enum
    log.trace("setup:", G)
end

return M
