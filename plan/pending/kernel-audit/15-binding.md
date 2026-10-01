# Layer 15 — binding (`source/kernel/binding/`)

Commit 15b40434, 2026-09-27. Seal state: none sealed (0 of 4).

## Verdict

The binding layer works, and its own suite passes with 81 assertions. It holds no
process-global mutable state. The most important finding is L15-1: the lookup
never finds a table that `@gestures` declares on a concrete parameterization, for
example a `[DC]`-bound document name. The layer also builds each table again on
every lookup on the key path (L15-3). Its documentation says that `sel` and `event`
are in scope in a rule body, and that is false (L15-4). Two open seams that other
packages extend are not in the interface file (L15-2). The split with
`projection/GestureBindings.jl` in layer 17 follows the dependency height and is
correct.

## Shape

- Purpose: reified gesture rules. A `GestureBinding` holds an event pattern, an
  operation closure, a precondition, a description, a domain tag, an `override`
  flag and an optional name. The layer keeps a table for each document type (a
  method for each type) and a table for each instance. It has one loop that fires a
  table and one answer to the `CollectIntents` payload. It also holds the
  `@gestures` / `@gesture_set` DSL and the `read_gesture` seam with its catch-all
  for `Document`.
- Files:

  | file | lines | seal | what it holds |
  | --- | ---: | --- | --- |
  | `GestureBindingModule.jl` | 48 | ⬜ | docstring, three `using`, one `export`, three `include`s |
  | `GestureBindingInterface.jl` | 26 | ⬜ | the `read_gesture` declaration |
  | `GestureBinding.jl` | 245 | ⬜ | the struct, the type and instance tables, the loop that fires, the name run, the intent collection, `read_bound_gesture`, the `read_gesture` catch-all |
  | `Gestures.jl` | 218 | ⬜ | the `@gestures` / `@gesture_set` parser and macros |

- Imports: bare `using` of `DocumentModule` (layer 10), `EventModule` (6) and
  `IntentModule` (14). It extends no foreign generic, so it has no `import`.
  Imported by: `ProjectionModule` (layer 17) in the kernel, and 24 files outside the
  kernel. `DomainModule` imports `get_document_gesture_bindings_own` and
  `WidgetModule` imports `get_instance_gesture_bindings` to extend them.
- Public surface: 12 exported names.
  - Used by production code outside the kernel: `GestureBinding`, `@gestures`,
    `read_gesture`, `read_bound_gesture`, `fire_gesture_bindings`,
    `get_document_gesture_bindings_own` (extended), `get_instance_gesture_bindings`
    (extended).
  - Used only inside the kernel and by tests: `get_document_gesture_bindings`.
  - Used only by tests: `fire_named_gesture_binding`, `get_applicable_gesture_bindings`,
    `@gesture_set`.
  - No user outside its own file: `collect_binding_intents`.
  - omnet-julia and inet-julia use no name of this layer, except in generated
    precompile lists.
- The split with layer 17: `projection/GestureBindings.jl` holds
  `get_projection_gesture_bindings(::Projection, iomap)` and
  `read_projection_gesture`. Both need the `Projection` type (layer 17) and read the
  input of an IoMap (layer 16). Layer 15 can not import either. Both fire through
  this layer's `fire_gesture_bindings`, so the one loop stays here. The split is
  correct. At the seam, the layer-17 file repeats the selection read (L15-8), and
  its name differs from `GestureBinding.jl` by one letter (L15-12).
  `read_projection_gesture` passes no `claimed`, so the `override` flag has no
  effect in a projection table. That is a question for layer 17.
- Deferred plan: `plan/pending/key-chords-from-bindings.md` wants the chord table of
  an editor to come from `KeyChord` patterns in these tables. The tables are
  methods per type, so a collector must walk the types that a projection reaches.
  The fix of L15-3 (one constant table per type) makes that walk cheap.
- State: no module-level mutable state. The tables are methods. A `@gesture_set`
  is a module-level `const` vector that nothing writes after load, so it is the
  same for every editor. No shared state needs a lock.
- Tests: `test/kernel/binding/GestureBindingTest.jl`, one file, 303 lines, 20
  testsets, 81 assertions, all pass in the baseline. It covers the DSL, inheritance,
  `@gesture_set` and `splice`, the precondition, rules with no gesture, the name run,
  and `CollectIntents`. Fifteen more files in `test/` reach the layer through
  domains (JSON, XML, text, pane, command palette, widgets). The kernel suite does
  not test the claim gate, the instance tables, the three-argument
  `read_bound_gesture`, or a parameterized document type (L15-6).

## Summary

| Category | High | Medium | Low |
| --- | ---: | ---: | ---: |
| Correctness | 0 | 1 | 2 |
| Architecture | 0 | 1 | 0 |
| Shape | 0 | 0 | 3 |
| Types/performance | 0 | 1 | 0 |
| Naming | 0 | 0 | 1 |
| Documentation | 0 | 2 | 1 |
| Tests | 0 | 1 | 1 |

## Findings

### L15-1 The lookup does not find a table that `@gestures` declares on a concrete parameterization

- Category: Correctness · Severity: Medium · Confidence: Confirmed (no document has
  such a table today)
- Where: [GestureBinding.jl:72](../../../source/kernel/binding/GestureBinding.jl#L72) ⬜,
  [Gestures.jl:188](../../../source/kernel/binding/Gestures.jl#L188) ⬜
- Evidence: `@gestures T` emits a method on `::Type{T}`. The walk asks only for the
  wrapper of each level: `base = S isa DataType ? S.name.wrapper : S`, then
  `get_document_gesture_bindings_own(base)`. It never asks for `S` itself. For a
  `[DC]` document, the bare name is a concrete type:
  [DocumentMacro.jl:689-690](../../../source/kernel/document/DocumentMacro.jl#L689)
  emits `const StyleColor = DCStyleColor`, a parameterization of `ACStyleColor`. So
  `@gestures StyleColor begin … end` compiles, and `read_gesture` on a `StyleColor`
  returns `nothing` for every key. The same occurs for `@gestures DCFoo`, `ICFoo`,
  `MCFoo`, `RCFoo` and `Foo{Int}`. The three `[DC]` documents of today
  (`StyleFont`, `StyleColor`, `StyleText`) declare no table, so no user sees it now.
- Rule: bug. The `@gestures` docstring promises a table for any document type.
- Fix: in the walk, ask for `S` first and then for its wrapper when the two are
  different. Or make `@gestures` raise an error on a concrete parameterization.
- Reach: `GestureBinding.jl` (or `Gestures.jl`); a new case in
  `GestureBindingTest.jl`.

### L15-2 Two open seams that other packages extend are not in the interface file

- Category: Architecture · Severity: Medium · Confidence: Confirmed
- Where: [GestureBinding.jl:48](../../../source/kernel/binding/GestureBinding.jl#L48) ⬜,
  [GestureBinding.jl:92](../../../source/kernel/binding/GestureBinding.jl#L92) ⬜,
  [GestureBindingInterface.jl:1](../../../source/kernel/binding/GestureBindingInterface.jl#L1) ⬜
- Evidence: `get_document_gesture_bindings_own` and `get_instance_gesture_bindings`
  start as default methods with bodies in `GestureBinding.jl`. Other packages add
  methods to both: `source/platform/domain/DomainModule.jl:26` imports the first,
  `source/platform/widget/WidgetModule.jl:40` imports the second, and every `@gestures`
  extends the first. The interface file declares only `read_gesture`. Commit
  4c067207 ("every open seam lives in its layer's contract files") moved
  `read_gesture` and left these two.
- Rule: architecture-rules.md, "Interfaces live with their concept … Each layer's
  interface is its first file(s)"; PAR-INTERFACE-DECLARES-ONLY (the export list of
  the interface is the API surface of the layer).
- Fix: declare `function get_document_gesture_bindings_own end` and
  `function get_instance_gesture_bindings end`, with their docstrings, in
  `GestureBindingInterface.jl`. Keep the two default methods in `GestureBinding.jl`.
- Reach: `GestureBindingInterface.jl`, `GestureBinding.jl`, `GestureBindingModule.jl`
  (export order). No other repository.

### L15-3 Each lookup builds every gesture table of the supertype chain again

- Category: Types/performance · Severity: Medium · Confidence: Confirmed for the
  mechanism; Suspected for the cost per key (it needs a measurement with the frame
  counters or an allocation count)
- Where: [Gestures.jl:187-191](../../../source/kernel/binding/Gestures.jl#L187) ⬜,
  [Gestures.jl:125](../../../source/kernel/binding/Gestures.jl#L125) ⬜,
  [GestureBinding.jl:64-78](../../../source/kernel/binding/GestureBinding.jl#L64) ⬜,
  [GestureBinding.jl:223-227](../../../source/kernel/binding/GestureBinding.jl#L223) ⬜
- Evidence:
  - The method that `@gestures` emits makes a new `Vector{GestureBinding}` on each
    call: new closures for each operation, guard and precondition, a new pattern,
    and a new `modifiers` vector.
  - A rule with no description calls `describe_event_pattern` on each call, which
    makes two `Dict`s and joins strings
    ([EventPattern.jl:170-178](../../../source/kernel/event/EventPattern.jl#L170)).
    The macro also puts the pattern expression into the expansion twice
    (lines 125 and 133).
  - `get_document_gesture_bindings` calls the method for each level of the
    supertype chain, on each `read_gesture`. The template reader calls
    `read_gesture` at each level of the selected path
    ([ProjectionTemplate.jl:1314](../../../source/kernel/projection/ProjectionTemplate.jl#L1314)),
    and again at each level for a claimed key
    ([ProjectionTemplate.jl:1346](../../../source/kernel/projection/ProjectionTemplate.jl#L1346)).
  - The comment at Gestures.jl:181-182 says the table is "cached by
    `get_document_gesture_bindings`". The docstring at GestureBinding.jl:59-62 says
    that it is not cached, and the code does not cache it.
- Rule: PAR-PROFILE-WITH-COUNTERS (find the work that a key press does);
  PAR-TIGHT-COMMENTS (when a comment and the code differ, the comment is the bug).
- Fix: let `@gestures` make the table once, in a hidden `const`, as `@gesture_set`
  already does, and let the emitted method return it. A table made once is read-only
  data that is the same for every editor, which the PAR-PER-EDITOR-STATE carve-out
  permits. Delete the false comment.
- Reach: `Gestures.jl`; the docstring of `get_document_gesture_bindings`.

### L15-4 The documentation says that `sel` and `event` are in scope in a rule body, but the body gets only `doc` and the pattern variables

- Category: Documentation · Severity: Medium · Confidence: Confirmed
- Checked by the lead on 2026-09-27: Read the code: the operation closure names its event argument with `gensym(:event)`, and only the precondition binds `sel`.
- Where: [Gestures.jl:18-19](../../../source/kernel/binding/Gestures.jl#L18) ⬜,
  [Gestures.jl:150-152](../../../source/kernel/binding/Gestures.jl#L150) ⬜,
  [Gestures.jl:155-156](../../../source/kernel/binding/Gestures.jl#L155) ⬜,
  [Gestures.jl:45](../../../source/kernel/binding/Gestures.jl#L45) ⬜,
  [Gestures.jl:106](../../../source/kernel/binding/Gestures.jl#L106) ⬜,
  [Gestures.jl:123](../../../source/kernel/binding/Gestures.jl#L123) ⬜
- Evidence: The operation closure is `(doc, <gensym>) -> body` for a rule
  (lines 106 and 123) and for a `nothing` rule (line 45). Only the block
  precondition binds `sel` (line 64). The header comment says "In `rhs` and in the
  precondition, `doc` is the document and `sel` the selection". The `@gestures`
  docstring says "`rhs` builds the operation with `doc`, `event` and any bound
  pattern variables in scope", and says "the rhs reads `doc` and `sel` only" for a
  `nothing` rule. `devices-and-backends.md:615` repeats it. A rule written as the text
  says, `KeyDown(:x; ctrl) => "Cut" => cut(doc, sel)`, compiles, and throws
  `UndefVarError: sel` at the first Ctrl+X. The tables that exist read the selection
  themselves: `sel = doc.selection`
  ([SyntaxDocument.jl:609](../../../source/platform/syntax/SyntaxDocument.jl#L609)) and
  `get_selection(doc)` ([JsonDocument.jl:137](../../../source/domain/json/JsonDocument.jl#L137)).
- Rule: PAR-HONEST-DOCS; PAR-MODULE-DOCSTRING (keep docstrings accurate).
- Fix: the owner chooses one. Bind `sel = doc.selection` in the operation closure,
  or correct the three texts and the guide to say "`doc` and the pattern variables".
  Do not promise `event`: the parameter is a gensym on purpose.
- Reach: `Gestures.jl`; `documentation/package/kernel/devices-and-backends.md`.

### L15-5 The package design document gives wrong signatures and a wrong file tree for the layer

- Category: Documentation · Severity: Medium · Confidence: Confirmed
- Where: [devices-and-backends.md](../../../documentation/package/kernel/devices-and-backends.md)
  lines 552-557, 565, 598, 606, 625, 630-633;
  [engineer-tour.md](../../../documentation/design/engineer-tour.md) line 191
- Evidence:
  - Line 565 writes `fire_gesture_bindings(bindings, target, selection, event)`. The
    code is `fire_gesture_bindings(bindings, target, event; selection, claimed = nothing)`
    ([GestureBinding.jl:119](../../../source/kernel/binding/GestureBinding.jl#L119)).
    A call copied from the guide raises a `MethodError`.
  - Line 598 writes `fire_named_gesture_binding(bindings, target, selection, name)`.
    The code is `(bindings, target, name; selection)`
    ([GestureBinding.jl:152](../../../source/kernel/binding/GestureBinding.jl#L152)).
  - Lines 552-557: the file tree has no `GestureBindingInterface.jl` and puts
    `read_gesture` in `GestureBinding.jl`.
  - Lines 630-633, "Downward edges": `..EventModule` is there twice, `..IntentModule`
    is not there, and `..DocumentModule: Document` is a symbol-list import that the
    module does not use.
  - Line 606 and engineer-tour.md:191 call `move_to_field(doc, :key, :value)`. The
    function takes keywords, `move_to_field(doc; from, to)`
    ([Domain.jl:497](../../../source/platform/domain/Domain.jl#L497)), as
    [JsonDocument.jl:139](../../../source/domain/json/JsonDocument.jl#L139) calls it.
  - Line 625 puts the command palette "in the domain package". It is in the
    `gesturehelp` package of the substrate.
- Rule: PAR-UPDATE-THE-GUIDE; PAR-HONEST-DOCS.
- Fix: correct the two signatures, the tree, the edges and the two examples.
- Reach: `devices-and-backends.md`, `engineer-tour.md`.

### L15-6 The kernel suite does not test the claim gate, the instance tables or a parameterized type

- Category: Tests · Severity: Medium · Confidence: Confirmed
- Where: [GestureBindingTest.jl](../../../test/kernel/binding/GestureBindingTest.jl)
- Evidence: the file has no case for these parts:
  - `claimed` and `override`: `claimed === nothing || binding.override || continue`
    ([GestureBinding.jl:127](../../../source/kernel/binding/GestureBinding.jl#L127)).
    Only domain suites (XML, pane) reach it, through whole pipelines.
  - `get_instance_gesture_bindings`, and the order "instance before type" in
    `_gesture_bindings` (GestureBinding.jl:223-227).
  - The three-argument `read_bound_gesture(target, event, selection)`
    (GestureBinding.jl:206).
  - A document with a `[DC]`, `[M]` or `[I]` layout (see L15-1 and L15-8).
  - An operation that returns `nothing`, so that a later rule fires
    (GestureBinding.jl:130).
- Rule: PAR-NEW-CODE-SHIPS-TESTS. The lowest test package that can express these
  cases is `ProjecturedKernelTest`.
- Fix: add one testset for each item to `GestureBindingTest.jl`.
- Reach: `test/kernel/binding/GestureBindingTest.jl`.

### L15-7 A second block precondition replaces the first with no error

- Category: Correctness · Severity: Low · Confidence: Confirmed
- Where: [Gestures.jl:63-65](../../../source/kernel/binding/Gestures.jl#L63) ⬜,
  [Gestures.jl:138-139](../../../source/kernel/binding/Gestures.jl#L138) ⬜
- Evidence: each bare `when(expr)` sets `precondition = …`, so a second one replaces
  the first with no message. Every rule of the block reads the one `_applicable`, so
  the precondition also applies to the rules above it. A table written as
  `when(a) … when(b) …` looks like two sections and acts as one section with `b`
  only.
- Rule: bug. The header says "optional, block-level" and does not say "at most one".
- Fix: raise an error on a second `when(expr)` in one block, or accept it only as
  the first entry.
- Reach: `Gestures.jl`.

### L15-8 The layer reads the selection through the raw cell and not through `get_selection`

- Category: Correctness · Severity: Low · Confidence: Confirmed for the code; no
  document of today reaches the failure
- Where: [GestureBinding.jl:218](../../../source/kernel/binding/GestureBinding.jl#L218) ⬜,
  [GestureBinding.jl:243](../../../source/kernel/binding/GestureBinding.jl#L243) ⬜;
  [projection/GestureBindings.jl:33-34](../../../source/kernel/projection/GestureBindings.jl#L33) ⬜
- Evidence: `getfield(target, :selection)[]` expects a field that holds a cell. A
  document of a native layout (`[M]` or `[I]`) holds its selection as a plain value.
  For such a document the read is `nothing[]` or `reference[]`, a `MethodError`. It
  occurs as soon as a table exists on the type chain of that document. The selection layer, which is lower, has the getter:
  `get_selection(document::Document) = document.selection`
  ([SelectionDefaults.jl:7](../../../source/kernel/selection/SelectionDefaults.jl#L7)).
  Layer 17 repeats the raw read with `hasproperty` and `hasfield` guards.
- Rule: bug; one getter for one value (the `get_selection` / `set_selection!` pair of
  naming-rules.md).
- Fix: add `using ..SelectionModule` and call `get_selection(target)` for a
  `Document`. Keep the explicit `selection` argument for a target that is not a
  document.
- Reach: `GestureBinding.jl`, `GestureBindingModule.jl`, `projection/GestureBindings.jl`.

### L15-9 Four exported names have no user in production code

- Category: Shape · Severity: Low · Confidence: Confirmed (searched `source/`,
  `package/`, `example/`, `tool/` and `test/` here, and omnet-julia and inet-julia)
- Where: [GestureBindingModule.jl:35-41](../../../source/kernel/binding/GestureBindingModule.jl#L35) ⬜
- Evidence:
  - `collect_binding_intents`: one caller, `fire_gesture_bindings` in the same file
    (GestureBinding.jl:124). No user anywhere else.
  - `fire_named_gesture_binding`: only tests (`GestureBindingTest.jl`,
    `CommandPaletteTest.jl:406`, `EvaluatorToplevelTest.jl:656`). The palette runs a
    command through the operation that `CollectIntents` built, not by its name.
  - `get_applicable_gesture_bindings`: only `GestureBindingTest.jl`.
    `JsonToSyntaxTest.jl:236` names it in a comment, beside
    `collect_gesture_bindings`, a function that does not exist.
  - `@gesture_set` and `splice(…)`: only `GestureBindingTest.jl`.
- Rule: architecture-rules.md, "No orphans shape the structure"; the size of the
  public surface.
- Fix: stop the export of `collect_binding_intents`. Ask the owner whether the other
  three stay as supported API (each has tests) or go.
- Reach: `GestureBindingModule.jl`, `GestureBinding.jl`, `Gestures.jl`, the kernel
  test, `devices-and-backends.md`.

### L15-10 A collected `Intent` holds a pattern where the `Intent` contract says an input event

- Category: Shape · Severity: Low · Confidence: Confirmed
- Where: [GestureBinding.jl:186](../../../source/kernel/binding/GestureBinding.jl#L186) ⬜;
  [Intent.jl:10-12](../../../source/kernel/intent/Intent.jl#L10) ⬜
- Evidence: `collect_binding_intents` makes `Intent(binding.pattern, operation, …)`.
  The `Intent` docstring defines `gesture` as "the originating input (a device event
  …)" that stays unchanged through the chain. A collected intent holds an
  `EventPattern` or `nothing` in that field, and a list reads it with
  `describe_event_pattern(intent.gesture)` (`JsonToSyntaxTest.jl:238`). One field
  has two meanings, and the contract states one.
- Rule: PAR-HONEST-DOCS; writing-rules.md, "Use one word for one thing".
- Fix: state the second meaning in the `Intent` docstring, or give the pattern a
  field of its own.
- Reach: `Intent.jl` (layer 14) or `GestureBinding.jl`.

### L15-11 The module file and one parser function break the code-quality budgets

- Category: Shape · Severity: Low · Confidence: Confirmed
- Where: [GestureBindingModule.jl:35-41](../../../source/kernel/binding/GestureBindingModule.jl#L35) ⬜,
  [Gestures.jl:56-142](../../../source/kernel/binding/Gestures.jl#L56) ⬜,
  [Gestures.jl:217-218](../../../source/kernel/binding/Gestures.jl#L217) ⬜
- Evidence:
  - One `export` statement names the names of three fragments, and the interface
    name `read_gesture` is not first. Planned: `plan/pending/export-block-rule.md`
    (the guard in `test/suite/exports.jl` lists this module).
  - `_parse_gesture_block` has 87 lines. The budget for a function of main code is
    60.
  - The two branches of `_type_name` return the same `string(document_type)`.
- Rule: code-quality-rules.md §1 (the export block) and §5 (size budgets).
- Fix: one export statement per fragment; move the parse of one rule out of
  `_parse_gesture_block`; fold `_type_name` to one test.
- Reach: `GestureBindingModule.jl`, `Gestures.jl`.

### L15-12 Two getters do a search, and two files of adjacent layers differ by one letter

- Category: Naming · Severity: Low · Confidence: Confirmed
- Where: [GestureBinding.jl:64](../../../source/kernel/binding/GestureBinding.jl#L64) ⬜,
  [GestureBinding.jl:242](../../../source/kernel/binding/GestureBinding.jl#L242) ⬜;
  [projection/GestureBindings.jl](../../../source/kernel/projection/GestureBindings.jl) ⬜
- Evidence: `get_document_gesture_bindings` walks the supertype chain and gathers
  the table of each level; the verb table gives `collect_` for that. 
  `get_applicable_gesture_bindings` filters a list with a predicate; `get_` is for a
  value at a known place. `GestureBinding.jl` (layer 15) and `GestureBindings.jl`
  (layer 17) show almost the same name in a tab or a stack trace.
  naming-rules.md itself uses `get_document_gesture_bindings_own` as an example, so
  a rename touches that document too.
- Rule: naming-rules.md, "The verb follows the nature of the work"; "A file is named
  for what it defines".
- Fix: if the owner agrees, rename with `workspace/bin/julia-rename.jl`, and give the
  layer-17 file a name that says "projection", for example
  `ProjectionGestureBinding.jl`.
- Reach: `GestureBinding.jl`, about 40 call sites in tests, `ProjectionModule.jl`,
  naming-rules.md.

### L15-13 The source text has stale phrases, consumer names and phrases that break the writing rules

- Category: Documentation · Severity: Low · Confidence: Confirmed
- Where: the four files of the layer ⬜
- Evidence:
  - [GestureBindingInterface.jl:20](../../../source/kernel/binding/GestureBindingInterface.jl#L20)
    says "The catch-all `read_gesture(::Document, gesture)` below". The method is in
    GestureBinding.jl:233. Commit 4c067207 moved the text and kept "below".
  - [GestureBinding.jl:16](../../../source/kernel/binding/GestureBinding.jl#L16): the
    signature in the docstring has no `override` keyword.
  - [GestureBindingModule.jl:1-28](../../../source/kernel/binding/GestureBindingModule.jl#L1):
    the docstring names `Gestures.jl` but not the other two fragments. It does not
    name `get_instance_gesture_bindings`, `fire_named_gesture_binding` or
    `CollectIntents`.
  - Consumer names (PAR-NO-CONSUMER-DOCS): "the line the gesture help draws" and
    "what a command palette calls it" (GestureBinding.jl:22-24); "the chain reader"
    (GestureBinding.jl:111); "the Lisp" (GestureBinding.jl:172); "XML's `<` inside a
    tag name" (Gestures.jl:25).
  - "Layer" for a stage of the pipeline (PAR-DIVISION-VOCABULARY): "output layer(s)"
    (GestureBinding.jl:106-109, Gestures.jl:23), "the text layer" (Gestures.jl:26,
    162).
  - Idioms (writing-rules.md): "for free" (GestureBindingModule.jl:20,
    GestureBindingInterface.jl:18), "provably" (GestureBindingModule.jl:26).
  - Gestures.jl:6-28 repeats the grammar and the `override` reason of the
    `@gestures` docstring (Gestures.jl:147-173), which PAR-TIGHT-COMMENTS forbids.
  - Ten lines are longer than 90 characters: GestureBinding.jl:128, 186;
    Gestures.jl:13, 41, 42, 77, 84, 100, 125, 188.
- Rule: as each item names; code-quality-rules.md §5 for the line width.
- Fix: edit the text.
- Reach: the four files of the layer.

### L15-14 The binding test repeats event-layer tests and names a past state

- Category: Tests · Severity: Low · Confidence: Confirmed
- Where: [GestureBindingTest.jl:3-5](../../../test/kernel/binding/GestureBindingTest.jl#L3),
  [GestureBindingTest.jl:71-110](../../../test/kernel/binding/GestureBindingTest.jl#L71)
- Evidence: four testsets test `matches_event_pattern` and `describe_event_pattern`,
  which belong to the event layer. `test/kernel/event/EventModuleTest.jl` already
  tests both (17 lines name them). The header says "parity with the old hand-written
  readers", a phrase about the past.
- Rule: a test lives with the file it tests (naming-rules.md, "`<Thing>Test.jl`");
  code-quality-rules.md §2, "A comment says what is, never what was".
- Fix: move the four testsets to the event suite, or delete the copies; delete "old
  hand-written".
- Reach: `GestureBindingTest.jl`, `EventModuleTest.jl`.

## Accepted before, not raised again

- Chords: `@gestures` has no `KeyChord` pattern, and the editor collects no chord
  table. The owner deferred this on 2026-09-25
  (`plan/pending/key-chords-from-bindings.md`, `plan/done/gesture-layer-audit.md` D6).
- The shared pattern parser of `@event_case` and `@gestures`, and `__module__` as the
  scope of an event type name (`plan/done/event-layer-audit.md`).
- The module name of the layer-17 file: closed on 2026-09-12, "the kernel keeps its
  modules" (`plan/pending/naming-rule-violations.md`). The file is now a fragment of
  `ProjectionModule`.
- `CollectIntents` and `ClaimedGesture` exist as reader payloads. PAR-NO-NEW-SYNTHETIC-EVENT
  says that they are no precedent; they are not raised as findings.
- A collected list keeps a row for a rule that can not run, with no operation: a
  deliberate difference from the Lisp original (`plan/done/reified-gesture-bindings.md`).

## Checked and clean

- PAR-PER-EDITOR-STATE and PAR-NO-PROJECTION-GLOBALS: no module-level mutable state;
  the tables are methods; a `@gesture_set` vector is written once at load.
- PAR-QUALIFIED-EXTENSION: `@gestures` emits a method on
  `$(@__MODULE__).get_document_gesture_bindings_own`; the module header has bare
  `using` only; `DomainModule` and `WidgetModule` import the names they extend.
- PAR-MODULE-BOUNDARY-IS-API: no code outside the module reaches a name that it does
  not export.
- PAR-INTERFACE-DECLARES-ONLY: `GestureBindingInterface.jl` declares only; the guard
  checks it.
- Layering: the module imports layers 6, 10 and 14 only; the kernel guard passes.
- PAR-READER-IS-PURE: the loop that fires returns an operation and writes nothing.
- PAR-GEOMETRY-FREE-IN-DOCUMENT: `read_gesture` reads only the document and its
  selection.
- Exact modifier match: the layer calls `matches_event_pattern` of the event layer
  and has no second matcher.
- code-quality-rules.md §4: every public function has at most three positional
  arguments; `GestureBinding` has five keywords.
- History comments: the grep of code-quality-rules.md §2 finds none in the layer.
- PAR-CITE-EXCEPTIONS-ONLY: the one citation (GestureBinding.jl:61) states a rejected
  alternative, which the rule permits.
