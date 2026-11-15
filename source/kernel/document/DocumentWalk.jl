# Fragment of `DocumentModule` — the reflection walk over an arbitrary object
# graph, and the walk that says which nodes it visits and in what order.
#
# There is exactly one traversal. It knows how to descend four shapes — a
# positional collection (`is_element_collection`), a dict, an array, and a struct
# read by `fieldnames` — how to stop (scalar leaves, `maxdepth`, `maxvisits`), how
# to fold a scalar match up to its enclosing `Document`, and how to keep from
# looping. The `DocumentWalk` decides which nodes it enters, in what order, and how
# often a shared node is visited. The caller decides how a match is named: the
# object itself, or its path as a chain of steps, which the reference layer turns
# into a `Reference`. So the walk sits below the reference layer and knows nothing
# of it.

"""
    DocumentWalk(; is_opaque = is_walk_opaque, enter_field = is_field_entered,
                   descend = (parent, child) -> true, order = (node, steps) -> steps,
                   policy = :once_per_object)

The rules of a walk of the documents: which nodes it visits, in what order, and how
often it visits a node that two places share. A search takes a walk, so a caller
that needs another route through the documents passes one.

  - `is_opaque(node) -> Bool` — a node whose parts the walk does not enter. The
    default asks the node's own rule, `is_walk_opaque`.
  - `enter_field(node, name) -> Bool` — whether the walk enters the field `name` of
    `node`, a struct or a document. It decides before the read, so a field that it
    refuses is not read, and a computed field is not computed. The default,
    `is_field_entered`, asks the node's own rule, `is_field_walked`, and never
    enters the mouse target or the selection.
  - `descend(parent, child) -> Bool` — whether the walk enters `child`, decided by
    its value. The walk does not match or walk a child that it does not enter. The
    root is always entered, and the default enters every child.
  - `order(node, steps) -> steps` — the steps from `node` to its children, in the
    order that the walk visits them: the positions of a collection, the keys of a
    dict, or the field names of a struct. The default keeps their own order.
  - `policy` — how often the walk visits a node that two places share:

      • `:once_per_object` (default) — once, at the first path that reaches it; a
        shared part is not walked again, and a cyclic graph ends.
      • `:once_per_path` — once for each path; a path that comes back through one
        of its own nodes is dropped, so a cyclic graph ends. A node that many
        places share, such as a row that the old versions of undo share, costs a
        visit at each place.

Use it to search the documents along a route of your own, such as a route that
also enters the selection.

# Example

    walk_1 = DocumentWalk(; enter_field = (node, name) -> name === :selection || is_field_entered(node, name))
    search_documents(editor.document, "Ada"; walk = walk_1)

See also `search_documents`, `search_references` and `is_field_entered`.

For the assistant.
"""
struct DocumentWalk
    is_opaque::Function
    enter_field::Function
    descend::Function
    order::Function
    policy::Symbol

    function DocumentWalk(is_opaque, enter_field, descend, order, policy::Symbol)
        policy in (:once_per_object, :once_per_path) ||
            throw(ArgumentError("DocumentWalk: `policy` is :once_per_object or :once_per_path, got :$policy"))
        new(is_opaque, enter_field, descend, order, policy)
    end
end

DocumentWalk(; is_opaque = is_walk_opaque, enter_field = is_field_entered, descend = _enter_every_child,
               order = _keep_walk_order, policy::Symbol = :once_per_object) =
    DocumentWalk(is_opaque, enter_field, descend, order, policy)

"""
    is_field_entered(node, name) -> Bool

Whether the default walk enters the field `name` of `node`: a field that the node's
own rule, `is_field_walked`, allows, apart from the mouse target and the
selection, which hold where the person points and what the person selected, not
content.

Use it to build a walk that changes one rule and keeps the rest.

# Example

    walk_1 = DocumentWalk(; enter_field = (node, name) -> node isa UndoBuffer || is_field_entered(node, name))

See also `DocumentWalk`.

For the assistant.
"""
function is_field_entered end

is_field_entered(node, name) = name !== :mouse_target && name !== :selection && is_field_walked(node, name)

# A node is a walk leaf — nothing to descend into — when it is a scalar Julia
# value or a node that the walk does not open.
_is_walk_leaf(walk::DocumentWalk, x) = x === nothing || x isa Number || x isa AbstractString ||
                                       x isa Symbol || x isa Char || walk.is_opaque(x)

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
- `maxvisits` — the most nodes that the walk visits, or `nothing` for no bound;
  `is_visit_limit_reached` says that the walk stopped there, so parts that it did
  not visit can hold more matches.
- `unreadable_count` — how many matches a search of places left out, because the
  path that the walk built to them does not read back to them, such as a match
  inside a dict whose keys are types.

Use it to read why a search answered fewer matches than the document holds.

# Example

    found_1 = search_documents(document_1, "temperature")
    limits_1 = found_1.limits
    is_search_complete(found_1)

See also `DocumentMatches`, `search_documents` and `is_search_complete`.

For the assistant.
"""
struct WalkLimits
    limit::Union{Int,Nothing}
    is_limit_reached::Bool
    maxdepth::Int
    depth_stop_count::Int
    background::Bool
    provisional_count::Int
    maxvisits::Union{Int,Nothing}
    is_visit_limit_reached::Bool
    unreadable_count::Int
end

"""
    DocumentMatches(matches, limits)

The answer of a walk of the documents: `matches`, in the order that the walk found
them, and the [`WalkLimits`](@ref) that the walk ran under, with what each one left
out. It is a vector of the matches, so a caller indexes, iterates and counts it as a
vector. Its summary, the first line of its display, names each limit that stopped
the walk and the keyword that lifts it, so a person and the assistant see that an
answer is not complete.

Use it to read the matches of a search and to see whether the search is complete.

# Example

    matches_1 = search_documents(editor.document, "temperature")
    is_search_complete(matches_1)

See also `search_documents` and `is_search_complete`.

For the assistant.
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
answer, the depth stopped at no part, the bound of visits did not stop the walk,
the walk read no value that a task still computes, and no match was left out for a
path that does not read back.

Use it to know whether a search found everything before you act on its answer.

# Example

    is_search_complete(search_documents(editor.document, "temperature"))

See also `DocumentMatches`.

For the assistant.
"""
function is_search_complete end

function is_search_complete(found::DocumentMatches)
    limits = found.limits
    !limits.is_limit_reached && limits.depth_stop_count == 0 && limits.provisional_count == 0 &&
        !limits.is_visit_limit_reached && limits.unreadable_count == 0
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
    limits.is_visit_limit_reached &&
        print(io, ". The search stopped after it visited ", limits.maxvisits,
              " nodes: pass `maxvisits = nothing` to search further")
    limits.provisional_count > 0 &&
        print(io, ". ", limits.provisional_count,
              limits.provisional_count == 1 ? " value that a task still computes was taken as it is" :
                                              " values that a task still computes were taken as they are",
              ": pass `background = true` to wait for them")
    limits.unreadable_count > 0 &&
        print(io, ". ", limits.unreadable_count, limits.unreadable_count == 1 ? " match was" : " matches were",
              " left out, because the path to ", limits.unreadable_count == 1 ? "it" : "them",
              " does not read back")
    nothing
end

# What a walk counts while it runs: the matches that it may still find before its
# limit, the parts that its depth left out, the values still to come that it read
# as they are, and the nodes that it visited.
mutable struct _WalkCounts
    limit::Int
    depth_stop_count::Int
    provisional_count::Int
    maxvisits::Int
    visit_count::Int
    is_visit_limit_reached::Bool
end

# Whether the walk stops: it found one match more than its limit, or it came to a
# node after it visited as many as it may.
_is_walk_stopped(results, counts::_WalkCounts) = length(results) > counts.limit || counts.is_visit_limit_reached

"""
    walk_document(walk::DocumentWalk, obj, predicate;
                  paths = false, maxdepth = 64, limit = 100, maxvisits = 100_000, raw = false,
                  enter_matches = true, on_error = (object, exception) -> false,
                  background = false) -> DocumentMatches

Walk any object graph along `walk` and return every match, as a
[`DocumentMatches`](@ref) that says which limit stopped the walk. `walk` decides
which nodes the walk enters, in what order, and how often it visits a node that
two places share.

A match is the matched object itself. With `paths = true` it is the path to the
object instead: a chain of steps from the root, `()` for the root and
`parent => step` below it, where `step` is the name of a field (a `Symbol`), the
key of a dict entry (a `String`, or a `Symbol` key as it is) or a 1-based position
(an `Int`). A dict entry whose key is not a name, a symbol or a string, has the
step `nothing`: no path reads such an entry back. The walk never prints a key. The
reference layer turns a chain into a `Reference`.

By default the results are **document-scoped**: a match on a raw scalar (a
String / Number / Bool leaf) folds up to the nearest enclosing `Document`, so
every match is a selectable node. A predicate matching a `Document`
directly reports that document. A scalar match with no enclosing document is
dropped. Pass `raw=true` to report the **exact matched node** instead, scalars
included.

Each match is reported at most once. `maxdepth` bounds recursion for structures
that are never the *same* object — an infinite lazy list whose nodes are generated
fresh on demand — which the visited set alone cannot stop.

The walk has three bounds, each with a default that keeps a walk of a large
document small, and the answer says when one stopped it (`is_search_complete`):

- `limit` is the most matches that the walk answers: 100 by default.
  `limit = nothing` answers every match. A caller that needs every match, such as
  a save that visits every node of a kind, passes `limit = nothing`.
- `maxdepth` is how deep the walk goes: 64 by default.
- `maxvisits` is the most nodes that the walk visits: 100,000 by default, so a
  walk of a window, which has some thousands of nodes, ends in a fraction of a
  second, and a walk of a large table stops. `maxvisits = nothing` visits every
  node. With `limit = nothing` the default is `nothing` too, because a caller that
  asks for every match asks for the whole walk.

`enter_matches = false` stops the walk at each match: it reports the match and
reads no part of it. A caller that gathers items, each with parts of its own,
passes it, so that a computation that gathers the items reads no cell inside an
item, and a change inside one item does not make it gather again.

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

Use it to walk a document with a walk of your own, such as `DocumentWalk()`, which answers the matching objects.

# Example

    matches_1 = walk_document(DocumentWalk(), document_1, value -> value isa String; limit = 10)

See also `search_documents` and `search_references`.
"""
function walk_document end

function walk_document(walk::DocumentWalk, obj, predicate;
                       paths::Bool = false, maxdepth::Int = 64,
                       limit::Union{Integer,Nothing} = 100,
                       maxvisits::Union{Integer,Nothing} = limit === nothing ? nothing : 100_000,
                       raw::Bool = false, enter_matches::Bool = true,
                       on_error = _count_as_no_match, background::Bool = false)
    limit === nothing || limit >= 0 || throw(ArgumentError("walk_document: `limit` is a count, got $limit"))
    maxvisits === nothing || maxvisits >= 1 ||
        throw(ArgumentError("walk_document: `maxvisits` is a count of at least 1, got $maxvisits"))
    results = Any[]
    # The walk looks for one match more than its limit, so it knows that the limit
    # cut the answer.
    counts = _WalkCounts(limit === nothing ? typemax(Int) - 1 : Int(limit), 0, 0,
                         maxvisits === nothing ? typemax(Int) : Int(maxvisits), 0, false)
    with(_IS_BACKGROUND_WORK_ALLOWED => background) do
        root = _read_walked(obj, background, counts)
        _walk_document!(walk, results, IdDict{Any,Bool}(), root,
                        _GuardedPredicate(predicate, on_error),
                        paths ? () : root, nothing, IdDict{Any,Bool}(),
                        maxdepth, raw, paths, enter_matches, background, counts)
    end
    is_limit_reached = length(results) > counts.limit
    is_limit_reached && pop!(results)
    DocumentMatches(results, WalkLimits(limit === nothing ? nothing : Int(limit), is_limit_reached, maxdepth,
                                        counts.depth_stop_count, background, counts.provisional_count,
                                        maxvisits === nothing ? nothing : Int(maxvisits),
                                        counts.is_visit_limit_reached, 0))
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
_has_walk_children(walk::DocumentWalk, obj) =
    is_element_collection(obj) ? length(obj)::Int > 0 :
    obj isa Union{AbstractDict,AbstractArray} ? !isempty(obj) :
    any(name -> walk.enter_field(obj, name), fieldnames(typeof(obj)))

_enter_every_child(_, _) = true

_keep_walk_order(_, steps) = steps

_count_as_no_match(_, _) = false

# The location of `child`, one `step` below `location`: the child itself, or with
# `paths` the chain of steps to it.
_locate_walked(paths::Bool, location, step, child) = paths ? Pair{Any,Any}(location, step) : child

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
# when it found one match more than its limit, or when it comes to a node after it
# visited as many as `maxvisits` allows.
function _walk_document!(walk::DocumentWalk, results, reported, obj, predicate, location, enclosing,
                         seen, depth, raw, paths, enter_matches, background, counts)
    # Nothing dispatches on `enclosing`: it is pushed into `results::Vector{Any}`,
    # used as an `IdDict{Any, Bool}` key, and handed down. Every use is an `Any`
    # slot already, so specialising on it buys no speed — and costs a great deal
    # of compilation, because the walk then instantiates once per (child type,
    # enclosing type) PAIR rather than once per child type. Walking one demo page
    # produced 67 instantiations across 38 distinct children, `CellVector` alone
    # appearing under twelve different parents. A location that is a path is the
    # same kind of `Any` slot.
    #
    # The recursion is written out at each branch rather than through one closure
    # that recurses, for the same reason, and it is the half that actually works: a
    # closure captures `here` and so carries the enclosing type in its own type,
    # which no declaration on the variable removes. Measured on a five-type tree,
    # the closure form compiled 16 instances, the closure with `here::Any` 14, and
    # this form 9.
    @nospecialize enclosing
    _is_walk_stopped(results, counts) && return
    if counts.visit_count >= counts.maxvisits
        counts.is_visit_limit_reached = true
        return
    end
    counts.visit_count += 1
    leaf = _is_walk_leaf(walk, obj)
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
        enter_matches || return
    end
    leaf && return
    if depth <= 0
        _has_walk_children(walk, obj) && (counts.depth_stop_count += 1)
        return
    end

    if is_element_collection(obj)
        for i in walk.order(obj, 1:(length(obj)::Int))
            _is_walk_stopped(results, counts) && return
            child = _read_walked(obj[i], background, counts)
            walk.descend(obj, child) || continue
            _walk_document!(walk, results, reported, child, predicate, _locate_walked(paths, location, i, child),
                            here, seen, depth - 1, raw, paths, enter_matches, background, counts)
        end
    elseif obj isa AbstractDict
        # Walk a dict by its entries, not its `fieldnames` — the latter descends
        # into the hash table's internals, whose `Memory` buffers have undefined
        # slots. A key that is a name is the field name of its entry, which is how a
        # path addresses a dict entry. Another key names nothing that a path reads
        # back, and its print can be as large as the key, so it gives no step.
        for key in walk.order(obj, keys(obj))
            _is_walk_stopped(results, counts) && return
            child = _read_walked(obj[key], background, counts)
            walk.descend(obj, child) || continue
            step = key isa Symbol ? key : key isa AbstractString ? String(key) : nothing
            _walk_document!(walk, results, reported, child, predicate, _locate_walked(paths, location, step, child),
                            here, seen, depth - 1, raw, paths, enter_matches, background, counts)
        end
    elseif obj isa AbstractArray
        for i in walk.order(obj, 1:length(obj))
            isassigned(obj, i) || continue
            _is_walk_stopped(results, counts) && return
            child = _read_walked(obj[i], background, counts)
            walk.descend(obj, child) || continue
            _walk_document!(walk, results, reported, child, predicate, _locate_walked(paths, location, i, child),
                            here, seen, depth - 1, raw, paths, enter_matches, background, counts)
        end
    else
        for name in walk.order(obj, fieldnames(typeof(obj)))
            walk.enter_field(obj, name) || continue
            isdefined(obj, name) || continue
            _is_walk_stopped(results, counts) && return
            child = _read_walked(getfield(obj, name), background, counts)
            walk.descend(obj, child) || continue
            _walk_document!(walk, results, reported, child, predicate, _locate_walked(paths, location, name, child),
                            here, seen, depth - 1, raw, paths, enter_matches, background, counts)
        end
    end
end
