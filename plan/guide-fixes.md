Steps 1-11 are already DONE

# Guide Fixes — Step-by-Step Plan

Inconsistencies, errors, and stale content found by cross-referencing the
markdown guides against the actual source code in `program/src/`.

---

## Step 1: Fix `StyledString` → `TextString` everywhere

Files: `guide/design.md`, `guide/document/syntax.md`

- `design.md:181` — change "`StyledString`" to "`TextString`"
- `design.md:186` — change "`Cell{Vector{StyledString}}`" to the actual
  container type `TextText` with `elements::CollectionDocument`
- `syntax.md:41` — change "Each delimiter or value is a `StyledString`" to
  "Each delimiter or value is a `TextString`"

---

## Step 2: Standardise project name to `predj`

Files: `guide/design.md`, `guide/higher-order-projections.md`,
`guide/document/collection.md`, `guide/document/workbench.md`

- `design.md:1` title — change "pred" to "predj"
- All body occurrences of "pred" referring to the project → "predj"
- `higher-order-projections.md:9` — "pred" → "predj"
- `collection.md:4` — "pred" → "predj"
- `workbench.md:13` — "pred" → "predj"

---

## Step 3: Fix SyntaxLeaf/SyntaxNode field descriptions

Files: `guide/design.md`, `guide/document/syntax.md`

- `design.md:181` — fix field order to `open, close, value` (not
  `open, value, close`); add `indentation::Int` and `collapsed::Bool`;
  change type to `TextString`
- `design.md:183` — change `indent::Bool` → `indentation::Int`; add
  `collapsed::Bool`; change `children::Cell` → `children::CellVector`
- `syntax.md` "Types" section — note the actual struct field order
  (`open, close, value`) and list `indentation` and `collapsed` fields

---

## Step 4: Fix JSON type field names in design.md

File: `guide/design.md`

- Lines 170–172 — change "`cell::Cell`" to "`value::String`" (or
  `value::Bool`, `value::Real` per type); `selection::Cell` → `selection::Reference`
- Add `collapsed::Bool` to JsonArray, JsonObject, JsonObjectEntry descriptions

---

## Step 5: Fix Editor struct description in design.md

File: `guide/design.md`

- Lines 283–289 — remove `running::Bool`, add `backend::Backend` as first field
- Match actual: `backend, document, projection, devices, iomap, operation`

---

## Step 6: Fix KeyPress definition and examples in design.md

File: `guide/design.md`

- Lines 271–273 — add `ctrl::Bool` field
- Lines 255–258 — change `KeyPress(:left)` → `KeyPress(:left, false)`, etc.

---

## Step 7: Fix IoMap description in design.md

File: `guide/design.md`

- Lines 116–124 — change the parametric `struct IoMap{Input, Output, Mapping}`
  to describe it as an abstract type with `SimpleIoMap`, `ChildrenIoMap`,
  `ContentIoMap` subtypes (matching `projection-system.md`)

---

## Step 8: Fix `projection_print` signature in design.md

File: `guide/design.md`

- Line 109 — change 3-arg signature to 4-arg:
  `projection_print(projection, input, recursion, reference) → iomap`

---

## Step 9: Fix `evaluate_operation` signature in design.md

File: `guide/design.md`

- Line 660 — change `evaluate_operation(editor, op)` to
  `evaluate_operation(op::ReplaceSelectionOperation, document)` and fix the body
  (remove `editor.document`, just use `document`)

---

## Step 10: Reconcile "Reader status" contradictions in design.md

File: `guide/design.md`

- Lines 326–331 ("What is missing") — update to reflect current state:
  XML reader is implemented, mouse-click exists in TextToGraphics, domain-
  independent projections (Sorting, Reversing, Focusing, etc.) are implemented.
  Keep only genuinely missing items (undo/redo, insert/delete).
- Alternatively, remove the duplicated status section to avoid future drift.

---

## Step 11: Update "only operation" claim in design.md

File: `guide/design.md`

- Line 134 — change "ReplaceSelectionOperation is the only operation defined
  so far" to list or reference the full set (see `operations.md` for the
  canonical list).

---

## Step 12: Fix section numbering in design.md

File: `guide/design.md`

- Section 11 ("The Reference and Selection Mechanism") appears before
  Section 10 ("Key Differences from the Original"). Renumber them
  sequentially: 10, 11 (or whatever order makes sense).

---

## Step 13: Fix ElementReference/PositionReference descriptions

Files: `guide/design.md`, `guide/editor/reference.md`

- `design.md:157–161` — note that these are constructor aliases for
  `RangeReference`, not separate types
- `reference.md:11–12` — clarify that `ElementReference` and
  `PositionReference` are constructors that produce a `RangeReference`

---

## Step 14: Fix text.md constructor examples

File: `guide/document/text.md`

- Lines 19–31 — rewrite examples to use actual constructors:
  `TextString(content; font=font_ubuntu_monospace_regular_18, font_color="red")`
  instead of `TextString("Hello", "bold", "red")`
- `TextNewline` — use `StyleFont` for the font argument, not a bare string

---

## Step 15: Fix graphics.md constructor examples

File: `guide/document/graphics.md`

- Lines 16–42 — remove `StyledString("Hello")` references; use plain strings
  and `Int32` values. Show the `@document`-based transparent construction
  pattern.

---

## Step 16: Fix xml.md reactive access examples

File: `guide/document/xml.md`

- Lines 35–37 — change `text.cell[] = "New text"` to `text.cell = "New text"`
  (the `@document` macro provides transparent `setproperty!`).

---

## Step 17: Add `TextText` to text.md

File: `guide/document/text.md`

- Add `TextText` (the container type) to the Types section. Currently only
  span types are listed.

---

## Step 18: Add WorkbenchAssistant to workbench.md

File: `guide/document/workbench.md`

- Add `WorkbenchAssistant` to the document types table (it is exported and
  has a matching projection `WorkbenchAssistantToWidgetScrollPane`).

---

## Step 19: Add collapsed/indentation fields to domain guides

Files: `guide/document/json.md`, `guide/document/syntax.md`

- Document the `collapsed::Bool` field on `JsonArray`, `JsonObject`,
  `JsonObjectEntry`, `SyntaxLeaf`, `SyntaxNode`
- Document the `indentation::Int` field on `SyntaxLeaf`, `SyntaxNode`

---

## Step 20: Harmonise reading order across CLAUDE.md, README.md, getting-started.md

Files: `CLAUDE.md`, `README.md`, `guide/getting-started.md`

- Pick one canonical order and use it in all three files.
  Suggestion: follow README.md (design → getting-started → …).
- `getting-started.md` currently puts reactive-cells first; update to
  match the chosen order or explain why it differs.

---

## Step 21: Add missing domain guides to CLAUDE.md

File: `CLAUDE.md`

- Line 18 — add `widget.md`, `workbench.md`, `collection.md` to the
  per-domain guide list (they are already in README.md).

---

## Step 22: Review design.md text.md reference to "Text" container

File: `guide/design.md`

- Line 186 — change "Text holds a Cell{Vector{StyledString}}" to
  "TextText holds an elements::CollectionDocument" and fix the
  selection description.

---

## Validation

After all fixes, grep for:
- `StyledString` — should have zero hits in `guide/`
- `cell::Cell` in JSON type descriptions — should say `value::String` etc.
- `running::Bool` in Editor descriptions — should be gone
- `pred ` (space after) — verify project name is consistently `predj`
