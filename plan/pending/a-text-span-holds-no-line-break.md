# A text span holds no line break

> **Kind:** plan · **Status:** pending, 2026-10-08. The owner decided the rule
> (§1) on 2026-10-08. The questions of §7 are open, and no step is started. ·
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
   goes on its last line.
5. A delimiter or a separator of many lines is a block of lines, or the chrome
   puts it on a line of its own (§7, N3).
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
- **N1b The shared helper and the edit of a line.** Every domain stage needs the
  same conversion of a string into styled lines, as `make_hinted_text` makes a
  styled run today, and an edit of a line must map back to an offset in the
  string, as `bound(...)` maps an edit of one run today. Open.
- **N1c A text document in a field.** What the recursion of the domain-to-syntax
  stage does with a text document that a field holds. Open.
- **N2 A child on each line.** What replaces `sep = TextString("\n")`: a compound
  that puts each child on a line of its own with no indentation, through the
  `indentation` that exists or a new field.
- **N3 A delimiter of many lines.** A block of lines as the delimiter, or the
  chrome of the compound puts it on lines.
- **N4 The edit of a break in a `String`.** Enter in a field that a
  `StringToTextBlock` prints splits a line of its output; its reader maps that to
  an insertion of `'\n'` into the string. Backspace at the start of a line is the
  deletion of that `'\n'`.
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
