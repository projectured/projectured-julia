# Layer 14 — intent (`source/kernel/intent/`)

Commit 15b40434, 2026-09-27. Seal state: none sealed (0 of 2).

## Verdict

The intent layer is small and sound: it holds the carrier that flows back through the readers, two reader payloads, and the operation that carries a list of intents home. It has no state and no logic fault in the carrier itself. `CollectedIntentsOperation` declares no inverse, so a history reads it as an operation with no way back, and its name is not a verb-first phrase. The layer has no test folder, and `follow_intent_route` has no test at all. `with_intent_labels` has no caller, and several docstrings name higher layers or state old facts.

## Shape

- Purpose: the unit that flows back through the readers. `Intent` holds the gesture, the operation so far, two labels and a route. `ClaimedGesture` and `CollectIntents` are reader payloads. `CollectedIntentsOperation` carries the answer to `CollectIntents` home, and its `reroot_operation` method reroots each operation that it carries.
- Files:

| file | lines | seal | what it holds |
| --- | ---: | --- | --- |
| [IntentModule.jl](../../../source/kernel/intent/IntentModule.jl) | 23 | ⬜ | module docstring, header, one include |
| [Intent.jl](../../../source/kernel/intent/Intent.jl) | 167 | ⬜ | `Intent` and its constructors, `follow_intent_route`, `with_intent_labels`, `ClaimedGesture`, `CollectIntents`, `CollectedIntentsOperation`, `merge_collected_intents`, the `reroot_operation` method |

- Imports: `ReferenceModule` and `OperationModule` as bare `using`, and `import ..OperationModule: reroot_operation`, which the file extends. Imported by: `GestureBindingModule`, `ProjectionModule`, `EditorModule` and `PlaybackModule` in the kernel; 21 source files outside the kernel; omnet-julia and inet-julia use `Intent`.
- Public surface: 7 exported names. `Intent` is the most used (43 source files, 36 test files, omnet-julia and inet-julia). `ClaimedGesture` has one reader method, in [ProjectionTemplate.jl:1329](../../../source/kernel/projection/ProjectionTemplate.jl#L1329). `with_intent_labels` has no caller in projectured-julia, omnet-julia or inet-julia.
- State: none. `Intent` is an immutable struct.
- Tests: there is no `test/kernel/intent/`. The reroot of `CollectedIntentsOperation` and `merge_collected_intents` have tests in [RerootingTest.jl:78](../../../test/kernel/operation/RerootingTest.jl#L78), in the folder of the operation layer. [GestureBindingTest.jl:233](../../../test/kernel/binding/GestureBindingTest.jl#L233) tests `CollectIntents` through the bindings. No test file names `follow_intent_route`, `ClaimedGesture` or `with_intent_labels`.

## Summary

| Category | High | Medium | Low |
| --- | ---: | ---: | ---: |
| Architecture | 0 | 1 | 1 |
| Shape | 0 | 0 | 3 |
| Naming | 0 | 1 | 0 |
| Documentation | 0 | 0 | 1 |
| Tests | 0 | 1 | 0 |

## Findings

### L14-1 `CollectedIntentsOperation` changes no document, but it declares no way back

- Category: Architecture · Severity: Medium · Confidence: Confirmed
- Where: [Intent.jl:141](../../../source/kernel/intent/Intent.jl#L141) ⬜
- Evidence: the type has no `make_inverse_operation` method, so the default answers `nothing` ([Inversion.jl:18](../../../source/kernel/operation/Inversion.jl#L18)). The contract says that `nothing` means "this operation has no way back", and that an operation that changes no document answers `DoNothingOperation()` ([OperationInterface.jl:199](../../../source/kernel/operation/OperationInterface.jl#L199)). Its own docstring says "Applying it does nothing"; it has no `evaluate_operation` method and reaches the catch-all. If one reaches a history, the history records a barrier for a no-op. No path to a history was seen today, because the answer to `CollectIntents` goes to a caller, not to the editor loop.
- Rule: PAR-INVERTIBLE-OPERATIONS ("or the operation must be explicitly one an undo log skips").
- Fix: add `make_inverse_operation(document, ::CollectedIntentsOperation) = DoNothingOperation()` and import the name in IntentModule.jl.
- Reach: Intent.jl, IntentModule.jl.

### L14-2 `CollectedIntentsOperation` is not a verb-first phrase

- Category: Naming · Severity: Medium · Confidence: Confirmed
- Where: [Intent.jl:141](../../../source/kernel/intent/Intent.jl#L141) ⬜
- Evidence: "Collected" is a past participle. naming-rules.md: "Operations are verb-first phrases with the `Operation` suffix … The one structural exception is `CompoundOperation`." The docstring models the type on `CompoundOperation` but does not claim the exception. Planned: plan/pending/naming-rule-violations.md (line 426, marked "unsure").
- Rule: naming-rules.md, "Types"; PAR-NAMING-LAW.
- Fix: rename it (for example `CarryIntentsOperation`) with `workspace/bin/julia-rename.jl`, or name it as a second exception in naming-rules.md.
- Reach: Intent.jl, IntentModule.jl; 8 source files; 2 test files; ProjectionDefaults.jl; operation.md and system-anatomy.md.

### L14-3 The layer has no test folder, and `follow_intent_route` has no test

- Category: Tests · Severity: Medium · Confidence: Confirmed
- Where: [Intent.jl:62](../../../source/kernel/intent/Intent.jl#L62) ⬜; `test/kernel/` has no `intent/` folder.
- Evidence: `follow_intent_route` decides which child is on the route of an operation that code gives at a place. Six source files call it (FileToContent.jl, UndoBufferToAny.jl, ClipboardSliceToAny.jl, ClipboardCollectionToAny.jl, WidgetToGraphics.jl, ScreenToScreen.jl). No test file names it, so only the higher suites exercise it. `ClaimedGesture` and the four constructors of `Intent` have no direct test. The tests of `CollectedIntentsOperation` and `merge_collected_intents` sit in the test folder of the operation layer.
- Rule: PAR-NEW-CODE-SHIPS-TESTS.
- Fix: add `test/kernel/intent/IntentTest.jl`. Test a route that starts with the steps, a route that does not, a route of `nothing`, the labels that each constructor keeps, and the merge. Move the two testsets from RerootingTest.jl there, and register the file in KernelSuite.jl.
- Reach: test files only.

### L14-4 The kernel's default reader bridge drops the labels that the carrier says a reader must keep

- Category: Architecture · Severity: Low · Confidence: Confirmed (no reader reads the labels after a reroot today)
- Where: [Intent.jl:37](../../../source/kernel/intent/Intent.jl#L37) ⬜; [ProjectionDefaults.jl:210](../../../source/kernel/projection/ProjectionDefaults.jl#L210) ⬜
- Evidence: the docstring of `Intent` says "A reader that reroots an operation must preserve the labels." The default bridge of the projection layer rebuilds the carrier as `Intent(change.gesture, op)` (line 213). That drops `description`, `domain` and `route` at each projection that has no reader of its own. The gesture log reads the labels from the carrier that it gets, before any reroot ([GestureLogRecording.jl:63](../../../source/gesturelog/GestureLogRecording.jl#L63)), so no output is wrong today.
- Rule: the contract of `Intent`.
- Fix: rebuild the carrier with `Intent(change.gesture, op, change.description, change.domain)`.
- Reach: ProjectionDefaults.jl.

### L14-5 `with_intent_labels` has no caller

- Category: Shape · Severity: Low · Confidence: Confirmed
- Where: [Intent.jl:77](../../../source/kernel/intent/Intent.jl#L77) ⬜
- Evidence: a search of source/, test/, example/, tool/, package/, omnet-julia and inet-julia finds only the definition and the export. Its docstring calls it "The one place labels are attached", but the code that attaches labels calls the four-argument constructor ([GestureBinding.jl:186](../../../source/kernel/binding/GestureBinding.jl#L186)).
- Rule: code-quality-rules.md (dead code); architecture-rules.md ("No orphans shape the structure").
- Fix: delete it and its export, or make the readers use it.
- Reach: Intent.jl, IntentModule.jl.

### L14-6 `IntentModule.jl` heads a single fragment

- Category: Shape · Severity: Low · Confidence: Confirmed
- Where: [IntentModule.jl:21](../../../source/kernel/intent/IntentModule.jl#L21) ⬜
- Evidence: [system-anatomy.md:139](../../../documentation/design/system-anatomy.md#L139) says "A module with one fragment keeps its code there, because a head listing one include gives a reader nothing. All 15 head files of the kernel carry two or more includes." IntentModule.jl includes only Intent.jl. ClockModule.jl, GestureRecognizerModule.jl and PlaybackModule.jl also include one file, so the sentence in system-anatomy.md is false for four kernel modules.
- Rule: system-anatomy.md; code-quality-rules.md §1.
- Fix: move the content of Intent.jl into IntentModule.jl, or correct the rule text if the owner keeps the two-file form.
- Reach: IntentModule.jl, Intent.jl, SEALING.md (the inventory lists both files); system-anatomy.md.

### L14-7 The module header and the source form do not follow the code-quality rules

- Category: Shape · Severity: Low · Confidence: Confirmed
- Where: [IntentModule.jl:14](../../../source/kernel/intent/IntentModule.jl#L14) ⬜
- Evidence: the `using` lines are not sorted (`ReferenceModule` before `OperationModule`). The export block has one finding in plan/pending/export-block-rule.md (planned). The fragment header of Intent.jl is 126 characters long, and line 78 is 95.
- Rule: code-quality-rules.md §1 and §5.
- Fix: sort the `using` lines; wrap the two lines.
- Reach: IntentModule.jl, Intent.jl.

### L14-8 Several docstrings name higher layers or state facts that are no longer true

- Category: Documentation · Severity: Low · Confidence: Confirmed
- Where: [IntentModule.jl:9](../../../source/kernel/intent/IntentModule.jl#L9), [Intent.jl:4](../../../source/kernel/intent/Intent.jl#L4), [Intent.jl:86](../../../source/kernel/intent/Intent.jl#L86), [Intent.jl:119](../../../source/kernel/intent/Intent.jl#L119) ⬜
- Evidence:
  - IntentModule.jl says "They sit in the operation layer". They are in layer 14, above it. The same sentence names "the binding layer above" as the reason (PAR-NO-CONSUMER-DOCS).
  - The docstring of `ClaimedGesture` names JSON, XML, `fire_gesture_bindings`, "the generic reader bridge" and `ProjectionModule`, all above this layer (PAR-NO-CONSUMER-DOCS). It also says "(now) a claimed event", a word about the past (line 101).
  - The docstring of `CollectIntents` says "`ClaimedGesture` is the precedent". PAR-NO-NEW-SYNTHETIC-EVENT says: "A synthetic event or a reader payload that exists now is not a precedent for a new one."
  - The signature line of `Intent` shows four arguments and omits `route`. Line 11 calls `WindowInput` a thing of "the screen layer"; it is in the event layer of the kernel, and the screen is a package (PAR-DIVISION-VOCABULARY).
  - The layer has no design document of its own. [projection-system.md:160](../../../documentation/package/kernel/projection-system.md#L160) describes `Intent`, links IntentModule.jl instead of Intent.jl, shows a struct of two fields, and calls `route` "a fifth field".
- Rule: PAR-NO-CONSUMER-DOCS, PAR-NO-NEW-SYNTHETIC-EVENT, PAR-DIVISION-VOCABULARY, PAR-HONEST-DOCS; CLAUDE.md "A comment says what is, never what was".
- Fix: state the layer in IntentModule.jl without the consumer; describe `ClaimedGesture` by the concepts only; delete "is the precedent" and "(now)"; show the five fields in the docstring and in projection-system.md.
- Reach: IntentModule.jl, Intent.jl; projection-system.md.

## Accepted before, not raised again

- The `route` field of `Intent` is the owner's decision of 2026-09-23 (plan/done/an-operation-enters-at-any-reference.md, §3 "The route is a separate field of `Intent`").
- `ClaimedGesture` (2026-07-14) and `CollectIntents` (2026-08-08) are older than PAR-NO-NEW-SYNTHETIC-EVENT (2026-09-23), and the rule keeps a payload that exists. Only the "precedent" sentence is raised (L14-8).
- `Intent.gesture` and `Intent.operation` hold `Any`: architecture-rules.md names `Intent` as an opaque payload that a lower layer may carry.

## Checked and clean

- PAR-READER-IS-PURE: the layer holds no reader; `Intent` is immutable and each helper returns a new value.
- PAR-NO-NEW-SYNTHETIC-EVENT: no payload type came after the rule.
- PAR-REGISTER-NEW-OPERATION: `CollectedIntentsOperation` has a `reroot_operation` method here and a branch in the default reader ([ProjectionDefaults.jl:161](../../../source/kernel/projection/ProjectionDefaults.jl#L161)).
- Description: `describe_operation` answers "CollectedIntents" through its fallback.
- PAR-QUALIFIED-EXTENSION: the module imports only `reroot_operation`, and it extends it.
- PAR-PER-EDITOR-STATE: no module-level mutable value.
- PAR-MODULE-DOCSTRING: the module file opens with a docstring and the fragment with a header line.
- Naming of the functions: `follow_intent_route`, `merge_collected_intents` and `with_intent_labels` start with a verb.
