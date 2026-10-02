# The Help menu opens the gesture help and the command palette

> **Status:** in progress since 2026-10-02, on the branch `help-menu-tools`.
> Written on 2026-10-02 at the owner's request. The owner decided the route (D1)
> and the place (D2) on 2026-10-02. D3 and D4 are my choices, because the owner
> said to start without a change to them; the owner can still change either. D3
> changed during S2, when I found that a menu item draws no key (3.5). S1 to S4
> are done.

## 1. The request

The owner asked on 2026-10-02:

> would it make sense to add to the help menu of widget shell in
> projectured-julia, the F1 context help and command palette help?

The owner then gave the mechanism:

> just like when the assistant opens or closes a pane, the operation is routed
> without a gesture to the receiver projection and it's reader returns the
> operation and it bubbles up to the editor

The owner chose the content of the shell as the place of the route ("ok, let's
use the shell then").

## 2. What exists

### 2.1 The Help menu

- The Help menu has three items: Documents, Projections and About
  (`make_window_help_menu`, `source/platform/shell/WindowChrome.jl:103-115`).
  Each item is a `make_window_command` with a callback that takes the editor.
- The docstring of `make_window_menu_bar` (`WindowChrome.jl:133-137`) and the
  limits of `documentation/package/platform/shell/shell.md` (line 154) say that
  the menu has no Command palette item and no Gesture help item, because no verb
  reaches the owner through the editor.
- A press on an item gives `InvokeActionOperation`. The editor evaluates it and
  calls the callback with the editor
  (`source/platform/widget/WidgetDocument.jl:2867-2880`).
- The shell fires a menu shortcut before the focused widget gets the key
  (`source/platform/widget/WidgetToGraphics.jl:3326-3331`).

### 2.2 The two decorators

- **F1.** `GestureHelpDecoratorProjection`
  (`source/platform/gesturehelp/GestureHelpDecorator.jl:110-133`) asks its inner
  reader first. If the inner reader gives no operation and the event is F1, the
  decorator collects the rows with `Intent(CollectIntents())` through its inner IO
  map. It then answers `OpenWindowOperation` with a `GestureMap`. A second F1
  answers `CloseWindowOperation`. The open flag is in `GestureHelpState`.
- **Ctrl+Shift+P.** `CommandPaletteDecoratorProjection`
  (`source/platform/gesturehelp/CommandPaletteDecorator.jl:155-187`) asks its
  inner reader first. `_open!` collects the rows, sets the `open` cell and
  answers `DoNothingOperation`. While the palette is open, it takes every event
  that has no route.
- Each decorator keeps its state and needs its own IO map to collect the rows.
  A menu callback has only the editor, so it can not reach them.

### 2.3 The route

- `read_rooted_operation(editor, place, operation)`
  (`source/kernel/editor/ReadEvaluatePrint.jl:93-103`) sends an operation from
  the root, with a route and no gesture. The readers carry it down to `place`.
  The parent at that place takes it as the answer of the child, and the readers
  lift it up to the root. The View menu uses it for the split commands
  (`_post_tree_operation!`, `WindowChrome.jl:292-297`).
- For an `EmptyReference`, `read_rooted_operation` returns the operation at once,
  and no reader runs (`ReadEvaluatePrint.jl:95`).
- An operation that names no place in a document declares
  `operation_travels_unchanged(...) = true`
  (`source/kernel/operation/Rerooting.jl:68-74`), so the readers on the way up
  keep it. Examples: `UndoOperation`, `SaveFileOperation`, `AdjustZoomOperation`.

### 2.4 The order of the wrappers

- `build_editor` applies the wrappers of a layer in the order of their numbers
  (`source/kernel/editor/EditorBuild.jl:247-258`). Each wrapper that comes later
  is around the wrappers before it. The container layer, from the inside out:
  `tabs` 0, `undo` 5, `shell` 10, `focus_cycling` 20, `clipboard` 30,
  `gesture_help` 40, `command_palette` 50, `gesture_log` 90. So both decorators
  are around the shell.
- The `shell` wrapper puts the root document into a `WidgetShell`, and the
  document becomes its `content`
  (`source/platform/shell/WindowShellWrapper.jl:39-56`).
- The shell reader carries a route that starts with `.content` to its content
  child, and reroots the answer by `.content` (`WidgetToGraphics.jl:3247-3264`).
- These readers between the shell and the help decorator pass a routed change to
  the inside and give the answer back:
  - `FocusCyclingProjection` (`source/platform/focus/FocusCycling.jl:37-49`).
  - `SelectionWalkingProjection` (`source/platform/focus/SelectionWalking.jl:36-48`).
  - The clipboard projections (`ClipboardSliceToAny.jl:489-494`,
    `ClipboardCollectionToAny.jl:163-168`).
- `WindowManagingProjection` applies an `OpenWindowOperation` or a
  `CloseWindowOperation` that comes up through its reader, and answers nothing
  (`source/platform/screen/WindowManaging.jl:117-125`). So in a window, the help
  window opens during the read.
- The shell wrapper knows which wrappers are on. `parts.arguments` holds the
  argument of each wrapper that is on (`EditorBuild.jl:31-35`). The wrapper
  already uses it for `recorded` (`WindowShellWrapper.jl:44`).

## 3. The design

### 3.1 Two operations

- `ToggleGestureHelpOperation`, in `GestureHelpDecorator.jl`.
- `ToggleCommandPaletteOperation`, in `CommandPaletteDecorator.jl`.

Each operation has no fields. Each declares `operation_travels_unchanged` and a
`describe_operation` for the gesture log. The names say what the key does: F1
and Ctrl+Shift+P each open and close.

### 3.2 Each decorator acts on its operation on the way up

Each decorator asks its inner reader first, as it does now. If the answer is its
own operation, the decorator does what its key does and answers what its key
answers:

- The help decorator answers `CloseWindowOperation` when the help is open. Else
  it collects the rows and answers `OpenWindowOperation`.
- The palette decorator closes the palette when it is open. Else it calls
  `_open!`. It answers `DoNothingOperation`.

The key and the operation call one function in each decorator, so the two paths
can not differ.

The rows come from `Intent(CollectIntents())`, which has no route, so they
follow the selection, as for the key. The place of the route does not change the
rows.

### 3.3 The place: the content of the shell

`_find_shell_content_reference(editor)`, in `WindowChrome.jl`, gives the
reference of the `WidgetShell` from the root, followed by `.content`. It finds the
shell like this:

1. It takes the prefix of the selection that ends at a `WidgetShell`.
2. If no prefix ends at a shell, it takes the only `WidgetShell` in the
   document. The search does not go into the content of a shell.
3. Else it gives `nothing`, and the item does nothing.

This place exists in every window that has the Help menu, with or without panes.
The selection only chooses the shell. It is not the route.

### 3.4 The two items

`make_window_help_menu` and `make_window_menu_bar` get two keywords,
`gesture_help = false` and `command_palette = false`. The shell wrapper sets each
from `haskey(parts.arguments, keyword)`. An item is there only when its wrapper is
on.

The two items come first in the Help menu, before Documents, Projections and
About:

| Item | Tooltip |
| --- | --- |
| Gestures | The gestures that work where the selection is (F1) |
| Command palette | Find a command that works here, and run it (Ctrl+Shift+P) |

The callback of each item:

1. It finds the place with `_find_shell_content_reference`. If there is no
   place, it stops.
2. It calls `read_rooted_operation` with the toggle operation.
3. It posts the answer with `post_operation!`, as `_post_tree_operation!` does.
   It does not post an answer that is `nothing`, `DoNothingOperation`, or the
   toggle operation itself. The editor has no `evaluate_operation` for a toggle
   operation that no decorator took.

In a window, the help window opens during the read, because
`WindowManagingProjection` applies it (2.4). F1 opens it during the read too.

### 3.5 The key on the item (D3)

**The item carries no key, and its tooltip names the key.** The key goes to the
decorator, as it does without the item.

The first recommendation was the other way: the item carries the key, so that
the menu shows it. During S2 I found that a menu item draws only its label. No
code in the widget package draws `action.shortcut`, and no item of the bar shows
a key. So a key on the item shows nothing. It only moves F1 and Ctrl+Shift+P
onto a new path: the shell would take the key first and run the item, the
gesture log would record the key as a menu command, and the help could list F1
twice. Without a key on the item, the path of each key does not change.

### 3.6 The labels (D4)

**My recommendation:** "Gestures", because the window that F1 opens has the
title "Gestures", and "Command palette".

## 4. Decisions

- **D1 (owner, 2026-10-02).** The menu reaches the decorators with a routed
  operation, through `read_rooted_operation`. These approaches were rejected:
  - A synthetic F1 key: it is a fake event.
  - The state of the decorators in the editor: the callback still has no IO map
    to collect the rows, and a projection must not read the state of another.
  - A press that returns the operation from the shell reader: it needs an
    `Action` that carries an operation, which changes the widget model. Every
    other menu item is a callback.
- **D2 (owner, 2026-10-02).** The place is the content of the shell. These places
  were rejected:
  - The selection. A caret can end below the last reader that holds a child, for
    example in a character position or in an introduced step. That reader then
    answers no operation (`ProjectionDefaults.jl:240-241`), and
    `read_routed_child` gives `nothing` back (`ProjectionDefaults.jl:411-412`).
    An empty selection makes no route at all.
  - The focused pane tree. A window can have no pane tree.
- **D3 (2026-10-02, my choice).** The item carries no key, and its tooltip names
  the key; see 3.5. This changed from my first recommendation, because a menu
  item draws no key.
- **D4 (2026-10-02, my recommendation).** The labels are "Gestures" and "Command
  palette"; see 3.6.

## 5. Steps

Do the work in a worktree. Commit each step.

- [x] **S1. The operations and the decorators.** Done on 2026-10-02. The two
  operations, and `_toggle!` in each decorator: the key and the operation call
  it. The tests are in `test_gesture_help()` and
  `test_command_palette_decorator()`. A toggle operation with the route
  `.elements[1]` into a JSON array opens and closes each tool, and the rows are
  the rows of the key. A probe showed that the route `.elements`, which no reader
  holds as a child, carries nothing up. That is the reason of D2. The shell is
  tested in S3, not here.
- [x] **S2. The items.** Done on 2026-10-02. `_post_shell_content_operation!`,
  `_find_shell_content_reference` and `_find_shell_reference` are in
  `WindowChrome.jl`, beside `_post_tree_operation!`. `test_window_shell()` tests
  the items, their order, that they carry no key, and that the tooltip names the
  key. The test that the shell wrapper gives the keywords is in
  `test_window_wrappers()`, not in `test_window_wrap()`, because it needs a whole
  editor with its arguments.
- [x] **S3. The whole window.** Done on 2026-10-02, in `test_window_wrappers()`:
  - A real click on "Help" and then on "Gestures", with pushed pointer events,
    opens the help window, and a second click closes it. This holds with panes
    and without panes (`tabs = false`).
  - The rows of the help from the menu are the rows of F1: 21 rows with the focus
    in a tab, and 5 rows without panes. The click leaves the selection where it
    was. So the context is the content, not the menu.
  - F1 still opens and closes the help when the shell is on.
  - The Command palette item draws what Ctrl+Shift+P draws, and a second use
    draws the closed window again.
  - With panes, the selection finds the shell. Without panes, the selection is
    `nothing`, and the search finds the only shell.
- [x] **S4. The documents.** Done on 2026-10-02:
  - The docstrings of `make_window_help_menu` and `make_window_menu_bar` in
    `WindowChrome.jl`, and of the `shell` wrapper in `WindowShellWrapper.jl`.
  - `documentation/package/platform/shell/shell.md`: the menu bar section says
    how the two items reach their wrappers, and the limits say that a menu item
    draws no key.
  - `documentation/package/platform/gesturehelp/gesturehelp.md`: the two
    operations, and the limit about the menu is gone.
  - `documentation/guide/keyboard-and-mouse-guide.md`: Help > Gestures and
    Help > Command palette.
- [ ] **S5. Close.** Run the narrow tests of S1 to S3 and the layering guard of
  the shell. Move this plan to `plan/done/`.

## 6. Risks

- A press on a menu item can move the selection into the menu window. Then the
  rows are the rows of the menu. S3 tests a real click, and the selection does
  not move.
- The help window opens during a read that runs inside the evaluation of the menu
  command. The split commands also read inside that evaluation, and F1 opens the
  window during a read. The callback posts what remains, so no evaluation runs
  inside another.
