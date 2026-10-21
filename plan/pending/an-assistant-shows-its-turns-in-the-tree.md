# An assistant shows its turns in the tree

Status: IN PROGRESS, 2026-10-21, on the branch `conversation-outline`, in the
worktree `projectured-julia-conversation-outline`. Not landed on `main`.

## The ask

The ask, 2026-10-21: "make an outline view of the conversation below the
assistant item in the tree where it would be possible to see the turns and the
stuff in the turns in the tree recursively and click on each one".

The owner, 2026-10-21, on what a click does: "in the explorer's navigator, no
move on the assistant's own tab".

An example of the result, in the Explorer:

```
Assistants
└─ Fix the paste guard                       (an assistant)
   ├─ Explore: find the guards               (a subagent)
   │  ├─ You · Find where the guard reads…
   │  └─ Assistant · The guard reads the size…
   ├─ You · I was wondering if we could make an outline…
   └─ Assistant · Yes, we can do this.        9 parts · 14:02:11
      ├─ Thinking
      ├─ tool · Bash "git grep -n -i assistant"
      ├─ tool · Read "ExplorerDocument.jl"
      └─ Yes, we can do this.
```

## The facts

The facts at `main` `3f8b6a126`, checked again at `bc22297b4`. Find each
function by its name.

1. **The tree asks each document for its node.** `get_tree_children_steps`
   gives the paths to the collections of the children, `format_tree_node_label`
   gives the text, and `get_document_decoration` gives the icon, the marks and
   the detail ([TreeInterface.jl](../../source/platform/tree/TreeInterface.jl)).
   Each path must reach a collection. The default is a leaf whose label is the
   title or the name of the type. The tree reads the children of an open node
   only, and keeps each label in the cell of its row.
2. **An assistant gives two collections now.** `Assistant` gives
   `agent_work.subagents` and `agent_work.background_tasks`
   ([AssistantList.jl](../../source/platform/assistant/AssistantList.jl)).
   `AgentWork`, the node of a subagent, gives `subagents` and `background_tasks`
   ([AgentWorkDocument.jl](../../source/platform/assistant/AgentWorkDocument.jl)).
   The root of the tree of the work page, `AssistantWork`, gives the same two.
3. **A conversation is a list of turns, and a turn is a list of parts.**
   `Assistant.conversation` is a `ConversationConversation` with `turns`, a
   `CellVector` of `ConversationTurn`. A turn has `role`, `parts` (a `CellVector`
   of `ConversationPart`), `start_time` and `finish_time`. A part has `content`,
   a document. A subagent has its own `conversation`, which the feed fills
   (`_open_agent_turn!(child.conversation)` in
   [AgentEventFeed.jl](../../source/platform/assistant/AgentEventFeed.jl)).
4. **The content of a part is one of these kinds.**
   - A `TextBlock` while a text streams. At the end of the text,
     `parse_markdown_blocks` puts in its place a Markdown document, or the
     document of a domain for a fenced block of code.
   - A `ConversationThinking`.
   - An `EvaluatorForm` for a tool call. `get_evaluation_title(form)` gives its
     header, such as `tool · Grep "query"`. It has `is_running` and `is_error`.
   - A `ConversationPermissionRequest` (`title`), a `ConversationQuestionRequest`
     (`message`) or a `ConversationSignInRequest` (`message`).

   No kind of content gives tree children now.
5. **A press on a node of the Explorer shows its page in the navigator.**
   Ctrl+press opens the page in a new tab (`_convert_explorer_answer` in
   [ExplorerToWidget.jl](../../source/platform/explorer/ExplorerToWidget.jl)).
   The row `make_conversation_row` draws every `ConversationDocument`, and
   `ConversationToWidget` has a print for a turn and for a part. Step 2 tests
   that a turn and a part show as a page.
6. **The text of a document.** A `TextBlock` gives its string with
   `get_flat_string`. Any other document with a natural notation gives its
   text with `print_natural_text`, which prints the whole document.
7. **The conversation slice can not use the tree slice now.**
   `PLATFORM_SLICE_EDGES` in
   [PlatformSuite.jl](../../test/platform/PlatformSuite.jl) gives no edge from
   `conversation` to `tree`. The tree slice loads before the conversation slice,
   and it does not use it, so the edge makes no cycle. The edge from
   `systemprocess` to `tree` is of the same kind.
8. **A test asserts that a subagent and the work page give the same children.**
   The testset "the nodes of the tree of the work, and a file of the page" in
   [AssistantWorkTest.jl](../../test/platform/conversation/AssistantWorkTest.jl)
   asserts `get_tree_children_steps(child) == get_tree_children_steps(work)`.

## The design

### The decisions

- **D1 (the owner).** A press on a turn or a part shows it as the page of the
  navigator of the Explorer. The tab of the assistant does not move. This
  needs no new operation.
- **D2 (mine).** The turns are the third collection of an assistant, after the
  subagents and the background tasks. A node "Conversation" between them is not
  possible, because a child must be an element of a collection. The few nodes of
  the work stay at the top, and the long list of turns comes after them.
- **D3 (mine).** The conversation slice owns the tree hooks of its own kinds. It
  gets the edge to `tree` in `PLATFORM_SLICE_EDGES`. The interface of the tree
  says that the slice that owns a kind adds its methods.
- **D4 (mine).** A part forwards to its content: its children are the
  children of its content, with the step `content` in front. No kind of content
  gives children now, so the outline ends at the part. A kind that gives
  children later continues the outline with no change here.
- **D5 (mine).** `AgentWork` gets the turns too, so a subagent shows its own
  conversation. The hook is for a document, not for one tree, so the tree of the
  work page also shows the turns below each subagent. Its root, "This session",
  stays as it is.

### The nodes

| Node | Children | Label | Decoration |
| --- | --- | --- | --- |
| `Assistant` | subagents, background tasks, `conversation.turns` | as now | as now |
| `AgentWork` | subagents, background tasks, `conversation.turns` | as now | as now |
| `ConversationTurn` | `parts` | "You" or "Assistant", then " · " and the first line of its first text part, if one exists | icon `:user` or `:bot`; while it runs, `:loader` and the condition `:running`; the detail "N parts" and the start time `HH:MM:SS`, if it is known |
| `ConversationPart` | the children of its content, after the step `content` | the label of its content | the decoration of its content |

A turn runs while its `start_time` is not zero and its `finish_time` is zero.
The detail reads no clock.

The label and the decoration of a part come from two private functions of the
conversation slice:

- A `TextBlock` gives the first line of `get_flat_string`, and the icon
  `:pilcrow`.
- Another document with a natural notation gives the first line of
  `print_natural_text`, and the icon `:pilcrow`.
- Any other document gives `format_tree_node_label` and
  `get_document_decoration` of the content.

The first line is the first line that is not blank, with no blanks at its ends,
cut at 80 characters with "…".

The conversation slice gives the two generics to its own kinds of content:

| Kind | Label | Decoration |
| --- | --- | --- |
| `ConversationThinking` | "Thinking" | `:circle_dashed` |
| `EvaluatorForm` | `get_evaluation_title(form)` | `:lambda` for `eval`, else `:terminal`; while `is_running`, the condition `:running`; with `is_error`, the condition `:failed` |
| `ConversationPermissionRequest` | its `title` | `:circle_help`; while it is open, the condition `:waiting` |
| `ConversationQuestionRequest` | the first line of its `message` | `:circle_help`; while it is open, the condition `:waiting` |
| `ConversationSignInRequest` | the first line of its `message` | `:lock` |

A tool call keeps the icon of its kind and says its state as a condition, as
`get_document_decoration(::EvaluatorToplevel)` does. A request whose text is
blank says "Permission", "Question" or "Sign in". (Found in step 1.)

### What else changes

- The menu `▾` of the Explorer lists the kinds of the rows that the tree read.
  After a person opens an assistant, it also lists the turn and the part.
- A search below a node (`ExplorerSearch`) also walks the turns and the parts,
  so a search finds a turn by its first line. Step 3 measures its cost.

## The steps

Do the work in the worktree `../projectured-julia-conversation-outline`, on the
branch `conversation-outline`. Make a commit for each step. Do not land on
`main` without the approval of the owner.

1. [x] **The nodes of a turn and a part.** Add the fragment
   `source/platform/conversation/ConversationTree.jl` with the methods of "The
   nodes" and of the kinds of content. Import `get_tree_children_steps` and
   `format_tree_node_label` from `TreeModule` in `ConversationModule`. Add
   `"tree"` to the edges of `"conversation"` in `PLATFORM_SLICE_EDGES`. Add
   `test/platform/conversation/ConversationTreeTest.jl` with
   `test_conversation_tree()`, and call it from `test_conversation()`. The test
   asserts the children, the label and the decoration of each row of the two
   tables, a turn that runs, the cut of a long line, and the forward of a part
   whose content gives children (an `ExplorerSection` as the content). Run
   `test_conversation_tree()` and `test_platform_slice_edges()`.

   Done, 2026-10-21. `test_conversation_tree()` passes 42 of 42,
   `test_platform_slice_edges()` 1 of 1, and `test_platform_layering()` 21 of
   21. The test module of the conversation imports `ProjecturedJSON`, so a part
   of JSON is the document with a natural notation that the test labels. No
   other test reads a decoration of a conversation kind.
2. [ ] **The turns below an assistant and a subagent.** Add
   `(FieldReferenceStep("conversation"), FieldReferenceStep("turns"))` as the
   third collection of `Assistant` and of `AgentWork`. Change the assertion of
   fact 8: a subagent gives the two collections of the work page and the turns.
   Add a testset to `AssistantWorkTest.jl`: an Explorer of a section that holds
   an assistant with a finished turn; a press on the row of the turn shows the
   turn as the page of the navigator, and a press on the row of a tool call
   shows that part. Run `test_assistant_work()`, `test_explorer()` and
   `test_document_tree()`.
3. [ ] **The cost.** In a scratch script, make an assistant with 200 turns of 10
   parts each, with a Markdown text of 20 lines in each part. Measure two
   values: the frame that draws the open node of the assistant, and a search
   from the root for a word of the last turn. Write the two numbers here. If the
   frame takes more than 50 ms, or the search more than 2 s, report it to the
   owner. Do not change the design in this plan.
4. [ ] **The guides.** In
   [tree.md](../../documentation/package/platform/tree/tree.md), change the
   example of the two collections of the work of an agent. In
   [assistant.md](../../documentation/package/platform/assistant/assistant.md),
   say the three collections of an assistant and of a subagent, and that the
   tree of the work page shows the turns below a subagent. In
   [conversation.md](../../documentation/package/platform/conversation/conversation.md),
   add a section about the nodes of a conversation in a tree, with the two
   tables.
5. [ ] **The live check.** Start the application with an external agent. Send
   one prompt that makes a tool call. In the Explorer, open Assistants, the
   assistant and its last turn. Press the row of the tool call: the navigator
   shows the tool call, and the tab of the assistant does not move. Keep a
   screenshot, and write what it shows here.

## Open items

- D5: the tree of the work page also shows the turns below each subagent. The
  owner can keep it, or ask for the work page to show the work only.
- A label is the first line as the source writes it, so a Markdown line keeps
  its marks, such as `**Plan**`.
