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

A node of a `WidgetTree` is closed until its path is in `expanded`, so the owner of a tree names the nodes it opens at the start with the keyword `expanded` of the `WidgetTree` constructor. The children of a `WidgetTreeNode` are a `Vector` or a `CellVector`; the tree reads them only for a row it draws, to know if the row has a chevron, and for an open node. Every row has one height, so the printer places each row by arithmetic, and it puts the rows on a canvas with a vertical layout and no overlap: the renderer draws, and so computes, only the rows in the viewport. The tree takes the width that its parent offers; with no offer it is as wide as its widest row, which reads every row of the open tree. The icons of the roots decide the width of the icon column. The printer keeps the canvas of each row by its path, and the top of the canvas reads where the path is now, so a row keeps its graphics when a folder above it opens or closes. The chevron of a row is a glyph whose text reads whether the row is open, and the rest of the row does not read `expanded`: a toggle changes one glyph and moves the rows below it.

Most widgets have `visible`, a `tooltip`, the box insets `margin`, `border` and `padding`, and a `style` that overrides the color of a part. An inset that is `nothing`, the default, takes the inset of the projection. An interactive widget also has `enabled`: its reader returns `nothing` for every event while `enabled` is `false`, and its printer resolves its parts in the disabled state. Some cells hold the state of the view and not content. Examples are `hovered` and `pressed` of a button, `scroll_position` of a scroll pane, `transform` of a transform pane, `collapsed` of a card, and the drag cells of a split pane. The reader writes them with ordinary operations, so the printer reads them as it reads any other cell. A write of `hovered`, `pressed` or `dragging` is also marked with `ReplaceViewStateOperation`, and so are the three operations of a divider drag, so a history does not record the pointer. A scroll is marked the same way: `scroll_position` and `follow_end` of a scroll pane, `tab_scroll` of a tab strip, and `transform` of a transform pane, so `Ctrl+Z` takes back an edit and not a scroll. So are the open nodes of a tree (`expanded`) and the open section of an accordion (`expanded`), which the renderer reads as the state of the view; a projection that shows the same widget as data writes those fields as edits.

`has_document_duplicate(::WidgetDocument)` is `true`, so the duplicate of a pane that holds widgets is a copy. The copy shares its `Action`, because an `Action` declares no duplicate.

### Drawing

`WidgetToGraphics(font; measure, theme)` returns a `TypeDispatchingProjection` with one rule for each widget type and one for `GridLayout`. `WidgetTabPage` and `WidgetAccordionItem` have no rule, because the printer of the parent draws them, so the table has 42 widget rules. A caller wraps the result in `RecursiveProjection`, or puts its `.dispatch` pairs into a larger table:

```julia
widgets    = WidgetToGraphics(font_ubuntu_regular_20; measure = FontFileMeasure())
projection = RecursiveProjection(TypeDispatchingProjection(vcat(
    LayoutToGraphics().dispatch, widgets.dispatch)))
```

A printer returns a `GraphicsCanvas` whose elements, width and height are computed cells. A leaf pushes text, rectangles and lines. A container prints each child through `recursion`, keeps the IO map of each child with `reconcile_child_iomap`, and places the child canvases. So a change of one cell draws again only what reads that cell.

The size of a widget follows the rules of the layout package: the policy of a child is on its container, and a container that bounds a child clips it. The container gives each axis a range, a minimum and a maximum, and the widget draws `max(minimum, content)`, or its authored size (`_resolve_size`). An overlay, such as a tooltip or a menu, caps its content at the maximum instead (`_resolve_overlay`). A container with one content — a card, a tab page, a scroll pane, a table — passes its range on, less its insets, in the same state (`with_inner_size`), and a toolbar gives its items its edge, so a text in any of them wraps at the edge that reaches it. A widget that fills a slot — a shell, a split, a scroll pane, a tabbed pane, a dialog — reads `get_exact_width` and `get_exact_height`, and is as large as its content where its parent gives no slot. [layout.md](../layout/layout.md#the-size-that-a-parent-offers) describes the available size, and [layout-rules.md](../../rule/layout-rules.md) states the rules. `WidgetTable` scrolls its own parts. The header row, the header column and the cells are each a `GridLayout` in a `WidgetScrollPane` of their own, and the corner between the two headers holds still. The pane of the cells shares the `scroll_position` of the table, the pane of the header row follows its `x`, and the pane of the header column its `y`. A table fills the size that it is offered and scrolls there; on an axis with no offer it is as large as its content. The cells decide the width of every column and the height of every row: a column is at least as wide as its header, and a `Content` row at least as tall as its header. The header row takes the widths as `Fixed`, and the header column the heights. A layout draws nothing, so the table draws its rules, its header bands and the bands of the hover and of the selection once, in the coordinates of the whole table as if it were not scrolled, and every region shows them behind its pane, moved by its own offset. So the band of a row runs across the header column and the cells. Its layout options are those of the grid: the column and row policies pass through; the cell policy, `:wrap` or `:clip`, is the `column_offers` of the grid; and `column_align` places each cell, and the header cell of its column, at the `:left`, in the `:center` or at the `:right`. The gaps come from the cell padding of the theme and the border.

A `WidgetSplitPane` makes its per-slot cells and child IO maps for the number of slots that it has. So its printer runs the part that depends on the slots inside a cell that reads the slot list. A slot that is added or removed prints the children again, and the IO map of the pane keeps its identity.

### The theme

`WidgetTheme` holds the tokens that many widgets read: the palette, the decorations `shadow`, `scrim`, `selection`, `knob`, `hover_layer` and `pressed_layer`, the fonts, the radius, the paddings, `gap`, `border_width`, `stroke`, `chevron`, and four text styles. Only the factory reads it. It derives the style fields of each projection from the theme and gives the dimensions that only one widget uses, such as the size of a switch. So every color that a printer draws is a style field of its projection, and another look is another theme. Four presets exist: `make_light_theme` and `make_dark_theme` are neutral zinc, and `make_slate_light_theme` and `make_slate_dark_theme` are slate with an indigo accent. The default is `make_slate_light_theme(font = font)`.

A projection holds one style field for each part that it draws, in each variant and each state. The name is `[<variant>_]<part>[_<state>]_<kind>`, and the kind is `color`, `stroke` or `text`: `padding_color`, `content_disabled_color`, `label_text`, `secondary_content_color`, `focus_ring_stroke`. Its constructor takes the theme and one keyword for each field, so `WidgetScrollPaneToGraphicsCanvas(theme; measure, font, content_color = color_transparent)` gives one widget type another look. The `style` of a document overrides a field of the same name: `WidgetStyle` holds `margin_color`, `border_color`, `padding_color`, `content_color` and `label_text_color`, and a widget type with more parts has a style of its own, such as `WidgetTabbedPaneStyle`. A `_text` or `_stroke` field is overridden by `<name>_color`. The color of a part is the override, else the field that the variant and the state select; the disabled state ignores the override, so a disabled widget reads as inert whatever its style says. A hovered or a pressed widget draws `layer_hovered_color` or `layer_pressed_color` over its surface. A button, a menu item and a toolbar item always hold the layer: its size and its color are cells of their own that read `hovered` and `pressed`, as the focus ring reads the selection, so a hover changes the layer and not the size or the element list of the widget. A toolbar and a menu take their extent from the sizes that their items state, and not from a measure of every graphic in an item.

`nothing` has one meaning: the layer gives no value, and the next one applies. A theme token and a style field of a projection are never `nothing`. `color_transparent` is the one color that draws nothing: the printer adds no element for a transparent part, and a container routes a press only over an element that a widget drew, so a transparent surface takes no press. The colors of another domain belong to the projection that makes widgets from it, in the way that `JsonToSyntax` owns the colors of JSON; such a projection gives its colors to the widgets as overrides.

An icon is a `Symbol`, not an image. `register_icon!(:name, renderer)` stores a renderer `(elements, x, y, size, color) -> nothing`, so an icon takes the color of its label and scales with the font. Every built-in icon is a glyph of the Lucide icon font (`asset/font/lucide.ttf`, ISC licence in `Lucide-ISC.txt`), drawn through the text renderer, so it has smooth edges on every backend; `LUCIDE_ICON_GLYPHS` maps each name to its code point, and a name says what the picture shows. `find_icon_character(name)` answers the character for a label that writes an icon as text, in `font_lucide_icons_20` given as its `text_style`. A renderer can also draw a glyph of another icon font with `make_glyph_icon`, which draws at the size of the icon box, or an image with `make_image_icon`. An image does not take the color. An unknown name draws nothing.

### A press goes by coordinate

A container keeps an entry `(x, y, child_iomap)` for each child. For a pointer event, `_route_to_children` translates the point into the frame of each child and tests it with `hit_element_at` on the canvas of the child. The first child that is hit gets the event. It calls `read_child_event` of the layout package, which applies the Alt+press rule below. The container then roots the answer under its own field, for example `elements[i]`.

Each widget also compares the point with its own canvas in `_outside_widget`. A container clips before it routes, but a widget can have no container above it. Without this test, a button at the root answers a press 800 pixels to its right.

**A drag is not hit-tested.** `WidgetComposite` and `WidgetSplitPane` give `MouseDown`, `MouseMove` and `MouseUp` to the hit child first, and to each child in order when no child is hit. `WidgetShell` does the same with `MouseDown` and `MouseUp`, in the frame of each band. `WidgetTabbedPane` gives them to the tab that it shows. Two cases need this. A slot is drawn only where its content draws, so a splitter dragged past the text loses its release. The divider of a nested split is in the gap between two panes, and a hit test of the parent finds no element there.

A container routes a `MouseMove` only to the child under the pointer, so a widget gets no event when the pointer leaves it. `WidgetHoverTrackingProjection` wraps a widget chain for this. On each `MouseMove`, it gives the move to the chain, then routes a synthetic `MouseEnter` at the pointer. When the widget that answers is a different one, it routes a `MouseLeave` to the last widget, and returns the operations together. The tracker makes no widget operation of its own: `WidgetButton` sets `hovered` on an enter and clears it on a leave.

### A key goes by selection

A key has no coordinate. `WidgetComposite`, `WidgetSplitPane`, `WidgetTabbedPane`, `WidgetCard` and the layouts give a key only to the child that their own `selection` names. `WidgetTable` gives a key that it does not take itself to the cell that its selection is in, as a whole or with a caret in it, so the readers of the domain of the cell edit it. A selected row, column or table is in no cell. When the selection is not inside the container, the container returns `nothing`. No container gives a key to a default child, to the first child, or to every child. The selection is the focus, and no widget has a `focused` field. [focus.md](../focus/focus.md) describes the functions.

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

A `WidgetText` has room around its text by default: the control padding of the theme, `theme.pad_y` above and below and `theme.pad_x` at each side, as a tooltip and an option of a select have. A `WidgetText` that gives its own `padding` keeps it.

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

A popup is a window of its own, as a tooltip is. A trigger, such as `WidgetSelect`, a `WidgetMenuItem` with a submenu, or `WidgetContextMenu`, answers `ReplaceViewStateOperation(OpenPopupOperation(; id, x, y, auto_dismiss, content))` of the screen package, in its own frame. A submenu item and `WidgetSelect` answer a position just below themselves, and `WidgetContextMenu` answers the point of the press. No trigger gives a size: the popup window takes the extent of what its content draws. `ReplaceViewStateOperation` marks the popup as not an edit, so a history does not record it.

What a popup holds is a vertical `WidgetMenu`: the submenu of an item, the menu of a `WidgetContextMenu`, and the options of a `WidgetSelect`. A vertical menu is a dropdown, and it draws the popover of the theme: the fill of `theme.popover`, a hairline of `theme.border`, and a small padding, from the style fields of the variant `vertical`. A horizontal menu, the menu bar, has no fields of that variant and draws on the bar that holds it. A dropdown offers its items no height, so each is as tall as its label, and it offers each `WidgetMenuItem` the width of the widest one, so the highlight of a row spans the menu. An item measures that width in a cell that does not read its offer, and its IO map carries it as `natural_width`; the dropdown reaches it through the `inner_iomap` of a host wrapper and never reads the drawn width of an item, which depends on the offer.

No trigger computes a screen position. Each reader that reads a child with a press shifts the popup that the child answers back into its own frame with `shift_operation_position(operation, dx, dy)`, by the offset at which it placed that child: a reader that read the child with a pointer event at `(lx, ly)` for its own `(x, y)` shifts the answer by `(x - lx, y - ly)`. `WidgetTransformPane` maps the position through its transform with `map_operation_position`, because its transform can scale it. [graphics.md](../graphics/graphics.md) describes the two functions.

`WidgetShell` shifts the answer of each band by the offset where it placed that band. Each band prints with the reference step of its own field: `menu_bar`, `toolbar`, `status_bar`, `content` and `overlay`. The screen layer adds the origin of the window and turns the popup into an `OpenWindowOperation` with `style = :popup`, a window that never takes the focus; [screen.md](../screen/screen.md) describes that step.

A popup closes on a `WindowClose` of its window, on a press in another window, on a bare Escape, and when a window loses the focus; [screen.md](../screen/screen.md) gives the rules. A click on an option or a menu item writes its value and closes the popup in one `CompoundOperation`.

`ContextMenuProbeProjection` wraps a window content. It answers the press point in its own frame, so it needs no anchor. On a right press it finds the document under the pointer with an Alt+press and calls `compute_context_menu` on it. When the closer answer inside only moves the selection, for example a row of a list that a press selects, the probe answers the selection and the popup together, in one `CompoundOperation`, so a right press on a row selects the row and opens its menu.

A `WidgetDialog` opens as a window with `modal = true`. `WindowManagingProjection` then drops the input of every other window. Escape, a click on the scrim, or a button closes the dialog. [screen.md](../screen/screen.md) describes the windows, and [shell.md](../shell/shell.md) says which row draws the widgets a popup holds.

### From a domain to widgets

Three projections turn objects of a domain into widgets:

- **`ObjectToWidget(; fields)`** reflects one object into a form: a `WidgetComposite` with a two-column `GridLayout` of labels and controls. A `Bool` becomes a `WidgetCheckbox`, and a string or a number becomes a `WidgetText`, which a person can edit when the field is a cell. A nested struct with cell fields and a vector become a collapsible `WidgetCard`. Below depth 16 the walk shows a nested value read only. The IO map holds a `(control, path)` pair for each control, and the reader turns an edit into `ReplaceReferencedValueOperation(root, path, value)`.
- **`ObjectFieldToWidget()`** projects one `ObjectField(object, path)` to a control without a label. So a `FormLayout` can put fields of different objects in rows that the author labels. The control writes through the path, so it can edit an element of a vector, which `ObjectToWidget` shows read only. It uses the classification and the coercion of `ObjectToWidget`.
- **`CellTableToWidgetTable()`** wraps a `CellTable` in a `WidgetTable`. Row 1 holds the headers. Each value becomes a `PrimitiveString`, `PrimitiveNumber` or `PrimitiveBool`, so the table draws it through its content recursion and names no domain.

`ProjectionConfiguringProjection` uses `ObjectToWidget` on a projection object. It shows the parameters of the projection above the document in a `WidgetSplitPane`, and Ctrl+F toggles them. A control writes the same cells that the projection reads, so the document prints again at once.

`ReflectionToWidget` of the reflection package draws a reflected object as a `WidgetTree`; [reflection.md](../reflection/reflection.md) compares the two paths.

### The table as a list

The `rows` of a `WidgetTable` can be a `ListNode`, and `WidgetTableParts.jl` prints such a table with the same parts: the header row, and the cells as a `GridLayout` over the list of rows. A turn of the wheel over any part goes to the pane of the cells. The grid walks the list from its `head` in both directions and builds only the rows that the viewport shows, and the pane stops at the first row and at the last row of a list that ends. The cells decide the width of every column; a weighted column with no minimum is at least as wide as its header, and the header row takes those widths as `Fixed`. Each column must have a `Fixed` width or a weight, because a column that is as wide as its content would read rows that were never built. A layout draws nothing, so the table draws its rules and its bands behind each pane, at the places that the grids report: for the cells, a list of row graphics that mirrors the rows that the grid placed. Such a table fills the height that it is offered, and it needs one, because a list has no extent to size it by. As it scrolls, the table writes `top_row`, the row at the top of the cells counted from the head. When that row is more than 200 rows from the head, the table moves the head of `rows` to it and the offset by the place of that row, in one operation of view state, so the rows that it builds stay near the head and the same row stays in place; a selection or a hover of a row moves with it. A projection that owns the rows turns that write of `rows` into an edit of its own: the data frame view moves its anchor. When `column_headers` is a `ListNode` too, the columns are a list as well: the cells of every row are a `ListNode` anchored at the same column, every column is the `Fixed` `column_policy` and at least as wide as its header, and every row is `Fixed`. The header row and the cells share one list of policies that mirrors the headers, the grid places the columns as a list that a pane stops at, and each region draws the rules of the columns as a list, so only the columns that show are built. A column far from the head column moves the head column to it, as a row does: the table writes `column_headers`, a list `column_align`, and `rows` as a list of the rows from that column on; the data frame view moves its `column_anchor` instead.

### The transform pane

`WidgetTransformPane` holds one affine `transform`, where a scroll pane holds one offset. Ctrl and the wheel zoom about the pointer, with a total scale from 0.25 to 4.0. The wheel alone pans. Ctrl with `=`, `-` or `0` zooms about the center, but only after the content returns `nothing` for the key. Other events go to the content. Each pointer event, that is a press, a button down, a button up, a move and the two crossings, gets its point mapped through the inverse transform. So a button down gives the focus to the control that is drawn under the pointer, and a move of a drag reaches the content at the point that is drawn under the pointer.

## How it fits

`ProjecturedWidget` depends on the kernel and on `ProjecturedCollection`, `ProjecturedFocus`, `ProjecturedGraphics`, `ProjecturedLayout`, `ProjecturedDomain`, `ProjecturedPrimitive`, `ProjecturedProjection`, `ProjecturedScreen`, `ProjecturedSerialization`, `ProjecturedStyle` and `ProjecturedText`. `ProjecturedPane`, `ProjecturedShell`, `ProjecturedReflection`, `ProjecturedNatural`, `ProjecturedConversation`, `ProjecturedAssistant` and `ProjecturedFileSystem` use it. A page of `markdown` or `rst` puts a block of another domain in the card that `make_embed_card` builds.

A scroll pane is a layer that a person sees through: `get_edited_field` of a `WidgetScrollPane` answers `:content`, and its title is the title of its content. So a file tab, whose content is a file in a scroll pane, is called by the name of the file, and `get_edited_document` of it reaches the document of the file. The widget stage routes an operation through a scroll pane to its content, as it does through a composite, a split pane and a tabbed pane.

The `__init__` registers `WidgetShell` and `WidgetScrollPane` as `.pred` types. Each writes its content only: the bands of a shell, and the scroll position and the size of a scroll pane, belong to the window that opens them. The widgets register no natural row: `NaturalToGraphics` adds the rules of `WidgetToGraphics` to its own table. A widget answers `compute_tooltip` with its `tooltip` field, and `WidgetShell` answers `compute_context_menu` with its `context_menu` field.

## Design decisions

- **A key goes only where the selection is.** A default child or a broadcast gives a key to a widget that the person did not choose. See [plan/done/widget-focus-traversal.md](../../../plan/done/widget-focus-traversal.md).
- **One theme for every widget.** A widget with its own colors can not follow a change of the palette. See [plan/done/widget-shadcn-styling.md](../../../plan/done/widget-shadcn-styling.md).
- **A popup is a real window.** An overlay layer inside the window was rejected. The close of a popup is a focus event of its window, which the window manager already sends for the tooltip. See [plan/done/widget-popup-overlay.md](../../../plan/done/widget-popup-overlay.md).
- **A drag of a divider keeps its state in the document.** The size of a slot is data that must survive the next print. See [plan/done/split-pane-drag-resize.md](../../../plan/done/split-pane-drag-resize.md).
- **An instance can have its own gestures.** `WidgetButton`, `WidgetCheckbox`, `WidgetSwitch`, `WidgetMenuItem`, `WidgetToolbarItem`, `WidgetTree` and `WidgetTreeNode` have a `gestures` field. `read_bound_gesture` reads it before the table of the type, so one instance can add, replace or remove a gesture with no new widget type. See [plan/done/widget-per-instance-gestures.md](../../../plan/done/widget-per-instance-gestures.md).
- **The tracker detects the crossing; the widget sets its state.** A new widget reacts to hover with no change of the tracker. See [plan/done/widget-button-hover-press-feedback.md](../../../plan/done/widget-button-hover-press-feedback.md).
- **One pane for scroll and zoom.** A zoom viewport inside a scroll viewport clips at a fixed box, and its clip conflicts with the pan of the outer one. See [plan/done/widget-transform-pane.md](../../../plan/done/widget-transform-pane.md).
- **One table widget, eager or lazy.** A second, lazy table widget and a separate table domain would each repeat the placement of the grid. See [plan/done/one-table-widget.md](../../../plan/done/one-table-widget.md) and [plan/done/converge-table-on-widgettable.md](../../../plan/done/converge-table-on-widgettable.md).

## Usage

```julia
save    = Action("Save"; icon = :save, shortcut = Shortcut(:s; ctrl = true),
                 callback = editor -> save_all!(editor))
toolbar = WidgetToolbar(Any[WidgetToolbarItem(save)])
form    = FormLayout([(WidgetLabel("Name"),     ObjectField(server, "name")),
                      (WidgetLabel("Capacity"), ObjectField(server, "capacity"))])
open_pane!(editor, WidgetSpinBox(10; min = 1, max = 100, width = 80); title = "Runs")
run_example(widget_transform_pane_example)
write_example_image(widget_tree_example, "tree.png")
```

`save_all!` and `server` stand for your own function and object.

- Examples: one for each widget in `example/substrate/SubstrateExamples.jl`, such as `widget_example`, `widget_table_example`, `widget_popup_example` and `object_to_widget_example`. The screenshots are `asset/image/example/widget-*.png`.
- Tests: the `Widget*Test.jl`, `ObjectToWidgetTest.jl`, `ObjectFieldToWidgetTest.jl` and `CellTableToWidgetTableTest.jl` files in `test/substrate/projection/`, for example `test_widget_selection()`, `test_widget_split_pane()` and `test_widget_table_list()`. `test_substrate()` runs them all; the package has no suite of its own.

## Limits

- A press on a button does not move the focus to it, because the button answers the down with its pressed look. Tab or an Alt+press moves the focus to a button.
- `WidgetAccordion` has no `enabled` field.
- `ObjectToWidget` maps no reference in either direction, so a caret can not move into the form from outside.
- A path whose last step is a range writes a vector value as a splice. So an `ObjectField` whose value is a vector can not be replaced as one value.
- The backends draw only the translation and the scale of a transform. Rotation and shear are dropped.
- The scrim of a `WidgetDialog` fills the window of the dialog, not the screen. `ScreenDocument` has no size of the screen to center against.
- `ProjectionConfiguringProjection` has a fixed Ctrl+F and a split pane. [plan/pending/configuration-overlay-widget.md](../../../plan/pending/configuration-overlay-widget.md) replaces them with an overlay and is not started. Its test has one `@test_broken`: a key does not reach the only control of the bar, because nothing selects it first.
