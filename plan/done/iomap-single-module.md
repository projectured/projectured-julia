# Collapse the iomap layer to one `IoMapModule` (Interface/Defaults fragments)

Adopt the Interface/Defaults-fragments-of-one-module pattern (as in
selection/operation/document) for the iomap layer. Today it has **two** modules —
`IoMapApiModule` (contract) and `IoMapModule` (concrete maps). Merge them into a
single **`IoMapModule`** with two fragments, and reduce the layer's comments to
justified ones.

## Target structure

```
iomap/
  IoMapLayer.jl       # banner + include("IoMapModule.jl")   (like SelectionLayer.jl)
  IoMapModule.jl      # aggregator: docstring + exports + includes both fragments
  IoMapInterface.jl   # fragment: the IoMap supertype + 3 accessor generics   (was IoMapApi.jl)
  IoMapDefaults.jl    # fragment: default accessors + SimpleIoMap/ChildrenIoMap/ContentIoMap + @iomap  (was IoMap.jl)
```

`IoMapApiModule` ceases to exist; every name it exported (`IoMap`,
`get_iomap_projection/input/output`) moves into `IoMapModule`. The `IoMapModule`
name is **preserved**, so the ~40 `import ..IoMapModule: SimpleIoMap` sites are
untouched.

## Consumer surface (survey)

- `import ..IoMapApiModule: IoMap` — ~38 files in base/visual/domain (+ kernel
  ProjectionTemplate/Editor use `using ..IoMapApiModule`). Retarget the module
  name → `IoMapModule`. (Files already importing `IoMapModule: SimpleIoMap` just
  gain a second import line from the same module — fine.)
- `const IoMapApiModule = ProjecturedKernel.IoMapApiModule` in
  base/visual/domain entry modules — **delete** (the `IoMapModule` alias stays).
- `package/kernel/test/ProjecturedKernelTest.jl` interface_files:
  `iomap/IoMapApi.jl => :IoMapApiModule` → `iomap/IoMapInterface.jl => :IoMapModule`.
- `.md` docs + CLAUDE.md inventory: file/module names.

## Steps

- [x] 1. Plan.
- [x] 2. Restructure the layer (fragments + `IoMapModule.jl` aggregator;
      `IoMapLayer.jl` includes it) + reduced comments. (commit `e33feaa0`)
- [x] 3. Retarget consumers: 3 aliases deleted; global `IoMapApiModule` →
      `IoMapModule`; test interface_files path + symbol. (commit `e33feaa0`)
- [x] 4. Docs + CLAUDE.md inventory. (commit `1421d113`)
- [x] 5. Verify: kernel 10/10, base 7/7, visual 7/7, domain 6/6 layering guards;
      full stack loads; json `test_printer` 3516/3516, `test_reader` 225/225.
- [x] 6. Done → plan/done/.

## Notes discovered
- **The `IoMapModule` name was preserved**, so the ~40 `import ..IoMapModule:
  SimpleIoMap` sites needed no change — only the ~40 `IoMapApiModule` references
  retargeted. Files that imported from both now carry two `import ..IoMapModule:`
  lines (left as-is; merging them is out of scope, PAR-FOCUSED-DIFFS).
- **Fragments inherit the aggregator's `using`.** `IoMapDefaults.jl` dropped its
  own `using ..CellModule` / `..CellStructModule` / `..IoMapApiModule` — the
  aggregator's `using ..CellModule` / `..CellStructModule` covers it, and the
  interface generics are same-namespace.
- **Cleaned up drift the extraction left in docs**: `kernel/doc/architecture.md`
  still listed `IoMapApi`/`IoMap` under the `projection/` folder row (no `iomap/`
  row); `macros.md` and `projection-system.md` still linked `projection/IoMap*`
  paths. All fixed here.
- **`plan/pending/kernel-cleanup.md` anticipated this fold** (it lists
  `IoMapApiModule` as a "pure internal cycle-breaker with one implementor" to
  collapse). Left untouched — it's the user's planning doc — but that item is now
  effectively done.
