# Syntax Tree Selection

Preliminary plan for selecting a *whole* syntax element — a full `SyntaxNode`, `SyntaxLeaf`, or wrapper (`SyntaxDelimitation`, `SyntaxIndentation`, …) — as a single unit, in addition to the character-level cursor selections that already exist (`.open{k}`, `.value{k}`, `.close{k}`, `.children[i]…`).

## Motivation

Today a selection inside the syntax domain always lands *inside* a leaf or node (a character cursor in a delimiter/value, or a child index). There is no way to say "the entire `[1, 2, 3]` array node is selected" or "this whole identifier leaf is selected" as one atom. Whole-element selection is needed for:

- range edits (cut/copy/paste a subtree, drag-and-drop a node)
- structural navigation (expand selection to enclosing node, shrink to first child)
- visual highlighting of the active subtree
- mapping selections cleanly **backward** from text/cursor positions to the enclosing syntax element, and **forward** from a domain-level element (a `JsonArray`, an `XmlElement`) into the syntax tree and onward to text.

## Design Sketch

### 1. A "whole element" reference

Introduce a marker reference step that addresses *the element itself* rather than a position inside it. Two options to evaluate:

- **(a) `SelfReference`** — a new `ReferenceStep` meaning "this node, as a whole". A selection path that ends in `SelfReference` denotes whole-element selection. Cheap and explicit.
- **(b) Empty-path convention** — interpret a `ReferencePath` that terminates at a `SyntaxNode`/`SyntaxLeaf` (no further `.value` / `.children` step) as whole-element selection. No new type, but ambiguous against "no cursor placed yet".

Lean toward (a); revisit during implementation.

### 2. Selection storage

Same recursive `selection::Reference` cells already in place — only the *terminal* step changes. A node selected as a whole stores `SelfReference` (or the agreed marker) in its `selection` cell; ancestors store the path to it as today.

### 3. Range / multi-element selection (stretch)

A second pass can add a *range* selection over sibling children: e.g. `.children[2..4]` selects three adjacent subtrees. Out of scope for the preliminary plan but the marker design should not preclude it — keep the reference step extensible.

### 4. Backward mapping (text → syntax element)

Reader side of `SyntaxToText` and the various `*ToSyntax` projections must translate:

- a character-cursor selection in text → the **enclosing** syntax element when the user issues a "select enclosing" gesture
- a click that lands on a delimiter or whitespace boundary → the node whose delimiter it is

Each projection's `iomap` already round-trips positions; extend it so that a `SelfReference` on the *output* side resolves to `SelfReference` on the corresponding *input* node.

### 5. Forward mapping (domain element → syntax → text)

When upstream code sets the selection to "this `JsonArray`" (whole element), the printers must:

- propagate `SelfReference` through the printer chain (`JsonToSyntax` → `SyntaxToText`)
- in text, render as a *range highlight* spanning open-delimiter start to close-delimiter end of the syntax node it printed

This is symmetric to (4): the iomap must carry `SelfReference` in both directions.

### 6. Editor surface (later)

- Keyboard: `Ctrl+Shift+Up` expand selection to enclosing element; `Ctrl+Shift+Down` shrink.
- Mouse: double-click on a leaf selects the whole leaf; triple-click selects the enclosing node.

Not part of the first slice — the first slice is the data model and iomap plumbing.

## First Slice (what to actually build first)

**Status: done.** Chose option (b) — the empty-path convention — over option (a)
(`SelfReference`). A whole-element selection is **not a distinct reference step**;
it is just a path that terminates *at* the element, i.e. an `EmptyReferencePath`
(`∅`). Each node stores only its remaining path, so the one node whose `selection`
cell holds `∅` is the wholly-selected one; ancestors hold a non-empty path routing
down to it, and descendants hold `nothing`. A `SelfReference` marker was built
first and then removed: it was an unnecessary extra degree of freedom, since tree
position already disambiguates and `evaluate_reference(doc, ∅)` already returns the
element. Tests: `test/src/projection/SyntaxTreeSelectionTest.jl`
(`test_syntax_tree_selection`).

1. ✅ No new reference type. `evaluate_reference(document, EmptyReferencePath())`
   already returns the element itself — that *is* the whole-element semantics.
2. ✅ `set_selection!` / `replace_selection!` / `clear_selection!` accept
   `∅`-terminated paths with no change: the `∅` terminal falls through their
   `path isa ConcreteReferencePath || return` guard (no child to recurse into).
3. ✅ `@reference_case` gained a writable **empty-path pattern** `∅` (the macro
   already matched zero-step patterns internally; there was just no surface
   syntax). `∅ => @reference()` maps a whole-element selection through as
   identity. The macro's no-match fallthrough is unchanged (`nothing`).
4. ✅ Selection mappers carry `∅` both ways. `@reference_case`-based mappers use
   the `∅ => @reference()` branch (default fwd, JSON leaf/array/object fwd+bwd,
   `SyntaxLeafToText` fwd); the flat-offset mappers and printer cells keep a small
   `x isa EmptyReferencePath && return @reference()` guard. A whole `JsonArray`/
   `JsonObject`/`SyntaxLeaf` round-trips `∅`; a *nested* whole-child survives the
   syntax level as `.children[i]` (terminating `∅`) and back to `.elements[i]`.
5. ✅ Tests added (forward/backward for array, object, leaf; the empty-path
   predicate; `set_selection!`/`clear_selection!` placing `∅` at the target node;
   nested whole-child round-trip).

### Deferred (not in this slice)

- **Text-range highlight for a nested child.** `SyntaxNodeToText` flattens all
  children into one `TextText`, so a nested `.children[i]` (terminating `∅`)
  cannot be a `∅` on that text — it must become a *sub-range* spanning the
  child's open-delimiter start to close-delimiter end (plan §5). `_syntax_to_flat`
  returns `-1` for a `∅` terminal today, so the nested case degrades to *no
  highlight* (graceful, no crash) rather than rendering a range.
- **Visual highlighting in `TextToGraphics`.** The text→graphics layer renders a
  cursor (point), not a range box; drawing the highlight is part of the editor
  surface below.
- **Editor surface (plan §6):** expand/shrink keybindings, double/triple-click.
- **Range / multi-element selection (plan §3).**

## Open Questions

- ~~Does whole-element selection need a dedicated reference step?~~ **Resolved: no.** It is the empty path (`∅`); the default `map_reference_forward`/`backward` and the `@reference_case` `∅` pattern pass it through, so any domain (XML, filesystem, …) inherits whole-element selection for free.
- How should whole-element selection compose with `ProjectionReference` (projection-introduced delimiters)? Probably: an `∅` selection on a projection-introduced node is allowed and renders as that delimiter's range.
- Interaction with `ContentIoMap` wrappers (`Dragging`, navigation overlays) — confirm they pass an `∅` selection through unchanged.
