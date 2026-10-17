# A view keeps its selection and its folds

Status: LATER. A plan for after `a-view-document-keeps-the-state-of-one-view.md`.
The JSON pipeline is the pilot. No step has started.

## The ask

The owner, 2026-10-18: "If backward compatibility was not an issue, how would you
design this? I mean even the json domain contains the selection and the collapsed
state, maybe it would have been better to put this info the view then we can have
different collapse and selection per view. [...] We should also think about how it
can be projected towards the syntax domain. I have the feeling that this is all
related to where the selection should be stored. Another question is it the
navigator should really work with the selection or it's just a path independent of
selection?"

After the answer: "I agree it's D1, but also write the other plan which will be done
later. Json pipeline will be the pilot."

## What the code does now

The facts for the JSON pipeline, found 2026-10-18:

- **The chain.** A JSON document in a tab draws through `JsonToSyntax` (a template
  projection, `JsonToSyntax.jl`), then the syntax dispatch and `SyntaxToText`, then
  `TextToGraphics` (`SyntaxNatural.jl`). The JSON chain has no `TextFold`: only Julia
  sets `text_folds = true`.
- **The selection is stored along the documents.** `@document` adds the fields
  `selection` and `mouse_target` to about 545 document types
  (`DocumentMacro.jl`). A selection is one path from the root of the window, and
  each document on the path keeps the rest of the path below it
  (`_set_selection_walk!`, `SelectionDefaults.jl`). `_sync_selection!` writes only
  the cells that change; a move of the caret in one leaf changes the two cells of
  one range step and no `selection` cell (`PrinterLocalityTest.jl`). Each projection
  maps the selection forward into computed cells of its output
  (`make_output_path_cells`, `OutputPaths.jl`).
- **Two views of one document share the caret.** The caret is a cell of the
  document, so two pipelines over one document show the same caret
  (`engineer-tour.md`: "they share the cells").
- **The fold of JSON is a cell of each print.** `JsonArray`, `JsonObjectEntry` and
  `JsonObject` declare `collapsed`, and no projection reads it: the templates make
  each `SyntaxNode` with a fold of its own, and the entry template passes `false`.
  A click on the ellipsis, or Ctrl+., answers `ToggleCollapseOperation` on the
  syntax node; it is self-contained and reaches no JSON node. So two tabs of one
  JSON document fold apart, and a new print of a part loses its fold. A `.pred`
  save writes the JSON `collapsed`, which stays `false`. Markdown, YAML, XML and
  reStructuredText declare the same dead field.
- **No test** opens one JSON document in two tabs, and no test folds a JSON document
  through `JsonToSyntax`.
- **The navigator** keeps its address apart from the selection, in its own field.
  Each visit also keeps the selection that the person had when they left the page,
  because the selection lives on the content.

## The model

- **The content keeps what a thing is**, and no selection and no fold. A save writes
  only the content.
- **Each view keeps its own state for each place that it shows**: its selection, its
  folds, its scroll. It keeps them in a mirror of the places that it reached: a node
  for each place, made when the view reaches the place, as the `_TreeEntry` of a tree
  is now, but a document. Each node of the mirror holds the selection tail of its
  place, so a move of the caret still writes only the cells on its path.
- **The editor keeps one focus path**: window, pane, tab, the view that has the focus.
  The live selection is the selection of that view, so the rule "one selection, keys
  follow the root path" stays. Each other view keeps the selection that it had, so a
  tab that comes back shows its caret where it was.
- **The state is keyed in the coordinates of the content**, by the node of the
  content, and kept at the top of the chain, in the view. Each projection maps it
  forward, as it maps the selection now: `JsonToSyntax` reads the fold of a node
  from the view, and the fold of the syntax node follows it. A state with no content
  counterpart is keyed by its origin, which the IO map gives.
- **The navigator keeps addresses.** A visit is an address and a view; the selection
  in a page belongs to the view of the page. The paths of the navigator go through
  its view (D2 of the plan before this one), and the computed selection cell of a
  view (D1) becomes a stored one.

## The pilot: the JSON pipeline

The pilot takes one domain through the whole model, so the cost and the keys are
known before another domain follows. A domain that is not migrated keeps its fields
and works as now.

## Questions for the owner

- **Q1. The key of a place.** (a) The identity of the content node: a state stays at
  its node when another node comes before it, and a new parse of the text, which
  makes new nodes, loses it. (b) The path of the node: a state survives a new parse,
  and moves at an insert before it. My recommendation is (a) for JSON, because a
  JSON document is edited as a structure, and a new parse is a new document.
- **Q2. How a content type drops its selection.** (a) An option of `@document` that
  adds no `selection` and no `mouse_target`. (b) The fields stay, and no write
  reaches them. My recommendation is (a): a field that nothing writes is the dead
  state that the JSON fold is now.

## Steps

Each step is one or more commits with its tests, in a worktree, with a check of
`SEALING.md` before each edit of a kernel file. Mark each step done here.

1. [ ] **Tests that state the behaviour now.** One JSON document in two tabs: the
   fold of one tab, the caret of each; a fold through `JsonToSyntax` and a new print
   of the part. Each wanted behaviour that the code does not have yet is a
   `@test_broken` with its `# @broken:` reason. Tests: `test_json()`,
   `test_syntax_to_text()`.
2. [ ] **The JSON view and its mirror.** `JsonView(json)` with a node for each place
   that it reached, keyed by Q1, and `make_document_view` of a JSON document. A tab
   shows the view of its content as a navigator does (the plan before this one), so
   two tabs of one document are two views.
3. [ ] **The folds move into the view.** `JsonToSyntax` reads the fold of a node from
   the view, and the fold cell of the syntax node is the cell of the mirror node, so
   a fold lasts across a new print and stays in its view. The dead `collapsed` fields
   of the JSON types go. Tests: the broken folds of step 1 pass.
4. [ ] **The selection moves into the view.** The JSON types drop their selection
   (Q2); each mirror node keeps the selection tail of its place; the focus path goes
   through the view. `JsonToSyntax` and the template wiring read the selection from
   the mirror. Tests: the broken carets of step 1 pass; `test_example(json_example)`,
   `test_json_placeholder_navigation()`, `test_json_mouse_target()`,
   `test_click_roundtrips()`, `test_selection_localities()`.
5. [ ] **The navigator goes through its view.** The paths of a navigator go through
   its view (D2), the computed selection of a view becomes a stored one, and a visit
   keeps its view in place of its selection. Tests: the navigator suites,
   `test_document_tree()`.
6. [ ] **The guides.** `architecture-rules.md` (a view keeps its selection and its
   folds), `concepts.md` (selection), `engineer-tour.md` (two live views),
   `json.md`, `selection.md`; the plan moves to `plan/done/`.

## Not in this plan

The other domains with a fold or a selection on their content; they follow the
pilot one at a time.
