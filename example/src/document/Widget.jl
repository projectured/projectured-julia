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

# ── Per-widget examples ──────────────────────────────────────────────────────
#
# The gallery above (make_widget_document_example) crams every widget into one
# document. The functions below do the opposite: each builds the smallest
# possible document exercising a single widget type, so a widget's behavior can
# be tested in isolation. Pair each with make_widget_projection_example, except
# the editable text widget, which needs make_widget_text_projection_example.

# WidgetLabel — a positioned, non-interactive label.
make_widget_label_document_example() =
    WidgetLabel(Point2D(40, 40), "Hello, label")

# WidgetText — an editable text widget. Its content is a TextText, so the widget
# recurses it through the Text domain and all caret navigation / text editing
# comes from TextToGraphics (the widget only maps the resulting references
# backward). Click to place the cursor, then type / backspace to edit. Render
# with make_widget_text_projection_example.
function make_widget_text_document_example()
    content = TextText(TextString("edit me", font_ubuntu_monospace_regular_24, color_default))
    WidgetText(Point2D(40, 40), content;
               border=Inset(1, 1, 1, 1),
               border_color=color_default,
               padding=Inset(4, 4, 4, 4))
end

# WidgetCheckbox — a checkbox; content is the boolean checked state.
make_widget_checkbox_document_example() =
    WidgetCheckbox(Point2D(40, 40), true;
                   border=Inset(1, 1, 1, 1), border_color=color_default,
                   padding=Inset(4, 4, 4, 4))

# WidgetButton — a clickable button.
make_widget_button_document_example() =
    WidgetButton(Point2D(40, 40), Point2D(180, 56), "Click me";
                 border=Inset(1, 1, 1, 1), border_color=color_default,
                 padding=Inset(4, 4, 8, 8))

# WidgetTooltip — a floating tooltip overlay (visible so it renders standalone).
make_widget_tooltip_document_example() =
    WidgetTooltip(Point2D(40, 40), Point2D(360, 56), "A floating tooltip";
                  border=Inset(1, 1, 1, 1), border_color=color_default,
                  padding=Inset(4, 4, 4, 4))

# WidgetMenuItem — a single item, normally found inside a menu or toolbar.
make_widget_menu_item_document_example() =
    WidgetMenuItem("File"; padding=Inset(4, 4, 8, 8))

# WidgetMenu — a sequence of WidgetMenuItems.
make_widget_menu_document_example() =
    WidgetMenu([WidgetMenuItem("File"), WidgetMenuItem("Edit"),
                WidgetMenuItem("View"), WidgetMenuItem("Help")])

# WidgetToolbar — a horizontal strip of tool items.
make_widget_toolbar_document_example() =
    WidgetToolbar([WidgetMenuItem("New"), WidgetMenuItem("Open"),
                   WidgetMenuItem("Save"), WidgetMenuItem("|"),
                   WidgetMenuItem("Undo"), WidgetMenuItem("Redo")];
                  padding=Inset(4, 4, 4, 4))

# WidgetComposite — a positioned container of child widgets.
make_widget_composite_document_example() =
    WidgetComposite(Point2D(40, 40), Any[
        WidgetLabel(Point2D(0,   0), "First"),
        WidgetLabel(Point2D(0,  56), "Second"),
        WidgetLabel(Point2D(0, 112), "Third"),
    ])

# WidgetTitlePane — a pane with a title bar and a content area.
function make_widget_title_pane_document_example()
    body = WidgetComposite(Point2D(8, 8), Any[
        WidgetLabel(Point2D(0,  0), "Detail one"),
        WidgetLabel(Point2D(0, 56), "Detail two"),
    ])
    WidgetTitlePane("Details", body;
                    title_fill_color=StyleColor(50/255, 80/255, 140/255, 1.0),
                    content_fill_color=StyleColor(22/255, 30/255, 50/255, 1.0),
                    padding=Inset(4, 4, 4, 4))
end

# WidgetSplitPane — two child panes divided along an axis.
function make_widget_split_pane_document_example(; width=600)
    left  = WidgetTitlePane("Left",  WidgetLabel(Point2D(8, 8), "Left content"))
    right = WidgetTitlePane("Right", WidgetLabel(Point2D(8, 8), "Right content"))
    WidgetSplitPane(:horizontal, Any[left, right];
                    sizes=[div(width, 2), div(width, 2)])
end

# WidgetScrollBar — a single scroll bar with a thumb.
make_widget_scroll_bar_document_example() =
    WidgetScrollBar(:vertical; value=0.4, thumb_size=0.3,
                    position=Point2D(40, 40), size=Point2D(20, 300))

# WidgetScrollPane — a scrollable viewport over an over-tall composite.
function make_widget_scroll_pane_document_example(; width=400, height=300, line_height=56)
    items = [WidgetLabel(Point2D(4, (i - 1) * line_height), "Item $i") for i in 1:20]
    WidgetScrollPane(WidgetComposite(Point2D(0, 0), Any[items...]);
                     size=Point2D(width, height),
                     content_fill_color=StyleColor(28/255, 28/255, 40/255, 1.0),
                     border=Inset(1, 1, 1, 1),
                     border_color=StyleColor(80/255, 80/255, 120/255, 1.0))
end

# WidgetShell — a top-level window shell with a menu bar and toolbar.
function make_widget_shell_document_example(; width=600, height=400)
    content = WidgetComposite(Point2D(16, 16), Any[
        WidgetLabel(Point2D(0,  0), "Inside a shell"),
        WidgetLabel(Point2D(0, 56), "with a menu bar and toolbar"),
    ])
    menu_bar = WidgetMenu([WidgetMenuItem("File"), WidgetMenuItem("Edit"),
                           WidgetMenuItem("Help")])
    toolbar  = WidgetToolbar([WidgetMenuItem("New"), WidgetMenuItem("Open"),
                              WidgetMenuItem("Save")]; padding=Inset(4, 4, 4, 4))
    WidgetShell(content;
                menu_bar=menu_bar, toolbar=toolbar,
                content_fill_color=StyleColor(28/255, 28/255, 38/255, 1.0),
                size=Point2D(width, height))
end

# WidgetTabbedPane — a tabbed container with three tabs.
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

# ── shadcn/ui extension widgets ──────────────────────────────────────────────
# Each shows one new widget (some with several states) so its behavior can be
# tested in isolation with make_widget_projection_example.

# WidgetBadge — the four variants stacked.
make_widget_badge_document_example() =
    WidgetComposite(Point2D(40, 40), Any[
        WidgetBadge(Point2D(0,   0), "Default"),
        WidgetBadge(Point2D(0,  44), "Secondary";   variant=:secondary),
        WidgetBadge(Point2D(0,  88), "Destructive"; variant=:destructive),
        WidgetBadge(Point2D(0, 132), "Outline";     variant=:outline),
    ])

# WidgetSeparator — a rule between two labels.
make_widget_separator_document_example() =
    WidgetComposite(Point2D(40, 40), Any[
        WidgetLabel(Point2D(0,  0), "Above the rule"),
        WidgetSeparator(Point2D(0, 44); length=260),
        WidgetLabel(Point2D(0, 64), "Below the rule"),
    ])

# WidgetCard — title + description + body + footer.
make_widget_card_document_example() =
    WidgetCard(Point2D(40, 40);
               title="Create project",
               description="Deploy your new project in one click.",
               content="Name and framework go here.",
               footer="You can change this later.")

# WidgetSwitch — on and off.
make_widget_switch_document_example() =
    WidgetComposite(Point2D(40, 40), Any[
        WidgetSwitch(Point2D(0,  0), true),
        WidgetSwitch(Point2D(0, 44), false),
    ])

# WidgetProgress — a 60% bar.
make_widget_progress_document_example() =
    WidgetProgress(Point2D(40, 40), 0.6; width=260)

# WidgetSlider — a knob at 40%.
make_widget_slider_document_example() =
    WidgetSlider(Point2D(40, 40), 0.4; width=260)

# WidgetRadioGroup — three options, the middle one selected.
make_widget_radio_group_document_example() =
    WidgetRadioGroup(Point2D(40, 40), ["Default", "Comfortable", "Compact"]; selected=2)

# WidgetAvatar — initials in a circle.
make_widget_avatar_document_example() =
    WidgetAvatar(Point2D(40, 40), "JD"; size=64)

# WidgetAlert — default and destructive variants.
make_widget_alert_document_example() =
    WidgetComposite(Point2D(40, 40), Any[
        WidgetAlert(Point2D(0,   0), "Heads up!",
                    "You can add components to your app using the CLI."),
        WidgetAlert(Point2D(0, 110), "Something went wrong",
                    "Your session has expired. Please log in again.";
                    variant=:destructive),
    ])

# WidgetSkeleton — loading placeholders.
make_widget_skeleton_document_example() =
    WidgetComposite(Point2D(40, 40), Any[
        WidgetSkeleton(Point2D(0,  0); width=260, height=20),
        WidgetSkeleton(Point2D(0, 36); width=200, height=20),
        WidgetSkeleton(Point2D(0, 72); width=230, height=20),
    ])
