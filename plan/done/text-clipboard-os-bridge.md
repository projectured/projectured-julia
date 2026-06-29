# Text-domain clipboard (copy/cut/paste) with OS bridge

> **Status: DONE (2026-06-29).** Follow-up to `plan/done/clipboard-os-bridge-and-run-example-wrapper.md`.
> `run_example(plain_text_example; clipboard=true)` (and the other `TextText` examples) now
> support copy/cut/paste over **character ranges**, with the ProjecturEd clipboard as the
> primary store and the **OS clipboard** as the paste fallback / copy-mirror.
>
> Outcome notes (vs. the design below):
> - **Text mode is exclusive over a `TextText` content** — when `p.text && input.content isa
>   TextText`, copy/cut/paste run only the text path and never fall through to the node path
>   (which would `evaluate_reference` a character selection and do something surprising).
> - The caret advances for free: a `StringReplaceRangeOperation`'s evaluation runs
>   `_replace_selection_with_cursor!`, so paste needs no trailing `ReplaceSelectionOperation`.
> - **Still requires a clipboard tool** (`xclip`/`xsel`/`wl-*`) for the OS half — absent on the
>   dev box, so OS read returns nothing and OS half is inert there; the ProjecturEd slice works
>   regardless. Verified via a stubbed backend in tests + a full-wrapper end-to-end drive.
> - Single-span ranges only (the `_text_selection_range` shape); cross-line selections decline.
>
> Verification: `test_clipboard_to_any()` green incl. the new 18-assertion `slice text clipboard`
> testset; full-wrapper drive (`make_clipboard_projection(...; text=true)`) gives
> copy→`CompoundOperation` ending in `WriteOsClipboardOperation`, paste(slice)→content-rooted
> `StringReplaceRangeOperation("ZZZ")`, paste(empty)→OS fallback `…("OSTEXT")`; no regression in
> `test_printer/text_navigation(plain_text_example)` (212/210) or
> `test_printer/repl(clipboard_example)` (699/225).

## Problem

The clipboard projection's copy/cut/paste are **node** operations: `_clipboard_copy` does
`evaluate_reference(content, sel)` and expects a `Document`; `_clipboard_paste` does
`replace_document(sel, doc)`. In flat text the selection is a **character range**
(`elements[i].content[a:b]`), not a node, so those readers decline — Ctrl+C/V do nothing for
`plain_text_example`.

The text domain edits via `StringReplaceRangeOperation` (insert/replace a character range), and
`_text_insert(text, str)` already builds exactly that op; after evaluation the caret auto-advances
(`_replace_selection_with_cursor!`). So text clipboard = extract substring on copy, splice-in on
paste.

## Design

A `text::Bool` flag on `ClipboardSliceToAnyProjection`. When set, copy/cut/paste take a
**text branch** that operates on `input.content::TextText` (which carries its own `.selection`,
set by the normal click path):

- **Copy** (`Ctrl+C`): `sub = text_selection_substring(content)` (selected substring within one
  span; declines on an empty caret or multi-span selection). Store it in the slice as
  `TextString(sub)` (the ProjecturEd clipboard), restore the original selection, and append a
  `WriteOsClipboardOperation(sub)` (mirror to OS).
- **Cut** (`Ctrl+X`): store `TextString(sub)` + delete the range (`text_insert_op(content, "")`,
  re-rooted under `content`) + OS mirror.
- **Paste** (`Ctrl+V`): source string = the slice's text if present (`TextString`/`PrimitiveString`
  → its value), else `os_clipboard_read()` (the **fallback**). Emit
  `text_insert_op(content, str)` re-rooted under `content` — a `StringReplaceRangeOperation` that
  replaces the selected range / inserts at the caret; the caret advances for free.

In text mode the OS clipboard is always used (mirror on copy/cut, fallback on paste) — for text it
is just strings, so it is type-safe and is the whole point of the request. With `text=false`
(default) nothing changes; the node path and all existing tests are untouched.

### Wiring

- `TextModule` exposes two public helpers: `text_selection_substring(text)` and
  `text_insert_op(text, str)` (a thin alias for the existing `_text_insert`).
- `ClipboardToAny` imports `TextText` / `TextString` / `PrimitiveString` + those helpers, adds the
  `text` field + keyword, and the text branch in `_clipboard_copy/cut/note/paste/paste_copy`.
- `make_clipboard_projection(projection; text=false, …)` threads `text` to the slice projection.
- `run_example`'s clipboard branch sets `text = (document isa TextText)` so the text examples get
  it automatically; no new user-facing flag.

## Tests

- `ClipboardToAnyTest.jl` new `slice text clipboard` testset (stubbed OS backend): copy stores
  `TextString(sub)` + mirrors to OS; cut adds the delete op; paste from the slice emits a
  content-rooted `StringReplaceRangeOperation` with the stored text; paste with an empty slice
  falls back to the OS string; `text=false` regression unchanged.
- Programmatic end-to-end on the `plain_text` clipboard wrapper (copy → paste), plus
  `test_clipboard_to_any()` and `test_printer/repl(clipboard_example)` for no regression.

## Steps

- [x] TextModule: `text_selection_substring`, `text_insert_op` (+ export).
- [x] ClipboardToAny: `text` field; `_text_clipboard_copy/cut/paste`, `_slice_text`; **exclusive**
      branch in the readers (`p.text && input.content isa TextText`).
- [x] Wrapper + `run_example`: `text` kwarg on `make_clipboard_projection`; `run_example`
      auto-detects `document isa TextText`.
- [x] Tests (`slice text clipboard`, 18 assertions) + full-wrapper end-to-end verification.
- [x] Move to `plan/done/`.
