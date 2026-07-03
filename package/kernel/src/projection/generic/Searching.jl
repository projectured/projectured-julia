"""
    SearchingProjectionModule

Domain-independent projection that walks an arbitrary input document recursively
and collects every object owning a field whose string value matches a `Regex`.
The output is a flat `CellVector` of the matched objects, in pre-order. A seen
set keyed by object identity makes the walk safe on cyclic or shared structure.

Where `FilteringProjection` keeps a shallow subset of one collection's direct
elements, `SearchingProjection` performs a deep recursive search of the whole
document tree and gathers matches from anywhere inside it.
"""
module SearchingProjectionModule

import ..ProjectionApiModule: print_document, map_reference_forward, map_reference_backward, Projection
import ..IoMapApiModule: IoMap
import ..ReactiveModule: Cell, set_function!
import ..CollectionModule: CellVector
import ..DocumentApiModule: Document
import ..ReferenceModule: ReferencePath, EmptyReferencePath, ConcreteReferencePath,
                          FieldReference, ElementReference, append_reference, head, tail,
                          strip_reference_types
import ..ReferenceCaseModule: var"@reference_case"
export SearchingProjection, SearchingProjectionIoMap

# ── IoMap ─────────────────────────────────────────────────────────────────

struct SearchingProjectionIoMap <: IoMap
    projection::Any
    input::Any
    output::Any                          # CellVector of the matched objects
    match_paths::Vector{ReferencePath}   # input-root-relative path to each match
end

# ── Projection ────────────────────────────────────────────────────────────

"""
    SearchingProjection(pattern; field_match=<default>)

A generic projection that walks the input document recursively and collects
every `Document` object that has a field for which `field_match(name, value)`
returns `true`. The default `field_match` matches a field whose value is an
`AbstractString` matching `pattern`.

`pattern` may be a `Regex` or a `String` (compiled to a `Regex`).

# Example

    sp = SearchingProjection(r"foo")
    iomap = print_document(sp, nothing, document, PrinterContext())
    iomap.output   # CellVector of every object with a string field matching "foo"
"""
struct SearchingProjection <: Projection
    pattern::Regex
    field_match::Function
end

_default_field_match(pattern::Regex) =
    (_name, value) -> value isa AbstractString && occursin(pattern, value)

SearchingProjection(pattern::Regex; field_match::Function = _default_field_match(pattern)) =
    SearchingProjection(pattern, field_match)

SearchingProjection(pattern::AbstractString; kw...) =
    SearchingProjection(Regex(pattern); kw...)

# ── print_document ──────────────────────────────────────────────────────

function print_document(p::SearchingProjection, recursion, input, ctx)
    matches = Tuple{ReferencePath,Any}[]
    seen = Base.IdSet{Any}()
    _walk(p, input, EmptyReferencePath(), matches, seen)

    out_cells = Cell[Cell(obj) for (_, obj) in matches]
    output = CellVector(out_cells)
    iomap = SearchingProjectionIoMap(p, input, output,
        ReferencePath[path for (path, _) in matches])

    # Forward-project the input selection so the cursor lands on the matching
    # result when it points inside one. Lazy so the not-yet-needed `iomap`
    # closure is fine, and reactive on the input selection.
    set_function!(getfield(output, :selection), () -> begin
        sel = hasfield(typeof(input), :selection) ? input.selection : nothing
        sel === nothing && return nothing
        map_reference_forward(p, iomap, sel)
    end)

    iomap
end

# Two-argument convenience entry mirroring the editor's bare-call form.
print_document(p::SearchingProjection, input) =
    print_document(p, nothing, input, nothing)

# ── The recursive walk ────────────────────────────────────────────────────
# Pre-order DFS over the three structural shapes the codebase uses, building the
# input-root-relative path as it descends. The seen set (identity membership)
# visits each object at most once, breaking cycles and de-duplicating shared
# substructure. A `ListNode` is handled by the generic struct branch — its
# `value`/`prev`/`next` fields are ordinary `Document`-valued fields, so the
# seen set is what terminates the prev/next chain.

function _walk(p::SearchingProjection, node, path::ReferencePath, matches, seen)
    node isa Document || return
    node in seen && return
    push!(seen, node)

    if node isa CellVector
        # A bare collection is not itself an object with fields; only its
        # element objects can match. Address elements directly on the vector.
        for i in 1:length(node)
            _walk(p, node[i], append_reference(path, ElementReference(i)), matches, seen)
        end
        return
    end

    # Struct-shaped Document (including ListNode): test its own fields, then
    # recurse into every Document-valued field.
    _object_matches(p, node) && push!(matches, (path, node))

    for nm in fieldnames(typeof(node))
        nm === :selection && continue
        raw = getfield(node, nm)
        val = raw isa Cell ? raw[] : raw
        val isa Document || continue
        _walk(p, val, append_reference(path, FieldReference(string(nm))), matches, seen)
    end
    return
end

function _object_matches(p::SearchingProjection, node)
    for nm in fieldnames(typeof(node))
        nm === :selection && continue
        raw = getfield(node, nm)
        val = raw isa Cell ? raw[] : raw
        p.field_match(string(nm), val) && return true
    end
    return false
end

# ── Reference mapping ─────────────────────────────────────────────────────

function map_reference_forward(p::SearchingProjection, iomap::SearchingProjectionIoMap, reference)
    reference isa ReferencePath || return nothing
    stripped = strip_reference_types(reference)   # match the plain skeleton; selections are canonical
    # Choose the longest matching prefix so a selection inside a nested match
    # resolves to the most specific (deepest) result.
    best_j = 0
    best_rest = nothing
    best_len = -1
    for (j, mp) in enumerate(iomap.match_paths)
        rest = _strip_prefix(stripped, mp)
        rest === nothing && continue
        len = length(mp)
        if len > best_len
            best_len = len
            best_j = j
            best_rest = rest
        end
    end
    best_j != 0 && return ConcreteReferencePath(ElementReference(best_j), best_rest)
    # Fallback: a projection-introduced position (e.g. a structural delimiter
    # clicked by the user) has been wrapped in proj(SearchingProjection, inner)
    # by map_reference_backward's wildcard branch. Strip the wrapper so the
    # output CellVector carries the inner (collection-domain) reference as its
    # selection, letting the downstream NestingProjection/CollectionToSyntax
    # place a cursor at the nearest structural position.
    @invoke map_reference_forward(p::Projection, iomap, reference)
end

function map_reference_backward(p::SearchingProjection, iomap::SearchingProjectionIoMap, reference)
    @reference_case reference begin
        [j].rest... => begin
            (j < 1 || j > length(iomap.match_paths)) && return nothing
            _concat(iomap.match_paths[j], rest)
        end
        _ => @invoke map_reference_backward(p::Projection, iomap, reference)
    end
end

# ── Path helpers ──────────────────────────────────────────────────────────
# `is_prefix_of` is a *proper*-prefix boolean (excludes equality, no tail) and
# `append_reference` joins step varargs — neither covers "strip a path prefix,
# return the remaining tail" or "concatenate two paths", so these fill the gap.

_strip_prefix(ref::ReferencePath, ::EmptyReferencePath) = ref
_strip_prefix(::EmptyReferencePath, ::ConcreteReferencePath) = nothing
function _strip_prefix(ref::ConcreteReferencePath, prefix::ConcreteReferencePath)
    head(ref) == head(prefix) || return nothing
    _strip_prefix(tail(ref), tail(prefix))
end

_concat(::EmptyReferencePath, t::ReferencePath) = t
_concat(p::ConcreteReferencePath, t::ReferencePath) =
    ConcreteReferencePath(head(p), _concat(tail(p), t))

end # module
