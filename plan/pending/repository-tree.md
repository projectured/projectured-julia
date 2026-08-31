# One dimension per level — the repository tree

**Status: pending, written 2026-08-31.**

**Goal:** give this repository the five top-level folders that omnet-julia has —
`example`, `source`, `test`, `package`, `environment`. Inside them the 62 slices
stay flat, exactly as `package/` holds them today. Only `kernel` has folders
inside it, and those are the seventeen layers it already has.

**Written from:** omnet-julia's
[plan/done/repository-tree.md](../../../omnet-julia/plan/done/repository-tree.md),
which did this move on 613 files and recorded what it cost.

The sibling plan is
[inet-julia/plan/pending/repository-tree.md](../../../inet-julia/plan/pending/repository-tree.md).

## 1. The problem

A path is one-dimensional. A file here varies along four dimensions at once, and
three of them fight for the first segment:

| dimension | encoded in | times |
| --- | --- | --- |
| slice | folder `json/` · file prefix `Json…` · module name | 3 |
| package kind | folder `main/ test/ example/` · name suffix `…Test` `…Example` | 2 |
| role | folder `document/ projection/ editor/` · file name `JsonToSyntax.jl` | 2 |
| tooling artifact | `Project.toml` · `Manifest.toml` · the folder itself | mixed |

The package kind sits **below** the slice, at `package/json/test/`. That is the
wrong order. Tests and examples are the two things a person most wants to stop
seeing, and today each one costs 62 folds instead of one.

The tooling artifact has no level of its own at all. A `Project.toml` sits in the
same directory as the source it names, so a package and its code cannot be read
apart, and five directories have grown a `Manifest.toml` and become environments
by accident.

**The slice level is not part of the problem.** It is one folder per subject, it
is already flat, and every name in it is unique. It stays as it is.

## 2. What the repository has today

Measured on 2026-08-31, on `main`:

| | count |
| --- | ---: |
| `.jl` files | 777 |
| of which `package/*/main/` | 386 |
| of which `package/*/test/` | 222 |
| of which `package/*/example/` | 153 |
| slice directories under `package/` | 62 |
| `Project.toml` under `package/` | 116 |
| `Manifest.toml` anywhere | 5 — the root, plus 4 that are accidents |
| `[sources]` path entries | 2260 |
| `.md` files under `package/*/doc/` | 50, in 19 slices |
| `[sources]` entries in **other repositories** that name a path here | 184 — omnet-julia 150, inet-julia 34 |

Two directories already break the rules this plan writes down:

- `package/repl/` holds `PrecompileStatements.jl`, 12 775 lines. It is a
  recording that a person made by driving the editor, not code.
- `package/executable/` holds `build/`, a compiled binary tree, and `build.log`.

## 3. The five folders, and what each may not hold

- `source/` holds no `Project.toml` and no `Manifest.toml`. Source is material.
- `package/` holds one directory per package. Each holds `Project.toml`,
  `src/<Name>.jl`, and `ext/` if the package has an extension. Nothing else. No
  `Manifest.toml`, no second `.jl`.
- `environment/` holds `Project.toml` and `Manifest.toml` only. No `.jl` at all.
- `test/` holds nothing that ships.
- `example/` holds nothing that a `source/` file loads.

Each rule is a directory walk and costs under a second. **Write them before the
move.** A rule that you assert after a move records what happened to be true. A
rule that you assert before it says what you intended, and it fails the first
step that gets it wrong. omnet-julia wrote `test/tree.jl` first and it found a
violation on the tree as it stood.

## 4. The tree

`source/`, `test/` and `example/` each hold one folder per slice, in one flat
list, with the same name in all three. A slice that has no test or no example has
no folder there.

```
source/                      the system — what ships, 62 folders
  adaptagrams/  assistant/  book/  chart/  clipboard/  collection/
  component/  console/  conversation/  database/  dbcatalog/  domain/
  dragging/  executable/  fileformat/  filesystem/  focus/  formula/
  fsm/  gesturehelp/  gesturelog/  graph/  graphics/  inspector/  json/
  julia/  layout/  llm/  markdown/  math/  mcp/  natural/  odbc/  pane/
  pdf/  plot/  primitive/  process/  projection/  projectured/
  reflection/  repl/  rst/  screen/  sdl/  sequencechart/
  serialization/  sql/  style/  substrate/  syntax/  text/  tooltip/
  tulip/  versioning/  video/  web/  widget/  workbench/  xml/  yaml/

  kernel/                    the one slice with folders inside it — §5
    cell/  clock/  event/  device/  gesture/  backend/  document/
    reference/  selection/  operation/  binding/  iomap/  projection/
    tool/  llm/  agent/  editor/

test/                        the same names, one folder per slice
  json/    document/  projection/  editor/  serializer/
  kernel/  cell/ clock/ document/ event/ gesture/ operation/ reference/
           binding/ backend/ editor/ agent/ layering/
  substrate/  document/  projection/  editor/  serialization/
  projectured/  backend/  document/  editor/  projection/  reference/
                serializer/
  suite/   runtests.jl  PackageGraphTest.jl  ExportCollisionTest.jl
           tree.jl
  bench/   the four benchmark bodies

example/                     the same names again
  json/    document/  projection/
  kernel/  Harness.jl  BackendHeadless.jl  LlmFake.jl  LlmScripted.jl
  projectured/  Catalog.jl  Gallery.jl  DomainExamples.jl  FileEditor.jl
                DefaultBackend.jl  document/  projection/  workspace/

package/                     flat — one directory per package, 116 of them
  Projectured/  ProjecturedKernel/  ProjecturedKernelTest/
  ProjecturedKernelExample/  ProjecturedJson/  ProjecturedJsonTest/  …
  each holding Project.toml, src/<Name>.jl, and ext/ where there is one

environment/                 Project.toml + Manifest.toml, never any code
  all/                       everything, for the full suite — what `jp` loads

documentation/  plan/  asset/  bin/
```

Inside a slice folder nothing changes. `source/json/` holds `Json.jl`,
`JsonParser.jl`, `JsonToSyntax.jl` and `JsonFile.jl`, and `test/json/` keeps the
role folders `document/`, `projection/`, `editor/` and `serializer/` it has
today. `source/graph/` keeps its `omnetpp/` subfolder and `source/projection/`
keeps `generic/`, `compound/` and `higherorder/`, because those are the slice's
own structure and not a level this plan added.

## 5. Why the slices stay flat

A group level above the slice was drafted and dropped. What it cost, in the order
the problems appeared:

- **The obvious groups overlap, and a folder cannot hold an overlap.** `sdl`,
  `web` and `video` are backends *and* the three that reach an outside library. A
  slice gets one folder, so one of the two true statements has to be thrown away
  every time. Prose can say both. A path cannot.
- **A group forces a decision on every slice, including the ones not written
  yet.** Every draft needed a paragraph arguing where `console`, `component`,
  `natural`, `plot` and `assistant` belong, and a wrong call is a rename across
  2260 `[sources]` entries later.
- **The slice name is what a person searches for.** All 62 names are unique, and
  sorted they are one screen. A group hides a slice behind a guess about which
  group it landed in.
- **It removes the largest piece of judgement in the move.** With groups, the 78
  tests and 42 examples of the `substrate` stem had to be split across seven
  folders by hand. Flat, they stay in `test/substrate/` and
  `example/substrate/`, and step 3 becomes mechanical.

The grouping is not lost; it moves to where overlap is allowed.
[documentation/packages.md](../../documentation/packages.md) already carries it,
and it can say a slice is both a backend and a carrier of a third-party
dependency without contradicting itself.

## 6. `kernel` is the one slice with levels inside it

The seventeen layer folders under `package/kernel/main/` become
`source/kernel/<layer>/`, unchanged in name, in content and in include order.
They are not a grouping this plan invented: they are the kernel's layer ladder,
they are what the seal list in [CLAUDE.md](../../CLAUDE.md) is ordered by, and
`test_kernel_layering()` already walks them.

So every entry of that seal list gains the prefix `source/kernel/` and nothing
else. The rules of the list forbid a reorder, not a rename; each entry keeps its
position and its mark.

Six of those layer names — `llm`, `tool`, `backend`, `projection`, `document`
and `device` — also name something outside the kernel. `source/kernel/llm/`
against `source/llm/` is the same collision the repository has today between
`package/kernel/main/llm/` and `package/llm/`, and it reads the same way: the
kernel layer **declares** a seam, and the slice beside it **fills** that seam.

## 7. Where the things that are not source go

| today | after | why |
| --- | --- | --- |
| `package/<slice>/doc/*.md` (50 files, 19 slices) | `documentation/package/<slice>.md`, or a folder where a slice has several | `package/` holds no prose; omnet-julia has `documentation/package/` already |
| `package/repl/PrecompileStatements.jl` (12 775 lines) | `asset/precompile/` | a recording, beside the reference images |
| `package/repl/record/driver.jl` | `source/repl/record/` | it is code |
| `package/executable/build/`, `build.log` | nothing — untracked output | a build artifact is not a folder of the design |
| `package/executable/builder/` | `package/ProjecturedBuilder/` | the tool is a package like any other; it is one file, so it owns no source folder |
| `package/executable/main/Precompile.jl`, `AppConfig.default.jl` | `package/ProjecturedExecutable/src/`, beside the root | neither is library source: one is a PackageCompiler execution script, the other a config template whose generated sibling the build writes next to it, and both are found by `@__DIR__` |
| `package/adaptagrams/deps/` | stays in the package | `Pkg.build` runs `<pkgdir>/deps/build.jl`; `deps/` is Julia's choice like `src/` and `ext/` |
| `package/web/assets/` | `asset/web/` | a static asset, and the repository already has `asset/` |
| `bench/` | `source/bench/` (the package) and `test/bench/` (the bodies) | `ProjecturedBench` is a package; its four benchmark files are not source |
| the root `Project.toml` and `Manifest.toml` | `environment/all/` | the alias follows, see §10 |
| the 4 stray `Manifest.toml` | deleted | a package that doubles as an environment is the entanglement this tree undoes |

`bench` is the only new slice folder. `builder` becomes a package directory of
its own but owns no source, because it is a single file — like `sdl`, `web`,
`llm`, `mcp`, `odbc`, `tulip`, `video`, `adaptagrams` and the two umbrellas,
whose whole content is the root file the package holds. Eleven of the 62 slices
have no `source/` folder for that reason, which is why step 2 created 51 and not
62.

## 8. Steps

Each step is one commit. Do not run `test_all()` after each one — run the guard
and the narrowest suite the step touches.

**Step 8 runs before step 5, not after it.** Prose, the recording and the web
client all sit inside package directories, and the flatten's rule is that a
package directory holds a `Project.toml` and a `src/`. Moving them out first
means the flatten has one job.

1. [x] **Write the guard.** — done, `test/suite/tree.jl`. It found five
       violations on the tree as it stood, all of them the stray `Manifest.toml`
       of a package that had become an environment, and they went in the same
       commit. `package/repl/` is already at the flat depth, so the
       per-directory half of the package rule is gated on the whole folder
       rather than on each directory; it starts to bite at step 5.
       `test_tree()` is exported from `ProjecturedTest` and runs first in
       `test_all()`.
2. [x] **Move `source/`.** — done. **325 files** moved into 51 slice folders,
       and **51 root files** had their `include` lines rewritten to
       `../../../source/<slice>/…`. That prefix is right both now and after step
       5, because a package root file sits three levels below the repository
       root either way, so step 5 does not touch an include again.

       Every `include` inside a moved file is a sibling of it, so the whole
       subtree moved with its own links intact. Four things did not move
       themselves and had to be repaired by hand:

       - `source/style/Font.jl` and `source/kernel/tool/Documentation.jl` each
         name a depth to the repository root. Both were three or four levels
         down and are now two or three.
       - `package/repl/ProjecturedRepl.jl` names the recording driver, which is
         code and moved to `source/repl/record/`.
       - **The two static guards had gone blind.** `check_layering` was given
         the package folder as its source root, which after the move holds only
         the root file; it reported ten interface files "not on disk". The fix
         is `package_source_root(pkg)`, one helper in `CheckLayering.jl`, and 22
         call sites now pass `(package_source_root(X), pathof(X))`.
         `PackageGraphTest` was worse: its two walks over `package/*/main/` and
         its `@compile_workload` walk still **passed**, over almost nothing.
         Both now walk `source/` as well.

       The second of those is the one to remember. A guard that stops looking
       reports success, and only the first one failed loudly.
3. [x] **Move `test/`.** — done. **201 files** into 27 slice folders, and 27
       root files rewritten. Two files stayed with their package: the root, and
       `runtests.jl`, which `Pkg.test` looks for in the package directory and
       nowhere else. The guard allows it there by name.

       `test/suite/` holds only `tree.jl`. The umbrella's own suites are
       `test/projectured/`, because `projectured` is a slice like any other —
       that is what flat buys, and it is why the `substrate` stem's 78 files
       needed no judgement at all.

       The tree guard names the walkers it protects, and two of them moved in
       this step, so its list moved with them. `test_kernel()` is 1540/3/2 here
       and on clean main; `test_package_graph()` is 592/2 on both.
4. [x] **Move `example/`.** — done. **133 files** into 27 slice folders, 27 root
       files rewritten, and five directory constants redirected.

       That last part is the one worth knowing. Five example roots include
       through `const _PKG_DIR = @__DIR__` rather than by a literal path, so
       rewriting `include` lines would have missed them entirely. Each const now
       reads `normpath(joinpath(@__DIR__, "../../../example/<slice>"))`, and
       every `include(joinpath(_PKG_DIR, …))` under it works unchanged.

       Verified: 102 examples load, `test_json()` 169/169, `test_domain_examples()`
       green, `test_tree()` green. `ProjecturedAdaptagramsExample` cannot load on
       this machine — a database example opens a PostgreSQL ODBC connection at
       load time and the driver is not installed — and it fails identically on
       clean main.
5. [x] **Flatten `package/`.** — done. **117 directories**, one per package,
       each holding `Project.toml` and `src/<Name>.jl`. Every `entryfile` line is
       gone, and every `[sources]` entry collapsed to `../<Name>`, or to
       `package/<Name>` in the repository-root environment.

       Four things the flatten turned up:

       - **A manifest records paths.** Nothing resolved until `Pkg.resolve()`
         rewrote the root `Manifest.toml`. Do that before believing any failure.
       - **`bench/` was a package outside `package/`.** It is
         `ProjecturedBench`, so it moves in, and it is the 117th. Its three
         benchmark bodies go to `test/bench/` and `juliac-trim/` to `tool/`.
       - **That move made a third leaf visible.** `ProjecturedBench` loads
         `ProjecturedExample`, which only a leaf may do, and the guard had never
         seen it because it walked `package/` and the bench was outside. The leaf
         set is now one `_LEAVES` constant, and it names three.
       - **`deps/` stays in the package.** `Pkg.build` runs
         `<pkgdir>/deps/build.jl` and nowhere else, so the guard allows it beside
         `src/` and `ext/` as Julia's choice rather than this tree's.

       Verified: every stem loads; `test_kernel()` 1540/3/2, the clean-main
       baseline; `test_package_graph()` 709/2 — the same two pre-existing
       domain-edge failures, the count risen because there is a third leaf to
       check every package against.
6. [ ] **Repair the other two repositories.** 184 `[sources]` entries in
       omnet-julia and inet-julia name a path here. Do this in the same hour as
       step 5, and land all three; between the two commits neither of those
       repositories resolves.
7. [x] **Make the environments.** — done, and **one** rather than four. The
       root `Project.toml` and `Manifest.toml` are `environment/all/`, whose
       `[sources]` name `../../package/<Name>`. The five stray package manifests
       went in step 1.

       `kernel`, `editor` and `tool` are **not** created, and that is a decision
       rather than an omission: each already has an environment that is not a
       file this repository writes. A package directory activates as its own
       environment, so `julia --project=package/ProjecturedKernelTest` is the
       SDL-free run that `environment/kernel` would have been; the builder does
       `Pkg.activate(exe_dir)` on the executable's own package directory, which
       is `environment/editor`; and the build tool is
       `package/ProjecturedBuilder`. Writing three more files that duplicate
       those closures would give three more things to keep in step.

       **`julia --project=.` no longer works from the repository root, by
       design.** Eight documents and one module header said it; all nine now say
       `--project=environment/all`. §10 is the alias.
8. [x] **Move the prose and the recording.** — done, and done **before** step 5
       rather than after it, so the flatten has nothing left to carry. 33 guides
       from 19 slices and two READMEs now sit in `documentation/package/<slice>/`,
       the 12 775-line recording in `asset/precompile/`, and the web client in
       `asset/web/`.

       The editor's own documentation tool walked `package/*/doc/`. It now walks
       `documentation/package/<slice>/`, and the bare walk over `documentation/`
       skips that subtree — without the skip every slice guide is listed twice,
       under `kernel/cell` and under `package/kernel/cell`. Checked: 58 guides,
       no duplicate, every path on disk.
9. [x] **Repair every relative markdown link by resolution.** — done, and the
       resolution was git's own rename detection between the branch point and
       `HEAD`, so a link changed only where the exact file it named moved, and
       only to where it moved to.

       It took three passes, and the second is the one a rule would have missed:

       1. **From the linking file's current directory.** 668 links.
       2. **From the linking file's *old* directory**, for the 33 guides that
          moved themselves. A guide that said `../main/document/DocumentCopy.jl`
          resolved from `package/kernel/doc/`, and from
          `documentation/package/kernel/` the same text resolves to nothing the
          map has ever heard of. 22 links.
       3. **By unique basename**, for ten links that named a file that had
          already moved before this branch — `../main/math/Math.jl` had not been
          right for some time. One of the ten was ambiguous (`Math.jl` exists in
          the source and in two example folders) and was resolved by hand.

       Measured: **the move introduced 0 broken links.** The repository had 939
       distinct broken markdown links at the branch point and has 926 now, all
       926 in `plan/`, where a done plan cites a tree from before this branch.

       `CLAUDE.md`'s seal list header now names `source/kernel/`, and its first
       entry carries the note that a package root file is the one member that
       lives with its package. `README.md`'s layout table is the new tree.

## 8b. The full suite, diffed against clean main

Run on both sides, 47 minutes each:

| | clean main | this branch |
| --- | ---: | ---: |
| pass | 869 701 | 869 751 |
| **fail** | **484** | **484** |
| **error** | **3** | **3** |
| **broken** | **1585** | **1585** |

Fail, error and broken are identical, which is the result that matters. Every
difference in the pass column is accounted for:

- `repository tree` — the new guard, 1 assertion.
- `package dependency graph` 592 → 717. Three causes, all of them the guard
  seeing more: a third leaf to check every package against, `ProjecturedBench`
  inside `package/` at last, and `_is_main_package` widened to include the
  leaves and the build tool. That last one was a **regression I introduced and
  then measured**: the first version excluded them and quietly dropped two
  assertions from "every package declares exactly the packages it names", which
  is now 126 against clean main's 120.
- `DomainExamples` and `Printers` each **−34**. One example is not hermetic:
  `make_workbench_document_example` roots a `Workspace` at its own folder, and
  that folder lost the two files a package keeps — `Project.toml` and the root
  `.jl`. Fewer files listed, fewer atoms printed, fewer assertions. Nothing
  regressed; the example's input is the tree, so its count moves when the tree
  does.

  Left as it is, because this plan changes paths and not behaviour. Making it
  hermetic means pointing it at a fixture, the way `filesystem` already does,
  and that is a change worth its own decision.

## 9. What omnet-julia already paid for

Take these as facts, not as risks:

- **A package root is `src/<Name>.jl`, not `<Name>.jl`.** A flat root loads if
  `entryfile` says so, and `pkgdir` then throws. Every package here uses
  `entryfile` today, and `ProjecturedAdaptagrams.__init__` and the SDL asset
  paths call `pkgdir`. Step 5 must add the `src/` level, not only flatten.
- **Path repair by basename picks the wrong copy.** Resolve each path; do not
  rewrite by name. Common names — `Json.jl` exists in `main/`, `test/document/`
  and `example/document/` — give every one of them three candidates.
- **A page's file reference resolves from the catalog root**, not from the page's
  own directory. `example/projectured/Catalog.jl` is the one to check.
- **The failures a move produces are misleading by default.** A stale path in a
  gallery reads as a document that lost its content, not as a path error. Budget
  for diagnosis, not for the fix.

## 10. The alias moves

`jp` is `julia --project=/home/projectured/workspace/projectured-julia`. After
step 7 it becomes `--project=…/projectured-julia/environment/all`, which is what
`jo` already does for omnet-julia. Change `~/.bashrc` in the same hour as step 7,
and say so, because a stale alias resolves to a directory with no `Project.toml`
and the failure reads as a broken package.

## 11. Not in this plan

- No file is renamed, no module is split, no slice is split or merged, and no
  `include` **order** changes. Paths only.
- **No level is added anywhere.** `source/`, `test/` and `example/` are flat over
  the slices, and every folder inside a slice is one the slice already has.
- No package is renamed and no dependency changes. `documentation/packages.md`
  keeps its four-set table, which stays true and which no folder now has to
  encode.
- `results/` and `build/` are not folders of the design. They appear when
  something runs, and `.gitignore` covers them.
