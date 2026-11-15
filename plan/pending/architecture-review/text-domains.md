# Architecture review: the text-like domains

Commit 3a9b4fae4. Reviewer area key: text-domains.

## Scope

Paths: `source/domain/{json,xml,yaml,sql,julia,markdown,rst,math,formula,book}` (22 193 lines in 69 files), `source/adapter/languageserver` (946 lines), `package/ProjecturedJSON*`, `package/ProjecturedSQL*`, `example/domain/json`, `test/domain/json`.

Read in full, about 4 700 lines:

- JSON: all six files (735 lines).
- XML: the module, the documents, the projection, the file (448 lines). YAML: the same four (545 lines).
- The module file of every other domain, and every `*File.jl` (SQL, math, Markdown, RST, Julia).
- `JuliaInsertionToSyntax.jl`, `MarkdownDocument.jl`, `MarkdownToLayout.jl`, `RstToLayout.jl`, `FormulaToGraphics.jl`, `FormulaToTable.jl`, `LanguageServerModule.jl`.
- The roots of the three JSON packages, `JsonProjectionExample.jl`, `JsonSuite.jl`.
- In the platform, because the domains call them: `NaturalRegistry.jl`, the registration half of `NaturalNotation.jl`.

Sampled, about 2 500 lines: `MarkdownToSyntax.jl` (lines 1 to 640), `RstToSyntax.jl` (1 to 160 and 829 to 960, the rest by outline), `JuliaToSyntax.jl` (1 to 200 and the builder), `JuliaDocument.jl` (1 to 135), `FormulaEdit.jl` (1 to 200), `FormulaToSyntax.jl` (1 to 140 and the builder), `MathToGraphics.jl` (the key reader, 1940 to 2045), `LanguageServerDocument.jl`, `BookToSyntax.jl` (the list rule and the builder), `InsertionToSyntax.jl` (the head, the policies, the constructors), `ProjectionTemplate.jl` (the markers and the atomic print), `DocumentFile.jl` (the read and the save of a tab). The parsers of SQL, Julia, Markdown, RST and math, `SqlToSyntax.jl`, `MathToSyntax.jl`, `FormulaDocument.jl` and `FormulaComputation.jl` were read by outline and by `grep` only. A cell of a matrix that I did not check says so.

Documents read: `concepts.md`, `architecture-decisions.md`, `domain-anatomy.md`, `domain-inventory.md`, the domain and projection sections of `architecture-invariants.md`, `domain.md`, `syntax.md`, and the domain documents of JSON, SQL, YAML and book in full, of Julia and math in part. Plans: the head of each of the sixteen named plans, and the parts cited below.

## State

The skeleton of the area is sound. Every domain has the same parts in the same places: documents, a parser, a projection to syntax, a file type, a theme, a module. JSON, XML and Julia write every rule of their printer with `@projection_template`, the macro that makes the printer, both reference maps and the reader from one builder. No domain defines an operation type for an insert or a delete: the three shared verbs give `ReplaceReferencedValueOperation`. The natural registry gives each domain its print, its parse, its import and its export from one call.

The main weakness is that the general mechanisms fit the shape of JSON, and stop there. A domain that needs one thing more leaves the mechanism and writes its own, and the next domain copies it. A marker before each item of a list is written by hand four times. A value that a subtree inherits, such as an indent or a bold font, is carried in three different ways. A text buffer that commits by parsing exists three times. The page that stacks blocks is written three times. Five of the ten domains do not use the placeholder kit at all, so the insert-by-typing of the project works in half of the area.

The second weakness is that one fact is declared in several tables. A format has a row in the natural registry, a row in the registry of file types, a method for its seed and three contract methods that repeat the first row. A tab reads its file through the first table and writes it through the second.

So the answer to the sentence of `concepts.md`, "Type-in of single characters does not work the same way in every domain", is structural. Type-in is made of four separate mechanisms, and each domain takes a different subset. The inventory shows the subsets, and TD-1, TD-7 and TD-8 name the three causes that no plan covers.

## Inventory

### Domain by part, with line counts

| Domain | Documents | Parser | To syntax | Other projections | File | Theme | `__init__` is in | Example | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| JSON | 152 | 189 | 193 | none | 90 | 38 | `JsonModule.jl` | 109 | 908 |
| XML | 123 | 184 | 163 | none | 103 | 34 | `XmlModule.jl` | 113 | 346 |
| YAML | 108 | 338 | 308 | none | 91 | 36 | `YamlToSyntax.jl` | 56 | 209 |
| SQL | 358 | 1211 | 2013 | none | 30 | 52 | `SqlToSyntax.jl` | 162 | 973 |
| Julia | 788 | 870 | 1158, and 225 for the insertion | code pieces 59, expression 74 | 189 | 68 | `JuliaModule.jl` | 142 | 1870 |
| Markdown | 218 | 343 | 701 | page layout 234, link 111 | 139 | 71 | `MarkdownModule.jl` | 80 | 916 |
| RST | 572 | 762 | 1458 | page layout 189, link 100 | 132 | 79 | `RstModule.jl` | 131 | 581 |
| Math | 486 | 564 | 699 | graphics 2118 | 24 | 47 | `MathToSyntax.jl` | 162 | 610 |
| Formula | 944, computation 243, edit 234 | none (`MathToJulia.jl` 205) | 478 | layout 76, table 63 | none | 37 | `FormulaModule.jl` | 116 | 1244 |
| Book | 90 | none | 664 | none | none | 41 | `BookToSyntax.jl` | 102 | 168 |

What is nearly the same in every domain and written by hand in each:

- the file type: the same three fields and the same three contract lines (TD-4);
- the registration: two to five calls that restate one fact (TD-4, TD-10);
- the builder `XToSyntax(; theme)`: each style role is named once as the default of a field and once in the builder (348 defaults, about 196 builder arguments in the ten domains). This follows the owner's decision that a projection holds its styles and a builder fills them; see "Examined and sound";
- the cursor of the parser: `_Cur`, `_eof`, `_peek`, `_next!`, `_skipws!`, `_expect!` are the same 15 lines in [JsonParser.jl:11](../../../source/domain/json/JsonParser.jl#L11) and [XmlParser.jl:17](../../../source/domain/xml/XmlParser.jl#L17);
- the example chain `ChainingProjection(RecursiveProjection(XToSyntax()), RecursiveProjection(SyntaxToText()), TextToGraphics(...))`: 50 times in 36 example files, although `make_natural_projection` builds it from the registration;
- the root module of each of the three packages of a domain: the same alias loop, in 87 package roots, and the same layering test in 39 suites. This belongs to the package area.

### How the rules of each printer are written

| Domain | Document types | Template rules | Hand-written `print_document` | Hand-written forward maps | `read_intent` methods | Uses of `ChildrenIoMap` |
| --- | --- | --- | --- | --- | --- | --- |
| JSON | 8 | 7 | 0 | 0 | 0 | 0 |
| XML | 4 | 3 | 0 | 0 | 0 | 0 |
| YAML | 8 | 6 | 1 | 1 | 3 | 6 |
| SQL | 40 | 10 | 20 | 20 | 39 | 101 |
| Julia | 61 | 58 | 2 | 2 | 2 | 0 |
| Markdown | 18 | 17 | 5 | 5 | 11 | 10 |
| RST | 44 | 15, and 32 through two macros of its own | 2 | 6 | 10 | 13 |
| Math | 22 | 16 | 28 (most in the graphics view) | 5 | 5 | 12 |
| Formula | 3 | 0 | 7 | 2 | 2 | 7 |
| Book | 6 | 3 | 3 | 3 | 7 | 15 |

`ChildrenIoMap` is the IO map of a hand-written rule that delegates to its children.

### Domain by edit capability

"Cut" is the general cut of the clipboard slice: it removes an element of a list, and it replaces a document in a field by the empty document of its domain ([Clipboard.jl:318](../../../source/platform/clipboard/Clipboard.jl#L318), [Clipboard.jl:357](../../../source/platform/clipboard/Clipboard.jl#L357)). It is the same for every domain, so the matrix has no column for it.

| Domain | A character in a leaf | Insert an element | Replace by typing | Wrap, unwrap | Reorder | Fold | Comments of the file | Layout on save | Parser on an error |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| JSON | yes, 4 `bound` fields, a number retypes ([JsonToSyntax.jl:76](../../../source/domain/json/JsonToSyntax.jl#L76)) | yes, `,` appends ([JsonDocument.jl:131](../../../source/domain/json/JsonDocument.jl#L131)) | yes, 8 keys ([JsonDocument.jl:113](../../../source/domain/json/JsonDocument.jl#L113)) | no | sort by key, by name only | field declared, not read | none in the format | one fixed layout | raises |
| YAML | yes, 4 | yes ([YamlDocument.jl:101](../../../source/domain/yaml/YamlDocument.jl#L101)) | yes ([YamlDocument.jl:88](../../../source/domain/yaml/YamlDocument.jl#L88)) | no | no | declared, not read | dropped ([YamlParser.jl:28](../../../source/domain/yaml/YamlParser.jl#L28)) | one fixed layout, block or flow | raises |
| XML | yes, 8 | yes, `<`, `"`, space ([XmlDocument.jl:114](../../../source/domain/xml/XmlDocument.jl#L114)) | on a placeholder ([XmlDocument.jl:89](../../../source/domain/xml/XmlDocument.jl#L89)) | no | no | declared, not read | skipped ([XmlParser.jl:75](../../../source/domain/xml/XmlParser.jl#L75)) | one fixed layout | raises |
| SQL | no, 0 `bound` | no | no; a whole statement is typed into the insertion | no | no | no | dropped ([SqlParser.jl:129](../../../source/domain/sql/SqlParser.jl#L129)) | one fixed layout | raises for the whole text; a part it does not model becomes a raw text node or is skipped |
| Julia | only a comment, a docstring, a module name (5 `bound`) | no key; a hole takes typed code | no | keyword scaffolds make holes | no | text folds in the file view only | kept as documents | no blank line, no alignment | Julia's own parser; raises on a construct with no document |
| Markdown | yes, 7, and the rendered text | no | no | no | no | 5 fields declared, not read by the syntax; a card folds on the page | not checked | plan pending | not checked |
| RST | yes, 37; 7 bodies of many lines are not editable | no | no | no | no | 16 fields declared, not read | kept as `RstComment` | written by hand, 3 spaces | not checked |
| Math | linear view: 2 `bound`; box view: none, a selection is a whole node | box view only: a letter or a digit fills an empty slot | no | box view only: `/`, `^`, `_`, `(` wrap; no unwrap | no | no | none | one line | raises with a position |
| Formula | through the code, into a draft copy | no | no | through math | no | no | none | none | no parser |
| Book | yes, 10 (a paragraph is a `TextBlock`) | no | no | no | no | yes, 3 rules pass `collapsed` | no text form | no text form | no parser |

### The placeholder kit and the insertion buffer

`@domain X` is the macro that makes the root type, the empty placeholder `XNothing`, the typed buffer `XInsertion`, the Insert key and the traits that the general code reads.

| Domain | Kit | The buffer prints through | The buffer commits |
| --- | --- | --- | --- |
| JSON | `@domain Json` ([JsonDocument.jl:7](../../../source/domain/json/JsonDocument.jl#L7)) | the shared leaf `InsertionToSyntaxLeaf` | a type name, or a number ([JsonToSyntax.jl:32](../../../source/domain/json/JsonToSyntax.jl#L32)) |
| XML, YAML | `@domain` | the shared leaf | a type name |
| SQL | `@domain Sql root = … insertion = …` ([SqlDocument.jl:38](../../../source/domain/sql/SqlDocument.jl#L38)) | the shared leaf with `parse_completion` ([SqlToSyntax.jl:1989](../../../source/domain/sql/SqlToSyntax.jl#L1989)) | a text that `parse_sql_text` reads |
| Julia | `@domain Julia` adopts three types ([JuliaDocument.jl:114](../../../source/domain/julia/JuliaDocument.jl#L114)) | a projection of its own ([JuliaInsertionToSyntax.jl:107](../../../source/domain/julia/JuliaInsertionToSyntax.jl#L107)) | a keyword scaffold, or a text that `parse_julia` reads, through `@gestures JuliaInsertion` ([JuliaInsertionToSyntax.jl:222](../../../source/domain/julia/JuliaInsertionToSyntax.jl#L222)) |
| Markdown | none; `MarkdownInsertion` by hand, `value::Any` ([MarkdownDocument.jl:29](../../../source/domain/markdown/MarkdownDocument.jl#L29)) | the fixed label "insert markdown here" ([MarkdownToSyntax.jl:36](../../../source/domain/markdown/MarkdownToSyntax.jl#L36)) | never |
| RST | none ([RstDocument.jl:35](../../../source/domain/rst/RstDocument.jl#L35)) | the fixed label "insert rst here" ([RstToSyntax.jl:150](../../../source/domain/rst/RstToSyntax.jl#L150)) | never |
| Book | none ([BookDocument.jl:28](../../../source/domain/book/BookDocument.jl#L28)) | "insert here" ([BookToSyntax.jl:33](../../../source/domain/book/BookToSyntax.jl#L33)) | never |
| Math | none ([MathDocument.jl:33](../../../source/domain/math/MathDocument.jl#L33)) | the glyph "⌷" ([MathToSyntax.jl:29](../../../source/domain/math/MathToSyntax.jl#L29)) | never in the linear view; one character in the box view |
| Formula | none ([FormulaDocument.jl:29](../../../source/domain/formula/FormulaDocument.jl#L29)) | "insert formula" ([FormulaToSyntax.jl:43](../../../source/domain/formula/FormulaToSyntax.jl#L43)) | never |

### The file types

All eight are `@document struct XFile <: FileDocument` with `filename`, `content::Document` and `disk`.

| File | `get_file_domain` | `parse_file_content` | `emit_text` | Reference to another file | Seed of an empty file | Default `content` |
| --- | --- | --- | --- | --- | --- | --- |
| `JsonFile` | `JsonDocument` | `parse_json` | natural text | a string | `JsonInsertion()` | `JsonNothing()` |
| `YamlFile` | `YamlDocument` | `parse_yaml` | natural text | a string | none, so `DocumentNothing()` | `YamlNothing()` |
| `XmlFile` | `XmlDocument` | `parse_xml` | natural text | a `pred:ref` element | `XmlInsertion()` | `XmlNothing()` |
| `SqlFile` | `SqlDocument` | `parse_sql_text` | natural text | a string literal | `SqlInsertion()` | `SqlNothing()` |
| `JuliaFile` | `JuliaDocument` | `parse_julia` | natural text and `"\n"` | a `pred_ref("…")` call | `JuliaInsertion()` | `JuliaNothing()` |
| `MarkdownFile` | `MarkdownDocument` | `parse_markdown` | natural text | a `pred-ref` fence | none | `MarkdownRoot()` |
| `RstFile` | `RstDocument` | `parse_rst` | natural text | a `pred-ref` directive | none | `RstRoot()` |
| `MathFile` | `MathDocument` | `parse_math(strip(text))` | natural text and `"\n"` | none | none | `MathInsertion()` |

In every row the parser and the printer are the ones that the natural registration of the domain already names.

### What each domain registers

| Domain | Typed notation (`register_natural_domain!`) | Keyed syntax rows (`register_natural_syntax!`) | Keyed graphics rows | File type | Seed method |
| --- | --- | --- | --- | --- | --- |
| JSON, XML, SQL | yes | no | no | yes | yes |
| YAML | yes, and `:yml` | no | no | yes, two extensions | no |
| Julia | yes, with `expression` | no | `:julia_code` | yes, and a marker function | yes |
| Markdown | yes, the source style | yes, the rendered style | `:markdown_page` | yes, two extensions | no |
| RST | yes, the source style | yes, the rendered style | `:rst_page` | yes | no |
| Math | yes | yes, the same projection again ([MathToSyntax.jl:687](../../../source/domain/math/MathToSyntax.jl#L687), [MathToSyntax.jl:693](../../../source/domain/math/MathToSyntax.jl#L693)) | `:math` | yes | no |
| Formula | no | no | `:formula` | no | no |
| Book | no | yes | no | no | no |

### How one domain holds another

| Way | Where | What it gives |
| --- | --- | --- |
| A field declared `Document`, drawn by the natural projection | `JsonArray.elements`, `XmlElement.children`, `MarkdownRoot.elements`, `RstRoot.elements` | any loaded domain, by its registered row |
| The rows of the outer domain passed into the builder of the inner one | `JuliaToSyntax(entries...)` from formula, state machine, process ([FormulaToSyntax.jl:464](../../../source/domain/formula/FormulaToSyntax.jl#L464)) | one table, with `Document => JuliaObjectToSyntaxLeaf` as the last row |
| The rows of the inner domain spliced into the table of the outer one | `math.dispatch...` ([FormulaToSyntax.jl:470](../../../source/domain/formula/FormulaToSyntax.jl#L470)) | one table |
| A page of blocks | `MarkdownRootToVerticalLayout`, `RstRootToVerticalLayout`, `RstSectionToVerticalLayout` | each block in its own chain, a file of another domain in a card |
| A wrapper node of the holder | `JuliaObject(value::Document)` ([JuliaDocument.jl:89](../../../source/domain/julia/JuliaDocument.jl#L89)) | a document of another domain as a literal in code |
| A string | `MarkdownCodeBlock.code`, the body of an RST code block | text with a language name; no document of that language |
| A marker to another file | `make_reference_leaf`, one spelling for each format | a node of any domain, cut into its own file |

The first row is the general way and it is sound. The page of blocks is TD-5.

### Parser and printer

| Domain | Printer | Parser | The two halves of an escape |
| --- | --- | --- | --- |
| JSON | 7 template rules | recursive descent over characters, 189 lines | `json_escape` in the printer file, `_string!` in the parser file |
| XML | 3 template rules | recursive descent, 184 lines | `_xml_text_escape`, `xml_escape_attr` and `_unescape` |
| YAML | 6 template rules, 1 by hand | lines by indent, and a flow reader, 338 lines | none on print: a string prints with no quotes; `_unescape_double` on read |
| SQL | 10 template rules, 20 by hand | a tokenizer and a recursive descent, 1211 lines | the quote `''`, in both files |
| Julia | 58 template rules | `Meta.parseall`, then one `_convert_head` method for each `Expr` head, 870 lines | `_julia_string_escape`; the read is Julia's |
| Markdown | 17 rules | by hand, 343 lines | not checked |
| RST | 47 rules | by hand, 762 lines | not checked |
| Math | 16 rules | a tokenizer and a recursive descent, 564 lines; "the printer is the grammar" | backslash names, a table in the documents |

Could one description give both? A template rule already holds the concrete syntax of a node: its opening text, its separator, its closing text, and which field each slot shows. For JSON, the XML subset and the linear form of math, the parser restates exactly that. A reader derived from the rules is thinkable for these three. It is not for YAML, Markdown and RST, where the indent carries the structure, nor for Julia, which uses the parser of Julia. Such an engine is a new mechanism and its size is unknown, so I do not propose it. TD-8 proposes the smallest true part of it: the escape of a value, which is the one place where the printer and the parser must be exact inverses.

## Findings

### TD-1 The insertion buffer is built three ways, and half of the domains have only a label

- **Kind:** several-ways · **Value:** high · **Effort:** medium · **Confidence:** high
- **Principle:** 7 (one mechanism, a missing case gets its row) and PAR-DOMAIN-OWNS-EDITS ("Generate the whole insertion kit with one `@domain X` line rather than re-implementing").
- **Today:**
  - Five domains have a working buffer, in two models. In JSON, XML, YAML and SQL the shared projection `InsertionToSyntaxLeaf` prints the buffer and also reads its keys: Enter, Tab and Escape are gesture bindings of the projection ([InsertionToSyntax.jl:302](../../../source/platform/syntax/InsertionToSyntax.jl#L302)). In Julia the projection only prints, and the keys are a `@gestures` table on the document `JuliaInsertion` ([JuliaInsertionToSyntax.jl:222](../../../source/domain/julia/JuliaInsertionToSyntax.jl#L222)), with its own printer and its own two reference maps ([JuliaInsertionToSyntax.jl:122](../../../source/domain/julia/JuliaInsertionToSyntax.jl#L122)).
  - "Commit the text when the parser of the domain reads it" exists three times: `parse_completion(parse_sql_text)` for SQL ([SqlToSyntax.jl:1989](../../../source/domain/sql/SqlToSyntax.jl#L1989)), `_julia_commit` for Julia ([JuliaInsertionToSyntax.jl:86](../../../source/domain/julia/JuliaInsertionToSyntax.jl#L86)), and `_parse_source` of the conversation composer, which is already general: it asks the natural registry for the parser of the domain of the buffer ([ConversationEditor.jl:362](../../../source/platform/conversation/ConversationEditor.jl#L362)).
  - JSON, XML and YAML commit a type name only. A JSON buffer that holds `{"a": 1}` does not commit, though `parse_json` is registered.
  - Markdown, RST, book, math and formula do not call `@domain`. Each declares an insertion type by hand and prints it as a fixed label with no reader (the five places are in the inventory). So these domains have no empty placeholder, no Insert key, no completion, and the traits answer the defaults: `get_domain_insertion` gives `nothing` ([Domain.jl:164](../../../source/platform/domain/Domain.jl#L164)).
  - General code reads those traits. The cut of the clipboard asks for the empty document of the domain and falls back to `DocumentNothing`, the placeholder of no domain ([Clipboard.jl:357](../../../source/platform/clipboard/Clipboard.jl#L357)). The tables of the five domains have no row for it; only the natural projection of a tab has one ([SyntaxNatural.jl:50](../../../source/platform/syntax/SyntaxNatural.jl#L50)). The rule that a pasted text becomes the insertion of the domain needs the same trait, and does nothing where the trait gives `nothing` ([ClipboardSliceToAny.jl:427](../../../source/platform/clipboard/ClipboardSliceToAny.jl#L427)).
- **Example:**

  ```julia
  # Today: each domain builds its own leaf, or a label.
  SqlInsertionToSyntaxLeaf(; theme = nothing) =
      InsertionToSyntaxLeaf((ins, text, place = Any) -> _sql_commit(text);
                            completion = parse_completion(parse_sql_text), theme)
  @projection_template MarkdownInsertionToSyntaxLeaf MarkdownInsertion (prj, doc) ->
      SyntaxLeaf(TextString("insert markdown here", prj.style))

  # Proposed: the kit and one row, the same in every domain.
  @domain Markdown
  MarkdownInsertion => DomainInsertionToSyntaxLeaf(MarkdownDocument; theme = syntax_theme),
  MarkdownNothing   => InsertionNothingToSyntaxLeaf(; theme = syntax_theme),
  # The commit is general: a type name of the domain, or a text that the
  # registered parser of the domain reads (find_natural_parser).
  ```
- **Problem:** A new domain must choose among three patterns, and the easiest one, the label, gives a place where a person can not type. The narrow fields of Markdown and RST admit their insertion by the plan `strict-document-types`, but that insertion takes no key. Math needs a buffer in its box view too (step 5 of its plan is open), and the shared leaf can not serve it, because its keys live in a projection to syntax.
- **Proposal:** One buffer for every domain.
  1. Every text domain calls `@domain`; a domain that has its type adopts it with `insertion = …`, as Julia and SQL do.
  2. The keys of the buffer are a `@gestures` table on the insertion document, which `@domain` makes: the Julia model, for all. A projection then only prints the buffer, so a box view or a widget view can show the same buffer.
  3. The commit is one function: a type name by reflection, as today, or a text that the registered parser of the domain reads, when the result fits the declared type of the place. The extras of a domain stay rows: the keyword scaffolds of Julia are `@insertion` rows already ([JuliaInsertionToSyntax.jl:77](../../../source/domain/julia/JuliaInsertionToSyntax.jl#L77)), and the number of JSON stays three options of the leaf: `commit`, `completion` and `commit_at_key` ([JsonToSyntax.jl:52](../../../source/domain/json/JsonToSyntax.jl#L52)).
- **What goes away:** the five hand-declared insertion types and their five label rules; `JuliaInsertionToSyntaxLeaf` with its maps and `_julia_state` (about 100 lines); `_sql_commit` and the SQL leaf constructor; `_composer_kind` and `_parse_source` of the composer; the key bindings inside `InsertionToSyntaxLeaf` (lines 302 to 420 move to the document table).
- **What stays:** the completion colours and the pale hint, Tab, Enter, Escape, the popup list of `DocumentInsertion`, the keyword scaffolds and the jump to the next hole of Julia, the number rule of JSON, the composer of the conversation. Book has no parser, so its buffer commits by name only.
- **Risk and open questions:** A parser that accepts almost any text, such as Markdown, makes every buffer commit; the rule "a type name wins" must come first, as it does in `_julia_commit` for a keyword. Whether a file that does not parse should open as the insertion of its domain with the text in it is a separate question; the kit makes it possible but this finding does not ask for it.
- **Related plans:** `strict-document-types.md` (in progress; it types the fields and does not touch the kit), `math-linear-form-reader.md` (step 5, type-in, open), `excel-julia-formulas.md` (phase 5, the formula insertion, open), `xml-to-syntax-reference-parity.md` (phase 5, placeholders, open). `plan/done/julia-typein-operations.md` chose the gesture table for Julia.
- **Check:** confirmed-with-corrections. I opened every cited place. The five insertion types that are declared by hand and their five label rules, the shared leaf, the Julia leaf with its `@gestures` table, the three "commit by parse" functions and the trait defaults stand as written. PAR-DOMAIN-OWNS-EDITS asks for the kit in every domain, and no plan gives it to the five. **Correction to step 2:** the keys of the shared leaf are in the projection for a stated reason. The commit, the completion, Tab and the Insert key read the declared type of the place of the insertion, and the print finds that type in `PrinterContext.reference` (`strict-document-types.md`, §3.5 and step 5.2, done; [InsertionToSyntax.jl:196](../../../source/platform/syntax/InsertionToSyntax.jl#L196); the comment at [InsertionToSyntax.jl:293](../../../source/platform/syntax/InsertionToSyntax.jl#L293) says why the table stays in the projection). A `@gestures` row gets the document and the event, and no place. So "the Julia model, for all" would lose the rule "an insertion offers only what its place admits" (PAR-WIDE-FIELD-TYPES) and the key that widens an insertion, which the Julia hole does not have today (step 5.3: "A Julia hole has its own leaf and no Insert binding"). The one buffer must keep the place. Either the Julia hole becomes a row of the shared leaf (a commit that makes a scaffold or parses, a completion over the keywords, and Tab with the jump to the next hole as an option), or the gesture gets the place by a way that exists. The key bindings of `InsertionToSyntaxLeaf` therefore do not go away, and a box view needs a printer for the same options, not a move of the keys. Two small facts: the number of JSON is three options of the leaf (`commit`, `completion`, `commit_at_key`), and `⌷` of math is a token that `parse_math` reads back as the empty slot, so `@domain Math` must adopt `MathInsertion` and say what `MathNothing` is beside it. The value stays high for steps 1 and 3.

### TD-2 The template can not wrap each element of a list, so four list rules are written by hand

- **Kind:** special-case · **Value:** high · **Effort:** small · **Confidence:** high
- **Principle:** 7 (a missing case gets its row in the generic mechanism, never a special path); PAR-DELEGATE-ONE-LEVEL.
- **Today:** The marker `collection(:field)` of a template projects each element bare. Its second form, `collection(:field) do x … end`, builds a node from the fields of `x`; it can not hold the projected element as a whole. Four rules need a marker in front of each projected element, and each says so in a comment and is written by hand with a printer, two maps and two or three readers:
  - `YamlSequenceToBlockSyntaxNode`, `- ` ([YamlToSyntax.jl:134](../../../source/domain/yaml/YamlToSyntax.jl#L134), 115 lines);
  - `BookListToSyntaxNode`, `• ` ([BookToSyntax.jl:430](../../../source/domain/book/BookToSyntax.jl#L430), 116 lines);
  - `MarkdownListToStyledNode`, `1. ` or `• ` ([MarkdownToSyntax.jl:548](../../../source/domain/markdown/MarkdownToSyntax.jl#L548), 76 lines);
  - `RstEnumeratedListToStyledNode` ([RstToSyntax.jl:1153](../../../source/domain/rst/RstToSyntax.jl#L1153), 84 lines).

  All four build the same thing, `SyntaxDelimitation(child_output; opening_delimiter = marker)`, and state the same map: `.field[i].rest ↔ .children[i].content.rest`.
- **Example:**

  ```julia
  # Today (YAML, shortened): 115 lines.
  function print_document(p::YamlSequenceToBlockSyntaxNode, recursion, seq::YamlSequence, ctx)
      child_iomaps = Cell(@computation([print_child(recursion, elem, make_child_context(ctx, …))
                                        for (i, elem) in enumerate(seq.elements)]))
      items = CellVector(@computation(SyntaxDocument[
          SyntaxDelimitation(im.output; opening_delimiter = TextString("- ", p.marker_style))
          for im in child_iomaps[]]))
      …
  end
  function map_reference_forward(p::YamlSequenceToBlockSyntaxNode, iomap::ChildrenIoMap, reference) … end
  function map_reference_backward(…) … end
  function read_intent(…) … end   # three methods

  # Proposed: a third form of the marker.
  @projection_template YamlSequenceToBlockSyntaxNode YamlSequence (prj, doc) ->
      SyntaxNode(collection(:elements; each = (index, element) ->
                     SyntaxDelimitation(element; opening_delimiter = TextString("- ", prj.marker_style)));
                 open = "\n", sep = "\n", indentation = 1)
  ```
- **Problem:** The next domain with a bulleted or numbered list writes the fifth copy. The copies already differ: the YAML reader gives a key to the selected child and then to the gestures of the sequence, the Markdown and RST readers map two operation types only.
- **Proposal:** `collection(:field; each = (index, element) -> wrapper)`, where `element` stands for the projected element. The engine walks the wrapper as it walks a fixed node today, finds the place of `element`, and records the one extra step. The index serves the number of an ordered list.
- **What goes away:** the four hand-written rules, about 390 lines. `FileSystemDirectoryToSyntaxNode` of the platform, which the YAML comment names as its model, does not follow: it puts no wrapper around an element, it prints a name leaf and a body node of the bare elements ([FileSystemToSyntax.jl:94](../../../source/platform/filesystem/FileSystemToSyntax.jl#L94)), which is another shape.
- **What stays:** every printed marker, the selection through the marker, the gestures of `YamlSequence`.
- **Risk and open questions:** The wrapper may hold more than one level (a delimitation inside an indentation); the walk must accept any path to the element. This is a change of `ProjectionTemplate.jl` in the kernel.
- **Related plans:** `projection-template-engine.md` (in progress). Its open stages name SQL, math, formula and the collection rules; none names this form. `a-markdown-page-prints-back-its-text.md` (not built) adds the wrapper `SyntaxLinePrefix`, which a list item would use together with this form. Step 4 of that plan writes the source list of Markdown by hand, "as `MarkdownListToStyledNode` is": that is the fifth copy, already planned.
- **Check:** confirmed-with-corrections. I opened the four rules and the engine. `grep "SyntaxDelimitation(.*\.output"` finds exactly these four places in `source/`, and the line counts hold (115, 116, 76 and 84). `_node_print` has only the two forms of `collection` that the finding names ([ProjectionTemplate.jl:540](../../../source/kernel/projection/ProjectionTemplate.jl#L540)), and the done criteria of `projection-template-engine.md` ask for every structural rule as a builder, but no stage names this form. Two facts make the finding stronger. First, the pending Markdown plan adds a fifth copy (step 4). Second, the four rules build their child IO maps as a plain computed list with a fixed index ([YamlToSyntax.jl:154](../../../source/domain/yaml/YamlToSyntax.jl#L154)), and not through the shared reconciler that PAR-STABLE-IOMAP-IDENTITY asks for and that the engine uses ([ProjectionTemplate.jl:529](../../../source/kernel/projection/ProjectionTemplate.jl#L529)); the new form gives them the reconciler. Corrections: the RST rule also puts the ambient indent in its marker (`"\n" * indent`), so it needs the context of TD-3 or `SyntaxLinePrefix` beside the new form; and the directory rule of the file system is no case of it (corrected above). The index that `each` gets is a cell in the engine, so the number of an ordered list is a computation over it. I found no feature that the form would lose: the reader of a `TemplateIoMap` already gives a key to the selected child first and then to the gestures of the document (PAR-DELEGATE-AND-LIFT), which is what the YAML reader does by hand. The value stays high.

### TD-3 A value that a subtree inherits is carried in three ways, one for each domain that needed it

- **Kind:** several-ways · **Value:** high · **Effort:** medium · **Confidence:** medium
- **Principle:** 7; the settled rule that a per-print value goes in the printer context; decision D7 of `a-markdown-page-prints-back-its-text.md`.
- **Today:** The builder of a template gets `(projection, document)` and not the printer context. Three domains need a value that comes from the nodes above. All three carry it in the properties of the printer context (`with_property`, `get_property`), which is the settled way; each found its own way around the template to reach the context:
  1. **Markdown writes the rules by hand.** The rendered bold, italic, heading and link set `:md_style` and `:md_pointer_shape` for their children, and the rendered text leaf reads them. That is one abstract type, four structs, a printer, a forward map, four backward maps made by `@eval`, and two readers ([MarkdownToSyntax.jl:313](../../../source/domain/markdown/MarkdownToSyntax.jl#L313) to 475), and a text leaf with its own maps ([MarkdownToSyntax.jl:265](../../../source/domain/markdown/MarkdownToSyntax.jl#L265)).
  2. **RST copies that for the style** ([RstToSyntax.jl:861](../../../source/domain/rst/RstToSyntax.jl#L861) to 992, the text leaf is the same code with `Rst` for `Markdown`), **and adds two macros of its own for the indent.** `@rst_flat` and `@rst_indented` wrap `print_template_document` and pass the ambient `:rst_indent` to the builder ([RstToSyntax.jl:103](../../../source/domain/rst/RstToSyntax.jl#L103), [RstToSyntax.jl:124](../../../source/domain/rst/RstToSyntax.jl#L124)); 32 rules use them. Seven bodies of many lines are indented by a closure, `_indent_body`, and are therefore not editable in the source view ([RstToSyntax.jl:25](../../../source/domain/rst/RstToSyntax.jl#L25)).
  3. **Formula calls the engine directly** with a closure that captured the context, for the set of reference identifiers ([FormulaToSyntax.jl:62](../../../source/domain/formula/FormulaToSyntax.jl#L62)).

  The RST file gives its reason: the `indentation` of a node counts in units of `indent_size`, which is one number of the whole `SyntaxToText` stage, 2 by default ([SyntaxToText.jl:396](../../../source/platform/syntax/SyntaxToText.jl#L396)), and RST needs 3 columns ([RstToSyntax.jl:17](../../../source/domain/rst/RstToSyntax.jl#L17)).
- **Example:**

  ```julia
  # Today, RST: a macro of the domain around the template, and the indent as text.
  @rst_indented RstBlockQuoteToSyntaxNode RstBlockQuote (prj, doc, outer, inner) ->
      SyntaxNode(collection(:elements); open = TextString(_IND, prj.marker_style),
                 sep = TextString("\n\n" * inner, prj.marker_style), …, indentation = 0)
  # Today, Markdown: 160 lines by hand for "the children are bold".

  # Proposed, the style: one rule form that sees the context and gives one to its children.
  @projection_template MarkdownStrongToStyledNode MarkdownStrong (prj, doc, ctx) ->
      SyntaxNode(collection(:content; context = (:text_style => bold(ctx, prj.bold_font)));
                 indentation = 0)
  # Proposed, the indent: the wrapper that D7 decided for Markdown.
  @projection_template RstBlockQuoteToSyntaxNode RstBlockQuote (prj, doc) ->
      SyntaxLinePrefix(SyntaxNode(collection(:elements); sep = "\n\n"); prefix = "   ")
  ```
- **Problem:** The owner rejected, for Markdown, the way that RST uses today: "each Markdown printer of a line writes the prefix from a context value, so every printer of a line … must know it" (D7). The style cascade has the same fault: `:md_style` is read in two places only, the styled text leaf and the styled containers ([MarkdownToSyntax.jl:296](../../../source/domain/markdown/MarkdownToSyntax.jl#L296), [MarkdownToSyntax.jl:406](../../../source/domain/markdown/MarkdownToSyntax.jl#L406)), so any other leaf below a bold node keeps its own font. A third prose domain copies 130 lines again.
- **Proposal:**
  1. The indent and the prefix of a line: RST uses `SyntaxLinePrefix` when the Markdown plan builds it. The 32 macro rules become plain template rules, and the seven bodies become `bound` values of many lines, which follow the indentation of the code around them ([syntax.md](../../../documentation/package/platform/syntax/syntax.md), "Each line of a leaf after its first is a line of the chrome").
  2. The inherited style and the reference set: the template accepts a builder with a third argument, the context, and `collection` and `project` take the properties that the children get. Markdown and RST then share one key and one styled text leaf, in the syntax or the text slice.
- **What goes away:** `@rst_flat`, `@rst_indented`, `_ambient`, `_indent_body` and the hand-written indent text in 32 rules; `MarkdownStyledInline` and `RstStyledInline` with their maps and readers; one of the two styled text leaves; the direct call in the formula rule. About 400 lines.
- **What stays:** both views of Markdown and RST, the 3-column body of RST, the hand over a link, the reference colour of a formula.
- **Risk and open questions:** For the style, a wrapper node of the syntax slice (one concern in one wrapper, as D7 chose for the prefix) is the other possible shape; it would need `SyntaxToText` to restyle the runs of a child, which I did not check. The context form is the smaller change. A builder that reads the context must stay a pure function of it.
- **Related plans:** `a-markdown-page-prints-back-its-text.md` (not built; D7 gives the wrapper and names "another domain can use it", with no step for RST), `projection-template-engine.md` (in progress, no step for the context), `text-domain-kit.md` (phase 3, lines with an indentation, in progress).
- **Check:** confirmed-with-corrections, and the value is lower. I opened the cited ranges of Markdown, RST and formula, the two macros, D7 of the Markdown plan and the sentence of `syntax.md`; the counts hold (32 macro rules: 12 flat and 20 indented; 6 calls of `_indent_body` for the seven bodies that the file header names). **Correction of the frame:** the value is not carried in three ways. Markdown, RST, formula and also the box view of math (`:math_style`, [MathToGraphics.jl:405](../../../source/domain/math/MathToGraphics.jl#L405)) all carry it in the properties of the printer context, as the settled decision says. The one gap is that the builder of `@projection_template` does not see the context and can not set the context of its children; the three "ways" are three ways around that gap, and the entry `print_template_document(p, recursion, doc, ctx, builder)` that RST and formula call is already public. So part 2 is a small addition to the macro (a builder with the context, and the properties for the children), and with it the styled containers of Markdown and RST are `SyntaxNode(collection(:content); indentation = 0)`. Part 1 is right against D7 (the owner rejected "each printer of a line writes the prefix from a context value", which is what `:rst_indent` does), but it is a follow-up of a plan that is not built: `SyntaxLinePrefix` is step 3 of `a-markdown-page-prints-back-its-text.md`, which says "another domain can use it" and has no step for RST. What part 1 would give beyond less code: the seven verbatim bodies of RST become editable in the source view. The sentence that the style cascade "has the same fault" as the prefix is a judgment and not a fact: a code span below a bold node keeps its own font on purpose, so a leaf that reads the ambient style by choice is a fair model. I found no feature that the proposal would lose. Value: medium, because the carrier is one already and half of the change waits for another plan.

### TD-4 A format is declared in two registries and four methods, and a tab reads through one and writes through the other

- **Kind:** several-ways · **Value:** medium · **Effort:** medium · **Confidence:** high
- **Principle:** 7 (one mechanism); 11 (design as from scratch).
- **Today:** "JSON is written as `.json`, read by `parse_json`, printed by `JsonToSyntax`, and an empty file starts as an insertion" is said in four places:
  1. `register_natural_domain!(JsonDocument; rung, make, format, extension, parse)` fills the tables `_NOTATIONS`, `_FORMATS` and `_PARSERS` ([NaturalNotation.jl:117](../../../source/platform/natural/NaturalNotation.jl#L117));
  2. `register_file_document_type!(".json", JsonFile)` fills `_FILE_DOCUMENT_TYPES` ([FileProject.jl:268](../../../source/platform/serialization/FileProject.jl#L268));
  3. three contract methods on the file type repeat the first call: `get_file_domain`, `parse_file_content`, `emit_text` ([JsonFile.jl:21](../../../source/domain/json/JsonFile.jl#L21) to 27; the same three lines in all eight file types);
  4. `make_document_seed(::Val{:json})` ([JsonToSyntax.jl:193](../../../source/domain/json/JsonToSyntax.jl#L193)), and a second default in the struct, `content::Document = JsonNothing()`.

  The platform has two input and output paths to match. A tab reads a natural format with `read_document_file`, which calls `import_document` and the natural parser ([DocumentFile.jl:99](../../../source/platform/fileformat/DocumentFile.jl#L99)), and saves with `save_file_text!`, which calls `emit_text` of the file type ([DocumentFile.jl:320](../../../source/platform/fileformat/DocumentFile.jl#L320)). `parse_file_content` serves the load of a project of several files, and the read of a file whose type is not the one of its extension ([FileSplice.jl:33](../../../source/platform/serialization/FileSplice.jl#L33), [FileSplice.jl:68](../../../source/platform/serialization/FileSplice.jl#L68)).

  The copies have drifted. `emit_text` of a Julia file adds a line break ([JuliaFile.jl:28](../../../source/domain/julia/JuliaFile.jl#L28)) and `export_document` of the same tree does not ([NaturalFormat.jl:64](../../../source/platform/fileformat/NaturalFormat.jl#L64)). Four of eight formats have a seed method; an empty `.yaml` opens as `DocumentNothing`, an empty `.json` as `JsonInsertion`. `find_file_extension` and `get_natural_extension` answer the same question from the two tables.
- **Example:**

  ```julia
  # Today: JsonModule.__init__ and JsonFile.jl and JsonToSyntax.jl.
  register_natural_domain!(JsonDocument; rung = :syntax, make = …, format = :json,
                           extension = ".json", parse = parse_json)
  register_file_document_type!(".json", JsonFile)
  get_file_domain(::Type{<:JsonFile}) = JsonDocument
  parse_file_content(::Type{<:JsonFile}, text::AbstractString) = parse_json(text)
  emit_text(f::JsonFile) = print_natural_text(get_file_content(f))
  make_document_seed(::Val{:json}) = JsonInsertion()

  # Proposed: one call; the file type owes only what is special to its format.
  register_natural_domain!(JsonDocument; rung = :syntax, make = …, format = :json,
                           extension = ".json", parse = parse_json, file = JsonFile)
  make_reference_leaf(::JsonFile, marker) = JsonString(make_marker_text(marker))
  find_reference_marker(leaf::JsonString) = parse_marker_text(leaf.value)
  ```
- **Problem:** A new format writes six statements for one fact and can get any of them wrong without an error. The rule of the last line break, the seed and the extension live in two places each.
- **Proposal:** The natural row of a format is the one source. The three contract functions get general methods for a file whose type a natural row names: the domain is the registered root, the parser is the registered parser, the text is the natural text with the line break rule of the format said once. The seed of a format is the insertion of its domain, from the kit (TD-1). A file type overrides a function only where it differs, as `MathFile` does for `is_file_domain_node`.
- **What goes away:** 24 contract lines and 4 seed methods in the domains, the second registration call in 8 modules; in the platform, the split between a "natural path" and a "registered file path" in `read_document_file` and `write_document_file`, and one of the two extension lookups.
- **What stays:** the file types themselves, because gestures, views and workloads dispatch on them; the spelling of a reference to another file, which is a true fact of each format; `.pred`, `.txt` and the picture types, which have no natural row.
- **Risk and open questions:** The tables are process-wide and filled in `__init__`. The settled decision says a registry belongs to the editor; these tables hold types and functions of the loaded packages and no state of a session, so I read them as outside that decision, but the owner may see it otherwise. The work is mostly in the platform.
- **Related plans:** `a-print-writes-and-a-make-answers.md` and `pending-edits-and-file-changes.md` mention the file contract; neither merges the registries.
- **Check:** confirmed. I opened the four places of the declaration, the read and the save of a tab, and counted with `grep`: 8 file types with the three contract lines each (24 lines), 4 seed methods (`:json`, `:xml`, `:sql`, `:jl`), 10 calls of `register_file_document_type!` in the 8 domains. `make_file_tab` reads through `read_document_file`, which takes the natural parser for an extension that has one ([DocumentFile.jl:171](../../../source/platform/fileformat/DocumentFile.jl#L171)), and Ctrl+S writes through `save_file_text!` and `emit_text` ([DocumentFile.jl:320](../../../source/platform/fileformat/DocumentFile.jl#L320)). More drift than the finding names: `emit_text` of `MathFile` adds a line break too, so `write_document_file(document, "a.jl")` and `write_document_file(document, "a.math")` write a file without the last line break that a save of the tab writes; and `.markdown` has a file type and no natural parser (only `:md` has one), so a `.markdown` file reads through `parse_file_content` and a `.md` file through the natural parser. The reason for the contract functions is the layering: the serialization slice does not depend on the natural slice, and `fileformat.md` and `serialization.md` describe the contract as it is, but no document gives a reason for saying the same fact twice. The general methods can stand in the file-format slice, which sees both slices, so the layering stays. The proposal loses no feature that I could name: `TextFile`, `PredFile`, `ImageFile` and `SourceFile` have no natural row and keep their own methods. It adds no registry: it joins two that exist, so the settled decision on registries is not touched in either direction. Value: medium.

### TD-5 The parts of a prose page are written once for each prose domain

- **Kind:** repeated-by-hand · **Value:** medium · **Effort:** medium · **Confidence:** high
- **Principle:** PAR-FRAMEWORKS-SINK ("Anything two slices both need is a framework and sinks to the platform slice that owns the concept"); 8 (reuse an existing view); 9 (a printer reads no disk).
- **Today:** Markdown, RST and book each show prose, and four parts exist in two or three copies.
  1. **The page of blocks.** `MarkdownRootToVerticalLayout` ([MarkdownToLayout.jl:21](../../../source/domain/markdown/MarkdownToLayout.jl#L21)), `RstRootToVerticalLayout` and `RstSectionToVerticalLayout` ([RstToLayout.jl:28](../../../source/domain/rst/RstToLayout.jl#L28), [RstToLayout.jl:61](../../../source/domain/rst/RstToLayout.jl#L61)) each stack the elements of a field as the children of a `VerticalLayout`, put a file of another domain in a card, and map `elements[i].rest ↔ children[i].rest`. The Markdown file says that it "mirrors `CellVectorToVerticalLayout`", the general projection of a bare list ([CollectionToLayout.jl:21](../../../source/platform/layout/CollectionToLayout.jl#L21)). The copies differ where nothing asks for it: the Markdown layout gives its blocks the width `Fill` and has a reader of its own for a `ReplacePathOperation` ([MarkdownToLayout.jl:224](../../../source/domain/markdown/MarkdownToLayout.jl#L224)); the RST layouts have neither.
  2. **The picture.** `_md_image_value` ([MarkdownToSyntax.jl:490](../../../source/domain/markdown/MarkdownToSyntax.jl#L490)), `_rst_picture` ([RstToSyntax.jl:1242](../../../source/domain/rst/RstToSyntax.jl#L1242)) and the picture leaf of book ([BookToSyntax.jl:578](../../../source/domain/book/BookToSyntax.jl#L578)) are the same function. Each calls `isfile` inside a printer to choose between the picture and its path as text.
  3. **The link.** Markdown and RST each build the same three bindings, follow, open in a new tab, show the target ([MarkdownLinkTarget.jl:23](../../../source/domain/markdown/MarkdownLinkTarget.jl#L23), [RstLinkTarget.jl:25](../../../source/domain/rst/RstLinkTarget.jl#L25)), although both documents already answer the general `is_link` and `get_link_target` of the link slice.
  4. **The ladder of six heading fonts.** Six theme fields and a lookup by level, in both themes and both rendered rules.
- **Example:**

  ```julia
  # Today: three printers, each with this line.
  if url isa AbstractString && !isempty(url) && isfile(String(url))
      img = Image(String(url)); …; return TextGraphics(Cell(img), dw, dh, …)
  end

  # Proposed: the domain names a field; the platform has the page and the picture.
  MarkdownRoot => BlocksToVerticalLayout(:elements; gap)
  RstSection   => BlocksToVerticalLayout(:elements; head = make_title_block, gap)
  ```
- **Problem:** The research domain and each new prose domain need the same page. A fix of the card, of the width or of the click through a card must be made three times.
- **Proposal:** A platform projection `BlocksToVerticalLayout(field; head)` that generalizes `CellVectorToVerticalLayout` to a named field of a document, with an optional first block and the card rule. One picture value in the platform, which takes a path and answers the picture or the text, with the check of the disk in the acquire of the image and not in a printer. One function of the link slice that makes the three bindings for a type that says `is_link`.
- **What goes away:** two of the three layout projections and `_relocate_head` (about 190 lines; the 95 lines of the Markdown table stay), two of the three picture functions, one of the two binding tables.
- **What stays:** the table of a Markdown page as a widget table, the title line of an RST section, the card of an embedded file and its fold, the click that follows a link in both views.
- **Risk and open questions:** I did not check how `Image` learns that its file is missing; if it can not, the picture value needs that state from an acquire. The widget table of Markdown is a rule for one element type and stays a rule of the domain.
- **Related plans:** `views-compose-as-content-composes.md` (later) names "json and xml in markdown" as a feature to keep; it does not cover the page. `a-tab-shows-the-file-that-a-program-rewrites.md` (pending) covers the disk read of the picture: step 5 for Markdown and step 5a for book and RST, both open, take the picture from `:shown_files` and call no `isfile`. That plan keeps one picture function in each domain.
- **Check:** confirmed-with-corrections. I opened the three layouts, `CellVectorToVerticalLayout`, the three picture functions and the two link files. The facts hold: three projections in two domains stack a field as a `VerticalLayout` with the same card rule; the Markdown page gives its blocks the width `Fill` and re-roots a `ReplacePathOperation`, and the RST pages do neither, so a paragraph of an RST page does not break at the edge of the page and a click in a card of an RST page does not put the caret there. Both are a feature that works in one prose domain only. The three `isfile` calls in a printer stand at the cited lines. **Corrections:** (1) the disk read of the picture is covered by a plan (added above), so only "one function in place of three" is left of part 2, and it must be built on the `:shown_files` of that plan, not on an acquire of its own; (2) the Markdown page builds its widget table inside the page rule and maps the table paths in the two maps of the page ([MarkdownToLayout.jl:76](../../../source/domain/markdown/MarkdownToLayout.jl#L76)), so before the general page can take Markdown, the table must become a row of its own with its own maps, which the proposal says in one clause only; (3) the line count was high (corrected above). Book has no page: its part in this finding is the picture alone. The heading ladder of part 4 has no proposal. I found no feature that the general page would lose when it keeps the card rule, the first block and the three readers of Markdown. Value: medium.

### TD-6 JSON and YAML are one data model kept as two domains

- **Kind:** redundant · **Value:** medium · **Effort:** medium · **Confidence:** medium
- **Principle:** 2 (a view is a projection; two notations of one data are two projections); 11.
- **Today:** The YAML document says "The documents mirror JSON one to one". `YamlDocument.jl` repeats the eight types, the six insertion rows and the three gesture tables of `JsonDocument.jl` with other names ([YamlDocument.jl:7](../../../source/domain/yaml/YamlDocument.jl#L7) to 108, [JsonDocument.jl:7](../../../source/domain/json/JsonDocument.jl#L7) to 152). The four leaf rules of the printer are the same but for the quotes. The note of the file under the pointer is the same 60 lines, `_format_json_path` and `_format_yaml_path` ([JsonFile.jl:45](../../../source/domain/json/JsonFile.jl#L45), [YamlFile.jl:46](../../../source/domain/yaml/YamlFile.jl#L46)).

  The copies have drifted since the commit that made YAML "mirroring JSON" (ed65fbf4d). JSON has typed lists `CellVector{Document}`, the rows for `DocumentInsertion`, the rule that `,` on a closing bracket belongs to the parent, the incomplete number, a rule for an entry on its own, the sort and the move back to the key. YAML has none of these ([YamlDocument.jl:101](../../../source/domain/yaml/YamlDocument.jl#L101), and the table at [YamlToSyntax.jl:273](../../../source/domain/yaml/YamlToSyntax.jl#L273), where an entry prints through `CopyingProjection`).
- **Example:**

  ```julia
  # Today: a YAML mapping in a JSON array is a node of another domain. The tab draws
  # it as YAML, by the natural row of its type (the first row of "How one domain holds
  # another"), and the save of the .json file cuts it into a file of its own, as the
  # file project does by design for a node of another type
  # (get_file_domain(JsonFile) = JsonDocument).
  push!(json_array.elements, parse_yaml("a: 1"))

  # Proposed: one tree of data, two notations.
  data = parse_yaml("a: 1")            # the same types as parse_json gives
  JsonFile("a.json", data)             # prints with JsonToSyntax
  YamlFile("a.yaml", data)             # prints with YamlToSyntax(; style = :block)
  ```
- **Problem:** The most natural act between the two formats, to save data of one as the other, has no path. Each edit feature of JSON must be made again for YAML, and was not. A third data notation would be a third copy.
- **Proposal:** One domain of tree data (object, array, string, number, boolean, null) with the notations as projections and parsers: `JsonToSyntax`, `YamlToSyntax` in its two styles, `parse_json`, `parse_yaml`. The file type chooses the notation.
- **What goes away:** `YamlDocument.jl` (108 lines), the four YAML leaf rules, the note of `YamlFile.jl` (60 lines), and the drift.
- **What stays:** `.yaml` and `.yml` files, the block and the flow style, the YAML parser, the gestures (YAML gets those of JSON), both themes.
- **Risk and open questions:** The natural registry maps a type to its one format (`get_natural_format(T)`), so `print_natural_text` of a bare node would not know which notation to write; the notation would have to come from the file or from the caller. YAML has parts that JSON has not (comments, anchors, tags, several documents); the parser reads none of them today, and a model for them would need YAML node types again. The retype keys differ in one place (`-` for a sequence, `[` for an array). If the owner wants YAML to grow apart, the smaller step is to move the shared parts (the path note, the leaf rules) to one place.
- **Related plans:** none found.
- **Check:** weakened. The facts hold: `yaml.md` says "the documents mirror JSON one to one", the types, the insertion rows and the gesture tables are copies, and the drift list is right (YAML has untyped lists, no rows for `DocumentInsertion`, no incomplete number, no entry rule, no sort). The example was wrong in one point and is corrected above. **The proposal loses a feature and is not future proof.** (1) The natural notation is chosen by the type of the document (`_NOTATIONS` and `_FORMATS` are keyed by type; first principle 2, dispatch on type). A YAML tree that stands in no `.yaml` file draws and prints as YAML only because of its type: a `yaml` fence of an answer of the assistant becomes a `ConversationPart` of the parsed document ([AssistantTurn.jl:1276](../../../source/platform/assistant/AssistantTurn.jl#L1276)), and a YAML value in a Markdown page, in a card or in a `JsonArray` is the same case. With one data type these all draw as JSON, or they need a node that holds the notation, which is the YAML types again or a fact of layout in the tree, against the settled decision that the tree holds no layout. The finding names this under risk and gives no answer. (2) The parser drops comments and does not read anchors, tags, block scalars and several documents. A save that is the print of the tree needs nodes for them, and JSON has none, so the correct model of YAML is wider than JSON; the report says so itself ("a model for them would need YAML node types again"). What is left is real and small: bring the YAML types to the state of JSON (typed lists, the rows for `DocumentInsertion`, the incomplete number), which the option (b) of `strict-document-types.md` reaches only where people type documents, and, if wanted, a function that converts a tree of one domain to the other for "save as". Shared code between two domains (the path note) must sink to a platform slice (PAR-DOMAINS-INDEPENDENT), not go from one domain to the other. Value: low.

### TD-7 The structural keys of math live in the reader of one view

- **Kind:** wrong-place · **Value:** medium · **Effort:** small · **Confidence:** high
- **Principle:** 3 (one way to edit; a person, the assistant and a test make the same operations); `domain-anatomy.md`, "The gestures: the structural edits, as `@gestures` tables on the document types".
- **Today:** In JSON, XML and YAML a structural key is a row of a `@gestures` table on the document type. Every view asks the document with `read_gesture`, and the command palette lists the rows by name. In math the same kind of edit is code in the reader of the projection to graphics: `_act_on_selection` and `_build_around` wrap the selected node in a fraction, a script or parentheses, fill an empty slot with a variable or a number, and clear a node with Backspace ([MathToGraphics.jl:1998](../../../source/domain/math/MathToGraphics.jl#L1998), [MathToGraphics.jl:2014](../../../source/domain/math/MathToGraphics.jl#L2014)). The only `@gestures` table of the math documents is the tooltip of a symbol ([MathDocument.jl:397](../../../source/domain/math/MathDocument.jl#L397)).
- **Example:**

  ```julia
  # Today: in MathToGraphics.jl, inside the reader.
  built = text == "/" ? _with_hole(MathFraction(doc, MathInsertion()), "denominator") : …
  make_replace_document_operation(EmptyReference(), built)

  # Proposed: in MathDocument.jl, on the document.
  @gestures MathDocument begin
      KeyPress('/') => "Wrap in a fraction" =>
          replace_selected_document(doc, @selected MathFraction(selected, MathInsertion()) denominator)
      KeyPress('^') => "Add a superscript" => …
      KeyDown(:backspace;) => "Clear to an empty slot" => replace_selected_document(doc, MathInsertion())
  end
  ```
- **Problem:** The linear view of the same formula, which a `.math` file and a formula sheet show, has no key that wraps. The palette and the gesture help do not list the math edits. These are the only wrap edits of the area, and no other domain can reuse their form.
- **Proposal:** Move the build keys to `@gestures` tables on the math documents, built with the shared verb `replace_selected_document`. The reader of the graphics view keeps what belongs to a view of boxes: the press that finds the smallest box, and the moves between boxes. It calls `read_gesture` for the rest, as a template reader does.
- **What goes away:** `_act_on_selection`, `_build_around` and `_with_hole` in the projection, about 45 lines; they come back as about 10 rows.
- **What stays:** every key of the box view, with the same result. The linear view gains them.
- **Risk and open questions:** In the linear view a `/` typed in a `bound` leaf is a character first; a rule needs `override`, as XML uses for `<`. The verb `replace_selected_document` must accept a replacement that holds the selected node.
- **Related plans:** `math-linear-form-reader.md` (step 5 open; it is about a typed line, not about these keys). `plan/done/math-formula-layout.md`, part F, built the reader and records no reason against a gesture table.
- **Check:** confirmed-with-corrections. I opened `_read_key`, `_act_on_selection`, `_build_around` and `_with_hole`, the one `@gestures` table of the math documents, `math.md` ("Selecting and editing") and part F of the done plan. The facts hold, and the rule is stronger than the finding says: PAR-GEOMETRY-FREE-IN-DOCUMENT says that a gesture that reads only the structure and the selection of the document lives behind `read_gesture`, and that a projection reader keeps only its geometry arms. The build keys and Backspace read only the selected document. No document gives a reason for the place in the reader. **Correction:** a number in a formula is a `PrimitiveNumber` of the platform, not a `MathDocument` (`MathOperand`, [MathDocument.jl:26](../../../source/domain/math/MathDocument.jl#L26)), and the box view gives it the same reader (`MathNumberToGraphics`, [MathToGraphics.jl:491](../../../source/domain/math/MathToGraphics.jl#L491)), so today `/`, `^`, `_` and `(` wrap a selected number. A table on `MathDocument` does not reach a number, and the math domain can not put a table on a type of the platform. So "every key of the box view, with the same result" holds only when the build is one function of the math domain that the rows of the table call and that the number rule of each view calls too. Also: in the linear view Backspace on a whole node meets the general delete of the clipboard slice, so the row for it needs an order between the two. The keys that the linear view gains are consistency of one edit in two views, not a new feature. Value: medium.

### TD-8 An escape is two unrelated functions, and the edit of an escaped value maps by plain offset

- **Kind:** partial-feature · **Value:** medium · **Effort:** medium · **Confidence:** medium
- **Principle:** 2 and PAR-MAPPERS-ARE-INVERSES (a printer needs its inverse, and the two directions must agree).
- **Today:** A value that the text form escapes is printed by one function in the projection file and read by another in the parser file: `json_escape` ([JsonToSyntax.jl:173](../../../source/domain/json/JsonToSyntax.jl#L173)) and `_string!` ([JsonParser.jl:52](../../../source/domain/json/JsonParser.jl#L52)); `_xml_text_escape` and `xml_escape_attr` ([XmlToSyntax.jl:131](../../../source/domain/xml/XmlToSyntax.jl#L131)) and `_unescape` ([XmlParser.jl:62](../../../source/domain/xml/XmlParser.jl#L62)); `_julia_string_escape` ([JuliaToSyntax.jl:1122](../../../source/domain/julia/JuliaToSyntax.jl#L1122)) and the parser of Julia. Nothing ties a pair together.

  The marker `bound(:value, String, render)` holds the rendered text and no inverse ([ProjectionTemplate.jl:56](../../../source/kernel/projection/ProjectionTemplate.jl#L56)). The engine passes a caret `.value{k}` as it is between the field and the leaf ([ProjectionTemplate.jl:482](../../../source/kernel/projection/ProjectionTemplate.jl#L482)). So in a JSON string that holds a quote, the offsets of the shown text `a\"b` and of the value `a"b` differ after the escape, and a typed `\n` goes into the value as two characters. The template plan records this: "Escaping deferred — the value lens is identity at character-offset granularity".
- **Example:**

  ```julia
  # Today: the two halves, in two files.
  SyntaxLeaf(bound(:value, String, make_hinted_text(() -> json_escape(doc.value); …)); open = "\"", close = "\"")
  function _string!(p) … e == 'n' ? print(io, '\n') : … end

  # Proposed: one value with both directions, used by the rule and by the parser.
  const JSON_STRING = TextEscape(escape = json_escape, unescape = json_unescape)
  SyntaxLeaf(bound(:value, String, …; escape = JSON_STRING); open = "\"", close = "\"")
  ```
- **Problem:** A character edit in an escaped value is correct only while the value needs no escape. Each new format writes a new pair with no check that it is a pair.
- **Proposal:** An escape is one value with `escape` and `unescape`. `bound` takes it: the print applies `escape`, the forward and backward maps move an offset through it, and a text edit is applied to the shown text and written back through `unescape`. The parser calls the same `unescape`.
- **What goes away:** the body of the string reader in each parser as a second definition; the deferred item of the template plan.
- **What stays:** the printed text of every value; the placeholder hints.
- **Risk and open questions:** A caret inside an escape sequence (between `\` and `n`) needs a rule; the simplest is that it does not stop there. A text that is not a valid escape yet (a lone `\`) is an intermediate state: it must go somewhere, most simply into the insertion of the domain as an incomplete number does today. I did not run the editor, so the wrong offset is read from the code and from the plan, not seen.
- **Related plans:** `projection-template-engine.md` lists "Escape-aware character mapping for strings" as out of scope. `a-markdown-page-prints-back-its-text.md` (not built), D10, decided by the owner: "A backslash escape is syntax, and the tree holds the content" and "The IO map takes the difference of one character for each escape"; its step 7 writes that for the Markdown leaves only.
- **Check:** confirmed. I opened the three pairs, the `Bound` marker and the atomic print. Four `bound` leaves print an escaped text and map the caret by plain offset: the value and the key of JSON ([JsonToSyntax.jl:91](../../../source/domain/json/JsonToSyntax.jl#L91), [JsonToSyntax.jl:122](../../../source/domain/json/JsonToSyntax.jl#L122)), the text and the attribute value of XML ([XmlToSyntax.jl:42](../../../source/domain/xml/XmlToSyntax.jl#L42), [XmlToSyntax.jl:70](../../../source/domain/xml/XmlToSyntax.jl#L70)). The string of Julia is an opaque leaf that takes no caret, so it is not hit today. The template plan records the gap ("Escaping deferred", "not yet inverted") and puts it out of scope, so no plan covers the general form. The owner already chose the model for Markdown (D10, added above): the tree holds the content and the IO map takes the difference of an escape. That is this proposal for one domain, and its step 7 would write the fifth and sixth escaped leaf by hand, so the general `escape` of `bound` has a user that is planned. One thing the proposal must allow for it: the escape of Markdown depends on the place (a `|` only in a table cell, a `#` only at a line start), so the escape value is chosen by the rule and may read the context. YAML shows the same fault from the other side: a string prints with no quotes and no escape, so `YamlString("true")` prints `true` and reads back as a bool. The wrong offset is read from the code, as the finding says; nobody saw it in the editor. Value: medium.

### TD-9 The code view of a file is assembled by hand for each file type that has it

- **Kind:** partial-feature · **Value:** medium · **Effort:** small · **Confidence:** high
- **Principle:** 7 (one mechanism for every part).
- **Today:** A Julia file in a tab shows line numbers and fold triangles. `make_julia_file_code_projection` builds that view: `JuliaToSyntax`, `SyntaxToText(text_folds = true)`, `TextLineNumbering`, `TextFolding`, `TextBlockToScrollLayout`, and around it a table with rows for a history, the gutter, text and graphics ([JuliaModule.jl:93](../../../source/domain/julia/JuliaModule.jl#L93)). The language server adapter builds the same view for a C or C++ file, with `MarkedTextToText` as the first step and the same rows around it ([LanguageServerDocument.jl:238](../../../source/adapter/languageserver/LanguageServerDocument.jl#L238)). Each also writes the same wrapper `FileToContent(; content, accepts)` with its own test for "the content, or a history that holds it" ([JuliaModule.jl:78](../../../source/domain/julia/JuliaModule.jl#L78), [LanguageServerDocument.jl:226](../../../source/adapter/languageserver/LanguageServerDocument.jl#L226)). A JSON, XML, YAML or SQL file has no such view: it draws through the general chain with no gutter.
- **Example:**

  ```julia
  # Today, twice: five steps and five rows by hand.
  make_graphics_projection(::Type{JuliaFile}; measure, appearance) =
      FileToContent(; content = make_julia_file_code_projection(; measure, appearance),
                    accepts = _is_julia_file_code)

  # Proposed: the tail is one platform function; a file type names its first step.
  make_graphics_projection(::Type{JuliaFile}; measure, appearance) =
      make_code_file_projection(JuliaDocument, make_julia_syntax_chain; measure, appearance)
  ```
- **Problem:** The next text format that wants numbers copies 25 lines and the history rule. A change of the gutter must be made in each copy.
- **Proposal:** One platform function that takes the content type and the steps up to a `TextBlock`, and adds the numbering, the folding, the scroll layout, the rows and the history rule. A file type whose natural rung is `:syntax` can then get the code view from one general row.
- **What goes away:** two of the three functions and one of the two `accepts` tests, about 50 lines. The third copy is the view of a text of Git, which builds the same tail and the same three rows today ([GitToWidget.jl:555](../../../source/domain/git/GitToWidget.jl#L555)).
- **What stays:** the view of a Julia file and of a source file as they are. A piece of code inside another document draws with no gutter, as the owner decided.
- **Risk and open questions:** The owner decided on 2026-10-08 that only the code of a Julia file in its tab gets the gutter, against "every Julia code view". That decision is about a snippet inside another document, and this finding keeps it. Whether a `.json` tab should show numbers is the owner's choice; the function makes it one row.
- **Related plans:** `a-text-has-a-gutter-beside-its-lines.md` (pending; step 6 records the decision and the Julia view).
- **Check:** confirmed-with-corrections, and the value is lower. I opened the two functions, the Git one and step 6 of the gutter plan. `grep "TextBlockToScrollLayout("` finds three builders, not two: Julia, the source file of the language server and the text of Git. The three share the line spacing, `TextBlockToScrollLayout` and the rows for `TextGutter`, `TextBlock` and `GraphicsCanvas`; two of them share the row for a history and the `FileToContent(; content, accepts)` wrapper. They are not "the same view": only Julia has `SyntaxToText(text_folds = true)` and `TextFolding`, the source file has no fold, and the diff text of Git has no line numbers, so the one function takes the folding and the numbering as options. No plan covers the function. The owner's decision of 2026-10-08 (option b: the gutter only for the code of a Julia file in its tab, not for every Julia code view) is kept by the function itself. The last sentence of the proposal, a code view for every file whose natural rung is `:syntax`, is a new feature for JSON, XML, YAML and SQL tabs and is outside the goal of this review; it needs its own decision. What is left is one helper of about 25 lines for three callers. Value: low.

### TD-10 A domain says how it draws in two tables, and their order decides which view a tab shows

- **Kind:** several-ways · **Value:** medium · **Effort:** medium · **Confidence:** medium
- **Principle:** 7; PAR-DECIDE-LOCALLY (a registry answers only what no part can answer).
- **Today:** The natural slice has two tables for "this type becomes syntax" and two for "this type becomes graphics". The typed table `_NOTATIONS` is filled by `register_natural_domain!` ([NaturalNotation.jl:9](../../../source/platform/natural/NaturalNotation.jl#L9)). The keyed tables `_SYNTAX_FACTORIES` and `_GRAPHICS_FACTORIES` are filled by `register_natural_syntax!` and `register_natural_graphics!` ([NaturalRegistry.jl:38](../../../source/platform/natural/NaturalRegistry.jl#L38)). The renderer reads the keyed rows first and then the typed rows ([NaturalRegistry.jl:101](../../../source/platform/natural/NaturalRegistry.jl#L101)). `print_natural_text` goes through `make_natural_projection`, which reads the typed table: the docstring of `register_natural_syntax!` says "The rows serve the renderer only" ([NaturalRegistry.jl:44](../../../source/platform/natural/NaturalRegistry.jl#L44)). The header of `NaturalRegistry.jl` calls the keyed form "what is left", kept "so a domain can move from one to the other on its own".

  In the area: math registers the same projection for `MathDocument` in both tables ([MathToSyntax.jl:687](../../../source/domain/math/MathToSyntax.jl#L687), [MathToSyntax.jl:693](../../../source/domain/math/MathToSyntax.jl#L693)). Markdown and RST register two different projections for one type at the syntax rung: the rendered style in the keyed table and the source style in the typed one ([MarkdownModule.jl:55](../../../source/domain/markdown/MarkdownModule.jl#L55), [MarkdownModule.jl:65](../../../source/domain/markdown/MarkdownModule.jl#L65)). So "the view of a tab" and "the text of a file" are told apart only by which table holds the row. Book and formula use the keyed tables alone, so they have no notation that `make_natural_projection` can find.
- **Example:**

  ```julia
  # Today: Markdown, three calls.
  register_natural_syntax!(:markdown, (; appearance) -> Pair{Type,Any}[
      MarkdownDocument => MarkdownToSyntax(style = :rendered, …)])
  register_natural_domain!(MarkdownDocument; rung = :syntax, make = (; appearance) -> MarkdownToSyntax(…),
                           format = :md, extension = ".md", parse = parse_markdown)
  register_natural_graphics!(:markdown_page, …)

  # Proposed: one call that names the two roles.
  register_natural_domain!(MarkdownDocument;
      text = (rung = :syntax, make = …source…, format = :md, extension = ".md", parse = parse_markdown),
      view = (rung = :graphics, make = …page…))
  ```
- **Problem:** A domain author must know that the keyed row wins in a tab and the typed row wins in a save. A domain that registers only keyed rows has no text for the assistant.
- **Proposal:** One table. A domain declares the notation of its text (what a file writes and a model reads; it has the format and the parser) and, when it differs, the notation of its view. The renderer reads the view and falls back to the text.
- **What goes away:** the keyed tables and their two registration functions, or their use by the domains; the duplicate row of math.
- **What stays:** every view of today; a registration that carries several rows for several types, which a call for each type gives.
- **Risk and open questions:** The keyed functions have 30 callers in all, 14 in the domains and 16 in the platform, outside my area; I did not read those of the platform, and some may need a row for a type that has no domain root. The same note on process-wide tables as in TD-4 applies.
- **Related plans:** `packages-compose-by-seams.md` (design) and four other pending plans mention these functions as they are; none merges the tables.
- **Check:** weakened. The facts about the code hold: two tables, the keyed rows before the typed rows, the double row of math, the two projections of Markdown and RST at the syntax rung, and book and formula with keyed rows only. But the difference has a stated reason that the finding does not cite. `natural.md` describes both tables and the order ("The factory rows come first, so a factory row wins over a rung row of the same type. Markdown and RST use this"), and lists as a design decision: "Two tables serve two questions. The rung table answers 'this document, up to this target', where the rung of the document must win. The renderer table answers 'any document, in any nesting, to pixels', where a caller or a domain can override a row." The proposal keeps exactly these two roles (`text` and `view`, with the view falling back to the text, which `get_natural_syntax_entries` does today), so it changes the form of the call and not the model. It also does not fit the case that it shows: the page of Markdown is five rows for five types (the root, and four prose blocks; a code block and a thematic break fall to the fabric on purpose, [MarkdownModule.jl:76](../../../source/domain/markdown/MarkdownModule.jl#L76)), and a row for `MarkdownRoot` in the typed table would hide the `:syntax` row of `MarkdownDocument` from `print_natural_text`, because the rung table answers with the rows of the most derived registered type only ([NaturalNotation.jl:145](../../../source/platform/natural/NaturalNotation.jl#L145)). So one `view` on the root type can not say it, and a call for each type in one table breaks the text. What is left: the double row of math, which is one statement to delete; the header of `NaturalRegistry.jl`, which calls the keyed form "what is left" and has no plan behind it; and the choice whether book and formula should have a text notation at all, which is a choice of each domain. The count of callers was wrong and is corrected above. Value: low.

## Covered by plans

- The hand-written node rules of SQL (20 printers, 101 uses of `ChildrenIoMap`), of math and of formula: `projection-template-engine.md`, stages B and C, in progress.
- The hand-written rules of `BookBook` and `BookChapter`: the same plan, by its done criteria; `simplest-syntax-document.md` lists book as opportunistic.
- The opaque leaves of Julia (an identifier, a number, a string take no caret): `julia-syntax-navigation.md`, step 3, open.
- `collapsed` declared on 33 document types and read by 3 rules: `collapse-expand-syntax-nodes.md` for JSON and XML, in progress.
- The fold state and the selection in the data and not in a view: `views-compose-as-content-composes.md`, later.
- The scope analysis of Julia code inside the formula domain (`_collect_free_identifiers!`, [FormulaDocument.jl:269](../../../source/domain/formula/FormulaDocument.jl#L269)): `bound-julia-code-stores-each-name-once.md`, step 7, not started.
- The layout and the lost content of a saved Markdown page, and the wrapper for a line prefix: `a-markdown-page-prints-back-its-text.md`, not built.
- Lines with an indentation in the output of `SyntaxToText`: `text-domain-kit.md`, phase 3, in progress.
- `INSERT`, `UPDATE`, `GROUP BY` and the aggregates in the SQL parser: `sql-insert-update-support.md`, `sql-select-aggregation-support.md`.
- A SQL statement bound to a catalog: `bound-sql-statement.md`, not started.
- A typed line in a math slot, and a typed formula: `math-linear-form-reader.md` step 5, `excel-julia-formulas.md` phase 5 (TD-1 gives both the same buffer).
- The declared types of the fields: `strict-document-types.md`, in progress.
- The export blocks of the module files: `export-block-rule.md`.

## Examined and sound

- The three shared verbs (`replace_selected_document`, `append_insertion_operation`, `move_to_field`) return general operations, so no text domain defines an insert or a delete operation. The only operation types of the area are six of the formula domain: four of its edit mode and two of its computation.
- The cut and the delete of an element are one general step of the clipboard slice, not a rule of each domain.
- The spelling of a reference to another file (`make_reference_leaf`, `find_reference_marker`) differs for each format for a true reason: a JSON string, an XML element, a fence, a directive, a Julia call. Two lines each.
- The natural projection as the general way to hold a document of another domain in a `Document` field: the outer rule delegates to the recursion and names no inner domain.
- `JuliaObject` as the one node that holds a foreign document in Julia code, made by `convert_to_declared_type`: it keeps the declared types of Julia narrow and follows PAR-DOMAINS-INDEPENDENT.
- The formula table that merges the Julia and the math rows: formula holds documents of both domains, so the dependency is real, and its identifier rule must come before the Julia row.
- The edit mode of a formula (a draft copy, Enter commits, Escape drops): a commit as one operation is what a sheet needs, and the keys are a `@gestures` table on the document.
- `SourceFile` of the language server adapter: a text with marks from an outside process, read through a background cell, never in a print. It is a different model from a tree domain for a true reason, and it sits in an adapter because of its dependency.
- Two presentations of one document as a keyword of the builder (`YamlToSyntax(; style)`, `MarkdownToSyntax(; style)`, `RstToSyntax(; style)`): the presentation is a fact of the projection, not of the data.
- Each style role named twice, as the default of a projection field and in the builder: this is the cost of the owner's decision in `plan/done/a-projection-holds-its-styles.md` (a projection holds its styles, a builder fills them). A fill by reflection would save about 200 lines and add a concept; I did not keep it.
- The parsers written by hand: a domain has no third-party dependency, and Julia uses the parser of Julia. See "Parser and printer" for why I propose no general parser.
- `get_document_section` as one shared verb with a method for Markdown and one for RST: the two models differ (flat headings, nested sections), and the verb is shared.
- The `__init__` of YAML, SQL, math and book sits in the projection file and not in the module file. It is a tidiness fault, not a structure fault.

## Check of the report

A second agent checked each finding against the code at commit 3a9b4fae4, the design documents, the rules and the plans. It ran no code. Facts, counts and links that were wrong are corrected where they stand, and each finding has a **Check** item.

| Id | Verdict | Value after the check |
| --- | --- | --- |
| TD-1 | confirmed-with-corrections: the kit for the five domains and the one commit hold; the keys of the buffer must stay where the declared type of the place is known | high |
| TD-2 | confirmed-with-corrections: four copies today, a fifth is planned; the RST rule also needs TD-3 | high |
| TD-3 | confirmed-with-corrections: one carrier (the printer context) and one gap in the template macro, not three ways; the indent half waits for `SyntaxLinePrefix` | medium (was high) |
| TD-4 | confirmed | medium |
| TD-5 | confirmed-with-corrections: the disk read of the pictures is covered by `a-tab-shows-the-file-that-a-program-rewrites.md`, steps 5 and 5a; the Markdown table must become a row first | medium |
| TD-6 | weakened: one data type loses the YAML notation of a tree outside a `.yaml` file, and closes the way to comments and anchors | low (was medium) |
| TD-7 | confirmed-with-corrections: a number in a formula is a `PrimitiveNumber`, which a table on `MathDocument` does not reach | medium |
| TD-8 | confirmed: D10 of the Markdown plan already chose this model for one domain | medium |
| TD-9 | confirmed-with-corrections: three copies, with different options; the code view for every syntax file is a new feature | low (was medium) |
| TD-10 | weakened: `natural.md` gives the reason for the two tables, and the proposal keeps both roles | low (was medium) |
