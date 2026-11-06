# The assistant wakes until a long work ends

> **Kind:** plan · **Status:** a plan, written 2026-11-05 from a survey of
> projectured-julia `main` at `de6b4e95d` and omnet-julia `main` at `f7b41c034`,
> and re-checked at projectured-julia `main` `6b93bfcf3` and omnet-julia `main` `a1dfa5af3`.
> Nothing is built. · **Stands on:**
> [assistant.md](../../documentation/package/platform/assistant/assistant.md),
> [task.md](../../documentation/package/platform/task/task.md),
> [agent.md](../../documentation/package/kernel/agent.md),
> [an-assistant-carries-a-long-study-to-its-end.md](an-assistant-carries-a-long-study-to-its-end.md)
> (built, merged), inet-cpp `plan/pending/ieee80211-chart-baseline-evolution.md` §9.3, gap G9 ·
> **Related plans:** [the-assistant-starts-programs-as-tasks.md](the-assistant-starts-programs-as-tasks.md)
> (G1, written the same day); [the-assistant-finds-its-names-by-reflection.md](the-assistant-finds-its-names-by-reflection.md)
> (branch `reflection-api`; steps 1 to 4 are on main `2bbc18fb5`, and steps 5 to 7 are on main since `0836ec536` to `40fca6884`). The owner decided on 2026-11-05 that steps 1 to 4 of
> `reflection-api` land on main first, and that this plan starts from main after that.
> Steps 1 to 4 landed on main `2bbc18fb5` (omnet-julia `991a89b4f`) on 2026-11-05, and `origin/main` holds them.

A walk over about 60 commits runs for 5 hours in the window of `omnet_ide`. Each commit
is one task group, and the end of each group must wake the assistant. Today the window
wakes it at most 3 times after a message of the person. When this plan is done, the
person allows the wakes that the work needs, sees how many are left, and stops them at
any time. A loop of the model can not spend more turns than the person allowed.

## 1. What exists

Each row was checked in the code on 2026-11-05, and again at projectured-julia `main`
`6b93bfcf3` and omnet-julia `main` `a1dfa5af3`.

| What | Where | What it does |
| --- | --- | --- |
| The limit | `ASSISTANT_WAKE_LIMIT = 3`, `source/platform/assistant/AssistantWake.jl:18` | The count of wakes after one message of the person. |
| The watch | `_watch_turn_task_groups!`, AssistantWake.jl:33-52, called at `AssistantTurn.jl:957` and `ExternalAgentTurn.jl:192` | At the end of a turn, a waiter task waits for each group that started during the turn and still runs. |
| The wake | `wake_assistant!`, AssistantWake.jl:67-75 | It always adds a `:wake` note turn. It starts a turn only when `_is_wake_allowed` answers true. |
| The rules | `_is_wake_allowed`, AssistantWake.jl:84-94 | False while the draft has text, after a `:cancelled` turn since the last message, and after 3 `:wake` notes since that message. |
| The switch | `wake::Bool`, `AssistantDocument.jl:167`, default `false` at :240, kept by the `.pred` file at :310 | Off by default. |
| The rounds | `max_rounds`, AssistantDocument.jl:166; the note and **Go on**, AssistantTurn.jl:1035-1047 | Only a turn of a model has a round budget. An external agent runs its own loop. |
| The note | `ConversationNote`, `source/platform/conversation/ConversationDocument.jl:216`; its row, `ConversationToWidget.jl:350-356` | One fixed line and at most one button. |
| A message that waits | `_has_waiting_message`, AssistantTurn.jl:427-430; the launch at :349-350 | A user turn after the turns that the turn read starts the next turn. |
| The stop | `CancelAssistantTurnOperation`, AssistantTurn.jl:77 and :367; the stop of a code unit makes it too, :362-365; the button, `AssistantToWidget.jl:378-383` | The button is enabled only while a turn runs. |
| The row under the composer | AssistantToWidget.jl:94-107 | Stop and picture; for an external agent also work, the option menus and the usage. |
| A stopped group | `stop_task_group!` sets `group.stopping = true`, `source/platform/task/TaskGroup.jl:556-566`; a start sets it false, :409 | The group records the stop. |
| The wait of a model | `wait_for_tasks!`, `source/platform/task/TaskVerbs.jl:416-451` | Its docstring tells the model to end the turn for a long group. |
| omnet_ide | `IDE_ASSISTANT_ROUNDS = 24`, `source/ide/IdeWindow.jl:54`; `wake = true` at :316 and :339; `IdeWorkload.jl:200` | The window and its workload make an assistant with the wake on. |
| The study verbs | `wait_for_run_card!`, `source/ide/StudyVerbs.jl:529-573`; the section "The runs go on without you" of the guide, `documentation/guide/assistant-guide.md:606-621` | They tell the model to end the turn and wait for the wake. |
| The test | `test_assistant_wake()`, `test/platform/conversation/AssistantWakeTest.jl:32`, in `test_conversation()` | Four cases: a wake, the switch off, an external agent, the three rules. |

## 2. What does not exist

1. **No grant for long work.** The walk stops after 3 groups until the person types.
2. **No statement of why.** A note that starts no turn has the same text as a note that
   starts one. Nothing shows how many wakes are left.
3. **The hold leaks while a turn runs.** A held note is a user turn at the end of the
   conversation. When the turn that runs ends, `_has_waiting_message` starts a turn with
   the held note. So text in the draft, or the limit, does not stop that turn.
4. **No stop between turns.** While a group runs and no turn runs, the Stop button is off.
5. **A stopped group wakes the assistant.** A group that the person stopped in the Tasks
   pane ends, and the assistant can start it again.

## 3. The options

The use case: about 60 commits, one group for each commit, about 70 wakes with the
bisections, 5 hours, nobody at the window, and a person who can look, type or stop.

| Option | What the person does | Behavior in the walk | Bound on a loop of the model |
| --- | --- | --- | --- |
| **A. A count that the person allows** | Types 100 in the count once | Runs to the end. Stops with a note when the count is used. | The count. Each turn of a model also has its rounds. |
| B. A time that the person allows | Picks "until 23:00" | Stops at the time, also when the walk is half done. | None in the time: 10-second failed builds can wake 1000 times. |
| C. Tokens that the person allows | Gives a count of tokens | The person can not size it for 60 commits. | The editor can not count it for all backends. An external agent reports its context and an optional cost. The conversation keeps no tokens of a model, and a local model costs nothing. |
| D. A wake that belongs to a declared work | Approves a workflow, or sets the work state to "in progress" | Runs until the work is done. | None inside the work. The platform can not read a workflow, which is a domain above it. The assistant writes the workflow and can keep it open. |
| E. A wake only after progress | Nothing | A range of commits that do not build stops the walk. | Weak: a loop that starts a group at each wake shows progress by any measure that the editor can read. |
| F. A larger limit that the window sets | Nothing | Runs to the end. | The window, not the person, gives the consent. The limit holds for any work, also short work. |

**Decided by the owner on 2026-11-05: A.** The assistant recommended it: The editor starts the turn, so the
editor can count turns for every backend. The person can size the count from the work
("60 commits, about 70 wakes"). The count bounds a loop. Each wake note gives the count
to the model too, so the model can tell the person early when the count is low. From D
the design keeps one idea: the model names the work and its size in prose.

The walk with A:

1. The person asks for the walk. The row under the composer reads "Wakes left: [ 3 ]".
2. The model says that the walk needs about 70 wakes. It starts group 1 and ends the turn.
3. The person types 100 in the count under the composer. The person goes away.
4. Each group end adds a note, "… ended: 1 of 1 done, in 4 min 12 s. Wakes left: 102.",
   and starts a turn. The model records the result and starts the next group.
5. The person asks a question at commit 20. The count stays at its value.
6. A build fails at commit 31. The note names the failure, and the model records it.
7. The person presses Stop during a turn. The count goes to 0. The next group end adds a
   held note, "The assistant does not wake: you stopped the last turn.", with **Go on**.
8. The walk ends with 20 wakes left. The person sets the count to 0, or keeps them.

## 4. Decisions

The owner decided D1, D3, D11 and D12 on 2026-11-05. The assistant proposed D2 and D4 to D10.
A decision that the assistant proposed counts as approved when the owner approves this plan for
implementation (the owner, 2026-11-05). The owner can name one to see it first.

- **D1. The unit is a count of wakes.** The owner decided this on 2026-11-05 (option A).
  Section 3 gives the reasons.
- **D2. One count, `wakes_left`, a field of the `Assistant`.** A message of the person
  raises it to at least `ASSISTANT_WAKE_LIMIT`, and never lowers it. A wake takes one. A
  stop of a turn sets it to 0. With no grant, this gives the same behavior as today.
- **D3. Only the person sets the count.** The owner decided the control on 2026-11-05 (open
  question 4, option B). A `WidgetSpinBox` in the row under the composer, "Wakes left: [ 70 ]",
  shows the count and sets it to any number from 0. An edit makes
  `SetAssistantWakesOperation(assistant, count)`. The value 0 stops the wakes, so a stop needs
  no operation of its own. No name with the mark reaches the operation, and no verb of the model
  sets the count. A count that the model can raise bounds nothing. Rejected: a menu with the
  fixed picks "Allow 10 / 30 / 100 more" and "Stop the wakes", and the menu with a typed field
  too. The count is one value, so one control shows it and sets it.
- **D4. The spin box is the live statement**: it shows the count as it falls. Every assistant
  shows it (D12).
- **D5. A held note says why.** Its kind is `:wake_held`, a new value of the field `kind`.
  It has the **Go on** button of `send_go_on!`. Its text ends with "The assistant does not
  wake: " and the first reason that holds:
  1. "you have a message that you did not send";
  2. "a stop ended the group";
  3. "you stopped the last turn";
  4. "it has no wakes left".

  A note that wakes ends with "Wakes left: N.".
- **D6. A held note never starts a turn later.** `_has_waiting_message` skips a turn of
  `:wake_held` notes. The model reads the held note with the next message of the person.
- **D7. A raise of the count while the conversation ends with a held note** and no turn runs
  starts a turn with that note. The raise is the act of the person, so it takes no wake.
- **D8. A failed group wakes. A stopped group does not.** A commit that does not build is
  a result of the walk. A group with `stopping` set ended by a stop. The stop came from
  the person, or from the model in a turn. In both cases a wake is not necessary.
- **D9. A restart starts at 0.** `wakes_left` is live state, as `status` is. A `.pred` file
  does not keep it, and a fork starts at 0. The watches are tasks of the process, so the new
  window does not wake for groups of the old one. The person at the restart types, and
  allows wakes again. The work goes on from its record: the walk writes each commit into its
  workflow and its table before it starts the next group.
- **D11. A turn that used its rounds goes on by itself while wakes are left.** The owner
  decided this on 2026-11-05 (open question 2, option A). The editor starts the next turn and
  takes one wake, and the note reads "The turn reached its 24 rounds. Wakes left: 55." With no
  wakes left, the note keeps its **Go on** button, as now. The rule is the same as for a group
  end: a continuation without the person takes one wake. An external agent has no round
  budget, so D11 does not apply to it. Rejected: the note as now, and a decision in a later plan.
- **D10. omnet_ide sets no count.** Only the person sets the count (D3). `omnet_ide` stops
  setting `wake = true` (D12), in `IdeWindow.jl` and `IdeWorkload.jl`.
- **D12. The switch `wake` goes, and the count is the one gate.** The owner decided this on
  2026-11-05 (open question 3, option A), with no regard to compatibility or the decision of
  2026-10-24. Every assistant wakes when a group that it started ends, at most
  `ASSISTANT_WAKE_LIMIT` times after each message, unless the person allows more or stops the
  wakes. The reasons: a window author can not forget a flag that does not exist; the count bounds
  a loop and the notes say why a turn came, which were the two reasons for the switch; and one
  count covers every kind of wake, also D11 and later kinds such as a changed file or a timer.
  The field `wake`, its default and its keyword in the `.pred` file go. Rejected: the switch as
  a second gate, which hides the count in each window that does not turn it on.

## 5. Steps

Each step is one commit with its test. No step changes a sealed file: SEALING.md covers
only `source/kernel/`, and every file here is under `source/platform/` or `test/platform/`.

- [x] **1. The count of wakes left.** `wakes_left` in `AssistantDocument.jl`, out of
      `pred_arguments` and out of a fork. `SubmitDraftTurnOperation`, `SubmitProseOperation`,
      `EvaluateDraftTurnOperation` and `send_go_on!` raise it. `wake_assistant!` takes one.
      `CancelAssistantTurnOperation` sets 0. `_is_wake_allowed` becomes a function that finds
      the reason of a hold, or `nothing`. Test: `test_assistant_wake()`. The case of the
      limit starts from a message. New cases: a message keeps a count above 3; a stop sets
      0; a `.pred` round trip has no `wakes_left`.
      What the implementation found:
      - `wakes_left` has no constructor keyword: no caller sets it, and a test writes the field.
      - `_is_wake_allowed` became `_find_wake_hold_reason`, which answers `:draft`,
        `:stopped_turn`, `:no_wakes_left` or `nothing`. "The last turn was stopped" holds
        only while no message of the person follows the stopped turn, so a raise of the
        count by the person is not held again by an old stop.
      - A stop sets 0 only while a turn runs (the operation does nothing otherwise).
- [x] **2. The note says the count or why.** `:wake_held`, the four reasons, **Go on**, the
      check of `stopping`, "Wakes left: N.", and the skip in `_has_waiting_message`. Test:
      `test_assistant_wake()`. New cases: a group ends while a turn runs and the draft has
      text, and no turn starts after that turn ends; a stopped group adds a held note with
      its reason; each wake note names the count. Also `test_external_agent_turn()`,
      because a held note must not steer a prompt that runs.
      D11 is in this step too: `_finish_turn!` with `:round_limit` and wakes left starts the
      next turn and takes one wake. New cases: a turn at its rounds with 2 wakes left goes
      on and leaves 1; with 0 left, the note keeps **Go on** and no turn starts.
      What the implementation found:
      - D11 continues with a user turn "Go on." pushed after the turn (the model needs a
        user turn to answer, and `_has_waiting_message` starts the next turn with it). The
        turn takes one wake in `_make_round_limit_note`, which now words "Wakes left: N." and
        has no button; with 0 left the note keeps **Go on**. The continuation is not a
        message of the person, so it does not raise the count.
      - Because a message now gives 3 wakes, `test_assistant_rounds` zeroes `wakes_left` in
        its `probe` tool to get the note with its button.
      - `_has_waiting_message` looks for the last turn that is not a held-wake note.
      - The hold reasons live in the tuple `_WAKE_HOLD_REASONS`.
- [ ] **3. The count under the composer.** A `WidgetSpinBox` over `wakes_left` in the row of
      `AssistantToWidget.jl`, `SetAssistantWakesOperation`, and D7. Test:
      `test_assistant_wake()`. New cases: the spin box follows the count as wakes take it; an
      edit to 70 sets 70; an edit to 0 stops the wakes; a raise with a held last note starts a
      turn and takes no wake; every assistant has the spin box. Also
      `test_external_agent_turn()` and `test_assistant_mvp()`, which read the row.
- [ ] **3a. The switch goes (D12).** Remove the field `wake` from `AssistantDocument.jl`, its
      default and its `pred_arguments` keyword, and the check of the switch in
      `wake_assistant!`. In omnet-julia, remove `wake = true` from `IdeWindow.jl` (two places)
      and `IdeWorkload.jl`, in the same landing. Test: `test_assistant_wake()`, whose case
      "the switch off" becomes "an assistant with 0 wakes left adds a held note"; then
      `test_conversation()`, and in omnet-julia the IDE assistant tests. A test that starts a
      group and expects no turn after it now gets a wake: such a test sets the count to 0.
- [ ] **4. The texts.** The docstrings of `ASSISTANT_WAKE_LIMIT`, `wake_assistant!`, the
      `Assistant` and `ConversationNote`. The docstring of `wait_for_tasks!` gets one
      sentence: for work of many groups, tell the person how many wakes it needs; the
      person allows them under the message box. The guides: "The wake" in assistant.md and
      "A wait has a deadline" in task.md. In omnet-julia, the section "The runs go on without you" in
      `documentation/guide/assistant-guide.md` gets one sentence: for long work, say how many wakes
      it needs. Test: `test_referenced_document_editor()`,
      because the docstring of a declared verb can move the rank of `search_api`;
      `test_assistant_documentation()`; `test_documentation()`.
- [ ] **5. A live check in omnet_ide, with no code.** Run the window with an external
      agent through `workspace/bin/bounded-run` on a copy of a small project. Ask for six
      stages, each a run card of a short configuration, and allow 10 wakes. Check six wake
      notes, the count at 4, then a held note after the person sets the count to 0. Record the
      result here.

## 6. Risks

- **The row gains a spin box.** A test that counts the items of the row fails:
  `test_external_agent_turn()`, `test_assistant_mvp()`. The omnet-julia workload builds
  an assistant (`IdeWorkload.jl:197`), so its print of the row covers the spin box. After D12,
  the workloads of projectured-julia print it too, so their recorded lists change.
- **Every assistant wakes (D12).** A test or an example that starts a group in a turn now gets
  up to 3 more turns. `test_conversation()`, `test_assistant_mvp()` and the IDE tests show it.
- **The skip of D6 changes when a turn starts.** `test_conversation()` covers the
  messages that wait, and `test_external_agent_turn()` covers the steer.
- **The docstring of `wait_for_tasks!` can move the rank of `search_api`.**
  `test_referenced_document_editor()` shows it.
- **The count guards against a loop. It is no lock.** Code that the model runs can
  write a field of a document that it finds. Rule 1 and the guides forbid it. The two
  operations carry no mark, so no name offers them to the model.
- **A turn of an external agent has no round budget of the editor.** The count bounds
  the turns, not the work inside one turn.
- **A group that never ends wakes nothing.** The walk stops with no note. The verb of
  G1 can give a process a time limit.
- **Wakes that the walk did not use stay.** At most that count of turns can come with a
  later group. The spin box shows them, and the value 0 ends them.

## 7. Open questions for the owner

1. **A request from the model.** Answered by the owner on 2026-11-05: prose is enough. The
   question was: a verb could add a note with an "Allow N wakes" button
   that only the person can press. That is a new channel from the model to the person,
   and the verb must know which assistant calls it. This plan uses prose only. Is prose
   enough?
2. **A turn that reached its rounds.** Answered by the owner on 2026-11-05: in this plan (D11).
   The question was: with wakes left, such a turn of a model could go
   on by itself and take one wake. A long turn of a model with nobody at the window then
   does not stop the walk. Add it here, or in a later plan?
3. **The switch `wake`.** Answered by the owner on 2026-11-05: remove it in this plan (D12). The
   question was: rule 6 says that a generic capability has no opt-in flag. With
   the count, the switch adds a second gate. D1 of the long-study plan chose "off by
   default", and the owner agreed on 2026-10-24. Keep it, or remove it in a later plan?
4. **The control of the count.** Answered by the owner on 2026-11-05: a spin box where the person
   types the count (D3). The question was: 10, 30 and 100, or a field where the person types a
   count?
5. **omnet-julia.** Decided by the assistant on 2026-11-05, because D12 already changes
   omnet-julia in the same landing: step 4 writes the sentence. The question was: OT-EXECUTE in its
   assistant guide needs one sentence: for long work,
   say how many wakes it needs. Write a sibling plan, or let step 0 of the parent plan
   carry it?
