# Fragment of `ReferenceModule` — the reference **contract**: the `ReferenceStep`
# and `Reference` abstract types every reference value is built from (a `Reference`
# is what a document's `selection` field points to, or `nothing`), and the open
# generics higher packages add methods to. Nothing here carries a body — the kernel
# step types and their seam defaults live in `ReferenceStep.jl`, the path structure
# and algebra in `ReferencePath.jl`, path evaluation in `ReferenceEvaluation.jl`, and
# the two DSLs in `ReferenceCase.jl` / `ReferenceBuilder.jl`.

"""
    ReferenceStep

One step of an address: a field, an element, a range, or a check.

Use it when you build or read a path a step at a time. A structural step goes
one level down, into a field or an element; a checkpoint step stays where it is
and states what must be true there, which is what keeps a path honest while the
document changes.

# Example

    for step in reference
        get_reference_step_kind(step) === :structural && println(step)
    end

See also `Reference`, the whole path, `evaluate_reference_step`, which walks
one, and the guide `kernel/reference`.
"""
abstract type ReferenceStep end

"""
    Reference

The address of a place in a document: which field, which element, how deep.

Use it to name a place without holding what is there: a selection, the target of
an edit, the tab a verb opened. A reference stays meaningful while the document
changes around it, and a projection can carry it from what is held to what is
shown and back.

# Example

    place = @reference(document, rows[2].name)
    value = get_referenced_value(editor, place)

See also `ReferenceStep`, the one step it is built of, `get_selection`, and the
guide `kernel/reference`.

Abstract base type for a path into a document. Implemented as an
immutable linked list so that extending a path (going deeper) reuses
the existing tail — no copying required.
"""
abstract type Reference end

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

Take one step of an address, and answer what is there.

Use it to walk a path by hand, or to write a step of your own: every kind of
step answers for itself. A structural step answers the child it reaches and
throws when the document has no such place; a checkpoint answers the document it
was given, having checked what it states.

# Example

    child = evaluate_reference_step(step, document)

See also `Reference`, `ReferenceStep` and `get_reference_step_kind`.

Navigate through `step`. For a `:structural` step, return the descended
value (throws on descent failure). Some step types descend to a document
child (`FieldReferenceStep`, `RangeReferenceStep`); others descend to a synthetic
value that stands in for the reference target — a coordinate pair, a projection's
output path, a character range. For a `:checkpoint` step, return `document`
unchanged after asserting the invariant (throws on mismatch).
"""
function evaluate_reference_step end

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

# ── The step-matching seam (methods in ReferenceRules.jl) ──────────────

"""
    match_reference_step_value(::Val{name}, step, argpats, bindings,
                               match_value, match_path) -> bindings | nothing

Match a `.name(patterns...)` pattern against an actual `step` value, for the
`@reference_rules` interpreter. The **interpreted sibling** of
[`match_reference_step`](@ref), which generates a match branch for `@reference_case`
instead: an interpreter cannot use a codegen seam, so a step type that wants to appear
in a rules pattern registers both.

`argpats` is the vector of parsed patterns (a `PatValue` for a value argument, a
`Vector{PatStep}` for a subpath argument) and `bindings` the `Dict{Symbol,Any}`
accumulated so far. Return the bindings (updated in place is fine) on a match, or
`nothing`. `match_value` and `match_path` are the callbacks so extension methods match
value and subpath patterns without reaching into kernel internals:

    match_value(value, pat, bindings)      -> bindings | nothing
    match_path(path, patsteps, bindings)   -> bindings | nothing

Each package registers a `::Val{:name}` method for its own step types; none live in the
kernel's reference layer. An unregistered name is an error the matcher raises.
"""
function match_reference_step_value end
