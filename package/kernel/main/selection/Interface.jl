# Fragment of `SelectionModule` — the selection **interface**: the open generics
# that read, clear, set, replace, and incrementally update a document's current
# selection. A document with unconventional selection storage overrides these;
# the default implementations (and the private path-walking helpers) live in
# `Selection.jl`.
#
# See documentation/concepts.md for the document-editing model these are part of.

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
"""
function set_selection! end

"""
    with_selection(document, path) -> document

Construct-and-select convenience: `set_selection!(document, path)` then return
`document`, so a freshly-built document literal can be selected in a single
expression. See [`set_selection!`](@ref) for the propagation/canonicalization
semantics.
"""
function with_selection end

"""
    replace_selection!(document, path)

Replaces the current selection on `document` with `path`. Equivalent to
`clear_selection!(document)` followed by `set_selection!(document, path)`,
ensuring the old selection is fully cleared before setting the new one.
"""
function replace_selection! end

"""
    update_selection!(document, path)

Incrementally move the selection to `path`, producing the same stored state as
[`replace_selection!`](@ref) but writing the **shared selection chain in place** —
touching only the cells whose content actually changed. The caret-move fast path:
a cursor move within one leaf mutates just that step's cells, leaving every
routing ancestor's `selection` cell untouched (so partial rendering repaints only
the caret).
"""
function update_selection! end
