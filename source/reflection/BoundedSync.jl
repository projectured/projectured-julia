# Fragment of `ReflectionModule` — the bounded synchronisation of a native tree
# into its cell shadow: `UnsyncedDocument`, the placeholder that stands for a
# subtree the walk chose not to descend into, and the walk that decides.

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
get_unsynced_size(x) = is_element_collection(x) ? length(x) :
                   (x isa Document ? fieldcount(typeof(x)) - 1 : -1)

"""
    make_unsynced_marker(document) -> UnsyncedDocument

A marker standing in for `document`. Write one into a shadow slot to **collapse**
what is there: the next sync sees an un-requested marker and leaves it alone, so
the subtree is dropped and stays dropped until someone asks for it again.
"""
make_unsynced_marker(source) = UnsyncedDocument(string(nameof(typeof(source))),
                                           get_unsynced_size(source), false)

"""
    request_sync!(marker) -> marker

Ask that this node be filled in on the next sync — one level, with fresh markers
below it. Sugar over setting `requested`; a projection may equally emit a
`ReplaceReferencedValueOperation`, since the marker lives in the shadow like any
other document.

The flag is consumed by the expansion: the marker is *replaced* by the real
child, so a request cannot outlive the node it was made on.
"""
request_sync!(m::AUnsyncedDocument) = (m.requested = true; m)

# ── policies ──────────────────────────────────────────────────────────────────

"""
    SyncPolicy

Decides, per child, whether a bounded sync descends into it or leaves a marker.
Implement [`is_descendable_for_sync`](@ref).
"""
abstract type SyncPolicy end

"""
    is_descendable_for_sync(policy, depth, shadow_slot) -> Bool

Whether to sync the child at `depth` (1 for a root's children). `shadow_slot` is
what stands in that slot now — a marker, a document already materialised there,
or `nothing` when the slot has yet to be grown.
"""
function is_descendable_for_sync end

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

`elements` caps a collection the way `depth` caps nesting, and matters just as
much: a thousand-entry array one level down is one level down, and walking it
would defeat the bound as thoroughly as walking a deep tree. Past the cap a
single marker stands for the tail and reports how many are behind it.
"""
struct DepthPolicy <: SyncPolicy
    depth::Int
    elements::Int
end
DepthPolicy(depth::Integer) = DepthPolicy(Int(depth), 32)
DepthPolicy(; depth::Integer = 1, elements::Integer = 32) =
    DepthPolicy(Int(depth), Int(elements))

is_descendable_for_sync(p::DepthPolicy, depth::Int, slot) =
    slot isa AUnsyncedDocument ? slot.requested :
    slot isa Document                 ? true :
                                        depth <= p.depth

"""
    sync_element_limit(policy, total; shown, requested) -> Int

How many of a collection's `total` elements to materialise, given how many are
`shown` there now and whether the tail marker has been `requested`. Returning
`total` means no cap.

Same shape as [`is_descendable_for_sync`](@ref) and for the same reason: what is
already shown stays shown, and a request buys one more page rather than the whole
tail.
"""
sync_element_limit(::SyncPolicy, total::Int; shown::Int, requested::Bool) = total

function sync_element_limit(p::DepthPolicy, total::Int; shown::Int, requested::Bool)
    limit = max(p.elements, shown)
    requested && (limit += p.elements)
    min(limit, total)
end

"""
    UNBOUNDED_SYNC

A policy that never stops — every child descended, every element taken. The same
result as passing no policy at all, and useful for a caller that holds a policy
variable and wants to turn the bound off without a second code path.
"""
const UNBOUNDED_SYNC = DepthPolicy(typemax(Int), typemax(Int))

# ── the policy the kernel walk consults ───────────────────────────────────────
#
# There is no walk here. `sync_document!` / `copy_document` carry a policy and
# ask these three questions at every child; this module answers them and supplies
# the marker. The traversal stays where it belongs — one of it, in the kernel.

"""
    sync_document!(shadow, source, policy) -> shadow

Sync `source` into `shadow`, stopping where `policy` says to and leaving an
[`UnsyncedDocument`](@ref) there. Sugar for the kernel's four-argument form.
"""
sync_document!(shadow::Document, source::Document, policy::SyncPolicy) =
    sync_document!(shadow, source, policy, 0)

"""
    copy_document(kind, document, policy) -> Document

Copy `document` into a shadow of cell kind `kind`, stopping where `policy` says
to and leaving an [`UnsyncedDocument`](@ref) there.

**This is how you get a shadow to bounded-sync into.** The two-argument
`copy_document` builds the whole subtree, and a shadow that already holds
everything has nothing left for the bound to withhold — the depth governs
*growth*, and a full copy has already grown. Start bounded and stay bounded.
"""
copy_document(K::Type{<:AbstractCell}, doc::Document, policy::SyncPolicy) =
    copy_document(K, doc, policy, 0)

# What stands where the walk stopped. `current` is what is in the slot now, so an
# already-placed marker is handed straight back and the shadow keeps its identity
# — the kernel writes only when this returns something new.
make_unsynced_placeholder(::SyncPolicy, source, current) =
    current isa AUnsyncedDocument ? current : make_unsynced_marker(source)

# A tail placeholder reports how many elements are behind it, not the child count
# of whichever one happens to stand first.
make_unsynced_placeholder(::SyncPolicy, source::AbstractVector, current) =
    current isa AUnsyncedDocument ?
        (current.size == length(source) || (current.size = length(source));
         current.requested = false;                    # the request is spent
         current) :
        UnsyncedDocument(isempty(source) ? "" : string(nameof(typeof(_unwrap(first(source))))),
                         length(source), false)

_unwrap(x) = x isa AbstractCell ? x[] : x

# How many of a collection's elements to keep. Given the whole source and shadow
# because the answer depends on what the shadow already holds — including whether
# its trailing marker was flagged — which is this module's bookkeeping, not the
# kernel's.
function sync_element_limit(p::DepthPolicy, source, shadow)
    total = length(source)
    nc = length(shadow)
    tail = nc > 0 && shadow[nc] isa AUnsyncedDocument ? shadow[nc] : nothing
    shown = tail === nothing ? nc : nc - 1
    limit = max(p.elements, shown)
    tail !== nothing && tail.requested && (limit += p.elements)
    min(limit, total)
end

sync_element_limit(::SyncPolicy, source, shadow) = length(source)
