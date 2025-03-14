local ast = require('cppgen.ast')
local log = require('cppgen.log')
local utl = require('cppgen.generators.util')

---------------------------------------------------------------------------------------------------
-- JSON serializarion function generator.
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Global parameters for code generation. Initialized in setup.
---------------------------------------------------------------------------------------------------
local G = {}

---------------------------------------------------------------------------------------------------
-- Local parameters for code generation.
---------------------------------------------------------------------------------------------------
local P = {}

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

-- Apply parameters to the format string 
local function apply(format)
    format = string.gsub(format, "<nullcheck>", P.nullcheck or '')
    format = string.gsub(format, "<nullvalue>", P.nullvalue or '')

    return utl.apply(P, format)
end

-- Collect names and values for a class type node.
local function class_labels_and_values(node, object)
    local records = {}
    ast.visit_children(node,
        function(n)
            if n.kind == "Field" then
                local record = {}
                record.field = ast.name(n)
                record.label = G.json.class.label(ast.name(node), record.field, utl.camelize(record.field))

                -- Null handling checks
                if G.json.class.nullcheck then
                    if (object) then
                        record.nullcheck = G.json.class.nullcheck(object .. '.' .. record.field, ast.type(n))
                    else
                        record.nullcheck = G.json.class.nullcheck(record.field, ast.type(n))
                    end
                end
                if G.json.class.nullvalue then
                    if (object) then
                        record.nullvalue = G.json.class.nullvalue(object .. '.' .. record.field, ast.type(n))
                    else
                        record.nullvalue = G.json.class.nullvalue(record.field, ast.type(n))
                    end
                end
                -- Custom code will trigger field skipping when it sets either label or value to nil
                if record.label ~= nil then
                    if (object) then
                        record.value = G.json.class.value(object .. '.' .. record.field, ast.type(n))
                    else
                        record.value = G.json.class.value(record.field, ast.type(n))
                    end
                    if record.value ~= nil then
                        table.insert(records, record)
                    end
                end
            end
            return true
        end
    )
    return records
end

---------------------------------------------------------------------------------------------------
-- Generate serialization snippet for a class type node.
---------------------------------------------------------------------------------------------------
local function save_class_snippet(node, alias, friend)
    log.debug("save_class_snippet:", ast.details(node))

    P.attribute    = G.attribute or ''
    P.classname    = alias and ast.name(alias) or ast.name(node)
    P.functionname = G.json.name
    P.indent       = string.rep(' ', vim.lsp.util.get_effective_tabstop())

    local records = class_labels_and_values(node, 'o')
    local maxllen, maxvlen = max_lengths(records)

    local lines = {}

    if friend then
        table.insert(lines, apply('friend <attribute> std::string <functionname>(const <classname>& o, bool verbose)'))
    else
        table.insert(lines, apply('inline <attribute> std::string <functionname>(const <classname>& o, bool verbose)'))
    end
    table.insert(lines, apply('{'))
    if G.keepindent then
        table.insert(lines, apply('<indent>// clang-format off'))
    end
    table.insert(lines, apply('<indent>return std::string()'))
    table.insert(lines, apply('<indent><indent>+ "{"'))

    --- Get straight - no null check code variation
    local function code(last)
        return '<indent><indent>+ <dquote> + "<label>"<labelpad> + <dquote> + <colon> + <functionname>(<value><valuepad>, verbose)' .. (last and '' or ' + <comma>')
    end
    --- Get straight - no null check code variation
    local function straight_code(l, last)
        table.insert(l, apply(code(last)))
    end

    --- Get skip-null code variation
    local function skipnull_code(l, last)
        table.insert(l, apply('<indent>if(!<nullcheck>) {'))
        table.insert(l, apply(code(last)))
        table.insert(l, apply('<indent>}'))
    end

    --- Get show-null code variation
    local function shownull_code(l, last)
        table.insert(l, apply('<indent>if(!<nullcheck>) {'))
        table.insert(l, apply(code(last)))
        table.insert(l, apply('<indent>} else {'))
        table.insert(l, apply(code(last)))
        table.insert(l, apply('<indent>}'))
    end

    local idx = 1
    for _,r in ipairs(records) do
        P.fieldname = r.field
        P.label     = r.label
        P.value     = r.value
        P.labelpad  = string.rep(' ', maxllen - string.len(r.label))
        P.valuepad  = string.rep(' ', maxvlen - string.len(r.value))
        P.nullcheck = r.nullcheck
        P.nullvalue = r.nullvalue

        if r.nullcheck ~= nil then
            if r.nullvalue ~= nil then
                shownull_code(lines, idx == #records)
            else
                skipnull_code(lines, idx == #records)
            end
        else
            straight_code(lines, idx == #records)
        end
        idx = idx + 1
    end

    table.insert(lines, apply('<indent><indent>+ "}";'))
    if G.keepindent then
        table.insert(lines, apply('<indent>// clang-format on'))
    end
    table.insert(lines, apply('}'))

    for _,l in ipairs(lines) do log.debug(l) end
    return lines
end

-- Generate completion items
local function save_class_items(lines)
    return
    {
        { trigger = G.json.name, lines = lines },
        G.json.trigger ~= G.json.name and
        { trigger = G.json.trigger, lines = lines } or nil
    }
end

-- Generate serialization function snippet items for a class type node.
local function save_class_friend_items(node, alias)
    log.trace("save_class_friend_items:", ast.details(node))
    return save_class_items(save_class_snippet(node, alias, true))
end

local function save_class_free_items(node, alias)
    log.trace("save_class_free_items:", ast.details(node))
    return save_class_items(save_class_snippet(node, alias, false))
end

-- Collect names and values for an enum type node. Labels are fixed, values are calculated.
local function enum_labels_and_values(node, alias, vf)
    log.trace("labels_and_values:", ast.details(node))

    local lsandvs = {}
    for _,r in ipairs(utl.enum_records(node)) do
        local record = {}
        record.label = (alias and ast.name(alias) or ast.name(node)) .. '::' .. r.label
        record.value = vf(r.label, r.value)
        table.insert(lsandvs, record)
    end
    return lsandvs
end

---------------------------------------------------------------------------------------------------
-- Generate serialization snippet for an enum type node.
---------------------------------------------------------------------------------------------------
local function save_enum_snippet(node, alias)
    log.trace("save_enum_snippet:", ast.details(node))

    P.attribute    = G.attribute or ''
    P.classname    = alias and ast.name(alias) or ast.name(node)
    P.functionname = G.json.name
    P.indent       = string.rep(' ', vim.lsp.util.get_effective_tabstop())

    local lines = {}

    table.insert(lines, apply('inline <attribute> std::string <functionname>(<classname> o, bool verbose)'))
    table.insert(lines, apply('{'))

    if G.keepindent then
        table.insert(lines, apply('<indent>// clang-format off'))
    end

    -- Helper function to generate switch statement
    local function switch(lines, node, alias, valuef)
        table.insert(lines, apply('<indent><indent>switch(o)'))
        table.insert(lines, apply('<indent><indent>{'))

        local records = enum_labels_and_values(node, alias, valuef)
        local maxllen, maxvlen = max_lengths(records)
        for _,r in ipairs(records) do
            P.label     = r.label
            P.value     = r.value
            P.labelpad  = string.rep(' ', maxllen - string.len(r.label))
            P.valuepad  = string.rep(' ', maxvlen - string.len(r.value))
            table.insert(lines, apply('<indent><indent><indent>case <label>:<labelpad> return <functionname>(<value><valuepad>, verbose); break;'))
        end
        table.insert(lines, apply('<indent><indent>};'))
    end

    -- Verbose and terse versions
    table.insert(lines, apply('<indent>if (verbose) {'))
    switch(lines, node, alias, G.json.enum.verbose.value)
    table.insert(lines, apply('<indent>} else {'))
    switch(lines, node, alias, G.json.enum.terse.value)
    table.insert(lines, apply('<indent>}'))

    table.insert(lines, apply('<indent>return <functionname>("", verbose);'))

    if G.keepindent then
        table.insert(lines, apply('<indent>// clang-format on'))
    end
    table.insert(lines, apply('}'))

    for _,l in ipairs(lines) do log.debug(l) end
    return lines
end

-- Generate completion items
local function save_enum_items(lines)
    return
    {
        { trigger = G.json.name, lines = lines },
        G.json.trigger ~= G.json.name and
        { trigger = G.json.trigger, lines = lines } or nil
    }
end

-- Generate serialization function snippet items for a class type node.
local function save_enum_free_items(node, alias)
    log.trace("save_enum_free_items:", ast.details(node))
    return save_enum_items(save_enum_snippet(node, alias, false))
end

local enclosing_node = nil
local preceding_node = nil
local typealias_node = nil

local M = {}

---------------------------------------------------------------------------------------------------
--- Generator will call this method to get kind of nodes that are of interest to each generator.
---------------------------------------------------------------------------------------------------
function M.digs()
    log.trace("digs:")
    return { "CXXRecord", "ClassTemplate", "Enum" }
end

--- Generator will call this method before presenting a set of new candidate nodes
function M.reset()
    enclosing_node = nil
    preceding_node = nil
    typealias_node = nil
end

---------------------------------------------------------------------------------------------------
--- Generator will call this method with a node, optional type alias and a node location
---------------------------------------------------------------------------------------------------
function M.visit(node, alias, location)
    -- We can generate serialization function for enclosing class node
    if location == ast.Encloses and ast.is_class(node) then
        log.debug("visit:", "Accepted enclosing node", ast.details(node))
        enclosing_node = node
    end
    -- We can generate serialization function for preceding enumeration and class nodes
    if location == ast.Precedes and (ast.is_enum(node) or ast.is_class(node)) then
        log.debug("visit:", "Accepted preceding node", ast.details(node))
        preceding_node = node
    end
    typealias_node = alias
end

---------------------------------------------------------------------------------------------------
--- Generator will call this method to check if the module can generate code
---------------------------------------------------------------------------------------------------
function M.available()
    return enclosing_node ~= nil or preceding_node ~= nil
end

-- Add elements of one table into another table
local function add_to(to, from)
    for _,item in ipairs(from) do
        table.insert(to, item)
    end
end
---------------------------------------------------------------------------------------------------
-- Generate completion items
---------------------------------------------------------------------------------------------------
function M.generate(strict)
    log.trace("generate:", ast.details(preceding_node), ast.details(enclosing_node))

    local items = {}
    if ast.is_class(enclosing_node) then
        add_to(items, save_class_friend_items(enclosing_node, typealias_node))
    end
    if ast.is_class(preceding_node) then
        add_to(items, save_class_free_items(preceding_node, typealias_node))
    end
    if ast.is_enum(preceding_node) then
        add_to(items, save_enum_free_items(preceding_node, typealias_node))
    end
    return items
end

---------------------------------------------------------------------------------------------------
--- Info callback
---------------------------------------------------------------------------------------------------
local function combine(name, trigger)
    return name == trigger and name or name .. ' or ' .. trigger
end

function M.info()
    return {
        { combine(G.json.name, G.json.trigger), "Class and enum serialization into JSON" }
    }
end

---------------------------------------------------------------------------------------------------
--- Initialization callback. Capture relevant parts of the configuration.
---------------------------------------------------------------------------------------------------
function M.setup(opts)
    G.keepindent = opts.keepindent
    G.attribute  = opts.attribute
    G.json       = opts.json
end

return M
