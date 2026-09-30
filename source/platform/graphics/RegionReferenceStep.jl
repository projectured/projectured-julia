# Fragment of `GraphicsModule` — `RegionReferenceStep`, the reference step that
# names a region of a graphics node: a box that no node of its own draws.

"""
    RegionReferenceStep(x, y, width, height)

A box in the frame of the graphics node before it, which no node of its own
draws, as `PointReferenceStep` names a point there. A forward map answers it
after the smallest node that holds all of the image of a part, when that image is
no node and no range of one text: a text part that covers several segments is the
node of its line, or of its lines, followed by the region of its rows.
[`find_reference_box`](@ref) reads it as the box of the part.
"""
@cell_struct struct RegionReferenceStep <: ReferenceStep
    x::Int
    y::Int
    width::Int
    height::Int
end

ReferenceModule.get_reference_step_kind(::RegionReferenceStep) = :structural

# Every reference descends to a value; a region step's value is its box.
ReferenceModule.evaluate_reference_step(step::RegionReferenceStep, document) =
    (step.x, step.y, step.width, step.height)

Base.:(==)(a::RegionReferenceStep, b::RegionReferenceStep) =
    a.x == b.x && a.y == b.y && a.width == b.width && a.height == b.height

function Base.show(io::IO, s::RegionReferenceStep)
    print(io, "@(", s.x, ",", s.y, " ", s.width, "×", s.height, ")")
end
