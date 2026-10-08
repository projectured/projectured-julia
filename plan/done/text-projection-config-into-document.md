# Hoist editable text-projection config into documents

> **Status (2026-10-08): DONE** on the branch `text-config-in-documents`,
> on top of `plain-value-form`, in the worktree `projectured-julia-plain-value-form`.
> Steps 1 to 7 are done. Not on main and not pushed.
> **Refreshed 2026-10-08.** The plan was written on
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
laid out as usual, and the bar drawn over it, through a `StackLayout` (step 4). It maps a
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

Checked in step 4: `AnchoredLayout` places a child only beside its target, so
the overlay is a `StackLayout`; and the vertical layout leaves a hidden bar out
of its list, so it takes no space.

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
2. ✅ **`HighlightedText` and `HighlightedTextToText`; `TextHighlighting` goes.**
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

   **Done 2026-10-08.** What the implementation found and decided:
   - **The recursion of the text is a text stage.** `HighlightedTextToText`
     prints `text` through the recursion that it gets, and needs a `TextBlock`
     back. So it sits in a text stage, `RecursiveProjection(TypeDispatching(
     HighlightedText => HighlightedTextToText(), TextBlock =>
     IdentityProjection()))`, and a graphics stage follows it. The view of step 4
     therefore gives the `HighlightedText` the row
     `ChainingProjection(<text stage>, <renderer>)`.
   - **The document `HighlightedText` subtypes `Document`, not `TextDocument`**,
     which is the type of the elements inside a block. It is declared in
     `TextDocument.jl`.
   - **Four helpers handle the step `text`** and serve step 3 as they are:
     `_strip_text_step`, `_forward_map_text`, `_backward_map_text` and
     `_read_text_operation`. A reader translates an operation across the
     segments, gives it to the reader of the IO map of the text, and puts the
     step `text` in front with `reroot_operation`.
   - `TextHighlighting.jl` moved to `HighlightedTextToText.jl` with `git mv`;
     its helpers `_highlight`, `_forward_map` and `_forward_flat` did not
     change. `TextHighlightingTest.jl` became `HighlightedTextToTextTest.jl`, and
     `test_text_highlighting` became `test_highlighted_text_to_text`, also in the
     umbrella suite.
   - `ObjectToWidgetTest.jl` used `TextHighlighting` only as an object with cell
     fields; it has a test-local struct of that shape now.
   - `InlineImageCaretTest.jl`: each entry of its two loops says how it wraps a
     block, and the checks read the block back. An edit of a wrapper names
     `.text.elements…`, so the check that it is an element write reads it
     without the step `text`.
   - **Not green between steps 2 and 5:** `ProjectionConfiguringTest.jl` still
     uses `TextHighlighting`, and step 5 rewrites it; the gallery branch
     `text_highlighting = true` fails when it runs, and step 4 replaces it.
   - `test_highlighted_text_to_text()` 86 pass, `test_inline_image_caret()` 261,
     `test_object_to_widget()` passes; `walk_printer_output` and
     `walk_repl_loop` report no error on the example `text_highlighting`; the
     naming guard passes.

3. ✅ **`FilteredText` and `FilteredTextToText`; `TextFiltering` goes.** The same,
   with `invert`, `TextFilteringTest.jl` (10 call sites), its example, and the
   other 2 call sites of `InlineImageCaretTest.jl`. And a `FilteredText` around a
   `HighlightedText`: the filter keeps the highlighted lines, and a caret and an
   edit map back through both.

   **Done 2026-10-08.** What the implementation found and decided:
   - **The helpers of step 2 serve as they are.** `FilteredTextToText` prints
     `text` through the recursion of its stage and uses `_forward_map_text`,
     `_backward_map_text` and `_read_text_operation`. The box and caret logic of
     the backward map moved into `_backward_map_kept`, which takes the kept
     table and the two blocks. `_filter`, `_make_filter_runs` and `_forward_map`
     did not change.
   - **`_effective_pattern` is gone**: `make_text_pattern` of step 1 takes its
     place, and a pattern that does not compile keeps every line.
   - **A filter around a highlight works with no new code.** The text stage
     holds both rows, the filter prints the `HighlightedText` through the
     recursion, and filters the block that the highlight gives. A caret maps
     back to `text.text…`, and an edit of a highlighted run writes the block.
   - `TextFiltering.jl` moved to `FilteredTextToText.jl` with `git mv`.
     `TextFilteringTest.jl` became `FilteredTextToTextTest.jl`, and
     `test_text_filtering` became `test_filtered_text_to_text`, also in the
     umbrella suite.
   - **Still not green until steps 4 and 5:** `ProjectionConfiguringTest.jl`,
     the gallery branches `text_highlighting` and `text_filtering`, and the
     comment in `GalleryWrapperProjectionExample.jl` name the old projections.
   - `test_filtered_text_to_text()` 37 pass, `test_highlighted_text_to_text()`
     86, `test_inline_image_caret()` 261, `test_object_to_widget()` passes;
     `walk_printer_output` and `walk_repl_loop` report no error on the examples
     `text_filtering` and `text_highlighting`; the naming guard passes.
4. ✅ **The view and the gallery.** The view document, its projection, which
   arranges the bar and the content by `overlaid`, and its `@gestures` table. A
   function of the examples makes the view and its projection, and takes the
   place of `make_text_configuring_projection`.
   The two branches of `Gallery.jl` use it, and `content_unwrap` there learns the
   fields of the view. The exports of `ProjecturedExample` follow.

   **Done 2026-10-08.** What the implementation found and decided. The choices
   are those of the implementation, except the caret, which decision 11 holds:
   - **The name is `FindBarView`**, a document of `WidgetDocument.jl` with the
     fields `bar`, `content` and `overlaid`. Its projection is
     `FindBarViewToWidget`, and its table and its three operations
     (`make_find_bar_show_operation`, `make_find_bar_hide_operation`,
     `make_find_bar_placement_operation`) are in `FindBarViewGestures.jl`.
   - **The projection follows `NavigatorToWidget`.** It prints no child: its
     output is a `VerticalLayout` whose list of children it computes from
     `visible` of the bar and `overlaid` of the view, and the row is
     `FindBarView => ChainingProjection(FindBarViewToWidget(),
     VerticalLayoutToGraphicsCanvas())`. A hidden bar is not in the list, so it
     takes no gap.
   - **The overlay is a `StackLayout`, not an `AnchoredLayout`.** The check of
     the design found that `compute_anchored_positions` places a child only
     beside its target (`:above`, `:below`, `:left`, `:right`), never inside it.
     A `StackLayout([content, row])` draws the row over the top left corner of
     the content, and gives a click to the row first.
   - **The button of the placement is made by the projection of the view**,
     beside the bar, because `overlaid` is a field of the view, as the chevron
     of the card is drawn by the card. Its press is a per-instance gesture
     binding of the `WidgetButton`, which reads `overlaid` when the press comes.
     Its label says where a press puts the bar: "Over" or "Above".
   - **The view keeps a dormant selection** (`has_dormant_selection`), so the
     side that the caret leaves keeps its caret.
   - **Ctrl+F and Escape are `override` rules.** The reader of the view gives a
     key that the layout answered to the table as a claimed key, as
     `NavigatorToWidget` does.
   - **The caret in a field is a path in the document (decision 11).** Ctrl+F
     writes `bar.content.children[2].object.pattern{5}`: through the field of
     the pattern in the bar to the end of the string. The printers map it
     forward: `ObjectFieldToWidget` puts it under the slot of the widget that it
     made (`content`), and `ObjectFieldToValue` maps
     `object.<path of the field>{start:stop}` to the same flat range of the
     value; the way back takes the same steps. Before, the caret was a path
     that the two projections introduced, which names their instances, so no
     table of a document could build it. `make_object_field_range_reference`
     and `find_object_field_range` in `ObjectField.jl` make and read the path.
   - **A bare `ObjectField` is a focus stop** (`is_focusable_document`), and a
     whole selection of the field is a whole selection of its widget. Ctrl+F
     takes the first stop of the bar and, when it is a field with a text, puts
     the caret at the end of the text. Tab now reaches the fields of a
     hand-laid form, which it did not before.
   - **Escape links back the dormant caret of the content.** The path to the
     pattern walks through the object of the field, which is the content, and
     writes the selection of that object; the text block below it keeps the
     caret of the text as a dormant selection. So the rule takes the dormant
     selection of the content, or of the first document below it that keeps
     one (`search_references`), and falls back to the whole content.
   - Facts: a whole selection of a text box, which Tab gives, takes no key, also
     for a plain `WidgetText`; the keys of the find bar do not need it.
   - Checked through an editor (`build_editor`, `HeadlessBackend`): the first
     Ctrl+F puts the caret at the end of the pattern; keys and Left write the
     pattern at the caret and the highlight follows; Escape hides the bar and
     puts the caret back in the text; Ctrl+F puts it back in the field; Tab goes
     from the pattern to the next field; the button switches to the overlay,
     and the keys work there. The gallery (`make_example_editor` with
     `text_highlighting` and with `text_filtering`, in `environment/all`): the
     bar draws, Ctrl+F, a key and Escape work, and the filter keeps no line for
     a pattern that matches none.
   - `test_object_field_to_widget()`, `test_widget_value_slot()`,
     `test_object_field_to_syntax()`, `test_object_to_widget()`,
     `test_widget_text_editing()`, `test_widget_button_behavior()`,
     `test_settings_tab()`, `test_window_wrappers()` and
     `test_highlighted_text_to_text()` pass; `walk_printer_output` and
     `walk_repl_loop` report no error on the two examples of the field; the
     naming guard and `test_platform_layering()` pass.
   - **Still not green until step 5:** `ProjectionConfiguringTest.jl` uses the
     removed projections. The tests of the view are step 5.
   - For step 6: `widget.md` describes the caret of a plain value in a text
     box, and part C of the form plan has no section yet; the caret of a field
     goes into the documents with step 9 of
     [a-form-edits-a-plain-value.md](a-form-edits-a-plain-value.md).
5. ✅ **The tests of the view.** `ProjectionConfiguringTest.jl` becomes a test of
   the view, through an editor: typing in the pattern highlights again as a
   person types, the caret stays in the field, undo takes a key back, a press on
   a checkbox changes the matches, a press in the text puts a caret in the text.
   The `@test_broken` of typing becomes a `@test`. And the states: Ctrl+F shows
   and expands the bar and puts the caret in the pattern, Escape hides it and
   puts the caret back in the text, a hide keeps the collapse and the placement,
   the button switches the placement, and the text keeps its place under an
   overlay bar.

   **Done 2026-10-08.** `ProjectionConfiguringTest.jl` moved to
   `FindBarViewToWidgetTest.jl` with `git mv`, and `test_projection_configuring`
   became `test_find_bar_view_to_widget`, also in the umbrella suite. The test
   drives a view through `build_editor` and a `HeadlessBackend`, with the rows
   of the gallery, and 48 assertions pass in seven groups: the bar above and
   over the text (the text keeps its place under the overlay bar); a press in
   the text; Ctrl+F and Escape; typing and Backspace in the pattern; a press on
   the checkbox of the case; a hide that keeps the collapse and the placement;
   and Ctrl+Z, which takes back a key in the pattern and keeps no step for
   `visible`, `overlaid` and `collapsed`. The `@test_broken` of typing is gone,
   so the platform suite counts one broken test less.
   - Found: a glyph is drawn from its origin, and the box of the chevron starts
     a few pixels inside it, so the test presses 4 pixels inside the glyph.
   - Found: a press on the overlay bar where no control answers, such as its
     padding, went on to the text under it, because a `StackLayout` gives a
     press to the next child when the top one declines. Question Q4, answered
     by decision 12: the reader of `WidgetCardToGraphicsCanvas` answers a plain
     left click on the card that nothing inside it uses with
     `DoNothingOperation`. `test_widget_card_fold()` has a group for it, and
     the view test a group "a press on an empty part of the bar over the text
     keeps the caret", so it has 50 assertions. `widget.md` describes the solid
     card under "A press goes by coordinate".

6. ✅ **Retire `ProjectionConfiguringProjection`.** Delete
   `ProjectionConfiguring.jl`, its include, its export, and its mentions in the
   six documents and in the header of `ObjectToWidget.jl`. `ObjectToWidgetTest.jl`
   takes another fixture for its 6 uses of `TextHighlighting`, or part D
   rewrites them. `ProjecturedPlatform` loses the exported names
   `ProjectionConfiguringProjection`, `TextHighlighting` and `TextFiltering`
   (with their IO maps); it already takes the version 0.2.0 at its next release,
   and this change falls into that step.

   **Done 2026-10-08.** `ProjectionConfiguring.jl` is deleted with its include
   and its export. The header of `ObjectToWidget.jl` names it no more, and
   `ObjectToWidgetTest.jl` had its own fixture since step 2. The documents
   `projection.md`, `higher-order-projections.md`, `system-anatomy.md`,
   `projection-system.md`, `engineer-tour.md`, `widget.md` and `text.md` name
   the new documents and projections: `widget.md` describes `FindBarView` and
   lists the limit of Q4, `text.md` describes `HighlightedText` and
   `FilteredText`, and `projection-system.md` counts `HighlightedTextToText` and
   `FilteredTextToText` as domain-to-domain, because each takes a document of its
   own. `ProjecturedPlatform` loses the exported names
   `ProjectionConfiguringProjection`, `ProjectionConfiguringIoMap`,
   `TextHighlighting`, `TextHighlightingIoMap`, `TextFiltering` and
   `TextFilteringIoMap`. No source of omnet-julia or inet-julia names them; their
   generated `PrecompileStatements.jl` name `TextFilteringModule.TextFiltering`,
   a module that main does not have either. `test_find_bar_view_to_widget()`,
   `test_object_to_widget()`, `test_highlighted_text_to_text()`,
   `test_filtered_text_to_text()`, `test_platform_layering()` and the naming
   guard pass.

7. ✅ Move this plan to `plan/done/`, and go on with step 7 (part D) of
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

11. **The caret in a field is a path in the document, and the printer maps it
    forward** (asked during step 4). Ctrl+F writes the selection to the pattern,
    through the field in the bar; the old selection stays dormant where the two
    paths diverge, and Escape links it back. Rejected: a caret that the
    projections of the field introduce, which no table of a document can build;
    a whole selection of a text box that takes a key.

12. **A card is a solid surface** (question Q4, asked during step 5). A plain
    left click on a `WidgetCard` that nothing inside it uses ends at the card,
    so a press on the overlay bar does not reach the text under it. A right
    click and an Alt+click go on, to the menus and to a whole selection.
    Rejected: keep the press that falls through as a known limit; a setting of
    `StackLayout` that makes its top child take every press inside its box.

## Open questions

None. Q3 and Q4 are answered by decisions 11 and 12.
