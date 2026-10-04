# Fragment of `SettingsModule` — a settings group, the description of each of its
# settings, and the macro `@settings` that declares both.

"""
    SettingsGroup

The supertype of a settings group: a document that holds the settings of one part
of an editor, one cell for each setting. `@settings` declares one.
"""
abstract type SettingsGroup <: Document end

"""
    SettingDescription(name, label, text, type, default, values)

What a view, a check and a file know of one setting of a group:

- `name` — the field of the group that holds it;
- `label` — the words that name it in a view;
- `text` — one sentence that says what it does;
- `type` — `Bool`, `Int`, `Float64`, `Symbol` or `String`;
- `default` — its value in a new group;
- `values` — the values that it can take: a range for a number, a tuple of
  symbols for a choice, or `nothing` for any value of its type.
"""
struct SettingDescription
    name::Symbol
    label::String
    text::String
    type::Type
    default::Any
    values::Any
end

"""
    get_setting_descriptions(T) -> Tuple of SettingDescription

The description of each setting of the group type `T`, in the order of the
declaration. `@settings` adds the method.
"""
function get_setting_descriptions end

"""
    get_settings_name(T) -> String

The name of the group type `T` in a settings file: the name of the type without
`Settings`, in lower case with an underscore between words. `RenderSettings` is
`"render"`. `@settings` adds the method.
"""
function get_settings_name end

"""
    get_settings_group_type(group) -> Type

The type that the declaration of `group` names. `@document` gives a declared name
to the cell layout of a document, so the concrete type of a group is a variant of
that name, and a `Settings` keeps its groups by the declared name. `@settings`
adds the method.
"""
function get_settings_group_type end

"""
    find_setting_description(T, name) -> SettingDescription or nothing

The description of the setting `name` of the group type `T`, or `nothing` when
`T` has no such setting.
"""
function find_setting_description(T::Type, name::Symbol)
    for description in get_setting_descriptions(T)
        description.name === name && return description
    end
    nothing
end

"""
    convert_setting_value(description, value) -> value or nothing

`value` as a value of the setting that `description` describes: converted to its
type, and inside its values. A number from a text, such as `"3"`, converts. The
answer is `nothing` when `value` does not convert or is outside the values.
"""
function convert_setting_value(description::SettingDescription, value)
    converted = _convert_setting_type(description.type, value)
    converted === nothing && return nothing
    _is_allowed_setting_value(description.values, converted) ? converted : nothing
end

_is_allowed_setting_value(::Nothing, value) = true
_is_allowed_setting_value(values::AbstractRange, value) =
    first(values) <= value <= last(values)
_is_allowed_setting_value(values, value) = value in values

_convert_setting_type(::Type{Bool}, value::Bool) = value
_convert_setting_type(::Type{Int}, value::Integer) = Int(value)
_convert_setting_type(::Type{Int}, ::Bool) = nothing
_convert_setting_type(::Type{Int}, value::AbstractFloat) =
    isinteger(value) ? Int(value) : nothing
_convert_setting_type(::Type{Int}, value::AbstractString) = tryparse(Int, strip(value))
_convert_setting_type(::Type{Float64}, value::Real) =
    isfinite(value) ? Float64(value) : nothing
_convert_setting_type(::Type{Float64}, ::Bool) = nothing
_convert_setting_type(::Type{Float64}, value::AbstractString) =
    _convert_setting_type(Float64, something(tryparse(Float64, strip(value)), NaN))
_convert_setting_type(::Type{Symbol}, value::Symbol) = value
_convert_setting_type(::Type{Symbol}, value::AbstractString) =
    isempty(value) ? nothing : Symbol(value)
_convert_setting_type(::Type{String}, value::AbstractString) = String(value)
_convert_setting_type(::Type{String}, value::Symbol) = String(value)
_convert_setting_type(::Type, value) = nothing

# The types that a setting can have, by the name that a declaration writes.
const _SETTING_TYPES = (:Bool, :Int, :Float64, :Symbol, :String)

_throw_settings_error(text) = throw(ArgumentError("@settings: " * text))

# `"Label: text"` as the label and the text. The text starts with a capital.
function _split_setting_docstring(docstring::AbstractString, field::Symbol)
    parts = split(strip(docstring), ": "; limit = 2)
    length(parts) == 2 && !isempty(parts[1]) && !isempty(parts[2]) ||
        _throw_settings_error("the docstring of `$field` is `\"Label: text\"`, " *
                              "got $(repr(docstring))")
    String(strip(parts[1])), uppercasefirst(String(strip(parts[2])))
end

# `RenderSettings` → "render", `UndoHistorySettings` → "undo_history".
function _make_settings_name(name::Symbol)
    stem = String(name)
    endswith(stem, "Settings") && length(stem) > length("Settings") ||
        _throw_settings_error("the name of a group ends with `Settings`, got `$name`")
    stem = stem[1:end-length("Settings")]
    lowercase(replace(stem, r"(?<=[a-z0-9])(?=[A-Z])" => "_"))
end

# One line `name::Type = default` or `name::Type = default in values` of a
# declaration, with its docstring: the line for `@document`, and the expression
# that makes its `SettingDescription`.
function _parse_setting_line(line, docstring)
    (line isa Expr && line.head === :(=)) ||
        _throw_settings_error("each setting is `name::Type = default`, got `$line`")
    declaration, value = line.args
    (declaration isa Expr && declaration.head === :(::) &&
     declaration.args[1] isa Symbol) ||
        _throw_settings_error("each setting is `name::Type = default`, got `$line`")
    field, type = declaration.args
    type in _SETTING_TYPES ||
        _throw_settings_error("the type of `$field` is one of $(_SETTING_TYPES), " *
                              "got `$type`")
    field in (:selection, :mouse_target) &&
        _throw_settings_error("a setting can not be named `$field`, " *
                              "a document keeps its own `$field` under that name")
    docstring === nothing &&
        _throw_settings_error("the setting `$field` needs a docstring `\"Label: text\"`")
    label, text = _split_setting_docstring(docstring, field)
    values = nothing
    if value isa Expr && value.head === :call && length(value.args) == 3 &&
       value.args[1] === :in
        value, values = value.args[2], value.args[3]
    end
    description = :($SettingDescription($(QuoteNode(field)), $label, $text, $type,
                                        $value, $values))
    Expr(:(=), declaration, value), description
end

"""
    @settings struct NameSettings … end

Declare the settings group `NameSettings`. Each setting is a field with a
docstring `"Label: text"`, a type, a default and, for a number or a choice, the
values that it can take after `in`:

    @settings struct RenderSettings
        "Partial render: repaint only the parts of a window that changed."
        partial_render::Bool = true
        "Supersample: pixels in each direction for each pixel of a window."
        supersample::Int = 2 in 1:4
    end

The type of a setting is `Bool`, `Int`, `Float64`, `Symbol` or `String`. The
macro makes the group a document whose fields are cells, so
`RenderSettings(partial_render = true)` works, and adds
[`get_setting_descriptions`](@ref), [`get_settings_name`](@ref) and
[`get_settings_group_type`](@ref) for it.
"""
macro settings(definition)
    (definition isa Expr && definition.head === :struct) ||
        _throw_settings_error("expects a struct definition")
    definition.args[1] && _throw_settings_error("makes an immutable struct")
    name = definition.args[2]
    name isa Symbol ||
        _throw_settings_error("sets the supertype of `$name` itself: write `struct Name`")
    settings_name = _make_settings_name(name)
    definition.args[2] = Expr(:(<:), name, GlobalRef(SettingsModule, :SettingsGroup))
    body = Any[]
    descriptions = Any[]
    docstring = nothing
    for line in definition.args[3].args
        if line isa LineNumberNode
            push!(body, line)
        elseif line isa AbstractString
            docstring === nothing ||
                _throw_settings_error("two docstrings follow each other: $(repr(line))")
            docstring = line
        else
            field_line, description = _parse_setting_line(line, docstring)
            push!(body, field_line)
            push!(descriptions, description)
            docstring = nothing
        end
    end
    docstring === nothing ||
        _throw_settings_error("a docstring follows the last setting: $(repr(docstring))")
    isempty(descriptions) && _throw_settings_error("`$name` declares no setting")
    definition.args[3] = Expr(:block, body...)
    document = Expr(:macrocall, GlobalRef(DocumentModule, Symbol("@document")),
                    __source__, definition)
    esc(quote
        $document
        $SettingsModule.get_setting_descriptions(::Type{$name}) =
            $(Expr(:tuple, descriptions...))
        $SettingsModule.get_settings_name(::Type{$name}) = $settings_name
        $SettingsModule.get_settings_group_type(::$name) = $name
        $name
    end)
end
