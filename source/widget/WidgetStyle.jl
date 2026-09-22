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
