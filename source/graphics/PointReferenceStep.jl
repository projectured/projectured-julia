# Fragment of `GraphicsModule` — `PointReferenceStep`, the reference step that
# names a point in a graphics document, and its reference-layer seams.

@cell_struct struct PointReferenceStep <: ReferenceStep
    x::Int
    y::Int
end

ReferenceModule.get_reference_step_kind(::PointReferenceStep) = :structural

# Every reference descends to a value; a point step's value is its
# coordinate pair.
ReferenceModule.evaluate_reference_step(step::PointReferenceStep, document) = (step.x, step.y)

Base.:(==)(a::PointReferenceStep, b::PointReferenceStep) = a.x == b.x && a.y == b.y

function Base.show(io::IO, s::PointReferenceStep)
    print(io, "@(", s.x, ",", s.y, ")")
end

# ── DSL registrations ──────────────────────────────────────────────────────

ReferenceModule.build_reference_step(::Val{:point}, xex, yex) =
    :($(GlobalRef(GraphicsModule, :PointReferenceStep))(Int($xex), Int($yex)))

function ReferenceModule.match_reference_step(::Val{:point}, hex, argpats, rest_success, bound,
                                        gen_value_match, gen_path_match)
    xpat, ypat = argpats[1], argpats[2]
    xexpr = :($hex.x)
    yexpr = :($hex.y)
    inner2, bound2 = gen_value_match(yexpr, ypat, rest_success, bound)
    inner1, bound1 = gen_value_match(xexpr, xpat, inner2, bound2)
    ex = quote
        if $hex isa $(GlobalRef(GraphicsModule, :PointReferenceStep))
            $inner1
        else
            _nomatch
        end
    end
    return ex, bound1
end
