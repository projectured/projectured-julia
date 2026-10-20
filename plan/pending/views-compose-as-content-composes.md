# Views compose as content composes

Status: IN PROGRESS, decided but for the questions of step 6. The JSON
pipeline is the pilot, built from the bottom up. Step 1 is done, in the worktree
`projectured-julia-views-compose`, branch `views-compose`; step 2 is done in
the model of one recursion (decisions 10 to 13).

## The ask

The owner, 2026-10-18, after `a-view-document-keeps-the-state-of-one-view.md`:

- "If backward compatibility was not an issue, how would you design this? I mean
  even the json domain contains the selection and the collapsed state, maybe it
  would have been better to put this info the view then we can have different
  collapse and selection per view. [...] I have the feeling that this is all
  related to where the selection should be stored."
- "I wonder if we should also separate the content and the view projections by
  repeating the separation of content and view in the syntax domain and the text
  domain as well. [...] it would allow editing text or syntax in itself with using
  multiple views the same way. Plus, don't forget that content and view should
  combine domains, for example, json and xml in markdown, etc."
- "I believe from the main editor loop's point of the content and the view is just
  the same. [...] Selection, content and view are not special cases in the
  projectional sense."
- "When this plan gets implemented we should not loose features and composition is
  a feature. Also, being able to show the same view at two different places in the
  editor with the exact same shared selection is a feature now. We want to have
  both, multiple views with different selections and shared views for parts. [...]
  So the whole view and content structure should be recursive, no? Also, there's a
  focusing projection, which should work, no? [...] one json file with two
  different views with their own selection and collapse state and both of those
  views have two places on the screen showing two different parts of the views. So
  it's 4 things on the screen of the same json file."
- "In the beginning we only have json string and it's view perhaps json string
  view. This maps to syntax leaf and a syntax leaf view which then maps to text
  block and text view. Then we realise we need json array, but we don't throw out
  the existing structure, we create new documents and combine them with existing
  ones. [...] Composition and reuse, that's very important, because this makes sure
  whatever new document and view we can come up with, it's going to combine with
  existing ones. So the pilot should be built bottom up. Text content and text view
  first. Syntax leaf and it's view second. Syntax node and it's view third. Json
  string and it's view fourth. Json array and its view fifth. Maybe the individual
  view documents can share the types, it depends on their shape."

The owner, 2026-10-19 and 2026-10-20, on the shape of the projections:

- "so a NewView(NewContent()) is basically the same as the OldContent(), right? so
  the old SyntaxToText() recursion should be replaced by a new SyntaxToText()
  recursion which builds a TextBlockView(TextBlock()) from
  SyntaxNodeView(SyntaxNode()) as one step in the recursion."
- "I kind of feel like the separation of view and content is not that much
  different in terms of how the recursive nature of the document is structured but
  for the projection part I sense a difficulty of having a recursive content
  projection and and recursive view projection separately. Maybe we should have one
  recursive projection which does both at the same time."
- "can the view recursion reuse the individual content projection in some other way
  to avoid duplicating them?"

## What the code does now

The facts for the JSON pipeline, found 2026-10-18:

- **The chain is printed once for each place.** A JSON document in a tab draws
  through `JsonToSyntax`, then the syntax dispatch and `SyntaxToText`, then
  `TextToGraphics` (`SyntaxNatural.jl`), and each tab prints its own chain.
- **The selection is stored along the documents.** `@document` adds `selection`
  and `mouse_target` to about 545 document types (`DocumentMacro.jl`). Each
  document on the selection path keeps the rest of the path below it
  (`_set_selection_walk!`, `SelectionDefaults.jl`), and a move of the caret in one
  leaf writes the two cells of one range step and no `selection` cell
  (`PrinterLocalityTest.jl`). So two places of one document share the caret, which
  is a feature to keep.
- **The fold of JSON is a cell of each print.** The JSON types declare a
  `collapsed` field that no projection reads; the fold that a person makes is a
  cell of the `SyntaxNode` that each print makes, so a new print of the part loses
  it.
- **The focusing projection keeps its part itself.** `FocusingProjection` has a
  field `part`, and `ReplaceFocusPartOperation` writes the projection.
- **A document tree mirrors its content by identity.** `_TreeEntry` of
  `DocumentTreeToWidgetTree` has one entry for each place, made when the tree
  reaches it.
- **The editor holds each open file once** (`OpenFileList`), as a session document.
- **A content projection prints each child through the recursion that it gets**
  (`print_child(recursion, child, child_ctx)`), and the context of the child holds
  the path of the child: the path of the parent and the step of the child. The
  template engine gives `.field` or `.field[i]` (`_make_template_child_context`,
  `_make_template_element_context`, where the index is a cell that follows the
  child when it moves), and `SyntaxCompoundToText` gives `.children[i]`.
- **The key tables of the syntax read the selection of the content**:
  `@gestures SyntaxCompound` and `@gestures SyntaxLeaf` (`SyntaxDocument.jl`).
- **A text fold shares the fold of its content node.** With `text_folds = true`,
  `SyntaxCompoundToText` prints every child, and the first line of a node that folds
  gets a `TextFold` that shares the `collapsed` cell of the node.

## The model

1. **A view is a shadow of its content.** Each content node has a view node, so the
   view tree mirrors the content tree. A view keeps the state of one view: the tail
   of the caret, the fold and the part under the pointer. It answers the paths of
   its content: the step that reaches a child content from its parent content
   reaches the view of that child from the parent view, and a step into a field of a
   leaf reaches that field of the content. So a path of a view, such as
   `[2].value{3}`, is the path that the document had before the separation. A view
   makes the view of a child lazily and follows the child content by identity; a
   child that goes takes its view with it.
2. **A view over its content is the document of before.** It holds what one
   document held before: the content and the state of one view. So one projection
   step can print both.
3. **One recursion over the views builds both outputs.** A stage takes a view over
   its content and gives the view of the next domain over the printed content. A
   content with no view prints with the content recursion, as now.
4. **A step reuses the content projection of its content.** A viewing projection
   wraps the content table of a stage. For a view V over the content C:

   ```
   P = the row of the content table for C
   R = the recursion of V
   M = print_document(P, R, C, ctx)        # P prints its own level, as now
   ```

   P prints each child through its recursion, `print_child(R, child, child_ctx)`.
   R takes the step of the child from the path of `child_ctx`, such as
   `.elements[2]` or `.children[2]`, and applies it to V, which gives the view of
   the child. R prints that view through the real recursion, keeps its output view,
   and gives P the content IO map of the child, so P builds its output as now. A
   child that V has no view for prints as content. The output of the step is the
   view of the next domain: it holds `M.output`, the output views of the children,
   and the state of V mapped through the reference maps of M.
5. **Nothing new in printing.** R is a projection that implements
   `print_document`. Printing gets no new field of the context, no new argument and
   no new recursive function.
6. **The output view follows the shape.** A compound view gives a compound view and
   a leaf view gives a leaf view, with the caret and the fold mapped through M.
   Where the shape changes, the step has code of its own: syntax to text joins the
   carets of the child views into the flat caret of one text view and turns the
   folds into hidden ranges; text to graphics draws the band and the caret over
   `M.output`.
7. **Keys belong to the views.** A key table that reads a caret belongs to a view
   type, as the keys of a text are `@gestures TextView`. A key gives an operation
   on the view, which goes back through the reference maps of each stage. An edit
   through a view changes the content and leaves the caret on the view.
8. **Sharing is by reference, at every level.** Two views of one content are two
   view trees over it, each with its own caret and folds. A view shown at two places
   is two places that refer to the one view tree, or to one subtree of it, so they
   share its caret and its folds. A place is printed by the focusing projection, and
   the part that it shows is a field of the place.
9. **Composition crosses domains.** A view of a Markdown document holds the view of
   its JSON part, and that JSON view can also have places of its own elsewhere.

### The shape for JSON

```julia
array = JsonArray([JsonString("a"), JsonString("b")])   # the content
view  = JsonArrayView(array)                             # its child views follow array.elements

ChainingProjection(
    RecursiveProjection(ViewingProjection(JsonToSyntax())),
    RecursiveProjection(ViewingProjection(SyntaxToText(text_folds = true))),
    ViewingProjection(TextBlockToGraphicsCanvas(; measure)))
```

```
JsonArrayView(JsonArray) → SyntaxNodeView(SyntaxNode) → TextView(TextBlock) → [band, drawing of the text, caret]
```

The IO maps of the first stage:

```
ViewingIoMap                              input = JsonArrayView        output = SyntaxNodeView
├ M: the IO map of JsonArrayToSyntaxNode   input = JsonArray            output = SyntaxNode
│   ├ child 1: a content IO map, which R gave P
│   └ child 2: a content IO map, which R gave P
└ the IO maps of the child views
    ├ ViewingIoMap                        input = view of element 1    output = SyntaxLeafView
    └ ViewingIoMap                        input = view of element 2    output = SyntaxLeafView
```

R finds the view of element 2 so: P prints element 2 with a context whose path
ends with `.elements[2]`, and `.elements[2]` of the `JsonArrayView` is the view of
element 2.

## Decisions

1. **A content document lives where the composition puts it** (the owner,
   2026-10-18: "there's no hard requirement, it lives where composition makes
   sense"): a file in the open files of the editor, a JSON part in its Markdown
   document.
2. **The `selection` and `mouse_target` fields that `@document` adds go**, for a
   domain when its views hold the selection, then from the macro (the owner:
   "agreed").
3. **The pilot is built from the bottom up, one pair at a time** (the owner: "Text
   content and text view first. Syntax leaf and it's view second. Syntax node and
   it's view third. Json string and it's view fourth. Json array and its view
   fifth."), and the work shows the composition (the owner: "I want to see the
   composition").
4. **The view mapping is generic**, through the reference maps of the content
   projections, and **a view follows its content by the identity of the content
   node** (the owner, 2026-10-18: "Agreed all 3"). **Each content type has a view
   type of its own, which declares the child fields of its content** (the owner,
   2026-10-20: "yes", which replaces "view types are shared by shape" of
   2026-10-18). Two content types share a view type only when they have the same
   child fields and the same key table, as the sequences of the syntax do. All views
   are subtypes of one abstract type, `ContentView`, which holds what every view
   does: it reads a field that it does not have through its content, it gives an
   edit of such a field to its content, it keeps its caret when the focus leaves
   it, and it names `content` as the field that a person edits. The reasons: a step
   maps its paths with the maps of its content projection only when a path of the
   view is the path of its content; the selection walk enters a child by the name
   of its field; and a key table moves from a content type to its view type with
   its rows and its dispatch.
5. **The structure is recursive, and features stay** (the owner, 2026-10-18): two
   places of one view share its selection, as two places of one document share it
   now; two views of one content do not; the focusing projection works on views.
6. **The plan `an-insert-moves-the-paths-after-it.md` does not come first** (the
   owner, 2026-10-19: "I don't think we need to do the insert path plan first").
7. **Until step 8, the caret of a view ends at the view and never enters its
   content** (found in step 1). The text types still have their `selection`
   fields. A path through `.content` makes the selection walk write into the shared
   text, so two views would hold one chain of cells, and an in-place caret move of
   one view (`_sync_selection!`) would move the caret of the other. So a text view
   keeps a flat caret `{k}` on itself, and an edit through it goes back as a flat
   edit of the view.
8. **The content and the view each have their part of a step, and no text block
   carries the caret of a view** (the owner, 2026-10-19: "the content should be
   projected using two projections, no? one is for the content
   TextBlockToGraphicsCanvas, the other is TextViewToGraphicsCanvas"). In the one
   recursion of decision 10, the content part is the row of the content table, such
   as `TextBlockToGraphicsCanvas`, and the view part is the output view of the step,
   such as the band and the caret over the drawing. Step 1 built the two as rows of
   one table; step 2 makes the view part the text case of the viewing projection. A
   first form of step 1 printed a view as a `TextBlock` that held the caret of the
   view, which the owner rejected ("how can a TextView be printed into a
   TextBlock?").
9. **A content is printed once for each place, and printing a document once is a
   topic of its own** (the owner, 2026-10-19: "in step 1, it's fine"; "this issue of
   printing only once is not new, it has nothing to do with the view and content
   separation"), in `plan/tentative/a-document-at-several-places-is-printed-once.md`.
   The owner deferred that plan, and the syntax step goes on (2026-10-19: "I defer
   the tentative plan").
10. **One recursion builds the output content and the output view together** (the
    owner, 2026-10-20: "Maybe we should have one recursive projection which does
    both at the same time"; "this looks exceptionally promising"). A step reuses the
    content projection of its content with a recursion of its view (model 4).
11. **Nothing new in printing** (the owner, 2026-10-20: "I would like to avoid
    extending the printer context and I would like to also avoid changing the
    print_document function or introducing a new recursive function").
12. **A content with no view prints with the content recursion** (the owner,
    2026-10-20: "we can still have the content recursion if that's what is in the
    document (no view attached)").
13. **The view is a shadow of its content, and the recursion of a view finds a child
    view by the step of the child** (the owner, 2026-10-20: "when R finds the child
    view of a child content it could use the reference of the child stored in the
    iomap"; "Maybe we don't need the whole reference from the root only a step or
    something but the view is basically a shadow of the content so there should be a
    direct mapping between the two"). R reads the step from the context that P gives
    the child, whose path ends with it. A path of a view is the path of its content
    (model 1).

## What is not known yet

- **The cost of the mirrors.** Each view keeps a node for each content node that it
  reached, at each domain of the chain.
- **The old text chains.** `TextToGraphics` draws a `TextBlock` with its own caret
  for every chain that is not a chain of views yet, so step 8 can take the field
  from `TextBlock` only when no chain gives a text a caret.

## Questions

- **QA, for step 6. The state of a view and the state of a place.** My proposal: the
  view keeps the caret and the folds, which its places share; the place keeps its
  part, its scroll and the part under the pointer.
- **QB, for step 6. A key when the caret of a view is not in the part of the focused
  place.** My proposal: a press in a place moves the caret of its view into the part
  of the place, and a key goes to the caret of the view.
- **QC, for step 6. The pastes of a view.** A new place of the same view, a new view
  that starts from a copy of the state, or a copy of the content: three commands, or
  one paste whose kind the person picks.

## Steps

Each step is one or more commits with its tests, in a worktree, with a check of
`SEALING.md` before each edit of a kernel file. Mark each step done here. Each step
keeps every pair below it working, and shows its composition: the content, the views
and the output of each stage, as structures that a person reads.

1. [x] **Text content and its view.** A `TextBlock` and a text view: one text in two
   views, each with its own caret and scroll, and one view at two places, which
   share its caret. First in a test of the platform with no change of `main`, which
   measures the cells that a move of the caret recomputes; then on the editor.
   Tests: the text suites, `test_selection_localities()`.

   Done 2026-10-19, in the shape of decision 8. What it made:
   - `TextView(content)` in `source/platform/text/TextView.jl`: the field
     `content`, and the `selection` and `mouse_target` that `@document` adds. Its
     selection is a flat place `{k}`, `{s:e}` or a box, and ends at the view
     (decision 7). It keeps its caret as a dormant selection when the focus leaves
     it, in any container (`has_dormant_selection`); this is my choice, so that two
     views keep two carets in a layout too, which keeps no dormant branch.
     `get_edited_field` names `content`. Its keys are a table of its own,
     `@gestures TextView`; the key helpers of the text take the caret as an
     argument.
   - `TextBlockToGraphicsCanvas`: the lines of a text as a canvas, with no caret,
     laid out by the line layout of `TextToGraphics` (`_print_text_lines`). Its IO
     map gives the forward map of a place, the caret at a point, and the caret and
     the band of a selection (`_compute_selection_marks`). A text whose lines are a
     lazy list still prints with `TextToGraphics`.
   - `TextViewToGraphicsCanvas`: prints `view.content` through the recursion, and
     draws the band and the caret of the view over that drawing
     (`_make_selection_marks`); its output is `[band, drawing of the content,
     caret]`. Forward, a place of the view maps through the IO map of the content;
     backward, a point maps through it to the caret of the view. Up, Down, Home and
     End read the segments of the content (`_read_geometry_key`). The band follows
     each row of a range, which a reference map and `find_reference_box` do not
     give, so the view asks the IO map of its content for the rows.
   - `TextToGraphics` draws as before, from the same two parts: the lines, and the
     marks of the caret of its block.
   - `evaluate_operation` of a `ReplaceTextRangeOperation` edits the content of a
     `TextView` and puts the caret on the view. An edit beside an inline image
     through a view does nothing: an element write puts its caret into the lines.
   - The example `text_view`: a vertical layout of three places over one text, view
     A, view B and view A again. It is on the skip list of the caret sweep beside
     `layout`: a layout sends a key only by the selection, so Ctrl+Home with no
     selection reaches no caret.
   - The scroll stays with the place; a `TextView` keeps none. Question QA decides
     it at step 6.

   The shape:

   ```
   documents                          projection: one table in a recursion
   VerticalLayout                     VerticalLayout => VerticalLayoutToGraphicsCanvas
   ├ [1] TextView A ──┐               TextView       => TextViewToGraphicsCanvas
   ├ [2] TextView B ──┼─ TextBlock T  TextBlock      => TextBlockToGraphicsCanvas
   └ [3] TextView A ──┘

   IO maps
   ChildrenIoMap                            input = the layout
   ├ [1] TextViewToGraphicsCanvasIoMap      input = A   output = [band, drawing of T, caret of A]
   │     └ TextBlockToGraphicsCanvasIoMap   input = T   output = drawing of T, no caret
   ├ [2] TextViewToGraphicsCanvasIoMap      input = B   output = [band, drawing of T, caret of B]
   │     └ TextBlockToGraphicsCanvasIoMap   input = T
   └ [3] TextViewToGraphicsCanvasIoMap      input = A   output = [band, drawing of T, caret of A]
         └ TextBlockToGraphicsCanvasIoMap   input = T
   ```

   Measured with `is_cell_valid` over the cells that the drawing of each place
   reaches (93 for each place):

   | Change | place 1 (A) | place 2 (B) | place 3 (A) | in the drawings of T |
   | --- | --- | --- | --- | --- |
   | a caret move in A | 5 | 0 | 5 | 0, 0, 0 |
   | the focus from A to B | 5 | 5 | 5 | 0, 0, 0 |
   | a caret move in B | 0 | 5 | 0 | 0, 0, 0 |
   | a typed character in B | 14 | 15 | 14 | 10, 10, 10 |

   One `TextBlock` in one place through `TextToGraphics` makes 5 cells stale for a
   caret move. The last row shows the three prints of T (decision 9).

   Limits: a caret path into the content through `.content`, as a sweep or a
   search makes one, writes selection cells into the shared text until step 8; a
   key or a click makes none. An insert before the caret of another view does not
   move that caret.

   Tests: `test_text_view()` 30; the text tests with the widget text, the syntax
   and primitive text and the printer walk of every platform example 153713;
   `test_json()` 239; the platform layering guard; the naming guard. The REPL walk
   of the example gives no error.
2. [x] **The viewing projection, on a syntax leaf.** The viewing projection and the
   recursion of a view (model 4), and the view of a syntax leaf. The chain is
   `ViewingProjection(SyntaxToText())` and then the text stage, where the text step
   of step 1 becomes the text case of the viewing projection over
   `TextBlockToGraphicsCanvas`. A content with no view prints as now. The keys of a
   leaf move to its view. Tests: `test_text_view()`, `test_syntax_to_text()`, and a
   test of one leaf in two views at three places, with keys, a click and an edit.

   Done 2026-10-20. What it made:
   - `ContentView`, `make_content_view`, `ViewingProjection` and `ViewingIoMap` in
     `source/platform/projection/higherorder/Viewing.jl`. A field step that a view
     does not have reads its content (`evaluate_reference_step`), so the
     annotation, the validation and the selection walk take `.value{3}` at the view,
     and the walk stops there. A `ContentView` names `content` as its edited field
     and keeps a dormant caret.
   - `ViewingProjection` prints the content of a view with its table and gives
     `make_content_view(M.output)`, whose paths are the paths of the view mapped
     through the maps of the table. A path of the view is typed against the content
     before the map (`_get_content_path`), because the map of a content projection
     matches the types of the content, such as `::SyntaxLeaf.value{s:_}`. A gesture
     with no operation goes to the key table of the view; an operation goes back
     through the readers of the content print. Any other input prints with the
     table, as now.
   - The recursion of a view (R) is not in this step, because a leaf prints no
     child. It comes in step 3, with the first child.
   - `SyntaxLeafView` in `source/platform/syntax/SyntaxLeafView.jl`, with
     `@gestures SyntaxLeafView` (Ctrl+Space and Ctrl+Alt+Home), whose rows share
     `_toggle_leaf_cursor` with the table of `SyntaxLeaf`. `TextView` is a
     `ContentView`, and `make_content_view(::TextBlock)` is a `TextView`.
   - The last stage stays the table of step 1, `TextView => TextViewToGraphicsCanvas`
     beside `TextBlock => TextBlockToGraphicsCanvas`, and not a case of the viewing
     projection, as the text of this step said. The view row there is the change of
     shape of decision 8: it draws the marks of a view with the colors of a theme,
     which a generic step does not hold.
   - An edit of a field that its target does not have edits the document that the
     target shows (`_get_field_holder`, in the evaluation of a string edit and of a
     number edit), and its caret stays on the target.
   - The example `syntax_leaf_view`, on the skip list of the caret sweep beside
     `layout`.

   The shape:

   ```
   documents                          projection
   VerticalLayout                     VerticalLayout => VerticalLayoutToGraphicsCanvas()
   ├ [1] SyntaxLeafView A ──┐         SyntaxLeafView => ChainingProjection(
   ├ [2] SyntaxLeafView B ──┼─ L          RecursiveProjection(ViewingProjection(SyntaxToText())),
   └ [3] SyntaxLeafView A ──┘             RecursiveProjection(TypeDispatchingProjection(
                                              TextView  => TextViewToGraphicsCanvas(),
                                              TextBlock => TextBlockToGraphicsCanvas(; measure))))

   IO maps of a place
   ChainingIoMap
   ├ ViewingIoMap                         input = A    output = TextView A′(content = T, caret of A through M)
   │   └ M: the IO map of SyntaxLeafToText   input = L    output = T
   └ TextViewToGraphicsCanvasIoMap        input = A′   output = [band, drawing of T, caret]
       └ TextBlockToGraphicsCanvasIoMap   input = T
   ```

   `SyntaxLeafToText` does not change. Back: Right gives `{k}` on A′, which the map of
   M takes to `.value{j}` on A; a typed character gives a flat edit on A′, which the
   reader of M makes `.value[s:e]` on A, an edit of L with the caret on A.

   Tests: `test_syntax_leaf_view()` 31; `test_text_view()` 30; the syntax, primitive
   and text tests with the printer walk of every platform example 154173;
   `test_json()` 239; the platform layering guard; the naming guard. The REPL walk of
   the example gives no error.
3. [ ] **A syntax node and its view.** R finds each child view by the step of the
   child (decision 13). The carets of the child views join into the flat caret of
   the text view, and the folds of the views become its hidden ranges, over a
   content printed with `text_folds = true`. The keys of a compound move to its
   view. Tests: `test_syntax()`, `test_collapse_roundtrip()`.
4. [ ] **A JSON string and its view**, through `ViewingProjection(JsonToSyntax())`.
   Tests: `test_json_to_syntax()`.
5. [ ] **A JSON array and its view**, which holds the views of its elements; the dead
   `collapsed` fields of the JSON types go. Tests: `test_json()`,
   `test_example(json_example)`, `test_click_roundtrips()`.
6. [ ] **Places**: the owner's example of one JSON file, two views and four places,
   with the focusing projection printing a place; the pastes of QC.
7. [ ] **Composition across domains**: a JSON part of a Markdown document, its view
   inside the Markdown view and at a place of its own. Tests: `test_markdown()`.
8. [ ] **The selection fields go** for the text, syntax and JSON types (decision 2).
9. [ ] **The guides.** `concepts.md`, `engineer-tour.md`, `architecture-rules.md`,
   `selection.md`, `projection-system.md`, `text.md`, `syntax.md`, `json.md`; the
   plan moves to `plan/done/`.

## Not in this plan

The other domains; they follow the pilot one at a time. The navigator keeps its
views of pages (`a-view-document-keeps-the-state-of-one-view.md`) until a step
reaches its pages. Printing a document once for several places is the tentative
plan of decision 9.
