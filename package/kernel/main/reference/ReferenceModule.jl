"""
    ReferenceModule

**Paths into documents**. A reference is a linked list
of typed steps (`RangeReferenceStep`, `FieldReferenceStep`, `TypeReferenceStep`, …),
forming a `ReferencePath` (an `EmptyReferencePath` or a
`ConcreteReferencePath`) that addresses one location inside a document tree.
Domain-specific step types live in their own layers and register their
navigation and DSL behaviours through this module's extension seams. The
path-producing reflection search (`search_references`) also lives here: it walks
an arbitrary document and *produces* a reference path for every matching node, so
it belongs with the paths it emits (the value-collecting `search_documents`
sibling, which needs no reference machinery, lives one layer down in the document
layer).

The reference types/values, the `@reference_case` pattern-matching DSL, and the
`@reference` / `@step` construction DSL are one module, because they are only ever
imported together and separating them just multiplied import headers.

The module lives in eight fragments that share this namespace:

- [`ReferenceInterface.jl`](ReferenceInterface.jl) — the contract: the `ReferenceStep` and
  `ReferencePath` abstract types, the `Reference` union a selection field holds,
  and the open generics higher packages add methods to (`step_kind`,
  `evaluate_step`, and the `dsl_*` DSL seams).
- [`ReferenceStep.jl`](ReferenceStep.jl) — the kernel's step vocabulary
  (`RangeReferenceStep`, `FieldReferenceStep`, `TypeReferenceStep`, the `Position` a cursor
  evaluates to), each step type packaged with its own `show`, `==`, and seam
  methods.
- [`ReferencePath.jl`](ReferencePath.jl) — the path structure and its
  document-free algebra: the two path types, their constructors/accessors/
  iteration, the equality and prefix predicates, and `append_reference` /
  `concat_references` / `reference_steps`.
- [`ReferenceEvaluation.jl`](ReferenceEvaluation.jl) — walking a path against a
  document (`evaluate_reference`, `get_valid_reference_prefix`,
  `is_valid_reference`) and the "types always present" invariant
  (`annotate_reference_types`, `strip_reference_types`, `fold_reference_types`,
  `reference_node_type`, `is_fully_typed`).
- [`ReferenceSearch.jl`](ReferenceSearch.jl) — the path-producing reflection
  search (`search_references`) over documents.
- [`ReferenceSyntax.jl`](ReferenceSyntax.jl) — the **surface grammar both DSLs
  accept**, parsed once into one step AST (`RefStep`). The two DSL fragments below
  are *lowerings* of that AST, not parsers of their own.
- [`ReferenceCase.jl`](ReferenceCase.jl) — the `@reference_case`
  pattern-matching DSL (destructures a path against a series of
  `pattern => result` rules) plus the `when`/`prefix` guards.
- [`ReferenceBuilder.jl`](ReferenceBuilder.jl) — the `@reference` / `@step`
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

export Reference, ReferenceStep, ElementReferenceStep, PositionReferenceStep, TypeReferenceStep,
       FieldReferenceStep, Position,
       RangeReferenceStep, ReferencePath,
       EmptyReferencePath, ConcreteReferencePath, append_reference, concat_references, reference_steps,
       evaluate_reference, try_evaluate_reference, is_valid_reference, is_element_reference,
       is_position_reference, is_reference_equal, is_prefix_of,
       ReferenceTypeMismatch,
       get_valid_reference_prefix, annotate_reference_types, strip_reference_types,
       fold_reference_types, reference_node_type, is_fully_typed,
       # Reflection search (produces reference paths):
       search_references,
       # Step-type extensibility seam:
       step_kind, evaluate_step,
       # DSL extension seams:
       dsl_build_step, dsl_match_step, dsl_step_subpath_args,
       # ReferenceCase DSL:
       @reference_case, when, prefix,
       # ReferenceBuilder DSL:
       @reference, @step

# The contract first — the abstract types it declares are named in the struct
# field annotations below (`head::ReferenceStep`, `tail::ReferencePath`), which
# are evaluated at definition time. Then the types, the value protocol on them,
# and finally the DSL fragments that consume the seams.
include("ReferenceInterface.jl")
include("ReferenceStep.jl")
include("ReferencePath.jl")
include("ReferenceEvaluation.jl")
include("ReferenceSearch.jl")
# The shared surface grammar, then the two DSLs that lower it. Syntax must precede
# both: it calls the `dsl_step_subpath_args` seam (declared in `ReferenceInterface.jl`) to tag
# an extension step's subpath arguments while parsing.
include("ReferenceSyntax.jl")
include("ReferenceCase.jl")
include("ReferenceBuilder.jl")

end # module
