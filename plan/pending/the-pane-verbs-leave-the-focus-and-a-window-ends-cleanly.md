# The pane verbs leave the focus, and a window ends cleanly

> **Kind:** decision · **For:** developer · **Status:** current · **Stands on:** [pane.md](../../documentation/package/platform/pane/pane.md), [assistant.md](../../documentation/package/platform/assistant/assistant.md)

Four faults that the measurement of `the-assistant-finds-its-names-by-reflection.md`
(step 7) and its test runs found, which the owner asked to fix on 2026-11-05: "Fix
the pane verbs, the 3 failures and the crash, skip the recording".

## Facts (2026-11-05)

- **The rule** (the owner, 2026-10-27, commit `8a0c14f1e`): a verb places or
  changes and leaves the focus of the person. `open_pane!` places a tab behind the
  shown one, `show_pane!` brings a tab to the front, and only `focus_pane!` moves
  the focus. A press of a person composes a place or a show with a focus.
- **`move_pane!` breaks the rule.** It makes the operations of a person's drag,
  `make_pane_move_tab_operation` and `make_pane_drop_split_operation`, which give
  the focus to the moved tab. An ACP agent moved notes.md beside people.json, and
  the focus left the Explorer for notes.md.
- **`duplicate_pane!` and `close_pane!` break it too.** The duplicate focuses its
  copy. A close gives the focus to the neighbour of the closed tab, also when the
  focus was on a tab of another group.
- **`show_pane!` keeps the rule.** It moves the focus only when the shown tab is in
  the group that has the focus, because such a group can show only the focused
  tab; its docstring says so.
- **`test_application` fails at three places on main.**
  - The Show of a row of the Assistants list is a press of the person, and the
    test expects that it focuses the tab. The button only shows it.
  - The test of the pane verbs expects that `open_pane!` focuses the new tab,
    which the rule ended. The test is wrong.
  - A drag of the divider between the groups puts the divider inside the Explorer
    back to its first weight, scaled to the narrower group: `[250, 988]` against
    `[375, 988]`, and 275 × 1000 / 1100 = 250. The drag builds the split of the
    Explorer again.
- **The crash.** The IDE process of the ACP measurement crashed in LLVM while a
  task compiled `close` of the MCP server of the agent: the harness called
  `exit(0)` just after `stop_external_agent!`, whose stop runs on an `@async` task
  that nothing waits for. A real window can meet the same race: no step at the
  end of the loop stops the external agent of an assistant, so the agent, its MCP
  server and its `claude` process live until the process ends.

## Steps

Each step is done in the worktree `projectured-julia-pane-fixes`, runs the
narrowest tests that cover it, and ends with a commit.

1. [x] **The pane verbs leave the focus.** Done. The move and the drop on an edge take
   `focus`, as the open does; without the focus, the focused tab keeps the focus at
   the place that the move leaves it. The duplicate takes `focus` and passes it to
   the open. A close moves the focus only when the closed tab had it. The program
   verbs pass `focus = false`; a press of a person keeps its focus. Tests of the
   surgery and of each verb.
   - Without the focus, the operation writes the change and after it the kept view
     (`_make_kept_view_operation` with `swaps`, `owner => list after`, and `subs`,
     `old node => new node`): the focus stays on its tab, with the rest of the live
     selection inside it, and each group keeps the tab that it showed. The removal
     of an emptied group (`_find_removal_shape`) gives the shape for the kept view.
   - Two old tests of the close had a tree with no focus and expected that the close
     gives the focus to the neighbour. With the rule a close leaves no focus where
     there was none, so the tests focus the closed tab first.
   - The default of each operation stays `focus = true`, because a press of a person
     and the tests of the duplicate of a workspace and of an evaluator expect it.
2. [x] **The two focus tests.** Done. The Show of the Assistants list composes the show
   with a focus, as a press of a person does. The test of the pane verbs holds
   that `open_pane!` leaves the focus.
   - The opener of the list, `_show_and_focus_assistant!`, shows the assistant with
     `show_document!` and then focuses its tab with `focus_pane!`. `test_application`
     passes both places.
   - In a runner that loads every test package in one process, the test "a pane
     that no caller placed does not cover a conversation" fails: the workflow test
     package adds a method `pane_group_to_avoid(tree::PaneTree)`
     (`WorkflowEditsTest.jl`). It passes in the platform suite alone.
3. [x] **The divider of the Explorer.** Done. Find why a drag of the divider between
   the groups builds the split of the Explorer again, and fix it so the weight
   that a drag gave the Explorer stays.
   - The cause (found by experiment: a trace of each print of the Explorer, and a
     snapshot of the cells that the build of each split pane read). The print of a
     tabbed pane read `inner.w` and `inner.h`, which a document answers as the
     values of its cells. The print of a slot runs inside the build cell of its
     split (`_split_build`), so that build depended on the extent of the page of
     each group. A press on the divider between the groups pins the sizes of the
     slots, a page changes its extent, and the split built every slot again: each
     group printed its content again, and the split of the Explorer started over
     with its first weights. The read came with `c3e769c1b` (2026-11-03).
   - The fix: the print passes the cells (`getfield(inner, :w)`), and the extent
     reads them only in its own cells. The same read also froze the extent of a
     tabbed pane with no slot and a minimum at the value of its first print.
   - A second read, which `d8cb5a156` (2026-11-05) added: the build asks each slot
     whether it takes the extent of its child (`_is_split_content_slot`), which
     reads the weight of the slot. A weight of a pane split is a cell that computes
     from the weights of the split, so each move of a drag built the split again.
     With the first fix alone the press built nothing, and the move still did.
   - The second fix: the answers are a tuple of `Bool` in a cell of their own. A
     tuple of `Bool` is plain data, so a new weight that keeps each answer stops at
     that cell, and the build stays valid.
   - The experiment with both fixes: no split builds again at the press, the move or
     the release, and the dividers end at `[371, 988]`, where the drags put them.
     `test_application` passes the divider, the split pane, layout and pane tests
     pass, and the data frame suite passes (608 of 608).
4. [x] **A window ends cleanly.** Done. At the end of the loop, a stop step stops the
   external agent of each assistant of the window and waits, a bounded time, for
   the stop of its session and of its MCP server. `stop_external_agent!` keeps the
   task of its stop, so the step can wait for it.
   - The `AgentEventFeed` holds a source for each open session of an agent, with
     its assistant, so the stop step of the wrapper `agent_event` needs no search
     of the window and no new registry. The step is the form that the wrappers
     `file_change` and `mcp_log` use for their stores. It waits at most 10 s.
   - The test gives a session an MCP server that takes 0.3 s to stop, runs the stop
     steps of the editor, and holds that the agent stopped and that the server
     stopped before the steps ended (`test_external_agent_turn`, 311 of 311).

## Decisions

- The rule is not changed: `show_pane!` keeps its one case.
- `test_application` on main `fb9e8a171` fails at four places: the three of this
  plan and "36k / 1M" (:1001): the usage of an agent draws as three words. It did
  not fail on `2bbc18fb5`, and the layout merge `660b68779` came after; its cause
  is not found. That fourth one is not in this plan.
