# ──────────────────────────────────────────────────────────────────────────
# Folded in from TextRangeReferenceStep.jl.
#
# The `TextRangeReferenceStep` step type — a reference step representing a flat
# character range / caret in the text domain (`start` / `stop` are 0-based
# character offsets into the concatenated text of a `TextBlock`). This is the
# canonical, structure-independent representation of the text cursor and linear
# text selection: `start == stop` is the caret, `start < stop` a selection. It
# addresses a position purely by its flat offset, so the *same* visual caret has a
# single representation regardless of how the block splits its text into
# spans/lines — the boundary-duplicate ambiguity a span-anchored path suffers from
# does not arise.
#
# Sibling to `TextSpanReferenceStep`: both carry a flat `(start, stop)` pair,
# but they route to opposite behaviours — a rectangular reference is a whole-element
# box highlight (structural mode, declines character motion), a range reference is
# the character cursor itself. They are therefore distinct types.
#
# Lives with the text slice because the concept is text-domain vocabulary; the
# kernel reference layer never names it. Evaluates to a `Position` for a caret (so a
# caret path terminates `::Position`, as the old span-anchored form did) and to the
# offset pair `(start, stop)` for a non-empty range.
using ..CellModule
using ..CellStructModule
using ..ReferenceModule


"""
    TextRangeReferenceStep(start, stop)

A reference step representing a flat character range in the text domain. `start`
and `stop` are 0-based character offsets into the concatenated text of a
`TextBlock`. `start == stop` is a zero-width caret; `start < stop` a linear
selection. Evaluates to `Position(start)` for a caret and `(start, stop)` for a
range — every reference in the tree is evaluatable, and the range's value is its
character range independent of what characters happen to sit in the current text.
"""
@cell_struct struct TextRangeReferenceStep <: ReferenceStep
    start::Int
    stop::Int
end

"True when this range is a zero-width caret (`start == stop`)."
is_text_caret(s::TextRangeReferenceStep) = s.start == s.stop

ReferenceModule.get_reference_step_kind(::TextRangeReferenceStep) = :structural

# A caret evaluates to a `Position` (a flat caret between characters); a non-empty
# range's descended value is the offset pair itself.
ReferenceModule.evaluate_reference_step(step::TextRangeReferenceStep, document) =
    step.start == step.stop ? Position(step.start) : (step.start, step.stop)

Base.:(==)(a::TextRangeReferenceStep, b::TextRangeReferenceStep) =
    a.start == b.start && a.stop == b.stop

function Base.show(io::IO, s::TextRangeReferenceStep)
    s.start == s.stop ? print(io, "⌶{", s.start, "}") :
                        print(io, "⌶{", s.start, ":", s.stop, "}")
end
