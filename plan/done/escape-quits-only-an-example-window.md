# Escape quits only an example window

Status: DONE, 2026-10-22, on the branch `escape-quit`, in the worktree
`projectured-julia-escape-quit`. Not landed on `main`.

## The ask

The owner, 2026-10-22: "in the projectured binary and the omnet IDE, ESC key
should not exit from the application, it should have a File/Exit menu item with
a typical key shortcut. in the repl, when examples are run using run_example,
exiting using ESC is desirable." To the design below, and to the question whether
the other windows can lose the Escape quit, the owner answered: "agreed, plan and
implement".

## The problem

1. **The kernel quits on Escape.** `run_read_stage!`
   (`source/kernel/editor/ReadEvaluatePrint.jl`) answers `QuitEditorOperation`
   for a bare Escape that no reader took. This is the one gesture that the
   editor recognizes itself, and every window has it: the ProjecturEd binary
   (`run_application`), the IDE of omnet-julia (`make_ide_wrappers`), and the
   windows of `run_example`.
2. **No menu item quits.** The File menu of `make_window_menu_bar`
   (`source/platform/shell/WindowChrome.jl`) holds "New tab" and "Close tab".
   Both binaries get their menu bar from the `shell` wrapper.

## The model

- **The kernel recognizes no Escape quit.** `run_read_stage!` keeps one rule for
  a bare Escape that no reader took: it leaves the safe mode. The safe mode puts
  the projection aside, so no wrapper is there to answer the key.
- **A projection quits on Escape.** `EscapeQuittingProjection(; inner)` in the
  screen slice wraps a projection and has the same input. Its reader asks
  `inner` first. When `inner` gives no operation and the gesture is a bare
  Escape, alone or in a `WindowInput`, it answers `QuitEditorOperation()`. It
  must be the outermost reader, so that a popup, a tooltip, a dialog, a drag and
  the palette take Escape first.
- **The wrapper `quit_on_escape` of `build_editor`** puts the projection around
  everything, in the layer `:screen` with the number 100. It is off by default.
  Neither binary turns it on.
- **The examples turn it on.** `_make_window_scene_editor`
  (`example/projectured/Gallery.jl`) wraps its projection. It is the start of
  `run_example`, `make_example_editor`, `run_file_editor` and the value viewer.
  `run_console_example` wraps its projection too.
- **File > Exit, Ctrl+Q.** `make_window_file_menu` adds a separator and "Exit"
  with `Shortcut(:q; ctrl = true)`. Its callback posts `QuitEditorOperation()`.
  The shell fires a menu shortcut before the focused widget sees the key, so
  Ctrl+Q works wherever the focus is. No other code binds Ctrl+Q. Both binaries
  get the item through the `shell` wrapper, so omnet-julia does not change.

## Steps

Do the work in this worktree. Commit each step. Do not land on `main` before the
owner approves.

1. [x] **The Escape quit moves to a projection.** Done; see [As built](#as-built). The kernel rule, the projection
   and its wrapper, the wrap in the examples, and the tests: the kernel test
   `EscapeQuitTest.jl` keeps what the kernel still does, a new platform test
   `test/platform/shell/EscapeQuittingTest.jl` tests the projection and the
   wrapper, and the console test wraps its projection. Run the kernel editor
   tests, the shell tests, the safe mode test and the console test. Commit.
2. [x] **File > Exit.** Done; see [As built](#as-built). The item, and the tests that list the File menu:
   `WindowShellTest.jl` and `ApplicationTest.jl`. Run them. Commit.
3. [x] **The guides.** Done; see [As built](#as-built). Every guide that says that Escape quits: `editor.md`,
   `operation.md`, `devices-and-backends.md`, `screen.md`, `shell.md`,
   `console.md`, `keyboard-and-mouse-guide.md`, `setup-guide.md` and
   `debugging-guide.md`. The plan moves to `plan/done/`. Commit.

## As built

- **Step 1.** `run_read_stage!` answers `QuitEditorOperation` only for a
  `WindowQuit`. A bare Escape that no reader took leaves the safe mode, through
  `_is_bare_escape` of `EditorModule`; otherwise it is consumed. The screen
  slice already had `_is_bare_escape(event)` in `WindowManaging.jl`, so
  `EscapeQuitting.jl` uses it on the event of a `WindowInput`; a second method
  in the same module failed the naming guard. `EscapeQuittingProjection` follows
  `FocusCyclingProjection`: the IoMap has the same input as the child, so it
  needs no `get_child_iomaps`, and a route goes to `inner` with the change. The
  kernel test is `WindowQuitTest.jl` (`test_window_quit`); the platform test is
  `test/platform/shell/EscapeQuittingTest.jl` (`test_escape_quitting`). The
  fixture of `ContextMenuWindowTest.jl` wraps its projection, so its check that
  a popup takes the Escape is a real claim. `GalleryWrapperTest.jl` checks that
  an Escape closes a menu of an example window, and that a second Escape quits.
- **Step 2.** The Exit callback evaluates `QuitEditorOperation()` at once. Its
  `QuitEditorException` is no fault, so no barrier takes it, and the loop stops
  as for the close button. `WindowShellTest.jl` presses Ctrl+Q in a headless
  shell window and reads the `InvokeActionOperation` of Exit. The shortcut walk
  of the shell skips a `WidgetSeparator`, and the label helpers of the tests skip
  it too.
- **Step 3.** Eight guides change: `editor.md`, `operation.md`,
  `devices-and-backends.md`, `screen.md` (a new section, "Quitting on Escape"),
  `shell.md`, `console.md`, `keyboard-and-mouse-guide.md` (a row for Ctrl+Q)
  and `debugging-guide.md`. `setup-guide.md` stays: its "Press Escape to close
  the window" follows `run_example` and `run_value_viewer`, which quit on Escape.
  The guides name only the ProjecturEd application, not the IDE.
- **Tests.** In `environment/all`: `test_window_quit`, `test_escape_quitting`,
  `test_window_shell`, `test_context_menu_window`, `test_tracking_screen`,
  `test_fault_safe_mode`, `test_gesture_tracking`, `test_shell_completeness`,
  `test_console_backend` and `test_tooltip_window` pass, 509 of 509.
  `test_gallery_wrappers` and `test_application` pass, 405 of 407; the 2 broken
  are the two `@test_broken` marks that `ApplicationTest.jl` has on `main`.

## Not in this plan

The F1 help does not list the Escape quit: it collects the rows inside its own
decorator, and the Escape wrapper must be outside every reader. The window of
the REPL `display` (`EditorDisplay.jl`) does not quit on Escape.
