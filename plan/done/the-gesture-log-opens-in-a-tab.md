# The gesture log opens in a tab

**Status (2026-09-22): IN PROGRESS.**

**Goal:** a person reads the gesture log in a tab of the window, which they open
from the menu. The `--gesture-log` switch of both binaries goes, and so does the
corner panel it turned on.

**Repositories:** projectured-julia and omnet-julia. The plan changes no sealed
file.

## 1. Why

The owner asked on 2026-09-22 whether `bin/projectured` needs `--gesture-log`,
now that a tab can show the log and a tab will later detach into a window that
stays on top. It does not:

- **The switch changes nothing about what is recorded.** The recorder of
  `make_window_wrap` is always on, and it writes into the one session log. The
  switch only adds a panel in a corner.
- **A tab shows the same log, and more of it.** A person who types `gestures`
  into an empty tab gets `get_session_gesture_log()`, which already holds what
  happened before the tab opened. So a person opens it after a fault; with the
  switch they must know before the binary starts.
- **The panel is not a document.** `GestureLogOverlayProjection` draws it, so
  nobody can select it, reference it, filter it or move it. That is the argument
  that put the shell into the document.
- **A detached tab is the panel, done correctly**, and `PAR-MANY-WINDOWS` already
  gives it a floating window style that stays on top.

## 2. Decisions

- **View → Gesture log** is the new way to reach the log. It opens the session log
  in a tab, or gives the focus to the tab that already holds it, so a second press
  never shows the same log twice. It carries no shortcut: a menu shortcut fires
  before the focused widget sees the key, and there is no key this needs.
- **The panel stays for `run_example`.** An example window holds one document and
  has no pane tree, so it cannot open a tab, and there the panel is the only way to
  see the log. The gallery composes the panel itself and does not need the fold.
- **Both binaries lose the switch**, so the two interfaces stay one.
- **The fold loses its `gesture_log` keyword**, because no binary passes it. It is
  removed last, after omnet-julia stops passing it, so no `main` is ever broken.

## 3. Steps

### Step 0 — baselines

- [x] projectured-julia: `test_shell()` **108**, `test_application()` **63**.
- [x] omnet-julia: `test_ide_window_wrap()` **25**, measured when the last plan
      landed.

### Step 1 — View → Gesture log

- [x] Add the item to `make_window_menu_bar`, with a callback that opens the
      session log in a tab or focuses the tab that holds it. It finds the tab by
      `get_wrapped_document`, so a tab that holds the log inside a history still
      counts. It carries a tooltip and no shortcut.
- [x] `test_window_shell()`: the item opens a tab that holds the session log, and
      a second press opens no second tab and gives that tab the focus.
      **`test_shell()` is 111.**
- [x] `test_application()`: the window draws no "Gestures" before the press and
      draws it after.

### Step 2 — the application loses `--gesture-log`

- [x] `parse_application_arguments`, the usage line, `make_application_window`,
      `run_application`, the rows of `ApplicationTest.jl` and the README line.
      The suite now asserts that the parser refuses `--gesture-log`, and the
      README names View → Gesture log instead. **`test_application()` is 67**:
      63, one less for the flag the usage no longer lists, one more for the
      refusal, and four for the new case.

### Step 3 — the interface loses `--gesture-log`

- [ ] omnet-julia, after Steps 1 and 2 land: the switch in
      `source/build/Program.jl`, the keyword of `make_ide_window_wrap` and
      `run_omnet_ide`, the precompile workload, the test and the guide.

### Step 4 — the fold loses `gesture_log`

- [ ] projectured-julia, after Step 3 lands: the keyword of `make_window_wrap`,
      its tests and the shell guide.

### Step 5 — close

- [ ] Update the memory of the interface's window, and move this plan to
      `plan/done/`.
