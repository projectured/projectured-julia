# The export block of a module, one statement for each fragment

A module file lists its exports in `export` statements, and until now no rule
said how. Most kernel modules had one statement for all their fragments, some
grouped by a concept, and one had comments inside the list. So a reader who
found a name in the block could not tell which file defines it. The owner asked
for a rule on 2026-09-24, accepted the text below, asked for a guard, and asked
for a migration plan.

## The rule

In `documentation/rule/code-quality-rules.md`, section 1, after the three
header blocks:

> **The export block has one statement for each fragment, in the order of the
> includes.** A statement names what one fragment defines, in the order that the
> fragment defines it. A reader who finds a name in the block then knows which
> file to open, and a reader of a fragment finds all its public names in one
> place. The interface fragment comes first. Its statement names every generic
> that it declares, also when a sibling file holds the body. A fragment that
> defines no public name has no statement. Do not put a comment inside the
> block: the docstring of the module says what each fragment holds.

## The guard

`test/suite/exports.jl`, run by `test_exports()` in `ProjecturedSuite.jl` and
on its own as `julia test/suite/exports.jl`. Like the argument guard, it parses
and loads nothing. For each `*Module.jl` file under `source/`, it:

1. reads the `export` statements and the `include`s of the module file;
2. finds, for each exported name, the first fragment in include order that
   defines or declares it;
3. reports a statement that names two fragments, two statements for one
   fragment, statements out of include order, names out of the order of their
   fragment, a name that no fragment defines, and a comment inside the block.

A module that does not follow the rule yet is named in a list in the guard. A
module in that list that follows the rule is reported too, so the list can not
go stale.

## The migration

Not started. The owner decides when it starts. Each module in the list of the
guard gets its export block rewritten, and leaves the list. A sealed module
file needs the permission of the owner for that file first.

## Steps

- [x] 1. The rule text in `code-quality-rules.md`.
- [x] 2. The guard, its list of modules that do not follow the rule yet, and
  `test_exports()`. The first run found five kinds of finding:
  - the names of a statement are not in the order that the fragment defines
    them (133 statements);
  - a fragment comes after a later one, or has two statements (67);
  - one statement names several fragments (36);
  - no fragment defines a name (37): the name belongs to another module, which
    the naming rules forbid to export twice, or a macro such as `@document` or
    `@domain` exports it already;
  - a comment inside the export block (8).
- [x] 3. The migration list below, from the first run of the guard.

## The modules to migrate

The first run of the guard, on 2026-09-24: 8 of the 77 module files follow the
rule, and 69 do not. The count is the number of findings in each.

Kernel, 18 files. A sealed one needs the permission of the owner first.

| Module file | Findings | Seal |
| --- | ---: | --- |
| `source/kernel/agent/AgentModule.jl` | 2 | open |
| `source/kernel/backend/BackendModule.jl` | 1 | sealed |
| `source/kernel/binding/GestureBindingModule.jl` | 1 | open |
| `source/kernel/device/DeviceModule.jl` | 1 | sealed |
| `source/kernel/document/DocumentModule.jl` | 5 | open |
| `source/kernel/editor/EditorModule.jl` | 1 | open |
| `source/kernel/event/EventModule.jl` | 2 | migrated in the event audit, 2026-09-25 |
| `source/kernel/fault/FaultModule.jl` | 2 | sealed |
| `source/kernel/intent/IntentModule.jl` | 1 | open |
| `source/kernel/iomap/IoMapModule.jl` | 1 | sealed |
| `source/kernel/llm/LlmModule.jl` | 1 | open |
| `source/kernel/operation/OperationModule.jl` | 5 | open |
| `source/kernel/performance/PerformanceModule.jl` | 2 | sealed |
| `source/kernel/projection/ProjectionModule.jl` | 7 | open |
| `source/kernel/reference/ReferenceModule.jl` | 10 | open |
| `source/kernel/selection/SelectionModule.jl` | 1 | sealed |
| `source/kernel/struct/CellStructModule.jl` | 3 | sealed |
| `source/kernel/tool/ToolModule.jl` | 1 | open |

Slices, 51 files.

| Module file | Findings |
| --- | ---: |
| `source/assistant/AssistantModule.jl` | 2 |
| `source/book/BookModule.jl` | 1 |
| `source/chart/ChartModule.jl` | 6 |
| `source/clipboard/ClipboardModule.jl` | 4 |
| `source/collection/CollectionModule.jl` | 1 |
| `source/conversation/ConversationModule.jl` | 5 |
| `source/database/DatabaseModule.jl` | 3 |
| `source/dbcatalog/DbCatalogModule.jl` | 3 |
| `source/domain/DomainModule.jl` | 4 |
| `source/dragging/DraggingModule.jl` | 1 |
| `source/fault/FaultViewModule.jl` | 1 |
| `source/fileformat/FileFormatModule.jl` | 5 |
| `source/filesystem/FileSystemModule.jl` | 8 |
| `source/focus/FocusModule.jl` | 1 |
| `source/formula/FormulaModule.jl` | 2 |
| `source/fsm/FsmModule.jl` | 9 |
| `source/gesturehelp/GestureHelpModule.jl` | 5 |
| `source/gesturelog/GestureLogModule.jl` | 3 |
| `source/graph/GraphModule.jl` | 12 |
| `source/graphics/GraphicsModule.jl` | 8 |
| `source/inspector/InspectorModule.jl` | 3 |
| `source/json/JsonModule.jl` | 1 |
| `source/julia/JuliaModule.jl` | 8 |
| `source/layout/LayoutModule.jl` | 7 |
| `source/log/MessageLogModule.jl` | 3 |
| `source/markdown/MarkdownModule.jl` | 4 |
| `source/math/MathModule.jl` | 7 |
| `source/natural/NaturalModule.jl` | 2 |
| `source/odbc/OdbcModule.jl` | 1 |
| `source/pane/PaneModule.jl` | 5 |
| `source/plot/PlotModule.jl` | 2 |
| `source/primitive/PrimitiveModule.jl` | 1 |
| `source/process/ProcessModule.jl` | 10 |
| `source/projection/ProjectionAlgebraModule.jl` | 6 |
| `source/reflection/ReflectionModule.jl` | 4 |
| `source/rst/RstModule.jl` | 4 |
| `source/screen/ScreenModule.jl` | 1 |
| `source/sequencechart/SequenceChartModule.jl` | 6 |
| `source/serialization/SerializationModule.jl` | 3 |
| `source/shell/ShellModule.jl` | 1 |
| `source/sql/SqlModule.jl` | 4 |
| `source/statistics/FrameStatisticsModule.jl` | 4 |
| `source/style/StyleModule.jl` | 6 |
| `source/syntax/SyntaxModule.jl` | 6 |
| `source/text/TextModule.jl` | 11 |
| `source/tooltip/TooltipModule.jl` | 2 |
| `source/undo/UndoModule.jl` | 1 |
| `source/versioning/VersioningModule.jl` | 2 |
| `source/widget/WidgetModule.jl` | 22 |
| `source/xml/XmlModule.jl` | 7 |
| `source/yaml/YamlModule.jl` | 6 |
