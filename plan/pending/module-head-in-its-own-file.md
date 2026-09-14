# A module is declared in the file that names it

## The problem

A slice is one unit of architecture and it declares one module. The module head
is the table of contents of that unit: the docstring, the header, the ordered
includes, and the load-time registration. Today 59 of the 73 modules hide that
head inside a file that also holds code. Measured again on 2026-09-14, after
the projection layer became one module: seven projection modules became one, and
that one keeps its head in `ProjectionModule.jl`.

A reader who opens the `style` slice must open `Color.jl` to find the module. A
reader who opens the `json` slice had to read past 110 lines of document types
to reach the includes. Ten slices name the module file after one fragment:
`Color.jl`, `Workspace.jl`, `Evaluator.jl`, `BoundedSync.jl`, `DocumentCore.jl`,
`NaturalFormat.jl`, `GestureMap.jl`, `PointReferenceStep.jl`,
`ReferenceInspector.jl`, `BinarySerialization.jl` and `generic/Identity.jl`.

Fourteen kernel layers already have the right shape. `CellModule.jl`,
`AgentModule.jl` and twelve more hold a head and nothing else. They are the
model.

## The law

**A module is declared in `<Module>.jl`.** `JsonModule` lives in
`JsonModule.jl`. `StyleModule` lives in `StyleModule.jl`. There is no exception.

**`<Module>.jl` holds the head and nothing else, when the module has more than
one file.** The head is the docstring, the `module` line, the `using` /
`import` / `export` block, the ordered includes and `__init__`.

**A module that is one small file keeps its code.** Four kernel modules declare
only open generics. A head file above them would include a file with two
declarations in it. Rename those; do not split them.

## The shape

The json slice is done. It is the pattern for every other slice.

Before, `source/json/JsonDocument.jl`, 179 lines, four jobs.

After, five files:

```
source/json/
  JsonModule.jl     66 lines   the head
  JsonDocument.jl  115 lines   the document types
  JsonParser.jl                the parser
  JsonToSyntax.jl              the projection
  JsonFile.jl                  the .json file wrapper
```

`JsonModule.jl`:

```julia
"""
    JsonModule
…
"""
module JsonModule

export entries
…                                  # the header, unchanged
using ..DomainModule

include("JsonDocument.jl")
include("JsonParser.jl")
include("JsonToSyntax.jl")
include("JsonFile.jl")

# What this slice registers when it loads: …
function __init__()
    …
end

end # module
```

`JsonDocument.jl`:

```julia
# Fragment of `JsonModule` — the JSON document types.
#
# `@domain Json` declares the abstract `JsonDocument` type. Every type below
# subtypes it.

@domain Json
```

[package/ProjecturedJson/src/ProjecturedJson.jl](../../package/ProjecturedJson/src/ProjecturedJson.jl)
changes one line:

```diff
-include("../../../source/json/JsonDocument.jl")
+include("../../../source/json/JsonModule.jl")
```

## What the tree says about the move

I parsed all 79 module files before I wrote this plan. Three facts make the move
mechanical.

1. **No module file puts a header line after its first code line.** Every
   `using`, `import` and `export` is contiguous at the top. The cut is one
   line number.
2. **The includes sit in one of four places.** 41 files put the code first and
   the includes after it. 19 files have no include at all. 4 files put the code
   first, then the includes, then `__init__`. 1 file puts the includes first and
   one `const` after them.
3. **A module declares one `__init__` at most, and it always sits in the module
   file.** It moves with the head.

Fact 2 gives the rule for the include order. The old file becomes a fragment,
and its include takes the place its code held. Code before the includes means
the fragment goes first. Code after them means the fragment goes last.

## The header the head file carries

The json trial settled the shape of the header. Every head file takes it.

```julia
module JsonModule

using ..CellModule
using ..CollectionModule
…                                  # every using, sorted by module name
using ..TextModule

# Imported to extend: this module adds a method to each of these.
import ..FileFormatModule: make_document_seed
import ..SerializationModule: emit_text, populate_file!

export parse_json, parse_json_file
export JsonToSyntax, JsonInsertionToSyntaxLeaf
```

Three blocks, in this order: what the module uses, what it extends, what it
offers. The usings are sorted. The imports carry the comment that says why they
are imports and not usings, which is what `PAR-QUALIFIED-EXTENSION` demands.

**A module exports only what no macro exports for it.** Three macros emit an
export, and no others:

| macro | exports | file |
| --- | --- | --- |
| `@document struct T` | `T` and its four spelling aliases | [DocumentMacro.jl:292](../../source/kernel/document/DocumentMacro.jl#L292) |
| `@domain X` | `XDocument`, and `XNothing` / `XInsertion` through `@document` | [Domain.jl:575](../../source/domain/Domain.jl#L575) |
| `@projection struct T` | `T` | [Projection.jl](../../source/kernel/projection/Projection.jl) |

`@projection` did not export until this campaign. It does now, because a
projection type is the public name of the rule it holds, exactly as a document
type is. The change made 17 projection types public that no module had
exported: 15 in `WidgetToGraphics.jl` and 2 in `RstToSyntax.jl`. No name
collides — all 312 projection types in the tree carry a distinct name, and
`test_export_collisions()` proves it over the whole loaded stack.

So an export line keeps only a plain function and a plain type. **286 names on
22 export lines are now duplicates.** Delete them as each batch reaches its
file:

| file | names to delete |
| --- | ---: |
| `julia/JuliaDocument.jl` | 57 |
| `rst/RstDocument.jl` | 52 |
| `sql/SqlDocument.jl` | 27 |
| `widget/WidgetDocument.jl` | 26 |
| `markdown/MarkdownDocument.jl` | 21 |
| `math/MathDocument.jl` | 21 |
| `process/ProcessDocument.jl` | 15 |
| `syntax/SyntaxDocument.jl` | 14 |
| `fsm/FsmDocument.jl` | 9 |
| `text/TextSpanReferenceStep.jl` | 7 |
| `yaml/YamlDocument.jl` | 7 |
| `book/BookDocument.jl` | 6 |
| `xml/XmlDocument.jl` | 5 |
| `dbcatalog/DbCatalogDocument.jl` | 5 |
| `formula/FormulaDocument.jl` | 4 |
| `gesturehelp/GestureMap.jl`, `fileformat/NaturalFormat.jl`, `filesystem/FileSystemDocument.jl` | 2 each |
| `projection/generic/Identity.jl`, `inspector/ReferenceInspector.jl`, `gesturelog/GestureLogDocument.jl`, `layout/LayoutDocument.jl` | 1 each |

**Delete only a name that a macro really declares.** The json slice exported
`JsonToSyntax` and `JsonInsertionToSyntaxLeaf` on the same line as nine
`@projection struct` names. Both are plain functions that build a projection,
not projection types, so both keep their export. A name that ends in
`ToSyntaxLeaf` is not proof of anything.

**Count the export list before and after.** `length(names(M))` on the loaded
module must not move, unless a name was dead. The count caught
`JsonInsertionToSyntaxLeaf` when the whole line went out at once.

**A dead export is silent.** The json slice exported `entries`, a field name of
`JsonObject`. No binding of that name ever existed. Julia accepts an export of
an undefined name without a word, so the line was inert from the day it was
written. Look for one in every header.

## The recipe

Do one batch at a time. One commit per batch.

1. Read the module file. Find four line ranges: the docstring and `module` line,
   the header, the code, and `__init__`.
2. Write `<dir>/<Module>.jl`. It holds the docstring, the `module` line, the
   header, the includes with the fragment in its place, `__init__` and
   `end # module`.
3. Rewrite the old file. Remove the head, the includes, `__init__` and the
   closing `end`. Add a four-line comment that names the module and says what
   the fragment holds.
4. Change the one include that reaches the module. For a slice it is
   `package/Projectured<Name>/src/Projectured<Name>.jl`. For a kernel layer it
   is `source/kernel/<layer>/<Layer>Layer.jl`.
5. Sort the usings. Put the imports and the exports in blocks of their own.
   Put the extension comment above the imports.
6. Delete every export name that `@document`, `@domain` or `@projection`
   already emits. Check `length(names(M))` before and after.
7. Run the layering guard and the narrowest suite that covers the slice:
   `test_<slice>_layering()` and `test_<slice>()`.
8. Mark the item done in this plan and commit.

Write `workspace/bin/split-module-head.py` first. It does steps 1 to 4 for one
file. Sixty-five files by hand is sixty-five chances to drop a line.

## The inventory

The `code` column is the number of code lines that stay in the old file.

### Batch 1 — the trial (done)

- [x] `json` — `JsonDocument.jl` → `JsonModule.jl`, code 58. 7/7 layering,
  170/170 suite. Commit `96cd3373`.
- [x] The json header: sorted usings, three blocks, the extension comment.
  Commit `99019cbb`.
- [x] The json exports: delete what `@document` and `@domain` already export,
  and the dead `export entries`. Commit `b933fdf5`.
- [x] `@projection` exports the type it declares. `test_export_collisions()`
  passes over the whole stack.

### Batch 2 — small slices (done)

- [x] `collection` — `CollectionDocument.jl`, code 1. The fragment goes **last**.
- [x] `inspector` — `ReferenceInspector.jl`, code 3
- [x] `dragging` — `DraggingDocument.jl`, code 4
- [x] `tooltip` — `TooltipDocument.jl`, code 5
- [x] `workbench` — `Workspace.jl`, code 6
- [x] `chart` — `ChartSampleReferenceStep.jl`, code 16
- [x] `domain` — `DocumentCore.jl`, code 17
- [x] `filesystem` — `FileSystemDocument.jl`, code 17
- [x] `component` — `ComponentDocument.jl`, code 18. One file today.
- [x] `dbcatalog` — `DbCatalogDocument.jl`, code 22
- [x] `graphics` — `PointReferenceStep.jl`, code 23
- [x] `gesturehelp` — `GestureMap.jl`, code 23
- [x] `fileformat` — `NaturalFormat.jl`, code 25
- [x] `book` — `BookDocument.jl`, code 25


**What batch 2 measured.** `test_substrate()` 60167 / 4 / 2 / 1 / 60174 and
`test_json()` 170 / 170, both identical to the baseline. The stack loads with no
warning, the naming guard is clean, `test_export_collisions()` passes, and every
touched file parses.

**Two bugs in the tool, both caught before they reached a suite.**

The first cut every trailing `end`. The tool took the code region as the first
`code` line to the last `code` line, and an `end` that closes a struct or a
function is not a `code` line — it is an `end` line. Four files failed to parse.
The region now runs to whatever comes next at the top level: an include,
`__init__`, or the module's own closing `end`, which is the last one in the file.

The second left a duplicate `using`. Two modules named `TextModule` twice,
scattered through a header that no one had sorted; sorting brought the copies
together without removing them. The tool now drops an exact duplicate. Four more
files in the tree carry the same duplication and will be fixed as their batch
reaches them: `SyntaxDocument.jl`, `NaturalNotation.jl`,
`GestureLogDocument.jl`, `Console.jl`.

**Parse every touched file before running a suite.** `Meta.parseall` over the
files the batch changed costs a second and reports a truncation that a load
would report as something else.

### Batch 3 — medium slices (done)

- [x] `conversation` — `Evaluator.jl`, code 29
- [x] `serialization` — `BinarySerialization.jl`, code 37
- [x] `database` — `DatabaseAdapters.jl`, code 43
- [x] `focus` — `Focus.jl`, code 46. One file today.
- [x] `yaml` — `YamlDocument.jl`, code 46
- [x] `reflection` — `BoundedSync.jl`, code 50
- [x] `xml` — `XmlDocument.jl`, code 55
- [x] `versioning` — `VersioningDocument.jl`, code 64
- [x] `pane` — `PaneDocument.jl`, code 67
- [x] `screen` — `ScreenDocument.jl`, code 67
- [x] `assistant` — `AssistantDocument.jl`, code 70
- [x] `markdown` — `MarkdownDocument.jl`, code 71
- [x] `gesturelog` — `GestureLogDocument.jl`, code 77
- [x] `primitive` — `PrimitiveDocument.jl`, code 77


**What batch 3 measured.** `test_substrate()` 60167 / 4 / 2 / 1 / 60174,
`test_json()` 170 / 170, `test_xml()` 78 / 78, `test_yaml()` 47 / 2 broken, and
`test_markdown()` 40 / 3 / 2 / 45. Every one matches the baseline. The stack
loads with no warning, the naming guard is clean,
`test_export_collisions()` passes, and every touched file parses.

**The embed suites fail on `main` too.** `MarkdownEmbedTest.jl` reports 3 fails
and 2 errors, and `RstEmbedTest.jl` the same five, at the same line numbers, on
a clean checkout. Measure a domain's baseline before reading its failures as
yours.

### Batch 4 — large slices (done)

- [x] `process` — `ProcessDocument.jl`, code 83
- [x] `clipboard` — `Clipboard.jl`, code 83
- [x] `fsm` — `FsmDocument.jl`, code 94
- [x] `natural` — `NaturalNotation.jl`, code 103
- [x] `odbc` — `OdbcAdapter.jl`, code 136
- [x] `console` — `Console.jl`, code 143. One file today.
- [x] `math` — `MathDocument.jl`, code 183
- [x] `julia` — `JuliaDocument.jl`, code 190
- [x] `sql` — `SqlDocument.jl`, code 192
- [x] `formula` — `FormulaDocument.jl`, code 193
- [x] `rst` — `RstDocument.jl`, code 217


**What batch 4 measured.** `test_substrate()` 60167 / 4 / 2 / 1 / 60174 and
`test_rst()` 79 / 3 / 2 / 84, both identical to the baseline. `test_fsm()`
154 / 154, `test_sql()` 354 / 354, `test_julia()` 59 / 59, `test_math()` 79 / 79.
The stack loads with no warning, the naming guard is clean,
`test_export_collisions()` passes, and every touched file parses.

`ConsoleBackendModule` now lives in `ConsoleBackendModule.jl`, so it no longer
needs its entry in `_PENDING_SLICE_MODULES`. `PdfBackendModule` is the last one
in that set, and batch 5 settles it.

### Batch 5 — the giants (done)

- [x] `syntax` — `SyntaxDocument.jl`, code 270
- [x] `sequencechart` — `SequenceChartGeometry.jl`, code 300
- [x] `layout` — `LayoutDocument.jl`, code 360
- [x] `plot` — `PlotGeometry.jl`, code 366
- [x] `pdf` — `Pdf.jl`, code 506. One file today.
- [x] `widget` — `WidgetDocument.jl`, code 1106
- [x] `style` — `Color.jl`, code 1110


**What batch 5 measured.** `test_substrate()` 60167 / 4 / 2 / 1 / 60174,
`test_workbench()` 105 / 3 / 2 / 110, both identical to the baseline.
`test_json()` 170 / 170, `test_sequencechart()` 270 / 270. The stack loads with
no warning, `test_export_collisions()` passes, and every touched file parses.

**The first piece of the prize.** `_PENDING_SLICE_MODULES` is gone. It parked
`ConsoleBackendModule` and `PdfBackendModule`, which now live in files that name
them. Removing the same exception on `main` makes the guard report both, so it
was load-bearing until this batch.

**The largest head moved out from under 2381 lines** in `WidgetDocument.jl`.
`Color.jl` keeps 1216 lines, of which about 1076 are `const color_… = _color(…)`
— a lookup table, not logic.

### Batch 6 — the three that rewrite include paths

- [ ] `text` — `TextSpanReferenceStep.jl`, code 9, 13 includes
- [ ] `graph` — `GraphDocument.jl`, code 22, 15 includes, 9 of them in
  `omnetpp/`
- [ ] `projection` — `generic/Identity.jl`, code 12, 18 includes. The head moves
  up one folder to `source/projection/ProjectionAlgebraModule.jl`, so every
  include path changes: `"Reversing.jl"` becomes `"generic/Reversing.jl"` and
  `"../higherorder/Chaining.jl"` becomes `"higherorder/Chaining.jl"`.

### Batch 7 — the kernel, rename only

These four declare open generics and nothing else. `git mv` the file. Change
the include in the layer file. Do not split.

- [ ] `AgentServer.jl` → `AgentServerModule.jl`, code 7

Three of this batch's four are done. `ChildrenContainer.jl`,
`GestureBindings.jl` and `ProjectionApi.jl` are fragments of `ProjectionModule`
now. See
[projection-layer-is-one-module.md](../done/projection-layer-is-one-module.md).

### Batch 8 — the kernel, split

The layer file `<Layer>Layer.jl` includes the new head file, and the head file
includes the old one.

- [ ] `clock/Clock.jl`, code 23
- [ ] `operation/Intent.jl`, code 25
- [ ] `cell/PerformanceCounter.jl`, code 27
- [ ] `editor/Playback.jl`, code 54
- [ ] `binding/GestureBinding.jl`, code 68
- [ ] `gesture/GestureRecognizer.jl`, code 107
- [ ] `editor/Editor.jl`, code 131
- [ ] `event/EventPattern.jl`, code 213

Four more are done. `ProjectionReferenceStep.jl`, `PrinterContext.jl`,
`Projection.jl` and `ProjectionTemplate.jl` are fragments of `ProjectionModule`
now, and the layer has the head file it lacked.

## What ends the campaign

The prize is a guard that states the law in one sentence.

- [ ] Delete the slice exception in
  [test/suite/naming.jl](../../test/suite/naming.jl). `module_violations` allows
  a file to declare the module of its slice rather than one named after itself.
  That exception exists only because 66 modules hide in a fragment.
- [x] Delete `_PENDING_SLICE_MODULES`. It parked `ConsoleBackendModule` and
  `PdfBackendModule`. Batch 4 and batch 5 settled them, and the guard passes
  without it. Proved by breaking: with the exception removed on `main`, the
  guard reports both files.
- [ ] Prove the guard by breaking it. Move one module head back into a fragment
  and see the guard report it.
- [ ] Update the module inventory in
  [documentation/design/system-anatomy.md](../../documentation/design/system-anatomy.md).
- [ ] Fix four stale references to `plan/pending/one-module-per-slice.md`. That
  plan is in `plan/done/`. They are in `test/suite/naming.jl` lines 30, 102 and
  167, and `source/projection/generic/Identity.jl` line 11.

## Decisions

**`__init__` goes to the head file.** It is the load-time registration of the
whole slice. In json it names `JsonDocument`, `JsonToSyntax`, `parse_json` and
`JsonFile`, one from each fragment. The whole tree already keeps `__init__` next
to the module head, so nothing moves except the head itself.

**A fragment gets a comment, not a docstring.** A docstring above a fragment
documents nothing, because the fragment declares no module. The comment names
the module the fragment belongs to. `ReactiveCell.jl` in the kernel shows the
form.

**A slice splits even when it is one file.** `component`, `focus`, `console` and
`pdf` each hold the whole slice in one file. A rename would satisfy the law and
cost nothing. A split is better: `<Slice>Document.jl` is written law in
[documentation/rule/naming-rules.md](../../documentation/rule/naming-rules.md),
and every slice then looks the same.

**A kernel module that is one small file renames.** The four in batch 7 declare
open generics. A head file above two `function … end` declarations helps no
reader.

**The naming rules gained a row.** `<Slice>Module.jl` is now in the file-name
table in `documentation/rule/naming-rules.md`. It landed with the json commit.

## What this plan does not touch

Twelve slices declare no module: `adaptagrams`, `anthropic`, `builder`,
`executable`, `mcp`, `ollama`, `projectured`, `repl`, `sdl`, `tulip`, `video`
and `web`. Each is one file that its package includes directly. Whether a slice
must declare a module is a separate question.
