# A dashboard card states its size and can fill the page

> **Kind:** plan · **Status:** design approved by the owner on 2026-11-14; step 1 is done, step 2 waits for a decision (see its note). ·
> **Stands on:** the omnet-julia plan `the-ide-follows-the-baseline-catch-up.md` (its step 11 found
> the need), `source/platform/explorer/Dashboard.jl`, `DashboardToWidget.jl`, and the maximize of a
> pane group (`PaneTree.maximized`, `source/platform/pane/PaneDocument.jl`).

## 1. The ask

The owner, 2026-11-14, after the pictures of the pages of the baseline catch-up in the IDE window:

> I'd rather have layout options on the dashboard and also some gesture which allows one card to
> take the whole space temporarily.

> I'm talking about maximizing one card inside the dashboard.

> I agree with your recommendations. I would allow controlling the L1 parameters from the UI as it
> makes sense.

## 2. What exists

- `Dashboard(title, cards)` and `DashboardCard(title, content, content_view)`. `DashboardToWidget`
  draws the cards in a grid with as many columns as cards of at least `card_width` (280 px) fit in
  the page width; each card is a `WidgetCard` in one cell; the rows of the grid are a lazy list in a
  scroll area that grows.
- A card has no height limit: it is as high as its content. A table in a card builds all its rows.
  In the catch-up pages, a log of 4,893 rows made the page about 137,000 px high, and the walk page
  needed 6.5 GB and the page of step 14 11.2 GB. A card can not be wider than one cell, so a wide
  chart or a matrix gets about 300 px.
- The maximize of a pane group is view state: `PaneTree.maximized` names the group that fills the
  window, a save does not keep it, undo records nothing, and Ctrl+M toggles it.

## 3. The design

**Each card states its size (L1).** `DashboardCard` gets two fields:

- `columns`: the count of grid columns that the card spans: `1` (the default), `2`, … or `:all`
  for the whole row. A card that asks for more columns than the page has takes the whole row.
- `height`: `:content` (the default): as high as its content, but at most the visible height of the
  page, and a higher content scrolls inside the card; a number: that height in pixels; or `:page`:
  the visible height of the page.

The cards flow row by row in their order, as now, and a narrow page reflows them. A row is as high
as its highest card, and each card fills its cell. A `.pred` file keeps both fields. The default
limit makes every table in a card build only the rows that show.

```julia
Dashboard("Baseline catch-up", [
    DashboardCard("The walk", walk_chart; columns = :all, height = 360),
    DashboardCard("Steps", steps; columns = 2, height = :page),
    DashboardCard("Progress", progress)])
```

**One card fills the page for a while (M1, M2, M4).** The view of the dashboard holds `maximized`,
the card that fills the page, as view state: a save does not keep it, undo records nothing, and two
views of one dashboard each have their own. The page then shows the title of the dashboard and that
card at the full width and the visible height; the other cards are hidden, not closed.

- M1: a button in the title of each card, which shows while the pointer is over the card, toggles
  the card (its icon says maximize or restore).
- M2: a double click on the title of a card toggles the card.
- M4: Escape restores a maximized card. With no card maximized, Escape does what it does now.
- Ctrl+M stays the maximize of a pane group (M3 was not chosen).

**The size in the window.** The context menu of a card has two submenus, and each item is an edit of
the field of the card, which undo records and a save keeps:

- Width: 1 column, 2 columns, 3 columns, Full row.
- Height: Fit content, One page, 240 px, 360 px, 480 px, 720 px.

## 4. Decisions

| # | Decision | State |
| --- | --- | --- |
| D1 | The card states its size (L1). Rejected: explicit rows on the dashboard (L2), which can not reflow; one size for all cards (L3). | owner, 2026-11-14 |
| D2 | A maximized card is view state of the view of the dashboard, as the maximize of a pane group is. | owner, 2026-11-14 (the recommendation) |
| D3 | The gestures are the button in the title, a double click on the title, and Escape. Rejected: Ctrl+M from the inside out (M3), which changes what Ctrl+M does today. | owner, 2026-11-14 |
| D4 | The size changes from the context menu of a card, with the values of §3. | proposed by the assistant; the owner asked for UI control "as it makes sense" |
| D5 | The default height of a card is its content, at most the visible height of the page. | proposed by the assistant |

## 5. Steps

Each step is one commit in the worktree `projectured-julia-baseline-catch-up` (branch
`baseline-catch-up`). Each test runs through `bounded-run` with the private depot of the worktree.

1. ~~**The size of a card.**~~ **Done.** The fields `columns` and `height`, their `.pred` form, the layout of
   `DashboardToWidget` and the height limit. Tests: a card of 2 columns and one of `:all` in a page
   of 3 columns and in a page of 1; a card of `:content` with a high content scrolls inside and is
   one page high; `:page` and a number; a card that holds a table of 9,000 rows builds only the rows
   that show, and its memory stays bounded; a `.pred` round trip.
   Facts of the code: `DashboardCard` has `columns::Union{Int,Symbol} = 1` and `height::Union{Int,Symbol} = :content`,
   and a constructor `DashboardCard(title, content; columns, height)`; a `.pred` file writes both fields.
   The grid of the page is a list of rows of one column; each row is a `GridLayout` of N columns whose cells
   are `LayoutConstraint(card widget; column_span)`, so the spans use the grid that exists, and the rows stay
   lazy. The cards go to rows by `compute_grid_places` (the placement that `GridLayout` uses, now public), and
   N is no more than the sum of the spans. A vector `GridLayout` with fewer children than columns kept only as
   many columns as children; it now keeps all its columns, which the last row of a dashboard needs. The body
   of a card is a `WidgetScrollPane` in a `VerticalLayout`: `:content` caps the pane at the visible height of
   the page less `card_chrome` (the height of a card with a title and no content, measured from the card
   projection), `:page` and a number set the pane to that height less `card_chrome`, so the card is that
   high. A page with no visible height leaves `:content` and `:page` as high as the content. The path of
   a card is `children[r][1].children[i].child` below the grid, and its content is
   `content.children[1].child.content` below the card.
2. **The maximize of a card.** The view state, the button, the double click and Escape. Tests in a
   real editor: each gesture maximizes and restores; the other cards keep their state; a save keeps
   no maximize; undo records nothing.
3. ~~**The size from the context menu.**~~ **Done.** The two submenus. Tests: each item writes its field, undo
   takes it back, the layout follows.
   Facts of the code: a right click on a card (its `WidgetCard` carries the binding) opens
   `compute_context_menu(::DashboardCard)`, and the binding is in the gesture table of `DashboardCard`, so the
   palette runs it. A submenu opens in a window of its own, which closes the context menu layer, so an item
   can not carry an `operation` that the menu lifts; each item runs an `Action` whose callback finds the card
   in the editor (`search_documents` with `places`) and applies `find_rooted_operation` and `apply_change!`,
   which one entry of undo records. The page maps the path of a card widget back to `cards[k]` and its title
   to `cards[k].title`, which the source of a menu needs.
4. **The guide.** The explorer guide describes the size of a card, the maximize and the menu; the
   naming guard; the dashboard tests of the explorer suite.

Then the catch-up plan uses it: `present.jl` gives the cards their sizes, and the pictures of the
pages are made again.

## 6. Not in this plan

A drag of the edge of a card to change its size.
