# The pointer shows what a press does there

Status: in progress on the branch `pointer-shape` (worktree
`.claude/worktrees/pointer-shape`). Steps 1 and 2 are done (§6). The owner decided
P1 to P4 on 2026-10-02 (§8). Written 2026-10-02 at the owner's word ("c affects
many other places, needs a plan"), after G3 of step 5.7 of
[view-and-edit-a-data-frame.md](view-and-edit-a-data-frame.md) chose a lit edge
for the edge of a column, and the shape of the pointer for later.

## 1. The goal

The pointer takes a shape that says what a press does where it is: a double
arrow over the edge of a column and over the divider of a split pane, an I-beam
over text that a person edits, and the arrow everywhere else. While a drag is on,
the pointer keeps the shape of the press, wherever it goes, as a desktop program
does.

## 2. What is there now

- No backend changes the shape of the pointer. SDL shows the arrow of the system,
  the browser shows the arrow of the canvas, and the video backend draws its own
  arrow into each frame (`pointer = true`).
- The part under the pointer is found by the backward map of the point, and each
  document on the path keeps a `mouse_target`; a part lights from it. A part that
  a projection made, such as the table of a data frame view, has its mouse target
  through its owner (5.7).
- The drag tracking keeps the part whose drag is on, and gives it the parts of
  the drag by its path, wherever the pointer is.
- Each backend gets the graphics of each window in `write_to_devices`. SDL draws
  them, the web backend sends each window as JSON over a WebSocket, and the video
  backend draws them into a frame.

## 3. The parts that have a shape

| Where the pointer is | Shape | Owner |
|---|---|---|
| the right edge of a header of a table | resize across | widget (table) |
| the divider of a split pane | resize across or down | widget (split pane) |
| text that a person edits: a text field, a text area, a text document | I-beam | widget, text |
| a drag that is on, anywhere | the shape of its press | drag tracking |
| everywhere else | the arrow | — |

Also in this plan, at the owner's word (P2, "all mentioned"):

| Where the pointer is | Shape | Owner |
|---|---|---|
| a button, a link, a tab | pointing hand | widget, pane |
| a tab that can drag, before the press | open hand | pane, dragging |
| a drag that carries a thing, over a place that takes it | closed hand | drag tracking and the keeper |
| a drag that carries a thing, over a place that refuses it | crossed circle | drag tracking and the keeper |
| anywhere, while the editor is busy | hourglass | the backend (§4.3) |

## 4. The design: the shape is part of what a part draws

**Recommendation (mine): a region of the graphics carries the shape.** A part
puts an invisible element, `GraphicsPointerShape(x, y, w, h, shape)`, into the
graphics that it draws, where a press does something. The backend finds the shape
at the pointer in the graphics of the window, by the same order in which it draws
them: the last region that holds the point wins, and a viewport clips the regions
inside it, as it clips what it draws. The drag tracking puts one region over the
whole window, last, while a drag is on, with the shape that the pointer had at the
press, so the shape stays wherever the pointer goes.

Why:

- **A part says it where it knows it.** The table knows where its edges are, the
  divider knows its band, a text field knows its text. No central table names the
  parts, and a part that a projection made, such as the table of a view, needs no
  owner to carry its shape, because the shape travels in the graphics, as the
  rules of the table do.
- **The kernel does not change.** The graphics already reach every backend in
  `write_to_devices`, so the shape is an element of the graphics slice and a
  reading of each backend. A backend that has no pointer, the console and the
  PDF, ignores the element.
- **A move needs no new frame.** The backend finds the shape at each move in the
  graphics of the last frame. Today a move already runs a frame for the light, so
  the cost is one more walk of the graphics at the point, which the backward map
  of the point already does.

**The alternative: the shape follows the mouse target.** Each document answers a
seam, `get_pointer_shape(document, target)`, and the window asks the deepest part
of the mouse target, and sends the shape to the backend. Rejected (mine):

- The backend needs the shape from the state of the editor, and no channel goes
  that way: a new channel from the editor to the backend.
- A part that a projection made is no document, so its owner must answer for it,
  as the view of a data frame now answers the mouse target for its table.
- A drag would need its own rule for its shape anyway.

### 4.1 The shape during a drag

The drag tracking keeps the shape while a drag is on, because it is the code that
already keeps the drag and gives the dragged part each move by its path, wherever
the pointer is:

1. At the press, when it takes the `StartDragOperation` of a part, it reads the
   shape at the press point from the graphics of the window
   (`find_pointer_shape`), and keeps it in its state beside the path of the drag.
2. While the drag is on, it draws one more region over the whole of every window
   of the screen, last, marked as a region of a drag. The backend reads only the
   regions of a drag while one is drawn, and the last one that holds the point
   wins, so the shape of the press stays over the cells, outside the table, and
   in another window.
3. At the release, at Escape and at a lost release, the drag ends, the region
   goes, and the shape follows the part under the pointer again.

A drag that carries a thing (`dragged` is not `nothing`), such as a tab, takes
its shape from the place under the pointer and not from the press: the keeper of
the drag already asks `find_drop_zone` at each move to light the zone, and it
draws a region of a drag over its own extent with the closed hand where a zone
takes the thing and the crossed circle where none does. It draws after the region
of the drag tracking, so it wins over its own extent, and the closed hand of the
drag tracking holds everywhere else.

### 4.2 Outside the window

While the button is held, SDL2 keeps giving the moves outside the window to the
window of the press (its mouse capture of a held button), and the window system
keeps the shape of that window on the pointer. To check on the machine in step 2.
The web client must capture the pointer at a press (`setPointerCapture`), which
it does not do now, so the canvas keeps the moves and its `cursor` while the
pointer is outside it.

### 4.3 The hourglass

The busy shape is a state of the editor and not of a part, so it has no region.
The backend shows the hourglass while the loop is in a frame that takes longer
than a threshold, and the shape at the pointer again after it. The web backend
sends the hourglass in the message of the pointer of step 3. Its message `busy`
says that another client is connected, and is not a busy editor.

## 5. The vocabulary of the shapes

A `Symbol` of a small set, named by the picture (P1), so a backend maps each to
its own:

| Shape | SDL2 | CSS |
|---|---|---|
| `:arrow` | `SDL_SYSTEM_CURSOR_ARROW` | `default` |
| `:ibeam` | `SDL_SYSTEM_CURSOR_IBEAM` | `text` |
| `:double_arrow_horizontal` | `SDL_SYSTEM_CURSOR_SIZEWE` | `col-resize` |
| `:double_arrow_vertical` | `SDL_SYSTEM_CURSOR_SIZENS` | `row-resize` |
| `:pointing_hand` | `SDL_SYSTEM_CURSOR_HAND` | `pointer` |
| `:open_hand` | a color cursor made from an image | `grab` |
| `:closed_hand` | a color cursor made from an image | `grabbing` |
| `:crossed_circle` | `SDL_SYSTEM_CURSOR_NO` | `not-allowed` |
| `:hourglass` | `SDL_SYSTEM_CURSOR_WAIT` | `wait` |

SDL2 has no open and no closed hand of the system, so the backend makes the two
with `SDL_CreateColorCursor` from an image of each, such as the glyphs `hand`
and `grab` of the Lucide font. A shape that a backend does not know is the
arrow.

## 6. Steps

1. ✅ **The graphics slice.** `GraphicsPointerShape` and
   `find_pointer_shape(graphics, x, y) -> Symbol`, which walks the graphics in
   the order of the drawing, through canvases, viewports and the lists of a
   table, and answers `:default` where no region is. Tests: the last region
   wins, a viewport clips, a list of rows that the viewport does not show is not
   walked.

   Done. What the code does:
   - `GraphicsPointerShape(x, y, w, h, shape; drag = false)` is in
     `GraphicsDocument.jl`; `shape` is a `Symbol`, a cell or a function, so a
     region of the drag tracking can follow its state. `POINTER_SHAPES` names the
     nine shapes of §5. `find_pointer_shape` is in `PointerShape.jl`.
   - The walk follows the drawing of SDL exactly: the root canvas is at the
     origin of the window (SDL ignores its own `x` and `y`), a nested canvas moves
     its elements and clips nothing, a viewport clips and moves by its content and
     the scale and translation of its transform.
   - **Decision: a region of a drag that holds the point wins over a plain region
     that holds it, wherever each is in the order; among the regions of a drag,
     the last one wins.** §4.1 says the drag tracking draws "last" and that the
     keeper of a drag draws "after" it, which can not both hold. With this rule the
     drag tracking can draw its region first, and the keeper's regions win over
     their own extent (§4.1).
   - A laid-out list walks only the element that can hold the point: for a
     `CellVector` the one that `compute_first_visible_index` finds, for a
     `ListNode` the last one that starts at or before the point. A canvas that
     declares its extent and does not hold the point is not walked.
   - Tests: `test_pointer_shape()` in `test/platform/document/PointerShapeTest.jl`,
     30 assertions.
2. ✅ **SDL.** The backend keeps the graphics of each window from its last frame
   and the shape it set. At each move, and after each frame, it finds the shape at
   the pointer, and sets the cursor of the system when it changes, with one
   cursor of the system for each shape, made once. Tests: the shape that the
   backend chose for a pushed move (the cursor of the system itself can not be
   read in a test).

   Done. `SdlBackend` holds `drawn_canvases` (the canvas of each window at its
   last frame), `pointer_shape` and `cursors`. `read_from_devices` sets the shape
   for the newest motion of a read, before the rate limit of idle motion, so the
   shape does not wait for the frame. `write_to_devices` sets it at the pointer
   after each frame. The open and the closed hand are made from the Lucide glyphs
   `hand` (U+E1D7) and `grab` (U+E1E6), 22 logical pixels, black with a white
   outline, with the hot spot in the middle; `quit_backend!` frees every cursor.
   Tests: `test_sdl_pointer_shape()` in
   `test/backend/sdl/backend/PointerShapeTest.jl`; `test_sdl()` passes, 844 of 844.
3. **The web backend.** It sends `{"type": "pointer", "window", "shape"}` when
   the shape changes, and the client sets `cursor` of the canvas.
4. **The video backend.** It draws the pointer of each shape: an image for each
   of the nine, in the style of the arrow it draws now (P4).
5. **The parts.** The edge of a column (a region of 7 pixels around each edge of
   the header row), the divider of a split pane, the text of a text field, a text
   area and a text document that a person edits, a button, a link and a tab, and
   a tab that can drag. Each with a test of its region, which presses in the
   region and checks the answer of the reader.
6. **The drag** (§4.1). The drag tracking keeps the shape of the press and draws
   the region of a drag in every window; the keeper of a drag that carries a
   thing draws the closed hand and the crossed circle over its zones; the web
   client captures the pointer. Tests: a drag of the edge of a column keeps the
   double arrow over the cells, outside the table and in a second window; a tab
   that drags shows the closed hand over a group and the crossed circle where no
   zone takes it.
7. **The hourglass** (§4.3), in SDL and in the web client.
8. **The documents** of the graphics, widget, screen, drag tracking and of each
   backend, and the user guide of the pointer.

## 7. Risks

- **The cost of a move.** A walk of the graphics at the point for each move. The
  walk stops at the regions that do not hold the point, and a list walks only
  what it built. Measure it on the data frame of ten million rows and on the
  application window before step 5 ends.
- **A shape that does not match what a press does.** The region and the reader of
  a part must agree on where a press does something. Each part's test presses in
  its region and checks the reader's answer, so the two stay one rule.
- **The video and a review of the takes.** A take that shows the pointer shows the
  new shapes, so the screenplays of the videos may want a new take.

## 8. The owner's decisions

The owner, 2026-10-02:

- **P1. Name by the picture** (against the recommendation of the writer, which
  was by what a press does): `:double_arrow_horizontal`, not `:resize_across`.
- **P2. All mentioned:** the shapes of §3, and the pointing hand, the open and
  the closed hand, the crossed circle and the hourglass.
- **P3. A region of the graphics** (§4).
- **P4. Yes:** the video backend draws the shapes.

The owner asked, with the decisions: "what will keep the cursor shape during a
drag when it moves away from the part being dragged but still operates?" The
answer is §4.1: the drag tracking, which keeps the shape of the press and draws a
region of a drag over every window while the drag is on.
