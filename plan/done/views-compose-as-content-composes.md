# Views compose as content composes

Status: DONE and landed on 2026-11-15. The JSON
pipeline is the pilot, built from the bottom up, on the branch `views-compose`.
Steps 1 to 7 and 9 are done; step 8 is no step of this plan (decision 21). The
plan `one-text-view-keeps-the-look-and-the-caret.md` brought the branch up to
`main`, made one `TextView` from the two, and did step 9. The owner approved the
landing, and `main` holds the pilot from `adea9d83f` on.

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
   share its caret and its folds. A container that holds the view, or the view of a
   part, is the place (decision 15).
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
    print_document function or introducing a new recursive function"). Decision 16
    adds one property to the context, and nothing else.
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

14. **A fold is state of a view, as the caret is** (the owner, 2026-10-20: "Yes but
    only if we will be able to do that the folded lines are not necessarily laid
    out if they are actually not needed. The lazy principle must hold eventually,
    what's not needed is not calculated"). In the long term:
    - A content print marks where a fold can be: the `TextFold` of a node says which
      lines are the body of the node and what its placeholder is, and holds no
      state. The `collapsed` fields of the content types go.
    - Each compound view holds its own fold, `collapsed`, and follows its node by
      identity.
    - A fold maps forward with its view. A step that maps a node to one node gives
      the fold to the view of that node; at syntax to text, the folds of the tree of
      views become the closed folds of the one text view.
    - A text view hides the lines of its closed folds, in a view step of the text
      whose closedness comes from the view.
    - A toggle is an operation on a path of the view, which each stage maps back as
      it maps a caret; the evaluation flips the fold of the view at that path.

    The first form of the content print with the fold cell of a view, asked of the
    recursion, was rejected: the content print would hold state of a view, as a text
    holding the caret of a view did in the first form of step 1.

    The condition holds in two layers. The layout and the drawing of folded lines
    are not computed, because the folding step gives the drawing only the lines that
    it shows. The print of folded text is computed while the text of a node is one
    flat list of lines and a fold counts the lines of its body; to compute nothing
    there, the text of a node becomes a structure of regions that a closed fold
    skips (not in this plan). Two rules keep the way open: the step finds closed
    folds only through the nodes that it shows, and the folding step asks a fold
    where its region ends, not for its lines.

15. **There is no place type** (the owner, 2026-10-22: "Why do we need the place to
    begin with? I question it's mere existence"; "I think the container can hold
    the view"). A container holds the view: a tab of a pane, a child of a layout. A
    place of a part holds the view of the part, which is the child view itself, such
    as `view_a.elements[3]`, so the folds of the part are the folds that the whole
    view shows. The scroll stays with the scroll pane, as now. A place of a part
    needs no focusing projection; the focusing projection stays a feature and works
    on views (decision 5).

    A whole view at one place and one of its parts at a second place keep the rule
    of decision 16 with no more code: the path from the root goes through one of the
    two, and the other shows its stored caret as a dormant one.
16. **One live selection, and the parent tells the child whether it is on the live
    path** (the owner, by 2026-11-14: "A selection is either live if it comes from
    the root or dormant if it does not. So there's only one live selection even if
    many documents, views or contents appear at multiple places. Dormant selections
    there can be many"; "When printing a selection, it may turn into a selection or
    into content. If it turns into selection then dormant selection remains dormant,
    live selection remains live. When a selection prints into content, then live and
    dormant looks differently"; "Remember that the recursion into the child from the
    parent handles selection keeping the above invariants"; "Why not just a live
    flag which the parent tells the child that it's on the live path?").
    - A document at two places has one stored caret, so its places show one
      position. Only the place on the path from the root shows it live; every other
      place shows it dormant.
    - The print context carries a live flag of the place, as a property. The root is
      live. `make_child_context` computes the flag of a child from the parent: the
      flag of the parent, and the stored path of the parent starts with the steps to
      the child. The flag is a computed value, because the caret moves between
      places with no new print, as the path of the place in the context is.
    - The path itself does not travel: the selection walk stores in each document
      on the live path the part of the path below it.
    - A print takes the caret of its input as live when the stored flag of the input
      and the flag of the place both say so.

    What the code does at the time of the decision, read and not rendered: the live
    flag is in the selection cell of each document, one for each document and not
    one for each place; the print recursion carries no selection, and a print reads
    the cell of its input (`map_selection_forward`, `TextViewToGraphicsCanvas`). So
    the places 1 and 3 of the examples of steps 1 to 5, which hold one view, both
    draw a live caret. One document at two places does the same with no view.

    Facts for the build:
    - About 73 of about 150 calls of `make_child_context` and `make_element_context`
      give the steps only and no parent document. The child of such a call takes
      the flag of its parent as it is, so nothing changes there, and the stored
      flag decides as now. The containers of the example of step 6 give their
      document.
    - The rule composes over the stages of a chain. At each level, the stored path
      of the parent and the steps to the child belong to one document. The stages
      after the first print documents that one place owns, whose stored flags the
      first stage wrote with the flag of the place.
    - `PrinterContext.jl`, `OutputPaths.jl` and `SelectionDefaults.jl` have no seal
      (`SEALING.md`, 2026-11-14).
17. **A paste gives a new view, and Copy or Note says whether the content is a copy
    or the same** (the owner, 2026-11-14: "I believe the second place of the same
    view is less useful than a second view of the same content. So we can have a
    complete copy of the content with a new view, and new view of the same content
    this will be the note, and the third case is the same view at a new place this
    is the least interesting case").
    - Copy (Ctrl+C), then Paste (Ctrl+V): a copy of the content, with a new view.
    - Note (Ctrl+N), then Paste (Ctrl+V): the same content, with a new view. The new
      view starts with a copy of the caret and the folds of the noted view.
    - Note (Ctrl+N), then the new gesture "Paste the same view" (Ctrl+Alt+V): the
      same view at a second place. It keeps the feature of one document at two
      places with one caret, which Note and Paste give before this plan.

    A paste of a stored document that is no view stays as it is. No binding uses
    Ctrl+Alt+V in the platform or in `omnet-julia` (2026-11-14). The build of step 6
    makes the second view with `make_sibling_view`, and the copy of a view with a
    method of `copy_document` for a view under every policy; no new copy policy.

    What the gestures do at the time of the decision, read and not run on a view:
    Note stores the object itself, Copy stores a full copy, Paste puts the stored
    object into the selected slot, and "Paste copy" (Ctrl+Shift+V) puts a new full
    copy of it.
18. **Step 7 gives a view to the four Markdown types of its example** (the owner,
    2026-11-14: "It's B"): `MarkdownRoot`, `MarkdownHeading`, `MarkdownParagraph`
    and `MarkdownText`, so a person puts a caret in each part of the example. The
    other 13 Markdown types keep no view and print as content, as a JSON object
    does. The choices that the owner did not take: a view of the root only, with
    which the caret names a heading or a paragraph only as a whole; a view of each
    of the 17 types, which is the move of a whole domain and no step of this plan.

    Open with it: the heading, the paragraph and the text keep their children or
    their text in a field with the name `content`, and a view keeps what it shows
    in a field with that name too, while the field of its child views needs the
    name of the child field of its content. About 80 fields in the tree have this
    name. The rule for the name is a question to the owner.
19. **A view keeps what it shows in the field `viewed`, in every view type** (the
    owner, 2026-11-14: "It's option 1"). "What a view shows" is one role, so it has
    one name, and the name is a word that a content type does not use: no field in
    the tree has it, and `content` is the most common field name of the content
    types. A caret path of a view stays the path of the document, such as
    `.content[1].content{3}` in a paragraph, and an edit goes below `.viewed`. A
    content type that has a view has no field `viewed`; a viewing step refuses a
    view whose content has one. The choices that the owner did not take: the
    Markdown types change their field, and each later domain with a field `content`
    does the same; each view type chooses its name, which gives more than one name
    to one role. The word `viewed` is the proposal of the build.
20. **A key goes down along the live caret** (the owner, 2026-11-14: "Yes, keys
    should go down along the live selection"). Each view on the path of the live
    caret reads a key with its own key table, the deepest first. It is the rule
    that the documents with no view have: the reader of a projection template asks
    the focused child before its own document, and `read_gesture_outward` of the
    kernel is that rule over a path. So a view of a part answers its keys inside
    the view of a document of another domain. The choice that the owner did not
    take: only the view at the root of a place reads a key, as after step 5, with
    which the keys of a part work only at a place of its own.
21. **Step 8 moves to a later plan** (the owner, 2026-11-15: "Agreed"). The
    selection fields go from a type only when every chain that shows the type is a
    chain of views. Found 2026-11-14: 40 of 46 chains of `JsonToSyntax`, 133 of 147
    chains of `SyntaxToText` and each of the 181 chains of `TextToGraphics` have no
    view; 18 of the 19 domains have no view; four JSON types have none. So the
    removal is the end of the move of the domains, and no step of the pilot. The
    choices that the owner did not take: the move of JSON whole in this plan, with
    the tab of a JSON file and the uses in `omnet-julia`; the move of all domains.
    The picture for the decision on the whole project is
    `plan/tentative/content-and-view-for-the-whole-project.md`.

## What is not known yet

- **The cost of the mirrors.** Each view keeps a node for each content node that it
  reached, at each domain of the chain.
- **The old text chains.** `TextToGraphics` draws a `TextBlock` with its own caret
  for every chain that is not a chain of views yet, so step 8 can take the field
  from `TextBlock` only when no chain gives a text a caret.
- **The live flag in the chains with no view.** About 126 calls in 64 files wire
  the selection of an output with no context (step 6). To pass the context in each
  is a wide change with no design in it; it is not a step of this plan yet.
- **A paste into a view.** The clipboard writes at the path of the selection, and
  the path of a part of a view names a view. The write must go to the content, as
  `make_content_edit` does for the keys of a view (step 6).

## Questions

- QA, the state of a view and the state of a place, has its answer in the decisions
  15 and 16: the view keeps the caret and the folds, the scroll pane keeps the
  scroll, and no place type keeps a thing.
- QB, a key when the caret of a view is not in the part of the focused place, is
  closed with no rule (the owner, 2026-11-14): decision 15 leaves no case. A place
  of a part holds the view of the part, and the caret of that view is a path inside
  the part.
- QC, the pastes of a view, has its answer in decision 17.

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
   - A `TextView` keeps no scroll: the scroll stays with the scroll pane (decision
     15).

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
3. [x] **A syntax node and its view.** R finds each child view by the step of the
   child (decision 13). The carets of the child views join into the flat caret of
   the text view, and the folds of the views become its hidden ranges, over a
   content printed with `text_folds = true`, in the shape of decision 14. The keys
   of a compound move to its view. Tests: `test_syntax()`,
   `test_collapse_roundtrip()`.

   The node, its view and its keys were done on 2026-10-20, and the fold on
   2026-10-21. What it made:
   - `ViewRecursion` (R) in `Viewing.jl`. A viewing step gives it to the content
     projection as the recursion. R takes the steps that the context of a child adds
     to the path of the view, applies them to the view, and prints the child view
     through the recursion of the stage; the content projection gets the content
     IO map of the child. A child with no view prints as content.
   - `make_child_views(content, field)`: the views of the children of a
     collection, which keep their identity while their child stays, at any place.
     `make_content_view(content)` answers `nothing` for a content with no view.
     `get_content_path(view, path)` gives a path of a view typed against its
     content.
   - `SyntaxNodeView(content)` in `source/platform/syntax/SyntaxView.jl`, beside
     `SyntaxLeafView`; its `children` hold the views of the children of the node.
     `@gestures SyntaxNodeView` has the rows of `@gestures SyntaxCompound`
     (Ctrl+Alt+Home, Ctrl+Space, Alt with an arrow, an arrow on a whole node); both
     tables share `_toggle_syntax_cursor` and `_navigate_syntax_tree`.
   - The carets of the child views map through the content IO map of the node to
     the flat caret of the text view, with no code of the view: the map of
     `SyntaxCompoundToText` delegates the tail of a path to its children.
   - A caret at the end of the last child is also the caret before the closing
     delimiter of the node, and the map of `SyntaxCompoundToText` names it
     `.close{0}`, as it does today.

   - The fold, in the shape of decision 14. `SyntaxNodeView.collapsed` is the fold
     of a view. The IO map of a compound print holds the `TextFold` that the print
     made (`fold`). Two hooks of the viewing step carry state that is not a path:
     `map_view_state!` sets the closed folds of the output `TextView` of a node view,
     found through the views that the text shows and never inside a closed one; and
     `read_view_operation` makes a toggle of a fold of the text,
     `ToggleCollapseOperation(fold)`, into `ToggleFoldOperation(path)`, the toggle of
     the view of the node whose print made that fold. `ToggleFoldOperation` maps back
     and reroots as a path does, and flips the fold of the view at its path.
   - `TextView.closed_folds`, and Ctrl+. in `@gestures TextView`. `TextFolding` folds
     a `TextView` too: it hides the lines of the closed folds of the view
     (`TextViewFoldingIoMap`), maps the caret over the lines that it keeps, and maps a
     flat edit back to the text. Its code takes the test of a closed fold and the
     caret as arguments, so `TextFolding` of a text reads the cell of each fold as
     before.
   - The drawing gets only the lines that a fold shows, so folded lines are not laid
     out. Their print is still computed (decision 14).
   - The example `syntax_node_view`: one node in two views at three places, view A
     folded and view B open with its caret.

   Limits: the view chain draws no gutter, so no triangle shows: a fold opens by a
   click on its placeholder or by Ctrl+., and closes by Ctrl+. only. The cell
   `collapsed` of the content and `TextFolding` of a text stay for the old chains.

   The shape:

   ```
   documents                          projection of a place
   VerticalLayout                     ChainingProjection(
   ├ [1] SyntaxNodeView A ──┐             RecursiveProjection(ViewingProjection(SyntaxToText(text_folds = true))),
   ├ [2] SyntaxNodeView B ──┼─ node       TextFolding(),
   └ [3] SyntaxNodeView A ──┘             RecursiveProjection(TypeDispatchingProjection(
   A.children, B.children: the views         TextView  => TextViewToGraphicsCanvas(),
   of the leaves, by identity               TextBlock => TextBlockToGraphicsCanvas(; measure))))

   stage 1  A  → TextView(T, caret of A through M, closed folds = the fold of each closed view)
   stage 2     → TextView(T without the lines of those folds, caret through the kept lines)
   stage 3     → [band, drawing of the shown lines, caret]
   ```

   Tests: `test_syntax_node_view()` 41, which records the documents that the stage
   prints (only views: the three of the places and the six of their children) and
   folds view A, then view B by Ctrl+., and opens view A by a click on its
   placeholder; the tests of steps 1 and 2, the folding, gutter, numbering, syntax
   and text tests and the printer walk of every platform example 154209;
   `test_json()` 239. The printer walk and the REPL walk of the example give no
   error.
4. [x] **A JSON string and its view**, through `ViewingProjection(JsonToSyntax())`.
   Tests: `test_json_to_syntax()`.

   Done 2026-10-21. What it made:
   - `JsonStringView` in `source/domain/json/JsonView.jl`, with
     `make_content_view(::JsonString)`. A viewing step of `JsonToSyntax` prints it
     as the `SyntaxLeafView` of the leaf of the string, and the viewing step of
     `SyntaxToText` prints that as a `TextView`. `JsonStringToSyntaxLeaf` and
     `SyntaxLeafToText` do not change.
   - A viewing step maps through the projection that its content IO map names, as
     the table of a stage does: the map of the table itself is ambiguous for a
     template IO map.
   - The example `json_string_view`, on the skip list of the caret sweep beside
     `layout`.

   The shape:

   ```
   JsonStringView A ── ViewingProjection(JsonToSyntax())  ──► SyntaxLeafView(leaf of the string)
                    ── ViewingProjection(SyntaxToText())  ──► TextView(text of the leaf)
                    ── TextView => TextViewToGraphicsCanvas ──► [band, drawing, caret]
   ```

   Limit: the keys of `@gestures JsonDocument` that replace a selected node with a
   node of another kind (`n`, `[`, a digit) do nothing on a view of a root string.
   A view type belongs to one content type, so the replace must also replace the
   view, and a root content shared by two views has no place of its own before step
   6.

   Tests: `test_json_string_view()` 24; `test_json()` 263; the view, syntax and
   folding tests and the printer walk of every platform example 155567. The
   printer walk and the REPL walk of the example give no error.
5. [x] **A JSON array and its view**, which holds the views of its elements; the dead
   `collapsed` fields of the JSON types go. Tests: `test_json()`,
   `test_example(json_example)`, `test_click_roundtrips()`.

   Done 2026-10-21. What it made:
   - The views of JSON in `JsonView.jl`: the abstract `JsonView`, and
     `JsonNullView`, `JsonBoolView`, `JsonNumberView`, `JsonStringView` and
     `JsonArrayView`, whose `elements` hold the views of the elements and whose
     `collapsed` is its fold.
   - R keeps the IO map of each child view that it prints. The output view of a
     compound is `make_content_view(content, children)` over the output views of the
     steps of its children, so the view tree of the next domain carries the state of
     the child views, such as their folds; `map_view_state!` of a `SyntaxNodeView`
     takes the fold of the view that the step printed.
   - `make_content_edit`: an edit that the key table of a view makes with the
     helpers of its content goes through the view. Each write of a value goes below
     `.content`, because the child fields of a view hold views; the written value
     keeps no caret; the caret stays a path of the view, which the view of the new
     part takes. `@gestures JsonView` replaces the element that the caret names with
     one of another kind; `@gestures JsonArrayView` appends an element to the
     innermost array around the caret. The table of the root view walks the caret
     path to that array, as the table of a compound of the syntax walks its tree.
   - `ToggleFoldOperation` reads its path by its steps alone: a stage that maps it
     back types it with the nodes of its content.
   - The `collapsed` fields of `JsonArray`, `JsonObject` and `JsonObjectEntry` go.
     No code read them.
   - The example `json_array_view`.

   Facts: a comma inside a string types a comma, as now, because the text stage
   reads the key first; the comma of the array fires where the text declines it,
   such as on a whole element.

   Limits: objects, entries and insertions have no view yet. A new element, a
   `JsonInsertion`, prints as content, and the caret of its array view names it
   whole. The recorded precompile statements (`package/*/precompile/*.txt`) name the
   types before this plan and must be recorded again before a landing.

   The shape:

   ```
   JsonArrayView A { content = array, elements = [JsonStringView, JsonNumberView, JsonArrayView], collapsed }
     ── ViewingProjection(JsonToSyntax())  ──► SyntaxNodeView(node, children = the outputs of the element steps)
     ── ViewingProjection(SyntaxToText(text_folds = true)) ──► TextView(text, closed folds of the views)
     ── TextFolding() ──► TextView(the shown lines)
     ── TextView => TextViewToGraphicsCanvas ──► [band, drawing, caret]
   ```

   Tests: `test_json_array_view()` 34; `test_json()` 297; the view, syntax and
   folding tests and the printer walk of every platform example 155585;
   `test_example(json_example)` and `test_click_roundtrips()` 7691, in a fresh
   process. The printer walk and the REPL walk of the example give no error.
6. [x] **Places**: the owner's example of one JSON file, two views and four places,
   where a tab holds a view or the view of a part (decision 15); the live flag of a
   place (decision 16), with a test that only the place on the path from the root
   draws a live caret and that every other place of the view draws the same
   position dormant; the three pastes of decision 17.

   Done 2026-11-14. What it made:
   - **No place type.** The example `json_view_places` is a vertical layout of four
     places: view A, the view of the nested array of view A, view B and the view of
     the nested array of view B. The place of a part holds the child view itself.
   - **The live flag of a place**, in the kernel:
     - `is_live_place(ctx)` and `with_live_place(ctx, is_live)` in
       `PrinterContext.jl`. The flag is a function in the property `:live_place` of
       the context, and no cell: a computation that calls `is_live_place` reads the
       selection cells of the documents above the place, so it follows the selection.
     - `make_child_context(ctx, parent, steps...)` and
       `make_element_context(ctx, parent, index, make_steps)` give the child the
       flag: the place of the parent is live, and
       `has_live_selection_below(parent, steps)` of the selection layer says that
       the live path of the parent goes on into the child. A parent with no
       selection field gives its flag as it is.
     - `map_selection_forward` takes `live`, and `make_output_path_cells` and
       `set_output_path_computations!` take `context`: the image of a live selection
       is a dormant one when the place is not live.
   - **The flag in the views.** A step of `ViewingProjection` gives its context to
     the paths of its output view. `ViewRecursion` tells the child view from the
     view, and not from the content that the content projection names as the parent:
     the caret is state of the view. `TextViewToGraphicsCanvas` draws a live caret
     when the stored state and the place both say live.
   - **The three pastes.**
     - `make_sibling_view(view)`: a second view of the same content, with the folds
       of the view and its caret as a dormant one, which the selection of the new
       view wakes. The views of the children take the state of the views of the
       children, in their order.
     - `copy_document(policy, view)`: a copy of a view is a new view of the copy that
       the policy makes of its content, because the child fields of a view follow
       the content by identity and a copy of their cells does not. The duplicate of
       a view (`make_document_duplicate`) is a sibling view.
     - `make_pasted_document(stored)` of the clipboard: what a paste puts in for the
       stored document, the document itself, or a sibling view for a stored view.
       It lives in the clipboard slice, because the projection slice must not use
       the domain slice.
     - The gesture `:paste_same_view`, "Paste the same view", on Ctrl+Alt+V: the
       stored document itself. A note of the view of a part and this paste give a
       place of the part.
     - A view owns no place that takes a pasted value
       (`is_admitted_by_declared_type` of a view answers `false`), so a paste and a
       cut do not write into a view. A paste replaces a view at its place, and a cut
       takes it from its place.
   - **A fix of the selection walk**, in the kernel. A write of the stored path wrote
     no cell, so a document that a write of a value put on the path, in the place of
     one of the same type, kept no part of the path, or a dormant one. A view that a
     paste put over a view was not live. `_repair_selection_chain!` gives each
     document below its part, from the first that does not hold it; while each
     holds its part, it writes no cell.
     The fault is one of the storage of a path and of no view: with two plain
     documents, the new one stored `nothing` after the two writes of a paste. The
     owner accepted the change (2026-11-14). The cause stays: each document keeps
     its part of the path and each print reads that part; step 8 takes the parts
     from the text, syntax and JSON types, and the views and the containers keep
     theirs.

   Facts:
   - A path to a place that holds a view with a dormant caret wakes the caret. A
     second write of the path, to the view that is then live, selects the view as a
     whole. A person selects a whole view from inside it, with the keys of the tree.
   - The copy of a stored view keeps the dormant caret of each child view, and no
     caret of the view itself.
   - The cost of the flag: one child context with a parent document takes 455 ns
     and 1216 bytes without the flag, and 601 ns and 1840 bytes with it. It is
     below 0.1 % of the print and the walk of the examples `json`, `layout`,
     `table` and `widget`.
   - In a real editor with a headless backend, the flag goes through every
     container of a window: the path of the caret of the example is
     `.content.content.content.content.windows[1].content.content.children[1]…`,
     and only the place on it draws a live caret.

   Limits:
   - The prints of the chains with no view do not use the flag: about 126 calls of
     `make_output_path_cells` and `set_output_path_computations!` in 64 files give
     no context. A document with no view at two places draws a live selection at
     both, as before.
   - A paste onto a part inside a view is refused. It is an edit of the content
     through the view, with a path of the view and a value that is content.
   - The state copy of a sibling view visits every node of the view tree.
   - The replace of a root content by a key of another kind still does nothing
     (the limit of step 4).

   The shape:

   ```
   VerticalLayout [ view A, view A .elements[3], view B, view B .elements[3] ]
     the context of each child carries the live flag: the place of the layout is live,
       and the live path of the layout goes on into this child
     view A at place 1 and its part at place 2 store one caret; place 1 or place 2 draws it live

   Ctrl+C, Ctrl+V      copy_document(ClipboardCopyPolicy(), view)  then  make_sibling_view(stored)
   Ctrl+N, Ctrl+V      the view itself                             then  make_sibling_view(stored)
   Ctrl+N, Ctrl+Alt+V  the view itself                             then  the stored view itself
   ```

   Tests: `test_json_view_places` (four places: only the place on the path from the
   root draws a live caret, and each other place of that view draws the same
   position dormant) and `test_json_view_pastes` (the three pastes, a paste over a
   view, a cut of a view); a testset each in `TextViewTest`, `ClipboardTest` and
   `SelectionTest`, and one in `test_json_string_view`. The suites of the kernel,
   of JSON, of the data frames and of the platform, with their layer guards:
   175079 pass, 7 broken, which no marker of this step adds, and no failure. The
   naming guard passes. A check in a real editor with a headless backend, which is
   not in the repository: 9 of 9; it found the fault of the selection walk.
7. [x] **Composition across domains**: a JSON part of a Markdown document, its view
   inside the Markdown view and at a place of its own. Tests: `test_markdown()`.

   Done 2026-11-14. What it made:
   - **The field `viewed`** (decision 19). The eight view types of the text, of the
     syntax and of JSON keep what they show in `viewed`. `get_edited_field` of a
     view answers `:viewed`, and an edit through a view goes below `.viewed`. A
     viewing step refuses a view whose content has a field `viewed`, with an
     `ArgumentError`. The check runs at the print of the view and not at the
     definition of its type, because a type has no hook at its definition.
   - **The views of Markdown** in `MarkdownView.jl` (decision 18): the abstract
     `MarkdownView`, and `MarkdownRootView`, whose `elements` hold the views of the
     blocks, `MarkdownHeadingView` and `MarkdownParagraphView`, whose `content`
     holds the views of the inline nodes, and `MarkdownTextView`. They have no key
     table, because the four content types have none.
   - **The composition.** A view makes the view of each child with
     `make_content_view`, so the view of a `MarkdownRoot` holds a `JsonArrayView`
     for a JSON array among its blocks. No Markdown code names JSON, and no JSON
     code names Markdown. The stage of the syntax of the example gives a node to
     the table of its domain: `MarkdownDocument => MarkdownToSyntax()`,
     `JsonDocument => JsonToSyntax()`, and `Vector{Cell} => CopyingProjection()`,
     which each of the two tables has.
   - The example `markdown_json_view`: the view of the document at one place and
     the view of its JSON part at a second place. It lives in the umbrella example
     package, and its test `test_markdown_json_view()` in the umbrella test package,
     because they name two domains. `test_markdown_view()` of the Markdown suite
     tests the four views with no other domain.

   Facts:
   - A typed character in the heading, in the paragraph and in a string of the
     JSON part edits the content through the view of the document, and the caret
     stays on the view. The text stage reads these keys.
   - The JSON part has one caret and one fold at its two places, and only the
     place on the path from the root draws the caret as a live one. A second view
     of the document has a view of the JSON part of its own.
   - The root of Markdown has no fold in its text: its node has no indentation, so
     no line carries a fold. So `MarkdownRootView` has no fold field.

   - **The keys along the live caret** (decision 20). A viewing step gives a key
     that no later stage took to `read_gesture_outward`, with the steps of the
     live caret of its view that lead to the deepest view on it
     (`_find_caret_view_steps`). Before, only the view at the root of the place
     read the key: a comma on an element of the array gave no operation inside the
     view of the document, and appended an element at the place of the part alone.
     Now the view of the array reads the comma at both places. The key tables of
     the JSON views and of the syntax views did not change: a table that walks the
     caret of its view answers the same when a deeper view of its kind is asked
     first.

   More facts, of the keys:
   - In a tree of syntax views, the view of the leaf that holds the caret reads
     Ctrl+Alt+Home before the view of the node, and selects the leaf. The view of
     the node reads it when the caret is on the node itself. Before, the view at
     the root read it and selected the root node.
     The description of the key of a node view stays "Select the root node",
     as in the key table of a node; a view of an inner node that reads the key
     selects its own node.
   - A comma in the paragraph, beside the JSON part, types a comma: the view of the
     array is not on that caret.
   - A place draws the caret that the path of its own view names. When the caret
     of the view of the document is in the heading and the live caret is in the
     place of the part alone, the place of the document draws its dormant caret in
     the heading, and not the caret of the part.
   - A listing of the keys joins the tables of the views on the caret, by the rule
     of `read_gesture_outward`. No test reads such a listing.

   Limits:
   - 13 Markdown types have no view: a node of one of them prints as content, and
     the caret of the view above it names it only as a whole.
   - Only the source style of `MarkdownToSyntax` is tested with views.
   - The dead `collapsed` fields of the Markdown content types stay.
   - The design document of Markdown gets the views in step 9, with the other
     guides.

   The shape:

   ```
   MarkdownRoot [ MarkdownHeading, MarkdownParagraph, JsonArray ]        the content, held once
   MarkdownRootView { viewed = root, elements = [MarkdownHeadingView, MarkdownParagraphView, JsonArrayView] }
     MarkdownHeadingView   { viewed = heading,   content = [MarkdownTextView] }
     MarkdownParagraphView { viewed = paragraph, content = [MarkdownTextView] }
     JsonArrayView         { viewed = array,     elements = [JsonStringView, JsonNumberView], collapsed }

   VerticalLayout [ the view of the document, its .elements[3] ]        two places, one JSON view

   MarkdownRootView ── ViewingProjection(MarkdownDocument => MarkdownToSyntax(), JsonDocument => JsonToSyntax())
                         ──► SyntaxNodeView(node of the document, children = the outputs of the steps of the blocks)
                    ── ViewingProjection(SyntaxToText(text_folds = true)) ──► TextView(text, closed folds of the views)
                    ── TextFolding ── TextView => TextViewToGraphicsCanvas ──► [band, drawing, caret]
   JsonArrayView at the second place prints through the same stages.
   ```

   Tests: `test_markdown_view()` in `test_markdown()` (the four views, two views of
   one document, a caret and a typed character in the paragraph and in the
   heading, a type with no view) and `test_markdown_json_view()` of the umbrella
   (the view of the part inside the view of the document, one caret and one fold
   at two places, a typed character in each part); a testset in `test_text_view()`
   for the check of the field `viewed`; the printer test of the example. With
   `test_markdown()`, `test_json()`, the view tests, the clipboard tests and the
   layer guard of the platform: 3482 pass, no failure, with the keys along the
   caret: a comma and a replace key of the JSON view inside the view of the
   document, and the order of the views in `test_syntax_node_view()`. The naming
   guard passes. A check in a real editor with a headless backend and real key
   events, which is not in the repository: the example of this step 9 of 9, and
   the example of step 6 again 9 of 9.
8. **The selection fields go** for the text, syntax and JSON types (decision 2).
   Not a step of this plan: it moves to a later plan (decision 21).
9. [x] **The guides.** `concepts.md`, `engineer-tour.md`, `architecture-rules.md`,
   `selection.md`, `projection-system.md`, `text.md`, `syntax.md`, `json.md`,
   `markdown.md`; the plan moves to `plan/done/`.

   Done 2026-11-15, as step 4 of `one-text-view-keeps-the-look-and-the-caret.md`,
   which holds the record. The guides of the widgets and of the clipboard follow
   too.

## Not in this plan

The other domains; they follow the pilot one at a time. The navigator keeps its
views of pages (`a-view-document-keeps-the-state-of-one-view.md`) until a step
reaches its pages. Printing a document once for several places is the tentative
plan of decision 9. The text of a node as a structure of regions, which a closed
fold skips with no print (decision 14).
