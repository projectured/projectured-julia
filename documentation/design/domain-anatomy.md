# The parts of a domain

> **Kind:** design · **Status:** current · **Stands on:** [concepts.md](concepts.md), [domain-inventory.md](domain-inventory.md), [projection-system.md](../package/kernel/projection-system.md)

This document describes the parts that every domain package has, and how an edit and a registration travel through them. The design document of each domain describes only how that domain differs from this shape. Read this document first, then the document of the domain.

## The parts

A domain package holds the documents of one kind of content and everything that is true of that content. JSON is the reference: each part below names the JSON file that has it.

| Part | What it is | JSON |
| --- | --- | --- |
| The documents | `@document` structs under one abstract root | `source/json/JsonDocument.jl` |
| The placeholder kit | `XNothing`, `XInsertion` and their traits, from `@domain` | `@domain Json` |
| The gestures | the structural edits, as `@gestures` tables on the document types | `JsonDocument.jl` |
| The printer | `XToSyntax`, one projection rule for each document type | `source/json/JsonToSyntax.jl` |
| The parser | a hand-written reader of the text form | `source/json/JsonParser.jl` |
| The file type | an `XFile <: FileDocument` for the file extension | `source/json/JsonFile.jl` |
| The registration | the `__init__` of the module | `source/json/JsonModule.jl` |
| The examples | a document factory and a projection factory | `example/json/` |
| The tests | `test_json()`, with the layering guard first | `test/json/JsonSuite.jl` |

A domain has no third-party dependency. A domain that needs one becomes an opt-in package, as `ProjecturedOdbc` is for live SQL queries. [package-rules.md](../rule/package-rules.md) states the rule.

## The documents

`@domain Json` makes the abstract root `JsonDocument`, the empty placeholder `JsonNothing`, the typed-name buffer `JsonInsertion`, the Insert-key gesture from the placeholder to the buffer, and the traits that the completion reads. [macros.md](../package/kernel/macros.md#domain) lists what it makes. The package that holds the macro is `ProjecturedDomain`; see [domain.md](../package/domain/domain.md).

Each concrete type is an `@document` struct. The macro wraps each field in a reactive cell and adds a `selection` field. **The field names are the reference vocabulary of the domain**: a selection path such as `entries[1].value.value{3}` names them. A rename of a field breaks every stored reference to it.

A container field holds a `CellVector`. A structural change of the vector invalidates only the cells that read that vector, so an insert repaints one container and not the whole document.

`@insertion JsonString = @with_selection JsonString("") value{0}` says what a committed insertion of a type becomes, with the caret already in place. A type without `@insertion` becomes its zero-argument constructor.

## The printer chain

Most domains reach the screen through three projections:

```
JsonObject ──JsonToSyntax──▶ SyntaxNode ──SyntaxToText──▶ TextBlock ──TextToGraphics──▶ GraphicsCanvas
```

`XToSyntax()` is a `TypeDispatchingProjection` with one rule for each document type, and the chain wraps it in a `RecursiveProjection`. Two rules of the table come from the shared kit, and `@domain` does not write them:

```julia
JsonInsertion => DomainInsertionToSyntaxLeaf(JsonDocument),
JsonNothing   => InsertionNothingToSyntaxLeaf(),
```

A rule is written with `@projection_template` when it can be. The markers `bound(:field, …)` and `collection(:field)` say which output part holds which input field. From them the template makes the printer, both reference maps and the reader. A rule is written by hand only when the output has a part that no field produces but that must take a caret. The XML element chrome and the YAML block sequence are the two cases. [syntax.md](../package/syntax/syntax.md) and [text.md](../package/text/text.md) describe the two shared stages.

Four other routes exist:

- **The domain draws itself.** `chart` and `sequencechart` project to graphics directly, with the axis arithmetic of `ProjecturedPlot`.
- **The domain becomes a graph.** `fsm` and `process` build a `GraphGraph` and reuse the layout and graphics stages of `graph`.
- **The domain becomes a page.** `markdown` and `rst` also project a page to a vertical layout of blocks, and each block goes through its own chain. So a block of another domain in the page takes its own clicks.
- **The domain becomes widgets.** `conversation` and `assistant` project to widgets. `filesystem` has a syntax chain and a widget tree.

## How an edit goes back

The editor gives an event to the outermost projection. Each stage maps it one step inward, and the operation that comes back out of the domain stage is the edit. The reader section of [projection-system.md](../package/kernel/projection-system.md) states the rules. For a domain, three paths matter:

1. **A typed character.** `TextToGraphics` finds the span, and the `@gestures` table of `TextBlock` makes a `ReplaceTextRangeOperation` on the flat text. It is lowered to a `ReplaceStringRangeOperation` on one span. `SyntaxToText` maps the span to the leaf, and the `bound` marker of the domain rule maps the leaf to the field.
2. **A structural gesture.** A key that the text and syntax stages do not use, such as `,` in a JSON array, reaches the template reader of the domain. The reader gives it to the selected child first. If the child returns `nothing`, the reader calls `read_gesture` on its own document, which reads the `@gestures` table. So the nearest enclosing node that has a rule for the key makes the edit.
3. **A retype.** On a whole-element selection, a key such as `[` replaces the selected node. The shared verbs of `ProjecturedDomain` make these operations: `replace_selected_document`, `append_insertion_operation` and `move_to_field`. They return a `ReplaceReferencedValueOperation`, so a domain defines no operation type for an insert or a delete.

A rule marked `override(...)` takes a key before the text stage uses it. XML uses this for `<` and `"` inside an element, because the two characters can not occur in a tag name.

## The placeholder and the insertion

An empty place in a document holds `JsonNothing`. `InsertionNothingToSyntaxLeaf` prints it as a muted label, "empty json". A printable key on the placeholder runs the create gesture of the document type. So `{` on "empty json" makes a `JsonObject`.

The Insert key replaces the placeholder with a `JsonInsertion` buffer. The candidates of the buffer come from reflection over the loaded types: every concrete, insertable subtype of `JsonDocument`. No list of names exists, so a new document type is a candidate as soon as Julia evaluates its `struct`. Tab completes the name, Enter commits it, and Escape goes back to the placeholder. A domain whose insertion parses source text builds its own leaf. `SqlInsertionToSyntaxLeaf` is an `InsertionToSyntaxLeaf` with `parse_completion(parse_sql_text)`. `JuliaInsertionToSyntaxLeaf` is a projection of its own, and the `@gestures` table of `JuliaInsertion` parses the text on commit.

## The text form and the file

A domain with a text form has a parser, `parse_json`. The parsers are hand-written, because a domain has no third-party dependency. Each one reads a subset of its format, and the document of the domain says which subset.

The file type is an `@document struct JsonFile <: FileDocument` with a `filename` and a `content`. It implements the contract of `ProjecturedSerialization`: `get_file_domain`, `parse_file_content`, `emit_text`, `make_reference_leaf` and `find_reference_marker`. The last two spell a reference to a node in another file. The spelling depends on the format: a JSON string, an XML `pred:ref` element, a Markdown fence or an RST directive. [serialization.md](../package/serialization/serialization.md) describes the multi-file project that uses them.

`make_document_seed(::Val{:json})` gives the document that a new, empty `.json` file starts from.

## The registration

The `__init__` of the module registers the domain with two tables:

```julia
register_natural_domain!(JsonDocument; rung = :syntax, make = () -> JsonToSyntax(),
                         format = :json, extension = ".json", parse = parse_json)
register_file_document_type!(".json", JsonFile)
```

The first call gives the domain these, without more code:

- `print_natural_text(document)` and `parse_natural_text(:json, text)`;
- `import_document` and `export_document` by the file extension;
- a row in `NaturalToGraphics`, so that a tab draws the document when it has no designed view;
- the text form that a tool gives to a language model.

A domain calls `register_natural_syntax!` or `register_natural_graphics!` as well when the general renderer must use a different projection. Markdown draws the rendered page in a tab and prints the source form to a file. [natural.md](../package/natural/natural.md) describes the two tables.

## One domain inside another

A domain that holds the documents of another domain depends on that package. A state machine guard is a Julia expression, so `ProjecturedFsm` depends on `ProjecturedJulia`. The printer of the outer domain puts the rules of the inner domain in its dispatch table, and the inner documents go through their own chain. `ProjecturedDbCatalog` depends on `ProjecturedSql` for the other reason: its printer makes SQL documents. [domain-inventory.md](domain-inventory.md) has the table of these edges.

## Usage

Every domain has two example factories, and the example registry pairs them:

```julia
document   = make_json_document_example()
projection = make_json_projection_example()     # the chain above, with a real text measure
run_example("json")                             # the registered pair, in a window
run_example(document, projection; name = "mine")
print_natural_text(parse_json("""{"a": [1, 2]}"""))
```

`example/projectured/DomainExamples.jl` holds the `Example(...)` registry. `atomic_documents()` holds one small, hand-written document for each document type. `example/projectured/Catalog.jl` builds a generated example from each one, and `CatalogCoverageTest` compares the document types with the catalog and lists the types that have no entry yet. The narrowest test of a domain is `test_example(json_example)`; the test of the package is `test_json()`. [testing-guide.md](../guide/testing-guide.md) lists the others.

## Where the shape does not hold

- `book` has no text form, no file type and no `register_natural_domain!` call.
- `chart`, `sequencechart`, `fsm` and `process` register no natural row. A caller builds their projection chain.
- `markdown`, `rst`, `book` and `math` declare their abstract root by hand and have no `@gestures` tables. `sql` uses `@domain` but has no `@gestures` table either.
- `MathFile` has no reference marker, so a multi-file project can not cut a math document into another file.
- `database` holds an adapter interface and no projection. `odbc` is the opt-in package that implements it.
