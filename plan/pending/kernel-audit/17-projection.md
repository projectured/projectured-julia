# Layer 17 — projection (`source/kernel/projection/`)

Commit 15b40434, 2026-09-27. Seal state: none sealed (0 of 9).

## Verdict

The layer holds the four-function contract, its defaults, the printer context, the
introduced reference step and the template engine. The engine is 1423 of 2649 lines
and carries most findings. The most important finding is L17-1: a template child list
that a builder writes as a thunk prints once and then stays fixed. 33 template rules
in six files of four packages do not follow an edit of an optional field, and a write
of `nothing` can make the print throw. The template mappers read a range step by its start only
(L17-2), ignore the route of an operation from code (L17-3), rebuild every child of a
mixed or sectioned node (L17-5) and name the Syntax field `value` (L17-6). The
contract file is incomplete (L17-10), a second recursive printer interface has no
caller (L17-9), private names cross into another package and another repository
(L17-8), and the kernel tests cover only the ranges of `PrinterContext` (L17-12).

## Shape

- Purpose: the projection contract (`Projection`, `print_document`, `read_intent`,
  `map_reference_forward`, `map_reference_backward`), the fallback of each generic,
  the context a printer carries down, the reference step for projection-introduced
  output, `@projection`, the gesture table of a projection, and `@projection_template`
  with its builder-and-walk engine.
- Files:

| file | lines | seal | what it holds |
| --- | ---: | --- | --- |
| `ProjectionModule.jl` | 107 | ⬜ | module head: docstring, 11 `using`, 8 export statements, 8 includes |
| `ChildrenContainer.jl` | 5 | ⬜ | a fragment header and no code |
| `PrinterContext.jl` | 284 | ⬜ | `PrinterContext`, the size-range helpers, `make_child_context`, `with_clock`, `with_property` / `get_property` |
| `ProjectionReferenceStep.jl` | 138 | ⬜ | `ProjectionReferenceStep`, the introduced-caret helpers, the `.proj` DSL registration |
| `ProjectionInterface.jl` | 379 | ⬜ | `Projection` and nine bodiless generics (the contract file) |
| `ProjectionDefaults.jl` | 229 | ⬜ | default mappers, default 3-argument reader, 4-argument bridge, `read_routed_intent`, `print_child`, the pure fallbacks |
| `ProjectionMacro.jl` | 47 | ⬜ | `@projection` |
| `GestureBindings.jl` | 37 | ⬜ | default `get_projection_gesture_bindings`, `read_projection_gesture` |
| `ProjectionTemplate.jl` | 1423 | ⬜ | `@projection_template`, the five markers, the walk, `RuleIoMap`, seven wiring kinds, the generic mappers and readers |

- Imports: `using` of CellModule, CellStructModule, ClockModule, DocumentModule,
  EventModule, GestureBindingModule, IntentModule, IoMapModule, OperationModule,
  ReferenceModule, SelectionModule (layers 3 to 16). No `import`: the layer extends the
  reference seams by qualification (`ReferenceModule.get_reference_step_kind`, …) and
  `Base.show` / `Base.:(==)`. Imported by: the kernel editor (22) and playback (23)
  layers, 52 files in `source/` of this repository, and 65 files in omnet-julia and
  inet-julia.
- Public surface: 37 exported names. No caller anywhere: `print_pure`,
  `print_child_pure`. `print_document_pure` has methods in three combinators and no
  caller (L17-9). `with_clock` has only the kernel editor and one test.
  `print_template_rule`, `read_template_intent` and `make_template_builder` have one
  user, `source/rst/RstToSyntax.jl`. Six names that the module does not export are
  imported from outside: `AtomicWiring` and the five marker words (L17-8).
- State: no module-level mutable state (two `const`s: a tuple and a type union). Per
  print, `PrinterContext.properties` is one `Dict` shared by reference down the tree;
  the docstring says so, and no code mutates it in place. The template engine keeps
  its tables per invocation, in `RuleIoMap` and in cell closures. The default clock of
  `PrinterContext()` is a new `Clock` that nothing advances, not the wall clock. No
  state is shared between tasks.
- The split from layer 15 (binding): right. The default of
  `get_projection_gesture_bindings` takes `::Projection`, and `read_projection_gesture`
  reads `iomap.input`; both concepts sit above layer 15. The problems are that the seam
  is not in the contract file (L17-10) and that the file name is one letter from
  `binding/GestureBinding.jl` (L17-21).
- Tests: `test/kernel/projection/PrinterContextTest.jl` (1 file, 6 testsets, 22
  assertions; it passes in the baseline log). The engine has two small testsets in
  `test/substrate/projection/ProjectionTemplateTest.jl` and indirect coverage through
  the domain suites; `test/projectured/editor/RecursionContractTest.jl` checks the
  contract from outside. What no test covers is in L17-12.

## Summary

| category | High | Medium | Low |
| --- | ---: | ---: | ---: |
| Correctness | 1 | 3 | 2 |
| Architecture | 0 | 6 | 1 |
| Shape | 0 | 0 | 4 |
| State | 0 | 1 | 0 |
| Types/performance | 0 | 0 | 1 |
| Naming | 0 | 0 | 1 |
| Documentation | 0 | 0 | 6 |
| Tests | 0 | 1 | 0 |

## Findings

### L17-1 A thunk child list of a template prints once and then stays fixed

- Category: Correctness · Severity: High · Confidence: Confirmed by a run
- Checked by the lead on 2026-09-27: A run: `x = 1:2:5` printed through `JuliaToSyntax`, `SyntaxToText` and `TextToString`, then `r.step = nothing`. The same output then throws `TypeDispatchingProjection: no projection registered for type Nothing`, and a new print gives `x = 1:5`. So the throw is confirmed too.
- Where: [ProjectionTemplate.jl:303](../../../source/kernel/projection/ProjectionTemplate.jl#L303) ⬜,
  [ProjectionTemplate.jl:248](../../../source/kernel/projection/ProjectionTemplate.jl#L248) ⬜,
  [ProjectionTemplate.jl:540](../../../source/kernel/projection/ProjectionTemplate.jl#L540) ⬜
- Evidence:
  - The engine takes the conditional path (the "F2" reactive child list) only for "a
    field holding a bare `Function`" (`_find_conditional`, lines 299-309).
  - `SyntaxConcatenation(computation::Function) = SyntaxConcatenation(Cell(Computation(computation)), nothing)`
    (`source/syntax/SyntaxDocument.jl:300`). The field holds a computed cell, so
    `getfield(out, fname)[]` answers the marker `Vector`, not a `Function`.
  - `_dispatch_print` then goes to `_fixed_print` (lines 248-252). `_fixed_print` reads
    the vector once (line 539) and writes
    `setproperty!(out, children_field, make_children_container(output_cells))` (line 540).
  - A write to a `ReactiveCell` sets `c.computation = nothing`
    (`source/kernel/cell/ReactiveCell.jl:208-211`). The thunk never runs again, and the
    `FixedNodeWiring` keeps the slots of the first print.
  - 33 template rules write their child list this way: 5 in
    `source/julia/JuliaToSyntax.jl` (`JuliaRange` step, `JuliaReturn` value, `JuliaTry`
    catch and finally), 12 in `source/math/MathToSyntax.jl`, 5 in
    `source/fsm/FsmToSyntax.jl`, 1 in `source/fsm/FsmDiagramToGraph.jl`, 6 in
    `source/process/ProcessToSyntax.jl`, 4 in `source/process/ProcessDiagramToGraph.jl`.
    `_conditional_print`, `ConditionalNodeWiring` and their mappers have no reachable
    caller.
  - Commit 758585a2 (2026-08-03) made `SyntaxConcatenation(::Function)` a computed cell.
    `plan/pending/simplest-syntax-document.md:715-721` records that the thunk "must be
    stored as it is" for the engine to see it.
  - Scenario: print a `JuliaRange` that has a step, then write `nothing` to `.step`
    through the same IoMap. The static `project(:step)` slot re-prints `nothing`, and
    `TypeDispatchingProjection` has no entry for `Nothing` in `JuliaToSyntax`, so it
    throws "no projection registered for type Nothing". The other direction: write a
    document to `.default` of a printed `FsmVariable` whose `default` is `nothing`; the
    `= …` part never shows. `ProcessDecision(nothing)` keeps `<condition>` after a
    condition arrives.
  - No test sees it: `test/process/projection/ProcessToSyntaxTest.jl` "reactive" calls
    `print_document` again for each check, so each check is a fresh print.
  - The rule of `_find_conditional` also conflicts with PAR-NO-NESTED-CELL: a
    `Function` is an ordinary field value, so an output node with a callback field
    would have that callback called as a child-list thunk.
- Rule: bug; PAR-REACTIVE-OUTPUT-STRUCTURE, PAR-STABLE-IOMAP-IDENTITY.
- Fix: in `_dispatch_print`, recognise a children field whose cell holds a computation
  (`is_computed_cell`) and give that computation to `_conditional_print` as the thunk;
  drop the "any `Function`" test. Add a test that writes an optional field of a printed
  node and reads the same IoMap.
- Reach: `ProjectionTemplate.jl`; a test in the substrate test package. No sealed
  file. omnet-julia and inet-julia use no thunk child list.

### L17-2 The template mappers read a range step by its start only

- Category: Correctness · Severity: Medium · Confidence: Confirmed for the code;
  Suspected for the impact (no producer of such a path through a template was found).
- Where: [ProjectionTemplate.jl:834](../../../source/kernel/projection/ProjectionTemplate.jl#L834) ⬜,
  [ProjectionTemplate.jl:854](../../../source/kernel/projection/ProjectionTemplate.jl#L854) ⬜,
  [ProjectionTemplate.jl:916](../../../source/kernel/projection/ProjectionTemplate.jl#L916) ⬜,
  [ProjectionTemplate.jl:1194](../../../source/kernel/projection/ProjectionTemplate.jl#L1194) ⬜
- Evidence: every collection step in the engine checks `after.head isa RangeReferenceStep`
  and then takes `after.head.start + 1` (lines 834, 854, 916, 1004, 1026, 1089, 1123,
  1143, 1152, 1194). None checks `is_element_reference_step`, which the `[i]` pattern of
  `@reference_case` requires (`source/kernel/reference/ReferenceCase.jl:699`). So a
  boundary `.elements{2}` maps to `.children[3]`, a range `.elements[2:4]` maps to
  `.children[2]`, and a boundary `.children{0}` maps back to `.elements[1]`. A caret
  between two elements also focuses the next element in `_focused_child`, so a key
  there goes into that element. Hand-written mappers keep the range
  (`source/filesystem/FileSystemToSyntax.jl:141`, `source/markdown/MarkdownToSyntax.jl:401`).
- Rule: PAR-ONE-BASED-INDEXING ("distinguish elements from boundaries").
- Fix: accept only an element step at each collection step, and answer `nothing` for a
  boundary or a range (or map the range as a range).
- Reach: `ProjectionTemplate.jl`.

### L17-3 The reader bridge and the template reader drop the route and the labels of an intent

- Category: Correctness · Severity: Medium · Confidence: Confirmed for the code;
  Suspected for the impact (needs a run of `insert_elements!` into a nested XML element).
- Where: [ProjectionDefaults.jl:213](../../../source/kernel/projection/ProjectionDefaults.jl#L213) ⬜,
  [ProjectionTemplate.jl:1364](../../../source/kernel/projection/ProjectionTemplate.jl#L1364) ⬜
- Evidence: the bridge answers `Intent(change.gesture, op)` and `read_template_intent`
  answers `Intent(change.gesture, …)` (lines 1368, 1371). Both drop `description`,
  `domain` and `route`, although `Intent.jl` says "A reader that reroots an operation
  must preserve the labels". Neither reads `change.route`; each reads
  `change.operation` as an operation of its own output domain. For a routed change the
  operation is relative to a place below the input. `find_rooted_operation`
  (`source/kernel/editor/DocumentEdits.jl:20-33`) tries the deepest place first, and the
  chain (`source/projection/higherorder/Chaining.jl:167-187`) hands the change with a
  non-empty route to the template of the stage root. Most template mappers answer
  `nothing`, and the loop moves one place up. When the input field and the output field
  have the same name, as `children` in XML, `_slots_backward` accepts the place-relative
  path and can answer an introduced reference. `find_rooted_operation` then takes a
  wrong operation.
- Rule: bug; the route contract in `documentation/package/kernel/editor.md` ("An
  operation from a place, not a gesture").
- Fix: keep the labels (the 5-argument `Intent` constructor), and answer
  `Intent(change.gesture, nothing)` for a route that the reader does not follow; a node
  wiring can follow it through `_focused_child`.
- Reach: `ProjectionDefaults.jl`, `ProjectionTemplate.jl`.

### L17-4 ProjectionReferenceStep defines == without hash

- Category: Correctness · Severity: Medium · Confidence: Confirmed (the contract of
  `hash` is broken); no failing site found.
- Where: [ProjectionReferenceStep.jl:96](../../../source/kernel/projection/ProjectionReferenceStep.jl#L96) ⬜
- Evidence: `Base.:(==)(a::ProjectionReferenceStep, b::ProjectionReferenceStep) = a.projection === b.projection && a.output_path == b.output_path`,
  and no `Base.hash` method. The step is a `@cell_struct`, which "hashes by identity
  unless it says otherwise" (`source/kernel/reference/ReferencePath.jl:138-141`).
  `hash(::ConcreteReference)` mixes the hash of its head (line 146-147). Two introduced
  carets that `make_introduced_reference` builds separately are `==` and hash
  differently, so a `Set` or a `Dict` keyed by references misses them.
- Rule: bug (Julia requires `a == b` to imply `hash(a) == hash(b)`).
- Fix: `Base.hash(s::ProjectionReferenceStep, h::UInt) = hash(s.output_path, hash(objectid(s.projection), hash(:ProjectionReferenceStep, h)))`.
- Reach: `ProjectionReferenceStep.jl`.

### L17-5 Mixed and sectioned template nodes rebuild every child IoMap on a change

- Category: Architecture · Severity: Medium · Confidence: Confirmed for the rebuild;
  Suspected for the second consequence below.
- Where: [ProjectionTemplate.jl:616](../../../source/kernel/projection/ProjectionTemplate.jl#L616) ⬜,
  [ProjectionTemplate.jl:689](../../../source/kernel/projection/ProjectionTemplate.jl#L689) ⬜,
  [ProjectionTemplate.jl:562](../../../source/kernel/projection/ProjectionTemplate.jl#L562) ⬜
- Evidence: `_mixed_print` wires `coll_iomaps = Cell(@computation([print_child(recursion, x, …) for (i, x) in enumerate(…)]))`,
  and `_sections_print` prints every entry of every section in one computation.
  `_conditional_print` re-walks all markers and makes new reconcile cells on each run.
  `_node_print` uses `reconcile_child_iomaps` (line 441); these three do not. omnet-julia
  uses mixed nodes (`source/legacy/ini/presentation/IniToSyntax.jl:117-127`) and
  sections (`source/legacy/ned/presentation/NedToSyntax.jl:457-548`). An insert of one
  INI entry rebuilds the IoMap and the output node of every entry of the section. Each
  child print runs inside that computation and reads output cells of the child, so a
  later write of such a cell (a collapse, for example) also rebuilds every child.
- Rule: PAR-STABLE-IOMAP-IDENTITY.
- Fix: use `reconcile_child_iomaps` for the spliced collection and for the entries of
  each section.
- Reach: `ProjectionTemplate.jl`; the omnet-julia INI and NED projections gain from it
  with no change.

### L17-6 The template engine names the Syntax field value

- Category: Architecture · Severity: Medium · Confidence: Confirmed.
- Where: [ProjectionTemplate.jl:361](../../../source/kernel/projection/ProjectionTemplate.jl#L361) ⬜,
  [ProjectionTemplate.jl:416](../../../source/kernel/projection/ProjectionTemplate.jl#L416) ⬜,
  [ProjectionTemplate.jl:891](../../../source/kernel/projection/ProjectionTemplate.jl#L891) ⬜
- Evidence: `_key_leaf_sel`, `_slots_forward`, `_slots_backward`, the mixed mappers and
  the inline mappers write `FieldReferenceStep("value")` or test `.name == "value"`
  (lines 361, 891, 924, 993, 1035, 1076, 1094). `_scan_atomic!` records the real output
  field in `value_field` (line 478), but `KeySlot` drops it (lines 529, 610) and
  `InlineWiring` never records it. The leaf shortcut `wiring.bound_field === :value ?
  getfield(doc, :selection)` (line 416) tests the input field name and assumes the
  output field is also `value`. The comment at lines 466-469 says "no output-domain
  field names are referenced", and lines 403-404 name the render stage's
  `.value`/`.open`/`.close`. A builder that puts `bound(:x, …)` in another field of a
  child leaf gets carets at `.children[k].value`, a field the leaf does not have.
- Rule: PAR-FRAMEWORKS-SINK (a lower layer names a higher concept only as an opaque
  payload); PAR-HIGHER-ORDER-IS-DOMAIN-FREE.
- Fix: carry `value_field` in `KeySlot` and `InlineWiring` and use it; gate the shortcut
  on `wiring.value_field === :value`.
- Reach: `ProjectionTemplate.jl`.

### L17-7 The template gesture descent calls the obsolete 3-argument reader of the child

- Category: Architecture · Severity: Medium · Confidence: Confirmed.
- Where: [ProjectionTemplate.jl:1308](../../../source/kernel/projection/ProjectionTemplate.jl#L1308) ⬜
- Evidence: `child_op = read_intent(child.projection, child, evt)`. PAR-PREFER-REFERENCE-RETARGET
  says "Do not write the obsolete 3-arg shim in new code". A child projection that
  obeys and has only a 4-argument reader falls to the default
  `read_intent(::Projection, iomap, operation)`, which answers `read_gesture(input, evt)`
  and skips the reader of the child. Today it works only because every higher-order
  projection keeps a 3-argument shim that calls its 4-argument reader with
  `recursion = nothing` (for example `source/projection/higherorder/Nesting.jl:64`).
  `ScreenToScreen` has no shim (`source/screen/ScreenToScreen.jl:166`, `:197`).
- Rule: PAR-RECURSION-CONTRACT (the child gets its own version of the same function);
  PAR-PREFER-REFERENCE-RETARGET.
- Fix: descend with the 4-argument reader, `read_intent(child.projection, recursion, Intent(evt), child)`,
  and let the 4-argument template entry pass `recursion` down.
- Reach: `ProjectionTemplate.jl`; `source/projection/ReaderDefaults.jl` (its
  disambiguations exist for the 3-argument path).

### L17-8 Private names of the layer cross module and repository boundaries

- Category: Architecture · Severity: Medium · Confidence: Confirmed.
- Where: [ProjectionModule.jl:86](../../../source/kernel/projection/ProjectionModule.jl#L86) ⬜,
  [ProjectionTemplate.jl:60](../../../source/kernel/projection/ProjectionTemplate.jl#L60) ⬜,
  [ProjectionTemplate.jl:93](../../../source/kernel/projection/ProjectionTemplate.jl#L93) ⬜
- Evidence: the export list names none of `AtomicWiring`, `bound`, `project`,
  `collection`, `tokens`, `sections`. Importers:
  `source/projection/ReaderDefaults.jl:19` (`AtomicWiring`); omnet-julia
  `source/legacy/ned/presentation/NedToSyntax.jl:29` (`bound, collection, sections, tokens`),
  `source/legacy/ini/presentation/IniToSyntax.jl:14`,
  `source/legacy/testfile/presentation/TestToSyntax.jl:21`; and
  `test/substrate/projection/ProjectionTemplateTest.jl:56` (`bound`).
  `make_template_builder` rewrites the marker words only inside a builder body, so a
  helper outside it (`NedToSyntax.jl:97`, `_name_token(…) = SyntaxLeaf(bound(…))`) must
  name the private function. The layering guard checks kernel imports only, so nothing
  reports it. `documentation/rule/naming-rules.md:384-385` still says the words "are
  exported as a set".
- Rule: PAR-MODULE-BOUNDARY-IS-API.
- Fix: replace the `AtomicWiring` test in `ReaderDefaults.jl` with an exported predicate
  (for example `is_opaque_template_leaf(iomap)`). For the marker words the owner
  decides: export them again, or let a helper take its markers from the builder.
- Reach: `ProjectionModule.jl`, `ProjectionTemplate.jl`, `source/projection/ReaderDefaults.jl`,
  three omnet-julia files, one test, `naming-rules.md`.

### L17-9 The pure printer pair is a second recursive interface with no caller

- Category: Architecture · Severity: Medium · Confidence: Confirmed.
- Where: [ProjectionInterface.jl:136](../../../source/kernel/projection/ProjectionInterface.jl#L136) ⬜,
  [ProjectionDefaults.jl:18](../../../source/kernel/projection/ProjectionDefaults.jl#L18) ⬜,
  [ProjectionDefaults.jl:28](../../../source/kernel/projection/ProjectionDefaults.jl#L28) ⬜
- Evidence: the contract declares `print_document_pure` and `print_child_pure`, and the
  defaults add `print_pure` and a snapshot fallback. Nothing calls `print_pure` or
  `print_child_pure`. `print_document_pure` is called only from its own methods in
  `Chaining.jl:86-89`, `Recursive.jl:37-38` and `TypeDispatching.jl:48-51`.
  `source/pdf/Pdf.jl` and `write_image` do not use it, although the docstring (lines
  141-142) says "for batch/export use (write_image / write_pdf / text serialization)".
  `print_child_pure` is a fifth recursive function; the universal fallback is why no
  composition breaks.
- Rule: PAR-FOUR-FUNCTIONS, PAR-RECURSION-CONTRACT; code with no user.
- Fix: delete the pure pair and `print_pure` until a caller exists, or record the
  exception in `architecture-invariants.md`, give it a caller and a test.
- Reach: `ProjectionInterface.jl`, `ProjectionDefaults.jl`, `ProjectionModule.jl`, the
  three combinators in `source/projection/higherorder/`, `test/suite/arguments.jl:37`,
  `projection-system.md`.

### L17-10 The projection gesture seam is outside the contract file

- Category: Architecture · Severity: Medium · Confidence: Confirmed.
- Where: [GestureBindings.jl:15](../../../source/kernel/projection/GestureBindings.jl#L15) ⬜,
  [ProjectionInterface.jl:362](../../../source/kernel/projection/ProjectionInterface.jl#L362) ⬜
- Evidence: `get_projection_gesture_bindings(::Projection, iomap) = GestureBinding[]`
  creates the generic with a default method. Seven files in six packages extend it
  (undo, projection, versioning, syntax, clipboard, conversation). The contract file
  declares nine generics and not this one. Commit 4c067207 ("every open seam lives in
  its layer's contract files") moved the two children-container seams of this layer
  and left this one. The file header and the fragment table call the file "the open
  generics", but it holds a default and a function body.
- Rule: PAR-INTERFACE-DECLARES-ONLY ("one file gives a reader the entire contract of a
  layer"); PAR-PROJECTION-PLACEMENT.
- Fix: declare `function get_projection_gesture_bindings end` with its docstring in
  `ProjectionInterface.jl`; keep the default and `read_projection_gesture` in the
  fragment.
- Reach: `ProjectionInterface.jl`, `GestureBindings.jl`, `ProjectionModule.jl`
  (docstring and export statement order).

### L17-11 A printer that makes a new PrinterContext drops the per-editor state of the context

- Category: State · Severity: Medium · Confidence: Confirmed that the state is dropped;
  Suspected for the fault consequence (needs a run with a fault in a log panel).
- Where: [PrinterContext.jl:57](../../../source/kernel/projection/PrinterContext.jl#L57) ⬜
- Evidence: `PrinterContext()` makes an empty reference, free ranges, an empty
  `properties` Dict and a new `Clock` that nothing advances. The editor puts its clock,
  `:root`, `:fault_store` and `:fault_policy` into the root context
  (`source/kernel/editor/FaultBarriers.jl:181`). Four printers print a subtree with a
  new context: `source/fault/FaultLogOverlay.jl:119`,
  `source/gesturelog/GestureLogOverlay.jl:106`,
  `source/inspector/SelectionInspectorToText.jl:42`,
  `source/inspector/ReferenceInspectorToText.jl:62`. The two overlays want only free
  ranges ("must not inherit the layout space"). In those subtrees an animation stays
  at time 0, and a barrier (`source/fault/Catching.jl:115-116`) finds no store and uses
  the strict policy, so it records nothing and catches nothing.
- Rule: PAR-PER-EDITOR-STATE (the clock and the fault store that the context carries
  are per editor).
- Fix: derive from the given context, `with_exact_size(ctx; width = nothing, height = nothing)`;
  state in the `PrinterContext` docstring that a printer derives each context from the
  one it receives.
- Reach: `PrinterContext.jl` (docstring); `source/fault/`, `source/gesturelog/`,
  `source/inspector/`.

### L17-12 The kernel tests cover only the ranges of PrinterContext

- Category: Tests · Severity: Medium · Confidence: Confirmed.
- Where: `test/kernel/projection/PrinterContextTest.jl`,
  `test/substrate/projection/ProjectionTemplateTest.jl`
- Evidence: the kernel suite has one file with 22 assertions on exact, bounded and free
  ranges. No kernel test covers `with_inner_size`, `with_size_range`, `get_property`,
  the typed `make_child_context(ctx, doc, steps…)`, the default mappers, the branches
  of the default reader, the bridge, `read_routed_intent`, `ProjectionReferenceStep`
  (`==`, `show`, the `.proj` DSL), `@projection` or `read_projection_gesture`. The
  engine has two substrate testsets (import hygiene, fixed children). No test in this
  repository exercises `tokens`, `sections`, mixed nodes or the conditional path, and
  no test writes a field of a printed template node and reads the same IoMap (L17-1).
- Rule: PAR-NEW-CODE-SHIPS-TESTS.
- Fix: kernel tests with fixture documents for the defaults, the bridge, the step and
  the macro; substrate tests for each wiring kind with an edit through the same IoMap
  (the kernel has no children container, so the engine tests need the substrate).
- Reach: `test/kernel/projection/`, `test/substrate/projection/`.

### L17-13 An introduced caret has two typed forms

- Category: Correctness · Severity: Low · Confidence: Confirmed that the forms differ;
  Suspected for the impact.
- Where: [ProjectionDefaults.jl:93](../../../source/kernel/projection/ProjectionDefaults.jl#L93) ⬜,
  [ProjectionReferenceStep.jl:50](../../../source/kernel/projection/ProjectionReferenceStep.jl#L50) ⬜
- Evidence: the default backward mapper builds `@reference(iomap.input, proj(projection, ^(reference)))`.
  The annotation evaluates the step to its `output_path`, so the terminal records a
  `Reference` type. `make_introduced_reference` records `Position` and says "Build
  every introduced caret through this, never by hand". `_atomic_backward` says it
  mirrors "the default mapper exactly" (`ProjectionTemplate.jl:794`) but uses
  `make_introduced_reference`. The strict `==` separates the two forms.
- Rule: PAR-FOLDED-CHECKPOINTS (produce the canonical form).
- Fix: build the default with `make_introduced_reference(projection, iomap.input, reference)`.
- Reach: `ProjectionDefaults.jl`.

### L17-14 The 2-argument print_document fails for a node projection

- Category: Correctness · Severity: Low · Confidence: Confirmed.
- Where: [ProjectionDefaults.jl:7](../../../source/kernel/projection/ProjectionDefaults.jl#L7) ⬜
- Evidence: `print_document(projection, input)` passes `recursion = nothing`. A node
  projection calls `print_child(nothing, …)`, which is `print_document(nothing, nothing, …)`,
  a `MethodError`. So `print_document(JsonArrayToSyntaxNode(), array)` fails, and the
  2-argument form works only for a leaf or a self-recursive wrapper.
  `projection-system.md:110-112` says "The editor uses this"; the editor calls the
  4-argument form (`FaultBarriers.jl:185`).
- Rule: bug (usability); PAR-HONEST-DOCS.
- Fix: say in the docstring that the form is for a leaf or a wrapped pipeline, and
  correct the guide.
- Reach: `ProjectionDefaults.jl`, `ProjectionInterface.jl`, `projection-system.md`.

### L17-15 The template walk writes cells while a parent computation runs

- Category: Architecture · Severity: Low · Confidence: Confirmed; no failure seen.
- Where: [ProjectionTemplate.jl:662](../../../source/kernel/projection/ProjectionTemplate.jl#L662) ⬜,
  [ProjectionTemplate.jl:479](../../../source/kernel/projection/ProjectionTemplate.jl#L479) ⬜
- Evidence: the children computation of `_inline_print` calls `setproperty!(leaf, fname, v.render)`.
  A nested template prints inside the reconcile computation of its parent, and there it
  reads blueprint cells (`_find_*`, lines 297-374, with `[]`) and then writes them
  (lines 458, 479, 540, 563). The cells are new and no other cell reads them, so no
  consumer goes stale mid-computation. But each read adds an edge from a fresh output
  cell to the parent computation, and a later write of that cell invalidates the parent
  (this feeds L17-5).
- Rule: PAR-NO-WRITE-IN-THUNK (it has no carve-out for fresh cells).
- Fix: read the blueprint with `peek`, or record the fresh-cell case as a carve-out.
- Reach: `ProjectionTemplate.jl`, or `architecture-invariants.md`.

### L17-16 ChildrenContainer.jl is an empty fragment

- Category: Shape · Severity: Low · Confidence: Confirmed.
- Where: [ChildrenContainer.jl:1](../../../source/kernel/projection/ChildrenContainer.jl#L1) ⬜
- Evidence: the file holds a 5-line header and no code since commit 4c067207 moved its
  two declarations to `ProjectionInterface.jl:364-379`. The fragment table
  (`ProjectionModule.jl:63`) and the banner `(methods in ChildrenContainer.jl)`
  (`ProjectionInterface.jl:362`) still point to it; the methods are in
  `source/collection/CellVector.jl:320-322`.
- Rule: PAR-PROJECTION-PLACEMENT ("no orphan shapes the structure").
- Fix: delete the file and its `include`; correct the table and the banner.
- Reach: `ChildrenContainer.jl`, `ProjectionModule.jl`, `ProjectionInterface.jl`.

### L17-17 The children-container seam has one registrant per process

- Category: Shape · Severity: Low · Confidence: Confirmed.
- Where: [ProjectionInterface.jl:371](../../../source/kernel/projection/ProjectionInterface.jl#L371) ⬜,
  [ProjectionTemplate.jl:841](../../../source/kernel/projection/ProjectionTemplate.jl#L841) ⬜
- Evidence: `get_children_container_type()` takes no argument, and
  `make_children_container` dispatches only on `Vector` or `Function`. One package can
  define each method; a second definition overwrites the first. Every template output
  gets the same container whatever its output domain, and the engine writes that type
  into every type checkpoint (line 841). Without ProjecturedCollection loaded, no
  template node prints.
- Rule: PAR-FRAMEWORKS-SINK (the seam must let each user register its own methods).
- Fix: key both methods on the output node, `make_children_container(out, cells)` and
  `get_children_container_type(out)`.
- Reach: `ProjectionInterface.jl`, `ProjectionTemplate.jl`, `source/collection/CellVector.jl`.

### L17-18 The default reader special-cases two operations that a seam covers

- Category: Shape · Severity: Low · Confidence: Confirmed.
- Where: [ProjectionDefaults.jl:171](../../../source/kernel/projection/ProjectionDefaults.jl#L171) ⬜
- Evidence: two branches answer `ToggleCollapseOperation` and
  `SelectNextInsertionOperation` unchanged, and line 189-190 calls them "the kernel's
  own instances" of the `operation_travels_unchanged` case. That open seam exists
  (`source/kernel/operation/Rerooting.jl:59`) and higher packages use it. The function
  is 80 lines (118-197) against a budget of 60.
- Rule: code-quality-rules.md §5 (function budget); one mechanism for one case.
- Fix: add the two `operation_travels_unchanged` methods in the operation layer and
  delete the two branches.
- Reach: `ProjectionDefaults.jl`, `source/kernel/operation/Operations.jl` ⬜.

### L17-19 ProjectionTemplate.jl and its helpers exceed the size, width and argument budgets

- Category: Shape · Severity: Low · Confidence: Confirmed.
- Where: [ProjectionTemplate.jl:436](../../../source/kernel/projection/ProjectionTemplate.jl#L436) ⬜,
  [ProjectionModule.jl:86](../../../source/kernel/projection/ProjectionModule.jl#L86) ⬜
- Evidence: the file is 1423 lines (budget 500). 126 lines of the layer are over 90
  characters (95 in this file, 11 in `PrinterContext.jl`, 9 in `ProjectionModule.jl`).
  Private helpers take 4 to 7 positional arguments with no marker, for example
  `_node_print(p, recursion, doc, ctx, out, children_field, coll)`, `_inline_print`,
  `_sections_print`, `_slots_forward`. The export block breaks §1: one statement mixes
  interface and default names, `print_pure` stands with `@projection`, and the two
  interface seams form a separate fifth statement. Planned: plan/pending/export-block-rule.md
  (`ProjectionModule.jl` is in `EXPORT_UNMIGRATED`).
- Rule: code-quality-rules.md §1, §4, §5.
- Fix: split the engine into fragments (markers and walk, mappers, readers, macro)
  when it next changes.
- Reach: `ProjectionTemplate.jl`, `ProjectionModule.jl`.

### L17-20 The template mappers switch by isa over Any fields, and RuleIoMap keeps constants in reactive cells

- Category: Types/performance · Severity: Low · Confidence: Confirmed for the code;
  Suspected for the cost (not measured).
- Where: [ProjectionTemplate.jl:724](../../../source/kernel/projection/ProjectionTemplate.jl#L724) ⬜,
  [ProjectionTemplate.jl:178](../../../source/kernel/projection/ProjectionTemplate.jl#L178) ⬜
- Evidence: both generic mappers select the wiring with a 7-branch `isa` chain over
  `iomap.wiring`, while `_focused_child` dispatches by method. The wiring structs type
  `intype`, `outtype`, `bound_type` and `retype` as `Any`. `RuleIoMap.child_iomaps`
  holds five shapes (a cell of a vector, a `Dict`, a state tuple, a `NamedTuple`,
  `nothing`) that only the wiring separates. `@iomap` makes the five fields reactive
  cells, and four of them (projection, input, output, wiring) never change, so each
  mapper call inside a selection computation adds edges to four constant cells.
- Rule: code-quality-rules.md (use dispatch); PAR-FINEST-GRANULARITY (no cell that
  never changes needs reactive bookkeeping).
- Fix: dispatch `_forward(w::NodeWiring, …)`; type the fields that hold types; declare
  the constant fields of `RuleIoMap` as `ImmutableCell`.
- Reach: `ProjectionTemplate.jl`.

### L17-21 Four names break the naming rules

- Category: Naming · Severity: Low · Confidence: Confirmed.
- Where: [GestureBindings.jl:1](../../../source/kernel/projection/GestureBindings.jl#L1) ⬜,
  [PrinterContext.jl:251](../../../source/kernel/projection/PrinterContext.jl#L251) ⬜,
  [ProjectionTemplate.jl:178](../../../source/kernel/projection/ProjectionTemplate.jl#L178) ⬜
- Evidence:
  - `GestureBindings.jl` is one letter from `binding/GestureBinding.jl`; a tab shows the
    name only. `ProjectionGestureBindings.jl` says what it defines.
  - `withhold_offer(ctx, axis)` answers a derived copy, which the rules name
    `with_<stem>`. It also takes any `Symbol` other than `:x` as the height axis.
  - One concept has two words: `@projection_template`, `read_template_intent`,
    `make_template_builder` against `RuleIoMap` and `print_template_rule`.
  - The parameters of the four functions differ inside the layer: `projection` and `p`,
    `context` and `ctx`, `operation`, `op`, `evt` and `c`, `input` and `doc`. Planned:
    plan/pending/unify-projection-api-parameter-names.md. Its scheme (`prj`, `rec`,
    `ref`, `op`, `evt`) uses the short forms that naming-rules.md "Words" and the
    project instructions discourage; the plan needs a new decision.
- Rule: naming-rules.md ("A file is named for what it defines", "Derived copies are
  `with_<stem>`", "Words"); writing-rules.md ("one word for one thing").
- Fix: rename with `workspace/bin/julia-rename.jl`; check the axis in `withhold_offer`.
- Reach: the layer; callers of `withhold_offer` in layout and widget.

### L17-22 Links, paths and type names in the layer are stale

- Category: Documentation · Severity: Low · Confidence: Confirmed.
- Where: [ProjectionModule.jl:45](../../../source/kernel/projection/ProjectionModule.jl#L45) ⬜,
  [ProjectionInterface.jl:146](../../../source/kernel/projection/ProjectionInterface.jl#L146) ⬜
- Evidence: `documentation/testing.md` (ProjectionModule.jl:45) does not exist.
  `package/kernel/doc/…` (ProjectionModule.jl:54-57, ProjectionInterface.jl:271 and 278,
  ProjectionDefaults.jl:122, ProjectionTemplate.jl:1176) does not exist; the guides are
  in `documentation/package/kernel/`. `plan/pending/cell-kind-documents.md`
  (ProjectionInterface.jl:152, ProjectionTemplate.jl:228) is in `plan/done/`.
  "Sequential" (ProjectionInterface.jl:146, ProjectionDefaults.jl:38) is
  `ChainingProjection`. `[_with_selection](@ref)` (ProjectionTemplate.jl:225) points at
  a private name.
- Rule: writing-rules.md "Links"; PAR-MODULE-DOCSTRING.
- Fix: correct each path and name.
- Reach: five files of the layer.

### L17-23 Comments state false facts about the layer

- Category: Documentation · Severity: Low · Confidence: Confirmed.
- Where: [ProjectionModule.jl:63](../../../source/kernel/projection/ProjectionModule.jl#L63) ⬜,
  [ProjectionReferenceStep.jl:7](../../../source/kernel/projection/ProjectionReferenceStep.jl#L7) ⬜,
  [ProjectionTemplate.jl:2](../../../source/kernel/projection/ProjectionTemplate.jl#L2) ⬜
- Evidence: the fragment table says `ChildrenContainer.jl` holds the open generics
  (L17-16) and `GestureBindings.jl` holds open generics (L17-10). ProjectionModule.jl:70
  and ProjectionTemplate.jl:2-3 say every structural projection is written with the
  engine; `SqlToSyntax.jl` has 20 hand-written printers, `MathToSyntax.jl` 5,
  `FormulaToSyntax.jl` 4, `CollectionToSyntax.jl` 2 (Planned:
  plan/pending/projection-template-engine.md converts them). ProjectionReferenceStep.jl:7
  says "a `:terminal` step type"; line 27 answers `:structural`, and no `:terminal`
  kind exists. ProjectionTemplate.jl:183 says "(nodes; WIP)". Line 794 and lines
  466-469 are false (L17-13, L17-6), and so is the export claim of the pure printer
  (L17-9).
- Rule: PAR-HONEST-DOCS, PAR-MODULE-DOCSTRING.
- Fix: correct each statement.
- Reach: four files of the layer.

### L17-24 Comments narrate history and use plan codes

- Category: Documentation · Severity: Low · Confidence: Confirmed.
- Where: [ProjectionTemplate.jl:265](../../../source/kernel/projection/ProjectionTemplate.jl#L265) ⬜,
  [ProjectionDefaults.jl:38](../../../source/kernel/projection/ProjectionDefaults.jl#L38) ⬜
- Evidence: lines 265-275 record a change: "Recognising only the raw `Vector` is why a
  fixed-children template node had to be spelled in the long positional form … So the
  rule is strictly additive — it cannot change what any existing template does."
  "F1", "F2" and "F3" (lines 133, 234, 299, 311, 494, 496, 513, 556) are feature codes
  of a plan and have no definition in the source. ProjectionDefaults.jl:38 says "from
  day one". ProjectionTemplate.jl:228 and ProjectionInterface.jl:150-153 cite plan
  phases.
- Rule: code-quality-rules.md §2; PAR-TIGHT-COMMENTS.
- Fix: keep the constraint in the present tense, and name each shape in words (a
  nested sub-node, a reactive child list, an `as=` override).
- Reach: `ProjectionTemplate.jl`, `ProjectionDefaults.jl`, `ProjectionInterface.jl`.

### L17-25 Kernel text names consumers and calls pipeline stages layers

- Category: Documentation · Severity: Low · Confidence: Confirmed.
- Where: [ProjectionInterface.jl:279](../../../source/kernel/projection/ProjectionInterface.jl#L279) ⬜,
  [ProjectionDefaults.jl:172](../../../source/kernel/projection/ProjectionDefaults.jl#L172) ⬜,
  [ProjectionTemplate.jl:10](../../../source/kernel/projection/ProjectionTemplate.jl#L10) ⬜
- Evidence: ProjectionInterface.jl:279-305 names `PointReferenceStep` and
  "`map_operation_position` of the graphics package"; the seam carve-out allows a
  concept, not a method of a higher package. ProjectionDefaults.jl:172 "Collapse state
  lives at the syntax layer" and ProjectionTemplate.jl:1166 "the upstream Text/Syntax
  layers" call pipeline stages layers. Other consumer names: ProjectionTemplate.jl:403-404
  (the render stage), ProjectionReferenceStep.jl:46-48 (`PaneToWidget`),
  ProjectionMacro.jl:26 (`FocusingProjection`), GestureBindings.jl:25 (Clipboard),
  PrinterContext.jl:258-260 (the editor loop). ProjectionTemplate.jl:10-15 and
  1374-1380 say the same thing twice and describe a private import of a higher package.
- Rule: PAR-NO-CONSUMER-DOCS, PAR-DIVISION-VOCABULARY, PAR-TIGHT-COMMENTS.
- Fix: describe the contract only; delete the second copy of the comment.
- Reach: six files of the layer.

### L17-26 The contract docstrings teach forms that the rules forbid

- Category: Documentation · Severity: Low · Confidence: Confirmed.
- Where: [ProjectionInterface.jl:179](../../../source/kernel/projection/ProjectionInterface.jl#L179) ⬜,
  [ProjectionInterface.jl:193](../../../source/kernel/projection/ProjectionInterface.jl#L193) ⬜
- Evidence: the Example of `read_intent` is
  `read_intent(::BoxToText, iomap, event::KeyDown) = event.key == :backspace ? … : nothing`:
  a 3-argument shim (PAR-PREFER-REFERENCE-RETARGET) and a geometry-free key in a
  projection reader (PAR-GEOMETRY-FREE-IN-DOCUMENT). A model copies the Example
  (code-quality-rules.md §1). Lines 193-198 say "Leaf projections therefore keep their
  3-arg methods", and lines 238-240 say a projection returns an `Operation` although
  the 4-argument form returns an `Intent`. `map_reference_backward`, `print_child`,
  `PrinterContext`, `make_child_context` and `read_routed_intent` have no "Use it to"
  paragraph, no Example and no "See also". The `Projection` docstring adds an older
  paragraph after "See also" (lines 27-30).
- Rule: PAR-PREFER-REFERENCE-RETARGET, PAR-GEOMETRY-FREE-IN-DOCUMENT,
  code-quality-rules.md §1.
- Fix: show the 4-argument form in the Example with a gesture that needs geometry;
  complete the four parts.
- Reach: `ProjectionInterface.jl`, `ProjectionDefaults.jl`, `PrinterContext.jl`.

### L17-27 The design documents of the layer are stale

- Category: Documentation · Severity: Low · Confidence: Confirmed.
- Where: `documentation/package/kernel/projection-system.md`,
  `documentation/package/kernel/macros.md`, `documentation/rule/naming-rules.md`,
  `documentation/package/kernel/architecture.md`
- Evidence: projection-system.md:110-112 says the editor uses the 2-argument print
  (L17-14). Lines 163-168 list `Intent` with two fields and line 182 calls `route` "a
  fifth field"; `Intent` has five fields. Lines 148-150 say a pipeline uses the pure
  pair for image, PDF and text (L17-9). macros.md:9-10 says "Seventeen files use it"
  and lines 353-355 say every structural projection uses it; 18 files use it, and 31
  hand-written printers remain in four `*ToSyntax` files. naming-rules.md:384-385 says the marker words are exported (L17-8).
  architecture.md:111 gives `ProjectionModule` layer 13; it is layer 17. Partly
  planned: plan/pending/documentation-rewrite-survey.md (the pure printer, the
  2-argument link).
- Rule: PAR-UPDATE-THE-GUIDE, PAR-HONEST-DOCS.
- Fix: correct each statement.
- Reach: four documents.

## Accepted before, not raised again

- No earlier audit of this layer exists in `plan/done/`.
- The five marker words are not exported. The owner decided it in
  `plan/done/projection-layer-is-one-module.md` (stage 3). L17-8 reports only the
  private imports that the decision left in another package and in omnet-julia.
- Reactive cells hold `Any` on purpose.
- Deferred: the gesture unions of the default reader (`KeyPress`, `KeyDown`,
  `MousePress`) and of the template reader (`KeyPress`, `KeyDown`) do not take a
  `KeyChord` (plan/pending/key-chords-from-bindings.md).
- The reader payloads `ClaimedGesture` (2026-07-14) and `CollectIntents` (2026-08-08)
  are older than PAR-NO-NEW-SYNTHETIC-EVENT (2026-09-23), which says that an existing
  payload is not a precedent.

## Checked and clean

- PAR-NO-PROJECTION-GLOBALS, PAR-PER-EDITOR-STATE: the layer has no module-level
  mutable state; each table lives in an IoMap or a cell closure.
- PAR-RECURSE-VIA-PRINT-CHILD: every descent of the engine uses `print_child`; the one
  direct `print_document` call applies a projection that an `as=` override supplies.
- PAR-DELEGATE-ONE-LEVEL: the engine prints one level and delegates each child through
  `recursion` and the stored child IoMaps.
- PAR-BIDIRECTIONAL-PROJECTION, PAR-MAPPERS-ARE-INVERSES: the default pair and each
  wiring map both ways, and each pair adds and strips the same
  `ProjectionReferenceStep` (except the ranges of L17-2).
- PAR-USE-PROJECTION-MACRO: `@projection` supplies `<: Projection` and exports the
  type; `RuleIoMap` uses `@iomap`.
- PAR-INTERFACE-DECLARES-ONLY: `ProjectionInterface.jl` holds only the abstract type,
  bodiless declarations and docstrings; the kernel layering guard is green in the
  baseline log.
- PAR-QUALIFIED-EXTENSION, PAR-MODULE-BOUNDARY-IS-API inside the kernel: the reference
  seams are extended by qualification, the macro emits `ProjectionModule.print_document`
  and `ProjectionModule.read_intent`, and the layer names only exported symbols.
- PAR-PROJECTION-PLACEMENT: the layer names no concrete document.
- PAR-REGISTER-NEW-OPERATION: the default reader maps every path-bearing kernel
  operation and opens the rest through `operation_reference` / `retarget_operation`.
- PAR-FOLDED-CHECKPOINTS: the engine folds its `TypeReferenceStep`s with
  `fold_reference_types` and types its answers with `annotate_reference_types`.
- PAR-SHARED-CHILDREN-IOMAP: a node wiring keeps its child IoMaps in one reconciled
  cell. `RuleIoMap` has the role that the rule gives `ChildrenIoMap`.
- PAR-EMPTY-PATH-IS-SELECTION: `∅` maps by identity and is typed on each side.
- The history word list of code-quality-rules.md §2 has no hit in the layer (the forms
  of L17-24 are outside the list).
- Exported function names start with a verb, and the predicates start with `is_`.
