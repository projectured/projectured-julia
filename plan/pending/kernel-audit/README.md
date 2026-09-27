# The re-audit of the kernel, layer by layer

The owner asked for a review of the whole shape of the kernel and a re-audit of each of its 23
layers, with one report of findings for each layer, sorted by category. This folder holds that
work: this index and 23 reports, `01-fault.md` to `23-playback.md`. The audit changed no file of
the repository.

- **Commit:** `15b40434` on main, 2026-09-27.
- **Totals:** 329 findings: 20 High, 134 Medium, 175 Low.
- **The main result:** 15 of the 20 High findings are in files that are not sealed, and most
  of them have a small fix. Five High findings need an edit of a sealed file: L01-1, L01-2 and
  L03-1 in the code, and L09-1 and L09-2 in a docstring.

## How the audit ran

1. Eleven auditors read the layers in full, with their tests, the rules in
   `documentation/rule/`, the design documents, the earlier audit plans, and the users of each
   name in projectured-julia, omnet-julia and inet-julia. Small layers shared an auditor. Each
   layer has its own report.
2. The lead checked every High finding against the code. A line "Checked by the lead" in a
   finding says how. Seven High findings were proved by a run: L03-1, L10-1, L10-2, L17-1 and
   L18-2 by a small program, and L18-3 and L22-1 by the argument guard.
3. The baseline of `test_kernel()` on `15b40434`: 2407 pass, 3 fail, 3 error. The six failures
   are the known ones (L10-14, L11-18).
4. The static guards on the kernel:
   - The layering guard, the export guard, the naming guards and the documentation guards find no
     violation in `source/kernel/`.
   - The argument guard `test_arguments()` fails on main with five violations. Three are in the
     kernel: `Tool.jl:30` (L18-3), and `DocumentEdits.jl:56` and `:77` (L22-1).

## Categories and severity

Each finding has one category:

- **Correctness:** a behaviour that is wrong or can fail.
- **Architecture:** a break of a `PAR-…` rule, a layer rule or a package rule.
- **Shape:** abstraction, cohesion, dead code, redundancy, a thing in the wrong layer.
- **State:** state that is shared between editors, thread safety, leaks.
- **Types/performance:** abstract fields, unintended `Any`, work on a hot path.
- **Naming:** a break of `naming-rules.md`.
- **Documentation:** docstrings, comments, guides, false or stale text.
- **Tests:** behaviour with no test, a test that asserts the wrong thing, unmarked failures.

Each finding also has a severity:

- **High:** a user or a caller can get a wrong result, a crash, a hang or a leak. A failure of a
  guard also counts as High.
- **Medium:** a break of a rule or a design fault, with no failure seen now.
- **Low:** text, names and small cosmetic faults.

| Category | High | Medium | Low |
| --- | ---: | ---: | ---: |
| Correctness | 15 | 58 | 41 |
| Architecture | 0 | 26 | 5 |
| Shape | 2 | 8 | 47 |
| State | 3 | 7 | 1 |
| Types/performance | 0 | 3 | 7 |
| Naming | 0 | 3 | 16 |
| Documentation | 0 | 12 | 44 |
| Tests | 0 | 17 | 14 |
| **Total** | **20** | **134** | **175** |

## The layers

| # | Layer | Seal | High | Medium | Low | The most important finding |
| ---: | --- | --- | ---: | ---: | ---: | --- |
| 1 | [fault](01-fault.md) | 8 of 8 🔒 | 2 | 4 | 12 | After 64 distinct keys, a new fault is lost with no report (L01-1). |
| 2 | [performance](02-performance.md) | 3 of 3 🔒 | 0 | 3 | 5 | The switch of the counters comes from an environment variable that the package cache does not track (L02-1). |
| 3 | [cell](03-cell.md) | 7 of 7 🔒 | 1 | 5 | 7 | A reader that catches a failed computation never computes again (L03-1). |
| 4 | [struct](04-struct.md) | 3 of 3 🔒 | 0 | 0 | 10 | The parse of a struct body skips an unknown field form with no error (L04-1). |
| 5 | [clock](05-clock.md) | 2 of 2 🔒 | 0 | 1 | 3 | A write of the heartbeat during a computation can stop a reader of the clock (L05-1). |
| 6 | [event](06-event.md) | 9 of 9 🔒 | 0 | 2 | 13 | The key names exist only as prose, so each backend chooses its own (L06-1). |
| 7 | [device](07-device.md) | 5 of 5 🔒 | 0 | 2 | 3 | Only a method in the SDL package steps the zoom of a `Display` (L07-1). |
| 8 | [gesture](08-gesture.md) | 2 of 2 🔒 | 0 | 0 | 4 | While a chord waits, other events overtake its keys (L08-1). |
| 9 | [backend](09-backend.md) | 3 of 3 🔒 | 2 | 6 | 10 | Ctrl+Z and other letter shortcuts can not fire in the SDL application (L09-1). |
| 10 | [document](10-document.md) | 2 of 10 🔒 | 3 | 12 | 11 | `search_documents` finds only the first document that holds an equal value (L10-1). |
| 11 | [reference](11-reference.md) | 2 of 13 🔒 | 1 | 18 | 6 | A step indexes a `String` by byte, not by character (L11-1). |
| 12 | [selection](12-selection.md) | 3 of 3 🔒 | 0 | 5 | 5 | A caret between two documents selects the next document (L12-1). |
| 13 | [operation](13-operation.md) | 0 of 7 | 1 | 10 | 5 | "-5" typed into an empty number gives 5 (L13-1). |
| 14 | [intent](14-intent.md) | 0 of 2 | 0 | 3 | 5 | `CollectedIntentsOperation` declares no way back (L14-1). |
| 15 | [binding](15-binding.md) | 0 of 4 | 0 | 6 | 8 | The lookup never finds a table that is declared on a concrete type with parameters (L15-1). |
| 16 | [iomap](16-iomap.md) | 2 of 4 🔒 | 0 | 3 | 6 | The reconcilers run a child printer inside their own computation (L16-1). |
| 17 | [projection](17-projection.md) | 0 of 9 | 1 | 11 | 15 | A template child list that is a thunk prints once and then stays fixed (L17-1). |
| 18 | [tool](18-tool.md) | 0 of 8 | 4 | 11 | 14 | A print of more than 64 KiB in `execute_julia_code` blocks the editor task (L18-2). |
| 19 | [llm](19-llm.md) | 0 of 6 | 1 | 1 | 7 | The Anthropic adapter throws on the first event of every stream (L19-1). |
| 20 | [agent](20-agent.md) | 0 of 5 | 1 | 6 | 5 | A turn has no time bound, so one silent provider locks the assistant (L20-1). |
| 21 | [feed](21-feed.md) | 0 of 3 | 1 | 4 | 2 | The session feeds share a wake and a document between editors (L21-1). |
| 22 | [editor](22-editor.md) | 0 of 9 | 1 | 16 | 14 | The inbox stays open after the loop ends, so a caller can wait for ever (L22-3). |
| 23 | [playback](23-playback.md) | 0 of 2 | 1 | 5 | 5 | `play_live!` runs a second frame loop that leaves out the feeds and the fault report (L23-1). |

## The High findings

| ID | Finding | How checked | Sealed file in the fix |
| --- | --- | --- | --- |
| L01-1 | After 64 distinct keys, a new fault gets no report on any tier. | code | yes |
| L01-2 | Each entry into the safe mode attaches one more fault log, and none is detached. | code | yes, or an unsealed alternative |
| L03-1 | A reader that catches a failed computation stays stale after the input is fixed. | run | yes |
| L09-1 | The backends name different letter keys: Ctrl+Z, Ctrl+Y and Ctrl+F never fire on SDL, and Ctrl+S, Ctrl+O and Ctrl+W never fire in the browser. | code | the key rule in a docstring |
| L09-2 | A side button of the mouse makes a right click on SDL and a left click in the browser. | code | a docstring |
| L10-1 | `search_documents` finds only the first document that holds an equal scalar value. | run | no |
| L10-2 | The path walk does not cut a cycle through documents. A list of three linked nodes gives about 2^32 paths at the default depth. | run | no |
| L10-3 | `sync_document!` stores a leaf `Vector` by reference, so a later change in place reaches no reader. | code | no |
| L11-1 | An element step indexes a `String` by byte, so non-ASCII text gives a wrong character or a throw. | code | no |
| L13-1 | A number text that does not parse yet is lost: "-5" typed into an empty number gives 5. | code | no |
| L17-1 | 33 template rules with a thunk child list do not follow an edit of an optional field, and a write of `nothing` makes the output throw. | run | no |
| L18-1 | With no declared API, the documentation tools read only the kernel, and the code tool reads every package. | code | no |
| L18-2 | A print of more than 64 KiB inside `execute_julia_code` blocks the editor task. | run | no |
| L18-3 | The `Tool` constructor fails the argument guard. | guard | no |
| L18-4 | `execute_julia_code` swaps the streams of the process, so other editors print into the answer. | code | no |
| L19-1 | The Anthropic adapter names an undefined `input_tokens` on the first event of a stream. | code | no |
| L20-1 | An agent turn has no time bound. | code | no |
| L21-1 | The log and statistics feeds default to process-wide stores, so two editors share a wake and a document. | code | no |
| L22-1 | `insert_elements!` and `delete_elements!` fail the argument guard. | guard | no |
| L23-1 | `play_live!` runs its own frame loop without the feeds, the barriers and the clock tick. | code | no |

## Themes across the layers

1. **A wrong result with no error.** L01-1, L03-1, L10-1, L10-3, L13-1 and L17-1 each lose data
   or show stale data, and nothing tells the person. They are the most urgent group.
2. **Waits and walks with no bound.** L10-2, L18-2, L18-9, L20-1, L21-5, L22-3, L22-4 and L22-5
   can hang an editor or a caller.
3. **A catch-all that also stops the exceptions that mean "stop".** L01-8, L10-10, L11-5, L20-6
   and L22-11 catch `InterruptException`, and so does `execute_julia_code` (L18-10). The two sentences of
   PAR-REPORT-NEVER-THROWS conflict at this point (L01-8), so the owner must decide first.
4. **State shared between editors.** Inside the kernel: the process streams (L18-4), the method
   table of the rules (L11-12) and the guide registry (L18-13). Outside the kernel, the session
   stores of the log, the statistics and the fault log are shared by all editors (L21-1, L22-14,
   L22-15, and a note in L01).
5. **Faults of the reactive model.** L03-1, L03-2 with L05-1, L03-3, L10-3, L16-1, L17-1, L17-5
   and L17-15. The engine faults are in the sealed cell layer.
6. **One concept, several readings.** The key vocabulary (L06-1, L09-1), the two matchers of the
   pattern language (L11-2), the modifiers (L06-3), the timeline format (L23-4), the count base of
   the element builders (L13-9), and a caret against an element (L11-8, L12-1, L17-2).
7. **Surface with no user.** Half of the reference layer is a pattern language with no user in
   production code (L11-10). Also: the pure printer pair (L17-9), the playback layer (L23-5), and
   exports with no user in L06-7, L14-5, L15-9, L18-22 and L22-24.
8. **Seams outside their interface files.** L15-2, L17-10, L22-12, and a seam in the wrong layer
   (L01-12).
9. **Stale guides.** The design documents of most layers describe an older state:
   `document.md` (L10-13), `reference.md` (L11-16), `devices-and-backends.md` (L06-14, L09-17,
   L15-5), `editor.md` (L22-29), `projection-system.md` (L16-2, L17-27), `cell.md` (L03-12) and
   `agent.md` (L19-7, L20-11). The law is wrong in places too: L01-5 and L22-28 (`run_editor!`
   and the barriers), L01-17, L02-6, L05-3 and L10-13.
10. **Tests.**
    - Six failures on main are not marked broken (L10-14, L11-18).
    - Three tests assert a defect as correct (L01-3, L01-7, L10-2).
    - Several layers have no kernel test of their own: the selection writers (L12-5), intent
      (L14-3), iomap (L16-3), llm (L19-9), agent (L20-7), projection (L17-12) and playback (L23-6).

## Findings that two layers report

Each report looks at a fault from the side of its own layer. These findings are about the same
fault, so fix each pair together.

| Fault | Findings |
| --- | --- |
| A write during a computation is lost | L03-2, L05-1 |
| The key vocabulary | L06-1, L09-1 |
| A caret between elements against an element | L11-8, L12-1, L17-2 |
| Shared mutable steps | L11-13, L12-2 |
| The reader bridge drops the route and the labels | L14-4, L17-3 |
| Gesture seams outside the interface file | L15-2, L17-10 |
| One feed that throws stops the others | L21-2, L22-6 |
| Calls between frames outside every barrier | L21-3, L22-7 |
| The inbox drain has no bound | L21-4, L22-5 |
| A post into a full inbox from the editor task | L21-5, L22-4 |
| `run_editor!` and the barriers in the text | L01-5, L22-28 |
| The zoom works only on SDL | L07-1, L22-23 |
| The element builders and the edit verbs | L13-9, L22-1 |
| The `read!` name against `Base.read!` | L18-1 (note), L22-13 |
| No read timeout in the adapters | L19-2, L20-1 |

## Decisions for the owner

These findings need a decision before anyone can fix them:

- **L01-8:** which sentence of PAR-REPORT-NEVER-THROWS wins, "never throws" or "never catch an
  exception that means stop".
- **L03-1:** the form of a failure that a cell stores: a failed cell that stays valid and throws
  again on each read, or another form.
- **L07-1:** whether to reopen the decision of the device audit and step the zoom in the kernel,
  so that the web backend can zoom.
- **L11-10:** whether the pattern language of the reference layer stays in the kernel.
- **L18-3 and L22-1:** a new signature, or a `# @positional:` marker. The owner approved the
  signatures of L22-1 in D24.
- **L21-1:** whether a feed belongs to one editor, and whether the session stores stay
  process-wide.
- **L23-5:** whether playback stays in the kernel, or becomes a source of input around
  `run_editor!`, as `VideoBackend` does.

## A proposed order of work

This order is my recommendation. The owner decides the order.

1. Fix the High findings in the files that are not sealed. Each one is small: L10-1, L10-2,
   L10-3, L11-1, L13-1, L17-1 and L19-1.
2. Add bounds to the waits: L18-2 with L18-4, L20-1, L22-3 and L22-4.
3. Ask permission for the sealed engine and fault files, and fix L03-1, L03-2 and L03-3 there.
   Fix L01-1 to L01-3 together with the pending fault plan, because its step D1 opens the same
   files.
4. Give the event layer one key vocabulary, and make the backends follow it: L06-1, L09-1 and
   L09-2.
5. Make the decisions above.
6. Correct the guides and the law, and add the missing tests.

## Findings not proved

These findings are Suspected: the auditor read the code, but the effect needs a run to prove
it. L03-9, L04-4, L06-11, L09-9, L09-10, L10-11, L10-22, L11-23, L12-1, L13-3, L13-6, L16-4,
L21-4, L21-5, L22-4, L22-5, L22-10, L22-13 and L22-16. Some Confirmed findings also name an
effect that nobody ran. Their reports say which.

## Found outside the kernel

The audit found these faults outside `source/kernel/`. They are not in the counts above.

- **The process and FSM domains print each node as `⟨Type⟩` on main.**
  - `test_process()` gives 196 pass and 108 fail.
  - The cause is commit `154f3306` (2026-09-23). It adds `Document => JuliaObjectToSyntaxLeaf()`
    as the last entry of the Julia table, and the first entry that matches wins.
    `ProcessToSyntax()` and `FsmToSyntax()` copy that table and add their own entries after
    the catch-all.
  - The FSM suite was not run, but it has the same construction.
- **The argument guard also fails outside the kernel.** It reports `Application.jl:599` and
  `TextMeasure.jl:223`.
- **The test package `ProjecturedProcessTest` does not precompile in its own environment.**
- **The adapters and the session stores** are in the reports: L19-1 and L19-2 are in
  `source/anthropic/` and `source/ollama/`. The session stores of L21-1 and L22-14 are in
  `source/log/`, `source/statistics/` and `source/fault/`.
