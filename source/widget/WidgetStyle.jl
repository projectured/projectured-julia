# Fragment of `WidgetModule` — the style documents: the colors that a widget
# takes instead of the colors of its projection.

"""
    WidgetStyle(; margin_color, border_color, padding_color, content_color, label_text_color)

The colors that a widget takes instead of the colors of its projection. Give it
to the `style` field of a widget. A field that is `nothing`, the default, takes
the style field of the projection with the same name, and a field with a color
replaces it.

The fields are the parts that every widget has: the four parts of its box, from
the outside in, and its text. `label_text_color` changes the color of the text
and keeps the font of the projection. `color_transparent` removes a part, and
the printer then adds no element for it.

A widget type with more parts has a style of its own, with these five fields and
the parts of its type. Many widgets can share one style, of any type, and a
change to the style changes all of them.

# Example

    WidgetLabel(Point2D(0, 0), "Runs"; style = WidgetStyle(margin_color = color_red))
"""
@document struct WidgetStyle <: WidgetDocument
    margin_color::Any = nothing
    border_color::Any = nothing
    padding_color::Any = nothing
    content_color::Any = nothing
    label_text_color::Any = nothing
end

"""
    WidgetCheckboxStyle(; <the fields of WidgetStyle>, indicator_color, indicator_checked_color,
                        indicator_stroke_color, check_color)

The style of a `WidgetCheckbox`: the fields of `WidgetStyle`, and the box that
shows the value (`indicator_…`) and the tick in it (`check_color`).
"""
@document struct WidgetCheckboxStyle <: WidgetDocument
    margin_color::Any = nothing
    border_color::Any = nothing
    padding_color::Any = nothing
    content_color::Any = nothing
    label_text_color::Any = nothing
    indicator_color::Any = nothing
    indicator_checked_color::Any = nothing
    indicator_stroke_color::Any = nothing
    check_color::Any = nothing
end

"""
    WidgetDialogStyle(; <the fields of WidgetStyle>, title_text_color, body_text_color)

The style of a `WidgetDialog`: the fields of `WidgetStyle`, and the title and the
body text.
"""
@document struct WidgetDialogStyle <: WidgetDocument
    margin_color::Any = nothing
    border_color::Any = nothing
    padding_color::Any = nothing
    content_color::Any = nothing
    label_text_color::Any = nothing
    title_text_color::Any = nothing
    body_text_color::Any = nothing
end

"""
    WidgetTitlePaneStyle(; <the fields of WidgetStyle>, title_bar_color, title_text_color,
                         body_text_color)

The style of a `WidgetTitlePane`: the fields of `WidgetStyle`, the fill of the
title row (`title_bar_color`), and the title and the body text.
"""
@document struct WidgetTitlePaneStyle <: WidgetDocument
    margin_color::Any = nothing
    border_color::Any = nothing
    padding_color::Any = nothing
    content_color::Any = nothing
    label_text_color::Any = nothing
    title_bar_color::Any = nothing
    title_text_color::Any = nothing
    body_text_color::Any = nothing
end

"""
    WidgetSplitPaneStyle(; <the fields of WidgetStyle>, splitter_stroke_color)

The style of a `WidgetSplitPane`: the fields of `WidgetStyle`, and the color of
the splitter between its slots.
"""
@document struct WidgetSplitPaneStyle <: WidgetDocument
    margin_color::Any = nothing
    border_color::Any = nothing
    padding_color::Any = nothing
    content_color::Any = nothing
    label_text_color::Any = nothing
    splitter_stroke_color::Any = nothing
end

"""
    WidgetTabbedPaneStyle(; <the fields of WidgetStyle>, tab_strip_color, tab_color,
                          tab_selected_color, tab_text_color, tab_selected_text_color,
                          page_color)

The style of a `WidgetTabbedPane`: the fields of `WidgetStyle`, the tab strip and
its tabs, and the page area below the strip.
"""
@document struct WidgetTabbedPaneStyle <: WidgetDocument
    margin_color::Any = nothing
    border_color::Any = nothing
    padding_color::Any = nothing
    content_color::Any = nothing
    label_text_color::Any = nothing
    tab_strip_color::Any = nothing
    tab_color::Any = nothing
    tab_selected_color::Any = nothing
    tab_text_color::Any = nothing
    tab_selected_text_color::Any = nothing
    page_color::Any = nothing
end

"""
    WidgetScrollBarStyle(; <the fields of WidgetStyle>, track_color, thumb_color)

The style of a `WidgetScrollBar`: the fields of `WidgetStyle`, the rail
(`track_color`) and the thumb (`thumb_color`).
"""
@document struct WidgetScrollBarStyle <: WidgetDocument
    margin_color::Any = nothing
    border_color::Any = nothing
    padding_color::Any = nothing
    content_color::Any = nothing
    label_text_color::Any = nothing
    track_color::Any = nothing
    thumb_color::Any = nothing
end
