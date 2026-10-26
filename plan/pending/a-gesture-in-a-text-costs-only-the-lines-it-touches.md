# A gesture in a text costs only the lines it touches

Status: IN PROGRESS, started 2026-10-21. Branch `text-gestures` from `frame-guards`,
worktree `projectured-julia-text-gestures`. No decision is open.

Step 7, the folding, came after step 3. The owner, 2026-10-26, to "add that step
and continue with step 4, or continue with step 4 and keep the folding for a later
plan?": "add that step and continue".

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
   flat base, its offset, and one layout of that line with the caret, by the loop
   that lays out the line, so the caret stands where its glyph is drawn. The
   highlight of a selection reads the layouts that the lines of its range keep.
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
2. [x] **The flat place of a line by sums of aligned blocks**, in `TextToGraphics`,
   and the overlay of the caret and of the selection that read only their lines.
   Run `test_text()`, `test/platform/projection/TextToGraphicsTest.jl`, the selection
   and printer locality tests (`test_selection_locality`, `test_value_locality`), and
   the window guards. The overlay guard of step 1 passes. Commit.
3. [x] **The reader with the same structure.** The read guard of step 1 passes. Run
   the tests of step 2, `test_position_navigations()` for the text examples, and the
   click and type-in tests (`test_click_roundtrips`, `test_typeins`). Commit.
4. [x] **The colour of a span reaches only the text that draws it.** The layout of a
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
7. [ ] **The folding maps a selection through the lines it touches.** `TextFolding`
   maps a flat offset through the line that holds it: the output line of the
   offset, its input line by `kept`, and the flat starts of both lines from sums of
   aligned blocks of the flat lengths of the kept lines and of the input lines. The
   forward map, the backward map and `_find_clicked_fold` read only those lines. A
   guard in `test/platform/projection/TextFoldingTest.jl`: the bytes of a forward map
   and of a backward map of a caret are flat from 100 to 10_000 lines. The window
   guards of the caret move and of the click in the Julia file pass. Run
   `test_text_folding()`, the 34 text parts of `test_platform()`,
   `test_position_navigations()` and the window guards. Commit.
8. [ ] **The measurement and the guides.** The window guards on the branch and on its
   base, A/B/A; the broken markers of the gestures come off where a guard passes.
   Write the table in [As built](#as-built). Record the compile workload again
   (`ProjecturedREPL.record_precompile_statements("examples")`), because the new
   functions of the overlay and of the reader are not in it. The guides of the text
   and of the layouts say how a gesture reads its place. Move this plan to
   `plan/done/`. Commit.

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
- The other text stages that map flat runs over every line (`WordWrapping`,
  `TextLineNumbering`, `FilteredTextToText`, `HighlightedTextToText`), until a
  measure shows them in a gesture.

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

### Step 2: the flat place of a line, and the overlay

- **One structure for the places of the lines.** `_PlaceBlocks{T}` combines a
  value of each place over aligned blocks of places, with `+` or `max`. Its
  functions are `_get_block_total`, `_get_prefix_total` (the total of the places
  before a place) and `_find_place_at` (the place of an offset, a descent through
  the blocks). It replaces the closures `get_distance_sum` and `get_offset` of
  `print_document`. The text keeps four of them: the line distances (the `y` of a
  line), the widths (the width of the canvas, which read the layout of every line
  before), and the flat lengths of the places in the caret space and in the box
  space. Each line entry has a cell `flat_lengths`, which reads only the lengths of
  the spans of its line. The flat length of a place counts the break after it.
- **The overlay.** `_layout_overlay` now takes `_TextPlaces`: the groups, the
  `TextLine` of each group, the cells of each place, and the two flat sums.
  - The caret: `_find_flat_selection` finds the flat selection, with the base of a
    structural `.content` caret from the sums (`_find_span_flat_base`).
    `_find_place_at` finds the line, `_find_group_flat_place` the span and the
    character, by the rule of `_find_flat_place`. `_layout_group` lays out that one
    line with the caret, and the `y` of the line places it.
  - The highlight: the lines from the place of the start to the place of the stop,
    their segments from the layout that each line keeps
    (`_collect_line_segments!`), and `_compute_span_rows` as before.
    `_highlight_char_range` no longer takes the segments.
- **A decision against the first model.** The model said that the overlay lays out
  no line again. The caret needs the baseline of its row and the font at its place,
  which the layout of a line does not keep. A second way to place a caret from the
  segments would have to agree with `_layout_group` in each case: a soft break, an
  image, an empty line. So the overlay lays out the caret line once more with the
  same loop. It costs one line.
- **A trap.** A computation in `print_document` assigns a local named `places`, and
  a closure that assigns a name of its outer function writes the outer variable. So
  the outer variable is `text_places`.
- **The bytes** with `FixedMeasure(10, 15, 5, 0)`, after three warm runs:

  | Lines | The caret, before | The caret, after |
  |---|---|---|
  | 100 | 1.56 MB | 11.6 kB |
  | 1_000 | 15.9 MB | 11.7 kB |
  | 10_000 | 160.3 MB | 12.3 kB |

- **Tests.**
  - `test_text_to_graphics()`: 154 pass, 3 broken. The caret guard is a `@test` now.
  - The 34 text parts of `test_platform()`, one at a time
    (`/var/tmp/text-gestures/platform_text.jl`), on the branch and on `frame-guards`:
    equal counts, no failure. The whole `test_platform()` did not end in 10 minutes
    on this machine, on the base too, so I ran these parts.
  - `test_selection_localities()` fails on `main` in every example (13346 of 20957
    on 2026-10-01: the caret and ring graphics). A probe counted the kinds of the
    flagged cells per example on the branch and on `frame-guards`
    (`/var/tmp/text-gestures/locality_tags.jl`): the same kinds in all 76 examples.
    Four examples (`text_with_image`, `widget_button_image`, `filesystem`, `files`)
    have more carets on the branch, because the path of the worktree is one
    character longer, and the same failures for each caret.  - `test_value_localities()`, with the same kind of probe
    (`/var/tmp/text-gestures/value_locality.jl`): the same counts on the branch and on
    `frame-guards` in all 118 examples; its failures are those of `main`.
  - `test_window_frame_guards()`: 17 pass, 14 broken, as on `frame-guards`. No guard
    is flat yet: the read stage of a key still reads every line (step 3), and the
    Markdown file is step 6.
- **The window frames**, A/B/A on the lane `taskset -c 28,30,31` on 2026-10-21
  (`/var/tmp/text-gestures/window_aba.sh`), the minimum frame at the large size; the
  second run of the branch is within 15% of the first, except the move of the
  pointer in the Julia file (13.4 and 18.6 ms):

  | Gesture | `frame-guards` | The branch |
  |---|---|---|
  | Julia, 1_000 lines: a typed character | 554 ms | 104 ms |
  | Julia: a caret move by a line | 382 ms (print 288) | 116 ms (print 1.4) |
  | Julia: a click on a line | 331 ms | 48 ms |
  | Julia: a move of the pointer | 12 ms | 13 ms |
  | JSON, 1_000 objects: a typed character | 1984 ms | 488 ms |
  | JSON: a caret move by a line | 255 ms | 228 ms |
  | JSON: a click on a line | 1156 ms | 16 ms |
  | JSON: a move of the pointer | 2307 ms | 49 ms |
  | Markdown, 3_000 paragraphs: a typed character | 438 ms | 445 ms |
  | The open of a Julia file of 1_000 lines | 853 ms | 698 ms |

### Step 3: the reader with the same structure

- **Where the read stage went.** Profiles of the steady frames after step 2
  (`/var/tmp/text-gestures/profile_probe.jl`, a tree and a flat profile of each
  gesture at the large size) showed one cause in each read: a lookup of a flat
  place that reads every line.
  - A caret move: `get_flat_cursor_coordinate` in `read_intent` of `TextToGraphics`.
  - A typed character: the lowering of the edit, `_read_lowered_gesture`, through
    `_flat_to_span`, `_flat_to_span_nearest` and `_make_image_edit`. Each called
    `get_flat_base` for each span before the place, and each of those read every
    line, so the lowering was quadratic. The gesture table of the text domain
    itself was cheap.
  - A click and a move of the pointer: `_hit_segment` over every segment, then
    `get_flat_base`.
  - In the Julia file, also the run table of `TextFolding` (see below).
- **An index of the lines in the text domain.** The flat lookups of
  `TextDocument.jl` take an optional last argument, an index of the flat offsets
  where the lines start: `_find_flat_line(index, flat)` and
  `_get_flat_line_start(index, i)`. The default index is `get_flat_offsets(text)`,
  which a lookup searches by halves, so each lookup that had a loop over every span
  with a scan of every line in it is now one pass and one line. `_TextPlaces` is the
  other index, in log2 of the count of lines. A span of another line never holds a
  flat offset, so each lookup reads the line of the offset only:
  `_flat_to_span`, `_find_flat_image_place`, `_find_flat_place`,
  `_flat_span_range_start`, `_flat_span_range_end`, `get_flat_base`,
  `_text_flat_span`, `get_flat_cursor_coordinate`, `_text_flat_selection`.
  `_flat_to_span_nearest` reads the lines from the nearest line before the offset
  that has a run to the nearest one after it. `_find_image_range` reads the lines of
  its range. `_is_line_edit` compares the lines of the two ends, and reads the
  characters of one line only when both ends are in it. The lowering passes its
  index down. `_collect_image_paths` had no caller left, and went.
- **A decision.** The gesture table of a document passes only the document and its
  selection to an action, so the index can not reach the actions of `@gestures
  TextBlock` without a new channel. The table is not where the time went, so it
  stays as it is. `TextToGraphics` hands its places only to the lowering, a plain
  function.
- **TextToGraphics.** The IO map has a field `places`. The overlay, the key reader
  (Up, Down, Home, End, with and without Shift), the click map and the forward map
  use the lookups of the domain with the places. The key reader reads the segments
  of the line of the caret and of the next line with a segment (`_find_next_row`).
  The click map reads the lines from the nearest line with a segment above the point
  to the nearest one below it (`_find_caret_at_point`). The forward map reads the
  lines of its range, and finds the node of a segment in the canvas of its own line.
  `_compute_span_bases`, which made a table of every span, had no caller left, and
  went; its explanation of the two spaces is on `_TextPlaces`. `char_to_coord`
  stays for the pointer shapes of spans and for the click on a rasterized canvas.
- **The bytes** with `FixedMeasure(10, 15, 5, 0)`, 100 → 10_000 lines:

  | Gesture | Before | After |
  |---|---|---|
  | The key Down | 0.47 → 49.7 MB | 12.9 → 13.0 kB |
  | A typed character | — | 7.8 → 7.9 kB |
  | A click | — | 8.2 → 8.3 kB |

  The guard of step 1 now measures all four gestures, and all are `@test`.
- **Tests.** `test_text_to_graphics()`, `test_text()` and `test_inline_image_caret()`:
  545 pass, 2 broken (the colour test of step 4). The 34 text parts of
  `test_platform()`: the same counts as on `frame-guards`. `test_click_roundtrips()`
  and `test_typeins()`: 5199 pass, 20 broken. `test_position_navigations()`: 9030
  pass, 5 broken.
- **The window guards**: 27 pass, 9 broken, after five markers came off. The
  minimum frame at the large size:

  | Gesture | `frame-guards` | Step 2 | Step 3 |
  |---|---|---|---|
  | Julia, 1_000 lines: a typed character | 554 ms | 104 ms | 0.2 ms |
  | Julia: a caret move by a line | 382 ms | 116 ms | 36 ms |
  | Julia: a click on a line | 331 ms | 48 ms | 41 ms |
  | Julia: a move of the pointer | 12 ms | 13 ms | 9.9 ms |
  | JSON, 1_000 objects: a typed character | 1984 ms | 488 ms | 2.2 ms |
  | JSON: a caret move by a line | 255 ms | 228 ms | 0.2 ms |
  | JSON: a click on a line | 1156 ms | 16 ms | 2.0 ms |
  | JSON: a move of the pointer | 2307 ms | 49 ms | 2.0 ms |

- **Found, not in this step.**
  - **The folding maps every selection through a table of every line.**
    `TextFolding` builds `_make_fold_runs` over each kept line at each forward map
    (the cell of the selection of its output, computed again at each caret move)
    and at each backward map, and `_find_clicked_fold` reads `get_flat_offsets` of
    its output. That is most of the caret move and the click in the Julia file. The
    other text stages that map flat runs (`WordWrapping`, `TextLineNumbering`,
    `FilteredTextToText`, `HighlightedTextToText`) are not measured yet.
  - **The caret scene of the JSON file stops after two keys.** On `frame-guards`
    and on this branch alike, the first Down and the first Up give a
    `ReplaceSelectionOperation`, the third key a `ReplaceMouseTargetOperation`, and
    each key after it no operation (`/var/tmp/text-gestures/caret_check.jl`). The
    second key puts the caret on the open bracket of the array. So the JSON caret
    guard measures a key that does nothing after its warm up.

### Step 4: the colour of a span reaches only the text that draws it

- `_layout_group` reads the content and the font of a span, and no colour. A text
  placement of a layout carries its span in place of a colour.
- `_get_drawn_color(p, span)` gives the colour that a span draws in: its own, or
  the plain text colour of the theme for a run that names `color_default`. The
  colour cell of each persistent text reads it, and no longer reads the layout. A
  key of a persistent text belongs to one occurrence of one span, so the text reads
  the span of its first placement. A text whose placement went falls back to no
  text, so it paints nothing.
- **A decision.** The owner asked whether the drawn text could use the same cell
  as its span. It could for a span whose colour is never `color_default`, but a
  colour cell can move between a colour and the default, which only the projection
  resolves to the plain colour of the theme. So each text keeps its own colour cell,
  the one that it had before, and that cell reads only the colour of its span.
- The lines of a lazy list read their colour once, when a line canvas is built, as
  before: `_make_list_line_graphic` takes the projection.
- The fill of a span stays in the layout: whether a span has a fill decides whether
  its line has a fill rect.
- **Tests.** The colour test of step 1 passes: a new colour leaves the caret and
  the layout of the line valid, and the text draws the new colour.
  `test_text_to_graphics()`, `test_text()`, `test_inline_image_caret()`,
  `test_text_and_syntax_themes()`, `test_syntax_to_text()`,
  `test_highlighted_text_to_text()`, `test_text_folding()`: 1006 pass. The 34 text
  parts of `test_platform()`: the counts of `frame-guards`. `test_json()`: 239 pass.
  The window guards: 27 pass, 9 broken. A move of the pointer in the Julia file is
  1.4 ms at 100 lines and 5.5 ms at 1_000; its read stage is the folding of step 7.

