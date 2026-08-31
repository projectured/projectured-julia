# One dimension per level — the repository tree

**Status: pending, written 2026-08-31.**

**Goal:** give this repository the five top-level folders that omnet-julia has —
`example`, `source`, `test`, `package`, `environment` — so that a person who
opens the three repositories reads one tree, not three.

**Written from:** two things, and it matters which is which.

The **five folders and their rules** come from omnet-julia's
[plan/done/repository-tree.md](../../../omnet-julia/plan/done/repository-tree.md),
which did this move on 613 files and recorded what it cost. Take that part as
settled.

The **grouping inside them** comes from reading the 62 module docstrings in this
repository, and it is not borrowed from omnet-julia and not taken from
[documentation/packages.md](../../documentation/packages.md). §4 says what the
code turned out to say, and §6 gives the rule that decides each group. The first
draft of this plan used the documentation's `substrate` / `domain` /
`integration` split; the owner rejected it, correctly — it had no folder for the
five backends.

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

## 4. What the code says, which the documentation does not

[documentation/packages.md](../../documentation/packages.md) sorts the 62 slices
into "the kernel", "the twenty-eight packages of the substrate", "the twenty
domains" and "the packages that own a third-party dependency". Those four sets
are correct and they are useless as folders. **`substrate` means "the other
twenty-eight"**, and a folder whose rule is "everything else" tells a reader
nothing. It also hides real families. Read the module docstrings and four of them
appear at once:

**There are five backends, and the documentation files them in three places.**
`ConsoleBackendModule` renders a Text document to a terminal with ANSI colours.
`PdfBackendModule` walks a `GraphicsCanvas` and emits vector PDF. `SdlBackend`
opens a window. `WebBackend` serves the same tree over HTTP and WebSocket.
`ProjecturedVideo` reuses SDL's offscreen renderer and encodes an `.mp4`. All
five implement the same kernel seam, and today `console` and `pdf` are
"substrate" while `sdl`, `web` and `video` are "third-party". Nothing in the
tree says they are one family. They are the answer to "where do the pixels go",
and there are five answers.

**Five more packages are the same shape as a backend, for a different seam.**
`ProjecturedTulip` "adds a `solve_constraint_layout` method to the seam defined
in `ProjecturedLayout.ConstraintSolverModule`". `ProjecturedAdaptagrams` adds
`AdaptagramsLayout` to the `GraphLayoutEngine` seam. `ProjecturedOdbc`
"registers `make_database_adapter(:odbc)`". `ProjecturedLlm` and
`ProjecturedMcp` fill the kernel's LLM and tool seams. Each is opt-in, each
names a seam a core package declared, and each is there to carry one third-party
dependency. That is a family with a rule, not a leftover.

**Seven packages are the same idea repeated seven times.** `DraggingState` is "a
transparent wrapper marking a sub-tree as a drag-and-drop reorder region".
`TooltipSource` is "a transparent wrapper marking a sub-tree as a tooltip
anchor". Versioning is "a domain-neutral overlay: any document subtree can carry
multiple versions", eliminated by `VersioningToAnyProjection` — and the clipboard
has `ClipboardToAny.jl`, the same name for the same move. Gesture help is
`GestureHelpDecorator`, gesture log is `GestureLogOverlay`. Every one is a
document-neutral wrapper plus the projection that removes it, and the tree files
them beside `Color.jl` and `CellVector.jl`.

**Everything else is a document, and the file names say which kind.** A file here
is `Foo.jl` (a document kind), `FooToBar.jl` (a projection), `FooParser.jl` or
`FooFile.jl` (a file seam), or `FooReferenceStep.jl` (a reference extension).
Follow the `FooToBar.jl` names and the pipeline draws itself: every domain prints
to `Syntax`, `Widget` or `Layout`; `SyntaxToText`; `TextToGraphics`,
`WidgetToGraphics`, `LayoutToGraphics`; then a backend. Five documents sit on
that spine and no domain owns any of them.

So the cut this plan uses is not "kernel, substrate, domain, third-party". It is
**the path a document takes to a person and back**.

## 5. The tree

```
source/                            the system — what ships
  kernel/                          the machine — the seventeen layers, unchanged
    cell/  clock/  event/  device/  gesture/  backend/  document/
    reference/  selection/  operation/  binding/  iomap/  projection/
    tool/  llm/  agent/  editor/

  value/                           plain values, not documents
    style/                         Color  Font  Image  Geometry  TrueType
                                   StyleStroke  StyleText
    plot/                          axis scaling, ticks, the data-to-pixel map,
                                   the colour and marker cycles

  document/                        DocumentCore.jl  Domain.jl — what a document
                                   kind must provide, and what the four below obey
    generic/                       a document kind no notation owns
      primitive/                   bool, number, string
      collection/                  vector, matrix, table, linked list
    stage/                         every notation prints through these
      syntax/  text/  component/  widget/  layout/  graphics/
    overlay/                       a document-neutral wrapper, and the
                                   projection that removes it
      versioning/  dragging/  tooltip/  clipboard/  inspector/
      gesturehelp/  gesturelog/
    notation/                      what a person reads and edits — 21 slices
      json/  yaml/  xml/  markdown/  rst/  book/  julia/  formula/  math/
      sql/  database/  dbcatalog/  filesystem/  graph/  chart/
      sequencechart/  fsm/  process/  conversation/  workbench/  assistant/

  projection/                      a projection that names no document kind
    combinator/                    filtering  searching  sorting  copying
                                   higherorder/  generic/  compound/
    natural/                       NaturalToGraphics — draws any document
    focus/                         the walk that finds the focusable leaf

  workspace/                       where documents sit while a person works
    screen/                        which windows exist
    pane/                          how a window is divided

  gateway/                         a document made from something that is not one
    serialization/                 a binary or text file
    fileformat/                    a natural text format, and embeds
    reflection/                    a live Julia object, bounded

  backend/                         where a rendered document goes
    sdl/  web/  console/  pdf/  video/

  engine/                          a seam the core declares and a third party fills
    tulip/  adaptagrams/  odbc/  llm/  mcp/

  tool/                            the leaves and the build tool
    repl/  executable/  builder/  bench/

test/                              mirrors source/, group for group
  kernel/    cell/ clock/ document/ event/ gesture/ operation/ reference/
             binding/ backend/ editor/ agent/ layering/
  document/  generic/  stage/  overlay/  notation/<name>/
             each notation keeping the role folders it has:
             document/  projection/  editor/  serializer/
  projection/  workspace/  gateway/  backend/  engine/
  suite/     runtests.jl  PackageGraphTest.jl  ExportCollisionTest.jl
             tree.jl
  bench/     the four benchmark bodies

example/                           documents, galleries, and workload bodies
  kernel/    Harness.jl  BackendHeadless.jl  LlmFake.jl  LlmScripted.jl
  document/  stage/  notation/<name>/  each with document/ and projection/
  backend/   sdl/
  engine/    odbc/  tulip/  adaptagrams/
  gallery/   Catalog.jl  Gallery.jl  DomainExamples.jl  FileEditor.jl
             DefaultBackend.jl  workspace/

package/                           flat — one directory per package, 116 of them
  Projectured/  ProjecturedKernel/  ProjecturedKernelTest/
  ProjecturedKernelExample/  ProjecturedJson/  ProjecturedJsonTest/  …
  each holding Project.toml, src/<Name>.jl, and ext/ where there is one

environment/                       Project.toml + Manifest.toml, never any code
  all/                             everything, for the full suite
  kernel/                          no backend but console, no engine
  editor/                          what the binary compiles
  tool/                            the build tool's own closure

documentation/  plan/  asset/  bin/
```

The 62 slices, counted by group:

| group | slices |
| --- | ---: |
| `kernel/` | 1 |
| `value/` | 2 |
| `document/` — the rule itself | 1 |
| `document/generic/` | 2 |
| `document/stage/` | 6 |
| `document/overlay/` | 7 |
| `document/notation/` | 21 |
| `projection/` | 3 |
| `workspace/` | 2 |
| `gateway/` | 3 |
| `backend/` | 5 |
| `engine/` | 5 |
| `tool/` | 4 |
| **total** | **62** |

Two of the 62 own no source at all — the `projectured` and `substrate` stems,
which are test and example packages over other slices. §9b says where their
content goes, and the two slices they replace in the count are `builder` and
`bench`, which are packages today inside another slice's directory.

## 6. The rule that decides each group

A group is worth a folder only when a one-line rule decides its membership and a
person can apply the rule without asking. These are those rules:

| group | a slice belongs here when | how many |
| --- | --- | ---: |
| `kernel/` | it depends on nothing | 1 |
| `value/` | it defines a value a document carries and is not itself a document | 2 |
| `document/generic/` | it is a document kind that no notation owns | 2 |
| `document/stage/` | every notation prints through it on the way to a backend | 6 |
| `document/overlay/` | it wraps any subtree, and a `…ToAny` or decorator projection removes it | 7 |
| `document/notation/` | a person reads and edits it directly | 21 |
| `projection/` | it is a projection that names no document kind | 3 |
| `workspace/` | it arranges other documents for a person | 2 |
| `gateway/` | it makes a document out of something that is not one | 3 |
| `backend/` | it implements the kernel's backend seam and puts a rendered document somewhere | 5 |
| `engine/` | it fills a seam a core package declared, and carries a third-party dependency | 5 |
| `tool/` | nothing may depend on it | 4 |

Three of these rules are checkable, and each one becomes an assertion in
`test/tree.jl`:

- **Every non-standard-library dependency in the repository lives under
  `backend/` or `engine/`.** Measured today: HTTP, JSON3, ModelContextProtocol,
  MathOptInterface, Tulip, FFMPEG, Libdl, SDL2_jll, SimpleDirectMediaLayer,
  DBInterface, ODBC and Tables, in exactly those two groups and nowhere else.
  `console/` and `pdf/` are pure Julia and sit in `backend/` on the seam they
  implement, not on a dependency they carry.
- **Nothing under `document/notation/` reaches `backend/` or `engine/`.** A
  notation prints to a stage; a stage reaches a backend.
- **Nothing depends on `tool/`.** That is `test_package_graph()`'s leaf rule,
  which already exists.

The gain over "substrate" is that a new slice now has an answer. A live-query
adapter for a second database is `engine/`. A curses backend is `backend/`. A
"mark this subtree read-only" wrapper is `document/overlay/`. Under
"substrate" all four were the same folder.

## 7. Four placements that needed an argument

**`console/` and `pdf/` are backends even though they carry no third-party
dependency.** The documentation groups by dependency, so it files them with
`ProjecturedCollection`. Their own docstrings say `ConsoleBackendModule` and
`PdfBackendModule`, and `console` even documents where it leaves the pipeline —
"the pipeline stops at `SyntaxToText` and does not run `TextToGraphics`". Group
by what a slice **is**, and a dependency is then a fact about it, not its
address.

**`component/` is a stage, not a widget.** Its docstring draws the chain itself:
`Document → Component → Widget → Graphics → Screen`. The slice holds its document
kind and not yet its projection — `ComponentToWidget` is unwritten — so it is the
one stage that does not stage anything today. Put it beside the five that do, and
the gap is visible instead of hidden.

**`natural/` is a projection, not a gateway.** `NaturalToGraphics` "projects
almost any document to a `GraphicsCanvas`" and is "built entirely from existing,
already-bidirectional projections". The word *natural* is shared with
`fileformat`'s natural text format and means something else there. Two slices,
two groups, one word — keep both names and let the group disambiguate.

**`assistant/` is a notation.** The slice is new and not yet committed:
`Assistant.jl`, `AssistantTurn.jl`, `AssistantToWidget.jl`. A document a person
reads and edits, with a projection to a stage — that is the notation rule
exactly, so it joins the 21 rather than starting a group. It also carries a
`Manifest.toml`, which §3 forbids; that goes either way. If the assistant later
grows a wire protocol of its own, the protocol is an `engine/` slice and the
document stays here.

## 8. Where a projection file lives inside a slice

The move never has to split a slice, because the repository already follows one
convention and it is worth writing down:

> A projection lives with its **source** document, unless the source is a generic
> document kind, in which case it lives with its **target**.

`JsonToSyntax.jl` is in `json/`, `SyntaxToText.jl` in `syntax/`,
`TextToGraphics.jl` in `text/`, `VersioningToAny.jl` in `versioning/` — source.
`CollectionToSyntax.jl` and `PrimitiveToSyntax.jl` are in `syntax/`,
`PrimitiveToText.jl` in `text/`, `ObjectToWidget.jl` in `widget/` — target,
because `collection` and `primitive` name no notation and would otherwise
accumulate a file for every stage.

## 9. Group names collide with layer names, and that is the improvement

`llm`, `tool`, `backend`, `projection`, `document` and `device` each name a
kernel layer **and** something outside the kernel. Today those are
`package/kernel/main/llm/` against `package/llm/`, which a reader has to know to
tell apart. After the move they are `source/kernel/llm/` against
`source/engine/llm/`, and the first segment says which is which. The pairing is
not an accident: the kernel layer **declares** the seam and the outside slice
**fills** it. Keep both names, and read the pair as the seam and its filler.

## 9b. The two stems that own no source

`package/projectured/` and `package/substrate/` are not slices and get no folder
under `source/`:

- **`package/projectured/`** is the umbrella. Its `main/` holds one file, which
  becomes `package/Projectured/src/Projectured.jl`. Its 38 test files and 23
  example files are cross-group, so each one goes to the group it covers, or to
  `test/suite/` and `example/gallery/` when it covers all of them. Do not move
  them as a block.
- **`package/substrate/`** has no `main/` at all. Its 78 test files and 42
  example files cover the slices that are now spread over `value/`,
  `document/generic/`, `document/stage/`, `document/overlay/`, `projection/`,
  `workspace/` and `gateway/`. The two packages keep their names —
  `ProjecturedSubstrateTest` and `ProjecturedSubstrateExample` — because a
  package name is not a folder path. Their **contents** distribute by group.

That second one is the largest single piece of judgement in the move. Do it in
its own commit, and expect the group of a test to be obvious from the module it
imports.

## 10. Where the things that are not source go

| today | after | why |
| --- | --- | --- |
| `package/<slice>/doc/*.md` (50 files, 19 slices) | `documentation/package/<slice>.md`, or a folder where a slice has several | `package/` holds no prose; omnet-julia has `documentation/package/` already |
| `package/repl/PrecompileStatements.jl` (12 775 lines) | `asset/precompile/` | a recording, beside the reference images |
| `package/repl/record/driver.jl` | `source/tool/repl/record/` | it is code |
| `package/executable/build/`, `build.log` | nothing — untracked output | a build artifact is not a folder of the design |
| `package/executable/builder/` | `package/ProjecturedBuilder/` and `source/tool/builder/` | the tool is a package like any other |
| the root `Project.toml` and `Manifest.toml` | `environment/all/` | the alias follows, see §13 |
| the 4 stray `Manifest.toml` | deleted | a package that doubles as an environment is the entanglement this tree undoes |
| `bench/` | `source/tool/bench/` (the package) and `test/bench/` (the bodies) | `ProjecturedBench` is a package; its four benchmark files are not source |

## 11. Steps

Each step is one commit. Do not run `test_all()` after each one — run the guard
and the narrowest suite the step touches.

1. [ ] **Write the guard.** `test/tree.jl`, ported from omnet-julia's, with the
       five rules of §3. Four of them are vacuous today because `source/`,
       `example/` and `environment/` do not exist. It must pass now, and every
       step below must keep it passing. Register it in the suite that
       `test_all()` runs.
2. [ ] **Move `source/`.** Nine groups, 386 files. Of those, 60 are package
       **root** files and go to `package/<Name>/src/`, not to `source/`; 326
       move. The group folders are the only new levels; the slice folders and
       everything under them move whole, and `projection/` splits into its three
       named parts. Fix the root files' `include` paths in the same commit.
3. [ ] **Move `test/`.** 222 files, plus the 120 of the `projectured` and
       `substrate` stems, into the mirror tree of §5. Keep the role folders.
4. [ ] **Move `example/`.** 153 files, plus the 65 of the two stems.
5. [ ] **Flatten `package/`.** 116 directories, one per package, each holding
       `Project.toml` and `src/<Name>.jl`. Delete `entryfile` from every
       `Project.toml` — see §12. The 2260 `[sources]` entries all collapse to
       `../<Name>`.
6. [ ] **Repair the other two repositories.** 184 `[sources]` entries in
       omnet-julia and inet-julia name a path here. Do this in the same hour as
       step 5, and land all three; between the two commits neither of those
       repositories resolves.
7. [ ] **Make the environments.** Four: `all`, `kernel`, `editor`, `tool`. The
       root `Project.toml` and `Manifest.toml` become `environment/all/`. Delete
       the four stray Manifests.
8. [ ] **Move the prose and the recording.** §10's table, in one commit each for
       the doc folders and for `asset/precompile/`.
9. [ ] **Repair every relative markdown link by resolution.** Not by rule — see
       §12. `CLAUDE.md`, `README.md`, `documentation/`, every moved `doc/` file,
       and the seal list.
10. [ ] **Update the seal list.** Every entry in `CLAUDE.md`'s kernel inventory
        gains the `source/kernel/` prefix. The rules forbid a reorder, not a
        rename; each entry keeps its position and its mark.

## 12. What omnet-julia already paid for

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

## 13. The alias moves

`jp` is `julia --project=/home/projectured/workspace/projectured-julia`. After
step 7 it becomes `--project=…/projectured-julia/environment/all`, which is what
`jo` already does for omnet-julia. Change `~/.bashrc` in the same hour as step 7,
and say so, because a stale alias resolves to a directory with no `Project.toml`
and the failure reads as a broken package.

## 14. Not in this plan

- No file is renamed, no module is split, and no `include` **order** changes.
  Paths only.
- The 17 kernel layer folders keep their names and their contents. The seal list
  gains a prefix and nothing else.
- No slice folder is merged, and only one is split: `projection/` becomes
  `combinator/`, `natural/` and `focus/`, which are three packages today sharing
  one group. Every other slice moves whole.
- **No package is renamed and no dependency changes.** A group is a folder, not
  a module and not a `[deps]` entry. `ProjecturedConsole` keeps its name after
  it moves to `backend/console/`, and `documentation/packages.md` keeps its
  four-set table, which stays true.
- `results/` and `build/` are not folders of the design. They appear when
  something runs, and `.gitignore` covers them.
