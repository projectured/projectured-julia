# A gesture in a text costs only the lines it touches

Status: IN PROGRESS, 2026-10-21. Branch `text-gestures` from `frame-guards`, worktree `projectured-julia-text-gestures`. No decision is open.

## The ask

The frame guards of the text documents (step 5 of
[guards-keep-the-frame-short-at-any-size.md](guards-keep-the-frame-short-at-any-size.md))
found that each gesture in a Julia, a JSON or a Markdown file does work that grows
with the whole file. The owner, 2026-10-21, to "do you want me to continue the
guards plan, or first write a plan that fixes the text documents?" with the
recommendation of the fix plan first: "agreed".

## The problem

The facts at `frame-guards` `52bdfd979`. The numbers are from the window guards
and their probes: the application window on SDL with the offscreen driver, the
minimum frame after the warm up.

| Gesture | Julia, 100 → 1_000 lines | JSON, 100 → 1_000 objects | Markdown, 100 → 3_000 paragraphs |
|---|---|---|---|
| a typed character | 9.0 → 102.5 ms | 106.5 → 1261 ms | 2.6 → 459.6 ms |
| a caret move by a line | 26.6 → 347.6 ms | 19.7 → 212.4 ms | flat |
| a click on a line | 23.1 → 257.0 ms | 64.1 → 754.7 ms | 3.2 → 91.7 ms |
| a move of the pointer | 1.8 → 11.6 ms | 98.7 → 1092 ms | 1.3 → 33.0 ms |

At 10_000 lines of Julia a caret move takes 11 s. Statistical profiles of the
steady frames (`/var/tmp/frame-guards/profile_probe.jl`) give four causes:

1. **The overlay of a text lays out the whole block.** `TextToGraphics` keeps a cell
   for the layout of each line and the vertical offset of each line from sums of
   aligned blocks (`get_distance_sum`, `get_offset`), so one offset reads log2 N
   cells. The overlay does not use them. `_layout_overlay` computes the caret with
   `get_flat_cursor_coordinate`, which reaches `_find_flat_place`, `get_flat_base`
   and `get_flat_offsets`: the flat offset of every line, with `get_flat_length` of
   every span. Then `_compute_span_bases` makes a dictionary of the base of every
   span, and the overlay runs `_layout_group` for every group of the block to find
   the place of the caret. A caret move in the Julia file of 1_000 lines allocates
   199 MB in this way. In the profile of a move of the pointer over the JSON file,
   5440 of 9095 samples are in this path.
2. **The reader of a text reads the same flat offsets.** `read_intent` of
   `TextToGraphics` calls `get_flat_cursor_coordinate`, so a key reads the flat
   offsets of every line: 479 of the 856 samples of the read stage of a caret move.
3. **A move of the pointer updates the overlay.** A move of the pointer writes the
   part under the pointer into each compound of the syntax (`mouse_target`), and
   `SyntaxCompoundToText` lights the delimiters around that part: the colour of each
   delimiter span is a cell that reads the level of its compound
   (`_make_lit_text`). `_layout_group` reads the colour of every span, also in the
   pass of the overlay, which needs no colour. So the new colour of one bracket lays
   out its line again, and the overlay lays out every line again. A probe that
   records each write of a frame and follows the readers to the overlay
   (`/var/tmp/text-gestures/hover_cause.jl`) shows the chain in the JSON file: the
   write of the part under the pointer, the level of a compound, the colour of a
   delimiter, the overlay. In the Julia file the same chain stops before the
   overlay, because the level stays `nothing`.
4. **A long vertical layout costs its whole length.**
   - `LayoutToGraphics` makes the canvas of a `VerticalLayout` with `layout_none` and
     overlapping elements, and `_is_early_stop_layout` is then false. So the dirty
     walk of SDL visits and checks every child after a change; typing in the
     Markdown file of 3_000 paragraphs spends most of a frame there.
   - The cell engine removes a reader from the readers of a cell by a scan of the
     list (`_unregister_dependent!` in `ReactiveCell.jl`). A cell that thousands of
     cells read, and that changes, makes each of them detach in a scan: 1017 samples
     of self time in one profile of typing in Markdown.

## The model

A gesture costs the lines that it changes or shows, and log2 N for its place in a
text of N lines:

1. **The flat place of a line comes from sums of aligned blocks**, as its vertical
   offset does. `TextToGraphics` keeps, for each line, a cell of its flat length,
   which reads only the spans of that line, and the sums of aligned blocks of these
   lengths. The flat base of a line reads log2 N cells, and the line of a flat
   offset is a descent through the blocks. The structure lives in the projection,
   beside the offsets of the lines, and the reader reaches it through the IO map.
   `get_flat_offsets` of `TextDocument` stays for the callers that need every
   offset.
2. **The overlay reads only its lines.** The caret reads the line of the caret: its
   flat base, its layout cell and its offset. The highlight of a selection reads the
   lines of the range. No overlay lays out a line again: it reads the layout that
   the line keeps.
3. **The reader maps a key with the same structure.**
4. **The colour of a span reaches only the text that draws it.** The layout of a
   line reads the content, the font and the breaks of its spans, and not their
   colour. The colour cell of each drawn text reads the colour of its span. So a
   move of the pointer, which lights delimiters in a new colour, lays out no line
   again and moves no caret.
5. **A removal of a reader costs no scan.** A reader keeps its place in the list of
   readers of each cell that it reads. A removal moves the last entry into that
   place and corrects the place of the moved entry.
6. **A vertical layout is a layout that the paint stops at.** The canvas of a
   `VerticalLayout` and of a `HorizontalLayout` names its axis and no overlap, so the
   walk and the render stop at the edge of the view. The place of each child reads
   the sums of aligned blocks of the sizes before it, not one cell of all places.

## Keep

1. A text draws the same pixels as now: the caret, the selection, the highlight,
   and each line.
2. Do not change a sealed file. `CellModule.jl` is 🔒; `ReactiveCell.jl` is not.
3. Add no event, no payload and no channel.
4. Each new name follows [naming-rules.md](../../documentation/rule/naming-rules.md).

## Rule of measurement

As in the guards plan: each time in the lane `taskset -c 28,30,31`, the branch and
its base interleaved as A/B/A, with the load beside it. A count of bytes or of cells
needs no idle machine. The window guards of step 5 of the guards plan are the end to
end measure.

## Steps

Do the work in a worktree on a branch of its own, from `frame-guards`, because the
window guards are there. Commit each step. Do not land on `main` before the owner
approves.

1. [x] **The guards of the text projection.** In
   `test/platform/projection/TextToGraphicsTest.jl`: a text block of 100 and of
   10_000 lines printed by `TextToGraphics`; the bytes of the caret after a caret
   move, and of a read of the key Down, at each size. Both grow now: mark them
   `@test_broken`. A locality test: a new colour of the span under the caret leaves
   the caret and the layout of its line valid, and the text draws the new colour
   (cause 3). It fails now: mark it `@test_broken`. Commit.
2. [ ] **The flat place of a line by sums of aligned blocks**, in `TextToGraphics`,
   and the overlay of the caret and of the selection that read only their lines.
   Run `test_text()`, `test/platform/projection/TextToGraphicsTest.jl`, the selection
   and printer locality tests (`test_selection_locality`, `test_value_locality`), and
   the window guards. The overlay guard of step 1 passes. Commit.
3. [ ] **The reader with the same structure.** The read guard of step 1 passes. Run
   the tests of step 2, `test_position_navigations()` for the text examples, and the
   click and type-in tests (`test_click_roundtrips`, `test_typeins`). Commit.
4. [ ] **The colour of a span reaches only the text that draws it.** The layout of a
   line reads no colour, and the colour cell of each drawn text reads the colour of
   its span. The locality test of step 1 passes. Run the tests of step 2 and the
   theme tests of the text (`test/platform/projection/TextThemeTest.jl`). Commit.
5. [ ] **A removal of a reader with no scan**, in `ReactiveCell.jl`. A new test in
   `test/kernel/cell/`: a cell with 100_000 readers, of which 1_000 detach; the time
   for each detach is flat in the count of readers. Run `test_kernel()` and
   `test_cell()`. Commit.
6. [ ] **A vertical layout that the paint stops at.** `LayoutToGraphics`: the axis and
   no overlap for a vertical and a horizontal layout, and the place of each child
   from sums of aligned blocks. Run `test_platform()`, `test_sdl()`, the partial paint
   test (`test_partial_paint()`), and the window guards. Commit.
7. [ ] **The measurement and the guides.** The window guards on the branch and on its
   base, A/B/A; the broken markers of the gestures come off where a guard passes.
   Write the table in [As built](#as-built). The guides of the text and of the
   layouts say how a gesture reads its place. Move this plan to `plan/done/`. Commit.

## Not in this plan

- **The open of a file.** To open the window with a Julia file of 10_000 lines
  takes 15 s, of 30_000 lines 64 s, and of 100_000 lines more than 14 minutes. A
  profile of the open of 3_000 lines (5.85 s) spreads over every stage of the text
  pipeline: the splice of the children of a syntax compound (`_splice_compound`,
  `_compute_child_lines`), the folding (`_find_shown_elements`), the numbers of the
  lines, the gutter, the heights for the scroll pane (`_pane_scroll_y`) and the
  groups of `TextToGraphics`. Each stage visits every line when the file opens. It
  needs a plan of its own: a print of the lines that the view shows.
- The other documents of step 5 of the guards plan: the data frame, the Explorer,
  the chart, the tabs, the transcript and the MCP log view.

## Wait on long jobs

- While a build, a test run, a sweep, a CI script or a subagent runs, wait with one foreground `until` loop that checks every 15 s, with a timeout of up to 600000 ms, and repeat only that loop until the job ends.
- Do not end a turn to wait. Do not run filler commands such as `echo ok`. Do not print "Waiting" or any status line while a job runs. Report once, when the job has ended.
- Put this rule verbatim into the prompt of every subagent that may wait on a job.

## As built

### Step 1: the guards of the text projection

Three guards in `test/platform/projection/TextToGraphicsTest.jl`, all marked
`@test_broken`:

- `_ttg_measure_gesture_bytes(size)` measures the bytes of the caret after a move
  from the third line to the fourth, and of the read of the key Down, after three
  warm runs. `_ttg_is_flat` bounds them as the frame guards do:
  `FLAT_ALLOCATION_RATIO`, with a floor of 4 kB.
- The colour test gives the first line a colour cell, as `_make_lit_text` gives a
  delimiter, and writes a new colour. The caret and the layout of the line must stay
  valid, and the text must draw the new colour.

The bytes at `text-gestures` `9a70e5c75`, with `FixedMeasure(10, 15, 5, 0)`:

| Lines | The caret after a move | The key Down |
|---|---|---|
| 100 | 1.56 MB | 0.47 MB |
| 1_000 | 15.9 MB | 4.84 MB |
| 10_000 | 160.3 MB | 49.7 MB |

`test_text_to_graphics()`: 153 pass, 4 broken.
