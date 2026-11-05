# A Markdown page prints back its text

> **Kind:** plan · **Status:** a plan, written 2026-11-05, re-checked at `main` `6b93bfcf3`. Nothing is
> built. · **Stands on:** [markdown.md](../../documentation/package/domain/markdown/markdown.md),
> [syntax.md](../../documentation/package/platform/syntax/syntax.md),
> [text.md](../../documentation/package/platform/text/text.md),
> [a-tab-shows-the-file-that-a-program-rewrites.md](a-tab-shows-the-file-that-a-program-rewrites.md)

This plan makes a save of a Markdown page keep the content that the page read, and makes the
layout of the save follow the layout that most Markdown files of the three repositories use. It
holds the measurement of 1320 files, the content that the tree must keep, the printer rules, and
the share of files that a save still changes.

The defect came up in G4 ([a-tab-shows-the-file-that-a-program-rewrites.md](a-tab-shows-the-file-that-a-program-rewrites.md),
§2 and Q6). The owner decided on 2026-11-05 that it is a plan of its own in the Markdown domain.
The model for the method is the omnet-julia plan
`plan/done/the-ned-and-ini-printers-write-the-layout-of-the-files.md`.

## 1. The goal

1. A save of a Markdown file writes the content that the file holds. `parse_markdown` of the save
   gives the tree that `parse_markdown` of the file gave, for each of the 1320 files of §4.
2. A CommonMark reader reads the same content in the file and in its save, except where §9 says.
3. The layout of the save follows the layout that most files use, rule by rule (§4.3). A file in
   that layout saves byte for byte.
4. A file in another layout changes on its first save, and only in its layout. §4.5 gives the
   measured share.

## 2. The decisions of the owner that bind this plan

- **2026-11-03, the save.** A save is the print of the tree. The tree keeps no original text, no
  stored print, and no layout. No step compares two prints. To keep a diff small, each printer rule
  follows the layout that most files of the corpus use, as measured. A body that the tree can not
  represent does not parse, and stays text.
- **2026-11-05, this plan.** The defect is a plan of its own in the Markdown domain. An ordered
  list keeps its kind, because the kind is content. The printer rules follow the layout of most
  Markdown files of the repositories: the final line end, the empty lines between blocks, and the
  line breaks in a paragraph.

## 3. What exists (checked at `6b93bfcf3`)

No step changes a file under `source/kernel/`. `SEALING.md` lists only `source/kernel/`, so no
step changes a sealed file.

| Fact | Where |
| --- | --- |
| A list item is one paragraph: the marker line and the lines below it that start no block, joined with a space. An indented item is an item of the same list. | `source/domain/markdown/MarkdownParser.jl:281-293`, `:204-205` |
| The marker reader takes `-`, `*`, `+`, `N.` and `N)`, and drops the number. | `MarkdownParser.jl:102-108` |
| `MarkdownList` holds `ordered`, `items` and `collapsed`. It holds no start number. | `source/domain/markdown/MarkdownDocument.jl:158-169` |
| The source item prints `- ` in front of each item, also in an ordered list. A comment says that the numbers are deferred. The rendered list numbers its items from 1. | `source/domain/markdown/MarkdownToSyntax.jl:132-151`, `:544` |
| A paragraph is its lines, stripped and joined with a space. | `MarkdownParser.jl:301-307` |
| A quote prints `> ` at its start and `\n> ` between two blocks. A line inside a block gets no `> `, and no empty line `>` stands between two blocks. | `MarkdownToSyntax.jl:120-130` |
| The page prints one empty line between two blocks, and no line end after the last block. `emit_text` of a `MarkdownFile` is that print. A Julia file and a math file add a line end. | `MarkdownToSyntax.jl:186-193`; `source/domain/markdown/MarkdownFile.jl:28`; `source/domain/julia/JuliaFile.jl:27`; `source/domain/math/MathFile.jl:23` |
| A fence opens with three backticks and closes with a line of three backticks. A fence of tildes or of four backticks is read as paragraphs. | `MarkdownParser.jl:247-257` |
| The code block prints the placeholders `lang` and `code` for an empty language and an empty code. The text, the code span, the link target and the alt text have the placeholders `text`, `code`, `url` and `alt`. | `MarkdownToSyntax.jl:248-257`, `:48`, `:63`, `:209`, `:226`, `:233` |
| `make_hinted_text` puts the placeholder into the content of the span while the value is empty, and `make_text_block` does the same for a block. `TextStringToString` writes the content. So the placeholder reaches the text of a file. A probe on 2026-11-05: `print_natural_text(parse_json("{\"a\": \"\"}"))` gives `"a": "enter json string"`. | `source/platform/text/TextDocument.jl:152-159`, `:443-455`; `source/platform/text/TextToString.jl:22-24` |
| A table entry reads `\|` as a bare pipe, and the row printer writes the entry as it is. So the print has one more column. | `MarkdownParser.jl:149-172`; `MarkdownToSyntax.jl:157-166` |
| A syntax node indents the lines that its children start by `indentation` times `indent_size` spaces, and `indent_size` is 2. A node has no text that starts each of its lines. | `source/platform/syntax/SyntaxDocument.jl:530-537`; `source/platform/syntax/SyntaxToText.jl:284-289`, `:327` |
| A `@projection_template` rule gets the projection and the document, and not the printer context. The rendered text leaf is hand-written, because it reads `:md_style` from the context. | `source/kernel/projection/ProjectionTemplate.jl:281`, `:291`; `MarkdownToSyntax.jl:270-299` |
| One test prints a page and parses it again: the table test. | `test/domain/markdown/MarkdownParserTest.jl:175-181` |
| `test_markdown()` runs the layering guard and nine suites. | `test/domain/markdown/MarkdownSuite.jl:23-36` |
| A new document type brings an atom for the catalog. | `documentation/guide/testing-guide.md:280`; `example/projectured/DomainExamples.jl:295` |
| `markdown.md` says that a printed page is not always its text, and that the parser reads a flat list only, no hard line break and no HTML. | `documentation/package/domain/markdown/markdown.md:40`, `:98` |
| The documentation guard reads the header of a guide as one line with the fields `Kind`, `For` and `Status`, and the first line after it that is not empty must not start with `>`. | `test/suite/documentation.jl:171-200` |

## 4. The measurement

### 4.1 The corpus and the method

The assistant measured on 2026-11-05, with scripts outside the repository in
`/tmp/claude-1001/markdown-print-measure/`.

| Repository | Commit | Markdown files |
| --- | --- | --- |
| projectured-julia | `0d8dd49a0` | 823: `documentation/` 162, `plan/` 653, the files at the root and in `example/` and `tool/` 8. One plan is left out at the request of the owner. |
| omnet-julia | `fbfeaa1c9` | 403 |
| inet-julia | `1e91ecd` | 94 |
| All | | 1320 tracked `.md` files, 415,635 lines |

1. A Julia script ran `print_natural_text(parse_markdown(text))` on each file in
   `environment/all`, through `bounded-run` (177 s, no error).
2. A CommonMark reader, markdown-it-py 3.0.0 with the CommonMark rules and GitHub tables, read
   each file and its print. A difference in its blocks and inlines, with runs of spaces counted as
   one, is a change of content. Every other difference is a change of layout.
3. The same reader counted the layout conventions of the files.
4. A model of the rules of §5 printed each file from the CommonMark tree of the file (§4.5). It
   answers how much a save still changes after this plan. Step 8 measures the real print with the
   tool of step 1.

### 4.2 What the print of today changes

No file prints back as it is. 35 files differ only in the final line end. The print changes
261,085 of the 415,635 lines (62.8%).

The print changes the content of 1046 files (79.2%). For 963 files (73.0%), `parse_markdown` of
the print gives another tree than `parse_markdown` of the file. The causes:

| Content that changes | Files | Where |
| --- | --- | --- |
| An ordered list prints as a bullet list. This holds for all 1777 ordered lists. | 791 (59.9%) | `MarkdownToSyntax.jl:132-151` |
| A list item keeps one paragraph. A nested list becomes items of the outer list (431 files). A second paragraph, a code block or a table leaves the item, and the code keeps the indent of the item. 2505 items hold more than one block. | 555 (42.0%) | `MarkdownParser.jl:281-293` |
| A code block with no language prints the placeholder `lang` (1160 code blocks). An empty code span prints `code`, and an empty link target `url`. | 474 (35.9%) | `TextDocument.jl:152-159` |
| A quote of more than one block loses the empty line `>` between two paragraphs, so they become one paragraph. A code block, a list or a table in a quote loses `> ` on its lines (23 files). | 87 (6.6%) | `MarkdownToSyntax.jl:120-130` |
| The lines of an HTML block join into one paragraph. In 4 files this changes what a reader shows. | 34 (2.6%) | `MarkdownParser.jl:301-307` |
| An ordered list starts at a number other than 1 (30 lists). The number is lost. | 20 (1.5%) | `MarkdownDocument.jl:158-169` |
| An escaped pipe in a table entry prints bare, so the row gets one more column. | 16 (1.2%) | `MarkdownParser.jl:157-160` |
| Link reference definitions on lines that follow each other join into one line, and their links break. | 8 (0.6%) | `MarkdownParser.jl:301-307` |
| A hard line break, two spaces at the end of a line, is lost. Both files use it on purpose, for example for the field lists of omnet-julia `documentation/design/vocabulary.md`. | 2 | `MarkdownParser.jl:301-307` |
| A setext heading, a line over `===` or `---`, becomes a paragraph. | 1 | `MarkdownParser.jl:301-307` |
| A fence of four backticks is not read. | 1 | `MarkdownParser.jl:247` |
| The front matter of a slide deck becomes a thematic break and one paragraph. | 1 | `MarkdownParser.jl:239` |

The 274 files with no content change differ as follows: 35 in the final line end only, 201 also in
the line breaks and the indent, and 38 also in markers or other characters.

### 4.3 The layout that the files use

| Convention | What the files use | The print of today | The rule of this plan |
| --- | --- | --- | --- |
| Final line end | one: 1300 files (98.5%); two or more: 15; none: 5 | none | one |
| Empty lines between two blocks of the page | 1: 64,451 of 65,627 (98.2%); 0: 1116; 2 or more: 60, in 38 files | 1 | 1 |
| The same, a paragraph and then a list | 1: 87.9%; 0: 12.0% | 1 | 1 |
| Empty lines between two blocks of one list item | paragraph, nested bullet list: 0 in 97.8%; paragraph, nested ordered list: 0 in 90.1%; paragraph, paragraph: 1 in 100%; paragraph, code block: 1 in 77.4%; paragraph, table: 1 in 99.4% | the item has one block | 0 before a list that follows a paragraph, else 1 |
| Empty line between two items | none in 10,680 of 11,371 lists (93.9%) | none | none; an empty line ends the list (D3) |
| Bullet | `-` in 9493 of 9595 lists (98.9%); `*` 53; `+` 49 | `-` | `-` |
| Ordered marker | `N.` in 100%; the numbers count up in 1750 of 1758 lists (99.5%) | `-` | `N.`, from the start number |
| Spaces after a marker | one, 100% | one | one |
| Second line of an item | at the column of the item text: 31,189 of 34,023 (91.7%); after a checkbox `[x] `: 2738 (8.0%) | joined | the column of the item text |
| Nested list | at the column of the item text: 1925 of 1935 (99.5%) | flattened | the column of the item text |
| Lines of a paragraph | several lines: 57,616 of 81,409 paragraphs (70.8%); the longest line is at most 80 characters in 70.8% of those | one line | at most 80 characters (D5) |
| Code block | fenced: 3156 of 3521 (89.6%); indented: 365 | fenced | fenced |
| Fence | three backticks: 3155 of 3156; no space before the language: 100% | three backticks | three backticks, more when the code holds three |
| Heading | `#`: 17,942 of 17,943; no `#` after the text: 100% | `#` | `#` |
| Thematic break | `---`: 1094 of 1095 | `---` | `---` |
| Delimiter row of a table | `\| --- \|`: 2305 of 3159 tables (73.0%); `\|---\|`: 850 (26.9%) | `\| --- \|` | `\| --- \|` |
| Table entry | one space each side: 3128 (99.0%); padded to align: 29 | one space | one space |
| Outer pipes of a table | 100% | yes | yes |
| Quote marker | `> ` on 96.5% of the quote lines; an empty quote line is `>` in 186 of 186 | `> `, no empty line | `> `, and `>` for an empty line |
| Emphasis and strong | `*`: 6348 of 6367; `**`: 43,733 of 43,738 | as written | as written: the parser reads `*` and `**` only, so `_` stays text |
| Spaces at the end of a line | none in 1313 files (99.5%) | none | none; a hard line break prints two spaces, as in both files that have one |

### 4.4 The line breaks of a paragraph

Each rule breaks the words of a paragraph at the last space that keeps the line at most N
characters wide, the prefix of the line included. The count leaves out the paragraphs in a quote and
the paragraphs with a hard line break: 81,409 paragraphs of 262,817 lines.

| Rule | Paragraphs kept | Files with every paragraph kept | Lines that change |
| --- | --- | --- | --- |
| one line, as today | 23,793 (29.2%) | 99 (7.5%) | 239,024 |
| at most 72 | 15,146 (18.6%) | 0 | 295,558 |
| at most 78 | 33,644 (41.3%) | 15 (1.1%) | 196,695 |
| at most 79 | 39,678 (48.7%) | 41 (3.1%) | 171,511 |
| **at most 80** | **42,584 (52.3%)** | **35 (2.7%)** | **158,691** |
| at most 84 | 25,575 (31.4%) | 2 (0.2%) | 222,979 |
| at most 100 | 17,637 (21.7%) | 0 | 257,832 |
| at most 120 | 17,481 (21.5%) | 0 | 256,142 |

A rule that never breaks inside a code span changes each count by less than 0.3%. Half of the
paragraphs that break near 80 do not break at the last space that fits. So no width keeps most of
them.

The groups differ:

| Group | Paragraphs | On one line | Several lines, longest at most 80 | Several lines, longest 81 to 100 |
| --- | --- | --- | --- | --- |
| projectured-julia `documentation/` | 7256 | 4846 | 1549 | 729 |
| projectured-julia `plan/` | 45,136 | 12,437 | 21,240 | 10,339 |
| omnet-julia | 24,816 | 5138 | 15,666 | 3676 |
| inet-julia | 3838 | 1090 | 2260 | 443 |

### 4.5 What a save still changes after this plan

The model of §4.1 prints each file with all rules of §5. Four paragraph rules are compared with
the print of today.

| Paragraph rule | Files kept exactly | Lines that change |
| --- | --- | --- |
| the print of today | 0 | 261,085 (62.8%) |
| one line | 63 (4.8%) | 251,994 (60.6%) |
| at most 79 | 34 (2.6%) | 184,897 (44.5%) |
| **at most 80, this plan** | **28 (2.1%)** | **171,199 (41.2%)** |
| the line breaks of the file, kept in the tree (not allowed, Q1) | 459 (34.8%) | 22,466 (5.4%) |

| Group | Files | Today | One line | At most 80 | Line breaks kept |
| --- | --- | --- | --- | --- | --- |
| projectured-julia `documentation/` | 162 | 35.9%, 0 kept | 33.9%, 58 kept | 78.1%, 0 kept | 0.6%, 113 kept |
| projectured-julia `plan/` | 653 | 68.0%, 0 | 65.3%, 3 | 43.6%, 0 | 6.4%, 143 |
| omnet-julia | 403 | 62.0%, 0 | 60.6%, 1 | 29.0%, 10 | 4.6%, 142 |
| inet-julia | 94 | 58.1%, 0 | 55.9%, 0 | 35.2%, 17 | 7.9%, 56 |

The percentages are the lines that change. The 8 other files of projectured-julia count in the
totals only. So with the rule of this plan, about 98% of the files
change on their first save. The line breaks of the paragraphs cause most of it. The guides of
`documentation/` keep most paragraphs on one line, and a save of a guide changes 78.1% of its lines,
more than the 35.9% of today.

A CommonMark reader finds the content of the file in the model print for 1291 of the 1320 files.
Of the other 29, 27 hold a construct that the model does not print as §5 says: 16 escaped pipes, 8
runs of link reference definitions, one front matter, one hard line break in an item, and one list
after a list in an item. One file has a line that would start with an HTML tag, which rule 4 of
§5.3 keeps on the line before. One file has an HTML comment inside a paragraph, whose line breaks
move. In 41 more files a code span crosses a line end in an item whose second line stands after the
checkbox. CommonMark keeps the extra spaces of that indent inside the code span, and the tree keeps
one space. A browser shows one space in both, and the count above counts the spaces of a code span
as one.

## 5. The design

### 5.1 The content that the tree keeps

- **The kind and the start of a list.** `MarkdownList` keeps `ordered` and gets `start::Int = 1`,
  the number of the first item. CommonMark reads no content from the numbers after the first, so
  the tree does not keep them.
- **A list item holds blocks.** The parser reads an item as CommonMark does: the lines indented to
  the column of the item text belong to the item, and a line with less indent continues the
  paragraph above it when it starts no block. The parser removes that indent and reads the lines
  with the same block reader. So an item holds a nested list, more paragraphs, a code block and a
  table. `MarkdownListItem.elements` already declares `Document`, so the type does not change.
- **An empty line ends a list**, as now. Two items with an empty line between them are two lists in
  the tree, each with its start number. A loose list then prints back as it was written, and the
  tree holds no layout field.
- **A hard line break** is a new inline document, `MarkdownLineBreak`.
- **A block that the tree can not represent stays text.** `MarkdownRawBlock(text)` holds such a
  block as written: an HTML block as CommonMark starts it (a comment, a block tag such as
  `<details>`, or a line that holds one complete tag and nothing more), the front matter at the
  start of a file (a line `---` and the lines up to the next `---`), and a run of link reference
  definitions. The page prints it as written.
- **A setext heading** is a `MarkdownHeading`, of level 1 for `===` and 2 for `---`.
- **A fence** of three or more backticks or tildes ends at a fence of the same character that is at
  least as long. The code is a `MarkdownCodeBlock`, as now.
- **A backslash escape stays in the text as written**, also `\|` in a table entry. The parser keeps
  every other escape in the text already.

### 5.2 The printer rules

Each rule is the form that most files use (§4.3).

1. `emit_text` of a `MarkdownFile` adds one line end to the print of the page, as a Julia file
   does. A page that a tool prints with `print_natural_text` gets no line end.
2. One empty line stands between two blocks of the page, and between two blocks of a list item or a
   quote. The one exception: a list that follows a paragraph in an item follows it with no empty
   line.
3. A bullet item starts with `- `. An ordered item starts with `N. `, and N counts up from `start`.
4. Each line of an item after its first starts at the column of the item text: 2 for `- `, 3 for
   `1. `, 4 for `10. `. An empty line in an item has no spaces.
5. Each line of a quote starts with `> `. An empty line in a quote is `>`.
6. A fence is three backticks. When the code holds a run of three or more backticks, the fence is
   one backtick longer than the longest run. An empty code block prints no empty line.
7. A hard line break prints two spaces and a line end. No other line ends with a space.
8. A paragraph breaks its lines at the last space that keeps the line at most 80 characters wide,
   the prefix of the line included (D5). The rules of §5.3 say where a break can stand.
9. Headings, thematic breaks, tables and inline markers print as now (§4.3).

### 5.3 A paragraph prints on one line

The paragraph of the source style prints its inline document on one line (D5). It reads no output
of another projection.

1. No line end stands inside a paragraph, except the line end of a hard line break (D9).
2. A line never starts with text that the parser reads as the start of a block: a list marker such
   as `2026.` followed by a space, `#`, `>`, a fence, a thematic break, a table row, an HTML block
   or a setext line. This holds for the start of a paragraph and for the line after a hard line
   break. Where the text would read so, the printer writes a backslash escape (D10). The paragraph
   asks the predicate of the parser itself, so the two can not disagree.
3. A second paragraph or a block of a list item starts its lines after the line prefix of the item
   (D7).
4. The rendered style shows the text with no escape and breaks lines only on the screen.

### 5.4 A capability of the platform

- **A wrapper starts each line inside it with a prefix (D7).** A new wrapper of the syntax slice,
  `SyntaxLinePrefix(content; prefix)`, beside `SyntaxIndentation`, `SyntaxDelimitation` and
  `SyntaxCollapsible`, each of which has one concern (`SyntaxDocument.jl:196-226`). It starts each
  line that a break inside it starts with `prefix`, as `SyntaxIndentation` moves such a line by
  levels. The prefix stands after the prefixes and the indent of the wrappers above it, and before
  those below it. A prefix on a line with no other text loses its spaces at the end. The prefix is
  part of the frame, as an indent is, so a caret never stands inside it. `SyntaxNode` does not
  change. A quote wraps its blocks with the prefix `> `, and a list item wraps the blocks after its
  first line with the spaces of the width of its marker. Another domain can use it, for example a
  block of comments that starts each line with `# `.

## 6. Decisions

A decision that the assistant proposed counts as approved when the owner approves this plan for
implementation (the owner, 2026-11-05). The owner can name one to see it first.

- **D1. The kind and the start of an ordered list.** Decided by the owner on 2026-11-05 for the
  kind; the start is proposed by the assistant. A: `ordered` stays, `start::Int = 1` is new, and
  the printer counts up from it (99.5% of the ordered lists count up). The new field stands after
  `items`, so `MarkdownList(false, items)` of the two examples still works. Rejected: B, print
  `1.` for each item. CommonMark shows the same list, but no list of the 1758 in the corpus does
  that. Rejected: C, keep the number of each item. CommonMark reads no content from the numbers
  after the first, so they are layout. Rejected: D, a field for the delimiter `)`. No list in the
  corpus uses it.
- **D2. A list item holds blocks.** Proposed by the assistant. A: the parser reads an item as a
  container (§5.1). Rejected: B, keep one paragraph for each item. A save then flattens the nested
  lists of 431 files and moves the code out of the items of 120 files. Rejected: C, a list with a
  nested block stays text. That is 42.0% of the files, and the tree can represent the content.
- **D3. A loose list.** Decided by the owner on 2026-11-05 (open question 6, option B): one list with
  the field `tight::Bool`, as the tree of CommonMark has it. The field is content, because the HTML of
  a loose list differs from the HTML of a tight list. The parser reads the items of a loose list as
  one list, and the printer writes an empty line between the items when `tight` is false. The text
  below is the first proposal, now rejected. First proposal, A: an empty line ends a list, as now, so a loose
  list is two lists with their start numbers. It prints back exactly, and the tree holds no layout.
  Rejected: B, one list with a field `loose`. The field is layout. Rejected: C, one list with no
  field, printed tight. Then 691 loose lists change, and a CommonMark reader shows them with less
  space.
- **D4. The printer rules of §5.2.** Decided by the owner on 2026-11-05: each rule follows the
  majority of §4.3. Where the final line end goes is proposed by the assistant: in `emit_text` of
  the file, as in `JuliaFile.jl:27` and `MathFile.jl:23`. Rejected: the page prints a line end
  after its last block. Then `print_natural_text` of a page, for the clipboard or a tool, ends with
  a line end that the print of a part of the page does not have.
- **D5. A paragraph is one line in the file.** Decided by the owner on 2026-11-05: "no wrapping per
  paragraph in the file". The printer writes each paragraph on one line, as it does now, and the
  tree holds no line break of a paragraph ("No formatting in parsed markdown"). So the printer needs
  no width, an edit never moves the line breaks of the rest of a paragraph, and the header quote of
  a guide stays on one line. The cost is the first save of a file whose paragraphs are wrapped: of
  all 1320 files, 60.6% of the lines change; of the guides, 35.9%. Rejected: a wrap at 80
  characters, which changes 41.2% of all lines but 78.1% of the lines of a guide, needs a width and
  a rule for the start of each line, and breaks the header of a guide over several lines. Rejected:
  the line breaks of the file kept in the tree as the soft break of CommonMark, which is layout in
  the tree.
- **D6. A placeholder in the text of a file.** Skipped by the owner on 2026-11-05 ("skip this issue
  altogether"): this plan does not fix it, and no other plan is written for it now. The fault stays:
  an empty value saves as the hint that the screen shows in its place. The text below is the first
  proposal. Proposed by the assistant: A: the text slice marks
  the span of a placeholder, and the string step writes nothing for it (§5.4). Rejected: B, the
  Markdown projections lose their placeholders. The screen then shows no hint in an empty language,
  and JSON still saves `"enter json string"`. Rejected: C, a field of `TextString`. Every projection
  makes a `TextString` with positional arguments, and the field serves only the string step.
  Rejected: D, the placeholder is a decoration that the graphics step draws over an empty span. That
  is the most exact model, but it changes the draw, the caret space and the hit test of every text.
  It needs a plan of its own.
- **D7. The prefix of a line.** Decided by the owner on 2026-11-05: a new wrapper `SyntaxLinePrefix`
  (§5.4), one concern in one wrapper, as `SyntaxIndentation` is. Rejected by the owner: a field
  `SyntaxNode.line_prefix`, which grows the combined node of every domain for one need of Markdown
  ("bad design"). Rejected: each Markdown printer of a line writes the prefix from a context value,
  so every printer of a line, also the lines of a code block, must know it.
  Rejected: B, an indent in levels of `indent_size`. It can not give 3 columns for `1. ` nor the
  text `> `. Rejected: C, the quote prints its blocks to text itself and adds `> `. It breaks the
  delegation to the children and the reference maps. Rejected: D, an indent of 4 for every ordered
  item. CommonMark accepts it, but 99.5% of the nested lists stand at the column of the item text.
- **D8. A block that the tree can not represent.** Applies the decision of the owner of
  2026-11-03. A: `MarkdownRawBlock` holds an HTML block, the front matter and a run of link
  reference definitions as written. Rejected: B, join their lines as now. The links of 8 files
  break, and 4 files show other content. Rejected: C, a type for each of the three. They differ in
  name only: each prints its text as written. Rejected: D, the whole file stays text. Then up to 43
  files open as text with no structure.
- **D9. A hard line break.** Proposed by the assistant. A: `MarkdownLineBreak`, printed as two
  spaces and a line end, as both files write it. Rejected: B, the paragraph stays text. It then
  loses its links and its emphasis in the editor. Rejected: C, print a backslash and a line end.
  CommonMark reads the same break, but no file of the corpus writes it so.
- **D10. A backslash escape is syntax, and the tree holds the content.** Decided by the owner on
  2026-11-05 (open question 5, option B), for every backslash escape, not only the pipe. The parser
  removes the backslash: `a \| b` in a table cell reads as the text `a | b`, and `\*` as `*`. Only
  the text notation, the print of the file, writes an escape, and only where the syntax needs one:
  a table cell tells its text through a context value that a `|` needs an escape, and the line rule
  of D5 asks the parser which text would start a block. The IO map takes the difference of one
  character for each escape. The owner added: "in the rendered markdown notation you don't need the
  escaping". So the rendered view, a search and the assistant see the real text. An escape that the
  syntax does not need, such as `\.`, goes at the first save. The text below is the first
  proposal, now rejected. First proposal, A: `\|` stays in the entry as written, as
  every other backslash escape stays in the text. Rejected: B, the parser removes the backslash and
  the printer adds it again in a table entry. The text leaf then must know that it is in a table,
  and the offsets of the print and of the text differ by one for each pipe. The cost of A: the
  rendered table shows `\|` in 16 files.
- **D11. The test of the round trip.** Proposed by the assistant. A: a new test with fixed samples,
  one for each rule, and a tool that measures any folder. Rejected: B, a test that prints every file
  of the corpus. The corpus changes with each plan that is written, so the counts of the test move
  with no change of the code.

## 7. Steps

Each step runs in a worktree, ends with one commit, and names its narrowest test. Run each test
through `workspace/bin/bounded-run`: a test under `test/platform/` in
`package/ProjecturedPlatformTest`, a Markdown test in `package/ProjecturedMarkdownTest`, any other
in `environment/all`. Record the counts of `tool/markdown-round-trip.jl` at the end of each step.

- [ ] **1. The measurement, and the final line end (D4).** `emit_text` in `MarkdownFile.jl` adds
      the line end, so each sample of §8 can compare a whole save. A new tool
      `tool/markdown-round-trip.jl` reads every `.md` file under the folders that it gets, saves
      each with `emit_text(MarkdownFile(path, parse_markdown(text)))`, and counts: the files saved
      exactly, the files whose save parses to the same tree, the lines that change, and the ladder
      of §4.2 (final line end, empty lines, line breaks, other). A new `test_markdown_round_trip()` in `test/domain/markdown/MarkdownRoundTripTest.jl`, run by
      `test_markdown()` and exported from `MarkdownSuite.jl`, holds the samples of §8. Each sample
      that fails on main is `@test_broken` with a `# @broken:` comment that names its step. Record
      the counts of the tool over the corpus of §4.1 here, before and after the line end. Tests:
      `test_markdown_round_trip()`, then `test_markdown()`, `test_marker_vocabulary()` and
      `test_file_project()`, which save Markdown files.
- **2. Skipped** by the owner on 2026-11-05 (D6). The placeholder fault is not fixed.
- [ ] **3. A wrapper starts each line inside it with a prefix (D7).** The wrapper `SyntaxLinePrefix`
      in `source/platform/syntax/SyntaxDocument.jl`, and its lines in
      `source/platform/syntax/SyntaxToText.jl`. Update `syntax.md`. Test: `test_syntax_to_text()`
      with new sets: a wrapper with the prefix `> ` over a node with the separator `\n\n` and two children gives
      `> a\n>\n> b`; a prefix of two spaces inside the prefix `> ` gives `> - a\n>   b`; a caret
      after the prefix is at offset 0 of the child; Left from there goes to the end of the line
      above. Then `test_json_to_syntax()`, to show that a domain with no prefix prints the same.
- [ ] **4. A list keeps its kind, its start and its blocks (D1, D2, D3).** `start` in
      `MarkdownDocument.jl`. The marker reader keeps the number, and the item reader of §5.1 in
      `MarkdownParser.jl`. In `MarkdownToSyntax.jl`, the source list is hand-written, as
      `MarkdownListToStyledNode` is: it puts each item in a node whose `open` is the marker, and wraps
      the blocks after its first line in a `SyntaxLinePrefix` of the spaces of its width, and the item follows rule 2 of §5.2. The rendered
      list counts from `start`, and the lines of a nested block take the prefix of the width of the
      marker. Tests: `test_markdown_parser()` with new sets (a nested list, an item of two
      paragraphs, a fence in an item without the indent of the item, a start number, a loose list
      as two lists); `test_markdown_round_trip()` promotes the list samples; then
      `test_markdown_page_wrap()`, `test_markdown_embed_card()` and `test_catalog(; domain = :markdown)`.
- [ ] **5. A quote starts each of its lines with `> ` (§5.2 rule 5).** `MarkdownQuoteToSyntaxNode`
      wraps its node with the separator `\n\n` in a `SyntaxLinePrefix` of `> `; the rendered quote uses `▏ ` the same way.
      Tests: `test_markdown_round_trip()` promotes the quote samples; then `test_markdown_theme()`
      and `test_catalog(; domain = :markdown)`.
- [ ] **6. The rare blocks keep their content (D8, D9, D10).** In `MarkdownParser.jl`: the
      setext heading, the fence of §5.1, `MarkdownRawBlock`, `MarkdownLineBreak`, and `\|` as
      written. In
      `MarkdownToSyntax.jl`: the fence of rule 6, the raw block, the line break, in both styles. The
      two new types get their atoms in `example/domain/markdown/MarkdownDocumentExample.jl`, their
      rows in `example/projectured/DomainExamples.jl`, and their exports. The set "an escaped pipe
      is a pipe in its entry" of `MarkdownParserTest.jl` now expects `x \| y`. The docstring of
      `parse_markdown` names the raw block. Tests: `test_markdown_parser()`,
      `test_markdown_round_trip()`, `test_markdown_page_table()`, `test_catalog(; domain = :markdown)`,
      `test_marker_vocabulary()`, which reads the fence of a reference, and
      `test_referenced_document_editor()`, because a docstring for the assistant changes.
- [ ] **7. A paragraph prints on one line, and its line start is safe (D5, D10).** In
      `MarkdownToSyntax.jl`: the paragraph and the text leaf of the source style write the escape of
      §5.3 at the start of a paragraph and after a hard line break, and the printer of a table cell
      escapes `|`. Tests: `test_markdown_round_trip()` gets a set for each text that would start a
      block, a set for a pipe in a cell, and a set that types a `#` at the start of a paragraph
      through an editor and saves; the file then holds `\#`, and the rendered view shows `#`. Then
      `test_markdown_code_block_edit()` and `test_markdown()`.
- [ ] **8. The documentation and the numbers.** Update "The text form" and "Limits" of
      `markdown.md`: what the parser reads, the rules with their measured shares, and what a save of
      a file in another layout changes. Run the tool over the corpus of §4.1 and record its counts
      here, beside the model of §4.5. Run `Pkg.precompile()` in omnet-julia and in inet-julia, which
      use `parse_markdown`, `MarkdownParagraph` and `MarkdownQuote`. Tests: `test_markdown()` and
      `test_documentation()`. Then move this plan to `plan/done/`.

## 8. Tests

`test_markdown_round_trip()` holds fixed sample texts. For each sample in the layout of §5.2 it
asserts that the save is the sample. For each other sample it asserts the save that §5.2 gives. For
every sample it asserts that the save parses to the tree of the sample, compared with the
description of `_describe_markdown_tree` in `MarkdownParserTest.jl`. The samples:

| Sample | Step |
| --- | --- |
| a heading, a paragraph and the final line end | 1 |
| three empty lines between two paragraphs, saved as one | 1 |
| a code block with no language | 2 |
| an ordered list from 1, and one from 3 | 4 |
| a nested bullet list in an ordered list, at 3 columns | 4 |
| an item of two paragraphs; an item with a fence; an item with a table | 4 |
| a loose list of three items | 4 |
| a quote of two paragraphs; a quote with a code block | 5 |
| a fence that holds three backticks; a fence of tildes, saved with backticks; an empty code block | 6 |
| a setext heading, saved with `#` | 6 |
| a table with the four alignments; an entry with `\|` | 6 |
| a hard line break | 6 |
| an HTML block of three lines; front matter; three link reference definitions | 6 |
| a paragraph of 200 characters in the page, in a `- ` item, in a `10. ` item and in a quote | 7 |
| a paragraph whose break would put `2026. ` at the start of a line | 7 |
| a paragraph with a code span and a link at the place of a break | 7 |

The narrowest test of each step is in §7. The aggregates `test_all()` and `test_printers()` are not
needed.

## 9. Risks

- **The first save changes most files.** With one line for each paragraph (D5), 60.6% of all lines
  change at the first save, and 35.9% of the lines of a guide of `documentation/` (§4.5). Most of it
  is the plans, whose paragraphs are wrapped. Later saves change only what a person edits.
- **The hand-written projections.** Steps 4, 5 and 7 replace template rules of the list, the item,
  the quote, the paragraph and the text leaf with hand-written ones, with their maps and readers.
  The caret can lose a place. `test_catalog(; domain = :markdown)` walks the caret over each atom,
  and the edit tests of step 7 type into a paragraph.
- **The cost of a key.** A key in a paragraph computes the breaks of the whole paragraph again. A
  paragraph of 5000 characters must stay below 1 ms for the computation. Step 7 measures it.
- **The prefix in the syntax step.** `SyntaxToText.jl` serves every domain. A node with no prefix
  must print as now. Step 3 runs `test_syntax_to_text()` and `test_json_to_syntax()`.
- **The placeholder fault stays (D6, skipped).** An empty code span still saves as `code`, an empty
  link target as `url`, a code block with no language as a fence with `lang`, and an empty JSON
  string as `"enter json string"`. The round trip of §8 keeps these cases out of its samples, and
  the numbers of step 8 count them apart.
- **The answers of the tools.** The assistant reads the answers of the documentation tools as
  Markdown. A nested list in such an answer now nests. The excerpts in `MarkdownParserTest.jl` show
  it.
- **The rendered table** shows `\|` for an escaped pipe in 16 files (D10).
- **The rendered page.** A nested list in the rendered page takes the prefix of its marker. A long
  item that the page wraps at its width starts its next row at the indent of the line, as now.
  Steps 4 and 5 run `test_markdown_page_wrap()` and `test_markdown_embed_card()`.
- **The model is not the code.** The numbers of §4.5 come from a model of the rules over a
  CommonMark tree. Step 8 measures the real save with the tool.
- **A search of the assistant.** Step 6 changes the docstring of `parse_markdown`, which carries
  `For the assistant.`, so `search_api` can rank another name first. Step 6 runs
  `test_referenced_document_editor()`.

Not in this plan, and recorded so: a Julia admonition stays a quote (no file of the corpus has one;
the docstrings have them); a code span over a line end keeps one space where CommonMark keeps the
indent of the next line too (§4.5); a code block of one empty line and an empty code block are one
tree; a code span of two backticks is read as two empty code spans, which print back as written.

## 10. Open questions for the owner

1. **The line breaks of a paragraph.** Answered by the owner on 2026-11-05: "No formatting in parsed
   markdown". The tree holds no line break of a paragraph, so A stays and the soft break in the tree
   (C) is rejected. The question was: §4.5 shows that the line breaks decide most of a diff. With
   the rule of 80, a save keeps 28 files of 1320 and changes 41.2% of the lines; a guide of
   `documentation/` changes 78.1% of its lines, more than today. With the line breaks of the file
   kept in the tree, as the soft break of CommonMark, a save keeps 459 files and changes 5.4% of
   the lines, and step 7 becomes a small step in the parser and the printer. Do you keep the rule
   of 2026-11-05 (A), or do you allow the soft break in the tree (C)? The plan follows A until you
   answer. Recommended by the assistant: C, because it keeps the diffs about eight times smaller and
   needs less code than §5.3.
2. **The header of a guide.** Resolved by D5 on 2026-11-05: a paragraph is one line, so the header
   quote stays on one line, and the guard and the guide search need no change. The question was: only with A. The guard reads the header as one line. Must
   `header_violations` read the whole quote at the top of a guide, and `writing-rules.md` and
   `documentation/README.md` say "the header quote"? Or must the printer never break the first
   paragraph of a quote at the top of a page? Recommended by the assistant: the guard reads the
   whole quote, because the plans already break their headers (60 of 66).
3. **Two steps in the platform.** Answered by the owner on 2026-11-05: skip the placeholder fix (D6,
   step 2); step 3 stays. The question was: steps 2 and 3 change the text slice and the syntax slice, and
   step 2 changes the save of every domain. Do they stay in this plan, or move to plans of their
   own? Recommended by the assistant: they stay, each with its own commit and tests, because this
   plan needs both and each is small.
4. **The new names and mechanisms.** Answered by the owner on 2026-11-05: approved, except
   `SyntaxNode.line_prefix`, which became the wrapper `SyntaxLinePrefix` (D7). The names: `MarkdownList.start`, `MarkdownList.tight` (D3), `MarkdownLineBreak`,
   `MarkdownRawBlock`, `SyntaxLinePrefix` (D7, decided),
   and `tool/markdown-round-trip.jl`. The two context properties of the wrap went with D5. Do you
   approve them?
5. **The escaped pipe (D10).** Answered by the owner on 2026-11-05: option B for every backslash
   escape, and the rendered notation shows no escape (D10). The question was: the rendered table then
   shows `\|` in 16 files. Do you accept it?
   Recommended by the assistant: yes.
6. **A loose list (D3).** Answered by the owner on 2026-11-05: one list with `tight::Bool` (D3). The
   question was: a loose list stays two or more lists in the tree. Do you accept it?
   Recommended by the assistant: yes.
