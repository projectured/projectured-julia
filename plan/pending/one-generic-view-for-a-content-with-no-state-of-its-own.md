# One generic view for a content with no state of its own

**Status:** pending, written on 2026-11-16, not approved, nothing built.

This plan is point 2 of the order in section 12 of
`plan/tentative/content-and-view-for-the-whole-project.md`, which the owner
approved on 2026-11-16. It makes one generic view type, removes 11 of the 12 view
types of the pilot, and leaves one key table for each content type. It lands
nothing and pushes nothing: it ends with a request to land.

## The problem

The pilot has a view type for each content type that it moved: 12 types in 4
shapes. Nine keep only their part of the caret. Each view type has a key table
that repeats the table of its content with another helper.

```julia
# now: a type and a table for each content type
@document struct JsonStringView <: JsonView
    viewed::JsonString
end
@document struct MarkdownParagraphView <: MarkdownView
    viewed::MarkdownParagraph
    content::CellVector
end
@gestures JsonDocument begin
    KeyPress('n') => "Replace with null" => replace_selected_document(doc, @selected JsonNull())
end
@gestures JsonView begin
    KeyPress('n') => "Replace with null" => _replace_through_view(doc, @selected JsonNull())
end

# after this plan: one view type, one table for each content type
make_content_view(JsonString("a"))                           # a DocumentView
make_content_view(MarkdownParagraph([MarkdownText("b")]))    # a DocumentView, with the views of its parts
@gestures JsonDocument begin
    KeyPress('n') => "Replace with null" => replace_selected_document(doc, sel, @selected JsonNull())
end
```

With a view type for each type on the path of a caret, the whole project needs
300 to 400 view types.

## The decisions of the owner

1. **One generic view** (2026-11-16: "Yes"). A type with no state of its own has
   no view type of its own. The generic view keeps its part of the caret and the
   views of its parts.
2. **A key table belongs to the content type, and the view gives it the caret**
   (2026-11-16: "I agree with option 1"). This replaces decision 7 of the pilot
   plan, "Keys belong to the views". A key still goes down along the caret of the
   views, the deepest first (decision 20 of the pilot plan).
3. **No view gives its state to the printer of a part through the printer
   context** (2026-11-16, on the arrangement). The printer of a part reads the
   view of that part.
4. **Views that are equal in structure and behaviour are one view** (2026-11-16:
   "Perhaps we should switch to reusing the same view if they are structurally
   and behaviourally equivalent").

## Proposed decisions

They are approved with this plan.

1. **The name is `DocumentView`.** It is the view of a document that has no view
   type of its own. `ContentView` stays the supertype of every view. The other
   name that was considered is `GenericView`, which says how the type is made and
   not what it shows.
2. **The fold is state of the generic view**, in the field `collapsed`. So
   `JsonArrayView` and `SyntaxNodeView`, which are equal in structure, go too, and
   11 of the 12 types go. A view of a leaf never closes.
3. **The generic view keeps the views of its parts for each child field of its
   content.** A field of the content that holds one document has one part view,
   and a field that holds a collection of documents has the views of its
   elements, which follow the elements by identity as `make_child_views` does now.
   A field step with the name of a child field of the content gives the part
   views, so a path of the content stays a path of the view (rule 5 of section
   11.6 of the picture).
4. **The selection walk of the kernel enters a child through the reference seam.**
   `_selection_child` reads a struct field with `hasfield` and `getfield` now. The
   reference evaluation asks `has_reference_step_child` and
   `evaluate_reference_step`. The walk asks the same two, so a document answers
   one question for both. The kernel gets no notion of a view.
5. **A row of a key table can read `sel`**, the caret that the table got, as a
   `when` condition reads it now. `doc` is the content. A view reads a key first
   with the table of its own type, for state of its own, and then with the table
   of the type of its content, to which it gives its caret as a path of the
   content. A write that the row makes goes below the field `viewed`
   (`make_content_edit`). A helper that reads the caret of `doc`, such as
   `replace_selected_document`, gets a method that takes the caret.
6. **The same types have a view as now.** Each domain declares them in one method,
   such as `make_content_view(content::Union{JsonNull, JsonBool, JsonNumber,
   JsonString, JsonArray}) = DocumentView(content)`. A JSON object and the other
   Markdown types get the generic view in points 6 and 8 of the order.
7. **A node of a part is made as now**, when the collection of the part views is
   read. A node that is made only when a caret or a state reaches it belongs to
   the view of a lazy list, point 4 of the order.
8. **`TextView` stays a type**, because it has its own printer and its own state.
   Its key table goes by proposed decision 5: the table of `TextBlock` reads the
   caret that the view gives.

## Facts of the code

- **The shapes.** `viewed` only: the four JSON leaf views, `MarkdownTextView`,
  `SyntaxLeafView`. `viewed` and the views of the children:
  `MarkdownParagraphView`, `MarkdownHeadingView`, `MarkdownRootView`. The same and
  a fold: `JsonArrayView`, `SyntaxNodeView`. `TextView` is the fourth shape.
- **Who names a view type.** No source file outside `JsonView.jl`,
  `MarkdownView.jl` and `SyntaxView.jl`. Five test files and eight example files
  call a constructor: `JsonArrayView` 9 times, `SyntaxNodeView` 6, `MarkdownRootView`
  5, `SyntaxLeafView` 4, `JsonStringView` 4. No released version exports a view
  type of the pilot: the pilot came to `main` on 2026-11-15.
- **The machinery is generic already.** `Viewing.jl` works on `ContentView`:
  the paths, the dormant caret, the copy, the paste, the viewing step and its
  recursion. `evaluate_reference_step` and `has_reference_step_child` of a
  `ContentView` read the content for a field that the view does not have.
- **The fold code of the syntax** dispatches on `SyntaxNodeView` and on
  `SyntaxCompoundToTextIoMap`: `map_view_state!`, `read_view_operation`,
  `_find_closed_folds`, `_find_fold_path`. The IO map type alone can carry the
  dispatch.
- **A key table.** `@gestures` makes a row as a closure of `doc` and the event,
  and a `when` condition as a closure of `doc` and `sel`.
  `fire_gesture_bindings(bindings, target, event; selection, claimed)` has the
  caret in `selection` and gives it only to the condition. 77 bindings of the
  source are made by hand with a closure of two arguments, so that form must stay.
- **Rows that read the caret of `doc`** in the tables of this plan: two rows of
  `JsonDocument.jl` (`get_selection(doc)`), two of `MarkdownToSyntax.jl`
  (`doc.selection`), four of `SyntaxDocument.jl` (`doc.selection`), and each row
  that calls `replace_selected_document`. The helpers of the text take the caret
  as an argument since the plan `one-text-view-keeps-the-look-and-the-caret.md`.
- **The files of the kernel that change** are not sealed in `SEALING.md` on
  2026-11-16: `selection/SelectionDefaults.jl`, `binding/Gestures.jl`,
  `binding/GestureBinding.jl`. Each is checked again before its edit.

## Steps

- [ ] **1. The generic view and the walk.** `DocumentView` in `Viewing.jl`, with
  `viewed`, the part views and `collapsed`; it answers a field step of a child
  field of its content. `_selection_child` asks the reference seam.
  Tests: a new test of a generic view over a type with one child field and over a
  type with a collection: a path of the content is a path of the view, two views
  of one content keep two carets and two folds, a part keeps its view when its
  index changes, a copy and a paste. `test_selection()` and the selection tests of
  the kernel, with the time of the selection walk before and after.
- [ ] **2. One key table for each content type.** A row can read `sel`; a view
  reads a key with the table of the type of its content. This step comes before
  the view types go, because a table of a view type has no home after its type
  goes. The tables of `JsonView`, `JsonArrayView`, the two syntax views and
  `TextView` go, and the helpers `_replace_through_view` and
  `_append_element_through_view` with them.
  Tests: the key tests of `JsonViewTest.jl`, `SyntaxLeafViewTest.jl`,
  `SyntaxNodeViewTest.jl`, `MarkdownJsonViewTest.jl` and `TextViewTest.jl`, the
  text tests of the widgets (`WidgetTextEditTest.jl`, `WidgetTextWrapTest.jl`),
  `test_json()`, `test_markdown()`, `test_syntax()`, and a real editor: typed
  text, a replace key and a comma in a JSON view inside a Markdown view, and a
  text field.
- [ ] **3. The view types with no behaviour of their own go.** The five JSON
  views, the four Markdown views and `SyntaxLeafView`; `make_content_view` of
  their content types gives a `DocumentView`. The tests and the examples make a
  view with `make_content_view`.
  Tests: `JsonViewTest.jl`, `MarkdownViewTest.jl`, `SyntaxLeafViewTest.jl`,
  `MarkdownJsonViewTest.jl`, the print of the seven view examples.
- [ ] **4. `SyntaxNodeView` goes.** The fold code of the syntax becomes code of
  the view of a syntax node, by the IO map type.
  Tests: `SyntaxNodeViewTest.jl`, `TextViewTest.jl`, the fold tests of
  `JsonViewTest.jl`, and the real editor check of the folds of the pilot.
- [ ] **5. The wide check and the guides.** `test_platform()`, `test_kernel()` in
  a process of its own, the sweeps of the examples, against the known failures of
  `main`. A new record of the precompile calls of each package whose list goes
  stale. `Pkg.precompile` of `omnet-julia` against the branch, with a count of
  the compiled packages against the manifest. The guides: the rule "A type that
  has views" of `architecture-rules.md`, `selection.md`, `projection-system.md`,
  `syntax.md`, `json.md`, `markdown.md`, `text.md`, and the key tables in
  `engineer-tour.md`. The plan moves to `plan/done/`. Then the session asks for
  the landing, and for the push apart.

## Risks

1. **The selection walk is on the path of every key.** The seam costs more than
   `hasfield` and `getfield`. Step 1 measures it, and a cost that shows stops the
   step.
2. **A helper reads the caret of `doc` in a place that the scan did not find.**
   Then a key in a view does nothing or acts at the caret of the content. The key
   tests of step 2 and the real editor check are the guard.
3. **Hand-made bindings.** The form of two arguments must keep its meaning, in
   this repository and in `omnet-julia`.
4. **The recorded precompile calls go stale**, as in the plan before this one.
5. **A leaf view gets a field `collapsed` that it never uses.** The memory of a
   view of a leaf grows by one cell. Step 1 measures the memory of the JSON array
   of the picture, section 7, before and after.

## Not in this plan

- More types with a view: a JSON object, its entry, the other Markdown types
  (points 6 and 8 of the order).
- The rules for the view documents of the older rule, and who makes and holds a
  view in the editor (point 3).
- The arrangement as state of a view, the rows in view, and a node that is made
  only when needed (point 4).
- The tools that read a caret (point 5), and the widget chains (point 7).
- What `PrimitiveString` becomes.
