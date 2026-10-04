# YAML domain

> **Kind:** design · **Status:** current · **Stands on:** [domain-anatomy.md](../../../design/domain-anatomy.md), [json.md](../json/json.md)

The YAML domain, `ProjecturedYAML`, holds YAML data as the same tree of scalars, sequences and mappings that the JSON domain uses. This document says where it differs from the [shape of every domain](../../../design/domain-anatomy.md): the two presentations of one document, the parser subset, and the one hand-written projection.

<img width="396" alt="YAML example" src="../../../asset/image/example/yaml.png">

## How it works

The documents mirror JSON one to one:

| YAML | JSON |
| --- | --- |
| `YamlNull`, `YamlBool`, `YamlNumber`, `YamlString` | `JsonNull`, `JsonBool`, `JsonNumber`, `JsonString` |
| `YamlSequence` (`elements`) | `JsonArray` (`elements`) |
| `YamlMapping` (`entries`), `YamlMappingEntry` (`key`, `value`) | `JsonObject`, `JsonObjectEntry` |

So a reference path has the same form in both domains, for example `entries[1].value.elements[2]`. The gestures are also the same, except that YAML has no value-to-key gesture and no sort by key. The containers have a `collapsed` field, but the projection does not read it yet.

`YamlToSyntax(; style)` has two presentations of the same document:

- **`:block`**, the default: `key: value` lines and `- item` lines, with nesting by indentation and no brackets or commas.
- **`:flow`**: `{a: 1, b: [2, 3]}`, the JSON-like form.

In both styles a string prints without quotes. The mapping rule is one `@projection_template`, and `YamlToSyntax` gives it different `open`, `close`, `sep` and indentation values for each style.

The block sequence is the one hand-written projection, `YamlSequenceToBlockSyntaxNode`. The `collection(...)` marker of the template can not put a `- ` marker in front of each item. So the projection wraps each child in a `SyntaxDelimitation` with the opening delimiter `"- "`, and writes its own printer, reference maps and reader. The reader gives a key to the selected child first, and uses the `@gestures` table of the sequence only when no child is selected.

## The text form

`parse_yaml` reads block mappings and sequences by indentation, flow collections, plain and quoted scalars, numbers, booleans, null, `#` comments and one leading `---`. It does not read these:

- more than one document in a file;
- anchors, aliases and tags;
- block scalars (`|` and `>`);
- a block sequence nested in the same line (`- - x`).

`YamlFile` is the file type. A reference to a node in another file is a `YamlString` whose whole value is the marker, as in JSON.

### The theme

`YamlTheme` holds the look of the YAML projections: the text of a null, a bool, a number, a string and a key, of the delimiters (also the marker of a block sequence) and of the separators (also the colon). Each value has
the default that the domain draws with no appearance. A projection holds its
styles as fields, and no theme; nothing in it scales or asks whether a theme is
scaled. `YamlToSyntax(; style, theme, syntax_theme)` gives each projection the
style of its role with `get_yaml_style`, from `theme`, a `YamlTheme` scaled or
not, or the default styles for `nothing`; the insertion and the empty
placeholder take `syntax_theme`. The natural registration gives the scaled
theme of the `Appearance` of the editor, so the view follows its scales, and
the appearance tab shows a section for `YamlTheme`.

## How it fits

`ProjecturedYAML` depends on the engine and on the platform. No other domain depends on it. Its `__init__` registers:

- the natural notation, with the format `:yaml`, the extension `.yaml` and the parser `parse_yaml`;
- a second parser name, `register_natural_parser!(:yml, parse_yaml)`, so a Markdown fence tagged `yml` also parses;
- `YamlFile` for both `.yaml` and `.yml`.

The registration is at the end of `source/domain/yaml/YamlToSyntax.jl`, not in the module file.

## Design decisions

- **The quote style is not part of the value.** `YamlString` holds only the text. How a string prints is a choice of the projection, so a document does not change when its presentation changes.
- **Block or flow is a parameter of the projection, not a field of the document.** Two views of the same document can show both styles at the same time.
- **`.yml` is the same format under a second name.** It gets a second parser name and a second file extension, but no second domain and no second projection.

## Usage

```julia
doc = YamlMapping("name" => YamlString("Alice"), "age" => YamlNumber(30))
doc = parse_yaml("a: 1\nb:\n  - 2\n  - 3\n")
block = YamlToSyntax()                  # key: value lines
flow  = YamlToSyntax(style = :flow)     # {a: 1, b: [2, 3]}
print_natural_text(doc)                 # the block form, as a String
```

- Examples: `make_yaml_document_example()` and `make_yaml_projection_example()`, registered as `yaml_example`. The atomic catalog has one document for each type.
- Test: `test_yaml()` runs the layering guard and the parser test.

## Limits

- The test package covers only the parser. No test covers the projection, the reader or the gestures.
- The parser reads an anchor (`&x`) as plain text, and it accepts a tab in the indentation. Both are `@test_broken` in `test/domain/yaml/document/YamlParserTest.jl`.
