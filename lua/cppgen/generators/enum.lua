local ast = require('cppgen.ast')
local log = require('cppgen.log')
local utl = require('cppgen.generators.util')

---------------------------------------------------------------------------------------------------
-- Enum function generators.
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Global parameters for code generation. Initialized in setup.
---------------------------------------------------------------------------------------------------
local G = {}

---------------------------------------------------------------------------------------------------
-- Private parameters for code generation.
---------------------------------------------------------------------------------------------------
local P = {}

-- Apply parameters to the format string
local function apply(format)
    format = string.gsub(format, "<errortype>", P.errortype or '')
    format = string.gsub(format, "<error>", P.error or '')
    format = string.gsub(format, "<exception>", P.exception or '')
    format = string.gsub(format, "<default>", P.default or '')

    return utl.apply(P, format)
end

-- Collect names and values for an enum type node. Labels are fixed, values are calculated.
local function labels_and_values(node, alias, vf)
    log.trace("labels_and_values:", ast.details(node))

    local lsandvs = {}
    for _, r in ipairs(utl.enum_records(node)) do
        local record = {}
        record.label = (alias and ast.name(alias) or ast.name(node)) .. '::' .. r.label
        record.value = vf(r.label, r.value)
        table.insert(lsandvs, record)
    end
    return lsandvs
end

-- Calculate the longest length of labels and values
local function max_lengths(records)
    local max_lab_len = 0
    local max_val_len = 0

    for _, r in ipairs(records) do
        if r.label then
            max_lab_len = math.max(max_lab_len, string.len(r.label))
        end
        if r.value then
            max_val_len = math.max(max_val_len, string.len(r.value))
        end
    end
    return max_lab_len, max_val_len
end

---------------------------------------------------------------------------------------------------
-- Generate to string converter.
---------------------------------------------------------------------------------------------------
local function to_string_snippet(node, alias, specifier)
    log.trace("to_string_snippet:", ast.details(node))

    P.specifier            = specifier
    P.attribute            = G.attribute and ' ' .. G.attribute or ''
    P.classname            = alias and ast.name(alias) or ast.name(node)
    P.functionname         = G.enum.to_string.name
    P.indent               = string.rep(' ', vim.lsp.util.get_effective_tabstop())

    local records          = labels_and_values(node, alias, G.enum.to_string.value)
    local maxllen, maxvlen = max_lengths(records)

    local lines            = {}

    table.insert(lines, apply('<specifier> <attribute> std::string <functionname>(<classname> o)'))
    table.insert(lines, apply('{'))
    table.insert(lines, apply('<indent>switch(o)'))
    table.insert(lines, apply('<indent>{'))
    if G.keepindent then
        table.insert(lines, apply('<indent><indent>// clang-format off'))
    end

    for _, r in ipairs(records) do
        P.label    = r.label
        P.value    = r.value
        P.labelpad = string.rep(' ', maxllen - string.len(r.label))
        P.valuepad = string.rep(' ', maxvlen - string.len(r.value))
        table.insert(lines, apply('<indent><indent>case <label>:<labelpad> return <value>;<valuepad> break;'))
    end

    if G.enum.to_string.default then
        P.default = G.enum.to_string.default(P.classname, 'o')
        if P.default then
            table.insert(lines, apply('<indent><indent>default: return <default>; break;'))
        end
    end

    if G.keepindent then
        table.insert(lines, apply('<indent><indent>// clang-format on'))
    end
    table.insert(lines, apply('<indent>};'))
    table.insert(lines, apply('}'))

    for _, l in ipairs(lines) do log.debug(l) end
    return lines
end

-- Optionally replicate the lines and generate multiple completion items that can be triggered by different labels.
local function to_string_items(lines)
    return
    {
        { name = G.enum.to_string.name, trigger = G.enum.to_string.trigger, lines = lines }
    }
end

-- Generate to string member function converter completion item for an enum type node.
local function to_string_member_items(node, alias)
    log.trace("to_string_member_items:", ast.details(node))
    return to_string_items(to_string_snippet(node, alias, 'friend'))
end

-- Generate to string free function converter completion item for an enum type node.
local function to_string_free_items(node, alias)
    log.trace("to_string_free_items:", ast.details(node))
    return to_string_items(to_string_snippet(node, alias, 'inline'))
end

---------------------------------------------------------------------------------------------------
-- Generate enumerator cast snipets. Converts from string matching on enumerator name.
---------------------------------------------------------------------------------------------------
local function string_cast_snippets(node, alias, specifier, throw)
    log.trace("string_cast_snippets:", ast.details(node))

    P.specifier      = specifier
    P.attribute      = G.attribute and ' ' .. G.attribute or ''
    P.classname      = alias and ast.name(alias) or ast.name(node)
    P.functionname   = G.enum.cast.name
    P.indent         = string.rep(' ', vim.lsp.util.get_effective_tabstop())
    P.errortype      = G.enum.cast.from_string_no_throw.errortype
    P.error          = G.enum.cast.from_string_no_throw.error(P.classname, 'v')
    P.exception      = G.enum.cast.from_string.exception(P.classname, 'v')

    P.declaration    = 'template<typename T>'
    P.specialization = 'template<>'

    local records    = utl.enum_records(node)
    local maxllen, _ = max_lengths(records)

    local function declpattern(throwing)
        if throwing then
            return '<declaration> <specifier> <attribute> T <functionname>(std::string_view v);'
        else
            return '<declaration> <specifier> <attribute> T <functionname>(std::string_view v, <errortype>& error) noexcept;'
        end
    end

    local function specpattern(throwing)
        if throwing then
            if P.specifier == 'static' then
                return '<specialization> <attribute> <classname> <functionname><<classname>>(std::string_view v)'
            else
                return '<specialization> <specifier> <attribute> <classname> <functionname><<classname>>(std::string_view v)'
            end
        else
            if P.specifier == 'static' then
                return '<specialization> <attribute> <classname> <functionname><<classname>>(std::string_view v, <errortype>& error) noexcept'
            else
                return '<specialization> <specifier> <attribute> <classname> <functionname><<classname>>(std::string_view v, <errortype>& error) noexcept'
            end
        end
    end

    local decl = { apply(declpattern(throw)) }
    local spec = { apply(specpattern(throw)) }

    table.insert(spec, '{')
    if G.keepindent then
        table.insert(spec, apply('<indent>// clang-format off'))
    end

    for _, r in ipairs(records) do
        P.fieldname = r.label
        P.valuepad  = string.rep(' ', maxllen - string.len(P.fieldname))
        table.insert(spec, apply('<indent>if (v == "<fieldname>")<valuepad> return <classname>::<fieldname>;'))
    end

    if G.keepindent then
        table.insert(spec, apply('<indent>// clang-format on'))
    end
    if throw then
        table.insert(spec, apply('<indent>throw <exception>;'))
    else
        table.insert(spec, apply('<indent>error = <error>;'))
        table.insert(spec, apply('<indent>return <classname>{};'))
    end
    table.insert(spec, '}')

    for _, l in ipairs(decl) do log.debug(l) end
    for _, l in ipairs(spec) do log.debug(l) end

    return decl, spec
end

---------------------------------------------------------------------------------------------------
-- Generate enumerator cast snipets. Converts from integer matching on enumerator value.
---------------------------------------------------------------------------------------------------
local function integer_cast_snippets(node, alias, specifier, throw)
    log.trace("integer_cast_snippets:", ast.details(node))

    P.specifier      = specifier
    P.attribute      = G.attribute and ' ' .. G.attribute or ''
    P.classname      = alias and ast.name(alias) or ast.name(node)
    P.functionname   = G.enum.cast.name
    P.indent         = string.rep(' ', vim.lsp.util.get_effective_tabstop())
    P.errortype      = G.enum.cast.from_integer_no_throw.errortype
    P.error          = G.enum.cast.from_integer_no_throw.error(P.classname, 'v')
    P.exception      = G.enum.cast.from_integer.exception(P.classname, 'v')

    P.declaration    = 'template<typename T>'
    P.specialization = 'template<>'

    local records    = utl.enum_records(node)
    local maxllen, _ = max_lengths(records)

    local function declpattern(throwing)
        if throwing then
            return '<declaration> <specifier> <attribute> T <functionname>(int v);'
        else
            return '<declaration> <specifier> <attribute> T <functionname>(int v, <errortype>& error) noexcept;'
        end
    end

    local function specpattern(throwing)
        if throwing then
            if P.specifier == 'static' then
                return '<specialization> <attribute> <classname> <functionname><<classname>>(int v)'
            else
                return '<specialization> <specifier> <attribute> <classname> <functionname><<classname>>(int v)'
            end
        else
            if P.specifier == 'static' then
                return '<specialization> <attribute> <classname> <functionname><<classname>>(int v, <errortype>& error) noexcept'
            else
                return '<specialization> <specifier> <attribute> <classname> <functionname><<classname>>(int v, <errortype>& error) noexcept'
            end
        end
    end

    local decl = { apply(declpattern(throw)) }
    local spec = { apply(specpattern(throw)) }

    table.insert(spec, '{')

    local cnt = ast.count_children(node,
        function(n)
            return n.kind == "EnumConstant"
        end
    )

    table.insert(spec, apply('<indent>if ('))
    if G.keepindent then
        table.insert(spec, apply('<indent><indent>// clang-format off'))
    end

    local idx = 1
    for _, r in ipairs(records) do
        P.fieldname = r.label
        P.valuepad  = string.rep(' ', maxllen - string.len(P.fieldname))
        if idx == cnt then
            table.insert(spec,
                apply(
                    '<indent><indent>v == static_cast<std::underlying_type_t<<classname>>>(<classname>::<fieldname>)<valuepad>)'))
        else
            table.insert(spec,
                apply(
                    '<indent><indent>v == static_cast<std::underlying_type_t<<classname>>>(<classname>::<fieldname>)<valuepad> ||'))
        end
        idx = idx + 1
    end

    if G.keepindent then
        table.insert(spec, apply('<indent><indent>// clang-format on'))
    end

    table.insert(spec, apply('<indent>{'))
    table.insert(spec, apply('<indent><indent>return static_cast<<classname>>(v);'))
    table.insert(spec, apply('<indent>}'))
    if throw then
        table.insert(spec, apply('<indent>throw <exception>;'))
    else
        table.insert(spec, apply('<indent>error = <error>;'))
        table.insert(spec, apply('<indent>return <classname>{};'))
    end
    table.insert(spec, '}')

    for _, l in ipairs(decl) do log.debug(l) end
    for _, l in ipairs(spec) do log.debug(l) end

    return decl, spec
end

---------------------------------------------------------------------------------------------------
-- Collect non-empty completion items. Note that we expect nested table here.
---------------------------------------------------------------------------------------------------
local function cast_items(...)
    local items = {}
    for _, t in ipairs({ ... }) do
        for _, l in ipairs(t) do
            table.insert(items, { name = G.enum.cast.name, trigger = G.enum.cast.trigger, lines = l })
        end
    end
    return items
end

---------------------------------------------------------------------------------------------------
-- Generate from string enumerator member function snippet items for an enum type node.
---------------------------------------------------------------------------------------------------
local function cast_member_items(node, alias)
    log.trace("cast_member_items:", ast.details(node))

    local decls = {}
    local specs = {}

    if G.enum.cast.from_string.enabled then
        local decl, spec = string_cast_snippets(node, alias, 'static', true)
        utl.append(decls, decl)
        utl.append(specs, spec)
    end
    if G.enum.cast.from_string_no_throw.enabled then
        local decl, spec = string_cast_snippets(node, alias, 'static', false)
        utl.append(decls, decl)
        utl.append(specs, spec)
    end
    if G.enum.cast.from_integer.enabled then
        local decl, spec = integer_cast_snippets(node, alias, 'static', true)
        utl.append(decls, decl)
        utl.append(specs, spec)
    end
    if G.enum.cast.from_integer_no_throw.enabled then
        local decl, spec = integer_cast_snippets(node, alias, 'static', false)
        utl.append(decls, decl)
        utl.append(specs, spec)
    end

    for _, l in ipairs(decls) do log.info(l) end
    for _, l in ipairs(specs) do log.info(l) end

    return cast_items({ decls }, { specs })
end

---------------------------------------------------------------------------------------------------
-- Generate from string enumerator free function snippet items for an enum type node.
---------------------------------------------------------------------------------------------------
local function cast_free_items(node, alias)
    log.trace("cast_free_items:", ast.details(node))

    local decls = {}
    local specs = {}

    if G.enum.cast.from_string.enabled then
        local decl, spec = string_cast_snippets(node, alias, 'inline', true)
        utl.append(decls, decl)
        utl.append(specs, spec)
    end
    if G.enum.cast.from_string_no_throw.enabled then
        local decl, spec = string_cast_snippets(node, alias, 'inline', false)
        utl.append(decls, decl)
        utl.append(specs, spec)
    end
    if G.enum.cast.from_integer.enabled then
        local decl, spec = integer_cast_snippets(node, alias, 'inline', true)
        utl.append(decls, decl)
        utl.append(specs, spec)
    end
    if G.enum.cast.from_integer_no_throw.enabled then
        local decl, spec = integer_cast_snippets(node, alias, 'inline', false)
        utl.append(decls, decl)
        utl.append(specs, spec)
    end

    return cast_items({ decls }, { specs })
end

---------------------------------------------------------------------------------------------------
-- Generate output stream shift operator
---------------------------------------------------------------------------------------------------
local function shift_snippet(node, alias, specifier)
    log.trace("shift_snippet:", ast.details(node))

    P.specifier            = specifier
    P.attribute            = G.attribute and ' ' .. G.attribute or ''
    P.classname            = alias and ast.name(alias) or ast.name(node)
    P.indent               = string.rep(' ', vim.lsp.util.get_effective_tabstop())

    local records          = labels_and_values(node, alias, G.enum.shift.value)
    local maxllen, maxvlen = max_lengths(records)

    local lines            = {}

    table.insert(lines, apply('<specifier> <attribute> std::ostream& operator<<(std::ostream& s, <classname> o)'))
    table.insert(lines, apply('{'))

    if G.enum.shift.to_string then
        table.insert(lines, apply('<indent>return s << to_string(o);'))
    else
        table.insert(lines, apply('<indent>switch(o)'))
        table.insert(lines, apply('<indent>{'))
        if G.keepindent then
            table.insert(lines, apply('<indent><indent>// clang-format off'))
        end
        for _, r in ipairs(records) do
            P.label    = r.label
            P.value    = r.value
            P.labelpad = string.rep(' ', maxllen - string.len(r.label))
            P.valuepad = string.rep(' ', maxvlen - string.len(r.value))
            table.insert(lines, apply('<indent><indent>case <label>:<labelpad> s << <value>;<valuepad> break;'))
        end
        if G.enum.shift.default then
            P.default = G.enum.shift.default(P.classname, 'o')
            if P.default then
                table.insert(lines, apply('<indent><indent>default: s << <default>; break;'))
            end
        end
        if G.keepindent then
            table.insert(lines, apply('<indent><indent>// clang-format on'))
        end
        table.insert(lines, apply('<indent>};'))
        table.insert(lines, apply('<indent>return s;'))
    end
    table.insert(lines, apply('}'))

    for _, l in ipairs(lines) do log.debug(l) end
    return lines
end

-- Optionally replicate the lines and generate multiple completion items that can be triggered by different labels.
local function shift_items(lines)
    return
    {
        { name = string.match(lines[1], "^([%w]+)"), trigger = G.enum.shift.trigger, lines = lines }
    }
end

-- Generate output stream shift member operator completion item for an enum type node.
local function shift_member_items(node, alias)
    log.trace("shift_member_items:", ast.details(node))
    return shift_items(shift_snippet(node, alias, 'friend'))
end

-- Generate output stream shift free operator completion item for an enum type node.
local function shift_free_items(node, alias)
    log.trace("shift_free_items:", ast.details(node))
    return shift_items(shift_snippet(node, alias, 'inline'))
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
    return { "Enum" }
end

---------------------------------------------------------------------------------------------------
--- Generator will call this method to get generated code
---------------------------------------------------------------------------------------------------
function M.generate(node, alias, scope, acceptor)
    log.trace("generate:", ast.details(node))

    if ast.is_enum(node) then
        if scope == ast.Class then
            if G.enum.to_string.enabled then
                for _, item in ipairs(to_string_member_items(node, alias)) do
                    acceptor(item)
                end
            end
            for _, item in ipairs(cast_member_items(node, alias)) do
                acceptor(item)
            end
            if G.enum.shift.enabled then
                for _, item in ipairs(shift_member_items(node, alias)) do
                    acceptor(item)
                end
            end
        else
            if G.enum.to_string.enabled then
                for _, item in ipairs(to_string_free_items(node, alias)) do
                    acceptor(item)
                end
            end
            for _, item in ipairs(cast_free_items(node, alias)) do
                acceptor(item)
            end
            if G.enum.shift.enabled then
                for _, item in ipairs(shift_free_items(node, alias)) do
                    acceptor(item)
                end
            end
        end
    end
end

---------------------------------------------------------------------------------------------------
--- Info callback
---------------------------------------------------------------------------------------------------
function M.info()
    local function combine(name, trigger)
        return name == trigger and name or name .. ' or ' .. trigger
    end

    local info = {}
    if G.enum.to_string.enabled then
        table.insert(info, { combine(G.enum.to_string.name, G.enum.to_string.trigger), "Enum class to string converter" })
    end

    local trigger = combine(G.enum.cast.name, G.enum.cast.trigger)
    if G.enum.cast.from_string.enabled then
        table.insert(info, { trigger, "Throwing constructor of enum class from string" })
    end
    if G.enum.cast.from_string_no_throw.enabled then
        table.insert(info, { trigger, "Non throwing constructor of enum class from string" })
    end
    if G.enum.cast.from_integer.enabled then
        table.insert(info, { trigger, "Throwing constructor of enum class from the underlying type" })
    end
    if G.enum.cast.from_integer_no_throw.enabled then
        table.insert(info, { trigger, "Non throwing constructor of enum class from the underlying type" })
    end

    if G.enum.shift.enabled then
        table.insert(info, { G.enum.shift.trigger, "Enum class output stream shift operator" })
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
    G.enum       = opts.enum
    log.trace("setup:", G)
end

return M
