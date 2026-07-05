"""
    ProjecturedBase

The domain-independent vocabulary and frameworks — layered between the
kernel engine and the concrete domain slices.

## Scope

The plan for this package (see `plan/pending/kernel-layered-architecture.md`
and `plan/pending/domain-layered-architecture.md`) is:

- **`document/`** — the engine's concrete document types: `Collection`
  (CellVector / CellMatrix / CellTable / ListNode), `Primitive`
  (Bool/Number/String/Insertion), and `ScreenDocument` (window model).
- **`projection/`** — the document-shaped generic projections (Sorting,
  Filtering, Searching, Copying, WindowManaging) plus the R6 reader
  defaults for the Primitive splice-range operations.
- **`serialization/`** (added at Q2/D4) — the domain-independent persistence
  frameworks: BinarySerialization, NaturalFormat, DocumentFile.
- **`document/Insertion.jl`** (added at Q2/D1) — the shared insertion
  document moved down from domain's `core/`.

## P7 scope: package skeleton only

Kernel plan P7 stands up the package (Project.toml, this file, the guard
skeleton, tests folder, docs folder) but leaves the actual content in the
kernel. The reason is a coupling constraint: moving one of
`{Collection, Primitive, ScreenDocument}` alone leaves a wrong-direction
kernel→base edge — the four kernel-side generic projections (Searching,
Filtering, Copying, Sorting), `WindowManagingProjection`, and the
`common/Projection.jl` default reader all reference the concrete types.
The whole family moves together at P8 (the projection split), which is
where the coupling is resolved by splitting `common/Projection.jl` and
migrating the document-shaped projections wholesale.

## Package chain (target)

```
kernel ← base ← domain ← umbrella
                       ← opt-in (sdl/web/odbc/…)
```

Kernel submodule aliases below let files under this package's source
folders keep their relative `..XxxModule` references unchanged — a file
inside a submodule of `ProjecturedBase` resolves `..CellModule` through
the `const CellModule = ProjecturedKernel.CellModule` binding.
"""
module ProjecturedBase

using ProjecturedKernel

# Kernel submodule aliases — populate as content migrates from the kernel
# at P8. Ordered like ProjecturedKernel's include list for consistency.
const CellModule = ProjecturedKernel.CellModule
const DocumentModule = ProjecturedKernel.DocumentModule
const ReferenceModule = ProjecturedKernel.ReferenceModule
const OperationModule = ProjecturedKernel.OperationModule
const GestureModule = ProjecturedKernel.GestureModule
const BackendModule = ProjecturedKernel.BackendModule

# Base's own layers land here at P8 (document + projection) and Q2
# (serialization). Left empty at P7 by design — see the docstring.

end # module ProjecturedBase
