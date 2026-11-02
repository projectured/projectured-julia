# Fragment of `ReferenceModule` — the reference **contract**: the `ReferenceStep`
# and `Reference` abstract types every reference value is built from (a `Reference`
# is what a document's `selection` field points to, or `nothing`), and the open
# generics higher packages add methods to. Nothing here carries a body — the kernel
# step types and their `get_reference_step_kind` and `evaluate_reference_step`
# methods live in `ReferenceStep.jl`, the path structure and algebra in
# `ReferencePath.jl`, and path evaluation in `ReferenceEvaluation.jl`. The defaults
# of the DSL seams live with their DSLs: `build_reference_step` in
# `ReferenceBuilder.jl`, `match_reference_step` in `ReferenceCase.jl`,
# `match_reference_step_value` in `ReferenceRules.jl`, and
# `get_reference_step_subpath_args` in `ReferenceSyntax.jl`.

"""
    ReferenceStep

One step of an address: a field, an element, a range, or a step that a higher
package adds.

Use it to build or read a path a step at a time. A step goes one level
down, into a field or an element, or to a value that stands for the place, such
as a coordinate or a range of characters. The type that keeps a path honest while
the document changes sits on each node of the path, not in a step.

A step type defines `==` by value and a `hash` that agrees with it, because a
`Reference` compares and hashes by its steps. A step of a type that defines no
`==` equals only itself.

# Example

    references_1 = search_references(document_1, "Overview")
    steps_1 = collect(references_1[1])

See also `Reference`, the whole path, `search_references`, which finds paths, and
the guide `kernel/reference`.

For the assistant.
"""
abstract type ReferenceStep end

"""
    Reference

The address of a place in a document: which field, which element, how deep.

Use it to name a place without holding what is there: a selection, or the target
of an edit. A reference stays meaningful while the document
changes around it, and a projection can carry it from what is held to what is
shown and back.

A path is a linked list. A new node in front of a path reuses its tail, and
`extend_reference`, which appends at the far end, builds a new node for each node
of the path.

# Example

    references_1 = search_references(document_1, "Overview")
    part_1 = evaluate_reference(document_1, references_1[1])
    longer_1 = extend_reference(references_1[1], step_1)

See also `ReferenceStep`, the one step it is built of, `search_references`,
`evaluate_reference`, `extend_reference` and the guide `kernel/reference`.

For the assistant.
"""
abstract type Reference end

"""
    get_reference_step_kind(step) -> Symbol

Classify a reference step. A step type answers `:structural`: the step descends
to a child or to a synthetic value. Every step type answers for itself, beside
its `evaluate_reference_step`, and there is no default. No kernel walker reads
the kind. A `:structural` step must be evaluatable under the "types always
present" invariant.
"""
function get_reference_step_kind end

"""
    evaluate_reference_step(step, document) -> child

Take one step of an address, and answer what is there.

Use it to walk a path by hand, or to write a step of your own: every kind of
step answers for itself. A step answers the child it reaches, and throws when
the document has no such place.

# Example

    child = evaluate_reference_step(step, document)

See also `Reference`, `ReferenceStep` and `get_reference_step_kind`.

Navigate through `step`. For a `:structural` step, return the descended
value (throws on descent failure). Some step types descend to a document
child (`FieldReferenceStep`, `RangeReferenceStep`); others descend to a synthetic
value that stands in for the reference target — a coordinate pair, a projection's
output path, a character range.
"""
function evaluate_reference_step end

"""
    has_reference_step_child(step, document) -> Bool

Whether `step` reaches a place in `document`, without the step.

Use it before `evaluate_reference_step` in a walk that answers "no child" for a
path that does not fit. A step that throws records a backtrace of the whole
stack, and a print deep in a tree pays that for each child. A field step answers
whether the struct has the field or the dict has the key, and an element step
whether the index is inside the length. A step of a kind with no method of its
own answers `true`, and its evaluation decides.

# Example

    child = has_reference_step_child(step, document) ?
            evaluate_reference_step(step, document) : nothing

See also `evaluate_reference_step` and `try_evaluate_reference`.
"""
function has_reference_step_child end

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
