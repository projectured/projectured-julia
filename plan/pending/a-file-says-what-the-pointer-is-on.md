# A file says what the pointer is on

Status: IN PROGRESS, 2026-10-21, on the branch `pointed-part`, in the worktree
`projectured-julia-pointed-part`. Not landed on `main`. The user, 2026-10-21, to
"Shall I implement this plan now": "yes". Item 5 of wave 2 of
[a-catalog-of-what-each-part-could-say.md](a-catalog-of-what-each-part-could-say.md).

## The ask

The user, 2026-10-21, on item 5 ("a path for a binding"): "I don't like this
shape. explain to me what happens step by step from dwell to tooltip operation. I
feel like we already know where the mouse dwells". After the explanation, to the
question whether the note of a container may come after the note of the part:
"the order is right, yes".

## The problem

The facts at projectured-julia `main` `8c378b3b1`.

1. **A part does not know where it is.** A tooltip binding calls
   `compute(document)` with the part alone (`make_tooltip_binding`,
   `TooltipOperation.jl`). So a JSON value can not say its path, an XML element
   its namespace, a Julia call the function it names, an INI section its chain.
2. **The place is already known.** Each move of the pointer writes the mouse
   target: each document on the path holds the path from itself down to the part
   under the pointer (`replace_mouse_target!`, `PathChain.jl`; see
   [mouse-target.md](../../documentation/package/kernel/mouse-target.md)). A file
   holds the path from the file to the part. A command that runs a tooltip with
   no pointer has the selection, which is a chain of the same kind.
3. **A container reads the dwell anyway.** After the part, each document around
   it reads the dwell with its own table, from the inside out
   (`_read_outward`, `ProjectionDefaults.jl`), and a tooltip of a container is
   joined as a later layer.

## The decision

The user agreed on 2026-10-21:

- **A container says what the pointer is on, from its own mouse target.** Its
  tooltip binding reads `get_mouse_target(container)`, or the selection when no
  pointer is set, takes the part at the end of that path, and makes a note
  about it. No new mechanism: one binding for each container, as the invariant
  PAR-DECIDE-LOCALLY asks.
- **The order of the layers stays.** When the part has a note of its own, such
  as a Julia function, the note of the file is the next layer, which F2 shows.
  When the part has none, as a JSON value has none, the note of the file shows
  first.

An example: the pointer rests on `"Alice"` in a JSON file. The value answers
nothing. The file answers a note: title `a.json`, facts "Path: users[3].name",
"Type: String", "Length: 5".

## Steps

The steps are fixed. Each step is one commit. projectured-julia lands first.

1. [x] **The part that a container points at.** A helper of the tooltip slice,
   `find_pointed_part(container) -> (steps, part)` or `nothing`: the path of the
   mouse target, else of the selection, cut to its deepest document, and the
   document there. The first test proves the ground of the plan in a real
   editor: a dwell on a value of a JSON file in a text view reaches the table of
   the `JsonFile`. If it does not, the step records which document of the walk
   is the outermost one of the domain, and the later steps use that one.
   Test: a new `test_pointed_part()`, through an editor.

   Done. As built:
   - `find_pointed_part(container)` answers `(part, documents, steps)`: it
     follows the mouse target, else the selection, while each step leads to a
     document, so the place of a caret inside a string is left out.
   - The ground holds in the application: with "a.json" open in a tab, a move
     on "Alice" writes the mouse target
     `.content.content.entries[1].value.elements[1].entries[1].value.value{0}`
     into the `JsonFile`, the value answers no dwell, and a tooltip binding of
     the `JsonFile` answers it with that path in hand.
   - A file drawn bare in a window by `NaturalToGraphics`, as the tooltip window
     test draws its documents, takes no move into its content: the window keeps
     the empty path. So a test of a dwell on a file uses the setup of
     `ApplicationTest` (`_app_make_scene`), which opens the file as the
     application does.
   - Test: `test_tooltip_note()` 40 (a container finds the part under the
     pointer, cut at the text of a label, and else its selected part),
     `test_platform_layering()`, `test_platform_slice_edges()`.
2. [x] **JSON and YAML.** `JsonFile` and `YamlFile` say: the path of the part
   (`users[3].name`), its type, and its length, its value or its count of
   entries. Test: the JSON and YAML suites.

   Done. As built:
   - `JsonFile` and `YamlFile` splice a tooltip binding, "Show the path of the
     part", into their `@gestures` table. The note: the file name as the title;
     the facts Path, Type (String, Number, Boolean, Null, Object or Mapping,
     Array or Sequence; an entry says the type of its value), and Length, Value,
     Entries or Elements.
   - The path counts the elements of an array from 1, as the editor does, and
     writes a key that is not a plain name in brackets: `["my key"]`. The path
     of the root is "the root".
   - The owner of a part is the nearest node of the domain above it in the walk,
     because the list of the elements of an array is a document of its own
     between the array and the element.
   - Test: `test_json_file_note()` and `test_yaml_file_note()` (a mouse target in
     a string, a key in brackets, a number, an array, and the selection with no
     pointer), and `test_pointed_part()` in the umbrella package: "a.json" open
     as the application opens it, a move and a dwell on "Alice" answer the note
     with "Path: users[1].name". `test_json()` 245, `test_yaml()` 64 and 2
     broken, as before.
3. [x] **XML.** `XmlFile` says for an element: its path (`/root/a[2]/b`), the
   namespace of its prefix from the `xmlns` of the elements on the path, and its
   attributes and children. Test: the XML suite.

   Done (written by a code agent, reviewed). For the text "hi" in
   `<root xmlns="urn:r"><a><b>hi</b></a><a/></root>`: Path `/root/a[1]/b`,
   Namespace `urn:r`, Attributes 0, Children 0. A text or an attribute says the
   element that holds it. Test: `test_xml_file_note()` 6, `test_xml()` 86.
4. [x] **Julia.** `JuliaFile` says for a call: the signature and the docstring of
   the function that it names, when that function is in the same file, with
   `_make_julia_function_note`. Test: `test_julia_tooltip()`.

   Done (written by a code agent, reviewed, and checked in the application).
   The file says the note of the called function: its name as the title, its
   signature as code, its docstring as text. In the application, a dwell on
   the call `helper(x)` inside `function bar` gives one note, from the file:
   "helper", `helper(y)`, "Add one."; the enclosing function answers nothing
   there. Only a call of a plain name is covered: `a.b(x)` and `f{T}(x)` say
   nothing, and of two functions of one name the first is said. The table is
   `get_document_gesture_bindings_own(::Type{JuliaFile})`, as `JuliaFunction`
   has, because a `@gestures` block in this file breaks the test that reads
   the file back through `parse_julia`. Test: `test_julia_file_note()` 8,
   `test_julia()` 690.
5. [x] **Graph.** The graph says for a vertex: its edges in and out. Test: the
   graph suite.

   Done (written by a code agent, reviewed). `GraphGraph` says for a vertex:
   Edges out, Edges in, and the Label of a vertex whose content is a string.
   No graph file type exists, so the binding is on `GraphGraph`. An edge says
   nothing. Test: `test_graph_note()` 4, `test_graph()` 471.
6. [ ] **omnet-julia INI.** `IniFile` says for a section: the chain of
   `extends`, such as `X → Base → General`, and its runs; for the value of
   `extends =`: the same chain. Test: the INI suite of omnet-julia.
7. [ ] **The documentation and the catalog.** tooltip.md (a container says what
   the pointer is on), the guides of the domains, and the catalog marks item 5
   done.

## Not in this plan

- The other five items of wave 2, and wave 3.
- A tooltip of a part that is not a document, such as a character of a text.
- The graph of the topology card of omnet-julia. The view makes that graph
  itself, so it holds no mouse target; the deferred plan
  [a-graph-lights-the-part-under-the-pointer.md](a-graph-lights-the-part-under-the-pointer.md)
  covers it. Step 5 is for a graph that is a document of its own.
