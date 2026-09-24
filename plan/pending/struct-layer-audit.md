# The audit of the struct layer

The owner asked for a review of the whole shape of the struct layer
(`source/kernel/struct/`) and an audit against the rules in
`documentation/rule/`. The audit found three defects in behavior, contract
limits that the docstrings do not state, code that the document layer writes a
second time, two forms of one concept, names that break the naming law,
docstrings with history and false claims, and an export block that breaks the
export rule. On 2026-09-24 the owner gave permission to unseal the three files
and to fix every item.

## Decisions

- **The layer is unsealed.** `SEALING.md` marks its three files ⬜ until the
  owner seals them again.
- **`@cell_struct` supports type parameters.** The struct keeps the parameters
  as the programmer wrote them. `T{A}(values…)` always works. `T(values…)` works
  when each parameter is the declared value type of a field; the parameter then
  takes the value type of that argument. The rule is the one that `@document`
  uses, and one function of this layer states it for both.
- **A kind is a type.** `ReactiveCell`, `ImmutableCell` and `MutableCell` name
  a kind at expansion time and at run time. The symbols `:reactive`,
  `:immutable` and `:mutable` go.
- **The generated code splices `Cell` as an object.** A caller of `@cell_struct`
  needs nothing in scope. The struct layer depends on the cell layer, which is
  below it.
- **The plan gives the name of each parameter.** `CellStructPlan.parameters`
  holds the declarations as written (`A<:Real`), and
  `get_cell_struct_parameter_names` gives the names (`A`). A declaration goes
  into a `where` clause and a struct head; a name goes into a type application.
- **A parameter binds from a field whose value type is that parameter.**
  `find_cell_struct_parameter_slots` compares with the value types, so a field
  `a::ImmutableCell{A}` binds `A`. Before, the comparison used the declared
  types, and such a field did not bind.
- **The trim comment stays with its function.** `juliac --trim=safe` reported a
  verifier error for the splat in `build_cell_struct_keyword_constructor` in an
  omnet-julia binary. That build reported no other splat of the layer, so the
  other builders keep their splats, and the comment states the observed fact.

## Names

| Before | After |
| --- | --- |
| `parse_cell_struct_macro_default` | `parse_cell_struct_macro_arguments` |
| `get_cell_kind` (exported) | `_find_cell_kind` (private) |
| `cell_struct_autowrap_ctor` | `_build_cell_struct_autowrap_ctor` |
| `cell_struct_property_accessors` | `_build_cell_struct_property_accessors` |
| `_cell_kind_name` | `_find_cell_kind` |
| `_field_kind_type` | `_parse_field_type` |
| `_cell_kind` | `_get_cell_kind` |
| field `structdef` | `definition` |
| field `params` | `parameters` |
| field `n_declared` | `declared_field_count` |
| field `n_programmer_defaults` | `programmer_default_count` |
| `test_struct_plan` | `test_cell_struct_plan` |
| `_default_cell_type` in `DocumentMacro.jl` | `build_cell_struct_field_type` |
| `_document_param_type` in `DocumentMacro.jl` | `get_cell_value_type` |

New exported names: `get_cell_struct_parameter_names`,
`find_cell_struct_parameter_slots`, `build_cell_struct_field_type` and
`get_cell_value_type`.

## Steps

- [x] 1. Unseal the layer in `SEALING.md`, and add this plan.
- [x] 2. Both fragments, their callers and their tests, in one commit. The two
  fragments change their callers together, so a split would add code that the
  next step removes.
  - The plan fragment: the field names, the parameter names and slots, the
    rejection of an inner constructor, `ArgumentError` for a bad argument, the
    kinds as types, the private names, the docstrings and the comments.
  - The code generation fragment: `build_cell_struct_positional_ctors` moves here;
    `build_cell_struct_field_type`, `get_cell_value_type`, `Cell` as an object,
    type parameters, the private names, the argument parse, one-line property
    methods with no branch for each field, the docstrings and the comments.
  - `DocumentMacro.jl`: the new field names, the kinds as types, the shared
    functions in place of `_default_cell_type` and `_document_param_type`, and the
    parameter names in every type application.
  - Tests: 51 in `test_cell_struct`, 47 in `test_cell_struct_plan`, and a bounded
    parameter in `test_document_macro`.
- [x] 3. The module file: the docstring, and the export block in the order of the
  export rule. `CellStructModule` leaves `EXPORT_UNMIGRATED`.
- [ ] 4. Outside the layer: the docstrings of the two test files, the import of
  `get_cell_struct_kind` from its owner in `ProjecturedSubstrateTest`, and the
  guides `cell.md`, `macros.md`, `testing-guide.md` and
  `architecture-invariants.md`.
- [ ] 5. Verification, and the move of this plan to `plan/done/`.

## What the implementation found

- The docstrings of `CellStructPlan` and `make_cell_struct_plan` said that the
  parse removes each default from the body. The body keeps the default until
  `retype_cell_struct_fields!` writes the slot of the field. The docstrings say
  that now.
- The bounded parameter broke six places, not four: the positional
  constructors of this layer, and in `DocumentMacro.jl` the inner constructor,
  the right side of the spelling aliases, the kind constructors, the method of
  `_declared_value_types` and `_emit_collection_ctor_at`. The struct head, the
  native struct head and the left side of an alias take the declarations, and
  they were right.
- `_emit_collection_ctor_at` in `DocumentMacro.jl` had its own copy of the rule
  for the parameters. It asks `find_cell_struct_parameter_slots` now.
- A field docstring is a plain `String` in the body of a quoted struct, so the
  parse skips it.
- A reactive field stores only a `Cell` as its cell. It wraps a cell of another
  type, such as a `ReactiveCell{Int}` or an `ImmutableCell`, in a new `Cell`, and
  that makes a nested cell. The docstring states this. A change needs a decision
  of the owner, so it is not part of this plan.
- `test_document_macro` gives 3 fails and 2 errors in Rule C on `main` and in the
  worktree. The collection trait lives in a package above the kernel test
  package, so Rule C does not run there.

## Verification

To fill in.
