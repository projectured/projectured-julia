# The plain text of a conversation follows its theme

Status: a plan. Written 2026-11-02 from the answers of the owner on that day.
Nothing is built yet.

## 1. Goal

The greeting of the assistant pane does not follow the size of the text
(Ctrl+Alt+= and Ctrl+Alt+-) or the fonts of the Appearance tab. The same is true
for the error lines, the notes of an external agent, an answer while it streams
and the text of a thinking part. The zoom and the colour mode reach them, because
the zoom scales the whole frame and `TextToGraphics` swaps `color_default` for the
colour of its theme.

The owner, 2026-11-02:

- "a conversation is just another domain, I don't see why it would not work the
  same way as any other domain"
- "since the user cannot style a user message in a draft, it's basically a plain
  string which is drawn with the conversation style."
- "when the AI agent talks to the user, if it talks in plain text then we should
  store that and use the conversation theme to display it"
- "if the AI responds with markdown, we should store that and use the markdown
  theme"

## 2. Facts (2026-11-02)

- **The document chooses the font.** `ConversationPart(::String)` makes a
  `TextBlock` with `make_text_block`, which puts `UNSTYLED_TEXT_FONT`
  (`StyleFont("Ubuntu Mono", 14)`) in each run. `TextToGraphics` draws the font
  of a run as it is (`TextToGraphics.jl`, the read of `span.font`). So no theme
  reaches the text.
- **The transcript uses its theme only for its own labels.**
  `ConversationPartToWidget` gets the role, tag, section and error styles and
  the gaps from `ConversationTheme`. Its last branch shows the content of a part
  as it is.
- **A `PrimitiveString` part takes the wrong theme.** In the application it
  reaches the row of `PrimitiveDocument`, which prints with `PrimitiveToText`
  and the `TextTheme`.
- **The printer that the transcript needs exists.** `PrimitiveStringToTextBlock`
  prints a `PrimitiveString` as a `TextBlock` in a style that it gets, maps the
  selection both ways, and keeps the object of each line that did not change.
- **A sent message is changed.** `finalize_draft!` makes each `PrimitiveString`
  part a markdown document, and `ComposerInsertPartOperation` makes it a
  `TextBlock`. The markdown round trip loses text: `"line1\nline2"` comes back
  as `"line1 line2"`, `"1. first\n2. second"` as `"- first\n- second"`, and an
  indented line as a fence with the language `lang`. The model reads that print.
- **The model text of a `PrimitiveString` is its `repr`.** `_content_to_string`
  and `_block_text` of `PrimitiveString("a")` give `"PrimitiveString(\"a\")"`.
  Only `_text_to_string` gives the value.
- **The stream holds a `TextBlock` for its print, not for a style.**
  `append_text!` adds a delta at the end of the last line, so the lines before it
  keep their print (step 2 of `plan/done/an-answer-streams-in-without-holding-the-window.md`).
  Before that step, a frame of a delta grew from 5.09 ms to 16.64 ms over one
  answer. Both streams, the built-in loop and an external agent, go through
  `_handle_agent_event!`.
- **The composer draws typed text in `code_font`** (Ubuntu Mono), in
  `_editable_body`. A markdown answer draws its prose in Ubuntu.
- **The thinking card makes two texts with no style**: `"[redacted thinking]"`
  and `"[no thinking summary]"` (`ConversationToWidget.jl`).
- The greeting of each backend comes back unchanged from the markdown round
  trip.

## 3. Decisions

- **D1. The type of a text follows one rule** (the owner, 2026-11-02): "we store
  it as TextBlock if we want to have style in it other than what the
  conversation theme offers, we store it as PrimitiveString if we want to allow
  having selection in it and print the document on its own, otherwise we store
  it as a String".
- **D2. A user message is a list of parts of any content** (the owner,
  2026-11-02): "the user message must be able to contain content other than
  string or text, it can already contain images, widgets, JSON, etc. whatever the
  user can put there". The rule of D1 applies only to a typed text part.
- **D3. The source of a text decides its format.** The text of a model has no
  mark of its format. An answer of the model is markdown and takes the markdown
  theme. Its thinking is plain text and takes the conversation theme. The editor
  knows the format of each text that it writes. (The table of §4, which the
  owner agreed to on 2026-11-02.)
- **D4. A streamed answer, a thinking text and an error line can be selected**
  (the owner, 2026-11-02: "agreed, yes must be able to select"). So each one is a
  `PrimitiveString`.
- **D5. The greeting is markdown with some style** (the owner, 2026-11-02:
  "put in a markdown (which I would prefer to use some style in it) and use the
  markdown theme").
- **D6. A new field `message_text` of `ConversationTheme`**, `TextRole(:text)`
  on the base `font` (Ubuntu). The composer and the transcript both use it, so a
  message looks the same before and after it is sent (the owner, 2026-11-02:
  "yes").
- **D7. A text part takes a range selection, and the transcript stays read-only**
  (the owner, 2026-11-02: "eventually we need both whole part and range
  selection, they are different / in both cases the transcript should stay read
  only", and "so it's option (a)"). A plain click puts a caret and a drag
  selects a range in a plain or a markdown part; an Alt+click selects the whole
  part. Before this plan, a click anywhere in a part named the part
  (`ConversationToWidget.jl`, "a transcript is read as messages, not as
  characters"), so a markdown answer could be selected only as a whole.
- **D8. The guard of the stream checks the pieces made again and the time of a
  delta** (the owner, 2026-11-02: "Yes"). A streamed answer is one plain text, so
  a delta marks each cell that reads the text, and the count of marked cells
  grows with the answer (63 at 10 paragraphs, 1,053 at 1,000). The guard no longer
  counts them. It checks that the objects that a delta makes again stay the same
  (184 at both sizes), that the lines before the last keep their objects, and
  that a delta at the end of 1,000 paragraphs takes less than 5 ms.
- **Rejected:** a printer-context property `:text_font` that `TextToGraphics`
  reads for a run in `UNSTYLED_TEXT_FONT` (the owner: "no, that's the wrong
  fix"). Markdown for every plain text: the round trip loses line breaks.

## 4. Design

| Part | Format | Type | Theme |
| --- | --- | --- | --- |
| Typed text part of a user message | plain | `PrimitiveString`, also after it is sent | conversation, `message_text` |
| Other parts of a user message | their own | their own document | their own domain |
| Model answer, while it streams | incomplete markdown source | `PrimitiveString` | conversation, `message_text` |
| Model answer, after the stream | markdown | markdown document | markdown |
| Text of a `ConversationThinking` | plain | `PrimitiveString` | conversation, `message_text` |
| Error line | plain | `PrimitiveString` | conversation, `message_text` |
| Greeting | markdown | markdown document | markdown |
| Notes of an external agent: fork, new session, sign-out | plain | `String` in a `ConversationNote` | conversation, `section_text` |
| "Go on." and the prompt of `SubmitProseOperation` | plain | `PrimitiveString` | conversation, `message_text` |
| Prompt of a subagent | markdown | markdown document | markdown |
| A code fence with no parser for its language | markdown | markdown document | markdown |

`ConversationPart(::AbstractString)` makes a `PrimitiveString` part: a plain
text is the default. A producer of markdown calls `make_prose_document` itself.

## 5. Steps

Each step is done in a worktree, runs the narrowest tests that cover it, and
ends with a commit.

1. ✅ **Done.** **The style and the print of a plain text part.** Add `message_text` to
   `ConversationTheme`. `ConversationPartToWidget` prints a `PrimitiveString`
   part with `PrimitiveStringToTextBlock` and `message_text`, and maps a
   reference through that child IO map. A part with no chrome, such as a
   markdown answer, maps a reference into its content by the step `content`
   (D7). An Alt+click still names the part, and each edit is still declined.
   `_editable_body` draws a typed `PrimitiveString` in `message_text`; a kind
   chooser keeps `code_font`. `_content_to_string` and `_block_text` of a
   `PrimitiveString` give its value exactly. Tests: the font of a
   `PrimitiveString` part follows `font_scale`, its model text is its value, a
   click in a plain or a markdown part names a text position, an Alt+click names
   the part, and an edit at a text position is declined.

   As built: a text part is a part whose content is a `PrimitiveString`, a
   `TextBlock`, or a document in a format that is no code, which
   `ConversationToWidget.jl` already reads as prose (`_is_text_content`). So the
   text parts of the example, which are still `TextBlock` until step 3, take a
   range selection now. The part maps the text as a whole to the part, so an
   Alt+press on a plain text names the part with no extra rule. The composite
   cuts an Alt+press inside the text of a text part to the part, so a markdown
   paragraph is no Alt+click object of the transcript (D7). `_find_path_part`
   walks a path to its part for both `_is_live_path` and `_is_text_path`. The
   tests: `test_conversation_transcript`, `test_parse_markdown_blocks` and
   `test_conversation_theme`, 215 passes.
2. ✅ **Done.** **A sent message keeps its text.** `finalize_draft!` and
   `ComposerInsertPartOperation` keep a `PrimitiveString` part as it is. Change
   the sentence of `transcript.md` that says a typed message becomes markdown.
   Tests: a sent message with line breaks reaches the model unchanged, and a
   person can select a range inside it.

   As built: a committed text that stays in the draft before an inserted part
   draws as the typein drew it (`_committed_body(p, ::PrimitiveString)`), and the
   maps of the composer read its places as a value, as for the typein
   (`_has_value_body`). `reset_draft!` already takes the caret out of each sent
   part, so a sent message shows no caret. The tests:
   `test_conversation_editor`, `test_parse_markdown_blocks`,
   `test_conversation_transcript`, `test_assistant_composer_panel`,
   `test_draft_press` and `test_conversation_theme`, 355 passes.
3. ✅ **Done.** **The editor text takes its type.** `ConversationPart(::AbstractString)`
   makes a `PrimitiveString`. The three agent notes become `ConversationNote`.
   The greeting, the prompt of a subagent and the fallback of a code fence
   become markdown; the greeting shows its keys and its command-line options as
   code spans. Tests: the greeting test of `ApplicationTest`, and the tests of
   the agent notes.

   As built: the greeting also shows **Explorer** and **Files** in bold, and the
   name `ProjecturedACP` and the variable `ANTHROPIC_API_KEY` as code spans.
   `_content_to_string` of a `ConversationNote` gives its text, as `_block_text`
   already did, so `_part_text` reads a note. The line "Starting Claude Code…"
   is an editor text too, so it is a `PrimitiveString`. The tests:
   `test_application` gives 389 passes and the two failures that main has
   (memory `application-test-baseline-2026-10-15`, `:677` and `:789`);
   `test_external_agent_turn` and `test_agent_work` give 466 passes in a process
   that loads only `ProjecturedPlatformTest`. In a process that also loads
   `ProjecturedTest`, the MCP package starts a server for each external turn, and
   the stand-in editor `(document = a,)` of those tests has no `tools`, so they
   must run without it.
4. ✅ **Done.** **The stream and the thinking text.** `LlmTextStart` opens a
   `PrimitiveString` part, a delta adds to its value, and `LlmTextStop` parses
   the value with `parse_markdown_blocks`. The text of a `ConversationThinking`
   is a `PrimitiveString`, and the two texts of the thinking card take a style of
   the theme. Measure the frame of a delta over one answer with the test of the
   stream plan, and compare it with §2. Tests: `AssistantStreamTest`, and a
   thinking text that can be selected.

   As built: `PrimitiveStringToTextBlock` reads the value in two string cells,
   the lines before the last break and the last line, and the last line is one
   object whose run reads the second cell. So a delta with no break changes only
   that run, and the line objects stay: a delta makes 184 objects again at 10 and
   at 1,000 paragraphs, where a print of the whole value made 218 and 1,208. A
   delta at the end of 1,000 paragraphs takes 0.55 ms at that layer, 100
   paragraphs 0.02 ms. The count of marked cells still grows with the answer, and
   D8 records the change of the guard. A place in a thinking text is
   `content.text.<place>`; `_find_text_leads` gives where the text of a part is,
   in its output and in the part, and the maps and the press rule of the
   transcript read it. The tree knows a plain text part by its first line, as a
   text block. The tests: `test_conversation_transcript`,
   `test_conversation_serialization`, `test_text_clipboard`,
   `test_text_range_selection`, and in a process with no MCP package
   `test_primitive_to_text`, `test_conversation_tree`, `test_assistant_overview`
   and `test_conversation_theme`.
5. **Check and close.** Run the conversation and assistant tests of the platform
   and `ConversationTranscriptTest`. Check that omnet-julia loads and
   precompiles. Update `conversation.md`. Move this plan to `plan/done/`.

## 6. What else changes

- omnet-julia makes the greeting of its IDE with `ConversationPart(String(text))`
  (`source/ide/CampaignWindow.jl`). After step 3 it is a `PrimitiveString` in
  `message_text`. It follows the theme, but it shows no markdown style until
  omnet-julia calls `make_prose_document`.
- After step 4 `append_text!` has no caller. It stays, because it is an export
  of `TextModule`.

## 7. Not in this plan

- The text of the arguments and of the result of an evaluation
  (`Evaluator.jl`, `make_text_block` with `_EVALUATOR_TEXT_STYLE`) has the same
  fault. It is program output, and a later plan decides its style.
- A range selection inside a code card and inside the two sections of an
  evaluation. They keep the selection of a whole part or a whole section.
