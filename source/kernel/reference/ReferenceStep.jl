# Fragment of `ReferenceModule` — the kernel's **step vocabulary**: the concrete
# `ReferenceStep` subtypes (`RangeReferenceStep`, `FieldReferenceStep`, `TypeReferenceStep`),
# the `Position` value a cursor step evaluates to, the `ReferenceTypeMismatchException` a
# failed checkpoint throws, and the cell-transparent navigation helpers the steps
# descend with.
#
# Each step type is self-contained: its struct, `show`, `==`, and its `get_reference_step_kind` /
# `evaluate_reference_step` seam methods sit together, the same way a step type owned by a
# higher package packages itself. The abstract `ReferenceStep` and the seam generics
# are declared in `ReferenceInterface.jl`; the paths these steps are threaded onto live in
# `ReferencePath.jl`.

# ── Cell-transparent navigation ───────────────────────────────────────────

# Cells are transparent to reference navigation: a step that lands on a cell
# descends into its value, via `unwrap_cell`. Element and range access must do
# this too, not just field access — otherwise a step into a plain `Vector{Cell}`
# would stop on the raw cell and the rest of the path — recorded against the
# *unwrapped* value — would fail to resolve (and `annotate_reference_types` would
# stop adding type checkpoints there). `CellVector` already unwraps on
# `getindex`, so this is a no-op for it.

# ── RangeReferenceStep ────────────────────────────────────────────────────────

"""
    RangeReferenceStep(start, stop)

Unified sequence step.  Encodes:
- **Cursor position** (start == stop): a position between elements (0-based).
- **Single element**  (stop == start + 1): element at 1-based index `start + 1`.
- **Range**           (stop > start + 1): a multi-element selection.

All positions are 0-based boundaries.  For a collection with n elements,
valid boundaries are 0 to n.
"""
@document [C, M] struct RangeReferenceStep <: ReferenceStep
    start::Int
    stop::Int
end

# `[C, M]`, bare name = the C (reactive) layout: a step IS mutated in the UI —
# an index shifts and the change propagates — so every existing constructor
# call keeps building the reactive step, unchanged. The M layout is the plain
# VALUE the simulator's run path constructs (designators, sites, hashing,
# matching); it never propagates because the run path never mutates a step.
# Every method below dispatches on the `A…` stem, so the two layouts share
# `show`/`==`/`hash`/the seam methods, and a C step equals an M step that
# holds the same numbers. Same for `FieldReferenceStep` and
# `TypeReferenceStep` below.

# ── Convenience step constructors ───────────────────────────────────────

"""
    ElementReferenceStep(index)

Construct a `RangeReferenceStep` representing the `index`-th element (1-based).
Equivalent to `RangeReferenceStep(index - 1, index)`.
"""
ElementReferenceStep(index::Int) = RangeReferenceStep(index - 1, index)

"""
    PositionReferenceStep(index)

Construct a `RangeReferenceStep` representing a cursor position (0-based).
Equivalent to `RangeReferenceStep(index, index)`.
"""
PositionReferenceStep(index::Int) = RangeReferenceStep(index, index)

# The M (plain-layout) conveniences, for a hot path that builds VALUE steps.
MElementReferenceStep(index::Int) = MRangeReferenceStep(index - 1, index)
MPositionReferenceStep(index::Int) = MRangeReferenceStep(index, index)

# ── Predicates ────────────────────────────────────────────────────────────

"True when `r` encodes a single element (stop == start + 1)."
is_element_reference_step(r::ARangeReferenceStep) = r.stop == r.start + 1

"True when `r` encodes a cursor position (start == stop)."
is_position_reference_step(r::ARangeReferenceStep) = r.start == r.stop

"""
    Position(index)

The value a zero-width cursor step (`{k}`) evaluates to: a caret *between*
elements at 0-based `index`, not a document node. Every reference is
evaluatable (the types-always-present invariant), and a cursor's "empty
something" is a `Position`. A path terminating at a cursor therefore records
`Position` as its terminal type (`…{k}::Position`), and
`evaluate_reference` of such a path returns `Position(k)` — a signal that the
target is a caret, distinct from a document node reached by a structural step.
"""
struct Position
    index::Int
end

Base.:(==)(a::Position, b::Position) = a.index == b.index
Base.hash(p::Position, h::UInt) = hash(p.index, hash(:Position, h))
Base.show(io::IO, p::Position) = print(io, "Position(", p.index, ")")

function Base.show(io::IO, s::ARangeReferenceStep)
    if is_element_reference_step(s)
        print(io, "[", s.start + 1, "]")
    elseif is_position_reference_step(s)
        print(io, "{", s.start, "}")
    else
        print(io, "{", s.start, ":", s.stop, "}")
    end
end

Base.:(==)(a::ARangeReferenceStep, b::ARangeReferenceStep) = a.start == b.start && a.stop == b.stop
Base.hash(s::ARangeReferenceStep, h::UInt) =
    hash(s.stop, hash(s.start, hash(:RangeReferenceStep, h)))

get_reference_step_kind(::ARangeReferenceStep) = :structural

# A zero-width cursor evaluates to a `Position` (a caret between elements); a
# single element / range descends into the item at start+1 (cell-transparent).
function evaluate_reference_step(step::ARangeReferenceStep, document)
    is_position_reference_step(step) && return Position(step.start)
    unwrap_cell(document[step.start + 1])
end

# A string counts characters, not bytes: `[i]` is the i-th character, as every
# text offset of a reference counts. `nextind(document, 0, i)` is the byte index
# of that character, and an index past the last character does not resolve.
function evaluate_reference_step(step::ARangeReferenceStep, document::AbstractString)
    is_position_reference_step(step) && return Position(step.start)
    document[nextind(document, 0, step.start + 1)]
end

# ── FieldReferenceStep ────────────────────────────────────────────────────────

"""
    FieldReferenceStep(name)

References a named field of an object/record.
"""
@document [C, M] struct FieldReferenceStep <: ReferenceStep
    name::String
end

# A `FieldReferenceStep` addresses a struct field by name — OR, when the document is
# an `AbstractDict`, a dict entry by key. A reference into a dict records the
# entry this way (the reference grammar has no dedicated key step), so navigation
# must follow it back. Dict keys may be stored as `String` or `Symbol`; the
# recorded name is the `string(key)`, so try it as both. Results are cell-unwrapped.
function _get_field(document::AbstractDict, name)
    haskey(document, name) && return unwrap_cell(document[name])
    unwrap_cell(document[Symbol(name)])
end
_get_field(document, name) = unwrap_cell(getfield(document, Symbol(name)))

function Base.show(io::IO, s::AFieldReferenceStep)
    print(io, ".", s.name)
end

Base.:(==)(a::AFieldReferenceStep, b::AFieldReferenceStep) = a.name == b.name
Base.hash(s::AFieldReferenceStep, h::UInt) = hash(s.name, hash(:FieldReferenceStep, h))

get_reference_step_kind(::AFieldReferenceStep) = :structural

evaluate_reference_step(step::AFieldReferenceStep, document) =
    _get_field(document, step.name)

# ── TypeReferenceStep ─────────────────────────────────────────────────────────

"""
    TypeReferenceStep(type)

A **build-time token** for a node type. `@reference` writes a `::T` as this step,
and so does the template engine, and [`fold_reference_types`](@ref) at once folds it
into the `type` of the node that the next step stands on. A path that is stored,
walked or matched records its types on its nodes and holds no such step. The step
has no `get_reference_step_kind` and no `evaluate_reference_step`: `evaluate_reference`
throws a `MethodError` at such a step, and `get_valid_reference_prefix` cuts the
path there.
"""
@document [C, M] struct TypeReferenceStep <: ReferenceStep
    type::Any
end

"""
    ReferenceTypeMismatchException(expected, actual)

Thrown by [`evaluate_reference`](@ref) when the type that a node of the path records
does not hold: the node reached is an `actual` but the path expected an
`expected`. Callers that replay possibly-stale references catch this specifically
to distinguish a structural mismatch from a genuine bug.
"""
struct ReferenceTypeMismatchException <: Exception
    expected::Any
    actual::Any
end

Base.showerror(io::IO, e::ReferenceTypeMismatchException) =
    print(io, "ReferenceTypeMismatchException: expected node of type ", e.expected,
          ", got ", e.actual)

function Base.show(io::IO, s::ATypeReferenceStep)
    print(io, "::", s.type)
end

Base.:(==)(a::ATypeReferenceStep, b::ATypeReferenceStep) = a.type === b.type
Base.hash(s::ATypeReferenceStep, h::UInt) = hash(s.type, hash(:TypeReferenceStep, h))

# ── Cross-type step equality ──────────────────────────────────────────────

Base.:(==)(::ReferenceStep, ::ReferenceStep) = false

# ── Hashing ───────────────────────────────────────────────────────────────
#
# **A step compares by value, so it hashes by value.** The C layout is
# mutable, and a mutable struct hashes by identity unless it says otherwise —
# which would make two equal steps land in different buckets and lose every
# lookup of a rebuilt reference. Each `hash` above therefore sits beside the
# `==` it must agree with, and each mixes in its own type name, because two
# steps of different kinds are never equal whatever they hold.
#
# The `type` field a step may carry is NOT part of either: it is not part of
# `==` here and so it is not part of `hash`. `is_reference_equal` is the strict
# comparison that does read it, and it is a different question.
