# Fragment of `ArrangementModule` — the language of a filter: the text of the
# field under the header of a column, and the value of a condition of the
# operator `:matches`. A text is read once into a condition, a callable struct,
# so a filter of many items calls one compiled function for each item.
#
# The language, for values of the type `T`:
#
#     abc          the printed value contains `abc`, in any case
#     /re/         the printed value matches the regular expression `re`
#     = a, b       the value is `a` or `b`; a value with a comma is written in quotes
#     != a         the value is not `a`
#     > 30         a comparison, also `>=`, `<` and `<=`, for a `T` that is a number
#     10..20       the value is between 10 and 20, both included, for a number
#     missing      the value is `missing`
#     !missing     the value is not `missing`
#
# A value that is `missing` passes only `missing`. A text that does not parse
# keeps every value, and the parse gives the reason, which the field shows. For
# the type `Any`, the values of one place can be of any type: a comparison and a
# range hold only for a value that is a number, and `= a, b` compares the text
# of a value.

# ── The conditions ───────────────────────────────────────────────────────────

struct _MissingCondition
    is_missing::Bool
end
(c::_MissingCondition)(value) = ismissing(value) == c.is_missing

struct _MatchCondition
    regex::Regex
end
(c::_MatchCondition)(value) = !ismissing(value) && occursin(c.regex, _get_filter_text(value))

struct _EqualCondition{T}
    values::Vector{T}
end
(c::_EqualCondition)(value) = !ismissing(value) && _is_filter_value_in(value, c.values)

struct _NotEqualCondition{T}
    values::Vector{T}
end
(c::_NotEqualCondition)(value) = !ismissing(value) && !_is_filter_value_in(value, c.values)

struct _OrderCondition{F}
    order::F
    bound::Float64
end
(c::_OrderCondition)(value) = !ismissing(value) && _is_number_value(value) && c.order(value, c.bound)

struct _RangeCondition
    low::Float64
    high::Float64
end
(c::_RangeCondition)(value) = !ismissing(value) && _is_number_value(value) && c.low <= value <= c.high

# The text that a filter reads of a value: a string as it is, and anything else
# as it prints.
_get_filter_text(value::AbstractString) = value
_get_filter_text(value) = string(value)

# Whether `value` is one of `values`: by value for the values that the type
# parsed, and by its printed text for the values of a type that it can not.
_is_filter_value_in(value, values::Vector{String}) = _get_filter_text(value) in values
_is_filter_value_in(value, values::Vector) = value in values

_is_number_type(T::Type) = T <: Real && !(T <: Bool)
_is_number_value(value) = value isa Real && !(value isa Bool)

# Whether the type `T` takes a comparison and a range: a type of numbers, or `Any`,
# whose values each say if they are numbers.
_has_number_forms(T::Type) = T === Any || _is_number_type(T)

# ── The parse ────────────────────────────────────────────────────────────────

"""
    parse_filter_text(text, type = Any) -> condition, nothing or String

The condition of the filter text `text` for values of the type `type`: a
callable that gives whether a value passes, `nothing` for an empty text, which
keeps every value, or a `String`, the reason, for a text that does not parse.
The language: `abc` (the printed value contains it, in any case), `/re/`,
`= a, b`, `!= a`, `> 30`, `>=`, `<`, `<=`, `10..20`, `missing` and `!missing`.

Use it to read the text of a filter field, or the value of a condition of the
operator `:matches`, as a test of a value.

# Example

    condition = parse_filter_text("= failed, error")
    condition("failed")      # true

See also `is_condition_holding`, `make_value_list_text`.
"""
function parse_filter_text(text::AbstractString, type::Type = Any)
    text = strip(text)
    isempty(text) && return nothing
    text == "missing" && return _MissingCondition(true)
    text == "!missing" && return _MissingCondition(false)
    T = nonmissingtype(type)
    _is_regular_expression(text) && return _parse_regular_expression(text)
    startswith(text, "!=") && return _parse_equal_filter(text[3:end], T; negated = true)
    startswith(text, "=") && return _parse_equal_filter(text[2:end], T)
    for (prefix, order) in ((">=", >=), ("<=", <=), (">", >), ("<", <))
        startswith(text, prefix) || continue
        _has_number_forms(T) || return "a comparison needs a column of numbers"
        bound = tryparse(Float64, strip(text[(length(prefix) + 1):end]))
        bound === nothing && return "the value after $(prefix) is no number"
        return _OrderCondition(order, bound)
    end
    range = match(r"^(\S+?)\s*\.\.\s*(\S+)$", text)
    if range !== nothing && _has_number_forms(T)
        low, high = tryparse(Float64, range[1]), tryparse(Float64, range[2])
        (low === nothing || high === nothing) && return "a range is two numbers, such as 10..20"
        return _RangeCondition(low, high)
    end
    _MatchCondition(_make_contains_regex(text))
end

_is_regular_expression(text::AbstractString) =
    length(text) >= 2 && startswith(text, "/") && endswith(text, "/")

function _parse_regular_expression(text::AbstractString)
    try
        _MatchCondition(Regex(text[2:prevind(text, lastindex(text))]))
    catch exception
        "the regular expression does not parse: " * sprint(showerror, exception)
    end
end

# A regular expression that matches `text` as it is, in any case.
_make_contains_regex(text::AbstractString) =
    Regex("\\Q" * replace(text, "\\E" => "\\E\\\\E\\Q") * "\\E", "i")

# `= a, b` or `!= a, b`: the values that the type parses, else their texts.
function _parse_equal_filter(text::AbstractString, T::Type; negated::Bool = false)
    values = _split_filter_values(text)
    isempty(values) && return "name a value after the ="
    parsed = if _is_number_type(T)
        numbers = [tryparse(Float64, value) for value in values]
        any(isnothing, numbers) && return "a value of a column of numbers is a number"
        Float64[number for number in numbers]
    elseif T <: Bool
        flags = [tryparse(Bool, value) for value in values]
        any(isnothing, flags) && return "a value of a column of true and false is true or false"
        Bool[flag for flag in flags]
    else
        values
    end
    negated ? _NotEqualCondition(parsed) : _EqualCondition(parsed)
end

# The values of a list separated by commas, each without the spaces around it; a
# value in double quotes keeps its commas.
function _split_filter_values(text::AbstractString)
    values = String[]
    current = IOBuffer()
    quoted = false
    for char in text
        if char == '"'
            quoted = !quoted
        elseif char == ',' && !quoted
            push!(values, strip(String(take!(current))))
        else
            print(current, char)
        end
    end
    push!(values, strip(String(take!(current))))
    String[value for value in values if !isempty(value)]
end

"""
    parse_name_pattern(text) -> predicate or String

The pattern of names `text` as a predicate of a name: a name passes when it
contains the text, in any case, or matches `/re/`. An empty text keeps every
name, and a text that does not parse gives a `String`, the reason.

Use it to read the field that chooses the columns of a table by their names.

# Example

    keep = parse_name_pattern("delay")
    keep("queue_delay")      # true

See also `parse_filter_text`.
"""
function parse_name_pattern(text::AbstractString)
    text = strip(text)
    isempty(text) && return _ -> true
    condition = _is_regular_expression(text) ? _parse_regular_expression(text) :
                                               _MatchCondition(_make_contains_regex(text))
    condition isa String && return condition
    name -> condition(name)
end

# ── A list of values ─────────────────────────────────────────────────────────

# The text of `value` in a list of a filter: in double quotes when it holds a
# comma or starts or ends with a space, so the list reads it back as one value.
function _get_listed_value_text(value)
    text = _get_filter_text(value)
    (occursin(',', text) || text != strip(text)) ? "\"" * text * "\"" : text
end

"""
    make_value_list_text(values, ticked) -> String or nothing

The filter text that keeps the values of `values` whose place in `ticked` is
`true`: `= a, b`, with a value that holds a comma in double quotes; the empty
text when every value is ticked; `nothing` when no value is.

Use it to write the choice of a list of the values of a column as its filter.

# Example

    make_value_list_text(["done", "failed", "error"], [false, true, true])   # "= failed, error"

See also `is_value_listed`, `parse_filter_text`.
"""
function make_value_list_text(values::AbstractVector, ticked::AbstractVector{Bool})
    any(ticked) || return nothing
    all(ticked) && return ""
    "= " * join((_get_listed_value_text(value) for (value, on) in zip(values, ticked) if on), ", ")
end

"""
    is_value_listed(text, value, type = Any) -> Bool

Whether the filter text `text` keeps `value` as a list keeps it: a list `= a, b`
keeps its values, and any other text keeps every value.

Use it to tick the boxes of a list of the values of a column when it opens.

# Example

    is_value_listed("= failed, error", "done")   # false

See also `make_value_list_text`.
"""
function is_value_listed(text::AbstractString, value, type::Type = Any)
    condition = parse_filter_text(text, type)
    condition isa _EqualCondition ? condition(value) : true
end
