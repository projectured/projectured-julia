# Fragment of `SelectionModule` — the selection **interface**: the open generics
# that read, clear, set, and replace a document's current selection. A document
# with unconventional selection storage overrides these; the default
# implementations (and the private path-walking helpers) live in `SelectionDefaults.jl`.

"""
    get_selection(document) -> reference or nothing

The document's current selection — a reference path or `nothing`. Every document
has one (the [`Document`](@ref) contract requires a `selection` field); the
default reads that conventional field, so a concrete document gets it for free,
and one that stores its selection differently overrides this method.
"""
function get_selection end

"""
    clear_selection!(document)

Recursively clears the selection from `document` and all its children. Sets the
document's `selection` field to `nothing` and traverses the reference path to
clear selections from nested structures.
"""
function clear_selection! end

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

The canonical path must also **match** `document` — every routing step still
resolving — or a [`SelectionMismatch`](@ref) is thrown *before any cell is
written*, leaving the current selection untouched. A selection either matches and
applies or fails; it is never half-written. (A terminal caret is accepted by
reachability, since a text leaf exposes no length/index to replay it against.)
"""
function set_selection! end

"""
    with_selection(document, path) -> document

Construct-and-select convenience: `set_selection!(document, path)` then return
`document`, so a freshly-built document literal can be selected in a single
expression. See [`set_selection!`](@ref) for the propagation/canonicalization
semantics.

To select a path that must be *typed against* the document being built, use
[`@with_selection`](@ref): it binds the freshly-built document once and hands it
to the `@reference` DSL.
"""
function with_selection end

"""
    replace_selection!(document, path)

Change `document`'s current selection to `path`, replacing whatever was selected
before; pass `nothing` to clear it.

Like [`set_selection!`](@ref), `path` is **canonicalized** against `document`
first (stripped to its navigation skeleton, then re-annotated) and required to
**match** — a non-matching path throws [`SelectionMismatch`](@ref) before any
cell is written, so a failed apply never changes the selection. On a match,
instead of clearing and rebuilding every selection cell on the path, the new path
is written into the
**shared selection chain in place**: only the cells whose content actually
changed are touched, and any old branch that diverges from the new path is
cleared. A caret move within one leaf mutates just that step's start/stop cells,
leaving every routing ancestor's `selection` cell untouched — so partial
rendering repaints only the caret.
"""
function replace_selection! end

"""
    keeps_dormant_selection(document) -> Bool

Whether `document` keeps a selection the live one has left behind, instead of
having it cleared.

`false` for every document by default, so nothing changes for a document that
does not ask. A document answers `true` when its children are alternatives and it
has to remember which one it was showing — a tab group is the case this exists
for: the tab it shows is the tab its own selection names, so clearing that
selection makes it forget.

What a keeper keeps is **dormant**: still stored, still drawable, never acted on.
See [`SelectionDocument`](@ref).

The question is asked at a divergence, starting at the divergence node itself and
walking down the branch that is being abandoned. The first `true` keeps the whole
branch below the divergence. The node itself is included because the two trees
that need this put the keeper on opposite sides: a pane group sits below the
divergence, while a tabbed pane **is** the divergence.
"""
function keeps_dormant_selection end

"""
    get_stored_selection(document) -> reference or nothing

The path `document` holds, live **or** dormant.

[`get_selection`](@ref) answers only the live one, because a dormant selection
reads as `nothing` — the default that keeps every reader written against a bare
reference correct. A reader that has to see a dormant path asks for it here, and
says so by asking.

A tab group is the case this exists for: the tab it shows is the tab its own
selection names, and it must still show that tab while the focus is elsewhere.
"""
function get_stored_selection end

"""
    is_live_selection(document) -> Bool

Whether the selection `document` holds is the live one. `true` when it holds none,
so a document with no selection never looks dormant.
"""
function is_live_selection end

"""
    map_selection_forward(source, map) -> image or nothing

The forward image of `source`'s selection, carrying its live/dormant state.

A printer wires its output's selection from its input's, and it must use this
rather than reading the property: the property answers `nothing` for a dormant
selection, so a plain read drops the state at the first hop and the painter at the
end of the chain has nothing left to paint pale.

`map` receives the stored path and returns the image, normally through
`map_reference_forward`.
"""
function map_selection_forward end
