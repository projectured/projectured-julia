# Fragment of `DocumentModule` — the reflection walk over an arbitrary object
# graph, and the seam that lets a caller decide what a visited node's *location*
# is.
#
# There is exactly one traversal. It knows how to descend four shapes — a
# positional collection (`is_element_collection`), a dict, an array, and a struct
# read by `fieldnames` — how to stop (scalar leaves, `is_opaque`, `maxdepth`), how
# to fold a scalar match up to its enclosing `Document`, and how to keep from
# looping. What it deliberately does *not* know is how to *name* the node it is
# standing on: that is the one thing its two callers disagree about, and it is
# what `DocumentWalk` abstracts.
#
# A caller that wants the matching *objects* names a node by the object itself. A
# caller that wants the *paths* to them names it by a `ReferencePath` — but
# reference paths live a layer above this one, so the walk cannot build them. The
# seam is what keeps the walk below the reference layer while still serving it
# (AR-FRAMEWORKS-SINK: the lower layer declares the open generic, the higher layer adds the
# method, and dispatch is the registration).

"""
    DocumentWalk

The strategy of a [`walk_document`](@ref): what a visited node's **location** is,
and how often a node may be visited.

Implement it by subtyping and adding [`child_field_location`](@ref) and
[`child_element_location`](@ref) — the two ways the walk descends. Override
[`initial_location`](@ref) if the root's location is not the root object itself,
and [`visit_policy`](@ref) to choose the cycle rule.
"""
abstract type DocumentWalk end

"""
    initial_location(walk, root) -> location

The location of the walk's root. Defaults to `root` itself — correct for a walk
whose locations *are* the objects; a path-valued walk overrides it with its empty
path.
"""
initial_location(::DocumentWalk, root) = root

"""
    child_field_location(walk, location, name, child) -> location

The location of `child`, reached from `location` by the field (or dict key)
`name`. `name` is a `Symbol` for a struct field and the raw key for a dict entry.
"""
function child_field_location end

"""
    child_element_location(walk, location, index, child) -> location

The location of `child`, reached from `location` at 1-based `index` — an element
of a positional collection or an array.
"""
function child_element_location end

"""
    visit_policy(walk) -> Symbol

How often the walk may visit one node.

  • `:once_per_object` (the default) — a single visited set for the whole walk, so
    a node reachable by several paths is walked **once**. Shared subtrees are not
    re-walked; cyclic graphs terminate.

  • `:once_per_path` — the visited set holds only the *current path's ancestors*,
    so **every distinct path** to a node is walked. A path that loops back through
    one of its own ancestors is dropped, which is what keeps a cyclic graph (a
    doubly-linked list's `prev`/`next`) finite.

The two are not interchangeable. A location that is the object itself has nothing
to gain from walking a shared node twice — the second visit reports the same
location. A location that is a *path* does: the same node reached two ways is two
different places to put a cursor, so both must be reported.
"""
visit_policy(::DocumentWalk) = :once_per_object

# A node is a walk leaf — nothing to descend into — when it is a scalar Julia
# value or an opaque document (see `is_opaque`).
is_walk_leaf(x) = x === nothing || x isa Number || x isa AbstractString ||
                  x isa Symbol || x isa Char || is_opaque(x)

# The textual form of a leaf, for a String/Regex query. Struct and collection
# nodes have none, so they never match one.
_walk_text(x::AbstractString) = x
_walk_text(x::Symbol)         = string(x)
_walk_text(x::Number)         = string(x)
_walk_text(x::Char)           = string(x)
_walk_text(::Any)             = nothing

"""
    text_query(q::Union{AbstractString,Regex}) -> predicate

Turn a `String` (substring) or `Regex` into a walk predicate matching any *leaf*
node whose textual form contains / matches it. Struct and collection nodes have
no textual form and so never match — pass a predicate to match on type or shape.
"""
text_query(q::AbstractString) = x -> (t = _walk_text(x); t !== nothing && occursin(q, t))
text_query(q::Regex)          = x -> (t = _walk_text(x); t !== nothing && occursin(q, t))

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
[`visit_policy`](@ref)'s business. `include_selection` includes `selection`
fields in the walk. `maxdepth` bounds recursion for structures that are never the
*same* object — an infinite lazy list whose nodes are generated fresh on demand —
which the visited set alone cannot stop.

`obj` need not be a document: the walk descends structs, arrays, and dicts alike.
"""
function walk_document(walk::DocumentWalk, obj, predicate;
                       include_selection::Bool=false, maxdepth::Int=64, raw::Bool=false)
    results = Any[]
    root = unwrap_cell(obj)
    _walk_document!(walk, results, IdDict{Any,Bool}(), root, predicate,
                    initial_location(walk, root), nothing, IdDict{Any,Bool}(),
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
    if visit_policy(walk) === :once_per_path
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

    descend(child, child_location) =
        _walk_document!(walk, results, reported, child, predicate, child_location,
                        here, seen, include_selection, depth - 1, raw)

    if is_element_collection(obj)
        for i in 1:length(obj)
            child = unwrap_cell(obj[i])
            descend(child, child_element_location(walk, location, i, child))
        end
    elseif obj isa AbstractDict
        # Walk a dict by its entries, not its `fieldnames` — the latter descends
        # into the hash table's internals, whose `Memory` buffers have undefined
        # slots. The key is the field name, which is how a dict entry is addressed.
        for (k, v) in obj
            child = unwrap_cell(v)
            descend(child, child_field_location(walk, location, k, child))
        end
    elseif obj isa AbstractArray
        for i in 1:length(obj)
            isassigned(obj, i) || continue
            child = unwrap_cell(obj[i])
            descend(child, child_element_location(walk, location, i, child))
        end
    else
        fnames = try fieldnames(typeof(obj)) catch; () end
        for fn in fnames
            (fn == :ref || (fn == :selection && !include_selection)) && continue
            isdefined(obj, fn) || continue
            child = unwrap_cell(getfield(obj, fn))
            descend(child, child_field_location(walk, location, fn, child))
        end
    end
end
