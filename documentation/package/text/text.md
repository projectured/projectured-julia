# Text domain

> **Kind:** design · **Status:** current · **Stands on:** [reference.md](../kernel/reference.md), [projection-system.md](../kernel/projection-system.md), [style.md](../style/style.md), [graphics.md](../graphics/graphics.md)

`ProjecturedText` holds styled text as a flat sequence of spans, and the projections that lay it out as graphics or change it on the way. Nearly every view reaches the screen through it, because `SyntaxToText` prints to it. This document says how the caret is addressed, how a key becomes an edit, and why the text decorators can map a caret in both directions.

<img width="396" alt="Text example" src="../../../asset/image/example/text.png">

## How it works

| Document | What it is |
| --- | --- |
| `TextBlock` | the container: `elements`, a `CellVector` of spans or lines |
| `TextString` | a span: `content`, `font`, `font_color`, `fill_color`, `line_color`, `padding` |
| `TextNewline` | a line break, with the same style fields |
| `TextSpacing` | a gap of `size` in `:pixel` or `:space` units |
| `TextGraphics` | a graphics document, such as an image, inline as one glyph |
| `TextLine` | one line of spans, with an `indentation` |

A `TextString` keeps `content` in a reactive `Cell`, because you type into it. `font` and `font_color` are an `ImmutableCell` by default: the style of a span is authored and not edited, so no glyph gets a dependency edge on it. Pass a `Cell` to make one of them reactive.

**A `TextLine` holds no break and implies one before itself.** So a block of `n` lines has `n - 1` breaks and no empty last line. Its `indentation` is a property of the line and not a span, so no caret can land in it. A span inside a line has the index path `[i, j]`, the type `SpanPath`, and the caret path gets a second `elements` step: `.elements[i].elements[j].content{k}`. A block must hold spans or lines, not both. Nothing enforces this, and no projection makes a mixed block.

`@domain Text` makes `TextNothing` and `TextInsertion`; see [domain.md](../domain/domain.md). Only `TextBlock` is a candidate of the insertion: `@insertion TextBlock` makes a block with one empty span and the caret in it. A span type has a required field, so it is not a candidate, and the text chain can not print a lone span at the root.

### The caret

**The canonical caret is a flat offset.** `TextRangeReferenceStep(start, stop)` counts characters over the whole block, from 0. `start == stop` is a caret, and it evaluates to a `Position`. A `TextNewline` and a `TextSpacing` count one character, and so do the indentation and the implied break of a `TextLine`. `get_flat_offsets` is the one function that counts the implied break. So a place between two spans has one offset, from whichever direction the caret came.

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

**The geometry-free half** is the `@gestures TextBlock` table in `source/text/TextDocument.jl`. It reads only `elements` and `selection`:

| Key | Edit |
| --- | --- |
| a printable key | insert the text at the selection |
| Backspace, Delete | delete one character, or the range |
| Left, Right | move the caret one character; a range collapses to its near end |
| Ctrl+Left, Ctrl+Right | move by a word |
| Ctrl+Home, Ctrl+End | go to the start or the end of the text |
| Shift with one of the six motion keys above | move one end of the range and keep the other |
| Ctrl+. | `ToggleCollapseOperation`, which the syntax stage resolves |

The table matches modifiers exactly. `KeyDown(:left;)` is plain Left, and Alt+Left is a different gesture. A key with no rule, such as Tab or Alt with an arrow, gets no operation, so it goes on to the syntax stage. A plain arrow on a whole-element selection also gets `nothing` from the motion rule.

**The geometry half** is the reader of `TextToGraphics`. It calls the table first through `_gesture_op`. If the table gives `nothing`, the reader uses its coordinate table for three kinds of input. Plain Home and End go to the ends of the visual line. Up and Down keep the nearest x. A mouse click places the caret. Shift with Home, End, Up or Down moves one end of the range in the same way. A click always makes a plain caret; `SyntaxToText` resolves Alt+click. A key that neither half uses gives `nothing` and never the raw event, so the next reader gets it.

A typed key makes a `ReplaceTextRangeOperation` on the flat range. `_lower_text_range` lowers it to a `ReplaceStringRangeOperation` on `.elements[i].content[s:e]` of one span, which the syntax stage and the domains read. A range that crosses two spans lowers to `nothing`. At the end, `splice_value!` changes the `content` of the span in place. On a `TextBlock` target it finds the span that holds the range, and on an empty block it adds a `TextString`.

### Layout

`TextToGraphics(; start_x, start_y, measure)` places the spans from left to right and starts a new line at a `TextLine`, a `TextNewline` or a `'\n'` in the content. It does not wrap. `measure(text, font)` returns `(width, height)`. It is required, and a backend gives its own, for example `measure_sdl_text`, or `measure_truetype_text` of [style.md](../style/style.md).

The IO map holds `char_to_coord`, one `SegmentCoordinate` for each drawn piece: its `span_path`, its character range, its pixel position, its font and its size. An inline `TextGraphics` is one character wide in the text and carries the size of the image. So a click on its left or right half puts the caret before or after it. The reader and the hit test downstream use this table. `TextToGraphics` also draws the caret and the selection rectangles; [graphics.md](../graphics/graphics.md) describes the output.

### The decorators

A decorator is a projection from `TextBlock` to `TextBlock`. You put it before `TextToGraphics` in a chain.

| Projection | What it does |
| --- | --- |
| `WordWrapping(; max_width, measure)` | breaks lines at word boundaries, at `ctx.available_width` when the context has one |
| `TextLineNumbering(; width, separator, font)` | puts a number span before each line |
| `TextFiltering(pattern; invert)` | keeps only the lines that match the pattern |
| `TextHighlighting(pattern; color)` | sets `fill_color` on each match |
| `SelectionInverting()` | shows the selection as inverse video in the span colours |
| `TextFirstLine()` | keeps the first line only |

**The shared design: a decorator never changes a character of its input.** It splits a span into pieces, restyles the pieces, adds a span that has no input, or drops whole lines. So each output span is either a piece of one input span at a known offset, or an added span. The IO map is a table of these pieces. `WrapSegment`, `HighlightSegment` and `SelectionSegment` have the same four fields. `TextFilteringIoMap.kept` holds the input index of each output span, and `TextFirstLineIoMap` holds the length of the kept prefix. The forward map, the backward map and the reader all read that table, and none of them searches the text to find where a caret goes.

A whole-element box, a `TextSpanReferenceStep`, maps through the same table. A soft `TextNewline` and a number prefix count flat offsets, and a dropped line counts none in the output, so `WordWrapping`, `TextLineNumbering` and `TextFiltering` move a box past each soft break, number and dropped line before it. A box on a dropped line has no image. `TextHighlighting` and `SelectionInverting` keep every flat offset, so a box passes through them unchanged.

Each decorator maps the caret in both of its forms, and its output selection is the flat form. `TextLineNumbering` puts the caret after the number of its line, and `TextFirstLine` draws no caret that is after the first line.

A decorator gets a key only when the stages after it return no operation for it. `SelectionInverting` returns `nothing` for a key. The other decorators read the key with `read_gesture` of their input block, so the answer is an edit at the caret of the input, or `nothing`. No decorator returns the key itself, so on `nothing` the stage before it gets the key.

The added spans are the soft `TextNewline` of `WordWrapping` and the number prefix of `TextLineNumbering`. They have no input, so a click on a number goes to the first character of the line. A space at a wrap stays at the end of the upper line, so every input character is in the output once.

`WordWrapping` must get the same `measure` as `TextToGraphics`, or the wrap points and the layout do not agree. Its reader also reads a key against the unwrapped input, so a Backspace across a soft break is an edit inside one span. `TextFiltering` and `TextHighlighting` keep the pattern in a `Cell`: a new pattern filters again, and `nothing` passes everything through. A line of `TextFiltering` ends at a `TextNewline`, and `TextHighlighting` matches inside one span only.

`SelectionInverting` is for a backend that draws no caret of its own. The console pipeline and `make_json_console_projection_example` end with it. In an SDL chain `TextToGraphics` already draws the caret, so the selection would show twice.

### Other projections

`PrimitiveToText` prints a `PrimitiveBool`, `PrimitiveNumber` or `PrimitiveString` as a block of one span with no syntax leaf, for a widget label or a form field. It maps both caret forms and a range `value{s:e}`. `ReferenceToText` and `ReferenceToHumanReadableText` print a `Reference` as coloured text, and their output has no selection. `TextToString` joins the spans into a plain `String`.

### Ranges through a projection

A range maps through a projection only when it lies in one span that maps to one field. `PrimitiveToText` maps it to `value{s:e}`, `WordWrapping` maps each end across a soft break, and the chat composer maps it to the value of its draft. The backward maps of `SyntaxToText` return `nothing` for a flat range, so a Shift key in a syntax view leaves the selection where it was.

## How it fits

`ProjecturedText` depends on the kernel, `ProjecturedCollection`, `ProjecturedDomain`, `ProjecturedPrimitive`, `ProjecturedProjection`, `ProjecturedStyle` and `ProjecturedGraphics`. `ProjecturedSyntax` prints every leaf and node to it, so every domain with a syntax chain uses it. Widgets, the conversation view, the console backend and the undo view use it directly.

It registers no file type and no natural row. `@domain Text` makes the placeholder pair, and the three reference steps register their kind with the kernel.

## Design decisions

- **The caret is a flat offset.** A caret anchored to a span has two names at a span boundary, one for each direction of travel; a flat offset has one. See `plan/done/text-range-reference-flat-cursor.md`.
- **A box selection and a caret are two step types.** They hold the same data, but a motion key moves a caret and does not move a box. One type for both would make a selected element act as an editable caret.
- **The reader is split by what it reads.** What needs only the spans is a `@gestures` table on `TextBlock`, and the gesture help lists that same table. What needs pixels stays in `TextToGraphics`. See [projection-system.md](../kernel/projection-system.md).
- **A key without a rule goes on.** The gesture table matches modifiers exactly, so a key that it does not bind gets `nothing` with no extra rule that returns it.
- **A line is a document, not a span with a `'\n'`.** A block of lines has no empty last line, and no caret lands in the indentation. `SyntaxToText` does not make lines yet; see `plan/pending/text-domain-kit.md`.
- **Wrapping is a separate stage.** `TextToGraphics` only places spans, and `WordWrapping` before it changes the spans. A view without wrapping leaves the stage out.
- **Text has its own package.** It is not in one package with graphics and the backends. See `plan/done/extract-graphics-text-packages.md`.

## Usage

```julia
span  = TextString("Hello")                                        # default font and colour
span  = TextString("Hello", font_ubuntu_monospace_regular_24, color_default)
live  = TextString(() -> uppercase(document.name), font_ubuntu_monospace_regular_24, color_default)
block = TextBlock(TextString("Hello"), TextNewline(font = font_ubuntu_monospace_regular_24),
                  TextString("world"))
lines = TextBlock(TextLine(TextString("a = 1")), TextLine(TextString("b = 2"); indentation = 2))
span.content = "New content"          # writes through the cell

projection = ChainingProjection(WordWrapping(measure = measure_truetype_text),
                                TextToGraphics(measure = measure_truetype_text))
```

- Examples: `text_example`, `plain_text_example`, `text_with_image_example`, `word_wrapping_example`, `line_numbering_example`, `text_filtering_example` and `text_highlighting_example` in `example/substrate/`. The atomic catalog has one document for each span type and for `TextLine`.
- Tests: `test_text()` for the documents and the gesture table, `test_text_to_graphics()`, `test_word_wrapping()`, `test_text_filtering()`, `test_text_first_line()`, `test_text_line_numbering()`, `test_text_highlighting()` and `test_selection_inverting()` in `test/substrate/`, and `test_text_range_selection()` in the umbrella suite.

## Limits

- An edit over a range that crosses two spans does nothing.
- `TextColumnReferenceStep` has no gesture that makes it.
- No code in `source/` or `example/` uses `TextFirstLine`.
- In `text` and `text_with_image`, a walk with Left does not reach the start of the text. It also takes a different number of steps than a walk with Right. `formula` and `markdown_rendered` have the same fault. `NAV_LEFT_WALK_STALLS` in `test/projectured/editor/ExampleSweeps.jl` marks the four as broken; see `plan/pending/left-motion-stalls-on-introduced-text.md`.
- `run_example` with `text_filtering = true` or `text_highlighting = true` replaces the whole projection of the example. See `plan/pending/fix-text-configuring-run-example.md` and `plan/pending/text-projection-config-into-document.md`.
