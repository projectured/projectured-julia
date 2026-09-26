# The assistant reaches a document through a referenced document

> **Status:** pending. Written 2026-09-26.

## 1. The request

In the rehearsals of S2 (`plan/pending/feature-video-screenplays.md`), qwen was asked
"Open a second tab beside the first one with a table of the people in
people.json, sorted by name." It found `open_pane!` and `WidgetTable` in its third
round and then spent the rest of its eight rounds on reaching the people inside
the tab. The owner asked for the code the agent should ideally run, then for the
code it would run "if the API would be good", with an API "not specific to this
problem", and shaped that API over several messages (2026-09-26):

- A type that holds "both the pane document and the reference", so that "you can
  go to the file document with one function call or go to the group with a get
  parent or something". Its name: "It has the wrong name, it's ReferencedDocument.
  A DocumentLocator is a start plus a reference." Both types are wanted.
- "I prefer having it act like the document it locates." It keeps "just a
  reference, it's a snapshot and T" (a type parameter).
- On the file: "we should have a function just a better name. The agent should
  not deal with the complexity." The name agreed: `get_edited_document`.
- "I don't like the generic Julia conversion … A proper shape documentation will
  give that to the agent. Also, the agent can do multiple code rounds to see some
  stuff first like the json file."
- "The rounds can share variables, the agent should know that." The variables are
  named by what they hold and numbered: "names + index, for long term evaluator
  use." The rule goes into the description of `execute_julia_code`, "In the MCP
  tool description".
- "print natural text can take the locator."
- "Make sure the documentation is good enough for the agent to find out."

## 2. What exists

- **Finding a tab.** `find_pane_reference(editor, title)` answers a reference;
  `get_referenced_value(editor, reference)` answers the node. Two calls, two
  results to keep apart.
- **The layers of a file tab.** `PaneTab.content` is a `FileDocument` (a
  `JsonFile`); its `content` is, in the application, an `UndoBuffer`; the
  buffer's `content` is the `JsonArray`. Every layer calls its field `content`.
  `get_file_content(file)` answers the raw field, the `UndoBuffer`, but its
  docstring (`source/serialization/FileProject.jl`) promises "the parsed tree for
  a `JsonFile`" and names the function `content(f)`. The program's own code
  unwraps it: `get_wrapped_document(get_file_content(file))` (`DocumentFile.jl:158`).
  `get_wrapped_document` has a method for each transparent wrapper (a history, a
  clipboard slice).
- **The group of a tab.** No verb answers it. `move_pane!` with a tab as target
  puts the pane before that tab.
- **References.** `Reference` is an abstract type with two concrete subtypes,
  `EmptyReference` and `ConcreteReference`. `ReferenceModule` exports
  `extend_reference`, which adds steps; nothing removes them. A start and a
  reference already travel together in `ReplaceReferencedValueOperation(document,
  reference, value)`, whose `document` is its start (`nothing` for the editor's
  document).
- **JSON.** `source/json/JsonDocument.jl`: `JsonArray(elements)`,
  `JsonObject(entries)` of `JsonObjectEntry(key::String, value::Document)`,
  `JsonString(value)`, `JsonNumber(value)`, `JsonBool(value)`, `JsonNull`. Each
  docstring is one line. No key access on an object. The application does not
  declare these types, so the model's search does not find them.
- **Rounds share their variables.** `execute_julia_code` runs every call at the top
  level of one scratch module per tool set, so a top-level assignment stays bound.
  Nothing tells the model so.
- **What the model reads about `execute_julia_code`.** The tool's description, not
  the docstring: `_execute_julia_code_description(set)` when an API is declared,
  `_WHOLE_SURFACE_DESCRIPTION` when none is (`source/kernel/tool/DefaultTools.jl`,
  not sealed). The MCP server sends the same text (`source/mcp/Mcp.jl:175`). Both
  say "The value of the last expression is described in one line, and shown only
  when it is short", which the landed plan `the-evaluator-shows-a-value-as-the-repl-does.md`
  made wrong: a long value now reaches the model trimmed, with a note.
- **The seals.** `reference/ReferenceInterface.jl`, `reference/ReferenceSearch.jl`
  and `document/DocumentSearch.jl` are sealed (`SEALING.md`); the other files of
  the document and the reference layers are not. An interface file holds only
  declarations (PAR-INTERFACE-DECLARES-ONLY), so a concrete struct and its
  functions go into an implementation file of the layer.
- **The ideal code with today's API** (tested 2026-09-26, as the assistant runs
  it; it opens "People by name" after "people.json" in the same group):

  ```julia
  tab = get_referenced_value(editor, find_pane_reference(editor, "people.json"))
  group = only(search_documents(editor.document, g -> g isa PaneGroup && any(t -> t === tab, g.tabs)))
  people = get_wrapped_document(get_file_content(tab.content))
  rows = [[string(entry.value.value) for entry in person.entries] for person in people.elements]
  sort!(rows; by = first)
  open_pane!(editor, WidgetTable(["name", "age"], rows); title = "People by name", group = group)
  ```

## 3. The ideal code with the new API

The code of S2, as the model would write it after its searches. It ran headless
through `execute_julia_code` on the declared API of the application on
2026-09-26, with the five people of the screenplay, and made the window of the
video. The owner agreed to it on 2026-09-26.

**Prompt 1:** "Open a second tab beside the first one with a table of the people
in people.json, sorted by name." Call 1 looks at the data and keeps what it finds:

```julia
people_tab_1 = find_pane(editor, "people.json")      # ReferencedDocument{PaneTab}
people_1 = get_edited_document(people_tab_1)         # ReferencedDocument{JsonArray}
println(print_natural_text(people_1))
```

The tool answers the JSON text. Call 2 uses the same variables:

```julia
rows_1 = [[person["name"].value, person["age"].value] for person in people_1]
sort!(rows_1; by = first)
table_tab_1 = open_pane!(editor, WidgetTable(["name", "age"], rows_1);
                         title = "People by name", target = get_parent(editor, people_tab_1))
```

"People by name" opens after "people.json" in the same group, with the rows Ada,
Bob, Cleo, Dan, Eve. `people_1` iterates its elements, because `JsonArray` acts as
a vector; each `person` is a `ReferencedDocument{JsonObject}`; `person["name"]` a
`ReferencedDocument{JsonString}` whose reference reaches that entry's value;
`.value` the plain `String`.

**Prompt 2:** "Under the two tabs, add a card with a table of the names and the
ages." One call, which uses `rows_1` again and does not read the file a second
time:

```julia
card_tab_1 = open_pane!(editor, WidgetCard(content = WidgetTable(["name", "age"], rows_1));
                        title = "Names and ages", target = get_parent(editor, table_tab_1),
                        side = :below)
```

The group of the two tabs becomes a stacked split, 50% and 50%, with the card
below. **Beat 4:** one `Ctrl+Z` removes the card and its split, because an open
with `side` is one undo step.

With D10, each `open_pane!` answers
`ReferencedDocument{PaneTab} at .windows[1]….tabs[2]: PaneTab(PrimitiveString("People by name"), WidgetTable(…), nothing)`,
so the model sees the tab, and `table_tab_1` is a target like `people_tab_1`.
Before D10, the answer was the typed path
`::ScreenDocument.windows::CellVector[1]::…::PaneGroup.tabs::CellVector[2]::PaneTab`.

`println(print_natural_text(people_1))` stays here: `print_natural_text` answers
a `String`. The owner decided on 2026-09-26 that a `print_` function writes; the
rename to `print_natural_string` and `make_natural_string` is its own plan,
`a-print-writes-and-a-make-answers.md`, after this one.

Not shown by the headless run: what qwen writes. The system prompt is not changed
(D18) and names the older path, so the rehearsal of Step 6 shows which path the
model takes.

## 4. Decisions

### The two types

- **D1. `ReferencedDocument{T}`: a document with the reference that reached it.**
  Two fields, read with `get_document(x)` and `get_reference(x)`: the node, of
  type `T`, as it was when it was found (a snapshot), and the complete reference
  to it from the root it was found from — for everything the assistant finds, the
  editor's document. `T` is the type of whatever the reference reaches, a document,
  a collection or any other value. It lives in a new implementation file of the
  reference layer, and `ReferenceModule.jl` exports it.
- **D2. It acts like the document it references.** It forwards to its document:
  reading and writing a property, indexing, iteration and `length`. A read that
  answers a document or a collection answers it as a referenced document, with the
  reference extended by the field or the index; a read that answers any other value
  (a string, a number, a `Bool`, `nothing`) answers that value. It does not forward
  `==` or `hash`: a referenced document and its document are two kinds of value.
  Because every property is forwarded, the two fields are read only through
  `get_document` and `get_reference`. `x isa JsonArray` stays false; code that
  checks a type asks `get_document(x)`.
  *Found in Step 4:* the functions a collection answers go to the document too:
  `isempty`, `firstindex`, `lastindex`, `eachindex`, `keys`, `haskey`, `get`,
  `values` and `setindex!`, because the JSON docstrings of D15 tell the reader to
  use `keys(object)` and `get(object, key, default)`. An element of a sequence is
  at its position only when the document reads that position back; any other
  value that iteration or a key answers, such as a `(key, value)` member of a
  `JsonObject`, is found in the document by its identity, and a value the document
  does not hold is answered plain.
- **D3. Its display says both what and where:**
  `ReferencedDocument{PaneTab} at .windows[1]…tabs[2]: PaneTab("people.json", …)`,
  so a model that reads a value knows it holds a referenced document.
- **D4. `DocumentLocator`: a start and a reference.** An address, not resolved:
  `DocumentLocator(start, reference)`, where `start` is the document the reference
  is read from (usually the editor's document, or a carried root as in
  `ReplaceReferencedValueOperation`). `find_referenced_document(locator)` resolves
  it to a `ReferencedDocument`, or answers `nothing` when the reference no longer
  reaches a node. A snapshot is brought up to date with
  `find_referenced_document(DocumentLocator(editor.document, get_reference(x)))`.
  It lives beside `ReferencedDocument`.
- **D5. Functions take a referenced document where they take a document or a
  reference.** A method lifts each function of the declared API: a parameter
  declared `::Reference` receives `get_reference(x)`, any other parameter receives
  `get_document(x)`; the same for keywords. So `print_natural_text(people_1)`,
  `describe_document(x)` and `move_pane!(editor, x, target)` work. `convert` has
  a method to each document type (`get_document`) and to `Reference`
  (`get_reference`), so a referenced document can be stored in a typed field or
  container.
- **D6. Not a subtype of `Reference` or of `Document`.** As a `Reference`, it would
  have to answer every method that code writes for the two concrete references, in
  a layer whose interface is sealed. As a `Document`, the generic document code
  (searches, printer walks, copies, serialization) would treat it as a node of the
  tree, which it is not.

### The functions

- **D7. `find_pane(editor, title) -> ReferencedDocument{PaneTab}` or `nothing`.**
  The tab of that title. `find_pane_reference` stays, for a caller that needs only
  the reference.
- **D8. `get_edited_document(x) -> ReferencedDocument`.** The document that a person
  edits in `x`: for a file tab, the file's own document, through the file and its
  history; for any other tab, what the tab shows; for a file document, a history or
  a clipboard slice, the document inside. It follows the layers until it reaches a
  document that is itself what is edited, and its reference goes through every
  layer. Each layer says which of its fields holds what is edited, through an open
  generic declared in an interface file that is not sealed (the document layer's,
  `DocumentInterface.jl`, is not), with a method in each package that has such a
  layer: the pane tab, the file document, the history, the clipboard slice. A need
  to change a sealed file stops the work and goes to the owner.
- **D9. `get_parent(root, x) -> ReferencedDocument` or `nothing` at the root.**
  The enclosing document, read from `root` at the call: one step up the
  reference, and past each collection on the way (`is_element_collection`, or a
  Julia vector, dictionary or tuple): a tab's parent is its group, a JSON entry's
  parent is its object, an element's parent is its array. `x` is a
  `ReferencedDocument` or a `Reference`. The root is an argument, because a
  referenced document keeps only its reference (D1); the owner chose on
  2026-09-26 that `get_parent` takes a document and an editor. The reference layer
  has `get_parent(document, x)`; the editor layer has `get_parent(editor::Editor,
  x)`, which reads `editor.document` at the call, so it is right after the root is
  replaced. For the same reason `DocumentLocator` has a type parameter for its
  start, and the editor layer adds `find_referenced_document` for a locator that
  starts at an editor: a locator made from `editor.document` would keep the old
  root. Both editor methods are methods of reference-layer functions for the
  `Editor` type, so no new generic function is needed.
- **D10. `open_pane!(editor, document; title, target = nothing, side = nothing)`**
  places the new tab as `move_pane!` places a pane (a group: at its end; a tab:
  before it; with `side`, beside it in a new split) and answers the new tab as a
  `ReferencedDocument`. `duplicate_pane!` answers its new tab the same way. The
  owner agreed on 2026-09-26, after the S2 code of §3.
- **D21. One answer type for a part, and one way to reach its reference.** The
  owner agreed on 2026-09-26:
  - A function that finds or makes a part answers a `ReferencedDocument`.
  - A function that takes a part takes a `ReferencedDocument` or a `Reference`
    (D5).
  - A caller that needs the reference calls `get_reference(x)`. There is no
    second, `_reference`, version of a finder in the public API: it is one call
    away, and two names for one act show side by side in each search.
  - No keyword that changes the answer type: the type would depend on a value,
    each docstring would describe two answers, and a model that does not pass
    the keyword gets the older form. No second verb for the new answer: a model
    picks between two names for one act at random.
  - Not now: `find_pane_reference` and `find_pane_tree_reference` stay declared
    while the system prompt names them (D18). The follow-up is below.
- **D11. `object[key]` on a `JsonObject`** answers the value document of that key,
  and throws a `KeyError` that names the keys the object has when the key is
  missing.
  *Found in Step 4:* `object[key]`, `keys`, `haskey`, `get`, `values` and iteration
  already exist, from `@adapt_map_protocol` in `ForwardProtocol.jl`, and
  `JsonArray` acts as a vector through `@forward_vector_protocol`. The `KeyError`
  names the key only: `ForwardProtocol.jl` is sealed, and a second `getindex`
  method for `JsonObject` would overwrite the method of the macro, which stops
  precompilation. The docstring of `JsonObject` sends the reader to `keys(object)`.

### The documentation the model reads

- **D12. The description of `execute_julia_code`** — what the assistant and an MCP
  client read, `_execute_julia_code_description` and `_WHOLE_SURFACE_DESCRIPTION` —
  and its docstring get this paragraph:

  > Each call runs in the same module, so a variable that one call binds at the top
  > level is still there in every later call. Keep each object that you find or
  > make in its own variable, named by what it holds and numbered: `people_tab_1`,
  > `people_1`, `rows_1`. When you make another object of the same kind, give it
  > the next number, `rows_2`, and do not overwrite the first. Use a variable again
  > in a later call instead of finding its object again.

  The sentence about the last value says what the tool does now: a short value as
  it is; a long one as the Julia REPL shows it, trimmed with a note when it is
  still long.
- **D13. Each new name is found by the words a request uses.** Its docstring
  starts with what it answers, says "Use it to …" in the words of a request, and
  shows one example, because `search_api` with mode "description" ranks by that
  text: `get_edited_document` for "the data of a tab", "what a file tab holds", "the
  JSON of an open file"; `get_parent` for "the group that holds a tab", "the object
  of a field"; `find_pane` for "a tab by its title"; `ReferencedDocument` for "a
  document and where it is"; `DocumentLocator` for "the address of a document".
  Tests assert that these searches answer the name first.
- **D14. The application declares the new names** (`make_pane_api` or a vocabulary
  of its own): `ReferencedDocument`, `DocumentLocator`, `get_document`,
  `get_reference`, `find_referenced_document`, `find_pane`, `get_edited_document`,
  `get_parent`, and the JSON types of D15.
- **D15. The shape of JSON.** The docstrings of the seven JSON types say their
  fields and how to read a value — an array's `elements`, an object's `entries` and
  `object[key]`, a leaf's `value` — and the application declares the types.
- **D16. The guides.** The orientation guide (`guide/orientation`, which the model
  reads first) gets a section "Reach what a tab holds", with the two rounds of §3
  and the rule of D12. `documentation/package/kernel/reference.md` describes the
  two types; the documents of the pane, file format and JSON packages describe
  `find_pane`, `open_pane!`'s `target`, `get_edited_document` and the shape.
- **D17. The docstring of `get_file_content`** says what it answers: the value of
  the `content` field, which the application keeps inside a history, and that
  `get_edited_document` reaches the document itself.
- **D18. The application's system prompt is not changed** (the owner, 2026-09-26,
  for the S2 rehearsals). It names the older path (`find_pane_reference`,
  `get_referenced_value`, `print_natural_text(tab.content)`), which still works;
  whether it names the new one is the owner's choice after Step 6.

- **D22. The model knows from the start that it changes the editor's document
  through a verb or an operation** (the owner, 2026-09-26: "It should not discover
  that fact by seeing a failure, it should know this from the beginning", and "it's
  not like directly editing is forbidden but discouraged because the editor's
  default behaviour will not apply (such as undo, filtering out operations due to
  permissions, transforming operations, etc.)"). A direct write, also one through a
  referenced document (D2), stays possible. Both descriptions of
  `execute_julia_code` say it (`_make_editing_description` in `DefaultTools.jl`):
  the declared one names `replace_referenced_value!` only when the tool set
  declares it, and the whole surface also names `evaluate_operation`. The
  orientation guide says it under "Acting on the document" and shows the S2 edit,
  `replace_referenced_value!(editor, people_1[2]["city"], JsonString("Paris"))`; the
  docstring of `ReferencedDocument` says it in the concepts of the kernel.
  `test_declared_api()` checks both descriptions and that a declaration without
  the verb does not name it; 284 checks pass with the editor, reference, code
  execution, documentation and naming tests.

- **D23. An edit of the assistant inside a document that keeps its own history
  goes into that history** (the owner, 2026-09-26: "yes, that's simpler"), as an
  edit of the person does. So the person undoes it in the tab of the file, and the
  file's history knows the change. Found before the decision:
  `replace_referenced_value!` records its step in the history of the window,
  not in the history of the file. To do.

- **D24. The editing verbs of the editor** (the owner, 2026-09-26: "sounds
  right"). A small set of verbs in the editor layer, not in the pane package,
  next to `get_parent` and the moved `get_referenced_value`:
  - `replace_referenced_value!(editor, part, value)` keeps its name; its general
    part moves to the editor layer, and its checks of a write into a pane tree
    stay in the pane package.
  - `insert_elements!(editor, collection, index, values)` and
    `delete_elements!(editor, collection, index, count)` are new. They pair with
    the kernel operations `insert_elements` and `delete_elements`: the kernel
    function makes the operation, and the verb with `!` runs it through the
    editor.
  - Each takes a `ReferencedDocument` or a `Reference`, as
    `insert_elements!(editor, people_1, 6, [frank_1])`.
  - Each goes through the readers of the editor, so each edit has a line in the
    gesture log and gets the checks and the transforms of an operation (D22).
  - Each records into the history of the document it changes (D23).
  - The orientation guide names them beside the text of D22, and the application
    declares them.

### Not done

- **D20. No `document` binding in `execute_julia_code`** (the owner,
  2026-09-26). The root of the editor can be replaced: by an import, by a load of
  a saved editor, and by a `ReplaceReferencedValueOperation` at the empty
  reference and its undo. A `document` bound once would then read an old tree with
  no error. A binding made again at each call is still stale inside a call, and it
  overwrites a variable that the model named `document` itself, against the rule
  of D12. The functions that need a root take `editor`, which reads the current
  root at the call.

- **D19.** No conversion of a document to plain Julia data: the owner rejected it,
  it is a second shape to learn. A leaf keeps its `.value`: making `object[key]`
  answer the plain value would be that conversion, and would lose the leaf
  document.

## 5. Steps

Each step: tests first where they fit, the change, the narrowest tests that cover
it, and a commit with explicit paths and no attribution line. Work in a worktree of
its own, from `main`. Check each file against `SEALING.md` before editing it.

- [x] **Step 1: the two types.** **Done (2026-09-26).**
      `source/kernel/reference/ReferencedDocument.jl` holds `ReferencedDocument`,
      its forwarding, display and `convert`, `DocumentLocator` and
      `find_referenced_document`; `test_referenced_document()` passes 25 checks,
      and the kernel layering guard accepts the file. Found: `CellVector` is not a
      kernel type (it lives in `source/collection/`), so the kernel knows a
      collection by `Document`, `AbstractVector`, `AbstractDict` and `Tuple`; a
      `CellVector` is a `Document`. A property that is not a field of its document
      has no step a reference can record, so its value is answered plain. A key
      that is neither a position nor a dictionary key is found in the document by
      identity (`search_references`). `get_parent` is done as D9 says, with the
      two editor methods in `source/kernel/editor/Editor.jl`; the kernel test
      covers a part, a reference, a collection, the root and a reference that no
      longer reaches a node, and the editor test a tab, an element of the JSON, a
      new tab at the end of the parent group, and a locator that starts at the
      editor (127 checks with the layering guard and `test_naming()`).
      The step as planned: D1 to D6 and D9 in the reference layer, with
      tests: forwarding of a property, a write, indexing and iteration, and the
      referenced answer for a document and the plain answer for a leaf; the
      display; `convert` to a document type and to `Reference`; a locator resolved,
      and one whose reference no longer reaches a node; `get_parent` of a tab, a
      JSON entry and an element.
- [x] **Step 2: finding and editing.** **Done (2026-09-26).** The seam
      `get_edited_field(node) -> Symbol or nothing` is declared in
      `DocumentInterface.jl` with the default `nothing` in `DocumentDefaults.jl`; its
      methods answer `:content` for a `PaneTab` (pane), an `UndoBuffer` (undo), a
      `ClipboardSlice` and a `ClipboardCollection` (clipboard), and a
      `FileDocument` unless `is_own_content` (serialization, where `FileDocument`
      and `get_file_content` live, in `FileProject.jl`). `get_edited_document`
      follows the seam in the kernel, for a referenced document and for a plain one,
      at most 16 layers deep. Its kernel docstring names the layers as concepts (a
      tab, a file, a history), as PAR-NO-CONSUMER-DOCS allows and as
      `get_wrapped_document` already does; each package's method has its own
      comment. `find_pane` is in `PaneProgram.jl`. `test_referenced_document_editor()`
      passes 13 checks on a real application window; the substrate layering guards,
      `test_naming`, `test_export_collisions` and `test_documentation` pass;
      `test_exports` has 3 failures in `source/help/HelpModule.jl`, which is on
      `main` and not touched here.
      The step as planned: D7 and D8: `find_pane` of a title and of a
      missing title; `get_edited_document` of a file tab reaches the `JsonArray`,
      and its reference evaluates to it; of a tab that holds a widget; of a file
      document and of a history.
- [ ] **Step 3: the pane verbs and the lifted functions.** **In progress
      (2026-09-26).** Done:
      - The lift of D5 is one method for each function, next to the function, and
        no generic mechanism: a macro or a generated method that reads the
        signatures of a function would be a new mechanism. The functions of the
        application API that take a reference or a document: `focus_pane!`,
        `close_pane!`, `duplicate_pane!`, `move_pane!` (either parameter),
        `get_referenced_value`, `replace_referenced_value!` (the reference or the
        value), `describe_document` and `open_pane!` in `PaneProgram.jl`;
        `search_documents` and `get_wrapped_document` in `ReferencedDocument.jl`
        (the reference layer extends the two document-layer generics for its own
        type); `get_file_content` in `FileProject.jl`; `print_natural_text` in
        `NaturalNotation.jl`, which needs `ProjecturedNatural` to bind
        `ReferenceModule`; `export_document` and `write_document_file` in the
        file format package.
      - `open_pane!` and `make_open_pane_operation` take `target` (a `Reference`
        or a `ReferencedDocument`: a group, and the tab goes to its end; a tab,
        and the new tab goes before it) and `side`. `group` stays, as a value;
        `group` and `target` together are refused, and so is a `side` that is not
        one of the four. `side` uses `make_pane_split_operation(tree, group;
        orientation, side, tab)`, which a split of a group already uses: a new
        split takes the place of the target group, or the new group joins the
        parent split when it has that orientation, so no split holds a split of
        its own orientation. The open is one undo step.
      - `test_referenced_document_editor()` passes 44 checks; `test_pane_surgery()`,
        `test_pane_drag()`, `test_application()`, the substrate and kernel
        layering guards, `test_naming()` and `test_export_collisions()` pass.
      - Found: a `CellVector` has no `keys`, so `findfirst` on `group.tabs` throws;
        the test collects the vector first. Not changed here.
      D10, done in this repository (2026-09-26): `open_pane!` and
      `duplicate_pane!` answer the tab they made as a `ReferencedDocument`, with
      its fully typed reference; their docstrings and `pane/pane.md` say so, and
      `ApplicationTest.jl` reads the reference with `get_reference`.
      `test_referenced_document_editor()`, `test_application()`,
      `test_pane_surgery()` and `test_documentation()` pass (505).
      omnet-julia, branch `referenced-document` in the worktree
      `omnet-julia-referenced-document`: the system texts of `IdeWindow.jl` and
      `CampaignWindow.jl` say that `open_pane!` answers the tab (5d0ad513), and
      `test/campaign/PaneProgramTest.jl` gives `evaluate_reference` the
      `get_reference` of what `duplicate_pane!` answers (the first search missed
      it; `evaluate_reference` takes only a `Reference`). Run in scratch
      environments against this branch and against both `main` checkouts, the
      same counts: `test_pane_program` 47, `test_result_verbs` 63,
      `test_ide_file_navigator` 8, `test_select_and_paste` 86,
      `test_assistant_session_by_hand` 24, `test_assistant_problem_table` 16,
      `test_assistant_turn_misses` 8. The environments are under
      `/var/tmp/referenced/omnet-check/`; `OmnetIdeTest` and
      `OmnetCampaignUiTest` are packages of their own, not in `environment/all`.
      Measured before the change: in this repository
      `ApplicationTest.jl:466` gives the answer to `strip_reference_types` and
      becomes `get_reference(opened)`; in omnet-julia every use of the answer
      goes to `get_referenced_value`, which takes a referenced document, so its
      code works unchanged, and its text changes: the system texts
      `IdeWindow.jl:135` and `CampaignWindow.jl:429` ("answers a reference") and
      the docstrings of the functions that answer what `open_pane!` answered
      (`ResultSelection.jl`, `ResultReader.jl`). A referenced document does not
      forward `==`; no comparison of the answer with a `Reference` was found.
      The two repositories land together.
      The step as planned: D5 and D10, with tests:
      `open_pane!` with a group target, a tab target and a side, and its answer;
      `move_pane!`, `focus_pane!`, `close_pane!` and `print_natural_text` with a
      referenced document.
- [x] **Step 4: JSON.** Done. D11 already existed (see D11). The docstrings
      of the JSON types say their shape (D15 for the source; the application
      declaration is in Step 5). The referenced document forwards the collection
      functions (see D2). `test_referenced_document()` passes 33 checks and
      `test_referenced_document_editor()` 24, with an array that iterates, an
      object read by key, by `get` and by iteration, and a missing key that throws
      a `KeyError`; `test_json()` passes 194, as on `main`.
      The step as planned: D11 and D15, with tests of `object[key]` and its
      `KeyError`.
- [x] **Step 5: the documentation.** **Done (2026-09-26).**
      - D12: `_ANSWER_DESCRIPTION` and `_VARIABLES_DESCRIPTION` in
        `DefaultTools.jl` hold the sentence about the answer and the paragraph
        about variables, and both descriptions use them, so the two can not
        differ. The docstring of `execute_julia_code` says the rule too.
        `test_declared_api()` checks both descriptions.
      - D13: the first sentence of `get_edited_document` says "the data that a
        tab or an open file shows". Found: the search ranks a hit by its name
        score first and by its prose only in a tie, so a request whose words are
        not in a name can not answer that name first with the words alone. The
        unit test asserts what the words can do: "edited document" and "find
        pane" in mode "keywords", "a document and where it is", "the address of
        a document" and "the fields of a JSON object" in mode "description".
        Measured with the meaning model of the application
        (`nomic-embed-text`, fused with the words), the place of the name in the
        hits: "the data of a tab" 3 (`get_edited_document`), "what a file tab
        holds" 5, "the JSON of an open file" not in the first 5, "a tab by its
        title" 3 (`find_pane`), "find a tab by its name" 1, "read the data that a
        tab shows" 4, "open a new tab next to another tab" 1 (`open_pane!`), "a
        document and where it is" and "the address of a document" 1
        (`DocumentLocator`). A hit list shows 8 in summary and 25 in names, so
        each is in what the model reads, but not always first.
      - D14: `make_pane_api` declares `find_pane` and `ReferencedDocument`,
        `get_document`, `get_reference`, `DocumentLocator`,
        `find_referenced_document` and `get_edited_document`, because `find_pane`
        answers a referenced document; `make_application_api` declares the seven
        JSON types.
      - D16: the orientation guide has a row for the referenced document, the
        section "Reach what a tab holds" with the two rounds and the rule of D12,
        and a gotcha: a referenced document is not an instance of its
        document's type.
      - D17: the docstring of `get_file_content` has the right name and says
        that the answer can be the history. Each pane verb says that it takes a
        referenced document.
      - `test_documentation()`, `test_naming()`, `test_declared_api()`,
        `test_code_execution()` and `test_referenced_document_editor()` (49)
        pass.
      - D16, the package documents: `kernel/reference.md` (a section "A
        document together with its reference"), `pane/pane.md` (`target`,
        `side`, `find_pane`, the verbs that take a referenced document),
        `fileformat/fileformat.md`, `serialization/serialization.md`
        (`get_file_content`, `get_edited_field` of a file) and `json/json.md`
        (the shape, with an example that runs). The writing guard passes.
      The step as planned: D12 to D17; the search tests of D13;
      `test_documentation()` and `test_naming()` pass.
- **The review of Steps 1 to 5 (2026-09-26).** A code review of the branch
  found these, and each is fixed, with a test:
  - A reference that a read made was not fully typed: `extend_reference` leaves
    the new last node without a type, and each pane verb refuses a reference that
    is not fully typed. Each step that a read adds now records the type of the
    node it stands on and ends on the type of the value, as
    `annotate_reference_types` does; a value found by identity has its found path
    annotated, and `find_referenced_document` annotates the locator's reference.
  - `_make_key_step` had two methods that were ambiguous for a dictionary with
    integer keys. It is one method: a dictionary key that a field step can name
    (a `String` or a `Symbol`) is a field step, a position is an element step, and
    any other key is found by identity.
  - A write stored a referenced document in the tree. `setproperty!`,
    `setindex!`, `push!` and `insert!` store its document.
  - `open_pane!` with `side` had its own surgery, without the flattening of
    `make_pane_split_operation`; it calls that function now (see Step 3).
  - The identity search took the first of equal values, which gives a wrong
    reference for a document with no fields that is at two places. A value found
    at more than one place is answered plain.
  - A dictionary iterates `key => value`, with the value read by its key;
    `values` of a sequence reads by position. `push!`, `insert!` and `deleteat!`
    go to the document. `SEALING.md` lists `reference/ReferencedDocument.jl`, and
    the docstring of `ReferenceModule.jl` names the fragment.
  - Not changed: `people[1]` and `people.elements[1]` answer two different
    references to one node; both evaluate to it. `get_edited_document` of a text
    file answers a `PrimitiveString`, a document, and not a `String` as the review
    said.
  `test_referenced_document()` passes 44 checks and
  `test_referenced_document_editor()` 58; with `test_pane_surgery()`,
  `test_application()`, the kernel and substrate layering guards, `test_naming()`
  and `test_documentation()`, 752 pass.
- [ ] **Step 6: the ideal code, and the rehearsal.** **In progress
      (2026-09-26).** The two rounds of the orientation guide run through
      `execute_julia_code` on the declared API of the application, headless:
      round 1 prints the JSON, round 2 opens "People by name" after
      "people.json" in the same group, with the rows Ada 36, Bob 41, Cleo 29,
      and a third call shows `people_tab_1` as
      `ReferencedDocument{PaneTab} at .windows[1]…tabs[1]: PaneTab(…)`. Found:
      `print_natural_text` answers a `String`, which the tool shows quoted with
      `\n` escapes, as the REPL does; the guide and §3 print it with `println`.
      **The rehearsal with qwen, prompt 1 (2026-09-26):** a tab opened, in
      137 s and 6 rounds of the 8 the agent allows. Every rehearsal before this
      plan ended with no tab. `qwen3.8:27b` on the GPU, context 32768, seed 1,
      the system prompt unchanged (D18), three people in `people.json`. The
      script is `/var/tmp/referenced/rehearse.jl`: the S2 rehearsal of the
      s2-video branch, with the assistant built by the `Assistant` constructor,
      which takes `llm` on `main`. What the model did:
      1. `read_resource` of the orientation guide;
      2. `search_api` for `open_pane!` and for `WidgetTable`, and a
         `search_guides` by description;
      3. `execute_julia_code` with the three lines of round 1 of the guide,
         copied as they stand, which printed the JSON;
      4. a call that converted each value with `String(...)`, because the
         docstring of `WidgetTable(headers, rows)` calls it a "string
         convenience shim"; `String(::Int64)` failed;
      5. the same with `string(...)`, and `open_pane!(…; title = "People by
         name", target = people_tab_1, side = :right)`: the tab opened in a new
         group to the right of "people.json", with Ada 36, Bob 41, Cleo 29;
      6. an answer that says so.
      It read "beside the first one" as `side = :right`, a new split, and not
      as the next tab of the same group; both fit the prompt.
      **The rehearsal of both prompts (2026-09-26),** the five people of the
      screenplay, one conversation (`/var/tmp/referenced/rehearse_two.jl`):
      - Prompt 1: a tab opened, in 155 s, by the same path; but the rows were
        `string(person["name"])` and not `person["name"].value`. `string` of a
        referenced document is its display, `"ReferencedDocument{JsonString} at
        .windows[1]…entries[1].value: JsonString(\"Cleo\")"`, so each cell holds
        that text, and the sort by it keeps the order of the file. `string` of a
        plain `JsonString` is `JsonString("Cleo")`, not the name either. The
        model said the table was sorted; it was not.
      - Prompt 2 ("Under the two tabs, add a card …"): no card, 489 s, 6 rounds,
        and the turn ended with `max_tokens` in a thinking block. The model
        searched "move_pane! open_pane! target split below nested group", which
        answered `move_pane!` first, read the pane design document, and set out
        to build a `PaneSplit` by hand with `replace_referenced_value!`. It then
        called `get_document` on what `get_referenced_value` answered, a plain
        `PaneSplit`, and got a `MethodError`: it took every part to be a
        referenced document. `open_pane!` with `target` and `side = :below`
        would have done it in one call; the guide shows only `side = :right`.
      What the owner decided on the findings (2026-09-26):
      - `print` of a document writes its natural text, and a referenced document
        prints its document: its own plan, `a-print-writes-and-a-make-answers.md`
        (D5 there).
      - `get_referenced_value` answers the node, and moves to the editor layer:
        a follow-up below.
      - Done here: `get_document(x)` answers `x` for any value that is not a
        referenced document; the orientation guide shows a card put under a group
        with `side = :below`, and says `:left`, `:right`, `:above`, `:below`; the
        `open_pane!` docstring says "beside or under another tab" and shows a
        `side = :below` call; the `WidgetTable` docstring says that a row takes
        any value (a document as itself, any other value as `string(value)` in a
        `WidgetLabel`, a JSON leaf by its `.value`), and its example has a number.
        Measured place of `open_pane!` after the change, with the words only and
        with the meaning model: "open a tab under another tab" not in the first
        four and 3; "put a new pane below a group of tabs" 3 and 3; "open a pane
        under another pane" 1 and 2. The unit test asserts the last with the
        words. `test_referenced_document()` 51 and
        `test_referenced_document_editor()` 71 pass, with `test_documentation()`,
        `test_naming()` and `test_export_collisions()`.
      **The rehearsal of both prompts after those changes (2026-09-26,
      `/var/tmp/referenced/rehearsal_3.log`):**
      - Prompt 1: right, in 110 s. The model read the guide, searched
        `open_pane!` and `WidgetTable`, printed the JSON, and built the rows with
        `.value`: the table holds the five people sorted by name, with the age and
        the city. It opened it in a new group to the right of "people.json".
      - Prompt 2: no card; the turn used its 8 rounds and stopped while it still
        called tools (179 s). The search found `open_pane!` with `target` and
        `side` first this time; the model called `get_parent` twice and printed
        the group and the split, then set out to build a split by hand and spent
        the rest of its rounds on `PaneSplit`, `@reference` and
        `concat_references`. The cause is the layout that prompt 1 made: "the two
        tabs" are two groups side by side in the root split, between "Files" and
        "Assistant", so a pane under both needs a new split around those two
        groups alone, and `open_pane!` takes one group or one tab as its target.
        Open for the owner: the words of the prompts in the screenplay, or a verb
        that puts a pane beside several panes.
      **The screenplay changed (the owner, 2026-09-26):** the card step is gone.
      S2 ends with "Ada moved to Paris. Change it in people.json." and one
      `Ctrl+Z` that puts "London" back (s2-video worktree, 576a1774). Checked
      headless after the choice, three ways the model can write it, with the
      undo steps of the window's history and of the file's own history:
      - `people_1[2]["city"] = JsonString("Paris")`: the file shows Paris; no
        undo step anywhere.
      - `people_1[2]["city"].value = "Paris"`: the same; no undo step anywhere.
        This is the form the guide invites, because it reads with `.value`.
      - `replace_referenced_value!(editor, people_1[2]["city"], JsonString("Paris"))`:
        the file shows Paris; one step in the window's history, none in the
        file's.
      So a write through a referenced document (D2) changes the document with
      no step that `Ctrl+Z` can take back, and the write through the window
      records its step in the window's history, not in the history of the file
      that a person's own edit goes to. Open for the owner: what a write through
      a referenced document does, and which history an edit of the assistant
      goes to; and whether the table follows the file.
      **The screenplay changed again (the owner, 2026-09-26; s2-video,
      1b65bd98):** "Add Frank, 30, from Paris to people.json."; the person clicks
      in `people.json` and presses `Ctrl+Z`; then the table prompt of beat 2; the
      video ends on the table. The log panel is at the bottom left. Decided with
      it (D23 below): an edit of the assistant inside a file goes into the
      history of that file. The question whether the table follows the file does
      not come up in this order. Checked after the choice: the declared API has
      one verb that edits, `replace_referenced_value!`; the kernel makes an insert
      and a delete operation (`insert_elements`, `delete_elements` in
      `Operations.jl`), but neither is declared, and neither is `evaluate_operation`
      that runs one. So "Add Frank" has no path through an operation that the
      model can call; `push!(people_1, …)` works only as a direct write, with no
      undo step (D22).
      Round 2 answers the typed reference of the new tab, which is long
      (`::ScreenDocument.windows::CellVector[1]::…::PaneTab`); a
      `ReferencedDocument` answer (D10, open) would show the tab.
      The step as planned: The code of §3 runs as the
      assistant runs it (`execute_julia_code` on the declared API) and opens the
      table after "people.json". Then a rehearsal of S2 with qwen on the GPU
      (context 32768, seed 1): the rounds it takes and whether the tab opens are
      recorded here and in the video plan.
- [x] **Step 6a: the editing verbs** (D23, D24). **Done (2026-09-26);** see
      the notes under Step 6. First find how an edit of a
      person inside a file reaches the file's history and not the window's; then
      the verbs in the editor layer with that routing; then the declaration, the
      guide and the docstrings; tests of a replace, an insert and a delete through
      a referenced document: the document changes, the file's history has one
      step, the window's has a step that names it (an outer history records
      that the inner one took a step, `UndoModule`), the gesture log has a
      line, and an undo in the file takes it back. Then a rehearsal of the new
      S2 order.
      **Found (2026-09-26):** `read_rooted_operation` carries an operation up to
      the root only from the pane tree itself. From every place below it, the
      root split down to a JSON entry, it answers `nothing`
      (`/var/tmp/referenced/route_depth.jl`). The window's chain is
      `ChainingProjection(RecursiveProjection(PaneToWidget()), renderer)`; the
      chain maps a route forward through a stage while the stage prints the
      place as the same document (`_read_routed_chain`), and the pane stage does
      not: its projections (`PaneTreeToWidget`, `PaneSplitToWidgetSplitPane`,
      `PaneGroupToWidgetTabbedPane`) turn the tree into widgets, and only the
      tree's reader has four arguments, which reads the operation as its own
      and ignores the route. The file's own readers, its history among them,
      are in the second stage, where the renderer prints the content of each
      tab. So D23 needs a route through the pane stage into the content of a
      tab: the forward map of a route into a tab's content, and the widget
      stage carrying it to the content's projection. The pane verbs route to the
      tree, which is why the window's history records their edits.
      The owner (2026-09-26): "yes, we need proper routing not shortcuts". What
      the proper route needs, found in the code:
      1. **The `.element` step.** The pane stage maps a route into a tab's content
         to `selector_element_pairs[i]` and the content path, but the node at
         `[i]` is a `WidgetTabPage`, and the content is its `element`. The widget
         stage says so in `_tab_prefix` (`WidgetToGraphics.jl`): "writing it
         unconditionally is the correct path, and it would need the decoder changed
         in the same commit"; the decoder is `PaneToWidget`. So the pane stage's
         forward and backward maps and the widget stage's `_tab_prefix` change
         together, and the selection that the tabbed pane passes into a page
         follows.
      2. **A route through the widget containers.** On the path from the window's
         widget root to a file, the widget stage has
         `WidgetCompositeToGraphicsCanvas`, `WidgetSplitPaneToGraphicsCanvas` (with
         a `LayoutConstraint` that has no IoMap of its own) and
         `WidgetTabbedPaneToGraphicsCanvas` (with a `WidgetTabPage` that has
         none), then `FileToContent`, which follows routes. Only the shell of the
         widget stage follows a route today. The rule the shell uses is general:
         take the steps of the route from the input until a node is the input of a
         child IoMap, pass the rest to that child, and reroot the answer by the
         steps taken. One helper for the widget containers, whose `child_iomaps`
         hold `(x, y, child)`; the kernel's `ChildrenIoMap` leaves that form open,
         so the helper is in the widget stage.
      3. **The verbs** of D24, rooted at the document that the history of the
         file holds.
      **Parts 1 and 2 done (2026-09-26).** The pane group's forward map writes
      `selector_element_pairs[i]::WidgetTabPage.element` and then the content's
      image (`_get_tab_content_path` in `PaneToWidget.jl`); a selection of the
      tab whole or of its title names the page. The backward map already took
      `.element`, and the widget stage already wrote it for a page that holds a
      document that is not a widget. `WidgetToGraphics.jl` has
      `_RoutingContainerProjection` (the composite, the split pane, the tabbed
      pane) with a four-argument reader that routes by `_read_routed_child`, the
      rule of the shell made general. Measured with
      `/var/tmp/referenced/route_depth.jl`: an operation rooted at the tab's file,
      at the file's history or at the JSON array now comes back as a
      `RecordUndoOperation`; below the array, inside the JSON, it does not, because
      the JSON projection follows no route; at a pane node below the tree it does
      not either, and the pane verbs root at the tree. Rooted at the array, the
      Paris write changes the city, and both histories have one step. Tests: a
      route into a file tab is recorded in the file's history
      (`test_referenced_document_editor()`, 76 with `test_naming()`); the pane,
      tab, split, file-tab, gesture-log and application tests pass (1291);
      `test_split_pane_drag()` has 3 failures and 2 errors, the same on `main`
      (a893fc2a).
      **Part 3 done (2026-09-26).** `source/kernel/editor/DocumentEdits.jl` (a
      new fragment of `EditorModule`, listed in `SEALING.md`):
      `find_rooted_operation(editor, reference, make_operation)` tries the places
      on the reference from the deepest up and roots the operation at the first
      one from which the readers carry it to the root, so it needs to know nothing
      of undo; `insert_elements!(editor, collection, index, values)` and
      `delete_elements!(editor, collection, index, count = 1)` make the range
      replace that `insert_elements` and `delete_elements` make, with a 1-based
      index, store the document of each value, and answer the collection after
      the edit as a `ReferencedDocument`. `replace_referenced_value!` keeps its
      checks and its answer in the pane package and roots its write the same way
      (`_make_deepest_pane_write`), with the route to the tree for a root with no
      readers, as the test stand-ins have. Decided in the work: the move of
      `replace_referenced_value!` to the editor layer waits for the follow-up that
      moves `get_referenced_value`; the routing it needs is done now. The
      application declares `insert_elements!` and `delete_elements!`; the
      editing sentence of the description names each declared one of the three;
      the orientation guide shows the insert of Frank. Tests: each verb through a
      referenced document puts one step in the file's history and one in the
      window's, and an undo in the file's history takes it back; the description
      names the verbs only when they are declared. 711 pass with the tool,
      layering, naming, export, documentation, application, pane and file-tab
      tests.
      **The rehearsal of the new S2 order (2026-09-26,
      `/var/tmp/referenced/rehearse_three.jl`, `rehearsal_4.log`):** qwen3.8:27b on
      the GPU, context 32768, seed 1, the system prompt unchanged.
      1. "Add Frank, 30, from Paris to people.json.": 70 s. The model printed the
         JSON, then ran
         `frank_1 = JsonObject("name" => JsonString("Frank"), "age" => JsonNumber(30), "city" => JsonString("Paris"))`
         and `insert_elements!(editor, people_1, length(people_1) + 1, [frank_1])`.
         Frank is the sixth person; the file's history has one step, the
         window's one.
      2. The undo in the file's history (evaluated by the script; the take
         presses the keys): Frank is gone.
      3. The table prompt: 111 s. The model used `people_1` again, the values by
         `.value`, sorted by name, and
         `open_pane!(…; title = "People by name", target = get_parent(editor, people_tab_1))`:
         the tab opened in the group of "people.json", and the answer showed the
         tab as a `ReferencedDocument{PaneTab}`.
      The two turns took 7 rounds together. The script's print of the table
      failed (a `WidgetLabel` holds its text in `content`), so the rows are known
      from the code, not read back. Open: the take itself, with the log panel
      and real keys, in the s2-video worktree, which needs this branch; and the
      text of a log line (the owner's question 4).
- [x] **Step 7: the landing** (the owner, 2026-09-26: "land this branch").
      Rebased onto `main` 4b828483 with no conflict; six files changed on both
      sides (`pane.md`, `Application.jl`, `PaneProgram.jl`, `WidgetDocument.jl`,
      `WidgetToGraphics.jl`, `ApplicationTest.jl`). `main` had removed
      `measure_truetype_text` (acde9278), so the editor test builds the window
      with the default measure. The landing check: `test_referenced_document()`
      51, `test_referenced_document_editor()` 87, the pane, tab, file-tab,
      split-pane, gesture-log, declared-API, code-execution, JSON, documentation,
      naming, export and layering tests pass; `test_application()` 336 of 338 and
      `test_split_pane_drag()` 25 of 30, each the same on `main`. The omnet-julia
      branch `referenced-document` (the two system texts and the test fix of
      `PaneProgramTest.jl`) waits for the owner's word; until it lands,
      `test_pane_program` of omnet-julia has 2 errors against this `main`.
      Not done in this plan: the take of S2 (Step 6), the follow-ups below.

### Follow-up, after this plan (D21)

- [ ] When the owner changes the system prompt of the application (D18, after
      Step 6): stop declaring `find_pane_reference` and `find_pane_tree_reference`,
      and add `find_pane_tree(editor)`, which answers the pane tree as a
      referenced document.
- [ ] A cleanup across this repository and omnet-julia: the `_reference` finders
      become private (`find_pane` is built on `_find_pane_reference`), and their
      callers call `find_pane` and pass the referenced document, or call
      `get_reference`.
- [ ] `get_referenced_value` moves to the editor layer (the owner, 2026-09-26:
      "it's a generic function that evaluates a reference relative to the
      editor, it has nothing to do with panes"). It came into
      `source/pane/PaneProgram.jl` with the other verbs that read and write the
      window as a program (bfd380a2, 2026-09-12). Its body is generic: the root
      of the editor, the refusal of a reference that is not fully typed, the
      evaluation, and an `ArgumentError` that names the path. Two parts belong
      to the pane: it takes a `PaneTree` as a root too, and its error text names
      "this window" and `show_layout`. In the editor layer it sits next to
      `get_parent(editor, x)`; whether it keeps its name or becomes a method
      `evaluate_reference(editor::Editor, reference)` is for the owner.
      It answers the node, not a `ReferencedDocument`: it evaluates a reference,
      which is below the referenced document, and a `get_` reads a value at a
      known place, so D21 ("finds or makes a part") does not cover it.
      `replace_referenced_value!` stays in the pane package: it checks a write
      into a pane tree and restores the focus.
