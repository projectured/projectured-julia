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

The module lives in eleven fragments that share this namespace:

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
  accept**, parsed once into one step AST (`ReferenceSyntaxStep`). The two DSL fragments below
  are *lowerings* of that AST, not parsers of their own.
- [`ReferenceGlob.jl`](ReferenceGlob.jl) — the **glob language** (`glob_matches`):
  `*`, `?`, `{a-e}`, `{^a-e}`, `{38..47}` over a single name. It knows nothing
  about references; it is a fragment here because this is where its callers are.
- [`ReferenceCase.jl`](ReferenceCase.jl) — the `@reference_case`
  pattern-matching DSL (destructures a path against a series of
  `pattern => result` rules) plus the `when`/`prefix` guards.
- [`ReferenceRules.jl`](ReferenceRules.jl) — the `@reference_rules` DSL: the same
  block of arms kept as a **value** (`ReferenceRules`), which is stored, compared,
  printed and applied later with `apply_reference_rules`. Its patterns are the
  `PatStep` data `ReferenceCase.jl` lowers to, matched by an interpreter rather
  than compiled, since a rule set may be built where no macro ran.
- [`ReferencePatternString.jl`](ReferencePatternString.jl) — the **string spelling**
  of a pattern (`ref"…"`, `parse_reference_pattern`): a dotted, glob-style key of
  the kind a configuration file is written in, parsed into the same `PatStep` data
  the Julia surface lowers to. A front end, not a second pattern language.
- [`ReferenceBuilder.jl`](ReferenceBuilder.jl) — the `@reference` / `@reference_step`
  construction DSL (compact surface syntax for building paths).

The linked-list *shape* is persistent — extending a path reuses the existing
tail rather than copying. The reactive step structs are mutable and store
their dynamic values (indices, positions, the head/tail links) in reactive
`Cell`s, so callers can update those cells in place without rebuilding the
chain — an index shifts in the UI and the change propagates.

The step types are `@document [C, M]` LAYOUT FAMILIES (the user's ruling,
2026-08-24: no reactivity in the kernel's run-path values; reactivity is for
the UI). The bare name binds the C (reactive) layout, so every UI caller
keeps the propagating step it always had; the `M…` variants are the plain
VALUES a simulator's hot path constructs, compares and hashes — a trimmed
binary resolves those statically. The `A…` stems carry `show`/`==`/`hash`/
the seam methods, so a reactive step equals a plain step holding the same
values. Steps are still not addressable CONTENT — nothing navigates into
one — the document machinery is used for its layouts alone.
"""
module ReferenceModule

using ..CellModule
using ..CellStructModule
using ..DocumentModule

export ReferenceStep, ElementReferenceStep, PositionReferenceStep, TypeReferenceStep,
       FieldReferenceStep, Position,
       RangeReferenceStep, Reference,
       # a reference is a linked list, and these read its two ends
       get_reference_head, get_reference_tail,
       # the step layout families: the A… stems carry the shared methods, the
       # M… variants are the plain values a simulator's hot path constructs
       ARangeReferenceStep, AFieldReferenceStep, ATypeReferenceStep,
       MRangeReferenceStep, MFieldReferenceStep, MTypeReferenceStep,
       MElementReferenceStep, MPositionReferenceStep,
       EmptyReference, ConcreteReference, extend_reference, concat_references, get_reference_steps,
       evaluate_reference, try_evaluate_reference, is_valid_reference, is_element_reference_step,
       is_position_reference_step, is_reference_equal, is_reference_prefix,
       ReferenceTypeMismatchException,
       get_valid_reference_prefix, annotate_reference_types, strip_reference_types,
       fold_reference_types, get_reference_node_type, is_fully_typed_reference,
       search_references,
       get_reference_step_kind, evaluate_reference_step,
       build_reference_step, match_reference_step, match_reference_step_value,
       get_reference_step_subpath_args,
       ReferenceRules, ReferenceRule, ReferenceRuleAnswer, REFERENCE_RULE_MODES,
       apply_reference_rules, match_reference_pattern,
       glob_matches,
       parse_reference_pattern, @ref_str,
       @reference_case, @reference_rules, @reference, @reference_step

include("ReferenceInterface.jl")
include("ReferenceStep.jl")
include("ReferencePath.jl")
include("ReferenceEvaluation.jl")
include("ReferenceSearch.jl")
include("ReferenceSyntax.jl")
include("ReferenceGlob.jl")
include("ReferenceCase.jl")
include("ReferenceRules.jl")
include("ReferencePatternString.jl")
include("ReferenceBuilder.jl")

end # module
