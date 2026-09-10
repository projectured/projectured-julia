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

- [x] **Step 1 — fix B, the widget.** DONE. Subtract `_inset_total(w)` from the offered
      main and cross extents before the split divides them, and add it back to
      the reported outer size. Add a test that a bordered split keeps its
      children and its splitter inside the size it reports.
- [x] **Step 2 — fix A, the pane layer.** DONE. Drop the `border` argument on the
      `WidgetSplitPane`. Keep it on the `WidgetTabbedPane`. Say in the comment
      on `_PANE_BORDER` that it is the tabbed pane's chrome and that a split
      pane takes none.
- [x] **Step 3 — run the pane suites and the widget suites**, and compare the
      split-pane drag baseline (24 pass, 3 fail, 2 error) against clean main.
      DONE. Every pane suite passes: surgery 79, geometry 35, PaneToWidget 42,
      reader 29, gestures 42, drag 251, rename 19, construct 45. The widget
      suites pass: split pane reflow 22, tab strip 18, transform pane 26, scroll
      pane hover 4, workbench content pane 6. `test_split_pane_drag` reports 24
      pass, 3 fail, 2 error, which is its baseline on clean main.

## Decisions taken while implementing

**The two faults were fixed in the order B then A.** Fixing A alone would have
hidden B rather than removed it: with no caller setting a box-model field on a
split, the wrong arithmetic simply never runs. Fixing B first meant the test for
A could be written against a split that is otherwise correct, so its failure
reports the gap in pixels — the nested splitter starts at 209 rather than 201
and stops at 384 rather than 400 — instead of an arithmetic error further down.

**`inset_default` is `Inset(0, 0, 0, 0)`,** so every other split pane in the
repository has an empty box model. Both new branches in `_split_build` are
guarded on `inset_x == 0` / `inset_y == 0` and hand back the same cells, so the
change is a no-op for every caller but a future one.

**`_split_measured_sizes` now takes the content extent, not the canvas.** Its old
form, `outer_main - pos(n) - pos(1)`, happened to be right for a symmetric inset
once the canvas reported the inset, and wrong for an asymmetric one. The drag
reader subtracts the inset itself and passes the content extent, which is right
for either.

## A gap this plan does not close

A split pane reserves the space its `margin`, `border` and `padding` ask for and
never paints them: `_split_build` does not call `_push_box_rects!`, so a caller
that set `border_color` would get the gap and no line. No caller sets one, and
painting the box model is a different piece of work from dividing the space, so
it is left alone.
