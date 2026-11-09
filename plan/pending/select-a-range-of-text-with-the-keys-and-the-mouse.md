# Select a range of text with the keys and the mouse

**Status (2026-11-09): IN PROGRESS.** The owner approved the plan for
implementation on 2026-11-09, so D1 to D7 are approved with the plan. The owner
answered Q1. The work is on the branch `text-range`, in the worktree
`projectured-julia-text-range`.

**Goal:** a person selects a range of characters in any text that the editor
shows: a plain text file, a string of a form, the chat draft, a finished message
of the assistant, and a string, a number or a name in a syntax domain (JSON, SQL,
Julia, XML, YAML, Markdown and the others). The keys and the mouse both select. The
caret is drawn at the end that moves, and the opposite `Shift` key makes the range
smaller. A range that crosses a structural boundary declines, as it does now.

**Repository:** projectured-julia. No file that the plan changes is sealed (the
reference layer, `ProjectionTemplate.jl` and the platform are all ⬜ in
[SEALING.md](../../SEALING.md)).

## 1. The request and the rulings

> I would like to have basic string/text range selection in projectured-julia
> […] it's ok if the range selection is not supported when it crosses structural
> boundaries like in a large JSON document

> kinda works in a __TODO file but there's no cursor at either ends

To the question "a quick fix that always draws the caret at the right end, or a
correct fix where the selection records which end moves, with a plan first", the
owner answered:

> yes, with a plan first
>
> also, I would expect that range selection also works with the mouse
>
> and also works for example in the assistant conversation, but it does not
>
> if the text domain supports range selection the backward mapping should be
> enough if the range maps to a single part in the structure, no?

So the owner decided (2026-11-09): the selection records which end moves; the
mouse selects a range; a range works in the assistant conversation; a range that
crosses a structural boundary may decline.

The words mean this in the plan:

| Word | Meaning |
| --- | --- |
| range | a selection `{s:e}` with `s < e`, in flat characters of a text or in characters of a field of a document |
| caret | a range with `s == e` |
| anchor | the end of a range that stays when a `Shift` key or a drag moves the other end |
| moving end | the end of a range that a `Shift` key or a drag moves; the caret is drawn there |
| direction | `:forward` when the moving end is `stop`, `:backward` when it is `start` |
| part | one field of one document whose value is a `String`, `nothing` or a `Number`: the place where a range edit splices |

## 2. What exists

| Fact | Where |
| --- | --- |
| A range is `RangeReferenceStep(start, stop)` in the kernel and `TextRangeReferenceStep(start, stop)` in the text slice, always with `start <= stop`. Nothing records which end moves. | [ReferenceStep.jl:26](../../source/kernel/reference/ReferenceStep.jl#L26), [TextRangeReferenceStep.jl:37](../../source/platform/text/TextRangeReferenceStep.jl#L37) |
| `Shift` and a motion key move a fixed end: the left, word-left and start keys move `start`, the others move `stop`. So a range never gets smaller. | `_text_extend`, [TextDocument.jl:1214](../../source/platform/text/TextDocument.jl#L1214); `Shift+Home/End/Up/Down` in [TextToGraphics.jl:362](../../source/platform/text/TextToGraphics.jl#L362) |
| A range has no caret: `get_flat_cursor_coordinate` answers `nothing` for it. The line motion reads the same function, so a plain `Up` or `Down` does nothing while a range is selected. | [TextDocument.jl:1054](../../source/platform/text/TextDocument.jl#L1054), [TextToGraphics.jl:372](../../source/platform/text/TextToGraphics.jl#L372) |
| A range is painted row by row, ragged on the first and last row. | `_compute_span_rows`, [TextToGraphics.jl:1119](../../source/platform/text/TextToGraphics.jl#L1119) |
| The maps that carry a range now: the plain string, the word wrapping (as is), the text drawing, the object field, the text widget, the chat draft, the marked text and the line numbers. | [PrimitiveToText.jl:14](../../source/platform/text/PrimitiveToText.jl#L14), [ObjectFieldToValue.jl:47](../../source/platform/widget/ObjectFieldToValue.jl#L47), [WidgetToGraphics.jl:2146](../../source/platform/widget/WidgetToGraphics.jl#L2146), [ConversationEditor.jl:612](../../source/platform/conversation/ConversationEditor.jl#L612), [MarkedTextToText.jl:52](../../source/platform/text/MarkedTextToText.jl#L52), [TextLineNumbering.jl:129](../../source/platform/text/TextLineNumbering.jl#L129) |
| The syntax layer maps a caret as one flat offset. Its backward maps refuse a range, and its forward maps read only the start. Every syntax domain goes through it. | `_is_flat_text_range` at [SyntaxToText.jl:76](../../source/platform/syntax/SyntaxToText.jl#L76), [:562](../../source/platform/syntax/SyntaxToText.jl#L562), [:1858](../../source/platform/syntax/SyntaxToText.jl#L1858); forward `value{s:_}` at [:63](../../source/platform/syntax/SyntaxToText.jl#L63) |
| The step from a domain to the syntax tree copies the whole range step, both ends. It needs no change. | `_map_forward` and `_map_backward` of `AtomicWiring`, [ProjectionTemplate.jl:853](../../source/kernel/projection/ProjectionTemplate.jl#L853) |
| A finished message of the assistant is a `MarkdownRoot`, drawn through the syntax layer, so it refuses a range. A message that still streams is a `PrimitiveString` and takes one. | `parse_markdown_blocks`, [AssistantTurn.jl:1199](../../source/platform/assistant/AssistantTurn.jl#L1199); `MarkdownStyledTextToSyntaxLeaf`, [MarkdownToSyntax.jl:270](../../source/domain/markdown/MarkdownToSyntax.jl#L270) |
| In Markdown each run of a paragraph is its own document: plain text, `**strong**`, `*emphasis*` and `` `code` `` are separate `MarkdownText` or `MarkdownCode` parts. | [MarkdownDocument.jl:38-116](../../source/domain/markdown/MarkdownDocument.jl#L38-L116) |
| A click puts a caret on `MouseClick`, which the gesture tracker makes on the release. `MouseClick` has `count`: 1, 2 or 3. Nothing in the text reads `MouseDown`, the count or `Shift`. | [TextToGraphics.jl:313](../../source/platform/text/TextToGraphics.jl#L313), [MouseGesture.jl:19](../../source/kernel/gesture/MouseGesture.jl#L19) |
| A part takes the pointer for a drag with `StartDragOperation(path, dragged)`. `DragTrackingProjection` then sends `DragMove`, `DragEnd` and `DragCancel` to that path, in the frame of the part, wherever the pointer is. A `MouseClick` while the drag is on goes nowhere. The splitter, the scroll bar and the graph use it. | [Operations.jl:266](../../source/kernel/operation/Operations.jl#L266), [DragTracking.jl:56](../../source/platform/dragtracking/DragTracking.jl#L56) |
| `Alt` and a click select a whole part; in text the syntax layer decides it. | `is_whole_selection_press`, [WholeSelection.jl:17](../../source/platform/focus/WholeSelection.jl#L17); [SyntaxToText.jl:183](../../source/platform/syntax/SyntaxToText.jl#L183) |

## 3. Decisions

### D1. The range step records its direction (proposed by the assistant, approved with the plan 2026-11-09)

`RangeReferenceStep` and `TextRangeReferenceStep` get a third field, `direction`,
with the value `:forward` (the default: `stop` moves) or `:backward` (`start`
moves). `start <= stop` stays true, so every reader that reads the two ends reads
them as now. A caret is always `:forward`. Equality and the hash include the
direction, because a selection that changes only its direction changes what the
screen shows. The name follows the `direction` of a selection in a web browser.

Rejected:

- **A reversed pair, `start > stop`.** The clipboard plan rejected it in its step
  0: many readers, the readers of list ranges among them, read the two ends in
  order.
- **A field of the selection document at the root.** The text layer reads its
  selection as a reference that each projection maps forward. A field outside the
  reference needs a second way to reach the text layer.
- **A separate step type for a backward range.** Each pattern and each reader of a
  range would need two cases.

### D2. The text form of a backward range (proposed by the assistant, approved with the plan 2026-11-09)

A backward range prints and parses as its anchor first: `{5:3}` is
`start = 3, stop = 5, direction = :backward`. A forward range prints as now. A
backward range of one character prints `{5:4}`, not `[5]`. A pattern `{s:e}` in
`@reference_case` binds `s = start` and `e = stop` as now, so no existing pattern
changes its meaning.

### D3. A map carries the direction, and maps a range by its characters (proposed by the assistant, approved with the plan 2026-11-09)

A map that builds a range from the numbers of another range copies its direction.
`make_flat_range_reference(start, stop; direction)` takes it, and
`get_range_direction(reference)` reads it. A map that passes a reference on or adds
steps before it needs no change.

A map that must find the part of a range maps the first character, `start`, and
the last character, `stop - 1`, each as one character. The range maps when both
characters are in the same part, and declines otherwise. A caret maps as now. The
reason: a caret at the border of two parts, such as the end of a string and its
closing quote, belongs to both, but a character belongs to one.

To the owner's question: yes, the rule is that simple. But the backward map alone is
not enough. The selection is kept at the root, and each print maps it forward to
the text again, so the text can draw it and the next key can move it. The forward
maps of the syntax layer read only the start now. So both directions get the same
rule.

### D4. The keys move the moving end (proposed by the assistant, approved with the plan 2026-11-09)

- A `Shift` key moves the moving end. When the moving end passes the anchor, the
  direction changes. From a caret, the direction of the key gives the direction of
  the range.
- `Left` and `Right` without `Shift` collapse the range to its near end, as now.
- `Up`, `Down`, `Home` and `End` without `Shift` move from the moving end and
  collapse the range.

### D5. The caret is drawn at the moving end (proposed by the assistant, approved with the plan 2026-11-09)

A range draws its highlight and a caret at its moving end, in the live or the
dormant colour, as a caret does now.

### D6. The mouse (proposed by the assistant, approved with the plan 2026-11-09)

- A left press without a modifier puts the caret at the point and starts a drag of
  the text, by `StartDragOperation`. The press point is the anchor.
- Each `DragMove` moves the moving end to the character nearest to the point. A
  point above the text gives its start, and a point below it gives its end.
- `DragEnd` keeps the range. `DragCancel` (`Escape`) keeps it too.
- `Shift` and a left press move the moving end to the point and keep the anchor. A
  drag after it goes on from that anchor.
- A double click selects the word at the point, by the word class of
  `Ctrl+Left` and `Ctrl+Right`. A triple click selects the line.
- `Alt` and a press select a whole part, as now; it starts no drag.
- A press inside a range starts a new selection. It does not drag the selected text.

The press now puts the caret, not the release. Every other mouse use of the text
stays.

### D7. One change in the syntax layer covers every syntax domain (proposed by the assistant, approved with the plan 2026-11-09)

`SyntaxLeafToText`, `SyntaxCompoundToText` and `SyntaxListToText` map a range in
both directions by D3. The step from a domain to the syntax tree carries the whole
range step already (§2). So JSON, SQL, Julia, XML, YAML, Markdown, RST, the book,
the formula, the FSM, the math, the process and the database catalog all take a
range in one string, number or name, and so does a finished message of the
assistant.

### Q1. A range across the runs of a Markdown paragraph (answered by the owner, 2026-11-09)

A paragraph of an assistant message often holds a `` `code` `` word or a
`**strong**` word. Each run is its own part (§2). By D3, a range from plain text into
a code word declines. Is that acceptable for this plan, or must a range in the
conversation cross the runs of one paragraph?

My recommendation was to accept it in this plan: a range across runs needs a range
that starts in one part and stops in another, which is a new kind of reference.

The owner: "yes, acceptable for now". So a range in an assistant message stays in
one run, and a range across runs declines.

## 4. Steps

Each step is one commit on a branch in a worktree. The narrowest test runs after
each step, with `workspace/bin/bounded-run`.

### Step 0 — baselines and probes

- [ ] Baseline counts on the branch point: `test_text()`, `test_text_to_graphics()`,
      `test_primitive_to_text()`, `test_word_wrapping()`,
      `test_text_range_selection()`, `test_syntax()`, `test_json()`,
      `test_markdown()`, `test_conversation_transcript()`, `test_clipboard()`, and
      the reference tests of `test_kernel()`.
- [ ] Probe: a press with no move, and a double click, while a drag of the text is
      on. Does the `MouseClick` with its `count` reach the text after `DragEnd`?
      Record the answer here; step 5 depends on it.
- [ ] Probe: a `MouseDown` in a text reaches `TextToGraphics` in a file tab, in a
      JSON tab, in an assistant message and in the cached canvas path
      (`GraphicsCanvasToGraphicsImage`).
- [ ] Probe: a caret after an escape in a JSON string (`"a\nb"`). Record whether
      the offset in the value is correct. A wrong offset is a fault of the caret
      that this plan does not change.

### Step 1 — the direction of a range (kernel reference layer, text slice)

- [ ] D1 and D2: the field, the constructors, `show`, the parser of `@reference`,
      equality and hash, `get_range_direction`, and
      `make_flat_range_reference(…; direction)`.
- [ ] Tests: a backward range prints and parses back; a pattern `{s:e}` binds the
      ordered ends; a forward and a backward range are not equal.

### Step 2 — every map keeps the direction (text, primitive, widget, conversation slices)

- [ ] D3 in each map that builds a range from numbers: the plain string, the object
      field, the text widget, the chat draft, the marked text and the text drawing.
- [ ] Tests: a backward range maps forward and back unchanged in each.

### Step 3 — the keys and the caret (text slice)

- [ ] D4 in `_text_extend` and in the geometry keys of `TextToGraphics`.
- [ ] D5: `get_flat_cursor_coordinate` answers the moving end, and the overlay draws
      it.
- [ ] Tests: `test_text()` (a range that grows, shrinks and changes direction;
      `Up` and `Down` from a range); `test_text_to_graphics()` (the caret at each
      end); `test_text_range_selection()` (a range made with `Shift+Left` gets
      smaller with `Shift+Right`, through the editor loop).

### Step 4 — the syntax layer maps a range (syntax slice)

- [ ] D3 and D7 in `SyntaxLeafToText`, `SyntaxCompoundToText` and
      `SyntaxListToText`; `_is_flat_text_range` goes.
- [ ] Tests: the JSON case of `test_text_range_selection()` changes from "declines"
      to "selects": `Shift+Left` in a JSON string makes a range, a typed key
      replaces it, and `Ctrl+C` copies it. A range from one string to the next
      declines. One test in a second domain (a SQL name). A range in a paragraph of
      a finished assistant message, through the editor loop.

### Step 5 — the mouse (text slice)

- [ ] D6 in `TextToGraphics`: the press, the drag, `Shift` and a press, the double
      and the triple click, also on the cached canvas path.
- [ ] Tests through the editor loop with real pixels: a drag in a plain text file
      over two lines, a drag in a JSON string, a drag outside the text, `Shift` and
      a press, a double and a triple click, an `Alt` press that still selects a
      whole part, and a drag in an assistant message.

### Step 6 — documentation and the old plans

- [ ] [selection.md](../../documentation/package/kernel/selection.md),
      [reference.md](../../documentation/package/kernel/reference.md) and the text
      and syntax documents in [documentation/package/platform/](../../documentation/package/platform/)
      say what a range is and how it maps.
- [ ] Section 1 of [syntax-tree-selection.md](syntax-tree-selection.md) points
      here for the range of characters; the range of sibling nodes stays there.
- [ ] The plan moves to `plan/done/`.

**Not in this plan:** a range across parts (Q1, if accepted), a range of sibling
nodes, the column selection, a drag that moves selected text, a drag by words
after a double click, and a scroll while a drag passes the edge of a scroll area.
