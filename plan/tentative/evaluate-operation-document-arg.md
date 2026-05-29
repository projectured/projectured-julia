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

### Reader purity is preserved

A natural worry is that making `ReplaceSelectionOperation` carry a document
reference forces the reader to "know" the root document and therefore breaks
reader purity. It does not.

The reader already receives the document as input — `projection_read` is given
the document it is reading against. Including that same document reference in
the operation it returns is still a pure transformation: same inputs in, same
operation value out. Purity is about determinism and absence of side effects,
not about whether the output value happens to hold a reference to one of the
inputs. The reader does not *capture mutable state*; it just *passes through*
a reference that was handed to it.

So the operations produced by the reader can carry the document when
necessary (as `ReplaceSelectionOperation` would) or not (as all the others
already do), and the reader remains pure either way.

### Arguments against

- **Redundant reference storage.** The editor *already* holds the document.
  Putting it into every `ReplaceSelectionOperation` (the most common
  operation) duplicates the reference — though this is one pointer per
  short-lived operation value, not meaningful overhead.

---

## Option B: Keep the `document` argument — editor provides context

Keep `evaluate_operation(op, document)`. The editor injects the root document
at evaluation time; operations remain lightweight value objects.

### Arguments for

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
- **Command/invoker separation.** An operation describes *what* to do; the
  editor (invoker) provides *where*. This separation is a stylistic
  preference, not a purity requirement — Option A also works — but some
  may find it clearer.

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

**Option A (remove the `document` argument; operations are self-contained).**

Rationale:

1. **Consistency wins.** 12 of 13 concrete operations already embed their
   target. The `document` argument exists for exactly one operation. Aligning
   that one with the rest gives every operation the same shape: a
   self-describing command.

2. **Reader purity is not at risk.** The reader receives the document as
   input and produces operations from it; passing that reference through into
   the operation value is still a pure transformation. The earlier draft
   over-weighted this concern.

3. **Self-contained operations are easier to log, replay, serialise, and
   undo.** Each operation entry stands on its own without needing an
   ambient "current document" supplied at evaluation time.

4. **The `_document` noise goes away.** 12 methods stop declaring a parameter
   they never use.

The remaining concerns — extension points for an evaluation context (undo
log, transaction handle, timestamps) — can be added later as a separate
argument *when actually needed*, without forcing every present-day operation
to accept a document it ignores. Option C (an `EvaluationContext`) remains
available as a future move if those needs materialise.

### Minimal action items

- Change the signature of `evaluate_operation` in `api/Operation.jl` to
  `evaluate_operation(operation::Operation)`.
- Add a `document::Document` field to `ReplaceSelectionOperation`.
- Update the reader pipeline that constructs `ReplaceSelectionOperation` to
  pass the root document it already has access to.
- Drop the `_document` parameter from the 12 methods that ignore it.
- Update the editor's call site to `evaluate_operation(editor.operation)`.
- If/when undo/redo or transactional evaluation lands, introduce an
  `EvaluationContext` as a second argument at that point (Option C).
