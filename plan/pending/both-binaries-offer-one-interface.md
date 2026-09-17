# Both binaries offer one interface

**Status (2026-09-17): NOT STARTED.** This plan is written and waits for the
owner. Four questions in §3.13 are open; every other decision is made.

**Goal:** `projectured` and `omnet_ide` offer the same interface. A person who
learns one knows the other. Every layer is built once, in projectured-julia, and
each binary turns the layers on that it wants.

**Repositories:** projectured-julia (the shell package, the widget tooltip, the
declared verbs) and omnet-julia (the interface calls the shell package, and
gains the file navigator). The plan changes no sealed file.

**Process:** work in a sibling git worktree in `workspace/`. Commit each step
with explicit paths. Mark each part done here, and write down each decision that
the work makes.

## 1. The request and the rulings

> create a list of what's missing from the projectured binary user interface in
> projectured-julia compared to the omnet_ide binary user interface in
> omnet-julia

> All of it should be added, preferably in a reusable way. Tooltips should be
> added to widgets and tooltip support to the UI. Tooltips should use a
> functional api and fallback to fields for widgets.
>
> Instead of background colour a shell widget would be better with menu and
> context menu, toolbar and status line.
>
> File navigator should be available in the IDE too.

The rulings of the owner, 2026-09-17:

| Question | Ruling |
| --- | --- |
| How much of the comparison is added? | All of it. |
| How is it added? | In a reusable way. One layer, built once, used by both. |
| Where does a tooltip live? | On the widget, and the interface supports it. |
| How does a widget say its tooltip? | A function answers it. A field on the widget is the fallback. |
| The window background colour | Drop it. A shell widget takes its place. |
| What does the shell hold? | A menu, a context menu, a toolbar and a status line. |
| The file navigator | It works in the interface too, not only in the application. |

## 2. What exists

The gap is small because most of the parts are already written. Each row is a
fact this plan stands on.

### 2.1 The two windows today

| Fact | Where |
| --- | --- |
| The interface folds five layers over its window: gesture help, command palette, gesture log, selection walk and clipboard | omnet-julia `source/ide/IdeWindow.jl:171` |
| The application folds two: gesture help and command palette | [example/projectured/Application.jl:169](../../example/projectured/Application.jl#L169) |
| Both draw the same pane gesture table | [source/pane/PaneGestures.jl:152](../../source/pane/PaneGestures.jl#L152) |
| The interface declares its verbs; the application declares none | omnet-julia `source/campaign/CampaignWindow.jl:191` |
| `declare_api!` has no caller in `source/` or `example/` of this repository | [source/kernel/tool/ToolSet.jl:38](../../source/kernel/tool/ToolSet.jl#L38) |
| An empty declaration makes `search_api` index the 23 submodules of `ProjecturedKernel`, and nothing else | [source/kernel/tool/Documentation.jl:826](../../source/kernel/tool/Documentation.jl#L826) |
| `execute_julia_code` meanwhile re-exports the whole `Projectured` umbrella | [source/kernel/tool/CodeExecution.jl:60](../../source/kernel/tool/CodeExecution.jl#L60) |
| `make_pane_api` and `make_interface_api` already declare the pane and widget verbs; only a test calls them | [source/pane/PaneProgram.jl:93](../../source/pane/PaneProgram.jl#L93) |
| The interface paints its windows one colour at start | omnet-julia `source/campaign/CampaignWindow.jl:93` |
| The interface has four callers of its fold, so the move costs little | omnet-julia `source/ide/IdeWindow.jl`, `IdePrecompile.jl:146`, `test/ide/IdeWindowWrapTest.jl:20` |

### 2.2 The chrome widgets all exist, and all draw

`WidgetShell` already holds every part the owner asked for.

| Widget | Definition | Drawn by |
| --- | --- | --- |
| `WidgetShell` — `content`, `menu_bar`, `toolbar`, `status_bar`, `tooltip`, `context_menu` | [source/widget/WidgetDocument.jl:1001](../../source/widget/WidgetDocument.jl#L1001) | [source/widget/WidgetToGraphics.jl:2063](../../source/widget/WidgetToGraphics.jl#L2063) |
| `WidgetMenu` | [source/widget/WidgetDocument.jl:629](../../source/widget/WidgetDocument.jl#L629) | WidgetToGraphics.jl:1807 |
| `WidgetMenuItem` — carries an `Action` and per-instance gestures | [source/widget/WidgetDocument.jl:679](../../source/widget/WidgetDocument.jl#L679) | WidgetToGraphics.jl:1682 |
| `WidgetToolbar` | [source/widget/WidgetDocument.jl:776](../../source/widget/WidgetDocument.jl#L776) | WidgetToGraphics.jl:3940 |
| `WidgetStatusBar` — non-interactive by design | [source/widget/WidgetDocument.jl:964](../../source/widget/WidgetDocument.jl#L964) | WidgetToGraphics.jl:4000 |
| `WidgetContextMenu` — a wrapper that opens `menu` on a right press | [source/widget/WidgetDocument.jl:514](../../source/widget/WidgetDocument.jl#L514) | WidgetToGraphics.jl:1423 |
| `WidgetTooltip` — a floating overlay | [source/widget/WidgetDocument.jl:471](../../source/widget/WidgetDocument.jl#L471) | drawn as a band of the shell |
| `WidgetDialog` — a modal | [source/widget/WidgetDocument.jl:559](../../source/widget/WidgetDocument.jl#L559) | WidgetToGraphics.jl |

Three facts follow.

1. **`WidgetShell.context_menu` is a dead field.** Nothing reads it — not the
   printer, not `_shell_field`, not the reader. A caller that sets it sees
   nothing.
2. **No binary uses `WidgetShell`.** The only caller is the gallery, through
   `make_shell_document` and `make_shell_projection` in
   [example/workbench/WrapperDocumentExample.jl:31](../../example/workbench/WrapperDocumentExample.jl#L31)
   and
   [example/workbench/WrapperProjectionExample.jl:25](../../example/workbench/WrapperProjectionExample.jl#L25).
3. **No widget carries a tooltip.** `WidgetShell.tooltip` is one overlay for the
   whole window, not an attachment on a widget. No generic function reads a
   tooltip from a widget.

### 2.3 The tooltip machinery

| Fact | Where |
| --- | --- |
| `TooltipDecoratorProjection` already takes a `trigger::Function` and a `position::Function` | [source/tooltip/TooltipDecorator.jl:45](../../source/tooltip/TooltipDecorator.jl#L45) |
| It needs a `TooltipSource` node in the document, so it decorates one node at a time | [source/tooltip/TooltipDocument.jl:4](../../source/tooltip/TooltipDocument.jl#L4) |
| It opens a second native window through `OpenWindowOperation` and the `:tooltip` style | [source/tooltip/TooltipDecorator.jl:91](../../source/tooltip/TooltipDecorator.jl#L91) |
| The SDL `:tooltip` flags set no no-input-focus flag, so a tooltip steals the focus | [source/sdl/Sdl.jl:424](../../source/sdl/Sdl.jl#L424) |
| `screen_origin` does not exist, so a tooltip cannot be placed in screen coordinates | grep answers nothing |
| `default_tooltip_position` answers a fixed corner | [source/tooltip/TooltipDecorator.jl:53](../../source/tooltip/TooltipDecorator.jl#L53) |
| The web backend opens a second window as a browser popup, and a browser needs a click first, so a hover tooltip never appears there | [asset/web/client.js:164](../../asset/web/client.js#L164) |
| `WidgetHoverTrackingProjection` knows which widget the pointer is over, but only for a widget that answers `MouseEnter` | [source/widget/WidgetHoverTracking.jl:144](../../source/widget/WidgetHoverTracking.jl#L144) |
| `HoverProbeProjection` shows how to reverse-project the pointer without a click | [source/inspector/HoverProbe.jl:32](../../source/inspector/HoverProbe.jl#L32) |
| An Alt+left press answers the innermost widget under the pointer, for every drawn widget, and never fires an action | [source/focus/WholeSelection.jl:51](../../source/focus/WholeSelection.jl#L51) |

### 2.4 The navigator and the closure of the interface

| Fact | Where |
| --- | --- |
| The navigator needs a closure of 23 packages | `ProjecturedWorkbench`, `ProjecturedFileSystem`, `ProjecturedFileFormat` and their dependencies |
| Of those, only `ProjecturedWorkbench` and `ProjecturedFileSystem` are new to `OmnetIde` | omnet-julia `package/OmnetIde/Project.toml` |
| A document format is opt-in and registers itself, so the interface opens only the formats its closure holds: Julia, Markdown and Math today | [source/fileformat/NaturalFormat.jl:15](../../source/fileformat/NaturalFormat.jl#L15) |
| The campaign window forbids `ProjecturedFileFormat` and `ProjecturedSyntax`, so the navigator must not go there | omnet-julia `test/legacy/runner/CampaignUiClosureTest.jl:37` |
| A `WorkbenchEditor` and a `WorkbenchNavigator` sit in a plain `PaneTab` when the host adds two dispatch entries | [example/projectured/Application.jl:188](../../example/projectured/Application.jl#L188) |
| omnet-julia reads and writes no file through `ProjecturedFileFormat` today | grep answers nothing |

**Two closure tests already fail on a clean omnet-julia `main`.** `IdeClosureTest`
asserts 42 and the closure is 43. `CampaignUiClosureTest` asserts 22 and the
closure is 25, and `ProjecturedSerialization` is present although the guard
forbids it. Step 0 records this, so that a step of this plan is not blamed for
it and does not hide behind it.

### 2.5 No popup opens in either binary

`WidgetPopupResolverProjection`
([source/widget/WidgetPopupResolver.jl:18](../../source/widget/WidgetPopupResolver.jl#L18))
turns the anchor-relative `OpenPopupOperation` that a trigger emits into an
absolute `OpenWindowOperation`, which `WindowManagingProjection` opens. A host
must compose it at the root of the window's content.

**No binary composes it.** The only callers are one example and three tests.
So today, in both binaries:

- a `WidgetSelect` does not drop down;
- a `WidgetMenu` submenu does not open;
- a `WidgetContextMenu` draws its child and swallows the right press.

The gallery says so in a comment: the commands of its shell are inert because no
popup resolver is composed there
([example/workbench/WrapperDocumentExample.jl:26](../../example/workbench/WrapperDocumentExample.jl#L26)).

One line in the fold fixes all three at once, in both binaries. That is the
cheapest item in this plan and it is the reason the chrome looks unfinished.

### 2.6 Two facts that shape the shell

- **A `WidgetShell` with no size hugs its content.** `test_shell_offers_only_its_size`
  ([test/substrate/projection/WidgetTableTest.jl:171](../../test/substrate/projection/WidgetTableTest.jl#L171))
  asserts it. A window shell must fill the window instead, so the fold must say
  what size it is.
- **A `WidgetTooltip` takes a position, a size and a content**
  ([source/widget/WidgetDocument.jl:471](../../source/widget/WidgetDocument.jl#L471)).
  So the tooltip layer computes where and how large, and puts the content that
  the tooltip function answered inside.

## 3. Decisions

### 3.1 One package holds the shell of a window

A new package `ProjecturedShell`, whose slice folder is `source/shell/`. It
holds what sits between a window and the document in it:

- `make_window_shell(...)` — the fold `(document, projection) -> (document,
  projection)` that stacks the layers. It is the function that
  `make_ide_window_wrap` is today, moved down and made general.
- `make_shell_opened_window_projections(...)` — what a window that a layer opens
  draws with.
- The shell document: a `WidgetShell` around the content of the window, with a
  menu bar, a toolbar, a status line and a context menu.
- The tooltip layer, which finds the widget under the pointer.
- `WidgetPopupResolverProjection` at the root of the window's content, so that
  every popup a widget asks for actually opens (§2.5).

Every package it depends on — `ProjecturedGestureHelp`, `ProjecturedGestureLog`,
`ProjecturedClipboard`, `ProjecturedFocus`, `ProjecturedTooltip`,
`ProjecturedWidget`, `ProjecturedPane` — carries no third-party dependency, so
`ProjecturedShell` is a sub-stem and the `Projectured` umbrella aggregates it.

`make_shell_document` and `make_shell_projection` move out of
`example/workbench/` into this package. The gallery keeps calling them.

**Why a package and not a function in each binary.** Each binary composes the
layers by hand today, and the two lists drifted apart. One function that takes a
keyword per layer cannot drift: a layer that the application turns on is the
same code the interface turns on.

### 3.2 The window draws the tooltip; a second window does not

`WidgetShell` already draws a `WidgetTooltip` band. The tooltip goes there.

The reason is that the second-window path is not finishable cheaply and is not
wanted on the web:

- SDL sets no no-input-focus flag, so a tooltip window takes the focus from the
  window under it. The fix is platform work across X11, Wayland, macOS and
  Windows.
- `screen_origin` does not exist, so a tooltip cannot be placed next to the
  pointer in screen coordinates.
- A browser refuses `window.open` without a click, so a hover tooltip never
  appears on the web backend.

A tooltip drawn inside the window needs none of those. It cannot leave the
window, which a tooltip near an edge would want; that is accepted.

**A menu keeps the second window.** A menu opens on a click, and a click is the
user gesture a browser asks for, so the popup route works on every backend. A
tooltip opens on a hover, and a hover is not one. The rule is the gesture that
opens it, not the thing that is opened.

The three open steps of [tooltip.md](tooltip.md) stay open. This plan does not
close them, and it does not need them. That file keeps its own status.

### 3.3 The tooltip finds its widget with the Alt+press rule

The layer synthesises a left press with Alt at the pointer, reads the operation
back through the reader, and takes the path it answers. That path names the
innermost widget under the pointer as a whole, for every drawn widget, because
`convert_to_whole_selection` already applies that rule to whatever child a press
hits. `HoverProbeProjection` shows the shape of a probe that reads an operation
back without evaluating it.

**Why not `WidgetHoverTrackingProjection`.** It knows the widget under the
pointer only when that widget answers `MouseEnter` with an operation. A label, a
table cell and a badge answer nothing, so they would never show a tooltip. The
Alt+press rule needs no change to any widget.

**Why Alt and not a plain press.** A plain press answers a button's action. The
probe never evaluates what it reads, so no action would fire; but an Alt press
answers a selection and never an action, so the probe cannot be the thing that
makes an action fire by accident later.

### 3.4 A function answers the tooltip, and a field is the fallback

```julia
find_widget_tooltip(document, reference) -> Document | Nothing
```

`find_` and not `get_`, because a widget with no tooltip answers `nothing`.

The default method reads the document at `reference` and answers its `tooltip`
field when it has one, and `nothing` otherwise. A host that wants another rule
passes its own function to `make_window_shell`. The function wins; the field is
what the default function reads.

A tooltip is a `Document`, so a tooltip is a projection of a document like
everything else. A `String` is accepted and wrapped, because most tooltips are
one line.

### 3.5 Every widget type carries a `tooltip` field

The field goes last in the chrome run that nearly every widget type already
has — after `padding_color`, beside `visible`, `margin` and `border`. It
defaults to `nothing`, so `@document` keeps emitting the keyword constructor and
the Rule Y positional constructor unchanged.

The cost is honest and large: 43 widget types, each with a hand-written outer
constructor that must pass one more `Cell`. The IO map field count changes, and
the widget suite counts move with it. Step 4 carries that cost alone, so that a
count that moves is explained by one step.

### 3.6 The context menu asks the same question, and opens the way it already does

```julia
find_widget_context_menu(document, reference) -> Document | Nothing
```

A right press runs the same probe as the tooltip, finds the innermost widget and
asks the function. The default method reads a `context_menu` field on the widget.
What it answers opens through `OpenPopupOperation`, which is the route
`WidgetContextMenu` already takes and which §3.1 makes work.

`WidgetShell.context_menu` stops being a dead field. It becomes the menu of the
window itself: what opens when no widget under the pointer offers one.

`WidgetContextMenu`, the wrapper type, stays and changes not at all. It gives one
subtree a menu without a field on every widget in it, and it answers first
because it is closer to the pointer.

**Why the same probe twice.** A tooltip and a context menu ask one question: what
does the thing under the pointer offer. One probe, two functions, two fields.

### 3.7 The status line and the menu bar say only what works

A menu item that does nothing is worse than no menu. The first menu offers only
commands that exist today:

- **File** — New tab (`Ctrl+T`), Close tab (`Ctrl+W`), Save (`Ctrl+S`), Reload
  (`Ctrl+O`), Quit.
- **Edit** — Copy, Cut, Note, Paste, Paste copy. Each is the clipboard gesture
  of the same name, and each is greyed when the layer that offers it is off.
- **View** — Split vertically, Split horizontally, Duplicate tab, Command
  palette, Gesture help.

Save As, Open, Find and Preferences are **not** on the menu, because nothing
behind them exists. §6 says where they go.

The status line shows three fields: the title of the focused tab, the selection
as `ReferenceToHumanReadableText` prints it, and what the host appends. The host
appends the run state in the interface and nothing in the application.

A host adds a menu, a toolbar button and a status field through keywords of
`make_window_shell`, so the interface adds Run and Stop without the shell
knowing them.

### 3.8 The application declares its verbs

```julia
make_application_api() = Any[make_pane_api()..., make_interface_api()...,
                             make_file_api()...]
```

`make_file_api()` is new and belongs beside the file verbs, in the workbench
slice: open a file in a tab, save the tab, reload the tab, list the workspace,
read a document from a path, write a document to a path.

`APPLICATION_SYSTEM` is new, and it is what the model is told about itself, as
`IDE_SYSTEM` is in the interface. The greeting, the system text and the module
list are three descriptions of one thing, so all three change together.

### 3.9 The application turns on all six clipboard gestures

The interface offers four and leaves out cut and toggle, because a cut would
write into a record of a run. The application edits files, so cut is what a
person expects, and the toggle shows what is stored. The application offers all
six.

### 3.10 The navigator goes into the interface, not into the campaign window

`OmnetIde` gains `ProjecturedWorkbench` and `ProjecturedFileSystem`. It opens a
navigator tab on the project directory, in the first group, beside the runner.

The campaign window does not get it. Its guard forbids `ProjecturedFileFormat`
and `ProjecturedSyntax` so that the small binary stays small, and the navigator
needs both.

The interface opens the formats its closure already holds: Julia, Markdown and
Math. It does not gain JSON, XML, YAML or SQL. A NED file and an INI file open
as plain text until omnet-julia registers its own formats, which is its own
work and not this plan's.

### 3.11 The two flags

`projectured` gains `--gesture-log`, the switch the interface already has, and
`--context`, the token window of the model. Three places must agree: the parser,
`make_projectured_usage`, and the test that compares them.

The shell is always on. A flag to turn it off is not added until somebody needs
one.

### 3.12 The background colour goes away

`_paint_windows!` and `CAMPAIGN_BACKGROUND` are deleted from omnet-julia. The
shell paints the window, because a shell with a menu bar and a status line
already covers the ground that the colour was painted on.

### 3.13 Open questions for the owner

1. **Undo and redo.** They are missing from both binaries. An undo needs an
   inverse for every operation and a log on the editor, which is a design of its
   own size. The proposal is that this plan does not carry it and a plan of its
   own does. §6 holds it.
2. **Save As and Open.** Both need a path picker, which needs a modal over the
   window. `WidgetDialog` exists and draws. The proposal is one more step in
   this plan, after Step 6, because the File menu asks for them the moment it
   exists.
3. **Find in document.** The command palette searches gestures, not text. A
   find needs a search projection over the focused document. The proposal is
   out of scope.
4. **A tooltip that leaves the window.** §3.2 draws the tooltip inside the
   window. A tooltip near the right edge is clipped. The proposal is to accept
   that and to revisit only if it annoys in use.

## 4. Steps

Each step lands on `main` as one commit, with explicit paths. Each step names
the narrowest test that covers it. A step that moves a count writes the old and
the new count here.

### Step 0 — the baselines

- [ ] Record the counts of `test_application()` and `test_substrate()` in
      projectured-julia.
- [ ] Record the counts of `test_ide_window_wrap()` and `test_select_and_paste()`
      in omnet-julia.
- [ ] Record the two closure tests that already fail on omnet-julia `main`:
      `IdeClosureTest` asserts 42 against 43, and `CampaignUiClosureTest` asserts
      22 against 25 and finds `ProjecturedSerialization`. Write the exact output
      here, so Step 7 can prove it changed nothing else.
- [ ] Record what each binary does today, as a short list of keys that work.

### Step 1 — one package holds the shell of a window

- [ ] Add `package/ProjecturedShell` and `source/shell/`. Follow
      [package-rules.md](../../documentation/rule/package-rules.md): a
      `Project.toml`, a `src/ProjecturedShell.jl` with the docstring, the
      imports and the ordered includes.
- [ ] `make_window_shell(; gesture_help, command_palette, gesture_log, selection,
      clipboard_gestures, tooltip, shell, measure)` answers the fold. It is the
      body of `make_ide_window_wrap`, with two keywords more.
- [ ] `make_shell_opened_window_projections(; gesture_help, measure)`.
- [ ] The fold composes `WidgetPopupResolverProjection` at the root of the
      window's content. This is the one behaviour that Step 1 does change, and
      it is a repair: a `WidgetSelect`, a submenu and a `WidgetContextMenu` start
      to open in both binaries (§2.5).
- [ ] Move `make_shell_document` and `make_shell_projection` out of
      `example/workbench/` into the package. The gallery keeps its call.
- [ ] Add `ProjecturedShell` to the `Projectured` umbrella.
- [ ] omnet-julia: `make_ide_window_wrap` becomes a call to `make_window_shell`
      that names the layers the interface wants. `IDE_CLIPBOARD_GESTURES` stays
      where it is, because it is the interface's choice.
- [ ] projectured-julia: `make_application_projection` calls `make_window_shell`
      with the two layers it has today, and nothing more.
- [ ] **No behaviour changes in this step.** Both windows draw and answer as
      before.
- [ ] A test asserts that a `WidgetSelect` in a window drops down, which it does
      not today.
- Tests: `test_application()`, `test_gesture_help()`,
  `test_command_palette_decorator()`, `test_gesture_log()`,
  `test_selection_walking()`, `test_clipboard()`, `test_package_graph()`; in
  omnet-julia `test_ide_window_wrap()`.

### Step 2 — the application gets the clipboard, the walk and two flags

- [ ] Turn on `selection` in the application's call to `make_window_shell`, with
      all six clipboard gestures (§3.9).
- [ ] Add `--gesture-log` and `--context` to `parse_application_arguments`, to
      `make_projectured_usage` and to the greeting text.
- [ ] `--context` reaches the `Assistant` through its `context` field.
- [ ] The greeting names the keys that the layers turned on, as the interface's
      greeting does, and says nothing about a key that is off.
- Tests: `test_application()`, `test_clipboard()`, `test_selection_walking()`.

### Step 3 — the application declares its verbs

- [ ] Add `make_file_api()` beside the file verbs in the workbench slice.
- [ ] Add `make_application_api()` in the application.
- [ ] Add `APPLICATION_SYSTEM`, and give it to the `Assistant`.
- [ ] `run_application` calls `declare_api!(editor.tools, make_application_api())`
      in `on_start`, before `bind_meaning_model!`.
- [ ] The greeting names what the verbs do, in the words a person uses.
- [ ] A test asserts that `search_api` answers a file verb and a pane verb, and
      that it no longer answers a kernel module for a plain question.
- Tests: `test_application()`, `test_interface_api()`,
  `test_execute_julia_code()`, `test_mcp_tools()`.

### Step 4 — a widget carries a tooltip

- [ ] Add `tooltip::Any = nothing` to the chrome run of each of the 43 widget types in
      `source/widget/WidgetDocument.jl`, and a `tooltip` keyword to each
      hand-written outer constructor.
- [ ] Add `find_widget_tooltip(document, reference)` with the default method that
      reads the field, and the `String` convenience.
- [ ] Write the old and the new `test_substrate()` counts here. The IO map field
      count moves, and the count of passes moves with it.
- Tests: `test_substrate()`.

### Step 5 — the interface shows a tooltip

- [ ] Add the tooltip layer to `ProjecturedShell`: the Alt+press probe, the dwell
      timer, and the `WidgetTooltip` it puts into `WidgetShell.tooltip`.
- [ ] `make_window_shell(; tooltip = find_widget_tooltip)` turns it on. A host
      passes its own function.
- [ ] Both binaries turn it on.
- [ ] A new `test_widget_tooltip()`: a probe over a widget with a tooltip answers
      one, a probe over a widget without one answers nothing, a probe under the
      dwell time answers nothing, and a move to another widget replaces it.
- Tests: `test_widget_tooltip()`, `test_tooltip()`, `test_application()`.

### Step 6 — the shell draws the chrome

- [ ] Wrap the content of the window in a `WidgetShell` inside the fold, and give
      the shell the size of the window. A shell with no size hugs its content
      (§2.6), which a window shell must not do.
- [ ] Add `find_widget_context_menu(document, reference)` and the right-press
      probe. What it answers opens through `OpenPopupOperation` (§3.6).
- [ ] `WidgetShell.context_menu` becomes the menu of the window itself, and opens
      when no widget offers one.
- [ ] Build the menu bar, the toolbar and the status line of §3.7, and let a host
      append to each.
- [ ] omnet-julia: delete `_paint_windows!`, `CAMPAIGN_BACKGROUND` and the
      `background` keyword of `run_campaign_window`. The interface appends its
      own Run and Stop to the toolbar.
- [ ] A new `test_window_shell()`: every menu item runs the gesture it names, a
      greyed item is greyed when its layer is off, and the status line follows
      the focused tab.
- Tests: `test_window_shell()`, `test_widget_context_menu()`,
  `test_application()`; in omnet-julia `test_ide_window_wrap()`.

### Step 7 — the file navigator in the interface

- [ ] omnet-julia: add `ProjecturedWorkbench` and `ProjecturedFileSystem` to
      `package/OmnetIde/Project.toml`.
- [ ] `run_omnet_ide` opens a navigator tab on the project directory, in the
      first group.
- [ ] Add the two dispatch entries a host needs, as §2.4 names them.
- [ ] Set the closure cap of `IdeClosureTest` to the true number, and say in the
      test why it moved. Do not touch `CampaignUiClosureTest`: the campaign
      window gains nothing.
- [ ] Prove that the campaign window's closure did not change.
- [ ] A new test opens a Julia file and a Markdown file from the navigator of the
      interface.
- Tests: in omnet-julia `test_ide_window_wrap()`, `IdeClosureTest`,
  `CampaignUiClosureTest`.

### Step 8 — the guides, and close

- [ ] Write `documentation/package/shell/shell.md`: what the fold is, what each
      layer does, and how a host adds a menu, a button and a status field.
- [ ] Update [editor.md](../../documentation/package/kernel/editor.md) where it
      names the window.
- [ ] Update the omnet-julia guide that names `make_ide_window_wrap`.
- [ ] Update [README.md](../../README.md) if the quick start names a key.
- [ ] Move this plan to `plan/done/`.

## 5. Risks

| Risk | What is done about it |
| --- | --- |
| The field sweep of Step 4 touches 43 types and moves test counts. | Step 4 carries it alone and writes the old and the new count. A count that moves in another step is a fault of that step. |
| The two closure tests already fail on omnet-julia `main`. | Step 0 records the exact output. Step 7 sets one cap and proves the other closure did not change. |
| A menu item that does nothing teaches a person that the menu is a lie. | §3.7 puts only working commands on the menu. Save As and Open wait for §3.13 question 2. |
| The Alt+press probe runs on every pointer move. | The probe runs only after the pointer rests for the dwell time, as `HoverProbeProjection` throttles idle motion today. Step 5 measures it before it is turned on. |
| Moving the fold could change what the interface does. | Step 1 changes one thing on purpose — the popup resolver — and nothing else. `test_ide_window_wrap()` is the proof for the rest. |
| A popup that never opened now opens, so a widget that was inert becomes live. | That is the repair, not a regression. Step 1 lists which widgets change: `WidgetSelect`, a submenu, and `WidgetContextMenu`. |
| A tooltip drawn in the window is clipped at an edge. | Accepted; §3.13 question 4. |

## 6. Out of scope

- **Undo and redo.** §3.13 question 1. They need an inverse per operation and a
  log on the editor.
- **Find in document.** §3.13 question 3.
- **A settings surface and a recent-files list.** Nothing asks for them yet.
- **The three open steps of [tooltip.md](tooltip.md)**: the SDL no-input-focus
  flag, `screen_origin`, and the position of a native tooltip window. §3.2 says
  why this plan does not need them.
- **The NED and INI formats in the navigator.** omnet-julia registers no natural
  format today. Its files open as plain text until it does.
- **The campaign window.** It stays small on purpose.
