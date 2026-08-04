"""
    ReferenceModule

**Paths into documents**. A reference is a linked list
of typed steps (`RangeReferenceStep`, `FieldReferenceStep`, `TypeReferenceStep`, …),
forming a `Reference` (an `EmptyReference` or a
`ConcreteReference`) that addresses one location inside a document tree.
Domain-specific step types live in their own layers and register their
navigation and DSL behaviours through this module's extension seams. The
path-producing reflection search (`search_references`) also lives here: it walks
an arbitrary document and *produces* a reference path for every matching node, so
it belongs with the paths it emits (the value-collecting `search_documents`
sibling, which needs no reference machinery, lives one layer down in the document
layer).

The reference types/values, the `@reference_case` pattern-matching DSL, and the
`@reference` / `@reference_step` construction DSL are one module, because they are only ever
imported together and separating them just multiplied import headers.

The module lives in eight fragments that share this namespace:

- [`ReferenceInterface.jl`](ReferenceInterface.jl) — the contract: the `ReferenceStep` and
  `Reference` abstract types (a document's `selection` field holds a `Reference`
  or `nothing`), and the open generics higher packages add methods to
  (`get_reference_step_kind`, `evaluate_reference_step`, and the reference-step DSL seams).
- [`ReferenceStep.jl`](ReferenceStep.jl) — the kernel's step vocabulary
  (`RangeReferenceStep`, `FieldReferenceStep`, `TypeReferenceStep`, the `Position` a cursor
  evaluates to), each step type packaged with its own `show`, `==`, and seam
  methods.
- [`ReferencePath.jl`](ReferencePath.jl) — the path structure and its
  document-free algebra: the two path types, their constructors/accessors/
  iteration, the equality and prefix predicates, and `extend_reference` /
  `concat_references` / `get_reference_steps`.
- [`ReferenceEvaluation.jl`](ReferenceEvaluation.jl) — walking a path against a
  document (`evaluate_reference`, `get_valid_reference_prefix`,
  `is_valid_reference`) and the "types always present" invariant
  (`annotate_reference_types`, `strip_reference_types`, `fold_reference_types`,
  `get_reference_node_type`, `is_fully_typed_reference`).
- [`ReferenceSearch.jl`](ReferenceSearch.jl) — the path-producing reflection
  search (`search_references`) over documents.
- [`ReferenceSyntax.jl`](ReferenceSyntax.jl) — the **surface grammar both DSLs
  accept**, parsed once into one step AST (`RefStep`). The two DSL fragments below
  are *lowerings* of that AST, not parsers of their own.
- [`ReferenceCase.jl`](ReferenceCase.jl) — the `@reference_case`
  pattern-matching DSL (destructures a path against a series of
  `pattern => result` rules) plus the `when`/`prefix` guards.
- [`ReferenceBuilder.jl`](ReferenceBuilder.jl) — the `@reference` / `@reference_step`
  construction DSL (compact surface syntax for building paths).

The linked-list *shape* is persistent — extending a path reuses the existing
tail rather than copying. The `@cell_struct`-backed step/path structs are
mutable and store their dynamic values (indices, positions, the head/tail
links) in reactive `Cell`s, so callers can update those cells in place
without rebuilding the chain.

Steps and paths are **not `Document`s** — they are the machinery that *addresses*
documents, not addressable content. Nothing navigates into a reference, selects
inside one, or projects one, so a reference has no `selection` field and needs
none of `@document`'s document codegen. `@cell_struct` gives it the only thing it
wants: transparent reactive-`Cell` fields.
"""
module ReferenceModule

using ..CellModule
using ..CellStructModule
using ..DocumentModule

export ReferenceStep, ElementReferenceStep, PositionReferenceStep, TypeReferenceStep,
       FieldReferenceStep, Position,
       RangeReferenceStep, Reference,
       EmptyReference, ConcreteReference, extend_reference, concat_references, get_reference_steps,
       evaluate_reference, try_evaluate_reference, is_valid_reference, is_element_reference_step,
       is_position_reference_step, is_reference_equal, is_reference_prefix,
       ReferenceTypeMismatch,
       get_valid_reference_prefix, annotate_reference_types, strip_reference_types,
       fold_reference_types, get_reference_node_type, is_fully_typed_reference,
       search_references,
       get_reference_step_kind, evaluate_reference_step,
       build_reference_step, match_reference_step, get_reference_step_subpath_args,
       @reference_case, @reference, @reference_step

include("ReferenceInterface.jl")
include("ReferenceStep.jl")
include("ReferencePath.jl")
include("ReferenceEvaluation.jl")
include("ReferenceSearch.jl")
include("ReferenceSyntax.jl")
include("ReferenceCase.jl")
include("ReferenceBuilder.jl")

end # module
