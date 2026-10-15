# Fragment of `ReflectionModule`.
#
# A bounded shadow of an **arbitrary Julia object** — a live simulation engine, a
# model, anything that is not a `Document` and never will be.
#
# [`ReflectionModule`](@ref) needs a `Document` on both sides. The things one most
# wants to inspect are ordinary structs, so there is nothing to shadow: no shadow,
# no bound, no inspector. Hence this walk, which reflects an object into a tree of
# [`ReflectedNode`](@ref)s — label, kind, leaf value, children — and syncs that
# tree in place against the object, under the same [`SyncPolicy`](@ref).
#
# Everything bounded sync provides carries over unchanged, because the same policy
# and the same [`UnsyncedDocument`](@ref) marker are used: a node's `children` slot
# holds a marker while it is collapsed, `request_sync!` on that marker expands it
# one level on the next sync, a large field is capped with a tail marker, and the
# nodes a widget holds keep their identity across syncs.
#
# What it does *not* do is guess at presentation. A leaf's `value` is a short
# string and a node's `kind` is a type name; deciding what that should look like is
# the projection's business.
"""
    ReflectedNode(label, kind, value, children)

One node of a reflected object tree.

- `label` — where this node came from in its parent: a field name, an index, a key.
- `kind` — the type name of the object here.
- `value` — a short rendering, for a leaf; `nothing` for a composite.
- `children` — a `CellVector` of `ReflectedNode` when expanded, an
  [`UnsyncedDocument`](@ref) when collapsed, `nothing` for a leaf.

The three states of `children` are exactly the three the sync policy
distinguishes, which is why collapsing is just writing a marker there.
"""
@document struct ReflectedNode
    label::Any
    kind::Any
    value::Any
    children::Any
end

# ── disclosure, as an operation ───────────────────────────────────────────────

"""
    SetReflectedDisclosureOperation(changes)

Open or close reflected nodes. `changes` is a vector of `node => expanded` pairs.

The two directions are deliberately asymmetric, because the sync policy is:
collapsing is IMMEDIATE — the subtree is dropped behind a marker and stays
dropped — while expanding is a REQUEST, flagging the marker so the next
`sync_reflection!` fills it one level deeper. Opening a node therefore costs
nothing until something syncs.

This type exists so a projection's reader can stay pure (PAR-READER-IS-PURE): a
chevron click RETURNS this operation rather than writing the shadow itself, which
also makes disclosure undoable and scriptable like every other edit. Collapse is
the exact inverse of expand (PAR-INVERTIBLE-OPERATIONS).
"""
struct SetReflectedDisclosureOperation <: Operation
    changes::Vector{Pair{Any,Bool}}
end

function evaluate_operation(editor, op::SetReflectedDisclosureOperation)
    for (node, expanded) in op.changes
        if expanded
            node.children isa AUnsyncedDocument && request_sync!(node.children)
        elseif !(node.children isa AUnsyncedDocument)
            node.children = make_unsynced_marker(node.children)
        end
    end
end

# ── what counts as a leaf, and what a leaf shows ──────────────────────────────

"""
    is_reflection_leaf(x) -> Bool

Whether `x` is shown as a value rather than opened up. Numbers, strings, symbols,
functions and types are leaves however many fields they happen to have; anything
else is a leaf when it has no children to show.
"""
is_reflection_leaf(x) =
    x === nothing || x isa Number || x isa AbstractString || x isa Symbol ||
    x isa Char || x isa Function || x isa Type || x isa Enum ||
    reflect_child_count(x) == 0

"""
    get_reflection_value(x) -> String

A leaf's short rendering. Truncated, because a shadow of a live object will
happily contain a megabyte-long `repr` otherwise.
"""
function get_reflection_value(x)
    s = x isa AbstractString ? String(x) : sprint(show, x; context = :compact => true)
    length(s) <= 64 ? s : string(first(s, 61), "...")
end

"""
    reflect_child_count(x) -> Int
    reflect_child_pairs(x) -> iterator of `label => value`

The labelled children of `x`: indices for an array, keys for a dictionary, field
names for a struct. Extend both to teach the inspector about a type whose useful
structure is not its fields.

They are an **iterator and a count** rather than a vector because the point of a
cap is not to touch what it withholds. Building a thousand pairs to show the
first eight would put the cost back exactly where the bound was meant to remove
it — which is what the first version did, at 162 KB per sync.
"""
reflect_child_count(x) = length(_reflect_fieldnames(x))
reflect_child_count(x::AbstractArray) = length(x)
reflect_child_count(x::AbstractDict)  = length(x)
reflect_child_count(x::Tuple)         = length(x)
reflect_child_count(::Union{Number, AbstractString, Symbol, Char, Function, Type}) = 0

reflect_child_pairs(x) =
    (string(nm) => getproperty(x, nm) for nm in _reflect_fieldnames(x))

# `getproperty`, not `getfield`: a `@document` struct keeps every field in a
# `Cell`, and an inspector wants the value, not the box. Its trailing `selection`
# field is the document's own cursor slot — machinery, never content.
#
# The test is the FIELD and not the supertype. `Document` carries two jobs: it is
# the shape `@document` builds, and it is the bound an event argument is stored
# inline under, so `EventArgument <: Document` and every gate and every
# simulation module is a `Document` that never met the macro and holds no
# `selection`. Asking `isa Document` dropped a declared field from each of them.
#
# The two agree everywhere a document is one: the macro appends `selection` last,
# and an explicit one it refuses anywhere but last.
function _reflect_fieldnames(x)
    f = fieldnames(typeof(x))
    !isempty(f) && last(f) === :mouse_target && (f = f[1:end-1])
    !isempty(f) && last(f) === :selection ? f[1:end-1] : f
end
reflect_child_pairs(x::AbstractArray) = (string(i) => x[i] for i in eachindex(x))
reflect_child_pairs(x::AbstractDict)  = (string(k) => v for (k, v) in x)
reflect_child_pairs(x::Tuple)         = (string(i) => x[i] for i in eachindex(x))
reflect_child_pairs(::Union{Number, AbstractString, Symbol, Char, Function, Type}) =
    Pair{String, Any}[]

"""
    reflect_children(x) -> Vector{Pair{String, Any}}

Every child of `x`, materialised. A convenience for tests and small objects; the
walk itself takes only what it will show.
"""
reflect_children(x) = collect(reflect_child_pairs(x))

# `Vector{Int64}` rather than `Array`: a bare type name loses exactly the part a
# reader wants. Module qualifiers go the other way — `Foo.Bar.Baz` is noise in a
# label — and a deeply parameterised type has no useful tail.
#
# A document is the exception: every one of its type parameters is a cell kind,
# so `ACSimulationRun{Cell, Cell, Cell, Cell, Cell}` says nothing a reader wants.
# The **schema** name is what a reader wants, and `get_document_schema_name` answers
# it for every layout — `nameof` would say which layout it was handed.
function _kind_of(x)
    x isa Document && return string(get_document_schema_name(typeof(x)))
    s = replace(string(typeof(x)), r"[A-Za-z_][A-Za-z0-9_!]*\." => "")
    length(s) <= 48 ? s : string(first(s, 45), "...")
end

# ── building and syncing ──────────────────────────────────────────────────────

"""
    reflect_document(object, policy = DepthPolicy(1)) -> ReflectedNode

A fresh bounded shadow of `object`. Sync it afterwards with
[`sync_reflection!`](@ref) and the same policy.
"""
# @optional: the policy follows the object, as the depth the walk goes to; label
# is its chrome.
function reflect_document(object, policy::SyncPolicy = DepthPolicy(1); label = "")
    node = ReflectedNode(label, "", nothing, nothing)
    _sync_reflection!(node, object, policy, 0)
    node
end

"""
    sync_reflection!(node, object, policy = DepthPolicy(1)) -> node

Bring `node` up to date with `object`, stopping where `policy` says to. Nodes
already materialised keep their identity, so a widget holding one keeps holding
it; a `requested` marker in a `children` slot is filled in one level.
"""
function sync_reflection!(node::AReflectedNode, object,
                          policy::SyncPolicy = DepthPolicy(1))
    _sync_reflection!(node, object, policy, 0)
    node
end

# `depth` is where `node` itself sits; its children are checked at `depth + 1`.
function _sync_reflection!(node, object, policy::SyncPolicy, depth::Int)
    k = _kind_of(object)
    node.kind == k || (node.kind = k)

    if is_reflection_leaf(object)
        v = get_reflection_value(object)
        node.value == v || (node.value = v)
        node.children === nothing || (node.children = nothing)
        return node
    end
    node.value === nothing || (node.value = nothing)

    cur = node.children
    if !is_descendable_for_sync(policy, depth + 1, cur)
        cur isa AUnsyncedDocument || (node.children = _collapsed_marker(object))
        return node
    end

    kids = cur isa CellVector ? cur : CellVector(Any[])
    kids === cur || (node.children = kids)
    _sync_reflected_children!(kids, object, policy, depth + 1)
    node
end

# A marker for a whole collapsed node: it reports how many children are behind it.
_collapsed_marker(object) =
    UnsyncedDocument(_kind_of(object), reflect_child_count(object), false)

function _sync_reflected_children!(kids, object, policy::SyncPolicy, depth::Int)
    ns = reflect_child_count(object)
    nc = length(kids)
    tail = nc > 0 && kids[nc] isa AUnsyncedDocument ? kids[nc] : nothing
    shown = tail === nothing ? nc : nc - 1
    limit = compute_sync_element_limit(policy, ns; shown,
                                       requested = tail !== nothing && tail.requested)

    # One pass over at most `limit + 1` children: the extra one names the tail.
    i, first_hidden = 0, nothing
    for (label, value) in Iterators.take(reflect_child_pairs(object), limit + 1)
        i += 1
        if i > limit
            first_hidden = value
            break
        elseif i <= shown
            n = kids[i]
            n.label == label || (n.label = label)     # a field can be replaced wholesale
            _sync_reflection!(n, value, policy, depth)
        else
            n = ReflectedNode(label, "", nothing, nothing)
            _sync_reflection!(n, value, policy, depth)
            i <= nc ? (kids[i] = n) : push!(kids, n)
        end
    end

    want = limit < ns ? limit + 1 : limit
    for _ in 1:(length(kids) - want)
        pop!(kids)
    end
    limit < ns || return kids
    cur = length(kids) >= want ? kids[want] : nothing
    # The same placeholder the kernel walk would ask for, so a reflected tail and
    # a real collection's tail behave identically.
    new = make_unsynced_placeholder(policy, HiddenElements(_Repeated(first_hidden), 1, ns - limit), cur)
    new === cur && return kids
    length(kids) >= want ? (kids[want] = new) : push!(kids, new)
    kids
end

# The hidden children are produced by an iterator, not indexed out of a
# container, so there is nothing for `HiddenElements` to index into — only the
# first of them, which is all a placeholder needs for its label.
struct _Repeated
    value::Any
end
Base.getindex(r::_Repeated, ::Int) = r.value

# ── a read off the loop ───────────────────────────────────────────────────────
#
# A sync reads the value with the methods of its type, which a user defines, and
# writes the shadow, whose cells the loop owns. A feed splits the two: the loop
# reads which nodes are open, a task of its own reads the value along them into a
# snapshot, and the loop writes the snapshot into the shadow at its next drain.

# Which part of a node the sync descends into, read from the shadow on the loop as
# plain data: whether its children are read, how many of them it shows, whether
# its tail marker asks for more, and the same for each child that it shows.
struct _ReflectionOpenState
    is_descended::Bool
    shown::Int
    is_tail_requested::Bool
    kids::Vector{_ReflectionOpenState}
end

# The open state of a node at `depth` that the shadow does not hold yet.
_make_new_reflection_open_state(policy::SyncPolicy, depth::Int) =
    _ReflectionOpenState(is_descendable_for_sync(policy, depth + 1, nothing), 0, false,
                         _ReflectionOpenState[])

# How many children the slot `current` of a node shows, and whether its tail
# marker asks for more. A slot that holds no list shows none.
function _get_reflection_shown(current)
    current isa CellVector || return (0, false)
    count = length(current)
    tail = count > 0 && current[count] isa AUnsyncedDocument ? current[count] : nothing
    (tail === nothing ? count : count - 1, tail !== nothing && tail.requested)
end

# The open state of `node` at `depth`. It walks only what is open, as the screen
# shows it.
function _make_reflection_open_state(node, policy::SyncPolicy, depth::Int)
    current = node.children
    is_descendable_for_sync(policy, depth + 1, current) ||
        return _ReflectionOpenState(false, 0, false, _ReflectionOpenState[])
    shown, is_tail_requested = _get_reflection_shown(current)
    kids = _ReflectionOpenState[_make_reflection_open_state(current[index], policy, depth + 1)
                                for index in 1:shown]
    _ReflectionOpenState(true, shown, is_tail_requested, kids)
end

# Whether only the loop reads `x`: a cell, or a document that keeps its fields in
# cells, as `@document` makes it. A read of a computed cell off the loop would
# compute it there.
_is_read_on_loop(x) =
    x isa AbstractCell ||
    (x isa Document && any(index -> isdefined(x, index) && getfield(x, index) isa AbstractCell, 1:nfields(x)))

# What a read of the value found for one node, as plain data: its kind, its
# rendering when it is a leaf, its count of children, and the children that it
# read for the open state of the node. A child is a snapshot, or a value that only
# the loop reads, which the loop reads when it writes the shadow. The child after
# the last one that the node shows is the value as it is, because only its type
# names the tail marker.
struct _ReflectionSnapshot
    kind::String
    is_leaf::Bool
    value::Union{String,Nothing}
    count::Int
    is_descended::Bool
    shown::Int
    is_tail_requested::Bool
    children::Vector{Pair{String,Any}}
end

_kind_of(snapshot::_ReflectionSnapshot) = snapshot.kind
is_reflection_leaf(snapshot::_ReflectionSnapshot) = snapshot.is_leaf
get_reflection_value(snapshot::_ReflectionSnapshot) = snapshot.value
reflect_child_count(snapshot::_ReflectionSnapshot) = snapshot.count
reflect_child_pairs(snapshot::_ReflectionSnapshot) = snapshot.children

# Read `object` at `depth` for the open state `open`, with the methods of its type.
# A task other than the loop runs it, so it writes no cell.
function _take_reflection_snapshot(object, open::_ReflectionOpenState, policy::SyncPolicy, depth::Int)
    _is_read_on_loop(object) && return object
    kind = _kind_of(object)
    is_reflection_leaf(object) &&
        return _ReflectionSnapshot(kind, true, get_reflection_value(object), 0, false, 0, false,
                                   Pair{String,Any}[])
    count = reflect_child_count(object)
    open.is_descended ||
        return _ReflectionSnapshot(kind, false, nothing, count, false, 0, false, Pair{String,Any}[])
    limit = compute_sync_element_limit(policy, count; shown = open.shown,
                                       requested = open.is_tail_requested)
    children = Pair{String,Any}[]
    for (index, (label, value)) in enumerate(Iterators.take(reflect_child_pairs(object), limit + 1))
        if index > limit
            push!(children, label => value)
        else
            child = index <= length(open.kids) ? open.kids[index] :
                                                 _make_new_reflection_open_state(policy, depth + 1)
            push!(children, label => _take_reflection_snapshot(value, child, policy, depth + 1))
        end
    end
    _ReflectionSnapshot(kind, false, nothing, count, true, open.shown, open.is_tail_requested, children)
end

# Write a snapshot into `node` on the loop. A node that opened, closed or grew
# since the read keeps its children, and the next read fills it.
function _sync_reflection!(node, snapshot::_ReflectionSnapshot, policy::SyncPolicy, depth::Int)
    node.kind == snapshot.kind || (node.kind = snapshot.kind)
    if snapshot.is_leaf
        node.value == snapshot.value || (node.value = snapshot.value)
        node.children === nothing || (node.children = nothing)
        return node
    end
    node.value === nothing || (node.value = nothing)
    current = node.children
    if !is_descendable_for_sync(policy, depth + 1, current)
        current isa AUnsyncedDocument || (node.children = _collapsed_marker(snapshot))
        return node
    end
    snapshot.is_descended || return node
    _get_reflection_shown(current) == (snapshot.shown, snapshot.is_tail_requested) || return node
    kids = current isa CellVector ? current : CellVector(Any[])
    kids === current || (node.children = kids)
    _sync_reflected_children!(kids, snapshot, policy, depth + 1)
    node
end
