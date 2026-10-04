# Shell

> **Kind:** design · **Status:** current · **Stands on:** [widget.md](../widget/widget.md), [screen.md](../screen/screen.md), [pane.md](../pane/pane.md)

The shell slice of `ProjecturedPlatform` holds everything that a window has besides the document in it: the wrappers that a binary stacks over its window, and the chrome that the window is drawn in. One slice holds both, so two binaries show one interface and can not drift into two lists. This document says why the wrappers have their order, how the chrome is a document, how the toolbar reaches the tools, and what does not work yet.

<img width="396" alt="Widget shell example" src="../../../asset/image/example/widget-shell.png">

## How it works

### The wrappers of a window

A window is a document and a projection built by `build_editor` with a keyword for each feature it has; [editor.md](../../kernel/editor.md#running-an-editor) describes the mechanism. A binary names by keyword what its window has. Seven features nest around the pane tree that the `tabs` wrapper of the pane slice makes, each in the layer `:container`, ordered by the number beside it:

| What a person sees | Keyword | Slice | Layer |
| --- | --- | --- | --- |
| Ctrl+Z takes back a change that belongs to no file | `undo` | undo | `:container => 5` |
| The menu bar, the toolbar and the status bar | `shell` | shell | `:container => 10` |
| Tab and Shift+Tab start over at the ends of the window | `focus_cycling` | focus | `:container => 20` |
| Alt+click, the Alt+arrow walk, and the clipboard | `clipboard` | clipboard | `:container => 30` |
| F1 opens the list of the gestures that work here | `gesture_help` | gesturehelp | `:container => 40` |
| Ctrl+Shift+P opens the command palette | `command_palette` | gesturehelp | `:container => 50` |
| Every gesture of the session, recorded | `gesture_log` | gesturelog | `:container => 90` |

**The order is fixed by what each wrapper reads.** From the inside out: `undo` sits next to the tabs, because it must hold every change below it, down to the pane tree itself. `shell` is around it and inside everything else, so a command of a band finds the pane tree in its content, and a verb that reads the pane tree goes past the chrome with `get_wrapped_document`. `focus_cycling` is around the chrome, so the cycle of Tab goes through the bands too, and not only through the panes. `clipboard` is around the cycle of the focus, so the Alt+arrow walk and the clipboard reach into the bands. `gesture_help` and `command_palette` are around the clipboard, so their lists name the gestures of the walk and of the clipboard too. `gesture_log` is outermost in this layer, so it sees every operation that the window makes, from any wrapper inside it.

Three more features fill what a tool of the toolbar shows, instead of nesting around the content. Each adds a feed or a start step to the editor, in the layer `:screen`, which acts once, on the root:

| What a person sees | Keyword | Slice | Layer |
| --- | --- | --- | --- |
| The message log fills with what the program logs | `message_log` | log | `:screen => 10` |
| The statistics and the frame times follow the frames | `frame_statistics` | statistics | `:screen => 20` |
| The fault log fills with what failed | `fault_log` | fault | `:screen => 30` |

[log.md](../log/log.md), [statistics.md](../statistics/statistics.md) and [fault.md](../fault/fault.md) describe each one; [gesturelog.md](../gesturelog/gesturelog.md) describes `gesture_log` above.

- **The light under the pointer is not a wrapper.** The screen gives each move to the window that the pointer leaves and to the window at the point, and each container gives it on to its children in the same way. Each document on the path writes its `mouse_target`, so a toolbar button goes dark when the pointer goes to a row in a pane, or from a window to a popup. [widget.md](../widget/widget.md) describes the light.
- **The tooltip window and the context menu window are wrappers that the window wrapper places.** A part answers a dwell or a right click from its own gesture table. The `tooltip` and `context_menu` wrappers of `build_editor`, on by default in the layer `:window` before the `window` wrapper, give `wrap_tooltip_window` and `wrap_context_menu_window` to it through `EditorParts.window_wrappers`, and it puts them around the screen inside the trackers. [tooltip.md](../tooltip/tooltip.md) and [context-menu.md](../widget/context-menu.md) describe them.

A wrapper that opens a window of its own needs `make_opened_window_projections()`, the value of the `opened_window_projections` option of the `window` wrapper of `build_editor`. A host that turns the tooltip on passes `make_natural_tooltip_row(; measure)` in `content`, and the rows that draw its own documents, because a tooltip can hold a document of any domain. **A popup holds widgets**: the menu of a menu bar or of a context menu, and the options of a `WidgetSelect`, in a layout. So `make_opened_window_projections` ends with the rows of `WidgetToGraphics`, one for each widget and each layout, in the font and the measure the shell draws its bands with; the rows of `content` come before them, so a host decides first. A popup needs no wrapper of its own: a trigger answers its position in its own frame, each reader on the way up moves the position into its own frame, and the window opens the popup at its screen position. [widget.md](../widget/widget.md) describes the popup operation and how a reader moves it.

### The chrome is a document

`make_window_shell_document(document; menu_bar, toolbar, status_bar, context_menu, size)` puts the document of the window inside a `WidgetShell`, and `make_window_shell_projection(projection; measure, appearance)` draws it. The bands draw through the dispatch of `WidgetToGraphics`, with the widget theme of the `Appearance` of the window, which the `shell` wrapper of `build_editor` and `make_opened_window_projections(; …, appearance)` take too, and the `content` slot goes to the projection that drew the window before, so the content draws as it did without the shell.

**The chrome is data.** A person can select, reference, walk, copy and save it, and a verb can reach it. A shell that only a printer made could be none of those. Wrapping is idempotent: a document that is already a `WidgetShell`, for example one read back from a file, keeps its identity and takes the bands that it is given.

**The shell fills its window.** The printer, `WidgetShellToGraphicsCanvas` in the widget package, takes the extent on each axis from the authored `size`, else from the available size that the parent gives. Only a shell with neither takes the size of its content. The window gives its own size as the available size, so the `shell` wrapper passes no `size`, and the shell follows the window when it resizes. The content gets the extent less the insets and the bands. A band gets the width and no height, so it is as tall as what it holds, and the status bar is on the bottom edge.

**What is saved is the window, and not the bands.** `WidgetShell` writes its `content`, its size, its margins and its style, and none of its bands. A menu bar and a toolbar belong to the binary, and the `shell` wrapper makes the bands again at each start, so one binary never writes its menu into a file that another binary opens. On open, a size that the application gives wins over the saved one.

### The menu bar

Each menu of the bar has its own make function. `make_window_file_menu()` makes File, with the commands that open and close a tab. `make_window_view_menu()` makes View, with the commands that split the focused group and open the gesture log. `make_window_help_menu(; about, gesture_help, command_palette)` makes Help, with the commands that open the list of document types, the list of projections and the page about the program. Gestures and Command palette come first, each only when its keyword is true.

`make_window_menu_bar(; extra, about, gesture_help, command_palette)` combines them: File, then View, then the menus of `extra`, then Help. Help is the last menu, as on a desktop, so a host's own menus go between View and Help.

Each Help item opens its tab through `_reach_tool!`, [the same function the toolbar uses](#the-toolbar-opens-the-tools). A second use of a Help item focuses the tab that is already open, and does not open a second one. The list of document types and the list of projections are longer than a pane, and a tab page gets no scroll of its own, so each opens inside a `WidgetScrollPane`, with the title of the list; `_find_tool_tab` looks into the scroll pane. A saved window keeps the list in its scroll pane, and where it was scrolled. `about` makes the page of the host's own program, from the editor; the default makes the page of ProjecturEd.

**Gestures and Command palette do what F1 and Ctrl+Shift+P do.** Each opens its tool, or closes it when it is open. The tool belongs to its wrapper, `gesture_help` or `command_palette`, which is around the shell, so a callback that has only the editor can not reach it. The command sends `ToggleGestureHelpOperation` or `ToggleCommandPaletteOperation` with `read_rooted_operation`, and the place is the `content` of the shell. The readers carry the operation to the content and lift it up again, so it passes every wrapper around the shell. The wrapper that owns it answers what its key answers, and the command posts what reaches the root. The shell is the first one on the path of the selection, else the only shell of the document, so the items work with and without panes. The rows of the help follow the selection, as for F1, so the place does not change them. An item carries no key, because the key reaches the wrapper itself and a menu item draws no key, and its tooltip names the key. The `shell` wrapper gives each keyword from the wrappers that are on.

### How a host adds a command

Each band takes an `extra`, and `make_window_command(label, callback; icon, shortcut, tooltip)` makes one item:

```julia
_host_shell(document) =
    (make_window_menu_bar(; extra = Any[WidgetMenuItem("Run"; submenu = WidgetMenu(Any[
         make_window_command("Run all", _run_all!)]))]),
     make_window_toolbar(),
     make_window_status_bar(document), nothing, nothing)
```

So a host adds a command and needs no widget package of its own.

**An item goes on a band only when its callback does the work.** `WidgetShell` fires a menu shortcut before the focused widget gets the key. So an item with a shortcut that it can not perform takes the key away from the widget that could answer it. The callback calls the verb of the slice that owns the command, so the menu is a second way to one implementation. The gesture log records the `InvokeActionOperation` of the item, and not the pane operation that the callback applies.

**A status bar must be reactive.** `make_window_status_bar(document)` makes each segment a computed cell over the document of the window: the title of the focused tab and the selection. A band built from strings would show the state of the window when it opened, and never change.

**The status bar shows the selection inside the document of the focused tab.** The part of the selection that leads to the tab, through the splits, the group and the tab of the pane tree, names no place in a document, so the band leaves it out. `find_pane_content_selection(tree)` of the pane slice gives the rest. The band shows nothing when the selection is on a tab title or a group, or names the whole document of the tab, which the title names already. A window with no pane tree shows the selection of its document.

### The toolbar opens the tools

`make_window_toolbar(; assistant, explorer, recorded, extra)` holds one `WidgetToolbarItem` for each tool of the window: the explorer, the assistant, the evaluator, the message log, the gesture log, the fault log, the frame statistics, the frame times, the selection and the appearance. Each shows an icon, and its tooltip starts with the name of the tool. A new tab is not on it, because the tab strip of every group has a button for that.

`make_window_tool_command(label, type; icon, tooltip, make)` makes one button. **A press reaches the tool, and makes one only when none exists.** It gives the focus to a tab that holds a `type`: the first one in the focused group, else the first one in the window. A tab counts when the document that it wraps is a `type`, so a tool inside a history counts too. When no tab holds one, it opens `make(editor)` in a new tab. `make` makes by default what `Ctrl+T` and the name of the tool make. View → Gesture log calls the same function.

Two tools need what only the window has. `assistant` makes the assistant of the window, with its backend and its greeting; when it is `nothing`, the toolbar has no assistant button. `explorer` makes the file explorer over the folder of the window; when it is `nothing`, the button opens the working directory.

**A button must not open a tool that stays empty.** Five tools show what the window records, and each fills only when the wrapper of `build_editor` that fills it is also on: the message log with `message_log`, the gesture log with `gesture_log`, the fault log with `fault_log`, and the statistics and the frame times with `frame_statistics`. `RECORDED_TOOLS` names the four keywords of those wrappers. The `shell` wrapper reads which of them are on in `parts.arguments` and passes those as `recorded` to `make_window_toolbar` and `make_window_menu_bar`, so a window built with none of the four has no button and no item for a tool that would stay empty:

```julia
editor = build_editor(document, projection; backend = backend,
                      window = (; title = "Title"), shell = true,
                      message_log = true, gesture_log = true,
                      fault_log = true, frame_statistics = true)
run_editor!(editor)
```

The message log needs no feed from the caller: its wrapper installs the capture of the logger and gives the editor a `MessageLogFeed`, and removes the capture again when the loop ends, also when it throws, so the logger that the window replaced comes back. [log.md](../log/log.md) and [statistics.md](../statistics/statistics.md) describe the two feeds. The explorer, the evaluator, the selection and the appearance need nothing more than the window.

### The `shell` wrapper

`shell = true | (; assistant, explorer, about, status_bar, measure, appearance)` is the wrapper of `build_editor` that puts the root document in the chrome of a window. It is off by default. It acts in the layer `:container` with the number 10, so it is around the pane tree that the `tabs` wrapper makes and around the `undo` wrapper when that is on too, and inside the cycle of Tab. The bands are the menu bar, the toolbar and the status bar of this slice, drawn with the widget theme of `appearance`, which defaults to the `Appearance` of the `appearance` wrapper of the same editor. The wrapper adds the rows of `make_opened_window_projections` to the windows that open later, so the menus of the bar draw.

A toolbar button and a menu item for a tool that shows what the window records appear only when the wrapper that fills that tool is also on; [the toolbar section above](#the-toolbar-opens-the-tools) says which. `shell` alone, with none of the four, builds a toolbar with the explorer, the evaluator, the selection, the appearance and the settings, and no button for any of the four. It has no assistant either, because an assistant needs a model, which the `assistant` option gives. The screen slice's `show_document!` looks through the shell exactly as it looks through the clipboard and the undo buffer, so a later document still opens in a tab and not in a window of its own; see [screen.md](../screen/screen.md#one-window-on-one-document). The display slice turns the wrapper on.

**An Alt+click on a band selects in that band.** A band is not the `content` of the shell, so an Alt+press over the menu bar, the toolbar or the status bar names a field of that band. On the toolbar it names the button under the pointer, `toolbar.elements[i]`. A button of the toolbar answers a dwell with its name, so it shows its name as a tooltip.

### The pointer in a shell

The shell hands a press, a down, an up, a move and a scroll to the band under the pointer, in that band's frame. A move with no button held goes first to the band or the content that the pointer leaves. **A drag keeps the band it started in**: the band that takes a `MouseDown` gets every move with a button held and the next `MouseUp`, wherever the pointer is. So a divider dragged across the status line keeps moving, and its release is not lost. A split pane reads a drag in progress before it checks its own bounds for the same reason.

A hover, a held button, a tab drag in flight and a divider drag are **view state**. The readers that write them mark the write with `ReplaceViewStateOperation`, and a history does not record it, so Ctrl+Z after a hover takes back the edit before it.

### The menu of the window

The `context_menu` field of `WidgetShell` holds the menu of the window itself. The shell binds a right click to it in its own gesture table ("Show the window menu", `make_context_menu_binding`). The shell gives a right click to the band at its point, as it gives a dwell, and then reads its own table. So a right click anywhere in the window adds the menu of the window as the outermost layer of the context menu, and F2 shows it from any part. A right click on a part with no menu opens the menu of the window alone. [context-menu.md](../widget/context-menu.md) describes the layers.

### The file dialogs

`open_file_dialog!(editor, directory)` and `save_file_dialog!(editor, file, directory)` open a `WidgetDialog` over a `FileSystemChooser` as a window of its own. Both are built on `make_file_dialog`, because the chooser only chooses a path. The open command then applies `OpenFileOperation`, and the save command sets `file.filename` and applies `SaveFileOperation`. [filesystem.md](../filesystem/filesystem.md) describes the chooser.

## How it fits

The shell slice depends on the kernel and on the clipboard, domain, file-format, file-system, focus, gesturehelp, gesturelog, graphics, help, pane, projection, screen, style, tooltip and widget slices. The help slice gives the Help menu its three documents; [help.md](../help/help.md) describes them. Six more slices are there for the tools of the toolbar: assistant, conversation, fault, inspector, log and statistics. None of them depends on the shell.

The [application slice](../application/application.md) builds its window with the wrappers of `build_editor` and the chrome of this slice, and a downstream window host uses the same toolbar. The [display slice](../display/display.md) turns the `shell` wrapper on by its keyword, and does not depend on this slice. The shell slice has no `__init__` and registers no row or file type. A binary calls its functions.

## Design decisions

- **The order of the wrappers is fixed by what each one reads.** The reasons are in [the wrappers of a window](#the-wrappers-of-a-window). See [plan/done/both-binaries-offer-one-interface.md](../../../../plan/done/both-binaries-offer-one-interface.md).
- **The chrome is a document.** A shell inside a printer could not be selected, saved or reached by a verb. See [plan/done/both-binaries-offer-one-interface.md](../../../../plan/done/both-binaries-offer-one-interface.md).
- **The shell takes the available size of its parent.** The rejected alternative was a shell that gives its content no available size when it has no authored `size`. That shell draws the panes only as wide as their content, and draws no status bar. See [plan/done/the-shell-fills-its-window.md](../../../../plan/done/the-shell-fills-its-window.md), and [layout-rules.md](../../../rule/layout-rules.md), which names the shell.
- **A press reaches a tool, and never opens a second one.** One rejected option was a press that always opens a new tab: three presses give three message logs with the same lines. The other was a second press that closes the tool, which loses the conversation of an assistant. See [plan/done/the-toolbar-opens-the-tools.md](../../../../plan/done/the-toolbar-opens-the-tools.md).
- **The shell names the tools.** The rejected options were a button that each tool slice registers in its `__init__`, and a table in `Application.jl`. A slice can not have the setup of the window, such as the backend of the assistant or the folder of the explorer, and a second window host can not reach a table in the application. The cost is six more dependencies. See [plan/done/the-toolbar-opens-the-tools.md](../../../../plan/done/the-toolbar-opens-the-tools.md).
- **The gesture log is always recorded.** The tab that shows it must hold what happened before it opened.

## Usage

```julia
editor = build_editor(document, projection; backend = SdlBackend(),
                      window = (; title = "Title"),
                      shell = (; assistant = editor -> Assistant()),
                      undo = true, clipboard = true, gesture_help = true,
                      command_palette = true, gesture_log = true,
                      message_log = true, fault_log = true, frame_statistics = true)
run_editor!(editor)
```

- Tests: `test_shell()` runs the layering guard, `test_shell_completeness()`, `test_window_wrap()`, `test_window_wrappers()`, `test_widget_tooltip()`, `test_context_menu_window()`, `test_window_shell()`, `test_file_dialog()`, `test_tracking_screen()` and `test_pointer_light()`. `test_shell_completeness()` fails when a `test_*` function under `test/platform/shell/` is not called by `test_shell()` exactly once. `test_window_wrap()` makes the parts of an editor with `make_editor_parts` and checks the document and the projection that each wrapper, and each pair of wrappers, builds. `test_window_wrappers()` builds a whole editor with `build_editor` and a headless backend, presses real keys through it, and checks what each wrapper does in a real frame. The layout of the shell and how it hands the pointer to its bands are in the platform suite, `test_widget_shell_layout()` and `test_widget_shell_pointer()`, and the whole window in `test_application()`.
- No example of its own: the application is the example.

## Limits

- The menu bar has no Save, Reload or clipboard items. The keys work, but no verb reaches the owner of each command through the editor yet.
- A menu item draws its label only, and not its key.
- There is no Tools menu, and the fault button shows no mark for a fault that nobody read.
- A press on the Assistant button after its tab closed opens a new, empty assistant, because the session keeps no assistant of its own.
- The gesture help, the command palette, the MCP server and the undo history have no document that a tool button could open.
- No test is marked `@test_broken`.
