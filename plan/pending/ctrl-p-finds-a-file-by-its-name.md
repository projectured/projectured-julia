# Ctrl+P finds a file by its name

> **Status (2026-11-03):** pending, not approved. The owner answered Q1 to Q11.
> No step is started. The second plan,
> [every-popup-window-is-placed-by-a-function.md](every-popup-window-is-placed-by-a-function.md),
> starts after this one.

## The goal

Ctrl+P opens a list of the files of the folders of the Explorer. A person types a
part of a name, the list narrows, and Return opens the chosen file in a tab.
Ctrl+O opens the Open dialog, and F5 reloads a file from the disk. The command
palette (Ctrl+Shift+P) opens in the same kind of list, at the same place.

An example. The Explorer shows the folder `projectured-julia`, and the focus is
on `a.json`:

```
┌──────────────────────────────────────────────────────────────┐
│ File  View  Help                                             │
│      ┌──────────────────────────────────────────────────┐    │
│      │ Go to file: panprog▏                             │    │
│      │ › PaneProgram.jl          source/platform/pane   │    │
│      │   PaneProgramTest.jl      test/platform/pane     │    │
│      └──────────────────────────────────────────────────┘    │
│ Explorer │ a.json*                                           │
│          │ { "items": … }                                    │
└──────────────────────────────────────────────────────────────┘
```

Return opens `PaneProgram.jl` in a new tab beside `a.json`, and the tab takes the
focus.

## The questions and the answers

All answers are from the owner, 2026-11-03.

- **The key and its owner.** Ctrl+P belongs to the window, as a command of the
  File menu. The window frame fires a menu shortcut before a tab reads the key
  (`read_intent` of `WidgetShellToGraphicsCanvas`), so the key works wherever the
  focus is. A key in the table of the Explorer works only in the Explorer. A key
  in the table of `PaneTree` is read last, so a tab that binds Ctrl+P blocks it.
- **Q1. What does Ctrl+P show?** A search of the files by name, as in VS Code,
  and not the Open dialog. Ctrl+O opens the Open dialog. The reload of a file
  gets another key.
- **Q2. The key of the reload.** F5. The data frame view uses F5 for "read the
  frame again", which is the same idea, and it reads the key first.
- **Q3. Which files?** The files below the folders of the Explorer. The search
  skips each folder whose name starts with a dot, and each file and folder that
  a `.gitignore` names. The editor reads `.gitignore` with its own code, so the
  search works with no git and outside a repository. The Explorer does not
  change and shows every file. In this repository the rule lists 2,997 files of
  8,216; most of the others are the build output in `build/projectured`.
- **Q4. How does a query match?** The letters of the query come in the same
  order in the path, and they need not touch. Case does not matter. `panprog`
  finds `PaneProgram.jl`. The order of the list:
  1. a match at the start of a word ranks higher; a capital letter, `/`, `_`,
     `-` and `.` start a word;
  2. a match in the file name ranks higher than a match in the folder;
  3. of equal matches, the shorter path comes first.
- **Q5. What shows before a person types?** The open files, then all other
  files in path order. The editor keeps no record of the files opened before.
- **Q6. Where does the search appear?** In a window of its own, as the
  architecture rule `PAR-MANY-WINDOWS` asks of every popup.
- **Q7. The two faults of the group choice.** This plan fixes both (D9).
- **Q8. The command palette.** It moves from an overlay inside the window to the
  same popup list as the file search. A row shows the command and its key at the
  right edge. The domain headings go, and the query still matches the domain
  name. A command that can not run now is not in the list; F1 still shows every
  command. The palette uses the letters-in-order rule too.
- **Q9. Where do the lists open?** At the top center of the main window, below
  the toolbar. The width is a share of the width of the window, with a minimum,
  so it does not change while a person types. The height follows the rows up to
  a maximum, and a longer list scrolls.
- **Q10. When is the list of files read?** The editor keeps the list that it
  read last, and each Ctrl+P shows it at once and reads the folders again on a
  background task. A new file appears when that read ends. At the first Ctrl+P of
  a session, the list says "Reading the files…". A read stops at 100,000 files,
  and the list says so.
- **Q11. The place of a popup.** A popup carries a placement function. The
  function can read the whole state of the screen: every window, its position
  and its size, the size of the content, the point, and the printed box of any
  part. The window follows each change of what the function reads. A new place
  is a new function and needs no change of the window code. In this plan only
  the context menu window uses it; the second plan moves the other popups.
- **The rows are a lazy list.** The owner asked for it. The list builds a row
  only when the view draws it.

The owner also said that my note "a projection must not read the output of
another projection" was too limiting here. That note is about one wrapper that
reads the state or the output of a different wrapper. `ScreenToScreen` prints
every window, so it places one window from the box of a part in another window
from its own output.

## The design

**D1. The keys.**

- The File menu (`make_window_file_menu`) gets two commands with shortcuts:
  "Open file…" (Ctrl+O), which calls `open_file_dialog!`, and "Go to file…"
  (Ctrl+P), which calls the new verb `open_file_search!(; editor)`. The rule of
  `WindowChrome.jl` holds: each item does its work.
- The rule of `FileDocument` (`DocumentFile.jl:471`) changes from
  `KeyDown(:o; ctrl)` to `KeyDown(:f5)`. So does the answer of the page
  (`LoadFilePageOperation`). No other code in projectured-julia or omnet-julia
  binds Ctrl+O, Ctrl+P or F5, except the F5 of the data frame view.
- The Open dialog starts in the folder of the file of the focused tab, else in
  the first folder of the Explorer, else in the current folder. This is my
  choice; the owner did not answer it.

**D2. A popup window is placed by a function (Q11).**

- `WindowDocument` and `OpenWindowOperation` get the field `placement`. Its
  default is `nothing`, and then the window keeps its `x` and `y` as now.
- A placement is a function of a `WindowPlacementContext`, and it answers a
  `WindowPlace`: `x`, `y`, `minimum_size` and `maximum_size`. A width that must
  not change gets the same minimum and maximum width. The context gives the
  windows of the output screen with their positions and sizes, the window that
  is placed, the size that its content printed, the point of the gesture or
  `nothing`, and `find_window_part_box(context, reference)`, the box of a part
  in screen coordinates.
- `ScreenToScreen` calls the placement in a computation over its own output and
  writes the answer into the output window. The backend reads the output screen
  as now. So the window follows a resize of the main window and a scroll that
  moves its part.
- The screen slice gives three ready-made placements:
  `make_point_placement(point)`, `make_part_placement(reference; gap)`, which
  is below the part, and `make_window_top_placement(reference; width_share,
  minimum_width, maximum_height)`, which is at the top center of the window of
  the part.
- Step 1 checks two facts before the rest depends on them: that a field of an
  output window can hold a computed value, and whether a native move of the main
  window writes its `x` and `y`. If it does not, a popup follows a resize but not
  a move, and that is a limit.

**D3. The context menu window takes a placement.** `OpenContextMenuOperation`
gets the field `placement`. Its default gives the behavior of now: at the point,
else below the part. `make_choice_list_operation(title, list; point,
placement)` passes it on. A right click opens exactly where it opens now.

**D4. The rows of a `WidgetChoiceList` are a lazy list.** `find(query)` answers
the choices in rank order as an `AbstractVector`. The view makes its rows with
`make_index_list`, so it builds a row only when it draws it, as the tree and the
table do. The rows sit in a pane with the maximum height of D2. Up and Down move
`row`, and the pane keeps that row in view. The mouse wheel scrolls the rows. A
list of 10,000 choices builds about as many rows as it shows. The navigator uses
the same list, so its suite is the check that nothing else changed.

**D5. One match rule.** `find_letter_match(query, text; name_start)` answers a
`LetterMatch`, with a score and the places of the matched letters, or `nothing`.
`name_start` is the index where the name part of `text` starts, after the last
`/` for a path, and after the description for a command. The score follows the
order of Q4. The function is in the widget slice, beside the choice list, so the
file search and the palette both use it. A query that grows by a letter can
only lose matches, so a search can score only the matches of the query before
it. Step 4 measures the cost at 100,000 paths. If a keystroke takes longer than
one frame, the match moves to a background task, and the list shows the matches
before it until the task ends.

**D6. The list of files.** The filesystem slice keeps a session document of the
editor, `WorkspaceFileList`: the folders, the paths that the last read found,
the state of the read, and whether the read stopped at the limit. It belongs to
the editor and is no module constant. Its folders are the folders of the
`Workspace` entries of the content of the Explorer
(`get_session_explorer_content`). The shell gives them to the slice, because the
filesystem slice does not depend on the explorer slice.

- `open_file_search!` starts a read of the folders on a background task and
  opens the list at once with the paths that the document holds. A print never
  reads the disk.
- A row shows the file name as its label, and the folder as its note, relative
  to its Explorer folder. When the Explorer has more than one folder, the note
  starts with the name of the folder.
- An empty query shows the open files (`OpenFileList`) first, then the other
  files in path order (Q5).
- A choice answers `OpenFileOperation(path)`, so the file opens as a file opens
  from the Explorer: a file that is open already only takes the focus.

**D7. The editor reads `.gitignore` itself.** The rules of git: `#`, `!`, `\`, a
`/` at the start or in the middle, a `/` at the end, `*`, `?`, `[…]` and `**`.
The file of each folder applies to the folder and below it, a later rule wins,
and the read does not enter an ignored folder. The read skips each folder whose
name starts with a dot. It does not read `.git/info/exclude` or the global file
of git.

**D8. The palette is a popup list.** The decorator collects the rows as now. At
Ctrl+Shift+P it answers `make_choice_list_operation` with the top placement of
D2. A row is a `WidgetChoice`: the description as the label, and the key as the
note. Only a row whose operation is not `nothing` is in the list. The match of
D5 reads the description as the name and the domain after it. The choice of a
row answers the operation of the row, and the context menu window lifts it from
the place of the decorator through the readers above it, as a key would. These
go: the overlay canvas and its step `elements[1]`, `CommandPaletteToSyntax`, and
the parts of the palette in `GestureHelpTheme`. Two changes of behavior:

- A key that the list does not answer goes to the window under the list. Now the
  overlay takes every key.
- Ctrl+Shift+P while the list is open opens it again with an empty query, and
  Escape closes it. The decorator does not read the state of the context menu
  window, because that is the state of a different wrapper.

**D9. The group of a new file (Q7).**

- `get_pane_file_group` takes the focused group first among the groups that
  hold a file. Now it takes the first in the order of the tree.
- The pane slice gets the predicate `avoids_new_panes(document)`, `false` by
  default, and `Assistant` answers `true`. The default `pane_group_to_avoid(tree)`
  answers the first group that holds a tab whose content avoids new panes. So no
  file opens over the conversation in projectured-julia. omnet-julia has its own
  method of `pane_group_to_avoid(::PaneTree)` with the same rule. It is more
  specific than the default, so it overwrites nothing and keeps working. A
  change in omnet-julia can delete it after this plan lands.

## The steps

1. **The placement (D2)** in the screen slice: the field, the context, the three
   placements, and the computation in `ScreenToScreen`, after the two checks of
   D2. Tests in the screen tests: a window with the top placement follows a
   resize of the main window; a window below a part follows a scroll of the
   part; a window with no placement keeps its `x` and `y`.
2. **The context menu window (D3).** Test: `test_context_menu_window()` passes
   with no change, and a choice list with the top placement opens at the top
   center and keeps its width while the query changes.
3. **The lazy rows (D4).** Tests: a list of 10,000 choices builds only the rows
   that it shows; Down past the last shown row scrolls; the wheel scrolls. The
   navigator suite passes.
4. **The match (D5).** Tests: the examples of Q4, case, the three rules of the
   order, and the cost at 100,000 paths.
5. **The palette (D8).** Tests: the palette tests of `WindowShellTest.jl`,
   `WindowWrapTest.jl`, `WindowWrappersTest.jl`, `HelpThemeTest.jl` and
   `GalleryWrapperTest.jl`, changed to the popup: Ctrl+Shift+P opens the list at
   the top, a query narrows it, Return runs the row and Ctrl+Z takes it back,
   Escape closes it.
6. **The list of files (D6, D7).** Tests on a fixture folder: a `.gitignore` in
   the root and in a subfolder, a negation, a folder rule, `**`, a dot folder,
   and the limit with a small limit value. The read runs on a task and the print
   reads no disk.
7. **The keys (D1).** Tests in `test_window_wrappers()`, through a real editor:
   Ctrl+P, a query and Return open the file in a tab with the focus; Ctrl+P on an
   open file focuses its tab; Ctrl+O opens the Open dialog; F5 reloads a file;
   Ctrl+O does not reload.
8. **The group (D9).** Tests in `test_pane_surgery()` and `test_application()`:
   after a split, the file goes to the focused group of files; with the focus in
   the Assistant, the file goes beside the Explorer.
9. **The documents.** `screen.md`, `popup-window.md`, `context-menu.md`,
   `widget.md`, `gesturehelp.md`, `shell.md`, `pane.md`, `filesystem.md`,
   `fileformat.md`, `keyboard-and-mouse-guide.md`, `gestures-guide.md`, and the
   help text in `Application.jl`. The naming guard and the layering guards of the
   slices that changed.
10. **A pixel check** with the offscreen SDL driver, as in
    [maximize-a-pane.md](../done/maximize-a-pane.md): Ctrl+P shows the list at
    the top center; a query narrows it; Return opens the file; Ctrl+Shift+P
    shows the palette at the same place.

## Limits

- No record of recent files (Q5).
- The `.gitignore` read does not read `.git/info/exclude` or the global file of
  git (D7).
- A file that is made after the last read appears only when the next read ends
  (Q10).

## Open items

- The new names (`open_file_search!`, `WorkspaceFileList`,
  `WindowPlacementContext`, `WindowPlace`, `find_letter_match`,
  `avoids_new_panes` and the three placements) are proposals. The naming guard
  checks them in each step.
- The method `pane_group_to_avoid(::PaneTree)` of omnet-julia becomes redundant
  (D9). It is deleted only with the approval of the owner, in omnet-julia.
