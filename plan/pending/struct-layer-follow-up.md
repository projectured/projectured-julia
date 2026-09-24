# The follow-up of the struct layer audit

The audit of the struct layer ([struct-layer-audit.md](../done/struct-layer-audit.md))
left two items for the owner. On 2026-09-24 the owner approved both.

## Decisions

- **A reactive field does not wrap a cell of another type.** The inner
  constructor of `@cell_struct`, `@projection` and `@iomap` stores a `Cell`
  argument as the cell of a reactive field. Before, it wrapped any other cell,
  such as a `ReactiveCell{Int}` or an `ImmutableCell`, in a new `Cell`, and the
  field then held a nested cell. Now every cell argument goes to `new`, which
  throws a `MethodError` when the cell does not have the type of the field. All
  kinds follow the same rule, and a field never holds a cell as its value.
- **The guides number the 23 kernel layers as `ProjecturedKernel.jl` does.** The
  lists in `kernel/architecture.md` and `system-anatomy.md` had 18 layers, from
  before the split into one module for each layer. Seven guides used those
  numbers.

## Steps

- [ ] 1. Find the code that gives a cell of another type to a reactive field. A
  temporary probe keeps the old behavior, records each struct, field and cell
  type, and `test_all()` of projectured-julia and `test_omnet()` of omnet-julia
  run with it.
- [ ] 2. The inner constructor passes every cell to `new`, with a test, and the
  code that the probe found changes.
- [x] 3. The layer lists and the numbers in the guides.
- [ ] 4. Verification, and the move of this plan to `plan/done/`.

## Verification

To fill in.
