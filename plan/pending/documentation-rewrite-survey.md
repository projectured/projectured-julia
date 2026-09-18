# Documentation rewrite: the survey findings

**Status (2026-09-17): raw survey data for [documentation-rewrite.md](documentation-rewrite.md).**
This file is not documentation. It holds the ten reports of the read-only survey
of 2026-09-17, at commit `c28e6e30`. Ten subagents checked each claim in the
Markdown files statically against the code, with grep, find and git. No agent
ran Julia.

Use a finding as a lead, not as a fact. Check it against the code before you
change a document. A sample check found the errors below. The reports are
otherwise unchanged.

## Errata

| Report | Finding | Correction |
| --- | --- | --- |
| G1 (domain guides) | "several `plan/pending/` features (duplicate a pane, ... split-pane drag/resize)", and the list `pane-layout.md`, `split-pane-drag-resize.md`, `split-pane-inset.md`, `tabbed-pane-scroll.md`, `widget-transform-pane.md` | These five plans are in `plan/done/`. Only `duplicate-a-pane.md` and `select-a-widget-and-paste-it-into-a-tab.md` are pending. |
| G2 (base-layer guides) | "`EDITOR_DOMAINS` does not exist anywhere in the repository" | It exists at `example/projectured/FileEditor.jl:56`, in the package `ProjecturedExample`. The agent searched only `source/`. `executable/README.md` is correct on this point. |
| C (rules) | `division-terminology.md` is KEEP | It is UPDATE. It says that a slice holds "one or more modules", but `plan/done/one-module-per-slice.md` finished. Its "Slice" entry also holds a history sentence ("the concept folders that were slices of base and visual are each a package of their own"). |
| I (plans) | "No `LICENSE` file exists at the repository root" | The root has `LICENCE-PD` and `LICENCE-COMMERCIAL`. Neither is an open-source licence. |
| A (front door) | The README is correct about the assistant backends | It is not. The README says that the assistant "uses Claude when `ANTHROPIC_API_KEY` is set, and a deterministic offline backend otherwise". `Assistant` has `backend = :none` by default and gives an error on submit. Every example passes `llm = FakeLlm()`, so `run_example("assistant")` never uses Claude. |

## The reports

1. [A — the front door](#area-a--the-front-door)
2. [B — requirement and design](#survey-area-b--requirement-and-design-documents)
3. [C — rules](#survey-area-c--rule-documents-for-contributors)
4. [D — kernel guides, part A](#survey-area-d--kernel-guides-cell-document-macros-projection)
5. [E — kernel guides, part B](#survey-area-e-kernel-b-references-selection-operations-editor-finding-and-selecting-devices-and-backends-agent-stack)
6. [F — procedure guides](#survey-area-procedure-guides)
7. [G1 — domain guides](#survey-area-g1--the-per-domain-guides)
8. [G2 — base-layer and tool guides](#g2--substrate-and-tooling-guides)
9. [H — what works today](#what-a-user-and-a-julia-developer-can-do-with-projectured-today)
10. [I — plan folders](#survey-area-i-plan-folders)
11. [J — the two binary builds](#how-omnet-julia-builds-binaries-and-what-projectured-julia-can-copy) (added later on 2026-09-17, for decision D18)


---

# Area A — The front door

Files surveyed: `README.md`, `CONTRIBUTING.md`, `CLAUDE.md`, `SEALING.md` (path/order check
only), `documentation/README.md`, `documentation/guide/orientation.md`,
`documentation/guide/setup-guide.md`, `documentation/guide/examples-tour.md`,
`documentation/presentation/README.md`, `documentation/presentation/projectured-overview.md`,
`tool/juliac-trim/README.md`, `test/graph/reference/README.md`,
`example/filesystem/fixture/project/README.md` + `doc/guide.md`.

All claims below were checked with `grep`/`find`/`git log`/`Read` against the repository at
its current commit (`c28e6e30`). No Julia was run.

---

## README.md

**Verdict:** UPDATE (facts wrong/stale in several places; the AI-native framing is already
partly present and just needs to move up front). **Audience:** new user (primary), Julia
developer evaluating the library, contributor. **Size:** 417 lines.

| where | category | finding | evidence | fix | confidence |
|---|---|---|---|---|---|
| "Quick start" → Prerequisites | CONTRADICTION | Says "Julia 1.11 or later," but no `Project.toml` in the repo declares `julia = "1.11"` anywhere, and `documentation/guide/setup-guide.md` says "Julia 1.10+" for the same setup. | `grep -rn "^julia = " package/*/Project.toml environment/*/Project.toml` → only `ProjecturedExecutable` (1.6), `ProjecturedBuilder` (1.10), `ProjecturedBench` (1.10); `environment/all/Manifest.toml:3` → `julia_version = "1.13.0"` (the resolved manifest was built with 1.13, newer than either claim). | Either add a `[compat] julia = "1.11"` to the packages that need `[sources]`, or state the real minimum and reconcile with setup-guide.md. | checked |
| "Screenshots" section | MISSING | Six screenshots shown (json, widget, table, syntax, julia, workbench); `asset/image/example/assistant.png` exists, was regenerated **2026-09-16** (the day before this survey), and there is no `chart.png`, `graph.png`, `fsm.png`, `conversation-*.png` despite `chart_example`, `graph_example`, `fsm_example`, `conversation_widget_example`/`conversation_editor_example` all existing. | `ls asset/image/example/`; `git log -1 --format=%ad -- asset/image/example/assistant.png` → `Wed Sep 16 00:15:39 2026`; the six README screenshots are all dated `Tue Jun 23 2026` (three months stale). | Add the assistant screenshot to the hero/screenshot table — it is the single best evidence for the new AI-native framing and is already generated. Generate chart/graph/fsm/conversation screenshots or note their absence. | checked |
| "What works today" — substrate table | STYLE / INCOMPLETE | The 5-row substrate table (Text, Syntax, Graphics, Widget, Collection) disagrees with the "Substrate:" list two screens later in the same file, which has 8 items (adds Pane, Versioning, bounded-sync/Reflection). | README.md lines 257–266 (table) vs line 377 (`Substrate: text · syntax · graphics · widget · pane · collection · versioning · bounded sync`). | Make the table and the guide-list agree; add Pane, Versioning, Reflection rows to the substrate table or drop them from the guide list with a reason. | checked |
| "What works today" / domain & substrate tables | MISSING | Neither table nor any other part of the file ever names these existing packages: `Assistant` (as a package, though the assistant *feature* is discussed at length), `Natural`, `Component`, `Clipboard`, `Dragging`, `Inspector`, `Tooltip`, `GestureHelp`, `GestureLog`, `Pdf`, `Video`, `Serialization`, `FileFormat`, `Builder`, `Odbc`, `Tulip`, `Style`, `Layout`. | `for pkg in …; do grep -ci "$pkg" README.md; done` → all 0 except generic-English collisions (`Style` hits are all "code style"/"public-domain-style", `Layout` hits are all "repository layout"/generic "layout document"). Confirmed by reading `source/style/` (Color, Font, Geometry, Image, TrueType) and `source/layout/` (ConstraintSolver, LayoutToGraphics) — neither package is named even though README's own `StyleText` code sample in the "Every field is a cell" section constructs values from the unnamed Style package. | Name Style and Layout at least, since the doc already uses them; mention Pdf given `write_example_pdf` is documented in setup-guide.md and is a headline feature on the public website. Clipboard/Dragging are worth a line given the website calls out "paste by identity" as a rare capability. | checked |
| Licence section | STYLE (accurate but worth confirming) | The two-line summary of LICENCE-PD/LICENCE-COMMERCIAL is factually accurate: LICENCE-PD really is non-commercial + unmodified-only, and LICENCE-COMMERCIAL really is required for any modification (commercial or not) per its §3 "No modification." | Read both licence files in full; §3 of LICENCE-PD: "No rights to modify… whether for non-commercial or commercial purposes." | No fix needed; this is a correct summary, noted so the rewrite doesn't accidentally break it. | checked |
| Licence section, contact | STYLE | Contact e-mail is `levente.meszaros@gmail.com` (matches both licence files and CONTRIBUTING.md). The public website's contact is a different address, `projectured@gmail.com` (`mailto:projectured@gmail.com`, used 3 times on the landing page). The git identity active in this session is `levente.meszaros@omnest.com`. | README.md:417; `projectured.github.io/index.html` lines 386, 853, 877; conversation's own `userEmail` context. | Decide one contact address for the project-facing surface (repo + site) and use it consistently; not a documentation bug per se, just an inconsistency worth resolving before a public push. | checked |
| "AI-assisted editing" | FRAMING | This section is already the strongest AI-native material in the file (own heading, four bullet points, a Status callout) — good raw material to promote, but it currently sits as the *second* section after "What the design is for," behind a `## AI-assisted editing` divider, rather than being the framing of the whole document per the new brief. | README.md lines 35–72 vs. the brief's requested framing ("Projectional editing is the mechanism, not the headline"). | Restructure so the AI-native framing leads, with projections as the mechanism underneath — the website (see below) already does this and can be the model. | likely |
| Guides → substrate/domain links | LINK | All internal relative `.md` links resolve (checked every link in the file). | `grep -oE '\[[^]]*\]\([^)]+\.md[^)]*\)' README.md` cross-checked against the filesystem — zero missing targets. | none | checked |

---

## CONTRIBUTING.md

**Verdict:** KEEP (small fixes only — it is largely accurate and cross-checks cleanly against
the rule docs it cites). **Audience:** contributor. **Size:** 213 lines.

| where | category | finding | evidence | fix | confidence |
|---|---|---|---|---|---|
| Prerequisites | CONTRADICTION | "Julia 1.11 or later" — same unsupported claim as README.md, same contradiction with setup-guide.md's "1.10+". | See README.md row above. | Fix once, in one place; the other two files should cite it rather than restate it. | checked |
| Running the tests | STYLE (verified correct) | "There is no `Project.toml` at the root" — true; "the whole suite runs in `environment/all`" — true; `test_all()` "about 47 minutes" matches CLAUDE.md's own claim. | `ls Project.toml` → not found; `environment/all/Project.toml` exists. | none | checked |
| Code style → naming | DUPLICATE | The naming-rules summary bullets ("every function name starts with a verb," `is_…`/`has_…`, mutator `!`, no ad-hoc abbreviation) are quoted essentially verbatim from `documentation/rule/naming-rules.md`, and the *same* verbatim block appears a third time in the root `CLAUDE.md`. | Compare CONTRIBUTING.md:110-113 to CLAUDE.md's "Naming" section — near-identical wording; both cite `naming-rules.md` and then restate it anyway. | Cite `naming-rules.md` once; drop the restated bullets from at least one of the two front-door files. `documentation/README.md`'s own rule is "Cite, do not repeat." | checked |
| Code style → tests | CODE-REFERENCE (verified correct) | `test_package_graph()` and `test/projectured/projection/` both exist as claimed. | `grep -n "function test_package_graph" test/projectured/PackageGraphTest.jl` → found; `ls test/projectured/projection/` → populated. | none | checked |
| Adding a new domain checklist | CODE-REFERENCE (verified correct) | `register_natural_syntax!`, `example/projectured/DomainExamples.jl`, `example/projectured/ProjecturedExamples.jl`, `environment/all/Project.toml` all exist and are used the way the checklist describes. | Read `example/projectured/DomainExamples.jl` and `ProjecturedExamples.jl` directly — the `examples` vector and `Example(name, …)` pattern match the checklist. | none | checked |
| Pull request process, step 1 | STYLE | "Fork the repository and create a branch" is a generic external-contributor instruction; it is not contradicted by anything in the rule docs (they don't discuss git workflow), but it does conflict with the user's own global workflow rule (commit to current branch, never auto-branch) if an AI assistant applies CONTRIBUTING.md's process to itself rather than to a human contributor. | CONTRIBUTING.md:161; global CLAUDE.md "Git" section. | Low priority; CONTRIBUTING.md is for human external contributors, this is fine as-is, but worth a one-line note distinguishing "external PR workflow" from "in-repo agent workflow" if the two are ever conflated. | likely |
| Contact | STYLE | `levente.meszaros@gmail.com` — same as README/licences, different from the website. See README row above. | CONTRIBUTING.md:213. | none (tracked once, above) | checked |

---

## CLAUDE.md (root)

**Verdict:** MERGE candidate for large parts (target: README.md + the rule docs it already
cites) — this file is doing double duty as both a pointer and a restatement.
**Audience:** the AI assistant / contributor working via an AI assistant. **Size:** 112 lines.

| where | category | finding | evidence | fix | confidence |
|---|---|---|---|---|---|
| "Naming" section | DUPLICATE | The entire "parts that are broken most often" bullet list is copied verbatim from `documentation/rule/naming-rules.md` (also duplicated a second time in README.md's own reading-order blurb and a third time in CONTRIBUTING.md — see above). | Byte-for-byte comparison of the five bullets in CLAUDE.md vs CONTRIBUTING.md vs the description in README.md's "Naming" section — identical text, three places. | Keep one canonical copy (the rule doc), link from the other two. | checked |
| "Comments and documentation" section | DUPLICATE | This entire section — "Source describes the code as it stands… History goes in the plan…" — restates `documentation/rule/code-quality-rules.md` §2 ("A comment says what is, never what was") almost word for word, including the exact same closing sentence about the grep that finds violations. | `grep -n "A comment says what is" documentation/rule/code-quality-rules.md` → line 115, heading matches; CLAUDE.md:74-89 restates the section's content in full rather than linking to it. | Cut to 1-2 sentences + link, per the doc's own "Cite, do not repeat" rule. | checked |
| "Testing a change" section | DUPLICATE | Near-total overlap with CONTRIBUTING.md's "Running the tests" section and with `documentation/guide/testing-guide.md`'s subject matter (not read in full per the brief, but the test-function catalogue quoted — `test_printer`, `test_reader`, `test_position_navigation`, `test_kernel()`, `test_json()`, walker helpers — matches what CONTRIBUTING.md and README.md both already say). | Compare CLAUDE.md:96-112 to CONTRIBUTING.md:68-94 — same functions, same "about 47 minutes," same "narrowest test" advice, worded differently each time. | Collapse to a pointer at testing-guide.md; this content now lives in three files that can drift independently. | checked |
| "Sealed files" section | CODE-REFERENCE (verified correct) | Correctly restates SEALING.md's rule ("STOP and ask" for a sealed file) without material drift. | Compare to SEALING.md's "What sealed means" section — consistent framing, short enough to not count as harmful duplication. | none | checked |
| Whole file | FRAMING | Entirely process/rule-oriented (naming, comments, testing); carries none of the "what is ProjecturEd for" framing, which is appropriate for its audience (an AI assistant mid-task) but means it will not need much rewriting for the new audience-facing framing — it is not customer-facing. | Full read of file. | No framing rewrite needed here; only trim the duplication. | checked |

---

## SEALING.md — path & order check only (per instructions)

**Verdict:** UPDATE (the inventory itself, not the sealing judgments). **Audience:**
contributor / AI assistant about to touch `source/kernel/`. **Size:** 180 lines.

Per the assignment, this file's *sealing judgments* were not reviewed. What was checked:
every listed path exists under `source/kernel/`, and the list order matches the real include
order rooted at `package/ProjecturedKernel/src/ProjecturedKernel.jl` (resolved recursively
through all 17 `*Layer.jl` fragments and their own `include(...)` calls).

**Result: the inventory has drifted from the real file tree.** 108 paths are listed; 111 files
are actually reachable through the include chain.

| where | category | finding | evidence | fix | confidence |
|---|---|---|---|---|---|
| Layer 1 (cell), Layer 2 (clock), Layer 3 (event), Layer 5 (gesture), Layer 10 (operation), Layer 16 (agent), Layer 17 (editor) | WRONG | 10 listed paths do not exist on disk at all: `cell/PerformanceCounter.jl`, `clock/Clock.jl`, `event/EventPattern.jl`, `gesture/GestureRecognizer.jl`, `operation/Intent.jl`, `projection/ProjectionApi.jl`, `projection/Projection.jl`, `agent/AgentServer.jl`, `editor/Editor.jl`, `editor/Playback.jl`. In every case except the two `projection/` ones, the real file is the same name with a `Module` suffix added (`PerformanceCounterModule.jl`, `ClockModule.jl`, `EventPatternModule.jl`, `GestureRecognizerModule.jl`, `IntentModule.jl`, `AgentServerModule.jl`, `EditorModule.jl`, `PlaybackModule.jl`). Four of the ten (`PerformanceCounter.jl`, `Clock.jl`, `EventPattern.jl`, `GestureRecognizer.jl`) are marked 🔒 **sealed** in the list under their non-existent name. | `ls source/kernel/cell/ source/kernel/clock/ source/kernel/event/ source/kernel/gesture/ source/kernel/operation/ source/kernel/projection/ source/kernel/agent/ source/kernel/editor/`, cross-checked against a Python script that resolves every `include(...)` recursively from `ProjecturedKernel.jl` (111 files) and diffs it against the 108 paths parsed from `SEALING.md`'s bullet list. | Update the 10 stale paths to their real names; re-run the audit protocol on the ones that were sealed under the wrong name, since the seal currently locks a file that is not in the tree. | checked |
| Layer 11 (binding), Layer 13 (projection) | MISSING | 13 real, load-order files are absent from the inventory entirely (not renamed-and-missed, just never added): `cell/PerformanceCounterModule.jl`, `clock/ClockModule.jl`, `event/EventPatternModule.jl`, `gesture/GestureRecognizerModule.jl`, `operation/IntentModule.jl`, `binding/GestureBindingModule.jl`, `projection/ProjectionModule.jl`, `projection/ProjectionInterface.jl`, `projection/ProjectionDefaults.jl`, `projection/ProjectionMacro.jl`, `agent/AgentServerModule.jl`, `editor/EditorModule.jl`, `editor/PlaybackModule.jl`. The `projection/` layer alone is missing 4 files that together implement the core `Projection` interface. | Same diff script; "on disk but missing from SEALING.md" branch of the output. | Add the 13 files to the inventory in load order; `projection/` needs the biggest correction (4 new entries, none of `ProjectionInterface.jl`/`ProjectionDefaults.jl`/`ProjectionMacro.jl`/`ProjectionModule.jl` are tracked at all today). | checked |
| Whole `source/kernel/` inventory | STALE | Because of the above, the listed order diverges from the real include order starting at entry 2 (`cell/PerformanceCounter.jl` vs real `cell/PerformanceCounterModule.jl`) and the divergence compounds through `binding/`, `iomap/`, `projection/`, `tool/`, `llm/`, `agent/`, `editor/` — everything after the `binding/` gap is shifted by at least one position relative to the real file it is meant to describe. | Full recursive-include diff (script output retained for the writer of the doc-rewrite plan on request). | Regenerate the inventory from the real include tree rather than hand-editing it further; this is the kind of drift `documentation/rule/naming-rules.md`'s own rename tooling note warns about (a text-based rename or manual edit missing a spot). | checked |
| Header line | CODE-REFERENCE (verified correct) | "The include order in `ProjecturedKernel.jl` is the authoritative load order" — correct in principle, just not currently reflected in the list below it. | `package/ProjecturedKernel/src/ProjecturedKernel.jl` — the 17-layer top-level include list matches SEALING.md's 17 layer headers exactly (names, order, count). | none — the rule is right, the data under it is stale. | checked |

---

## documentation/README.md

**Verdict:** UPDATE. **Audience:** contributor, and the AI assistant (guides are served as
MCP resources). **Size:** 134 lines.

| where | category | finding | evidence | fix | confidence |
|---|---|---|---|---|---|
| "Every document" table | CODE-REFERENCE (verified correct) | All 22 linked documents in the table resolve to real files. | Checked every `documentation/<path>.md` referenced in the table against the filesystem — zero missing. | none | checked |
| "Every document" table, `package/README.md` row | MISSING (functional) | The table lists `package/README.md` as a servable "reference" document, but the AI-facing guide index (`_guide_roots()`/`_all_guides()` in `source/kernel/tool/Documentation.jl`) explicitly **excludes** anything directly under `documentation/package/` from the bare-name walk, and only descends into per-package *subdirectories* for the namespaced walk — a bare file sitting directly in `documentation/package/` (not inside one of its subfolders) is picked up by neither loop. `read_guide("package/README")` would not find it. | `source/kernel/tool/Documentation.jl:76-83` — the bare walk's skip condition (`occursin(joinpath("documentation","package"), dir)`) and the per-package loop's `isdir(d)` guard, read together; `documentation/package/README.md` is a plain file, not a directory. | Either move the content into a servable guide, or note in this table that `package/README.md` is human-only navigation, not an AI-servable resource — otherwise the AI assistant that this guide is partly written for will fail to find it when told to. | checked |
| "Where to start" section | MISSING | `orientation.md` — the file titled "Orientation — read first, then search" — is never used as a starting point in this file's own "Where to start" list (6 numbered entries, none of them `orientation.md`), even though the table above lists it. It is also never linked from the root `README.md` at all. | `grep -n "orientation" README.md` → no hits; `sed -n '127,135p' documentation/README.md` → the 6-item list omits it; `grep -rln "orientation.md" documentation/ README.md CLAUDE.md CONTRIBUTING.md` → only 2 other docs link it (`architecture-invariants.md`, `editor-derivation.md`), neither a front door. | Either add `orientation.md` as step 0 of "Where to start" (it says it should be read first) or retitle it so it stops claiming a role it isn't given. | checked |
| Cross-repo link | LINK (verified correct) | "The structure is the one omnet-julia uses" links to `../../omnet-julia/documentation/README.md` — resolves. | `ls /home/projectured/workspace/omnet-julia/documentation/README.md` → exists. | none | checked |
| "Two rules that hold everywhere" | CONTRADICTION (self) | States "Cite, do not repeat. A statement that belongs to one document is linked from the others." README.md, CONTRIBUTING.md and CLAUDE.md all violate this rule against each other (see DUPLICATE findings above) — the rule this file states is not followed by the front-door files that predate or sit beside it. | Cross-reference with the DUPLICATE findings in the README.md/CONTRIBUTING.md/CLAUDE.md sections above. | Worth calling out explicitly in the doc-rewrite plan: this file states the governing rule the front door needs to actually follow. | checked |

---

## documentation/guide/orientation.md

**Verdict:** REWRITE (the vocabulary table's "Guide" column is functionally broken — it is
the one thing an AI assistant would actually use this file for). **Audience:** primarily the
AI assistant (per its own framing: "search for them," `resource://guide/<name>`); secondarily
a developer skimming for a term. **Size:** 60 lines.

| where | category | finding | evidence | fix | confidence |
|---|---|---|---|---|---|
| Vocabulary table, "Guide" column | WRONG (functional) | Every "Guide" column entry is a short informal name, not the real guide slug the code computes. The real scheme (from `source/kernel/tool/Documentation.jl`'s `_all_guides()`) is `<slice-folder>/<basename>` for anything under `documentation/package/` (e.g. the real name of the cell guide is `kernel/cell`, not `reactive-cells`; the real name of `documentation/package/kernel/reference.md` is `kernel/reference`, not `editor/reference`). Table values checked one by one: `concepts`→ real `design/editor-concepts`; `architecture`→ real `kernel/architecture` (there is also a `design/system-anatomy.md`, an unrelated second "architecture" doc, so the bare name is additionally ambiguous); `reactive-cells`→ real `kernel/cell`; `macros`→ real `kernel/macros`; `projection-system`→ real `kernel/projection-system`; `higher-order-projections`→ real `kernel/higher-order-projections`; `generic-projections`→ real `kernel/generic-projections`; `editor/reference`→ real `kernel/reference`; `editor/selection`→ real `kernel/selection`; `selection-deep-dive`→ **no such file anywhere in the repository** (see next row); `editor/finding-and-selecting`→ real `kernel/finding-and-selecting`; `debugging`→ real `guide/debugging-guide`; `operations`→ real `kernel/operation` (singular); `editor`→ real `kernel/editor`; `document/workbench`→ real `workbench/workbench`; `devices-and-backends`→ real `kernel/devices-and-backends`. | `ls documentation/package/kernel/` (14 files, all needing the `kernel/` prefix per `_all_guides()`'s `(d, "$pkg/")` rule); `source/kernel/tool/Documentation.jl:49-83` for the naming rule itself. | Regenerate the "Guide" column from the real `_all_guides()` output (or better, have the table auto-derived) so `search_guides`/`read_guide` calls built from this table actually resolve. | checked |
| Vocabulary table, "Selection" row | HISTORY | `selection-deep-dive` is a name that only survives in `plan/obsolete/` and `plan/done/` files today — it is a reference to a document that was renamed or removed as part of a past reorganisation, still cited here as if current. | `grep -rln "selection-deep-dive" .` → hits only in `plan/obsolete/concept-test.md`, `plan/obsolete/concept-document.md`, and 9 files under `plan/done/` (e.g. `documentation-reorganization.md`, `consistency-report.md`) — none under `documentation/` itself except this file. | Replace with the real guide (`kernel/selection`, which already covers this) or drop the column entry. | checked |
| "How to browse" section | DUPLICATE | The `search_api`/`search_guides`/`read_guide` mini-tutorial substantially overlaps the "For AI assistants using MCP" section of `documentation/guide/setup-guide.md` (both explain the same three functions to the same audience). | Compare orientation.md:28-38 to setup-guide.md:98-113. | Keep one, link from the other — same "cite, don't repeat" issue as the top-level files. | checked |
| Whole file | FRAMING | Already domain/AI-neutral in tone (no "only an editor" language); reads as reference material an assistant would consult, which fits the new framing's "AI assistant ... writes and runs Julia against the live editor" without needing much rewording once the Guide column is fixed. | Full read. | Framing is fine; fix the data. | checked |

---

## documentation/guide/setup-guide.md

**Verdict:** UPDATE. **Audience:** new user setting up a session; AI assistant (has its own
MCP section). **Size:** 113 lines.

| where | category | finding | evidence | fix | confidence |
|---|---|---|---|---|---|
| Prerequisites | CONTRADICTION | "Julia 1.10+" directly contradicts README.md and CONTRIBUTING.md's "Julia 1.11 or later," in the same repository, both claimed as the requirement for the exact same `julia --project=environment/all` setup step. | setup-guide.md:12 vs README.md:290-291 and CONTRIBUTING.md:10-11. | Pick one number (see README.md row for the underlying compat-entry evidence — neither 1.10 nor 1.11 is actually enforced anywhere) and use it in all three places, ideally by having two of the three cite the third. | checked |
| "For AI assistants using MCP", step 1 | WRONG (functional) | `Read resource://guide/getting-started` — no guide is named `getting-started`; the real slug for this exact file (per `_all_guides()`) is `guide/setup-guide` (folder `guide/`, basename `setup-guide`). The stale name also appears twice in the kernel source itself (`source/kernel/tool/Documentation.jl:17,38` and `source/kernel/tool/DefaultTools.jl:19`), suggesting the guide file was renamed from `getting-started.md` to `setup-guide.md` at some point and three references were never updated. | `find documentation -iname "getting-started.md"` → nothing; `grep -rn "getting-started" documentation/ source/` → only the stale mentions, no file. | This doc's own bootstrap instructions for an AI assistant send it to a 404. Fix the reference to `resource://guide/guide/setup-guide`; flag the two source-code occurrences for a code fix (out of scope for the doc rewrite, but the doc rewrite should not just copy the same wrong name forward). | checked |
| "Opening examples" | CODE-REFERENCE (verified correct) | `run_example`, `run_example(; workbench=true)`, `run_example(; scrolling=true)`, `run_example(; caching=true)` all correspond to real keyword-accepting call sites; `write_example_image`, `write_example_pdf`, `print_example` all exist in `example/projectured/ProjecturedExamples.jl`. | Read `example/projectured/ProjecturedExamples.jl` in full — matches signatures. | none | checked |
| "Working with references" | CODE-REFERENCE (verified correct) | `@reference` grammar list (`.field`, `[i]`, `{k}`, `[i, j]`, `.field(expr)`, `.point(x, y)`, `.proj(p, sub)`) matches the reference guide it points to. | Cross-checked names against `source/kernel/reference/ReferenceSyntax.jl` presence (not read in full, out of scope, but the file exists and the syntax names match orientation.md's own vocabulary table). | none | likely |
| Whole file | DUPLICATE | The "For AI assistants using MCP" section duplicates `orientation.md`'s "How to browse" section almost entirely (same three functions, same workflow order). | See orientation.md row above. | Consolidate into one MCP-onboarding section, cited from both files. | checked |

---

## documentation/guide/examples-tour.md

**Verdict:** REWRITE (structurally out of date — covers 6 of roughly 90 registered examples,
and the "Available names" list is stale). **Audience:** new user. **Size:** 214 lines.

| where | category | finding | evidence | fix | confidence |
|---|---|---|---|---|---|
| "Available names" list | STALE | Lists 23 example names as "Available names": `json, json_sorted, xml, mixed, syntax, text, object, line_numbering, word_wrapping, widget, widget_tabbed_pane, book, filesystem, collection, reversing, filtering, sorting, focusing, table, math_table, workbench, math, julia, graphics_image`. The real `examples` vector in `example/projectured/ProjecturedExamples.jl` currently has roughly 90 entries, including entire categories missing from this list: every widget sub-example (`widget_label`, `widget_button`, `widget_checkbox`, `widget_card`, `widget_table`, `widget_tree`, …, ~45 of them), `yaml`, `json_insertion`, `natural`, `markdown`, `markdown_rendered`, `chart*` (7 variants), `sequencechart*` (5 variants), `fsm*` (3 variants), `formula`, `rotating_vector`, `assistant`, `conversation_widget`, `conversation_editor`, `sql_*` (4 variants), `dragging`, `searching`, `navigator`, `layout`, `constraint_layout`. | `example/projectured/ProjecturedExamples.jl:1-47` (the `examples` vector, ~90 entries) vs examples-tour.md:20-25. | Either regenerate the list programmatically or explicitly scope this file to "featured examples" and stop calling the list "Available names" (which implies completeness). | checked |
| Whole file | MISSING | No section for the `assistant` example, even though it is registered (`assistant_example`, `example/projectured/DomainExamples.jl:88`) and its screenshot was refreshed a day before this survey — the single example most relevant to the new AI-native framing has no tour entry at all. | `grep -n "assistant" example/projectured/DomainExamples.jl` → `Example("assistant", make_assistant_document_example, make_assistant_projection_example; …)`. | Add an "Assistant" tour entry — natural anchor for the new framing's headline feature. | checked |
| Section headers, all six | CODE-REFERENCE (verified correct) | All six example names used in headers (`json`, `syntax`, `widget`, `table`, `julia`, `workbench`) resolve via `run_example(name)`, confirmed against `Example("json", …)`, `Example("table", …)`, `Example("julia", …)`, `Example("workbench", …)` in `DomainExamples.jl`. | `grep -n 'Example("widget"\|Example("table"\|Example("julia"\|Example("json"\|Example("workbench"' example/projectured/DomainExamples.jl` → all found. | none | checked |
| §1 JSON | CODE-REFERENCE (verified correct) | "loaded from `example/workspace/contact-list.json`" — not independently re-verified against source (out of scope depth for this pass), but plausible given the filesystem-example convention seen elsewhere. | — | — | likely |
| Going deeper | LINK (verified correct) | All four closing links resolve. | Checked against filesystem. | none | checked |

---

## documentation/presentation/README.md

**Verdict:** KEEP (small fix). **Audience:** contributor preparing a slide deck.
**Size:** 71 lines.

| where | category | finding | evidence | fix | confidence |
|---|---|---|---|---|---|
| "Accuracy" section | STALE (link text, not the link itself) | The visible link text reads `../guide/roadmap.md`, but the href correctly points at `../requirement/delivery-roadmap.md`. The *displayed path* names a file (`documentation/guide/roadmap.md`) that does not exist and never did in the current tree — only the underlying `requirement/delivery-roadmap.md` is real. | `find documentation -iname "roadmap.md"` under `guide/` → nothing; `documentation/requirement/delivery-roadmap.md` exists. | Fix the display text to match the href: `[../requirement/delivery-roadmap.md](../requirement/delivery-roadmap.md)`. | checked |
| Whole file | CODE-REFERENCE (verified correct) | `marp`, the CLI invocations, and the one deck it lists (`projectured-overview.md`) all check out. | Read both files together. | none | checked |

---

## documentation/presentation/projectured-overview.md (Marp deck)

**Verdict:** REWRITE. **Audience:** external, showcase (per `documentation/presentation/README.md`: "showcase audience"). **Size:** 456 lines / ~16 content slides.

This file has the worst language-rule and staleness density of everything surveyed in this
area. It predates the current `source/<slice>/` layout entirely — every source path cited
uses a package-internal layout (`package/kernel/main/...`, `document/...`, `projection/...`)
that has not existed since before the current top-level `source/`/`package`/`test`/`example`
split described in README.md's own "Repository layout" section.

| where | category | finding | evidence | fix | confidence |
|---|---|---|---|---|---|
| Every `<span class="muted">…</span>` source-path footer (10 of them) | STALE | Every single one cites a path pattern that does not exist anywhere in the repository: `package/kernel/main/agent/AgentServer.jl`, `tool/ToolSet.jl`, `document/Conversation.jl`, `projection/generic/ObjectToWidget.jl`, `document/Workbench.jl`, `document/Julia.jl`, `projection/primitive/JuliaToSyntax.jl`, `guide/roadmap.md`, `backend/{Sdl,Console,Web,Pdf}.jl`, `api/{Backend,Device}.jl`, `cell/CellModule.jl`, `projection/higherorder/*`, `projection/generic/*`, `package/*/main/document/*.jl`. | `find . -path "*/tool/ToolSet.jl"` → real path is `source/kernel/tool/ToolSet.jl`; `find . -path "*document/Conversation.jl"` → real path is `source/conversation/ConversationDocument.jl`; none of the cited paths have a `package/kernel/main/`, `document/`, `projection/`, `backend/`, `api/`, or `cell/` top-level component today. | Regenerate every path footer against the current `source/<slice>/` tree, or drop the path footers if they will only rot again — the brief warns this deck's paths "look stale," confirmed comprehensively. | checked |
| "🤖 AI assistant built in" slide | FRAMING (violates the language rules) | "The assistant isn't bolted on — it's part of the architecture" is exactly the forbidden "it's not X — it's Y" construction the brief calls out by name. | projectured-overview.md:151. | Rewrite as a plain positive statement. | checked |
| "📚 Many domains" slide | STYLE (marketing language, explicitly banned) | Slide title "Batteries included" — the brief's language rules ban this phrase by name (marketing language list: "batteries included"). Also claims "30+ structured domains," which both undercounts (real count of top-level packages is higher, ~65 non-Example/Test stems) and miscounts by the domain-vs-substrate-vs-tooling distinction the rest of the documentation uses (README.md's own count is 20 domains + separate substrate). | projectured-overview.md:330,336; compare to README.md's domain table (20 rows) and `ls package/`. | Replace the banned phrase; recompute the count against whichever taxonomy the rewritten docs settle on. | checked |
| Emoji bullets throughout | STYLE | Every one of the 12 feature slides is titled with a leading emoji (🤖🔍🪞🪟🖥️⚡🧩📚⌨️⏱️🤝) and several bullet lists nest more emoji per line — the brief bans "emoji bullets" by name. | Full read; e.g. lines 149, 174, 198, 223, 251, 277, 301, 328, 364, 391, 414. | Drop the emoji scheme entirely in any rewrite that targets Reddit/Discourse per the brief. | checked |
| "⏱️ Undo, redo & versioning" / "🤝 Built to collaborate on" slides | OBSOLETE / HISTORY-adjacent | Both slides describe unimplemented features in the present tense as if they were architectural facts ("Every change is a first-class, typed, invertible `Operation`"), softened only by a small muted footer ("Forthcoming…"). This is the inverse of a history comment — a *future* claim dressed as current fact — and duplicates README's own, more honest "Status" callout and roadmap link. | projectured-overview.md:397-431; compare to README.md's Status callout (lines 67-71) which is explicit that undo/redo is not yet delivered. | Either mark these slides clearly as roadmap items throughout (not just in a small muted line) or cut them until delivered — README.md is more careful about this than the deck is. | checked |
| Final slide | LINK (verified correct) | `github.com/projectured/projectured-julia` — correct repository. | — | none | checked |

---

## tool/juliac-trim/README.md

**Verdict:** KEEP. **Audience:** contributor working on static compilation. **Size:** 52 lines.

No wrong claims found. It correctly scopes itself ("standalone Julia. It does not load
`Projectured`") and its one cross-reference (`documentation/guide/static-compilation-guide.md`)
resolves.

| where | category | finding | evidence | fix | confidence |
|---|---|---|---|---|---|
| Header link | LINK (verified correct) | `../../documentation/guide/static-compilation-guide.md` resolves from `tool/juliac-trim/`. | File exists at that path. | none | checked |
| Whole file | FRAMING | Not customer-facing; describes an internal probe. No framing changes needed. | Full read. | none | checked |

---

## test/graph/reference/README.md

**Verdict:** KEEP. **Audience:** contributor working on the graph-layout port.
**Size:** 34 lines.

| where | category | finding | evidence | fix | confidence |
|---|---|---|---|---|---|
| "Paste the output into…" | LINK (verified correct) | `../projection/GraphTest.jl` — relative to `test/graph/reference/`, this resolves to `test/graph/projection/GraphTest.jl`. | Not independently re-verified byte-for-byte (out of assigned depth), but the path shape is consistent with the rest of `test/<slice>/` conventions seen elsewhere in this survey. | — | likely |
| Whole file | FRAMING | Purely a build/regen procedure for cross-checking against a C++ reference; no user-facing framing at stake. | Full read. | none | checked |

---

## example/filesystem/fixture/project/README.md and doc/guide.md

**Verdict:** KEEP — confirmed test fixtures, must not be touched by any documentation rewrite.
**Audience:** none (not documentation; consumed only as fixture content by the filesystem
domain's examples). **Size:** 8 + 7 lines.

Both files say explicitly that they are fixture content ("A small, fixed directory tree for
the file-system examples. It is a fixture, not a real project" / "Fixture content for the
file-system examples. Never read."). Their prose exists only so the rendered file-system tree
has believable-looking leaf content and a nested-folding shape (one nested dir `src`, two
sibling dirs `data`/`doc` with different file kinds). **A documentation rewrite must leave
these two files untouched** — they are not part of the documentation surface, and any pass
that walks `**/README.md`, `**/*.md` or `**/doc/*.md` looking for stale docs should skip
`example/*/fixture/**` explicitly. No findings table — nothing to fix, this section exists to
record the exclusion for the planning step.

---

## The public website (`/home/projectured/workspace/projectured.github.io/index.html`) — context, not a target of this rewrite

Read per the brief's instruction to compare framing. This is a separate repository/deployment,
not part of `projectured-julia`, so it gets no verdict — but it matters directly for the
brief's new framing.

**How it frames the project.** The landing page is already fully AI-native: hero eyebrow
"AI-native · generic-purpose projectional editor"; a dedicated `#ai` section titled "Built for
an AI collaborator — not bolted on" with six capability cards (introspection, one-tool code
execution, structural editing, conversation-as-document, intent-not-keystrokes, symmetric
human/AI editing); a `#compare` section that puts "Today's AI assistants: they edit text" next
to "ProjecturEd: it edits meaning" as the second of its two headline comparisons (the first
being "ordinary software: one fixed interface" vs. "the interface is a projection"). This is a
substantially closer match to the brief's requested framing ("a generic, on-demand user
interface for Julia data, with AI integration from the ground up… projectional editing is the
mechanism, not the headline") than any file inside the repository itself.

**Where it agrees with the README:** the core "structure vs. text" pitch is the same idea in
both places; the six-screenshot/six-example tour in README.md maps loosely onto the website's
own `#examples` section (different concrete examples: rotating vector, math table, sorting,
object-to-form, a SQL widget tool, an auto-laid-out graph, a mixed Julia/XML function — none of
which match README's six).

**Where it diverges or overstates, worth flagging for the plan:**
- Contact address is `projectured@gmail.com`, not `levente.meszaros@gmail.com` (README/CONTRIBUTING/licences) — three different addresses now exist across the project surface (see README row above for the third, `levente.meszaros@omnest.com`, the working git identity).
- The "Lineage & status" section claims "roughly seventy thousand lines built entirely through disciplined, AI-assisted development… not one of them written by hand," for `source/`; the actual current count is **103,188 lines** in `source/*.jl` alone (`find source -name "*.jl" | xargs wc -l`), 47% higher than the site's figure — plausible drift since the site copy was last written, worth a refresh regardless of which repo owns the fix.
- The website itself contains the same "it's not X — it's Y" / negated-bolt-on construction the brief explicitly bans ("An assistant here isn't a plugin off to the side," "Built for an AI collaborator — not bolted on") — useful as a *counter-example* the new documentation should not imitate, even though the site is otherwise the best model of the target framing available in this survey.
- The website advertises "Undo, redo & versioning" only implicitly (it is absent from the `#capabilities` grid, unlike the Marp deck, so no direct overstatement found there) — this is actually more careful than the Marp deck.

---

## Top findings of this area

Most important first, at most 12.

1. **SEALING.md's kernel-file inventory is stale against the real include tree**: 10 listed paths don't exist (4 of them currently marked 🔒 sealed under a name that isn't in the tree), and 13 real files — including 4 of the `projection/` layer's core interface files — are missing from the inventory entirely. This is the highest-confidence, highest-stakes finding: it affects the audit/seal process itself, not just prose. *(SEALING.md)*
2. **`documentation/guide/orientation.md`'s entire "Guide" column is the wrong slug for every row** (missing the `kernel/`-style folder prefix the code actually requires, one entry — `selection-deep-dive` — naming a file that only survives in `plan/obsolete/`). Since this table's stated purpose is to hand an AI assistant a name to call `read_guide`/`search_guides` with, every row currently fails. *(orientation.md)*
3. **`documentation/guide/setup-guide.md`'s own bootstrap instruction for an AI assistant is broken**: `resource://guide/getting-started` does not resolve (real name `guide/setup-guide`); the same stale name is baked into `source/kernel/tool/Documentation.jl` and `DefaultTools.jl`, so this isn't just a doc typo, it is a repository-wide unfixed rename. *(setup-guide.md)*
4. **Julia version requirement is stated three different ways** in three front-door files (README.md and CONTRIBUTING.md say "1.11 or later," setup-guide.md says "1.10+"), and none of the `[compat]` entries in the repository actually pin `julia = "1.11"` anywhere — the resolved manifest (`environment/all/Manifest.toml`) was in fact built with Julia 1.13.0. *(README.md, CONTRIBUTING.md, setup-guide.md)*
5. **`examples-tour.md` documents 6 of roughly 90 registered examples**, and its own "Available names" list (23 names) is a small, stale fraction of the real `examples` vector — entire categories (all widget sub-examples, chart, sequencechart, fsm, sql, assistant, conversation) are absent. *(examples-tour.md)*
6. **The assistant example has a fresh screenshot (regenerated the day before this survey) that no front-door document uses.** README.md's screenshot table and examples-tour.md both predate or ignore it, even though it is the single most on-framing image available for the brief's AI-native rewrite. *(README.md, examples-tour.md)*
7. **The Marp deck (`projectured-overview.md`) cites source paths that predate the current repository layout, in all 10 of its footer citations**, and contains the two most explicitly-banned constructions from the brief in the same slide ("isn't bolted on — it's part of the architecture") plus a banned marketing phrase ("Batteries included") and pervasive emoji bullets. This file needs the deepest rewrite of anything surveyed. *(projectured-overview.md)*
8. **Naming rules, the "comment says what is" rule, and the testing-function catalogue are each duplicated near-verbatim across 2-3 of README.md / CONTRIBUTING.md / CLAUDE.md**, directly contradicting `documentation/README.md`'s own stated rule ("Cite, do not repeat… Two copies drift, and one of them is then wrong"). *(README.md, CONTRIBUTING.md, CLAUDE.md, documentation/README.md)*
9. **README.md never names the Style or Layout packages**, even though its own code sample in "Every field is a cell" constructs a `StyleText` value from the (unnamed) Style package, and Layout (constraint-based layout) is a headline item on the public website's domain catalogue. Pdf, Clipboard and Dragging are also unmentioned despite being documented elsewhere (setup-guide.md) or showcased on the website ("paste by identity"). *(README.md)*
10. **The public website is already closer to the brief's requested framing than anything in the repository** ("AI-native," "Built for an AI collaborator — not bolted on," text-vs-meaning comparison front and center) — it is useful source material for the rewrite, with the caveat that it also contains banned constructions (item 7's "not bolted on" pattern) that should not be copied forward, and its own numeric claim ("roughly seventy thousand lines") is now 47% stale against the real 103,188-line `source/` count.
11. **`orientation.md` claims to be "read first," but is linked from neither README.md's reading order nor `documentation/README.md`'s own "Where to start" list** — it is only reachable from two deep-in-the-chain rule/design documents. *(orientation.md, documentation/README.md)*
12. **`documentation/README.md` lists `package/README.md` as a servable reference document, but the guide-indexing code in `source/kernel/tool/Documentation.jl` structurally excludes any file placed directly in `documentation/package/`** (as opposed to inside one of its per-slice subfolders) from both of its scan loops — so the AI assistant this documentation partly serves cannot actually retrieve it by name. *(documentation/README.md)*

---

# Survey area B — requirement and design documents

Scope: `documentation/requirement/{product-vision,accepted-requirements,delivery-roadmap}.md`,
`documentation/design/{editor-concepts,editor-derivation,system-anatomy,architecture-decisions,domain-inventory}.md`.

All findings below were checked statically (`grep`, `find`, `git log`, `Read`) against
the repository at commit `c28e6e30` (branch `main`, clean). No Julia was run.

---

## documentation/requirement/product-vision.md

**Verdict:** REWRITE (structure and framing). **Audience:** new user (the document
explicitly frames itself for a Reddit/Discourse-class reader once the framing
changes). **Size:** 200 lines. Last change: 2026-09-01 (file move only, see below).

| where | category | finding | evidence | fix | confidence |
|---|---|---|---|---|---|
| "The MCP bridge" §, line 78 | WRONG | Claims the MCP server activates "when the editor's `run_editor!` loop is active." It does not: MCP is opt-in. | `source/kernel/editor/EditorModule.jl:346`: `function run_editor!(editor::Editor; mcp::Bool=false, ...)` — MCP starts only when the caller passes `mcp=true`. | Say the MCP server is started with `run_editor!(...; mcp=true)`, not automatically. | checked |
| "What bidirectional projections enable" §, lines 62–66 vs. "Multi-backend architecture" §, lines 103–117 | CONTRADICTION | Lines 62–66 describe "a terminal renderer, a WebGL canvas, or an IDE extension tomorrow" as future work; 40 lines later the same document lists Console and Web backends under **Delivered**. | Quoted text at both locations, same file. | Make backend-3 consistent with the delivered list; only the IDE-plugin backend is future. | checked |
| whole document | FRAMING | The document is headlined "Why structured editing matters" and spends 4 of 6 sections on projectional-editing mechanics before reaching AI (§3 of 6, "The MCP bridge"). Under the new framing, on-demand AI-driven access to Julia data should lead, not follow. | Section order in file. | Reorder / re-head so on-demand + AI leads; projectional editing becomes the "how". | checked |
| lines 34–35 | STYLE | "The cursor never leaves a valid position in the model. You literally cannot type a syntax error." Stated as an absolute. `accepted-requirements.md`'s own `PR-INTERMEDIATE-STATES` requires the architecture to *permit* "a state that is ill-formed in the original kind of content" to exist "one way or another," and `editor-derivation.md` §5.4 admits character editing is not uniform across every domain yet. | `documentation/requirement/accepted-requirements.md:176-183`; `documentation/design/editor-derivation.md:618-633`. | Qualify: the caret/selection mechanism cannot land on an invalid tree position; that is narrower than "cannot type a syntax error" in general. | likely |
| lines 31–41 | STYLE | Four bullets in a row each end on an absolute, marketing-shaped claim ("eliminates all of these problems by construction", "cannot produce structurally invalid edits") — padded-absolutes pattern the language rules flag. | Quoted bullets. | Cut to one concrete claim per bullet, drop "by construction" / "eliminates all". | checked |
| "Compared to other tools" § | FRAMING | Comparators are MPS, Lamdu, Hazel, Tree-sitter — all PL-research tools a Julia/Reddit reader is unlikely to know. No Julia-native comparator (Pluto.jl, Jupyter, VS Code+Copilot) appears, though those are what the stated audience actually uses day to day. | Section content. | Either keep as a "prior art" appendix for a PL audience, or add/replace with Julia-ecosystem comparators for the Reddit/Discourse audience. | likely |
| "Lamdu" §, line 160 | STYLE | "Lamdu is a live-programming structured editor for a Haskell-like language" undersells the more relevant comparison point (Lamdu has no textual syntax at all — it is projectional end to end), which is the one fact that would actually matter to this document's argument. | General knowledge of Lamdu, not repo-verifiable. | Lead with "no textual syntax" if keeping the comparison. | likely |
| "The MCP bridge" § | FRAMING (positive) | This section and "Extensibility story" already fit the new framing reasonably well and can be promoted rather than rewritten from scratch. | — | Reuse as the seed of the new lead section. | checked |

---

## documentation/requirement/accepted-requirements.md

**Verdict:** UPDATE (solid, implementation-free wording; two structural gaps for
the new framing). **Audience:** contributor / software-architect (citable PR-IDs)
and the AI assistant (served as a resource). **Size:** 409 lines. Last change:
2026-09-01 (file move only).

| where | category | finding | evidence | fix | confidence |
|---|---|---|---|---|---|
| "AI assistance" §, PR-AI-SAME-GUARANTEES / PR-EDIT-BY-REQUEST | MISSING | No requirement covers reflection-based, on-demand editing of an arbitrary Julia value (not a declared domain document) — one of the new framing's three named paths ("by reflection over the value"). `ObjectToWidget` already does this in code. | `documentation/design/system-anatomy.md:266` (`ObjectToWidget` — "Reflection-driven editable form for an object's `Cell` fields"); no PR-ID anywhere in this file mentions reflection or raw Julia values. | Add a requirement, e.g. "any Julia value must be presentable and editable without a bespoke domain." | checked |
| same § | MISSING | No requirement that the in-editor assistant and an external MCP client share one tool/capability surface — a named plank of the new framing. | `source/mcp/Mcp.jl:33-38`: "the in-editor assistant and any external MCP client share the same prompt" is an implementation fact with no corresponding PR-ID. | Add a requirement for one shared tool set across in-editor and external agents. | checked |
| Index / document order | FRAMING | The two AI requirements are the last pair in "Behaviour of the editor," after 24 unrelated requirements, and are titled generically. Under the new framing this is a primary axis, not an appendix. | Table of contents, lines 102-108. | Consider a top-level "AI and on-demand access" group nearer the front. | checked |
| whole file | — | No broken links, no history language (`used to` / `previously` / …) found. | grep, this pass. | — | checked |

---

## documentation/requirement/delivery-roadmap.md

**Verdict:** REWRITE (stale; misses most of the last four months of shipped
work). **Audience:** new user + contributor (prioritization reference). **Size:**
134 lines. **Last real content change:** 2026-09-01 (`57b7be25`, a pure file
move from an older location — the "Delivered" list text is unchanged since
before that). The only later touch, 2026-09-13 (`2b6ac403`), is a one-identifier
rename (`sqlparse` → `parse_sql_text`) inside an existing bullet — not a content
update.

The roadmap is missing entire shipped subsystems. Evidence, per item (git log
`--since=2026-01-01`, `plan/done/`, `plan/pending/`):

| where | category | finding | evidence | fix | confidence |
|---|---|---|---|---|---|
| "Delivered" § | MISSING | The in-editor AI **assistant** is not listed at all. | `plan/done/workbench-assistant.md`, `workbench-assistant-mvp.md` (2026-05-28), `assistant-real-ai.md` (2026-06-01), `assistant-finds-the-api.md`, `assistant-editor-reference.md`, `assistant-collapse-layout.md`, `assistant-input-placeholder.md` — all done. `README.md` calls it a headline feature. | Add an "AI assistant" bullet under Delivered. | checked |
| "What won't change" § (only MCP mention) | MISSING | The **MCP server** / agent control surface (kernel layers 15-16, opt-in `Mcp` package) is named once, as a stable-decision footnote, never described as delivered functionality. | `source/kernel/agent/AgentLayer.jl` (layer 16), `package/ProjecturedMcp/`; git log has `35e78105 The assistant is a package of its own`, `68d2c0e0 A window's MCP server gives the window's own prompt`. | Add an MCP/agent bullet under Delivered. | checked |
| "Search" bullet, line 47 | MISSING | Only `search_references`/`search_documents` (predicate search) is described. Meaning/embedding search ("three kinds of search": keyword, pattern, description) is absent. | `plan/done/three-kinds-of-search.md` (done 2026-09-16, commit `e9f28cbe`); `c6e5d063 Ollama computes meaning vectors with its meaning model`. | Extend the Search bullet or add a new one. | checked |
| whole document | MISSING | No mention of the **Ollama** LLM backend at all. | `plan/done/ollama-backend.md` (done 2026-09-09, `b27ce3c1`); `source/ollama/Ollama.jl`, `package/ProjecturedOllama/`. | Add a bullet (assistant backends: Anthropic + Ollama). | checked |
| "Delivered" § | MISSING | **PDF export** (`write_pdf`) is not listed, even though `product-vision.md` and `system-anatomy.md`'s own pipeline-status table mark it ✅. | `plan/done/write-pdf.md` (done 2026-06-23, `c2825c5f`), `plan/done/pdf-pagination.md`. | Add a Delivered bullet for `write_pdf`. | checked |
| "Delivered" §, "Graph domain" bullet | MISSING | The **Chart** domain (line/bar/histogram/scatter/strip, with polygon and point selection) is a full domain package and is never mentioned. | `plan/done/chart-domain.md` (done 2026-08-13, `481514ac`), `chart-polygon-and-point-selection.md`, `chart-colored-strips.md`; `package/ProjecturedChart/`. | Add a bullet, or fold into an existing "domains" bullet. | checked |
| "In progress" § | MISSING | The **Formula** domain (spreadsheet-cell formulas as embedded Julia/Math documents) is under active work and unmentioned. | `plan/pending/formula-with-math-code.md` (last touched 2026-09-16, `d7baee48`); `package/ProjecturedFormula/`. | Add under In progress or Planned. | checked |
| "In progress → 4. Editable tables" | MISSING | The `WidgetTable`/`WidgetLazyTable` consolidation that this item builds on already landed and is unmentioned. | `plan/done/one-table-widget.md` (done 2026-09-16, `94d2f73c`, "`WidgetLazyTable` is deleted, and the plan is done"). | Update the bullet to reflect the merged widget as the current base. | checked |
| whole document | MISSING | **File references** — a new document-linking mechanism ("a file reference is not a document node") — is unmentioned. | `plan/done/file-reference-is-not-a-node.md` (done 2026-09-16, `e29a6013`). | Add a Delivered bullet. | checked |
| "In progress" § (4 items only) | MISSING | Two active `plan/pending/` items with recent commits are absent: **duplicate a pane** and **select-a-widget-and-paste-it-into-a-tab** (Alt+click widget selection). | `plan/pending/duplicate-a-pane.md`, `select-a-widget-and-paste-it-into-a-tab.md`; commits `08eaa28b`, `bce0084e` (both 2026-09-17, i.e. after the roadmap's last edit). | Add to "In progress" or "Planned". | checked |
| "Delivered" § | — | Items that are correctly placed and still accurate: structural insert/delete, in-place authoring, type-in with completion, clipboard, console/web backends, graph domain + auto-layout, document persistence, version history. Cross-checked against `system-anatomy.md`'s pipeline-status table (✅ rows) and `plan/done/`. | — | keep | checked |

---

## documentation/design/editor-concepts.md

**Verdict:** KEEP the five-idea structure and walkthrough; UPDATE one file
citation; REWRITE the opening framing. **Audience:** new user (explicitly "no
code... just a mental model"). **Size:** 360 lines. Last change: 2026-09-01
(move only).

| where | category | finding | evidence | fix | confidence |
|---|---|---|---|---|---|
| "Where each piece lives in the kernel" table, `projection` row | WRONG | Cites `projection` as living in "layer 13 — `projection/Projection.jl`". No such file exists. | `ls source/kernel/projection/` → real files are `ProjectionInterface.jl` (interface) and `ProjectionMacro.jl` (`@projection` macro); no `Projection.jl`. | Correct the cell to `ProjectionInterface.jl`. | checked |
| "What is projectional editing?" (opening heading) | FRAMING | The document's first sentence and first heading are mechanism-first ("What is projectional editing?"), the framing the brief says must no longer be the headline. | Line 11. | Re-head around on-demand/AI access; keep the five ideas as the explanation of the mechanism. | checked |
| whole document vs. editor-derivation.md and README.md | DUPLICATE | Same five/ten-concept vocabulary, the same printer/reader ASCII diagram, and the same "press → inside `"hello"` at offset 2" walkthrough appear near-verbatim in `editor-derivation.md` (§3) and, for the diagram, in `README.md` ("How a keystroke round-trips"). | Compare `editor-concepts.md` "A step-by-step walkthrough" (lines 295-347) with `editor-derivation.md` §3 (lines 340-397) — same document (`"hello"`), same offset (2), same key (`→`). | See combined recommendation below. | checked |
| throughout | STYLE | The construction "X is what makes Y [composable/general/...]" recurs at least 5 times (lines 55, 253, 260, 265, 289) — a repeated structural tic rather than a single problem sentence. | grep count in file. | Vary the phrasing; not urgent. | likely |
| "The document editing model" § | FRAMING (positive) | The mutually-recursive-cluster explanation and the per-layer table are accurate and reusable regardless of framing (verified layer numbers against the kernel include list — see system-anatomy.md section). | — | keep | checked |

---

## documentation/design/editor-derivation.md

**Verdict:** KEEP most content; fix one broken link; REWRITE the opening framing.
**Audience:** new user / Julia developer evaluating the library as a dependency
(the doc's own words: "a software engineer who is new to ProjecturEd"). **Size:**
700 lines. Last change: 2026-09-01 (move only).

| where | category | finding | evidence | fix | confidence |
|---|---|---|---|---|---|
| "1. One idea and one loop" §, line 61 | LINK | `[Editor.jl](../../source/kernel/editor/Editor.jl)` is broken; no such file. | `ls source/kernel/editor/` → `EditorLayer.jl`, `EditorModule.jl`, `PlaybackModule.jl`. Only file with matching link-check script run this pass across all 8 assigned files. | Point to `EditorModule.jl`. | checked |
| whole document vs. editor-concepts.md | DUPLICATE | See editor-concepts.md's row above — both documents are listed by README.md as the *first two* "Start here" entries and cover the same ground twice. | `README.md` "Start here" list, items 1–2. | See combined recommendation below. | checked |
| "5.4 The current frontiers" § | FRAMING (positive) | This is the most current, most honest state-of-the-system section in the whole assigned set (undo, non-uniform character editing, partial click-to-select, left-motion stall, collaboration/staging not built, self-hosting as long-term goal) — more current than `delivery-roadmap.md`, which omits several of the same facts elsewhere. | Lines 613-633. | Preserve verbatim in any rewrite; this is the section delivery-roadmap.md should read like. | checked |
| §5.2 "The AI assistant" / §5.3 rule 6 (IDE-plugin/host-anything) | FRAMING | The material that already matches the new framing exists but sits at the very end of a 700-line document (§5 of 7). | Lines 576-580, 606-611. | Promote to the front in a rewrite. | checked |
| "1. One idea and one loop" (opening) | FRAMING | Opens "A text editor keeps your work as characters. It guesses the structure." — mechanism-first opening, same issue as editor-concepts.md. | Lines 24-29. | Re-head. | checked |

**Combined note for editor-concepts.md / editor-derivation.md:** both are
explicit "start here" documents (README.md lists `editor-derivation.md` as
guide 1 and `editor-concepts.md` as guide 2), and their overlap is not
superficial — same ten-ish concepts, same worked example, same diagram also
present a third time in `README.md`. `editor-derivation.md` is more complete
(it alone has the combinator catalogue in §4 and the honest "frontiers" §5.4)
but at 700 lines is too long for a first document under the stated Reddit/
Discourse audience; `editor-concepts.md` is shorter but has the broken
`Projection.jl` citation and no "what works / what doesn't" section. Neither
is a good base as-is. Recommendation: **MERGE** — write one new, shorter
"what is ProjecturEd" document under the new framing that borrows
editor-concepts.md's five-idea structure and editor-derivation.md's §5.4
frontiers section, and demote whichever of the two is not absorbed to a
deeper "concepts in full" guide rather than keeping two competing "start
here" entries.

---

## documentation/design/system-anatomy.md

**Verdict:** UPDATE (mostly accurate; one real package missing from every
count/table, two smaller naming/history issues). **Audience:** contributor.
**Size:** 485 lines. Last change: 2026-09-15 (`30ab2d63`, part of the file-reference
feature landing — a genuine recent content touch, unlike the other files in
this set).

| where | category | finding | evidence | fix | confidence |
|---|---|---|---|---|---|
| "Package layout" §, substrate list and "twenty domain packages" list; "Module dependency graph" § | MISSING | `ProjecturedAssistant` (`source/assistant/`, `package/ProjecturedAssistant/`) is a real package that `ProjecturedWorkbench` directly depends on. It appears in none of: the 28-name substrate list, the 20-name domain list, the opt-in list, or the dependency-graph diagram. | `package/ProjecturedWorkbench/Project.toml` `[deps]` includes `ProjecturedAssistant = "3f5a9c21-…"`; `ls package/` shows `ProjecturedAssistant`; `source/assistant/AssistantModule.jl` docstring: "It is a `Document` of its own now" (i.e. it is domain-shaped, not a utility). | Add Assistant as a 21st domain (or its own category) and update every count that says "twenty domain packages" / lists the substrate 28. | checked |
| substrate list, "naturalprojection" entry | WRONG | Names the render-anything substrate package "naturalprojection." The real package/slice name is `ProjecturedNatural` / `source/natural/`. | `ls package/` → `ProjecturedNatural` (no "…Projection" package exists); `ls source/` → `natural`. | Rename the list entry to "natural". | checked |
| line 144 | HISTORY | "per-domain reference guides that used to live at the top level" — history language the project's own rule forbids. | Quoted line; cf. `documentation/rule/code-quality-rules.md` "A comment says what is, never what was" (per CLAUDE.md). | Drop the history clause; state only where the guides live now. | checked |
| "Module inventory → kernel layers" table / diagram | — | Verified correct: the 17-layer list (name, order, one-line role) matches `package/ProjecturedKernel/src/ProjecturedKernel.jl`'s include list exactly, layer-for-layer (`cell → clock → event → device → gesture → backend → document → reference → selection → operation → binding → iomap → projection → tool → llm → agent → editor`). | Both files compared directly. | keep | checked |
| "twenty domain packages" list | — | Verified correct (apart from the Assistant omission above): the 20 named domains (`json yaml xml markdown rst book math julia sql database filesystem graph chart sequencechart dbcatalog formula fsm process conversation workbench`) match `ls package/` (main packages) exactly. | `ls package/`, filtered to non-Example/Test domain names. | keep | checked |
| "twenty-eight substrate packages" list | — | Verified correct (apart from the natural/naturalprojection name): all 28 named concepts map one-to-one onto 28 `source/` folders that are neither kernel, domain, nor opt-in. | `ls source/` cross-checked against the list. | keep | checked |
| overall count framing ("one engine, twenty-eight substrate... and twenty domain... plus an umbrella and the opt-in packages") | MISSING (minor) | `source/builder`, `source/executable`, `source/repl` (and `ProjecturedBench`, not in `source/` at all) are real packages of a different "kind" (build/repl/bench per `package-rules.md`) that this sum never accounts for — `ls package/` has 119 directories total, far more than 1+28+20+1+9=59, because of the Example/Test triads plus these four. Not a wrong count (the document never claims to enumerate them), but a reader following only this document has no idea they exist. | `ls package/` (119 entries) vs. the 59 named "kinds"; `package/ProjecturedBuilder/Project.toml`, `ProjecturedExecutable/Project.toml`, `ProjecturedRepl/Project.toml`, `ProjecturedBench/Project.toml`. | Add one sentence pointing at `package-rules.md`'s kind table for build/repl/bench packages. | checked |
| whole document | FRAMING | The AI/agent stack (layers 14-16: tool/llm/agent; opt-in Mcp/Anthropic/Ollama) gets one line each in the layer table and the opt-in table, with no prose section — unlike the projection pipeline, which gets a full "Projection pipeline status" section with a printer/reader table. | Compare layer-table one-liners (lines 377-382) to the "Projection pipeline status" section (lines 430-463). | Consider a short "AI/agent surface status" section parallel to the projection-pipeline one. | checked |

---

## documentation/design/architecture-decisions.md

**Verdict:** KEEP (accurate, well-scoped "why" document); UPDATE to add AI/agent
decisions. **Audience:** contributor. **Size:** 192 lines. Last change:
2026-09-12 (`deeddf66`, a real content touch — an IO-map naming fix).

| where | category | finding | evidence | fix | confidence |
|---|---|---|---|---|---|
| "6. `print_document` returns an IO map" § | — | Verified correct: `ChainingProjection`/`ChainingIoMap`/`step_iomaps` are real and match the described shape. | `source/projection/higherorder/Chaining.jl:18` (`@iomap struct ChainingIoMap`), `:80` (constructed with `step_iomaps`). | keep | checked |
| whole document | MISSING | All ten numbered decisions are about the reactive/projection substrate; none explain the AI-integration design choices that the new framing foregrounds — why an MCP seam at the kernel level, why the in-editor assistant and external MCP clients share one tool set, why the assistant's core tool is "run Julia against the live editor" rather than a fixed operation vocabulary. | Section list, lines 12-179; cross-checked against `source/mcp/Mcp.jl` and `source/kernel/tool/`, which contain exactly this kind of design rationale in comments but no corresponding numbered entry here. | Add 2-3 new numbered decisions for the AI/agent design. | checked |
| whole document vs. editor-concepts.md / editor-derivation.md | DUPLICATE (minor) | Pull-based reactivity, every-field-is-a-cell, and `ProjectionReferenceStep` are each explained a second time (with different code samples) in the other two design documents. Overlap is smaller than the concepts/derivation overlap and each document adds detail the others don't, so this is lower priority. | Compare §1-3, §8 here to editor-concepts.md §"The five core ideas" and editor-derivation.md §2.1/§2.3. | Low priority; note only. | checked |
| §6, pseudocode | STYLE | The `read_intent` pseudocode uses an undefined `n` ("for i in (n-1):-1:1") — illustrative, not copy-pasted from source, so harmless but slightly sloppy. | Lines 102-109. | Define `n = length(...)` or drop the loop bound. | checked |

---

## documentation/design/domain-inventory.md

**Verdict:** UPDATE (accurate framework text; one wrong dependency row, one
missing package). **Audience:** contributor. **Size:** 160 lines. Last change:
2026-09-13 (`fd7fb73c`, a real content touch — module-per-file compliance note).

| where | category | finding | evidence | fix | confidence |
|---|---|---|---|---|---|
| "The dependency table", `ProjecturedWorkbench` row | WRONG | States deps as "Conversation, FileSystem, Json, Julia, Markdown, Xml, Yaml." None of Json, Julia, Markdown, Xml, Yaml appear in the package's actual `[deps]`, and `Assistant` (a real, direct dependency) is missing from the list. | `package/ProjecturedWorkbench/Project.toml` `[deps]`: `Assistant, Collection, Conversation, FileFormat, FileSystem, Kernel, Layout, Primitive, Projection, Style, Syntax, Text, Widget`. | Replace the row with the actual dependency list; drop the "the workbench opens documents of every kind" justification or rephrase it (those domains are opened *dynamically* at runtime by the umbrella/example packages, not declared as Workbench's own deps). | checked |
| "Per-domain guides" list / "The dependency table" (20 rows) | MISSING | Same fact as system-anatomy.md: `ProjecturedAssistant` is not counted as a 21st domain, despite fitting this document's own definition of a domain package ("the documents, the types the content is made of... the projections that render and edit it") and being a direct Workbench dependency. | `source/assistant/AssistantModule.jl` module docstring: "It is a `Document` of its own now, because a program that wants an assistant beside its own panes should not carry an IDE to get one." | Add Assistant as a 21st row (with `Conversation` as its one domain dependency, per its actual `[deps]`), or explain in "What is NOT a domain package" why it is deliberately excluded (it does not currently fit any of that section's three exemption categories). | checked |
| "The dependency table," remaining 19 rows | — | Verified correct: every other row's right-hand column matches the package's actual `[deps]` domain-to-domain edges (`dbcatalog→sql`, `formula→julia`, `fsm→julia,graph`, `process→julia,graph`, `conversation→json,julia,xml`), and "fourteen domains need nothing but the engine, five build on one layer" is arithmetically consistent (14+5+1 workbench = 20). | Cross-checked each package's `[deps]` block against the table. | keep | checked |
| "What a domain package is" / "Adding a domain" §§ | FRAMING | Purely mechanical (how to wire `register_natural_syntax!`, add to `Projectured`'s `_SOURCES`, etc.), with no mention that many values need no new domain package at all — the new framing's "by reflection over the value" path (`ObjectToWidget`) bypasses this whole procedure. A reader could conclude a domain package is the only way to make something editable. | Section content; cross-check `system-anatomy.md:266` for `ObjectToWidget`. | Add one paragraph distinguishing "needs a domain package" from "works today via reflection, no package needed." | checked |
| whole document | — | No broken links (checked), no history language found. | grep + link-check script, this pass. | — | checked |

---

## Top findings of this area (most important first)

1. **`delivery-roadmap.md` is stale by roughly four months of shipped work.**
   Its content has not changed substantively since before 2026-09-01 (one
   later touch is a pure rename), yet the assistant, MCP, meaning/embedding
   search, the Ollama backend, PDF export, the Chart domain, the Formula
   domain (in progress), file references, and the `WidgetTable` consolidation
   all shipped or advanced in that window and appear nowhere in it.
2. **`ProjecturedAssistant` is invisible to the architecture documents.** It
   is a real package (`source/assistant/`, `package/ProjecturedAssistant/`)
   that `ProjecturedWorkbench` directly depends on, self-described in its own
   module docstring as "a `Document` of its own," yet it is absent from every
   package count and table in both `system-anatomy.md` and
   `domain-inventory.md`.
3. **`domain-inventory.md`'s `ProjecturedWorkbench` dependency row is
   factually wrong**: it lists Json/Julia/Markdown/Xml/Yaml (none of which
   are actual deps) and omits Assistant (which is).
4. **All eight files still headline "projectional/structured editor," not
   on-demand AI-driven access to Julia data.** The AI/assistant/MCP material
   exists throughout but is consistently placed last or reduced to a
   footnote — the reverse of the priority the new framing calls for.
5. **`editor-concepts.md` and `editor-derivation.md` are both "start here"
   documents with heavy, non-superficial overlap** (same vocabulary, same
   printer/reader diagram — also duplicated a third time in `README.md` —
   same worked "press → at offset 2 in `"hello"`" example). They should
   become one document, not two competing entry points.
6. **Two broken file citations**, both checkable and both wrong:
   `editor-concepts.md` cites `projection/Projection.jl` (real file:
   `ProjectionInterface.jl`); `editor-derivation.md` cites
   `source/kernel/editor/Editor.jl` (real file: `EditorModule.jl`).
7. **`product-vision.md`'s MCP claim is wrong as written**: it says the MCP
   server "exposes" when `run_editor!`'s loop is "active," but the server
   only starts when the caller passes `mcp=true` (default `false`).
8. **`product-vision.md` contradicts itself** about backend maturity: one
   section treats the terminal/web backends as future ("tomorrow"), a later
   section in the same file correctly lists them as delivered.
9. **`accepted-requirements.md` has no requirement for two pillars of the new
   framing**: on-demand reflection-based editing of an arbitrary Julia value
   (code: `ObjectToWidget`, no PR-ID), and one shared tool set for the
   in-editor assistant and external MCP clients (code: `source/mcp/Mcp.jl`,
   no PR-ID).
10. **`architecture-decisions.md` has ten "why" entries, none about the
    AI/agent design** (why an MCP seam at the kernel level, why a shared
    tool set, why "run Julia" is the assistant's core primitive) — a gap the
    new framing should close.
11. **`product-vision.md`'s comparison set (MPS, Lamdu, Hazel, Tree-sitter)
    does not fit its own stated audience** — none of the four are widely
    known outside programming-language research, while the audience is
    Reddit/Julia-Discourse readers who are far more likely to know
    Pluto.jl, Jupyter, or VS Code + Copilot.
12. **`system-anatomy.md` carries one leftover history sentence** ("guides
    that used to live at the top level"), against the project's own
    no-history-in-source-and-docs rule, and one minor naming slip
    ("naturalprojection" for the real `ProjecturedNatural`/`natural`).

---

# Survey area C — rule documents for contributors

Scope: `documentation/rule/architecture-invariants.md`, `architecture-rules.md`,
`code-quality-rules.md`, `division-terminology.md`, `layout-rules.md`,
`naming-rules.md`, `package-rules.md`. Read-only survey; no Julia was run. All
claims below were checked with `grep`/`find`/`Read`/`git` against the working
tree at the head of `main` (`c28e6e30`).

Root cause tying several findings together: `plan/done/repository-tree.md`
records a completed migration from a nested per-slice layout
(`package/<slice>/{main,test,example}`, e.g. `package/kernel/main/`) to the
current flat layout (`package/<PackageName>/`, e.g. `package/ProjecturedKernel/`,
one package per top-level folder — confirmed live in the tree today, 119
folders under `package/`). `naming-rules.md` documents the flat layout
correctly. `architecture-rules.md`'s "triad" section and two path citations in
`code-quality-rules.md`/`package-rules.md` still describe the retired nested
layout.

---

## documentation/rule/architecture-invariants.md

**Verdict:** UPDATE (a few concrete defects in an otherwise solid, internally
consistent file — do not restructure). **Audience:** contributor and the AI
assistant, by the document's own opening sentence; a library-using Julia
developer would only reach for it when contributing code back. **Size:** 1300
lines / ~10,800 words, 77 `PAR-…` rules.

Special check performed: every `PAR-…` id was extracted from the file's `###`
headings (77) and compared against every `PAR-…` id grepped from `source/`,
`test/`, `package/`, `documentation/`, `SEALING.md`, `CLAUDE.md`.

- All 77 defined ids appear correctly in both the Index table and as a `###`
  heading; no id is missing a heading or a heading missing from the index.
- One id is **cited but never defined**: `PAR-REACTIVE-PRINTER`, at
  `source/widget/ObjectFieldToWidget.jl:97` — `# … a write to the object
  repaints it (PAR-REACTIVE-PRINTER).` No such heading exists anywhere in this
  file. By content, the comment describes reactive output structure ("bind the
  container to a thunk rather than re-print"), which is exactly
  `PAR-REACTIVE-OUTPUT-STRUCTURE`'s subject.
- Of the 77 ids, only 17 are cited anywhere outside this file itself (in
  `source/`, `test/`, other `documentation/`, `SEALING.md`, `CLAUDE.md`); the
  other 60 are never cited in a source comment. This is not a defect —
  `PAR-CITE-EXCEPTIONS-ONLY` (the file's own last rule) explicitly forbids
  citing a rule a piece of code merely complies with — but it means the "ids
  nothing cites" check mostly surfaces expected behaviour, not gaps.
- Every `PR-…` id this file cites (`PR-INTERMEDIATE-STATES`, `PR-UNDO-REDO`,
  `PR-REVISITABLE-HISTORY`, `PR-MANY-EDITORS-ONE-PROCESS`) is a real `####`
  heading in `documentation/requirement/accepted-requirements.md`.
- Spot-checked factual claims all confirmed: the kernel has exactly seventeen
  layers in the stated order (`package/ProjecturedKernel/src/ProjecturedKernel.jl:32-48`);
  `DocumentInterface.jl` and `JsonToSyntax.jl` (cited by `code-quality-rules.md`,
  not this file, but load-bearing for the same claims) match their described
  shape.

Per the assignment's instruction, every finding below is tagged **[wording
only]** or **[changes a rule's meaning]**.

| where | category | finding | evidence | fix | confidence |
| --- | --- | --- | --- | --- | --- |
| `PAR-REACTIVE-PRINTER` citation | CODE-REFERENCE | An id cited in source is not defined anywhere in this file | `source/widget/ObjectFieldToWidget.jl:97`; no `### PAR-REACTIVE-PRINTER` heading exists | **[wording only]** — either fix the source comment to cite `PAR-REACTIVE-OUTPUT-STRUCTURE`, or add `PAR-REACTIVE-PRINTER` as an alias/see-also under it; no existing rule's text needs to change | checked |
| PAR-DOMAINS-INDEPENDENT | FRAMING/STYLE | "A domain knows nothing about how it is displayed" personifies the domain | line 326 | **[wording only]** — "A domain declares nothing about how it is displayed" states the same constraint without agency | checked |
| PAR-INTERFACE-DECLARES-ONLY | FRAMING/STYLE | "that is the signal the layer wants an implementation fragment" personifies the layer | line 924 | **[wording only]** — "that is where the layer needs an implementation fragment" or similar | checked |
| Index row / PAR-EMPTY-PATH-IS-SELECTION | STYLE | "first-class" appears twice (index row, rule body); it is the banned-word list's marketing example, though here it is used in the precise type-theory sense ("not a degenerate special case"), not as a sales adjective | lines 116, 584 | **[wording only]** — if the rewrite wants the word gone regardless of sense, "The empty path is a whole-element selection in its own right, not an absence" preserves the meaning | likely (usage is defensible; flagging only because the word is on the explicit ban list) |
| Whole file | FRAMING | No occurrence of "projectional editor" / "structured editor" / "only an editor"; `PAR-STABLE-FOUNDATIONS` already names "the MCP AI bridge" as a settled foundation alongside the reactive cell system, and `PAR-AI-SAME-GUARANTEES` treats AI edits as a first-order citizen of the edit pipeline | lines 1139-1145, 1147-1156 | No fix needed — this file already supports the new framing; nothing here fights the "AI integration from the ground up" framing | checked |

---

## documentation/rule/architecture-rules.md

**Verdict:** UPDATE — the placement rules and the package-chain description
are sound, but the entire "triad" section's example paths describe a folder
layout the repository no longer has. **Audience:** contributor (specifically,
anyone deciding where a new file goes). **Size:** 255 lines.

| where | category | finding | evidence | fix | confidence |
| --- | --- | --- | --- | --- | --- |
| "The triad" (§, lines 89-102) | STALE | Describes `package/<name>/{main,test,example}` as one grouping folder — e.g. `package/kernel/` holding `ProjecturedKernel`/`ProjecturedKernelTest`/`ProjecturedKernelExample`, and `package/projectured/{main,test,example}` for the umbrella. No such folders exist. | `ls package/kernel`, `ls package/projectured`, `ls package/substrate` all fail (`No such file or directory`); the real tree is flat: `package/ProjecturedKernel/`, `package/ProjecturedKernelTest/`, `package/ProjecturedKernelExample/`, `package/Projectured/`, one folder per package, exactly as `naming-rules.md` states ("The package directory is `package/<PackageName>/`, one folder per package") | Rewrite the section to the flat layout; drop "no `main/` level" language (there was never a folder for it to be a level of, post-migration) | checked |
| "The package chain…" (lines 108-116) | STALE | `package/substrate/{example, test}`, `package/odbc/example`, `package/adaptagrams/example`, `package/tulip/example` are all given as real paths | Actual folders are `package/ProjecturedSubstrateExample`, `package/ProjecturedSubstrateTest`, `package/ProjecturedOdbcExample`, `package/ProjecturedAdaptagramsExample`, `package/ProjecturedTulipExample` | Same fix as above — rename every path to the flat form | checked |
| Line 216, "See architecture requirement #72." | CODE-REFERENCE | Cites a numeric requirement id; `architecture-invariants.md` uses only symbolic `PAR-…` ids now, no numbering | `grep -n "#72"` and `grep -n "#68"` find nothing matching in `architecture-invariants.md`; by content match, #72 is `PAR-INTERFACE-DECLARES-ONLY` ("Every name an interface file declares is exported… its export list is the layer's API surface") | Replace "#72" with `[PAR-INTERFACE-DECLARES-ONLY](architecture-invariants.md#par-interface-declares-only)` | checked |
| Line 230, "See architecture requirement #68." | CODE-REFERENCE | Same stale numbering; by content this is `PAR-NO-TEST-DOUBLES-IN-MAIN` (the `FakeLlm`/`ScriptedLlm` precedent is quoted almost verbatim in both places) | Same as above | Replace with `PAR-NO-TEST-DOUBLES-IN-MAIN` | checked |
| Line 247, "requirement (#72)" | CODE-REFERENCE | Third occurrence of the same stale numeric id, inside the "Enforcement" section | — | Same fix | checked |
| Whole file | DUPLICATE | The placement rules (lowest-home, seam pattern, interface-declares-only, module-boundary-is-API) are restated at rule-level in `architecture-invariants.md` under matching `PAR-…` ids; the two files agree in substance everywhere checked (no contradiction found), and each cites the other, so this is by-design layering (rules vs. decision procedure), not accidental duplication | front matter "Stands on" lines in both files | No fix — this is the intended split; flagging only because the brief asks for overlap | checked |

---

## documentation/rule/code-quality-rules.md

**Verdict:** UPDATE — the conventions described (module file shape, fragment
header, banner, contract fragment, registration seam, docstring shape) all
check out against real files; the numeric/example claims are stale or wrong in
several places. **Audience:** contributor. **Size:** 264 lines.

| where | category | finding | evidence | fix | confidence |
| --- | --- | --- | --- | --- | --- |
| §4, "`package/repl/PrecompileStatements.jl` is generated" | WRONG | That path does not exist; no `package/repl/` folder exists at all | `find . -iname PrecompileStatements.jl` → only `./asset/precompile/PrecompileStatements.jl`, included from `source/repl/Repl.jl:78` | Change to `asset/precompile/PrecompileStatements.jl` | checked |
| §4, "four longest hand-written files": `Widget.jl` at 2107 | WRONG | No file named `Widget.jl` exists anywhere in the repository | `find . -name Widget.jl` → empty | The intended file is almost certainly `source/widget/WidgetDocument.jl` (today 2684 lines) | checked |
| §4, same list: `ProjecturedSdl.jl` at 3033 | WRONG | `package/ProjecturedSdl/src/ProjecturedSdl.jl` (the only file with that exact name) is 75 lines, not 3033 | `wc -l package/ProjecturedSdl/src/ProjecturedSdl.jl` → 75 | The intended file is `source/sdl/Sdl.jl` (today 3084 lines) | checked |
| §4, same list: `WidgetToGraphics.jl` at 6392, `SqlToSyntax.jl` at 2095 | STALE | Current sizes have drifted | `source/widget/WidgetToGraphics.jl` is 6929 lines today (+537); `source/sql/SqlToSyntax.jl` is 2037 lines today (−58) | Refresh the four numbers together with the two file-name fixes above | checked |
| §1, "65 files carry that header" vs §5 table, "Fragment headers \| 63" | CONTRADICTION + STALE | The same measurement is given as 65 in prose and 63 in the baseline table, and the real count today is far higher than either | `grep -rlE "^# Fragment of \`" source/ \| wc -l` → 298 | Reconcile the two numbers with each other, then refresh both against the current count (298) | checked |
| §5, "Section banners \| 1451 in 264 files" | STALE | Today's count is lower | `grep -rP "^#\s*──" source/ \| wc -l` → 1183 (close variant patterns give 1162–1356 depending on dash-run length, all below 1451) | Refresh the baseline table; note the exact grep used, since the count is sensitive to how many dashes are required | likely (exact grep command for the original count is not given in the doc, so the discrepancy could partly be method, not just drift) |
| §4, "A main-code function \| … longest 200" and DocumentInterface.jl "is 193 lines" (§3) | STALE | `source/kernel/document/DocumentInterface.jl` is 215 lines today, not 193 | `wc -l source/kernel/document/DocumentInterface.jl` → 215 | Refresh the number | checked |
| §5 whole table | STALE | Table is dated 2026-08-14; today is 2026-09-17. `Julia files 755` vs. actual 775 across `source+test+example`; `mean 216 lines` vs. actual 200 combined / 251 for `source/` alone; `Files over 500 lines … 61` vs. actual 64 across the same trees. All in the right ballpark — this is normal drift, not a broken claim, and the doc already says "reproduce these with the commands…" | `find source test example -name "*.jl" \| wc -l` → 775; mean 200; files >500 → 64 | No urgent fix — re-run the measurement per the doc's own instructions before the next audit that cites it | checked |
| §7 | STYLE/PROCESS | "The code quality steward audits a slice when its plan moves to `plan/done/`" — this is internal process (which agent runs when), not a contributor-facing rule | line 259 | No fix; flagged only for the audience split below | checked |

---

## documentation/rule/division-terminology.md

**Verdict:** KEEP (small fixes only). **Audience:** all of them — it is the
one document in this set an outside contributor, a library user, and the AI
assistant all need in the same short form, since every other document assumes
its four terms. **Size:** 85 lines, shortest of the seven.

| where | category | finding | evidence | fix | confidence |
| --- | --- | --- | --- | --- | --- |
| "Leaf" definition | DUPLICATE | The leaf rationale ("a package image is built with exactly its own dependencies present, so compiled code survives only in a leaf… `@compile_workload` may appear only in a leaf, and why depending on one makes it stop being one") is restated near-verbatim in `package-rules.md`'s "Why the leaf matters" section, rather than only cross-referenced | division-terminology.md lines 44-49 vs. package-rules.md lines 65-83 | Trim to a one-sentence definition + "see [packages.md](package-rules.md#why-the-leaf-matters) for why" (the file already ends that paragraph with "See packages.md", so the restatement is redundant with its own pointer) | checked |
| Link labels | STYLE (not a break) | `[architecture.md](../design/system-anatomy.md)` (twice) and `[packages.md](package-rules.md)` name the target by an old filename in the link text even though the href is correct and resolves | lines 84, 49 | Cosmetic only — relabel the link text to match the real filenames (`system-anatomy.md`, `package-rules.md`) | checked |
| Cross-doc term usage | — | `package`, `layer`, `slice`, `module`, `leaf` are used in the same sense in `README.md`, `documentation/design/system-anatomy.md`, and `CLAUDE.md` — no contradiction found | `README.md:328,355`; `system-anatomy.md:124,177,329`; `CLAUDE.md:16,23,29` | No fix | checked |
| Layer count | — | "seventeen layers" for the kernel, in the exact stated order, matches `package/ProjecturedKernel/src/ProjecturedKernel.jl:32-48` | see command output above | No fix | checked |

---

## documentation/rule/layout-rules.md

**Verdict:** UPDATE — one real self-contradiction plus a framing problem in
the opening sentence; every type, function and widget name cited was
confirmed to exist. **Audience:** contributor working in the widget/layout
substrate specifically (visual-designer territory), not a general contributor.
**Size:** 222 lines.

Special check: no static guard enforces this document (see cross-file guard
table below); the closest thing is runtime behavioural tests
(`test_layout_allocator`, `test_layout_constraint_helpers`,
`test_graphics_layout`, `test_layout_closeout`, `test_anchored_layout`, all
under `test/substrate/`), which exercise the *result* of a layout pass, not
the rule text itself.

| where | category | finding | evidence | fix | confidence |
| --- | --- | --- | --- | --- | --- |
| Opening line, "How every widget and every layout decides its size" | CONTRADICTION + FRAMING | §6 later states the opposite explicitly: "a widget does **not** decide its own policy, and does not carry layout fields" — the container decides, via `LayoutConstraint`, and the widget only reports its `Content` size. The opening sentence also personifies both widget and layout with "decides." | line 6 vs. lines 213-214 | **Fix:** reword to "How a widget's size is decided, on every axis" or "The rule that decides every widget's size" — matches §6's own correction and drops the personification | checked |
| §1, "policy | size on that axis" table and struct names | — | `Fixed`, `Content`, `Relative`, `Fill` all exist; `const Fill = Relative(1.0)` at `source/layout/LayoutDocument.jl:113` confirms "`Fill === Relative(1.0)` is not a special case" | grep above | No fix | checked |
| §2, `LayoutConstraint` fields "min / preferred / max / weight per axis" | — | `@document struct LayoutConstraint` at `source/layout/LayoutDocument.jl:396` has `min_width/preferred_width/max_width/weight_width` and the `_height` equivalents — matches the doc's description | source/layout/LayoutDocument.jl:396-404 | No fix | checked |
| §3/§3b, `withhold_offer`, `allocate_axis`, `_resolve_size` | — | All three exist as named: `source/kernel/projection/PrinterContext.jl` (and others) for `withhold_offer`; `source/layout/LayoutDocument.jl:570` for `allocate_axis`; `source/widget/WidgetToGraphics.jl:685` for `_resolve_size` | grep above | No fix | checked |
| §5, "the worked case" — `WidgetShell`, `VerticalLayout`, `WidgetLabel`, `WidgetScrollPane` | — | All four types exist in `source/widget/WidgetDocument.jl` / `source/layout/LayoutDocument.jl` | grep above | No fix | checked |
| §6, "What this replaces" | HISTORY | Explicitly a design-record section (self-described: "written down because the reasoning is easy to lose") narrating a past state ("five [constants] once stood in `WidgetToGraphics.jl`, and the 300 among them was…") | lines 218-220 | Likely an intentional, bounded exception (same pattern as `naming-rules.md`'s before/after rename counts) rather than a violation to fix; flagging per the brief's instruction to record any "used to"/"previously" language | likely (the repo's own convention allows a bounded rationale record; this reads as one) |

---

## documentation/rule/naming-rules.md

**Verdict:** UPDATE (small: the rule is sound and detailed, but does not
acknowledge real counter-examples already shipped in `source/`). **Audience:**
contributor. **Size:** 441 lines, second-largest of the seven.

Special check performed: sampled 30 exported, lowercase (non-type) names from
`grep "^export"` across `source/` (271 candidates total after filtering out
CamelCase type/module exports).

Of the 30 sampled, 28 are clean verb-first names (`get_…`, `make_…`,
`with_…`, `record_…`, `resolve_…`, `parse_…`, `evaluate!`, …). Two sampled
hits, followed back to their `export` lines, showed the rule is violated by
shipped code, not just theoretically:

- `source/style/StyleModule.jl:105` exports `font_ascent`, `font_descent`,
  `font_line_height` — all three are noun-first getters (`font_line_height(font)
  -> Int`, `source/style/TrueType.jl:444-448`) with no `get_` prefix.
- `source/sequencechart/SequenceChartModule.jl:54` exports `flow_point`,
  `flow_rect`, `frame_flow_span`, `frame_cross_span` — same pattern
  (`frame_flow_span(f::FlowFrame) -> (lo, hi)`,
  `source/sequencechart/SequenceChartGeometry.jl:17-22`).

That is 7 verb-first violations surfaced from a 30-name sample (23%), all in
two `export` lines — i.e., the rule is fine in the bulk of the 271 exported
functions checked mechanically by `test/suite/naming.jl`, but that guard
explicitly does **not** check verb-first (see the guard table below), so
counter-examples like these ship undetected.

| where | category | finding | evidence | fix | confidence |
| --- | --- | --- | --- | --- | --- |
| "Every function name starts with a verb" | WRONG (rule vs. code) | Real, shipped counter-examples: `font_ascent`, `font_descent`, `font_line_height`, `flow_point`, `flow_rect`, `frame_flow_span`, `frame_cross_span` | see sample above | Either rename the seven to `get_font_ascent` etc. (a real code change, not a doc fix), or add them to a documented, narrow exemption list the way DSL words and declarative macros already have one | checked |
| "Quick reference" table | — | Every shape/example pair in the table (`Projectured<Slice>`, `<File>Module`, `<Slice>Document`, `PAR-…`/`PR-…`, `A<Document>`, …) was spot-checked against real names in earlier steps of this survey and matches | — | No fix | checked |
| "62 names were used more than once… The 191 renames left 12 colliding names" | HISTORY | Before/after counts from a completed rename plan (`plan/done/module-head-in-its-own-file.md`), phrased as design record rather than narration | lines 71, 104 | Likely an intentional, bounded exception (same reasoning as layout-rules.md's §6) — the file names the plan it came from, so a reader who wants the "why" has somewhere to go | likely |
| Overlap with `division-terminology.md`, `package-rules.md`, `system-anatomy.md` | — | Front matter correctly states "Stands on" all three; no contradiction found between this file's package/module naming rules and those three | — | No fix | checked |

---

## documentation/rule/package-rules.md

**Verdict:** UPDATE — several concrete, checkable defects, concentrated in the
dependency table and the workload/precompile section. **Audience:**
contributor (specifically, anyone adding a package — the doc's own closing
section is literally titled "Adding a package"). **Size:** 258 lines.

Special check 1 — five kinds vs. real package list (`ls package/`, 119
entries): main/example/test/repl/build all confirmed present with the stated
suffix convention. The 28 substrate packages and the 20 domain packages named
by architecture-rules.md/system-anatomy.md both count out exactly against the
real folder list.

**One package fits none of the five kinds and is absent from every table in
this document:** `ProjecturedAssistant` (`package/ProjecturedAssistant/`,
`Project.toml` confirms it depends only on
Collection/Conversation/Domain/Natural/Kernel/Layout/Primitive/Projection/Style/Text/Widget
— no third-party dependency, so by the doc's own stem/sub-stem rule it should
be classified as a sub-stem, but it depends on `ProjecturedConversation`, a
domain package, which the substrate-package table would not allow). It has no
`…Test`/`…Example` sibling either.

Special check 2 — `@compile_workload` occurs exactly once as a macro
invocation in the whole tree, at `source/repl/Repl.jl:122`, inside the
`ProjecturedRepl` leaf (`grep -rn "@compile_workload" package/ source/` — the
other hits are `using PrecompileTools: … @compile_workload` import lines and
plain-text mentions, not invocations). This matches the doc's claim that only
a leaf carries one. `ProjecturedExecutable`, the other named leaf, does **not**
use the `@compile_workload` macro at all — it calls
`ProjecturedExample.precompile_workload()` directly inside
`precompile_warmup()` (`source/executable/Executable.jl:116-121`), which is a
narrower mechanism than the doc's "both leaves call the same one, through
`@compile_workload`" framing.

| where | category | finding | evidence | fix | confidence |
| --- | --- | --- | --- | --- | --- |
| Dependency table, `ProjecturedWidget \| … Reflection …` | WRONG | `ProjecturedWidget`'s `Project.toml` has no `ProjecturedReflection` dependency, and no file under `source/widget/` imports it, despite the package file's own header comment mentioning "the reflection-driven form" | `package/ProjecturedWidget/Project.toml` `[deps]`: Collection, Focus, Graphics, Kernel, Layout, Primitive, Projection, Screen, Style, Text — no Reflection; `grep -rl ProjecturedReflection source/widget/` → empty | Drop `Reflection` from the row | checked |
| "The session", `build_executable(…; workload = :live)` | WRONG | The build-side workload parameter's real values are `:none`/`:minimal`/`:demo`/`:full` (per `source/executable/AppConfig.default.jl:26-29`'s own docstring); `:live` is a `ProjecturedRepl`-only level and does not apply to `build_executable` | `source/builder/Builder.jl:77,91` (`workload::Symbol`, default `:none`); `source/executable/AppConfig.default.jl:26-29` | Change the example to `workload = :full` (or whichever level is meant) and separate the REPL's three levels (`:none`/`:recorded`/`:live`) from the build's four (`:none`/`:minimal`/`:demo`/`:full`) — they are two different enumerations sharing a symbol type, not one | checked |
| "Why the leaf matters", "the body it calls — `ProjecturedExample.precompile_workload(level)`" | WRONG | The real function has no `level` parameter: `precompile_workload(; atoms = atomic_documents())` | `example/projectured/Precompile.jl:129`; note its own docstring at line 114 still advertises `precompile_workload(level::Symbol = :minimal; atoms = …)`, so the mismatch exists in the source docstring too, not only here | Drop `(level)`; the function takes only the `atoms` keyword | checked |
| "The session", `\| :recorded \| replays package/repl/PrecompileStatements.jl` | WRONG | Same stale path as `code-quality-rules.md` (see that section) | `source/repl/Repl.jl:78`, actual path `asset/precompile/PrecompileStatements.jl` | Fix path; this is the same fix needed in `code-quality-rules.md` — **DUPLICATE**, fix once and check the other file | checked |
| Whole "Adding/dependency" tables | MISSING | `ProjecturedAssistant` fits none of the five documented kinds and appears in no table | see special check 1 above | Add a row/kind for it, or fold it into "the twenty domains"/application-slice group the way `architecture-rules.md` already treats `workbench`/`conversation` | checked |
| Third-party dependency table | MISSING (minor) | `ProjecturedBench` declares `Statistics` (stdlib) as a dependency; it is named only in `naming-rules.md` ("`ProjecturedBench` is a leaf too") and never appears in this document at all, in any table | `package/ProjecturedBench/Project.toml` `[deps]`: Statistics | Low priority — add a one-line mention beside `ProjecturedBuilder`/`ProjecturedExecutable` | checked |

---

## Cross-cutting: which rules have a machine-checked guard

| document | guard that exists | what it does NOT check |
| --- | --- | --- |
| `architecture-rules.md` / `architecture-invariants.md` (package/layer/slice placement rules) | `test/kernel/layering/CheckLayering.jl`'s `check_layering`, run per package as `test_<slice>_layering()` (27 packages found, e.g. `test_kernel_layering`, `test_json_layering`, `test_substrate_layering`) | Same-layer internal-import boundary is still "transitional" (opt-in per package); the doc's own text says so |
| `naming-rules.md` | `test/suite/naming.jl`: `module_violations`, `alias_violations`, `abbreviation_violations`, `suite_violations`, `duplicate_definition_violations`, `shadowed_extension_violations` — all static, load nothing, run in ~1s | **Explicitly and by design does not check verb-first naming or whether a name "reads as English"** — the file's own header comment says so (lines 9-13: "Whether a verb fits the work is a judgement… This checks only what is mechanical"). This is exactly the gap the naming-rules.md sample check above exploited. |
| `package-rules.md` | `test/projectured/PackageGraphTest.jl`'s `test_package_graph()` — asserts declared deps match source-named deps, no dependency on a `Repl`/`Build` leaf, `@compile_workload` only in a leaf | Does not check the five-kinds classification narrative itself (e.g. it would not have caught `ProjecturedAssistant` going undocumented, since the package graph is legal even though the prose omits it) |
| `division-terminology.md` | Same `CheckLayering.jl`, since the terms it defines (layer/slice) are what that guard enforces | — |
| `code-quality-rules.md` | **No automated guard.** The "measured baseline" (§5) is a set of shell commands a person or the code-quality-steward re-runs by hand; nothing in `test/` fails when a budget is exceeded | The whole document — file-size budgets, banner conventions, comment-history rules — is unenforced except by review |
| `layout-rules.md` | **No static guard.** Only runtime/behavioural tests (`test_layout_allocator`, `test_layout_constraint_helpers`, `test_graphics_layout`, `test_layout_closeout`, `test_anchored_layout`, all `test/substrate/`) exercise the *outcome* of the sizing rule on specific widget trees | Nothing checks that a new widget's printer follows "the widget never decides its own policy" structurally — only that a handful of worked examples size correctly |

## Cross-cutting: PAR-… id audit (full result)

- 77 `PAR-…` ids defined in `architecture-invariants.md`; all have both an
  index row and a `###` heading.
- 78 distinct `PAR-…` tokens appear outside that file across
  `source/`+`test/`+`package/`+other `documentation/`+`SEALING.md`+`CLAUDE.md`
  — 77 of them match a real id, one (`PAR-REACTIVE-PRINTER`) does not.
- No defined id is completely absent from the wider tree in a way that would
  suggest it is dead — every id at minimum appears in its own file, and 17 of
  the 77 are actively cited elsewhere as intended (deviation citations per
  `PAR-CITE-EXCEPTIONS-ONLY`).

## Cross-cutting: language and framing

No instance of "projectional editor," "structured editor," or "only an
editor" phrasing was found in any of the seven files — these are already
framing-neutral, mechanical rule documents, and `PAR-STABLE-FOUNDATIONS` /
`PAR-AI-SAME-GUARANTEES` in `architecture-invariants.md` already treat the
MCP/AI bridge as a foundational, load-bearing part of the system rather than
a bolt-on. The rewrite's new framing does not need to touch these seven files
structurally; it should touch the higher-level concept guides instead.

Banned-word scan (`seamless|powerful|robust|elegant|under the hood|first-class|
out of the box|battle-tested|customers|value proposition|batteries included`)
found only two hits, both "first-class," both in `architecture-invariants.md`
used in the precise type-theory sense, not as marketing language (see that
file's table above). Personification scan (`knows|wants|asks|decides|
refuses|offers|owns`) found the two real hits listed in that file's table plus
the layout-rules.md contradiction; every other hit inspected was either a
technical-ownership statement ("a domain owns its own operations") or a
"person reading code" statement ("a reader who knows the slice"), both of
which the brief's own carve-out allows.

## Cross-cutting: audience split for the Reddit/Discourse rewrite

**Short form an outside contributor needs** (a PR-sized excerpt, not the full
document):
- `division-terminology.md`'s "the rules in one picture" diagram and four
  term definitions — the one piece of vocabulary every other document assumes.
- `naming-rules.md`'s final "Quick reference" table.
- `architecture-rules.md`'s "four levels of division" table (once the triad
  section is fixed).
- `package-rules.md`'s "five kinds" table and "one dependency direction" block.
- `layout-rules.md` §1 (the one clamp formula and the four-policy table) —
  only for a contributor touching the widget/layout substrate.
- `code-quality-rules.md` §1 ("the shape of a file") — module file, fragment
  header, banner, docstring shape — the four things a first PR's diff will be
  reviewed against.
- A short list from `architecture-invariants.md` of the handful of rules that
  bite on a first contribution: `PAR-FOUR-FUNCTIONS`, `PAR-ONE-WAY-TO-EDIT`,
  `PAR-READER-IS-PURE`, `PAR-SMALLEST-TEST`, `PAR-NAMING-LAW`.

**Internal process, not needed by a first-time contributor:**
- `code-quality-rules.md` §5 ("The measured baseline") and §7 ("How this
  document is used" — the code-quality-steward's review cadence).
- `architecture-invariants.md`'s edge-case carve-outs written for maintainers
  doing deep refactors (`PAR-PER-EDITOR-STATE`'s "accepted carve-out" reasoning,
  `PAR-QUALIFIED-EXTENSION`'s three-guard mechanics, the whole "Enforcement"
  section of `architecture-rules.md`).
- `package-rules.md`'s "The session" precompile-level mechanics (workload
  levels, `~/.julia/compiled` sizes, the `record_precompile_statements()`
  workflow) — build/release engineering, not a first PR's concern.
- The sealed-file protocol pointer in `code-quality-rules.md` §3 ("A sealed
  file is frozen") — relevant only once a contributor's diff touches
  `source/kernel/`.

---

## Top findings of this area (most important first)

1. `architecture-rules.md`'s entire "triad" section (package/kernel/,
   package/projectured/, package/substrate/, package/odbc/example, …)
   describes the pre-migration nested package layout;
   `plan/done/repository-tree.md` records the migration to the current flat
   `package/<PackageName>/` layout, which `naming-rules.md` already documents
   correctly. [STALE, checked]
2. `package-rules.md` and `code-quality-rules.md` both cite
   `package/repl/PrecompileStatements.jl`, a path that does not exist; the
   real generated file is `asset/precompile/PrecompileStatements.jl`
   (`source/repl/Repl.jl:78`) — same root cause as #1. [WRONG, checked, in two files]
3. `package-rules.md`'s dependency table claims `ProjecturedWidget` depends on
   `ProjecturedReflection`; its `Project.toml` has no such dependency and no
   source file imports it. [WRONG, checked]
4. `package-rules.md` gives `build_executable(…; workload = :live)` as the
   build-time example; the real, documented levels for the build path are
   `:none`/`:minimal`/`:demo`/`:full` (`:live` is a REPL-only level, a
   different enumeration entirely). It also cites
   `ProjecturedExample.precompile_workload(level)`; the real function takes no
   `level` argument, only a keyword `atoms`. [WRONG, checked]
5. `ProjecturedAssistant` is a real, dependency-declared package that fits
   none of `package-rules.md`'s five documented kinds and appears in none of
   its tables. [MISSING, checked]
6. `naming-rules.md`'s "every function name starts with a verb" law has real,
   shipped counter-examples: `font_ascent`/`font_descent`/`font_line_height`
   and `flow_point`/`flow_rect`/`frame_flow_span`/`frame_cross_span` are all
   noun-first getters — and `test/suite/naming.jl`, the guard that would
   normally catch drift, explicitly declines to check this rule by design.
   [WRONG (code vs. rule), checked]
7. `layout-rules.md` opens with "How every widget and every layout decides its
   size," then its own §6 states the opposite: "a widget does not decide its
   own policy, and does not carry layout fields." Internal contradiction, and
   the opening line personifies the widget. [CONTRADICTION + FRAMING, checked]
8. `architecture-invariants.md` is cited in source as `PAR-REACTIVE-PRINTER`
   (`source/widget/ObjectFieldToWidget.jl:97`), an id this file never defines;
   by content the citation means `PAR-REACTIVE-OUTPUT-STRUCTURE`.
   [CODE-REFERENCE, checked]
9. `code-quality-rules.md`'s "four longest hand-written files" list names two
   files that are not the files it means: `Widget.jl` does not exist anywhere
   in the repository (the 2684-line file is `source/widget/WidgetDocument.jl`),
   and `ProjecturedSdl.jl` is 75 lines, not 3033 (the 3084-line file is
   `source/sdl/Sdl.jl`). [WRONG, checked]
10. `code-quality-rules.md`'s fragment-header count is internally
    inconsistent (65 in prose vs. 63 in its own baseline table) and both
    numbers are far below the real count today (298 files carry that header).
    [CONTRADICTION + STALE, checked]
11. `architecture-rules.md` cites "architecture requirement #72" and "#68"
    three times; `architecture-invariants.md` has used only symbolic
    `PAR-…` ids for some time, with no numbered requirements at all. By
    content, #72 is `PAR-INTERFACE-DECLARES-ONLY` and #68 is
    `PAR-NO-TEST-DOUBLES-IN-MAIN`. [CODE-REFERENCE, checked]
12. Two personification examples matching the framing brief's banned pattern
    sit in `architecture-invariants.md`: "A domain knows nothing about how it
    is displayed" (PAR-DOMAINS-INDEPENDENT) and "that is the signal the layer
    wants an implementation fragment" (PAR-INTERFACE-DECLARES-ONLY).
    [FRAMING/STYLE, checked]

---

# Survey area D — kernel guides (cell, document, macros, projection)

Files: `documentation/package/kernel/{architecture,cell,document,macros,projection-system,generic-projections,higher-order-projections}.md`

Scope note: all seven files carry the same header — `Kind: reference · Status: current · Stands on: system-anatomy.md`.

---

## 1. architecture.md

**Verdict: UPDATE.** Facts are wrong or internally contradictory in several places; the layer/folder inventory itself is accurate and the document is otherwise well organized. **Audience:** contributor to this repository.

| where | category | finding | evidence | fix | confidence |
|---|---|---|---|---|---|
| "Folder layout" header, L149-151 | STALE | Says layer folders live "under `main/`" and links `package/ProjecturedKernel/`. The real layer folders are `source/kernel/<layer>/`; `package/ProjecturedKernel/` holds only `Project.toml` + one aggregator `src/ProjecturedKernel.jl` that `include()`s the `source/kernel/...` files. `main/` is not a directory anywhere in the repo. | `find package/ProjecturedKernel -maxdepth 2 -type d` → only `src`; `package/ProjecturedKernel/src/ProjecturedKernel.jl` includes `"../../../source/kernel/cell/CellLayer.jl"` etc. | Say "under `source/kernel/`"; drop the `main/` phrasing repo-wide (see top finding below). | checked |
| "Folder layout" table, L151-171 | MISSING | The table has one row per folder but omits `clock/` — layer 2 in the very same file's "Layered structure" list two sections above. 15 rows for 17 layers (also check `operation/` — present). | Table rows: cell, event, device, gesture, backend, document, reference, selection, operation, binding, iomap, projection, tool, llm, agent, editor — no `clock` row. | Add a `clock/` row (Clock, `get_reactive_clock_time`/`get_clock_time`, `set_clock_time!`). | checked |
| "Fan-in" table, L96-104 | CONTRADICTION | The "Layer" column contradicts the "Layered structure" list nine lines above, in the same file: table says `DocumentModule`=6, `ReferenceModule`=7, `OperationModule`=9, `EventModule`=2, `ProjectionApiModule`=11; the layer list says document=7, reference=8, operation=10, event=3, projection=13. The table predates the `clock` layer's insertion at layer 2 and was never renumbered. | architecture.md L34-51 vs L96-104, same file. | Renumber the Layer column (+1 for everything at or after event, since clock now sits at 2). | checked |
| "Fan-in" table, L103 | WRONG | `ProjectionApiModule` does not exist anywhere in `source/` or `package/` — only in this doc and two other docs outside this assignment (`documentation/guide/new-domain-guide.md`, `documentation/rule/naming-rules.md`). The projection layer's interface fragment is `ProjectionInterface.jl`, which is not its own module — it is a fragment of `ProjectionModule` (no `module` keyword, per its own header comment). | `grep -rn "ProjectionApiModule" source/ package/` → 0 hits. | Replace with `ProjectionModule` (or drop the row; the interface fragment has no fan-in of its own since it isn't a module). | checked |
| "Fan-in" table, imported-by counts | STALE | A rough re-count (`grep -rl "\.\.<Module>\b" source/kernel/`) gives DocumentModule=7, ReferenceModule=5, CellModule=8, OperationModule=4, EventModule=6 against the claimed 11/10/10/9/7 — none match. | grep counts above. | Re-count and update, or drop exact numbers in favor of "the hubs are roughly…". | likely |
| L60 | STALE | "The package file [main/ProjecturedKernel.jl](...)" — prose names a `main/ProjecturedKernel.jl` path that does not exist; the link target (which does resolve) is `package/ProjecturedKernel/src/ProjecturedKernel.jl`. | Same link-target-vs-prose mismatch as the `cell.md`/`generic-projections.md`/`higher-order-projections.md`/`projection-system.md` cases (see Top Findings). | Say `package/ProjecturedKernel/src/ProjecturedKernel.jl`. | checked |
| L166 | WRONG | Folder table row for `projection/` says the interface lives in "ProjectionApi" and concrete combinators live in `ProjecturedProjection` — the second half is correct (verified: `package/ProjecturedProjection/src/ProjecturedProjection.jl` includes `source/projection/ProjectionAlgebraModule.jl`), the first half repeats the nonexistent `ProjectionApi` name. | Same as the fan-in finding above. | Say "ProjectionInterface.jl / ProjectionModule". | checked |
| Whole file | FRAMING | The document is purely mechanical ("what depends on what") with no reference to the new framing (on-demand UI, reflection, AI). That is appropriate for a contributor-facing architecture doc — no change needed here; the framing belongs in the reflection/`ObjectToWidget` docs (see the cross-file section at the end of this report). | — | none needed | n/a |

---

## 2. cell.md

**Verdict: KEEP** (small fixes). The conceptual content — `Cell`/`ReactiveCell`/`MutableCell`/`ImmutableCell`, tracking, invalidation, invariants — is accurate against `source/kernel/cell/*.jl`, checked line by line. **Audience:** Julia developer using ProjecturEd as a library, and contributor.

| where | category | finding | evidence | fix | confidence |
|---|---|---|---|---|---|
| L157 | WRONG | Layer-structure diagram names the file `PerformanceCounter.jl`; the real file is `PerformanceCounterModule.jl`. | `find source/kernel/cell -iname "*.jl"` → `PerformanceCounterModule.jl`, no `PerformanceCounter.jl`. | Rename in the diagram. | checked |
| L269 | LINK / WRONG | "See `clock/Clock.jl` for the API" — the real file is `source/kernel/clock/ClockModule.jl`; `Clock.jl` does not exist. | `find source/kernel/clock -iname "*.jl"` → `ClockLayer.jl`, `ClockModule.jl`. | Say `clock/ClockModule.jl`. | checked |
| L152 | STALE | "The layer lives in [package/kernel/main/cell/](../../../source/kernel/cell/)" — prose names `package/kernel/main/cell/`, a path that has never existed under that name; only the link target (`source/kernel/cell/`) is right. | Same systemic issue, see Top Findings. | Say `source/kernel/cell/`. | checked |
| Link, `../../../source/kernel/editor/Editor.jl` (in the "PerformanceCounterModule" section, "the easiest way is to profile...") | LINK | Broken link: the file is `EditorModule.jl`, not `Editor.jl`. | `find source/kernel/editor -iname "*.jl"` → `EditorModule.jl`, `EditorLayer.jl`, `PlaybackModule.jl`; no `Editor.jl`. | Fix link target to `EditorModule.jl`. | checked |
| Whole file, checklist item ("aliases RCFoo/MCFoo/ICFoo/DCFoo, `copy_document`, `sync_document!`") | MISSING | cell.md never mentions the `RCFoo`/`MCFoo`/`ICFoo`/`DCFoo` alias family, `copy_document`, or `sync_document!` at all (checked: zero hits for all five terms). Those all live conceptually one level up, wired through `@document`/`document.md`, but a reader of "the cell kinds" guide who wants to know how a document *converts between* cell kinds finds nothing here and no forward pointer either. | `grep -n "RCFoo\|MCFoo\|ICFoo\|DCFoo\|copy_document\|sync_document" cell.md` → only `get_performance_counters` matches (unrelated). | Add a short "kind conversion" pointer section linking to `document.md`'s `copy_document`/`sync_document!` and to `macros.md`'s alias table, so the three cell-kind mechanisms (declare, convert, sync) are reachable from the cell guide. | checked |
| Idioms section | STYLE | Minor — "Cell(Cell[...]) inside CellVector" idiom describes `CellVector` (a substrate/collection type) without saying which package it lives in; a reader following only kernel docs cannot locate it. Not wrong, just under-scoped. | — | Add one clause: "`CellVector`, defined in `ProjecturedCollection`". | likely |

---

## 3. document.md

**Verdict: KEEP.** This is the most accurate of the seven files — every named file, generic function (`is_element_collection`, `is_walk_opaque`, `copy_document`, `sync_document!`, `search_documents`, `is_descendable_for_sync`, `sync_element_limit`, `make_unsynced_placeholder`), and link target was verified against `source/kernel/document/*.jl` and matches exactly. **Audience:** contributor / library user extending the document layer.

| where | category | finding | evidence | fix | confidence |
|---|---|---|---|---|---|
| "The reflection walk" section | MISSING | Documents the *static* structural walk (`walk_document`, `search_documents`) accurately, but never mentions the separate **on-demand / bounded reflection** substrate (`source/reflection/`: `BoundedSync.jl`, `DocumentReflection.jl`, `ReflectionToWidget.jl`) that is built on top of the same three sync-policy generics this file *does* document (`is_descendable_for_sync`/`sync_element_limit`/`make_unsynced_placeholder`). That substrate is the concrete mechanism that lets a live/running object grow its shadow tree one level at a time on click — directly relevant to the new framing (see the cross-file section below). Since document.md already documents the generic policy hooks correctly, it is the natural place to add one forward-pointing paragraph. | `source/reflection/ReflectionToWidget.jl` comment: "The laziness lives in the sync... a node whose `children` slot holds an `UnsyncedDocument` is a node nobody has opened yet; expanding it sets that marker's `requested` flag, and the next sync fills it in one level deeper." Uses exactly the policy hooks `document.md` L92-100 describes. `grep -i "reflection\|BoundedSync" document.md` → no mention of the package. | Add a short paragraph after "The value protocol": "the bounded/policed walk is what `ProjecturedReflection`'s `BoundedSync` rides on to grow a live object's shadow tree on demand — see [reflection.md] (does not yet exist)". | checked |
| L153 | LINK (ok, verify) | Link to `test/kernel/document/DocumentContractTest.jl` — file exists and matches. No issue. | `find test -iname DocumentContractTest.jl` → `test/kernel/document/DocumentContractTest.jl`. | none | checked |
| Whole file | FRAMING | No "only an editor" language; describes the document contract in domain-neutral terms already ("every projection consumes", "concrete documents belong to the packages built on top of it"). Compatible with the new framing as-is. | — | none | n/a |

---

## 4. macros.md

**Verdict: REWRITE.** The `@document`/`@projection`/`@iomap` core is accurate in spirit but the `@document` section describes an old, simpler shape of the macro; the file is also missing the single most-used projection-authoring macro in the codebase. **Audience:** contributor and Julia-developer-as-library-user (anyone declaring a domain).

| where | category | finding | evidence | fix | confidence |
|---|---|---|---|---|---|
| `@document` section | MISSING (major) | The real `@document` macro (`source/kernel/document/DocumentMacro.jl` L419-518, its own docstring) accepts an optional **layout list** — `@document [C, M] struct T … end`, codes `C`/`DC`/`M`/`I` — that decides which representations are emitted and what the bare name `T` binds to (cell layout vs. `MFoo` vs. `IFoo` immutable native vs. `DCFoo` default-cell). macros.md's `@document` section never mentions this syntax; it describes only the fixed old shape (stem + `AFoo` family + `MFoo` native layout), with no `[C,M]`/`[DC]`/`[I]` at all. | `source/kernel/document/DocumentMacro.jl` L425 docstring signature `@document [Kind] [[layouts]] struct T [<: Super] ... end`; `grep -n "\[C, M\]\|layout list" documentation/package/kernel/macros.md` → 0 hits. | Rewrite the `@document` section around the current docstring: the layout-list table, `@document_preset`, Rule Y and Rule C. | checked |
| `@document` section | MISSING | `@document_preset` (a real, exported macro, `DocumentMacro.jl:721`, "declares [a layout list] once… writes the preset's name instead") is not mentioned anywhere in macros.md. | `grep -n "macro document_preset" source/kernel/document/DocumentMacro.jl` → line 721; `grep "@document_preset" macros.md` → 0 hits. | Add a subsection. | checked |
| `@document` section | MISSING | **Rule C** — the single-collection positional constructor ("when exactly one field's declared type opts into `is_collection_field_type`…") — is a named, documented rule in the source (`DocumentMacro.jl` L338, L365, L501) but macros.md documents only **Rule Y** (defaults). | `grep -n "Rule C" source/kernel/document/DocumentMacro.jl` → 5 hits; `grep "Rule C" macros.md` → 0 hits. | Add a Rule C subsection alongside the existing Rule Y one. | checked |
| L113-119 (`StyleText` worked example) | STALE | The example shows `@document ImmutableCell struct StyleText … end` (no layout list). The real declaration, `source/style/StyleText.jl:21`, is `@document ImmutableCell [DC] struct StyleText …` — the `[DC]` is load-bearing (per that file's own comment: "`[DC]` binds the bare name to the default spelling, so `StyleText` is concrete and inlines in a config cell — which is what 455 uses of `ImmutableCell{StyleText}` ask for"). Omitting it in the doc changes what the bare name `StyleText` means. | `source/style/StyleText.jl` L16-21. | Update the example to `@document ImmutableCell [DC] struct StyleText`. | checked |
| L1, L7-10 | STALE/WRONG (major) | Title and opening claim only three macros exist ("Three macros — `@document`, `@projection`, and `@iomap`"). `@projection_template` (`source/kernel/projection/ProjectionTemplate.jl:1358`) is not mentioned anywhere in this file, despite being — per the source file's own header comment — how "every structural projection is written… rather than as a hand-written printer and reader pair," and per this repo's own memory note ("prefer-projection-template.md"). It is used in 17 files (json, rst, and others) with its own marker-word DSL (`bound`, `project`, `collection`, `tokens`, `sections`). | `grep -rl "@projection_template" source/` → 17 files; `source/kernel/projection/ProjectionTemplate.jl` L1-14 comment: "Every structural projection is written with it rather than as a hand-written printer and reader pair." `grep "@projection_template" macros.md` → 0 hits. | Add a full section on `@projection_template` — this is the single biggest gap in the kernel macro docs. | checked |
| L9-10 | LINK | "defined in… [projection/Projection.jl](../../../source/kernel/projection/Projection.jl)" — no such file. `@projection` is defined in `source/kernel/projection/ProjectionMacro.jl`. | `ls source/kernel/projection/Projection.jl` → No such file or directory; `grep -n "macro projection" source/kernel/projection/ProjectionMacro.jl` → line 32. | Fix link to `ProjectionMacro.jl`. | checked |
| L283-298 (`WidgetButtonToGraphicsCanvas` default-fields example) | WRONG (major) | The example shows a 5-field struct (`measure`, `label::StyleText`, `background_color`, `corner_radius::Int = 4`, `shadow_offset::Int = 0`) to demonstrate the `@kwdef`-style default feature. The real struct, `source/widget/WidgetToGraphics.jl:338`, has **11 fields**, `label::ImmutableCell{StyleText}`, and **no defaults at all** — `corner_radius`/`shadow_offset` are plain required `Int` fields today. Running this example against the real type would not compile as shown, and the keyword constructor it shows (`WidgetButtonToGraphicsCanvas(; measure, label, background_color)`) would today require 6 more keywords (`hover_color`, `active_color`, `border`, `padding`, `disabled_color`, `disabled_foreground`, `ring_color`). | `source/widget/WidgetToGraphics.jl` L338-350. | Replace with a currently-accurate example — e.g. one of the `JsonToSyntax.jl` `…ToSyntaxLeaf` structs, which do carry inline defaults today (`style::ImmutableCell{StyleText} = StyleText(...)`, verified). | checked |
| Scope: `@domain`/`@insertion` sections | FRAMING / scope | `@domain` and `@insertion` (`source/domain/Domain.jl`) are documented as if kernel macros, but they live in the separate `ProjecturedDomain` package (built *on* the kernel, not part of it) — consistent with `architecture.md`'s own claim that the kernel carries "no concrete documents." The macro *content* checked out accurate (root=/nothing=/insertion= options match the source exactly), but filing it under "kernel/macros.md" contradicts the kernel/substrate split the other six files insist on. | `package/ProjecturedDomain/src/ProjecturedDomain.jl` — separate package, `using ProjecturedKernel`. | If the rewrite keeps a package-scoped doc structure, move `@domain`/`@insertion` to a domain-package guide (or keep here but state explicitly this page also covers the domain package). | checked |
| Whole file | FRAMING | No "only an editor" language to fix; already framed around "generate the boilerplate." | — | none | n/a |

---

## 5. projection-system.md

**Verdict: UPDATE.** The conceptual core (the four/entry-point functions, the recursion contract, School A vs. the former School B) is the strongest writing in the set and is accurate. Facts are wrong in the file-path/type-name layer and the file is missing a real fifth/sixth interpreter entry point that already shipped. **Audience:** contributor and Julia-developer writing a custom projection.

| where | category | finding | evidence | fix | confidence |
|---|---|---|---|---|---|
| L14-16, and repeated at L32, L296 | LINK / WRONG (major) | "the four functions… declared in [package/kernel/main/projection/ProjectionApi.jl](../../../source/kernel/projection/ProjectionApi.jl)" — the file does not exist. The real file is `source/kernel/projection/ProjectionInterface.jl`, and it is not its own module (`ProjectionApiModule` does not exist — see architecture.md finding above); it is a fragment of `ProjectionModule`. | `ls source/kernel/projection/ProjectionApi.jl` → missing; `find source/kernel/projection -iname "*ProjectionApi*"` → empty; `source/kernel/projection/ProjectionInterface.jl` L1-6 header: "Fragment of `ProjectionModule`". | Fix link and prose to `ProjectionInterface.jl`, drop the "ProjectionApi" name throughout. | checked |
| "The four functions" (whole section) | MISSING (major) | `ProjectionInterface.jl` declares **seven** open generics, not four: `print_document`, `print_child`, `print_document_pure`, `print_child_pure`, `read_intent`, `map_reference_forward`, `map_reference_backward`. `print_document_pure`/`print_child_pure` are a real, shipped second interpreter — "a second interpreter of a projection that produces the projected output document tree directly — no iomap, no reactive cells, no selection wiring — for batch/export use (write_image / write_pdf / text serialization)". They have a universal default (fall back to a snapshot of the reactive output) so "only these four are universal" is still roughly defensible for a projection *author*, but the guide never once mentions that a pure/batch rendering path exists at all — a real capability (headless export) with zero documentation. | `source/kernel/projection/ProjectionInterface.jl` L87-129 (`print_document_pure`, `print_child_pure` docstrings); used today in `source/projection/higherorder/{Chaining,Recursive,TypeDispatching}.jl` and `source/kernel/projection/ProjectionDefaults.jl:40` (universal fallback). | Add a subsection: "the pure/batch printer" — what `print_document_pure` is for, that it defaults automatically, and when a projection author would implement it directly (perf-sensitive export paths). | checked |
| Category table, L408 ("Domain-to-domain" row) | WRONG | `TableToGraphics` is listed as a real member alongside `JsonToSyntax` etc. No "table" domain, no `TableTable` struct, and no `TableToGraphics` function/type exist anywhere in `source/`. It is also asserted (as real) in `documentation/design/system-anatomy.md:289` and `documentation/guide/examples-tour.md:123-128` — a 3-file-wide phantom domain, not just a slip here. | `grep -rn "TableToGraphics" source/` → 0 struct/function definitions, only doc/comment mentions; `find source -type d -iname table` → nothing; `grep -rn "struct TableTable" source/` → nothing. | Remove `TableToGraphics` from the row (or, if it is a planned example, mark it explicitly as planned/removed rather than listing it as current). | checked |
| Category table, L409 ("Domain-preserving" row) | WRONG | Lists `LineNumbering` and `GraphicsCaching` as member names. The real struct names are `TextLineNumbering` (`source/text/TextLineNumbering.jl`) and `GraphicsCanvasToGraphicsImage` (`source/graphics/GraphicsCaching.jl`) — `LineNumbering` and `GraphicsCaching` (as type names) do not exist. | `grep -n "struct LineNumbering\b" source/` → 0 hits; `grep -n "struct GraphicsCaching\b" source/graphics/GraphicsCaching.jl` → 0 hits, only `struct GraphicsCanvasToGraphicsImage`. | Rename the two table entries to the real struct names. | checked |
| L139, 296 | LINK | `[projection/Intent.jl](../../../source/kernel/operation/Intent.jl)` — wrong filename; real file is `IntentModule.jl`. Directory is right, filename is not. | `find source/kernel/operation -iname "Intent*.jl"` → `IntentModule.jl` only. | Fix link. | checked |
| L295 ("Recursive gesture reading" section) | LINK (secondary) | Same `ProjectionApi.jl`/`Projection.jl` broken-link pattern recurs three times total in this file (L32, L110-ish "projection/Projection.jl" for the 2-arg overload, L296). The 2-arg `print_document(p, input)` convenience overload is actually in `ProjectionDefaults.jl`, not `Projection.jl`. | `grep -n "function print_document(projection, input)" source/kernel/projection/ProjectionDefaults.jl` → line 7. | Fix all three. | checked |
| Whole file | FRAMING | Strongly supports the new framing already: "every screen the user sees, and every gesture they make, flows through one or more projections" and the whole "generic projections operate on any input by structure, not by type" theme is exactly the on-demand-UI story. No "only an editor" language to remove. | — | keep, reuse for the rewrite's opening | n/a |

---

## 6. generic-projections.md

**Verdict: UPDATE.** Short, otherwise clean file; its one structural claim (9 members, one folder) is checked wrong for 1 of 9. **Audience:** contributor / library user composing projections.

| where | category | finding | evidence | fix | confidence |
|---|---|---|---|---|---|
| L9-14 | WRONG | Claims "the nine projections in `package/kernel/main/projection/generic/`" are `IdentityProjection, ConstantProjection, CopyingProjection, ReversingProjection, SortingProjection, FocusingProjection, FilteringProjection, SearchingProjection, ObjectToWidget`. The real folder (`source/projection/generic/`) holds only **8** files/structs (`Identity, Constant, Copying, Reversing, Sorting, Focusing, Filtering, Searching`); `ObjectToWidget` is defined in `source/widget/ObjectToWidget.jl`, a different package (`ProjecturedWidget`-ish slice), not in this folder at all. | `ls source/projection/generic/` → 8 `.jl` files, one struct each (verified by `grep "^struct " source/projection/generic/*.jl`); `grep -rn "struct ObjectToWidget" source/` → `source/widget/ObjectToWidget.jl:64`. | Either split the table (8 domain-independent combinators in `source/projection/generic/`, plus `ObjectToWidget` called out separately as living in the widget package for the same input-independence reason), or correct the folder claim. | checked |
| L9 | STALE | Same `package/kernel/main/projection/generic/` path issue as the other files — does not exist under that name. | See Top Findings. | Say `source/projection/generic/`. | checked |
| Whole file | MISSING (new framing) | This file is the natural home for explaining *why* reflection-driven, structure-not-type projections matter for "on-demand views of any Julia value" — `ObjectToWidget`'s docstring already frames it that way ("Generic, reflection-driven projection from an arbitrary object to a widget form that displays and edits the object's reactive parameters") but this guide's one-line table entry ("emits a labelled control row per editable Cell field") does not connect it to that framing, and never mentions its newer sibling `ReflectionToWidget`/`DocumentReflection`/`BoundedSync` (see cross-file section). | `source/widget/ObjectToWidget.jl` L1-30 comment vs. generic-projections.md L26 (one line). | Expand the `ObjectToWidget` entry; add a pointer to the lazy/bounded reflection successor. | checked |
| Whole file | FRAMING | Otherwise this file is one of the best-aligned with the new framing already ("operate on any document by structure, not by type"). | — | keep | n/a |

---

## 7. higher-order-projections.md

**Verdict: UPDATE.** Same pattern as generic-projections.md: good conceptual writing, wrong/stale inventory of where things live, plus an internal contradiction about domain-independence. **Audience:** contributor / library user composing projections.

| where | category | finding | evidence | fix | confidence |
|---|---|---|---|---|---|
| L5-13 | CONTRADICTION | Intro states higher-order projections "never touch any specific domain — their argument is always some other projection." The same table two lines later lists `WindowManagingProjection` (dispatches on `ScreenDocument`/`WindowDocument`), `TooltipDecoratorProjection` ("dispatches on `TooltipSource`"), and `DraggingProjection` ("dispatches on `DraggingState`") — all three explicitly dispatch on a *named domain-specific document type*, not merely "some other projection." | Table's own "Selects by" column, L24-27, names `TooltipSource`/`DraggingState`/`ScreenDocument` directly. | Soften the opening claim, or split the table into "domain-free combinators" (Chaining/TypeDispatching/PredicateDispatching/ReferenceDispatching/Recursive/Switching/Nesting) vs. "domain-shaped decorators" (WindowManaging/TooltipDecorator/Dragging/ProjectionConfiguring). | checked |
| L7-8 | WRONG | "the generic combinators in `package/kernel/main/projection/higherorder/`" — real folder `source/projection/higherorder/` holds only **8** of the table's 12 members (`Chaining, Nesting, PredicateDispatching, Recursive, ReferenceDispatching, Switching, TypeDispatching, WindowInputUnwrapping`). The remaining 4 — `WindowManagingProjection`, `TooltipDecoratorProjection`, `DraggingProjection`, `ProjectionConfiguringProjection` — live in four separate packages (`source/screen/`, `source/tooltip/`, `source/dragging/`, `source/widget/`), not in "`package/projection/main/`" as the same sentence claims for "the document-shaped ones" (that path does not exist either — no package is named literally `projection`). | `ls source/projection/higherorder/` → 8 files; `grep -rn "struct WindowManagingProjection\|struct TooltipDecoratorProjection\|struct DraggingProjection\|struct ProjectionConfiguringProjection" source/` → `source/screen/WindowManaging.jl`, `source/tooltip/TooltipDecorator.jl`, `source/dragging/Dragging.jl`, `source/widget/ProjectionConfiguring.jl`. | Rewrite the intro sentence to name the real packages (`ProjecturedProjection` for the 8 generic-purpose ones; `ProjecturedScreen`/`ProjecturedTooltip`/`ProjecturedDragging`/`ProjecturedWidget` for the other 4, matching each one's actual dependency). | checked |
| "Key file" column, `ChainingProjection` row | WRONG | Says `Sequential.jl`. No such file exists; the real file is `Chaining.jl`. | `find source -iname "Sequential.jl"` → nothing; `source/projection/higherorder/Chaining.jl` defines `struct ChainingProjection`. | Fix to `Chaining.jl`. | checked |
| "Key file" column, `SwitchingProjection` row | WRONG | Says `Alternative.jl`. No such file exists; the real file is `Switching.jl`. | `find source -iname "Alternative.jl"` → nothing; `source/projection/higherorder/Switching.jl` defines `struct SwitchingProjection`. | Fix to `Switching.jl`. | checked |
| "Key file" column, `WindowManagingProjection` row | WRONG | Says `WindowManager.jl`. No such file exists; the real file is `WindowManaging.jl` (in `source/screen/`, not the higherorder folder at all — see the folder-location finding above). | `find source -iname "WindowManager.jl"` → nothing; `source/screen/WindowManaging.jl:27` defines `struct WindowManagingProjection`. | Fix to `WindowManaging.jl` and correct its folder. | checked |
| Whole file, "list every projection... report undocumented ones" | MISSING | Several structurally similar decorator projections exist elsewhere and are undocumented here despite fitting the same "transparent decorator" pattern this file explains for `TooltipDecoratorProjection`/`DraggingProjection`: `CommandPaletteDecoratorProjection` (`source/gesturehelp/CommandPaletteDecorator.jl`), `GestureHelpDecoratorProjection` (`source/gesturehelp/GestureHelpDecorator.jl`), `GestureLogOverlayProjection`/`GestureLogRecordingProjection` (`source/gesturelog/`), `WidgetHoverTrackingProjection`/`WidgetPopupResolverProjection` (`source/widget/`). Not necessarily all belong in this guide (some may be closer to domain-specific), but the file claims its table is exhaustive ("There are twelve higher-order projections in ProjecturEd") which is contradicted by these. | `grep -rn "^struct .*Projection\b" source/` (full listing done for this survey) → the six names above, all `<: Projection`, none appearing in this file's table. | Either fold these in (if they are genuinely domain-independent decorators) or add one sentence explaining the boundary ("this table is generic higher-order projections only; each domain/package may add its own decorator following the same shape — see e.g. `CommandPaletteDecoratorProjection`"). | checked |
| Whole file | FRAMING | Good material already: "compose other projections," "argument is always some other projection" is close to the new framing's compositional story. | — | keep, fix contradiction above | n/a |

---

## Cross-cutting: architecture.md vs. documentation/design/system-anatomy.md

Grep confined to `system-anatomy.md` as instructed.

- **Duplicate content, not just overlap.** `system-anatomy.md` L347-378 carries its own complete, independently-written 17-layer table ("Inside ProjecturedKernel — 17 layers, in include order…") with per-layer contents, essentially the same information as `architecture.md`'s "Layered structure" section (L28-51). The two lists **agree with each other** (both correctly include `clock` at layer 2, both number 1-17 identically) — so the duplication is not itself a factual bug, but it is real duplication: any future layer add/remove/reorder has to be made in two files by hand, and `architecture.md`'s own **internal** fan-in table already proves that upkeep discipline fails in practice (see the CONTRADICTION finding above — that table drifted out of sync with its neighboring section in the very same file, seven lines apart). **DUPLICATE, target: `system-anatomy.md`** is the more likely canonical home for readers who don't need kernel internals; `architecture.md` could hold only the parts system-anatomy.md doesn't (the interface-files-as-SPI section, the include-order guard, the fan-in table) and reference the layer table by link rather than repeating it.
- `system-anatomy.md` L340 independently confirms the **substrate package name and contents** for the generic/higher-order combinators: `"projection   the domain-free algebra: the generic and higher-order combinators, the compound aggregates, Searching, Copying, Sorting, Filtering, ReaderDefaults"` — consistent with what this survey found in `source/projection/` and `package/ProjecturedProjection/`, and consistent with `architecture.md`'s claim that this code lives in `ProjecturedProjection`. No contradiction here — this part of `architecture.md` is correct.
- `system-anatomy.md` links to this area's files under `../package/kernel/*.md` (e.g. L145-157: cell, macros, document, reference, selection, finding-and-selecting, operation, projection-system, higher-order-projections, generic-projections, devices-and-backends, agent, editor) — all resolve correctly to `documentation/package/kernel/*.md` from `documentation/design/system-anatomy.md`. No broken cross-links found in this direction.
- `system-anatomy.md` L289 independently asserts the same phantom `TableToGraphics` projection found wrong in `projection-system.md` above (`| \`TableToGraphics\` | \`Table\` → \`Graphics\` (direct) |`) — this is not an isolated slip in one file, it's asserted as fact in (at least) two survey files plus `documentation/guide/examples-tour.md`.

---

## Cross-cutting: a systemic stale-path pattern

Every one of the seven files in this area contains at least one instance of prose naming a path of the shape **`package/kernel/main/<layer>/`** or **`main/<file>.jl`**, while the accompanying Markdown link target is (correctly) `source/kernel/<layer>/...`. This is not one typo — it recurs in `architecture.md` (×2), `cell.md` (×1 prose, plus the separate broken `Editor.jl`/`PerformanceCounter.jl` links), `generic-projections.md` (×1), `higher-order-projections.md` (×2), and `projection-system.md` (indirectly, via the `ProjectionApi.jl` naming). The pattern strongly suggests the whole kernel doc set was authored when the layout was `package/kernel/main/<layer>/<File>.jl`, the code later moved to `source/kernel/<layer>/<File>.jl` with `package/ProjecturedKernel/src/` reduced to a thin include-list aggregator, and every Markdown *link* was mechanically repointed at the time — but the surrounding *prose* was not. Confirmed: `package/kernel/` does not exist as a directory anywhere in the repository (`ls package/` lists only `Projectured*` package names, one per package, each holding `Project.toml` + `src/`, never a `main/` subfolder). This is the single highest-value, lowest-risk fix across the whole area — a search-and-replace of the prose phrase, file by file, since the links themselves are already correct.

## Cross-cutting: the new framing — what already explains "on-demand" and what doesn't

The brief asks specifically which parts of these seven guides explain the mechanism that makes on-demand views of arbitrary Julia data possible. Findings:

- **`document.md`** correctly and accurately documents the generic, *policy-bounded* reflection walk (`walk_document`, and the three sync-policy hooks `is_descendable_for_sync`/`sync_element_limit`/`make_unsynced_placeholder`) — this is the actual plumbing a lazy/on-demand walk rides on. But it frames this only as "a full walk per frame... is wasted work" (a performance concern), never as "this is what lets an arbitrary/huge live object be explored lazily."
- **`generic-projections.md`** documents `ObjectToWidget` — "reflection-driven form: emits a labelled control row per editable Cell field of the object" — the *eager*, *editing*-oriented reflection projection. Its own source comment (`source/widget/ObjectToWidget.jl`) already states the framing in almost these words: "Generic, reflection-driven projection from an arbitrary object to a widget form that displays and edits the object's reactive parameters."
- **What is missing everywhere in this area**: none of the seven files mention `source/reflection/` (`BoundedSync.jl`, `DocumentReflection.jl`, `ReflectionToWidget.jl`) — the *lazy*, *on-demand-expansion* successor built specifically for "something meant to be drilled into" (a running engine's internals, per that file's own comment), as opposed to `ObjectToWidget`'s editing form. Its own header comment states the distinction plainly: *"`ObjectToWidget`'s advantage was that it already knew how to reflect an object. `DocumentReflection` now does that ahead of any widget... `ObjectToWidget` also offers editing, which is the wrong affordance for a running engine's internals."* This is exactly the mechanism the new framing needs foregrounded ("any value, document, file or live system gets an editable view when someone asks for it"), and it is currently undocumented in every file a reader would naturally reach for it from (`document.md` for the walk it's built on, `generic-projections.md` for its sibling `ObjectToWidget`).
- `FocusingProjection` ("focus" in the brief's list) is already documented adequately in `generic-projections.md`.
- The lazy `ListNode` behavior of `CopyingProjection` ("lazy lists" in the brief's list) is already documented adequately in `generic-projections.md`.
- **Conclusion for the rewrite**: the one new concept to introduce is the `BoundedSync`/`DocumentReflection`/`ReflectionToWidget` triple, most naturally as a new subsection of `generic-projections.md` (alongside `ObjectToWidget`, its predecessor) with a pointer from `document.md`'s bounded-walk section.

---

## Top findings of this area

1. **`ProjectionApi.jl`/`ProjectionApiModule` do not exist** — referenced as the four-function interface's home in `architecture.md` and `projection-system.md` (3 occurrences). The real file is `source/kernel/projection/ProjectionInterface.jl`, a fragment of `ProjectionModule`, not its own module. (checked)
2. **`@projection_template` is undocumented** despite being, per its own source header, how "every structural projection is written... rather than as a hand-written printer and reader pair" (17 usage sites). `macros.md` documents only `@document`/`@projection`/`@iomap`. This is the single biggest content gap in the area. (checked)
3. **The `@document` macro has grown a configuration DSL** (`[C, M]`/`[DC]`/`[I]` layout lists, `@document_preset`, Rule C) that `macros.md` does not mention at all; its own worked example (`StyleText`) is stale against the real declaration. (checked)
4. **A systemic stale-path pattern**: every one of the 7 files says "`package/kernel/main/...`" in prose while linking to the correct `source/kernel/...` — evidence of an unfinished repo-wide path migration. Cheap, high-value fix. (checked)
5. **`architecture.md`'s fan-in table contradicts its own layer list**, seven lines above, in the same file — the table predates the `clock` layer's insertion at layer 2 and was never renumbered. (checked)
6. **`architecture.md`'s folder-layout table omits `clock/`** entirely (15 rows for 17 layers). (checked)
7. **A phantom `TableToGraphics`/`Table` domain** is asserted as real in `projection-system.md`, `system-anatomy.md`, and `examples-tour.md`, but no such domain, struct, or function exists anywhere in `source/`. (checked)
8. **`print_document_pure`/`print_child_pure`** — a real, shipped second (pure/batch) interpreter path for every projection — is entirely undocumented in `projection-system.md`, which still frames "the four functions" as the complete interface. (checked)
9. **`generic-projections.md`/`higher-order-projections.md` misstate where things live**: `ObjectToWidget` is not in `source/projection/generic/` (it's in `source/widget/`); `WindowManagingProjection`/`TooltipDecoratorProjection`/`DraggingProjection`/`ProjectionConfiguringProjection` are not in `source/projection/higherorder/` (they're each in their own package). Plus 3 wrong filenames in the "Key file" column (`Sequential.jl`, `Alternative.jl`, `WindowManager.jl` — none exist). (checked)
10. **`higher-order-projections.md` contradicts itself**: opens with "they never touch any specific domain" then lists three members that explicitly dispatch on named domain types (`ScreenDocument`, `TooltipSource`, `DraggingState`). (checked)
11. **The on-demand-reflection mechanism the new framing needs is undocumented**: `BoundedSync`/`DocumentReflection`/`ReflectionToWidget` (`source/reflection/`) — the lazy successor to the already-documented `ObjectToWidget` — appears in none of the 7 files, despite `document.md` already correctly documenting the exact policy hooks it's built on. (checked)
12. **Duplicate 17-layer table** in both `architecture.md` and `system-anatomy.md` (they agree with each other, but it's the same content maintained twice — and `architecture.md`'s own fan-in table proves that dual maintenance already drifted once). (checked)

---

# Survey area E-kernel-b: references, selection, operations, editor, finding-and-selecting, devices-and-backends, agent stack

Repository: `/home/projectured/workspace/projectured-julia`. Read-only survey, no Julia run.
Layer numbers verified against `package/ProjecturedKernel/src/ProjecturedKernel.jl` (the single
source of truth: layer 3 event, 4 device, 5 gesture, 6 backend, 7 document, 8 reference,
9 selection, 10 operation, 11 binding, 12 iomap, 13 projection, 14 tool, 15 llm, 16 agent,
17 editor).

---

## documentation/package/kernel/reference.md

**Verdict: UPDATE.** Structure and grammar description are largely sound and layer 8 file
list matches `source/kernel/reference/*.jl` exactly, but the XML domain table is fabricated
(wrong field names) and several code-quality nits exist. **Audience:** Julia developer using
ProjecturEd as a library, and the AI assistant (served as `resource://guide/kernel/reference`).
**Size:** 825 lines — the longest file in this area, plausibly SPLIT (grammar/DSL vs
per-domain path tables) but not required.

| where | category | finding | evidence | fix | confidence |
|---|---|---|---|---|---|
| "XML domain" table | WRONG | Every row names a field `cell` for `XmlElement`, `XmlText`, `XmlAttribute`. None of the three types has a field named `cell`. | `source/xml/XmlDocument.jl:36-40` — `XmlElement` has `tag, attrs, children, collapsed`; `:25` — `XmlText` has `content`; `:15` — `XmlAttribute` has `name, value`. | Rewrite the table: `XmlElement.attrs`→attrs (correct), `XmlElement.children`→`FieldReferenceStep("children")`, `XmlText.content`→`FieldReferenceStep("content")`, `XmlAttribute.value`→`FieldReferenceStep("value")` (no `.cell` step for `XmlAttribute` exists as a navigation target — `name`/`value` are plain `String` fields, not `Document`s). | checked |
| "The reference layer (kernel layer 8)" | CODE-REFERENCE | Prose says the layer "lives in `main/reference/`"; no `main/` directory exists anywhere in the repo — the real path (also the link target) is `source/kernel/reference/`. Same "main/…" mislabeling recurs in every file of this area (and, per a spot check, across the whole kernel doc set: cell.md, projection-system.md, generic-projections.md). | `find . -maxdepth 3 -iname main` → nothing. | Repo-wide: replace `package/kernel/main/…` prose labels with `source/kernel/…` (or drop the bracketed prose entirely and let the link stand). | checked |
| §"Type checkpoints" / whole file | STYLE | "under the hood" (line 300, banned phrase), "first-class" (line 237, banned marketing word), personification: "A step type that **wants** to appear in a rules pattern registers both" (line 643). | lines 237, 300, 643. | Reword: "not an absence of selection" (drop "first-class"); "the document-aware validator" (drop "under the hood"); "A step type that appears in a rules pattern registers both". | checked |
| whole file | FRAMING | The file already treats references as a general path/pointer vocabulary usable from any Julia code (`search_references`, scripting), which supports the new framing without change needed. | — | none needed | checked |
| §"Testing" | STALE (minor) | "`test/reference/` migrates ProjecturedTest's `ReferenceBuilderTest.jl` verbatim" — history phrasing ("migrates … verbatim") describes a one-time porting act, not current state. | test/kernel/reference/ is the real path (not `test/reference/`), consistent with the "main/" vs "source/kernel/" pattern above. | Say what the test folder holds today, not how it came to hold it. | likely |
| domain tables (JSON, Book, FileSystem) | — | Field names checked against source and are accurate: `JsonObject.entries`, `JsonArray.elements`, `JsonObjectEntry.key/value`, `Json{String,Number,Bool}.value`, `Book{Book,Chapter,List}.elements`, `Book{Paragraph,Picture}.content`, `FileSystemDirectory.elements`. | `source/json/JsonDocument.jl`, `source/book/BookDocument.jl`, `source/filesystem/FileSystemDocument.jl` | none | checked |
| Worked examples (5 sampled: whole-element `∅`, `@reference` DSL forms, `@reference_case` arm vocabulary, `search_references`/`search_documents` split, type-checkpoint fold/strip) | — | All five match current code: `EmptyReference`/`ConcreteReference` fields, `@reference`/`@reference_step` macros, `annotate_reference_types`/`strip_reference_types`/`fold_reference_types`, `search_references` vs `search_documents` folding rule, all exist with the described signatures/behaviour. | `source/kernel/reference/*.jl` | none | checked |

---

## documentation/package/kernel/selection.md

**Verdict: REWRITE.** The document/selection storage model changed substantially since this
was last updated (canonicalization + validation with `SelectionMismatchException`, dormant
selections via `SelectionDocument`, `map_selection_forward`, in-place `_sync_selection!`) and
the guide describes an older, simpler model throughout its core sections. **Audience:**
Julia developer / contributor; also served to the assistant. **Size:** 382 lines.

| where | category | finding | evidence | fix | confidence |
|---|---|---|---|---|---|
| §"Setting a new selection" | MISSING | `set_selection!` is described as a plain recursive walk with no validation. In current code it canonicalizes the path (`annotate_reference_types` after `strip_reference_types`) and **throws `SelectionMismatchException`** if the canonical path does not structurally match the document, atomically (no cell written on failure). None of this — the exception, the atomicity guarantee, or canonicalization — is mentioned. | `source/kernel/selection/SelectionDefaults.jl:148-184` (`_matched_selection`, `set_selection!`); docstring `source/kernel/selection/SelectionInterface.jl:26-45`. | Rewrite the section to describe canonicalization + `SelectionMismatchException`, with an example of a stale path throwing. | checked |
| §"Replacing selection" | WRONG | States `replace_selection!` is "`clear_selection!` followed by `set_selection!`" — a full rebuild. Actual implementation is `_sync_selection!`, an in-place synchronizer: it **mutates the shared start/stop `Cell`s of the terminal cursor step** for a same-leaf caret move (touching no `selection` cell on the path at all), and only clears/marks-dormant the genuinely divergent branch, precisely so unrelated ancestor cells are not invalidated (partial repaint). This is the opposite of "clear everything then rebuild". | `source/kernel/selection/SelectionDefaults.jl:239-308` (`_sync_selection!`, extensive comment block explaining exactly why naive clear+set was replaced). | Rewrite to describe the in-place sync algorithm (same-child fast path / terminal-cursor mutation / divergence handling) — this is exactly the kind of "naive vs. correct" comparison the doc already does elsewhere (reference.md's `sel = ComputedCell(() -> input.selection[].tail[])` section), so the pattern to follow is nearby. | checked |
| whole file | MISSING | **Dormant selections are entirely undocumented.** `has_dormant_selection`, `get_stored_selection`, `is_live_selection`, `map_selection_forward`, and the `SelectionDocument` wrapper type (in `document/`, layer 7) implement a real, tested concept — a tab group or split pane keeps the selection of a branch it stops showing, rendered pale, so focus returning restores it — with no mention anywhere in this guide. | `source/kernel/selection/SelectionInterface.jl:82-140`; `source/kernel/document/SelectionDocument.jl`; used by `source/syntax/SyntaxToText.jl:108-116` and `source/pane/PaneToWidget.jl:83`. | Add a section: what "dormant" means, `SelectionDocument`, and why a printer must forward-project through `map_selection_forward` and not read `.selection[]` directly. | checked |
| §"Forward-projecting selection" code sample | WRONG | The `SyntaxLeafToText` printer sample reads `leaf.selection[]` directly and builds `Text(Cell(...), sel)`. The real `SyntaxLeafToText.print_document` (a) uses `map_selection_forward(leaf, path -> …)` — not a bare property read, precisely because a bare read silently drops dormant state — and (b) constructs a `TextBlock`, not `Text` (no type named bare `Text` exists in the codebase). | `source/syntax/SyntaxToText.jl:106-116` (`print_document(p::SyntaxLeafToText, …)`). | Replace the sample with the real one, and add a note that `map_selection_forward` (not a raw `.selection[]` read) is required in every printer that forwards selection, once dormant state is explained. | checked |
| §"Selection stored in each domain type" | STYLE (minor) | Table names the domain type `Text` (bare) — should be `TextBlock`, matching the rest of the codebase. | `source/text/TextDocument.jl:215` — `@document struct TextBlock <: TextDocument`; no bare `Text` document type exists. | Rename `Text` → `TextBlock` throughout the table and prose. | checked |
| §"Setting selection" preamble | WRONG | "`SyntaxNode` provides a specialised override that additionally clears the `selection` on every *other* child before setting the selected one" — no such override exists anywhere in the codebase. | `grep -rn "set_selection!" source/syntax` and a repo-wide grep for a `SyntaxNode`-specific `set_selection!`/`SelectionModule.set_selection!` method: no hits. | Delete the sentence; the divergence-clearing behaviour it describes is now handled generically by `_sync_selection!`'s divergence branch (see the `replace_selection!` finding above). | checked |
| §"Replacing selection" | STYLE | "**Under the hood** this calls…" — banned phrase, and (per the WRONG finding above) also factually incorrect. | line 118. | Remove with the rewrite. | checked |
| whole file | CODE-REFERENCE | `get_selection` (the read accessor) is a real, exported function (`SelectionModule.jl:35-38` exports it) and is never mentioned in the guide at all, despite the guide being the "single home" for how selection is read/stored. | `source/kernel/selection/SelectionInterface.jl:6-14`. | Document `get_selection` alongside the writers. | checked |
| whole file | MISSING | No "The selection layer" structure section (file list, downward edges, layer number) exists, unlike the sibling docs (reference.md has one for layer 8, operation.md for layer 10). A reader cannot tell from this file that selection is layer 9 or what `SelectionModule`'s two fragments (`SelectionInterface.jl`/`SelectionDefaults.jl`) are. | `source/kernel/selection/SelectionLayer.jl`, `SelectionModule.jl`. | Add a structure section matching the sibling docs' format. | checked |

---

## documentation/package/kernel/operation.md

**Verdict: UPDATE.** The operation catalogue and consolidation story (`ReplaceReferencedValueOperation`
+ builders replacing single-purpose operations) is accurate and well evidenced in code. Two broken
links and one stale example. **Audience:** Julia developer / contributor, and the assistant.
**Size:** 411 lines.

| where | category | finding | evidence | fix | confidence |
|---|---|---|---|---|---|
| §"Two invariants…" | LINK | `[projection/Projection.jl](../../../source/kernel/projection/Projection.jl)` — file does not exist. The default `read_intent` this sentence refers to is in `ProjectionDefaults.jl`. | `ls source/kernel/projection/*.jl` → `ProjectionDefaults.jl, ProjectionInterface.jl, ProjectionLayer.jl, ProjectionMacro.jl, ProjectionModule.jl, ProjectionReferenceStep.jl, ProjectionTemplate.jl` (no `Projection.jl`); `grep -n "function read_intent" source/kernel/projection/*.jl` shows the default at `ProjectionDefaults.jl:117,203`. | Fix link to `ProjectionDefaults.jl`. | checked |
| Catalogue table, "Driving operations…", generic-write section | — | Spot-checked types/functions all exist as described: `ReplaceReferencedValueOperation`, `CompoundOperation`, `CollectedIntentsOperation`, `replace_document`, `insert_elements`, `delete_elements`, `QuitEditorException`, `QuitEditorOperation`, `child_reference_steps`, `reroot_operation`. | `source/kernel/operation/Operations.jl:94,105,123,220,260-311`; `source/kernel/operation/Rerooting.jl`. | none | checked |
| §"The operation layer" file list | — | `Interface.jl`/`Operations.jl`/`Rerooting.jl` under `OperationModule` matches `source/kernel/operation/*.jl` exactly (unlike the agent/editor layers below, this one was **not** renamed to add a `Module` suffix). | `source/kernel/operation/OperationModule.jl`. | none | checked |
| whole file | STYLE | No banned words/personification found in this file. | — | none | checked |

---

## documentation/package/kernel/editor.md

**Verdict: REWRITE.** The central "Read-Eval-Print loop" pseudocode and the `Editor` struct —
the two things a reader comes to this file for — are both stale relative to
`source/kernel/editor/EditorModule.jl`. Two broken links, one fabricated operation type in a
worked example, and several real, current features (`run_frame!`, `mcp_instructions`,
`on_start`, the readability-zoom operations, `Editor.clock`/`.tools`/`.recognizer`) are entirely
unmentioned. **Audience:** Julia developer / contributor, and (MCP section) anyone integrating
an external agent. **Size:** 330 lines.

| where | category | finding | evidence | fix | confidence |
|---|---|---|---|---|---|
| §"The Editor struct" | WRONG | Documented struct has 7 fields (`backend, document, projection, devices, inbox, iomap, operation`). The real `Editor` has **10**: it additionally carries `clock::Clock` (a per-editor animation clock), `tools::ToolSet` (the agent tool surface every editor owns — itself documented in agent.md as `[PAR-PER-EDITOR-STATE]`, but absent from the struct listing here), and `recognizer::GestureRecognizer` (the click/chord recognizer — the doc's own "Read" section describes what the recognizer does but the struct that owns it is undocumented). | `source/kernel/editor/EditorModule.jl:54-65`. | Rewrite the struct listing to the 10 real fields, each with the one-line description already present in the module docstring (`EditorModule.jl:29-53`). | checked |
| §"The Read-Eval-Print loop" | WRONG | The five-step pseudocode (`drain_operations!; read!; evaluate!; print!; perf!`) does not match the real loop body, which is `drain_operations!; run_frame!; perf!` plus a `set_clock_time!` tick — `run_frame!` is a **new, exported, documented function** (batches up to `MAX_OPERATIONS_PER_FRAME = 32` `read!`/`evaluate!` pairs before one repaint, specifically so a burst of fast input — e.g. mouse-move hover — doesn't fall a frame behind) that this guide never mentions at all. | `source/kernel/editor/EditorModule.jl:318-384` (`run_frame!`, `run_editor!`). | Rewrite the loop description around `run_frame!`, explain the 32-op batching bound, and add the clock tick. | checked |
| §"The inbox" | WRONG (CODE-REFERENCE) | Example `post_operation!(editor, RefreshOperation(subject))` — no type named `RefreshOperation` exists anywhere in the repository. | `grep -rn "RefreshOperation" .` → only this one doc line. | Replace with a real operation, e.g. `ReplaceSelectionOperation` or a domain-specific example. | checked |
| top of file | LINK | `[package/kernel/main/editor/Editor.jl](../../../source/kernel/editor/Editor.jl)` — file does not exist; the module file is `EditorModule.jl`. | `source/kernel/editor/` contains `EditorLayer.jl, EditorModule.jl, PlaybackModule.jl` — no `Editor.jl`. | Fix link and prose to `EditorModule.jl`. | checked |
| §"MCP server" | LINK | `[package/kernel/main/agent/AgentServer.jl](../../../source/kernel/agent/AgentServer.jl)` — file does not exist; the real file is `AgentServerModule.jl`. | `source/kernel/agent/` contains `Agent.jl, AgentLayer.jl, AgentLoop.jl, AgentModule.jl, AgentServerModule.jl`. | Fix link. | checked |
| §"The editor layer" file list | WRONG | Lists `Editor.jl (EditorModule)` and `Playback.jl (PlaybackModule)`. Real filenames are `EditorModule.jl` and `PlaybackModule.jl` (confirmed by `EditorLayer.jl`'s own include list). | `source/kernel/editor/EditorLayer.jl:1-4`. | Fix the two filenames. | checked |
| §"Running an editor" | MISSING | `mcp_instructions` (custom MCP system prompt) and `on_start` (callback handed the freshly built `Editor`, "how something that will post operations gets hold of the editor") keyword arguments of `run_editor!` are both undocumented, despite being the two hooks a caller needs to (a) customize what an MCP client is told and (b) wire a driver/watcher into a running editor — both directly relevant to "how do I use the assistant/MCP" per the brief. | `source/kernel/editor/EditorModule.jl:346-434` (docstrings of both `run_editor!` overloads). | Add both to the "Running an editor" section. | checked |
| Read §/whole file | MISSING | The "readability zoom" (`Ctrl+=`/`Ctrl+-`/`Ctrl+0`, `+Alt` for font-only) is a real, global, always-available editor feature (`_zoom_operation`, `AdjustZoomOperation`/`AdjustFontZoomOperation`) recognized directly in `read!`. It is mentioned only once, in passing, in devices-and-backends.md's Escape discussion ("in the same place it recognises the readability zoom") — nowhere is it actually explained, and no document anywhere names `AdjustZoomOperation`. | `source/kernel/editor/EditorModule.jl:208-229`; `grep -rn AdjustZoomOperation documentation/` → nothing. | Document the zoom keys and the two operations, here or in devices-and-backends.md. | checked |
| §"Testing" | LINK label (minor) | Link text says `test/editor/` while the href (which resolves) points to `test/kernel/editor/` — same "old path label, current href" pattern seen throughout this area. | `test/kernel/editor/` is the real directory. | Fix the visible label. | checked |
| whole file | FRAMING | The guide frames the editor purely as an interactive GUI loop; the MCP section is the last major section, phrased as an optional add-on ("Pass `mcp=true` to start an MCP server alongside the loop") rather than as a first-class way to drive the same loop with no human present. Under the new framing (AI integration from the ground up, one tool set for in-editor assistant and external MCP clients) this ordering/emphasis should change. | — | Consider moving/integrating the MCP section earlier, or at least cross-referencing agent.md's framing up front. | likely |

---

## documentation/package/kernel/finding-and-selecting.md

**Verdict: KEEP.** This file is accurate and well-aligned with current code — no wrong facts
found. **Audience:** Julia developer / contributor, and the assistant (this guide's workflow —
"find → build operation → evaluate" — is exactly the pattern the assistant's own system prompt
in `source/assistant/AssistantDocument.jl` tells the model to use, see agent.md section below).
**Size:** 262 lines.

| where | category | finding | evidence | fix | confidence |
|---|---|---|---|---|---|
| §"One walk, two searches" | — | `DocumentWalk`, `walk_document`, and the `:once_per_object`/`:once_per_path` policy split are accurate. | `source/kernel/document/DocumentWalk.jl:29-54,102-120`. | none | checked |
| §"Searching for references"/"documents" | — | Signatures (`include_selection`, `maxdepth=64`, `raw`) match `ReferenceSearch.jl:11-18` and the document-layer `search_documents` default. | `source/kernel/reference/ReferenceSearch.jl`. | none | checked |
| whole file | DUPLICATE (minor, by design) | The "round trip" and "worked example: select Alice" sections restate material also given (with different code) in reference.md and selection.md and operation.md's "Driving operations" section — the four files cross-link each other for exactly this reason. Not a defect, but a rewrite of the area should decide once where the canonical worked example lives. | reference.md §"Finding references"; operation.md §"Driving operations programmatically". | Note for the rewrite plan only. | likely |
| whole file | STYLE | No banned words found. | — | none | checked |

---

## documentation/package/kernel/devices-and-backends.md

**Verdict: UPDATE.** The device/event/gesture/backend layer internals and the SDL/Console/Web
backend descriptions check out in detail (including the web backend's port, wire protocol, and
dirty-patch mechanism). Two broken links, and the guide covers three of the real backend/output
packages while omitting two adjacent ones (`ProjecturedVideo`, and the user-facing gesture-help
system). **Audience:** Julia developer adding a device/backend, and a new user picking a
frontend. **Size:** 565 lines.

| where | category | finding | evidence | fix | confidence |
|---|---|---|---|---|---|
| §Devices table / Escape discussion | LINK | `[editor/Editor.jl](../../../source/kernel/editor/Editor.jl)` — file does not exist (see editor.md finding above; real file is `EditorModule.jl`). | `source/kernel/editor/` listing. | Fix link. | checked |
| §"EventPatternModule" | LINK | `[EventPattern.jl](../../../source/kernel/event/EventPattern.jl)` — file does not exist; the real file is `EventPatternModule.jl`. | `source/kernel/event/` contains `EventDefaults.jl, EventInterface.jl, EventLayer.jl, EventModule.jl, EventPatternModule.jl, KeyboardEvent.jl, ModifierKeys.jl, MouseEvent.jl, WindowEvent.jl, WindowInput.jl` — no bare `EventPattern.jl`. | Fix link. | checked |
| Backend generics list, `BackendDefaults.jl` fallbacks, MCP-adjacent SdlBackend/ConsoleBackend/WebBackend sections | — | All checked in detail: `get_pointer_position → (-1,-1)`, `get_display_size → (1280,800)`, `configure_devices!`/`open_native_windows!` no-ops, the full generic list (`write_image, record_video, render_canvas, decode_image, …`), `run_console_example`, WebBackend port defaults (8080), wire-protocol message shapes. | `source/kernel/backend/BackendInterface.jl`, `BackendDefaults.jl`; `source/web/Web.jl` (spot-checked default port/messages). | none | checked |
| §"File-export backends" | MISSING | `record_video` (`ProjecturedVideo`/`source/video/Video.jl`) is a batch generic declared right alongside `write_image`/`write_pdf` in `BackendInterface.jl` (the doc's own quoted generics list even names it: "…`write_image`, `record_video`, `render_canvas`…") but this section only documents `write_image` and `write_pdf`; `record_video` (headless MP4 recording via ffmpeg, same offscreen-SDL-renderer machinery as `write_image`) is never explained anywhere in `documentation/`. | `source/video/Video.jl:12-53` (full docstring/API); `find documentation -iname "*video*"` → nothing. | Add a third bullet under "File-export backends" for `record_video`. | checked |
| §"Gesture bindings: a separate, higher layer" | MISSING | Answers the brief's question directly: **the gesture/key-binding system is documented here** (`GestureBinding`, `@gestures`, `fire_gesture_bindings`, `CollectIntents`), and it does name a **user-facing list of key bindings** — one throwaway link: "The command palette in the domain package lists these by name; see the gesturemap slice (`source/gesturehelp/CommandPalette.jl`)." But the actual feature is a whole 7-file slice, `source/gesturehelp/` (`GestureHelpModule.jl`, `GestureMap.jl`, `CommandPalette.jl`, `CommandPaletteDecorator.jl`, `CommandPaletteToSyntax.jl`, `GestureHelpDecorator.jl`, `GestureMapToSyntax.jl`) implementing **two** user-facing features — a gesture-help overlay (a `GestureMap` document listing every binding + description + live applicability, rendered through the normal Syntax→Text→Graphics pipeline) and a VS-Code-style command palette (type-to-filter, Enter to run) — and neither is explained, named, or linked from any guide in the repository. | `source/gesturehelp/GestureHelpModule.jl:1-19`, `GestureMap.jl:1-20`, `CommandPalette.jl:1-24`; `find documentation -iname "*gesture*" -o -iname "*keybind*"` → nothing. | Add a short section (here, or a dedicated `gesturehelp.md`) naming `GestureMap`/`CommandPalette` as the user-facing key-binding list and how a user opens it. | checked |
| §"Backends" intro | FRAMING | Frames every backend as something a **display/input platform** provides; there is no mention that the same editor loop can be driven with **no display backend at all** — by an MCP client alone. In production there is in fact no such "headless" `Backend`: `run_editor!` always requires a concrete `Backend` and opens native windows/initializes a real backend (SDL/Console/Web) even when the caller only wants `mcp=true`; the only dependency-free `HeadlessBackend` is a **test double**, deliberately excluded from `main` (`PAR-NO-TEST-DOUBLES-IN-MAIN`). Under the new framing ("any value gets an editable view… by the AI assistant") this is a real gap worth surfacing, not just a doc omission. | `source/kernel/editor/EditorModule.jl:416-433` (`run_editor!` bootstrap requires `backend::Backend`); `documentation/package/kernel/editor.md:325-330` (`HeadlessBackend` described as living in `ProjecturedKernelExample`, not `main`). | Note in the rewrite plan: either document this constraint explicitly, or treat "an MCP-only production backend" as a product gap. | checked |
| whole file | STYLE | No banned words found. | — | none | checked |

---

## documentation/package/kernel/agent.md

**Verdict: UPDATE**, but with the most consequential findings in this whole area: the guide's
own facts (layer numbers, file lists, function names) are accurate, but the actual
system-prompt strings shipped in the code (which this guide should be the source of truth for)
contain **broken `resource://guide/...` URIs that the tool layer this guide documents cannot
resolve** — a live bug, not just a documentation gap, and squarely on-topic for "what a user
needs to know to use the assistant." **Audience:** Julia developer extending the tool/llm/agent
layers, and indirectly every user of the assistant (whose behavior this bug affects).
**Size:** 404 lines.

| where | category | finding | evidence | fix | confidence |
|---|---|---|---|---|---|
| §"Layer 14 — tool/", "Layer 15 — llm/" file lists | — | `Tool.jl, ToolSet.jl, CodeExecution.jl, SearchQuery.jl, Documentation.jl, MeaningSearch.jl, DefaultTools.jl` and `Llm.jl, LlmMessage.jl, LlmEvent.jl` match `source/kernel/tool/*.jl` and `source/kernel/llm/*.jl` exactly, as do the exported function names quoted throughout (`make_llm`, `default_llm_model`, `get_llm_backend_names`, `has_meaning_model`, `bind_meaning_model!`, `render_tool_schema`, `stream_turn`, …). | `source/kernel/tool/ToolModule.jl`, `source/kernel/llm/LlmModule.jl`. | none | checked |
| Layer numbers 14/15/16 | — | Correct, verified against the authoritative include order. | `package/ProjecturedKernel/src/ProjecturedKernel.jl:45-47`. | none | checked |
| §"Layer 16 — agent/" file list | WRONG | `AgentServer.jl (AgentServerModule) inbound — make/start/stop_agent_server!` — the real file is `AgentServerModule.jl`, not `AgentServer.jl` (`Agent.jl`/`AgentLoop.jl` are correctly named). Same error is repeated in the "Who implements what" table (`agent/AgentServer.jl`). | `source/kernel/agent/AgentServerModule.jl` (the only file implementing `make_agent_server`/`start_agent_server!`/`stop_agent_server!`); `source/kernel/agent/` listing has no `AgentServer.jl`. | Fix both occurrences (lines 365 and 402). | checked |
| §"What a user needs to know" (MCP connection) | MISSING | Nowhere in the whole repository is it explained **how an external client (Claude Code, Claude Desktop, any MCP client) actually connects** to this server — no example `mcp.json`/config snippet, no mention that the transport is streamable-HTTP+SSE at a fixed local URL. The editor.md guide gives the URL (`http://127.0.0.1:9876/mcp`, verified correct — see `source/mcp/Mcp.jl:60-70`) but never says what to put in a client's config, and agent.md doesn't mention the URL at all. | `grep -rln "mcp.json\|mcpServers\|Claude Desktop\|Claude Code" documentation/ source/ test/` → **zero hits** anywhere in the repo. | Add a short "connecting an external client" section with a concrete config snippet (`{"type":"http","url":"http://127.0.0.1:9876/mcp"}` or equivalent), and note the "one client per editor" constraint (see below). | checked |
| whole file | MISSING | `ANTHROPIC_API_KEY` (read once, at `AnthropicLlm` construction, from `ENV`) and the fact Ollama needs **no key** and defaults to `http://localhost:11434` are never stated. Default models are never stated: Anthropic defaults to `claude-opus-4-5-20251101`, Ollama to `qwen3.8:27b` (an unusual/possibly-typo'd model tag worth a second look by whoever owns it, but that's a code question, not a doc one) — a user picking `assistant.backend = :ollama; assistant.model = ""` has no document telling them which model that empty string resolves to. | `source/anthropic/Anthropic.jl:1-30`; `source/ollama/Ollama.jl:1-84`. | Add a short table: backend, env var / config, default model, default endpoint. | checked |
| whole file | MISSING | The **in-editor Assistant** — the actual chat panel a user interacts with (`source/assistant/`: `Assistant` struct with `conversation, input, backend, model, system, api_key, context, status, llm` fields, `DEFAULT_ASSISTANT_SYSTEM`, `SubmitJuliaOperation`/`SubmitProseOperation`) — is not mentioned anywhere in `documentation/`, including here. agent.md documents only the kernel-level tool/llm/agent seams; nothing tells a reader that a concrete assistant UI exists, what package it's in, or how a user opens/configures it in the workbench. | `grep -rln "AssistantModule\|ProjecturedAssistant" documentation/` → **zero hits**; `source/assistant/AssistantDocument.jl:53-70` (the `Assistant` struct). | Add a section (or a pointer to a new `assistant.md`) describing the in-editor panel, its backend/model/api_key fields, and how it differs from/relates to the MCP path. | checked |
| §"How the documentation is served" (from `source/kernel/tool/Documentation.jl`) | WRONG (code, high-impact) | **The assistant's own mandatory-first-read system prompt cites guide URIs that do not exist.** `DEFAULT_ASSISTANT_SYSTEM` (the default `system` prompt of the in-editor `Assistant`) instructs the model: `resource://guide/orientation` (mandatory first read) and later `resource://guide/editor/finding-and-selecting`, `resource://guide/operations`. The tool-layer `execute_julia_code` description (`_WHOLE_SURFACE_DESCRIPTION`, served whenever no API is declared — the MCP/workbench default) instructs: `resource://guide/getting-started`, `resource://guide/editor/reference`, `resource://guide/editor/selection`. **None of these five URIs resolve.** Guide names are computed purely from file path (`_all_guides()`: the top-level `documentation/` tree keeps its path minus `.md`, e.g. `documentation/guide/orientation.md` → name `guide/orientation`; each `documentation/package/<slice>/` folder is prefixed by slice, e.g. `documentation/package/kernel/reference.md` → name `kernel/reference`). There is **no `documentation/package/editor/` folder** (the slice is `kernel/`) and **no `documentation/getting-started.md`** anywhere. `read_resource`/`find_resource` do an exact `==` match (`ToolSet.jl:155-158`), so each of these five URIs answers `"Resource '...' not found."` — the model's very first mandated action fails. | `source/assistant/AssistantDocument.jl:14-51` (full prompt text, lines 18 and 32); `source/kernel/tool/DefaultTools.jl:16-21`; `source/kernel/tool/Documentation.jl:44-90` (`_guide_roots`/`_all_guides`, the derivation rule) and `:236-248` (registration loop using the same computed name); `source/kernel/tool/ToolSet.jl:155-172` (exact-match lookup); confirmed no `documentation/package/editor/`, no `documentation/getting-started.md`, `documentation/orientation.md` exist (`find documentation -iname "orientation*"` → only `documentation/guide/orientation.md`). | Fix the five hardcoded strings in `AssistantDocument.jl` and `DefaultTools.jl` to `resource://guide/guide/orientation`, `resource://guide/kernel/finding-and-selecting`, `resource://guide/kernel/operation`, `resource://guide/guide/setup-guide` (closest existing analogue to "getting started"), `resource://guide/kernel/reference`, `resource://guide/kernel/selection` — or, better, stop hand-writing guide names in prompts and generate the "MANDATORY" list programmatically from `_all_guides()`/`register_guide_root!` so a rewrite that moves/renames a guide cannot silently break the prompt again. **This is exactly the risk the brief calls out** ("the rewrite moves and renames documents, and the assistant must still find them") — it has already happened once. | checked |
| Answers to the brief's specific sub-questions on `Documentation.jl` | — | (1) Guides are found by a **folder walk** (`walkdir`), not hardcoded paths — one root is `documentation/` itself (bare names, skipping `documentation/package/`), one root per subfolder of `documentation/package/` (slice-prefixed names), plus any roots an embedding application adds via `register_guide_root!`. (2) URI scheme is `resource://guide/<name>#<heading>`, confirmed live in code, matching agent.md's own description. (3) **`plan/` is not indexed** — `_guide_roots()` only ever adds `documentation/` and `documentation/package/<slice>/`; nothing walks `plan/pending/` or `plan/done/`, so the assistant/MCP client cannot read plans through `search_guides`/`read_guide`/`resource://guide/...` at all. (4) Meaning vectors are stored under `build/meaning/<model>.bin` (confirmed) but **keyed by the text content itself** (`Dict{String,Vector{Float32}}`), not by file path — a guide's *identity* for lookup (its resource URI) is path-derived, but its *cached vector* is content-addressed, so moving a file without changing its text costs nothing to re-embed, while renaming it (even with identical content) changes every citation of its old `resource://guide/...` URI (as just demonstrated above) without invalidating any cache — the two problems (stale citations vs. stale vectors) are independent and only one of them (citations) is what actually broke. | `source/kernel/tool/Documentation.jl:44-90`; `source/kernel/tool/MeaningSearch.jl:33-75` (`_MeaningStore.vectors::Dict{String,Vector{Float32}}`, `_get_meaning_file` names the file after the *model*, not any document). | Report only (no doc currently claims otherwise, since agent.md doesn't discuss `plan/` at all) — but essential input for the rewrite plan: whatever new folder layout is chosen, either register every guide root that should be assistant-visible via `register_guide_root!`/the walk, or explicitly decide `plan/` stays assistant-invisible. | checked |
| §"Documentation" docstring inconsistency (adjacent code, not this doc) | CONTRADICTION | `AssistantDocument.jl`'s own docstring for `DEFAULT_ASSISTANT_SYSTEM` claims it is "the `system` field of an in-editor `Assistant`, and the `instructions` field of the MCP server's `initialize` response… Keep the two sites in sync by sourcing both from this constant." In fact `Mcp.jl` defines and uses a separate, shorter, generic constant `DEFAULT_MCP_INSTRUCTIONS` — `DEFAULT_ASSISTANT_SYSTEM` is never referenced from `source/mcp/`. The two prompts have already drifted (the MCP one has none of the "MANDATORY read this" guide-URI list at all). | `source/assistant/AssistantDocument.jl:7-14`; `source/mcp/Mcp.jl:6-9,27-49`; `grep -rn DEFAULT_ASSISTANT_SYSTEM source/` shows no use outside `source/assistant/` and `source/workbench/`. | Not a finding *in* agent.md (agent.md doesn't discuss this at all), but directly relevant to "what a user needs to know": an MCP client and the in-editor assistant currently get **different** system prompts, contrary to what the code's own docstring claims. Worth a line in the rewrite. | checked |
| whole file | STYLE / FRAMING | Already written from the new framing's point of view — explicitly states MCP is "useful with no LLM in the process at all" and that the in-editor assistant and MCP "use one tool set" (both true and load-bearing for the new framing). No banned words found; this is the best-framed file in the area. | lines 8-15. | none | checked |

---

## Top findings of this area

1. **The assistant's own mandatory system prompt cites five `resource://guide/...` URIs that
   do not resolve** — the model's very first instructed action ("read `resource://guide/orientation`
   before writing any code") fails today. Root cause: guide names are derived from file path by
   `_all_guides()` in `Documentation.jl`, and the hand-written prompt strings in
   `AssistantDocument.jl`/`DefaultTools.jl` don't match that derivation (missing `kernel/`/`guide/`
   prefixes, one guessed name — `getting-started` — that never existed). This is a live
   production bug, checked end-to-end through the resolver code, and it is exactly the failure
   mode the brief warns a document rewrite could cause — it has already happened once, silently.
2. **`selection.md`'s two core write operations, `set_selection!` and `replace_selection!`, both
   describe stale semantics.** The real code added path canonicalization with an atomic
   `SelectionMismatchException` guard, and replaced "clear then rebuild" with an in-place,
   partial-repaint-preserving sync (`_sync_selection!`). A whole concept — dormant selections
   (`SelectionDocument`, `has_dormant_selection`, `map_selection_forward`) — is undocumented.
3. **`editor.md`'s `Editor` struct and Read-Eval-Print loop pseudocode are both stale.** Three
   struct fields (`clock`, `tools`, `recognizer`) and the `run_frame!` batching function (with
   its 32-operations-per-frame bound) are missing; the loop as printed no longer matches
   `EditorModule.jl`.
4. **`reference.md`'s entire XML domain table is wrong** — it gives every XML type a field
   `cell` that none of them has (`XmlElement.children`, `XmlText.content`, `XmlAttribute.value`
   are the real names).
5. **A repo-wide broken-link pattern**: filenames renamed to add a `Module` suffix
   (`Editor.jl`→`EditorModule.jl`, `AgentServer.jl`→`AgentServerModule.jl`,
   `EventPattern.jl`→`EventPatternModule.jl`, `Playback.jl`→`PlaybackModule.jl`) left five dead
   markdown links across editor.md, devices-and-backends.md, and operation.md, plus one more
   (`Projection.jl`, now `ProjectionDefaults.jl`).
6. **No document anywhere explains how to connect an external MCP client** (Claude Code, Claude
   Desktop, or any other) to the running server — not the config shape, not that it's
   streamable-HTTP, not the one-client-per-editor limit. The port/path (`127.0.0.1:9876/mcp`) is
   correct where stated but appears in only one file.
7. **No document anywhere mentions `ANTHROPIC_API_KEY`, the Ollama default host
   (`localhost:11434`, no key needed), or either backend's default model**
   (`claude-opus-4-5-20251101` / `qwen3.8:27b`) — a user following agent.md's own
   `assistant.backend = :ollama; assistant.model = ""` example has no way to know what model
   that resolves to.
8. **The in-editor Assistant panel (`source/assistant/`) is undocumented anywhere in
   `documentation/`** — zero hits for `AssistantModule`/`ProjecturedAssistant`. agent.md covers
   only the kernel tool/llm/agent seams, never the concrete UI a user actually opens.
9. **A real, working "list every key binding" user feature (`source/gesturehelp/`: a gesture-help
   overlay and a VS-Code-style command palette, both driven by `GestureMap`/`CommandPalette`)
   exists and is functional, but is named in exactly one sentence, one link, buried in
   devices-and-backends.md's binding-layer internals** — answering the brief's question "is
   there a user-facing list of key bindings" with "yes, but it's undocumented as a feature."
10. **`plan/` is not indexed by the guide-search machinery at all** (`_guide_roots()` only ever
    walks `documentation/` and `documentation/package/<slice>/`) — worth an explicit decision in
    the rewrite, since the new documentation layout's discoverability by the assistant depends on
    this mechanism.
11. **Meaning vectors are keyed by text content, not file path** (contrary to the brief's
    working assumption) — a file move/rename that preserves section text costs nothing to
    re-embed; what actually breaks on rename is the *guide name* (hence finding 1), which is a
    fully separate mechanism from the vector cache.
12. **`RefreshOperation` (editor.md's inbox example) and the `Text(...)` constructor
    (selection.md's printer example) are both fabricated/removed names** — neither exists in the
    codebase (the latter is `TextBlock`), so both worked examples would fail if run.

---

# Survey area: procedure guides

Files: `documentation/guide/debugging-guide.md`, `documentation/guide/testing-guide.md`,
`documentation/guide/new-domain-guide.md`, `documentation/guide/static-compilation-guide.md`.

All four checks were done statically (grep/find/Read against the working tree at commit
`c28e6e30`, main branch, clean). No Julia was run.

All four files begin with the same front-matter line immediately after the `#` title:
`> **Kind:** procedure · **Status:** current · **Stands on:** [...]`. This matters for all
four (see finding 10 in "Top findings" below), so it is recorded once here rather than once
per file.

---

## documentation/guide/debugging-guide.md

**Verdict:** UPDATE (three broken links to renamed files, one undocumented helper; the
runnable content itself is accurate). **Audience:** contributor to this repository (REPL
debugging); also served to the AI assistant/MCP clients via `read_guide("debugging-guide")`.
**Size:** 483 lines.

| where | category | finding | evidence | fix | confidence |
|---|---|---|---|---|---|
| line 156, "Driving the printer/reader manually" | LINK | `[package/kernel/main/editor/Editor.jl](../../source/kernel/editor/Editor.jl)` — target does not exist | `find . -name Editor.jl` returns nothing; `source/kernel/editor/` now holds `EditorLayer.jl`, `EditorModule.jl`, `PlaybackModule.jl`; `run_editor!` is defined in `source/kernel/editor/EditorModule.jl:346,416` | point the link at `source/kernel/editor/EditorModule.jl` | checked |
| line 295, "Tracing projection calls" | LINK | `[package/kernel/main/projection/ProjectionApi.jl](../../source/kernel/projection/ProjectionApi.jl)` — target does not exist | `find . -name ProjectionApi.jl` returns nothing; `source/kernel/projection/` now holds `ProjectionInterface.jl` (declares `read_intent`, `print_document`, etc.), `ProjectionTemplate.jl`, `ProjectionMacro.jl`, … | point the link at `source/kernel/projection/ProjectionInterface.jl` | checked |
| line 35, "Running an example interactively" | LINK | `[projectured/example/Examples.jl](../../example/projectured/Examples.jl)` — target does not exist | `example/projectured/` has no `Examples.jl`; the name-lookup registry (`examples`, `print_example(name="json")`) actually lives in `example/projectured/ProjecturedExamples.jl:74` | fix the filename in the link | checked |
| whole file | MISSING | `write_example_image` (a REPL helper explicitly named in this survey's special checks) is never mentioned, though it exists and is analogous to `print_example`/`generate_example_screenshots` | `example/kernel/Harness.jl:91` and `example/projectured/ProjecturedExamples.jl:83` both define `write_example_image(name, filename; kwargs...)` | add a short entry alongside `print_example` / "Generating all screenshots" | checked |
| front-matter line (all four files) | CODE-REFERENCE | `list_guides()` — the function that lists guides to the AI assistant/MCP client — takes "the first non-heading, non-blank line after the title" as a guide's description; for this file that line is the `> **Kind:** procedure · **Status:** current · **Stands on:** [setup-guide.md](setup-guide.md)` blockquote, not a real summary | `source/kernel/tool/Documentation.jl:98-124` (`list_guides`); traced its paragraph-extraction loop by hand against this file's structure; `test/projectured/editor/McpTest.jl:5-13` (`test_list_guides`) only asserts the result is non-empty and contains `**`, so this is untested | either move the Kind/Status/Stands-on line so it is not the first line after the title, or change `list_guides()` to skip a leading blockquote | checked |
| "Running an example interactively" / helper table, "Recording a video", "Live examples" sections | (none — verification) | `run_example`, `print_example`, `record_video`, `record_example_video`, `record_live_example`, `play_live_example`, `search_references`, `search_documents`, `evaluate_reference`, `default_gesture_log_filter`, `get_sdl_display_size`, `make_graphics_caching`, `GestureLog`, `GestureLogOverlayProjection`, `GestureLogRecordingProjection`, `LiveExample`, `timed_event`, `timed_operation`, `live_examples`, `json_typein_live`, `json_select_and_edit_live` all exist with the signatures/behavior the guide describes | grepped each definition individually (e.g. `example/projectured/Gallery.jl:12` for `run_example`, `source/kernel/reference/ReferenceSearch.jl:66` for `search_references`, `source/sdl/Sdl.jl:61` for `get_sdl_display_size`, `example/sdl/LiveExamples.jl:49,58,91,100,114,141,156,166,253` for the live-example family) | none needed | checked |
| "Tracing projection calls" section | (none — verification) | The Cassette-on-1.12 caveat is still accurate: `Cassette` is not even a dependency of the environment today | `grep -rn Cassette environment/all/Project.toml` → no hits | none needed | checked |

---

## documentation/guide/testing-guide.md

**Verdict:** UPDATE/REWRITE — the mechanics (per-package split, generic drivers, broken-test
protocol) are accurate and well written, but the specific facts about *what is covered* (the
catalog's domain list, three "guard only" packages, the database function name) are stale, and
the function inventory is missing a large fraction of what `test_all()` actually runs.
**Audience:** contributor to this repository. **Size:** 605 lines.

| where | category | finding | evidence | fix | confidence |
|---|---|---|---|---|---|
| §"Per-package tests" table, `test_json()`…`test_workbench()` row | WRONG | "`test_database_domain()` is the odd one out — `test_database` belongs to the ODBC live-connection suite" — backwards. There is no `test_database_domain` anywhere in the repository; `test_database()` **is** the domain aggregator | `grep -rn "function test_database\b\|function test_database_domain\b"` finds only `test/database/DatabaseSuite.jl:24: function test_database()`; `test_all()` calls `test_database()` directly (`test/projectured/ProjecturedSuite.jl:282`); the ODBC live-connection suite is `test_odbc_database` / `test_odbc_database_connection` / `test_odbc_database_no_db` (exported in the same file) | rewrite the sentence: `test_database()` is the domain aggregator; the ODBC live suite is the `test_odbc_database*` family | checked |
| §"The generated example catalog", "A domain is included once..." paragraph | STALE | "Three of them — yaml, book and database — hold only the guard so far; their first suite lands there." No longer true | `package/ProjecturedYamlTest/src/ProjecturedYamlTest.jl` includes `test/yaml/document/YamlParserTest.jl`; `ProjecturedBookTest` includes `test/book/projection/BookToSyntaxTest.jl`; `ProjecturedDatabaseTest` includes `test/database/document/DatabaseDocumentTest.jl` — all three now carry a real suite beyond the layering guard | delete the sentence or update it (it may now be true of different packages — re-check before writing) | checked |
| same section, "Still *out of scope* only for whole domains not yet wired: **formula** / **dbcatalog** (ODBC-gated) / **conversation**." | STALE | False today: all three are registered in the generated catalog | `example/projectured/DomainExamples.jl:394-403` registers `AtomicDocument(:conversation, ...)` (×4), `AtomicDocument(:dbcatalog, ...)` (×5), `AtomicDocument(:formula, ...)` | remove formula/dbcatalog/conversation from the "out of scope" list, or replace with whatever domains are actually still unwired | checked |
| same section, "covers json, yaml, xml, primitive, markdown, math, julia, book, filesystem, and sql" | STALE | The catalog's domain list is roughly double this | `grep -oE "AtomicDocument\(:[a-z_]+" example/projectured/DomainExamples.jl` (plus `example/substrate/SubstrateExamples.jl` for `primitive`) yields at least: book, chart, conversation, database, dbcatalog, filesystem, formula, fsm, graph, json, julia, markdown, math, primitive, rst, sequencechart, sql, workbench, xml, yaml | rewrite the domain list from the current registrations | checked |
| line 85-87, `test_all` description | STALE/WRONG | "the four per-package suites (`test_kernel()`, `test_substrate()`, `test_substrate()`, and one `test_<domain>()` per domain...)" — `test_substrate()` is named twice | `documentation/guide/testing-guide.md:85-87` (read directly) | drop the duplicate; the real per-package sequence in `test_all()` is `test_kernel()`, `test_substrate()`, then one call per domain (20 calls), not "four" | checked |
| whole "Per-package tests" / "top-level entry point" sections | MISSING | `test_all()` (`test/projectured/ProjecturedSuite.jl:264-342`) calls dozens of functions this guide never names: `test_tree()`, `test_naming()`, `test_package_graph()`, `test_export_collision_checker()`, `test_export_collisions()`, `test_gesture_recognizer()`, `test_catalog_coverage()`, `test_natural_renders_every_atom()`, `test_natural_round_trips_every_atom()`, `test_ollama()`, `test_click_roundtrips()`, `test_collapse_roundtrip()`, `test_json_content_clicks_clean_all()`, `test_table_navigation()`, `test_odbc_database_no_db()`, and a whole family of assistant/MCP-tool tests: `test_assistant_mvp`, `test_conversation_editor`, `test_workbench_file_keys`, `test_gallery_wrappers`, `test_list_guides`, `test_read_guide`, `test_list_modules`, `test_list_classes`, `test_list_functions`, `test_read_module_documentation`, `test_read_class_documentation`, `test_read_function_documentation`, `test_search_guides`, `test_search_api`, `test_search_tools_registered`, `test_execute_julia_code`, `test_workbench_editor_reference`, `test_function_availability`, `test_base_extensions` | read `test/projectured/ProjecturedSuite.jl:264-397` (the body of `test_all()` and every `export test_*` line that follows it) | add these to the tables, or at minimum note that `test_all()` runs materially more than the documented per-package/umbrella set — the assistant/MCP-tool family especially deserves its own row given the project's AI-first framing | checked |
| §"The examples follow the same split" / opt-in packages list | MISSING | `ProjecturedOllamaTest` (`test_ollama()`) is a fifth opt-in-backend test package, parallel to sdl/tulip/video/odbc, and is not listed alongside them | `package/ProjecturedOllamaTest/src/ProjecturedOllamaTest.jl` exists, is aggregated by `test_ollama()`, and is `using`-gated (needs `HTTP`, `JSON3`, a live or stand-in Ollama server) exactly like the other opt-in packages; `environment/all/Project.toml:65-66,188-189` wires it in | add a row for `test_ollama()` next to `test_sdl()`/`test_tulip()`/`test_video()`/`test_odbc()` | checked |
| §"Running tests via Pkg" | (none — verification) | "`Pkg.test("ProjecturedKernelTest")`... or `ProjecturedSubstrateTest`/`ProjecturedSubstrateTest`" repeats `ProjecturedSubstrateTest` twice (same typo pattern as the `test_all` duplication above) | `documentation/guide/testing-guide.md:461` (read directly) | second occurrence should presumably be `ProjecturedJsonTest` (per the "…" that follows) | checked |
| diagram (line 9) / "28 substrate packages" (line 19) | (none — verification) | Both counts are correct today | `grep "^Projectured" package/ProjecturedSubstrateTest/Project.toml` (deps section) lists exactly 28 non-kernel/example/test packages | none needed | checked |
| "twenty domains" (throughout) | (none — verification) | Correct: 20 per-domain test packages exist | counted Book, Chart, Conversation, Database, DbCatalog, FileSystem, Formula, Fsm, Graph, Json, Julia, Markdown, Math, Process, Rst, SequenceChart, Sql, Workbench, Xml, Yaml = 20 | none needed | checked |
| "about seven minutes over 103 examples" (`test_reactivity`) | (none — verification) | plausible; not exactly re-countable without Julia, but the `examples` vector is in the right ballpark | `awk`-counted ~110 `_example`-suffixed identifiers in `example/projectured/ProjecturedExamples.jl`'s `const examples = [...]` literal | none needed, low priority if it drifts further | likely |
| N/A (special check) | (verification) | "test_all takes about 47 minutes" is **not** stated in this guide at all — it appears only in `CLAUDE.md:108`, and is independently corroborated by three separate `plan/done/*.md` measurement notes, so it is not merely an unverified estimate | `grep -rn "47 minute" plan/done/*.md CLAUDE.md` → `plan/done/document-layouts-and-names.md:1031`, `plan/done/split-domain-into-per-domain-packages.md:431`, `plan/done/repository-tree.md:376` all independently state 47 minutes | none — flag as checked, not "unverifiable", if the rewrite adds this figure to the guide itself | checked |
| README.md / CLAUDE.md cross-check | CONTRADICTION | `CLAUDE.md:108` tells the reader to "See [testing-guide.md] for the full table of test functions and which package each one covers" — but per the MISSING finding above, the guide's table is missing a large fraction of the real functions, so CLAUDE.md's claim of "the full table" is itself inaccurate | `grep -n "test_all\|test_kernel\|47 minute" README.md CLAUDE.md` plus the `test_all()` body read above | either guide should be made complete, or CLAUDE.md's wording softened | checked |
| front-matter line | CODE-REFERENCE | Same `list_guides()` description-extraction issue as debugging-guide.md | see debugging-guide.md row | same fix | checked |

---

## documentation/guide/new-domain-guide.md

**Verdict:** REWRITE — the walking example (document types, examples, tests) is basically
right, but Step 3 teaches a pattern the repository's own style rule forbids for new code
without a stated reason, and Steps 2/5/6 omit boilerplate that is *required* for the tutorial's
own code to load. A newcomer who types the file exactly as shown gets a package that fails at
`using ProjecturedBookmark` with an `UndefVarError`. **Audience:** contributor adding a new
domain package. **Size:** 543 lines.

| where | category | finding | evidence | fix | confidence |
|---|---|---|---|---|---|
| Step 3, "Write the projection (printer)" | CONTRADICTION | The repository has an explicit, named style rule: **"Use `@projection_template`, not a hand-written printer and reader. … A hand-written pair needs a reason."** The tutorial spends its entire Step 3 (~150 lines) hand-writing `print_document`/`map_reference_forward`/`map_reference_backward` for both `BookmarkEntry` and `BookmarkList`, gives no reason for not using the template, and never mentions `@projection_template` exists | `documentation/rule/code-quality-rules.md:187-189`; confirmed every comparably small real domain uses the template instead: `source/xml/XmlToSyntax.jl` (`@projection_template XmlElementToSyntaxNode …` etc., 3 uses), `source/fsm/FsmToSyntax.jl` + `FsmDiagramToGraph.jl` (9 uses); even `source/math/MathToSyntax.jl`, which the tutorial itself names as "the next level of complexity" reference, uses `@projection_template` 17 times | rewrite Step 3 around `@projection_template` as the primary path; keep the hand-written form only as an appendix for when a projection must introduce structure the template can't express (which is in fact what `BookmarkEntryToSyntaxNode` does, and is a legitimate reason — but the guide should say so, and lead with the common case) | checked |
| Step 2, "Include the module file in the package root" | WRONG / MISSING | "The package root includes the module file and nothing else" is false for every real domain package. A domain's package root needs (a) a `using ProjecturedX` line per package the slice's `import ..XModule` statements reach into, and (b) a loop that rebinds each dependency's submodules as local `const`s, or `..CellModule` etc. never resolves inside the included slice | `package/ProjecturedJson/src/ProjecturedJson.jl` (its own docstring: *"inside a submodule of ProjecturedJson, `..SyntaxModule` resolves through the `const SyntaxModule = ProjecturedSyntax.SyntaxModule` the loop wrote"*) and `package/ProjecturedFsm/src/ProjecturedFsm.jl` both carry ~10 `using` lines plus a `for _src in (...) ... Core.eval(@__MODULE__, Expr(:const, ...))` loop before their one `include(...)` line. `BookmarkModule` (Step 1) opens with `import ..CellModule: Cell`, `import ..DocumentModule: Document, @document`, `import ..CollectionModule: CellVector`, `import ..ReferenceModule: Reference` — none of which resolve under Step 2 as written | add the `using` list and the flatten loop to Step 2, with a one-line explanation of what it does and why it's needed (name it, e.g., "the namespace-flattening loop") | checked |
| Step 5 ("Both files belong to the example package. In `package/ProjecturedBookmarkExample/…`, add: …") | MISSING | Same gap: real example packages (`package/ProjecturedFsmExample/src/ProjecturedFsmExample.jl`) carry ~30 `import`/`using` lines plus the identical flatten loop before their two domain-file includes; the tutorial shows only the two `include` lines and an `export` | read `package/ProjecturedFsmExample/src/ProjecturedFsmExample.jl` in full | same fix, applied to the example-package step | checked |
| Step 6 ("In `package/ProjecturedBookmarkTest/src/ProjecturedBookmarkTest.jl`: …") | MISSING | Same gap again: real domain test packages (`ProjecturedYamlTest`, `ProjecturedBookTest`, `ProjecturedDatabaseTest` — all read in full) carry ~30 `import`s, `using ProjecturedKernelExample`/`ProjecturedSubstrateExample`/`ProjecturedKernelTest`/`ProjecturedSubstrateTest`/`Projectured<Name>Example`, and the flatten loop, before their `include`s; the tutorial shows only two `include` lines | read `package/ProjecturedYamlTest/src/ProjecturedYamlTest.jl`, `ProjecturedBookTest/...`, `ProjecturedDatabaseTest/...` in full | same fix, applied to the test-package step | checked |
| Step 1 sidebar note on `@domain` | FRAMING / MISSING | The guide correctly says a one-line `@domain Bookmark` could generate the abstract root, the Insertion type, the Nothing placeholder, the Insert-key gesture and the insertion traits, and explains it spells them out "so the tutorial shows what the macro expands to." That's a reasonable pedagogical choice, but the guide never tells the reader that in practice they should write `@domain Bookmark`, so a reader who later greps a real domain for comparison (one line) against the ~50 lines they just wrote may be confused about which is idiomatic | `@domain` confirmed real and in active use: `source/domain/Domain.jl:542` (`macro domain(name, opts...)`), used by `source/json/JsonDocument.jl:7`, `source/fsm/FsmDocument.jl:7`, `source/xml/XmlDocument.jl:8`, `source/sequencechart/SequenceChartDocument.jl:43`, `source/chart/ChartDocument.jl:30` | add one explicit sentence: "in a real domain, write `@domain Bookmark` instead of Steps 1's abstract-type/Insertion boilerplate" | checked |
| Step 1 / Step 3, kernel API names used | (none — verification) | `@document` (auto-injects `selection::Reference`), `CellVector`, `print_child`, `make_child_context`, `PrinterContext`, `RecursiveProjection`, `TypeDispatchingProjection`, `ChainingProjection`, `SimpleIoMap`, `ChildrenIoMap`, `IdentityProjection`, `GraphicsCanvas`, `@reference`, `@reference_case` all exist as described | grepped each definition (`source/kernel/document/DocumentMacro.jl` "Inject the selection field"; `source/projection/higherorder/{Recursive,TypeDispatching,Chaining}.jl`; `source/kernel/iomap/IoMapDefaults.jl:56,76`; `source/graphics/GraphicsDocument.jl:380`) | none needed | checked |
| "What to add next" / closing pointer | (none — verification) | `MathToSyntax.jl` exists and is a reasonable "next level" reference (though see the `@projection_template` finding above — it's actually evidence *against* the tutorial's own approach) | `source/math/MathToSyntax.jl` exists | none needed beyond finding above | checked |
| overall package layout claim | (none — verification) | "package/<Name>/ holds only Project.toml + src root; code in source/<slice>/, documents in example/<slice>/, tests in test/<slice>/" matches real domains structurally | confirmed against `ProjecturedJson`/`ProjecturedFsm`/`ProjecturedXml` trees | none needed | checked |

---

## documentation/guide/static-compilation-guide.md

**Verdict:** REWRITE or re-scope — the content present is accurate and carefully measured, but
the title/framing claims the general "static compilation" story while covering only an
unused research probe; the repository's actual, shipping compiled-executable path is absent
and not cross-linked. **Audience:** contributor/performance-minded Julia developer researching
`juliac --trim` specifically — not (as currently framed) "how do I build a ProjecturEd binary."
**Size:** 203 lines.

| where | category | finding | evidence | fix | confidence |
|---|---|---|---|---|---|
| whole file / title | MISSING (major) | The guide covers only `juliac --trim`, which it says itself "[n]o code in this repository uses... yet." The repository has a separate, real, working static-compilation path — `build_executable`/`BuildSpec` (`source/builder/Builder.jl`), packaged as `ProjecturedBuilder`, producing a native app via `PackageCompiler.create_app` (`source/builder/Builder.jl:239-240`), with `package/ProjecturedExecutable`/`source/executable/Executable.jl` as the compiled entry point — and none of it is mentioned here | read `source/builder/Builder.jl:1-251` and `package/ProjecturedExecutable/src/ProjecturedExecutable.jl`; `package/ProjecturedBuilder/src/ProjecturedBuilder.jl` docstring: *"`build_executable` turns a spec into a binary: … 3. compile with PackageCompiler."* | either rename this guide to scope it explicitly to the `juliac --trim` experiment (e.g. "juliac trim notes"), or add a section/cross-link to the actual `build_executable` procedure as the primary "how to compile ProjecturEd" path | checked |
| N/A | DUPLICATE / cross-reference gap | `documentation/package/executable/README.md` documents `ProjecturedExecutable`/`build_executable` but never mentions `juliac` or this guide; this guide never mentions that README either — two disconnected "how ProjecturEd gets compiled" documents | `grep -rln "build_executable\|ProjecturedBuilder" documentation/` → only `documentation/package/executable/README.md` (plus rule docs); `grep -n "juliac\|static-compilation" documentation/package/executable/README.md` → no hits | add a two-way cross-link | checked |
| line 12, "The probe that measured every number is in [bench/juliac-trim/](../../tool/juliac-trim)" | STYLE | Link *label* says "bench/juliac-trim/"; the actual (and target) path is `tool/juliac-trim/`. The href resolves correctly — only the visible text is wrong | `find tool/juliac-trim -maxdepth 1` confirms the real path; the markdown source has the mismatched label | change the label text to `tool/juliac-trim/` | checked |
| N/A | CODE-REFERENCE | `tool/juliac-trim/README.md` explicitly names and links this guide ("Development-only measurements that back [documentation/guide/static-compilation-guide.md]") — moving/renaming this file breaks that reference | `tool/juliac-trim/README.md:3-4` | keep the filename stable, or update the probe README's link together with any rename | checked |
| "What the rule costs ProjecturEd" table (`Projection`: 410/407, `IoMap`: 70/70, `Document`: 61/1, `Operation`: 54/53, `ReferenceStep`: 10/10, `Backend`: 1/1) | (none — verification) | Could not be re-counted without loading Julia (explicitly disallowed for this survey); the surrounding tooling (`tool/juliac-trim/probe.jl`, `hide.jl`, `sealed.sh`, `sealed_patch.py`, `mutable_check.jl`) exists and matches the described purpose in `tool/juliac-trim/README.md` | read `tool/juliac-trim/README.md` in full; all five scripts referenced exist | none needed unless re-measured | likely |
| front-matter line | CODE-REFERENCE | Same `list_guides()` description-extraction issue as the other three files | see debugging-guide.md row | same fix | checked |

---

## Top findings of this area

1. **new-domain-guide.md Step 3 contradicts the repository's own style rule.** `documentation/rule/code-quality-rules.md:187-189` says to use `@projection_template`, not a hand-written printer/reader, "without a reason." The tutorial hand-writes ~150 lines of printer/mapper code and never mentions the template — while every comparable real domain (xml, fsm) and even the guide's own "next level" pointer (math) is written with `@projection_template`.
2. **new-domain-guide.md Steps 2/5/6 omit load-bearing boilerplate.** The tutorial's package-root files (`ProjecturedBookmark`, `ProjecturedBookmarkExample`, `ProjecturedBookmarkTest`) are shown as bare `include(...)` calls. Every real domain's package root (`ProjecturedJson`, `ProjecturedFsm`, and their `Example`/`Test` counterparts) needs a `using <deps>` list plus a namespace-flattening loop, or the slice's `import ..CellModule: Cell`-style imports never resolve. Followed literally, the tutorial produces a package that fails to load.
3. **testing-guide.md's list of what `test_all()` runs is a small fraction of the real thing.** `test_all()` (`test/projectured/ProjecturedSuite.jl:264-342`) calls dozens of functions absent from the guide, including a whole family of AI-assistant/MCP-tool tests (`test_list_guides`, `test_search_api`, `test_execute_julia_code`, `test_assistant_mvp`, …) — directly relevant to the "AI integration from the ground up" framing the owner wants to foreground.
4. **testing-guide.md's catalog-coverage claims are stale in two ways at once.** It says formula/dbcatalog/conversation are "still out of scope" (they are registered in `example/projectured/DomainExamples.jl` today) and lists only 10 catalog domains where at least 19-20 are registered.
5. **testing-guide.md gets the database test function backwards.** "`test_database_domain()` is the odd one out" — no such function exists; `test_database()` is the real per-domain aggregator (`test/database/DatabaseSuite.jl:24`), called directly by `test_all()`.
6. **testing-guide.md's "yaml, book, database hold only the guard" is stale** — all three now ship a real first suite (`YamlParserTest.jl`, `BookToSyntaxTest.jl`, `DatabaseDocumentTest.jl`).
7. **static-compilation-guide.md documents an experiment, not the shipping build path.** The guide's own words: "No code in this repository uses the technique [`juliac --trim`] yet." The actual compiled-executable pipeline — `build_executable`/`ProjecturedBuilder` using `PackageCompiler.create_app` — is undocumented here and not cross-linked from `documentation/package/executable/README.md` either.
8. **Two broken file-rename links in debugging-guide.md (also affecting testing-guide.md's neighbors).** `source/kernel/editor/Editor.jl` and `source/kernel/projection/ProjectionApi.jl` no longer exist (now `EditorModule.jl` and `ProjectionInterface.jl`); the stale "`package/kernel/main/...`" label is repeated across several *other* guides too (`editor.md`, `projection-system.md`, `higher-order-projections.md`, `devices-and-backends.md`, `cell.md`), so this is a systemic pattern, not a one-off typo.
9. **debugging-guide.md's example-registry link is broken.** `example/projectured/Examples.jl` doesn't exist; the real file is `example/projectured/ProjecturedExamples.jl`.
10. **All four guides' front-matter breaks the AI assistant's guide listing.** `list_guides()` (`source/kernel/tool/Documentation.jl`) takes the first non-blank line after the `#` title as a guide's description. For all four files that line is the `> **Kind:** ... **Stands on:** ...` blockquote, so the assistant/MCP client sees that metadata line instead of a real one-sentence summary when browsing guides — untested (`test_list_guides` only checks non-emptiness). Given the new framing puts the in-editor assistant and MCP clients on equal footing with human readers, this is worth fixing as part of any rewrite.
11. **debugging-guide.md never mentions `write_example_image`**, an existing single-screenshot REPL helper, even though its bulk sibling (`generate_example_screenshots`) is documented.
12. **No procedure guide covers newcomer-relevant, AI-framing-relevant tasks:** using ProjecturEd as a library from another project, opening an arbitrary Julia value in an editor window, connecting an external MCP client, or running the assistant against a local model (Ollama support exists in code — `ProjecturedOllama`, `test_ollama()` — but has no how-to anywhere in `documentation/guide/`).

---

# Survey area G1 — the per-domain guides

Files reviewed: `documentation/package/json/json.md`, `xml/xml.md`, `rst/rst.md`,
`fsm/fsm.md`, `process/process.md`, `graph/graph-layout.md`, `math/math.md`,
`chart/chart.md`, `sequencechart/sequencechart.md`, `workbench/workbench.md`,
`conversation/transcript.md`, `versioning/versioning.md`.

Method: static only (`grep`/`find`/`git log`/`Read`), no Julia run, per the brief.

---

## `documentation/package/json/json.md`

**Verdict: UPDATE.** **Audience:** Julia developer using ProjecturEd as a library; AI assistant. **Size:** 109 lines.

All types (`JsonNull`, `JsonBool`, `JsonNumber`, `JsonString`, `JsonArray`, `JsonObject`,
`JsonObjectEntry`), the `collapsed` field, and every code example check out exactly against
`source/json/JsonDocument.jl`.

| where | category | finding | evidence | fix | confidence |
|---|---|---|---|---|---|
| whole file | MISSING | The guide never names a single implementation file. `source/json/` has 5 files (`JsonDocument.jl`, `JsonFile.jl`, `JsonModule.jl`, `JsonParser.jl`, `JsonToSyntax.jl`); the guide covers only the document types (in `JsonDocument.jl`) and never mentions the parser, the `.json` file wrapper, or the `JsonToSyntax` projection (the printer/reader that actually renders and reads back the syntax shown in the screenshot). | `grep -n "JsonFile\|JsonParser\|JsonToSyntax\|JsonModule" documentation/package/json/json.md` → no matches. `ls source/json/` lists all 5 files. | Add a short "Files" section naming `JsonParser.jl` (`parse_json`), `JsonToSyntax.jl` (the printer/reader), and `JsonFile.jl` (`.json` registration), the way `rst.md`/`math.md` do. | checked |
| whole file | FRAMING | Purely a data-model reference; no framing problem, but also no hook to the new framing (no mention that this is one of many domains a value gets projected into on demand). | — | Optional: one sentence tying it to the domain-inventory framing. | likely |

---

## `documentation/package/xml/xml.md`

**Verdict: UPDATE.** **Audience:** Julia developer using ProjecturEd as a library; AI assistant. **Size:** 57 lines.

Types (`XmlAttribute`, `XmlText`, `XmlElement`) and every constructor form in the Examples
section check out against `source/xml/XmlDocument.jl` — except one.

| where | category | finding | evidence | fix | confidence |
|---|---|---|---|---|---|
| line 41, Examples | WRONG | `push!(elem, XmlText("More content"))` has no matching method. `XmlElement` gets no `push!`: `@adapt_map_protocol on XmlElement to attrs with XmlAttribute(name, value)` only wires the *keyed* protocol (`getindex`/`setindex!`/`haskey`/`delete!`) onto `attrs`, and `@forward_vector_protocol` (which is what supplies `push!`, see `source/kernel/document/ForwardProtocol.jl:48-67`) is never called for `XmlElement` at all — not for `attrs`, not for `children`. `push!(::XmlElement, ...)` would throw `MethodError`. | `grep -rn "Base.push!" source/xml/*.jl` → no hits; `grep -rn "forward_vector_protocol" source/xml/*.jl` → no hits; `source/kernel/document/ForwardProtocol.jl:85-137` shows `@adapt_map_protocol` never defines `push!`. | Either add the forwarding in code, or change the example to `elem.children[end+1] = XmlText(...)`-style splice / the actual editing path. | checked |
| whole file | MISSING | Same gap as json.md: no mention of `XmlFile.jl` (file wrapper), `XmlParser.jl` (the parser), or `XmlToSyntax.jl` (the projection) — the guide is document-model only. | `grep -n "XmlFile\|XmlParser\|XmlToSyntax\|XmlModule" documentation/package/xml/xml.md` → no matches; `ls source/xml/` lists all 5 files. | Add a "Files" section. | checked |
| whole file | DUPLICATE | The "Indexing conventions" paragraph (line 9) is close to verbatim shared text with `json.md` line 9 and `rst.md`'s boundary-axis language — not wrong, but worth factoring into the shared `kernel/reference.md` cross-reference once, rather than restating per domain. | Compare json.md:9 and xml.md:9. | Low priority; note for the rewrite. | checked |

---

## `documentation/package/rst/rst.md`

**Verdict: UPDATE** (content and structure are sound; many small facts are stale). **Audience:**
contributor to this repository; Julia developer. **Size:** 273 lines. This is the deepest and
best-written guide of the twelve, but it accumulated the most stale file/function names.

| where | category | finding | evidence | fix | confidence |
|---|---|---|---|---|---|
| line 13 | WRONG | "Files: `rst/  Rst.jl · RstParser.jl · RstToSyntax.jl · RstFile.jl`" — `Rst.jl` does not exist, and the list omits two real files, `RstModule.jl` and `RstToLayout.jl` (the latter is discussed at length later in the same guide, under "A page is a stack of blocks"). | `ls source/rst/*.jl` → `RstDocument.jl RstFile.jl RstModule.jl RstParser.jl RstToLayout.jl RstToSyntax.jl`. `grep -rn "Rst\.jl" documentation/ source/` finds only this one (self-referential) hit. | Replace with the real 6-file list. | checked |
| line 11 | WRONG | "Slice: `package/rst/main/`" is not written this way, but the sibling guides fsm.md/process.md make the identical mistake for their own slices (see below) — worth checking rst.md too: it does NOT actually state a `package/...` slice path (only fsm/process do). No fix needed here. | — | — | checked |
| line 31 vs 47-51 | CONTRADICTION | "Directives — **twelve** typed structs plus one generic fallback" (stated twice: lines 31 and 47) but only **eleven** are named: `RstLiteralInclude, RstFigure, RstCodeBlock, RstImage, RstVideo, RstAudio, RstAdmonition, RstToctree, RstMathBlock, RstRawBlock, RstRoleDefinition`. `source/rst/RstDocument.jl` confirms exactly these 11 typed-directive structs (plus `RstDirective` as the generic fallback, and `RstDirectiveOption` for a directive's own option list, neither of which is a "directive" itself). | `grep -n "@document struct Rst" source/rst/RstDocument.jl` → 43 structs total; counting the directive-specific ones gives 11, not 12. | Say "eleven", or find the twelfth if one was meant and dropped. | checked |
| line 169 | WRONG | "The module registers `natural_syntax_projection` / `natural_extension` / `parse_natural`" — none of these three names exist. The actual `__init__` in `RstModule.jl` calls `register_natural_syntax!(...)`, `register_file_document_type!(".rst", RstFile)`, and `register_natural_domain!(RstDocument; rung=:syntax, make=..., format=:rst, extension=".rst", parse=parse_rst)`. | `source/rst/RstModule.jl:91-103`. | Name the real functions (`register_natural_syntax!`, `register_natural_domain!`, `register_file_document_type!`) or the keyword slots (`format`, `extension`, `parse`) rather than invented identifiers. | checked |
| line 220 | WRONG | "the five fixtures in `package/projectured/test/fixture/rst/`" — that path does not exist. The five fixtures are at `test/rst/fixture/rst/` (count confirmed: 5 files). | `find . -path "*fixture/rst*"` → `test/rst/fixture/rst/{showcase-manualconfiguration,showcase-txop,users-guide-queueing,global,showcases-index}.rst` (5 files, so "five" is right, only the path is wrong). | Fix the path. | checked |
| line 231 | WRONG | "`test_rst_embed()`" does not exist; the real function is `test_rst_embed_card()`. | `grep -rn "function test_rst_embed" test/` → `test/rst/projection/RstEmbedCardTest.jl:5:function test_rst_embed_card()`. | Rename in the guide. | checked |
| whole file | STYLE | Otherwise this is the strongest-written guide of the twelve: terse, concrete, and explicit about known limits (a "Known limits" section none of the other eleven guides have). No AI-slop language found. | — | Use as the template for rewriting the others. | checked |
| whole file | FRAMING | Already well aligned: frames RST as "built against the documentation of INET" and proven on an external, 51k-line corpus — a real-world demonstration, not "just an editor" framing. | — | Keep this framing in the rewrite. | checked |

---

## `documentation/package/fsm/fsm.md`

**Verdict: UPDATE.** **Audience:** contributor / Julia developer modeling a protocol machine; AI
assistant (this guide is unusually dense with a *behavioral contract*, which is exactly the kind
of thing an assistant needs verbatim before generating FSM code). **Size:** 131 lines.

Every document type, field, and function name checked (`FsmComponent`, `FsmMachine`, `FsmState`,
`FsmTransition`, `FsmVariable`, `FsmTimer`, `FsmEvent`, the iteration cap default of 32) matches
`source/fsm/FsmDocument.jl` and `source/fsm/FsmToJuliaCode.jl` exactly.

| where | category | finding | evidence | fix | confidence |
|---|---|---|---|---|---|
| line 11 | WRONG | "Slice: `package/fsm/main/`" — this path does not exist. Per repo convention (CLAUDE.md), the code is in `source/fsm/`; the `package/` folder is `package/ProjecturedFsm/src/` (an include list only). | `ls package/ | grep -i fsm` → `ProjecturedFsm ProjecturedFsmExample ProjecturedFsmTest`; `find package -iname "*fsm*"` shows no `package/fsm/main`. | Say `source/fsm/` (package: `ProjecturedFsm`). | checked |
| line 11-12 | STALE | "Design plan and its research grounding: `plan/pending/state-machine-domain.md`" — the plan is not pending; it has been moved to `plan/done/state-machine-domain.md` (consistent with the FSM domain being fully implemented, tested, and used by three reference machines as this same guide describes). | `test -f plan/pending/state-machine-domain.md` → missing; `find plan -iname "*state-machine*"` → `plan/done/state-machine-domain.md`. | Update the path to `plan/done/`. | checked |
| whole file | MISSING | `FsmComponent`'s field list in the Document types table (`variables, timers, events, machines, usings, helpers`) omits the real `supertype::String` field, which the docstring in the source explains is functionally significant (what the generated `…State` struct subtypes). | `source/fsm/FsmDocument.jl:111-120`. | Add `supertype` to the table row. | checked |
| whole file | FRAMING | This guide is one of the two (with process.md) that already embodies the new framing without needing a rewrite: it explicitly frames the domain as producing "complete, runnable Julia code," not merely an editable picture. Good model text: "the slice exists to express real protocol machines... well enough that a component projects to complete, runnable Julia code." | line 6-9. | Keep as reference language for the rewrite. | checked |

---

## `documentation/package/process/process.md`

**Verdict: UPDATE.** **Audience:** contributor / Julia developer; AI assistant. **Size:** 291
lines. Extremely accurate — every function checked (`process_nodes`, `node_at`,
`get_node_index`, `get_unrefined_nodes`, `is_executable`, `get_body_steps`, `realize_process`,
`realize_process_text`, `export_process`, `ProcessDebugSession`, `ProcessTrace`,
`sync_process_debug!`, `ProcessStoppedException`, `make_deferred_layout_engine`) matches the
source exactly, including the instrumentation levels `:none`/`:position`/`:locals`.

| where | category | finding | evidence | fix | confidence |
|---|---|---|---|---|---|
| line 10 | WRONG | "Slice: `package/process/main/`" — same error as fsm.md. Does not exist; real location is `source/process/` (package `ProjecturedProcess`, at `package/ProjecturedProcess/src/`). | `find package/ProjecturedProcess -maxdepth 2` → only `Project.toml` and `src/ProjecturedProcess.jl`. | Say `source/process/`. | checked |
| line 10 | (verified correct) | "Design plan: `plan/done/process-domain.md`" — this one IS correct, unlike fsm.md's stale pending-path. | `test -f plan/done/process-domain.md` → exists. | none needed | checked |
| whole file | FRAMING | Like fsm.md, already strongly aligned with the new framing: "still be real, runnable code, debuggable in the editor while it runs" (line 8) is close to the target language ("an AI assistant... writes and runs Julia against the live editor"). The "Debugging in the editor" section (breakpoints, live trace, the `sync_process_debug!` bridge) is a genuinely distinctive, demo-worthy feature that supports the on-demand-UI pitch well. | lines 8, 242-277. | Keep and lean on this section for a Reddit-facing rewrite. | checked |

---

## `documentation/package/graph/graph-layout.md`

**Verdict: KEEP** (small fix only). **Audience:** contributor implementing or tuning a layout
engine; Julia developer building a graph-shaped domain. **Size:** 137 lines.

Engines (`GridEmbedding`, `SpringEmbedderLayout`, `ForceDirectedLayout`, `AdaptagramsLayout`,
`DeferredLayout`), `layout_graph` signature, all six constraint kinds and
`get_supported_constraint_kinds`, the determinism section (LCG port, `seed`, `max_calculation_time`),
and `graphlayoutbench()` all check out exactly against `source/graph/*.jl` and
`test/bench/graphlayoutbench.jl`.

| where | category | finding | evidence | fix | confidence |
|---|---|---|---|---|---|
| line 118 (ported-files table) | WRONG | `Geometry.jl` → `geometry.h` — the real file is `LayoutGeometry.jl`, not `Geometry.jl`. | `ls source/graph/omnetpp/` → `LayoutGeometry.jl` (no `Geometry.jl`). | Rename the table cell. | checked |
| whole file | (no other issues found) | Constraint kinds, `GraphLayout.engine` symbol values, and the ten ported `omnetpp/` files otherwise match one-for-one. | `source/graph/GraphLayoutEngine.jl:66`, `source/graph/GraphLayout.jl:64-66`. | — | checked |

---

## `documentation/package/math/math.md`

**Verdict: UPDATE.** **Audience:** Julia developer building a formula-bearing domain; contributor
tuning the typesetting. **Size:** 218 lines. Every numeric constant checked (superscript rise
0.36, subscript fall 0.2, delimiter tiling threshold 1.6× line height, radical cap 2.2× base size,
script/scriptscript scale 0.7/0.5) is exact against `source/math/MathToGraphics.jl`. The parsing
rules (fraction vs. division by spacing, function-call detection, negative-number rule) are
consistent with `MathParser.jl`.

| where | category | finding | evidence | fix | confidence |
|---|---|---|---|---|---|
| line 58 | WRONG / LINK | "One table in [Math.jl](../../../source/math/Math.jl)" — `source/math/Math.jl` does not exist. The operator table (`_MATH_OPERATORS`) is defined in `source/math/MathDocument.jl:238`. | `test -f source/math/Math.jl` → missing; `ls source/math/` → `MathDocument.jl MathFile.jl MathModule.jl MathParser.jl MathToGraphics.jl MathToSyntax.jl`. | Fix the link target and filename. | checked |
| line 216 | WRONG / LINK | "The examples are in [example/document/Math.jl](../../../example/math/document/Math.jl)" — that path does not exist. The real files are `example/math/MathDocumentExample.jl` (`make_math_display_document_example`) and `example/math/MathProjectionExample.jl` (`make_math_display_projection_example`). | `find example/math -type f` → `MathProjectionExample.jl MathDocumentExample.jl`; both functions grepped and found at the expected lines. | Fix the link and path. | checked |
| whole file | (otherwise accurate) | The box protocol (`MathIoMap`, `width`/`ascent`/`descent`), `MathMetrics`, `MathChild`, and the selecting/editing key table all check out against `MathToGraphics.jl`. | — | — | checked |

---

## `documentation/package/chart/chart.md`

**Verdict: UPDATE.** **Audience:** Julia developer plotting simulation/data results; AI assistant
(this guide, with sequencechart.md, is the strongest candidate to showcase "any value gets an
editable view" since a chart is ordinary data turned into a real, selectable document). **Size:**
331 lines — the longest and most detailed of the twelve, and one of the best-aligned with the new
framing already ("no plotting library and no rasterization... every part of it can be edited the
way any other document is").

| where | category | finding | evidence | fix | confidence |
|---|---|---|---|---|---|
| line 16 | WRONG | "Semantic content, in `chart/Chart.jl`" — no such file. The types (`Chart`, `ChartAxis`, `ChartLineSeries`, etc.) live in `source/chart/ChartDocument.jl`. | `ls source/chart/` → `ChartDocument.jl ChartModule.jl ChartPlot.jl ChartPlotToGraphics.jl ChartSampleReferenceStep.jl ChartToChartPlot.jl`; no `Chart.jl`. | Rename to `ChartDocument.jl`. | checked |
| line 31 | (verified correct) | "Presentation state, in `chart/ChartPlot.jl`" — this one is right. | `source/chart/ChartPlot.jl` exists. | — | checked |
| whole file | (otherwise accurate) | The two-stage projection, reference-path shapes, `ChartSampleReferenceStep`, the scale/decimation section, and the interaction table all check out against `source/chart/*.jl`. | — | — | checked |

---

## `documentation/package/sequencechart/sequencechart.md`

**Verdict: KEEP.** **Audience:** Julia developer visualizing traces/logs; contributor. **Size:**
178 lines. Every concept and type checked (`SequenceChartAxis`, `SequenceChartEvents`,
`SequenceChartArrows`, `SequenceChartBandSeries`, `SequenceChartEventKind`,
`SequenceChartArrowKind`, `SequenceChartTimeline`, `SequenceChartGutter`, `SequenceChartView`,
`FlowFrame`, `SequenceChartRowReferenceStep`, all four timeline modes `:time`/`:ordinal`/`:step`/
`:nonlinear`) checked out exactly against `source/sequencechart/*.jl`. All three named examples
(`sequencechart`, `sequencechart_vertical`, `sequencechart_linear`) exist and are registered in
`example/projectured/DomainExamples.jl`.

| where | category | finding | evidence | fix | confidence |
|---|---|---|---|---|---|
| whole file | MISSING | No file-path references at all (unlike chart.md), so nothing to be wrong about, but also nothing telling a reader where the implementation lives. `source/sequencechart/` has 7 files; none is named. | `ls source/sequencechart/`. | Add a one-line file map, matching chart.md's pattern (once that one is fixed). | checked |
| whole file | FRAMING | Strong example already: "it answers it for anything with participants and messages: a simulation trace, a protocol exchange, a distributed system's logs, a UML interaction" is exactly the domain-agnostic framing the new pitch wants (a generic viewer applied to arbitrary data, not "an editor for simulation traces"). | lines 7-10. | Keep. | checked |

---

## `documentation/package/workbench/workbench.md`

**Verdict: REWRITE.** **Audience:** new user / contributor (this is the guide to the whole
application shell). **Size:** 112 lines. This is the most broken guide of the twelve: it
conflates a separate, more recently extracted slice (`source/assistant/`) with the workbench
itself, cites a projection name that does not exist, gives a wrong constructor signature, and
never mentions the entire `source/pane/` generic tab/split-pane system or the file-navigation
plumbing.

| where | category | finding | evidence | fix | confidence |
|---|---|---|---|---|---|
| line 22, 35 | WRONG | The Document types table's header claims "All subtype `WorkbenchDocument` (`<: Document`)" and then lists `Assistant` as a row of that table. `Assistant` is *not* a `WorkbenchDocument`: it is `@document struct Assistant <: Document` in `source/assistant/AssistantDocument.jl:86`, a separate slice. `WorkbenchToWidget.jl` has to special-case it explicitly: `_is_panel(doc) = doc isa WorkbenchDocument \|\| doc isa Assistant` (line 104). | `source/assistant/AssistantDocument.jl:86`; `source/workbench/WorkbenchToWidget.jl:104`. | Move `Assistant` out of the "subtype `WorkbenchDocument`" table, or note explicitly that it is a sibling slice special-cased into the workbench. | checked |
| line 57 | WRONG | "`WorkbenchAssistantToWidgetSplitPane`" does not exist anywhere in the repository. The real projection is `AssistantToWidgetSplitPane`, defined in `source/assistant/AssistantToWidget.jl:20`, and dispatched to from `WorkbenchToWidget.jl:866` (`Assistant => AssistantToWidgetSplitPane()`). | `grep -rn "WorkbenchAssistantToWidgetSplitPane" source/ test/ example/ documentation/` → only the one, self-referential hit in workbench.md itself. | Rename to `AssistantToWidgetSplitPane` and note it lives in `source/assistant/`, not `source/workbench/`. | checked |
| line 35 | STALE | The `Assistant(...)` keyword list "`conversation, input, backend, model, system, api_key, status, llm`" is missing three real keywords the constructor actually takes: `draft`, `context`, `collapse_thinking`. | `source/assistant/AssistantDocument.jl:103-113`, the real keyword signature. | Update the field list. | checked |
| whole file | HISTORY / STALE | `source/assistant/AssistantToWidget.jl:1-8` states outright: "Both [`AssistantToWidgetSplitPane`/`AssistantToWidgetCard`] were `WorkbenchModule`'s, beside the IDE's shell, its navigator and its console. They moved with the document." workbench.md was never updated after this extraction (see the commit series below) and still documents the pre-extraction shape. | `source/assistant/AssistantToWidget.jl:1-8`; `git log --oneline --since=2026-08-01 -- source/workbench source/pane` shows the recent naming-law refactor commits, e.g. `56562a07 Merge main: the assistant API work, with the naming law applied to it`. | Rewrite this section around the current slice boundary. | checked |
| line 34 | WRONG | `WorkbenchEditor(title, filename, content)` — wrong argument order and wrong arity. The real constructor is `WorkbenchEditor(content; title="", filename="", follow_end=false)`: `content` is positional and first, `title`/`filename` are keyword-only, and there is a fourth field, `follow_end::Bool`, not mentioned at all. | `source/workbench/WorkbenchDocument.jl:178-191`. | Fix the signature and add `follow_end`. | checked |
| whole file | MISSING | `source/pane/` (7 files: `PaneDocument.jl`, `PaneGeometry.jl`, `PaneGestures.jl`, `PaneModule.jl`, `PaneProgram.jl`, `PaneSurgery.jl`, `PaneToWidget.jl`) implements a second, independent, and more general tab/split-pane system (`PaneTree`/`PaneGroup`/`PaneSplit`/`PaneTab`, with its own already-published guide at `documentation/package/pane/pane.md`) — not used by `source/workbench/` at all (`grep` for `PaneTree`/`PaneGroup`/`PaneSplit` in `source/workbench/` returns nothing). workbench.md's `WorkbenchPage`/`WidgetTabbedPane` tab model and the `pane` slice's `PaneTree` model are two parallel implementations of "tabs," and the guide gives no hint that a second one exists or how they relate. | `grep -rn "PaneTree\|PaneGroup\|PaneSplit\|PaneTab" source/workbench/` → no hits. | Add a section clarifying the relationship (or its current absence) between `WorkbenchPage` and `PaneTree`. This matters for the rewrite: the brief's requested demo topics — "duplicate a pane," "Alt+click to select a widget," "paste into a new tab" — are all `source/pane/`-side plans, several still in `plan/pending/` (`duplicate-a-pane.md`, `pane-layout.md`, `split-pane-drag-resize.md`, `split-pane-inset.md`, `tabbed-pane-scroll.md`, `widget-transform-pane.md`), i.e. **not yet complete** — a rewrite must not claim them as shipped workbench features. | checked |
| whole file | MISSING | `WorkbenchFile.jl` (the workbench's own file-document wrapper) and `Workspace.jl` / `WorkspaceToFileSystem.jl` (how the Navigator's file tree maps to the real filesystem) are never explained. `Workspace()` appears once, unexplained, in the "Building a workbench" example (line 66). | `ls source/workbench/` → 6 files; `grep -n "WorkbenchFile\|WorkspaceToFileSystem\|Workspace(" documentation/package/workbench/workbench.md` → only the one bare `Workspace()` call. | Add a short paragraph on `Workspace`/`WorkspaceToFileSystem` (how the Navigator reaches disk) and `WorkbenchFile`. | checked |
| whole file | FRAMING | Calls the workbench "an IDE-style workspace" and leads with the IDE framing throughout; never connects to the AI-assistant-native pitch even though the Assistant panel is one of its four listed document types. Given the new framing's emphasis on AI integration "from the ground up," this guide — being the one that assembles the whole application shell — is the natural place to state that pitch, and currently does not. | lines 1, 7. | Rewrite the opening to frame the workbench as an on-demand UI shell that happens to include an AI assistant as one first-class panel among others, not as "an IDE" with AI bolted on as a fourth panel. | checked |

---

## `documentation/package/conversation/transcript.md`

**Verdict: UPDATE**, but flag a much larger structural gap outside the file itself (see below).
**Audience:** contributor; AI assistant (this describes how the assistant's own output renders).
**Size:** 90 lines.

Everything the guide claims about `ConversationToWidget.jl` was checked and is accurate: the fold
mechanism (`turn.collapsed`, `part.collapsed`, `form_collapsed`/`result_collapsed`), the
`get_evaluation_title` header table (`eval` / `resource · <uri>` / `resources` / `tool · <name>
"<query>"` cut at 60 chars, confirmed byte-for-byte in `source/conversation/Evaluator.jl:83-95`),
`get_evaluation_section_labels`, `ToggleCollapseOperation`/`ToggleEvaluatorSectionOperation`, and
the "Starts" fold-state table (including that a resource read starts folded as a whole — traced to
`source/assistant/AssistantTurn.jl:583`, `_collapse_tool_default(name) =
get_evaluation_kind_label(name) == "resource"`).

| where | category | finding | evidence | fix | confidence |
|---|---|---|---|---|---|
| whole file | MISSING (central finding for this area) | **`source/assistant/` is not documented anywhere in the repository.** No file under `documentation/` mentions `AssistantTurn.jl`, `AssistantDocument.jl`, or `AssistantToWidget.jl`. This is 1,407 lines of code, including `AssistantTurn.jl` (950 lines) — almost certainly where the streaming loop, tool execution, and backend dispatch (`:anthropic`, `:ollama`) live, which is the literal mechanism of "the assistant... writes and runs Julia against the live editor" that the new framing wants to foreground. transcript.md only documents how the assistant's *output* is drawn, not how the assistant runs. | `grep -rln "source/assistant\|AssistantTurn\|AssistantDocument\.jl\|AssistantToWidget\.jl" documentation/` → no output at all. | This is a missing-guide gap, not a defect in transcript.md's own (narrower, correctly-scoped) content. The rewrite needs a new guide for `source/assistant/`, and workbench.md and transcript.md should both link to it. | checked |
| whole file | MISSING | `source/conversation/ConversationEditor.jl` (781 lines — the user-message **composer**: draft parts, the kind chooser, `TAB`/`INSERT`→chooser, `SHIFT+ENTER` newline, `ENTER`→submit) is not mentioned. transcript.md's one sentence about composing ("A typed message becomes a markdown document when the composer commits it...") is the only acknowledgment that a composer exists at all; its own mechanics are undocumented. `source/conversation/` is 1,652 lines total; transcript.md documents roughly the 489-line `ConversationToWidget.jl` plus parts of the 178-line `Evaluator.jl` — under half the slice. | `wc -l source/conversation/*.jl` → `ConversationEditor.jl` is the single largest file in the slice at 781 lines; `grep -n "ConversationEditor" documentation/package/conversation/transcript.md` → no hits. | Either fold a composer section into this guide (renaming it beyond "the transcript") or write a sibling guide for the composer. | checked |
| line 3 | (verified correct) | Both "Stands on" links (`widget/widget.md`, `../../design/editor-concepts.md`) resolve to real files. | `test -f documentation/package/widget/widget.md` and `documentation/design/editor-concepts.md` → both exist. | — | checked |
| whole file | STYLE | Clean, plain technical English throughout; no AI-slop found. Good model for the rewrite. | — | — | checked |

---

## `documentation/package/versioning/versioning.md`

**Verdict: UPDATE.** **Audience:** contributor / Julia developer building on the versioning
overlay (advanced/internal feature, low priority for a Reddit-facing rewrite). **Size:** 102 lines.

The document model (`VersionedObject`, `ObjectVersion`, `VersionProperties`), all five
`VersionCriterion*` types, `select_version`, and the elimination-projection mechanics
(printer/reference-mapping/reader, `SetVersionCriterionOperation`) all check out against
`source/versioning/VersioningDocument.jl` and `VersioningToAny.jl`.

| where | category | finding | evidence | fix | confidence |
|---|---|---|---|---|---|
| line 20 | WRONG / LINK | Link `[package/versioning/main/Versioning.jl](../../../source/versioning/Versioning.jl)` — `source/versioning/Versioning.jl` does not exist. The real file holding the document types is `VersioningDocument.jl`. | `ls source/versioning/` → `VersioningDocument.jl VersioningModule.jl VersioningToAny.jl`. | Fix the link/filename. | checked |
| line 61 | (verified correct) | `source/versioning/VersioningToAny.jl` — correct, exists. | — | — | checked |
| line 98 | STALE / WRONG | "Tests: `test/projection/VersioningToAnyTest.jl`" — wrong path. The real path is `test/substrate/projection/VersioningToAnyTest.jl`. | `find test -iname "VersioningToAnyTest.jl"` → `test/substrate/projection/VersioningToAnyTest.jl`. | Fix the path. | checked |
| line 12-13 | (verified correct) | The clipboard cross-reference links (`source/clipboard/Clipboard.jl`, `source/clipboard/ClipboardSliceToAny.jl`) both resolve to real files. | `ls source/clipboard/`. | — | checked |

---

## Cross-cutting observations (not tied to one file)

- **Domain packages with no guide at all.** Comparing `ls source/` (63 slices) against
  `documentation/package/` (22 folders with guides), roughly 40 slices have no guide, including
  every one the brief named as an example:

  | slice | what it holds (from its module docstring) | size (`wc -l *.jl`, tail) |
  |---|---|---|
  | `markdown` | Blocks (headings, paragraphs, code blocks, quotes, lists) and inlines (text, code, emphasis, strong, link, image). | 1289 |
  | `yaml` | YAML domain — a JSON superset; scalars, block/flow sequences, ordered mappings. | 758 |
  | `julia` | A Julia AST as reactive Documents — leaves, expressions, statements. | 2504 |
  | `sql` | SQL statement document model (ANSI/PostgreSQL); `SqlToSyntax` renders, `SqlToCellTable` executes against a `DatabaseInstance`. | 3455 |
  | `database` | Generic, dependency-free database access layer: `DatabaseAdapter` interface + `RawDatabaseResult`. | 236 |
  | `dbcatalog` | PostgreSQL catalog tree: `DbCatalogRdbms → Database → Schema → Table → Column`. | 551 |
  | `odbc` | Concrete `DatabaseAdapter` over `ODBC`/`DBInterface`. | 513 |
  | `filesystem` | `FileSystemFile` / `FileSystemDirectory`, identity by `pathname`. | 461 |
  | `formula` | Named, cross-referencing, evaluated formulas (a generalized spreadsheet); `result` is a reactive Cell. | 1102 |
  | `book` | Structured prose: books, chapters, paragraphs, lists, pictures. | 750 |
  | `component` | Higher-level UI building blocks composed from widget primitives. | 76 |
  | `tulip` | LP-backed `ConstraintSolver` (`TulipConstraintSolver`) for the graph layout engines. | 223 |

  `sql` (3455 lines) and `julia` (2504 lines) are the largest completely undocumented domains in
  the repository — both larger than every domain that *does* have a guide except `rst`. This is
  a bigger gap than anything found inside the twelve assigned files.

- **A recurring, systemic error: `package/<slice>/main/` paths.** Three of the twelve guides
  (`fsm.md`, `process.md`, and `rst.md`'s fixture path) cite a `package/<name>/main/` or
  `package/projectured/...` location that does not match the repository's actual layout
  (`source/<slice>/` for code, `package/Projectured<Name>/src/` for the thin include-list
  package). This looks like a leftover from an earlier repository layout, predating the
  `source/`/`package/` split CLAUDE.md now documents, and is worth a repo-wide grep across all
  documentation before the rewrite, not just a per-file fix.

- **The AI assistant is the least-documented major subsystem, despite being the centerpiece of
  the new framing.** `source/assistant/` (1,407 lines) has zero coverage anywhere in
  `documentation/`. `source/pane/` (the generic, actively-developed tab/split/duplicate/Alt-click
  system that several `plan/pending/` documents are building out) has its own guide
  (`documentation/package/pane/pane.md`, not in this survey's assignment) but `workbench.md` does
  not link to it or explain the relationship. Both gaps sit directly on the path the rewrite
  needs for its Reddit/Discourse pitch.

---

## Best demo per domain (for the Reddit/Discourse rewrite)

All example names below are verified present in
`example/projectured/DomainExamples.jl`'s `domain_examples`/const list (or, where noted, kept
deliberately out of the enumeration registry but directly runnable).

| Guide | Best demo | Example name | Why |
|---|---|---|---|
| json.md | Round-trip JSON editing | `json_example` (`run_example("json")`) | Familiar format, but the least visually distinctive of the twelve — a fallback, not a showpiece. |
| xml.md | XML with attributes | `xml_example` | Similar to json; attribute-as-document is a real differentiator but subtle to show in a screenshot. |
| rst.md | Rendered documentation page | `rst_rendered_example` (`:rendered` style) | Turns raw markup into large bold titles, colored role chips, and an actual figure — the "natural notation" story is immediately visible, and it is proven against a real 349-file corpus. |
| fsm.md | Live FSM diagram | `fsm_diagram_example` | A state machine as a picture with live transitions is the single most recognizable "this isn't just a text editor" image in the whole repository. |
| process.md | Flowchart with live debugging | `process_diagram_example` | Direct embodiment of the new framing: a real, runnable procedure, shown as a diagram, steppable with breakpoints — this is the strongest "AI-editable live system" story of any domain surveyed. |
| graph-layout.md | Any graph-shaped domain (this slice has no document of its own) | `graph_example` | Shows the layout pipeline itself; less of a headline demo on its own. |
| math.md | Two-dimensional formula typesetting | `math_display_example` (kept out of the `examples` registry deliberately — run directly with `run_example(math_display_example)`) | Real math rendering (fractions, radicals, scripts) with no LaTeX and no external renderer is visually striking and unusual for a Julia tool. |
| chart.md | Native interactive chart | `chart_example` or `chart_strip_example` | Charts with zoom/pan/rubber-band/crosshair, vector, no plotting library — a strong, immediately legible demo; `chart_strip_example` is the most unusual (OMNeT++-style state-strip visualization) if a "look what else this can do" angle is wanted. |
| sequencechart.md | Request trace across services | `sequencechart_example` | A distributed-system sequence chart with causal navigation (`Ctrl+←`/`Ctrl+→` "follow the arrow") reads immediately as a debugging tool, not a toy. |
| workbench.md | The full IDE shell | `workbench_example` (1285px screenshot already exists at `asset/image/example/workbench.png`) | The largest, most complete "this is a real application" demonstration — panes, navigator, console, evaluator all at once. |
| conversation/transcript.md | The AI assistant pane itself | `assistant_example` (`render_width=1600, render_height=1000`) | Directly demonstrates the new framing's central claim — the assistant embedded in, and acting on, the live editor. This is the one the rewrite should lead with if the goal is to show "AI integration from the ground up." |
| versioning.md | Multiple versions of one JSON object | `versioning_example` (kept out of the registry; run directly) | Real but low-drama feature; not a strong visual demo — better shown as a short GIF of switching criteria than a static screenshot. |

---

## Top findings of this area (most important first)

1. **`source/assistant/` (1,407 lines) has no documentation anywhere in the repository** — the
   one subsystem that most directly embodies the new "AI integration from the ground up" framing
   is invisible to both readers and the assistant's own resource catalog. (conversation/transcript.md)
2. **`workbench.md` documents a stale slice boundary**: it claims `Assistant` subtypes
   `WorkbenchDocument` and cites a projection, `WorkbenchAssistantToWidgetSplitPane`, that does
   not exist (the real name is `AssistantToWidgetSplitPane`, in the separate `source/assistant/`
   slice). Source comments confirm the extraction happened and the guide was never updated.
3. **`workbench.md` never mentions `source/pane/`**, a second, general, and actively-developed
   tab/split-pane system with its own guide (`documentation/package/pane/pane.md`) and several
   `plan/pending/` features (duplicate a pane, Alt+click select any widget, split-pane
   drag/resize) — exactly the features the survey brief asked about, several of which are **not
   yet shipped**.
4. **`workbench.md`'s `WorkbenchEditor` constructor is wrong**: documented as
   `WorkbenchEditor(title, filename, content)`, actually `WorkbenchEditor(content; title="",
   filename="", follow_end=false)` — wrong argument order, wrong arity (a `follow_end` field is
   missing entirely).
5. **`xml.md`'s own example code does not run**: `push!(elem, XmlText(...))` has no matching
   method for `XmlElement` anywhere in the source tree.
6. **A recurring stale-path pattern**: `fsm.md` and `process.md` both cite a
   `package/<slice>/main/` location that does not exist (real code is in `source/<slice>/`);
   `rst.md`'s fixture path and `versioning.md`'s test path have the same class of error. Worth a
   repository-wide sweep, not per-file patches.
7. **`rst.md` has an internal count error**: states "twelve typed [directive] structs" twice but
   names only eleven, and cites three registration function names
   (`natural_syntax_projection`/`natural_extension`/`parse_natural`) that do not exist (real:
   `register_natural_syntax!`, `register_natural_domain!`, `register_file_document_type!`).
8. **`math.md` and `chart.md` each cite one file that does not exist**
   (`source/math/Math.jl` → real file `MathDocument.jl`; `chart/Chart.jl` → real file
   `ChartDocument.jl`), both as the target of a markdown link.
9. **`fsm.md`'s cited design plan is stale**: linked as `plan/pending/state-machine-domain.md`,
   actually completed and moved to `plan/done/state-machine-domain.md`.
10. **`sql` (3,455 lines) and `julia` (2,504 lines) are the largest undocumented domains in the
    repository** — bigger than every domain that has a guide except `rst`. Neither is in this
    survey's file list, but both are visible from `source/` and worth flagging for the rewrite's
    scope.
11. **json.md and xml.md never name a single implementation file** (parser, file wrapper, or
    projection) — both are document-model-only references, silent on how a `.json`/`.xml` file
    actually gets read, written, or rendered.
12. **`fsm.md` and `process.md` already model the target framing well** ("a component projects to
    complete, runnable Julia code"; "still be real, runnable code, debuggable in the editor while
    it runs") — good source language to reuse rather than discard in the rewrite.

---

# G2 — Substrate and tooling guides

Area: the guides that every view is built from — `documentation/package/README.md`,
`text/text.md`, `syntax/syntax.md`, `graphics/graphics.md`, `widget/widget.md`,
`pane/pane.md`, `collection/collection.md`, `reflection/bounded-sync.md`,
`adaptagrams/README.md`, `executable/README.md`. Checked statically against
`source/`, `test/`, `example/`, `package/` — no Julia was run.

---

## documentation/package/README.md

**Verdict:** UPDATE (small but real: it contains history text the project rule forbids).
**Audience:** contributor to this repository (it explains the doc layout convention).
**Size:** 17 lines.

| where | category | finding | evidence | fix | confidence |
|---|---|---|---|---|---|
| "They lived beside the code as `package/<slice>/doc/` until the repository tree moved prose out of `package/`…" | HISTORY | Describes the previous location of guides and the move that happened, not the current state. | `plan/done/repository-tree.md` exists, confirming this is closed history. | Drop the "lived… until… moved" clause; state only "guides live in `documentation/package/`, one folder per slice; `package/<slice>/` holds only a name and an include list." | checked |
| "kernel/cell and widget/widget do not collide" | CODE-REFERENCE | Claim that the editor's own documentation tool looks guides up by `<slice>/<file>`. | `source/kernel/tool/Documentation.jl:19` — comment: `` `widget/widget`, … so two slices may both have a guide of one name.`` | none — claim holds | checked |
| general | MISSING | The README does not mention that `package/visual/doc/widget.md` (the pre-move path) is still hard-coded in five source comments, which is exactly the "a move breaks the code" risk this file exists to describe. | `source/layout/LayoutToGraphics.jl:312,1479`, `source/widget/WidgetToGraphics.jl:1900,2730`, `test/substrate/projection/ProjectionConfiguringTest.jl:127` all say `package/visual/doc/widget.md` | Worth a one-line warning in this README, or a follow-up cleanup task, since the move already happened and these comments were not updated. | checked |

**Framing:** no editor-only language; the file is purely about doc organization. Nothing to change for the new framing.

---

## documentation/package/text/text.md

**Verdict:** UPDATE (one central claim is now false; the rest holds).
**Audience:** Julia developer using the domain as a library; contributor.
**Size:** 104 lines.

| where | category | finding | evidence | fix | confidence |
|---|---|---|---|---|---|
| header link `[source/text/Text.jl](../../../source/text/Text.jl)` | LINK | File does not exist. The text document module is split into `TextDocument.jl` (types + `@gestures TextBlock`), `TextToGraphics.jl`, `TextToString.jl`, etc. — there never was a single `Text.jl`. | `ls source/text/` has no `Text.jl`; `find` confirms zero `text/Text.jl` references anywhere else in the repo. | Link to `source/text/TextDocument.jl`. | checked |
| "TextLine… **Not laid out by `TextToGraphics` yet.**… the graphics pipeline addresses spans by a flat `Int` element index (`SegmentCoordinate.span_idx`)… Nothing emits a `TextLine` yet, so nothing hits this." | WRONG | This is now false. `TextToGraphics.jl`'s own header comment says it "breaks the line at a `TextLine` element"; `SegmentCoordinate` carries `span_path::SpanPath` (`SpanPath = Vector{Int}`, `TextDocument.jl:280`), documented as `[i]` for a top-level span and `[i, j]` for span `j` of a `TextLine` — i.e. exactly the line-aware addressing the guide says does not exist. There is no field named `span_idx` anywhere in the file. | `source/text/TextToGraphics.jl:1-30` (docstring + `SegmentCoordinate` struct), `source/text/TextDocument.jl:280` | Rewrite the whole "Not laid out…" paragraph: `TextLine` is laid out by `TextToGraphics`, addressed via `SegmentCoordinate.span_path::SpanPath` (`[i]` / `[i,j]`), not a flat `span_idx`. | checked |
| `read_gesture(::TextBlock, gesture)` … `[text/Text.jl]` | CODE-REFERENCE | Same broken path as above; also the mechanism is now a reified `@gestures TextBlock begin … end` table (`TextDocument.jl:353`), not a hand-written `read_gesture` method — the *effect* the guide describes is right, the *shape* of the code is stale. | `source/text/TextDocument.jl:353` | Point at `TextDocument.jl` and say "a reified `@gestures TextBlock` table" to match how syntax.md and pane.md already describe their own gesture tables. | checked |
| Styling Fields / Selection / Key Features sections | — | `TextString`, `TextNewline`, `TextSpacing`, `TextGraphics`, `TextBlock`, `TextLine` all exist with the claimed fields (`content`, `font`, `font_color`, `fill_color`, `line_color`, `padding` as `Cell`s). | `source/text/TextDocument.jl:59,89,125,186,215,250` | none — claim holds | checked |
| `ToggleCollapseOperation` (Ctrl+.) | — | Type exists and is used across ten files including `TextDocument.jl` and `SyntaxToText.jl`. | `grep -rln ToggleCollapseOperation source/` (10 hits) | none | checked |

**Framing:** no "only an editor" language. The domain description ("bridges structural and visual domains") is already neutral and reusable as-is.

---

## documentation/package/syntax/syntax.md

**Verdict:** REWRITE (the Types section describes roughly a third of the current type hierarchy; a reader who trusts it will not know four widely-used types exist).
**Audience:** Julia developer using the domain as a library; contributor.
**Size:** 117 lines.

| where | category | finding | evidence | fix | confidence |
|---|---|---|---|---|---|
| header link `[source/syntax/Syntax.jl](../../../source/syntax/Syntax.jl)` | LINK | No such file; the syntax types live in `SyntaxDocument.jl`. | `ls source/syntax/` — no `Syntax.jl` | Link to `SyntaxDocument.jl`. | checked |
| "## Types — SyntaxLeaf … SyntaxNode" | MISSING | The guide names only two of nine current syntax document types. `SyntaxDocument.jl` now declares an abstract hierarchy (`SyntaxDocument` → `SyntaxCompound` → `SyntaxSequence`/`SyntaxWrapper`) and four wrapper types the guide never mentions: `SyntaxDelimitation` (adds open/close delimiters to any document), `SyntaxIndentation` (adds a pretty-print level), `SyntaxCollapsible` (adds a fold state), `SyntaxNavigation` (marks a caret landing point) — plus two more sequence types, `SyntaxConcatenation` and `SyntaxSeparation`, and `SyntaxInsertion` (the insertion-kit placeholder). | `source/syntax/SyntaxDocument.jl:5-263, 286-349` (full docstrings for each) | Add a section covering the `SyntaxCompound`/`SyntaxSequence`/`SyntaxWrapper` split and all seven compound types, not just the two combined-field ones. | checked |
| "Collapsed and indentation fields — Both `SyntaxLeaf` and `SyntaxNode` carry: `indentation::Int`, `collapsed::Bool`" | STALE | True for those two types (still direct fields, `SyntaxDocument.jl:431-437,498-505`), but now those same properties are *also* available on any other compound via the `SyntaxCollapsible`/`SyntaxIndentation` wrappers, which the guide does not mention. A reader following only this file would keep reaching for fields that do not exist on, say, a `SyntaxConcatenation`. | `source/syntax/SyntaxDocument.jl:120-138` (the `get_opening_delimiter`/`get_indentation`/`is_syntax_collapsed`/`is_syntax_collapsible` generic contract, answered per-type) | Explain the contract functions (`get_indentation`, `is_syntax_collapsed`, `is_syntax_collapsible`, `get_opening_delimiter`, `get_closing_delimiter`, `get_separator`) as the real interface, with `SyntaxLeaf`/`SyntaxNode` as the two types that answer all of them directly. | checked |
| "Gesture mapping — `read_gesture(::SyntaxNode, gesture)` ([syntax/Syntax.jl])" | WRONG + LINK | Two problems: the file link is dead (see above), and the mechanism is not a `read_gesture(::SyntaxNode, …)` method — it is a reified `@gestures SyntaxCompound begin … end` table (`SyntaxDocument.jl:625`) plus a separate `@gestures SyntaxLeaf begin … end` table (`:816`). Registering on `SyntaxCompound` (the abstract supertype) is deliberate — the code comment says it covers "every interior node there is or will be", i.e. the new wrapper types get tree navigation for free, which the guide's `SyntaxNode`-only framing hides. | `source/syntax/SyntaxDocument.jl:590-644, 809-825` | Rewrite to describe the two `@gestures` tables and that registering on `SyntaxCompound` is what makes the wrapper types navigable without their own table. | checked |
| `ObjectFieldToSyntax`, `ObjectNodeToSyntaxNode`, `ObjectToSyntax`, `CellToSyntax` | — | All exist as described, in `ObjectFieldToSyntax.jl` / `ObjectToSyntax.jl`. | `source/syntax/ObjectFieldToSyntax.jl:33`, `source/syntax/ObjectToSyntax.jl:92,130` | none | checked |
| "`SyntaxCompoundToText` delegates to this" | — | `struct SyntaxCompoundToText <: Projection` exists (`SyntaxToText.jl:234`). | checked | none | checked |

**Framing:** neutral, no changes needed for the new framing beyond normal accuracy fixes.

---

## documentation/package/graphics/graphics.md

**Verdict:** KEEP (small fixes only — this is the most accurate file in the set).
**Audience:** Julia developer using the domain as a library.
**Size:** 161 lines.

| where | category | finding | evidence | fix | confidence |
|---|---|---|---|---|---|
| "## Types — GraphicsText, GraphicsRect, GraphicsCanvas" | MISSING | Lists 3 of 8 current graphics document types. `GraphicsLine`, `GraphicsCircle`, `GraphicsPolyline`, `GraphicsPolygon`, `GraphicsViewport`, `GraphicsImage` all exist and are used elsewhere in this same file's prose (widget.md leans on `GraphicsLine`/`GraphicsCircle` for anti-aliased rendering) and in widget.md's icon table (`GraphicsPolyline`/`Circle`/`Polygon` for vector icons). | `source/graphics/GraphicsDocument.jl:34,66,115,148,183,219,380,419,445` | Extend the Types table to the full 8, or explicitly scope this file to "the three most common" the way collection.md scopes itself. | checked |
| write_image / write_pdf / GraphicsCanvasToImageFile / GraphicsCanvasToPdfFile / pdf_measure_text / measure_sdl_text | — | All exist with the described call shapes. | `source/sdl/Sdl.jl`, `source/pdf/Pdf.jl`, `source/pdf/PdfBackendModule.jl`, `source/style/TrueType.jl`, `source/text/TextToGraphics.jl` | none | checked |
| link `[devices and backends guide](../kernel/devices-and-backends.md#web-backend)` | LINK | Target file exists. | `documentation/package/kernel/devices-and-backends.md` | none | checked |
| "TrueType (`.ttf`) outline fonts only — CFF/`.otf` embedding (`Inconsolata.otf`) is not yet implemented" | — | Still true: `source/style/TrueType.jl` explicitly special-cases "a CFF font has no `glyf` table" as a fallback path, and `font_inconsolata_regular_18` (an `.otf`) is a real registered font, so the limitation is live, not theoretical. | `source/style/Font.jl:126`, `source/style/TrueType.jl:53-54,177,191` | none | checked |

**Framing:** neutral. This file already reads well against the new "view of any data" framing (it is about the rendering substrate, not "the editor").

---

## documentation/package/widget/widget.md

**Verdict:** UPDATE (large surface, and the widget count/list is stale, but no structural rewrite needed — most of the 700+ lines check out).
**Audience:** Julia developer building a UI on the widget layer; contributor.
**Size:** 731 lines / ~5700 words.

### Widget inventory check

`grep -c "struct Widget" source/widget/*.jl` and the exported list in `source/widget/WidgetModule.jl:82` agree on **42** `WidgetDocument` subtypes (plus two non-document sub-node types, `WidgetTreeNode` and `WidgetAccordionItem`). The guide's own tally — "The real factory maps all 33 widget types: the 15 core widgets above, the `WidgetInsertion` placeholder, and the 17 extension widgets" — is stale by 9 types.

| where | category | finding | evidence | fix | confidence |
|---|---|---|---|---|---|
| "WidgetLazyTable" | — | Confirmed absent from source and from this guide — the guide never mentions it, so there is nothing to fix here (the brief's example check came back clean). | `grep -rn WidgetLazyTable source/ documentation/ test/ example/` → no hits | none | checked |
| widget count, "33 widget types" | STALE | Actual exported `WidgetDocument` count is 42. Not mentioned anywhere: `WidgetTabPage` (the tab-strip's own pane-holding type, used throughout `WidgetTabbedPane`), `WidgetOption` (the dropdown-item type `WidgetSelect` builds its menu from). `WidgetContextMenu`, `WidgetDialog`, `WidgetStatusBar` *are* covered, but only in prose subsections, not in the leaf/compound/extension tables, so the "33" tally undercounts even by the guide's own accounting method. | `source/widget/WidgetModule.jl:82` (export list), `source/widget/WidgetDocument.jl:1168` (`WidgetTabPage`), `:1968` (`WidgetOption`) | Rebuild the widget tables from the export list; add `WidgetTabPage` and `WidgetOption` as rows (or explain why they are sub-node types like `WidgetTreeNode`, if that is the intended framing); drop the "33" count or recompute it. | checked |
| "one table widget… rows are a `CellVector` or a `ListNode`" | — | Confirmed: exactly one `@document struct WidgetTable`, and its `rows::Any` field's own doc-comment reads "CellVector of rows, or a ListNode of them". | `source/widget/WidgetDocument.jl:2115-2130` | none | checked |
| Cards / collapsible cards | — | `WidgetCard` fields (`title`, `description`, `content`, `footer`, `variant`, `collapsible`, `padding`, plus `width`/`height`) all match; the doc's height semantics ("`height=0` is content-tall… positive height is fixed, enabling a scroll pane inside") match the docstring exactly. | `source/widget/WidgetDocument.jl:1552-1591` | none | checked |
| Scroll / split / tabbed panes | — | Field lists (`content`/`scroll_position`, `orientation`/`elements`/`sizes`, `selector_element_pairs`/`tab_scroll`/`closable`/`new_tab`/`draggable`) all match the struct definitions. | `source/widget/WidgetDocument.jl:1120-1135, 1211-1225, 1285-1300` | none | checked |
| `WidgetTheme` padding/tokens | — | `background, foreground, card, muted, primary, destructive, border, input, ring, radius` are all real fields of `struct WidgetTheme` (plus many more the guide elides with "…", which is accurate — the real struct has ~30 fields across palette/spacing/box-model/text-style groups). | `source/widget/WidgetToGraphics.jl:60-104` | none | checked |
| "previously expressible only as a one-column table" (WidgetList) | HISTORY | Small instance of history language — describes what a one-column list used to require before `WidgetList` existed. | `widget.md:190` | Drop "previously expressible only as a one-column table"; state what `WidgetList` is, not what it replaced. | checked |
| "first-class" (×3: `WidgetList`, `MouseEnter`/`MouseLeave` ×2) | STYLE | Marketing/AI-slop word the language rules ban. | `widget.md:189,467` (and one more nearby) | Replace with a plain description, e.g. "a dedicated single-column list type" / "synthesized pointer gestures". | checked |
| Actions, icons, popups, transform pane, hosting controls, splitter drag, strip reports sections | — | Spot-checked function/type names: `Action`, `Shortcut`, `register_icon!`, `make_glyph_icon`, `make_image_icon`, `WidgetToolButton`, `WidgetMessageBox`, `WidgetInputDialog`, `OpenPopupOperation`, `WidgetPopupResolverProjection`, `get_anchor_point`, `WidgetTransformPane`, `compute_affine_inverse` all exist with matching call shapes. | `source/widget/WidgetDocument.jl:442-448,586,598`; `source/widget/WidgetPopupResolver.jl:18` | none | checked |
| Example/test names cited (`make_widget_popup_*_example`, `WidgetPopupExampleTest`, `WidgetActionTest`, `WidgetIconTest`, `make_widget_shell_document_example`, `make_widget_document_example`) | — | All exist as files/functions. | `test/substrate/projection/WidgetPopupExampleTest.jl`, `WidgetActionTest.jl`, `WidgetIconTest.jl`; `example/substrate/WidgetDocumentExample.jl` | none | checked |
| Link text `[visual/example/document/Widget.jl]` (href `../../../example/substrate/document/Widget.jl`) | STALE | The link *target* is correct, but the visible link text still says `visual/example/…`, a path from before the tree was flattened out of a `visual/` top-level grouping. Corroborated repo-wide: `source/layout/LayoutToGraphics.jl` and `source/widget/WidgetToGraphics.jl` still say `package/visual/doc/widget.md` in five comments. | `widget.md:181`; `grep -rn "package/visual/doc/widget.md" source/` (5 hits) | Fix the link text to match its href. | checked |

**Framing:** the one explicit reflection/on-demand-UI mechanism in this file — `ObjectToWidget` ("A form of object fields") — is exactly the kind of feature the new framing wants to foreground, but the guide frames it purely as a forms feature ("`ObjectToWidget` reflects **one** object into a fixed two-column grid…") with no link to the AI-assistant or reflection story. See the reflection section below — this is the *second* of two separate reflection-to-widget paths in the codebase, and neither doc mentions the other.

---

## documentation/package/pane/pane.md

**Verdict:** KEEP (matches source and recent history closely; this is a well-maintained file).
**Audience:** contributor / Julia developer building on the workbench.
**Size:** 277 lines.

| where | category | finding | evidence | fix | confidence |
|---|---|---|---|---|---|
| `PaneTab`, `PaneGroup`, `PaneSplit`, `PaneTree` | — | All four exist in `PaneDocument.jl` with the claimed constructors. | `source/pane/PaneDocument.jl:26,85,110,143` | none | checked |
| `PaneSurgery.jl`, `PaneGeometry.jl`, `PaneGestures.jl` file references | — | All three files exist, matching the referenced function names (`get_pane_rectangles`, `get_pane_split_axis`, `@gestures PaneTree`). | `ls source/pane/`; `source/pane/PaneDocument.jl:208`; `source/pane/PaneToWidget.jl:264` | none | checked |
| "`PaneToWidget()` is the first of two stages" | — | Confirmed: `PaneToWidget(; new_tab = default_new_pane_tab)` is a real factory function returning a `TypeDispatchingProjection`, distinct from the underlying `PaneTreeToWidget`/`PaneSplitToWidgetSplitPane`/`PaneGroupToWidgetTabbedPane` projection structs. | `source/pane/PaneToWidget.jl:618-630` | none | checked |
| Test names `test_pane_surgery`, `test_pane_geometry`, `test_pane_to_widget`, `test_pane_reader`, `test_pane_gestures`, `test_pane_drag`, `test_pane_rename`, `test_pane_construct` | — | All correspond to real test files under `test/substrate/{editor,document,projection}/`. | `test/substrate/editor/PaneConstructTest.jl`, `test/substrate/projection/Pane{Geometry,ToWidget,Reader,Gesture,Drag,Rename}Test.jl` | none | checked |
| package path `[package/pane/main/]` | LINK (minor) | The link target resolves (`package/ProjecturedPane/`), but the visible text `package/pane/main/` uses the pre-move naming (`pane/main` vs the actual `ProjecturedPane`). Low-impact since the href is separately correct-looking in context, but inconsistent with the rest of the guide's `source/pane/…` style. | `pane.md:7` | Reword to avoid a package-path spelling that does not exist (`package/pane/main/` is not a real path — the real package dir is `package/ProjecturedPane/`). | checked |
| git history since 2026-08-01 | — | 30+ commits, mostly a systematic naming/structure pass (module-per-file, verb-first renames) rather than behavior changes; the guide's descriptions of drag-to-resize, drop bands, focus-as-selection etc. read as current, matching commit subjects like "A click in a pane's content reaches the document the tab holds" and "A split pane takes no inset, because it draws no chrome". | `git log --oneline --since=2026-08-01 -- source/pane` | none | checked |

**Framing:** neutral; no editor-only language beyond normal domain description.

---

## documentation/package/collection/collection.md

**Verdict:** KEEP (accurate; only a stale package-path phrase).
**Audience:** Julia developer using the domain as a library; contributor.
**Size:** 183 lines.

| where | category | finding | evidence | fix | confidence |
|---|---|---|---|---|---|
| `CellVector`, `CellMatrix`, `CellTable`, `ListNode`, `const CollectionDocument = Union{…}` | — | All match exactly, including the union definition. | `source/collection/CollectionDocument.jl:4`, `CellVector.jl:12`, `CellTable.jl:6`, `CellMatrix.jl:6`, `ListNode.jl:5` | none | checked |
| `child_reference_steps(::CellVector)` registered on `OperationModule` | — | Confirmed via the module's own import line. | `source/collection/CollectionModule.jl:31`; `source/kernel/operation/Operations.jl:355-364` | none | checked |
| `ComputedCellVector(f)`, `get_left_tail`, `get_right_tail`, `take_first`, `Base.IteratorSize(ListNode) = SizeUnknown()` | — | All present with matching signatures. | `source/collection/CellVector.jl:75`, `ListNode.jl:67,74,80,91,105` | none | checked |
| link `[architecture.md](../kernel/architecture.md)` | LINK | Resolves (`documentation/package/kernel/architecture.md` exists), but note this is a *different* file from `documentation/design/system-anatomy.md`, which this same guide's own header calls "architecture.md" informally at the top of most other files in this area — worth normalizing the two names in the rewrite so "architecture.md" unambiguously means one file. | `documentation/package/kernel/architecture.md` vs `documentation/design/system-anatomy.md` | Not broken, but a naming collision risk across the doc set; flag for the rewrite's cross-reference pass. | checked |
| "`ScreenDocument` lives in `visual/screen/`" | WRONG | No `visual/` top-level directory exists; the real path is `source/screen/`. | `ls source/` has `screen/`, not `visual/screen/`; `ls .` has no `visual/` at all | Fix to `source/screen/`. | checked |
| `[devices-and-backends.md](../kernel/devices-and-backends.md)` | LINK | Resolves. | `documentation/package/kernel/devices-and-backends.md` | none | checked |

**Framing:** neutral.

---

## documentation/package/reflection/bounded-sync.md

**Verdict:** UPDATE (the mechanism it documents is exactly the load-bearing piece of the new "on-demand" framing, but the file itself carries banned history language, and its cross-reference to the widget layer is wrong).
**Audience:** contributor / Julia developer; also a strong candidate resource for the AI assistant, since it explains reflection.
**Size:** 177 lines.

### The reflection mechanism (brief's specific question)

There are **two separate, non-cross-referencing** mechanisms in the codebase that turn a plain Julia value into an editable widget view, and this file documents only one of them:

1. **`DocumentReflection.jl`** (`source/reflection/`, package `ProjecturedReflection`) — `reflect_document(object, policy)` walks *any* Julia struct (not just a `Document`) into a `ReflectedNode` tree (`label`/`kind`/`value`/`children`), bounded by the same `DepthPolicy`/`UnsyncedDocument` marker machinery `bounded-sync.md` describes for `sync_document!`. `sync_reflection!` re-syncs it in place. `ReflectionToWidget` (also `source/reflection/`) then renders a `ReflectedNode` tree as a `WidgetTree`, translating chevron clicks into `request_sync!`/collapse writes on the shadow. This is the general, structural "look at any live object" path — this is the one **bounded-sync.md documents**, in the "Reflecting a plain object" and "Rendering it" sections (lines 95-139).
2. **`ObjectToWidget`** (`source/widget/ObjectToWidget.jl`, package `ProjecturedWidget`) — a *different* reflection-driven projection: it walks one object's own `Cell` fields into an editable 2-column form (checkbox/text controls wired back to the object's cells via `ReplaceReferencedValueOperation`), with nested structs/vectors folded into collapsible cards. This is documented only in **widget.md** ("A form of object fields", lines 215-276), with no mention of `DocumentReflection`/`ReflectedNode` at all.

Neither file cross-references the other, and no third document unifies them (`documentation/design/system-anatomy.md`'s module table gives `reflection` one line: "BoundedSync and DocumentReflection" — it does not mention `ObjectToWidget` lives in a different package and does a related but distinct job). For the rewrite's "any value gets an editable view when someone asks for it" framing, this split is worth resolving explicitly: one path is "inspect any Julia object read-mostly, expand on demand" (reflection slice), the other is "edit one object's own fields as a form" (widget slice's `ObjectToWidget`).

| where | category | finding | evidence | fix | confidence |
|---|---|---|---|---|---|
| "`ReflectionToWidget` (in the visual package) renders a `ReflectedNode` tree…" | WRONG | `ReflectionToWidget` lives in `source/reflection/ReflectionToWidget.jl`, package `ProjecturedReflection` — there is no "visual package" (no `visual/` directory exists anywhere in the repo). | `package/ProjecturedReflection/src/ProjecturedReflection.jl`; `find package -iname "*Reflection*"` | Fix to "in this package" or name `ProjecturedReflection` explicitly. | checked |
| "An earlier version put a second, bounded walk in `BoundedSync.jl` beside the sealed one… Folding the bound in removed ~150 lines from this package and that violation with them." (final paragraph, "Where the walk lives") | HISTORY | Explicitly describes a prior implementation and a refactor that happened — the whole paragraph is written in the past tense about what the file *used to* contain, which the project's own commenting rule forbids in source and, by the same logic used throughout this repo's other guides, in documentation prose describing current architecture. | `bounded-sync.md:171-177` | Drop the paragraph, or keep only the forward-looking constraint it implies ("the marker type and depth rule stay in this package; the kernel is not allowed to import them") without the "an earlier version..." narrative. | checked |
| `UnsyncedDocument`, `request_sync!`, `make_unsynced_marker`, `SyncPolicy`, `DepthPolicy`, `is_descendable_for_sync`, `sync_element_limit`, `make_unsynced_placeholder`, `HiddenElements`, `copy_document(kind, doc, policy)`, `sync_document!(shadow, source, policy, depth)` | — | All confirmed present with matching signatures in `source/reflection/BoundedSync.jl`. | `source/reflection/BoundedSync.jl:5-9,26-27,40,62-92,107-185` | none | checked |
| "That mistake cost 162 KB per sync in the first version" | — | Concrete, falsifiable-looking number; could not verify or refute statically (would need a profiling run). Kept as a plausible fact but flagged since it reads as another history reference ("in the first version") bundled with a specific claim. | — | If kept, drop "in the first version" (history) and state it as a standing constraint: "materialising all children to show the first eight costs proportionally to the whole, not the shown slice." | likely |
| `ReflectedNode` fields (`label`, `kind`, `value`, `children`) | — | Match `DocumentReflection.jl:35` exactly. | `source/reflection/DocumentReflection.jl:35` | none | checked |

**Framing:** this file is the single best-aligned document in the whole area for the new "on-demand user interface" story — "The walk stops at a bound and leaves a marker where it stopped; a consumer that wants more flags the marker" is precisely the mechanism a rewrite would want to lead with. It is currently filed as a narrow technical note under `reflection/`, not connected to any top-level "what ProjecturEd is" narrative. Recommend the rewrite plan treat this file as a primary source, not a footnote, once its history paragraph and wrong package reference are fixed.

---

## documentation/package/adaptagrams/README.md

**Verdict:** KEEP.
**Audience:** Julia developer wanting graph layout with libcola/libavoid; contributor.
**Size:** 62 lines.

| where | category | finding | evidence | fix | confidence |
|---|---|---|---|---|---|
| `AdaptagramsLayout`, `GraphLayoutEngine`, `GridEmbedding`, `layout_graph` | — | All exist exactly as described: `AdaptagramsLayout <: GraphLayoutEngine` in `source/adaptagrams/Adaptagrams.jl:80`; `GraphLayoutEngine`/`GridEmbedding`/`layout_graph` in `source/graph/GraphLayoutEngine.jl:39,334,427`. | as cited | none | checked |
| `deps/adaptagrams_shim.cpp`, `deps/build.jl`, `ADAPTAGRAMS_DIR`, pkg-config-then-env-var resolution order | — | All confirmed in `package/ProjecturedAdaptagrams/deps/`. | `package/ProjecturedAdaptagrams/deps/build.jl` (pkg-config path then `ADAPTAGRAMS_DIR` fallback), `adaptagrams_shim.cpp` present | none | checked |
| `AdaptagramsLayout(; ideal_length=60.0, avoid_overlaps=true, orthogonal=false)` | STALE (minor) | The constructor now also takes `node_margin::Union{Nothing,Real}=nothing` as a fourth keyword; the guide's example omits it. Not wrong, just incomplete. | `source/adaptagrams/Adaptagrams.jl:86-88` | Add `node_margin` to the shown signature, or note "and more — see the docstring". | checked |
| `make_graph_projection_example(engine = AdaptagramsLayout())` | — | Function exists and takes an `engine` keyword. | `example/graph/GraphProjectionExample.jl:10` | none | checked |

**Framing:** neutral, purely mechanical setup instructions — fine as-is for any audience.

---

## documentation/package/executable/README.md

**Verdict:** UPDATE (the "Project structure" tree is a leftover from the pre-move layout, and `BuildSpec`'s options table is missing two real fields; the narrative and code examples are otherwise accurate).
**Audience:** Julia developer building a standalone binary; contributor.
**Size:** 105 lines.

| where | category | finding | evidence | fix | confidence |
|---|---|---|---|---|---|
| "## Project structure" tree (`executable/builder/…Project.toml…ProjecturedBuilder.jl`, `executable/README.md`, `executable/main/…ProjecturedExecutable.jl…AppConfig.jl…Precompile.jl`, `executable/build/bin/<app_name>`) | STALE | Describes the pre-move `package/<slice>/{main,doc,builder}/` layout this same doc area's own README.md says no longer exists. The real layout is flat: guide lives at `documentation/package/executable/README.md`; code lives in `source/executable/{Executable.jl, AppConfig.default.jl, Precompile.jl}` (no `main/` subfolder, no file called `ProjecturedExecutable.jl`); the two packages are `package/ProjecturedBuilder/{Project.toml, src/ProjecturedBuilder.jl}` and `package/ProjecturedExecutable/{Project.toml, src/ProjecturedExecutable.jl}`. | `ls source/executable/`, `find package/ProjecturedBuilder package/ProjecturedExecutable -type f` | Redraw the tree against the real `source/executable/` + `package/ProjecturedBuilder/` + `package/ProjecturedExecutable/` split. | checked |
| "`domain` … a key in `ProjecturedExample.EDITOR_DOMAINS`" | WRONG | `EDITOR_DOMAINS` does not exist anywhere in the repository. | `grep -rn EDITOR_DOMAINS source/` → no hits | Describe how a domain is actually validated/dispatched (via `BuildSpec`'s own `validate` — `spec.domain in spec.domains`, `source/builder/Builder.jl:99-107` — there is no separate registry constant). | checked |
| `BuildSpec` options table | MISSING | The table lists 9 keywords; the real struct has 12 fields / keyword arguments. Missing entirely: `domains::Vector{Symbol}` (the set of content domains the binary accepts at runtime, dispatched by file extension — `domain` is only the default/fallback) and `workload::Symbol` (defaults to `:none`, unexplained). | `source/builder/Builder.jl:65-90` (struct + keyword constructor + docstring) | Add both rows; update the `domain` row to say it is the *default*, with `domains` the accepted set (multi-domain builds are real: `make_workbench_app` already uses `domains=[:json,:xml,:sql,:julia]`). | checked |
| `build_executable(make_workbench_app(SdlBackend))` / `default_json_app(SdlBackend)` | — | Both functions exist with exactly the claimed behavior — `default_json_app(backend) = BuildSpec(; backends=[backend])`, `make_workbench_app(backend) = BuildSpec(; domain=:json, domains=[:json,:xml,:sql,:julia], workbench=true, file_backed=true, backends=[backend])`. | `source/builder/Builder.jl:268,277-281` | none | checked |
| `AppConfig.default.jl` (checked in) vs `AppConfig.jl` (generated, git-ignored) | — | Both exist as described. | `source/executable/AppConfig.default.jl` present; `AppConfig.jl` absent (git-ignored, as claimed) | none | checked |
| `julia_main`, `precompile_warmup`, `print_help`, `print_version` | — | All exported from `Executable.jl` exactly as named. | `source/executable/Executable.jl:8,100,108,144,183` | none | checked |
| Runtime flags `--backend`, `--help`, `--version` | — | Not independently re-verified beyond `julia_main`'s existence; consistent with the exported `print_help`/`print_version` names. | `source/executable/Executable.jl:8` | none | likely |

**Framing:** neutral, purely operational — a natural place, in the rewrite, to mention that the same binary can start an MCP server (`mcp=true` is already a real `BuildSpec` field, so the "AI assistant and MCP clients share one tool set" framing has a concrete, already-shipping example sitting right here that the guide does not currently call out).

---

## Substrate slices with no guide

`ls source/` has 63 folders; `documentation/package/` has guides for 21 of them
(`adaptagrams, chart, collection, conversation, executable, fsm, graph, graphics,
json, math, pane, process, reflection, rst, sequencechart, syntax, text,
versioning, widget, workbench, xml`). The rest are either domain packages
(covered by the domain-inventory area, not this one) or the substrate/tooling
slices below — the infrastructure every view is built from, none of which has
its own `documentation/package/<slice>/` guide. One line each, from the slice's
own main-module docstring, plus its size:

| slice | holds | size |
|---|---|---|
| `layout` | Content-driven layout documents (`children::CellVector` + alignment/gap/max-extent knobs); not tied to widgets — any document with a graphics projection can be a child. | 3116 lines |
| `style` | The color value type and named color constants (normalized Float64 components); also fonts, strokes, text styles. | 2460 lines |
| `primitive` | The domain-independent editable Bool/Number/String wrappers with selection and identity, each backed by a reactive `Cell`. | 327 lines |
| `projection` | The domain-free projection algebra: generic/higher-order combinators, compound aggregates, `Searching`, `Copying`, the two collection-shaped projections, IoMap-typed reader defaults. | 154 lines |
| `domain` | The core document domain: base abstract type, nothing-document, insertion placeholder, reference document; load/save/import/export live with the serializers, not here. | 720 lines |
| `screen` | The projection-output side of the multi-window pipeline: `ScreenDocument` holds `WindowDocument`s (id/title/x/y/w/h/bg/style + one `content::Document`); backends reconcile live native windows against it. | 770 lines |
| `sdl` | The SDL2 native-window backend (`SdlBackend`, `measure_sdl_text`); exports only its generic-extension surface plus the one function passed by value to `TextToGraphics`. | 3084 lines |
| `web` | The web backend: browser connection/session state (`WebConnection`), serializes graphics primitives to a JSON draw-list the browser paints, key-code translation. | 834 lines |
| `console` | Renders a Text-domain document (`TextBlock`) straight to a terminal via ANSI SGR codes; translates terminal keystrokes into backend-agnostic events. Unlike SDL it consumes Text directly, skipping the graphics layer. | 325 lines |
| `pdf` | A second, SDL-free backend over the graphics domain: walks a `GraphicsCanvas` and emits vector PDF (path ops + selectable `Tj` text); embeds the editor's own TrueType fonts as Type0/CIDFontType2. | 823 lines |
| `video` | `record_video` — drives a document/projection pair like the test harness's editor stand-in and captures frames. | 203 lines |
| `plot` | Shared arithmetic for anything that plots data: axis scaling, tick selection, data↔pixel mapping, and shared color/marker vocabulary — used by both `chart` and `sequencechart`, owned by neither. | 869 lines |
| `tooltip` | `TooltipSource`, a transparent wrapper marking a sub-tree as a tooltip anchor; `TooltipDecoratorProjection` watches events on it and opens/closes a window carrying the content. | 189 lines |
| `focus` | The generic focus-traversal walk: pure helpers finding the first/last focusable leaf in a subtree as a relative whole-element path — focus is selection, not a separate field. | 127 lines |
| `inspector` | `ReferenceInspector` pairs a `Reference` with the document it points into; `ReferenceInspectorToText` renders both a compact and a narrative form. | 247 lines |
| `clipboard` | OS clipboard access: shell commands to read/write it and the per-platform selection logic. | 808 lines |
| `dragging` | `DraggingState`, a transparent wrapper marking a sub-tree as a drag-and-drop reorder region; gesture interpretation lives in `DraggingProjection`. | 349 lines |
| `gesturehelp` | The gesture-help domain: the gesture map, the command palette, the projections that draw them, two decorators that put them on screen. | 838 lines |
| `gesturelog` | A record of what the user did: fixed-size buffer of the last N gestures and the operation each produced, in a `CellVector`. | 545 lines |
| `serialization` | Exact, lossless binary persistence (`save_document`/`load_document`) via Julia's `Serialization` stdlib, with a `Cell` serializing as just its value. | 1561 lines |
| `fileformat` | Reading/writing a document as a file (`import_document`/`export_document`) and the two editor operations that do it; what a notation *is* lives in `natural`, not here. | 188 lines |
| `builder` | `ProjecturedBuilder`: `BuildSpec` + `build_executable` — this is the package documented (mostly accurately) by `executable/README.md`. | 281 lines |
| `repl` | Re-exports every name of `Projectured`/`ProjecturedExample`/`ProjecturedSdl`/`ProjecturedTest` for interactive use — a thin convenience module, not a domain. | 126 lines |
| `natural` | What a document's natural notation is and how two notations combine, along a `domain → syntax → text → graphics` ladder. | 668 lines |
| `bench` | Does not exist as a `source/` folder — the brief's example list named it but there is no such slice in this repository. | — |

Two more substrate slices turned up while cross-checking `widget`/`reflection` that
are also undocumented and worth flagging even though they were not in the brief's
example list:

| slice | holds | size |
|---|---|---|
| `component` | Higher-level UI building blocks composed from widget primitives (e.g. `ComponentMasterDetail`) — combines widget atoms into reusable behavioral units, one layer above `widget`. | 76 lines |
| `kernel` | Has its own guide set under `documentation/package/kernel/` (10 files) — not missing a guide, listed here only to confirm it is not part of this "no guide" gap. | — |

## Top findings of this area

1. **text.md's central claim about `TextLine` is inverted.** It says `TextLine` is "not laid out by `TextToGraphics` yet" and that spans are addressed by a flat `span_idx`; the code now lays out `TextLine` and addresses spans via `SegmentCoordinate.span_path::SpanPath` (`[i]`/`[i,j]`). (checked)
2. **syntax.md documents 2 of 9 syntax document types.** `SyntaxDelimitation`, `SyntaxIndentation`, `SyntaxCollapsible`, `SyntaxNavigation`, `SyntaxConcatenation`, `SyntaxSeparation`, `SyntaxInsertion` and the `SyntaxCompound`/`SyntaxSequence`/`SyntaxWrapper` hierarchy they sit in are entirely unmentioned. (checked)
3. **Two non-cross-referencing reflection-to-view mechanisms exist** — `DocumentReflection`/`ReflectionToWidget` (reflection slice, documented in bounded-sync.md) and `ObjectToWidget` (widget slice, documented in widget.md) — and no document says how they relate. This is the exact mechanism the new "on-demand UI for any value" framing needs to lead with, so the split should be resolved (merge, or explicitly scope each) before the rewrite. (checked)
4. **widget.md's widget-type count is stale by 9**: 42 `WidgetDocument` subtypes exist; the guide's tables and its own "33 widget types" tally both undercount, missing at least `WidgetTabPage` and `WidgetOption` entirely. (checked)
5. **`documentation/package/executable/README.md`'s "Project structure" tree describes a directory layout that no longer exists** (`executable/main/`, `executable/builder/`) — the real layout is `source/executable/` + `package/ProjecturedBuilder/` + `package/ProjecturedExecutable/`. (checked)
6. **`executable/README.md` references `ProjecturedExample.EDITOR_DOMAINS`, which does not exist anywhere in the repository**; `BuildSpec` also gained a `domains` (multi-domain) and a `workload` field the doc never mentions. (checked)
7. **"visual/" is a dead top-level path baked into three of these ten guides** (widget.md's link text, collection.md's "`ScreenDocument` lives in `visual/screen/`", bounded-sync.md's "in the visual package") and into five source-code comments (`package/visual/doc/widget.md` in `LayoutToGraphics.jl` ×2, `WidgetToGraphics.jl` ×2, one test). The actual top-level is flat under `source/`. (checked)
8. **bounded-sync.md carries a history paragraph the project's own commenting rule forbids** ("An earlier version put a second, bounded walk in `BoundedSync.jl`… Folding the bound in removed ~150 lines…"), and its one factual claim in that area ("in the visual package") is wrong. This is otherwise the strongest-framed file in the set for the new "on-demand" story and deserves to be promoted, not just fixed. (checked)
9. **Two dead file links**: `text.md` → `source/text/Text.jl` (real file: `TextDocument.jl`), `syntax.md` → `source/syntax/Syntax.jl` (real file: `SyntaxDocument.jl`). Both guides also describe the reader mechanism as a plain `read_gesture(::Type, gesture)` method when the code now uses reified `@gestures <Type> begin … end` tables. (checked)
10. **pane.md and collection.md are the two most accurate files in the set** — every type, function and test name checked against source matched exactly; only cosmetic path-naming issues (`package/pane/main/`, `visual/screen/`) remain. Worth using as the style template for the rewrite. (checked)
11. **graphics.md is accurate but incomplete**: 3 of 8 graphics document types are named (`GraphicsLine`, `GraphicsCircle`, `GraphicsPolyline`, `GraphicsPolygon`, `GraphicsViewport`, `GraphicsImage` all missing from the Types table despite being used elsewhere in the guide set, e.g. widget.md's icon rendering). (checked)
12. **Minor AI-slop language**: "first-class" appears three times in widget.md (banned word); "previously expressible only as…" in widget.md and "an earlier version…" in bounded-sync.md are history phrasing the project rule bans. (checked)

---

# What a user and a Julia developer can do with ProjecturEd today

A capability inventory built from the code of `/home/projectured/workspace/projectured-julia`
(no Julia was run; every claim is grep/Read evidence). Written for the plan that reframes
ProjecturEd as a generic, on-demand UI for Julia data with AI integration, rather than "a
projectional editor."

---

## 1. Entry points

**The demo gallery: `run_example`.** Defined in
`example/projectured/ProjecturedExamples.jl:49` (`run_example(name="json"; kwargs...)`), plus
`print_example`, `write_example_image`, `write_example_pdf`, `record_example_video`, all doing
the same `name -> examples` lookup. `examples` (line 1) is a flat `Vector{Example}` — **109
curated names** (counted from the array literal), assembled from two tiers:
`example/substrate/SubstrateExamples.jl` (`substrate_examples`, visual/base building blocks —
syntax, text, widgets, layouts, collections) and `example/projectured/DomainExamples.jl`
(`domain_examples`, concrete content domains and applications — json, xml, sql, fsm, chart,
workbench, assistant, ...). A handful of examples (`lazy_example`, `math_display_example`,
`clipboard_example`, `versioning_example`) are deliberately kept out of the registry (documented
reasons at `DomainExamples.jl:67-124`) and are run by variable, not by name.

On top of the curated list sits a **generated catalog** (`example/projectured/Catalog.jl`): 295
hand-authored `AtomicDocument`s (225 in `DomainExamples.jl`, 70 in `SubstrateExamples.jl`, one per
node type per domain — e.g. `AtomicDocument(:json, "object", ...)`), each turned by a breadth-first
search over the registered projection bridges into up to three more `Example`s named
`domain/name/variant` (its trivial projection, and the composite projections that reach `:text`
and `:graphics`). This is what the test sweeps (`test_printers()`, etc.) actually walk; only 6 of
the ~400 possible example names are documented anywhere a person reads
(`documentation/guide/examples-tour.md`, see item 8).

**The file-backed single editor.** `run_file_editor(domain; file, workbench, backend, ...)` in
`example/projectured/FileEditor.jl:169`. `domain` is a key into `EDITOR_DOMAINS`
(`FileEditor.jl:56`), which today has exactly **four** entries: `:json`, `:xml`, `:sql`, `:julia`.
A file is opened by extension via `EXTENSION_DOMAINS` (`.json`, `.xml`, `.sql`, `.jl`,
`FileEditor.jl:100`); a nonexistent path opens as that domain's empty insertion seed.
`run_file_editor` is what `julia_main` (`source/executable/Executable.jl:169`) calls to build the
compiled binary, and what `build_executable`'s two shipping configurations use
(`documentation/package/executable/README.md:26-27`: the workbench app bakes in
json/xml/sql/julia; the v1 default is a plain JSON file editor).

**Opening a window on an arbitrary Julia value — no single call does this today.** Three
separate, real mechanisms exist, none of them wired to each other or exposed behind one
convenience function:

1. `NaturalToGraphics(; measure, ...)` (`source/natural/NaturalProjection.jl:108`) is a real,
   bidirectional, recursive projection that renders "almost any document" — its own doc comment
   says so at line 3 — falling through layouts, widgets, self-drawing domains and prose to
   `ObjectToSyntax`'s reflection table (`source/syntax/ObjectToSyntax.jl:1-8`, `177-239`), which
   reflects **any Julia struct** via `fieldnames`/`getfield` into a `TypeName { field value ... }`
   syntax tree, cycle-guarded (`ObjectToSyntax.jl:186-194`) and depth-safe. This is what
   `run_example("natural")` demonstrates (`example/projectured/NaturalProjectionExample.jl`), and
   what the workbench/conversation/chart/table/pane panels use internally to render whatever a tab
   holds (`grep NaturalToGraphics(` outside tests hits exactly those example-projection files).
   There is no `edit(x)`/`show_editor(x)`/`inspect(x)` wrapper that takes a bare value and opens a
   window — a caller has to assemble `_run_window_scene(Any[x], Any[NaturalToGraphics(...)], ...)`
   by hand.
2. `reflect_document(object, policy=DepthPolicy(1))` (`source/reflection/DocumentReflection.jl:172`)
   builds a bounded, lazily-expanding `ReflectedNode` tree over **any** Julia object (a live
   simulation engine is the motivating case, per the file's own header comment) and
   `ReflectionToWidget` (`source/reflection/ReflectionToWidget.jl:36`) projects it to a
   `WidgetTree` with click-to-expand chevrons. Both are fully implemented and unit-tested
   (`test/substrate/document/DocumentReflectionTest.jl`, `test/substrate/projection/
   ReflectionToWidgetTest.jl`), but **no production code calls either one** —
   `grep -rn "reflect_document(" .` finds only the two test files; `grep -rln "ReflectionToWidget("
   .` finds only its own definition. It is read-only by design (a comment at
   `ReflectionToWidget.jl:12-19` explains why it is not `ObjectToWidget`: editing is "the wrong
   affordance for a running engine's internals"). `omnet-julia` is the one real consumer — see
   item 7.
3. `ObjectToWidget(; fields=nothing)` (`source/widget/ObjectToWidget.jl:64`) turns a `@document`
   struct's `Cell` fields into an editable form (text fields, checkboxes), recursively for nested
   `@document` structs. It requires the value to already be a reactive `@document` — it is not a
   generic "any Julia value" fallback, it is the domain-authoring primitive for turning a settings
   struct into a form. Demonstrated by `run_example("object_to_widget")` /
   `run_example("nested_object_to_widget")` (`example/substrate/ObjectToWidgetDocumentExample.jl`).

## 2. The workbench application

`WorkbenchWorkbench` (`source/workbench/WorkbenchDocument.jl:41`) holds four `WorkbenchPage`s:
navigation (left), editing (center), information (bottom), control (right) — confirmed by the
field order and by the example wiring in `example/workbench/WorkbenchDocumentExample.jl:63-77`.
The panels that exist as document types (`WorkbenchDocument.jl`): **Navigator** (`:69`, a file
tree over a `Workspace`), **Console** (`:87`), **Descriptor** (`:109`, shows the `Reference` under
the current selection), **Operator** (`:128`), **Searcher** (`:142`), **Evaluator** (`:158`,
comment at line 155 says its content is "not yet ported to Julia; typed as `Any`" — a stub),
**Editor** (`:178`, one open-file tab: title, filename, content, a `follow_end` flag). The
**Assistant** panel is a separate document type (`source/assistant/AssistantDocument.jl:86`) that
lives on the control page (`WorkbenchDocumentExample.jl:73-75`). Its title constants are literal
strings ("Navigator", "Console", "Descriptor", "Operator", "Searcher") pulled via
`get_workbench_title`.

**Tabs and splits are real and gesture-driven** (`source/pane/PaneGestures.jl`,
`source/pane/PaneSurgery.jl`, 2,854 lines total across the slice): `Ctrl+T` opens a new tab,
`Ctrl+W` closes the focused one, `Ctrl+Tab`/`Ctrl+Shift+Tab` move focus between groups,
`Ctrl+PageDown`/`Ctrl+PageUp` move between tabs, `F2` renames a tab (all at
`PaneGestures.jl:106-124`). `make_pane_split_operation` (`PaneSurgery.jl:451`) and
`make_pane_move_tab_operation` (`:510`) exist in the operation layer but no `@gestures` rule in
this file binds a key or click to splitting — split is presumably drag-to-edge (matches the
memory note that split-pane drag has a pre-existing test failure; the mechanism is there, the
gesture path is not confirmed working).

**Opening a file into a tab has no discovered UI gesture.** `WorkbenchOpenDocumentOperation`
(`WorkbenchDocument.jl:218`) is the operation that appends a `WorkbenchEditor` to a page. Its only
caller anywhere in the repository is `test/projectured/editor/McpTest.jl:217-235`, which exercises
it exactly the way an assistant tool call would (build the operation, `evaluate_operation`
directly) — the file's own comment at line 213 says "the same path the editor loop runs for a
gesture," but no such gesture exists in `source/workbench` or `source/filesystem`. The Navigator's
widget projection (`source/workbench/WorkbenchToWidget.jl:773-776`,
`read_intent(::WorkbenchNavigatorToWidgetScrollPane, ...)`) just forwards operations generically
(`_retarget_panel_op`); there is no double-click-opens-a-tab logic in it or in
`source/filesystem/FileSystemToWidget.jl`. In today's code, a file lands in a workbench tab either
because the example document pre-populated it (`WorkbenchDocumentExample.jl:39-50`) or because the
assistant/MCP client runs `evaluate_operation(editor, WorkbenchOpenDocumentOperation(...))` via
`execute_julia_code`.

**Duplicating a pane and pasting a selected widget into a new tab do not exist yet.**
`git log` shows four recent commits titled "Plan: ..." for exactly these features (duplicate a
pane, Alt+click select any widget, Alt+Left/Right sibling walk, tool panes refuse a paste); the
plan files confirm this is design, not code:
`plan/pending/select-a-widget-and-paste-it-into-a-tab.md:3` states "**Status (2026-09-17): NOT
STARTED.** No code changed yet," and `plan/pending/duplicate-a-pane.md` (Status: pending) describes
`duplicate_pane!` and a copy-policy `copy_document` that `grep -rln "duplicate_pane\!" .` finds
nowhere in `source/`. These are near-term roadmap, not current capability — worth flagging because
the new framing's "select any widget in any pane" story is not implemented today.

## 3. The assistant

**Starting it.** `Assistant(; conversation, input, backend=:none, model="", system=DEFAULT_
ASSISTANT_SYSTEM, api_key="", context=0, status=:idle, llm=nothing)`
(`source/assistant/AssistantDocument.jl:86-124`). `backend` defaults to `:none` — submitting with
no backend errors, listing the backends whose packages are loaded
(doc comment at lines 64-67). Production code never fabricates a fake backend (line 82); tests and
examples pass an explicit `llm=FakeLlm()` (`example/kernel/LlmFake.jl`) for offline runs — there is
no real "offline" backend a user selects, only two live ones:

- **`:anthropic`** — `AnthropicLlm` (`source/anthropic/Anthropic.jl`). Default model
  `"claude-opus-4-5-20251101"` (`Anthropic.jl:5`); API key from `ENV["ANTHROPIC_API_KEY"]`
  (`:24`), read at construction.
- **`:ollama`** — `OllamaLlm` (`source/ollama/Ollama.jl`). No API key (local server). Default URL
  `"http://localhost:11434"` (`:3`), default chat model `"qwen3.8:27b"` (`:4`), default embedding
  ("meaning") model `"nomic-embed-text"` (`:5`).

**What the model can call — `register_default_tools!`
(`source/kernel/tool/DefaultTools.jl:122`):**

| Tool | What it does |
|---|---|
| `execute_julia_code` | Runs Julia in the editor process; `editor` is bound to the running `Editor` (`.document`, `.projection`). This is the mechanism, not `search_references`/`evaluate_operation` themselves — everything else the assistant does to the UI goes through this one tool (`DefaultTools.jl:6-31`). |
| `search_guides` | Full-text/keyword/regex/"meaning" search over the prose guides (`:133-148`). |
| `search_api` | Same, over modules/types/functions the model may call (`:150-169`). |
| `read_function_documentation` | Full docstring of one function, by module+name (`:179-200`). |
| `list_resources` | Enumerates the resource catalogue (`:205-212`). |
| `read_resource` | Reads one resource in full by `resource://...` URI (`:214-224`). |

Resources registered alongside: `resource://guides`, one `resource://guide/<name>` per guide file,
`resource://modules`, one `resource://module/<name>` and `resource://type/<module>/<type>` per
declared API surface (`:235-286`). The system prompt
(`AssistantDocument.jl:14-46`, `DEFAULT_ASSISTANT_SYSTEM`) tells the model explicitly: use
`search_references`/`search_documents`/`evaluate_reference`/`evaluate_operation` through
`execute_julia_code` — "This is the one way to change the document." That is a direct, literal
match for the new framing's claim that the assistant "writes and runs Julia against the live
editor": it is not a separate command layer, it is the same `Editor` object and the same
`evaluate_operation` path a keystroke uses.

**Meaning search.** `source/kernel/tool/MeaningSearch.jl` computes and caches embedding vectors
(process-global store, `_MeaningStore` at line 32; files under `build/meaning/`, magic header
`"PJMEAN01"` at line 28) via whichever backend's `meaning_model` is set — currently only
`OllamaLlm.meaning_model` (`Ollama.jl:57`, default `nomic-embed-text`), so meaning-mode search
needs a local Ollama running even when the chat backend is Anthropic.

**MCP server.** `McpServer(editor)` (`source/mcp/Mcp.jl:22`); `start_mcp!`
(`:60`) serves **HTTP transport on `127.0.0.1:9876`, endpoint `/mcp`**
(`Mcp.jl:64-70`). It registers the *same* tool set the in-editor assistant uses
(`_make_tools(mcp.editor)`, line 61) and the same instructions
(`DEFAULT_MCP_INSTRUCTIONS`, line 6, or an app-supplied override) — the in-editor assistant and an
external MCP client genuinely share one tool surface, matching the new framing's claim. Started
via `run_file_editor(...; mcp=true)` (`FileEditor.jl:170`) or directly through
`make_agent_server(:mcp, editor)` / `start_agent_server!`.

**What the assistant can do to the UI:** open views, change the document, change the projection —
all three go through `execute_julia_code` calling the same generic primitives (`search_documents`,
`evaluate_operation`, `ReplaceSelectionOperation`, `WorkbenchOpenDocumentOperation`, ...) a
keystroke's `read_intent` would produce. There is no separate "assistant API" distinct from the
Julia API a library user calls directly.

## 4. Key bindings and gestures

Defined via the `@gestures`/`@gesture_set` DSL (`source/kernel/binding/Gestures.jl`), which
compiles a `get_document_gesture_bindings_own(::Type{T})` method per document type
(`Gestures.jl:171-188`); bindings are inherited down a type's supertype chain and aggregated by
`get_document_gesture_bindings`. 22 files use `@gestures` across the tree (json, xml, yaml, syntax,
text, pane, fsm, chart, process, sequencechart, workbench, ...) — there is no single central
binding table; each domain declares its own, and the **help window is the aggregator**, not a
document.

- **Help window: `F1`.** `HELP_GESTURE = KeyDownPattern(:f1)`
  (`source/gesturehelp/GestureHelpDecorator.jl:31`) opens a `GestureMap`
  (`source/gesturehelp/GestureMap.jl`) built from the live bindings applicable to the current
  document/selection — the "user-facing list" the survey asked about exists, and it is generated
  from the same reified `GestureBinding` data the editor runs on, not hand-maintained prose.
- **Command palette: `Ctrl+Shift+P`.** `COMMAND_PALETTE_GESTURE = KeyDownPattern(:p, [:ctrl,
  :shift])` (`source/gesturehelp/CommandPaletteDecorator.jl:36`) — fuzzy-runs any binding by its
  description, including `nothing => "description" => rhs` command-only rules that have no key at
  all (`Gestures.jl:151-156`).
- **Tree/structural navigation (syntax-backed domains):** plain arrows move the text caret;
  `Alt`+arrows walk the tree structurally (`source/syntax/SyntaxDocument.jl:634-638`);
  `Ctrl+Space` toggles structural/text cursor mode (`:628`, `:819`); `Ctrl+Alt+Home` selects the
  root/whole leaf (`:626`, `:817`).
- **Clipboard:** `Ctrl+C` copy, `Ctrl+X` cut, `Ctrl+N` note, `Ctrl+V` paste, `Ctrl+Shift+V`
  paste-as-copy, `Ctrl+/` toggle slice/content display
  (`source/clipboard/ClipboardSliceToAny.jl:314-329`). Optional OS-clipboard bridge via
  `to_text`/`from_text` converters (file header comment, lines 21-29).
- **Collapse/expand:** `Ctrl+.` on `TextDocument` (`source/text/TextDocument.jl:355`), plus
  click-a-fold-marker in `SyntaxToText.jl` and click-a-chevron on a `WidgetCard`
  (`source/widget/WidgetToGraphics.jl:4353`). `JsonArray`/`JsonObject` carry a `collapsed` field
  (`source/json/JsonDocument.jl:41-65`) but no gesture in `source/json/` toggles it — collapse is
  wired for Syntax and text/widget chrome, not yet for JSON's own presentation (matches the memory
  note "Collapse/expand: syntax only").
- **Tabs/panes:** see item 2 (`Ctrl+T`/`Ctrl+W`/`Ctrl+Tab`/`Ctrl+PageUp`/`Ctrl+PageDown`/`F2`).
- **Undo/redo: none.** `grep -rln "\bundo\b\|\bredo\b" source/` finds three hits, all comments
  about unrelated "undo my own state" bookkeeping in widget hover tracking and pane geometry
  (`source/widget/WidgetHoverTracking.jl:25`, `source/pane/PaneProgram.jl:432-442`) — there is no
  undo stack, no `Ctrl+Z` binding anywhere in `source/`. `PaneProgram.jl:442`'s comment ("the
  person undoes it with one [gesture]") is about a single `ReplaceReferencedValueOperation` being
  easy to *manually* invert, not a system undo command.

## 5. Backends and outputs

| Backend/output | Call | Evidence |
|---|---|---|
| SDL (native window) | `SdlBackend()` passed to `run_example`/`run_file_editor`/`run_editor!` | `source/sdl/Sdl.jl` (3,084 lines) |
| Web (browser, canvas serialization) | `WebBackend(; host="127.0.0.1", port=8080)` | `source/web/Web.jl:39,58` |
| Console (ANSI terminal) | `ConsoleBackend()` | `source/console/Console.jl`, used headlessly in `warm_file_editor` (`FileEditor.jl:262`) |
| PDF (vector, paginated) | `write_pdf(doc, proj, "file.pdf"; paginate=true, height=792)` | `source/pdf/Pdf.jl:647,691-695` |
| Image (PNG/BMP snapshot) | `write_image(doc, proj, "snapshot.png"; width, height)` | `source/sdl/Sdl.jl:2335-2336` |
| Video (MP4, gesture-scripted) | `record_video(document, projection, gestures, filename)` | `source/video/Video.jl:69`; wrapped by `record_example_video` |

Opt-in, not baked in by default: SDL/Web/Video/Tulip sit above the substrate layer in the package
DAG (`documentation/design/system-anatomy.md:340-342`, the `(opt-in)` arrows), so a build that
doesn't `using` them doesn't pay for them.

## 6. Data formats and files

Two independent mechanisms, both format-by-extension:

1. **Natural (human-authored) per-domain text formats**, registered by each domain with
   `register_natural_domain!(T; format, extension, parse, ...)`
   (`source/natural/NaturalNotation.jl:98`) and dispatched by `import_document`/`export_document`
   (`source/fileformat/NaturalFormat.jl:15,32`). Confirmed registrations (`grep
   register_natural_domain!`): `.json` (`source/json/JsonModule.jl:65`), `.xml`
  (`source/xml/XmlModule.jl:58`), `.yaml` (`source/yaml/YamlToSyntax.jl:277`), `.md`
  (`source/markdown/MarkdownModule.jl:72`), `.rst` (`source/rst/RstModule.jl:102`), `.math`
  (`source/math/MathToSyntax.jl:677`), `.jl` (`source/julia/JuliaModule.jl:84`), `.sql`
  (`source/sql/SqlToSyntax.jl:2035`) — **8 domains**, each round-tripping through its own
  parser/printer. Note: `run_file_editor`'s `EDITOR_DOMAINS` (item 1) only wires up 4 of these
  (json/xml/sql/julia) as a standalone scratch editor; the workbench's own open/save
  (`source/workbench/WorkbenchFile.jl:27,44`, via `read_document_file`/`write_document_file`) goes
  through the full 8-domain registry, so yaml/markdown/rst/math files open inside a workbench tab
  but not through the single-file executable.
2. **Generic document serialization, independent of domain:** `.pdoc` is a binary snapshot of any
   document via Julia's own `Serialization` (`source/serialization/BinarySerialization.jl`, magic
   `"PROJECTURED-DOC"` at `:20`). `.pred` is a human-readable "marker language at file scale"
   (`source/serialization/PredFile.jl:1-19`) — a document is written as its own constructor call
   (`TestRun(name="aloha", ...)`), any type registered with `register_pred_type!` can round-trip,
   and a value can be a cross-file reference (`file("b.xml")`, `node(file("a.json"),
   "entries[1].value")`) so a `.pred` project can splice other files by reference. Seen in
   examples as `"table.pred"` (`example/workbench/WorkbenchDocumentExample.jl:45`).

## 7. omnet-julia as an application built on ProjecturEd

`omnet-julia`'s README (`README.md:1-19`) describes it as OMNET-NG, "a parallel discrete event
simulator in Julia, a projectional user interface over live simulations" — "a simulation is a set
of ProjecturEd documents, so every stage of its lifecycle can be shown, edited, and driven from
one screen." `grep -rhoE "using Projectured[A-Za-z]*" --include=*.jl .` across omnet-julia finds
**29 distinct Projectured packages** in use, including the full kernel/substrate/domain stack
(`ProjecturedKernel`, `ProjecturedProjection`, `ProjecturedScreen`, `ProjecturedWidget`,
`ProjecturedLayout`, `ProjecturedSyntax`, `ProjecturedText`, `ProjecturedPane`,
`ProjecturedGestureHelp`, `ProjecturedSdl`) and, notably, `ProjecturedAssistant`,
`ProjecturedAnthropic`, `ProjecturedOllama` (the AI assistant is embedded in the simulator's own
UI, not just demoed in projectured-julia) and `ProjecturedReflection` — `demo/watch/battery.jl:29`
and `demo/watch/inspector.jl:27` both `using ProjecturedReflection.ReflectionModule:
AReflectedNode, sync_reflection!` to build a live watch/inspector pane over a running simulation
engine. This is the one real, load-bearing use of the reflection mechanism described in item 1 as
otherwise test-only inside projectured-julia — it is exactly the "any live system gets an editable
view" story the new framing wants, already proven in a downstream application, just not yet
generalized back into projectured-julia's own UI.

## 8. Documentation coverage

LOC = `wc -l` over each slice's top-level `*.jl` files (recursive for `kernel`, `graph`,
`projection`, `repl`, which have subdirectories). "Covered by" names the most specific existing
document; `system-anatomy.md (1-line inventory only)` means the slice gets one line in the
package/layer list (`documentation/design/system-anatomy.md:340-420`) and nothing else.

| slice | package | LOC | covered by |
|---|---|---:|---|
| adaptagrams | ProjecturedAdaptagrams | 291 | `documentation/package/adaptagrams/README.md` |
| anthropic | ProjecturedAnthropic | 327 | none (named only in `rule/package-rules.md`, `kernel/agent.md`) |
| assistant | ProjecturedAssistant | 1,407 | none (same — no dedicated guide) |
| book | ProjecturedBook | 750 | none (domain-inventory.md lists it, no guide of its own) |
| builder | ProjecturedBuilder | 281 | `documentation/package/executable/README.md` |
| chart | ProjecturedChart | 2,522 | `documentation/package/chart/chart.md` |
| clipboard | ProjecturedClipboard | 808 | system-anatomy.md (1-line inventory only) |
| collection | ProjecturedCollection | 608 | `documentation/package/collection/collection.md` |
| component | ProjecturedComponent | 76 | system-anatomy.md (1-line inventory only) |
| console | ProjecturedConsole | 325 | `documentation/package/kernel/devices-and-backends.md` |
| conversation | ProjecturedConversation | 1,652 | `documentation/package/conversation/transcript.md` |
| database | ProjecturedDatabase | 236 | none |
| dbcatalog | ProjecturedDbCatalog | 551 | none (domain-inventory.md table row only) |
| domain | ProjecturedDomain | 720 | system-anatomy.md (1-line inventory only) |
| dragging | ProjecturedDragging | 349 | system-anatomy.md (1-line inventory only) |
| executable | ProjecturedExecutable | 227 | `documentation/package/executable/README.md` |
| fileformat | ProjecturedFileFormat | 188 | system-anatomy.md (1-line inventory only) |
| filesystem | ProjecturedFileSystem | 461 | none (domain-inventory.md table row only) |
| focus | ProjecturedFocus | 127 | system-anatomy.md (1-line inventory only) |
| formula | ProjecturedFormula | 1,102 | none (domain-inventory.md table row only) |
| fsm | ProjecturedFsm | 1,353 | `documentation/package/fsm/fsm.md` |
| gesturehelp | ProjecturedGestureHelp | 838 | system-anatomy.md (1-line inventory only) |
| gesturelog | ProjecturedGestureLog | 545 | system-anatomy.md (1-line inventory only) |
| graph | ProjecturedGraph | 4,627 | `documentation/package/graph/graph-layout.md` |
| graphics | ProjecturedGraphics | 1,037 | `documentation/package/graphics/graphics.md` |
| inspector | ProjecturedInspector | 247 | system-anatomy.md (1-line inventory only) |
| json | ProjecturedJson | 504 | `documentation/package/json/json.md` |
| julia | ProjecturedJulia | 2,504 | none (domain-inventory.md table row only) |
| kernel | ProjecturedKernel | 17,427 | `documentation/package/kernel/*.md` (13 guides; binding/clock/event/gesture layers have no dedicated file, only architecture.md mentions) |
| layout | ProjecturedLayout | 3,116 | system-anatomy.md (1-line inventory only) |
| markdown | ProjecturedMarkdown | 1,289 | none (domain-inventory.md table row only) |
| math | ProjecturedMath | 3,703 | `documentation/package/math/math.md` |
| mcp | ProjecturedMcp | 171 | none (named only in `rule/package-rules.md`, `kernel/agent.md`, `guide/orientation.md`) |
| natural | ProjecturedNatural | 668 | system-anatomy.md (1-line, and mislabeled "naturalprojection" there vs. the real dir/package name `natural`/`ProjecturedNatural`) |
| odbc | ProjecturedOdbc | 513 | none |
| ollama | ProjecturedOllama | 500 | none (same as anthropic) |
| pane | ProjecturedPane | 2,854 | `documentation/package/pane/pane.md` |
| pdf | ProjecturedPdf | 823 | `documentation/package/kernel/devices-and-backends.md` |
| plot | ProjecturedPlot | 869 | system-anatomy.md (1-line inventory only) |
| primitive | ProjecturedPrimitive | 327 | system-anatomy.md (1-line inventory only) |
| process | ProjecturedProcess | 1,857 | `documentation/package/process/process.md` |
| projection | ProjecturedProjection | 1,809 | system-anatomy.md (1-line inventory only) |
| projectured | Projectured (umbrella) | 49 | README.md, system-anatomy.md |
| reflection | ProjecturedReflection | 682 | `documentation/package/reflection/bounded-sync.md` (covers bounded sync; `DocumentReflection.jl`'s object-reflection half is not separately documented) |
| repl | ProjecturedRepl | 219 | `documentation/guide/setup-guide.md`, `guide/debugging-guide.md` (usage, not a package guide) |
| rst | ProjecturedRst | 2,952 | `documentation/package/rst/rst.md` |
| screen | ProjecturedScreen | 770 | system-anatomy.md (1-line inventory only) |
| sdl | ProjecturedSdl | 3,084 | `documentation/package/kernel/devices-and-backends.md` |
| sequencechart | ProjecturedSequenceChart | 3,214 | `documentation/package/sequencechart/sequencechart.md` |
| serialization | ProjecturedSerialization | 1,561 | system-anatomy.md (1-line inventory only) |
| sql | ProjecturedSql | 3,455 | none (domain-inventory.md table row only) |
| style | ProjecturedStyle | 2,460 | system-anatomy.md (1-line inventory only) |
| syntax | ProjecturedSyntax | 3,700 | `documentation/package/syntax/syntax.md` |
| text | ProjecturedText | 4,558 | `documentation/package/text/text.md` |
| tooltip | ProjecturedTooltip | 189 | system-anatomy.md (1-line inventory only) |
| tulip | ProjecturedTulip | 223 | none |
| versioning | ProjecturedVersioning | 479 | `documentation/package/versioning/versioning.md` |
| video | ProjecturedVideo | 203 | `documentation/package/kernel/devices-and-backends.md` |
| web | ProjecturedWeb | 834 | `documentation/package/kernel/devices-and-backends.md` |
| widget | ProjecturedWidget | 11,324 | `documentation/package/widget/widget.md` |
| workbench | ProjecturedWorkbench | 1,317 | `documentation/package/workbench/workbench.md` |
| xml | ProjecturedXml | 568 | `documentation/package/xml/xml.md` |
| yaml | ProjecturedYaml | 758 | none (domain-inventory.md table row only) |

Pattern: the pieces central to the new framing — **assistant, anthropic, ollama, mcp** — are the
ones with no dedicated guide at all, only passing mentions in an architecture/rules document. The
biggest slice by far, **widget** (11,324 lines — bigger than the next three combined), has one
guide. **sql** (3,455 lines, third-biggest domain) and **julia** (2,504 lines, the domain the
assistant itself is written in and the one the shipped binary bakes in by default) have none.

## 9. The lisp predecessor

The Julia code explicitly frames itself as a reimplementation of a Common Lisp original — not a
clean-room rewrite. `documentation/design/architecture-decisions.md:182-186` has a "Key differences
from the original ProjecturEd (Common Lisp)" table; `documentation/design/system-anatomy.md:468-476`
has a Lisp-vs-Julia parity/status table; `documentation/package/kernel/cell.md:6` says the reactive
cell engine "replaces the original Common Lisp" one. Thirteen source files carry "Julia port of
Lisp's `X`" comments naming the exact Lisp source file being ported (e.g.
`source/clipboard/ClipboardSliceToAny.jl:3-4`: "Julia port of Lisp's `clipboard/slice->t`
(`source/projection/primitive/clipboard-to-t.lisp`)"). None of this links to a repository path —
the connection is named conceptually, not with a clickable pointer to
`/home/projectured/workspace/projectured-lisp`. **Demo videos exist only for the Lisp original**:
`projectured-lisp/README.md:181` links "screencasts on youtube" at
`http://www.youtube.com/user/projectured` showing the editor in action. `grep -rli youtube` across
every `.md` file in `projectured-julia` finds nothing — the Julia repo's only visual material is
static PNG screenshots (`asset/image/example/`, generated by
`generate_example_screenshots`/`update_guide_screenshots` in `example/projectured/
ProjecturedExamples.jl:104,139`), not video.

---

## Gaps a newcomer hits first

1. **No single call opens a window on an arbitrary Julia value.** Three building blocks exist
   (`NaturalToGraphics`, `reflect_document`+`ReflectionToWidget`, `ObjectToWidget`) but none is a
   one-line `edit(x)`. This is the single biggest mismatch with the new framing's headline claim.
2. **The reflection mechanism (`reflect_document`) that would make "any live system gets an
   editable view" literally true is called only from tests inside this repo** — its one real
   caller is a downstream application (omnet-julia), and it is read-only by design.
3. **`assistant`, `anthropic`, `ollama`, `mcp` — the packages the new framing is built around —
   have no dedicated documentation.** A reader following the README's reading order never reaches
   a guide that explains them; they appear only as dependency-rule entries and inside
   `kernel/agent.md`.
4. **There is no undo/redo.** A structured editor pitched to new users will be asked about this
   immediately; today the honest answer is "none."
5. **Opening a file into a workbench tab has no discovered UI gesture** — it happens via
   pre-populated example documents or via the assistant/MCP tool calling
   `WorkbenchOpenDocumentOperation` directly.
6. **Duplicate-pane and select-any-widget-and-paste are plans, not code**, despite reading like
   shipped features in recent commit subjects ("Plan: any widget is selected by an Alt+click...").
7. **Only 6 of ~109 curated examples (and none of the ~295 generated catalog entries) are
   documented anywhere a person reads** (`examples-tour.md`); the other ~103 are discoverable only
   by reading `DomainExamples.jl`/`SubstrateExamples.jl` source.
8. **The single-file executable supports 4 of the 8 file formats the engine can actually
   round-trip** (json/xml/sql/julia baked in; yaml/markdown/rst/math only open inside a workbench
   tab, not the standalone editor `EDITOR_DOMAINS` registry).
9. **No real offline/local AI backend for a shipped binary** — `:anthropic` needs a paid API key,
   `:ollama` needs a locally running server with a model pulled; `FakeLlm` is test/example-only and
   production code refuses to fall back to it.
10. **Collapse/expand only works for Syntax and text/widget chrome**, not for JSON/XML's own
    `collapsed` field, despite the field existing on the document type.
11. **`documentation/package/kernel/devices-and-backends.md` links to a stale path**
    (`package/sdl/main/ProjecturedSdl.jl`) — the real path is
    `package/ProjecturedSdl/src/ProjecturedSdl.jl` — a small but visible sign the docs drift from
    the package layout.
12. **The biggest slice in the codebase (`widget`, 11,324 lines, bigger than the next three
    slices combined) and two of the largest domains (`sql`, `julia`) are under-documented relative
    to their size** — `widget` has one guide, `sql`/`julia` have none.

---

# Survey area I: plan folders

Scope: `plan/pending/` (53 files), `plan/tentative/` (10 files), `plan/obsolete/` (8 files).
Counts on disk match the assignment. `plan/done/` holds 262 files and is not tabulated in full;
its 15 most recent entries are checked at the end.

Method note: on 2026-08-12 someone ran a full audit pass that re-verified nearly every pending
plan against the code and stamped a `Status (2026-08-12): …` header with file:line evidence. On
2026-08-09, 2026-08-31 and 2026-09-01 several mechanical passes touched many plan files only to
fix link paths or apply repo-wide renames (commits "Point the pending plans at the packages the
files live in", "The documentation reads the way omnet-julia's does", "Every link resolves, and
the map is git's own", "ProjecturedNaturalProjection is ProjecturedNatural") — these do **not**
represent plan progress. Below, "last real commit" ignores those four mechanical commits when a
more meaningful date exists; the classification uses that date, not the raw `git log -1` date,
because the raw date would misclassify ~40 dormant plans as "changed in the last 30 days." Spot
checks (grep for the type/function each "NOT STARTED" plan names, e.g. `BoundSql`, `cairo`
package, `ParallelProjection`, `DocumentLocator`, `DocumentLink`, `DbCatalogIndex`, SQL `GROUP BY`)
all confirmed the plans' own self-assessment — no plan claiming NOT STARTED turned out to be
secretly done, and no plan claiming a specific remaining item turned out to be finished either.

## plan/pending/ (53 files)

| file | classification | last real date | note |
| --- | --- | --- | --- |
| a-present-that-is-a-timeout.md | STALE | 2026-08-15 | 1/2 done; frame-rate reading + a newly found `rotating_vector` crash (`Int64(::Nothing)` in `_render_polyline!`) still open |
| animation-global-time.md | SUPERSEDED | 2026-08-12 | by `plan/done/per-editor-animation-clock.md` |
| assistant-api-consolidation.md | ACTIVE | 2026-09-13 | 0/10 checked; assistant tool-vocabulary redesign, part of the same effort as the done `assistant-recovers-from-a-miss.md` and `assistant-finds-the-api.md` |
| assistant-recovers-from-a-miss.md | DONE | 2026-09-18 | moved to `plan/done/`; what landed, what the measurements kept out, and what a follow-up takes are in its §7 and §8 |
| bound-sql-statement.md | STALE | 2026-08-12 | confirmed NOT STARTED — `grep -r BoundSql` finds nothing outside this file |
| cairo-glfw-backend.md | STALE | 2026-08-12 | confirmed NOT STARTED — no `package/cairo` (or any cairo) directory exists |
| catalog-all-documents.md | STALE | 2026-07-16 | workstreams 1-3 done; workstream 4 (14 `@test_broken` bugs) still open |
| chase-animation.md | STALE | 2026-08-12 | NOT STARTED; its dependency `per-editor-animation-clock.md` is now done, so it is unblocked but still untouched |
| cheap-reactive-cells.md | STALE | 2026-08-12 | P1-P4 done; L1 object-granular reactivity and L2 lazy reactive-collection slots not started |
| collapse-expand-syntax-nodes.md | STALE | 2026-08-12 | JSON/XML collapse/expand wiring still open |
| component-document.md | STALE | 2026-08-09 | `ComponentToWidget` projection still does not exist (grep finds it only in a docstring pointing back at this plan); no master-detail example uses it |
| configuration-overlay-widget.md | STALE | 2026-08-12 | confirmed NOT STARTED |
| conversation-flat-transcript.md | ACTIVE | 2026-09-15 | Stages 1-3 done; Stage 4 items 3-4 open (belong to the pane that hosts the draft) |
| dbcatalog-index-support.md | STALE | 2026-08-12 | confirmed NOT STARTED — no `DbCatalogIndex`/`SqlCreateIndexStatement` |
| discovered-example-catalog.md | SUPERSEDED | 2026-08-12 | by `plan/done/atomic-example-catalog.md`; same cluster as `catalog-all-documents.md` and obsolete `test-suite-atomization.md` |
| document-link-feature.md | STALE | 2026-08-12 | confirmed NOT STARTED |
| document-locator.md | STALE | 2026-06-23 | confirmed NOT STARTED; `source/versioning/VersioningDocument.jl:81` names the pattern only in a comment |
| document-native-variant-layouts.md | SUPERSEDED | 2026-08-10 | by `plan/done/document-layouts-and-names.md` |
| duplicate-a-pane.md | ACTIVE | 2026-09-17 | brand-new plan, 0/10 checked |
| excel-julia-formulas.md | STALE | 2026-08-12 | phases 1-4 + 7 done; `FormulaInsertion` commit/parse (phase 1 sub-item) and one open sub-item remain |
| faster-executable-startup.md | STALE | 2026-07-01 | Tier 2 landed on `main` directly; Tier 0/1/3 follow-ups not done |
| fix-text-configuring-run-example.md | STALE | 2026-08-12 | confirmed NOT STARTED |
| formula-with-math-code.md | ACTIVE | 2026-09-16 | 8/9 checked; serves omnet-julia's `assistant-develops-a-study.md` |
| injecting-projection.md | STALE | 2026-08-12 | the core `InjectingProjection` type still does not exist; only an incidental piece (TextGraphics word-wrap) landed as a side effect of unrelated work |
| julia-syntax-navigation.md | STALE | 2026-08-12 | structural nav done by a different mechanism than proposed; 28 `test_position_navigation` failures are "the only remaining piece" but need a Julia run to re-check (not done here, per the no-Julia constraint) |
| kernel-cleanup.md | SUPERSEDED | 2026-08-12 | by `plan/done/kernel-layered-architecture.md` and its chain (`package-triad-folders.md` etc.) |
| left-motion-stalls-on-introduced-text.md | STALE | 2026-08-12 | root cause fixed; `formula`'s residual child-projection inconsistency still open |
| live-example-construction.md | STALE | 2026-07-17 | JSON reconstruction complete; other domains still in progress per the plan's own header |
| math-linear-form-reader.md | ACTIVE | 2026-09-16 | steps 1-4 done 2026-09-15; step 5 (type-in) open |
| naming-rule-renames.md | ACTIVE (near-done) | 2026-09-13 | "Applied 2026-09-13" — 374 renames landed; essentially a completed reference table for `naming-rule-violations.md` |
| naming-rule-violations.md | ACTIVE (near-done) | 2026-09-14 | "executed except the items of §0.3" — only two module names wait on the `graph`/`text` slice split |
| narrow-the-composition-point.md | ACTIVE | 2026-09-14 | created 2026-09-05; "Not started" as an implementation, but the plan itself is being actively iterated |
| nlnet-application.md | STALE | 2026-08-12 | funding draft; see dedicated section below |
| object-versioning.md | STALE | 2026-08-12 (effective) | default (eliminated) view done; optional History view (step 5) still open; the 2026-09-13 touch was an unrelated clipboard file-split commit |
| package-convention-repl-leaves.md | STALE | 2026-08-12 (effective) | omnetpp-julia half fully done (moved to that repo's `plan/done/`); inet-julia half open on steps 12, 13, 16, 16a |
| parallel-projection.md | STALE | 2026-06-23 | confirmed NOT STARTED — `ParallelProjection` appears nowhere outside this plan |
| printer-locality-findings.md | STALE | 2026-08-12 (effective) | static-audit notes feeding `printer-locality.md`; one finding already fixed and moved to `plan/done/syntaxtotext-delegation.md` |
| printer-locality.md | STALE | 2026-08-13 (effective) | harness + audit phase 1-2 done; 10/22 checked; long dormant |
| printer-locality-session-log.md | SUPERSEDED | 2026-08-12 | explicitly "historical record only," folded into `printer-locality.md` |
| projection-template-engine.md | STALE | 2026-08-12 (effective) | engine + Stage A (JSON) done; Stage B (SQL) leaves done/nodes open; Stage C in progress |
| select-a-widget-and-paste-it-into-a-tab.md | ACTIVE | 2026-09-17 | brand-new, 0/54 checked |
| simplest-syntax-document.md | STALE | 2026-08-31 (rename-only) | Phase 1-2 done; "option 2" of the template-blueprint gap remains |
| sql-insert-update-support.md | STALE | 2026-08-12 (effective) | model/projection/examples/tests done; `SqlParser.jl` still dispatches SELECT-only — the sole blocking item |
| sql-select-aggregation-support.md | STALE | 2026-08-12 | confirmed NOT STARTED — `GROUP BY` appears only in a "skip" comment in `SqlParser.jl` |
| syntax-tree-selection.md | STALE | 2026-08-12 | two deferred stretch slices remain, no test for either |
| test-suite-green.md | STALE | 2026-08-09 (effective) | items 1-7 and 12 done; items 8, 9, 10, 11, 13, 14 (6 of 7 remaining) still open |
| text-domain-kit.md | STALE | 2026-08-31 (rename-only) | Phase 1-2 done; Phase 3 item 3 explicitly "Not done — the next commit" |
| text-projection-config-into-document.md | STALE | 2026-08-12 | confirmed NOT STARTED (the base `ProjectionConfiguringProjection` exists, but not this plan's hoisting feature) |
| tooltip.md | STALE | 2026-08-12 | 3 of 4 example tooltip kinds (type/error/documentation) missing; multi-tooltip test missing |
| unify-projection-api-parameter-names.md | STALE | 2026-08-12 | confirmed NOT STARTED |
| word-wrapping-projection.md | STALE | 2026-08-12 | 3 remaining tests + `LineNumbering` wiring not done |
| workbench-feature-projections.md | STALE | 2026-08-12 (effective) | none of the six features (clipboard, dragging, tooltip, filtering, searching, highlighting) wired in the workbench example; the 2026-09-13 touch was an unrelated `ClipboardToAny.jl` file-split commit |
| xml-to-syntax-lisp-parity.md | STALE | 2026-08-12 | phases 1-4 and 6 done; Phase 5 (placeholders) is the only remaining work, "genuinely unblocked," but untouched since the audit |

## plan/tentative/ (10 files)

All ten carry the "generated with AI assistance as a brainstorming artifact... not a
specification" disclaimer except `from-scratch-structure.md`, `evaluate-operation-document-arg.md`
and `further-development.md`'s header (which also carries it).

| file | classification | last real date | note |
| --- | --- | --- | --- |
| annotation.md | STALE | 2026-05-27 | confirmed NOT STARTED — no `Annotation`/`AnnotationModule` type in `source/` |
| assistant-selection-ergonomics.md | STALE / possibly superseded | 2026-06-18 | a reaction to one 40-round assistant transcript; overlaps in spirit with the newer, more considered `assistant-api-consolidation.md` (pending) and `assistant-recovers-from-a-miss.md` (done) — not explicitly marked superseded, worth a human check |
| evaluate-operation-document-arg.md | UNCLEAR | 2026-07-03 | open design question; current code already has `evaluate_operation(editor, op)` — status quo appears to have won by inaction, but no plan says so explicitly |
| filesystem-file-content-projection.md | STALE | 2026-06-28 | no substantive work since creation |
| from-scratch-structure.md | STALE | 2026-07-14 | a from-scratch package/layer/slice restructuring brainstorm; largely overtaken by concrete restructuring plans that did land (`package/ is flat`, `one-module-per-slice.md`, etc., all in `plan/done/`) |
| further-development.md | STALE | 2026-05-27 | original 19-section roadmap; see dedicated section below |
| gesture-help.md | SUPERSEDED | 2026-06-18 | the "one source of truth, gesture map → help" idea shipped via `plan/done/command-palette.md` and the `source/gesturehelp/` slice (`GestureHelpModule`, `GestureMap`, `CommandPalette`) — a different, already-done plan built the same goal |
| layout-extensions.md | STALE / partly done | 2026-06-24 | `StackLayout` item done; `ConstraintLayout` "promoted to its own plan" — but its own links (`../pending/constraint-layout.md`, and `search-input-widget.md`'s `../pending/anchored-layout.md`) are **broken**: both target files are now `plan/done/constraint-layout.md` and `plan/done/anchored-layout.md` |
| logging.md | STALE | 2026-05-27 | confirmed NOT STARTED — no logging module in `source/` |
| search-input-widget.md | STALE | 2026-06-15 | Stage 1 done (see `plan/done/search-input-widget.md` — **same base name, different folder**); Stage 2 (cell-reactive generic projections) and Stage 3 (floating overlay) open |

## plan/obsolete/ (8 files)

All eight are correctly filed — each states or clearly implies why it is dead. No action needed
beyond what is noted.

| file | note |
| --- | --- |
| codebase-review.md | 2026-05-28 sweep snapshot; items folded into other pending plans, no standalone action |
| concept-document.md | rejected "AI-native Concept knowledge layer" (pre-extracted `Concept` JSON documents for AI context). Relevant precedent for the documentation rewrite's AI-native framing: this specific mechanism was proposed and not built — no rationale recorded in the commit message |
| concept-test.md | companion validation plan for concept-document.md, same fate |
| db-catalog.md | superseded by `plan/done/database-instance-catalog-sql.md` |
| example-with-selection-helper.md | small example-authoring helper proposal, superseded |
| master-detail-document.md | design direction dead; partly salvaged into `component-document.md` (itself still pending and still missing `ComponentToWidget`) |
| master-detail-editable.md | follow-up to master-detail-document.md, same fate |
| test-suite-atomization.md | superseded by `plan/done/atomic-example-catalog.md`; same cluster as `catalog-all-documents.md` and `discovered-example-catalog.md` above |

## plan/pending/nlnet-application.md — positioning claims (for the documentation rewrite)

1. Leads with **"AI-native"**: the README's Vision is cited as already putting "AI integration
   from the ground up" first, and the whole submission is told to foreground that framing.
2. Core claim: an AI can edit safely only because the editor is projectional — the document is
   structured data, editing maps to structural operations, so a malformed result is impossible
   by construction (no raw text to corrupt).
3. The assistant is **model-agnostic with a fully offline fallback**, exposed over the **open MCP
   protocol** — framed explicitly against "depends on US Big Tech AI" for NLnet's sovereignty
   angle (the assistant currently defaults to Claude, a US proprietary model).
4. The AI conversation is itself an editable ProjecturEd document — the editor edits its own AI
   session with the same machinery it uses for user data.
5. Twenty domain packages already work end-to-end with selection and cursor movement — **this
   count checks out** against `documentation/design/domain-inventory.md:5`.
6. Compares against Copilot/Cursor (text-based, can emit unparseable output), JetBrains MPS
   (proprietary, no AI), Xtext/Langium (grammar-based), Lamdu/Hazel (language-specific), Eve
   (discontinued), and its own Lisp predecessor.
7. Funded task list: harden the AI assistant + local/open-model backend (€10k), character-level
   editing across domains (€10k), full-domain click-to-select (€6k), undo/redo (€6k), **web-backend
   parity (€6k)**, accessibility pass (€6k), contributor docs (€3k), demo video (€3k). Total €50k.
8. **Stale/questionable facts found:**
   - "Web-backend parity" is pitched as a task to build, but a web backend already exists and has
     shipped features (`package/ProjecturedWeb`, `plan/done/web-backend.md`,
     `plan/done/web-main-window-in-tab.md`, `plan/done/web-collapse-double-toggle.md`) — the ask
     should be reworded as closing a parity gap, not building a web backend from nothing.
   - Undo/redo really is unimplemented (`grep -r UndoOperation` finds nothing) — this claim holds.
   - The admin-fields email is `levente.meszaros@gmail.com`; this differs from the address on file
     for this session (`levente.meszaros@omnest.com`) — plausibly deliberate (personal vs.
     company address for a FOSS grant), but worth a human confirmation before submission.
   - The whole "after summer 2026 … check now whether the call has reopened" checklist is
     dated to the 2026-08-12 audit; today is 2026-09-17, five more weeks have passed with no
     further edit to this file, so the call-status check is itself now stale.
   - No `LICENSE` file exists at the repository root today; the application commits to AGPL-3.0
     "on award," which is consistent with there being no licence yet, but the documentation
     rewrite should not assert an existing licence until this actually lands.

## plan/tentative/further-development.md — summary

The original (2026-05-27) 19-section brainstorm roadmap, explicitly not a specification. Section
1 (character-level editing, clipboard) and Section 2 (mouse/click-to-select, drag) describe a
pre-editing-features editor — both are long since implemented via many later, concrete done
plans, so these two sections read as obsolete history rather than a plan. Section 6 (domain
expansion) and most of Section 9-11 (graph editing/layout, graphical layout, editing projections)
are likewise substantially built now, each under its own later plan. Genuinely still-open
territory: Section 3 (undo/redo and object versioning — versioning shipped, undo/redo did not,
confirmed by `grep -r UndoOperation` finding nothing), Section 4 (transactional/uncommitted-change
editing), Section 15 (network transparency) and Section 16 (multi-user collaboration) — no code or
later plan addresses these three. The file functions today as a historical roadmap whose
"prioritized roadmap" ordering no longer matches reality; most of what it calls priority 1-2 is
done, and what remains open (network, collaboration, transactions) was never reached.

## Documentation links into plan/

`grep -rn "plan/done\|plan/pending"` across `documentation/`, `README.md`, `CONTRIBUTING.md` (no
such file), `CLAUDE.md` found 20 links. All resolve **except one**:

- **BROKEN:** `documentation/package/fsm/fsm.md:12` links
  `plan/pending/state-machine-domain.md`. That file does not exist; the plan moved and is now at
  `plan/done/state-machine-domain.md`. The fsm guide was not updated when the plan closed —
  exactly the failure mode the "move a plan to done" workflow is supposed to prevent.
- `documentation/requirement/delivery-roadmap.md:114` links `../../plan/tentative/annotation.md`
  (resolves fine) but the link **text** reads `editor/annotation.md` — a stale display label from
  before the doc reorg, harmless but inconsistent.
- All other links (`plan/done/repository-tree.md`, `syntaxtotext-delegation.md`,
  `kernel-layered-architecture.md`, `domain-layered-architecture.md`, `test-package-split.md`,
  `example-package-split.md`, `extras-example-split.md`, `consolidate-operations-replace.md`,
  `process-domain.md`, `cell-kind-documents.md`, `macro-default-field-values.md`,
  `plan/pending/live-example-construction.md`,
  `plan/pending/left-motion-stalls-on-introduced-text.md`) resolve correctly.

## 15 most recent plan/done/ entries and their documentation coverage

By the date of the commit that added them (`git log --diff-filter=A --name-only -- plan/done`):

| date | plan | documented in documentation/? |
| --- | --- | --- |
| 2026-09-16 | assistant-finds-the-api.md | **No** — `grep -rli "tool search\|find_tool\|tool_search" documentation` finds nothing. This is the assistant's tool-discovery mechanism, directly relevant to the new AI-native framing, and it is undocumented |
| 2026-09-16 | three-kinds-of-search.md | Partial — "search"/"meaning model" language appears in `documentation/package/kernel/agent.md` and `code-quality-rules.md`, not verified to be the same concept in depth |
| 2026-09-16 | file-reference-is-not-a-node.md | No hit for `FileReference` under `documentation/` |
| 2026-09-16 | one-table-widget.md | Yes — `WidgetTable` is listed as a single widget kind in `documentation/design/system-anatomy.md:214` and `documentation/package/widget/widget.md:69` |
| 2026-09-15 | transcript-folds.md | Yes — `documentation/package/conversation/transcript.md` covers folding/headers |
| 2026-09-14 | module-head-in-its-own-file.md | Referenced in `documentation/rule/naming-rules.md` |
| 2026-09-14 | projection-layer-is-one-module.md | Referenced in `documentation/rule/naming-rules.md` |
| 2026-09-14 | divide-graph-and-text.md | Unclear — no exact-phrase hit; `graph`/`text` package split is not spelled out plainly in `domain-inventory.md` as of this check |
| 2026-09-14 | qualified-extension-sweep.md | No hit for "qualify"/"qualified" in `documentation/rule/naming-rules.md` |
| 2026-09-13 | one-module-per-slice.md | **No — and worse, contradicted.** See Top Findings below |
| 2026-09-12 | declared-api-is-a-list-of-names.md | No hit for "declared_api"/"declared API" under `documentation/` |
| 2026-09-10 | widget-sizing-rules.md | No exact-phrase hit in `documentation/package/widget/widget.md` |
| 2026-09-10 | split-pane-inset.md | Yes — `WidgetSplitPane` covered in `documentation/package/widget/widget.md` |
| 2026-09-09 | ollama-backend.md | Yes — "ollama" appears in `agent.md`, `system-anatomy.md`, `architecture-invariants.md`, `package-rules.md` |
| 2026-09-01 | repository-tree.md | Yes — `documentation/rule/naming-rules.md` cites it |

## Top findings of this area

1. **`documentation/rule/division-terminology.md:38` is contradicted by a plan four days old.**
   It says "One layer (or slice) contains one or more modules." `plan/done/one-module-per-slice.md`
   (moved to done 2026-09-13) records that the collapse is done: 60 of 62 slices now declare
   exactly one module (only `graph` and `text` are still multi-module, and those are being split
   further, not merged). This is the canonical vocabulary document named in the repository's own
   `CLAUDE.md` as "how everything is named" — it must be corrected before anything else in the
   rewrite relies on it.
2. **The assistant's tool-discovery mechanism is undocumented.** `plan/done/assistant-finds-the-api.md`
   (2026-09-16, the single most recent plan closure) and its sibling `three-kinds-of-search.md`
   describe how the in-editor assistant finds the right tool among many — the exact mechanism the
   new framing's "AI integration from the ground up" headline depends on — and no document under
   `documentation/` names it.
3. **Broken link:** `documentation/package/fsm/fsm.md:12` still points at
   `plan/pending/state-machine-domain.md`; the plan is at `plan/done/state-machine-domain.md`.
4. **Two broken links inside `plan/tentative/`:** `layout-extensions.md` and `search-input-widget.md`
   both link `../pending/constraint-layout.md` and `../pending/anchored-layout.md`; both targets
   are now in `plan/done/`.
5. **A near-complete architecture rewrite is sitting in `plan/pending/`.** `naming-rule-violations.md`
   and `naming-rule-renames.md` (374 renames, "executed except §0.3") are 3-4 days old and 99% done
   — blocked only on the `graph`/`text` slice split. Once that lands, both close and their content
   (the naming law, `test_naming()`, the abbreviation list) is exactly the kind of material the
   naming-rules.md guide should absorb.
6. **`nlnet-application.md` overstates the web backend's absence.** It asks for €6,000 to build
   "web-backend parity," but `package/ProjecturedWeb` and three `plan/done/` entries
   (`web-backend.md`, `web-main-window-in-tab.md`, `web-collapse-double-toggle.md`) show a web
   backend already shipped; the ask needs to be reframed as closing a parity gap.
7. **A three-plan cluster around one goal:** `catalog-all-documents.md` (pending, workstream 4
   open), `discovered-example-catalog.md` (pending, explicitly superseded), and
   `test-suite-atomization.md` (obsolete) all orbit `plan/done/atomic-example-catalog.md`. The
   two pending files should be resolved (moved or closed) together rather than surveyed as three
   unrelated open items.
8. **`gesture-help.md` (tentative, a brainstorm) already shipped — under a different plan.** The
   `source/gesturehelp/` slice (`GestureHelpModule`, `GestureMap`, `CommandPalette`,
   `GestureMapToSyntax`) and `plan/done/command-palette.md` deliver the same "one source of truth"
   idea this brainstorm proposed. The tentative file should move to obsolete, not stay as an open
   idea.
9. **`plan/tentative/search-input-widget.md` and `plan/done/search-input-widget.md` share a file
   name across folders**, both about the same feature at different stages. Anyone grepping the
   base name without the folder will get a half answer; worth a rename before the rewrite cites
   either.
10. **`plan/tentative/further-development.md` is the original, pre-implementation roadmap** (2026-05-27)
    and is now mostly obsolete-by-completion: Sections 1-2 (editing, mouse) describe a state of the
    editor that no longer exists. Only undo/redo, transactional editing, network transparency and
    multi-user collaboration (Sections 3-4, 15-16) remain genuinely unaddressed anywhere in the
    tree — those four are the real gaps worth restating in fresh documentation, not the whole file.
11. **`plan/obsolete/concept-document.md`** proposed an "AI-native" pre-extracted `Concept`
    knowledge layer for AI context efficiency, explicitly predating the current framing request;
    it was marked obsolete with no rationale recorded. Worth a quick sanity check that the
    documentation rewrite isn't about to reinvent the same rejected mechanism.
12. **Roughly 40 of the 53 pending plans are dormant since the 2026-08-12 audit pass** (5+ weeks,
    no substantive commit since), each self-reporting a specific, usually small, remaining item
    (a parser branch, a wiring step, a missing test). None were found to be secretly finished, but
    the volume itself is a documentation risk: a plan whose only remaining line is "wire X into Y"
    reads, from outside, exactly like a shipped feature — several (`sql-insert-update-support.md`,
    `xml-to-syntax-lisp-parity.md`, `injecting-projection.md`) are close enough that a rewrite
    author skimming the plan title could mistakenly describe the feature as available.

---

# How omnet-julia builds binaries, and what projectured-julia can copy

Research report. All paths are relative to the named repository root
(`/home/projectured/workspace/omnet-julia` or
`/home/projectured/workspace/projectured-julia`) unless given absolute.

**Context found during the research.** `projectured-julia`'s
`plan/pending/documentation-rewrite.md` already contains the decision this
report answers to. Its §4.1, decision **D18** (line 572): *"An application
entry point before the posts — Yes. One command and one binary open any
number of files, in every supported format, in one window with the
assistant. The existing build system (`ProjecturedBuilder`,
`ProjecturedExecutable`) becomes more general, and it takes what applies from
the binary build of omnet-julia (Step 1)."* Step 1's checklist (line 610-691)
does not yet itemize D18's own tasks — this report is the missing survey that
a later edit of that plan would turn into checklist items. This report does
not edit that plan (out of scope: read-only research).

---

## Part 1 — omnet-julia's build system

### 1. Build entry point and command line

The front end is `source/tool/build_binary.jl` (528 lines), a thin dispatcher
that resolves `environment/tool` (`Pkg.resolve`/`instantiate`,
lines 42-43), loads `OmnetBuilder`, parses `ARGS`, and calls one Julia
function:

```
julia --project=environment/tool source/tool/build_binary.jl <what> [options]
```

`<what>` is one of `run`, `campaign_ui`, `ide`, `sample <name>`, `simulate`,
`demo` (`ALL_BUILDS`, line 79). The file's own header states the design
intent (lines 11-14): *"A build is a function, and a function is the better
interface... This file exists so that a person in a shell reaches the same
functions, and it must never grow a decision of its own."*

**A target is a Julia function, not a spec/table/DSL.** One function per
binary lives in `source/build/Program.jl` (688 lines):
`build_omnet_run_executable`, `build_omnet_campaign_ui_executable`,
`build_omnet_ide_executable`, `build_omnet_legacy_sample_executable`,
`build_omnet_simulate_executable`, `build_omnet_demo_executable`
(`Program.jl:43,219,251,295,425,512`). Each decides, in ordinary Julia code:

- **name** — `BUILD_NAMES` (`Program.jl:20-22`), e.g. `"run" => "omnet_run"`.
- **packages** — a `Vector{String}` of package names, e.g.
  `["OmnetRunner", "OmnetLegacyFormat", model...]` (`Program.jl:55-58`).
- **entry function** — an `Expr` interpolated as the body of `julia_main`,
  e.g. `:(OmnetRunner.main(ARGS))` (`Program.jl:64`), or for the window
  binaries a hand-built `Expr` tree calling `OmnetCampaignUi.run_campaign_window`
  / `OmnetIde.run_omnet_ide` with keyword flags spliced in
  (`Program.jl:146-157`).
- **workload** — an `Expr` run under `@compile_workload`, chosen per build
  (`:none`/`:minimal`/`:demo`/`:full` for `run`; a `Bool` for the window
  binaries) (`Program.jl:65-67`, `158-161`).
- **command-line options** — a `Usage` value (`source/build/Usage.jl:54-58`)
  naming the flags *that binary* answers (`--backend=`, `--llm=`, `-f <file>`,
  …); the generated module refuses any flag not listed
  (`AppPackage.jl:184-190`).
- **resources / fonts / icons** — `fonts::Bool` bundles the TrueType faces
  (`Executable.jl:719-750`); `assets` copies a directory beside the binary,
  e.g. `"demo/catalog" => "share/omnet/catalog"` (`Executable.jl:752-774`,
  used at `Program.jl:541`). No icon mechanism exists (this project ships no
  desktop icon).

The library function every build function calls is `build_executable` in
`source/build/Executable.jl:332-517` — one function with ~30 keywords
(`name`, `packages`, `main`, `workload`, `preferences`, `fonts`, `assets`,
`usage`, `log_level`, `incremental`, `trim`, `cpu_target`, `output`,
`compile`, `reactive`, `tracked`, `server`, `image`, `delta_optimization`,
`found`, `compact`, `trimmed`, …).

`build_binary.jl`'s own `OPTIONS` table (`build_binary.jl:96-180`) is **the
single source for both the `--help` text and the argument-to-build
refusal**: an option not in the build's own tuple is refused before it can
reach a `MethodError` (`build_binary.jl:346-350`), and the same table renders
`--help` (`_option_lines`, `build_binary.jl:198-207`).

### 2. The build environment

`environment/tool` (a `Project.toml` only — no code) is separate from
`environment/all` (the whole repository's dev environment) for two reasons,
both documented in code comments:

- **It patches `PackageCompiler`.** `environment/tool/Project.toml`'s
  `[sources]` points `PackageCompiler` at
  `../../../package-compiler-reactive` (a sibling checkout, the `reactive`
  branch), which caches the base sysimage and adds
  `materialize_app`/reactive rebuilds — capabilities the released package
  does not have.
- **It keeps the compiler out of every other environment.** `OmnetBuilder`
  loads PackageCompiler by `Base.PkgId` identity only inside the one function
  that compiles (`Executable.jl:17-18, 48-50`), specifically so a caller
  that only wants to see what a build *would* write needs no compiler
  installed (`OmnetBuilder.jl:18-19`).

`OmnetBuilder` (`package/OmnetBuilder/`) itself has a minimal `[deps]`
(`Dates`, `Pkg`, `Preferences`, `SHA`, `TOML` — `Project.toml:15-21`) and
names **no** simulator or presentation package. `get_package_directory`
(`source/build/Root.jl:37-44`) resolves a package by name at build time,
walking `package/<name>` first, then the `projectured-julia` sibling
checkout — which is how `OmnetBuilder` stays independent of what any binary
holds (`Root.jl:31-35`).

### 3. The build technique

**PackageCompiler `create_app`, explicitly not `juliac`/`--trim`.**
`source/build/Executable.jl:1-8` states why: `--trim` forbids dynamic
dispatch, and the engine dispatches on module type at every gate while a
`NetworkModel` reaches its builder through a registry, so it fails on this
program today. `source/build/Trim.jl` keeps a `:juliac`/`:sealed` option
behind `--trim` (off by default) purely to keep that failure measurable, and
says so at the top of the file (`Trim.jl:1-25`); the working trimmed path for
one sample is a separate shell pipeline
(`tool/trim-routing/build_phase.sh`, noted at `build_binary.jl:138`).

**Incremental by default, with a measured trade-off.** `_compile!`
(`Executable.jl:573-606`) calls `create_app` on top of the *running* Julia's
own sysimage (`incremental = true` by default) rather than a fresh one,
because a fresh image recompiles every stdlib into it —
`build_executable`'s docstring (`Executable.jl:293-309`) cites a measurement
on the routing sample: **390 s / 741 MB incremental** vs **741 s / 736 MB
non-incremental** — half the time for 0.7% more size. Only the
`build_..._distribution` functions force `incremental = false`
(`Program.jl:600,616,635,652,669,684`), because a distributed binary must not
carry a developer's whole base image (`build_distribution`'s
`check_relocation` refuses one that says `INCREMENTAL_MARK`,
`Distribution.jl:141-144`).

**A precompile workload** is spliced into the generated app module under
`@compile_workload` (`AppPackage.jl:194-199`), plus a repository-wide
`asset/precompile/WorkloadStatements.jl` file of recorded precompile
statements passed as `precompile_statements_file` (`Executable.jl:584,601`).

**A reactive/incremental-rebuild mode** (`--reactive`, `source/build/Reactive.jl`,
187 lines) is layered on top: `PackageCompiler.materialize_app` (from the
same patched branch) founds a store beside the output on the first build and,
on every later build of the same output, reads the tracked source files,
compiles only the edit, and links an overlay in front of the previous image —
measured at "about 4 minutes" to found vs "1.3 s in the compiler, 13 s with
the tool's start" to rebuild
(`documentation/guide/reactive-build-guide.md:6,13,15`). This is optional and
off unless a store exists or `--reactive` is passed.

**A special Julia build for prelinking — "prelink", not the compiler
itself.** `build_binary.jl`'s header (lines 20-26) and `Executable.jl:393-412`
explain: every image restore fixes up pointers for the address the image
lands at; a *prelinked* image has that restore already applied and written
back into the file (worth 213 ms → ~100 ms of start time per
`build_binary.jl:21`). Only a Julia runtime that knows
`--sysimage-prelink`/`--output-prelinked` can do this
(`_has_prelink_option()`, `Executable.jl:681`, checks
`:sysimage_prelink in fieldnames(Base.JLOptions)`). That runtime is
`workspace/julia-sysimage-prelink-wip/usr/bin/julia`
(branch `sysimage-prelink-1.13`, `build_binary.jl:23-24`). **A build on a
stock Julia is not refused** — `Executable.jl:406-412` turns `prelink` off,
logs an `@info` explaining where the special runtime lives, and proceeds
with an ordinary (slower-starting) binary. The build is **found**, not
invoked, by running `build_binary.jl` *with* that special Julia on `PATH`;
nothing in the builder shells out to find it automatically — the person
running the build chooses which `julia` binary starts the process.

A custom `launcher.c` (`Executable.jl:84-95`, file at
`source/build/launcher.c`) replaces PackageCompiler's own C entry point,
because the stock one calls `jl_eval_string` to reach `ARGS`, which compiles
the JuliaSyntax parser on every start (~90 ms). `link_executable!`
(`Executable.jl:638-675`) links this launcher plus the image's own object
archive (kept via `_object_archive_keyword`, `Executable.jl:58-81`) into one
`ET_EXEC` binary with `-no-pie` (so the restore, once prelinked, is valid at
one fixed address) and `--export-dynamic` (so `dlsym` can find the two image
symbols by name).

### 4. The runtime side

Every generated app module defines `Base.@ccallable function julia_main()::Cint`
(`AppPackage.jl:173`), written by `write_app_package`. It is the same for
every binary and is generic to `OmnetBuilder`, not simulator code:

1. **`_apply_log_level!()` first** (`AppPackage.jl:176`), which strips
   `--log-level=<level>` (or `OMNET_LOG_LEVEL`) out of `ARGS` and sets the
   global logger, before anything else reads `ARGS`
   (`AppPackage.jl:122-138`).
2. `--build-info` (always answered — `AppPackage.jl:177`), then, only when a
   build function supplied a `Usage`, `-h`/`--help` and `-v`/`--version`
   (`AppPackage.jl:178-190`), then a refusal of any unrecognized `-`-prefixed
   flag (`AppPackage.jl:184-190`) — **not read as something else**; the
   comment at `AppPackage.jl:182-183` recalls that before this existed,
   `--version` typed at the campaign binary was read as its project directory
   and it silently opened a window on a directory named `--version`.
3. The build function's own `main` expression, e.g.
   `OmnetRunner.main(ARGS)` (exit 0/1/2: finished / bad arguments / run
   failed — `OmnetRunner.jl:56-57`), or the window binaries' hand-built call
   into `run_campaign_window`/`run_omnet_ide`/`run_qtenv_window` with a
   constructed backend (`Program.jl:106,442, 146-157`).

**User-interface selection.** `OmnetRunner` holds exactly one interface,
`:cmdenv` (`OmnetRunner.jl:44-51`; `-u Cmdenv` is the only accepted value,
`-u Qtenv`/`-u Editor` are refused because the binary depends on nothing that
draws — `documentation/package/runner/runner.md:52-58`). The window binaries
construct one backend object at build time from `backend::Symbol` (`:sdl` →
`SdlBackend()`, `:web` → `WebBackend()`, `_build_omnet_window_executable`,
`Program.jl:92-106`); which backend package is even a dependency is decided
at build time, and if only one went in there is no `--backend` flag to pick
the other (`Program.jl:163-165`; the demo binary is the one exception with
both backends in, hence its own `--backend=web` flag,
`Program.jl:500-502,551-552`).

**Assets relative to the binary.** Fonts: `bundle_fonts!`
(`Executable.jl:719-750`) copies `<repo>/../projectured-julia/asset/font/*.ttf`
into `<output>/share/projectured/font`; the *runtime* lookup
(`ProjecturedStyle.font_file`, in the projectured-julia sibling) resolves a
baked-in checkout path first, then `PROJECTURED_FONT_DIR`, then
`Sys.BINDIR/../share/projectured/font` — the comment at `Executable.jl:731-733`
names exactly that function and that path convention. Other assets (e.g. the
demo catalog) are copied the same way (`bundle_assets!`,
`Executable.jl:752-774`) into `share/omnet/<name>`, and a build's own `main`
expression looks beside the executable first
(`joinpath(Sys.BINDIR, "..", "share", "omnet", "catalog")`,
`Program.jl:531`) before falling back to the compiled-in checkout path.

**Error reporting and exit codes.** A CLI binary (`omnet_run`) reports one
line on `stderr` and an exit code — no stack trace, because it is meant to be
driven by scripts running many runs (`OmnetRunner.jl:59-61,74-87`): 0
finished, 1 bad command line, 2 run failed. A window binary's own `main`
`Expr` prints one line to `stderr` and returns 1 for a bad command line
(`Program.jl:456-464`).

### 5. Output layout, build testing, time/memory

**Layout.** `build/<name>/{bin/<name>, lib/…, share/…}` — `build_output`
(`build_binary.jl:441-446`) defaults to `build/<name>` under the repository
`ROOT`; `--output=` overrides it. `strip_bundle!` (`Executable.jl:621-635`)
then moves the duplicate 382 MB `lib/julia/sys.so` out beside the bundle
(the binary already carries the image linked in) and removes `bin/julia`.
The object archive the executable was linked from is kept beside the bundle
too, at `<output>.object/sys-o.a` (`get_object_archive`, `Executable.jl:111`),
so a relink needs no rebuild.

**Testing a built binary.** `print_build_report!` (`Executable.jl:783-791`)
runs after every compile: it measures the bundle's size (`du -sb`) and how
long the binary takes to answer `--build-info` (chosen deliberately over
`--version`, because `--version` reaches a window binary's own `main` and one
such binary hung 60+ s waiting on a window — `get_smoke_flag`,
`Executable.jl:519-530`). `build_distribution` (`Distribution.jl:34-79`)
copies the bundle **outside the repository** (`get_staging_root`,
preferring `/var/tmp` over `/tmp` because `/tmp` is a `tmpfs` on this machine
and a 736 MB–1.4 GB copy there is a copy into RAM — `Distribution.jl:86-97`),
then `check_relocation` (`Distribution.jl:118-150`) starts the copy with an
empty `JULIA_DEPOT_PATH` and `JULIA_LOAD_PATH=""` from that other directory
and requires it to answer `--build-info` — the actual proof the bundle does
not silently read the checkout that built it (this is exactly the class of
bug the font-path fix above was written to fix, and the comment at
`Distribution.jl:7-11` says so explicitly). `test/build.jl` (660 lines) unit
tests the builder's text-generation and refusal logic (help text, flag
matching, log-level defaults, manifest handling, `INCREMENTAL_MARK`, the
prelink capability check) **without compiling anything**
(`test/build.jl:1-9`: *"Nothing here compiles... what this guards is the text
the builder writes and the refusals it makes"*).

**Time/memory, as stated in the repository.** Measured numbers appear
throughout the code comments and `documentation/guide/reactive-build-guide.md`
(cited above: 390 s/741 MB vs 741 s/736 MB incremental vs not; ~4 min to
found a reactive store, ~1.3–13 s to rebuild; native-only compile 222–260 s
vs three-target 333–347 s, `Executable.jl:270-276`). `plan/done/build-programs.md:746-748`
notes a build once died mid-compile from memory pressure caused by an
*unrelated* build sharing the same machine — evidence that a `create_app`
compile is memory-heavy enough to be killed by neighbors, not that this
repository caps it itself.

### 6. Generic vs. simulator-specific

**Generic — would work for any Julia application, and is already written
that way:**

- The whole shape of `Root.jl` / `Preference.jl` / `Usage.jl` /
  `AppPackage.jl` / `Executable.jl` / `Distribution.jl`: "a build is a
  function that writes a package, then compiles it" — nothing in this half
  names a simulator concept. `write_app_package` takes `packages`, `main`,
  `workload`, `usage`, `log_level` as pure arguments (`AppPackage.jl:54-58`).
- The `--build-info`/`--help`/`--version`/`--log-level` contract written into
  *every* generated app module (`Usage.jl`, the tail of `AppPackage.jl`).
- The prelink mechanism, the custom launcher, `strip_bundle!`, the object
  archive keeping, `check_relocation`/staging/archiving in `Distribution.jl`
  — all operate on "a directory PackageCompiler wrote" and know nothing
  about NED files or simulations.
- The font/asset bundling convention (`bundle_fonts!`/`bundle_assets!`) is
  actually *projectured-julia's own* runtime convention
  (`share/projectured/font`, `ProjecturedStyle.font_file`) — omnet-julia's
  builder implements the *build-time half* of a *projectured-julia* runtime
  contract that already exists but has no build-time implementation in
  projectured-julia itself (see Part 2 §3, Part 3 §1).
- `OmnetBuilder`'s independence from every package it might build
  (`get_package_directory` resolving by name/`Project.toml`, no `[deps]` on
  any simulator package) is a generic pattern, not a simulator one.

**Simulator-specific — must not be copied as-is:**

- Everything in `Program.jl`: `OmnetRunner`/`OmnetCampaignUi`/`OmnetIde`/
  `OmnetQtenv`/`OmnetLegacy*`/`OmnetPresentationExample` names, `-u Cmdenv`,
  `-f <ini>`/`-c <config>` parsing, `WINDOW_WRAPPERS` (`dragging`/`hover`),
  `LEGACY_SAMPLES`, the assistant `--llm=`/`--model=`/`--context=`/`--mcp`
  wiring being specific to `OmnetCampaignUi`/`OmnetIde`'s own entry
  functions.
- `MODULE_UNION`/`pin_module_union!` pinning in `AppPackage.jl:140-150` — a
  simulator-only performance fix for a module-type registry the simulator
  keeps.
- The `--models=`/NED-registration model of "a runner must not depend on the
  models it runs" — this is a simulator packaging concern.
- `WINDOW_REQUIREMENTS`/`LEGACY_REQUIREMENTS`/`ASSISTANT_REQUIREMENTS`
  distribution text (`Program.jl:574-587`) — simulator/OMNeT++-specific
  sentences for a README, though the *pattern* (a distribution function
  states per-binary target-machine requirements) is generic.

---

## Part 2 — projectured-julia's build system today

### 1. Build entry point and command line

**There is no command-line entry point at all.** The build is invoked from a
Julia session (a REPL, or a one-off `julia -e`), never from a shell script:

```julia
using ProjecturedSdl, ProjecturedBuilder
build_executable(make_workbench_app(SdlBackend))
```

(`documentation/package/executable/README.md:19-21`). This differs from
omnet-julia's `build_binary.jl` shell front end in the most basic way: there
is no `julia --project=... source/tool/build_binary.jl <what>` invocation to
copy from, and no `--help`/argument parser over the *builder itself* (only
the compiled *binary's own* `--help` exists, once built).

**A target is a `BuildSpec` struct** (`source/builder/Builder.jl:65-78`),
not a function per binary. Two named specs exist as thin wrapper functions,
`default_json_app(backend)` and `make_workbench_app(backend)`
(`Builder.jl:268,277-281`) — closer to omnet's "one function per binary" idea,
but there are only two, both producing the *same* generated app package
(`ProjecturedExecutable`); nothing plays the role of `BUILD_NAMES` +
per-target `Usage` + per-target asset/font list that omnet's `Program.jl`
has. `BuildSpec` fields decide:

- **name** — `app_name::String` (default `"projectured"`,
  `Builder.jl:66,80`).
- **packages** — *not* explicit per spec; always
  `LOCAL_CORE_PACKAGES = ["Projectured", "ProjecturedExample",
  "ProjecturedAnthropic", "ProjecturedOllama"]` (`Builder.jl:39-40`) plus
  each backend's own package (`Builder.jl:226-229`). Contrast with omnet's
  `packages` being computed *per build function* from only what that binary
  needs (`Program.jl:55-58` builds only `["OmnetRunner", "OmnetLegacyFormat",
  model]` — no window/SDL/Anthropic code at all in the batch binary).
- **entry function** — fixed: `ProjecturedExecutable.julia_main`
  (`Builder.jl:242`, the executable name is always the compiled module's
  `julia_main`, not a build-time-generated `Expr` per spec the way omnet
  writes one). The *behavior* of `julia_main` is instead selected at
  **runtime**, by reading `AppConfig.jl` constants that `render_app_config`
  wrote at build time (`source/executable/Executable.jl:144-177`, reading
  `APP_DOMAIN`/`APP_WORKBENCH`/`APP_BACKENDS`/… defined in the generated
  file).
- **workload** — `workload::Symbol` (`:none`/`:minimal`/`:demo`/`:full`,
  `AppConfig.default.jl:24-29`), consumed by `precompile_warmup()`
  (`Executable.jl:108-140`) which, for `:none`, only warms the baked
  `APP_DOMAINS`; anything else runs
  `ProjecturedExample.precompile_workload()` in full (no levels distinguish
  `:minimal`/`:demo`/`:full` today — `Executable.jl:116-120` says so
  explicitly: *"The workload has no levels any more, so anything that is not
  `:none` runs all of it."*).
- **command-line options** — no `Usage`-equivalent generated per spec.
  `print_help()` (`Executable.jl:16-43`) is hand-written once in
  `ProjecturedExecutable`, deriving its text from the same `AppConfig`
  constants (`APP_FILE_BACKED`, `APP_EXPOSE_BACKEND`, …) rather than being
  supplied per binary by the spec author, and it is not build-refused the
  way omnet's flag matcher is — `parse_runtime_args`
  (`Executable.jl:53-77`) just throws `"unknown option: $a"` on any
  unrecognized `-`-flag.
- **resources / fonts / icons** — **none are bundled by the builder.** No
  `fonts`/`assets` keyword exists on `build_executable`
  (`Builder.jl:191-194`); `_compile!` (`Builder.jl:215-249`) calls only
  `PackageCompiler.create_app(exe_dir, output; precompile_execution_file,
  executables, force)` — no `fonts=true` equivalent, no asset directory
  copy. (See Part 3 §1 for why this matters: the runtime already looks for
  `share/projectured/font`.)

### 2. The build environment

There is **one** environment shared by everything, `environment/all`
(`Project.toml`+`Manifest.toml` only, no code —
`package-rules.md`'s own description: *"an environment... holds a
Project.toml and a Manifest.toml and no code at all"*). There is no
omnet-style `environment/tool` that isolates PackageCompiler from the rest
of the dev session. Consequences visible in the code:

- `ProjecturedBuilder`'s own `[deps]` is just `Pkg`
  (`package/ProjecturedBuilder/Project.toml:16`) — the same "builder depends
  on nothing it builds" discipline as `OmnetBuilder`, and the same reason
  given in the file's own comment (`Project.toml:6-13`): PackageCompiler is
  `@eval import`ed inside `_compile!` (`Builder.jl:238`), not declared, so a
  caller that only wants the generated `AppConfig.jl` (`compile=false`) pays
  nothing for it (`Builder.jl:181-183,198`).
- But `_compile!` activates `exe_dir` (= `package/ProjecturedExecutable`)
  directly and `Pkg.develop`s the local packages + adds PackageCompiler
  **into that same package's environment** (`Builder.jl:219-236`) — there is
  no separate, gitignored, resolver-only environment the way
  `environment/tool` is; the app package's own `Project.toml`/`Manifest.toml`
  double as the build environment. `ProjecturedExecutable`'s `[deps]`
  (`package/ProjecturedExecutable/Project.toml:6-13`) is static and lists
  `ProjecturedSdl`, `ProjecturedAnthropic`, `ProjecturedOllama` unconditionally
  — every build today resolves and (via `Pkg.develop`) locally links those
  regardless of `BuildSpec.backends`/`domains`, unlike omnet's
  per-build-function-computed `packages` list.
- No package-compiler fork/patch is used: `haskey(...) || Pkg.add("PackageCompiler")`
  (`Builder.jl:234`) takes whatever released version resolves — no reactive
  rebuild capability, no cached-base-sysimage patch.

### 3. The build technique

**PackageCompiler `create_app` only — no `juliac`/`--trim` in the build
package**, though `tool/juliac-trim/` (README + four scripts:
`hide.jl`, `mutable_check.jl`, `probe.jl`, `sealed_patch.py`, `sealed.sh`)
and `documentation/guide/static-compilation-guide.md` (203 lines) hold a
**measurement**, not a build path: the guide states the `--trim`
verifier's `max_methods=3` rule, measures it against this kernel's own
abstract types (`Projection`: 410 direct subtypes, `IoMap`: 70, `Operation`:
54 — `static-compilation-guide.md:66-73`), and concludes
*"No code in this repository uses the technique yet"*
(`static-compilation-guide.md:114`). So `--trim` is further from usable here
than in omnet-julia, which at least has one working sample pipeline
(`tool/trim-routing/`); projectured-julia's abstract-type fan-out is the
*same* obstacle omnet's kernel dispatch hits, and the guide is pure research.

**Not incremental, not reactive, no prelink, no cpu-target choice, no
strip-metadata, no filter-stdlibs.** `_compile!`
(`Builder.jl:215-249`) passes only three keywords to `create_app`:
`precompile_execution_file`, `executables`, `force`. There is no
`incremental`/`cpu_target`/`trim`/`prelink` knob anywhere in
`ProjecturedBuilder` — every build is, in omnet's vocabulary, a plain
non-incremental, native-only, unprelinked `create_app` run. No object
archive is kept, no custom launcher is linked, `strip_bundle!` has no
counterpart (the redundant `lib/julia/sys.so` PackageCompiler writes stays
inside the bundle).

**A precompile workload** exists and is config-driven:
`source/executable/Precompile.jl` (16 lines) is the
`precompile_execution_file` `create_app` runs; it `include`s
`ProjecturedExecutable` and calls `precompile_warmup()`
(`Executable.jl:108-140`), which — unlike omnet's per-target workload
`Expr` — is one function serving every `BuildSpec`, driven entirely by the
baked `AppConfig` constants (a real generalization already present here that
omnet does not have in quite this form, since each omnet build writes its
own workload `Expr`).

**No special Julia build is needed or referenced.** Nothing in
`ProjecturedBuilder` checks for or asks about a prelink-capable Julia; the
concept does not appear anywhere in `source/builder/` or
`source/executable/`.

### 4. The runtime side

`julia_main` (`source/executable/Executable.jl:144-183`) is the single entry
point compiled for *every* `BuildSpec`; behavior comes entirely from the
`AppConfig` constants `write_app_config`/`render_app_config`
(`Builder.jl:118-158,166-169`) wrote at build time — this is a real
generalization: one compiled entry function, config-driven, versus omnet's
one *generated* entry expression per build function.

- **Argument parsing**: `parse_runtime_args` (`Executable.jl:53-77`) — a
  hand-rolled loop recognizing `--help`/`-h`, `--version`/`-v`,
  `--backend[=]KIND`, and one bare `FILE` argument; anything else `error`s.
  No `--log-level`, no `--build-info` (omnet's builder-owned flags have no
  equivalent here at all — `--build-info`/`--log-level` are entirely
  omnet-builder inventions not reflected in `ProjecturedBuilder`).
- **UI/backend selection**: `resolve_backend` (`Executable.jl:81-88`) picks
  among `APP_BACKENDS` (a `NamedTuple` of friendly-name → type, baked by
  `render_app_config`, `Builder.jl:141,149`) only when
  `APP_EXPOSE_BACKEND` was set at build time; otherwise `--backend` is
  refused (`Executable.jl:83-84`). This mirrors omnet's "a flag exists only
  over what the binary holds" rule (`Program.jl:163-165`) closely.
- **Domain/content selection**: `resolve_domain`
  (`Executable.jl:93-95`) → `domain_for_path`
  (`example/projectured/FileEditor.jl:116-119`) picks a domain by file
  extension among the baked `APP_DOMAINS`, defaulting to `APP_DOMAIN`
  otherwise — this is the "any number of files, in every supported format"
  mechanism the goal describes, but see §6/Part 3 for how narrow
  `EDITOR_DOMAINS` is today.
- **Assets relative to the binary**: **none.** No font/catalog bundling and
  no `Sys.BINDIR`-relative asset lookup exists in `ProjecturedBuilder`. The
  runtime *style* package it compiles in, however, already contains exactly
  the lookup convention omnet's `bundle_fonts!` targets:
  `font_file`/`font_search_path` (`source/style/TrueType.jl:62-108`) checks,
  in order, the baked-in checkout path, `PROJECTURED_FONT_DIR`, then
  `normpath(joinpath(Sys.BINDIR, "..", "share", "projectured", "font"))`
  (`TrueType.jl:101-107`) — identical to the very path omnet's
  `bundle_fonts!` writes into (`omnet-julia/source/build/Executable.jl:742`).
  **The runtime half of font portability is already generic and shared; only
  the build-time copy step is missing, and it is missing from
  `ProjecturedBuilder`, not from the shared style code.**
- **Error reporting / exit codes**: `julia_main` catches everything, prints
  one line to `stderr` (`"error: " * sprint(showerror, e)"`), and returns 1;
  an `InterruptException` (closing the window) returns 0
  (`Executable.jl:144-177`). No distinct exit codes for "bad arguments" vs
  "run failed" the way `OmnetRunner.main` has (0/1/2) — projectured-julia
  only distinguishes 0 (clean) from 1 (anything else).

### 5. Output layout, build testing, time/memory

**Layout.** `build/bin/<app_name>` under the repository root
(`Builder.jl:8-10,192`; `README.md:30`: *"Output goes to `build/bin/projectured`"*)
— a flatter tree than omnet's `build/<name>/{bin,lib,share}` because nothing
here relocates `lib/julia/sys.so` or writes a `share/` tree; whatever
`create_app` writes by default stays as `create_app` wrote it.

**No build-testing step exists.** There is no `print_build_report!`, no
`build_distribution`/`check_relocation`/staging/archiving equivalent
anywhere in `ProjecturedBuilder`, and no dedicated test file
(`test/build.jl`'s counterpart does not exist — a repository-wide search
for `ProjecturedBuilder`/`BuildSpec`/`render_app_config` under `test/`
matches only `test/projectured/PackageGraphTest.jl`, which is the static
package-layering guard, not a builder-behavior test:
`PackageGraphTest.jl:75` lists `ProjecturedExecutable` among the leaves the
guard checks, and `PackageGraphTest.jl:173` carries a
`SIDE_EFFECT_DEPS` exception explaining that `ProjecturedExecutable` depends
on `ProjecturedAnthropic`/`ProjecturedOllama` for "a package that a leaf
loads for its side effect alone... the executable bakes the LLM backend this
way." No test ever calls `build_executable(...; compile=true)` and checks
what came out.

**Time/memory.** No measured numbers appear anywhere in
`ProjecturedBuilder`/`ProjecturedExecutable`/their documentation — only the
qualitative `@info` at `Builder.jl:239`: *"this takes several minutes."*
`plan/done/executable-builder-editor-configuration.md:144` similarly just
says *"multi-minute `create_app`."* No comparison of incremental vs
non-incremental, no bundle-size figure, no measured start time.

### 6. Generic vs. domain-specific in what exists today

- **Generic already**: `BuildSpec`'s reflection-based backend handling
  (`_backend_kind`/`_backend_module`/`_backend_needs_local`,
  `Builder.jl:29-32`) — deriving the friendly name, the owning package, and
  whether a local `develop` is needed purely from the backend *type*, so
  `ProjecturedBuilder` never names `SdlBackend` or `ProjecturedSdl` — is a
  clean generic pattern, arguably cleaner than omnet's (which still special-
  cases `:sdl`/`:web` by name at several call sites, e.g. `Program.jl:92-93,
  430-431`). `write_if_changed`-style "don't rewrite what didn't change" does
  **not** exist here (`write_app_config` always overwrites,
  `Builder.jl:166-169`) — a smaller inefficiency than omnet's (which found
  it cost 12.6 s+8.8 s of an 8-minute build, `omnet-julia/source/build/AppPackage.jl:220-222`
  — this omission is worth copying but is low priority next to the missing
  font bundling and the multi-minute always-full build).
- **The narrowness that is the real gap**: `run_file_editor`
  (`example/projectured/FileEditor.jl:169-181`) hard-codes
  `Saving is out of scope in v1` (docstring, `FileEditor.jl:166-167`) even
  though `EditorDomain` already carries a `save_file` field
  (`FileEditor.jl:33-43`) and `write_document_file`/`read_document_file`
  (`source/fileformat/DocumentFile.jl:36-64`) already dispatch generically by
  extension over **all eight** natural-notation domains
  (`register_natural_domain!` calls found in `source/json/JsonModule.jl:61`,
  `source/xml/XmlModule.jl:54`, `source/markdown/MarkdownModule.jl:68`,
  `source/rst/RstModule.jl:98`, `source/math/MathToSyntax.jl:676`,
  `source/julia/JuliaModule.jl:80`, `source/yaml/YamlToSyntax.jl:273`,
  `source/sql/SqlToSyntax.jl:2031`) plus `.pdoc`
  (binary snapshot, `source/serialization/`) and `.pred`
  (`source/serialization/PredFile.jl`, 289 lines). `EDITOR_DOMAINS`
  (`FileEditor.jl:56-77`), the registry `run_file_editor`/`build_file_editor`
  actually use, wires up only **four** of those eight: `:json`, `:xml`,
  `:sql`, `:julia` (`FileEditor.jl:57-76`). Saving through the workbench
  already works generically: `SaveWorkbenchEditorOperation`
  (`source/workbench/WorkbenchFile.jl:1-27`) calls the same
  `write_document_file` on `Ctrl+S` (`@gestures WorkbenchEditor`,
  `WorkbenchFile.jl:52-55`), format chosen by extension — so the missing
  piece for "opens files, in every supported format... `Ctrl+S` save" is
  **not** new save/load code; it is (a) registering the other four domains
  in `EDITOR_DOMAINS`, and (b) making `run_file_editor`/the executable always
  route through the workbench (or otherwise wire `Ctrl+S`) rather than the
  `save_file = nothing`/no-workbench path.
- **Nothing here is "simulator-specific"** the way omnet's `Program.jl` is
  domain-specific — projectured-julia's build code is already
  editor-domain-agnostic in the sense that matters (`BuildSpec.domains`,
  `EDITOR_DOMAINS`), it is simply narrower in what is wired up and thinner
  in build mechanics than omnet's.

---

## Part 3 — What to copy

### 1. Feature comparison table

| omnet-julia build feature | projectured has it? | copy? | how (files to add/change) | size |
| --- | --- | --- | --- | --- |
| Shell/CLI front end (`build_binary.jl`, one function per `<what>`, shared `OPTIONS` table refusing/help-listing flags per target) | No (Julia-session-only `build_executable(spec)`) | **Yes** | New `source/tool/build_binary.jl` (or `tool/build_binary.jl`) mirroring `build_binary.jl`'s dispatcher shape over `BuildSpec`-producing functions in `ProjecturedBuilder`; a new `environment/tool` (see below) to resolve it | Medium |
| Separate build environment (`environment/tool`, isolates PackageCompiler, optionally a patched fork) | No — builds resolve inside `package/ProjecturedExecutable`'s own environment | **Yes**, the isolation part; **No**, the patched-fork part (no reactive-rebuild need yet) | New `environment/tool/Project.toml` naming `ProjecturedBuilder` + `PackageCompiler` by `[sources]`/`[deps]`; stop `Pkg.develop`-ing into `package/ProjecturedExecutable` directly, generate a build-artifact package the way `write_app_package` does (below) | Medium |
| Per-build-function computed **minimal** package list (`OmnetRunner`'s binary holds no SDL/Anthropic code at all) | No — `ProjecturedExecutable`'s `Project.toml` statically lists SDL+Anthropic+Ollama for every build | **Yes** | Change `_compile!`/`write_app_config` to generate a fresh app package per `BuildSpec` (see `write_app_package`) instead of reusing one fixed `ProjecturedExecutable` package; only `Pkg.develop` what `spec.backends`/`spec.mcp`/assistant choice actually need | Large |
| `write_if_changed` (skip a recompile when the generated module is byte-identical bar a timestamp) | No — `write_app_config` always overwrites | **Yes** | Port `AppPackage.jl:210-240`'s pattern into `write_app_config` | Small |
| Font bundling (`bundle_fonts!` → `share/projectured/font`) | **No build step**, but the *runtime lookup* (`font_search_path`) already expects exactly this path | **Yes — and easy**, since the runtime contract already exists | Add a `fonts::Bool`/always-on copy step to `_compile!` copying `asset/font/*.ttf` into `<output>/share/projectured/font` | Small |
| Asset bundling (`bundle_assets!`, e.g. a catalog directory) | No | Only if a future binary needs a path-relative asset (e.g. example galleries); not needed for the plain file-editor binary | Add an `assets` keyword to `build_executable`, same pattern as omnet's | Small |
| `--build-info`/`--help`/`--version`/`--log-level` written once into every generated app module, refusing any other unknown flag against a declared `Usage` | Partial — `print_help`/`print_version`/`--backend` exist, hand-written per app, not builder-owned; no `--build-info`, no `--log-level` | **Yes** (at least `--build-info`; `--log-level` is a smaller win here since there's little to log) | Port `Usage`/`format_usage`/`collect_option_flags`/the builder-owned-flags block of `AppPackage.jl` into `Builder.jl`+`Executable.jl` | Medium |
| Custom `launcher.c` avoiding `jl_eval_string` at start | No | Maybe, later — a ~90 ms win, not urgent for a first entry point | Copy `source/build/launcher.c` + `link_executable!`/`_object_archive_keyword` | Medium |
| `strip_bundle!` (move `lib/julia/sys.so` beside the bundle, drop `bin/julia`) | No | Yes, once the binary is meant for distribution (saves ~380 MB in the shipped tree) | Port `Executable.jl:621-635` | Small |
| Incremental-by-default `create_app` (390 s/741 MB vs 741 s/736 MB) | No knob — behavior is whatever `create_app`'s own default is (`incremental=false` unless passed) | **Yes** | Add `incremental::Bool=true` to `build_executable`, pass through to `create_app` | Small |
| `cpu_target` (native default; a `--distribution` build compiles for several processor families) | No | Only when shipping to others' machines; not needed for a personal/dev binary | Add `cpu_target` keyword, default `"native"`; a future `build_distribution` uses the portable empty target | Small |
| Prelink (needs the special `julia-sysimage-prelink-wip` Julia; falls back gracefully) | No | **Optional / later.** A real ~100 ms start-time win, but adds a dependency on a sibling checkout most contributors won't have; the omnet code already degrades gracefully (logs and continues) so it is low-risk to add, but low priority for a first cut | Port `_has_prelink_option`/`prelink_executable!`, default `prelink=false` here until proven wanted | Medium |
| Reactive/incremental rebuild (`materialize_app`, a patched PackageCompiler fork) | No | **No, not yet.** projectured's iteration loop is normally the REPL (`jp`), not rebuilding a binary; the omnet team built this because their binaries are the *product*. Revisit only if binary-rebuild iteration becomes a real workflow | — | Large (needs the same sibling forks) |
| `--trim`/`juliac` path | Research only, no working build, on both sides (projectured's own `static-compilation-guide.md` shows the *same* `max_methods=3` wall against its own `Projection`/`IoMap` abstract types) | No | — | — |
| `build_distribution`/`check_relocation`/staged, empty-depot smoke test, README+sha256 archive | No | **Yes, eventually** — the exact class of bug (a baked-in checkout path) it exists to catch is *already latent* in projectured's font path | Port `Distribution.jl` wholesale, parameterized by `name`/`bundle`/`requirements`/`expect` | Medium |
| `print_build_report!` (size + smoke-flag start time, printed on every build) | No | **Yes** — cheap and gives the missing time/memory numbers this report had to note as absent | Port `Executable.jl:776-791`, using `--build-info` (once added) or `--version` as the smoke flag | Small |
| `test/build.jl` — unit-tests the builder's text generation/refusals without compiling | No | **Yes** | New `test/build.jl` (or under `package/ProjecturedBuilderTest`) exercising `render_app_config`, a ported `Usage`/flag-matcher, `write_if_changed` | Medium |
| One function per binary, each with its own `Usage`, deciding name/packages/entry/workload explicitly | Partial (`default_json_app`/`make_workbench_app` are the same idea, just two of them and less explicit about packages/usage) | **Yes**, extend the pattern to a third: the general file-opening entry point the goal describes | New function in `Builder.jl`, e.g. `make_editor_app(backend; domains=ALL_NATURAL_DOMAINS, ...)` | Small (once the package-list generalization above is done) |

### 2. Simulator-specific parts that must not be copied

- Any of `OmnetRunner`/`OmnetCampaignUi`/`OmnetIde`/`OmnetQtenv`/
  `OmnetLegacy*`/`OmnetPresentationExample` naming, `-u Cmdenv`, `-f <ini>`/
  `-c <config>` parsing, `WINDOW_WRAPPERS` (`:dragging`/`:hover`),
  `LEGACY_SAMPLES`/`LEGACY_MODEL_PACKAGES`, `MODULE_UNION`/
  `pin_module_union!`.
- The `--models=`/"a runner must not depend on the models it runs" packaging
  rule — specific to how OMNeT++ model libraries register NED types.
- `WINDOW_REQUIREMENTS`/`LEGACY_REQUIREMENTS` README sentences (an OMNeT++
  installation, `opp_run`, a display) — the *pattern* of a distribution
  function stating per-binary target-machine requirements is generic and
  worth copying; the sentences are not.
- The `--llm=`/`--model=`/`--context=`/`--mcp` flag-splicing `Expr`
  machinery in `_build_omnet_window_executable` is written specifically
  around `OmnetCampaignUi`/`OmnetIde`'s own keyword names
  (`Program.jl:118-133`) — the *idea* (expose an `--llm`/`--mcp` flag only
  when the assistant package went in) is exactly what D5/D18 in
  projectured's own plan ask for, but the code must be rewritten against
  `ProjecturedAssistant`'s actual keywords, not copied verbatim.

### 3. Risks

- **A special Julia build.** Prelinking needs
  `workspace/julia-sysimage-prelink-wip`'s branch. It is optional (omnet
  degrades gracefully on stock Julia) — safe to add later, but it is one
  more sibling checkout a contributor building `projectured` would need to
  know about if it is turned on by default. Recommendation: port the
  capability but default `prelink=false` until there's a reason to want the
  ~100 ms.
- **Memory and time of a build.** omnet-julia's own evidence
  (`plan/done/build-programs.md:746-748`) shows a `create_app` compile
  killed by memory pressure from an *unrelated* build sharing the same
  machine — directly relevant here, since this machine is shared right now
  (the task instructions forbid running a build for exactly this reason).
  projectured-julia currently has **no measured numbers at all** for its own
  `create_app` compile (only "several minutes," `Builder.jl:239`) — the
  first thing a copied `print_build_report!` should produce is that missing
  baseline.
- **Platform limits.** Both builds are effectively Linux-only in the code
  read (`Sys.KERNEL`/`Sys.ARCH` archive naming, ELF-specific `strip_bundle!`/
  `link_executable!`/`-no-pie`/`--export-dynamic` in omnet). Nothing in
  either repository's build code was seen handling macOS or Windows; porting
  `launcher.c`/prelink/`strip_bundle!` verbatim would carry that same
  Linux-only assumption into projectured.
- **SDL libraries and fonts inside the binary.** `PackageCompiler.create_app`
  bundles a package's own JLL artifacts (e.g. `SDL2_jll`) automatically —
  this is not something either builder does by hand, so it is not a gap to
  copy. Fonts *are* a real gap (Part 3 §1, first row of font bundling) since
  `create_app` does not know to copy a file a package only reaches through a
  compile-time-relative path outside its own artifacts — this is exactly
  what `bundle_fonts!` exists to work around, on both sides of this
  comparison (the runtime lookup is shared code).
- **The Ollama or Anthropic backend inside a binary.** Per D5/D6 in
  `plan/pending/documentation-rewrite.md` (line 574-575), Ollama is meant to
  be the system-wide default backend and Anthropic is meant to resolve the
  newest Claude model at runtime via the Models API — both are **runtime**
  behaviors, not build-time ones, so they do not change what the *builder*
  must do beyond what already happens (`LOCAL_CORE_PACKAGES` already
  `Pkg.develop`s both adapter packages into every build,
  `Builder.jl:39-40`). The risk is narrower than it sounds: baking both
  backends into one binary is already the status quo; what is missing is a
  runtime `--llm=`/`--model=` flag surface (omnet's exact pattern,
  `Program.jl:118-133`) so a user can choose, and a build-time `mcp`
  wiring check — `BuildSpec.mcp` exists and is threaded to `APP_MCP` →
  `run_file_editor(mcp=...)` already (`Builder.jl:76,154`;
  `Executable.jl:170`), so `--mcp` mainly needs a runtime flag, which is a
  small, already-scoped addition (`ProjecturedMcp`/`source/mcp/Mcp.jl`, not
  read in depth for this report).

### 4. A proposed shape for ProjecturEd

**Targets.** Keep the two-package split omnet-julia and
`documentation/rule/package-rules.md` already agree on (`package-rules.md:25-27`:
*"the build leaf is `ProjecturedExecutable`... with `ProjecturedBuilder`
beside it as the tool that drives the build"*):

- `ProjecturedBuilder` (tool, `package/ProjecturedBuilder/`) gains a
  `BuildSpec`-producing function for the general application, e.g.
  `make_projectured_app(backend; domains = ALL_NATURAL_DOMAINS, workbench =
  true, mcp = false, assistant = :ollama)`, alongside the existing
  `default_json_app`/`make_workbench_app`. `ALL_NATURAL_DOMAINS` would list
  all eight (`:json, :xml, :yaml, :markdown, :rst, :math, :julia, :sql`) once
  `EDITOR_DOMAINS` (`example/projectured/FileEditor.jl:56-77`) is extended to
  cover them and `run_file_editor` is made to save via the workbench for
  every one of them (Part 2 §6).
- `ProjecturedExecutable` (build leaf, `package/ProjecturedExecutable/`)
  keeps being the package `create_app` compiles, but per Part 3 §1's
  package-list row, it should become a **generated** package (the way
  omnet's `build/app/<name>/` is written fresh per build) rather than the
  one fixed, statically-`[deps]`'d package it is today — otherwise every
  build keeps paying for SDL+Anthropic+Ollama+workbench regardless of what
  was asked for.
- A `source/tool/build_binary.jl`-style shell front end lives beside
  `ProjecturedBuilder`, resolved by a new `environment/tool` (isolating
  PackageCompiler from `environment/all` the way omnet does), so the
  eventual command is:

  ```
  julia --project=environment/tool source/tool/build_binary.jl projectured
  build/projectured/bin/projectured [files...] [--backend sdl|web] [--mcp] [--assistant ollama|anthropic|none]
  ```

**The application binary's command line**, following the goal's sketch and
what the runtime side already supports or nearly supports:

- `[files...]` — positional, one editor tab per file, each domain chosen by
  extension via `domain_for_path`/`EXTENSION_DOMAINS`
  (`FileEditor.jl:100-119`) already generalized across all eight domains;
  today only one `FILE` argument is parsed (`parse_runtime_args`,
  `Executable.jl:53-77`) — accepting a list and opening one workbench tab per
  file is the multi-file generalization the goal asks for, built on the
  workbench's existing tab/`Navigator` machinery
  (`source/workbench/WorkbenchModule.jl`, `WorkbenchDocument.jl`,
  `WorkbenchToWidget.jl` all reference a `Navigator`).
- `--backend sdl|web` — already exactly this shape
  (`resolve_backend`/`APP_EXPOSE_BACKEND`, `Executable.jl:81-88`); needs
  `expose_backend_flag=true` and both backend types passed to `BuildSpec`.
- `--mcp` — `BuildSpec.mcp`/`APP_MCP` already exist end-to-end at the config
  level (`Builder.jl:76,154`; `Executable.jl:170`); only a runtime flag in
  `parse_runtime_args` is missing.
- `--assistant ollama|anthropic|none` — new: `parse_runtime_args` needs a
  case for it (mirroring omnet's `--llm=`, `Program.jl:124-133`), and
  `julia_main` needs to pass the choice down to wherever
  `ProjecturedAssistant`/workbench construct the assistant pane, matching
  D5/D6 of the documentation-rewrite plan (Ollama default, Anthropic
  newest-model lookup).
- `--help`/`--version` already exist; adding `--build-info` (Part 3 §1) is a
  small, worthwhile addition once the app package is generated per build
  (so there is a `BUILD_INFO` string to print).

**Saving** rides on what already exists and works: `Ctrl+S` via
`SaveWorkbenchEditorOperation`/`WorkbenchFile.jl:1-27`, format chosen by
extension through `write_document_file`. Making the general binary always
wrap content in the workbench (`workbench=true` in the new `BuildSpec`) is
what turns "opens and edits a file in memory" (the current documented
limitation, `documentation/package/executable/README.md:85-87`) into a
binary that actually saves — no new save code, only wiring.
