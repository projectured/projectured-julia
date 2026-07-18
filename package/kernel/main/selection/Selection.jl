# Fragment of `SelectionModule` — the default implementations of the selection
# generics declared in `Interface.jl`, plus the private path-walking helpers they
# share (`_selection_child`, `_set_selection_walk!`, `_sync_selection!`,
# `_mutate_terminal_step!`). All read and write the conventional
# `document.selection` field and descend the folded reference path.

get_selection(document::Document) = document.selection

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
    SelectionMismatch(document, path)

Thrown by the selection writers ([`set_selection!`](@ref) /
[`replace_selection!`](@ref)) when `path` does not match `document`: a routing
step names a field the node lacks, indexes past the end of a sized container, or
lands on a node whose folded type no longer holds. The stored selection is left
untouched — a selection either matches and applies, or fails without half-writing.
"""
struct SelectionMismatch <: Exception
    document::Any
    path::Any
end

Base.showerror(io::IO, e::SelectionMismatch) =
    print(io, "SelectionMismatch: selection path ", e.path,
          " does not match a document of type ", typeof(e.document))

# Canonicalize `path` against `document` (see `set_selection!`) and require it to
# still match before any selection cell is written — throwing `SelectionMismatch`
# without touching the stored selection when it does not. `nothing` (a clear)
# always matches. This is the single validate-then-write gate every selection
# writer passes through, so a stale/cross-domain path fails atomically instead of
# leaving a half-written selection.
function _matched_selection(document, path)
    path === nothing && return nothing
    canonical = annotate_reference_types(document, strip_reference_types(path))
    _selection_matches(document, canonical) || throw(SelectionMismatch(document, canonical))
    canonical
end

# A canonical selection matches `document` iff its **routing** resolves — every
# field, element index and folded node type along the way. We delegate that to the
# reference layer's tested resolver (`is_valid_reference`) after removing a
# terminal caret: a cursor step (`start == stop`) addresses a position *inside* a
# leaf, and a text leaf exposes no length/index, so the resolver would reject a
# real caret (see the base `SelectionEnumeration` note). Dropping it validates the
# path up to the node the caret sits on and accepts the caret by reachability,
# while still failing a missing field, an out-of-range element, or a stale type.
_selection_matches(document, canonical) =
    is_valid_reference(document, _drop_terminal_cursor(canonical))

_drop_terminal_cursor(path::EmptyReferencePath) = path
function _drop_terminal_cursor(path::ConcreteReferencePath)
    if path.tail isa EmptyReferencePath && path.head isa RangeReferenceStep &&
       path.head.start == path.head.stop
        # Terminal caret: stop at the node it sits on, keeping that node's type.
        return EmptyReferencePath(path.type)
    end
    ConcreteReferencePath(path.type, path.head, _drop_terminal_cursor(path.tail))
end

function set_selection!(document, path)
    _set_selection_walk!(document, _matched_selection(document, path))
end

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

with_selection(document, path) = (set_selection!(document, path); document)

"""
    @with_selection(document)
    @with_selection(document, path)

Construct-and-select in one expression: evaluate `document` once, then select
`path` in it. Without a `path` the whole node is selected.

    @with_selection JsonBool(false)              # whole node
    @with_selection JsonString("") value{0}      # caret at the path

`path` is the [`@reference`](@ref) step DSL, typed against the document that was
just built — the same as the two-argument `@reference(document, path)` form, so
no `::T` is spelled by hand. The document expression is bound once, which is what
the DSL needs (typing a path is a *runtime* operation against the value) and what
a bare `with_selection(build(), @reference(???, path))` cannot express.
"""
macro with_selection(document, path...)
    length(path) <= 1 ||
        throw(ArgumentError("@with_selection takes a document and at most one path"))
    d = gensym("document")
    # The reference is built through `ReferenceModule.@reference` under its own
    # module, so the calling module needs only `@with_selection` in scope.
    selection = isempty(path) ?
        :($annotate_reference_types($d, $EmptyReferencePath())) :
        Expr(:macrocall, Expr(:., ReferenceModule, QuoteNode(Symbol("@reference"))),
             __source__, d, path[1])
    esc(:(let $d = $document
              $with_selection($d, $selection)
          end))
end

# Change `document`'s selection to `path`, replacing any previous selection.
# `path` is canonicalized and required to match (`_matched_selection` throws
# `SelectionMismatch` on a stale/cross-domain path, before any cell is written),
# then written into the shared selection chain **in place** by `_sync_selection!`
# — see the algorithm note on that helper for why this touches only the cells that
# actually changed instead of clearing and rebuilding every selection cell.
function replace_selection!(document, path)
    hasproperty(document, :selection) || return
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
#     same path objects), and `ConcreteReferencePath`'s head/tail — and a
#     `RangeReferenceStep`'s start/stop — are themselves `Cell`s. A caret move
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
# ReactiveCell.jl), so the whole point is to avoid the *writes*, not to rely on the
# engine to absorb redundant ones.
#
# Returns the value now held by `document.selection` so the caller can keep its
# own path tail pointing at it (chain sharing).
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
    child = if h isa FieldReferenceStep
        sym = Symbol(h.name)
        # The path may not match this node (a stale or cross-domain selection):
        # stop walking gracefully rather than throwing FieldError. In the folded
        # model `h` is always the navigation step (the node type is a field), so
        # guard the field's presence explicitly.
        hasproperty(document, sym) || return nothing
        unwrap_cell(getfield(document, sym))
    elseif h isa RangeReferenceStep
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
