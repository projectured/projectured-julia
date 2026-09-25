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
- **`get_cell_value_type` is `get_cell_struct_argument_type`.** Every other
  exported name of the struct layer contains `cell_struct`, and the function has
  one job in this layer: the type that a constructor argument gives to a type
  parameter. The owner chose this name over a move to the cell layer.

## Steps

- [x] 1. Find the code that gives a cell of another type to a reactive field. A
  temporary probe kept the old behavior, recorded each struct, field and cell
  type, and `test_all()` of projectured-julia and `test_omnet()` of omnet-julia
  ran with it. Both found one site: `ObjectNodeToSyntaxNode.print_document` gives
  the object that it prints to `SimpleIoMap` as the input, and that object is an
  `ImmutableCell` when the projection prints a field of an immutable document.
- [x] 2. The inner constructor passes every cell to `new`, with a test. The one
  site gives its input through `_get_object_input`, which puts a cell of another
  kind into a `Cell` of its own, so the projection shows what it showed before.
  A comment marks this place as an exception to PAR-NO-NESTED-CELL.
- [x] 3. The layer lists and the numbers in the guides.
- [x] 3a. The rename of `get_cell_value_type`, in the code, the test and the guides.
- [ ] 4. Verification, and the move of this plan to `plan/done/`.

## Verification

- `test_cell_struct()` 53 pass, `test_cell_struct_plan()` 47 pass,
  `test_document_macro()` 84 pass with the 5 known failures of Rule C.
- Both environments precompile with the change.
- Open: `test_all()` and `test_omnet()` with the change, compared with the run
  with the probe, which had the old behavior: projectured-julia 1049850 pass,
  649 fail, 11 error, 1114 broken; omnet-julia 10942 pass, 26 fail, 67 error,
  1 broken. The owner asked to wait with the full run.
