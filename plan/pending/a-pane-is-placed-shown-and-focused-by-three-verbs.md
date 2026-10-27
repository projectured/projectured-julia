# A pane is placed, shown and focused by three verbs

> Status: pending. Branch `aloha-video`, worktree `projectured-julia-aloha-video`,
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

- [ ] `make_open_pane_operation` and `open_pane!` insert the tab and move no
      selection; a group that the open makes, by `side` or empty, selects its
      tab as a dormant selection, so it shows it. The surgery operation
      `make_pane_open_tab_operation` keeps its focus move for the gestures that
      use it, such as a drop of a dragged tab.
- [ ] `_find_placement_group` by role, as in section 3.
- [ ] Tests: a placed tab does not show and leaves the selection; a placed tab in
      a new group shows; with the focus in a side group (the plan of work), the
      tab goes into the group of documents; with no group of documents, the rule
      of today.

### Step 2 — show

- [ ] `make_show_pane_operation(reference)` and `show_pane!(tab)`: one operation
      of the pane slice that writes the selection of the group of the tab, as a
      dormant one when the live selection is not in the group, and as a
      `ReplaceSelectionOperation` of the root when it is. No step of the undo,
      as a focus move is none.
- [ ] Tests: a show in a group without the focus changes what it shows and not
      the selection of the window; a show in the focused group moves the
      selection; the frame draws the shown tab.

### Step 3 — the gestures and the callers

- [ ] The four callers of `make_open_pane_operation` compose the place and the
      focus. The 21 files of projectured and the 7 of omnet that name
      `open_pane!`: each call keeps the place only, or adds `show_pane!` where
      showing is the purpose of the call, as in an example of a docstring that
      ends in a look at the tab.
- [ ] `accepts_opened_file(::WorkflowStep) = false`: the plan of work is a side
      area, as the Explorer is.
- [ ] omnet `_open_study_pane!` shows the tab of the study with
      `show_pane!`'s operation, in place of a focus and a focus back.

### Step 4 — the guides and the agent

- [ ] pane.md, the docstrings of `open_pane!`, `focus_pane!` and `show_pane!`,
      and the list of the interface (`make_pane_api`, `InterfaceApiTest`).
- [ ] The guide of the assistant and the system text of the IDE: place with
      `open_pane!`, show with `show_pane!` what the person must look at, never
      `focus_pane!`.

### Step 5 — check

- [ ] `test_platform()`, `test_workflow()`, the omnet suites of the IDE
      (`test_study_verbs`, the assistant study window), and the scripted Aloha
      pictures in the scratch environment: the plots go to the group of the
      study, and the conversation keeps its column.

## 5. Not in this plan

A rule that shows a tab when a verb changes its document (the owner refused an
automatic show); a minimum share of the conversation in its column; a person's
command to show a tab without the focus.
