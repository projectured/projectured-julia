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

    WidgetLabel("Runs"; style = WidgetStyle(margin_color = color_red))
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

"""
    WidgetBadgeStyle(; <the fields of WidgetStyle>, secondary_padding_color, secondary_content_color,
                     secondary_border_color, secondary_label_text_color, destructive_padding_color,
                     destructive_content_color, destructive_border_color, destructive_label_text_color,
                     outline_padding_color, outline_content_color, outline_border_color,
                     outline_label_text_color)

The style of a `WidgetBadge`: the fields of `WidgetStyle`, and the surface and
the label of each of its three other variants.
"""
@document struct WidgetBadgeStyle <: WidgetDocument
    margin_color::Any = nothing
    border_color::Any = nothing
    padding_color::Any = nothing
    content_color::Any = nothing
    label_text_color::Any = nothing
    secondary_padding_color::Any = nothing
    secondary_content_color::Any = nothing
    secondary_border_color::Any = nothing
    secondary_label_text_color::Any = nothing
    destructive_padding_color::Any = nothing
    destructive_content_color::Any = nothing
    destructive_border_color::Any = nothing
    destructive_label_text_color::Any = nothing
    outline_padding_color::Any = nothing
    outline_content_color::Any = nothing
    outline_border_color::Any = nothing
    outline_label_text_color::Any = nothing
end

"""
    WidgetSeparatorStyle(; <the fields of WidgetStyle>, divider_stroke_color)

The style of a `WidgetSeparator`: the fields of `WidgetStyle`, and the color of
its rule.
"""
@document struct WidgetSeparatorStyle <: WidgetDocument
    margin_color::Any = nothing
    border_color::Any = nothing
    padding_color::Any = nothing
    content_color::Any = nothing
    label_text_color::Any = nothing
    divider_stroke_color::Any = nothing
end

"""
    WidgetCardStyle(; <the fields of WidgetStyle>, title_text_color, description_text_color,
                    body_text_color, footer_text_color, header_color, body_color, footer_color,
                    chevron_color, tinted_border_color, tinted_padding_color,
                    tinted_content_color, muted_border_color, muted_padding_color,
                    muted_content_color, plain_border_color, plain_padding_color,
                    plain_content_color)

The style of a `WidgetCard`: the fields of `WidgetStyle`, its title, description,
body and footer text, the fill behind each of its three regions, the fold mark,
and the surface of each of its three other variants.
"""
@document struct WidgetCardStyle <: WidgetDocument
    margin_color::Any = nothing
    border_color::Any = nothing
    padding_color::Any = nothing
    content_color::Any = nothing
    label_text_color::Any = nothing
    title_text_color::Any = nothing
    description_text_color::Any = nothing
    body_text_color::Any = nothing
    footer_text_color::Any = nothing
    header_color::Any = nothing
    body_color::Any = nothing
    footer_color::Any = nothing
    chevron_color::Any = nothing
    tinted_border_color::Any = nothing
    tinted_padding_color::Any = nothing
    tinted_content_color::Any = nothing
    muted_border_color::Any = nothing
    muted_padding_color::Any = nothing
    muted_content_color::Any = nothing
    plain_border_color::Any = nothing
    plain_padding_color::Any = nothing
    plain_content_color::Any = nothing
end

"""
    WidgetAlertStyle(; <the fields of WidgetStyle>, title_text_color, description_text_color,
                     destructive_border_color, destructive_title_text_color)

The style of a `WidgetAlert`: the fields of `WidgetStyle`, its title and
description text, and the border and the title of its destructive variant.
"""
@document struct WidgetAlertStyle <: WidgetDocument
    margin_color::Any = nothing
    border_color::Any = nothing
    padding_color::Any = nothing
    content_color::Any = nothing
    label_text_color::Any = nothing
    title_text_color::Any = nothing
    description_text_color::Any = nothing
    destructive_border_color::Any = nothing
    destructive_title_text_color::Any = nothing
end

"""
    WidgetSwitchStyle(; <the fields of WidgetStyle>, track_color, track_checked_color,
                      knob_color, knob_stroke_color)

The style of a `WidgetSwitch`: the fields of `WidgetStyle`, the track and the
knob.
"""
@document struct WidgetSwitchStyle <: WidgetDocument
    margin_color::Any = nothing
    border_color::Any = nothing
    padding_color::Any = nothing
    content_color::Any = nothing
    label_text_color::Any = nothing
    track_color::Any = nothing
    track_checked_color::Any = nothing
    knob_color::Any = nothing
    knob_stroke_color::Any = nothing
end

"""
    WidgetProgressStyle(; <the fields of WidgetStyle>, track_color, indicator_color)

The style of a `WidgetProgressBar`: the fields of `WidgetStyle`, the track and the
filled portion.
"""
@document struct WidgetProgressStyle <: WidgetDocument
    margin_color::Any = nothing
    border_color::Any = nothing
    padding_color::Any = nothing
    content_color::Any = nothing
    label_text_color::Any = nothing
    track_color::Any = nothing
    indicator_color::Any = nothing
end

"""
    WidgetSliderStyle(; <the fields of WidgetStyle>, track_color, indicator_color,
                      knob_color, knob_stroke_color)

The style of a `WidgetSlider`: the fields of `WidgetStyle`, the track, the
filled portion and the knob.
"""
@document struct WidgetSliderStyle <: WidgetDocument
    margin_color::Any = nothing
    border_color::Any = nothing
    padding_color::Any = nothing
    content_color::Any = nothing
    label_text_color::Any = nothing
    track_color::Any = nothing
    indicator_color::Any = nothing
    knob_color::Any = nothing
    knob_stroke_color::Any = nothing
end

"""
    WidgetRadioGroupStyle(; <the fields of WidgetStyle>, indicator_color, indicator_stroke_color,
                          indicator_selected_stroke_color, dot_color)

The style of a `WidgetRadioGroup`: the fields of `WidgetStyle`, the circle of
each option and its selected dot.
"""
@document struct WidgetRadioGroupStyle <: WidgetDocument
    margin_color::Any = nothing
    border_color::Any = nothing
    padding_color::Any = nothing
    content_color::Any = nothing
    label_text_color::Any = nothing
    indicator_color::Any = nothing
    indicator_stroke_color::Any = nothing
    indicator_selected_stroke_color::Any = nothing
    dot_color::Any = nothing
end

"""
    WidgetToggleStyle(; <the fields of WidgetStyle>, border_checked_color, padding_checked_color,
                      content_checked_color, label_checked_text_color)

The style of a `WidgetToggle`: the fields of `WidgetStyle`, and its box and
label when checked.
"""
@document struct WidgetToggleStyle <: WidgetDocument
    margin_color::Any = nothing
    border_color::Any = nothing
    padding_color::Any = nothing
    content_color::Any = nothing
    label_text_color::Any = nothing
    border_checked_color::Any = nothing
    padding_checked_color::Any = nothing
    content_checked_color::Any = nothing
    label_checked_text_color::Any = nothing
end

"""
    WidgetToggleGroupStyle(; <the fields of WidgetStyle>, segment_color, segment_selected_color,
                           label_selected_text_color)

The style of a `WidgetToggleGroup`: the fields of `WidgetStyle`, an unselected
segment, the selected segment, and its label.
"""
@document struct WidgetToggleGroupStyle <: WidgetDocument
    margin_color::Any = nothing
    border_color::Any = nothing
    padding_color::Any = nothing
    content_color::Any = nothing
    label_text_color::Any = nothing
    segment_color::Any = nothing
    segment_selected_color::Any = nothing
    label_selected_text_color::Any = nothing
end

"""
    WidgetHighlightStyle(; content_color, border_stroke_color)

The style of a `WidgetHighlight`: its fill and its outline. A highlight has no
box (it keeps no margin, border or padding), so its style holds only these two
fields, not the other fields of `WidgetStyle`.
"""
@document struct WidgetHighlightStyle <: WidgetDocument
    content_color::Any = nothing
    border_stroke_color::Any = nothing
end

"""
    WidgetSelectStyle(; <the fields of WidgetStyle>, chevron_color)

The style of a `WidgetSelect`: the fields of `WidgetStyle`, and the trailing
chevron.
"""
@document struct WidgetSelectStyle <: WidgetDocument
    margin_color::Any = nothing
    border_color::Any = nothing
    padding_color::Any = nothing
    content_color::Any = nothing
    label_text_color::Any = nothing
    chevron_color::Any = nothing
end

"""
    WidgetSpinBoxStyle(; <the fields of WidgetStyle>, stepper_color, divider_stroke_color)

The style of a `WidgetSpinBox`: the fields of `WidgetStyle`, the + and − marks
(`stepper_color`), and the line beside them (`divider_stroke_color`).
"""
@document struct WidgetSpinBoxStyle <: WidgetDocument
    margin_color::Any = nothing
    border_color::Any = nothing
    padding_color::Any = nothing
    content_color::Any = nothing
    label_text_color::Any = nothing
    stepper_color::Any = nothing
    divider_stroke_color::Any = nothing
end

"""
    WidgetListStyle(; <the fields of WidgetStyle>, row_selected_color)

The style of a `WidgetList`: the fields of `WidgetStyle`, and the band of the
selected row.
"""
@document struct WidgetListStyle <: WidgetDocument
    margin_color::Any = nothing
    border_color::Any = nothing
    padding_color::Any = nothing
    content_color::Any = nothing
    label_text_color::Any = nothing
    row_selected_color::Any = nothing
end

"""
    WidgetAccordionStyle(; <the fields of WidgetStyle>, title_text_color, body_text_color,
                         divider_stroke_color, chevron_color)

The style of a `WidgetAccordion`: the fields of `WidgetStyle`, its title and
body text, the hairline between items, and the fold mark.
"""
@document struct WidgetAccordionStyle <: WidgetDocument
    margin_color::Any = nothing
    border_color::Any = nothing
    padding_color::Any = nothing
    content_color::Any = nothing
    label_text_color::Any = nothing
    title_text_color::Any = nothing
    body_text_color::Any = nothing
    divider_stroke_color::Any = nothing
    chevron_color::Any = nothing
end

"""
    WidgetTableStyle(; <the fields of WidgetStyle>, divider_stroke_color, header_row_color,
                     row_selected_color)

The style of a `WidgetTable`: the fields of `WidgetStyle`, the outer frame and
the grid lines (`divider_stroke_color`), the header strip fill, and the band of
the selected row, column or cell.
"""
@document struct WidgetTableStyle <: WidgetDocument
    margin_color::Any = nothing
    border_color::Any = nothing
    padding_color::Any = nothing
    content_color::Any = nothing
    label_text_color::Any = nothing
    divider_stroke_color::Any = nothing
    header_row_color::Any = nothing
    row_selected_color::Any = nothing
end

"""
    WidgetTreeStyle(; <the fields of WidgetStyle>, icon_text_color, chevron_color,
                    row_selected_color)

The style of a `WidgetTree`: the fields of `WidgetStyle`, the icon glyph, the
expand chevron, and the band of the selected row.
"""
@document struct WidgetTreeStyle <: WidgetDocument
    margin_color::Any = nothing
    border_color::Any = nothing
    padding_color::Any = nothing
    content_color::Any = nothing
    label_text_color::Any = nothing
    icon_text_color::Any = nothing
    chevron_color::Any = nothing
    row_selected_color::Any = nothing
end
