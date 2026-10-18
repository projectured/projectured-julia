# A view refers to content that the editor holds once

Status: LATER. The JSON pipeline is the pilot. No step has started.

## The ask

The owner, 2026-10-18, after `a-view-document-keeps-the-state-of-one-view.md`:

- "If backward compatibility was not an issue, how would you design this? I mean
  even the json domain contains the selection and the collapsed state, maybe it
  would have been better to put this info the view then we can have different
  collapse and selection per view. [...] We should also think about how it can be
  projected towards the syntax domain. I have the feeling that this is all related
  to where the selection should be stored."
- "Json pipeline will be the pilot."
- "I wonder if we should also separate the content and the view projections by
  repeating the separation of content and view in the syntax domain and the text
  domain as well. [...] it would allow editing text or syntax in itself with using
  multiple views the same way. Plus, don't forget that content and view should
  combine domains, for example, json and xml in markdown, etc."
- "I think you are wrong on needing a new mechanism to find the content. I believe
  from the main editor loop's point of the content and the view is just the same.
  So we should find a way of building the document and projection composites of
  the editor in a way the gives this structure without introducing the separate
  notions of content and view into the projectional nature of the editor. I'm not
  even sure if we should keep the automatic addition of selection fields to
  documents. Selection, content and view are not special cases in the projectional
  sense."

## What the code does now

The facts for the JSON pipeline, found 2026-10-18:

- **The chain is printed once for each place.** A JSON document in a tab draws
  through `JsonToSyntax`, then the syntax dispatch and `SyntaxToText`, then
  `TextToGraphics` (`SyntaxNatural.jl`), and each tab prints its own chain. Two tabs
  of one document compute its syntax and its text twice.
- **The selection is stored along the documents.** `@document` adds the fields
  `selection` and `mouse_target` to about 545 document types (`DocumentMacro.jl`).
  Each document on the selection path keeps the rest of the path below it
  (`_set_selection_walk!`, `SelectionDefaults.jl`). A move of the caret in one leaf
  changes the two cells of one range step and no `selection` cell
  (`PrinterLocalityTest.jl`). So two views of one document share the caret.
- **A reference is made of cells.** `ConcreteReference` is a `@cell_struct` of its
  type, its head and its tail (`ReferencePath.jl`), so the tail at each depth is a
  cell of its own.
- **The fold of JSON is a cell of each print.** The JSON types declare a
  `collapsed` field that no projection reads; the fold that a person makes is a
  cell of the `SyntaxNode` that each print makes, so it is lost when that part
  prints again. A `.pred` save writes the dead field.
- **No test** opens one JSON document in two tabs, and no test folds a JSON
  document through `JsonToSyntax`.

## The model

Nothing in it is a new kind of thing for the editor. Content, view and selection
are documents and references, and the composites of documents and of projections
give the structure.

1. **The editor document holds each content document once.** A view is an
   ordinary document that refers to a content document and keeps its own state as
   references into it: the caret, the folds, the place of a scroll. A tab holds a
   view. Two tabs of one JSON document hold two views of the one document.
2. **The projection of the editor prints its document in stages.** Each stage
   takes the whole editor document that the stage before it made, and makes the
   next one: it prints each content document one domain further, such as JSON to
   syntax and syntax to text, and it maps the references that each view holds with
   the reference maps that every projection has. A content document is in one place
   of the editor document, so each stage prints it once, and each view reads that
   one print through its references. Nothing finds the content: it is where the
   document graph puts it.
3. **The stages that depend on a view print each view**: the layout and the
   graphics, which follow the size of the viewport. They read the text of the
   content in their own input, through the references of the view.
4. **The selection is a reference that a view holds.** The editor keeps one focus
   path, from the window to the view that has the focus, and keys follow it, as now.
   A print node reads the tail of the reference at its own depth, which is a cell,
   so a move of the caret recomputes only the nodes on its path, as now, with no
   field on each document.
5. **Each piece of view state is stored once, where it starts.** A fold of a JSON
   node is a reference that the view holds at the JSON level; the stages below map
   it into a fold of a syntax node and a hidden range of lines. A fold of a range of
   text that is no JSON node is a reference that the view holds at the text level.
   A reference is moved by an insert before it (`an-insert-moves-the-paths-after-it.md`),
   so a fold stays at its node.
6. **Content and view combine across domains.** A Markdown document can hold a
   JSON document as a part. The view of the Markdown document then holds the
   references into the JSON part too, and each stage prints the JSON part in its own
   domain. Two tabs of the Markdown document fold the JSON part apart.
7. **A text and a syntax document are content as any other.** A text file in two
   tabs is one text document and two views; the stages print it once.

## What is not known yet

- **A stage of the whole editor document.** Each stage must print each content
  document one domain further and leave the rest of the editor document as it is,
  and it must reuse the print of each part that did not change, as a projection
  reuses its children now.
- **How a print node gets its tail.** The view document is the input of the
  projection that prints it; that projection walks its content with the reference
  and gives each part the tail at its depth. Whether the template engine can give a
  template the tail of its node in this way is not checked.
- **The cost of state as references.** Every fold and every caret is a reference
  that each stage maps forward. The prototype measures it.

## Questions for the owner

- **Q1. Where a content document lives in the editor document.** (a) In a list of
  the window that holds each content document once, and each tab holds a view of
  one of them. (b) In the tab of its first view, and the other views refer to it
  there. My recommendation is (a): a content document then outlives a tab, and no
  tab is a special one.
- **Q2. The `selection` and `mouse_target` fields that `@document` adds.** (a) They
  go for a domain when its views hold their references, and then from the macro
  when no domain reads them. (b) They stay. My recommendation is (a).
- **Q3. The order of the work.** (a) The prototype first, then the pilot from the
  bottom up: text, syntax, JSON, then JSON in Markdown. (b) The pilot from the top:
  JSON first. My recommendation is (a): each level then exists before the level
  above it maps into it.

## Steps

Each step is one or more commits with its tests, in a worktree, with a check of
`SEALING.md` before each edit of a kernel file. Mark each step done here. The plan
`an-insert-moves-the-paths-after-it.md` comes first, because view state that is a
reference must move at an insert.

1. [ ] **The prototype.** In a test of the platform, with no change of `main`: an
   editor document that holds one text document once and two views of it, a
   projection of two stages (the text, then the graphics of each view), and the
   caret as a reference of each view. It measures: two carets, one print of the
   text for both views, and the cells that a move of the caret recomputes. The
   facts go into this plan, and the owner decides the next steps from them.
2. [ ] **The text domain.** A text document in two tabs on the real editor: each
   tab a view that holds its caret, its scroll and its folds; the stages print the
   text once. Tests: the text suites, `test_selection_localities()`.
3. [ ] **The syntax domain.** A syntax document as content, with its views; the
   stage from syntax to text maps their references. Tests: `test_syntax()`,
   `test_syntax_to_text()`, `test_collapse_roundtrip()`.
4. [ ] **JSON.** A JSON document in two tabs; the stages print JSON to syntax to
   text once; a fold and a caret of each view. The dead `collapsed` fields of the
   JSON types go. Tests: `test_json()`, `test_example(json_example)`,
   `test_click_roundtrips()`.
5. [ ] **JSON in Markdown.** A JSON part of a Markdown document, folded apart in
   two tabs. Tests: `test_markdown()`.
6. [ ] **The fields of the selection** (Q2): the JSON, syntax and text types drop
   them; the macro keeps them for the domains that are not moved yet.
7. [ ] **The guides.** `concepts.md` (selection), `engineer-tour.md` (two live
   views), `architecture-rules.md`, `selection.md`, `json.md`, `syntax.md`,
   `text.md`; the plan moves to `plan/done/`.

## Not in this plan

The other domains; they follow the pilot one at a time. The navigator keeps its
views of pages (`a-view-document-keeps-the-state-of-one-view.md`) until step 6
reaches its pages.
