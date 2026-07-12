"""
    ReferenceModule

Layer 3 of the kernel — **paths into documents**. A reference is a linked list
of typed steps (`RangeReference`, `FieldReference`, `TypeReference`, …),
forming a `ReferencePath` (an `EmptyReferencePath` or a
`ConcreteReferencePath`) that addresses one location inside a document tree.
Domain-specific step types live in their own layers and register their
navigation and DSL behaviours through this module's extension seams. The
path-producing reflection search (`search_references`) also lives here: it walks
an arbitrary document and
*produces* a reference path for every matching node, so it belongs with the
paths it emits (the value-collecting `search_documents` sibling, which needs no
reference machinery, lives one layer down in the document layer).

The reference types/values, the `@reference_case` pattern-matching DSL, and the
`@reference` / `@step` construction DSL are one module, because they are only ever
imported together and separating them just multiplied import headers.

The module lives in three fragments that share this namespace:

- [`Reference.jl`](Reference.jl) — the reference-path *types* (steps, paths,
  their `@document`-generated struct forms) plus the value protocol on them
  (`append_reference`, `concat_references`, `evaluate_reference`,
  `is_valid_reference`, `annotate_reference_types`, `strip_reference_types`,
  the equality/prefix predicates), and the path-producing reflection search
  (`search_references`) over documents.
- [`ReferenceCase.jl`](ReferenceCase.jl) — the `@reference_case`
  pattern-matching DSL (destructures a path against a series of
  `pattern => result` rules) plus the `when`/`prefix` guards.
- [`ReferenceBuilder.jl`](ReferenceBuilder.jl) — the `@reference` / `@step`
  construction DSL (compact surface syntax for building paths).

The linked-list *shape* is persistent — extending a path reuses the existing
tail rather than copying. The `@document`-backed step/path structs are
mutable and store their dynamic values (indices, positions, the head/tail
links) in reactive `Cell`s, so callers can update those cells in place
without rebuilding the chain.
"""
module ReferenceModule

import ..CellModule: Cell, AbstractCell
import ..DocumentModule: Document, is_element_collection, is_opaque, @document

export Reference, ReferenceStep, ElementReference, PositionReference, TypeReference,
       FieldReference, Position,
       RangeReference, ReferencePath,
       EmptyReferencePath, ConcreteReferencePath, append_reference, concat_references, reference_steps,
       evaluate_reference, is_valid_reference, is_element_reference,
       is_position_reference, is_reference_equal, is_prefix_of,
       ReferenceTypeMismatch,
       get_valid_reference_prefix, annotate_reference_types, strip_reference_types,
       fold_reference_types, reference_node_type, is_fully_typed,
       # Reflection search (produces reference paths):
       search_references,
       # Step-type extensibility seam:
       step_kind, evaluate_step,
       # DSL extension seams:
       dsl_build_step, dsl_match_step,
       # ReferenceCase DSL:
       @reference_case, when, prefix,
       # ReferenceBuilder DSL:
       @reference, @step

# Types + value protocol first; the DSL fragments come last.
include("Reference.jl")
include("ReferenceCase.jl")
include("ReferenceBuilder.jl")

end # module
