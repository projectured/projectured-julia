# Architecture review: The widget set

Commit 3a9b4fae4. Reviewer area key: widget-set.

Short names in this report: **WD** is `source/platform/widget/WidgetDocument.jl` (the widget document types), **WTG** is `source/platform/widget/WidgetToGraphics.jl` (the projection that draws each widget and reads its events), **LTG** is `source/platform/layout/LayoutToGraphics.jl` (the same for the layouts).

## Scope

Paths: `source/platform/widget` (28 files, 27 206 lines by `wc -l`), `source/platform/component` (2 files, 76 lines), `documentation/package/platform/widget/`.

Read in full, about 8 000 lines:

- `documentation/design/concepts.md`, `documentation/design/architecture-decisions.md`, `documentation/package/platform/widget/widget.md` (all 434 lines).
- `WidgetModule.jl`, both component files, `WidgetValueSlot.jl`, `ObjectFieldToValue.jl`, `DocumentComposition.jl`.
- WD: lines 1 to 720 and 3860 to 4251 with their docstrings; every struct and every constructor of the rest without the docstrings.
- WTG: about 3 300 of 15 822 lines. The shared head (1 to 780, 1450 to 2237), and the printers and readers of the label, the checkbox, the button, the switch, the toggle, the composite, the shell, the title pane, the readers of the tooltip, the context menu, the dialog, the menu, the toolbar, the card, the scroll pane, the accordion, the slider and the toggle group.
- LTG lines 200 to 600, and the kernel functions that the findings name (`GestureBinding.jl` 60 to 215, `ProjectionDefaults.jl` 120 to 372, `Intent.jl`, `Inversion.jl`, the docstring of `@document`, `PredFile.jl` 180 to 240).

Sampled by outline and by `grep`: the rest of WTG (the printers of the split pane, the tabbed pane, the table and the tree), `WidgetTableParts.jl`, `WidgetTableHeaderLevels.jl`, `WidgetStyle.jl`, `WidgetTheme.jl`, and the head of each small fragment. Counts over other slices and over omnet-julia come from `grep`. A cell of a matrix that comes from a count and not from a read is marked "(grep)".

## State

The model of a widget is sound and uniform. A widget is a `@document`, its state is in fields of that document for every widget, one projection draws it, and its IO map carries the shape of its box to the reader. Several behaviours are written once and work for every widget: the tooltip (one gesture binding on `WidgetDocument`), the light under the pointer (read from the mouse target, no state), the box (`BoxGeometry`), the read-only text of a widget (`DrawnTextLine`), the value slot (`WidgetValueSlot.jl`), the popup as a window.

The main weakness is that the parts above the single widget are written again for each widget. The layouts share their reader: one function serves four layout types and a second one serves three. The sixteen widget containers do not: each has a reader of its own, two are full copies of the layout reader, and the others pass on a different subset of the events. So a control works in one container and is dead in another.

The second weakness is the surface that a view author meets. A control states what a press does in five ways, and binds its value in two. The constructors are written by hand, take plain values only, and so about 420 call sites reach under a document with `getfield` to make a field follow a value. The gestures of a control are code in its reader, where 43 tables of other slices declare theirs as rows; the plan that added gesture tables to widgets left this step out on purpose.

Every view that builds widgets is a hand-written projection: 72 in this repository and 82 in omnet-julia. The engine that derives a reader and both maps from a builder (`@projection_template`) has 162 uses, and all of them make syntax.

The component slice has no user.

## Inventory

### I1. The widget types

Struct line in WD, printer line in WTG. "Slot" is the field that holds the value of a value widget. "View state" lists the fields that the widget keeps of how it is shown.

| Widget | Struct | Printer | Value or children | View state fields |
| --- | --- | --- | --- | --- |
| `WidgetLabel` | [124](../../../source/platform/widget/WidgetDocument.jl#L124) | [1973](../../../source/platform/widget/WidgetToGraphics.jl#L1973) | `content` | none |
| `WidgetBadge`, `WidgetAvatar`, `WidgetAlert` | [1946](../../../source/platform/widget/WidgetDocument.jl#L1946), [2514](../../../source/platform/widget/WidgetDocument.jl#L2514), [2555](../../../source/platform/widget/WidgetDocument.jl#L2555) | [9394](../../../source/platform/widget/WidgetToGraphics.jl#L9394), [10769](../../../source/platform/widget/WidgetToGraphics.jl#L10769), [10864](../../../source/platform/widget/WidgetToGraphics.jl#L10864) | `content`, `initials`, `title` | none |
| `WidgetFactGroup` (`WidgetFact`) | [2992](../../../source/platform/widget/WidgetDocument.jl#L2992) | [12898](../../../source/platform/widget/WidgetToGraphics.jl#L12898) | `facts[i].label`, `.value` | none |
| `WidgetProgressBar`, `WidgetProgressRing`, `WidgetSkeleton`, `WidgetSwatch`, `WidgetHighlight`, `WidgetSeparator`, `WidgetIcon`, `WidgetInsertion` | [2318](../../../source/platform/widget/WidgetDocument.jl#L2318) … [84](../../../source/platform/widget/WidgetDocument.jl#L84) | [10216](../../../source/platform/widget/WidgetToGraphics.jl#L10216) … [2219](../../../source/platform/widget/WidgetToGraphics.jl#L2219) | a value | none |
| `WidgetTooltip`, `WidgetStatusBar` | [722](../../../source/platform/widget/WidgetDocument.jl#L722), [1275](../../../source/platform/widget/WidgetDocument.jl#L1275) | [3292](../../../source/platform/widget/WidgetToGraphics.jl#L3292), [8799](../../../source/platform/widget/WidgetToGraphics.jl#L8799) | `content`, `elements` | none |
| `WidgetButton` | [577](../../../source/platform/widget/WidgetDocument.jl#L577) | [2945](../../../source/platform/widget/WidgetToGraphics.jl#L2945) | `action`, `dialog` | `pressed` |
| `WidgetToolbarItem`, `WidgetMenuItem` | [992](../../../source/platform/widget/WidgetDocument.jl#L992), [927](../../../source/platform/widget/WidgetDocument.jl#L927) | [3913](../../../source/platform/widget/WidgetToGraphics.jl#L3913), [3739](../../../source/platform/widget/WidgetToGraphics.jl#L3739) | `action`; `submenu`, `operation` | `pressed` (toolbar item) |
| `WidgetLink` | [683](../../../source/platform/widget/WidgetDocument.jl#L683) | [3174](../../../source/platform/widget/WidgetToGraphics.jl#L3174) | `content`, `target` | none |
| `WidgetCheckbox` | [490](../../../source/platform/widget/WidgetDocument.jl#L490) | [2853](../../../source/platform/widget/WidgetToGraphics.jl#L2853) | slot `content` | none |
| `WidgetSwitch` | [2271](../../../source/platform/widget/WidgetDocument.jl#L2271) | [10121](../../../source/platform/widget/WidgetToGraphics.jl#L10121) | slot `checked` | `duration`, `anim_from`, `anim_t0` (no reader in the slice) |
| `WidgetToggle` | [2666](../../../source/platform/widget/WidgetDocument.jl#L2666) | [11334](../../../source/platform/widget/WidgetToGraphics.jl#L11334) | slot `pressed` | none |
| `WidgetToggleGroup` | [2722](../../../source/platform/widget/WidgetDocument.jl#L2722) | [11449](../../../source/platform/widget/WidgetToGraphics.jl#L11449) | `selected::Int`, `values`, `target`, `field` | none |
| `WidgetRadioGroup` | [2485](../../../source/platform/widget/WidgetDocument.jl#L2485) | [10628](../../../source/platform/widget/WidgetToGraphics.jl#L10628) | slot `selected` (an index) | none |
| `WidgetSelect` (`WidgetOption`) | [2786](../../../source/platform/widget/WidgetDocument.jl#L2786) | [11684](../../../source/platform/widget/WidgetToGraphics.jl#L11684) | slot `value` (a value) | none |
| `WidgetSlider` | [2406](../../../source/platform/widget/WidgetDocument.jl#L2406) | [10396](../../../source/platform/widget/WidgetToGraphics.jl#L10396) | slot `value`, and `target`, `field`, `mapping` | `dragging`, `press_value` |
| `WidgetSpinBox` | [342](../../../source/platform/widget/WidgetDocument.jl#L342) | [11913](../../../source/platform/widget/WidgetToGraphics.jl#L11913) | slot `value` | none |
| `WidgetText`, `WidgetTextarea` | [241](../../../source/platform/widget/WidgetDocument.jl#L241), [2872](../../../source/platform/widget/WidgetDocument.jl#L2872) | [2418](../../../source/platform/widget/WidgetToGraphics.jl#L2418), [12408](../../../source/platform/widget/WidgetToGraphics.jl#L12408) | slot `content` | `scroll_position`, `wheel_run`, `scrolled_selection` |
| `WidgetScrollBar` | [1852](../../../source/platform/widget/WidgetDocument.jl#L1852) | [8945](../../../source/platform/widget/WidgetToGraphics.jl#L8945) | `value`, `thumb_size` | `thumb_drag` |
| `WidgetMenu` | [871](../../../source/platform/widget/WidgetDocument.jl#L871) | [4104](../../../source/platform/widget/WidgetToGraphics.jl#L4104) | `elements` | `highlighted` |
| `WidgetToolbar`, `WidgetContextMenu` | [1083](../../../source/platform/widget/WidgetDocument.jl#L1083), [759](../../../source/platform/widget/WidgetDocument.jl#L759) | [8688](../../../source/platform/widget/WidgetToGraphics.jl#L8688), [3385](../../../source/platform/widget/WidgetToGraphics.jl#L3385) | `elements`; `child`, `menu` | none |
| `WidgetComposite` | [1049](../../../source/platform/widget/WidgetDocument.jl#L1049) | [4211](../../../source/platform/widget/WidgetToGraphics.jl#L4211) | `elements` | none |
| `WidgetShell` | [1308](../../../source/platform/widget/WidgetDocument.jl#L1308) | [4517](../../../source/platform/widget/WidgetToGraphics.jl#L4517) | `content`, `menu_bar`, `toolbar`, `status_bar`, `overlay` | none |
| `WidgetTitlePane`, `WidgetDialog` | [1363](../../../source/platform/widget/WidgetDocument.jl#L1363), [797](../../../source/platform/widget/WidgetDocument.jl#L797) | [4876](../../../source/platform/widget/WidgetToGraphics.jl#L4876), [3545](../../../source/platform/widget/WidgetToGraphics.jl#L3545) | `content`; `content`, `buttons` | none |
| `WidgetCard` | [2159](../../../source/platform/widget/WidgetDocument.jl#L2159) | [9799](../../../source/platform/widget/WidgetToGraphics.jl#L9799) | `title`, `description`, `content`, `footer` | `collapsed` |
| `WidgetAccordion` | [2937](../../../source/platform/widget/WidgetDocument.jl#L2937) | [12575](../../../source/platform/widget/WidgetToGraphics.jl#L12575) | `items[i].title`, `.body` | `expanded` |
| `WidgetSplitPane` | [1424](../../../source/platform/widget/WidgetDocument.jl#L1424) | [5056](../../../source/platform/widget/WidgetToGraphics.jl#L5056) | `elements` | `sizes`, `pinned`, `active_splitter`, `splitter_under_pointer`, `drag_anchor` |
| `WidgetTabbedPane` (`WidgetTabPage`, `WidgetTabLabel`) | [1573](../../../source/platform/widget/WidgetDocument.jl#L1573) | [6139](../../../source/platform/widget/WidgetToGraphics.jl#L6139) | `selector_element_pairs[i].element` | `tab_scroll`, `scrolled_tab` |
| `WidgetScrollPane` | [1706](../../../source/platform/widget/WidgetDocument.jl#L1706) | [7505](../../../source/platform/widget/WidgetToGraphics.jl#L7505) | `content` | `scroll_position`, `follow_end`, `wheel_run`, `at_natural_size`, `revealed_position` |
| `WidgetTransformPane` | [1796](../../../source/platform/widget/WidgetDocument.jl#L1796) | [8428](../../../source/platform/widget/WidgetToGraphics.jl#L8428) | `content` | `transform`, `wheel_run` |
| `WidgetList` | [404](../../../source/platform/widget/WidgetDocument.jl#L404) | [12224](../../../source/platform/widget/WidgetToGraphics.jl#L12224) | `items` | `scroll_position` |
| `WidgetTable` | [3220](../../../source/platform/widget/WidgetDocument.jl#L3220) | [13630](../../../source/platform/widget/WidgetToGraphics.jl#L13630) | `cells`, `column_headers`, `row_headers`, `corner` | `scroll_position`, `top_row`, `shown`, `column_drag` |
| `WidgetTree` | [3617](../../../source/platform/widget/WidgetDocument.jl#L3617) | [14851](../../../source/platform/widget/WidgetToGraphics.jl#L14851) | `roots` | `expanded`, `anchor`, `shown`, `current`, `scroll_position` |

Where the state lives: in a field of the widget document, for every widget. No widget keeps state in its projection (a projection holds style fields only) or in a view document.

Fields that every widget repeats (counts in WD): `visible` 45 structs, `margin`, `border`, `padding` 45, `style` 46, `tooltip` 53, `position` 34, `enabled` 17, `gestures` 9.

### I2. The controls and their behaviours

"once" means one shared function gives the behaviour. "own" means the reader or the printer of the widget writes it.

| Control | `enabled` | Light under the pointer | Pressed look | Focus ring | Keys | Own gestures of an instance (`gestures`) | Text can be selected | Value slot |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Button | yes | once, `_push_hover_layer!` [WTG:3012](../../../source/platform/widget/WidgetToGraphics.jl#L3012) | own, `pressed` | once [WTG:3032](../../../source/platform/widget/WidgetToGraphics.jl#L3032) | own, Return, Space [WTG:3099](../../../source/platform/widget/WidgetToGraphics.jl#L3099) | yes | once, with Alt | no |
| Toolbar item | yes | once (grep) | own (grep) | no call (grep) | none | yes | once, with Alt | no |
| Menu item | yes | once (grep) | no | no | the menu reads them | yes | no, by decision | no |
| Link | yes | own, a line | no | once (grep) | from its table | from its table | once, with Alt | no |
| Checkbox | yes | no | no | once [WTG:2885](../../../source/platform/widget/WidgetToGraphics.jl#L2885) | own, Return, Space [WTG:2923](../../../source/platform/widget/WidgetToGraphics.jl#L2923) | yes | no | `content` |
| Switch | yes | no | no | once | own, same text as the checkbox [WTG:10175](../../../source/platform/widget/WidgetToGraphics.jl#L10175) | yes | no | `checked` |
| Toggle | yes | no | no | once | own [WTG:11372](../../../source/platform/widget/WidgetToGraphics.jl#L11372) | no | no | `pressed` |
| Toggle group | yes | no | no | once (grep) | own, only the `:step` look | no | once, with Alt | no: `target`, `field` |
| Radio group | yes | no | no | once (grep) | own, arrows, Return, Space | no | no | `selected` |
| Select | yes | no | no | once (grep) | none | no | no | `value` |
| Slider | yes | no | no | once (grep) | none | no | no | `value`, and `target`, `field` |
| Spin box | yes | no | no | once (grep) | own, Up, Down | no | no | `value` |
| Text, text area | yes | no | no | once | the text domain | no | the text domain | `content` |
| Label, badge, avatar, alert | no | no | no | no | once, `read_drawn_text_key` | label only | once | no |
| List, tree, table | list only | own, the row | no | no | own | tree only | no | no |

Written once for every widget: the tooltip ([WD:4173](../../../source/platform/widget/WidgetDocument.jl#L4173)), the test of the bounds (`_outside_widget`, 57 calls), the box parts (`_push_box_parts!`, 45 calls), the selection of drawn text (`DrawnTextLine.jl`, wired in 10 widgets).
Written per widget: the reaction to a press and to a key, the test of `enabled`, the pressed look, the drag, the scroll of a text.

### I3. The containers

"all" means click, button down and up, wheel, dwell, right click and move. The reader lines are in WTG, except the first row.

| Container | Holds its children in | Pointer events that reach a child | Key to the selected child | Tab to the next child | Re-roots the answer by | Ring on a child selected as a whole |
| --- | --- | --- | --- | --- | --- | --- |
| The layouts: `_route_layout_event` [LTG:480](../../../source/platform/layout/LayoutToGraphics.jl#L480) for the row, the column, the grid and the flow; `_route_stack_event` [LTG:2417](../../../source/platform/layout/LayoutToGraphics.jl#L2417) for the stack, the constraint and the anchored layout; the scroll layout has its own [LTG:3024](../../../source/platform/layout/LayoutToGraphics.jl#L3024) | `children[i]` | all for the row, the column, the grid and the flow; the stack, the constraint and the anchored layout pass click, wheel and move only: `_route_stack_event` has no branch for a button down, a button up or a dwell, and calls no `read_container_gesture` (corrected by the check) | yes | yes, `_layout_tab` [LTG:458](../../../source/platform/layout/LayoutToGraphics.jl#L458) | `children[i]`, typed | yes [LTG:284](../../../source/platform/layout/LayoutToGraphics.jl#L284) |
| Composite [4346](../../../source/platform/widget/WidgetToGraphics.jl#L4346) | `elements[i]` | all | yes | yes, `_composite_tab` [4490](../../../source/platform/widget/WidgetToGraphics.jl#L4490) | `elements[i]` | yes [4291](../../../source/platform/widget/WidgetToGraphics.jl#L4291) |
| Split pane [5643](../../../source/platform/widget/WidgetToGraphics.jl#L5643) | `elements[i]`, through a `LayoutConstraint` | all | yes | yes, `_split_tab` [5746](../../../source/platform/widget/WidgetToGraphics.jl#L5746) | `elements[i]` | no |
| Tabbed pane [6640](../../../source/platform/widget/WidgetToGraphics.jl#L6640) | `selector_element_pairs[i].element` | all, to the open page | yes [6907](../../../source/platform/widget/WidgetToGraphics.jl#L6907) | no code | the page steps | yes [6399](../../../source/platform/widget/WidgetToGraphics.jl#L6399) |
| Scroll pane [8030](../../../source/platform/widget/WidgetToGraphics.jl#L8030), transform pane [8593](../../../source/platform/widget/WidgetToGraphics.jl#L8593) | `content` | all | every key, with no test of the selection [8110](../../../source/platform/widget/WidgetToGraphics.jl#L8110) | no code | the backward map, `_retarget_op` [1891](../../../source/platform/widget/WidgetToGraphics.jl#L1891) | no |
| Card [9958](../../../source/platform/widget/WidgetToGraphics.jl#L9958), [10009](../../../source/platform/widget/WidgetToGraphics.jl#L10009) | `title`, `content` | all | to `content` only [10042](../../../source/platform/widget/WidgetToGraphics.jl#L10042) | no code | the field of the slot | yes [9843](../../../source/platform/widget/WidgetToGraphics.jl#L9843) |
| Accordion [12749](../../../source/platform/widget/WidgetToGraphics.jl#L12749) | `items[i].body` | all, to the open body | yes [12785](../../../source/platform/widget/WidgetToGraphics.jl#L12785) | no code | `items[i].body` | no |
| Fact group [13076](../../../source/platform/widget/WidgetToGraphics.jl#L13076) | `facts[i].value` | click, down, up, wheel, move | no (grep) | no | steps found by identity | no |
| Shell [4758](../../../source/platform/widget/WidgetToGraphics.jl#L4758) | `content` and four bands | all | every child in order [4864](../../../source/platform/widget/WidgetToGraphics.jl#L4864), the documented exception | no code | the backward map, which adds `content` also for a band; `_select_in_band` [4801](../../../source/platform/widget/WidgetToGraphics.jl#L4801) corrects one case | no |
| Context menu wrapper [3449](../../../source/platform/widget/WidgetToGraphics.jl#L3449) | `child` | all | every key | no code | the backward map | no |
| Dialog [3671](../../../source/platform/widget/WidgetToGraphics.jl#L3671) | `content`, `buttons` | click, dwell, move | no: the reader answers Escape and returns for any other key [3677](../../../source/platform/widget/WidgetToGraphics.jl#L3677) | no | the backward map | no |
| Toolbar [8742](../../../source/platform/widget/WidgetToGraphics.jl#L8742) | `elements[i]` | click, down, up, dwell, wheel, move | no | no | `elements[i]` | no |
| Menu [4179](../../../source/platform/widget/WidgetToGraphics.jl#L4179) | `elements[i]` | click, dwell, wheel, move | reads the keys itself | no | the click is not re-rooted [4184](../../../source/platform/widget/WidgetToGraphics.jl#L4184) | no |
| Title pane [4945](../../../source/platform/widget/WidgetToGraphics.jl#L4945) | `content` | dwell, wheel, move | no | no | not re-rooted | no |
| Tooltip [3341](../../../source/platform/widget/WidgetToGraphics.jl#L3341) | `content` | dwell, wheel, move | no | no | not re-rooted | no |
| Table (two readers, [13913](../../../source/platform/widget/WidgetToGraphics.jl#L13913), [14319](../../../source/platform/widget/WidgetToGraphics.jl#L14319)), list and tree (`WidgetRowsPaneIoMap` [12013](../../../source/platform/widget/WidgetToGraphics.jl#L12013)) | `cells`, `items`, `roots` | not read for this matrix | | | | |

What the containers share: the entry `(x, y, child_iomap)` of each child, the hit test `_find_widget_child_point` ([1684](../../../source/platform/widget/WidgetToGraphics.jl#L1684)), the forward map `_map_child_forward` ([1831](../../../source/platform/widget/WidgetToGraphics.jl#L1831), 41 uses), the backward map of a point `_map_child_point`, and `read_child_event` of the layout slice ([LTG:251](../../../source/platform/layout/LayoutToGraphics.jl#L251)). Added by the check: the widget slice also has three shared routing helpers, `_route_to_children` with `_find_child_hit` ([1641](../../../source/platform/widget/WidgetToGraphics.jl#L1641)), `_read_children_move` ([1776](../../../source/platform/widget/WidgetToGraphics.jl#L1776)) and `_read_children_outward`, which the tooltip, the menu, the title pane, the toolbar, the dialog and the shell call. What each writes itself: which events go to a child, the copy of each event into the frame of the child, the choice of the selected child, Tab, the move and the leave (10 functions `_read_…_move` of 8 containers, beside the shared `_read_children_move` and `_read_single_child_move`; corrected by the check), and the steps that re-root the answer.

### I4. The ways to build a tree of widgets

| Way | Where | Count |
| --- | --- | --- |
| A constructor with keywords, written by hand | WD | 46 constructors; `WidgetTable` has 21 keywords ([WD:3327](../../../source/platform/widget/WidgetDocument.jl#L3327)), `WidgetText` 16, `WidgetScrollPane` 14 |
| A builder function that returns widgets | `make_pager_widget`, `make_filter_bar_widget`, `make_column_chooser_widget` ([WD:1140](../../../source/platform/widget/WidgetDocument.jl#L1140)), `make_embed_card`, `WidgetMessageBox`, `WidgetInputDialog`, `make_value_list_dialog`, `make_labeled_field` | about 12 |
| A general projection from an object | `ObjectToWidget`, `ObjectFieldToWidget`, `CellTableToWidgetTable`, `FaultToWidget`, `ReflectionToWidget` | 5 |
| A projection written by hand for one document type | every `…ToWidget` and `…ToLayout` | 72 structs, 67 `print_document`, 80 `read_intent` in this repository; 82 `print_document` in omnet-julia |
| A document of the widget slice with a projection of its own | `FindBarView`, `WidgetChoiceList` | 2 |
| The builder engine `@projection_template` | kernel | 0 of its 162 uses make widgets |
| `DocumentComposition.jl` | three seams that choose a view: `make_value_document`, `make_graphics_projection`, `refresh_document!` | it builds no widget |

A field that follows a value is written in three ways: a function as the argument (68 uses of `WidgetLabel(() -> …)` and `WidgetLink(() -> …)`), `set_cell_computation!(widget, f)` for the main field (19 methods in WD, 74 uses), and `set_cell_computation!(getfield(widget, :field), f)` for any field (261 uses in `source/` outside the widget slice and the kernel, 159 in omnet-julia; 45 of them set `enabled`, 43 `content`, 13 `visible`; the count includes fields of layouts and graphics).

### I5. The draw code

WTG has 47 projection structs with 703 fields, 399 of them a color, a text style or a stroke, and 375 calls of `_themed` that fill them from the theme. Shared draw code: lines 1 to 600 (styles, box) and 1270 to 1950 (text, size, canvas, routing), about 1 300 lines. The other 14 500 lines are per widget. Each leaf printer repeats the same frame by hand: the test of `visible` (42 times, counted again by the check), the cell of the box (41), `_push_box_parts!` (45), `_resolve_width` and `_resolve_height` (60, counted again by the check), `_cut_content_at_box!` (24), `_push_focus_ring!` (13).

## Findings

### WS-1 Each widget container has a reader of its own for the same job

- **Kind:** repeated-by-hand · **Value:** high · **Effort:** large · **Confidence:** high
- **Principle:** 7 (one mechanism for every widget, a missing case gets its row), 6 (decide locally, delegate one level).
- **Today:** A container does one job in its reader: it gives a pointer event to the child at the point, a key to the child that its selection names, Tab to the next child, a move to the child that the pointer leaves and to the child that it is on, and it re-roots the answer by the steps to that child. The layouts do this in shared functions: `_route_layout_event` ([LTG:480](../../../source/platform/layout/LayoutToGraphics.jl#L480)) serves the row, the column, the grid and the flow layout, and `_route_stack_event` ([LTG:2417](../../../source/platform/layout/LayoutToGraphics.jl#L2417)), which tests the topmost child first, serves the stack, the constraint and the anchored layout. The widget containers use neither. The composite ([WTG:4346](../../../source/platform/widget/WidgetToGraphics.jl#L4346) to 4513) and the split pane ([WTG:5643](../../../source/platform/widget/WidgetToGraphics.jl#L5643) to 5826) each hold a full copy, with `elements` in place of `children`: `_selected_composite_slot`, `_forward_composite_event_slot`, `_route_composite_event`, `_read_composite_move`, `_composite_tab`, and the same five for the split pane. The comments say so: "mirror of `_selected_composite_slot`" ([LTG:401](../../../source/platform/layout/LayoutToGraphics.jl#L401)), "mirroring `_composite_tab`" ([WTG:5740](../../../source/platform/widget/WidgetToGraphics.jl#L5740)). Twelve more containers each list by hand the events that they pass on (matrix I3). About 44 places in WTG and 6 in LTG (counted again by the check) build a copy of an event for the frame of a child, kind by kind (`MouseClick(evt.button, x, y, evt.count, evt.modifiers; time = evt.time)`), though `shift_event_position` ([EventPosition.jl:17](../../../source/platform/graphics/EventPosition.jl#L17)) moves any pointer event.
- **Example:**
  ```julia
  # today: the title pane passes on three kinds of event (WTG:4945)
  function read_intent(::WidgetTitlePaneToGraphicsCanvas, iomap::WidgetChildrenIoMap, evt)
      evt isa MouseMove && return _read_children_move(iomap, evt)
      _outside_widget(iomap, evt) && return nothing
      child_iomaps = getfield(iomap, :child_iomaps)[]::Vector
      evt isa MouseDwell && return _read_children_outward(iomap.input, child_iomaps, evt)
      evt isa MouseScroll || return nothing
      _route_scroll_to_children(child_iomaps, evt)
  end

  # proposed: one reader for every container (the name is a proposal)
  read_intent(::WidgetTitlePaneToGraphicsCanvas, iomap::WidgetChildrenIoMap, evt) =
      read_container_event(iomap, evt)

  # a container with parts of its own reads them first, then delegates
  function read_intent(p::WidgetSplitPaneToGraphicsCanvas, iomap::WidgetChildrenIoMap, evt)
      own = _read_splitter_event(p, iomap, evt)
      own === nothing ? read_container_event(iomap, evt; press_reaches_every_child = true) : own
  end
  ```
- **Problem:** A widget works in one container and not in another. By the code of the readers, a click and a key do not reach the content of a title pane or of a tooltip; a key other than Escape and a button down do not reach the content of a dialog; a key does not reach an item of a toolbar; the click of a menu comes back without the step of its item. The ring of a child selected as a whole is drawn by the composite, the card and the tabbed pane, and by no other widget container. Each new container, and each new kind of event, means one more hand-made list.
- **Proposal:** One function, in the graphics or the layout slice beside `read_child_event`, that takes the entries of the children and reads an event by the container protocol. The steps of a child come from the entry, or by identity as `_find_child_steps` ([WTG:1720](../../../source/platform/widget/WidgetToGraphics.jl#L1720)) and the kernel function `read_routed_child` ([ProjectionDefaults.jl:338](../../../source/kernel/projection/ProjectionDefaults.jl#L338)) already find them. The seven layouts of the two shared functions and every widget container call it; the order of the hit test, first child or topmost child, is an argument. A container keeps only what is its own: the dividers of a split pane, the strip of a tabbed pane, the scroll of a pane, the chevron of a card, the shortcuts of the shell. The decision stays local, as the owner asked in N7 of the Tab plan: each container still calls for itself and can read first.
- **What goes away:** the composite and split pane copies (about 250 lines), ten `_read_…_move` functions (corrected by the check), the `make_evt` closures and about 44 hand-made event copies, `_route_scroll_to_children`, `_route_click_to_children`, `_route_downup_to_children`, the per-container slot helpers. A rough count is 800 to 1 200 lines of WTG and 150 of LTG.
- **What stays:** every special behaviour of a container, read before the shared call; the shell rule that a shortcut fires first; the rule that a key goes only where the selection is.
- **Risk and open questions:** The entries of the layouts hold cells and those of the widgets hold numbers; the shared function must take both. The shell gives a key to every child in order today; whether that stays is the owner's choice. The table and the tree readers were not read; they may need to stay as they are.
- **Related plans:** `plan/pending/tab-and-the-arrows-reach-every-part-that-takes-the-keyboard.md` (deferred; N7 keeps the walk in the parts, which this proposal keeps). `plan/pending/a-click-reaches-the-innermost-part-in-every-view.md` (in progress; it repairs views one by one and does not join the readers).
- **Check:** confirmed-with-corrections. Value after the check: high. Opened: `_route_layout_event` (LTG:480), `_route_stack_event` (LTG:2417), the readers of the composite (WTG:4346 to 4513), the split pane (WTG:5643 to 5826), the tooltip, the dialog, the menu, the title pane and the toolbar. The composite and the split pane are copies of the layout reader, function by function; the tooltip and the title pane pass a dwell, a wheel and a move only; the dialog passes a click, a dwell and a move and answers `nothing` for every key but Escape; the menu gives a click with `_route_click_to_children` and adds no step. No design document gives a reason for these differences: `widget.md` ("A press goes by coordinate", "A key goes by selection") states one protocol for all containers. No plan joins the readers; N7 of the Tab plan asks that each container walks inside itself, and a shared function that each container calls keeps that, as the four layouts of `_route_layout_event` show. Corrections: (1) the layouts are not one baseline: `_route_stack_event` passes click, wheel, move and the keys only, so by the code a button in a `StackLayout`, a `ConstraintLayout` or an `AnchoredLayout` gets no button down, so no pressed look, and no dwell; this makes the finding stronger, and matrix I3 is corrected. (2) The widget slice already has three shared helpers (`_route_to_children`, `_read_children_move`, `_read_children_outward`) that six containers call, so the work is to finish a join that is begun, not to start one. (3) The count of `_read_…_move` is 10, and of event copies 44 in WTG. (4) `WidgetTitlePane` has no use outside the widget slice in both repositories, so nobody meets its dead click today. What the proposal must keep: a container that holds an event back on purpose. A card ends a plain click that nothing in it answers (`widget.md`, "A card is a solid surface"); the dialog answers a click outside its card with the close and joins the close to the answer of a button; the toolbar maps a laid-out index back to its element; the split pane adds the step `child` of a `LayoutConstraint`; the composite and the split pane give a button down to every child when none is hit, for the divider of a nested split. Each is an argument or a step before the shared call, so no feature is lost.

### WS-2 The gestures of a control are code in its reader, not rows of its gesture table

- **Kind:** several-ways · **Value:** high · **Effort:** medium · **Confidence:** high
- **Principle:** 3 (a person, the assistant and a test make the same operations), 7, 10 (the surface comes by reflection).
- **Today:** The kernel has one table of gestures for each document type. `fire_gesture_bindings` ([GestureBinding.jl:108](../../../source/kernel/binding/GestureBinding.jl#L108)) fires a row, lists every row for the key help and the command palette, and runs a row by its name. 44 `@gestures` tables in 35 files use it (counted by `grep`), 43 of them outside the widget slice. In the widget slice the table holds the tooltip ([WD:4173](../../../source/platform/widget/WidgetDocument.jl#L4173)), the context menu, the find bar, and one control, the link: the reader of `WidgetLink` ends with `read_bound_gesture` and nothing else ([WTG:3277](../../../source/platform/widget/WidgetToGraphics.jl#L3277), table at [OpenPageOperation.jl:125](../../../source/platform/widget/OpenPageOperation.jl#L125)). Every other control writes its gestures as code: the button ([WTG:3092](../../../source/platform/widget/WidgetToGraphics.jl#L3092)), the checkbox ([WTG:2906](../../../source/platform/widget/WidgetToGraphics.jl#L2906)), the switch, whose two readers are the text of the checkbox readers with another slot name ([WTG:10166](../../../source/platform/widget/WidgetToGraphics.jl#L10166)), the toggle, the radio group, the spin box, the menu. An instance can replace a gesture only where the reader calls `read_bound_gesture` first: 8 widget types and the row of a tree, `WidgetTreeNode`, have the field `gestures`. The plan that added the field says that the built-in gestures "were NOT reified into a `@gestures WidgetButton` domain table" as a simplification, because that session could not run the tests (`plan/done/widget-per-instance-gestures.md`, "Implementation notes").
- **Example:**
  ```julia
  # today (WTG:2918): the keys of a checkbox are code
  function read_intent(::WidgetCheckboxToGraphicsCanvas, iomap::WidgetValueIoMap, evt)
      _outside_widget(iomap, evt) && return nothing
      w = iomap.input
      w.enabled === false && return nothing
      op = read_bound_gesture(w, evt); op === nothing || return op
      _is_plain_typed(evt, '\n', ' ') || return nothing
      _checkbox_toggle(iomap)
  end

  # proposed: rows, as FindBarView has them (FindBarViewGestures.jl:95); a sketch
  @gestures WidgetCheckbox begin
      MouseClick(:left) => "Tick or clear the box" => make_toggle_operation(doc)
      KeyPress(' ')     => "Tick or clear the box" => make_toggle_operation(doc)
      KeyPress('\n')    => "Tick or clear the box" => make_toggle_operation(doc)
  end
  ```
- **Problem:** The key help and the palette can list "open" for a link and nothing for a button or a checkbox. Nothing can run "tick the box" by name, so the assistant and a test must make a click at a point. A toggle, a radio group, a select, a slider and a spin box take no gesture of an instance. The table of the keys in `widget.md` ("What a control reads") is kept by hand because the code has no table.
- **Proposal:** Each control declares its gestures as rows of its type. One shared reader for a control does the test of the bounds, the test of `enabled`, the Alt rules of the text, and then `read_bound_gesture`, as the link does today.
- **What goes away:** the gesture branches of about 12 readers, the repeated lines "bounds, enabled, bound gesture" in each, the field `gestures` as a special case of 8 types (every widget then takes instance rows), the hand-kept table in `widget.md`.
- **What stays:** every gesture of today. The pressed look of a button stays view state that its rows write.
- **Risk and open questions:** A row gets `(document, event)` and not the IO map. A gesture that depends on what was drawn, such as the segment of a toggle group under `x`, the stepper of a spin box or the track of a slider, needs the IO map, and a store through a value slot needs the IO map of the slot. Either the row gets the IO map, or these stay in the reader. A press that answers `nothing` for a query of all rows must stay cheap.
- **Related plans:** `plan/done/widget-per-instance-gestures.md` (done; left this step out). `plan/pending/key-chords-from-bindings.md` (deferred; it reads the same tables).
- **Check:** confirmed-with-corrections. Value after the check: medium. Opened: `GestureBinding.jl` 60 to 215, the readers of the checkbox (WTG:2906 to 2927), the switch (WTG:10166 to 10182), the button (WTG:3080 to 3103) and the link (WTG:3270 to 3281), `OpenPageOperation.jl:125`, `WidgetValueSlot.jl`, and the note of 2026-07-02 in `plan/done/widget-per-instance-gestures.md`. The facts hold: the link is the one control whose reader ends in `read_bound_gesture`; the two readers of the switch are the text of the checkbox readers; the plan left the tables out because that session could not run the tests, which is no design reason. No pending plan does the step. Corrections: (1) the example row can not be written as shown. A row gets `(document, event)`, and the toggle of a checkbox is `make_slot_store_operation(iomap, :content, …)`: with a document in the slot the store is the answer of the reader of the child, which needs `value_iomap`. This holds for all 8 value widgets of `_VALUE_WIDGET_TYPES`, so for most controls, and for the gestures that read what was drawn (a segment, a stepper, a track). Rows of today serve only the button, the toolbar item and the menu item. (2) No kernel change is needed for the others: `fire_gesture_bindings` takes any list of bindings ("a document, an instance, a projection", `GestureBinding.jl`), so the reader of a value widget can fire rows that it makes over its IO map; the listing then comes through the reader with `CollectIntents`, not from `collect_document_gesture_bindings` of the type. (3) The kernel has two forms on purpose, `@gesture_case` compiled in a reader and `@gestures` as a table (`gesture.md`, "The gesture pattern and the table"), and the readers of the widgets use the first. The value is lowered because the gain is a listing and a run by name; no gesture is missing today, and the assistant can already write the slot of a widget by an operation. No feature is lost.

### WS-3 A control says what a press does in five ways, and a typed operation needs a closure

- **Kind:** several-ways · **Value:** high · **Effort:** medium · **Confidence:** medium
- **Principle:** 3 (an edit is a typed operation; there is one way to edit), 2 (the reader maps an answer back).
- **Today:** (1) `action`, an `Action` ([WD:3842](../../../source/platform/widget/WidgetDocument.jl#L3842)) whose `callback` is a closure; the press answers `InvokeActionOperation` and its evaluation calls the closure ([WD:4092](../../../source/platform/widget/WidgetDocument.jl#L4092)). A `grep` finds 55 such closures, and 20 of them only wrap a typed operation: `editor -> evaluate_operation(editor, StopTaskGroupOperation(doc))` ([TaskGroupToWidget.jl:323](../../../source/platform/task/TaskGroupToWidget.jl#L323)), also for a menu item ([AssistantToWidget.jl:471](../../../source/platform/assistant/AssistantToWidget.jl#L471)). (2) `operation`, a field of `WidgetMenuItem` only ([WD:931](../../../source/platform/widget/WidgetDocument.jl#L931), read at [WTG:3849](../../../source/platform/widget/WidgetToGraphics.jl#L3849)), 45 uses. (3) `gestures` on the control, as `make_open_page_gestures` gives a button ([OpenPageOperation.jl:95](../../../source/platform/widget/OpenPageOperation.jl#L95)). (4) The view keeps the `Action` in its IO map and its reader turns the `InvokeActionOperation` with that same action into its own operation ([ExplorerToWidget.jl:224](../../../source/platform/explorer/ExplorerToWidget.jl#L224); 13 lines compare `.action ===`, counted by `grep` over both repositories). (5) `dialog` of a button ([WTG:3114](../../../source/platform/widget/WidgetToGraphics.jl#L3114)).
- **Example:**
  ```julia
  # today
  stop = WidgetButton("Stop"; action = editor -> evaluate_operation(editor, StopTaskGroupOperation(doc)))
  item = WidgetMenuItem("Stop"; operation = StopTaskGroupOperation(doc))      # only a menu item can
  # proposed: the command of every control can hold the operation
  stop = WidgetButton("Stop"; operation = StopTaskGroupOperation(doc))
  ```
- **Problem:** An operation inside a closure is applied inside the evaluation of `InvokeActionOperation`. No reader above the button sees it, so no projection can map it, and the list of gestures shows the action and not the edit. `InvokeActionOperation` has no method of `make_inverse_operation`, and the default is `nothing` ([Inversion.jl:5](../../../source/kernel/operation/Inversion.jl#L5)), which a history records as a barrier that undo does not pass ([UndoDocument.jl:44](../../../source/platform/undo/UndoDocument.jl#L44)). So the same edit can be undone from a menu item with `operation` and not from a button with a closure. I did not run this.
- **Proposal:** The command, `Action`, holds an operation or a function that makes one, beside the callback for a command that has an effect outside the data. A press of any control that shows the command answers that operation, and it travels up as every answer does. `WidgetMenuItem.operation` becomes the same field.
- **What goes away:** the 20 closures that wrap an operation, the second field on the menu item, most uses of way 4, and `make_open_page_gestures` on a button.
- **What stays:** a callback for a command that starts a process or opens a window; a shortcut; `dialog`.
- **Risk and open questions:** `WidgetMenuItem.operation` is relative to the part of a context menu (`EditMenuPartOperation`, [ContextMenuOperation.jl:123](../../../source/platform/widget/ContextMenuOperation.jl#L123)); the shared field must say what its operation is relative to. An operation made at print time can be stale at the press, so a function that makes it at the press is the safer form.
- **Related plans:** none found in `plan/pending`.
- **Check:** weakened. Value after the check: medium. Opened: `Action` and `InvokeActionOperation` (WD:3842, WD:4092), `_button_primary_op` (WTG:3114), `_make_menu_item_choice` (WTG:3849), `EditMenuPartOperation` (`ContextMenuOperation.jl:123`), `Inversion.jl:5`, `is_undo_step` (`UndoDocument.jl:207`), `_record_operation` (`UndoBufferToAny.jl:153`), `ExplorerToWidget.jl:224`, and `plan/done/one-action-one-operation.md`, which the report did not name. What holds: `Action` can hold a callback only; 21 closures only wrap `evaluate_operation(editor, …)` (14 in this repository, 7 in omnet-julia); `is_undo_step` keeps an `InvokeActionOperation`, it has no inverse, so by the code each press of such a button under a history writes a barrier entry. The menu item got `operation` on 2026-10-03 for this very reason ("Hide column" as a step of undo, `plan/pending/view-and-edit-a-data-frame.md`, step 4b.1). What is smaller than stated: the ways are two, not five. `gestures` and `dialog` are other features (more gestures on one control; a window to open). Way 4 is a result of way 1, and it stays where the view needs the gesture, as the explorer does to place its menu. `WidgetMenuItem.operation` is no general typed command: it is relative to the part of a context menu, the context menu window lifts it, and its own evaluation does nothing, so in a menu bar it has no effect; the example line "only a menu item can" misleads. My `grep` finds 88 lines `action = … ->` or `callback = … ->` in both repositories, not 55. What the proposal must not lose: `plan/done/one-action-one-operation.md` chose one operation type for every activation so that each reader on the way up names one type; `MarkdownToLayout.jl:212` and `RstToLayout.jl:178` pass `InvokeActionOperation` by name and answer `nothing` for a type that they do not know. A button in an embedded card whose press answers its own typed operation would be dead there, unless the operation is self-contained and every such reader passes self-contained operations. The form that keeps both: `InvokeActionOperation` stays the one type that travels, and the `Action` holds the operation, so the invocation has an inverse and a listing can show the edit.

### WS-4 The value of a control is bound in two ways and held in five shapes

- **Kind:** several-ways · **Value:** high · **Effort:** medium · **Confidence:** high
- **Principle:** 2 (a view is bidirectional through its IO map), 7.
- **Today:** The value slot ([WidgetValueSlot.jl:39](../../../source/platform/widget/WidgetValueSlot.jl#L39), [68](../../../source/platform/widget/WidgetValueSlot.jl#L68)) is the general way: the slot holds a plain value or a document such as an `ObjectField`, the widget prints the document as a child, reads the value from the output of the child, and asks the reader of the child for the operation that stores a new value. Eight widgets have it ([WidgetValueSlot.jl:88](../../../source/platform/widget/WidgetValueSlot.jl#L88)). The slider and the toggle group also have `target`, `field`, and `mapping` or `values` ([WD:2455](../../../source/platform/widget/WidgetDocument.jl#L2455), [WD:2754](../../../source/platform/widget/WidgetDocument.jl#L2754)): a pick writes `target.field`, and nothing reads it back. The slider has both ([WTG:10457](../../../source/platform/widget/WidgetToGraphics.jl#L10457)); the toggle group has only the second, though the radio group, which does the same job, has a slot. The name of the slot is `content`, `checked`, `pressed`, `selected` or `value`. "One of N" is an index in a slot (radio group), an index with `values` (toggle group), or the value itself (select).
- **Example:**
  ```julia
  # today (FrameStatisticsToWidget.jl:231): the write and the read are two statements
  choice = WidgetToggleGroup(Any[labels...]; values = Any[values...], target = statistics, field = String(field))
  set_cell_computation!(getfield(choice, :selected),
                        () -> something(findfirst(==(getproperty(statistics, field)), values), 1))
  # proposed: one binding, as a select has it today
  choice = WidgetToggleGroup(Any[labels...]; values = Any[values...], value = ObjectField(statistics, String(field)))
  ```
- **Problem:** With `target` the author writes the binding twice. Three of the four callers that I read add the read half by hand ([NavigatorToWidget.jl:141](../../../source/platform/navigator/NavigatorToWidget.jl#L141), [ConversationToWidget.jl:622](../../../source/platform/conversation/ConversationToWidget.jl#L622), [McpLogToWidget.jl:91](../../../source/platform/mcplog/McpLogToWidget.jl#L91)); the slider of omnet-julia computes its knob once at the print (`SimulationEmbedToWidget.jl:382`), so the knob does not follow a change made elsewhere. The plan of the value slot states the gap: "Unifying the two mechanisms is outside this plan" (`plan/done/a-form-edits-a-plain-value.md`, line 705).
- **Proposal:** Every value widget has one slot with one name, `value`. A choice widget holds the chosen value, with `values` beside the labels, as the select does. `target` and `field` go away, because `ObjectField(target, field)` in the slot says the same in both directions. The `mapping` of a slider becomes a pair of functions, or a small projection between the slot and the track.
- **What goes away:** `target`, `field` on two widgets, `resolve_slider_write`, `resolve_toggle_group_write` (both exported), the hand-written read halves, four of the five slot names.
- **What stays:** the three looks of a choice (radio, segments, dropdown), the step look, the logarithmic slider.
- **Risk and open questions:** A value widget with a document in its slot needs the nested dispatch of `make_object_field_widget_dispatch`, or its print loops ([WidgetValueSlot.jl:13](../../../source/platform/widget/WidgetValueSlot.jl#L13)); a toggle group in every table of widgets then needs that nesting. The rename of the slot fields changes saved `.pred` files, which the owner said is no design argument.
- **Related plans:** `plan/done/a-form-edits-a-plain-value.md` (done; left the unification open). No pending plan.
- **Check:** confirmed-with-corrections. Value after the check: medium. Opened: `WidgetValueSlot.jl` in full, `WidgetSlider` and `resolve_slider_write` (WD:2406 to 2463), `WidgetToggleGroup` and `resolve_toggle_group_write` (WD:2722 to 2764), `_make_slider_write` (WTG:10457), the four callers named, `SimulationEmbedToWidget.jl:382`, and lines 705 to 710 of `plan/done/a-form-edits-a-plain-value.md`. The facts hold: all four callers add the read half by hand, the fourth is the example itself; the plan kept `target` and `field` and left the join open; no pending plan takes it up. Corrections: (1) the value slot is not general today, and this is the main cost that the report puts under risk. A document in a slot prints only under a table of `make_object_field_widget_dispatch`, which nests the 8 value widgets over `ObjectFieldToValue`. Only the forms of `ObjectToWidget` and one table of the task group (`TaskGroupToWidget.jl:1654`) use it; under any other table the print makes the widget again without end (`WidgetValueSlot.jl:13` to 18). So the proposal first needs the nesting in the standard widget rows, for the navigator, the conversation, the MCP log, the statistics, the research and the workflow views. (2) The extent is small: 13 uses of the slider and the toggle group in both repositories, 12 of them with `target`. (3) A slider with `mapping` writes one way today; with a slot the caller must also give the inverse, as omnet-julia has it in `_embed_speed_fraction`. The value is lowered for (1) and (2). No feature is lost; the rename of the slot fields to `value` is a small gain on its own and touches `content` of `WidgetText`, which also holds a document that the widget draws.

### WS-5 The widget constructors are written by hand and take plain values only

- **Kind:** complicated-api · **Value:** high · **Effort:** medium · **Confidence:** high
- **Principle:** 1 (every field is a reactive cell), 7. `cell.md` line 371: "Let the `@document` macro wrap the fields of a document in cells. Do not write the wrapping by hand."
- **Today:** WD writes one constructor for each widget. Each wraps every field in `Cell(…)` and repeats the same keywords: `margin=nothing, border=nothing, padding=nothing` is on 43 lines and `visible::Bool=true` on 45 (counted again by the check). `@document` makes a constructor that takes a raw value or a cell for each field, and keyword and positional forms ([DocumentMacro.jl:694](../../../source/kernel/document/DocumentMacro.jl#L694), [712](../../../source/kernel/document/DocumentMacro.jl#L712)); it has no form with the content first and the other fields as keywords, which is the form that every widget wants. Because a keyword is typed and wrapped, a caller can not give a cell or a function. Six widget types take a function or a cell for some fields (corrected by the check): the label, the link and the badge through `_make_shown_cell` ([WD:161](../../../source/platform/widget/WidgetDocument.jl#L161)), the tab label through it and `_make_value_cell`, the progress bar and the progress ring through `_make_share_cell` ([WD:2331](../../../source/platform/widget/WidgetDocument.jl#L2331)); 19 methods `set_cell_computation!(w::WidgetX, f)` do it for one main field; for any other field the caller reaches under the document (counts in I4). Only `scroll_position` and `follow_end` of a scroll pane take a cell that the caller shares ([WD:1730](../../../source/platform/widget/WidgetDocument.jl#L1730)).
- **Example:**
  ```julia
  # today (TaskGroupToWidget.jl:387)
  button = WidgetButton(text; size = p.button_size, tooltip, action = run)
  set_cell_computation!(getfield(button, :enabled), enabled)
  # proposed: each keyword takes a value, a cell or a function of no arguments
  button = WidgetButton(text; size = p.button_size, tooltip, action = run, enabled)
  ```
- **Problem:** The most common need of a view, a field that follows the data, has three spellings, and the general one works below the property access of a document. A view that wants to keep the state of a widget in its own document can share a cell for two fields of one widget type only.
- **Proposal:** One rule for every widget field: a value, a cell (kept as it is, so two documents can share it), or a function of no arguments (a computed cell). One generated constructor form: the leading required fields by position, the others by keyword. Either `@document` gets that form, or a small macro of the widget slice adds the shared fields (`visible`, the three insets, `style`, `tooltip`) and the form, as `@document` adds `selection` today.
- **What goes away:** about 46 hand-written constructors (roughly 500 lines), the 19 `set_cell_computation!` methods, `_make_shown_cell` and `_make_value_cell` as special cases, and the reason for under half of the 420 `getfield` sites (corrected by the check: about 190 of them set a field of a widget; 84 set `elements` or `children` of a layout or a collection, 42 set `x`, `y`, `w` or `h` of a graphics node, and 32 set `selection` or `mouse_target`).
- **What stays:** the sugar that carries logic: `resolve_action` for a button, the 1-based `selected` of a list, `_as_tab_page`, the checks of `WidgetTable`.
- **Risk and open questions:** A field whose value is itself a function (`validator`, `find`, `choose`, `mapping`, a callback) must be marked, so the rule does not turn it into a computation. A computed cell takes no write, so a field that a reader writes (`pressed`, `scroll_position`) must refuse a function. The change of `@document` reaches the kernel; `DocumentMacro.jl` may be sealed.
- **Related plans:** none found.
- **Check:** confirmed-with-corrections. Value after the check: medium. Opened: the constructors of the label, the link, the badge, the tab label, the progress bar, the slider, the toggle group and the menu item in WD, `_make_shown_cell`, `_make_value_cell`, `_make_share_cell`, the docstring of `@document` (`DocumentMacro.jl` 680 to 730), `cell.md` 360 to 372, `macros.md` 240 to 250, and `SEALING.md` (`DocumentMacro.jl` is not sealed). The core holds and is stronger than stated: the constructor that `@document` generates takes a cell for any field and keeps it, and the hand-written constructors of the widgets take that away, because a keyword such as `enabled::Bool=true` is typed and then wrapped. `@document` has keyword constructors and positional ones with defaults, and no form with the first fields by position and the rest by keyword. Corrections, made where they stand: 43 and 45 lines, not 44 and 50; six widget types take a function or a cell today, not three; about 190 of the 420 `getfield` sites set a field of a widget (45 `enabled`, 43 `content`, 13 `visible`, 13 `value`, 9 `selected`), and the others are layouts, graphics nodes and the follow of the selection, which this proposal does not touch. A counter-point: `set_cell_computation!(getfield(obj, :field), f)` is the documented way of the kernel to bind a field after the construction (`cell.md:365`, `macros.md:247`), not a way around the document, so it stays valid and the change adds a shorter spelling at the construction. The value is lowered because the gain is one line at each of about 190 sites and about 46 constructors; nothing fails to combine today. What the proposal must keep: a field whose value is a function (`validator`, `mapping`, `find`, `choose`, a callback) must not become a computation, so the rule belongs in a macro of the widget slice with a mark for each such field, not in `@document` for every domain; the conversions of the hand-written constructors (`Int(width)`, `Float64(value)`, `String(field)`, `CellVector(…)`, `resolve_action`, `_make_link_target`) must stay.

### WS-6 Each printer assembles the frame of its widget by hand

- **Kind:** repeated-by-hand · **Value:** medium · **Effort:** large · **Confidence:** medium
- **Principle:** 7; the settled rule that a widget cuts its content at its own size.
- **Today:** The parts of the frame are shared functions, and each printer calls them in its own order: the test of `visible`, the cell of the box, the insets, `_push_box_parts!`, the size by `_resolve_width`, the cut by `_cut_content_at_box!`, the focus ring, the canvas, the IO map. Compare the toggle ([WTG:11334](../../../source/platform/widget/WidgetToGraphics.jl#L11334)), the checkbox ([WTG:2853](../../../source/platform/widget/WidgetToGraphics.jl#L2853)) and the switch ([WTG:10121](../../../source/platform/widget/WidgetToGraphics.jl#L10121)): the toggle resolves its size from the offer and cuts its text; the checkbox and the switch draw a label and do neither. By the count per section, 45 printers draw box parts and 24 call a cut.
- **Example:**
  ```julia
  # today: about 12 of the 25 lines of a small printer are the frame (WTG:11334 to 11361)
  # proposed (a sketch): the printer gives the content, one function gives the frame
  print_document(p::WidgetToggleToGraphicsCanvas, recursion, w::WidgetToggle, ctx) =
      print_boxed_widget(p, w, ctx; focus_ring = true) do box, state
          (; width = text_width, height = text_height, elements)   # the content only
      end
  ```
- **Problem:** A rule of the frame holds only where a printer remembers the call. The next widget copies 12 lines and can leave one out, as the checkbox leaves out the cut.
- **Proposal:** One function builds the frame of a leaf widget around a content that the printer gives: visibility, box, size, cut, ring, light, pointer shape, canvas and IO map. A container uses the same function with its children as the content.
- **What goes away:** the frame lines of about 40 printers, a rough count of 400 to 600 lines; the 42 early returns for `visible`.
- **What stays:** the three layers of color and every style field; the box in the IO map.
- **Risk and open questions:** Several printers build parts in cells of their own so that a light or a caret repaints little (`PAR-LIGHT-KEEPS-LAYOUT`); the shared frame must keep those cells apart. I read 8 printers in full and counted the rest.
- **Related plans:** `plan/pending/guards-keep-the-frame-short-at-any-size.md` and `plan/pending/printer-locality.md` touch the same printers; I did not read them.
- **Check:** weakened. Value after the check: low. Opened: the printers of the toggle (WTG:11334 to 11363) and the checkbox (WTG:2853 to 2888), `plan/done/a-widget-cuts-its-content-at-its-box.md` (done 2026-11-15, D1 to D8), and `test/platform/projection/LayoutRulesTest.jl`. The repetition is real, and the counts hold after the corrections above (42 tests of `visible`, 60 calls of the two resolve functions). What is weaker: (1) the statement that a rule of the frame holds only where a printer remembers the call. `test_layout_rules()` checks the ink of every widget type against its box, also with a set size, a test set fails when a widget type has no kind, and `_RULES_INK_BROKEN` lists the known breaks. So the rule has a guard for every type, and a new widget that leaves a call out fails there. Whether the checkbox breaks D2 of the cut plan was not run by the report and not by me. (2) The sketch can not be written as shown. The content is placed inside the resolved box: the toggle centers its text in `content_width`, which comes from `_resolve_width`, and the box parts go under the content and need the same size. So the shared frame needs two steps from each printer, a measure and then a draw at the resolved size. (3) The printers return four IO map types (`WidgetValueIoMap`, `WidgetBoxIoMap`, `WidgetChildrenIoMap` and IO maps of their own) and two kinds of canvas (`_reactive_canvas`, `_reactive_canvas_cell` with a build), so the frame can not make the IO map for all. The parts of the frame are shared functions already; what repeats is the order of about 12 calls. No feature is lost by the proposal, but the gain is 400 to 600 of 15 800 lines for a large change of every printer, the day after the cut plan touched them.

### WS-7 A view that builds widgets is written by hand; the builder engine makes syntax only

- **Kind:** partial-feature · **Value:** medium · **Effort:** large · **Confidence:** low
- **Principle:** 2 (a general step knows no domain), 7.
- **Today:** `@projection_template` takes a builder and derives the IO map, the reader and both maps from the `bound(…)` marks in it. All 162 uses make syntax (counted by `grep`; 0 names end in `ToWidget` or `ToLayout`). A view that makes widgets writes its printer, and where it needs them an IO map, a reader that turns the answers of its widgets into its own operations, and both maps. It also calls `follow_widget_output!` ([WD:40](../../../source/platform/widget/WidgetDocument.jl#L40)) so that its widgets hold the selection (45 calls). [McpLogToWidget.jl:84](../../../source/platform/mcplog/McpLogToWidget.jl#L84) is a small example of the pattern.
- **Example:**
  ```julia
  # today (McpLogToWidget.jl:84 to 108, shortened)
  function print_document(p::McpLogToWidget, recursion, log::McpLog, ctx)
      heading = WidgetLabel(() -> string(log.count, " calls"))
      calls = VerticalLayout(Any[])
      set_cell_computation!(getfield(calls.children, :elements), () -> Cell[Cell(_build_block(p, e)) for e in log.entries])
      follow_built_children!(calls)
      root = VerticalLayout(Any[heading, calls])
      iomap = ChildrenIoMap(p, log, root, Cell(Any[]))
      follow_widget_output!(root, log, path -> map_reference_forward(p, iomap, path))
      iomap
  end
  ```
- **Problem:** Each of about 150 views repeats the wiring, and each can leave a part out; the plan of the innermost click lists the views that drop a click or map nothing.
- **Proposal:** Let the builder engine, or a sibling of it, take a builder that returns widgets and layouts, with the same marks for "this widget shows this field". The pairs give the maps, the selection of the output and the re-rooting of the answers.
- **What goes away:** the hand-made IO maps and maps of the simple views, and the `follow_…` calls.
- **What stays:** a view with real logic keeps its own reader.
- **Risk and open questions:** I did not read `ProjectionTemplate.jl`, so I do not know how much of it assumes a syntax tree. This finding belongs mostly to the projection system and to every domain.
- **Related plans:** `plan/pending/a-view-names-the-domain-part-under-a-point.md` (pending, not started; it proposes a child IO map for each part that a view prints, which covers the maps). `plan/pending/projection-template-engine.md` (in progress; syntax only).
- **Check:** weakened. Value after the check: low. Opened: the head of `ProjectionTemplate.jl` (1 755 lines; the report did not read it), `follow_widget_output!` and `follow_built_children!` (WD:27 to 60), `McpLogToWidget.jl:84` to 108, and the two plans. The counts hold: 162 uses of `@projection_template` outside the kernel and none makes a widget or a layout; 72 structs; 82 printers in omnet-julia; 48 calls of `follow_widget_output!` in both repositories (23 here). The problem is real: a view must itself call `follow_widget_output!`, and `follow_built_children!` for each layout whose children a computation builds, and a view that leaves one out shows no selection. The proposal is not shown to work. The engine builds the output of a print from a blueprint with marks, and derives the maps from the pairs of that one build; a view of widgets binds fields by computed cells and builds children by a computation that runs after the print (the example sets the computation of `calls.children`), so the pairs do not exist at the print. The header of the engine says that it names no container type, so the kernel does not forbid the step, but nobody measured it. Two things already do parts of this job: the value slot with an `ObjectField` is "this widget shows this field" in both directions, and `plan/pending/a-view-names-the-domain-part-under-a-point.md` plans a child IO map for each part that a view prints, which covers the maps; that plan is not started and every decision in it waits for the owner. So the finding is a direction for that plan, not a proposal that stands by itself.

### WS-8 The component slice is a concept with no user

- **Kind:** redundant · **Value:** low · **Effort:** small · **Confidence:** high
- **Principle:** 11 (design as from scratch), 8 (reuse an existing view).
- **Today:** `source/platform/component` holds an abstract type and one document, `ComponentMasterDetail` ([ComponentDocument.jl:27](../../../source/platform/component/ComponentDocument.jl#L27)). No projection draws it and no other slice names it; only the platform package includes the module. Its own document says so (`documentation/package/platform/component/component.md`, line 19). The job that the slice describes, a document that a projection turns into widgets, is done by `FindBarView` ([WD:2239](../../../source/platform/widget/WidgetDocument.jl#L2239)), `WidgetChoiceList` ([WidgetChoiceList.jl:73](../../../source/platform/widget/WidgetChoiceList.jl#L73)), the explorer, the navigator and the dashboard, and none of them is a `ComponentDocument`.
- **Example:**
  ```julia
  ComponentModule.ComponentMasterDetail(master, detail)   # builds a document that nothing can draw
  ```
- **Problem:** A reader of the anatomy expects a layer between a domain and the widgets, and finds a type with no behaviour.
- **Proposal:** Remove the slice, or decide that a component is any document with a `…ToWidget` projection and keep no type for it. No feature goes away, because the document can not be drawn or edited.
- **What goes away:** 76 lines, one module, one package document, one plan.
- **What stays:** master and detail as the explorer and the navigator do it.
- **Risk and open questions:** The owner may still want the layer; then the plan needs a new start.
- **Related plans:** `plan/pending/component-document.md` (status "in progress" of 2026-08-12; the projection and the example are open; stale).
- **Check:** confirmed. Value after the check: low. Opened: both files of `source/platform/component`, `documentation/package/platform/component/component.md` and the head of `plan/pending/component-document.md`. A `grep` for `ComponentModule`, `ComponentMasterDetail` and `ComponentDocument` over `source`, `test`, `example`, omnet-julia and inet-julia finds no use outside the slice. The slice is the first step of a pending plan whose status is "in progress" of 2026-08-12, and `component.md` records "A component is a document" as a design decision. So to remove the slice is to drop that plan, which only the owner can decide. No feature goes away: nothing draws or edits the document.

### WS-9 The widget slice holds operations and seams of other slices

- **Kind:** wrong-place · **Value:** low · **Effort:** small · **Confidence:** medium
- **Principle:** 5 (independent parts), the slice rules of the platform.
- **Today:** `WidgetModule` includes `OpenPageOperation.jl` (evaluated by the navigator), `OpenFileOperation.jl` (the file system), `AddExplorerEntryOperation.jl` (the explorer), `DocumentComposition.jl` (three seams between packages), `LetterMatch.jl` (the match of a typed query), `compute_code_pieces` ([WD:294](../../../source/platform/widget/WidgetDocument.jl#L294), the seam of a language), and `ContextMenuWindow.jl` (a wrapper at the screen). `widget.md` gives the reason: the slices that make these operations load below the slices that evaluate them.
- **Example:**
  ```julia
  using ..WidgetModule: OpenFileOperation     # a tree row that opens a file needs the widget slice for it
  ```
- **Problem:** The widget set can not be read or loaded as "the widgets" alone, and a slice that only makes a request depends on all widgets.
- **Proposal:** A small slice of requests and seams below the widget slice, or `DomainModule`, which already holds `accepts_pasted_text` and `compute_context_menu`. Only the bindings of `WidgetLink` stay with the widgets.
- **What goes away:** nothing; about 600 lines move.
- **What stays:** every operation and seam.
- **Risk and open questions:** `OpenPageOperation.jl` also holds the bindings of the link; the file splits. `plan/pending/packages-compose-by-seams.md` may place the seams elsewhere.
- **Related plans:** `plan/pending/packages-compose-by-seams.md` (design; not read past its head).
- **Check:** weakened. Value after the check: low. Opened: `WidgetModule.jl` 132 to 158, the six files named (796 lines together), `widget.md` line 240, and P4 and step 4 of `plan/pending/packages-compose-by-seams.md`, which the report did not read past its head. The present place has a stated reason for each part. For the two operations: the slices that make them load below the slices that evaluate them (`widget.md:240`). For the three seams of `DocumentComposition.jl`: P4 of the seams plan put them in Widget as "the lowest package that both the data frame package and the display load", and step 4 of that plan is done. Corrections: `ContextMenuWindow.jl` (410 lines) uses widget types, so it can not move below the widget slice; without it about 390 lines could move, not 600. `OpenFileOperation.jl`, `AddExplorerEntryOperation.jl`, `DocumentComposition.jl` and `LetterMatch.jl` name no widget type, so the move is possible, and `DomainModule` loads below the widgets. What is left of the finding: the reasons explain why the files are in a low slice, not why in this one. No feature is lost, and nothing gets simpler for the next domain or widget.

## Covered by plans

- Tab and the arrows reach every stop, also in a list, a table, a tree and an accordion: `plan/pending/tab-and-the-arrows-reach-every-part-that-takes-the-keyboard.md` (deferred).
- The text of more widgets takes a caret, and views that drop a click: `plan/pending/a-click-reaches-the-innermost-part-in-every-view.md` (in progress, step 5).
- A point in a table cell or an accordion maps on into what the cell holds: `plan/pending/the-work-that-the-forward-image-found.md` (paused).
- A widget that floats over a content: `plan/pending/configuration-overlay-widget.md` (not started).
- Selection and fold state move from the data into a view document: `plan/pending/views-compose-as-content-composes.md` (later).
- A widget part maps back to the domain part that it shows: `plan/pending/a-view-names-the-domain-part-under-a-point.md` (pending).

## Examined and sound

- State of a widget lives in fields of its document, the same for all 47 types; the projection holds styles only.
- The mark of view state at each write (`_write_view_state`, 86 sites) is a ruling of the owner of 2026-09-25 (`plan/done/the-history-records-edits-and-not-view-state.md`): one field can be view state in one view and data in another. Note: only 5 widget types also list such fields for a file ([WD:4216](../../../source/platform/widget/WidgetDocument.jl#L4216) to 4230), so by `pred_arguments` ([PredFile.jl:197](../../../source/platform/serialization/PredFile.jl#L197)) a saved file holds `pressed`, `active_splitter` and `drag_anchor`.
- The three layers of color (theme, style field of the projection, `style` of the document) and one style field for each part and state: decided by the owner on 2026-09-22 (`plan/done/widget-color-design.md`).
- The read-only text of a widget, `DrawnTextLine.jl`: written once, as the owner settled; the wiring per widget is the work of the innermost-click plan.
- The value slot: the child projection `ObjectFieldToValue` maps the write, and the widget knows nothing of the field.
- The tooltip: one binding on `WidgetDocument` serves every widget.
- The light under the pointer: read from the mouse target, no state and no reader code per widget.
- The box: computed once in a cell and carried by the IO map to every reader.
- `WidgetText` and `WidgetTextarea` edit through a `TextView` of the text domain.
- The list and the tree scroll by a `WidgetScrollPane` over a second print of themselves; one table widget serves eager and lazy rows.
- `WidgetChoiceList` is a document that a projection turns into existing widgets.
- A popup and a context menu are windows, opened by an operation, with no screen position in a widget.
- The wheel run is computed once (`_compute_wheel_turn`, [WTG:7873](../../../source/platform/widget/WidgetToGraphics.jl#L7873)) for the pane and the text field.
- The shell gives a key to its shortcuts first: a documented exception with a reason.

## Check of the report

A second reviewer opened the cited code, counted again with `grep`, and read the plans and the design documents that touch each finding. Nothing was run. The corrections stand in the text above, each marked "by the check", and each finding has a **Check** item.

| Id | Verdict | Value after the check |
| --- | --- | --- |
| WS-1 | confirmed-with-corrections | high |
| WS-2 | confirmed-with-corrections | medium |
| WS-3 | weakened | medium |
| WS-4 | confirmed-with-corrections | medium |
| WS-5 | confirmed-with-corrections | medium |
| WS-6 | weakened | low |
| WS-7 | weakened | low |
| WS-8 | confirmed | low |
| WS-9 | weakened | low |

Seen during the check and not in the findings:

- The value slot of a widget works only under a table of `make_object_field_widget_dispatch`; under any other table a document in the slot makes the print loop ([WidgetValueSlot.jl:13](../../../source/platform/widget/WidgetValueSlot.jl#L13)). Two places use that table. The nesting in the standard widget rows would make the slot work in every view; WS-4 needs it first.
- `_route_stack_event` ([LTG:2417](../../../source/platform/layout/LayoutToGraphics.jl#L2417)) gives a child of a stack, a constraint or an anchored layout no button down, no button up and no dwell, and reads no gesture of the container. It also re-roots each answer as `children[i]` by the index of the entry, and the first entry of an anchored layout is its `content` ([LTG:2870](../../../source/platform/layout/LayoutToGraphics.jl#L2870)). Read, not run. The shared reader of WS-1 should cover the layouts of this function too.
