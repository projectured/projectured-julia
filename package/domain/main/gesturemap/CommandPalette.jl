"""
    CommandPaletteModule

The document behind the **command palette**: a type-in field over a list of the
commands available where the user is. The user types a few characters, the list
narrows to what matches, and Enter runs the selected row.

The palette is the running twin of the gesture-help window. Both read one
collected set of [`GestureBinding`](@ref)s, and both display it as
[`GestureRow`](@ref)s. The help window only shows the set; the palette runs the
rows that carry an operation — see [`GestureRow`](GestureMap.jl).

The chosen row is the palette's own `selection`, as `rows[i-1:i]` — the same
"element `i` of this collection field" reference a `WidgetList` row uses. The
selection names a row of `rows`, not a row of the displayed subset, so the chosen
command stays chosen while the user types more characters.

The palette has one selection and it names the chosen row, so the query is edited
at its end, as a type-in buffer is.
"""
module CommandPaletteModule

import ..CellModule: Cell
import ..DocumentApiModule: Document
import ..DocumentModule: var"@document"
import ..ReferenceModule: Reference, ConcreteReference, FieldReferenceStep,
                          RangeReferenceStep, EmptyReference
import ..GestureMapModule: GestureRow

export CommandPalette, command_palette_selection, command_palette_selected,
       command_palette_matches, command_palette_row, command_palette_step,
       command_palette_settled_selection

"""
    CommandPalette(query = "", rows = GestureRow[])

The palette state: what the user typed so far, and every row the palette was
opened with. The matching subset is derived from `query` by
[`command_palette_matches`](@ref); it is not stored, so it cannot go stale.
"""
@document struct CommandPalette
    query::String = ""
    rows::Any = GestureRow[]
end

# `rows[i-1:i]` — the canonical "element i of this collection field" reference, the
# one a widget row already uses. Building it here rather than reaching into the
# widget slice keeps the palette independent of how a list happens to render.
"""
    command_palette_selection(i) -> Reference or nothing

The selection reference for row `i` of `rows` (1-based); `nothing` for no row.
"""
command_palette_selection(i::Integer) = i <= 0 ? nothing :
    ConcreteReference(FieldReferenceStep("rows"),
        ConcreteReference(RangeReferenceStep(Int(i) - 1, Int(i)), EmptyReference()))

"""
    command_palette_selected(palette) -> Int

The selected row as a 1-based index into `rows`, or `0` when nothing is selected.
The inverse of [`command_palette_selection`](@ref).
"""
function command_palette_selected(palette::CommandPalette)
    selection = palette.selection
    selection isa ConcreteReference || return 0
    head = selection.head
    (head isa FieldReferenceStep && head.name == "rows") || return 0
    tail = selection.tail
    tail isa ConcreteReference || return 0
    step = tail.head
    step isa RangeReferenceStep || return 0
    step.start + 1
end

"""
    command_palette_row(palette) -> GestureRow or nothing

The selected row itself, or `nothing` when the selection names no row.
"""
function command_palette_row(palette::CommandPalette)
    i = command_palette_selected(palette)
    rows = palette.rows
    1 <= i <= length(rows) ? rows[i] : nothing
end

# Where `query` first matches `text` as a subsequence, or `nothing` when it does not
# match at all. An empty query matches everything at position 0. The position is the
# rank: a command whose match starts earlier reads as the better answer.
function _subsequence_position(query::AbstractString, text::AbstractString)
    isempty(query) && return 0
    q = lowercase(query)
    t = lowercase(text)
    at = firstindex(q)
    first_match = 0
    for (n, c) in enumerate(t)
        at > lastindex(q) && break
        if c == q[at]
            first_match == 0 && (first_match = n)
            at = nextind(q, at)
        end
    end
    at > lastindex(q) ? first_match : nothing
end

"""
    command_palette_matches(palette) -> Vector{Int}

The indices of the rows that match `query`, best first. A row matches when the
query is a subsequence of `"<domain> <description>"`, compared without case.

The order is: the rows that can run, then the rows whose match starts earlier,
then the collection order. A row that cannot run carries no operation, which is
the same thing as "not applicable right now" — there is only one answer, and it is
whether an operation was built.

A subsequence match is loose on purpose — "sort" matches "Replace with null" in
the `JsonDocument` domain, letter by letter. The rank carries the weight: the row
the user meant comes first, and the rest stay reachable for a query too short to
be precise.
"""
function command_palette_matches(palette::CommandPalette)
    rows = palette.rows
    query = palette.query
    found = NTuple{3,Int}[]
    for (i, row) in enumerate(rows)
        at = _subsequence_position(query, string(row.domain, " ", row.description))
        at === nothing && continue
        push!(found, (row.operation === nothing ? 1 : 0, at, i))
    end
    sort!(found)
    Int[f[3] for f in found]
end

"""
    command_palette_step(palette, delta) -> Reference or nothing

The selection reference `delta` rows away in the matching subset, clamped at both
ends. With nothing selected, a forward step lands on the first match and a
backward step on the last. Returns `nothing` when nothing matches.
"""
function command_palette_step(palette::CommandPalette, delta::Integer)
    matches = command_palette_matches(palette)
    isempty(matches) && return nothing
    at = findfirst(==(command_palette_selected(palette)), matches)
    next = at === nothing ? (delta >= 0 ? 1 : length(matches)) :
           clamp(at + delta, 1, length(matches))
    command_palette_selection(matches[next])
end

"""
    command_palette_settled_selection(palette) -> Reference or nothing

The selection to hold after `query` changed: the chosen row while it still
matches, the first match once it does not, and `nothing` when nothing matches.
"""
function command_palette_settled_selection(palette::CommandPalette)
    matches = command_palette_matches(palette)
    isempty(matches) && return nothing
    selected = command_palette_selected(palette)
    command_palette_selection(selected in matches ? selected : matches[1])
end

end # module
