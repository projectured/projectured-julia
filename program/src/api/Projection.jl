"""
    ProjectionApiModule

Shared projection interface. Declares projection_print and projection_read
as generic functions dispatched on by all projection types, primitive and
higher-order alike. Keeping the interface here avoids circular dependencies
between projection modules.
"""
module ProjectionApiModule

export projection_print, projection_read, map_reference_forward, map_reference_backward, Projection

"""
    Projection

Abstract base type for all projection types, primitive and higher-order alike.
Subtype this to register with the default `map_reference_forward`,
`map_reference_backward`, and `projection_read` fallbacks.
"""
abstract type Projection end

"""
    projection_print(projection, input, recursion, context::ProjectionContext) -> output

Shared interface function for all projections. Each concrete projection
type adds a method to this function. This allows compound projections
like `SequentialProjection` to compose arbitrary projections via dispatch.

The `recursion` argument is a projection that can be used to call
`projection_print` recursively on sub-documents.

The `context` argument is a `ProjectionContext` carrying the reference
path (where `input` sits relative to the document root) plus optional
downward-flowing fields — tree depth, parent-allocated available width/
height, and an extensible `properties` Dict. At the top level the editor
passes a fresh `ProjectionContext()`; projections that recurse into child
elements call `child_context(ctx, steps...)` to extend the reference and
bump the depth.
"""
function projection_print end

"""
    projection_read(projection, iomap, event_or_op) -> op_or_nothing

Shared interface function for the reader side of all projections. Each
concrete projection type adds a method to this function.

The last projection in a pipeline receives a raw device event; each earlier
projection receives the operation produced by its downstream neighbour and
translates it into an operation on its own input domain.
"""
function projection_read end

"""
    map_reference_forward(projection, iomap, reference) -> reference_or_nothing

Shared interface function for all projections. Each concrete projection type
adds a method to this function.

`reference` is an *input reference* — its steps are understood starting from
`projection`'s input document. The returned reference is an *output reference*
— its steps are understood starting from `projection`'s output document.
Returns `nothing` for input references that have no image in the output (e.g.
elements removed by a filtering projection).

If the input reference begins with `ProjectionReference(projection, output_path)`,
the step is stripped and `output_path` is returned directly — that step exists
precisely to embed an already-translated output reference inside an input
reference.
"""
function map_reference_forward end

"""
    map_reference_backward(projection, iomap, reference) -> reference_or_nothing

Shared interface function for all projections. Each concrete projection type
adds a method to this function.

`reference` is an *output reference* — its steps are understood starting from
`projection`'s output document. The returned reference is an *input reference*
— its steps are understood starting from `projection`'s input document.
Returns `nothing` for output references that have no pre-image in the input.

When the output reference has no direct pre-image (e.g. it points at a
projection-introduced delimiter), the input reference can be constructed as
`closest_matched_input_prefix + ProjectionReference(projection, unmatched_output_suffix)`
— i.e. wrap the unmatched suffix with this projection's own `proj` step so
that `map_reference_forward` can later strip it and recover the original
output reference.
"""
function map_reference_backward end

end # module
