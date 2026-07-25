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

# Relationship to the unbounded walk

`sync_document!(shadow, source, policy)` is a separate method of the same
generic function, living outside the sealed `DocumentSync.jl`. A policy that
never stops delegates to the unbounded method outright, so "unbounded" is the
existing behaviour by construction rather than by imitation.

The bounded walk cannot delegate *per level*, because the unbounded one recurses
through the two-argument `sync_document!` and so has no way to carry a policy
down. It therefore mirrors that walk's structure (same-type children synced in
place, leaves written only when changed, collections matched by index) while
consulting the policy at each child.
"""
module BoundedSyncModule

import ..CellModule: Cell
import ..DocumentModule: Document, @document, sync_document!, copy_document,
                         is_element_collection, get_cell_struct_kind,
                         is_same_document_type, copy_shadow_element
import ..ReferenceModule: Reference

export UnsyncedDocument, AbstractUnsyncedDocument,
       SyncPolicy, DepthPolicy, UNBOUNDED_SYNC,
       should_descend_sync, unsynced_size, request_sync!

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

# A marker standing in for `source`.
_marker_for(source) = UnsyncedDocument(string(nameof(typeof(source))),
                                       unsynced_size(source), false)

"""
    request_sync!(marker) -> marker

Ask that this node be filled in on the next sync. Sugar over setting
`requested`; a projection may equally emit a `ReplaceReferencedValueOperation`,
since the marker lives in the shadow like any other document.
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
what currently occupies that slot, so a policy can honour a marker whose
`requested` flag is set.
"""
function should_descend_sync end

"""
    DepthPolicy(depth)

Sync `depth` levels below the root without being asked, and always follow a
`requested` marker regardless of depth — which is what lets a consumer drill
past the bound one level per interaction.
"""
struct DepthPolicy <: SyncPolicy
    depth::Int
end
DepthPolicy(; depth::Integer = 1) = DepthPolicy(Int(depth))

should_descend_sync(p::DepthPolicy, depth::Int, slot) =
    depth <= p.depth || (slot isa AbstractUnsyncedDocument && slot.requested)

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

# The child value to store in a shadow slot, given what is there now.
#
# Materialising a marker copies the source subtree in full and then prunes it
# back to the bound. The copy is eager because `copy_document` is; it is paid
# once, when a consumer asks for that node, rather than on every sync — which is
# the cost that matters. Bounding the copy itself would need a bounded
# `copy_document`, and is deferred.
function _synced_child(cur, sv, K, policy, depth)
    if !should_descend_sync(policy, depth, cur)
        return cur isa AbstractUnsyncedDocument ? nothing : _marker_for(sv)
    end
    if cur isa Document && !(cur isa AbstractUnsyncedDocument) && is_same_document_type(cur, sv)
        _bounded_sync!(cur, sv, policy, depth)      # in place: identity preserved
        return nothing                               # nothing to store
    end
    _prune!(copy_document(K, sv), sv, K, policy, depth)
end

# Replace, in a freshly copied shadow subtree, everything the policy would not
# have descended into.
function _prune!(fresh, source, K, policy, depth)
    fresh isa Document || return fresh
    if is_element_collection(source)
        for i in 1:min(length(source), length(fresh))
            s = source[i]
            s isa Document || continue
            fresh[i] = should_descend_sync(policy, depth + 1, fresh[i]) ?
                       _prune!(fresh[i], s, K, policy, depth + 1) : _marker_for(s)
        end
    else
        for nm in fieldnames(typeof(source))
            s = getproperty(source, nm)
            s isa Document || continue
            cur = getproperty(fresh, nm)
            setproperty!(fresh, nm,
                should_descend_sync(policy, depth + 1, cur) ?
                _prune!(cur, s, K, policy, depth + 1) : _marker_for(s))
        end
    end
    fresh
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
               _prune!(copy_document(K, s), s, K, policy, depth + 1) : _marker_for(s)) :
              copy_shadow_element(K, s))
    end
    for _ in 1:(nc - ns)
        pop!(shadow)
    end
end

end # module
