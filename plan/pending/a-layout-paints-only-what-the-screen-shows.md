# A layout paints only what the screen shows

> **Kind:** plan · **For:** developer · **Status:** a plan, written 2026-11-05 at `main` `6b93bfcf3`,
> revised on 2026-11-09 at `main` `d0b9c06c5` and the G3 branch `picture-file` (`92e96eb1a`).
> The owner answered open questions 1 to 6 on 2026-11-05 and open question 7 on 2026-11-09 (option
> B, D12), and approved the plan for implementation on 2026-11-09, with step 1 in it (D4). The work
> runs on the branch `layout-paints`.
> · **Needs:** G3 on main (D0), which landed on 2026-11-09 (`776199253`) · **Sibling plans:** G3 [the-assistant-shows-a-picture-file.md](../done/the-assistant-shows-a-picture-file.md)
> (its open question 9), G4 [a-tab-shows-the-file-that-a-program-rewrites.md](a-tab-shows-the-file-that-a-program-rewrites.md)
> · **Stands on:** [layout.md](../../documentation/package/platform/layout/layout.md),
> [graphics.md](../../documentation/package/platform/graphics/graphics.md),
> [sdl.md](../../documentation/package/backend/sdl/sdl.md),
> [layout-rules.md](../../documentation/rule/layout-rules.md),
> [architecture-decisions.md](../../documentation/design/architecture-decisions.md)

The owner said on 2026-11-05: "The drawing is lazy in the backend when the graphics domain is
read." A survey for G3 found that this holds only in part: the backend skips the elements outside
the clip only in a list and in the lines of a text. The owner decided on 2026-11-05 (G3, open
question 9, option A) that a plan of its own, after G3, makes it hold for every layout. This is
that plan. It decides how much the editor paints, and also how much it reads, because the pixels
of a picture (G3) are a cell that only a paint reads.

The owner rules that bind the design: the editor is lazy and incremental in principle ("If it's
not visible, then it's not calculated"); a projection never reads the state or the output of
another projection; what can be done locally is done locally, with no central walker; a printer
reads no disk; the editor keeps no global state.

## 1. The goal

When this plan is done, these must be true:

1. Each layout of the layout slice tells the backend which of its elements meet the visible area.
   It tells it with the two fields that every canvas has, and with no new field.
2. The SDL backend paints only those elements. Its render, its walk of the changes, its guards and
   its hit test read the content of no other element.
3. A viewport gives its content only the part of its box that the clip in force shows.
4. A picture outside the screen is never read. Neither the render nor the walk reads the pixel cell
   of an image whose box is outside the clip.
5. A scroll paints the elements that come on the screen. The editor reads their background cells
   after the frame, and the next frame paints the answer.
6. A grid of 60 cards in a scroll pane with 6 cards on the screen reads 6 pictures. A column, a
   row and a flow read only the pictures on the screen too.

## 2. What exists (checked at `main` `d0b9c06c5` and `picture-file` `92e96eb1a`)

The rows were first written at `6b93bfcf3` from a report of `0d8dd49a0`. The assistant read each
row again on 2026-11-09 at `main` `d0b9c06c5`, and at the G3 branch `picture-file` (`92e96eb1a`,
on `d0b9c06c5`) where G3 changes a file. The lines are those of main. On G3, each line that the
plan names in `SdlBackend.jl` is 4 more, in `GraphicsDocument.jl` 6 more, and in `WebBackend.jl` 3
more. `LayoutToGraphics.jl`, `GridList.jl`, `LayoutList.jl` and `WidgetTableParts.jl` keep their
lines, and so does `TextToGraphics.jl` up to its line 1722. A row gives the G3 line of
`WidgetToGraphics.jl`. The column "Since `6b93bfcf3`" says what changed.

| Thing | Where | State | Since `6b93bfcf3` |
| --- | --- | --- | --- |
| The search | `compute_first_visible_index`, `source/platform/graphics/GraphicsDocument.jl:1092-1099`; the binary search, `:1105-1120` | It answers the last element that starts at or before the near edge. It answers `1` for `layout_none`, for elements that can overlap, for a `ListNode`, and for an element with no position. | held |
| The canvases that search | the lines of a text, `source/platform/text/TextToGraphics.jl:695-696` and `:1269`; `source/platform/layout/LayoutList.jl:142-145`; `GridList.jl:145-146`; `GridColumnList.jl:169`, `:209`, `:213`; the rows of a tree, `WidgetToGraphics.jl:13835-13840` (G3 `:13866-13871`); the regions of a table, `WidgetTableParts.jl:577`, `:1045`, `:1201`, `:1306` | `layout_vertical` or `layout_horizontal`, and no overlap. | held; the rows of a tree and the regions of a table moved (`:13482` is `:13835`, `:561` is `:577`) |
| The canvases that do not search | `source/platform/layout/LayoutToGraphics.jl:1014` (row), `:1337` (column), `:1864` (grid), `:2084` (flow), `:2249` (stack), `:2442` (constraint), `:2591` (anchored), `:2725` (scroll layout); the row of a grid of a list, `GridList.jl:256-259` | `layout_none` with overlap. The render, the walk and the guard visit each element, also outside the clip. | held; from the grid on, the lines moved by 22, because `cdd4f19e2` gives a `Content` row of a grid an edge (`:1696-1714`) |
| The wrapper of a child | `_wrap_child`, `LayoutToGraphics.jl:116-121`; `clip_child_to_slot`, `:168-185`; the cell of a grid, `place_output`, `:1824-1833` | A canvas at the place of the child with `w = h = 0`, or a viewport at the slot of the child. A grid clips a cell on each axis whose columns or row hand out their extent. | held |
| The ring of a whole selected child | `make_layout_selection_ring`, `LayoutToGraphics.jl:242-243` | It is the last element of the canvas of the row (`:1008-1014`), the column (`:1331-1337`), the grid (`:1839`, `:1857`), the flow (`:2078-2084`), the constraint layout (`:2436-2442`) and the anchored layout (`:2584-2591`). It lies over a child. The stack and the scroll layout have no ring. | held; the lines moved |
| The render | `_render_canvas!`, `source/backend/sdl/SdlBackend.jl:2034-2101`; `_compute_first_drawn_index`, `:2105-2107`; `_is_past_early_stop`, `:2405-2416` | A canvas with an axis and no overlap starts at the search and stops at the first element past the far edge. Any other canvas draws each element. | held; G3 changes no line of the paint |
| The walk, the records and the guards | `_record_painted_element!`, `:2450-2463`; `_record_painted_canvas!`, `:2502-2529`; `_collect_canvas_dirty!`, `:2722`; `_record_moved_canvas!`, `:3074`; `_forget_recorded_canvas!`, `:3267-3289`; `_read_guarded_cells`, `:3492-3515`; `_read_guarded_element`, `:3518-3533` | They select the elements as the render does. The guard reads every field cell of each leaf that it visits, so a leaf whose cell changes is painted again. | held; the forget of the records was not named |
| A viewport does not cut the edges | `_dispatch_render_elem!`, `:2128-2129`; `_render_viewport!`, `:1304-1335`; `_compute_viewport_content_place`, `:1352-1361`; the record, `:2545-2552`; the walk, `:2956-2970`; the guard, `:3523-3525`; the move, `:3231`; the forget, `:3259`; the paint of the rectangles, `:3712` | A viewport gets no edges from the canvas around it. It gives its content the edges of its own box, so a pane that the window or an outer pane cuts draws its rows up to its own edge. The SDL clip cuts the pixels, but the content is read. | held; `:3259` is the forget, not the move. The case is more common: each tab and each card of a dashboard shows a `FileView`, a scroll pane that grows on its height (`FileView.jl:44-47`, G4 step 1a), and the detail of a task holds a scroll pane for each stream (`TaskGroupToWidget.jl:852`) |
| An image reads its pixels at each visit | `_render_image!`, `:1988-2005`; `_compute_leaf_signature`, `:2469-2480`; `_read_guarded_element`, `:3527-3531` | The render reads `data` with no test of the box. The record and the guard read every field cell, `data` too. On G3, `data` is the pixel cell of the picture itself (`_make_image_data_cell`, `GraphicsDocument.jl:805-806` on G3), so each of these reads asks for the pixels. | held; G3 makes each read a demand of the pixels |
| The picture of G3 | `Image`, `source/platform/style/Image.jl:64-88` on G3; the label, `_image_payload(::Image)`, `WidgetToGraphics.jl:1283-1286` on G3; the text span, `_extract_image_data`, `TextToGraphics.jl:1735-1740` on G3 | A picture keeps its pixels in a background cell that only a paint reads. A print reads `natural_size` and `failure`. Until the first answer, a picture measures as 320 by 240 in a label, and as 720 by 460 in a span of Markdown, Book or RST. The answer writes `natural_size`, so the print measures the picture again. | new, from G3 |
| A pane gives the backend the elements of its content | the scroll pane, `WidgetToGraphics.jl:6772-6781` (G3 `:6785-6794`); the transform pane, G3 `:7614-7623` | A pane shows a canvas of its own with `layout_none` and overlap in its viewport. It holds the elements of the output canvas of the content when they are a `CellVector`, else that whole canvas. So the axis of the output canvas of a content does not reach the backend through a pane, and a canvas inside that output keeps its own. On G3 the transform pane follows the canvas of its content through a cell, as the scroll pane does, and its viewport has the transform of the zoom: the render passes no partial paint into it, and its edges are in the units of the content. | not reported; the transform pane changes in G3 step 4 |
| The hit test | `hit_element_at`, `GraphicsDocument.jl:947-1024`, with the search at `:1006`; `find_pointer_shape`, `source/platform/graphics/PointerShape.jl:83`; the router of a layout, `_route_to_children`, `LayoutToGraphics.jl:265-277`, and `_find_child_point`, `:288-302` | The two functions of the graphics slice search a canvas with an axis. The router reads the place and the box of each child, and the content of the child at the point only. | held; `hit_element_at` ends at `:1024` |
| A canvas that declares its extent | `has_declared_extent`, `GraphicsDocument.jl:1141-1143`; `extend_canvas_bounds!`, `:1197-1206`; `_bounds_of_canvas`, `SdlBackend.jl:2356-2362`; `PointerShape.jl:105` | A canvas with an axis, no overlap and a size answers a size or a bounds query with its box, and reads no element. | held |
| A list in a pane | `is_infinite_canvas`, `GraphicsCaching.jl:18-26`; `_find_list_canvas`, `WidgetToGraphics.jl:6320` (G3 `:6333`); `_measure_list_extent`, `:6400` (G3 `:6413`) | A pane looks for a `ListNode` in its content and one level down. A `CellVector` with an axis is no list. A pane with an edge and no offer on an axis measures a list that runs along it by a walk from the head, up to the edge (`b9db3f2c4`), and with no offer at all up to the maximum of its range (model C, `93e07e022`). The walk takes only a `ListNode` canvas, so a canvas of a vector with an axis changes no measure. | held; the measure of a list is new |
| The dashboard | `print_document(::DashboardToWidget, …)`, `source/platform/explorer/DashboardToWidget.jl:37-67`; `_build_card_grid`, `:78-96` | The rows of the grid are a list on every page. The pane of the grid takes at most the visible height of the page (`:49-52`). A card draws the view of its content (`_get_card_view`, `Dashboard.jl:116`), so a card of a file holds a `FileView`. | changed: G4 step 1 (`741d14cc4`, G4 D9) makes the grid a list also on a page with no height, so row 2 of §2.1 describes no code of main |
| The print of a file asks for its read | `FileToContent.jl:76` on G3 (G3 D14) | The print of a file document asks for the read of its file, so a file that a layout prints is read after the frame, also off the screen. The read of a picture file takes the time and the size of the file and no byte. | new, from G3 |
| The detail of a task | `_build_detail`, `source/platform/task/TaskGroupToWidget.jl:736-738` | One `VerticalLayout` of a vector in a scroll pane that grows down: the header, the documents of the kind, and the cards Process, Earlier executions, stdout and stderr, which fold. | new (`cd34d4f4f`, `e9bcb445d`); a real column that step 2 changes |
| The order of a frame | `source/kernel/editor/EditorLoop.jl:115-122` | The paint runs in the print stage. `start_background_cell_work!` runs after it. So a read in a paint records a demand, and the work runs after the frame. | held (G3 §1) |
| A fault on main | `print_document(::FlowLayoutToGraphicsCanvas, …)`, `LayoutToGraphics.jl:2074-2075` | At `6b93bfcf3` a `FlowLayout` printed with any context threw `UndefVarError: outer_h`: the merge `660b68779` put the first assignment after its read. Main fixed it in `fb9e8a171`: the flow defines `outer_h` before it raises it to the minimum. The measurement of §2.1 found it. | fixed on main |
| The stack | `_visible`, `LayoutToGraphics.jl:2184` | A stack with `active` not 0 draws only that page. The limit of [layout.md](../../documentation/package/platform/layout/layout.md) says that the printer draws every child. | held |
| The seals | `SEALING.md` | It lists files under `source/kernel/` only. No step of this plan changes one. | held |
| The other repositories | omnet-julia `main` `d35ae52e3`, inet-julia `main` `9074572` | Their `source/` names none of `make_slot_reference`, `descend_reference_forward`, `compute_first_visible_index`, `overlapping_elements`, `has_declared_extent`, `layout_vertical` or `layout_horizontal`. | held |
| The test environments | `.gitignore:28` | A worktree has no manifest for the test packages (`package/*/Manifest.toml` is ignored), and `environment/all` has one. The tests of G3 ran in `environment/all` of its worktree for this reason. | new |

### 2.1 The measurement at `6b93bfcf3`

**The counts of this section were taken at `6b93bfcf3` on 2026-11-05, and this revision did not take
them again.** The plan names no command or test that gives them: the script stood in a scratchpad
that is gone, and only its output stays, in the log of the `bounded-run` job `count-reads` (34 s).
Two facts of main change what the counts describe. The dashboard of row 2 has a grid of a list on
every page since `741d14cc4` (§2). G3 gives an image the pixel cell of its picture as its `data`, so
a read of `data` asks for the pixels (§2). §4.8 and step 6 use the counts. The tests of steps 2 to
5 assert the cards that are read by their numbers, and do not use the counts.

A script outside the repository ran through `workspace/bin/bounded-run` in `environment/all`, with
`SDL_VIDEODRIVER=dummy`. It made 60 cards. Each card holds a canvas of 200 by 200 pixels with one
`GraphicsImage`, whose `data` cell is a computation that records its read. That cell is what the
pixel cell of G3 is to the backend: a cell that only a paint reads. The script printed each
document with `NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0))` in an exact range of
1100 by 500 pixels, painted it with `_render_canvas_offscreen!`, and ran `_compute_dirty_region` on
a second, fresh print. "On the screen" counts the images whose box meets the clip in force, by a
walk of the drawn tree.

| Document | On the screen | Print reads | Render reads | Walk reads | Walk records, guards |
| --- | --- | --- | --- | --- | --- |
| `Dashboard`, page with a height: a grid of a list | 6 | 0 | 6 | 6 | 74, 43 |
| `Dashboard`, page with no height: a grid of a vector | 6 | 0 | 60 | 60 | 505, 257 |
| Scroll pane, `GridLayout` of a vector, 3 columns of `Relative(1)` | 9 | 0 | 60 | 60 | 491, 247 |
| Scroll pane, `GridLayout` of a vector, 3 columns of `Content` | 9 | 0 | 60 | 60 | 491, 247 |
| Scroll pane, `VerticalLayout` of a vector | 3 | 0 | 60 | 60 | 491, 247 |
| Scroll pane that grows to the side, `HorizontalLayout` of a vector | 6 | 0 | 60 | 60 | 491, 247 |
| Scroll pane, `VerticalLayout` of a list | 3 | 0 | 3 | 3 | 31, 19 |
| Scroll pane, `FlowLayout` | — | — | — | — | the print threw at `6b93bfcf3` (§2); not measured again |

With pictures of 200 by 120 pixels the counts on the screen are 9, 9, 12, 12, 4, 6 and 4, and the
reads are the same in kind: 9 and 4 for the two lists, 60 for each layout of a vector.

So the report held for every layout of a vector, and it was wrong for the case it named. A
dashboard on a page with a height, which is a dashboard in a tab or in a pane, already reads 6
pictures of 60 with 6 on the screen. A dashboard reads all 60 only on a page with no height, such
as a page in a scroll area that grows. Main removed that case in `741d14cc4`.

## 3. What the code does not do yet

1. A row, a column, a grid and a flow of a vector declare no axis, so the backend paints each child
   and reads each picture, also outside the screen.
2. The ring of a whole selected child lies in the list of the children. A list with an axis stops
   at the first child past the far edge, so a ring after it would never draw.
3. A viewport gives its content the edges of its own box, not the part that the clip shows.
4. An image reads its pixels in the render, the record and the guard, also outside the clip.

## 4. The design

### 4.1 What a layout tells

A layout tells the order of its elements on one axis. It writes the two fields of the canvas that
holds them: `layout`, the axis, and `overlapping_elements = false`. The producer declares the order,
and nothing checks it ([graphics.md](../../documentation/package/platform/graphics/graphics.md)).
The lists, the lines of a text, the rows of a tree and the regions of a table use this contract
today. So the backend reads it with the code it has: the search, the early stop, and the same
selection in the walk, the records, the guards and the moves.

A child of a layout of a vector follows the main axis in order, and it starts after the extent
that the child before it drew ([layout-rules.md](../../documentation/rule/layout-rules.md) §4). So
the order holds for each child that draws inside its extent on that axis (D10).

### 4.2 Which layouts search

| Layout | Search | The canvas tree |
| --- | --- | --- |
| `VerticalLayout`, `HorizontalLayout` of a vector | the main axis | a canvas of the children with the axis, beside the ring |
| `GridLayout` of a vector, `FormLayout` | by rows | a canvas of rows on the vertical axis; each row a canvas of its cells on the horizontal axis, at the top of the row and as tall as it |
| `GridLayout` of a list | by rows, as today, and in a row by columns | its row canvas takes the horizontal axis; each cell is a viewport clipped to its column, so the cells do not overlap |
| `FlowLayout` | by lines | a canvas of lines on the vertical axis; each line a canvas of its children on the horizontal axis; the line plan (`_fl_line_plan`, `LayoutToGraphics.jl:1893`) gives the line of each child |
| `StackLayout` | none | its children overlap at one place; with `active` it draws one page |
| `ConstraintLayout`, `AnchoredLayout` | none | a relation or an anchor can put any child over another; an annotation lies over its content |
| `ScrollLayout` | none | at most nine parts, in three rows and three columns |
| the layouts of a list | as today | no change |

A layout with no search is skipped as a whole by the canvas or the viewport around it. A row of a
grid that holds a child that spans a column which does not hand out its width keeps `layout_none`,
because such a child can reach past its columns ([layout.md](../../documentation/package/platform/layout/layout.md)).

The grid of a vector then draws the tree that the grid of a list draws: rows, and cells in each
row. The children keep their order in each canvas, so slot `i` of the old flat list is slot `s`
of row or line `r`, and a helper counts one into the other.

### 4.3 The ring stands beside the children

The output of a row, a column, a grid and a flow is a canvas with no layout. It holds two elements:
the canvas of the children, which declares the axis, and the ring. The lines of a text stand apart
from the caret and the highlights in the same way (`TextToGraphics.jl:696`, `:751-758`). The ring
stays in its list at all times, so a selection move still changes the four cells of the ring and
nothing else ([graphics.md](../../documentation/package/platform/graphics/graphics.md)). A scroll
pane and a transform pane show the elements of the output canvas of their content in a canvas of
their own with no layout (§2), so the axis must stand on a canvas inside that output, as here.

The forward map of a child puts the step to the canvas of the children before the slot:
`elements[1].elements[i]…`, and for a grid or a flow `elements[1].elements[r].elements[s]…`. The
backward map takes the steps off. `make_slot_reference` keeps its signature: a layout gives it the
canvas that holds the slots. The entries `(x, y, child_iomap)` keep the place of each child in the
frame of the layout, so the router, the ring, `find_first_baseline` and the backward map of a point
do not change.

### 4.4 A viewport gives its content the part of its box that shows

A viewport cuts the edges in force by its box, and gives its content the cut edges. The render,
the walk, the records, the guards, the moves and the paint of the rectangles do the same, through
one function. A viewport whose cut is empty draws nothing and reads no element of its content; it
keeps the record of its box. So a pane that an outer pane or the window cuts searches its rows
against the part that shows. The content keeps its origin at the box; only its edges come from the
cut. The box and the edges in force are in the units of the canvas around the viewport, so a
viewport with a scale, such as the transform pane of a zoom tab of G3, cuts its box in those units,
and `_compute_viewport_content_place` turns the cut into the units of the content, as it turns the
box today.

### 4.5 An image outside the clip reads only its box

An image draws only inside its box, so a test of its box against the clip is exact. Each walk of
the backend selects the elements of a canvas with one predicate. It is false for a fence, as each
walk tests today, and for an image whose box misses the edges. For such an image, the render draws
nothing, and the record, the walk and the guard read its place and its size, and no other cell. So
an image in a canvas with no layout, such as the content of a card that the edge of a pane cuts
below its title, reads no pixel. The image is read in the frame in which its box meets the clip.
On G3 the `data` of an image is the pixel cell of its picture, so a read of `data` is the demand of
the pixels, and a test can give an image a computed cell that counts its reads.

### 4.6 The paint, the walk and the hit test

The backend changes in two places only (§4.4, §4.5). For the layouts it uses what exists:

- **The paint** starts at the search and stops at the first element past the far edge.
- **The walk** selects the same elements, so it records, tests and guards only them. A canvas with
  an axis and a size declares its extent, so a size query of a layout reads no child.
- **The hit test**: `hit_element_at` and `find_pointer_shape` search a canvas with an axis. The router
  of a layout keeps its walk over the entries: it reads the place and the box of each child, and
  the content of the child at the point only.

### 4.7 A scroll

A scroll moves the content of a viewport, so the edges move in the frame of the content. The
search then selects the elements that came on the screen. The render paints them, and the walk
records them. The elements that left the screen are not drawn, and their records go, as for a list
today (`_record_moved_canvas!`). A read of a background cell in that paint records a demand. The
editor computes the cell after the frame (`EditorLoop.jl:115-122`), and the next frame paints the
answer. This plan adds no event, no payload and no channel.

A picture that is read for the first time can change its size. Until its first answer it measures as
320 by 240 (G3), and the answer writes its natural size, so in the next frame the layout places it
and each child after it again. In a layout of a vector the extent of the layout changes too, and
with it the scroll bar of the pane around it. Before this plan a layout of a vector read every
picture at its first paint, so its sizes came all at once. A layout of a list and the lines of a
text do so today already, because they read only the pictures on the screen (open question 7).

### 4.8 The cost for a layout of few elements

The search reads about log2(n) + 1 places where the walk visited n elements. For 2 to 4 children
that is 2 or 3 reads. The shape costs more than the search. Each row, column, grid and flow gets
one canvas more (§4.3), and each row of a grid and each line of a flow gets one canvas (§4.2). A
partial paint records and guards each canvas, so each costs one record and one guard. A layout of
one child gets the same shape, so the output of a layout has one form, and a reference into it has
one form.

The first walk of 60 cards in a column recorded 491 graphics and made 247 guards at `6b93bfcf3`; a
column of a list recorded 31 and made 19 (§2.1). Step 6 measures both again, at the base of the
branch and after the steps.

### 4.9 What a print still reads

A layout of a vector prints every child, because its extent on its main axis is the sum of its
children (layout-rules §4). So a cell that a print reads is read for every child. This plan makes
the paint lazy. It does not make that print lazy. A print reads only the children that show in a
layout of a list, which has no extent on its main axis (`LayoutList.jl:23-30`).

The pixels of G3 are read only by a paint, so this plan covers them in every layout. The print of a
file asks for the read of its file (G3 D14), so each file that a layout of a vector prints is read
after the frame, also off the screen; the read of a picture file takes the time and the size of the
file and no byte. A dashboard prints only the cards on the screen on every page, because its rows
are a list (G4 D9, on main since `741d14cc4`, open question 2). The size of a picture comes only with
its pixels, so a picture off the screen keeps the size of a picture with no answer (§4.7, open
question 7).

### 4.10 What is not in this plan

- The web backend (`WebBackend.jl:349`, `_serialize_clipped`, `:352` on G3) and the PDF writer keep
  their walks.
- The widget containers keep their canvases. The rows of a tree and the regions of a table already
  search. The other containers hold a small fixed count of parts, and the canvas around them skips
  them whole.
- A print of a layout of a vector that prints only the children on the screen (§4.9).
- The size of a picture apart from its pixels (D12). A plan of its own gives it after this plan.

## 5. Decisions

A decision that the assistant proposed counts as approved when the owner approves this plan for
implementation (the owner, 2026-11-05). The owner can name one to see it first. The revision of
2026-11-09 adds no decision: it adds facts of main and of G3 to the reasons of D3, D4 and D11, and
their choices stay as they were.

- **D0. A plan of its own.** Decided by the owner on 2026-11-05 (G3, open question 9, option A): a
  plan of its own, after G3, makes each layout tell which of its elements meet the visible area,
  so that the backend paints only those. G3 accepts the extra reads until this plan lands.
- **D1. A layout tells the order of its elements on one axis** (§4.1). Proposed by the assistant.
  The order uses the two fields that every canvas has, so the backend needs no new code to read it,
  and an interface that exists widens instead of a new one. Rejected: a rectangle for each element,
  which each wrapper states and the backend tests against the clip. The test is linear in the count
  at each paint and in each guard. A stated box that is smaller than the ink cuts the ink of every
  canvas with a size, and that is a new rule for every canvas. Rejected: an index on the canvas, a
  new field or a seam that answers the elements in a rectangle. `GraphicsCanvas` is a document that
  about 100 positional calls build, and ten walks of the backend and the hit test must call the
  seam. Once the grid and the flow keep a canvas for each row or line (D2), no level needs more than
  one axis. It is a new mechanism, and the owner asks to be asked before one.
- **D2. The grid searches by rows and the flow by lines; the stack, the constraint layout, the
  anchored layout and the scroll layout do not search** (§4.2). Proposed by the assistant. The
  cells of a row overlap on the vertical axis, so a flat list of a grid has no order on it.
  Rejected: a flat grid with a `GraphicsFence` between its rows. No producer uses a fence, a fence
  has no position for a search, and the render, the walk and the hit test skip it. A new use
  changes the contract of an exported type. Rejected: a flat grid whose cells all start at the top
  of their row, with a search for the first of equal starts. A cell then keeps its aligned place
  only in one more canvas, one for each cell instead of one for each row. Rejected: a search in a
  stack, a constraint layout or an anchored layout. Their children can overlap, and a search needs
  an order without overlap.
- **D3. The ring stands beside the canvas of the children** (§4.3). Proposed by the assistant. In
  the ordered list, the early stop ends the walk at the first child past the far edge, so the ring
  after it never draws. A scroll pane and a transform pane show the elements of the output canvas of
  their content in a canvas with no layout (§2), so an axis on that output canvas would not reach the
  backend, and the canvas of the children inside it keeps its axis. Rejected: a ring in the wrapper
  of each child. That makes n rings, and a
  selection move computes n boxes. Rejected: the ring as the first element. It then lies below the
  children, and an opaque child hides it.
- **D4. A viewport gives its content the part of its box that the clip shows** (§4.4). Proposed by
  the assistant. The edges are what the search compares, so without the cut a pane that the window
  or an outer pane cuts reads its rows up to its own edge: a row of cards that the edge of a pane
  cuts, or a table in a page that scrolls. Each tab and each card of a dashboard shows a `FileView`,
  a scroll pane (G4 step 1a), so a card that the edge of the dashboard cuts is the common case.
  The owner asked on 2026-11-09 whether D4 is generally useful, and kept it in this plan: the rule
  "what does not show is not read" then holds for a pane in a pane at any depth, although the gain
  today is only the hidden part of the panes that an edge cuts. Rejected by the owner: step 1 out of
  this plan, as a limit that layout.md states. Rejected: the cut in the render only. The walk and the
  guard then read what the render does not draw, and [sdl.md](../../documentation/package/backend/sdl/sdl.md)
  requires that the walk visits what the render draws.
- **D5. An image outside the clip reads only its box** (§4.5). Decided by the owner on 2026-11-05
  (open question 1): step 5 is in this plan, as its last change of the backend. An image draws only inside its box, so the test is exact. Rejected: a box test for
  every leaf. A text draws ink past its box, and a box, a line or a text reads no outside state, so
  the test gains nothing there. Rejected: no test for an image. A card that the edge of a pane cuts
  below its title then reads its picture, and the walk and the guard read the pixel cell of each
  image that they visit.
- **D6. The paint, the walk and the hit test use what exists** (§4.6). Proposed by the assistant.
  Rejected: a search in the router of a layout. A layout of a vector prints every child anyway, and
  the router reads only the place and the box of a child that is not at the point.
- **D7. A scroll paints what comes on the screen, and the editor reads its cells after the frame**
  (§4.7). Proposed by the assistant. It is the path of a list today, and of the background cells of
  G3 and G4. Rejected: a read ahead of the rows next to the screen. A row that never shows is then
  read, against the rule of the owner.
- **D8. Every row, column, grid and flow has the same shape, also with one child** (§4.8). Decided
  by the owner on 2026-11-05 (open question 3, option A). Rejected: no canvas of the children for a layout of at most N
  children. That gives one output two forms, and the form of a reference then follows the count of
  the children.
- **D9. This plan makes the paint lazy, not the print of a layout of a vector** (§4.9). Proposed by
  the assistant. Rejected: a layout of a vector that prints only the children on the screen. Its
  extent needs the extents of the children that it does not print. A layout of a list solves this,
  because it has no extent on its main axis.
- **D10. A layout declares that each child draws inside its extent on the axis of the layout, and
  nothing checks it** (§4.1). Decided by the owner on 2026-11-05 (open question 4, option A). A
  child that draws past its extent is cut where its extent leaves the clip, as a row of a list is
  today. The fault is in such a widget, and the search only shows it. The check of step 2 lists each
  widget type that draws past its extent, and a later plan fixes each one where the fault is: the
  widget reports the extent that it draws, or the giver of its slot clips it (layout-rules §3b). The layout rules
  make a widget at least as large as its content (§1), so only an authored size smaller than its
  content, and ink past a box, draw past it. Rejected: a viewport around each child of a stack. That
  is one clip for each child, and one step more in the reference of each child. §3b of the layout
  rules already asks the giver of a slot to clip it. Rejected: the row and the column clip a child
  with an exact slot in this plan (§3b). It adds a viewport and a step to each such child, and it
  does not cover an authored size outside a slot or ink past a box.
- **D11. The SDL backend and the layout slice only** (§4.10). Decided by the owner on 2026-11-05
  (open question 6, option C, "for now"). The web backend does not change, and no plan for it is
  written now. At the first paint it sends the whole drawing of a window to the browser and reads
  the pixel cell of each picture (`WebBackend.jl:1089`, `:303-305`; `:1092`, `:306-308` on G3), so
  it reads every picture,
  also off the screen. The PDF writer draws every page, because a PDF shows every page. Rejected for
  now: a plan of its own for the web backend after this plan, and a step of this plan.
- **D12. A picture gets its size apart from its pixels, in a plan of its own after this plan**
  (§4.10). Decided by the owner on 2026-11-09 (open question 7, option B). A print asks for the
  size, and a task reads it from the head of the file with no decode. Only a paint asks for the
  pixels. The size is one more background cell of the picture, as the pixels are, so the plan adds
  no event, no payload and no channel. This plan does not change: until that plan lands, a picture
  that the screen has not shown is about 320 by 240, and it moves what is below it when it is read.
  Rejected: option A, accept the move with no plan for it.

## 6. Steps

Each step is one commit with its test. `SEALING.md` lists only files under `source/kernel/`
(checked at `d0b9c06c5`), and no step changes a file there, so no step needs the permission of the
owner for a sealed file. `workspace/bin/bounded-run` runs each test in `environment/all` of the
worktree, because a worktree has no manifest for the test packages (§2); the tests of G3 ran the
same way. The work starts after G3 lands on main (D0), in a worktree of its own, and nothing lands
on main without the approval of the owner. The lines below are those of main `d0b9c06c5`; after G3
each line of `SdlBackend.jl` that a step names is 4 more (§2).

The order: step 1 first, because steps 2 to 5 count reads inside a scroll pane, and a pane gives
its content the right edges only after step 1. Main fixed the fault of the flow in `fb9e8a171`
(open question 5). Step 5 can come before step 2 or after step 4.

- [x] **1. A viewport gives its content the part of its box that the clip shows (D4).**
      `SdlBackend.jl`: `_dispatch_render_elem!` (`:2128-2129`) passes the edges to `_render_viewport!`
      (`:1304`). One function cuts the box of a viewport by the edges in force, and the render
      (`:1314`), the record (`:2545-2552`), the walk (`:2956-2970`), the guard (`:3523-3525`), the move
      (`:3231`), the forget of the records (`:3259`) and the paint of the rectangles (`:3712`) call it.
      The content keeps its origin at the box, and only its edges come from the cut (§4.4). A viewport
      with an empty cut draws nothing and records its box only. Update "Paint a window" in
      [sdl.md](../../documentation/package/backend/sdl/sdl.md). Test: `test_laid_out_canvas()` in
      `test/backend/sdl/backend/LaidOutCanvasTest.jl`, a new set: the 1000 rows of that file in a
      viewport of 200 pixels whose upper half lies above the window. The render reads the rows of the
      lower half, by their numbers, and a walk on a fresh print reads the same rows. Then
      `test_partial_paint()`, `test_dirty_rect()` and `test_dashboard_render()`, and
      `test_scroll_work()`, which compares each frame of a partial paint with a full paint.
      Done on `layout-paints`. Facts found: `_compute_viewport_content_place` takes the box, the
      content, the transform and the edges in force, and answers `nothing` when the cut is empty
      (`_cut_viewport_box`); the 7-argument form is gone. The render, the record
      (`_record_painted_viewport!`), the walk (`_collect_viewport_dirty!`), the guard, the move
      (`_record_moved_viewport!`), the forget of the records (`_forget_viewport_content!`, new) and the
      paint of the rectangles (`_collect_cover_element!`) all call it, and each of the first three
      gets the edges in force as a new parameter. A viewport whose cut is empty records its box and
      forgets the records of its content between the edges that the last recording used, which the
      record of the viewport keeps as the 4th item of `res.painted.viewports[key]` (`nothing` when the
      edges showed none of it), so the forget reads no element that never showed and a content that
      comes into view again is recorded as new and painted. The 4th item lives and goes with the
      record of the viewport, so it needs no field and no forget of its own; the change test of the
      walk compares the first 3 items only. The moved viewport is recorded again when the cut by the
      new edges differs from the cut by the old edges. Under a scale the cut rounds out (floor of the
      near edge, ceil of the far edge) where the box rounded to the nearest, so no element that shows
      is lost. `test_scroll_work()` fails twice in the set "a Julia file in a focused tab" at the base of the branch too, a known failure on main.
- [x] **2. A row and a column order their children on their axis (D1, D3).**
      `LayoutToGraphics.jl`: the print of the row (`:1002-1016`) and of the column (`:1321-1339`) puts
      the children in a canvas with `layout_horizontal` or `layout_vertical` and no overlap, and that
      canvas beside the ring in the output. `_children_forward` (`:674-677`) and
      `_children_backward` (`:756-763`) add and take off the step to the canvas of the children.
      Update "Measure and place with cells", "References" and the line of the stack under "Limits" in
      [layout.md](../../documentation/package/platform/layout/layout.md), and "The canvas and the hit
      test" in [graphics.md](../../documentation/package/platform/graphics/graphics.md). Test: a new
      `test_layout_render()` in `test/backend/sdl/projection/LayoutRenderTest.jl`, included and
      exported in `SdlSuite.jl`. It holds 60 cards, each with a picture whose `data` is a computed cell
      that records its read, as in §2.1, in a scroll pane of a window of 1100 by 500 pixels; G3 keeps a
      `Cell` given as `data` (§4.5). For a column and for a row,
      the render reads exactly the cards whose picture meets the clip, by their numbers, and a walk on
      a fresh print reads the same set. A scroll of the pane by 300 pixels reads the cards that come on
      the screen and no other, and the pixels of the partial paint equal a full paint. A selected card
      shows its ring when a card after it lies past the far edge. Then `test_graphics_layout()`,
      `test_layout_closeout()`, `test_pointer_shape()` and `test_layout_rules()`, with one more check
      for D10: in each state, what each widget sample draws lies inside the extent that it reports,
      except for an authored size. A type that fails is marked `@test_broken` with a `# @broken:`
      comment, and this plan lists it under the risk of D10. Then `test_dataframes()`, because a
      layout change broke the edits of a data frame once while the platform suite passed,
      `test_task_views()`, because the detail of a task is a column of cards in a scroll pane (§2),
      and `test_scroll_work()`, for its counts of records and guards.
      Done on `layout-paints`. Facts found: `_make_ordered_children_canvas` (new) builds the output of
      a row and of a column: a canvas with no layout that holds the canvas of the children, with
      `layout_horizontal` or `layout_vertical`, no overlap and the size of the layout, and the ring.
      `_children_forward` and `_children_backward` take a keyword `ordered` that the row and the
      column set; they put `elements[1]` in front of the slot of a child and take it off
      (`_strip_ordered_children_steps`). A reference that names the canvas of the children or the ring
      alone maps back to nothing. The grid, the flow, the stack, the constraint layout and the
      anchored layout keep their form until their own steps. The far edge of the clip is exclusive: an element that starts at or past it is past, so
      `_render_canvas!`, its two loops and `_is_past_early_stop` test `>=`, and every walk of the
      backend goes through `_is_past_early_stop`. A card that starts on the far edge shows no pixel
      and reads no picture. The hit test and `find_pointer_shape` keep `>`, because they compare a
      point, and an element that starts at the point holds it. The D10 check is `_rules_check_ink` in `LayoutRulesTest.jl`: it walks the
      leaves of an output (a canvas declares no box there) and checks the ink against `output.w` and
      `output.h` in the six states of `_rules_measure`, except on an authored axis. A text counts as
      inside when its box is inside under the fixed measure of the projection or under the font
      files, because a plain string in a widget is measured by the font files. The risk of D10 lists
      the types that fail, `@test_broken` under `_RULES_INK_BROKEN`. Counts: before, `test_layout_rules`
      548 passed; after, 588 passed and 10 broken.
- [x] **3. A grid orders its rows, and each row its cells (D2, D3).** `LayoutToGraphics.jl`: the
      print of the grid (`:1575-1872`) puts its cells in row canvases at the top of each row, the rows
      in a canvas with `layout_vertical`, and that canvas beside the ring. A row with a child that
      spans a column which does not hand out its width keeps `layout_none`. `map_reference_forward`
      and `map_reference_backward` of the grid (`:1874-1879`) name the row: the forward map as the
      grid of a list does (`GridList.jl:392-410`), and the backward map takes the two steps off
      again, which the grid of a list does not need, because it maps no path back (`GridList.jl:429`).
      `GridList.jl:256-259`: the row canvas takes `layout_horizontal`. Update
      [layout.md](../../documentation/package/platform/layout/layout.md). Test: `test_layout_render()`,
      new sets. A grid of 60 cards in 3 columns, once with `Relative(1)` and once with `Content`
      columns, with 2 rows of 3 cards on the screen, reads the 6 pictures of those cards and no other.
      A grid wider than its pane, scrolled to the side, reads only the cards of the columns on the
      screen. The dashboard needs no set: its rows are a list on every page since `741d14cc4` (§2), and
      `test_dashboard_render()` checks that it builds only the rows that it draws, also in a scroll
      area that grows. Then
      `test_graphics_layout()`, `test_layout_rules()`, `test_layout_list()`, `test_dashboard_render()`,
      `test_settings_tab()` and `test_appearance_tab()`, whose grids span columns, and
      `test_dataframes()`.
      Done on `layout-paints`. Facts found: the output of the grid of a vector is a canvas with no
      layout that holds the canvas of the rows (`layout_vertical`, no overlap, the size of the grid)
      and the ring. Row `r` is a canvas at `y = row_y[r]`, as tall as the row and as wide as the grid,
      and its cells stand in the frame of the row (the `y` of a cell is `child_y` less `row_y`; the
      slot of a clipped cell has `y = 0`), so the entries `(x, y, child_iomap)` keep the frame of the
      grid. A row declares `layout_horizontal` and no overlap unless it holds a child with `span > 1`
      whose spanned columns do not all hand out their extent (`clip_x` false), and then it keeps
      `layout_none` with overlap. A child of one column in a `Content` column keeps the order: its
      `x` is the column's `x` plus an offset inside the column. `_make_children_beside_ring` (new)
      builds the canvas of the children beside the ring and is shared with
      `_make_ordered_children_canvas`; the placement of the cells does not fit
      `_place_child_outputs`, because a grid clips a cell by its column and row (`place_output`), so
      the grid keeps its own computation for each row. `descend_reference_forward` and
      `_children_forward` take a keyword `rows` (the row of each child) that `make_slot_reference`
      does not need: `_make_row_slot_reference` puts `elements[row]` and then the slot among the
      drawn cells of that row. `_children_backward` takes the same keyword, and `_strip_row_step`
      turns `elements[row].elements[slot]` into `elements[place]` among all the drawn cells, so
      `_backward_descend` is unchanged. `GridLayoutIoMap` carries the field `places` (a cell) that the
      print made (`_gl_place`), and the two reference maps read the rows from it, so they place
      no child again and agree with the output that the print made. A grid with no child has the same shape, with an empty canvas of the
      rows, so its forward map needs no case. The rows of a grid of a list take
      `layout_horizontal` and no overlap in `_make_grid_list_row_canvas`. The geometry of the test is
      computed by `compute_shown_cards`: with the cards of 200 pixels and no gap, the grid of 3
      columns shows 3 rows, the cards 1 to 9 (the plan text said 2 rows of 3, which the geometry
      of the pane of 500 does not give: the third row starts at 400), and after a scroll of 300 the
      cards 4 to 12 (the fifth row starts on the far edge). The grid of 12 columns of `Content` shows
      the columns 1 to 6 of the rows 1 to 3, and after a scroll of 300 to the side the columns 2 to
      7. Counts, before and after: `test_layout_render` 16 and 39 passed; `test_graphics_layout` 23
      and 23; `test_layout_rules` 588 passed and 10 broken, and the same; `test_layout_list` 101 and
      101; `test_dashboard_render` 7 and 7; `test_settings_tab` 55 and 55; `test_appearance_tab` 159
      and 159; `test_dataframes` 613 and 613; `test_laid_out_canvas` 32 and 32; `test_partial_paint`
      78 and 78; `test_scroll_work` 14 passed and 2 failed, before and after, the failure of the
      base of the branch.

- [ ] **4. A flow orders its lines, and each line its children (D2, D3).** `LayoutToGraphics.jl`:
      the print of the flow
      (`:1984-2086`) puts the children of each line in a line canvas from the line plan, the lines in a
      canvas with `layout_vertical`, and that canvas beside the ring. Its forward and backward maps
      name the line. Update [layout.md](../../documentation/package/platform/layout/layout.md). Test:
      `test_layout_render()`, a new set. A flow of 60 cards with 6 on the screen reads those 6. A new
      width moves cards to other lines, and the pixels of the partial paint then equal a full paint.
      Then `test_graphics_layout()` and `test_layout_rules()`.
- [ ] **5. An image outside the clip reads only its box (D5).** `SdlBackend.jl`: one predicate selects
      what a canvas draws, where each walk tests a fence today: the render (`:2047`, `:2066`, `:2087`),
      the record (`:2521`), the walk (`:2832`, `:2893`, `:2914`, `:2929`), the move (`:3123`), the forget
      of the records (`:3284`), the nodes of a list (`:3301-3389`), the guard (`:3510`, `:3526`) and the
      paint of the rectangles (`:3690`). It is false
      for a fence and for an image whose box misses the edges. Update
      [sdl.md](../../documentation/package/backend/sdl/sdl.md) and
      [graphics.md](../../documentation/package/platform/graphics/graphics.md). Test:
      `test_laid_out_canvas()`, a new set. A canvas with no layout in a viewport holds two images
      whose `data` cells record their reads, one in the viewport and one below its edge. The render,
      a walk on a fresh print and the guard read only the first. A scroll of the viewport by the copy
      of its pixels brings the second into view and reads it in that frame. In the frame after, its
      cell has a new value, and the pixels of the partial paint equal a full paint. A frame with no
      change paints nothing. Then `test_layout_render()`, with a set where the edge of the pane cuts
      a card below its title and the card reads no picture, `test_partial_paint()`,
      `test_part_picture()` and `test_scroll_work()`.
- [ ] **6. The measurement, and the close.** The script of §2.1 is gone (§2.1), so write it again
      from §2.1: the documents of its table, the flow among them, each image with a computed `data`
      cell that counts its reads, printed with
      `NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0))` in an exact range of 1100 by 500
      pixels, painted with `_render_canvas_offscreen!`, and walked with `_compute_dirty_region` on a
      fresh print. Run it with `bounded-run` at the base of
      the branch and at its head, and write both counts in §2.1 beside the counts of `6b93bfcf3`. G3
      is in `plan/done/` by then, and a done plan stays as it closed: this plan records here that the
      risk of G3 "A plain layout reads each of its pictures" ends with this plan, and does not change
      G3. Run `Pkg.precompile()` in omnet-julia, which prints these layouts. Move this plan to
      `plan/done/`.

## 7. Tests

The narrowest test of each step, in the order in which to run them:

| Step | First | Then |
| --- | --- | --- |
| 1 | `test_laid_out_canvas()` | `test_partial_paint()`, `test_dirty_rect()`, `test_dashboard_render()`, `test_scroll_work()` |
| 2 | `test_layout_render()` | `test_graphics_layout()`, `test_layout_closeout()`, `test_pointer_shape()`, `test_layout_rules()`, `test_dataframes()`, `test_task_views()`, `test_scroll_work()` |
| 3 | `test_layout_render()` | `test_graphics_layout()`, `test_layout_rules()`, `test_layout_list()`, `test_dashboard_render()`, `test_settings_tab()`, `test_appearance_tab()`, `test_dataframes()` |
| 4 | `test_layout_render()` | `test_graphics_layout()`, `test_layout_rules()` |
| 5 | `test_laid_out_canvas()` | `test_layout_render()`, `test_partial_paint()`, `test_part_picture()`, `test_scroll_work()` |
| 6 | the measurement of §2.1, at the base and at the head of the branch | `Pkg.precompile()` in omnet-julia |

Each test asserts which cards and which rows are read, by their numbers, and not only how many. No
step runs an aggregate suite.

## 8. Risks

- **A child that draws past its extent is cut at the edge of the view (D10).** An authored size
  smaller than its content, and a glyph past the box of its text, draw past the extent. The row and
  the column do not clip a `Fixed` child (`_wrap_child`), although §3b of the layout rules asks it.
  The check of step 2 in `test_layout_rules()` lists the widget types that draw past their extent:
  `WidgetAccordion` (ink 1 pixel left of its box), `WidgetButton` (2 pixels below its height, in
  every state), `WidgetProgressRing` (2 pixels around its box), `WidgetRadioGroup` (2 pixels left),
  `WidgetScrollBar` (a bar of no height draws 1 pixel), and, in a range smaller than their content,
  `WidgetShell`, `WidgetTabbedPane`, `WidgetMenu`, `WidgetContextMenu` and `WidgetTooltip`, whose
  giver cuts or caps them. A later plan fixes each one.
- **A reference into a layout gets more steps (D3, D2).** A test that states the output path of a
  child must add them: `test_graphics_layout()`, `test_layout_closeout()` and `test_layout_list()`
  show it. A widget that finds the node of a child by depth can miss a child that is now deeper:
  `find_node_reference(…; depth = 6)` at `WidgetToGraphics.jl:1720` and `:5815` (G3 `:1733` and
  `:5828`), and `depth = 4` at
  `GraphLayoutToGraphics.jl:656` and `:665`. Of 103 test files that index `.elements[`, 16 also
  print a layout.
- **A size query of a layout takes its box.** The canvas of the children declares its extent
  (`has_declared_extent`), so `extend_canvas_bounds!`, `_bounds_of_canvas` and the walk of the pointer
  shape take its box and walk no child. Ink past the box no longer counts in the bounds, for
  example in the size that `write_image` fits to, or in the room of a scroll pane that measures
  what is drawn.
- **The partial paint.** Steps 1 and 5 change what each walk of the backend selects, and the move
  of a scroll keeps records and guards by what a canvas draws. `test_partial_paint()` and
  `test_scroll_work()` compare the pixels of each frame with a full paint. `test_scroll_work()` also
  bounds the records and the guards of a notch (at most 12 guards in the Files pane), and the
  canvases of §4.8 can raise them.
- **A guard that does not follow an image into the clip.** A guard that a move keeps at the new
  place must read the pixel cell of an image that came into the clip, or the new pixels never
  paint. The test of step 5 covers that frame.
- **A grid with a span.** A child that spans columns and does not take its whole row can reach past its
  columns. Its row keeps `layout_none`, and `test_settings_tab()` and `test_appearance_tab()` print
  such grids.
- **A flow moves its children between lines.** A new width gives new lists to the line canvases,
  so the walk paints the children that moved, as a flow does today.
- **The print of a layout of a vector reads each child (D9).** A cell that a print reads is still
  read for every child. The print of a file asks for the read of its file (G3 D14), so a file in a
  layout of a vector is read also off the screen. The dashboard has no such case: its rows are a list
  on every page since `741d14cc4` (open question 2).
- **A picture that comes on the screen moves what is after it (§4.7, open question 7).** A picture
  that a layout of a vector holds off the screen measures as 320 by 240 until it is first painted.
  Then it takes its natural size, and each child after it moves. Before this plan every picture of
  such a layout was read at the first paint. `test_layout_render()` gives each picture a fixed box,
  so it does not show this.

## 9. Open questions for the owner

1. **An image outside the clip (D5).** Answered by the owner on 2026-11-05: yes, step 5 is in this
   plan (D5). The question was: step 5 changes the selection of every walk of the backend,
   so that a picture is never read also inside a canvas with no layout, such as a card that the
   edge of a pane cuts below its title. Without step 5, the layouts and the viewports skip what is
   off the screen, and such a card still reads its picture. Must step 5 be in this plan? The
   assistant recommends yes, as the last change of the backend.
2. **A dashboard on a page with no height.** Answered by the owner on 2026-11-05: option A, the
   dashboard reads the visible extent, in G4 step 1 (G4 D9). G4 step 1 made it on 2026-11-06
   (`741d14cc4`). The question was: it chooses its grid of a list by `get_exact_height`,
   which is `nothing` in a scroll area that grows. Layout-rules §3c says that a part that builds
   only the rows that show reads `get_visible_height`. So such a dashboard prints every card, and
   G4 reads the text of each page in it. Must the dashboard read the visible extent, so that it
   prints only the cards on the screen? The assistant recommends yes, in G4, whose step 1 changes
   the dashboard.
3. **One shape for every layout (D8).** Answered by the owner on 2026-11-05: option A, every layout
   gets the shape (D8). The question was: each row, column, grid and flow gets the canvas of its
   children, also with one child, and each grid row and flow line gets a canvas. Is one record and
   one guard more for each layout acceptable? The assistant recommends yes.
4. **A child that draws past its extent (D10).** Answered by the owner on 2026-11-05: option A,
   accept the cut here; the list of step 2 names the widgets, and a later plan fixes each one where
   the fault is (D10). The question was: is it acceptable that such a child is cut where its
   extent leaves the view, as a row of a list is today? Or must a later plan make the row and the
   column clip a `Fixed` child, as §3b of the layout rules asks? The assistant recommends to accept
   it here, and to decide after the list of step 2.
5. **The fault of the flow on main.** Answered by the facts: main fixed it in `fb9e8a171` on
   2026-11-05, so step 4 waits for nothing. The question was: `LayoutToGraphics.jl:2047` reads `outer_h` before its
   assignment, since the merge `660b68779`. Must it be fixed on main now, apart from this plan, with
   `test_layout_rules()` as its test? The assistant recommends yes, before step 4.
6. **The web backend (D11).** Answered by the owner on 2026-11-05: option C for now, no change;
   the web backend reads every picture (D11). The question was: must the web backend skip what is off the screen too, in a plan of its
   own? The assistant recommends to decide after this plan.
7. **A picture that the screen has not shown yet has no size.** Answered by the owner on
   2026-11-09: option B, a plan of its own after this plan gives a picture its size apart from its
   pixels (D12).

   A column of pictures in a tab. A picture gets its size when its pixels are read (G3). After this
   plan, only a picture on the screen is read, so a picture below the screen is a box of about 320
   by 240. The column puts each picture below the one before it. So when a picture gets its size,
   each picture below it moves. Before this plan, the first paint reads every picture of the column,
   so all the sizes come at once.

   The example: a folder of 3 charts, each 1000 by 600 pixels, in a column in a tab that is 1000 wide
   and 500 high.

   ```
   charts/
     a.png   1000 × 600
     b.png   1000 × 600
     c.png   1000 × 600
   ```

   ```julia
   column_1 = VerticalLayout(Any[open_file_document!("charts/$name.png") for name in ("a", "b", "c")])
   open_pane!(WidgetScrollPane(column_1; grows = (width = false, height = true)); title = "Charts")
   # before this plan: the first paint reads a, b and c, and the column is 1800 high
   # after this plan:  the first paint reads a only, and the column is about 1080 high
   ```

   Option A, this plan as it is:

   | # | What happens | The state | What the person sees |
   | --- | --- | --- | --- |
   | 1 | The tab opens. | a is read and is 600 high. b and c are not read and are about 240 high each. The column is about 1080 high. | a ✓. The scroll bar shows a column of 1080, and the true column is 1800 ✗ |
   | 2 | The person scrolls to the end. | The view shows 580 to 1080: the boxes of b and c. Both are read, and each grows to 600. The column is 1800 high. | The view stays at 580 to 1080. It shows the end of a and the top of b, not the end ✗ |
   | 3 | The person scrolls to the end again. | The view shows 1300 to 1800. | c ✓ |

   Option B, a size that is read apart from the pixels:

   | # | What happens | The state | What the person sees |
   | --- | --- | --- | --- |
   | 1 | The tab opens. | The print asks for the size of a, b and c. A task reads the head of each file, and decodes nothing. The paint reads the pixels of a only. The column is 1800 high. | a ✓, and the scroll bar shows a column of 1800 ✓ |
   | 2 | The person scrolls to the end. | The view shows 1300 to 1800. c is read. Nothing moves. | c, as a box of 1000 by 600 for one frame, then the chart ✓ |

   - **A.** Accept it. A picture gets its size with its pixels, as an image with no stated size on a
     web page does. This plan does not change. A Markdown page does the same on G3 already: a
     picture there is 720 by 460 until it is read.
   - **B.** A plan of its own, after this plan, gives a picture its size apart from its pixels. A
     print asks for the size, and a task reads it from the head of the file with no decode: 24 bytes
     for a PNG, at most a few kilobytes for a JPEG. Only a paint asks for the pixels. B adds no
     event, no payload and no channel: the size is one more background cell of the picture, as the
     pixels are. This plan does not change.

   Not offered: a pane that keeps in place what the person sees when a picture above it grows. That
   stops a jump of the view, but the scroll bar and the end stay wrong until each picture was on the
   screen.

   The assistant recommends B. The column needs the size of each picture to place the pictures that
   show and to give the length of its scroll bar. The owner said on 2026-10-18: "whoever needs it,
   calculates it". Here the print needs the size, and only the paint needs the pixels. Until B
   lands, A holds.

   The question was: must a picture read its size apart from its pixels, in a plan of its own after this
   plan (B)? Or is it acceptable that a picture that comes on the screen moves what is below it (A)?
