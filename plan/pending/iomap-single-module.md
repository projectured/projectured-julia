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

- [ ] 1. Plan.
- [ ] 2. Restructure the layer (rename files → fragments, new `IoMapModule.jl`
      aggregator, `IoMapLayer.jl` includes it) + **reduce comments**.
- [ ] 3. Retarget consumers: delete the 3 `IoMapApiModule` aliases; global
      `IoMapApiModule` → `IoMapModule` in imports; fix the test interface_files
      path + symbol. (Kernel change + consumer retarget land together so the full
      stack loads.)
- [ ] 4. Docs + CLAUDE.md inventory.
- [ ] 5. Verify: kernel + base + visual + domain layering guards; full-stack load;
      `test_printer/test_reader(json_example)` at baseline.
- [ ] 6. Done → plan/done/.

## Notes discovered
- (fill in)
