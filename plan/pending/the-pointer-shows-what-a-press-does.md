# The pointer shows what a press does there

Status: a plan, not started. Written 2026-10-02 at the owner's word ("c affects
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

Other candidates, for the owner (P2): the hand over a button, a link and a tab;
the grab and the grabbing hand over a tab that drags; "not allowed" over a drop
that a place refuses; the busy shape while the editor waits.

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

## 5. The vocabulary of the shapes

A `Symbol` of a small set, so a backend maps each to its own:

| Shape | SDL | CSS |
|---|---|---|
| `:default` | `SDL_SYSTEM_CURSOR_ARROW` | `default` |
| `:text` | `SDL_SYSTEM_CURSOR_IBEAM` | `text` |
| `:resize_across` | `SDL_SYSTEM_CURSOR_SIZEWE` | `col-resize` |
| `:resize_down` | `SDL_SYSTEM_CURSOR_SIZENS` | `row-resize` |
| `:hand` | `SDL_SYSTEM_CURSOR_HAND` | `pointer` |
| `:move` | `SDL_SYSTEM_CURSOR_SIZEALL` | `move` |
| `:not_allowed` | `SDL_SYSTEM_CURSOR_NO` | `not-allowed` |

The names say what a press does, not how the picture looks (P1). A shape that a
backend does not know is the arrow.

## 6. Steps

1. **The graphics slice.** `GraphicsPointerShape` and
   `find_pointer_shape(graphics, x, y) -> Symbol`, which walks the graphics in
   the order of the drawing, through canvases, viewports and the lists of a
   table, and answers `:default` where no region is. Tests: the last region
   wins, a viewport clips, a list of rows that the viewport does not show is not
   walked.
2. **SDL.** The backend keeps the graphics of each window from its last frame
   and the shape it set. At each move, and after each frame, it finds the shape at
   the pointer, and sets the cursor of the system when it changes, with one
   cursor of the system for each shape, made once. Tests: the shape that the
   backend chose for a pushed move (the cursor of the system itself can not be
   read in a test).
3. **The web backend.** It sends `{"type": "pointer", "window", "shape"}` when
   the shape changes, and the client sets `cursor` of the canvas.
4. **The video backend.** It draws the pointer of each shape: an image for each
   of the seven, in the style of the arrow it draws now (P4).
5. **The parts.** The edge of a column (a region of 7 pixels around each edge of
   the header row), the divider of a split pane, and the text of a text field, a
   text area and a text document that a person edits. Each with a test of its
   region.
6. **The drag.** The drag tracking reads the shape at the press from the graphics
   of the content, keeps it in its state, and draws a region over the whole window
   while the drag is on. A test: a drag of the edge of a column keeps the resize
   shape over the cells and outside the table.
7. **The documents** of the graphics, widget, screen, drag tracking and of each
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

## 8. Points for the owner

- **P1.** The names of the shapes: by what a press does (`:resize_across`), as
  above, or by the picture (`:double_arrow`). Recommendation: by what a press
  does.
- **P2.** Which parts get a shape in this plan: the three of §3, or also the hand
  over a button, a link and a tab, and the grab over a tab that drags.
  Recommendation: the three of §3 and the drag first; the hand and the grab as a
  second step, because a hand over every button is a question of style.
- **P3.** The design of §4 (a region of the graphics) against the alternative (the
  mouse target and a seam). Recommendation: the region.
- **P4.** The video backend: draw the shapes, or keep the arrow in videos.
  Recommendation: draw them, because a video shows what a person sees.
