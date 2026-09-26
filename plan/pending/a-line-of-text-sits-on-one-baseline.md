# A line of text sits on one baseline

> **Status:** in progress, in the worktree `projectured-julia-text-baseline` on
> the branch `text-baseline`, from `c634a718`. Written 2026-09-25. The owner
> decided the five questions of §5 on 2026-09-25, and asked on the same day to
> start the work in a worktree. Steps 0 to 8 are done; Steps 10 and 11 are in progress.

Text in the editor is laid out by the top of each run, measured with a height
that is the em size, and drawn by backends that kern and hint as they like. This
plan gives text a correct line model, as a word processor has one: the box of
every string is measured as it is drawn, every run of a line sits on one
baseline, the height of a line comes from the fonts on it, and lines are set at
a line distance.

## 1. The request

The first draft of this plan (`a-text-reports-the-height-it-draws.md`, commit
`512e00f5`) changed the height that the measure answers and nothing else. The
owner rejected it on 2026-09-25:

> What? Don't cut corners, we must do things correctly
>
> String box must be measured correctly. Fonts also have baselines. Multiple
> fonts in a line have to be aligned at the baseline. The line height should be
> calculated. The line distance is between lines as it is usually done in other
> word processing editors.
>
> Lay out a correct plan, not a punt

The owner, after the rewrite: "I like the plan". Asked where the measure goes and
what it returns, the owner took the interface of §3.8, with the caret offsets, on
2026-09-25.

The requirements this plan meets:

- **R1. The box of a string is measured as it is drawn.** Its width is the sum
  of the advances and the kerning that the backends draw. Its ascent and descent
  come from the fonts that draw its glyphs, fallback fonts included.
- **R2. Every run of a line sits on the baseline of the line**, whatever its
  font, its size, or the fallback font of a glyph in it.
- **R3. The height of a line is computed** from the runs on it: the largest
  ascent above the baseline, the largest descent below it, and the line gap.
- **R4. The distance between two lines is set as word processors set it:**
  single spacing is the line distance that the fonts give (ascent, descent and
  line gap), and a text can ask for a multiple, an exact distance, or a minimum.
- **R5. Every backend draws the ink where the layout put it:** the baseline of
  each run and the advance of each glyph, in SDL, PDF and the web client.
- **R6. No viewport cuts the ink of a text whose box it holds.** This is the
  defect that started the work (§2.6).

## 2. What exists

### 2.1 Two measures, and neither is what is drawn

`measure_truetype_text(text, font)` is the measure of the application, the
catalog, the PDF export and the web backend
([TrueType.jl:388-410](../../source/style/TrueType.jl#L388-L410)). It answers:

- the width: the sum of the `hmtx` advances, with no kerning and no hinting;
- the height: `font_logical_size(font)`, the em size, for every text, whatever
  its glyphs and whatever the fallback fonts that draw some of them.

`measure_sdl_text` asks SDL_ttf ([Sdl.jl:2147-2184](../../source/sdl/Sdl.jl#L2147-L2184)).
The video backend and some tests use it. SDL2_ttf is version 2.24.0 over
FreeType 2.14.3, built without HarfBuzz. The editor opens every font with the
defaults: kerning on (the `kern` table, through FreeType), hinting
`TTF_HINTING_NORMAL`.

A comparison on 2026-09-25 (`/var/tmp/text-height/sdl_vs_parser.jl`), widths in
logical pixels:

| Font, text | `measure_truetype_text` | SDL at ratio 1 | SDL at ratio 2 |
| --- | --- | --- | --- |
| Ubuntu 20, `"AVAWAToTy"` | 116 | 111 | 111 |
| Ubuntu 20, `"WWWWWWWWWW"` | 186 | 190 | 185 |
| Ubuntu 20, `"1111111111"` | 113 | 110 | 115 |
| Ubuntu Bold 36, `"AVAWAToTy"` | 224 | 209 | 208 |
| Ubuntu Bold 36, `"WWWWWWWWWW"` | 341 | 349 | 349 |
| Ubuntu Mono 20, every text | equal | equal | equal |

So the layout places the caret, the selection and the click targets up to 15
pixels away from the glyphs that SDL draws, and differently at each device
pixel ratio. The code font agrees, because it has a fixed pitch and no `kern`
table.

The heights disagree in the same way:

| Font | parser `font_ascent` / `font_descent` | SDL ascent / descent / height / line skip, ratio 1 | ratio 2, in logical pixels |
| --- | --- | --- | --- |
| Ubuntu 20 | 19 / 4 | 19 / 3 / 23 / 23 | 19 / 3.5 / 22.5 / 23 |
| Ubuntu Mono 20 | 17 / 3 | 17 / 3 / 20 / 20 | 17 / 3 / 20 / 20 |
| Ubuntu Bold 36 | 34 / 7 | 34 / 6 / 41 / 42 | 34 / 6.5 / 40.5 / 41.5 |
| Ubuntu 14 | 13 / 3 | 14 / 2 / 16 / 17 | 13.5 / 2.5 / 16 / 16.5 |

The parser rounds each metric on its own (`_font_metric`,
[TrueType.jl:424-449](../../source/style/TrueType.jl#L424-L449)), so
`font_line_height` of DejaVu Sans 20 is 19 + 5 = 24 while the line box is 23.28.
SDL_ttf rounds in its own way at each device size.

### 2.2 The metrics of the bundled fonts

Read from the font files at 20 pixels:

| Font | ascent | descent | line gap (`hhea`) | OS/2 typo ascent / descent / gap | USE_TYPO_METRICS |
| --- | --- | --- | --- | --- | --- |
| Ubuntu (all weights) | 18.64 | 3.78 | 0.56 | 15.52 / 3.70 / 1.12 | no |
| Ubuntu Mono | 16.60 | 3.40 | 0 | 13.86 / 3.30 / 0.98 | no |
| DejaVu Sans, Sans Mono | 18.56 | 4.72 | 0 | 15.20 / 4.80 / 4.00 | no |
| Noto Emoji | 18.55 | 4.88 | 0 | 18.55 / 4.88 / 0 | no |
| Liberation Sans | 18.11 | 4.24 | 0.65 | 14.56 / 4.21 / 3.00 | no |
| Lucide (icons) | 20.00 | 0 | 0 | 20.00 / 0 / 1.80 | yes |

- The parser reads the `hhea` ascender and descender only
  ([TrueType.jl:129-185](../../source/style/TrueType.jl#L129-L185)). It reads no
  line gap, no OS/2 typo or win metric, and not the USE_TYPO_METRICS flag.
  Nothing in the code base reads a line gap, and the SDL backend never calls
  `TTF_FontLineSkip`.
- The parser reads no `kern` and no `GPOS` table. Ubuntu and DejaVu Sans carry
  both; Ubuntu Mono carries neither.
- The body font and the code font differ by 2 pixels of ascent at the same size.

### 2.3 How a line is laid out

- A line of `TextToGraphics` is a sequence of spans, each with one `StyleFont`
  ([TextDocument.jl](../../source/text/TextDocument.jl)). A line with several
  fonts is several adjacent `TextString`s.
- `_layout_group` places **every segment at the top of its row**, `y = cy`, and
  the row is as high as the largest height that the measure answered
  ([TextToGraphics.jl:588-608](../../source/text/TextToGraphics.jl#L588-L608)).
  So inline code (Ubuntu Mono) next to body text (Ubuntu) sits 2 pixels higher,
  in every rendered Markdown line with a code span, and a DejaVu list marker
  sits beside body text on another baseline again.
- A line starts where the previous one ends, at its `y` plus its height
  ([TextToGraphics.jl:348-357](../../source/text/TextToGraphics.jl#L348-L357)).
  There is no line distance and no line gap.
- The caret is at the top of the row and as high as the row. The selection
  rectangles and the click bands are `font_logical_size` high
  ([TextToGraphics.jl:1152-1318](../../source/text/TextToGraphics.jl#L1152-L1318)),
  and code finds the segments of a row by an equal `y`.
- An inline image (`TextGraphics`) is placed at the top of the row too.
- `WordWrapping` reads the width of a measure only
  ([WordWrapping.jl:118-176](../../source/text/WordWrapping.jl#L118-L176)).
- No test puts two fonts on one line and checks where they go
  (`test/substrate/projection/TextToGraphicsTest.jl`). The tests of the
  selection geometry assert `font_logical_size` as the height of a row.

### 2.4 Other text

- About 25 widgets size a text box from the measured height and centre that box
  in the control (`_text_size`,
  [WidgetToGraphics.jl:1031](../../source/widget/WidgetToGraphics.jl#L1031)).
  The chart and the sequence chart reserve their title and label bands the same
  way. omnet-julia sizes the label of a module and the timeline strip from the
  measured height.
- `_bounds_elem!` and the hit test of a `GraphicsText` take the height of a text
  from `font_logical_size`
  ([GraphicsDocument.jl:723-726, 788-792](../../source/graphics/GraphicsDocument.jl#L788-L792)),
  and `get_graphics_size`, `get_canvas_content_bounds`, `write_image` and
  `write_pdf` build on it.
- The math typesetter is the one correct precedent. Every box has a width, an
  ascent and a descent from the font tables, and `_row` puts every child on one
  baseline: `ascent = max(child ascents)`, `y = ascent − child ascent`
  ([MathToGraphics.jl:308-361](../../source/math/MathToGraphics.jl#L308-L361)).

### 2.5 What a `GraphicsText` means to each backend

`GraphicsText(text, x, y, font, color)` does not say in its docstring what `y`
is ([GraphicsDocument.jl:56-89](../../source/graphics/GraphicsDocument.jl#L56-L89)).
The `font_ascent` docstring and a comment in the math typesetter say that `y` is
the top of the box and the baseline is `font_ascent` below it. Each backend
finds that baseline in its own way:

- **SDL** puts the top of the rendered surface at `y`
  ([Sdl.jl:881-884](../../source/sdl/Sdl.jl#L881-L884)). The baseline is then
  SDL_ttf's own ascent below `y`, rounded at the device size. A string with a
  fallback glyph is drawn as runs on one baseline inside the surface
  (`_render_runs_blended`), and that surface is taller than one font.
- **PDF** puts the baseline at `y` plus the unrounded `hhea` ascent of the
  primary font ([Pdf.jl:394-399](../../source/pdf/Pdf.jl#L394-L399)), for every
  run of the text, fallback runs included. It emits no kerning.
- **The web client** draws with `textBaseline = "top"` at `y`, from the same font
  files ([client.js:344-350](../../asset/web/client.js#L344-L350)), so the
  browser decides the baseline and the kerning.

### 2.6 Where the ink is cut

A `GraphicsViewport` cuts in every backend. A viewport that ends at the height a
text reported cuts the bottom of g, p, q, y and j:

- each cell of a grid, because `clip_child_to_slot` gives a cell a viewport of
  the height the cell reported, on the axis where its docstring says it "clips
  nothing" ([LayoutToGraphics.jl:128-156](../../source/layout/LayoutToGraphics.jl#L128-L156));
- the body of a card, whose viewport is `inner.h` high under the comment
  "Height is not clipped"
  ([WidgetToGraphics.jl:5525-5536](../../source/widget/WidgetToGraphics.jl#L5525-L5536));
- a scroll pane with no height and a tab page with no offered height.

A walk of the graphics of a chat pane result on 2026-09-25
(`/var/tmp/text-height/cut_texts.jl`) found the table entries and the last line
of the result cut by 3 pixels, and the paragraphs between them whole.

### 2.7 The seal

`measure_text(backend, text, font) -> (Int, Int)`, "the `(pixel_width,
pixel_height)` of `text`", is declared in
[BackendInterface.jl:28-33](../../source/kernel/backend/BackendInterface.jl#L28-L33),
which is sealed (🔒). A change of that contract needs the owner's permission for
that file (§5, question 5).

## 3. The model

### 3.1 The metrics of a font

- **One authority: the font file**, read by the parser. The layout, every
  backend and every test read the same numbers.
- **The vertical metrics** are the ones FreeType uses, so SDL_ttf reads the same
  numbers: the `hhea` ascender, descender and line gap; the OS/2 typo metrics
  when the font sets USE_TYPO_METRICS; FreeType's rule when `hhea` is empty.
  Step 1 confirms the rule for every bundled font against SDL_ttf at a size where
  one pixel is one font unit.
- **The metrics are real numbers** in logical pixels at the logical size of the
  font: `ascent`, `descent` (positive), `line_gap`. Nothing rounds a metric on its
  own. Rounding happens once, where a position is made (§3.7).
- **The horizontal metrics:** the `hmtx` advance of each glyph, and the kerning
  of each pair of glyphs of one font (question 1). No hinting changes an advance.

### 3.2 The box of a string

A string in one `StyleFont` is split into runs by the font that draws each
glyph: the font itself, or a fallback font (`find_glyph_font_file`). Its box is:

- `width` = the sum of the advances, plus the kerning between the glyphs of one
  run, as a real number;
- `ascent` and `descent` = the largest of the fonts that draw its runs;
- `line_gap` = the largest of those fonts.

This is the box a backend draws: each run on the baseline of the string, each
glyph at its advance.

### 3.3 A line

A line is a sequence of boxes: strings, and inline images.

- **The baseline.** Every box sits with its baseline on the baseline of the
  line. A string's top is the baseline minus its own ascent.
- **An inline image** sits with its bottom on the baseline, as a picture "in line
  with text" does in a word processor: its ascent is its height, its descent 0.
- **The line metrics:** `A` = the largest ascent of its boxes, `D` = the largest
  descent, `G` = the largest line gap. A line with no box (a blank line) takes
  the metrics of its own font (the newline's font).
- **The natural distance** of the line is `N = A + D + G`. This is the line
  distance that the fonts ask for: FreeType's `height` and SDL_ttf's line skip.
  For Ubuntu 20 it is 22.98; for Ubuntu Mono 20 it is 20.00.

### 3.4 The line distance

The line spacing of a text sets the distance `L` of each line, as word
processors do:

| Spacing | `L` |
| --- | --- |
| `Single` | `N` |
| `Multiple(f)`, for example 1.15, 1.5, 2 | `f × N` |
| `Exactly(d)` | `d` |
| `AtLeast(d)` | `max(d, N)` |

- **The leading** of a line is `L − (A + D)`. It is placed inside the line box,
  around the ink (question 2).
- **The line box** of a line is `L` high. The next line's box starts where it
  ends, so one baseline is `L` below the other.
- **A text block** is as high as the sum of its line boxes, with the first line
  at its top. `Exactly(d)` with `d < A + D` lets the ink of neighbouring lines
  overlap, as it does in a word processor. The box of the block still reaches
  the ink bottom of its last line, so R6 holds.
- **The setting lives on the projection that lays out lines,**
  `TextToGraphics(; line_spacing = Single)`, and a theme chooses it for code,
  prose and widgets (question 3). A space before or after a paragraph stays with
  the block layouts: the gap of a Markdown page is that space.

### 3.5 The caret, the selection and a click

- **The caret** stands on the baseline and is as high as the font at its place:
  from `baseline − ascent` to `baseline + descent` of the run it is in, as in a
  word processor. On a blank line it takes the line's font. Its x is the caret
  offset of its character boundary (§3.8), not the width of the text before it.
- **A selection** covers the full line box of each line it spans, so the
  rectangles of consecutive lines meet with no gap and no overlap. Its left and
  right edges are caret offsets.
- **A click** picks the line whose box holds its `y`, then the character boundary
  whose caret offset is nearest to its `x`. A segment knows its line by an
  index, not by an equal `y`, because segments of one line now have different
  tops.

### 3.6 The contract of `GraphicsText`

- `y` is the top of the text's box, and **the baseline is `y + ascent`**, with the
  ascent of §3.2 as §3.7 rounds it. The box is `ascent + descent` high. The
  docstring of `GraphicsText` says so.
- **SDL** draws the surface so that its baseline, which SDL_ttf puts at
  `TTF_FontAscent` below its top, lands on the layout's baseline in device
  pixels. It opens each font with kerning as §3.1 decides and with the hinting
  `TTF_HINTING_LIGHT_SUBPIXEL`, which keeps the advances unhinted. The runs of a
  fallback font stay on that baseline.
- **PDF** puts the baseline at `y + ascent`, the same rounded number, for every
  run, and writes the kerning of §3.2 into the text as `TJ` adjustments.
- **The web client** gets the baseline and draws with `textBaseline =
  "alphabetic"`, with the browser's kerning set as §3.1 decides. Step 3 checks
  the browser's advances against the measure; where they differ, the client
  places each run at the x the layout sends.
- **The console** draws cells, has no font, and does not change.

### 3.7 Rounding

Positions in the graphics are integer logical pixels (`Int32`).

- A line's top is the rounded sum of the real distances `L` of the lines above
  it, so rounding never drifts down a long text.
- A line's baseline is its top plus the rounded ascent of the line; each string's
  top is that baseline minus its rounded ascent. So all strings of a line share
  one integer baseline.
- A box's height rounds `A + D` up, so it never ends inside the ink.
- A string's x is the rounded real sum of the widths before it on the line, so
  a long line with many runs does not drift either.
- At a device pixel ratio above 1, SDL places the surface in device pixels, so
  the baseline lands on the same pixel as the layout computed.

### 3.8 The measure contract

The layout needs a box, not a pair, and the caret needs the pen positions.

**Where it lives.** A new file, `source/style/TextMeasure.jl`, in the style
package (`StyleModule`), beside the font parser (`TrueType.jl`) and `StyleFont`.
Every package that lays out or draws text already depends on the style package.
`TrueType.jl` keeps the font tables and gains the line gap, the OS/2 metrics and
the `kern` table. Each projection that lays out text holds a measure object in
its `measure` field, where it holds a function today: `TextToGraphics`,
`WordWrapping`, `WidgetToGraphics`, `NaturalToGraphics`, the charts, the math
typesetter. The application and the exports pass `FontFileMeasure()`, and a test
passes a `FixedMeasure`.

**What it returns.** All values are real numbers in logical pixels, and nothing
here rounds; the layout rounds a position once (§3.7).

```julia
abstract type TextMeasure end

struct FontMetrics
    ascent::Float64           # baseline up to the top of the box
    descent::Float64          # baseline down to the bottom, positive
    line_gap::Float64         # the extra line distance the font asks for
end

struct StringBox
    width::Float64            # advances plus kerning, fallback runs included
    ascent::Float64           # the largest of the fonts that draw its glyphs
    descent::Float64
    line_gap::Float64
end

measure_string(measure::TextMeasure, text, font::StyleFont) -> StringBox
get_font_metrics(measure::TextMeasure, font::StyleFont) -> FontMetrics
compute_caret_offsets(measure::TextMeasure, text, font::StyleFont) -> Vector{Float64}
```

- **`measure_string`** gives the box of a string. The line places the string on
  its baseline with it and computes its `A`, `D` and `G` from it.
  `WordWrapping` reads only its `width`.
- **`get_font_metrics`** gives the metrics of a font with no text: a blank line,
  and a caret on an empty place.
- **`compute_caret_offsets`** gives the x of each character boundary of the
  text: `length(text) + 1` values, the first 0 and the last the width. Each is the
  pen position where the next glyph starts. With kerning, the width of a prefix
  is not that position: the caret after "A" in "AV" stands where "V" starts,
  after the kerning of the pair A–V, and the prefix "A" alone does not hold that
  kerning. The caret, a click and the edges of a selection read these offsets
  (§3.5). A boundary between two runs of different fonts has no kerning.

The implementations:

- **`FontFileMeasure`** is the authority of §3.1, the one the application, the
  exports and every backend's layout use. It answers from the font file: the
  `hmtx` advances, the `kern` pairs inside a run of one font (question 1), the
  fallback font of each glyph that the font lacks, and the ascent, descent and
  line gap by FreeType's rule. It keeps the tables of a font once, and it can
  hold the font zoom of an editor, which is what
  [font-zoom-per-editor.md](font-zoom-per-editor.md) needs (§7).
- **`FixedMeasure(advance, ascent, descent, line_gap; fonts = Dict())`** is the
  measure of a test: every character is `advance` wide, every font has the
  metrics given, and there is no kerning. It replaces the closures such as
  `(t, f) -> (length(t) * 8, 16)`. The optional `fonts` maps a `StyleFont` to
  its own `FontMetrics`, so a test of mixed fonts gives two fonts different
  metrics.
- The function contract `(text, font) -> (width, height)` goes, with no shim
  that keeps both: two contracts are two truths. About 29 files in 20 packages
  pass a measure, about 13 test files write a closure, and omnet-julia and
  inet-julia pass the default.
- A backend no longer measures text for the layout. `measure_sdl_text` goes, and
  `measure_text(backend, …)` answers the authority's box, or goes (question 5).

### 3.9 The other readers of a text height

- **A widget** sizes a one-line label by its line box with `Single` spacing, and
  centres that box in the control.
- **The chart and the sequence chart** reserve their bands by the line box.
- **`_bounds_elem!` and the hit test of a `GraphicsText`** take the box of §3.6,
  so `get_graphics_size`, `write_image`, `write_pdf` and the repaint areas cover
  the ink.
- **The math typesetter** keeps its box model and takes its widths from the new
  measure.
- **omnet-julia**: the module label and the timeline strip use the line box.

## 4. What changes for a person

- Runs of different fonts on one line sit on one baseline: inline code, list
  markers and fallback glyphs move up to 2 pixels.
- With `Single` spacing, a line of body text is 23 pixels apart at 20 pixels
  (today 20), and a line of code stays 20 apart, because Ubuntu Mono has no line
  gap and its box is its em size.
- The caret, the selection and a click match the glyphs, also in headings and in
  kerned pairs, at ratio 1 and 2.
- No descender is cut.
- Widget boxes that are sized by their text grow by the difference between the
  line box and the em size: 3 pixels for the body font, 0 for the code font.

## 5. The questions, decided

The owner, 2026-09-25: "I agree with your recommendations". Each question
below takes its recommendation.

1. **Kerning.** (a) Kern with the `kern` table, the pairs that SDL_ttf draws
   today, in the layout, SDL, PDF and the web client. (b) Kern with the GPOS
   pair adjustments, the fuller table, which SDL_ttf without HarfBuzz does not
   draw: it needs HarfBuzz in SDL_ttf or positions for each glyph. (c) No
   kerning anywhere. **Decided: (a) now, because it is correct in every
   backend with the tables that exist, and (b) as a later plan.**
2. **Where the leading goes.** (a) Half above the ink and half below, as CSS and
   the editors built on it do: the ink sits in the middle of its line box, and
   the caret and the selection look even. (b) All above the ink, as Microsoft
   Word does with a multiple. **Decided: (a).**
3. **The default spacing.** `Single` for code and widgets. For prose: `Single`
   (22.98 for Ubuntu 20), or `Multiple(1.15)`, the default of current word
   processors. **Decided: `Single` everywhere, and a theme value to change
   it.**
4. **The web client** in this plan, or after it. **Decided: in it,
   because R5 names every backend.**
5. **The sealed file.** `measure_text` in `BackendInterface.jl` either answers the
   authority's box (its contract changes) or goes. Both need permission for that
   file. **Decided: it goes, because the layout does not ask a backend.** The
   owner's answer is the permission to change `backend/BackendInterface.jl` for
   this one change, the removal of `measure_text`, and for nothing else in that
   file. `SEALING.md` asks for the permission in the conversation that makes
   the change, so the implementer confirms it with the owner before Step 6.

## 6. Steps

Do the work in a git worktree. Commit each step. Before a kernel file changes,
check [SEALING.md](../../SEALING.md) for it.

**The order is 0, 1, 2, 3, 5, 4, 6 to 11.** Step 5 comes before Step 4. Each
projection holds its measure in one typed field, so the line model can not read a
`TextMeasure` while the other readers of that field still pass a function.

- [x] **Step 0. The baseline and the probes.** On the base commit, the counts of
  `test_substrate()`, `test_markdown()`, `test_chart()`,
  `test_sequencechart()`, `test_math()`, the shell and PDF tests, and the
  presentation tests of omnet-julia and inet-julia. Two probes kept as tools of
  the plan: the walk of `/var/tmp/text-height/cut_texts.jl` (ink against the
  viewports), and an ink probe that draws a line through SDL offscreen and
  reads where the ink of each run begins, ends and sits (its baseline row).
  *Done.* The counts are in `/var/tmp/text-baseline-base/test-counts.tsv`, the
  failures of the base in `failures.txt`, the catalog counts in
  `catalog-per-example.tsv`, and the cut texts in `cut_texts.log`. The base has
  known failures: substrate 3 fail and 2 error (`SplitPaneDragTest`), formula 12
  fail (`FormulaToSyntaxTest`), assistant_mvp 4 fail, `conversation_widget` 1060
  fail, `assistant` 2 fail, `markdown_rendered` 8 fail.
- [x] **Step 1. The metrics of a font** (§3.1). The parser reads the `hhea` line
  gap, the OS/2 typo and win metrics, `fsSelection`, and the `kern` table
  (question 1). A test compares ascent, descent and line gap with SDL_ttf for
  every bundled font at the size where a pixel is a font unit, and the kerning
  of a set of pairs with FreeType's.
  *Done* in `c8f65f3a` (the test with SDL_ttf in `dd396eb0`). `get_kerning` and
  `get_vertical_metrics` are in `TrueType.jl`. SDL_ttf agrees with the parser in
  519 assertions. The generated binding lacks `TTF_GetFontKerningSizeGlyphs32`,
  so the test calls it with `ccall`.
- [x] **Step 2. The box of a string and the measure contract** (§3.2, §3.8).
  `TextMeasure`, `FontMetrics`, `StringBox`, `measure_string`,
  `get_font_metrics`, `compute_caret_offsets`, `FontFileMeasure`,
  `FixedMeasure`. A test compares the width of a set of strings (the strings of
  §2.1, pairs, fallback glyphs) with the width SDL draws after Step 3, for
  Ubuntu, Ubuntu Bold, Ubuntu Mono and DejaVu at 14, 20 and 36 pixels and ratios
  1 and 2: equal within one device pixel. A test of the caret offsets: each step
  is the advance of its glyph plus the kerning with the next glyph of the same
  run, the last offset is the width, and the offset where each glyph starts
  matches the column where the ink probe of Step 0 finds that glyph drawn.
  *Done* in `c8f65f3a`, in `source/style/TextMeasure.jl`, with
  `compute_text_extent`, the rounded box that every backend draws. The
  comparison with the width that SDL draws moved to Step 3b: it found that SDL
  does not draw at the pen positions of the layout.
- [x] **Step 3. The backends draw where the layout says** (§3.6). The
  `GraphicsText` docstring; SDL: hinting, kerning, and the placement of the
  baseline in device pixels; PDF: the baseline and the `TJ` kerning; the web
  client: the baseline and the kerning (question 4). Tests: the ink probe finds
  the baseline row of a line of Ubuntu, Ubuntu Mono, a DejaVu marker and an
  emoji at one row, at ratio 1 and 2; the PDF test finds one baseline for every
  run.
  *Done* in `dd396eb0` for the baseline. SDL renders with
  `TTF_HINTING_LIGHT_SUBPIXEL` and kerning on, and places the baseline of each
  texture at `y + ascent`. The web client draws each character at its pen
  position. It is not run in a test, because the machine has no `node`.
- [x] **Step 3b. SDL draws each glyph at the pen position of the layout.** A
  probe measured where SDL_ttf puts the pen: the width of a prefix and of the
  prefix with a bar after it. With the same font, the same hinting and the same
  kerning, SDL_ttf moves away from the layout by up to 1.38 device pixels
  (Ubuntu 20, 24 characters) and 1.78 (DejaVu, "Type yj"). The advances of
  SDL_ttf are those of the hinted glyphs, and the layout uses the advances of
  the font file. Ubuntu Mono is exact. Thus SDL renders one glyph at a time, as
  the web client does. A test finds the left edge of the ink of a bar after each
  prefix within one device pixel of the offset of the layout.
  *Done* in `684bba42`, with a change of the design: SDL does not draw one
  texture for each glyph in each frame. On a miss of the text texture cache,
  `_render_text_surface` rasterizes each glyph that `compute_placed_glyphs`
  names, in its font file and in the color of the text, and composes the glyphs
  into one surface. The draw path stays one texture for each text, so the cost
  of a frame does not change. The pen origin of each glyph goes on the device
  pixel nearest to its pen position, so the error is the rounding of that pixel:
  0.48 device pixels at most, for every case at ratio 1 and 2. SDL_ttf lays a
  glyph out as a string of one character, with the pen origin at column
  `max(0, -minx)` and the baseline at row `max(ascent, maxy)`, from
  `TTF_GlyphMetrics32`. The binding lacks it and `TTF_RenderGlyph32_Blended`,
  so SDL calls them with `ccall`. The cache key holds the logical size of the
  font as well as the device size, because two zooms can give one device size
  and two logical sizes. The old test that compared `measure_sdl_text` with
  `measure_truetype_text` goes: no draw path uses them, and the pen test has a
  fallback glyph.
- [x] **Step 4. The line model** (§3.3 to §3.5, §3.7) in `TextToGraphics`: the
  baseline, the line metrics, the line spacing, the blank line, the inline
  image, the caret, the selection, the click, and the line index of a segment.
  Tests with a `FixedMeasure` of two fonts: tops, baselines, line boxes, each
  spacing, the leading, contiguous selections, click bands, the caret of each
  font; and a test with the authority that a line of body text, code and an
  emoji has one baseline.
  *Decisions made in the step:*
  - A `SegmentCoordinate` carries the line box of its line in `y` and `height`,
    not the box of its text. So every segment of a line has the same `y`, the
    boxes of consecutive lines meet, a click picks a line by its box, and a
    selection row is the line box. Home, End, Up and Down find a line by its
    `y`, as before, so a segment needs no line index. The `y` of a drawn text is
    its own: the baseline less the rounded ascent of its box.
  - `_layout_group` collects the pieces of a visual line (texts, images, the
    places of empty lines, the caret) and places them when the line closes,
    because the baseline needs every box of the line. `_GroupLayout` holds the
    state, so the layout stays free of boxed closures.
  - A group returns the real sum of its line distances (`distance`) and the
    lowest pixel of its ink (`height`). The line stack chains the real
    distances and rounds each top once; the overlay does the same, so the caret
    and the glyphs agree. A line inside a group rounds its top from the start
    of the group, so the error stays under one pixel and does not add up.
  - The paragraphs of the `ListNode` path chain their real line distances in
    the same way.
  - The empty line after a trailing '\n' adds no height, as on the base; its
    caret stands where the next line begins. A group with no glyph that is a
    line takes one line of `_line_height_font`, as on the base.
  - An inline image sits on the baseline: its ascent is its height.
  - The caret is `compute_text_extent(measure, "", font)` high, from the
    baseline less its ascent, in the font of the span at its place.
  - `TextToGraphics(; line_spacing = SingleSpacing())`. No theme reaches
    `TextToGraphics` today: every builder passes only a measure. So a theme can
    not choose the spacing yet (question 3). This is an open item for the owner:
    where a theme of code, of prose and of a widget meets the text layout.

  *Done.* `test_text_line_model` (21) tests the model with a `FixedMeasure` of
  two fonts and with the font files. The suites of Step 0
  (`/var/tmp/text-baseline-step4/`) fail as the base does. The substrate count is
  that of Step 5 and the new test. `catalog_markdown` falls by 525 more, in the
  printer walk of eleven `/syntax` atoms (`table` −146, `list` −64 and nine
  others): the new types move the `Dict` order of Step 5 again, and these atoms
  take the Julia object bridge too. Their reader and REPL counts do not move.
  *Open item for the owner:* `path_sequences` takes its goal types from a
  `Dict{DataType,Int}`, so a new type anywhere can change which projection the
  catalog tests for a `/syntax` atom. On this branch 13 Markdown atoms test the
  generic Julia bridge and no longer the Markdown syntax projection. A fix takes
  the goal types in the order the search finds them; it is a change of the
  catalog, outside this plan.
- [x] **Step 5. Every reader moves to the new contract** (§3.8, §3.9): the
  widgets, `_bounds_elem!` and the hit test, the charts, the fault and gesture
  overlays, the math widths, `WordWrapping`, the Markdown and syntax
  projections, and the test closures. The mechanical part of this step suits a
  delegated agent, and its result is checked file by file. The dirty rectangle
  of a text in SDL (`_bounds_of_elem`, `_bounds_of_canvas`) must cover the
  texture: its left edge is left of `x` by the ink of a negative left bearing,
  and its top is above the box when a glyph rises above the ascent of the
  font. The glyph metrics that `_render_text_surface` reads give that extent
  without a render. On the base, the bounds are the em size high, so a partial
  repaint does not cover the descenders.
  *Decisions made in the step:*
  - `compute_text_extent(measure, text, font)` is the rounded box of a text for
    any measure; the form with no measure is the `FontFileMeasure` box that the
    backends draw.
  - The spacing types are `SingleSpacing`, `MultipleSpacing(factor)`,
    `ExactSpacing(distance)` and `AtLeastSpacing(distance)` in
    `source/style/LineSpacing.jl`, with `compute_line_distance` and
    `compute_baseline_offset`. The short names of §3.4 (`Single`, `Exactly`)
    are too general to export.
  - A reader that places one text on a line of its own (a widget label, a chart
    title, an overlay row) asks `compute_line_box(measure, text, font)`. It
    answers the width, the height of the line box, the baseline and the `y` of
    the text in the box. The baseline is the rounded offset of the model, but
    never less than the rounded ascent of the text, so the ink never rises above
    the line box. The height reaches the bottom of the box of the text when that
    is below the line distance: Ubuntu Mono 20 has a line distance of 20 and a
    line box of 21 (17 + 4).
  - `_bounds_elem!`, `get_graphics_size` and `get_canvas_content_bounds` take a
    `TextMeasure`, by default `FontFileMeasure()`. A bare text has its width in
    `get_graphics_size`, where it had none.
  - The hit test of a `GraphicsText` is its box, with a right edge.
  - SDL finds its dirty rectangles and the size of `write_image` by its own walk
    (`_extend_drawn_bounds!`), which adds the texture of each text.
  - `write_pdf` has no `measure` keyword: the PDF writer draws from the font
    files, so only `FontFileMeasure` can size its pages.
  - The widgets lose `TextMeasurer`, the wrapper that kept a function out of a
    cell: a `TextMeasure` is a value.
  - A widget, a chart and an overlay place each text at the top of its line box
    plus `text_y`. `_push_text!` of the widgets takes the measure for that.
  - A test closure `(t, f) -> (length(t) * a, h)` became
    `FixedMeasure(a, h - h ÷ 4, h ÷ 4, 0)`: its line is `h` high, as before.
    The two tests of the window shell that sized a line by the em size take the
    box of the font files.
  - `TextToGraphics` measures its segments with `compute_line_box` and puts the
    caret at the pen positions of `compute_caret_offsets`. Its line model waits
    for Step 4.
  - `asset/precompile/PrecompileStatements.jl` names `TextMeasurer` and
    `measure_truetype_text` in old signatures. A replay skips an entry that does
    not resolve, so the file needs a new recording, not an edit.

  *Done.* The suites of Step 0 on the branch (`/var/tmp/text-baseline-step5/`)
  have the same failures as the base, at the same lines. Four pass counts move,
  and each has its cause:
  - substrate +54: `test_line_spacing` 15, `test_text_measure` 24, and the font
    metrics test 29 where the base has 14.
  - sdl +537: the metrics agreement 519, the baseline ink 4 and the pen
    positions 16, less the 2 assertions of the old fallback measure test.
  - write_pdf +3: the tests of Step 3.
  - catalog_markdown −102: `markdown/image/syntax` −41 and `markdown/link/syntax`
    −61, all in the printer walk. Each atom has two paths of equal length to
    syntax, one through the Julia dispatcher and one through the Markdown
    dispatcher, and `path_sequences` orders them by a `Dict`. The new types move
    the hash order, so the catalog takes the Julia path first. A fresh process on
    the branch gives the same counts. This is not a change of behavior.
- [x] **Step 6. The old contract goes.** `measure_truetype_text` as a pair,
  `measure_sdl_text`, `font_logical_size` as a height, and `measure_text` of the
  backends (question 5). The naming guard passes.
  *Part one, done:* the uses of the em size as a height go.
  - `font_ascent` and `font_descent` are the box of a text in the font alone,
    as `compute_text_extent("", font)` gives it: the rule of FreeType, rounded
    up. They rounded the `hhea` values to the nearest pixel, so at Ubuntu 14
    (13.05) the math put the baseline one pixel above where a backend draws it.
  - The math typesetter takes the box of each text run and each glyph from the
    text itself (`_get_text_ascent`), so a glyph that a fallback font draws sits
    where a backend draws it.
  - `GraphicsCaching` bounds a text by its box, where it took a width of 200
    and the em size.
  The suites of Step 0 fail as the base does. In the warm session,
  `example_markdown` counts 4081 and `example_markdown_rendered` 3777; the
  difference is in `test_typein`, and neither the old caching bounds nor the old
  math metrics change it there. A fresh process on the branch counts 3911, as the
  base does. So the typein count follows the history of the process, and a count
  that moves must be measured in a fresh process, as the base was.
  *Part two, done:* `measure_text` is declared in `BackendInterface.jl`,
  exported by `BackendModule.jl` and named in a comment of `BackendDefaults.jl`.
  All three are sealed; the owner gave the permission for the three on
  2026-09-26. The declaration, the export and the name go, with
  `measure_truetype_text`, `measure_sdl_text`, the run helpers of SDL, the
  `measure_text` methods of the SDL, web, video, console and example backends,
  and their tests. SDL does not turn on the kerning of SDL_ttf: each glyph draws
  at the pen position of the layout. The naming guard passes.
- [x] **Step 7. No ink is cut** (R6). A test walks a `WidgetTable` of text, a
  card with a text body, a scroll pane with no height and a Markdown result in
  the chat pane, and asserts that the box of every text ends inside every
  viewport around it. It fails on the base commit.
  *Done:* `test_text_ink_inside_viewports` (10) in
  `test/projectured/projection/TextInkTest.jl`. It asserts that the walk sees
  the texts of each case, and that it finds the cut of a viewport as high as
  the em size. The test uses the new API, so it does not load on the base; the
  probe of Step 0 found five cut texts in the same Markdown result there.
- [x] **Step 8. The suites of Step 0**, compared with the baseline. A moved pass
  count is explained before it is accepted.
  *Done* after the rebase on `main` (`14deb157`), both sides in a fresh process
  (`/var/tmp/text-baseline-main/` and `/var/tmp/text-baseline-final/`). The
  failures are the same, 1091 entries at the same files and lines. The moved
  counts: substrate +77 (the new tests 15, 24 and 21, and 17 more in the font
  metrics test); sdl +529 (the new tests 519, 4 and 16, less the 10 assertions
  of the removed tests); write_pdf +3; catalog_markdown +3388, from the
  deterministic order of the catalog (a separate commit): every Markdown atom
  takes the Markdown bridge in its `/syntax`, `/text` and `/graphics` variants,
  and none fails. The `/syntax` variants count what the first base counted; the
  `/text` and `/graphics` variants took the Julia bridge on the first base too.
- [ ] **Step 9. The look, in a real window.** The application on `main` and on
  the branch, with the same panes: a code tab, a guide with a table and inline
  code, the chat pane with a result, a form, a heading with kerned pairs, and a
  selection across three lines. Images of both go to the owner, at ratio 1 and 2.
  *Images made, the review of the owner open:* `/var/tmp/text-baseline-look/`
  holds `scenes.jl`, which renders through `write_image` (the SDL renderer,
  offscreen) at ratio 1 and 2, the images of the base and of the branch, and
  `compare/`, each pair side by side (base left, red; branch right, green):
  a line of body text, code and an emoji under a kerned heading; a selection
  across three lines; a Markdown result in the chat pane; a JSON code tab; the
  widget gallery. On the base, the descenders of the last line, of every table
  cell and of the status line are cut; on the branch every ink shows, the runs
  of a line share its baseline, and selection rows meet. The code tab does not
  change: Ubuntu Mono has no line gap. A check in a live window is not done.
- [ ] **Step 10. omnet-julia and inet-julia** follow the contract: their packages
  precompile, their presentation tests pass, and images of a topology, a
  timeline and a packet diagram go to the owner.
- [x] **Step 11. The documents:** `style.md` (the metrics and the measure),
  `text.md` (the line model and the spacing), the `GraphicsText` docstring and
  `graphics.md`, `sdl.md`, `pdf.md`, `web.md`, `layout-rules.md` if it names a
  text height, and `markdown.md`, whose limit goes.
  *Done:* 23 documents. `style.md` has the measure contract and the line
  spacing; `text.md` the line model; `graphics.md` the box of a `GraphicsText`;
  `sdl.md`, `pdf.md`, `web.md` and `console.md` how each backend draws a text;
  `devices-and-backends.md`, `editor.md` and `architecture-invariants.md` the
  backend interface with no `measure_text`; `markdown.md` loses its limit; the
  example code of eleven more documents passes `FontFileMeasure()`.
  `layout-rules.md` names no text height, and `testing-guide.md` names no
  removed test.

## 7. Relations and risks

- [font-zoom-per-editor.md](font-zoom-per-editor.md) (pending) changes the same
  measure. Its option (B) passes the zoom through the measure; a `TextMeasure`
  object can hold it. The two plans must agree on one contract before either
  changes it.
- [layout-sizing-model.md](layout-sizing-model.md) (pending, landing open) owns
  the rules of ranges and clipping. This plan changes no rule: a viewport keeps
  clipping, at a box that now holds the ink.
- [word-wrapping-projection.md](word-wrapping-projection.md) (pending):
  `WordWrapping` takes the new width, and nothing else in it changes.
- [sdl-per-editor-state.md](sdl-per-editor-state.md) (pending) changes the font
  cache and the ratio of the SDL backend, which Step 3 also touches.
- **Every text moves.** Every screenshot, video and image test changes, and the
  pass counts of the printer walks change with the new fields.
- **Kerning costs a lookup per pair.** The measure keeps the pairs of a font in a
  table, and a string's box is computed once for each text and font.
