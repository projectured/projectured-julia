# A text span holds no line break

> **Kind:** plan · **Status:** pending, 2026-10-08. The owner decided the rule
> (§1), N1, N1b and N2 with N3 on 2026-10-08; §9 holds the steps, and no step is
> started. ·
> **Stands on:** [text.md](../../documentation/package/platform/text/text.md),
> [syntax.md](../../documentation/package/platform/syntax/syntax.md),
> [text-domain-kit.md](text-domain-kit.md) (Q5 of step 3 of Phase 3),
> [cell.md](../../documentation/package/kernel/cell.md)

## 1. The goal and the rule

The owner's principle (2026-10-08): "I prefer the changes to the edited document
to cause little changes in the output down the chain."

The rule, decided by the owner on 2026-10-08:

- **A `TextString` holds no `'\n'`.** A break is always a line: the break
  before a `TextLine`, or a `TextNewline` element.
- **The domain states which fields can hold lines, by the type it gives the
  value.** A `TextString` is one run, and a `TextBlock` of `TextLine`s is a text of
  lines. A domain can keep a `String` field, or hold a `TextDocument` where it
  wants to (N1 below says who turns which into lines).
- **The syntax states nothing of its own.** A syntax content field takes what the
  domain gives.

The other options that the owner did not take: every leaf reads its value to find
a break; a flag on `SyntaxLeaf` that a domain sets; a required `TextBlock` in each
domain.

## 2. Why the structure must not come from the content

The cell system has no cut-off for an equal value: a write invalidates every cell
that reads it, also when a computation gives the same value again (decision 10
of `architecture-decisions.md`). So a projection that reads a content to find its
breaks computes its line list again after every keystroke, and every stage that
reads that list computes again too, down to the screen.

Real editors keep a line index that the edit updates; they do not search the
content for the lines after each key. The rule puts the lines in the structure
where the domain makes them, and an edit of a run changes one run.

## 3. The rules today

| break | where it comes from | flat offsets | how `TextToGraphics` draws it | an edit of it changes |
|---|---|---|---|---|
| a `TextNewline` element | prose, the lazy list, the soft breaks of `WordWrapping` | 1 | it ends a group, one line canvas | the element list |
| the break before a `TextLine` | a producer of lines: the gutter, `TextLineNumbering`, `SyntaxToText` from step 3 | 1 | a group per line | the element list |
| a `'\n'` in the content of a `TextString` | a leaf value, a delimiter, a separator, a text of a log, a fault, a message | 1 | a row inside the same group | the content of one span |

The text domain has no Enter key, and `TextToGraphics` keys the canvas of a line
by the index of the line.

## 4. The rules after this plan

1. A `TextString` holds no `'\n'`, and a test guard rejects one that does.
2. The text domain edits a break as structure: Enter splits the line at the
   caret, so a new `TextLine` takes the runs after the caret; Backspace at the
   start of a line and Delete at its end join two lines; a paste of a text with
   breaks makes lines. A typed character edits one run.
3. A domain stage turns a `String` of its own with breaks into a `TextBlock` of
   lines in its style, as it turns a string into a styled `TextString` today
   (N1). A line whose text did not change stays the same object, and a split or a
   join of a line maps back to an edit of the string. `StringToTextBlock` does the
   same for a string that no domain decides.
4. The content fields of the syntax (`value`, `open`, `close`, `sep`) take a
   `TextDocument`, and a leaf joins the lines of a block value as a compound joins
   the lines of a child: its first line joins the line of `open`, and `close`
   goes on its last line. A constructor converts a string that holds `'\n'`, such
   as `open = "[\n"`, into such a block (N2).
5. **A break is text, and `indentation` only indents (N2).** A break of the layout
   is in the opening delimiter, the separator or the closing delimiter of a
   compound. A line that a break in the opening delimiter or in a separator starts
   is inside the node, at the indentation of the line of the node plus
   `indentation × indent_size`; a line that a break in the closing delimiter
   starts is at the indentation of the line of the node. These are lines of the
   chrome, so an ancestor moves them by its own indentation. A node is inline when
   its texts hold no break; the layout makes no break of its own.
6. ~~`TextToGraphics` keys the canvas of a line by the line object~~, so an
   inserted line lays out alone and the lines below keep their canvases. **Done
   2026-10-08 on the branch `text-gutter`,** because a structural edit of the lines
   of syntax text lost the graphics of every line after it (step 3 of Phase 3 of
   `text-domain-kit.md`).
7. `TextToGraphics` and `TextFirstLine` drop their rule for a `'\n'` inside a span.

## 5. What a keystroke costs

| the field holds | a keystroke without a break | a keystroke that makes a break |
|---|---|---|
| a `TextString` (an identifier, a JSON value) | one run changes; one line lays out | not possible: a run holds no break |
| a `TextDocument` | one run changes; one line lays out | one line is inserted; the joins above it change at one place; the new line lays out |
| a `String` | `StringToTextBlock` splits the string again and reuses each unchanged line; the joins up to the root compute again (pointer work, no layout); one line lays out | the same, with one more line |

## 6. What it touches

- **The projections to syntax that put a `'\n'` into a span**, about 15:
  - The message log, the gesture log, the help list, the command palette, the
    undo buffer, the gesture map, the about page and the fault log use
    `sep = TextString("\n")` to put each child on a line.
  - Julia (the fence `"\n\"\"\"\n"` and a `"\n"` separator), Formula,
    reStructuredText, Markdown, SQL and Book have about 76 lines with a break
    literal.
- **The producers of a free text** that can hold a break: the fault messages,
  the conversation, `ObjectToSyntax`, `PrimitiveToText`.
- **The text domain:** the split and join operations, the paste, the key of a
  line canvas, the guard.
- **The syntax:** the field types and their constructors, a leaf with a block
  value, the mappers and readers of a path into a block value.
- **The domains with a text of many lines** (Markdown code blocks and texts,
  Book paragraphs, Julia docstrings and strings, XML text nodes, SQL raw texts):
  each gives a `String` or a `TextDocument` for that field in place of a
  `TextString`.

## 7. Open questions

One at a time, with the owner.

- **N1 Who turns a string into lines. Decided, the owner, 2026-10-08:** the
  domain stage, as it turns a string into styled text today.
  - A domain stage converts its own strings into styled text: `JuliaToSyntax`
    already gives a comment or a docstring as `TextString(() -> d.text, p.doc_style)`.
    For a field of many lines that text is a `TextBlock` of `TextLine`s in the
    style of the domain. There is no new text type.
  - A plain string never goes through the generic recursion: in a document that
    mixes domains, a dispatch on `String` can not know which domain a string
    belongs to, so only the domain that holds it can style it.
  - A field can also hold a text-domain document. The domain stage checks the
    value with `isa`: a plain string it converts itself; a `TextString`, a
    `TextBlock` or another text document it recurses into, because the type of a
    text document says what it is.
  - The value of a `SyntaxLeaf` takes a `TextDocument`: a `TextString` for one
    run, a `TextBlock` for lines.
  - `StringToTextBlock` is a projection of the text domain for a string that no
    domain decides, such as a string that stands on its own; most domains decide
    themselves.

  The options that the owner did not take: a new text type that may hold `'\n'`,
  printed by a row of the recursion; a `String` value with a `style` field on the
  leaf; a child projection `StringToTextBlock` that every domain stage calls.
- **N1b The shared helper and the edit of a line. Decided (a), the owner,
  2026-10-08:** a helper of the text domain, `make_text_block(content_thunk,
  style)`, the twin of `make_hinted_text`: it makes a `TextBlock` of `TextLine`s
  in the style from a string, and a line whose text did not change stays the same
  object. A domain uses it where it uses a styled text today, inside `bound`:

  ```julia
  SyntaxLeaf(bound(:text, String, make_text_block(() -> d.text, p.doc_style)))
  ```

  The leaf names an edit in a block value by flat offset, `value[s:e]`. In a block
  of lines that a string makes, the flat offset is the offset in the string,
  because a break counts one as the `'\n'` does, so `bound` maps it to the field
  unchanged; Enter becomes the insertion of `'\n'`, and Backspace at the start of
  a line its deletion. No domain maps an edit itself, and the template engine does
  not change. The owner asked for a name of the text domain; `make_text_block`
  names the type it makes. The option not taken: a projection per domain through
  `project(:text; as = …)`.
- **N1c A text document in a field.** What the recursion of the domain-to-syntax
  stage does with a text document that a field holds. **Left open, the owner,
  2026-10-08:** no domain holds a text document in a field today, so the row
  waits for the first domain that does; the likely row is a leaf whose value is
  that document itself.
- **N2 and N3 Where a break of the layout is. Decided, the owner, 2026-10-08:** a
  break is text in the opening delimiter, the separator or the closing delimiter,
  and `indentation` only indents (rule 5 of §4).
  - Today the integer `indentation` does two jobs: it puts breaks after the
    opening delimiter, before each child and before the closing delimiter, and it
    indents the lines they start. Only zero and its sign count: `2` (the file
    system) acts as `1`, and `-1` (YAML, the database catalog, SQL, all with no
    closing delimiter) only drops the line before the closing delimiter, which a
    node with no closing delimiter shows as an empty last line. No value puts each
    child on a line with no indentation, so 27 places write `sep = "\n"` and Julia
    puts `"\n"` into leaf values. NED (in omnet-julia) puts `"\n\n"` at the start
    of each heading and an empty `close` in each section, and INI joins with
    `"\n\n"` and `"\n"`, which make the empty lines there.
  - The decision: the texts hold the breaks, written as strings that the
    constructors convert (`open = "[\n"`, `sep = ",\n"`, `close = "\n]"`; the owner:
    "I would allow the "[\n" string as open/etc. and convert it"), and
    `indentation` is a count of levels, multiplied by `indent_size`, that indents
    the lines inside a node. The examples:

    | layout | `open` | `sep` | `close` | `indentation` |
    |---|---|---|---|---|
    | JSON array | `"[\n"` | `",\n"` | `"\n]"` | 1 |
    | YAML list | `"\n"` | `"\n"` | nothing | 1 |
    | Lisp call, head then body | `"("` | `" "` | `")"` | 0, with a body node `"\n"`, `"\n"`, nothing, 1 |
    | Julia struct body | `"\n"` | `"\n"` | `"\n"` | 1 |
    | docstring, log | nothing | `"\n"` | nothing | 0 |
    | INI file | nothing | `"\n\n"` | nothing | 0 |

    The Lisp call keeps `)))))` on its last line because its `close` holds no
    break, and YAML and NED lose their empty last lines because no text holds the
    break that made them.
  - Not taken: a flag "on lines" with a `gap` of empty lines (the owner: `gap = 1`
    is a separator that is one break); empty leaves as spacers, which break the
    rule that child `i` is element `i` of a collection; a new wrapper
    `SyntaxLines`; a flag `keeps_last_line`, which named what `-1` hid.
  - Later, not in this plan: a soft break that a node takes only when it does not
    fit the width, as the `line` of a pretty printer of Wadler does, so `[1, 2]`
    stays on one line.
- **N4 The edit of a break in a `String`.** Decided by N1b: Enter in a line of a
  block that `make_text_block` made inside `bound` is the insertion of `'\n'` at
  that flat offset of the string, and Backspace at the start of a line its
  deletion.
- **N5 `TextNewline`.** What a `TextNewline` element means after this plan: the
  prose, the soft break of a wrap (Q4 of `text-domain-kit.md`) and the lazy list
  use it today.
- **N6 The order of the domains.** Julia first, because the gutter targets the
  Julia view.

## 8. Facts found

- 2026-10-08: the cell system has no cut-off (decision 10), so any line list
  that is computed from a content changes after every keystroke in that content.
- 2026-10-08: `TextToGraphics` kept a line canvas by the index of the line, so a
  new line list laid out every line again, also when most `TextLine` objects were
  the same. It now keeps it by the line object (rule 6).
- 2026-10-08: the JSON view writes a newline inside a string as the escape `\n`,
  so a JSON leaf never holds a break.

## 9. Steps (tentative)

Each step is one commit, on a branch in a worktree, with its tests. Steps 2 to 4
change how every view of syntax makes its lines, so they land together.

0. **The baseline.** The guards and the suites of the domains that print through
   `SyntaxToText`, the example sweeps and the console, each part in a process of
   its own, at main before step 1.
1. **`make_text_block(content, style)`** in the text domain: a `String` or a
   thunk of one, to a `TextBlock` of `TextLine`s in the style; a line whose text
   did not change stays the same object. Tests.
2. **The syntax reads breaks from texts.** The content fields take a
   `TextDocument`, and `_text` converts a string, or a constant `TextString`, that
   holds `'\n'` with `make_text_block`. `SyntaxLeafToText` joins the lines of a
   block value and names an edit in it by flat offset, `value[s:e]`.
   `SyntaxCompoundToText` joins the lines of a block delimiter or separator, and
   indents by rule 5 of §4. Until step 4 a node with an `indentation` that is not
   0 and whose texts hold no break keeps the breaks of today, so each domain moves
   in a step of its own; step 4 removes that path.
3. **The domains state their breaks**, one commit for each, with its suite and
   the example sweeps: JSON, YAML, XML, SQL, FSM, the collections, the reflection
   of objects, the file system (its `2` becomes `1` unless the owner wants two
   levels), the database catalog, Formula, reStructuredText, Markdown, Book, the
   lists of the platform (the logs, the help, the command palette, the undo
   buffer, the gesture map, the about page, the fault log), and Julia, with its
   fences and its `"\n"` leaves.
4. **`indentation` only indents.** The transition of step 2 and the breaks of
   the integer go, `-1` goes, and the flat metric (`_syntax_to_flat`,
   `_subtree_len`) follows. A full sweep against step 0.
5. **Values of many lines**, Julia first (N6): its docstrings and its strings of
   many lines, then the code blocks and the texts of Markdown, the paragraphs of
   Book, the text nodes of XML and the raw texts of SQL, each with
   `bound(:f, String, make_text_block(...))`. Check: a Julia file with a docstring
   numbers each of its lines.
6. **The text domain edits a break as structure** (rule 2 of §4): Enter,
   Backspace and Delete at a line boundary, and a paste with breaks, on a block of
   lines; in a block inside `bound`, they are edits of `'\n'` in the string.
7. **The guard**: a test walks the printer output of every example and rejects a
   `TextString` that holds `'\n'`. `TextToGraphics` and `TextFirstLine` drop their
   rule for a `'\n'` inside a span. The producers of a free text (the fault
   messages, the conversation, `ObjectToSyntax`, `PrimitiveToText`) give lines,
   with `StringToTextBlock` for a string that no domain decides.
8. **omnet-julia**: NED and INI state their breaks in their texts, which removes
   their empty lines. It follows the landing of steps 2 to 4.
9. **The documents**: `text.md`, `syntax.md` and the guides of the domains.
