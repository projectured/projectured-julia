# Shell

> **Kind:** design · **Status:** current · **Stands on:** [widget.md](../widget/widget.md), [screen.md](../screen/screen.md), [pane.md](../pane/pane.md)

The shell slice of `ProjecturedPlatform` holds everything that a window has besides the document in it: the wrappers that a binary stacks over its window, and the chrome that the window is drawn in. One slice holds both, so two binaries show one interface and can not drift into two lists. This document says why the wrappers have their order, how the chrome is a document, how the toolbar reaches the tools, and what does not work yet.

<img width="396" alt="Widget shell example" src="../../../asset/image/example/widget-shell.png">

## How it works

### The fold

`make_window_wrap(; …)` returns the fold `(document, projection) -> (document, projection)`. A window entry applies it before the window opens, and a binary names by keyword what its window has:

| Keyword | What it adds |
| --- | --- |
| `gesture_help` | F1 opens a window that lists the gestures that work where the person is |
| `command_palette` | Ctrl+Shift+P finds a command by name and runs it |
| `selection` | Alt and an arrow walk the objects, and the clipboard acts on the selected one |
| `clipboard_gestures` | which of the six gestures of `CLIPBOARD_GESTURES` the window has |
| `history` | a `projection -> projection` wrapper for what the window remembers |
| `shell` | the chrome: `(document) -> (menu_bar, toolbar, status_bar, context_menu, size)` |
| `context_menu` | the menu of the document under the pointer on a right press |

**The order is fixed.** From the inside out: the history, the shell, the start over of Tab, the selection walk with the clipboard, the context menu probe, the help, the palette, and the recorder of the gesture log.

- The **history** is innermost because it is a recursive type dispatch over the tree. A wrapper between it and the tree prints that subtree itself, and the recursion never reaches the type that it dispatches on.
- The **shell** is outside the document of the window and inside everything that acts on a window. So the walk and the clipboard reach into the chrome, and a verb that reads the pane tree goes past it with `get_wrapped_document`.
- The **start over of Tab** (`FocusCyclingProjection`) is around the shell, so it sees the whole window: Tab at the last stop of the window goes to the first stop, and Shift+Tab goes the other way. It takes no keyword.
- **The light under the pointer is not in the wrap.** The mouse target tracking of the screen (`make_tracking_screen`) sees every window, so it can tell that the pointer left a toolbar button for a row in a pane, or a window for a popup. [mousetargettracking.md](../mousetargettracking/mousetargettracking.md) describes it.
- The **context menu probe** is over the walk, because it reads the document that the walk selects in. It is under the help and the palette, because it must not answer for a window that one of those opened. It passes every event on.
- **The tooltip is not in the wrap.** A part answers a dwell from its own gesture table, and the wrapper that keeps the tooltip window sits at the screen, in `make_tracking_screen(; inner_wrappers = [wrap_tooltip_window])`. A host gives it in the `inner_wrappers` setting of the `window` wrapper of `build_editor`. [tooltip.md](../tooltip/tooltip.md) describes it.
- The **recorder** is outermost, where it sees every operation of the window. It takes no keyword and writes into the log of the session, and **View → Gesture log** opens that log in a tab. So the tab holds what happened before it opened, and a person can open it after a fault.

A wrapper that opens a window of its own needs `make_opened_window_projections()`, the value of the `opened_window_projections` setting of the `window` wrapper of `build_editor`. A host that turns the tooltip on passes `make_natural_tooltip_row(; measure)` in `content`, and the rows that draw its own documents, because a tooltip can hold a document of any domain. **A popup holds widgets**: the menu of a menu bar or of a context menu, and the options of a `WidgetSelect`, in a layout. So `make_opened_window_projections` ends with the rows of `WidgetToGraphics`, one for each widget and each layout, in the font and the measure the shell draws its bands with; the rows of `content` come before them, so a host decides first. A popup needs no wrapper of its own: a trigger answers its position in its own frame, each reader on the way up moves the position into its own frame, and the window opens the popup at its screen position. [widget.md](../widget/widget.md) describes the popup operation and how a reader moves it.

### The chrome is a document

`make_window_shell_document(document; menu_bar, toolbar, status_bar, context_menu, size)` puts the document of the window inside a `WidgetShell`, and `make_window_shell_projection(projection)` draws it. The bands draw through the dispatch of `WidgetToGraphics`, and the `content` slot goes to the projection that drew the window before, so the content draws as it did without the shell.

**The chrome is data.** A person can select, reference, walk, copy and save it, and a verb can reach it. A shell that only a printer made could be none of those. Wrapping is idempotent: a document that is already a `WidgetShell`, for example one read back from a file, keeps its identity and takes the bands that it is given.

**The shell fills its window.** The printer, `WidgetShellToGraphicsCanvas` in the widget package, takes the extent on each axis from the authored `size`, else from the available size that the parent gives. Only a shell with neither takes the size of its content. The window gives its own size as the available size, so the fold passes no `size`, and the shell follows the window when it resizes. The content gets the extent less the insets and the bands. A band gets the width and no height, so it is as tall as what it holds, and the status bar is on the bottom edge.

**What is saved is the window, and not the bands.** `WidgetShell` writes its `content`, its size, its margins and its style, and none of its bands. A menu bar and a toolbar belong to the binary, and the fold makes the bands again at each start, so one binary never writes its menu into a file that another binary opens. On open, a size that the application gives wins over the saved one.

### The menu bar

Each menu of the bar has its own make function. `make_window_file_menu()` makes File, with the commands that open and close a tab. `make_window_view_menu()` makes View, with the commands that split the focused group and open the gesture log. `make_window_help_menu(; about)` makes Help, with the commands that open the list of document types, the list of projections and the page about the program.

`make_window_menu_bar(; extra, about)` combines them: File, then View, then the menus of `extra`, then Help. Help is the last menu, as on a desktop, so a host's own menus go between View and Help.

Each Help item opens its tab through `_reach_tool!`, [the same function the toolbar uses](#the-toolbar-opens-the-tools). A second use of a Help item focuses the tab that is already open, and does not open a second one. The list of document types and the list of projections are longer than a pane, and a tab page gets no scroll of its own, so each opens inside a `WidgetScrollPane`, with the title of the list; `_find_tool_tab` looks into the scroll pane. A saved window keeps the list in its scroll pane, and where it was scrolled. `about` makes the page of the host's own program, from the editor; the default makes the page of ProjecturEd.

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

### The toolbar opens the tools

`make_window_toolbar(; assistant, explorer, extra)` holds one `WidgetToolbarItem` for each tool of the window: the explorer, the assistant, the evaluator, the message log, the gesture log, the fault log, the frame statistics and the selection. Each shows an icon, and its tooltip starts with the name of the tool. A new tab is not on it, because the tab strip of every group has a button for that.

`make_window_tool_command(label, type; icon, tooltip, make)` makes one button. **A press reaches the tool, and makes one only when none exists.** It gives the focus to a tab that holds a `type`: the first one in the focused group, else the first one in the window. A tab counts when the document that it wraps is a `type`, so a tool inside a history counts too. When no tab holds one, it opens `make(editor)` in a new tab. `make` makes by default what `Ctrl+T` and the name of the tool make. View → Gesture log calls the same function.

Two tools need what only the window has. `assistant` makes the assistant of the window, with its backend and its greeting; when it is `nothing`, the toolbar has no assistant button. `explorer` makes the file explorer over the folder of the window; when it is `nothing`, the button opens the working directory.

**A button must not open a tool that stays empty.** The window fills three tools, and not the tab. A capture of the logger and a feed fill the message log, a feed fills the frame statistics, and the fault store of the editor fills the fault log. `run_with_window_tools` gives all three, and a binary opens its window through it:

```julia
run_with_window_tools() do feeds, start
    editor = build_editor(document, projection; backend = backend, feeds = feeds,
                          window = (; title = "Title"))
    start(editor)
    run_editor!(editor)
end
```

The capture is removed when the window closes, also when it throws, so the logger that the window replaced comes back. [log.md](../log/log.md) and [statistics.md](../statistics/statistics.md) describe the two feeds.

**An Alt+click on a band selects in that band.** A band is not the `content` of the shell, so an Alt+press over the menu bar, the toolbar or the status bar names a field of that band. On the toolbar it names the button under the pointer, `toolbar.elements[i]`. A button of the toolbar answers a dwell with its name, so it shows its name as a tooltip.

### The pointer in a shell

The shell hands a press, a down, an up, a move, a scroll and a crossing to the band under the pointer, in that band's frame. A move with no button held goes first to the band or the content that the pointer leaves. **A drag keeps the band it started in**: the band that takes a `MouseDown` gets every move with a button held and the next `MouseUp`, wherever the pointer is. So a divider dragged across the status line keeps moving, and its release is not lost. A split pane reads a drag in progress before it checks its own bounds for the same reason.

A hover, a held button, a tab drag in flight and a divider drag are **view state**. The readers that write them mark the write with `ReplaceViewStateOperation`, and a history does not record it, so Ctrl+Z after a hover takes back the edit before it.

### The context menu probe

The document under the pointer gives its context menu. `compute_context_menu` is a generic function of `ProjecturedDomain`, and the fold gives it to the probe. Only `WidgetShell` carries a `context_menu` field, which holds the menu of the window itself. The context menu probe calls the function on the document under the pointer, and then on the root. So a right press on empty space also gets a menu.

### The file dialogs

`open_file_dialog!(editor, directory)` and `save_file_dialog!(editor, file, directory)` open a `WidgetDialog` over a `FileSystemChooser` as a window of its own. Both are built on `make_file_dialog`, because the chooser only chooses a path. The open command then applies `OpenFileOperation`, and the save command sets `file.filename` and applies `SaveFileOperation`. [filesystem.md](../filesystem/filesystem.md) describes the chooser.

## How it fits

The shell slice depends on the kernel and on the clipboard, domain, file-format, file-system, focus, gesturehelp, gesturelog, help, pane, projection, screen, style, tooltip and widget slices. The help slice gives the Help menu its three documents; [help.md](../help/help.md) describes them. Six more slices are there for the tools of the toolbar: assistant, conversation, fault, inspector, log and statistics. None of them depends on the shell.

The [application slice](../application/application.md) builds its window with the fold, the chrome and `run_with_window_tools`, and a downstream window host uses the same toolbar. The shell slice has no `__init__` and registers no row, file type or `.pred` type. A binary calls its functions.

## Design decisions

- **The order of the wrappers is fixed by what each one reads.** The reasons are in [the fold](#the-fold). See [plan/done/both-binaries-offer-one-interface.md](../../../../plan/done/both-binaries-offer-one-interface.md).
- **The chrome is a document.** A shell inside a printer could not be selected, saved or reached by a verb. See [plan/done/both-binaries-offer-one-interface.md](../../../../plan/done/both-binaries-offer-one-interface.md).
- **The shell takes the available size of its parent.** The rejected alternative was a shell that gives its content no available size when it has no authored `size`. That shell draws the panes only as wide as their content, and draws no status bar. See [plan/done/the-shell-fills-its-window.md](../../../../plan/done/the-shell-fills-its-window.md), and [layout-rules.md](../../../rule/layout-rules.md), which names the shell.
- **A press reaches a tool, and never opens a second one.** One rejected option was a press that always opens a new tab: three presses give three message logs with the same lines. The other was a second press that closes the tool, which loses the conversation of an assistant. See [plan/done/the-toolbar-opens-the-tools.md](../../../../plan/done/the-toolbar-opens-the-tools.md).
- **The shell names the tools.** The rejected options were a button that each tool slice registers in its `__init__`, and a table in `Application.jl`. A slice can not have the setup of the window, such as the backend of the assistant or the folder of the explorer, and a second window host can not reach a table in the application. The cost is six more dependencies. See [plan/done/the-toolbar-opens-the-tools.md](../../../../plan/done/the-toolbar-opens-the-tools.md).
- **The gesture log is always recorded.** The tab that shows it must hold what happened before it opened.

## Usage

```julia
wrap = make_window_wrap(; shell = document -> (make_window_menu_bar(),
                                               make_window_toolbar(; assistant = editor -> Assistant()),
                                               make_window_status_bar(document), nothing, nothing))
document, projection = wrap(document, projection)
run_with_window_tools() do feeds, start
    editor = build_editor(document, projection; backend = SdlBackend(), feeds = feeds,
                          window = (; title = "Title"))
    start(editor)
    run_editor!(editor)
end
```

- Tests: `test_shell()` runs the layering guard, `test_shell_completeness()`, `test_window_wrap()`, `test_widget_tooltip()`, `test_julia_tooltip()`, `test_tooltip_window()`, `test_context_menu_probe()`, `test_window_shell()` and `test_file_dialog()`. `test_shell_completeness()` fails when a `test_*` function under `test/platform/shell/` is not called by `test_shell()` exactly once. The layout of the shell and how it hands the pointer to its bands are in the platform suite, `test_widget_shell_layout()` and `test_widget_shell_pointer()`, and the whole window in `test_application()`.
- No example of its own: the application is the example.

## Limits

- The menu bar has no Save, Reload, Command palette, Gesture help or clipboard items. The keys work, but no verb reaches the owner of each command through the editor yet.
- There is no Tools menu, and the fault button shows no mark for a fault that nobody read.
- A press on the Assistant button after its tab closed opens a new, empty assistant, because the session keeps no assistant of its own.
- The gesture help, the command palette, the MCP server and the undo history have no document that a tool button could open.
- No test is marked `@test_broken`.
