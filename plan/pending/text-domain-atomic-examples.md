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
      instead of the flat-only `_text_range_caret(sel)`. (5 files.)
- [x] Verify: the repro keeps the cursor present across every edit on the `text` projection.

### Phase 2 — atomic text example documents

- [ ] Add `make_text_*_document_example` factories in `visual/example/document/Text.jl`,
      one meaningful instance per text type: `string`, `newline`, `spacing`, `graphics`
      (span types), `block`, `line` (containers), plus the insertion kit `nothing`,
      `insertion`. Mirror the JSON leaf/compound split.
- [ ] Register them as `AtomicDocument(:text, "...", ...)` in `visual_atomic_documents`.
- [ ] Teach the catalog to derive text/graphics variants for a document already **at**
      the text level (today `_text_sequence` filters the identity path, so a text atom
      gets no variant). A text atom's `:text` variant = identity/decorator; its
      `:graphics` variant = `_TEXT_TO_GRAPHICS`.

### Phase 3 — tests green

- [ ] `test_typein` on each text atom (add `:text` to the `test_typeins` sweep set, or
      cover via the catalog).
- [ ] `test_position_navigation` / completeness on each `:graphics` text atom.
- [ ] Re-check the existing `text` / `text_with_image` nav `@broken` markers
      (`NAV_LEFT_WALK_STALLS`): if the forward-map fix resolves the left/right asymmetry,
      promote them; otherwise keep with an updated reason.
- [ ] Fix the `TextNewline.font_color = ""` string-default artifact (a `StyleColor` field
      defaulting to a `String` makes the type-in walk treat it as editable text with no
      caret) — or skip style fields in the walk, matching how `StyleFont` is skipped.

### Phase 4 — sweep & land

- [ ] `test_visual()` + umbrella text sweeps: no new `Fail`/`Error`, `@broken` count only
      drops.
- [ ] Move this plan to `plan/done/`.

## Notes / decisions

- The fix is deliberately localized to the decorators' **forward** map (cursor rendering);
  backward map stays flat-only (the decorator output is always flat). Revisit only if a
  test needs a structural backward map.
- This is the incremental, non-refactor path referenced by the type-in test's
  `_typein_broken_reason` ("text-selection representation refactor"). It does not unify the
  two representations — it makes the decorators tolerate both.
