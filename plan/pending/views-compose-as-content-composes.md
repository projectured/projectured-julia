# Views compose as content composes

Status: LATER, decided but for the questions of step 6. The JSON pipeline is the
pilot, built from the bottom up. No step has started.

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

## The model

1. **Each content type has a view type.** A view is a tree of view documents that
   mirrors its content tree: `JsonArrayView` holds the views of the elements of its
   `JsonArray`. Views compose as content composes, so a new domain adds its pairs of
   content and view, and they combine with the pairs that exist.
2. **View types are shared by shape.** A leaf view keeps a caret, for
   `JsonString`, `JsonNumber`, `JsonBool` and `SyntaxLeaf`. A compound view keeps a
   fold, the tail of the caret and the views of its children, for `JsonArray`,
   `JsonObject` and `SyntaxNode`. A text view keeps a caret, a scroll and the hidden
   ranges of a `TextBlock`. A content type gets a view type of its own only when its
   view keeps other state.
3. **The selection is a tail on each view node.** Each view node keeps the rest of
   the selection path below it, the same chain as now, so a move of the caret
   writes as few cells as now. View types declare `selection` as an ordinary field;
   content types lose the field that `@document` adds.
4. **The content chain is printed once; the views are mapped through it.** A
   content document is in one place of the editor document, where the composition
   puts it, so each content projection prints it once for all its views. A view
   projection maps each view node through the reference maps of the content
   projection, as the forward map maps the selection now. It has code of its own
   only where the shape changes: the folds of a tree of syntax views become the
   hidden ranges of one text view.
5. **A view tree follows its content by identity, lazily.** A view makes the view
   of a part when it first reaches the part; a part that goes takes its view with
   it. A fold then stays at its node across an insert before it; the selection tails
   are index paths, which `an-insert-moves-the-paths-after-it.md` moves.
6. **Sharing is by reference, at every level.** Two views of one content are two
   view trees over it, each with its own caret and folds. A view shown at two places
   is two places that refer to the one view tree, or to one subtree of it, so they
   share its caret and its folds. A place is printed by the focusing projection, and
   the part that it shows is a field of the place.
7. **Composition crosses domains.** A view of a Markdown document holds the view of
   its JSON part, and that JSON view can also have places of its own elsewhere.
8. **The projection of the editor prints in stages.** Each stage takes the whole
   editor document that the stage before it made, and moves each content document
   and each view one domain further. The layout and the graphics come last, for
   each place, because they follow the size of its viewport.

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
   projections; **view types are shared by shape**; **a view follows its content by
   the identity of the content node** (the owner, 2026-10-18: "Agreed all 3").
5. **The structure is recursive, and features stay** (the owner, 2026-10-18): two
   places of one view share its selection, as two places of one document share it
   now; two views of one content do not; the focusing projection works on views.

## What is not known yet

- **A stage of the whole editor document**, which moves each content and each view
  one domain further and reuses the print of each part that did not change, as a
  projection reuses its children now.
- **How the template engine gives a view its tail.** The templates describe the
  content mapping; the generic view mapping must reach the reference maps that they
  build.
- **The cost of the mirrors.** Each view keeps a node for each place that it
  reached, at each domain of the chain.

## Questions for step 6

- **QA. The state of a view and the state of a place.** My proposal: the view keeps
  the caret and the folds, which its places share; the place keeps its part, its
  scroll and the part under the pointer.
- **QB. A key when the caret of a view is not in the part of the focused place.** My
  proposal: a press in a place moves the caret of its view into the part of the
  place, and a key goes to the caret of the view.
- **QC. The pastes of a view.** A new place of the same view, a new view that starts
  from a copy of the state, or a copy of the content: three commands, or one paste
  whose kind the person picks.

## Steps

Each step is one or more commits with its tests, in a worktree, with a check of
`SEALING.md` before each edit of a kernel file. Mark each step done here. The plan
`an-insert-moves-the-paths-after-it.md` comes first. Each step keeps every pair below
it working, and shows its composition: the content, the views and the output of
each stage, as structures that a person reads.

1. [ ] **Text content and its view.** A `TextBlock` and a text view: one text in two
   views, each with its own caret and scroll, and one view at two places, which
   share its caret. First in a test of the platform with no change of `main`, which
   measures the cells that a move of the caret recomputes; then on the editor.
   Tests: the text suites, `test_selection_localities()`.
2. [ ] **A syntax leaf and its view**, mapped to text through the reference maps of
   `SyntaxToText`. Tests: `test_syntax_to_text()`.
3. [ ] **A syntax node and its view**: the fold of a compound view, mapped to the
   hidden ranges of the text view. Tests: `test_syntax()`, `test_collapse_roundtrip()`.
4. [ ] **A JSON string and its view**, mapped to a syntax leaf view. Tests:
   `test_json_to_syntax()`.
5. [ ] **A JSON array and its view**, which holds the views of its elements; the dead
   `collapsed` fields of the JSON types go. Tests: `test_json()`,
   `test_example(json_example)`, `test_click_roundtrips()`.
6. [ ] **Places**: the owner's example of one JSON file, two views and four places,
   with the focusing projection printing a place; the pastes of QC.
7. [ ] **Composition across domains**: a JSON part of a Markdown document, its view
   inside the Markdown view and at a place of its own. Tests: `test_markdown()`.
8. [ ] **The selection fields go** for the text, syntax and JSON types (decision 2).
9. [ ] **The guides.** `concepts.md`, `engineer-tour.md`, `architecture-rules.md`,
   `selection.md`, `text.md`, `syntax.md`, `json.md`; the plan moves to
   `plan/done/`.

## Not in this plan

The other domains; they follow the pilot one at a time. The navigator keeps its
views of pages (`a-view-document-keeps-the-state-of-one-view.md`) until a step
reaches its pages.
