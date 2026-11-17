# An XML text keeps its white space

> **Status:** proposed, 2026-11-17. Nothing is built. The defect was found by the contract
> test of [a-file-format-is-declared-once.md](../done/a-file-format-is-declared-once.md)
> (§10, step 5), and the owner moved it to this plan: "can we defer this to another plan?"

## 1. Goal

A load and a save of an XML file write the bytes that the file held. The reader keeps
each character of a text, as XML 1.0 requires (section 2.10, "White Space Handling": "An
XML processor MUST always pass all characters in a document that are not markup through
to the application").

## 2. Current state

- **The reader** drops a text of white space alone and keeps any other text with its
  spaces (`source/domain/xml/XmlParser.jl:114`).
- **The printer** writes the children of each element on lines of their own, one level
  in (`source/domain/xml/XmlToSyntax.jl:95`: `open="\n", sep="\n", close="\n",
  indentation=1`).
- **The syntax slice** moves each line of a leaf after its first by the indent of the
  nodes around it (`source/platform/syntax/SyntaxToText.jl:922` and `:1119`).
- **So each load and save adds white space.** A save writes
  `"<person>\n  <name>\n    Alice\n  </name>\n</person>"`, and the load and save of that
  string writes `"<person>\n  <name>\n    \n        Alice\n      \n  </name>\n</person>"`.
- **The contract test fails** at its XML row: `FileFormatContractTest.jl:82`, the print of
  the print is not the print. It runs in `test_documents()`.

## 3. Decision of the owner

- **D1 (owner, 2026-11-17, "option 2 is fine"). The white space of a text is data.** The
  reader keeps it, and the printer writes each text as it is, on the line of its tags.
  Rejected: (1) the reader removes the white space around a text, because a text such as
  `<code>  x</code>` loses its spaces; (3) a known failure with no fix.

## 4. Design

- **The reader.** In an element whose texts are all white space (element content), a text
  of white space alone is layout, and the reader drops it, as now. In an element with
  another text (mixed content), each text stays, a text of white space alone too: in
  `<p>a <b>x</b> <i>y</i></p>` the space between `</b>` and `<i>` is data.
- **The printer.** An element with a text child prints its children on the line of its
  tags, with no break and no indent: `<name>Alice</name>`, `<p>a <b>x</b> <i>y</i></p>`. An
  element with element children only keeps a line for each child, one level in.
- **The syntax slice (proposed decision P1).** `SyntaxLeaf` gets the field
  `keeps_columns::Bool = false`. No compound moves a line of a leaf with `true`:
  `_make_leaf_chrome_lines` marks no line of it. The XML text leaf sets it, so a text with
  a line break, such as `"\n    Alice\n  "`, prints its lines exactly inside an indented
  element. The default keeps the layout of each other domain. Rejected: a line break of a
  text written as `&#10;`, because it changes the bytes of the file; the indent written
  as the text of each separator, because an element would need to know its depth.
- **Open point O1.** The delimiters of the body follow the children of the element. A
  delimiter can be a computed `TextString`, as the close of the tag leaf is. The
  `indentation::Int` of a `SyntaxNode` is a plain value; step 3 finds whether the template
  builds the body again when a text child comes or goes, or whether the body needs a
  computed indent.

## 5. Steps

- [ ] **1. The reader keeps the texts of mixed content.** Test: `test_xml()`, with new rows
  for element content, mixed content and a text with a line break.
- [ ] **2. `keeps_columns` in the syntax slice** (P1). Test: `test_syntax()`, with a leaf
  of two lines inside an indented node, with and without the field.
- [ ] **3. The printer writes a text on the line of its tags.** The body of a mixed element
  is inline, and the text leaf keeps its columns. Test: `test_xml()`,
  `test_example(xml_example)`, `test_file_format_contract()` (its XML row passes).
- [ ] **4. The list of `ProjecturedXML` records again** (`record_package_calls!`), alone,
  because the lists below it are fresh. Test: a precompile with no warning of a stale list.

## 6. Risks

- **The navigation of the XML example changes**, because a text no longer has a line of
  its own: `test_position_navigation(xml_example)` and the caret tests of XML count the
  places again.
- **Files saved before the fix** hold a text on a line of its own. After the fix they load
  with that white space as data, and they save with the same bytes.

## 7. Found during the work

(empty)
