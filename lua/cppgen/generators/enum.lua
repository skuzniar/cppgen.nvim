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
-- Local parameters for code generation.
---------------------------------------------------------------------------------------------------
local P = {}

-- Apply parameters to the format string 
local function apply(format)
    local result  = format

    result = string.gsub(result, "<label>",        P.label        or '')
    result = string.gsub(result, "<labelpad>",     P.labelpad     or '')
    result = string.gsub(result, "<value>",        P.value        or '')
    result = string.gsub(result, "<valuepad>",     P.valuepad     or '')
    result = string.gsub(result, "<specifier>",    P.specifier    or '')
    result = string.gsub(result, "<attribute>",    P.attribute    or '')
    result = string.gsub(result, "<classname>",    P.classname    or '')
    result = string.gsub(result, "<functionname>", P.functionname or '')
    result = string.gsub(result, "<fieldname>",    P.fieldname    or '')
    result = string.gsub(result, "<separator>",    P.separator    or '')
    result = string.gsub(result, "<indent>",       P.indent       or '')
    result = string.gsub(result, "<errortype>",    P.errortype    or '')
    result = string.gsub(result, "<error>",        P.error        or '')
    result = string.gsub(result, "<exception>",    P.exception    or '')

    return result;
end

-- Collect names and values for an enum type node. Labels are fixed, values are calculated.
local function labels_and_values(node, alias, vf)
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

-- Calculate the longest length of labels and values
local function max_lengths(records)
    local max_lab_len = 0
    local max_val_len = 0

    for _,r in ipairs(records) do
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

    P.specifier    = specifier
    P.attribute    = G.attribute and ' ' .. G.attribute or ''
    P.classname    = alias and ast.name(alias) or ast.name(node)
    P.functionname = G.enum.to_string.name
    P.indent       = string.rep(' ', vim.lsp.util.get_effective_tabstop())

    local records = labels_and_values(node, alias, G.enum.to_string.value)
    local maxllen, maxvlen = max_lengths(records)

    local lines = {}

    table.insert(lines, apply('<specifier><attribute> std::string <functionname>(<classname> o)'))
    table.insert(lines, apply('{'))
    table.insert(lines, apply('<indent>switch(o)'))
    table.insert(lines, apply('<indent>{'))
    if G.keepindent then
        table.insert(lines, apply('<indent><indent>// clang-format off'))
    end

    for _,r in ipairs(records) do
        P.label     = r.label
        P.value     = r.value
        P.labelpad  = string.rep(' ', maxllen - string.len(r.label))
        P.valuepad  = string.rep(' ', maxvlen - string.len(r.value))
        table.insert(lines, apply('<indent><indent>case <label>:<labelpad> return <value>;<valuepad> break;'))
    end

    if G.keepindent then
        table.insert(lines, apply('<indent><indent>// clang-format on'))
    end
    table.insert(lines, apply('<indent>};'))
    table.insert(lines, apply('}'))

    for _,l in ipairs(lines) do log.debug(l) end
    return lines
end

-- Optionally replicate the lines and generate multiple completion items that can be triggered by different labels.
local function to_string_items(lines)
    return
    {
        { trigger = G.enum.to_string.name, lines = lines },
        G.enum.to_string.trigger ~= G.enum.to_string.name and
        { trigger = G.enum.to_string.trigger, lines = lines } or nil
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
local function enum_cast_snippets(node, alias, specifier, throw)
    log.trace("enum_cast_snippets:", ast.details(node))

    P.specifier    = specifier
    P.attribute    = G.attribute and ' ' .. G.attribute or ''
    P.classname    = alias and ast.name(alias) or ast.name(node)
    P.functionname = G.enum.cast.name
    P.indent       = string.rep(' ', vim.lsp.util.get_effective_tabstop())
    P.errortype    = G.enum.cast.enum_cast_no_throw.errortype
    P.error        = G.enum.cast.enum_cast_no_throw.error(P.classname, 'e')
    P.exception    = G.enum.cast.enum_cast.exception(P.classname, 'e')

    local maxllen, _ = max_lengths(utl.enum_records(node))

    local primary = {}
    if throw then
        table.insert(primary, apply('<specifier><attribute> <classname> <functionname>(std::string_view e)'))
    else
        table.insert(primary, apply('<specifier><attribute> <classname> <functionname>(std::string_view e, <errortype>& error) noexcept'))
    end
    table.insert(primary, '{')
    if G.keepindent then
        table.insert(primary, apply('<indent>// clang-format off'))
    end
    ast.visit_children(node,
        function(n)
            if n.kind == "EnumConstant" then
                P.fieldname = ast.name(n)
                P.valuepad  = string.rep(' ', maxllen - string.len(P.fieldname))
                table.insert(primary, apply('<indent>if (e == "<fieldname>")<valuepad> return <classname>::<fieldname>;'))
            end
            return true
        end
    )
    if G.keepindent then
        table.insert(primary, apply('<indent>// clang-format on'))
    end
    if throw then
        table.insert(primary, apply('<indent>throw <exception>;'))
    else
        table.insert(primary, apply('<indent>error = <error>;'))
        table.insert(primary, apply('<indent>return <classname>{};'))
    end
    table.insert(primary, '}')

    -- Add a forwarding functions that take char pointer or string and forwards it as string view
    local cptrfwd = {}
    local strnfwd = {}
    if throw then
        table.insert(cptrfwd, apply('<specifier><attribute> <classname> <functionname>(const char* e)'))
        table.insert(cptrfwd, apply('{'))
        table.insert(cptrfwd, apply('<indent>return <functionname><<classname>>(std::string_view(e));'))
        table.insert(cptrfwd, apply('}'))

        table.insert(strnfwd, apply('<specifier><attribute> <classname> <functionname>(const std::string& e)'))
        table.insert(strnfwd, apply('{'))
        table.insert(strnfwd, apply('<indent>return <functionname><<classname>>(std::string_view(e));'))
        table.insert(strnfwd, apply('}'))
    else
        table.insert(cptrfwd, apply('<specifier><attribute> <classname> <functionname>(const char* e, <errortype>& error) noexcept'))
        table.insert(cptrfwd, apply('{'))
        table.insert(cptrfwd, apply('<indent>return <functionname><<classname>>(std::string_view(e), error);'))
        table.insert(cptrfwd, apply('}'))

        table.insert(strnfwd, apply('<specifier><attribute> <classname> <functionname>(const std::string& e, <errortype>& error) noexcept'))
        table.insert(strnfwd, apply('{'))
        table.insert(strnfwd, apply('<indent>return <functionname><<classname>>(std::string_view(e), error);'))
        table.insert(strnfwd, apply('}'))
    end

    for _,l in ipairs(primary) do log.debug(l) end
    for _,l in ipairs(cptrfwd) do log.debug(l) end
    for _,l in ipairs(strnfwd) do log.debug(l) end

    if P.strict then
        return { primary, cptrfwd, strnfwd }
    end
    return { utl.combine(primary, cptrfwd, strnfwd) }
end

---------------------------------------------------------------------------------------------------
-- Generate enumerator cast snipets. Converts from integer matching on enumerator value.
---------------------------------------------------------------------------------------------------
local function value_cast_snippets(node, alias, specifier, throw)
    log.trace("value_cast_snippets:", ast.details(node))

    P.specifier    = specifier
    P.attribute    = G.attribute and ' ' .. G.attribute or ''
    P.classname    = alias and ast.name(alias) or ast.name(node)
    P.functionname = G.enum.cast.name
    P.indent       = string.rep(' ', vim.lsp.util.get_effective_tabstop())
    P.errortype    = G.enum.cast.value_cast_no_throw.errortype
    P.error        = G.enum.cast.value_cast_no_throw.error(P.classname, 'v')
    P.exception    = G.enum.cast.value_cast.exception(P.classname, 'v')

    local maxllen, _ = max_lengths(utl.enum_records(node))

    local lines = {}

    if throw then
        table.insert(lines, apply('<specifier><attribute> <classname> <functionname>(std::underlying_type_t<<classname>> v)'))
    else
        table.insert(lines, apply('<specifier><attribute> <classname> <functionname>(std::underlying_type_t<<classname>> v, <errortype>& error) noexcept'))
    end
    table.insert(lines, '{')

    local cnt = ast.count_children(node,
        function(n)
            return n.kind == "EnumConstant"
        end
    )

    table.insert(lines, apply('<indent>if ('))
    if G.keepindent then
        table.insert(lines, apply('<indent><indent>// clang-format off'))
    end
    local idx = 1
    ast.visit_children(node,
        function(n)
            if n.kind == "EnumConstant" then
                P.fieldname = ast.name(n)
                P.valuepad  = string.rep(' ', maxllen - string.len(P.fieldname))
                if idx == cnt then
                    table.insert(lines, apply('<indent><indent>v == static_cast<std::underlying_type_t<<classname>>>(<classname>::<fieldname>)<valuepad>)'))
                else
                    table.insert(lines, apply('<indent><indent>v == static_cast<std::underlying_type_t<<classname>>>(<classname>::<fieldname>)<valuepad> ||'))
                end
                idx = idx + 1
            end
            return true
        end
    )
    if G.keepindent then
        table.insert(lines, apply('<indent><indent>// clang-format on'))
    end

    table.insert(lines, apply('<indent>{'))
    table.insert(lines, apply('<indent><indent>return static_cast<<classname>>(v);'))
    table.insert(lines, apply('<indent>}'))
    if throw then
        table.insert(lines, apply('<indent>throw <exception>;'))
    else
        table.insert(lines, apply('<indent>error = <error>;'))
        table.insert(lines, apply('<indent>return <classname>{};'))
    end
    table.insert(lines, '}')

    for _,l in ipairs(lines) do log.debug(l) end
    return { lines }
end

---------------------------------------------------------------------------------------------------
-- Collect non-empty completion items. Note that we expect nested table here.
---------------------------------------------------------------------------------------------------
local function cast_items(...)
    local items = {}
    for _,t in ipairs({...}) do
        for _,l in ipairs(t) do
            table.insert(items, { trigger = G.enum.cast.name, lines = l })
            if G.enum.cast.trigger ~= G.enum.cast.name then
                table.insert(items, { trigger = G.enum.cast.trigger, lines = l })
            end
        end
    end
    return items
end

---------------------------------------------------------------------------------------------------
-- Generate from string enumerator member function snippet items for an enum type node.
---------------------------------------------------------------------------------------------------
local function cast_member_items(node, alias)
    log.trace("enum_cast_member_items:", ast.details(node))
    if P.strict then
        return cast_items(
            G.enum.cast.enum_cast.enabled           and enum_cast_snippets (node, alias, 'template <>', true ) or {},
            G.enum.cast.enum_cast_no_throw.enabled  and enum_cast_snippets (node, alias, 'template <>', false) or {},
            G.enum.cast.value_cast.enabled          and value_cast_snippets(node, alias, 'template <>', true ) or {},
            G.enum.cast.value_cast_no_throw.enabled and value_cast_snippets(node, alias, 'template <>', false) or {})
    end
    return cast_items(
        {
            utl.flatten(
                G.enum.cast.enum_cast.enabled           and enum_cast_snippets (node, alias, 'template <>', true ) or {},
                G.enum.cast.enum_cast_no_throw.enabled  and enum_cast_snippets (node, alias, 'template <>', false) or {})
        },
        {
            utl.flatten(
                G.enum.cast.value_cast.enabled          and value_cast_snippets(node, alias, 'template <>', true ) or {},
                G.enum.cast.value_cast_no_throw.enabled and value_cast_snippets(node, alias, 'template <>', false) or {})
        })
end

---------------------------------------------------------------------------------------------------
-- Generate from string enumerator free function snippet items for an enum type node.
---------------------------------------------------------------------------------------------------
local function cast_free_items(node, alias)
    log.trace("enum_cast_free_items:", ast.details(node))
    if P.strict then
        return cast_items(
            G.enum.cast.enum_cast.enabled           and enum_cast_snippets (node, alias, 'template <> inline', true ) or {},
            G.enum.cast.enum_cast_no_throw.enabled  and enum_cast_snippets (node, alias, 'template <> inline', false) or {},
            G.enum.cast.value_cast.enabled          and value_cast_snippets(node, alias, 'template <> inline', true ) or {},
            G.enum.cast.value_cast_no_throw.enabled and value_cast_snippets(node, alias, 'template <> inline', false) or {})
    end
    return cast_items(
        {
            utl.flatten(
                G.enum.cast.enum_cast.enabled           and enum_cast_snippets (node, alias, 'template <> inline', true ) or {},
                G.enum.cast.enum_cast_no_throw.enabled  and enum_cast_snippets (node, alias, 'template <> inline', false) or {})
        },
        {
            utl.flatten(
                G.enum.cast.value_cast.enabled          and value_cast_snippets(node, alias, 'template <> inline', true ) or {},
                G.enum.cast.value_cast_no_throw.enabled and value_cast_snippets(node, alias, 'template <> inline', false) or {})
        })
end

---------------------------------------------------------------------------------------------------
-- Generate output stream shift operator
---------------------------------------------------------------------------------------------------
local function shift_snippet(node, alias, specifier)
    log.trace("shift_snippet:", ast.details(node))

    P.specifier = specifier
    P.attribute = G.attribute and ' ' .. G.attribute or ''
    P.classname = alias and ast.name(alias) or ast.name(node)
    P.indent    = string.rep(' ', vim.lsp.util.get_effective_tabstop())

    local records = labels_and_values(node, alias, G.enum.shift.value)
    local maxllen, maxvlen = max_lengths(records)

    local lines = {}

    table.insert(lines, apply('<specifier><attribute> std::ostream& operator<<(std::ostream& s, <classname> o)'))
    table.insert(lines, apply('{'))
    table.insert(lines, apply('<indent>switch(o)'))
    table.insert(lines, apply('<indent>{'))
    if G.keepindent then
        table.insert(lines, apply('<indent><indent>// clang-format off'))
    end

    for _,r in ipairs(records) do
        P.label     = r.label
        P.value     = r.value
        P.labelpad  = string.rep(' ', maxllen - string.len(r.label))
        P.valuepad  = string.rep(' ', maxvlen - string.len(r.value))
        table.insert(lines, apply('<indent><indent>case <label>:<labelpad> s << <value>;<valuepad> break;'))
    end

    if G.keepindent then
        table.insert(lines, apply('<indent><indent>// clang-format on'))
    end
    table.insert(lines, apply('<indent>};'))

    table.insert(lines, apply('<indent>return s;'))
    table.insert(lines, apply('}'))

    for _,l in ipairs(lines) do log.debug(l) end
    return lines
end

-- Optionally replicate the lines and generate multiple completion items that can be triggered by different labels.
local function shift_items(lines)
    return
    {
        { trigger = G.enum.shift.trigger, lines = lines },
        { trigger = string.match(lines[1], "^([%w]+)"), lines = lines }
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
--- Exported functions
---------------------------------------------------------------------------------------------------
local M = {}

local enclosing_node = nil
local preceding_node = nil
local typealias_node = nil

---------------------------------------------------------------------------------------------------
--- Generator will call this method to get kind of nodes that are of interest to each generator.
---------------------------------------------------------------------------------------------------
function M.digs()
    log.trace("digs:")
    return { "Enum" }
end

---------------------------------------------------------------------------------------------------
--- Generator will call this method before presenting a set of new candidate nodes
---------------------------------------------------------------------------------------------------
function M.reset()
    log.trace("reset:")
    enclosing_node = nil
    preceding_node = nil
    typealias_node = nil
end

---------------------------------------------------------------------------------------------------
--- Generator will call this method with a node, optional type alias and a node location
---------------------------------------------------------------------------------------------------
function M.visit(node, alias, location)
    -- We can generate conversion function for preceding enumeration node
    if location == ast.Precedes and ast.is_enum(node) then
        log.debug("visit:", "Accepted preceding node", ast.details(node))
        preceding_node = node
    end
    -- We capture enclosing class node since the specifier for the enum conversion depends on it
    if location == ast.Encloses and ast.is_class(node) then
        log.debug("visit:", "Accepted enclosing node", ast.details(node))
        enclosing_node = node
    end
    typealias_node = alias
end

---------------------------------------------------------------------------------------------------
--- Generator will call this method to check if the module can generate code
---------------------------------------------------------------------------------------------------
function M.available()
    return preceding_node ~= nil
end

-- Add elements of one table into another table
local function add_to(to, from)
    for _,item in ipairs(from) do
        table.insert(to, item)
    end
end
---------------------------------------------------------------------------------------------------
-- Generate from string functions for an enum nodes.
---------------------------------------------------------------------------------------------------
function M.generate(strict)
    log.trace("generate:", ast.details(preceding_node), ast.details(enclosing_node))

    local items = {}

    P.strict = strict
    if ast.is_enum(preceding_node) then
        if ast.is_class(enclosing_node) then
            add_to(items, to_string_member_items(preceding_node, typealias_node))
            add_to(items, cast_member_items(preceding_node, typealias_node))
            add_to(items, shift_member_items(preceding_node, typealias_node))
        else
            add_to(items, to_string_free_items(preceding_node, typealias_node))
            add_to(items, cast_free_items(preceding_node, typealias_node))
            add_to(items, shift_free_items(preceding_node, typealias_node))
        end
    end

    return items
end

---------------------------------------------------------------------------------------------------
--- Validator will call this method with a generated node.
---------------------------------------------------------------------------------------------------
function M.validate(node)
end

---------------------------------------------------------------------------------------------------
--- Info callback
---------------------------------------------------------------------------------------------------
local function combine(name, trigger)
    return name == trigger and name or name .. ' or ' .. trigger
end

function M.info()
    local info = {}
    table.insert(info, { combine(G.enum.to_string.name, G.enum.to_string.trigger), "Enum class to string converter" })

    local trigger = combine(G.enum.cast.name, G.enum.cast.trigger)
    if G.enum.cast.enum_cast.enabled then
        table.insert(info, { trigger, "Throwing version of enum class from string converter" })
    end
    if G.enum.cast.enum_cast_no_throw.enabled then
        table.insert(info, { trigger, "Non throwing version of enum class from string converter" })
    end
    if G.enum.cast.value_cast.enabled then
        table.insert(info, { trigger, "Throwing version of enum class from the underlying type converter" })
    end
    if G.enum.cast.value_cast_no_throw.enabled then
        table.insert(info, { trigger, "Non throwing version of enum class from the underlying type converter" })
    end

    table.insert(info, { G.enum.shift.trigger, "Enum class output stream shift operator" })

    return info
end

---------------------------------------------------------------------------------------------------
--- Initialization callback. Capture relevant parts of the configuration.
---------------------------------------------------------------------------------------------------
function M.setup(opts)
    G.keepindent = opts.keepindent
    G.attribute  = opts.attribute
    G.enum       = opts.enum
end

return M
