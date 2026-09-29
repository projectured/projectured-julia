"""
    ReflectionModule

Bounded `sync_document!`: stop the shadow walk at a bound and leave a marker
where it stopped, so a shadow grows only where someone looked.

The unbounded `sync_document!(shadow, source)` walks the whole source. That is
right for a small document and ruinous for a large one — an object holding
thousand-entry collections and a heap of closures costs the same to shadow
whether four of its fields are on screen or all of it is, and syncing that every
frame to display the four is wasted work.

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

# Where the walk lives

Not here. `sync_document!` and `copy_document` take a policy and consult
`is_descendable_for_sync` / `compute_sync_element_limit` /
`make_unsynced_placeholder` at every child; this module answers those three and
supplies the marker. There is one traversal of each kind, in the kernel, and
bounding is a parameter of it.

An earlier version put a second, bounded walk here beside the sealed one. It
worked, but it mirrored `_sync_fields!` / `_sync_elements!` / `copy_document`
line for line — two traversals differing only by a policy check, kept in step by
hand — and it could only reach the kinded-copy machinery by importing kernel
internals, which the module boundary forbids. The hooks are the honest shape.
"""
module ReflectionModule

using ..CellModule
using ..CollectionModule
using ..DocumentModule
using ..FeedModule
using ..GestureBindingModule
using ..IoMapModule
using ..OperationModule
using ..ProjectionModule
using ..ReferenceModule
using ..WidgetModule

# Imported to extend: this module adds a method to each of these.
import ..DocumentModule: sync_document!, copy_document, is_descendable_for_sync,
                         compute_sync_element_limit, make_unsynced_placeholder
import ..FeedModule: drain_changes!, compute_wake_deadline
import ..OperationModule: evaluate_operation
import ..ProjectionModule: print_document, read_intent

export UnsyncedDocument, AUnsyncedDocument,
       SyncPolicy, DepthPolicy, UNBOUNDED_SYNC,
       get_unsynced_size, make_unsynced_marker, request_sync!
export ReflectedNode, AReflectedNode, SetReflectedDisclosureOperation,
       reflect_document, sync_reflection!,
       reflect_child_count, reflect_child_pairs, reflect_children,
       is_reflection_leaf, get_reflection_value
export ReflectionToWidget
export ReflectionFeed


include("BoundedSync.jl")
include("DocumentReflection.jl")
include("ReflectionToWidget.jl")
include("ReflectionFeed.jl")

end # module
