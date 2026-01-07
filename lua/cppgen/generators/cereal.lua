local ast = require('cppgen.ast')
local log = require('cppgen.log')
local utl = require('cppgen.generators.util')

---------------------------------------------------------------------------------------------------
-- Serializarion function generator.
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
                record.label = G.class.cereal.label(ast.name(node), record.field, utl.camelize(record.field))

                -- Null handling checks
                if G.class.cereal.nullcheck then
                    if (object) then
                        record.nullcheck = G.class.cereal.nullcheck(object .. '.' .. record.field, ast.type(n))
                    else
                        record.nullcheck = G.class.cereal.nullcheck(record.field, ast.type(n))
                    end
                end
                if G.class.cereal.nullvalue then
                    if (object) then
                        record.nullvalue = G.class.cereal.nullvalue(object .. '.' .. record.field, ast.type(n))
                    else
                        record.nullvalue = G.class.cereal.nullvalue(record.field, ast.type(n))
                    end
                end
                -- Custom code will trigger field skipping when it sets either label or value to nil
                if record.label ~= nil then
                    if (object) then
                        record.value = G.class.cereal.value(object .. '.' .. record.field, ast.type(n))
                    else
                        record.value = G.class.cereal.value(record.field, ast.type(n))
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
local function save_class_snippet(node, alias, specifier, member)
    log.debug("save_class_snippet:", ast.details(node))

    P.specifier            = specifier
    P.attribute            = G.attribute and ' ' .. G.attribute or ''
    P.classname            = alias and ast.name(alias) or ast.name(node)
    P.functionname         = G.class.cereal.name
    P.indent               = string.rep(' ', vim.lsp.util.get_effective_tabstop())

    local records          = member and class_labels_and_values(node) or class_labels_and_values(node, 'o')
    local maxllen, maxvlen = max_lengths(records)

    local lines            = {}

    if member then
        table.insert(lines, apply('<specifier> <attribute> void <functionname>(Archive& archive) const'))
    else
        table.insert(lines, apply('<specifier> <attribute> void <functionname>(Archive& archive, const <classname>& o)'))
    end
    table.insert(lines, apply('{'))
    if G.keepindent then
        table.insert(lines, apply('<indent>// clang-format off'))
    end

    --- Get straight - no null check code variation
    local function straight_code(l, last)
        table.insert(l, apply('<indent>archive(cereal::make_nvp("<label>",<labelpad> <value>));'))
    end

    --- Get skip-null code variation
    local function skipnull_code(l, last)
        table.insert(l, apply('<indent>if(!<nullcheck>) {'))
        table.insert(l, apply('<indent><indent>archive(cereal::make_nvp("<label>", <value>));'))
        table.insert(l, apply('<indent>}'))
    end

    --- Get show-null code variation
    local function shownull_code(l, last)
        table.insert(l, apply('<indent>if(!<nullcheck>) {'))
        table.insert(l, apply('<indent><indent>archive(cereal::make_nvp("<label>", <value>));'))
        table.insert(l, apply('<indent>} else {'))
        table.insert(l, apply('<indent><indent>archive(cereal::make_nvp("<label>", <nullvalue>));'))
        table.insert(l, apply('<indent>}'))
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
                shownull_code(lines, idx == #records)
            else
                skipnull_code(lines, idx == #records)
            end
        else
            straight_code(lines, idx == #records)
        end
        idx = idx + 1
    end

    if G.keepindent then
        table.insert(lines, apply('<indent>// clang-format on'))
    end
    table.insert(lines, apply('}'))

    for _, l in ipairs(lines) do log.debug(l) end
    return lines
end

-- Generate completion items
local function save_class_items(lines)
    return
    {
        { name = G.class.cereal.name, trigger = G.class.cereal.trigger, lines = lines }
    }
end

-- Generate serialization function snippet items for a class type node.
local function save_class_member_items(node, alias)
    log.trace("save_class_member_items:", ast.details(node))
    return save_class_items(save_class_snippet(node, alias, 'template <typename Archive>', true))
end

local function save_class_free_items(node, alias)
    log.trace("save_class_free_items:", ast.details(node))
    return save_class_items(save_class_snippet(node, alias, 'template <typename Archive>', false))
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
    return { "CXXRecord", "ClassTemplate" }
end

---------------------------------------------------------------------------------------------------
-- Generate completion items
---------------------------------------------------------------------------------------------------
function M.generate(node, alias, scope, acceptor)
    log.trace("generate:", ast.details(node))

    if G.class.cereal.enabled then
        if ast.is_class(node) then
            if scope == ast.Class then
                for _, item in ipairs(save_class_member_items(node, alias)) do
                    acceptor(item)
                end
            else
                for _, item in ipairs(save_class_free_items(node, alias)) do
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
    log.trace("info")
    local info = {}

    local function combine(name, trigger)
        return name == trigger and name or name .. ' or ' .. trigger
    end

    if G.class.cereal.enabled then
        table.insert(info,
            { combine(G.class.cereal.name, G.class.cereal.trigger), "Class serialization that uses cereal library" })
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
    log.trace("setup:", G)
end

return M
