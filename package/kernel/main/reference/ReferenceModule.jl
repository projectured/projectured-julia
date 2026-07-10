"""
    ReferenceModule

Layer 3 of the kernel — **paths into documents**. A reference is a linked list
of typed steps (`RangeReference`, `FieldReference`, `TypeReference`, …),
forming a `ReferencePath` (an `EmptyReferencePath` or a
`ConcreteReferencePath`) that addresses one location inside a document tree.
Domain-specific step types live in their own layers and register their
navigation and DSL behaviours through this module's extension seams. The selection generics
(`get_selection` / `clear_selection!` / `set_selection!` / `with_selection`)
also live here — their payload is a reference — so a document's current-focus
API sits with the machinery that expresses it.

The reference types/values, the selection generics, the `@reference_case`
pattern-matching DSL, and the `@reference` / `@step` construction DSL are one
module, because they are only ever imported together and separating them just
multiplied import headers.

The module lives in four fragments that share this namespace:

- [`Reference.jl`](Reference.jl) — the reference-path *types* (steps, paths,
  their `@document`-generated struct forms) plus the value protocol on them
  (`append_reference`, `concat_references`, `evaluate_reference`,
  `is_valid_reference`, `annotate_reference_types`, `strip_reference_types`,
  the equality/prefix predicates).
- [`Selection.jl`](Selection.jl) — the `get_selection` / `clear_selection!` /
  `set_selection!` / `with_selection` generics that read, clear, and canonicalize
  a document's `selection` field.
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
import ..DocumentModule: Document, @document

export Reference, ReferenceStep, ElementReference, PositionReference, TypeReference,
       FieldReference,
       RangeReference, ReferencePath,
       EmptyReferencePath, ConcreteReferencePath, append_reference, concat_references, reference_steps,
       evaluate_reference, is_valid_reference, collect_references, is_element_reference,
       is_position_reference, is_reference_equal, is_prefix_of,
       ReferenceTypeMismatch,
       get_valid_reference_prefix, annotate_reference_types, strip_reference_types,
       fold_reference_types,
       # Step-type extensibility seam:
       step_kind, evaluate_step,
       # DSL extension seams:
       dsl_build_step, dsl_match_step,
       # Selection generics:
       get_selection, clear_selection!, set_selection!, with_selection,
       # ReferenceCase DSL:
       @reference_case, when, prefix,
       # ReferenceBuilder DSL:
       @reference, @step

# Types + value protocol first; the selection generics reference `Document`
# only (from DocumentModule) and are declaration-only, so their placement is
# order-insensitive. The DSL fragments come last.
include("Reference.jl")
include("Selection.jl")
include("ReferenceCase.jl")
include("ReferenceBuilder.jl")

end # module
