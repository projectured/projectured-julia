# Copy and paste text with the system clipboard

**Status (2026-09-17): IN PROGRESS** in the worktree `projectured-julia-text-clipboard`
(branch `text-clipboard`). Step 0 is done.

**Start it only after** [select-a-widget-and-paste-it-into-a-tab.md](select-a-widget-and-paste-it-into-a-tab.md)
is done and on `main`. This plan builds on its paste rules (D9), on its reading
of the selection (D10), on `reroot_operation` (D11), and on the clipboard layer
that its step 6 puts into the omnet IDE.

**Goal:** a person copies text in another program, puts the text cursor into a
string in ProjecturEd, and presses `Ctrl+V`. The text goes in at the cursor. That
string can be the chat draft of the omnet IDE, a field of the runner, or a string
of any domain. `Shift` and the arrow keys select a range of characters wherever
a projection maps the range trivially. `Ctrl+V` replaces a range, and `Ctrl+C` or
`Ctrl+N` put a range on the system clipboard. The chat draft keeps one selection:
the complete path from the root. Every other case is deferred.

**Repositories:** projectured-julia (the domain, text, conversation and clipboard
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

> the conversation draft composer should be selected with a complete path from
> the root when I click there, there should not be two different selection (one
> local and one global) after a click, the click leaves detached trails as it did
> before, but the key cursor events goes to where the complete selection points
> from the root
>
> we can also support shift+cursor keys in the text domain, so any projection
> which can map a trivial range (no cross-span or cross document range) works

The words mean this in the code:

| Word | Meaning |
| --- | --- |
| system clipboard | the clipboard of the operating system: `read_os_clipboard` and `write_os_clipboard!`, which run `xclip`, `xsel`, `wl-paste` / `wl-copy` or `pbpaste` / `pbcopy` |
| complete selection | the selection path from the editor's root document down to the target, `ScreenDocument.windows[1].content…value{s..e}` |
| trail | the suffix of the complete selection that a document on the path holds in its own `selection` cell. A click writes every trail, as it does today |
| text cursor | a complete selection whose last two steps are a field `f` and a range `{k..k}`, where the field holds a string |
| range cursor | the same with a range `{s..e}` and `s < e` |
| trivial map | the range lies in one span of the text layer, and maps to one field of one document whose value is a `String`, `nothing` or a `Number`. A range across spans, across a line break, or across documents is not trivial |
| text target | a text cursor, or a range cursor with a trivial map |

## 2. What exists

### The kernel and the text domain

| Fact | Where |
| --- | --- |
| `ReplaceStringRangeOperation(reference, text)` splits its path into a document, a field and a range, splices with `splice_value!`, and moves the caret to `s + length(text)` along the whole path, which writes every trail. | [PrimitiveDocument.jl:109](../../source/primitive/PrimitiveDocument.jl#L109), its `evaluate_operation` below it |
| `splice_value!` covers `String`, `nothing` and `Number` in the kernel, and `TextString` and `TextBlock` in the text slice. A number is spliced as text and parsed again. | [Operations.jl:83-92](../../source/kernel/operation/Operations.jl#L83-L92), [TextDocument.jl:308-316](../../source/text/TextDocument.jl#L308-L316) |
| A typed character in a `PrimitiveString` IS that operation. The table reads the range from the string's trail (`_string_value_range`). Backspace already deletes a non-empty range. | `@gestures PrimitiveString`, [PrimitiveToText.jl:182](../../source/text/PrimitiveToText.jl#L182) |
| The text domain edits a flat character range. A typed character replaces the range, Backspace and Delete remove it, and a plain arrow collapses it to its near end. | `@gestures TextBlock`, `_text_insert`, `_text_delete`, `_text_char_motion`, [TextDocument.jl:353-594](../../source/text/TextDocument.jl#L353-L594) |
| The text edit is `ReplaceTextRangeOperation` in flat coordinates, lowered to a span or domain edit on its way up. **A range that crosses a span boundary declines when it is lowered.** That is the trivial-map rule, already in the code. | `_text_insert` and the comment on `_text_delete` |
| **No gesture selects a range.** Neither table has `Shift` and an arrow. The geometry keys (plain `Home` / `End`, `Up` / `Down`) are in `TextToGraphics`, without `Shift` too. | [TextDocument.jl:353](../../source/text/TextDocument.jl#L353), [TextToGraphics.jl:133-170](../../source/text/TextToGraphics.jl#L133-L170) |
| `TextToGraphics` draws a non-empty range as highlight rectangles. | [TextToGraphics.jl:285-310](../../source/text/TextToGraphics.jl#L285-L310) |
| A widget container sends a key to the child that its selection names. | `_forward_composite_event_slot`, [WidgetToGraphics.jl:1950](../../source/widget/WidgetToGraphics.jl#L1950) |

### The chat draft

| Fact | Where |
| --- | --- |
| The draft is `ConversationDraft([ConversationPart(PrimitiveString(""))])`. | [AssistantDocument.jl:101](../../source/assistant/AssistantDocument.jl#L101) |
| The composer draws the editable string as a `TextBlock` that it builds itself. The caret of that block is computed from `_cursor(content)`, which reads the string's own trail. | `_editable_body`, `_attach_caret!`, [ConversationEditor.jl:383-450](../../source/conversation/ConversationEditor.jl#L383-L450) |
| A click in the draft's text is answered by the text layer, and the composer's `map_reference_backward` turns it into `parts[i].content.value{k}`. **Both maps carry only a caret**: a range from the text layer becomes its end, and a range in the draft is drawn as a caret. | `map_reference_forward` and `map_reference_backward`, [ConversationEditor.jl:519-575](../../source/conversation/ConversationEditor.jl#L519-L575) |
| A typed key does not go to the text layer. The composer's own table answers it with `ComposerInputOperation`, `ComposerBackspaceOperation` or `ComposerNewlineOperation`. They splice the value and move the caret in the string's own trail only (`_set_value!`), and the table does not read the selection at all. The comment says the enclosing card drops key events so that the text layer does not take them. | `_composer_bindings`, [ConversationEditor.jl:173-200](../../source/conversation/ConversationEditor.jl#L173-L200), [ConversationEditor.jl:400](../../source/conversation/ConversationEditor.jl#L400) |
| **So there are two selections today.** Measured 2026-09-17 in the omnet IDE, headless: after a click into the draft and the keys `h`, `i`, the root's path and the pane tree's trail end in `value{0}`, and the string's own trail holds `value{2}`. | a probe script, repeated in step 0 |
| When nothing below it takes a key, `AssistantToWidgetSplitPane` sends the key to the draft, whatever the selection is. At the window level a key reaches the assistant pane only when the selection is in it: with no click, `h`, `i` make no operation. | [AssistantTurn.jl:915-930](../../source/assistant/AssistantTurn.jl#L915-L930), the same probe |
| The composer has no `Ctrl+V`, no arrow key, and no `Shift`. | `_composer_bindings` |

### The clipboard

| Fact | Where |
| --- | --- |
| The other plan's D9 rule 1 says "the composer's own `Ctrl+V` pastes text", and its step 7 tests "`Ctrl+V` with the caret in the composer pastes text". No step of it adds that paste. **This plan supplies it.** | the other plan, D9 and step 7 |
| `accepts_pasted_document` refuses the `Assistant` and the `SimulationFilter`, which hold the draft and the runner's fields. A text paste must therefore not ask it. | the other plan, D9 |
| The system clipboard has a test seam, `set_os_clipboard_backend!(read, write)`. `WriteOsClipboardOperation(text)` writes at evaluation. | [Clipboard.jl](../../source/clipboard/Clipboard.jl) |
| The existing text mode (`text = true`) acts only when the slice's whole content is one `TextBlock`, and uses `TextBlock` helpers. The gallery turns it on for the text examples. | `_text_clipboard_*`, [ClipboardSliceToAny.jl](../../source/clipboard/ClipboardSliceToAny.jl) |

## 3. Decisions

The decisions are numbered T1 to T14, so that they do not mix with the D numbers
of the other plan.

### The text domain

#### T1. `Shift` and a motion key extend the selection

Every motion key of the text domain gets a `Shift` twin that moves one end of the
range and keeps the other:

| Key | Moves the moving end | Table |
| --- | --- | --- |
| `Shift+Left`, `Shift+Right` | by one character | `@gestures TextBlock` |
| `Shift+Ctrl+Left`, `Shift+Ctrl+Right` | by one word | `@gestures TextBlock` |
| `Shift+Ctrl+Home`, `Shift+Ctrl+End` | to the start or the end of the text | `@gestures TextBlock` |
| `Shift+Home`, `Shift+End` | to the start or the end of the line | `TextToGraphics` |
| `Shift+Up`, `Shift+Down` | one line up or down | `TextToGraphics` |

A plain motion key collapses a range, as it does now.

#### T2. A Shift key moves the end in its direction

**Changed in step 0.** A range stays ordered, `start <= stop`: the text slice
documents that contract for `TextRangeReferenceStep`, and about a hundred places
read the two ends of a range step, element ranges of lists among them. A reversed
pair would have to be sorted in each of them.

So a range records no moving end. `Shift+Left`, `Shift+Up`, `Shift+Home` and the
word and text-start keys move the start; `Shift+Right`, `Shift+Down`, `Shift+End`
and their twins move the stop. From a caret, the key's direction makes the range.
The opposite key therefore grows the other end, where most editors would shrink
the range. A plain arrow collapses the range, and the person selects again.
Shrinking with the opposite key is deferred (§4).

#### T3. A projection maps a range when the map is trivial

A projection that maps a caret between its text layer and its domain maps a range
the same way when both ends lie in one span, and the span maps to one field. A
range that it can not map does not become a selection: the `Shift` key declines,
and the selection stays where it was. The existing lowering of
`ReplaceTextRangeOperation` already declines a cross-span range, so a typed key
over such a range does nothing, as now.

The projections that map a range are the ones on the composer's path and the
plain string's: `PrimitiveToText`, `WordWrapping`, `TextToGraphics` and the
composer (T5).

**Changed in step 0.** The syntax chain (`SyntaxLeafToText`,
`SyntaxCompoundToText` and a domain's projection to syntax) maps a caret as one
flat offset at every level. A range there needs both ends carried through each
level, so its range map is deferred (§4). A JSON string still takes a paste at a
caret, which is what step 4 tests.

### The chat draft

#### T4. One selection

A click in the draft writes the complete selection and every trail, as it does
now. **After that, nothing writes a trail of the draft alone.** Every edit and
every motion of the draft is an operation on the complete selection, which the
kernel evaluates at the root and which writes every trail again.

#### T5. A key goes where the complete selection points

The composer's editable text is a text layer like any other. A key reaches it
through the containers, which send it to the child that the selection names. The
text domain's table answers it: typing, `Backspace`, `Delete`, the arrows, the
`Ctrl` arrows and the `Shift` keys of T1. The composer lowers the text layer's
operations to the draft:

- `ReplaceTextRangeOperation` in its body becomes
  `ReplaceStringRangeOperation(parts[n].content.value{s..e}, text)`. The flat
  offsets are shifted by the length of the prefix span of a `DocumentInsertion`.
- `ReplaceSelectionOperation` in its body becomes a selection of
  `parts[n].content.value{s..e}` through `map_reference_backward`, which now
  carries the range.

`map_reference_forward` carries the range too, and the body's selection is that
forward map of the draft's trail. `_cursor` reads the same trail.

The composer's own table keeps only the keys that mean something to a composer:
`Return` (submit, commit or choose), `Alt+Return` (evaluate), `Tab` and `Insert`
(a structured part), `Escape` (cancel). `Shift+Return` becomes
`ReplaceStringRangeOperation(path, "\n")`. `ComposerInputOperation`,
`ComposerBackspaceOperation` and `ComposerNewlineOperation` go, or stay only as
the lowering of T5 if a host names them. Step 0 lists their users.

#### T6. The fallback of the assistant pane goes

`AssistantToWidgetSplitPane` no longer sends a key that nothing took to the draft.
A key goes where the complete selection points, and a selection outside the draft,
for example a message selected with `Alt+click`, keeps its key.

### The clipboard

#### T7. The clipboard makes the text edit

At a text target, a paste answers `ReplaceStringRangeOperation(path, text)`,
rooted at the content and re-rooted with `reroot_operation`. It is the operation
that typing makes, so the kernel applies it the same way in every domain, and the
caret moves to the end of the pasted text.

#### T8. What a text target is

The clipboard's selection (the other plan's D10) ends in a `FieldReferenceStep(f)`
and a `RangeReferenceStep`. The prefix names a document `D`, and `D.f` holds a
`String`, `nothing` or a `Number`. Type checkpoints are ignored. The range is the
one on the path: T4 makes the path true in the draft too. Any other selection is
not a text target, and goes to the rules of D9 as before.

#### T9. Where the pasted text comes from

At a text target, the text comes from the system clipboard. When that gives
nothing (no tool, or an empty clipboard), it comes from the slice when the slice
holds a `PrimitiveString` or a `TextString`. Otherwise the paste is refused.

**Why:** the last copy wins, in whichever program it was made. A copy in
ProjecturEd writes the system clipboard too (T10), so the order stays true.

#### T10. What a copy and a note of a range store

A copy or a note of a range cursor writes the text to the system clipboard,
stores `PrimitiveString(text)` in the slice, and leaves the selection where it
was. A text cursor has nothing to copy: the gesture goes on, and the rules of D9
refuse it, because a caret is not a whole element. Where `:cut` is offered, a cut
of a range also answers `ReplaceStringRangeOperation(path, "")`. The IDE does not
offer `:cut`.

`PrimitiveString` and not `TextString`, because a pasted object goes into a tab,
and the IDE draws a primitive as text.

#### T11. The text branch comes first

The clipboard asks T8 before the rules of D9. A text target never reaches the
whole-document rules, and a whole-element selection never reaches the text
branch. Rule 1 of D9 ("not a caret and not a range") stays true for what reaches
it.

#### T12. A document can refuse pasted text

A new predicate `accepts_pasted_text(document)` goes into `ProjecturedDomain`,
beside `accepts_pasted_document`. It answers `true` by default. A text paste or
cut is refused unless every document from the content down to `D` answers
`true`. **Changed in step 4:** a copy and a note only read, and ask no document,
as a copy of a whole document asks none either; so text is copied out of a
record.

| Document | Answer | Why |
| --- | --- | --- |
| `ConversationConversation` | `false` | the history is a record |
| `Assistant` | `true` (default) | a person types into its draft |
| `SimulationFilter` | `true` (default) | a person types into its fields |

**Why a second predicate:** the clipboard writes above the readers (D9 says why),
so a read-only reader can not refuse the edit. `accepts_pasted_document` is the
wrong question: it refuses the two panes that a person types into.

#### T13. Line breaks and numbers

A text pasted into a string that holds no line break loses its trailing line
breaks. Every other line break stays: a line copied from an editor often ends in
one, and a runner parameter must not.

A paste into a number field is refused when the result is not empty and does not
parse (`splice_number` answers `nothing`). A copy of a range of a number copies
the characters of its text.

#### T14. On by default

The text branch has no keyword: a string takes a string. `offered_gestures` still
decides which keys the clipboard answers. The `text = true` mode for a whole
`TextBlock` stays as it is.

## 4. Deferred

These are the hard parts, and none of them is in this plan:

- **A range with a map that is not trivial:** across spans, across a line break,
  across documents, and over a reference that a projection introduced. A `Shift`
  key that would make one declines (T3).
- **A range in the syntax chain** (T3): `SyntaxLeafToText`,
  `SyntaxCompoundToText` and the domain projections to syntax map a caret only.
- **Shrinking a range with the opposite `Shift` key** (T2).
- **A range selected with the pointer:** a drag, a double click, a `Shift+click`.
- **A projection that is not on the path of the tests** and maps only a caret. It
  keeps its caret map until someone needs its range.
- **A one-line rule per field** (T13 covers the trailing line break only).
- **A text form of a structured object**, such as a table as tab-separated text.
  The other plan puts it out of scope too; `to_text` makes it possible later.
- **Rich text** (HTML) from the system clipboard.
- **A slow clipboard tool.** `read_os_clipboard` runs a process on the drawing
  thread. Step 5 measures one call. If it is slow, an asynchronous read is a
  separate change.

## 5. Steps

### Step 0 — baselines and probes

- [x] The other plan is done: steps 0 to 12 are on `main`, and two items wait for
      the user (a timing, and a change in a sealed file).
- [x] Baseline counts at `edeadcb6`, all passing: `test_clipboard()` 163,
      `test_gesture_help()` 42, `test_command_palette_decorator()` 63,
      `test_text_to_graphics()` 92, `test_primitive_to_text()` 46,
      `test_widget_text_editing()` 12, `test_conversation()` 164,
      `test_assistant_composer_panel()` 15. The omnet-julia counts are taken in
      step 5, on the omnet-julia worktree.
- [x] D9, D10 and D11 as they landed. `_get_clipboard_selection` reads the
      content's trail. `_find_paste_target` applies the three rules. The
      clipboard answers its own keys **first** and passes a key to its content
      only when it declines, so a text branch in its paste runs before any
      reader below. The IDE's `make_ide_window_wrap` has a `selection` flag, on
      by default, that puts the clipboard (copy, note, paste, paste-copy) and the
      walk over the window.
- [x] The probe of §2, repeated in projectured-julia on the assistant example
      through the real editor loop: a press at the placeholder selects
      `…draft.parts[1].content.value{0}`. The keys `h`, `i` make two
      `ComposerInputOperation`s. The value is `"hi"`, the string's trail is
      `value{2}`, and the root's path is still `value{0}`. `Left` makes no
      operation.
- [x] Where the key is lost: a `WidgetCard` sends a key to its content only
      while its own selection is set (`read_intent(::WidgetCardToGraphicsCanvas,
      …)`), and the composer builds its part cards with none. The transcript sets
      them with `_follow_selection!`, and the composer will too.
- [x] **A second fault the probe showed.** The composer's
      `map_reference_backward` reads only the structural caret
      `elements[s].content{k}`. A press gives the flat caret `{f}`, so every click
      puts the caret at the end of the value. Step 3 maps the flat form.
- [x] A reversed pair: not used (T2 changed, see there).
- [x] The projections that map a text caret: `PrimitiveToText`, `WordWrapping`,
      `TextToGraphics`, the other text decorators, the syntax chain, and the
      composer. T3 now names the ones this plan changes.
- [x] The users of the three composer operations: the composer's key table, and
      tests in projectured-julia and omnet-julia (`CampaignAssistantTest`) that
      fill a draft with `ComposerInputOperation(draft, text)` and no editor.
      **Decision:** the three operations stay as a program interface; the key
      table no longer makes them. The panel tests that expect a key with no
      selection in the draft to make one change with T6.
- [x] The composer's structural operations (a new part, a commit, a revert, a
      submit) set the caret on the new part's own cell. **Decision:** they also
      select that caret through the complete path, so that the next key goes to
      the new part (T4).
- [x] The other plan added no `Ctrl+V` to the composer. Its step 7 crossed out
      the composer paste, because a headless press could not place the caret. A
      `MousePress` at the placeholder's drawn text does place it (the probe
      above), so step 5 can test it.

### Step 1 — `accepts_pasted_text` (projectured, domain and conversation slices)

- [x] The predicate in `ProjecturedDomain`, beside `accepts_pasted_document` (T12).
- [x] `accepts_pasted_text(::ConversationConversation) = false`.
- [x] Tests: the conversation in `test_conversation_transcript()` (120, one
      more). The default is asserted in step 4, where the clipboard asks it.

### Step 2 — `Shift` selects a range (projectured, text and primitive slices)

- [x] The `Shift` keys of T1, with the rule of T2: six rows in
      `@gestures TextBlock` (`_text_extend`), and `Shift+Home` / `End` / `Up` /
      `Down` in `TextToGraphics`, which moves the start or the stop to the
      target its plain key finds. `make_flat_range_reference` is public, and the
      private `_flat_range_ref` is gone.
- [x] The range maps of T3: `PrimitiveToText` maps `value{s:e}` to the flat
      range and back. `WordWrapping` maps a range end by end both ways; the
      forward half is `_forward_map`, which `TextHighlighting` shares, so its
      forward map carries a range too. `SyntaxLeafToText` and
      `SyntaxCompoundToText` decline a non-empty flat range
      (`_is_flat_text_range`): before, their backward map read its start, and
      `Shift+Left` in a JSON string moved the caret.
- [x] Tests:
      - `test_text()` 56: the six keys from a caret and from a range, the ends
        of the text, the collapse, and the decline on a whole element (11 new);
      - `test_primitive_to_text()` 51 (46 before): the range maps both ways;
      - `test_word_wrapping()` 60: a range across a soft break maps there and
        back (5 new);
      - `test_text_range_selection()` 17, new, in the umbrella suite, through the
        editor loop: a press, `Shift+Left` twice, `Shift+Right`, `Shift+End`, a
        typed key, `Shift+Home` and `Backspace` on a plain string; the root's
        path names the same range; the range draws one more rectangle; a plain
        arrow collapses; a JSON string declines `Shift+Left` and keeps its caret.
      - Unchanged: `test_text_to_graphics()` 92, `test_widget_text_editing()` 12,
        `test_gesture_help()` 42, `test_command_palette_decorator()` 63,
        `test_clipboard()` 163, `test_json()` 154, `test_syntax()` 10.
        `test_substrate()` 62593 pass, 3 fail, 2 error, 1 broken, all in
        `SplitPaneDragTest`, the failure `main` already has.
- **Found:** a selection path is a live value that changes in place, so a test
  that compares a path before and after a key keeps its printed form. A
  one-character range prints as an element step, `value[5]`; it is the same
  `RangeReferenceStep(4, 5)`.

### Step 3 — one selection in the chat draft (projectured, conversation, assistant and workbench slices)

- [x] The composer's text layer takes the keys (T5). The active part's card and
      its body follow the draft's selection (`_follow_draft!`): the card follows
      a live one, because it routes keys by it, and the body also a dormant one,
      which the text layer draws pale. The text layer's edits come back through
      the kernel's default reader as `ReplaceStringRangeOperation`s on
      `parts[n].content.value{s:e}`.
- [x] Both maps carry a range. The backward map reads the flat form that a
      press and a motion key make, and the span form that an edit is lowered to
      (`_map_body_to_value`). A caret in the chooser's prefix is the value's
      start, and one after it the value's end; a range that leaves the value
      maps to nothing. The body's selection is the forward map of the draft's
      selection (`_body_selection`).
- [x] The composer's own table keeps `Return`, `Shift+Return`, `Alt+Return`,
      `Tab`, `Insert` and `Escape`. `Shift+Return` is a
      `ReplaceStringRangeOperation` of a line break over the draft's selected
      range. The three edit operations stay as a program interface, and every
      composer operation ends with `sync_draft_selection!(editor, draft)`, which
      puts the complete selection on the active part's caret through the path
      that leads to the draft. `make_draft_caret_reference(draft)` builds that
      path's end, and tests use it to put a caret in a draft.
- [x] The assistant pane's key fallback goes (T6). **Found:** the split pane's
      own selection was never set, so a key reached the draft only through that
      fallback. The split pane now follows the assistant's selection.
      **Extended T6 to two more places**, for the same rule: the assistant
      card's key readers act only while the assistant's selection is in the
      draft, and the workbench shell no longer offers a key to every panel when
      nothing is selected. A submit and an evaluation of the assistant call
      `sync_draft_selection!` after they reset the draft.
- [x] Tests:
      - `test_assistant_composer_panel()` 66 (15 before). A new case drives the
        assistant through the editor loop: a press, five keys, `Left`, a key,
        `Shift+Left` twice, `Backspace`, `Shift+Return`, a press inside the
        text, `Return`, a key, `Tab`, three keys, five `Left`s, `Backspace` at
        the value's start, `Ctrl+End` and `Shift+Right`. After each one the
        value, the root's path and the string's selection are asserted, and the
        two selections name one range. The two older cases put a caret in the
        draft before a key, and assert that a key without one edits nothing.
      - `test_conversation()` 167 (165 before): the composer alone answers no
        text key, and its `Shift+Return` is an edit of the value.
      - `test_workbench_tab_click()`: the typing case asserts that a key edits
        the draft only with a caret in it (17 pass). The tab-strip scroll case
        fails as it does before this step.
      - `test_assistant_mvp()` 85, with the 2 failures it has before this step
        (lines 599 and 643); `_mvp_enter!` puts the caret in the draft and
        presses `Return` on the whole assistant chain.
      - `test_assistant_duplicate()` 29, `test_workbench()` 144 with the 3
        failures and 2 errors it has before this step, `test_gesture_help()`,
        `test_command_palette_decorator()` and `test_clipboard()` unchanged.
      The "before" counts are taken in the same session with the step's source
      files stashed.

### Step 4 — the text branch (projectured, clipboard slice)

- [x] Find a text target (T8): `_find_text_target` in `Clipboard.jl` answers a
      `TextTarget` with the path, the document, the field, its value, the range
      and whether the field takes text or a number. An empty field is a number
      field when its document is a `PrimitiveNumber`, or when its cell's value
      type takes an `Int` and not a `String`.
- [x] Paste and paste-copy at a text target (T7, T9, T13), before the rules of D9
      (T11), refused by T12. A number field gets a `ReplaceNumberRangeOperation`,
      as typing gives it, because the string splice would put a `String` into it.
      `\r\n` is read as `\n`.
- [x] Copy and note of a range cursor, and cut (T10).
- [x] Tests:
      - `test_clipboard()` 197 (163 before): a caret takes the text and the
        caret follows it; paste-copy is the same edit; a range is replaced; a
        copy and a note store the characters and keep the selection; a copy at a
        caret changes nothing; a cut takes the range out; a number takes digits
        and refuses letters; the line-break rule both ways; a record refuses a
        paste and a cut and gives its text to a copy; with no system clipboard
        a text slice is pasted and a whole-document slice is refused; the
        default of `accepts_pasted_text`. The D9 cases keep their counts.
      - `test_text_clipboard()` 8, new, in the umbrella suite, through the
        editor loop: a press in the JSON example's `"Alice"` and `Ctrl+V` put
        the text in, and `Ctrl+C` at the caret takes nothing; a plain string
        copies a range made with `Shift+Left` and a paste replaces it.
      - Unchanged: `test_gesture_help()` 42,
        `test_command_palette_decorator()` 63, `test_conversation()` 167,
        `test_gallery_wrappers()` 13.

### Step 5 — the chat draft and the runner in the IDE (omnet)

- [ ] A test in `test/ide/`, through the real editor loop, with the in-memory
      system clipboard:
      - a click into the draft, then `a`, `b`, then `Ctrl+V` of `"xyz\n"`: the
        draft holds `"abxyz"`; then `!`: `"abxyz!"`;
      - `Shift+Left` twice, then `Ctrl+C`: the system clipboard holds `"z!"`;
        then `Ctrl+V` of `"Q"`: the draft holds `"abxyQ"`;
      - a click into a text field of the runner, then `Ctrl+V`: the field holds
        the text, and no run starts;
      - `Ctrl+V` with nothing in the system clipboard and nothing in the slice
        changes nothing.
- [ ] The other plan's step 7 assertion "`Ctrl+V` with the caret in the composer
      pastes text" passes.
- [ ] Measure one real `read_os_clipboard` call on this machine, and write the
      time here.

### Step 6 — guides, and close

- [ ] The text guide ([text.md](../../documentation/package/text/text.md)) names
      the `Shift` keys, and says which ranges map.
- [ ] The conversation guide
      ([transcript.md](../../documentation/package/conversation/transcript.md))
      says that the draft has one selection and takes the text domain's keys.
- [ ] The guide that the other plan wrote for the clipboard says how a text paste
      and a text copy work, and what is deferred. If there is none, a section in
      [operation.md](../../documentation/package/kernel/operation.md) beside
      `ReplaceStringRangeOperation`.
- [ ] The omnet runner guide says that `Ctrl+V` pastes text at a text cursor.
- [ ] Move this plan to `plan/done/`.

## 6. Risks

- **The other plan changes before it lands.** Step 0 reads D9, D10 and D11 as
  they are, and corrects this plan first.
- **The composer's keys change for people who use them.** The draft gains the
  arrows and loses the key fallback of T6: typing while a message is selected no
  longer writes into the draft. The guide says so.
- **A text key reaches a layer that did not take keys before.** The text layer of
  the composer now answers keys that the composer's table answered. Step 3 runs
  every composer key through the real chain, `Return` and `Alt+Return` among
  them, and a `DocumentInsertion` part.
- **A reversed range breaks a map.** T2 allows `head < anchor`. A map that sorts
  the pair loses the moving end. Step 2 tests `Shift+Left` then `Shift+Right`.
- **The key does not reach the clipboard.** `Ctrl+V` must reach the clipboard
  layer; the composer no longer takes it (T5) and the fallback is gone (T6), so
  nothing else takes it. Step 5 tests the real chain.
- **A refused paste says nothing.** An empty system clipboard, or a missing tool,
  makes `Ctrl+V` do nothing, and the person is not told why.
