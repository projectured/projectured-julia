# Copy and paste text with the system clipboard

**Status (2026-09-17): NOT STARTED.** No code changed yet.

**Start it only after** [select-a-widget-and-paste-it-into-a-tab.md](select-a-widget-and-paste-it-into-a-tab.md)
is done and on `main`. This plan builds on its paste rules (D9), on its reading
of the selection (D10), on `reroot_operation` (D11), and on the clipboard layer
that its step 6 puts into the omnet IDE.

**Goal:** a person copies text in another program, puts the text cursor into a
string in ProjecturEd, and presses `Ctrl+V`. The text goes in at the cursor. That
string can be the chat draft of the omnet IDE, a field of the runner, or a string
of any domain. A range cursor works too when its map is trivial: `Ctrl+V`
replaces the range, and `Ctrl+C` or `Ctrl+N` put the range on the system
clipboard. Every other case is deferred.

**Repositories:** projectured-julia (the domain, clipboard and conversation
slices) and omnet-julia (one end-to-end test). The plan changes no sealed file.

## 1. The request and the rulings

> tell me how would a text copy-paste work. For example, the user wants to
> copy-paste from an external text editor into the text draft in the
> conversation panel. […] I thought it's pretty simple, the clipboard sees the
> selection path pointing into a string, so it simply produces a replace range
> operation with the text from the OS clipboard. It works the other way around
> too

> we should defer the hard parts, we can easily support copy-paste from external
> source to a text cursor. extending to a range cursor is easy if the structural
> map is trivial, otherwise we should defer it, let's make a plan that should be
> executed after the other plan finishes

The words mean this in the code:

| Word | Meaning |
| --- | --- |
| system clipboard | the clipboard of the operating system: `read_os_clipboard` and `write_os_clipboard!`, which run `xclip`, `xsel`, `wl-paste` / `wl-copy` or `pbpaste` / `pbcopy` |
| text cursor | a selection whose last two steps are a field `f` and a range `{k..k}`, where the field holds a string |
| range cursor | the same with a range `{s..e}` and `s < e` |
| trivial map | the range lies in one field of one document, and the field's value is a `String`, `nothing` or a `Number`: the representations the kernel's own `splice_value!` methods cover. The text of the range is the characters `s+1` to `e` of that value |
| text target | a text cursor or a range cursor with a trivial map |

## 2. What exists

| Fact | Where |
| --- | --- |
| `ReplaceStringRangeOperation(reference, text)` splits its path into a document, a field and a range, splices with `splice_value!`, and moves the caret to `s + length(text)` along the whole path. | [PrimitiveDocument.jl:109](../../source/primitive/PrimitiveDocument.jl#L109), its `evaluate_operation` below it |
| `splice_value!` covers `String`, `nothing` and `Number` in the kernel, and `TextString` and `TextBlock` in the text slice. A number is spliced as text and parsed again. | [Operations.jl:83-92](../../source/kernel/operation/Operations.jl#L83-L92), [TextDocument.jl:308-316](../../source/text/TextDocument.jl#L308-L316) |
| A typed character in a `PrimitiveString` IS that operation. The table reads the range from the document's own selection (`_string_value_range`). Backspace already deletes a non-empty range. | [PrimitiveToText.jl:182](../../source/text/PrimitiveToText.jl#L182) |
| No gesture makes a range cursor. The string table and the `TextBlock` table have no Shift and arrow, and nothing selects characters by a drag or a double click. | same, and [TextDocument.jl:335](../../source/text/TextDocument.jl#L335) |
| The chat draft is `ConversationDraft([ConversationPart(PrimitiveString(""))])`. The composer does not use `ReplaceStringRangeOperation`: `ComposerInputOperation` splices the value and moves only the caret in the string's own selection cell. | [AssistantDocument.jl:101](../../source/assistant/AssistantDocument.jl#L101), [ConversationEditor.jl:173](../../source/conversation/ConversationEditor.jl#L173) |
| **The two carets differ.** Measured 2026-09-17 in the omnet IDE, headless: after a click into the draft and the keys `h`, `i`, the window's path and the pane tree's path end in `value{0}`, and the string's own cell holds `value{2}`. | a probe script, repeated in step 0 |
| A key reaches the draft only when the selection is inside the assistant pane. Measured: with no click, `h`, `i` make no operation, with and without the runner's startup focus. | same probe |
| The composer has no `Ctrl+V`. Its table has insert, Backspace, Return, Shift+Return, Tab, Insert and Escape. | `_composer_bindings`, [ConversationEditor.jl](../../source/conversation/ConversationEditor.jl) |
| The other plan's D9 rule 1 says "the composer's own `Ctrl+V` pastes text", and its step 7 tests "`Ctrl+V` with the caret in the composer pastes text". No step of it adds that paste. **This plan supplies it.** | the other plan, D9 and step 7 |
| `accepts_pasted_document` refuses the `Assistant` and the `SimulationFilter`, which hold the draft and the runner's fields. A text paste must therefore not ask it. | the other plan, D9 |
| The system clipboard has a test seam: `set_os_clipboard_backend!(read, write)`. `WriteOsClipboardOperation(text)` writes at evaluation. | [Clipboard.jl](../../source/clipboard/Clipboard.jl) |
| The existing text mode (`text = true`) acts only when the slice's whole content is one `TextBlock`, and uses `TextBlock` helpers. The gallery turns it on for the text examples. | `_text_clipboard_*` in [ClipboardSliceToAny.jl](../../source/clipboard/ClipboardSliceToAny.jl) |

## 3. Decisions

The decisions are numbered T1 to T11, so that they do not mix with the D numbers
of the other plan.

### T1. The clipboard makes the text edit

At a text target, a paste answers `ReplaceStringRangeOperation(path, text)`,
rooted at the content and re-rooted with `reroot_operation`. It is the operation
that typing makes, so the kernel applies it the same way in every domain, and the
caret moves to the end of the pasted text.

### T2. What a text target is

The clipboard's selection (the other plan's D10) ends in a `FieldReferenceStep(f)`
and a `RangeReferenceStep`. The prefix names a document `D`, and `D.f` holds a
`String`, `nothing` or a `Number`. Type checkpoints on the path are ignored. Any
other selection is not a text target and goes to the rules of D9 as before.

### T3. The caret comes from the document that holds the string

When `D`'s own selection cell names `f{s..e}`, the paste uses that range.
Otherwise it uses the range at the end of the clipboard's path.

**Why:** the composer moves only the cell of its string (§2, the two carets).
The path still names the caret of the click, and a paste there would go to the
wrong place. `@gestures PrimitiveString` reads the same cell for the same reason.

### T4. Where the pasted text comes from

At a text target, the text comes from the system clipboard. When that gives
nothing (no tool, or an empty clipboard), the text comes from the slice when the
slice holds a `PrimitiveString` or a `TextString`. Otherwise the paste is refused.

**Why:** the last copy wins, in whichever program it was made. A person who copies
in ProjecturEd and then in an editor wants the editor's text. A copy in
ProjecturEd also writes the system clipboard (T5), so the order stays true.

### T5. What a copy and a note of a range store

A copy or a note of a range cursor writes the text to the system clipboard,
stores `PrimitiveString(text)` in the slice, and puts the selection back where
it was. A text cursor has nothing to copy: the gesture goes on, and the rules of
D9 then refuse it, because a caret is not a whole element.

`PrimitiveString` and not `TextString`, because a pasted object goes into a tab,
and the IDE draws a primitive as text.

### T6. A cut of a range

Where `:cut` is offered, a cut of a range cursor does what T5 does, and also
answers `ReplaceStringRangeOperation(path, "")`. The IDE does not offer `:cut`.

### T7. The text branch comes first

The clipboard asks T2 before the rules of D9. A text target never reaches the
whole-document rules, and a whole-element selection never reaches the text
branch. Rule 1 of D9 ("not a caret and not a range") stays true for what reaches
it.

### T8. A document can refuse pasted text

A new predicate `accepts_pasted_text(document)` goes into `ProjecturedDomain`,
beside `accepts_pasted_document`. It answers `true` by default. A text paste,
copy or cut is refused unless every document from the content down to `D`
answers `true`.

| Document | Answer | Why |
| --- | --- | --- |
| `ConversationConversation` | `false` | the history is a record |
| `Assistant` | `true` (default) | a person types into its draft |
| `SimulationFilter` | `true` (default) | a person types into its fields |

**Why a second predicate:** the clipboard writes above the readers (D9 says why),
so a read-only reader can not refuse the edit. `accepts_pasted_document` is the
wrong question: it refuses the two panes that a person types into.

### T9. Line breaks

A text pasted into a string that holds no line break loses its trailing line
breaks. Every other line break stays.

**Why:** a line copied from an editor often ends in a line break, and a runner
parameter must not end in one. A rule per field ("this field takes one line")
needs a declaration that no domain has, so it is deferred.

### T10. A number

A paste into a number field is refused when the result is not empty and does not
parse (`splice_number` answers `nothing`). A copy of a range of a number copies
the characters of its text.

### T11. On by default

The text branch has no keyword: a string takes a string. `offered_gestures` still
decides which keys the clipboard answers. The `text = true` mode for a whole
`TextBlock` stays as it is.

## 4. Deferred

These are the hard parts, and none of them is in this plan:

- **A range with a map that is not trivial:** a range over several spans of a
  `TextBlock`, a range across a line break, a range that crosses documents, and a
  reference that a projection introduced. A `TextBlock` or `TextString` inside a
  document is deferred as a whole, because its copy needs the span map.
- **A gesture that makes a range cursor:** Shift and an arrow, a drag, a double
  click, in a string field and in the composer. Until one exists, the tests set
  a range selection by hand.
- **A key that reaches a document without a selection in it.** The paste goes
  where the selection is.
- **The composer's two carets.** T3 reads the right one. Making the composer's
  own edits move the whole path is a separate change.
- **A one-line rule per field** (T9).
- **A text form of a structured object**, such as a table as tab-separated text.
  The other plan puts it out of scope too; `to_text` makes it possible later.
- **Rich text** (HTML) from the system clipboard.
- **A slow clipboard tool.** `read_os_clipboard` runs a process on the drawing
  thread. Step 3 measures one call. If it is slow, an asynchronous read is a
  separate change.

## 5. Steps

### Step 0 — baselines and probes

- [ ] The other plan is in `plan/done/` and its branch is on `main`.
- [ ] Record the counts on `main`: `test_clipboard()`, `test_gesture_help()`,
      `test_command_palette_decorator()`, and in omnet-julia
      `test_ide_window_wrap()` and the other plan's `test_select_and_paste()`.
      Write down which of its assertions fail, the composer paste of step 7 among
      them.
- [ ] Read D9, D10 and D11 as they landed, and the code of
      `_get_clipboard_selection` and `_find_paste_target`. If they differ from §2,
      correct §2 and the decisions first.
- [ ] Repeat the probe of §2 in the IDE: a click into the draft, then `h`, `i`.
      Compare the caret of the path with the caret in the string's own cell. If
      the two now agree, T3 stays, and the plan says so.
- [ ] Check whether the other plan added a `Ctrl+V` to the composer. If it did,
      decide with the user which of the two answers a caret in the draft.

### Step 1 — `accepts_pasted_text` (projectured, domain and conversation slices)

- [ ] The predicate in `ProjecturedDomain`, beside `accepts_pasted_document` (T8).
- [ ] `accepts_pasted_text(::ConversationConversation) = false`.
- [ ] Tests: the default, and the conversation.

### Step 2 — the text branch (projectured, clipboard slice)

- [ ] Find a text target (T2), and its range (T3).
- [ ] Paste and paste-copy at a text target (T1, T4, T9, T10), before the rules of
      D9 (T7), refused by T8.
- [ ] Copy and note of a range cursor (T5), and cut (T6).
- [ ] Tests in `test_clipboard()`, with the in-memory system clipboard of
      `set_os_clipboard_backend!`:
      - a text cursor in a `PrimitiveString` takes the text, and the caret moves
        to its end;
      - **the composer case:** the path names one caret and the string's own
        cell another, and the paste goes to the own cell's caret;
      - a range cursor is replaced;
      - a copy and a note of a range write the system clipboard and the slice,
        and the selection stays;
      - a copy at a text cursor goes on, and changes nothing;
      - a cut of a range, where `:cut` is offered;
      - a JSON string of the gallery's JSON example takes a paste at its cursor;
      - a number field takes digits and refuses letters;
      - a trailing line break is dropped in a one-line string and kept in a
        string that holds a line break;
      - a string inside a `ConversationConversation` refuses;
      - with no system clipboard, a text slice is pasted, and any other slice is
        refused;
      - a whole-element selection still goes through D9: every count of the
        other plan's tests stays the same.

### Step 3 — the chat draft and the runner in the IDE (omnet)

- [ ] A test in `test/ide/`, through the real editor loop, with the in-memory
      system clipboard:
      - a click into the draft, then `a`, `b`, then `Ctrl+V` of `"xyz\n"`: the
        draft holds `"abxyz"`;
      - then `!`: the draft holds `"abxyz!"`. This proves that the composer reads
        the caret that the paste left;
      - a click into a text field of the runner, then `Ctrl+V`: the field holds
        the text, and no run starts;
      - `Ctrl+V` with nothing in the system clipboard and nothing in the slice
        changes nothing.
- [ ] The other plan's step 7 assertion "`Ctrl+V` with the caret in the composer
      pastes text" passes.
- [ ] Measure one real `read_os_clipboard` call on this machine, and write the
      time here.

### Step 4 — guides, and close

- [ ] The guide that the other plan wrote for the clipboard says how a text paste
      and a text copy work, and what is deferred. If there is none, a section in
      [operation.md](../../documentation/package/kernel/operation.md) beside
      `ReplaceStringRangeOperation`.
- [ ] The omnet runner guide says that `Ctrl+V` pastes text at a text cursor.
- [ ] Move this plan to `plan/done/`.

## 6. Risks

- **The other plan changes before it lands.** Step 0 reads D9, D10 and D11 as
  they are, and corrects this plan first.
- **The composer reads a canonical caret badly.** After a paste, the kernel writes
  a path with type checkpoints into the string's cell. `_cursor` reads a plain
  `value{k}`. If it does not read the canonical form, the next typed character
  goes to the end. Step 3 types after a paste to find out.
- **The key does not reach the clipboard.** `Ctrl+V` must reach the clipboard
  layer before the assistant panel sends it to the composer, which ignores it.
  Step 3 tests the real chain.
- **A refused paste says nothing.** An empty system clipboard, or a missing tool,
  makes `Ctrl+V` do nothing, and the person is not told why.
