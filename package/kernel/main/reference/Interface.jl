# Fragment of `ReferenceModule` — the reference **contract**: the two abstract
# types every reference value is built from (`ReferenceStep`, `ReferencePath`),
# the `Reference` union a document's selection field holds, and the open generics
# that higher packages add methods to. The concrete kernel step types live in
# `ReferenceStep.jl`, the path structure in `ReferencePath.jl`, and the DSLs that
# consume the `dsl_*` seams in `ReferenceCase.jl` / `ReferenceBuilder.jl`.
#
# A step type defined in a higher package (`PointReference`, `ProjectionReference`,
# `TextRectangularReference`) subtypes `ReferenceStep` and registers itself by
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
# `step_kind` (classification) and `evaluate_step` (one-level navigation).
# The three path walkers (`evaluate_reference`,
# `get_valid_reference_prefix`, `annotate_reference_types`) all dispatch
# through this seam — a new step type living in a higher package registers
# its methods at its own definition site and needs no edits here.

"""
    step_kind(step) -> Symbol

Classify a reference step: `:structural` (descends to a child or
synthetic value) or `:checkpoint` (stays on the current node, asserts an
invariant). The default is `:structural` — every step must be evaluatable
under the "types always present" invariant; a step type that doesn't opt
into `:checkpoint` is expected to implement `evaluate_step`.
"""
step_kind(::ReferenceStep) = :structural

"""
    evaluate_step(step, document) -> child

Navigate through `step`. For a `:structural` step, return the descended
value (throws on descent failure). Some step types descend to a document
child (`FieldReference`, `RangeReference`); others descend to a synthetic
value that stands in for the reference target (`PointReference` returns a
coordinate pair, `ProjectionReference` returns the projection's output
path, `TextRectangularReference` returns the character range). For a
`:checkpoint` step, return `document` unchanged after asserting the
invariant (throws on mismatch).
"""
function evaluate_step end

# ── DSL seams ─────────────────────────────────────────────────────────────
# The `@reference` / `@step` construction DSL and the `@reference_case`
# pattern-matching DSL both reach a step type through these generics, so
# neither parser names a step type it does not own. A step type registers a
# `::Val{:name}` method for its `.name(args...)` surface syntax in the package
# that defines it; the kernel registers none — its own steps (`.field`, `[i]`,
# `{k}`, `::T`) are built-in grammar, not seam entries.

"""
    dsl_build_step(::Val{name}, escaped_args...) -> Expr

Return the expression that constructs the step type mapped to `.name(args...)`
in the `@reference` DSL. `escaped_args` are `esc`'d Julia expressions ready
to splice into the returned constructor call. Each package registers a
`::Val{:name}` method for its own step types; none live in the kernel's reference
layer (`.point` / `.proj` register in the packages that own them).
"""
function dsl_build_step end

dsl_build_step(::Val{n}, args...) where {n} =
    error("no `dsl_build_step(::Val{$(QuoteNode(n))}, …)` method registered — `.$(n)(…)` is not a known @reference step")

"""
    dsl_match_step(::Val{name}, hex, argpats, rest_success, bound,
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
that own them).
"""
function dsl_match_step end

dsl_match_step(::Val{n}, hex, argpats, rest_success, bound, gvm, gpm) where {n} =
    error("no `dsl_match_step(::Val{$(QuoteNode(n))}, …)` method registered — `.$(n)(…)` is not a known @reference_case step")

"""
    dsl_step_subpath_args(::Val{name}) -> Tuple{Vararg{Int}}

The 1-based argument positions of a `.name(args...)` DSL step that are
**subpaths** (parsed as reference paths) rather than value expressions. Default
`()` — every argument is a value. A step type whose surface syntax takes a
subpath argument at position `n` registers `(n,)` here, so neither DSL parser
needs to name the step. Consulted by
both the `@reference_case` pattern parser and the `@reference` / `@step`
construction parser.
"""
function dsl_step_subpath_args end
dsl_step_subpath_args(::Val) = ()
