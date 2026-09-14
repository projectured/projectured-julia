# Fragment of `TextModule` — `TextSpanReferenceStep`, the reference step that
# names a run of characters between two offsets, and its reference-layer seams.

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
