function make_widget_document_example(; width=1024, height=768, line_height=56)
    # All colors come from the widget theme — this gallery only positions widgets.
    field_border = Inset(1, 1, 1, 1)

    # ── Form tab ──────────────────────────────────────────────────────────────
    name_label  = WidgetLabel(Point2D(0,           0),           "Username:")
    name_field  = WidgetText( Point2D(280,          0),           "alice"; border=field_border)

    email_label = WidgetLabel(Point2D(0,           line_height), "Email:")
    email_field = WidgetText( Point2D(280,          line_height), "alice@example.com"; border=field_border)

    notify_check = WidgetCheckbox(Point2D(0,   2 * line_height), true)
    notify_label = WidgetLabel(  Point2D(100,  2 * line_height), "Enable notifications")

    save_btn = WidgetButton(Point2D(0, 3 * line_height), Point2D(180, line_height), "Save")

    form_composite = WidgetComposite(Point2D(16, 16), Any[
        name_label,  name_field,
        email_label, email_field,
        notify_check, notify_label,
        save_btn,
    ])

    form_scroll = WidgetScrollPane(form_composite;
                                   size=Point2D(width - 2, height - 80))

    # ── List tab ──────────────────────────────────────────────────────────────
    item_labels = [WidgetLabel(Point2D(4, (i - 1) * line_height), "Item $i")
                   for i in 1:20]

    list_composite = WidgetComposite(Point2D(0, 0), Any[item_labels...])

    list_scroll = WidgetScrollPane(list_composite;
                                   size=Point2D(width - 2, height - 80),
                                   border=Inset(1, 1, 1, 1))

    # ── Layout tab ────────────────────────────────────────────────────────────
    left_labels = [WidgetLabel(Point2D(4, (i - 1) * line_height), "Left item $i")
                   for i in 1:8]
    right_labels = [WidgetLabel(Point2D(4, (i - 1) * line_height), "Right item $i")
                    for i in 1:8]

    left_scroll  = WidgetScrollPane(WidgetComposite(Point2D(0, 0), Any[left_labels...]);
                                    size=Point2D(div(width, 2) - 4, height - 120))
    right_scroll = WidgetScrollPane(WidgetComposite(Point2D(0, 0), Any[right_labels...]);
                                    size=Point2D(div(width, 2) - 4, height - 120))

    left_pane  = WidgetTitlePane("Navigation", left_scroll; padding=Inset(4, 4, 4, 4))
    right_pane = WidgetTitlePane("Details", right_scroll; padding=Inset(4, 4, 4, 4))

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
                                       size=Point2D(width - 2, height - 80))

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
    ]; padding=Inset(4, 4, 4, 4))

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
                size=Point2D(width, height))
end

# ── Per-widget examples ──────────────────────────────────────────────────────
#
# The gallery above (make_widget_document_example) crams every widget into one
# document. The functions below do the opposite: each builds the smallest
# possible document exercising a single widget type, so a widget's behavior can
# be tested in isolation. Pair each with make_widget_projection_example, except
# the editable text widget, which needs make_widget_text_projection_example.

# Layout offsets are authored in logical pixels. The widget projection scales
# every widget's position by the font scale at render time, so these stay
# logical here (scaling them now would double-count on hi-dpi displays).
_wy(px::Integer) = px

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
               padding=Inset(8, 8, 12, 12))
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

# WidgetButton (behaviour) — a button whose `action` increments a counter shown
# by a sibling label. Click it (real input or a scripted MousePress) and the
# label re-renders; hovering re-styles the button via its transient `hovered`
# flag (cleared by WidgetHoverTrackingProjection on leave). The action captures
# the label so it can mutate it when the editor evaluates the
# InvokeWidgetActionOperation.
function make_widget_button_action_document_example()
    count = Ref(0)
    label = WidgetLabel(Point2D(40, 40), "count: 0")
    button = WidgetButton(Point2D(40, 84), Point2D(180, 48), "Increment";
                          action = (_editor) -> begin
                              count[] += 1
                              label.content = "count: $(count[])"
                          end,
                          border=Inset(1, 1, 1, 1), border_color=color_default,
                          padding=Inset(4, 4, 8, 8))
    WidgetComposite(Point2D(0, 0), Any[label, button])
end

# WidgetButton / WidgetLabel (image content) — a label and a button whose
# `content` is an ImageFile instead of a string. The leaf printers detect the
# ImageDocument and emit a GraphicsImage (a muted placeholder until the image is
# decoded). Reuses the lazy-decoding inline-image loader.
function make_widget_button_image_document_example()
    logo = _load_inline_image("projectured.png")
    icon = _load_inline_image("file.png")
    picture_label = WidgetLabel(Point2D(40, 40), logo)
    icon_button = WidgetButton(Point2D(40, 200), Point2D(72, 72), icon;
                               action = (_editor) -> nothing,
                               border=Inset(1, 1, 1, 1), border_color=color_default,
                               padding=Inset(8, 8, 8, 8))
    WidgetComposite(Point2D(0, 0), Any[picture_label, icon_button])
end

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
        WidgetLabel(Point2D(0, _wy(0)),  "First"),
        WidgetLabel(Point2D(0, _wy(40)), "Second"),
        WidgetLabel(Point2D(0, _wy(80)), "Third"),
    ])

# WidgetTitlePane — a pane with a title bar and a content area. The body stays a
# positioned WidgetComposite: WidgetTitlePane places its content as a positioned
# widget, so a (position-less) layout child is not the right fit here.
function make_widget_title_pane_document_example()
    body = WidgetComposite(Point2D(0, 0), Any[
        WidgetLabel(Point2D(0, _wy(0)),  "Detail one"),
        WidgetLabel(Point2D(0, _wy(40)), "Detail two"),
    ])
    WidgetTitlePane("Details", body; padding=Inset(4, 4, 4, 4))
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
function make_widget_scroll_pane_document_example(; width=400, height=300, line_height=40)
    items = [WidgetLabel(Point2D(4, _wy((i - 1) * line_height)), "Item $i") for i in 1:20]
    WidgetScrollPane(WidgetComposite(Point2D(0, 0), Any[items...]);
                     size=Point2D(width, height),
                     border=Inset(1, 1, 1, 1))
end

# WidgetShell — a top-level window shell with a menu bar and toolbar.
function make_widget_shell_document_example(; width=600, height=400)
    # Content stays a positioned WidgetComposite: WidgetShell places its content
    # as a positioned widget below the menu/toolbar bands, so a position-less
    # layout child is not the right fit here.
    content = WidgetComposite(Point2D(16, 16), Any[
        WidgetLabel(Point2D(0, _wy(0)),  "Inside a shell"),
        WidgetLabel(Point2D(0, _wy(40)), "with a menu bar and toolbar"),
    ])
    menu_bar = WidgetMenu([WidgetMenuItem("File"), WidgetMenuItem("Edit"),
                           WidgetMenuItem("Help")])
    toolbar  = WidgetToolbar([WidgetMenuItem("New"), WidgetMenuItem("Open"),
                              WidgetMenuItem("Save")]; padding=Inset(4, 4, 4, 4))
    WidgetShell(content;
                menu_bar=menu_bar, toolbar=toolbar,
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

    WidgetShell(tabs; size=Point2D(width, height))
end

# ── Extension widgets ──────────────────────────────────────────────
# Each shows one new widget (some with several states) so its behavior can be
# tested in isolation with make_widget_projection_example.

# WidgetBadge — the four variants stacked by a VerticalLayout (no hand-placed
# offsets; the layout spaces them from their intrinsic heights + a gap).
make_widget_badge_document_example() =
    VerticalLayout(Any[
        WidgetBadge(Point2D(0, 0), "Default"),
        WidgetBadge(Point2D(0, 0), "Secondary";   variant=:secondary),
        WidgetBadge(Point2D(0, 0), "Destructive"; variant=:destructive),
        WidgetBadge(Point2D(0, 0), "Outline";     variant=:outline),
    ]; gap=12)

# WidgetSeparator — a rule between two labels, stacked by a VerticalLayout.
make_widget_separator_document_example() =
    VerticalLayout(Any[
        WidgetLabel(Point2D(0, 0), "Above the rule"),
        WidgetSeparator(Point2D(0, 0); length=260),
        WidgetLabel(Point2D(0, 0), "Below the rule"),
    ]; gap=12)

# WidgetCard — title + description + body + footer.
make_widget_card_document_example() =
    WidgetCard(Point2D(40, 40);
               title="Create project",
               description="Deploy your new project in one click.",
               content="Name and framework go here.",
               footer="You can change this later.")

# WidgetSwitch — on and off, stacked by a VerticalLayout.
make_widget_switch_document_example() =
    VerticalLayout(Any[
        WidgetSwitch(Point2D(0, 0), true),
        WidgetSwitch(Point2D(0, 0), false),
    ]; gap=12)

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

# WidgetAlert — default and destructive variants, stacked by a VerticalLayout
# (the gap is uniform regardless of how tall each alert's text wraps).
make_widget_alert_document_example() =
    VerticalLayout(Any[
        WidgetAlert(Point2D(0, 0), "Heads up!",
                    "You can add components to your app using the CLI."),
        WidgetAlert(Point2D(0, 0), "Something went wrong",
                    "Your session has expired. Please log in again.";
                    variant=:destructive),
    ]; gap=12)

# WidgetSkeleton — loading placeholders, stacked by a VerticalLayout.
make_widget_skeleton_document_example() =
    VerticalLayout(Any[
        WidgetSkeleton(Point2D(0, 0); width=260, height=20),
        WidgetSkeleton(Point2D(0, 0); width=200, height=20),
        WidgetSkeleton(Point2D(0, 0); width=230, height=20),
    ]; gap=12)

# WidgetToggle — a pressed and an unpressed toggle, stacked by a VerticalLayout.
make_widget_toggle_document_example() =
    VerticalLayout(Any[
        WidgetToggle(Point2D(0, 0), "Bold";   pressed=true),
        WidgetToggle(Point2D(0, 0), "Italic"; pressed=false),
    ]; gap=12)

# WidgetToggleGroup — a three-segment control with the middle selected.
make_widget_toggle_group_document_example() =
    WidgetToggleGroup(Point2D(40, 40), ["Left", "Center", "Right"]; selected=2)

# WidgetSelect — a closed select showing a value + chevron.
make_widget_select_document_example() =
    WidgetSelect(Point2D(40, 40), "Apple"; width=220)

# WidgetTextarea — a multi-line text surface.
make_widget_textarea_document_example() =
    WidgetTextarea(Point2D(40, 40),
                   "Type your message here.\nIt can span several lines."; width=340, rows=4)

# WidgetAccordion — two items, the first expanded.
make_widget_accordion_document_example() =
    WidgetAccordion(Point2D(40, 40), [
        ("Is it accessible?", "Yes. It adheres to the WAI-ARIA design pattern."),
        ("Is it styled?",     "Yes. It comes with default styles that match the theme."),
    ]; expanded=1)

# WidgetTable — a data table.
make_widget_table_document_example() =
    WidgetTable(Point2D(40, 40),
                ["Invoice", "Status", "Method", "Amount"],
                [["INV001", "Paid",    "Credit Card", "\$250.00"],
                 ["INV002", "Pending", "PayPal",      "\$150.00"],
                 ["INV003", "Unpaid",  "Bank Transfer", "\$350.00"]])

# WidgetTree — a nested outline with expand chevrons.
make_widget_tree_document_example() =
    WidgetTree(Point2D(40, 40), Any[
        ("src", Any[
            ("components", Any["button.jl", "card.jl", "table.jl"]),
            "app.jl",
        ]),
        ("test", Any["runtests.jl"]),
        "README.md",
    ])

# Interaction state — each control shown enabled then disabled, stacked by a
# VerticalLayout. The disabled variants render with the theme's muted tokens and
# (for Button/Checkbox) their readers swallow clicks; see the `enabled` flag in
# document/Widget.jl and plan/pending/widget-interaction-state.md.
make_widget_disabled_document_example() =
    VerticalLayout(Any[
        WidgetButton(Point2D(0, 0), Point2D(180, 48), "Enabled"),
        WidgetButton(Point2D(0, 0), Point2D(180, 48), "Disabled"; enabled=false),
        WidgetCheckbox(Point2D(0, 0), true),
        WidgetCheckbox(Point2D(0, 0), true; enabled=false),
        WidgetSwitch(Point2D(0, 0), true),
        WidgetSwitch(Point2D(0, 0), true; enabled=false),
        WidgetToggle(Point2D(0, 0), "Bold"; pressed=true),
        WidgetToggle(Point2D(0, 0), "Bold"; pressed=true, enabled=false),
        WidgetSelect(Point2D(0, 0), "Apple"; width=220),
        WidgetSelect(Point2D(0, 0), "Apple"; width=220, enabled=false),
    ]; gap=12)

# Focus traversal — a column of controls with an initial selection on the first,
# so the focus ring is visible and Tab / Shift-Tab cycle the selection (the
# disabled control is skipped). See plan/pending/widget-focus-traversal.md.
function make_widget_focus_document_example()
    layout = VerticalLayout(Any[
        WidgetButton(Point2D(0, 0), Point2D(180, 44), "First"),
        WidgetCheckbox(Point2D(0, 0), true),
        WidgetButton(Point2D(0, 0), Point2D(180, 44), "Disabled"; enabled=false),
        WidgetButton(Point2D(0, 0), Point2D(180, 44), "Last"),
    ]; gap=12)
    sel = first_focusable_path(layout)
    sel === nothing || set_selection!(layout, sel)
    layout
end
