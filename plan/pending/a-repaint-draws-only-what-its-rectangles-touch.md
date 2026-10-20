# A repaint draws only what its rectangles touch

Status: PENDING, 2026-10-20. In progress on the branch `repaint-skip`, in the
worktree `projectured-julia-repaint-skip`. No decision is open.

## The ask

On 2026-10-20 an animation in one pane slowed the whole editor. The assistant
of the editor found the cause in the SDL backend, and the owner asked for a plan
of the fix. A plan by another agent, `a-repaint-walks-only-what-its-rectangles-touch.md`,
measured the symptom and took a profile. This plan keeps those measurements,
corrects one claim, and chooses the way of the change.

The line numbers are from commit `983d0a42b`. Find each function by its name
first, and use the line number only as a hint.

## The problem

A `GraphicsCanvas` in its own tab moved shapes by
`get_reactive_clock_time(editor.clock)`. The window also showed the Explorer, a
dashboard with charts, a graph of cards and a long Assistant transcript. The
frame times came from *Editor › Frame times* (`FrameStatistics`):

| State of the window | Mean frame time |
| --- | --- |
| before the animation | 15–25 ms |
| about 20 moving elements | 417 ms, peaks of 1–3 s |
| one moving dot | about 190 ms |
| one moving dot, the graph tab closed | about 198 ms |

One dot costs almost as much as 20 shapes. So the count of moving shapes is not
the cause. A CPU profile of 4 s with one moving dot had 771 samples in the
editor loop. 572 of them were under `_paint_dirty_rects!` → `_render_canvas!` →
`_render_viewport!`. 184 were in `_render_element!` for a `GraphicsText`: the
build of `_TextTextureKey` (line 1093) and `SDL_RenderCopyF` (line 1122).

The code path:

1. `_render_window!` (line 3105) gets the rectangles of the frame from the dirty
   walk and caps them at 32 (`_limit_dirty_rects`).
2. `_paint_dirty_rects!` (line 3004) sets an SDL clip for each rectangle and
   calls `_render_canvas!` on the canvas of the whole window, with the edges of
   the whole window, `_ClipEdges(0, 0, width, height)`.
3. `_render_canvas!` (line 1891) skips an element only by the early stop of a
   laid-out canvas against those edges. `_render_viewport!` (line 1172) gives its
   content the edges of its own box. It draws its content also when its box
   misses the SDL clip.
4. So each rectangle visits every graphic that the window shows: the visible
   rows of each scroll pane, and each element of a canvas with no layout. Each
   visited text builds a texture key and calls SDL. The clip drops the pixels
   after the work is done.

The correction: the report of the assistant said that the whole Assistant
transcript is walked. The render visits only the rows that the viewport of the
transcript shows, because the viewport gives its content the edges of its box.
The cost is still the whole visible window for each rectangle.

`render_offscreen_changes!` (line 3637) paints the target of the video backend by
the same `_paint_dirty_rects!`, so the same cost applies there.

## The facts that the change uses

- The dirty walk records the bounds of each graphic that the render reaches, in
  `res.dirty_bounds`. The key is the placement of the graphic,
  `_make_placement_key(elem, parent)`. The root is
  `_make_placement_key(canvas, UInt(0))` (`_compute_dirty_region`, line 2895).
  - A leaf records `_bounds_of_elem` (line 2147). For a text, that includes the
    texture box from `_compute_text_texture_box`: ink left of `x` and ink above
    the ascent of the font.
  - A canvas records the union of the records of the elements that it draws
    (`_record_painted_canvas!`, line 2289). When an element changes, the walk
    records the canvas again (`_refresh_canvas_bounds!`).
  - A viewport records its box, because it clips its content
    (`_record_painted_viewport!`, line 2329). The records of its content are in
    the units of the content.
  - A list node records at `_make_placement_key(node, list)`, and its value at
    `_make_placement_key(value, node_key)`.
- The walk uses the same origins and edges as the render. So the render reaches
  no graphic that the walk did not record, except a graphic with no bounds.
- The walk ends, with its deferred recordings, before the paint starts. So at
  paint time each record holds the bounds of the present frame.
- The walk pads each rectangle by 2 px (`pad = 2` in `_compute_dirty_region`).
- `render_offscreen_changes!` uses the same `SdlWindowResources` as a window.
- A full paint must not depend on the walk (the comment of `_render_window!`).

## The decision

**The render skips a graphic by the record of the walk.** Claude proposed it,
and the owner accepted it on 2026-10-20: "yes, but measure it, I want numbers".

In a partial paint, before the render draws a graphic for one rectangle, it gets
the record of the placement of that graphic. When the record, widened by the
pad, does not meet the rectangle, the render skips the graphic. For a canvas or a
viewport, it skips all that the graphic holds. A graphic with no record draws.
Inside a viewport with a scale, the render skips nothing, because the records
there are in the units of the content. The scaled viewport itself is still
skipped by its box.

The other ways, and why this plan does not take them:

- **Narrow the edges to the rectangle** (way A of the other plan). The early stop
  and `_compute_first_drawn_index` compare the layout place of an element, not
  its ink. Take a row just below a rectangle, with a glyph that rises above the
  ascent of its font. The render skips the row, but its ink is in the
  rectangle. The background fill erases that ink, and nothing draws it again. A
  margin needs a bound on how far ink reaches, and the code has none. The
  records give the exact bounds.
- **One walk for all the rectangles** (way B of the other plan). SDL has one clip
  rectangle, and the rectangles of a frame can overlap. A graphic with alpha that
  draws under two clips that overlap blends twice in the overlap. A paint for
  each rectangle fills its background first, so each pixel gets each graphic
  once.

The risk: a record that is smaller than what its graphic draws gives a missing
pixel. The walk already uses the same records to clear old pixels, so such a
record is a fault of the walk now too, which shows as a trail. The pixel test of
step 1 looks for it.

## Keep

1. A partial paint gives the same pixels as a full paint of the same frame.
2. The first paint, a paint with `partial_render = false`, `write_image` and
   `write_offscreen_frames!` draw as now, with no lookup of a record.
3. The walk does not change, so `debug_dirty` outlines the same rectangles.
4. The state stays on the resources of the window (`PAR-PER-EDITOR-STATE`). Add
   no process-global value.
5. Each new name follows
   [naming-rules.md](../../documentation/rule/naming-rules.md).

## Rule of measurement

The owner asked for numbers. A number is a time, a count of drawn graphics, or a
frame time. Take each time in the measurement lane, `taskset -c 28,30,31`, with
`main` and the branch interleaved as A/B/A, and write the load of the machine
beside it. A count needs no idle machine.

## Steps

Do the work in a worktree on a branch of its own. Commit each step. Do not land
on `main` before the owner approves.

1. [ ] **The pixel test.** A new testset in `test/backend/sdl/backend/` paints a
   sequence of frames with `render_offscreen_changes!` into one offscreen
   renderer. It paints each frame in full into a second renderer, with a new
   `make_offscreen_paint_state`, and compares the pixels of the two surfaces.
   The frames include:
   - a circle that moves;
   - a text with a glyph above the ascent of its font, one row below a dirty
     rectangle;
   - a text with a negative left bearing just right of a dirty rectangle;
   - a list of rows (`ListNode`);
   - elements with alpha that overlap;
   - a viewport with a scale;
   - two dirty rectangles that overlap.

   The test passes before the change, because the paint now draws everything.
   Commit.
2. [ ] **The skip.**
   - Add a private struct that holds the records, the rectangle and a count of
     the leaves that it draws.
   - `_paint_dirty_rects!` takes the records, or `nothing`. `_render_window!`
     and `render_offscreen_changes!` pass `res.dirty_bounds` only for a partial
     paint that is not the first paint.
   - `_render_canvas!`, `_render_element_guarded!`, `_dispatch_render_elem!` and
     `_render_viewport!` take that struct, or `nothing`, and the placement key
     of the graphic. They make each key as the walk makes it. With `nothing`,
     they make no key.
   - Add one predicate that tests a record against the rectangle.
   - Make the pad one named constant, for `_compute_dirty_region`, the predicate
     and the test.
   - Add a testset: 5000 texts in a viewport at the left, one circle at the
     right. The circle moves, and the partial paint draws no text of the
     viewport. Before the change, it draws all 5000 for each rectangle. Add a
     second case: a dot moves over the rows of a list in a viewport. The paint
     draws exactly the rows whose records meet a rectangle.
   - Run `test_sdl()` in `ProjecturedSDLTest`,
     `test/backend/video/editor/VideoTest.jl` and
     `test/backend/video/editor/ApplicationVideoTest.jl`. Each must give zero
     `Fail`, zero `Error`, and the same count of `Broken`.

   Commit.
3. [ ] **The measurement and the guides.**
   - In a live window, put one moving dot in a `GraphicsCanvas` tab, beside the
     Explorer and an Assistant transcript. Do not run an assistant turn. Write
     the mean frame time from `FrameStatistics` on `main` and on the branch in
     [As built](#as-built).
   - [sdl.md](../../documentation/package/backend/sdl/sdl.md) says that each
     rectangle "costs one walk of the render". Make it describe the skip, in
     the present tense. Change the comment above `_DIRTY_RECT_LIMIT` to the same.
   - Move this plan to `plan/done/`. Commit.

## Not in this plan

- The cost of the walk. It visits each graphic that the window shows once in
  each frame, at a low cost for each. If step 3 shows that it is large, it needs
  a plan of its own.
- The value of `_DIRTY_RECT_LIMIT`. After the change, 32 small rectangles can
  cost less than the one rectangle that covers them.
- The frames of 175 ms while the Assistant pane draws during a turn.
- A change of the example canvas, and `FRAME_INTERVAL`.

## Wait on long jobs

- While a build, a test run, a sweep, a CI script or a subagent runs, wait with one foreground `until` loop that checks every 15 s, with a timeout of up to 600000 ms, and repeat only that loop until the job ends.
- Do not end a turn to wait. Do not run filler commands such as `echo ok`. Do not print "Waiting" or any status line while a job runs. Report once, when the job has ended.
- Put this rule verbatim into the prompt of every subagent that may wait on a job.

## As built

Nothing yet.
