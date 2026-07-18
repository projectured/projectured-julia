# Fragment of `ReferenceModule` — the reference **contract**: the two abstract
# types every reference value is built from (`ReferenceStep`, `ReferencePath`),
# the `Reference` union a document's selection field holds, and the open generics
# that higher packages add methods to. The concrete kernel step types live in
# `ReferenceStep.jl`, the path structure in `ReferencePath.jl`, and the DSLs that
# consume the `dsl_*` seams in `ReferenceCase.jl` / `ReferenceBuilder.jl`.
#
# A step type defined in a higher package (`PointReferenceStep`, `ProjectionReferenceStep`,
# `TextSpanReferenceStep`) subtypes `ReferenceStep` and registers itself by
# adding methods to the generics declared here — at its own definition site, with
# no edit to this layer.

"""
    ReferenceStep

Abstract base type for reference steps. Each subtype describes how to
descend one level into a document structure.
"""
abstract type ReferenceStep end

"""
    ReferencePath

Abstract base type for a path into a document. Implemented as an
immutable linked list so that extending a path (going deeper) reuses
the existing tail — no copying required.
"""
abstract type ReferencePath end

"""
    Reference

Union type for document selection fields: either `nothing` (no selection)
or a `ReferencePath` describing the selected location.
"""
const Reference = Union{Nothing, ReferencePath}

# ── Step navigation seam ──────────────────────────────────────────────────
# Each step type registers its own behaviour by adding methods on
# `get_reference_step_kind` (classification) and `evaluate_reference_step` (one-level navigation).
# The three path walkers (`evaluate_reference`,
# `get_valid_reference_prefix`, `annotate_reference_types`) all dispatch
# through this seam — a new step type living in a higher package registers
# its methods at its own definition site and needs no edits here.

"""
    get_reference_step_kind(step) -> Symbol

Classify a reference step: `:structural` (descends to a child or synthetic
value) or `:checkpoint` (stays on the current node, asserts an invariant).
Every step type answers for itself, beside its `evaluate_reference_step` — there is no
default, so a new step type that forgets to classify itself fails loudly at the
first path walk rather than being silently treated as structural. A
`:structural` step must be evaluatable under the "types always present"
invariant.
"""
function get_reference_step_kind end

"""
    evaluate_reference_step(step, document) -> child

Navigate through `step`. For a `:structural` step, return the descended
value (throws on descent failure). Some step types descend to a document
child (`FieldReferenceStep`, `RangeReferenceStep`); others descend to a synthetic
value that stands in for the reference target (`PointReferenceStep` returns a
coordinate pair, `ProjectionReferenceStep` returns the projection's output
path, `TextSpanReferenceStep` returns the character range). For a
`:checkpoint` step, return `document` unchanged after asserting the
invariant (throws on mismatch).
"""
function evaluate_reference_step end

# ── DSL seams ─────────────────────────────────────────────────────────────
# The `@reference` / `@reference_step` construction DSL and the `@reference_case`
# pattern-matching DSL both reach a step type through these generics, so
# neither parser names a step type it does not own. A step type registers a
# `::Val{:name}` method for its `.name(args...)` surface syntax in the package
# that defines it; the kernel registers none — its own steps (`.field`, `[i]`,
# `{k}`, `::T`) are built-in grammar, not seam entries. Each seam's fallback for
# an unregistered name lives with the DSL that reaches it (`ReferenceSyntax.jl`,
# `ReferenceBuilder.jl`, `ReferenceCase.jl`).

"""
    build_reference_step(::Val{name}, escaped_args...) -> Expr

Return the expression that constructs the step type mapped to `.name(args...)`
in the `@reference` DSL. `escaped_args` are `esc`'d Julia expressions ready
to splice into the returned constructor call. Each package registers a
`::Val{:name}` method for its own step types; none live in the kernel's reference
layer (`.point` / `.proj` register in the packages that own them). An unregistered
name is an error the builder raises.
"""
function build_reference_step end

"""
    match_reference_step(::Val{name}, hex, argpats, rest_success, bound,
                   gen_value_match, gen_path_match) -> (Expr, Set{Symbol})

Return `(match_branch, updated_bound)` for a `.name(patterns...)` pattern in the
`@reference_case` DSL. `hex` is the expression bound to the current step, and
`argpats` is the vector of parsed patterns (each a `PatValue` for a value
argument, or a `Vector{PatStep}` for a subpath argument). `gen_value_match`
and `gen_path_match` are helper callbacks the caller passes in so extension
methods can generate value/path patterns without reaching into kernel
internals: their signatures are

    gen_value_match(expr, pat, rest_success, bound) -> (Expr, Set{Symbol})
    gen_path_match(path_expr, patsteps, success, bound) -> (Expr, Set{Symbol})

Each package registers a `::Val{:name}` method for its own step types; none
live in the kernel's reference layer (`.point` / `.proj` register in the packages
that own them). An unregistered name is an error the matcher raises.
"""
function match_reference_step end

"""
    get_reference_step_subpath_args(::Val{name}) -> Tuple{Vararg{Int}}

The 1-based argument positions of a `.name(args...)` DSL step that are
**subpaths** (parsed as reference paths) rather than value expressions — `()`
unless a step type says otherwise, i.e. every argument is a value. A step type
whose surface syntax takes a subpath argument at position `n` registers `(n,)`
here, so neither DSL parser needs to name the step. Consulted by
both the `@reference_case` pattern parser and the `@reference` / `@reference_step`
construction parser.
"""
function get_reference_step_subpath_args end
