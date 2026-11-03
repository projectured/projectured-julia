# The layout cases: one window for each case of the sizing rules
# (documentation/rule/layout-rules.md). Each window has a hint at the top that
# says what the case must do, and a splitter below it. Drag the splitter, or
# resize the window, and see how the parts share the space.

const _LAYOUT_CASE_BLUE   = StyleColor(0.86, 0.92, 0.98, 1.0)
const _LAYOUT_CASE_ORANGE = StyleColor(0.98, 0.92, 0.86, 1.0)
const _LAYOUT_CASE_GREEN  = StyleColor(0.88, 0.96, 0.88, 1.0)
const _LAYOUT_CASE_GRAY   = StyleColor(0.94, 0.94, 0.94, 1.0)

# A part whose extent shows: a tinted scroll pane around `content`.
_make_layout_case_panel(content, color) =
    WidgetScrollPane(content; style = WidgetStyle(content_color = color))

# A page that grows down: a tinted scroll pane whose content grows on its height.
_make_layout_case_page(content, color) =
    WidgetScrollPane(content; grows = (width = false, height = true), style = WidgetStyle(content_color = color))

# `count` lines of text, each one a label.
_make_layout_case_lines(text, count) =
    VerticalLayout(Any[WidgetLabel("$text $i") for i in 1:count]; gap = 2)

# The window of a case: the hint, and below it a split of `case` and an empty
# part, along `orientation`. A `:vertical` split puts the case below the empty
# part, so a drag up gives the case more height; a `:horizontal` split puts the
# case at the left, so a drag to the right gives it more width.
function _make_layout_case_window(hint, case; orientation = :vertical)
    empty = _make_layout_case_panel(WidgetLabel("Drag the splitter beside this part."), _LAYOUT_CASE_GRAY)
    parts = orientation === :vertical ? Any[empty, case] : Any[case, empty]
    split = WidgetSplitPane(orientation,
                            Any[LayoutConstraint(part; width = Fill, height = Fill) for part in parts])
    VerticalLayout(Any[WidgetLabel(hint), LayoutConstraint(split; width = Fill, height = Fill)];
                   gap = 8, child_width = Fill)
end

"""
    make_layout_text_above_table_document_example()

The detail of a task: a text of twelve lines in a scroll area with no weight,
above a table that fills the rest and has a minimum of 120. The text must give
up height and scroll when the part is short, and the table must keep its 120.
"""
function make_layout_text_above_table_document_example()
    text = _make_layout_case_panel(_make_layout_case_lines("A fact of the task, line", 12), _LAYOUT_CASE_BLUE)
    table = WidgetTable(Any["module", "name", "old", "new"],
                        Any[Any["Net.host[$i]", "count", string(10i), string(10i + 1)] for i in 1:30])
    detail = VerticalLayout(Any[text, LayoutConstraint(table; height = Fill, min_height = 120)];
                            gap = 6, child_width = Fill)
    _make_layout_case_window(
        "A text in a scroll area above a table that fills the rest, with a minimum of 120. " *
        "Drag the splitter down: the text must give up height and scroll, and the table must keep 120.",
        detail)
end

"""
    make_layout_scroll_area_in_page_document_example()

A page that scrolls, with a code block in a scroll area of its own between two
paragraphs. The code block must be as tall as its lines, and scroll only its
long lines to the side; the page scrolls when it is taller than its part.
"""
function make_layout_scroll_area_in_page_document_example()
    code = _make_layout_case_panel(
        _make_layout_case_lines("a long line of code that is wider than the page " ^ 3 * "— line", 16),
        _LAYOUT_CASE_ORANGE)
    page = VerticalLayout(Any[_make_layout_case_lines("A paragraph above the code, line", 8), code,
                              _make_layout_case_lines("A paragraph below the code, line", 8)];
                          gap = 8, child_width = Fill)
    _make_layout_case_window(
        "A code block in its own scroll area, in a page that scrolls. " *
        "The code block must be as tall as its 16 lines at every height of its part, " *
        "and the page must scroll when it is taller than its part.",
        _make_layout_case_page(page, _LAYOUT_CASE_GRAY))
end

"""
    make_layout_fill_in_scroll_area_document_example()

Two scroll areas side by side, each with a column of a header, a part that fills
and a footer. With a short header the filling part takes the rest of the view.
With a long header the column is as tall as its content, and the area scrolls to
the footer.
"""
function make_layout_fill_in_scroll_area_document_example()
    function column(lines)
        VerticalLayout(Any[_make_layout_case_lines("A line of the header,", lines),
                           LayoutConstraint(_make_layout_case_panel(WidgetLabel("This part fills"), _LAYOUT_CASE_GREEN);
                                            height = Fill),
                           WidgetLabel("The footer")];
                       gap = 6, child_width = Fill)
    end
    pair = WidgetSplitPane(:horizontal,
                           Any[LayoutConstraint(_make_layout_case_page(column(2), _LAYOUT_CASE_GRAY);
                                                width = Fill, height = Fill),
                               LayoutConstraint(_make_layout_case_page(column(40), _LAYOUT_CASE_GRAY);
                                                width = Fill, height = Fill)])
    _make_layout_case_window(
        "A part that fills, in a scroll area. Left, with a short header: the green part must fill " *
        "the rest of the view. Right, with a long header: the area must scroll down to the footer.",
        pair)
end

"""
    make_layout_shares_document_example()

One column with each size policy: a `Fixed(60)` part, a label that is as tall
as its text, and two parts that share the rest two to one, each with a minimum
of 40.
"""
function make_layout_shares_document_example()
    part(text, color) = _make_layout_case_panel(WidgetLabel(text), color)
    column = VerticalLayout(Any[
        LayoutConstraint(part("Fixed(60)", _LAYOUT_CASE_ORANGE); height = Fixed(60)),
        WidgetLabel("Content: this label is as tall as its text"),
        LayoutConstraint(part("Relative(2), at least 40", _LAYOUT_CASE_BLUE); height = Relative(2), min_height = 40),
        LayoutConstraint(part("Relative(1), at least 40", _LAYOUT_CASE_GREEN); height = Relative(1), min_height = 40),
    ]; gap = 6, child_width = Fill)
    _make_layout_case_window(
        "The size policies in one column. The blue part must be twice the green part; " *
        "below their minimums of 40 the column is cut at the bottom.",
        column)
end

"""
    make_layout_row_edge_document_example()

Three rows at the left of a splitter: a label, a field that fills and a button;
a long text before a button; and the same with a weight on the text.
"""
function make_layout_row_edge_document_example()
    long = "A long text that wraps at the edge that it gets from its row, " ^ 3
    rows = VerticalLayout(Any[
        HorizontalLayout(Any[WidgetLabel("Name:"), LayoutConstraint(WidgetText(""); width = Fill),
                             WidgetButton("Go")]; gap = 8),
        HorizontalLayout(Any[WidgetLabel("No weight: " * long), WidgetButton("Go")]; gap = 8),
        HorizontalLayout(Any[LayoutConstraint(WidgetLabel("A weight: " * long); width = Fill),
                             WidgetButton("Go")]; gap = 8),
    ]; gap = 16, child_width = Fill)
    _make_layout_case_window(
        "Rows at the edge. Drag the splitter to the left. First row: the field must take what the label " *
        "and the button leave. Second row: the text takes the room, and the button is cut. " *
        "Third row: the text must wrap where the button begins.",
        rows; orientation = :horizontal)
end

"""
    make_layout_rows_in_slot_and_page_document_example()

A table and a list in a part that cuts, at the left, and in a page that scrolls,
at the right. In the part that cuts the table fills its slot and scrolls its
rows; in the page the table and the list are as tall as their rows, and the page
scrolls.
"""
function make_layout_rows_in_slot_and_page_document_example()
    table() = WidgetTable(Any["row", "value"], Any[Any["row $i", string(i * i)] for i in 1:40])
    list() = WidgetList(Any["item $i" for i in 1:20])
    slot = VerticalLayout(Any[WidgetLabel("In a part that cuts: the table fills and scrolls its rows"),
                              LayoutConstraint(table(); height = Fill)];
                          gap = 6, child_width = Fill)
    page = _make_layout_case_page(
        VerticalLayout(Any[WidgetLabel("In a page: the table and the list are as tall as their rows"),
                           table(), list()];
                       gap = 6, child_width = Fill),
        _LAYOUT_CASE_GRAY)
    pair = WidgetSplitPane(:horizontal, Any[LayoutConstraint(slot; width = Fill, height = Fill),
                                            LayoutConstraint(page; width = Fill, height = Fill)])
    _make_layout_case_window(
        "Rows in a part that cuts and in a page. Left: the table must fill its part and scroll its rows. " *
        "Right: the table and the list must be as tall as their rows, and the page must scroll.",
        pair)
end
