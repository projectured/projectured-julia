"""
    ReferenceModule

Layer 3 of the kernel — **paths into documents**. A reference is a linked list
of typed steps (`RangeReference`, `FieldReference`, `TypeReference`,
`FunctionReference`, `ProjectionReference`, `PointReference`, …), forming a
`ReferencePath` (an `EmptyReferencePath` or a `ConcreteReferencePath`) that
addresses one location inside a document tree. The selection mechanism
propagates paths recursively, writing each suffix into the matching child
document's selection cell so every node in the tree always holds the sub-path
relevant to its own subtree.

The reference types/values, the `@reference_case` pattern-matching DSL, and
the `@reference` / `@step` construction DSL are one module, because the three
are only ever imported together and separating them just multiplied import
headers.

The module lives in three fragments that share this namespace:

- [`Reference.jl`](Reference.jl) — the reference-path *types* (steps, paths,
  their `@document`-generated struct forms) plus the value protocol on them
  (`append_reference`, `concat_references`, `evaluate_reference`,
  `is_valid_reference`, `annotate_reference_types`, `strip_reference_types`,
  the equality/prefix predicates).
- [`ReferenceCase.jl`](ReferenceCase.jl) — the `@reference_case`
  pattern-matching DSL (destructures a path against a series of
  `pattern => result` rules) plus the `when`/`prefix` guards.
- [`ReferenceBuilder.jl`](ReferenceBuilder.jl) — the `@reference` / `@step`
  construction DSL (compact surface syntax for building paths).

The linked-list *shape* is persistent — extending a path reuses the existing
tail rather than copying. The `@document`-backed step/path structs are
mutable and store their dynamic values (indices, positions, the head/tail
links) in reactive `Cell`s, so a caret move can update those cells in place
(see `update_selection!`) without rebuilding the chain.

A **layering pattern worth documenting**: `ProjectionReference` stores its
projection as an opaque `Any` payload — the reference layer defines only the
step's shape and never imports `Projection`; only higher layers construct
and interpret the payload (same pattern as `Intent`). So projection →
reference is the only edge between them, pointing down.
"""
module ReferenceModule

import ..CellModule: Cell, AbstractCell
import ..DocumentModule: @document

export Reference, ReferenceStep, ElementReference, PositionReference, TypeReference,
       FunctionReference, ProjectionReference, TextRectangularReference, ReferencePath,
       EmptyReferencePath, append_reference, concat_references, reference_steps,
       evaluate_reference, is_valid_reference, collect_references, is_element_reference,
       is_position_reference, is_range_reference, is_reference_equal, is_prefix_of,
       is_reference_equal_ignoring_types, is_prefix_of_ignoring_types, ReferenceTypeMismatch,
       get_valid_reference_prefix, annotate_reference_types, strip_reference_types,
       fold_reference_types,
       # ReferenceCase DSL:
       @reference_case, when, prefix,
       # ReferenceBuilder DSL:
       @reference, @step

# Types + value protocol first; the DSL fragments below use them.
include("Reference.jl")
include("ReferenceCase.jl")
include("ReferenceBuilder.jl")

end # module
