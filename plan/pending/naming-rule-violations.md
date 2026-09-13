# Fix the names that break the naming law

> **Kind:** plan · **Status:** executed except the items of §0.3 · **Stands on:**
> [naming-rules.md](../../documentation/rule/naming-rules.md),
> [architecture-invariants.md](../../documentation/rule/architecture-invariants.md)
> (`PAR-NAMING-LAW`), [division-terminology.md](../../documentation/rule/division-terminology.md)

## 0. What was done — status as of 2026-09-13

**The plan is executed, apart from the items §0.3 names.** 45 commits on branch
`naming-law`, in the worktree `projectured-julia-naming`.

### 0.1 What landed

| work | count |
| --- | --- |
| function and constant renames | 385 |
| type renames | 48 |
| IO map renames | 23 |
| file renames | 11 |
| file splits | 2 of 3 |
| module alias lines deleted | 29 |
| layering guards added | 4 |
| documentation headers added | 2 |
| coverage artifacts removed | 19 |
| corrections to renames this plan itself got wrong | 8 |

`test_package_graph()` reported 728 pass and 2 fail at every step, which is what
the same guard reports on `main`. Those two failures are pre-existing and
concern domain edges, not names. Every group was verified by loading its
packages and running the narrowest suite that covers it.

### 0.2 The naming guard

[test/suite/naming.jl](../../test/suite/naming.jl) is new, and `test_all()`
calls `test_naming()` beside `test_tree()`. It checks a module name against its
file and its slice, an alias no file declares, an abbreviation the rules ban,
and a test package's entry point. It does not judge whether a verb fits the work
or whether a name reads as English — a guard that guessed would be wrong often
enough to be ignored.

It found a real conflict on its first run: `ProjecturedDatabaseTest` had no
`test_database()` because `test/odbc` held a live query test of that name. The
odbc tests now say odbc, and the database package has its own entry point.

### 0.3 What is still open

| item | where |
| --- | --- |
| the clipboard file split | [one-module-per-slice.md](one-module-per-slice.md) §4.1 |
| the 30 document module renames | cancelled; a slice becomes one module |
| six module names that the slice collapse settles | allow-listed in the guard, with the reason |
| the four `PRED_REF` constants | §9.30 — the abbreviation is the wire value |
| `EVALUATION_HANDLER` is a process-wide global | §11.1 — a design finding, not a rename |
| the stale block in `system-anatomy.md` | §8.3 |
| whether the four `sdl_*` helpers should be exported at all | §14.11 of the appendix |

### 0.4 What reading the code changed

The merged list was built before the user's verb rulings existed, so it
systematically under-used `find_`, `compute_`, `build_`, `collect_`, `convert_`
and `format_`. Roughly twenty names were corrected during execution, and the
pattern is worth keeping:

- **A `get_` that was not a read.** `text_flat_to_elem` is a conversion, and its
  own docstring says so. `math_metrics` scales a font and derives an x-height.
  `nearest_sample` returns `nothing` when nothing is near.
- **A slice word that said nothing, or one that was missing.** `syntax_opening`
  returns `:opening_delimiter`, so it is `get_opening_delimiter`. The fsm
  functions had dropped a prefix their own types carry, and `state` appears in
  103 files outside that slice.
- **A name that read as no English phrase.** `get_base_plane_length_square`,
  `get_cell_kind_of`, `make_widget_pager`. This produced the rule at the head of
  the Functions section: where a shape gives a phrase nobody would say, the
  English wins and the rule yields.
- **A generic name nobody could place.** `get_content` and `get_title` were
  rejected outright and became `get_file_content` and `get_workbench_title`.

Three names were left alone after reading them: `would_create_cycle` asks what
an edge *would* do, `julia_main` is PackageCompiler's required symbol, and five
`@projection_template` words are DSL vocabulary.

### 0.5 The renamer

[workspace/bin/julia-rename.jl](../../../bin/julia-rename.jl) does the renames
with Julia's own parser rather than a text substitution. Running it on real code
found three defects in it, each of which had produced or would have produced
wrong output:

1. `function f end` read as an ordinary reference rather than a definition.
2. The left operand of an infix call sits where the function of a prefix call
   sits, so `vertex_count >= LIMIT` read as a call and one run renamed a
   parameter. That run was reverted whole.
3. `Module.name` was skipped as a field access. 64 qualified calls in the
   sequence chart slice were silently left behind by one pass.

The lesson that outlived all three: **an `other` count can not be read without
looking at what it is.** `kinetic_energy`'s single other reference had to move,
`vertex_count`'s seven had to stay, and `truetype_measure_text`'s 135 all had to
move.

## 1. What this plan is

I collected every name in the repository that the naming law governs, and I
checked each one against [naming-rules.md](../../documentation/rule/naming-rules.md).
This file holds the findings and the order of the fix.

The law is also an architecture invariant, `PAR-NAMING-LAW`. Every sealed file
was audited against that invariant, so a violation inside a sealed file means
the audit missed it. The user gave permission on 2026-09-12 to open sealed files
for this work.

### Scope of the collection

| family | what I enumerated | count |
| --- | --- | --- |
| packages | every directory under `package/` | 119 |
| files | every `.jl` file under `source/`, `test/`, `example/` | 699 |
| modules | every top-level `module <Name>` declaration | 378 in 371 files |
| types | `struct`, `mutable struct`, `abstract type`, type aliases | see §5 |
| functions | every `export` list under `source/`, `test/`, `example/` | see §6 |
| projections | every type that ends in `Projection` | 36 |
| documentation | every `PR-…` and `PAR-…` identifier | 44 + 77 |

Two independent passes counted the modules: mine and a subagent's. They agree on
every class. My own regex missed one declaration, `module StatementScope end` on
one line, and wrongly counted two that sit inside a docstring or a string
literal. The numbers below are the corrected ones.

### How to read the tables

Every table row carries a confidence. `certain` means the rule states the shape
and the name does not have it. `likely` means the rule states the shape and one
judgement stands between the name and the fix. `unsure` means the rule is silent
or reads two ways; §9 collects the questions those rows raise.

### The result in one table

| family | examined | violations | largest open question |
| --- | --- | --- | --- |
| packages | 119 | 0 | — |
| file names | 699 | 5 + 4 missing guards | 97 test file names (§9.2) |
| modules | 378 | 49 in three classes | the 30 document modules (§9.1) |
| types | 1443 | 54 | 85 converters with no suffix (§9.18) |
| functions and constants | 1486 | 64 | 452 getters (§9.27) |
| projections | 36 | 6 stems, 4 misplaced files | §9.14 and §9.18 are one question |
| pipeline ladder | — | 1 pair | — |
| `PR-…` / `PAR-…` | 121 | 0 | — |
| doc headers | 60 | 3 | — |

**178 names are violations and 31 questions are open.** Three of the questions
each govern more names than the whole violation list: the 452 getters, the 85
converters and the 30 document modules. Answer those three first, because they
decide whether this work is 178 renames or over 600.

## 2. Order of the work

Put the cheap and wide changes first, and the ones that need a decision last.

1. **The three big rulings** (§13). All three are answered. The getters take a
   verb, the `<A>To<B>` converters stay bare, and a module is one unit of
   architecture rather than one file, which cancels §4.1.
2. **The naming guard** (§10), with the assertions that already pass turned on.
3. **Module renames** (§4.1, §4.2). No `include` line changes and no `git mv`.
   717 references in code and 8 in documentation.
4. **Module aliases** (§4.3). Delete a second name for a module that no file
   declares.
5. **File splits and renames** (§3.2, §4.4, §7.1, §7.2). Each one also
   rewrites an `include("…")` string.
6. **The four missing layering guards** (§3.3). New code, not a rename.
7. **Type renames** (§5). Start with §5.1 and §5.2, which need no judgement.
8. **Exported function renames** (§6). The widest blast radius, so last.
9. **The three documentation headers** (§8.1) and the stale rule sentence
   (§8.2). Independent of everything above, so do them whenever convenient.

Commit one step at a time. After each step run the narrowest test that covers
it, and a load of the touched package — a green precompile can hide a failing
`using`.

## 3. Packages and file names

### 3.1 Packages — no violations

All 119 package names conform:

- the directory name, the `name` field of `Project.toml`, and
  `src/<PackageName>.jl` carry the same name in all 119 cases;
- every suffix is bare or one of `Example`, `Test`, `Repl`, `Build`, or a named
  exception (`ProjecturedExecutable`, `ProjecturedBuilder`, `ProjecturedBench`);
- 113 of 119 have a `source/<slice>/` folder with the exact derived name. The
  other six are facts and not violations: `Projectured`, `ProjecturedExample`,
  `ProjecturedTest`, `ProjecturedBench`, `ProjecturedSubstrateExample` and
  `ProjecturedSubstrateTest`.

### 3.2 File names — three wrong suite names

The slice folder is lower case, but the file name takes the package's own
CamelCase. Three suite names took the folder spelling instead.

| name | file | rule broken | proposed name | confidence |
| --- | --- | --- | --- | --- |
| `DbcatalogSuite.jl` | [test/dbcatalog/DbCatalogSuite.jl](../../test/dbcatalog/DbCatalogSuite.jl) | "A file is named for what it defines" — `<Slice>Suite.jl` takes the CamelCase of `ProjecturedDbCatalog`. | `DbCatalogSuite.jl` | certain |
| `FilesystemSuite.jl` | [test/filesystem/FileSystemSuite.jl](../../test/filesystem/FileSystemSuite.jl) | Same rule — the package is `ProjecturedFileSystem`. | `FileSystemSuite.jl` | certain |
| `SequencechartSuite.jl` | [test/sequencechart/SequenceChartSuite.jl](../../test/sequencechart/SequenceChartSuite.jl) | Same rule — the package is `ProjecturedSequenceChart`. | `SequenceChartSuite.jl` | certain |

Two more file names are findings that need a judgement:

| name | file | rule broken | proposed name | confidence |
| --- | --- | --- | --- | --- |
| `LiveExamples.jl` | [example/sdl/LiveExamples.jl](../../example/sdl/LiveExamples.jl) | The registry is `<Slice>Examples.jl`, so the sdl slice's registry is `SdlExamples.jl`, and no such file exists. The file defines the `LiveExample` type and a demo timeline, not the slice's document and projection examples. | `SdlExamples.jl`, or a name that drops `Examples` because the file is not the registry | likely |
| `DocumentCore.jl` | [source/domain/DocumentCore.jl](../../source/domain/DocumentCore.jl) | Only a document file carries `Document`, and the primary document file of a slice is `<Slice>Document.jl`. This file declares the whole document family of the `domain` slice (`DocumentBase`, `DocumentNothing`, `DocumentInsertion`, `DocumentReference`). | `DomainDocument.jl` | unsure |
| `ReferenceStep.jl` | [source/kernel/reference/ReferenceStep.jl](../../source/kernel/reference/ReferenceStep.jl) | Same rule — the file declares three real `@document [C, M] struct` types (`RangeReferenceStep`, `FieldReferenceStep`, `TypeReferenceStep`). | `?` — no kernel layer has a `<Layer>Document.jl` precedent | unsure |

Checks that found nothing:

- `source/<Slice>Document.jl`: all 37 files contain a real `@document`.
- `source/<A>To<B>.jl`: 62 projection file names conform.
- `example/<Thing>DocumentExample.jl`: 52 conform.
  `example/<Thing>ProjectionExample.jl`: 54 conform.
- Duplicated basenames: 11 names cover 22 files, and 9 of the 11 are the
  sanctioned pattern of one concept in two slices. Two are in §9.

### 3.3 Four test packages have no layering guard

A test package exports `test_<slice>()` and the static guard
`test_<slice>_layering()` beside it. Twenty-three guards exist. Four slices have
a suite and no guard.

| slice | suite | what to add | confidence |
| --- | --- | --- | --- |
| odbc | [test/odbc/OdbcSuite.jl](../../test/odbc/OdbcSuite.jl) | `test_odbc_layering()` | certain |
| sdl | [test/sdl/SdlSuite.jl](../../test/sdl/SdlSuite.jl) | `test_sdl_layering()` | certain |
| tulip | [test/tulip/TulipSuite.jl](../../test/tulip/TulipSuite.jl) | `test_tulip_layering()` | certain |
| video | [test/video/VideoSuite.jl](../../test/video/VideoSuite.jl) | `test_video_layering()` | certain |

The `projectured` umbrella has no `test_projectured_layering()` either. It has
`test_package_graph()` instead, which is the umbrella's equivalent. §9 asks
whether the rule must name that exception.

## 4. Module names

378 top-level declarations break down like this:

| class | count | state |
| --- | --- | --- |
| conformant | 323 | 119 package roots, 13 `<Concept>Module.jl`, 167 base rule, 24 projection exception |
| class A — a document module that drops `Document` | 30 | needs the decision in §9.1 |
| class B — the module carries a word the file does not | 13 | fix per row, §4.2 |
| class C — a file that declares more than one module | 6 declarations in 5 files | §4.4 |
| test fixture modules | 6 declarations in 3 files | needs the decision in §9.9 |

I applied the three exceptions the rules state, so no row below is an exception:

- a package root file `package/<P>/src/<P>.jl` declares the module `<P>`;
- a file already named `<Concept>Module.jl` declares `<Concept>Module`;
- a projection file `<Stem>.jl` declares `<Stem>ProjectionModule` (24 files do
  this correctly, and each one really declares the matching `<Stem>Projection`
  type).

450 files declare no module of their own. 445 are fragments that a parent
includes, which the rules allow, and every parent exists. The other five are not
Julia units at all: two build-time templates
([AppConfig.default.jl](../../source/executable/AppConfig.default.jl),
[Precompile.jl](../../source/executable/Precompile.jl)), one sub-process driver
script ([driver.jl](../../source/repl/record/driver.jl)) and two files that are
fixture data for a sample project under `example/filesystem/fixture/`.

No two files declare the same module name. That check came back empty.

### 4.1 Class A — a document file whose module drops `Document` (30 files) — CANCELLED

**The user decided on 2026-09-12 that a module is one unit of architecture, not
one file. See [one-module-per-slice.md](one-module-per-slice.md).** Under that
rule `JsonModule` in `JsonDocument.jl` is correct, so none of these 30 is a
violation and none is renamed. The 717 references stay as they are. The table
below records what the old rule would have demanded, and nothing more.

The file is `<Slice>Document.jl` and the module is `<Slice>Module`. The file
name is right, because the file declares the slice's documents, so the module
name is the one to change.

| file | has | proposed | references |
| --- | --- | --- | --- |
| [source/collection/CollectionDocument.jl](../../source/collection/CollectionDocument.jl) | `CollectionModule` | `CollectionDocumentModule` | 157 |
| [source/text/TextDocument.jl](../../source/text/TextDocument.jl) | `TextModule` | `TextDocumentModule` | 107 |
| [source/primitive/PrimitiveDocument.jl](../../source/primitive/PrimitiveDocument.jl) | `PrimitiveModule` | `PrimitiveDocumentModule` | 64 |
| [source/syntax/SyntaxDocument.jl](../../source/syntax/SyntaxDocument.jl) | `SyntaxModule` | `SyntaxDocumentModule` | 44 |
| [source/graphics/GraphicsDocument.jl](../../source/graphics/GraphicsDocument.jl) | `GraphicsModule` | `GraphicsDocumentModule` | 36 |
| [source/layout/LayoutDocument.jl](../../source/layout/LayoutDocument.jl) | `LayoutModule` | `LayoutDocumentModule` | 32 |
| [source/widget/WidgetDocument.jl](../../source/widget/WidgetDocument.jl) | `WidgetModule` | `WidgetDocumentModule` | 29 |
| [source/json/JsonDocument.jl](../../source/json/JsonDocument.jl) | `JsonModule` | `JsonDocumentModule` | 18 |
| [source/julia/JuliaDocument.jl](../../source/julia/JuliaDocument.jl) | `JuliaModule` | `JuliaDocumentModule` | 14 |
| [source/pane/PaneDocument.jl](../../source/pane/PaneDocument.jl) | `PaneModule` | `PaneDocumentModule` | 12 |
| [source/graph/GraphDocument.jl](../../source/graph/GraphDocument.jl) | `GraphModule` | `GraphDocumentModule` | 12 |
| [source/process/ProcessDocument.jl](../../source/process/ProcessDocument.jl) | `ProcessModule` | `ProcessDocumentModule` | 10 |
| [source/markdown/MarkdownDocument.jl](../../source/markdown/MarkdownDocument.jl) | `MarkdownModule` | `MarkdownDocumentModule` | 10 |
| [source/xml/XmlDocument.jl](../../source/xml/XmlDocument.jl) | `XmlModule` | `XmlDocumentModule` | 9 |
| [source/rst/RstDocument.jl](../../source/rst/RstDocument.jl) | `RstModule` | `RstDocumentModule` | 9 |
| [source/fsm/FsmDocument.jl](../../source/fsm/FsmDocument.jl) | `FsmModule` | `FsmDocumentModule` | 9 |
| [source/filesystem/FileSystemDocument.jl](../../source/filesystem/FileSystemDocument.jl) | `FileSystemModule` | `FileSystemDocumentModule` | 9 |
| [source/conversation/ConversationDocument.jl](../../source/conversation/ConversationDocument.jl) | `ConversationModule` | `ConversationDocumentModule` | 9 |
| [source/assistant/AssistantDocument.jl](../../source/assistant/AssistantDocument.jl) | `AssistantModule` | `AssistantDocumentModule` | 8 |
| [source/chart/ChartDocument.jl](../../source/chart/ChartDocument.jl) | `ChartModule` | `ChartDocumentModule` | 7 |
| [source/yaml/YamlDocument.jl](../../source/yaml/YamlDocument.jl) | `YamlModule` | `YamlDocumentModule` | 6 |
| [source/workbench/WorkbenchDocument.jl](../../source/workbench/WorkbenchDocument.jl) | `WorkbenchModule` | `WorkbenchDocumentModule` | 5 |
| [source/sequencechart/SequenceChartDocument.jl](../../source/sequencechart/SequenceChartDocument.jl) | `SequenceChartModule` | `SequenceChartDocumentModule` | 5 |
| [source/math/MathDocument.jl](../../source/math/MathDocument.jl) | `MathModule` | `MathDocumentModule` | 5 |
| [source/gesturelog/GestureLogDocument.jl](../../source/gesturelog/GestureLogDocument.jl) | `GestureLogModule` | `GestureLogDocumentModule` | 5 |
| [source/versioning/VersioningDocument.jl](../../source/versioning/VersioningDocument.jl) | `VersioningModule` | `VersioningDocumentModule` | 4 |
| [source/book/BookDocument.jl](../../source/book/BookDocument.jl) | `BookModule` | `BookDocumentModule` | 4 |
| [source/formula/FormulaDocument.jl](../../source/formula/FormulaDocument.jl) | `FormulaModule` | `FormulaDocumentModule` | 3 |
| [source/clipboard/ClipboardDocument.jl](../../source/clipboard/ClipboardDocument.jl) | `ClipboardModule` | `ClipboardDocumentModule` | 3 |
| [source/component/ComponentDocument.jl](../../source/component/ComponentDocument.jl) | `ComponentModule` | `ComponentDocumentModule` | 2 |

This class is closed. [one-module-per-slice.md](one-module-per-slice.md) holds
the decision and the reasoning.

### 4.2 Class B — the module carries a word the file name does not (13 files)

**Most of this class dissolves.** A slice becomes one module, so a module name
that only exists because a file needed one disappears with it. Only the rows
that rename a **file** survive, and they survive for their own reasons — a
duplicate basename, or a projection stem that does not agree with itself. The
`module` column below records what is there today, not what must change.

Here either name can change, so each row states which one I propose and why.

| file | has | proposed fix | confidence |
| --- | --- | --- | --- |
| [source/graph/omnetpp/LayoutGeometry.jl](../../source/graph/omnetpp/LayoutGeometry.jl) | `LayoutGeometryModule` | rename the file to `LayoutGeometry.jl`. [source/style/Geometry.jl](../../source/style/Geometry.jl) already owns `GeometryModule`, so this file can not take the base name. The rename also removes a duplicate basename. | certain |
| [source/inspector/ReferenceInspector.jl](../../source/inspector/ReferenceInspector.jl) | `ReferenceInspectorDocumentModule` | rename the module to `ReferenceInspectorModule`. No sibling claims that name. | likely |
| [source/database/DatabaseInstance.jl](../../source/database/DatabaseInstance.jl) | `DatabaseInstanceDocumentModule` | rename the module to `DatabaseInstanceModule`. No sibling claims that name. | likely |
| [source/syntax/InsertionToSyntax.jl](../../source/syntax/InsertionToSyntax.jl) | `DocumentInsertionToSyntaxModule` | rename the module to `InsertionToSyntaxModule`. The sibling [source/julia/JuliaInsertionToSyntax.jl](../../source/julia/JuliaInsertionToSyntax.jl) follows the base rule exactly. | likely |
| [source/text/TextLineNumbering.jl](../../source/text/TextLineNumbering.jl) | `TextLineNumberingModule` | rename the file to `TextLineNumbering.jl`. Every other projection file in `source/text/` carries `Text` in the file name. | likely |
| [source/gesturelog/GestureLogRecording.jl](../../source/gesturelog/GestureLogRecording.jl) | `GestureLogRecordingProjectionModule` | rename the file to `GestureLogRecording.jl`. The module, the type `GestureLogRecordingProjection` and the IO map already agree on the stem `GestureLogRecording`; only the file disagrees. | certain |
| [source/database/DatabaseAdapters.jl](../../source/database/DatabaseAdapters.jl) | `DatabaseModule` | rename the module to `DatabaseAdaptersModule`. The sibling `DatabaseDocument.jl` already declares `DatabaseDocumentModule`, so the bare name was free only by accident. | likely |
| [source/console/Console.jl](../../source/console/Console.jl) | `ConsoleBackendModule` | rename the file to `ConsoleBackend.jl`, or sanction `Backend` as a qualifier. See §9.10. | unsure |
| [source/pdf/Pdf.jl](../../source/pdf/Pdf.jl) | `PdfBackendModule` | rename the file to `PdfBackend.jl`, or sanction `Backend`. See §9.10. | unsure |
| [source/kernel/projection/GestureBindings.jl](../../source/kernel/projection/GestureBindings.jl) | `ProjectionGestureBindingsModule` | **no change.** The user decided on 2026-09-12 that the kernel keeps its modules as they are. See [one-module-per-slice.md](one-module-per-slice.md). | closed |
| [source/repl/Repl.jl](../../source/repl/Repl.jl#L88) | `StatementScope` | a one-line `module StatementScope end` with no `Module` suffix. Its docstring says it exists only as a namespace for dynamic bindings and is never exported. Leave it and state the exemption, or rename it. See §9.12. | unsure |
| [source/clipboard/ClipboardToAny.jl](../../source/clipboard/ClipboardToAny.jl) | `ClipboardToAnyProjectionModule` | see §7 — the file holds two projection stems. | likely |
| [source/dragging/Dragging.jl](../../source/dragging/Dragging.jl) | `DraggingProjectionModule` | the module matches the file, but the file name bakes in `Projection`. See §7. | certain |

### 4.3 A second, undeclared name for a module — 29 alias lines

A package root may hold module aliases. Six of them give a module a name that no
file declares, so a reader who greps the name finds no `module` line. That is
the exact bidirectional guess the law promises.

| alias | target | alias lines | fix |
| --- | --- | --- | --- |
| `DocumentApiModule` | `ProjecturedKernel.DocumentModule` | 10 | delete the alias, use `DocumentModule` |
| `OperationApiModule` | `ProjecturedKernel.OperationModule` | 7 | delete the alias, use `OperationModule` |
| `ReferenceCaseModule` | `ProjecturedKernel.ReferenceModule` | 4 | delete the alias, use `ReferenceModule` |
| `ReferenceBuilderModule` | `ProjecturedKernel.ReferenceModule` | 4 | delete the alias, use `ReferenceModule` |
| `OperationRerootingModule` | `ProjecturedKernel.OperationModule` | 3 | delete the alias, use `OperationModule` |
| `BackendApiModule` | `ProjecturedKernel.BackendModule` | 1 | delete the alias, use `BackendModule` |

[test/projectured/PackageGraphTest.jl:233](../../test/projectured/PackageGraphTest.jl#L233) holds
the table of these deprecated names. Shrink it as each alias goes, and delete it
when the last one goes. The table also lists three names that no longer appear
anywhere: `SelectionApiModule`, `ReferenceApiModule` and
`ProjectionReferenceStepApiModule`. Remove those three rows now.

### 4.4 Class C — a file that declares more than one module

The law gives a file one module. Two files in `source/` break it.

| file | declares | fix | confidence |
| --- | --- | --- | --- |
| `source/odbc/Odbc.jl`, now split into four files | `OdbcAdapterModule` (line 1), `ConnectionPoolModule` (251), `SqlToCellTableModule` (365), `DatabaseInstanceToDbCatalogModule` (415) | split into four files, each named for its module. Every module name is already correct, so only the split is needed. | certain |
| [source/dragging/Dragging.jl](../../source/dragging/Dragging.jl) | `DraggingProjectionModule` (29), `DraggingWrapperModule` (307) | move the second module to `DraggingWrapper.jl` | certain |

Three files under `test/` declare six fixture modules:
[test/kernel/tool/DeclaredApiTest.jl](../../test/kernel/tool/DeclaredApiTest.jl)
(`ToyApi`, `ToyShaped`, `ToyExtra`),
[test/substrate/projection/ProjectionTemplateTest.jl](../../test/substrate/projection/ProjectionTemplateTest.jl)
(two probes) and
[test/projectured/ExportCollisionTest.jl](../../test/projectured/ExportCollisionTest.jl)
(`CollisionFixture`, which itself holds four nested modules on purpose). Julia
allows `module` only at the top level, so a test that needs a module has no other
place to put it. §9.9 asks whether these are exempt.

Two declarations that a first pass reports are **not** declarations: `FooFsm` in
[source/fsm/FsmToJuliaCode.jl](../../source/fsm/FsmToJuliaCode.jl) sits inside a
fenced example in a docstring, and `ProbeRuntime` in
[test/fsm/projection/FsmToJuliaCodeTest.jl](../../test/fsm/projection/FsmToJuliaCodeTest.jl)
sits inside a string that the test feeds to `Base.include_string`. Do not change
either one.

## 5. Type names

1443 declarations examined: 1358 `struct` and `mutable struct`, 77
`abstract type`, 8 `const` type aliases. No `primitive type` exists. A bare grep
for `struct` finds only about a third of them, because `@document`,
`@projection`, `@iomap` and `@cell_struct` put the keyword after the macro; the
count above resolves all four macros.

1291 struct names, 68 abstract type names and 5 of the 8 aliases conform.

### 5.1 An exception without the `Exception` suffix

| name | file:line | proposed name | confidence |
| --- | --- | --- | --- |
| `ProcessStopped` | [ProcessRuntime.jl:47](../../source/process/ProcessRuntime.jl#L47) | `ProcessStoppedException` | certain |
| `ReferenceTypeMismatch` | [ReferenceStep.jl:189](../../source/kernel/reference/ReferenceStep.jl#L189) | `ReferenceTypeMismatchException` | certain |
| `SelectionMismatch` | [SelectionDefaults.jl:65](../../source/kernel/selection/SelectionDefaults.jl#L65) | `SelectionMismatchException` | certain |

All three are `<: Exception`. I checked each declaration.
[SelectionDefaults.jl](../../source/kernel/selection/SelectionDefaults.jl) is
the one **sealed** file that a finding names — see §12.

### 5.2 An operation that is not verb-first

| name | file:line | proposed name | confidence |
| --- | --- | --- | --- |
| `DatabaseUpdateOperation` | [DatabaseDocument.jl:41](../../source/database/DatabaseDocument.jl#L41) | `UpdateDatabaseCellOperation` | certain |
| `DatabaseInsertOperation` | [DatabaseDocument.jl:52](../../source/database/DatabaseDocument.jl#L52) | `InsertDatabaseRowOperation` | certain |
| `NewTabRequestOperation` | [WidgetDocument.jl:2122](../../source/widget/WidgetDocument.jl#L2122) | `OpenTabOperation` — `New` is an adjective, and §7.3 already drops `Request` | certain |
| `ToyPathOp` | [RerootingTest.jl:17](../../test/kernel/operation/RerootingTest.jl#L17) | `ToyPathOperation` — it is `<: Operation`, lacks the suffix, and abbreviates `operation` to `op` | certain |
| `FrameDrainOperation` | [FrameDrainTest.jl:24](../../test/kernel/editor/FrameDrainTest.jl#L24) | `DrainFrameOperation` | likely |
| `FrameDrainSwapOperation` | [FrameDrainTest.jl:32](../../test/kernel/editor/FrameDrainTest.jl#L32) | `DrainFrameSwapOperation` | likely |
| `InboxProbeOperation` | [InboxTest.jl:31](../../test/kernel/editor/InboxTest.jl#L31) | `ProbeInboxOperation` | likely |
| `CollectedIntentsOperation` | [Intent.jl:129](../../source/kernel/operation/Intent.jl#L129) | `Collected` is a past participle. The docstring models the type on `CompoundOperation`, the one named exception, but does not claim the exemption. Name it as a second exception, or rename it. | unsure |

The rule's own forbidden example is this exact noun-then-verb shape, so the
first two rows need no judgement.

### 5.3 Four or more nouns in a row

| name | file:line | proposed name | confidence |
| --- | --- | --- | --- |
| `ToggleClipboardSliceDisplayOperation` | [ClipboardToAny.jl:251](../../source/clipboard/ClipboardToAny.jl#L251) | `ToggleClipboardSliceOperation` | certain |
| `ToggleClipboardCollectionDisplayOperation` | [ClipboardToAny.jl:267](../../source/clipboard/ClipboardToAny.jl#L267) | `ToggleClipboardCollectionOperation` | certain |

### 5.4 A coded document prefix on a hand-written type

The prefixes `A`, `AC`, `M`, `I`, `RC`, `IC`, `MC` and `DC` belong to
`@document`. Three hand-written names take one and mean something else.

| name | file:line | proposed name | confidence |
| --- | --- | --- | --- |
| `IBody` | [ForceDirectedParametersBase.jl:150](../../source/graph/omnetpp/ForceDirectedParametersBase.jl#L150) | `AbstractBody` — the same file already uses `AbstractElectricRepulsion` and `AbstractSpring` for an open interface | certain |
| `IForceProvider` | [ForceDirectedParametersBase.jl:158](../../source/graph/omnetpp/ForceDirectedParametersBase.jl#L158) | `AbstractForceProvider` | certain |
| `IC` (alias) | [colorbench.jl:18](../../test/bench/colorbench.jl#L18) | delete the alias and write `ImmutableCell` — `IC` reads as the generated cell-layout prefix | likely |

### 5.5 An abbreviated word inside a type name

The rules name `val`, `fn`, `ref`, `op`, `perf` and `eval` as forbidden, and
sanction only `Api`, `IoMap`, the generated `I<Document>` prefix, `ctor` and
`expr`.

| name | file:line | proposed name | confidence |
| --- | --- | --- | --- |
| `RefStep` and 11 siblings — `RefField`, `RefFieldExpr`, `RefIndex`, `RefPosition`, `RefRange`, `RefType`, `RefSplice`, `RefTailBind`, `RefArgValue`, `RefArgSubPath`, `RefExtension` | [ReferenceSyntax.jl:22-106](../../source/kernel/reference/ReferenceSyntax.jl#L22) | `ReferenceSyntaxStep` and so on. `ref` is the rule's own named example. `RefStep` is also confusable with the unrelated `ReferenceStep` that already exists in `ReferenceInterface.jl`. | certain |
| `JuliaBinaryOp`, `JuliaUnaryOp` | [JuliaDocument.jl:102,111](../../source/julia/JuliaDocument.jl#L102) | `JuliaBinaryOperation`, `JuliaUnaryOperation`. The Math domain spells the same concept out. | certain |
| `JuliaBinaryOpToSyntaxNode`, `JuliaUnaryOpToSyntaxNode` | [JuliaToSyntax.jl:197,217](../../source/julia/JuliaToSyntax.jl#L197) | carry the fix through to the projection names | certain |
| `JuliaModuleDef`, `JuliaModuleDefToSyntaxNode` | [JuliaDocument.jl:314](../../source/julia/JuliaDocument.jl#L314), [JuliaToSyntax.jl:338](../../source/julia/JuliaToSyntax.jl#L338) | `JuliaModuleDefinition`, `JuliaModuleDefinitionToSyntaxNode` | certain |
| `PageCtx`, `FontReg` | [Pdf.jl:122,114](../../source/pdf/Pdf.jl#L114) | `PageContext`, `FontRegistration`. `ctx` is the rule's own named example. | certain |
| `WebConn` | [Web.jl:15](../../source/web/Web.jl#L15) | `WebConnection` | certain |
| `SelSeg`, `WrapSeg`, `HighlightSeg`, `SegCoord` | [SelectionInverting.jl:85](../../source/text/SelectionInverting.jl#L85), [WordWrapping.jl:65](../../source/text/WordWrapping.jl#L65), [TextHighlighting.jl:84](../../source/text/TextHighlighting.jl#L84), [TextToGraphics.jl:59](../../source/text/TextToGraphics.jl#L59) | `SelectionSegment`, `WrapSegment`, `HighlightSegment`, `SegmentCoordinate` | certain |
| `RCV` (alias) | [CellVector.jl:89](../../source/collection/CellVector.jl#L89) | `ReactiveCellVector` | certain |
| `EvalChild`, `EvalDoc`, `EvalLeaf`, `EvalBranch` | [ReferenceBuilderTest.jl:21,24](../../test/kernel/reference/ReferenceBuilderTest.jl#L21), [ReferenceEvalTest.jl:14,18](../../test/kernel/reference/ReferenceEvalTest.jl#L14) | `eval` is the rule's own named example | certain |
| `_Cur` | [JsonParser.jl:25](../../source/json/JsonParser.jl#L25), [XmlParser.jl:25](../../source/xml/XmlParser.jl#L25) | `_Cursor`. The leading underscore marks it private, which may put it out of scope. | likely |
| `WriteOsClipboardOperation` | [ClipboardToAny.jl:285](../../source/clipboard/ClipboardToAny.jl#L285) | `Os` may be the kind of well-known abbreviation the rule sanctions. Leave, or write `WriteOSClipboardOperation`. | unsure |

Two more are lower case where the rules and Julia both want CamelCase:
`shared` twice in
[ExportCollisionTest.jl:116,121](../../test/projectured/ExportCollisionTest.jl#L116).
Both are deliberate fixture data for an export-collision test, so they may be
intentional.

### 5.6 Two false positives I discarded

`MathBinaryOperation` and `MathUnaryOperation`
([MathDocument.jl:84,93](../../source/math/MathDocument.jl#L84)) end in
`Operation` and are not verb-first. I checked the declarations: both are
`@document struct … <: MathDocument`, so they are document nouns and the
Operations rule does not reach them. "A binary operation" is a noun phrase.
§9.17 asks whether the rule should say that the `Operation` suffix is reserved.

## 6. Function names and constant names

2420 distinct exported names across the three trees: 1207 functions, 279
constants, 907 types and 21 macros. A per-line grep for `export` undercounts
this badly, because one statement can wrap over dozens of lines — the statement
at [Font.jl:13](../../source/style/Font.jl#L13) names 155 identifiers and the one
at [Color.jl:12](../../source/style/Color.jl#L12) names 107. The count above
comes from a parse with Julia's own parser, and it supersedes the figure of 685
that my own first grep produced.

703 functions and 18 constants conform. 64 names are violations. No method that
extends a Julia Base generic is in the list; each one keeps its foreign name.

### 6.1 A mutating function that starts with a noun

Every name here ends with `!`, so it is an action and must start with a verb.

| name | file:line | proposed name | confidence |
| --- | --- | --- | --- |
| `db_close!`, `db_connect!`, `db_delete!`, `db_insert!`, `db_update!` | [DatabaseAdapters.jl:56-98](../../source/database/DatabaseAdapters.jl#L56) | `close_db!`, `connect_db!`, `delete_from_db!`, `insert_into_db!`, `update_db!` | certain |
| `mcp_start!`, `mcp_stop!` | [Mcp.jl:57,81](../../source/mcp/Mcp.jl#L57) | `start_mcp!`, `stop_mcp!`. A verb-first wrapper `start_agent_server!` already calls the first. | certain |
| `heap_embed!` | [HeapEmbedding.jl:73](../../source/graph/omnetpp/HeapEmbedding.jl#L73) | `embed_heap!` — the verb sits at the end | certain |
| `star_tree_embed!` | [StarTreeEmbedding.jl:45](../../source/graph/omnetpp/StarTreeEmbedding.jl#L45) | `embed_star_tree!` | certain |
| `wall_set_position!`, `wall_set_variable!` | [ForceDirectedParameters.jl:116,122](../../source/graph/omnetpp/ForceDirectedParameters.jl#L116) | `set_wall_position!`, `set_wall_variable!` | certain |
| `uniform!` | [LcgRandom.jl:70](../../source/graph/omnetpp/LcgRandom.jl#L70) | `sample_uniform!` — `uniform` is an adjective | likely |
| `next01!` | [LcgRandom.jl:56](../../source/graph/omnetpp/LcgRandom.jl#L56) | `advance_uniform01!` | likely |

### 6.2 Words glued together

The rules say: snake_case, with an underscore between all words.

| name | file:line | proposed name | confidence |
| --- | --- | --- | --- |
| `insertrow!`, `insertcol!`, `deleterow!`, `deletecol!` | [CellMatrix.jl:57,69,81,91](../../source/collection/CellMatrix.jl#L57) | `insert_row!`, `insert_col!`, `delete_row!`, `delete_col!` | certain |
| `jsonparse`, `jsonparse_file` | [JsonParser.jl:159,172](../../source/json/JsonParser.jl#L159) | `parse_json`, `parse_json_file` | certain |
| `juliaparse`, `juliaparse_file` | [JuliaParser.jl:56,73](../../source/julia/JuliaParser.jl#L56) | `parse_julia`, `parse_julia_file` | certain |
| `markdownparse`, `markdownparse_file` | [MarkdownParser.jl:180,192](../../source/markdown/MarkdownParser.jl#L180) | `parse_markdown`, `parse_markdown_file` | certain |
| `rstparse`, `rstparse_file` | [RstParser.jl:752,763](../../source/rst/RstParser.jl#L752) | `parse_rst`, `parse_rst_file` | certain |
| `sqlparse`, `sqlparse_file` | [SqlParser.jl:48,61](../../source/sql/SqlParser.jl#L48) | `parse_sql`, `parse_sql_file` | certain |
| `xmlparse`, `xmlparse_file` | [XmlParser.jl:149,162](../../source/xml/XmlParser.jl#L149) | `parse_xml`, `parse_xml_file` | certain |
| `yamlparse`, `yamlparse_file` | [YamlParser.jl:319,330](../../source/yaml/YamlParser.jl#L319) | `parse_yaml`, `parse_yaml_file` | certain |
| `dbcatalog_marker_eligible` | [DbCatalogToSyntax.jl:344](../../source/dbcatalog/DbCatalogToSyntax.jl#L344) | `is_db_catalog_marker_eligible` — the sibling family spells it `db_catalog_*` | likely |

The four `CellMatrix` names are the strongest rows in the whole collection.
[naming-rules.md:275](../../documentation/rule/naming-rules.md#L275) reads
"`insert_row!`, not `insertrow!`", and the quick reference gives `insert_row!` as
the example of a correct name. The rule names the real function in this
repository as its own counter-example.

### 6.3 A function that starts with a noun

| name | file:line | proposed name | confidence |
| --- | --- | --- | --- |
| `api_entry_names` | [Tool.jl:66](../../source/kernel/tool/Tool.jl#L66) | `get_api_entry_names` | certain |
| `api_modules` | [Tool.jl:87](../../source/kernel/tool/Tool.jl#L87) | `get_api_modules` | certain |
| `anchor` | [LayoutDocument.jl:731](../../source/layout/LayoutDocument.jl#L731) | `get_anchor` | certain |
| `anchor_offset` | [PlotGeometry.jl:676](../../source/plot/PlotGeometry.jl#L676) | `get_anchor_offset` | certain |
| `anchor_point` | [WidgetToGraphics.jl:120](../../source/widget/WidgetToGraphics.jl#L120) | `get_anchor_point` | certain |

### 6.4 A predicate that starts with neither `is_` nor `has_`

| name | file:line | proposed name | confidence |
| --- | --- | --- | --- |
| `insertable` | [Domain.jl:207](../../source/domain/Domain.jl#L207) | `is_insertable` | certain |
| `keeps_dormant_selection` | [SelectionInterface.jl:82,102](../../source/kernel/selection/SelectionInterface.jl#L82) | `has_dormant_selection` | certain |
| `affine_is_axis_aligned` | [Geometry.jl:161](../../source/style/Geometry.jl#L161) | `is_affine_axis_aligned` — the marker sits mid-name | certain |
| `math_accent_is_wide` | [MathDocument.jl:444](../../source/math/MathDocument.jl#L444) | `is_math_accent_wide` | certain |
| `math_big_operator_is_text` | [MathDocument.jl:409](../../source/math/MathDocument.jl#L409) | `is_math_big_operator_text` | certain |
| `color_equal`, `color_equal_safe` | [Color.jl:1208,1217](../../source/style/Color.jl#L1208) | `is_color_equal`, `is_color_equal_safe` | certain |
| `filesystem_marker_eligible` | [FileSystemToSyntax.jl:219](../../source/filesystem/FileSystemToSyntax.jl#L219) | `is_filesystem_marker_eligible` | certain |
| `db_alive` | [DatabaseAdapters.jl:64](../../source/database/DatabaseAdapters.jl#L64) | `is_db_alive` — also noun-first | certain |
| `point_near_polyline`, `point_in_polygon` | [GraphicsDocument.jl:509,531](../../source/graphics/GraphicsDocument.jl#L509) | `is_point_near_polyline`, `is_point_in_polygon` | likely |
| `default_gesture_log_filter` | [GestureLogDocument.jl:111](../../source/gesturelog/GestureLogDocument.jl#L111) | `?` — a filter-callback name, so a rename may fight Julia's own `filter(pred, …)` idiom | likely |

### 6.5 An abbreviated word

| name | file:line | proposed name | confidence |
| --- | --- | --- | --- |
| `composer_host_op` | [ConversationEditor.jl:779](../../source/conversation/ConversationEditor.jl#L779) | `composer_host_operation` | certain |
| `text_insert_op` | [TextDocument.jl:719](../../source/text/TextDocument.jl#L719) | `text_insert_operation` | certain |
| `eval_kind_label` | [Evaluator.jl:69](../../source/conversation/Evaluator.jl#L69) | `evaluation_kind_label` | certain |
| `test_reference_eval` | [ReferenceEvalTest.jl:27](../../test/kernel/reference/ReferenceEvalTest.jl#L27) | `test_reference_evaluation` | certain |
| `nav_broken` | [ExampleSweeps.jl:430](../../test/projectured/editor/ExampleSweeps.jl#L430) | `navigation_broken` | certain |
| `test_text_nav_invariants` | [ClickRoundtripTest.jl:380](../../test/substrate/editor/ClickRoundtripTest.jl#L380) | `test_text_navigation_invariants` | certain |
| `test_text_nav_invariants_all` | [ExampleSweeps.jl:438](../../test/projectured/editor/ExampleSweeps.jl#L438) | `test_text_navigation_invariants_all` | certain |
| `_path_contains_projection_ref` | [ClickRoundtripTest.jl:88](../../test/substrate/editor/ClickRoundtripTest.jl#L88) | `_path_contains_projection_reference` | certain |
| `EVAL_HANDLER` | [ConversationEditor.jl:751](../../source/conversation/ConversationEditor.jl#L751) | `EVALUATE_HANDLER` | certain |
| `POSITION_NAV_KEYS`, `TREE_NAV_KEYS` | [NavigationPresets.jl:20,36](../../test/substrate/editor/NavigationPresets.jl#L20) | `POSITION_NAVIGATION_KEYS`, `TREE_NAVIGATION_KEYS` | certain |

### 6.6 A mutation with no `!`

| name | file:line | proposed name | confidence |
| --- | --- | --- | --- |
| ~~`focus_pane`, `close_pane`, `move_pane`, `resize_pane`~~ | [PaneProgram.jl](../../source/pane/PaneProgram.jl) | **done 2026-09-13.** `focus_pane!` has the `!` and takes a reference; the other three went, because each is a value written at a reference. See [assistant-api-consolidation.md](assistant-api-consolidation.md). | done |

### 6.7 One row I discarded

The agent reported `entries`, exported at
[JsonDocument.jl:23](../../source/json/JsonDocument.jl#L23), as a bare noun
getter. I checked: `entries` is not a function. It is the
`entries::CellVector` field of `@document JsonObject`, and the export makes the
field name resolve as API, which `PAR-FIELD-NAMES-ARE-API` requires. The
verb-first rule does not reach a field name.

### 6.8 Two exported names have no definition

This is a bug, not a naming violation, and it belongs in a separate report. Both
shapes are correct.

| name | file:line | state |
| --- | --- | --- |
| `test_domain` | [ProjecturedSuite.jl:339](../../test/projectured/ProjecturedSuite.jl#L339) | exported once, defined nowhere. Three docstrings cite it as callable. Only `test_domain_examples()` exists. |
| `make_assistant_mvp_projection` | [ProjecturedSuite.jl:366](../../test/projectured/ProjecturedSuite.jl#L366) | exported once, defined nowhere. `make_assistant_mvp_setup` on the same line does exist. |

## 7. Projection stems and the pipeline ladder

36 types end in `Projection`: 35 concrete and one abstract. Four of the 35 are
disposable test doubles with no file, module or IO map of their own, so 32 carry
a stem. The rule is that one stem gives all four names: file `<Stem>.jl`, type
`<Stem>Projection`, module `<Stem>ProjectionModule`, IO map
`<Stem>ProjectionIoMap`.

Conformant: the nine gerund stems with a dedicated IO map (`Copying`,
`Filtering`, `Searching`, `Sorting`, `Chaining`, `Nesting`,
`ReferenceDispatching`, `Switching`, `WindowInputUnwrapping`), `WindowManaging`,
the three sanctioned non-gerunds (`Identity`, `Constant`, `Recursive`) and six
single-stem domain projections (`HoverProbe`, `TooltipDecorator`,
`VersioningToAny`, `ProjectionConfiguring`, `WidgetHoverTracking`,
`WidgetPopupResolver`).

### 7.1 A stem that disagrees with itself

| name | file:line | rule broken | proposed name | confidence |
| --- | --- | --- | --- | --- |
| `WorkspaceWorkspaceProjection` | [WorkspaceToFileSystem.jl:62](../../source/workbench/WorkspaceToFileSystem.jl#L62) | The type repeats `Workspace` and matches the file, the module and even its own comment on line 60 (`WorkspaceWorkspaceToSyntax`) none. | `WorkspaceToFileSystemDirectory`, parallel to the sibling `WorkspaceFolderToFileSystemDirectory` | certain |
| `CommandPaletteProjection`, `CommandPaletteProjectionIoMap` | [CommandPaletteDecorator.jl:114,140](../../source/gesturehelp/CommandPaletteDecorator.jl#L114) | The file and the module carry the stem `CommandPaletteDecorator`; the type and the IO map drop `Decorator`. | `CommandPaletteDecoratorProjection`, `CommandPaletteDecoratorProjectionIoMap` | certain |
| `GestureHelpProjection`, `GestureHelpProjectionIoMap` | [GestureHelpDecorator.jl:76,95](../../source/gesturehelp/GestureHelpDecorator.jl#L76) | Same rule, same shape. | `GestureHelpDecoratorProjection`, `GestureHelpDecoratorProjectionIoMap` | certain |
| `GestureLogRecordingProjection` | [GestureLogRecording.jl:43](../../source/gesturelog/GestureLogRecording.jl#L43) | The type, the module and the IO map agree on `GestureLogRecording`; the file says `Recorder`. | rename the file to `GestureLogRecording.jl` | certain |
| `DraggingProjection` | [Dragging.jl:77](../../source/dragging/Dragging.jl#L77) | The file must be `<Stem>.jl`. This is the only stem file in the repository that bakes `Projection` into its own name. | rename the file to `Dragging.jl` | certain |
| `ClipboardSliceToAnyProjection`, `ClipboardCollectionToAnyProjection` | [ClipboardToAny.jl:94,110](../../source/clipboard/ClipboardToAny.jl#L94) | The file and the module say `ClipboardToAny`, which is neither type's stem. | split into `ClipboardSliceToAny.jl` and `ClipboardCollectionToAny.jl`, one module each | likely |

Both decorators keep `Decorator` in all four names rather than dropping it,
because the sibling `TooltipDecoratorProjection` already does. That is the
precedent, and it costs two type renames instead of two file renames.

### 7.2 Four gerund stems sit in the wrong folder

[naming-rules.md](../../documentation/rule/naming-rules.md) names `Copying`,
`Filtering`, `Searching` and `Sorting` as `generic/` stems. All four files sit
directly in `source/projection/` instead. Move them into
`source/projection/generic/`, which then holds all eight generic stems.

`source/projection/` also holds [ReaderDefaults.jl](../../source/projection/ReaderDefaults.jl),
which is not a projection, and a third folder the rule does not mention,
`source/projection/compound/`, with `GenericCompound.jl` and
`HigherOrderCompound.jl`. §9.13 asks what the rule should say about both.

### 7.3 One operation competes with the Intent rung

| name | file:line | rule broken | proposed name | confidence |
| --- | --- | --- | --- | --- |
| `CloseTabRequestOperation`, `NewTabRequestOperation` | [WidgetDocument.jl:2111,2122](../../source/widget/WidgetDocument.jl#L2111) | "The pipeline ladder" — no two rungs are synonyms, and `Request` is not a word the ladder uses. Both `evaluate_operation` bodies return `nothing`, and both docstrings say the type only reports, so the projection that owns the tabs answers it. The siblings `SelectTabOperation` and `DragTabOperation` carry the same meaning with no `Request`. | `CloseTabOperation`, `NewTabOperation`, with the deferred nature stated in the docstring only | certain |

Every other candidate word (`edit`, `command`, `action`, `change`, `message`)
resolved to something else: an LLM message, a widget node, a GUI string, or a
local variable, which the rules place out of scope.

## 8. Documentation identifiers

The identifiers are clean. 44 `PR-…` ids carry 96 citations and 77 `PAR-…` ids
carry 206 citations. Each id is defined exactly once, in the file the rule
names, and every citation resolves to a definition. No id is defined twice, no
citation dangles, and no other `SCREAMING-KEBAB-CASE` prefix pretends to be a
claim identifier.

### 8.1 Three documents have no header

Every document in `documentation/` carries a one-line header naming its Kind,
its Status and what it Stands on. 57 of 60 do.

| file | fix | confidence |
| --- | --- | --- |
| [documentation/package/adaptagrams/README.md](../../documentation/package/adaptagrams/README.md) | add the header under the title | certain |
| [documentation/package/executable/README.md](../../documentation/package/executable/README.md) | add the header under the title | certain |
| [documentation/presentation/projectured-overview.md](../../documentation/presentation/projectured-overview.md) | **no change.** The user decided on 2026-09-12 to exempt a slide deck. Marp renders the file, so a block-quote after the front matter shows as text on slide one. `documentation/README.md` now states the exemption. | closed |

### 8.3 A stale block in the module inventory — DONE 2026-09-13

[system-anatomy.md:165-173](../../documentation/design/system-anatomy.md#L165)
holds a block-quote that exists to correct stale per-file paths, and the
correction is itself stale. It says the code "now lives across the four
packages" and maps files to `base/main/`, `visual/main/` and `domain/main/`.
None of those three trees exists, and the repository holds 119 packages under
`source/<slice>/`, not four.

**Fixed.** The block now says the truth: every file the inventory cites lives in
`source/<slice>/`, one folder per slice, and a slice's document file is
`<Slice>Document.jl`.

The audit it needed found more. Seventeen file names the inventory cited did not
exist: fifteen were the `<Slice>Document.jl` rename this plan made, `Operation.jl`
is `Operations.jl`, and `Table.jl` described a document family — `TableCell`,
`TableRow`, `TableColumn`, `TableTable` — that exists nowhere in the repository.
That row is deleted. Every file the inventory names now exists.

### 8.2 One rule sentence is stale

The section "Files and modules" says: "**`Api` is a layer marker carried in the
filename.** Every file in `api/` ends in `Api`." No `api/` folder exists any
more. One file keeps the marker:
[source/kernel/projection/ProjectionApi.jl](../../source/kernel/projection/ProjectionApi.jl),
which declares `ProjectionApiModule` and is correct under the base rule. Rewrite
the sentence so it describes the one file that exists, and stop promising a
folder that does not.

## 9. Questions for the user

These rows need a decision before the fix. Each one is a class, not one name.

1. **The 30 document modules (§4.1).** The file rule says the primary document
   file is `<Slice>Document.jl`, and the module rule says the module is the file
   name plus `Module`. Together they give `JsonDocumentModule`, and 30 files say
   `JsonModule` instead. Rename the 30 modules and rewrite 717 references, or
   add a sentence to the rule that a slice's document module drops `Document`?
   I recommend the rename: the rule is stated twice, once in naming-rules.md and
   once in `PAR-NAMING-LAW`, and a second exception costs more than the rename.
2. **97 test file names (§3.2).** 97 of the 191 `test/*Test.jl` files name a
   feature and not a file in `source/` — for example
   [test/substrate/projection/PaneDragTest.jl](../../test/substrate/projection/PaneDragTest.jl).
   The rule already names two such classes by example. Does it intend the same
   reading for the other 97, or must each one map to a real `source/` file?
3. **A catch-all row for `test/` and `example/`.** `source/`'s shape table has a
   `<Thing>.jl` row for a file that is neither a document nor a projection.
   `test/` and `example/` have no such row, and 18 files need one: 7 shared
   fixtures under `test/` (`CheckLayering.jl`, `SelectionEnumeration.jl`,
   `NavigationPresets.jl`, `ExampleSweeps.jl`, `tree.jl` and two more) and 11
   under `example/` (`Harness.jl`, `Gallery.jl`, `Catalog.jl`, `Precompile.jl`
   and more). Add the row, or rename the 18 files?
4. **The umbrella's own slice.** `Projectured` removes its own name as the
   prefix and leaves an empty slice, yet its code sits in `source/projectured/`.
   Is that the intended reading, and must the rule say so?
5. **`test_all()` and `test_package_graph()`.** `ProjecturedTest` exports these
   two and never `test_projectured()` or `test_projectured_layering()`. Is that
   a named exception the rule must state?
6. **A tier-level example registry.**
   [example/projectured/DomainExamples.jl](../../example/projectured/DomainExamples.jl)
   and [example/substrate/SubstrateExamples.jl](../../example/substrate/SubstrateExamples.jl)
   are registries of a whole tier, not of one slice. Does the rule need this
   third shape?
7. **The bench files.** `test/bench/colorbench.jl`, `fanout.jl` and
   `graphlayoutbench.jl` are the only 3 of 699 files that start with a lower
   case letter. `ProjecturedBench` is a package-level exception only. Must its
   files take the CamelCase that every other file uses?
8. **Two duplicate basenames.** `Geometry.jl` exists in `source/graph/omnetpp/`
   and `source/style/`, and `Precompile.jl` in `example/projectured/` and
   `source/executable/`. These two are not one concept in two slices. Rename one
   side of each pair? The `Geometry.jl` fix in §4.2 already settles the first.
9. **A test fixture module (§4.4).** Three test files declare six fixture
   modules, because Julia allows `module` only at the top level. Only 3 of 226
   module-eligible test files declare a module at all. Does the file-name law
   reach `test/`, and is a module that no other file imports exempt?
10. **Is `Backend` a sanctioned qualifier? — MOOT.**
    [Pdf.jl](../../source/pdf/Pdf.jl) declares `PdfBackendModule` and
    [Console.jl](../../source/console/Console.jl) declares
    `ConsoleBackendModule`. Both modules disappear when their slice becomes one
    module, so the question does not arise. Neither file needs a rename.
11. **A collision prefix — ANSWERED.** `ProjectionGestureBindingsModule` stays:
    the kernel keeps its modules. `LayoutGeometryModule` in
    `source/graph/omnetpp/` disappears when the `graph` slice becomes one
    module, so only the file rename to `LayoutGeometry.jl` survives, and that
    one is worth doing on its own because it ends a duplicate basename.
12. **`StatementScope`.** [Repl.jl:88](../../source/repl/Repl.jl#L88) declares
    `module StatementScope end` with no `Module` suffix. It is a namespace for
    dynamic bindings and is never exported, so it is not a unit of architecture
    at all. Keep it, and say in the rules that a namespace object of this kind
    is not a module in the architectural sense.
13. **The `source/projection/` folders.** The rule names `generic/` and
    `higherorder/` only. The tree also has `compound/` with two files, and
    [ReaderDefaults.jl](../../source/projection/ReaderDefaults.jl) sits directly
    in `source/projection/` and is not a projection. What should the rule say
    about a third folder and about a non-projection file in that tree?
14. **Does the projection stem table reach a multi-type file?** About 62
    `<A>To<B>.jl` files hold many small per-node sub-projections under one module
    named `<File>Module`, and none declares a single `<A>To<B>Projection` type.
    They follow the base module rule, not the stem table. Does the stem table
    apply only to a file with one projection type, and should it say so?
15. **Must every stem have its own IO map?** Four ordinary gerund stems
    (`Focusing`, `Reversing`, `TypeDispatching`, `PredicateDispatching`) declare
    no `<Stem>ProjectionIoMap`; they reuse `SimpleIoMap`, `ChildrenIoMap`, or the
    IO map of the projection they wrap. Is a dedicated IO map required when a
    projection adds no cursor mapping of its own?
16. **`WindowManaging`'s folder.** Its four names agree, but the file is
    [source/screen/WindowManaging.jl](../../source/screen/WindowManaging.jl) and
    the rule lists the stem under `higherorder/`. Is the screen slice the right
    owner, or must the file move?
17. **Is the `Operation` suffix reserved?**
    [MathDocument.jl](../../source/math/MathDocument.jl) declares
    `MathBinaryOperation` and `MathUnaryOperation` as document nodes. They are
    noun phrases and correct as documents, yet they wear the suffix the rule
    gives to the pipeline rung. Should the rule reserve the suffix, so a
    document node must read `MathBinaryOperator` or similar?
18. **85 domain converters carry no `Projection` suffix.** **UNDER DISCUSSION —
    see §13.2 for the case on each side.** This is the same question as §9.14,
    seen from the type side.
19. **The `Llm`/`Agent` event vocabulary.** 14 types under `LlmEvent` and
    `AgentEvent` do not subtype the pipeline `Event` and are not
    `<Source><Action>`: they read `LlmTextStart`, `LlmThinkingDelta`,
    `LlmToolUseStop`, `LlmTurnEnd`, `AgentToolResult`. The module docstring says
    the vocabulary is deliberately the project's own and mirrors a streaming
    turn. Is the Events rule scoped to the pipeline `Event` only?
20. **Nine scope-first `Composer…Operation` types.**
    [ConversationEditor.jl](../../source/conversation/ConversationEditor.jl)
    consistently leads with the widget, not the verb:
    `ComposerInputOperation`, `ComposerBackspaceOperation`,
    `ComposerNewlineOperation`, `ComposerInsertPartOperation`,
    `ComposerCommitChooserOperation`, `ComposerCommitSourceOperation`,
    `ComposerEvaluateOperation`, `ComposerRevertOperation`,
    `ComposerSubmitOperation`. Is `<Scope><Verb><Noun>Operation` a second
    accepted shape for an operation scoped to one sub-widget, or are all nine
    wrong?
21. **The `Pat` family — 22 types.**
    [ReferenceCase.jl](../../source/kernel/reference/ReferenceCase.jl) uses
    `Pat` for `Pattern` throughout (`PatValue`, `PatStep`, and 20 subtypes; one
    of them, `PatStepAlt`, also shortens `Alternative`). Is `Pat` accepted
    shorthand inside this one DSL file, or must it read `Pattern`?
22. **13 test fixture types with a two-letter file-scope prefix.** `Dm` for
    `DocumentMacro` in
    [DocumentMacroTest.jl](../../test/kernel/document/DocumentMacroTest.jl)
    (nine types) and `Cs` for `CellStruct` in
    [CellStructTest.jl](../../test/kernel/cell/CellStructTest.jl) (four). Are
    test-local abbreviations exempt, the way a local variable is?
23. **A documented vocabulary port from C++.**
    [source/graph/omnetpp/LayoutGeometry.jl](../../source/graph/omnetpp/LayoutGeometry.jl)
    declares `Pt`, `Rs`, `Rc`, `Ln` and `Cc`, and its docstring names the
    mapping to OMNeT++'s `src/layout/geometry.h` outright and gives the reason.
    `IBody` and `IForceProvider` in §5.4 come from the same port. This is not a
    `ccall` binding, so the third-party exemption does not literally apply. Is a
    documented, deliberate port exempt?
24. **19 AST nodes named after a source keyword.** `JuliaBreak`,
    `JuliaContinue`, `JuliaReturn`, `JuliaFor`, `JuliaIf`, `SqlAnd`, `SqlNot`,
    `SqlDistinct`, `RstStrong`, `MarkdownEmphasis` and nine more. Read as "the
    node for the X construct" they are nouns; read as English words, several are
    imperatives or adjectives. I did not file them as violations. Is the keyword
    reading accepted?
25. **Gesture patterns are functions, not types.** `KeyDownPattern` and
    `MouseDownPattern`, which the rules name as types, are functions in
    [EventPattern.jl](../../source/kernel/event/EventPattern.jl) that build an
    `EventPattern{E}`. The only real types ending in `Pattern` are
    `EventPattern` and the abstract `FieldPattern`, and neither breaks the rule.
    Should the rules move this family to the Functions section, where the real
    names live?
26. **Four document types repeat their own stem.** `BookBook`,
    `WorkbenchWorkbench`, `ConversationConversation` and `GraphGraph`, each the
    root document of its domain. No listed rule forbids it, and both halves are
    nouns, but the doubling reads oddly. Worth a decision, not a violation.
27. **460 getters read `<subject>_<property>`, not `get_<stem>`.** **ANSWERED —
    see §13.1. The rule wins: use verbs.**
28. **246 constants are lower case, not `SCREAMING_SNAKE_CASE`.** Two deliberate
    families dominate: 142 `font_*` constants in
    [Font.jl](../../source/style/Font.jl) and 99 `color_*` constants in
    [Color.jl](../../source/style/Color.jl), plus three `@enum LayoutDirection`
    values (`layout_none`, `layout_horizontal`, `layout_vertical`) and two named
    defaults (`affine_identity`, `inset_default`). This is a palette style,
    closer to a design-token list than to a numeric constant, and it is used
    consistently. Exempt the palette style in the rule, or uppercase all 246?
29. **23 exported names start with an underscore.** Eight constants (`_FONT_DIR`,
    `_DISPLAY_SCALE`, `_USER_ZOOM`, `_WALK_MAX_DEPTH` and more) and 15 functions
    (`_walk!`, `_emit_frames!`, `_find_cursor_rect`, `_syntax_to_flat` and
    more). In Julia a leading underscore says "not public", yet each of these is
    exported. Is the underscore a deliberate mark for a name that crosses files
    inside one package but is not part of the umbrella's surface, or must these
    lose the underscore or lose the `export`?
30. **`PRED_REF` in four constants.** `PRED_REF_DIRECTIVE`,
    `PRED_REF_ELEMENT_TAG`, `PRED_REF_FUNCTION_NAME` and `PRED_REF_LANGUAGE`
    shorten `reference`, but the abbreviation is the wire value itself: the
    literal text is `"pred-ref"`, `"pred:ref"` and `"pred_ref"`, which four file
    formats look for. Renaming the Julia constant alone would leave the value
    reading `pred-ref`. Is a fixed external tag name exempt, the way a Base
    generic keeps its foreign spelling, or must the four formats change too?
31. **`os_clipboard_write` has no `!`.** It writes to the operating system
    clipboard and returns a `Bool`. Its comparable neighbours `db_connect!` and
    `db_close!` do carry `!`, and both do external input and output. Decide the
    `!` question for an external side effect on its own, because it also settles
    `os_clipboard_read`.

## 10. Add a naming guard

[test/suite/tree.jl](../../test/suite/tree.jl) shows the pattern: a static check
that reads directory entries, `Project.toml` files and `include` lines, loads
nothing, and runs in under a second. Add a naming guard beside it that asserts,
for the whole repository:

1. the module name of every file is the file name plus `Module`, with the three
   stated exceptions;
2. a file that contains `@document` and is a slice's primary document file is
   named `<Slice>Document.jl`;
3. every `<Slice>Suite.jl` name matches the CamelCase of its package;
4. every test package defines `test_<slice>()` and `test_<slice>_layering()`;
5. no package root declares a module alias whose name no file declares;
6. every file declares at most one module, or its extra modules are declared
   fixtures on a short list the guard holds;
7. every exported name is defined somewhere, which catches §6.8;
8. no exported name contains a banned abbreviation. Hold the banned list in the
   guard (`val`, `fn`, `ref`, `op`, `perf`, `eval`, `ctx`, `nav`, `seg`, `def`,
   `conn`, `reg`, `cur`) and the sanctioned list beside it (`api`, `iomap`,
   `ctrl`, `alt`, `meta`, `ctor`, `expr`).

Write the guard before the renames, with the assertions that already pass turned
on, so each step of §2 has to keep it green. That is how
[test/suite/tree.jl](../../test/suite/tree.jl) was written, and the comment at
its head says why.

## 11. What a rename must not break

- A **module rename** touches only `import ..X` and `X.y` references. It changes
  no `include` line and needs no `git mv`.
- A **file rename** also rewrites the `include("…")` string in the package root
  or in the layer module, and it needs a `git mv`.
- A rename with `sed` also rewrites a file-path string. I checked: every
  `"<Name>.jl"` string in the code names a test fixture (`"root.jl"`, `"a.jl"`,
  `"Top.jl"`), and no file this plan renames appears as a string. Check again
  before each `sed`.
- The kernel seal list in [CLAUDE.md](../../CLAUDE.md) names each file by path.
  A file rename in `source/kernel/` must rewrite that entry in the same commit.

## 11.1 A design finding this work uncovered — NOT A NAMING PROBLEM

`EVALUATION_HANDLER` in
[ConversationEditor.jl:751](../../source/conversation/ConversationEditor.jl#L751)
is a module-level mutable `Ref`:

    const EVALUATION_HANDLER = Ref{Any}(nothing)
    EVALUATION_HANDLER[] = a -> EvaluateDraftTurnOperation(a)   # set in AssistantTurn.jl

One `Ref` at module level means **one handler for the whole process**. Two
editors, two assistants, or a test running beside real use all share it, and the
last writer wins. There is no way to have two different handlers at once.

The fix is to move the hook onto the thing it belongs to — a field on the
assistant or the editor, so each instance carries its own. That is a refactor
with its own before and after, and it is not a rename, so this plan only records
it. The rename of the constant does not make the problem worse.

The user raised this on 2026-09-13 when reviewing the conversation slice.

## 12. Sealed kernel files

The user gave permission on 2026-09-12 to open sealed files for this work. Only
one sealed file carries a finding:

| file | finding | seal |
| --- | --- | --- |
| [selection/SelectionDefaults.jl](../../source/kernel/selection/SelectionDefaults.jl) | `SelectionMismatch` has no `Exception` suffix (§5.1) | 🔒 |

Six more kernel files carry findings and are **not** sealed, so no permission is
needed for them: `reference/ReferenceStep.jl`, `reference/ReferenceSyntax.jl`,
`reference/ReferenceCase.jl`, `projection/GestureBindings.jl`,
`operation/Intent.jl` and `projection/ProjectionApi.jl`.

`PAR-NAMING-LAW` is part of the audit that a file passes before it is sealed, so
`SelectionMismatch` means the audit of that file missed the rule. Re-audit the
file after the fix and keep the `🔒` mark, as CLAUDE.md directs.


## 13. The three rulings

The user answered on 2026-09-12. Two are settled. The third needs my pushback,
which §13.3 gives.

### 13.1 Getters — use verbs, and never reuse a name

**Decision: every exported function takes a verb, and a rename must never
collapse two unrelated concepts onto one name.**

I recount the class honestly. My first two counts, 452 and 460, were both too
high: the verb list behind them missed many verbs, so names like
`unwrap_selection`, `adjust_user_zoom!` and `reconcile_children` were counted as
noun-first when they are not. With a complete verb list the class is **383
exported functions that do not start with a verb**.

The class is not one kind. Reading the definitions shows at least six:

| kind | fix |
| --- | --- |
| getter | `get_<stem>` |
| predicate returning `Bool` | `is_<condition>` or `has_<possession>` |
| factory | `make_<thing>` |
| derived copy | `with_<stem>` |
| mutator | `<verb>_<noun>!` |
| a constant or an enum value, not a function | no change; it belongs to §9.28 |

So `get_` is not the answer for all 383. Each name needs its definition read.

**The user's rule and what it costs.** The rules say the subject travels by
dispatch, which would turn `pane_drop_zone` into `get_drop_zone`. The user
overruled that: never reuse a name and let dispatch separate two unrelated
concepts. So the subject word stays unless the two names are provably one
concept. I tested the conservative form — keep the whole name, add the verb —
across the class: **zero collisions**. Only one name in the whole class has a
proven twin, `body_mass` beside the `set_mass!` that already exists, so only
that one drops its subject and becomes `get_mass`.

The complete list of 383, one row per name, is §14.

### 13.1.1 How to choose the verb

The user decided these on 2026-09-12. They settle the 62 rows where two
independent passes disagreed, and they apply to every future name.

1. **The verb follows the nature of the work.**
   - `find_` when it is a search that may return nothing.
   - `get_` when the value sits at a known place, with at most a trivial
     computation applied before it is returned.
   - `compute_` when a non-trivial computation is involved.
   - Another verb when it fits better: `format_` for text, `render_` for an
     output representation, `build_` for assembly, `collect_` for gathering,
     `convert_` for a conversion, `measure_` for measuring.
2. **`make_` means the intention is to create a new something.** A function does
   not take `make_` merely because it returns a fresh `NamedTuple` or `Vector`.
   The question is what the caller wants: a new object, or a value derived from
   state that already exists.
3. **A qualifier keeps subject-first order**, because it reads more like
   English: `get_base_plane_length`, not `get_length_base_plane`. This overrides
   the "qualifiers are suffixes" line of the rules for this shape, and
   [naming-rules.md](../../documentation/rule/naming-rules.md) needs the
   correction.
4. **A trailing `of` or `for` is dropped.** `chart_view_of` becomes
   `get_chart_view`; `dsn_for` becomes `get_dsn`.
5. **An external side effect takes `!`.** `os_clipboard_write` becomes
   `write_os_clipboard!`. A pure read of external state takes none, so
   `os_clipboard_read` becomes `read_os_clipboard`. This closes §9.31.
6. **`julia_main` is exempt** and keeps its name. It is the entry point
   PackageCompiler requires, and a rename breaks the compiled binary. Record the
   exemption in the rules.

### 13.2 The `Projection` suffix — the third option, and `<Stem>IoMap`

**Decision: keep the 85 `<A>To<B>` converters bare, write the exception into the
rule, and drop `Projection` from the IO map name.**

Two changes to [naming-rules.md](../../documentation/rule/naming-rules.md).

**First, the projections table loses `Projection` from the IO map row:**

| artifact | was | is |
| --- | --- | --- |
| file | `<Stem>.jl` | `<Stem>.jl` |
| type | `<Stem>Projection` | `<Stem>Projection` |
| module | `<Stem>ProjectionModule` | `<Stem>ProjectionModule` |
| iomap | `<Stem>ProjectionIoMap` | **`<Stem>IoMap`** |

**Second, a sentence that states the exception**, to be added under
"Projections":

> A projection named `<A>To<B>` takes no suffix. The `To` already says the name
> is a projection, and the chain that these names live in reads better without
> the word repeated: `ChainingProjection([JsonToSyntax(), SyntaxToText(),
> TextToGraphics()])`. Every other projection takes `<Stem>Projection`.

**The 23 IO map renames.** 189 references. No target name is taken, which I
checked.

| old | new | refs |
| --- | --- | --- |
| `CopyingProjectionIoMap` | `CopyingIoMap` | 21 |
| `ChainingProjectionIoMap` | `ChainingIoMap` | 11 |
| `DraggingProjectionIoMap` | `DraggingIoMap` | 10 |
| `CommandPaletteProjectionIoMap` | `CommandPaletteIoMap` | 9 |
| `VersioningToAnyProjectionIoMap` | `VersioningToAnyIoMap` | 9 |
| `WindowManagingProjectionIoMap` | `WindowManagingIoMap` | 9 |
| `ClipboardSliceToAnyProjectionIoMap` | `ClipboardSliceToAnyIoMap` | 8 |
| `HoverProbeProjectionIoMap` | `HoverProbeIoMap` | 8 |
| `NestingProjectionIoMap` | `NestingIoMap` | 8 |
| `ClipboardCollectionToAnyProjectionIoMap` | `ClipboardCollectionToAnyIoMap` | 7 |
| `FilteringProjectionIoMap` | `FilteringIoMap` | 7 |
| `GestureHelpProjectionIoMap` | `GestureHelpIoMap` | 7 |
| `GestureLogOverlayProjectionIoMap` | `GestureLogOverlayIoMap` | 7 |
| `GestureLogRecordingProjectionIoMap` | `GestureLogRecordingIoMap` | 7 |
| `ProjectionConfiguringProjectionIoMap` | `ProjectionConfiguringIoMap` | 7 |
| `ReferenceDispatchingProjectionIoMap` | `ReferenceDispatchingIoMap` | 7 |
| `SortingProjectionIoMap` | `SortingIoMap` | 7 |
| `SwitchingProjectionIoMap` | `SwitchingIoMap` | 7 |
| `TooltipDecoratorProjectionIoMap` | `TooltipDecoratorIoMap` | 7 |
| `WidgetHoverTrackingProjectionIoMap` | `WidgetHoverTrackingIoMap` | 7 |
| `WidgetPopupResolverProjectionIoMap` | `WidgetPopupResolverIoMap` | 7 |
| `WindowInputUnwrappingProjectionIoMap` | `WindowInputUnwrappingIoMap` | 7 |
| `SearchingProjectionIoMap` | `SearchingIoMap` | 5 |

The two decorator rows of §7.1 still hold. `CommandPaletteProjection` becomes
`CommandPaletteDecoratorProjection` and its IO map becomes
`CommandPaletteDecoratorIoMap`, because the file and the module already say
`Decorator` and the sibling `TooltipDecoratorProjection` keeps the word.

**What this decision cancels.** §9.18 and §9.14 are closed. The 85 converters
keep their names, and no rename follows from them.

### 13.3 One module per slice — the pushback the user asked for

The user asks: why so many modules? Why not one `JsonModule` for the whole
slice, since a document, a projection and a parser will not clash inside one
slice?

**The premise is right, and it is not the reason for the boundary.** Clashes are
not what the per-file module buys. Two other things are.

**The first is real and the measurement is smaller than I expected.** The
layering guard [CheckLayering.jl](../../test/kernel/layering/CheckLayering.jl)
reads the real `import ..XModule` headers and asserts that the include order is
a valid topological order over them. Collapse a slice and the edges inside it
stop existing, so the guard has nothing to sort there. But I counted them:

| edge kind | count |
| --- | --- |
| `import ..XModule` lines outside the kernel | 1880 |
| of those, **cross-slice** — unaffected, they just target `JsonModule` instead | **1626** |
| of those, **intra-slice** — these disappear | **254** |

**20 non-kernel slices already have zero intra-slice edges.** For those the
collapse loses nothing whatsoever. The 254 concentrate in a few: `graph` 39,
`text` 25, `process` 15, `syntax` 13, `pane` 12.

**The second cost is the one I would not give up lightly.** Today a name can be
exported from `JsonParserModule` and imported only by `JsonFileModule`, so it is
shared between two files and still invisible outside the slice.
`PAR-MODULE-BOUNDARY-IS-API` says the module boundary is the API boundary, and
that is the boundary doing the work. Collapse the slice and there is no place
left to put a name that two files share but no consumer should see. I counted
them: **346 exported symbols are used only inside their own slice.** All 346
become public, with no way to mark them internal.

**Where the user is right, and it is most of the way.**

- The kernel already does exactly what the user proposes. A layer is
  `DocumentModule.jl` owning `DocumentInterface.jl`, `DocumentCopy.jl` and the
  rest as fragments with no module of their own, and the guard errors if a
  fragment tries a relative import. So "one module, many fragment files" is not
  a new idea here; it is the kernel's own pattern, and 450 files across the
  repository are already fragments.
- The ceremony is real. `source/projection/` is 19 modules for 19 files, `text`
  14 for 14, `graph` 17 for 16.
- It deletes §9.1 outright. `JsonModule` in `JsonDocument.jl` becomes correct
  rather than wrong, and the 717 references stay as they are.

**My recommendation: do not decide it inside this plan.** It is an architecture
change, not a naming fix — it moves an API boundary, it drops 254 checked edges
and it makes 346 names public. It deserves its own plan, its own before and
after, and its own guard change. If it goes ahead, §4.1 and §9.1 vanish with it,
so **defer §4.1 until this is settled** and do the rest of the plan meanwhile.

If the user wants it now, the cheapest honest version is: collapse only the 20
slices that already have zero intra-slice edges. It costs no checked edge, it
proves the pattern, and it leaves `graph`, `text`, `syntax`, `process` and
`pane` — where the edges actually are — for a later look.

## 14. Every rename

The user asked to see every rename before any of it happens. This section lists
them. Nothing in it is applied yet.

Status: the 383 rows of §13.1 are still being named, one definition at a time.
Every other table below is complete.

### 14.1 Module renames — CANCELLED

The 30 module renames of §4.1 do not happen. A module is one unit of
architecture, so `JsonModule` in `JsonDocument.jl` is the correct name. See
[one-module-per-slice.md](one-module-per-slice.md).

### 14.2 Module renames that do not wait

These are independent of §13.3.

| file | old module | new module | confidence |
| --- | --- | --- | --- |
| [source/inspector/ReferenceInspector.jl](../../source/inspector/ReferenceInspector.jl) | `ReferenceInspectorDocumentModule` | `ReferenceInspectorModule` | likely |
| [source/database/DatabaseInstance.jl](../../source/database/DatabaseInstance.jl) | `DatabaseInstanceDocumentModule` | `DatabaseInstanceModule` | likely |
| [source/syntax/InsertionToSyntax.jl](../../source/syntax/InsertionToSyntax.jl) | `DocumentInsertionToSyntaxModule` | `InsertionToSyntaxModule` | likely |
| [source/database/DatabaseAdapters.jl](../../source/database/DatabaseAdapters.jl) | `DatabaseModule` | `DatabaseAdaptersModule` | likely |
| [source/kernel/projection/GestureBindings.jl](../../source/kernel/projection/GestureBindings.jl) | `ProjectionGestureBindingsModule` | `GestureBindingsModule` | unsure, see §9.11 |

### 14.3 File renames

| old path | new path | why |
| --- | --- | --- |
| [test/dbcatalog/DbCatalogSuite.jl](../../test/dbcatalog/DbCatalogSuite.jl) | `test/dbcatalog/DbCatalogSuite.jl` | §3.2 |
| [test/filesystem/FileSystemSuite.jl](../../test/filesystem/FileSystemSuite.jl) | `test/filesystem/FileSystemSuite.jl` | §3.2 |
| [test/sequencechart/SequenceChartSuite.jl](../../test/sequencechart/SequenceChartSuite.jl) | `test/sequencechart/SequenceChartSuite.jl` | §3.2 |
| [source/graph/omnetpp/LayoutGeometry.jl](../../source/graph/omnetpp/LayoutGeometry.jl) | `source/graph/omnetpp/LayoutGeometry.jl` | §4.2, also ends a duplicate basename |
| [source/text/TextLineNumbering.jl](../../source/text/TextLineNumbering.jl) | `source/text/TextLineNumbering.jl` | §4.2 |
| [source/gesturelog/GestureLogRecording.jl](../../source/gesturelog/GestureLogRecording.jl) | `source/gesturelog/GestureLogRecording.jl` | §7.1, the other three names already say `Recording` |
| [source/dragging/Dragging.jl](../../source/dragging/Dragging.jl) | `source/dragging/Dragging.jl` | §7.1, a stem file never bakes in `Projection` |
| [source/projection/generic/Copying.jl](../../source/projection/generic/Copying.jl) | `source/projection/generic/Copying.jl` | §7.2 |
| [source/projection/generic/Filtering.jl](../../source/projection/generic/Filtering.jl) | `source/projection/generic/Filtering.jl` | §7.2 |
| [source/projection/generic/Searching.jl](../../source/projection/generic/Searching.jl) | `source/projection/generic/Searching.jl` | §7.2 |
| [source/projection/generic/Sorting.jl](../../source/projection/generic/Sorting.jl) | `source/projection/generic/Sorting.jl` | §7.2 |

Each row also rewrites the `include("…")` line that names the file.

### 14.4 File splits

| file | becomes | why |
| --- | --- | --- |
| `source/odbc/Odbc.jl`, now split into four files | `OdbcAdapter.jl`, `ConnectionPool.jl`, `SqlToCellTable.jl`, `DatabaseInstanceToDbCatalog.jl` | §4.4, four modules in one file. Every module name is already right. |
| [source/dragging/Dragging.jl](../../source/dragging/Dragging.jl) | `Dragging.jl` plus `DraggingWrapper.jl` | §4.4 |
| [source/clipboard/ClipboardToAny.jl](../../source/clipboard/ClipboardToAny.jl) | `ClipboardSliceToAny.jl`, `ClipboardCollectionToAny.jl` | **moved to [one-module-per-slice.md](one-module-per-slice.md) §4.1.** The split needs the slice to be one module first. |

### 14.5 Module aliases to delete

29 alias lines in the package roots, six distinct names. Replace each use with
the real module name.

| alias | real module | lines |
| --- | --- | --- |
| `DocumentApiModule` | `DocumentModule` | 10 |
| `OperationApiModule` | `OperationModule` | 7 |
| `ReferenceCaseModule` | `ReferenceModule` | 4 |
| `ReferenceBuilderModule` | `ReferenceModule` | 4 |
| `OperationRerootingModule` | `OperationModule` | 3 |
| `BackendApiModule` | `BackendModule` | 1 |

Also delete three rows from the table at
[PackageGraphTest.jl:233](../../test/projectured/PackageGraphTest.jl#L233) that
name aliases no file uses any more: `SelectionApiModule`, `ReferenceApiModule`
and `ProjectionReferenceStepApiModule`.

### 14.6 Type renames

| old | new | why |
| --- | --- | --- |
| `ProcessStopped` | `ProcessStoppedException` | §5.1 |
| `ReferenceTypeMismatch` | `ReferenceTypeMismatchException` | §5.1 |
| `SelectionMismatch` | `SelectionMismatchException` | §5.1, sealed file |
| `DatabaseUpdateOperation` | `UpdateDatabaseCellOperation` | §5.2 |
| `DatabaseInsertOperation` | `InsertDatabaseRowOperation` | §5.2 |
| `NewTabRequestOperation` | `OpenTabOperation` | §5.2 and §7.3 |
| `CloseTabRequestOperation` | `CloseTabOperation` | §7.3 |
| `ToyPathOp` | `ToyPathOperation` | §5.2 |
| `FrameDrainOperation` | `DrainFrameOperation` | §5.2 |
| `FrameDrainSwapOperation` | `DrainFrameSwapOperation` | §5.2 |
| `InboxProbeOperation` | `ProbeInboxOperation` | §5.2 |
| `ToggleClipboardSliceDisplayOperation` | `ToggleClipboardSliceOperation` | §5.3 |
| `ToggleClipboardCollectionDisplayOperation` | `ToggleClipboardCollectionOperation` | §5.3 |
| `IBody` | `AbstractBody` | §5.4 |
| `IForceProvider` | `AbstractForceProvider` | §5.4 |
| `WorkspaceWorkspaceProjection` | `WorkspaceToFileSystemDirectory` | §7.1 |
| `CommandPaletteProjection` | `CommandPaletteDecoratorProjection` | §7.1 |
| `GestureHelpProjection` | `GestureHelpDecoratorProjection` | §7.1 |
| `RefStep` | `ReferenceSyntaxStep` | §5.5 |
| `RefField` | `ReferenceSyntaxField` | §5.5 |
| `RefFieldExpr` | `ReferenceSyntaxFieldExpression` | §5.5 |
| `RefIndex` | `ReferenceSyntaxIndex` | §5.5 |
| `RefPosition` | `ReferenceSyntaxPosition` | §5.5 |
| `RefRange` | `ReferenceSyntaxRange` | §5.5 |
| `RefType` | `ReferenceSyntaxType` | §5.5 |
| `RefSplice` | `ReferenceSyntaxSplice` | §5.5 |
| `RefTailBind` | `ReferenceSyntaxTailBind` | §5.5 |
| `RefArgValue` | `ReferenceSyntaxArgumentValue` | §5.5 |
| `RefArgSubPath` | `ReferenceSyntaxArgumentSubPath` | §5.5 |
| `RefExtension` | `ReferenceSyntaxExtension` | §5.5 |
| `JuliaBinaryOp` | `JuliaBinaryOperation` | §5.5 |
| `JuliaUnaryOp` | `JuliaUnaryOperation` | §5.5 |
| `JuliaBinaryOpToSyntaxNode` | `JuliaBinaryOperationToSyntaxNode` | §5.5 |
| `JuliaUnaryOpToSyntaxNode` | `JuliaUnaryOperationToSyntaxNode` | §5.5 |
| `JuliaModuleDef` | `JuliaModuleDefinition` | §5.5 |
| `JuliaModuleDefToSyntaxNode` | `JuliaModuleDefinitionToSyntaxNode` | §5.5 |
| `PageCtx` | `PageContext` | §5.5 |
| `FontReg` | `FontRegistration` | §5.5 |
| `WebConn` | `WebConnection` | §5.5 |
| `SelSeg` | `SelectionSegment` | §5.5 |
| `WrapSeg` | `WrapSegment` | §5.5 |
| `HighlightSeg` | `HighlightSegment` | §5.5 |
| `SegCoord` | `SegmentCoordinate` | §5.5 |
| `RCV` | `ReactiveCellVector` | §5.5 |
| `EvalChild` | `EvaluationChild` | §5.5 |
| `EvalDoc` | `EvaluationDocument` | §5.5 |
| `EvalLeaf` | `EvaluationLeaf` | §5.5 |
| `EvalBranch` | `EvaluationBranch` | §5.5 |
| `_Cur` (json and xml) | `_Cursor` | §5.5 |
| `IC` (alias) | delete it, write `ImmutableCell` | §5.4 |

### 14.7 IO map renames

The 23 rows of §13.2, unchanged.

### 14.8 Function and constant renames already filed

The 64 rows of §6.1 to §6.6, unchanged. They are separate from the 383 of §14.9.

### 14.9 The functions that do not start with a verb

**374 real names.** Two independent passes named every one of them, each reading
the definition rather than the name. They agree on 287, differ on 62, and the
rest need no change. No two rows propose the same name, which is what the rule
of §13.1 asks for.

| status | count |
| --- | --- |
| agreed by both passes — apply it | 287 |
| contested — both readings shown, see §14.10 of the appendix | 62 |
| no change — verb-first already, a fixture, or a `const` | 16 |
| one pass only — apply the name shown | 5 |
| one pass breaks a stated rule — the compliant name is shown | 4 |

The 62 contested rows are not 62 questions. Six policy questions settle almost
all of them, and the appendix states each one.

Nine of the 383 candidates are not names at all, and I removed them:

- `the` — my export reader joined a comment line into a wrapped `export`
  statement at [ReferenceModule.jl:84](../../source/kernel/reference/ReferenceModule.jl#L84)
  and read an English word as an identifier.
- eight `fsm_*` names — they sit inside the triple-quoted string
  `_PROBE_RUNTIME_SOURCE` at
  [FsmToJuliaCodeTest.jl:199](../../test/fsm/projection/FsmToJuliaCodeTest.jl#L199),
  which the test feeds to `Base.include_string`. They are the call targets that
  [FsmToJuliaCode.jl](../../source/fsm/FsmToJuliaCode.jl) emits, not exports of
  this repository.

Each of the 374 was classified by reading its definition, not its name:

| kind | count | shape |
| --- | --- | --- |
| getter | 213 | `get_<stem>` |
| factory | 57 | `make_<thing>` |
| other verb | 53 | the right verb, usually already in the name but at the end |
| mutator | 15 | `<verb>_<noun>!` |
| predicate | 12 | `is_<condition>` |
| derived copy | 1 | `with_<stem>` |
| false positive — already verb-first | 7 | no change |
| already filed in §6 | 7 | no change |
| test fixture | 6 | no change |
| not a function | 1 | no change; `affine_identity` is a `const` |

**Three rows need a decision rather than a rename.**

1. `julia_main` in [Executable.jl](../../source/executable/Executable.jl) is the
   entry-point symbol PackageCompiler requires. A rename breaks the compiled
   binary. Leave it, and say so in the rules.
2. `bound`, `collection`, `sections` and `tokens` in
   [ProjectionTemplate.jl](../../source/kernel/projection/ProjectionTemplate.jl)
   may be DSL words of `@projection_template`, like `when` and `prefix` in
   `@reference_case`, which the rules exempt. If they are, they keep their
   names.
3. `insertrow` and `deleterow` in
   [CollectionDocument.jl](../../source/collection/CollectionDocument.jl) turned
   out to mutate, so they need a `!`. The proposal that came back was
   `insertrow!` and `deleterow!`, still glued. The targets must be `insert_row!`
   and `delete_row!`, which is the rule's own example and matches §6.2.

**The qualifier-prefix shape is settled.** `pure_print`, `pure_print_child` and
`pure_print_document` become `print_pure`, `print_child_pure` and
`print_document_pure`, so the qualifier sits at the end beside the sibling
`print_child` and `print_document`.

The full table, grouped by file, is
[naming-rule-renames.md](naming-rule-renames.md).
