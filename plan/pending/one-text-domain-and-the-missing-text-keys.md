# One text domain, and the text keys that are missing

**Status (2026-11-10): in progress on the branch `one-text-domain`.** The owner
decided D1, D15, D17 and the list of keys (§1). The assistant proposed the other
decisions, and the owner approved the plan for implementation on 2026-11-10
("Yes"), so they are approved with the plan. No question is open.

**Goal:** every text that the editor shows takes its keys from one table, the
`@gestures TextBlock` table of the text domain. No other table types or removes a
character. The table gets the keys that are missing: Ctrl+Backspace,
Ctrl+Delete, Ctrl+A, Page Up and Page Down with and without Shift, Tab and
Shift+Tab, and a Home that skips the spaces at the start of a line.

**Repository:** projectured-julia. No file that the plan changes is sealed: the
plan changes no file under `source/kernel/`, and [SEALING.md](../../SEALING.md)
seals only kernel files.

**Branch:** `one-text-domain`, in the worktree `../projectured-julia-one-text-domain`.

## 1. The request and the rulings

> I would like to have ctrl+backspace and ctrl+delete operations in the
> projectured text domain. what other typical text operations are missing?
>
> create a plan

The assistant listed ten operations that are missing. The owner answered
(2026-11-10):

> the tab name should also use the generic text mechanism. It's bad that it does
> not today. The julia insertion and the type-in (whatever type-in it is) should
> also use that. There should only be one text domain.
>
> missing operation I want:
>  - ctrl+A
>  - page up/page down, with shift
>  - tab, shift+tab
>  - home key
>
> the rest is not needed. structural crossing selection operations (e.g. style
> change) are deferred for now

"Home key" is the row of the list "Home to the first character that is not a
space". The other rows of the list are not in this plan: the copy of a range
across lines, an edit of a range across two runs, the removal to the start or
the end of a line, replace in the find bar, the operations on a whole line, and
the keys of macOS.

## 2. What exists

### The private text editors

A chain of projections reads a key from its last stage to its first
([Chaining.jl:108-161](../../source/platform/projection/higherorder/Chaining.jl#L108-L161)).
So in a chain that ends in `TextToGraphics`, the text table answers first, and
each stage before it carries the edit back to its own input. An earlier stage
reads the raw key only when no later stage answered, or when a stage can not
carry the answer.

| Place | What reads its keys now | Where |
| --- | --- | --- |
| The name of a tab, a `PrimitiveString` | The pane table gives each typed key, Backspace and Delete, with no modifier, to `read_gesture(title.name, …)`, so the `@gestures PrimitiveString` table edits the name. The tab bar draws the name through a text view with a `TextToGraphics` of its own, but that view reads no key. | [PaneGestures.jl:85-119](../../source/platform/pane/PaneGestures.jl#L85-L119), [PaneGestures.jl:209-221](../../source/platform/pane/PaneGestures.jl#L209-L221), [a-caret-in-the-tab-name.md](../done/a-caret-in-the-tab-name.md) |
| A string, `PrimitiveString` | The text table. `@gestures PrimitiveString` types, and removes with `find_deletion_range`, only where no text table answered. | [PrimitiveToText.jl:313-338](../../source/platform/text/PrimitiveToText.jl#L313-L338), [PrimitiveDocument.jl:538](../../source/platform/primitive/PrimitiveDocument.jl#L538) |
| The type-in, `PrimitiveInsertion`: the field of a value whose type the text decides, such as a number that a person types and that shows red until it parses | The text table, carried back by `PrimitiveInsertionToText` and by `InsertionToSyntaxLeaf`. `@gestures PrimitiveInsertion` types and removes only where no text table answered. Return makes the value, and Escape drops the text. | [PrimitiveToText.jl:340-357](../../source/platform/text/PrimitiveToText.jl#L340-L357), [PrimitiveToText.jl:211](../../source/platform/text/PrimitiveToText.jl#L211) |
| The insertion field of a syntax domain, `InsertionToSyntaxLeaf` | The text table, carried back at [InsertionToSyntax.jl:288-293](../../source/platform/syntax/InsertionToSyntax.jl#L288-L293). Its own table types and removes only where no text table answered, and its Backspace and Delete match any modifier. Return commits, Escape cancels, and Tab accepts the completion. | [InsertionToSyntax.jl:303-337](../../source/platform/syntax/InsertionToSyntax.jl#L303-L337) |
| The hole of Julia code, `JuliaInsertion` | The text table, carried back by the default reader of the kernel through the backward map of `JuliaInsertionToSyntaxLeaf` ([ProjectionDefaults.jl:209-226](../../source/kernel/projection/ProjectionDefaults.jl#L209-L226)). `@gestures JuliaInsertion` types and removes only where no text table answered. Return commits, and Tab commits and goes to the next hole. The first form of this plan said that the leaf can not carry the edit; the reading of the default reader in step 1 showed that it can. | [JuliaInsertionToSyntax.jl:177-229](../../source/domain/julia/JuliaInsertionToSyntax.jl#L177-L229) |
| A step of the address of a navigator, `ReferenceStepToSyntaxLeaf` | No text caret. A step is a value, so every place in its text maps back to the whole step, and a selected step draws as a box, where the text table declines. A typed key or Backspace on the selected step turns it into a `ReferenceInsertion` with the text of the step and the key, or with its last character removed. The insertion is a text of the text domain. | [NavigatorAddressToSyntax.jl:40-85](../../source/platform/navigator/NavigatorAddressToSyntax.jl#L40-L85) |
| The query of a `WidgetChoiceList` | Its own reader. The query is drawn as a label with no caret. A typed key adds a character, and Backspace removes the last one. | [WidgetChoiceList.jl:205-225](../../source/platform/widget/WidgetChoiceList.jl#L205-L225) |
| The draft of a conversation | The text table. `ComposerBackspaceOperation` and `ComposerNewlineOperation` have no producer: only their definitions and the export are left. | [ConversationEditor.jl:210-225](../../source/platform/conversation/ConversationEditor.jl#L210-L225), [ConversationEditor.jl:315](../../source/platform/conversation/ConversationEditor.jl#L315) |
| A chain with no `TextToGraphics`: the console | `SyntaxToText` reads the key against the syntax first, and when the syntax gives no answer, it asks the text table of its output ([SyntaxToText.jl:1203-1218](../../source/platform/syntax/SyntaxToText.jl#L1203-L1218)). So the private tables above answer first in the console, and the text table answers when they are gone. `SelectionInverting` gives `nothing` for a raw key, so the key goes on to `SyntaxToText`. | [SelectionInverting.jl:246-253](../../source/platform/text/SelectionInverting.jl#L246-L253), `make_json_console_projection_example` |

### The keys

| Fact | Where |
| --- | --- |
| The text table binds Backspace and Delete with no modifier only. A rule matches the modifiers exactly, so Ctrl+Backspace and Ctrl+Delete go on to the bindings around the text. | [TextDocument.jl:871-889](../../source/platform/text/TextDocument.jl#L871-L889) |
| Ctrl+Left and Ctrl+Right move by a word: `_word_left_flat` skips the separators and then the word, and `_word_right_flat` skips the word and then the separators. An inline image is a word of its own. A line break is a separator, so a motion crosses lines. | [TextDocument.jl:1131-1154](../../source/platform/text/TextDocument.jl#L1131-L1154) |
| `_text_delete` removes a range, or the character beside a caret. Backspace at the start of the text of a line joins it to the line above, and Delete at the end of a line joins the next line. | [TextDocument.jl:1190-1228](../../source/platform/text/TextDocument.jl#L1190-L1228) |
| An edit of a range that holds text and an image does nothing. A range of only images is removed as elements. | Limits of [text.md](../../documentation/package/platform/text/text.md) |
| Only `VersioningToAny` binds Ctrl+Delete, to delete the active version. It reads its own keys before the keys of the value. The chart and the sequence chart remove a selected part with Alt+Delete. | [VersioningToAny.jl:189-225](../../source/platform/versioning/VersioningToAny.jl#L189-L225), [ChartDocument.jl:962](../../source/domain/chart/ChartDocument.jl#L962), [SequenceChartDocument.jl:1281](../../source/domain/sequencechart/SequenceChartDocument.jl#L1281) |
| The keyboard guide says that Ctrl+Delete removes the selected part. No code binds that meaning. | [keyboard-and-mouse-guide.md:38](../../documentation/guide/keyboard-and-mouse-guide.md#L38) |
| No code binds Ctrl+Backspace or Ctrl+A. Ctrl+Alt+Home selects the root node of a syntax view. | [SyntaxDocument.jl:669](../../source/platform/syntax/SyntaxDocument.jl#L669) |
| Plain Home goes to the start of the row of the caret, in the geometry reader of `TextToGraphics`. In a plain text file the spaces at the start of a line are characters of its run, because `make_text_block` puts a line in one run. | [TextToGraphics.jl:524-530](../../source/platform/text/TextToGraphics.jl#L524-L530) |
| No text binds Page Up or Page Down. Ctrl+Page Up and Ctrl+Page Down switch the tabs. `WidgetChoiceList` reads `:pageup` and `:pagedown`, but every backend gives `:page_up` and `:page_down`, so these keys never move its rows. | [PaneGestures.jl:200-201](../../source/platform/pane/PaneGestures.jl#L200-L201), [WidgetChoiceList.jl:211](../../source/platform/widget/WidgetChoiceList.jl#L211), [KeyboardEvent.jl:11-12](../../source/kernel/event/KeyboardEvent.jl#L11-L12) |
| A scroll area gives its content the height that shows, as the property `:visible_height` of the printer context, and `get_visible_height(ctx)` reads it. The text slice uses the layout slice, which holds it. | [LayoutToGraphics.jl:1228-1275](../../source/platform/layout/LayoutToGraphics.jl#L1228-L1275) |
| `KeepPointOperation(operation, move)` asks the nearest scroll pane to scroll by `move`, so a point that `operation` moves stays where it shows. It is in the widget slice, which is above the text slice. `ShowSelectionOperation`, in the kernel, asks a scroll pane to bring a selection into view. | [KeepPointOperation.jl](../../source/platform/widget/KeepPointOperation.jl), [Operations.jl:196-208](../../source/kernel/operation/Operations.jl#L196-L208), [WidgetToGraphics.jl:7250-7270](../../source/platform/widget/WidgetToGraphics.jl#L7250-L7270) |
| The text table does not take Tab: its rule of typed text takes printable text only, so Tab goes on. Six bindings give Tab a meaning: the completion of an insertion, the composer (it commits the text and opens the chooser of a kind), JSON and YAML (from a key to its value), the hole of Julia (commit and go to the next hole), and the workflow (indent and outdent a node). The text layout draws no tab stops. | [InsertionToSyntax.jl:321](../../source/platform/syntax/InsertionToSyntax.jl#L321), [ConversationEditor.jl:860](../../source/platform/conversation/ConversationEditor.jl#L860), [JsonDocument.jl:146](../../source/domain/json/JsonDocument.jl#L146), [YamlDocument.jl:107](../../source/domain/yaml/YamlDocument.jl#L107), [JuliaInsertionToSyntax.jl:228](../../source/domain/julia/JuliaInsertionToSyntax.jl#L228), [WorkflowToWidget.jl:424-425](../../source/domain/workflow/WorkflowToWidget.jl#L424-L425) |
| A producer of one line declines an edit that holds a break (`_holds_break`), so Enter goes on to the bindings around it. | [PrimitiveToText.jl:62](../../source/platform/text/PrimitiveToText.jl#L62) |
| The console reads the bytes `0x7f` and `0x08` as a plain Backspace, and `ESC [3;5~` as Ctrl+Delete. | [ConsoleBackend.jl:420](../../source/backend/console/ConsoleBackend.jl#L420), [ConsoleBackendTest.jl:146](../../test/backend/console/ConsoleBackendTest.jl#L146) |

## 3. The behaviour

`|` is the caret, `[…]` is a selected range, and `<img>` is an inline image.

| Before | Key | After |
| --- | --- | --- |
| `foo bar |baz` | Ctrl+Backspace | `foo |baz` |
| `foo bar| baz` | Ctrl+Backspace | `foo | baz` |
| `foo |bar baz` | Ctrl+Delete | `foo |baz` |
| `foo bar| baz` | Ctrl+Delete | `foo bar|baz` |
| `foo [bar] baz` | Ctrl+Backspace or Ctrl+Delete | `foo | baz` |
| `first` / `  |second`, a line with an indentation of 2 | Ctrl+Backspace | `first|second` |
| `first` / `  |x`, the two spaces are characters | Ctrl+Backspace | `first` / `|x` |
| `first|` / `second` | Ctrl+Delete | `first|second` |
| `abc <img> |` | Ctrl+Backspace | `abc <img>|` |
| `abc <img>|` | Ctrl+Backspace | `abc |` |
| `fo|o` / `bar` | Ctrl+A | `[foo` / `bar]` |
| `    foo|`, the spaces are characters | Home | `    |foo` |
| `    |foo` | Home | `|    foo` |
| `    fo|o` | Shift+Home | `    [fo]o`, the caret at the start of the range |
| line 3 of 100, 20 lines show | Page Down | line 23, at the same x; the view scrolls 20 lines |
| `foo|bar` | Tab | `foo |bar`, spaces to column 4 |
| `[a` / `b]` | Tab | `    [a` / `    b]` |
| `    |x` | Shift+Tab | `|x` |

## 4. Decisions

### One text domain

- **D1. Only the text table types or removes a character.** Every text takes
  Backspace, Delete, a typed key and every key of this plan from
  `@gestures TextBlock`. A projection that shows a value as text carries the
  edit of the text back to its value. A table of a projection keeps only the keys
  that mean something else: commit, cancel, completion, the next hole. The owner
  decided (2026-11-10).
- **D2. The tab name is read by its text view.** The pane gives no key to the
  name. The key goes to the text view of the name in the tab bar, whose text
  table answers. The tab bar maps the answer back to `title.name.value{s:e}`,
  and the pane takes it as it takes the answer of any part. F2 and Escape stay
  in the pane table, and `_title_edit` and its three rules go. Proposed by the
  assistant; approved with the plan (2026-11-10). Rejected: the pane hands the key to the text table instead of to
  the `PrimitiveString` table. Then the name would still be read in a place
  that draws no text.

  How step 2 does it, found while reading the code:
  - The strip of `WidgetTabbedPaneToGraphicsCanvas` draws the name that holds
    the caret through a text view of one run (`_print_tab_name_view`), but keeps
    the IO map of that view only in a local variable of its printer. The tabbed
    pane gets an IO map type of its own, `WidgetTabbedPaneToGraphicsCanvasIoMap`:
    the fields of a `WidgetChildrenIoMap` and `name_view`, the cell of the IO map
    of the view. A card has an IO map of its own in the same way, with `header`.
  - The reader of the tabbed pane gives a key to that view while the selection is
    in a name, before the selected page gets it, and maps the answer back to
    `selector_element_pairs[i].selector.text{s:e}`. It declines an edit that holds
    a break, because a name is one line.
  - The selection of a name can be a range: the strip draws the range, and the
    pane maps `title.name.value{s:e}` both ways, not only a caret.
  - A name with no text shows a stand-in, the title of the document or
    "untitled". The pane maps back only a place inside the name, so in an empty
    name only a typed key edits, and the stand-in is never edited.
  - `make_pane_retarget_title_operation` loses its last caller and goes.
- **D3. Dropped in step 1: the console needs no change.** The decision was that
  `SelectionInverting` reads a key with the text table, so that the console keeps
  its typing when the private tables go. Step 1 found that `SyntaxToText` already
  asks the text table of its output in a chain with no `TextToGraphics` (§2), so
  the change would give the console a second way to the same table.
- **D4. Dropped in step 1: a step of an address stays as it is.** The decision
  was that `ReferenceStepToSyntaxLeaf` applies an edit at its range. Step 1 found
  that a step has no text caret (§2): its two key rules turn a selected value
  into an insertion, as a typed key replaces a selected value in a JSON
  document, and they edit no text. The insertion that they make is a text of the
  text domain.
- **D5. The query of a `WidgetChoiceList` is a text.** The list draws its query
  through a text view, with a caret, and the keys of the query go to the text
  table. The list keeps Up, Down, Page Up, Page Down and Return, and reads the
  page keys by the names `:page_up` and `:page_down`. Proposed by the assistant; approved with the plan (2026-11-10).
  Rejected: the list keeps its own query editor. Then it would be a second text
  domain.

### The keys

- **D6. Ctrl+Backspace and Ctrl+Delete remove what Ctrl+Shift+Left and
  Ctrl+Shift+Right select**, inside the limits of D7 and D9. Proposed by the
  assistant; approved with the plan (2026-11-10). Rejected: Ctrl+Delete removes to the end of the word, as VS Code
  does. The text has no motion to the end of a word, so that removal would match
  no motion.
- **D7. A word removal stays in the line of the caret.** It stops at the start of
  the text of the line and at the end of the line. When the caret is already
  there, the key joins the two lines, as Backspace and Delete do. Proposed by the
  assistant; approved with the plan (2026-11-10). Rejected: remove exactly what Ctrl+Shift+Left selects. At the start
  of a line, that also removes the last word of the line above.
- **D8. With a range, Ctrl+Backspace and Ctrl+Delete remove the range**, as
  Backspace and Delete do. Proposed by the assistant; approved with the plan (2026-11-10). Rejected: no edit with a
  range.
- **D9. A word removal never holds text and an image together.** It stops at the
  edge of an image, and an image alone is one word. An edit of text and an image
  does nothing (§2), so each press would otherwise do nothing. Proposed by the
  assistant; approved with the plan (2026-11-10). Rejected: one range over the image and the separators before it.
- **D10. Ctrl+A selects the whole text that holds the caret.** In a field, the
  tab name, the draft and a plain text file, that is the whole text. Where the
  range maps to no one part, as in a syntax view, the stage that can not carry it
  declines, and the syntax table answers Ctrl+A by selecting the root node, as
  Ctrl+Alt+Home does. Proposed by the assistant; approved with the plan (2026-11-10). Rejected: in a syntax view,
  select the characters of the leaf of the caret. A person who presses Ctrl+A
  in a file expects the whole file.
- **D11. Home skips the spaces at the start of a line.** On the first row of a
  line, Home goes to the first character that is not a space. When the caret is
  already there, Home goes to the start of the row. On a later row of a wrapped
  line, Home goes to the start of the row, as now. Shift+Home moves the moving end
  in the same way. Proposed by the assistant; approved with the plan (2026-11-10). Rejected: Home goes to the start of
  the line first and to the first character on the second press. Most code
  editors go to the first character first.
- **D12. Page Up and Page Down move the caret by the height that shows.**
  `TextToGraphics` keeps the cell of `get_visible_height(ctx)` in its IO map and
  reads it only in its reader, so a resize prints no line again. The key moves
  the caret by that height and keeps its x, as Up and Down keep it, and stops at
  the first or the last line. The answer is a `KeepPointOperation` with the
  distance that the caret moved, so a scroll pane scrolls by the same distance
  and the caret keeps its row on the screen. With Shift, the moving end moves.
  With no visible height, the key goes on. `KeepPointOperation` moves from the
  widget slice to the layout slice, beside `with_visible_size`, so the text
  slice can make it. Proposed by the assistant; approved with the plan (2026-11-10). Rejected: a
  `ShowSelectionOperation`. The view then scrolls only as far as the caret leaves
  it, so the caret stays at the edge of the view.
- **D13. Tab inserts spaces, and Shift+Tab removes them.** With a caret, Tab
  inserts spaces up to the next stop of 4 columns. With a range over more than
  one line, Tab puts 4 spaces at the start of each line of the range, and the
  range stays on the lines. Shift+Tab removes up to 4 spaces at the start of the
  line of the caret, or of each line of the range. When there is no space to
  remove, Shift+Tab goes on. The width of a stop is a constant of the text slice.
  Proposed by the assistant; approved with the plan (2026-11-10). Rejected: one tab character. The text layout draws
  no tab stops, and a file of spaces would get mixed indentation.
- **D14. "Delete version" moves from Ctrl+Delete to Alt+Delete**, as the chart and
  the sequence chart remove a selected part with Alt+Delete. Proposed by the
  assistant; approved with the plan (2026-11-10). Rejected: keep Ctrl+Delete on the version, so a text in a versioned
  value has no Ctrl+Delete.

- **D15. Tab and Shift+Tab act only in a text that can hold many lines**, such
  as a plain text file and the chat draft. A producer of one line declines their
  edit, as it declines a break, so Tab keeps its meaning in a JSON key, a
  workflow title, an insertion field and a Julia hole, and those domains do not
  change. The owner decided (2026-11-10), with the words "agreed, it's A", to
  Q1: "Does Tab act in a text of one line?". The option that the owner rejected,
  B, made Tab act in every text and made each of the six bindings of §2 an
  `override` binding.
- **D16. The edit of Tab and Shift+Tab is a line edit.** It is a
  `ReplaceTextRangeOperation` that names itself a change of the indentation of
  its lines. So it stays flat, as the edit of Enter stays flat
  (`_lower_unless_line_edit`), and each producer that declines a break declines
  it too: `_holds_break` becomes the check of a line edit. `SyntaxToText` declines
  it, because the lines of a syntax view belong to the syntax, so the syntax
  domain reads Tab as now. A paste of a text that holds a tab character is no
  line edit, so it still goes into a field. Proposed by the assistant; approved with the plan (2026-11-10).
  Rejected: an edit that holds a tab character, which a producer of one line
  declines. That also declines a paste with a tab. Rejected: a new operation
  type, which every decorator of a text would have to carry.

- **D17. Tab indents the draft of the chat composer.** The draft is a text of
  many lines, so by D15 Tab indents it. The binding of Tab in the composer
  ([ConversationEditor.jl:860](../../source/platform/conversation/ConversationEditor.jl#L860)),
  which commits the text and opens the chooser of a kind, goes, because it would
  no longer fire. Insert starts a new part, as now. The owner decided
  (2026-11-10), with the words "Agreed it's A", to Q2: "What does Tab do in the
  chat composer?". The option that the owner rejected, B, made the binding of the
  composer an `override` binding, so the draft had no Tab.

## 5. Steps

Each step ends with its tests and a commit on the branch. A step that removes
code also compares `test_repls()` with the same run on `main`, because the walk
of every example types keys into each one.

**The baseline** is the branch point `b14502b56`, run in the worktree before any
change (Julia 1.13.1, 2026-11-10). Every function of the list of step 1 passes
with no failure, except two: `test_repls()` gives 31988 pass, 206 fail, 0 error
and 8 broken, and `test_typeins()` gives 5148 pass and 20 broken. Also with no
failure: `test_versioning_to_any()`, `test_text_to_graphics()`,
`test_inline_image_caret()`, `test_widget_menu_keys()`, `test_command_palette()`,
`test_widget_text_editing()` and `test_text_range_selection()`.

1. ✅ **The leaves keep no key of the text (D1).** Done 2026-11-10. Every
   function of the list below gives the counts of the baseline. Two tests read a
   raw key with a projection that has no text stage, so they relied on a private
   table: `InsertionChoicesTest.jl` now gives the leaf the text edit that the
   text domain makes of the key, and `JuliaTypeinTest.jl` types through the chain
   of `make_julia_projection_example`, from Julia to graphics. Remove the rows that type or
   remove a character from `@gestures PrimitiveInsertion`, the table of
   `InsertionToSyntaxLeaf` and `@gestures JuliaInsertion`, and the helpers that
   lose their last caller: `insert_insertion_text_operation`,
   `delete_insertion_text_operation`, `_make_insertion_typed_operation` and
   `_make_type_in_deletion`. Remove the two composer operations that have no
   producer, `ComposerBackspaceOperation` and `ComposerNewlineOperation`.
   `JuliaInsertionToSyntaxLeaf` needs no new reader (§2). `@gestures
   PrimitiveString` stays until step 2, because the pane reads it for the tab
   name. The removed exports give `ProjecturedPlatform` a minor step at its next
   release. Test: `test_text()`, `test_primitive()`, `test_primitive_type_in()`,
   `test_primitive_to_text()`, `test_insertion_choices()`,
   `test_insertion_in_tab()`, `test_pane_rename()`, `test_console_backend()`,
   `test_julia_typein()`, `test_navigator_address()`,
   `test_conversation_editor()`, `test_assistant_composer_panel()`,
   `test_typeins()`, `test_json()`, `test_sql()`, `test_evaluator_toplevel()` and
   `test_repls()` against the baseline of the branch point.
2. ⬜ **The tab name (D2).** Remove `@gestures PrimitiveString`, `_string_delete`
   and `find_deletion_range`, which then have no caller. Test:
   `test_pane_rename()`, which presses F2, types, removes and leaves through a
   real editor.
3. ⬜ **The query of a choice list (D5).** Test:
   `test/platform/projection/WidgetMenuKeysTest.jl` and
   `test/projectured/projection/CommandPaletteTest.jl`, with Page Down added.
4. ⬜ **Ctrl+Backspace and Ctrl+Delete (D6 to D9).** Two rows in the text table,
   "Delete a word backward" and "Delete a word forward". Test: the rows of §3 in
   `test_text()`, and the two image rows in `test_inline_image_caret()`.
5. ⬜ **Ctrl+A (D10).** A row in the text table and a row in the syntax table.
   Test: `test_text()`, and Ctrl+A in `json_example`.
6. ⬜ **Home (D11).** Test: `test_text_to_graphics()`.
7. ⬜ **Page Up and Page Down (D12).** Move `KeepPointOperation` to the layout
   slice. Test: `test_text_to_graphics()` for the caret, and a text in a scroll
   pane through an editor for the scroll.
8. ⬜ **Tab and Shift+Tab (D13, D15, D16, D17).** Remove the binding of Tab in
   the composer. Test: `test_text()`, Tab in a plain text and in the chat draft,
   Insert in the chat draft, which still starts a new part, and Tab in a JSON
   key, a workflow node title, an insertion field and a Julia hole, where it
   keeps its meaning.
9. ⬜ **Delete version on Alt+Delete (D14).** Change
   [VersioningToAny.jl:195](../../source/platform/versioning/VersioningToAny.jl#L195)
   and [VersioningToAnyTest.jl:173](../../test/platform/projection/VersioningToAnyTest.jl#L173).
   Test: `test_versioning_to_any()`.
10. ⬜ **Through an editor, and the documents.** A new umbrella test,
    `test_text_keys()`, presses each key of this plan through an editor on a plain
    text, a string of `json_example`, the chat draft and a tab name. It checks the
    document and the caret that renders, and that one undo takes back one
    Ctrl+Backspace. Update the key table and the limits of
    [text.md](../../documentation/package/platform/text/text.md), the rows of
    [keyboard-and-mouse-guide.md](../../documentation/guide/keyboard-and-mouse-guide.md),
    [versioning.md](../../documentation/package/platform/versioning/versioning.md),
    and the documents of the pane, the primitive and the widget slices where they
    name the private tables. Test: `test_text_keys()`, and
    `test_documentation()`.

## 6. Limits after the plan

- In the console, most terminals send Ctrl+Backspace as the byte `0x08` or
  `0x7f`, which is also the plain Backspace. So the console removes one
  character. Ctrl+Delete works there.
- A word removal across two runs of one styled line does nothing, as any edit of
  such a range does. The owner deferred an edit across runs.
- A text of a lazy list of lines has no Page Up and Page Down, as it has no Up and
  Down.

**Not in this plan:** the operations that the owner did not choose (§1); the
console byte `0x08`; `ComposerInputOperation`, which the assistant uses to put a
command into the draft and which no key makes; Backspace on a selected node of a
formula, which replaces the node and edits no text.
