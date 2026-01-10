local log = require('cppgen.log')

---------------------------------------------------------------------------------------------------
--- Options module. Provides default configuration options and a mechanism to override them.
---------------------------------------------------------------------------------------------------
local M = {}

---------------------------------------------------------------------------------------------------
--- Default options. Should be merged with user options.
---------------------------------------------------------------------------------------------------
M.merge = function(default, user)
    for k, v in pairs(user) do
        if (type(v) == "table") and (type(default[k] or false) == "table") then
            M.merge(default[k], user[k])
        else
            default[k] = v
        end
    end
    return default
end

---------------------------------------------------------------------------------------------------
--- Default options. Should be merged with user options.
---------------------------------------------------------------------------------------------------
M.default = {
    -- Logging options.
    log = {
        -- Name of the log file.
        plugin = 'cppgen',
        -- Log level
        level = 'info',
        -- Do not print to console.
        use_console = false,
        -- Truncate log file on start.
        truncate = false
    },

    -- Generated code can be decorated using an attribute. Set to empty string to disable.
    attribute = '[[cppgen::auto]]',

    -- Add clang-format on/off guards around parts of generated code.
    keepindent = true,

    -- Batch mode code generation. Will attempt generate code for the whole file
    batchmode = {
        -- Disabled by default.
        enabled = false,

        -- Visually differentiate in-context and batch mode code snippets for a given trigger
        trigger = function(trig)
            return trig .. '!'
        end,
    },

    -- Class type snippet generator.
    class = {
        -- Output stream shift operator.
        shift = {
            -- Enabled by default.
            enabled   = true,

            -- String printed before any fields are printed.
            preamble  = function(classname)
                return '[' .. classname .. ']='
            end,
            -- Label part of the field.
            label     = function(classname, fieldname, camelized)
                return camelized .. ': '
            end,
            -- Value part of the field.
            value     = function(fieldref, type)
                return fieldref
            end,
            -- Separator between fields.
            separator = "' '",
            -- Completion trigger. Will also use the first word of the function definition line.
            trigger   = "shift"
        },

        -- JSON serialization
        json = {
            -- Enabled by default.
            enabled = true,

            -- Field will be skipped if this function returns nil.
            label = function(classname, fieldname, camelized)
                return camelized
            end,
            value = function(fieldref, type)
                return fieldref
            end,

            -- Check for null field. To disable null check, this function should return nil.
            nullcheck = function(fieldref, type)
                return 'isnull(' .. fieldref .. ')'
            end,
            -- If the null check succedes, this is the value that will be serialized. Return nil to skip null field serialization.
            nullvalue = function(fieldref, type)
                return 'nullptr'
            end,

            -- Name of the conversion function. Also used as a completion trigger.
            name = "to_json",

            -- Additional completion trigger if present.
            trigger = "json"
        },

        -- Serialization using cereal library.
        cereal = {
            -- Enabled by default.
            enabled = true,

            -- Field will be skipped if this function returns nil.
            label = function(classname, fieldname, camelized)
                return camelized
            end,
            value = function(fieldref, type)
                return fieldref
            end,
            -- To disable null check, this function should return nil.
            nullcheck = function(fieldref, type)
                return nil
            end,
            -- If the null check succedes, this is the value that will be serialized. Return nil to skip the serialization.
            nullvalue = function(fieldref, type)
                return 'nullptr'
            end,
            -- Name of the conversion function. Also used as a completion trigger.
            name = "save",
            -- Additional completion trigger if present.
            trigger = "arch"
        },
    },

    -- Enum type snippet generator.
    enum = {
        -- Output stream shift operator.
        shift = {
            -- Enabled by default.
            enabled = true,

            -- Given an enumerator and optional value, return the string to print.
            value = function(enumerator, value)
                if (value) then
                    return '"' .. value .. '(' .. enumerator .. ')' .. '"'
                else
                    return '"' .. enumerator .. '"'
                end
            end,
            --  Expression for the default case. If nil, no default case will be generated.
            default = function(classname, value)
                return 'std::to_string(static_cast<std::underlying_type_t<' ..
                    classname .. '>>(' .. value .. ')) + "(Invalid ' .. classname .. ')"'
            end,
            -- May use to_string function
            to_string = false,
            -- Completion trigger. Will also use the first word of the function definition line.
            trigger = "shift"
        },

        -- To string conversion function: std::string to_string(enum e).
        to_string = {
            -- Enabled by default.
            enabled = true,

            -- Given an enumerator and optional value, return the string to print.
            value = function(enumerator, value)
                if (value) then
                    return '"' .. value .. '(' .. enumerator .. ')' .. '"'
                else
                    return '"' .. enumerator .. '"'
                end
            end,
            --  Expression for the default case. If nil, no default case will be generated.
            default = function(classname, value)
                return 'std::to_string(static_cast<std::underlying_type_t<' ..
                    classname .. '>>(' .. value .. ')) + "(Invalid ' .. classname .. ')"'
            end,
            -- Name of the conversion function. Also used as a completion trigger.
            name = "to_string",
            -- Additional completion trigger if present.
            trigger = "to_string"
        },

        -- Enum cast functions. Conversions from various types into enum.
        cast = {
            -- From string conversion. Specializations of: template <typename T> T enum_cast(std::string_view v).
            from_string = {
                -- Enabled by default.
                enabled = true,

                -- Given an enumerator and optional value, return the string to compare against.
                value = function(enumerator, value)
                    return enumerator
                end,
                -- In rare cases we want to compare against the value instead - stripped if character constant.
                --[[
                value = function(enumerator, value)
                    return string.gsub(value, "'", '')
                end,
                --]]

                -- Exception expression thrown if conversion fails
                exception = function(classname, value)
                    return 'std::out_of_range("Value " + std::string(' ..
                        value .. ') + " is outside of ' .. classname .. ' enumeration range.")'
                end,
            },
            -- No-throw version of from string conversion. Specializations of: template <typename T> T enum_cast(std::string_view v, E& error).
            from_string_no_throw = {
                -- Enabled by default.
                enabled = true,

                -- Given an enumerator and optional value, return the string to compare against.
                value = function(enumerator, value)
                    return enumerator
                end,
                -- In rare cases we want to compare against the value instead - stripped if character constant.
                --[[
                value = function(enumerator, value)
                    return string.gsub(value, "'", '')
                end,
                --]]

                -- Error type that will be passed from the conversion function.
                errortype = 'std::string',

                -- Error expression returned if conversion fails.
                error = function(classname, value)
                    return '"Value " + std::string(' ..
                        value .. ') + " is outside of ' .. classname .. ' enumeration range."'
                end,
            },
            -- From integer conversion. Specializations of: template <typename T> T enum_cast(int v).
            from_integer = {
                -- Enabled by default.
                enabled = true,

                -- Exception expression thrown if conversion fails.
                exception = function(classname, value)
                    return 'std::out_of_range("Value " + std::to_string(' ..
                        value .. ') + " is outside of ' .. classname .. ' enumeration range.")'
                end,
            },
            -- No-throw version of from integer conversion. Specializations of: template <typename T> T enum_cast(int v, E& error).
            from_integer_no_throw = {
                -- Enabled by default.
                enabled = true,

                -- Error type that will be passed from the conversion function.
                errortype = 'std::string',

                -- Exception expression thrown if conversion fails.
                error = function(classname, value)
                    return '"Value " + std::to_string(' ..
                        value .. ') + " is outside of ' .. classname .. ' enumeration range."'
                end,
            },
            -- Name of the conversion function. Also used as a completion trigger.
            name = "enum_cast",
            -- Additional completion trigger if present.
            trigger = "enum_cast",
        },

        -- Terse and verbose JSON serialization
        json = {
            -- Enabled by default.
            enabled = true,

            terse = {
                -- Given an enumerator and optional value, return the desired string.
                value = function(enumerator, value)
                    return (enumerator == 'Null' or enumerator == 'null' or enumerator == 'nullvalue') and 'nullptr' or
                        value
                end,
                --  Expression for the default case. If nil, no default case will be generated.
                default = function(classname, value)
                    return 'static_cast<std::underlying_type_t<' .. classname .. '>>(' .. value .. ')'
                end,
            },
            verbose = {
                -- Given an enumerator and optional value, return the desired string.
                value = function(enumerator, value)
                    if enumerator == 'Null' or enumerator == 'null' or enumerator == 'nullvalue' then
                        return 'nullptr'
                    end
                    if (value) then
                        return '"' .. value .. '(' .. enumerator .. ')' .. '"'
                    else
                        return enumerator
                    end
                end,
                --  Expression for the default case. If nil, no default case will be generated.
                default = function(classname, value)
                    return 'std::to_string(static_cast<std::underlying_type_t<' ..
                        classname .. '>>(' .. value .. ')) + "(Invalid ' .. classname .. ')"'
                end,
            },

            -- Name of the conversion function. Also used as a completion trigger.
            name = "to_json",

            -- Additional completion trigger if present.
            trigger = "json"
        },

        -- Switch statement generator.
        switch = {
            -- Enabled by default.
            enabled = true,

            -- Part that will go between case and break.
            placeholder = function(classname, value)
                return '// ' .. classname .. '::' .. value
            end,
            --  Expression for the default case. If nil, no default case will be generated.
            default = function(classname, value)
                return '// "Value " + std::to_string(' ..
                    value .. ') + " is outside of ' .. classname .. ' enumeration range."'
            end,
            -- Completion trigger.
            trigger = "case"
        },
    },
}

return M
