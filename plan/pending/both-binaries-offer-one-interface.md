# Both binaries offer one interface

**Status (2026-09-18): NOT STARTED.** The plan is complete. The owner answered
the four open questions on 2026-09-18, and §1 records the rulings. Every name it
mints is checked against
[naming-rules.md](../../documentation/rule/naming-rules.md), and §3.14 lists
them with the rule each one answers to. Nothing is implemented, and nothing is
pushed.

**Steps 3, 8 and 9 wait for another plan.**
[tool-views-replace-the-workbench.md](tool-views-replace-the-workbench.md)
removes the workbench and moves what survives it into the pane and file system
slices. §2.7 says what that changes here, and it makes those three steps
smaller.

**The tooltip is a generic over documents, not over widgets** (§3.4), which is
the owner's ruling of 2026-09-18. A widget stores its tooltip in a field; every
other document computes one.

**Goal:** `projectured` and `omnet_ide` offer the same interface. A person who
learns one knows the other. Every wrapper is built once, in projectured-julia,
and each binary turns on the wrappers it wants.

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
| How is it added? | In a reusable way. One wrapper, built once, used by both. |
| Where does a tooltip live? | On the widget, and the interface supports it. |
| How does a widget say its tooltip? | A function answers it. A field on the widget is the fallback. |
| The window background colour | Drop it. A shell widget takes its place. |
| What does the shell hold? | A menu, a context menu, a toolbar and a status line. |
| The file navigator | It works in the interface too, not only in the application. |

The rulings of the owner on the first draft, 2026-09-18:

| Question | Ruling |
| --- | --- |
| Undo and redo | Not in this plan. A plan of its own carries them. |
| Save As and Open | In this plan. Write them as dialogs. |
| Find in document | Not in this plan. |
| A tooltip clipped at the window edge | Do not draw the tooltip in the window. **A tooltip is a separate window.** |

The ruling of the owner on the tooltip, 2026-09-18:

> a tooltip can be answered by any document, a widget is different in the sense
> that it has a field which stores the tooltip usually set externally, other
> documents will have tooltips which are computed. for example, a Julia function
> definition can have a documentation tooltip with signature and prose.

| Question | Ruling |
| --- | --- |
| Which documents can answer a tooltip? | Any document, not only a widget. |
| What makes a widget different? | It has a field. Whoever builds the widget sets it from outside. |
| What does every other document do? | It computes its tooltip. |
| An example of a computed one | A Julia function definition answers its signature and its prose. |

## 2. What exists

The gap is small because most of the parts are already written. Each row is a
fact this plan stands on.

### 2.1 The two windows today

| Fact | Where |
| --- | --- |
| The interface folds five wrappers over its window: gesture help, command palette, gesture log, selection walk and clipboard | omnet-julia `source/ide/IdeWindow.jl:171` |
| The application folds two: gesture help and command palette | [example/projectured/Application.jl:169](../../example/projectured/Application.jl#L169) |
| Both draw the same pane gesture table | [source/pane/PaneGestures.jl:152](../../source/pane/PaneGestures.jl#L152) |
| The interface declares its verbs; the application declares none | omnet-julia `source/campaign/CampaignWindow.jl:191` |
| `declare_api!` has no caller in `source/` or `example/` of this repository | [source/kernel/tool/ToolSet.jl:38](../../source/kernel/tool/ToolSet.jl#L38) |
| An empty declaration makes `search_api` index the 23 submodules of `ProjecturedKernel`, and nothing else | [source/kernel/tool/Documentation.jl:826](../../source/kernel/tool/Documentation.jl#L826) |
| `execute_julia_code` meanwhile re-exports the whole `Projectured` umbrella | [source/kernel/tool/CodeExecution.jl:60](../../source/kernel/tool/CodeExecution.jl#L60) |
| `make_pane_api` and `make_interface_api` already declare the pane and widget verbs; only a test calls them | [source/pane/PaneProgram.jl:93](../../source/pane/PaneProgram.jl#L93) |
| The interface paints its windows one colour at start. The shell replaces it, and §3.12 deletes it | omnet-julia `source/campaign/CampaignWindow.jl:93` |
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
| `get_screen_origin` does not exist, so a tooltip cannot be placed in screen coordinates | grep answers nothing |
| `default_tooltip_position` answers a fixed corner | [source/tooltip/TooltipDecorator.jl:53](../../source/tooltip/TooltipDecorator.jl#L53) |
| The web backend opens a second window as a browser popup, and a browser needs a click first, so a hover tooltip never appears there | [asset/web/client.js:164](../../asset/web/client.js#L164) |
| `WidgetHoverTrackingProjection` knows which widget the pointer is over, but only for a widget that answers `MouseEnter` | [source/widget/WidgetHoverTracking.jl:144](../../source/widget/WidgetHoverTracking.jl#L144) |
| `HoverProbeProjection` shows how to reverse-project the pointer without a click | [source/inspector/HoverProbe.jl:32](../../source/inspector/HoverProbe.jl#L32) |
| An Alt+left press answers the innermost widget under the pointer, for every drawn widget, and never fires an action | [source/focus/WholeSelection.jl:51](../../source/focus/WholeSelection.jl#L51) |

### 2.4 The navigator and the closure of the interface

Every row here is the tree of 2026-09-18. §2.7 says which of them the other plan
changes, and Step 9 works from §2.7 where the two disagree.

| Fact | Where |
| --- | --- |
| The navigator needs a closure of 23 packages | `ProjecturedWorkbench`, `ProjecturedFileSystem`, `ProjecturedFileFormat` and their dependencies |
| Of those, only `ProjecturedWorkbench` and `ProjecturedFileSystem` are new to `OmnetIde` | omnet-julia `package/OmnetIde/Project.toml` |
| A document format is opt-in and registers itself, so the interface opens only the formats its closure holds: Julia, Markdown and Math today | [source/fileformat/NaturalFormat.jl:15](../../source/fileformat/NaturalFormat.jl#L15) |
| The campaign window forbids `ProjecturedFileFormat` and `ProjecturedSyntax`, so the navigator must not go there | omnet-julia `test/legacy/runner/CampaignUiClosureTest.jl:37` |
| A `WorkbenchEditor` and a `WorkbenchNavigator` sit in a plain `PaneTab` when the host adds two dispatch entries. Both types go away, and the entries with them (§2.7) | [example/projectured/Application.jl:188](../../example/projectured/Application.jl#L188) |
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
- a `WidgetContextMenu` draws its child and answers a right press with nothing
  visible.

**Measured 2026-09-18**, in `test_window_wrap()`. The widget does answer: an
`OpenPopupOperation` naming an anchor and an offset reaches the top of the window
route with nothing there to resolve it, and the screen keeps its one window. With
the wrap, the reader answers `nothing` instead — because the window manager has
already consumed the resolved operation — and the screen has two windows, the
second holding the option list.

The gallery says so in a comment: the commands of its shell are inert because no
popup resolver is composed there
([example/workbench/WrapperDocumentExample.jl:26](../../example/workbench/WrapperDocumentExample.jl#L26)).

One line fixes all three at once, in both binaries. That is the cheapest item in
this plan and it is the reason the chrome looks unfinished.

**It is not a line in the fold.** Found while implementing, 2026-09-18. A popup
is a native window, so its `OpenWindowOperation` carries **screen** coordinates,
and the resolver reaches them only by mapping through `ScreenToScreen`. The
gallery places it accordingly, between the manager and the screen printer
([example/substrate/WidgetProjectionExample.jl:37](../../example/substrate/WidgetProjectionExample.jl#L37)),
while the unit test places it around a bare content projection and asserts
content-local coordinates
([test/substrate/projection/WidgetContextMenuTest.jl:70](../../test/substrate/projection/WidgetContextMenuTest.jl#L70)).
Both compile; only the first opens a popup where the pointer is.

The resolver therefore belongs in `make_window_scene_projection`
([source/screen/WindowScene.jl:60](../../source/screen/WindowScene.jl#L60)),
which the fold never sees. `ProjecturedScreen` must not name
`ProjecturedWidget`, so that function takes a new `screen_wrap` keyword,
`run_window_editor` passes it through, and `ProjecturedShell` exports the value
to pass. `WindowScene.jl` is not sealed; the sealed set is 50 files, all in the
kernel.

### 2.6 Two facts that shape the shell

- **A `WidgetShell` with no size hugs its content.** `test_shell_offers_only_its_size`
  ([test/substrate/projection/WidgetTableTest.jl:171](../../test/substrate/projection/WidgetTableTest.jl#L171))
  asserts it. A window shell must fill the window instead, so the fold must say
  what size it is.
- **`WidgetShell.tooltip` is a band inside the window.** A tooltip is a separate
  window (§3.2), so this plan sets that field on nothing and the band stays
  empty. `WidgetTooltip`
  ([source/widget/WidgetDocument.jl:471](../../source/widget/WidgetDocument.jl#L471))
  keeps its place for a host that wants an overlay inside its own content.

### 2.7 Another plan removes the workbench under us

[tool-views-replace-the-workbench.md](tool-views-replace-the-workbench.md) is
written and not started. It affects six places in this plan, and mostly it makes
them smaller.

| What that plan decides | Where | What it does to this plan |
| --- | --- | --- |
| `WorkbenchEditor` goes away. A file tab holds a `FileDocument`, which carries its own `filename`. `Ctrl+S` calls `save_file!` and `Ctrl+O` calls `load_file`. | its D4, Step 7 | Step 8 acts on a `FileDocument`, not on a tab beside a name. |
| `Workspace`, `WorkspaceFolder` and `WorkspaceToFileSystem` move to the file system slice. `WorkbenchFile.jl` becomes `source/pane/PaneFile.jl`. The three workbench packages are deleted. | its D6, Step 8 | Step 9 adds **one** package to the interface, not two. `make_file_api` and the file operations belong to `PaneModule`. |
| A tool registers its own natural row from its `__init__`. The file explorer and the `FileDocument` each get one. | its D1, Steps 1 and 7 | Step 9 needs no dispatch entry. A host that depends on the package gets the explorer. |
| The `:workbench` value of `APPLICATION_WINDOWS` goes, and the parameter with it. One window is left. | its Step 8 | §3.7 drops its note about a window that is not a pane tree. |
| The whole editor document saves to a `.pred` file, with a reference to each open file. | its Steps 9 and 10 | **The chrome must not be in the document** (§3.1). |
| `print!` puts `editor.document` in the root printer context as the `:root` property. | its D8 | The status line of §3.7 reads the same property. |

**Which plan goes first.** Steps 7 and 8 of that plan must land before Steps 3,
8 and 9 of this one. Steps 0 to 2 and 4 to 7 of this plan touch nothing it
moves, so the two can run side by side up to that point.

**Two things this plan hands back to that one.**

1. **The clipboard wrapper will be in the saved document.** Step 2 turns it on in
   the application, and it sits above the pane tree. Its D5 lists `PaneTree`,
   `Assistant`, `GestureLog` and `SelectionInspector` as documents that must
   write less; the clipboard slice is not on that list and should be.
2. **The gallery's `shell = true` calls `make_shell_document`**
   ([example/projectured/Gallery.jl:266](../../example/projectured/Gallery.jl#L266)),
   which its Step 8 deletes with `example/workbench/`. Step 7 of this plan gives
   the gallery the projection to use instead.

## 3. Decisions

### 3.1 One package holds the shell of a window

A new package `ProjecturedShell`, whose slice folder is `source/shell/`. It
holds what sits between a window and the document in it:

- `make_window_wrap(...)` — the fold `(document, projection) -> (document,
  projection)` that stacks the wrappers. It is the function that
  `make_ide_window_wrap` is today, moved down and made general.
- `make_opened_window_projections(...)` — what a window that a wrapper opens
  draws with.
- `WindowShellProjection`, which prints a `WidgetShell` around whatever the inner
  projection printed: a menu bar, a toolbar, a status line and a context menu.

**The shell is drawn, not stored.** The projection makes the `WidgetShell`; no
document is wrapped in one. Three reasons, and the first is the one that decides
it:

1. The other plan saves the whole editor document to a `.pred` file (§2.7). A
   menu bar in that file would be the binary's chrome saved as the person's
   work, and a layout saved by the application would carry the application's
   menu into the interface.
2. A saved document would have to be unwrapped on load, or the fold would wrap a
   second shell around the first.
3. `WidgetShell` would need `register_pred_type!`, and every band with it.

The clipboard is the other way round, and stays that way: it wraps the document
because what it stores is the person's, not the binary's.
- The tooltip wrapper. `TooltipProbeProjection` lives in the tooltip slice, and
  the shell composes it (§3.14).
- `make_popup_screen_wrap()`, the value of the new `screen_wrap` keyword of
  `run_window_editor`. It puts `WidgetPopupResolverProjection` on the window
  route, so that every popup a widget asks for actually opens (§2.5). It is not
  part of the fold, because the fold never sees the screen.

It depends on `ProjecturedGestureHelp`, `ProjecturedGestureLog`,
`ProjecturedClipboard`, `ProjecturedFocus`, `ProjecturedTooltip`,
`ProjecturedWidget` and `ProjecturedPane`. None of them carries a third-party
dependency, so `ProjecturedShell` is a sub-stem and the `Projectured` umbrella
aggregates it.

`make_shell_document` and `make_shell_projection` in `example/workbench/` are
**not** moved. They wrap a document, which the paragraph above rejects, and the
other plan deletes the folder they live in. `WindowShellProjection` replaces
both, and Step 7 gives the gallery's `shell = true` the new one.

The pair `make_<thing>_document` / `make_<thing>_projection` stays the convention
for a wrapper that does own document state: `make_clipboard_document` /
`make_clipboard_projection` is the one this package composes.

**The package brings its siblings.** [package-rules.md](../../documentation/rule/package-rules.md)
asks for them and `test_package_graph()` asserts it:

- `package/ProjecturedShellTest`, whose entry point is `test_shell()` and whose
  static guard is `test_shell_layering()`, in `test/shell/ShellSuite.jl`.
- `source/shell/ShellModule.jl` declares `ShellModule` and holds the docstring,
  the imports and the ordered includes. `ShellModule` is free today. Every other
  file under `source/shell/` is a fragment that declares no module.
- The slice declares no document of its own, so no `ShellDocument.jl` is written.
  A file is named for what it defines: `WindowWrap.jl` holds the fold and
  `WindowShell.jl` holds `WindowShellProjection`.

**Why a package and not a function in each binary.** Each binary composes the
wrappers by hand today, and the two lists drifted apart. One function that takes a
keyword per wrapper cannot drift: a wrapper that the application turns on is the
same code the interface turns on.

### 3.2 A tooltip is a separate window

The owner ruled it. A tooltip opens as its own native window, through
`TooltipDecoratorProjection`, `OpenWindowOperation` and the `:tooltip` style
that the backend already reads. It can therefore leave the window it belongs to,
which is what a tooltip near an edge needs.

**One route for everything that pops.** A menu, a submenu, a select, a context
menu and a tooltip all become a second window through the same two steps: an
operation from the widget, and `WindowManagingProjection` above it. §3.1 makes
that route work by composing the popup resolver, and the tooltip rides the route
the menus use.

**This plan therefore finishes the tooltip window.** Three things are unfinished
today, and each is a part of Step 5:

1. **The focus.** SDL sets no no-input-focus flag, so a tooltip window takes the
   focus from the window under it
   ([source/sdl/Sdl.jl:424](../../source/sdl/Sdl.jl#L424)). The comment there is
   also wrong: `0x00000400` is `SDL_WINDOW_MOUSE_FOCUS`, not
   `SDL_WINDOW_ALWAYS_ON_TOP`, which is `0x00008000`. Step 5 fixes the flags and
   the comment.
2. **The place.** `get_screen_origin` does not exist, so nothing can say where a
   window is on the screen, and a tooltip cannot be put beside the pointer.
   Step 5 adds it to the backend interface.
3. **The position.** `default_tooltip_position` answers a fixed corner
   ([source/tooltip/TooltipDecorator.jl:53](../../source/tooltip/TooltipDecorator.jl#L53)).
   Step 6 derives the real one: the pointer, plus the origin of the window it is
   in, plus an offset, held inside the screen.

This closes Step 1 and Step 6 of [tooltip.md](tooltip.md), and its Steps 5 and 8
come along as tests. Step 4 of this plan closes the documentation tooltip of its
Step 7. That file then holds two example tooltips and nothing else: one for a
type and one for an error.

### 3.2b The web backend draws a tooltip window in the page

A browser refuses `window.open` without a user gesture, so the web client queues
a window it cannot open and shows it on the next click
([asset/web/client.js:164](../../asset/web/client.js#L164)). A menu opens on a
click and is therefore fine. A tooltip opens on a hover and would never appear.

The answer keeps the document model whole. A tooltip is a separate window
everywhere, and only the **web client draws it differently**. A window whose
style is `:tooltip` renders as a positioned overlay in the page instead of a
popup. Nothing above the backend knows the difference.

Step 5 carries it. A tooltip on the web is then held inside the browser tab.
That is the one place the ruling cannot be met, because a browser gives a page no
way out of its tab.

### 3.3 The tooltip finds its widget with the Alt+press rule

The wrapper synthesises a left press with Alt at the pointer, reads the operation
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

### 3.4 Any document answers a tooltip

```julia
compute_tooltip(document) -> Document | Nothing
```

One generic over documents. `compute_` because most documents build a fresh
answer rather than look one up: only a widget has something to find.
`compute_tooltip(::Any) = nothing` is the default, so a document with nothing to
say says nothing.

**A widget stores its tooltip; every other document computes one.** That is the
whole of the difference the owner named:

| kind of document | how it answers |
| --- | --- |
| a widget | It reads its `tooltip` field. Whoever builds the widget sets the field from outside, because a button knows nothing about why it is there. |
| a Julia function definition | It computes a document that holds the signature and the prose of the docstring. |
| a JSON or XML node | It computes what it is worth saying about that node. |
| anything else | `nothing`, until a slice adds a method. |

**Where the generic lives.** `DomainModule`, in
[source/domain/DocumentCore.jl](../../source/domain/DocumentCore.jl), beside
`accepts_pasted_document`. That file already holds the generic that every domain
specialises, `ProjecturedDomain` depends on `ProjecturedKernel` alone, and
`ProjecturedClipboard`, `ProjecturedConversation` and `ProjecturedPane` already
depend on it. The one new edge is `ProjecturedWidget` to `ProjecturedDomain`,
which is acyclic and small.

**The probe hands it a node, not a widget.** An Alt+press reverse-projects to a
path in the source document, so what the pointer rests on is a JSON node in a
JSON tab, a Julia node in a Julia tab, and a widget where a widget is what was
drawn (§3.3). The generic is therefore the right shape and the probe needs no
case for a widget.

**A host may still override.** `make_window_wrap` takes the function as a
keyword, and `compute_tooltip` is the default. A host that wants another rule
passes another function.

A tooltip is a `Document`, so it draws through a projection like everything
else, and it becomes the content of the tooltip window (§3.2). A `String` is
accepted and wrapped, because most tooltips are one line.

### 3.5 Every widget type carries a `tooltip` field

A widget is the one kind of document that stores its tooltip instead of
computing one, so the field is what its `compute_tooltip` method reads.

The field goes last in the chrome run that nearly every widget type already
has, after `padding_color`, beside `visible`, `margin` and `border`. It defaults
to `nothing`, so `@document` keeps emitting the keyword constructor and the
Rule Y positional constructor unchanged. A caller then writes
`WidgetButton(...; tooltip = "Run the selected configurations")`, which is the
"set externally" the owner asked for: a button knows nothing about why it is
there, and whoever places it does.

The cost is honest and large: 43 widget types, each with a hand-written outer
constructor that must pass one more `Cell`. The IO map field count changes, and
the widget suite counts move with it. Step 4 carries that cost alone, so that a
count that moves is explained by one step.

`WidgetTreeNode` is a plain value and not a `@document`, so it takes no field.
Its method answers `nothing`.

### 3.6 The context menu asks the same question of any document

```julia
compute_context_menu(document) -> Document | Nothing
```

A right press runs the same probe as the tooltip, finds the innermost document
and asks the function. What it answers opens through `OpenPopupOperation`, which
is the route `WidgetContextMenu` already takes and which §3.1 makes work.

The two kinds of answer are the two of §3.4. A widget reads a `context_menu`
field that whoever built it set. Every other document computes its menu, which is
what makes the menu worth having: a JSON array offers "Add an element", a Julia
function definition offers "Go to the definition", and neither could have been
set from outside.

`WidgetShell.context_menu` stops being a dead field. It becomes the menu of the
window itself: what opens when the document under the pointer offers none.

`WidgetContextMenu`, the wrapper type, stays and changes not at all. It gives one
subtree a menu without a field on every widget in it, and it answers first
because it is closer to the pointer.

**The owner ruled on the tooltip, and the menu takes the same shape.** One probe
finds the innermost document; two generics ask it two questions. A menu that
worked differently from a tooltip would be a second rule to learn for no gain.

### 3.7 The status line and the menu bar say only what works

A menu item that does nothing is worse than no menu. The first menu offers only
commands that exist today:

- **File** — New tab (`Ctrl+T`), Close tab (`Ctrl+W`), Save (`Ctrl+S`), Reload
  (`Ctrl+O`), Quit.
- **Edit** — Copy, Cut, Note, Paste, Paste copy. Each is the clipboard gesture
  of the same name, and each is greyed when the wrapper that offers it is off.
- **View** — Split vertically, Split horizontally, Duplicate tab, Command
  palette, Gesture help.

Step 8 adds **Open** (`Ctrl+Shift+O`) and **Save As** (`Ctrl+Shift+S`) to the
File menu, in the same step that writes them. A menu item never lands before the
command behind it.

Find and Preferences are **not** on the menu. Nothing behind them exists, and §6
says so.

The status line shows three fields: the title of the focused tab, the selection
as `ReferenceToHumanReadableText` prints it, and what the host appends. The host
appends the run state in the interface and nothing in the application. It reads
the selection from the `:root` property of the root printer context, which the
other plan puts there for its selection display (§2.7); neither tool needs its
own way in.

A host adds a menu, a toolbar button and a status field through keywords of
`make_window_wrap`, so the interface adds Run and Stop without the shell
knowing them.

The first draft said that `--window=workbench` is not a pane tree and gets none
of these keys. The other plan deletes that window and the parameter with it
(§2.7), so there is one window and the note is gone.

### 3.8 The application declares its verbs

```julia
make_application_api() = Any[make_pane_api()..., make_interface_api()...,
                             make_file_api()...]
```

`make_file_api()` is new and belongs beside the file verbs. The other plan moves
`WorkbenchFile.jl` to `source/pane/PaneFile.jl` (§2.7), so they are in the pane
slice and `PaneModule` owns them: open a file in a tab, save the tab, reload the
tab, list the workspace, read a document from a path, write a document to a
path.

`APPLICATION_SYSTEM` is new, and it is what the model is told about itself, as
`IDE_SYSTEM` is in the interface. The greeting, the system text and the module
list are three descriptions of one thing, so all three change together.

### 3.9 The application turns on all six clipboard gestures

The interface offers four and leaves out cut and toggle, because a cut would
write into a record of a run. The application edits files, so cut is what a
person expects, and the toggle shows what is stored. The application offers all
six.

### 3.10 The file explorer goes into the interface, not into the campaign window

`OmnetIde` gains `ProjecturedFileSystem`, and that is the whole of it. The other
plan moves `Workspace` and `WorkspaceToFileSystem` into that slice and deletes
`ProjecturedWorkbench` (§2.7), so one package carries what two would have.

The interface opens a file explorer tab on the project directory, in the first
group, beside the runner. It adds no dispatch entry, because the explorer
registers its own natural row.

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

### 3.13 What the owner settled, and what follows

Every question of the first draft is answered. Nothing in this plan is open.

1. **Undo and redo are not in this plan.** They need an inverse for every
   operation and a log on the editor, which is a design of its own size. A plan
   of its own carries them. §6 holds the pointer.
2. **Save As and Open are in this plan, as dialogs.** `WidgetDialog` exists and
   draws, and §3.1 makes a popup open, so a dialog has both halves it needs.
   Step 8 writes them, and the File menu gains the two items it was missing.
3. **Find in document is not in this plan.** §6 holds it.
4. **A tooltip is a separate window.** §3.2 and §3.2b say what that costs and
   what it buys.

### 3.14 The names this plan mints

Every name below is checked against
[naming-rules.md](../../documentation/rule/naming-rules.md). A name is written
here before it is written in code, so the audit that seals a file finds nothing
to correct.

| name | kind | the rule it answers to |
| --- | --- | --- |
| `ProjecturedShell` | package | `Projectured<Slice>`. The slice is `shell`, so the code is `source/shell/`, the suite `test/shell/` and the documents `example/shell/`. |
| `ProjecturedShellTest` | test package | `Test` is a reserved suffix. Its entry point is `test_shell()` and its guard `test_shell_layering()`. |
| `ShellModule` | module | `<Slice>Module`, declared by `source/shell/ShellModule.jl` and by no other file. |
| `make_window_wrap` | function | Verb first. The word that names the kind produced goes last, and it produces a wrap. |
| `make_opened_window_projections` | function | Verb first. It builds the value of the `opened_window_projections` keyword of `run_window_editor`, so it carries that name. |
| `make_shell_document`, `make_shell_projection` | functions | The wrapper pair every other wrapper here uses. |
| `compute_tooltip` | function | `compute_`, because most methods build a fresh document. `find_` would promise a look-up, which only the widget method does. One generic over documents, not one per kind of document. |
| `compute_context_menu` | function | The same shape, for the same reason. |
| `get_screen_origin` | function | `get_`, because the value sits at a known place. It is the sibling of `get_display_size`, so it is declared in `source/kernel/backend/BackendInterface.jl`, defaulted in `BackendDefaults.jl` and answered in `source/sdl/Sdl.jl`. |
| `make_file_api` | function | The shape of `make_pane_api` and `make_interface_api`. |
| `make_application_api` | function | The same. |
| `APPLICATION_SYSTEM` | constant | The shape of `IDE_SYSTEM` and `CAMPAIGN_SYSTEM`. |
| `TooltipProbeProjection`, `TooltipProbeIoMap` | projection | `<Stem>Projection` and `<Stem>IoMap`. The stem mirrors `HoverProbeProjection`, which probes the pointer the same way. |
| `ContextMenuProbeProjection`, `ContextMenuProbeIoMap` | projection | The same stem, for the right press. |
| `FileSystemChooser` | document | A noun, in the `FileSystem<Noun>` family beside `FileSystemFile` and `FileSystemDirectory`. |
| `WindowShellProjection`, `WindowShellIoMap` | projection | `<Stem>Projection` and `<Stem>IoMap`, in `source/shell/WindowShell.jl`. |
| `make_popup_screen_wrap` | function | Verb first, produced kind last: it makes the wrap that goes on the screen route. |
| `screen_wrap` | keyword | A snake_case noun, beside `opened_window_projections` on the same two functions. |
| `tooltip`, `context_menu` | fields | snake_case nouns. `context_menu` already exists on `WidgetShell`. |

**Who owns each name.** Every exported name has exactly one owning module.

- `DomainModule` owns the generics `compute_tooltip` and `compute_context_menu`, in
  `source/domain/DocumentCore.jl` beside `accepts_pasted_document`. Every other
  slice imports them and adds methods; none redefines or re-exports them.
- `WidgetModule` owns `ContextMenuProbeProjection`, and adds the widget methods of
  the two generics. It gains one dependency edge, `ProjecturedWidget` to
  `ProjecturedDomain` (§3.4).
- `JuliaModule` adds the `compute_tooltip` method that builds a signature and its
  prose. `ProjecturedJulia` already depends on `ProjecturedDomain`.
- `TooltipModule` owns `TooltipProbeProjection`. It takes the tooltip function as
  a keyword and gains one dependency edge, `ProjecturedTooltip` to
  `ProjecturedDomain`, so that it can name the generic it defaults to.
- `BackendModule` owns `get_screen_origin`.
- `FileSystemModule` owns `FileSystemChooser`.
- `PaneModule` owns `make_file_api`, and the save and reload operations that the
  other plan moves into `source/pane/PaneFile.jl`. **This plan mints no file
  operation.** Save As writes the `filename` of the `FileDocument` and then
  reuses the save operation that is already there, so it is a `CompoundOperation`
  of two things that exist.
- That other plan must rename those two operations when it moves them:
  `SaveWorkbenchEditorOperation` and `ReloadWorkbenchEditorOperation` name a type
  it deletes. `SaveFileOperation` and `ReloadFileOperation` read as English and
  follow the law. This plan uses those names and says so here, so the two plans
  do not each invent one.
- `ShellModule` owns `make_window_wrap`, `make_opened_window_projections` and
  `WindowShellProjection`.

**What the law changed in the first draft.** Three names were wrong, and each
would have reached the code.

1. `screen_origin` is a noun, and every function name starts with a verb. It is
   `get_screen_origin`. The first draft took the name from
   [tooltip.md](tooltip.md), which was written before the rule.
2. The plan called a wrapped projection a **layer**.
   [division-terminology.md](../../documentation/rule/division-terminology.md)
   reserves that word for a stratum inside a package, and asks that a plan use
   these words and no synonyms. Every one now says **wrapper**, which is what the
   code already says.
3. `make_window_shell` named the fold after the thing it is not. The fold makes a
   wrap; `WidgetShell` is the widget that draws the chrome. Two things must not
   share one word, so the fold is `make_window_wrap` and the shell stays the
   widget.

Two more names changed after that, and both for the same pair.

4. `find_widget_tooltip` and `find_widget_context_menu` named a widget in a
   generic that is over documents. A widget answers with a method, and a method
   needs no name of its own.
5. `find_` promised a look-up, and only the widget method does one. Every other
   method builds a fresh document, so the verb is `compute_`. The pair is
   `compute_tooltip` and `compute_context_menu`.

**The verb is chosen by the work, not by the return.** A function does not take
`find_` because it can answer `nothing`; it takes `find_` because it searches.
Answering `nothing` is what a computation with nothing to say does too.

## 4. Steps

Each step lands on `main` as one commit, with explicit paths. Each step names
the narrowest test that covers it. A step that moves a count writes the old and
the new count here.

### Step 0 — the baselines

**Done 2026-09-18**, in the worktree `workspace/projectured-julia-one-interface`
on branch `one-interface`, cut from `main` at `25e338c0`.

- [x] `test_application()`: **72 pass, 0 fail, 0 error**, 56 s.
- [ ] `test_substrate()`: running.
- [ ] Record the counts of `test_ide_window_wrap()` and `test_select_and_paste()`
      in omnet-julia. **A worktree cannot measure them.** omnet-julia's
      `[sources]` name `../../../projectured-julia/package/…`, which is the main
      checkout and not this worktree, so an omnet run tests `main`'s projectured.
      Take the omnet baselines against `main`, and do the omnet half of any step
      only after its projectured half has landed on `main`.
- [ ] Record the two closure tests that already fail on omnet-julia `main`:
      `IdeClosureTest` asserts 42 against 43, and `CampaignUiClosureTest` asserts
      22 against 25 and finds `ProjecturedSerialization`. Write the exact output
      here, so Step 7 can prove it changed nothing else.
- [ ] Record what each binary does today, as a short list of keys that work.

### Step 1 — one package holds the shell of a window

**Done 2026-09-18.** `test_shell()` is 23 pass, and `test_application()` is 72
pass, the same count as the baseline: the rewiring changed no behaviour. What
the work decided:

- The application grew `make_application_window(paths; …)`, which answers the
  pair. `run_application`, `warm_application` and the suite all come through it,
  so none of them holds a wrapper list of its own.
  `make_application_projection` now answers the **content** projection alone.
- `_gesture_map_entry`, the private helper the suite imported from the gallery,
  is gone from the application. `make_opened_window_projections()` says the same
  thing and is public.
- The clipboard and the walk stay off here. Step 2 turns them on.

- [x] Add `package/ProjecturedShell` and `source/shell/`. Follow
      [package-rules.md](../../documentation/rule/package-rules.md): a
      `Project.toml`, a `src/ProjecturedShell.jl` with the docstring, the
      imports and the ordered includes. `source/shell/ShellModule.jl` declares
      `ShellModule`; every other file under `source/shell/` is a fragment.
- [x] Add `package/ProjecturedShellTest` and `test/shell/ShellSuite.jl`, which
      define `test_shell()` and `test_shell_layering()`.
- [x] `make_window_wrap(; gesture_help, command_palette, gesture_log, selection,
      clipboard_gestures, tooltip, shell, measure)` answers the fold. It is the
      body of `make_ide_window_wrap`, with two keywords more.
- [x] `make_opened_window_projections(; gesture_help, measure)`.
- [x] Add the `screen_wrap` keyword to `make_window_scene_projection` and to
      `run_window_editor`, defaulting to `identity`, and apply it to
      `ScreenToScreen()` inside `WindowManagingProjection`.
- [x] `make_popup_screen_wrap()` in `ShellModule` answers
      `inner -> WidgetPopupResolverProjection(inner = inner)`. Both binaries pass
      it. This is the one behaviour that Step 1 does change, and it is a repair:
      a `WidgetSelect`, a submenu and a `WidgetContextMenu` start to open in both
      binaries (§2.5).
- [x] Do not move `make_shell_document`: the shell is drawn, not stored (§3.1).
      `WindowShellProjection` moved wholly into Step 7 — a projection that draws
      no band is a file nobody can judge, and the fold is complete without it.
- [x] Add `ProjecturedShell` to the `Projectured` umbrella, to
      `environment/all` and to `ProjecturedTest`.
- [ ] omnet-julia: `make_ide_window_wrap` becomes a call to `make_window_wrap`
      — **waits for this half to land on `main`**, because a worktree is invisible
      to omnet (Step 0).
      that names the wrappers the interface wants. `IDE_CLIPBOARD_GESTURES` stays
      where it is, because it is the interface's choice.
- [x] projectured-julia: `make_application_window` calls `make_window_wrap`
      with the two wrappers it has today, and nothing more.
- [x] **No behaviour changes in this step.** Both windows draw and answer as
      before.
- [x] `test_window_wrap()` asserts that a `WidgetSelect` in a window drops down,
      which it does not today, and that each keyword adds the wrapper it names.
- Tests: `test_shell()`, `test_shell_layering()`, `test_application()`,
  `test_gesture_help()`, `test_command_palette_decorator()`,
  `test_gesture_log()`, `test_selection_walking()`, `test_clipboard()`,
  `test_package_graph()`; in omnet-julia `test_ide_window_wrap()`.

### Step 2 — the application gets the clipboard, the walk and two flags

- [ ] Turn on `selection` in the application's call to `make_window_wrap`, with
      all six clipboard gestures (§3.9).
- [ ] Add `--gesture-log` and `--context` to `parse_application_arguments`, to
      `make_projectured_usage` and to the greeting text.
- [ ] `--context` reaches the `Assistant` through its `context` field.
- [ ] The greeting names the keys that the wrappers turned on, as the interface's
      greeting does, and says nothing about a key that is off.
- Tests: `test_application()`, `test_clipboard()`, `test_selection_walking()`.

### Step 3 — the application declares its verbs

- [ ] **Needs Step 8 of the other plan first** (§2.7): the file verbs must be in
      the pane slice before an API names them.
- [ ] Add `make_file_api()` beside the file verbs, in the pane slice.
- [ ] Add `make_application_api()` in the application.
- [ ] Add `APPLICATION_SYSTEM`, and give it to the `Assistant`.
- [ ] `run_application` calls `declare_api!(editor.tools, make_application_api())`
      in `on_start`, before `bind_meaning_model!`.
- [ ] The greeting names what the verbs do, in the words a person uses.
- [ ] A test asserts that `search_api` answers a file verb and a pane verb, and
      that it no longer answers a kernel module for a plain question.
- Tests: `test_application()`, `test_interface_api()`,
  `test_execute_julia_code()`, `test_mcp_tools()`.

### Step 4 — a document answers a tooltip

- [ ] Add the generic `compute_tooltip(document)` to `DomainModule`, in
      `source/domain/DocumentCore.jl` beside `accepts_pasted_document`, with
      `compute_tooltip(::Any) = nothing` and the `String` convenience.
- [ ] Add `tooltip::Any = nothing` to the chrome run of each of the 43 widget
      types in `source/widget/WidgetDocument.jl`, and a `tooltip` keyword to each
      hand-written outer constructor.
- [ ] Add the widget method that reads the field, and the dependency edge
      `ProjecturedWidget` to `ProjecturedDomain` that lets it name the generic.
- [ ] Add the first computed method: a Julia function definition answers a
      document holding its signature and the prose of its docstring. It is the
      proof that a computed tooltip works, and it is what
      [tooltip.md](tooltip.md) asked for in its Step 7.
- [ ] `test_widget_tooltip()`: a widget with a tooltip answers it, a widget
      without one answers `nothing`, and a `String` arrives wrapped.
- [ ] `test_julia_tooltip()`: a function definition answers its signature, and a
      node with no docstring answers the signature alone.
- [ ] Write the old and the new `test_substrate()` counts here. The IO map field
      count moves, and the count of passes moves with it.
- Tests: `test_widget_tooltip()`, `test_julia_tooltip()`, `test_substrate()`,
  `test_package_graph()`.

### Step 5 — a tooltip window that takes no focus

This step is backend work, and it closes Step 1 of [tooltip.md](tooltip.md).

- [ ] SDL: give the `:tooltip` style a flag set that does not take the focus.
      Try `SDL_WINDOW_UTILITY` and `SDL_WINDOW_SKIP_TASKBAR` first, and check the
      result on X11 and on Wayland. Fix the wrong comment at
      [source/sdl/Sdl.jl:424](../../source/sdl/Sdl.jl#L424) at the same time:
      `0x00000400` is `SDL_WINDOW_MOUSE_FOCUS`.
- [ ] Add `get_screen_origin(backend, id) -> (x, y)` to the backend interface, and a
      method for each backend that has one. A backend that cannot say answers
      `nothing`, and the caller then places the window relative to itself.
- [ ] Web client: draw a window whose style is `:tooltip` as a positioned overlay
      in the page, not as a popup (§3.2b). It must never enter `pendingPopups`.
- [ ] A test opens a tooltip window and asserts that the main window keeps the
      keyboard focus.
- [ ] A test asserts that `get_screen_origin` answers the same origin that the window
      was opened at.
- Tests: `test_tooltip()`, and a new `test_tooltip_window()`.

### Step 6 — the interface shows a tooltip

- [ ] Add `TooltipProbeProjection` and `TooltipProbeIoMap` to `TooltipModule`:
      the Alt+press probe, the dwell timer, and the `OpenWindowOperation` it
      makes from what its `compute_tooltip` keyword answered. The keyword is why
      `ProjecturedTooltip` needs no dependency on `ProjecturedWidget` (§3.14).
- [ ] Derive the real position: the pointer, plus `get_screen_origin` of the window
      the pointer is in, plus an offset, held inside the screen. This closes
      Step 6 of [tooltip.md](tooltip.md).
- [ ] The shell composes it. `make_window_wrap(; tooltip = compute_tooltip)` turns
      it on, and a host passes its own function.
- [ ] The tooltip window draws with the content projections of the window it
      belongs to, through `make_opened_window_projections`. A computed tooltip is
      a syntax or a prose document, and it renders as nothing without them.
- [ ] Both binaries turn it on.
- [ ] `test_tooltip_probe()`: a probe over a widget with a tooltip answers one, a
      probe over a widget without one answers nothing, a probe under the dwell
      time answers nothing, a move to another widget replaces it, and two
      tooltips never stand at once. The last two cover Steps 5 and 8 of
      [tooltip.md](tooltip.md).
- [ ] Measure what the probe costs on a pointer move before it is turned on.
- Tests: `test_tooltip_probe()`, `test_tooltip()`, `test_application()`.

### Step 7 — the shell draws the chrome

- [ ] Wrap the content of the window in a `WidgetShell` inside the fold, and give
      the shell the size of the window. A shell with no size hugs its content
      (§2.6), which a window shell must not do.
- [ ] Add the generic `compute_context_menu(document)` to `DomainModule`, the widget
      method that reads a `context_menu` field, and
      `ContextMenuProbeProjection` with `ContextMenuProbeIoMap` in
      `WidgetModule`. What the generic answers opens through
      `OpenPopupOperation` (§3.6).
- [ ] Add one computed method, so that the generic is proved and not only
      declared: a JSON array answers a menu that offers to add an element.
- [ ] `WidgetShell.context_menu` becomes the menu of the window itself, and opens
      when no widget offers one.
- [ ] Build the menu bar, the toolbar and the status line of §3.7, and let a host
      append to each.
- [ ] omnet-julia: delete `_paint_windows!`, `CAMPAIGN_BACKGROUND` and the
      `background` keyword of `run_campaign_window`. The interface appends its
      own Run and Stop to the toolbar.
- [ ] Give the gallery's `shell = true` the new projection, so that the other
      plan can delete `example/workbench/` without taking the option with it
      (§2.7).
- [ ] A new `test_window_shell()`: every menu item runs the gesture it names, a
      greyed item is greyed when its wrapper is off, and the status line follows
      the focused tab.
- Tests: `test_window_shell()`, `test_widget_context_menu()`,
  `test_application()`; in omnet-julia `test_ide_window_wrap()`.

### Step 8 — Open and Save As, as dialogs

The File menu of Step 7 names them, so they are written here and not later.

- [ ] Add `FileSystemChooser` to `FileSystemModule`: a folder, its entries, a
      selected path and a typed name. It is a document, so `FileSystemToWidget`
      grows a printer for it and it draws through the projection the navigator
      already uses.
- [ ] `WidgetDialog` holds it, and `OpenPopupOperation` opens it, so the dialog
      rides the route §3.1 repaired.
- [ ] Open: the picker answers a path, and the window opens it in a new tab with
      `make_file_tab`, which the other plan leaves in the pane slice (§2.7).
- [ ] Save As: the picker answers a path, a `CompoundOperation` writes the
      `filename` of the `FileDocument` and then runs `SaveFileOperation`. This
      plan mints no operation (§3.14). A file with no name and a `Ctrl+S` opens
      the Save As dialog instead of declining, which is what
      [source/workbench/WorkbenchFile.jl:49](../../source/workbench/WorkbenchFile.jl#L49)
      calls future work today.
- [ ] **Needs Steps 7 and 8 of the other plan first** (§2.7). Until a tab holds a
      `FileDocument`, there is no `filename` to write.
- [ ] Both go on the File menu, and both get a key: `Ctrl+Shift+O` and
      `Ctrl+Shift+S`.
- [ ] The interface gets them too, because it has the navigator from Step 9 and
      the same File menu.
- [ ] `test_filesystem_chooser()` covers the document, and `test_file_dialog()`
      the two commands: a picker answers the path a person chose, an unnamed tab
      saved with `Ctrl+S` opens the dialog, Escape cancels and writes nothing.
      A test file is named for the source file it tests, so the first lives in
      `test/filesystem/document/FileSystemDocumentTest.jl` beside the other
      documents of that slice, and the second in `test/shell/FileDialogTest.jl`
      beside `source/shell/FileDialog.jl`.
- Tests: `test_filesystem_chooser()`, `test_file_dialog()`,
  `test_widget_dialog()`, `test_application()`.

### Step 9 — the file navigator in the interface

- [ ] **Needs Steps 7 and 8 of the other plan first** (§2.7).
- [ ] omnet-julia: add `ProjecturedFileSystem` to `package/OmnetIde/Project.toml`.
      One package, not the two §2.4 counted: the other plan moves `Workspace` and
      `WorkspaceToFileSystem` into that slice and deletes `ProjecturedWorkbench`.
- [ ] `run_omnet_ide` opens a file explorer tab on the project directory, in the
      first group.
- [ ] Add no dispatch entry. The file explorer and the `FileDocument` register
      their own natural rows, so the interface draws them by depending on the
      package.
- [ ] Set the closure cap of `IdeClosureTest` to the true number, and say in the
      test why it moved. Do not touch `CampaignUiClosureTest`: the campaign
      window gains nothing.
- [ ] Prove that the campaign window's closure did not change.
- [ ] A new test opens a Julia file and a Markdown file from the file explorer of
      the interface.
- Tests: in omnet-julia `test_ide_window_wrap()`, `IdeClosureTest`,
  `CampaignUiClosureTest`.

### Step 10 — the guides, and close

- [ ] Write `documentation/package/shell/shell.md`, which is the shape every
      per-slice guide takes: what the fold is, what each wrapper does, and how a
      host adds a menu, a button and a status field. Carry the one-line header
      that names its Kind, its Status and what it Stands on.
- [ ] Update [editor.md](../../documentation/package/kernel/editor.md) where it
      names the window.
- [ ] Update [tooltip.md](tooltip.md): its Steps 1, 5, 6 and 8 are closed here,
      and of its Step 7 only the type tooltip and the error tooltip remain.
- [ ] Update the omnet-julia guide that names `make_ide_window_wrap`.
- [ ] Update [README.md](../../README.md) if the quick start names a key.
- [ ] Move this plan to `plan/done/`.

## 5. Risks

| Risk | What is done about it |
| --- | --- |
| The field sweep of Step 4 touches 43 types and moves test counts. | Step 4 carries it alone and writes the old and the new count. A count that moves in another step is a fault of that step. |
| The two closure tests already fail on omnet-julia `main`. | Step 0 records the exact output. Step 9 sets one cap and proves the other closure did not change. |
| A menu item that does nothing teaches a person that the menu is a lie. | §3.7 puts only working commands on the menu. Step 8 writes Open and Save As, and the File menu gains them in that step and not before. |
| The Alt+press probe runs on every pointer move. | The probe runs only after the pointer rests for the dwell time, as `HoverProbeProjection` throttles idle motion today. Step 6 measures it before it is turned on. |
| Moving the fold could change what the interface does. | Step 1 changes one thing on purpose, the popup resolver, and nothing else. `test_ide_window_wrap()` is the proof for the rest. |
| A popup that never opened now opens, so a widget that was inert becomes live. | That is the repair, not a regression. Step 1 lists which widgets change: `WidgetSelect`, a submenu, and `WidgetContextMenu`. |
| **A tooltip window that takes the focus makes the editor unusable.** A wrong flag set is worse than no tooltip. | Step 5 lands the flags and the focus test **before** Step 6 turns any tooltip on. If no flag set keeps the focus on X11 and on Wayland, Step 5 stops and the owner decides; Step 6 does not start. |
| The flag set that works on X11 may not work on Wayland, macOS or Windows. | Step 5 checks the two this machine has and writes down what it could not check. A backend that cannot answer is named in the guide, not hidden. |
| The web client must draw a `:tooltip` window in the page, which is a second drawing path. | It is one branch in `client.js` at the point where a window is opened. Step 5 asserts that a `:tooltip` window never enters `pendingPopups`. |
| A computed tooltip runs while the person moves the pointer, and a slow one stalls the window. | `compute_tooltip` is called once the pointer has rested for the dwell time, and its answer is held until the pointer moves to another document. Step 4 keeps every method cheap: the Julia one reads a docstring that Julia already holds, and computes no layout. |
| Another plan removes the workbench under this one, and three steps here name what it moves. | §2.7 names every place, and Steps 3, 8 and 9 each say which of its steps they wait for. Steps 0 to 2 and 4 to 7 touch nothing it moves, so neither plan blocks the other for long. |
| A dialog is modal, and a modal that cannot be closed traps the person. | Step 8 gives every dialog an Escape that cancels and writes nothing, and tests it. |

## 6. Out of scope

- **Undo and redo.** They need an inverse for every operation and a log on the
  editor. The owner ruled that a plan of its own carries them; write that plan
  before this one closes, so the pointer does not dangle.
- **Find in document.** The command palette searches gestures, not text. A find
  needs a search projection over the focused document.
- **A settings surface and a recent-files list.** Nothing asks for them yet.
- **The type tooltip and the error tooltip of [tooltip.md](tooltip.md)**, which
  are what remains of its Step 7. Its Steps 1, 5, 6 and 8 are closed by Steps 5
  and 6 of this plan, and the documentation tooltip of its Step 7 by Step 4.
- **The NED and INI formats in the navigator.** omnet-julia registers no natural
  format today. Its files open as plain text until it does.
- **The campaign window.** It stays small on purpose.
