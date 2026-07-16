# Fragment of `ReferenceModule` — the kernel's **step vocabulary**: the concrete
# `ReferenceStep` subtypes (`RangeReference`, `FieldReference`, `TypeReference`),
# the `Position` value a cursor step evaluates to, the `ReferenceTypeMismatch` a
# failed checkpoint throws, and the cell-transparent navigation helpers the steps
# descend with.
#
# Each step type is self-contained: its struct, `show`, `==`, and its `step_kind` /
# `evaluate_step` seam methods sit together, the same way a step type owned by a
# higher package packages itself (`PointReference.jl`, `ProjectionReference.jl`,
# `TextSpanReference.jl`). The abstract `ReferenceStep` and the seam generics
# are declared in `Interface.jl`; the paths these steps are threaded onto live in
# `ReferencePath.jl`.

# ── Cell-transparent navigation ───────────────────────────────────────────

# Cells are transparent to reference navigation: a step that lands on a cell
# descends into its value, via `unwrap_cell`. Element and range access must do
# this too, not just field access — otherwise a step into a plain `Vector{Cell}`
# would stop on the raw cell and the rest of the path — recorded against the
# *unwrapped* value — would fail to resolve (and `annotate_reference_types` would
# stop adding type checkpoints there). `CellVector` already unwraps on
# `getindex`, so this is a no-op for it.

# ── RangeReference ────────────────────────────────────────────────────────

"""
    RangeReference(start, stop)

Unified sequence step.  Encodes:
- **Cursor position** (start == stop): a position between elements (0-based).
- **Single element**  (stop == start + 1): element at 1-based index `start + 1`.
- **Range**           (stop > start + 1): a multi-element selection.

All positions are 0-based boundaries.  For a collection with n elements,
valid boundaries are 0 to n.
"""
@cell_struct struct RangeReference <: ReferenceStep
    start::Int
    stop::Int
end

# `RangeReference(start, stop)` needs no explicit Int constructor: the
# `@cell_struct` inner constructor auto-wraps raw values into `Cell`s (and passes
# `Cell`s through). Same for `FieldReference`/`PointReference` below.

# ── Convenience step constructors ───────────────────────────────────────

"""
    ElementReference(index)

Construct a `RangeReference` representing the `index`-th element (1-based).
Equivalent to `RangeReference(index - 1, index)`.
"""
ElementReference(index::Int) = RangeReference(index - 1, index)

"""
    PositionReference(index)

Construct a `RangeReference` representing a cursor position (0-based).
Equivalent to `RangeReference(index, index)`.
"""
PositionReference(index::Int) = RangeReference(index, index)

# ── Predicates ────────────────────────────────────────────────────────────

"True when `r` encodes a single element (stop == start + 1)."
is_element_reference(r::RangeReference) = r.stop == r.start + 1

"True when `r` encodes a cursor position (start == stop)."
is_position_reference(r::RangeReference) = r.start == r.stop

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
Base.show(io::IO, p::Position) = print(io, "Position(", p.index, ")")

function Base.show(io::IO, s::RangeReference)
    if is_element_reference(s)
        print(io, "[", s.start + 1, "]")
    elseif is_position_reference(s)
        print(io, "{", s.start, "}")
    else
        print(io, "{", s.start, ":", s.stop, "}")
    end
end

Base.:(==)(a::RangeReference, b::RangeReference) = a.start == b.start && a.stop == b.stop

step_kind(::RangeReference) = :structural

# A zero-width cursor evaluates to a `Position` (a caret between elements); a
# single element / range descends into the item at start+1 (cell-transparent).
function evaluate_step(step::RangeReference, document)
    is_position_reference(step) && return Position(step.start)
    unwrap_cell(document[step.start + 1])
end

# ── FieldReference ────────────────────────────────────────────────────────

"""
    FieldReference(name)

References a named field of an object/record.
"""
@cell_struct struct FieldReference <: ReferenceStep
    name::String
end

# A `FieldReference` addresses a struct field by name — OR, when the document is
# an `AbstractDict`, a dict entry by key. A reference into a dict records the
# entry this way (the reference grammar has no dedicated key step), so navigation
# must follow it back. Dict keys may be stored as `String` or `Symbol`; the
# recorded name is the `string(key)`, so try it as both. Results are cell-unwrapped.
_has_field(document::AbstractDict, name) = haskey(document, name) || haskey(document, Symbol(name))
_has_field(document, name) = hasproperty(document, Symbol(name))

function _get_field(document::AbstractDict, name)
    haskey(document, name) && return unwrap_cell(document[name])
    unwrap_cell(document[Symbol(name)])
end
_get_field(document, name) = unwrap_cell(getfield(document, Symbol(name)))

function Base.show(io::IO, s::FieldReference)
    print(io, ".", s.name)
end

Base.:(==)(a::FieldReference, b::FieldReference) = a.name == b.name

step_kind(::FieldReference) = :structural

evaluate_step(step::FieldReference, document) =
    _get_field(document, step.name)

# ── TypeReference ─────────────────────────────────────────────────────────

"""
    TypeReference(type)

A **non-navigating type checkpoint**: asserts that the node reached so far is a
`type`. Evaluation does not descend — it stays on the current node and continues
with the rest of the path. The point of the checkpoint is *validity*: when a
stored path is replayed against a document whose structure has changed, a
`TypeReference` whose recorded `type` no longer matches the actual node marks the
**remaining path as invalid** (see [`evaluate_reference`](@ref),
[`get_valid_reference_prefix`](@ref), [`annotate_reference_types`](@ref)).

The match rule is `node isa type`. Checkpoints are normally created from
`typeof(node)` by [`annotate_reference_types`](@ref), so on an unchanged document
the assertion holds exactly; recording an abstract supertype is also tolerated.
"""
@cell_struct struct TypeReference <: ReferenceStep
    type::Any
end

"""
    ReferenceTypeMismatch(expected, actual)

Thrown by [`evaluate_reference`](@ref) when a [`TypeReference`](@ref) checkpoint
does not hold: the node reached is an `actual` but the checkpoint expected an
`expected`. Callers that replay possibly-stale references catch this specifically
to distinguish a structural mismatch from a genuine bug.
"""
struct ReferenceTypeMismatch <: Exception
    expected::Any
    actual::Any
end

Base.showerror(io::IO, e::ReferenceTypeMismatch) =
    print(io, "ReferenceTypeMismatch: expected node of type ", e.expected,
          ", got ", e.actual)

function Base.show(io::IO, s::TypeReference)
    print(io, "::", s.type)
end

Base.:(==)(a::TypeReference, b::TypeReference) = a.type === b.type

step_kind(::TypeReference) = :checkpoint

function evaluate_step(step::TypeReference, document)
    document isa step.type ||
        throw(ReferenceTypeMismatch(step.type, typeof(document)))
    document
end

# ── Cross-type step equality ──────────────────────────────────────────────

Base.:(==)(::ReferenceStep, ::ReferenceStep) = false
