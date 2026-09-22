# The shell fills its window

**Status (2026-09-22): DONE.** Landed on `main`. Nothing is pushed. It found three
regressions of the one-interface plan in omnet-julia's
`test_select_and_paste()`, which this fix did not cause and did not repair; §4
says what they are.

**Goal:** a window drawn inside a `WidgetShell` looks as it did before the shell,
plus its bands. The panes fill the window below the menu bar and the toolbar, the
status line runs along the bottom edge, and every menu of the menu bar is inside
the window.

**Repository:** projectured-julia. Both binaries get the fix, because both draw
their window through the same shell printer. The plan changes no sealed file.

## 1. What is wrong

The owner saw it on 2026-09-22, in a `bin/projectured` window of 1850 × 1150. A
probe of the same window measured it:

| What | Measured |
| --- | --- |
| `size` of the `WidgetShell` | `nothing` |
| "File" of the menu bar | x = 0 |
| "View" of the menu bar | **x = 1862**, past the right edge |
| the Files group and the Assistant group | as wide as their content |
| the status line | not drawn |

**Fault 1 — the shell drops the window's offer.** `WidgetShellToGraphicsCanvas`
gives its content an available size only when the shell has an authored `size`.
Without one it withholds the offer on both axes, so the pane tree takes its own
extent and hugs its content. The window does offer its size: the menu bar gets it.
The status bar is drawn only under an authored `size`, and so is the background.
Both binaries build their shell with `size = nothing`.

`layout-rules.md` §3 says the opposite: a container with no authored size offers
"the space its parent gave", and withholds only when it has neither.

**Fault 2 — a menu bar item takes the whole width.** The menu bar is a horizontal
`WidgetMenu`. It hands its full offer to each item, and an item fills what it is
offered, so "File" is as wide as the window and "View" starts where it ends. A
horizontal container derives its width from its items, so by the same rule it
withholds the width offer, as `WidgetToolbar` already does. An item also fills the
height offer, so a band that passes the window's height makes an item as tall as
the window.

**How it passed.** Step 7 of
[both-binaries-offer-one-interface.md](../done/both-binaries-offer-one-interface.md)
said "give the shell the size of the window", and it was ticked without a
measurement. A comment in `example/projectured/Application.jl` claimed that the
window scene gives the shell its size, which is false. No test asked where the
panes are drawn: the suites asserted what the shell holds.

## 2. Decisions

- **The shell's extent on an axis is its authored size, else its parent's offer.**
  Only a shell with neither takes its content's extent. This is §3 as a viewport
  applies it, and it needs no number: the offer is a cell, so the shell follows
  the window when it resizes.
- **The content is offered the shell's extent less the insets and the bands**, on
  each axis where the shell has an extent.
- **A band is offered the shell's width and no height.** A band is as tall as what
  it holds.
- **The status line sits on the bottom edge when the shell has a height, and under
  the content when it has none**, so a shell that hugs still shows it.
- **A horizontal `WidgetMenu` withholds the width offer from its items.** A
  vertical one is unchanged: a dropdown's items fill its width, which is what
  makes a row's highlight span it.
- **The fold passes no size.** It stays `nothing` in both binaries; the offer is
  the size.
- **This reverses half of commit `2337dad7`, and keeps its purpose.** On
  2026-09-17 a shell with no size offered 0, so a pane in it drew nothing. That
  commit made the shell withhold on both axes, and its test,
  `test_shell_offers_only_its_size`, asserts that a sizeless shell **inside an
  offer of 700 × 500** gives a pane only its label's width. That is the window's
  fault in a small case. The test becomes two: inside an offer the pane takes the
  offer, and with no offer at all it takes its label's width. Neither case offers
  0.
- **`layout-rules.md` §3 names the shell**, beside the scroll pane and the transform
  pane, so the rule states what a shell offers and the next change does not
  reverse it.

## 3. Steps

### Step 0 — baseline

- [x] `test_shell()` **109** and `test_application()` **70** in this worktree.
      `test_substrate()` on `main` at the same commit: **63098 pass, 3 fail,
      2 error, 1 broken**, and all five are the split-pane drag cases known on
      `main`.

**What the work found beyond §1, and fixed in the same step:**

- **A band was placed by one line height, not by the height it draws.** The
  status line drew 18 tall in a slot of 16, so the shell reached 602 in an offer
  of 600; the menu bar and the toolbar stepped the same way, so the content could
  start under the lower edge of a band. Each band is now as tall as it draws, and
  the shell reads that height. A band is offered no height, so its height comes
  from what it holds and reading it closes no cycle.
- **A test's measure must agree with the font.** After that fix the test still
  measured 602. The cause is not the shell: `get_graphics_size` walks into every
  canvas and takes the height of a drawn text from its font's size, 18, while the
  test's measure answered 16 for a line. So each text stood 2 pixels taller than
  the line reserved for it. A real measure answers at least the font's size, so a
  window does not see this; the test's measure now answers the font's size too.
  **A first guess blamed the wrapper canvas** around a band, which sizes what it
  wraps with no measure. That wrapper does report a band wrongly (the menu bar 44
  wide where the menu says 76), but nothing reads a wrapper's stated extent: the
  bounds walk goes past it. A fix for it changed nothing observable and was
  taken back out.

### Step 1 — the shell passes on the offer

- [x] `WidgetShellToGraphicsCanvas` takes each axis from `size` or the offer, gives
      the content and the bands their contexts as §2 says, draws the background
      over the extent it has, and places the status line.
- [x] The tests are in the substrate suite, beside the printer, and not in
      `test_window_shell()`: `test_widget_shell_layout()` in a new
      `WidgetShellTest.jl` asserts where each band and the content are drawn, and
      `test_shell_offers_only_its_size()` became its two cases.

### Step 2 — the menu bar keeps its items inside the window

- [x] A horizontal `WidgetMenu` withholds the width offer from its items.
- [x] A test in `test_widget_menu()`: every item of a horizontal menu is drawn
      right of the one before it, at its natural width, and inside the offer.
- **`test_substrate()` is 63119 pass with the baseline's 3 fail, 2 error and
  1 broken**: the same five split-pane drag cases, and 21 new assertions.

### Step 3 — the application window

- [x] `test_application()`: in a window of 1600 × 1000 "View" is drawn right of
      "File" and inside the window, the files' tab starts past the first fifth of
      the width, and something is drawn in the last band of the window.
      **`test_application()` is 74**: the baseline's 70 and the four new
      assertions. `test_shell()` stays 109.
- [x] Correct the comment in `Application.jl`.
- [x] **A picture**, rendered offscreen at the owner's 1850 × 1150: the panes fill
      the window, the menu bar shows File and View, and the status line runs
      along the bottom. The shell now paints the window's background too, which
      it did only under an authored size.
- **What the picture shows next**: the status line writes the selection as a raw
  reference path, `Files ::UndoBuffer.content::PaneTree.root::…`. Step 7 of the
  one-interface plan wrote it that way on purpose and named
  `ReferenceToHumanReadableText` as the way to say it as a person would. It was
  never drawn until now, so nobody saw it. It is not this plan's.

### Step 4 — close

- [x] Run omnet-julia's suites once this lands, because the interface draws
      through the same printer. `test_ide_window_wrap()` is **25** and
      `test_ide_file_navigator()` **8**, as before. `test_select_and_paste()` is
      **72 pass, 7 fail, 3 error** — see §4.
- [x] Record the correction in the plan of the one interface, and move this plan to
      `plan/done/`.

## 4. What the interface's suite found, and what caused it

`test_select_and_paste()` fails ten assertions. **They are not this fix's.** The
same test, run in one process with the two printers of `f03adc7b` put back — the
shell's and the menu's, exactly what this plan changed — fails the same ten:
72 pass, 7 fail, 3 error, case for case.

They are regressions of the one-interface plan, which never ran this suite after
its Step 7:

- **The clipboard does not see the focus through the shell** (two cases, six
  assertions). After `focus_pane!`, `_get_clipboard_selection` answers `nothing`:
  it looks for the pane tree's focus directly under the clipboard slice, and a
  `WidgetShell` now sits between them. So Ctrl+C on a focused tab copies nothing.
- **The window draws two texts "Run"** (one case, four assertions). The toolbar's
  Run of the interface is drawn before the runner's own button, so an Alt+click
  found by that text lands in the toolbar, outside the pane tree, and the tree's
  selection stays empty. A person sees the same two words.

Both are left to the owner: the first is a fault of the clipboard slice, the
second a question of what the toolbar's button is called or how a test finds the
runner's.
