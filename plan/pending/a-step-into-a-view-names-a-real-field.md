# A step into a view names a real field

**Status:** pending, written on 2026-11-17, not approved, nothing built.

This plan is point 1 of the order in section 13.3 of
`plan/tentative/content-and-view-for-the-whole-project.md`. The design is
`documentation/design/content-and-view.md`. The plan makes the type `View`, puts
the families of views below it, and removes the field step that a view sends to
its content. Each path into the content of a view then has the step `.viewed`.
The plan lands nothing and pushes nothing: it ends with a request to land.

## The problem

A view answers a step to a field that it does not have with that field of its
content. So a step on a view does not mean what it says, and other code that
reads the step as a real step can break.

```julia
view = JsonStringView(JsonString("abc"))

# now
@reference(view, value{2})          # reads view.viewed.value: the view has no field `value`
view.selection                      # .value{2}
text_view.selection                 # {3}: a place in the text, as a step on the view

# after this plan
@reference(view, viewed.value{2})   # each step names a real field
view.selection                      # .viewed.value{2}
text_view.selection                 # .viewed{3}
@reference(view, value{2})          # does not evaluate: a JsonStringView has no field `value`
```

The types that are views have no common type:

```julia
# now
abstract type ContentView <: Document end
abstract type WidgetDocument <: Document end

# after this plan
abstract type View <: Document end
abstract type ContentView <: View end       # a view of one content: it has `viewed`
abstract type WidgetDocument <: View end    # the same for the layout, graphics and pane families
```

## The decisions of the owner

From section 13.1 of the whole-project plan.

1. **A reference step means what it says** (2026-11-16): "the reference step
   should not lie and should not have a document specific hack, that should be a
   rule. Why? Because other places may expect that a reference step is a real step
   and it means what it means, and is not overridden."
2. **The caret is in the view of its node**, as `.viewed` and then the path inside
   the node (2026-11-16: "the JsonStringView should have a selection
   viewed.value{2} and use the forward mapping of the content for the value{2}
   part and use it's own for the viewed part").
3. **`View` is the supertype of every view, with `ContentView` below it**
   (2026-11-17: "B, View for every view with ContentView below it").

## Proposed decisions

They are approved with this plan.

1. **`View` lives in the projection slice**, in `Viewing.jl`, beside
   `ContentView`. The graphics, layout, widget and pane slices can use that slice
   already (`PLATFORM_SLICE_EDGES` in `test/platform/PlatformSuite.jl`), so the
   table gets no new edge. `ProjecturedPlatform` exports `View`.
2. **Five families go below `View`**: `ContentView`, `WidgetDocument`,
   `LayoutDocument`, `GraphicsDocument` and `PaneDocument`. The other documents
   that show something, such as a tooltip, wait for the plan that sorts the
   document types of the session.
3. **The caret of a `TextView` is `.viewed` and then the place in the text.** Its
   caret is a flat step on the view itself now, so it names no field of the view.
4. **Two functions change a path between a view and its content.**
   `get_content_path(view, path)` takes the step `.viewed` out of a path of the
   view. A new `get_view_path(view, path)` puts the step `.viewed` into a path of
   the content, in front of the first step that reaches no view of a part. The
   name `get_view_path` is a proposal.
5. **A helper of a content gives a path of the content, and the view changes it.**
   `make_content_edit` puts a write below `viewed` now. It gets the same work for
   a caret that an operation of the content gives.
6. **Nothing changes for a person.** Each key and each click does what it does
   now. Only the paths that the code stores and reads change.

## Facts of the code

A search of both repositories on 2026-11-17 found these places. A number with
"about" is an estimate of the search.

- **No source file builds a `ViewingProjection`.** Ten test and example files do.
  The one view type that the editor uses in each window is `TextView`: each plain
  text of a widget prints through it (`_print_plain_text_view` and
  `_make_widget_text_view` in `WidgetToGraphics.jl`).
- **The two methods that go** are in `Viewing.jl`, lines 33 to 41:
  `evaluate_reference_step` and `has_reference_step_child` of a `ContentView`.
- **The fields of the views of the parts are real fields**: `elements`, `children`
  and `content`. A path such as `.elements[3].elements[1].value{2}` changes only
  after them: `.elements[3].elements[1].viewed.value{2}`.
- **The places in the source**, by file:

  | File | Places | What |
  | --- | --- | --- |
  | `source/platform/projection/higherorder/Viewing.jl` | 7 | the two methods, `get_content_path`, the path computation of the output view, the two maps of the viewing step, `_find_caret_view_steps` |
  | `source/platform/text/TextView.jl` | 6 | the maps of `TextViewToGraphicsCanvas`, `_find_text_view_place`, two reads of the caret |
  | `source/platform/text/TextDocument.jl` | about 8 | `make_flat_range_reference`, `_make_flat_selection_reference`, `_text_insert`, the motions, `_text_extend`, the evaluation of `ReplaceTextRangeOperation` |
  | `source/platform/text/TextToGraphics.jl` | about 5 | the caret of a pointer and of a geometry key |
  | `source/platform/text/TextFolding.jl` | 5 | the path computation of the output view, two maps, three readers |
  | `source/platform/syntax/SyntaxView.jl` | 3 | `_get_view_caret` and its callers |
  | `source/domain/json/JsonView.jl` | 4 | `_find_replaceable_view`, `_find_innermost_array`, the path of a comma |
  | `source/platform/widget/WidgetToGraphics.jl` | about 10 | the caret of the text of a widget, in both directions, and the text of a tab name |
  | `source/platform/widget/WidgetColumnHeader.jl` | 1 | the filter field of a column |

- **The lines in the tests and the examples** that write or compare a path of a
  view:

  | File | Lines |
  | --- | --- |
  | `test/domain/json/projection/JsonViewTest.jl` | about 52 |
  | `test/platform/projection/SyntaxLeafViewTest.jl` | about 21 |
  | `test/platform/projection/SyntaxNodeViewTest.jl` | about 17 |
  | `test/projectured/projection/MarkdownJsonViewTest.jl` | about 17 |
  | `test/domain/markdown/projection/MarkdownViewTest.jl` | about 12 |
  | `test/platform/projection/TextViewTest.jl` | about 11 |
  | `test/platform/projection/WidgetTextWrapTest.jl` | about 4 |
  | `example/domain/json/JsonViewDocumentExample.jl` | 6 |
  | four other document examples of views | 2 each |

- **A new content brings a caret.** A row such as `@selected JsonString("")
  value{0}` gives a content with a caret in it. `make_content_edit` clears that
  caret (`_clear_written_selection!`), and the view takes it. The view must take
  it as `.viewed.value{0}`.
- **`omnet-julia` names no view type and no path of a view.** No source file
  there uses `TextView`, `ContentView`, `viewed`, `make_content_view` or
  `get_content_path`. `_wire_carets!` in
  `source/legacy/simulator/presentation/LegacySimulationRunnerToWidget.jl` maps
  paths of widgets and names no view.
- **No file of the kernel changes.** So no sealed file is in the way. Each file is
  checked against `SEALING.md` again before its edit.

## Steps

- [ ] **1. The type `View`.** `abstract type View <: Document` in `Viewing.jl`,
  `ContentView` below it, and the widget, layout, graphics and pane families below
  it. The export of `View`.
  Tests: a new test that each of the five families is below `View`;
  `test_platform_layering()`.
- [ ] **2. The path functions of a view.** The two methods of `Viewing.jl` go.
  `get_content_path` takes the step `.viewed` out, and `get_view_path` puts it in.
  The path computation of the output view, the two maps of the viewing step and
  `_find_caret_view_steps` use them.
  Tests: a new test of the two functions on a view with parts and on a view of a
  leaf: each is the inverse of the other, a step to a field of the content does
  not evaluate on the view, and the path with `.viewed` does.
- [ ] **3. The JSON, Markdown and syntax views.** `_find_replaceable_view`,
  `_find_innermost_array` and the path of a comma in `JsonView.jl`;
  `_get_view_caret` in `SyntaxView.jl`; the caret that a new content brings.
  Tests: `JsonViewTest.jl`, `SyntaxLeafViewTest.jl`, `SyntaxNodeViewTest.jl`,
  `MarkdownViewTest.jl`, `MarkdownJsonViewTest.jl`, and the print of the five
  document examples of views.
- [ ] **4. The text view.** The caret of a `TextView` is `.viewed` and the place
  in the text: the helpers of `TextDocument.jl`, the pointer and the geometry
  keys of `TextToGraphics.jl`, the maps of `TextView.jl` and of `TextFolding.jl`.
  Tests: `TextViewTest.jl`, the text view examples, `test_text()` if the suite has
  that name, else the text files of `test_platform()`.
- [ ] **5. The text of a widget.** The caret of the text of a widget, in both
  directions, in `WidgetToGraphics.jl`; the text of a tab name; the filter field
  of a column.
  Tests: `WidgetTextEditTest.jl`, `WidgetTextWrapTest.jl`, `SlotSpaceTest.jl`, and
  a real editor: typed text in a text field, a click that puts the caret, a
  selection by a drag, a change of a tab name, and a text in the filter field of
  a column.
- [ ] **6. The wide check and the guides.** `test_platform()`, `test_kernel()` in
  a process of its own, `test_json()`, `test_markdown()`, the sweeps of the
  examples, each against the known failures of `main`. A new record of the
  precompile calls of each package whose list goes stale. `Pkg.precompile` of
  `omnet-julia` against the branch, with a count of the compiled packages against
  the manifest. The guides: the section "A type that has views" of
  `architecture-rules.md`, `selection.md`, `projection-system.md`, `text.md`,
  `syntax.md`, `json.md` and `markdown.md`. In
  `documentation/design/content-and-view.md`, the two lines of "The code now"
  that this plan makes untrue go. The plan moves to `plan/done/`. Then the session
  asks for the landing, and for the push apart.

## Risks

1. **A path that the search did not find.** Such a path evaluates to nothing, so a
   caret does not show or a key does nothing, with no error. The key tests of
   steps 3 to 5 and the real editor check are the guard.
2. **The text of each widget goes through step 5.** A fault there shows in each
   text field of the editor. The widget tests and the real editor check are the
   guard, and step 5 is a commit of its own, so it can go back alone.
3. **The cost of a caret move.** `get_view_path` walks the views of the parts at
   each move. Step 2 measures a caret move in the JSON array of section 7 of the
   whole-project plan before and after, and a cost that shows stops the step.
4. **The recorded precompile calls go stale**, as in the plans before this one.
5. **A new supertype for four families.** A method of the platform for `View` can
   be ambiguous with a method of a family, here or in `omnet-julia`. Step 1 adds
   no method for `View`, and the precompile of step 6 is the guard.

## Not in this plan

- `@content_view`, the view of a list, and a view that is made only when
  something reaches it (point 2 of the order).
- The key tables: which rows are in the table of a view and which in the table
  of a content (point 3).
- The kernel hook, and a content with no selection field (point 4).
- A change of any key, click or look.
