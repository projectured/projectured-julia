# Strict document types

**Status (2026-10-05): PENDING. Not started.** The owner asked for this plan in the decision
walk of [kernel-audit-fixes.md](kernel-audit-fixes.md), at L10-13. Do not implement it until the
owner asks. The owner accepted the model of §3 on 2026-10-05: no foreign type, and a field that
admits other domains declares `Document`. The pilot domains are Julia, JSON and XML. Every
question of §7 is decided, so the pilot can start when the owner asks.

**Goal:** the declared type of a `@document` field becomes a contract that the reactive layout
keeps. An intermediate state of an edit is the insertion or the nothing of its domain, and a field
that a person edits admits them by its declared type. A wrong value fails at the write that makes
it, not later in a printer. The pilot domains are Julia, JSON and XML.

**Repositories:** projectured-julia for the model and the pilot. omnet-julia and inet-julia
declare their own documents. The check applies to every type at once (S-1), so it reaches their
narrow fields at Step 3. Their loose fields change only when the model goes past the pilot.

## 1. The request

At L10-13 the owner first chose a loose reactive layout, then asked for a strict one:

> The number parsing issue can be solved with having a PrimitiveNumber which supports incomplete
> numbers with type safety. When typein goes into a Julia document, there's JuliaInsertion, so
> this could be typed strictly for each Julia field. For cross domain combinations we could have
> a JuliaForeign which allows contains Document, so it allows combining different domains. Then
> we can have strict type handling. What do we loose? Copy pasting an alien domain has to
> introduce the foreign document type at the boundary but how? Editing a data structure that is
> not @document needs a first projection which maps it to a document data structure to support
> intermediate states.

The ruling, 2026-09-30: L10-13 is A for now, so the law states what the code does today. The
strict model is this plan, with a pilot on the Julia domain.

The ruling, 2026-10-05: no domain gets a foreign type. A field that admits a document of another
domain declares `Document`. §4.1 gives the reason.

The ruling, 2026-10-05: the pilot adds JSON and XML to Julia, because JSON has a full type-in, and
JSON and XML documents are mixed with each other.

## 2. The facts today

**The reactive layout checks no declared type.** An example on main, with `age::Int`:

| Value | `Person` (reactive) | `MCPerson`, `ICPerson` (kind layouts) |
| --- | --- | --- |
| raw `"thirty"` in the constructor | `"thirty"` | `MethodError` |
| `Cell("thirty")` | `"thirty"` | `"thirty"` |
| `ReactiveCell{String}("thirty")` / `MutableCell{String}("thirty")` | `"thirty"` | `"thirty"` |
| the write `x.age = "thirty"` | `"thirty"` | `MethodError` |

- The bounds of the layout are `<: AbstractCell`, not `<: AbstractCell{T}`
  ([DocumentMacro.jl:96-99](../../source/kernel/document/DocumentMacro.jl#L96-L99)). The machinery
  makes an untyped `Cell(x)`, a `ReactiveCell{Any}`, and stores it in typed fields.
- The setter writes `getfield(obj, name)[] = val` with no check
  ([DocumentMacro.jl:221-226](../../source/kernel/document/DocumentMacro.jl#L221-L226)).
- The owner ruled on 2026-09-04 that a reactive cell stores `Any`, so that projections can
  combine domains. This plan keeps the storage `Any` (§3.3).
- The macro already records the declared types: `_declared_value_types` in
  [DocumentCopy.jl:244](../../source/kernel/document/DocumentCopy.jl#L244). L10-21 recommends
  that this becomes a public seam.
- A field declared `Vector{T}` becomes a `CellVector` in the reactive layout, and the `T` is lost
  ([CellVector.jl:33-56](../../source/platform/collection/CellVector.jl#L33-L56)).

**The intermediate states that exist:**

- 20 domains have an insertion type for text that a person types (`JuliaInsertion`,
  `JsonInsertion`, `PrimitiveInsertion`, and others). `@domain` generates the kit. The generated
  insertion is a buffer for a type name
  ([Domain.jl:681-692](../../source/platform/domain/Domain.jl#L681-L692)). Julia and SQL declare
  an insertion of their own that parses its text.
- 3 domains have a type for an empty place: `DocumentNothing`, `JsonNothing`, `JuliaNothing`.
- A number text that does not parse, such as `-` or `1e`, is lost: `splice_number` answers
  `nothing` ([Operations.jl:61-66](../../source/kernel/operation/Operations.jl#L61-L66)). Only the
  primitive domain keeps it: `make_number_edit_operation`
  ([PrimitiveDocument.jl:394-406](../../source/platform/primitive/PrimitiveDocument.jl#L394-L406))
  replaces the number with a `PrimitiveInsertion` of the text, limited to a number.

**The insertion chain.** A `DocumentInsertion` turns into the insertion of a domain by its alias,
for example `xml`, and an insertion turns into a value of its domain by a type name
([InsertionToSyntax.jl:31-33](../../source/platform/syntax/InsertionToSyntax.jl#L31-L33)). No key
turns the insertion of a domain into a `DocumentInsertion`: Escape goes back to the nothing of
the domain ([InsertionToSyntax.jl:276-279](../../source/platform/syntax/InsertionToSyntax.jl#L276-L279)).
The candidates of an insertion come only from its root type, `get_insertion_candidates(root)`
([Domain.jl:321](../../source/platform/domain/Domain.jl#L321)), not from the declared type of
the place where it sits.

**A printer knows its place.** `PrinterContext.reference` is the place of the input relative to
the root of the document ([PrinterContext.jl:11-12](../../source/kernel/projection/PrinterContext.jl#L11-L12)).
`make_child_context(ctx, current_doc, steps...)` records the type of each step
([PrinterContext.jl:148-153](../../source/kernel/projection/PrinterContext.jl#L148-L153)). The form
without `current_doc` records no type. A count by pattern found about 39 typed calls of 149.

**The loose fields.** About 1,080 of about 5,300 declared fields in `source/` are `Any` or
`Document`. The Julia domain has 57 `@document` types with 102 fields:

| Declared type | Fields |
| --- | --- |
| `Document` | 52 |
| `CellVector` (elements untyped) | 20 |
| `String` | 10 |
| `Bool` | 6 |
| `Union{Document,Nothing}` | 5 |
| `Symbol` | 4 |
| `JuliaDocument`, `Int`, `Float64`, `Char` | 1 each |

Other domains hold Julia code in their own loose fields: `FsmTransition.guard` and `.action`,
`FsmState.entry` and `ProcessStep.action` are `Any`; `ProcessModel.parameters` is a
`CellVector`. The pilot does not change them.

The JSON domain has 7 types with 11 fields (§7.1). The XML domain has 3 types with 7 fields in
[XmlDocument.jl](../../source/domain/xml/XmlDocument.jl):

| Field | Declared type |
| --- | --- |
| `XmlAttribute.name`, `XmlAttribute.value`, `XmlText.content`, `XmlElement.tag` | `String` |
| `XmlElement.attrs` | `CellVector` (elements untyped) |
| `XmlElement.children` | `CellVector` (elements untyped) |
| `XmlElement.collapsed` | `Bool` |

The convenience constructors of `XmlElement` tell `attrs` from `children` by the element type of
the vector they get ([XmlDocument.jl:42-55](../../source/domain/xml/XmlDocument.jl#L42-L55)).
The tests put JSON documents into `XmlElement.children`
(`test/projectured/serializer/FileProjectTest.jl`, near lines 201 and 233), so the comment
"holds XmlDocument children" at line 39 does not describe what the tests do.

**The write and the paste.** An operation writes with `_write_slot!`
([Operations.jl:232-238](../../source/kernel/operation/Operations.jl#L232-L238)), which does
`f[] = value` with no check. The paste asks `_is_slot_accepting`
([Clipboard.jl:210](../../source/platform/clipboard/Clipboard.jl#L210)), which refuses a value
that is not of the value type of the cell. For a `ReactiveCell{Any}` that type is `Any`, so the
check passes everything today.

## 3. The model

### 3.1 The declared type of a field

Each field chooses one of four forms:

| Form | Admits | Use it for |
| --- | --- | --- |
| `Any` | every value | a generic container (§3.8) |
| `Document` | every document | a place where domains combine |
| the root type of a domain, for example `JuliaDocument` | the documents of that domain | a place that refuses other domains |
| a narrow type, for example `Bool`, `String` or `Vector{JsonObjectEntry}` | that type only | a place with one kind of value |

The restriction is in the declaration only, and the declaration is local to its domain. To admit
more, a domain makes a declaration wider. A wider declaration never breaks an old value. A
narrower one can, and it needs the lenient load of §3.7.

### 3.2 The intermediate states

The intermediate state of an edit is the insertion or the nothing of the domain of the place:

- Text that a person types becomes the insertion of the domain, to be parsed later.
- An empty place holds the nothing of the domain.
- An incomplete number, a text that does not parse yet, becomes the insertion of its domain (S-5),
  as the primitive domain does today. This is option D of L13-1. A domain whose insertion holds
  only a type name, such as JSON, makes its insertion also hold the text of a number, and turn
  into the number when the text parses.

A field declared `Document` or with the root type of its domain admits these states with no
change. **A narrow field that a person edits admits them explicitly** (§3.9, law 1), for example
`Vector{Union{JsonObjectEntry, JsonInsertion, JsonNothing}}`.

### 3.3 The check

The reactive layout checks a value against the declared type of its field:

- **The setter** checks each write.
- **The constructor** checks the value at construction. A cell given to a constructor is checked
  for its value at that time only. Later writes to that cell from another place are not checked
  (S-3).
- **The `CellVector`** keeps the element type of its field and checks each element write (S-2).
  This changes the collection package.

The storage stays `ReactiveCell{Any}`. So the engine does not change, the cells still combine, and
the invariance problem of `DocumentMacro.jl:96-99` does not come back. The check applies rule 1
and rule 2 of the seam (§3.4): it keeps a value of the type, and it converts a value with no loss.
So the three layouts agree. It does not make an insertion of text, because program code wrote
that text, not a person. A computed field keeps "narrow at the read", because its value exists
only after the computation.

### 3.4 The seam

Every edit goes through an operation (PAR-ONE-WAY-TO-EDIT). The operation knows the parent and the
field of its write. One seam, called at the write, makes the value that the declared type admits:

1. If the value has the declared type, it passes.
2. If Julia has a conversion to the declared type that loses nothing, the seam converts. An `Int`
   into a `Float64` field is an example.
3. If the value is text and the declared type admits the insertion of the domain of the place,
   the text becomes that insertion. The domain of the place is the domain of the parent document:
   `get_domain_insertion` of its root type.
4. Otherwise the seam refuses the write, with a message that says why (S-6).

`_write_slot!` calls the seam, and `_is_slot_accepting` asks it, so a paste target and the write
agree. A paste, a drag, a type-in and an operation from the model all pass through this one place.
A direct write by program code does not pass through the seam. It meets the check of §3.3.

### 3.5 The insertion follows the declared type of its place

The printer of an insertion reads its place from `PrinterContext.reference`: the last step names
the field or the element, and the type checkpoint before it names the parent type. The declared
type of that field filters the candidates, so the person sees only what the type admits. This is
local: the insertion decides from what its parent gives it, and it is right again after a cut and
a paste, because it is printed again at its new place. Each container that can hold an insertion
gives a typed child context, `make_child_context(ctx, current_doc, steps...)`. The filter needs
the public seam for declared types (L10-21).

### 3.6 The widening key

A key turns the insertion of a domain into a `DocumentInsertion`, where the declared type of the
place admits a `DocumentInsertion`. With the chain that exists, a person can then type a document
of any domain into such a place. An example in a `JsonArray` whose elements are `Document`:

1. `,` appends a `JsonInsertion`.
2. The widening key turns it into a `DocumentInsertion`.
3. `xml` turns it into an `XmlInsertion`, or `xml element` makes an `XmlElement`.

Where the elements are `JsonDocument`, the check refuses step 2, and the filter of §3.5 does not
offer the key. The widening key is a gesture binding, not a new mechanism.

### 3.7 The lenient load

Saved files, the undo history, version snapshots and the gesture log can hold values that a new
declaration refuses. A load turns such a value into the insertion of the domain, or a migration
changes the files once. The load never fails on a value that was valid before.

### 3.8 What stays loose

Generic containers keep `Document` or `Any`, because to hold anything is their purpose: the tabs,
the clipboard, the results of the evaluator, the messages of a conversation, and the fault log. So
strictness is a property of a field, not of the whole system.

A data structure that is not a `@document` gets strict types only through a first projection that
maps it to a `@document` structure. That structure holds the intermediate states.

### 3.9 The two laws that keep the model future proof

The model restricts nothing by itself: every combination that the declared types admit is
allowed, and every other one is refused. Two laws keep this true:

1. **Each place that a person can edit admits the intermediate states of its domain**, the
   insertion and the nothing. Otherwise no person can type there. This is the strict form of
   PAR-WIDE-FIELD-TYPES.
2. **Each write through a document meets the check.** The one exception is the cell given to a
   constructor (S-3). So the guarantee is "each write through the document is checked", not "the
   value always has its declared type".

## 4. The trade-offs

**What the strict model costs:**

1. **Migration.** A field that gets a narrower type changes one by one, in three repositories. The
   type-in and example sweeps first show every place that writes a value that its type does not
   admit. Each of those is a hidden fault now, so this is a cost and a benefit at once.
2. **Stored data** needs the lenient load of §3.7.
3. **A narrow field that a person edits** declares a `Union` with the insertion and the nothing.
4. **The filter of the candidates** needs a typed child context in each container that can hold an
   insertion.
5. **Each write costs one type check.** It is an `isa` against a type that the macro knows.

**What the strict model gives:**

- A wrong value fails at the write that makes it, not later in a printer.
- A model gets a clear refusal.
- A person sees only the candidates that the type of the place admits.
- An incomplete number keeps its text.
- The declared type becomes a real contract for the copy, the paste and the type checkpoints.

### 4.1 The rejected alternative: a foreign type in each domain

A foreign type, for example `JuliaForeign <: JuliaDocument` with `content::Document`, lets a field
declare the root type of its domain and still hold a document of another domain. It was rejected
on 2026-10-05:

- **It adds no refusal.** A field declared `JsonDocument` with `JsonForeign` admits every JSON
  document and every other document. That is the set that `Document` admits.
- **It costs a type, a projection and a reader in each domain**, one more step in each path across
  a domain boundary, and a rule at the paste: a pasted `JsonForeign(x)` must give `x` where the
  target admits `x`, or it becomes `XmlForeign(JsonForeign(x))`.
- **Automatic unwrapping does not help.** A read that unwraps gives a value that is not of the
  declared type, and a reference step reads the cell without the getter
  ([ReferenceStep.jl:137](../../source/kernel/reference/ReferenceStep.jl#L137)), so a read and a
  path disagree. If the paths also skip the wrapper, nothing can reach it, and the field behaves
  as `Document`.
- **What it would give:** a typed read, which still must branch over the insertion, the nothing and
  the foreign type, and a node at the boundary. If a boundary needs its own state, an explicit
  embedding node gives it in the places that need one, as `WidgetCard` does with `content`.

## 5. The pilot on the Julia, JSON and XML domains

The pilot measures the migration before the other domains follow. Each step is one commit in a
worktree. The three domains test different parts of the model:

- **Julia** has an insertion of its own that parses text, and the most loose fields (§2).
- **JSON** has a full type-in through the generated insertion chain: the `@insertion` factories
  and the gestures of [JsonDocument.jl](../../source/domain/json/JsonDocument.jl). Its insertion
  must learn the text of a number (§3.2).
- **JSON and XML are mixed in both directions.** XML sits inside JSON in `mixed_example`
  ([MixedDocumentExample.jl:11](../../example/domain/xml/MixedDocumentExample.jl#L11)) and in
  `test/projectured/serializer/FileProjectTest.jl`. JSON sits inside XML in the same test file. So
  the pilot tests the `Document` fields, the widening key (§3.6), and a paste from one domain into
  the other.

- [ ] **Step 0: an inventory.** The check of §3.3 runs in a mode that records each violation and
  does not throw. Because the check applies to every type at once (S-1), run every per-package
  suite, the example sweeps with the type-in and position walks, and the omnet-julia and
  inet-julia suites, one package at a time. The result is the list of every write of a value that
  its declared type does not admit, with its caller.
  *The projectured-julia part is done (2026-10-05, 15:27 to 17:04).* The example sweeps and the
  omnet-julia and inet-julia suites are still to run. The 23 suites found 354 fields of 100
  document types that get a value outside their declared type, in about 20.1 million writes.
  The full list is `/var/tmp/strict-types/analysis.txt`. The groups:
  1. **A missing optional value, 146 fields, about 18.3 million writes.** The field is declared
     `Inset` or `StyleColor`, and the code writes `nothing`. Most of the writes are
     `TextString.padding`, `.line_color` and `.fill_color`, and the margins, borders and paddings
     of the widgets. The declaration must become `Union{…, Nothing}`.
  2. **The colors of the color set that landed on 2026-10-05, about 155 fields of the themes.**
     A field declared `StyleColor` gets a `PaletteColor` or a `ColorRole`. The declaration must
     name the type that the color set gives a color.
  3. **The markers of a template in an output document, 2 fields, about 940,000 writes.**
     `SyntaxLeaf.value` (declared `TextString`) gets `Bound` and `TextGraphics`, and
     `SyntaxNode.children` (declared `CellVector`) gets `Collection`, `Sections` and `Tokens`.
     This is a question of design: the template holds a marker where the output holds a value.
  4. **A plain `Vector` written into a field declared `Vector{T}`, 16 fields.** The cell layout
     holds a `CellVector` there, and the setter writes the plain vector into the cell with no
     wrap. Examples: `Appearance.open_sections`, `ChartTheme.series_colors`,
     `DataFrameView.edits`.
  5. **A lazy list in a field declared `CellVector`, 5 fields** of the layouts and of
     `WidgetTable`: they get a `ListNode`.
  6. **An `UndoBuffer` in the `content` field of a file document, 8 file types**, among them
     `JsonFile`, `XmlFile` and `JuliaFile`, whose `content` is declared with the root type of
     the domain.
  7. **An `Int64` in a field declared `Int32`, 7 fields of the graphics documents.** Julia
     converts it with no loss, so rule 2 admits it.
  8. **Single cases:** `JsonBool.value` and `YamlBool.value` get `nothing` and a `String` (2
     writes, an intermediate state of an edit), `TextNewline.font_color` and
     `TextSpacing.font_color` get a `String`, `SqlSelectItem.expression` gets a
     `SqlScalarValue`, `WidgetLabel.text_style` gets a `StyleFont`, and a few test documents
     write on purpose.

  **The documents of the three pilot domains are nearly clean:** only `JsonBool.value` (2
  writes), the `content` of the three file types (group 6) and two colors of `JuliaTheme`
  (group 2). Almost every refused write is in the output documents of projections, in the
  themes and in the widgets.

  **The tests under the record mode:** kernel 4174 pass, 1 fail; platform 94044 pass, 3 fail;
  integration 1206344 pass, 12 fail, 2 error; anthropic 2 fail, 1 error; ollama 2 error; every
  other suite passes. The kernel failure is the layering guard, which refuses the private name
  that commit `66aaa720b` used; Step 1 removed it. The other failures are in tests of local
  network servers (MCP, web, Anthropic, Ollama), of the font files and of a folder read. The run
  had no network and ran in a user namespace, which is the probable cause. A run of clean `main`
  under the same conditions must confirm it.

  What is built, in commits `3dccce895` and `66aaa720b`:
  - The check is in the new fragment `source/kernel/document/DeclaredType.jl`. The setter and the
    inner constructor that `@document` emits for the cell layout call it, and so does the field
    write of `_write_slot!`, because that write goes into the cell and not through the setter.
  - The mode is `:off` (the default, so the behaviour does not change), `:record` or `:throw`
    (`set_declared_type_check_mode!`). The `:record` mode keeps one `DeclaredTypeMismatchRecord`
    for each owner type, field, declared type and value type, with its count, whether Julia
    converts the value with no loss, and the first 20 callers.
  - The constructor reads each cell with `Base.peek`, so it makes no dependency inside a
    computation, and it leaves a computed cell alone (`is_computed_cell`). The setter leaves a
    `Computation` alone, because a cell computes its value later.
  - `DeclaredTypeMismatchException` is the exception of S-6. Its message has the form
    `SmokePerson.age is declared Int64, and the write gives a String: "fifty"`.
  - An element write into a `CellVector` is not in the inventory yet, because no list field
    declares its element type before Step 4.
  - The run: one process for each of the 23 suites of `test_all()`, each with an 8 GB cap, two
    threads, no network and a time limit, from a separate detached checkout in
    `../projectured-julia-strict-types-inventory`. The environment refers to sibling
    repositories by relative paths, so a checkout must sit in the workspace. The driver and the
    runner are in `/var/tmp/strict-types/`.
- [x] **Step 1: the seam.** Add the seam of §3.4 and call it in `_write_slot!`. Make
  `_is_slot_accepting` ask it.
  *Done (2026-10-05).* What is built, and what differs from §3.4 and S-4:
  - **The signature has the owner first:** `convert_to_declared_type(owner, declared_type,
    value; name = nothing)`. Rule 3 needs the domain of the place, and for an element of a list
    the parent of the write is the `CellVector`, which has no domain. So the caller gives the
    owner: the document of the field, or the nearest document above the list
    (`_find_owner_document` in `Operations.jl`). `name` only names the place in the message.
  - **The seam throws, and the caller applies the mode.** The kernel method applies rules 1, 2
    and 4. `convert_written_value` calls it at the write of `ReplaceReferencedValueOperation`,
    before the mouse target chain, and applies the mode to a refusal: `:throw` throws,
    `:record` records, and `:record` and `:off` write the value as it is. Rules 2 and 3 apply in
    every mode.
  - **Rule 3 is one method in `DomainModule`**, beside the traits in `Domain.jl`, for
    `owner::Document` and `value::AbstractString`. It uses `get_domain_insertion` of the type of
    the owner, and `DocumentInsertion` for a document of no domain. `@domain` does not change.
  - **The paste asks `is_admitted_by_declared_type`.** `_find_paste_target` keeps the owner as
    it walks the path. A field with a declared type asks the seam, and a field with none keeps
    the old test of the value type of its cell.
  - **The public seam for declared types (part of L10-21):** `find_declared_field_type(T, name)`,
    and `find_declared_element_type(collection)`, which answers `nothing` until a `CellVector`
    keeps its element type (Step 3).
  - Tests: a probe of eight cases passes (text into `JsonObjectEntry.value` becomes a
    `JsonInsertion`, an `Int` into a `Float64` field converts, text into a `Document` field of
    no domain becomes a `DocumentInsertion`, a refusal throws in `:throw` and passes in `:off`,
    and three paste checks). `test_clipboard()` passes. `test_kernel()`: 4175 pass, 2 broken,
    no fail.
- [ ] **Step 2: the intermediate states.** An incomplete number becomes the insertion of its
  domain (S-5): a `JuliaInsertion` in a Julia number field, and a `JsonInsertion` in
  `JsonNumber.value`. The generated `JsonInsertion` learns to hold the text of a number and to
  turn into a `JsonNumber` when the text parses, as `PrimitiveInsertion` does. XML has no number
  field.
  *Julia needs no change.* The leaves of `JuliaInteger` and `JuliaFloat` print a fixed text and
  have no bound field (`JuliaToSyntax.jl:26-40`), so a person can not edit a Julia number. A
  Julia number comes only from a `JuliaInsertion`, which keeps source text and commits it with
  `parse_julia`. So an incomplete number already stays in the insertion of the domain.
  *The JSON part is done (2026-10-06).* What is built:
  - **The number becomes the insertion in the reader.** `make_number_range_operation(input,
    reference, replacement)` in the primitive slice makes the edit of a number: a
    `ReplaceNumberRangeOperation` when the number shows the new text exactly or the text is
    empty, else a replace of the number with the document that
    `make_incomplete_number_document(number, text)` gives, with the caret after the key. The
    generic template reader calls it for a number edit. It is in the reader and not in the
    evaluation, because the editor makes the inverse before it evaluates: an evaluation that
    replaced the number would make undo write a number into the text of the insertion.
  - **The domain gives the insertion.** `make_incomplete_number_document` is a hook of the
    primitive slice with the default `nothing`, and JSON answers `JsonInsertion(text)` for a
    `JsonNumber`. The `domain` and `primitive` slices do not depend on each other, and the
    projection slice depends only on `primitive`, so the domain itself gives the method. The
    owner has not yet said yes to these two functions.
  - **The insertion becomes a number again.** `JsonInsertionToSyntaxLeaf` builds an
    `InsertionToSyntaxLeaf` with three options that exist: `commit_at_key` turns the insertion
    into a `JsonNumber` at the key that makes a text that a number shows exactly, Enter commits
    any text that parses as a number, and the completion shows such a text as valid. A text
    such as `1e5` never shows exactly (`100000.0`), so only Enter commits it.
  - **A template gives a text edit to the element that holds it** (the owner's decision,
    2026-10-06: for every element). Before, the template wrote a text edit inside an element
    itself, and asked a child for a retype only when the child was also a template, so an
    insertion leaf inside an array never saw its edit. Now `find_template_output_child(iomap,
    reference)` in `ProjectionTemplate.jl` finds the element that holds the position of the
    output, for each kind of wiring, and the template reader in `ReaderDefaults.jl` gives the
    edit to the reader of the element and puts the input steps in front of the answer, as a
    key event already does. `find_template_value_retype` answers only for a leaf.
  - Tests: `test_json()` 231 pass, no fail. The test "a letter typed into a number is ignored"
    now asserts that `.` after `42` in an array gives `JsonInsertion("42.")`, and that `5` then
    gives `JsonNumber(42.5)`.
- [ ] **Step 3: the check.** Add the check of §3.3 to the reactive layout and to the `CellVector`,
  for every type at once (S-1). A refused write throws the exception type of S-6. The writes that
  Step 0 found in other domains are fixed in this step, or the check does not land.
  *In progress (2026-10-06).* The groups of the inventory (Step 0):
  - [x] **Group 1, a missing optional value:** 147 declarations became `Union{X, Nothing}`: the
    margin, border and padding of 41 widgets, the optional parts of `WidgetShell`, the position
    and size of the scroll panes, scroll bars and `WidgetTransformPane.position`, the inner type
    of `WidgetLabel.text_style::ImmutableCell{…}`, and the fill color, line color and padding of
    `TextString`, `TextSpacing`, `TextNewline` and `TextGraphics`. `JsonBool.value` and
    `YamlBool.value` are not in this group: they get `nothing` and a `String` during an edit.
  - [x] **Group 2, the theme colors:** 155 fields of 20 themes became `ThemeColor`, the union
    `Union{StyleColor, PaletteColor, ColorRole}` that the color set already declares as what a
    color field of a theme holds (`ThemeColor.jl:77`).
  - A Sonnet agent made both edits from the lists of the inventory; the diff is one declaration
    for each listed field and nothing else. A probe in the `:throw` mode constructs
    `ColorTheme()`, `WidgetTheme()` and a `TextString` with no padding. `ChartTheme()` still
    fails on `series_colors`, which is group 4.
  - [ ] Group 3, the markers of a template: waits for the owner.
  - [ ] Group 4, a plain `Vector` in a field declared `Vector{T}`: waits for the owner.
  - [ ] Group 5, a lazy list in a field declared `CellVector`: it belongs with group 4 and S-2.
    `HorizontalLayout` and `VerticalLayout` have constructors that take a `ListNode`, so their
    declaration is too narrow. But the collection sugar of `@document` (Rule C,
    `_collection_slot` in `DocumentMacro.jl`) finds the collection field only when its declared
    type is a bare symbol such as `CellVector`, so `Union{CellVector, ListNode}` would take the
    sugar `HorizontalLayout(a, b)` away. `CellVector{Document}` (S-2) meets the same limit.
  - [x] **Group 6, an overlay in the content of a file:** the `content` of `JsonFile`, `XmlFile`,
    `JuliaFile`, `MarkdownFile`, `MathFile`, `RstFile`, `SqlFile` and `YamlFile` is declared
    `Document`, and `TextFile.content` is `Union{String, Document}`. `make_file_tab(path, wrap)`
    gives every opened file an overlay, such as an `UndoBuffer`, by design. No code reads the
    declared type of `content`.
  - [ ] Group 7, an `Int64` in a field declared `Int32`: rule 2 of the check converts it (the
    check of the setter and of the constructor must apply rules 1 and 2, §3.3).
  - [ ] Group 8, the single cases:
    - `JsonBool.value` and `YamlBool.value`: the REPL walk types text into a bool leaf, and
      `splice_value!` writes a `String` or `nothing` into the bool. An intermediate state of an
      edit, as the incomplete number; it belongs with `make_incomplete_number_document`.
    - `TextNewline.font_color` and `TextSpacing.font_color` are declared `StyleColor = ""`
      (`TextDocument.jl:61`): the default itself is a `String`.
    - `SqlSelectItem.expression` is declared `SqlSelectExpression`, and the SQL parser puts a
      `SqlScalarValue` there, as for `SELECT 1`.
    - `SyntaxLeaf.value` gets a `TextGraphics` from Markdown and RST, an image in a syntax leaf:
      the declaration must be `Union{TextString, TextGraphics}`.
    - `ToyNode.label::String` gets a function in a kernel test of `copy_document` on purpose
      (`DocumentContractTest.jl:236-242`): the test document must declare that field `Any`.
    - `PrimitiveString.value` gets a `SubString`, and `DescriptionList.entries` and
      `ToyList.items` get a vector of a concrete element type: rule 2 converts them.
- [ ] **Step 4: the fields of the three domains.** Each narrow field that a person edits admits
  the insertion and the nothing (law 1).
  - Julia: each of the 52 `Document` fields and the 5 `Union{Document,Nothing}` fields chooses
    `Document` or `JuliaDocument` (§3.1). A field that holds code of another domain stays
    `Document`. The 20 list fields declare their element types.
  - JSON: `JsonArray.elements` and `JsonObject.entries` become `CellVector{Document}`, and
    `JsonObjectEntry.value` stays `Document` (§7.1, S-7).
  - XML: `XmlElement.children` becomes `CellVector{Document}`, because the tests put JSON there.
    `XmlElement.attrs` becomes `CellVector{Document}` (S-8). The convenience constructors of
    `XmlElement` must still tell `attrs` from `children` when both admit any document.
- [ ] **Step 5: the insertion follows its place.** The typed child contexts, the filter of the
  candidates (§3.5), and the widening key (§3.6), in the three domains. The example of §3.6, an
  XML element typed into a `JsonArray`, is the test of acceptance.
- [ ] **Step 6: fix the callers** that the inventory of Step 0 found, one by one.
- [ ] **Step 7: test and measure.** Run `test_julia()`, `test_json()`, `test_xml()`,
  `test_fsm()`, `test_process()`, `test_formula()`, `test_conversation()`, `test_platform()` for
  `FaultPartTest.jl`, the umbrella test file `test/projectured/serializer/FileProjectTest.jl`,
  `test_example(mixed_example)`, and the omnet-julia suite. omnet-julia is in the list because its
  IDE edits Julia code, and `MiniProjectRoundTripTest.jl` puts documents of other domains into a
  `JsonObject`. Report the count of changed callers, the new refusals that a person meets, and
  the cost of the check per write.
- [ ] **Step 8: the owner decides** whether the other domains follow, and in which order.

The laws change only when the pilot lands (§6).

## 6. The laws that change

- **PAR-NO-NESTED-CELL.** L10-13 gives it the text of the loose layout now. After the pilot, the
  reactive layout checks the declared type of each write through a document, with the one
  exception of law 2 (§3.9).
- **PAR-WIDE-FIELD-TYPES** says: "Widen the annotation to admit the transient value". In the strict
  model the transient value is the insertion or the nothing of the domain, and each place that a
  person edits admits them (law 1).
- **PAR-DOMAIN-OWNS-EDITS** names the insertion type and the nothing type of each domain.
- **PAR-DOMAINS-INDEPENDENT** does not change. A field that admits other domains declares
  `Document`, so a domain names no other domain.

## 7. Questions for the owner before the pilot

- **S-1: opt-in or all at once.** Does a strict type say so in its declaration, for example a
  struct-level word of `@document`, so that the pilot changes only the Julia types? Or does the
  check apply to every type, and a loose field stays loose by its `Any` or `Document`?
  *Recommended (mine):* all at once, with no flag. A field declared `Any` or `Document` passes
  everything anyway, so the check changes only the fields that already claim a narrower type. Step
  0 shows how many writes break in the other domains before the check throws.
  *Open (owner, 2026-10-04):* first see how the JSON domain works in the strict model. The study
  is §7.1: in JSON, both give the same result.
  **Decided by the owner, 2026-10-05: all types at once.**
- **S-2: the element type of a list.** `CellVector.elements` is an untyped `Vector`. Does a list
  field declare its element type, for example `arguments::Vector{JuliaDocument}`, and does the
  `CellVector` check each element write? This changes the collection package.
  **Decided by the owner, 2026-10-04: yes.** The `CellVector` must keep the element type that the
  reactive layout drops today.
- **S-3: a cell that a constructor gets.** It becomes the cell of the field, and later writes to it
  can come from another place. Does the constructor check only the value at construction, or does
  it refuse a cell that another place can write?
  **Decided by the owner, 2026-10-04: the constructor checks only the value at construction.**
- **S-4: the seam.** Its name, and the layer that declares it.
  *Recommended (mine), 2026-10-05:* `convert_to_declared_type(declared_type, value)` in the kernel
  layer `document` (10). The name uses the verb `convert_` of naming-rules.md, and it does what
  `Base.convert(T, x)` does: it answers a value of the type, or it refuses. It does not use the
  word "slot", because layout-rules.md uses "slot" for the space that a parent gives a child. The
  layer `document` records the declared types (`_declared_value_types`) and holds the check of
  §3.3. The operation layer (13) and the clipboard are above it, so both can call it. The kernel
  method applies rules 1, 2 and 4 of §3.4. The platform domain package adds rule 3 with the trait
  `get_domain_insertion`, which exists.
  **Decided by the owner, 2026-10-05: as recommended.**
- **S-5: the incomplete number.** A type in the primitive domain (L13-1, option B), and do the
  number fields of the Julia domain (`JuliaInteger.value::Int`, `JuliaFloat.value::Float64`) use it
  or go through `JuliaInsertion`?
  **Decided by the owner, 2026-10-04: always the insertion type of the domain, if the domain has
  one.**
- **S-6: the refusal.** A new exception type for a write that the check refuses, and what a person
  sees when an edit meets it.
  *Recommended (mine), 2026-10-05:*
  - **One exception for the check and the seam:** `DeclaredTypeMismatchException(owner, name,
    declared_type, value)` in the kernel layer `document`, next to the seam. `owner` is the type
    of the document or of the `CellVector`, and `name` is the field or the element index. The name
    follows `ReferenceTypeMismatchException` of the reference layer
    ([ReferenceStep.jl:176](../../source/kernel/reference/ReferenceStep.jl#L176)). Its `showerror`
    says the place, the declared type and the type of the value in one sentence, for example
    `JsonBool.value is declared Bool, and the write gives a String: "yes"`.
  - **A person meets it rarely.** Three things stop a refused value before the write: the paste
    target asks the seam, the candidates of an insertion follow the declared type (§3.5), and the
    widening key shows only where it is admitted (§3.6).
  - **When an operation meets it, it is a fault of the reader** that made an operation that its
    place does not admit. No new path shows it. The `:evaluate` barrier records it, takes the
    change back where an inverse exists
    ([FaultBarriers.jl:162-176](../../source/kernel/editor/FaultBarriers.jl#L162-L176)), and the
    fault targets and the console show the sentence. A strict editor, as `Editor(…)` makes and the
    tests use, throws it at the write.
  - **A model reads the same sentence.** The code tool answers the `showerror` text of an
    exception ([CodeExecution.jl:320](../../source/kernel/tool/CodeExecution.jl#L320)).
  - **The alternative, a silent refusal** with no fault, hides the reader that made the wrong
    operation. It is not recommended.

  **Decided by the owner, 2026-10-05: as recommended.**
- **S-7: the element type of `JsonObject.entries`.** `Vector{JsonObjectEntry}` with the insertion
  and the nothing (law 1), or `Vector{JsonDocument}`? The sort rule
  ([JsonDocument.jl:130-133](../../source/domain/json/JsonDocument.jl#L130-L133)) expects an
  element that is not a `JsonObjectEntry`, "an entry still under construction". No test and no
  gesture puts one there.
  **Decided by the owner, 2026-10-05: mixing is allowed, so the element type is `Document`.** The
  sort rule then keeps every element that is not a `JsonObjectEntry` at the end, in its order.
- **S-8: the element type of `XmlElement.attrs`.** `Vector{XmlAttribute}` with the insertion and
  the nothing (law 1), or `Vector{Document}` as `JsonObject.entries` (S-7)?
  *Recommended (mine), 2026-10-05:* `Vector{Document}`. The attributes of an element and the
  entries of an object are both lists of name and value pairs, and S-7 allows mixing in the
  entries. One rule for both is easier to read.
  **Decided by the owner, 2026-10-05: yes, `CellVector{Document}`.** The four list fields of JSON
  and XML use the same form, `CellVector{Document}` (owner, 2026-10-05). A field declared
  `CellVector{T}` holds a `CellVector` in every layout, and a field declared `Vector{T}` holds a
  plain `Vector` in the native layouts. So `CellVector` gets a type parameter, which S-2 needs
  anyway.

### 7.1 The JSON domain in the strict model (a study for S-1, 2026-10-04)

The JSON domain has 7 types and 11 fields in
[JsonDocument.jl](../../source/domain/json/JsonDocument.jl). A search of projectured-julia,
omnet-julia and inet-julia found every construction and every write of a JSON field.

| Field | Today | Strict |
| --- | --- | --- |
| `JsonBool.value`, the three `collapsed` | `Bool` | no change |
| `JsonString.value`, `JsonObjectEntry.key` | `String` | no change |
| `JsonNumber.value` | `Union{Real, Nothing}` | no change; a text that does not parse becomes a `JsonInsertion` (S-5) |
| `JsonArray.elements` | `CellVector` | `CellVector{Document}`, because the tests put documents of other domains there |
| `JsonObject.entries` | `CellVector` | `CellVector{Document}`, because mixing is allowed (S-7) |
| `JsonObjectEntry.value` | `Document` | no change, for the same reason |

**The writes today are correct where a field is narrow.** The parser writes only values of the
declared types. All other constructor calls in the examples and the tests are correct. No code
writes a raw Julia value or a number text into a JSON field, because `splice_number` answers an
`Int`, a `Float64` or `nothing`. So the check of §3.3 alone breaks nothing in JSON.

**Three places put a document of another domain into a JSON field on purpose.** With `Document`
in `elements` and `value`, they stay valid. A declaration of `JsonDocument` there would refuse
them:

1. `test/projectured/serializer/FileProjectTest.jl`: about 15 places put an `XmlElement`, and one
   place a test document, into a `JsonObject` or a `JsonArray`. The test checks a node that two
   files of different domains hold.
2. `test/platform/fault/FaultPartTest.jl:46` puts a `FaultPartProbe` into a `JsonArray`. The test
   checks that a fault in one leaf costs only that leaf.
3. omnet-julia `test/legacy/simulation/MiniProjectRoundTripTest.jl:59-62` puts a Markdown, an INI
   and a NED document into a `JsonObject`.

A JSON document inside a document of another domain does not change: `GraphVertex.content` and
the cells of a table are `Any`.

**The incomplete number is lost today.** A key `e` after `42` sets `JsonNumber.value` to
`nothing` ([JsonToSyntaxTest.jl:158-160](../../test/domain/json/projection/JsonToSyntaxTest.jl#L158-L160)).
With S-5, the JSON reader replaces the number with a `JsonInsertion` of the text, as the primitive
domain does. The generated `JsonInsertion` must then also hold the text of a number (§3.2).

**What it shows for S-1.** In JSON, opt-in and all at once give the same result. The check
changes nothing where a field is narrow and every write is correct, and the narrowing of a field
is an edit of its declaration in both cases. JSON can not show the cost of all at once in the
other domains. Only the inventory of Step 0 for those domains can show it.

## 8. Related items

- L10-13 of [kernel-audit-fixes.md](kernel-audit-fixes.md): decided A for now. This plan changes
  it again when the pilot lands.
- L13-1: the home of a number text that does not parse. The owner decided it as D on 2026-10-05,
  through S-5. The work belongs to this plan.
- L10-21: the public seam for the declared types of a field. The check, the seam, the clipboard and
  the filter of the candidates need it.
