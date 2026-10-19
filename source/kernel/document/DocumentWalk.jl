# Fragment of `DocumentModule` — the reflection walk over an arbitrary object
# graph, parameterized by how a visited node's *location* is named.
#
# There is exactly one traversal. It knows how to descend four shapes — a
# positional collection (`is_element_collection`), a dict, an array, and a struct
# read by `fieldnames` — how to stop (scalar leaves, `is_walk_opaque`, `maxdepth`,
# and a child that the caller's `descend` refuses), how to fold a scalar match up
# to its enclosing `Document`, and how to keep from looping. What it leaves open
# is how to *name* the node it is standing on, and which children it enters: a
# caller that wants the matching *objects* names a node by the object itself, a
# caller that wants the *paths* names it by a location it builds up as it descends.
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
_is_walk_leaf(x) = x === nothing || x isa Number || x isa AbstractString ||
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
    WalkLimits

The limits that a walk of the documents ran under, and what each one left out:

- `limit` — the most matches that the walk answers, or `nothing` for every match;
  `is_limit_reached` says that more matches exist, which the walk did not answer.
- `maxdepth` — how deep the walk goes; `depth_stop_count` is how many parts at that
  depth the walk did not enter, which can hold more matches.
- `background` — whether the walk starts background work; `provisional_count` is
  how many values that a task still computes the walk took as they are, which it
  does when it starts no work. A match can be in the final value of such a value.
"""
struct WalkLimits
    limit::Union{Int,Nothing}
    is_limit_reached::Bool
    maxdepth::Int
    depth_stop_count::Int
    background::Bool
    provisional_count::Int
end

"""
    DocumentMatches(matches, limits)

The answer of a walk of the documents: `matches`, in the order that the walk found
them, and the [`WalkLimits`](@ref) that the walk ran under, with what each one left
out. It is a vector of the matches, so a caller indexes, iterates and counts it as a
vector. Its summary, the first line of its display, names each limit that stopped
the walk and the keyword that lifts it, so a person and the assistant see that an
answer is not complete.

# Example

    matches_1 = search_documents(editor.document, "temperature")
    is_search_complete(matches_1)

See also `search_documents` and `is_search_complete`.
"""
struct DocumentMatches{T} <: AbstractVector{T}
    matches::Vector{T}
    limits::WalkLimits
end

Base.size(found::DocumentMatches) = size(found.matches)
Base.getindex(found::DocumentMatches, index::Int) = found.matches[index]
Base.setindex!(found::DocumentMatches, value, index::Int) = (found.matches[index] = value)
Base.IndexStyle(::Type{<:DocumentMatches}) = IndexLinear()

"""
    is_search_complete(found::DocumentMatches) -> Bool

Whether no limit of the walk left a match out: the limit of matches did not cut the
answer, the depth stopped at no part, and the walk read no value that a task still
computes.

Use it to know whether a search found everything before you act on its answer.

# Example

    is_search_complete(search_documents(editor.document, "temperature"))

See also `DocumentMatches`.
"""
function is_search_complete end

function is_search_complete(found::DocumentMatches)
    limits = found.limits
    !limits.is_limit_reached && limits.depth_stop_count == 0 && limits.provisional_count == 0
end

# The count of the matches, then each limit that stopped the walk, with the
# keyword that lifts it.
function Base.summary(io::IO, found::DocumentMatches)
    count = length(found)
    print(io, count, count == 1 ? " match" : " matches")
    limits = found.limits
    limits.is_limit_reached &&
        print(io, ". The search stopped at its limit of ", limits.limit,
              " matches, and more exist: pass `limit = nothing` to find all")
    limits.depth_stop_count > 0 &&
        print(io, ". The search did not enter ", limits.depth_stop_count,
              limits.depth_stop_count == 1 ? " part" : " parts", " below its depth of ", limits.maxdepth,
              ": pass a larger `maxdepth` to search them")
    limits.provisional_count > 0 &&
        print(io, ". ", limits.provisional_count,
              limits.provisional_count == 1 ? " value that a task still computes was taken as it is" :
                                              " values that a task still computes were taken as they are",
              ": pass `background = true` to wait for them")
    nothing
end

# What a walk counts while it runs: the matches that it may still find before its
# limit, the parts that its depth left out, and the values still to come that it
# read as they are.
mutable struct _WalkCounts
    limit::Int
    depth_stop_count::Int
    provisional_count::Int
end

"""
    walk_document(walk::DocumentWalk, obj, predicate;
                  include_selection=false, maxdepth=64, limit=100, raw=false,
                  descend=(parent, child) -> true,
                  on_error=(object, exception) -> false,
                  background=false) -> DocumentMatches

Walk any object graph and return the **location** of every match, as `walk`
defines locations, as a [`DocumentMatches`](@ref) that says which limit stopped the
walk.

By default the results are **document-scoped**: a match on a raw scalar (a
String / Number / Bool leaf) folds up to the nearest enclosing `Document`, so
every location addresses a selectable node. A predicate matching a `Document`
directly reports that document. A scalar match with no enclosing document is
dropped. Pass `raw=true` to report the location of the **exact matched node**
instead, scalars included.

Each location is reported at most once. How often a *node* is visited is
`walk.policy`'s business. `include_selection` includes `selection` fields in the
walk; a `mouse_target` field is never walked. `maxdepth` bounds recursion for
structures that are never the *same* object — an infinite lazy list whose nodes
are generated fresh on demand — which the visited set alone cannot stop.

`limit` is the most matches that the walk answers: 100 by default, so a search in a
large document stays small. `limit = nothing` answers every match. A caller that
needs every match, such as a save that visits every node of a kind, passes
`limit = nothing`. The answer says when the limit cut it, when the depth left a part
out, and when the walk took values that a task still computes as they are
(`is_search_complete`).

`descend(parent, child) -> Bool` returns whether the walk enters `child` from
`parent`. The walk does not match or walk a child that it does not enter. The
root is always entered, and the default enters every child. Pass one when the
matches can be only in some parts of the graph, so that the walk skips the
parts that can hold none, such as a type or a function held in a field. An
exception from `descend` goes to the caller.

`background` says whether the walk starts background work. A cell whose value
a task computes off the loop, a background cell, holds its last answer or its
default until its work is done. By default the walk takes that value as it is
and starts no work, so a walk over a large document reads no file and starts no
task. With `background = true` the walk waits for the final value of each
provisional cell that it reads (`complete_walked_cell`), so it can match inside
the values that a task computes; call it so only outside a computation.

`on_error(object, exception) -> Bool` runs when `predicate` throws an ordinary
exception on `object`, and its answer is the match of that object. The walk
visits objects of every type, so a predicate that reads a field of one type
throws on the others; the default counts that as no match. Pass
`on_error = (object, exception) -> throw(exception)` to let the exception go to
the caller. An exception that is not a fault (`is_fault_exception`) never
reaches `on_error`: it ends the walk.

`obj` need not be a document: the walk descends structs, arrays, and dicts alike.
"""
function walk_document(walk::DocumentWalk, obj, predicate;
                       include_selection::Bool=false, maxdepth::Int=64,
                       limit::Union{Integer,Nothing} = 100, raw::Bool=false,
                       descend = _enter_every_child, on_error = _count_as_no_match,
                       background::Bool = false)
    limit === nothing || limit >= 0 || throw(ArgumentError("walk_document: `limit` is a count, got $limit"))
    results = Any[]
    # The walk looks for one match more than its limit, so it knows that the limit
    # cut the answer.
    counts = _WalkCounts(limit === nothing ? typemax(Int) - 1 : Int(limit), 0, 0)
    with(_IS_BACKGROUND_WORK_ALLOWED => background) do
        root = _read_walked(obj, background, counts)
        _walk_document!(walk, results, IdDict{Any,Bool}(), root,
                        _GuardedPredicate(predicate, on_error),
                        walk.initial(root), nothing, IdDict{Any,Bool}(),
                        include_selection, maxdepth, raw, descend, background, counts)
    end
    is_limit_reached = length(results) > counts.limit
    is_limit_reached && pop!(results)
    DocumentMatches(results, WalkLimits(limit === nothing ? nothing : Int(limit), is_limit_reached, maxdepth,
                                        counts.depth_stop_count, background, counts.provisional_count))
end

# Whether a read may start background work now: false inside a walk that starts
# none.
const _IS_BACKGROUND_WORK_ALLOWED = ScopedValue(true)

"""
    is_background_work_allowed() -> Bool

Whether a read of a background cell may start its work now: `true`, except inside
a walk of the documents that starts no background work, which is the default of
`walk_document`, `search_documents` and `search_references`.
"""
is_background_work_allowed() = _IS_BACKGROUND_WORK_ALLOWED[]

"""
    complete_walked_cell(cell) -> value

The value of `cell` for a walk that starts background work (`background = true`):
the final value when the cell holds a value that a task still computes. The
default reads the cell. The editor answers it for a reactive cell: it waits for
the background work below the cell.
"""
complete_walked_cell(cell) = unwrap_cell(cell)

# The value of a field or an element for the walk. A walk that starts no
# background work counts each value that a task still computes, which it takes as
# it is.
function _read_walked(x, background::Bool, counts::_WalkCounts)
    x isa AbstractCell || return x
    background && return complete_walked_cell(x)
    value = unwrap_cell(x)
    is_cell_provisional(x) && (counts.provisional_count += 1)
    value
end

# Whether a node that the depth stops at has a part that the walk would enter.
_has_walk_children(obj) =
    is_element_collection(obj) ? length(obj)::Int > 0 :
    obj isa Union{AbstractDict,AbstractArray} ? !isempty(obj) :
    any(name -> name !== :mouse_target && name !== :selection, fieldnames(typeof(obj)))

_enter_every_child(_, _) = true

_count_as_no_match(_, _) = false

# The predicate of a walk with its answer for an exception: an exception that
# means stop goes on, and `on_error` answers for every other one.
struct _GuardedPredicate{P,E}
    predicate::P
    on_error::E
end

function (guarded::_GuardedPredicate)(object)
    try
        guarded.predicate(object)
    catch exception
        is_fault_exception(exception) || rethrow()
        guarded.on_error(object, exception)
    end
end

# Enter `obj` under the walk's cycle rule. Returns the visited set the children
# should be walked with, or `nothing` to prune this node entirely. A walk leaf
# does not come here: it has no children, so it cannot close a cycle, and two
# equal scalars in two documents are two matches.
#
# `:once_per_object` keeps one set for the whole walk, so it walks and reports
# each *object* once. `:once_per_path` keeps the ancestors of the current path, so
# it prunes only a path that comes back to one of them. It records every node,
# mutable or not: a `@document` cell layout is an immutable struct, and its
# `IdDict` key is the identity of its cells, so a `prev`/`next` loop ends there.
function _enter_node(walk::DocumentWalk, obj, seen)
    if walk.policy === :once_per_path
        haskey(seen, obj) && return nothing
        seen = copy(seen)
        seen[obj] = true
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
# All but `obj`, `location`, `enclosing`, `seen` and `depth` pass through
# unchanged, and the compile count below is measured on this form. The walk ends
# when it found one match more than its limit.
function _walk_document!(walk, results, reported, obj, predicate, location, enclosing,
                         seen, include_selection, depth, raw, descend, background, counts)
    # Nothing dispatches on `enclosing`: it is pushed into `results::Vector{Any}`,
    # used as an `IdDict{Any, Bool}` key, and handed down. Every use is an `Any`
    # slot already, so specialising on it buys no speed — and costs a great deal
    # of compilation, because the walk then instantiates once per (child type,
    # enclosing type) PAIR rather than once per child type. Walking one demo page
    # produced 67 instantiations across 38 distinct children, `CellVector` alone
    # appearing under twelve different parents.
    #
    # The recursion is written out at each branch rather than through one closure
    # that recurses, for the same reason, and it is the half that actually works: a
    # closure captures `here` and so carries the enclosing type in its own type,
    # which no declaration on the variable removes. Measured on a five-type tree,
    # the closure form compiled 16 instances, the closure with `here::Any` 14, and
    # this form 9.
    @nospecialize enclosing
    length(results) > counts.limit && return
    leaf = _is_walk_leaf(obj)
    if !leaf
        seen = _enter_node(walk, obj, seen)
        seen === nothing && return
    end
    here = obj isa Document ? location : enclosing
    if predicate(obj)
        target = raw ? location : here
        if target !== nothing && !haskey(reported, target)
            push!(results, target); reported[target] = true
        end
    end
    leaf && return
    if depth <= 0
        _has_walk_children(obj) && (counts.depth_stop_count += 1)
        return
    end

    if is_element_collection(obj)
        for i in 1:(length(obj)::Int)
            length(results) > counts.limit && return
            child = _read_walked(obj[i], background, counts)
            descend(obj, child) || continue
            _walk_document!(walk, results, reported, child, predicate,
                            walk.locate_element(location, i, child),
                            here, seen, include_selection, depth - 1, raw, descend, background, counts)
        end
    elseif obj isa AbstractDict
        # Walk a dict by its entries, not its `fieldnames` — the latter descends
        # into the hash table's internals, whose `Memory` buffers have undefined
        # slots. The key is the field name, which is how a dict entry is addressed.
        for (k, v) in obj
            length(results) > counts.limit && return
            child = _read_walked(v, background, counts)
            descend(obj, child) || continue
            _walk_document!(walk, results, reported, child, predicate,
                            walk.locate_field(location, k, child),
                            here, seen, include_selection, depth - 1, raw, descend, background, counts)
        end
    elseif obj isa AbstractArray
        for i in 1:length(obj)
            isassigned(obj, i) || continue
            length(results) > counts.limit && return
            child = _read_walked(obj[i], background, counts)
            descend(obj, child) || continue
            _walk_document!(walk, results, reported, child, predicate,
                            walk.locate_element(location, i, child),
                            here, seen, include_selection, depth - 1, raw, descend, background, counts)
        end
    else
        for fn in fieldnames(typeof(obj))
            fn == :mouse_target && continue
            fn == :selection && !include_selection && continue
            isdefined(obj, fn) || continue
            length(results) > counts.limit && return
            child = _read_walked(getfield(obj, fn), background, counts)
            descend(obj, child) || continue
            _walk_document!(walk, results, reported, child, predicate,
                            walk.locate_field(location, fn, child),
                            here, seen, include_selection, depth - 1, raw, descend, background, counts)
        end
    end
end
