"""
    ReferenceModule

The reference module provides path-like references into document trees,
implemented as an immutable reactive linked list of typed steps. Each step
descends one level by integer index, named field, projection-introduced
element, or pixel coordinate. The selection mechanism propagates paths
recursively, writing each suffix into the matching child Document's selection
cell so every node in the tree always holds the sub-path relevant to its
own subtree.

The module includes:
- **Reference steps**: `RangeReference` (unified sequence step with backward-compatible
  `ElementReference`/`PositionReference` constructors), `FieldReference`,
  `TypeReference`, `FunctionReference`, `ProjectionReference`, `PointReference`
- **Reference paths**: `ReferencePath` (abstract), `EmptyReferencePath`,
  `ConcreteReferencePath`
- **Functions**: `append_reference`, `evaluate_reference`, `is_valid_reference`

All reference steps and paths are immutable for safety, with reactive cells
for dynamic values.
"""
module ReferenceModule

import ..ReactiveModule: Cell
import ..DocumentModule: @document
export Reference, ReferenceStep, ElementReference, PositionReference, RangeReference, FieldReference, TypeReference, FunctionReference, ProjectionReference, PointReference, ReferencePath, EmptyReferencePath, ConcreteReferencePath, append_reference, evaluate_reference, is_valid_reference, collect_references,
       is_element_reference, is_position_reference, is_range_reference,
       IRangeReference, IFieldReference, IConcreteReferencePath, IPointReference,
       reference_equal, is_prefix_of

# ── ReferenceStep ─────────────────────────────────────────────────────

"""
    ReferenceStep

Abstract base type for reference steps. Each subtype describes how to
descend one level into a document structure.
"""
abstract type ReferenceStep end

"""
    RangeReference(start, stop)

Unified sequence step.  Encodes:
- **Cursor position** (start == stop): a position between elements (0-based).
- **Single element**  (stop == start + 1): element at 1-based index `start + 1`.
- **Range**           (stop > start + 1): a multi-element selection.

All positions are 0-based boundaries.  For a collection with n elements,
valid boundaries are 0 to n.
"""
@document struct RangeReference <: ReferenceStep
    start::Int
    stop::Int
end

RangeReference(start::Int, stop::Int) = RangeReference(Cell(start), Cell(stop))

# ── Backward-compatible constructors ─────────────────────────────────────

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

"True when `r` encodes a multi-element range (stop > start + 1)."
is_range_reference(r::RangeReference) = r.stop > r.start + 1


"""
    FunctionReference(f)

References the element produced by applying function `f`.
"""
struct FunctionReference <: ReferenceStep
    f::Any
end

"""
    FieldReference(name)

References a named field of an object/record.
"""
@document struct FieldReference <: ReferenceStep
    name::String
end

FieldReference(name::String) = FieldReference(Cell(name))

"""
    TypeReference(type)

References the element of a given type within a heterogeneous collection.
"""
struct TypeReference <: ReferenceStep
    type::Any
end

# ── ReferencePath (immutable linked list) ────────────────────────────────

"""
    ReferencePath

Abstract base type for a path into a document. Implemented as an
immutable linked list so that extending a path (going deeper) reuses
the existing tail — no copying required.
"""
abstract type ReferencePath end

"""
    EmptyReferencePath()

The empty reference path (root).
"""
struct EmptyReferencePath <: ReferencePath end

"""
    Reference

Union type for document selection fields: either `nothing` (no selection)
or a `ReferencePath` describing the selected location.
"""
const Reference = Union{Nothing, ReferencePath}

"""
    ConcreteReferencePath(head, tail)

A non-empty path: `head` is the current `Reference`,
`tail` is the remaining `ReferencePath`.

# Example

    path = ConcreteReferencePath(FieldReference("address"),
               ConcreteReferencePath(FieldReference("city"),
                   EmptyReferencePath()))
"""
@document struct ConcreteReferencePath <: ReferencePath
    head::ReferenceStep
    tail::ReferencePath
end

ConcreteReferencePath(head::ReferenceStep, tail::ReferencePath) =
    ConcreteReferencePath(Cell(head), Cell(tail))

"""
    ProjectionReference(projection, output_path)

A reference step that points to an element introduced by a projection — for
example, a delimiter that exists in the output but has no direct counterpart
in the input domain. The `output_path` describes where within the projection's
output the reference points.
"""
struct ProjectionReference <: ReferenceStep
    projection::Any
    output_path::ReferencePath
end

"""
    PointReference(x, y)

References a point within the current element by pixel coordinates relative
to that element's origin.
"""
@document struct PointReference <: ReferenceStep
    x::Int
    y::Int
end

PointReference(x::Int, y::Int) = PointReference(Cell(x), Cell(y))

# Whole-element ("tree") selection is not a distinct reference step: it is just
# a path that terminates *at* the element, i.e. an `EmptyReferencePath`. The one
# node holding `∅` in its `selection` cell is the wholly-selected one; its
# ancestors hold a non-empty path routing down to it, and its descendants hold
# `nothing`. `evaluate_reference(document, EmptyReferencePath())` already returns
# the element itself, so no marker step is needed.

# ── Convenience constructors ─────────────────────────────────────────────

ConcreteReferencePath(head::ReferenceStep) = ConcreteReferencePath(Cell(head), Cell(EmptyReferencePath()))

"""
    ReferencePath(steps::Reference...)

Build a `ReferencePath` from a sequence of reference steps (left = outermost).
"""
function ReferencePath(steps::ReferenceStep...)
    path = EmptyReferencePath()
    for i in length(steps):-1:1
        path = ConcreteReferencePath(steps[i], path)
    end
    path
end

# ── Accessors ────────────────────────────────────────────────────────────

Base.isempty(::EmptyReferencePath) = true
Base.isempty(::ConcreteReferencePath) = false

head(p::ConcreteReferencePath) = p.head
tail(p::ConcreteReferencePath) = p.tail

Base.length(::EmptyReferencePath) = 0
Base.length(p::ConcreteReferencePath) = 1 + length(tail(p))

# ── Iteration ────────────────────────────────────────────────────────────

Base.iterate(::EmptyReferencePath) = nothing
Base.iterate(p::ConcreteReferencePath) = (head(p), tail(p))
Base.iterate(::EmptyReferencePath, ::ReferencePath) = nothing
Base.iterate(::ConcreteReferencePath, rest::ReferencePath) = iterate(rest)

Base.eltype(::Type{<:ReferencePath}) = ReferenceStep

# ── Display ──────────────────────────────────────────────────────────────

function Base.show(io::IO, s::RangeReference)
    if is_element_reference(s)
        print(io, "[", s.start + 1, "]")
    elseif is_position_reference(s)
        print(io, "{", s.start, "}")
    else
        print(io, "{", s.start, ":", s.stop, "}")
    end
end

function Base.show(io::IO, s::FunctionReference)
    print(io, "(", s.f, ")")
end

function Base.show(io::IO, s::FieldReference)
    print(io, ".", s.name)
end

function Base.show(io::IO, s::TypeReference)
    print(io, "{{", s.type, "}}")
end

function Base.show(io::IO, s::PointReference)
    print(io, "@(", s.x, ",", s.y, ")")
end

function Base.show(io::IO, ::EmptyReferencePath)
    print(io, "∅")
end

function Base.show(io::IO, p::ConcreteReferencePath)
    show(io, head(p))
    tail(p) isa EmptyReferencePath || show(io, tail(p))
end


# ── Equality ─────────────────────────────────────────────────────────────

Base.:(==)(a::RangeReference,      b::RangeReference)      = a.start  == b.start  && a.stop == b.stop
Base.:(==)(a::FieldReference,      b::FieldReference)      = a.name   == b.name
Base.:(==)(a::FunctionReference,   b::FunctionReference)   = a.f        === b.f
Base.:(==)(a::TypeReference,       b::TypeReference)       = a.type     === b.type
Base.:(==)(a::ProjectionReference, b::ProjectionReference) = a.projection === b.projection && a.output_path == b.output_path
Base.:(==)(a::PointReference,      b::PointReference)      = a.x == b.x && a.y == b.y
Base.:(==)(::ReferenceStep,        ::ReferenceStep)        = false

Base.:(==)(::EmptyReferencePath,   ::EmptyReferencePath)   = true
Base.:(==)(::EmptyReferencePath,   ::ConcreteReferencePath) = false
Base.:(==)(::ConcreteReferencePath, ::EmptyReferencePath)  = false
Base.:(==)(a::ConcreteReferencePath, b::ConcreteReferencePath) =
    head(a) == head(b) && tail(a) == tail(b)

"""
    reference_equal(a, b)

Structural equality of two reference paths.
"""
reference_equal(a::ReferencePath, b::ReferencePath) = a == b

"""
    is_prefix_of(a, b)

Return `true` if reference path `a` is a proper prefix of `b` (i.e. `a` is
strictly shorter and matches the leading steps of `b`).
"""
is_prefix_of(::EmptyReferencePath, ::EmptyReferencePath) = false
is_prefix_of(::EmptyReferencePath, ::ConcreteReferencePath) = true
is_prefix_of(::ConcreteReferencePath, ::EmptyReferencePath) = false
is_prefix_of(a::ConcreteReferencePath, b::ConcreteReferencePath) =
    head(a) == head(b) && is_prefix_of(tail(a), tail(b))

# ── Path construction helpers ────────────────────────────────────────────

"""
    append_reference(base::ReferencePath, steps::Reference...) -> ReferencePath

Return a new `ReferencePath` formed by appending `steps` to the end of
`base`. The first step in `steps` becomes the direct successor of the last
step already in `base`.
"""
function append_reference(base::EmptyReferencePath, steps...)
    isempty(steps) && return base
    ConcreteReferencePath(steps[1], append_reference(EmptyReferencePath(), steps[2:end]...))
end

function append_reference(base::ConcreteReferencePath, steps...)
    ConcreteReferencePath(base.head, append_reference(tail(base), steps...))
end

# ── Reference validation ─────────────────────────────────────────────────

"""
    is_valid_reference(obj)

Check if `obj` is a valid reference step or reference path.

Returns `true` if `obj` is a subtype of `Reference` or `ReferencePath`,
and for `ConcreteReferencePath`, recursively validates that the head and
tail cells contain valid reference steps and paths.

# Examples

```julia
is_valid_reference(PositionReference(1))  # true
is_valid_reference(FieldReference("name"))  # true
is_valid_reference(EmptyReferencePath())  # true
is_valid_reference("not a reference")  # false
is_valid_reference(42)  # false
```
"""
is_valid_reference(::ReferenceStep) = true
is_valid_reference(::EmptyReferencePath) = true

function is_valid_reference(obj::ConcreteReferencePath)
    # Recursively validate head and tail
    try
        head_step = obj.head
        tail_path = obj.tail
        return is_valid_reference(head_step) && is_valid_reference(tail_path)
    catch
        return false  # Cell evaluation failed or contains invalid data
    end
end

is_valid_reference(::Any) = false

# ── Reference evaluation ─────────────────────────────────────────────────

"""
    evaluate_reference(document, path::ReferencePath)

Navigate into `document` by following each step in `path` in order.
Returns the sub-document reached at the end of the path.
"""
function evaluate_reference(document, ::EmptyReferencePath)
    document
end

function evaluate_reference(document, path::ConcreteReferencePath)
    step = path.head
    rest = path.tail
    child = if step isa RangeReference
        if is_element_reference(step)
            document[step.start + 1]
        else
            # cursor / range — treat as element access at start+1 when possible
            document[step.start + 1]
        end
    elseif step isa FieldReference
        f = getfield(document, Symbol(step.name))
        f isa Cell ? f[] : f
    elseif step isa FunctionReference
        step.f(document)
    else
        error("Unsupported reference step: $(typeof(step))")
    end
    evaluate_reference(child, rest)
end

# ── Reference collection ─────────────────────────────────────────────────────

"""
    collect_references(document, search_value) -> Vector{ReferencePath}

Search the document tree for all occurrences of `search_value` and return their
reference paths. This is useful for finding all locations where a specific value
appears in the document.

The function recursively traverses the document structure, handling both Cell-wrapped
and unwrapped values, and collects reference paths for all matches.

Returns a vector of `ReferencePath` objects for all matches, or an empty vector if
no matches are found.
"""
function collect_references(document, search_value)
    try
        results = ReferencePath[]
        _search_document(document, EmptyReferencePath(), search_value, results)
        return results
    catch e
        @error "Error collecting references" exception = e
        return ReferencePath[]
    end
end

function _search_document(node, current_path, search_value, results)
    # Check if current node matches
    try
        if hasfield(typeof(node), :value) && getfield(node, :value) isa Cell
            if getfield(node, :value)[] == search_value
                push!(results, current_path)
                return
            end
        elseif node == search_value
            push!(results, current_path)
            return
        end
    catch
    end

    # Skip non-document types
    node isa Union{AbstractString, Number, Bool, Nothing, Symbol} && return
    node isa ReferencePath && return

    # Use reflection to recursively search all fields
    T = typeof(node)
    isstructtype(T) || return
    for fname in fieldnames(T)
        fval = getfield(node, fname)
        field_path = append_reference(current_path, FieldReference(string(fname)))
        if fval isa Cell
            try
                _search_document(fval[], field_path, search_value, results)
            catch
            end
        elseif !(fval isa Union{AbstractString, Number, Bool, Nothing, Symbol}) && !(fval isa ReferencePath)
            # Try to iterate as a collection
            iterated = false
            try
                r = iterate(fval)
                if r !== nothing
                    iterated = true
                    idx = 1
                    while r !== nothing
                        (elem, state) = r
                        elem_path = append_reference(field_path, RangeReference(idx - 1, idx))
                        _search_document(elem, elem_path, search_value, results)
                        idx += 1
                        r = iterate(fval, state)
                    end
                end
            catch
            end
            # If not iterable, recurse as struct
            if !iterated && isstructtype(typeof(fval))
                _search_document(fval, field_path, search_value, results)
            end
        end
    end
end

end # module
