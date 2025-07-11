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
-- Private parameters for code generation.
---------------------------------------------------------------------------------------------------
local P = {}

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

-- Apply parameters to the format string
local function apply(format)
    format = string.gsub(format, "<nullcheck>", P.nullcheck or '')
    format = string.gsub(format, "<nullvalue>", P.nullvalue or '')
    format = string.gsub(format, "<default>", P.default or '')

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
                record.label = G.class.json.label(ast.name(node), record.field, utl.camelize(record.field))

                -- Null handling checks
                if G.class.json.nullcheck then
                    if (object) then
                        record.nullcheck = G.class.json.nullcheck(object .. '.' .. record.field, ast.type(n))
                    else
                        record.nullcheck = G.class.json.nullcheck(record.field, ast.type(n))
                    end
                end
                if G.class.json.nullvalue then
                    if (object) then
                        record.nullvalue = G.class.json.nullvalue(object .. '.' .. record.field, ast.type(n))
                    else
                        record.nullvalue = G.class.json.nullvalue(record.field, ast.type(n))
                    end
                end
                -- Custom code will trigger field skipping when it sets either label or value to nil
                if record.label ~= nil then
                    if (object) then
                        record.value = G.class.json.value(object .. '.' .. record.field, ast.type(n))
                    else
                        record.value = G.class.json.value(record.field, ast.type(n))
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

    P.attribute            = G.attribute or ''
    P.classname            = alias and ast.name(alias) or ast.name(node)
    P.functionname         = G.class.json.name
    P.indent               = string.rep(' ', vim.lsp.util.get_effective_tabstop())

    local records          = class_labels_and_values(node, 'o')
    local maxllen, maxvlen = max_lengths(records)

    local lines            = {}

    if friend then
        table.insert(lines, apply('friend <attribute> std::string <functionname>(const <classname>& o, bool verbose)'))
    else
        table.insert(lines, apply('inline <attribute> std::string <functionname>(const <classname>& o, bool verbose)'))
    end
    table.insert(lines, apply('{'))
    table.insert(lines, apply('<indent>std::string s;'))
    if G.keepindent then
        table.insert(lines, apply('<indent>// clang-format off'))
    end
    table.insert(lines, apply('<indent>s += "{";'))

    --- Get straight - no null check code variation
    local function codex()
        return
        'std::string() + <dquote> + "<label>"<labelpad> + <dquote> + <colon> + <functionname>(<value><valuepad>, verbose);'
    end
    local function codez()
        return
        'std::string() + <dquote> + "<label>"<labelpad> + <dquote> + <colon> + (<nullcheck><valuepad> ? <functionname>(<nullvalue>, verbose) : <functionname>(<value><valuepad>, verbose));'
    end
    local function codey()
        return
        '(<nullcheck><valuepad> ? "" : std::string() + <dquote> + "<label>"<labelpad> + <dquote> + <colon> + <functionname>(<value><valuepad>, verbose));'
    end

    --- Get no-null-check code variation
    local function straight_code(l)
        table.insert(l, apply('<indent>s += ' .. codex()))
    end

    --- Get skip-null code variation
    local function skipnull_code(l)
        table.insert(l, apply('<indent>s += ' .. codey()))
    end

    --- Get show-null code variation
    local function shownull_code(l)
        table.insert(l, apply('<indent>s += ' .. codez()))
    end

    local idx = 1
    for _, r in ipairs(records) do
        P.fieldname = r.field
        P.label     = r.label
        P.value     = r.value
        P.labelpad  = string.rep(' ', maxllen - string.len(r.label))
        P.valuepad  = string.rep(' ', maxvlen - string.len(r.value))
        P.nullcheck = r.nullcheck
        P.nullvalue = r.nullvalue

        if r.nullcheck ~= nil then
            if r.nullvalue ~= nil then
                shownull_code(lines)
            else
                skipnull_code(lines, idx == #records)
            end
        else
            straight_code(lines)
        end
        idx = idx + 1
    end

    table.insert(lines, apply('<indent>s += "}";'))
    if G.keepindent then
        table.insert(lines, apply('<indent>// clang-format on'))
    end
    table.insert(lines, apply('<indent>return s;'))
    table.insert(lines, apply('}'))

    for _, l in ipairs(lines) do log.debug(l) end
    return lines
end

-- Generate completion items
local function save_class_items(lines)
    return
    {
        { name = G.class.json.name, trigger = G.class.json.trigger, lines = lines }
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
    for _, r in ipairs(utl.enum_records(node)) do
        local record = {}
        record.label = (alias and ast.name(alias) or ast.name(node)) .. '::' .. r.label
        record.value = vf(r.label, r.value) or r.label
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
    P.functionname = G.enum.json.name
    P.indent       = string.rep(' ', vim.lsp.util.get_effective_tabstop())

    local lines    = {}

    table.insert(lines, apply('inline <attribute> std::string <functionname>(<classname> o, bool verbose)'))
    table.insert(lines, apply('{'))

    -- Helper function to generate switch statement
    local function switch(lines, records, default, extraindent)
        local indent = extraindent and '<indent>' or ''

        table.insert(lines, apply(indent .. '<indent>switch(o)'))
        table.insert(lines, apply(indent .. '<indent>{'))

        if G.keepindent then
            table.insert(lines, apply('<indent><indent>// clang-format off'))
        end

        local maxllen, maxvlen = max_lengths(records)
        for _, r in ipairs(records) do
            P.label    = r.label
            P.value    = r.value
            P.labelpad = string.rep(' ', maxllen - string.len(r.label))
            P.valuepad = string.rep(' ', maxvlen - string.len(r.value))
            table.insert(lines,
                apply(indent ..
                '<indent><indent>case <label>:<labelpad> return <functionname>(<value><valuepad>, verbose); break;'))
        end

        if default then
            P.default = default
            table.insert(lines,
                apply(indent .. '<indent><indent>default: return <functionname>(<default>, verbose); break;'))
        end

        if G.keepindent then
            table.insert(lines, apply('<indent><indent>// clang-format on'))
        end

        table.insert(lines, apply(indent .. '<indent>};'))
    end

    --- Compare labels and values
    local function same(lhs, rhs)
        if #lhs == #rhs then
            for i = 1, #lhs do
                if lhs[i].label ~= rhs[i].label or lhs[i].value ~= rhs[i].value then
                    return false
                end
            end
            return true
        end
        return false
    end

    local vrecords = enum_labels_and_values(node, alias, G.enum.json.verbose.value)
    local trecords = enum_labels_and_values(node, alias, G.enum.json.terse.value)

    local vdefault = G.enum.json.verbose.default and G.enum.json.verbose.default(P.classname, 'o')
    local tdefault = G.enum.json.terse.default and G.enum.json.terse.default(P.classname, 'o')

    if (same(vrecords, trecords)) then
        switch(lines, vrecords, vdefault)
    else
        table.insert(lines, apply('<indent>if (verbose) {'))
        switch(lines, vrecords, vdefault, true)
        table.insert(lines, apply('<indent>} else {'))
        switch(lines, trecords, tdefault, true)
        table.insert(lines, apply('<indent>}'))
    end

    table.insert(lines, apply('<indent>return <functionname>("", verbose);'))

    table.insert(lines, apply('}'))

    for _, l in ipairs(lines) do log.debug(l) end
    return lines
end

-- Generate completion items
local function save_enum_items(lines)
    return
    {
        { name = G.enum.json.name, trigger = G.enum.json.trigger, lines = lines }
    }
end

-- Generate serialization function snippet items for a class type node.
local function save_enum_free_items(node, alias)
    log.trace("save_enum_free_items:", ast.details(node))
    return save_enum_items(save_enum_snippet(node, alias, false))
end

---------------------------------------------------------------------------------------------------
--- Public interface.
---------------------------------------------------------------------------------------------------
local M = {}

---------------------------------------------------------------------------------------------------
--- Generator will call this method to get kind of nodes that are of interest to each generator.
---------------------------------------------------------------------------------------------------
function M.digs()
    log.trace("digs:")
    return { "CXXRecord", "ClassTemplate", "Enum" }
end

---------------------------------------------------------------------------------------------------
-- Generate completion items
---------------------------------------------------------------------------------------------------
function M.generate(node, alias, scope, acceptor)
    log.trace("generate:", ast.details(node))

    if G.class.json.enabled then
        if ast.is_class(node) then
            if scope == ast.Class then
                for _, item in ipairs(save_class_friend_items(node, alias)) do
                    acceptor(item)
                end
            else
                for _, item in ipairs(save_class_free_items(node, alias)) do
                    acceptor(item)
                end
            end
        end
    end

    if ast.is_enum(node) then
        for _, item in ipairs(save_enum_free_items(node, alias)) do
            acceptor(item)
        end
    end
end

---------------------------------------------------------------------------------------------------
--- Info callback
---------------------------------------------------------------------------------------------------
function M.info()
    log.trace("info")
    local info = {}

    local function combine(name, trigger)
        return name == trigger and name or name .. ' or ' .. trigger
    end

    if G.class.json.enabled then
        table.insert(info, { combine(G.class.json.name, G.class.json.trigger), "Class serialization into JSON" })
    end
    if G.enum.json.enabled then
        table.insert(info, { combine(G.enum.json.name, G.enum.json.trigger), "Enum serialization into JSON" })
    end

    return info
end

---------------------------------------------------------------------------------------------------
--- Initialization callback. Capture relevant parts of the configuration.
---------------------------------------------------------------------------------------------------
function M.setup(opts)
    log.trace("setup")
    G.keepindent = opts.keepindent
    G.attribute  = opts.attribute
    G.class      = opts.class
    G.enum       = opts.enum
    log.trace("setup:", G)
end

return M
