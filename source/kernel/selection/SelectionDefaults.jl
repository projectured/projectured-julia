# Fragment of `SelectionModule` — the defaults of the generics and the path-walk helpers.

get_selection(document::Document) =
    hasfield(typeof(document), :selection) ? document.selection : nothing

# No document keeps a dormant selection unless it says so.
has_dormant_selection(::Any) = false

# The path a `selection` cell holds, live or dormant.
#
# `get_selection` answers only the live one, because the property read unwraps a
# dormant selection to `nothing`. The writers below need the path either way: what
# they are abandoning is exactly what a dormant node still holds.
_get_stored_path(value) = value
_get_stored_path(value::SelectionDocument) = value.primary
is_live_selection(document) = _is_live_value(hasfield(typeof(document), :selection) ?
                                            getfield(document, :selection)[] : nothing)
_is_live_value(value) = true
_is_live_value(value::SelectionDocument) = value.live

# Map a document's selection forward through `map` and carry the live/dormant
# state onto the image. A live selection maps to a bare reference, exactly as a
# plain `map_reference_forward` did; a dormant one maps to a wrapper that says so,
# which is what lets the state survive a projection chain.
#
# `map_missing` decides what happens when the source holds no selection at all. It
# is `false` by default, because most callers guard on `nothing` before mapping.
# A projection that **introduces** a selection maps `nothing` to a real image, so
# such a caller passes `true` and lets the mapper answer for the missing path.
function map_selection_forward(source, map; map_missing::Bool = false)
    path = get_stored_selection(source)
    (path === nothing && !map_missing) && return nothing
    image = map(path)
    image === nothing && return nothing
    is_live_selection(source) ? image : SelectionDocument(; primary = image, live = false)
end

get_stored_selection(document) =
    hasfield(typeof(document), :selection) ?
        _get_stored_path(getfield(document, :selection)[]) : nothing

function clear_selection!(document)
    hasfield(typeof(document), :selection) || return
    sel = getfield(document, :selection)
    path = _get_stored_path(sel[])
    sel[] = nothing
    path isa ConcreteReference || return
    # Descend into the child this step routes to and clear it too.
    child = _selection_child(document, path)
    child === nothing && return
    clear_selection!(child)
end

"""
    SelectionMismatchException(document, path)

Thrown by the selection writers ([`set_selection!`](@ref) /
[`replace_selection!`](@ref)) when `path` does not match `document`: a routing
step names a field the node lacks, indexes past the end of a sized container, or
lands on a node whose folded type no longer holds. The stored selection is left
untouched — a selection either matches and applies, or fails without half-writing.
"""
struct SelectionMismatchException <: Exception
    document::Any
    path::Any
end

Base.showerror(io::IO, e::SelectionMismatchException) =
    print(io, "SelectionMismatchException: selection path ", e.path,
          " does not match a document of type ", typeof(e.document))

# ── Dormant selections ─────────────────────────────────────────────────────
#
# At a divergence the old branch is cleared, or kept and marked dormant when a
# document on it asks to keep it. Marking walks the same path as a clear and
# writes a flag.

# Whether the branch `divergence` is abandoning is kept. The walk starts at the
# divergence node **itself** and goes down the abandoned path; the first `true`
# keeps the whole branch. Inclusive because a keeper can sit below the divergence
# or be the divergence.
function _keeps_branch(owner, divergence, old_path)
    # The owner of the divergence node first. A document that holds its
    # alternatives in a collection has that collection as the divergence, because
    # the step that differs belongs to the collection — while the document that
    # knows the children are alternatives is the one above it.
    (owner !== nothing && has_dormant_selection(owner)) && return true
    has_dormant_selection(divergence) && return true
    node = divergence
    path = old_path
    while path isa ConcreteReference
        node = _selection_child(node, path)
        node === nothing && return false
        has_dormant_selection(node) && return true
        path = path.tail
    end
    false
end

# Mark this node and everything below it on its own stored path as dormant. The
# paths stay exactly where they are; only the flag changes.
function _mark_dormant!(document)
    hasfield(typeof(document), :selection) || return
    cell = getfield(document, :selection)
    value = cell[]
    path = _get_stored_path(value)
    path === nothing && return
    if value isa SelectionDocument
        value.live && (value.live = false)
    else
        cell[] = SelectionDocument(; primary = path, live = false)
    end
    path isa ConcreteReference || return
    child = _selection_child(document, path)
    child === nothing || _mark_dormant!(child)
end

# A path that ends on a keeper holding a dormant selection is extended by it, so
# the focus coming back makes the whole branch live again. `path` must already be
# canonical; the caller re-validates the result and falls back when it is stale.
function _restore_selection(document, path)
    node = document
    rest = path
    while rest isa ConcreteReference
        child = _selection_child(node, rest)
        child === nothing && return path
        node = child
        rest = rest.tail
    end
    has_dormant_selection(node) || return path
    hasfield(typeof(node), :selection) || return path
    value = getfield(node, :selection)[]
    (value isa SelectionDocument && !value.live) || return path
    dormant = value.primary
    dormant isa ConcreteReference || return path
    concat_references(path, dormant)
end

# Canonicalize `path` against `document` (see `set_selection!`) and require it to
# still match before any selection cell is written — throwing `SelectionMismatchException`
# without touching the stored selection when it does not. `nothing` (a clear)
# always matches. This is the single validate-then-write gate every selection
# writer passes through, so a stale/cross-domain path fails atomically instead of
# leaving a half-written selection.
function _matched_selection(document, path)
    path === nothing && return nothing
    canonical = annotate_reference_types(document, strip_reference_types(path))
    _selection_matches(document, canonical) ||
        throw(SelectionMismatchException(document, canonical))
    restored = _restore_selection(document, canonical)
    restored === canonical && return canonical
    # A dormant path can name a node an edit has since removed. Canonicalize and
    # match the extension too, and fall back to the plain path when the extension
    # does not match — a stale memory must not fail the write that woke it.
    extended = annotate_reference_types(document, strip_reference_types(restored))
    _selection_matches(document, extended) ? extended : canonical
end

# A canonical selection matches `document` iff its **routing** resolves — every
# field, element index and folded node type along the way. We delegate that to the
# reference layer's tested resolver (`is_valid_reference`) after removing a
# terminal caret: a cursor step (`start == stop`) addresses a position *inside* a
# leaf, and a text leaf exposes no length/index, so the resolver would reject a
# real caret. Dropping it validates the path up to the node the caret sits on and
# accepts the caret by reachability, while still failing a missing field, an
# out-of-range element, or a stale type.
_selection_matches(document, canonical) =
    is_valid_reference(document, _drop_terminal_cursor(canonical))

_drop_terminal_cursor(path::EmptyReference) = path
function _drop_terminal_cursor(path::ConcreteReference)
    if path.tail isa EmptyReference && path.head isa RangeReferenceStep &&
       path.head.start == path.head.stop
        # Terminal caret: stop at the node it sits on, keeping that node's type.
        return EmptyReference(path.type)
    end
    ConcreteReference(path.type, path.head, _drop_terminal_cursor(path.tail))
end

function set_selection!(document, path)
    _set_selection_walk!(document, _matched_selection(document, path))
    document
end

# Internal recursive walker: assumes `path` is already canonical and writes each
# suffix into the matching child's selection cell, descending one navigation step
# per level.
function _set_selection_walk!(document, path)
    if hasfield(typeof(document), :selection)
        getfield(document, :selection)[] = path
    end
    path isa ConcreteReference || return
    # Descend into the routed child and write the remaining tail there.
    child = _selection_child(document, path)
    child === nothing && return
    _set_selection_walk!(child, path.tail)
end

"""
    @selected(document)
    @selected(document, path)

Construct-and-select in one expression: evaluate `document` once, then select
`path` in it. Without a `path` the whole node is selected.

    @selected JsonBool(false)              # whole node
    @selected JsonString("") value{0}      # caret at the path

`path` is the [`@reference`](@ref) step DSL, typed against the document that was
just built — the same as the two-argument `@reference(document, path)` form, so
no `::T` is spelled by hand. The document expression is bound once, which is what
the DSL needs (typing a path is a *runtime* operation against the value) and what
a bare `set_selection!(build(), @reference(???, path))` cannot express.
"""
macro selected(document, path...)
    length(path) <= 1 ||
        throw(ArgumentError("@selected takes a document and at most one path"))
    d = gensym("document")
    # The reference is built through `ReferenceModule.@reference` under its own
    # module, so the calling module needs only `@selected` in scope.
    selection = isempty(path) ?
        :($annotate_reference_types($d, $EmptyReference())) :
        Expr(:macrocall, Expr(:., ReferenceModule, QuoteNode(Symbol("@reference"))),
             __source__, d, path[1])
    esc(:(let $d = $document
              $set_selection!($d, $selection)
          end))
end

function replace_selection!(document, path)
    hasfield(typeof(document), :selection) || return
    _sync_selection!(document, _matched_selection(document, path))
    return
end

# ── In-place selection replacement ─────────────────────────────────────────
#
# `_sync_selection!` moves the selection to a new (canonical) path while keeping
# the stored state identical to a `clear`-then-`set` rebuild — each level still
# holds the *whole remaining reference*, so every reader is unaffected — but it
# writes the **shared selection chain in place**, touching only the cells whose
# content actually changed:
#
#   * `set_selection!` stores `child.selection === parent.selection.tail` (the
#     same path objects), and `ConcreteReference`'s head/tail — and a
#     `RangeReferenceStep`'s start/stop — are themselves `Cell`s. A caret move
#     within a leaf therefore differs from the stored selection only in the
#     terminal cursor step's start/stop: we mutate those two cells in place and
#     rewrite **no** `selection` cell on the path. Unchanged routing ancestors
#     (e.g. the cell of a container that reads only the head step)
#     are not invalidated, so partial rendering repaints only the caret.
#
#   * Where the path structurally diverges, we clear just the old divergent
#     branch and `set_selection!` the new suffix from the divergence point down,
#     then fix the parent path's `.tail` cell in place to keep the chain shared
#     — so cells *above* the divergence stay untouched too.
#
# The eager reactive engine has no value-equality short-circuit (see
# ReactiveCell.jl), so the whole point is to avoid the *writes*, not to rely on the
# engine to absorb redundant ones.
#
# Returns the value now held by `document.selection` so the caller can keep its
# own path tail pointing at it (chain sharing).
function _sync_selection!(document, path, owner = nothing)
    hasfield(typeof(document), :selection) || return path
    cell = getfield(document, :selection)
    stored = cell[]
    old = _get_stored_path(stored)
    # A live write through a node revives it: the wrapper goes, the path stays.
    stored isa SelectionDocument && (cell[] = old)
    (old isa Reference && path isa Reference && is_reference_equal(old, path)) &&
        return old

    if old isa ConcreteReference && path isa ConcreteReference
        old_child = _selection_child(document, old)
        new_child = _selection_child(document, path)
        # Same routing step into the same child Document: keep this cell, recurse
        # into the child and only re-point our tail if the child's value changed.
        if new_child !== nothing && old_child === new_child && old.head == path.head
            new_tail = _sync_selection!(new_child, path.tail, document)
            getfield(old, :tail)[] === new_tail || (getfield(old, :tail)[] = new_tail)
            return old
        end
        # Terminal cursor moved within the same leaf step: mutate start/stop in
        # place, leaving every selection cell on the path untouched.
        if new_child === nothing && old_child === nothing &&
           is_reference_equal(old.tail, path.tail) &&
           _mutate_terminal_step!(old.head, path.head)
            return old
        end
    end

    # Divergence: the old branch hanging here is cleared, or kept and marked
    # dormant when a document on it asks to keep it. Then install the new suffix.
    if old isa ConcreteReference
        oc = _selection_child(document, old)
        if oc !== nothing
            _keeps_branch(owner, document, old) ? _mark_dormant!(oc) :
                                                  clear_selection!(oc)
        end
    end
    cell[] = path
    if path isa ConcreteReference
        nc = _selection_child(document, path)
        nc === nothing || set_selection!(nc, path.tail)
    end
    return path
end

# The child Document that `path`'s head step descends into, or `nothing` when
# the head terminates at `document` (a leaf cursor: string char, out-of-range,
# or a non-Document field). This is the single descent helper shared by
# `clear_selection!`, `_set_selection_walk!`, and `_sync_selection!`.
function _selection_child(document, path::ConcreteReference)
    h = path.head
    child = if h isa AFieldReferenceStep
        sym = Symbol(h.name)
        # The path may not match this node (a stale or cross-domain selection):
        # stop walking gracefully rather than throwing FieldError. In the folded
        # model `h` is always the navigation step (the node type is a field), so
        # guard the field's presence explicitly.
        hasfield(typeof(document), sym) || return nothing
        unwrap_cell(getfield(document, sym))
    elseif h isa ARangeReferenceStep
        document isa AbstractString && return nothing
        _find_indexed_child(document, h.start + 1)
    else
        return nothing
    end
    child isa Document ? child : nothing
end

# The element at `index` of a sequence, or `nothing` past its ends. A sequence
# with a length is checked against it. One with none, such as a link of a list
# that can be endless, is indexed as `evaluate_reference_step` indexes it, and
# an index past its ends names no child.
function _find_indexed_child(document, index::Integer)
    if applicable(length, document)
        (1 <= index <= length(document)) || return nothing
        return document[index]
    end
    applicable(getindex, document, index) || return nothing
    try
        document[index]
    catch exception
        exception isa BoundsError || rethrow()
        nothing
    end
end

# Mutate a terminal cursor step `old` in place to match `new`, returning `true`
# on success. Only `RangeReferenceStep` (a character cursor/range) is updated this
# way — its start/stop are `Cell`s shared across every path level, so one write
# moves the caret everywhere it is observed. Any other step type returns
# `false`, leaving the caller to rewrite the selection cell wholesale.
function _mutate_terminal_step!(old::RangeReferenceStep, new::RangeReferenceStep)
    getfield(old, :start)[] === new.start || (getfield(old, :start)[] = new.start)
    getfield(old, :stop)[]  === new.stop  || (getfield(old, :stop)[]  = new.stop)
    true
end
_mutate_terminal_step!(::Any, ::Any) = false
