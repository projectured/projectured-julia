# A key in one paragraph repaints only that paragraph

## Goal

The owner's words, 2026-09-26: "using partial render in the SdlBackend, I want to
have an example which has multiple paragraphs, blocks … where I can type-in one
paragraph and the following paragraph is not rendered in the partial render mode.
This is possible because the layout of the paragraph following the one that is
being edited does not depend on the edited paragraph if the height does not
change. … I want to make a video of this feature working in the projectured
binary."

This is the take S10 of [feature-video-screenplays.md](feature-video-screenplays.md)
("Only what changes is drawn again"). The binary turns the feature on with
`PROJECTURED_PARTIAL_RENDER=1`, and `PROJECTURED_DEBUG_DIRTY=1` outlines the
repainted rectangle in red: the program makes its backend as `SdlBackend()`, and
both switches default to these variables.

## What was measured on main, 2026-09-26

A probe with no window printed four paragraphs, edited paragraph 2, and asked the
real `_compute_dirty_rect` for the rectangle. A line is about 20 px high.

| Pipeline | Edit | Rectangle | Result |
| --- | --- | --- | --- |
| `TextToGraphics` alone | same height | `(0,18,332,43)` | only paragraph 2, but by accident (fault 1) |
| `TextToGraphics` alone | the first edit shrinks the line | `(0,18,22,43)` | the old text stays on screen (fault 2) |
| `TextToGraphics` alone | paragraph 2 grows by one line | `(0,18,332,63)` | paragraphs 3 and 4 move to y 60 and 80, and are not repainted (fault 1) |
| `WordWrapping` → `TextToGraphics` | same height | `(0,0,692,243)` | the whole block |
| a `.txt` file as the binary opens it | same height | `(0,0,692,243)` | the whole block |
| a Markdown page as a tab draws it | same height | `(0,75,704,148)` of a 302 px page | only paragraph 2 |

**Fault 1.** `_collect_dirty_elem!` read `elem.x` and `elem.y` of a child canvas
for its offset, and the layout early-stop read `elem.y`, before
`_collect_canvas_dirty!` tested whether they were up to date. The read computes
the value again, so the walk never saw a stale origin on any child canvas. A
paragraph below an edit that kept its height was not repainted, which is right,
but a paragraph that moved was not repainted either.

**Fault 2.** The first paint makes the whole tree one unit, and the walk recorded
the bounds of that unit only. The first change of a line inside it had no old
bounds, so it could not clear the pixels it no longer covered.

**The word wrap is not local.** `WordWrapping` wraps the whole block in one cell
and makes new sub-spans after each edit, so every line below is new.

**A `.txt` file is one cell.** It opens as one `PrimitiveString`. Propagation is
write-driven (architecture decision 10), so every cell below that string is stale
after each key, and no projection can make it local.

**A Markdown page is local already.** A `.md` file in a tab is the rendered page:
`MarkdownRootToVerticalLayout` gives each block its own chain, so each paragraph
has its own `WordWrapping` and its own `TextToGraphics`. A key writes the
`MarkdownText` of one paragraph. The children of the vertical layout get a stale
`x` (from the width of the page) and a stale `y` (from the heights above), and
fault 1 hid both.

## Decisions

- **The video uses a Markdown file** (the owner, 2026-09-26, asked "can we use a
  markdown file?"). It needs no change of a text projection: the rendered page is
  local for each paragraph once the backend is right.
- **The backend compares the geometry of a container by value** and keeps the
  engine write-driven. The `y` cells below an edit still compute again, one sum
  for each paragraph, but the backend does not repaint a paragraph whose place is
  the same. A cutoff by value in the engine would change decision 10 and the
  sealed files of `source/kernel/cell/`.
- **The word wrap for each paragraph is deferred.** The owner said yes to its plan
  before the Markdown answer. It is written below, and it is not needed for the
  video.

## Steps

- [x] **1. Fix the two faults of the dirty walk** (`source/sdl/Sdl.jl`).
  - A graphic changes in one of three ways. Its content changed: a stale element
    list, a stale slot of it, a stale list node, or a leaf with a stale cell, each
    tested before it is read. It moved or was resized: the walk compares the
    absolute content origin of each canvas, and the box, the content canvas and
    the transform of each viewport, by value with what the last paint used
    (`res.painted::_PaintedGeometry`). It came into view or left it: a graphic
    with no record is painted, and one that was painted and is now past the
    layout early-stop has its old place cleared.
  - A paint of a unit records, for everything inside it that the render reaches,
    its place in `res.painted.origins`, its bounds in `dirty_bounds`, and the
    geometry of each viewport (`_record_painted_element!`, `_record_painted_canvas!`,
    `_record_painted_node!`, `_record_painted_viewport!`). The records stop at the
    layout early-stop, as the render does. A first version recorded the whole
    content of a viewport; in a scroll pane that lays out the whole document on
    each paint of a unit, so the records follow the render.
  - **A record is keyed by placement**: `hash(objectid(graphic), key of its
    container)`, with the window canvas under 0. The four regions of a frozen pane
    share one element list, and keyed by `objectid` alone each region found the
    origin that the region before it left, so a scrolled table with frozen headers
    repainted on every frame. The code review found it.
  - **The walk passes the extents that the render passes.** A nested canvas gets
    the edges of the viewport unchanged, as `_dispatch_render_elem!` does; main
    subtracted the offset of the canvas and stopped too early inside a nested
    stack. `_get_viewport_content_place` and `_is_plain_viewport_transform` give
    the content origin and the edges of a viewport to the renderer and to the walk,
    also under a scale.
  - **A list records the nodes it draws** (`_collect_drawn_nodes`, the order and
    the early-stop of `_render_canvas!`). On main a list had no bounds, so a list
    inside a canvas that scrolled was not repainted at all. A list that moved, or
    that was never painted, reflows to the bottom and unions the old bounds of its
    nodes, so a move to the left clears the old right edge.
  - **The bounds of a container follow its content.** Each walk function answers
    whether the recorded bounds of what it walked changed, and a container whose
    content changed so records its bounds again from the graphics it draws
    (`_refresh_canvas_bounds!`). Before, only a unit wrote its record: a line that
    grew left the paragraph around it with the old width, and a later move of the
    paragraph left ghost pixels. The second review round found it; it was on main
    too.
  - **A leaf is tested before the early-stop reads its place**, as a canvas is.
    Before, a leaf whose `y` changed in a vertical stack was never repainted.
  - A list reads a `.prev` link past its near edge only when the link is up to
    date, so the walk never builds a node that the render does not build.
  - A slot is tested as an `AbstractCell`, only where the walk visits it, because
    a slot past the early-stop can stay stale for as long as it is off-screen.
  - A viewport that changed repaints its old and its new box. On main it repainted
    the new box only, and it did so whenever one of its cells was stale, also when
    the values were the same. A viewport of zero size records no bounds.
  - The records of graphics that are gone stay until a full paint. When the
    records are more than twice what the last full paint recorded, plus 10000,
    the backend forgets them and paints the whole window once.
  - Tests: `test_dirty_rect()`, 61 pass (20 on main). The new cases: a paragraph
    below an edit that keeps its place is not repainted; a paragraph that moves
    repaints its old and its new place; the first change after the first paint
    clears what was painted, for a canvas and for a leaf; a paint records only
    what the render reaches; a list inside a canvas that scrolls moves with it; a
    nested stack is walked as far as it is drawn; a graphic drawn at two places
    keeps each place; a graphic that leaves the view clears where it was; a list
    that moves left clears its old right edge; a paragraph whose line grew clears
    the whole line when it moves; a leaf that moves along its stack repaints; a
    scaled viewport repaints its box
    when its content moves; a viewport repaints when its geometry changes and not
    when it is computed again. The first frame of the `ListNode` case is now a
    reflow of the whole list. `test_write_image()`,
    `test_text_ink_inside_viewports()`, `test_sdl_layering()` and the naming
    guard pass.
  - The probe again, on the branch: `TextToGraphics`, paragraph 2 grows →
    `(0,18,332,103)`, which covers the moved paragraphs; the first edit shrinks →
    `(0,18,332,43)`; Markdown, same height → `(0,75,704,148)`; Markdown, grows →
    `(0,75,657,325)`; Markdown, shrinks → `(0,75,657,302)`.
- [x] **2. Check it in the binary.** The owner asked for the video API instead of
  a screen capture, so the check is the probe with no window over the window
  scene of `run_application`, and the take itself, which `record_application_video`
  records from the same window.
  - The live run works: `build/video/s10/drive.jl` (ignored by git) opens the
    application on `example/markdown/paragraphs.md` with `partial_render` and
    `debug_dirty` on, pushes SDL events from a command file, and logs each dirty
    rectangle and unit. The desktop is Wayland with Xwayland on `:0`, so a grab
    of the root window is black; `ffmpeg -f x11grab -window_id <id>` grabs the
    SDL window itself. F1 of the screenplays is fixed: a click and a key reach
    the Markdown file tab.
  - **A click or a key repaints the whole window in the binary.** A probe with no
    window (`make_application_window` and the window scene, as
    `ApplicationTest.jl` builds them) lists the stale canvases and the chain of
    stale cells behind each. Three causes:
    1. The window shell (`WidgetShellToGraphicsCanvas`) built its band wrappers in
       one cell that read the height of each band. The status bar shows the
       selection, so its height cell goes stale on each key, and the shell made
       new wrappers for every band. Fixed in the worktree, not committed: the
       list reads which bands exist, each band keeps its wrapper, and its top is
       a cell of its own.
    2. The composite that holds the pane tree (`WidgetCompositeToGraphicsCanvas`)
       sizes its box from its children with `get_graphics_size`, in the same cell
       that makes its wrappers, so any change inside it rebuilds it whole. A box in
       a canvas of its own was tried and taken back: the walk visits the box first,
       and its size computation reads every graphic below the children, so their
       stale cells were computed again before the walk reached them, and the typed
       text was drawn but not found. The walk depends on the order of reads.
    3. The backend repaints one bounding rectangle. The status bar at the bottom
       changes on each key, so the rectangle of any key reaches the bottom of the
       window, over every paragraph below the edit.
  - **The owner's answer, 2026-09-26:** "there's a specific video recording API
    in projectured, use that" and "how about instead of unioning the boxes into a
    large box we add them to a set and only drop boxes which are totally covered?
    then we paint that".
    - Done: the dirty region is a set of rectangles (commit `9a6490dc`): a
      rectangle that another covers is dropped, each one is painted under its own
      clip, and past eight the region is painted as the box that covers them.
    - Done: `VideoBackend` and `record_application_video` take `partial_render`
      and `debug_dirty` (commit `1c9a4b3b`). The offscreen surface is the kept
      target; the pointer and the outline go on a copy of the frame; the outline
      of the last repaint stays on the frames until the next one.
    - Done: the shell keeps the wrappers of its bands (commit `995b3f91`).
    - The probe after a click and after typing now gives two rectangles, the pane
      area `(0,70,1280,693)` and the status bar `(0,689,1280,720)`. The pane area
      is still one unit because the composite rebuilds, so the next step is the
      containers, and the question below is still open.
  - **The owner's answer, 2026-09-26, second round:** "most projections are
    already handling selection changes with a very small reactive change in the
    output, usually only selection … a size change is of course different …
    yes, you can continue on refining how projection printers handle
    incremental changes, the smaller the change in the output is the better".
    So the model stays the one of stale cells, and the printers get smaller.
  - **What a click and a key repainted, cause by cause** (the probe with no
    window lists the stale canvases and the chain of stale cells behind each):
    1. *The status bar* computed its height in the cell of its words, so the
       selection it shows made its height stale on each key, and with it the
       room the shell offers the pane tree. Its height now comes from the line
       of its font and its insets.
    2. *The composite* sized its box from its children in the cell that built its
       wrappers, and the size of a child reads every graphic in it, the caret
       and the selection ring included. Its list now reads which children it has;
       its box is a canvas of its own, which measures the children only when it
       has something to draw.
    3. *The split pane and the tabbed pane* measured their children with
       `get_graphics_size` even when the parent offered the extent and the
       measure was not used. They measure only for an axis with no slot.
    4. *A string edit* placed its caret with `clear_selection!` and
       `set_selection!`, which writes the selection cell of every node on the
       path, so each container that reads its selection (a tabbed pane reads it
       for its active tab) rebuilt on each key. It uses `replace_selection!`,
       which stores the same selection and writes only the cells whose value
       changes.
    5. *The walk* read cells in an order that let a recording compute cells it
       had still to test: the box of the composite, visited first, measured the
       children and hid the typed text. The walk now has two phases: it finds
       every change, then it runs the recordings in the order it met them. A
       viewport always defers the clip of its inner rectangles, because a
       viewport inside it answers that its own bounds did not change.
  - The probe after these: a click repaints the caret `(699,256,705,283)` and
    the status bar; each key repaints paragraph 2 `(262,233,1245,283)` and the
    status bar, and nothing else.
  - **Decided, no longer open: what the red box means.** It stays the picture of
    the stale cells, as the owner's answer says. The two options were:
    - *Staleness (the model now).* The box shows what the reactive graph made
      stale, plus the graphics that moved. It is the honest picture of the
      reactivity the video is about. It needs: a dirty region of several
      rectangles; a walk in two phases, which finds every unit before it records
      any, so a recording cannot compute cells that the walk has still to test;
      and each container of the window chrome changed so that its element list
      depends only on which children it has (the shell is done; the composite, the
      split pane, the tab group and the scroll pane are next).
    - *Value.* The walk compares what is drawn with what was painted, keyed by
      the place in the tree: the element list, the origin, and the field values of
      each leaf. It does not depend on the order of reads, and a container that
      rebuilds with the same content costs no paint. But the box then shows what
      changed on the screen, not what the graph made stale, so it proves less
      about the reactivity. Open a Markdown file of several paragraphs in
  `bin/projectured` with both variables set, on the live display, and type into
  the second paragraph with pushed SDL events. Find every other unit that a key
  repaints: the caret, the tab title if it marks a change, a status line, the
  selection ring of the page. Keep what is right to repaint and fix what is not.
- [x] **3. The Markdown file for the take**: `example/markdown/paragraphs.md`, a
  heading and five paragraphs of prose that wrap at the width of the tab and say
  what the viewer sees.
- [x] **4. Record the take** with `record_application_video(...; partial_render =
  true, debug_dirty = true, debug_dirty_hold = 0.6)`, the video API of the
  repository (the owner, 2026-09-26), and not from the screen.
  - The take of 2026-09-26: `build/video/s10/s10_partial_render.mp4` of the
    worktree, 1280×720, 30 fps, 46.1 s, recorded by `build/video/s10/take.jl`
    (ignored by git, as the scripts of the other takes are). The beats: the
    first paint outlines the whole window; a click on the second line of
    paragraph 2 outlines the caret and the status line; four arrow keys outline
    the old and the new place of the caret; `End`, then " Only this one."
    outlines paragraph 2 and the status line on each key; a sentence typed word
    by word makes paragraph 2 one line taller, and the key of the wrap outlines
    paragraphs 2 to 5 at their old and their new places; deleted word by word,
    the key of the unwrap does the same; each other key outlines paragraph 2.
  - A scan of the take at 4 frames a second finds the red rows 234–258 (the
    caret), 210–258 (paragraph 2), 210–442 (the wrap and the unwrap) and 690–718
    (the status line), and nothing else after the first paint.
  - **The owner, after the first take, 2026-09-26:** "is it possible and simple to
    merge the resulting boxes in a way that the inner lines are not drawn?" and
    "the type-in speed is quite weird … we need the jitter but it should be more
    realistic like a human. The json type-in example video does it right."
    - The outline is the outline of the union of the rectangles
      (`_compute_union_outline`): an edge is kept only where the pixels just
      beyond it are outside every rectangle. The live window and the video both
      draw it.
    - The typing follows the JSON example: phrases of up to three words, cut at
      a comma or a period, at one speed for the whole take (0.14 s a character,
      jitter 0.45), a gap of 0.35 s between phrases, and a fixed seed. The
      uneven speed of the first take was the timeline: a pause after each word,
      and three different speeds. It was not the editor: a take in video time
      fires each event at its video second, however long a frame takes.
    - The second take: 30.4 s; the scan finds the caret, paragraph 2, the wrap
      and the unwrap (paragraphs 2 to 5 as one outline) and the status line.
  - `debug_dirty_hold` is new: the outline of the last repaint changes with the
    next key, so the frame where the paragraphs below move lasted 1/30 s. With a
    hold, a video outlines every repaint of the last 0.6 s as well. The default
    is 0, and a live window does not change.
  - `_DIRTY_RECT_LIMIT` is 32, not 8: the wrap gives 10 rectangles (the old and
    the new place of paragraphs 2 to 5, the caret, the status line), and a limit
    of 8 painted them as the box that spans the window. Each rectangle is one
    walk of the render; merging overlapping rectangles would be cheaper, and it
    is a change of the owner's rule, so it is not done. The beats of S10: the arrow keys move the caret (a small red
  box at the old and at the new place), then a word is typed into the second
  paragraph (the red box covers that paragraph only), then a line is typed that
  makes the paragraph one line taller (the red box reaches the paragraphs below,
  which move). The output goes to `build/video/` of the worktree.

## Landing: the rebase onto the main of 2026-09-26

Another session changed the same walk on main while this branch was open: the
render, the walk, the records and the hit test get all four edges of the clip
(`_ClipEdges`), a laid-out canvas starts at `_compute_first_drawn_index`, the walk
finds its start with `_find_first_walked_index` (a stale slot on the path of the
search makes the canvas one unit, and a stale leaf keeps its test from before the
read), and a canvas that declares its extent gives its box as its bounds. The
rebase kept both: each of the four commits of this branch that touch `Sdl.jl` was
applied onto main's walk, with main's edges, start index and search, and
`_paint_dirty_rects!` passes the edges of the window to the render, as main's
single rectangle did, because a glyph can reach past its box into the next
rectangle. `WidgetToGraphics.jl` merged by itself. After each resolved commit
`test_dirty_rect()` and `test_laid_out_canvas()` passed.

## Deferred: the word wrap for each paragraph

For a `TextBlock` of spans and `TextNewline` elements (the `TextDocument` row of
the binary, and every prose chain that holds more than one paragraph):

- `WordWrapping` groups its input into hard paragraphs at `TextNewline` elements.
  The grouping reads the structure only, as `_line_groups` of `TextToGraphics`
  does. Each paragraph has its own wrap cell, which reads only its own spans and
  the wrap width, and its own table of `WrapSegment`s.
- The output keeps one container for each paragraph, so a content edit does not
  change the membership of the output. **Open choice for the owner:** a nested
  `TextBlock` for each paragraph, or a `TextLine` that may hold soft breaks. Both
  change the flat offsets (`get_flat_offsets`, `TextBlockToString`) and the
  mapping of the selection.
- `TextToGraphics` gives each paragraph container its own canvas and its own line
  cells, with a `y` chain of paragraphs. The stack reads only the count of
  paragraphs.
- A `.txt` file stays one cell, so it stays whole-dirty. Only a change of what a
  `.txt` opens as would change that.

## Known limits

- A leaf repaints when one of its cells is stale, also when the value is the same.
  Leaves are small, so the cost is small.
- The caret overlay of `TextToGraphics` lays out the whole block again on each key
  (`_layout_overlay`). It repaints only the caret, but the work is not local.
- A take in video time that faults in `print!` never ends: the fault barrier
  keeps the loop going, no frame is written, and the schedule moves only with the
  frames. After the rebase the pointer of a partial take called the render with
  its old signature, and the take ran 14 minutes on its first mouse event with an
  empty log. The call is fixed and a partial take with a mouse event is tested;
  the loop itself is unchanged.
- The web backend (`source/web/Web.jl`) has its own dirty walk, with the model
  of main: it tests the `x` and `y` cells for staleness and keys by `objectid`.
