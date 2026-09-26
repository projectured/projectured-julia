# A new pane skips a navigator group

## Problem

A toolbar tool button (Explorer, Evaluator, Message log, …) and the Help and
View commands open their tool with `open_pane!`, through `_reach_tool!`. The
group comes from `_find_placement_group`:

- the focused group, unless `pane_group_to_avoid(tree)` names it;
- else the first group in depth-first order, which is the leftmost group.

The application window is `[Files 0.18 | files 0.5 | Assistant 0.32]`. The focus
is in the Files group at start when no file is open, and after a click in the
navigator. A plain click on a toolbar button does not move the focus. So the
tool opens in the thin Files group. The new tab takes the focus, so the next
tool opens there too.

A file opened from the navigator does not have this problem.
`get_pane_file_group` skips a group that holds a tab whose content answers
`false` to `accepts_opened_file`. `Workspace` and `Assistant` answer `false`.
The two paths use two different policies.

## Decision

Step 1 only (the owner chose this on 2026-09-26):

- `_find_placement_group` takes a group only when every tab in it
  `accepts_opened_file`, while such a group exists. The rest of the policy
  stays: the focused group if it is a candidate, else the first candidate.
- No record of the group that had the focus last. The owner said that this
  new mechanism is not necessary.
- No choice by area. No rename of `accepts_opened_file`. `pane_group_to_avoid`
  stays.

## Steps

- [x] 1. `_find_placement_group` filters by `accepts_opened_file`, with one
  helper that `get_pane_file_group` shares. Update the docstrings of
  `accepts_opened_file` and `open_pane!`, and `documentation/package/pane/pane.md`.
  Add a test to `ApplicationTest.jl`: focus on Files, press the Evaluator
  toolbar button, and the evaluator opens in the group of the files.

## Results

- The shared helper is `_is_free_group(group)` in `PaneFile.jl`. A group with
  no tab is free.
- The filter runs after the `pane_group_to_avoid` step. If no group is free,
  the old policy applies unchanged.
- A scenario script pressed the Evaluator button with the focus on Files. On
  `main` the evaluator opened in the group `["Files", "Evaluator"]`. With the
  change it opened in `["a.json", "Evaluator"]`.
- `test_application()`: 345 of 345 pass. The naming guard
  (`julia test/suite/naming.jl`) passes.
- omnet-julia: its `pane_group_to_avoid` avoids a group that holds an
  `Assistant`, and `Assistant` already declines `accepts_opened_file`, so the
  new filter keeps that rule. Its tests did not run, because omnet-julia reads
  projectured-julia from the main checkout.
- File > New tab, the `+` of a tab strip, and a split still act on the focused
  group. They name their group, so the policy of `open_pane!` does not apply.
