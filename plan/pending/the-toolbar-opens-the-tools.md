# The toolbar opens the tools

**Status (2026-09-22): APPROVED, not started.** The owner answered the
questions of §5 on 2026-09-22. The plan is on the branch
`toolbar-opens-the-tools`, in the worktree
`workspace/projectured-julia-toolbar-opens-the-tools`.

**Goal:** the toolbar of the application window holds one button for each tool:
the assistant, the file explorer, the evaluator, the message log, the gesture
log, the fault log, and more. Each button shows an icon and no text, and a
tooltip names the tool. A press gives the focus to the tab that holds the tool,
or opens the tool in a new tab. The "New tab" button leaves the toolbar. **The
omnet-julia IDE window gets the same toolbar**, and it loses "Run" and "Stop".

**Repositories:** projectured-julia, then omnet-julia (Step 8). The plan changes
no sealed file: every file it touches is outside `source/kernel/`.

## 1. Why

- **"New tab" on the toolbar is a fourth way to one command.** The "+" in the
  header of each tab group, `Ctrl+T` and File → New tab do the same thing, and
  the "+" is nearer to the group that gets the tab.
- **The tools exist, but a person can not find them.** Each tool is a document
  that a tab can hold. Today a person reaches most of them only through `Ctrl+T`,
  Insert and a typed name such as `gestures` or `log`. Nothing in the window
  shows these names.
- **The tool-views plan left this open.** Its decision D3 says: "how does a
  person **reach** the assistant that is already open … is a separate plan"
  ([tool-views-replace-the-workbench.md](../done/tool-views-replace-the-workbench.md)).
  A toolbar button is one answer.
- **A closed tool has no way back that keeps its setup.** If a person closes
  the assistant tab, `Ctrl+T` and `assistant` open a blank `Assistant()` with
  the Ollama backend and no key. It does not have the backend, the model, the
  key or the greeting of the command line.

## 2. What exists

### The toolbar

- `make_window_toolbar(; extra = [])` in
  [WindowChrome.jl](../../source/shell/WindowChrome.jl) makes a `WidgetToolbar`
  that holds "New tab" and then `extra`.
- The application calls it with no `extra`, in `_application_shell` of
  [Application.jl](../../example/projectured/Application.jl).
- The omnet-julia IDE calls it with `extra = _ide_toolbar_commands()`, which
  holds "Run" and "Stop" as text buttons (`source/ide/IdeWindow.jl` there).
- `make_window_command(label, callback; icon, shortcut, tooltip)` makes a
  `WidgetMenuItem` whose `Action` carries the icon and the callback.

### Icons

- An icon is a `Symbol` key in `ICON_REGISTRY`
  ([WidgetToGraphics.jl](../../source/widget/WidgetToGraphics.jl)).
  `register_icon!(name, renderer)` adds one. The renderer draws vector graphics
  (`GraphicsPolyline`, `GraphicsPolygon`, `GraphicsCircle`) in a square box, in
  the color that the caller gives.
- The registry holds 22 names now, with aliases: `:chevron_down`, `:chevron_right`, `:check`,
  `:x`, `:close`, `:plus`, `:minus`, `:menu`, `:file`, `:folder`, `:save`,
  `:pencil`, `:edit`, `:trash`, `:delete`, `:search`, `:play`, `:pause`,
  `:stop`, `:step_forward`, `:step`, `:finish`.
- The printer of `WidgetMenuItem` draws the icon, a gap of 6 pixels and then
  the label. The icon is as tall as the text of the label. There is no mode that
  draws the icon alone.
- An unknown icon name draws nothing and takes no width.
- The SDL backend finds a glyph in a fallback font (DejaVu Sans Mono, then Noto
  Emoji). The web backend does not: it sends one font name for each text, and
  the browser does the rest. A vector icon draws the same on both backends.

### Tooltip and click

- `compute_tooltip(::WidgetDocument)` answers the `tooltip` of the widget, and
  `TooltipProbeProjection` opens it in a window of its own beside the pointer.
  The application turns this on, because it gives `make_window_wrap` a
  `pointer`.
- A left `MousePress` on a menu item gives an `InvokeActionOperation`, and the
  editor calls `action.callback(editor)`.
- **No test covers either one on a toolbar.** `TooltipProbeTest.jl` uses a
  `WidgetLabel`. `WindowShellTest.jl` calls `evaluate_operation` with an
  `InvokeActionOperation` directly. `WidgetToolbarTest.jl` tests only the hover.

### The tools

| Tool | Document type | A fresh one comes from | How a person opens it now |
| --- | --- | --- | --- |
| Assistant | `Assistant` | `make_application_assistant` (backend, model, key, greeting); `Ctrl+T` gives a blank `Assistant()` | at start, in a group of its own |
| File explorer | `Workspace` | the application: a folder over `root`; `Ctrl+T`: a folder over `pwd()` | at start, the "Files" group; `Ctrl+T` `explorer` |
| Evaluator | `EvaluatorToplevel` | `make_insertion_document` | `Ctrl+T` `evaluator` or `repl` |
| Message log | `MessageLog` | `get_session_message_log()` | `Ctrl+T` `log` |
| Gesture log | `GestureLog` | `get_session_gesture_log()` | View → Gesture log; `Ctrl+T` `gestures` |
| Fault log | `FaultLog` | **nothing**: there is no session log | **not at all** in the application |
| Frame statistics | `FrameStatistics` | `get_session_frame_statistics()` | `Ctrl+T` `statistics` |
| Selection | `SelectionInspector` | `make_insertion_document` | `Ctrl+T` `selection` |

- **The fault log is not in the application.** A fault goes to the
  `FaultStore` of the editor, and `drain_faults!` puts it into each log that
  `attach_fault_target!` attached. The application attaches no log. Only the
  gallery does, through `make_fault_tolerant_projection`.
- **View → Gesture log** is the model for a button. `_open_gesture_log!` looks
  for a tab whose `get_wrapped_document(tab.content)` is the session log. If it
  finds one, it gives that tab the focus. If not, it calls `open_pane!`.
- `open_pane!` puts the tab in the focused group, but never in the group that
  `pane_group_to_avoid` names while another group exists.
- These are not documents, so a tab can not hold them now: the gesture help, the
  command palette, the state of the MCP server and the undo history. This plan
  does not add them.

### The setup that the tools need

The application does three things that make three of the tools show something:

- `run_application` calls `install_message_log_capture!()` before the window
  opens, and `remove_message_log_capture!` after it closes. Without it the
  message log stays empty.
- It gives `run_window_editor` the feeds `MessageLogFeed()` and
  `FrameStatisticsFeed()`. Without them the message log and the frame
  statistics do not change.
- Nothing attaches a fault log (see above).

### The omnet-julia IDE window

- `run_omnet_ide` (`source/ide/IdeWindow.jl`) calls `run_campaign_window`
  (`source/campaign/CampaignWindow.jl`), which calls `run_window_editor`. Other
  keywords go through to `run_window_editor`.
- The IDE makes its assistant with `campaign_assistant(:auto; llm, model,
  context, greeting, system)`, so it always has one, also with `llm = :none`.
- `_open_file_navigator!` opens a `Workspace` over
  `get_project_result_directory(editor)`, with the title "Files", in the first
  group. The folder comes from the editor, not from an argument.
- `StudyVerbs.jl` finds the assistant pane by its title "Assistant". A
  reopened assistant gets that title from `ASSISTANT_TITLE`.
- The IDE has no message log capture, no feeds and no fault log.
- `_ide_toolbar_commands` gives "Run" and "Stop". No other code calls
  `_run_selected_simulations!`, `_stop_focused_simulations!` or
  `_find_focused_batch`.

### Packages

`ProjecturedShell` depends on `ProjecturedGestureLog` and
`ProjecturedFileSystem`. It does not depend on `ProjecturedLog`,
`ProjecturedConversation` (the evaluator), `ProjecturedFault`,
`ProjecturedStatistics`, `ProjecturedInspector` or `ProjecturedAssistant`.

None of these six packages depends on `ProjecturedShell`, so the shell can
depend on them with no cycle. Only `Projectured`, `ProjecturedShellTest` and the
omnet-julia package `OmnetIde` depend on the shell.

## 3. Decisions

R1, R3, R5 and the list of tools in §2 are decisions of the owner (§5). The other
decisions are my recommendations, and they follow from the code.

### R1. A button reaches the tool (decided by the owner)

A press gives the focus to a tab that holds a document of the type of the tool.
If no tab holds one, the press opens a fresh one with `open_pane!`. If several
tabs hold one, the press takes the first one in the focused group, and then the
first one in the order of the tree. A person who wants a second evaluator uses
`Ctrl+T`, as now.

This is what View → Gesture log does now, so the two stay one behavior.

**Rejected:** a press always opens a new one. Then three presses give three
message logs that show the same lines.

**Rejected:** a press that closes the tool when its tab has the focus. A closed
assistant loses its conversation, because there is no session assistant, so a
second press must not destroy work.

### R2. A tool is a row of data, and one shell function makes its button

The shell gets `make_window_tool_command(label, type; icon, tooltip, make)`.
`type` is the document type that R1 looks for. `make` takes the editor and
makes a fresh one. By default it is `editor -> make_insertion_document(type)`,
so a button opens what `Ctrl+T` and the name open. It takes the editor because
the IDE finds the folder of its explorer through the editor. A tab counts when
`get_wrapped_document(tab.content) isa type`, so a tab that holds the tool in a
history counts too.

`_open_gesture_log!` becomes one use of the same function, so View → Gesture log
and the button have one implementation.

**Rejected:** each tool slice registers its button from its own `__init__`, as
it registers its natural row. The assistant and the explorer need the setup of
the window (backend, key, folder), and the order of the buttons is one choice
for the whole toolbar. A slice can not know either one.

### R3. The shell names the tools, and the host gives the assistant and the folder (decided by the owner)

The owner decided that the IDE has the same toolbar as the application. So the
table of tools is in the shell, next to `make_window_toolbar`, and both windows
use it. The toolbar loses "New tab" and holds the eight tools, then `extra`:

    make_window_toolbar(; assistant = nothing, explorer = nothing, extra = [])

- `assistant` makes the assistant of this window from the editor. If it is
  `nothing`, the toolbar has no assistant button, because a blank assistant
  with no backend is not useful.
- `explorer` makes the file explorer of this window from the editor. If it is
  `nothing`, the button opens what `Ctrl+T` and `explorer` open: a folder over
  `pwd()`.

`ProjecturedShell` gets six more dependencies: `ProjecturedAssistant`,
`ProjecturedLog`, `ProjecturedConversation`, `ProjecturedFault`,
`ProjecturedStatistics` and `ProjecturedInspector`. None of them depends on the
shell (§2).

**Rejected:** the table in `Application.jl`. The IDE can not reach it, so the
two toolbars become two lists.

**Rejected:** a new package that holds only the table. The shell is already
"the chrome both binaries share", and one more package for one table adds a
name and no boundary.

### R4. The icons are vector icons, named after what they show

New names for `ICON_REGISTRY`, next to the 22 that exist:

| Name | Picture | Tool |
| --- | --- | --- |
| `:chat` | a speech bubble | Assistant |
| `:terminal` | `>_` in a frame | Evaluator |
| `:list` | lines of text, each with a dot | Message log |
| `:keyboard` | a key cap row | Gesture log |
| `:warning` | a triangle with `!` | Fault log |
| `:chart` | three bars | Frame statistics |
| `:crosshair` | a circle with a cross | Selection |

The file explorer takes `:folder`, which exists.

A name says what the icon shows and not which tool uses it, as `:folder` and
`:search` do now. Then a second use does not need a second name.

**Rejected:** emoji or Unicode glyphs as the label. The web backend has no font
fallback, the glyphs do not take the color of the theme, and Noto Emoji draws
in one color only.

### R5. A toolbar holds `WidgetToolbarItem`s (decided by the owner)

A new widget, `WidgetToolbarItem`, is one button of a toolbar. Like
`WidgetMenuItem` and `WidgetButton`, it is a view of an `Action`.

- It draws the icon of its action alone when the action has an icon. It draws
  the label when the action has no icon. The icon is as tall as a line of the
  font, and the item is as wide as the icon and its padding.
- It is flat. It draws a surface behind itself only while the pointer is on it.
- The label stays on the `Action`. It names the command, the tests find the
  command by it, and it is the tooltip when the item has no tooltip of its own.
- `WidgetMenuItem` keeps what only a menu needs: the submenu and the popup that
  closes after a click. It gets no new field.

This is what most widget libraries do. One command object has two views, and the
toolbar view is a type of its own: `QToolButton` in Qt, `ToolStripButton` in
WinForms, `GtkToolButton` in GTK 3 and `NSToolbarItem` in Cocoa. The command
keeps its text when the toolbar hides it, and the text becomes the default
tooltip. The rule "icon when there is one, else the text" is the rule of Swing.

A later mark on the fault button (§5, answer 3) and a pressed look while a tool
is open are toolbar concerns, so they go on this type and never on a menu item.

**Rejected:** a field on `WidgetMenuItem` that hides the label. It puts a
toolbar choice on a menu type.

**Rejected:** an empty label, with no gap after the icon when the label is
empty. It removes the name from the command.

**Rejected:** a `WidgetButton`. It draws a raised panel with a border and a
shadow, and eight of them in a band look heavy.

### R6. The tooltip names the tool first

Each tooltip starts with the name of the tool, because the icon does not say
it. Then it says what the tool shows. Example: "Gesture log: every gesture of
this session, and what each one did".

### R7. The fault log gets a session log

The fault slice gets `get_session_fault_log()`, like the message log and the
gesture log. `make_insertion_document(::Type{FaultLog})` answers it, with the
alias `faults` and the title "Faults". The setup of R11 attaches it to
`editor.faults` when the window starts, so the log holds every fault after the
window opened, also the faults from before the tab opened.

### R8. The assistant button opens an assistant with the setup of the window

- The application gives `assistant = editor -> make_application_assistant(backend;
  model, context)`. With `--assistant=none`, it gives `nothing`, and the toolbar
  has no assistant button.
- The IDE gives `assistant = editor -> campaign_assistant(:auto; llm, model,
  context, greeting, system)`, with the values that `run_omnet_ide` got.

A reopened assistant then has the backend, the model, the key and the greeting.
It does not have the conversation of the tab that closed. A session assistant
that keeps it is out of scope (tool-views D3).

### R9. The explorer button opens the folder of the window

- The application gives a `Workspace` over the `root` of the command line, the
  same one that it opens at start.
- The IDE gives a `Workspace` over `get_project_result_directory(editor)`, the
  same one that `_open_file_navigator!` opens. `_open_file_navigator!` then uses
  the same function, so the two can not differ.

### R10. The order of the buttons

Explorer, Assistant, Evaluator, then Message log, Gesture log, Fault log, then
Statistics, Selection. If a `WidgetSeparator` fits in a `WidgetToolbar`, a
separator goes between the three sets. If it does not fit, there is no
separator. Step 5 finds out.

### R11. The shell gives the setup that the tools need

A toolbar button that opens an empty message log is a button that lies. So the
shell gives the setup of §2 as one piece, and both windows use it:

- the message log capture, installed before the window opens and removed after
  it closes;
- the feeds `MessageLogFeed()` and `FrameStatisticsFeed()`;
- the session fault log, attached to `editor.faults` when the window starts.

The names and the shape (one function that runs the window, or three small
ones) follow [naming-rules.md](../../documentation/rule/naming-rules.md), and
Step 5 chooses them. The IDE reaches `run_window_editor` through
`run_campaign_window`, which passes other keywords on, so the feeds reach it
with no change to `run_campaign_window`.

## 4. Steps

Steps 1 to 7 are in projectured-julia, in this worktree. Step 8 is in
omnet-julia, in a worktree of its own, after Steps 1 to 7 are on the `main` of
projectured-julia: a change in a worktree of one repository is not visible to
the other one.

### Step 0: baselines

- [ ] projectured-julia, clean `main`: `test_widget_icon()`,
      `test_widget_toolbar()`, `test_tooltip_probe()`, `test_window_shell()`,
      `test_shell()`, `test_fault()`, `test_application()`.
- [ ] omnet-julia, clean `main`: `test_ide_window_wrap()`, the test file
      `test/ide/IdeSelectAndPasteTest.jl`, and the count of the closure guard
      of `OmnetIde`.

### Step 1: seven icons

- [ ] Register `:chat`, `:terminal`, `:list`, `:keyboard`, `:warning`, `:chart`
      and `:crosshair` next to the others in `WidgetToGraphics.jl`.
- [ ] `test_widget_icon()`: each name is registered, and each draws only inside
      its box.
- [ ] Look at them: render each one at the toolbar size in the SDL backend and
      the web backend, and put the screenshots in this plan.

### Step 2: `WidgetToolbarItem`

- [ ] The document in `WidgetDocument.jl`, with the constructor sugar of
      `WidgetMenuItem` (`content`, `icon` and `action` fold into one `Action`),
      the export, a Tab stop in `FocusableWidget`, and `compute_tooltip` that
      falls back to the label.
- [ ] The printer and the reader in `WidgetToGraphics.jl`, and the row in the
      dispatch table. A left press invokes the action, and a crossing sets
      `hovered`. The shortcut walk of the shell collects its action too.
- [ ] `test_widget_toolbar()`: an item with an icon draws no text and is as
      wide as its icon and padding; an item with no icon draws its label; a
      crossing lands on the correct item; a `MousePress` gives the
      `InvokeActionOperation` of its action (no test does this now); the
      tooltip falls back to the label.

### Step 3: the shell reaches a tool

- [ ] `make_window_tool_command(label, type; icon, tooltip, make)` in
      `WindowChrome.jl`, with R1 and R2. It makes a `WidgetToolbarItem`.
- [ ] `_open_gesture_log!` becomes a use of it. View → Gesture log keeps its
      behavior.
- [ ] `test_window_shell()`: the first press opens a tab of the type and gives
      it the focus; the second press opens no second tab; a tab in another
      group gets the focus; a tab that holds the tool in an `UndoBuffer`
      counts.

### Step 4: the session fault log

- [ ] `get_session_fault_log()`, `make_insertion_document(::Type{FaultLog})`,
      the alias `faults` and the title "Faults", in the fault slice.
- [ ] `test_fault()`: a fault that a barrier records reaches the session log
      after `drain_faults!`.

### Step 5: the shared toolbar and its setup, in the shell

- [ ] Add the six packages of R3 to `[deps]` and `[sources]` of
      `package/ProjecturedShell/Project.toml`. Run `Pkg.resolve` in each
      environment that holds the shell, because `instantiate` does not see a
      new dependency inside a package that the manifest already lists.
- [ ] `test_shell_layering()` and the naming guard pass with the new imports.
- [ ] `make_window_toolbar(; assistant, explorer, extra)` with the eight tools,
      R4, R6 and R10. "New tab" leaves the toolbar. Find out if a
      `WidgetSeparator` fits in the toolbar (R10).
- [ ] The setup of R11: the capture, the two feeds and the attach of the
      session fault log.
- [ ] Update the docstring of `make_window_toolbar` and the header of
      `WindowChrome.jl`.
- [ ] `test_window_shell()`: the toolbar holds the tools in the order of R10;
      no button draws text; a press on each button opens a tab of its type, and
      a second press does not; `assistant = nothing` gives no assistant button;
      `explorer = nothing` opens a folder over `pwd()`; the setup attaches the
      session fault log to `editor.faults`.

### Step 6: the application uses the shared toolbar

- [ ] `_application_shell` gives `make_window_toolbar` the assistant of R8 and
      the explorer of R9. `make_application_window` takes what it needs for
      that. The warm-up of the build and `ApplicationTest.jl` call it too, so
      they must keep working.
- [ ] `run_application` uses the setup of R11 in place of its own capture and
      feeds.
- [ ] `test_application()`: the toolbar holds the eight tools; there is no
      assistant button with `assistant = :none`; a reopened assistant has the
      backend and the greeting of the command line; a reopened explorer lists
      `root`.

### Step 7: the real window

- [ ] A test through the window scene: a `MousePress` at the pixel of a button
      opens the tool, and the pointer at rest on a button opens a tooltip window
      that holds the text of R6.
- [ ] Run `bin/projectured` and press each button with the real pointer. Put a
      screenshot of the toolbar in this plan.
- [ ] Land Steps 1 to 7 on `main` of projectured-julia.

### Step 8: omnet-julia, the IDE gets the same toolbar

- [ ] In `source/ide/IdeWindow.jl`: `_ide_shell` gives `make_window_toolbar`
      the assistant of R8 and the explorer of R9, and no `extra`.
      `make_ide_window_wrap` gets the values that it needs for the assistant
      from `run_omnet_ide`.
- [ ] Remove `_ide_toolbar_commands`, `_run_selected_simulations!`,
      `_stop_focused_simulations!` and `_find_focused_batch`. No other code
      calls them. `CampaignVerbs.run_simulations!` and `stop_simulations!` stay,
      because a model calls them. Remove the sentence "the toolbar carries Run
      and Stop" from the docstring of `make_ide_window_wrap`.
- [ ] `_open_file_navigator!` makes its `Workspace` with the explorer function
      of R9.
- [ ] `run_omnet_ide` uses the setup of R11. The feeds go through
      `run_campaign_window` as keywords.
- [ ] Resolve the environments of omnet-julia: the six new dependencies of the
      shell reach the closure of `OmnetIde`. The count of its closure guard
      changes. Record the new count and the reason.
- [ ] Tests: `test_ide_window_wrap()` against Step 0. The test "a widget of the
      runner is selected, and nothing runs" in `IdeSelectAndPasteTest.jl`: it
      clicks the first "Run" text on the screen and expects the `WidgetButton`
      of the Runner, which is now the only "Run" text. A new test: the IDE
      toolbar holds the same buttons as the toolbar of the application, and the
      assistant button opens a tab with the title "Assistant", which
      `StudyVerbs.jl` looks for.
- [ ] Update the guide of the IDE window if it names the toolbar, and the
      memory about the layers of the IDE window.

### Step 9: close

- [ ] Update [shell.md](../../documentation/package/shell/shell.md), the guide
      of the fault slice, and the README line about the toolbar if one exists.
- [ ] Update the memory, and move this plan to `plan/done/`.

## 5. Questions to the owner

The owner answered on 2026-09-22.

1. **Reach or toggle (R1).** Answer: **focus.** A press gives the focus to the
   open tool, or opens one.
2. **Which tools.** Answer: **the eight of the table in §2.**
3. **A mark on the fault button while the log holds a fault that nobody read.**
   Answer: **a later plan.**
4. **"Run" and "Stop" in the IDE.** Answer: **the IDE does not need them.**
   Step 8 removes them.
5. **The tool buttons in the IDE.** Answer: **the IDE has the same toolbar as
   the application.** R3 and Step 8.
6. **A new widget for a toolbar button.** Answer: **yes, a
   `WidgetToolbarItem`.** R5 and Step 2.

## 6. What this plan does not do

- It adds no Tools menu. View → Gesture log stays as it is.
- The fault button shows no mark for a fault that nobody read. That is a later
  plan (§5, answer 3).
- It makes no document for the gesture help, the command palette, the MCP
  server or the undo history.
- It adds no session assistant that keeps a conversation after its tab closes.
- It gives the tab strip no icons, although `PaneTab` has an `icon` field.
