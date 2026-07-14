# Fragment of `DocumentModule` — the shadow sync.
#
# The double-buffer pattern: mutate a MutableCell-kind document freely (zero
# reactive overhead per event, no observable intermediate states); at a pause
# point diff-copy it into a ReactiveCell-kind shadow, writing a shadow cell
# only when its value changed so the reactive graph sees a minimal set of
# invalidations. Both trees are the same document type (generated from one
# `@document` declaration), which is what lets the sync be one generic walk.

# Same document type ignoring cell kind (compare the UnionAll wrappers).
_same_wrapper(a, b) = Base.typename(typeof(a)).wrapper === Base.typename(typeof(b)).wrapper

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
    _same_wrapper(shadow, source) ||
        error("sync_document!: type mismatch, $(typeof(shadow)) vs $(typeof(source))")
    K = _document_cell_kind(shadow)
    for nm in fieldnames(typeof(source))
        sv  = getproperty(source, nm)
        cur = getproperty(shadow, nm)
        if sv isa Document
            if cur isa Document && _same_wrapper(cur, sv)
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

# A source element rebuilt for the shadow's kind: a document is copied in that
# kind, a plain value passes through.
_shadow_elem(K, x) = x isa Document ? copy_document(K, x) : x
