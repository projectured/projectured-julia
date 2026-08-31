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
  all/                       everything, for the full suite
  kernel/                    no SDL, no ODBC, no Tulip
  editor/                    what the binary compiles
  tool/                      the build tool's own closure

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
| `package/executable/builder/` | `package/ProjecturedBuilder/` and `source/builder/` | the tool is a package like any other, and it gets its own slice |
| `bench/` | `source/bench/` (the package) and `test/bench/` (the bodies) | `ProjecturedBench` is a package; its four benchmark files are not source |
| the root `Project.toml` and `Manifest.toml` | `environment/all/` | the alias follows, see §10 |
| the 4 stray `Manifest.toml` | deleted | a package that doubles as an environment is the entanglement this tree undoes |

`builder` and `bench` are the only two new slice folders. Both are packages
today that live inside another slice's directory, and flattening `package/` gives
them a name of their own either way.

## 8. Steps

Each step is one commit. Do not run `test_all()` after each one — run the guard
and the narrowest suite the step touches.

1. [ ] **Write the guard.** `test/tree.jl`, ported from omnet-julia's, with the
       five rules of §3. Four of them are vacuous today because `source/`,
       `example/` and `environment/` do not exist. It must pass now, and every
       step below must keep it passing. Register it in the suite that
       `test_all()` runs.
2. [ ] **Move `source/`.** 386 files. Of those, 60 are package **root** files and
       go to `package/<Name>/src/`, not to `source/`; 326 move. Each slice folder
       moves whole, and `kernel/` moves whole with its seventeen layers. Fix the
       root files' `include` paths in the same commit, and update the seal list
       per §6.
3. [ ] **Move `test/`.** 222 files, one slice folder at a time, keeping the role
       folders inside each. `test/suite/` takes the cross-slice files.
4. [ ] **Move `example/`.** 153 files, the same way.
5. [ ] **Flatten `package/`.** 116 directories, one per package, each holding
       `Project.toml` and `src/<Name>.jl`. Delete `entryfile` from every
       `Project.toml` — see §9. The 2260 `[sources]` entries all collapse to
       `../<Name>`.
6. [ ] **Repair the other two repositories.** 184 `[sources]` entries in
       omnet-julia and inet-julia name a path here. Do this in the same hour as
       step 5, and land all three; between the two commits neither of those
       repositories resolves.
7. [ ] **Make the environments.** Four: `all`, `kernel`, `editor`, `tool`. The
       root `Project.toml` and `Manifest.toml` become `environment/all/`. Delete
       the four stray Manifests.
8. [ ] **Move the prose and the recording.** §7's table, in one commit each for
       the doc folders and for `asset/precompile/`.
9. [ ] **Repair every relative markdown link by resolution.** Not by rule — see
       §9. `CLAUDE.md`, `README.md`, `documentation/`, and every moved `doc/`
       file.

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
