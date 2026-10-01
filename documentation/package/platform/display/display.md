# Display

> **Kind:** design · **Status:** current · **Stands on:** [editor.md](../../kernel/editor.md), [screen.md](../screen/screen.md), [natural.md](../natural/natural.md)

The display slice of `ProjecturedPlatform` shows a value from the REPL in an editor that runs beside the REPL. It shows any value that a loaded package gives a document, and it depends on no such package, on no backend and on no container of documents. This document says how a value becomes a document, where the editor runs, and what the display leaves to other packages.

## How it works

### A value and its document

`display_in_editor(value; title, backend, tabs)` asks the seam `make_value_document(value)` of the widget slice for the document of the value. The package that owns the value's type adds the method: `ProjecturedDataFrames` adds it for a data frame, which shows as a `DataFrameView`. A value of a type that no loaded package gives a document is an error. `display(EditorDisplay(), value)` is the same call; this slice pushes no display, so a value at the prompt still prints as text.

The editor draws with `NaturalToGraphics`, which asks the seam `make_graphics_projection` for the projection of each document type, so the owner of the type decides how it draws.

### The editor beside the REPL

The first call starts the editor with `run_editor!(document, projection; wait = false)`. The kernel builds the editor and runs its loop on a task pinned to another thread of the default pool, because a backend such as SDL answers only the thread that started it. So the REPL keeps its speed, and the window stays live while an input runs. With no `backend`, the one loaded backend that draws windows runs the editor.

The loop logs each operation that it applies as an info line, and a hover is an operation. The display starts the editor inside `with_logger` with a console logger at the `Warn` level. The task of the loop keeps the logger of that scope, so the REPL shows the warnings and the errors of the editor and no line for each operation. The REPL keeps its own logger.

A later call shows its value with `show_document!` of the screen slice. Its `tabs` wrapper holds the values as tabs of one window, because the pane slice is always loaded with it. The window has the features of a window of the platform around its tabs, each a wrapper of `build_editor` that the display turns on by its keyword: the chrome (`shell`) with the menu bar, the toolbar and the status bar, the undo (`undo`), the clipboard and the walk (`clipboard`), F1 help (`gesture_help`), the command palette (`command_palette`), and the gesture log, the message log, the statistics and the fault log (`gesture_log`, `message_log`, `frame_statistics`, `fault_log`), which fill the tools of the toolbar. So the toolbar is the full one but the assistant, which needs a model. While the window is open, the message log also collects what the REPL logs; the REPL still prints it, and the window puts the logger of the process back when its loop ends. With `tabs = false`, each value has a window of its own instead, with none of these features, because they act on the tabs. A value that is shown already gets the focus again, and a title that the editor has already gets a number.

The loop keeps the world of its start, so every call that the display posts to the editor goes through `Base.invokelatest`. `close_display_editor!()` stops the editor, and a call after the window was closed starts a new one.

A value that a program changes in place stays the same object, so its document does not see the change. `refresh_display_editor!()` asks every shown document with a method of `refresh_document!` to read its value again, on the task of the editor, and waits until it did. With `refresh_every`, a number of seconds, the editor that `display_in_editor` starts does the same at that interval; it is off by default, because a program that writes a value while the editor reads it races the editor.

## How it fits

The display slice depends on the kernel for the run function and the inbox, on the screen slice for `show_document!`, on the widget slice for `make_value_document`, on the natural slice for the renderer and on the style slice for the measure. It names the `tabs` wrapper and the features of the window only by their keywords of `build_editor`, so it does not depend on the slices that declare them. A package that wants its values shown adds a method of `make_value_document` and uses only the widget slice of `ProjecturedPlatform`.

## Design decisions

- **The package that owns a type gives its document.** A seam, not a registry, so a method in a package's precompile cache is enough and no `__init__` registers anything. See [plan/pending/packages-compose-by-seams.md](../../../../plan/pending/packages-compose-by-seams.md), C1 and C4.
- **No fallback for a value without a document.** A reflected tree of any value is a later plan of its own: a package that keeps documents in step with the values they show (C15).
- **The loop takes input during a REPL input.** There is no pause: a refresh after the input reads the value again (C6).

## Usage

`ProjecturedDataFrames` exports `display_in_editor`, `refresh_display_editor!`
and `close_display_editor!` too, so a person who looks at a frame loads no more
than this:

```julia
using DataFrames, ProjecturedDataFrames, ProjecturedSDL
frame = DataFrame(a = 1:3)
display_in_editor(frame)
push!(frame, (a = 4,))
refresh_display_editor!()
close_display_editor!()
```

The display itself is a name of the platform:

```julia
using DataFrames, ProjecturedDataFrames, ProjecturedPlatform, ProjecturedSDL
display(EditorDisplay(), DataFrame(b = ["x", "y"]))
```

- Test: `test_display()` in `ProjecturedDisplayTest`.

## Limits

- No refresh runs by itself after each REPL input yet: a person calls `refresh_display_editor!()`, presses F5 in a data frame view, or passes `refresh_every`.
- `show_document!` applies no wrapper of the `:document` layer to a later value.
