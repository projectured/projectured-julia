# Shell

> **Kind:** reference · **Status:** current · **Stands on:** [system-anatomy.md](../../design/system-anatomy.md), [editor.md](../kernel/editor.md), [widget.md](../widget/widget.md)

The shell is everything a window has besides the document in it: the wrappers a
binary stacks over its window, and the chrome the window is drawn in. One
package holds both, so two binaries offer one interface and cannot drift into
two lists.

## What is in the slice

| File | What it holds |
| --- | --- |
| `source/shell/ShellModule.jl` | the module, and what it exports |
| `source/shell/WindowWrap.jl` | `make_window_wrap`, `make_opened_window_projections`, `make_popup_screen_wrap` |
| `source/shell/WindowShell.jl` | `make_window_shell_document`, `make_window_shell_projection` |
| `source/shell/WindowChrome.jl` | `make_window_menu_bar`, `make_window_toolbar`, `make_window_status_bar`, `make_window_command` |
| `source/shell/FileDialog.jl` | `make_file_dialog`, `open_file_dialog!`, `save_file_dialog!` |

## The fold

`make_window_wrap(; …)` answers the fold `(document, projection) -> (document,
projection)`. A window entry applies it before the window opens, and a binary
names by keyword what its window has:

| Keyword | What it adds |
| --- | --- |
| `gesture_help` | F1 opens a window that lists the gestures that work where the person is |
| `command_palette` | Ctrl+Shift+P finds a command by name and runs it |
| `selection` | Alt and an arrow walk the objects, and the clipboard acts on the one selected |
| `clipboard_gestures` | which of the five the window has |
| `history` | a `projection -> projection` wrapper for what the window remembers |
| `shell` | the chrome: `(document) -> (menu_bar, toolbar, status_bar, context_menu, size)` |
| `tooltip` + `pointer` | what the document under the pointer says about itself |
| `context_menu` | the menu of the document under the pointer on a right press |

**The order is not a preference.** From the inside out: the history, the shell,
the selection walk with the clipboard, the tooltip probe, the context menu
probe, the help, the palette, and the gesture log's recorder.

- The **history** is innermost because it is a recursive type dispatch over the
  tree. A wrapper between it and the tree prints that subtree itself, and the
  recursion never reaches what it dispatches on.
- The **shell** is outside the window's own document and inside everything that
  acts on a window, so the walk and the clipboard reach into it and a verb that
  reads the pane tree skips it.
- The **probes** are over the walk, because a probe asks the document the walk
  selects in, and under the help and the palette, because a probe must not answer
  for a window that one of those opened.
- The **recorder** is outermost, where it sees every operation the window makes.
  It is always there and takes no keyword: it writes into the session's own log,
  and **View → Gesture log** opens that log in a tab. So the tab holds what
  happened before it opened, and a person opens it after a fault rather than
  before one.

A wrapper that opens a window of its own needs
`make_opened_window_projections()`, which is the value of the
`opened_window_projections` keyword of `run_window_editor`.

## The popup route

`make_popup_screen_wrap()` is the value of the `screen_wrap` keyword of
`run_window_editor`. It puts `WidgetPopupResolverProjection` on the window route,
where the screen coordinates a popup needs are reachable. It is not part of the
fold, because the fold never sees the screen.

Without it a `WidgetSelect` does not drop down, a submenu does not open, and a
`WidgetContextMenu` swallows the right press.

## The chrome is a document

`make_window_shell_document(document; menu_bar, toolbar, status_bar,
context_menu, size)` puts the window's document inside a `WidgetShell`, and
`make_window_shell_projection(projection)` draws it.

**The chrome is structured data like everything else.** It can be selected,
referenced, walked, copied, saved and reached by a verb. A shell that existed
only inside a printer could be none of those.

A shell with no size hugs its content, which a window shell must not do, so a
caller that knows the window's size says it. Wrapping is idempotent, so a window
read back from a saved file is not wrapped twice.

**What is saved is the window, and not the bands.** `WidgetShell` writes only
its `content`. A menu bar belongs to the binary and is built fresh at every
start; writing it would put one binary's menu into a file another opens. The
fold fills the bands back in on load.

`WidgetShell` answers `get_wrapped_document`, so everything that reads the tree
rather than the picture looks straight through it.

## How a host adds a command

Each band takes an `extra`, and `make_window_command(label, callback; icon,
shortcut)` builds one item:

```julia
_ide_shell(document) =
    (make_window_menu_bar(),
     make_window_toolbar(; extra = Any[make_window_command("Run", _run_selected_simulations!)]),
     make_window_status_bar(document), nothing, nothing)
```

A host adds a command this way and names no widget package of its own.

**An item goes on a band only once it has a callback that does the work.** A
`WidgetShell` fires a menu shortcut **before the focused widget sees the key**,
so an item that carries a shortcut it cannot perform does not merely say
nothing — it takes the key away from whatever could have answered it. The
callback calls the slice's own verb, so the menu is a second way to one
implementation.

**What a menu command does is not what the log records.** The key travels as an
`InvokeActionOperation`, and the callback's own work reaches the tree through
that slice's verb.

**A status bar must be reactive.** Its segments are `ComputedCell`s over the
window's document, so the band follows the focus. A band built from strings would
say where the person was when the window opened and never again.

## The two probes

A tooltip and a context menu are answered by the document, not by the widget
alone:

- `compute_tooltip(document)` answers what the document says about itself. A
  widget reads a field somebody set; every other document computes one — a Julia
  function answers its signature and its prose.
- `compute_context_menu(document)` answers the menu a right press opens. Only
  `WidgetShell` carries a `context_menu` field, and it is the menu of the window
  itself: the probe asks the document it found and then the root, so a press on
  empty space is answered too.

**A tooltip is drawn in a window of its own, always** (`PAR-MANY-WINDOWS`). The
probe needs `pointer`, a 0-argument callable answering the pointer in screen
coordinates, because only a backend has the position of the pointer.

## The file dialogs

`open_file_dialog!(editor, directory)` and `save_file_dialog!(editor, file,
directory)` open a chooser as a window of its own. Both are built on
`make_file_dialog`, because **a chooser chooses a path and does nothing with
one**: a path that exists is a row of the tree, and a path that does not is a
name typed into a directory. The two commands differ only in the verb at the
end.
