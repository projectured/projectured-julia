# An evaluation moves the selection from the root

**Status (2026-09-23): MEASURED. Nothing is fixed.** The owner asked for the
measurement first, and for no automatic fix: "change the plan, first measure and
collect, don't fix automatically anything yet". Step 0 is done. Every later step
waits for the owner's decision on each finding (§4).

**Goal:** know where an evaluation leaves the live selection off the one path from
the root, and which of those places a person can see. A fix comes only where the
owner decides that it is worth one.

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

## 4. Decisions for the owner

For each finding: fix it, or keep it as a broken case. If a fix is made, the owner
prefers Option 1 of the first version of this plan: the reader answers the
selection change as a `ReplaceSelectionOperation`, in one `CompoundOperation` with
the edit, and the readers above reroot it. Option 1 needs a reader, so it can not
fix #3 or #4, which a script evaluates with no reader. For those two the choices
are: write no live caret when the root's path does not pass through the draft, or
let the draft keep a dormant caret, which today only the pane and widget
containers may.

1. **#3, the caret in the draft after a submit off the focus.** The only visible
   finding.
2. **#6, the caret of a new evaluator.** The fix is in the open of a pane: the new
   tab's content brings its own selection into the root's path.
3. **#2, #4 and #5.** No visible effect.
4. **The unused `input` operations of the assistant:** remove them, or keep them
   for scripts.

## 5. Steps

### Step 0 — measure and collect
- [x] A test set that does each gesture in the application window and checks one
      path, no stray and the drawn carets; a broken case for each finding.
      Measured on 2026-09-23 (§3).

### Step 1 — the owner decides
- [ ] A decision for each item of §4.

### Later steps
Written after Step 1, one for each decision to fix. Each one turns its broken case
into a passing test, and runs `test_application`, the conversation, assistant,
evaluator and file-format suites, and in omnet-julia `test_ide` without the two
model tests and `test_campaign_ui`.
