# INI: full text + tree navigation

Goal: make both navigation tests pass for the `ini` example:

- `test_text_navigation(ini_example; check_reaches_all=true)` — every enumerated
  text caret reachable (add `ini` to `_text_navigation_complete_examples`).
- `test_tree_navigation(ini_example)` — Ctrl+Alt+Home seeds a whole-element
  selection and Alt+arrows navigate the structure with no errors.

All work is in `program/src/projection/primitive/IniToSyntax.jl`
(plus the two completeness-list edits in the test module).

## Diagnosis (text completeness, 96 unreached carets)

Three categories, all the documented `syntax` delimiter-boundary limitation:

1. **`value{0}` / `path{0}`** — the `" = "` separator and `"include "` keyword
   are *separate* `SyntaxLeaf`s, so the value's start caret sits on a leaf↔leaf
   boundary that maps to a flat `ProjectionReference`, never `.value{0}`.
   JSON passes because its delimiters live in the *same* leaf's `.open` span.
   **Fix:** fold the separator/keyword into the following leaf's `.open` span so
   `value{0}` / `path{0}` becomes an intra-leaf open|value boundary.
2. **Inline comments** (`entries[*].comment`) — comment leaf has no selection
   cell and no reference mapping. **Fix:** add a selection cell + map
   `comment ↔ children[N].value`.
3. **Section names** (`children[*].name`) — `[name]` is baked into the
   `SyntaxNode.open` delimiter (non-navigable chrome). **Fix:** restructure the
   section so the heading is a navigable `SyntaxLeaf` (`open="["`/`"[Config "`,
   `value=name`, `close="]"`), nested as the first child of an inline section
   node whose second child is the indented entry body.

## Diagnosis (tree nav seeding)

Ctrl+Alt+Home → `ReplaceSelectionOperation(EmptyReferencePath())` at the
SyntaxToText layer; `IniFileToSyntaxNode.map_reference_backward(∅)` returns
`nothing` (no `∅` case), so seeding fails. **Fix:** add whole-element `∅ ↔ ∅`
mapping to every IniToSyntax `map_reference_forward`/`backward` (consistent with
the whole-element-selection design).

## Section layout

**Design decision (changed from the nested-body-wrapper idea):** make the
heading leaf and the entries *siblings* of one inline section node, rather than
nesting entries inside a separate body node.

```
section = SyntaxNode(open="", close="", sep="\n    ", indentation=0,
                     children=[heading_leaf, entry₁, entry₂, …], collapsed=s.collapsed)
heading_leaf = SyntaxLeaf("[" | "[Config ", "]", name)
```

- name → `children[1].value`; entries[i] → `children[i+1]`.
- The separator carries the newline + 4-space indent (sections always sit one
  level under the file), so the heading renders at column 2 and entries at 4 —
  visually identical to before, with one cleaner blank line between sections.
- **Why siblings, not a body wrapper:** a body wrapper node has no INI-domain
  equivalent, so `children[2]∅` maps to nothing and tree navigation cannot
  descend *through* it into the entries. As siblings, Alt+arrows reach every
  entry. Trade-off: collapsing the section now folds the heading too (collapse
  is not exercised for `ini` by any test, and INI examples are never collapsed).
- `test_printer` only forces cells (no byte comparison), so the layout tweak is
  safe; mouse-click / click-roundtrip roundtrips still pass.

Node `sel` cells (file + section) mirror `map_reference_forward` (delegating
through child IO maps) so the syntax node carries the full structural path —
needed for cursor/highlight rendering *and* to drive tree navigation at depth.

## Parts

- [x] Add `∅ ↔ ∅` to all IniToSyntax map_reference functions (tree-nav seeding).
- [x] Config option / param assignment: fold `" = "` into value leaf `.open`;
      drop the separate eq leaf; remap key→children[1], value→children[2],
      comment→children[3].
- [x] Make inline comments navigable: selection cell + `comment↔children[3].value`.
- [x] Include: collapse to a single leaf with `"include "` in `.open`; remap path.
- [x] Insertion: add `∅↔∅` + reader (was missing, latent `map_reference_forward`).
- [x] Restructure section: navigable heading leaf + entries as siblings; remap
      name→children[1].value, entries→children[i+1].
- [x] Add `ini` to `_text_navigation_complete_examples`.
- [x] Verify: `test_example` (5328), text-nav check_reaches_all (928, was 96
      unreached), tree-nav (76 states, 0 errors), mouse-click, click-roundtrip,
      text-nav-invariants, `test_ini`, and the `*_complete` / tree-nav suites.
</content>
