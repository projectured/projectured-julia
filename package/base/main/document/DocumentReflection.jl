"""
    DocumentReflectionModule

A bounded shadow of an **arbitrary Julia object** — a live simulation engine, a
model, anything that is not a `Document` and never will be.

[`BoundedSyncModule`](@ref) needs a `Document` on both sides. The things one most
wants to inspect are ordinary structs, so there is nothing to shadow: no shadow,
no bound, no inspector. Hence this walk, which reflects an object into a tree of
[`ReflectedNode`](@ref)s — label, kind, leaf value, children — and syncs that
tree in place against the object, under the same [`SyncPolicy`](@ref).

Everything bounded sync provides carries over unchanged, because the same policy
and the same [`UnsyncedDocument`](@ref) marker are used: a node's `children` slot
holds a marker while it is collapsed, `request_sync!` on that marker expands it
one level on the next sync, a large field is capped with a tail marker, and the
nodes a widget holds keep their identity across syncs.

What it does *not* do is guess at presentation. A leaf's `value` is a short
string and a node's `kind` is a type name; deciding what that should look like is
the projection's business.
"""
module DocumentReflectionModule

import ..CellModule: Cell, MutableCell
import ..DocumentModule: Document, @document
import ..ReferenceModule: Reference
import ..CollectionModule: CellVector
import ..BoundedSyncModule: SyncPolicy, DepthPolicy, AbstractUnsyncedDocument,
                            UnsyncedDocument, should_descend_sync,
                            sync_element_limit, unsynced_marker, _tail_marker

export ReflectedNode, AbstractReflectedNode,
       reflect_document, sync_reflection!,
       reflect_child_count, reflect_child_pairs, reflect_children,
       is_reflection_leaf, reflection_value

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
    reflection_value(x) -> String

A leaf's short rendering. Truncated, because a shadow of a live object will
happily contain a megabyte-long `repr` otherwise.
"""
function reflection_value(x)
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
_reflect_fieldnames(x) =
    (f = fieldnames(typeof(x)); x isa Document ? f[1:end-1] : f)
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
# so `SimulationRun{Cell, Cell, Cell, Cell, Cell}` says nothing a reader wants
# and `…Mut` is the alias for one such spelling. The bare name is the type.
function _kind_of(x)
    x isa Document && return string(nameof(typeof(x)))
    s = replace(string(typeof(x)), r"[A-Za-z_][A-Za-z0-9_!]*\." => "")
    length(s) <= 48 ? s : string(first(s, 45), "...")
end

# ── building and syncing ──────────────────────────────────────────────────────

"""
    reflect_document(object, policy = DepthPolicy(1)) -> ReflectedNode

A fresh bounded shadow of `object`. Sync it afterwards with
[`sync_reflection!`](@ref) and the same policy.
"""
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
function sync_reflection!(node::AbstractReflectedNode, object,
                          policy::SyncPolicy = DepthPolicy(1))
    _sync_reflection!(node, object, policy, 0)
    node
end

# `depth` is where `node` itself sits; its children are checked at `depth + 1`.
function _sync_reflection!(node, object, policy::SyncPolicy, depth::Int)
    k = _kind_of(object)
    node.kind == k || (node.kind = k)

    if is_reflection_leaf(object)
        v = reflection_value(object)
        node.value == v || (node.value = v)
        node.children === nothing || (node.children = nothing)
        return node
    end
    node.value === nothing || (node.value = nothing)

    cur = node.children
    if !should_descend_sync(policy, depth + 1, cur)
        cur isa AbstractUnsyncedDocument || (node.children = _collapsed_marker(object))
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
    tail = nc > 0 && kids[nc] isa AbstractUnsyncedDocument ? kids[nc] : nothing
    shown = tail === nothing ? nc : nc - 1
    limit = sync_element_limit(policy, ns, shown, tail !== nothing && tail.requested)

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
    rest = ns - limit
    cur = length(kids) >= want ? kids[want] : nothing
    if cur isa AbstractUnsyncedDocument
        cur.size == rest || (cur.size = rest)
        cur.requested = false                         # the request is spent
    else
        m = _tail_marker(first_hidden, rest)
        length(kids) >= want ? (kids[want] = m) : push!(kids, m)
    end
    kids
end

end # module
