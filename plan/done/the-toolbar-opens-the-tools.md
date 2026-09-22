# The toolbar opens the tools

**Status (2026-09-22): DONE.** Landed on `main` in both repositories:
projectured-julia Steps 1 to 7, omnet-julia Step 8 (`8de099db`). Nothing is
pushed. The owner answered the questions of §5 on 2026-09-22.

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

- [x] projectured-julia, at `b8f221f9` (the branch point), all pass:
      `test_widget_icon()` **26**, `test_widget_toolbar()` **8**,
      `test_tooltip_probe()` **16**, `test_window_shell()` **30**,
      `test_shell()` **109**, `test_fault()` **68**, `test_application()`
      **70**.
- [ ] omnet-julia, clean `main`: `test_ide_window_wrap()`, the test file
      `test/ide/IdeSelectAndPasteTest.jl`, and the count of the closure guard
      of `OmnetIde`. Taken at the start of Step 8, because `main` of
      omnet-julia moves until then.

### Step 1: seven icons

- [x] Register `:chat`, `:terminal`, `:list`, `:keyboard`, `:warning`, `:chart`
      and `:crosshair` next to the others in `WidgetToGraphics.jl`, and name
      them in the icon list of `widget.md`.
- [x] `test_widget_icon()`: each name is registered, and each draws only inside
      its box. **69** (26 + 43).
- [x] Look at them. A toolbar of menu items with the eight icons, written with
      `write_image` of the SDL backend at the real size, shows each picture
      clearly: the folder, the bubble, the `>_`, the list, the keys, the
      triangle with `!`, the bars and the crosshair. The picture is not in the
      repository, because no plan keeps pictures. The web backend needs no
      font for them: `Web.jl` sends `GraphicsCircle`, `GraphicsPolyline` and
      `GraphicsPolygon` as shapes.

### Step 2: `WidgetToolbarItem`

- [x] The document in `WidgetDocument.jl`, with the constructor sugar of
      `WidgetMenuItem` (`content`, `icon` and `action` fold into one `Action`),
      the export, a Tab stop in `FocusableWidget`, and `compute_tooltip` that
      falls back to the label. An empty label gives no tooltip.
- [x] The printer and the reader in `WidgetToGraphics.jl`, and the row in the
      dispatch table. A left press invokes the action, and a crossing sets
      `hovered`. The shortcut walk of the shell collects its action too. The
      icon is as tall as the line of `"M"` in the font of the item, and the
      canvas is as large as the icon and the padding.
- [x] `test_widget_toolbar()`: an item with an icon draws no text and is as
      wide as its icon and padding; an item with no icon draws its label; a
      crossing and a press land on the item under the pointer inside a
      toolbar (no test pressed a toolbar item before); a disabled item and an
      item bound to a disabled action are inert; the tooltip falls back to the
      label. **27** (8 + 19). `test_widget_icon()` stays **69**. The naming
      guard passes.
- [x] The widget guide names the new widget, and the icon list names the tool
      pictures.
- Open, not in this plan: `WidgetToolButton(icon)` is a helper that makes a
  `WidgetButton` with an icon and an empty label. It is the design that R5
  rejected, and its name is close to the new widget. The widget example uses
  it for a row of large icon buttons. Retire it, or keep it for that row, in a
  later change.

### Step 3: the shell reaches a tool

- [x] `make_window_tool_command(label, type; icon, tooltip, make)` in
      `WindowChrome.jl`, with R1 and R2. It makes a `WidgetToolbarItem`. The
      default `make` is `make_insertion_document(type)`, so the shell now
      depends on `ProjecturedDomain` (Step 5 adds the other six). The layering
      guard wants a bare `using ..DomainModule` for a name that the shell only
      calls; a `using` with a list of names fails it.
- [x] `_open_gesture_log!` became `_reach_tool!(editor, GestureLog, make)`,
      the one implementation of both. View → Gesture log keeps its behavior,
      and its test passes unchanged. A tab now counts when it wraps any
      `GestureLog`, not only the session log.
- [x] `test_window_shell()`: the first press makes one tool with the editor
      and gives it the focus; the second press makes none and reaches the same
      tab; with a tool in each group, the press reaches the one in the focused
      group; a tool inside a `ClipboardSlice` counts (the shell test package
      has no `UndoBuffer`, and both wrappers answer `get_wrapped_document`).
      **42** (30 + 12). `test_shell()` **121** (109 + 12).
- [ ] `make_window_toolbar` loses "New tab" in Step 5, with the table, so the
      toolbar is never empty in between.

### Step 4: the session fault log

- [x] `get_session_fault_log()`, `make_insertion_document(::Type{FaultLog})`,
      the alias `faults` and the title "Faults", in the fault slice. Like the
      two other session logs, `pred_arguments` saves the capacity and none of
      the entries: the faults of one session say nothing about the next. The
      fault package now depends on `ProjecturedDomain` and
      `ProjecturedSerialization`, and the layering guard passes.
- [x] `test_fault()`: `Ctrl+T` and `faults` give the session log, its title
      and its saved form are right, and a fault that a barrier records reaches
      it after `drain_faults!`. **73** (68 + 5).
- [x] The fault guide says how a window with tabs reads the log.

### Step 5: the shared toolbar and its setup, in the shell

- [x] Add the six packages of R3 to `[deps]` and `[sources]` of
      `package/ProjecturedShell/Project.toml` (the lists are now sorted), with
      a module alias each in `ProjecturedShell.jl` and a bare `using` in
      `ShellModule.jl`. `Pkg.resolve` in `environment/all` updates the entry
      of the shell in its manifest. `environment/build` does not hold the
      shell.
- [x] `test_shell_layering()` and the naming guard pass with the new imports.
- [x] `make_window_toolbar(; assistant, explorer, extra)` with the eight tools,
      R4, R6 and R10. "New tab" left the toolbar; it stays in File and on
      `Ctrl+T`. **No separator (R10):** a vertical `WidgetSeparator` needs a
      length of its own or an offered height, and the toolbar offers none, so
      a separator would need a guessed number for the height of an item.
- [x] The setup of R11 is `run_with_window_tools(run)`, with a do-block:
      `run(feeds, start)` opens the window. It installs the capture before
      `run` and removes it after, also when `run` throws, gives the two
      feeds, and `start(editor)` attaches the session fault log to
      `editor.faults`. `run_window_editor` has no hook for the moment when the
      window closes, so the capture must be around the call; one function
      keeps both binaries from drifting apart.
- [x] The docstring of `make_window_toolbar`, the shell module docstring and
      the shell guide (a new section, and a host example that no longer names
      the IDE's "Run").
- [x] `test_window_shell()`: the toolbar holds the tools in the order of R10,
      with the icons of R4 and a tooltip that starts with the name; it draws
      no text; `extra` comes last; a press on each button opens a tab of its
      type, and a second press does not; `assistant = nothing` gives no
      assistant button; `explorer = nothing` opens `pwd()`, and a named
      explorer opens its folder; `run_with_window_tools` gives the feeds, the
      capture and the fault log, and restores the logger after a throw. The
      shell test package reaches the tool types through the aliases of
      `ProjecturedShell`, which its loop binds, so it needs no new dependency.
      `test_shell()` **154** (121 + 33).

### Step 6: the application uses the shared toolbar

- [x] The shell of the application is a closure over the start assistant and
      `root`: `make_window_toolbar` gets an assistant made by
      `make_application_assistant` with the backend, the model and the window
      of tokens of the start assistant, and an explorer over `root`, made by
      the same `_make_application_navigator` that makes the navigator at
      start. `make_application_window` needs no new keyword: it already gets
      the start assistant. The warm-up of the build and `ApplicationTest.jl`
      call it unchanged.
- [x] `run_application` opens its window through `run_with_window_tools`, in
      place of its own capture and feeds; its `on_start` calls `start` and then
      `_start_application!`.
- [x] `test_application()`: the toolbar holds the seven tools of a window with
      no assistant, and the window draws none of their names nor "New tab";
      with an assistant, the button reaches the open one and makes none, and
      after its tab closes it makes one with the backend, the model, the
      window of tokens, the title "Assistant" and the greeting of the start
      assistant; a closed navigator comes back over `root`. **88** (70 + 18).
- [x] The README, the delivery roadmap and the system anatomy name the
      toolbar of tools, the new tab names and the new widget.

### Step 7: the real window

- [x] A test through the window scene, in `test_application()`: a press at
      the pixel of the "Message log" button, found by pressing along the band
      as a hand would, opens the session message log; the pointer at rest on
      it opens a window of style `:tooltip` that draws "Message log: …".
      **94** (88 + 6).
- [x] **The tooltip did not open at first, and the cause was in the shell,
      not in the new widget.** The tooltip probe finds the document under the
      pointer with a synthetic Alt+press. The shell answered every press
      through its `content`, so an Alt+press on a toolbar button selected
      `.windows[1].content.content.content` — the window content — and the
      probe found no tooltip. The select-and-paste plan taught every container
      to re-root an Alt+press answer into its child; the shell and the toolbar
      were not in its list. Three changes, each the rule the other containers
      already follow:
      - the toolbar re-roots the answer of the item under the pointer into
        `elements[i]`, as the composite does (`_route_toolbar_press`);
      - the shell reads an Alt+press over a band with that band alone and
        re-roots it into `menu_bar`, `toolbar` or `status_bar`
        (`_select_in_band`). It hit-tests only the bands, because the probe
        sends an Alt+press on every pointer move, and the content must not be
        read twice;
      - the toolbar item declines an Alt+press, so the press selects it and
        runs nothing.
      Now the press names `.windows[1].content.content.toolbar.elements[3]`.
      An Alt+press on the menu bar names `menu_bar`, where it named the window
      content before. The menu does not yet re-root into its items, so a menu
      item's tooltip still does not show; that is outside this plan.
- [x] `test_widget_toolbar()` **36**: an Alt+press on an item runs nothing,
      and in a toolbar it names `elements[i]`; a press anywhere on the item,
      also a corner or between the bars of `:chart`, hits it; with an offered
      height of 1000 the item stays 24 × 24. The other tests of a shell pass
      unchanged: `test_widget_action()` 43, `test_widget_tree()` 31,
      `test_anchor_point()` 17, the seven table and pane size tests,
      `test_shell()` 154, `test_gallery_wrappers()` 13.
- [x] Run the real window, as far as this machine allows. It has no display
      tool, no Xvfb and no browser, and a window on the owner's desktop would
      disturb the owner's work, so the window was driven offscreen: the
      application window exactly as `run_application` builds it (with an
      Ollama assistant), in a window scene, with presses and a pointer move
      read through the scene, and drawn by the SDL renderer with `write_image`.
      **Nobody pressed a button with a real pointer in a real window yet.**
      What the offscreen run showed:
      - the band draws the eight pictures in the order of R10, and no word;
      - a press along the band found all eight buttons, and the pointer at
        rest on "Message log" opened a `:tooltip` window that draws "Message
        log: what the program said in this session".
      It also found two faults, both fixed in `5c323e31`, with tests:
      - **the "Statistics" button missed presses.** A toolbar item took a hit
        only on the strokes of its picture, and the thin bars of `:chart` left
        gaps. The item now draws a clear surface over its whole box, as a
        button draws its panel.
      - **then every press below a button hit the button.** The item took its
        height from the offer of the band, which is the height of the window,
        so the clear surface covered the navigator and "the navigator opens a
        file" failed. The hover surface had the same fault before: it would
        have painted a column down the window. The item is now as large as its
        content on both axes.
      One more observation, not caused by this plan: the offscreen write-out
      draws only "File" in the menu bar, and no "View". The branch point
      `b8f221f9` draws the same, and the window scene draws "View", so it is
      a fault of the offscreen write-out alone. It is not investigated here.
- [x] Land Steps 1 to 7 on `main` of projectured-julia. `main` moved by 12
      commits during the work; the rebase onto `d539f35b` had one conflict, a
      comment above the application shell, where `main` rewrote the sentence
      about the size. After the rebase, all pass: `test_widget_icon()` 69,
      `test_widget_toolbar()` 36, `test_widget_shell_layout()` 14,
      `test_widget_menu()` 37, `test_shell()` 157, `test_fault()` 73,
      `test_gallery_wrappers()` 13, `test_evaluator_toplevel()` 27,
      `test_application()` 100 (`main` added 6), and the six widget table and
      pane tests. `test_document_insertion()` is 118 with 1 failure ("rendered
      completion feedback" compares a typed path with an untyped one); `main`
      at `d539f35b` fails the same assertion, so it is not from this plan.

### Step 8: omnet-julia, the IDE gets the same toolbar

Done in the worktree `omnet-julia-toolbar-opens-the-tools`, landed on omnet-julia
`main` as `8de099db`.

- [x] `_make_ide_shell(document, assistant)` gives `make_window_toolbar` the
      assistant of R8 and the explorer of R9, and no `extra`.
      `make_ide_window_wrap` takes an `assistant` keyword; `run_omnet_ide`
      makes it from the `assistant`, `llm`, `model` and `context` keywords it
      passes on, with `campaign_assistant` and the IDE greeting. A window
      opened with an assistant document of its own reopens that document, and
      one opened with `assistant = nothing` has no button.
- [x] `_ide_toolbar_commands`, `_run_selected_simulations!`,
      `_stop_focused_simulations!` and `_find_focused_batch` are gone, with the
      imports only they used. `CampaignVerbs` stays for the model. The
      docstring of `make_ide_window_wrap` no longer names Run and Stop.
- [x] `_open_file_navigator!` and the explorer button share
      `_find_project_folder` and `_make_workspace`. With no project folder the
      button opens the working directory.
- [x] `run_omnet_ide` opens its window through `run_with_window_tools`; the
      feeds go through `run_campaign_window` as keywords, and `start` runs in
      `on_open`.
- [x] The environments: `environment/all` and `package/OmnetIdeTest` of the
      worktree resolved (their manifests are untracked). The closure of
      `OmnetIde` grows from 46 to 50: `ProjecturedLog`, `ProjecturedFault`,
      `ProjecturedStatistics` and `ProjecturedInspector`. `IdeClosureTest`
      allows 50 with a paragraph that names the four, and requires them.
      **26** pass. `CampaignUiClosureTest` fails 2 (25 > 22, it reaches
      `ProjecturedSerialization`); a walk with projectured-julia at `d539f35b`
      counts 25 as well, so this plan adds nothing to it.
      `test_runner_closure()` 30.
- [x] Tests, from `--project=package/OmnetIdeTest`: `test_ide_window_wrap()`
      **29** (25 + 4: the IDE toolbar is the shell's, it holds the eight tools
      and no Run or Stop, and the assistant button reopens a closed assistant
      with the title "Assistant"). `test_ide_file_navigator()` 8.
      `test_select_and_paste()` goes from 72 pass, 7 fail, 3 errors to 81
      pass, 4 fail, 1 error: "a widget of the runner is selected" passes now,
      because the first "Run" on the screen is the runner's button. The rest
      fail the same with projectured-julia at `d539f35b` (a scratch
      environment with every projectured path at that commit): the note of a
      tool (lines 304-317) and an `evaluate_reference(::ClipboardSlice, …)`
      MethodError (line 434). `test_result_verbs()` 63, `test_result_views()`
      45, `test_study_verbs()` 54, `test_study_runs()` 10,
      `test_prompt_names()` 3, `test_ide_text_clipboard()` 9.
- [x] The runner guide names the toolbar of tools. The memory about the layers
      of the IDE window is updated.
- **Four untracked manifests of the omnet-julia main checkout are stale**:
  `environment/all`, `package/OmnetCampaignUiTest`, `package/OmnetIde` and
  `package/OmnetIdeTest` list the old dependencies of `ProjecturedShell`.
  Each needs `Pkg.resolve()` before it loads `OmnetIde`. They are generated
  files of the main checkout, which other sessions use, so this plan leaves
  them to the owner.

### Step 9: close

- [x] The shell guide, the widget guide, the fault guide, the README, the
      delivery roadmap and the system anatomy are updated in their steps.
- [x] The memory is updated, and this plan moves to `plan/done/`.

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
