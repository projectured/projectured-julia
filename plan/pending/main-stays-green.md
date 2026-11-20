# Main stays green

> **Status (2026-11-20): approved, in progress.** The owner asked for this work on 2026-11-20
> and approved the plan for implementation the same day ("yes, implement it"). The work is on
> the branch `main-stays-green` in the worktrees `projectured-julia-main-stays-green` and
> `omnet-julia-main-stays-green`. Step 1 runs.

## 1. The purpose

The owner, 2026-11-20: "some projectured and omnet tests fail on main, it prevents agents
working in new worktrees to assume that all tests either pass or marked broken. let's change
that so these agents don't have to run the tests before and after to make sure that they have
the same fails and errors. The main branches should always be green with all tests either
passing or being marked broken."

So this plan does two things:

1. It makes `main` of both repositories green now. Each check passes, or it has a marker with
   its reason.
2. It adds a rule that keeps `main` green. Then an unmarked `Fail` or `Error` on a branch is a
   fault of that branch, and no run of `main` is necessary to see it.

## 2. What exists

- **The rule is written, but main does not follow it.** The testing guide says: "every
  currently-failing assertion is marked with `@test_broken`"
  ([testing-guide.md](../../documentation/guide/testing-guide.md), "Marking known-failing
  tests"). The marker is `# @broken: <reason>` on the line above `@test_broken`.
  projectured-julia has 79 such markers and 9 `@test_skip`. omnet-julia has 10 markers.
- **The CI of projectured-julia on GitHub is red.** Each of the last 8 runs on `main` failed or
  was cancelled. Run 44521510104 (commit `dd36cc61d`, 2026-11-19): 9 of 39 jobs failed. The job
  of `test_integration` stopped at its limit of 180 minutes, with 596 failures before the stop.
  The static guards fail: `arguments.jl` 6, `documentation.jl` 10, `exports.jl` 36, `style.jl`
  1.
- **The whole run of projectured-julia.** The branch `tests-run-fast` (commit `fd51372fe`,
  2026-11-20) ran all 751 parts of all suites in `environment/all`, with two workers of 5 GB.
  48 parts are not green: 745 fails, 40 errors, 1 part at its time limit
  (`test_process_debug`, which hangs at `ProcessDebugTest.jl:185`), and 2 parts over their
  memory (`test_application`, `test_window_frame_guards`). The largest are `test_repls` (361),
  `test_catalog` (211), `test_exports` (38), `test_mouse_clicks` (23) and
  `test_text_navigation_invariants_all` (16).
- **omnet-julia has no CI.** Runs of `main` on 2026-11-19: `test_legacy` 3512 pass, 23 fail,
  68 error. `test_ide` 2745 pass, 23 fail, 12 error, and one run of it stopped at a cap of
  12 GB. `test_presentation` did not end in 4 hours. The other suites of `test/runtests.jl`
  have no recent result.
- **Some checks fail only at some times.** Notes of earlier sessions name these:
  `FeedsTest.jl:260` (frame time under 45 ms), `FormulaFrameGuardTest.jl:67` (time ratio),
  `WindowFrameGuardTest.jl:325` (a time ratio that is `@test_broken` and passes at times),
  `TaskWorkItemTest.jl:171` (a wait of 30 s), `TaskVerbsTest.jl:102`,
  `SystemProcessTest.jl:332` (a wait of 10 s), `SemanticTokensTest.jl:111-113` (a wait of
  10 s), `ProcessDebugTest.jl:185` (a race that can hang), and in omnet-julia
  `CampaignAssistantTest.jl:79` and `:83` (a wait of 5 s).
- **Some checks depend on the other packages in their process.** For example,
  `test_build_editor`, `test_agent_work` and `test_assistant_work` fail when every test
  package is loaded, and pass in their own environment.
- **The agents compare with main.** The memory of the assistant holds 130 notes about
  failures of `main`. Agents read them and run `main` beside each branch. The plan
  `the-tests-run-fast` counted 145 such runs of a base commit in `/var/tmp/bounded-run`.
- **The plan `the-tests-run-fast`** (approved 2026-11-20, in progress in the worktree
  `projectured-julia-tests-run-fast`) gives the tools that this plan uses:
  `tool/run-tests.jl` runs each part in a worker with a time limit, and writes a record of
  the counts of each part. Its step 9 also says to mark the known failures of `main`.

## 3. Decisions

Each decision is proposed by the assistant. The owner approved them with the plan on
2026-11-20.

- **G1. Green means one thing in each repository** (proposed by the assistant, approved with the plan on 2026-11-20). In
  projectured-julia: a run of all parts of the suites of the CI matrix and of the static
  guards with `tool/run-tests.jl` gives 0 `Fail` and 0 `Error`, and each part ends in its time
  limit and its memory. The CI run on GitHub is green too. In omnet-julia: the same for each
  suite that `test/runtests.jl` calls. The suites that run only on request (the suites that
  call a model, the sweeps that no suite calls) are not part of green.
- **G2. A known failure gets the marker that exists, at the narrowest place** (proposed by the
  assistant, approved with the plan on 2026-11-20). The place is one assertion, one example of a walk, or one entry of the list of a
  guard. A guard (exports, arguments, documentation, style, layering, slice edges, catalog
  coverage) gets a list of its known entries, each with its reason. Then a new entry still
  fails the guard. Rejected: one marker for a whole testset or a whole guard, because it hides
  the next fault of the same place.
- **G3. A check that fails only at some times gets no `@test_broken`** (proposed by the
  assistant, approved with the plan on 2026-11-20). A pass of `@test_broken` is an error, so such a marker makes the run red at
  times. A check of a result that waits a fixed time gets a wait for its condition, with a
  bound that holds under the load of the shared machine. A check of speed (a time, or a ratio
  of times) gets `@test_skip` with a `# @broken:` reason. A check is in this group when its
  result differs between two runs of one commit, between the run and CI, or when a note names
  it.
- **G4. A part that hangs or passes its memory is not green** (proposed by the assistant, approved with the plan on 2026-11-20). A
  hang gets a fix of its race when the cause is clear from its stacks. Else the case that
  hangs gets `@test_skip` with the reason. A part that needs more memory than a worker gets a
  split at its top-level testsets, or the documented run gets workers with the memory that
  the largest part needs, at most 8 GB.
- **G5. A check that depends on the other packages in its process gets `@test_skip`** (proposed
  by the assistant, approved with the plan on 2026-11-20), with the reason and the name of the package that changes its result. A
  `@test_broken` can not work here, because the check passes in one process and fails in
  the other.
- **G6. The rule that keeps main green** (proposed by the assistant, approved with the plan on 2026-11-20):
  - Before a land on `main`, the branch runs all parts of its repository. The land needs 0
    unmarked `Fail`, 0 `Error`, and an end of each part.
  - A branch adds no marker to a check that passes on `main`. A new marker for a fault that
    the branch did not make needs the word of the owner, and the report of the land names it.
  - omnet-julia reads projectured-julia from the main checkout. So a land of projectured-julia
    also runs the fast parts of omnet-julia against the branch. A failure there stops the land
    in the same way.
  - A red CI run on `main` is a fault of `main`. The session that pushed fixes it, or marks it
    with the word of the owner, before more work lands.
- **G7. The CI job of `test_integration` ends in its time** (proposed by the assistant, approved with the plan on 2026-11-20). It
  splits into two or three jobs with the filters `only` and `skip` of the runner, each under
  180 minutes. Rejected: a larger limit, because one job of more than 3 hours makes each run
  slow.
- **G8. This plan does the markers, not step 9 of `the-tests-run-fast`** (proposed by the
  assistant, approved with the plan on 2026-11-20). Step 9 there keeps the store of the records
  of `main` and `compare_records`, which are done (commit `cd1874d5c` on the branch
  `tests-run-fast` says so). This plan uses the runner of that branch, and that branch changes
  each suite file. So the branch `main-stays-green` starts on a merge of `main` and
  `tests-run-fast`: `d732e6e2b` in projectured-julia (`main` `8e792dc15` with `89417570d`) and
  `bae20cf4a` in omnet-julia (`main` `21d013f2f` with `16c3069c3`). After `tests-run-fast`
  lands, `git rebase --onto main <merge> main-stays-green` moves only the commits of this plan.

## 4. Steps

Do the work in the worktrees `projectured-julia-main-stays-green` and
`omnet-julia-main-stays-green`, on the branch `main-stays-green`. Make one commit for each
step. Run each Julia process with `bounded-run`, and each whole run in `bwrap
--unshare-net`.

- [ ] 1. **The list.** Run all parts of each repository two times on one commit of `main`.
  Read the last CI run on `main`. Write each part that is not green into section 5 of this
  plan, with each check by its file and line, and its kind: fail, error, sometimes (G3),
  process (G5), hang or memory (G4). **Done when:** section 5 names each check that is not
  green in the two runs and in CI.
- [ ] 2. **The fails and errors of projectured-julia (G2).** Mark each check of kind fail or
  error, and give each guard its list of known entries. **Done when:** a run of all parts on
  the branch has no unmarked `Fail` or `Error` outside the kinds of step 3.
- [ ] 3. **The other kinds in projectured-julia (G3, G4, G5).** Change the waits, mark the
  checks of speed and of process, fix or skip each hang, and fit each part in its memory.
  Split the CI job of `test_integration` (G7). **Done when:** two runs of all parts on the
  branch are green. With the word of the owner, the branch is pushed, and a CI run of the
  branch is green.
- [ ] 4. **omnet-julia (G2 to G5).** Do steps 2 and 3 for omnet-julia, against the branch of
  step 3. **Done when:** two runs of all parts of omnet-julia on its branch are green.
- [ ] 5. **The rule (G6).** Write the rule into the `CLAUDE.md` of both repositories and into
  the testing guide. Replace the 130 notes about failures of `main` in the memory of the
  assistant with one note: `main` is green, and an unmarked failure is a regression. **Done
  when:** the texts say the rule, and each branch lands with the word of the owner, first
  projectured-julia, then omnet-julia. Before the land, rebase each branch on `main`, run all
  parts again, and mark the new failures of `main` by G2 to G5.

### What the implementation found

- **The runs of step 1** run in the detached checkout `projectured-julia-main-stays-green-base`
  at the merge `d732e6e2b`, with its own depot, so that the marks of step 2 do not change a run
  while it goes. The command: `tool/run-tests.jl --workers 2 --threads 2 --record …` over
  `ProjecturedTest test_all`, `ProjecturedTest test_repository` and the ten suites of the CI
  matrix that `test_all` does not call (OpenRouter, Console, PDF, Web, MCP, SDL, Tulip, Video,
  ODBC, Builder), with the default worker memory of 6 GB, the default limit of 600 s, `taskset
  -c 24-27`, and `bwrap --unshare-net`.
- **"All tests" in omnet-julia is more than `test/runtests.jl`.** That file calls 11 test
  packages and three suites of its own. It does not call 15 test packages, among them
  `OmnetIdeTest` (`test_ide`), the ten legacy sample packages, `OmnetLegacyResultTest`,
  `OmnetCosimPresentationTest`, `OmnetDynamicsTest` and `OmnetMeasureTest`. So G1 for
  omnet-julia covers the suite of each test package, except a suite that calls a model.
- **The runner can not run `test/runtests.jl` of omnet-julia as a part.** A worker includes a
  `.jl` file into `Main`, and that file runs the whole suite when it loads. So the whole run of
  omnet-julia names the suite of each test package, and the three suites that only
  `test/runtests.jl` defines run in one small process of their own.
- **A guard keeps a list of its known violations** (`test/suite/known.jl`). The key of an entry
  is the text of the violation without its line number. A listed violation does not fail the
  guard, and its test counts it as broken. A violation that no entry excuses fails, and so does
  an entry that excuses none. The guards of arguments (6), exports (37), style (1) and
  documentation (10) have their lists. The exports guard had a list of modules that are not
  migrated yet; its new list is narrower, one violation for each entry. `check_layering` and
  `check_slice_edges` take the keyword `known` in the same form.
- **A test that can set what it reads sets it, in place of a skip** (a choice of the
  implementation under G5, which the owner did not decide): the history sweep prints fresh
  documents, the memory checks of the explorer count from their start, and the builder test sets
  a plain logger. Each such change is in the test, not in the code that it tests.
- **The CI split went into commit `aa7658d3d`** with the marks of run 1, although its message
  does not say so.
- **A worker of the runner loads every test package of the run.** So a check whose result
  depends on the packages in its process gives one result in CI, where each test package has
  its own environment, and another in the run of all parts. The notes of earlier sessions name
  `ProjecturedMCP` (an agent turn starts an MCP server for a fake editor), the Markdown domain
  (`WorkPlanTest.jl:122`, `:125`) and the umbrella.

## 5. The list

### projectured-julia

Two runs of all 765 parts on `d732e6e2b` (2026-11-20, 1 h 44 min each, peak 12.2 GB): 808 fails
and 88 errors, then 808 and 86. Each part ended in its limits. The two runs differ only in
`test_task_work_item` and `test_build_executable`. The CI runs 44521510104, 44493898739 and
44337950246 on `main` add the checks that fail only there.

| Kind | Checks | What the branch does |
|---|---|---|
| guard (G2) | arguments 6, exports 37, style 1, documentation 10, platform layering 9, slice edges 6 | the list of known violations of each guard |
| fail, error (G2) | the catalog walk, the type-in walk and the REPL walk on `text/view` (with the other views of a text); the REPL walk of `graph` (205), `yaml` (106) and eight charts (48); the position and invariant walks of the eight charts (8, 16); the clicks on 23 layouts and cards of widgets; the coverage of 9 types with no atom; graph drag and scroll pane; tooltip frame; math depth; navigator choices; clipboard cut; save under a new name; reload of the last line break; SDL workload and tree; release copy; call site entries; drag over a stub; history palette; MCP surface sentence; pivot search and drop; agent bar usage; the forms of five verbs | `@test_broken` with a reason, in the registry of its walk where it has one |
| stale mark | the flat view of a dictionary (an unexpected pass), the natural render of `appearance/document` | the mark goes |
| sometimes (G3) | `FeedsTest.jl:260`, `FormulaFrameGuardTest.jl:67`, `WindowFrameGuardTest.jl:325` (checks of a time) | `@test_skip` with a reason |
| sometimes (G3) | `TaskWorkItemTest.jl:171`, `LanguageServerConnectionTest.jl:18`, `TextRangeSelectionTest.jl:267`, `SystemProcessTest.jl:332` (a fixed wait) | a wait for the condition with a bound |
| sometimes (G3) | `TaskVerbsTest.jl:102`, `TaskGroupToWidgetTest.jl:440` (a process that ends before its identifier is read) | the process of the test lives a second |
| process (G5) | `HistorySweepTest.jl:118` (CI: the REPL sweep changes the shared documents before it), `ExplorerTest.jl:1928` (CI: the whole memory of the process), `BuilderTest.jl:410` (a logger that an earlier part left) | the test sets what it reads: fresh documents, memory from its start, a plain logger |
| process (G5) | `BuilderTest.jl:1152`, `:1157` (`bwrap` inside the `bwrap` of the run), `WindowFrameGuardTest.jl:310` (fails on each CI run only, cause not found) | `@test_skip` where it fails, with the reason |
| process (G5) | the agent and assistant tests, `AssistantWakeTest.jl:116`, `McpLogTest.jl:55`, `PaneDocumentTest.jl:276`, `WorkPlanTest.jl:122`, `BuildEditorTest.jl:257` | the probe of step 1 names the package that changes each result |
| fault of `tests-run-fast` | `ExampleSweeps.jl:79` (2), `HistorySweepTest.jl:37` and `:124` | fixed on that branch, not marked here |

### omnet-julia

The runs of `test_legacy`, `test_ide` and `test_presentation` on `main` `21d013f2f` of 2026-11-19
give the first list: `test_legacy` 23 fails and 68 errors (marked on the branch), `test_ide` 23 fails
and 12 errors, `test_presentation` 28 failures before its bound of 4 hours. The two runs of all
parts follow.

## 6. Not in this plan

- The fixes of the faults that the markers name. Each marker keeps its reason, and the open
  plan `test-suite-green` keeps its items.
- A CI on GitHub for omnet-julia.
