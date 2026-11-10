# Fragment of `AppearanceModule` — the views of the parts of an appearance: the
# scale, the colour settings, a heading of the themes and one theme, each as the
# page of the part and as its body in the appearance tab.

"""
    AppearancePartToWidget

The supertype of the views of the parts of an appearance:
[`AppearanceScaleToWidget`](@ref), [`AppearanceColorsToWidget`](@ref),
[`ThemeGroupToWidget`](@ref) and [`ThemeToWidget`](@ref). Each draws the page of its
part, alone. The appearance tab builds the same widgets with the same functions,
so every control of the tab is in its one widget tree, and Tab moves through them
all; Tab does not enter a document that another view draws.

A view holds `appearance`, the appearance of the editor, whose widget theme and
colours it draws with. It makes its controls as the tab does, and prints its
widgets through the recursion. Its reader answers as the tab answers: a press of a
button the operation of the button, a step of a spin box or a choice of a preset
the write of the part, an edit of a colour text the write of the colour, and a
press on the chevron of a card the write of the open cards of the heading. The
selection and the part under the pointer of the part are paths in its widgets,
which the view introduces.
"""
abstract type AppearancePartToWidget <: Projection end

# The tables of the controls of the print, as the tab holds them (see
# `AppearanceToWidgetIoMap`); `child_iomap` is the IO map of the widgets that the
# recursion printed.
@iomap struct AppearancePartToWidgetIoMap
    projection::Any
    input::Any
    output::Any
    child_iomap::Any
    commands::Any
    writes::Any
    edits::Any
    folds::Any
end

get_child_iomaps(iomap::AppearancePartToWidgetIoMap) = Any[iomap.child_iomap]

"""
    AppearanceScaleToWidget(; appearance)

The [`AppearanceScale`](@ref) of an appearance as widgets: its summary, a row for
the zoom and one for each of the six scales, each with its name, a − button, its
value in percent, a + button and a reset button, and under the rows a button
"Reset all" that resets each of them. A step takes nothing back, as from its keys.
"""
struct AppearanceScaleToWidget <: AppearancePartToWidget
    appearance::Any
end

AppearanceScaleToWidget(; appearance) = AppearanceScaleToWidget(appearance)

print_document(p::AppearanceScaleToWidget, recursion, scale::AppearanceScale, ctx) =
    _print_part_view(p, recursion, scale, ctx, controls -> _make_scale_body(controls, scale))

"""
    AppearanceColorsToWidget(; appearance)

The [`AppearanceColors`](@ref) of an appearance as widgets: its summary, a row for
each of the five colour settings, the mode, the contrast, the palette, the accent
and the neutral, each with its name, buttons ‹ and › that step through its values,
and its value, and under the rows a button "Reset all" that writes the default of
each of them. A setting `:system` shows the value of the system after it.
"""
struct AppearanceColorsToWidget <: AppearancePartToWidget
    appearance::Any
end

AppearanceColorsToWidget(; appearance) = AppearanceColorsToWidget(appearance)

print_document(p::AppearanceColorsToWidget, recursion, colors::AppearanceColors, ctx) =
    _print_part_view(p, recursion, colors, ctx, controls -> _make_colors_body(controls, colors))

"""
    ThemeGroupToWidget(; appearance)

A [`ThemeGroup`](@ref), a heading of the themes of an appearance, as widgets: a
card for each of its themes, in order, as wide as the view. A card folds to its
title and the summary of its theme type, and shows the controls of the theme, as
[`ThemeToWidget`](@ref) draws them, while the `open_names` of the heading name the
type of the theme. A press on the chevron of a card writes `open_names`, as view state.
"""
struct ThemeGroupToWidget <: AppearancePartToWidget
    appearance::Any
end

ThemeGroupToWidget(; appearance) = ThemeGroupToWidget(appearance)

print_document(p::ThemeGroupToWidget, recursion, group::ThemeGroup, ctx) =
    _print_part_view(p, recursion, group, ctx, controls -> _make_group_body(controls, group))

"""
    ThemeToWidget(; appearance)

One theme of an appearance as widgets: the summary of its theme type, the presets
of the theme, as a choice that writes every field of the preset into the theme,
and a row for each field, its name and its control, with the docstring of the
field under it. The controls are those of the appearance tab, and a write of a
field is an edit of the theme that a history records.
"""
struct ThemeToWidget <: AppearancePartToWidget
    appearance::Any
end

ThemeToWidget(; appearance) = ThemeToWidget(appearance)

print_document(p::ThemeToWidget, recursion, theme::Theme, ctx) =
    _print_part_view(p, recursion, theme, ctx, controls -> _make_theme_body(controls, theme))

# The print of the view `p` of `document`: `build(controls)` makes its widgets, and
# the recursion prints them. The widgets hold the paths of `document` that `p`
# introduces, each document below the root the part of its parent's path.
function _print_part_view(p::AppearancePartToWidget, recursion, document, ctx, build)
    (controls, tables) = _make_view_controls(p.appearance)
    root = build(controls)
    set_output_path_computations!(root, document, path -> _get_tab_path(p, path))
    set_output_tree_path_computations!(root)
    child = print_child(recursion, root, ctx)
    AppearancePartToWidgetIoMap(p, document, Cell(@computation child.output), child, tables.commands,
                                tables.writes, tables.edits, tables.folds)
end

function read_intent(p::AppearancePartToWidget, recursion, change::Intent, iomap::AppearancePartToWidgetIoMap)
    child = iomap.child_iomap
    answer = read_intent(child.projection, recursion, change, child)
    operation = answer isa Intent ? answer.operation : answer
    Intent(change.gesture, _translate_tab_operation(iomap, operation))
end

read_intent(p::AppearancePartToWidget, iomap::AppearancePartToWidgetIoMap, payload) =
    read_intent(p, nothing, Intent(payload), iomap).operation

# A path of the part through its view names its path in the widgets, and the
# printer of the widgets maps it on; a widget maps back to that path.
function map_reference_forward(p::AppearancePartToWidget, iomap::AppearancePartToWidgetIoMap, reference)
    reference isa EmptyReference && return EmptyReference(get_reference_node_type(iomap.output))
    inner = _get_tab_path(p, reference)
    child = iomap.child_iomap
    inner === nothing ? nothing : map_reference_forward(child.projection, child, inner)
end

function map_reference_backward(p::AppearancePartToWidget, iomap::AppearancePartToWidgetIoMap, reference)
    child = iomap.child_iomap
    inner = map_reference_backward(child.projection, child, reference)
    inner isa Reference ? _introduce_tab_path(iomap, inner) : nothing
end
