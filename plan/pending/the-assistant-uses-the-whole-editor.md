# The assistant uses the whole editor

Status: a plan. Written 2026-10-15 from the answers of the owner on that day.
Nothing is built. Every decision is made. The plan spans two repositories: the
vocabulary and its verbs are in projectured-julia, and the OMNeT++ IDE in
omnet-julia declares them.

Stands on: [the-assistant-reaches-a-referenced-document.md](the-assistant-reaches-a-referenced-document.md)
(the `ReferencedDocument` that a verb takes and answers) and
[a-fast-loop-for-the-assistant.md](a-fast-loop-for-the-assistant.md) (the
rehearsal of step 7).

## 1. The goal

The assistant and the person work in one window together. The assistant can:

- **read** what the person does, what the window shows, and the data under it, as text;
- **tell** the person something: a document, a table, a drawing, a chart, a page;
- **control** the window: the selection, the panes, the settings;
- **change** a document with every command that a key or the command palette runs.

Both windows offer the same vocabulary. A model finds each verb by its
documentation, and each verb carries an example.

## 2. The ask of the owner (2026-10-15)

- "think a bit more generally, anything is useful from the editor API with which
  the assistant can communicate information to the user, can manipulate or
  control the user interface and help the user, and can retrieve information
  about what the user is doing or what the user interface is representing, what
  is the underlying data (e.g. printing any part into a string)"
- "anything that is available for the omnet IDE should be available for the
  projectured editor and vice versa if it makes sense. Clearly if something is
  specific to omnet IDE, then projectured will not get that."
- "the goal is to make the collaboration of the assistant and the user better,
  more integrated, with more possibilities."
- "we should make sure that all such verbs and tools are properly documented for
  the agent to discover them based on the documentation, including usage
  examples"

## 3. The facts (2026-10-15)

### The surface

- A model has six tools (`register_default_tools!`,
  `source/kernel/tool/DefaultTools.jl:336`). `execute_julia_code` resolves only the
  names that `declare_api!` declared. An MCP or an ACP agent gets the same tool
  set (`source/adapter/mcp/McpServer.jl:367`).
- The application declares `make_application_api()`
  (`source/platform/application/Application.jl:351`). `start_application!` adds the
  tools `undo`, `redo` and `take_picture`.
- The IDE declares `get_assistant_api()` (omnet-julia `source/ide/IdeWindow.jl:56`):
  the campaign, result and study lists, with `declare_api!` at
  `source/campaign/CampaignWindow.jl:265`. It does not call `start_application!`,
  so it has no `undo`, `redo` or `take_picture` tool.
- The IDE does not declare the file verbs, `print_natural_text`,
  `parse_natural_text`, `search_documents`, `insert_elements!`,
  `delete_elements!` or `get_registered_assistant_api()`. The application does not
  declare `make_task_api()`.
- `NedModule.jl:71` and `IniModule.jl:64` register their types with
  `register_assistant_api!`. No host in omnet-julia declares the registered
  entries, so the two registrations do nothing.
- The IDE has no undo wrapper (`make_ide_wrappers`, `IdeWindow.jl:229`). A file tab
  keeps its own `UndoBuffer`. `CampaignVerbs.jl:103`, `:212` and
  `CampaignWindow.jl:539` say that Ctrl+Z takes back an edit of the Runner. In this
  window it does not.
- `register_assistant_api!` keeps a list for the process
  (`source/platform/assistant/AssistantApi.jl:6`). The list holds what the loaded
  packages offer. It is the same for every editor and holds no state of a session,
  so this plan keeps it.

### The text forms

- `parse_natural_text(format::Symbol, text)` and `print_natural_text(document)`
  (`source/platform/natural/NaturalNotation.jl`). Ten formats have a parser: `:json`,
  `:yaml`, `:md`, `:jl`, `:math`, `:rst`, `:xml`, `:sql`, and in omnet-julia `:ned`
  and `:ini`.
- A parser takes a fragment: one JSON value, or one Julia expression. The Markdown
  parser answers a `MarkdownRoot` that holds one block.
- `print_natural_text` takes any part of a domain that has a notation, and a
  `ReferencedDocument`. It refuses a part with no notation, such as a widget, a
  pane, a chart or a graph.
- `print_pred_text(document)` (`source/platform/serialization/PredFile.jl:245`)
  prints any document as its own constructor. `parse_pred_text` reads it back.

### Read and control

- `get_selection(document)` answers the selection. `ReplaceSelectionOperation(path)`
  (`source/kernel/operation/Operations.jl:158`) sets it from the root.
  `convert_to_whole_selection` (`source/platform/focus/WholeSelection.jl:51`) makes
  the whole selection that Alt+click makes.
- `get_mouse_target(document)` (`source/kernel/operation/PathChain.jl:49`) answers
  the part under the pointer. `get_pane_focus(tree)`
  (`source/platform/pane/PaneSurgery.jl:174`) answers the focused tab.
- `get_session_gesture_log`, `get_session_message_log` and `get_session_fault_log`
  answer the three logs of the session. `find_undo_buffer(document)` answers the
  history, and each entry of its `undo_entries` has a `label`.
- `read_os_clipboard()` and `write_os_clipboard!(text)`
  (`source/platform/clipboard/Clipboard.jl:71`) read and write the clipboard.
- `find_editor_settings` and `ApplySettingOperation(group, name, value)` read and
  change a setting. `find_editor_appearance` answers the appearance.
- `OpenPageOperation` opens a part as the page of a navigator. When no navigator
  takes it, a tab with a navigator of its own opens
  (`source/platform/navigator/NavigatorModule.jl`).
- No mechanism scrolls a part into view, marks a part, or writes to the status bar.

### The commands

- The command palette and F1 ask the reader chain for every command at the
  selection: `read_intent(inner, recursion, Intent(CollectIntents()), iomap)`
  (`source/platform/gesturehelp/CommandPaletteDecorator.jl:212`,
  `GestureHelpDecorator.jl:146`).
- Each answer carries an operation that its binding built and that every stage
  rooted. `collect_gesture_rows` (`source/platform/gesturehelp/GestureMap.jl:49`)
  makes the rows.
- No function asks the chain for the commands from the editor.
  `read_rooted_operation` (`source/kernel/editor/ReadEvaluatePrint.jl:93`) asks the
  readers from the editor for one gesture.
- An `Intent` can carry a `route`: the path from the input of a reader to one part
  (`source/kernel/intent/Intent.jl`). A container gives the change to the child
  that the route names (`read_routed_child`,
  `source/kernel/projection/ProjectionDefaults.jl:325`). No reader finds the part
  by the pointer or by the selection. The context menu and the tooltip use this.
- At the end of a route, the part reads the gesture with its own table
  (`read_gesture`). Each binding gets the part as its target, and the selection
  that the part holds (`GestureBinding.jl:208`).
- After the part answers, the documents around it read the gesture only when the
  answer collects (`is_collecting_operation`). `CollectedIntentsOperation` does not
  collect, so a routed collection answers the commands of the part itself.

### The drawing

- The graphics documents (`source/platform/graphics/GraphicsDocument.jl`):
  `GraphicsCanvas`, `GraphicsRect`, `GraphicsText`, `GraphicsLine`,
  `GraphicsCircle`, `GraphicsArc`, `GraphicsPolyline`, `GraphicsPolygon`,
  `GraphicsSpline`, `GraphicsImage`.
- A graphics document draws as itself in a tab
  (`source/platform/natural/NaturalProjection.jl:191`). No test opens one in a tab.
- A `Chart` and its series (`source/domain/chart/ChartDocument.jl`) have no row in
  the natural renderer, so a chart made by hand does not draw in a tab. Only
  `FrameTimeSeries` has a row (`ChartModule.jl:58`).
- A `GraphGraph` draws through `register_natural_graphics!(:graph)`
  (`source/domain/graph/GraphLayoutToGraphics.jl:457`).
- No SVG reader or writer exists.

### The documentation

- `search_api` ranks by the name first. Then it ranks by the signature paragraph,
  the sentence under it, and a "Use it to" paragraph
  (`source/kernel/tool/Documentation.jl:295-330`, `:1073-1150`).
- `test/platform/projection/InterfaceApiTest.jl:38-56` asserts "Use it to",
  "See also" and an example that parses. It does this for 32 names only. No test
  does it for the rest of either list.
- The guide for a model is `documentation/guide/orientation.md`. The IDE adds
  `omnet/assistant-guide`. `tool/assistant/rehearsal.jl` has four tasks of one
  prompt each.
- Worked examples in the system text moved the rehearsal of S2 from 9 of 10 seeds
  to 10 of 10. The docstrings alone did nothing, because the model seldom reads
  them (a-fast-loop-for-the-assistant.md).

## 4. The decisions

- **D1. Decided by the owner, 2026-10-15.** A domain with a parser gets no declared
  constructors. The model reads the text of the domain with `print_natural_text`
  and writes text with `parse_natural_text`: "JSON: the assistant doesn't need the
  constructors if it can parse natural JSON, it knows that better. that is
  generally true for all domains which do have a parser". So the type
  registrations of JSON, NED and INI go.
- **D2. Decided by the owner, 2026-10-15 ("1: agreed").** The commands of a part:
  two verbs over `CollectIntents`.
- **D3. Decided by the owner, 2026-10-15 ("2: agreed").** Verbs that read and set
  the selection.
- **D4. Decided by the owner, 2026-10-15 ("3: agreed", and the second quote of
  §2).** One vocabulary for both windows. A verb that is specific to OMNeT++ stays
  in omnet-julia.
- **D5. Decided by the owner, 2026-10-15 ("4: agreed").** Declare the chart, the
  graph and a page in a navigator. Declare the graphics documents too: "graphics
  is good for drawing arbitrary stuff by the assistant, that can be useful like
  SVG to quickly paint something for the user".
- **D6. Decided by the owner, 2026-10-15.** The scope is read, tell, control and
  change (the first quote of §2).
- **D7. Decided by the owner, 2026-10-15.** Every verb and every tool has
  documentation that a model finds, with an example (the last quote of §2).
- **D8. Decided by the owner, 2026-10-15.** A verb of the assistant does not move
  the selection of the person: "why do we want to move the selection just because
  the assistant does something with something? I don't think that's generally
  useful", and "you can route gestures along a path to a part". The verbs of D2
  send `CollectIntents` with a route to the part, as the context menu sends its
  gesture. `select_part!` (D3) is the one verb that moves the selection, for when
  the assistant wants to show the person a part.

  My first proposal was to select the part first. It came from a wrong fact: I
  said that a collection at a part needs a new channel. The `route` of an
  `Intent` is that channel, and it exists.

  What a routed collection answers: the commands of the part's own table. The
  documents around the part are not asked, because `CollectedIntentsOperation`
  does not collect. This is right for a list of the part's commands: a binding of
  a parent reads the parent's own selection, so in that list it could act on
  another element. To insert or delete an element of a collection, the model uses
  `insert_elements!` and `delete_elements!`.

## 5. The vocabulary

The names that are new are proposals under the naming rules. The step that adds a
name makes it final. "Declared" means that the name exists and the list now
declares it.

| Group | Name | Kind | What it uses |
| --- | --- | --- | --- |
| Read | `find_selected_part()` | new | `get_selection`, answers a `ReferencedDocument` |
| Read | `find_part_under_pointer()` | new | `get_mouse_target` |
| Read | `find_focused_pane()` | new | `get_pane_focus` |
| Read | `print_pred_text` | declared | the text of a part with no notation |
| Read | `describe_natural_formats()` | new | the formats with a parser, their extensions and types |
| Read | `get_session_gesture_log`, `get_session_message_log`, `get_session_fault_log`, `find_undo_buffer` | declared | the logs and the history of the session |
| Read | `read_os_clipboard` | declared | |
| Read | the tool `take_picture` | both windows | |
| Tell | the graphics documents of §3 | declared | |
| Tell | `Chart`, its series and axes; `GraphGraph`, `GraphVertex`, `GraphEdge` | declared by their domain | |
| Tell | `open_page!(part)` | new | `OpenPageOperation` |
| Tell | `write_os_clipboard!` | declared | |
| Control | `select_part!(part)` | new | `ReplaceSelectionOperation` of a whole selection |
| Control | `find_editor_settings`, `find_editor_appearance` | declared | |
| Control | `change_setting!(group, name, value)` | new | `ApplySettingOperation` |
| Control | the tools `undo` and `redo` | both windows | |
| Change | `collect_commands(part)` | new | `CollectIntents` with a route to the part |
| Change | `run_command!(part, description)` | new | the operation of the row, run by the editor |

The verbs that exist stay as they are: `print_natural_text`, `parse_natural_text`,
`show_layout`, `describe_document`, the pane verbs, the widgets,
`show_roster!`, `replace_referenced_value!`, `insert_elements!` and
`delete_elements!`. After step 1, both windows declare them.

## 6. The steps

Each step works in a worktree of each repository that it changes, and ends with
its tests and a commit. Each name that a step adds or declares has:

- a docstring whose first sentence says what the name does in the words of the person;
- a "Use it to" paragraph, an `# Example` block that parses, and a "See also" line;
- a `text/plain` show of what it answers that a model can read.

After each change of a declared list, `test_referenced_document_editor` must pass.
If a rank moves, the fix is a word of a docstring, not the scorer of `search_api`.

- [x] **1. One vocabulary for both windows.** Done 2026-10-15.
  - What was built:
    - The Workspace of the Files pane is shared too, because the IDE also has a
      Files pane. So the application adds nothing to the shared list:
      `make_application_api` is renamed to `make_editor_api`, and the application
      declares it as it is.
    - `EDITOR_SYSTEM` is the shared paragraph, in the application slice.
      `CAMPAIGN_SYSTEM` holds it in place of its own paragraphs on the roster and
      the layout. Its sentence "every verb takes [`editor`] as its first argument"
      was false, and it now says that a verb acts on the editor.
    - The application slice may now use the task slice (`PLATFORM_SLICE_EDGES`).
    - The orientation guide writes JSON values with `parse_natural_text`, and its
      two notes no longer name the JSON types.
    - `search_api` put `find_pane_reference` above `find_pane` for "find pane"
      after the task names joined the list. The rank was fragile: without any one
      of six entries, `find_pane` was first again. The "Use it to" line of
      `find_pane` now says "find a pane", and the scorer is unchanged.
    - OmnetIde does not load ProjecturedDataFrames, so `make_result_api()` keeps
      its ten DataFrames names. Both declarations give the same bindings.
  - The counts: the application declares 132 names, the IDE 195, and the IDE
    holds each name of the application.
  - Failures that main has too, and that this step does not change:
    `test_application` 2 fail and 2 error (the evaluator and the restore of a
    closed pane), `test_campaign_verbs` 3 error (stale names), and
    `test_ide_file_navigator` 1 fail (a Julia file of the folder draws).
  - `make_editor_api()` in the application slice holds what both windows share:
    the pane, interface, file and natural text lists, `search_documents`,
    `get_wrapped_document`, the edit verbs, the arrangement and roster verbs,
    `make_task_api()`, and the registered entries.
  - `make_application_api()` is `make_editor_api()` with `Workspace` and
    `OpenFileOperation`. In omnet-julia, `make_campaign_api()` and
    `get_assistant_api()` start from `make_editor_api()`.
  - `register_editor_tools!(set)` adds `undo`, `redo` and `take_picture`.
    `start_application!` and `run_campaign_window` call it.
  - `make_ide_wrappers` turns on the `undo` wrapper, so Ctrl+Z works as the
    comments of the Runner say.
  - The type registrations of JSON, NED and INI go (D1).
  - The formula domain registers `get_formula_value`.
  - ProjecturedDataFrames registers the ten DataFrames names that
    `make_result_api()` declares now. `make_result_api()` keeps them only if
    OmnetIde does not load the adapter.
  - One shared paragraph of the system text names the shared verbs.
    `APPLICATION_SYSTEM` and `IDE_SYSTEM` both hold it.
  - Tests: `ApplicationTest` "the assistant's verbs", `test_interface_api`,
    `test_referenced_document_editor`. In omnet-julia: `test_prompt_names`,
    `CampaignVerbsTest`, `MeaningSearchMeasurementTest`.
- [ ] **2. Read.**
  - `find_selected_part`, `find_part_under_pointer`, `find_focused_pane` and
    `describe_natural_formats`.
  - Declare `print_pred_text`, the three log getters, `find_undo_buffer` and
    `read_os_clipboard`.
  - Tests: an editor with a JSON tab and a Markdown tab. After a selection, a
    pointer motion and an edit, each verb answers the part, the tab and the entry
    that the person made.
- [ ] **3. Control and tell.**
  - `select_part!`, `change_setting!` and `open_page!`.
  - Declare `find_editor_settings`, `find_editor_appearance` and
    `write_os_clipboard!`.
  - Tests: `select_part!` writes the complete selection at the root, and the status
    bar shows the part. `change_setting!` is undone by `undo`. `open_page!` opens a
    tab with a navigator.
- [ ] **4. The commands.**
  - `collect_commands(part)` and `run_command!(part, description)`, by D8.
  - They ask the chain from the editor with
    `Intent(CollectIntents(), nothing, "", "", get_reference(part))`. The editor
    evaluates the operation of the chosen row, which the readers rooted on the
    way back. They add no event, no payload, no reader method and no method of
    `is_collecting_operation`.
  - Check first that the route reaches a part through the chain of each window:
    the panes, a file tab, the history and the domain projections.
  - Tests: in a JSON tab, a Markdown tab and, in omnet-julia, a NED tab, the
    commands of a part are the rows of its own table that F1 shows when the person
    selects it. The selection of the person does not change. A command that
    `run_command!` runs is undone by `undo`.
- [ ] **5. Draw.**
  - Declare the graphics documents, `StyleColor` and `StyleFont`.
  - The chart domain registers a row of the natural renderer for `Chart`, so a
    chart made by hand draws in a tab. The chart and graph domains register their
    names with `register_assistant_api!`.
  - Tests: a `GraphicsCanvas`, a `Chart` and a `GraphGraph` opened with
    `open_pane!` draw in a tab, and a canvas draws inside a `WidgetCard`. The tests
    walk the painted output.
- [ ] **6. The documentation.**
  - A test asserts the docstring form of §6 for every name of `make_editor_api()`
    (ProjecturedPlatformTest) and for every name that the IDE adds (OmnetIdeTest).
    `test_interface_api` becomes part of it.
  - `orientation.md` gets one section for each group of §5, each with a worked
    example. `omnet/assistant-guide` keeps its sections for OMNeT++ and points to
    these sections for the shared verbs.
  - The shared paragraph of the system text gets one example line for each group.
  - The description of `execute_julia_code` names the four groups, so an MCP or
    ACP agent sees them.
- [ ] **7. The rehearsal and the live check.**
  - Six new tasks of one prompt each in `tool/assistant/rehearsal.jl`, at least
    one for each group. Examples: "what did I select?", "draw a red circle in a new
    tab", "add a heading to notes.md", "make the text larger".
  - Run seeds 1 to 10 with the model of the fast loop, and record the table of
    passes in this plan.
  - One round of repair from what the model missed: a name, or the first line of
    a docstring.
  - A live session in each window: select a part and ask about it, ask for a
    drawing, ask for an edit, and take the edit back.

## Not in this plan

Scroll a part into view, mark a part, or write to the status bar: no mechanism
exists, and each needs a design of its own · an SVG reader · a chart verb for a
data frame · a Tasks pane in either window (`TaskVerbs.jl:19` says that one
exists, but none does) · F1 or the palette opened by the model for the person ·
the `ask_person` tool for an MCP or ACP agent.
