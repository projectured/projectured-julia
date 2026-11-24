# A person steps through the commits of a range

> **Kind:** plan · **Status:** done, 2026-11-24; approved by the owner on 2026-11-24 ("yes, implement it") ·
> **Branch:** `commit-steps` (worktree `projectured-julia-commit-steps`) ·
> **Follows:** [the-page-of-a-commit-shows-its-files-as-a-tree-beside-their-diffs.md](the-page-of-a-commit-shows-its-files-as-a-tree-beside-their-diffs.md),
> [a-navigator-with-back-forward-parent-and-links.md](a-navigator-with-back-forward-parent-and-links.md) ·
> **Stands on:** [git.md](../../documentation/package/domain/git/git.md),
> [navigator.md](../../documentation/package/platform/navigator/navigator.md)

## 1. The problem

The owner (2026-11-24): "the git view needs some work in projectured, it needs word wrapping for
the comment parts and we also need a better mechanism to view a sequence of commits. Currently it's
displayed as a table but I can't navigate between the commits. So am I supposed to click on a commit
then brows the changes, then go back and click another commit? How could I simply navigate next
commit/prev commit or any commit in the sequence whatsoever?"

Then, about the bar of the navigator: "the spacing is a bit too large the navigator header goes out
to the right very quick" and "the move to tab pane button is at the right most location, it's often
not even visible and there's no way to scroll there". A screenshot of the IDE showed a commit in
the page of the explorer, with the address cut at `master..topic/baseli`.

## 2. What exists (main `3dcb5f516`)

The assistant checked each row in the code. A headless render of commit `3dcb5f516` and of the range
`HEAD~4..HEAD`, 900 px wide with 8 px for each character, checked the rows about the message.

| Part | What it does now |
| --- | --- |
| The page of a range | `GitCommitRangeToWidget`: a line (revisions, count of commits), then the table of the commits (`range.table`, an `ArrangementDocument` of a `Roster`): hash, subject, author, date. |
| A press on a hash | It opens the commit at its place in the range, `commits[j]` (`retarget_held_row_open`). A navigator takes the open: the navigator of the explorer, or a new tab with a navigator (`Navigator(range, commits[j])`). |
| To see the next commit | Parent (Ctrl+Up) or Back (Ctrl+[), then a press on the next row. No key or button goes to the next or the previous commit. |
| The list of the address | The arrow before an item of the address opens a list of about 50 siblings (`find_navigator_choices`); a word or a number finds one. In a narrow navigator the item of the commit, with its arrow, is out of view. |
| The subject | The header of the commit page wraps it: 690 characters show on 7 lines. |
| The subject in the table | One line, cut at the edge of the column; the row does not grow. |
| The rest of the message | It stands above the diffs in the pane of the diffs, as lines of the kind `:message` of the `GitDiffText`, while the top node of the tree is chosen. It does not wrap. The pane scrolls sideways for the code lines, so its content has no right edge, and `WordWrapping` wraps only at an edge (`ctx.maximum_width`). |
| How the diffs follow the tree | The diffs show the node that the stored selection of the tree names, live or dormant (`_find_chosen_node`, `has_dormant_selection(::GitCommit)`). |
| The bar of the navigator | `NavigatorToWidget`: a `HorizontalLayout` of Back, Forward, Parent, the view switch, the items of the address, and "Open in a tab" at the end, at the width of its content. In a narrow navigator it goes past the right edge. Nothing scrolls it, so "Open in a tab" is out of view. Each item of the address is a `WidgetToolbarItem` with the insets of a button, an arrow item stands before it, and the gap `label_gap` stands between all of them. |
| Free keys | Ctrl+Shift+PageUp and Ctrl+Shift+PageDown are bound nowhere. Ctrl+PageUp and Ctrl+PageDown go to the previous and the next tab. |

## 3. Decisions

The owner, 2026-11-24:

- **D1.** Both ways to move between commits: the list above the commit on the page of a range, and
  next and previous in the navigator ("C, both").
- **D2.** The comment parts of a commit wrap.
- **D3.** The bar of the navigator takes less space, and "Open in a tab" is always in view.

Proposed by the assistant, approved with the plan on 2026-11-24:

- **P1. Only the message wraps.** The lines of the message wrap at the visible width of the pane.
  The code lines of a diff do not wrap and scroll sideways, as now and as in `git show` and gitk.
  The message stays above the diffs: the owner moved it there on 2026-11-14, after a message of 30
  lines in the header took the whole window. Rejected: wrap every line of a diff, because code that
  wraps loses its columns.
- **P2. A line says whether it wraps.** `TextLine` gets the field `wraps::Bool = true`.
  `GitTextToText` sets `wraps = false` on each line that is not a line of the message. `WordWrapping`
  keeps a line with `wraps = false` whole. When the parent gives no right edge, `WordWrapping` wraps
  at the visible width (`get_visible_width(ctx)`, which exists), less the gutter. The chain of a git
  text becomes `GitTextToText`, `WordWrapping`, `TextBlockToScrollLayout`. Rejected: a keyword of
  `WordWrapping` with a function that picks the lines, because only the stage that makes a line knows
  whether it is prose or code.
- **P3. The page of a range shows the chosen commit below its table.** Below the line, a split pane
  that a person divides by a drag: the table at the top (1 share), the page of the chosen commit
  below (2 shares), with its header, its tree and its diffs as now. The chosen commit is the row that
  the stored selection of the table names, live or dormant, as the diffs of a commit follow its tree.
  With no row chosen, it is the first row. Up and Down in the table show the next and the previous
  row below at once. A press on a row shows its commit below. A press on the hash still opens the
  commit as a page of the navigator, at full size. The keys go from the table into the commit and
  back as in the explorer between its tree and its page. Rejected: a second navigator in the page of
  a range, because the explorer already holds the page in a navigator, and two bars of addresses
  would stand one above the other.
- **P4. Next and previous in the navigator.** Two buttons after Parent, and the keys
  Ctrl+Shift+PageDown (next) and Ctrl+Shift+PageUp (previous): Ctrl+PageDown is the next tab, and
  Shift makes it the next item of the list. They change the last element step of the address,
  `[j]`, to `[j+1]` or `[j-1]`. They keep the rest of the address where it still reaches, as the
  list of the address does now. Each move is a visit, so Back returns. A button is off at the end of
  its list, and its tooltip names the item that it opens. The order is the order of the list in the
  document, for a range the order of the log, and not the order of a sorted table. The navigator
  knows nothing of git, so the keys work for a page of any list: a row of a table, a file of a folder,
  a changed file of a commit.
- **P5. The bar fits its width.** The order of the bar: Back, Forward, Parent, Previous, Next, Open in
  a tab, the view switch, the address. So every button is at the left and in view. The address takes
  the rest of the width, and the bar never grows past the width of the navigator. The items of the
  address get less space: no gap between an arrow and its name, and smaller insets than a button.
  When the address does not fit, its first items fold into one item `…`, whose press lists them. The
  last item, the page, stays in view with the arrow of its list, and its name is cut with `…` when it
  is still too wide. Rejected: a bar that scrolls, because a person can not see what is out of view.

## 4. Steps

The work is done in a worktree of its own (`julia-worktree new`), and each step is one commit with
its tests. Each step updates the page of its part in `documentation/`.

1. ✅ **The message of a commit wraps** (P1, P2). Done. Facts of the work: the wrap at the
   visible width is the keyword `visible` of `WordWrapping` (default `false`), so a view of code in
   a pane that scrolls sideways stays as it is; only the chain of a `GitDiffText` sets it. The lines
   of words of a git text are the kinds `:message`, `:note` and `:failure`; every other kind has
   `wraps = false`. A `GitFileText` holds only code, so its chain has no `WordWrapping`. A line that
   does not wrap reads no width, so a resize does not touch it. Add `wraps` to `TextLine` and carry it in each stage
   that copies a line (`WordWrapping`, `TextLineNumbering`, the constructors in `TextDocument.jl`).
   `WordWrapping` keeps a line with `wraps = false` whole and wraps at the visible width when no edge
   is given. `GitTextToText` marks the lines that wrap, and `_make_git_text_projection` puts
   `WordWrapping` in the chain. Tests: the text suite, a block with one line that wraps and one that
   does not, in a pane that scrolls sideways; `GitViewTest`, a message line of 300 characters shows
   on more than one line inside the pane, and a long code line stays one line.
2. ✅ **The bar of the navigator fits its width** (P5). Done, in one commit with step 3, because both
   change the same lines of the bar. Facts of the work: the navigator printer
   prints each part of the bar once more through the recursion, with no range offered, to get the
   width that the part draws at; so the fold copies no width formula of the widgets. The width comes
   from `get_printed_width`, a new export of the layout slice, which reads a printed part as a layout
   reads its children; so the navigator slice needs no edge to the graphics slice. The edge is the
   maximum width that the navigator gets. The items of the address stand in a row of their own with
   no gap, with half the side padding of a toolbar item. A `WidgetLabel` with `max_lines` now also
   cuts a kept line that is wider than its bound, such as one long word like
   `master..topic/baseline-catch-up`; before, only a text of more lines than `max_lines` got the
   `…`. The list of `…` opens at the last folded item. The test that exists: a navigator 420 px wide
   with three long names, in `NavigatorChoicesTest.jl`. Planned tests: a navigator 400 px wide with an address
   of six items: each button inside the bar; the item of the page and its arrow in view; the item `…`
   lists the folded items; a press on a listed item opens it.
3. ✅ **Next and previous in the navigator** (P4). Done. Facts of the work: the icon font had no
   `chevron_up` in the table of the widgets; `lucide.ttf` holds it at `0xe070`, and the table names it
   now. `find_navigator_sibling` finds the last element step of the page address and checks that the
   list has an item there; `make_navigator_sibling_operation` is a choice at that step
   (`make_navigator_choice_operation`). The tests that exist: the shelf of the navigator tests (the
   chapters of a book, then the books), the keys and the Next button in an editor, and the commits of
   a range in `GitViewTest.jl`. Planned tests: a navigator on `commits[2]` of a range: Next
   shows `commits[3]`, Back shows `commits[2]` again, Next is off at the last commit; the same on a
   plain vector of documents, to show that the navigator knows nothing of git.
4. ✅ **The page of a range shows the chosen commit below its table** (P3). Done. Facts of the work:
   the chosen commit is the item of the row that the stored selection of the table names
   (`.document.rows[k]`), and `has_dormant_selection(::GitCommitRange)` keeps that row while the
   selection is in the commit below. A roster table answers Return as a move into a cell, and opens
   a row only on a double press; so a double press, and not Return, puts the keys into the commit
   below, and Return keeps its meaning of a table. A press in the commit below puts the keys there too. Tests in `GitViewTest` and
   `GitGestureTest`: the commit below shows the first row; Down in the table shows the subject of the
   next commit below; a press on row 3 shows commit 3; a press on a hash still opens the page of the
   commit; the table keeps its row while the keys are in the commit below.
5. ✅ **Pictures of the views, headless, at one density.** Done: an editor on the headless backend
   with `FontFileMeasure`, and `write_image` of the SDL backend for the canvas of its window, 1200 to
   1400 px wide and 560 px for the narrow navigator. The pictures showed each view as the steps say.
   The owner (2026-11-24): "no need to live
   check, you can take screenshots headlessly at one display density". The pictures show a range
   with the chosen commit below its table, a commit with a long message, a commit at full size with
   Next and Previous, and the bar of a narrow navigator.

## 5. Risks

- A new field of `TextLine` changes its constructor with all fields. Three files build a line that
  way in projectured-julia, and none in omnet-julia or inet-julia. The `Pkg.precompile` of
  omnet-julia shows a call that is missed.
- The split pane of P3 makes the page of a commit lower. A subject of 700 characters takes 7 lines
  of its header, so the diffs get less height in a small window. The drag of the divider gives the
  height back.

Not in this plan: the tree of a commit cuts long names at a quarter of the width (seen in the
screenshot).
