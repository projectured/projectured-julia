# Layer 16 — iomap (`source/kernel/iomap/`)

Commit 15b40434, 2026-09-27. Seal state: 2 of 4 sealed (`IoMapModule.jl`,
`IoMapInterface.jl`).

## Verdict

The iomap layer is small and holds no process-global state. Its caches live in cell
closures and are pruned on each computation, so they do not grow without bound. The
most important finding is L16-1: the reconcilers call `make_iomap`, and so a whole
child printer, inside their own computation. Each eager read of that printer becomes
a dependency of the child list, and each write of that printer happens inside a
computation. The layer has no unit test in the kernel test package; only projections
in higher packages test it (L16-3). The projection guide teaches `ChildrenIoMap` with
code that throws (L16-2).

## Shape

- Purpose: the record that a print leaves. `IoMap` and its three accessors, three
  general IoMaps (`SimpleIoMap`, `ChildrenIoMap`, `ContentIoMap`), the `@iomap`
  macro, and the two reconcilers that keep the IoMap of a child while its element
  stays the same.
- Files:

  | file | lines | seal | what it holds |
  | --- | ---: | --- | --- |
  | `IoMapModule.jl` | 35 | 🔒 | docstring, two `using`, one `export`, three `include`s |
  | `IoMapInterface.jl` | 67 | 🔒 | `abstract type IoMap` and the three accessor declarations |
  | `IoMapDefaults.jl` | 96 | ⬜ | `@iomap`, the accessor defaults, `SimpleIoMap`, `ChildrenIoMap`, `ContentIoMap` |
  | `IoMapReconcile.jl` | 65 | ⬜ | `reconcile_child_iomaps`, `reconcile_child_iomap` |

- Imports: bare `using` of `CellModule` (layer 3) and `CellStructModule` (4). Its
  imports permit a place just above the struct layer. The owner placed it just below
  the projection layer (`plan/done/extract-iomap-layer.md`). Imported by:
  `ProjectionModule` (17) and `EditorModule` (22) in the kernel, and 45 files outside
  the kernel.
- Public surface: 10 exported names, and each has a user outside the kernel.
  - This repository: `IoMap`, `SimpleIoMap` (about 285 uses), `ChildrenIoMap` (about
    260), `@iomap` (about 100), `get_iomap_output` (47), `reconcile_child_iomap`
    (32), `reconcile_child_iomaps` (22), `get_iomap_input` (19),
    `get_iomap_projection` (12, of them 5 in the file format package and 1 in a test),
    `ContentIoMap` (2 files: file format and layout).
  - omnet-julia uses `SimpleIoMap`, `ChildrenIoMap`, `get_iomap_output`, `@iomap` and
    `reconcile_child_iomaps`. inet-julia uses `SimpleIoMap`, `get_iomap_output` and
    `@iomap`.
- Sealed files: the seal is commit f66f4ba5 (2026-07-19). `IoMapModule.jl` has no
  change of content since then; commit cff9c079 only moved it. `IoMapInterface.jl`
  has the same move and one change, commit 29ad8218 (2026-09-18), docstrings only,
  with the user's permission of that day.
- State: no module-level state. `reconcile_child_iomaps` keeps a `Dict` in the closure
  of its cell and deletes each key that is not live at the end of each computation.
  `reconcile_child_iomap` keeps one value. The readers of a cell are weak references
  ([ReactiveCell.jl:189-190](../../../source/kernel/cell/ReactiveCell.jl#L189)), so an
  evicted child IoMap can be collected. Each IoMap belongs to one print, and so to
  one editor.
- Tests: the kernel test package has no `test/kernel/iomap/`. Four test files of
  higher packages reach the layer:
  - `test/substrate/projection/CopyingProjectionTest.jl`: reuse after an append;
  - `test/substrate/projection/HigherOrderTest.jl`: a branch swap through
    `reconcile_child_iomap`;
  - `test/projectured/editor/PrinterLocalityTest.jl` and `ReactivityTest.jl`: loss
    of identity and stale output over whole examples; they read the accessors.

  L16-3 lists what no test covers.

## Summary

| Category | High | Medium | Low |
| --- | ---: | ---: | ---: |
| Correctness | 0 | 0 | 1 |
| Architecture | 0 | 1 | 0 |
| Shape | 0 | 0 | 2 |
| Types/performance | 0 | 0 | 1 |
| Naming | 0 | 0 | 1 |
| Documentation | 0 | 1 | 1 |
| Tests | 0 | 1 | 0 |

## Findings

### L16-1 The reconcilers run a child printer inside their own computation

- Category: Architecture · Severity: Medium · Confidence: Confirmed for the
  mechanism; Suspected for the size of the effect (it needs a run that lists the
  dependencies of a child-list cell after its first and after a later computation)
- Where: [IoMapReconcile.jl:22-31](../../../source/kernel/iomap/IoMapReconcile.jl#L22) ⬜,
  [IoMapReconcile.jl:56-61](../../../source/kernel/iomap/IoMapReconcile.jl#L56) ⬜
- Evidence: `reconcile_child_iomaps` calls `make_iomap(i, x)` for a new slot inside
  `Cell(@computation …)`, and `reconcile_child_iomap` does the same for a new value.
  While the computation runs, its cell is on the stack of computations of the task, and each `c[]`
  records the top cell of that stack as a reader
  ([ReactiveCell.jl:131-139](../../../source/kernel/cell/ReactiveCell.jl#L131),
  [ReactiveCell.jl:168-172](../../../source/kernel/cell/ReactiveCell.jl#L168)). The
  results:
  1. Each cell that a child printer reads eagerly becomes a dependency of the child
     list. The set depends on the cache: the first computation records the reads of
     every child, and a later one records only those of new slots, because
     `_recompute!` detaches the old edges first (ReactiveCell.jl:168). A write to such
     a cell makes the list and each reader of the list compute again, and the list
     then returns the same cached children. The work changes nothing.
  2. The deferred-iomap write of a child printer runs inside the computation.
     [ScreenToScreen.jl:104](../../../source/screen/ScreenToScreen.jl#L104) does
     `iomap_cell[] = iomap` while the list cell of
     [ScreenToScreen.jl:43](../../../source/screen/ScreenToScreen.jl#L43) computes.
     The cell is new and has no reader yet, so nothing goes invalid now.
  3. A child printer that reads a cell derived from the output of its parent makes a
     cycle through the list cell. No instance is known.
- Rule: PAR-NO-WRITE-IN-THUNK (item 2); PAR-WRITE-DRIVEN-PROPAGATION (item 1: one
  write makes the whole list compute again); PAR-ACYCLIC-CELLS (item 3).
- Fix: call `make_iomap` with no dependency record. The cell layer has `peek` for one
  cell, but no scope without a record. The smallest fix is a primitive there, for
  example `run_untracked(f)`, which runs `f` with an empty stack of computations.
- Reach: `IoMapReconcile.jl`; `cell/ReactiveCell.jl` 🔒 and `cell/CellModule.jl` 🔒
  for the new primitive and its export, which need the owner's permission.

### L16-2 The projection guide teaches a compound printer that throws and that breaks PAR-STABLE-IOMAP-IDENTITY

- Category: Documentation · Severity: Medium · Confidence: Confirmed
- Where: [projection-system.md](../../../documentation/package/kernel/projection-system.md)
  lines 577-582, 596, 611, 616, 624
- Evidence: the example makes `child_iomaps = Cell(@computation([print_child(…) for i
  in …]))`, which prints every child again on each change, and not
  `reconcile_child_iomaps`. The two mappers read `iomap.child_iomaps[]`.
  `ChildrenIoMap` is an `@iomap` struct, so `iomap.child_iomaps` is already the
  vector, and `v[]` on a vector whose length is not 1 throws a `BoundsError`. Real
  code reads `getfield(iomap, :child_iomaps)[]`
  ([LayoutToGraphics.jl:381](../../../source/layout/LayoutToGraphics.jl#L381)). The
  example also builds `ConcreteReference(ElementReferenceStep(Cell(i)), …)` by hand.
- Rule: PAR-HONEST-DOCS; PAR-STABLE-IOMAP-IDENTITY; PAR-REFERENCE-DSL.
- Fix: write the example again with `reconcile_child_iomaps`,
  `iomap.child_iomaps` (no `[]`), and `@reference`.
- Reach: `documentation/package/kernel/projection-system.md`.

### L16-3 The layer has no unit test, and only projections in higher packages test it

- Category: Tests · Severity: Medium · Confidence: Confirmed
- Where: `test/kernel/` (no `iomap/` folder); `test/kernel/KernelSuite.jl` calls no
  iomap test
- Evidence: the tests named under Shape reach the layer through whole projections.
  No test checks these cases:
  - after a delete or a front insert, the children after the change are made again;
  - an element that goes away leaves the cache;
  - one object at two indexes gets two child IoMaps;
  - a `make_iomap` that returns `nothing`;
  - `reconcile_child_iomap` with the same object, and with a new one;
  - the supertype that `@iomap` adds, and the kind argument that it accepts;
  - the three accessors.
- Rule: PAR-NEW-CODE-SHIPS-TESTS. The lowest test package that can express these
  cases is `ProjecturedKernelTest`: they need only a cell and a closure.
- Fix: add `test/kernel/iomap/IoMapReconcileTest.jl` and `IoMapDefaultsTest.jl`, and
  call them from `test_kernel()`.
- Reach: `test/kernel/`, `test/kernel/KernelSuite.jl`,
  `package/ProjecturedKernelTest/src/ProjecturedKernelTest.jl`.

### L16-4 Reuse is safe only while the cached value keeps the element alive, and the docstrings do not say so

- Category: Correctness · Severity: Low · Confidence: Suspected (each caller found
  returns an IoMap whose `input` is the element, or `nothing`; a caller that breaks
  the contract needs a run to show the failure)
- Where: [IoMapReconcile.jl:21-33](../../../source/kernel/iomap/IoMapReconcile.jl#L21) ⬜,
  [IoMapReconcile.jl:54-61](../../../source/kernel/iomap/IoMapReconcile.jl#L54) ⬜
- Evidence: the cache key is `objectid(x)`, a number, not a reference to `x`. For a
  mutable object, `objectid` comes from its address, and Julia can give that address
  to a new object after the old one is collected. The cache is safe only because the
  value stored under the key, the child IoMap, holds `x` as its `input`. A
  `make_iomap` that returns an IoMap over a value derived from `x` lets `x` go. A new
  element at the same index and the same address then gets the old child IoMap. The
  docstrings state the key but not this contract.
- Rule: PAR-MODULE-DOCSTRING (state the invariant that the code needs).
- Fix: state in both docstrings that the result must hold the element, or keep `x`
  in the cache entry and compare it with `===`.
- Reach: `IoMapReconcile.jl`.

### L16-5 No IoMap overrides the three accessors, and most readers do not call them

- Category: Shape · Severity: Low · Confidence: Confirmed
- Where: [IoMapInterface.jl:33-67](../../../source/kernel/iomap/IoMapInterface.jl#L33) 🔒,
  [IoMapDefaults.jl:36-45](../../../source/kernel/iomap/IoMapDefaults.jl#L36) ⬜
- Evidence: the docstrings say that an IoMap "that stores it differently overrides
  this". No method overrides any of the three in the three repositories, and each of
  the 84 IoMap struct definitions found has the fields `projection`, `input` and
  `output`. `source/` has 5 calls of `get_iomap_output(` and about 218 direct reads
  of `.output` on an IoMap. Layer 17 reads `hasproperty(iomap, :input) ? iomap.input`
  ([GestureBindings.jl:32](../../../source/kernel/projection/GestureBindings.jl#L32)).
  omnet-julia makes `ChildrenIoMap(nothing, doc, …)` with no projection
  (`source/legacy/simulator/presentation/SimulationToWidget.jl:254`). The three field
  names are the contract in practice, and the accessors are a second way to read
  them.
- Rule: PAR-HONEST-DOCS (the override promise has no use); the size of the surface.
- Fix: the owner chooses one. State the three field names as the contract and keep
  the accessors as plain getters, or send the readers through the accessors. A text
  change in the sealed interface file needs permission.
- Reach: `IoMapInterface.jl` 🔒, `IoMapDefaults.jl`.

### L16-6 `@iomap` names its supertype with a bare symbol, and the module file has one export statement

- Category: Shape · Severity: Low · Confidence: Confirmed
- Where: [IoMapDefaults.jl:31](../../../source/kernel/iomap/IoMapDefaults.jl#L31) ⬜,
  [IoMapModule.jl:27-29](../../../source/kernel/iomap/IoMapModule.jl#L27) 🔒
- Evidence: `Expr(:(<:), name_expr, :IoMap)` resolves `IoMap` in the module of the
  caller. A module that writes `ProjecturedKernel.@iomap struct X … end` without
  `IoMap` in scope gets an `UndefVarError`, and a module with an `IoMap` of its own
  gets the wrong supertype. macros.md:71-72 states the requirement. `@gestures`
  puts the module object into its expansion instead
  ([Gestures.jl:188](../../../source/kernel/binding/Gestures.jl#L188)), which is the
  form that PAR-QUALIFIED-EXTENSION names for a macro. The module file has one
  `export` statement for three fragments. Planned: `plan/pending/export-block-rule.md`.
- Rule: PAR-QUALIFIED-EXTENSION (the form for a macro); code-quality-rules.md §1.
- Fix: put the type object into the expression, `Expr(:(<:), name_expr, IoMap)`, and
  update macros.md. Split the export statement when the owner permits the edit of
  the sealed file.
- Reach: `IoMapDefaults.jl`; `IoMapModule.jl` 🔒; macros.md.

### L16-7 One field type is not checked, and each computation of the list allocates more than it needs

- Category: Types/performance · Severity: Low · Confidence: Confirmed
- Where: [IoMapDefaults.jl:95](../../../source/kernel/iomap/IoMapDefaults.jl#L95) ⬜,
  [IoMapReconcile.jl:24-38](../../../source/kernel/iomap/IoMapReconcile.jl#L24) ⬜
- Evidence: `inner_iomap::IoMap` in `ContentIoMap` looks like a check. A reactive
  field of a cell struct "is a `Cell`, so its declared type is not checked"
  ([CellStruct.jl:215-216](../../../source/kernel/struct/CellStruct.jl#L215)), and the
  inline comment calls the type "documentary". The three other fields say `::Any`.
  `reconcile_child_iomaps` allocates a new `Set` and a copy of the keys
  (`collect(keys(cache))`) on each computation, and `objectid` of an immutable
  element, for example a `String`, hashes all of its content.
- Rule: PAR-HONEST-DOCS for the annotation; code-quality-rules.md for the cost.
- Fix: write `inner_iomap::Any` and keep its meaning in the docstring. Fill a new
  `Dict` in the loop and let it replace the old one.
- Reach: `IoMapDefaults.jl`, `IoMapReconcile.jl`.

### L16-8 The two reconcilers make a cell, but their names do not say so

- Category: Naming · Severity: Low · Confidence: Confirmed (the choice of the verb is
  the owner's)
- Where: [IoMapReconcile.jl:20](../../../source/kernel/iomap/IoMapReconcile.jl#L20) ⬜,
  [IoMapReconcile.jl:53](../../../source/kernel/iomap/IoMapReconcile.jl#L53) ⬜
- Evidence: each call makes a new `Cell`, and the cell does the reconcile at each
  computation. The call itself reconciles nothing. The verb table gives `make_` for
  a function whose purpose is a new object, for example
  `make_child_iomaps_cell`. This repository calls `reconcile_child_iomaps` 22 times
  and `reconcile_child_iomap` 32 times; omnet-julia calls the first 3 times.
- Rule: naming-rules.md, "The verb follows the nature of the work".
- Fix: if the owner agrees, rename with `workspace/bin/julia-rename.jl`, then
  omnet-julia.
- Reach: `IoMapReconcile.jl`, `IoMapModule.jl` 🔒 (export), about 20 files here,
  omnet-julia, and the guides that name the functions.

### L16-9 The text has idioms, a consumer name, stale lists and a claim that the key does not keep

- Category: Documentation · Severity: Low · Confidence: Confirmed
- Where: the layer files and three guides
- Evidence:
  - [IoMapInterface.jl:8-9](../../../source/kernel/iomap/IoMapInterface.jl#L8) 🔒: "the
    record that lets an edit find its way home" is an idiom; line 13-14, "Every
    printer answers one", gives an object an action of a person.
  - [IoMapDefaults.jl:42](../../../source/kernel/iomap/IoMapDefaults.jl#L42) ⬜ names
    `ChainingIoMap`, a type of a higher package (PAR-NO-CONSUMER-DOCS).
  - [IoMapDefaults.jl:6](../../../source/kernel/iomap/IoMapDefaults.jl#L6) ⬜: the
    signature `@iomap struct T ... end` has no optional cell kind, which
    `parse_cell_struct_macro_arguments` accepts.
  - [IoMapReconcile.jl:17](../../../source/kernel/iomap/IoMapReconcile.jl#L17) ⬜:
    "unminimal" is not an English word. Line 47-49: "(e.g. editing a string in
    place)" is not possible for a Julia `String`, which is immutable; the case is an
    edit inside a document. "crucially" adds emphasis only.
  - [IoMapReconcile.jl:1-5](../../../source/kernel/iomap/IoMapReconcile.jl#L1) ⬜: the
    fragment header has five lines; code-quality-rules.md §1 asks for one line.
  - IoMapDefaults.jl:95 has 104 characters; the budget is 90.
  - `documentation/package/kernel/architecture.md:51`, `:177` and
    `documentation/design/system-anatomy.md:387-388` list the layer without
    `IoMapReconcile.jl` and the two reconcilers.
  - PAR-STABLE-IOMAP-IDENTITY in architecture-invariants.md says that the shared
    reconciler is "keyed by child identity so a surviving child's IoMap is reused".
    The key is the identity and the index, so a child that stays after a front
    insert is made again. IoMapReconcile.jl:13-17 says so correctly.
- Rule: writing-rules.md (idioms, no personification); PAR-NO-CONSUMER-DOCS;
  PAR-UPDATE-THE-GUIDE; code-quality-rules.md §1 and §5.
- Fix: edit the text. The sealed file needs permission.
- Reach: `IoMapInterface.jl` 🔒, `IoMapDefaults.jl`, `IoMapReconcile.jl`,
  architecture.md, system-anatomy.md, architecture-invariants.md.

## Accepted before, not raised again

- The key `(objectid, index)`: a delete or a front insert makes the later
  children again. This is by design (`plan/done/reactive-iomap-stable-identity.md`),
  and the docstring gives the reason.
- The place of the layer, just below the projection layer
  (`plan/done/extract-iomap-layer.md`).
- The split pane and the grid do not reconcile their child count, on purpose
  (`plan/done/reactive-iomap-stable-identity.md`, 2026-07-19). That code is outside
  this layer.
- The docstring change of the sealed `IoMapInterface.jl` on 2026-09-18 (commit
  29ad8218) had the user's permission; the seal holds.
- A private reconcile cache in a cell closure is the sanctioned form
  (PAR-NO-PROJECTION-GLOBALS).
- The fields of the general IoMaps are `::Any`; cells hold `Any` on purpose.

## Checked and clean

- PAR-NO-PROJECTION-GLOBALS and PAR-PER-EDITOR-STATE: no module-level state; each
  cache belongs to one cell of one print.
- Leaks: the list cache holds only live keys after each computation; the single
  cache holds one value; the readers of an upstream cell are weak.
- PAR-SHARED-CHILDREN-IOMAP: `ChildrenIoMap` keeps its children in one
  `child_iomaps` cell.
- PAR-STABLE-IOMAP-IDENTITY: each reconciler returns one cell for the life of the
  IoMap, and reuses a child IoMap while its element stays at its index.
- PAR-MUTATE-OR-NULL-IOMAP: the layer does not touch `editor.iomap`.
- PAR-MAPPERS-ARE-INVERSES: the layer holds no mapper; the `ChildrenIoMap` docstring
  describes the delegation of the tail to the child mapper in both directions.
- PAR-INTERFACE-DECLARES-ONLY: `IoMapInterface.jl` declares only; the guard checks
  it.
- PAR-MODULE-BOUNDARY-IS-API: no code outside the module reaches a name that it does
  not export.
- Layering: the module imports layers 3 and 4 only; the kernel guard passes.
- PAR-ONE-BASED-INDEXING: `enumerate` gives the 1-based slot index that the callers
  put into `ElementReferenceStep(i)`.
- code-quality-rules.md §4: no function has more than three positional arguments.
- History comments: the grep of code-quality-rules.md §2 finds none in the layer.
