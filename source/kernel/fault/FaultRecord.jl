# Fragment of `FaultModule` — one fault as a value, and the key that decides
# when two faults are the same one.

"""
    FaultRecord

One fault, as a plain value. It is not a `Document`, because this layer sits
below the layer that defines documents. A record is what a document above it
shows.

- `key` — what makes two faults the same one: the site, the origin and the
  exception type.
- `site` — which barrier caught it, for example `:print`, `:device` or `:tool`.
- `origin` — the name of the type or the function whose code failed.
- `exception_type` — the name of the exception type.
- `message` — the message of the first occurrence, formatted once.
- `traceback` — the traceback of the first occurrence, truncated.
- `first_reference` — where in the document the first occurrence was, or
  `nothing` where the site knows no place.
- `first_time` — when the first occurrence was, in seconds.
- `count` — how many occurrences the key has taken.

# Example

    record = make_fault_record(:print; origin = JsonToSyntax, reference,
                               exception, traceback)

See also [`record_fault!`](@ref), which is what a barrier calls.
"""
struct FaultRecord
    key::UInt64
    site::Symbol
    origin::Symbol
    exception_type::Symbol
    message::String
    traceback::String
    first_reference::Any
    first_time::Float64
    count::Int
end

"""
    _compute_fault_key(site, origin, exception_type) -> UInt64

What makes two faults the same one.

**The key holds no reference and no message, and that decision carries the
design.** A chain bounds how far a fault spreads downward, to one record per
stage. Nothing bounds how far it spreads sideways: one bug in one projection
fails at every leaf of one kind, which in a large document is thousands of
nodes. With the reference in the key those become thousands of keys, the store
fills, and the report is thousands of lines that differ only in the place.
Without it they become one record with a count of three thousand and one place
kept as an example.

The message is left out for the same reason. Two `BoundsError`s at index 4 and
index 7 carry different messages and the same bug.

# Example

    key = _compute_fault_key(:print, :JsonToSyntax, :BoundsError)

See also [`FaultRecord`](@ref).
"""
_compute_fault_key(site::Symbol, origin::Symbol, exception_type::Symbol) =
    hash((site, origin, exception_type))

"""
    _format_fault_message(exception; maximum_length = 400) -> String

The message of `exception`, as one line, truncated to `maximum_length`
characters.

It never throws an ordinary exception. An exception whose own `showerror` fails
answers its type name, because a report that can not be written is worse than a
report that is short. An exception that means stop goes on.
"""
function _format_fault_message(exception; maximum_length::Integer = 400)
    text = try
        sprint(showerror, exception)
    catch failure
        is_passthrough_exception(failure) && rethrow()
        string(nameof(typeof(exception)))
    end
    text = replace(text, '\n' => ' ')
    length(text) > maximum_length ? first(text, maximum_length) * "…" : text
end

"""
    _format_fault_traceback(exception, traceback; maximum_lines = 12) -> String

The traceback of `exception`, truncated to the frames nearest the failure.

It never throws an ordinary exception, and it answers `""` where no traceback was
taken. Formatting a
traceback is expensive, so `record_fault!` formats one only for a key the store
has not seen.
"""
function _format_fault_traceback(exception, traceback; maximum_lines::Integer = 12)
    traceback === nothing && return ""
    text = try
        sprint(showerror, exception, traceback)
    catch failure
        is_passthrough_exception(failure) && rethrow()
        return ""
    end
    lines = split(text, '\n')
    length(lines) <= maximum_lines && return text
    join(lines[1:maximum_lines], '\n') * "\n  …"
end

"""
    make_fault_record(site; origin, reference = nothing, exception,
                      traceback = nothing) -> FaultRecord

One fault as a value, with its key computed and its message formatted.

`origin` is what failed. Pass the projection, the type, the backend or a
`Symbol`; the name is taken from whichever it is.

# Example

    record = make_fault_record(:read; origin = p.inner, exception,
                               traceback = catch_backtrace())

See also [`record_fault!`](@ref), which makes one only when the key is new.
"""
function make_fault_record(site::Symbol; origin, reference = nothing, exception,
                           traceback = nothing)
    origin_name = _get_fault_origin_name(origin)
    exception_name = _get_fault_exception_name(exception)
    FaultRecord(_compute_fault_key(site, origin_name, exception_name),
                site, origin_name, exception_name,
                _format_fault_message(exception),
                _format_fault_traceback(exception, traceback),
                reference, time(), 1)
end

"""
    _get_fault_origin_name(origin) -> Symbol

The name to record for the thing that failed.
"""
_get_fault_origin_name(origin::Symbol) = origin
_get_fault_origin_name(origin::Type) =
    origin isa DataType || origin isa UnionAll ? nameof(origin) : Symbol(string(origin))
_get_fault_origin_name(origin::Nothing) = :unknown
_get_fault_origin_name(origin) = nameof(typeof(origin))

"""
    _get_fault_exception_name(exception) -> Symbol

The name to record for the exception.
"""
_get_fault_exception_name(exception) = nameof(typeof(exception))
