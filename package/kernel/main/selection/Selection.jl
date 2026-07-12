# Fragment of `SelectionModule` — the selection primitives: read, clear, set,
# replace, and canonicalize a document's current selection, propagating it down
# the document hierarchy. A selection's payload is a `ReferencePath`, and setting
# one folds node types against the live document, so these sit one layer above
# references (whose paths they carry) and above the document contract (whose
# `.selection` field they read), and one layer below the operations that drive
# them (`ReplaceSelectionOperation`, `SelectNextInsertionOperation`).
#
# See documentation/concepts.md for the document-editing model these are part of.

"""
    get_selection(document) -> reference or nothing

The document's current selection — a reference path or `nothing`. Every
document has one (the [`Document`](@ref) contract requires a `selection`
field); the default reads that conventional field, so a concrete document gets
it for free, and one that stores its selection differently overrides this
method.
"""
get_selection(document::Document) = document.selection

"""
    clear_selection!(document)

Recursively clears the selection from `document` and all its children.
Sets the document's `selection` field to `nothing` and traverses the reference
path to clear selections from nested structures.
"""
function clear_selection!(document)
    hasproperty(document, :selection) || return
    sel = getfield(document, :selection)
    path = sel[]
    sel[] = nothing
    path isa ConcreteReferencePath || return
    # Descend into the child the path's head step routes to (see `_selection_child`,
    # which returns `nothing` when the head terminates here — a leaf char cursor,
    # a stale/cross-domain step, or a non-Document field) and clear it too.
    child = _selection_child(document, path)
    child === nothing && return
    clear_selection!(child)
end

"""
    set_selection!(document, path)

Recursively sets the selection on `document` and its children to `path`.

The path is first **canonicalized** against `document`: it is stripped to its
plain navigation skeleton and then re-annotated so every node records the
`typeof` the document it stands on (see `annotate_reference_types` — in the
folded model the type is a *field* on each path node, not a separate step). This
is the single binding point that makes every stored selection self-describing —
callers hand in a plain navigation skeleton (built with `@reference`) and it
becomes canonical against the live document. Annotation is idempotent on an
unchanged document.
"""
function set_selection!(document, path)
    canonical = path === nothing ? path :
                annotate_reference_types(document, strip_reference_types(path))
    _set_selection_walk!(document, canonical)
end

"""
    with_selection(document, path) -> document

Construct-and-select convenience: `set_selection!(document, path)` then return
`document`, so a freshly-built document literal can be selected in a single
expression. See [`set_selection!`](@ref) for the propagation/canonicalization
semantics.
"""
with_selection(document, path) = (set_selection!(document, path); document)

# Internal recursive walker: assumes `path` is already canonical and writes each
# suffix into the matching child's selection cell, descending one navigation step
# per level.
function _set_selection_walk!(document, path)
    if hasproperty(document, :selection)
        getfield(document, :selection)[] = path
    end
    path isa ConcreteReferencePath || return
    # Descend into the child this step routes to and write the remaining tail there
    # (see `_selection_child`: `nothing` means the step terminates at a leaf here).
    child = _selection_child(document, path)
    child === nothing && return
    _set_selection_walk!(child, path.tail)
end

"""
    replace_selection!(document, path)

Replaces the current selection on `document` with `path`.
This is equivalent to calling `clear_selection!(document)` followed by
`set_selection!(document, path)`, ensuring the old selection is fully cleared
before setting the new one.
"""
function replace_selection!(document, path)
    clear_selection!(document)
    set_selection!(document, path)
end

# ── Incremental selection replacement ──────────────────────────────────────
#
# `update_selection!` is the caret-move fast path used by
# `ReplaceSelectionOperation`. It produces exactly the same stored state as
# `replace_selection!` (each level still holds the *whole remaining reference*,
# so every reader is unaffected), but writes the **shared selection chain in
# place**, touching only the cells whose content actually changed:
#
#   * `set_selection!` stores `child.selection === parent.selection.tail` (the
#     same path objects), and `ConcreteReferencePath`'s head/tail — and a
#     `RangeReference`'s start/stop — are themselves `Cell`s. A caret move
#     within a leaf therefore differs from the stored selection only in the
#     terminal cursor step's start/stop: we mutate those two cells in place and
#     rewrite **no** `selection` cell on the path. Unchanged routing ancestors
#     (e.g. a tabbed pane's active-tab cell, which reads only the head step)
#     are not invalidated, so partial rendering repaints only the caret.
#
#   * Where the path structurally diverges, we clear just the old divergent
#     branch and `set_selection!` the new suffix from the divergence point down,
#     then fix the parent path's `.tail` cell in place to keep the chain shared
#     — so cells *above* the divergence stay untouched too.
#
# The eager reactive engine has no value-equality short-circuit (see
# Reactive.jl), so the whole point is to avoid the *writes*, not to rely on the
# engine to absorb redundant ones.
function update_selection!(document, path)
    hasproperty(document, :selection) || return
    _sync_selection!(document, path)
    return
end

# Sync `document`'s selection subtree to `path`, reusing the existing chain in
# place wherever possible. Returns the value now held by `document.selection`
# so the caller can keep its own path tail pointing at it (chain sharing).
function _sync_selection!(document, path)
    hasproperty(document, :selection) || return path
    cell = getfield(document, :selection)
    old = cell[]
    (old isa ReferencePath && path isa ReferencePath && is_reference_equal(old, path)) && return old

    if old isa ConcreteReferencePath && path isa ConcreteReferencePath
        old_child = _selection_child(document, old)
        new_child = _selection_child(document, path)
        # Same routing step into the same child Document: keep this cell, recurse
        # into the child and only re-point our tail if the child's value changed.
        if new_child !== nothing && old_child === new_child && old.head == path.head
            new_tail = _sync_selection!(new_child, path.tail)
            getfield(old, :tail)[] === new_tail || (getfield(old, :tail)[] = new_tail)
            return old
        end
        # Terminal cursor moved within the same leaf step: mutate start/stop in
        # place, leaving every selection cell on the path untouched.
        if new_child === nothing && old_child === nothing &&
           is_reference_equal(old.tail, path.tail) && _mutate_terminal_step!(old.head, path.head)
            return old
        end
    end

    # Divergence: clear the old branch hanging here, install the new suffix.
    if old isa ConcreteReferencePath
        oc = _selection_child(document, old)
        oc === nothing || clear_selection!(oc)
    end
    cell[] = path
    if path isa ConcreteReferencePath
        nc = _selection_child(document, path)
        nc === nothing || set_selection!(nc, path.tail)
    end
    return path
end

# The child Document that `path`'s head step descends into, or `nothing` when
# the head terminates at `document` (a leaf cursor: string char, out-of-range,
# or a non-Document field). This is the single descent helper shared by
# `clear_selection!`, `_set_selection_walk!`, and `_sync_selection!`.
function _selection_child(document, path::ConcreteReferencePath)
    h = path.head
    child = if h isa FieldReference
        sym = Symbol(h.name)
        # The path may not match this node (a stale or cross-domain selection):
        # stop walking gracefully rather than throwing FieldError. In the folded
        # model `h` is always the navigation step (the node type is a field), so
        # guard the field's presence explicitly.
        hasproperty(document, sym) || return nothing
        f = getfield(document, sym)
        f isa AbstractCell ? f[] : f
    elseif h isa RangeReference
        document isa AbstractString && return nothing
        idx = h.start + 1
        (!applicable(length, document) || idx < 1 || idx > length(document)) && return nothing
        document[idx]
    else
        return nothing
    end
    child isa Document ? child : nothing
end

# Mutate a terminal cursor step `old` in place to match `new`, returning `true`
# on success. Only `RangeReference` (a character cursor/range) is updated this
# way — its start/stop are `Cell`s shared across every path level, so one write
# moves the caret everywhere it is observed. Any other step type returns
# `false`, leaving the caller to rewrite the selection cell wholesale.
function _mutate_terminal_step!(old::RangeReference, new::RangeReference)
    getfield(old, :start)[] === new.start || (getfield(old, :start)[] = new.start)
    getfield(old, :stop)[]  === new.stop  || (getfield(old, :stop)[]  = new.stop)
    true
end
_mutate_terminal_step!(::Any, ::Any) = false
