# The assistant reaches a document through a locator

> **Status:** pending. Written 2026-09-26.

## 1. The request

In the rehearsals of S2 (`plan/pending/feature-video-screenplays.md`), qwen was asked
"Open a second tab beside the first one with a table of the people in
people.json, sorted by name." It found `open_pane!` and `WidgetTable` in its third
round and then spent the rest of its eight rounds on reaching the people inside
the tab. The owner asked for the code the agent should ideally run, then for the
code it would run "if the API would be good", with an API "not specific to this
problem", and shaped that API in turn:

- "Maybe we are missing a type called DocumentLocator which could be returned by a
  find_pane and many other function. It would contain both the pane document and
  the reference. Then you can go to the file document with one function call or go
  to the group with a get parent or something."
- "When converting the json to widget, I don't like the generic Julia conversion
  … A proper shape documentation will give that to the agent. Also, the agent can
  do multiple code rounds to see some stuff first like the json file."
- "The rounds can share variables, the agent should know that. The documentation
  should tell the agent to store objects in numbered variables and reuse them."
  Then: "the agent should use meaningful names", and "names + index, for long term
  evaluator use".
- "print natural text can take the locator."
- On `.document` and `.value` in the rows: "maybe it's not worth it". It is not;
  see D10.

## 2. What exists

- **Finding a tab.** `find_pane_reference(editor, title)` answers a reference;
  `get_referenced_value(editor, reference)` answers the node. Two calls, two
  results to keep apart.
- **The document of a file tab.** A tab's `content` is a `FileDocument` (a
  `JsonFile`). `get_file_content(file)` answers its `content` field, which in the
  application is an `UndoBuffer` around the parsed tree. Its docstring
  (`source/fileformat/DocumentFile.jl:82`) promises "the parsed tree for a
  `JsonFile`" and names the function `content(f)`. The program's own code unwraps
  it: `get_wrapped_document(get_file_content(file))` (`DocumentFile.jl:158`).
- **The group of a tab.** No verb answers it. `move_pane!` with a tab as target
  puts the pane before that tab. The shortest working code searched:
  `only(search_documents(editor.document, g -> g isa PaneGroup && any(t -> t === tab, g.tabs)))`.
- **References.** `ReferenceModule` exports `extend_reference`, which adds steps;
  nothing removes them.
- **JSON.** `source/json/JsonDocument.jl`: `JsonArray(elements)`,
  `JsonObject(entries)` of `JsonObjectEntry(key::String, value::Document)`,
  `JsonString(value)`, `JsonNumber(value)`, `JsonBool(value)`, `JsonNull`. Each
  docstring is one line. No key access on an object. The application does not
  declare these types, so the model's search does not find them.
- **Rounds share their variables.** `execute_julia_code` runs every call at the top
  level of one scratch module per tool set, so a top-level assignment stays bound.
  Nothing tells the model so.
- **The seals.** `reference/ReferenceInterface.jl`, `reference/ReferenceSearch.jl`
  and `document/DocumentSearch.jl` are sealed (`SEALING.md`); the other files of
  the document and the reference layers are not. An interface file holds only
  declarations (PAR-INTERFACE-DECLARES-ONLY), so a concrete struct and its
  functions belong in an implementation file of the layer.
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
people_tab_1 = find_pane(editor, "people.json")
people_1 = get_content(people_tab_1)
print_natural_text(people_1)
```

Round 2, reuse `people_tab_1` and `people_1`:

```julia
rows_1 = [[person["name"].value, person["age"].value] for person in people_1.document.elements]
sort!(rows_1; by = first)
table_tab_1 = open_pane!(editor, WidgetTable(["name", "age"], rows_1);
                         title = "People by name", target = get_parent(people_tab_1))
```

## 4. Decisions

- **D1. `DocumentLocator`.** A value with two fields: `document`, the node, and
  `reference`, the complete reference to it from the root of the editor's
  document. It is how a find answers and what a verb takes where it takes a
  reference. It lives in a new implementation file of the reference layer, and
  `ReferenceModule.jl` exports it.
- **D2. `find_pane(editor, title) -> DocumentLocator` or `nothing`.** The tab of
  that title. `find_pane_reference` stays, for a caller that needs only the
  reference.
- **D3. `get_content(locator) -> DocumentLocator`.** The document that the located
  node holds, through each layer that only carries it: a tab to its content, a
  file document to its content, a history (`UndoBuffer`) or a clipboard slice to
  the document inside. For a file tab, one call reaches the file's own document
  (the `JsonArray`). The reference is extended by the steps it went through, so
  the answer is a complete locator. Where a layer answers what it carries is an
  implementation detail (the existing `get_wrapped_document` answers the
  wrappers); a new open generic, if one is needed, is declared in an interface
  file that is not sealed, and a need to change a sealed file stops the work and
  goes to the owner.
- **D4. `get_parent(locator) -> DocumentLocator` or `nothing`.** The enclosing
  document, one step up the reference, and past a collection: a tab's parent is
  its group, a JSON entry's parent is its object, an element's parent is its
  array.
- **D5. The pane verbs take locators.** `open_pane!(editor, document; title,
  target = nothing, side = nothing)` places the new tab as `move_pane!` places a
  pane (a group: at its end; a tab: before it; with `side`, beside it in a new
  split), and answers the locator of the new tab. `move_pane!`, `focus_pane!` and
  `close_pane!` take a locator wherever they take a reference.
- **D6. `print_natural_text(locator)`** prints the located document.
- **D7. `object[key]` on a `JsonObject`** answers the value document of that key,
  and throws a `KeyError` that names the keys when the key is missing.
- **D8. The shape of JSON is documented and declared.** The docstrings of the seven
  JSON types say their fields and how to read a value: an array's `elements`, an
  object's `entries` and `object[key]`, a leaf's `value`. The application declares
  these types (`make_application_api`), so the model's search finds them.
- **D9. The rounds keep their objects in named, numbered variables.** The
  description of `execute_julia_code` (its docstring) and the orientation guide
  (`guide/orientation`) say: "Each call runs in the same module, so a variable
  that one call binds at the top level is still there in every later call. Keep
  each object that you find or make in its own variable, named by what it holds
  and numbered: `people_tab_1`, `people_1`, `rows_1`. When you make another object
  of the same kind, give it the next number, `rows_2`, and do not overwrite the
  first. Use a variable again in a later call instead of finding its object
  again."
- **D10. Not done: a plain-data conversion, and hiding `.document` and `.value`.**
  The owner rejected a conversion of a document to plain Julia data: it is a second
  shape to learn. Hiding `.document` would need a locator to forward its
  document's fields, and hiding `.value` would make `object[key]` convert a leaf,
  which is that conversion again and loses the leaf document.
- **D11. The docstring of `get_file_content` says what it answers**: the value of
  the `content` field, which the application keeps inside a history, and that
  `get_content` of a locator reaches the document itself.
- **D12. The declared API** of the application adds `DocumentLocator`,
  `find_pane`, `get_content` and `get_parent` (D1 to D4) and the JSON types (D8).
  The application's system prompt is not changed now (the owner, 2026-09-26, for
  the S2 rehearsals); whether it names `find_pane` in place of
  `find_pane_reference` is the owner's choice after Step 5.

## 5. Steps

Each step: tests first where they fit, the change, the narrowest tests that cover
it, a commit with explicit paths and no attribution line. Work in a worktree of
its own, from `main`. Check each file against `SEALING.md` before editing it.

- [ ] **Step 1: the locator.** D1 to D4 and D6, with tests: `find_pane` of a title
      and of a missing title; `get_content` of a file tab reaches the `JsonArray`
      and its reference evaluates to it; `get_parent` of a tab is its group, of a
      JSON entry its object, of an element its array; `print_natural_text` of a
      locator.
- [ ] **Step 2: the pane verbs.** D5, with tests: `open_pane!` with a group target,
      a tab target and a side, and its answer a locator; `move_pane!`,
      `focus_pane!` and `close_pane!` with locators.
- [ ] **Step 3: JSON.** D7 and D8, with tests of `object[key]` and of the declared
      names.
- [ ] **Step 4: the documentation.** D9, D11 and D12; the package documents that
      describe finding a pane and reading a file tab (`documentation/package/pane/`,
      `…/fileformat/`, `…/json/`, `…/kernel/reference.md`) say what the code does
      now. `test_documentation()` and `test_naming()` pass.
- [ ] **Step 5: the ideal code, and the rehearsal.** The code of §3 runs as the
      assistant runs it (`execute_julia_code` on the declared API) and opens the
      table after "people.json". Then a rehearsal of S2 with qwen on the GPU
      (context 32768, seed 1): the rounds it takes and whether the tab opens are
      recorded here and in the video plan.
- [ ] **Step 6: the landing,** when the owner says so.
