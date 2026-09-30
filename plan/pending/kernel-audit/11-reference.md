# Layer 11 — reference (`source/kernel/reference/`)

Commit 15b40434, 2026-09-27. Seal state: 2 of 13 sealed (`ReferenceInterface.jl`, `ReferenceSearch.jl`).

## Verdict

The layer builds, walks, annotates and matches paths, and its sealed interface file still declares only.
One defect reaches callers: an element or range step indexes a `String` by byte, so non-ASCII text gives a wrong character or a throw (L11-1).
Half of the 4529 lines are a pattern language whose rules object, string spelling and interpreter no kernel or editor code uses (L11-10).
Its compiled and interpreted readings already disagree in forms that the conformance corpus does not hold (L11-2).
Other contracts are weaker than documented: M-layout steps never match, some steps hash by identity, walkers catch every exception, stored steps stay shared (L11-3, L11-5, L11-7, L11-13).
The design document describes an older layer, and the kernel suite on main has an unmarked Error in this layer (L11-16, L11-18).

## Shape

- Purpose: paths into documents. The layer holds the step and path types, the walk of a path against a document (evaluate, validate, annotate), the path-valued search, three DSLs over one grammar (`@reference`, `@reference_case`, `@reference_rules`), a string spelling of a pattern (`ref"…"`), a glob matcher, and `ReferencedDocument` / `DocumentLocator`.
- Files:

| file | lines | seal | what it holds |
| --- | ---: | :---: | --- |
| `ReferenceModule.jl` | 136 | ⬜ | module docstring, header, one export statement, 12 includes |
| `ReferenceInterface.jl` | 162 | 🔒 | `ReferenceStep`, `Reference`, six bodiless seam generics |
| `ReferenceStep.jl` | 228 | ⬜ | `RangeReferenceStep`, `FieldReferenceStep`, `TypeReferenceStep` (`@document [C, M]`), `Position`, `ReferenceTypeMismatchException`, their `==`/`hash`/`show`/seam methods |
| `ReferencePath.jl` | 232 | ⬜ | `EmptyReference`, `ConcreteReference` (`@cell_struct`), iteration, `==`/`hash`, `extend_reference`, `concat_references`, `get_reference_steps` |
| `ReferenceEvaluation.jl` | 297 | ⬜ | `evaluate_reference`, `try_evaluate_reference`, `get_valid_reference_prefix`, `is_valid_reference`, annotate/strip/fold, `copy_reference`, `_strict_check` |
| `ReferenceSearch.jl` | 74 | 🔒 | `search_references` over `walk_document` |
| `ReferenceSyntax.jl` | 390 | ⬜ | the shared surface grammar: `ReferenceSyntaxStep` AST, `parse_reference_path`, `parse_reference_step` |
| `ReferenceGlob.jl` | 111 | ⬜ | `glob_matches` |
| `ReferenceCase.jl` | 1150 | ⬜ | `PatStep`/`PatValue` AST, lowering, the compiled matcher, `@reference_case` |
| `ReferenceRules.jl` | 972 | ⬜ | `ReferenceRules`, the interpreted matcher, answer compilation with `Core.eval`, `show`, `@reference_rules` |
| `ReferencePatternString.jl` | 204 | ⬜ | `parse_reference_pattern`, `ref"…"` |
| `ReferenceBuilder.jl` | 234 | ⬜ | `@reference`, `@reference_step` |
| `ReferencedDocument.jl` | 339 | ⬜ | `ReferencedDocument`, `DocumentLocator`, `get_parent`, `get_edited_document` |

- Imports: bare `using` of `CellModule`, `CellStructModule`, `DocumentModule`; `import ..DocumentModule: search_documents, get_wrapped_document` (both extended in `ReferencedDocument.jl`). Imported by: kernel `SelectionModule`, `OperationModule`, `IntentModule`, `ProjectionModule`, `EditorModule`, `PlaybackModule`; 52 slice module files of this repository; 68 files of omnet-julia; 3 files of inet-julia.
- Module / Interface / Defaults: the layer has a module file and an interface file but no defaults file. The seam defaults are spread over four fragments (`ReferenceSyntax.jl:274`, `ReferenceCase.jl:746`, `ReferenceRules.jl:153`, `ReferenceBuilder.jl:87`). The interface header names a different home (L11-25).
- Public surface: 69 exported names. Used outside the kernel: the step and path types, the walkers, annotate/strip, `search_references`, `@reference`, `@reference_case`, `ReferencedDocument` and its functions. No user outside the layer and its own tests, in all three repositories: `REFERENCE_RULE_MODES`, `ReferenceSyntaxStep`, `ReferenceRules`, `ReferenceRule`, `ReferenceRuleAnswer`, `apply_reference_rules`, `match_reference_pattern`, `@reference_rules`, `@ref_str`. `match_reference_step_value` is a declared seam with no production method. Used only by omnet-julia: the eight `A…`/`M…` step names, `glob_matches`, `parse_reference_pattern`. Not exported but imported by omnet-julia: nine `Pat…` names (L11-9).
- State: no module-level mutable state except the method table of `_run_reference_rule_answer`, which grows at run time (L11-12). `REFERENCE_RETIRED_ARMS` is a `const Dict` that nothing writes. `_PATH_WALK` is immutable. Per object: `ReferenceRuleAnswer.compiled` changes on apply. Every path node and every C-layout step keeps its fields in reactive cells; the selection layer writes `tail`, `start` and `stop` in place (L11-13).
- Tests: `test/kernel/reference/`, 4 files, 1824 lines. `ReferenceBuilderTest.jl` (38 checks: the builder, `@reference_step`, part of `@reference_case`), `ReferenceEvalTest.jl` (33 pass, 1 Error on main), `ReferenceRulesTest.jl` (896: the conformance corpus, rules, globs, the string spelling), `ReferencedDocumentTest.jl` (51). L11-19 lists the gaps in coverage.
- Sealed files since their seal: `ReferenceInterface.jl` gained `match_reference_step_value` on 2026-09-20 (4c067207, accepted by the owner, "noted for re-audit"; the note left `SEALING.md` in 4d763b34). Re-audited here: it declares only, and the name is exported. `ReferenceSearch.jl` changed one docstring sentence on 2026-09-23 (0d13bf21, with permission).

## Summary

| category | High | Medium | Low |
| --- | ---: | ---: | ---: |
| Correctness | 1 | 7 | 1 |
| Architecture | 0 | 1 | 0 |
| Shape | 0 | 2 | 2 |
| State | 0 | 2 | 0 |
| Types/performance | 0 | 1 | 1 |
| Naming | 0 | 0 | 1 |
| Documentation | 0 | 3 | 1 |
| Tests | 0 | 2 | 0 |
| **total** | **1** | **18** | **6** |

## Findings

### L11-1 An element or range step indexes a String by byte, not by character

- Category: Correctness · Severity: High · Confidence: Confirmed
- Checked by the lead on 2026-09-27: Read the code: `document[step.start + 1]` at `ReferenceStep.jl:118`. The path from a key press to this line is not run.
- Where: [ReferenceStep.jl:118](../../../source/kernel/reference/ReferenceStep.jl#L118) ⬜
- Evidence: `evaluate_reference_step(step::ARangeReferenceStep, document)` answers `unwrap_cell(document[step.start + 1])`. For a `String`, Julia reads that index as a byte index. The contract says `[i]` is the i-th character ([reference.md:172-175](../../../documentation/package/kernel/reference.md#L172), table at line 728). The code base counts text offsets in characters (`s + length(replacement)` in `PrimitiveDocument.jl:176`). Failure: on `"héllo"`, `[3]` throws `StringIndexError` instead of answering `'l'`; `[6]` answers `'o'`, although the string has five characters. A range `{2:4}` on that string fails `get_valid_reference_prefix`, so `set_selection!` rejects a valid range with `SelectionMismatchException`, because `_selection_matches` drops only a terminal cursor ([SelectionDefaults.jl:169](../../../source/kernel/selection/SelectionDefaults.jl#L169) 🔒). `annotate_reference_types` also leaves such a path untyped.
- Rule: PAR-ONE-BASED-INDEXING (convert explicitly at every reference-to-container crossing); bug.
- Fix: add `evaluate_reference_step(step::ARangeReferenceStep, document::AbstractString)` that reads `document[nthind(document, step.start + 1)]`, and a test with a multi-byte character.
- Reach: `ReferenceStep.jl`, `ReferenceEvalTest.jl`. No sealed file.

### L11-2 The compiled and the interpreted reading of one pattern disagree in five forms

- Category: Correctness · Severity: Medium · Confidence: Confirmed
- Where: [ReferenceCase.jl:524](../../../source/kernel/reference/ReferenceCase.jl#L524) ⬜, [ReferenceRules.jl:850](../../../source/kernel/reference/ReferenceRules.jl#L850) ⬜, [ReferenceCase.jl:1017](../../../source/kernel/reference/ReferenceCase.jl#L1017) ⬜, [ReferenceCase.jl:869](../../../source/kernel/reference/ReferenceCase.jl#L869) ⬜
- Evidence: the arm syntax is parsed twice: `_parse_rule`/`_parse_arm_pattern` for `@reference_case`, `_parse_rules_arm`/`_rules_pattern` for `@reference_rules`. The contract is "a pattern means one thing, whichever DSL" ([ReferenceRules.jl:525-529](../../../source/kernel/reference/ReferenceRules.jl#L525)).
  1. `at(∅)`, `below(∅)`, `within(∅)`, `above(∅)`, `toward(∅)`, and `∅::T` inside an arm word: the case parser sends the argument to `_parse_path`, which reads `∅` as a field named `"∅"`. The rules parser reads it as the empty pattern. So `within(∅)` matches every path in rules and no path in a case.
  2. `within(ref"…")` and the other arm words around `ref"…"`: the rules parser accepts them; the case parser raises "unsupported reference syntax".
  3. A `nothing` input: the compiled catch-all `__ =>` returns its answer for `nothing` (line 1021), and so does a bare `rest... =>` arm. The interpreter answers `nothing` for every arm (`match_reference_pattern(…, ::Nothing)`, `ReferenceRules.jl:536`). A bound catch-all `__(x) =>` throws `MethodError` on `nothing` (`_navigation_length(::Reference)`).
  4. A leading `::t` binder on a `nothing` input throws "type Nothing has no field type" (`$sp.type`, line 869). The `::T` form tolerates it through `_type_step_node_type`.
  5. `above(a.rest...)`: no `_gen_step_match` method takes `PatStepWholePathBind`, so macro expansion fails with `MethodError`. The interpreter answers `true` (`ReferenceRules.jl:485-488`).
  The corpus paths ([ReferenceRulesTest.jl:68-95](../../../test/kernel/reference/ReferenceRulesTest.jl#L68)) hold no `nothing`, and no corpus arm puts `∅` or `ref"…"` inside an arm word.
- Rule: bug. The done plan `reference-pattern-vocabulary.md` makes the interpreter the normative matcher.
- Fix: one arm parser that both macros call. Read `∅`, `∅::T` and `ref"…"` after the arm word. Decide once what `nothing` means for a catch-all and write it down. Guard `::t` as `::T` is guarded. Handle `PatStepWholePathBind` in `_gen_above_match`. Add `nothing` and the arm-word rows to the corpus.
- Reach: `ReferenceCase.jl`, `ReferenceRules.jl`, `ReferenceRulesTest.jl`. A change of the catch-all reading touches 33 `__ =>` arms in `source/`.

### L11-3 The matchers and the path helpers recognize only the C layout of a step

- Category: Correctness · Severity: Medium · Confidence: Confirmed (latent: no production path mixes the layouts today)
- Where: [ReferenceCase.jl:685](../../../source/kernel/reference/ReferenceCase.jl#L685) ⬜ (also 699, 713, 730, 848, 948), [ReferenceRules.jl:227](../../../source/kernel/reference/ReferenceRules.jl#L227) ⬜ (230-238, 329, 393-418, 462), [ReferenceEvaluation.jl:206](../../../source/kernel/reference/ReferenceEvaluation.jl#L206) ⬜ (241, 260)
- Evidence: the module docstring promises that "a reactive step equals a plain step holding the same values" and that the `A…` family carries the shared methods ([ReferenceModule.jl:73-81](../../../source/kernel/reference/ReferenceModule.jl#L73)). But the generated matcher tests `$hex isa ReferenceModule.FieldReferenceStep` / `RangeReferenceStep`, the interpreter tests `h isa FieldReferenceStep`, `strip_reference_types` and `fold_reference_types` test `isa TypeReferenceStep`, and `_copy_reference_step` takes `::RangeReferenceStep`. The bare names bind the C layout, so `MFieldReferenceStep("a") isa FieldReferenceStep` is false. Failure: a path of `M` steps never matches `a`, `[i]`, `{k}` or `{s:e}` in either DSL. `copy_reference` does not copy an `M` range step. `set_selection!` does not descend an `M` step (`_selection_child`, [SelectionDefaults.jl:316](../../../source/kernel/selection/SelectionDefaults.jl#L316) 🔒). omnet-julia constructs `M` steps in 14 source files.
- Rule: bug.
- Fix: test the family (`AFieldReferenceStep`, `ARangeReferenceStep`, `ATypeReferenceStep`) in every `isa` above, or state that only C steps enter a `Reference` and convert at the boundary.
- Reach: `ReferenceCase.jl`, `ReferenceRules.jl`, `ReferenceEvaluation.jl`; `SelectionDefaults.jl` (sealed) for the selection walk.

### L11-4 `@reference_case` evaluates its input expression once for each arm it tries

- Category: Correctness · Severity: Medium · Confidence: Confirmed
- Where: [ReferenceCase.jl:1134](../../../source/kernel/reference/ReferenceCase.jl#L1134) ⬜
- Evidence: the macro builds the chain arm by arm, and every link is `let _ref_input = $(esc(ref))`. An input `f(x)` runs up to N times for N arms. Failure: `@reference_case get_selection(doc) begin … end` with five arms reads the selection up to five times, and an input with a side effect runs it again for each arm. Today all multi-arm call sites pass a plain variable, so no failure is seen.
- Rule: bug (a macro must evaluate its argument once).
- Fix: bind the escaped input once in an outer `let` with a gensym, and give each arm that name.
- Reach: `ReferenceCase.jl`.

### L11-5 Three walkers catch every exception, `InterruptException` included

- Category: Correctness · Severity: Medium · Confidence: Confirmed
- Where: [ReferenceEvaluation.jl:53](../../../source/kernel/reference/ReferenceEvaluation.jl#L53) ⬜, [ReferenceEvaluation.jl:91](../../../source/kernel/reference/ReferenceEvaluation.jl#L91), [ReferenceEvaluation.jl:101](../../../source/kernel/reference/ReferenceEvaluation.jl#L101), [ReferenceEvaluation.jl:184](../../../source/kernel/reference/ReferenceEvaluation.jl#L184)
- Evidence: `try_evaluate_reference`, `get_valid_reference_prefix` and `annotate_reference_types` use `try … catch … end` with no filter. They swallow `InterruptException`, `StackOverflowError` and `OutOfMemoryError`, which the fault layer names as never caught (`is_passthrough_exception`, `FaultDefaults.jl:26-30`). They also swallow a `MethodError` from a new step type that has no `evaluate_reference_step` method, and so turn a programming error into a silently truncated path or an untyped path.
- Rule: PAR-REPORT-NEVER-THROWS (second half: never swallow a fault in silence); bug.
- Fix: `catch e; is_passthrough_exception(e) && rethrow(); …`, and rethrow a `MethodError` whose function is `evaluate_reference_step`. Add `using ..FaultModule` (a lower layer).
- Reach: `ReferenceEvaluation.jl`, `ReferenceModule.jl`.

### L11-6 The path functions do not see through a `ReferencedDocument`

- Category: Correctness · Severity: Medium · Confidence: Confirmed
- Where: [ReferencedDocument.jl:212](../../../source/kernel/reference/ReferencedDocument.jl#L212) ⬜, [ReferenceSearch.jl:67](../../../source/kernel/reference/ReferenceSearch.jl#L67) 🔒
- Evidence: `search_documents` has a method that unwraps a `ReferencedDocument`; `search_references` has none. `walk_document` then walks the struct fields of the wrapper (`DocumentWalk.jl:213-217`). Failure: `search_references(people_1, "Ada")` on a `ReferencedDocument` answers paths that start with `::ReferencedDocument.document…`. These paths resolve neither from the editor root nor from the plain document, so `replace_referenced_value!` or a selection can not use them. `evaluate_reference(x, path)` and `annotate_reference_types(x, path)` fail the same way, because `_get_field` uses `getfield` on the wrapper. The docstring invites this use: "hand it to a function that needs the place" (line 30-32).
- Rule: bug. Related: plan/pending/the-assistant-reaches-a-referenced-document.md (D5 lifts the declared API only).
- Fix: add `search_references(x::ReferencedDocument, …)` that searches `get_document(x)` and prepends `get_reference(x)` with `concat_references`; add unwrapping methods of `evaluate_reference`, `try_evaluate_reference` and `annotate_reference_types`.
- Reach: `ReferencedDocument.jl`, `ReferencedDocumentTest.jl`. No sealed file.

### L11-7 Seven step types compare by value and hash by identity, and the interface states no contract

- Category: Correctness · Severity: Medium · Confidence: Confirmed (latent: nothing keys a table by such a path today)
- Where: [ReferencePath.jl:145](../../../source/kernel/reference/ReferencePath.jl#L145) ⬜, [ReferenceStep.jl:215](../../../source/kernel/reference/ReferenceStep.jl#L215) ⬜, [ReferenceInterface.jl:10](../../../source/kernel/reference/ReferenceInterface.jl#L10) 🔒
- Evidence: a `Reference` hashes by value "which is what lets one key a table" and mixes the hash of each head step. `PointReferenceStep`, `ChartSampleReferenceStep`, `SequenceChartRowReferenceStep`, `TextSpanReferenceStep`, `TextColumnReferenceStep`, `TextRangeReferenceStep` and `ProjectionReferenceStep` define `==` by value and no `hash`. They are `@cell_struct` values with cell fields, so the default hash follows cell identity. Failure: two equal paths that hold a text-range step land in different buckets of a `Dict`, `Set` or `unique`. The fallback `==(::ReferenceStep, ::ReferenceStep) = false` also makes `s == s` false for a step type that forgets `==`, so `is_valid_reference` then fails for every path with that step. The `ReferenceStep` docstring says nothing about `==` or `hash`.
- Rule: bug (the `==`/`hash` contract of Julia).
- Fix: state in the `ReferenceStep` docstring that a step type defines `==` and a consistent `hash`; add `Base.hash` to the seven types; change the fallback to `a === b`.
- Reach: `ReferenceInterface.jl` (sealed), `ReferenceStep.jl`, seven files in `source/graphics/`, `source/chart/`, `source/sequencechart/`, `source/text/`, `source/kernel/projection/`.

### L11-8 A range step evaluates to its first item, so a literal that records `::Position` after a range throws

- Category: Correctness · Severity: Medium · Confidence: Confirmed (the throw); Suspected (the reach in the editor, which needs a run)
- Where: [ReferenceStep.jl:116](../../../source/kernel/reference/ReferenceStep.jl#L116) ⬜
- Evidence: a cursor `{k}` evaluates to `Position(k)`; any other range answers `document[start + 1]`, the first item only. The layer does not say what a run of items is. Domain code assumes a range lands on a `Position`: `@reference ::DocumentInsertion.value::String{s:e}::Position` (`source/syntax/InsertionToSyntax.jl:107`, `:126`). For `s < e`, `evaluate_reference` of that literal reaches a `Char` and throws `ReferenceTypeMismatchException`, and `try_evaluate_reference` answers `nothing`. The text steps of the text package evaluate to a `(start, stop)` tuple instead, so two conventions exist.
- Rule: PAR-FOLDED-CHECKPOINTS (a recorded type must be the type the walk reaches); design fault.
- Fix: give a non-empty range a value of its own (for example a span value beside `Position`), record its type in `annotate_reference_types`, and correct the two literals.
- Reach: `ReferenceStep.jl`, `ReferenceEvaluation.jl`, `source/syntax/InsertionToSyntax.jl`, the reference guide.

### L11-9 omnet-julia imports nine names that the reference layer does not export

- Category: Architecture · Severity: Medium · Confidence: Confirmed
- Where: [ReferenceModule.jl:92](../../../source/kernel/reference/ReferenceModule.jl#L92) ⬜, [ReferenceCase.jl:46](../../../source/kernel/reference/ReferenceCase.jl#L46) ⬜
- Evidence: `omnet-julia/source/legacy/ini/IniConfiguration.jl:35-37` imports `PatStep, PatStepField, PatStepIndex, PatStepGap, PatStepAny, PatValueLiteral, PatValueGlob, PatValueRange, PatValueWildcard` from `ProjecturedKernel.ReferenceModule`. None is exported. omnet-julia then walks the pattern AST with a matcher of its own (lines 300-360 there). The AST is therefore public API in practice, with no export and no contract.
- Rule: PAR-MODULE-BOUNDARY-IS-API.
- Fix: decide with the owner. Either export the pattern AST after its rename (Planned: plan/pending/naming-rule-violations.md, question 21), or give omnet-julia an exported query surface (for example `match_reference_pattern` over a path it builds) and keep the AST private.
- Reach: `ReferenceModule.jl`, `ReferenceCase.jl`; omnet-julia `IniConfiguration.jl`.

### L11-10 The kernel holds a configuration pattern language that no kernel or editor code uses

- Category: Shape · Severity: Medium · Confidence: Confirmed
- Where: [ReferenceRules.jl](../../../source/kernel/reference/ReferenceRules.jl) ⬜, [ReferencePatternString.jl](../../../source/kernel/reference/ReferencePatternString.jl) ⬜, [ReferenceGlob.jl](../../../source/kernel/reference/ReferenceGlob.jl) ⬜, [ReferenceCase.jl:1064](../../../source/kernel/reference/ReferenceCase.jl#L1064) ⬜
- Evidence: the four pattern fragments hold 2437 of 4529 lines. Measured over `source/`, `example/`, `tool/`, omnet-julia and inet-julia:
  - `@reference_rules`, `ReferenceRules`, `apply_reference_rules`, `match_reference_pattern` and `ref"…"` have no user outside the kernel tests.
  - In `@reference_case`, no production arm uses `any(…)`, a searched gap, `__ʔ`, `__(name)`, `glob"…"`, `lo..hi`, `below`, `within` or `toward`. Two arms use `above`. So the interpreter (`_consume`, `_match_above`) runs only in tests.
  - The one production consumer, omnet-julia's legacy ini reader, uses only `parse_reference_pattern`, the private AST and `glob_matches`, and matches with its own code.
  So one AST has three matchers: compiled, interpreted, and omnet-julia's. The arm syntax has two parsers (L11-2). The two spellings disagree on the same characters: `[0]` is element 0 in `a[0]` and element 1 in `ref"a[0]"`, and `{0}` is a cursor in `a{0}` and a glob character set in `ref"a{0}"`. A position or a range step can not be written in the string spelling. The seam `match_reference_step_value` has no method for `.proj`, `.point`, `.row` or `.sample`, so none of them can appear in a rules pattern. An `@reference_case` arm that pairs such a step with `any(…)` or a searched gap fails at run time.
- Rule: architecture-rules.md, "The package chain and what belongs to each" (kernel membership test: "does the editor loop itself need it?"); PAR-LOWEST-PACKAGE.
- Fix: decide with the owner. Either move `ReferenceRules.jl`, `ReferencePatternString.jl`, `ReferenceGlob.jl` and the interpreter to a substrate package that omnet-julia uses, or keep them and record the exception in architecture-rules.md. In both cases, give each extension step a `match_reference_step_value` method or remove the seam.
- Reach: the four fragments, `ReferenceModule.jl`, `ReferenceInterface.jl` (sealed) if the seam goes, the package list, omnet-julia.

### L11-11 The step types are built with `@document`, so each step carries a selection cell and document registrations

- Category: Shape · Severity: Medium · Confidence: Confirmed (the layout); Suspected (the cost, which needs a measurement)
- Where: [ReferenceStep.jl:36](../../../source/kernel/reference/ReferenceStep.jl#L36) ⬜, [ReferenceStep.jl:130](../../../source/kernel/reference/ReferenceStep.jl#L130), [ReferenceStep.jl:177](../../../source/kernel/reference/ReferenceStep.jl#L177)
- Evidence: `@document` injects `selection::Union{Nothing, Reference, SelectionDocument}` into every schema (`DocumentMacro.jl:592-620`) and registers the document family methods. A step is not a document and nothing selects inside one (module docstring, line 80-81). So every C-layout range step holds three reactive cells instead of two, and every `M` step holds an unused field. The `M` layout is a mutable struct (`native_mutable = :I ∉ layouts`), although the docstring calls it the plain value that a hot path "constructs, compares and hashes". A mutable value that hashes by value is a hazard, and it allocates. The `type` cells of both path nodes and the `head` cell are reactive, but no code writes them in place; only `tail`, `start` and `stop` change in place (`SelectionDefaults.jl:283`, `:341-342`). Each read of those cells inside a computation adds a dependency edge.
- Rule: code-quality-rules.md §3 ("Use the macros": the macro must fit the thing); PAR-FINEST-GRANULARITY.
- Fix: declare the step schemas with an explicit last field `selection::ImmutableCell{Nothing}` (the form `DocumentMacro.jl` allows for a value document), or give the struct layer a layout list without `@document`. Use `[C, I]` for the value layout if omnet-julia never writes a step. Make `type` and `head` immutable cells.
- Reach: `ReferenceStep.jl`, `ReferencePath.jl`; omnet-julia if the `M` names change.

### L11-12 A rules answer compiles into a process-wide method table with `Core.eval`

- Category: State · Severity: Medium · Confidence: Confirmed (growth, no lock, key by `repr`); Suspected (a key collision and a precompile failure, which need a run)
- Where: [ReferenceRules.jl:556](../../../source/kernel/reference/ReferenceRules.jl#L556) ⬜, [ReferenceRules.jl:565](../../../source/kernel/reference/ReferenceRules.jl#L565)
- Evidence: `_evaluate_answer` defines one method of `_run_reference_rule_answer` for each distinct (expression, binding names) pair, with `Core.eval(@__MODULE__, …)`. Consequences:
  1. The method table and the symbol table grow for as long as the process runs. No method is removed.
  2. `get!` on `answer.compiled`, then `hasmethod`, then `Core.eval`: no lock guards the sequence, and a rule set is a value that two tasks can share.
  3. The key is `Symbol(repr(expr), "|", names)`. A spliced value whose `repr` does not tell it apart (for example `Int32(1)` and `1` both print `1`, or a struct whose `show` prints only its type) reuses the first compiled method, and that method holds the first value.
  4. Every answer expression runs as code in `ReferenceModule`, also one read back with `deserialize` from a file. A rule set from a file is therefore a program.
  5. A call during the precompilation of another package would evaluate into the closed module `ReferenceModule`.
- Rule: PAR-PER-EDITOR-STATE (process-global state that one editor can change); PAR-NO-WRITE-IN-THUNK (the method table is a write outside the graph that the fault-store carve-out does not name).
- Fix: guard the cache and the definition with a lock; keep a global `Dict` from key to expression and compare with `==` before a method is reused; state in the `ReferenceRules` docstring that a rule set is code. A larger fix interprets the common answer shapes without `eval`.
- Reach: `ReferenceRules.jl`.

### L11-13 The path operations share mutable steps, and the selection writer mutates a step that a caller still holds

- Category: State · Severity: Medium · Confidence: Confirmed (the sharing); Suspected (a visible failure, which needs a run)
- Where: [ReferenceEvaluation.jl:203](../../../source/kernel/reference/ReferenceEvaluation.jl#L203) ⬜, [ReferenceEvaluation.jl:174](../../../source/kernel/reference/ReferenceEvaluation.jl#L174), [ReferencePath.jl:209](../../../source/kernel/reference/ReferencePath.jl#L209) ⬜
- Evidence: `strip_reference_types` and `annotate_reference_types` build new nodes but keep the step objects of their input, and `concat_references` answers `b` itself when `b` is typed. `set_selection!` stores `annotate_reference_types(document, strip_reference_types(path))` ([SelectionDefaults.jl:150](../../../source/kernel/selection/SelectionDefaults.jl#L150) 🔒), so the stored selection holds the caller's range step. On a later caret move in the same leaf, `_mutate_terminal_step!` writes that step's `start` and `stop` cells in place ([SelectionDefaults.jl:340](../../../source/kernel/selection/SelectionDefaults.jl#L340) 🔒). The path that the caller passed now names the new place. `copy_reference` exists for this ("A stored selection is a LIVE value"), and five call sites copy by hand: `UndoDocument.jl:259`, `:317`, `Inversion.jl:73`, `PaneSurgery.jl:394`, `ConversationEditor.jl:136`. Each new consumer must remember to copy.
- Rule: design fault (aliasing of mutable values across owners).
- Fix: make `strip_reference_types` answer fresh range steps, because it already rebuilds every node. Then no caller's step enters the store, and the fix changes no sealed file.
- Reach: `ReferenceEvaluation.jl`. The alternative, `copy_reference` in the selection writer, is in `SelectionDefaults.jl` (sealed).

### L11-14 `search_references` copies the whole path prefix at every node it visits

- Category: Types/performance · Severity: Medium · Confidence: Confirmed (the copies); Suspected (the size, which needs a measurement)
- Where: [ReferenceSearch.jl:14](../../../source/kernel/reference/ReferenceSearch.jl#L14) 🔒, [ReferencePath.jl:190](../../../source/kernel/reference/ReferencePath.jl#L190) ⬜
- Evidence: `_PATH_WALK.locate_field` and `locate_element` call `extend_reference(location, …)` for every child visited, not only for matches. `extend_reference` rebuilds every node of the base, and each node holds three reactive cells; each new C step holds two or three more. So a walk of N nodes at depth d allocates about N·d path nodes. `search_references` then re-walks each result from the root with `annotate_reference_types`. The pane package searches the editor document this way (`_find_focused_tree_route`, `PaneProgram.jl:806`), and so does code that the assistant runs.
- Rule: code-quality (a hot path must not allocate per visit without need).
- Fix: carry the location as a cheap reversed list of steps (for example a tuple chain), and build a `Reference` for a result only.
- Reach: `ReferenceSearch.jl` (sealed).

### L11-15 Three guides teach a bare `_` arm, which now raises at macro expansion

- Category: Documentation · Severity: Medium · Confidence: Confirmed
- Where: [reference.md:566](../../../documentation/package/kernel/reference.md#L566), [higher-order-projections.md:102](../../../documentation/package/projection/higher-order-projections.md#L102), [projection-system.md:598](../../../documentation/package/kernel/projection-system.md#L598)
- Evidence: each example ends a `@reference_case` block with `_ => …`. `_parse_arm_pattern` raises `REFERENCE_RETIRED_CATCH_ALL` for a bare `_` ([ReferenceCase.jl:542-547](../../../source/kernel/reference/ReferenceCase.jl#L542)). A reader who copies the example gets a `LoadError`. The `projection-system.md` example also uses `children[i] + rest`, which the grammar does not accept.
- Rule: PAR-HONEST-DOCS.
- Fix: write `__ =>` in the three examples, and `children[i].rest...` in the last one.
- Reach: the three guides.

### L11-16 The design document and many docstrings describe an older layer

- Category: Documentation · Severity: Medium · Confidence: Confirmed
- Where: [reference.md](../../../documentation/package/kernel/reference.md), [ReferenceModule.jl:1](../../../source/kernel/reference/ReferenceModule.jl#L1) ⬜, and the lines below
- Evidence:
  1. reference.md:21 and :92 say "eleven fragments", and the tree omits `ReferencedDocument.jl`. There are twelve.
  2. reference.md:100-111 says `@cell_struct` builds each step and that `DocumentModule` is imported "not for `@document`", and calls that "the whole import surface". The steps use `@document [C, M]`, and the layer also uses `walk_document`, `get_document_cell_type`, `get_edited_field` and imports two names to extend.
  3. reference.md:266-273 shows `is_valid_reference(PositionReferenceStep(5))`. No one-argument method exists; only `is_valid_reference(document, path)` ([ReferenceEvaluation.jl:116](../../../source/kernel/reference/ReferenceEvaluation.jl#L116)).
  4. A `{k}` terminal "stays untyped" (reference.md:314-315, [ReferencePath.jl:19](../../../source/kernel/reference/ReferencePath.jl#L19), [ReferenceEvaluation.jl:166](../../../source/kernel/reference/ReferenceEvaluation.jl#L166)). The code records `Position` (line 181-189; `ReferenceBuilderTest.jl:106`). The `annotate_reference_types` docstring also says it records `typeof(node)`; it records the cell layout.
  5. "An immutable linked list … extending a path reuses the existing tail, no copying" ([ReferenceInterface.jl:48](../../../source/kernel/reference/ReferenceInterface.jl#L48) 🔒, [ReferenceModule.jl:67](../../../source/kernel/reference/ReferenceModule.jl#L67), reference.md:196-198). `extend_reference` rebuilds every node of the base, and the nodes hold mutable cells.
  6. Interleaved checkpoint steps, which PAR-FOLDED-CHECKPOINTS retired: [ReferenceSearch.jl:36-40](../../../source/kernel/reference/ReferenceSearch.jl#L36) 🔒 ("each navigation step is preceded by a `TypeReferenceStep`"), [ReferenceStep.jl:162-188](../../../source/kernel/reference/ReferenceStep.jl#L162), [ReferenceEvaluation.jl:72](../../../source/kernel/reference/ReferenceEvaluation.jl#L72) and :112, [ReferencePath.jl:221](../../../source/kernel/reference/ReferencePath.jl#L221), [ReferenceInterface.jl:14-17](../../../source/kernel/reference/ReferenceInterface.jl#L14) 🔒. About twelve comments in other packages repeat it, for example `SyntaxToText.jl:1226`, `TextToGraphics.jl:1242`, `Copying.jl:194`.
  7. [ReferenceModule.jl:47-49](../../../source/kernel/reference/ReferenceModule.jl#L47) names "the `when`/`prefix` guards"; `prefix` raises.
  8. [ReferenceModule.jl:41-43](../../../source/kernel/reference/ReferenceModule.jl#L41) and reference.md:48-51, :67-72 say the grammar is parsed once. `ReferencePatternString.jl` is a second parser with other index and brace rules.
  9. The `@reference_case` docstring ([ReferenceCase.jl:1087-1126](../../../source/kernel/reference/ReferenceCase.jl#L1087)) and reference.md:570-585 omit `__`, `__ʔ`, `__(name)`, `_` as one step, `any(…)`, `glob"…"`, `lo..hi` and `ref"…"` arms.
  10. [selection.md:32-33](../../../documentation/package/kernel/selection.md#L32) calls the reference layer 8 and the document layer 7; they are 11 and 10.
  11. [naming-rules.md:342-343](../../../documentation/rule/naming-rules.md#L342) cites `is_reference_equal_ignoring_types` and `is_prefix_of_ignoring_types`, which no longer exist.
  12. reference.md:873-879 lists two test files; there are four.
- Rule: PAR-HONEST-DOCS, PAR-MODULE-DOCSTRING, PAR-UPDATE-THE-GUIDE.
- Fix: correct each item in place. Items 5 and 6 in the two sealed files need permission.
- Reach: reference.md, selection.md, naming-rules.md, `ReferenceModule.jl`, `ReferenceStep.jl`, `ReferencePath.jl`, `ReferenceEvaluation.jl`, `ReferenceCase.jl`; `ReferenceInterface.jl` and `ReferenceSearch.jl` (sealed); about twelve comments in other packages.

### L11-17 Kernel docstrings name the pane package, the editor and a simulator

- Category: Documentation · Severity: Medium · Confidence: Confirmed
- Where: [ReferenceBuilder.jl:168](../../../source/kernel/reference/ReferenceBuilder.jl#L168) ⬜, [ReferenceInterface.jl:35](../../../source/kernel/reference/ReferenceInterface.jl#L35) 🔒, [ReferencedDocument.jl:226](../../../source/kernel/reference/ReferencedDocument.jl#L226) ⬜, [ReferenceEvaluation.jl:130](../../../source/kernel/reference/ReferenceEvaluation.jl#L130) ⬜, [ReferenceModule.jl:73](../../../source/kernel/reference/ReferenceModule.jl#L73) ⬜
- Evidence: the `@reference` docstring tells a reader to use it "for `get_referenced_value`, `replace_referenced_value!` and `focus_pane!`" and shows `show_layout(editor)`; all four are in `source/pane/PaneProgram.jl`. The `Reference` docstring (sealed) shows `get_referenced_value(editor, place)` and "the tab a verb opened". `DocumentLocator`, `get_parent` and `get_edited_document` speak of the editor, tabs, groups, files, histories and `find_pane`. `get_reference_node_type`, the module docstring and `ReferenceStep.jl:41-49` explain the `M` layout through "a simulator's hot path", "designators, sites", "the shadow". `ReferenceSearch.jl:43-44` (sealed) uses `JsonString`.
- Rule: PAR-NO-CONSUMER-DOCS. Note: code-quality-rules.md §1 asks for a "Use it to" paragraph and a runnable example; in a kernel file the example must use kernel names.
- Fix: describe each contract with documents and references only; move the pane and editor examples to the pane package or to the orientation guide.
- Reach: `ReferenceBuilder.jl`, `ReferencedDocument.jl`, `ReferenceEvaluation.jl`, `ReferenceModule.jl`, `ReferenceStep.jl`; `ReferenceInterface.jl` and `ReferenceSearch.jl` (sealed).

### L11-18 The kernel suite has an unmarked Error in this layer on main

- Category: Tests · Severity: Medium · Confidence: Confirmed
- Where: [ReferenceEvalTest.jl:216](../../../test/kernel/reference/ReferenceEvalTest.jl#L216)
- Evidence: `native = MEvalBranch(root.left, root.right, nothing)` raises `UndefVarError: MEvalBranch` in the baseline run of `test_kernel()`. Commit 5759f13f renamed `EvalBranch` to `EvaluationBranch` and did not see the `@document`-generated `MEvalBranch`. So the check that a path built on a native tree equals the path built on its cell twin never runs.
- Rule: PAR-MARK-BROKEN-TESTS (Fail + Error must be zero).
- Fix: write `MEvaluationBranch`.
- Reach: `ReferenceEvalTest.jl`.

### L11-19 The kernel tests do not cover several contracts of the layer

- Category: Tests · Severity: Medium · Confidence: Confirmed
- Where: [test/kernel/reference/](../../../test/kernel/reference/)
- Evidence:
  - No kernel test calls `get_valid_reference_prefix`, `is_valid_reference`, `try_evaluate_reference`, `copy_reference`, `concat_references`, `extend_reference`, `fold_reference_types` or `search_references`. Each is tested above the kernel or not at all. `get_valid_reference_prefix` has one test, `test/projectured/reference/TypeReferenceTest.jl`, in the umbrella package with JSON fixtures, and it tests the retired unfolded form.
  - No test covers a multi-byte string (L11-1), `M` steps in patterns (L11-3), `nothing` and arm words with `∅` in the corpus (L11-2), repeated input evaluation (L11-4), `search_references` on a `ReferencedDocument` (L11-6), or `hash` consistency across step types (L11-7).
- Rule: PAR-NEW-CODE-SHIPS-TESTS (the lowest test package that can express them); PAR-LOWEST-PACKAGE (the JSON fixture belongs to the json test package).
- Fix: add toy-document tests to `ReferenceEvalTest.jl`; add `nothing` and `M`-step rows to the corpus; move `TypeReferenceTest.jl` to `test/json/` or rewrite it on toy documents in the folded form.
- Reach: `test/kernel/reference/`, `test/projectured/reference/TypeReferenceTest.jl`.

### L11-20 Four edge cases give a wrong answer or a late error

- Category: Correctness · Severity: Low · Confidence: Confirmed
- Where: [ReferencedDocument.jl:96](../../../source/kernel/reference/ReferencedDocument.jl#L96) ⬜, [ReferenceSyntax.jl:286](../../../source/kernel/reference/ReferenceSyntax.jl#L286) ⬜, [ReferenceBuilder.jl:216](../../../source/kernel/reference/ReferenceBuilder.jl#L216) ⬜, [ReferenceEvaluation.jl:290](../../../source/kernel/reference/ReferenceEvaluation.jl#L290) ⬜
- Evidence:
  1. `_find_referenced_value` searches with the default `raw = false`. A collection that is not a document, found under a document, gets the reference of the enclosing document, which the docstring forbids ("no reference is better than a wrong one").
  2. A qualified type `::Mod.T` parses as the type `Mod` and a field step `.T`. `@reference` stores a module as a node type, and a pattern then calls `nodetype <: Mod`, which throws `TypeError`.
  3. `@reference(document, path)` runs no strict-type check. A step that does not resolve leaves the rest untyped with no error, although the docstring says the types are "correct by construction".
  4. `is_fully_typed_reference(::Nothing) = true` answers yes when there is no path. `evaluate_reference` throws `TypeError` for a recorded node type that is not a `Type`, while the matchers tolerate it.
- Rule: bug.
- Fix: pass `raw = true`; reject a dotted type in `_ref_type_and_fields!` with a message; run `_strict_check` in the two-argument form; answer `false` for `nothing`.
- Reach: `ReferencedDocument.jl`, `ReferenceSyntax.jl`, `ReferenceBuilder.jl`, `ReferenceEvaluation.jl`.

### L11-21 Transitional and dead code remains

- Category: Shape · Severity: Low · Confidence: Confirmed
- Where: [ReferenceStep.jl:205](../../../source/kernel/reference/ReferenceStep.jl#L205) ⬜, [ReferenceEvaluation.jl:89](../../../source/kernel/reference/ReferenceEvaluation.jl#L89) ⬜, [ReferenceCase.jl:846](../../../source/kernel/reference/ReferenceCase.jl#L846) ⬜, [ReferenceRules.jl:390](../../../source/kernel/reference/ReferenceRules.jl#L390) ⬜
- Evidence:
  - PAR-FOLDED-CHECKPOINTS says a `TypeReferenceStep` never appears in a consumed path. The layer still evaluates it as a checkpoint (`ReferenceStep.jl:205-211`), truncates on it (`ReferenceEvaluation.jl:89-97`, `:179`), steps over it in both matchers (`ReferenceCase.jl:846-856`, `:946-956`; `ReferenceRules.jl:329-331`, `:390-420`, `:462-465`), and the corpus keeps an unfolded path alive. The done plan `eliminate-skip-type-checkpoints.md` called the removal an optional follow-up.
  - `_has_field` (`ReferenceStep.jl:139-140`) has no caller. `_node_type` (`ReferenceEvaluation.jl:152`) and `_concat` (`ReferenceBuilder.jl:110`) are aliases of exported functions.
  - `REFERENCE_RULE_MODES` and `ReferenceSyntaxStep` are exported and have no user outside the layer in the three repositories.
  - `parse_reference_step` (`ReferenceSyntax.jl:348-390`) repeats five branches of `_parse_ref_path!` with another rule for the leading identifier.
- Rule: code-quality-rules.md (dead code, redundancy); PAR-FOLDED-CHECKPOINTS.
- Fix: remove the token support and its corpus row; remove `_has_field` and the two aliases; drop the two exports; let `parse_reference_step` call the path parser and drop the leading identifier.
- Reach: `ReferenceStep.jl`, `ReferenceEvaluation.jl`, `ReferenceCase.jl`, `ReferenceRules.jl`, `ReferenceSyntax.jl`, `ReferenceBuilder.jl`, `ReferenceModule.jl`, the corpus, `ProjectionTemplate.jl` (it emits the token).

### L11-22 Two files and four functions pass the size budgets, and the export block has one statement with comments

- Category: Shape · Severity: Low · Confidence: Confirmed
- Where: [ReferenceCase.jl](../../../source/kernel/reference/ReferenceCase.jl) ⬜, [ReferenceRules.jl](../../../source/kernel/reference/ReferenceRules.jl) ⬜, [ReferenceModule.jl:92](../../../source/kernel/reference/ReferenceModule.jl#L92) ⬜
- Evidence: `ReferenceCase.jl` has 1150 lines and `ReferenceRules.jl` 972 (budget 500). `_gen_path_match` has 132 lines, `_parse_ref_path!` 120, `_consume` 91, `_gen_above_match` 82 (budget 60). 139 lines pass 90 characters: 47 in `ReferenceCase.jl`, 24 in `ReferenceRules.jl`, 16 in `ReferenceSyntax.jl`, 12 in `ReferenceBuilder.jl`, 10 in `ReferencedDocument.jl`. The export block is one statement for twelve fragments, with three comments inside it.
- Rule: code-quality-rules.md §1 and §5. Planned: plan/pending/export-block-rule.md (listed with 10 findings, open).
- Fix: split the lowering, the compiled matcher and the macro of `ReferenceCase.jl` into fragments, and the interpreter, the display and the quoting of `ReferenceRules.jl`; one export statement per fragment.
- Reach: `ReferenceCase.jl`, `ReferenceRules.jl`, `ReferenceModule.jl`.

### L11-23 Some calls allocate without need, and one search is exponential

- Category: Types/performance · Severity: Low · Confidence: Suspected (each needs a measurement)
- Where: [ReferenceCase.jl:1147](../../../source/kernel/reference/ReferenceCase.jl#L1147) ⬜, [ReferenceCase.jl:1064](../../../source/kernel/reference/ReferenceCase.jl#L1064), [ReferenceGlob.jl:31](../../../source/kernel/reference/ReferenceGlob.jl#L31) ⬜, [ReferencedDocument.jl:190](../../../source/kernel/reference/ReferencedDocument.jl#L190) ⬜
- Evidence: every `@reference_case` call allocates `_nomatch = Base.RefValue{Any}()` unless the compiler removes it; the calls run in every mapper. An interpreted arm builds its pattern vector and a bindings `Dict` on each call. `glob_matches` retries every split for each `*` with no memo, so time grows with the power of the count of `*`. Iteration of a collection that is not indexable, through a `ReferencedDocument`, runs one full `search_references` for each value and then annotates each result a second time (line 99).
- Rule: code-quality (hot path).
- Fix: a module-level sentinel constant; a constant pattern built once at expansion; a memo in `_glob_match`; `raw = true` and no second annotation in `_find_referenced_value`.
- Reach: `ReferenceCase.jl`, `ReferenceGlob.jl`, `ReferencedDocument.jl`.

### L11-24 Four names break the naming rules

- Category: Naming · Severity: Low · Confidence: Confirmed; Suspected (that the naming guard misses the first)
- Where: [ReferencePatternString.jl:202](../../../source/kernel/reference/ReferencePatternString.jl#L202) ⬜, [ReferenceCase.jl:46](../../../source/kernel/reference/ReferenceCase.jl#L46) ⬜, [ReferenceCase.jl:231](../../../source/kernel/reference/ReferenceCase.jl#L231) ⬜
- Evidence: the exported string macro `@ref_str` (`ref"…"`) carries `ref`, a forbidden abbreviation; the guard word list holds `"ref" => "reference"` but the baseline reports nothing. The `Pat…` family (`PatValueInterp`, `PatStepAlt`, fields `idxpat`, `namepat`) shortens Pattern, Interpolation, Alternative and index; omnet-julia imports nine of them (Planned: plan/pending/naming-rule-violations.md, question 21). `glob"…"` looks like a string macro, but no `@glob_str` exists, so outside a pattern it is an `UndefVarError`. The test file `ReferenceEvalTest.jl` and its testset "ReferenceEval" carry `eval`; the file it tests is `ReferenceEvaluation.jl`.
- Rule: naming-rules.md "Words" and "A file is named for what it defines".
- Fix: rename after the owner answers question 21; rename the test file to `ReferenceEvaluationTest.jl`.
- Reach: `ReferencePatternString.jl`, `ReferenceCase.jl`, `ReferenceRules.jl`, tests, omnet-julia.

### L11-25 Comments hold history or sit at the wrong code, and an invariant lacks one exception note

- Category: Documentation · Severity: Low · Confidence: Confirmed
- Where: [ReferenceCase.jl:512](../../../source/kernel/reference/ReferenceCase.jl#L512) ⬜, [ReferenceModule.jl:73](../../../source/kernel/reference/ReferenceModule.jl#L73) ⬜, [ReferenceStep.jl:13](../../../source/kernel/reference/ReferenceStep.jl#L13) ⬜, [ReferenceInterface.jl:1](../../../source/kernel/reference/ReferenceInterface.jl#L1) 🔒
- Evidence:
  - History in source: `ReferenceCase.jl:286` ("The migration guard's message"), `:512-515` ("which is why it went"), `:526-527` ("the word is gone rather than left to mislead"); `ReferenceRules.jl:877-879` ("the retired catch-all", "meanwhile"); `ReferenceModule.jl:17-18` ("just multiplied import headers"), `:73-76` ("the user's ruling, 2026-08-24", "it always had"); `ReferencePath.jl:182` ("exactly as before"); reference.md:339-340 and :606-607; the test names "the June 2026 regression" (`ReferenceEvalTest.jl:120`) and "moved to the visual test suite" (`ReferenceBuilderTest.jl:169`).
  - Misplaced or stale comments: `ReferenceCase.jl:281-286` describes `_` and `__` above the constant of the migration message; `ReferenceRules.jl:435-439` sits above the `any` branch but describes the gap; `ReferenceRules.jl:813` describes the range above the glob line; `ReferenceStep.jl:13-21` is a banner with no code under it; `ReferenceStep.jl:226-228` speaks of "the `type` field a step may carry", which no navigation step has; `ReferenceStep.jl:41-49` repeats the module docstring (PAR-TIGHT-COMMENTS); the `@reference` docstring puts its "Use it to" block between "left = outermost:" and the list that the colon introduces (`ReferenceBuilder.jl:165-182`).
  - The header of `ReferenceInterface.jl` (sealed) says the seam defaults live in `ReferenceStep.jl`; they live in `ReferenceSyntax.jl:274`, `ReferenceCase.jl:746`, `ReferenceRules.jl:153` and `ReferenceBuilder.jl:87`.
  - PAR-ONE-BASED-INDEXING states no exception for the 0-based index of `ref"…"`, which plan/done/reference-pattern-vocabulary.md (step 9) decided.
- Rule: code-quality-rules.md §2 ("A comment says what is, never what was"); PAR-TIGHT-COMMENTS; code-quality-rules.md §1 (a contract fragment says where each body lives).
- Fix: delete the history; move each misplaced comment to its code; record the `ref"…"` exception in architecture-invariants.md.
- Reach: `ReferenceCase.jl`, `ReferenceRules.jl`, `ReferenceModule.jl`, `ReferencePath.jl`, `ReferenceStep.jl`, `ReferenceBuilder.jl`, two tests, reference.md, architecture-invariants.md; `ReferenceInterface.jl` (sealed).

## Accepted before, not raised again

No prior audit of this layer exists (`plan/done/` has no `reference-layer-audit.md`). These decisions stand in plans, and this report does not argue with them:

- Two matchers of one pattern AST, the interpreter normative and the codegen a differential-tested fast path, held by the conformance corpus (plan/done/reference-rules-macro.md, plan/done/reference-pattern-vocabulary.md). L11-2 reports only the forms the corpus does not hold, and L11-10 reports the placement.
- `ref"…"` shifts a 0-based index and keeps `**` a whole component (reference-pattern-vocabulary.md, step 9). L11-25 asks only for the note in the invariant.
- The retired arm words (`prefix`, `at_or_below`, `at_or_above`) and the bare `_` arm raise with a message (step 8, the 113 catch-alls). L11-25 reports only the history wording around them.
- The step types are `@document [C, M]` layout families, the bare name on the C layout (the owner's ruling of 2026-08-24, in the module docstring). L11-11 reports the selection field, the mutable `M` layout and the reactive `type` cells, which the ruling does not name.
- `ReferencedDocument` acts like its document, is not a subtype of `Reference` or `Document`, converts to both, and a direct write through it stays possible but discouraged; `get_parent` takes a root (plan/pending/the-assistant-reaches-a-referenced-document.md, D2, D5, D6, D9, D22).
- The addition of `match_reference_step_value` to the sealed `ReferenceInterface.jl` (accepted 2026-09-20) and the docstring sentence in the sealed `ReferenceSearch.jl` (2026-09-23).
- Reactive cells hold `Any`. A private helper is outside the rule of three positional arguments (the owner, 2026-09-22). A test function is outside the size budget.

## Checked and clean

- PAR-INTERFACE-DECLARES-ONLY: `ReferenceInterface.jl` holds two abstract types and six bodiless generics, all exported; no default, struct or state.
- PAR-QUALIFIED-EXTENSION: the header imports exactly the two names it extends; every `Base` method is qualified; higher packages extend the seams qualified (`ReferenceModule.build_reference_step`).
- PAR-PACKAGE-CHAIN and the layer order: the layer uses only `CellModule`, `CellStructModule` and `DocumentModule`, and names no projection, operation or device.
- The opaque-payload pattern: the reference layer never names `Projection`; `.proj` registers from the projection layer.
- PAR-REFERENCE-DSL: `@reference` folds `::T` at construction, and `_strict_check` rejects an under-typed literal with its file and line.
- PAR-ONE-BASED-INDEXING, outside L11-1: `ElementReferenceStep(i)` is `RangeReferenceStep(i - 1, i)`, `[i, j]` is `(i - 1, j)`, evaluation reads `start + 1`, and the matchers bind `start + 1` for `[i]`.
- PAR-EMPTY-PATH-IS-SELECTION, outside L11-2: `∅`, `@reference()`, and the `nothing` methods of `strip_reference_types`, `try_evaluate_reference`, `match_reference_pattern` and `apply_reference_rules` keep the two apart.
- PAR-FOLDED-CHECKPOINTS: construction folds, `search_references` annotates its results, and `strip` / `annotate` / `fold` exist as the rule requires.
- PAR-PREFER-REFERENCE-RETARGET: the layer adds no `read_intent`; nothing to check.
- PAR-NO-PROJECTION-GLOBALS and PAR-PER-EDITOR-STATE, outside L11-12: no module-level mutable state.
- The argument rule: no public definition takes more than three positional arguments; the two matcher seams are on the protocol list of `test/suite/arguments.jl`.
- Naming, outside L11-24: the module file name, the fragment headers (`# Fragment of ReferenceModule — …`), verb-first functions, `is_` predicates, the `Exception` suffix.
- PAR-MARK-BROKEN-TESTS: no `@test_broken` without a reason; the one violation is the unmarked Error of L11-18.
