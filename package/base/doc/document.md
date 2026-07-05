# The base document layer (target)

Layer 1 of the `ProjecturedBase` package — the **concrete engine documents**:
Collection (CellVector / CellMatrix / CellTable / ListNode), Primitive
(Bool/Number/String/Insertion), and ScreenDocument (the multi-window screen
model with its window events/ops).

## P7 status: contents still in kernel

Per `plan/pending/kernel-layered-architecture.md`, kernel plan P7 stood up
the ProjecturedBase package (Project.toml, ProjecturedBase.jl, guard skeleton,
tests folder, docs folder) but did not yet move the concrete documents from
`package/kernel/src/document/`. The reason is coupling: `ScreenDocument`
is referenced by `WindowManagingProjection`, and `Primitive` by
`common/Projection.jl`'s default reader; moving any of the three alone
would leave a wrong-direction kernel → base edge. The whole family
migrates together at P8 (the projection split), where the coupling is
resolved by splitting `common/Projection.jl` and migrating the
document-shaped projections wholesale to `base/projection/`.

Once the move lands, this file will describe:

- **Collection** — `CellVector` (reactive sequence container), `CellMatrix`,
  `CellTable`, `ListNode`. Provides the R1 seam method
  `child_reference_steps(::CellVector) = [(RangeReference(i-1, i), node[i]) …]`
  registered on the kernel's `OperationModule`.
- **Primitive** — the editable domain-independent Bool/Number/String
  documents with selection and identity, plus `ReplaceStringRangeOperation`
  / `ReplaceNumberRangeOperation` (the splice-range ops) with their R2
  `reroot_operation` methods.
- **ScreenDocument** — the multi-window screen model, `WindowDocument`,
  and the window events/ops (`WindowClose`, `WindowResize`,
  `WindowDefocus`, `OpenWindowOperation`, `CloseWindowOperation`,
  `ResizeWindowOperation`, `OpenPopupOperation`). `EventEnvelope` no
  longer lives here — it moved to `GestureModule` in kernel plan P5 (R5).

## What belongs in base/document

Membership test: a document type belongs in base if it is **shipped for
reuse** by every domain (not editor-loop machinery) and is
**domain-independent** (no domain concept in its structure). Collection,
Primitive, and ScreenDocument all pass; Json, Xml, etc. don't (they are
per-slice domain content).
