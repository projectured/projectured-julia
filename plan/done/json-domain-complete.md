# Make the JSON domain complete (placeholders, Ctrl+Space, insertion caret)

Follow-on to [json-nav-left-walk-loop.md](json-nav-left-walk-loop.md). Goal: every
enumerated caret and tree selection in a JSON document is reachable, the authoring
placeholders (`JsonInsertion` / `JsonNothing`) are navigable and structurally
selectable, and Ctrl+Space toggles text ⇄ structural everywhere.

## What was broken (measured on json_example)

Position-navigation completeness: **23 enumerated positions unreachable** —
- every **string value/key END caret** (`value{len}` / `key{len}`), 22 of them, and
- the **empty insertion buffer** (`.entries[8].value.value{0}`).

Each collides with a following projection-introduced span (a `"` close quote, or
the insertion's `⟨hint⟩·suffix`) and `map_reference_backward` resolved the flat to
the *chrome* span, not the content. Number/bool ends (no close delimiter) were fine,
which pinpointed the cause. Separately, a `JsonInsertion` value was **not tree
selectable** (the tree-nav completeness `@test_broken`), and `JsonNothing` was not
structurally selectable.

## Fixes

All are the one principle — **content wins over the projection's own delimiter at a
shared-flat seam** — applied at three layers:

1. **`SyntaxToText.jl` `SyntaxLeafToText.map_reference_backward`** — a caret at the
   start of a leaf's close span (`close{0}`) redirects to `value{len}`. Mirrors the
   existing open→value redirect in the edit reader. Fixes all 22 string ends (and
   makes an empty `""` string's only caret reachable). Commit a5fd1305.

2. **`InsertionToSyntax.jl` `InsertionToSyntaxLeaf.map_reference_backward`** — the
   suffix (`closing_delimiter{0}`) redirects to `value{len}`, so the empty insertion
   buffer is reachable (type there to fill it). Commit 7da32a9e.

3. **`InsertionToSyntaxLeaf` ∅ maps** — whole insertion `∅ ⇄ ∅` (and whole content
   leaf `.content∅ → ∅`), so a `JsonInsertion` is structurally selectable:
   Alt-navigable, Ctrl+Space on the buffer selects the whole insertion and toggles
   back, Ctrl+Alt+Home selects a root insertion. The ∅ images are **typed** against
   the output/input documents (as the generic `Projection` fallback does) — an
   untyped `@reference()` broke `YamlSequence`'s `.children[i].content.^(inner)`
   composition (under-typed reference; yaml/sequence repl). Commits 6234d591, 44c7ba0a.

4. **`InsertionNothingToSyntaxLeaf`** — structurally selectable via the generic
   `Projection` fallback (typed ∅ + introduced-caret wrap); no bespoke maps. Its
   `print_document` now **forward-maps** the document's selection instead of copying
   it raw — a cursor carried as `proj(p, value{k})` reached the rendered leaf
   unmapped, so `SyntaxLeafToText` could not place it and the label stalled at one
   caret. Forward-mapping unwraps it to the leaf's own `value{k}`, so the `empty
   json` label (and every `*Nothing` label) is char-navigable via `ProjectionReference`
   steps like any literal leaf (root `JsonNothing` 1 → 11 caret states). Commits
   6234d591, 7ea12aae.

Ctrl+Space itself (`@gestures SyntaxCompound`, `Syntax.jl`) already worked; no change.

## Result

- `PositionNavigationComplete` **json: 546 pass / 0 fail / 0 broken** (was 495/22/1).
- `TreeNavigationComplete`: **144 / 0** — the `.entries[8].value` marker dropped.
- New `JsonPlaceholderNavTest` (`test_json_placeholder_navigation`, 13 asserts): the
  Ctrl+Space toggle, the insertion-buffer nav + whole-insertion select + toggle-back,
  `JsonInsertion` tree selection, and a `JsonNothing`-in-context nav + structural select.
- **Zero regressions** vs clean main: catalog 184255/4/407, readers 19782/15/3, repls
  19334/2/16 — all identical; syntax_to_text / mouse_clicks / position_navigations /
  text_nav_invariants clean.

Root `JsonNothing` (a whole document that is a bare empty placeholder) rests a single
cursor (generic fallback) and is insertable; its "empty json" label is display chrome,
not char-navigable — acceptable, since a root nothing is transient (Insert/type at once).

## Steps

- [x] Characterise the 23 unreached positions (all string ends + empty buffer).
- [x] Fix (a) leaf value/close seam → 22 string ends reachable.
- [x] Fix (b) insertion suffix seam → empty buffer reachable (0/160 unreached).
- [x] ∅ maps → JsonInsertion structurally selectable; generic fallback for JsonNothing.
- [x] Type the ∅ images → fix the yaml/sequence under-typed-reference regression.
- [x] Drop the json completeness `@test_broken` markers (position + tree).
- [x] Add `JsonPlaceholderNavTest`; register + export.
- [x] Cross-domain regression sweep vs main — clean.
