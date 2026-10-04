# XML domain

> **Kind:** design · **Status:** current · **Stands on:** [domain-anatomy.md](../../../design/domain-anatomy.md), [json.md](../json/json.md), [reference.md](../../kernel/reference.md)

The XML domain, `ProjecturedXML`, holds an XML document as a tree of elements, text nodes and attributes. This document says where it differs from the [shape of every domain](../../../design/domain-anatomy.md): the attribute as a document, the element chrome and its reader, the gestures, and the reference marker of a file.

<img width="396" alt="XML example" src="../../../asset/image/example/xml.png">

## How it works

| Document | Fields |
| --- | --- |
| `XmlElement` | `tag::String`, `attrs`, `children`, `collapsed` |
| `XmlAttribute` | `name::String`, `value::String` |
| `XmlText` | `content::String` |

`attrs` and `children` are both `CellVector` fields. The constructors that the macro makes can not separate the two vectors, so three hand-written constructors select the slot by the element type of the vector: a `Vector{<:XmlAttribute}` goes to `attrs`, and a `Vector{<:XmlDocument}` goes to `children`. The signatures must stay covariant. An invariant `Vector{XmlAttribute}` does not match the vector of the concrete type that `@document` makes, so the attributes would go into `children`.

### The attribute is a document

An attribute is an `XmlAttribute` document, not a string on the element. So a selection can name an attribute as a whole, or descend into its name or value, as it descends into a child. `XmlToSyntax` has a rule for it, so an attribute also prints alone. You can insert an attribute with a key and replace a placeholder with one. `@adapt_map_protocol` also lets you use an element as a map from attribute name to value.

### The element and its chrome

`XmlToSyntax()` has one `@projection_template` rule for each document type. The element rule makes a `SyntaxConcatenation` of four parts:

1. the tag leaf, `bound(:tag)`, with `<` in front. Its `close` is a space when the element has attributes, and empty when it has none;
2. the attribute node, `collection(:attrs)`, with the separator `" "` and the closing `>`;
3. the body node, `collection(:children)`, indented by one level;
4. the closing tag `</tag>`, which prints the same `tag` field again but has no `bound`.

An attribute prints as `name="value"`, and text prints with `&`, `<` and `>` escaped. An attribute value escapes `&`, `<` and `"`. An edit of the tag changes both tags, because both read the one field.

The delimiters and the closing tag are chrome that no field produces. The backward map of the template names a caret there by the rule's own introduced step, which holds the path of the part in the rule's output, and the forward map gives that path back. So the printer, the reference maps and every reader come from the template.

### The gestures

| Key | Where | Edit |
| --- | --- | --- |
| `"`, `<`, `@` | an `XmlNothing` or `XmlInsertion` is selected | replace it with text, an element or an attribute |
| `<`, `"` | in an element, also with the caret in the tag | append an empty element or text to `children` |
| Insert | in an element | append an `XmlInsertion` to `children` |
| Space | on the element, its tag or an attribute | append an empty attribute, with the caret in its name |
| `=` | in the name of an attribute | move the caret to the value |
| no key | in the value of an attribute | move the caret to the name |

A letter or a digit on a placeholder is not a retype key, so it goes into the name of an insertion buffer. The two element keys `<` and `"` are `override` bindings: a tag name can not hold either character, so the element takes the key before the text stage makes it a character. `=` is an `override` binding for the same reason: an attribute name can not hold it. Outside an attribute name its rule returns `nothing`, so there `=` stays a character. Space does not fire when the caret is in a child, so a space in text stays a space.

### The text form

`parse_xml` returns the root element. It reads nested elements, attributes in double or single quotes, text, self-closing tags, the five named entities and the numeric character references, such as `&#65;` and `&#x41;`. One pass reads all of them, so `&amp;#65;` gives the text `&#65;`. A reference to a code point that is not a character stays as text. It skips the XML declaration, comments and `<!…>` declarations, so a save does not write them back. A text node that holds only white space is dropped. The parser has no namespaces and no DTD: a `:` is a character of a name.

`XmlFile` is the file type for `.xml`. A reference to a node in another file is a `pred:ref` element whose one text child is the marker, for example `<pred:ref>&lt;&lt;file("a.xml")&gt;&gt;</pred:ref>`. An element is the opaque unit of XML, and a text node can exist only inside an element. `find_reference_marker` accepts only an element with the tag `PRED_REF_ELEMENT_TAG` and exactly one `XmlText` child. An `.xml` path that does not exist opens as an `XmlInsertion`.

### The theme

`XmlTheme` holds the look of the XML projections: the text of a text node, a tag, a delimiter, the name and the value of an attribute, and the quotes. Each value has
the default that the domain draws with no appearance. A projection holds its
styles as fields, and no theme; nothing in it scales or asks whether a theme is
scaled. `XmlToSyntax(; theme, syntax_theme)` gives each projection the style of
its role with `get_xml_style`, from `theme`, a `XmlTheme` scaled or not, or the
default styles for `nothing`; the insertion and the empty placeholder take
`syntax_theme`. The natural registration gives the scaled theme of the
`Appearance` of the editor, so the view follows its scales, and the appearance
tab shows a section for `XmlTheme`.

## How it fits

`ProjecturedXML` depends on the kernel and the platform. No other domain package depends on it. Its `__init__` registers the natural row with the rung `:syntax`, the format `:xml`, the extension `.xml` and the parser `parse_xml`, and it registers `XmlFile` for `.xml`.

The mixed example puts XML inside JSON: `JsonXmlToSyntax()` in `example/domain/xml/` is one dispatch table with the rules of both domains, and the document is a `JsonObject` whose value is an `XmlElement`.

## Design decisions

- **An attribute is a document.** A selection can then reach an attribute value as it reaches a child, and the attribute can be inserted and replaced. See [plan/done/xml-attribute-insertable.md](../../../../plan/done/xml-attribute-insertable.md).
- **The authoring edits are `@gestures` on the document types.** The projection keeps only the printer and the caret mapping. The edits are splices through `ReplaceReferencedValueOperation`, so XML defines no operation type. See [plan/done/xml-authoring-gestures.md](../../../../plan/done/xml-authoring-gestures.md) and [plan/done/xml-to-syntax-template.md](../../../../plan/done/xml-to-syntax-template.md).
- **A caret on the chrome is the rule's own introduced step.** It holds the path of the delimiter in the output of the rule, so the forward map gives the same caret back.
- **`<`, `"` and `=` override the text stage.** Neither `<` nor `"` can occur in a tag name, so the keys can mean "insert a child" with the caret in the name. `=` can not occur in an attribute name, so it moves the caret to the value.
- **The reference marker is an element.** JSON and YAML use a string, Markdown a fence: each format spells a reference with its own opaque unit. See [plan/done/document-file-storage.md](../../../../plan/done/document-file-storage.md).

## Usage

```julia
text = XmlText("Hello world")
attr = XmlAttribute("id", "123")
elem = XmlElement("div", [XmlAttribute("class", "container")])     # attributes only
elem = XmlElement("p", [XmlText("Paragraph text")])                # children only
elem = XmlElement("div", [XmlAttribute("class", "container")], [XmlText("Content")])

text.content = "New text"                    # writes through the cell
push!(elem.children, XmlText("More content"))
doc = parse_xml("<a id=\"1\"><b>x</b></a>")
```

- Examples: `xml_example` and `mixed_example`. The document of `xml_example` is a library of books with attributes and an `XmlInsertion`. The factories are `make_xml_document_example`, `make_xml_projection_example`, `make_mixed_document_example` and `make_mixed_projection_example`. The atomic catalog has one document for each type.
- Test: `test_xml()` runs the layering guard, the parser, the printer, the reader on the XML stage alone, and `test_xml_override_gestures()` on the full chain.

### Reference paths

The paths use `[i]` for the i-th item, from 1, and `{k}` for the caret at boundary `k`, from 0, as in [JSON](../json/json.md). In XML the axis is the children, the attributes and the characters of a text or an attribute:

| Path | Names |
| --- | --- |
| `attrs[2]` | the second attribute, whole |
| `attrs{1}` | the caret between the first and the second attribute |
| `attrs[1].value{3}` | the caret after the third character of the first attribute value |
| `children[1]` | the first child |
| `children[1].content{0}` | the caret before the first character of a text child |
| `tag{2}` | the caret after the second character of the tag |

## Limits

- An empty text, tag, attribute name or attribute value shows no hint. JSON and YAML show one with `make_hinted_text`. The four hints "enter xml text", "enter xml element name", "enter xml attribute name" and "enter xml attribute value" are phase 5 of [plan/pending/xml-to-syntax-lisp-parity.md](../../../../plan/pending/xml-to-syntax-lisp-parity.md).
- No projection reads `collapsed`. `XmlToSyntax` does not give it to the output, and `SyntaxConcatenation` has no `collapsed` field. [plan/pending/collapse-expand-syntax-nodes.md](../../../../plan/pending/collapse-expand-syntax-nodes.md) holds the open step.
- An element with no children prints as `<tag></tag>`, never as `<tag/>`.
- The parser raises an error on a CDATA section.
