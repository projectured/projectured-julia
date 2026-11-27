# The JSON content keeps no selection

**Status:** pending. It waits for the approval of the owner.

This plan is plan 4c of point 4 of the order in section 13.3 of
`plan/tentative/content-and-view-for-the-whole-project.md`. Plans 4a, 4b1 and 4b2
are done and on `main`. The design is `documentation/design/content-and-view.md`.
After this plan, the owner reviews the JSON domain, and point 4 ends.

The steps come from a measurement, which the section "The measurement" gives. The
plan lands nothing and pushes nothing: it ends with a request to land.

**If a step finds a failure whose cause is not in this plan, or needs a mechanism
that this plan does not name, the work stops and the session asks.**

## What changes

A JSON document holds only its data. The nine JSON content types `JsonNull`,
`JsonBool`, `JsonNumber`, `JsonString`, `JsonArray`, `JsonObjectEntry`,
`JsonObject`, `JsonInsertion` and `JsonNothing` get no field `selection` and no
field `mouse_target`. The caret is in the view of the node, below the step
`.viewed`, as rules 4 and 5 of the views in the design say.

```julia
# On main now
string = JsonString("abc")             # fields: value, selection, mouse_target
view = JsonStringView(string)
get_selection(view)                    # .value{2}: a step that the view does not have

# After this plan
string = JsonString("abc")             # fields: value
view = JsonStringView(string)
get_selection(view)                    # .viewed.value{2}
```

A person sees no change. Each place that shows JSON shows it through its views,
and the caret, the pointer and the keys work as now.

## The measurement

**The method.** In a copy of `main` at `2b326cc4b`, `@document` left out the two
fields for the JSON content types. All the parts of all the suites ran in the copy,
with the land command of `CLAUDE.md`. The copy lands nowhere. The copy had two
stand-ins, which are not the design:

- `@document` tested the name of the supertype, `JsonDocument`, in place of a hook.
- Each JSON content type got a field `no_fields`, because `@document` can not make
  a type with no field (kernel fact 2 below).

The copy did not add the step `.viewed`. So the measurement says nothing about the
step `.viewed`, and step 6 below has no measured list.

**The result.** 772 parts: 769 done, 3 time out; 8647 fail, 278 error. The last
full record of `main` on the line of `2b326cc4b` is the record of `760b801ef`: it
has a fail in five parts (`test_exports`, `test_documentation`,
`test_editor_memory_cycle`, `test_scroll_work`, `test_application`). All the other
failures are new, in 84 parts and in 64 test files.

**The first fault of a walk hides the faults behind it.** An example walk stops
at the first error of each event. So the run shows the causes A to C of the table
below, and the code shows the causes D to F, which A to C hide.

### What the run shows

| | Cause | Where | Count |
| --- | --- | --- | --- |
| A | The print of an object entry gives its output node the selection cell of the entry | `JsonToSyntax.jl:129` | 1196 walk messages, 173 test errors |
| B | The reader of a template node reads the caret of its input to find the child that has the caret | `ProjectionTemplate.jl:1532` (`_read_template_key`), `:1652` (`_read_override_gesture`) | 6978 walk messages, 62 test errors |
| C | The empty place and the place for a new value read their caret: the print of the empty place, and the Tab of the place | `InsertionToSyntax.jl:532`, `:410` | 183 walk messages, 5 test errors |
| G | A tab of a JSON file draws nothing, because of A, so a wait for a text runs to its end | `FileWatchWindowTest.jl:68`, `UserInterfaceFileTest.jl:31`, `EditorMemoryCycleTest.jl:293`, the 3 parts that time out | 9 parts |
| H | A fault of the stand-in field `no_fields` | `DeclaredType.jl:192` and two positional constructors | 10 test errors, which do not count |

A walk message is one failure of the walks of the printers, of the readers, of the
loop of a key and of the navigation. These walks run in `test_catalog`,
`test_repls`, `test_readers`, `test_printers`, `test_domain_examples`, and the two
parts of complete navigation. The walk messages of B are all `read_intent threw`.
The walk messages of A are all `Cell[] threw`, with the type `JsonObjectEntry`.

Only the examples that hold a JSON document fail. These are 17 examples and the 18
atoms of the catalog of JSON:

- `json`, `json_sorted`, `json_insertion`, `graphics_image`, `mixed`, `natural`,
  `workflow_complete`, `focusing`, `table`, `graph`, `dragging`, `versioning`,
  `undo`, `widget_tabs`, `widget_split`, `widget_split_tabs`, `pane_json`;
- `json/<null|bool|number|string|array|object>/<text|syntax|graphics>`.

The two examples `json_object_view` and `json_file_view` show JSON through views
already. They fail only by A.

### What the code shows

| | Cause | Where |
| --- | --- | --- |
| D | A place or an example shows a JSON content with no view, so its caret has no document that keeps it | the 17 examples and 18 atoms above; in the editor, a card of a dashboard in an editor that holds no file, the page of a part inside a JSON file (from a search link or a row of the document tree), and the page of a navigator for such a part |
| E | The caret of a new JSON document is a field of the new document | the 6 `@insertion` lines and the 3 `@selected` rows of `JsonDocument.jl`, the 3 `@selected` rows of `JsonView.jl`; `make_replace_document_operation`, `append_insertion_operation` and `insert_document_operation` read it |
| F | A test writes or reads the caret or the part under the pointer of a JSON content | about 54 writes in `test/domain/json`, and more than 100 outside it, for example `SerializationTest.jl:40` and `:53`, `DocumentInsertionTest.jl:222`, the 7 checks of `JsonMouseTargetTest.jl` |

Twelve rows of the key tables of the JSON content read the caret: in `JsonDocument`,
the condition and the eight replace rows; in `JsonArray`, the comma; in
`JsonObject`, the comma, the Tab, and the move from the value to the key. The key
tables of the JSON views hold the same twelve rows. The thirteenth row of the
content, the sort of the entries, reads no caret.

### Three faults of `@document`, which the measurement found

1. **`@domain` expands its inner `@document` calls before its abstract type
   exists.** `@domain` calls the macro function of `@document` directly, for the
   two types that it makes (`source/platform/domain/Domain.jl:837` and `:845`).
   So a hook that `@document` asks for the supertype can not run there.
2. **`@document` can not make a type with no field.** With no field, a reduction
   over the fields has no start value (`_emit_autowrap_ctor`), and the two kinds of
   a type (immutable cells and mutable cells) are one type, so their constructors
   overwrite each other (`_emit_kind_aliases`, `_emit_keyword_ctors`).
3. **`@document` loops when the only field of a type is its list.** The
   constructor that takes the elements and the constructor that takes a vector call
   each other: `JsonObject` at `JsonDocument.jl:84` overflows the stack.

## Decisions that this plan proposes

The session proposes these decisions. They are approved with the plan.

1. **The hook is `keeps_selection(T::Type) -> Bool`**, a function of the kernel.
   `@document` asks it for the supertype of the new type, when it expands, in the
   module of the call. When it answers `false`, the type gets no field `selection`
   and no field `mouse_target`. In this plan the default answers `true`, so every
   type that is not JSON keeps its two fields. Point 11 of the order changes the
   default to `false`, and the platform then answers `true` for `View`. The name
   is the working name of open point 1 of the design. It follows the naming rules:
   a plain verb that reads as a question.
2. **`@domain Json keeps_selection = false`.** The option declares the method of
   the hook for the root type of the domain. `@domain` then gives the root type,
   the method and the two types that it makes in one top-level expression, in this
   order. Julia expands each part of a top-level expression after it evaluates the
   parts before it, so the inner `@document` calls see the root type and the
   method.
3. **A read of the caret of a document whose type keeps none answers "no caret".**
   Each direct `getfield(x, :selection)` that can get a JSON content reads
   `get_stored_selection(x)` in its place, as `_atomic_print` does now. The print of
   an entry gives its output node a cell of its own, computed as `_atomic_print`
   computes it. When the content shows through a view, the viewing step gives the
   output view its caret, as it does now.
4. **The caret of a new document is in the operation that writes the document.**
   `@insertion T = expr path` declares the document and the path of the caret in
   it: `make_insertion_document(T)` and the new `get_insertion_selection(T)`, whose
   default is the empty path, the whole node.

   ```julia
   @insertion JsonString = JsonString("") value{0}      # now: = @selected JsonString("") value{0}
   make_replace_document_operation(path, JsonNumber(5); selection = @reference(::JsonNumber, value{1}))
   ```

   `make_replace_document_operation(path, document; selection)` takes the path of
   the caret in `document` as a keyword. Its default reads the caret that
   `document` keeps, for the domains that keep one until point 9. The append, the
   insert of a placeholder and the commit of a typed name take the caret from
   `get_insertion_selection`. All 24 `@insertion` lines that use `@selected` take
   the new form, so a new document gets its caret in one way: 6 of JSON, 6 of
   YAML, 6 of FSM, 3 of XML, 2 of process and 1 of text. The other 4 `@selected`
   calls outside JSON, 3 rows of YAML and 1 in the evaluator, stay until the plans
   of their domains.
5. **The key tables of the JSON content keep only the rows that read no caret.**
   The twelve rows that read the caret go from the tables of `JsonDocument`,
   `JsonArray` and `JsonObject`. The tables of the views keep them, as rule 6 of
   the design says. The sort row stays in the two tables.
6. **Each place that shows a JSON content shows its view.**
   `make_document_view(document::JsonDocument) = make_content_view(document)`, a
   method of the JSON domain. The default of the design,
   `something(make_content_view(content), content)`, and the rename to
   `make_page_view` stay in point 7: the default also changes the pages of
   Markdown, of a text and of the place of every domain, which this plan does not
   measure. Each of the 17 examples and 18 atoms shows the view of its JSON, with
   `ViewingProjection` in its stages, as the view examples do now.
7. **A path through a view names its content by the step `.viewed`.** A
   `ContentView` reads only its own fields: the forward of a missing field step to
   the content goes from `evaluate_reference_step` and `has_reference_step_child`.
   `get_content_field(::ContentView)` answers `:viewed`, so `get_content_path` takes
   the step off and `get_view_path` puts it on. `_make_view_path` and
   `_make_plain_path` in `Viewing.jl` work with the step. The rule of plan 4b2 in
   `_read_routed_chain` (`_shows_place`, `Chaining.jl:193`), which lets a route go
   on at a document that names its content with `get_edited_field`, goes: the
   route names the content by `.viewed` now.
8. **A test puts a caret into the view, never into a JSON content.** A test that
   reads the part under the pointer of a JSON content reads it from the view.

## Steps

Each step is a commit in the worktree `json-no-selection`, with the narrowest
tests that cover it. A step marks itself done here, with the facts that it finds.

1. **`@document` makes a type with no field, and a type whose only field is a
   list** (kernel faults 2 and 3). Kernel tests of the two forms, with the two
   fields and without them. `test_kernel(only = "document")`.
2. **The hook and the option of `@domain`** (decisions 1 and 2). The default
   answers `true`, so no type changes. A kernel test type that answers `false`
   gets no field `selection` and no field `mouse_target`. A test domain with the
   option makes its placeholder and its insertion with no fields. The kernel and
   platform tests of documents and domains.
3. **The reads of a caret that a type does not keep** (decision 3, causes A, B
   and C). `JsonToSyntax.jl:129`, `ProjectionTemplate.jl:1532` and `:1652`,
   `InsertionToSyntax.jl:410` and `:532`, and the reads that a search of the code
   finds in the same form: `Focusing.jl:80`, `Clipboard.jl:209`,
   `ClipboardCollectionToAny.jl:118`, `ClipboardSliceToAny.jl:317`. No behavior
   changes, because the JSON content keeps its fields until step 8. `test_json()`.
4. **The caret of a new document in its operation** (decision 4, cause E). The 24
   `@insertion` lines and the example in the docstring of `@insertion`, the 6
   `@selected` rows of JSON, the four makers of operations. The suites of JSON,
   YAML, XML, FSM, process and text.
5. **Each place and each example shows the view of its JSON** (decision 6, cause
   D). The method of `make_document_view`, the 17 examples and the 18 atoms. The
   walks of these examples, `test_explorer`, `test_navigator`, and the parts of the
   dashboard.
6. **The step `.viewed`** (decision 7). The tests that name a caret through a JSON
   view take the step. `test_json()`, the platform parts of focus and of the
   chain, the parts of the integration suite that open a JSON file.
7. **The key tables and the tests** (decisions 5 and 8, cause F). The twelve rows
   go from the content tables. Each test that writes or reads the caret or the
   part under the pointer of a JSON content uses the view. The tests still pass
   with the fields.
8. **The JSON content keeps no selection.** `@domain Json keeps_selection = false`.
   All the parts of all the suites run in the worktree with the land command. The
   land needs 0 unmarked `Fail`, 0 `Error` and `done` for each part. Each failure
   must belong to a cause of this plan; else the work stops and the session asks.
9. **The documents and the land.** The section "The code now" of
   `documentation/design/content-and-view.md`, the package documents of JSON, of
   `@document` and of the selection, and point 4 of the order. A request to land.
   After the land, the lists of the test calls record again, as `CLAUDE.md` says,
   and the plan moves to `plan/done/`. Then the owner reviews the JSON domain.

## Not in this plan

- **The content of the other domains** keeps its selection: point 9 of the order,
  one plan for each domain. The YAML entry prints in the form that JSON prints
  now.
- **The boxes** `PrimitiveString`, `PrimitiveNumber`, `PrimitiveBool` and
  `ObjectField`: point 8.
- **The default `false` of the hook, and `true` for `View`**: point 11.
- **The default of the design for `make_document_view`, and its rename to
  `make_page_view`**: point 7.
- **`FileView` below `ContentView`, with the field `viewed`**: point 7.
- **The memory of the views**: open point 4 of the design. A JSON editor holds
  2.3 times the memory of the content alone (fact 15 of plan 4b2). The owner put
  this cost off to a later plan.
- **The faults of `main`** that plan 4b2 found: the sibling paths of the manifest,
  the start steps of an editor that never runs its loop, and the guards that fail
  on CI.
