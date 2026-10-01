# Layer 12 — selection (`source/kernel/selection/`)

Commit 15b40434, 2026-09-27. Seal state: all sealed (3 of 3).

## Verdict

The selection layer is small and holds no global state. It keeps its main promise: a write is canonical and atomic, and it never half-applies. It has two logic faults. The descent helper steps into element k+1 for a caret `{k}` that stands between documents. The writers keep the step objects that the caller gives, so a later caret move can change the caller's path. Two texts that the assistant reads teach the wrong call. The docstring recommends `set_selection!` to move the caret, and `with_selection` changes its argument although its name says "copy". The kernel suite does not test `replace_selection!`, dormant selections or the mismatch exception. Every fix except the tests changes a sealed file.

## Shape

- Purpose: read, clear, set and replace the selection of a document. The selection is a `Reference` that each document on the path holds as its own suffix. The layer also keeps a dormant selection for a document that asks for it, and gives the printers `map_selection_forward`.
- Files:

| file | lines | seal | what it holds |
| --- | ---: | --- | --- |
| [SelectionModule.jl](../../../source/kernel/selection/SelectionModule.jl) | 43 | 🔒 | module docstring, header, two includes |
| [SelectionInterface.jl](../../../source/kernel/selection/SelectionInterface.jl) | 181 | 🔒 | nine bodiless generics and their docstrings |
| [SelectionDefaults.jl](../../../source/kernel/selection/SelectionDefaults.jl) | 345 | 🔒 | the default methods, `SelectionMismatchException`, `@with_selection`, the dormant helpers, the in-place writer `_sync_selection!`, the descent helper `_selection_child` |

- Imports: `CellModule`, `DocumentModule`, `ReferenceModule`, all as bare `using`. Imported by: `OperationModule`, `ProjectionModule` and `EditorModule` in the kernel, and 24 source files outside the kernel.
- Public surface: 11 exported names. Each name has a user outside the layer. `has_dormant_selection` is the only generic that other packages extend (widget, pane, conversation). `is_live_selection` has 2 users in `source/` and `map_selection_forward` has 3; omnet-julia uses both. No exported name is dead.
- State: none at module level. The dormant state lives in the `selection` cell of each document, as a `SelectionDocument` of the document layer.
- Tests: there is no `test/kernel/selection/`. The kernel tests the layer in one testset, [DocumentContractTest.jl:96](../../../test/kernel/document/DocumentContractTest.jl#L96), which covers `with_selection`, `set_selection!` and a deep `clear_selection!`. [InversionTest.jl](../../../test/kernel/operation/InversionTest.jl) calls `replace_selection!` as a set-up step. The dormant selections have tests only in the umbrella suite ([ApplicationTest.jl](../../../test/projectured/editor/ApplicationTest.jl)). No test file names `is_live_selection`, `map_selection_forward` or `@with_selection`.
- Seal history: `git log` shows three commits after the seal. 47a44242 and 0b77137a (2026-09-13) record the permission of 2026-09-12 in their messages. 29ad8218 (2026-09-18) changes docstrings only, with the permission of 2026-09-18. No commit changed a file without permission.

## Summary

| Category | High | Medium | Low |
| --- | ---: | ---: | ---: |
| Correctness | 0 | 1 | 0 |
| Shape | 0 | 0 | 2 |
| State | 0 | 1 | 0 |
| Naming | 0 | 1 | 0 |
| Documentation | 0 | 1 | 3 |
| Tests | 0 | 1 | 0 |

## Findings

### L12-1 A caret between two documents of a collection selects the next document as a whole

- Category: Correctness · Severity: Medium · Confidence: Suspected (the code is read; a run must select `{k}` on a collection of documents and read the selection of element k+1)
- Where: [SelectionDefaults.jl:324](../../../source/kernel/selection/SelectionDefaults.jl#L324) 🔒
- Evidence: `_selection_child` uses only the start of a range step: `idx = h.start + 1` (line 326). It ignores `stop`. Take a caret `{k}` on a collection whose elements are documents. The walk goes into element k+1 and writes the tail, an `EmptyReference()`, into its `selection`. That value means "the whole element is selected" (PAR-EMPTY-PATH-IS-SELECTION). So the collection shows a caret, and element k+1 shows a whole-element selection. The reference layer does not agree: a zero-width step evaluates to `Position(k)` and "lands on no child node" ([ReferenceStep.jl:116](../../../source/kernel/reference/ReferenceStep.jl#L116), [ReferenceEvaluation.jl:166](../../../source/kernel/reference/ReferenceEvaluation.jl#L166)). A range `[i, j]` is documented as "a multi-element selection" ([ReferenceStep.jl:31](../../../source/kernel/reference/ReferenceStep.jl#L31)), but the walk marks only element i.
- Rule: bug. The selection layer and the reference layer must read one step the same way.
- Fix: in `_selection_child`, return `nothing` for a caret step. The caret then stays on the collection that holds it. For a range wider than one item, `evaluate_reference_step` also steps into item i, so the owner must decide what a range selection stores before the walk changes.
- Reach: SelectionDefaults.jl 🔒.

### L12-2 The writers store the step objects of the path that the caller gives

- Category: State · Severity: Medium · Confidence: Confirmed for the shared objects; Suspected for a visible failure (no caller-held path was seen to change)
- Where: [SelectionDefaults.jl:150](../../../source/kernel/selection/SelectionDefaults.jl#L150), [SelectionDefaults.jl:340](../../../source/kernel/selection/SelectionDefaults.jl#L340) 🔒
- Evidence: `_matched_selection` builds the stored path with `annotate_reference_types(document, strip_reference_types(path))`. Both functions make new path nodes but keep each step object: `ConcreteReference(nothing, step, rest)` ([ReferenceEvaluation.jl:206](../../../source/kernel/reference/ReferenceEvaluation.jl#L206)). Later, `_mutate_terminal_step!` writes `getfield(old, :start)[]` and `getfield(old, :stop)[]` of the stored step. That step is the object that the caller passed in. The caller can hold it in an operation that a log keeps, in a module constant, or in a path that `concat_references` shares ([ReferencePath.jl:209](../../../source/kernel/reference/ReferencePath.jl#L209)). `copy_reference` exists because the stored path is live, and [InversionTest.jl](../../../test/kernel/operation/InversionTest.jl) tests that a capture is a copy. The writers do not copy what they take in. The write in place occurs only at a node whose own path starts with the range step and has no document child (line 288).
- Rule: PAR-PER-EDITOR-STATE, when the shared object is a module constant; otherwise a design fault.
- Fix: copy the terminal range step with `copy_reference` in `_matched_selection`, before the write.
- Reach: SelectionDefaults.jl 🔒.

### L12-3 `with_selection` changes its argument, but its name and the naming rules say that it makes a copy

- Category: Naming · Severity: Medium · Confidence: Confirmed
- Where: [SelectionDefaults.jl:200](../../../source/kernel/selection/SelectionDefaults.jl#L200), [SelectionInterface.jl:88](../../../source/kernel/selection/SelectionInterface.jl#L88) 🔒
- Evidence: `with_selection(document, path) = (set_selection!(document, path); document)`. The test asserts `n2 === n` ([DocumentContractTest.jl:101](../../../test/kernel/document/DocumentContractTest.jl#L101)). [naming-rules.md:304](../../../documentation/rule/naming-rules.md#L304) gives this exact name as the example of a derived copy: "Derived copies are `with_<stem>`: `with_property`, `with_selection`, `with_exact_size` — return a copy with one aspect changed." A caller who trusts the rule writes `b = with_selection(a, p)` and changes `a`. The name also has no `!`. `@with_selection` has the same fault.
- Rule: naming-rules.md, "Derived copies are `with_<stem>`" and "Mutating functions end with `!`".
- Fix: give the function and the macro a name that ends in `!`, or let `set_selection!` return the document and replace the calls. Remove `with_selection` from the example list in naming-rules.md. Use `workspace/bin/julia-rename.jl`.
- Reach: SelectionModule.jl, SelectionInterface.jl and SelectionDefaults.jl 🔒; 9 source files and 8 test files that name `with_selection` or `@with_selection`; naming-rules.md. No use in omnet-julia or inet-julia.

### L12-4 The docstring of `set_selection!` tells the assistant to use it to move the caret

- Category: Documentation · Severity: Medium · Confidence: Confirmed
- Where: [SelectionInterface.jl:57](../../../source/kernel/selection/SelectionInterface.jl#L57) 🔒
- Evidence: "Use it to move the caret after an edit, to select what a search found, or to build a document that opens with something already selected." The example is `set_selection!(document, @reference(document, rows[2].name))`. PAR-REPLACE-SELECTION says: use `replace_selection!` whenever the cursor moves, because a bare `set_selection!` can leave a second cursor. PAR-SELECTION-WRITTEN-AT-ROOT says that code that moves the selection makes an operation from the root. code-quality-rules.md §1 says that `search_api` and the meaning model read the "Use it to" paragraph, so the assistant gets this advice first. `replace_selection!` has no "Use it to" paragraph and no example (lines 102-120).
- Rule: PAR-REPLACE-SELECTION, PAR-SELECTION-WRITTEN-AT-ROOT, code-quality-rules.md §1.
- Fix: move the goals "move the caret" and "select what a search found" to `replace_selection!`, with an example that evaluates a `ReplaceSelectionOperation` at `editor.document`. Keep only "a document that nothing holds yet" for `set_selection!`.
- Reach: SelectionInterface.jl 🔒.

### L12-5 The kernel suite has no test of the writers of the layer

- Category: Tests · Severity: Medium · Confidence: Confirmed
- Where: `test/kernel/` has no `selection/` folder; [DocumentContractTest.jl:96](../../../test/kernel/document/DocumentContractTest.jl#L96) is the only kernel testset.
- Evidence: no kernel test asserts these contracts: a mismatch throws `SelectionMismatchException` and leaves the cell unchanged; `replace_selection!` clears the divergent branch; a caret move writes no selection cell of an ancestor; a keeper marks a branch dormant and a later write makes it live again; `map_selection_forward` carries the dormant state; `@with_selection` builds a typed path. `SelectionMismatchException` occurs in tests only as an expected failure of the umbrella sweeps ([MouseClickTest.jl:323](../../../test/projectured/editor/MouseClickTest.jl#L323), [ExampleSweeps.jl:80](../../../test/projectured/editor/ExampleSweeps.jl#L80)). The dormant logic has tests only in the umbrella ([ApplicationTest.jl](../../../test/projectured/editor/ApplicationTest.jl)).
- Rule: PAR-NEW-CODE-SHIPS-TESTS (the lowest test package that can express them).
- Fix: add `test/kernel/selection/SelectionTest.jl` with test-local `@document` types, and register it in [KernelSuite.jl](../../../test/kernel/KernelSuite.jl).
- Reach: one new test file and KernelSuite.jl; no source change.

### L12-6 Eight of the nine open generics have no method outside the layer, and the value readers are private

- Category: Shape · Severity: Low · Confidence: Confirmed
- Where: [SelectionInterface.jl](../../../source/kernel/selection/SelectionInterface.jl) 🔒, [SelectionDefaults.jl:17](../../../source/kernel/selection/SelectionDefaults.jl#L17) 🔒
- Evidence: the module docstring says a document "overrides" `clear_selection!` and `set_selection!`. A search of projectured-julia, omnet-julia and inet-julia finds a method only for `has_dormant_selection`. The readers `get_stored_selection` and `is_live_selection` take a document. A painter holds the stored value, not the document, so [TextToGraphics.jl:114](../../../source/platform/text/TextToGraphics.jl#L114) copies the private `_get_stored_path` and `_is_live_value`.
- Rule: code-quality-rules.md (one definition, no copy); PAR-MODULE-BOUNDARY-IS-API.
- Fix: export the two value readers (or add methods on `SelectionDocument`) and delete the copy in TextToGraphics.jl. Say in the module docstring which generics a document extends.
- Reach: SelectionModule.jl and SelectionDefaults.jl 🔒; TextToGraphics.jl.

### L12-7 The header of the module and the line lengths do not follow the code-quality rules

- Category: Shape · Severity: Low · Confidence: Confirmed
- Where: [SelectionModule.jl:35](../../../source/kernel/selection/SelectionModule.jl#L35) 🔒
- Evidence: one `export` statement mixes the names of both fragments (`SelectionMismatchException` and `@with_selection` come from SelectionDefaults.jl). Planned: plan/pending/export-block-rule.md (1 finding, sealed). Nine lines are longer than 90 characters: SelectionDefaults.jl lines 42, 151, 274, 289, 299, 327 and SelectionModule.jl lines 12, 25, 26. The two fragment headers have four and five lines, not one.
- Rule: code-quality-rules.md §1 and §5.
- Fix: one export statement for each fragment; wrap the long lines; shorten the headers.
- Reach: all three files 🔒.

### L12-8 Two docstrings promise more than the writers do

- Category: Documentation · Severity: Low · Confidence: Confirmed
- Where: [SelectionInterface.jl:36](../../../source/kernel/selection/SelectionInterface.jl#L36), [SelectionInterface.jl:112](../../../source/kernel/selection/SelectionInterface.jl#L112) 🔒
- Evidence: `clear_selection!` says "It clears the whole document, not only its root". It also says that it "clears the selection from `document` and all its children". The code walks only the stored path ([SelectionDefaults.jl:44](../../../source/kernel/selection/SelectionDefaults.jl#L44)). A dormant selection in another tab stays, and so does a branch that a bare `set_selection!` left. `replace_selection!` says that a caret move "mutates just that step's start/stop cells". For the usual leaf path `.value{k}` the head is a field step. So the branch at line 288 does not apply, and the leaf's own `selection` cell gets the new path.
- Rule: PAR-HONEST-DOCS.
- Fix: say "along the path that it holds" for `clear_selection!`. Say for `replace_selection!` that the leaf cell is written once and the ancestors are not.
- Reach: SelectionInterface.jl 🔒.

### L12-9 A comment records what the code did before

- Category: Documentation · Severity: Low · Confidence: Confirmed
- Where: [SelectionDefaults.jl:76](../../../source/kernel/selection/SelectionDefaults.jl#L76) 🔒
- Evidence: "At a divergence the old branch used to be cleared unconditionally. It is now either cleared, exactly as before, or kept and marked dormant". code-quality-rules.md §2 names this line as the one history comment that waits for permission.
- Rule: CLAUDE.md "A comment says what is, never what was"; PAR-TIGHT-COMMENTS.
- Fix: "At a divergence the old branch is cleared, or kept and marked dormant when a document on it asks to keep it."
- Reach: SelectionDefaults.jl 🔒.

### L12-10 The layer text and the design document are stale in several places

- Category: Documentation · Severity: Low · Confidence: Confirmed
- Where: [SelectionInterface.jl:1](../../../source/kernel/selection/SelectionInterface.jl#L1), [SelectionDefaults.jl:1](../../../source/kernel/selection/SelectionDefaults.jl#L1), [SelectionModule.jl:1](../../../source/kernel/selection/SelectionModule.jl#L1) 🔒; [selection.md](../../../documentation/package/kernel/selection.md)
- Evidence:
  - The interface header names four generics ("read, clear, set, and replace"); the file declares nine. The defaults header names four private helpers; the file has twelve. The module docstring does not name the dormant generics or `map_selection_forward`.
  - Contract text names higher concepts: "a tab group", "a pane group", "a tabbed pane" (SelectionInterface.jl lines 130, 141, 155) and "a `CellVector`" (SelectionDefaults.jl line 87). PAR-NO-CONSUMER-DOCS lets a seam name a concept, not a higher type such as `CellVector`.
  - selection.md line 32 gives the old layer numbers "(8)" and "(7)"; they are 11 and 10. Line 100 links `SelectionMismatchException` to `#dormant-selections`.
  - selection.md lines 319-321 say that a node with no selection "falls back to forwarding to each child in turn". [WidgetToGraphics.jl:3838](../../../source/platform/widget/WidgetToGraphics.jl#L3838) returns `nothing` in that case, and PAR-REACTIVE-OUTPUT-SELECTION forbids the fallback.
- Rule: PAR-HONEST-DOCS, PAR-NO-CONSUMER-DOCS, PAR-MODULE-DOCSTRING.
- Fix: correct the headers and the three statements in selection.md.
- Reach: the three layer files 🔒; selection.md.

## Accepted before, not raised again

- `has_dormant_selection` asks a policy ("does this document keep a dormant selection"), and its name reads as a question about the state now. The rename from `keeps_dormant_selection` is the owner's decision (commit 0b77137a, plan/pending/naming-rule-violations.md, "certain").
- The changes after the seal (2026-09-13 and 2026-09-18) carry the permission of the owner in their commit messages.
- A terminal caret is accepted by reachability, not by a bound check. The `set_selection!` docstring states this limit.
- A cell holds `Any` on purpose.

## Checked and clean

- PAR-INTERFACE-DECLARES-ONLY: SelectionInterface.jl holds only docstrings and nine bodiless generics. The module exports all nine, and `test_kernel_layering()` lists the file.
- PAR-EVERY-DOCUMENT-HAS-SELECTION: the walk enters only a `Document` child; any other value stops it.
- PAR-REPLACE-SELECTION (the code): `replace_selection!` clears the old branch, or marks it dormant, before it writes the new suffix.
- PAR-SELECTION-WRITTEN-AT-ROOT (the code): the layer starts no write below the document that it gets; the descent is part of one write.
- PAR-EMPTY-PATH-IS-SELECTION: `nothing` and `EmptyReference()` stay distinct in each writer.
- PAR-REACTIVE-OUTPUT-SELECTION: `map_selection_forward` gives a printer the live or dormant image in one call.
- Atomic write: `_matched_selection` validates the whole canonical path before any cell changes.
- PAR-PER-EDITOR-STATE and PAR-NO-PROJECTION-GLOBALS: no module-level mutable value.
- PAR-QUALIFIED-EXTENSION and PAR-MODULE-BOUNDARY-IS-API: bare `using` only; no qualified access to a private name.
- PAR-CITE-EXCEPTIONS-ONLY: no rule is cited in the source.
- The names of the exported functions: all start with a verb, except the accepted `has_dormant_selection` and the finding L12-3.
