# Rewrite XmlToSyntax with `@projection_template`

Port `projection/primitive/XmlToSyntax.jl` from hand-written `projection_print` /
`map_reference_forward` / `map_reference_backward` / `projection_read` methods to
the declarative `@projection_template` builder form (like `JsonToSyntax` /
`JuliaToSyntax`). The engine (`ProjectionTemplate.jl`) then supplies reference
mapping and the recursive reader generically from the recorded wiring.

Authoring gestures move to the **document** layer as `@gestures` on the XML types
(mirroring `document/Json.jl`), because the template's generic reader delegates
own-level gestures to `document_read(input, evt)`.

## Baseline (clean `main`, worktree `xml-to-syntax-template`)

| test | Pass/Fail/Error |
|---|---|
| `test_printer(xml_example)` | 7318 / 0 / 0 |
| `test_reader(xml_example)` | 225 / 0 / 0 |
| `test_repl(xml_example)` | 225 / 0 / 0 |
| `test_text_navigation(xml_example)` | 1015 / 0 / 0 |
| `ProjecturedTest.test_xml_to_syntax()` | printer unit test |
| `ProjecturedTest.test_xml_to_syntax_reader()` | reader-command unit test |

Goal: keep all of these green after the rewrite.

## Design — how the XML shapes map onto template markers

Output node shape is unchanged (so SyntaxToText rendering + navigation are
identical). Element node children stay `[tag, attrs, body, close]`.

- **`XmlText` → leaf**: `bound(:content, String, TextString(() -> t.content, style))`
  — atomic leaf; `.content{k} ↔ .value{k}` falls out of `AtomicWiring`.
- **`XmlInsertion` → leaf**: opaque `SyntaxLeaf(TextString("insert XML here", …))`
  (no `bound`) — `∅↔∅` default.
- **`XmlElement` → node**: a fixed-children node (7-arg positional `SyntaxNode`)
  whose raw children Vector is walked by `_fixed_print`:
  1. **tag leaf** — `bound(:tag, …)`, `open="<"`, reactive `close=" "|""`
     → `KeySlot(:tag)`  (`.tag{k} ↔ .children[1].value{k}`).
  2. **attrs node** — `SyntaxNode(collection(:attrs) do a … end; close=">", sep=" ")`
     → `SubNodeSlot` wrapping a `NodeWiring` (F1). Each attribute builds a fixed
     2-leaf node `name = "value"` with `bound(:name)` + `bound(:value)` → two
     `KeySlot`s. Gives `.attrs{i}.name{k} ↔ .children[2].children[i].children[1].value{k}`
     and `.value{k} ↔ …children[2].value{k}` — same as the old hand map.
  3. **body node** — `SyntaxNode(collection(:children); indentation=1)` →
     `SubNodeSlot` wrapping a homogeneous `NodeWiring`; `.children{i}.tail ↔
     .children[3].children[i].tail` delegated (School A).
  4. **close leaf** — plain `SyntaxLeaf(TextString(() -> e.tag, …); open="</", close=">")`,
     no `bound` → `IntroSlot`: display-only, renders the shared `.tag`, carries no
     cursor and maps nothing back (matches the old "display-only" decision).

The two sub-node slots key off distinct input fields (`attrs` vs `children`), so
`_slots_forward`/`_slots_backward`'s "try each sub-node" loop routes cleanly.

## Reader migration (projection reader → document `@gestures`)

Template's generic reader = delegate to focused child, else `document_read(input,
evt)`. So move the XML authoring command set into `document/Xml.jl`:

- `@gestures XmlInsertion` — `<` / `"` replace the (root) insertion with an empty
  element / text node. Child-insertion replace is handled at the element level
  (a whole child is selected as `.children[i]`, an `ElementReference`, which the
  reader does not delegate into — same as JSON, whose parent gesture replaces at
  `doc.selection`).
- `@gestures XmlElement` — `<` / `"` : if the current selection targets a child
  `XmlInsertion`, replace it in place; else append a child element / text and
  select it. `=` moves an attribute name→value. `Space` inserts an attribute
  (gated to tag/attr context). `Insert` appends a generic insertion child.

Helpers (`_xml_child_element_insert`, `_xml_child_text_insert`,
`_xml_generic_insert`, `_xml_attr_insert`, `_xml_in_attr_context`,
`_xml_attr_equals`, plus new `_xml_replace_insertion` / `_xml_element_open` /
`_xml_element_text`) move from the projection file into `document/Xml.jl`.

## Steps

1. [x] Study the macro + reference impls; capture baseline. (done)
2. [x] Add authoring `@gestures` + helpers to `document/Xml.jl`; new imports.
3. [x] Rewrite `XmlToSyntax.jl` printers via `@projection_template`; drop the
   hand-written mappers/readers.
4. [ ] **Verify** (BLOCKED in this environment): the 4 example tests + the 2 XML
   unit tests all green. Julia's parallel precompilation of the 8 packages this
   change invalidates repeatedly crashed the VS Code host, so the run must happen
   in a **plain external terminal**, not the editor's Claude extension:
   ```
   cd .../.claude/worktrees/xml-template
   julia --project=. -e 'using ProjecturedTest, ProjecturedExample; \
     ProjecturedTest.test_xml_to_syntax(); ProjecturedTest.test_xml_to_syntax_reader(); \
     test_printer(xml_example); test_reader(xml_example); \
     test_repl(xml_example); test_text_navigation(xml_example)'
   ```
5. [ ] Once green, move this plan to `plan/done/` (and fix anything the run surfaces).

## Facts discovered during implementation

- `test_xml_to_syntax` / `test_xml_to_syntax_reader` are **not exported** from
  `ProjecturedTest`; call them qualified (`ProjecturedTest.test_xml_to_syntax()`).
- The element node must use the **7-arg positional** `SyntaxNode(open, close, sep,
  vec, indentation, collapsed, selection)` so the raw children Vector reaches the
  children Cell unwrapped (the keyword form's `_children` also passes a Vector
  through, but the positional form matches Julia/Json fixed nodes).
