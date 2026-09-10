# The split pane and its inset

A `WidgetSplitPane` in the pane example draws its children and its splitters
8 pixels inside the space it was given. The spacing compounds with the depth of
the tree, and a nested split's splitter does not meet the splitter of the split
that holds it.

## What is wrong

### A. The pane layer gives a split pane a border

`source/pane/PaneToWidget.jl` passes `_PANE_BORDER = Inset(8, 8, 8, 8)` to both
widgets it builds:

```julia
pane = WidgetSplitPane(axis, Any[]; border = _PANE_BORDER)      # line 298
pane = WidgetTabbedPane(...; border = _PANE_BORDER)             # line 365
```

On the tabbed pane the inset is chrome: it holds a tab's content off the pane's
edge. A split pane holds children and one splitter rectangle and draws no chrome
of its own, so the inset only pushes the layout right and down. Each level of
nesting adds another 8 pixels, and each nested splitter starts 8 pixels inside
the slot whose edge its parent's splitter runs along.

`PaneToWidget` is the only caller in the repository that gives a split pane a
box-model field.

### B. `_split_build` reads the inset for positions and forgets it for extents

`source/widget/WidgetToGraphics.jl`, `_split_build`:

  * `allocate_axis(Int(avail_main[]), ...)` divides the whole offered main
    extent, not the extent less the left and the right inset;
  * `outer_cross` is the whole offered cross extent, and the splitter rectangle
    takes that as its length;
  * `outer_w_cell` / `outer_h_cell` report the content size with no inset added.

So the content and the splitter overflow the far edge by the inset, and the pane
reports a size smaller than it draws. `_split_build` is the one container in that
file that never calls `_inset_total`.

Measured with a split of two labels offered 400x300 and `border = Inset(8,8,8,8)`:

```
Canvas x=0 y=0 w=1 h=300
  Viewport x=8 y=8 ...
  Viewport x=9 y=8 ...
  Rect x=8 y=8 w=1 h=300     <- the splitter
```

The splitter starts 8 pixels below the top and runs 300 pixels, so it ends 8
pixels past the bottom. It must start at 8 and run 284.

## The work

- [ ] **Step 1 — fix B, the widget.** Subtract `_inset_total(w)` from the offered
      main and cross extents before the split divides them, and add it back to
      the reported outer size. Add a test that a bordered split keeps its
      children and its splitter inside the size it reports.
- [ ] **Step 2 — fix A, the pane layer.** Drop the `border` argument on the
      `WidgetSplitPane`. Keep it on the `WidgetTabbedPane`. Say in the comment
      on `_PANE_BORDER` that it is the tabbed pane's chrome and that a split
      pane takes none.
- [ ] **Step 3 — run the pane suites and the widget suites**, and compare the
      split-pane drag baseline (24 pass, 3 fail, 2 error) against clean main.

## Decisions taken while implementing
