"""
    TextSpanReferenceStepModule

The `TextSpanReferenceStep` step type — a reference step representing a
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
module TextSpanReferenceStepModule

using ..CellModule
using ..CellStructModule
using ..ReferenceModule

export TextSpanReferenceStep

"""
    TextSpanReferenceStep(start, stop)

A reference step representing an axis-aligned bounding-box highlight in the
text domain. `start` and `stop` are flat 0-based character offsets into the
concatenated text of a `TextBlock`. Evaluates to the offset pair
`(start, stop)` — every reference in the tree is evaluatable, and the
box's value is its character range independent of what characters happen
to sit in the current text.
"""
@cell_struct struct TextSpanReferenceStep <: ReferenceStep
    start::Int
    stop::Int
end

ReferenceModule.get_reference_step_kind(::TextSpanReferenceStep) = :structural

# A rectangular text range's descended value is the range itself.
ReferenceModule.evaluate_reference_step(step::TextSpanReferenceStep, document) = (step.start, step.stop)

Base.:(==)(a::TextSpanReferenceStep, b::TextSpanReferenceStep) =
    a.start == b.start && a.stop == b.stop

function Base.show(io::IO, s::TextSpanReferenceStep)
    print(io, "▢(", s.start, ":", s.stop, ")")
end

end # module
