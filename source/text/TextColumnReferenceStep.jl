# Fragment of `TextModule`.
#
# The `TextColumnReferenceStep` step type — a reference step representing a
# flat character-range **column box** in the text domain (`start` / `stop` are
# 0-based character offsets into the concatenated text of a `TextBlock`). It is
# the sibling of `TextRangeReferenceStep` (stream) and `TextSpanReferenceStep` (bounding
# box): same `(start, stop)` data, different render geometry and cursor behaviour.
#
# A column box is the "rectangular selection" of Sublime / VS Code column-select
# and Emacs `rectangle-mark`: the left edge is the *column* of `start`, the right
# edge the *column* of `stop`, painted on every row the span covers — a true
# rectangle regardless of the glyph content on each row.
#
# Reserved but **deferred**: the type and its render path (`_compute_column_geo`)
# exist so a future column-select gesture (e.g. Alt+drag) is additive, not
# structural. No producer emits it today. Registered as a `:structural` step type —
# it identifies a range but does not descend into a child, and (like the bounding
# box) char motion declines and exits to structural navigation rather than
# corrupting it.
#
# Lives with the text slice because the concept is text-domain vocabulary; the
# kernel reference layer never names it.
using ..CellModule
using ..CellStructModule
using ..ReferenceModule


"""
    TextColumnReferenceStep(start, stop)

A reference step representing a column-box (rectangular block) highlight in the
text domain. `start` and `stop` are flat 0-based character offsets into the
concatenated text of a `TextBlock`. Evaluates to the offset pair
`(start, stop)` — every reference in the tree is evaluatable, and the box's
value is its character range independent of what characters happen to sit in the
current text.
"""
@cell_struct struct TextColumnReferenceStep <: ReferenceStep
    start::Int
    stop::Int
end

ReferenceModule.get_reference_step_kind(::TextColumnReferenceStep) = :structural

# A column text range's descended value is the range itself.
ReferenceModule.evaluate_reference_step(step::TextColumnReferenceStep, document) = (step.start, step.stop)

Base.:(==)(a::TextColumnReferenceStep, b::TextColumnReferenceStep) =
    a.start == b.start && a.stop == b.stop
Base.hash(s::TextColumnReferenceStep, h::UInt) =
    hash(s.stop, hash(s.start, hash(:TextColumnReferenceStep, h)))

function Base.show(io::IO, s::TextColumnReferenceStep)
    print(io, "▥(", s.start, ":", s.stop, ")")
end
