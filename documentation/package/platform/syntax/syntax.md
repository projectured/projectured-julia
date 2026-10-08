# Syntax domain

> **Kind:** design · **Status:** current · **Stands on:** [text.md](../text/text.md), [projection-system.md](../../kernel/projection-system.md), [domain-anatomy.md](../../../design/domain-anatomy.md)

The syntax slice of `ProjecturedPlatform` holds the generic tree between a structured document and styled text: leaves and compounds with delimiters, separators, indentation and a fold state. Every domain with a text form prints to it, and `SyntaxToText` prints it to a `TextBlock`. This document says how the tree is built, how `SyntaxToText` splices the output of the children, and how the shared insertion leaf and placeholder printer work.

<img width="396" alt="Syntax example" src="../../../asset/image/example/syntax.png">

## How it works

`SyntaxLeaf` is the only leaf. It holds a `value` and an optional `open` and `close`, each a `TextString`. Every other type is a `SyntaxCompound`:

| Type | Kind | Holds |
| --- | --- | --- |
| `SyntaxNode` | `SyntaxSequence` | `children`, `open`, `close`, `sep`, `indentation`, `collapsed` |
| `SyntaxConcatenation` | `SyntaxSequence` | `children` only |
| `SyntaxSeparation` | `SyntaxSequence` | `children` and a `separator` |
| `SyntaxDelimitation` | `SyntaxWrapper` | `content`, `opening_delimiter`, `closing_delimiter` |
| `SyntaxIndentation` | `SyntaxWrapper` | `content` and an `indentation` |
| `SyntaxCollapsible` | `SyntaxWrapper` | `content` and a `collapsed` flag |
| `SyntaxNavigation` | `SyntaxWrapper` | `content` only; it marks a place where the caret can stop |

A sequence addresses child `i` as `.children[i]`, and a wrapper addresses its one child as `.content`. `build_syntax_child_path` and `peel_child_step` are the only functions that see this difference. Tree navigation, collapse, the printer and both reference maps are written against `SyntaxCompound`, so a wrapper is a real level of the tree and not a special case.

**The compound contract** is the set of functions that describe a compound. Each function has a default of `nothing`, `0` or `false`:

| Function | Answers |
| --- | --- |
| `get_opening_delimiter`, `get_closing_delimiter`, `get_separator` | `field => span`, or `nothing` |
| `get_indentation` | the indentation, `0` when the compound does not indent |
| `is_syntax_collapsed` | whether the compound is folded now |
| `is_syntax_collapsible` | whether it can fold; only such a compound gets a fold marker |

`SyntaxNode` has a method of each function that reads its own fields. A wrapper has a method of only the one function that matches its name. Code that reads `node.indentation` works for a `SyntaxNode` and not for a wrapper, so call the contract when the input can be any compound. A delimiter comes back as `field => span` with the name of the document field. So a caret in the span maps back to `.<field>{k}`, and the printer does not depend on the name of the field.

**An absent delimiter is `nothing`, not `TextString("")`.** An absent delimiter makes no span and so no caret. An empty `TextString` makes a span that draws nothing and still holds a caret. A bare empty `String` becomes `nothing`. A `TextString` stays, because its content is a cell that can grow later. The tag close of an XML element changes between `" "` and `""`.

### The splice of SyntaxToText

`SyntaxToText()` is a `TypeDispatchingProjection` with `SyntaxLeafToText` for the leaf, one shared `SyntaxCompoundToText` for every compound, and `SyntaxListToText` for a lazy `ListNode`. The chain wraps it in a `RecursiveProjection`.

**Syntax text is a block of `TextLine`s.** A leaf prints one line of runs: its opening delimiter, its value and its closing delimiter. It never reads its value, so an edit of the value leaves the line valid; a `'\n'` that a value holds is a row inside the line. A delimiter or a separator of a compound that holds a `'\n'` is cut there into lines, because it is a constant of the domain, which no edit writes.

**A compound prints only its own level.** It prints each child through `print_child` and joins the lines of the child output into its own lines: the first line of the child joins the open line, every other line follows, and the last line of the child is the open line after it, where the separator or the closing delimiter goes. It never walks the subtree below a child. `_splice_compound` lays out every compound in the same five steps. They are the fold marker, the opening delimiter, the children with separators, the lines and their indentation, and the closing delimiter. A compound whose contract returns `nothing` or `0` for a step adds nothing for it. A folded compound prints no children and adds one ellipsis span.

The IO map, `SyntaxCompoundToTextIoMap`, records where each part went. Each index is an entry of `flat_elements`, the flat list of the output: each span of each line in order, with an entry for the break and one for the indentation of each line after the first. A break counts one flat offset and an indentation its width, so the offsets of the list are the flat offsets of the output.

| Field | What it holds |
| --- | --- |
| `child_iomaps` | the IO map of each child |
| `flat_elements` | the flat list of the output |
| `child_elem_ranges` | the range of entries that the lines of each child fill |
| `chrome_lines` | for each line, whether its indentation is of the chrome of a compound |
| `marker_index` | the fold marker, or 0 |
| `ellipsis_index` | the ellipsis of a folded node, or 0 |
| `own_spans` | each entry of a delimiter span, as entry `=>` (document field, offset in the span) |
| `sep_indices` | each entry of each separator span, as entry `=>` offset in the span |

A parent speaks to a child in the language of the child output: a flat caret, a whole span `[i, j]` of a line, or characters of such a span. So a child that another projection prints works as a syntax child does. Both reference maps use these ranges. A path under `.children[i]` goes to the map of child `i`, and the result moves by the start of the range of that child. A whole-element selection of a child becomes a `TextSpanReferenceStep` box over the range. A caret in a delimiter maps back to `.<field>{k}`. A caret on the marker, a line break, an indentation, the ellipsis or a separator maps back as a projection-introduced position, because no document field holds it. A separator is not in `own_spans`: one field makes `n - 1` spans, so a caret in one of them names no single place in the document.

**An indenting ancestor widens the lines of the chrome of its children.** A compound with `indentation != 0` starts a line with an indentation of one level before each child. When it joins a child, it adds one more level to every line that the child marks in `chrome_lines`, and it marks them in its own list. So the depth adds up level by level, and no compound computes its absolute depth. A compound that indents also starts a line with no indentation of its own before its closing delimiter, which an ancestor widens too. A line that a break inside a delimiter or a separator starts keeps indentation 0: the text of a span is its own, with its own spaces.

The reader has the same shape. An edit in a span of child `i` goes to the reader of that child, and `.children[i]` goes in front of the result. An edit in a separator span changes the one separator field, so every gap changes. An edit on other spans of the node gives `nothing`. A click on the marker or on the ellipsis gives a `ToggleCollapseOperation` for the node, and an Alt+click selects the whole leaf or node under it. Ctrl+. arrives with no target, and the reader resolves it to the innermost compound that can fold and holds the caret.

`SyntaxListToText` prints a lazy list of syntax as a lazy list of the lines of its elements, with no separator between two elements, because a line implies its break. Element `k` maps to the run of its lines, counted from the head, and a part of an element maps to the line, the span and the characters that hold it.

At the seam between a value and its closing delimiter, the backward map of a leaf returns `value{n}` and not `close{0}`. The two are the same place on the screen, but only the value is editable. Without this, the only caret of an empty string could not be reached.

### The delimiters around the pointer

**The delimiters of the compounds around the part under the pointer are lit by their level.** Each compound finds its level from its own mouse target: the number of compounds with a visible delimiter that the path enters below it. The compound that holds the part under the pointer is at level 0, and its delimiters are in `delimiter_light_color`. At each level further out, the colour mixes more with the colour of the delimiter. From level `delimiter_light_levels` on, the delimiter has its own colour. A compound with no mouse target is not around the part, so its delimiters keep their colour too. In `[1, [2, [3]]]` with the pointer on the `3`, the array `[3]` is at level 0, `[2, [3]]` is at level 1, and the outer array is at level 2.

A compound with empty delimiters, such as the entry of a JSON object, is not a level. So the light steps from one pair of brackets to the next pair that shows.

The span that draws a delimiter is not the span of the document. It holds the cells of the document span, so an edit of the delimiter shows at once, but its colour is a computed cell that reads the level. The span is cached with the decorative spans, so a layout keeps it. A move of the pointer computes only the colour cells. It does not lay out the node again, and the output elements stay the same objects.

The defaults are the orange of the solarized palette and 4 levels. `SyntaxToText(; delimiter_light_color, delimiter_light_levels)` sets them, and `delimiter_light_levels = 0` keeps every delimiter in its own colour.

### Tree gestures

The keyboard half of the reader is two `@gestures` tables in `source/platform/syntax/SyntaxDocument.jl`. They walk selection paths and read no pixels.

| Key | On | Edit |
| --- | --- | --- |
| Ctrl+Alt+Home | a compound or a leaf | select the root node, or the whole leaf |
| Ctrl+Space | a compound or a leaf | toggle between a whole-element selection and a text caret |
| Alt+arrow | a compound | move in the tree from any selection |
| an arrow | a compound | move in the tree, only when a whole element is selected |

The table is on `SyntaxCompound`, so every wrapper type has tree navigation. `SyntaxCompoundToText` gives a `KeyDown` to this table and keeps only the mouse arms.

### The insertion leaf

`InsertionToSyntaxLeaf(commit; prefix, suffix, completion, commit_at_key, cancel)` prints a document that has an editable `value` string as a typed-name buffer. The output is a `SyntaxDelimitation` around one leaf: `prefix`, the typed value, a pale continuation, `suffix`. The colour of the value and the text of the continuation are computed cells over `completion(insertion)`, so the feedback changes with each key and nothing prints again.

The default policy is `name_completion` of `ProjecturedDomain`. It returns one of four states:

| State | The typed value | The continuation |
| --- | --- | --- |
| `:empty` | the neutral colour | none |
| `:invalid` | red | none |
| `:ambiguous` | green | none; Tab adds the part that all the matching names share |
| `:unambiguous` | green | the rest of the one matching name |

The keys are in a gesture table of the projection, `get_projection_gesture_bindings`, because two of them call the projection. Enter calls `commit(insertion, text)` and replaces the buffer with the result. Escape replaces it with `get_nothing_document(typeof(insertion))()`, the placeholder of the domain, or with what the option `cancel(insertion)` gives. The `placeholder` is a text, or a function of the insertion that gives one, so the type-in of a primitive shows its own. Tab adds the extension. When the table gives `nothing` for a key, the key goes to the `@gestures` table of the insertion document. So a type-to-replace key of the domain still works on the buffer.

**A key can replace the buffer at once.** With the option `commit_at_key(insertion, text, caret)`, a key that edits the text asks it for a document for the text after the key. When it gives one, the key replaces the buffer with that document, whose caret is at `caret`; when it gives `nothing`, the key edits the text. A key that comes as a text edit from a later stage takes the same way. The type-in of a primitive uses both options.

Two constructors cover the name insertions. `DocumentInsertionToSyntaxLeaf()` reads "Insert a new … here" and completes over every document type. `DomainInsertionToSyntaxLeaf(root)` completes over the candidates of one domain without the domain prefix, so inside a `JsonInsertion` the name `string` makes a `JsonString`. Its `placeholder` keyword gives the text that an empty buffer shows in place of the frame, in the colour of the label: JSON passes `"enter json value"`, as its empty key shows `enter key`. A caret on the placeholder, or on the completion hint, is the caret at the end of the name. The candidates come from reflection over the loaded types; [domain.md](../domain/domain.md) describes it. A domain whose buffer holds source text passes `completion = parse_completion(parser)`, and the value is green when it parses. `SqlInsertionToSyntaxLeaf` is built this way. `JuliaInsertionToSyntaxLeaf` is a separate projection, and the `@gestures JuliaInsertion` table does its editing.

### The placeholder printer

`InsertionNothingToSyntaxLeaf()` prints every `*Nothing` placeholder that `@domain` makes. It shows a muted italic label made from the type name: `JsonNothing` prints "empty json". It has no reference maps of its own. The fallback of `Projection` maps a whole-element selection, and it keeps a caret on the label as a projection-introduced position.

**A typed key on the placeholder runs the create gesture of the document type.** The text stage turns the key into an insert on the label, which arrives as a `ReplaceStringRangeOperation`. The reader gives it back to `read_gesture` on the placeholder as a `KeyPress`. So `{` on "empty json" makes a `JsonObject`, from any caret and without a whole-element selection first. A key with no create rule does nothing, and a delete does nothing. The Insert key goes through the fallback to the placeholder table and opens the insertion buffer.

`SyntaxNothing` does not exist. `SyntaxInsertion` is declared, but no projection prints it and no code makes one; see [plan/pending/simplest-syntax-document.md](../../../../plan/pending/simplest-syntax-document.md).

### The bridges

- `ObjectToSyntax()` reflects any Julia value into a tree by its runtime type. A struct becomes a node of its type name and one node for each field. A `Bool`, number, string, `Symbol`, `Char` or `nothing` becomes a leaf.
- `ObjectFieldToSyntax()` prints one field of one object, an `ObjectField` of the primitive slice, as the name leaf and the value. `ObjectToSyntax` prints each field from its `Cell` through `CellToSyntax`, so a write to the cell repaints the field. An `ObjectField` has no cell, so it needs a separate projection. Put its row in front of the `ObjectToSyntax` table, or the `Any` row prints the whole object.
- `CollectionToSyntax()` prints a `CellVector` as a node in brackets and keeps a `ListNode` lazy.
- `PrimitiveToSyntax()` prints a `PrimitiveBool`, `PrimitiveNumber` or `PrimitiveString` as a leaf, and a `PrimitiveInsertion` as a type-in.
- **The type-in of a number.** `PrimitiveNumberToSyntaxLeaf` with `allows_type_in` reads a key whose text the number can not show, such as `-`, `1e` or `12.`, as a replace of the number with a `PrimitiveInsertion` of that text, limited to a number (`make_number_edit_operation` of [primitive.md](../primitive/primitive.md)). A range edit is no path operation, so the leaf reads it with a method for `ReplaceRangeOperation` over the default reader. Only `PrimitiveToSyntax` turns the option on, because its table also prints the type-in; the math domain prints its numbers with the same leaf and the option off. `PrimitiveInsertionToSyntaxLeaf()` is the source insertion of the type-in: its text is green when it parses as one of the allowed types and red when it does not, a key whose text an allowed type shows exactly replaces it with that document (`commit_at_key`), Enter replaces it with the first allowed type that the text parses as, so `1.50` becomes `1.5`, and Escape puts the first allowed type with no value (`cancel`). An empty type-in shows `enter a value`.

`make_natural_to_syntax_dispatch(; appearance)` builds the table of the general renderer, and passes the `Appearance` of the editor to every registered row. The rows that domains register with `register_natural_syntax!` come first. Then come `PrimitiveToSyntax`, the placeholder and insertion rows of `Text` and `Document`, `CollectionToSyntax` and the `ObjectToSyntax` table. The `DocumentNothing` and `DocumentInsertion` rows are what an empty pane tab shows.

### The theme

`SyntaxTheme` holds the text of each kind of leaf that this slice prints (a
boolean, a number, a string and its quotes, a symbol, a nothing, a reflected
boolean), of the name of a type and of a field and of a note (an undefined field, a
cycle, an empty placeholder), of a delimiter and a separator of a collection, of
the parts of an insertion and the colors of its completion states, and the color
that lights the delimiters around the pointer. The leaves, the reflection, the
collections, the insertions and `SyntaxToText` take `theme`; with none they draw
the default values. The natural renderer gives them the scaled `SyntaxTheme` of
its `Appearance`, so at a font scale of 1.5 its syntax is 1.5 times as large. A
domain that prints its own leaves styles them from a theme of its own.

## How it fits

The syntax slice depends on the kernel and on the text, domain, natural, primitive, collection, projection and style slices. Every domain with a syntax chain depends on it; [domain-anatomy.md](../../../design/domain-anatomy.md) shows the chain.

Its `__init__` calls `register_syntax_fallback!()`. That registers the reflection table as the fallback of the natural renderer and the rung from syntax to text. So a session that loads `ProjecturedPlatform` can draw a document of any shape, and the natural slice does not name this one. The fallback has a row for `SyntaxDocument` too: a syntax tree that a view puts among its parts, such as the path view in the bar of a navigator, starts at the stage from syntax to text and is not reflected as a struct.

## Design decisions

- **A compound prints only its own level.** A printer that walks the whole subtree prints every node again for one edit and loses the identity of each child output. The splice keeps the output of an unchanged child. See [plan/done/syntaxtotext-delegation.md](../../../../plan/done/syntaxtotext-delegation.md).
- **The depth adds up level by level.** An indenting ancestor widens the lines of the chrome that its children report, which gives the same width as `depth * indent_size`. No compound needs its absolute depth.
- **Syntax text is lines, and a leaf never reads its value.** A line is what the gutter, the numbers and the folds of the text domain stand on. A `TextString` is one run, so a domain states that a field can hold lines by the type it gives the leaf value; a leaf that read its value to find a break would build its lines again after every keystroke, because a cell has no cut-off for an equal value. See [plan/pending/text-domain-kit.md](../../../../plan/pending/text-domain-kit.md), Q1 to Q5 of step 3 of Phase 3, and [plan/pending/a-text-span-holds-no-line-break.md](../../../../plan/pending/a-text-span-holds-no-line-break.md).
- **The light of a delimiter is a colour cell, not a layout.** A move of the pointer changes the mouse target of each compound on the path. If the spans read the level, each move would lay out every compound on the path again. See [plan/done/a-document-knows-the-part-under-the-pointer.md](../../../../plan/done/a-document-knows-the-part-under-the-pointer.md), question Q8.
- **The printer records where each span went.** With optional delimiters no position identifies the opening or the closing span, so `own_spans` holds the field of each one.
- **The contract is five functions, not one type with five fields.** A wrapper adds one thing to any document and is a real level of the tree. `SyntaxConcatenation` and `SyntaxSeparation` can not get a delimiter by accident. See [plan/pending/simplest-syntax-document.md](../../../../plan/pending/simplest-syntax-document.md), whose first two phases are done.
- **Content is positional and chrome is a keyword.** `SyntaxLeaf(value; open, close)` and `SyntaxNode(children; open, close, sep)` put the content first. See [plan/done/syntax-constructor-keywords.md](../../../../plan/done/syntax-constructor-keywords.md).
- **A placeholder key is a create gesture, not a text edit.** The label is a prompt, so a typed key goes to the document table and not into the label.
- **Completion is reflection.** No list of names exists; a new document type is a candidate as soon as Julia evaluates its `struct`.

## Usage

```julia
leaf = SyntaxLeaf("hello"; open = "(", close = ")")
render(leaf)                         # "(hello)"

node = SyntaxNode(SyntaxDocument[SyntaxLeaf("a"), SyntaxLeaf("b")]; open = "[", close = "]", sep = ", ")
render(node)                         # "[a, b]"

wrapped = SyntaxDelimitation(SyntaxLeaf("x"); opening_delimiter = "<", closing_delimiter = ">")
chain   = RecursiveProjection(SyntaxToText(; indent_size = 2))
```

A path into a leaf is `.open{k}`, `.value{k}` or `.close{k}`. A path into a compound is `.children[i]` or `.content` for a child, or a caret in one of its delimiters, such as `.open{k}` on a `SyntaxNode`.

- Examples: `syntax_example` and `object_field_syntax_example` in `example/platform/`. Each domain has its own syntax examples, such as `sql_syntax_example`.
- Tests: `test_syntax()`, `test_syntax_to_text()` and `test_object_field_to_syntax()` in `test/platform/`; `test_syntax_tree_selection()` and `test_document_insertion()` in the umbrella suite.

## Limits

- `SyntaxLeaf` has `indentation` and `collapsed` fields, but the compound contract is not defined for a leaf and `SyntaxLeafToText` reads neither.
- A `@projection_template` node with a fixed list of children must use the positional seven-argument `SyntaxNode` form. The keyword form stores a `CellVector`, and the template engine then does not find the markers inside it.
- JSON and XML do not pass `collapsed` to their nodes, so their containers do not fold. See [plan/pending/collapse-expand-syntax-nodes.md](../../../../plan/pending/collapse-expand-syntax-nodes.md).
- A selection of a range of siblings, such as `.children[2..4]`, does not exist. See [plan/pending/syntax-tree-selection.md](../../../../plan/pending/syntax-tree-selection.md).
- `SyntaxToText` makes no `TextLine` and keeps its own indentation spans. See [plan/pending/text-domain-kit.md](../../../../plan/pending/text-domain-kit.md).
