"""
    make_layout_document_example(; width, height)

A small showcase of the four layout document types. The root is a
`VerticalLayout` containing:

  * a `HorizontalLayout` of three labels with `:center` vertical
    alignment — labels of different heights stack centred on the row;
  * a `GridLayout` (2 columns) of widget buttons;
  * a `FlowLayout` of tag-like labels that wraps when it runs out of
    width.

Children of layouts are widgets whose `…ToGraphicsCanvas` projections
populate `w` / `h` on their output canvases. The layout projections
read those cells and compute positions.
"""
function make_layout_document_example(; width=600, height=600)
    text_color = StyleColor(40/255, 80/255, 160/255, 1.0)

    # ── Row: labels of different sizes, vertically centred ───────────────
    row_labels = [
        WidgetLabel(Point2D(0, 0), "short"),
        WidgetLabel(Point2D(0, 0), "a longer label"),
        WidgetLabel(Point2D(0, 0), "mid"),
    ]
    row = HorizontalLayout(row_labels; vertical_align=:center, gap=12)

    # ── Grid: 2 columns of buttons ────────────────────────────────────────
    buttons = [
        WidgetButton(Point2D(0, 0), Point2D(140, 36), label;
                     border=Inset(1, 1, 1, 1), border_color=text_color,
                     padding=Inset(4, 4, 8, 8))
        for label in ("New", "Open", "Save", "Close", "Help")
    ]
    grid = GridLayout(buttons, 2;
                      horizontal_gap=8, vertical_gap=8,
                      horizontal_align=:left, vertical_align=:center)

    # ── Flow: tag-like labels that wrap ──────────────────────────────────
    tags = [
        WidgetLabel(Point2D(0, 0), t;
                    padding=Inset(2, 2, 6, 6),
                    border=Inset(1, 1, 1, 1), border_color=text_color)
        for t in ("alpha", "beta", "gamma", "delta", "epsilon",
                  "zeta", "eta", "theta", "iota", "kappa")
    ]
    flow = FlowLayout(tags; max_width=width - 40,
                      horizontal_gap=6, vertical_gap=6,
                      horizontal_align=:left, vertical_align=:center)

    # ── Outer vertical column ────────────────────────────────────────────
    VerticalLayout([row, grid, flow]; gap=24, horizontal_align=:left)
end
