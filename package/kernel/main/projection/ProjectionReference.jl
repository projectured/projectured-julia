"""
    ProjectionReferenceModule

The `ProjectionReference` step type — a reference step that points at an
element introduced by a projection (a delimiter, a bracket, an
indentation, or any output-only fragment that has no direct counterpart in
the input document). Carries the `projection` that introduced the element
and an `output_path` describing where within that projection's output the
reference points.

Lives at the projection layer because the projection concept is what it
bridges; the reference layer (below) never names it. Registered as a
`:terminal` step type — it identifies a location but does not participate
in structural navigation — and registers its own `.proj(projection, sub)`
entries with the `@reference` / `@reference_case` DSLs via the reference
layer's `dsl_build_step` / `dsl_match_step` / `dsl_step_subpath_args` seams.
"""
module ProjectionReferenceModule

using ..CellModule
using ..ReferenceModule

export ProjectionReference

"""
    ProjectionReference(projection, output_path)

A reference step that points to an element introduced by a projection.
`output_path` describes where within the projection's output the reference
points. Evaluates to `output_path` — the projection-introduced element is
identified by that path in the projection's own output; every reference in
the tree is evaluatable.
"""
@cell_struct struct ProjectionReference <: ReferenceStep
    projection::Any
    output_path::ReferencePath
end

ReferenceModule.step_kind(::ProjectionReference) = :structural

# A projection step descends to the location the projection introduced —
# reified as the output path within that projection's output.
ReferenceModule.evaluate_step(step::ProjectionReference, document) = step.output_path

Base.:(==)(a::ProjectionReference, b::ProjectionReference) =
    a.projection === b.projection && a.output_path == b.output_path

# ── DSL registrations ──────────────────────────────────────────────────────

# `.proj(projection, subpath)` — argument 2 is a subpath, so both DSL parsers
# parse it as a reference path (not a value). This is the only kernel-side
# coupling the reference layer needs; the parsers stay ignorant of `.proj` itself.
ReferenceModule.dsl_step_subpath_args(::Val{:proj}) = (2,)

ReferenceModule.dsl_build_step(::Val{:proj}, projex, outpathex) =
    :($(GlobalRef(ProjectionReferenceModule, :ProjectionReference))($projex, $outpathex))

function ReferenceModule.dsl_match_step(::Val{:proj}, hex, argpats, rest_success, bound,
                                        gen_value_match, gen_path_match)
    projpat, outpath = argpats[1], argpats[2]
    projexpr = :($hex.projection)
    outpathexpr = :($hex.output_path)
    after_out, bound2 = gen_path_match(outpathexpr, outpath, rest_success, bound)
    after_proj, bound1 = gen_value_match(projexpr, projpat, after_out, bound2)
    ex = quote
        if $hex isa $(GlobalRef(ProjectionReferenceModule, :ProjectionReference))
            $after_proj
        else
            _nomatch
        end
    end
    return ex, bound1
end

end # module
