# Widget

> **Kind:** design · **Status:** current · **Stands on:** [graphics.md](../graphics/graphics.md), [layout.md](../layout/layout.md), [focus.md](../focus/focus.md)

`ProjecturedWidget` holds the documents of a user interface, such as a button, a card, a table, a split pane and a tab, and the projection that draws them to a `GraphicsCanvas`. It also connects the objects of a domain to widgets, and opens a popup or a dialog as a window. This document says how a widget tree is drawn, how a press and a key reach the right widget, and where the traps are.

<img width="396" alt="Widget example" src="../../../asset/image/example/widget.png">

## How it works

### The documents

`WidgetDocument` is the abstract root, and 44 `@document` types subtype it:

| Kind | Types |
| --- | --- |
| Text and values | `WidgetLabel`, `WidgetText`, `WidgetTextarea`, `WidgetBadge`, `WidgetAvatar`, `WidgetAlert`, `WidgetProgress`, `WidgetSkeleton`, `WidgetHighlight`, `WidgetSeparator`, `WidgetTooltip`, `WidgetStatusBar` |
| Controls | `WidgetButton`, `WidgetCheckbox`, `WidgetSwitch`, `WidgetToggle`, `WidgetToggleGroup`, `WidgetRadioGroup`, `WidgetSlider`, `WidgetSpinBox`, `WidgetSelect`, `WidgetOption`, `WidgetScrollBar` |
| Menus and bars | `WidgetMenu`, `WidgetMenuItem`, `WidgetContextMenu`, `WidgetToolbar`, `WidgetToolbarItem` |
| Containers | `WidgetComposite`, `WidgetShell`, `WidgetTitlePane`, `WidgetCard`, `WidgetAccordion`, `WidgetAccordionItem`, `WidgetSplitPane`, `WidgetTabbedPane`, `WidgetTabPage`, `WidgetScrollPane`, `WidgetTransformPane`, `WidgetDialog` |
| Data | `WidgetTable`, `WidgetList`, `WidgetTree` |
| Placeholder | `WidgetInsertion`, the type-replace buffer of the domain |

Two values of the package are not widgets. `Action` is a `@document` for a command, and `WidgetTreeNode` is a plain `struct` for a row of a tree. `WidgetToolButton`, `WidgetMessageBox`, `WidgetInputDialog` and `make_embed_card` are builders that return one of the types above.

Most widgets have `visible`, a `tooltip`, and the box fields `margin`, `border` and `padding` with a color for each. An interactive widget also has `enabled`: its reader returns `nothing` for every event while `enabled` is `false`, and its printer uses the muted colors of the theme. Some cells hold the state of the view and not content. Examples are `hovered` and `pressed` of a button, `scroll_position` of a scroll pane, `transform` of a transform pane, `collapsed` of a card, and the drag cells of a split pane. The reader writes them with ordinary operations, so the printer reads them as it reads any other cell.

`has_document_duplicate(::WidgetDocument)` is `true`, so the duplicate of a pane that holds widgets is a copy. The copy shares its `Action`, because an `Action` declares no duplicate.

### Drawing

`WidgetToGraphics(font; measure, theme)` returns a `TypeDispatchingProjection` with one rule for each widget type and one for `GridLayout`. `WidgetTabPage` and `WidgetAccordionItem` have no rule, because the printer of the parent draws them, so the table has 42 widget rules. A caller wraps the result in `RecursiveProjection`, or puts its `.dispatch` pairs into a larger table:

```julia
widgets    = WidgetToGraphics(font_ubuntu_regular_20; measure = measure_truetype_text)
projection = RecursiveProjection(TypeDispatchingProjection(vcat(
    LayoutToGraphics().dispatch, widgets.dispatch)))
```

A printer returns a `GraphicsCanvas` whose elements, width and height are computed cells. A leaf pushes text, rectangles and lines. A container prints each child through `recursion`, keeps the IO map of each child with `reconcile_child_iomap`, and places the child canvases. So a change of one cell draws again only what reads that cell.

The size of a widget follows the rules of the layout package: the policy of a child is on its container, and a container that bounds a child clips it. [layout.md](../layout/layout.md#the-size-that-a-parent-offers) describes the available size, and [layout-rules.md](../../rule/layout-rules.md) states the rules. `WidgetTable` places its cells with a `GridLayout` and draws its lines and header band over the geometry of the grid.

A `WidgetSplitPane` makes its per-slot cells and child IO maps for the number of slots that it has. So its printer runs the part that depends on the slots inside a cell that reads the slot list. A slot that is added or removed prints the children again, and the IO map of the pane keeps its identity.

### The theme

`WidgetTheme` holds the tokens that many widgets read: the palette, the fonts, the radius, the paddings, `gap`, `border_width`, `stroke`, `chevron`, the default `inset`, and four text styles. The factory derives the style fields of each projection from the theme and gives the dimensions that only one widget uses, such as the size of a switch. So every palette color of a widget comes from the theme. Four presets exist: `make_light_theme` and `make_dark_theme` are neutral zinc, and `make_slate_light_theme` and `make_slate_dark_theme` are slate with an indigo accent. The default is `make_slate_light_theme(font = font)`.

An icon is a `Symbol`, not an image. `register_icon!(:name, renderer)` stores a renderer `(elements, x, y, size, color) -> nothing`, so an icon takes the color of its label and scales with the font. A renderer can draw vectors, a glyph of an icon font with `make_glyph_icon`, or an image with `make_image_icon`. An image does not take the color. An unknown name draws nothing.

### A press goes by coordinate

A container keeps an entry `(x, y, child_iomap)` for each child. For a pointer event, `_route_to_children` translates the point into the frame of each child and tests it with `hit_element_at` on the canvas of the child. The first child that is hit gets the event. It calls `read_child_event` of the layout package, which applies the Alt+press rule below. The container then roots the answer under its own field, for example `elements[i]`.

Each widget also compares the point with its own canvas in `_outside_widget`. A container clips before it routes, but a widget can have no container above it. Without this test, a button at the root answers a press 800 pixels to its right.

**A drag is not hit-tested.** `WidgetComposite` and `WidgetSplitPane` give `MouseDown`, `MouseMove` and `MouseUp` to the hit child first, and to each child in order when no child is hit. `WidgetShell` does the same with `MouseDown` and `MouseUp`, in the frame of each band. `WidgetTabbedPane` gives them to the tab that it shows. Two cases need this. A slot is drawn only where its content draws, so a splitter dragged past the text loses its release. The divider of a nested split is in the gap between two panes, and a hit test of the parent finds no element there.

A container routes a `MouseMove` only to the child under the pointer, so a widget gets no event when the pointer leaves it. `WidgetHoverTrackingProjection` wraps a widget chain for this. On each `MouseMove`, it gives the move to the chain, then routes a synthetic `MouseEnter` at the pointer. When the widget that answers is a different one, it routes a `MouseLeave` to the last widget, and returns the operations together. The tracker makes no widget operation of its own: `WidgetButton` sets `hovered` on an enter and clears it on a leave.

### A key goes by selection

A key has no coordinate. `WidgetComposite`, `WidgetSplitPane`, `WidgetTabbedPane`, `WidgetCard` and the layouts give a key only to the child that their own `selection` names. When the selection is not inside the container, the container returns `nothing`. No container gives a key to a default child, to the first child, or to every child. The selection is the focus, and no widget has a `focused` field. [focus.md](../focus/focus.md) describes the functions.

`WidgetShell` is the one exception. It fires the `Action` of its menu bar or toolbar whose `shortcut` matches the key. Then it gives the key to each band and to the content in order, and takes the first operation.

Tab moves the selection to the next focusable widget. A container gives Tab to its selected child first. When the child returns `nothing`, the container selects the first focusable document of the next sibling with `get_next_focusable_index`. At the end of the tree, `WidgetHoverTrackingProjection` wraps the selection to the first focusable document. The focusable types are the enabled controls of the `FocusableWidget` union in `WidgetDocument.jl`.

A tabbed pane draws its first tab when its selection names no tab. `has_dormant_selection` is `true` for `WidgetTabbedPane`, `WidgetTabPage` and `WidgetSplitPane`, so a pane that loses the focus keeps the tab that it shows and the caret in that tab.

### A press moves the focus

A left button down with no modifier gives the focus to the control under the pointer. The rule is in `read_child_event`, which every widget container calls to give a press or a down to a child. When the down lands on a focusable child that answers nothing and holds no selection, `convert_to_focus_selection` of the focus package answers `ReplaceSelectionOperation` of the child as a whole. That is the selection that Tab gives the child. So a key after the click goes to the control that was pressed.

The focus moves on the down, and the control acts on the press that the gesture recognizer makes after the up. So the move of the focus and the action are two operations. A projection that can not map the selection, such as `ObjectToWidget`, drops the move of the focus, and the press still acts. A control that answers the down itself keeps its answer and does not take the focus: a button answers the down with its pressed look. `WidgetMenu` and `WidgetToolbar` give no down to their items, so a menu item and a toolbar item leave the focus in the content.

### Selecting a whole widget

A left press with Alt and no other modifier selects the innermost document under the pointer as a whole. The rule is in `read_child_event`, which every widget container calls, and it uses `convert_to_whole_selection` of the focus package. A control never acts on an Alt+press, because the rule drops the action that the control returns. No widget declares that it can be selected.

A container whose selection names a child as a whole draws a ring over that child with `make_selection_ring`. The composite, the card, the tabbed pane and every layout keep one ring as the last element, with no size while nothing is selected. A focusable control gets no ring, because it draws its own focus ring. So a projection must not write a fixed routing path into the `selection` cell of a container, or the container draws a ring.

A projection can draw a widget that no document of the domain stands behind, such as the table of a form. An `OutputReferenceStep` of the focus package names such a widget from the document that it was drawn for.

### What a control reads

Each control has a reader in `WidgetToGraphics.jl`. The keys in the table work while the control has the focus. A control takes Return, Space and an arrow only with no modifier, so Alt and an arrow still walk the selection and a chord still reaches a shortcut. A left press on a focusable control gives it the focus first. A disabled control returns `nothing` for every event.

| Widget | A press | A key |
| --- | --- | --- |
| `WidgetButton` | a left press invokes its action, or opens its dialog | Return, Space |
| `WidgetCheckbox`, `WidgetSwitch` | a left press flips the value | Return, Space |
| `WidgetToggle` | a left press flips `pressed` | Return, Space |
| `WidgetToggleGroup` | a left press on a segment selects it | none |
| `WidgetRadioGroup` | a left press on the row of an option, on its circle or its label, selects it | Down and Right select the next option, Up and Left the previous one, around the ends. Return and Space select the first option when no option is on. |
| `WidgetSelect` | a left press opens the options in a popup | none |
| `WidgetSlider` | a left press and a drag set the value | none |
| `WidgetSpinBox` | a left press on a stepper steps the value | Up, Down |
| `WidgetList` | a left press on a row selects it | Up and Down select the row before and after |
| `WidgetText`, `WidgetTextarea` | a press puts the caret into the text | the keys of the text domain. In a textarea, Return types a line break. |
| `WidgetCard` | a press on the chevron folds the card | none |
| `WidgetAccordion` | a left press on the header of an item opens that item, or closes it when it is open. A press on an open body that is a document goes to the body. | the keys of an open body that is a document, while the selection is in it |

`WidgetText` and `WidgetTextarea` are edited by the text domain. A `content` that is a document, usually a `TextBlock`, is recursed through the chain, so `TextToGraphics` draws it and makes every caret move and every edit. The reader moves a press into the frame of the content and puts the `content` step in front of the answer. The textarea gives Return to the content as a typed line break, because the text domain has no meaning for Return.

A plain value, such as a `String`, is edited too. The printer makes a `TextBlock` of one span that shows the string of the value, and draws it with a `TextToGraphics` of its own, so a chain with no rule for a `TextBlock` draws it. The caret of that view is the range of `content` that the widget holds, `content[i:j]`. The reader maps a caret of the view to such a range, and an edit to a `ReplaceStringRangeOperation` of the range, so the edit writes the field and the caret after it is again a range of the field. A number keeps a number: the evaluation ignores a character that can not be part of a number.

`WidgetAccordion` holds the index of the open item in `expanded`, and `0` when no item is open. So one item is open at a time, and the press that opens an item closes the item that was open. A title and a body that are documents are drawn through the recursion, as `WidgetCard` draws its content: each title once, and a body while its item is open. A title or a body that is a plain value is drawn as its string. The answer of a body is re-rooted under `items[i].body`.

`WidgetBadge`, `WidgetSeparator`, `WidgetProgress`, `WidgetAvatar`, `WidgetAlert`, `WidgetHighlight` and `WidgetSkeleton` only show a value, and their readers return `nothing`.

### Operations

Most widget edits are one write into the widget: `ReplaceReferencedValueOperation(widget, "field", value)`. The operation carries the widget itself, so it passes unchanged through every container above. A scroll, a zoom, a hover, a toggle, a radio pick, an open accordion item and a spin box step are all such writes.

The other operations are in `WidgetDocument.jl`:

| Operation | Made by |
| --- | --- |
| `InvokeActionOperation(action)` | a click on a button, a menu item or a toolbar item, and a matching shortcut |
| `CloseTabOperation`, `OpenTabOperation`, `DragTabOperation`, `DuplicateTabOperation` | a button of the tab strip, or a button down on a tab |
| `StartSplitterDragOperation`, `ResizeSplitPaneOperation`, `EndSplitterDragOperation` | a drag of a divider of a split pane |

These name their subject and not a place. `operation_travels_unchanged` is `true` for them, so the generic reader of every projection passes them up. So a button inside a card inside a domain projection reaches the editor. A tab click is a `ReplaceSelectionOperation` of `selector_element_pairs[i]`.

The four tab-strip operations only report a press. A tabbed pane draws the buttons when its flags `closable`, `new_tab`, `draggable` and `duplicable` are set. The meaning of a close belongs to the projection that owns the tabs: [pane.md](../pane/pane.md) answers all four. A report that no projection answers does nothing in `evaluate_operation`. `_tab_strip_geometry` lays out the strip for the printer and the reader both, so a change of the strip goes into that function.

`evaluate_operation` of `InvokeActionOperation` calls the `callback` of the action: with the editor when it takes one argument, else with none. A disabled action does nothing.

### The drag of a splitter

The drag state of a `WidgetSplitPane` is in cells of the pane, because the pipeline of events has no state:

- `sizes` holds the extent of each slot. The start of a drag fills it from the measured extents when it is empty.
- `active_splitter` is `0`, or `k` while the divider after slot `k` is held.
- `drag_anchor` holds the grab point and the two sizes at the grab, so each move computes from the grab and not from the last move.
- `pinned` marks each slot that a drag has set. The allocator then gives a pinned slot its `sizes` extent and no share of the weights, so a later print does not undo the drag.

Each move adds a delta to slot `k` and takes it from slot `k+1`, clamped to the minimum and maximum of each slot.

### Actions

An `Action(label; icon, enabled, shortcut, callback)` is one command that a menu item, a toolbar item, a button and a shortcut can share. A control reads the cells of its action, so a change of the label or of `enabled` draws again every control that shows it. A control is enabled when its own `enabled` and the one of its action are both `true`. `Shortcut(:s; ctrl = true)` makes the key pattern.

### Popups and dialogs

A popup is a window of its own, as a tooltip is. A trigger, such as `WidgetSelect`, a `WidgetMenuItem` with a submenu, or `WidgetContextMenu`, returns an `OpenPopupOperation(anchor, dx, dy, content, auto_dismiss)` of the screen package. `anchor` is the reference of the trigger, and the trigger does not compute a screen position. `WidgetPopupResolverProjection` sits at the root of the window content. It maps `anchor` forward with `get_anchor_point` and returns an `OpenWindowOperation` with `style = :floating`. The forward image of a widget is a `PointReferenceStep`, and each container adds the offset of the child to it, so the point is correct in the frame of the window.

A popup closes on a `WindowClose` of its window, and on a `WindowDefocus` when `auto_dismiss` is set. A click on an option or a menu item writes its value and closes the popup in one `CompoundOperation`.

`ContextMenuProbeProjection` wraps a window content. On a right press that nothing inside answers, it finds the document under the pointer with an Alt+press, calls `compute_context_menu` on it, and opens the menu with an `OpenPopupOperation`.

A `WidgetDialog` opens as a window with `modal = true`. `WindowManagingProjection` then drops the input of every other window. Escape, a click on the scrim, or a button closes the dialog. [screen.md](../screen/screen.md) describes the windows, and [shell.md](../shell/shell.md) says where the resolver and the probe go in a window.

### From a domain to widgets

Three projections turn objects of a domain into widgets:

- **`ObjectToWidget(; fields)`** reflects one object into a form: a `WidgetComposite` with a two-column `GridLayout` of labels and controls. A `Bool` becomes a `WidgetCheckbox`, and a string or a number becomes a `WidgetText`, which a person can edit when the field is a cell. A nested struct with cell fields and a vector become a collapsible `WidgetCard`. Below depth 16 the walk shows a nested value read only. The IO map holds a `(control, path)` pair for each control, and the reader turns an edit into `ReplaceReferencedValueOperation(root, path, value)`.
- **`ObjectFieldToWidget()`** projects one `ObjectField(object, path)` to a control without a label. So a `FormLayout` can put fields of different objects in rows that the author labels. The control writes through the path, so it can edit an element of a vector, which `ObjectToWidget` shows read only. It uses the classification and the coercion of `ObjectToWidget`.
- **`CellTableToWidgetTable()`** wraps a `CellTable` in a `WidgetTable`. Row 1 holds the headers. Each value becomes a `PrimitiveString`, `PrimitiveNumber` or `PrimitiveBool`, so the table draws it through its content recursion and names no domain.

`ProjectionConfiguringProjection` uses `ObjectToWidget` on a projection object. It shows the parameters of the projection above the document in a `WidgetSplitPane`, and Ctrl+F toggles them. A control writes the same cells that the projection reads, so the document prints again at once.

`ReflectionToWidget` of the reflection package draws a reflected object as a `WidgetTree`; [reflection.md](../reflection/reflection.md) compares the two paths.

### The table as a list

The `rows` of a `WidgetTable` can be a `ListNode`. `WidgetTableList.jl` then walks the list from its `head` in both directions and builds only the rows that the viewport shows. Each column must have a `Fixed` width or a weight, because a column that is as wide as its content would read rows that were never built. The table reports a width and no height, so it goes inside a `WidgetScrollPane`.

### The transform pane

`WidgetTransformPane` holds one affine `transform`, where a scroll pane holds one offset. Ctrl and the wheel zoom about the pointer, with a total scale from 0.25 to 4.0. The wheel alone pans. Ctrl with `=`, `-` or `0` zooms about the center, but only after the content returns `nothing` for the key. Other events go to the content, with the point mapped through the inverse transform.

## How it fits

`ProjecturedWidget` depends on the kernel and on `ProjecturedCollection`, `ProjecturedFocus`, `ProjecturedGraphics`, `ProjecturedLayout`, `ProjecturedDomain`, `ProjecturedPrimitive`, `ProjecturedProjection`, `ProjecturedScreen`, `ProjecturedSerialization`, `ProjecturedStyle` and `ProjecturedText`. `ProjecturedPane`, `ProjecturedShell`, `ProjecturedReflection`, `ProjecturedNatural`, `ProjecturedConversation`, `ProjecturedAssistant` and `ProjecturedFileSystem` use it. A page of `markdown` or `rst` puts a block of another domain in the card that `make_embed_card` builds.

The `__init__` registers `WidgetShell` as a `.pred` type. The widgets register no natural row: `NaturalToGraphics` adds the rules of `WidgetToGraphics` to its own table. A widget answers `compute_tooltip` with its `tooltip` field, and `WidgetShell` answers `compute_context_menu` with its `context_menu` field.

## Design decisions

- **A key goes only where the selection is.** A default child or a broadcast gives a key to a widget that the person did not choose. See `plan/done/widget-focus-traversal.md`.
- **One theme for every widget.** A widget with its own colors can not follow a change of the palette. See `plan/done/widget-shadcn-styling.md`.
- **A popup is a real window.** An overlay layer inside the window was rejected. The close of a popup is a focus event of its window, which the window manager already sends for the tooltip. See `plan/done/widget-popup-overlay.md`.
- **A drag of a divider keeps its state in the document.** The size of a slot is data that must survive the next print. See `plan/done/split-pane-drag-resize.md`.
- **An instance can have its own gestures.** `WidgetButton`, `WidgetCheckbox`, `WidgetSwitch`, `WidgetMenuItem`, `WidgetToolbarItem`, `WidgetTree` and `WidgetTreeNode` have a `gestures` field. `read_bound_gesture` reads it before the table of the type, so one instance can add, replace or remove a gesture with no new widget type. See `plan/done/widget-per-instance-gestures.md`.
- **The tracker detects the crossing; the widget sets its state.** A new widget reacts to hover with no change of the tracker. See `plan/done/widget-button-hover-press-feedback.md`.
- **One pane for scroll and zoom.** A zoom viewport inside a scroll viewport clips at a fixed box, and its clip conflicts with the pan of the outer one. See `plan/done/widget-transform-pane.md`.
- **One table widget, eager or lazy.** A second, lazy table widget and a separate table domain would each repeat the placement of the grid. See `plan/done/one-table-widget.md` and `plan/done/converge-table-on-widgettable.md`.

## Usage

```julia
save    = Action("Save"; icon = :save, shortcut = Shortcut(:s; ctrl = true),
                 callback = editor -> save_all!(editor))
toolbar = WidgetToolbar(Any[WidgetToolbarItem(save)])
form    = FormLayout([(WidgetLabel(Point2D(0, 0), "Name"),     ObjectField(server, "name")),
                      (WidgetLabel(Point2D(0, 0), "Capacity"), ObjectField(server, "capacity"))])
open_pane!(editor, WidgetSpinBox(Point2D(0, 0), 10; min = 1, max = 100, width = 80); title = "Runs")
run_example(widget_transform_pane_example)
write_example_image(widget_tree_example, "tree.png")
```

`save_all!` and `server` stand for your own function and object.

- Examples: one for each widget in `example/substrate/SubstrateExamples.jl`, such as `widget_example`, `widget_table_example`, `widget_popup_example` and `object_to_widget_example`. The screenshots are `asset/image/example/widget-*.png`.
- Tests: the `Widget*Test.jl`, `ObjectToWidgetTest.jl`, `ObjectFieldToWidgetTest.jl` and `CellTableToWidgetTableTest.jl` files in `test/substrate/projection/`, for example `test_widget_selection()`, `test_widget_split_pane()` and `test_widget_table_list()`. `test_substrate()` runs them all; the package has no suite of its own.

## Limits

- A press on a button does not move the focus to it, because the button answers the down with its pressed look. Tab or an Alt+press moves the focus to a button.
- `WidgetAccordion` has no `enabled` field.
- `WidgetShell` keeps no drag. A move goes only to the band under the pointer, so a drag that crosses a band loses its moves. `plan/pending/hover-drag-and-tooltip-share-the-pointer.md` describes the fault and a fix.
- `ObjectToWidget` maps no reference in either direction, so a caret can not move into the form from outside.
- A path whose last step is a range writes a vector value as a splice. So an `ObjectField` whose value is a vector can not be replaced as one value.
- The backends draw only the translation and the scale of a transform. Rotation and shear are dropped.
- The scrim of a `WidgetDialog` fills the window of the dialog, not the screen. `ScreenDocument` has no size of the screen to center against.
- `ProjectionConfiguringProjection` has a fixed Ctrl+F and a split pane. `plan/pending/configuration-overlay-widget.md` replaces them with an overlay and is not started. Its test has one `@test_broken`: a key does not reach the only control of the bar, because nothing selects it first.
