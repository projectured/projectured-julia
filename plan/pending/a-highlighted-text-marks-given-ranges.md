# A highlighted text marks ranges that a caller gives

> **Kind:** plan · **Status:** pending, design, 2026-10-09. The owner chose to
> extend `HighlightedText` itself (Q-7.2-5 of the omnet plan
> `legacy-simulation-catalog-implementation.md`). Three questions are open
> (section 6); no step is started.

## 1. The goal

A domain that reads a text that a person types, such as the filter expression
of a result selection, shows the kind of each word in its colour and marks an
error at its place, in the text that the person edits. It gives the ranges and
their colours; the text slice splits the text, draws it and keeps it editable.
There is one split and one offset table for a pattern and for given ranges.

## 2. The facts

1. `HighlightedText(; text, pattern, regex, case_insensitive)` finds its ranges
   itself: one pattern, run over the content of each span with `eachmatch`. A
   caller can not give a range. A word whose kind depends on its neighbours,
   such as a property before `=~`, and an error whose place comes from a parse,
   are no pattern.
2. `HighlightedTextToText(color)` sets one colour, the background
   (`fill_color`), on every match. The colour is a parameter of the projection,
   so two nested highlights on one row get the same colour. The glyphs keep
   their colour.
3. It skips a match of no width, and a match stays inside one span.
4. What it does well stays: it splits the spans of an editable text, inserts no
   character, and keeps a table of offsets (`HighlightSegment`), so a caret and
   an edit map through it. `WordWrapping` and `SelectionInverting` split the
   same way.
5. A position in a text is a flat offset: `TextRangeReferenceStep(start, stop)`
   counts characters from 0 over the whole text of a block, and a break before
   a line counts one. A block is moving to lines only
   (`a-text-block-holds-only-lines.md`); the flat offset keeps its values there.
6. The `ColorTheme` has a role for each kind of token (`keyword`, `field`,
   `string_literal`, `number_literal`, `operator`, `punctuation`, …) and for a
   status (`error_text`, `error_tint`, `warning_text`, …). A theme names a
   colour as a `ThemeColor`: a `ColorRole`, a `PaletteColor` or a fixed
   `StyleColor`. A role resolves through the appearance (`resolve_theme_color`).
7. A span carries `line_color`, but `TextToGraphics` draws no line under a
   span.
8. `HighlightedText` draws only through a table of rows that a caller builds
   (the examples, the find bar of the gallery); the natural renderer has no row
   for it.

## 3. The design

### D1. A field `marks`

```julia
HighlightedText(; text, pattern = "", regex = false, case_insensitive = false,
                marks = TextMark[])
```

`marks` is data of the document, as the pattern is. A domain fills it, most
often as a cell that it computes from the text, so a key that changes the text
changes the marks.

```julia
TextMark(start, stop; text = nothing, surface = nothing)
```

- `start`, `stop`: a range of flat offsets, counted as the flat caret counts
  them (fact 5): from 0, `stop` excluded.
- `text`: the colour of the glyphs in the range, a `ThemeColor`, or `nothing`.
- `surface`: the colour behind the range, a `ThemeColor`, or `nothing`.

A word of a language names a role of the colour theme, for example
`TextMark(0, 18; text = ColorRole(:field))`; an error names two, for example
`TextMark(19, 21; text = ColorRole(:error_text), surface = ColorRole(:error_tint))`.

### D2. One split for the pattern and the marks

The split points are the edges of the matches and of the marks. Each piece takes
the colour of its glyphs from the last mark that covers it and gives a `text`
colour, and keeps its own colour otherwise. Its background is the background of
a match where a match covers it, else the `surface` of the last mark that gives
one, else its own. So a match of a search stays visible over a mark (Q2).

A mark with `start == stop` draws nothing. A mark past the end of the text is
cut at the end. The pattern keeps its rules: a match of no width is skipped, and
a match stays inside one span. A mark can cross spans and lines: each span takes
the part of the mark inside it.

### D3. From flat offsets to the pieces of each span

The projection walks the spans of the block in order, with the flat offset where
each span starts (a break before a line counts one), and gives each span the
parts of the marks inside it, as offsets of the span. The pieces and the offset
table are made as they are now. No character is inserted or removed, so the
mapping of a caret, of a range and of an edit does not change.

### D4. The colours of a mark

`HighlightedTextToText(; theme, color, appearance)`: `appearance` resolves a
`ColorRole` and a `PaletteColor` of a mark (`resolve_theme_color`); a fixed
`StyleColor` is used as it is. With no appearance, a default `Appearance()`
resolves them. The colours are resolved inside the computation that splits, so
the marks of each print use the appearance of the projection.

### D5. What does not change

The reader, the reference maps and the nesting with `FilteredText`. A row of a
caller passes `appearance` when it has one; a row with none keeps working.

## 4. The steps

1. ⬜ `TextMark`, the field `marks` and its default, the split of D2 and D3 for a
   block of spans and a block of lines, and `appearance` (D4).
2. ⬜ Tests in `HighlightedTextToTextTest.jl`: a mark colours glyphs; a mark and a
   match meet; a mark crosses two spans and a line; a mark past the end; a caret
   round trip and an edit through a marked piece; the marks follow a change of
   their cell.
3. ⬜ The docstring of `HighlightedText`, and the guide of the text slice.
4. ⬜ omnet (step 7.2d): the box of a result filter draws its text as a
   `HighlightedText` whose marks come from `collect_filter_tokens` (property →
   `:field`, operator → `:operator`, keyword → `:keyword`, pattern →
   `:string_literal`, parenthesis → `:punctuation`) and from
   `get_filter_error_place` (`:error_text` on `:error_tint`).

## 5. Not in this plan

- A line under a range: a span carries `line_color`, but `TextToGraphics` draws
  no line (fact 7).
- A tooltip with the message of a mark.
- A font of a mark, such as a bold keyword.
- A row of the natural renderer for `HighlightedText` (fact 8).

## 6. Questions to the owner

- **Q1, the shape of a mark.** (a) Two colours, each a `ThemeColor` (D1).
  (b) One role symbol, which the text theme maps to a style from a closed set
  (`:error`, `:warning`, and the kinds of a word). My recommendation is (a): the
  colour theme has a role for each kind of word and for each status already,
  and a `ThemeColor` is how every theme names a colour.
- **Q2, where a match and a mark meet.** (a) The background of the match wins,
  and the glyphs keep the colour of the mark (D2). (b) The mark wins. My
  recommendation is (a): a person who searches must see each match.
- **Q3, the error.** (a) The glyphs in the colour of an error on a tint, now;
  a line under the range later, with its drawing in `TextToGraphics`. (b) The
  line now. My recommendation is (a).
