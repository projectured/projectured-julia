# A text reports the height it draws

> **Status:** pending. Written 2026-09-25. Nothing is implemented.

A text reports a height that is smaller than the box it draws, so a viewport
that ends at the reported height cuts the bottom of g, p, q, y and j. This plan
makes the reported height and the drawn height one number.

## 1. The request

The plan `plan/done/documentation-tool-results-as-markdown.md` found the defect
in its Step 8 and recorded it as a limit (§6 there). The owner, 2026-09-25, after
the offer to write a plan for it: "yes, I want to write that".

## 2. What exists

### 2.1 The two heights

- `measure_truetype_text(text, font)` answers `(width, font_logical_size(font))`:
  the em size, the same for every text, whatever its glyphs
  ([TrueType.jl:388-410](../../source/style/TrueType.jl#L388-L410)). For
  `font_ubuntu_regular_20` it answers 20 for `"a"`, `"gypsy"` and `"Type"`.
- A `GraphicsText` draws from the top of its box, with its baseline
  `font_ascent` below the top (19), and its ink reaches `font_descent` below the
  baseline (4). The full box is `font_line_height`, 23. The glyph `g` reaches
  4 below the baseline, so its bottom is 3 pixels below the reported height.
- The SDL backend draws a surface of the font height at the text's `y`
  ([Sdl.jl:795-875](../../source/sdl/Sdl.jl#L795-L875)), and the PDF backend puts
  the baseline at `y` plus the ascent
  ([Pdf.jl:389-403](../../source/pdf/Pdf.jl#L389-L403)), so both draw the full box.
- `measure_sdl_text` answers the font height from `TTF_SizeUTF8`, which is the
  full box, except for an empty text, where it answers `font_logical_size`
  ([Sdl.jl:2147-2172](../../source/sdl/Sdl.jl#L2147-L2172)).
- The comment above the vertical metrics says so, as a fact and not as a
  decision: "the two measurers answer different heights: `measure_truetype_text`
  gives the em size, `measure_sdl_text` gives the rasterized one"
  ([TrueType.jl:415-419](../../source/style/TrueType.jl#L415-L419)). No plan in
  `plan/done/` chose the em size; `math-formula-layout.md` records the same
  fact, and the math typesetter reads the font tables instead.
- The application measures with `measure_truetype_text`
  ([WindowWrap.jl](../../source/shell/WindowWrap.jl), `make_application_*` in
  `example/projectured/`), and so do the catalog, the PDF export and the web
  backend.

### 2.2 Who reads the height

A survey on 2026-09-25 found 12 source files that read a text height:

- **The measured height.** `TextToGraphics` stacks lines at it, so it is the line
  pitch, and a text block is `cy + line_h - y0` high
  ([TextToGraphics.jl:562-626](../../source/text/TextToGraphics.jl#L562-L626));
  it is also the height of the caret. About 25 widgets in `WidgetToGraphics.jl`
  size their box from `_text_size`, and a menu, a list, a radio group and a tree
  use it as the pitch of a row and as the band of a click. The chart and the
  sequence chart reserve their title and label bands with it. omnet-julia reads it
  in two places: the label of a module in a topology
  (`ModuleAppearanceToGraphics.jl:216,290`) and the timeline strip
  (`TimelineView.jl:209,227`). inet-julia reads none.
- **`font_logical_size` in place of a measure.** The bounds of a graphics tree,
  `_bounds_elem!`, take the width from the measure and the height from
  `font_logical_size` ([GraphicsDocument.jl:788-792](../../source/graphics/GraphicsDocument.jl#L788-L792)).
  `get_canvas_content_bounds` and `get_graphics_size` build on it, so the natural
  size of a tab page, a split and a scroll room, and the automatic size of
  `write_image` and `write_pdf`, all end at the em size. The selection rectangle
  of a text and the band of a click on a segment are `font_logical_size` high
  ([TextToGraphics.jl:1184-1318](../../source/text/TextToGraphics.jl#L1184-L1318)),
  and the PDF page test of a text uses it too ([Pdf.jl:394](../../source/pdf/Pdf.jl#L394)).
- **The math typesetter** reads `font_ascent`, `font_descent` and
  `font_line_height` and uses the measure for a width only. It is right already.

### 2.3 Where the ink is cut

A `GraphicsViewport` cuts in every backend (SDL `SDL_RenderSetClipRect`, the PDF
`paint_viewport!`, the web `ctx.clip()`). A viewport cuts the ink of a text when
it ends at a height that came from the text:

- **A cell of a grid.** `clip_child_to_slot` gives a cell a viewport; on an axis
  the cell owns, the viewport "follows the child and clips nothing", in the words
  of its docstring, but it is the height the child reported, and the viewport
  cuts there ([LayoutToGraphics.jl:128-156](../../source/layout/LayoutToGraphics.jl#L128-L156)).
  Every `WidgetTable` cell of text is cut, in a tab and in the chat pane.
- **The body of a card.** A card clips its width and follows the height of its
  body with a viewport of that height, so the last line of the body is cut. Its
  comment says "Height is not clipped", and the viewport is `inner.h` high
  ([WidgetToGraphics.jl:5525-5536](../../source/widget/WidgetToGraphics.jl#L5525-L5536)). In
  the chat pane, the last line of a Markdown result is cut, in the route that
  draws the page as one syntax tree and in the route that draws it as a stack.
- **A scroll pane with no height, and a tab page with no offered height.** Each
  makes a viewport of the height its content reports
  ([WidgetToGraphics.jl:4448-4452](../../source/widget/WidgetToGraphics.jl#L4448-L4452), 4038-4062).

A check on 2026-09-25 walked the graphics of a chat pane with a Markdown result
and compared each text's box, top plus `font_line_height`, with the bottom of the
viewports around it (`/var/tmp/text-height/cut_texts.jl`). The paragraphs in the
middle of the page are whole; the four table entries and the last line of the
page are cut by 3 pixels, and the last line is cut in the old route as well.

### 2.4 The tests that read a text height

- One exact test: "the status line keeps its text off the edges"
  ([WindowShellTest.jl:357-372](../../test/shell/WindowShellTest.jl#L357-L372)).
  Its measure answers `font_logical_size` as the height, and it asserts
  `output.h == line + 8` with `line = font_logical_size(font)`.
- Five tests read a height through an inequality or a value computed in the test
  (`ChartProjectionTest`, `GestureLogProjectionTest`,
  `SequenceChartProjectionTest`, `TextRangeSelectionTest`,
  `ScrollPaneHoverTest`).
- About 13 test files use a fixed measure such as `(t, f) -> (length(t) * 8, 16)`,
  and a change of the TrueType measure does not reach them.
- omnet-julia and inet-julia have no test with an exact height of a text.

## 3. The options

### (A) The measure answers the box it draws

`measure_truetype_text` answers `font_line_height(font)`, and the three places
that read `font_logical_size` as a height (`_bounds_elem!`, the selection and
click bands of `TextToGraphics`, the PDF page test) read `font_line_height`.
The empty text of `measure_sdl_text` answers the same.

- One number is the height of a text everywhere, and it is what every backend
  draws. The two measures agree.
- Every viewport of §2.3 then ends below the ink, with no change to a container.
- **The line pitch grows from the em size to the font's line box:** 20 to 23 for
  the body font, 15 percent. A code view, a list and a form get taller, and each
  widget box that is sized by its text grows by 3 pixels. That changes what a
  person sees in every pane.
- About 6 files change, and one test.

### (B) The pitch stays, and a block reports its last line whole

A text block keeps the em size as its line pitch, and adds the rest of the box
of its last line to its height: `(lines − 1) × em + font_line_height`.

- The look stays: lines keep their spacing, and a block grows by 3 pixels at
  the bottom.
- A text has two heights then, the pitch and the box, and the measure contract
  `(width, height)` gives only one. `TextToGraphics` and each of the about 25
  widgets that size from `_text_size` must read the font's line height as well,
  and a fixed test measure has no font metrics to answer it.
- More places change, and the new idea stays in all of them.

### (C) A viewport that follows its content does not cut that axis

`clip_child_to_slot` and the card body cut only the axis they were given, as
their docstrings say.

- It changes no height, so nothing moves.
- A `GraphicsViewport` has one rectangle, so a clip on one axis is a new feature
  of the graphics layer and of the SDL, PDF and web backends: a new mechanism.
- The scroll pane and the tab page of §2.3 still cut, the automatic size of an
  image still ends at the em size, and the reported heights stay wrong.

**Recommendation (mine, not a decision): (A).** The drawn box and the reported
box become one number in one function, as the SDL measure already answers, and
every reader follows without a change of its own. The cost is the look: every
line of text is 3 pixels lower. The owner decides whether that spacing is
wanted (§6, question 1).

## 4. The design, for (A)

1. `measure_truetype_text` answers `(width, font_line_height(font))`. Its
   docstring and the comment above the vertical metrics say that the height is
   the box a `GraphicsText` draws: the ascent and the descent.
2. `_bounds_elem!` in `GraphicsDocument.jl` takes the height of a text from the
   measure it is given, as it takes the width. Then the bounds follow the
   measure of the caller, and a fixed test measure stays fixed.
3. The selection rectangle and the click band in `TextToGraphics` use the height
   of the line they belong to (`line_h`), not `font_logical_size`.
4. The PDF page test of a text uses the measured height.
5. `_measure_sdl_text` answers the full box for an empty text too.
6. The documents say one thing: `style.md`, `text.md`, `pdf.md`, `web.md`, and
   `markdown.md`, whose limit goes.

The web backend draws with the browser's own `textBaseline = "top"`, a third
placement of the ink. This plan does not change it (§7).

## 5. Steps

Do the work in a git worktree, not in the main checkout. Commit each step.
`source/kernel/backend/BackendInterface.jl` declares `measure_text`; if its
docstring needs a word about the height, check [SEALING.md](../../SEALING.md)
for it first.

- [ ] **Step 0. The baseline.** On the base commit: `test_substrate()` (the
  widget and text tests), `test_markdown()`, `test_chart()`,
  `test_sequencechart()`, `test_math()`, the shell tests, the PDF test, and the
  presentation tests of omnet-julia. Keep the counts in `/var/tmp`. Walk the
  chat pane check of §2.3 and write its result down.
- [ ] **Step 1. The test first.** A new test: "the ink of a text stays inside
  its viewports". It draws, with `measure_truetype_text`, a `WidgetTable` of
  text cells, a card with a text body, a scroll pane with no height over a text,
  and a Markdown result in the chat pane. It walks the graphics as the check of
  §2.3 does, and asserts that the box of each text ends inside every viewport
  around it. It fails on the base commit in all four places.
- [ ] **Step 2. The height** (§4, items 1 to 5). The new test passes.
  `WindowShellTest` asserts `line + 8` with `line = font_line_height(font)`,
  because its measure mirrors the TrueType one.
- [ ] **Step 3. The suites of Step 0**, compared with the baseline. A moved
  pass count is explained before it is accepted.
- [ ] **Step 4. The look, in a real window.** The application on `main` and on
  the branch, with the same panes: a code tab, a guide with a table, the chat
  pane with a result, a form. Images of both go to the owner. A timing is not
  part of this step.
- [ ] **Step 5. omnet-julia.** Its packages precompile, its presentation tests
  pass, and an image of a topology and a timeline shows the labels whole.
- [ ] **Step 6. The documents** (§4, item 6).

## 6. Questions for the owner

1. **Which option: (A), (B) or (C)?** My recommendation is (A), and it moves
   every line of text 3 pixels at the body size.
2. **The web backend.** Leave the browser's own placement of the ink as it is,
   or align it with SDL and PDF in this plan. *Recommendation: leave it, and
   note it (§7).*

## 7. Limits and relations

- The web backend places the ink with the browser's `textBaseline = "top"`,
  which can differ from the ascent of the font file.
- [font-zoom-per-editor.md](font-zoom-per-editor.md) (pending) also changes
  `measure_truetype_text`, and its option (B) changes the measure contract. The
  two plans touch the same function; whichever lands second rebases.
- [layout-sizing-model.md](layout-sizing-model.md) (pending, its landing step
  open) owns the rules of the ranges and of clipping. Option (A) changes no rule
  there: a container that clips keeps clipping, at a height that now covers the
  ink. Option (C) would change its rules.
- [word-wrapping-projection.md](word-wrapping-projection.md) (pending):
  `WordWrapping` reads the width of a measure and not its height, so the two
  plans do not meet.
