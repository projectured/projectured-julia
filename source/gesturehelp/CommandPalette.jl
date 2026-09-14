# Fragment of `GestureHelpModule`.
#
# The document behind the **command palette**: a type-in field over a list of the
# commands available where the user is. The user types a few characters, the list
# narrows to what matches, and Enter runs the selected row.
#
# The palette is the running twin of the gesture-help window. Both read one
# collected set of [`GestureBinding`](@ref)s, and both display it as
# [`GestureRow`](@ref)s. The help window only shows the set; the palette runs the
# rows that carry an operation — see [`GestureRow`](GestureMap.jl).
#
# The chosen row is the palette's own `selection`, as `rows[i-1:i]` — the same
# "element `i` of this collection field" reference a `WidgetList` row uses. The
# selection names a row of `rows`, not a row of the displayed subset, so the chosen
# command stays chosen while the user types more characters.
#
# The palette has one selection and it names the chosen row, so the query is edited
# at its end, as a type-in buffer is.
"""
    CommandPalette(query = "", rows = GestureRow[])

The palette state: what the user typed so far, and every row the palette was
opened with. The matching subset is derived from `query` by
[`get_command_palette_matches`](@ref); it is not stored, so it cannot go stale.
"""
@document struct CommandPalette
    query::String = ""
    rows::Any = GestureRow[]
end

# `rows[i-1:i]` — the canonical "element i of this collection field" reference, the
# one a widget row already uses. Building it here rather than reaching into the
# widget slice keeps the palette independent of how a list happens to render.
"""
    build_command_palette_selection(i) -> Reference or nothing

The selection reference for row `i` of `rows` (1-based); `nothing` for no row.
"""
build_command_palette_selection(i::Integer) = i <= 0 ? nothing :
    ConcreteReference(FieldReferenceStep("rows"),
        ConcreteReference(RangeReferenceStep(Int(i) - 1, Int(i)), EmptyReference()))

"""
    get_command_palette_selected(palette) -> Int

The selected row as a 1-based index into `rows`, or `0` when nothing is selected.
The inverse of [`build_command_palette_selection`](@ref).
"""
function get_command_palette_selected(palette::CommandPalette)
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
    get_command_palette_row(palette) -> GestureRow or nothing

The selected row itself, or `nothing` when the selection names no row.
"""
function get_command_palette_row(palette::CommandPalette)
    i = get_command_palette_selected(palette)
    rows = palette.rows
    1 <= i <= length(rows) ? rows[i] : nothing
end

# Where `query` matches `text`, or `nothing` when it does not. An empty query
# matches everything at position 0. The position is the rank: a command matched
# earlier in its text reads as the better answer.
#
# Every whitespace-separated word of the query must appear in `text` as a
# **contiguous** run of characters, in any order. So "sort" finds only what says
# sort, and "insert entry" still finds "Insert a new entry" without the user having
# to type the words between.
#
# A looser rule was tried first — the query as a subsequence, letter by letter — and
# it floods the list: over "<description> <domain>", the four letters of "sort" are
# a subsequence of "Select the root node" and of most of the JSON replace commands
# too. Ranking put the intended row on top, but everything else stayed on screen,
# which is not a filter.
function _query_position(query::AbstractString, text::AbstractString)
    words = split(lowercase(query))
    isempty(words) && return 0
    t = lowercase(text)
    earliest = 0
    for word in words
        at = findfirst(word, t)
        at === nothing && return nothing
        (earliest == 0 || first(at) < earliest) && (earliest = first(at))
    end
    earliest
end

"""
    get_command_palette_matches(palette) -> Vector{Int}

The indices of the rows that match `query`, best first. A row matches when every word of the
query appears in `"<description> <domain>"` as a contiguous run, without case.

A row ranks by: whether it can run, then how early its match starts, then the
collection order. A row that cannot run carries no operation, which is the same
thing as "not applicable right now" — there is only one answer, and it is whether
an operation was built.

The result is then **grouped by domain**, so the list reads as what each thing
offers rather than as one flat run of sentences. A group sits where its own
best-ranking row would have sat, so the row that would have led a flat list still
leads: the best answer stays first, and its neighbours are its own kind.

Matching by word rather than by letter is what makes the list a filter: a query of
"sort" leaves the rows that say sort, not every row whose letters happen to spell it.
"""
function get_command_palette_matches(palette::CommandPalette)
    rows = palette.rows
    query = palette.query
    ranked = NTuple{3,Int}[]
    for (i, row) in enumerate(rows)
        # The description leads, so a match in what the command *does* ranks ahead
        # of one in the group it belongs to — while typing a domain name still
        # narrows to that group.
        at = _query_position(query, string(row.description, " ", row.domain))
        at === nothing && continue
        push!(ranked, (row.operation === nothing ? 1 : 0, at, i))
    end
    sort!(ranked)
    # Group by domain, keeping each group where its best row put it.
    order = String[]                       # domains, best first
    grouped = Dict{String,Vector{Int}}()
    for r in ranked
        domain = rows[r[3]].domain
        haskey(grouped, domain) || (push!(order, domain); grouped[domain] = Int[])
        push!(grouped[domain], r[3])
    end
    result = Int[]
    for domain in order
        append!(result, grouped[domain])
    end
    result
end

"""
    compute_command_palette_step(palette, delta) -> Reference or nothing

The selection reference `delta` rows away in the matching subset, clamped at both
ends. With nothing selected, a forward step lands on the first match and a
backward step on the last. Returns `nothing` when nothing matches.
"""
function compute_command_palette_step(palette::CommandPalette, delta::Integer)
    matches = get_command_palette_matches(palette)
    isempty(matches) && return nothing
    at = findfirst(==(get_command_palette_selected(palette)), matches)
    next = at === nothing ? (delta >= 0 ? 1 : length(matches)) :
           clamp(at + delta, 1, length(matches))
    build_command_palette_selection(matches[next])
end

"""
    get_command_palette_settled_selection(palette) -> Reference or nothing

The selection to hold after `query` changed: the chosen row while it still
matches, the first match once it does not, and `nothing` when nothing matches.
"""
function get_command_palette_settled_selection(palette::CommandPalette)
    matches = get_command_palette_matches(palette)
    isempty(matches) && return nothing
    selected = get_command_palette_selected(palette)
    build_command_palette_selection(selected in matches ? selected : matches[1])
end
