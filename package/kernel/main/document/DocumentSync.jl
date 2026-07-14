# Fragment of `DocumentModule` — the shadow sync.
#
# The double-buffer pattern: mutate a MutableCell-kind document freely (zero
# reactive overhead per event, no observable intermediate states); at a pause
# point diff-copy it into a ReactiveCell-kind shadow, writing a shadow cell
# only when its value changed so the reactive graph sees a minimal set of
# invalidations. Both trees are the same document type (generated from one
# `@document` declaration), which is what lets the sync be one generic walk.
#
# `sync_document!` is an open generic: the walk here handles a record (a document
# whose children are named fields), and a document with a different *shape* adds
# its own method — a positional collection matches its slots by index, not by
# field name, and so cannot reuse this one. `is_same_document_type`,
# `get_document_cell_kind`, and `copy_shadow_element` are the seam such a method
# is written against, and are exported for that reason: they are this module's
# contract to any document that syncs, not internals.

"""
    is_same_document_type(a, b) -> Bool

`true` when `a` and `b` are the same document type **ignoring cell kind** — a
reactive `RFoo` and an immutable `IFoo` answer `true`, since both are `Foo`. The
shape test a sync makes before recursing into a slot: same type ⇒ sync in place,
different type ⇒ rebuild the slot.
"""
is_same_document_type(a, b) = Base.typename(typeof(a)).wrapper === Base.typename(typeof(b)).wrapper

"""
    sync_document!(shadow, source) -> shadow

Update the writable `shadow` document to match `source`, writing a shadow
cell **only when its value changed** — so the downstream graph sees a
*minimal* invalidation set, not a wholesale rebuild. `shadow` may be any
writable kind (`ReactiveCell` or `MutableCell`); `source` may be any kind.
Recurses structurally: a child document is synced in place when it is the
same type, else replaced by a fresh copy in the shadow's kind; a leaf field
is written only on `!isequal`.

The result is a consistent view of `source` after each sync; between syncs
the source is unobserved and pays nothing for observation.
"""
function sync_document!(shadow::Document, source::Document)
    is_same_document_type(shadow, source) ||
        error("sync_document!: type mismatch, $(typeof(shadow)) vs $(typeof(source))")
    K = get_document_cell_kind(shadow)
    for nm in fieldnames(typeof(source))
        sv  = getproperty(source, nm)
        cur = getproperty(shadow, nm)
        if sv isa Document
            if cur isa Document && is_same_document_type(cur, sv)
                sync_document!(cur, sv)                       # recurse in place
            else
                setproperty!(shadow, nm, copy_document(K, sv)) # type changed ⇒ rebuild in shadow's kind
            end
        else
            isequal(cur, sv) || setproperty!(shadow, nm, sv)   # leaf: write iff changed
        end
    end
    shadow
end

"""
    copy_shadow_element(K, x) -> value

A source element rebuilt for a shadow of cell kind `K`: a document is copied in
that kind, a plain value passes through. What a sync writes into a shadow slot
whose source element changed type — the slot cannot be synced in place, so it is
rebuilt on the shadow's side of the double buffer.
"""
copy_shadow_element(K, x) = x isa Document ? copy_document(K, x) : x
