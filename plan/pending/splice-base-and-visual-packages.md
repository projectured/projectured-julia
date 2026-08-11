# Splice the base and visual packages into the package folder

Turn `package/base` and `package/visual` into 28 peer packages under `package/`.
After this change the kernel is the only layered package. Every other package is
one concept, and the dependency direction is a package-to-package DAG.

Status: **in progress**. Part 1 is under way. The work happens in the
`worktree-splice-packages` worktree.

## Goal

- Delete `ProjecturedBase` and `ProjecturedVisual` as code packages.
- Give each concept folder its own package folder: `package/<stem>/main`.
- Keep `package/kernel` exactly as it is. It stays the one layered package.
- Write down the complete package table, so every `[deps]` list is exact and
  nobody depends on more than they use.

## What the split gives

- `ProjecturedTulip` depends on `ProjecturedLayout` alone, not on all of visual.
- `ProjecturedDatabase` depends on `ProjecturedKernel` alone. Today it lists
  Base and Visual and uses neither.
- `ProjecturedSdl` depends on Collection, Graphics, Screen and Style, not on
  the syntax, widget and text code it never touches.
- A change to `widget/` no longer invalidates the precompiled image of `sql`.

## Method

I built the graph from the source, not from the documents:

1. For every file under `package/base/main` and `package/visual/main`, I read
   the `module X` line and every `import ..XModule` / `using ..XModule` line.
2. I attributed each fragment file (a file with no `module` line) to the module
   of the file that includes it.
3. I mapped module to folder, then folder to folder.
4. I ran Tarjan on the module graph. **The module graph is acyclic.** The two
   cycles below exist only at folder level, so three file moves remove them.
5. For every other package I collected the same `..XModule` references. A
   submodule in Julia does not inherit the parent module's `using` bindings, so
   a `main` package must import each module by name. The `main` dependency
   lists below are therefore exact.

The `example` and `test` packages are different. They use the flat re-exported
namespace, so their dependency lists cannot come from import lines. Step 7 of
the migration says how to compute them.

## Part 1 — three file moves that break the two cycles

Do these first, on the current package layout. Each is a small, testable commit.

### Move 1 — the collection projections go to `projection/`

`base/collection/Sorting.jl` imports `IdentityProjectionModule`, and
`base/projection/compound/GenericCompound.jl` imports `SortingProjectionModule`.
That is the cycle.

- [x] `git mv package/base/main/collection/Sorting.jl package/base/main/projection/`
- [x] `git mv package/base/main/collection/Filtering.jl package/base/main/projection/`
- [x] Move the two `include` lines in `ProjecturedBase.jl` below the generic
      combinators. They already sat below them, so only the path changed.

Result: `collection/` holds documents only. `projection/` holds every
projection.

### Move 2 — `ReaderDefaults.jl` goes to `projection/`

`base/primitive/ReaderDefaults.jl` exists to disambiguate `read_intent` for
`RecursiveProjection` over `RuleIoMap`. It is projection code that names one
primitive operation.

- [x] `git mv package/base/main/primitive/ReaderDefaults.jl package/base/main/projection/`
- [x] Move its `include` line.

Result: `ProjecturedPrimitive` depends on the kernel alone.

### Move 3 — the focus walk leaves `WidgetModule`

`visual/layout/LayoutToGraphics.jl` imports `first_focusable_path`,
`last_focusable_path` and `_next_focusable_in` from `WidgetModule`, and
`visual/widget/WidgetToGraphics.jl` imports `LayoutToGraphicsModule`. That is
the second cycle.

Only one line of the focus walk is widget-specific:

```julia
_is_focusable_widget(w) = w isa FocusableWidget && !(getfield(w, :enabled)[] === false)
```

`_child_document_refs`, `_prepend_steps`, `_focusable_path` and
`_next_focusable_in` name only `Cell`, `Document`, `CellVector` and the
reference steps.

- [x] Create `visual/main/focus/Focus.jl` with `FocusModule`. Move
      `_child_document_refs`, `_prepend_steps`, `_focusable_path`,
      `first_focusable_path`, `last_focusable_path` and `_next_focusable_in`
      into it. Lines 2040 to 2145 of
      [Widget.jl](package/visual/main/widget/Widget.jl) hold them today.
- [x] Declare the open trait in `FocusModule`:
      `is_focusable_document(x) = false`.
- [x] In `WidgetModule`, add the one method:
      `FocusModule.is_focusable_document(w::FocusableWidget) = !(getfield(w, :enabled)[] === false)`.
- [x] Change the three importers to name `..FocusModule`:
      `layout/LayoutToGraphics.jl`, `widget/WidgetToGraphics.jl`,
      `widget/WidgetHoverTracking.jl`.
- [x] Move the `include("layout/LayoutToGraphics.jl")` line back into the
      layout block of `ProjecturedVisual.jl`. It no longer needs to wait for
      `widget/`.
- [x] Rename `_next_focusable_in` to `next_focusable_index` and export it.
      Three files import it. A private name that crosses a module boundary
      breaks the shared-helper rule of
      [architecture-rules.md](documentation/architecture-rules.md), and the
      splice turns that boundary into a package boundary.

Test after each move: `test_base()`, then `test_visual()`.

`package/repl/PrecompileStatements.jl` names 117 signatures through
`ProjecturedVisual.WidgetModule`, and the whole file names the module path of
every package. A stale entry is skipped by design, so nothing breaks. Record
the statements again after step 6.

## Part 2 — the new packages

28 packages come out of the two old ones. One file goes to an example package.

| new stem | package | from | files | lines |
| --- | --- | --- | ---: | ---: |
| `collection` | `ProjecturedCollection` | `base/collection` | 5 | 600 |
| `primitive` | `ProjecturedPrimitive` | `base/primitive` | 1 | 265 |
| `domain` | `ProjecturedDomain` | `base/domain` | 2 | 656 |
| `projection` | `ProjecturedProjection` | `base/projection` + 3 moved files | 19 | 1940 |
| `reflection` | `ProjecturedReflection` | `base/reflection` | 2 | 534 |
| `dragging` | `ProjecturedDragging` | `base/dragging` | 2 | 323 |
| `versioning` | `ProjecturedVersioning` | `base/versioning` | 2 | 492 |
| `serialization` | `ProjecturedSerialization` | `base/serialization` | 3 | 993 |
| `style` | `ProjecturedStyle` | `visual/style` | 7 | 2326 |
| `focus` | `ProjecturedFocus` | new, out of `widget/Widget.jl` | 1 | ~110 |
| `plot` | `ProjecturedPlot` | `visual/plot` | 2 | 869 |
| `graphics` | `ProjecturedGraphics` | `visual/graphics` | 3 | 1044 |
| `screen` | `ProjecturedScreen` | `visual/screen` | 3 | 672 |
| `layout` | `ProjecturedLayout` | `visual/layout` | 4 | 2509 |
| `text` | `ProjecturedText` | `visual/text` | 14 | 5092 |
| `widget` | `ProjecturedWidget` | `visual/widget` | 8 | 9350 |
| `component` | `ProjecturedComponent` | `visual/component` | 1 | 83 |
| `pane` | `ProjecturedPane` | `visual/pane` | 5 | 1995 |
| `syntax` | `ProjecturedSyntax` | `visual/syntax` | 6 | 3652 |
| `clipboard` | `ProjecturedClipboard` | `visual/clipboard` | 3 | 792 |
| `tooltip` | `ProjecturedTooltip` | `visual/tooltip` | 2 | 194 |
| `inspector` | `ProjecturedInspector` | `visual/inspector` | 3 | 270 |
| `gesturehelp` | `ProjecturedGestureHelp` | `visual/gesturehelp` | 6 | 910 |
| `gesturelog` | `ProjecturedGestureLog` | `visual/gesturelog` | 4 | 599 |
| `fileformat` | `ProjecturedFileFormat` | `visual/fileformat` | 3 | 623 |
| `naturalprojection` | `ProjecturedNaturalProjection` | `visual/naturalprojection` | 2 | 331 |
| `console` | `ProjecturedConsole` | `visual/backend/Console.jl` | 1 | 346 |
| `pdf` | `ProjecturedPdf` | `visual/backend/Pdf.jl` | 1 | 827 |

`focus` is new; the other 27 keep the name of the folder they come from. One
folder does not become a package: see Part 4.

## Part 3 — the complete dependency table

Every package in `package/` after the change. `Kernel` is a dependency of
almost everything, so the "depends on" column names it only where it is the
only dependency. A dependency in the table is **direct**: the package imports a
module of it. Julia needs each direct dependency in `[deps]`.

### The engine

| package | depends on | third-party |
| --- | --- | --- |
| `ProjecturedKernel` | — | — |

### The substrate that came out of base

| package | depends on | third-party |
| --- | --- | --- |
| `ProjecturedCollection` | Kernel | — |
| `ProjecturedPrimitive` | Kernel | — |
| `ProjecturedDomain` | Kernel | — |
| `ProjecturedSerialization` | Kernel | Serialization |
| `ProjecturedProjection` | Collection, Primitive | — |
| `ProjecturedReflection` | Collection | — |
| `ProjecturedDragging` | Collection | — |
| `ProjecturedVersioning` | Collection, Domain, Primitive | — |

### The substrate that came out of visual

| package | depends on | third-party |
| --- | --- | --- |
| `ProjecturedStyle` | Kernel | — |
| `ProjecturedComponent` | Kernel | — |
| `ProjecturedFocus` | Collection | — |
| `ProjecturedPlot` | Style | — |
| `ProjecturedGraphics` | Collection, Projection, Style | — |
| `ProjecturedScreen` | Collection, Graphics, Primitive | — |
| `ProjecturedLayout` | Collection, Focus, Graphics, Projection | — |
| `ProjecturedText` | Collection, Domain, Graphics, Primitive, Projection, Style | — |
| `ProjecturedWidget` | Collection, Focus, Graphics, Layout, Primitive, Projection, Reflection, Screen, Style, Text | — |
| `ProjecturedSyntax` | Collection, Domain, Primitive, Projection, Style, Text | — |
| `ProjecturedPane` | Collection, Domain, Dragging, Layout, Primitive, Projection, Widget | — |
| `ProjecturedClipboard` | Collection, Domain, Primitive, Text | — |
| `ProjecturedTooltip` | Screen | — |
| `ProjecturedInspector` | Screen, Style, Text | — |
| `ProjecturedGestureHelp` | Collection, Graphics, Projection, Screen, Style, Syntax, Text | — |
| `ProjecturedGestureLog` | Collection, Graphics, Projection, Style, Syntax, Text | — |
| `ProjecturedFileFormat` | Collection, Domain, Layout, Primitive, Projection, Serialization, Style, Syntax, Text, Widget | — |
| `ProjecturedNaturalProjection` | Collection, Domain, FileFormat, Layout, Primitive, Projection, Serialization, Style, Syntax, Text, Widget | — |
| `ProjecturedConsole` | Style, Text | — |
| `ProjecturedPdf` | Graphics, Style | — |

### The twenty domains

Each line is what the package's own `main` files import today, mapped onto the
new packages. Compare it with the current list, which is always
`Base, Kernel, Visual` plus other domains.

| package | depends on | plus these domains |
| --- | --- | --- |
| `ProjecturedDatabase` | Kernel | — |
| `ProjecturedChart` | Collection, Domain, Graphics, Plot, Style | — |
| `ProjecturedSequenceChart` | Collection, Domain, Graphics, Plot, Style | — |
| `ProjecturedGraph` | Collection, Graphics, NaturalProjection, Projection, Style | — |
| `ProjecturedYaml` | Collection, Domain, Primitive, Projection, Style, Syntax, Text | — |
| `ProjecturedFormula` | Collection, Projection, Style, Syntax, Text | Julia |
| `ProjecturedDbCatalog` | Collection, Projection, Style, Syntax, Text | Sql |
| `ProjecturedFsm` | Collection, Domain, FileFormat, Projection, Style, Syntax, Text | Graph, Julia |
| `ProjecturedProcess` | Collection, Domain, FileFormat, Projection, Style, Syntax, Text | Graph, Julia |
| `ProjecturedSql` | Collection, Domain, FileFormat, NaturalProjection, Projection, Style, Syntax, Text | — |
| `ProjecturedXml` | Collection, Domain, FileFormat, NaturalProjection, Projection, Serialization, Style, Syntax, Text | — |
| `ProjecturedJulia` | Collection, Domain, FileFormat, NaturalProjection, Projection, Serialization, Style, Syntax, Text | — |
| `ProjecturedJson` | Collection, Domain, FileFormat, NaturalProjection, Primitive, Projection, Serialization, Style, Syntax, Text | — |
| `ProjecturedMath` | Collection, Graphics, NaturalProjection, Primitive, Projection, Style, Syntax, Text | — |
| `ProjecturedBook` | Collection, Graphics, NaturalProjection, Primitive, Projection, Style, Syntax, Text | — |
| `ProjecturedFileSystem` | Collection, NaturalProjection, Primitive, Projection, Style, Syntax, Text, Widget | — |
| `ProjecturedConversation` | Collection, Domain, Layout, Primitive, Projection, Style, Syntax, Text, Widget | Json, Julia, Xml |
| `ProjecturedWorkbench` | Collection, FileFormat, Layout, Primitive, Projection, Style, Syntax, Text, Widget | Conversation, FileSystem, Json, Julia, Markdown, Xml, Yaml |
| `ProjecturedRst` | Collection, FileFormat, Layout, NaturalProjection, Primitive, Projection, Serialization, Style, Syntax, Text, Widget | — |
| `ProjecturedMarkdown` | Collection, FileFormat, Graphics, Layout, NaturalProjection, Primitive, Projection, Serialization, Style, Syntax, Text, Widget | — |

### The packages that own a third-party dependency

| package | depends on | plus these domains | third-party |
| --- | --- | --- | --- |
| `ProjecturedLlm` | Kernel | — | HTTP, JSON3 |
| `ProjecturedMcp` | Kernel | — | ModelContextProtocol |
| `ProjecturedTulip` | Layout | — | MathOptInterface, Tulip |
| `ProjecturedVideo` | Graphics | Sdl | FFMPEG |
| `ProjecturedAdaptagrams` | — | Graph | Libdl |
| `ProjecturedSdl` | Collection, Graphics, Screen, Style | — | SDL2_jll, SimpleDirectMediaLayer |
| `ProjecturedWeb` | Collection, Graphics, Screen, Style | — | Base64, HTTP, JSON3 |
| `ProjecturedOdbc` | Collection, Projection, Syntax, Text | Database, DbCatalog, Sql | DBInterface, ODBC, Tables |

### The aggregate and the leaves

| package | depends on |
| --- | --- |
| `Projectured` (umbrella) | Kernel, the 28 substrate packages, the 20 domains |
| `<Stem>Example` | `<Stem>`, the Examples below it |
| `<Stem>Test` | `<Stem>`, `<Stem>Example`, the Tests below it |
| `ProjecturedRepl` **(leaf)** | Projectured, Example, Test, Sdl |
| `ProjecturedExecutable` **(leaf)** | Projectured, Example, Llm, Sdl |
| `ProjecturedBuilder` (tool) | — |

The umbrella keeps its job. It is the front door a person loads, and it is the
one place the full set is written down.

## Part 4 — what goes somewhere else

Three folders do not become a package of their own.

### `base/backend/DefaultBackend.jl` goes to `ProjecturedExample`

52 lines. It picks a loaded `Backend` subtype by name with
`InteractiveUtils.subtypes`. It has exactly two callers, and both are examples:
`package/projectured/example/Gallery.jl` and
`package/projectured/example/FileEditor.jl`.

- [ ] `git mv package/base/main/backend/DefaultBackend.jl package/projectured/example/`
- [ ] Add `InteractiveUtils` to `ProjecturedExample`, and drop it from the
      substrate.

The alternative is a micro-package `ProjecturedBackendRegistry`. Do not take
it unless a `main` package needs `default_backend()`.

### `visual/backend/` becomes two backend stems

`Console.jl` and `Pdf.jl` are concrete backends with no shared code. They
become peers of `ProjecturedSdl` and `ProjecturedWeb`, which is what they are.
They carry no third-party dependency, so the umbrella still aggregates them.

### `visual/component/` stays one package, and it is nearly empty

`ComponentModule` is 83 lines and no other package imports it. The pending
plan [component-document.md](plan/pending/component-document.md) is what it
belongs to. Keep it as `ProjecturedComponent` rather than fold it into
`ProjecturedWidget`, because it imports no widget type at all.

## Part 5 — names

- `ProjecturedDomain` holds `DocumentCore.jl` and the `@domain` macro. The name
  says what the package is: the kit that defines what a document domain is. The
  twenty source domains are its consumers, not its namesakes. The old
  `package/domain` package that the twenty domains came out of no longer
  exists, so the name is free.
- `ProjecturedProjection` holds the domain-free projection algebra: the generic
  and higher-order combinators, `Searching`, `Copying`, `Sorting`, `Filtering`
  and `ReaderDefaults`.
- `ProjecturedFocus` is new. It holds the generic focus walk and the open trait
  `is_focusable_document`.
- `ProjecturedGraphics` and the existing `ProjecturedGraph` are different
  stems. Neither is a kind of the other.
- Every new package folder is lowercase and matches the old concept folder
  name, so `git log --follow` keeps working.

## Part 6 — the kinds

Today `base` has `main`, `test` and `doc`. `visual` has `main`, `example`,
`test` and `doc`.

**Split `main` first and split `example` and `test` last.** The example and
test files were written against the flat namespace, so a static import scan
cannot tell which package owns a name.

### doc

Move each guide to the stem it documents. Fold the two package architecture
documents into `documentation/architecture.md`.

| file | goes to |
| --- | --- |
| `base/doc/collection.md` | `package/collection/doc/` |
| `base/doc/bounded-sync.md` | `package/reflection/doc/` |
| `base/doc/versioning.md` | `package/versioning/doc/` |
| `base/doc/architecture.md` | fold into `documentation/architecture.md` |
| `visual/doc/graphics.md` | `package/graphics/doc/` |
| `visual/doc/pane.md` | `package/pane/doc/` |
| `visual/doc/syntax.md` | `package/syntax/doc/` |
| `visual/doc/text.md` | `package/text/doc/` |
| `visual/doc/widget.md` | `package/widget/doc/` |
| `visual/doc/architecture.md` | fold into `documentation/architecture.md` |

### example and test

The 17 document files and 20 projection files of `visual/example` map onto the
stems one to one by name. The 47 files of `visual/test` and the 15 files of
`base/test` map the same way. Do the split with a live symbol scan, not by
eye. Step 7 gives the procedure.

## Part 7 — the steps

Do the work in a git worktree, not in the main checkout. Commit each step.

1. **Break the cycles.** Do the three moves of Part 1 on the current layout.
   Run `test_base()` and `test_visual()`. Commit each move.
2. **Add the package skeletons.** Create `package/<stem>/main/Project.toml`
   for all 28, each with a fresh UUID, a `[deps]` block from the table of
   Part 3, and a `[sources]` block of relative paths
   (`{path = "../../collection/main"}`). Do not move any source yet.
   **Done.** A static scan of the module graph, run after Part 1, produced the
   same dependency set as the table of Part 3 for every one of the 28
   packages, and reported no folder cycle. The root `Project.toml` gains no
   entry here: a package whose entry file does not exist yet must stay
   invisible to the root environment.
3. **Move the source, lowest package first.** The order is a topological sort
   of Part 3: collection, primitive, domain, serialization, style, component,
   projection, reflection, dragging, focus, versioning, plot, graphics,
   screen, layout, text, widget, syntax, pane, clipboard, tooltip, inspector,
   gesturehelp, gesturelog, fileformat, naturalprojection, console, pdf.
   For each package:
   - `git mv` the folder to `package/<stem>/main/`;
   - write `package/<stem>/main/Projectured<Stem>.jl` with the module alias
     block its files need, and the `include` lines in their current order;
   - delete the moved `include` lines from `ProjecturedBase.jl` or
     `ProjecturedVisual.jl`, and add the matching
     `const XModule = Projectured<Stem>.XModule` alias there instead.
   `ProjecturedBase` and `ProjecturedVisual` become thin aggregators as the
   moves proceed. Nothing else in the repository changes yet, so every suite
   stays runnable at every commit.
4. **Rewire the 28 consumer packages.** Replace `ProjecturedBase` and
   `ProjecturedVisual` in each `main/Project.toml` with the exact set from
   Part 3. Change the `for _src in (…)` alias loop in each package root module
   to name the same set. Run that package's own suite.
5. **Delete the two aggregators.** Remove `package/base` and `package/visual`
   once no `main` package names them. Remove them from the root
   `Project.toml`, and add the 28 new `[deps]` and `[sources]` entries.
6. **Update the umbrella.** Put the 28 packages in the `import` list and in
   `_SOURCES` of [Projectured.jl](package/projectured/main/Projectured.jl).
   Run `test_export_collisions()`.
7. **Split example and test.** Write a one-off script that loads
   `ProjecturedRepl`, parses each example or test file, and for every free
   identifier asks `parentmodule` which package owns it. That gives an exact
   dependency set per file. Group the files by stem, create
   `package/<stem>/example` and `package/<stem>/test`, and give each the
   computed `[deps]`. Keep the alias loop of each new Example package, so the
   files keep using flat names.
8. **Update the guards.** `test_base_layering()` and `test_visual_layering()`
   disappear. Give each new package a trivial `check_layering` call over its
   own folder. Extend `test_package_graph()` to assert that the
   package-to-package graph is acyclic and that no package lists a dependency
   whose modules it never imports.
9. **Update the documents.** Part 8.
10. **Move this plan to `plan/done/`.**

## Part 8 — documents to change

- [documentation/packages.md](documentation/packages.md) — the "What depends on
  what" table becomes Part 3 of this plan. The five kinds and the leaf rule do
  not change.
- [documentation/terminology.md](documentation/terminology.md) — **slice** now
  applies to the kernel alone, because the kernel is the one layered package.
  Say that a concept folder outside the kernel is a package.
- [documentation/architecture.md](documentation/architecture.md) — the
  "Package layout — the 4-package chain" section becomes a package DAG.
- [documentation/architecture-rules.md](documentation/architecture-rules.md)
  and
  [documentation/architecture-requirements.md](documentation/architecture-requirements.md)
  — the rules that speak of base and visual slices now speak of packages.
- [documentation/domains.md](documentation/domains.md) — the "what a domain may
  depend on" list becomes the substrate set.
- [CLAUDE.md](CLAUDE.md) — the reading order links move with the guides of
  Part 6. The seal list covers `package/kernel/main/` only, so it does not
  change.
- [README.md](README.md) — the reading order.

## Part 9 — open questions

1. **`ProjecturedDomain` as a name.** The word "domain" also names the twenty
   source domains. `ProjecturedDomainKit` removes the overlap at the cost of a
   longer name. My recommendation is `ProjecturedDomain`.
2. **`ProjecturedFocus` as a package.** It is about 110 lines. The alternative
   is to keep the focus walk inside `ProjecturedLayout`, which `ProjecturedWidget`
   already depends on. That is one package fewer and one concept less clear.
3. **How far to split `example` and `test`.** 28 more Example packages and 28
   more Test packages is 56 more `Project.toml` files. The alternative is one
   `ProjecturedSubstrateExample` and one `ProjecturedSubstrateTest` that cover
   all 28. Step 7 can go either way, and the answer does not block steps 1
   to 6.
4. **Precompile cost.** 28 packages instead of 2 means 28 precompile units.
   The gain is that a change to one no longer invalidates the others. Measure
   a cold `jp` before step 1 and after step 6.

## Appendix — the two facts that constrain the design

- **The module graph is already acyclic.** Every folder-level cycle comes from
  a grouping choice, not from the code. Three file moves are the whole cost.
- **A Julia submodule does not see its parent's `using` bindings.** That is why
  the `main` dependency sets above are exact and the example and test sets are
  not.
