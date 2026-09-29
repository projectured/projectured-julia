# Fragment of `ProjectionModule` — `ProjectionReferenceStep`, a reference step
# that points at an element a projection introduced: a delimiter, a bracket, an
# indentation, or any output-only fragment with no counterpart in the input
# document. It carries the projection that introduced the element and an
# `output_path` saying where in that projection's output the reference points.
#
# It is a `:terminal` step type — it names a location and takes no part in
# structural navigation — and it registers its own `.proj(projection, sub)`
# entries with the `@reference` and `@reference_case` DSLs through the
# reference layer's `build_reference_step`, `match_reference_step` and
# `get_reference_step_subpath_args` seams.

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
    make_introduced_reference(projection, document, output_path) -> Reference
    make_introduced_reference(projection, node_type::Type, output_path) -> Reference

The canonical caret **on** a projection-introduced element: the step wrapped as a
one-node path that satisfies the strict-typing invariant.

`document` is the input node the projection printed, and its type is the type of the
one node the path has. `output_path` names the introduced element inside the
projection's output. The terminal records `Position`: the caret sits on the output the
projection printed, so it has no input node to land on, and `evaluate_reference` against
the input throws — which is what [`is_introduced_reference`](@ref) documents and what
`normalize_named_node_reference` exists to normalize.

Build every introduced caret through this, never by hand. A hand-built path leaves the
terminal untyped, which no reader notices while the caret stays inside its own domain —
`@reference` runs its strict check on **construction**, and a domain that maps its own
references never constructs one from this path. An embedder does: a pane tab holds a
foreign document, so `PaneToWidget` splices whatever the content projection hands back
into an `@reference` literal, and an untyped terminal throws there.
"""
make_introduced_reference(projection, node_type::Type, output_path::Reference) =
    ConcreteReference(node_type, ProjectionReferenceStep(projection, output_path),
                      EmptyReference(Position))

make_introduced_reference(projection, document, output_path::Reference) =
    make_introduced_reference(projection, get_reference_node_type(document), output_path)

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
    normalize_named_node_reference(reference) -> Reference

The reference of the document node this caret **names**.

A caret on a projection-introduced element names the whole node it was printed for —
you are on a container's bracket, or on a placeholder — so it normalizes to `∅`, the
enclosing document itself. Any other reference already names a node and is returned
unchanged. Structural gestures ask this before acting, because the introduced
reference itself does not resolve against the input document.
"""
normalize_named_node_reference(reference) =
    is_introduced_reference(reference) ? EmptyReference() : reference

# A projection step descends to the location the projection introduced —
# reified as the output path within that projection's output.
ReferenceModule.evaluate_reference_step(step::ProjectionReferenceStep, document) = step.output_path

Base.:(==)(a::ProjectionReferenceStep, b::ProjectionReferenceStep) =
    a.projection === b.projection && a.output_path == b.output_path

# It mixes exactly what `==` reads, so two equal steps key one entry of a table.
Base.hash(s::ProjectionReferenceStep, h::UInt) =
    hash(s.output_path, hash(objectid(s.projection), hash(:ProjectionReferenceStep, h)))

# A short line, such as a log of operations, asks for the `:compact` form through
# its `IOContext`. There the step reads as the part that the projection printed,
# in the vocabulary of its output and between ‹ and ›, and the projection is left
# out: `.entries[5].value‹.close{0}›`. A step inside the output path of another
# step adds no second pair of marks. Every other display keeps the full form.
function Base.show(io::IO, step::ProjectionReferenceStep)
    get(io, :compact, false) || return Base.show_default(io, step)
    inner = strip_reference_types(step.output_path)
    get(io, :introduced, false) && return show(io, inner)
    print(io, "‹")
    show(IOContext(io, :introduced => true), inner)
    print(io, "›")
end

# ── DSL registrations ──────────────────────────────────────────────────────

# `.proj(projection, subpath)` — argument 2 is a subpath, so both DSL parsers
# parse it as a reference path (not a value). This is the only kernel-side
# coupling the reference layer needs; the parsers stay ignorant of `.proj` itself.
ReferenceModule.get_reference_step_subpath_args(::Val{:proj}) = (2,)

ReferenceModule.build_reference_step(::Val{:proj}, projex, outpathex) =
    :($(GlobalRef(ProjectionModule, :ProjectionReferenceStep))($projex, $outpathex))

function ReferenceModule.match_reference_step(::Val{:proj}, hex, argpats, rest_success, bound,
                                        gen_value_match, gen_path_match)
    projpat, outpath = argpats[1], argpats[2]
    projexpr = :($hex.projection)
    outpathexpr = :($hex.output_path)
    after_out, bound2 = gen_path_match(outpathexpr, outpath, rest_success, bound)
    after_proj, bound1 = gen_value_match(projexpr, projpat, after_out, bound2)
    ex = quote
        if $hex isa $(GlobalRef(ProjectionModule, :ProjectionReferenceStep))
            $after_proj
        else
            _nomatch
        end
    end
    return ex, bound1
end
