# Extend the type-in test: post-edit selection + Backspace/Delete

## Goal

The type-in round-trip test (`package/visual/test/editor/TypeinTest.jl`) currently only:

- types **one character** (`KeyPress`) at every caret,
- checks the cursor renders and the **string value** changed,
- but never checks **where the caret lands** after the edit, and never exercises
  **Backspace** or **Delete**.

Extend it so each caret is exercised with three edits — **insert**, **backspace**,
**delete** — and every edit additionally asserts the **post-edit selection** is the
caret at the semantically-correct position.

## What the code already guarantees (so the test can assert it)

`evaluate_operation(::ReplaceStringRangeOperation)` (in
`package/base/main/document/Primitive.jl`) advances the selection **generically**:
after splicing `[s,e)→replacement`, it `set_selection!`s a zero-width caret at
`s + length(replacement)`. So the expected caret is deterministic and
domain-independent:

| edit      | event                              | range spliced | replacement | expected caret |
|-----------|------------------------------------|---------------|-------------|----------------|
| insert    | `KeyPress(ch)`                     | `[k,k)`       | `ch`        | `k + len(ch)`  |
| backspace | `KeyDown(:backspace, Modifiers())` | `[k-1,k)`     | `""`        | `k - 1`        |
| delete    | `KeyDown(:delete, Modifiers())`    | `[k,k+1)`     | `""`        | `k`            |

Boundary rule (uniform across `PrimitiveToText`, `Text`, `InsertionToSyntax`):
**backspace at `k==0` and delete at `k==n` decline** (reader returns `nothing`,
no edit). So at those boundaries the edit is a **no-op**: string unchanged, caret
stays at `k`.

A caret is `PositionReference(k) == RangeReference(k,k)`, so the post-edit selection
compared against `append_reference(target.cursor, PositionReference(expected_pos))`
(the same convention the walk uses to *set* carets), via
`is_reference_equal(strip_reference_types(actual), strip_reference_types(expected))`.

## Design

Rewrite the walker portion of `TypeinTest.jl`:

- `_edit_spec(kind, old, k, ch) -> (event, expected_string, expected_pos, op_expected)`
  — the table above, incl. the boundary-decline branches.
- `_edit_at(document, projection, target, k, ch, kind)` — one round-trip:
  set caret at `k`, print, assert cursor present, `read_intent(event)`, (if
  `op_expected`) assert a `ReplaceStringRangeOperation` (empty replacement for
  delete/backspace), `evaluate_operation`, assert **string == expected_string**
  **and** **caret == expected_pos**. `nothing` at a declined boundary evaluates
  to a safe no-op, so the same code path validates the boundary (unchanged string
  + caret still at `k`).
- `_restore!` — universal: replace the whole current string `[0,n)` with the
  pristine string, so each (position, kind) starts clean.
- `_edit_target` — loops positions × `(:insert, :backspace, :delete)`, restoring
  between edits; one result per `(position, edit)`.
- Result tuple gains an `edit` field: `(ref, position, length, edit, ok, message)`.
  Only `test_typein` destructures results, so this is safe.

Public names/signatures unchanged: `walk_typein(doc, proj; replacement, positions)`,
`test_typein(label, doc, proj; positions)`, `test_typein(example; positions)`.

## Known wrinkles / risks

- **`:texttext` (multi-span `TextBlock`)**: `Text._text_delete` applies the
  boundary rule **per span**, and the reader produces a **per-span** op reference
  (`elements[i].content[range]`) rather than the flat `content[k]` the walk sets.
  So the flat expected model / flat selection comparison may mismatch on
  multi-span TextBlock fields. Plan: implement the flat model, run, and if
  `:texttext` mismatches, either add a flattening comparison or mark those
  `@test_broken` via `_typein_broken_reason` (as with `markdown_rendered`). Verify
  whether any registered example even has a `:texttext` target first.
- Delete/Backspace at mid-string on a domain that **doesn't implement** the delete
  gesture yields `nothing` where an op is expected → a real **Fail** exposing the
  gap (the point of the test). Expect new failures; triage per domain.
- Baseline impact: insertion results now also assert the caret advance (should
  pass — the advance is generic); backspace/delete add 2 new results per caret.

## Steps

1. [x] Rewrite the walker in `TypeinTest.jl` (edit-kind generalization + selection check).
2. [x] Update the file header + docstrings to describe the three edits and the selection assertion.
3. [x] Run `test_typein(json_example)` — happy path confirmed (insert/delete/backspace at interior + selection all pass).
4. [x] Run the full sweep set (json, xml, syntax, text, book) at `:all` — mapped the failure landscape.
5. [x] Triage: mark the known boundary-deletion gaps `@test_broken` with refactor-tied reasons; keep real regressions as `Fail`.
6. [x] Record findings + final baseline here; REALFAIL=0 re-confirmed for all five sweep examples; moved to `plan/done/`.

## Findings (from the trace + full sweep at `:all`)

The extension loads and runs cleanly; **insert + selection passes 100%** everywhere,
and **delete/backspace + selection pass at every interior caret**. All failures are at
the **value↔chrome end-boundary** and are being handled by the in-progress
text-selection representation refactor — the user asked NOT to fix them, so they are
marked `@test_broken` (not `Fail`). Confirmed by tracing json/syntax:

- **Backspace at k==n** (erasing the last char) yields `nothing` in every domain: the
  stored selection is correctly `.field{n}`, but the per-span deletion reader treats
  the end caret as the start of the following chrome span and declines. → the last
  character cannot be erased with Backspace today.
- **Delete at a value's boundary** does not decline: in `syntax` it reaches into the
  following `.sep` span (`delete=.children[4].sep[1]`); on an empty value it emits a
  no-op `[0,1]` delete. (json/xml/book delete-at-end correctly declines → passes.)
- Interior positions (k = 1 … n-1) are all correct for all three edits, incl. the
  post-edit caret.

Harness note: a nested `TextBlock` (a block whose elements are blocks — only `book`)
does not round-trip through the flat-offset splice `_restore!` uses, so those targets
can't be restored between edits; marked broken with the same refactor reason.

Correctness fix made to the harness (not a domain fix): a stray op returned at a
declined boundary is **reported, not evaluated** — evaluating it would mutate the
neighbouring chrome and drift the document under the remaining positions.

### Baseline (full sweep, `positions=:all`)

| example | total | ok | broken | REALFAIL |
|---------|-------|------|--------|----------|
| json    | 480   | 458  | 22     | 0 |
| xml     | 1548  | 1497 | 51     | 0 |
| syntax  | 150   | 125  | 25     | 0 |
| text    | 1347  | 1347 | 0      | 0 |
| book    | 1643  | 1624 | 19     | 0 |

Broken breakdown: end-of-string Backspace (all domains), boundary Delete into chrome
(syntax + book empty title), nested-TextBlock restore (book). All flip from Broken →
Pass automatically when the refactor lands (the reason guard returns `nothing` once a
case starts passing).
