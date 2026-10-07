# Text domain

> **Kind:** design · **Status:** current · **Stands on:** [reference.md](../../kernel/reference.md), [projection-system.md](../../kernel/projection-system.md), [style.md](../style/style.md), [graphics.md](../graphics/graphics.md)

The text slice of `ProjecturedPlatform` holds styled text as a flat sequence of spans, and the projections that lay it out as graphics or change it on the way. Nearly every view reaches the screen through it, because `SyntaxToText` prints to it. This document says how the caret is addressed, how a key becomes an edit, and why the text decorators can map a caret in both directions.

<img width="396" alt="Text example" src="../../../asset/image/example/text.png">

## How it works

| Document | What it is |
| --- | --- |
| `TextBlock` | the container: `elements`, a `CellVector` of spans or lines |
| `TextString` | a span: `content`, `font`, `font_color`, `fill_color`, `line_color`, `padding` |
| `TextNewline` | a line break, with the same style fields |
| `TextSpacing` | a gap of `size` in `:pixel` or `:space` units |
| `TextGraphics` | a graphics document, such as an image, inline as one glyph and one caret position; it has no font and no colour |
| `TextLine` | one line of spans, with an `indentation` and a `gutter` |
| `TextGutter` | the gutter of a line of code: a `marker`, a `number` and a `fold`, each a mark or `nothing` |
| `TextFold` | a region of lines that folds: its `line_count` after its first line, `collapsed`, and a `placeholder` |

A `TextString` keeps `content` in a reactive `Cell`, because you type into it. `font` and `font_color` are an `ImmutableCell` by default: the style of a span is authored and not edited, so no glyph gets a dependency edge on it. Pass a `Cell` to make one of them reactive.

**A `TextLine` holds no break and implies one before itself.** So a block of `n` lines has `n - 1` breaks and no empty last line. Its `indentation` is a property of the line and not a span, so no caret can land in it. A span inside a line has the index path `[i, j]`, the type `SpanPath`, and the caret path gets a second `elements` step: `.elements[i].elements[j].content{k}`. A block must hold spans or lines, not both. Nothing enforces this, and no projection makes a mixed block.

`@domain Text` makes `TextNothing` and `TextInsertion`; see [domain.md](../domain/domain.md). Only `TextBlock` is a candidate of the insertion: `@insertion TextBlock` makes a block with one empty span and the caret in it. A span type has a required field, so it is not a candidate, and the text chain can not print a lone span at the root.

### The caret

**The canonical caret is a flat offset.** `TextRangeReferenceStep(start, stop)` counts characters over the whole block, from 0. `start == stop` is a caret, and it evaluates to a `Position`. A `TextNewline`, a `TextSpacing` and an inline `TextGraphics` count one character, and so do the indentation and the implied break of a `TextLine`. `get_flat_offsets` is the one function that counts the implied break. So a place between two spans has one offset, from whichever direction the caret came. `get_flat_string` gives the text as one string with one character for each offset: U+FFFC for an image, as `TextToString` gives it.

**An image has a caret before it and a caret after it.** An offset resolves to the text run that holds it, and at the seam of two runs to the end of the earlier run. An offset that no run holds is beside an image: the caret before the image or after it, drawn at its left or right edge. Because an image is one offset, the caret before it and the caret after it never have the same offset.

The structural form `.elements[i].content{k}` is the second legal form. An edit leaves it behind after `evaluate_operation`, until the next print makes the caret flat again. `get_flat_caret` reads either form, and every decorator maps the caret through it.

The package has three reference steps with the same `(start, stop)` data:

| Step | Meaning |
| --- | --- |
| `TextRangeReferenceStep` | the character caret or range; the motion keys move it |
| `TextSpanReferenceStep` | a whole-element box over a flat range; `SyntaxToText` makes it for a selected child, and a motion key does not move it |
| `TextColumnReferenceStep` | a rectangle of columns; `TextToGraphics` can paint it, but no gesture makes one |

The kernel reference layer names none of them. This package registers each one as a `:structural` step with `get_reference_step_kind` and `evaluate_reference_step`.

### From a key to an edit

The reader has two halves.

**The geometry-free half** is the `@gestures TextBlock` table in `source/platform/text/TextDocument.jl`. It reads only `elements` and `selection`:

| Key | Edit |
| --- | --- |
| a printable key | insert the text at the selection |
| Backspace, Delete | delete one character, or the range; Backspace after an image and Delete before it delete the image |
| Left, Right | move the caret one character; a range collapses to its near end |
| Ctrl+Left, Ctrl+Right | move by a word; an image is a word of its own |
| Ctrl+Home, Ctrl+End | go to the start or the end of the text |
| Shift with one of the six motion keys above | move one end of the range and keep the other |
| Ctrl+. | `ToggleCollapseOperation`, which the syntax stage resolves |

The table matches modifiers exactly. `KeyDown(:left;)` is plain Left, and Alt+Left is a different gesture. A key with no rule, such as Tab or Alt with an arrow, gets no operation, so it goes on to the syntax stage. A plain arrow on a whole-element selection also gets `nothing` from the motion rule.

**The geometry half** is the reader of `TextToGraphics`. It calls the table first through `_gesture_op`. If the table gives `nothing`, the reader uses its coordinate table for three kinds of input. Plain Home and End go to the ends of the visual line. Up and Down keep the nearest x. A mouse click places the caret. Shift with Home, End, Up or Down moves one end of the range in the same way. A click always makes a plain caret; `SyntaxToText` resolves Alt+click. A key that neither half uses gives `nothing` and never the raw event, so the next reader gets it.

A typed key makes a `ReplaceTextRangeOperation` on the flat range. `_lower_text_range` lowers it to a `ReplaceStringRangeOperation` on `.elements[i].content[s:e]` of one span, which the syntax stage and the domains read. A range that crosses two spans lowers to `nothing`. At the end, `splice_value!` changes the `content` of the span in place. On a `TextBlock` target it finds the span that holds the range in the caret space, and on an empty block it adds a `TextString`.

**An edit beside an image writes the element list.** A key typed where no run holds the caret, beside an image, starts a new run there with `make_insert_elements_operation`. A range of only images is deleted with `make_delete_elements_operation`, or replaced by one new run of the typed text. Each leaves the caret after it, and undo takes it back. A new run takes the style of the nearest text run of the image's line, the run before the image first; on a line with no run, the first `TextString` or `TextNewline` of the block. `evaluate_operation` of a `ReplaceTextRangeOperation` makes the same edits on a block that is the document.

### Layout

`TextToGraphics(; start_x, start_y, measure, line_spacing = SingleSpacing(), theme = nothing)` places the spans from left to right and starts a new line at a `TextLine`, a `TextNewline` or a `'\n'` in the content. It does not wrap. `measure` is a [`TextMeasure`](../style/style.md); `FontFileMeasure()` is the one the application and the exports pass, as every backend draws, and a test passes a `FixedMeasure`. `line_spacing` is a [`LineSpacing`](../style/style.md) and sets the distance to the next line, or a cell that reads one of the text theme: a builder of code passes `code_line_spacing` and a builder of prose `prose_line_spacing`, and a widget keeps single spacing. `theme` is a `TextTheme`, scaled or not, whose caret and selection band the projection holds as styles and draws; with `nothing`, it draws those of the default theme. When the printer context holds the property `:line_spacing`, as a table puts it for its cells, the text draws at that spacing in place of its own.

**Every box of a line sits on one baseline.** A `TextString` sits with its baseline on the baseline of the line, and its top is the baseline minus its own ascent, so a run in a smaller font or a fallback glyph aligns with the rest of the line. An inline `TextGraphics` sits with its bottom on the baseline, as a picture set in line with text does: its ascent is its height. A line with no box, an empty line, takes the metrics of its own font.

**The height of a line comes from its boxes.** It is as high as the largest ascent, the largest descent and the largest line gap of the boxes it holds. `line_spacing` sets the distance from the top of the line to the top of the next one; at `SingleSpacing()` that distance is the sum of those three. Half of the leading, the difference between the line distance and the ascent plus the descent, sits above the ink and half below.

**The caret stands on the baseline**, as high as the font at its place: from the baseline minus the ascent to the baseline plus the descent of the run it is in. Beside an image, which has no font, it takes the font of the nearest text run of its line, by the rule of a new run. Its x is the pen position of its character boundary from `compute_caret_offsets`, not the width of the text before it, so a caret after a kerned pair stands past the kerning. **A selection** covers the full line box of each line it spans, so the rectangles of consecutive lines meet with no gap. A range of the caret, a `TextRangeReferenceStep`, is painted with the offsets of the caret space. A box, a `TextSpanReferenceStep`, is painted with the offsets of the box space, where a `TextNewline` and a `TextSpacing` count 0, because `WordWrapping` adds soft newlines and a box must not move. An image in either counts 1, and it is painted. **A click** picks the line whose box holds its `y`, then the character boundary nearest to its `x`.

The examples show each rule of the layout, and the text of each says what to look at: `text_baseline_example` (runs of several fonts, a fallback glyph, an emoji and an icon on one baseline), `text_line_height_example` (lines of different heights, a code line with no line gap, an image on the baseline), `text_kerning_example` (kerned pairs and the caret in a pair) and `text_selection_example` (a selection across lines of mixed sizes). `text_spacing_examples` holds one example for each spacing; `run_example(text_spacing_examples)` opens them side by side, and `run_example(text_layout_examples)` the four others.

The IO map holds `char_to_coord`, one `SegmentCoordinate` for each drawn piece: its `span_path`, its character range, its pixel position, its font and its size. `y` and `height` are the line box of the visual line the segment is on, so every segment of one line shares them; a click picks a line by its box, and a selection covers each line it spans with no gap. An inline `TextGraphics` is one character wide in the text, carries the size of the image and the font of a caret beside it. So a click on its left or right half puts the caret before or after it. The reader and the hit test downstream use this table. `TextToGraphics` also draws the caret and the selection rectangles; [graphics.md](../graphics/graphics.md) describes the output.

**A click puts the caret, so `TextToGraphics` draws an I-beam over the box of its lines**, as an element of its top canvas ([graphics.md](../graphics/graphics.md#the-shape-of-the-pointer)). **A span can name a shape of its own** in its field `pointer_shape`, such as `:pointing_hand` over a link that a click follows: the canvas after the I-beam holds a region of that shape over each segment of the span, so it wins there. The copies of a span that word wrapping, highlighting, selection inverting and line numbers make carry the field. A text with no such span reads no segment for it. A container that gives no press to its text, such as a disabled field, covers it with the arrow instead ([widget.md](../widget/widget.md#the-shape-of-the-pointer)). The list path of `TextToGraphics`, drawn from a lazy list of spans, puts no caret at a point, so it draws no such region.

**A text reference maps forward to the characters that draw it**, as specifically as the output allows. A caret, and a range that one segment holds, map to the text node of that segment followed by the characters in it, `text{a:b}`; a caret is a range of no width. The text node of a segment is found in the canvas of its line by its place and its text, because a fill comes before some texts. A range across segments maps to the smallest node that holds all of its rows, the canvas of its line or the stack of lines, followed by a `RegionReferenceStep`: the box of the rows that its highlight draws.

**A text whose spans are a lazy list** (`ListNode`) is drawn as a list of paragraph canvases, one per paragraph between newlines. A span, and the characters of it, `elements[i].content{a:b}`, map to the text node of the span in its paragraph canvas; spans of one paragraph map to the paragraph canvas followed by a region, and spans of more paragraphs to the canvas of the text. The spans and the paragraphs count from their heads: the head paragraph holds the head span, and the paragraph before it ends at the span before the head. The stages before it map a lazy list forward by the same count: `CollectionListNodeToSyntax` maps element `k` to element `k` of its output, and `SyntaxListToText` maps element `k` to its spans in the list of spans.

### The gutter

**The gutter of a line is a property of the line**, as its indentation is: `TextLine.gutter` holds one document of any type, or `nothing`. It is not in the caret space and not in the flat string, so no caret of the text stands in it and a copy of a range never holds it, and it stays with its line when lines are added above. `TextGutter` is the gutter of a line of code; its fields are its lanes, `marker`, `number` and `fold`, and each holds a mark, any document that the recursion prints to graphics. A stage fills its own field, by name: it copies the gutter of its input line with that field replaced and every other cell kept, as `TextLineNumbering` does with `number`, or makes a `TextGutter` for a line with none. `TextLineNumbering` pads each number to the digits of the largest one, and a click that selects a number selects the whole line in its input. A view that wants other lanes brings a gutter type of its own and a projection for it.

`TextGutterToGraphics(; marker_width, number_width, fold_width, gap)` draws a `TextGutter` as one row: the marker, the number and the fold lane from the left. A lane is as wide as its mark and at least its width, so a lane keeps its width on a line that has no mark in it; a stage that wants a lane to grow gives every mark of the lane the same width. A marker and a fold stand in the middle of their lane, a number at its right, and the marks that draw text stand on one baseline.

`TextBlockToScrollLayout(; measure, …)` draws a `TextBlock` as a [`ScrollLayout`](../layout/layout.md#the-scroll-layout): the center is the canvas of the lines, laid out as `TextToGraphics` lays them out, and the left edge holds the gutter of each line, with its first baseline on the first baseline of the line. The left edge is as high as the lines and as wide as the gutter of the first line that has one. A `WidgetScrollPane` keeps it at its left edge while the lines scroll; anywhere else a chain ends with `LayoutToGraphics`, which draws it at the left of the lines. A click on a gutter goes to the projection of the gutter and on to the mark at the point, re-rooted into `.elements[i].gutter`; a click that a mark does not take selects the mark, so the stage that made it can answer. A key goes to the gutter that the selection is in, and else to the lines. A chain that holds gutters needs a recursion, because the recursion prints each gutter and each mark.

### Folds

**A text fold hides lines that the text holds.** `TextLine.fold` holds the `TextFold` that starts at the line, or `nothing`; the fold holds the line and the `line_count` lines after it, and at most one fold starts at a line. `TextFolding` drops the lines that a closed fold hides after its first line, and a closed fold inside a hidden region with them. The lines stay in its input, so a stage before it counts them: `TextLineNumbering` before `TextFolding` gives the lines after a closed fold their own numbers. This is not the syntax fold, where a closed node prints no children, so its lines are not in the text and the numbers after it change.

`TextFolding` puts a triangle, open or closed, in the `fold` field of the gutter of the first line of each fold, and the placeholder of a closed fold at the end of its first line: the spans of the `placeholder` of the fold, such as `…],` for a list, or `…`. A click on the triangle or on the placeholder answers `ToggleCollapseOperation(fold)`, and the operation with no target that Ctrl+. makes gets the innermost fold around the line of the caret. A projection that makes a fold can give it the `collapsed` cell of the part that it shows, so the state stays in the document. It maps a caret with one run of flat offsets for each line shown, and it reads a key against its output, so a motion steps over a closed fold.

### The decorators

A decorator is a projection from `TextBlock` to `TextBlock`. You put it before `TextToGraphics` in a chain.

| Projection | What it does |
| --- | --- |
| `WordWrapping(; max_width, measure)` | breaks lines at word boundaries, at the maximum of the range on the width (`ctx.maximum_width`), exact or bounded, cut at `max_width` when one is given; with neither, a line does not wrap |
| `TextFolding(; field, gutter_type, open_mark, closed_mark, theme)` | hides the lines that a closed fold holds after its first line, and puts its triangle in the gutter and its placeholder at the end of the first line |
| `TextLineNumbering(; width, separator, style, field, gutter_type)` | on a block of lines, puts the number of each line in the field `field` of its gutter; on a block of spans, puts a number span before each line |
| `TextFiltering(pattern; invert)` | keeps only the lines that match the pattern |
| `TextHighlighting(pattern; color)` | sets `fill_color` on each match |
| `SelectionInverting()` | shows the selection as inverse video in the span colours |
| `TextFirstLine()` | keeps the first line only |

**The shared design: a decorator never changes a character of its input.** It splits a span into pieces, restyles the pieces, adds a span that has no input, or drops whole lines. So each output span is either a piece of one input span at a known offset, or an added span. The IO map is a table of these pieces. `WrapSegment`, `HighlightSegment` and `SelectionSegment` have the same four fields. `TextFilteringIoMap.kept` holds the input index of each output span, and `TextFirstLineIoMap` holds the length of the kept prefix. The forward map, the backward map and the reader all read that table, and none of them searches the text to find where a caret goes.

A whole-element box, a `TextSpanReferenceStep`, maps through the same table. A soft `TextNewline` and a number prefix count flat offsets, and a dropped line counts none in the output, so `WordWrapping`, `TextLineNumbering` and `TextFiltering` move a box past each soft break, number and dropped line before it. A box on a dropped line has no image. `TextHighlighting` and `SelectionInverting` keep every flat offset, so a box passes through them unchanged.

Each decorator maps the caret in both of its forms, and its output selection is the flat form. `TextLineNumbering` puts the caret after the number of its line, and `TextFirstLine` draws no caret that is after the first line.

A decorator gets a key only when the stages after it return no operation for it. `SelectionInverting` returns `nothing` for a key. The other decorators read the key with `read_gesture` of their input block, so the answer is an edit at the caret of the input, or `nothing`. No decorator returns the key itself, so on `nothing` the stage before it gets the key. An edit beside an image writes the element list of the output, whose indices a decorator changes. So a decorator declines such a write (`is_text_element_write`), and the chain reads the key again against its input. `SyntaxToText` declines it too: an image in a syntax leaf, such as the picture of a Markdown, Book or reStructuredText document, is not edited through the syntax.

The added spans are the soft `TextNewline` of `WordWrapping` and the number prefix of `TextLineNumbering`. A soft newline before an image takes the style of a new run beside that image. They have no input, so a click on a number goes to the first character of the line. A space at a wrap stays at the end of the upper line, so every input character is in the output once.

`WordWrapping` must get the same `measure` as `TextToGraphics`, or the wrap points and the layout do not agree. Its reader also reads a key against the unwrapped input, so a Backspace across a soft break is an edit inside one span. An empty span stays one empty span with a segment of length 0, so a caret in an empty field maps through. `TextToGraphics` draws that caret one line high, and a line that holds only an empty span is one line high too. An empty line has a zero-width `SegmentCoordinate` where its caret stands, so Up and Down stop on it. The coordinate stays only on a line that draws no glyph, so the line-break spans of syntax text add none. `TextFiltering` and `TextHighlighting` keep the pattern in a `Cell`: a new pattern filters again, and `nothing` passes everything through. A line of `TextFiltering` ends at a `TextNewline`, and `TextHighlighting` matches inside one span only.

`SelectionInverting` is for a backend that draws no caret of its own. The console pipeline and `make_json_console_projection_example` end with it. In an SDL chain `TextToGraphics` already draws the caret, so the selection would show twice.

### Other projections

`PrimitiveToText` prints a `PrimitiveBool`, `PrimitiveNumber`, `PrimitiveString` or the type-in `PrimitiveInsertion` as a block of one span with no syntax leaf, so a string shows no quotes; the natural renderer draws every primitive that is no part of a syntax tree through it. A key whose text the number can not show makes a type-in (`make_number_edit_operation`), and `PrimitiveInsertionToText` draws the typed text in the style of the type that it parses as, red while it parses as none, and the placeholder of the type-in while it is empty. The keys of a type-in and of a Bool are document gestures in `PrimitiveToText.jl`: a key, Backspace and Delete edit the text of a type-in or make the value that it shows exactly, Enter makes the value that it parses as, and Escape drops the text; `t` makes a Bool true, `f` false, and Space switches it, and a key that would edit the text of a Bool does nothing. It maps both caret forms and a range `value{s:e}`. `ReferenceToText` and `ReferenceToHumanReadableText` print a `Reference` as coloured text, and their output has no selection. `TextToString` joins the spans into a plain `String`.

### Ranges through a projection

A range maps through a projection only when it lies in one span that maps to one field. `PrimitiveToText` maps it to `value{s:e}`, `WordWrapping` maps each end across a soft break, and the chat composer maps it to the value of its draft. The backward maps of `SyntaxToText` return `nothing` for a flat range, so a Shift key in a syntax view leaves the selection where it was.

### The theme

`TextTheme` holds what the text projections draw on their own: the font of a text
that no document styles (the line of a placeholder of the natural renderer), the
caret, the dormant caret and the width of the caret, the band under a selection,
live and dormant, and the radius of its corners, the texts of a boolean, a
number and a string that `PrimitiveToText` prints, and the color of a type-in
that is no value yet and the text of its placeholder. The fonts and the colors of a
text document stay as its author set them, so a scale of the font changes a text
that a domain styles from its theme, and not a text that a document styles.
`TextToGraphics(; measure, theme)` and the primitive leaves take the theme; with
none they draw the default values. The natural renderer gives them the scaled
`TextTheme` of its `Appearance`. `TextHighlighting`, `SelectionInverting` and
`TextLineNumbering` take their colors and fonts as keywords.

`ReferenceTheme` holds the font, the italic font and the colors of the tokens of a
reference that `ReferenceToText` and `ReferenceToHumanReadableText` draw: the
punctuation, a name, an index, a type, a projection and an unknown step. Each
projection holds all its values as one style field and reads it once at each
print. The inspector gives it the scaled theme of its `Appearance`.

## How it fits

The text slice depends on the kernel and on the collection, domain, primitive, projection, style and graphics slices. The syntax slice prints every leaf and node to it, so every domain with a syntax chain uses it. Widgets, the conversation view, the console backend and the undo view use it directly.

It registers no file type and no natural row. `@domain Text` makes the placeholder pair, and the three reference steps register their kind with the kernel.

## Design decisions

- **The caret is a flat offset.** A caret anchored to a span has two names at a span boundary, one for each direction of travel; a flat offset has one. See [plan/done/text-range-reference-flat-cursor.md](../../../../plan/done/text-range-reference-flat-cursor.md).
- **An inline image is one caret position,** as a word processor gives a picture set in line with text one character. Every reader of the caret space counts it 1, so a caret stands before and after it and a key can reach and delete it. See [plan/done/an-inline-image-is-one-caret-position.md](../../../../plan/done/an-inline-image-is-one-caret-position.md).
- **A box selection and a caret are two step types.** They hold the same data, but a motion key moves a caret and does not move a box. One type for both would make a selected element act as an editable caret.
- **The reader is split by what it reads.** What needs only the spans is a `@gestures` table on `TextBlock`, and the gesture help lists that same table. What needs pixels stays in `TextToGraphics`. See [projection-system.md](../../kernel/projection-system.md).
- **A key without a rule goes on.** The gesture table matches modifiers exactly, so a key that it does not bind gets `nothing` with no extra rule that returns it.
- **A line is a document, not a span with a `'\n'`.** A block of lines has no empty last line, and no caret lands in the indentation. `SyntaxToText` does not make lines yet; see [plan/pending/text-domain-kit.md](../../../../plan/pending/text-domain-kit.md).
- **Wrapping is a separate stage.** `TextToGraphics` only places spans, and `WordWrapping` before it changes the spans. A view without wrapping leaves the stage out.
- **Text has its own package.** It is not in one package with graphics and the backends. See [plan/done/extract-graphics-text-packages.md](../../../../plan/done/extract-graphics-text-packages.md).

## Usage

```julia
span  = TextString("Hello")                                        # default font and colour
span  = TextString("Hello", StyleFont("Ubuntu Mono", 24), color_default)
live  = TextString(() -> uppercase(document.name), StyleFont("Ubuntu Mono", 24), color_default)
block = TextBlock(TextString("Hello"), TextNewline(font = StyleFont("Ubuntu Mono", 24)),
                  TextString("world"))
lines = TextBlock(TextLine(TextString("a = 1")), TextLine(TextString("b = 2"); indentation = 2))
span.content = "New content"          # writes through the cell

projection = ChainingProjection(WordWrapping(measure = FontFileMeasure()),
                                TextToGraphics(measure = FontFileMeasure()))
```

- Examples: `text_example`, `plain_text_example`, `text_with_image_example`, the text layout examples of [Layout](#layout) (`text_layout_examples` and `text_spacing_examples`), `word_wrapping_example`, `line_numbering_example`, `text_gutter_example`, `text_folding_example`, `text_filtering_example` and `text_highlighting_example` in `example/platform/`. The atomic catalog has one document for each span type and for `TextLine`.
- Tests: `test_text()` for the documents and the gesture table, `test_text_to_graphics()`, `test_text_line_model()`, `test_inline_image_caret()`, `test_word_wrapping()`, `test_text_filtering()`, `test_text_first_line()`, `test_text_line_numbering()`, `test_text_highlighting()`, `test_selection_inverting()`, `test_text_gutter()` and `test_text_folding()` in `test/platform/`, and `test_text_range_selection()` in the umbrella suite.

## Limits

- A text of a lazy list has no gutter: `TextBlockToScrollLayout` draws only its lines.
- A caret that an edit or a search puts into a line that a fold hides does not open the fold.
- Outside a scroll pane, a text that wraps wraps at the whole width that it is offered, so its gutter makes it wider than the offer by the width of the gutter. A scroll pane offers the text the width beside the gutter.
- The gutter has no colors of its own in `TextTheme` yet: no background and no rule between it and the lines.
- An edit over a range that crosses two spans does nothing, also a range of text and an image.
- Through `SyntaxToText`, an image in a leaf is not edited: Backspace and Delete beside it make no element write.
- Through `WordWrapping`, a caret can not stand on an empty line between two `TextNewline`s: the backward map takes an offset in a gap to the nearest run.
- Through `WordWrapping`, Right does not move at the end of a line when a soft wrap puts an image at the start of the next line.
- At the end of a text, the block caret of `SelectionInverting` adds an inverted space, and Right there maps past the end.
- `TextColumnReferenceStep` has no gesture that makes it.
- No code in `source/` or `example/` uses `TextFirstLine`.
- In `text` and `text_with_image`, a walk with Left does not reach the start of the text. It also takes a different number of steps than a walk with Right. `formula` and `markdown_rendered` have the same fault. `NAV_LEFT_WALK_STALLS` in `test/projectured/editor/ExampleSweeps.jl` marks the four as broken; see [plan/pending/left-motion-stalls-on-introduced-text.md](../../../../plan/pending/left-motion-stalls-on-introduced-text.md).
- `run_example` with `text_filtering = true` or `text_highlighting = true` replaces the whole projection of the example. See [plan/pending/fix-text-configuring-run-example.md](../../../../plan/pending/fix-text-configuring-run-example.md) and [plan/pending/text-projection-config-into-document.md](../../../../plan/pending/text-projection-config-into-document.md).
