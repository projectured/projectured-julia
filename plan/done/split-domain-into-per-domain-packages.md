# Split and dissolve `ProjecturedDomain` into one package per domain

## Goal

Dissolve the `ProjecturedDomain` umbrella package. Give every concrete domain its own
package, with its own `main/`, `test/`, `example/` and `doc/` tiers. Sink the parts that
are not domains into `ProjecturedVisual`. After the split, `package/domain/` no longer
exists.

Three things drive this:

1. A domain is the natural consumer boundary. A user who wants JSON must not load the
   SQL parser, the process debugger and the workbench assistant.
2. `PAR-DOMAINS-INDEPENDENT` already states the rule. The single package hides every
   breach of it, because a slice can import a sibling slice with no visible cost.
3. Four opt-in packages (`Sdl`, `Web`, `Video`, `Tulip`) depend on `ProjecturedDomain`
   today, but use **no** domain module at all. The split makes that honest.

## Decisions taken on 2026-08-09

The user settled three questions before this plan was written:

- **Layout.** The new packages are flat under `package/`, like `kernel`, `base` and
  `visual`. There is no second nesting level.
- **Tiers.** Every domain gets all three tiers: `main/`, `test/` and `example/`.
- **Sink set.** The generic insertion core, the plot geometry, `gesturemap`,
  `gesturelog` and `component` sink into `ProjecturedVisual`. The `graph` slice does
  **not** sink; it stays a domain package.

## Measured facts

All numbers below come from a scan of `package/domain/main/` on 2026-08-09.

### The slice graph is almost acyclic already

24 slice folders. Only these slice-to-slice edges exist:

| From | To |
| --- | --- |
| `conversation` | `insertion`, `json`, `julia`, `xml` |
| `dbcatalog` | `sql` |
| `formula` | `julia` |
| `fsm` | `graph`, `insertion`, `julia` |
| `insertion` | `book`, `filesystem`, `graph`, `json`, `julia`, `markdown`, `math`, `rst`, `sql`, `xml` |
| `json`, `julia`, `sql`, `xml`, `yaml` | `insertion` |
| `process` | `graph`, `insertion`, `julia` |
| `sequencechart` | `chart` |
| `workbench` | `conversation`, `filesystem`, `json`, `julia`, `markdown`, `xml`, `yaml` |

The one cycle runs through `insertion`. Every other edge is a clean layer edge that a
package dependency expresses directly.

### The `insertion` slice is three unrelated things in one folder

- `InsertionToSyntax.jl` (688 lines) — a **generic** insertion leaf plus a **Julia** and
  a **SQL** specialization. Code use of `JsonInsertion`, `XmlInsertion` and
  `SqlInsertion` is zero; those three imports are dead. The real domain use is
  `JuliaModule` (types), `juliaparse` and `sqlparse`.
- `EmbedToSyntax.jl` (378 lines) — imports **no** domain module. `ReferenceStub` comes
  from `base/serialization/FileProject.jl`.
- `NaturalProjection.jl` (282 lines) — the true cross-domain aggregator. It names ten
  domains to build one `TypeDispatchingProjection` table.

### Four opt-in packages do not use the domain at all

`ProjecturedSdl`, `ProjecturedWeb`, `ProjecturedVideo` and `ProjecturedTulip` reach
`ProjecturedDomain` only through its kernel and visual alias table (`ColorModule`,
`GraphicsModule`, `ScreenDocumentModule`, `ConstraintSolverModule`, …). They reference
no domain module. `ProjecturedOdbc` uses `database`, `dbcatalog` and `sql`.
`ProjecturedAdaptagrams` uses `graph`.

### The natural-format seam is the pattern to copy

`visual/fileformat/NaturalFormat.jl` declares `natural_syntax_projection` /
`natural_extension` / `parse_natural` as open generics. Six domain files already
register their own methods. `NaturalProjection.jl` needs the same treatment, with a
type key instead of an instance key.

---

## What sinks into `ProjecturedVisual`

| From | To | Why |
| --- | --- | --- |
| the generic half of `insertion/InsertionToSyntax.jl` | `visual/syntax/InsertionToSyntax.jl` | `InsertionToSyntaxLeaf`, `DocumentInsertionToSyntaxLeaf`, `DomainInsertionToSyntaxLeaf`, `InsertionNothingToSyntaxLeaf`, `name_completion`. It imports Syntax, Font, Color and `@domain` only. Five domains need it, so it is a framework. |
| `insertion/EmbedToSyntax.jl` | `visual/fileformat/EmbedToSyntax.jl` | Zero domain imports. It belongs beside `DocumentFile` and `NaturalFormat`, which own the marker and the stub. |
| `chart/ChartGeometry.jl`, plus `series_color` and `default_color_cycle` from `ChartModule` and `marker_polygon` from `ChartPlotToGraphicsModule` | new slice `visual/plot/PlotGeometry.jl` | `AxisScale`, `to_pixel`, `to_data`, `nice_ticks`, `format_tick` and the marker/colour vocabulary. Both `chart` and `sequencechart` need them. |
| `gesturemap/` (6 files) | `visual/gesturehelp/` | A domain-neutral help feature that renders to Syntax and to the screen. `plan/done/base-package-structure.md` already earmarked it. |
| `gesturelog/` (4 files) | `visual/gesturelog/` | Same reason. The recorder decorates any projection. |
| `component/Component.jl` | `visual/component/Component.jl` | 83 lines, kernel imports only, no projection yet. Already earmarked. |

`insertion/NaturalProjection.jl` does **not** move as it stands. See the seam below.

### The natural-projection seam — **done, and larger than planned**

`NaturalToGraphics` moves to `visual/naturalprojection/NaturalProjection.jl`, but its
dispatch tables stop being literals. Three findings changed the design during
implementation:

1. **`register_natural_syntax!` already existed** in `NaturalProjection.jl`, for
   downstream domains. The work was to move the nine built-in rows onto it, not to
   invent it.
2. **There are two tables, not one.** A domain becomes graphics in one of two ways:
   through its `*ToSyntax` and the shared `Syntax → Text → Graphics` tail, or directly,
   because a page of blocks (markdown, RST), a diagram (graph) or a typeset formula
   (math) is not a syntax tree. The second kind needs the backend's `measure` function,
   so it registers a **factory** rather than a pair.
3. **The registry cannot live in the domain package.** A domain file can only import a
   module the compiler has already seen, and `NaturalProjection.jl` is included last.
   So the registry landed in **visual** immediately, as
   `visual/naturalprojection/NaturalRegistry.jl` — the folder `NaturalProjection.jl`
   itself moves into at Step 1.

`NaturalRegistryModule` declares:

```julia
register_natural_syntax!(pairs::Pair...)          # ready-made rows (the existing API)
register_natural_syntax!(key::Symbol, factory)    # factory(): fresh instances per build
register_natural_graphics!(key::Symbol, factory)  # factory(; measure)
natural_syntax_entries()                          # pairs first, then what factories build
natural_graphics_entries(; measure)
```

The nine to-syntax rows and the four to-graphics registrations use the **factory** form,
so every renderer still builds its own projection instances — the literal table did, and
a shared instance would share reactive state. Each domain registers from an `__init__` in
a file it already has: the nine `*ToSyntax.jl`, plus `MarkdownToLayout.jl`,
`RstToLayout.jl`, `GraphLayoutToGraphics.jl` and `MathToGraphics.jl`.

Row order changed in one harmless way: the domain graphics rows now come before
`ReferenceStub` and `FileDocument` instead of straddling them. Every type involved is
disjoint, so first-match-wins is unaffected. Measured after the change: 9 syntax rows and
25 graphics rows, the same set as the literal.

**Risk to watch.** A `TypeDispatchingProjection` built from a registry sees only the
domain packages that are loaded. `Projectured` loads all of them, so the umbrella
behaves as today. A user who loads `ProjecturedJson` alone gets a smaller table, which
is the point of the split.

---

## The 20 domain packages

Every package sits at `package/<name>/` with `main/`, `test/`, `example/` and `doc/`.
Every package depends on `ProjecturedKernel`, `ProjecturedBase` and `ProjecturedVisual`.
The table lists only the extra edges.

### Tier 1 — no domain dependency

| Package | Directory | Source files | Extra deps |
| --- | --- | --- | --- |
| `ProjecturedJson` | `package/json/` | `Json`, `JsonParser`, `JsonToSyntax`, `JsonFile` | — |
| `ProjecturedYaml` | `package/yaml/` | `Yaml`, `YamlParser`, `YamlToSyntax` | — |
| `ProjecturedXml` | `package/xml/` | `Xml`, `XmlParser`, `XmlToSyntax`, `XmlFile` | — |
| `ProjecturedMarkdown` | `package/markdown/` | `Markdown`, `MarkdownParser`, `MarkdownToSyntax`, `MarkdownToLayout`, `MarkdownFile` | `Markdown` stdlib |
| `ProjecturedRst` | `package/rst/` | `Rst`, `RstParser`, `RstToSyntax`, `RstToLayout`, `RstFile` | — |
| `ProjecturedBook` | `package/book/` | `Book`, `BookToSyntax` | — |
| `ProjecturedMath` | `package/math/` | `Math`, `MathToSyntax`, `MathToGraphics` | — |
| `ProjecturedJulia` | `package/julia/` | `Julia`, `JuliaParser`, `JuliaToSyntax`, `JuliaFile`, **`JuliaInsertionToSyntax`** | — |
| `ProjecturedSql` | `package/sql/` | `Sql`, `SqlParser`, `SqlToSyntax` | — |
| `ProjecturedDatabase` | `package/database/` | `DatabaseInstance`, `Database`, `DatabaseAdapters` | — |
| `ProjecturedFileSystem` | `package/filesystem/` | `FileSystem`, `FileSystemToSyntax`, `FileSystemToWidget` | — |
| `ProjecturedGraph` | `package/graph/` | `Graph`, `GraphLayout`, `GraphLayoutEngine`, `GraphToGraphLayout`, `GraphLayoutToGraphics` | — |
| `ProjecturedChart` | `package/chart/` | `Chart`, `ChartSampleReferenceStep`, `ChartPlot`, `ChartToChartPlot`, `ChartPlotToGraphics` | — |
| `ProjecturedSequenceChart` | `package/sequencechart/` | `SequenceChart`, `SequenceChartRowReferenceStep`, `SequenceChartGeometry`, `SequenceChartPlot`, `SequenceChartToSequenceChartPlot`, `SequenceChartPlotToGraphics` | — |

`sequencechart` loses its edge to `chart` once the plot geometry sinks to visual. Check
this when the move lands. If a residual symbol remains, add the `ProjecturedChart` edge
rather than duplicate the symbol.

### Tier 2 — one domain dependency layer

| Package | Directory | Extra deps |
| --- | --- | --- |
| `ProjecturedDbCatalog` | `package/dbcatalog/` | `ProjecturedSql` |
| `ProjecturedFormula` | `package/formula/` | `ProjecturedJulia` |
| `ProjecturedFsm` | `package/fsm/` | `ProjecturedJulia`, `ProjecturedGraph` |
| `ProjecturedProcess` | `package/process/` | `ProjecturedJulia`, `ProjecturedGraph` |
| `ProjecturedConversation` | `package/conversation/` | `ProjecturedJson`, `ProjecturedJulia`, `ProjecturedXml` |

### Tier 3 — the application

| Package | Directory | Extra deps |
| --- | --- | --- |
| `ProjecturedWorkbench` | `package/workbench/` | `ProjecturedConversation`, `ProjecturedFileSystem`, `ProjecturedJson`, `ProjecturedJulia`, `ProjecturedMarkdown`, `ProjecturedXml`, `ProjecturedYaml` |

### The `SqlInsertionToSyntaxLeaf` and `JuliaInsertionToSyntaxLeaf` split

`SqlInsertionToSyntaxLeaf` is three lines. It moves into `sql/SqlToSyntax.jl`. The Julia
half is larger: the keyword scaffolds, the six `@insertion` registrations,
`JuliaInsertionToSyntaxLeaf` and the whole `@gestures JuliaInsertion` block. It becomes
its own file `julia/JuliaInsertionToSyntax.jl` in `ProjecturedJulia`.

---

## The root module of a domain package

Do not copy the 130-line alias table of `ProjecturedDomain.jl` into 20 packages. Bind
the submodules with the same loop the `Projectured` umbrella already uses, so the source
files keep their relative `..XxxModule` imports unchanged:

```julia
module ProjecturedFsm

using ProjecturedKernel, ProjecturedBase, ProjecturedVisual
using ProjecturedJulia, ProjecturedGraph

# Bind every submodule of the packages below as a const, so `..SyntaxModule`
# inside a submodule of this package resolves through this binding.
for _src in (ProjecturedKernel, ProjecturedBase, ProjecturedVisual,
             ProjecturedJulia, ProjecturedGraph)
    for _n in names(_src; all = true)
        isdefined(_src, _n) || continue
        _m = getfield(_src, _n)
        (_m isa Module && _m !== _src && parentmodule(_m) === _src) || continue
        Core.eval(@__MODULE__, Expr(:const, Expr(:(=), _n, _m)))
    end
end

include("Fsm.jl")
include("FsmDiagram.jl")
include("FsmToSyntax.jl")
include("FsmToFsmDiagram.jl")
include("FsmDiagramToGraph.jl")
include("FsmToJuliaCode.jl")

end
```

The `parentmodule` guard is what stops a re-exported alias of a lower package from being
bound twice. The umbrella proves the pattern.

**Prerequisite.** The loop binds only canonical module names. `ProjecturedDomain.jl`
also defines twelve deprecated second names. Sweep them away first (Step 0):

| Deprecated name | Canonical name |
| --- | --- |
| `BackendApiModule` | `BackendModule` |
| `DocumentApiModule` | `DocumentModule` |
| `ReferenceApiModule`, `ReferenceBuilderModule`, `ReferenceCaseModule` | `ReferenceModule` |
| `SelectionApiModule` | `SelectionModule` |
| `OperationApiModule`, `OperationRerootingModule` | `OperationModule` |
| `ProjectionReferenceStepApiModule` | `ProjectionReferenceStepModule` |
| `PointReferenceStepApiModule` | `PointReferenceStepModule` |
| `TextSpanReferenceStepApiModule` | `TextSpanReferenceStepModule` |
| `TextColumnReferenceStepApiModule` | `TextColumnReferenceStepModule` |

**Alternative, rejected for now.** Rewrite every import to the absolute form
(`import ProjecturedVisual.SyntaxModule: SyntaxLeaf`). This removes the loop, but it
touches about 120 files and makes the diff of this plan unreadable. Do it later as its
own change if the loop proves fragile.

---

## The example tier

`ProjecturedDomainExample` dissolves. Each domain example package holds the factories
for its own domain, and builds the flat namespace with the same loop over its own main
package plus kernel, base and visual.

Twenty example packages get content: `package/<name>/example/`, one per domain, taking
the matching `document/X.jl` and `projection/X.jl` pair.

These files are cross-domain and rise to `ProjecturedExample` (the umbrella example
package, which already owns the registry):

- `Gallery.jl` — `run_example` and its workbench, tooltip, inspector and clipboard
  wrappers.
- `FileEditor.jl` — the editor domain table wires json, text and xml.
- `Examples.jl`, `Precompile.jl`.
- `document/` and `projection/` for `Mixed`, `Natural`, `Wrapper`, `Embed`, `Table`,
  `Clipboard`, `Navigator`, `Focusing`, `Pane`, `Dragging`, `Versioning`, `Graphics`.

`GestureMap.jl` follows its slice into `ProjecturedVisualExample`.

`ProjecturedSdlExample`, `ProjecturedOdbcExample`, `ProjecturedAdaptagramsExample` and
`ProjecturedTulipExample` need no change. They depend on `Projectured` and
`ProjecturedExample`, both of which keep their names.

## The test tier

`ProjecturedDomainTest` dissolves. `test_domain()` and `test_domain_layering()` go away.
Each domain test package exports `test_json()`, `test_fsm()` and so on, plus a
`test_<domain>()` aggregator that runs its own suite.

Seventeen of the twenty test packages get content today:

| Package | Test files that move in |
| --- | --- |
| json | `JsonTest`, `JsonParserTest`, `JsonToSyntaxTest`, `JsonContentClicksTest`, `JsonPlaceholderNavTest`, `JsonFileTest` |
| julia | `JuliaParserTest`, `JuliaTypeinTest` |
| xml | `XmlToSyntaxTest`, `XmlFileTest` |
| sql | `SqlDocumentTest`, `SqlParserTest`, `SqlToSyntaxTest` |
| rst | `RstParserTest`, `RstEmbedTest`, `fixture/rst/` |
| markdown | `MarkdownEmbedTest` |
| math | `MathToGraphicsTest` |
| fsm | `FsmTest`, `FsmToSyntaxTest`, `FsmDiagramTest`, `FsmToJuliaCodeTest` |
| process | `ProcessTest`, `ProcessToSyntaxTest`, `ProcessDiagramTest`, `ProcessToJuliaCodeTest`, `ProcessDebugTest` |
| chart | `ChartTest` |
| sequencechart | `SequenceChartTest`, `SequenceChartGeometryTest` |
| graph | `GraphTest` |
| filesystem | `FileSystemToSyntaxTest` |
| formula | `FormulaToSyntaxTest` |
| conversation | `ConversationEditorTest`, `ConversationPanelTest`, `ConversationParsingTest`, `ConversationSerializationTest` |
| workbench | `WorkbenchContentPaneTest`, `WorkbenchTabClickTest`, `WorkbenchFileTest`, `AssistantMvpTest` |
| dbcatalog | `DbCatalogSqlTest` |

`yaml`, `book` and `database` get an empty test package that declares the home. Their
first test lands there.

These tests are cross-domain and rise to `ProjecturedTest`: `ConstructTest`,
`SyntaxTreeSelectionTest`, `TableSelectionTest`, `TableNavigationTest`,
`DocumentInsertionTest`, `DraggingTest`, `HoverProbeTest`, `SerializationTest`,
`StubCollectionTest`, `MarkerVocabularyTest`, `FileProjectS4Test`, `FileProjectS5Test`,
`JuliaAndMarkdownFileTest`, `GalleryWrapperTest`, `McpTest`, `TypeReferenceTest`,
`SelectionEnumeration.jl`.

`ChartGeometryTest`, `CommandPaletteTest`, `GestureHelpTest` and `GestureLogTest` follow
their slices into `ProjecturedVisualTest`. `ConsoleBackendTest` and `PdfTest` follow
their fixture: both drive a JSON pipeline, so they go to `ProjecturedJsonTest`.

## Downstream packages

| Package | Change |
| --- | --- |
| `ProjecturedSdl` | Drop the `ProjecturedDomain` dep. Depend on `ProjecturedVisual`. Rewrite the `ProjecturedDomain.XxxModule` references to the owning package. |
| `ProjecturedWeb` | Same. |
| `ProjecturedVideo` | Same, plus keep its `ProjecturedSdl` dep. |
| `ProjecturedTulip` | Same. It uses only `ConstraintSolverModule`. |
| `ProjecturedOdbc` | Depend on `ProjecturedDatabase`, `ProjecturedDbCatalog`, `ProjecturedSql` and `ProjecturedVisual`. |
| `ProjecturedAdaptagrams` | Depend on `ProjecturedGraph`. |
| `Projectured` | Import all 20 domain packages instead of `ProjecturedDomain`. The re-export loop needs no other change. |
| `ProjecturedExample` | Import the 20 example packages. Take over the gallery and the cross-domain examples. |
| `ProjecturedTest` | Import the 20 test packages. Take over the cross-domain tests. |
| root `Project.toml`, `bench/` | Add the 60 new `[deps]` and `[sources]` entries. Remove the three `ProjecturedDomain*` entries. |

Keep the umbrella and the root environment in step. A dep that reaches only one of the
two makes the `jp` REPL alias resolve differently from a test run.

---

## Ordered steps

Do the work in a dedicated git worktree. Make one commit per step. The tree must load
and pass its targeted tests after every step.

### Step 0 — prepare inside the current package

No package boundary moves. The tree stays green.

1. Delete the three dead imports in `insertion/InsertionToSyntax.jl` (`JsonInsertion`,
   `XmlInsertion`, `SqlInsertion`).
2. Sweep the twelve deprecated module aliases to their canonical names, then delete them
   from `ProjecturedDomain.jl`.
3. Split `insertion/InsertionToSyntax.jl` into the generic core, `julia/JuliaInsertionToSyntax.jl`
   and three lines in `sql/SqlToSyntax.jl`.
4. Split `chart/ChartGeometry.jl` into the plot geometry and what stays chart-specific.
   Move `series_color`, `default_color_cycle` and `marker_polygon` with the geometry.
5. Add the type-keyed `natural_syntax_projection(::Type)` generic to
   `NaturalFormatModule`. Register every domain type. Rebuild the `NaturalToGraphics`
   table from the registry.

Verify: `test_domain()` and `test_visual()`.

### Step 1 — sink the six items into `ProjecturedVisual`

`git mv` the generic insertion core, `EmbedToSyntax.jl`, the plot geometry, `gesturemap/`,
`gesturelog/`, `component/` and `NaturalProjection.jl` into visual. Update
`ProjecturedVisual.jl` and `ProjecturedDomain.jl`. Move their tests and examples into the
visual test and example packages.

Verify: `test_visual()`, then `test_domain()`.

After this step, `package/domain/main/` holds 20 slices and its slice graph is acyclic.

### Step 2 — extract the 20 main packages, bottom-up

Extract in dependency order: the 14 tier-1 packages first, then dbcatalog, formula, fsm,
process, conversation, then workbench. For each package:

1. Create `package/<name>/main/` with `Project.toml` (new UUID) and the root module.
2. `git mv` the slice folder contents into it.
3. Add the package to `ProjecturedDomain`'s deps and to its alias set, so the slices that
   are still inside keep resolving.
4. Add the package to the root `Project.toml` `[deps]` and `[sources]`.
5. Verify the load and the narrowest test that covers the slice.

`ProjecturedDomain` shrinks by one slice per commit and stays loadable throughout.

### Step 3 — dissolve the umbrella package

When the last slice leaves, `package/domain/main/` is empty. Then:

1. Repoint `Projectured` to the 20 packages.
2. Repoint `Sdl`, `Web`, `Video`, `Tulip`, `Odbc`, `Adaptagrams`.
3. Delete `package/domain/main/` and its root Project entries.

Verify: load `Projectured`, then run one example end to end.

### Step 4 — the example tier

Create the 20 example packages. Move the cross-domain examples and the gallery up to
`ProjecturedExample`. Delete `package/domain/example/`.

Verify: `run_example("json")`, `run_example("workbench")`, `print_example`.

### Step 5 — the test tier

Create the 20 test packages. Move the cross-domain tests up to `ProjecturedTest`. Delete
`package/domain/test/`.

Verify: each `test_<domain>()`, then `test_all()` once, and diff the counts against the
baseline (see Risks).

### Step 6 — documentation and guards

1. Move `package/domain/doc/<domain>.md` into each package's `doc/`. `versioning.md`
   goes to `base/doc/` because versioning already lives in base.
2. Rewrite the package chain in `documentation/architecture.md` (lines about 75-160 and
   about 300-400).
3. Update the per-domain guide links in `CLAUDE.md` and `README.md`.
4. Replace `test_domain_layering()`. Each domain package is a single slice, so the
   per-package layer guard becomes trivial. Add one guard that reads every
   `package/*/main/Project.toml` and asserts the package dependency graph is acyclic and
   matches the table in this plan.

---

## Risks

**A wide refactor needs a baseline diff — but `test_all()` costs 47 minutes.** Run it
once for the baseline, then compare **per suite**, not per whole run. Two rules learned
at Step 1:

1. Compare like with like. A suite run standalone and the same suite run inside
   `test_all()` give **different** pass counts — `test_visual()` was 52526 standalone
   and 52514 inside `test_all()` on the same tree. Always re-measure the base commit
   the same way you measure the branch. The branch is committed, so
   `git checkout <base>` in the worktree is cheap and the precompile caches are warm.
2. `test_catalog()` is the highest-value single check for anything that touches the
   natural projection or a printer: 292982 assertions over every atomic document, six
   minutes, and it matched the baseline **exactly** after the registry rewrite.

**Four examples are not hermetic — they render the repository itself.**
`make_filesystem_document_example` takes `root = package/domain/example/` and lists the
live directory. So `filesystem`, `filesystem_widget`, `navigator` and `workbench` change
their assertion counts whenever a file is added to or removed from that directory. Moving
one example file out at Step 1 cost 67 + 17 + 67 + 17 = 168 assertions. Step 4 moves
about 150 example files, so expect a large, meaningless shift there. Do not read it as a
regression; read `Fail`, `Error` and `Broken` instead.

**A reactive-reuse bug hides from a direct read.** The insertion split and the
`natural_to_syntax` registry both change what a printer sees. Verify them in a real
editor, not only through a direct `print_document` call.

**Precompile cost.** 60 packages precompile separately. The first load after a change to
`ProjecturedVisual` invalidates every domain package. Measure the `jp` alias load time
before and after; if it grows too much, consider merging the smallest test packages.

**Three empty test packages.** `yaml`, `book` and `database` start with no test file.
They exist to declare the home.

**A registry-built dispatch table is order-sensitive.** Two domains must not register
the same type. Add an assertion in the registry that rejects a duplicate key.

## Answered questions

- `sequencechart` **did** lose its `chart` edge once the plot geometry sank. Both are
  tier-1 packages now.
- `graph` stayed a domain package. The registry expressed its `GraphGraph` row without
  trouble, so the question of sinking it into visual did not arise.
- `Base64`, `Markdown` and `Serialization` were all declared but unused. None of the
  twenty packages carries them.

## Follow-ups — all three closed

- [x] **The filesystem examples read a fixture, not the repository** (`e568fe21`).
  `make_filesystem_document_example` read the directory above its own file, so four
  examples changed their assertion counts whenever a file moved nearby — twice during
  this work, each time looking exactly like a regression. They now read
  `package/filesystem/example/fixture/project`, a fixed tree of nested folders and a few
  file kinds. `filesystem_example_root()` is exported and the workbench navigator example
  shares it.
- [x] **yaml, book and database have a first suite** (`48e5187e`). The yaml parser suite
  found a real gap and recorded it with two `@test_broken` markers: an anchor loads as
  its own source text (`"&x 1"` becomes a string) and a tab indent parses without
  complaint, so a file using either loads as something with nothing to signal it was not
  understood. Book covers the three rules a projection template cannot express; database
  covers the documents and the adapter seam without touching a database.
- [x] **The pending plans point at the packages the files live in** (`8c29774b`).
  35 plans were rewritten by mapping each path to the one file that matches it on disk.
  25 still name the old package in a way no rewrite can fix — the `ProjecturedDomain`
  module itself, or a pre-restructure `package/domain/src/` path whose file was since
  renamed. Those carry a layout note under their first heading instead of a wrong path.
- **`ProjecturedTest` is now large.** It keeps every cross-domain suite, which is
  correct, but it is worth a later look at whether some of those fixtures could be
  narrowed to one domain.

## Status

- [x] **Step 0 — prepare inside the current package.** Three commits on branch
  `domain-split`, worktree `projectured-julia-domain-split`.
  - `56392a6e` — the alias sweep. Every domain, odbc, sdl, web and video source names
    the canonical module; the twelve deprecated `const`s are gone from
    `ProjecturedDomain.jl`. `ExportCollisionTest.jl`'s prose keeps the old names on
    purpose: visual and base still define those aliases for their own files.
  - `a291be10` — the two splits. `julia/JuliaInsertionToSyntax.jl` is new;
    `chart/PlotStyle.jl` is new; `InsertionToSyntax.jl` lost 266 lines and names no
    domain. Verified with `test_document_insertion`, `test_julia_typein`,
    `test_sql_to_syntax`, `test_chart_geometry`, `test_chart`, `test_sequencechart` —
    658 pass, 0 fail.
  - the registry seam — see the section above. Verified with `test_markdown_embed`,
    `test_rst_embed`, `test_graph`, `test_math_to_graphics`, `test_document_insertion` —
    312 pass, 0 fail.
- [x] **Step 1 — sink the six items into `ProjecturedVisual`** (`195b052e`).
  `package/domain/main/` now holds exactly the 20 slice folders. `ChartGeometryModule` is
  renamed `PlotGeometryModule`. `ChartGeometryTest` moved to the visual test package as
  `PlotGeometryTest`; the three gesture tests stayed in domain because their fixtures are
  JSON documents.

  **The count diff reconciles exactly, with nothing left over:**

  | Suite | base | branch | delta | why |
  | --- | --- | --- | --- | --- |
  | `test_visual()` standalone | 52526 | 52631 | +105 | `test_plot_geometry` moved in |
  | `test_domain()` | — | 209281 | −273 | the two rows below |
  | ‣ `test_chart_geometry` | 105 | — | −105 | moved to visual |
  | ‣ `test_domain_examples()` | 206311 | 206143 | −168 | the four non-hermetic examples |
  | `test_catalog()` | 290836 | 290836 | 0 | identical |

  `Fail` and `Error` are 0 on both sides; `Broken` is unchanged (1 visual, 5 domain).
- [ ] Step 2 — extract the 20 main packages
- [x] **Step 2 — extract the 20 main packages** (`4cd8e734`). Every slice folder is now
  a package under `package/`, with its own UUID and a root module that binds its
  dependencies' submodules with the mechanical loop rather than a written table. The
  dependency edges in the tables above are declared in the `Project.toml` files.

  **One real regression, found by the tests.** The kernel's `execute_julia_code`
  sandbox built its namespace with the same `parentmodule(sub) === source` guard the
  umbrella used, so a domain that moved into its own package vanished from scratch
  code and `editor.document isa WorkbenchAssistant` stopped resolving. The guard in
  `tool/CodeExecution.jl` now also accepts a submodule whose parent package the source
  list does not name — the same relaxation the umbrella, the example package and the
  test package needed. Watch for this shape wherever a `parentmodule` guard walks a
  package's bindings.

  Verified: `test_domain()` 209281 pass, 5 broken, 0 fail — identical to Step 1.
- [x] **Step 3 — dissolve the umbrella package** (`03648d7f`). `package/domain/main/`
  is deleted.
  - `Projectured` imports the 20 directly. Its `_SOURCES` tuple is the one place the
    full set is written down; a new domain package needs an edit there and nowhere
    else.
  - `Sdl`, `Web`, `Video` and `Tulip` named 21 modules through `ProjecturedDomain` and
    **not one was a domain module**. They now depend on the engine packages only.
    `Odbc` depends on `Database`, `DbCatalog` and `Sql`; `Adaptagrams` on `Graph`.
  - `package/executable/main/Manifest.toml` is deleted — it pinned a package that no
    longer exists.
  - `test_domain_layering()` runs the guard once per domain package. That needed one
    change to the shared guard: `check_layering` read a package's module aliases off
    the literal `const` lines of the root module, and a domain root module binds them
    with a loop. It gained an `extra_aliases` keyword, and the test measures the set
    from the loaded package.

  Verified: `test_domain()` 209395 pass, 5 broken, 0 fail. The rise from 209281 is the
  layering guard running 20 times rather than once, 6 assertions each. All six opt-in
  packages load, SDL and Tulip included.
- [x] **Step 4 — the example tier** (`bcafc114`). Each domain's factories live in
  `package/<domain>/example/`.

  **The registry stayed whole**, against the plan. `DomainExamples.jl`,
  `Examples.jl`, `Catalog.jl`, `Gallery.jl` and `FileEditor.jl` all moved to
  `ProjecturedExample`: each names factories from every domain, so splitting them
  per domain would have reordered the registry and put the catalog comparison out
  of use for nothing. The umbrella also kept the examples that demonstrate an
  **engine feature over a domain fixture** rather than a domain — clipboard,
  dragging, embed, focusing, versioning, natural, pane, graphics.

  Three shared pieces needed a home both users can reach:
  `make_table_projection_example` is `NaturalToGraphics` with the chrome font and
  names no domain, so it sank to `ProjecturedVisualExample`; the mixed JSON+XML
  pair went to `ProjecturedXmlExample`; `_conversation_widget_graphics` went to
  `ProjecturedConversationExample`, where it belongs.

  An example package declares whatever its examples name, even when the main
  package does not — the workbench example opens a book, a SQL statement and a
  YAML document.

  Verified: `test_domain()` 199319 pass, 5 broken, 0 fail.
- [x] **Step 5 — the test tier** (`04ed37a7`). `package/domain/` is gone.

  The umbrella kept every suite whose fixture names several domains, which is most
  of what was left. Four things needed more than a move:
  - `test_xml_parser` lived inside `JsonParserTest`; it is now
    `xml/test/document/XmlParserTest.jl`.
  - The conversation panel, parsing and serialization suites drive
    `WorkbenchAssistant`, so they rose to the umbrella rather than pull workbench
    into the conversation test package. `WorkbenchFileTest` needs the gallery, so
    it rose too.
  - **Six aggregators collided with a suite of the same name.** `test_json`,
    `test_fsm`, `test_graph`, `test_process`, `test_chart`, `test_sequencechart`
    were taken by a single file's suite. The file-level suite took a specific name
    (`test_json_document`, `test_graph_projection`, …) and the bare name is now the
    package aggregator, which is what a reader expects it to mean.
  - `test_database` collided with the ODBC live-connection suite, so the domain
    one is `test_database_domain`.

  Verified: all twenty test packages green — 2261 pass, 1 broken, 0 fail.
- [x] **Step 6 — documentation and guards** (`5b274229`). `documentation/domains.md`
  replaces the old domain-package guide; the package chain, the thirteen visual
  slices and the opt-in edges are rewritten. New `test_package_graph()` reads every
  `package/*/main/Project.toml` and asserts the graph is acyclic, that each domain
  declares exactly the edges the table allows, that each depends on all three
  engine packages, and that no engine package depends on a domain.
