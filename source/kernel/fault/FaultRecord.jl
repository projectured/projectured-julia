# Fragment of `FaultModule` — one fault as a value, and the key that decides
# when two faults are the same one.

"""
    FaultRecord

One fault, as a plain value. It is not a `Document`: the kernel holds no
concrete document, and a record is what a document above it shows.

- `key` — what makes two faults the same one. See [`compute_fault_key`](@ref).
- `site` — which barrier caught it: `:print`, `:read`, `:map`, `:evaluate`,
  `:device` or `:tool`.
- `origin` — the name of the type or the function whose code failed.
- `exception_type` — the name of the exception type.
- `message` — the message of the FIRST occurrence, formatted once.
- `traceback` — the traceback of the first occurrence, truncated.
- `first_reference` — where in the document the first occurrence was, or
  `nothing` where the site knows no place.
- `first_time` — when the first occurrence was, in seconds.
- `count` — how many occurrences the key has taken.

# Example

    record = make_fault_record(:print; origin = JsonToSyntax, reference, exception, traceback)

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
    compute_fault_key(site, origin, exception_type) -> UInt64

What makes two faults the same one.

**The key holds no reference and no message, and that decision carries the
design.** A chain bounds how far a fault spreads downward — four stages at most.
Nothing bounds how far it spreads sideways: one bug in one projection fails at
every leaf of one kind, which in a large document is thousands of nodes. With
the reference in the key those become thousands of keys, the store fills, and
the report is a wall of near-identical lines. Without it they become one record
with a count of three thousand and one place kept as an example.

The message is left out for the same reason. Two `BoundsError`s at index 4 and
index 7 carry different messages and the same bug.

# Example

    key = compute_fault_key(:print, :JsonToSyntax, :BoundsError)

See also [`FaultRecord`](@ref).
"""
compute_fault_key(site::Symbol, origin::Symbol, exception_type::Symbol) =
    hash((site, origin, exception_type))

"""
    format_fault_message(exception; maximum_length = 400) -> String

The message of `exception`, as one line, truncated to `maximum_length`
characters.

It never throws. An exception whose own `showerror` fails answers its type name,
because a report that can not be written is worse than a report that is short.
"""
function format_fault_message(exception; maximum_length::Integer = 400)
    text = try
        sprint(showerror, exception)
    catch
        string(nameof(typeof(exception)))
    end
    text = replace(text, '\n' => ' ')
    length(text) > maximum_length ? first(text, maximum_length) * "…" : text
end

"""
    format_fault_traceback(exception, traceback; maximum_lines = 12) -> String

The traceback of `exception`, truncated to the frames nearest the failure.

It never throws, and it answers `""` where no traceback was taken. Formatting a
traceback is expensive, so a barrier takes one only for a key the store has not
seen.
"""
function format_fault_traceback(exception, traceback; maximum_lines::Integer = 12)
    traceback === nothing && return ""
    text = try
        sprint(showerror, exception, traceback)
    catch
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

    record = make_fault_record(:read; origin = p.inner, exception, traceback = catch_backtrace())

See also [`record_fault!`](@ref), which makes one only when the key is new.
"""
function make_fault_record(site::Symbol; origin, reference = nothing, exception,
                           traceback = nothing)
    origin_name = get_fault_origin_name(origin)
    exception_name = get_fault_exception_name(exception)
    FaultRecord(compute_fault_key(site, origin_name, exception_name),
                site, origin_name, exception_name,
                format_fault_message(exception),
                format_fault_traceback(exception, traceback),
                reference, time(), 1)
end

"""
    get_fault_origin_name(origin) -> Symbol

The name to record for the thing that failed.
"""
get_fault_origin_name(origin::Symbol) = origin
get_fault_origin_name(origin::Type) = nameof(origin)
get_fault_origin_name(origin::Nothing) = :unknown
get_fault_origin_name(origin) = nameof(typeof(origin))

"""
    get_fault_exception_name(exception) -> Symbol

The name to record for the exception.
"""
get_fault_exception_name(exception) = nameof(typeof(exception))
