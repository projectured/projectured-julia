# A toolbar item looks like a button

> **Status:** in progress since 2026-10-04, in the worktree
> `projectured-julia-toolbar-item` on the branch
> `toolbar-item-looks-like-a-button`. Written on 2026-10-04 at the owner's
> request. The owner chose the look on 2026-10-04 (section 3) and answered the
> two questions the same day (section 6). No question is open.

## 1. The request

The owner wrote on 2026-10-04:

> when toolbar items contain buttons, the buttons are lighted when the mouse is
> over but they don't look like a button. how can we make them more like button
> which can be pressed and has border or something?

Claude gave three options: a button only under the pointer, a button at all
times, and a pressed look that both need. Claude recommended the first with the
pressed look. The owner wrote: "I agree with your recommendation".

## 2. The facts (2026-10-04)

1. The toolbar of a window is a row of `WidgetToolbarItem`s
   ([WindowChrome.jl](../../source/platform/shell/WindowChrome.jl),
   `make_window_toolbar`). No example holds a `WidgetToolbarItem`. The
   `widget_toolbar` example and the gallery hold `WidgetMenuItem`s. Only the
   color probe of
   [WidgetColorTest.jl:113](../../test/platform/projection/WidgetColorTest.jl#L113)
   draws toolbar items.
2. The item is flat by its docstring: "It is flat: it draws a surface behind
   itself only while the pointer is on it"
   ([WidgetDocument.jl:735](../../source/platform/widget/WidgetDocument.jl#L735)).
3. `WidgetToolbarItemToGraphicsCanvas`
   ([WidgetToGraphics.jl:606](../../source/platform/widget/WidgetToGraphics.jl#L606))
   has `border`, `border_color` and `padding_color`. Each is zero or
   transparent by default. It has no `corner_radius`, no `layer_pressed_color`
   and no stroke for the layer.
4. The printer
   ([WidgetToGraphics.jl:2753](../../source/platform/widget/WidgetToGraphics.jl#L2753))
   draws one hover layer with `_push_hover_layer!` and no radius
   ([WidgetToGraphics.jl:2782](../../source/platform/widget/WidgetToGraphics.jl#L2782)).
   The layer is a `GraphicsRect` whose size and color are cells of their own.
   At rest its size is 0 and the renderer skips it. So a light changes only
   the layer, and the test "a hover changes the layer of an item and nothing
   else" holds that
   ([WidgetToolbarTest.jl:50](../../test/platform/projection/WidgetToolbarTest.jl#L50)).
5. `_push_hover_layer!`
   ([WidgetToGraphics.jl:269](../../source/platform/widget/WidgetToGraphics.jl#L269))
   takes `hovered_color`, an optional `pressed_color` and `radius`. It has no
   border. A `GraphicsRect` takes `border_width` and `border_color`; the focus
   ring uses them with a radius.
6. The item has no `pressed` field. A press shows nothing until the action
   runs. `WidgetButton` has the pattern: a transient `pressed` field, which its
   reader writes with `_write_view_state` on a left `MouseDown` and `MouseUp`,
   and clears on the leave move
   ([WidgetToGraphics.jl:2111](../../source/platform/widget/WidgetToGraphics.jl#L2111),
   [WidgetDocument.jl:2934](../../source/platform/widget/WidgetDocument.jl#L2934)).
   The leave is a `MouseMove(-1, -1)` that `read_child_leave` sends to the
   child that held the pointer
   ([ChildMove.jl:106](../../source/platform/graphics/ChildMove.jl#L106)).
   The toolbar sends it through `_read_children_move`.
7. The toolbar gives its items a move, a press, a dwell and a scroll, but no
   down and no up
   ([WidgetToGraphics.jl:5939](../../source/platform/widget/WidgetToGraphics.jl#L5939)).
   The shell gives a down and an up to the band under the pointer
   (`_route_shell_down`, `_route_downup_to_children`,
   [WidgetToGraphics.jl:3455](../../source/platform/widget/WidgetToGraphics.jl#L3455)).
8. The focus rule. `read_child_event`
   ([LayoutToGraphics.jl:178](../../source/platform/layout/LayoutToGraphics.jl#L178))
   turns a left down with no modifier on a focusable child into a focus move
   only when the child answers nothing (`convert_to_focus_selection`,
   [Focus.jl:120](../../source/platform/focus/Focus.jl#L120)). An enabled
   `WidgetToolbarItem` is focusable
   ([WidgetDocument.jl:3056](../../source/platform/widget/WidgetDocument.jl#L3056));
   a disabled one is not. So an enabled item that answers the down with its
   pressed look keeps the focus in the content. A disabled item answers
   nothing, is not focusable, and the down gives nothing, as now.
   [widget.md:126](../../documentation/package/platform/widget/widget.md#L126)
   says: "`WidgetMenu` and `WidgetToolbar` give no down to their items, so a
   menu item and a toolbar item leave the focus in the content." That sentence
   changes for the toolbar; the result for the focus stays the same.
9. An Alt+press selects an item as a whole. `is_whole_selection_press` matches
   a `MouseClick` only
   ([WholeSelection.jl:16](../../source/platform/focus/WholeSelection.jl#L16)),
   so a down with Alt is not part of that rule.
10. The theme has what the look needs
    ([WidgetTheme.jl](../../source/platform/widget/WidgetTheme.jl)): `border`
    (`color_slate_300`, the border of a control), `border_width` (1), `radius`
    (6, the corners of a control), and the hover and pressed layers, `primary`
    at 12% and at 20% (`_get_hover_layer`, `_get_pressed_layer`). A
    `WidgetButton` uses these same values for its border, its corners and its
    layers.
11. A `.pred` file writes every field of a document but `selection` and
    `mouse_target` (`pred_arguments`,
    [PredFile.jl:115](../../source/platform/serialization/PredFile.jl#L115);
    `is_view_state_field`, `DocumentDefaults.jl:55`). A type with no keyword
    constructor is read back from all its fields, and a field that the file
    does not give is an error (`make_pred_document`). `WidgetToolbarItem` has a
    positional `content`, so a file saved before this change, if it holds a
    toolbar item, does not load after it. **Found on 2026-10-04: a saved window
    holds no toolbar.** `pred_arguments(shell::WidgetShell)` leaves out the
    bands, because their actions hold callbacks and the binary builds them at
    each start
    ([WidgetDocument.jl:3121](../../source/platform/widget/WidgetDocument.jl#L3121)).
    The test "a saved user interface holds the window, and the binary its
    bands" of `WindowShellTest.jl` holds that. No example held a toolbar item
    before this change. So no file needs a value for `pressed`.
12. No file that this change touches is sealed (`SEALING.md`).
13. The branch `projection-styles` (45 commits ahead of `main` on 2026-10-04)
    changes the same constructor in two places: `theme::ScaledWidgetTheme`
    becomes `theme`, and `icon_scale` becomes `icon_size`. The branch that lands
    second adapts the constructor of `WidgetToolbarItemToGraphicsCanvas`.
14. `read_container_gesture` returns a down and an up as they are, because it
    reads only a dwell and a right click
    ([ChildMove.jl:73](../../source/platform/graphics/ChildMove.jl#L73)). So
    the toolbar can send a down and an up through `_route_toolbar_gesture`,
    which re-roots the answer into `elements[i]`.

## 3. The decisions

- **D1. Flat at rest, a button under the pointer.** At rest the item draws
  nothing behind its icon, as now. Under the pointer it draws a rounded surface
  with a 1 px border. While the left button is held on it, the surface is
  darker. This is the owner's choice of 2026-10-04. Qt calls it `autoRaise`; the
  GNOME header bar does the same.
- **D2. The look of a `WidgetButton`.** The border is `StyleStroke(theme.border,
  theme.border_width)`, the corners are `theme.radius`, the lit surface is the
  hover layer and the held surface is the pressed layer. These are the values
  that a `WidgetButton` draws, so a lit toolbar item has the outline of a
  button. No new color comes into the theme, so
  [one-coherent-color-set.md](one-coherent-color-set.md) can recolor the item
  with every other control.
- **D3. The border is on the layer.** The border is a part of the hover layer,
  not of the box of the item. The layer already reads the pointer and `pressed`
  in cells of its own, so a light still changes the layer and not the element
  list or the size. The item keeps its size, and the toolbar does not lay out
  again.
- **D4. Three new style fields.** `WidgetToolbarItemToGraphicsCanvas` gets
  `corner_radius::Int`, `layer_pressed_color::StyleColor` and
  `layer_stroke::StyleStroke`. Each takes its default from the theme, as the
  other fields do. The names follow
  `[<variant>_]<part>[_<state>]_<kind>`
  ([widget.md:70](../../documentation/package/platform/widget/widget.md#L70)):
  `layer_stroke` is the stroke of the layer in each state that shows it.
  `corner_radius` is the name that `WidgetButton` uses.
  [a-projection-holds-its-styles.md](a-projection-holds-its-styles.md) moves
  these fields later with all the others.
- **D5. The pressed state copies `WidgetButton`.** The item gets a transient
  `pressed::Bool` field. Its reader writes it with `_write_view_state` on a
  left down and a left up, and clears it on the leave move. No new operation
  and no new channel.
- **D6. The toolbar gives a down and an up to the item under the pointer**,
  through `_route_toolbar_gesture`, as it gives a press (fact 14). The focus
  stays in the content by fact 8.
- **D7. A new example, `widget_toolbar_item`.** It is a toolbar of
  `WidgetToolbarItem`s: one with an icon, one disabled, and one with a label and
  no icon, which is the content of the color probe. The probe of
  `WidgetColorTest.jl` then takes the example. The `widget_toolbar` example
  keeps its menu items. The owner agreed on 2026-10-04 (Q1).

## 4. What does not change

- The look at rest. So the widget images stay equal (fact 1).
- `WidgetButton` and `WidgetMenuItem`. `_push_hover_layer!` gets an optional
  keyword, and a caller that does not give it draws as now.
- A menu bar. The name of a menu on a bar is not a button on a desktop, so it
  keeps its flat light.
- The keys. A toolbar item answers no key now, and this plan adds none.

## 5. Steps

- [x] **0. Worktree and baseline.** Make a worktree of `main` on the branch
  `toolbar-item-looks-like-a-button`. On the clean `main`, write the widget
  images: `julia --project=environment/all tool/widget-images.jl write before`.
  **Done 2026-10-04:** the worktree is `projectured-julia-toolbar-item`, from
  `fa9182383`. The baseline drew 42 of 42 images into
  `/var/tmp/toolbar-item/before`, before any edit.
- [x] **1. The lit look.** **Done 2026-10-04:** `test_widget_toolbar()`
  passes, 66 of 66 (60 before, and 6 new).
  - Add `corner_radius` (default `theme.radius`) and `layer_stroke` (default
    `StyleStroke(theme.border, theme.border_width)`) to
    `WidgetToolbarItemToGraphicsCanvas` and to its theme constructor.
  - Give `_push_hover_layer!` an optional keyword `stroke = nothing`. When a
    stroke is given, the layer rect gets `border_width` and `border_color` from
    it. Its size and color stay cells, as now.
  - The printer of the item passes `radius = p.corner_radius` and
    `stroke = p.layer_stroke` to the layer, and `radius` to `_push_box_parts!`.
  - Test, in `WidgetToolbarTest.jl`: a lit item has one layer at the size of the
    item, with the radius, the border width, the border color and the hover
    color of the theme. The test "a hover changes the layer of an item and
    nothing else" passes without a change.
  - Commit.
- [x] **2. The pressed look.** **Done 2026-10-04:** the docstring of
  `WidgetToolbarItem` changed in this step, with the field, so step 4 changes
  only `widget.md`. The test under a shell is in `WidgetSelectionTest.jl`, beside
  "a press under a shell gives the focus to the control under the pointer". It
  drives the projection and not an `Editor`, as its neighbours do. The step 5
  live check drives the real editor. `test_widget_toolbar()` passes 82 of 82
  (66 before, 16 new). `test_widget_selection()` and
  `test_widget_button_behavior()` pass with no failure.
  - Add `pressed::Bool` to `WidgetToolbarItem` after `style`, as in
    `WidgetButton`. The constructor gives `Cell(false)`. The docstring says
    that it is transient pointer state.
  - Add `layer_pressed_color` (default `_get_pressed_layer`) to the projection,
    and pass it to `_push_hover_layer!` as `pressed_color`.
  - The reader of the item: on an enabled item, a left `MouseDown` writes
    `pressed = true`, and a left `MouseUp` writes `pressed = false`. A leave
    move writes `false` when `pressed` is true. The bound gestures of the item
    come first, as now. A disabled item writes nothing.
  - The reader of the toolbar gives a `MouseDown` and a `MouseUp` to the item
    under the pointer through `_route_toolbar_gesture`, as a press (fact 14).
  - Tests:
    - a down on an item through the toolbar answers the write of `pressed`;
      after it, the layer shows the pressed color; an up gives back the hover
      color;
    - a down, then a move off the item, clears `pressed`;
    - a disabled item answers a down with nothing, and `pressed` stays false;
    - in an `Editor` with a `WidgetShell` whose content holds a focused text
      box: a down, an up and a press on a toolbar item run the action and leave
      the selection of the window where it was;
    - the Alt+press tests of the toolbar pass without a change.
  - Commit.
- [x] **3. The example (D7).**
  - `make_widget_toolbar_item_document_example` in `WidgetDocumentExample.jl`,
    and `widget_toolbar_item_example` in `PlatformExamples.jl`, with the
    exports of `ProjecturedPlatformExample` and `ProjecturedExample` and the
    list of `ProjecturedExamples.jl`.
  - `WidgetColorTest.jl` takes the example in place of
    `_make_toolbar_item_probe`.
  - `tool/widget-images.jl` lists `widget_toolbar_item`.
  - Test: `test_printer`, `test_reader` and `test_repl` of
    `widget_toolbar_item_example`.
  - Commit.
  - **Done 2026-10-04.** `test_example` is not the check for a widget example.
    The navigation sweep skips every widget example but `widget_text`, and the
    type-in sweep covers five text examples (`ExampleSweeps.jl`). The
    `widget_toolbar` example on this branch fails `test_example` in the same
    way: 1 navigation check and 78 type-in checks. So the new example takes the
    three checks that the sweeps give a widget example: they pass, 1143 of
    1143. `test_widget_colors()` passes, 74 of 74.
- [x] **4. The documents.** **Done 2026-10-04:** the docstring changed in
  step 2. No other guide says that a toolbar item is flat or gives no down.
  - The docstring of `WidgetToolbarItem`: flat at rest, the outline of a button
    under the pointer, and the darker surface while it is held.
  - [widget.md](../../documentation/package/platform/widget/widget.md): line
    70, the toolbar item holds the pressed layer and a stroke on its layer;
    line 126, the toolbar gives the down to its items, and an item answers it
    with its pressed look, so the focus stays in the content.
  - The color catalog: `one-coherent-color-set.md` is not in git yet, because
    another session writes it. This branch does not change it. The new use for
    its catalog: `border` is the outline of the layer of a toolbar item.
  - Commit.
- [ ] **5. The checks.**
  - Narrow tests: `test_widget_toolbar()`, `test_widget_button_behavior()`,
    `test_widget_colors()`, `test_pointer_light()`, `test_window_shell()`.
  - Images: `tool/widget-images.jl write after`, then `compare before after`.
    Expect the 42 images of the baseline to be equal, because the look at rest
    does not change, and `widget_toolbar_item` to be new.
  - The live window: open the editor with the window chrome. Push SDL events:
    a move onto a toolbar button, a left down, a left up. Keep one frame at
    rest, one lit and one held. The owner looks at the three frames.
- [ ] **6. Report, then ask.** Report the commits, the test results, the image
  compare and the frames. Land on `main` only when the owner says so. Then move
  this plan to `plan/done/`.

## 6. Answered questions

- **Q1. The `widget_toolbar` example.** It shows `WidgetMenuItem`s, so no
  example showed the new look. The owner answered on 2026-10-04: "we can add a
  toolbar example, that is fine". So D7 adds a new example, and step 3 makes it.
- **Q2. A file that holds a toolbar item** (fact 11). A saved window leaves out
  its bands, so no saved file holds the toolbar of a window. Nothing to decide.
