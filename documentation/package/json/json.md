# JSON domain

> **Kind:** design · **Status:** current · **Stands on:** [domain-anatomy.md](../../design/domain-anatomy.md), [reference.md](../kernel/reference.md)

The JSON domain, `ProjecturedJson`, holds JSON data as a tree of reactive documents. It is the reference domain: [the shape of every domain](../../design/domain-anatomy.md) names a JSON file for each part, so this document covers only what is special to JSON. It describes the document types, the gestures and the parser subset, and it shows the reference paths into a JSON tree.

<img width="396" alt="JSON example" src="../../../asset/image/example/json.png">

## How it works

| Document | Fields | Prints as |
| --- | --- | --- |
| `JsonNull` | none | `null` |
| `JsonBool` | `value::Bool` | `true` or `false` |
| `JsonNumber` | `value::Union{Real, Nothing}` | the number |
| `JsonString` | `value::String` | the escaped text in quotes |
| `JsonArray` | `elements`, `collapsed` | `[a, b]` |
| `JsonObject` | `entries`, `collapsed` | `{"k": v}` |
| `JsonObjectEntry` | `key::String`, `value`, `collapsed` | `"k": v` |

`elements` and `entries` are `CellVector` fields. `@forward_vector_protocol` lets you index a `JsonArray` as a vector, and `@adapt_map_protocol` lets you use a `JsonObject` as a map from key to value. A `JsonNumber` holds `nothing` while you delete all of its text. The printer then shows the hint "enter json number" and does not call `string` on the value.

### The projection

`JsonToSyntax()` has one `@projection_template` rule for each document type. A scalar becomes a `SyntaxLeaf` whose text is `bound` to the `value` field. An empty value shows a muted hint: "enter json string", "enter json number", "enter json bool" or "enter key". The number leaf has `retype = ReplaceNumberRangeOperation`, so a typed digit edits the number as a number. The leaf retypes the edit also when an array or an object holds it: the reader of a container finds the leaf that the edit enters with `find_template_value_retype`, so a digit typed into a cleared number in an array makes a number. A key that can not be part of a number, such as a letter, leaves the number as it is. The string leaf escapes its text with `json_escape` and has the two quotes as `open` and `close`.

An array and an object become a `SyntaxNode` with brackets, the separator `", "` and `indentation = 1`. An object entry has its own rule: a `SyntaxNode` with no brackets, the separator `": "`, a key leaf in quotes, and `project(:value)` for the value. So a bare `JsonObjectEntry` also prints alone, and the atomic catalog has an example of it.

### The gestures

The `@gestures` tables of `source/json/JsonDocument.jl` hold every structural edit:

| Key | Where | Edit |
| --- | --- | --- |
| `n`, `t`, `f` | a whole-element selection | replace it with `null`, `true` or `false` |
| `"`, `[`, `{`, `:` | a whole-element selection | replace it with an empty string, array, object or object entry |
| a digit | a whole-element selection | replace it with that number |
| `,` | in an array | append a `JsonInsertion` at the end of `elements` |
| `,` | in an object | append an empty entry at the end of `entries`, with the caret in its key |
| Tab | in the key of an entry | move the caret to the value |
| no key | in the value of an entry | move the caret to the key |
| no key | in an object | sort the entries by key |

A rule with no key has a name, and the command palette runs it by that name; see [gesturehelp.md](../gesturehelp/gesturehelp.md). The sort is stable, and an entry that is still a placeholder stays at the end.

The retype rules have the guard `_json_replaceable`. It returns `false` when the selection names a `JsonObjectEntry`, so an entry stays a key and value pair and you retype its value instead.

### The text form

`parse_json` is a recursive-descent parser over a vector of characters. It reads objects, arrays, strings, numbers, `true`, `false`, `null` and the backslash escapes with `\uXXXX`. A high surrogate escape followed by a low surrogate escape reads as one character, and a surrogate escape alone raises an error. A `\u` escape needs four hex digits; any other character raises the parser error, which starts with `JSON:`. A number that parses as an `Int` becomes an `Int`, and any other number becomes a `Float64`. The parser raises an error on malformed input and on characters after the value. `parse_json_file(path)` reads a file and parses it.

`JsonFile` is the file type for `.json`. A reference to a node in another file is a `JsonString` whose whole value is the marker, because a string is the only unit of JSON that can hold any text. `emit_text` prints the content with `print_natural_text`. A `.json` path that does not exist opens as a `JsonInsertion`.

## How it fits

`ProjecturedJson` depends on the kernel and on `ProjecturedDomain`, `ProjecturedSyntax`, `ProjecturedText`, `ProjecturedNatural`, `ProjecturedSerialization` and `ProjecturedFileFormat`, with the small packages below them. No other domain package depends on it. The examples put JSON next to other domains, for example in `pane_json_example` and in a split pane with XML.

Its `__init__` in `source/json/JsonModule.jl` registers the natural row with the rung `:syntax`, the format `:json`, the extension `.json` and the parser `parse_json`. It also registers `JsonFile` for `.json`. The [YAML domain](../yaml/yaml.md) mirrors these types one to one.

## Design decisions

- **An object entry is a document of its own.** It has a projection rule, so it can be selected, printed and replaced as one unit. See `plan/pending/catalog-all-documents.md`.
- **A structural key reaches JSON through the chain.** When the text and syntax stages return no operation for a key, the chain gives the raw gesture to the JSON stage. So `,` with the caret on a delimiter inserts a sibling, and a retype key works on a placeholder, with no switch to a structural selection first. See `plan/done/json-contextual-gestures.md`.
- **An entry is retyped through its value.** A retype of the pair would lose the key. `_json_replaceable` holds the rule.
- **The sort and the move back to the key have no key.** Tab and the printable keys already have a meaning in an entry. The command palette reaches the two rules by name.
- **A sorted view and a sorted document are two things.** `json_sorted_example` sorts the entries in the view with a `SortingAtProjection` and does not change the document. The sort rule changes the order in the document.

## Usage

```julia
str = JsonString("hello")
num = JsonNumber(42)
arr = JsonArray([JsonString("a"), JsonNumber(1), JsonBool(true)])
obj = JsonObject("name" => JsonString("Alice"), "age" => JsonNumber(30))

str.value = "world"                  # writes through the cell
arr.elements[1] = JsonString("b")    # or: arr[1] = JsonString("b")

doc = parse_json("""{"people": [{"name": "Alice"}]}""")
print_natural_text(doc)
```

- Examples: `json_example`, `json_sorted_example`, `json_insertion_example` and `pane_json_example`. The factories are `make_json_document_example`, `make_json_projection_example`, `make_json_console_projection_example` and `make_json_sorted_projection_example`. The example document is an object with nested objects and arrays and one `JsonInsertion`. The atomic catalog has one document for each type.
- Test: `test_json()` runs the layering guard, the parser, the documents, the placeholder navigation, the printer, the reader and the gesture collection. `test_json_content_clicks_clean_all()` in the umbrella suite clicks the content characters of `json_example` and `json_sorted_example`, and checks that no path has a `ProjectionReferenceStep`.

### Reference paths

A path uses `[i]` for the i-th item, from 1, and `{k}` for the caret at boundary `k`, from 0. The two are readings of the same axis; see [the boundary axis](../kernel/reference.md#the-boundary-axis). In JSON the axis is the elements of an array, the entries of an object and the characters of a string or a number. `[1]` is the first item of any of them, and `{0}` is the caret before it.

A path is a linked list of steps that follow the fields of the structs. `FieldReferenceStep("entries")` names a field. `ElementReferenceStep(i)` and `PositionReferenceStep(k)` make the two forms of one `RangeReferenceStep`.

A caret in a scalar:

```julia
# Caret at position 3 inside JsonString("hello") (0-based)
@reference value{3}
```

An element of an array:

```julia
arr = JsonArray([JsonString("a"), JsonNumber(42), JsonBool(true)])

# Element 2 (the JsonNumber) - 1-based indexing
@reference elements[2]

# Caret at position 1 inside the value of element 2 - 0-based
@reference elements[2].value{1}
```

An entry of an object:

```julia
obj = JsonObject("name" => JsonString("Alice"), "age" => JsonNumber(30))

# Entry 1 (the "name" entry) - 1-based indexing
@reference entries[1]

# Caret at position 2 inside the key of entry 1 - 0-based
@reference entries[1].key{2}

# The value document of entry 1
@reference entries[1].value

# Caret at position 4 inside the value of entry 1 - 0-based
@reference entries[1].value.value{4}
```

A nested document:

```julia
# Given: {"people": [{"name": "Alice"}]}
# Point to caret position 3 of "Alice":
@reference entries[1].value.elements[1].entries[1].value.value{3}
#          ──────────╴people entry (1-based)
#                     ─────╴the JsonArray element (1-based)
#                           ────────────╴{"name": "Alice"}
#                                        ──────────╴"name" entry (1-based)
#                                                    ─────╴JsonString("Alice")
#                                                          ────────╴caret position 3 (0-based)
```

Each document also has a `selection` field, which `@document` adds. It holds a `Reference` or `nothing` in a cell. Both readings of the axis work in it: `.elements[i]` selects an element, and `.elements{k}` is the caret between two elements, where an insert goes.

## Limits

- No projection reads `collapsed`. The field exists on `JsonArray`, `JsonObject` and `JsonObjectEntry`, but `JsonToSyntax` does not give it to the `SyntaxNode`, so a value set to `true` still prints expanded. `plan/pending/collapse-expand-syntax-nodes.md` holds the open step.
- `,` appends at the end of the container, not after the selected element.
- The parser is not a conformance parser. An unknown escape gives the escaped character.
- An integer that does not fit in an `Int` becomes a `Float64`. A number prints with `string`, so `1e3` prints as `1000.0`.
