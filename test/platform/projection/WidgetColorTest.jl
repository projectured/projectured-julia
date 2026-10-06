# The colors of the widgets. Every color that a widget printer draws comes from
# the theme, from a color that the projection derives from the theme, or from a
# style that the document gives. The override of a style wins over the style
# field of the projection, a state keeps its own field, and a disabled widget
# ignores the override. Each box part is drawn at the size of its inset, and a
# transparent part adds no element.

_color_test_measure = FixedMeasure(8, 12, 4, 0)

# Every color that a canvas tree draws: the fills, the outlines, the lines and
# the texts. A rect of no size draws nothing, so its colors do not count.
function _drawn_colors(canvas)
    out = StyleColor[]
    walk(c) = for el in c.elements
        el = el isa CellModule.Cell ? el[] : el
        if el isa GraphicsCanvas
            walk(el)
        elseif el isa GraphicsViewport
            walk(el.content)
        elseif el isa GraphicsRect
            (Int(el.w) > 0 && Int(el.h) > 0) || continue
            push!(out, el.color)
            Int(el.border_width) > 0 && push!(out, el.border_color)
        elseif el isa GraphicsCircle || el isa GraphicsPolygon
            push!(out, el.color)
            Int(el.border_width) > 0 && push!(out, el.border_color)
        elseif el isa GraphicsText || el isa GraphicsLine || el isa GraphicsPolyline || el isa GraphicsArc
            push!(out, el.color)
        end
    end
    walk(canvas)
    out
end

# Every rect of a canvas tree that draws something.
function _drawn_rects(canvas)
    out = GraphicsRect[]
    walk(c) = for el in c.elements
        el = el isa CellModule.Cell ? el[] : el
        el isa GraphicsCanvas && walk(el)
        el isa GraphicsViewport && walk(el.content)
        el isa GraphicsRect && Int(el.w) > 0 && Int(el.h) > 0 && push!(out, el)
    end
    walk(canvas)
    out
end

_has_color(colors, color) = any(c -> is_color_equal(c, color), colors)

# A theme whose every color token is a color that no constant of the code uses,
# and whose text styles take those colors. A color in the output that is none of
# them, and no color that a style names, is a constant of a printer.
function _make_probe_theme()
    base = make_widget_theme()
    count = Ref(0)
    probe() = (count[] += 1; StyleColor(count[] / 101, 0.37, 1 - count[] / 101, 1.0))
    values = Dict{Symbol, Any}()
    for name in get_theme_field_names(WidgetTheme)
        value = getproperty(base, name)
        values[name] = value isa ThemeColor ? probe() : value
    end
    WidgetTheme(; values...)
end

# The colors of a theme, and the colors that the projections derive from it. The
# text styles that the projections derive — the body, the title, the caption and
# the label — take their color from a palette field that the loop already covers.
function _theme_colors(theme)
    colors = StyleColor[color_transparent]
    for name in get_theme_field_names(WidgetTheme)
        value = getproperty(theme, name)
        value isa StyleColor && push!(colors, value)
    end
    see_through(color, alpha) = StyleColor(color.red, color.green, color.blue, alpha)
    # The ring of a part selected as a whole and the band of a selected row come
    # from the graphics theme, which the probe leaves at its default.
    ring = get_theme_defaults(GraphicsTheme).selection_ring
    push!(colors, ring, see_through(ring, 0.25),                       # the band of a selected row
                  see_through(theme.primary, 0.25),                   # the area of a highlight
                  color_interpolate(theme.muted, theme.background, 0.5))  # a tinted card
    colors
end

# Every color that a style or a text style in the document tree names.
function _style_colors(document)
    out = StyleColor[]
    seen = IdDict{Any, Bool}()
    function visit(value, is_style::Bool)
        if value isa CellModule.Cell
            visit(value[], is_style)
        elseif value isa StyleColor
            is_style && push!(out, value)
        elseif value isa StyleText
            is_style && push!(out, value.color)
        elseif value isa AbstractVector
            haskey(seen, value) && return
            seen[value] = true
            foreach(v -> visit(v, false), value)
        elseif value isa Document
            haskey(seen, value) && return
            seen[value] = true
            style = endswith(string(nameof(typeof(value))), "Style")
            for name in fieldnames(typeof(value))
                field = try getproperty(value, name) catch; nothing end
                visit(field, style || name === :text_style)
            end
        end
    end
    visit(document, false)
    out
end

# The widget examples that the probe theme renders. The editable text box and
# the popup are left out: one needs the text domain and the other the screen
# domain, and their colors are not the widget layer's.
const _PROBED_WIDGET_DOCUMENTS = (make_widget_document_example,
    make_widget_accordion_document_example, make_widget_alert_atom_document_example,
    make_widget_alert_document_example, make_widget_avatar_document_example,
    make_widget_badge_atom_document_example, make_widget_badge_document_example,
    make_widget_button_action_document_example, make_widget_button_document_example,
    make_widget_button_image_document_example, make_widget_card_document_example,
    make_widget_checkbox_document_example, make_widget_collapsible_card_document_example,
    make_widget_composite_document_example, make_widget_context_menu_document_example,
    make_widget_dialog_document_example, make_widget_disabled_document_example,
    make_widget_focus_document_example, make_widget_insertion_document_example,
    make_widget_label_document_example, make_widget_list_document_example,
    make_widget_menu_document_example, make_widget_menu_item_document_example,
    make_widget_offered_document_example, make_widget_option_document_example,
    make_widget_progress_bar_document_example, make_widget_progress_ring_document_example,
    make_widget_radio_group_document_example,
    make_widget_scroll_bar_document_example, make_widget_scroll_pane_document_example,
    make_widget_select_document_example, make_widget_separator_atom_document_example,
    make_widget_separator_document_example, make_widget_shell_document_example,
    make_widget_skeleton_atom_document_example, make_widget_skeleton_document_example,
    make_widget_slider_document_example, make_widget_spin_box_document_example,
    make_widget_split_pane_document_example, make_widget_status_bar_document_example,
    make_widget_switch_atom_document_example, make_widget_switch_document_example,
    make_widget_tabbed_pane_atom_document_example, make_widget_tabbed_pane_document_example,
    make_widget_table_document_example, make_widget_table_frozen_document_example,
    make_widget_table_offered_document_example, make_widget_textarea_document_example,
    make_widget_title_pane_document_example, make_widget_toggle_atom_document_example,
    make_widget_toggle_document_example, make_widget_toggle_group_document_example,
    make_widget_toolbar_document_example, make_widget_toolbar_item_document_example,
    make_widget_tooltip_document_example,
    make_widget_transform_pane_document_example, make_widget_tree_document_example)

function test_widget_colors()
@testset "Widget colors" begin

render(projection, widget) = print_document(projection, nothing, widget, PrinterContext()).output
default_projection = RecursiveProjection(TypeDispatchingProjection(
    WidgetToGraphics(StyleFont("Ubuntu", 20); measure = _color_test_measure).dispatch))
theme = make_widget_theme()
red = StyleColor(1.0, 0.0, 0.0, 1.0)

@testset "every color comes from the theme or from a style" begin
    probe = _make_probe_theme()
    projection = RecursiveProjection(TypeDispatchingProjection(
        WidgetToGraphics(StyleFont("Ubuntu", 20); measure = _color_test_measure, theme = probe).dispatch))
    allowed = _theme_colors(probe)
    for make in _PROBED_WIDGET_DOCUMENTS
        @testset "$(nameof(make))" begin
            document = make()
            known = vcat(allowed, _style_colors(document))
            stray = filter(c -> !_has_color(known, c), _drawn_colors(render(projection, document)))
            @test isempty(stray)
        end
    end
end

@testset "an override wins, a state keeps its field, a disabled widget ignores the override" begin
    red_surface = WidgetStyle(padding_color = red, content_color = red)
    button(; kw...) = WidgetButton("Save"; style = red_surface, kw...)
    @test _has_color(_drawn_colors(render(default_projection, button())), red)
    @test !_has_color(_drawn_colors(render(default_projection, button(enabled = false))), red)
    # A lit button draws its layer over the surface that the override gives.
    lit = button()
    getfield(lit, :mouse_target)[] = EmptyReference()
    colors = _drawn_colors(render(default_projection, lit))
    @test _has_color(colors, red) && _has_color(colors, WidgetModule._get_hover_layer(make_scaled_theme(theme)))
    # The override of the normal state does not reach the checked state, and
    # the override of the checked state does.
    on(style) = WidgetToggle("Bold"; pressed = true, style)
    normal_only = _drawn_colors(render(default_projection,
        on(WidgetToggleStyle(padding_color = red, content_color = red))))
    @test !_has_color(normal_only, red) && _has_color(normal_only, get_theme_value(theme, :accent))
    @test _has_color(_drawn_colors(render(default_projection,
        on(WidgetToggleStyle(padding_checked_color = red, content_checked_color = red)))), red)
end

@testset "each box part is drawn at the size of its inset" begin
    margin_color, border_color, padding_color, content_color =
        StyleColor(1.0, 0.0, 0.0, 1.0), StyleColor(0.0, 1.0, 0.0, 1.0),
        StyleColor(0.0, 0.0, 1.0, 1.0), StyleColor(1.0, 1.0, 0.0, 1.0)
    label = WidgetLabel("Runs"; margin = Inset(3, 3, 3, 3), border = Inset(2, 2, 2, 2),
                        padding = Inset(5, 5, 5, 5),
                        style = WidgetStyle(; margin_color, border_color, padding_color, content_color))
    output = render(default_projection, label)
    rects = _drawn_rects(output)
    # The label is 4 × 8 wide and 16 high, and the insets add 2 × (3 + 2 + 5).
    @test Int(output.w) == 32 + 20 && Int(output.h) == 16 + 20
    margins = filter(r -> is_color_equal(r.color, margin_color), rects)
    @test length(margins) == 4
    @test any(r -> Int(r.x) == 0 && Int(r.y) == 0 && Int(r.w) == 52 && Int(r.h) == 3, margins)
    # A uniform border is the outline of one rect at the border box.
    @test any(r -> is_color_equal(r.border_color, border_color) && Int(r.border_width) == 2 &&
                   Int(r.x) == 3 && Int(r.y) == 3 && Int(r.w) == 46 && Int(r.h) == 30, rects)
    paddings = filter(r -> is_color_equal(r.color, padding_color), rects)
    @test length(paddings) == 4
    @test any(r -> Int(r.x) == 5 && Int(r.y) == 5 && Int(r.w) == 42 && Int(r.h) == 5, paddings)
    contents = filter(r -> is_color_equal(r.color, content_color), rects)
    @test length(contents) == 1
    @test Int(only(contents).x) == 10 && Int(only(contents).y) == 10
end

@testset "a transparent part adds no element" begin
    # The page of a tabbed pane is transparent by default and adds no rect; a
    # page color adds one.
    tabs(; kw...) = WidgetTabbedPane([("One", WidgetLabel("a"))]; kw...)
    @test !_has_color(_drawn_colors(render(default_projection, tabs())), red)
    @test count(c -> is_color_equal(c, red),
                _drawn_colors(render(default_projection, tabs(style = WidgetTabbedPaneStyle(page_color = red))))) == 1
    # A label draws no box at all by default.
    @test isempty(_drawn_rects(render(default_projection, WidgetLabel("a"))))
    # A transparent surface with a visible border keeps the rect of its outline.
    clear = WidgetText("x";
                       style = WidgetStyle(padding_color = color_transparent, content_color = color_transparent))
    rects = _drawn_rects(render(default_projection, clear))
    @test any(r -> is_color_transparent(r.color) && Int(r.border_width) == 1 &&
                   is_color_equal(r.border_color, get_theme_value(theme, :input)), rects)
    @test !any(r -> is_color_equal(r.color, get_theme_value(theme, :background)), rects)
end

end
end
