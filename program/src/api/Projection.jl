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
    projection_print(projection, input, recursion, reference) -> output

Shared interface function for all projections. Each concrete projection
type adds a method to this function. This allows compound projections
like `SequentialProjection` to compose arbitrary projections via dispatch.

The `recursion` argument is a projection that can be used to call
`projection_print` recursively on sub-documents.

The `reference` argument is a `ReferencePath` that describes where `input`
is located relative to the document root of the editor.  At the top level
the editor passes `EmptyReferencePath()`; projections that recurse into
child elements extend the path accordingly before each recursive call.
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

Translates `reference` from the projection's input domain to the output
domain using the recorded `iomap`.  Returns `nothing` for references that
have no image in the output (e.g. elements removed by a filtering projection).
"""
function map_reference_forward end

"""
    map_reference_backward(projection, iomap, reference) -> reference_or_nothing

Shared interface function for all projections. Each concrete projection type
adds a method to this function.

Translates `reference` from the projection's output domain back to the input
domain using the recorded `iomap`.  Returns `nothing` for references that
have no pre-image in the input (e.g. structural delimiters introduced by the
projection).
"""
function map_reference_backward end

end # module
