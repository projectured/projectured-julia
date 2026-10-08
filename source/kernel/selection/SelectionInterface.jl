# Fragment of `SelectionModule` — nine generics; `SelectionDefaults.jl` holds the bodies.

"""
    get_selection(document) -> reference or nothing

Where the cursor stands in a document, or nothing when it stands nowhere.

Use it to read what a person has selected before acting on it: the word under
the caret, the row of a table, the tab a click landed in. It answers a
reference, which is a path to the place, not the value there.

# Example

    place = get_selection(document)
    place === nothing || println("the cursor is at ", place)

See also `set_selection!`, which moves it, and `get_referenced_value`, which
reads what is there.

The document's current selection — a reference path or `nothing`. The default
reads the conventional `selection` field, so a concrete document gets it for
free. A document without that field has no selection of its own, and the
default answers `nothing`, as `set_selection!` passes over it. A document that
stores its selection differently overrides this method.
"""
function get_selection end

"""
    clear_selection!(document)

Take the cursor out of a document.

Use it before showing a document that nobody is editing, or to drop a selection
that an edit made meaningless. It clears the selection along the path that
`document` holds, so no part on that path keeps a stale place.

# Example

    clear_selection!(document)
    get_selection(document)        # nothing

See also `set_selection!` and `get_selection`.

Sets the `selection` field of `document` to `nothing` and follows the path that
it held, to clear the selection of each document on that path. A selection on
another branch stays, for example a dormant one.
"""
function clear_selection! end

"""
    set_selection!(document, path) -> document

Put the cursor at a place in a document, and return `document`, so a
freshly-built document literal can be selected in a single expression.

Use it to build a document that nothing holds yet, so that it opens with
something already selected. The path is made canonical against the document
first, so a path written by hand reaches the same place as one the editor built.

# Example

    set_selection!(document, @reference(document, rows[2].name))

See also `get_selection`, `clear_selection!`, and `replace_selection!`, which
moves the cursor. To select a path that must be *typed against* the document
being built, use [`@selected`](@ref): it binds the freshly-built document once
and hands it to the `@reference` DSL.

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
resolving — or a [`SelectionMismatchException`](@ref) is thrown *before any cell is
written*, leaving the current selection untouched. A selection either matches and
applies or fails; it is never half-written. (A terminal caret is accepted by
reachability, since a text leaf exposes no length/index to replay it against.)
"""
function set_selection! end

"""
    replace_selection!(document, path)

Change `document`'s current selection to `path`, replacing whatever was selected
before; pass `nothing` to clear it.

Use it to move the caret after an edit, or to select what a search found. Call
it on the root document, the one that holds the whole tree, so that the old
place leaves no second cursor behind.

# Example

    replace_selection!(root, @reference(root, rows[2].name))

See also `set_selection!`, which selects in a document that nothing holds yet,
and `get_selection`.

Like [`set_selection!`](@ref), `path` is **canonicalized** against `document`
first (stripped to its navigation skeleton, then re-annotated) and required to
**match** — a non-matching path throws [`SelectionMismatchException`](@ref)
before any cell is written, so a failed apply never changes the selection. On a
match, instead of clearing and rebuilding every selection cell on the path, the
new path is written into the **shared selection chain in place**: only the cells
whose content actually changed are touched, and any old branch that diverges
from the new path is cleared. A caret move within one leaf writes the
`selection` cell of the leaf once and writes no `selection` cell of an ancestor,
so partial rendering repaints only the caret. The start and stop cells of a
range step are written in place only where the path of the leaf starts with
that range step.
"""
function replace_selection! end

"""
    has_dormant_selection(document) -> Bool

Whether `document` keeps a selection the live one has left behind, instead of
having it cleared.

`false` for every document by default, so nothing changes for a document that
does not ask. A document answers `true` when its children are alternatives and it
has to remember which one it was showing: the alternative that it shows is the
one that its own selection names, so clearing that selection makes it forget.

What a keeper keeps is **dormant**: still stored, still drawable, never acted on.
See [`SelectionDocument`](@ref).

The question is asked at a divergence, starting at the divergence node itself and
walking down the branch that is being abandoned. The first `true` keeps the whole
branch below the divergence. The node itself is included because a keeper can
sit below the divergence or **be** the divergence.
"""
function has_dormant_selection end

"""
    get_stored_selection(document) -> reference or nothing

The path `document` holds, live **or** dormant.

[`get_selection`](@ref) answers only the live one, because a dormant selection
reads as `nothing` — the default that keeps every reader written against a bare
reference correct. A reader that has to see a dormant path asks for it here, and
says so by asking.

A document that shows one of several alternatives is the case this exists for:
it shows the alternative that its own selection names, and it must still show it
while the focus is elsewhere.
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
