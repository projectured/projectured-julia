# From-scratch structure — layers and slices, honestly applied

> **Layout note.** This plan was written when every domain lived in one
> `ProjecturedDomain` package. Each domain is its own package now — see
> [documentation/domains.md](../../documentation/domains.md). A path or a
> module name below that still says `package/domain/` or `ProjecturedDomain`
> needs translating when the plan is picked up.

A ground-up redesign of the package/layer/slice/module tree that follows
[architecture-rules.md](../../documentation/architecture-rules.md) and the numbered
requirements in
[architecture-requirements.md](../../documentation/architecture-requirements.md)
with no concession to backward compatibility. This is a *target*, not a plan: no phases,
no migration, no aliases. It answers one question — if the code were placed by the rules
today, where would every file sit?

Nothing here is a new *idea*. Every move below is forced by a rule the repository already
states; the design work was finding where the tree and the rules disagree.

## What the audit found

The structure is enforced by a guard with exactly one structural mechanism: an ordered
`layers` list plus a topological include-order check. There is **no declared slice DAG** —
visual's own guard docstring says so ("slice→slice edges are allowed provided the slice DAG
is acyclic, which is what the topological include-order check enforces"). Everything the
guard cannot see has drifted:

**Two slice-level cycles.** Acyclic at the file level (so the guard is green), cyclic at the
slice level (so the slices are not separable):

- `layout ⇄ widget` (visual) — `layout/LayoutToGraphics.jl` imports `WidgetModule` for
  focus-path helpers, while `widget/ObjectToWidget.jl` and `widget/WidgetToGraphics.jl`
  import `LayoutModule`. Resolved today only by hand-ordering the includes.
- `json ⇄ insertion`, and the same for `julia`, `sql`, `xml`, `yaml` (domain) — each
  domain's `*ToSyntax.jl` imports `InsertionModule`, while `insertion/InsertionToSyntax.jl`
  and `insertion/NaturalProjection.jl` import back into `JsonModule`, `JuliaModule`,
  `SqlModule`, `XmlModule`, `MathModule`, `BookModule`, `FileSystemModule`.

**Four documents owning cross-domain edges** — the rule is *"a document imports only its own
slice and the packages below; all cross-domain coupling lives in projections (the edges), not
documents (the nodes) — this is what makes slicing possible"*:

- `formula/Formula.jl` (the `@document` file) imports `..JuliaModule`.
- `workbench/Workbench.jl` (the `@document` file) imports `..ConversationModule`,
  `..JsonParserModule`, `..XmlParserModule`, `..JuliaParserModule`.

**Three slices in the wrong package**, by the lowest-home rule (*"code lives in the lowest
package of its DAG whose API it hard-references"*):

- `domain/gesturemap/` names no domain type at all — it imports the kernel's
  `GestureBindingModule` and visual's `SyntaxModule`. Its lowest home is **visual**.
- `domain/naturalformat/` (`DocumentFile.jl`, `NaturalFormat.jl`) is a persistence framework
  — the rules already assign it to base (*"base … the persistence frameworks (binary/natural
  serialization, document files)"*). It sits in domain only because it holds a hard-coded
  extension→parser table for four domains, which is what the seam pattern exists to invert.
- `base/backend/DefaultBackend.jl` is imported by nothing in any `main` tree and names only
  the kernel's `BackendModule`. Lowest home is the **kernel** backend layer.

**One misnamed layer.** `kernel/agent/` holds four files, and three of its names are wrong:
`Mcp.jl` contains no MCP (it is the editor's tool implementations; the protocol is in
`package/mcp`), `Agent.jl` is not the agent (it is the inbound server-hosting seam), and
`ToolRegistry.jl` knows Anthropic's wire format. The actual agent — the LLM loop — is
`_run_agent_loop!`, stranded in `domain/workbench/WorkbenchAssistant.jl`.

**One process-global registry.** `ToolRegistryModule._TOOLS` / `._RESOURCES` are module-level
`const` vectors, and `Mcp.jl` adds `_SCRATCH` (a shared scratch module for
`execute_julia_code`) and `LAST_VALUE`. AR-PER-EDITOR-STATE forbids exactly this — *"never in a module-level
`const` cell, `Ref`, `Dict`, or counter … one process must run many editors at once"*. Two
editors in one process today share one tool set, one scratch namespace, and one last-value.

**One test double in `main`.** `backend/HeadlessBackend.jl`'s scripted event queue is canned
input — AR-NO-TEST-DOUBLES-IN-MAIN / the no-test-doubles-in-`main` rule. (The device-layer plan noted this and
deliberately left it.)

## The enforcement change this design needs

Every structure below is *declarative*, and the guard must be able to reject an undeclared
edge — otherwise the slice DAG is decoration. `check_layering` grows one parameter:

```julia
check_layering(main, joinpath(main, "ProjecturedVisual.jl");
    layers = ["style", "graphics", "target", "decorator", "backend"],
    slices = Dict(                                  # undeclared cross-slice edge = failure
        "target/screen" => String[],
        "target/text"   => String[],
        "target/layout" => String[],
        "target/syntax" => ["target/text"],
        "target/widget" => ["target/text", "target/layout", "target/screen"],
    ))
```

This is ~15 lines in `layer_errors` (a set-membership test per cross-slice edge). It is what
makes *"documents own no cross-domain edges"* and *"anything two slices need is a framework"*
checkable instead of aspirational — and it is what catches both cycles above.

---

# The tree

## `package/kernel/main/` — 15 layers, by concept

The kernel keeps by-concept **layers**, never slices (*"keep by-concept layers where the kind
is itself the feature (the kernel)"*). The change is the top: one `agent` layer holding three
concerns becomes three layers at their three real heights — `tool` (the capability surface),
`llm` (the provider seam), `agent` (the glue). They are a genuine total order: an LLM request
carries `tools`, so `llm → tool`; the loop drives an LLM against a tool set, so
`agent → {llm, tool}`. MCP appears nowhere: it is a protocol, and protocols are opt-in
packages.

```
ProjecturedKernel.jl                 the layer diagram; 15 layer includes

cell/                                layer 1 — the reactive engine
  CellLayer.jl
  CellModule.jl
  AbstractCell.jl                    ▸ interface file
  ReactiveCell.jl
  MutableCell.jl
  ImmutableCell.jl
  CellAccess.jl
  StructPlan.jl
  CellStruct.jl
  Clock.jl
  PerformanceCounter.jl

event/                               layer 2 — the input vocabulary
  EventLayer.jl
  EventModule.jl
  Modifiers.jl
  KeyboardEvent.jl
  MouseEvent.jl
  WindowEvent.jl
  EventEnvelope.jl
  EventPattern.jl

device/                              layer 3 — where events come from
  DeviceLayer.jl
  DeviceModule.jl
  Device.jl                          ▸ interface file
  Keyboard.jl
  Mouse.jl
  Screen.jl

gesture/                             layer 4 — events → gestures
  GestureLayer.jl
  GestureRecognizer.jl

backend/                             layer 5 — the rendering-target seam
  BackendLayer.jl
  BackendModule.jl
  BackendInterface.jl                ▸ interface file
  BackendDefaults.jl                 + absorbs base/backend/DefaultBackend.jl
  Display.jl
  NullBackend.jl                     was HeadlessBackend: draws nothing, real backend.
                                     Its scripted event queue is a test double and leaves
                                     for package/kernel/example (AR-NO-TEST-DOUBLES-IN-MAIN).

document/                            layer 6 — the document contract
  DocumentLayer.jl
  DocumentModule.jl
  Document.jl                        ▸ interface file
  DocumentTrait.jl
  DocumentKind.jl
  DocumentCopy.jl
  DocumentSync.jl
  DocumentMacro.jl
  DocumentWalk.jl
  DocumentSearch.jl
  DocumentShow.jl
  Forward.jl

reference/                           layer 7
  ReferenceLayer.jl
  ReferenceModule.jl
  Interface.jl                       ▸ interface file
  ReferenceStep.jl
  ReferencePath.jl
  ReferenceEvaluation.jl
  ReferenceSearch.jl
  ReferenceSyntax.jl
  ReferenceCase.jl
  ReferenceBuilder.jl

selection/                           layer 8
  SelectionLayer.jl
  SelectionModule.jl
  Interface.jl                       ▸ interface file
  Selection.jl

operation/                           layer 9
  OperationLayer.jl
  OperationModule.jl
  Interface.jl                       ▸ interface file
  Operations.jl
  Rerooting.jl

binding/                             layer 10 — gesture → operation
  BindingLayer.jl
  GestureBinding.jl
  Gestures.jl

projection/                          layer 11
  ProjectionLayer.jl
  ProjectionApi.jl                   ▸ interface file
  IoMapApi.jl                        ▸ interface file
  ProjectionReference.jl
  Intent.jl
  IoMap.jl
  PrinterContext.jl
  ChildrenContainer.jl
  GestureBindings.jl
  Projection.jl
  ProjectionTemplate.jl

tool/                                layer 12 — the capability surface. No LLM. No MCP.
  ToolLayer.jl
  ToolModule.jl
  Tool.jl                            ▸ interface file — Tool, Resource, ToolSet
  ToolSet.jl                         register!/list/find/call — ON AN INSTANCE (AR-PER-EDITOR-STATE),
                                     replacing the process-global _TOOLS/_RESOURCES
  CodeExecution.jl                   execute_julia_code + its scratch module, per ToolSet
  Documentation.jl                   guides, module/type/function docs, search_documentation,
                                     search_api                   (all of today's agent/Mcp.jl)
  DefaultTools.jl                    register_default_tools!(::ToolSet)

llm/                                 layer 13 — provider abstraction. No MCP. No agent.
  LlmLayer.jl
  LlmModule.jl
  Llm.jl                             ▸ interface file — abstract Llm; stream_turn; tool_schema
  LlmRequest.jl                      system, messages, tools — the turn-varying part only.
                                     api_key/model are AnthropicLlm's config, not universal
                                     parameters, and move into the concrete struct.
  LlmEvent.jl                        TextDelta / ToolUseStart / ToolInputDelta / ToolUseStop /
                                     TurnEnd — neutral, not Anthropic's SSE names

agent/                               layer 14 — the glue: llm + tools + a target
  AgentLayer.jl
  AgentModule.jl
  Agent.jl                           Agent: llm, toolset, target, transcript
  AgentLoop.jl                       run_turn!: turn → tool_use → call_tool → tool_result → turn
                                     (extracted from domain/workbench/WorkbenchAssistant.jl)
  AgentServer.jl                     ▸ interface file — make/start/stop_agent_server!,
                                     the *inbound* hosting seam (today's agent/Agent.jl)

editor/                              layer 15 — the read-eval-print loop
  EditorLayer.jl
  Editor.jl                          gains `tools::ToolSet` (AR-PER-EDITOR-STATE: state on the instance)
  Playback.jl
```

## `package/base/main/` — 3 layers

```
ProjecturedBase.jl

document/                            layer 1 — the engine's documents
  DocumentLayer.jl
  DocumentCore.jl
  Domain.jl
  Primitive.jl
  Collection.jl
  collection/CellVector.jl
  collection/CellMatrix.jl
  collection/CellTable.jl
  collection/ListNode.jl
  Dragging.jl
  Insertion.jl                       the insertion document (the rules already put it here);
                                     it declares the seam each domain registers against
  Versioning.jl                      ← from domain/versioning/, IF it names no visual type
                                       (verify: if VersioningToAny renders, it goes to visual)

projection/                          layer 2 — the document-shaped generic projections
  ProjectionLayer.jl
  GenericCompound.jl
  HigherOrderCompound.jl
  ReaderDefaults.jl
  generic/Constant.jl
  generic/Identity.jl
  generic/Focusing.jl
  generic/Reversing.jl
  Copying.jl
  Filtering.jl
  Searching.jl
  Sorting.jl
  DraggingProjection.jl
  VersioningProjection.jl            ← from domain/versioning/VersioningToAny.jl (same caveat)
  higherorder/Chaining.jl
  higherorder/Nesting.jl
  higherorder/Recursive.jl
  higherorder/Switching.jl
  higherorder/EnvelopeUnwrapping.jl
  higherorder/PredicateDispatching.jl
  higherorder/ReferenceDispatching.jl
  higherorder/TypeDispatching.jl

serialization/                       layer 3 — the persistence frameworks
  SerializationLayer.jl
  BinarySerialization.jl
  NaturalFormat.jl                   ← from domain/naturalformat/. Keeps the framework;
  DocumentFile.jl                    ← the extension→parser table becomes a seam each
                                       domain slice registers into from the file it has.

(base/backend/ is deleted: DefaultBackend.jl names only the kernel's BackendModule and is
 imported by nothing — it sinks into kernel/backend/BackendDefaults.jl.)
```

## `package/visual/main/` — 5 layers, the middle one sliced

`style` is a leaf and `graphics` sits on it — both are single-concept layers, not slices. The
render targets *are* features that grow in number, so they are slices with a declared DAG.
The `layout ⇄ widget` cycle is broken the way the rules prescribe (*"the lower layer declares
open generics; higher layers add methods"*): the focus-path generic that `LayoutToGraphics`
reaches into `WidgetModule` for sinks below both users, into `graphics/Focus.jl`.

```
ProjecturedVisual.jl

style/                               layer 1 — the atoms (imports nothing)
  StyleLayer.jl
  Color.jl
  Font.jl
  TrueType.jl
  Geometry.jl
  Image.jl
  StyleStroke.jl
  StyleText.jl

graphics/                            layer 2 — the drawing document
  GraphicsLayer.jl
  Graphics.jl
  GraphicsCaching.jl
  PointReference.jl
  Focus.jl                           NEW — the focus-path generic, declared below both
                                     layout and widget. Kills the layout ⇄ widget cycle.

target/                              layer 3 — the render-target documents (slices)
  TargetLayer.jl                     declares the slice DAG:
                                       screen → ⌀        text   → ⌀        layout → ⌀
                                       syntax → text     widget → text, layout, screen
  screen/
    ScreenDocument.jl
    ScreenToScreen.jl
    WindowManaging.jl
  text/
    Text.jl
    TextRectangularReference.jl
    TextToGraphics.jl
    TextToString.jl
    PrimitiveToText.jl
    ReferenceToText.jl
    LineNumbering.jl
    WordWrapping.jl
    TextFiltering.jl
    TextFirstLine.jl
    TextHighlighting.jl
    SelectionInverting.jl
  layout/
    Layout.jl
    ConstraintSolver.jl
    CollectionToLayout.jl
    LayoutToGraphics.jl              now calls the focus_path generic; imports no widget
  widget/
    Widget.jl
    WidgetToGraphics.jl
    ObjectToWidget.jl
    CellTableToWidgetTable.jl
    WidgetHoverTracking.jl
    WidgetPopupResolver.jl
    ProjectionConfiguring.jl
  syntax/
    Syntax.jl
    SyntaxToText.jl
    ObjectToSyntax.jl
    CollectionToSyntax.jl
    PrimitiveToSyntax.jl

decorator/                           layer 4 — projections over any document (slices, no edges)
  DecoratorLayer.jl
  clipboard/
    Clipboard.jl
    ClipboardToAny.jl
    OsClipboard.jl
  tooltip/
    Tooltip.jl
    TooltipDecorator.jl
  inspector/
    ReferenceInspector.jl
    ReferenceInspectorToText.jl
    HoverProbe.jl
  gesturemap/                        ← from domain/gesturemap/ (names no domain type)
    GestureMap.jl
    GestureMapToSyntax.jl
    GestureHelpDecorator.jl

backend/                             layer 5 — the dependency-free output sinks
  BackendLayer.jl
  Console.jl
  Pdf.jl
```

## `package/domain/main/` — 3 layers of slices

The rules say *"pure feature slices … plus the application slices (workbench, conversation) in
the layer above"*. Two layers are not enough, because `workbench`'s **document** embeds
`Conversation` — a cross-slice document edge, and a violation, if they are siblings. There are
three real heights, and each one makes a would-be violation into a legal downward layer edge:

| Layer | Holds | Why it is its own height |
| --- | --- | --- |
| `source` | documents parsed from a text format, or standing alone | embeds no other domain's document |
| `composite` | documents built **out of** source documents | `Formula` embeds `JuliaDocument`; `Conversation`'s parts hold code in many languages |
| `application` | the editor applications | `Workbench` embeds `Conversation`, a workspace of files, and every parser |

`insertion/` disappears entirely. It is a bag of cross-domain edges, and it is half of the
`json ⇄ insertion` cycle. The insertion *document* is base's (the rules already say so); the
per-domain `InsertionToSyntax` / `NaturalProjection` methods move into each domain's own
`*ToSyntax.jl` — the seam pattern, *"multiple dispatch is the registration; a couple of methods
never earns a new file"*, and the projection-placement rule (*canonical home = the more-specific
side*) agrees: `Json`'s insertion behaviour belongs to the json slice.

```
ProjecturedDomain.jl

source/                              layer 1 — the pure domains (slices)
  SourceLayer.jl                     slice DAG: every slice → ⌀, except
                                       dbcatalog → sql   (via DbCatalogToSql.jl, a projection)
  json/
    Json.jl
    JsonParser.jl
    JsonToSyntax.jl                  + its insertion and natural-format methods
  xml/
    Xml.jl
    XmlParser.jl
    XmlToSyntax.jl                   + its insertion and natural-format methods
  yaml/
    Yaml.jl
    YamlParser.jl
    YamlToSyntax.jl                  + its insertion and natural-format methods
  julia/
    Julia.jl
    JuliaParser.jl
    JuliaToSyntax.jl                 + its insertion and natural-format methods
  markdown/
    Markdown.jl
    MarkdownParser.jl
    MarkdownToSyntax.jl
  sql/
    Sql.jl
    SqlParser.jl
    SqlToSyntax.jl                   + its insertion and natural-format methods
  math/
    Math.jl
    MathToSyntax.jl
  book/
    Book.jl
    BookToSyntax.jl
  graph/
    Graph.jl
    GraphLayout.jl
    GraphLayoutEngine.jl
    GraphToGraphLayout.jl
    GraphLayoutToGraphics.jl
  filesystem/
    FileSystem.jl
    FileSystemToSyntax.jl
    FileSystemToWidget.jl
  database/
    Database.jl
    DatabaseInstance.jl
    DatabaseAdapters.jl
  dbcatalog/
    DbCatalog.jl
    DbCatalogToSyntax.jl
    DbCatalogToSql.jl                the one declared source→source edge
  component/
    Component.jl

composite/                           layer 2 — documents built from source documents (slices)
  CompositeLayer.jl
  conversation/
    Conversation.jl
    ConversationToSyntax.jl
    ConversationToWidget.jl          the chat surface — a projection, not a loop
    ConversationEditor.jl            picks a projection per language (json/julia/xml)
    Evaluator.jl
  formula/
    Formula.jl                       may embed JuliaDocument: a downward layer edge, legal
    FormulaToSyntax.jl

application/                         layer 3 — the editor applications (slices)
  ApplicationLayer.jl
  workbench/
    Workbench.jl                     may embed Conversation + the parsers: downward, legal
    Workspace.jl
    WorkbenchToWidget.jl
    WorkspaceToFileSystem.jl
    WorkbenchFile.jl
```

`domain/workbench/WorkbenchAssistant.jl` is **gone**, split along the seam it was hiding:

- the agent loop (`_run_agent_loop!`, the SSE handling, the tool dispatch) → the kernel's
  `agent/AgentLoop.jl`, provider-agnostic and document-agnostic;
- the chat UI (the split pane, the turn rendering) → `conversation/ConversationToWidget.jl`,
  where a projection of a conversation belongs.

## The opt-in packages — one per external dependency or transport

Unchanged in shape; only `mcp` gains by the kernel losing its `Mcp.jl`.

```
package/llm/main/ProjecturedLlm.jl          AnthropicLlm + stream_turn + tool_schema(::AnthropicLlm)
                                            — the only file that knows Anthropic's wire format
package/mcp/main/ProjecturedMcp.jl          McpServer, the JSON-RPC/HTTP+SSE transport,
                                            registry→MCP bridges, make_agent_server(::Val{:mcp})
                                            (an MCP *client* — external tools registered INTO a
                                             ToolSet — is the same registry, opposite arrow, and
                                             becomes expressible for the first time)
package/sdl/main/ProjecturedSdl.jl
package/web/main/ProjecturedWeb.jl
package/odbc/main/ProjecturedOdbc.jl        implements domain/source/database's adapter seam
package/tulip/main/ProjecturedTulip.jl      implements visual/target/layout's solver seam
package/adaptagrams/main/ProjecturedAdaptagrams.jl   implements domain/source/graph's layout seam
package/video/main/ProjecturedVideo.jl
package/executable/…                        the app build
package/projectured/main/Projectured.jl     the umbrella re-export
```

## The triads

Unchanged: every package is `package/<name>/{main, test, example}`, three sibling packages of
equal standing, and the test/example DAGs mirror the main DAG. The redesign moves test and
example files only to follow their subject (`test/agent/` gains the agent-loop tests that are
`AssistantMvpTest` today; `kernel/example/` gains the scripted-event device that leaves
`HeadlessBackend`, alongside the `FakeLlm` / `ScriptedLlm` already there).

## Summary of every move

| From | To | Forced by |
| --- | --- | --- |
| `kernel/agent/ToolRegistry.jl` | `kernel/tool/` (Tool, ToolSet — per-editor) | AR-PER-EDITOR-STATE; the tool surface is independent of both LLM and MCP |
| `kernel/agent/Mcp.jl` | `kernel/tool/{CodeExecution,Documentation,DefaultTools}.jl` | it contains no MCP |
| `kernel/agent/Llm.jl` | `kernel/llm/` (+ neutral events, request struct) | a provider seam shaped like one provider is not a seam |
| `kernel/agent/Agent.jl` | `kernel/agent/AgentServer.jl` | it is the inbound hosting seam, not the agent |
| `domain/workbench/WorkbenchAssistant.jl` (loop) | `kernel/agent/AgentLoop.jl` | the agent loop is kernel-shaped: it names no domain document |
| `domain/workbench/WorkbenchAssistant.jl` (UI) | `domain/composite/conversation/ConversationToWidget.jl` | a chat surface is a projection |
| `kernel/backend/HeadlessBackend.jl` (scripted queue) | `kernel/example/` | AR-NO-TEST-DOUBLES-IN-MAIN — no test doubles in `main` |
| `base/backend/DefaultBackend.jl` | `kernel/backend/BackendDefaults.jl` | lowest-home rule; nothing imports it |
| `domain/gesturemap/` | `visual/decorator/gesturemap/` | lowest-home rule; it names no domain type |
| `domain/naturalformat/` | `base/serialization/` | the rules already place persistence frameworks in base |
| `domain/insertion/` | dissolved into each source slice + base's insertion document | it is half of the `json ⇄ insertion` cycle |
| `domain/versioning/` | `base/` (verify: only if it names no visual type) | lowest-home rule |
| widget's focus-path helpers | `visual/graphics/Focus.jl` | the seam pattern; kills the `layout ⇄ widget` cycle |
| `domain/{formula, conversation}` | `domain/composite/` | their documents embed other domains' documents |
| `domain/workbench` | `domain/application/` | its document embeds a composite document |

## What this does not settle

- **`component/`** — one file, no edges, and I have not read it. If `Component` is a
  framework rather than a domain, it sinks to base.
- **`versioning/`** — sinks to base if `VersioningToAny` names no visual type, to
  `visual/decorator/` if it renders. One grep decides it.
- **`math/`, `book/`** — placed in `source` on the strength of having no outgoing edges; if
  either embeds another domain's document, it is `composite`.
- **Whether `tool` at layer 12 is honest.** Its true dependency height is *zero* (it imports
  nothing). Placing it at 12 is a naming choice, and it buys the same permissiveness the
  device-layer plan accepted for `gesture`/`device`: the guard will permit `tool → projection`,
  an edge nobody wants. Declared slice edges would forbid it; declared *layer* edges would be
  the general fix, and are a bigger question than this document.
