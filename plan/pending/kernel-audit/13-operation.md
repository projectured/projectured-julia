# Layer 13 — operation (`source/kernel/operation/`)

Commit 15b40434, 2026-09-27. Seal state: none sealed (0 of 7).

## Verdict

The operation layer holds the `Operation` contract, the operations that cross domains, and the seams to reroot, invert and describe them. Every kernel operation type has an inverse or an explicit `DoNothingOperation`, a description, and a correct reroot. The most important finding is a user-visible fault: `splice_number` drops a number text that does not parse yet, so a person can not type "-5" into an empty number. Most medium faults are in the seams. `operation_reference` answers `nothing` for the two kernel operations that carry a path. The default reader drops a `DoNothingOperation`. "Next hole" walks every document of the editor. A splice into a plain vector writes no cell, and a document-rooted write ignores its type checkpoints. A new operation that carries a path needs three methods. The rule text names a registration that a package above the kernel can not make.

## Shape

- Purpose: the reified edit. The layer declares `Operation`, `WrappingOperation` and `evaluate_operation`. It defines the operations that cross domains, the builders of a slot write and the text splice helpers. It holds the open seams that reroot, invert, walk and describe an operation.
- Files:

| file | lines | seal | what it holds |
| --- | ---: | --- | --- |
| [OperationModule.jl](../../../source/kernel/operation/OperationModule.jl) | 70 | ⬜ | module docstring, header, six includes |
| [OperationInterface.jl](../../../source/kernel/operation/OperationInterface.jl) | 258 | ⬜ | the two abstract types and 13 bodiless generics |
| [OperationDefaults.jl](../../../source/kernel/operation/OperationDefaults.jl) | 14 | ⬜ | the two catch-all `evaluate_operation` methods |
| [Operations.jl](../../../source/kernel/operation/Operations.jl) | 423 | ⬜ | ten operation types, the builders, the splice helpers, `child_reference_steps`, the "next hole" walk |
| [Rerooting.jl](../../../source/kernel/operation/Rerooting.jl) | 59 | ⬜ | `reroot_reference`, the base methods of `reroot_operation`, the defaults of `operation_reference`, `retarget_operation`, `operation_travels_unchanged` |
| [Inversion.jl](../../../source/kernel/operation/Inversion.jl) | 129 | ⬜ | `make_inverse_operation` for each kernel operation, `evaluate_invertible_operation!`, `get_slot_at` |
| [Description.jl](../../../source/kernel/operation/Description.jl) | 71 | ⬜ | `describe_operation` |

- Imports: `FaultModule`, `CellModule`, `DocumentModule`, `ReferenceModule`, `SelectionModule`, all as bare `using`. `FaultModule` is used only to extend `is_passthrough_exception` for `QuitEditorException`. Imported by: `IntentModule`, `ProjectionModule`, `EditorModule` and `PlaybackModule` in the kernel; 45 source files outside the kernel; omnet-julia and inet-julia.
- Public surface: 33 exported names. Each has a user outside the layer. The least used: `child_reference_steps` and `get_slot_at` (one method each, in the collection package), `evaluate_invertible_operation!` (the undo package only) and `describe_operation` (the undo and gesture-log packages). `QuitEditorException` has no docstring.
- Operation types and their seams:

| type | evaluate | inverse | reroot | description |
| --- | --- | --- | --- | --- |
| `DoNothingOperation` | no-op | itself | catch-all | "do nothing" |
| `QuitEditorOperation` | throws | `DoNothingOperation` | catch-all | "quit" |
| `AdjustZoomOperation`, `AdjustFontZoomOperation` | backend (SDL) | `DoNothingOperation` | catch-all | "zoom …" |
| `ReplaceSelectionOperation` | `replace_selection!` at the root | selection now | method | "select …" |
| `SelectNextInsertionOperation` | walk at the root | selection now | catch-all (no path) | "select next insertion" |
| `ToggleCollapseOperation` | carried target | itself | catch-all (carried) | "toggle collapse" |
| `ReplaceReferencedValueOperation` | slot write | carried object | method | "set … = …" |
| `ReplaceViewStateOperation` | held operation | held operation | `WrappingOperation` | held operation |
| `CompoundOperation` | each member | only through `evaluate_invertible_operation!` | members | "compound(n): …" |

- State: none at module level.
- Tests: [test/kernel/operation/](../../../test/kernel/operation/) holds RerootingTest.jl (139 lines), InversionTest.jl (245) and TraversalTest.jl (55); the baseline run passes 28, 42 and 8 assertions. They cover the reroot base methods, the inverse of each kernel operation and the traversal seam. They do not cover the "next hole" walk, `describe_operation`, the splice helpers, the reroot of `ReplaceReferencedValueOperation`, or the defaults of `operation_reference`, `retarget_operation` and `operation_travels_unchanged` (finding L13-11).

## Summary

| Category | High | Medium | Low |
| --- | ---: | ---: | ---: |
| Correctness | 1 | 5 | 1 |
| Architecture | 0 | 2 | 0 |
| Shape | 0 | 0 | 2 |
| Naming | 0 | 1 | 1 |
| Documentation | 0 | 1 | 1 |
| Tests | 0 | 1 | 0 |

## Findings

### L13-1 A number text that does not parse yet is lost, so "-5" typed into an empty number gives 5

- Category: Correctness · Severity: High · Confidence: Confirmed from the code path (a run in a window would show it)
- Checked by the lead on 2026-09-27: Read the code: `splice_number` returns `nothing` when neither `tryparse` succeeds.
- Where: [Operations.jl:55](../../../source/kernel/operation/Operations.jl#L55) ⬜
- Evidence: `splice_number` returns `nothing` when the new text does not parse: `something(tryparse(Int, new_str), tryparse(Float64, new_str), Some(nothing))`. The evaluation of `ReplaceNumberRangeOperation` stores that result in the field ([PrimitiveDocument.jl:184](../../../source/platform/primitive/PrimitiveDocument.jl#L184), and line 210 for a cleared number). A number accepts a sign and an exponent mark as keys ([PrimitiveDocument.jl:114](../../../source/platform/primitive/PrimitiveDocument.jl#L114)), and a number value retypes a text edit to this operation ([ReaderDefaults.jl:61](../../../source/platform/projection/ReaderDefaults.jl#L61)). Scenario: the person selects all digits of a number, or starts in an empty number, and types "-". The spliced text is "-", `splice_number` returns `nothing`, the field becomes empty and the "-" is gone. The caret moves to `{1}` ([PrimitiveDocument.jl:176](../../../source/platform/primitive/PrimitiveDocument.jl#L176)). The "5" then splices into the empty text and gives 5. "1e5" gives 5 the same way, because "1e" does not parse.
- Rule: PAR-WIDE-FIELD-TYPES and PAR-DOMAIN-OWNS-EDITS (an intermediate state that a person passes through must be representable); bug.
- Fix: let `splice_number` return the spliced text when it does not parse, and let the number field hold that text until it parses. The field type of the number documents must admit the text.
- Reach: Operations.jl; PrimitiveDocument.jl and the number field declarations of the domains; [Clipboard.jl:309](../../../source/platform/clipboard/Clipboard.jl#L309), which tests a paste with `splice_number`.

### L13-2 `operation_reference` answers `nothing` for the two kernel operations that carry a path

- Category: Correctness · Severity: Medium · Confidence: Confirmed for the seam; Suspected for a failure (needs a path that does not map back)
- Where: [Rerooting.jl:55](../../../source/kernel/operation/Rerooting.jl#L55) ⬜
- Evidence: only the primitive package adds a method ([PrimitiveDocument.jl:293](../../../source/platform/primitive/PrimitiveDocument.jl#L293)). `ReplaceSelectionOperation` and a document-rooted `ReplaceReferencedValueOperation` have none. The contract says "The reference that `op` targets, or `nothing` when `op` carries none" ([OperationInterface.jl:150](../../../source/kernel/operation/OperationInterface.jl#L150)). Two callers trust it. [AssistantTurn.jl:1007](../../../source/platform/assistant/AssistantTurn.jl#L1007) forwards an operation unmapped when `operation_reference(op) === nothing`, so a `ReplaceSelectionOperation` whose path does not map back goes up with a path of the card's output domain. [Copying.jl:272](../../../source/platform/projection/generic/Copying.jl#L272) routes a `ReplaceSelectionOperation` by the node's own selection, not by the path of the operation.
- Rule: bug; the contract of `operation_reference`.
- Fix: add `operation_reference` and `retarget_operation` methods for `ReplaceSelectionOperation` and for a document-rooted `ReplaceReferencedValueOperation` in Rerooting.jl.
- Reach: Rerooting.jl; check the routes in Copying.jl and AssistantTurn.jl after the change.

### L13-3 "Next hole" searches every document of the editor, with no depth bound

- Category: Correctness · Severity: Medium · Confidence: Suspected (the logic is read; needs a run with two Julia documents in two tabs)
- Where: [Operations.jl:335](../../../source/kernel/operation/Operations.jl#L335), [Operations.jl:369](../../../source/kernel/operation/Operations.jl#L369) ⬜
- Evidence: the walk starts at `editor.document` and selects the first hole after the owner in pre-order. Nothing limits it to the document that holds the owner. In the application `editor.document` holds every pane, and `CellVector` answers `child_reference_steps` ([CellVector.jl:307](../../../source/platform/collection/CellVector.jl#L307)). So at the last hole of one Julia file the selection can go into another file in another tab, or into a copy that the clipboard holds. The walk stops only on an object that it saw before. A lazy `ListNode` makes a new node on each read of `next` ([LazyDocumentExample.jl:66](../../../example/platform/LazyDocumentExample.jl#L66)), so the walk does not end; `search_references` has `maxdepth` for this case ([ReferenceSearch.jl:57](../../../source/kernel/reference/ReferenceSearch.jl#L57)). The walk and `child_reference_steps` also repeat the document walk of the document layer (PAR-SEARCH-DONT-WALK), with a second seam that must agree with `evaluate_reference_step`. Line 340 reads `getfield(root, :selection)[]`; a dormant wrapper there reaches `strip_reference_types` and fails with a `MethodError`.
- Rule: PAR-SEARCH-DONT-WALK; bug.
- Fix: give the operation the path of the document to search (the reader knows it), search it with `search_references` and its `maxdepth`, and read the selection with `get_selection`. Then delete `child_reference_steps` and its `CellVector` method.
- Reach: Operations.jl, OperationInterface.jl, OperationModule.jl; [JuliaInsertionToSyntax.jl:188](../../../source/domain/julia/JuliaInsertionToSyntax.jl#L188) (the only producer); CellVector.jl, CollectionModule.jl; TraversalTest.jl.

### L13-4 The default reader drops `DoNothingOperation`, because no kernel operation answers `operation_travels_unchanged`

- Category: Correctness · Severity: Medium · Confidence: Confirmed that the default reader returns `nothing`; Suspected that a chain loses a suppression (needs a run)
- Where: [Rerooting.jl:59](../../../source/kernel/operation/Rerooting.jl#L59) ⬜; [ProjectionDefaults.jl:171](../../../source/kernel/projection/ProjectionDefaults.jl#L171) ⬜
- Evidence: `operation_travels_unchanged(op) = false`, and the layer adds no method for its own operations that carry no reference. The default reader names `ToggleCollapseOperation` and `SelectNextInsertionOperation` by type instead (ProjectionDefaults.jl lines 171-178). A `DoNothingOperation` reaches the last branch and becomes `nothing` (line 192). A chain then lets the earlier steps read the raw gesture again ([Chaining.jl:127](../../../source/platform/projection/higherorder/Chaining.jl#L127), "A claim that no step can carry is no claim"). The docstring calls `DoNothingOperation` "the canonical way to suppress a default behavior" ([Operations.jl:13](../../../source/kernel/operation/Operations.jl#L13)). Readers that answer it: [WindowManaging.jl:105](../../../source/platform/screen/WindowManaging.jl#L105), [CommandPaletteDecorator.jl:166](../../../source/platform/gesturehelp/CommandPaletteDecorator.jl#L166), and the widget bindings. `QuitEditorOperation` and the two zoom operations come from the editor loop, not from a reader, so they do not meet this branch today.
- Rule: the contract of `DoNothingOperation`; PAR-REGISTER-NEW-OPERATION (one registration path).
- Fix: in Rerooting.jl, answer `true` for `DoNothingOperation`, `QuitEditorOperation`, the two zoom operations, `ToggleCollapseOperation` and `SelectNextInsertionOperation`. Delete the two type branches in ProjectionDefaults.jl.
- Reach: Rerooting.jl; ProjectionDefaults.jl.

### L13-5 A wrapper that holds a `CompoundOperation` has no way back

- Category: Correctness · Severity: Medium · Confidence: Confirmed (no producer of such a wrapper exists today)
- Where: [Inversion.jl:18](../../../source/kernel/operation/Inversion.jl#L18), [Inversion.jl:54](../../../source/kernel/operation/Inversion.jl#L54) ⬜
- Evidence: `make_inverse_operation` has no method for `CompoundOperation`, so it answers `nothing`. The contract calls `nothing` "a truthful answer" for an operation with no way back ([OperationInterface.jl:199](../../../source/kernel/operation/OperationInterface.jl#L199)); a compound has a way back through `evaluate_invertible_operation!`. There is no `evaluate_invertible_operation!` method for `WrappingOperation`. So `evaluate_invertible_operation!(editor, ReplaceViewStateOperation(CompoundOperation(…)))` takes the default method, asks the wrapper for its inverse, reaches the compound and gets `nothing`: a history barrier. The fault barrier asks `make_inverse_operation` only ([FaultBarriers.jl:88](../../../source/kernel/editor/FaultBarriers.jl#L88)), so a compound that fails half way is never taken back; its comment says so.
- Rule: PAR-INVERTIBLE-OPERATIONS.
- Fix: add `evaluate_invertible_operation!(editor, op::WrappingOperation)` that inverts the held operation through `evaluate_invertible_operation!` when the wrapper has no `make_inverse_operation` method of its own. Say in the docstring of `make_inverse_operation` that a container answers `nothing` there and inverts through `evaluate_invertible_operation!`.
- Reach: Inversion.jl, OperationInterface.jl.

### L13-6 A document-rooted write removes its type checkpoints before it walks

- Category: Correctness · Severity: Medium · Confidence: Suspected (needs a run with a stale operation in the inbox); the strip is confirmed
- Where: [Operations.jl:235](../../../source/kernel/operation/Operations.jl#L235) ⬜
- Evidence: `reference = strip_reference_types(op.reference)`, then `evaluate_reference(root, parent_path)` (line 255). Without the types, a path that an edit made stale resolves to whatever node now stands at that place. An operation can wait: `post_operation!` queues it, a playback entry holds it, an agent builds it against an older tree. `make_inverse_operation` strips the same way ([Inversion.jl:79](../../../source/kernel/operation/Inversion.jl#L79)). No comment gives a reason for the strip.
- Rule: PAR-FOLDED-CHECKPOINTS ("Replay a cross-edit reference through `get_valid_reference_prefix` / `evaluate_reference` … rather than assuming a stored path still fits").
- Fix: walk to the parent with the typed path, so a changed node throws `ReferenceTypeMismatchException`. If a reader makes wrong types, fix that reader.
- Reach: Operations.jl, Inversion.jl.

### L13-7 The splice wraps each item in a `Cell` and changes a plain vector in place, with no cell write

- Category: Architecture · Severity: Medium · Confidence: Confirmed
- Where: [Operations.jl:167](../../../source/kernel/operation/Operations.jl#L167), [Operations.jl:176](../../../source/kernel/operation/Operations.jl#L176) ⬜
- Evidence: line 181: `insert!(parent, step.start + k, item isa AbstractCell ? item : Cell(item))`. For a plain `Vector` field, `evaluate_reference` answers the vector itself, and `insert!`, `deleteat!` and `setindex!` change it in place. The field cell is never written, so nothing that read it recomputes. The vector then holds `Cell`s among plain values. The kernel test uses such a field (`items::Vector{Any}`, [InversionTest.jl:29](../../../test/kernel/operation/InversionTest.jl#L29)) and reads it back through `unwrap_cell` (line 54). A reactive `CellVector` wraps a value itself ([CellVector.jl:205](../../../source/platform/collection/CellVector.jl#L205)), so the kernel wrap is redundant there. A `CellVector` with plain storage stores the value as given ([CellVector.jl:239](../../../source/platform/collection/CellVector.jl#L239)), so it stores the kernel's `Cell` as a value. The layer asks the collection package through `get_slot_at` for the inverse, but decides the storage form itself for the write.
- Rule: PAR-MUTATE-OR-NULL-IOMAP, PAR-NO-NESTED-CELL, PAR-FIELDS-ARE-CELLS.
- Fix: pass each item as it is and let the collection wrap it. Refuse a splice into a container that is not a document collection, or write the field cell after the change.
- Reach: Operations.jl; InversionTest.jl (its list must be a test-local document collection).

### L13-8 A new operation that carries a path needs three methods, and the rule names a registration that a higher package can not make

- Category: Architecture · Severity: Medium · Confidence: Confirmed
- Where: [Rerooting.jl:14](../../../source/kernel/operation/Rerooting.jl#L14), [Rerooting.jl:38](../../../source/kernel/operation/Rerooting.jl#L38) ⬜
- Evidence: PAR-REGISTER-NEW-OPERATION and the INVARIANT comment say an operation "must be registered in both the default `read_intent` and `reroot_operation`". The default reader is in ProjectionDefaults.jl, which a package above the kernel can not edit; it reaches an unnamed operation only through `operation_reference` and `retarget_operation` ([ProjectionDefaults.jl:183](../../../source/kernel/projection/ProjectionDefaults.jl#L183)). The catch-all `reroot_operation(op, steps) = op` does not use that pair. So an operation needs `reroot_operation`, `operation_reference` and `retarget_operation`, as [PrimitiveDocument.jl:283](../../../source/platform/primitive/PrimitiveDocument.jl#L283) does. `ReplaceTextRangeOperation` adds only `reroot_operation` ([TextDocument.jl:1176](../../../source/platform/text/TextDocument.jl#L1176)), so the default reader drops it. The text and syntax packages carry it with readers of their own ([SyntaxToText.jl:193](../../../source/platform/syntax/SyntaxToText.jl#L193)).
- Rule: PAR-REGISTER-NEW-OPERATION (its text), PAR-FRAMEWORKS-SINK (one seam).
- Fix: let the catch-all `reroot_operation` retarget through `operation_reference` and `retarget_operation` when the operation reports a reference. Then one pair registers both. Correct PAR-REGISTER-NEW-OPERATION, the comment and operation.md.
- Reach: Rerooting.jl; architecture-invariants.md; operation.md; the per-type `reroot_operation` methods in the primitive and text packages can go.

### L13-9 The builders `insert_elements` and `delete_elements` count from 0, and the editor verbs `insert_elements!` and `delete_elements!` count from 1

- Category: Naming · Severity: Medium · Confidence: Confirmed
- Where: [Operations.jl:298](../../../source/kernel/operation/Operations.jl#L298), [Operations.jl:313](../../../source/kernel/operation/Operations.jl#L313) ⬜; [DocumentEdits.jl:73](../../../source/kernel/editor/DocumentEdits.jl#L73), [DocumentEdits.jl:93](../../../source/kernel/editor/DocumentEdits.jl#L93) ⬜
- Evidence: `delete_elements(path, index[, count])` removes elements "starting at the 0-based `index`". `delete_elements!(editor, collection, index, count = 1)` removes them "starting at the 1-based `index`". So `delete_elements(p, 2)` removes the third element and `delete_elements!(e, c, 2)` the second. The two names differ by one character. The builders, and `replace_document`, read as actions but return an operation; the naming rules give `make_` to a function that makes a new thing.
- Rule: naming-rules.md, "The verb follows the nature of the work" (`make_`); guessability in both directions.
- Fix: rename the builders to `make_insert_elements_operation`, `make_delete_elements_operation` and `make_replace_document_operation` with `workspace/bin/julia-rename.jl`. Update PAR-PREFER-REPLACE-VALUE and operation.md.
- Reach: Operations.jl, OperationModule.jl; up to 6 source files and 4 test files for each name; omnet-julia (2 files); architecture-invariants.md.

### L13-10 The fall-through comment and the guide say that a reader returns a raw gesture when it declines

- Category: Documentation · Severity: Medium · Confidence: Confirmed
- Where: [OperationDefaults.jl:9](../../../source/kernel/operation/OperationDefaults.jl#L9) ⬜; [operation.md:298](../../../documentation/package/kernel/operation.md#L298)
- Evidence: "a reader that declines returns a raw gesture/event or `nothing`, and those flow all the way up to here". The guide says the catch-all exists "so the reader can return whatever it likes, including a raw event". A chain takes any value that is not `nothing` as an answer and stops its search ([Chaining.jl:149](../../../source/platform/projection/higherorder/Chaining.jl#L149)). So a reader that returns its gesture ends the read with a gesture as the operation. The editor loop evaluates only an `Operation` ([ReadEvaluatePrint.jl:43](../../../source/kernel/editor/ReadEvaluatePrint.jl#L43)). The file-system reader declines a raw gesture for this reason (`op isa Operation || return nothing`, [WorkspaceToFileSystem.jl:98](../../../source/platform/filesystem/WorkspaceToFileSystem.jl#L98)); the text teaches the opposite.
- Rule: PAR-READER-IS-PURE (a reader returns an operation or `nothing`); PAR-HONEST-DOCS.
- Fix: say that a reader that declines returns `nothing`, and that the catch-all accepts any value that is not an `Operation`, so a stray value does no harm.
- Reach: OperationDefaults.jl; operation.md.

### L13-11 Several contracts of the layer have no kernel test

- Category: Tests · Severity: Medium · Confidence: Confirmed
- Where: [test/kernel/operation/](../../../test/kernel/operation/)
- Evidence:
  - The "next hole" evaluation has tests only in the Julia and undo suites.
  - No test asserts a result of `describe_operation`; [HistorySweepTest.jl:28](../../../test/projectured/editor/HistorySweepTest.jl#L28) only prints it.
  - `splice_string`, `splice_number` and `splice_value!` have no direct test; [TypeinTest.jl:228](../../../test/platform/editor/TypeinTest.jl#L228) keeps a local copy of `splice_string`.
  - The docstring of [RerootingTest.jl:3](../../../test/kernel/operation/RerootingTest.jl#L3) says it verifies `ReplaceReferencedValueOperation`; no testset reroots one.
  - No test covers the defaults of `operation_reference`, `retarget_operation` and `operation_travels_unchanged`.
  - The override in [TraversalTest.jl:29](../../../test/kernel/operation/TraversalTest.jl#L29) addresses `ToyList` with `[i]`, a path that `evaluate_reference` can not follow, because `ToyList` has no `getindex`.
- Rule: PAR-NEW-CODE-SHIPS-TESTS.
- Fix: add these tests to test/kernel/operation/; make the ToyList override use `.items[i]`.
- Reach: the three test files.

### L13-12 Four small write and inverse cases give a wrong or no result

- Category: Correctness · Severity: Low · Confidence: Confirmed, except the last item (Suspected, needs a run)
- Where: [Inversion.jl:70](../../../source/kernel/operation/Inversion.jl#L70), [Operations.jl:161](../../../source/kernel/operation/Operations.jl#L161), [Operations.jl:167](../../../source/kernel/operation/Operations.jl#L167), [Operations.jl:89](../../../source/kernel/operation/Operations.jl#L89) ⬜
- Evidence:
  - The inverse of a selection move from "no selection" is `DoNothingOperation`, because `ReplaceSelectionOperation` can not hold `nothing`. An undo leaves the caret where the move put it.
  - `_write_slot!` with a field step calls `getfield`. The reference layer resolves a field step on an `AbstractDict` as a key ([ReferenceStep.jl:134](../../../source/kernel/reference/ReferenceStep.jl#L134)), so a write to that path fails.
  - An element overwrite with a range wider than one item writes only the first slot.
  - `CompoundOperation(one_operation)` takes the one-argument constructor that Julia makes for the typed field, not the variadic method on line 89. That constructor calls `convert` and fails.
- Rule: bug; PAR-INVERTIBLE-OPERATIONS for the first item.
- Fix: let `ReplaceSelectionOperation` hold `nothing`, or record a clear; refuse a dict field and a wide overwrite with a clear error; add `CompoundOperation(operation::Operation)`.
- Reach: Operations.jl, Inversion.jl.

### L13-13 Reference helpers, redundant methods and editor operations sit in this layer

- Category: Shape · Severity: Low · Confidence: Confirmed
- Where: [Rerooting.jl:29](../../../source/kernel/operation/Rerooting.jl#L29), [Operations.jl:152](../../../source/kernel/operation/Operations.jl#L152), [Operations.jl:230](../../../source/kernel/operation/Operations.jl#L230), [Operations.jl:23](../../../source/kernel/operation/Operations.jl#L23), [Description.jl:22](../../../source/kernel/operation/Description.jl#L22), [Operations.jl:118](../../../source/kernel/operation/Operations.jl#L118) ⬜
- Evidence:
  - `reroot_reference` and `_split_terminal_step` touch only references. `reroot_reference` builds `ConcreteReference` nodes by hand and repeats `concat_references(Reference(steps...), ref)`. The field constructor of `ReplaceReferencedValueOperation` also builds a node by hand (PAR-REFERENCE-DSL).
  - The catch-all `invalidate_projection!(editor) = nothing` is in Operations.jl, not in OperationDefaults.jl, which says it holds "the fallback behaviours".
  - `describe_operation(::ReplaceViewStateOperation)` repeats the `WrappingOperation` method on line 70.
  - Only the editor layer makes `AdjustZoomOperation` and `AdjustFontZoomOperation`, and only the SDL backend evaluates them. Planned: plan/pending/font-zoom-per-editor.md.
- Rule: PAR-REFERENCE-DSL; architecture-rules.md (a thing lives with its concept).
- Fix: move `reroot_reference` to the reference layer as a use of `concat_references`; move the catch-all to OperationDefaults.jl; delete the redundant description method.
- Reach: Rerooting.jl, Operations.jl, Description.jl; the reference layer.

### L13-14 The module header and the source form do not follow the code-quality rules

- Category: Shape · Severity: Low · Confidence: Confirmed
- Where: [OperationModule.jl:38](../../../source/kernel/operation/OperationModule.jl#L38) ⬜
- Evidence: the `using` lines are not sorted (`FaultModule` before `CellModule`). One `export` statement holds comments ("# from Operations.jl"); planned: plan/pending/export-block-rule.md (5 findings). The includes carry trailing comments. `delete_elements` takes an optional positional argument beside a keyword (code-quality-rules.md §4). Operations.jl lines 27, 44, 163, 248, 299 and 314 and Description.jl line 26 are longer than 90 characters. Five fragment headers have 4 to 20 lines, not one.
- Rule: code-quality-rules.md §1, §4, §5.
- Fix: sort the `using` lines, one export statement for each fragment, make `count` a keyword, wrap the lines.
- Reach: all seven files.

### L13-15 Three exported functions start with a noun, and a second structural exception is not written down

- Category: Naming · Severity: Low · Confidence: Confirmed
- Where: [OperationInterface.jl:138](../../../source/kernel/operation/OperationInterface.jl#L138), [OperationInterface.jl:159](../../../source/kernel/operation/OperationInterface.jl#L159), [OperationInterface.jl:188](../../../source/kernel/operation/OperationInterface.jl#L188), [OperationInterface.jl:50](../../../source/kernel/operation/OperationInterface.jl#L50) ⬜
- Evidence: `child_reference_steps`, `operation_reference` and `operation_travels_unchanged` do not start with a verb. `WrappingOperation` is not a verb-first phrase; naming-rules.md names `CompoundOperation` as "the one structural exception".
- Rule: naming-rules.md, "Every function name starts with a verb"; "Operations are verb-first phrases".
- Fix: `get_operation_reference`, a predicate such as `is_self_contained_operation`, and `collect_child_reference_steps` (or its removal, L13-3). Add `WrappingOperation` to the exceptions in naming-rules.md.
- Reach: OperationInterface.jl, OperationModule.jl, Rerooting.jl; 12 source files that extend `operation_travels_unchanged`, 5 that use `operation_reference`; omnet-julia (5 files); naming-rules.md.

### L13-16 The layer text and the design document describe an older layer

- Category: Documentation · Severity: Low · Confidence: Confirmed
- Where: [OperationModule.jl:9](../../../source/kernel/operation/OperationModule.jl#L9) ⬜; [operation.md](../../../documentation/package/kernel/operation.md)
- Evidence:
  - The module docstring says "five fragments" (there are six), links `Interface.jl` (the file is OperationInterface.jl), and says "two open seams" before it lists four names. [Operations.jl:4](../../../source/kernel/operation/Operations.jl#L4) also says `Interface.jl`. The header of OperationInterface.jl names two of the five body files.
  - `AdjustZoomOperation` refers to "the generic no-op fallback above"; it is in OperationDefaults.jl ([Operations.jl:115](../../../source/kernel/operation/Operations.jl#L115)). [Description.jl:43](../../../source/kernel/operation/Description.jl#L43) uses the type name `StringReplaceRangeOperation`, which does not exist.
  - The example of `Operation` writes `o.box.width[] -= 1`; a property read already unwraps the cell (PAR-NEVER-GUESS-NAMES), and the example has no inverse. The docstring of `insert_elements` shows `selection` as positional; it is a keyword. `QuitEditorException` has no docstring.
  - Contract text names higher code: `get_slot_at` says "the collection package answers", and `QuitEditorOperation` names "the editor loop".
  - operation.md shows the evaluation of `ReplaceSelectionOperation` as `clear_selection!` then `set_selection!` (the code calls `replace_selection!`); says "three fragments" and names `Interface.jl`; puts the window operations in Operations.jl (the file says the opposite, line 421); gives the path `document/Primitive.jl`; says `FaultModule` is "the barrier around the evaluation of an operation"; lists `clear_selection!`, `set_selection!`, `with_selection` as the selection imports; gives the test paths `test/operation/…`; and a subsection at line 139 cuts its table in two. It has no section for inversion, description, `ReplaceViewStateOperation` or `operation_travels_unchanged`.
- Rule: PAR-HONEST-DOCS, PAR-MODULE-DOCSTRING, PAR-NO-CONSUMER-DOCS, PAR-UPDATE-THE-GUIDE.
- Fix: correct the module docstring and the headers; rewrite the layer section of operation.md from the six files.
- Reach: OperationModule.jl, OperationInterface.jl, Operations.jl, Description.jl; operation.md.

## Accepted before, not raised again

- The catch-all `evaluate_operation(editor, ::Any) = nothing` is part of PAR-MUTATE-OR-NULL-IOMAP.
- A zoom, a quit and a file write answer `DoNothingOperation()` as their inverse; the contract of `make_inverse_operation` states this choice.
- An inverse carries the object that it writes into, not a path from the root (decided with the undo work, commit e276b0cf).
- `CompoundOperation` is the named structural exception of the naming rules.
- The two zoom operations belong to the deferred plan/pending/font-zoom-per-editor.md.
- A cell holds `Any` on purpose, and so do the payload fields of an operation.

## Checked and clean

- PAR-INTERFACE-DECLARES-ONLY: OperationInterface.jl holds two abstract types and 13 bodiless generics, all exported; `test_kernel_layering()` lists the file.
- PAR-ONE-WAY-TO-EDIT: the builders return operations; only `evaluate_operation` writes.
- PAR-PREFER-REPLACE-VALUE: the layer's own edits reduce to `ReplaceReferencedValueOperation` and its builders.
- PAR-MUTATE-OR-NULL-IOMAP: a whole-root swap calls `invalidate_projection!`; other writes go through cells, except the plain-vector case of L13-7.
- PAR-INVERTIBLE-OPERATIONS: each kernel operation type has an inverse or `DoNothingOperation`, except the container case of L13-5; InversionTest.jl proves each round trip.
- The reroot methods cover each kernel operation type. The two types that carry a path have methods, the compound and the wrapper map what they hold, and the others carry no path.
- Description covers each kernel operation type by a method or by the fallback.
- PAR-SELECTION-WRITTEN-AT-ROOT: `ReplaceSelectionOperation` and `SelectNextInsertionOperation` write at `editor.document`.
- Operation type names: each is a verb-first phrase with the `Operation` suffix, except `CompoundOperation` (sanctioned) and `WrappingOperation` (L13-15).
- PAR-PER-EDITOR-STATE: no module-level mutable value.
- PAR-QUALIFIED-EXTENSION: `FaultModule.is_passthrough_exception` is extended by qualification; the file imports no name that it does not extend.
- PAR-REPORT-NEVER-THROWS: `QuitEditorException` is a passthrough exception, so no barrier catches a quit.
- Argument rule: `splice_string` and `splice_number` carry `# @positional:` markers; `splice_value!` is on the protocol list.
