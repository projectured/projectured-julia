# The widget gallery: one document that demonstrates every widget type, grouped
# into tabs inside a WidgetShell with a Stage-3/4 chrome (horizontal menu bar with
# submenus + shared Actions + Ctrl+S, a toolbar of the same commands, a status bar,
# a tooltip). Project it with make_widget_projection_example. Interactive popups
# (the select dropdown, the context menu, the dialog button) render their closed /
# inline state here; opening them live needs the window-route projection (see
# make_widget_popup_projection_example).
function make_widget_document_example(; width=1024, height=768)
    fb = Inset(1, 1, 1, 1)   # field border

    # Shared commands (Stage 4) with icons (Stage 5): one Action drives a menu item
    # AND a toolbar button, both showing the icon; Save also carries Ctrl+S.
    new_action  = Action("New";  icon=:file)
    open_action = Action("Open"; icon=:folder)
    save_action = Action("Save"; icon=:save, shortcut=Shortcut(:s; ctrl=true))

    # ── Inputs tab ────────────────────────────────────────────────────────────
    inputs = VerticalLayout(Any[
        HorizontalLayout(Any[WidgetLabel(Point2D(0, 0), "Username:"),
                             WidgetText(Point2D(0, 0), "alice"; border=fb, padding=Inset(4, 4, 8, 8))]; gap=12),
        HorizontalLayout(Any[WidgetLabel(Point2D(0, 0), "Email:"),
                             WidgetText(Point2D(0, 0), "alice@example.com"; border=fb, padding=Inset(4, 4, 8, 8))]; gap=12),
        HorizontalLayout(Any[WidgetCheckbox(Point2D(0, 0), true; border=fb, padding=Inset(4, 4, 4, 4)),
                             WidgetLabel(Point2D(0, 0), "Enable notifications")]; gap=12),
        WidgetSwitch(Point2D(0, 0), true),
        WidgetRadioGroup(Point2D(0, 0), ["Default", "Comfortable", "Compact"]; selected=2),
        WidgetSelect(Point2D(0, 0), "Apple"; options=["Apple", "Banana", "Cherry", "Date"], width=220),
        WidgetSlider(Point2D(0, 0), 0.4; width=260),
        WidgetTextarea(Point2D(0, 0), "Type your message here.\nIt can span several lines."; width=340, rows=3),
    ]; gap=16, horizontal_align=:left)

    # ── Buttons & menus tab ───────────────────────────────────────────────────
    tool = (icon) -> WidgetToolButton(icon; size=Point2D(40, 40), border=fb, padding=Inset(8, 8, 8, 8))
    buttons = VerticalLayout(Any[
        WidgetButton(Point2D(0, 0), Point2D(180, 44), save_action;   # label + icon from the command
                     border=fb, padding=Inset(4, 4, 8, 8)),
        WidgetButton(Point2D(0, 0), Point2D(180, 44), "Edit";    # icon on the button itself
                     icon=:pencil, dialog=WidgetMessageBox("Confirm", "Proceed with the action?"),
                     border=fb, padding=Inset(4, 4, 8, 8)),
        # A row of icon-first tool buttons (Stage 5 WidgetToolButton).
        HorizontalLayout(Any[tool(:save), tool(:pencil), tool(:trash), tool(:search)]; gap=8),
        WidgetToggle(Point2D(0, 0), "Bold"; pressed=true),
        WidgetToggleGroup(Point2D(0, 0), ["Left", "Center", "Right"]; selected=2),
        WidgetContextMenu(WidgetLabel(Point2D(0, 0), "Right-click for a context menu"),
                          WidgetMenu([WidgetMenuItem("Cut"), WidgetMenuItem("Copy"),
                                      WidgetMenuItem("Paste")])),
    ]; gap=16, horizontal_align=:left)

    # ── Display tab ───────────────────────────────────────────────────────────
    display = VerticalLayout(Any[
        HorizontalLayout(Any[
            WidgetBadge(Point2D(0, 0), "Default"),
            WidgetBadge(Point2D(0, 0), "Secondary";   variant=:secondary),
            WidgetBadge(Point2D(0, 0), "Destructive"; variant=:destructive),
            WidgetBadge(Point2D(0, 0), "Outline";     variant=:outline),
        ]; gap=8),
        WidgetCard(Point2D(0, 0); title="Create project",
                   description="Deploy your new project in one click.",
                   content="Name and framework go here.", footer="You can change this later."),
        WidgetAlert(Point2D(0, 0), "Heads up!", "You can add components using the CLI."),
        HorizontalLayout(Any[WidgetAvatar(Point2D(0, 0), "JD"; size=56),
                             WidgetProgress(Point2D(0, 0), 0.6; width=260)]; gap=16),
        WidgetSeparator(Point2D(0, 0); length=320),
        WidgetSkeleton(Point2D(0, 0); width=320, height=18),
    ]; gap=16, horizontal_align=:left)

    # ── Data tab ──────────────────────────────────────────────────────────────
    data = VerticalLayout(Any[
        WidgetTable(Point2D(0, 0), ["Invoice", "Status", "Amount"],
                    [["INV001", "Paid",    "\$250.00"],
                     ["INV002", "Pending", "\$150.00"],
                     ["INV003", "Unpaid",  "\$350.00"]]),
        WidgetTree(Point2D(0, 0), Any[
            WidgetTreeNode(:folder, "src", Any[
                WidgetTreeNode(:folder, "components", Any[
                    WidgetTreeNode(:file, "button.jl"),
                    WidgetTreeNode(:file, "card.jl")]),
                WidgetTreeNode(:file, "app.jl")]),
            WidgetTreeNode(:file, "README.md"),
        ]),
        WidgetAccordion(Point2D(0, 0), [
            ("Is it accessible?", "Yes. It adheres to the WAI-ARIA design pattern."),
            ("Is it styled?",     "Yes. It matches the theme."),
        ]; expanded=1),
    ]; gap=16, horizontal_align=:left)

    # ── Layout tab (split pane + scrollable lists) ────────────────────────────
    left_scroll  = WidgetScrollPane(WidgetComposite(Point2D(0, 0),
                       Any[WidgetLabel(Point2D(4, (i - 1) * 44), "Left item $i") for i in 1:8]);
                       size=Point2D(div(width, 2) - 12, height - 200))
    right_scroll = WidgetScrollPane(WidgetComposite(Point2D(0, 0),
                       Any[WidgetLabel(Point2D(4, (i - 1) * 44), "Detail $i") for i in 1:8]);
                       size=Point2D(div(width, 2) - 12, height - 200))
    layout_split = WidgetSplitPane(:horizontal, Any[
        WidgetTitlePane("Navigation", left_scroll;  padding=Inset(4, 4, 4, 4)),
        WidgetTitlePane("Details",    right_scroll; padding=Inset(4, 4, 4, 4)),
    ]; sizes=[div(width, 2), div(width, 2)])

    # ── Forms tab (FormLayout + spin box + list + stacked pages) ──────────────
    # FormLayout is sugar over a 2-column GridLayout: the label column hugs and is
    # right-aligned, the field column fills the seeded width (column stretch). The
    # spin box and list are the new data-entry widgets; StackLayout(active=2) shows
    # a single page (QStackedWidget).
    form = FormLayout([
        (WidgetLabel(Point2D(0, 0), "Name"),
         WidgetText(Point2D(0, 0), "Ada Lovelace"; border=fb, padding=Inset(4, 4, 8, 8))),
        (WidgetLabel(Point2D(0, 0), "Email"),
         WidgetText(Point2D(0, 0), "ada@analytical.engine"; border=fb, padding=Inset(4, 4, 8, 8))),
        (WidgetLabel(Point2D(0, 0), "Quantity"),
         WidgetSpinBox(Point2D(0, 0), 3; min=0, max=99, step=1)),
    ])
    fruits = WidgetList(Point2D(0, 0), ["Apples", "Bananas", "Cherries", "Dates"];
                        selected=2, width=240)
    pages = StackLayout(Any[
        WidgetCard(Point2D(0, 0); title="Page 1", content="First page."),
        WidgetCard(Point2D(0, 0); title="Page 2", content="Second page is active."),
        WidgetCard(Point2D(0, 0); title="Page 3", content="Third page."),
    ]; active=2)
    forms = VerticalLayout(Any[
        form,
        WidgetSeparator(Point2D(0, 0); length=360),
        HorizontalLayout(Any[
            VerticalLayout(Any[WidgetLabel(Point2D(0, 0), "Favorite fruit"), fruits];
                           gap=8, horizontal_align=:left),
            VerticalLayout(Any[WidgetLabel(Point2D(0, 0), "Stacked pages (2 of 3 active)"), pages];
                           gap=8, horizontal_align=:left),
        ]; gap=24),
    ]; gap=16, horizontal_align=:left)

    tabs = WidgetTabbedPane([
        ("Inputs",  inputs,       :pencil),
        ("Buttons", buttons,      :plus),
        ("Forms",   forms,        :file),
        ("Display", display,      :search),
        ("Data",    data,         :folder),
        ("Layout",  layout_split, :menu),
    ])

    # ── Chrome: menu bar (shared actions) + toolbar + status bar + tooltip ─────
    menu_bar = WidgetMenu([
        WidgetMenuItem("File"; submenu=WidgetMenu([
            WidgetMenuItem(new_action),
            WidgetMenuItem(open_action),
            WidgetMenuItem(save_action)])),
        WidgetMenuItem("Edit"; submenu=WidgetMenu([
            WidgetMenuItem("Undo"), WidgetMenuItem("Redo")])),
        WidgetMenuItem("View"; submenu=WidgetMenu([
            WidgetMenuItem("Zoom In"), WidgetMenuItem("Zoom Out")])),
        WidgetMenuItem("Help"; submenu=WidgetMenu([WidgetMenuItem("About")])),
    ]; orientation=:horizontal)
    toolbar = WidgetToolbar([
        WidgetMenuItem(new_action),
        WidgetMenuItem(open_action),
        WidgetMenuItem(save_action),
    ]; padding=Inset(4, 4, 4, 4))
    status_bar = WidgetStatusBar(["Ready", "shadcn widget gallery", "Ln 1, Col 1"])
    tip = WidgetTooltip(Point2D(20, height - 80), Point2D(360, 48),
                        "Widget Gallery — hover items for tips"; visible=false)

    WidgetShell(tabs;
                menu_bar=menu_bar, toolbar=toolbar, status_bar=status_bar, tooltip=tip,
                size=Point2D(width, height))
end

# ── Per-widget examples ──────────────────────────────────────────────────────
#
# The gallery above (make_widget_document_example) crams every widget into one
# document. The functions below do the opposite: each builds the smallest
# possible document exercising a single widget type, so a widget's behavior can
# be tested in isolation. Pair each with make_widget_projection_example, except
# the editable text widget, which needs make_widget_text_projection_example.

# Layout offsets are authored in logical pixels and stay fixed: the single global
# `_DISPLAY_SCALE` is applied uniformly at the SDL render boundary (so authoring
# them in device pixels would double-count on hi-dpi displays), and font-zoom
# deliberately leaves hard-coded geometry put — only text-derived content boxes
# re-fit the larger glyphs (via re-projection on `AdjustFontZoomOperation`).
_wy(px::Integer) = px

# WidgetLabel — a positioned, non-interactive label.
make_widget_label_document_example() =
    WidgetLabel(Point2D(40, 40), "Hello, label")

# WidgetText — an editable text widget. Its content is a TextBlock, so the widget
# recurses it through the Text domain and all caret navigation / text editing
# comes from TextToGraphics (the widget only maps the resulting references
# backward). Click to place the cursor, then type / backspace to edit. Render
# with make_widget_text_projection_example.
function make_widget_text_document_example()
    content = TextBlock(TextString("edit me", font_ubuntu_monospace_regular_20, color_default))
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

# WidgetOffered — widgets under a REAL offer, which no other example gives them.
#
# Every other widget example draws its widget standalone, in a composite or a
# vertical stack, and neither of those offers a height. So they exercise the path
# where a widget sizes itself from its content, and never the path where a parent
# hands it an extent to fill — which is the path the sizing rules decide.
#
# The shell is what makes the offer real: it has a size of its own and seeds it
# into its content on both axes. Inside it, a horizontal split divides that width
# between two columns, so every widget below is drawn under an allocation.
#
# The left column holds widgets that should FILL the width they are given. The
# right one holds a scroll pane that AUTHORED a size, which must hold against the
# offer rather than be stretched by it, beside one that authored none.
function make_widget_offered_document_example(; width=760, height=420)
    filling = VerticalLayout(Any[
        WidgetAlert(Point2D(0, 0), "Filling", "This alert takes the width it is offered."),
        WidgetCard(Point2D(0, 0); title="Card", content="And so does this card."),
    ]; gap=12, child_width=Fill)
    # Filled, so the picture shows each pane's extent: a fixture that guards a
    # size has to draw the size it guards.
    holding = VerticalLayout(Any[
        WidgetScrollPane(WidgetLabel(Point2D(4, 4), "authored 200x90");
                         size=Point2D(200, 90),
                         content_fill_color=StyleColor(0.86, 0.92, 0.98, 1.0)),
        # No size of its own, and a weight instead: it asks the column for the
        # height the sized pane leaves. That is how a viewport gets an extent
        # without one being written on it.
        LayoutConstraint(WidgetScrollPane(WidgetLabel(Point2D(4, 4), "asks for the rest");
                                          content_fill_color=StyleColor(0.98, 0.92, 0.86, 1.0));
                         height=Fill),
    ]; gap=12, child_width=Fill)
    split = WidgetSplitPane(:horizontal, Any[filling, holding];
                            sizes=[div(width, 2), div(width, 2)])
    WidgetShell(split; size=Point2D(width, height))
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

# WidgetTransformPane — a zoom/pan viewport over an over-tall composite.
# Ctrl+wheel zooms about the cursor; a plain wheel pans.
function make_widget_transform_pane_document_example(; width=400, height=300, line_height=40)
    items = [WidgetLabel(Point2D(4, _wy((i - 1) * line_height)), "Item $i") for i in 1:20]
    WidgetTransformPane(WidgetComposite(Point2D(0, 0), Any[items...]);
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
        WidgetLabel(Point2D(0, _wy(40)), "menu + toolbar share Actions; Ctrl+S is a shortcut"),
    ])
    # Shared commands (Stage 4): one Action drives both a File-menu item and a
    # toolbar button; Save additionally has a Ctrl+S shortcut the shell dispatches.
    new_action  = Action("New")
    open_action = Action("Open")
    save_action = Action("Save"; shortcut=Shortcut(:s; ctrl=true))
    # A horizontal menu bar (QMenuBar): each top-level entry opens a submenu popup
    # on click (Stage 3 Step 4c); the File items present the shared commands.
    menu_bar = WidgetMenu([
        WidgetMenuItem("File"; submenu=WidgetMenu([
            WidgetMenuItem(new_action),
            WidgetMenuItem(open_action),
            WidgetMenuItem(save_action)])),
        WidgetMenuItem("Edit"; submenu=WidgetMenu([
            WidgetMenuItem("Undo"), WidgetMenuItem("Redo")])),
        WidgetMenuItem("Help"; submenu=WidgetMenu([
            WidgetMenuItem("About")])),
    ]; orientation=:horizontal)
    toolbar  = WidgetToolbar([WidgetMenuItem(new_action),
                              WidgetMenuItem(open_action),
                              WidgetMenuItem(save_action)];
                             padding=Inset(4, 4, 4, 4))
    status_bar = WidgetStatusBar(["Ready", "Ln 1, Col 1"])
    WidgetShell(content;
                menu_bar=menu_bar, toolbar=toolbar, status_bar=status_bar,
                size=Point2D(width, height))
end

# WidgetPopup — a screen of interactive popup-opening widgets (Stage 3 Step 6).
# The default window holds a horizontal menu bar, a select dropdown, and a right-click
# context-menu target; a pre-opened floating popup window shows an open menu so the
# window route renders in a static sweep. Project it with the screen-route
# make_widget_popup_projection_example (WindowManager + WidgetPopupResolver +
# ScreenToScreen), which turns a trigger's OpenPopupOperation into a real popup
# window anchored at the trigger's screen position.
function make_widget_popup_document_example(; width=520, height=360)
    select = WidgetSelect(Point2D(0, 0), "Apple";
                          options=["Apple", "Banana", "Cherry"], width=200)
    menu_bar = WidgetMenu([
        WidgetMenuItem("File"; submenu=WidgetMenu([WidgetMenuItem("New"), WidgetMenuItem("Open")])),
        WidgetMenuItem("Edit"; submenu=WidgetMenu([WidgetMenuItem("Undo"), WidgetMenuItem("Redo")])),
    ]; orientation=:horizontal)
    target = WidgetContextMenu(
        WidgetLabel(Point2D(0, 0), "right-click for a context menu"),
        WidgetMenu([WidgetMenuItem("Cut"), WidgetMenuItem("Copy"), WidgetMenuItem("Paste")]))
    content = VerticalLayout(Any[menu_bar, select, target]; gap=20, horizontal_align=:left)

    main = WindowDocument(; id=:widget_popup_main, title="Widget popup",
                          x=0, y=0, width=width, height=height, content=content)
    # A pre-opened floating popup so a static sweep/screenshot shows the window route.
    popup_menu = WidgetMenu([WidgetMenuItem("New"), WidgetMenuItem("Open"), WidgetMenuItem("Save")])
    popup = WindowDocument(; id=:widget_popup, title="", x=24, y=130,
                           width=160, height=120, style=:floating, auto_dismiss=true,
                           content=popup_menu)
    ScreenDocument([main, popup])
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
        # `duration` (ms) opts each switch into a knob-slide animation on toggle;
        # the third snaps instantly (duration defaults to 0).
        WidgetSwitch(Point2D(0, 0), true;  duration=200),
        WidgetSwitch(Point2D(0, 0), false; duration=200),
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

# WidgetSelect — a select showing a value + chevron, with a list of options a
# click opens as a dropdown popup (the window route is wired by the screen-level
# pipeline; see plan/pending/widget-popup-overlay.md Step 6).
make_widget_select_document_example() =
    WidgetSelect(Point2D(40, 40), "Apple";
                 options=["Apple", "Banana", "Cherry", "Date"], width=220)

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

# A table handed an offer, which a bare table cannot show.
#
# A grid's row height is its tallest cell, and a cell that authored no height
# fills what it is offered — so a table inside a viewport drew ONE row as tall as
# the viewport and pushed the rest below the fold. The picture is what guards it:
# the four rows stay the height of their text inside the pane.
make_widget_table_offered_document_example() =
    WidgetScrollPane(
        WidgetTable(Point2D(0, 0),
                    ["Invoice", "Status", "Amount"],
                    [["INV001", "Paid",    "\$250.00"],
                     ["INV002", "Pending", "\$150.00"],
                     ["INV003", "Unpaid",  "\$350.00"]]);
        size = Point2D(300, 140),
        content_fill_color = StyleColor(0.98, 0.96, 0.90, 1.0))

# A table whose header strips stay put while its body scrolls.
#
# Scrolled 60 down and 40 across, so the picture shows what a frozen prefix is
# for: the column names are still at the top, the ordinals are still at the left,
# the corner has not moved, and the body has travelled away from all three.
make_widget_table_frozen_document_example() =
    WidgetScrollPane(
        WidgetTable(Point2D(0, 0),
                    Any["Invoice", "Status", "Method", "Amount"],
                    Any["1", "2", "3", "4", "5", "6"],
                    Any[Any["INV00$(i)", "Paid", "Credit Card", "\$$(i)50.00"] for i in 1:6],
                    4);
        size = Point2D(320, 150),
        scroll_position = Point2D(40, 60),
        content_fill_color = StyleColor(0.98, 0.96, 0.90, 1.0))

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
    sel = get_first_focusable_path(layout)
    sel === nothing || set_selection!(layout, sel)
    layout
end

# ── Atomic-registry widgets ────────────────────────────────────────────────
# One bare instance per widget/screen type with a printer but no atom above:
# each is either a type nothing above constructs standing alone, or one whose
# `_atom` suffix disambiguates it from an existing same-named factory above
# that shows the type as a small multi-state showcase (several variants in a
# `VerticalLayout`, or wrapped in a `WidgetShell`) rather than the type by
# itself.

make_widget_context_menu_document_example() =
    WidgetContextMenu(WidgetLabel(Point2D(40, 40), "Right-click for options"),
                      WidgetMenu([WidgetMenuItem("Cut"), WidgetMenuItem("Copy"), WidgetMenuItem("Paste")]))

make_widget_dialog_document_example() =
    WidgetMessageBox("Confirm", "Proceed with the action?")

make_widget_insertion_document_example() = WidgetInsertion()

make_widget_list_document_example() =
    WidgetList(Point2D(40, 40), ["Apples", "Bananas", "Cherries"]; selected=2, width=200)

function make_widget_option_document_example()
    select = WidgetSelect(Point2D(40, 40), "Apple"; options=["Apple", "Banana"], width=200)
    WidgetOption(Point2D(40, 84), select, "Banana")
end

make_widget_spin_box_document_example() =
    WidgetSpinBox(Point2D(40, 40), 3; min=0, max=10, step=1)

make_widget_status_bar_document_example() =
    WidgetStatusBar(["Ready", "Ln 1, Col 1"])

make_tooltip_source_document_example() =
    TooltipSource(; child=WidgetLabel(Point2D(40, 40), "Hover me"),
                    content=WidgetLabel(Point2D(0, 0), "A helpful tip"),
                    id=:tooltip_source_example)

make_clipboard_collection_document_example() =
    ClipboardCollection(WidgetLabel(Point2D(0, 0), "Copied selection"),
                        Any[WidgetLabel(Point2D(0, 0), "Row 1"), WidgetLabel(Point2D(0, 0), "Row 2")])

function make_clipboard_slice_document_example()
    content = WidgetLabel(Point2D(0, 0), "Copied label")
    ClipboardSlice(; content=content, slice=Reference(FieldReferenceStep("content")))
end

function make_reference_inspector_document_example()
    target = WidgetLabel(Point2D(0, 0), "Hello")
    ReferenceInspector(; reference=Reference(FieldReferenceStep("content")), target=target)
end

make_graphics_canvas_document_example() =
    GraphicsCanvas(Any[
        GraphicsRect(0, 0, 120, 40, color_solarized_blue),
        GraphicsRect(0, 60, 120, 40, color_solarized_gray),
    ]; w=120, h=100)

function make_screen_document_document_example()
    content = WidgetLabel(Point2D(40, 40), "A window on screen")
    ScreenDocument([WindowDocument(; id=:screen_example, title="Example window",
                                   width=400, height=300, content=content)])
end

make_window_document_document_example() =
    WindowDocument(; id=:window_example, title="Example window",
                  width=400, height=300,
                  content=WidgetLabel(Point2D(40, 40), "Inside a window"))

# WidgetAlert — a single alert, distinct from `make_widget_alert_document_example`
# above (which stacks the default and destructive variants).
make_widget_alert_atom_document_example() =
    WidgetAlert(Point2D(40, 40), "Heads up!", "You can add components using the CLI.")

# WidgetBadge — a single badge, distinct from `make_widget_badge_document_example`
# above (which stacks all four variants).
make_widget_badge_atom_document_example() =
    WidgetBadge(Point2D(40, 40), "Default")

# WidgetSeparator — a single rule, distinct from `make_widget_separator_document_example`
# above (which frames it between two labels).
make_widget_separator_atom_document_example() =
    WidgetSeparator(Point2D(40, 40); length=260)

# WidgetSkeleton — a single placeholder block, distinct from
# `make_widget_skeleton_document_example` above (which stacks three).
make_widget_skeleton_atom_document_example() =
    WidgetSkeleton(Point2D(40, 40); width=260, height=20)

# WidgetSwitch — a single switch, distinct from `make_widget_switch_document_example`
# above (which stacks on/off/instant variants).
make_widget_switch_atom_document_example() =
    WidgetSwitch(Point2D(40, 40), true)

# WidgetTabbedPane — bare (no `WidgetShell` chrome), distinct from
# `make_widget_tabbed_pane_document_example` above.
make_widget_tabbed_pane_atom_document_example() =
    WidgetTabbedPane([
        ("Alpha", WidgetLabel(Point2D(16, 16), "Content A")),
        ("Beta",  WidgetLabel(Point2D(16, 16), "Content B")),
    ])

# WidgetToggle — a single toggle, distinct from `make_widget_toggle_document_example`
# above (which stacks pressed and unpressed).
make_widget_toggle_atom_document_example() =
    WidgetToggle(Point2D(40, 40), "Bold"; pressed=true)
