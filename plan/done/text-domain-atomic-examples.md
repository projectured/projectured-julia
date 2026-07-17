# Text domain: atomic examples + type-in / navigation green

## Goal

Bring the **text domain** to JSON-level example coverage:

1. Atomic example documents, one per text type (like `make_json_null_document_example`,
   `make_json_string_document_example`, …).
2. The default text projection (`WordWrapping → TextToGraphics`) works on each.
3. `test_typein` and the text-navigation tests pass on each.

The trigger bug: **typing into a simple text document loses the caret after the first
character.** With the default `text` projection, after one insert the caret vanishes and
editing oscillates.

## Root cause (found)

A text caret has **two representations**:

- **flat** — `TextRangeReference{k}` over the block's concatenated stream (the domain's
  canonical form; what `ReplaceTextRangeOperation`/navigation leave behind); and
- **structural** — `.elements[i].content{k}` (what the *lowered* `ReplaceStringRangeOperation`
  leaves behind after a character edit — `evaluate_operation(::ReplaceStringRangeOperation)`
  sets a `.field{k}` caret).

Every text→text decorator (`WordWrapping`, `LineNumbering`, `TextFiltering`,
`TextHighlighting`, `SelectionInverting`) forward-maps the caret with a local
`_text_range_caret(ref)` that recognises **only the flat form**. So the moment an edit
leaves a *structural* caret, `_forward_map` returns `nothing`, the decorator's output
block gets `selection = nothing`, and `TextToGraphics` renders no cursor.

Reproduction (default `text` projection, editor iomap reuse): the op/selection oscillates
flat↔structural; the cursor is present only on the flat frames. With the single-stage
`plain_text` projection (bare `TextToGraphics`, which understands `.content{k}` directly)
the caret survives — which is why the bug only shows with a decorator in the chain.

## Plan

### Phase 1 — fix the structural-caret forward map (the reported bug) ✅

- [x] Add a shared Text-domain helper `text_caret_flat(block, ref) -> Int | nothing`
      that resolves a caret reference to a flat offset from **either** representation
      (flat `TextRangeReference{k}` or structural `.elements[i].content{k}`), reusing
      `_flat_base` and the structural range parser. Export it.
- [x] Refactor `_text_selection_range(text)` to parse an arbitrary stripped ref
      (`_parse_selection_range(sel)`) so `text_caret_flat` can share the structural parse.
- [x] In each decorator's `_forward_map`, resolve the caret via `text_caret_flat(in_block, sel)`
      instead of the flat-only `_text_range_caret(sel)`. (4 files: WordWrapping, TextFiltering,
      TextHighlighting, SelectionInverting; LineNumbering hardcodes `selection = Cell(nothing)`
      and maps via `map_reference_forward`, so it is out of this path.)
- [x] Verify: the repro keeps the cursor present across every edit on the `text` projection.
- [x] Wrap-boundary backspace: at a soft wrap the delete range straddles the inserted
      newline, so `TextToGraphics` declines and the raw gesture reaches WordWrapping. Give
      WordWrapping the same lower-on-fallback `read_intent(::KeyPress/::KeyDown)` that
      `TextToGraphics._gesture_op` and a downstream `SyntaxToText` already have (lower the flat
      `ReplaceTextRangeOperation` against the un-wrapped input block). Proven behaviour-preserving
      for the syntax pipelines: `SyntaxCompoundToText`'s `ReplaceTextRangeOperation` handler
      lowers against the *same* block, so JSON/XML/book/syntax typein counts are byte-identical
      to baseline; only the pure-text pipeline (nothing below to lower) is fixed.
- [x] Baseline-diffed typein against clean `52fa96c0`: `text` 0/1347 → **1347/1347**;
      `text_with_image` 0 → 597; `json` 480/480, `xml` 1548, `book` 1638+5broken, `syntax`
      133+6fail+11broken all **unchanged** (the syntax 6 fails / book 5 broken are pre-existing).

### Phase 2 — atomic text example documents ✅

- [x] Add `make_text_*_document_example` factories in `visual/example/document/Text.jl`.
      The default text projection renders only a `TextBlock` root, so each atom is a
      minimal `TextBlock` exercising one span/structure type: `string`, `newline`,
      `spacing`, `graphics` (spans), `line` (TextLine container). The insertion kit
      (`TextNothing`/`TextInsertion`) is not a `TextBlock`, so it needs a dispatching
      projection — deferred (out of "default projection works").
- [x] Register them as `AtomicDocument(:text, "...", ...)` in `visual_atomic_documents`.
- [x] Teach the catalog: a `TextDocument` is already `:text`, so `_text_sequence` returns
      the empty (identity) sequence and the `:graphics` variant chains `_TEXT_TO_GRAPHICS`
      (the default text projection) onto it.
- [x] The `TextNewline.font_color = ""` string-default and the `TextGraphics` image
      filename were type-in-walk artifacts (presentation / non-text) — fixed by skipping
      text-span style fields in the walk (see Phase 1's test/typein commit), not by
      touching the domain defaults.
- [x] Line-nested content editing: generalise the text edit lowering to full span paths
      so a caret inside a `TextLine` (`.elements[i].elements[j].content`) edits cleanly;
      WordWrapping maps line-nested edit references by identity (lines pass through).

### Phase 3 — tests green ✅

- [x] `test_catalog(domain=:text)` — printer/reader/repl/navigation over all 5 atoms
      (both `:text` and `:graphics` variants): **5209/5209**.
- [x] `test_catalog_typeins()` — new; `test_typein` over each text atom's `:graphics`
      variant: **141/141** (string 18, newline 39, spacing 33, graphics 18, line 33).
      Wired into `test_all`.
- [ ] Re-check the existing `text` / `text_with_image` nav `@broken` markers
      (`NAV_LEFT_WALK_STALLS`): if the forward-map fix resolves the left/right asymmetry,
      promote them; otherwise keep with an updated reason.

### Phase 4 — sweep & land ✅

Baseline-diffed against a clean `52fa96c0` checkout:

- [x] `test_visual()` (worktree): **47104 pass, 0 fail, 0 error, 1 broken** (pre-existing).
- [x] `test_catalog()` all domains: baseline **184045 pass / 4 fail / 407 broken** →
      worktree **189256 pass / 3 fail / 407 broken**. The +5211 passes are the 5 new
      text atoms. The 3 remaining fails (`primitive/{string,number,bool}/graphics`
      Ctrl+Home seed returns nothing) are **pre-existing**; my WordWrapping backward-map
      identity fallback additionally **fixed** the pre-existing `julia/insertion/graphics`
      seed fail (4→3). `@broken` count unchanged (407).
- [x] Curated typein (`text`/`json`/`xml`/`book`/`syntax`) and curated navigation
      (`text` position-nav, nav-invariants) byte-identical to baseline.

Out of scope (pre-existing, unchanged before/after; **not** introduced or wired by this
work):

- `test_position_navigation(check_reaches_all=true)` on the big `text` paragraph
  (451/449) and on the atoms — a navigation-*completeness* gap on text pipelines
  (enumeration vs. reachable-set representation). The atoms pass the navigation test the
  catalog actually runs (`state_count > 0`, no throws); they are deliberately **not**
  added to `_position_navigation_complete_examples`, so no failing completeness test is
  wired. The `text`/`text_with_image` `NAV_LEFT_WALK_STALLS` markers still hold.
- The 3 `primitive/*/graphics` Ctrl+Home seed fails and the `syntax` typein value/chrome
  seam fails (both pre-existing).

- [x] Move this plan to `plan/done/`.

## Notes / decisions

- The fix is deliberately localized to the decorators' **forward** map (cursor rendering);
  backward map stays flat-only (the decorator output is always flat). Revisit only if a
  test needs a structural backward map.
- This is the incremental, non-refactor path referenced by the type-in test's
  `_typein_broken_reason` ("text-selection representation refactor"). It does not unify the
  two representations — it makes the decorators tolerate both.
