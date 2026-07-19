# Fragment of `DocumentModule` — the shadow sync.
#
# The double-buffer pattern: mutate a MutableCell-kind document freely (zero
# reactive overhead per event, no observable intermediate states); at a pause
# point diff-copy it into a ReactiveCell-kind shadow, writing a shadow cell
# only when its value changed so the reactive graph sees a minimal set of
# invalidations. Both trees are the same document type (generated from one
# `@document` declaration), which is what lets the sync be one walk.
#
# One `sync_document!` handles both shapes: a **record** (children are named
# fields) syncs field-by-field, and a **positional collection**
# (`is_element_collection`) syncs its elements by index through the vector
# protocol. `is_same_document_type` / `copy_shadow_element` are private helpers of
# that walk.

# `true` when `a` and `b` are the same document IGNORING variant — a reactive
# `RFoo`, an immutable `IFoo`, and the native mutable `FooMut` all answer `true`,
# via `document_family` (the schema's abstract family type; for a plain type it
# falls back to the name wrapper, so this is equivalent to the old wrapper test
# everywhere except that it now also unifies the two struct layouts). The shape
# test the sync makes before recursing into a slot: same document ⇒ sync in place,
# different ⇒ rebuild it.
is_same_document_type(a, b) = document_family(a) === document_family(b)

# A source element rebuilt for a shadow of cell kind `K`: a document is copied in
# that kind, a plain value passes through. Written into a shadow slot whose source
# element changed type and so cannot be synced in place.
copy_shadow_element(K, x) = x isa Document ? copy_document(K, x) : x

# Contract documented at the `sync_document!` declaration in `DocumentInterface.jl`.
function sync_document!(shadow::Document, source::Document)
    is_same_document_type(shadow, source) ||
        error("sync_document!: type mismatch, $(typeof(shadow)) vs $(typeof(source))")
    K = get_cell_struct_kind(shadow)
    is_element_collection(source) ? _sync_elements!(shadow, source, K) :
                                    _sync_fields!(shadow, source, K)
    shadow
end

# Record sync: match children by field name. A child document is synced in place
# when it is the same type, else replaced by a fresh copy in the shadow's kind; a
# leaf field is written only on `!isequal`, so the graph sees a minimal set.
function _sync_fields!(shadow, source, K)
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
end

# Positional sync: match a positional collection's slots by index through the
# vector protocol (`length`/`getindex`/`setindex!`/`push!`/`pop!`). A same-type
# slot is synced in place (its own inner cells, minimally); a changed-type or
# changed-value slot is rewritten; a longer source appends, a shorter one trims
# from the end. This is minimal for the dominant edits — in-place value change,
# append, pop-from-end; a front-shift re-syncs the shifted tail, and keying by
# source-element identity (an `IdDict` persisted across syncs) is the natural
# refinement if a front-heavy queue ever demands it.
function _sync_elements!(shadow, source, K)
    ns, nc = length(source), length(shadow)
    for i in 1:min(ns, nc)
        s, c = source[i], shadow[i]
        if s isa Document && c isa Document && is_same_document_type(c, s)
            sync_document!(c, s)
        else
            isequal(c, s) || (shadow[i] = copy_shadow_element(K, s))
        end
    end
    for i in (nc + 1):ns
        push!(shadow, copy_shadow_element(K, source[i]))
    end
    for _ in 1:(nc - ns)
        pop!(shadow)
    end
end
