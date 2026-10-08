# Hoist editable text-projection config into documents

> **Status (2026-10-08): IN PROGRESS** on the branch `text-config-in-documents`,
> on top of `plain-value-form`, in the worktree `projectured-julia-plain-value-form`.
> Step 1 is done. **Refreshed 2026-10-08.** The plan was written on
> 2026-08-12 and refreshed on 2026-10-08 against the code of the branch
> `plain-value-form`. It builds on part C of
> [a-form-edits-a-plain-value.md](a-form-edits-a-plain-value.md): a widget slot
> that holds an `ObjectField`, and the table of
> `make_object_field_widget_dispatch`. So it is implemented on a branch on top
> of `plain-value-form`. Step 7 (part D) of that plan waits for this plan,
> because part D would otherwise have to change `ProjectionConfiguringProjection`.
> Every question is answered, and the owner asked for the implementation on
> 2026-10-08.

## Goal

Retire `ProjectionConfiguringProjection` (pcp). Today the editable parameters of
`TextHighlighting` and `TextFiltering` (`pattern`, `case_insensitive`,
`invert`) live in cells on the projection structs. A projection is no document,
so it has no `selection`: the controls that pcp draws from those structs have no
place for a caret. That is why pcp swallows every path under its control slot
([ProjectionConfiguring.jl](../../source/platform/widget/ProjectionConfiguring.jl),
rule 3 of its reader), and why typing in the bar is `@test_broken`
([ProjectionConfiguringTest.jl:168](../../test/platform/projection/ProjectionConfiguringTest.jl#L168)).

After this plan the parameters are fields of a document. Selection, undo,
serialization and versioning then apply to them, because an editable parameter
and a field of the document are the same thing.

## What the code does now

Facts from the code on 2026-10-08:

- **The highlight and the filter are pure functions already.** `_highlight(text,
  pattern, color)` ([TextHighlighting.jl:89](../../source/platform/text/TextHighlighting.jl#L89)),
  `_filter(text, pattern, invert)` and `_effective_pattern(value,
  case_insensitive)` ([TextFiltering.jl:51-57](../../source/platform/text/TextFiltering.jl#L51-L57))
  take no projection. So step 1 of the plan of 2026-08-12 is done. The mappers
  and the readers take the projection and its IO map.
- **A pattern string is always the source of a regular expression.**
  `_effective_pattern` calls `Regex(s)`, with the flag `i` when
  `case_insensitive` holds. An empty string gives no pattern.
- **A pattern that does not compile throws.** `Regex("dolor(")` raises an error
  in the computation of the highlight, with no `try`. While a person types a
  regular expression, most prefixes do not compile.
- **pcp has these users:**
  - the gallery, `run_example(...; text_highlighting = true)` and
    `text_filtering = true` ([Gallery.jl:258-265](../../example/projectured/Gallery.jl#L258-L265));
  - `make_text_configuring_projection`
    ([GalleryWrapperProjectionExample.jl:78-93](../../example/projectured/GalleryWrapperProjectionExample.jl#L78-L93)),
    exported twice from `ProjecturedExample`;
  - `ProjectionConfiguringTest.jl`, six testsets, one `@test_broken`;
  - the export of `WidgetModule`, and six documents: `widget.md`,
    `projection.md`, `higher-order-projections.md`, `projection-system.md`,
    `engineer-tour.md` and `system-anatomy.md`;
  - the header of `ObjectToWidget.jl`, which says that pcp uses it.
- **pcp also shows and hides its bar:** Ctrl+F toggles it and Escape hides it,
  with a write that is marked as view state.

## Design

### The documents

Two documents of the text slice. The names say what a person sees: a text with
its matches marked, and a text with only its matching lines.

```julia
@document struct HighlightedText
    text::Any                 # the text whose matches are highlighted
    pattern::String
    regex::Bool               # the pattern is a regular expression, else literal text
    case_insensitive::Bool
end

@document struct FilteredText
    text::Any                 # the text whose matching lines stay
    pattern::String
    regex::Bool
    case_insensitive::Bool
    invert::Bool              # keep the lines that do not match
end
```

`case_insensitive` and `invert` keep the names of `TextHighlighting` and
`TextFiltering`. The colour of a highlight is a look, not data, so it stays a
setting of the projection, from the theme.

### The pattern

One function of the text slice makes the pattern from the fields:

- `regex` false: the text is escaped, so `a.b` and `f(x)` match as written.
- `case_insensitive`: the flag `i`.
- An empty pattern, and a pattern that does not compile, give no pattern, so
  the text shows no highlight and keeps every line. No error leaves the
  computation.

This function takes the place of `_effective_pattern`, which goes with
`TextFiltering`.

### The projections

`HighlightedTextToText` and `FilteredTextToText`, in the text slice. Each uses its
own input: the recursion sends a `HighlightedText` to `HighlightedTextToText` by
its type, and the fields of that node are the configuration. No projection looks
up a configuration anywhere else.

Each prints `doc.text` through the recursion first, and then highlights or
filters the `TextBlock` that comes back, with the pattern computed from the
fields of the document, inside a cell, so a write of a field highlights or
filters again. The code of `TextHighlighting` and `TextFiltering` moves into the
new projections, and the two old projections go (decision 10): the highlight and
the filter of the spans, the table of segments or of kept elements, the mappers
and the readers. So the wrappers nest, as the projections of today chain:

```julia
FilteredText(text = HighlightedText(text = block, pattern = "dolor", …),
             pattern = "^a", regex = true, …)   # filters the highlighted text
```

A reference of the document starts with the step `text`. On the way forward the
mappers take it off, map the rest through the child of `text`, and then through
the highlight or the filter. On the way back they go the other way and put the
step `text` back.

### The scope

- **Only the subtree in `text`.** The bar, the rest of the document and other
  panes are outside it.
- **Only text.** The child of `text` must give a `TextBlock`; another document
  there is drawn through the recursion, and its output is not highlighted.
- **The rules of today stay.** A highlight matches inside one span, so a match
  can not cross a change of style. A filter keeps or drops whole lines, split at
  each `TextNewline`, and a line matches on the joined strings of its spans.
- **The wrapper is part of the document.** To highlight a text, the document
  wraps it: each path in the text gets the step `text` in front, and a save
  keeps the pattern. That is what the decision of 2026-08-12 wanted: the
  configuration is data.
- **A search over a whole document is another feature.** `SearchingProjection`
  walks any document and collects the objects whose string field matches; it
  gives a list of matches, not marks in place.

`TextHighlighting` and `TextFiltering` go (decision 10). A fixed highlight, such
as "TODO" in every text, is a `HighlightedText` with a fixed pattern and no bar,
and a pattern that lives outside the document is a field of the wrapper that
holds a computed cell. `WordWrapping`, `TextFirstLine` and `TextLineNumbering`
stay projections, because nobody edits their parameters: a parameter that a
person edits is data of the document.

### The view

The bar is a form of the document's own fields, made with part C, in a
collapsible `WidgetCard` titled "Find" (or "Filter"). The view is a small
document (working name `BarView`; the step chooses the name by the naming rules)
that holds two authored children and one state:

```julia
highlighted = HighlightedText(text = block, pattern = "dolor", regex = false,
                              case_insensitive = false)
bar = WidgetCard(; title = WidgetLabel("Find"), collapsible = true, content =
    FormLayout([(WidgetLabel("Find"),               ObjectField(highlighted, "pattern")),
                (WidgetLabel("Regular expression"), ObjectField(highlighted, "regex")),
                (WidgetLabel("Ignore case"),        ObjectField(highlighted, "case_insensitive"))]))
view = BarView(bar = bar, content = highlighted, overlaid = false)
```

**Three states, each on its own** (decision 9):

| State | Field | Where |
| --- | --- | --- |
| shown or hidden | `visible` | the card (exists) |
| expanded or collapsed | `collapsed` | the card (exists; its chevron changes it) |
| displaced or overlay | `overlaid` | the view document (new) |

All three are view state, so a history keeps no step for them, and a hide keeps
the other two: a bar that shows again is as it was. The projection of the view
only arranges its two children by `overlaid`. Displaced: the bar above the
content, in a vertical layout, so the content moves down. Overlay: the content
laid out as usual, and the bar drawn over it, through `AnchoredLayout`. It maps a
path of the arrangement back to the field `bar` or `content` of the view, and
back again.

**The keys** are a `@gestures` table of the view document. A key that the part
under the caret does not take reaches that table, as a key reaches the table of
the navigator ([NavigatorToWidget.jl:281](../../source/platform/navigator/NavigatorToWidget.jl#L281)):

- **Ctrl+F**: the bar is shown and expanded, and the caret goes into the field of
  the pattern. The placement stays.
- **Escape**, with the caret in the bar: the bar is hidden, and the caret goes
  back to the content. Its collapse and its placement stay.
- **A press on the chevron** of the card: collapsed or expanded (exists).
- **A button on the bar**: displaced or overlay.

The projection of the whole view is one recursion: the layout rows, the table
of `make_object_field_widget_dispatch`, the row of the view document, and
`HighlightedText => ChainingProjection(HighlightedTextToText(), <the text renderer>)`.

- **A key in the bar** is an ordinary write on a cell field of the document, so
  undo works, and the highlight computation reads that cell.
- **The caret of the bar** is in the `ObjectField` of the bar, which is a node of
  the document, so the selection chain reaches it and it lasts across prints.
- **A caret in the text** maps back through `HighlightedTextToText` to a path
  that starts `text`, so it lives in the document too.

The owner chose an authored view on 2026-10-08 (decision 8) and the three states
with these keys (decision 9).

To check in step 4: `AnchoredLayout` places a child beside a target, and a place
inside a corner of the content may be missing; and a vertical layout gives no
space to a hidden child, which a split pane may not.

## Steps

Each step is one commit, on a branch on top of `plain-value-form`. Run the test
of the step, not `test_all()`.

1. ✅ **The pattern.** The function that makes the pattern from the fields.
   Tests: literal text with the characters of a regular expression, a regular
   expression, the flag for case, an empty pattern, and a pattern that does not
   compile.

   **Done 2026-10-08.** `make_text_pattern(pattern, regex, case_insensitive)` in
   `source/platform/text/TextPattern.jl`, exported from `TextModule`. Literal
   text gets a backslash before each of `\^$.|?*+()[]{}`. A pattern that does not
   compile throws an `ErrorException` in `Regex`, and the function answers
   `nothing` for exactly that exception. `test_text_pattern()` 14 pass, in
   `test/platform/document/TextPatternTest.jl`.
2. ⬜ **`HighlightedText` and `HighlightedTextToText`; `TextHighlighting` goes.**
   The code of `TextHighlighting.jl` moves into the new projection, which reads
   its configuration from its input and handles the step `text`.
   `TextHighlightingTest.jl` becomes the test of the new projection (10 call
   sites), with these cases besides its own: the highlights follow a write of
   each field; a caret in the text maps to a path that starts `text`, and back;
   an edit of the text writes the text of the document; two highlighted texts in
   one document each follow their own fields. The example
   `TextHighlightingProjectionExample.jl` and its document become a
   `HighlightedText`, and `InlineImageCaretTest.jl` wraps the text in one where
   it chained the projection (2 call sites).
3. ⬜ **`FilteredText` and `FilteredTextToText`; `TextFiltering` goes.** The same,
   with `invert`, `TextFilteringTest.jl` (10 call sites), its example, and the
   other 2 call sites of `InlineImageCaretTest.jl`. And a `FilteredText` around a
   `HighlightedText`: the filter keeps the highlighted lines, and a caret and an
   edit map back through both.
4. ⬜ **The view and the gallery.** The view document, its projection, which
   arranges the bar and the content by `overlaid`, and its `@gestures` table. A
   function of the examples makes the view and its projection, and takes the
   place of `make_text_configuring_projection`.
   The two branches of `Gallery.jl` use it, and `content_unwrap` there learns the
   fields of the view. The exports of `ProjecturedExample` follow.
5. ⬜ **The tests of the view.** `ProjectionConfiguringTest.jl` becomes a test of
   the view, through an editor: typing in the pattern highlights again as a
   person types, the caret stays in the field, undo takes a key back, a press on
   a checkbox changes the matches, a press in the text puts a caret in the text.
   The `@test_broken` of typing becomes a `@test`. And the states: Ctrl+F shows
   and expands the bar and puts the caret in the pattern, Escape hides it and
   puts the caret back in the text, a hide keeps the collapse and the placement,
   the button switches the placement, and the text keeps its place under an
   overlay bar.
6. ⬜ **Retire `ProjectionConfiguringProjection`.** Delete
   `ProjectionConfiguring.jl`, its include, its export, and its mentions in the
   six documents and in the header of `ObjectToWidget.jl`. `ObjectToWidgetTest.jl`
   takes another fixture for its 6 uses of `TextHighlighting`, or part D
   rewrites them. `ProjecturedPlatform` loses the exported names
   `ProjectionConfiguringProjection`, `TextHighlighting` and `TextFiltering`
   (with their IO maps); it already takes the version 0.2.0 at its next release,
   and this change falls into that step.
7. ⬜ Move this plan to `plan/done/`, and go on with step 7 (part D) of
   [a-form-edits-a-plain-value.md](a-form-edits-a-plain-value.md).

## Decisions

The owner decided these on 2026-08-12:

1. **Retire `ProjectionConfiguringProjection`.** An editable parameter of a
   projection lives on a field of a document, not on a projection struct.
   Rejected then: keep the projection and fix the caret another way (the
   configuration stays outside the document); keep both mechanisms (two ways to
   do one thing); defer the call (four plans stay blocked).
2. **Keep `TextHighlighting` and `TextFiltering`** for the uses that edit no
   parameter (path 1). Rejected then: route every use through the documents
   (path 2), about 40 test call sites for no gain. Replaced on 2026-10-08 by
   decision 10.

The owner decided these on 2026-10-08:

3. **The names are `HighlightedText` and `FilteredText`**, with the wrapped text
   in the field `text`. Rejected: `HighlightedContent` and `FilteredContent`,
   because the highlight works only on text and `Content` says nothing.
4. **The pattern is a `String`, and a field `regex` chooses** between a regular
   expression and literal text, as the find bar of an editor does. Rejected:
   the string is always a regular expression, as today.
5. **The colour of a highlight stays in the theme of the projection**, because
   it is a look and not data. Rejected: a field of the document, as the plan of
   2026-08-12 had it.
6. **The bar is a form of the document's own fields**, made with part C of
   [a-form-edits-a-plain-value.md](a-form-edits-a-plain-value.md). Rejected: a
   bar that `ObjectToWidget` makes, as the plan of 2026-08-12 had it.
7. **This plan comes before part D** of that plan.
8. **The view is an authored document** (question Q1): a split pane that holds a
   form of the document's own fields and the wrapper itself, which the caller
   builds. The fields of the bar are nodes of the document, so the caret of the
   bar is a real path in it. Rejected: a composer projection that makes the bar
   and maps its caret to the path `.pattern{k}` of the document, which needs a
   caret mapping of its own.
9. **The bar has three states, each on its own** (question Q2): shown or hidden
   (`visible` of the card), expanded or collapsed (`collapsed` of the card), and
   displaced or overlay (`overlaid` of the view document). All three are view
   state. Ctrl+F shows and expands the bar and puts the caret in the pattern;
   Escape in the bar hides it and puts the caret back; the chevron collapses
   and expands; a button switches the placement. The keys are a `@gestures`
   table of the view document. So decision 8 holds with a small view document:
   it holds the authored bar and content, and its projection only arranges them.
   Rejected: a collapsible card alone with no keys; one field with the four
   values hidden, collapsed, expanded and overlay, which forgets the collapse
   and the placement at a hide.
10. **`TextHighlighting` and `TextFiltering` go too** (path 2), and their code
    moves into the new projections. On 2026-10-08 nothing in `source/`, in
    omnet-julia or in inet-julia used them; only two examples, the gallery
    through pcp, and tests did. Their one advantage, a pattern from outside the
    document, is also a field of the wrapper that holds a computed cell. The
    call sites: 10 + 10 in their own tests, which become the tests of the new
    projections, 4 in `InlineImageCaretTest.jl`, 6 in `ObjectToWidgetTest.jl`,
    6 in `ProjectionConfiguringTest.jl`, which this plan rewrites anyway, and 2
    examples. Rejected: keep them beside the documents (path 1), two ways to do
    one thing, and the question how the two share their code.

## Open questions

None on 2026-10-08. A step that meets a new question records it here.
