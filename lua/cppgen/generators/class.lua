local ast = require('cppgen.ast')
local log = require('cppgen.log')
local utl = require('cppgen.generators.util')

---------------------------------------------------------------------------------------------------
-- Class function generators.
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
local function labels_and_values(node, object)
    local records = {}
    ast.visit_children(node,
        function(n)
            if n.kind == "Field" then
                local record = {}
                record.field = ast.name(n)
                record.label = G.class.shift.label(ast.name(node), record.field, utl.camelize(record.field))
                record.value = G.class.shift.value(object .. '.' .. record.field, ast.type(n))
                table.insert(records, record)
            end
            return true
        end
    )
    return records
end

-- Generate output stream shift operator for a class type node.
local function shift_snippet(node, alias, specifier)
    log.debug("shift_snippet:", ast.details(node))

    P.specifier = specifier
    P.attribute = G.attribute and ' ' .. G.attribute or ''
    P.classname = alias and ast.name(alias) or ast.name(node)
    P.separator = G.class.shift.separator
    P.indent    = string.rep(' ', vim.lsp.util.get_effective_tabstop())

    local records = labels_and_values(node, 'o')
    local maxllen, maxvlen = max_lengths(records)

    local lines = {}

    table.insert(lines, apply('<specifier><attribute> std::ostream& operator<<(std::ostream& s, const <classname>& o)'))
    table.insert(lines, apply('{'))
    if G.keepindent then
        table.insert(lines, apply('<indent>// clang-format off'))
    end

    if G.class.shift.preamble then
        table.insert(lines, apply('<indent>s << "' .. G.class.shift.preamble(P.classname) .. '";'))
    end

    local idx = 1
    for _,r in ipairs(records) do
        P.fieldname = r.field
        P.label     = r.label
        P.value     = r.value
        P.labelpad  = string.rep(' ', maxllen - string.len(r.label))
        P.valuepad  = string.rep(' ', maxvlen - string.len(r.value))
        if idx == #records then
            table.insert(lines, apply('<indent>s << "<label>"<labelpad> << <value>;'))
        else
            table.insert(lines, apply('<indent>s << "<label>"<labelpad> << <value><valuepad> << <separator>;'))
        end
        idx = idx + 1
    end

    if G.keepindent then
        table.insert(lines, apply('<indent>// clang-format on'))
    end
    table.insert(lines, apply('<indent>return s;'))
    table.insert(lines, apply('}'))

    for _,l in ipairs(lines) do log.debug(l) end
    return lines
end

-- Duplicate the lines and generate two completion items that can be triggered by different labels.
local function shift_items(lines)
    return
    {
        { trigger = G.class.shift.trigger, lines = lines },
        { trigger = string.match(lines[1], "^([%w]+)"), lines = lines }
    }
end

-- Generate output stream shift member operator completion item for a class type node.
local function shift_member_items(node, alias)
    log.trace("shift_member_items:", ast.details(node))
    return shift_items(shift_snippet(node, alias, 'friend'))
end

-- Generate output stream shift free operator completion item for a class type node.
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
    log.trace("digs")
    return { "Record", "CXXRecord", "ClassTemplate" }
end

---------------------------------------------------------------------------------------------------
-- Generate plain output stream shift operator for a class node.
---------------------------------------------------------------------------------------------------
function M.generate(node, alias, scope, acceptor)
    log.trace("generate:", ast.details(node))
    if ast.is_class(node) then
        if scope == ast.Class then
            for _,item in ipairs(shift_member_items(node, alias)) do
                acceptor(item)
            end
        else
            for _,item in ipairs(shift_free_items(node, alias)) do
                acceptor(item)
            end
        end
    end
end

---------------------------------------------------------------------------------------------------
--- Info callback
---------------------------------------------------------------------------------------------------
function M.info()
    log.trace("info")
    return {
        { G.class.shift.trigger or 'friend/inline',  "Class output stream shift operator" }
    }
end

---------------------------------------------------------------------------------------------------
--- Initialization callback. Capture relevant parts of the configuration.
---------------------------------------------------------------------------------------------------
function M.setup(opts)
    log.trace("setup")
    G.keepindent = opts.keepindent
    G.attribute  = opts.attribute
    G.class      = opts.class
    log.trace("setup:", G)
end

return M
