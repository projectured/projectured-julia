# Interface files declare; they never implement (AR-72)

## Why

[AR-72](../../documentation/architecture-requirements.md) says an interface file carries the module
docstring, the abstract types and type aliases, and the open generics as bodiless `function f end` —
and no method bodies at all, defaults and error fallbacks included. Everything it declares is
exported, so its export list *is* the layer's API surface.

The rule was written because AR-70's seam carve-out already leaned on it ("an open interface
declaration is content-free by construction") without it ever having been stated — and, unstated,
every interface file in the kernel drifted. The purpose is documentary: one file gives a reader the
entire contract of a layer and nothing else.

This plan purifies the six non-compliant files and makes the rule enforceable by the static
layering guard, so it cannot drift again.

## Design decisions

**A default is behaviour, so it moves next to the concrete methods it backs.** Not into a
"defaults" dumping ground: `step_kind`'s abstract default belongs with the per-step `step_kind`
methods in `ReferenceStep.jl`, the DSL seam fallbacks belong with the grammar that consumes them in
`ReferenceSyntax.jl`, and the cross-kind cell fallbacks dissolve into per-kind methods on
`MutableCell` / `ImmutableCell`. A new file is the *last* resort — AR-72's "the layer wants an
implementation fragment" clause, used exactly once (backend, below).

**The backend fallback is kept, not pushed onto the concrete backends.** `get_pointer_position`'s
`(-1, -1)` is load-bearing: of the four `Backend` subtypes (`SdlBackend`, `ConsoleBackend`,
`HeadlessBackend`, `WebBackend`) only `SdlBackend` implements it. The alternative — delete the
fallback and make all four implement it — was rejected: it spreads a kernel cleanup across three
packages and turns a legal answer ("this backend cannot report a pointer") into a `MethodError` for
any out-of-tree backend. The backend layer has no in-layer implementation file for the *abstract*
contract, so this is the one place AR-72's implementation-fragment clause applies:
`backend/BackendDefaults.jl`, a fragment of `BackendModule`.

**`print_child` is a derived helper, not a default, and lives with the recursion machinery.**
`print_child(recursion, input, ctx) = print_document(recursion, recursion, input, ctx)` is the
convenience wrapper every node printer recurses through; its home is `Projection.jl`
(`ProjectionModule`), next to the `RecursiveProjection` / `TypeDispatchingProjection` pipeline whose
doubled-`recursion` calling convention it encodes. Same for `pure_print_child`. `ProjectionModule`
already imports `print_document` from `ProjectionApiModule`; it gains two more names on that import.

**The `IoMap` accessors are the implementation of the field contract**, so they sink to `IoMap.jl`
(`IoMapModule`), which owns the concrete iomap types those `getfield`s assume. They stay methods on
the abstract `IoMap`, so `@iomap`-generated types in higher packages keep working unchanged.

**The guard learns the rule.** `check_layering` gains an `interface_files` argument (a map from
source path to owning module) and two checks that parse the file — no method bodies, and every
declared name exported. Purity is checkable *statically*: a bodiless `function f end` parses to a
one-argument `Expr(:function)`, a method has two. This is what makes AR-72 enforced rather than
aspirational, and it is why the AR could be written with a "known remaining instances" list at all.

## Steps

- [x] **1. Teach the guard the rule.** In `package/kernel/test/layering/CheckLayering.jl`: add
  `interface_purity_errors(src_root, interface_files, entries)` and self-tests in
  `test_layering_checkers()`. Not yet wired into `test_kernel_layering()` — the guard would be red
  until the cleanup lands. Run the checker by hand through the following steps.

  *Found while writing it:* `function Base.peek end` is a **syntax error** — a bodiless declaration
  cannot be qualified. So an interface file can never *declare* a generic it does not own (a `Base`
  one); it can only state the protocol in its docstring and let the implementors add methods. This
  settles step 2's `Base.peek` question.

- [x] **2. cell — `cell/AbstractCell.jl`** (sealed; the user gave explicit permission).
  `is_up_to_date(c::AbstractCell) = true` and `Base.peek(c::AbstractCell) = c[]` become per-kind
  methods in `MutableCell.jl` and `ImmutableCell.jl` (`ReactiveCell.jl` already overrides both).
  The abstract-type fallbacks disappear entirely — no subtype outside the three kinds exists — and
  `AbstractCell.jl` keeps the abstract type plus a bodiless `function is_up_to_date end` declaring
  the generic. `Base.peek` is Base's generic and cannot be re-declared; the file's docstring states
  it as part of the shared read protocol.

- [x] **3. reference — `reference/Interface.jl`.** Two changes to the plan, both found by looking:

  - `step_kind(::ReferenceStep) = :structural` was **deleted, not rehomed**. All six step types in
    the repo (`RangeReference`, `FieldReference`, `TypeReference`, `ProjectionReference`,
    `PointReference`, `TextRectangularReference`) already declare their own `step_kind`, so the
    abstract default was dead code — and `ReferenceStep.jl`'s header already states the design it
    contradicted ("each step type is self-contained: its struct, `show`, `==`, and its `step_kind` /
    `evaluate_step` seam methods sit together"). A new step type that forgets to classify itself now
    fails loudly at the first path walk instead of being silently taken as structural.
  - The seam fallbacks go to the **DSL that raises each**, not to the shared grammar:
    `dsl_step_subpath_args(::Val) = ()` → `ReferenceSyntax.jl` (its only caller),
    `dsl_build_step`'s error → `ReferenceBuilder.jl`, `dsl_match_step`'s error →
    `ReferenceCase.jl`. Each unregistered-name error is reported where the unknown `.name(…)` is
    first reachable.

- [ ] **4. operation — `operation/Interface.jl`.** `invalidate_projection!(editor) = nothing` →
  `Operations.jl`. Also fix the `evaluate_operation` docstring, which points at a `common/Operation.jl`
  that does not exist and claims the concrete methods "live in `OperationModule`" from inside a
  fragment of `OperationModule` itself.

- [ ] **5. backend — `backend/Backend.jl`.** `get_pointer_position(::Backend) = (-1, -1)` → new
  fragment `backend/BackendDefaults.jl`, included from `BackendModule`. Add the file to the seal
  inventory in `CLAUDE.md` (as `⬜`, in load order). Also fix two AR-70 violations in the module
  docstring: it names `SdlBackend()`, `ConsoleBackend()` and `ProjecturedBase.default_backend` —
  specific higher-package names the seam carve-out does *not* license (it permits the *concepts* a
  seam bridges, not its consumers) — and a closing comment that points at `device/Display.jl` when
  the file is `backend/Display.jl`.

- [ ] **6. projection — `projection/ProjectionApi.jl` and `projection/IoMapApi.jl`.**
  `print_child` / `pure_print_child` → `Projection.jl`; the three `get_iomap_*` accessors →
  `IoMap.jl`. Both modules already depend on the api modules; extend their import headers.

- [ ] **7. Wire the guard.** `test_kernel_layering()` passes `interface_files` naming all eight
  kernel interface files — the six purified above plus `document/Interface.jl`,
  `selection/Interface.jl` and `device/Device.jl`, which are already clean and now stay that way.

- [ ] **8. Close AR-72.** Replace its "known remaining instances" list with the enforcement
  statement, and update `package/kernel/doc/devices-and-backends.md` if it documents the moved
  backend fallback.

## Verification

`test_kernel_layering()` (guard, ~1s, no load) and `test_kernel()`. The moved methods are all on hot
paths that every projection uses, so also drive one end-to-end example (`test_example(json_example)`)
— method motion cannot change dispatch, but a wrong import header or include order fails at load,
and a load failure is exactly what a structural guard cannot see (memory: "guards are not a load
check").

## Out of scope

- The interface-file **naming** inconsistency (`Interface.jl` vs `ProjectionApi.jl` / `IoMapApi.jl`
  / `Backend.jl` / `Device.jl`) — explicitly deferred.
- Interface files above the kernel (agent/editor layers, `base`/`visual`/`domain` seams). The guard
  takes a per-package list, so those come clean one package at a time.
