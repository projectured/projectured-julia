# Plan: Should `evaluate_operation` have a `document` argument?

Quick analysis of the current `evaluate_operation(op, document)` signature
and whether the operation should be completely self-contained instead.

---

## Current state

The API signature (`api/Operation.jl`):

```julia
evaluate_operation(operation::Operation, document)
```

The editor calls it as `evaluate_operation(editor.operation, editor.document)`,
always passing the root document.

### How each concrete operation uses the two arguments

| Operation | Uses `document` arg? | Carries its own target? |
|---|---|---|
| `ReplaceSelectionOperation` | **YES** — passes to `clear_selection!(document)` / `set_selection!(document, path)` | No — only carries a `path` |
| `QuitEditorOperation` | No — throws exception | N/A |
| `NumberReplaceRangeOperation` | No (`_document`) | **YES** — `document::PrimitiveNumber` |
| `StringReplaceRangeOperation` | No (`_document`) | **YES** — `document::PrimitiveString` |
| `LoadDocumentOperation` | No (`_document`) | **YES** — `document::Document` |
| `SaveDocumentOperation` | No (`_document`) | **YES** — `document::Document` |
| `ExportDocumentOperation` | No (`_document`) | **YES** — `document::Document` |
| `HideWidgetOperation` | No (`_document`) | **YES** — `widget` |
| `ShowWidgetOperation` | No (`_document`) | **YES** — `widget` |
| `ScrollWidgetOperation` | No (`_document`) | **YES** — `scroll_pane` |
| `SetScrollBarValueOperation` | No (`_document`) | **YES** — `scroll_bar` |
| `SelectTabOperation` | No (`_document`) | **YES** — `widget` |
| `ReplaceFocusPartOperation` | No (shadows it in a lambda) | **YES** — `projection` |
| `Nothing` / fallback | No | N/A |

**Summary:** 12 out of 13 concrete methods ignore the `document` argument.
Only `ReplaceSelectionOperation` uses it.

---

## Option A: Remove the `document` argument — operations fully self-contained

Make `ReplaceSelectionOperation` carry its own root document reference, like
the other operations already do:

```julia
struct ReplaceSelectionOperation <: Operation
    document::Document
    path::ReferencePath
end
```

Signature becomes: `evaluate_operation(op::Operation)`.

### Arguments for

- **Consistency.** Every other operation already carries its target. The
  `document` argument exists solely for `ReplaceSelectionOperation`.
- **Simpler API.** One fewer argument; no need for the editor to thread the
  document through. The evaluate step becomes `evaluate_operation(op)`.
- **Decouples operations from the editor.** An operation is a self-describing
  command that can be logged, serialised, queued, or replayed without needing
  an external document reference.
- **Undo/redo becomes cleaner.** An operation log where each entry is
  self-contained is easier to reason about than one that depends on external
  state passed at evaluation time.

### Arguments against

- **Redundant reference storage.** The editor *already* holds the document.
  Putting it into every `ReplaceSelectionOperation` (the most common
  operation) duplicates the reference.
- **Reader must know the root document.** Today the reader pipeline produces
  operations knowing nothing about the root document — it only knows about
  paths. Making `ReplaceSelectionOperation` carry a document means the reader
  (or something between reader and evaluator) must inject the document
  reference. This either pushes complexity into readers or requires a
  post-processing step.
- **Breaks the reader's purity.** Readers are "purely functional" transforms
  from events to operations. If they must capture a mutable document
  reference, they are no longer pure in the same sense.

---

## Option B: Keep the `document` argument — editor provides context

Keep `evaluate_operation(op, document)`. The editor injects the root document
at evaluation time; operations remain lightweight value objects.

### Arguments for

- **Reader stays pure.** Readers produce operations that describe *intent*
  (a path to select) without needing a reference to the mutable document.
  The editor binds the intent to the document at the last possible moment.
- **Lighter operations.** `ReplaceSelectionOperation` is created on every
  keypress. Keeping it as just a `path` avoids carrying a document pointer
  that is always the same object.
- **Natural extension point.** If `evaluate_operation` ever needs more
  context (e.g. an undo log, a transaction handle), the second argument
  generalises to an "evaluation context" without touching the operation
  structs.
- **Matches the projection pipeline.** `projection_print(projection, input,
  recursion, reference)` also receives its document externally. Using the
  same pattern for evaluation keeps the architecture uniform.

### Arguments against

- **Inconsistency with self-contained operations.** Most operations already
  embed their target, making the `document` argument dead weight for them.
- **The `_document` noise.** 12 methods declare a parameter they never use,
  which is a code smell.

---

## Option C: Hybrid — keep the argument but make it an evaluation context

Replace the bare `document` with an `EvaluationContext` (or reuse
`ProjectionContext` once it exists):

```julia
evaluate_operation(op::Operation, ctx::EvaluationContext)
```

Where `EvaluationContext` carries `document`, plus future fields like
`undo_log`, `transaction`, `timestamp`. Self-contained operations ignore
`ctx`; `ReplaceSelectionOperation` reads `ctx.document`.

This is a superset of Option B and aligns with the `ProjectionContext` plan.

---

## Recommendation

**Option B (keep the `document` argument), with an eye toward Option C.**

Rationale:

1. **`ReplaceSelectionOperation` is the dominant operation** — it fires on
   every cursor movement. Making it self-contained means either the reader
   must capture the root document (breaking reader purity) or a wrapper step
   must inject it (adding mechanism for no gain).

2. **Reader purity matters.** The reader's job is to translate a device event
   into a domain-level intent. The intent "select this path" is independent
   of *which* document receives it. The editor binds intent to document.
   This is the Command pattern: a command object describes *what*, the
   invoker provides *where*.

3. **The `_document` noise is cosmetic.** Julia's convention of prefixing
   unused arguments with `_` already signals this. The cost is negligible
   compared to the architectural benefits of a uniform signature.

4. **Future undo/redo will need context.** When an operation log is added,
   `evaluate_operation` will need access to the log or a transaction handle.
   The second argument is the natural place for this, generalised as an
   `EvaluationContext`.

### Minimal action items

- No signature change needed now.
- When `ProjectionContext` lands, consider whether `EvaluationContext` should
  share structure or remain separate (projection is read-only downward flow;
  evaluation is write-side mutation — likely separate).
- When undo/redo is added, promote `document` to `EvaluationContext`.
