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

1. [ ] **The pane verbs leave the focus.** The move and the drop on an edge take
   `focus`, as the open does; without the focus, the focused tab keeps the focus at
   the place that the move leaves it. The duplicate takes `focus` and passes it to
   the open. A close moves the focus only when the closed tab had it. The program
   verbs pass `focus = false`; a press of a person keeps its focus. Tests of the
   surgery and of each verb.
2. [ ] **The two focus tests.** The Show of the Assistants list composes the show
   with a focus, as a press of a person does. The test of the pane verbs holds
   that `open_pane!` leaves the focus.
3. [ ] **The divider of the Explorer.** Find why a drag of the divider between
   the groups builds the split of the Explorer again, and fix it so the weight
   that a drag gave the Explorer stays.
4. [ ] **A window ends cleanly.** At the end of the loop, a stop step stops the
   external agent of each assistant of the window and waits, a bounded time, for
   the stop of its session and of its MCP server. `stop_external_agent!` keeps the
   task of its stop, so the step can wait for it.

## Decisions

- The rule is not changed: `show_pane!` keeps its one case.
