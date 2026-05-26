function make_widget_document_example(; width=1024, height=768, line_height=56)
    # ── Form tab ──────────────────────────────────────────────────────────────
    field_color  = StyleColor(50/255,  50/255,  80/255,  1.0)
    field_border = Inset(1, 1, 1, 1)
    field_border_color = StyleColor(100/255, 120/255, 200/255, 1.0)

    name_label  = WidgetLabel(Point2D(0,           0),           "Username:")
    name_field  = WidgetText( Point2D(280,          0),           "alice";
                              content_fill_color=field_color,
                              border=field_border, border_color=field_border_color)

    email_label = WidgetLabel(Point2D(0,           line_height), "Email:")
    email_field = WidgetText( Point2D(280,          line_height), "alice@example.com";
                              content_fill_color=field_color,
                              border=field_border, border_color=field_border_color)

    notify_check = WidgetCheckbox(Point2D(0,   2 * line_height), true)
    notify_label = WidgetLabel(  Point2D(100,  2 * line_height), "Enable notifications")

    save_btn = WidgetButton(Point2D(0, 3 * line_height), Point2D(180, line_height), "Save";
                            border=Inset(1, 1, 1, 1),
                            border_color=StyleColor(80/255, 160/255, 80/255, 1.0),
                            padding=Inset(4, 4, 8, 8))

    form_composite = WidgetComposite(Point2D(16, 16), Any[
        name_label,  name_field,
        email_label, email_field,
        notify_check, notify_label,
        save_btn,
    ])

    form_scroll = WidgetScrollPane(form_composite;
                                   size=Point2D(width - 2, height - 80),
                                   content_fill_color=StyleColor(28/255, 28/255, 40/255, 1.0))

    # ── List tab ──────────────────────────────────────────────────────────────
    item_labels = [WidgetLabel(Point2D(4, (i - 1) * line_height), "Item $i")
                   for i in 1:20]

    list_composite = WidgetComposite(Point2D(0, 0), Any[item_labels...])

    list_scroll = WidgetScrollPane(list_composite;
                                   size=Point2D(width - 2, height - 80),
                                   content_fill_color=StyleColor(28/255, 28/255, 40/255, 1.0),
                                   border=Inset(1, 1, 1, 1),
                                   border_color=StyleColor(80/255, 80/255, 120/255, 1.0))

    # ── Layout tab ────────────────────────────────────────────────────────────
    panel_fill  = StyleColor(22/255, 30/255, 50/255, 1.0)
    title_fill  = StyleColor(50/255, 80/255, 140/255, 1.0)
    left_labels = [WidgetLabel(Point2D(4, (i - 1) * line_height), "Left item $i")
                   for i in 1:8]
    right_labels = [WidgetLabel(Point2D(4, (i - 1) * line_height), "Right item $i")
                    for i in 1:8]

    left_scroll  = WidgetScrollPane(WidgetComposite(Point2D(0, 0), Any[left_labels...]);
                                    size=Point2D(div(width, 2) - 4, height - 120),
                                    content_fill_color=panel_fill)
    right_scroll = WidgetScrollPane(WidgetComposite(Point2D(0, 0), Any[right_labels...]);
                                    size=Point2D(div(width, 2) - 4, height - 120),
                                    content_fill_color=panel_fill)

    left_pane  = WidgetTitlePane("Navigation", left_scroll;
                                 title_fill_color=title_fill,
                                 padding=Inset(4, 4, 4, 4))
    right_pane = WidgetTitlePane("Details", right_scroll;
                                 title_fill_color=title_fill,
                                 padding=Inset(4, 4, 4, 4))

    layout_split = WidgetSplitPane(:horizontal, Any[left_pane, right_pane];
                                   sizes=[div(width, 2), div(width, 2)])

    # ── Controls tab ──────────────────────────────────────────────────────────
    h_bar = WidgetScrollBar(:horizontal;
                            value=0.3, thumb_size=0.25,
                            position=Point2D(16, 16),
                            size=Point2D(width - 64, 24))
    v_bar = WidgetScrollBar(:vertical;
                            value=0.6, thumb_size=0.3,
                            position=Point2D(width - 36, 16),
                            size=Point2D(20, height - 160))

    controls_composite = WidgetComposite(Point2D(0, 0), Any[h_bar, v_bar])
    controls_scroll = WidgetScrollPane(controls_composite;
                                       size=Point2D(width - 2, height - 80),
                                       content_fill_color=StyleColor(28/255, 28/255, 40/255, 1.0))

    # ── Tabbed content ────────────────────────────────────────────────────────
    tabs = WidgetTabbedPane([
        ("Form",     form_scroll),
        ("List",     list_scroll),
        ("Layout",   layout_split),
        ("Controls", controls_scroll),
    ])

    # ── Toolbar ───────────────────────────────────────────────────────────────
    toolbar = WidgetToolbar([
        WidgetMenuItem("New"),
        WidgetMenuItem("Open"),
        WidgetMenuItem("Save"),
        WidgetMenuItem("|"),
        WidgetMenuItem("Undo"),
        WidgetMenuItem("Redo"),
    ]; padding=Inset(4, 4, 4, 4),
       padding_color=StyleColor(40/255, 40/255, 56/255, 1.0))

    # ── Menu bar ──────────────────────────────────────────────────────────────
    menu_bar = WidgetMenu([
        WidgetMenuItem("File"),
        WidgetMenuItem("Edit"),
        WidgetMenuItem("View"),
        WidgetMenuItem("Help"),
    ])

    # ── Tooltip ───────────────────────────────────────────────────────────────
    tip = WidgetTooltip(Point2D(20, height - 80), Point2D(360, line_height),
                        "Widget Gallery — hover items for tips";
                        visible=false)

    WidgetShell(tabs;
                menu_bar=menu_bar,
                toolbar=toolbar,
                tooltip=tip,
                content_fill_color=StyleColor(28/255, 28/255, 38/255, 1.0),
                size=Point2D(width, height))
end

function make_widget_tabbed_pane_document_example(; width=600, height=400)
    tab_alpha = WidgetLabel(Point2D(16, 16), "Content A")
    tab_beta  = WidgetLabel(Point2D(16, 16), "Content B")
    tab_gamma = WidgetLabel(Point2D(16, 16), "Content C")

    tabs = WidgetTabbedPane([
        ("Alpha", tab_alpha),
        ("Beta",  tab_beta),
        ("Gamma", tab_gamma),
    ])

    WidgetShell(tabs;
                content_fill_color=StyleColor(28/255, 28/255, 38/255, 1.0),
                size=Point2D(width, height))
end
