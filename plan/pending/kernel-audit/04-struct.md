# Layer 04 — struct (`source/kernel/struct/`)

Commit 15b40434, 2026-09-27. Seal state: all sealed.

## Verdict

The struct layer is in good order after its audit and its follow-up of 2026-09-24 and 2026-09-25. It holds the code generation for a struct of cells, and five kernel modules build on it. This audit found no high and no medium defect. The ten low findings are edges of the generated code: the parse skips an unknown field form with no error, the generated setter can nest a cell, a `Computation` binds a type parameter, the kind of a mixed struct reduces to its first field, and the generated methods point to the kernel file. `@cell_struct` also does not apply Rule Y, which the macros guide calls a rule of any struct of cells.

## Shape

- Purpose: parse a `struct` definition into a `CellStructPlan`, and build the parts of a struct of cells: the inner constructor that wraps a value in a cell, the property methods, the keyword constructor, the inferring constructor and the positional constructors of Rule Y. `@cell_struct` puts them together. Two functions read a struct of cells at run time.
- Files:

  | file | lines | seal | what it holds |
  | --- | ---: | --- | --- |
  | `CellStructModule.jl` | 40 | 🔒 | module docstring, `using ..CellModule`, the export block, the includes |
  | `CellStructPlan.jl` | 237 | 🔒 | `CellStructPlan`, the parse, and the questions about fields and type parameters |
  | `CellStruct.jl` | 289 | 🔒 | the builders, `@cell_struct`, `get_cell_struct_argument_type`, `get_cell_struct_kind` |

- Imports: `CellModule` only. Imported by: 5 kernel module files (clock, document, reference, iomap, projection). Outside the kernel, 6 files use `@cell_struct` (the reference steps of graphics, chart, sequencechart and text), and `ListNode.jl` uses `get_cell_struct_kind`. omnet-julia uses `get_cell_struct_kind` in one test.
- Public surface: 19 exported names. The kernel uses 18 of them: `DocumentMacro.jl`, `IoMapDefaults.jl` and `ProjectionMacro.jl` use 17, and `DocumentSync.jl` uses `get_cell_struct_kind`. Outside the kernel only `@cell_struct` and `get_cell_struct_kind` have callers; `get_cell_struct_required_count` appears there only in the prose of `SyntaxDocument.jl`. `get_cell_struct_trailing_default_count` has no user outside the layer and its test (L04-7).
- State: none. The builders change the `definition` expression in place, and the docstrings say so.
- Tests: [CellStructTest.jl](../../../test/kernel/struct/CellStructTest.jl) (53 assertions) and [CellStructPlanTest.jl](../../../test/kernel/struct/CellStructPlanTest.jl) (47), all pass in the baseline run. They cover the four field forms, a field docstring, the rejection of an inner constructor, the retype in place, an added field, the kinds, the parameters and their slots, the split of required and trailing fields, the Rule Y builder, the wrapping constructor, a shared cell, a cell of another type, the property methods, the keyword constructor, a supertype, a leading kind, type parameters, the hygiene of the expansion and the argument parse. L04-10 lists what they do not cover.

## Summary

| Category | High | Medium | Low |
| --- | ---: | ---: | ---: |
| Correctness | 0 | 0 | 3 |
| Shape | 0 | 0 | 4 |
| Naming | 0 | 0 | 1 |
| Documentation | 0 | 0 | 1 |
| Tests | 0 | 0 | 1 |

## Findings

### L04-1 The parse skips an unknown expression of the struct body with no error

- Category: Correctness · Severity: Low · Confidence: Confirmed for the skip; Suspected for the effect (needs a run)
- Where: [CellStructPlan.jl:63](../../../source/kernel/struct/CellStructPlan.jl#L63) 🔒, the `continue` at [CellStructPlan.jl:81](../../../source/kernel/struct/CellStructPlan.jl#L81)
- Evidence: The loop knows a `Symbol`, `f::T`, `f = v`, `f::T = v` and a `function`. Every other expression takes `continue # a line number, a docstring`. A `const f::Int` field or an `@atomic f::Int` field of a `mutable struct` is thus not in `field_names`. The struct keeps it as a plain field, and the inner constructor calls `new` with one argument less than the struct has fields. The error then appears far from its cause, or a field stays undefined.
- Rule: bug.
- Fix: Skip only a `LineNumberNode` and a `String`. Throw an `ArgumentError` that names any other expression, as `_reject_inner_constructor` does.
- Reach: `CellStructPlan.jl` 🔒, `CellStructPlanTest.jl`. `DocumentMacro.jl` uses the same parse, so a run of `test_document_macro()` must follow.

### L04-2 The generated setter stores a cell as the value of a field

- Category: Correctness · Severity: Low · Confidence: Confirmed
- Where: [CellStruct.jl:52](../../../source/kernel/struct/CellStruct.jl#L52) 🔒
- Evidence: `Base.setproperty!(object, name, value) = (getfield(object, name)[] = value)`. For a reactive field, `object.f = Cell(1)` stores the cell as the value, so the field holds a nested cell. The constructor of the same struct refuses this: a cell of the type of the field becomes the cell of the field, and a cell of another type throws a `MethodError` ([CellStruct.jl:17](../../../source/kernel/struct/CellStruct.jl#L17), tested). For a `Computation`, the setter and the constructor agree: the field computes.
- Rule: PAR-NO-NESTED-CELL.
- Fix: In the generated setter, throw an `ArgumentError` when `value isa AbstractCell`, and point to `getfield` for the case that shares a cell. The check costs one type test for each write, so the owner decides.
- Reach: `CellStruct.jl` 🔒, and every struct of cells, because the setter is generated. A run of the suites must show that no writer depends on the nested cell.

### L04-3 A `Computation` argument binds a type parameter to `Computation`

- Category: Correctness · Severity: Low · Confidence: Confirmed; no caller does it at this commit
- Where: [CellStruct.jl:257](../../../source/kernel/struct/CellStruct.jl#L257) 🔒, [CellStruct.jl:40](../../../source/kernel/struct/CellStruct.jl#L40) 🔒
- Evidence: `get_cell_struct_argument_type(argument) = typeof(argument)`. For `@cell_struct struct Box{A}; content::A; end`, the call `Box(@computation 1)` makes a `Box{Computation}`. With `A<:Real`, the call throws `TypeError`. The value type of a computation is not known before it runs. The only parametric struct of cells in the three repositories, `SequentialEvent{A}` of omnet-julia, uses `ImmutableCell`, which rejects a `Computation`.
- Rule: bug.
- Fix: Add `get_cell_struct_argument_type(::Computation) = Any`, or throw an `ArgumentError` that asks for `T{A}(…)`.
- Reach: `CellStruct.jl` 🔒, `CellStructTest.jl`. `DocumentMacro.jl` calls the same function.

### L04-4 `get_cell_struct_kind` gives one kind for a struct whose fields have different kinds

- Category: Shape · Severity: Low · Confidence: Suspected (the effect on a `DCFoo` layout needs a run)
- Where: [CellStruct.jl:285](../../../source/kernel/struct/CellStruct.jl#L285) 🔒
- Evidence: The function reads field 1 only, and its docstring says so. `sync_document!` ([DocumentSync.jl:53](../../../source/kernel/document/DocumentSync.jl#L53)) and `_sync_list_tail!` ([ListNode.jl:148](../../../source/platform/collection/ListNode.jl#L148)) use the result as the kind of the whole shadow, and they rebuild each child in it. A `DCFoo` layout keeps each field in its declared kind, so its fields can differ.
- Rule: no written rule; a design fault between this layer and its callers.
- Fix: Give the kind of one field, for example `get_cell_struct_field_kind(x, name)`, and let the sync ask for each field. Or let the document audit decide that a mixed struct never reaches the sync, and say it in the docstring.
- Reach: `CellStruct.jl` 🔒, `CellStructModule.jl` 🔒, `DocumentSync.jl`, `ListNode.jl`.

### L04-5 `@cell_struct` does not apply Rule Y, which the macros guide calls a rule of any struct of cells

- Category: Shape · Severity: Low · Confidence: Confirmed
- Where: [CellStruct.jl:152](../../../source/kernel/struct/CellStruct.jl#L152) 🔒; [macros.md:48](../../../documentation/package/kernel/macros.md#L48)
- Evidence: `build_cell_struct_exprs` never calls `build_cell_struct_positional_ctors`. So `@cell_struct struct T; a; b = 1; end` has no `T(a)`, and `@iomap` and `@projection`, which build on `build_cell_struct_exprs`, also have none. `@document` has the positional constructors. macros.md:48 says: "Rule Y fills a trailing run of defaults positionally; it is a rule about any cell struct, not about documents."
- Rule: PAR-HONEST-DOCS.
- Fix: Call the builder in `build_cell_struct_exprs`, after a check for a method collision in the structs of `@iomap` and `@projection`. Or say in the guide that only `@document` applies Rule Y.
- Reach: `CellStruct.jl` 🔒, or `macros.md`.

### L04-6 The generated methods give `CellStruct.jl` as their source location

- Category: Shape · Severity: Low · Confidence: Confirmed (the baseline log shows it)
- Where: [CellStruct.jl:46](../../../source/kernel/struct/CellStruct.jl#L46), [CellStruct.jl:53](../../../source/kernel/struct/CellStruct.jl#L53), [CellStruct.jl:81](../../../source/kernel/struct/CellStruct.jl#L81) 🔒
- Evidence: The quoted parts carry the `LineNumberNode`s of the kernel file. The log of the baseline run of `test_kernel()` lists `DmSoleVector(; items, selection) @ ProjecturedKernelTest …/source/kernel/struct/CellStruct.jl:81`. So `methods(T)`, a stack trace and the hint of a `MethodError` point to the kernel and not to the declaration of the struct.
- Rule: no written rule; a diagnostic that points to the kernel sends a reader to the wrong file.
- Fix: Let `@cell_struct` pass `__source__` to `build_cell_struct_exprs`, and let the builders put it in place of the line nodes of the quoted parts.
- Reach: `CellStruct.jl` 🔒; `DocumentMacro.jl`, `IoMapDefaults.jl` and `ProjectionMacro.jl` then pass their own `__source__`.

### L04-7 `get_cell_struct_trailing_default_count` is exported, but only the layer uses it

- Category: Shape · Severity: Low · Confidence: Confirmed (search of source/, package/, test/, example/, tool/, omnet-julia and inet-julia)
- Where: [CellStructPlan.jl:221](../../../source/kernel/struct/CellStructPlan.jl#L221) 🔒
- Evidence: Its callers are `get_cell_struct_required_count` ([CellStructPlan.jl:237](../../../source/kernel/struct/CellStructPlan.jl#L237)) and `CellStructPlanTest.jl`. No other file names it.
- Rule: PAR-MODULE-BOUNDARY-IS-API (an exported name is a public contract); no caller needs this one.
- Fix: Make it private, and test it through `get_cell_struct_required_count`. Or keep it and state why a macro writer needs it.
- Reach: `CellStructPlan.jl` 🔒, `CellStructModule.jl` 🔒, `CellStructPlanTest.jl`, `cell.md` (its list of the public surface).

### L04-8 One family of builders spells "constructor" in two ways, and one builder takes two vectors by position

- Category: Naming · Severity: Low · Confidence: Confirmed
- Where: [CellStructModule.jl:33](../../../source/kernel/struct/CellStructModule.jl#L33) 🔒, [CellStruct.jl:75](../../../source/kernel/struct/CellStruct.jl#L75) 🔒
- Evidence: `build_cell_struct_keyword_constructor` and `build_cell_struct_positional_ctors` stand side by side in one export statement. writing-rules.md: "Use one word for one thing." `build_cell_struct_keyword_constructor(type_name, field_names, parameters)` takes two vectors that a caller can swap, and code-quality-rules.md §4 asks for a name on one of them.
- Rule: writing-rules.md; code-quality-rules.md §4.
- Fix: Rename to `build_cell_struct_positional_constructors` with `workspace/bin/julia-rename.jl`, and make `parameters` a keyword.
- Reach: `CellStruct.jl` 🔒, `CellStructModule.jl` 🔒, `DocumentMacro.jl`, `CellStructPlanTest.jl`, `cell.md`, `macros.md`.

### L04-9 Fifteen of the nineteen exported names have no "Use it to" paragraph and no example

- Category: Documentation · Severity: Low · Confidence: Confirmed
- Where: [CellStructPlan.jl](../../../source/kernel/struct/CellStructPlan.jl) 🔒, [CellStruct.jl](../../../source/kernel/struct/CellStruct.jl) 🔒
- Evidence: Only `build_cell_struct_exprs`, `@cell_struct`, `get_cell_struct_argument_type` and `get_cell_struct_kind` have both parts. `CellStructPlan`, `make_cell_struct_plan`, `add_cell_struct_field!`, `retype_cell_struct_fields!`, `get_cell_struct_value_types`, `get_cell_struct_field_kinds`, `get_cell_struct_parameter_names`, `find_cell_struct_parameter_slots`, `get_cell_struct_trailing_default_count`, `get_cell_struct_required_count`, `build_cell_struct_field_type`, `build_cell_struct_keyword_parameters`, `build_cell_struct_keyword_constructor`, `build_cell_struct_positional_ctors` and `parse_cell_struct_macro_arguments` have neither. `search_api` ranks every exported name.
- Rule: code-quality-rules.md §1, "A name a window declares to a model documents its use".
- Fix: Add the two parts, with the goal of a macro writer in each.
- Reach: the two fragments 🔒.

### L04-10 The tests do not cover the edges of the generated code

- Category: Tests · Severity: Low · Confidence: Confirmed
- Where: [CellStructTest.jl](../../../test/kernel/struct/CellStructTest.jl), [CellStructPlanTest.jl](../../../test/kernel/struct/CellStructPlanTest.jl)
- Evidence: No test covers an unknown expression in the body (L04-1), a write of a cell through the setter (L04-2), a `Computation` in the slot of a type parameter (L04-3), a struct whose fields have different kinds given to `get_cell_struct_kind` with a caller that copies (L04-4), a `mutable struct`, or `add_cell_struct_field!` followed by `build_cell_struct_exprs`.
- Rule: PAR-NEW-CODE-SHIPS-TESTS.
- Fix: Add a test set for each case; the sets for L04-1 to L04-3 must fail on the code at this commit.
- Reach: the two test files.

## Accepted before, not raised again

- A reactive field is a `Cell`, so its declared value type is not checked (plan/done/struct-layer-audit.md; the `@cell_struct` docstring).
- A cell of another type in a reactive field throws a `MethodError`, and the one site that needed the old wrap uses `_get_object_input` (plan/done/struct-layer-follow-up.md).
- A kind is found by its name when the macro expands, because no type exists then. `@cell_struct` does not accept a qualified kind; `_bare_kind` of `@document` does, and the struct audit left that difference to the document audit.
- The comment in `build_cell_struct_keyword_constructor` names the omnet-julia build that showed the trim error. The struct audit kept it, and a code comment may keep a private name.
- The duplicates in `DocumentMacro.jl` (`_REACTIVE_ANY`, `_emit_accessors`, `_emit_autowrap_ctor`, `_emit_keyword_ctors`) wait for the document audit (plan/done/struct-layer-audit.md, "Left for later").

## Checked and clean

- The layering: the layer imports only `CellModule`; the guard gives 10 of 10 in the baseline.
- The export block: one statement for each fragment, in the order of the includes and of the definitions.
- The module docstring and the two fragment headers.
- PAR-QUALIFIED-EXTENSION: the generated code qualifies `Base.getproperty` and `Base.setproperty!`, and the module has one bare `using`.
- The hygiene of the expansion: the generated code holds the kinds and `Cell` as objects, so a caller needs only `@cell_struct` in scope (tested).
- PAR-PER-EDITOR-STATE and PAR-NO-PROJECTION-GLOBALS: no mutable state.
- The naming of the other exported names: each starts with a verb, and `find_cell_struct_parameter_slots` can return `nothing`.
- No history comment, no line over 90 characters, no function over 60 lines, no definition over three positional arguments.
- No sealed file changed after its seal (8939434d, 2026-09-25).
- Baseline: `CellStruct` 53 pass, `CellStructPlan` 47 pass. The failures of `DocumentMacro` (Rule C) in the same run belong to the document layer.
