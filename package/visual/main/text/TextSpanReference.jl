"""
    TextSpanReferenceModule

The `TextSpanReference` step type — a reference step representing a
flat character-range box in the text domain (`start` / `stop` are 0-based
character offsets into the concatenated text of a `TextBlock`). Used by the
syntax-to-text stage to communicate a nested child's whole-element
selection as a character range to the text-to-graphics stage, which renders
it as a translucent rectangle.

Lives with the text slice because the concept is text-domain vocabulary;
the kernel reference layer never names it. Registered as a `:terminal` step
type — it identifies a range but does not descend into a child. No DSL
entry (`.rect` / equivalent) is exposed today; when one is added it goes
here alongside the type.
"""
module TextSpanReferenceModule

using ..CellModule
using ..CellStructModule
using ..ReferenceModule

export TextSpanReference

"""
    TextSpanReference(start, stop)

A reference step representing an axis-aligned bounding-box highlight in the
text domain. `start` and `stop` are flat 0-based character offsets into the
concatenated text of a `TextBlock`. Evaluates to the offset pair
`(start, stop)` — every reference in the tree is evaluatable, and the
box's value is its character range independent of what characters happen
to sit in the current text.
"""
@cell_struct struct TextSpanReference <: ReferenceStep
    start::Int
    stop::Int
end

ReferenceModule.step_kind(::TextSpanReference) = :structural

# A rectangular text range's descended value is the range itself.
ReferenceModule.evaluate_step(step::TextSpanReference, document) = (step.start, step.stop)

Base.:(==)(a::TextSpanReference, b::TextSpanReference) =
    a.start == b.start && a.stop == b.stop

function Base.show(io::IO, s::TextSpanReference)
    print(io, "▢(", s.start, ":", s.stop, ")")
end

end # module
