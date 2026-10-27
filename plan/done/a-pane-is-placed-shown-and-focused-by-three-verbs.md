# A pane is placed, shown and focused by three verbs

> Status: done (2026-10-27), on the branch `aloha-video`, not landed. Branch `aloha-video`, worktree `projectured-julia-aloha-video`,
> with the omnet worktree `omnet-julia-aloha-video` for the verbs of a study.
> The Aloha video (omnet `plan/pending/the-video-of-the-aloha-study-by-a-real-agent.md`)
> waits for it: its take 2 runs on this model.

## 1. The request

Take 1 of the Aloha video (2026-10-27) hid the conversation for its last seven
minutes. The agent opened a plot with `open_pane!` and no target, the plot went
into the group of the plan of work above the conversation, because that group
had the focus, the agent put a second plot below it, and then it set the weights
of the column so that the plots were large enough.

The owner, 2026-10-27, on the long term: "what are the correct verbs and behavior
that combines. Bringing something in front is a separate step, so it should not
be automatic because often times in the future it will just cause issues." The
owner agreed with this split: `open_pane!` places, `show_pane!` shows,
`focus_pane!` shows and moves the focus.

## 2. Facts (2026-10-27)

- A group shows the tab that the `selection` of the group names
  (`get_pane_shown_tab_index`). A group that loses the focus keeps its selection
  as a dormant one: a `SelectionDocument` with `live = false` in its `selection`
  cell. Every focus move and every tab switch is one `ReplaceSelectionOperation`
  of the root ([pane.md](../../documentation/package/platform/pane/pane.md)).
- `open_pane!` fuses three steps: it inserts the tab, shows it, and moves the
  selection of the window to it (`make_pane_open_tab_operation`: "Insert `tab`
  … and focus it"; pane.md: "A new tab takes the focus").
- `focus_pane!` fuses two steps: it shows the tab and moves the selection.
- With no target, `open_pane!` puts the tab into the focused group, never into
  the group that `pane_group_to_avoid` names, and only into a group every tab of
  which `accepts_opened_file` while one exists (`_find_placement_group`). A group
  with the Explorer and the study is not free, and the group of the plan of work
  is, so the plot went there.
- No operation writes the dormant selection of a group from outside.
- The callers: `make_open_pane_operation` has four callers outside the pane
  slice (the navigator, two file opens, the window chrome); `open_pane!` is in
  the docstrings and the code of 21 files of projectured and 7 of omnet.

## 3. The model

| Step | Verb | Operation | What it changes |
|---|---|---|---|
| Place | `open_pane!(document; title, target, side, group)` | `make_open_pane_operation` | A new tab at the end of its group. The tab that the group shows and the selection of the window stay. A group that the open makes shows its one tab. |
| Show | `show_pane!(tab)` | `make_show_pane_operation` | The tab that the group of `tab` shows: the selection of the group names it. The selection of the window stays, unless it is in that group: then it moves to the tab, because a group shows the tab that its selection names. |
| Focus | `focus_pane!(tab)` | `make_focus_pane_operation` | As now: the tab shows and the selection of the window moves to it. |

**Placement by role.** With no target and no group, `open_pane!` puts the tab
into a group of documents: a group that is not the one `pane_group_to_avoid`
names and that has a tab whose document `accepts_opened_file`. Of these, the
focused one, else the first in the order of the tree. With no such group, the
rule of today. A split happens only when the caller gives `side`.

**A gesture of a person composes.** A file that a person opens from the
Explorer, a page of the navigator, a command of the window chrome: each is a
place and a focus, as a person expects. So their operations compose the two.

**An agent** places with `open_pane!` and shows with `show_pane!` what it wants
the person to look at; it never calls `focus_pane!`, so it never moves the
selection of the person.

## 4. Steps

### Step 1 — place only

- [x] `make_pane_open_tab_operation` and `make_pane_split_operation` take
      `focus = true`; `_make_open_pane` passes it; `open_pane!` passes `false`,
      and `make_open_pane_operation` takes `focus = false` for the callers of
      step 3. A new group needs no selection: a group with none shows its first
      tab.
- [x] A fact found on the way: a selection names a tab or an element of a split
      by its index, so an insert before it makes it name another one. With
      `focus = false` the surgery keeps each selection on what it named:
      `_make_insert_selection_shifts` moves the focus (a root
      `ReplaceSelectionOperation`) or the dormant selection of the owner one
      element on, and `_make_wrap_selection_moves` gives the focus its path
      through a split that takes the slot of its group.
- [x] `_find_placement_group` by role: a group of documents is empty or holds a
      tab that `accepts_opened_file`; the focused one, else the first in the
      tree; with none, the rule of before.
- [x] Tests in `test_pane_surgery`: an open with no focus, before and after the
      focused tab; a split with no focus, as a sibling and as a wrap; the
      placement with the focus in a side area. 122/122.

### Step 2 — show

- [x] `make_pane_show_operation(tree, group, index)` in the surgery,
      `make_show_pane_operation(reference)` and `show_pane!(tab)` in the
      program. No new operation type, as the surgery file requires: the show is
      `ReplaceViewStateOperation(ReplaceReferencedValueOperation(nothing,
      <group>.selection, SelectionDocument(primary = .tabs[i], live = false)))`,
      a view state and no step of the undo. In the focused group it is the
      focus move. `show_pane!` is in `make_pane_api`.
- [x] Tests: a show in a group without the focus, a tab placed before the shown
      one, a show in the focused group. The frame of a show is checked in
      step 5.

### Step 3 — the gestures and the callers

- [x] Done (projectured `d6d711e62`, omnet `03e4bfcbb`):
  - A press of a person passes `focus = true` to `make_open_pane_operation`:
    the page of a navigator, the two opens of a file, the tool of the window
    chrome (projectured), and the new runner, the Open buttons of the project
    page, the project page of a runner and the run card of a result file
    (omnet).
  - A verb whose name says that it shows opens when no tab shows its document
    and then shows, with no focus: `show_document!` (the seam of the `show_…`
    verbs), `show_assistant_work!`, and omnet `open_project_page!`.
  - The verbs that place only: `start_study!`, `start_workflow!`, and the
    examples of the docstrings that place a document. `open_page!` runs the
    command "Open as a page" of a person through `OpenPageOperation`, and its
    tab opens a frame later, so it keeps the focus of that command; a form
    that answers the tab, for a program, is an open item.
  - `accepts_opened_file(::WorkflowStep) = false`.
  - omnet `_open_study_pane!`: the new group shows its first tab, the study,
    with no focus; the focus goes back to its tab, or, when that tab is in the
    new group, the show moves it to the study. The other branch places the two
    tabs and shows the study.

### Step 4 — the guides and the agent

- [x] Done: pane.md (the focus, the table of builders, the verbs, the
      placement, the example), the docstrings of `open_pane!`, `focus_pane!` and
      `show_pane!`, `make_pane_api`; `InterfaceApiTest` counts the interface
      names only, so it does not change. The orientation guide, the workflow
      guide and the omnet assistant guide; the system text of the assistant of
      every window (`Application.jl`) and of the IDE (`IdeWindow.jl`).

### Step 5 — check

- [x] The suites (2026-10-27). `test_platform()`: 173 615 pass, the three
      failures of main (the layering guard, now also naming `ShellModule.jl`,
      and the two of `InterfaceApiTest`), 7 broken; three tests read the old
      behaviour and now show what they open or read the shown tab (the two
      roster tests, the test of `show_document!`, and in the umbrella the
      split of `open_pane!`). `test_workflow()` 314/314; `test_assistant_verbs`
      79/79, `test_referenced_document_editor` 112/112, `test_search_corpus`
      6/6, `test_search_ranking` 27/27, `test_call_site` 20/20; omnet
      `test_study_verbs` 68/68, `test_assistant_study_window` 21/21,
      `test_task_verbs` 85/85.
- [x] The layout of take 1 as a test, in place of the scripted Aloha pictures,
      whose script opens no plot: omnet `test_assistant_study_window` (`656cd8c81`)
      puts a `WorkflowStep` above the conversation, gives it the focus, and
      opens a pane with `open_pane!`. The pane goes to the group of the study,
      behind the study; the column keeps the plan and the conversation; the
      focus stays in the plan; `show_pane!` brings the pane to the front and
      leaves the focus. 27/27.

## 5. Open items

- `open_page!` runs the command "Open as a page" of a person through
  `OpenPageOperation`, and its tab opens a frame later, so it moves the focus. A
  form for a program that places the page and answers its tab is not built.

## 6. Not in this plan

A rule that shows a tab when a verb changes its document (the owner refused an
automatic show); a minimum share of the conversation in its column; a person's
command to show a tab without the focus.
