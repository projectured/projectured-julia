# Fragment of `DataFramesModule`.
#
# The language of a filter, and the rows that pass the filters of a query. The
# text of a filter is read once into a condition, a callable struct, and the
# condition runs over the vector of the column, so a filter of ten million rows
# calls one compiled function for each row.
#
# The language, for a column whose element type is `T`:
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
# keeps every row, and the parse gives the reason, which the filter row shows.

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
(c::_OrderCondition)(value) = !ismissing(value) && c.order(value, c.bound)

struct _RangeCondition
    low::Float64
    high::Float64
end
(c::_RangeCondition)(value) = !ismissing(value) && c.low <= value <= c.high

# The text that a filter reads of a value: a string as it is, and anything else
# as it prints.
_get_filter_text(value::AbstractString) = value
_get_filter_text(value) = string(value)

# Whether `value` is one of `values`: by value for the values that the column
# type parsed, and by its printed text for the values of a type that it can not.
_is_filter_value_in(value, values::Vector{String}) = _get_filter_text(value) in values
_is_filter_value_in(value, values::Vector) = value in values

# ── The parse ────────────────────────────────────────────────────────────────

# The condition of `text` for a column of the element type `type`: `nothing`
# for an empty text, which keeps every row, and a `String`, the reason, for a
# text that does not parse.
function _parse_column_filter(text::AbstractString, type::Type)
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
        _is_number_type(T) || return "a comparison needs a column of numbers"
        bound = tryparse(Float64, strip(text[(length(prefix) + 1):end]))
        bound === nothing && return "the value after $(prefix) is no number"
        return _OrderCondition(order, bound)
    end
    range = match(r"^(\S+?)\s*\.\.\s*(\S+)$", text)
    if range !== nothing && _is_number_type(T)
        low, high = tryparse(Float64, range[1]), tryparse(Float64, range[2])
        (low === nothing || high === nothing) && return "a range is two numbers, such as 10..20"
        return _RangeCondition(low, high)
    end
    _MatchCondition(_make_contains_regex(text))
end

_is_number_type(T::Type) = T <: Real && !(T <: Bool)

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

# `= a, b` or `!= a, b`: the values that the column type parses, else their texts.
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

# The pattern of the column names: a predicate of a name, which keeps every name
# for an empty text, or a `String`, the reason, for a text that does not parse.
function _parse_name_pattern(text::AbstractString)
    text = strip(text)
    isempty(text) && return _ -> true
    condition = _is_regular_expression(text) ? _parse_regular_expression(text) :
                                               _MatchCondition(_make_contains_regex(text))
    condition isa String && return condition
    name -> condition(name)
end

# ── The rows that pass ───────────────────────────────────────────────────────

# The rows of `frame` that pass every filter of `query`, in the order of the
# frame. A filter that names no column of the frame, or whose text does not
# parse, keeps every row.
function _compute_kept_rows(frame, query)
    keep = trues(nrow(frame))
    columns = Set(names(frame))
    for filter in query.column_filters
        filter.column in columns || continue
        column = frame[!, filter.column]
        condition = _parse_column_filter(filter.text, eltype(column))
        (condition === nothing || condition isa String) && continue
        _apply_filter_condition!(keep, column, condition)
    end
    findall(keep)
end

# One condition over one column, compiled for both types.
function _apply_filter_condition!(keep::BitVector, column::AbstractVector, condition)
    for i in 1:length(column)
        keep[i] && (keep[i] = condition(column[i]))
    end
    keep
end
