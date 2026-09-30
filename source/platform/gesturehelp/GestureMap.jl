# Fragment of `GestureHelpModule` — `GestureRow` and the map that collects every
# gesture a projection offers, so the help view and the command palette can
# read one table.

struct GestureRow
    gesture::String
    description::String
    domain::String
    operation::Any
end

"""
    GestureMap(rows = GestureRow[])

A document wrapping the gesture rows for display. Read-only: it carries the
`selection` field the `Document` contract requires, but no editing gestures of
its own.
"""
@document struct GestureMap
    rows::Any = GestureRow[]
end

# An intent with no pattern has no keystroke to render, so its gesture column is
# empty. The intent's `gesture` field carries the binding's pattern, which is what
# a listing renders — the input that *would* fire it.
_row_gesture(pattern) = pattern === nothing ? "" : describe_gesture_pattern(pattern)

"""
    make_gesture_row(intent) -> GestureRow

One row for one collected `Intent`. Nothing is evaluated here: the operation was
built by the binding that owns it, against the document that owns it, and rooted
by every stage on the way back.
"""
make_gesture_row(intent::Intent) =
    GestureRow(_row_gesture(intent.gesture), intent.description, intent.domain,
               intent.operation)

"""
    collect_gesture_rows(collected) -> Vector{GestureRow}

The rows for a [`CollectedIntentsOperation`](@ref), in collection order — which is
chain order, so the innermost document's rules come first. A chain that visits one
document from more than one stage offers it more than once; the same
(domain, description) is kept only the first time.

`nothing` (a reader that had nothing to say) yields no rows.
"""
function collect_gesture_rows(collected::CollectedIntentsOperation)
    rows = GestureRow[]
    seen = Set{Tuple{String,String}}()
    for intent in collected.intents
        key = (intent.domain, intent.description)
        key in seen && continue
        push!(seen, key)
        push!(rows, make_gesture_row(intent))
    end
    rows
end
collect_gesture_rows(::Nothing) = GestureRow[]
collect_gesture_rows(::Any) = GestureRow[]

"""
    make_gesture_map(collected) -> GestureMap

The help window's document for a collection.
"""
make_gesture_map(collected) = GestureMap(collect_gesture_rows(collected), nothing)
