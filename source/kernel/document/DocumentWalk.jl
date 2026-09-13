# Fragment of `DocumentModule` — the reflection walk over an arbitrary object
# graph, parameterized by how a visited node's *location* is named.
#
# There is exactly one traversal. It knows how to descend four shapes — a
# positional collection (`is_element_collection`), a dict, an array, and a struct
# read by `fieldnames` — how to stop (scalar leaves, `is_walk_opaque`, `maxdepth`),
# how to fold a scalar match up to its enclosing `Document`, and how to keep from
# looping. What it deliberately leaves open is how to *name* the node it is standing
# on: a caller that wants the matching *objects* names a node by the object itself,
# a caller that wants the *paths* names it by a location it builds up as it descends.
# Those location functions are the `DocumentWalk`'s parameters — supplied by the
# caller, not dispatched off a subtype — which is what lets the walk sit below the
# reference layer (whose `Reference` a caller passes back in as a location) while
# knowing nothing of it.

"""
    DocumentWalk(; locate_field, locate_element, initial, policy)

The parameters a [`walk_document`](@ref) runs under: how a visited node's
**location** is named, and how often a node may be visited. A location is whatever
these functions return — the object itself (the defaults, a value-collecting walk)
or a path built up as the walk descends.

  - `locate_field(location, name, child) -> location` — the location of `child`
    reached from `location` by struct field / dict key `name`.
  - `locate_element(location, index, child) -> location` — the location of `child`
    reached at 1-based `index` of a positional collection or array.
  - `initial(root) -> location` — the root's location (default: `root` itself).
  - `policy::Symbol` — the cycle rule (default `:once_per_object`):

      • `:once_per_object` — one visited set for the whole walk, so a node reachable
        by several paths is walked **once**; shared subtrees are not re-walked and
        cyclic graphs terminate.
      • `:once_per_path` — the visited set holds only the current path's ancestors,
        so **every distinct path** to a node is walked; a path that loops back
        through one of its own ancestors is dropped, keeping a cyclic graph finite.

    The two are not interchangeable: a location that *is* the object gains nothing
    from a second visit (same location), while a *path* location does — the same
    node reached two ways is two different places to put a cursor.

`DocumentWalk()` is the value-collecting walk (locations are the objects);
[`search_documents`](@ref) runs it.
"""
struct DocumentWalk
    locate_field::Function
    locate_element::Function
    initial::Function
    policy::Symbol
end
DocumentWalk(; locate_field = (location, name, child) -> child,
               locate_element = (location, index, child) -> child,
               initial = root -> root,
               policy = :once_per_object) =
    DocumentWalk(locate_field, locate_element, initial, policy)

# A node is a walk leaf — nothing to descend into — when it is a scalar Julia
# value or an opaque document (see `is_walk_opaque`).
is_walk_leaf(x) = x === nothing || x isa Number || x isa AbstractString ||
                  x isa Symbol || x isa Char || is_walk_opaque(x)

# The string form of a leaf, for a String/Regex query. Struct and collection
# nodes have none, so they never match one.
_walk_string(x::AbstractString) = x
_walk_string(x::Symbol)         = string(x)
_walk_string(x::Number)         = string(x)
_walk_string(x::Char)           = string(x)
_walk_string(::Any)             = nothing

"""
    make_string_predicate(q::Union{AbstractString,Regex}) -> predicate

Turn a `String` (substring) or `Regex` into a walk predicate matching any *leaf*
node whose string form contains / matches it. Struct and collection nodes have
no string form and so never match — pass a predicate to match on type or shape.
"""
make_string_predicate(q::AbstractString) = x -> (t = _walk_string(x); t !== nothing && occursin(q, t))
make_string_predicate(q::Regex)          = x -> (t = _walk_string(x); t !== nothing && occursin(q, t))

"""
    walk_document(walk::DocumentWalk, obj, predicate;
                  include_selection=false, maxdepth=64, raw=false) -> Vector

Walk any object graph and return the **location** of every match, as `walk`
defines locations.

By default the results are **document-scoped**: a match on a raw scalar (a
String / Number / Bool leaf) folds up to the nearest enclosing `Document`, so
every location addresses a selectable node. A predicate matching a `Document`
directly reports that document. A scalar match with no enclosing document is
dropped. Pass `raw=true` to report the location of the **exact matched node**
instead, scalars included.

Each location is reported at most once. How often a *node* is visited is
`walk.policy`'s business. `include_selection` includes `selection` fields in the
walk. `maxdepth` bounds recursion for structures that are never the *same* object
— an infinite lazy list whose nodes are generated fresh on demand — which the
visited set alone cannot stop.

`obj` need not be a document: the walk descends structs, arrays, and dicts alike.
"""
function walk_document(walk::DocumentWalk, obj, predicate;
                       include_selection::Bool=false, maxdepth::Int=64, raw::Bool=false)
    results = Any[]
    root = unwrap_cell(obj)
    _walk_document!(walk, results, IdDict{Any,Bool}(), root, predicate,
                    walk.initial(root), nothing, IdDict{Any,Bool}(),
                    include_selection, maxdepth, raw)
    results
end

# Enter `obj` under the walk's cycle rule. Returns the visited set the children
# should be walked with, or `nothing` to prune this node entirely.
#
# `:once_per_path` guards on `ismutable` because an immutable value has no stable
# identity to loop back through; `:once_per_object` does not, and so also collapses
# repeats of an identical immutable — which is what makes it report each *object*
# once rather than each occurrence.
function _enter_node(walk::DocumentWalk, obj, seen)
    if walk.policy === :once_per_path
        if ismutable(obj)
            haskey(seen, obj) && return nothing
            seen = copy(seen)
            seen[obj] = true
        end
        return seen
    else
        haskey(seen, obj) && return nothing
        seen[obj] = true
        return seen
    end
end

# `enclosing` is the location of the nearest enclosing `Document` (this node's own
# location when it is one); a folded (`raw=false`) scalar match is reported there.
# `reported` dedups by location identity — sibling scalars under one document share
# the same enclosing location object, so that document is reported once, while
# distinct locations are all kept.
function _walk_document!(walk, results, reported, obj, predicate, location, enclosing,
                         seen, include_selection, depth, raw)
    # Nothing dispatches on `enclosing`: it is pushed into `results::Vector{Any}`,
    # used as an `IdDict{Any, Bool}` key, and handed down. Every use is an `Any`
    # slot already, so specialising on it buys no speed — and costs a great deal
    # of compilation, because the walk then instantiates once per (child type,
    # enclosing type) PAIR rather than once per child type. Walking one demo page
    # produced 67 instantiations across 38 distinct children, `CellVector` alone
    # appearing under twelve different parents.
    #
    # The recursion is written out at each branch rather than through a `descend`
    # closure for the same reason, and it is the half that actually works: a
    # closure captures `here` and so carries the enclosing type in its own type,
    # which no declaration on the variable removes. Measured on a five-type tree,
    # the closure form compiled 16 instances, the closure with `here::Any` 14, and
    # this form 9.
    @nospecialize enclosing
    seen = _enter_node(walk, obj, seen)
    seen === nothing && return
    here = obj isa Document ? location : enclosing
    if (try predicate(obj) catch; false end)
        target = raw ? location : here
        if target !== nothing && !haskey(reported, target)
            push!(results, target); reported[target] = true
        end
    end
    depth <= 0 && return
    is_walk_leaf(obj) && return

    if is_element_collection(obj)
        for i in 1:length(obj)
            child = unwrap_cell(obj[i])
            _walk_document!(walk, results, reported, child, predicate,
                            walk.locate_element(location, i, child),
                            here, seen, include_selection, depth - 1, raw)
        end
    elseif obj isa AbstractDict
        # Walk a dict by its entries, not its `fieldnames` — the latter descends
        # into the hash table's internals, whose `Memory` buffers have undefined
        # slots. The key is the field name, which is how a dict entry is addressed.
        for (k, v) in obj
            child = unwrap_cell(v)
            _walk_document!(walk, results, reported, child, predicate,
                            walk.locate_field(location, k, child),
                            here, seen, include_selection, depth - 1, raw)
        end
    elseif obj isa AbstractArray
        for i in 1:length(obj)
            isassigned(obj, i) || continue
            child = unwrap_cell(obj[i])
            _walk_document!(walk, results, reported, child, predicate,
                            walk.locate_element(location, i, child),
                            here, seen, include_selection, depth - 1, raw)
        end
    else
        fnames = try fieldnames(typeof(obj)) catch; () end
        for fn in fnames
            (fn == :ref || (fn == :selection && !include_selection)) && continue
            isdefined(obj, fn) || continue
            child = unwrap_cell(getfield(obj, fn))
            _walk_document!(walk, results, reported, child, predicate,
                            walk.locate_field(location, fn, child),
                            here, seen, include_selection, depth - 1, raw)
        end
    end
end
