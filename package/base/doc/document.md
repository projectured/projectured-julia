# The base document layer

Layer 1 of the `ProjecturedBase` package — the **concrete engine documents**:
Collection (CellVector / CellMatrix / CellTable / ListNode) and Primitive
(Bool/Number/String/Insertion).

- **Collection** — `CellVector` (reactive sequence container), `CellMatrix`,
  `CellTable`, `ListNode`. Provides the seam method
  `child_reference_steps(::CellVector) = [(RangeReference(i-1, i), node[i]) …]`
  registered on the kernel's `OperationModule`.
- **Primitive** — the editable domain-independent Bool/Number/String
  documents with selection and identity, plus `ReplaceStringRangeOperation`
  / `ReplaceNumberRangeOperation` (the splice-range ops) with their
  `reroot_operation` methods.

`ScreenDocument` — the multi-window screen model, `WindowDocument`, and the
window events/ops (`WindowClose`, `WindowResize`, `WindowDefocus`,
`OpenWindowOperation`, `CloseWindowOperation`, `ResizeWindowOperation`,
`OpenPopupOperation`) — does **not** live here even though it would pass the
membership test below: window things are visual, so it lives in
`visual/screen/` instead. `EventEnvelope` does not live with it either — it
lives in the kernel's `GestureModule`, because it is a protocol type
consumed by the editor loop and gesture recognizer, not a document concept.

## What belongs in base/document

Membership test: a document type belongs in base if it is **shipped for
reuse** by every domain (not editor-loop machinery) and is
**domain-independent** (no domain concept in its structure). Collection and
Primitive pass; Json, Xml, etc. don't (they are per-slice domain content).
