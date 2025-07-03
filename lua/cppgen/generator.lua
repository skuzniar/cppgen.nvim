local log = require('cppgen.log')
local ast = require('cppgen.ast')

---------------------------------------------------------------------------------------------------
-- Collection of code snippet generators. It knows the types of AST nodes that the generators can 
-- handle and can tell if a given node is relevant for code generation.
-- Givan an AST node and the scope in which the code is generated, it calls specilized generators
-- to produce code snippets.
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Local parameters
---------------------------------------------------------------------------------------------------
local L = {
    digs = {},
}

---------------------------------------------------------------------------------------------------
-- Global parameters for code generation.
-- TODO - populate during configuration
---------------------------------------------------------------------------------------------------
local G = {
    require('cppgen.generators.class'),
    require('cppgen.generators.enum'),
    require('cppgen.generators.cereal'),
    require('cppgen.generators.json'),
    require('cppgen.generators.switch')
}

--- Exported functions
local M = {}

---------------------------------------------------------------------------------------------------
--- Initialization callback. Collect kind of nodes the generators can handle
---------------------------------------------------------------------------------------------------
function M.setup(opts)
    log.trace("setup")
    for _,g in pairs(G) do
        g.setup(opts)
        for _, k in ipairs(g.digs()) do
            L.digs[k] = true
        end
    end
    log.trace("setup:", L.digs)
end

---------------------------------------------------------------------------------------------------
--- LSP client attached callback. Some generators may need it to get extra type info.
---------------------------------------------------------------------------------------------------
function M.attached(client, bufnr)
    log.trace("Attached client", client.id, "buffer", bufnr)
    for _,g in pairs(G) do
        if g.attached then
            g.attached(client, bufnr)
        end
    end
end

---------------------------------------------------------------------------------------------------
--- Given a node, possibly a type alias, check if at least one of the generators finds it relevant.
---------------------------------------------------------------------------------------------------
function M.is_relevant(node)
    log.trace("is_relevant:", ast.details(node))
    local aliastype = ast.alias_type(node)
    if aliastype then
        log.trace("is_relevant:", ast.details(node), L.digs[aliastype.kind])
        return L.digs[aliastype.kind]
    end
    log.trace("is_relevant:", ast.details(node), L.digs[node.kind])
    return L.digs[node.kind]
end

---------------------------------------------------------------------------------------------------
--- Asynchronously generate code snippets for a node and scope. Callback will get code snippets.
---------------------------------------------------------------------------------------------------
function M.generate(node, alias, scope, acceptor)
    log.trace("generate:", ast.details(node))
    for _,g in pairs(G) do
        g.generate(node, alias, scope, acceptor)
    end
end

---------------------------------------------------------------------------------------------------
--- Info callback. Collect details about generators' capabilities.
---------------------------------------------------------------------------------------------------
function M.info()
    local total = {}
    for _,g in pairs(G) do
        local items = g.info();
        for _,i in ipairs(items) do
            table.insert(total, i)
        end
    end
    table.sort(total, function(a, b) return a[1] < b[1] end)
    return total
end

return M

