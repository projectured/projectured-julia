"""
    ProjectionReferenceModule

The `ProjectionReferenceStep` step type — a reference step that points at an
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
layer's `build_reference_step` / `match_reference_step` / `get_reference_step_subpath_args` seams.
"""
module ProjectionReferenceModule

using ..CellModule
using ..CellStructModule
using ..ReferenceModule

export ProjectionReferenceStep, is_introduced_reference, named_node_reference

"""
    ProjectionReferenceStep(projection, output_path)

A reference step that points to an element introduced by a projection.
`output_path` describes where within the projection's output the reference
points. Evaluates to `output_path` — the projection-introduced element is
identified by that path in the projection's own output; every reference in
the tree is evaluatable.
"""
@cell_struct struct ProjectionReferenceStep <: ReferenceStep
    projection::Any
    output_path::Reference
end

ReferenceModule.get_reference_step_kind(::ProjectionReferenceStep) = :structural

"""
    is_introduced_reference(reference) -> Bool
    is_introduced_reference(reference, projection) -> Bool

Does `reference` point at a **projection-introduced** element — a delimiter, a
bracket, an indentation, a placeholder — rather than at anything in the input
document? Such a reference is headed by a `ProjectionReferenceStep` and has no input
pre-image, so `evaluate_reference` against the input throws (see
[`try_evaluate_reference`](@ref)).

This is the caret that sits *on the projection's own output*: the cursor is on a
comma the projection printed, not on any node the document contains. The two-argument
form additionally asks whether it was `projection` that introduced it, which is how a
projection recognizes its *own* output positions while mapping references.
"""
is_introduced_reference(reference) =
    reference isa ConcreteReference && reference.head isa ProjectionReferenceStep

is_introduced_reference(reference, projection) =
    is_introduced_reference(reference) && reference.head.projection === projection

"""
    named_node_reference(reference) -> Reference

The reference of the document node this caret **names**.

A caret on a projection-introduced element names the whole node it was printed for —
you are on a container's bracket, or on a placeholder — so it normalizes to `∅`, the
enclosing document itself. Any other reference already names a node and is returned
unchanged. Structural gestures ask this before acting, because the introduced
reference itself does not resolve against the input document.
"""
named_node_reference(reference) =
    is_introduced_reference(reference) ? EmptyReference() : reference

# A projection step descends to the location the projection introduced —
# reified as the output path within that projection's output.
ReferenceModule.evaluate_reference_step(step::ProjectionReferenceStep, document) = step.output_path

Base.:(==)(a::ProjectionReferenceStep, b::ProjectionReferenceStep) =
    a.projection === b.projection && a.output_path == b.output_path

# ── DSL registrations ──────────────────────────────────────────────────────

# `.proj(projection, subpath)` — argument 2 is a subpath, so both DSL parsers
# parse it as a reference path (not a value). This is the only kernel-side
# coupling the reference layer needs; the parsers stay ignorant of `.proj` itself.
ReferenceModule.get_reference_step_subpath_args(::Val{:proj}) = (2,)

ReferenceModule.build_reference_step(::Val{:proj}, projex, outpathex) =
    :($(GlobalRef(ProjectionReferenceModule, :ProjectionReferenceStep))($projex, $outpathex))

function ReferenceModule.match_reference_step(::Val{:proj}, hex, argpats, rest_success, bound,
                                        gen_value_match, gen_path_match)
    projpat, outpath = argpats[1], argpats[2]
    projexpr = :($hex.projection)
    outpathexpr = :($hex.output_path)
    after_out, bound2 = gen_path_match(outpathexpr, outpath, rest_success, bound)
    after_proj, bound1 = gen_value_match(projexpr, projpat, after_out, bound2)
    ex = quote
        if $hex isa $(GlobalRef(ProjectionReferenceModule, :ProjectionReferenceStep))
            $after_proj
        else
            _nomatch
        end
    end
    return ex, bound1
end

end # module
