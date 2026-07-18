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

- [ ] **1. Plan** committed to `plan/pending/`.
- [ ] **2. Structural move** (one guard-green commit):
  - [ ] `git mv package/kernel/main/projection/IoMapApi.jl package/kernel/main/iomap/IoMapApi.jl`
  - [ ] `git mv package/kernel/main/projection/IoMap.jl package/kernel/main/iomap/IoMap.jl`
  - [ ] Create `iomap/IoMapLayer.jl` (layer fragment; includes IoMapApi then IoMap).
  - [ ] Edit **sealed** `ProjecturedKernel.jl` (permission granted this task):
        add `include("iomap/IoMapLayer.jl")` at layer 12, renumber 13–17, bump
        "sixteen" → "seventeen".
  - [ ] Edit `projection/ProjectionLayer.jl`: drop the two includes, fix the
        header comments (IO maps now live one layer below).
  - [ ] Edit `package/kernel/test/ProjecturedKernelTest.jl`: add `"iomap"` to
        `layers`; retarget `interface_files` (`projection/IoMapApi.jl` →
        `iomap/IoMapApi.jl`); fix the "two contracts" comment.
  - [ ] Verify: `test_kernel_layering()` green (guard runs w/o loading), then an
        actual `using ProjecturedKernel` load + `test_printer(json_example)`.
- [ ] **3. Docs + inventory** commit:
  - [ ] `CLAUDE.md` seal inventory: new Layer 12 (iomap) with the two ⬜ files,
        renumber 13–17, remove the two entries from projection.
  - [ ] `package/kernel/doc/architecture.md`, `documentation/terminology.md`,
        `documentation/architecture.md`: layer count + the layer arrow-chain.
- [ ] **4. Done**: move plan to `plan/done/`.

## Notes / facts discovered during implementation

- (to fill in as I go)
