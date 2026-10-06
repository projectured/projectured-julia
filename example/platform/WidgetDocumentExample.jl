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
        HorizontalLayout(Any[WidgetLabel("Username:"),
                             WidgetText("alice"; border=fb, padding=Inset(4, 4, 8, 8))]; gap=12),
        HorizontalLayout(Any[WidgetLabel("Email:"),
                             WidgetText("alice@example.com"; border=fb, padding=Inset(4, 4, 8, 8))]; gap=12),
        WidgetCheckbox(true; label = "Enable notifications"),
        WidgetSwitch(; checked = true, label = "Live update"),
        WidgetRadioGroup(["Default", "Comfortable", "Compact"]; selected=2),
        WidgetSelect("Apple"; options=["Apple", "Banana", "Cherry", "Date"], width=220),
        WidgetSlider(0.4; width=260),
        WidgetTextarea("Type your message here.\nIt can span several lines."; width=340, rows=3),
    ]; gap=16, horizontal_align=:left)

    # ── Buttons & menus tab ───────────────────────────────────────────────────
    tool = (icon) -> WidgetToolButton(icon; size=Point2D(40, 40), border=fb, padding=Inset(8, 8, 8, 8))
    buttons = VerticalLayout(Any[
        WidgetButton(save_action;   # label + icon from the command
                     size = Point2D(180, 44), border=fb, padding=Inset(4, 4, 8, 8)),
        WidgetButton("Edit";    # icon on the button itself
                     size = Point2D(180, 44), icon=:pencil, dialog=WidgetMessageBox("Confirm", "Proceed with the action?"),
                     border=fb, padding=Inset(4, 4, 8, 8)),
        # A row of icon-first tool buttons (Stage 5 WidgetToolButton).
        HorizontalLayout(Any[tool(:save), tool(:pencil), tool(:trash), tool(:search)]; gap=8),
        WidgetToggle("Bold"; pressed=true),
        WidgetToggleGroup(["Left", "Center", "Right"]; selected=2),
        WidgetContextMenu(WidgetLabel("Right-click for a context menu"),
                          WidgetMenu([WidgetMenuItem("Cut"), WidgetMenuItem("Copy"),
                                      WidgetMenuItem("Paste")])),
    ]; gap=16, horizontal_align=:left)

    # ── Display tab ───────────────────────────────────────────────────────────
    display = VerticalLayout(Any[
        HorizontalLayout(Any[
            WidgetBadge("Default"),
            WidgetBadge("Secondary";   variant=:secondary),
            WidgetBadge("Destructive"; variant=:destructive),
            WidgetBadge("Outline";     variant=:outline),
        ]; gap=8),
        WidgetCard(; title="Create project",
                   description="Deploy your new project in one click.",
                   content="Name and framework go here.", footer="You can change this later."),
        WidgetAlert("Heads up!"; description = "You can add components using the CLI."),
        HorizontalLayout(Any[WidgetAvatar("JD"; size=56),
                             WidgetProgressBar(0.6; width=260)]; gap=16),
        WidgetSeparator(; length=320),
        WidgetSkeleton(; width=320, height=18),
    ]; gap=16, horizontal_align=:left)

    # ── Data tab ──────────────────────────────────────────────────────────────
    data = VerticalLayout(Any[
        WidgetTable(["Invoice", "Status", "Amount"],
                    [["INV001", "Paid",    "\$250.00"],
                     ["INV002", "Pending", "\$150.00"],
                     ["INV003", "Unpaid",  "\$350.00"]]),
        WidgetTree(Any[
            WidgetTreeNode(:folder, "src", Any[
                WidgetTreeNode(:folder, "components", Any[
                    WidgetTreeNode(:file, "button.jl"),
                    WidgetTreeNode(:file, "card.jl")]),
                WidgetTreeNode(:file, "app.jl")]),
            WidgetTreeNode(:file, "README.md"),
        ]; expanded = Set([[1], [1, 1]])),
        WidgetAccordion([
            ("Is it accessible?", "Yes. It adheres to the WAI-ARIA design pattern."),
            ("Is it styled?",     "Yes. It matches the theme."),
        ]; expanded=1),
    ]; gap=16, horizontal_align=:left)

    # ── Layout tab (split pane + scrollable lists) ────────────────────────────
    left_scroll  = WidgetScrollPane(WidgetComposite(Any[WidgetLabel("Left item $i"; position = Point2D(4, (i - 1) * 44)) for i in 1:8]);
                       size=Point2D(div(width, 2) - 12, height - 200))
    right_scroll = WidgetScrollPane(WidgetComposite(Any[WidgetLabel("Detail $i"; position = Point2D(4, (i - 1) * 44)) for i in 1:8]);
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
        (WidgetLabel("Name"),
         WidgetText("Ada Lovelace"; border=fb, padding=Inset(4, 4, 8, 8))),
        (WidgetLabel("Email"),
         WidgetText("ada@analytical.engine"; border=fb, padding=Inset(4, 4, 8, 8))),
        (WidgetLabel("Quantity"),
         WidgetSpinBox(3; min=0, max=99, step=1)),
    ])
    fruits = WidgetList(["Apples", "Bananas", "Cherries", "Dates"];
                        selected=2, width=240)
    pages = StackLayout(Any[
        WidgetCard(; title="Page 1", content="First page."),
        WidgetCard(; title="Page 2", content="Second page is active."),
        WidgetCard(; title="Page 3", content="Third page."),
    ]; active=2)
    forms = VerticalLayout(Any[
        form,
        WidgetSeparator(; length=360),
        HorizontalLayout(Any[
            VerticalLayout(Any[WidgetLabel("Favorite fruit"), fruits];
                           gap=8, horizontal_align=:left),
            VerticalLayout(Any[WidgetLabel("Stacked pages (2 of 3 active)"), pages];
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
    tip = WidgetTooltip("Widget Gallery — hover items for tips"; position = Point2D(20, height - 80), size = Point2D(360, 48), visible=false)

    WidgetShell(tabs;
                menu_bar=menu_bar, toolbar=toolbar, status_bar=status_bar, overlay=tip,
                size=Point2D(width, height))
end

# ── Per-widget examples ──────────────────────────────────────────────────────
#
# The gallery above (make_widget_document_example) crams every widget into one
# document. The functions below do the opposite: each builds the smallest
# possible document exercising a single widget type, so a widget's behavior can
# be tested in isolation. Pair each with make_widget_projection_example, except
# the editable text widget, which needs make_widget_text_projection_example.

# Layout offsets are authored in logical pixels and stay fixed: the device pixel
# ratio of the `Display` is applied uniformly at the SDL render boundary (so authoring
# them in device pixels would double-count on hi-dpi displays), and a font-scale
# change deliberately leaves hard-coded geometry put — only text-derived content
# boxes re-fit the larger glyphs (via re-projection on `AdjustScaleOperation`).
_wy(px::Integer) = px

# WidgetLabel — a positioned, non-interactive label.
make_widget_label_document_example() =
    WidgetLabel("Hello, label"; position = Point2D(40, 40))

# WidgetText — an editable text widget. Its content is a TextBlock, so the widget
# recurses it through the Text domain and all caret navigation / text editing
# comes from TextToGraphics (the widget only maps the resulting references
# backward). Click to place the cursor, then type / backspace to edit. Render
# with make_widget_text_projection_example.
function make_widget_text_document_example()
    content = TextBlock(TextString("edit me", StyleFont("Ubuntu Mono", 20), color_default))
    WidgetText(content;
               position = Point2D(40, 40), border=Inset(1, 1, 1, 1),
               padding=Inset(8, 8, 12, 12))
end

# WidgetCheckbox — a checkbox; content is the boolean checked state.
make_widget_checkbox_document_example() =
    WidgetCheckbox(true;
                   position = Point2D(40, 40), padding=Inset(4, 4, 4, 4))

# WidgetButton — a clickable button.
make_widget_button_document_example() =
    WidgetButton("Click me";
                 position = Point2D(40, 40), size = Point2D(180, 56), padding=Inset(4, 4, 8, 8))

# WidgetButton (behaviour) — a button whose `action` increments a counter shown
# by a sibling label. Click it (real input or a scripted MouseClick) and the
# label re-renders; the button lights while its mouse target names it, that is
# while the pointer is on it. The action captures
# the label so it can mutate it when the editor evaluates the
# InvokeWidgetActionOperation.
function make_widget_button_action_document_example()
    count = Ref(0)
    label = WidgetLabel("count: 0"; position = Point2D(40, 40))
    button = WidgetButton("Increment";
                          position = Point2D(40, 84), size = Point2D(180, 48), action = (_editor) -> begin
                              count[] += 1
                              label.content = "count: $(count[])"
                          end,
                          padding=Inset(4, 4, 8, 8))
    WidgetComposite(Any[label, button])
end

# WidgetButton / WidgetLabel (image content) — a label and a button whose
# `content` is an ImageFile instead of a string. The leaf printers detect the
# ImageDocument and emit a GraphicsImage (a muted placeholder until the image is
# decoded). Reuses the lazy-decoding inline-image loader.
function make_widget_button_image_document_example()
    logo = _load_inline_image("projectured.png")
    icon = _load_inline_image("file.png")
    picture_label = WidgetLabel(logo; position = Point2D(40, 40))
    icon_button = WidgetButton(icon;
                               position = Point2D(40, 200), size = Point2D(72, 72), action = (_editor) -> nothing,
                               padding=Inset(8, 8, 8, 8))
    WidgetComposite(Any[picture_label, icon_button])
end

# WidgetTooltip — a floating tooltip overlay (visible so it renders standalone).
make_widget_tooltip_document_example() =
    WidgetTooltip("A floating tooltip"; position = Point2D(40, 40), size = Point2D(360, 56))

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

# WidgetToolbarItem — the buttons of a toolbar: a picture, a disabled picture and
# a label with no picture. Each is flat at rest and a button under the pointer.
make_widget_toolbar_item_document_example() =
    WidgetToolbar(Any[WidgetToolbarItem("Run"; icon = :play),
                      WidgetToolbarItem("Stop"; icon = :stop, enabled = false),
                      WidgetToolbarItem("Log")])

# WidgetComposite — a positioned container of child widgets.
make_widget_composite_document_example() =
    WidgetComposite(Any[
        WidgetLabel("First"; position = Point2D(0, _wy(0))),
        WidgetLabel("Second"; position = Point2D(0, _wy(40))),
        WidgetLabel("Third"; position = Point2D(0, _wy(80))),
    ]; position = Point2D(40, 40))

# WidgetTitlePane — a pane with a title bar and a content area. The body stays a
# positioned WidgetComposite: WidgetTitlePane places its content as a positioned
# widget, so a (position-less) layout child is not the right fit here.
function make_widget_title_pane_document_example()
    body = WidgetComposite(Any[
        WidgetLabel("Detail one"; position = Point2D(0, _wy(0))),
        WidgetLabel("Detail two"; position = Point2D(0, _wy(40))),
    ])
    WidgetTitlePane("Details", body; padding=Inset(4, 4, 4, 4))
end

# WidgetSplitPane — two child panes divided along an axis.
function make_widget_split_pane_document_example(; width=600)
    left  = WidgetTitlePane("Left",  WidgetLabel("Left content"; position = Point2D(8, 8)))
    right = WidgetTitlePane("Right", WidgetLabel("Right content"; position = Point2D(8, 8)))
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
        WidgetAlert("Filling"; description = "This alert takes the width it is offered."),
        WidgetCard(; title="Card", content="And so does this card."),
    ]; gap=12, child_width=Fill)
    # Filled, so the picture shows each pane's extent: a fixture that guards a
    # size has to draw the size it guards.
    holding = VerticalLayout(Any[
        WidgetScrollPane(WidgetLabel("authored 200x90"; position = Point2D(4, 4));
                         size=Point2D(200, 90),
                         style=WidgetStyle(content_color=StyleColor(0.86, 0.92, 0.98, 1.0))),
        # No size of its own, and a weight instead: it asks the column for the
        # height the sized pane leaves. That is how a viewport gets an extent
        # without one being written on it.
        LayoutConstraint(WidgetScrollPane(WidgetLabel("asks for the rest"; position = Point2D(4, 4));
                                          style=WidgetStyle(content_color=StyleColor(0.98, 0.92, 0.86, 1.0)));
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
    items = [WidgetLabel("Item $i"; position = Point2D(4, _wy((i - 1) * line_height))) for i in 1:20]
    WidgetScrollPane(WidgetComposite(Any[items...]);
                     size=Point2D(width, height),
                     border=Inset(1, 1, 1, 1))
end

# WidgetTransformPane — a zoom/pan viewport over an over-tall composite.
# Ctrl+wheel zooms about the cursor; a plain wheel pans.
function make_widget_transform_pane_document_example(; width=400, height=300, line_height=40)
    items = [WidgetLabel("Item $i"; position = Point2D(4, _wy((i - 1) * line_height))) for i in 1:20]
    WidgetTransformPane(WidgetComposite(Any[items...]);
                        size=Point2D(width, height),
                        border=Inset(1, 1, 1, 1))
end

# WidgetShell — a top-level window shell with a menu bar and toolbar.
function make_widget_shell_document_example(; width=600, height=400)
    # Content stays a positioned WidgetComposite: WidgetShell places its content
    # as a positioned widget below the menu/toolbar bands, so a position-less
    # layout child is not the right fit here.
    content = WidgetComposite(Any[
        WidgetLabel("Inside a shell"; position = Point2D(0, _wy(0))),
        WidgetLabel("menu + toolbar share Actions; Ctrl+S is a shortcut"; position = Point2D(0, _wy(40))),
    ]; position = Point2D(16, 16))
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
# make_widget_popup_projection_example (WindowManager + ScreenToScreen), which
# turns a trigger's OpenPopupOperation into a real popup window at the trigger's
# screen position.
function make_widget_popup_document_example(; width=520, height=360)
    select = WidgetSelect("Apple";
                          options=["Apple", "Banana", "Cherry"], width=200)
    menu_bar = WidgetMenu([
        WidgetMenuItem("File"; submenu=WidgetMenu([WidgetMenuItem("New"), WidgetMenuItem("Open")])),
        WidgetMenuItem("Edit"; submenu=WidgetMenu([WidgetMenuItem("Undo"), WidgetMenuItem("Redo")])),
    ]; orientation=:horizontal)
    target = WidgetContextMenu(
        WidgetLabel("right-click for a context menu"),
        WidgetMenu([WidgetMenuItem("Cut"), WidgetMenuItem("Copy"), WidgetMenuItem("Paste")]))
    content = VerticalLayout(Any[menu_bar, select, target]; gap=20, horizontal_align=:left)

    main = WindowDocument(; id=:widget_popup_main, title="Widget popup",
                          x=0, y=0, width=width, height=height, content=content)
    # A pre-opened popup window so a static sweep/screenshot shows the window route.
    popup_menu = WidgetMenu([WidgetMenuItem("New"), WidgetMenuItem("Open"), WidgetMenuItem("Save")])
    popup = WindowDocument(; id=:widget_popup, title="", x=24, y=130,
                           width=160, height=120, style=:popup, auto_dismiss=true,
                           content=popup_menu)
    ScreenDocument([main, popup])
end

# WidgetTabbedPane — a tabbed container with three tabs.
function make_widget_tabbed_pane_document_example(; width=600, height=400)
    tab_alpha = WidgetLabel("Content A"; position = Point2D(16, 16))
    tab_beta  = WidgetLabel("Content B"; position = Point2D(16, 16))
    tab_gamma = WidgetLabel("Content C"; position = Point2D(16, 16))

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
        WidgetBadge("Default"),
        WidgetBadge("Secondary";   variant=:secondary),
        WidgetBadge("Destructive"; variant=:destructive),
        WidgetBadge("Outline";     variant=:outline),
    ]; gap=12)

# WidgetSeparator — a rule between two labels, stacked by a VerticalLayout.
make_widget_separator_document_example() =
    VerticalLayout(Any[
        WidgetLabel("Above the rule"),
        WidgetSeparator(; length=260),
        WidgetLabel("Below the rule"),
    ]; gap=12)

# WidgetCard — title + description + body + footer.
make_widget_card_document_example() =
    WidgetCard(;
               position = Point2D(40, 40), title="Create project",
               description="Deploy your new project in one click.",
               content="Name and framework go here.",
               footer="You can change this later.")

# WidgetCard that folds — a chevron before the title says whether the body is
# shown, and a click anywhere on the header band flips it. The title is a
# Document, because the header band is the title's own box. The second card
# starts collapsed, so both states are on screen at once.
make_widget_collapsible_card_document_example() =
    VerticalLayout(Any[
        WidgetCard(;
                   title=WidgetLabel("Details"),
                   content="The body of an open card.",
                   collapsible=true),
        WidgetCard(;
                   title=WidgetLabel("More details"),
                   content="The body of a collapsed card, which is not drawn.",
                   collapsible=true, collapsed=true),
    ]; gap=12)

# WidgetSwitch — on and off, stacked by a VerticalLayout.
make_widget_switch_document_example() =
    VerticalLayout(Any[
        WidgetSwitch(; checked = true),
        WidgetSwitch(; checked = false),
        WidgetSwitch(; checked = false),
    ]; gap=12)

# WidgetProgressBar — a 60% bar and a bar whose value is not known, stacked by a
# VerticalLayout.
make_widget_progress_bar_document_example() =
    VerticalLayout(Any[
        WidgetProgressBar(0.6; width=260),
        WidgetProgressBar(; width=260),
    ]; gap=12)

# WidgetProgressRing — rings at 0, 25, 60 and 100 percent and a ring whose value
# is not known, then a table of jobs with a column of rings.
make_widget_progress_ring_document_example() =
    VerticalLayout(Any[
        HorizontalLayout(Any[WidgetProgressRing(0.0), WidgetProgressRing(0.25), WidgetProgressRing(0.6),
                             WidgetProgressRing(1.0), WidgetProgressRing()]; gap=12),
        WidgetTable(["Job", "Done", "State"],
                    [["Parse",    WidgetProgressRing(1.0), "Finished"],
                     ["Simulate", WidgetProgressRing(0.4), "Running"],
                     ["Plot",     WidgetProgressRing(),    "Waiting"]]),
    ]; gap=16, horizontal_align=:left)

# WidgetSlider — a knob at 40%.
make_widget_slider_document_example() =
    WidgetSlider(0.4; position = Point2D(40, 40), width=260)

# WidgetRadioGroup — three options, the middle one selected.
make_widget_radio_group_document_example() =
    WidgetRadioGroup(["Default", "Comfortable", "Compact"]; position = Point2D(40, 40), selected=2)

# WidgetAvatar — initials in a circle.
make_widget_avatar_document_example() =
    WidgetAvatar("JD"; position = Point2D(40, 40), size=64)

# WidgetAlert — default and destructive variants, stacked by a VerticalLayout
# (the gap is uniform regardless of how tall each alert's text wraps).
make_widget_alert_document_example() =
    VerticalLayout(Any[
        WidgetAlert("Heads up!"; description = "You can add components to your app using the CLI."),
        WidgetAlert("Something went wrong";
                    description = "Your session has expired. Please log in again.", variant=:destructive),
    ]; gap=12)

# WidgetSkeleton — loading placeholders, stacked by a VerticalLayout.
make_widget_skeleton_document_example() =
    VerticalLayout(Any[
        WidgetSkeleton(; width=260, height=20),
        WidgetSkeleton(; width=200, height=20),
        WidgetSkeleton(; width=230, height=20),
    ]; gap=12)

# WidgetSwatch — the squares of three colors in a row; the last names its own size.
make_widget_swatch_document_example() =
    HorizontalLayout(Any[
        WidgetSwatch(color_solarized_blue),
        WidgetSwatch(color_solarized_green),
        WidgetSwatch(color_solarized_red; size=24),
    ]; gap=8, vertical_align=:center)

# WidgetToggle — a pressed and an unpressed toggle, stacked by a VerticalLayout.
make_widget_toggle_document_example() =
    VerticalLayout(Any[
        WidgetToggle("Bold";   pressed=true),
        WidgetToggle("Italic"; pressed=false),
    ]; gap=12)

# WidgetToggleGroup — a three-segment control with the middle selected.
make_widget_toggle_group_document_example() =
    WidgetToggleGroup(["Left", "Center", "Right"]; position = Point2D(40, 40), selected=2)

# WidgetSelect — a select showing a value + chevron, with a list of options a
# click opens as a dropdown popup (the window route is wired by the screen-level
# pipeline; see plan/pending/widget-popup-overlay.md Step 6).
make_widget_select_document_example() =
    WidgetSelect("Apple";
                 position = Point2D(40, 40), options=["Apple", "Banana", "Cherry", "Date"], width=220)

# WidgetTextarea — a multi-line text surface.
make_widget_textarea_document_example() =
    WidgetTextarea("Type your message here.\nIt can span several lines."; position = Point2D(40, 40), width=340, rows=4)

# WidgetAccordion — two items, the first expanded.
make_widget_accordion_document_example() =
    WidgetAccordion([
        ("Is it accessible?", "Yes. It adheres to the WAI-ARIA design pattern."),
        ("Is it styled?",     "Yes. It comes with default styles that match the theme."),
    ]; position = Point2D(40, 40), expanded=1)

# WidgetTable — a data table.
make_widget_table_document_example() =
    WidgetTable(["Invoice", "Status", "Method", "Amount"],
                [["INV001", "Paid",    "Credit Card", "\$250.00"],
                 ["INV002", "Pending", "PayPal",      "\$150.00"],
                 ["INV003", "Unpaid",  "Bank Transfer", "\$350.00"]]; position = Point2D(40, 40))

# A table handed an offer, which a bare table cannot show.
#
# A grid's row height is its tallest cell, and a cell that authored no height
# fills what it is offered — so a table inside a viewport drew ONE row as tall as
# the viewport and pushed the rest below the fold. The picture is what guards it:
# the four rows stay the height of their text inside the pane.
make_widget_table_offered_document_example() =
    WidgetScrollPane(
        WidgetTable(["Invoice", "Status", "Amount"],
                    [["INV001", "Paid",    "\$250.00"],
                     ["INV002", "Pending", "\$150.00"],
                     ["INV003", "Unpaid",  "\$350.00"]]);
        size = Point2D(300, 140),
        style = WidgetStyle(content_color = StyleColor(0.98, 0.96, 0.90, 1.0)))

# A table whose header strips stay put while its body scrolls.
#
# Scrolled 60 down and 40 across, so the picture shows what the parts of a table
# are for: the column names are still at the top, the ordinals are still at the
# left, the corner has not moved, and the body has travelled away from all
# three. The pane only gives the table its size, which the table fills and
# scrolls in.
make_widget_table_frozen_document_example() =
    WidgetScrollPane(
        WidgetTable(;
                    column_headers = Any["Invoice", "Status", "Method", "Amount"],
                    row_headers = Any["1", "2", "3", "4", "5", "6"],
                    cells = Any[Any["INV00$(i)", "Paid", "Credit Card", "\$$(i)50.00"] for i in 1:6],
                    scroll_position = Point2D(40, 60));
        size = Point2D(320, 150),
        style = WidgetStyle(content_color = StyleColor(0.98, 0.96, 0.90, 1.0)))

# WidgetTree — a nested outline with expand chevrons.
make_widget_tree_document_example() =
    WidgetTree(Any[
        ("src", Any[
            ("components", Any["button.jl", "card.jl", "table.jl"]),
            "app.jl",
        ]),
        ("test", Any["runtests.jl"]),
        "README.md",
    ]; position = Point2D(40, 40), expanded = Set([[1], [1, 1], [2]]))

# Interaction state — each control shown enabled then disabled, stacked by a
# VerticalLayout. The disabled variants render with the theme's muted tokens and
# (for Button/Checkbox) their readers swallow clicks; see the `enabled` flag in
# document/Widget.jl and plan/pending/widget-interaction-state.md.
make_widget_disabled_document_example() =
    VerticalLayout(Any[
        WidgetButton("Enabled"; size = Point2D(180, 48)),
        WidgetButton("Disabled"; size = Point2D(180, 48), enabled=false),
        WidgetCheckbox(true),
        WidgetCheckbox(true; enabled=false),
        WidgetSwitch(; checked = true),
        WidgetSwitch(; checked = true, enabled=false),
        WidgetToggle("Bold"; pressed=true),
        WidgetToggle("Bold"; pressed=true, enabled=false),
        WidgetSelect("Apple"; width=220),
        WidgetSelect("Apple"; width=220, enabled=false),
    ]; gap=12)

# Focus traversal — a column of controls with an initial selection on the first,
# so the focus ring is visible and Tab / Shift-Tab cycle the selection (the
# disabled control is skipped). See plan/pending/widget-focus-traversal.md.
function make_widget_focus_document_example()
    layout = VerticalLayout(Any[
        WidgetButton("First"; size = Point2D(180, 44)),
        WidgetCheckbox(true),
        WidgetButton("Disabled"; size = Point2D(180, 44), enabled=false),
        WidgetButton("Last"; size = Point2D(180, 44)),
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
    WidgetContextMenu(WidgetLabel("Right-click for options"; position = Point2D(40, 40)),
                      WidgetMenu([WidgetMenuItem("Cut"), WidgetMenuItem("Copy"), WidgetMenuItem("Paste")]))

make_widget_dialog_document_example() =
    WidgetMessageBox("Confirm", "Proceed with the action?")

make_widget_insertion_document_example() = WidgetInsertion()

make_widget_list_document_example() =
    WidgetList(["Apples", "Bananas", "Cherries"]; position = Point2D(40, 40), selected=2, width=200)

function make_widget_option_document_example()
    select = WidgetSelect("Apple"; position = Point2D(40, 40), options=["Apple", "Banana"], width=200)
    WidgetOption(select, "Banana"; position = Point2D(40, 84))
end

make_widget_spin_box_document_example() =
    WidgetSpinBox(3; position = Point2D(40, 40), min=0, max=10, step=1)

make_widget_status_bar_document_example() =
    WidgetStatusBar(["Ready", "Ln 1, Col 1"])

make_tooltip_source_document_example() =
    TooltipSource(; child=WidgetLabel("Hover me"; position = Point2D(40, 40)),
                    content=WidgetLabel("A helpful tip"),
                    id=:tooltip_source_example)

make_clipboard_collection_document_example() =
    ClipboardCollection(WidgetLabel("Copied selection"),
                        Any[WidgetLabel("Row 1"), WidgetLabel("Row 2")])

function make_clipboard_slice_document_example()
    content = WidgetLabel("Copied label")
    ClipboardSlice(; content=content, slice=Reference(FieldReferenceStep("content")))
end

function make_reference_inspector_document_example()
    target = WidgetLabel("Hello")
    ReferenceInspector(; reference=Reference(FieldReferenceStep("content")), target=target)
end

make_graphics_canvas_document_example() =
    GraphicsCanvas(Any[
        GraphicsRect(0, 0, 120, 40; color = color_solarized_blue),
        GraphicsRect(0, 60, 120, 40; color = color_solarized_gray),
    ]; w=120, h=100)

function make_screen_document_document_example()
    content = WidgetLabel("A window on screen"; position = Point2D(40, 40))
    ScreenDocument([WindowDocument(; id=:screen_example, title="Example window",
                                   width=400, height=300, content=content)])
end

make_window_document_document_example() =
    WindowDocument(; id=:window_example, title="Example window",
                  width=400, height=300,
                  content=WidgetLabel("Inside a window"; position = Point2D(40, 40)))

# WidgetAlert — a single alert, distinct from `make_widget_alert_document_example`
# above (which stacks the default and destructive variants).
make_widget_alert_atom_document_example() =
    WidgetAlert("Heads up!"; position = Point2D(40, 40), description = "You can add components using the CLI.")

# WidgetBadge — a single badge, distinct from `make_widget_badge_document_example`
# above (which stacks all four variants).
make_widget_badge_atom_document_example() =
    WidgetBadge("Default"; position = Point2D(40, 40))

# WidgetSeparator — a single rule, distinct from `make_widget_separator_document_example`
# above (which frames it between two labels).
make_widget_separator_atom_document_example() =
    WidgetSeparator(; position = Point2D(40, 40), length=260)

# WidgetSkeleton — a single placeholder block, distinct from
# `make_widget_skeleton_document_example` above (which stacks three).
make_widget_skeleton_atom_document_example() =
    WidgetSkeleton(; position = Point2D(40, 40), width=260, height=20)

# WidgetSwatch — a single swatch, distinct from `make_widget_swatch_document_example`
# above (which shows three).
make_widget_swatch_atom_document_example() =
    WidgetSwatch(color_solarized_blue; position = Point2D(40, 40))

# WidgetSwitch — a single switch, distinct from `make_widget_switch_document_example`
# above (which stacks on/off/instant variants).
make_widget_switch_atom_document_example() =
    WidgetSwitch(; position = Point2D(40, 40), checked = true)

# WidgetTabbedPane — bare (no `WidgetShell` chrome), distinct from
# `make_widget_tabbed_pane_document_example` above.
make_widget_tabbed_pane_atom_document_example() =
    WidgetTabbedPane([
        ("Alpha", WidgetLabel("Content A"; position = Point2D(16, 16))),
        ("Beta",  WidgetLabel("Content B"; position = Point2D(16, 16))),
    ])

# WidgetToggle — a single toggle, distinct from `make_widget_toggle_document_example`
# above (which stacks pressed and unpressed).
make_widget_toggle_atom_document_example() =
    WidgetToggle("Bold"; position = Point2D(40, 40), pressed=true)
