# An evaluation moves the selection from the root

**Status (2026-09-23): IMPLEMENTED** on branch `evaluation-selection`; landing on
`main` waits for the owner's approval. The owner asked for the measurement first
("first measure and collect, don't fix automatically anything yet"); Step 0 is
done. Then the owner decided (§4): "fix them — a draft can keep a dormant caret —
the rest as recommended by you — drop the 2nd part of the plan". The general
program of part 2 (every evaluation says its selection from the root) is dropped;
this plan fixes the measured findings, each at its own place.

**Goal:** the five measured findings pass: after each gesture the live selection
is one path from the root, with no live selection off it, and no caret is drawn
off the focus.

**Repositories:** projectured-julia. A search of omnet-julia found no site of this
kind; only the dormant selection of its embedded panes, which keeps the rule.

**Rules:** PAR-SELECTION-WRITTEN-AT-ROOT, PAR-READER-IS-PURE.

## 1. The question

This is part 2 of plan `an-operation-enters-at-any-reference` (in `plan/done/`).
That plan fixed the verbs, which now say their edit at a place and let the readers
lift it to the root. It left out the evaluations that write a selection: an
operation is evaluated after the readers have run, so no reader lifts what the
evaluation writes.

PAR-SELECTION-WRITTEN-AT-ROOT says: the live selection is one path from the root,
and each document on that path holds its suffix of it. A dormant selection, which
a document keeps off the live path, is not the live selection.

A read of the code (2026-09-23) listed the places that write a live selection
below the root. It did not say whether any of them hurts a person. The owner asked
what a fix buys, and decided to measure first.

## 2. How it is measured

A test set in `test/projectured/editor/ApplicationTest.jl`, "after each gesture,
the live selection is one path from the root", opens the application window with
an assistant (`FakeLlm`), does what a person or a script does, and then checks:

- **one path:** each document on the root's live path holds the rest of that path
  (`_app_find_path_mismatches`);
- **no stray:** no document holds a live selection off the root's path or off a
  dormant path. The search enters the contents of the tabs, but not what a history
  records (`_app_find_stray_selections_in_contents`);
- **what a person sees:** how many carets the window draws.

A case that breaks the rule is marked `@test_broken` with a `# @broken:` comment,
so the suite stays green and the finding is kept. `test_application` is 270 pass
and 6 broken; it was 246 pass before the test set.

## 3. What the measurement found

| # | Gesture | Result | Can a person see it? |
| --- | --- | --- | --- |
| 1 | Typing, Tab and Escape in the composer, with the focus in the draft | one path | — |
| 2 | Return in the composer: submit the draft | the submitted part keeps its caret, `.content.value{5}`, when it moves into the transcript | no: one caret is drawn, in the new draft |
| 3 | A submit that a script or an MCP client evaluates while the focus is on a file | `reset_draft!` writes the draft's caret; the root's path does not pass through the draft, so the caret stays off the path | **yes: a caret is drawn in the draft while the focus is on the file** |
| 4 | A composer edit (`ComposerInsertPartOperation`) that a script evaluates while the focus is on a file | the new insertion keeps its own caret off the path | no |
| 5 | Ctrl+O: reload a file | the file's own selection is `nothing`, and the root's path still passes through the file into its content | no: Ctrl+S still reaches the file, and the next keys answer as they did before the reload |
| 6 | The Evaluator button opens an evaluator | the new evaluator has the caret of its first form as its own selection; the root's path ends at its tab | yes, and it is what a person expects: the caret is drawn and a key reaches the form. The rule is broken without an effect. |
| 7 | Return, Up and Down in the evaluator | one path | — |
| 8 | A press on a file in the navigator | one path | — |

**Not reachable from the window:** the assistant's `input` field. No code in
either repository builds `SubmitProseOperation`, `SubmitJuliaOperation`,
`ClearInputOperation` or `ResetConversationOperation`; only `McpTest.jl` and
`AssistantMvpTest.jl` do. So `_set_input!`, which writes the input's caret below
the root, is not measured.

**Outside the editor's document:** the command palette keeps its document in the
decorator's state, and the file-system view writes the selection of a computed
document, a projection's output. Neither is in the editor's document tree, so the
measurement can not see them, and the rule does not reach them.

**In short:** one finding is visible (#3), and only when a script or a client
submits while the person works elsewhere. Finding #6 is a case of composition,
part 3 of the earlier plan: the open of a pane does not carry the content's own
selection into the root's path, as it does for an empty placeholder. The other
three break the rule with no effect that the measurement found.

## 4. Decisions (2026-09-23, the owner)

The owner dropped the general program of part 2 and decided a local fix for each
finding. None of them needs a new mechanism.

- **#3 and #4 — a draft keeps a dormant caret.** A `ConversationDraft` answers
  `has_dormant_selection`, as the pane and widget containers do. When the root's
  live path passes through the draft, `sync_draft_selection!` writes the caret
  from the root, as it does now. When it does not, the caret is written live from
  the root and the live selection is written back at once, both with
  `replace_selection!` at the root. At that second write the kernel keeps the
  abandoned branch as dormant, because the draft is a keeper, so the draft and
  every keeper above it name the new caret. A dormant caret is not drawn, and it
  is live again when the focus comes back to a keeper on its branch. The search
  for the draft's path from the root enters documents and collections only, so it
  does not find the draft through an operation that a history records.
- **#2 — a part that leaves the draft holds no caret.** `reset_draft!` clears the
  selection of the parts it takes out, which the submit has moved into the
  transcript.
- **#5 — a reload selects the file as a whole.** The reader answers the reload
  with a `ReplaceSelectionOperation` of the whole file, in one
  `CompoundOperation`, and the readers above reroot it (the owner's Option 1, for
  this one reader). The evaluation no longer sets `file.selection = nothing`.
- **#6 — a new tab brings its content's own selection.** When a document that
  holds a selection of its own is opened in a tab, the focus goes to the tab's
  content and on along that selection, so the root's path holds it. This is part
  3 of the earlier plan: the code that puts a document into a larger tree makes
  the new root hold the selection the document had.
- **The unused `input` operations of the assistant are kept unchanged.** They can
  not be reached from the window, and removing exported operations is a change of
  the API that is not part of these fixes.

## 5. Steps

### Step 0 — measure and collect
- [x] A test set that does each gesture in the application window and checks one
      path, no stray and the drawn carets; a broken case for each finding.
      Measured on 2026-09-23 (§3).

### Step 1 — the owner decides
- [x] Decided on 2026-09-23 (§4).

### Step 2 — a draft keeps a dormant caret (#3, #4)
- [x] `has_dormant_selection(::ConversationDraft)`; `sync_draft_selection!` keeps
      the caret dormant when the root's path does not pass through the draft
      (`_keep_dormant_caret!`). It copies the live path before the first write,
      because a write changes the cells of the stored path in place. With no
      live selection, or when the document does not hold the draft, it writes
      nothing.

### Step 3 — a part that leaves the draft holds no caret (#2)
- [x] `reset_draft!` clears the selection of the parts it takes out. Steps 2
      and 3 are one commit, because both change `ConversationEditor.jl`.

### Step 4 — a reload selects the file as a whole (#5)
- [x] Ctrl+O answers `CompoundOperation([ReloadFileOperation(file),
      ReplaceSelectionOperation(EmptyReference())])`, and the reload no longer
      writes a selection. A script that evaluates `ReloadFileOperation` alone
      moves no selection.

### Step 5 — a new tab brings its content's own selection (#6)
- [x] `_make_new_tab_cursor` focuses along the content's live selection when the
      content holds one. This also removes a limit that the conversation guide
      recorded: Ctrl+V of text into a fresh evaluator did nothing until a click
      placed the caret. It now reaches the form (tested).

### Step 6 — tests, suites and guides
- [x] The six broken cases pass and are `@test`; a new check: the dormant caret
      is live again when the focus comes back to the assistant, and a text paste
      reaches a new evaluator. `test_application` 285/285.
- [x] Suites: `test_conversation_editor` 40/40, `test_conversation_transcript`
      120/120, `test_assistant_composer_panel` 67/67, `test_evaluator_toplevel`
      205/205, `test_pane_surgery` 92/92, `test_pane_gestures` 73/73,
      `test_pane_to_widget` 44/44, `test_pane_construct` 50/50, `test_clipboard`
      201/201, `test_widget_selection` 91/91, `test_window_shell` 83/83,
      `test_mcp_server` 13/13, `test_kernel` with its six known failures.
      `test_conversation` (1 failure, the layering check on an import of
      `make_insertion_document`) and `test_assistant_mvp` (4 failures, the boxes
      of "the assistant card fills its page") fail the same way on `main`
      (`6d4fda3f`), measured in the same worktree. omnet-julia, in the scratch
      environment: `test_campaign_ui` 188/188, `test_select_and_paste` 86/86 and
      the other IDE, session, Qtenv and presentation suites pass. The naming,
      argument and tree guards pass; the documentation guard flags no sentence
      that this work wrote.
- [x] Guides: `kernel/selection.md` names the draft among the keepers;
      `conversation/transcript.md` and `conversation/conversation.md` describe
      the dormant caret, and the limit on a paste into a fresh evaluator is
      gone; `pane/pane.md` says where a new tab's focus goes;
      `fileformat/fileformat.md` says what Ctrl+O selects.
