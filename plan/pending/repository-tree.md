# One dimension per level — the repository tree

**Status: pending, written 2026-08-31.**

**Goal:** give this repository the five top-level folders that omnet-julia has —
`example`, `source`, `test`, `package`, `environment` — so that a person who
opens the three repositories reads one tree, not three.

**Written from:** omnet-julia's
[plan/done/repository-tree.md](../../../omnet-julia/plan/done/repository-tree.md),
which did this move on 613 files and recorded what it cost. That plan is the
design. This one is the application of it to projectured-julia, plus the one
addition the owner asked for: the folders inside `source`, `test` and `example`
carry a **logical group** above the slice, so a person can navigate the 62
slices without a flat list of 62.

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

```
source/                            the system — what ships
  kernel/                          the seventeen layers, unchanged
    cell/  clock/  event/  device/  gesture/  backend/  document/
    reference/  selection/  operation/  binding/  iomap/  projection/
    tool/  llm/  agent/  editor/
  substrate/                       the twenty-eight substrate slices
    collection/  primitive/  domain/  serialization/  style/  component/
    projection/  reflection/  dragging/  focus/  versioning/  plot/
    graphics/  screen/  layout/  text/  widget/  syntax/  pane/
    clipboard/  tooltip/  inspector/  gesturehelp/  gesturelog/
    fileformat/  naturalprojection/  console/  pdf/
  domain/                          the twenty domain slices
    json/  yaml/  xml/  markdown/  rst/  book/  math/  julia/  sql/
    database/  filesystem/  graph/  chart/  sequencechart/  dbcatalog/
    formula/  fsm/  process/  conversation/  workbench/
  integration/                     the eight that own a third-party dependency
    sdl/  web/  odbc/  tulip/  video/  adaptagrams/  llm/  mcp/
  tool/                            the leaves and the build tool
    repl/  executable/  builder/  bench/

test/                              mirrors source/, group for group
  kernel/    cell/  clock/  document/  event/  gesture/  operation/
             reference/  binding/  backend/  editor/  agent/  layering/
  substrate/ document/  projection/  editor/  serialization/
  domain/    json/  yaml/  xml/  …          each with the role folders it has:
                                            document/  projection/  editor/
                                            serializer/
  integration/ sdl/  odbc/  tulip/  video/
  suite/     runtests.jl  PackageGraphTest.jl  ExportCollisionTest.jl
             tree.jl
  bench/     the four benchmark bodies

example/                           documents, galleries, and workload bodies
  kernel/    Harness.jl  BackendHeadless.jl  LlmFake.jl  LlmScripted.jl
  substrate/ document/  projection/  Harness.jl
  domain/    json/  yaml/  xml/  …          each with document/ projection/
  integration/ sdl/  odbc/  tulip/  adaptagrams/
  gallery/   Catalog.jl  Gallery.jl  DomainExamples.jl  FileEditor.jl
             DefaultBackend.jl  workspace/

package/                           flat — one directory per package, 116 of them
  Projectured/  ProjecturedKernel/  ProjecturedKernelTest/
  ProjecturedKernelExample/  ProjecturedJson/  ProjecturedJsonTest/  …
  each holding Project.toml, src/<Name>.jl, and ext/ where there is one

environment/                       Project.toml + Manifest.toml, never any code
  all/                             everything, for the full suite
  kernel/                          no SDL, no ODBC, no Tulip
  editor/                          what the binary compiles
  tool/                            the build tool's own closure

documentation/  plan/  asset/  bin/
```

## 5. The groups, and why these four

The owner asked for a logical group above the slice, and asked that the slice
folders themselves stay as they are. The four groups are **not new**. Each one
already exists in [documentation/packages.md](../../documentation/packages.md)
as a named set with a rule attached to it, and this plan only gives each set a
directory:

| group | what makes a slice a member | the rule that already holds |
| --- | --- | --- |
| `kernel/` | it depends on nothing | one package, seventeen layers |
| `substrate/` | it depends on the kernel and on other substrate slices, and owns no third-party dependency | the umbrella aggregates it |
| `domain/` | it is a document domain with a printer and a reader | the umbrella aggregates it; it owns no third-party dependency |
| `integration/` | it owns a third-party dependency | the umbrella does **not** aggregate it; a session names it |
| `tool/` | it is a leaf or a build tool | nothing may depend on it |

So the group boundary is the same boundary `test_package_graph()` already
asserts. That is the point: the tree tells the reader the rule the guard
enforces, instead of hiding it in a table.

**The membership is fixed by that rule, not by taste.** A slice that acquires a
third-party dependency moves from `substrate/` or `domain/` to `integration/`
and stops being aggregated, which is exactly what
[documentation/packages.md](../../documentation/packages.md) already says
happens.

Three slices need a decision that the rule does not make:

- [ ] **`package/assistant/`** is new and not yet committed. Decide whether it
      is a domain or a substrate slice, and place it accordingly. It also carries
      a `Manifest.toml`, which §3 forbids; that goes either way.
- [ ] **`package/projectured/`** is the umbrella. Its `main/` holds one file, the
      umbrella root, which becomes `package/Projectured/src/Projectured.jl` and
      leaves nothing in `source/`. Its 38 test files and 23 example files are
      cross-slice, so they go to `test/suite/`, `test/<group>/` and
      `example/gallery/` by what each one covers, not as a block.
- [ ] **`package/substrate/`** has no `main/` at all — it is a test and example
      stem over the 28 substrate slices. Its 78 test files and 42 example files
      go to `test/substrate/` and `example/substrate/`, and the two packages keep
      their names.

## 6. Group names collide with layer names, and that is the improvement

`llm`, `tool` and `projection` each name a kernel layer **and** a package. Today
those are `package/kernel/main/llm/` against `package/llm/`, which a reader has
to know to tell apart. After the move they are `source/kernel/llm/` against
`source/integration/llm/`, and the group segment says which is which. Keep both
names.

## 7. Where the things that are not source go

| today | after | why |
| --- | --- | --- |
| `package/<slice>/doc/*.md` (50 files, 19 slices) | `documentation/package/<slice>.md`, or a folder where a slice has several | `package/` holds no prose; omnet-julia has `documentation/package/` already |
| `package/repl/PrecompileStatements.jl` (12 775 lines) | `asset/precompile/` | a recording, beside the reference images |
| `package/repl/record/driver.jl` | `source/tool/repl/record/` | it is code |
| `package/executable/build/`, `build.log` | nothing — untracked output | a build artifact is not a folder of the design |
| `package/executable/builder/` | `package/ProjecturedBuilder/` and `source/tool/builder/` | the tool is a package like any other |
| the root `Project.toml` and `Manifest.toml` | `environment/all/` | the alias follows, see §10 |
| the 4 stray `Manifest.toml` | deleted | a package that doubles as an environment is the entanglement this tree undoes |
| `bench/` | `source/tool/bench/` (the package) and `test/bench/` (the bodies) | `ProjecturedBench` is a package; its four benchmark files are not source |

## 8. Steps

Each step is one commit. Do not run `test_all()` after each one — run the guard
and the narrowest suite the step touches.

1. [ ] **Write the guard.** `test/tree.jl`, ported from omnet-julia's, with the
       five rules of §3. Four of them are vacuous today because `source/`,
       `example/` and `environment/` do not exist. It must pass now, and every
       step below must keep it passing. Register it in the suite that
       `test_all()` runs.
2. [ ] **Move `source/`.** Five groups, 386 files. Of those, 60 are package
       **root** files and go to `package/<Name>/src/`, not to `source/`; 326
       move. The group folder is the only new level; the slice folders and
       everything under them move whole. Fix the root files' `include` paths in
       the same commit.
3. [ ] **Move `test/`.** 222 files, plus the 120 of the `projectured` and
       `substrate` stems, into the mirror tree of §4. Keep the role folders.
4. [ ] **Move `example/`.** 153 files, plus the 65 of the two stems.
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
       §9. `CLAUDE.md`, `README.md`, `documentation/`, every moved `doc/` file,
       and the seal list.
10. [ ] **Update the seal list.** Every entry in `CLAUDE.md`'s kernel inventory
        gains the `source/kernel/` prefix. The rules forbid a reorder, not a
        rename; each entry keeps its position and its mark.

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
  own directory. `example/gallery/Catalog.jl` is the one to check.
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

- No file is renamed, no module is split, and no `include` **order** changes.
  Paths only.
- The 17 kernel layer folders keep their names and their contents. The seal list
  gains a prefix and nothing else.
- No slice folder is split or merged. The group level is the only new level.
- `results/` and `build/` are not folders of the design. They appear when
  something runs, and `.gitignore` covers them.
