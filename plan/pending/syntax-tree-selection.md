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

**Status: done.** Decided on option (a), `SelfReference` (rendered `⊙`), as the
whole-element marker. The data-model + iomap plumbing now carries `⊙` through the
JSON → Syntax → Text chain in both directions. Tests live in
`test/src/projection/SyntaxTreeSelectionTest.jl` (`test_syntax_tree_selection`).

1. ✅ Added the `SelfReference` step + `is_self_reference(path)` predicate in
   `ReferenceModule`; `evaluate_reference` returns the element itself for a `⊙`
   terminal. Exported from `Projectured`.
2. ✅ `set_selection!` / `replace_selection!` / `clear_selection!` already accept
   `⊙`-terminated paths: the terminal step falls through their `else` branch (no
   child to recurse into), so no change was needed beyond confirming it.
3. ✅ `SyntaxToText` printer + reader propagate and recover a *top-level*
   whole-element selection (`⊙` on the `TextText`). The default
   `map_reference_forward`/`backward` and every `Syntax*ToText` mapper pass `⊙`
   through unchanged.
4. ✅ `JsonToSyntax` end-to-end: selecting a `JsonArray` or `JsonObject` whole
   propagates `⊙` to the rendered text and round-trips back. The leaf mappers
   (`JsonBool/Number/String → SyntaxLeaf`) and the hand-rolled `JsonObject` `sel`
   cell were extended to pass `⊙` through, so a *nested* whole-child selection
   survives to the syntax level as `.children[i].⊙` and back to `.elements[i].⊙`.
5. ✅ Tests added (forward/backward for array, object, leaf; the predicate;
   `set_selection!`/`clear_selection!` acceptance; nested whole-child round-trip).

### Deferred (not in this slice)

- **Text-range highlight for a nested child.** `SyntaxNodeToText` flattens all
  children into one `TextText`, so a nested `.children[i].⊙` cannot be a `⊙` on
  that text — it must become a *sub-range* spanning the child's open-delimiter
  start to close-delimiter end (plan §5). `_syntax_to_flat` returns `-1` for a
  `⊙` terminal today, so the nested case degrades to *no highlight* (graceful,
  no crash) rather than rendering a range.
- **Visual highlighting in `TextToGraphics`.** The text→graphics layer renders a
  cursor (point), not a range box; drawing the highlight is part of the editor
  surface below.
- **Editor surface (plan §6):** expand/shrink keybindings, double/triple-click.
- **Range / multi-element selection (plan §3).**

## Open Questions

- ~~Does `SelfReference` belong in `ReferenceModule`, or as a syntax-domain–specific step?~~ **Resolved:** generic, in `ReferenceModule` — the default `map_reference_forward`/`backward` pass it through, so any domain (XML, filesystem, …) inherits whole-element selection for free.
- How should whole-element selection compose with `ProjectionReference` (projection-introduced delimiters)? Probably: `SelfReference` on a projection-introduced node is allowed and renders as that delimiter's range.
- Interaction with `ContentIoMap` wrappers (`Dragging`, navigation overlays) — confirm they pass `SelfReference` through unchanged.
