# A press on a menu name opens its menu, and every popup opens where its widget is

> **Status (2026-09-25): in progress** on the branch `popup-position`, worktree
> `projectured-julia-popup-position`. The owner chose the design below, in which
> a popup carries a position that each reader moves into its own frame on the
> way up, and took the three recommendations of "Decisions".

A press on "File", "View" or "Help" in the menu bar of the application window
does nothing, and no message says why. The same causes break the other popups:
a `WidgetSelect` inside a pane, a `WidgetContextMenu`, and the context menu of
the window. This plan fixes every popup, not only the menu bar.

## The faults (found 2026-09-25)

Each fault was found with an offscreen probe over `make_application_window`:
real presses at the drawn position of a label, read through the whole window
projection, with traces of the readers and of the forward maps.

- **F1. The anchor misses steps.** A popup opener takes its anchor from
  `ctx.reference` at print time. `make_clipboard_projection` builds a
  `ChainingProjection`, and a chain gives each stage the context of the chain's
  input. So the shell prints with the reference of the clipboard, and the anchor
  of "File" is `.windows[1].content.menu_bar.elements[1]` instead of
  `.windows[1].content.content.menu_bar.elements[1]`. The shell also gives its
  pane area no `content` step, so a dropdown inside a pane has a wrong anchor
  even without the chain.
- **F2. The palette wraps a point in a path.** `get_anchor_point` accepts only a
  bare `PointReferenceStep`. `CommandPaletteDecoratorProjection` answers the
  point of its inner layer inside a path, `elements[1]` of its canvas. The
  docstring of `map_reference_forward` in
  [ProjectionInterface.jl](../../source/kernel/projection/ProjectionInterface.jl)
  says "coordinates accumulate, paths stay paths", and the palette breaks it.
- **F3. No row draws the popup.** A popup window holds the `WidgetMenu` of the
  dropdown. `ScreenToScreen` draws the content of an opened window with the rows
  of `make_opened_window_projections`, and the binary gives the rows of
  `make_application_content_projections`, which name no widget. The output of
  the window is the `WidgetMenu` document itself, not a canvas.
- **F4. An unclaimed press comes back as the operation.** Stage 1 of the
  clipboard chain prints the content with `IdentityProjection`, and its reader
  (`source/projection/generic/Identity.jl`) returns any payload, a raw
  `MousePress` too. When no layer below claims a press, the chain asks stage 1,
  and the answer is the event itself. `ContextMenuProbeProjection` sees an
  answer and lets it win, so a right press in the JSON tab opens no context
  menu. A left press on an empty part of the tab also comes back as the event.
  It is not checked what the editor does with such an answer.
- **F5. A row takes the right press.** The Files navigator answers a right press
  with a `ReplaceSelectionOperation`, because a press selects the row. The probe
  lets the closer answer win, so a right press on a row opens no menu.
- **F6. A history records a popup.** Found in step 3. `is_undo_step`, the filter
  of `UndoBufferToAnyProjection`, does not skip a popup, so a popup that a widget
  inside a pane opens comes up wrapped in a `RecordUndoOperation`, and the window
  manager does not find it. The undo package does not depend on the screen
  package, so its filter can not name the popup.

## Why the clipboard is a chain

[clipboard-os-bridge-and-run-example-wrapper.md](../done/clipboard-os-bridge-and-run-example-wrapper.md),
step 6, records it. The first version was a nesting arm, the shape of the Lisp
original: `document/clipboard->t` is an arm of a `type-dispatching` under
`recursive`, and its printer recurses into the content with the reference
extended by `content-of`. The output of the clipboard is a computed cell, so
that Ctrl+/ switches the content and the slice with a cell write. At the top of a
pipeline nothing read the cell, and the cell reached the SDL backend:
`write_to_devices: …content is Cell, expected GraphicsCanvas`. A chain reads the
cell of a stage between two stages, so the clipboard became stage 1.

A scratch script (2026-09-25) made the clipboard a nesting arm again. The top
output of a wrapped JSON document is a `GraphicsCanvas`: an IO map now gives the
value of its `output` cell when code reads `iomap.output`
([IoMapDefaults.jl](../../source/kernel/iomap/IoMapDefaults.jl)). So the reason
for the chain is gone. The chain costs F1, F4 and a reader order that is the
reverse of the Lisp and of
[clipboard.md](../../documentation/package/clipboard/clipboard.md): the content
reads a key before the clipboard.

## The design: a popup carries a position, and each reader moves it

The owner's design. A popup does not record where it is in the document at
print time. It answers a position in the frame of the widget that opens it, and
each reader on the way up moves the position into its own frame. The reader
that moved the press into a child's frame on the way down is the reader that
moves the popup back on the way up, so the two directions use one piece of
knowledge and can not disagree. When the popup reaches the screen, it is in
screen coordinates.

The traced press on "File", with the numbers of the scratch run:

1. The item answers a popup at (0, 32) in its own frame: below itself, with the
   size 109 × 56.
2. The menu placed the item at (2, 2), so it moves the popup to (2, 34).
3. The shell placed the menu bar band at (0, 0), so the popup stays at (2, 34).
4. The hover tracker, the selection walk, the clipboard, the probes, the palette
   and the recorder place nothing, so the popup passes unchanged. The palette
   places its inner drawing at (0, 0).
5. The window is at (100, 100) on the screen, so the popup is at (102, 134). The
   window manager opens a window there.

The parts:

- **D1. The operation.** `OpenPopupOperation(; id, x, y, width, height,
  auto_dismiss, content)`: `(x, y)` is the top left of the popup in the frame of
  the reader that holds the operation. The `anchor`, `dx` and `dy` fields go.
- **D2. The rule on the way up.** A reader that reads a child which it placed at
  an offset moves a popup in the child's answer by that offset: the entry offset
  plus the origin of the child's canvas, as `shift_child_image` computes it for
  a point. A scroll pane moves it by its scroll offset. A zoom pane
  (`WidgetTransformPane`) moves the position with its transform and keeps the
  size, because a popup is a window with a size in screen pixels. One function
  does the moving, with a method for `OpenPopupOperation`, one for
  `CompoundOperation` and one for `WrappingOperation`, and a catch-all that
  returns any other operation unchanged. The proposed name is
  `shift_operation_position(operation, dx, dy)`. It is declared in
  `ProjecturedGraphics`, which the layouts, the widgets and the screen all
  depend on, and `ProjecturedScreen` adds the method for `OpenPopupOperation`.
- **D3. Where the rule applies.** Every popup opens from a press today: a left
  press for a submenu and a `WidgetSelect`, a right press for the two context
  menus. So the rule applies where a reader moves a pointer event into a
  child's frame. A first grep finds these helpers:
  - `WidgetToGraphics.jl`: `_route_to_children`, `_route_composite_event`,
    `_select_in_band`, `_read_band_event`, `_route_split_event`,
    `_route_active_tab`, `_route_selected_tab`, `_route_toolbar_press`, and the
    readers of `WidgetScrollPane` and `WidgetTransformPane`;
  - `LayoutToGraphics.jl`: `_route_to_children`, `_route_layout_event`,
    `_route_to_children_reverse`, `_route_stack_event`;
  - `GraphLayoutToGraphics.jl`: `_route_click`, and the reader of the chart plot.

  Step 3 finds every place with a grep for a translated event, because a place
  that is missed puts the popup at a wrong position and no error says so.
- **D4. The screen.** The layer that knows the window of the event adds the
  screen origin of the window and turns the popup into an `OpenWindowOperation`
  with the style `:floating`. `WindowManagingProjection` opens it, as today. A
  popup inside a popup window, such as a submenu of a dropdown, gets the origin
  of that window. `WidgetPopupResolverProjection`, `make_popup_screen_wrap` and
  `get_anchor_point` go; the `screen_wrap` keyword of `run_window_editor` stays,
  because it is a general hook.
- **D5. The openers.** The submenu item answers `(0, height + gap)`, below
  itself. `WidgetSelect` answers below itself. `WidgetContextMenu` answers the
  press point in its own frame. `ContextMenuProbeProjection` answers the press
  point in its own frame: it already has it, so it needs no anchor either.
- **D6. The row that draws a popup.** `make_opened_window_projections` gives a
  row `WidgetDocument => WidgetToGraphics(…)`, because every popup that the shell
  opens holds a widget. The row takes the font and the measure of the shell
  projection. This fixes F3.
- **D7. `IdentityProjection` declines a raw gesture.** For a `KeyPress`, a
  `KeyDown`, a `MousePress` or a `CollectIntents` it answers `read_gesture` of
  its input, as the default leaf reader of the kernel does; it passes every
  operation through unchanged. This is the rule of the memory about pass-through
  readers, and it fixes F4 in every chain that has an identity stage.
- **D8. The clipboard is a nesting arm again**, as in the Lisp and in its first
  version. `make_clipboard_projection` returns a `RecursiveProjection` of a
  `TypeDispatchingProjection` with the clipboard and
  `Any => NestingProjection(projection)`. The printer prints the stored slice
  only while it shows. The reader reads its own keys first, as `clipboard.md`
  says. This removes the identity stage from every window and gives every
  reference below the clipboard its `content` step.
- **D9. The shell gives its pane area the `content` step** in the context of the
  print, so every reference below the shell is complete. After D1 no popup
  needs it, but `ReferenceDispatchingProjection`, the transcript of the
  conversation and the place that a fault record names read `ctx.reference`.
- **D10. A right press on a row.** See "Open decisions". The recommendation: when
  the closer answer to a right press is only a selection, the probe answers the
  selection and the menu together, in a `CompoundOperation`. A person then
  selects a row and opens its menu with one press, as on a desktop.

`map_reference_forward` keeps every other job: selection wiring, the ring around
a selected widget, and the anchored layout. Only the position of a popup moves
to the readers.

## Steps

- [x] 1. **D7, the identity reader.** Test: a chain with an identity stage
  answers `nothing` to a press that no stage claims. Run the narrow suites of the
  projection algebra and of the clipboard, then `test_substrate()`, because
  identity stages are everywhere.

  Done. The reader answers `read_gesture` of its input for a `KeyPress`, a
  `KeyDown`, a `MousePress` and a `CollectIntents`, passes an `Operation`
  through, and answers `nothing` for any other payload, such as a `MouseMove`.
  `test_identity()` in `test/substrate/projection/IdentityTest.jl`: 6 pass.
  `test_clipboard()`: 201 pass. `test_substrate()`: 80868 pass, 3 fail, 2 error,
  1 broken; `main` gives 80862 pass and the same failures (the splitter drags
  inside a tabbed pane and along the y axis), so the 6 more are the new test.
- [x] 2. **D8, the nesting clipboard.** First list every key that the clipboard
  and a content both answer, and check each one against the new order. Tests:
  the clipboard suite, Ctrl+/ still switches the view, the slice prints only
  while it shows, and the application test.

  Done. No gesture table outside the clipboard binds Ctrl+/, Ctrl+C,
  Ctrl+Shift+C, Ctrl+X, Ctrl+N, Ctrl+V or Ctrl+Shift+V. The chain already let
  the clipboard win for these keys: when a later stage answered, the chain
  asked the clipboard with the gesture, and its own table replaced the answer.
  So the new order changes the answer to no key.

  The slice printer and the collection printer print the child on display
  through `reconcile_child_iomap`, only while it is on display. The collection
  draws its `elements` vector as one child, as stage 2 of the chain drew it; its
  reference maps peel `elements` and delegate the rest to that child. Both
  readers gained a branch for a routed intent, as `UndoBufferToAnyProjection`
  has, because the chain did that work before and the menu commands send their
  edits with a route. Both delegate every other gesture to the child on
  display.

  Tests: a new case in `ClipboardTest.jl` shows that the content prints at
  `content`, that the slice prints at `slice` only after a toggle, and that an
  unclaimed press gives no operation. `test_clipboard`, `test_text_clipboard`,
  `test_command_palette`, `test_command_palette_decorator`,
  `test_window_shell`, `test_window_wrap`, the two widget shell tests and
  `test_application`: 783 pass, 0 fail.
- [x] 3. **D1 to D5, the position on the way up.** Find every place of D3 with a
  grep. Tests with real presses in the window of `make_application_window`:
  "File" opens a popup window at the position under the label; a
  `WidgetSelect` in a pane opens its dropdown under the select, also inside a
  scrolled pane and a zoomed pane; a right press on a `WidgetContextMenu` opens
  its menu at the press point. `AnchorPointTest.jl` keeps its forward-map cases
  and loses the resolver cases; `WindowWrapTest.jl` loses the test of the
  popup wrap.

  Done. Decisions and facts of the implementation:

  - **Two functions, not one.** `map_operation_position(operation, move)` in
    `source/graphics/OperationPosition.jl` moves every position through a point
    map, with methods for `CompoundOperation` and `WrappingOperation` and a
    catch-all; `ProjecturedScreen` adds the method for `OpenPopupOperation`.
    `shift_operation_position(operation, dx, dy)` is its common case. The zoom
    pane needs the point map, because its transform scales a position.
  - **A popup is marked as view state (F6).** Each opener answers
    `ReplaceViewStateOperation(OpenPopupOperation(…))`: the kernel marker for "not
    an edit", which every history skips. It adds no mechanism. The window layer
    of `ScreenToScreen` (`_open_popup_windows`) turns the popup into an
    `OpenWindowOperation` at the window's origin and drops the marker, so the
    window manager finds it as before.
  - **The rule applies at a place that reads a child with a press.** A place
    that read the child with `(lx, ly)` for its own `(x, y)` shifts the answer
    by `(x - lx, y - ly)`: `_route_to_children` in both files,
    `_route_composite_event` (the composite and the toolbar),
    `_route_split_event`, `_route_to_children_reverse`, the active tab, the
    card, the dialog, the context menu widget, the text content, the scroll pane
    and the accordion. The zoom pane moves the position through its transform.
    Not changed: `_select_in_band` (an Alt press selects), `_read_band_event`
    and every drag (a down, an up or a move opens no popup).
  - **The graph drops a popup.** `_route_click` of the graph answers only a
    selection or an operation that travels unchanged, so a popup of a widget
    inside a node is dropped, as before. Out of scope.
  - **Removed:** `WidgetPopupResolver.jl`, `get_anchor_point`,
    `make_popup_screen_wrap` with its seven calls, and the `anchor` fields of the
    IO maps of the menu item, the select and the context menu widget.
    `AnchorPointTest.jl` keeps its forward-map cases with a local helper.
  - **The window origin** is added as `_map_window` added it before; −1 means
    that the backend chooses the position.

  Tests: new cases for a submenu below its item, a menu bar and a layout that
  move a popup, a select in a scrolled pane and in a zoomed pane, the context
  menu probe at the press, a select that drops down as a window below itself in
  a window scene, and a real press on "File" in the application window.
  `test_widget_menu`, `test_widget_select_dropdown`, `test_widget_context_menu`,
  `test_anchor_point`, `test_widget_transform_pane`, `test_scroll_pane_hover`,
  `test_widget_tooltip`, `test_tooltip_probe`, `test_context_menu_probe`,
  `test_window_wrap`, `test_window_shell`, `test_clipboard`, `test_identity`
  and `test_application`: 863 pass, 0 fail.

- [x] 4. **D6, the row.** Test: the popup window of "File" draws "New tab" and
  "Close tab", and a press on "New tab" opens a tab and closes the popup. The
  same for "Help" and "Documents".

  Done. `make_opened_window_projections` ends with the rows of
  `WidgetToGraphics(font_ubuntu_regular_20; measure).dispatch`, one for each
  widget and each layout, after the rows of the host. It names no abstract type,
  so the shell needs no dependency on `ProjecturedLayout` for `LayoutDocument`.

  **The place decides before the type.** In `make_window_scene_projection`, the
  rows by type came before the reference dispatch that gives the first window's
  content to the host projection. A row for `WidgetShell` would then draw a
  window whose content is a shell, as a window without the clipboard has. The
  projection is now a `ReferenceDispatchingProjection` under the
  `RecursiveProjection`: the screen goes to the manager, the first window's
  content to the host, and every other place to the rows by type.

  Tests: a popup window with a `WidgetMenu` draws "New tab" and "Close tab"; a
  first window whose content is a `WidgetShell` is printed by its host
  projection; in the application window a press on "File" opens a popup window
  that draws "New tab" and "Close tab", and a press on "New tab" in that window
  closes it and opens a tab. The press on "Help" follows the same path.
  `test_window_wrap` 27 pass; `test_window_shell`, `test_tooltip_probe`,
  `test_widget_tooltip` and `test_application`: 493 pass with the one case of
  `test_window_wrap` that the fix of its reading made pass.
- [x] 5. **D10.** Test: a right press on a row of the
  navigator selects it and opens the menu of the row; a right press in the JSON
  tab opens the menu of the window.

  Done. `ContextMenuProbeProjection` treats an answer that only moves the
  selection (`_is_selection_only`: a `ReplaceSelectionOperation`, a wrapper of
  one, or a compound of only such) as no answer to a right press: it answers
  the selection and the marked popup in one `CompoundOperation`. The window
  manager opens the popup and passes the selection on.

  **The application offers no context menu.** Only a `WidgetShell` answers
  `compute_context_menu`, with its `context_menu` field, and the shell of the
  application has none. So in the application window a right press opens
  nothing, with or without these faults; the tests use a projection whose
  reader answers every press with a selection, and the shell with a menu that
  the probe test already has. A right press in the JSON tab now gives no
  operation, where it gave the press itself (F4).

  Tests: `test_context_menu_probe`, `test_tooltip_probe`,
  `test_widget_tooltip`, `test_window_wrap` and `test_application`: 402 pass,
  0 fail.
- [x] 6. **D9, the `content` step of the shell.** Test: the reference that a
  printer gets for a pane below the shell names `content`.

  Done. Every band of `WidgetShellToGraphicsCanvas` prints with the step of its
  field: `menu_bar` as before, and now `toolbar`, `status_bar`, `content` and
  `overlay`. The forward map of the shell (`_shell_field`) names the status bar
  too. Tests: a shell prints its content at `.content`, and in the application a
  right press that no layer claims gives no operation (F4).
  `test_window_shell`, the two widget shell tests, `test_window_wrap`,
  `test_context_menu_probe` and `test_application`: 496 pass, 0 fail.
- [x] 7. **omnet-julia.** `IdeWindow.jl` imports `make_popup_screen_wrap`; the
  import and the keyword go. Land after projectured-julia, and run
  `Pkg.resolve()` where a manifest names a changed package.

  Done on the branch `popup-position` of omnet-julia. `IdeWindow.jl` imported
  the wrap and never called it, so the IDE window had no popup wrap and its
  popups never opened; with this design they need none. The IDE builds its
  popup rows with `make_opened_window_projections`, so its popups draw too. No
  package gains or loses a dependency, so the closure guards do not move.
  Tested in a temporary environment that reaches both worktrees:
  `test_ide_window_wrap` and `test_ide_file_navigator`, 41 pass; the naming
  checks of omnet-julia find nothing. Land after projectured-julia.
- [x] 8. **The documents.** `widget.md`, `screen.md`, `shell.md`,
  `clipboard.md`, the note in the docstring of `map_reference_forward` that a
  popup position is not its job, and the anchored-layout document if it names
  the resolver.

  Done: `widget.md`, `screen.md`, `shell.md`, `clipboard.md`, `graphics.md`
  (the two functions), `undo.md` (a popup is not recorded),
  `generic-projections.md` (the identity reader), `own-project-guide.md` and
  the docstring of `map_reference_forward`. The anchored layout is
  `AnchoredLayout`, a placement of layout children, and it never named the
  resolver, so its document does not change.
- [ ] 9. Verification against a baseline of `main`, and the move of this plan to
  `plan/done/`.

## Decisions (owner, 2026-09-25)

- **D10:** a right press on a row selects it and opens the menu, in one
  `CompoundOperation`.
- **The name** of the function of D2 is `shift_operation_position`.
- **The popup wrap:** `make_popup_screen_wrap` goes.

## The options before the owner's design

The first version of this plan had seven options. The owner's design replaces
a to f:

- a. the clipboard as a nesting arm, which D8 keeps for its own reasons;
- b. a new projection that gives stage 2 of the chain the right context;
- c. a chain that gives each stage the context of its input;
- d. the anchor built on the way up, which the owner's design makes exact;
- e. a palette that answers a point as a point;
- f. a `get_anchor_point` that follows a path;
- g. the row that draws a popup, which D6 keeps.

With a and e alone, a scratch script opened the popup of "File" at (102, 134),
the same position as the traced run of the owner's design. That fix left the
dropdowns in a pane broken (the `content` step of the shell) and kept two
derivations of one position that must agree.
