"""
    PointReferenceModule

The `PointReference` step type — a reference step that identifies a point
within an element by pixel coordinates relative to that element's origin.
Lives with the graphics slice because pixel coordinates are the graphics
domain's own vocabulary; the kernel reference layer never names it.

Registered as a `:terminal` step type (identifies a location but does not
descend), and registers its own `.point(x, y)` entries with the kernel
`@reference` / `@reference_case` DSLs via the reference layer's
`dsl_build_step` / `dsl_match_step` seams.
"""
module PointReferenceModule

using ..CellModule
using ..ReferenceModule

export PointReference

"""
    PointReference(x, y)

References a point within the current element by pixel coordinates
relative to that element's origin. Evaluates to the coordinate tuple
`(x, y)` — every reference in the tree is evaluatable, and a point's
value is the coordinate itself, independent of what happens to be at
that coordinate in the current document.
"""
@cell_struct struct PointReference <: ReferenceStep
    x::Int
    y::Int
end

ReferenceModule.step_kind(::PointReference) = :structural

# Every reference descends to a value; a point step's value is its
# coordinate pair.
ReferenceModule.evaluate_step(step::PointReference, document) = (step.x, step.y)

Base.:(==)(a::PointReference, b::PointReference) = a.x == b.x && a.y == b.y

function Base.show(io::IO, s::PointReference)
    print(io, "@(", s.x, ",", s.y, ")")
end

# ── DSL registrations ──────────────────────────────────────────────────────

ReferenceModule.dsl_build_step(::Val{:point}, xex, yex) =
    :($(GlobalRef(PointReferenceModule, :PointReference))(Int($xex), Int($yex)))

function ReferenceModule.dsl_match_step(::Val{:point}, hex, argpats, rest_success, bound,
                                        gen_value_match, gen_path_match)
    xpat, ypat = argpats[1], argpats[2]
    xexpr = :($hex.x)
    yexpr = :($hex.y)
    inner2, bound2 = gen_value_match(yexpr, ypat, rest_success, bound)
    inner1, bound1 = gen_value_match(xexpr, xpat, inner2, bound2)
    ex = quote
        if $hex isa $(GlobalRef(PointReferenceModule, :PointReference))
            $inner1
        else
            _nomatch
        end
    end
    return ex, bound1
end

end # module
