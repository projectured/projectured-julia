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

Round 1, look at the data and keep what it finds:

```julia
people_tab_1 = find_pane(editor, "people.json")      # ReferencedDocument{PaneTab}
people_1 = get_edited_document(people_tab_1)         # ReferencedDocument{JsonArray}
print_natural_text(people_1)
```

Round 2, reuse `people_tab_1` and `people_1`:

```julia
rows_1 = [[person["name"].value, person["age"].value] for person in people_1]
sort!(rows_1; by = first)
table_tab_1 = open_pane!(editor, WidgetTable(["name", "age"], rows_1);
                         title = "People by name", target = get_parent(people_tab_1))
```

`people_1` iterates its elements, because `JsonArray` acts as a vector; each `person` a
`ReferencedDocument{JsonObject}`; `person["name"]` a `ReferencedDocument{JsonString}`
whose reference reaches that entry's value; `.value` the plain `String`.

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
- **D9. `get_parent(x) -> ReferencedDocument` or `nothing` at the root.** The
  enclosing document, one step up the reference, and past a collection: a tab's
  parent is its group, a JSON entry's parent is its object, an element's parent is
  its array.
- **D10. `open_pane!(editor, document; title, target = nothing, side = nothing)`**
  places the new tab as `move_pane!` places a pane (a group: at its end; a tab:
  before it; with `side`, beside it in a new split) and answers the new tab as a
  `ReferencedDocument`.
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

### Not done

- **D19.** No conversion of a document to plain Julia data: the owner rejected it,
  it is a second shape to learn. A leaf keeps its `.value`: making `object[key]`
  answer the plain value would be that conversion, and would lose the leaf
  document.

## 5. Steps

Each step: tests first where they fit, the change, the narrowest tests that cover
it, and a commit with explicit paths and no attribution line. Work in a worktree of
its own, from `main`. Check each file against `SEALING.md` before editing it.

- [ ] **Step 1: the two types.** **In progress (2026-09-26).** Done:
      `source/kernel/reference/ReferencedDocument.jl` holds `ReferencedDocument`,
      its forwarding, display and `convert`, `DocumentLocator` and
      `find_referenced_document`; `test_referenced_document()` passes 25 checks,
      and the kernel layering guard accepts the file. Found: `CellVector` is not a
      kernel type (it lives in `source/collection/`), so the kernel knows a
      collection by `Document`, `AbstractVector`, `AbstractDict` and `Tuple`; a
      `CellVector` is a `Document`. A property that is not a field of its document
      has no step a reference can record, so its value is answered plain. A key
      that is neither a position nor a dictionary key is found in the document by
      identity (`search_references`). Open: `get_parent` must evaluate a shorter
      reference, which needs the root, and a `ReferencedDocument` keeps only its
      reference (D1); the owner chooses between `get_parent(editor, x)` and a
      referenced document that also keeps its root.
      The rest of the step: D1 to D6 and D9 in the reference layer, with
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
- [ ] **Step 3: the pane verbs and the lifted functions.** D5 and D10, with tests:
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
- [ ] **Step 5: the documentation.** D12 to D17; the search tests of D13;
      `test_documentation()` and `test_naming()` pass.
- [ ] **Step 6: the ideal code, and the rehearsal.** The code of §3 runs as the
      assistant runs it (`execute_julia_code` on the declared API) and opens the
      table after "people.json". Then a rehearsal of S2 with qwen on the GPU
      (context 32768, seed 1): the rounds it takes and whether the tab opens are
      recorded here and in the video plan.
- [ ] **Step 7: the landing,** when the owner says so.
