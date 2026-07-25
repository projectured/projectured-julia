"""
    BoundedSyncModule

Bounded `sync_document!`: stop the shadow walk at a bound and leave a marker
where it stopped, so a shadow grows only where someone looked.

The unbounded `sync_document!(shadow, source)` walks the whole source. That is
right for a small document and ruinous for a large one — an OMNeT++ sequential
engine holds per-module hash and count arrays with over a thousand entries each
plus a future-event heap, and syncing all of it every frame to display a handful
of numbers is wasted work.

Making the *projection* lazy would be the wrong layer: the sync cost would stay
and the result would be discarded. So the bound goes here. Where the walk stops
it writes an [`UnsyncedDocument`](@ref); a consumer that wants more sets that
marker's `requested` flag, and the next sync fills that node in one level
deeper, writing fresh markers below it. Widgets then need no laziness of their
own — they render whatever the shadow holds, and the shadow is small because the
sync was bounded.

Expansion state therefore needs no side table: it *is* the presence or absence
of markers in the shadow. Since the walk syncs same-type children in place, the
shadow a consumer holds stays the shadow it holds.

# The shadow decides

The bound governs *growth* only. A slot that already holds a document keeps it,
whatever its depth; a slot holding a marker is descended into exactly when that
marker is `requested`; only an empty slot faces the depth. Anything else
oscillates — a node materialised by a request sits past the bound, so a walk
that consulted depth alone would collapse it again on the very next sync.

The corollary is that a shadow must be *born* bounded, which is what
`copy_document(kind, doc, policy)` is for. A shadow made by the ordinary full
copy has already grown everything, and a bound can only withhold what has not
been grown yet.

# Relationship to the unbounded walk

`sync_document!(shadow, source, policy)` is a separate method of the same
generic function, living outside the sealed `DocumentSync.jl`. A policy that
never stops delegates to the unbounded method outright, so "unbounded" is the
existing behaviour by construction rather than by imitation.

The bounded walk cannot delegate *per level*, because the unbounded one recurses
through the two-argument `sync_document!` and so has no way to carry a policy
down. It therefore mirrors that walk's structure (same-type children synced in
place, leaves written only when changed, collections matched by index) while
consulting the policy at each child. `copy_document(kind, doc, policy)` mirrors
`copy_document(kind, doc)` for the same reason.
"""
module BoundedSyncModule

import ..CellModule: AbstractCell, Cell, ReactiveCell
import ..DocumentModule: Document, @document, sync_document!, copy_document,
                         is_element_collection, get_cell_struct_kind,
                         is_same_document_type, copy_shadow_element,
                         _declared_value_types, _kinded_value_type
import ..ReferenceModule: Reference

export UnsyncedDocument, AbstractUnsyncedDocument,
       SyncPolicy, DepthPolicy, UNBOUNDED_SYNC,
       should_descend_sync, unsynced_size, unsynced_marker, request_sync!

# ── the marker ────────────────────────────────────────────────────────────────

"""
    UnsyncedDocument(kind, size, requested)

Stands where a bounded sync stopped. `kind` names what would be there (for a
label), `size` is its child count when cheaply known and `-1` otherwise, and
`requested` is the flag a consumer sets to ask that this node be filled in on
the next sync.

It is an ordinary `Document`, so it flows through printers, references and
operations like anything else — a projection renders it as an unexpanded node.
"""
@document struct UnsyncedDocument
    kind::Any
    size::Int
    requested::Bool
end

# How many children `x` would have, when that is cheap to answer. A positional
# collection knows its length; a record knows its field count, less the
# `selection` field `@document` appends to every document — that one is
# machinery, not content, and counting it would misreport the label by one.
# Anything else reports -1 rather than paying to find out.
unsynced_size(x) = is_element_collection(x) ? length(x) :
                   (x isa Document ? fieldcount(typeof(x)) - 1 : -1)

"""
    unsynced_marker(document) -> UnsyncedDocument

A marker standing in for `document`. Write one into a shadow slot to **collapse**
what is there: the next sync sees an un-requested marker and leaves it alone, so
the subtree is dropped and stays dropped until someone asks for it again.
"""
unsynced_marker(source) = UnsyncedDocument(string(nameof(typeof(source))),
                                           unsynced_size(source), false)

"""
    request_sync!(marker) -> marker

Ask that this node be filled in on the next sync — one level, with fresh markers
below it. Sugar over setting `requested`; a projection may equally emit a
`ReplaceReferencedValueOperation`, since the marker lives in the shadow like any
other document.

The flag is consumed by the expansion: the marker is *replaced* by the real
child, so a request cannot outlive the node it was made on.
"""
request_sync!(m::AbstractUnsyncedDocument) = (m.requested = true; m)

# ── policies ──────────────────────────────────────────────────────────────────

"""
    SyncPolicy

Decides, per child, whether a bounded sync descends into it or leaves a marker.
Implement [`should_descend_sync`](@ref).
"""
abstract type SyncPolicy end

"""
    should_descend_sync(policy, depth, shadow_slot) -> Bool

Whether to sync the child at `depth` (1 for a root's children). `shadow_slot` is
what stands in that slot now — a marker, a document already materialised there,
or `nothing` when the slot has yet to be grown.
"""
function should_descend_sync end

"""
    DepthPolicy(depth)

Grow `depth` levels where there is nothing yet; elsewhere **the shadow decides**.

The three cases are the whole semantics, and they are what make expansion stable:

- an *empty* slot is grown only within `depth` — this is the bound;
- a slot holding a **marker** is descended into exactly when it is `requested`;
- a slot already holding a **document** is kept, whatever its depth.

The last case is not an optimisation. Without it, a node materialised by a
request would sit beyond `depth` and be collapsed again by the very next sync,
and expansion would oscillate instead of converge. With it, `depth` means "where
growth starts" rather than "the deepest anyone may ever see", and collapsing is
symmetric: write a marker back and it stays, at any depth.
"""
struct DepthPolicy <: SyncPolicy
    depth::Int
end
DepthPolicy(; depth::Integer = 1) = DepthPolicy(Int(depth))

should_descend_sync(p::DepthPolicy, depth::Int, slot) =
    slot isa AbstractUnsyncedDocument ? slot.requested :
    slot isa Document                 ? true :
                                        depth <= p.depth

"""
    UNBOUNDED_SYNC

A policy that never stops. `sync_document!` with it delegates straight to the
unbounded two-argument method, so it is that behaviour rather than a copy of it.
"""
const UNBOUNDED_SYNC = DepthPolicy(typemax(Int))

_is_unbounded(p::DepthPolicy) = p.depth == typemax(Int)
_is_unbounded(::SyncPolicy)   = false

# ── the bounded walk ──────────────────────────────────────────────────────────

"""
    sync_document!(shadow, source, policy) -> shadow

Sync `source` into `shadow`, stopping where `policy` says to and leaving an
[`UnsyncedDocument`](@ref) there. Same contract as the two-argument method
otherwise: same-type children are synced in place, leaves are written only when
they changed, and a positional collection is matched by index.
"""
function sync_document!(shadow::Document, source::Document, policy::SyncPolicy)
    _is_unbounded(policy) && return sync_document!(shadow, source)
    _bounded_sync!(shadow, source, policy, 0)
end

function _bounded_sync!(shadow::Document, source::Document, policy::SyncPolicy, depth::Int)
    is_same_document_type(shadow, source) ||
        error("sync_document!: type mismatch, $(typeof(shadow)) vs $(typeof(source))")
    K = get_cell_struct_kind(shadow)
    is_element_collection(source) ? _bounded_elements!(shadow, source, K, policy, depth) :
                                    _bounded_fields!(shadow, source, K, policy, depth)
    shadow
end

# The child value to store in a shadow slot, given what is there now. Returns
# `nothing` when the slot needs no write — either it was synced in place, or a
# marker already standing there is to be left alone.
function _synced_child(cur, sv, K, policy, depth)
    same = cur isa Document && !(cur isa AbstractUnsyncedDocument) &&
           is_same_document_type(cur, sv)
    # What the policy is shown: a marker, an already-materialised node, or
    # `nothing` for a slot that has to be grown from scratch. A document of the
    # *wrong* type is not "already there" — it has to be rebuilt, so it counts as
    # growth and faces the bound.
    slot = (same || cur isa AbstractUnsyncedDocument) ? cur : nothing
    should_descend_sync(policy, depth, slot) ||
        return cur isa AbstractUnsyncedDocument ? nothing : unsynced_marker(sv)
    same && (_bounded_sync!(cur, sv, policy, depth); return nothing)  # identity preserved
    _bounded_copy(K, sv, policy, depth)
end

function _bounded_fields!(shadow, source, K, policy, depth)
    for nm in fieldnames(typeof(source))
        sv  = getproperty(source, nm)
        cur = getproperty(shadow, nm)
        if sv isa Document
            new = _synced_child(cur, sv, K, policy, depth + 1)
            new === nothing || setproperty!(shadow, nm, new)
        else
            isequal(cur, sv) || setproperty!(shadow, nm, sv)
        end
    end
end

function _bounded_elements!(shadow, source, K, policy, depth)
    ns, nc = length(source), length(shadow)
    for i in 1:min(ns, nc)
        s, c = source[i], shadow[i]
        if s isa Document
            new = _synced_child(c, s, K, policy, depth + 1)
            new === nothing || (shadow[i] = new)
        else
            isequal(c, s) || (shadow[i] = copy_shadow_element(K, s))
        end
    end
    for i in (nc + 1):ns
        s = source[i]
        push!(shadow, s isa Document ?
              (should_descend_sync(policy, depth + 1, nothing) ?
               _bounded_copy(K, s, policy, depth + 1) : unsynced_marker(s)) :
              copy_shadow_element(K, s))
    end
    for _ in 1:(nc - ns)
        pop!(shadow)
    end
end

# ── the bounded copy ──────────────────────────────────────────────────────────

"""
    copy_document(kind, document, policy) -> Document

Copy `document` into a shadow of cell kind `kind`, stopping where `policy` says
to and leaving an [`UnsyncedDocument`](@ref) there.

**This is how you get a shadow to bounded-sync into.** The two-argument
`copy_document` builds the whole subtree, and a shadow that already holds
everything has nothing left for the bound to withhold — the depth governs
*growth*, and a full copy has already grown. Start bounded and stay bounded.

Structurally a bounded `copy_document(K, doc)`: same reconstruction through the
type's `UnionAll` constructor and the same cell-kind conversion, with the one
difference that a document-valued child past the bound is never visited.
"""
copy_document(K::Type{<:AbstractCell}, doc::Document, policy::SyncPolicy) =
    _is_unbounded(policy) ? copy_document(K, doc) : _bounded_copy(K, doc, policy, 0)

# `depth` is where `doc` itself sits, so its children are checked at `depth + 1`.
# A vector is not a level of its own: a collection document's elements are its
# children, matching how the sync walks them.
function _bounded_copy(K::Type{<:AbstractCell}, doc::Document, policy::SyncPolicy, depth::Int)
    T = typeof(doc)
    base = Base.typename(T).wrapper
    Ts = _declared_value_types(base)
    args = Any[]
    for (i, nm) in enumerate(fieldnames(T))
        raw = getfield(doc, nm)
        if raw isa AbstractCell
            v = _bounded_copy_value(K, raw[], policy, depth + 1)
            push!(args, K{_kinded_value_type(K, Ts, i, v)}(v))
        else
            push!(args, _bounded_copy_value(K, raw, policy, depth + 1))
        end
    end
    base(args...)
end

_bounded_copy_value(K, x::Document, policy, depth) =
    should_descend_sync(policy, depth, nothing) ? _bounded_copy(K, x, policy, depth) :
                                                  unsynced_marker(x)
_bounded_copy_value(K, x::AbstractVector, policy, depth) =
    [_bounded_copy_value(K, e, policy, depth) for e in x]
function _bounded_copy_value(K, c::AbstractCell, policy, depth)   # a per-slot cell
    v = _bounded_copy_value(K, c[], policy, depth)
    K{K === ReactiveCell ? Any : typeof(v)}(v)
end
_bounded_copy_value(K, x, policy, depth) = copy_document(K, x)    # leaf

end # module
