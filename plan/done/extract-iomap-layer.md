# Extract the iomap layer from the projection layer

Pull `IoMapApi.jl` (`IoMapApiModule`) and `IoMap.jl` (`IoMapModule`) out of the
projection layer into a new **`iomap/`** layer of their own.

## Why

The IO-map data structures are the record a projection's forward pass leaves
behind — foundational infrastructure that the projection interface/algebra
*build on*, not part of the projection contract itself. Their dependencies are
minimal: `IoMapApi` imports nothing; `IoMap` imports only the **cell layer**
(`CellModule`, `CellStructModule`) plus its own interface. Giving them a
distinct layer makes the dependency height honest and separates "the IoMap
types" from "the four projection generics".

## Placement — new layer 12, just below projection

Legal range is layers 2–11 (above cell, below projection). Chosen: **just below
projection**, keeping iomap adjacent to its main consumer with minimal
renumbering. `binding` stays 11; `projection`…`editor` shift +1.

```
10 operation
11 binding
12 iomap          ← NEW
13 projection
14 tool
15 llm
16 agent
17 editor
```

Consumers of iomap: the projection layer (`ProjectionTemplate` — `RuleIoMap <:
IoMap`, `using ..IoMapApiModule`) and the editor (`Editor.jl`). Both are now
valid downward edges. Nothing in layers 2–11 uses IoMap. Relative imports
(`..CellModule`, …) resolve by module nesting, not folder, so moving the files
changes none of them.

## Steps

- [x] **1. Plan** committed to `plan/pending/`.
- [x] **2. Structural move** (commit `09f47b9a`):
  - [x] `git mv` both files into `package/kernel/main/iomap/`.
  - [x] Create `iomap/IoMapLayer.jl` (layer fragment; includes IoMapApi then IoMap).
  - [x] Edit **sealed** `ProjecturedKernel.jl` (permission granted this task):
        add `include("iomap/IoMapLayer.jl")` at layer 12, renumber 13–17, bump
        "sixteen" → "seventeen".
  - [x] Edit `projection/ProjectionLayer.jl`: drop the two includes, fix the
        header comments (IO maps now live one layer below).
  - [x] Edit `package/kernel/test/ProjecturedKernelTest.jl`: add `"iomap"` to
        `layers`; retarget `interface_files`; fix the "two contracts" comment.
  - [x] Verify: `test_kernel_layering()` 10/10; full stack precompiles;
        `test_printer(json_example)` 3516/3516, `test_reader` 225/225 (baseline).
- [x] **3. Docs + inventory** (commit `814d8c18`):
  - [x] `CLAUDE.md` seal inventory: new Layer 12 (iomap) with the two ⬜ files,
        renumber 13–17, remove the two entries from projection.
  - [x] `terminology.md` + both `architecture.md` guides + `concepts.md` +
        `agent.md` + `editor.md`: layer count + every layer arrow-chain/number.
- [x] **4. Done**: move plan to `plan/done/`.

## Notes / facts discovered during implementation

- **Relative imports are folder-agnostic.** `..CellModule` etc. resolve by module
  nesting under `ProjecturedKernel`, not by file location, so moving the two files
  changed none of their import headers. Content moved verbatim.
- **Only `ProjectionTemplate` in the projection layer imports IoMap** (`using
  ..IoMapApiModule`, `RuleIoMap <: IoMap`); `Intent`/`PrinterContext`/etc. do not.
  So removing the two includes from `ProjectionLayer.jl` was safe. `Editor.jl`
  (layer 17) also imports `IoMapApiModule` — a valid downward edge.
- **`git mv` + `git commit <new-paths-only>` broke the first commit**: the
  old-path deletions weren't in the pathspec, so the tree kept both copies.
  Amended to fold the staged deletions in (proper renames). Lesson: when
  committing a rename with explicit pathspecs, include the *old* paths too.
- **Corrected a pre-existing doc drift.** `documentation/architecture.md`'s kernel
  include-order list had 15 entries and had dropped the **clock** layer (Clock was
  folded into the document row). Restored it as layer 2 so the list is honest at
  17 — a fix incidental to, but forced by, the layer-count bump.
