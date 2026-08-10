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
#
# The walk is optionally **bounded**: `policy` is consulted at every child, and
# where it says stop the slot gets `unsynced_placeholder` instead of a subtree.
# The default policy (`nothing`) always descends, so an un-policed sync is
# exactly the walk described above and pays nothing for the option. Bounding is
# a parameter of this walk rather than a second walk beside it — a shadow of a
# thousand-entry collection is the same traversal, stopped earlier.

# `true` when `a` and `b` are the same document IGNORING variant — a reactive
# `CRFoo`, an immutable `CIFoo`, and the native mutable `FooMut` all answer `true`,
# via `document_family` (the schema's abstract family type; for a plain type it
# falls back to the name wrapper, so this is equivalent to the old wrapper test
# everywhere except that it now also unifies the two struct layouts). The shape
# test the sync makes before recursing into a slot: same document ⇒ sync in place,
# different ⇒ rebuild it.
is_same_document_type(a, b) = document_family(a) === document_family(b)

# A source element rebuilt for a shadow of cell kind `K`: a document is copied in
# that kind, a plain value passes through. Written into a shadow slot whose source
# element changed type and so cannot be synced in place. The one place a child is
# built, so both walks below rebuild by the same rule.
#
# `K === nothing` says the shadow tree holds no cells — a native document, or a
# hand-written one whose first field is raw. Nothing in such a tree can invalidate
# a reader, so it is not a shadow. Say that here; the walk would otherwise fail
# several frames down as a `copy_document` method that does not exist.
function copy_shadow_element(K, x, policy = nothing, depth::Int = 0)
    x isa Document || return x
    K === nothing && error("sync_document!: a shadow holds cells and this one does not, " *
                           "so a child cannot be rebuilt in it. Build the shadow with " *
                           "copy_document(ReactiveCell, source), or from a cell-layout constructor.")
    copy_document(K, x, policy, depth)
end

# Contract documented at the `sync_document!` declaration in `DocumentInterface.jl`.
function sync_document!(shadow::Document, source::Document, policy = nothing, depth::Int = 0)
    is_same_document_type(shadow, source) ||
        error("sync_document!: type mismatch, $(typeof(shadow)) vs $(typeof(source))")
    K = get_cell_struct_kind(shadow)
    is_element_collection(source) ? _sync_elements!(shadow, source, K, policy, depth) :
                                    _sync_fields!(shadow, source, K, policy, depth)
    shadow
end

# The child to put in a slot, or `nothing` when the slot needs no write — either
# it was synced in place, or a placeholder already standing there is to be left
# alone. The one place the bound is decided; both walks below share it.
function _synced_child(cur, sv, K, policy, depth)
    if !should_descend_sync(policy, depth, cur)
        new = unsynced_placeholder(policy, sv, cur)
        return new === cur ? nothing : new          # already stopped here: leave it be
    end
    cur isa Document && is_same_document_type(cur, sv) &&
        (sync_document!(cur, sv, policy, depth); return nothing)      # recurse in place
    copy_shadow_element(K, sv, policy, depth)                         # rebuild in shadow's kind
end

# Record sync: match children by field name. A child document is synced in place
# when it is the same type, else replaced by a fresh copy in the shadow's kind; a
# leaf field is written only on `!isequal`, so the graph sees a minimal set.
function _sync_fields!(shadow, source, K, policy, depth)
    for nm in fieldnames(typeof(source))
        sv  = getproperty(source, nm)
        cur = getproperty(shadow, nm)
        if sv isa Document
            new = _synced_child(cur, sv, K, policy, depth + 1)
            new === nothing || setproperty!(shadow, nm, new)
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
function _sync_elements!(shadow, source, K, policy, depth)
    ns, nc = length(source), length(shadow)
    limit = sync_element_limit(policy, source, shadow)
    for i in 1:min(limit, nc)
        s, c = source[i], shadow[i]
        if s isa Document
            # A slot already holding the very same object needs no work — the
            # original short-circuit, kept: only a slot that is a *different*
            # object, or a same-type one to recurse into, reaches the walk.
            same = c isa Document && is_same_document_type(c, s)
            if same || !isequal(c, s)
                new = _synced_child(c, s, K, policy, depth + 1)
                new === nothing || (shadow[i] = new)
            end
        else
            isequal(c, s) || (shadow[i] = copy_shadow_element(K, s))
        end
    end
    for i in (nc + 1):limit
        push!(shadow, copy_shadow_element(K, source[i], policy, depth + 1))
    end
    _fit_shadow_tail!(shadow, source, policy, limit, ns)
end

# Trim to what is kept, and — when the policy kept only a prefix — leave one
# placeholder standing for the rest. Policy-agnostic: the placeholder is asked
# for, never constructed here, and it is given a view of what it stands for so it
# can say how much that is.
function _fit_shadow_tail!(shadow, source, policy, limit::Int, ns::Int)
    want = limit < ns ? limit + 1 : limit
    for _ in 1:(length(shadow) - want)
        pop!(shadow)
    end
    limit < ns || return shadow
    cur = length(shadow) >= want ? shadow[want] : nothing
    new = unsynced_placeholder(policy, HiddenElements(source, limit + 1, ns), cur)
    new === cur && return shadow
    length(shadow) >= want ? (shadow[want] = new) : push!(shadow, new)
    shadow
end
