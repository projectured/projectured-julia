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

"""
    make_constraint_layout_document_example(; width, height)

A small dashboard built with `ConstraintLayout`: a header pinned to the
top-left, a sidebar pinned to the left below it, a main panel to the right of
the sidebar, and a footer below the columns that is *softly* centered
horizontally. The relations exercise equality pinning, an offset (`+ 8`), an
inequality (`main.right <= parent.right`), and a soft constraint (the centered
footer yields to the hard pins around it).

Children are widgets whose `…ToGraphicsCanvas` projections populate `w` / `h`;
the solver reads those intrinsic extents and computes each child's position.
Where a relation explicitly constrains a child's size axis (here the main
panel's `:right` is pinned to the container), the layout *owns* that dimension:
the child is re-projected with the solved extent as its available size, so
content that honors available size reflows to fill. Each widget is given an
explicit intrinsic size as its starting point.
"""
function make_constraint_layout_document_example(; width=560, height=560)
    fg = StyleColor(40/255, 80/255, 160/255, 1.0)
    mkbtn(w, h, label) = WidgetButton(Point2D(0, 0), Point2D(w, h), label;
                                      border=Inset(1, 1, 1, 1), border_color=fg,
                                      padding=Inset(4, 4, 8, 8))

    header  = mkbtn(width - 20, 40,  "Header")
    sidebar = mkbtn(120,        200, "Sidebar")
    main    = mkbtn(width - 160, 200, "Main")
    footer  = mkbtn(160,        30,  "Footer")
    children = [header, sidebar, main, footer]   # 1=header 2=sidebar 3=main 4=footer

    relations = [
        # Header pinned to the top-left corner of the container.
        constrain(anchor(1, :left), :(==), anchor(0, :left)),
        constrain(anchor(1, :top),  :(==), anchor(0, :top)),
        # Sidebar pinned to the left, 8 px below the header.
        constrain(anchor(2, :left), :(==), anchor(0, :left)),
        constrain(anchor(2, :top),  :(==), anchor(1, :bottom) + 8),
        # Main panel to the right of the sidebar, aligned with its top.
        constrain(anchor(3, :left), :(==), anchor(2, :right) + 8),
        constrain(anchor(3, :top),  :(==), anchor(1, :bottom) + 8),
        # Main panel fills to the container's right edge (drives size override).
        constrain(anchor(3, :right), :(==), anchor(0, :right)),
        # Footer below the columns, softly centered horizontally.
        constrain(anchor(4, :top),     :(==), anchor(2, :bottom) + 8),
        constrain(anchor(4, :centerx), :(==), anchor(0, :centerx); strength=:weak),
    ]

    ConstraintLayout(children, relations; bounding_width=width, bounding_height=height)
end

# ── Atomic layout documents ────────────────────────────────────────────────
# One bare instance per remaining layout type: `make_layout_document_example`
# above nests several layouts inside an outer `VerticalLayout`, so none of
# them stands alone as its own root there.

function make_anchored_layout_document_example()
    content = VerticalLayout(Any[
        WidgetLabel(Point2D(0, 0), "Node A"),
        WidgetLabel(Point2D(0, 40), "Node B"),
    ]; gap=8)
    note = AnchoredEntry(WidgetLabel(Point2D(0, 0), "3 hops");
                         reference=Reference(FieldReferenceStep("children"), ElementReferenceStep(1)),
                         placement=:right)
    AnchoredLayout(content, Any[note])
end

make_flow_layout_document_example() =
    FlowLayout(Any[WidgetLabel(Point2D(0, 0), t) for t in ("alpha", "beta", "gamma", "delta", "epsilon")];
              max_width=200, horizontal_gap=6, vertical_gap=6)

make_grid_layout_document_example() =
    GridLayout(Any[WidgetLabel(Point2D(0, 0), "R$(r)C$(c)") for r in 1:2 for c in 1:2], 2;
              horizontal_gap=8, vertical_gap=8)

make_horizontal_layout_document_example() =
    HorizontalLayout(Any[WidgetLabel(Point2D(0, 0), "Left"), WidgetLabel(Point2D(0, 0), "Right")]; gap=12)

make_stack_layout_document_example() =
    StackLayout(Any[WidgetLabel(Point2D(0, 0), "Background"), WidgetLabel(Point2D(0, 0), "Foreground")])

make_vertical_layout_document_example() =
    VerticalLayout(Any[WidgetLabel(Point2D(0, 0), "Top"), WidgetLabel(Point2D(0, 0), "Bottom")]; gap=12)

make_layout_constraint_document_example() =
    LayoutConstraint(WidgetLabel(Point2D(0, 0), "Constrained");
                     min_width=80, preferred_width=160, max_width=320)
