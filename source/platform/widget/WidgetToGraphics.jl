# Fragment of `WidgetModule`.
#
# WidgetDocument → GraphicsCanvas projection. One projection struct per widget
# document type, composed via `TypeDispatchingProjection(...)` through the
# `WidgetToGraphics()` factory function. Wrap the result in `RecursiveProjection`
# at the call site to enable recursive child dispatch.
#
# Each widget projection produces a `GraphicsCanvas` as output. Leaf widgets
# emit text and rect elements; container widgets recurse via the `recursion`
# argument and nest child canvases. Event routing (e.g. MouseScroll) is
# delegated through containers to the appropriate child via hit-testing.
#
# `WidgetScrollPaneToGraphicsCanvas` is the one scroll pane projection: a sized
# `GraphicsCanvas` wrapping the `GraphicsViewport` that clips, with the content
# delegated through the recursion argument. Compose it with `NestingProjection`
# to give that content a different recursion table than the surrounding tree.
# ── Styling helpers ─────────────────────────────────────────────────────────

# Fallback viewport / track extents used only when a widget carries no `size`
# *and* its parent gave no exact extent (isolated rendering). Named
# here so the value is stated once — the scroll bar's track size is read by
# both its printer and its hit-test reader, so a single source avoids a drift
# risk between the two.
# No size constant lives here. An extent comes from the widget's own size, from
# what its parent offered, or from its content — and a widget with none of those
# on an axis has no extent there. A number invented in a printer is a size nobody
# chose, in a place nobody looks. See documentation/rule/layout-rules.md.

# All widget geometry is in logical pixels; the device pixel ratio of the
# `Display` applies at the SDL render boundary. `_sc` and `_origin` are identity
# markers for a logical pixel number that a document authors on a widget. A
# theme value reaches the printer through a style field of the projection and
# needs no marker.
_sc(px::Integer) = Int(px)

# A widget's authored `position` is in logical pixels, like insets.
_origin(pos::Point2D) = (Int(pos.x[]), Int(pos.y[]))

# Push a themed rounded box (fill + optional outline) of size cw×ch at (x,y). A
# transparent fill with no visible outline draws nothing, so it adds no element.
function _push_panel!(elems::Vector, x::Int, y::Int, cw::Int, ch::Int;
                      fill::StyleColor, border=nothing, border_w::Int=0, radius::Int=0)
    has_outline = border !== nothing && border_w > 0 && !is_color_transparent(border)
    (has_outline || !is_color_transparent(fill)) || return
    if has_outline
        push!(elems, GraphicsRect(x, y, cw, ch; color = fill, radius,
                                  border_width=border_w, border_color=border))
    else
        push!(elems, GraphicsRect(x, y, cw, ch; color = fill, radius))
    end
end

# ── Parts and their overrides ───────────────────────────────────────────────
# A widget document can hold a style in its `style` field: a `WidgetStyle`, or
# the style of its widget type. A field of that style that is not `nothing`
# replaces the style field of the projection with the same name.

function _get_part_color(w, name::Symbol, default)
    style = hasproperty(w, :style) ? w.style : nothing
    (style === nothing || !hasproperty(style, name)) && return default
    color = getproperty(style, name)
    color === nothing ? default : color
end

# The override of a text or a stroke holds only its color, under the name of the
# style field with `_color` added. The font and the width stay the projection's.
function _get_part_text(w, name::Symbol, default::StyleText)
    color = _get_part_color(w, Symbol(name, :_color), nothing)
    color === nothing ? default : StyleText(default.font, color)
end

function _get_part_stroke(w, name::Symbol, default::StyleStroke)
    color = _get_part_color(w, Symbol(name, :_color), nothing)
    color === nothing ? default : StyleStroke(color, default.width; dash = default.dash)
end

# The style field of `part` of the kind `kind` (`:color`, `:text` or `:stroke`) in
# a variant and a state. The names follow `[<variant>_]<part>[_<state>]_<kind>`,
# and a projection that has no field for the variant or the state has one field
# for all of them, so the search drops the state, then the variant. Answers the
# name and whether it names the disabled state.
function _find_style_field(p, part::Symbol, kind::Symbol, variant, state)
    variant_word = variant === nothing ? "" : string(variant, "_")
    state_word = state === nothing ? "" : string("_", state)
    for (name, stated) in ((Symbol(variant_word, part, state_word, "_", kind), true),
                           (Symbol(variant_word, part, "_", kind), false),
                           (Symbol(part, state_word, "_", kind), true),
                           (Symbol(part, "_", kind), false))
        hasproperty(p, name) && return (name, stated && state === :disabled)
    end
    nothing
end

# The color of `part`: the style field that the variant and the state select, or
# the override of the same name. A disabled field ignores the override, so a
# disabled widget looks disabled whatever its style says. A part with no style
# field draws nothing.
function _get_state_color(p, w, part::Symbol; variant = nothing, state = nothing)
    found = _find_style_field(p, part, :color, variant, state)
    found === nothing && return color_transparent
    name, disabled = found
    disabled ? getproperty(p, name) : _get_part_color(w, name, getproperty(p, name))
end

function _get_state_text(p, w, part::Symbol; variant = nothing, state = nothing)
    name, disabled = _find_style_field(p, part, :text, variant, state)
    disabled ? getproperty(p, name) : _get_part_text(w, name, getproperty(p, name))
end

function _get_state_stroke(p, w, part::Symbol; variant = nothing, state = nothing)
    name, disabled = _find_style_field(p, part, :stroke, variant, state)
    disabled ? getproperty(p, name) : _get_part_stroke(w, name, getproperty(p, name))
end

# The colors of the four box parts of `w` in a variant and a state, for
# `_push_box_parts!`.
_get_box_colors(p, w; variant = nothing, state = nothing) =
    (margin  = _get_state_color(p, w, :margin; variant, state),
     border  = _get_state_color(p, w, :border; variant, state),
     padding = _get_state_color(p, w, :padding; variant, state),
     content = _get_state_color(p, w, :content; variant, state))

# ── The box ─────────────────────────────────────────────────────────────────
# A widget with the box insets has four parts, from the outside in: the margin,
# the border, the padding and the content. An inset of the document that is
# `nothing` takes the inset of the projection with the same name, or in a
# variant the field `<variant>_<name>` when the projection has one.

function _get_inset(w, p, name::Symbol; variant = nothing)
    inset = getproperty(w, name)
    inset === nothing || return inset::Inset
    varied = variant === nothing ? name : Symbol(variant, "_", name)
    (hasproperty(p, varied) ? getproperty(p, varied) : getproperty(p, name))::Inset
end

_get_inset_sides(inset::Inset) =
    (_sc(Int(inset.left[])), _sc(Int(inset.top[])), _sc(Int(inset.right[])), _sc(Int(inset.bottom[])))

# The resolved insets of `w`, each as `(left, top, right, bottom)`.
_get_box_insets(p, w; variant = nothing) =
    (margin  = _get_inset_sides(_get_inset(w, p, :margin; variant)),
     border  = _get_inset_sides(_get_inset(w, p, :border; variant)),
     padding = _get_inset_sides(_get_inset(w, p, :padding; variant)))

function _content_offset(p, w::WidgetDocument; variant = nothing)
    box = _get_box_insets(p, w; variant)
    (box.margin[1] + box.border[1] + box.padding[1], box.margin[2] + box.border[2] + box.padding[2])
end

function _inset_total(p, w::WidgetDocument; variant = nothing)
    box = _get_box_insets(p, w; variant)
    (sum(sides -> sides[1] + sides[3], box), sum(sides -> sides[2] + sides[4], box))
end

# Push the band of `sides` inside the rectangle `(x, y, width, height)`: one rect
# for each side with a width. A transparent band adds no element.
function _push_band!(elements::Vector, x::Int, y::Int, width::Int, height::Int, sides, color::StyleColor)
    is_color_transparent(color) && return
    left, top, right, bottom = sides
    top > 0 && push!(elements, GraphicsRect(x, y, width, top; color))
    bottom > 0 && push!(elements, GraphicsRect(x, y + height - bottom, width, bottom; color))
    left > 0 && push!(elements, GraphicsRect(x, y + top, left, height - top - bottom; color))
    right > 0 && push!(elements, GraphicsRect(x + width - right, y + top, right, height - top - bottom; color))
end

# Push the four box parts of a widget whose content is `content_width` by
# `content_height`, at the widget's own origin. `box` holds the insets that
# `_get_box_insets` resolves, and `colors` a color for each part: `margin`,
# `border`, `padding` and `content`. A transparent part adds no element. With a
# uniform border and one color for the padding and the content, the border, the
# padding and the content are one rounded rect; else each part is a band, so a
# translucent part does not show the color of the part around it.
# True when `_push_box_parts!` can draw something for a box of these insets and
# colours: a colour that is not transparent, and a border only where it has a width.
_is_box_visible(box, colors) =
    !is_color_transparent(colors.margin) || !is_color_transparent(colors.padding) ||
    !is_color_transparent(colors.content) ||
    (any(>(0), box.border) && !is_color_transparent(colors.border))

function _push_box_parts!(elements::Vector, box, colors, content_width::Int, content_height::Int;
                          radius::Int = 0)
    margin_left, margin_top, margin_right, margin_bottom = box.margin
    border_left, border_top, border_right, border_bottom = box.border
    padding_left, padding_top, padding_right, padding_bottom = box.padding
    border_box_width = border_left + padding_left + content_width + padding_right + border_right
    border_box_height = border_top + padding_top + content_height + padding_bottom + border_bottom
    _push_band!(elements, 0, 0, margin_left + border_box_width + margin_right,
                margin_top + border_box_height + margin_bottom, box.margin, colors.margin)
    uniform = border_left == border_top == border_right == border_bottom
    if uniform && is_color_equal(colors.padding, colors.content)
        _push_panel!(elements, margin_left, margin_top, border_box_width, border_box_height;
                     fill = colors.padding, border = colors.border, border_w = border_left, radius = radius)
        return
    end
    if uniform
        _push_panel!(elements, margin_left, margin_top, border_box_width, border_box_height;
                     fill = color_transparent, border = colors.border, border_w = border_left, radius = radius)
    else
        _push_band!(elements, margin_left, margin_top, border_box_width, border_box_height,
                    box.border, colors.border)
    end
    _push_band!(elements, margin_left + border_left, margin_top + border_top,
                padding_left + content_width + padding_right, padding_top + content_height + padding_bottom,
                box.padding, colors.padding)
    # The content keeps the corner radius, less the border and the padding
    # that lie between it and the rounded outline.
    _push_panel!(elements, margin_left + border_left + padding_left, margin_top + border_top + padding_top,
                 content_width, content_height; fill = colors.content,
                 radius = max(0, radius - border_left - padding_left))
end

# Push the band of `sides` inside a rectangle whose origin and size are thunks:
# each rect computes its geometry from them, so it follows the cells that the
# thunks read without a print of the widget. A transparent band adds no element.
function _push_following_band!(elements::Vector, x_of, y_of, width_of, height_of, sides, color::StyleColor)
    is_color_transparent(color) && return
    left, top, right, bottom = sides
    function push_rect!(x, y, width, height)
        push!(elements, GraphicsRect(Cell(@computation Int32(x())), Cell(@computation Int32(y())),
                                     Cell(@computation Int32(max(0, width()))),
                                     Cell(@computation Int32(max(0, height()))),
                                     Cell(color), Cell(Int32(0)), Cell(Int32(0)), Cell(Int32(0)), Cell(Int32(0)),
                                     Cell(Int32(0)), Cell(color_transparent), Cell(nothing)))
    end
    top > 0 && push_rect!(x_of, y_of, width_of, () -> top)
    bottom > 0 && push_rect!(x_of, () -> y_of() + height_of() - bottom, width_of, () -> bottom)
    left > 0 && push_rect!(x_of, () -> y_of() + top, () -> left, () -> height_of() - top - bottom)
    right > 0 && push_rect!(() -> x_of() + width_of() - right, () -> y_of() + top, () -> right,
                            () -> height_of() - top - bottom)
end

# Push the margin, the border and the padding of a widget whose content extent
# is a pair of cells, such as the viewport of a pane. The bands follow the cells,
# so a content that grows moves them without a print of the pane. The pane
# paints its content part itself.
function _push_following_box_bands!(elements::Vector, box, colors, content_width::Cell, content_height::Cell)
    margin_left, margin_top, margin_right, margin_bottom = box.margin
    border_left, border_top, border_right, border_bottom = box.border
    padding_left, padding_top, padding_right, padding_bottom = box.padding
    padding_width() = padding_left + Int(content_width[]) + padding_right
    padding_height() = padding_top + Int(content_height[]) + padding_bottom
    border_width() = border_left + padding_width() + border_right
    border_height() = border_top + padding_height() + border_bottom
    _push_following_band!(elements, () -> 0, () -> 0,
                          () -> margin_left + border_width() + margin_right,
                          () -> margin_top + border_height() + margin_bottom, box.margin, colors.margin)
    _push_following_band!(elements, () -> margin_left, () -> margin_top, border_width, border_height,
                          box.border, colors.border)
    _push_following_band!(elements, () -> margin_left + border_left, () -> margin_top + border_top,
                          padding_width, padding_height, box.padding, colors.padding)
end

# Push the translucent layer that a hovered or a pressed widget draws over its
# surface, so the state shows over any surface color. `nothing` draws no layer.
function _push_state_layer!(elements::Vector, color, x::Int, y::Int, width::Int, height::Int;
                            radius::Int = 0)
    color === nothing && return
    _push_panel!(elements, x, y, width, height; fill = color, radius = radius)
end

# Push the layer of the light under the pointer, and of the pressed state when
# `pressed_color` is given, over the surface of `w`. The layer is always there:
# its size and its color are cells of its own that read the mouse target and the
# `pressed` cell of `w`, as the focus ring reads the selection. A move onto `w` or
# off it then changes the layer and not the element list or the extent of the
# widget, so only the layer is painted again. While the pointer is off `w` and `w` is not
# pressed, the layer has no size and draws nothing. A `stroke` draws the outline
# of the layer, so a widget that is flat at rest shows the shape of a button
# while the layer shows.
function _push_hover_layer!(elements::Vector, w::WidgetDocument, x::Int, y::Int,
                            width::Int, height::Int; hovered_color::StyleColor,
                            pressed_color = nothing, stroke = nothing, radius::Int = 0)
    is_pressed() = pressed_color !== nothing && w.pressed === true
    is_shown() = is_pressed() || _is_under_pointer(w)
    layer = stroke === nothing ?
        GraphicsRect(x, y, 0, 0; color = hovered_color, radius = radius) :
        GraphicsRect(x, y, 0, 0; color = hovered_color, radius = radius,
                     border_width = stroke.width, border_color = stroke.color)
    set_cell_computation!(getfield(layer, :w), () -> is_shown() ? Int32(width) : Int32(0))
    set_cell_computation!(getfield(layer, :h), () -> is_shown() ? Int32(height) : Int32(0))
    pressed_color === nothing ||
        set_cell_computation!(getfield(layer, :color), () -> is_pressed() ? pressed_color : hovered_color)
    push!(elements, layer)
end

# A focus ring around a focused widget (Stage 2). Focus is selection. The ring is
# a **persistent overlay** (always pushed) whose `w`/`h` read the selection — full
# control bounds when focused, 0 when not (a zero-size rect the renderer skips).
# Pushing it unconditionally keeps the selection read OUT of the elements-vector
# thunk, so a pure focus/caret move invalidates only the ring's own geometry cells
# (selection-overlay geometry), not the whole content `CellVector` — the widget
# analogue of the TextToGraphics cursor overlay, preserving selection isolation
# (dimension A; see plan/pending/printer-locality.md). Transparent fill so only the
# ring-coloured border shows.
#
# `whole`, when given, holds the values of the graphics theme, whose ring color
# the ring takes while the widget is selected as a whole. A text box with the focus holds a caret, so a whole selection of one is
# a selection of the box as an object, and it shows as one. The ring keeps the
# width of `ring`; only its color follows the kind of the selection.
function _push_focus_ring!(elems::Vector, w::WidgetDocument, cw::Int, ch::Int,
                           ring::StyleStroke, radius::Int; whole = nothing)
    rect = GraphicsRect(0, 0, 0, 0; color = color_transparent, radius,
                        border_width=max(1, Int(ring.width)), border_color=ring.color)
    set_cell_computation!(getfield(rect, :w),
                          () -> getfield(w, :selection)[] === nothing ? Int32(0) : Int32(cw))
    set_cell_computation!(getfield(rect, :h),
                          () -> getfield(w, :selection)[] === nothing ? Int32(0) : Int32(ch))
    whole === nothing ||
        set_cell_computation!(getfield(rect, :border_color), () ->
            get_stored_selection(w) isa EmptyReference ? whole.selection_ring : ring.color)
    push!(elems, rect)
end

# ── The light under the pointer ─────────────────────────────────────────────
# An actionable widget draws the layer of the light over its surface while the
# pointer is on it or on a part inside it, and while it is enabled. Its mouse
# target says where the pointer is; no reader writes a state for the light. A
# disabled widget never lights.

# Whether the pointer is on `w` or on a part inside it.
_is_under_pointer(w) = get_mouse_target(w) !== nothing

# ── Projection structs ─────────────────────────────────────────────────────
#
# A widget projection holds one style field for each part and state that it
# draws, named `[<variant>_]<part>[_<state>]_<kind>`, and a constructor that
# fills every field from a scaled `WidgetTheme`. A keyword of that constructor
# replaces one field with a fixed value. A widget with the box insets has the
# default insets `margin`, `border` and `padding`, which an inset of the document
# replaces, and a color for each of its four box parts.
#
# Each projection is `@projection UntrackedCell struct`: a field that the
# constructor fills from the theme, scaled or not, reads it at each read, with no
# edge (`_themed`), and the appearance wrapper makes the view print again after a
# change of the theme. A field can not be written after the projection is built.

@projection UntrackedCell struct WidgetLabelToGraphicsCanvas
    measure::TextMeasure
    margin::Inset
    border::Inset
    padding::Inset
    margin_color::StyleColor
    border_color::StyleColor
    padding_color::StyleColor
    content_color::StyleColor
    label_text::StyleText
    placeholder_color::StyleColor          # an image that is not decoded yet
end

WidgetLabelToGraphicsCanvas(theme; measure,
                            margin = inset_default, border = inset_default, padding = inset_default,
                            margin_color = color_transparent, border_color = color_transparent,
                            padding_color = color_transparent, content_color = color_transparent,
                            label_text = _themed(StyleText, theme, _get_body_text),
                            placeholder_color = _themed(StyleColor, theme, t -> t.muted)) =
    WidgetLabelToGraphicsCanvas(measure, margin, border, padding, margin_color, border_color,
                                padding_color, content_color, label_text, placeholder_color)

@projection UntrackedCell struct WidgetTextToGraphicsCanvas
    measure::TextMeasure
    margin::Inset
    border::Inset
    padding::Inset
    margin_color::StyleColor
    border_color::StyleColor
    padding_color::StyleColor
    content_color::StyleColor
    padding_disabled_color::StyleColor
    content_disabled_color::StyleColor
    label_text::StyleText                         # the text of the non-editable form
    label_disabled_text::StyleText
    placeholder_text::StyleText                   # the example that an empty field shows
    focus_ring_stroke::StyleStroke                # the widget holds the focus
    graphics_style::NamedTuple                    # the ring of the widget selected as a whole
    corner_radius::Int
    appearance::Any                               # whose theme of a language colors a field of code
end

WidgetTextToGraphicsCanvas(theme; graphics_theme = nothing, measure,
                           margin = inset_default,
                           border = _themed(Inset, theme, t -> _make_uniform_inset(t.border_width)),
                           padding = _themed(Inset, theme, t -> t.control_padding),
                           margin_color = color_transparent,
                           border_color = _themed(StyleColor, theme, t -> t.input),
                           padding_color = _themed(StyleColor, theme, t -> t.background),
                           content_color = _themed(StyleColor, theme, t -> t.background),
                           padding_disabled_color = _themed(StyleColor, theme, t -> t.muted),
                           content_disabled_color = _themed(StyleColor, theme, t -> t.muted),
                           label_text = _themed(StyleText, theme, _get_body_text),
                           label_disabled_text =
                               _themed(StyleText, theme, t -> StyleText(t.font, t.muted_foreground)),
                           placeholder_text =
                               _themed(StyleText, theme, t -> StyleText(t.font, t.muted_foreground)),
                           focus_ring_stroke =
                               _themed(StyleStroke, theme, t -> StyleStroke(t.ring, t.ring_width)),
                           graphics_style = _make_graphics_style(graphics_theme),
                           corner_radius = _themed(Int, theme, t -> t.radius),
                           appearance = theme isa ScaledTheme ? get_theme_appearance(theme) : nothing) =
    WidgetTextToGraphicsCanvas(measure, margin, border, padding, margin_color, border_color,
                               padding_color, content_color, padding_disabled_color,
                               content_disabled_color, label_text, label_disabled_text,
                               placeholder_text, focus_ring_stroke, graphics_style, corner_radius,
                               appearance)

@projection UntrackedCell struct WidgetCheckboxToGraphicsCanvas
    measure::TextMeasure
    margin::Inset
    border::Inset
    padding::Inset
    margin_color::StyleColor
    border_color::StyleColor
    padding_color::StyleColor
    content_color::StyleColor
    indicator_color::StyleColor              # the empty box
    indicator_checked_color::StyleColor      # the box when checked
    indicator_disabled_color::StyleColor
    indicator_stroke::StyleStroke            # the outline of the empty box
    indicator_disabled_stroke::StyleStroke
    check_color::StyleColor                  # the tick
    check_disabled_color::StyleColor
    focus_ring_stroke::StyleStroke
    indicator_size::Int
    corner_radius::Int
    label_text::StyleText                    # the label after the box
    label_disabled_text::StyleText
    label_gap::Int                           # between the box and its label
end

WidgetCheckboxToGraphicsCanvas(theme; measure,
                               margin = inset_default, border = inset_default, padding = inset_default,
                               margin_color = color_transparent, border_color = color_transparent,
                               padding_color = color_transparent, content_color = color_transparent,
                               indicator_color = _themed(StyleColor, theme, t -> t.background),
                               indicator_checked_color = _themed(StyleColor, theme, t -> t.primary),
                               indicator_disabled_color = _themed(StyleColor, theme, t -> t.muted),
                               indicator_stroke =
                                   _themed(StyleStroke, theme, t -> StyleStroke(t.input, t.stroke)),
                               indicator_disabled_stroke =
                                   _themed(StyleStroke, theme, t -> StyleStroke(t.muted_foreground, t.stroke)),
                               check_color = _themed(StyleColor, theme, t -> t.primary_foreground),
                               check_disabled_color = _themed(StyleColor, theme, t -> t.muted_foreground),
                               focus_ring_stroke =
                                   _themed(StyleStroke, theme, t -> StyleStroke(t.ring, t.ring_width)),
                               indicator_size = _themed(Int, theme, t -> t.indicator_size),
                               corner_radius = _themed(Int, theme, t -> t.radius_small),
                               label_text = _themed(StyleText, theme, _get_body_text),
                               label_disabled_text =
                                   _themed(StyleText, theme, t -> StyleText(t.font, t.muted_foreground)),
                               label_gap = _themed(Int, theme, t -> t.label_gap)) =
    WidgetCheckboxToGraphicsCanvas(measure, margin, border, padding, margin_color, border_color,
                                   padding_color, content_color, indicator_color,
                                   indicator_checked_color, indicator_disabled_color, indicator_stroke,
                                   indicator_disabled_stroke, check_color, check_disabled_color,
                                   focus_ring_stroke, indicator_size, corner_radius, label_text,
                                   label_disabled_text, label_gap)

@projection UntrackedCell struct WidgetButtonToGraphicsCanvas
    measure::TextMeasure
    margin::Inset
    border::Inset
    padding::Inset
    margin_color::StyleColor
    border_color::StyleColor
    padding_color::StyleColor
    content_color::StyleColor
    padding_disabled_color::StyleColor
    content_disabled_color::StyleColor
    label_text::StyleText
    label_disabled_text::StyleText
    layer_hovered_color::StyleColor        # over the surface while the pointer is inside
    layer_pressed_color::StyleColor        # over the surface while it is held down
    shadow_color::StyleColor
    shadow_offset::Int
    placeholder_color::StyleColor          # an image that is not decoded yet
    focus_ring_stroke::StyleStroke
    corner_radius::Int
    label_gap::Int                         # between the icon and the label
    icon_size::Float64                    # times the box of the icon, one line of the label
end

WidgetButtonToGraphicsCanvas(theme; measure,
                             margin = inset_default,
                             border = _themed(Inset, theme, t -> _make_uniform_inset(t.border_width)),
                             padding = _themed(Inset, theme, t -> t.control_padding),
                             margin_color = color_transparent,
                             border_color = _themed(StyleColor, theme, t -> t.border),
                             padding_color = _themed(StyleColor, theme, t -> t.background),
                             content_color = _themed(StyleColor, theme, t -> t.background),
                             padding_disabled_color = _themed(StyleColor, theme, t -> t.muted),
                             content_disabled_color = _themed(StyleColor, theme, t -> t.muted),
                             label_text = _themed(StyleText, theme, _get_label_text),
                             label_disabled_text =
                                 _themed(StyleText, theme, t -> StyleText(t.font, t.muted_foreground)),
                             layer_hovered_color = _themed(StyleColor, theme, _get_hover_layer),
                             layer_pressed_color = _themed(StyleColor, theme, _get_pressed_layer),
                             shadow_color = _themed(StyleColor, theme, t -> t.shadow),
                             shadow_offset = _themed(Int, theme, t -> t.shadow_offset),
                             placeholder_color = _themed(StyleColor, theme, t -> t.muted),
                             focus_ring_stroke =
                                 _themed(StyleStroke, theme, t -> StyleStroke(t.ring, t.ring_width)),
                             corner_radius = _themed(Int, theme, t -> t.radius),
                             label_gap = _themed(Int, theme, t -> t.label_gap),
                             icon_size = _themed(Float64, theme, t -> t.icon_size)) =
    WidgetButtonToGraphicsCanvas(measure, margin, border, padding, margin_color, border_color,
                                 padding_color, content_color, padding_disabled_color,
                                 content_disabled_color, label_text, label_disabled_text,
                                 layer_hovered_color, layer_pressed_color, shadow_color, shadow_offset,
                                 placeholder_color, focus_ring_stroke, corner_radius, label_gap,
                                 icon_size)

@projection UntrackedCell struct WidgetTooltipToGraphicsCanvas
    measure::TextMeasure
    margin::Inset
    border::Inset
    padding::Inset
    margin_color::StyleColor
    border_color::StyleColor
    padding_color::StyleColor
    content_color::StyleColor
    label_text::StyleText
    corner_radius::Int
end

WidgetTooltipToGraphicsCanvas(theme; measure,
                              margin = inset_default,
                              border = _themed(Inset, theme, t -> _make_uniform_inset(t.border_width)),
                              padding = _themed(Inset, theme, t -> t.control_padding),
                              margin_color = color_transparent,
                              border_color = _themed(StyleColor, theme, t -> t.border),
                              padding_color = _themed(StyleColor, theme, t -> t.popover),
                              content_color = _themed(StyleColor, theme, t -> t.popover),
                              label_text = _themed(StyleText, theme, t -> StyleText(t.font, t.popover_foreground)),
                              corner_radius = _themed(Int, theme, t -> t.radius)) =
    WidgetTooltipToGraphicsCanvas(measure, margin, border, padding, margin_color, border_color,
                                  padding_color, content_color, label_text, corner_radius)

# A menu bar is the variant `horizontal`, with no fields of its own: it draws on
# the surface of the bar that holds it. A dropdown is the variant `vertical`, and
# it draws the popover surface of the theme, because it is a window of its own.
@projection UntrackedCell struct WidgetMenuToGraphicsCanvas
    measure::TextMeasure
    margin::Inset
    border::Inset
    padding::Inset
    vertical_border::Inset
    vertical_padding::Inset
    margin_color::StyleColor
    border_color::StyleColor
    padding_color::StyleColor
    content_color::StyleColor
    vertical_border_color::StyleColor
    vertical_padding_color::StyleColor
    vertical_content_color::StyleColor
    font::StyleFont             # used to measure the per-item row height
    bar_gap::Int                # between the items of a horizontal menu bar
end

WidgetMenuToGraphicsCanvas(theme; measure,
                           margin = inset_default, border = inset_default,
                           padding = _themed(Inset, theme, t -> t.menu_bar_padding),
                           vertical_border = _themed(Inset, theme, t -> _make_uniform_inset(t.border_width)),
                           vertical_padding = _themed(Inset, theme, t -> _make_uniform_inset(t.item_gap)),
                           margin_color = color_transparent, border_color = color_transparent,
                           padding_color = color_transparent, content_color = color_transparent,
                           vertical_border_color = _themed(StyleColor, theme, t -> t.border),
                           vertical_padding_color = _themed(StyleColor, theme, t -> t.popover),
                           vertical_content_color = _themed(StyleColor, theme, t -> t.popover),
                           font = _themed(StyleFont, theme, t -> t.font),
                           bar_gap = _themed(Int, theme, t -> t.bar_gap)) =
    WidgetMenuToGraphicsCanvas(measure, margin, border, padding, vertical_border, vertical_padding,
                               margin_color, border_color, padding_color, content_color,
                               vertical_border_color, vertical_padding_color,
                               vertical_content_color, font, bar_gap)

# An item that opens a menu is the name of the menu on a bar, the variant
# `submenu`; any other item is a command of a menu. Each takes its own padding.
@projection UntrackedCell struct WidgetMenuItemToGraphicsCanvas
    measure::TextMeasure
    margin::Inset
    border::Inset
    padding::Inset
    submenu_padding::Inset
    margin_color::StyleColor
    border_color::StyleColor
    padding_color::StyleColor
    content_color::StyleColor
    label_text::StyleText            # font + foreground
    label_disabled_text::StyleText   # label when disabled (item or bound command)
    layer_hovered_color::StyleColor                 # hover surface behind the item (Stage 6)
    label_gap::Int                   # between a leading icon and the label
    popup_gap::Int                   # below the item, where its submenu opens
    icon_size::Float64              # times the box of a leading icon, one line of the label
end

WidgetMenuItemToGraphicsCanvas(theme; measure,
                               margin = inset_default, border = inset_default,
                               padding = _themed(Inset, theme, t -> t.menu_item_padding),
                               submenu_padding = _themed(Inset, theme, t -> t.menu_name_padding),
                               margin_color = color_transparent, border_color = color_transparent,
                               padding_color = color_transparent, content_color = color_transparent,
                               label_text = _themed(StyleText, theme, _get_body_text),
                               label_disabled_text =
                                   _themed(StyleText, theme, t -> StyleText(t.font, t.muted_foreground)),
                               layer_hovered_color = _themed(StyleColor, theme, _get_hover_layer),
                               label_gap = _themed(Int, theme, t -> t.label_gap),
                               popup_gap = _themed(Int, theme, t -> t.item_gap),
                               icon_size = _themed(Float64, theme, t -> t.icon_size)) =
    WidgetMenuItemToGraphicsCanvas(measure, margin, border, padding, submenu_padding, margin_color,
                                   border_color, padding_color, content_color, label_text,
                                   label_disabled_text,
                                   layer_hovered_color, label_gap, popup_gap, icon_size)

@projection UntrackedCell struct WidgetToolbarItemToGraphicsCanvas
    measure::TextMeasure
    margin::Inset
    border::Inset
    padding::Inset
    margin_color::StyleColor
    border_color::StyleColor
    padding_color::StyleColor
    content_color::StyleColor
    label_text::StyleText            # font (the size of the icon) + foreground
    label_disabled_text::StyleText   # icon and label when disabled
    layer_hovered_color::StyleColor                 # the layer while the pointer is on the item
    layer_pressed_color::StyleColor  # the layer while the left button is held on the item
    layer_stroke::StyleStroke        # the outline of the layer: the item shows as a button
    corner_radius::Int
    icon_size::Float64               # times the box of the icon, one line of the label
end

WidgetToolbarItemToGraphicsCanvas(theme; measure,
                                  margin = inset_default, border = inset_default,
                                  padding = _themed(Inset, theme, t -> t.toolbar_item_padding),
                                  margin_color = color_transparent, border_color = color_transparent,
                                  padding_color = color_transparent, content_color = color_transparent,
                                  label_text = _themed(StyleText, theme, _get_body_text),
                                  label_disabled_text =
                                      _themed(StyleText, theme, t -> StyleText(t.font, t.muted_foreground)),
                                  layer_hovered_color = _themed(StyleColor, theme, _get_hover_layer),
                                  layer_pressed_color = _themed(StyleColor, theme, _get_pressed_layer),
                                  layer_stroke =
                                      _themed(StyleStroke, theme, t -> StyleStroke(t.border, t.border_width)),
                                  corner_radius = _themed(Int, theme, t -> t.radius),
                                  icon_size = _themed(Float64, theme, t -> t.icon_size)) =
    WidgetToolbarItemToGraphicsCanvas(measure, margin, border, padding, margin_color, border_color,
                                      padding_color, content_color, label_text, label_disabled_text,
                                      layer_hovered_color, layer_pressed_color, layer_stroke,
                                      corner_radius, icon_size)

@projection UntrackedCell struct WidgetCompositeToGraphicsCanvas
    margin::Inset
    border::Inset
    padding::Inset
    margin_color::StyleColor
    border_color::StyleColor
    padding_color::StyleColor
    content_color::StyleColor
    graphics_style::NamedTuple           # the ring around a child selected as a whole
end

WidgetCompositeToGraphicsCanvas(theme; graphics_theme = nothing,
                                margin = inset_default, border = inset_default, padding = inset_default,
                                margin_color = color_transparent, border_color = color_transparent,
                                padding_color = color_transparent, content_color = color_transparent,
                                graphics_style = _make_graphics_style(graphics_theme)) =
    WidgetCompositeToGraphicsCanvas(margin, border, padding, margin_color, border_color, padding_color,
                                    content_color, graphics_style)

@projection UntrackedCell struct WidgetShellToGraphicsCanvas
    measure::TextMeasure
    margin::Inset
    border::Inset
    padding::Inset
    margin_color::StyleColor
    border_color::StyleColor
    padding_color::StyleColor
    content_color::StyleColor
    font::StyleFont             # measures the menu/toolbar band heights
    band_gap::Int               # gap below the toolbar band
end

WidgetShellToGraphicsCanvas(theme; measure,
                            margin = inset_default, border = inset_default, padding = inset_default,
                            margin_color = color_transparent,
                            border_color = color_transparent,
                            padding_color = _themed(StyleColor, theme, t -> t.background),
                            content_color = _themed(StyleColor, theme, t -> t.background),
                            font = _themed(StyleFont, theme, t -> t.font),
                            band_gap = _themed(Int, theme, t -> t.item_gap)) =
    WidgetShellToGraphicsCanvas(measure, margin, border, padding, margin_color, border_color,
                                padding_color, content_color, font, band_gap)

@projection UntrackedCell struct WidgetTitlePaneToGraphicsCanvas
    measure::TextMeasure
    margin::Inset
    border::Inset
    padding::Inset
    margin_color::StyleColor
    border_color::StyleColor
    padding_color::StyleColor
    content_color::StyleColor
    title_bar_color::StyleColor                 # fill of the title row
    title_text::StyleText        # bold title
    body_text::StyleText         # string-content body
    title_gap::Int
end

WidgetTitlePaneToGraphicsCanvas(theme; measure,
                                margin = inset_default, border = inset_default, padding = inset_default,
                                margin_color = color_transparent, border_color = color_transparent,
                                padding_color = color_transparent, content_color = color_transparent,
                                title_bar_color = color_transparent,
                                title_text = _themed(StyleText, theme, _get_title_text),
                                body_text = _themed(StyleText, theme, t -> StyleText(t.font, t.card_foreground)),
                                title_gap = _themed(Int, theme, t -> t.title_gap)) =
    WidgetTitlePaneToGraphicsCanvas(measure, margin, border, padding, margin_color, border_color,
                                    padding_color, content_color, title_bar_color, title_text, body_text,
                                    title_gap)

@projection UntrackedCell struct WidgetSplitPaneToGraphicsCanvas
    margin::Inset
    border::Inset
    padding::Inset
    margin_color::StyleColor
    border_color::StyleColor
    padding_color::StyleColor
    content_color::StyleColor
    splitter_stroke::StyleStroke    # divider color + thickness
end

WidgetSplitPaneToGraphicsCanvas(theme;
                                margin = inset_default, border = inset_default, padding = inset_default,
                                margin_color = color_transparent, border_color = color_transparent,
                                padding_color = color_transparent, content_color = color_transparent,
                                splitter_stroke =
                                    _themed(StyleStroke, theme, t -> StyleStroke(t.border, t.border_width))) =
    WidgetSplitPaneToGraphicsCanvas(margin, border, padding, margin_color, border_color, padding_color,
                                    content_color, splitter_stroke)

@projection UntrackedCell struct WidgetTabbedPaneToGraphicsCanvas
    measure::TextMeasure
    margin::Inset
    border::Inset
    padding::Inset
    margin_color::StyleColor
    border_color::StyleColor
    padding_color::StyleColor
    content_color::StyleColor
    font::StyleFont
    tab_strip_color::StyleColor           # the tab strip's own fill
    tab_color::StyleColor                 # an unselected tab
    tab_selected_color::StyleColor        # the selected tab's raised fill
    tab_text::StyleText
    tab_selected_text::StyleText
    page_color::StyleColor                # the area below the strip
    graphics_style::NamedTuple            # the ring around a page selected as a whole
    tab_padding::Int
    corner_radius::Int
    label_gap::Int                        # between a tab's icon and its label, and before its button
    icon_size::Float64                   # times the box of an icon and of a button, one line
    badge::Any                            # the badge printer of the theme, for the badges of a label
end

WidgetTabbedPaneToGraphicsCanvas(theme; graphics_theme = nothing, measure,
                                 margin = inset_default, border = inset_default,
                                 padding = _themed(Inset, theme, t -> t.tabbed_pane_padding),
                                 margin_color = color_transparent, border_color = color_transparent,
                                 padding_color = color_transparent, content_color = color_transparent,
                                 font = _themed(StyleFont, theme, t -> t.font),
                                 tab_strip_color = _themed(StyleColor, theme, t -> t.muted),
                                 tab_color = color_transparent,
                                 tab_selected_color = _themed(StyleColor, theme, t -> t.background),
                                 tab_text = _themed(StyleText, theme, t -> StyleText(t.font, t.muted_foreground)),
                                 tab_selected_text = _themed(StyleText, theme, t -> StyleText(t.font, t.foreground)),
                                 page_color = color_transparent,
                                 graphics_style = _make_graphics_style(graphics_theme),
                                 tab_padding = _themed(Int, theme, t -> t.item_gap),
                                 corner_radius = _themed(Int, theme, t -> t.radius),
                                 label_gap = _themed(Int, theme, t -> t.label_gap),
                                 icon_size = _themed(Float64, theme, t -> t.icon_size),
                                 badge = WidgetBadgeToGraphicsCanvas(theme; measure)) =
    WidgetTabbedPaneToGraphicsCanvas(measure, margin, border, padding, margin_color, border_color,
                                     padding_color, content_color, font, tab_strip_color, tab_color,
                                     tab_selected_color, tab_text, tab_selected_text, page_color,
                                     graphics_style, tab_padding, corner_radius, label_gap,
                                     icon_size, badge)

# The one scroll pane projection. It emits a `GraphicsCanvas` carrying the
# pane's real width and height — a parent that MEASURES its child (a WidgetCard
# sizing its body) needs them, or it under-sizes and the clipped viewport draws
# past its border — wrapping a `GraphicsViewport` that does the clipping.
#
# `chrome = false` omits the background fill, for a caller that paints its own
# or wants the pane to disappear into its surroundings. That is the only thing
# the retired `WidgetScrollPaneToGraphicsViewport` did differently; it was a
# second copy of the same viewport and the same coordinate arithmetic, and the
# copies drifted — one translated every pointer event and the other only the
# press, so a scrolled list's hover lagged the pointer by the scroll offset.
@projection UntrackedCell struct WidgetScrollPaneToGraphicsCanvas
    measure::TextMeasure
    margin::Inset
    border::Inset
    padding::Inset
    margin_color::StyleColor
    border_color::StyleColor
    padding_color::StyleColor
    content_color::StyleColor        # viewport fill; color_transparent paints none
    font::StyleFont                  # measures the scroll step
end

WidgetScrollPaneToGraphicsCanvas(theme; measure,
                                 font = _themed(StyleFont, theme, t -> t.font),
                                 margin = inset_default, border = inset_default, padding = inset_default,
                                 margin_color = color_transparent, border_color = color_transparent,
                                 padding_color = color_transparent,
                                 content_color = _themed(StyleColor, theme, t -> t.background)) =
    WidgetScrollPaneToGraphicsCanvas(measure, margin, border, padding, margin_color, border_color, padding_color,
                                     content_color, font)

@projection UntrackedCell struct WidgetTransformPaneToGraphicsCanvas
    measure::TextMeasure
    margin::Inset
    border::Inset
    padding::Inset
    margin_color::StyleColor
    border_color::StyleColor
    padding_color::StyleColor
    content_color::StyleColor         # default viewport fill
    font::StyleFont                   # measures the pan step
end

WidgetTransformPaneToGraphicsCanvas(theme; measure,
                                    font = _themed(StyleFont, theme, t -> t.font),
                                    margin = inset_default, border = inset_default, padding = inset_default,
                                    margin_color = color_transparent, border_color = color_transparent,
                                    padding_color = color_transparent,
                                    content_color = _themed(StyleColor, theme, t -> t.background)) =
    WidgetTransformPaneToGraphicsCanvas(measure, margin, border, padding, margin_color, border_color, padding_color,
                                        content_color, font)

@projection UntrackedCell struct WidgetToolbarToGraphicsCanvas
    measure::TextMeasure
    margin::Inset
    border::Inset
    padding::Inset
    margin_color::StyleColor
    border_color::StyleColor
    padding_color::StyleColor
    content_color::StyleColor
    font::StyleFont          # measures each item's advance
    item_gap::Int
end

WidgetToolbarToGraphicsCanvas(theme; measure,
                              margin = inset_default, border = inset_default,
                              padding = _themed(Inset, theme, t -> t.toolbar_padding),
                              margin_color = color_transparent, border_color = color_transparent,
                              padding_color = color_transparent, content_color = color_transparent,
                              font = _themed(StyleFont, theme, t -> t.font),
                              item_gap = _themed(Int, theme, t -> t.item_gap)) =
    WidgetToolbarToGraphicsCanvas(measure, margin, border, padding, margin_color, border_color,
                                  padding_color, content_color, font, item_gap)

@projection UntrackedCell struct WidgetScrollBarToGraphicsCanvas
    margin::Inset
    border::Inset
    padding::Inset
    margin_color::StyleColor
    border_color::StyleColor
    padding_color::StyleColor
    content_color::StyleColor
    track_color::StyleColor       # rail fill
    thumb_color::StyleColor       # thumb fill
    minimum_thumb_length::Int
    thickness::Int                # across the bar, where nothing sizes it
end

WidgetScrollBarToGraphicsCanvas(theme;
                                margin = inset_default, border = inset_default, padding = inset_default,
                                margin_color = color_transparent, border_color = color_transparent,
                                padding_color = color_transparent, content_color = color_transparent,
                                track_color = _themed(StyleColor, theme, t -> t.muted),
                                thumb_color = _themed(StyleColor, theme, t -> t.border),
                                minimum_thumb_length = _themed(Int, theme, t -> t.scroll_thumb_minimum),
                                thickness = _themed(Int, theme, t -> t.scroll_bar_thickness)) =
    WidgetScrollBarToGraphicsCanvas(margin, border, padding, margin_color, border_color, padding_color,
                                    content_color, track_color, thumb_color, minimum_thumb_length,
                                    thickness)

# ── IoMap for WidgetScrollPane ─────────────────────────────────────────────

@iomap struct WidgetScrollPaneToGraphicsCanvasIoMap
    projection::Any
    input::WidgetScrollPane
    output::GraphicsCanvas
    content_iomap::Any
end

# What a route reaches through this container: see `_collect_child_iomaps`.
ProjectionModule.get_child_iomaps(iomap::WidgetScrollPaneToGraphicsCanvasIoMap) =
    _collect_child_iomaps(iomap.content_iomap)

# ── IoMap for WidgetTransformPane ──────────────────────────────────────────

@iomap struct WidgetTransformPaneToGraphicsCanvasIoMap
    projection::Any
    input::WidgetTransformPane
    output::GraphicsCanvas
    content_iomap::Any
end

# What a route reaches through this container: see `_collect_child_iomaps`.
ProjectionModule.get_child_iomaps(iomap::WidgetTransformPaneToGraphicsCanvasIoMap) =
    _collect_child_iomaps(iomap.content_iomap)

# ── Text helpers ───────────────────────────────────────────────────────────

# Push `text` as one line whose line box has its top at `y`: the text sits on the
# baseline of that line (`compute_line_box`).
function _push_text!(elems::Vector, measure::TextMeasure, font::StyleFont, text::AbstractString,
                     x::Int, y::Int, fg::StyleColor)
    push!(elems, GraphicsText(text, x, y + compute_line_box(measure, text, font).text_y; font, color = fg))
end

# ── Text that must fit a width ──────────────────────────────────────────────
#
# A widget draws its own text as one measured line, and a line longer than the
# box is drawn past the edge and lost. Where the widget knows a width — the one
# it was told, or the one it was offered — it breaks the text to that width
# instead. Prose in a document is broken by `WordWrapping`, which this cannot
# use: a `String` in a widget field is not a `TextDocument`, and making one of
# it would give every label a domain it does not have.

# The lines `text` breaks into so that each fits `bound`, measured in `font`.
# A line break always ends a line. A text with no line break that fits is one
# line, so a widget whose text fits draws exactly the one line that it measures.
# A word wider than the bound keeps its own line: nothing can make a word
# narrower. A `bound` of zero is no bound.
function _text_lines(measure, font::StyleFont, text::AbstractString, bound::Int)
    !occursin('\n', text) && (bound <= 0 || first(_text_size(measure, font, text)) <= bound) &&
        return String[String(text)]
    out = String[]
    for paragraph in split(text, '\n'; keepempty = true)
        # A line break always ends a line; a line that fits stays whole.
        if bound <= 0 || first(_text_size(measure, font, paragraph)) <= bound
            push!(out, String(paragraph))
            continue
        end
        current = ""
        for word in split(paragraph, ' ')
            candidate = isempty(current) ? String(word) : current * " " * String(word)
            if isempty(current) || first(_text_size(measure, font, candidate)) <= bound
                current = candidate
            else
                push!(out, current)
                current = String(word)
            end
        end
        push!(out, current)
    end
    out
end

# One text, drawn from `x, y` down, broken to `bound`. Answers the width of the
# widest line and the height of all of them.
function _push_text_block!(elements::Vector, measure, style::StyleText,
                           text::AbstractString, x::Int, y::Int, bound::Int)
    width = 0
    height = 0
    for line in _text_lines(measure, style.font, text, bound)
        line_width, line_height = _text_size(measure, style.font, line)
        _push_text!(elements, measure, style.font, line, x, y + height, style.color)
        width = max(width, Int(line_width))
        height += Int(line_height)
    end
    (width, height)
end

# The width of `text` in `font` and the height of the line that holds it.
function _text_size(measure::TextMeasure, font::StyleFont, text::AbstractString)
    line = compute_line_box(measure, text, font)
    (line.width, line.height)
end

# ── Image / polymorphic content helpers ─────────────────────────────────────

# Decoded pixel payload of an ImageDocument and its natural size, read straight
# from the image's `raw` cell (filled by the backend's `decode_image_file!`):
#   (data, natural_w, natural_h)  when decoded
#   (nothing, 0, 0)               until decoded (printer draws a placeholder)
# Mirrors TextToGraphics' `_extract_image_data`: the domain layer only *reads*
# the raw bytes, never decodes (that is the backend's job).
function _image_payload(img::ImageDocument)
    raw = hasproperty(img, :raw) ? img.raw : nothing
    if raw isa Tuple && length(raw) == 3
        return (raw, Int(raw[2]), Int(raw[3]))
    end
    (raw, 0, 0)
end

# The rendered content size of a widget's polymorphic `content`: an ImageDocument
# measures to its natural size, anything else is stringified and text-measured.
function _content_size(measure, font::StyleFont, content)
    if content isa ImageDocument
        _, iw, ih = _image_payload(content)
        return (iw, ih)
    end
    _text_size(measure, font, string(content))
end

# Push a widget's polymorphic `content` into `elems` at (x, y). An ImageDocument
# becomes a GraphicsImage (a rect in `placeholder_color` when not yet decoded);
# everything else is drawn as label text. `cw`/`ch` are the resolved content box.
function _push_content!(elems::Vector, measure, label::StyleText, content,
                        x::Int, y::Int, cw::Int, ch::Int; placeholder_color::StyleColor)
    if content isa ImageDocument
        data, _, _ = _image_payload(content)
        if data === nothing
            # Not decoded yet — keep layout stable with a placeholder.
            _push_panel!(elems, x, y, cw, ch; fill = placeholder_color)
        else
            push!(elems, GraphicsImage(Int32(x), Int32(y), Int32(cw), Int32(ch), data))
        end
    else
        _push_text!(elems, measure, label.font, string(content), x, y, label.color)
    end
end

# ── Width resolution (content-aware + layout-aware) ─────────────────────────

# The sizing rule, once, for both axes. The parent gives each axis a range, a
# minimum and a maximum (`PrinterContext`); the widget draws
# `max(minimum, content)`, or its authored size.
#
#   - an exact range (the minimum is the maximum) stretches the widget to it, so
#     the widget takes its slot in a layout;
#   - a bounded or a free range has no minimum, so the widget draws its content;
#   - the widget never goes under its content — the measured content plus its
#     padding — so content is never lost; the container clips what passes the
#     maximum.
#
# A widget with no measurable content (progress, slider, skeleton) has a content
# of 0 and sizes from the minimum or from its authored value.
#
# The two axes are the same rule with a different field. Whether a widget fills
# on an axis is decided by the range its parent gave there, which is the parent's
# business and not the widget's.
# An overlay — a tooltip, a menu, a context menu — sizes to its content and to any
# size its caller asked for, and is then CAPPED at the maximum of the range rather
# than stretched to the minimum. A tooltip that filled its window would be a panel.
function _resolve_overlay(ctx, axis::Symbol, authored::Int, content::Int)
    base = max(authored, content)
    edge = ctx === nothing ? nothing :
           axis === :x ? ctx.maximum_width : ctx.maximum_height
    edge === nothing ? base : min(base, max(0, Int(edge[])))
end

# A widget's extent on one axis: `max(minimum, content)`, or the authored size.
# `authored` is the size the widget was given — `w.width`, `w.height`, a row
# count — and `content` is what it drew.
#
# An authored size is `Fixed`: a caller that wrote a number meant it, and a range
# that overrode it would take that away. `0` means the widget authored nothing.
# The widget then takes the minimum of the range its parent gave when its
# content is smaller: an exact range stretches it to the slot, and a bounded or
# a free range, whose minimum is 0, leaves it at its content.
#
# The content is a floor under the minimum, never under an authored size. A
# widget told to be 40 wide draws 40 and lets its content overflow, because that
# is what being told a size means. The maximum does not cut the widget: the
# container clips what passes it.
function _resolve_size(ctx, axis::Symbol, authored::Int, content::Int=0)
    authored > 0 && return authored
    minimum = ctx === nothing ? nothing :
              axis === :x ? ctx.minimum_width : ctx.minimum_height
    minimum === nothing ? content : max(0, Int(minimum[]), content)
end

_resolve_width(ctx, authored::Int, content::Int=0) =
    _resolve_size(ctx, :x, authored, content)

_resolve_height(ctx, authored::Int, content::Int=0) =
    _resolve_size(ctx, :y, authored, content)

# ── Canvas construction helper ─────────────────────────────────────────────

# A canvas of already-drawn children, which reports the extent they reach. The
# bounds are a computed cell rather than a number, because a child's own extent
# may be a cell that has no value yet when this is built.
function _make_canvas(x::Int, y::Int, elems::Vector)
    kept = CellVector(Cell[Cell(e) for e in elems])
    bounds = Cell(@computation begin
        w = 0; h = 0
        for e in kept
            ew, eh = _element_size(e, nothing)
            w = max(w, ew); h = max(h, eh)
        end
        (w, h)
    end)
    GraphicsCanvas(Int32(x), Int32(y),
                   Cell(@computation Int32(bounds[][1])),
                   Cell(@computation Int32(bounds[][2])),
                   kept, layout_none, true, Cell(nothing))
end

# The same, with its top a cell: a wrapper whose place follows what is above it,
# and that stays the same wrapper when it moves.
function _make_canvas(x::Int, y::Cell, elems::Vector)
    canvas = _make_canvas(x, 0, elems)
    GraphicsCanvas(getfield(canvas, :x), y, getfield(canvas, :w), getfield(canvas, :h),
                   getfield(canvas, :elements), layout_none, true, Cell(nothing))
end

function _make_canvas(x::Int, y::Int, w::Int, h::Int, elems::Vector)
    GraphicsCanvas(Int32(x), Int32(y), Int32(w), Int32(h),
                   CellVector(Cell[Cell(e) for e in elems]),
                   layout_none, true, Cell(nothing))
end

# Reactive analogue of `_make_canvas`: `build_fn()` returns
# `(; width, height, elements)` and is run inside a cell, so a leaf's extent and
# membership re-derive when the widget's cells change while the canvas keeps its
# identity (PAR-STABLE-IOMAP-IDENTITY). `x`/`y` are the leaf's own fixed origin
# (the parent positions it). Reads of the widget/style cells inside `build_fn`
# are what wire the reactivity. Replaces the eager `_make_canvas` at each leaf
# whose extent/membership depends on reactive widget state.
# Build the reactive canvas from an existing build cell (`build[] ->
# (; width, height, elements)`). A leaf whose IoMap must also expose the extent
# (e.g. a form control whose reader hit-tests `control_width`/`control_height`)
# holds the same `build` cell and stores `Cell(@computation build[].width)` etc.,
# so the canvas and the reader read one shared derivation.
function _reactive_canvas_cell(x::Int, y::Int, build::Cell)
    GraphicsCanvas(Int32(x), Int32(y),
                   Cell(@computation Int32(build[].width)),
                   Cell(@computation Int32(build[].height)),
                   CellVector(@computation build[].elements),
                   layout_none, true, Cell(nothing))
end

# Convenience for leaves that need only the canvas: make the build cell from a thunk.
_reactive_canvas(x::Int, y::Int, build_fn) = _reactive_canvas_cell(x, y, Cell(Computation(build_fn)))

# Auto-extent reactive canvas (w = h = 0, sized by its children) with reactive
# membership — the container analogue of the 3-arg `_make_canvas(x, y, elems)`.
# `elems_fn()` returns the (positioned) child element vector, re-derived reactively.
# A canvas of positioned children, which reports the extent those children reach.
#
# It answered `0 x 0` before, so a container built this way told its parent it
# occupied nothing: a layout could not place it, a scroll pane could not know
# whether it overflowed, and a test could not read it. The extent is the bounds of
# what was drawn, which is the only answer a container of positioned children has.
#
# `measure` is the projection's own text measurement — without it a canvas holding
# text directly reports nothing, which is the same bug with more steps. A
# projection that measures nothing (a composite holds already-drawn canvases, not
# words) has no such field, and `nothing` here means the caller-free form.
_p_measure(p) = hasproperty(p, :measure) ? p.measure : nothing

_element_size(e, measure) =
    measure === nothing ? get_graphics_size(e) : get_graphics_size(e, measure)

# The box a routed child takes in its container's frame, where a selection ring
# goes: the entry's offset, the child canvas's own origin, and the child's
# extent. A canvas that states its extent is taken at its word; any other child
# is measured. A child that takes the focus has no box here, because it draws
# its own focus ring when it is selected.
function _get_entry_box(x, y, cim, measure)
    # A control that takes the focus draws its own ring when it is selected.
    is_focusable_document(get_iomap_input(cim)) && return nothing
    child = cim.output
    child isa GraphicsDocument || return nothing
    x0, y0 = child isa GraphicsCanvas ? (Int(child.x[]), Int(child.y[])) : (0, 0)
    stated = child isa GraphicsCanvas && Int(child.w[]) > 0 && Int(child.h[]) > 0
    w, h = stated ? (Int(child.w[]), Int(child.h[])) : _element_size(child, measure)
    (Int(x isa Cell ? x[] : x) + x0, Int(y isa Cell ? y[] : y) + y0, w, h)
end

# `cap` is an overlay's context: given one, the extent is capped by what the
# parent offered rather than allowed to run past it.
function _reactive_canvas_auto(x::Int, y::Int, elems_fn, measure; cap = nothing)
    elems = CellVector(Computation(elems_fn))
    bounds = Cell(@computation begin
        w = 0; h = 0
        for e in elems
            ew, eh = _element_size(e, measure)
            w = max(w, ew); h = max(h, eh)
        end
        cap === nothing ? (w, h) :
            (_resolve_overlay(cap, :x, 0, w), _resolve_overlay(cap, :y, 0, h))
    end)
    GraphicsCanvas(Int32(x), Int32(y),
                   Cell(@computation Int32(bounds[][1])),
                   Cell(@computation Int32(bounds[][2])),
                   elems, layout_none, true, Cell(nothing))
end

_empty_canvas() = GraphicsCanvas(Int32(0), Int32(0), Int32(0), Int32(0),
                                 CellVector(), layout_none, true, Cell(nothing))

# ── Event routing helper ──────────────────────────────────────────────────

function _route_to_children(child_entries::Vector, evt, make_evt)
    hit = _find_child_hit(child_entries, evt, make_evt)
    hit === nothing ? nothing : first(hit)
end

# The answer of the first child of `entries` at the point of `evt` that answers the
# event that `make_evt(lx, ly)` makes at the point `(lx, ly)` of the child's frame,
# and the IoMap of that child: `(answer, child_iomap)`, or `nothing` when no child
# at the point answers.
function _find_child_hit(entries::Vector, evt, make_evt)
    for entry in entries
        point = _find_widget_child_point(entry, evt.x, evt.y)
        point === nothing && continue
        (lx, ly) = point
        # A position in the answer, such as a popup the child opens, goes back
        # into this frame by the offset the event came in by.
        answer = shift_operation_position(read_child_event(last(entry), make_evt(lx, ly)),
                                          evt.x - lx, evt.y - ly)
        answer === nothing || return (answer, last(entry))
    end
    nothing
end

# A dwell or a right click goes to the child of `entries` at its point, as a click
# goes (`_find_child_hit`). The answer of the child is re-rooted by the steps from
# `input`, the input of the container, to the child, found by identity as a point
# maps to a child (`_map_point_to_child`), and the container then reads its own
# stretch (`read_container_gesture`). When no child at the point answers, or the
# search finds no steps to the child, the container itself is the part.
function _read_children_outward(input, entries::Vector, gesture)
    hit = _find_child_hit(entries, gesture,
                          (x, y) -> shift_event_position(gesture, x - gesture.x,
                                                         y - gesture.y))
    steps = hit === nothing ? nothing : _find_child_steps(input, get_iomap_input(hit[2]))
    steps === nothing && return read_container_gesture(nothing, gesture, input)
    read_container_gesture(reroot_operation(hit[1], Tuple(steps)), gesture, input; steps)
end

# The point `(x, y)` of a container's frame in the frame of the child of `entry`,
# an `(x, y, child_iomap)` triple whose offsets are numbers or cells, when the
# child drew an element there; `nothing` otherwise. It is the hit test of a
# pointer event and of the backward mapping of a point, so a point maps to the
# child that a click there reaches.
function _find_widget_child_point(entry, x::Int, y::Int)
    entry isa Tuple && length(entry) == 3 || return nothing
    (ox, oy, cim) = entry
    canvas = cim.output
    canvas isa GraphicsCanvas || return nothing
    lx = x - Int(ox isa Cell ? ox[] : ox) - Int(canvas.x)
    ly = y - Int(oy isa Cell ? oy[] : oy) - Int(canvas.y)
    hit_element_at(canvas, lx, ly) === nothing && return nothing
    (lx, ly)
end

# The part of a container at `point` of its canvas: the child that `entries` holds
# at the point, the topmost first (the one drawn last), and on into that child
# with the point in its frame. A child that maps nothing at its point is itself
# the part. The steps from `input` to the child are found by identity, as a route
# reaches a child (`read_routed_child`), so a child held through a node without
# an IoMap of its own is found too.
function _map_point_to_child(input, entries, point::PointReferenceStep)
    for entry in Iterators.reverse(entries)
        local_point = _find_widget_child_point(entry, point.x, point.y)
        local_point === nothing && continue
        child = last(entry)
        steps = _find_child_steps(input, get_iomap_input(child))
        steps === nothing && return nothing
        answer = map_reference_backward(get_iomap_projection(child), child,
                                        PointReferenceStep(local_point...))
        path = answer === nothing ? EmptyReference() : answer
        for step in Base.reverse(steps)
            path = ConcreteReference(step, path)
        end
        return annotate_reference_types(input, path)
    end
    nothing
end

# The steps from `input` to `child`, a document it holds within three steps.
function _find_child_steps(input, child)
    input === child && return ReferenceStep[]
    paths = search_references(input, value -> value === child; maxdepth = 3)
    isempty(paths) ? nothing : collect(get_reference_steps(strip_reference_types(first(paths))))
end

# A point of a container that keeps its children in a `ChildrenIoMap` maps to the
# child drawn at it; any other reference maps to nothing.
function _map_child_point(iomap, reference)
    point = find_reference_point(reference)
    (point === nothing || !(iomap isa ChildrenIoMap)) && return nothing
    _map_point_to_child(iomap.input, getfield(iomap, :child_iomaps)[]::Vector, point)
end

# ── The move of the pointer ────────────────────────────────────────────
#
# A container gives such a move first to the child that its own mouse target
# names, when the point is not on that child: for that child the move is the leave
# of the pointer. Then it gives the move to the child at the point, which is the
# part under the pointer unless it names a part inside itself (`read_child_move`).

# Whether the mouse target of `document` begins with its field `name`.
function _is_mouse_target_in_field(document, name::AbstractString)
    target = get_mouse_target(document)
    target isa ConcreteReference && target.head isa FieldReferenceStep && target.head.name == name
end

# The entry of `entries` whose child the path `target` reaches from `input` within
# three steps, and those steps; `nothing` when the path reaches no child.
function _find_target_entry(input, entries::Vector, target)
    steps = ReferenceStep[]
    value = input
    path = target
    while path isa ConcreteReference && length(steps) < 3
        step = get_reference_head(path)
        value = try
            unwrap_cell(evaluate_reference_step(step, value))
        catch
            return nothing
        end
        push!(steps, step)
        for entry in entries
            entry isa Tuple && get_iomap_input(last(entry)) === value && return (entry, steps)
        end
        path = get_reference_tail(path)
    end
    nothing
end


# A move of the pointer in a container whose children are the
# `(x, y, child_iomap)` entries `entries`. The child at the point is the topmost
# one, as a point maps back (`_map_point_to_child`). Each answer is re-rooted by the
# steps from the container to its child. A point on the container and on no child
# is on the container itself, and a point off the container (`on_container` false)
# reaches only the child that the pointer leaves.
function _read_children_move(input, entries::Vector, evt::MouseMove, on_container::Bool)
    new_answer = nothing
    new_entry = nothing
    for entry in Iterators.reverse(entries)
        on_container || break
        point = _find_widget_child_point(entry, evt.x, evt.y)
        point === nothing && continue
        steps = _find_child_steps(input, get_iomap_input(last(entry)))
        steps === nothing && continue
        (lx, ly) = point
        move = MouseMove(lx, ly, evt.buttons, evt.modifiers; time = evt.time)
        answer = shift_operation_position(read_child_move(last(entry), move),
                                          evt.x - lx, evt.y - ly)
        new_answer = reroot_operation(answer, Tuple(steps))
        new_entry = entry
        break
    end
    old = _find_target_entry(input, entries, get_mouse_target(input))
    (old === nothing || old[1] === new_entry) && return new_answer
    (entry, steps) = old
    old_answer = read_child_leave(last(entry), evt, get_child_frame_offset(entry)...)
    join_move_answers(reroot_operation(old_answer, Tuple(steps)), new_answer)
end

_read_children_move(iomap::ChildrenIoMap, evt::MouseMove) =
    _read_children_move(iomap.input, getfield(iomap, :child_iomaps)[]::Vector, evt,
                        !_outside_widget(iomap, evt))

# A move of the pointer in a container with one child, in its field `field`,
# whose frame lies at `(dx, dy)` of the container's frame. A point on the child
# goes to the child. A point off it goes to the child only when the container's
# own mouse target is in the child. The answer is in the domain of the child.
function _read_single_child_move(input, field::AbstractString, child_iomap, evt::MouseMove,
                                 dx::Int, dy::Int, on_child::Bool)
    if on_child
        move = MouseMove(evt.x - dx, evt.y - dy, evt.buttons, evt.modifiers; time = evt.time)
        return shift_operation_position(read_child_move(child_iomap, move), dx, dy)
    end
    _is_mouse_target_in_field(input, field) || return nothing
    read_child_leave(child_iomap, evt, dx, dy)
end

# ── Forward: a part of a container, as the node that draws it ─────────────
#
# The mirror of `_map_point_to_child`. The reference reaches a child, found by
# identity as the input of one of the container's child IoMaps; the child's own
# mapper answers the rest of the reference; and the steps from the container's
# canvas to the child's canvas are found by identity too (`find_node_reference`),
# because a container puts parts of its own before its children, such as the
# parts of its box, whose number varies. The search goes six nodes deep: the
# page of a tabbed pane in a window is there, under the canvas that sizes the
# pane, its own canvas, the canvas of the page, the viewport of the page and the
# canvas in it. The empty reference is the container's own canvas. A part of the
# container that is no child, and a child that the container does not show, have
# no image.
function _map_child_forward(iomap, reference)
    reference isa Reference || return nothing
    reference = strip_reference_types(reference)
    reference isa ConcreteReference || return _map_self_forward(reference)
    children = something(get_child_iomaps(iomap), Any[])
    isempty(children) && return nothing
    node = unwrap_cell(get_iomap_input(iomap))
    rest = reference
    while rest isa ConcreteReference
        node = try
            unwrap_cell(evaluate_reference_step(get_reference_head(rest), node))
        catch
            return nothing
        end
        rest = get_reference_tail(rest)
        for child in children
            child === nothing && continue
            unwrap_cell(get_iomap_input(child)) === node || continue
            inner = map_reference_forward(get_iomap_projection(child), child, rest)
            inner === nothing && return nothing
            outer = find_node_reference(get_iomap_output(iomap), unwrap_cell(get_iomap_output(child));
                                        depth = 6)
            outer === nothing && return nothing
            return concat_references(outer, inner)
        end
    end
    nothing
end

# The image of a widget itself: its own canvas, the empty reference. A widget with
# no parts that a reference names maps nothing else.
_map_self_forward(reference) = reference isa EmptyReference ? EmptyReference() : nothing

_route_scroll_to_children(child_entries::Vector, evt::MouseScroll) =
    _route_to_children(child_entries, evt,
        (x, y) -> MouseScroll(evt.dx, evt.dy, x, y; time = evt.time))

_route_click_to_children(child_entries::Vector, evt::MouseClick) =
    _route_to_children(child_entries, evt,
        (x, y) -> MouseClick(evt.button, x, y, evt.count, evt.modifiers; time = evt.time))

# Route a raw press-down / release to the hit child (coordinate-translated), so a
# button nested in a container flips its `pressed` cell (the depress feedback). The
# composed MouseClick click is routed separately via `_route_click_to_children`.
_route_downup_to_children(child_entries::Vector, evt) =
    _route_to_children(child_entries, evt,
        (x, y) -> evt isa MouseDown ? MouseDown(evt.button, x, y, evt.modifiers;
                                                time = evt.time) :
                                      MouseUp(evt.button, x, y, evt.modifiers;
                                              time = evt.time))

# Translate a path-bearing op from `op`'s current domain (this projection's
# child's input domain — what the bubbled-up reader returned) into this
# projection's own input domain by running its reference through
# `map_reference_backward`. Identity-rooted / non-path-bearing ops (an
# identity-rooted `ReplaceReferencedValueOperation`, `CloseTabOperation`, …) pass through
# unchanged; `nothing` passes through.
# Returns `nothing` if the backward mapping rejects the reference.
function _retarget_op(p, iomap, op)
    op === nothing && return nothing
    if op isa ReplacePathOperation
        new_ref = map_reference_backward(p, iomap, get_operation_path(op))
        return new_ref === nothing ? nothing : make_path_operation(op, new_ref)
    elseif op isa ReplaceStringRangeOperation
        new_ref = map_reference_backward(p, iomap, op.reference)
        return new_ref === nothing ? nothing : ReplaceStringRangeOperation(new_ref, op.replacement)
    elseif op isa ReplaceNumberRangeOperation
        new_ref = map_reference_backward(p, iomap, op.reference)
        return new_ref === nothing ? nothing : ReplaceNumberRangeOperation(new_ref, op.replacement)
    elseif op isa ReplaceReferencedValueOperation
        # `editor.document`-rooted (document === nothing) ⇒ reroot the reference;
        # a self-contained one (carried root) passes through unchanged.
        op.document === nothing || return op
        new_ref = map_reference_backward(p, iomap, op.reference)
        return new_ref === nothing ? nothing : ReplaceReferencedValueOperation(nothing, new_ref, op.value)
    elseif op isa CompoundOperation
        mapped = Any[_retarget_op(p, iomap, o) for o in op.operations]
        # A move answers every part that it reached: each goes back alone.
        has_mouse_target(op) && return join_move_answers(mapped...)
        return any(isnothing, mapped) ? nothing : CompoundOperation(mapped)
    elseif op isa WrappingOperation
        inner = _retarget_op(p, iomap, get_wrapped_operation(op))
        return inner === nothing ? nothing : rewrap_operation(op, inner)
    elseif op isa CollectedIntentsOperation
        # A collection maps like a compound: every carried operation into this
        # container's input domain. A container that holds its child under a
        # field — a shell holds one at `content` — must add that step here too,
        # or the palette runs a command whose path starts one level too deep.
        # Unlike a compound it never fails as a whole: a row that cannot be run
        # is still worth showing.
        return CollectedIntentsOperation([
            Intent(intent.gesture,
                   intent.operation === nothing ? nothing :
                       _retarget_op(p, iomap, intent.operation),
                   intent.description, intent.domain)
            for intent in op.intents])
    else
        return op
    end
end

# Reference/operation re-rooting lives in `OperationModule`
# (`reroot_operation` / `reroot_reference`) — shared with the layout
# container readers so the prepend logic is defined once.

# ── WidgetLabel ─────────────────────────────────────────────────────────────

# The text style of a label: its own `text_style`, which can be a whole style, a
# bare colour or a bare font, over the label text of the theme and of its style.
function _get_label_style(p::WidgetLabelToGraphicsCanvas, w::WidgetLabel)
    label = _get_part_text(w, :label_text, p.label_text)
    w.text_style === nothing ? label :
    w.text_style isa StyleColor ? StyleText(label.font, w.text_style) :
    w.text_style isa StyleFont ? StyleText(w.text_style, label.color) :
    w.text_style
end

# The baseline of the first line of a label: the top of its content box and the
# baseline of the line box of its text. An image has none.
function find_first_baseline(p::WidgetLabelToGraphicsCanvas, iomap::SimpleIoMap)
    w = iomap.input
    (w.visible == false || w.content isa ImageDocument) && return nothing
    _, content_y = _content_offset(p, w)
    content_y + compute_line_box(p.measure, string(w.content), _get_label_style(p, w).font).baseline
end

function print_document(p::WidgetLabelToGraphicsCanvas, recursion, w::WidgetLabel, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    position = w.position::Point2D
    SimpleIoMap(p, w, _reactive_canvas(_origin(position)..., () -> begin
        content = w.content
        # A label may carry its own font+color (e.g. a chat card's title) that
        # overrides the theme's default label style — or a bare COLOUR, which
        # takes the theme's font and only changes the ink, or a bare FONT, which
        # takes the theme's ink. The colour is what lets a severity, a diff or a
        # status be coloured without a caller naming a font and so dropping out
        # of the theme; the font is what lets a label write an icon of the icon
        # font in the color of the text beside it. `text_style` wins over the
        # `label_text_color` of a style.
        style = _get_label_style(p, w)
        box = _get_box_insets(p, w)
        colors = _get_box_colors(p, w)
        inset_width, inset_height = _inset_total(p, w)
        content_x, content_y = _content_offset(p, w)
        content_width, content_height = _content_size(p.measure, style.font, content)
        elements = Any[]
        # Text breaks at the edge of the range the parent gave, exact or bounded,
        # less the box. A label in a column holds prose in that column, and a line
        # longer than the column would be drawn past it and lost. An image is not
        # broken; it fills its box.
        edge = ctx === nothing ? nothing : ctx.maximum_width
        bound = edge === nothing || content isa ImageDocument ? 0 : max(0, Int(edge[]) - inset_width)
        if bound > 0 && content_width > bound
            text_elements = Any[]
            text_width, text_height = _push_text_block!(text_elements, p.measure, style, string(content),
                                                        content_x, content_y, bound)
            outer_width = _resolve_width(ctx, 0, text_width + inset_width)
            outer_height = _resolve_height(ctx, 0, text_height + inset_height)
            _push_box_parts!(elements, box, colors, outer_width - inset_width, outer_height - inset_height)
            append!(elements, text_elements)
            return (width = outer_width, height = outer_height, elements = elements)
        end
        # No size of its own, so the offer decides and the content is the floor.
        # An image label fills what it is given; text stays where it is drawn.
        outer_width  = _resolve_width(ctx, 0, content_width + inset_width)
        outer_height = _resolve_height(ctx, 0, content_height + inset_height)
        content_width, content_height = outer_width - inset_width, outer_height - inset_height
        _push_box_parts!(elements, box, colors, content_width, content_height)
        _push_content!(elements, p.measure, style, content, content_x, content_y, content_width,
                       content_height; placeholder_color = p.placeholder_color)
        (width = outer_width, height = outer_height, elements = elements)
    end))
end

map_reference_forward(::WidgetLabelToGraphicsCanvas, iomap, reference) = _map_child_forward(iomap, reference)

function map_reference_backward(::WidgetLabelToGraphicsCanvas, iomap, reference)
    return nothing
end


# ── Every widget checks its own bounds ────────────────────────────────────────
#
# A container is expected to clip a position to a child's frame before handing
# the event down, and every container here does. That is not enough to rely on:
# a widget can be put into anything — a container written elsewhere, a
# projection composed by hand, or nothing at all when it is the root — and a
# contract nothing enforces is not one to build on. A 100x30 button with no
# container above it would answer a press 800 pixels to its right.
#
# So each widget asks whether the position is inside what it drew. A widget
# reads a position in the frame of its own canvas, as its container, or the
# window at the root, took the place of the canvas off; so the canvas spans 0 to
# its width and 0 to its height, one comparison per event with nothing new
# stored.
#
# Only POSITIONED events are judged: a click, a button down and up, a move, a turn
# of the wheel, and a dwell, which goes to the part at its point as a click does. A
# move that the pointer makes off a widget reaches it at a point outside, such as
# `(-1, -1)`. A key carries no position and is routed by selection.
_positioned_event(evt) = evt isa MouseClick || evt isa MouseDown || evt isa MouseUp ||
                         evt isa MouseMove || evt isa MouseScroll || evt isa MouseDwell

function _outside_widget(iomap, evt)
    _positioned_event(evt) || return false
    canvas = iomap.output
    canvas isa GraphicsCanvas || return false      # nothing drawn: nothing to bound
    canvas.w <= 0 && return false                  # unsized: the container decides
    canvas.h <= 0 && return false
    !(0 <= evt.x < canvas.w && 0 <= evt.y < canvas.h)
end

# A key pressed with no modifier. A control takes Return, Space and the arrows
# only bare, so an Alt+arrow still walks the selection and a chord still reaches a
# shortcut.
_is_plain_key(evt, keys::Symbol...) =
    evt isa KeyDown && evt.key in keys && evt.modifiers == ModifierKeys()

# The row that holds `y`, from `(top, bottom)` bounds in the frame of the widget,
# or `nothing` between and past the rows.
function _find_row_index(bounds, y::Real)
    for (index, (top, bottom)) in enumerate(bounds)
        top <= y < bottom && return index
    end
    nothing
end

function read_intent(::WidgetLabelToGraphicsCanvas, iomap::SimpleIoMap, evt)
    _outside_widget(iomap, evt) && return nothing
    return nothing
end

# ── WidgetInsertion ──────────────────────────────────────────────────────────

# Renders the type-replace placeholder ("insert here") as a muted text canvas at
# the origin. WidgetInsertion carries no `position`/`content` value of its own,
# so there is nothing to map; like the sibling JsonInsertion handler it is a
# projection-introduced placeholder and its reference maps are no-ops.
@projection UntrackedCell struct WidgetInsertionToGraphicsCanvas
    measure::TextMeasure
    margin::Inset
    border::Inset
    padding::Inset
    margin_color::StyleColor
    border_color::StyleColor
    padding_color::StyleColor
    content_color::StyleColor
    label_text::StyleText
end

WidgetInsertionToGraphicsCanvas(theme; measure,
                                margin = inset_default, border = inset_default, padding = inset_default,
                                margin_color = color_transparent, border_color = color_transparent,
                                padding_color = color_transparent, content_color = color_transparent,
                                label_text = _themed(StyleText, theme, _get_body_text)) =
    WidgetInsertionToGraphicsCanvas(measure, margin, border, padding, margin_color, border_color,
                                    padding_color, content_color, label_text)

function print_document(p::WidgetInsertionToGraphicsCanvas, recursion, w::WidgetInsertion, ctx)
    content = "insert here"
    label = _get_part_text(w, :label_text, p.label_text)
    content_width, content_height = _text_size(p.measure, label.font, content)
    inset_width, inset_height = _inset_total(p, w)
    content_x, content_y = _content_offset(p, w)
    elements = Any[]
    _push_box_parts!(elements, _get_box_insets(p, w), _get_box_colors(p, w), content_width, content_height)
    _push_text!(elements, p.measure, label.font, content, content_x, content_y, label.color)
    SimpleIoMap(p, w, _make_canvas(0, 0, content_width + inset_width, content_height + inset_height, elements))
end

map_reference_forward(::WidgetInsertionToGraphicsCanvas, iomap, reference) = _map_child_forward(iomap, reference)
map_reference_backward(::WidgetInsertionToGraphicsCanvas, iomap, reference) = nothing
read_intent(::WidgetInsertionToGraphicsCanvas, iomap::SimpleIoMap, evt) = nothing

# ── WidgetText ──────────────────────────────────────────────────────────────

# IoMap for a WidgetText. The text domain draws the content and makes every caret
# move and every edit, and the widget re-roots what it answers under `content`
# (see `map_reference_backward`). A Document content, typically a `TextBlock`, is
# recursed through the chain. A plain value is drawn through a text view of its
# string, which `_make_plain_text_view` makes.
# @iomap so the reader reads content_iomap/input transparently; the content is
# reconciled so a field grows reactively as text is typed
# (PAR-STABLE-IOMAP-IDENTITY).
@iomap struct WidgetTextToGraphicsCanvasIoMap
    projection::Any
    input::Any
    output::Any
    content_iomap::Any
end

# ── A plain value as a text ─────────────────────────────────────────────────
#
# A `WidgetText` or a `WidgetTextarea` whose `content` is a plain value, such as
# a `String`, is edited as a text too. The printer makes one `TextBlock` whose
# text is the string of the value and whose caret is the range of `content` that
# the widget holds, and draws it with a `TextToGraphics` of its own, so a chain
# with no rule for a `TextBlock` draws it too. The block is one span, or, for a
# field of code, a span for each piece that `compute_code_pieces` gives, in its
# color. The reader maps what the text domain answers back to a range of the
# `content` field. So a string edit writes the field itself, and the caret after
# the edit is again a range of the field.

# The spans of a field of code: a span for each piece of its text, in the color
# of the piece, or of the field. `appearance` gives the colors of the language.
function _make_code_spans(w, style::StyleText, appearance)
    text = string(w.content)
    spans = Any[]
    start = 1
    for (count, color) in _get_plain_text_pieces(w, text, appearance)
        stop = count == 0 ? start - 1 : nextind(text, start, count) - 1
        push!(spans, TextString(text[start:min(stop, lastindex(text))],
                                color === nothing ? style : StyleText(style.font, color)))
        start = stop + 1
    end
    spans
end

# The pieces of the text of `w`: one, or the pieces of the code of its language.
function _get_plain_text_pieces(w, text::AbstractString, appearance)
    language = hasproperty(w, :language) ? w.language : nothing
    language === nothing && return Tuple{Int,Any}[(length(text), nothing)]
    Base.invokelatest(compute_code_pieces, Val(language), text, appearance)
end

function _make_plain_text_view(w, style::StyleText, appearance)
    language = hasproperty(w, :language) ? w.language : nothing
    view = language === nothing ? TextBlock(TextString(() -> string(w.content), style)) :
                                  TextBlock(() -> _make_code_spans(w, style, appearance))
    set_cell_computation!(getfield(view, :selection),
                          () -> _get_plain_text_caret(w.selection))
    set_cell_computation!(getfield(view, :mouse_target),
                          () -> _get_plain_text_caret(w.mouse_target))
    view
end

# `appearance` is the appearance of a field of code, whose theme of its language
# gives the colors, or `nothing`.
function _print_plain_text_view(p, recursion, w, style::StyleText, ctx; appearance = nothing)
    view = _make_plain_text_view(w, style, appearance)
    measure = p.measure
    make_reconciled_child_iomap_cell(() -> view,
                          v -> print_document(TextToGraphics(measure = measure), recursion, v, ctx))
end

# The caret of the view: the range of `content` that the widget holds, as a flat
# range of the one span. A widget that holds no such range shows no caret.
function _get_plain_text_caret(selection)
    selection isa Reference || return nothing
    steps = get_reference_steps(strip_reference_types(selection))
    length(steps) == 2 || return nothing
    (steps[1] isa FieldReferenceStep && steps[1].name == "content") || return nothing
    range = steps[2]
    (range isa RangeReferenceStep || range isa TextRangeReferenceStep) || return nothing
    make_flat_range_reference(range.start, range.stop)
end

_make_content_range_reference(start::Int, stop::Int) =
    ConcreteReference(FieldReferenceStep("content"),
                      ConcreteReference(RangeReferenceStep(start, stop), EmptyReference()))

# A reference of the view, mapped to a range of the `content` field. The text
# domain answers a caret or a selection as a flat range, and an edit of the one
# span as `elements[1].content[start:stop]`. The whole view, which a press on an
# empty string answers, is the caret at the end of the string.
function _map_plain_text_reference(w, reference)
    reference === nothing && return nothing
    steps = get_reference_steps(strip_reference_types(reference))
    if isempty(steps)
        n = length(string(w.content))
        return _make_content_range_reference(n, n)
    end
    range = steps[end]
    if length(steps) == 1 && range isa TextRangeReferenceStep
        return _make_content_range_reference(range.start, range.stop)
    end
    if length(steps) == 4 && range isa RangeReferenceStep &&
       steps[1] isa FieldReferenceStep && steps[1].name == "elements" &&
       steps[2] isa RangeReferenceStep &&
       steps[3] isa FieldReferenceStep && steps[3].name == "content"
        # A range in span `k` of the pieces is that range moved by the length of
        # the spans before it. The lengths do not depend on the colors, so the
        # pieces need no appearance.
        text = string(w.content)
        before = sum((first(piece) for piece in _get_plain_text_pieces(w, text, nothing)[1:steps[2].start]);
                     init = 0)
        return _make_content_range_reference(before + range.start, before + range.stop)
    end
    nothing
end

# The range of the content of a widget that draws its box around it: the range of
# the widget less its insets, in the same state, so a slot stays a slot and an edge
# stays an edge (§3 of layout-rules.md).
function _get_inner_content_context(p, w::WidgetDocument, ctx)
    ctx === nothing && return nothing
    with_inner_size(ctx; width = Cell(@computation _inset_total(p, w)[1]),
                    height = Cell(@computation _inset_total(p, w)[2]))
end

function print_document(p::WidgetTextToGraphicsCanvas, recursion, w::WidgetText, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    pos = w.position::Point2D

    state = w.enabled === false ? :disabled : nothing

    # The content is drawn by the text domain, and the box grows with the text.
    # A Document content (e.g. a TextBlock) is recursed through the outer
    # projection chain (which routes it to TextToGraphics); a plain value is
    # drawn through a text view of its string. Mirrors WidgetScrollPane's
    # content recursion.
    content_ctx = _get_inner_content_context(p, w, ctx)
    content_iomap = w.content isa Document ?
        make_reconciled_child_iomap_cell(() -> w.content, c -> print_child(recursion, c, content_ctx)) :
        _print_plain_text_view(p, recursion, w, _get_state_text(p, w, :label; state), content_ctx;
                               appearance = p.appearance)
    build = Cell(@computation begin
        radius = p.corner_radius
        inner = content_iomap[].output::GraphicsCanvas
        # The box is at least as wide as the widget asks for, and always at
        # least one line tall. An empty document measures nothing in both
        # directions, and a form field of nothing cannot be clicked.
        inset_width, inset_height = _inset_total(p, w)
        content_x, content_y = _content_offset(p, w)
        # An empty field of plain text shows its placeholder, an example of what
        # it takes, where its text begins, and is as wide as the example.
        placeholder = w.placeholder
        shows_placeholder = placeholder !== nothing && !(w.content isa Document) && isempty(string(w.content))
        inner_w = Int(inner.w[])
        shows_placeholder && (inner_w = max(inner_w, _text_size(p.measure, p.placeholder_text.font,
                                                                String(placeholder))[1]))
        # `w.width` is an authored inner width, so it and the offer are both
        # outer measures here: resolve the outer extent by the one rule, then
        # take the inner box back out of it.
        outer_w = _resolve_width(ctx, w.width > 0 ? w.width + inset_width : 0, inner_w + inset_width)
        outer_h = _resolve_height(ctx, 0,
                                  max(Int(inner.h[]),
                                      _text_size(p.measure, p.label_text.font, "X")[2]) + inset_height)
        elems = Any[]
        _push_box_parts!(elems, _get_box_insets(p, w), _get_box_colors(p, w; state),
                         outer_w - inset_width, outer_h - inset_height; radius)
        if shows_placeholder
            style = p.placeholder_text
            push!(elems, GraphicsText(String(placeholder), content_x, content_y; font = style.font,
                                      color = style.color))
        end
        # A press anywhere in the box of a field that takes edits puts the caret,
        # and a press on a disabled field does nothing, also over its text.
        state === :disabled || push!(elems, GraphicsPointerShape(0, 0, outer_w, outer_h, :ibeam))
        push!(elems, _make_canvas(content_x, content_y, Any[inner]))
        state === :disabled && push!(elems, GraphicsPointerShape(0, 0, outer_w, outer_h, :arrow))
        _push_focus_ring!(elems, w, outer_w, outer_h, p.focus_ring_stroke, radius;
                          whole = p.graphics_style)
        (width=outer_w, height=outer_h, elements=elems)
    end)
    WidgetTextToGraphicsCanvasIoMap(p, w, _reactive_canvas_cell(_origin(pos)..., build), content_iomap)
end

map_reference_forward(::WidgetTextToGraphicsCanvas, iomap, reference) = _map_child_forward(iomap, reference)

function map_reference_backward(::WidgetTextToGraphicsCanvas, iomap, reference)
    return nothing
end

# Re-root a content-domain reference (already translated by the inner Text-domain
# reader) into this widget's domain by prepending `.content`. Same contribution
# WidgetScrollPane makes for its wrapped document. A reference of the text view
# of a plain value is a range of `content` itself. A point, which a container
# can pass as a bare step, is on the content (`_map_text_point`).
function map_reference_backward(::WidgetTextToGraphicsCanvas, iomap::WidgetTextToGraphicsCanvasIoMap, reference)
    reference === nothing && return nothing
    point = find_reference_point(reference)
    point === nothing || return _map_text_point(point)
    w = iomap.input
    w.content isa Document || return _map_plain_text_reference(w, reference)
    ConcreteReference(FieldReferenceStep("content"), reference)
end

# A point of a text widget: its content is the part there, at that point. The
# point ends the path, so the content is the same part at every point of it.
_map_text_point(point::PointReferenceStep) =
    ConcreteReference(FieldReferenceStep("content"), ConcreteReference(point, EmptyReference()))

# Invisible text (the printer returned a bare empty canvas): inert.
read_intent(::WidgetTextToGraphicsCanvas, iomap::SimpleIoMap, evt) = nothing

# Delegate every event to the recursed content (Text domain), then re-root the
# returned path-bearing operation through `map_reference_backward`.
function read_intent(p::WidgetTextToGraphicsCanvas, iomap::WidgetTextToGraphicsCanvasIoMap, evt)
    _outside_widget(iomap, evt) && return nothing
    iomap.input.enabled === false && return nothing   # a disabled text widget accepts no edits
    _validate_text_edit(iomap.input,
                        _read_text_content_intent(p, iomap, evt, _content_offset(p, iomap.input)...))
end

# Give an event to the text document that a text widget holds, and re-root the
# answer under `content`. The Text domain makes every caret move and every edit.
# A press moves into the frame of the content first: `left` and `top` are where
# the widget draws the content, from its own origin.
function _read_text_content_intent(p, iomap, evt, left::Int, top::Int)
    content_iomap = iomap.content_iomap
    content_iomap === nothing && return nothing
    op = @gesture_case evt begin
        MouseClick(button, x, y) => begin
            cox, coy = left, top
            # The box can be wider and taller than what it holds: it has a `width`
            # floor, and an empty document measures nothing at all. Clamp the
            # press into the content's own extent, so a click anywhere in the box
            # lands in the text — at the nearest character, and at the start when
            # there is no text to be near. Without this an empty field cannot be
            # clicked into at all, and a wide one only over its own letters.
            inner = content_iomap.output
            (lx, ly) = if inner isa GraphicsCanvas
                (clamp(x - cox, 0, max(0, Int(inner.w))), clamp(y - coy, 0, max(0, Int(inner.h))))
            else
                (x - cox, y - coy)
            end
            answer = shift_operation_position(
                read_intent(content_iomap.projection, content_iomap,
                            MouseClick(button, lx, ly, evt.count, evt.modifiers;
                                       time = evt.time)),
                cox, coy)
            # A document with nothing in it measures nothing, so it has no
            # position to answer with and an empty field could not be clicked
            # into at all. A left click in the box means "the caret goes here",
            # and on an empty document that is the whole of it. Another button
            # moves no caret.
            answer === nothing && button === :left ?
                ReplaceSelectionOperation(EmptyReference()) : answer
        end
        _ => read_intent(content_iomap.projection, content_iomap, evt)
    end
    _retarget_op(p, iomap, op)
end

# Stage 6 validators: drop a string edit whose inserted text the widget's
# `validator` (an acceptor `(String) -> Bool`) rejects. Non-string ops, a
# `nothing` validator, and deletions (empty replacement) pass through.
function _validate_text_edit(w::WidgetText, op)
    v = w.validator
    (v === nothing || op === nothing) && return op
    op isa ReplaceStringRangeOperation || return op
    (v(string(op.replacement)) === true) ? op : nothing
end

# ── WidgetCheckbox ──────────────────────────────────────────────────────────

# The content of a control with a mark and a label after it, a checkbox or a
# switch: its width and its height, the offset of the mark from the top, and the
# label with its style and its place, or `nothing` when the control has none.
# The mark and the label are each centred in the height of the larger.
function _get_mark_label_layout(p, w, mark_width::Int, mark_height::Int, enabled::Bool)
    label = w.label
    label === nothing && return (width = mark_width, height = mark_height, mark_y = 0, label = nothing)
    text = string(label)
    style = _get_state_text(p, w, :label; state = enabled ? nothing : :disabled)
    text_width, line = _text_size(p.measure, style.font, text)
    height = max(mark_height, line)
    (width = mark_width + p.label_gap + text_width, height, mark_y = (height - mark_height) ÷ 2,
     label = (text = text, style = style, x = mark_width + p.label_gap, y = (height - line) ÷ 2))
end

# The label of `content` (`_get_mark_label_layout`), with the content at (x, y).
function _push_mark_label!(elements::Vector, p, content, x::Int, y::Int)
    label = content.label
    label === nothing && return elements
    _push_text!(elements, p.measure, label.style.font, label.text, x + label.x, y + label.y,
                label.style.color)
end

function print_document(p::WidgetCheckboxToGraphicsCanvas, recursion, w::WidgetCheckbox, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    position = w.position::Point2D
    SimpleIoMap(p, w, _reactive_canvas(_origin(position)..., () -> begin
        checked = w.content === true
        enabled = !(w.enabled === false)
        box_size = p.indicator_size
        corner_radius = p.corner_radius
        inset_width, inset_height = _inset_total(p, w)
        content_x, content_y = _content_offset(p, w)
        content = _get_mark_label_layout(p, w, box_size, box_size, enabled)
        x, y = content_x, content_y + content.mark_y
        elements = Any[]
        _push_box_parts!(elements, _get_box_insets(p, w), _get_box_colors(p, w), content.width, content.height)
        _push_mark_label!(elements, p, content, content_x, content_y)
        # When disabled, the box uses the muted surface and the tick/outline render in
        # the muted foreground, keeping the checked/unchecked shape but signalling that
        # the control is inert (its reader also swallows clicks).
        state = !enabled ? :disabled : checked ? :checked : nothing
        indicator_color = _get_state_color(p, w, :indicator; state)
        if checked
            _push_panel!(elements, x, y, box_size, box_size; fill=indicator_color, radius=corner_radius)
            _push_icon!(elements, :check, x, y, box_size, _get_state_color(p, w, :check; state))
        else
            outline = _get_state_stroke(p, w, :indicator; state)
            _push_panel!(elements, x, y, box_size, box_size; fill=indicator_color,
                         border=outline.color, border_w=max(1, Int(outline.width)), radius=corner_radius)
        end
        outer_width, outer_height = content.width + inset_width, content.height + inset_height
        _push_focus_ring!(elements, w, outer_width, outer_height, p.focus_ring_stroke, corner_radius)
        (width=outer_width, height=outer_height, elements=elements)
    end))
end

map_reference_forward(::WidgetCheckboxToGraphicsCanvas, iomap, reference) = _map_child_forward(iomap, reference)

function map_reference_backward(::WidgetCheckboxToGraphicsCanvas, iomap, reference)
    return nothing
end

# A click toggles the checkbox. By convention a leaf control reports an edit as
# `ReplaceReferencedValueOperation(self, content, new_value)`; a configuring projection
# (ObjectToWidget) intercepts it by control identity and redirects it onto the
# bound parameter cell. A bare click that does not reach here leaves the value
# unchanged.
_checkbox_toggle(w) = ReplaceReferencedValueOperation(w,
    ConcreteReference(FieldReferenceStep("content"), EmptyReference()), !(w.content === true))

function read_intent(::WidgetCheckboxToGraphicsCanvas, iomap::SimpleIoMap, evt::MouseClick)
    _outside_widget(iomap, evt) && return nothing
    w = iomap.input
    w.enabled === false && return nothing   # a disabled checkbox swallows the click
    op = read_bound_gesture(w, evt); op === nothing || return op   # per-instance gestures win
    evt.button === :left || return nothing
    _checkbox_toggle(w)
end

# Enter / Space with no modifier toggle the focused checkbox (the keystroke
# reaches it via the selection-driven routing). Tab is left to fall through
# (nothing) so focus traversal can claim it.
function read_intent(::WidgetCheckboxToGraphicsCanvas, iomap::SimpleIoMap, evt)
    _outside_widget(iomap, evt) && return nothing
    w = iomap.input
    w.enabled === false && return nothing
    op = read_bound_gesture(w, evt); op === nothing || return op   # per-instance gestures win
    _is_plain_key(evt, :return, :space) || return nothing
    _checkbox_toggle(w)
end

# ── WidgetButton ────────────────────────────────────────────────────────────

# A control is a view of its `Action` (the constructor guarantees one is always
# there, folding a sugar-built control's own label/icon into a fresh one), so
# the printers read the action and nothing else — no precedence rule.
_button_action(w::WidgetButton) = w.action::Action
# Enablement is a CONJUNCTION, not an override: this view can be inert while the
# shared command stays live in its other views.
_button_enabled(w::WidgetButton) =
    !(w.enabled === false) && !(_button_action(w).enabled === false)
# The label is passed RAW, never string()-coerced here: the polymorphic
# branches downstream (`_content_size` / `_push_content!` render an
# `ImageDocument`, the menu-item printer recurses a `WidgetDocument`) must see
# the value itself, and text stringification already happens at the leaf.
_button_label_content(w::WidgetButton) = _button_action(w).label
# Icon (Stage 5): on the action, like the label.
_button_icon(w::WidgetButton) = _button_action(w).icon

function print_document(p::WidgetButtonToGraphicsCanvas, recursion, w::WidgetButton, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    position = w.position::Point2D
    SimpleIoMap(p, w, _reactive_canvas(_origin(position)..., () -> begin
        authored_size = w.size::Point2D
        label_content = _button_label_content(w)
        content_width, content_height = _content_size(p.measure, p.label_text.font, label_content)
        # A button that can show several labels is as wide as the widest, so the
        # row it stands in does not move when the label changes.
        for other in w.labels
            content_width = max(content_width, first(_content_size(p.measure, p.label_text.font, other)))
        end
        box = _get_box_insets(p, w)
        inset_width, inset_height = _inset_total(p, w)
        content_x, content_y = _content_offset(p, w)
        # An optional leading icon: a square of the height of the label times the icon
        # scale, with a gap before the label. The button is as tall as the larger of
        # the icon and the label. An unknown icon name contributes nothing.
        icon = _button_icon(w)
        icon_sz = scale_length(content_height, p.icon_size)
        icon_w  = icon_width(icon, icon_sz)
        icon_gap = icon_w > 0 ? p.label_gap : 0
        full_w = icon_w + icon_gap + content_width
        full_h = max(icon_w, content_height)
        button_width  = _resolve_width(ctx, Int(authored_size.x[]), full_w + inset_width)
        button_height = _resolve_height(ctx, Int(authored_size.y[]), full_h + inset_height)
        inner_width, inner_height = button_width - inset_width, button_height - inset_height
        corner_radius = p.corner_radius
        # State-driven surface. The reader keeps the transient `pressed` cell
        # current, and the mouse target says whether the pointer is on the button.
        # A lit or a pressed button draws a translucent layer over its surface, so
        # the state shows over any surface color; the layer reads the state in
        # cells of its own. A press also drops the shadow, so it is read here. A
        # disabled button (or one bound to a disabled command) ignores both: its
        # own muted surface and label, no shadow, no layer (its reader also never
        # sets `pressed`).
        enabled = _button_enabled(w)
        pressed = enabled && w.pressed === true
        state = enabled ? nothing : :disabled
        label = _get_state_text(p, w, :label; state)
        # The rect of the border: the box without its margin.
        margin_left, margin_top, margin_right, margin_bottom = box.margin
        border_box_width = button_width - margin_left - margin_right
        border_box_height = button_height - margin_top - margin_bottom
        elements = Any[]
        # Default button: light surface, subtle border, soft shadow, dark label —
        # matching the shadcn default button. A faint offset rect approximates the
        # shadow-sm drop shadow; it is dropped while pressed (so the button "sinks")
        # and while disabled (so it reads as inert/flat).
        if enabled && !pressed
            _push_panel!(elements, margin_left, margin_top + p.shadow_offset, border_box_width,
                         border_box_height; fill = p.shadow_color, radius = corner_radius)
        end
        _push_box_parts!(elements, box, _get_box_colors(p, w; state), inner_width, inner_height;
                         radius = corner_radius)
        enabled && _push_hover_layer!(elements, w, margin_left, margin_top, border_box_width, border_box_height;
                                      hovered_color = p.layer_hovered_color,
                                      pressed_color = p.layer_pressed_color, radius = corner_radius)
        # Lay out icon + label as one centered group; the icon tints to the label color
        # (so it mutes with the button), the label sits to its right.
        start_x = content_x + (inner_width - full_w) ÷ 2
        cy = content_y + (inner_height - content_height) ÷ 2
        if icon_w > 0
            _push_icon!(elements, icon, start_x, content_y + (inner_height - icon_sz) ÷ 2, icon_sz, label.color)
        end
        _push_content!(elements, p.measure, label, label_content, start_x + icon_w + icon_gap, cy, content_width,
                       content_height; placeholder_color = p.placeholder_color)
        _push_focus_ring!(elements, w, button_width, button_height, p.focus_ring_stroke, corner_radius)
        # A press on a button that acts runs its action.
        enabled && push!(elements, GraphicsPointerShape(0, 0, button_width, button_height, :pointing_hand))
        (width=button_width, height=button_height, elements=elements)
    end))
end

map_reference_forward(::WidgetButtonToGraphicsCanvas, iomap, reference) = _map_child_forward(iomap, reference)

function map_reference_backward(::WidgetButtonToGraphicsCanvas, iomap, reference)
    return nothing
end

# The button owns the transitions of its `pressed` state. A click invokes the
# action; press/release drive the held-down look. A move of the pointer also reaches the button when the
# pointer leaves it; every other pointer event reaches it only when the parent
# hit-tested the pointer onto it.
function read_intent(::WidgetButtonToGraphicsCanvas, iomap::SimpleIoMap, evt)
    w = iomap.input
    # A move off the button reaches it only while it is the part under the pointer,
    # so the pointer left it: a press that was released off the button ends here.
    if evt isa MouseMove && _outside_widget(iomap, evt)
        return w.pressed === true ? _write_view_state(w, "pressed", false) : nothing
    end
    _outside_widget(iomap, evt) && return nothing
    # A disabled button (or one bound to a disabled command) is inert: no action,
    # and no hover/press state changes, so it can never show an interaction surface
    # (see the printer's enabled branch).
    _button_enabled(w) || return nothing
    # Per-instance gestures are consulted first, so a binding can add a gesture
    # (right-click, shift-click, …), override a built-in (same pattern shadows it),
    # or suppress one (map the pattern to `DoNothingOperation()`). An empty table returns
    # `nothing` immediately, so a plain button behaves exactly as before.
    op = read_bound_gesture(w, evt)
    op === nothing || return op
    @gesture_case evt begin
        MouseClick(button, x, y) => button === :left ? _button_primary_op(w) : nothing
        MouseDown(button, x, y)  => button === :left ? _write_view_state(w, "pressed", true) : nothing
        MouseUp(button, x, y)    => button === :left ? _write_view_state(w, "pressed", false) : nothing
        # Enter / Space with no modifier activate the focused button (key reaches
        # it via selection routing). `:tab` is intentionally not matched, so it
        # falls through to `nothing` and focus traversal can claim it.
        when(KeyDown(k), _is_plain_key(evt, :return, :space)) => _button_primary_op(w)
        _ => nothing
    end
end

# The button's *primary* gesture (the built-in default that left-click / Enter /
# Space map to): invoke its bound `command` (Stage 4) if it has one; else open its
# `dialog` as a modal window (Step 5); else run its plain `action`. This is just
# the default primary op — it is not privileged; any gesture (double/right/shift-
# click, …) is expressed as its own per-instance binding. A modal dialog is
# centered, not placed under a widget, so it opens directly as an
# `OpenWindowOperation`. v1 uses a generous fixed window box; true screen-sizing /
# centering is deferred (see widget.md).
# A command that does something wins; the dialog is the fallback for one that
# does not, so a button carrying both a callback and a dialog runs the callback.
function _button_primary_op(w::WidgetButton)
    command = _button_action(w)
    command.callback === nothing || return InvokeActionOperation(command)
    dlg = w.dialog
    dlg === nothing && return InvokeActionOperation(command)
    OpenWindowOperation(; id=dlg.popup_id, modal=true, style=:dialog,
                        x=80, y=60, width=480, height=320, content=dlg)
end

# ── WidgetTooltip ───────────────────────────────────────────────────────────

# The range of the content of an overlay, a tooltip or a context menu: the edge of
# its range less its insets, and never a slot, because an overlay is as large as
# its content (§3 of layout-rules.md). A content in a slot would stretch to the
# whole window, and the overlay with it.
function _get_overlay_content_context(p, w::WidgetDocument, ctx)
    ctx === nothing && return nothing
    inner = _get_inner_content_context(p, w, ctx)
    with_bounded_size(inner; width = inner.maximum_width, height = inner.maximum_height)
end

function print_document(p::WidgetTooltipToGraphicsCanvas, recursion, w::WidgetTooltip, ctx)
    w.visible == false && return ChildrenIoMap(p, w, _empty_canvas(), Cell(Any[]))
    pos = w.position::Point2D
    # The child is reconciled and forced only in the WidgetDocument branch.
    content_ctx = _get_overlay_content_context(p, w, ctx)
    child_iomap = make_reconciled_child_iomap_cell(() -> w.content, c -> print_child(recursion, c, content_ctx))
    build = Cell(@computation begin
        # The padding of the projection keeps the box off the text, unless the
        # document gives a padding of its own.
        cox, coy = _content_offset(p, w)
        txp, typ = _inset_total(p, w)
        label = _get_part_text(w, :label_text, p.label_text)
        child_iomaps = Any[]
        content = w.content
        elems = Any[]
        # Size the box to its content (at least the requested size).
        cw, ch = 0, 0
        body = Any[]
        if content isa AbstractString
            cw, ch = _text_size(p.measure, label.font, content)
            _push_text!(body, p.measure, label.font, content, cox, coy, label.color)
        elseif content isa WidgetDocument
            cim = child_iomap[]
            inner = cim.output
            cw, ch = inner isa GraphicsCanvas ? (Int(inner.w[]), Int(inner.h[])) : (0, 0)
            push!(child_iomaps, (cox, coy, cim))
            push!(body, _make_canvas(cox, coy, Any[inner]))
        end
        # The size the caller asked for is a floor, its content is the other floor,
        # and the window is the ceiling.
        sz = w.size
        vw = _resolve_overlay(ctx, :x, sz isa Point2D ? Int(sz.x[]) : 0, cw + txp)
        vh = _resolve_overlay(ctx, :y, sz isa Point2D ? Int(sz.y[]) : 0, ch + typ)
        _push_box_parts!(elems, _get_box_insets(p, w), _get_box_colors(p, w), vw - txp, vh - typ;
                         radius = p.corner_radius)
        append!(elems, body)
        (width=vw, height=vh, elements=elems, child_iomaps=child_iomaps)
    end)
    ChildrenIoMap(p, w, _reactive_canvas_cell(_origin(pos)..., build), Cell(@computation build[].child_iomaps))
end

map_reference_forward(::WidgetTooltipToGraphicsCanvas, iomap, reference) = _map_child_forward(iomap, reference)

map_reference_backward(::WidgetTooltipToGraphicsCanvas, iomap, reference) =
    _map_child_point(iomap, reference)

function read_intent(::WidgetTooltipToGraphicsCanvas, iomap::ChildrenIoMap, evt)
    evt isa MouseMove && return _read_children_move(iomap, evt)
    _outside_widget(iomap, evt) && return nothing
    child_iomaps = getfield(iomap, :child_iomaps)[]::Vector
    evt isa MouseDwell && return _read_children_outward(iomap.input, child_iomaps, evt)
    evt isa MouseScroll || return nothing
    _route_scroll_to_children(child_iomaps, evt)
end

# ── WidgetContextMenu ─────────────────────────────────────────────────────────

@projection UntrackedCell struct WidgetContextMenuToGraphicsCanvas
    measure::TextMeasure
    margin::Inset
    border::Inset
    padding::Inset
    margin_color::StyleColor
    border_color::StyleColor
    padding_color::StyleColor
    content_color::StyleColor
end

WidgetContextMenuToGraphicsCanvas(theme; measure,
                                  margin = inset_default, border = inset_default, padding = inset_default,
                                  margin_color = color_transparent, border_color = color_transparent,
                                  padding_color = color_transparent, content_color = color_transparent) =
    WidgetContextMenuToGraphicsCanvas(measure, margin, border, padding, margin_color, border_color,
                                      padding_color, content_color)

# Carries the recursed child's iomap (for event routing + re-rooting).
# @iomap so the reader reads child_iomap transparently; the child is reconciled
# so a content swap rebuilds it (PAR-STABLE-IOMAP-IDENTITY).
@iomap struct WidgetContextMenuToGraphicsCanvasIoMap
    projection::Any
    input::Any
    output::Any
    child_iomap::Any
end

# What a route reaches through this container: see `_collect_child_iomaps`.
ProjectionModule.get_child_iomaps(iomap::WidgetContextMenuToGraphicsCanvasIoMap) =
    _collect_child_iomaps(iomap.child_iomap)

function print_document(p::WidgetContextMenuToGraphicsCanvas, recursion, w::WidgetContextMenu, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    w.child isa Document || return SimpleIoMap(p, w, _empty_canvas())
    child_ctx = _get_overlay_content_context(p, w, ctx)
    child_iomap = make_reconciled_child_iomap_cell(() -> w.child, c -> print_child(recursion, c, child_ctx))
    build = Cell(@computation begin
        content_x, content_y = _content_offset(p, w)
        inner = child_iomap[].output::GraphicsCanvas
        iw, ih = Int(inner.w[]), Int(inner.h[])
        inset_width, inset_height = _inset_total(p, w)
        # An overlay: content-sized, and capped by the window rather than stretched
        # to it, so a menu opened near an edge does not run past it.
        width = _resolve_overlay(ctx, :x, 0, iw + inset_width)
        height = _resolve_overlay(ctx, :y, 0, ih + inset_height)
        # The menu stands where its child stands, as a `LayoutConstraint` does: its
        # canvas takes the origin of the child's canvas, and the child draws inside
        # the box at the content offset, so the box covers the child wherever the
        # child is placed.
        x, y = Int(inner.x), Int(inner.y)
        elements = Any[]
        _push_box_parts!(elements, _get_box_insets(p, w), _get_box_colors(p, w),
                         max(0, width - inset_width), max(0, height - inset_height))
        push!(elements, _make_canvas(content_x - x, content_y - y, Any[inner]))
        (x = x, y = y, width = width, height = height, elements = elements)
    end)
    canvas = GraphicsCanvas(Cell(@computation Int32(build[].x)), Cell(@computation Int32(build[].y)),
                            Cell(@computation Int32(build[].width)),
                            Cell(@computation Int32(build[].height)),
                            CellVector(@computation build[].elements),
                            layout_none, true, Cell(nothing))
    WidgetContextMenuToGraphicsCanvasIoMap(p, w, canvas, child_iomap)
end

map_reference_forward(::WidgetContextMenuToGraphicsCanvas, iomap::WidgetContextMenuToGraphicsCanvasIoMap, reference) = _map_child_forward(iomap, reference)
map_reference_forward(::WidgetContextMenuToGraphicsCanvas, iomap, reference) = _map_child_forward(iomap, reference)

# Child ops re-root by prepending `.child`.
# A point maps into the child, in the child's frame, where the child drew
# something; any other reference of the child goes under `child`.
function map_reference_backward(p::WidgetContextMenuToGraphicsCanvas, iomap::WidgetContextMenuToGraphicsCanvasIoMap, reference)
    reference === nothing && return nothing
    point = find_reference_point(reference)
    point === nothing && return ConcreteReference(FieldReferenceStep("child"), reference)
    child_iomap = iomap.child_iomap
    child_iomap === nothing && return nothing
    dx, dy = _get_context_menu_child_offset(p, iomap)
    canvas = child_iomap.output
    lx, ly = point.x - dx, point.y - dy
    canvas isa GraphicsCanvas && hit_element_at(canvas, lx, ly) !== nothing || return nothing
    answer = map_reference_backward(child_iomap.projection, child_iomap, PointReferenceStep(lx, ly))
    annotate_reference_types(iomap.input, ConcreteReference(FieldReferenceStep("child"),
                                                            answer === nothing ? EmptyReference() : answer))
end
map_reference_backward(::WidgetContextMenuToGraphicsCanvas, iomap, reference) = nothing

read_intent(::WidgetContextMenuToGraphicsCanvas, iomap::SimpleIoMap, evt) = nothing

# Every event routes to the child: its answer is re-rooted through `.child`, and a
# popup the child opens is moved out of the content offset. A dwell and a right
# click go to the child where it drew something at the point, and the wrapper then
# reads its own stretch, so its gesture table adds its menu to a right click
# (`make_context_menu_binding`), after the menu of a nearer part.
function read_intent(p::WidgetContextMenuToGraphicsCanvas, iomap::WidgetContextMenuToGraphicsCanvasIoMap, evt)
    evt isa MouseMove && return _read_context_menu_move(p, iomap, evt)
    _outside_widget(iomap, evt) && return nothing
    w = iomap.input
    child_iomap = iomap.child_iomap
    child_iomap === nothing && return nothing
    is_outward_gesture(evt) &&
        return _read_children_outward(w, Any[_get_context_menu_child_entry(p, iomap)], evt)
    dx, dy = _get_context_menu_child_offset(p, iomap)
    op = @gesture_case evt begin
        MouseClick => shift_operation_position(
            read_intent(child_iomap.projection, child_iomap, shift_event_position(evt, -dx, -dy)), dx, dy)
        MouseScroll => read_intent(child_iomap.projection, child_iomap, shift_event_position(evt, -dx, -dy))
        _ => read_intent(child_iomap.projection, child_iomap, evt)
    end
    _retarget_op(p, iomap, op)
end

function _read_context_menu_move(p::WidgetContextMenuToGraphicsCanvas,
                                 iomap::WidgetContextMenuToGraphicsCanvasIoMap, evt::MouseMove)
    child_iomap = iomap.child_iomap
    child_iomap === nothing && return nothing
    dx, dy = _get_context_menu_child_offset(p, iomap)
    canvas = child_iomap.output
    on_child = !_outside_widget(iomap, evt) && canvas isa GraphicsCanvas &&
               hit_element_at(canvas, evt.x - dx, evt.y - dy) !== nothing
    _retarget_op(p, iomap,
                 _read_single_child_move(iomap.input, "child", child_iomap, evt, dx, dy, on_child))
end

# Where the frame of the child of a context menu stands in the menu's frame: at the
# content offset, because the menu stands where its child stands.
_get_context_menu_child_offset(p, iomap::WidgetContextMenuToGraphicsCanvasIoMap) =
    _content_offset(p, iomap.input)

# The child as an entry of the routing helpers, which take the place of the child's
# own canvas off a point: the offset of the wrapper canvas, the content offset less
# the origin of the child's canvas.
function _get_context_menu_child_entry(p, iomap::WidgetContextMenuToGraphicsCanvasIoMap)
    cox, coy = _content_offset(p, iomap.input)
    canvas = iomap.child_iomap.output
    canvas isa GraphicsCanvas || return (cox, coy, iomap.child_iomap)
    (cox - Int(canvas.x), coy - Int(canvas.y), iomap.child_iomap)
end

# ── WidgetDialog ──────────────────────────────────────────────────────────────

@projection UntrackedCell struct WidgetDialogToGraphicsCanvas
    measure::TextMeasure
    margin::Inset                          # space around the card
    border::Inset
    padding::Inset
    margin_color::StyleColor
    border_color::StyleColor
    padding_color::StyleColor
    content_color::StyleColor
    title_text::StyleText
    body_text::StyleText    # content/label fallback font + color
    scrim_color::StyleColor
    gap::Int                               # vertical gap between title / content / buttons
    corner_radius::Int
end

WidgetDialogToGraphicsCanvas(theme; measure,
                             margin = inset_default,
                             border = _themed(Inset, theme, t -> _make_uniform_inset(t.border_width)),
                             padding = _themed(Inset, theme, t -> t.control_padding),
                             margin_color = color_transparent,
                             border_color = _themed(StyleColor, theme, t -> t.border),
                             padding_color = _themed(StyleColor, theme, t -> t.card),
                             content_color = _themed(StyleColor, theme, t -> t.card),
                             title_text = _themed(StyleText, theme, _get_title_text),
                             body_text = _themed(StyleText, theme, _get_body_text),
                             scrim_color = _themed(StyleColor, theme, t -> t.scrim),
                             gap = _themed(Int, theme, t -> t.item_gap),
                             corner_radius = _themed(Int, theme, t -> t.radius)) =
    WidgetDialogToGraphicsCanvas(measure, margin, border, padding, margin_color, border_color,
                                 padding_color, content_color, title_text, body_text, scrim_color,
                                 gap, corner_radius)

# Carries the centered card's bounds (for the backdrop hit-test) plus the content
# and button child-iomaps (for routing + re-rooting), all in dialog-canvas coords.
@iomap struct WidgetDialogToGraphicsCanvasIoMap
    projection::Any
    input::WidgetDialog
    output::GraphicsCanvas
    card::NTuple{4,Int}      # (x, y, w, h)
    content_entry::Any       # (ox, oy, cim) | nothing
    button_entries::Cell     # Vector of (ox, oy, cim)
end

# What a route reaches through this container: see `_collect_child_iomaps`.
ProjectionModule.get_child_iomaps(iomap::WidgetDialogToGraphicsCanvasIoMap) =
    _collect_child_iomaps(iomap.content_entry, iomap.button_entries...)

function print_document(p::WidgetDialogToGraphicsCanvas, recursion, w::WidgetDialog, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    box = _get_box_insets(p, w)
    colors = _get_box_colors(p, w)
    margin_left, margin_top, _margin_right, _margin_bottom = box.margin
    border_left, border_top, border_right, border_bottom = box.border
    padding_left, padding_top, padding_right, padding_bottom = box.padding
    gap = p.gap; radius = p.corner_radius
    # The dialog fills its (modal) window; the scrim covers that whole area.
    aw = ctx === nothing ? nothing : get_exact_width(ctx)
    ah = ctx === nothing ? nothing : get_exact_height(ctx)
    avail_w = aw !== nothing ? max(0, Int(aw[])) : 480
    avail_h = ah !== nothing ? max(0, Int(ah[])) : 320

    title_text = _get_part_text(w, :title_text, p.title_text)
    body_text = _get_part_text(w, :body_text, p.body_text)
    title = string(w.title)
    title_w, title_h = _text_size(p.measure, title_text.font, title)

    # The card takes its size from what it holds, so it gives no slot: each part
    # gets the edge of the window less the margin, the border and the padding
    # around it (§3 of layout-rules.md).
    inset_width, inset_height = _inset_total(p, w)
    edge_w = max(0, avail_w - inset_width)
    edge_h = max(0, avail_h - inset_height - title_h)

    # Buttons laid out in a row, which offers no width.
    button_ctx = ctx === nothing ? nothing :
                 with_bounded_size(with_free_axis(ctx, :x); height = Cell(Int32(edge_h)))
    button_iomaps = Any[]
    btn_w = 0; btn_h = 0
    for b in w.buttons
        b isa WidgetDocument || continue
        bim = print_child(recursion, b, button_ctx)
        bc = bim.output
        bw, bh = bc isa GraphicsCanvas ? (Int(bc.w[]), Int(bc.h[])) : (0, 0)
        push!(button_iomaps, (bim, bw, bh))
        btn_w += bw; btn_h = max(btn_h, bh)
    end
    nbtn = length(button_iomaps)
    nbtn > 1 && (btn_w += (nbtn - 1) * gap)

    # Content: a recursed child widget, a plain string, or nothing. It stands
    # between the title and the row of buttons, a gap from each.
    content = w.content
    content_iomap = nothing; content_w = 0; content_h = 0
    if content isa Document
        content_edge_h = max(0, edge_h - gap - (nbtn > 0 ? gap + btn_h : 0))
        content_ctx = ctx === nothing ? nothing :
                      with_bounded_size(ctx; width = Cell(Int32(edge_w)),
                                        height = Cell(Int32(content_edge_h)))
        content_iomap = print_child(recursion, content, content_ctx)
        cc = content_iomap.output
        content_w, content_h = cc isa GraphicsCanvas ? (Int(cc.w[]), Int(cc.h[])) : (0, 0)
    elseif content !== nothing
        content_w, content_h = _text_size(p.measure, body_text.font, string(content))
    end

    has_content = content_w > 0 || content_h > 0
    has_buttons = nbtn > 0
    inner_w = max(title_w, content_w, btn_w)
    inner_h = title_h
    has_content && (inner_h += gap + content_h)
    has_buttons && (inner_h += gap + btn_h)
    # The card is the border box: the border and the padding around the content.
    # The margin goes around the card.
    card_w = border_left + padding_left + inner_w + padding_right + border_right
    card_h = border_top + padding_top + inner_h + padding_bottom + border_bottom
    card_x = max(0, (avail_w - card_w) ÷ 2); card_y = max(0, (avail_h - card_h) ÷ 2)

    elements = Any[]
    _push_panel!(elements, 0, 0, avail_w, avail_h; fill = p.scrim_color)
    box_elements = Any[]
    _push_box_parts!(box_elements, box, colors, inner_w, inner_h; radius)
    push!(elements, _make_canvas(card_x - margin_left, card_y - margin_top, box_elements))
    tx = card_x + border_left + padding_left; ty = card_y + border_top + padding_top
    _push_text!(elements, p.measure, title_text.font, title, tx, ty, title_text.color)
    cursor_y = ty + title_h

    content_entry = nothing
    if has_content
        cursor_y += gap
        if content_iomap !== nothing
            ox = tx; oy = cursor_y
            push!(elements, _make_canvas(ox, oy, Any[content_iomap.output]))
            content_entry = (ox, oy, content_iomap)
        else
            _push_text!(elements, p.measure, body_text.font, string(content), tx, cursor_y, body_text.color)
        end
        cursor_y += content_h
    end

    button_entries = Any[]
    if has_buttons
        cursor_y += gap
        bx = tx + max(0, inner_w - btn_w)   # right-align the row
        for (bim, bw, _bh) in button_iomaps
            push!(elements, _make_canvas(bx, cursor_y, Any[bim.output]))
            push!(button_entries, (bx, cursor_y, bim))
            bx += bw + gap
        end
    end

    canvas = _make_canvas(0, 0, avail_w, avail_h, elements)
    WidgetDialogToGraphicsCanvasIoMap(p, w, canvas, (card_x, card_y, card_w, card_h),
                                      content_entry, Cell(button_entries))
end

map_reference_forward(::WidgetDialogToGraphicsCanvas, iomap, reference) = _map_child_forward(iomap, reference)
# Content ops (e.g. an editable WidgetText field) re-root by prepending `.content`.
function map_reference_backward(::WidgetDialogToGraphicsCanvas, iomap::WidgetDialogToGraphicsCanvasIoMap, reference)
    reference === nothing && return nothing
    point = find_reference_point(reference)
    point === nothing && return ConcreteReference(FieldReferenceStep("content"), reference)
    entries = Any[iomap.content_entry; iomap.button_entries]
    _map_point_to_child(iomap.input, entries, point)
end
map_reference_backward(::WidgetDialogToGraphicsCanvas, iomap, reference) = nothing

read_intent(::WidgetDialogToGraphicsCanvas, iomap::SimpleIoMap, evt) = nothing

# Esc / a backdrop click (on the scrim, outside the card) dismiss; a button click
# runs its action AND closes (one CompoundOperation); a click inside the card on
# the content routes to it (re-rooted through `.content`). A dwell goes to the
# button or the content at its point, where it runs no action and closes nothing.
function read_intent(p::WidgetDialogToGraphicsCanvas, iomap::WidgetDialogToGraphicsCanvasIoMap, evt)
    evt isa MouseMove &&
        return _read_children_move(iomap.input, _get_dialog_entries(iomap), evt,
                                   !_outside_widget(iomap, evt))
    _outside_widget(iomap, evt) && return nothing
    pid = iomap.input.popup_id
    if evt isa KeyDown
        return evt.key === :escape ? CloseWindowOperation(pid) : nothing
    end
    evt isa MouseDwell &&
        return _read_children_outward(iomap.input, _get_dialog_entries(iomap), evt)
    evt isa MouseClick || return nothing
    evt.button === :left || return nothing
    (cx, cy, cw, ch) = iomap.card
    (cx <= evt.x < cx + cw && cy <= evt.y < cy + ch) || return CloseWindowOperation(pid)
    bop = _route_click_to_children(iomap.button_entries::Vector, evt)
    bop !== nothing && return CompoundOperation(Any[bop, CloseWindowOperation(pid)])
    ce = iomap.content_entry
    ce === nothing && return nothing
    (ox, oy, cim) = ce
    op = shift_operation_position(read_child_event(cim, MouseClick(evt.button, evt.x - ox, evt.y - oy,
                                                                   evt.count, evt.modifiers; time = evt.time)),
                                  ox, oy)
    _retarget_op(p, iomap, op)
end

# The children of a dialog that the pointer reaches, the buttons and then the
# content, as `(x, y, child_iomap)` entries.
function _get_dialog_entries(iomap::WidgetDialogToGraphicsCanvasIoMap)
    entries = Any[iomap.button_entries::Vector...]
    iomap.content_entry === nothing || push!(entries, iomap.content_entry)
    entries
end

# ── WidgetMenuItem ──────────────────────────────────────────────────────────

# Carries the rendered item size, so a submenu-opener item can open its `submenu`
# as a popup just below itself, in its own frame. `child_iomaps` keeps scroll
# routing into embedded widget content working.
# `natural_width` is the width the item needs, measured without its offer, so a
# dropdown can offer each of its items the width of the widest one.
# @iomap so the reader reads child_iomaps/control_width/control_height
# transparently (all shared from the build cell); PAR-STABLE-IOMAP-IDENTITY.
@iomap struct WidgetMenuItemToGraphicsCanvasIoMap
    projection::Any
    input::Any
    output::Any
    child_iomaps::Any
    natural_width::Any
    control_width::Any
    control_height::Any
end

# What a route reaches through this container: see `_collect_child_iomaps`.
ProjectionModule.get_child_iomaps(iomap::WidgetMenuItemToGraphicsCanvasIoMap) =
    _collect_child_iomaps(iomap.child_iomaps...)

# A bound command (Stage 4) supplies the item's label, enabled-state, and callback,
# so a menu item / toolbar button / shortcut can share one `Action`.
_menu_item_command(w::WidgetMenuItem) = w.action::Action
_menu_item_enabled(w::WidgetMenuItem) =
    !(w.enabled === false) && !(_menu_item_command(w).enabled === false)
_menu_item_icon(w::WidgetMenuItem) = _menu_item_command(w).icon
# The variant of the item: `submenu` for an item that opens a menu, the name of
# the menu on a bar, and `nothing` for a command.
_get_menu_item_variant(w::WidgetMenuItem) = w.submenu === nothing ? nothing : :submenu

function print_document(p::WidgetMenuItemToGraphicsCanvas, recursion, w::WidgetMenuItem, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    # The child (a recursed widget content) is reconciled and forced only in the
    # WidgetDocument branch. It is offered no width, so what the item needs does
    # not depend on what the item is offered.
    child_iomap = make_reconciled_child_iomap_cell(() -> w.action.label,
                                        c -> print_child(recursion, c,
                                                         with_free_axis(ctx, :x)))
    # What the item draws and the extent it needs. It reads the item and never the
    # offer, because a dropdown reads the width each item needs to offer every item
    # the widest.
    measured = Cell(@computation begin
        variant = _get_menu_item_variant(w)
        content_x, content_y = _content_offset(p, w; variant)
        inset_width, inset_height = _inset_total(p, w; variant)
        command = _menu_item_command(w)
        enabled = _menu_item_enabled(w)
        state = enabled ? nothing : :disabled
        label = _get_state_text(p, w, :label; state)
        # A bound command's label overrides the content; otherwise the content is the
        # label (text) or a recursed widget. The label is passed RAW (the
        # WidgetDocument branch below and the text leaf's own string() do the
        # interpreting), so a bound label keeps the same polymorphism as content.
        content = command.label
        child_iomaps = Any[]
        elems = Any[]
        cw, ch = 0, 0
        if content isa WidgetDocument
            cim = child_iomap[]
            inner = cim.output
            cw, ch = inner isa GraphicsCanvas ? (Int(inner.w[]), Int(inner.h[])) : (0, 0)
            push!(child_iomaps, (content_x, content_y, cim))
            push!(elems, _make_canvas(content_x, content_y, Any[inner]))
        else
            text = string(content)
            cw, line = _text_size(p.measure, label.font, text)
            # An optional leading icon, tinted to the item's foreground: a square of
            # one line times `icon_size`. The row is as tall as the larger of the
            # icon and the line, and each is centred in it.
            icon = _menu_item_icon(w)
            icon_w = icon_width(icon, scale_length(line, p.icon_size))
            gap = icon_w > 0 ? p.label_gap : 0
            ch = max(icon_w, line)
            icon_w > 0 && _push_icon!(elems, icon, content_x, content_y + (ch - icon_w) ÷ 2, icon_w, label.color)
            _push_text!(elems, p.measure, label.font, text, content_x + icon_w + gap,
                        content_y + (ch - line) ÷ 2, label.color)
            cw += icon_w + gap
        end
        (width = cw + inset_width, height = ch + inset_height, inset_width, inset_height,
         enabled, elements = elems, child_iomaps, variant)
    end)
    build = Cell(@computation begin
        needed = measured[]
        control_w = _resolve_width(ctx, 0, needed.width)
        control_h = _resolve_height(ctx, 0, needed.height)
        # A clear surface over the whole item: a press or a move anywhere on it
        # hits the item, and not only on its label, also where the padding is.
        final = Any[GraphicsRect(0, 0, control_w, control_h; color = color_transparent, radius = 0)]
        _push_box_parts!(final, _get_box_insets(p, w; needed.variant), _get_box_colors(p, w),
                         control_w - needed.inset_width, control_h - needed.inset_height)
        # The layer of the light of an enabled item, drawn over the box and under
        # the content. It reads the mouse target in cells of its own, so a light
        # changes no extent.
        needed.enabled && _push_hover_layer!(final, w, 0, 0, control_w, control_h;
                                             hovered_color = p.layer_hovered_color)
        append!(final, needed.elements)
        (width=control_w, height=control_h, elements=final, child_iomaps=needed.child_iomaps)
    end)
    # Bound the canvas to the item's own footprint so `hit_element_at` clips pointer
    # events to it. A `GraphicsText` has no right edge, so an auto-sized (w=h=0) item
    # canvas would claim hits anywhere to the right of its label — harmless in a
    # vertical menu (per-item y-bands differ) but in a *horizontal* toolbar / menu
    # bar the leftmost item then swallows every move, and the first button lights
    # for each. See `hit_element_at` in document/Graphics.jl.
    WidgetMenuItemToGraphicsCanvasIoMap(p, w, _reactive_canvas_cell(0, 0, build),
                                        Cell(@computation build[].child_iomaps),
                                        Cell(@computation measured[].width),
                                        Cell(@computation build[].width), Cell(@computation build[].height))
end

map_reference_forward(::WidgetMenuItemToGraphicsCanvas, iomap::WidgetMenuItemToGraphicsCanvasIoMap, reference) = _map_child_forward(iomap, reference)
map_reference_forward(::WidgetMenuItemToGraphicsCanvas, iomap::SimpleIoMap, reference) = _map_child_forward(iomap, reference)
function map_reference_backward(::WidgetMenuItemToGraphicsCanvas, iomap, reference)
    point = find_reference_point(reference)
    (point === nothing || !(iomap isa WidgetMenuItemToGraphicsCanvasIoMap)) && return nothing
    _map_point_to_child(iomap.input, iomap.child_iomaps, point)
end

# Invisible item (printer returned a bare empty canvas): inert.
read_intent(::WidgetMenuItemToGraphicsCanvas, ::SimpleIoMap, evt) = nothing

function read_intent(p::WidgetMenuItemToGraphicsCanvas, iomap::WidgetMenuItemToGraphicsCanvasIoMap, evt)
    _outside_widget(iomap, evt) && return nothing
    w = iomap.input
    # Per-instance gestures win over the built-in click/submenu handling (an enabled
    # item only, matching the built-in gate).
    if _menu_item_enabled(w)
        op = read_bound_gesture(w, evt)
        op === nothing || return op
    end
    if evt isa MouseClick
        # A left click on an enabled item: open its submenu if it has one, else
        # invoke its bound command (Stage 4) or its plain action, and dismiss the
        # enclosing popup (a no-op when rendered inline). Disabled (item or bound
        # command) ⇒ inert.
        (evt.button === :left && _menu_item_enabled(w)) || return nothing
        submenu = w.submenu
        submenu === nothing || return _open_submenu_popup(p, submenu, iomap)
        # The subtree wins over the callback here (unlike a button's dialog):
        # a menu-bar entry that opens a submenu is what the item IS. An item
        # with an operation edits the part that its context menu belongs to.
        command = _menu_item_command(w)
        operation = w.operation
        chosen = operation === nothing ? InvokeActionOperation(command) :
                 EditMenuPartOperation(operation, string(command.label))
        return CompoundOperation(Any[chosen, CloseWindowOperation(:widget_popup)])
    end
    # A dwell goes to the content at its point, and invokes nothing.
    evt isa MouseDwell &&
        return _read_children_outward(w, getfield(iomap, :child_iomaps)[]::Vector, evt)
    evt isa MouseScroll || return nothing
    _route_scroll_to_children(getfield(iomap, :child_iomaps)[]::Vector, evt)
end

# Open the item's `submenu` as a popup just below the item: a position in
# the item's own frame, which each reader above moves into its own frame, as the
# `WidgetSelect` dropdown does. The popup window takes the extent of what the
# submenu draws; placement beyond "below" is left to anchored-layout.md.
function _open_submenu_popup(p::WidgetMenuItemToGraphicsCanvas, submenu, iomap::WidgetMenuItemToGraphicsCanvasIoMap)
    ReplaceViewStateOperation(
        OpenPopupOperation(; id=:widget_popup, x=0, y=iomap.control_height + p.popup_gap,
                           auto_dismiss=true, content=submenu))
end

# ── WidgetToolbarItem ───────────────────────────────────────────────────────

_toolbar_item_command(w::WidgetToolbarItem) = w.action::Action
_toolbar_item_enabled(w::WidgetToolbarItem) =
    !(w.enabled === false) && !(_toolbar_item_command(w).enabled === false)

# The icon alone when the action has one, as tall as a line of the font; the
# label only when there is no icon to show. The canvas is as large as what it
# shows and its padding, so a move in a toolbar lands on the item under the
# pointer and not on its left neighbour.
function print_document(p::WidgetToolbarItemToGraphicsCanvas, recursion, w::WidgetToolbarItem, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    SimpleIoMap(p, w, _reactive_canvas(0, 0, () -> begin
        cox, coy = _content_offset(p, w)
        inset_width, inset_height = _inset_total(p, w)
        command = _toolbar_item_command(w)
        enabled = _toolbar_item_enabled(w)
        state = enabled ? nothing : :disabled
        label = _get_state_text(p, w, :label; state)
        _, line = _text_size(p.measure, label.font, "M")
        icon_size = icon_width(command.icon, scale_length(line, p.icon_size))
        elements = Any[]
        if icon_size > 0
            _push_icon!(elements, command.icon, cox, coy, icon_size, label.color)
            content_width, content_height = icon_size, icon_size
        else
            text = string(command.label)
            content_width, content_height = _text_size(p.measure, label.font, text)
            _push_text!(elements, p.measure, label.font, text, cox, coy, label.color)
        end
        # As large as what it shows, on both axes. A band can offer the height of
        # the window, and an item that took it would take every press below it.
        width = content_width + inset_width
        height = content_height + inset_height
        # A clear surface over the whole button: a press anywhere on it hits the
        # item, and not only on the strokes of its picture.
        drawn = Any[GraphicsRect(0, 0, width, height; color = color_transparent, radius = 0)]
        _push_box_parts!(drawn, _get_box_insets(p, w), _get_box_colors(p, w; state),
                         content_width, content_height; radius = p.corner_radius)
        # Flat at rest; under the pointer the layer draws the surface and the
        # outline of a button, and a darker surface while it is held.
        enabled && _push_hover_layer!(drawn, w, 0, 0, width, height; hovered_color = p.layer_hovered_color,
                                      pressed_color = p.layer_pressed_color,
                                      stroke = p.layer_stroke, radius = p.corner_radius)
        append!(drawn, elements)
        (width = width, height = height, elements = drawn)
    end))
end

map_reference_forward(::WidgetToolbarItemToGraphicsCanvas, iomap, reference) = _map_child_forward(iomap, reference)
map_reference_backward(::WidgetToolbarItemToGraphicsCanvas, iomap, reference) = nothing

# A left press on an enabled item invokes its action. The item's own gestures come
# first, as on a button.
#
# A left down and up on an enabled item write its transient `pressed`, as on a
# button. The down is the answer of the item, so it does not move the focus.
#
# Alt and a left press select the item as a whole, as they select any widget, so
# the item declines that press and the layers above select it.
function read_intent(::WidgetToolbarItemToGraphicsCanvas, iomap::SimpleIoMap, evt)
    w = iomap.input
    w.visible == false && return nothing
    # A move off the item reaches it only while it is the part under the pointer,
    # so the pointer left it: a press that was released off the item ends here.
    if evt isa MouseMove && _outside_widget(iomap, evt)
        return w.pressed === true ? _write_view_state(w, "pressed", false) : nothing
    end
    _outside_widget(iomap, evt) && return nothing
    is_whole_selection_press(evt) && return nothing
    enabled = _toolbar_item_enabled(w)
    enabled || return nothing
    operation = read_bound_gesture(w, evt)
    operation === nothing || return operation
    @gesture_case evt begin
        MouseClick(button, x, y) =>
            button === :left ? InvokeActionOperation(_toolbar_item_command(w)) : nothing
        MouseDown(button, x, y) => button === :left ? _write_view_state(w, "pressed", true) : nothing
        MouseUp(button, x, y)   => button === :left ? _write_view_state(w, "pressed", false) : nothing
        _ => nothing
    end
end

# ── WidgetMenu ──────────────────────────────────────────────────────────────

# What a menu offers an item. A menu bar is as wide as its items together, so it
# offers them no width and each takes its label's (`layout-rules.md` §3). A
# dropdown is as tall as its items together, so it offers them no height: an
# item draws at least what it is offered, and one offered the height of the
# window would push the others out of it. Each `WidgetMenuItem` of a dropdown is
# offered `row_width`, the width of the widest item, which is what makes a row's
# highlight span the menu; any other widget in it keeps its own width.
function _menu_item_context(w::WidgetMenu, ctx, item, row_width)
    w.orientation === :horizontal && return with_free_axis(ctx, :x)
    column = with_free_axis(ctx, :y)
    item isa WidgetMenuItem ? with_exact_size(column; width = row_width) :
                              with_free_axis(column, :x)
end

# The width of a row of a dropdown: what its widest element needs. An item says
# what it needs without its offer, and any other widget is offered no width. The
# drawn width of an item is never read here, because it depends on this width: an
# item whose IO map a host wraps beyond reach counts nothing, and it still draws
# at least what it needs.
function _menu_row_width(child_iomaps)
    width = 0
    for cim in child_iomaps
        cim === nothing && continue
        if cim.input isa WidgetMenuItem
            item = _find_menu_item_iomap(cim)
            item === nothing || (width = max(width, Int(item.natural_width)))
        else
            width = max(width, _menu_item_width(cim))
        end
    end
    width
end

# The IO map of a menu item below the transparent wrappers of a host, such as a
# reference dispatch, which keep the IO map that they wrap in `inner_iomap`.
function _find_menu_item_iomap(iomap)
    iomap = get_content_iomap(iomap)
    while !(iomap isa WidgetMenuItemToGraphicsCanvasIoMap)
        hasproperty(iomap, :inner_iomap) || return nothing
        iomap = get_content_iomap(iomap.inner_iomap)
    end
    iomap
end

# A laid-out item's advance along the main axis. A `WidgetMenuItem` knows its own
# rendered width (its canvas is 0-sized — the size lives on the iomap); any other
# widget carries it on its output canvas.
function _menu_item_width(cim)
    content = get_content_iomap(cim)
    content isa WidgetMenuItemToGraphicsCanvasIoMap ? content.control_width :
        (cim.output isa GraphicsCanvas ? Int(cim.output.w[]) : 0)
end

# The same item's extent across the main axis, so a padded item takes its whole
# row and the next row starts below it.
function _menu_item_height(cim)
    content = get_content_iomap(cim)
    content isa WidgetMenuItemToGraphicsCanvasIoMap ? content.control_height :
        (cim.output isa GraphicsCanvas ? Int(cim.output.h[]) : 0)
end

# The extent that a bar reaches: its box, `box_width` by `box_height`, and each
# item of `child_iomaps` at its place. The box is the insets of the bar around its
# content, also where the box has no color and draws nothing, so the bar keeps
# its padding on every side. A menu item and a toolbar item draw inside the size
# they state, so the bar takes that size, and a parent that asks the size of the
# bar reads no graphic inside such an item, such as the layer that a hover
# changes: a hover does not move what lies under the bar. Any other item is
# measured, because it can draw outside its size, as the shadow of a button does.
function _compute_bar_extent(box_width::Int, box_height::Int, child_iomaps::Vector, measure)
    width, height = box_width, box_height
    for (x, y, cim) in child_iomaps
        item_width, item_height =
            get_iomap_input(cim) isa Union{WidgetMenuItem,WidgetToolbarItem} ?
                (_menu_item_width(cim), _menu_item_height(cim)) :
            cim.output isa GraphicsDocument ? _element_size(cim.output, measure) : (0, 0)
        width = max(width, x + item_width)
        height = max(height, y + item_height)
    end
    (width, height)
end

function print_document(p::WidgetMenuToGraphicsCanvas, recursion, w::WidgetMenu, ctx)
    w.visible == false && return ChildrenIoMap(p, w, _empty_canvas(), Cell(Any[]))
    # Reconcile every element by identity, keeping the ORIGINAL index so the
    # context of an item names `…elements[i]` and its forward image maps back to
    # graphics coordinates (Step 4c). Non-widget slots reconcile to `nothing` and
    # are skipped when laying out.
    #
    # The row width of a dropdown is read from its items once they exist, so it
    # is a forward cell that the items read and that is installed below.
    row_width = Cell(nothing)
    child_cells = make_reconciled_child_iomaps_cell(
        () -> w.elements,
        (i, item) -> item isa WidgetDocument ?
            print_child(recursion, item,
                make_child_context(_menu_item_context(w, ctx, item, row_width),
                                   FieldReferenceStep("elements"), RangeReferenceStep(i - 1, i))) :
            nothing)
    w.orientation === :horizontal ||
        set_cell_computation!(row_width, () -> _menu_row_width(child_cells[]))
    build = Cell(@computation begin
        variant = w.orientation
        content_x, content_y = _content_offset(p, w; variant)
        horizontal = w.orientation === :horizontal
        _, item_h = _text_size(p.measure, p.font, "M")
        item_gap = horizontal ? p.bar_gap : 0
        child_iomaps = Any[]
        items = Any[]
        x_cursor = 0
        y_cursor = 0
        item_w = 0
        row_h = item_h
        for cim in child_cells[]
            cim === nothing && continue
            push!(child_iomaps, (content_x + x_cursor, content_y + y_cursor, cim))
            push!(items, _make_canvas(content_x + x_cursor, content_y + y_cursor, Any[cim.output]))
            if horizontal
                x_cursor += _menu_item_width(cim) + item_gap
                row_h = max(row_h, _menu_item_height(cim))
            else
                item_w = max(item_w, _menu_item_width(cim))
                y_cursor += max(item_h, _menu_item_height(cim))
            end
        end
        content_width = horizontal ? max(0, x_cursor - item_gap) : item_w
        content_height = horizontal ? row_h : y_cursor
        elems = Any[]
        _push_box_parts!(elems, _get_box_insets(p, w; variant), _get_box_colors(p, w; variant),
                         content_width, content_height)
        inset_width, inset_height = _inset_total(p, w; variant)
        width, height = _compute_bar_extent(inset_width + content_width, inset_height + content_height,
                                            child_iomaps, _p_measure(p))
        append!(elems, items)
        # A menu is an overlay: capped by the window, never stretched to it.
        (width = _resolve_overlay(ctx, :x, 0, width), height = _resolve_overlay(ctx, :y, 0, height),
         elements = elems, child_iomaps = child_iomaps)
    end)
    ChildrenIoMap(p, w, _reactive_canvas_cell(0, 0, build), Cell(@computation build[].child_iomaps))
end

map_reference_forward(::WidgetMenuToGraphicsCanvas, iomap::ChildrenIoMap, reference) = _map_child_forward(iomap, reference)

map_reference_backward(::WidgetMenuToGraphicsCanvas, iomap, reference) =
    _map_child_point(iomap, reference)

function read_intent(::WidgetMenuToGraphicsCanvas, iomap::ChildrenIoMap, evt)
    evt isa MouseMove && return _read_children_move(iomap, evt)
    _outside_widget(iomap, evt) && return nothing
    child_iomaps = getfield(iomap, :child_iomaps)[]::Vector
    evt isa MouseClick && return _route_click_to_children(child_iomaps, evt)
    evt isa MouseDwell && return _read_children_outward(iomap.input, child_iomaps, evt)
    evt isa MouseScroll || return nothing
    _route_scroll_to_children(child_iomaps, evt)
end

# ── WidgetComposite ─────────────────────────────────────────────────────────

function print_document(p::WidgetCompositeToGraphicsCanvas, recursion, w::WidgetComposite, ctx)
    w.visible == false && return ChildrenIoMap(p, w, _empty_canvas(), Cell(Any[]))
    pos = w.position::Point2D
    # A composite renders widget children, embedded layout children (e.g. a
    # GridLayout form from ObjectToWidget) and a child in a `LayoutConstraint`;
    # each re-enters the recursion. Reconcile the filtered children by identity so
    # a structural edit reuses survivors.
    child_cells = make_reconciled_child_iomaps_cell(
        () -> Any[c for c in w.elements
                  if (c isa WidgetDocument || c isa LayoutDocument || c isa LayoutConstraint)],
        (i, c) -> print_child(recursion, c, _make_composite_child_context(p, w, c, ctx)))
    # The natural extent of the children together, before the box around them.
    extent = Cell(@computation begin
        content_width, content_height = 0, 0
        for cim in child_cells[]
            ew, eh = _element_size(cim.output, _p_measure(p))
            content_width = max(content_width, ew); content_height = max(content_height, eh)
        end
        (content_width, content_height)
    end)
    # The box around the children is a canvas of its own, so the list of the
    # composite reads only which children there are and keeps its wrappers when
    # something inside a child changes. The box reads the size of the children
    # only when it has something to draw: the size of a child reads every graphic
    # in it, and a transparent box would pay for that on every change inside.
    box = GraphicsCanvas(CellVector(@computation begin
        elems = Any[]
        insets, colors = _get_box_insets(p, w), _get_box_colors(p, w)
        if _is_box_visible(insets, colors)
            content_width, content_height = extent[]
            _push_box_parts!(elems, insets, colors, content_width, content_height)
        end
        elems
    end))
    build = Cell(@computation begin
        content_x, content_y = _content_offset(p, w)
        cims = child_cells[]
        child_iomaps = Any[(content_x, content_y, cim) for cim in cims]
        elems = Any[box]
        for cim in cims
            push!(elems, _make_canvas(content_x, content_y, Any[cim.output]))
        end
        (elements=elems, child_iomaps=child_iomaps)
    end)
    # The ring over the element the composite's selection names as a whole.
    ring = make_selection_ring(() -> begin
        entries = build[].child_iomaps
        i = find_whole_selected_index(w.selection, "elements")
        (i === nothing || !(1 <= i <= length(entries))) && return nothing
        (x, y, cim) = entries[i]
        _get_entry_box(x, y, cim, _p_measure(p))
    end, p.graphics_style)
    ChildrenIoMap(p, w, _reactive_canvas_auto(_origin(pos)..., () -> vcat(build[].elements, Any[ring]),
                                              _p_measure(p)),
                  Cell(@computation build[].child_iomaps))
end

# The context of a child of a composite. The children overlap, each at its own
# position, so the composite divides neither axis, and it gives each child on both
# axes the range of `make_cross_axis_context`: the policy is the
# `LayoutConstraint` that the child is, else the composite's `child_width` and
# `child_height`, else `Content`. The edge is the maximum of the composite's
# range less its insets and less the position of the child, so a child that
# fills ends at the edge of the composite, and a child that fits its content
# draws it up to there.
function _make_composite_child_context(p, w::WidgetComposite, child, ctx)
    ctx isa PrinterContext || return ctx
    position = () -> _get_placed_position(child)
    edge(maximum, inset, coordinate) = maximum === nothing ? nothing :
        Cell(@computation Int32(max(0, Int(maximum[]) - inset() - coordinate())))
    cctx = with_bounded_size(ctx;
        width = edge(ctx.maximum_width, () -> _inset_total(p, w)[1], () -> position()[1]),
        height = edge(ctx.maximum_height, () -> _inset_total(p, w)[2], () -> position()[2]))
    cctx = make_cross_axis_context(cctx, child, :x, w.child_width)
    make_cross_axis_context(cctx, child, :y, w.child_height)
end

# The position of a child placed by hand, `(x, y)`, through a `LayoutConstraint` or
# a `WidgetContextMenu`, which stand where their child stands; `(0, 0)` for a child
# with none.
_get_placed_position(child::LayoutConstraint) = _get_placed_position(child.child)
_get_placed_position(child::WidgetContextMenu) = _get_placed_position(child.child)
function _get_placed_position(child)
    hasproperty(child, :position) || return (0, 0)
    position = child.position
    position isa Point2D ? (round(Int, position.x[]), round(Int, position.y[])) : (0, 0)
end

map_reference_forward(::WidgetCompositeToGraphicsCanvas, iomap::ChildrenIoMap, reference) = _map_child_forward(iomap, reference)

map_reference_backward(::WidgetCompositeToGraphicsCanvas, iomap, reference) =
    _map_child_point(iomap, reference)

# Route events to composite children and re-root the returned op. A MouseClick
# and a dwell are hit-tested against each child canvas; a coordless event
# (KeyPress/KeyDown) goes to the child the composite's selection points at, falling
# back to trying each child. The op a child returns is re-rooted by prepending
# `elements[i]` — the same scheme WidgetSplitPane uses. Identity-bearing ops
# (ReplaceReferencedValueOperation from a control) pass through `reroot_operation`
# unchanged. For a dwell and a right click the composite then reads its own stretch.
function read_intent(p::WidgetCompositeToGraphicsCanvas, iomap::ChildrenIoMap, evt)
    # A move that is off the composite still goes to the child the pointer leaves.
    _outside_widget(iomap, evt) && !(evt isa MouseMove) && return nothing
    child_iomaps = getfield(iomap, :child_iomaps)[]::Vector
    evt isa MouseMove && return _read_composite_move(iomap.input, child_iomaps, evt)
    # Tab traversal (Stage 2): distributed focus advance. Handle before the generic
    # selection-only routing so a Tab the selected child declines can advance my
    # own selection to the next focusable sibling.
    if iomap.input isa WidgetComposite && evt isa KeyDown && evt.key === :tab
        return _composite_tab(iomap.input, child_iomaps, evt)
    end
    res = @gesture_case evt begin
        MouseScroll => _route_composite_event(child_iomaps, evt.x, evt.y,
            (x, y) -> MouseScroll(evt.dx, evt.dy, x, y; time = evt.time))
        MouseClick => _route_composite_event(child_iomaps, evt.x, evt.y,
            (x, y) -> MouseClick(evt.button, x, y, evt.count, evt.modifiers;
                                 time = evt.time))
        MouseDwell => _route_composite_event(child_iomaps, evt.x, evt.y,
            (x, y) -> shift_event_position(evt, x - evt.x, y - evt.y))
        MouseDown => _route_composite_press(child_iomaps, evt.x, evt.y,
            (x, y) -> MouseDown(evt.button, x, y, evt.modifiers; time = evt.time))
        MouseUp => _route_composite_event(child_iomaps, evt.x, evt.y,
            (x, y) -> MouseUp(evt.button, x, y, evt.modifiers; time = evt.time))
        _ => begin
            # Coordless (keyboard) events route to the child the selection points
            # at, or to nothing when the selection is not inside this composite.
            # Selection is authoritative — no broadcast/first-answer fallback.
            # See package/visual/doc/widget.md.
            slot = iomap.input isa WidgetComposite ?
                   _selected_composite_slot(iomap.input, length(child_iomaps)) : 0
            slot == 0 ? nothing :
                        _forward_composite_event_slot(child_iomaps, evt, slot)
        end
    end
    res === nothing && return read_container_gesture(nothing, evt, iomap.input)
    op, slot_idx = res
    steps = _get_composite_slot_steps(slot_idx)
    read_container_gesture(reroot_operation(op, steps), evt, iomap.input; steps)
end

# A press routes to the hit child first, exactly as a click does — but when the
# pointer is over nothing, it is offered to the children anyway, in order: a split
# pane draws its divider in the gap between its slots, which is no hit, and the
# press there must still grab it. The rest of a drag comes by the path of the part
# whose drag is on.
function _route_composite_press(child_iomaps::Vector, x::Int, y::Int, make_evt)
    hit = _route_composite_event(child_iomaps, x, y, make_evt)
    hit === nothing || return hit
    for (i, entry) in enumerate(child_iomaps)
        entry === nothing && continue
        (ox, oy, cim) = entry::Tuple{Int,Int,Any}
        canvas = cim.output
        canvas isa GraphicsCanvas || continue
        result = read_intent(cim.projection, cim,
                             make_evt(x - ox - Int(canvas.x), y - oy - Int(canvas.y)))
        result === nothing || return (result, i)
    end
    nothing
end

# Hit-test a coordinate event against each child canvas, the topmost first (the
# one drawn last); returns `(op, i)` for the first child that produced a
# non-nothing result.
function _route_composite_event(child_iomaps::Vector, x::Int, y::Int, make_evt)
    for i in reverse(eachindex(child_iomaps))
        entry = child_iomaps[i]
        point = _find_widget_child_point(entry, x, y)
        point === nothing && continue
        (lx, ly) = point
        result = shift_operation_position(read_child_event(last(entry), make_evt(lx, ly)),
                                          x - lx, y - ly)
        result !== nothing && return (result, i)
    end
    nothing
end

# Forward a coordless event to the single child the selection points at.
function _forward_composite_event_slot(child_iomaps::Vector, evt, slot::Int)
    (1 <= slot <= length(child_iomaps)) || return nothing
    entry = child_iomaps[slot]
    entry === nothing && return nothing
    (_, _, cim) = entry::Tuple{Int,Int,Any}
    result = read_intent(cim.projection, cim, evt)
    result isa Operation ? (result, slot) : nothing
end

# The child slot the composite's selection (`elements[slot].<rest>`) points at,
# or 0 when it carries no such selection.
_selected_composite_slot(w::WidgetComposite, n::Int) = _get_elements_slot(getfield(w, :selection)[], n)

# The slot `i` of a path that begins `elements[i]`, or 0.
function _get_elements_slot(path, n::Int)
    path isa ConcreteReference || return 0
    (path.head isa FieldReferenceStep && path.head.name == "elements") || return 0
    t = path.tail
    (t isa ConcreteReference && t.head isa RangeReferenceStep) || return 0
    slot = t.head.start + 1
    1 <= slot <= n ? slot : 0
end

# The steps from a composite to the child in slot `slot`.
_get_composite_slot_steps(slot::Int) =
    (FieldReferenceStep("elements"), RangeReferenceStep(slot - 1, slot))

_reroot_composite(operation, slot::Int) =
    reroot_operation(operation, _get_composite_slot_steps(slot))

# A move of the pointer: the child that the composite's own mouse target names
# (the pointer leaves it), then the child under the point, the topmost first.
function _read_composite_move(document, child_iomaps::Vector, evt::MouseMove)
    new = _route_composite_event(child_iomaps, evt.x, evt.y,
        (x, y) -> MouseMove(x, y, evt.buttons, evt.modifiers; time = evt.time))
    new_answer = new === nothing ? nothing : _reroot_composite(new...)
    old = _get_elements_slot(get_mouse_target(document), length(child_iomaps))
    (old == 0 || (new !== nothing && new[2] == old) || child_iomaps[old] === nothing) &&
        return new_answer
    entry = child_iomaps[old]
    old_answer = read_child_leave(last(entry), evt, get_child_frame_offset(entry)...)
    join_move_answers(_reroot_composite(old_answer, old), new_answer)
end

# The focus walk (`get_first_focusable_path`, `get_last_focusable_path`,
# `get_next_focusable_index`, `_focusable_path`) lives in `FocusModule`, which names no
# widget type, so the `LayoutToGraphics` reader shares it for Tab traversal.
# `WidgetModule` answers its `is_focusable_document` trait for `FocusableWidget`.
# The three walk functions are imported at the top of this file.

# ── Distributed Tab traversal (Stage 2, composite) ──────────────────────────
#
# Tab handling for `WidgetComposite`. Each container participates: it delegates
# Tab to the selected child and, if the child declines (returns nothing — it ran
# off its own end), advances the selection to its next focusable sibling; if it
# has no next sibling it declines too, so its parent advances. The selection move
# is a `ReplaceSelectionOperation` *relative to this composite*; the parent's
# `reroot_operation` makes it absolute as it bubbles up (the same re-rooting
# applied to edit ops). With selection-only routing (Step 1) a non-root container
# only ever receives Tab when the selection is inside it, so a Tab that arrives
# with no child slot selected means "the selection is on me (∅)" — bootstrap into
# my first focusable (this also covers the root with no selection).
#
# NOTE: Wrap-around (Tab on the very last focusable → the first) is the one
# non-local case and is not handled here — a container only advances or
# declines. The single top-level rule that wraps a declined Tab lives at the
# outer widget seam, in `FocusCyclingProjection` (`source/platform/focus/FocusCycling.jl`).
function _composite_tab(w::WidgetComposite, child_iomaps::Vector, evt)
    n = length(child_iomaps)
    reverse = evt.modifiers.shift
    i = _selected_composite_slot(w, n)
    if i == 0
        # Selection is on me, not a child (∅), or I am the unselected root:
        # focus my first (last) leaf.
        sub = reverse ? get_last_focusable_path(w) : get_first_focusable_path(w)
        return sub === nothing ? nothing : ReplaceSelectionOperation(sub)
    end
    # Delegate to the selected child; an internal advance re-roots through me.
    deleg = _forward_composite_event_slot(child_iomaps, evt, i)
    if deleg !== nothing
        op, slot = deleg
        return reroot_operation(op, (FieldReferenceStep("elements"), RangeReferenceStep(slot - 1, slot)))
    end
    # Child declined: advance to my next focusable sibling, entering its first leaf.
    j = get_next_focusable_index(w.elements, i, reverse)
    j == 0 && return nothing                      # no next sibling — I decline; parent advances.
    sub = reverse ? get_last_focusable_path(w.elements[j]) : get_first_focusable_path(w.elements[j])
    sub === nothing && return nothing
    ReplaceSelectionOperation(ConcreteReference(FieldReferenceStep("elements"),
        ConcreteReference(RangeReferenceStep(j - 1, j), sub)))
end

# ── WidgetShell ─────────────────────────────────────────────────────────────

function print_document(p::WidgetShellToGraphicsCanvas, recursion, w::WidgetShell, ctx)
    w.visible == false && return ChildrenIoMap(p, w, _empty_canvas(), Cell(Any[]))
    # The shell's extent on an axis is its own `size` when it has one, else the
    # space its parent offered, and it has none on an axis where it has neither
    # (`layout-rules.md` §3). A window offers its size, so the shell of a window
    # fills it and follows it when it resizes, with no number of its own.
    authored = getfield(w, :size)[] isa Point2D
    has_width = authored || get_exact_width(ctx) !== nothing
    has_height = authored || get_exact_height(ctx) !== nothing
    outer_width = Cell(@computation begin
        sz = getfield(w, :size)[]
        sz isa Point2D ? Int(sz.x[]) : Int(get_exact_width(ctx)[])
    end)
    outer_height = Cell(@computation begin
        sz = getfield(w, :size)[]
        sz isa Point2D ? Int(sz.y[]) : Int(get_exact_height(ctx)[])
    end)
    # The room inside the shell, across, less its insets.
    avail_w_cell = Cell(@computation begin
        tx, _ = _inset_total(p, w)
        max(0, outer_width[] - tx)
    end)
    # A band spans the shell and is as tall as what it holds, so it is offered
    # the width and no height. An item of a band that is offered the window's
    # height draws as tall as the window.
    band_ctx = with_exact_size(ctx; width = has_width ? avail_w_cell : nothing,
                                    height = nothing)
    # Each named slot is reconciled by its field value and forced only in the
    # branch that renders it (a nil slot never re-projects). Each slot's reference
    # is extended into its field, so a reference inside a slot names the shell's
    # field and forward-maps back through the shell.
    mb_cell = make_reconciled_child_iomap_cell(() -> w.menu_bar,
        c -> print_child(recursion, c, make_child_context(band_ctx, FieldReferenceStep("menu_bar"))))
    tb_cell = make_reconciled_child_iomap_cell(() -> w.toolbar,
        c -> print_child(recursion, c, make_child_context(band_ctx, FieldReferenceStep("toolbar"))))
    sb_cell = make_reconciled_child_iomap_cell(() -> w.status_bar,
        c -> print_child(recursion, c, make_child_context(band_ctx, FieldReferenceStep("status_bar"))))
    tt_cell = make_reconciled_child_iomap_cell(() -> w.overlay,
        c -> print_child(recursion, c, make_child_context(ctx, FieldReferenceStep("overlay"))))
    # Where the bands sit, from the height each one draws. A band's height comes
    # from what it holds, never from the shell, so reading it closes no cycle.
    bands = Cell(@computation begin
        cox, coy = _content_offset(p, w)
        menu_h = w.menu_bar isa WidgetDocument ? _shell_band_height(mb_cell[]) : 0
        tool_h = w.toolbar isa WidgetDocument ? _shell_band_height(tb_cell[]) + p.band_gap : 0
        status_h = w.status_bar isa WidgetDocument ? _shell_band_height(sb_cell[]) : 0
        (cox=cox, coy=coy, menu_h=menu_h, tool_h=tool_h,
         content_y=coy + menu_h + tool_h, status_h=status_h)
    end)
    # The room inside the shell, down, less its insets and the bands above and
    # below the content.
    avail_h_cell = Cell(@computation begin
        _, ty = _inset_total(p, w)
        b = bands[]
        max(0, outer_height[] - ty - (b.content_y - b.coy) - b.status_h)
    end)
    # The content is offered that room on each axis where the shell has an
    # extent, and nothing where it has none: then it takes its own extent, and
    # a shell never offers 0.
    content_ctx = with_exact_size(ctx; width = has_width ? avail_w_cell : nothing,
                                       height = has_height ? avail_h_cell : nothing)
    content_cell = make_reconciled_child_iomap_cell(() -> w.content,
        c -> print_child(recursion, c, make_child_context(content_ctx, FieldReferenceStep("content"))))
    # The top of each band. The content hangs under the toolbar, and the status bar
    # runs along the bottom edge when the shell has a height, and under the content
    # when it has none, so a shell that hugs its content still shows it.
    places = Cell(@computation begin
        b = bands[]
        menu_y = b.coy
        tool_y = menu_y + b.menu_h
        content_y = tool_y + b.tool_h
        content_bottom = content_y
        w.content !== nothing && !has_height && (content_bottom += _shell_band_height(content_cell[]))
        _, ty = _inset_total(p, w)
        status_y = has_height ? b.coy + outer_height[] - ty - b.status_h : content_bottom
        (menu_bar = menu_y, toolbar = tool_y, content = content_y, status_bar = status_y)
    end)
    # The bands the shell draws, each with the iomap it holds and the cell of its top.
    # Which bands there are depends on the fields of the shell and not on how tall
    # a band is, so a status line that changes its text rebuilds nothing here:
    # each band keeps its wrapper, and the top of a band is a cell of its own. A
    # band that keeps its place is then not painted again.
    slots = Cell(@computation begin
        out = Any[]
        w.menu_bar isa WidgetDocument && push!(out, (:menu_bar, mb_cell[]))
        w.toolbar isa WidgetDocument && push!(out, (:toolbar, tb_cell[]))
        # Any content, not only a widget: the recursion decides how it renders, so
        # a shell frames a domain document the same way a tab of a
        # WidgetTabbedPane holds one. An absent content is the only empty case.
        w.content !== nothing && push!(out, (:content, content_cell[]))
        w.status_bar isa WidgetDocument && push!(out, (:status_bar, sb_cell[]))
        w.overlay isa WidgetDocument && push!(out, (:overlay, tt_cell[]))
        out
    end)
    get_band_left(name) = name === :overlay ? 0 : _content_offset(p, w)[1]
    get_band_top(name) = name === :overlay ? 0 : getproperty(places[], name)
    build = Cell(@computation begin
        elems = Any[]
        if has_width && has_height
            inset_width, inset_height = _inset_total(p, w)
            content_width = max(0, Int(outer_width[]) - inset_width)
            content_height = max(0, Int(outer_height[]) - inset_height)
            _push_box_parts!(elems, _get_box_insets(p, w), _get_box_colors(p, w), content_width, content_height)
        end
        for (name, cim) in slots[]
            push!(elems, _make_canvas(get_band_left(name), Cell(@computation Int32(get_band_top(name))),
                                      Any[cim.output]))
        end
        elems
    end)
    child_iomaps = Cell(@computation Any[(get_band_left(name), get_band_top(name), cim) for (name, cim) in slots[]])
    ChildrenIoMap(p, w, _reactive_canvas_auto(0, 0, () -> build[], _p_measure(p)), child_iomaps)
end

# How tall a band's printed output is.
_shell_band_height(cim) = cim.output isa GraphicsCanvas ? Int(cim.output.h[]) : 0

# A shell renders several field-addressed children (`menu_bar`, `toolbar`,
# `status_bar`, `content`, `overlay`), each wrapped at its band offset. Descend the leading
# field step to the matching child (found by identity, since the bands are
# positional/conditional) and shift a coordinate image by that placement; paths
# and unknown fields pass through with no image, and the menu-bar path maps an
# entry of the bar to its position (Step 4c).
_shell_field(w, name) =
    name == "menu_bar" ? w.menu_bar :
    name == "toolbar"  ? w.toolbar  :
    name == "status_bar" ? w.status_bar :
    name == "content"  ? w.content  :
    name == "overlay"  ? w.overlay  : nothing

map_reference_forward(::WidgetShellToGraphicsCanvas, iomap::ChildrenIoMap, reference) = _map_child_forward(iomap, reference)

map_reference_forward(::WidgetShellToGraphicsCanvas, iomap, reference) = _map_child_forward(iomap, reference)

# A change with a route goes to the part of the shell its route names, found as
# the forward mapper finds it, with the point of a pointer gesture in the frame of
# that band; every other change is read as any projection reads it.
function read_intent(p::WidgetShellToGraphicsCanvas, recursion, change::Intent,
                     iomap::ChildrenIoMap)
    change.route === nothing && return @invoke read_intent(p::Projection, recursion, change::Intent, iomap)
    head = change.route isa ConcreteReference ? get_reference_head(change.route) : nothing
    head isa FieldReferenceStep || return Intent(change.gesture, nothing)
    target = _shell_field(iomap.input, head.name)
    target === nothing && return Intent(change.gesture, nothing)
    for entry in getfield(iomap, :child_iomaps)[]::Vector
        entry === nothing && continue
        (_, _, cim) = entry
        cim.input === target || continue
        inner = read_routed_entry_child(recursion, follow_intent_route(change, head), cim;
                                        entries = (entry,))
        return Intent(change.gesture, reroot_operation(inner.operation, (head,)))
    end
    Intent(change.gesture, nothing)
end

# ── Routes through a container ─────────────────────────────────────────────
#
# A change with a route goes on to the child the route names, and comes back
# rerooted by the steps it took, as the answer to a gesture does. The kernel's
# default reader does this for every container whose IoMap names its children
# (`get_child_iomaps`, `read_routed_child`): a `ChildrenIoMap` does, and a
# container with an IoMap of its own says what it holds, next to that IoMap. The
# shell keeps its own reader, because its route names a band of the shell.

# The IoMaps among `entries`: an IoMap, a tuple whose last member is one (a place
# and the IoMap of what is there), or nothing.
function _collect_child_iomaps(entries...)
    found = Any[]
    for entry in entries
        entry isa Tuple && !isempty(entry) && (entry = last(entry))
        entry isa IoMap && push!(found, entry)
    end
    found
end

# The shell wraps a single child widget as its `.content` field. A path
# coming up from the child's reader lives at `.content.<rest>` in the
# shell's input domain.
function map_reference_backward(p::WidgetShellToGraphicsCanvas, iomap::ChildrenIoMap, reference)
    reference === nothing && return nothing
    find_reference_point(reference) === nothing || return _map_child_point(iomap, reference)
    ConcreteReference(FieldReferenceStep("content"), reference)
end

# Collect the shared `Action`s that carry a keyboard shortcut, reachable from a
# shell's `menu_bar` + `toolbar` (recursing submenus). The menu *is* the shortcut
# registry, so there is no separate list to keep in sync (Stage 4).
function _collect_command_actions!(acc::Vector{Action}, w)
    # Every control now carries an `Action`, but only a SHARED one ever declares
    # a shortcut — a sugar-folded action is built without one — so the filter
    # below collects exactly the same set it did when it read `command`.
    if w isa WidgetMenuItem
        c = w.action; c.shortcut !== nothing && push!(acc, c)
        sm = w.submenu; sm isa WidgetMenu && _collect_command_actions!(acc, sm)
    elseif w isa WidgetButton || w isa WidgetToolbarItem
        c = w.action; c.shortcut !== nothing && push!(acc, c)
    elseif w isa WidgetMenu || w isa WidgetToolbar
        for e in w.elements
            e isa WidgetDocument && _collect_command_actions!(acc, e)
        end
    end
    acc
end

function _shell_shortcut_actions(w::WidgetShell)
    acc = Action[]
    mb = w.menu_bar; mb isa WidgetDocument && _collect_command_actions!(acc, mb)
    tb = w.toolbar;  tb isa WidgetDocument && _collect_command_actions!(acc, tb)
    acc
end

function read_intent(p::WidgetShellToGraphicsCanvas, iomap::ChildrenIoMap, evt)
    # A band answers in its own field, and the content in `content`.
    evt isa MouseMove && return _read_children_move(iomap, evt)
    _outside_widget(iomap, evt) && return nothing
    # Stage 4 shortcuts: a `KeyDown` matching an (enabled) menu/toolbar command's
    # shortcut fires it globally — before the focused child sees the key — so e.g.
    # Ctrl+S works regardless of which widget is selected.
    if evt isa KeyDown
        for action in _shell_shortcut_actions(iomap.input)
            matches_action_shortcut(action, evt) && return InvokeActionOperation(action)
        end
    end
    child_iomaps = getfield(iomap, :child_iomaps)[]::Vector
    # A dwell and a right click go to the band at their point, as a click goes, and
    # the answer is rooted at the field of that band. The shell then reads its own
    # table, so the menu of the window is the outermost layer of a right click.
    is_outward_gesture(evt) &&
        return _read_children_outward(iomap.input, child_iomaps, evt)
    if is_whole_selection_press(evt)
        selected = _select_in_band(iomap.input, child_iomaps, evt)
        selected === nothing || return selected
    end
    op = @gesture_case evt begin
        MouseScroll => _route_scroll_to_children(child_iomaps, evt)
        MouseClick  => _route_click_to_children(child_iomaps, evt)
        # A down and an up carry coordinates like a press, so they go to the band
        # under the pointer, in that band's frame. The parts of a drag come by the
        # path of the part whose drag is on, wherever the pointer is.
        MouseDown   => _route_shell_down(child_iomaps, evt)
        MouseUp     => _route_downup_to_children(child_iomaps, evt)
        # Forward keyboard (and other coordless) events to the wrapped
        # child. The reader at the focused leaf returns an op; others
        # return nothing.
        _           => _forward_to_children(child_iomaps, evt)
    end
    _retarget_op(p, iomap, op)
end

# An Alt+press over a band selects in that band, and the path names the band's
# own field. Every other answer is re-rooted into `content`, and a band is not
# the content, so an Alt+press on a toolbar button selects the button and not the
# whole window. Only the bands are hit-tested here, so a press over the content
# reads the content once, on the ordinary route.
function _select_in_band(shell::WidgetShell, child_iomaps::Vector, evt::MouseClick)
    for entry in child_iomaps
        entry === nothing && continue
        (ox, oy, cim) = entry::Tuple{Int,Int,Any}
        field = _find_band_field(shell, cim.input)
        field === nothing && continue
        canvas = cim.output
        canvas isa GraphicsCanvas || continue
        lx, ly = evt.x - ox - Int(canvas.x), evt.y - oy - Int(canvas.y)
        hit_element_at(canvas, lx, ly) === nothing && continue
        answer = read_child_event(cim, MouseClick(evt.button, lx, ly, evt.count, evt.modifiers;
                                                  time = evt.time))
        answer === nothing && return nothing
        return reroot_operation(answer, (FieldReferenceStep(field),))
    end
    nothing
end

# The field of the shell that holds `band`, when it is one of the three bands.
function _find_band_field(shell::WidgetShell, band)
    band === nothing && return nothing
    band === shell.menu_bar && return "menu_bar"
    band === shell.toolbar && return "toolbar"
    band === shell.status_bar && return "status_bar"
    nothing
end

# ── The pointer in a shell ──────────────────────────────────────────────────
#
# The entry of the band under a point, or `nothing`.
function _find_shell_band_at(child_iomaps::Vector, x::Int, y::Int)
    for entry in child_iomaps
        entry === nothing && continue
        (ox, oy, cim) = entry::Tuple{Int,Int,Any}
        canvas = cim.output
        canvas isa GraphicsCanvas || continue
        hit_element_at(canvas, x - ox - Int(canvas.x), y - oy - Int(canvas.y)) === nothing && continue
        return entry
    end
    nothing
end

# Hand `evt` to one band, translated into its frame.
function _read_band_event(entry, evt)
    (ox, oy, cim) = entry::Tuple{Int,Int,Any}
    canvas = cim.output
    canvas isa GraphicsCanvas || return nothing
    read_child_event(cim, shift_event_position(evt, -ox - Int(canvas.x), -oy - Int(canvas.y)))
end

# A down goes to the band under the pointer, in the frame of that band.
function _route_shell_down(child_iomaps::Vector, evt::MouseDown)
    entry = _find_shell_band_at(child_iomaps, evt.x, evt.y)
    entry === nothing ? nothing : _read_band_event(entry, evt)
end

# Forward a coordless event to each child entry's reader, returning the
# first child that produced an `Operation`. Entries are `(x, y, cim)` tuples —
# coords are ignored here. A child has only *handled* the event if it returns
# an `Operation`; readers that pass the raw event back through (the common
# `read_intent(p, iomap, op) = op` passthrough) must not be mistaken for
# handlers, otherwise a non-focused pane would swallow the keystroke before a
# later, focused pane is reached.
function _forward_to_children(child_entries::Vector, evt)
    for entry in child_entries
        entry === nothing && continue
        (_, _, cim) = entry::Tuple{Int,Int,Any}
        result = read_intent(cim.projection, cim, evt)
        result isa Operation && return result
    end
    nothing
end

# ── WidgetTitlePane ─────────────────────────────────────────────────────────

function print_document(p::WidgetTitlePaneToGraphicsCanvas, recursion, w::WidgetTitlePane, ctx)
    w.visible == false && return ChildrenIoMap(p, w, _empty_canvas(), Cell(Any[]))
    content_ctx = _get_title_pane_content_context(p, w, ctx)
    content_cell = make_reconciled_child_iomap_cell(() -> w.content, c -> print_child(recursion, c, content_ctx))
    build = Cell(@computation begin
        content_x, content_y0 = _content_offset(p, w)
        title_text = _get_part_text(w, :title_text, p.title_text)
        body_text = _get_part_text(w, :body_text, p.body_text)
        title = string(w.title)
        tw, th = _text_size(p.measure, title_text.font, title)
        content_y = content_y0 + th + p.title_gap
        content = w.content
        body_elems = Any[]
        child_iomaps = Any[]
        cw, ch = 0, 0
        if content isa Document
            cim = content_cell[]
            inner = cim.output
            iw, ih = inner isa GraphicsCanvas ? (Int(inner.w[]), Int(inner.h[])) : (0, 0)
            cw, ch = iw, ih
            push!(child_iomaps, (content_x, content_y, cim))
            push!(body_elems, _make_canvas(content_x, content_y, Any[inner]))
        elseif content isa AbstractString
            cw, ch = _text_size(p.measure, body_text.font, content)
            _push_text!(body_elems, p.measure, body_text.font, content, content_x, content_y, body_text.color)
        end
        # The pane takes its slot, and with no slot the title and the content.
        inset_width, inset_height = _inset_total(p, w)
        outer_width = _resolve_width(ctx, 0, max(tw, cw) + inset_width)
        outer_height = _resolve_height(ctx, 0, (content_y - content_y0) + ch + inset_height)
        box_content_width = outer_width - inset_width
        elems = Any[]
        _push_box_parts!(elems, _get_box_insets(p, w), _get_box_colors(p, w), box_content_width,
                         outer_height - inset_height)
        title_bar_color = _get_part_color(w, :title_bar_color, p.title_bar_color)
        _push_panel!(elems, content_x, content_y0, box_content_width, th; fill = title_bar_color)
        # Card-like: bold title, body in the content style.
        _push_text!(elems, p.measure, title_text.font, title, content_x, content_y0, title_text.color)
        append!(elems, body_elems)
        (width=outer_width, height=outer_height, elements=elems, child_iomaps=child_iomaps)
    end)
    ChildrenIoMap(p, w, _reactive_canvas_cell(0, 0, build), Cell(@computation build[].child_iomaps))
end

# The range of the content: the range of the pane less its insets, and less the
# title bar and its gap on the height, in the same state, so a slot stays a slot
# and an edge stays an edge (§3 of layout-rules.md).
function _get_title_pane_content_context(p::WidgetTitlePaneToGraphicsCanvas, w::WidgetTitlePane, ctx)
    ctx === nothing && return nothing
    inset_width = Cell(@computation _inset_total(p, w)[1])
    above = Cell(@computation begin
        title_text = _get_part_text(w, :title_text, p.title_text)
        _inset_total(p, w)[2] + _text_size(p.measure, title_text.font, string(w.title))[2] + p.title_gap
    end)
    with_inner_size(ctx; width = inset_width, height = above)
end

map_reference_forward(::WidgetTitlePaneToGraphicsCanvas, iomap, reference) = _map_child_forward(iomap, reference)

map_reference_backward(::WidgetTitlePaneToGraphicsCanvas, iomap, reference) =
    _map_child_point(iomap, reference)

function read_intent(::WidgetTitlePaneToGraphicsCanvas, iomap::ChildrenIoMap, evt)
    evt isa MouseMove && return _read_children_move(iomap, evt)
    _outside_widget(iomap, evt) && return nothing
    child_iomaps = getfield(iomap, :child_iomaps)[]::Vector
    evt isa MouseDwell && return _read_children_outward(iomap.input, child_iomaps, evt)
    evt isa MouseScroll || return nothing
    _route_scroll_to_children(child_iomaps, evt)
end

# ── WidgetSplitPane ─────────────────────────────────────────────────────────

# Peek through a transparent LayoutConstraint wrapper to the underlying
# widget; split-pane treats the wrapper as opaque for layout policy but
# projects the wrapped child directly so the wrapper's own projection is
# not required to be registered in the dispatcher.
_split_inner(elem) = elem isa LayoutConstraint ? elem.child : elem

# Wrap a child canvas at the (x, y) given by two cells — same shape used
# by the layout projections; local copy here to avoid a circular import
# from LayoutToGraphics into this module.
# A split's slot. The split hands the child a main-axis extent it computed, so it
# clips that axis to what it handed out (§3b of layout-rules.md) — otherwise a
# child too big for its slot draws across its neighbour and past the splitter.
# The cross axis is clipped only when the split was offered one; an axis it
# withholds has nothing to clip against.
function _wrap_child_canvas(child::GraphicsCanvas, x_cell::Cell, y_cell::Cell,
                            w::Int, h::Int)
    GraphicsViewport(x_cell, y_cell, Cell(Int32(max(0, w))), Cell(Int32(max(0, h))),
                     Cell(GraphicsCanvas(Cell(Int32(0)), Cell(Int32(0)),
                                         Cell(Int32(0)), Cell(Int32(0)),
                                         CellVector(Cell[Cell(child)]),
                                         layout_none, true, Cell(nothing))),
                     Cell(affine_identity),
                     Cell(nothing))
end

"""
Per-slot intrinsic main-axis extent: the `LayoutConstraint`'s preferred when
there is one, else the `sizes` vector, else nothing. A slot nobody sized and
nobody weighted takes no room.
"""
function _split_intrinsic(elem, sizes, i::Int, axis::Symbol)
    intrinsic = (!isempty(sizes) && i <= length(sizes)) ? Int(sizes[i]) : 0
    layout_preferred(elem, axis, intrinsic)
end

# The slot list a split lays out: `Document` children, each optionally wrapped in a
# `LayoutConstraint` (transparent for projection, consulted for sizing policy).
function _split_valid_elements(w::WidgetSplitPane)
    result = Any[]
    for i in 1:length(w.elements)
        elem = w.elements[i]
        (elem isa LayoutConstraint || elem isa Document) && push!(result, elem)
    end
    result
end

# Every per-slot cell, child IoMap and canvas child below is built for the slot
# count it saw, so a slot **added or removed** can not be threaded through the ones
# already standing. `_split_build` is therefore run inside a cell that reads the
# slot list: adding a pane re-derives the layout, and everything that reads the
# output — the canvas, the child IoMaps the reader routes through — follows.
#
# A slot change re-prints the children. Reusing their IoMaps across it would mean
# building each child's context *before* the allocation that context depends on,
# which is the cycle the forward-declared `alloc_cell` below already threads once;
# a second pass through it would have to run inside the very cell it feeds.
function print_document(p::WidgetSplitPaneToGraphicsCanvas, recursion, w::WidgetSplitPane, ctx)
    w.visible == false && return ChildrenIoMap(p, w, _empty_canvas(), Cell(Any[]))
    build = Cell(@computation _split_build(p, recursion, w, ctx))
    ChildrenIoMap(p, w, Cell(@computation build[].canvas),
                  Cell(@computation build[].child_iomaps))
end

function _split_build(p::WidgetSplitPaneToGraphicsCanvas, recursion, w::WidgetSplitPane, ctx)
    box = _get_box_insets(p, w)
    colors = _get_box_colors(p, w)
    cox, coy = _content_offset(p, w)
    orientation = w.orientation::Symbol
    main_axis = orientation === :horizontal ? :x : :y
    sizes = w.sizes
    splitter_stroke = _get_part_stroke(w, :splitter_stroke, p.splitter_stroke)
    splitter_thickness = max(1, Int(splitter_stroke.width))
    splitter_color = splitter_stroke.color

    # Reading the slot list here is what makes the enclosing cell re-derive when a
    # slot is added or removed.
    valid_elems = _split_valid_elements(w)
    n = length(valid_elems)
    n == 0 && return (canvas = _make_canvas(0, 0, Any[]), child_iomaps = Any[])

    # The offer covers the pane's whole box, and the slots live inside its inset.
    # Allocating the full offer and then placing the first child at `cox` made the
    # pane overhang its own offer by exactly the inset, on both axes.
    inset_x, inset_y = _inset_total(p, w)
    outer_avail_w = get_exact_width(ctx)
    outer_avail_h = get_exact_height(ctx)
    avail_w = outer_avail_w === nothing ? nothing :
              Cell(@computation Int32(max(0, Int(outer_avail_w[]) - inset_x)))
    avail_h = outer_avail_h === nothing ? nothing :
              Cell(@computation Int32(max(0, Int(outer_avail_h[]) - inset_y)))
    avail_main = main_axis === :x ? avail_w : avail_h
    avail_cross = main_axis === :x ? avail_h : avail_w

    # Per-slot main-axis size (Cell). When the parent gave us an allocation
    # on the main axis, the slot is the per-child share of that allocation;
    # otherwise the slot falls back to each child's intrinsic preferred
    # extent. Built up-front so we can seed it into each child's available
    # size before recursion — without it the child (typically a scroll
    # pane) has no way to size its viewport to its slot.
    # The allocation is a forward-declared *reactive* cell: slot cells read it now
    # (before it has a value) and the real allocation thunk is installed via
    # `set_cell_computation!` once intrinsic sizes are readable (below). Reading it before then
    # yields `nothing` → a transient 0 slot; `set_cell_computation!` invalidates the slot cells so
    # they recompute with the real allocation. (A plain `Ref` was not reactive, so
    # a slot forced early — e.g. by a follow-end scroll pane measuring its
    # word-wrapped content — both crashed and could cache a stale size.)
    alloc_cell = Cell(nothing)
    slot_main = Cell[]
    if avail_main !== nothing
        for i in 1:n
            push!(slot_main, Cell(@computation begin v = alloc_cell[]; v === nothing ? 0 : Int(v[i]) end))
        end
    else
        # No main-axis offer: there is nothing to divide, so each slot is the
        # child's own extent. A declared size — `sizes[i]` or a `LayoutConstraint`
        # — is that extent; otherwise it is what the child draws, which is only
        # readable after the recursion, so these are forward-declared here and
        # filled in below, as `alloc_cell` is in the offered case.
        for _ in 1:n
            push!(slot_main, Cell(0))
        end
    end

    # Recurse into the wrapped widget (peeking through LayoutConstraint),
    # passing the slot's main-axis extent down via context so the child can
    # size itself to its slot.
    inner_iomaps = Any[]
    for i in 1:n
        elem  = valid_elems[i]
        inner = _split_inner(elem)
        cell  = slot_main[i]
        # Offer the slot only when there is one. Offering an unallocated slot
        # tells the child it has no room at all, and it draws nothing; withholding
        # the axis lets the child size itself, which is what the slot then is.
        cctx  = avail_main === nothing ? with_free_axis(ctx, main_axis) :
                main_axis === :x ? with_exact_size(ctx; width=cell) :
                                   with_exact_size(ctx; height=cell)
        cim = print_child(recursion, inner, cctx)
        push!(inner_iomaps, cim)
    end

    # The unoffered slots, now that the children have drawn.
    if avail_main === nothing
        for i in 1:n
            declared = _split_intrinsic(valid_elems[i], sizes, i, main_axis)
            cim_local = inner_iomaps[i]
            set_cell_computation!(slot_main[i], function ()
                declared > 0 && return declared
                out = cim_local.output
                out isa GraphicsCanvas || return 0
                Int(main_axis === :x ? out.w[] : out.h[])
            end)
        end
    end

    # Build the main-axis allocation cell now that intrinsic widths are
    # readable via the inner canvases. Falls back to `sizes` when
    # neither LayoutConstraint nor intrinsic preference is supplied.
    if avail_main !== nothing
        local_elems = valid_elems
        local_cims  = inner_iomaps
        axis        = main_axis
        n_local     = n
        sizes_local = sizes
        pinned_cv   = w.pinned
        set_cell_computation!(alloc_cell, function ()
            mins  = Vector{Int}(undef, n_local)
            maxs  = Vector{Int}(undef, n_local)
            prefs = Vector{Int}(undef, n_local)
            wts   = Vector{Float64}(undef, n_local)
            for i in 1:n_local
                elem      = local_elems[i]
                intrinsic = _split_intrinsic(elem, sizes_local, i, axis)
                mins[i]   = layout_min(elem, axis, intrinsic)
                maxs[i]   = layout_max(elem, axis, intrinsic)
                # A slot pinned by a drag is laid out at its dragged `sizes`
                # extent exactly: that value becomes a hard pref (overriding any
                # LayoutConstraint preferred) and its weight is zeroed so
                # weighted redistribution leaves it alone.
                if i <= length(pinned_cv) && pinned_cv[i] && i <= length(sizes_local)
                    prefs[i] = Int(sizes_local[i])
                    wts[i]   = 0.0
                else
                    prefs[i] = intrinsic
                    wts[i]   = layout_weight(elem, axis)
                end
            end
            allocate_axis(Int(avail_main[]); mins, maxs, prefs, weights = wts,
                          gap = splitter_thickness, n = n_local)
        end)
    end

    # Per-child top-left position cells (running cursor across the main axis).
    child_x = Cell[]
    child_y = Cell[]
    for i in 1:n
        if main_axis === :x
            push!(child_x, Cell(Computation(function ()
                x = cox
                for j in 1:(i-1)
                    x += Int(slot_main[j][]) + splitter_thickness
                end
                Int32(x)
            end)))
            push!(child_y, Cell(Int32(coy)))
        else
            push!(child_x, Cell(Int32(cox)))
            push!(child_y, Cell(Computation(function ()
                y = coy
                for j in 1:(i-1)
                    y += Int(slot_main[j][]) + splitter_thickness
                end
                Int32(y)
            end)))
        end
    end

    # Outer canvas size: sum of slot main extents (+ splitters) on the
    # main axis; max of child cross extents on the cross axis. If the
    # parent gave us an available cross extent we report that instead so
    # the slot fills the parent's allocation.
    outer_main = Cell(Computation(function ()
        total = 0
        for i in 1:n
            total += Int(slot_main[i][])
        end
        Int32(total + (n - 1) * splitter_thickness)
    end))
    outer_cross = if main_axis === :x
        avail_h === nothing ?
            Cell(Computation(function ()
                h = 0
                for cim in inner_iomaps
                    ch = cim.output isa GraphicsCanvas ? Int(cim.output.h[]) : 0
                    ch > h && (h = ch)
                end
                Int32(h)
            end)) :
            Cell(@computation Int32(avail_h[]))
    else
        avail_w === nothing ?
            Cell(Computation(function ()
                wmax = 0
                for cim in inner_iomaps
                    cw = cim.output isa GraphicsCanvas ? Int(cim.output.w[]) : 0
                    cw > wmax && (wmax = cw)
                end
                Int32(wmax)
            end)) :
            Cell(@computation Int32(avail_w[]))
    end
    # Report the whole box: the slots plus the inset they sit inside.
    inner_w_cell = main_axis === :x ? outer_main : outer_cross
    inner_h_cell = main_axis === :x ? outer_cross : outer_main
    outer_w_cell = Cell(@computation Int32(Int(inner_w_cell[]) + inset_x))
    outer_h_cell = Cell(@computation Int32(Int(inner_h_cell[]) + inset_y))

    # Build the outer canvas elements as a CellVector so splitter positions
    # and child wrappers re-flow reactively when slot sizes change. The
    # splitter's cross-axis extent tracks `outer_cross` so it spans exactly
    # the pane's cross dimension instead of overflowing on a fixed length.
    outer_elements = CellVector(Computation(function ()
        result = Any[]
        _push_box_parts!(result, box, colors, Int(inner_w_cell[]), Int(inner_h_cell[]))
        cross_extent = Int(outer_cross[])
        for i in 1:n
            cim = inner_iomaps[i]
            cim.output isa GraphicsCanvas || continue
            slot = Int(slot_main[i][])
            # A child is measured only when the parent offers no cross extent:
            # its size reads every graphic in it, so a measure that is not used
            # would rebuild this list on every change inside the child.
            cross = avail_cross === nothing ?
                    Int(get_graphics_size(cim.output)[main_axis === :x ? 2 : 1]) : cross_extent
            clip_w = main_axis === :x ? slot : cross
            clip_h = main_axis === :x ? cross : slot
            push!(result, _wrap_child_canvas(cim.output, child_x[i], child_y[i],
                                             clip_w, clip_h))
        end
        if main_axis === :x
            cursor = cox
            for i in 1:(n-1)
                cursor += Int(slot_main[i][])
                push!(result, GraphicsRect(cursor, coy, splitter_thickness, cross_extent;
                                           color = splitter_color))
                cursor += splitter_thickness
            end
        else
            cursor = coy
            for i in 1:(n-1)
                cursor += Int(slot_main[i][])
                push!(result, GraphicsRect(cox, cursor, cross_extent, splitter_thickness;
                                           color = splitter_color))
                cursor += splitter_thickness
            end
        end
        # Where a press grabs a splitter, the pointer is a double arrow along the
        # main axis, over the band of the reader (`_get_splitter_band`).
        for i in 2:n
            if main_axis === :x
                start, extent = _get_splitter_band(Int(child_x[i][]), splitter_thickness)
                push!(result, GraphicsPointerShape(start, coy, extent, cross_extent,
                                                   :double_arrow_horizontal))
            else
                start, extent = _get_splitter_band(Int(child_y[i][]), splitter_thickness)
                push!(result, GraphicsPointerShape(cox, start, cross_extent, extent,
                                                   :double_arrow_vertical))
            end
        end
        result
    end))

    outer_canvas = GraphicsCanvas(Cell(Int32(0)), Cell(Int32(0)),
                                  outer_w_cell, outer_h_cell,
                                  outer_elements,
                                  layout_none, true, Cell(nothing))

    child_iomaps = Tuple{Cell,Cell,Any}[]
    for i in 1:n
        push!(child_iomaps, (child_x[i], child_y[i], inner_iomaps[i]))
    end
    (canvas = outer_canvas, child_iomaps = child_iomaps)
end

map_reference_forward(::WidgetSplitPaneToGraphicsCanvas, iomap, reference) = _map_child_forward(iomap, reference)

# The split's input has `.elements[i]` (a CellVector). When the i-th slot
# wraps the child in a LayoutConstraint, the projector recurses into
# `.child` of the constraint; the backward map must account for that to
# re-root the inner path.
function map_reference_backward(p::WidgetSplitPaneToGraphicsCanvas, iomap::ChildrenIoMap, reference)
    reference === nothing && return nothing
    find_reference_point(reference) === nothing || return _map_child_point(iomap, reference)
    # Without a slot index this function can't disambiguate which child;
    # leave path-bearing translation to `read_intent` (which tracks the
    # slot it actually routed to). Cell-cursor mapping for the split's
    # selection is not currently used.
    return nothing
end

# Extra pixels on each side of a splitter's `thickness`-wide gap that still
# count as a grab, so a 1 px hairline is easy to catch with the cursor.
const _SPLITTER_GRAB_TOL = 3

# Main-axis screen coordinate of a child slot (its top-left in the split's own
# coordinate frame — the same frame the reader receives events in).
_split_child_main_pos(entry, orientation::Symbol) =
    (entry::Tuple{Cell,Cell,Any}; orientation === :horizontal ? Int(entry[1][]) : Int(entry[2][]))

# The band of the splitter before the child at `next_position` on the main axis,
# where a press grabs it, as `(start, extent)`: the `thickness`-wide gap before
# that child, widened by `_SPLITTER_GRAB_TOL` on each side, both ends included.
# The reader and the region of the pointer shape both read it.
_get_splitter_band(next_position::Int, thickness::Int) =
    (next_position - thickness - _SPLITTER_GRAB_TOL, thickness + 2 * _SPLITTER_GRAB_TOL + 1)

# Index `k` (1-based) of the splitter band under `(x, y)`, or 0 if none.
# Splitter `k` occupies the `thickness`-wide gap immediately before child `k+1`
# (see the print cursor), widened on each side along the main axis.
function _splitter_band_hit(orientation::Symbol, child_iomaps::Vector,
                            thickness::Int, x::Int, y::Int)
    n = length(child_iomaps)
    coord = orientation === :horizontal ? x : y
    for k in 1:(n - 1)
        nxt = child_iomaps[k + 1]
        nxt === nothing && continue
        start, extent = _get_splitter_band(_split_child_main_pos(nxt, orientation), thickness)
        (start <= coord < start + extent) && return k
    end
    0
end

# Currently measured main-axis extent of every slot. Inner slots are the
# distance between consecutive child positions minus the splitter; the last slot
# fills to the far edge — the child canvas itself can't be trusted, as it may not
# expand to fill its slot. Used to seed `sizes` on the first drag so it starts
# from the on-screen layout.
#
# `content_main` is the extent the split divided: its canvas less its own box
# model on that axis. The first child sits at the leading inset, so the last slot
# is what is left of the content past that child's offset. Reading the canvas
# itself here instead took the far inset for a slot, and an asymmetric box model
# for a symmetric one.
function _split_measured_sizes(child_iomaps::Vector, orientation::Symbol,
                               thickness::Int, content_main::Int)
    n = length(child_iomaps)
    sizes = Vector{Int}(undef, n)
    pos(i) = _split_child_main_pos(child_iomaps[i], orientation)
    for i in 1:(n - 1)
        sizes[i] = pos(i + 1) - pos(i) - thickness
    end
    sizes[n] = max(0, content_main - (pos(n) - pos(1)))
    sizes
end

# Drag lifecycle for the splitter gaps. Returns an Operation when the event
# starts, continues, or ends a drag; `nothing` lets the event fall through to
# the normal child-routing path below. A `MouseDown` on a band starts a drag of
# the pane (`StartDragOperation`), so its moves come by the path of the pane,
# wherever the pointer is; `DragMove` resizes the two adjacent slots relative to
# the grab origin (so rounding doesn't accumulate); `DragEnd` ends it, and
# `DragCancel` puts back the sizes of the grab. All are marked as view state, so a
# history records no part of a drag.
function _split_drag_read(p::WidgetSplitPaneToGraphicsCanvas, iomap::ChildrenIoMap,
                          w::WidgetSplitPane, evt)
    child_iomaps = getfield(iomap, :child_iomaps)[]::Vector
    n = length(child_iomaps)
    n < 2 && return nothing
    orientation = w.orientation::Symbol
    thickness   = max(1, Int(p.splitter_stroke.width))
    active      = w.active_splitter::Int

    if evt isa MouseDown && evt.button === :left && active == 0
        k = _splitter_band_hit(orientation, child_iomaps, thickness, evt.x, evt.y)
        k == 0 && return nothing
        outer = iomap.output
        outer_main = outer isa GraphicsCanvas ?
                     (orientation === :horizontal ? Int(outer.w[]) : Int(outer.h[])) : 0
        inset_x, inset_y = _inset_total(p, w)
        content_main = max(0, outer_main - (orientation === :horizontal ? inset_x : inset_y))
        slot_sizes = _split_measured_sizes(child_iomaps, orientation, thickness, content_main)
        coord = orientation === :horizontal ? evt.x : evt.y
        return CompoundOperation(Any[
            ReplaceViewStateOperation(StartSplitterDragOperation(w, k, coord, slot_sizes)),
            StartDragOperation(EmptyReference(), nothing),
            make_screen_pointer_shape_operation(orientation === :horizontal ?
                                                :double_arrow_horizontal : :double_arrow_vertical)])
    elseif evt isa DragMove && active != 0
        anchor = w.drag_anchor
        anchor === nothing && return nothing
        k = active
        (1 <= k && k + 1 <= n) || return nothing
        axis   = orientation === :horizontal ? :x : :y
        coord  = orientation === :horizontal ? evt.x : evt.y
        delta  = coord - anchor.coord
        size_a = anchor.size_a
        size_b = anchor.size_b
        elem_a = w.elements[k]
        elem_b = w.elements[k + 1]
        min_a, max_a = layout_min(elem_a, axis, size_a), layout_max(elem_a, axis, size_a)
        min_b, max_b = layout_min(elem_b, axis, size_b), layout_max(elem_b, axis, size_b)
        # Move the boundary by `delta`, conserve the pair's total, and keep both
        # slots within their min/max: clamp A, give/take the rest from B, then
        # re-derive A from the clamped B so the sum is exactly preserved.
        new_a = clamp(size_a + delta, min_a, max_a)
        new_b = clamp(size_b - (new_a - size_a), min_b, max_b)
        new_a = clamp(size_a + size_b - new_b, min_a, max_a)
        new_b = size_a + size_b - new_a
        return ReplaceViewStateOperation(ResizeSplitPaneOperation(w, k, new_a, new_b))
    elseif evt isa DragEnd && active != 0
        return CompoundOperation(Any[ReplaceViewStateOperation(EndSplitterDragOperation(w)),
                                     make_screen_pointer_shape_operation(nothing)])
    elseif evt isa DragCancel && active != 0
        ending = CompoundOperation(Any[ReplaceViewStateOperation(EndSplitterDragOperation(w)),
                                       make_screen_pointer_shape_operation(nothing)])
        anchor = w.drag_anchor
        (anchor === nothing || !(1 <= active && active + 1 <= n)) && return ending
        return CompoundOperation(Any[
            ReplaceViewStateOperation(ResizeSplitPaneOperation(w, active, anchor.size_a,
                                                               anchor.size_b)),
            ending.operations...])
    end
    nothing
end

function read_intent(p::WidgetSplitPaneToGraphicsCanvas, iomap::ChildrenIoMap, evt)
    w = iomap.input
    # The parts of the drag of a divider come by the path of the pane, wherever
    # the pointer is, so a divider does not stop where the pane ends.
    w isa WidgetSplitPane && evt isa Union{DragMove, DragEnd, DragCancel} &&
        return _split_drag_read(p, iomap, w, evt)
    w isa WidgetSplitPane && evt isa MouseMove && return _read_split_move(iomap, w, evt)
    _outside_widget(iomap, evt) && return nothing
    if w isa WidgetSplitPane
        drag = _split_drag_read(p, iomap, w, evt)
        drag !== nothing && return drag
    end
    child_iomaps = getfield(iomap, :child_iomaps)[]::Vector
    # Tab traversal (Stage 2): distributed focus advance, handled before the
    # selection-only coordless routing.
    if w isa WidgetSplitPane && evt isa KeyDown && evt.key === :tab
        return _split_tab(w, child_iomaps, evt)
    end
    res = @gesture_case evt begin
        MouseScroll => _route_split_event(child_iomaps, evt.x, evt.y,
            (x, y) -> MouseScroll(evt.dx, evt.dy, x, y; time = evt.time))
        MouseClick => _route_split_event(child_iomaps, evt.x, evt.y,
            (x, y) -> MouseClick(evt.button, x, y, evt.count, evt.modifiers;
                                 time = evt.time))
        # A dwell goes to the slot at its point, as a click does; a dwell on a
        # splitter is on the pane itself.
        MouseDwell => _route_split_event(child_iomaps, evt.x, evt.y,
            (x, y) -> shift_event_position(evt, x - evt.x, y - evt.y))
        # A press and a release route to the slot *under the pointer*, exactly as
        # the composite does. A press on a divider was already taken above by
        # `_split_drag_read`, so a `MouseDown`/`MouseUp` reaching here belongs to a
        # child.
        MouseDown => _route_split_press(child_iomaps, evt.x, evt.y,
            (x, y) -> MouseDown(evt.button, x, y, evt.modifiers; time = evt.time))
        MouseUp => _route_split_event(child_iomaps, evt.x, evt.y,
            (x, y) -> MouseUp(evt.button, x, y, evt.modifiers; time = evt.time))
        _ => begin
            # Forward keyboard (and other coordless) events to the child the
            # forward-projected selection points at, so the keystroke reaches the
            # focused descendant. When the split carries no such selection, route
            # nowhere (return nothing) — selection is authoritative, with no
            # try-each-slot fallback. See package/visual/doc/widget.md.
            slot = iomap.input isa WidgetSplitPane ?
                   _selected_split_slot(iomap.input, length(child_iomaps)) : 0
            slot == 0 ? nothing :
                        _forward_split_event_slot(child_iomaps, evt, slot)
        end
    end
    res === nothing && return read_container_gesture(nothing, evt, iomap.input)
    op, slot_idx = res
    steps = _get_split_slot_steps(iomap.input, slot_idx)
    read_container_gesture(reroot_operation(op, steps), evt, iomap.input; steps)
end

# The steps from a split pane to what slot `slot` shows. The slot can be wrapped in
# a LayoutConstraint; then the printer descended into `.child`, and the path walks
# through it.
function _get_split_slot_steps(w, slot::Int)
    steps = (FieldReferenceStep("elements"), RangeReferenceStep(slot - 1, slot))
    w.elements[slot] isa LayoutConstraint ? (steps..., FieldReferenceStep("child")) : steps
end

# A move of the pointer: the slot that the pane's own mouse target names (the
# pointer leaves it), then the slot under the point, each re-rooted into its slot.
# A point on a splitter is on the pane itself.
function _read_split_move(iomap::ChildrenIoMap, w::WidgetSplitPane, evt::MouseMove)
    child_iomaps = getfield(iomap, :child_iomaps)[]::Vector
    new = _outside_widget(iomap, evt) ? nothing :
          _route_split_event(child_iomaps, evt.x, evt.y,
              (x, y) -> MouseMove(x, y, evt.buttons, evt.modifiers; time = evt.time))
    new_answer = new === nothing ? nothing :
                 reroot_operation(new[1], _get_split_slot_steps(w, new[2]))
    old = _get_elements_slot(get_mouse_target(w), length(child_iomaps))
    (old == 0 || (new !== nothing && new[2] == old) || child_iomaps[old] === nothing) &&
        return new_answer
    entry = child_iomaps[old]
    old_answer = read_child_leave(last(entry), evt, get_child_frame_offset(entry)...)
    join_move_answers(reroot_operation(old_answer, _get_split_slot_steps(w, old)), new_answer)
end

# Tab traversal for a split pane (Stage 2), mirroring `_composite_tab` but with the
# split's slot shape: slots live under `elements[i]`, optionally wrapped in a
# `LayoutConstraint` (then the path walks through `.child`). `get_first_focusable_path`
# descends through the LayoutConstraint's `child` field generically, so the advance
# path is correct without special-casing; only the *delegate* re-rooting needs the
# `.child` step (as the reader above does).
function _split_tab(w::WidgetSplitPane, child_iomaps::Vector, evt)
    n = length(child_iomaps)
    reverse = evt.modifiers.shift
    i = _selected_split_slot(w, n)
    if i == 0
        sub = reverse ? get_last_focusable_path(w) : get_first_focusable_path(w)
        return sub === nothing ? nothing : ReplaceSelectionOperation(sub)
    end
    deleg = _forward_split_event_slot(child_iomaps, evt, i)
    if deleg !== nothing
        op, slot = deleg
        return reroot_operation(op, _get_split_slot_steps(w, slot))
    end
    j = get_next_focusable_index(w.elements, i, reverse)
    j == 0 && return nothing
    sub = reverse ? get_last_focusable_path(w.elements[j]) : get_first_focusable_path(w.elements[j])
    sub === nothing && return nothing
    ReplaceSelectionOperation(ConcreteReference(FieldReferenceStep("elements"),
        ConcreteReference(RangeReferenceStep(j - 1, j), sub)))
end

# The split slot the node's forward-projected selection points at. The
# projected selection has the shape `elements[slot].child.<rest>`, so the
# unit-range step right after the `elements` field names the slot. Returns 0
# when the split carries no such selection (route by fallback then).
function _selected_split_slot(w::WidgetSplitPane, n::Int)
    sel = getfield(w, :selection)[]
    sel = sel
    sel isa ConcreteReference || return 0
    (sel.head isa FieldReferenceStep && sel.head.name == "elements") || return 0
    t = sel.tail
    (t isa ConcreteReference && t.head isa RangeReferenceStep) || return 0
    slot = t.head.start + 1
    1 <= slot <= n ? slot : 0
end

# Forward a coordless event to the single split slot the selection points at,
# returning `(op, slot)` only when that child produced an `Operation`.
function _forward_split_event_slot(child_iomaps::Vector, evt, slot::Int)
    (1 <= slot <= length(child_iomaps)) || return nothing
    entry = child_iomaps[slot]
    entry === nothing && return nothing
    (_, _, cim) = entry::Tuple{Cell,Cell,Any}
    result = read_intent(cim.projection, cim, evt)
    result isa Operation ? (result, slot) : nothing
end

# A press, routed like a click and then — when the pointer is over nothing drawn —
# offered to the slots anyway. **A nested split's own splitter lives in exactly
# that gap**: it is drawn inside the child, but the parent hit-tests the child's
# canvas first, and a hairline between two panes is not a hit. Without this, only
# the outermost splitter can ever be grabbed.
function _route_split_press(child_iomaps::Vector, x::Int, y::Int, make_evt)
    hit = _route_split_event(child_iomaps, x, y, make_evt)
    hit === nothing || return hit
    for (i, entry) in enumerate(child_iomaps)
        entry === nothing && continue
        (x_cell, y_cell, cim) = entry::Tuple{Cell,Cell,Any}
        canvas = cim.output
        canvas isa GraphicsCanvas || continue
        result = read_intent(cim.projection, cim,
                             make_evt(x - Int(x_cell[]) - Int(canvas.x),
                                      y - Int(y_cell[]) - Int(canvas.y)))
        result === nothing || return (result, i)
    end
    nothing
end

function _route_split_event(child_iomaps::Vector, x::Int, y::Int, make_evt)
    for (i, entry) in enumerate(child_iomaps)
        point = _find_widget_child_point(entry, x, y)
        point === nothing && continue
        (lx, ly) = point
        result = shift_operation_position(read_child_event(last(entry), make_evt(lx, ly)),
                                          x - lx, y - ly)
        result !== nothing && return (result, i)
    end
    nothing
end

# ── WidgetTabbedPane ────────────────────────────────────────────────────────

# Shared tab-strip layout, so the printer's drawing and the reader's hit-testing /
# scroll-clamping agree exactly (including any per-tab icon width — measuring text
# only would shift the reader's tab boundaries left of where they are drawn). Returns
# a NamedTuple of the content offset, the tab padding, the strip height, the natural
# strip width, one tuple per tab — `(label, icon, icon_w, gap, x, rw, button_w,
# buttons, text_w, badges)`, where `x`/`rw` are the tab's left edge and full width in
# strip coordinates, `button_w` is the width of its button column (0 when it has
# none), `buttons` says what the column holds: `:none`, `:close`, `:duplicate`, or
# `:both`, the `+` above the `x`, `text_w` is the width of the label's text, and
# `badges` holds a `(badge, width, height)` for each badge after the text — and the
# new-tab button's box (`new_x`/`new_w`, `new_w` 0 when the pane has no `new_tab`).
#
# The first six fields come in the order a positional destructure reads them.
function _tab_strip_geometry(p::WidgetTabbedPaneToGraphicsCanvas, w::WidgetTabbedPane)
    cox, coy = _content_offset(p, w)
    sel_pad = p.tab_padding
    # The em height sizes the buttons, and gives an empty strip its height — a pane
    # with no tabs still shows a new-tab button, which is the state a fresh layout
    # starts in.
    _, em_h = _text_size(p.measure, p.font, "M")
    closable = w.closable === true
    duplicable = w.duplicable === true
    tabs = Any[]   # (label, icon, icon_w, gap, x, rw, button_w, buttons, text_w, badges)
    # An icon and a button are a square of one line times `icon_size`, and the
    # row is as tall as the largest of them and the line.
    new_side = w.new_tab === true ? scale_length(em_h, p.icon_size) : 0
    tab_h = max(em_h, new_side)
    x = cox
    for pair in w.selector_element_pairs
        selector = pair.selector
        label = _get_tab_selector_text(selector)
        icon  = _get_tab_icon(selector, pair.icon)
        tw, th = _text_size(p.measure, p.font, label)
        iw  = icon_width(icon, scale_length(th, p.icon_size))
        gap = iw > 0 ? p.label_gap : 0
        badges = Any[]
        badges_w = 0
        for badge in _get_tab_badges(selector)
            bw, bh = _measure_badge(p.badge, badge)
            push!(badges, (badge, bw, bh))
            badges_w += p.label_gap + bw
            tab_h = max(tab_h, bh)
        end
        buttons = _get_tab_buttons(closable, duplicable && pair.duplicable === true)
        button_w = buttons === :none ? 0 : scale_length(th, p.icon_size)
        button_gap = button_w > 0 ? p.label_gap : 0
        rw  = tw + badges_w + iw + gap + button_w + button_gap + 2 * sel_pad
        push!(tabs, (label, icon, iw, gap, x, rw, button_w, buttons, tw, badges))
        x += rw
        tab_h = max(tab_h, th, iw, button_w)
    end
    sel_h = tab_h + 2 * sel_pad
    new_w = w.new_tab === true ? new_side + 2 * sel_pad : 0
    strip_w = (isempty(tabs) && new_w == 0) ? 0 : (x + new_w - cox)
    (cox = cox, coy = coy, pad = sel_pad, height = sel_h, strip_w = strip_w,
     tabs = tabs, new_x = x, new_w = new_w, line = em_h)
end

# The icon of a tab: the icon of its label, else the icon of its page.
_get_tab_icon(selector::WidgetTabLabel, page_icon) =
    selector.icon === nothing ? page_icon : selector.icon
_get_tab_icon(selector, page_icon) = page_icon

# The color of a tab's icon: the text color of the role of its label, else `color`.
function _get_tab_icon_color(p::WidgetTabbedPaneToGraphicsCanvas, selector::WidgetTabLabel, color)
    role = selector.icon_role
    role === nothing && return color
    role in _BADGE_ROLES ||
        throw(ArgumentError("a tab label has no role $(repr(role)); the roles are $(_BADGE_ROLES)"))
    getproperty(p.badge, Symbol(role, "_label_text")).color
end
_get_tab_icon_color(p::WidgetTabbedPaneToGraphicsCanvas, selector, color) = color

# The badges a tab draws after its text: the visible badges of its label.
function _get_tab_badges(selector::WidgetTabLabel)
    badges = selector.badges
    badges === nothing && return WidgetBadge[]
    WidgetBadge[badge for badge in badges if badge isa WidgetBadge && badge.visible !== false]
end
_get_tab_badges(selector) = WidgetBadge[]

# What the button column of a tab holds.
_get_tab_buttons(closable::Bool, duplicable::Bool) =
    closable && duplicable ? :both :
    closable               ? :close :
    duplicable             ? :duplicate : :none

# The button column's box inside a tab tuple: its left edge and its width, or
# `nothing` when the tab has none.
function _get_tab_button_box(tab, sel_pad::Int)
    button_w = tab[7]
    button_w > 0 ? (tab[5] + tab[6] - sel_pad - button_w, button_w) : nothing
end

# The part of the strip a point on tab `tab` lands on: `:close`, `:duplicate`, or
# `:tab` for the rest. A column that holds both buttons is split across the strip's
# height: the `+` above, the `x` below.
function _get_tab_part(g, tab, xx::Int, yy::Int)
    box = _get_tab_button_box(tab, g.pad)
    (box !== nothing && xx >= box[1] && xx < box[1] + box[2]) || return :tab
    buttons = tab[8]
    buttons === :both || return buttons
    yy < g.coy + g.height ÷ 2 ? :duplicate : :close
end

# Draw the button column of a tab. A single button fills the column at the
# height of the label; two share it, each centred in its half of the strip.
function _push_tab_buttons!(result, g, tab, color)
    box = _get_tab_button_box(tab, g.pad)
    box === nothing && return
    x, w = box
    buttons = tab[8]
    if buttons === :both
        half = g.height ÷ 2
        side = min(w, half)
        icon_x = x + (w - side) ÷ 2
        _push_icon!(result, :plus, icon_x, g.coy + (half - side) ÷ 2, side, color)
        _push_icon!(result, :close, icon_x, g.coy + half + (g.height - half - side) ÷ 2,
                    side, color)
    else
        _push_icon!(result, buttons === :duplicate ? :plus : :close, x,
                    g.coy + g.pad + (g.height - 2 * g.pad - w) ÷ 2, w, color)
    end
end

# Rendered horizontal scroll offset of the strip: the stored `tab_scroll` clamped to
# the strip's overflow past the viewport (0 when it fits). Shared by printer (draws
# at `-offset`) and reader (offsets hit-testing and the scroll delta base).
_tab_scroll_offset(w::WidgetTabbedPane, strip_w::Int, view_w::Int) =
    clamp(Int(getfield(w, :tab_scroll)[]), 0, max(0, strip_w - view_w))

# ── The name that holds the caret ───────────────────────────────────────────
#
# A tab bar draws its names as plain text, except the one that holds the caret.
# That name is drawn through a text view of one span, as a `WidgetText` draws a
# plain value, so the text domain draws its caret as it draws every other caret.
# The view only draws: the keys that edit a name go to the document that owns
# the name. The caret is `selector_element_pairs[i].selector{k}`, or
# `selector_element_pairs[i].selector.text{k}` in the text of a `WidgetTabLabel`.

# The tab whose name holds the caret, and the caret position, or `nothing`.
function _find_tab_name_caret(selection)
    selection isa Reference || return nothing
    steps = get_reference_steps(strip_reference_types(selection))
    length(steps) in (4, 5) || return nothing
    (steps[1] isa FieldReferenceStep && steps[1].name == "selector_element_pairs" &&
     steps[2] isa RangeReferenceStep &&
     steps[3] isa FieldReferenceStep && steps[3].name == "selector") || return nothing
    length(steps) == 5 &&
        !(steps[4] isa FieldReferenceStep && steps[4].name == "text") && return nothing
    caret = steps[end]
    caret isa RangeReferenceStep || return nothing
    (steps[2].stop, caret.start)
end

# The view of the name that holds the caret, in the style of the selected tab,
# drawn with a `TextToGraphics` of its own.
function _print_tab_name_view(p, recursion, w::WidgetTabbedPane, caret::Cell, ctx)
    span = TextString(() -> begin
        found = caret[]
        pairs = w.selector_element_pairs
        (found === nothing || !(1 <= found[1] <= length(pairs))) ? "" :
            _get_tab_selector_text(pairs[found[1]].selector)
    end, _get_state_text(p, w, :tab; state = :selected))
    view = TextBlock(span)
    set_cell_computation!(getfield(view, :selection), () -> begin
        found = caret[]
        found === nothing ? nothing : make_flat_range_reference(found[2], found[2])
    end)
    measure = p.measure
    make_reconciled_child_iomap_cell(() -> view,
                          v -> print_document(TextToGraphics(measure = measure), recursion, v, ctx))
end

function print_document(p::WidgetTabbedPaneToGraphicsCanvas, recursion, w::WidgetTabbedPane, ctx)
    w.visible == false && return ChildrenIoMap(p, w, _empty_canvas(), Cell(Any[]))
    pairs = w.selector_element_pairs
    child_iomaps = Any[]
    if isempty(pairs)
        return ChildrenIoMap(p, w, _empty_canvas(), Cell(child_iomaps))
    end

    box = _get_box_insets(p, w)          # stable — independent of the tab count
    colors = _get_box_colors(p, w)
    cox, coy = _content_offset(p, w)     # stable — independent of the tab count
    # Reactive tab-strip geometry: re-derives when a tab is added / removed, so the
    # strip and everything sized from it (`sel_h`, `strip_w`, the tab tuples) reflows.
    geom = Cell(@computation _tab_strip_geometry(p, w))

    sel_cell = getfield(w, :selection)
    name_caret = Cell(@computation _find_tab_name_caret(get_stored_selection(w)))
    name_view = _print_tab_name_view(p, recursion, w, name_caret, ctx)

    _active_idx(sel, ntabs) = begin
        i = _tab_index_from_selection(sel, ntabs)
        i == 0 ? 1 : i
    end

    selector_cv = CellVector(@computation begin
        g = geom[]
        sel_pad, sel_h, tabs = g.pad, g.height, g.tabs
        active = _active_idx(get_stored_selection(w), length(tabs))
        result = Any[]
        tab_radius = p.corner_radius
        tab_strip_color = _get_part_color(w, :tab_strip_color, p.tab_strip_color)
        # The tab strip's own fill behind the whole tab row.
        _push_panel!(result, cox, coy, g.strip_w, sel_h; fill=tab_strip_color, radius=tab_radius)
        # Each tab is a canvas of its own in the strip, in the order of the tabs,
        # with no size of its own: the header of the tab, the image of its
        # `selector`. No other element of the strip is a canvas.
        for i in eachindex(tabs)
            label, icon, iw, gap, tx, rw, _, _, tw, badges = tabs[i]
            state = i == active ? :selected : nothing
            tab_color = _get_state_color(p, w, :tab; state)
            header = Any[]
            if i == active
                # Active tab: a raised background pill.
                _push_panel!(header, tx, coy, rw, sel_h; fill=tab_color, radius=tab_radius)
            end
            # A press on a tab opens it, and on a tab of a pane that drags tabs it
            # grabs it too.
            push!(header, GraphicsPointerShape(tx, coy, rw, sel_h,
                                               w.draggable === true ? :open_hand : :pointing_hand))
            tab_text = _get_state_text(p, w, :tab; state)
            fg = tab_text.color
            iw > 0 && _push_icon!(header, icon, tx + sel_pad, coy + sel_pad + (sel_h - 2 * sel_pad - iw) ÷ 2,
                                  iw, _get_tab_icon_color(p, pairs[i].selector, fg))
            name_x, name_y = tx + sel_pad + iw + gap, coy + sel_pad + (sel_h - 2 * sel_pad - g.line) ÷ 2
            found = name_caret[]
            if found !== nothing && found[1] == i
                push!(header, _make_canvas(name_x, name_y, Any[name_view[].output]))
            else
                _push_text!(header, p.measure, tab_text.font, label, name_x, name_y, fg)
            end
            # The badges follow the text, each centred on the height of the strip.
            badge_x = name_x + tw
            for (badge, bw, bh) in badges
                badge_x += p.label_gap
                push!(header, _make_canvas(badge_x, coy + (sel_h - bh) ÷ 2,
                                           _build_badge_elements(p.badge, badge, bw, bh)))
                badge_x += bw
            end
            # The button column sits at the tab's right edge, tinted like its label.
            _push_tab_buttons!(header, g, tabs[i], fg)
            button_box = _get_tab_button_box(tabs[i], g.pad)
            button_box === nothing ||
                push!(header, GraphicsPointerShape(button_box[1], coy, button_box[2], sel_h,
                                                   :pointing_hand))
            push!(result, GraphicsCanvas(Int32(0), Int32(0), Int32(0), Int32(0),
                                         CellVector(Cell[Cell(e) for e in header]),
                                         layout_none, true, Cell(nothing)))
        end
        # The new-tab button follows the last tab.
        new_side = g.new_w - 2 * sel_pad
        g.new_w > 0 && _push_icon!(result, :plus, g.new_x + sel_pad, coy + sel_pad + (sel_h - 2 * sel_pad - new_side) ÷ 2,
                                   new_side, _get_part_text(w, :tab_text, p.tab_text).color)
        g.new_w > 0 && push!(result, GraphicsPointerShape(g.new_x, coy, g.new_w, sel_h, :pointing_hand))
        result
    end)

    # Seed a reduced available extent for the tab content. The content lives
    # inside the pane's border (offset `cox`/`coy`) and below the tab strip,
    # so subtract the horizontal insets from the width and the tab strip plus
    # vertical insets from the height — otherwise the content is allocated the
    # full extent yet drawn at the inset, overhanging the pane (cf.
    # WidgetTitlePane above).
    avail_w = get_exact_width(ctx)
    avail_h = get_exact_height(ctx)
    # Distinct names: `tx` is reused below as a tab x-position inside the
    # selector builder loop, so capturing it here would alias that closure's
    # local and clobber the selector viewport width.
    inset_x, inset_y = _inset_total(p, w)
    # The page's extent inside a slot; with no slot the page is as large as what
    # it holds.
    avail_w_inner = avail_w === nothing ? nothing :
        Cell(@computation max(0, Int(avail_w[]) - inset_x))
    avail_h_inner = avail_h === nothing ? nothing :
        Cell(@computation max(0, Int(avail_h[]) - geom[][4] - inset_y))   # geom[][4] == sel_h
    # The content gets the pane's range less the insets, and less the tab strip
    # on the height, in the same state: a slot stays a slot and an edge stays an
    # edge.
    content_ctx = with_inner_size(ctx; width = inset_x, height = Cell(@computation geom[][4] + inset_y))
    # Reconcile the per-tab content iomaps so a tab add / remove reflows the content
    # through the held iomap; a non-widget slot reconciles to `nothing` (no content).
    all_cims = make_reconciled_child_iomaps_cell(
        () -> Any[pair.element for pair in w.selector_element_pairs],
        (i, content) -> content !== nothing ? print_child(recursion, content, content_ctx) : nothing)

    # The page. A tabbed pane hands its content a bounded extent above, so it is the
    # tabbed pane that keeps the promise: the page is a viewport at the content
    # origin, sized to the slot the content was offered. Without it the page is a
    # plain canvas and a content document — drawn as wide as it is — runs across the
    # next pane and over the tab strip.
    #
    # Per bounded axis. An axis the parent did not offer was never bounded, so there
    # is nothing to clip against and the page takes the content's own extent there.
    content_cv = CellVector(@computation begin
        cims = all_cims[]
        sel_h = geom[][4]
        active = _active_idx(get_stored_selection(w), length(cims))
        idx = active == 0 ? 1 : active
        cim = (1 <= idx <= length(cims)) ? cims[idx] : nothing
        page_w, page_h = 0, 0
        if cim !== nothing
            page_w, page_h = _compute_page_extent(cim, avail_w_inner, avail_h_inner)
        end
        result = Any[]
        page_color = _get_part_color(w, :page_color, p.page_color)
        _push_panel!(result, cox, coy + sel_h, max(geom[][5], page_w), page_h; fill = page_color)
        cim === nothing && return result
        push!(result, GraphicsViewport(Cell(Int32(cox)), Cell(Int32(coy + sel_h)),
                             Cell(Int32(page_w)), Cell(Int32(page_h)),
                             Cell(_make_canvas(0, 0, Any[cim.output])),
                             Cell(affine_identity),
                             Cell(nothing)))
        result
    end)

    # The generic box (margin/border/padding/content, all transparent by
    # default) around the strip and the page together.
    box_cv = CellVector(@computation begin
        cims = all_cims[]
        sel_h = geom[][4]
        active = _active_idx(get_stored_selection(w), length(cims))
        idx = active == 0 ? 1 : active
        cim = (1 <= idx <= length(cims)) ? cims[idx] : nothing
        page_w, page_h = 0, 0
        if cim !== nothing
            page_w, page_h = _compute_page_extent(cim, avail_w_inner, avail_h_inner)
        end
        result = Any[]
        _push_box_parts!(result, box, colors, max(geom[][5], page_w), sel_h + page_h)
        result
    end)

    # Clip the selector row to the pane's own width so a tab strip wider than
    # the tabbed pane cannot overflow the widget. When the parent seeded an
    # available width, clip to the content box (allocation minus insets) using the
    # distinctly-named `inset_x` (computed above); otherwise there is no constraint,
    # so the viewport is as wide as the strip and clips nothing.
    sel_view_w = if avail_w === nothing
        Cell(@computation Int32(geom[][5]))       # strip_w — reactive on the tab count
    else
        Cell(@computation Int32(max(0, Int(avail_w[]) - inset_x)))
    end
    # Horizontal scroll: when the strip is wider than the viewport, shift its inner
    # canvas left by the clamped `tab_scroll` so overflow tabs scroll into view (a
    # wheel over the strip drives it — see read_intent). Reactive on both the
    # stored offset and the viewport width.
    scroll_x = Cell(@computation Int32(-cox - _tab_scroll_offset(w, geom[][5], Int(sel_view_w[]))))
    # The viewport sits at the content origin; its inner canvas is shifted back
    # by that origin (minus any scroll) so the strip elements keep their original
    # coordinates at scroll 0.
    selector_viewport = GraphicsViewport(
        Cell(Int32(cox)), Cell(Int32(coy)), sel_view_w, Cell(@computation Int32(geom[][4])),   # sel_h reactive
        Cell(GraphicsCanvas(scroll_x, Cell(Int32(-coy)), Int32(0), Int32(0),
                            selector_cv, layout_none, true, Cell(nothing))),
        Cell(affine_identity),
        Cell(nothing))

    # The ring over the page, while the document the page shows is selected as a
    # whole. The page's document is in the tree, so its own selection says so.
    ring = make_selection_ring(() -> begin
        cims = all_cims[]
        idx = _active_idx(get_stored_selection(w), length(cims))
        (1 <= idx <= length(cims) && cims[idx] !== nothing) || return nothing
        page = _get_page_document(w, idx)
        _is_whole_selected_page(page) || return nothing
        page_w, page_h = _compute_page_extent(cims[idx], avail_w_inner, avail_h_inner)
        (cox, coy + geom[][4], page_w, page_h)
    end, p.graphics_style)

    # A tabbed pane offered an extent reports that extent, not what its strip and
    # its page happen to reach: it bounded them, so its box is its own (§3b).
    inner = _make_canvas(0, 0, Any[
        GraphicsCanvas(box_cv),
        selector_viewport,
        GraphicsCanvas(content_cv),
        ring,
    ])
    canvas = (avail_w === nothing && avail_h === nothing) ? inner :
        GraphicsCanvas(Cell(Int32(0)), Cell(Int32(0)),
                       avail_w === nothing ? inner.w : Cell(@computation Int32(max(0, Int(avail_w[])))),
                       avail_h === nothing ? inner.h : Cell(@computation Int32(max(0, Int(avail_h[])))),
                       CellVector(Cell[Cell(inner)]),
                       layout_none, true, Cell(nothing))
    # The (x, y, cim) tuples reflow with the reconciled per-tab content iomaps.
    child_iomaps = Cell(@computation Any[(cox, coy + geom[][4], cim) for cim in all_cims[] if cim !== nothing])
    ChildrenIoMap(p, w, canvas, child_iomaps)
end

# The extent of the page of a tabbed pane: the slot offered on each axis, else
# what the content reaches. The content is measured only for an axis with no
# slot, because its size reads every graphic in it: a measure that is not used
# would rebuild the page on every change inside it.
function _compute_page_extent(cim, avail_w_inner, avail_h_inner)
    reach() = get_graphics_size(cim.output)
    (avail_w_inner === nothing ? Int(reach()[1]) : max(0, Int(avail_w_inner[])),
     avail_h_inner === nothing ? Int(reach()[2]) : max(0, Int(avail_h_inner[])))
end

# A page maps as the pane shows it: the open page to the pane's own canvas, a
# page that is not open to nothing, the `selector` of any page to its header in
# the tab strip, and the `element` of the open page to the content.
function map_reference_forward(::WidgetTabbedPaneToGraphicsCanvas, iomap, reference)
    reference isa Reference || return nothing
    page = _find_tab_page_place(strip_reference_types(reference))
    page === nothing && return _map_child_forward(iomap, reference)
    index, rest = page
    w = get_iomap_input(iomap)
    w isa WidgetTabbedPane || return nothing
    if rest isa EmptyReference
        active = _tab_index_from_selection(get_stored_selection(w), length(w.selector_element_pairs))
        return index == (active == 0 ? 1 : active) ? EmptyReference() : nothing
    end
    head = get_reference_head(rest)
    (head isa FieldReferenceStep && head.name == "selector") || return _map_child_forward(iomap, reference)
    get_reference_tail(rest) isa EmptyReference || return nothing
    _find_tab_header_reference(iomap, index)
end

# `selector_element_pairs[i]` and the rest after it, as `(i, rest)`, or `nothing`.
function _find_tab_page_place(reference)
    reference isa ConcreteReference || return nothing
    head = get_reference_head(reference)
    (head isa FieldReferenceStep && head.name == "selector_element_pairs") || return nothing
    rest = get_reference_tail(reference)
    rest isa ConcreteReference || return nothing
    step = get_reference_head(rest)
    (step isa ARangeReferenceStep && is_element_reference_step(step)) || return nothing
    (step.start + 1, get_reference_tail(rest))
end

# The header of tab `index`: the canvas number `index` of the tab strip, which is
# the content of the pane's first viewport.
function _find_tab_header_reference(iomap, index::Int)
    output = unwrap_cell(get_iomap_output(iomap))
    strip = _find_first_viewport_content(output)
    strip isa GraphicsCanvas || return nothing
    elements = unwrap_cell(getfield(strip, :elements))
    elements isa Union{AbstractVector, CellVector} || return nothing
    count = 0
    for k in 1:length(elements)
        header = unwrap_cell(elements[k])
        header isa GraphicsCanvas || continue
        count += 1
        count == index && return find_node_reference(output, header; depth = 6)
    end
    nothing
end

# The content of the first viewport in `canvas`, level by level, at most three
# levels deep.
function _find_first_viewport_content(canvas)
    level = Any[canvas]
    for _ in 1:3
        next = Any[]
        for node in level
            node isa GraphicsCanvas || continue
            elements = unwrap_cell(getfield(node, :elements))
            elements isa Union{AbstractVector, CellVector} || continue
            for k in 1:length(elements)
                child = unwrap_cell(elements[k])
                child isa GraphicsViewport && return unwrap_cell(getfield(child, :content))
                push!(next, child)
            end
        end
        level = next
    end
    nothing
end

# A tabbed pane's input has `.selector_element_pairs[i]` (a Pair whose
# second member is the i-th tab's content widget). The reader prepends
# `selector_element_pairs[i]` to bubbled paths so the active tab is
# encoded; upstream projections (e.g. `PaneGroupToWidgetTabbedPane`)
# decode it. Without a slot index this generic mapper has nothing to add.
function map_reference_backward(p::WidgetTabbedPaneToGraphicsCanvas, iomap, reference)
    point = find_reference_point(reference)
    if point !== nothing
        header = _find_tab_header_at(p, iomap, point)
        return header === nothing ? _map_open_page_point(iomap, point) : header
    end
    # A bare `selector_element_pairs[i]` is a tab-strip click. This projection emits
    # it in its own input coordinates, so it maps back as itself; without the case
    # the generic reader re-targets it to `nothing` and the click is dropped before
    # any upstream projection can read it.
    if reference isa ConcreteReference && reference.head isa FieldReferenceStep &&
       reference.head.name == "selector_element_pairs"
        t = reference.tail
        (t isa ConcreteReference && t.head isa RangeReferenceStep && t.tail isa EmptyReference) &&
            return reference
    end
    return nothing
end

# A point in the page maps into the content of the open page, the one that the
# pane draws: the contents of the other pages are printed, at the same place, but
# not drawn.
function _map_open_page_point(iomap, point)
    iomap isa ChildrenIoMap || return nothing
    w = iomap.input
    w isa WidgetTabbedPane || return nothing
    pages = w.selector_element_pairs
    isempty(pages) && return nothing
    active = _tab_index_from_selection(get_stored_selection(w), length(pages))
    content = unwrap_cell(pages[active == 0 ? 1 : active].element)
    entries = Any[entry for entry in getfield(iomap, :child_iomaps)[]::Vector
                  if unwrap_cell(get_iomap_input(last(entry))) === content]
    _map_point_to_child(w, entries, point)
end

# The `selector` of the tab whose header is at `point`, the part that the header
# draws, or `nothing` when no header is there.
function _find_tab_header_at(p::WidgetTabbedPaneToGraphicsCanvas, iomap, point)
    iomap isa ChildrenIoMap || return nothing
    w = iomap.input
    w isa WidgetTabbedPane || return nothing
    strip_x = _tab_strip_coordinate(p, w, iomap, point.x, point.y)
    strip_x === nothing && return nothing
    index, _ = _find_tab_at_strip_point(_tab_strip_geometry(p, w), strip_x, point.y)
    index == 0 && return nothing
    annotate_reference_types(w, extend_reference(EmptyReference(), FieldReferenceStep("selector_element_pairs"),
                                                 ElementReferenceStep(index), FieldReferenceStep("selector")))
end

# Selector-viewport width as drawn (the clip box). Read back from the output so the
# reader clamps scroll / hit-tests against exactly what the printer produced; falls
# back to `strip_w` (no clip) when the pane is empty/invisible.
function _tab_view_w(iomap::ChildrenIoMap, strip_w::Int)
    canvas = iomap.output
    canvas isa GraphicsCanvas || return strip_w
    els = canvas.elements
    length(els) >= 1 || return strip_w
    vp = els[1]
    vp isa GraphicsViewport ? Int(vp.w[]) : strip_w
end

# The strip-space x of a point that lands in the tab strip, or `nothing` when it
# does not. A tab drawn at screen x sits at strip coordinate `x + scroll`, so every
# strip hit-test starts here.
function _tab_strip_coordinate(p::WidgetTabbedPaneToGraphicsCanvas, w::WidgetTabbedPane,
                               iomap, x::Int, y::Int)
    g = _tab_strip_geometry(p, w)
    (isempty(g.tabs) && g.new_w == 0) && return nothing
    (y >= g.coy && y < g.coy + g.height) || return nothing
    view_w = _tab_view_w(iomap, g.strip_w)
    (x >= g.cox && x < g.cox + view_w) || return nothing
    x + _tab_scroll_offset(w, g.strip_w, view_w)
end

# The 1-based tab a strip-space x lands on, or 0, and the part of it at `yy`:
# `:tab`, `:close` or `:duplicate` (see `_get_tab_part`).
function _find_tab_at_strip_point(g, xx::Int, yy::Int)
    for (i, t) in enumerate(g.tabs)
        tx, rw = t[5], t[6]
        (xx >= tx && xx < tx + rw) || continue
        return (i, _get_tab_part(g, t, xx, yy))
    end
    (0, :tab)
end

function read_intent(p::WidgetTabbedPaneToGraphicsCanvas, iomap::ChildrenIoMap, evt)
    child_iomaps = getfield(iomap, :child_iomaps)[]::Vector
    evt isa MouseMove && return _read_tabbed_pane_move(p, iomap, child_iomaps, evt)
    _outside_widget(iomap, evt) && return nothing
    # A dwell and a right click open, close and select no tab.
    is_outward_gesture(evt) && return _read_tabbed_pane_outward(p, iomap, evt)
    if evt isa MouseClick
        w = iomap.input
        if !(w isa WidgetTabbedPane)
            res = _route_active_tab(iomap, child_iomaps, evt)
            return _tab_prefix(res, iomap.input)
        end
        xx = _tab_strip_coordinate(p, w, iomap, evt.x, evt.y)
        if xx !== nothing
            g = _tab_strip_geometry(p, w)
            # The new-tab button first: it follows the last tab, so no tab box can
            # claim it.
            g.new_w > 0 && xx >= g.new_x && xx < g.new_x + g.new_w &&
                return OpenTabOperation(w)
            index, part = _find_tab_at_strip_point(g, xx, evt.y)
            index > 0 && part === :close && return CloseTabOperation(w, index)
            index > 0 && part === :duplicate && return DuplicateTabOperation(w, index)
            # A tab click is a selection change, nothing more. Emitted as this pane's
            # own local path, so the ordinary re-targeting carries it to the document
            # root: the walk then starts high enough to see a sibling group and mark
            # it dormant, which a widget-rooted write never could.
            index > 0 && return ReplaceSelectionOperation(Reference(
                                    FieldReferenceStep("selector_element_pairs"),
                                    ElementReferenceStep(index)))
        end
        return _read_tab_answer(w, evt, _route_active_tab(iomap, child_iomaps, evt))
    end
    if evt isa MouseScroll
        w = iomap.input
        if w isa WidgetTabbedPane
            cox, coy, sel_pad, sel_h, strip_w, tabs = _tab_strip_geometry(p, w)
            # A wheel over the strip scrolls it horizontally (the strip is a horizontal
            # row, so vertical wheel maps to horizontal motion); over the content it
            # scrolls the active tab as before.
            if !isempty(tabs) && evt.y >= coy && evt.y < coy + sel_h
                view_w = _tab_view_w(iomap, strip_w)
                max_s = max(0, strip_w - view_w)
                if max_s > 0
                    step, _ = _text_size(p.measure, p.font, "M")
                    delta = evt.dx != 0 ? evt.dx : -evt.dy
                    s = _tab_scroll_offset(w, strip_w, view_w)
                    new_s = clamp(s + delta * step, 0, max_s)
                    return _write_view_state(w, "tab_scroll", new_s)
                end
            end
        end
        return _tab_prefix(_route_active_tab(iomap, child_iomaps, evt), iomap.input)
    end
    # Coordinate-bearing events (drags and moves) target the *visible* tab
    # regardless of selection: a splitter drag inside the active tab must keep
    # receiving motion even when the pane carries no selection (the bootstrap case
    # the SplitPaneDrag tests cover), and a move must reach whatever the pointer is
    # over, not the selected tab. `_route_active_tab` translates coords into the
    # tab's frame.
    # A left button down on a tab of a `draggable` pane is a grab. The strip
    # resolves which tab; the projection that owns the tabs runs the drag from
    # there, because only it knows where a tab may be dropped. A down on the close
    # or the duplicate button is not a grab, and a down anywhere else routes to
    # the visible tab.
    if evt isa MouseDown && evt.button === :left
        w = iomap.input
        if w isa WidgetTabbedPane && w.draggable === true
            xx = _tab_strip_coordinate(p, w, iomap, evt.x, evt.y)
            if xx !== nothing
                index, part = _find_tab_at_strip_point(_tab_strip_geometry(p, w), xx, evt.y)
                index > 0 && part === :tab && return DragTabOperation(w, index)
            end
        end
    end
    if evt isa MouseDown || evt isa MouseUp || evt isa MouseMove
        return _tab_prefix(_route_active_tab(iomap, child_iomaps, evt), iomap.input)
    end
    # Coordless events (KeyDown, KeyPress, …): forward to the tab the selection
    # points at, or to nothing when the selection is not in this pane — selection
    # is authoritative, with no active-tab fallback for keyboard events (the
    # printer still falls back to tab 1 to *render* a tab). See widget.md.
    _tab_prefix(_route_selected_tab(iomap, child_iomaps, evt), iomap.input)
end

# A dwell or a right click on a tab header is read by the header and the
# documents around it: the pane draws the header itself, so the backward map of
# the point names it, as it names a part of a child that answers nothing
# (`read_child_part_gesture`). A dwell or a right click on the open page goes to
# the page, as a click does. Neither opens, closes or selects a tab.
function _read_tabbed_pane_outward(p::WidgetTabbedPaneToGraphicsCanvas,
                                   iomap::ChildrenIoMap, gesture)
    _find_tab_header_at(p, iomap, (x = gesture.x, y = gesture.y)) === nothing ||
        return read_child_part_gesture(iomap, gesture)
    w = iomap.input
    w isa WidgetTabbedPane || return read_container_gesture(nothing, gesture, w)
    child_iomaps = getfield(iomap, :child_iomaps)[]::Vector
    _read_tab_answer(w, gesture, _route_active_tab(iomap, child_iomaps, gesture))
end

# The answer of the open page that `res` names, `(operation, index)` or `nothing`,
# with the path of the page put before it (`_tab_prefix`), and read over the
# stretch of the pane for a dwell or a right click (`read_container_gesture`).
function _read_tab_answer(widget::WidgetTabbedPane, gesture, res)
    res === nothing && return read_container_gesture(nothing, gesture, widget)
    read_container_gesture(_tab_prefix(res, widget), gesture, widget;
                           steps = _get_tab_page_steps(widget, res[2]))
end

# The steps from a tabbed pane to the document that tab `idx` shows.
function _get_tab_page_steps(widget::WidgetTabbedPane, idx::Int)
    steps = (FieldReferenceStep("selector_element_pairs"),
             RangeReferenceStep(idx - 1, idx))
    widget.selector_element_pairs[idx] isa WidgetTabPage ?
        (steps..., FieldReferenceStep("element")) : steps
end

# A move of the pointer. The open page gets a move off it first when the
# pane's own mouse target is in that page and the point is not. Then the part at
# the point answers: a tab header is its `selector`, and the open page reads the
# move itself.
function _read_tabbed_pane_move(p::WidgetTabbedPaneToGraphicsCanvas, iomap::ChildrenIoMap,
                                child_iomaps::Vector, evt::MouseMove)
    w = iomap.input
    w isa WidgetTabbedPane || return nothing
    active = _active_tab_index(w, length(child_iomaps))
    entry = active == 0 ? nothing : child_iomaps[active]
    new_answer = nothing
    on_page = false
    if !_outside_widget(iomap, evt)
        header = _find_tab_header_at(p, iomap, (x = evt.x, y = evt.y))
        if header !== nothing
            new_answer = ReplaceMouseTargetOperation(header)
        elseif entry !== nothing
            (ox, oy, cim) = entry::Tuple{Int,Int,Any}
            canvas = cim.output
            if canvas isa GraphicsCanvas
                lx, ly = evt.x - ox - Int(canvas.x), evt.y - oy - Int(canvas.y)
                if hit_element_at(canvas, lx, ly) !== nothing
                    on_page = true
                    move = MouseMove(lx, ly, evt.buttons, evt.modifiers; time = evt.time)
                    answer = shift_operation_position(read_child_move(cim, move),
                                                      evt.x - lx, evt.y - ly)
                    new_answer = _prefix_tab_operation(answer, w, active)
                end
            end
        end
    end
    (entry === nothing || on_page || _find_mouse_target_page(w, length(child_iomaps)) != active) &&
        return new_answer
    old_answer = read_child_leave(last(entry), evt, get_child_frame_offset(entry)...)
    join_move_answers(_prefix_tab_operation(old_answer, w, active), new_answer)
end

# The tab whose page holds the part that the pane's mouse target names, or 0. A
# path to a header, `selector_element_pairs[i].selector`, is not in the page.
function _find_mouse_target_page(w::WidgetTabbedPane, n::Int)
    target = get_mouse_target(w)
    index = _tab_index_from_selection(target, n)
    index == 0 && return 0
    rest = target.head isa FieldReferenceStep ? target.tail.tail : target.tail
    is_header = rest isa ConcreteReference && rest.head isa FieldReferenceStep &&
                rest.head.name == "selector"
    is_header ? 0 : index
end

# Coordless routing: forward to the tab the selection points at, or nothing when
# the selection is not in this pane. Unlike `_route_active_tab` there is NO
# fallback to a default/visible tab — selection is authoritative for keyboard
# events. Coordless events need no coordinate translation, so `evt` is forwarded
# as-is. Returns (op, idx) with the 1-based tab number for `_tab_prefix`.
function _route_selected_tab(iomap::ChildrenIoMap, child_iomaps::Vector, evt)
    w = iomap.input
    w isa WidgetTabbedPane || return nothing
    idx = _tab_index_from_selection(get_stored_selection(w), length(child_iomaps))
    idx == 0 && return nothing
    entry = child_iomaps[idx]
    entry === nothing && return nothing
    (_, _, cim) = entry::Tuple{Int,Int,Any}
    op = read_intent(cim.projection, cim, evt)
    op === nothing && return nothing
    (op, idx)
end

# Returns (op, active_idx) — the index is the 1-based tab number so it can
# be turned into `selector_element_pairs[idx]` via _tab_prefix below.
function _route_active_tab(iomap::ChildrenIoMap, child_iomaps::Vector, evt)
    w = iomap.input
    w isa WidgetTabbedPane || return nothing
    active_idx = _active_tab_index(w, length(child_iomaps))
    active_idx == 0 && return nothing
    entry = child_iomaps[active_idx]
    entry === nothing && return nothing
    (ox, oy, cim) = entry::Tuple{Int,Int,Any}
    canvas = cim.output
    canvas isa GraphicsCanvas || return nothing
    # Mouse events: translate coords into the tab's local frame before
    # forwarding. `MouseClick`/`MouseScroll`/`MouseDwell` also hit-test (a
    # click/scroll/dwell outside the content is dropped). The drag events
    # `MouseDown`/`MouseUp`/`MouseMove` are translated too but not hit-gated — a
    # splitter drag inside the active tab must keep receiving motion even when the
    # cursor strays off the content, and the translation is what lets the tab's own
    # splitter band line up with where it is drawn (otherwise the grab region is
    # offset by the tab strip's height). Coordless events (KeyDown, KeyPress, …)
    # pass through.
    child_evt = @gesture_case evt begin
        MouseClick(button, x, y) => begin
            lx, ly = x - ox - Int(canvas.x), y - oy - Int(canvas.y)
            hit_element_at(canvas, lx, ly) === nothing && return nothing
            MouseClick(button, lx, ly, evt.count, evt.modifiers; time = evt.time)
        end
        MouseScroll(dx, dy, x, y) => begin
            lx, ly = x - ox - Int(canvas.x), y - oy - Int(canvas.y)
            hit_element_at(canvas, lx, ly) === nothing && return nothing
            MouseScroll(dx, dy, lx, ly; time = evt.time)
        end
        MouseDwell(x, y) => begin
            lx, ly = x - ox - Int(canvas.x), y - oy - Int(canvas.y)
            hit_element_at(canvas, lx, ly) === nothing && return nothing
            shift_event_position(evt, lx - x, ly - y)
        end
        MouseDown(button, x, y) =>
            MouseDown(button, x - ox - Int(canvas.x), y - oy - Int(canvas.y), evt.modifiers;
                      time = evt.time)
        MouseUp(button, x, y) =>
            MouseUp(button, x - ox - Int(canvas.x), y - oy - Int(canvas.y), evt.modifiers;
                    time = evt.time)
        MouseMove(x, y) =>
            MouseMove(x - ox - Int(canvas.x), y - oy - Int(canvas.y), evt.buttons, evt.modifiers;
                      time = evt.time)
        _ => evt
    end
    # The tab's frame is at the same offset for every event, so a position in the
    # answer goes back by it.
    op = shift_operation_position(read_child_event(cim, child_evt),
                                  ox + Int(canvas.x), oy + Int(canvas.y))
    op === nothing && return nothing
    (op, active_idx)
end

# The 1-based tab a tabbed pane's selection points at, or 0 when there is no
# tab selection. Accepts the forward-projected widget shape
# `selector_element_pairs[i].<rest>` (written by the printer when the document
# selection lands inside a tab) as well as the bare `[i]` shorthand a tab-strip
# click writes.
function _tab_index_from_selection(sel, n::Int)
    sel isa ConcreteReference || return 0
    h = sel.head
    if h isa FieldReferenceStep && h.name == "selector_element_pairs"
        t = sel.tail
        (t isa ConcreteReference && t.head isa RangeReferenceStep) || return 0
        i = t.head.start + 1
    elseif h isa RangeReferenceStep
        i = h.start + 1
    else
        return 0
    end
    1 <= i <= n ? i : 0
end

function _active_tab_index(w::WidgetTabbedPane, n::Int)
    n == 0 && return 0
    i = _tab_index_from_selection(get_stored_selection(w), n)
    i == 0 ? 1 : i
end

# The path an operation takes as it bubbles out of a tab's content.
#
# `selector_element_pairs[i]` names the `WidgetTabPage`, and what was printed is
# that page's `element`, so the true path continues through `.element`. It is not
# always written, and the reason is history rather than design.
#
# The upstream decoder — `PaneToWidget` — was written when a pair was a raw
# tuple, and it still expects the path to run straight from `[i]` into the
# content widget. It puts a **widget** in the tab, and it maps the reference
# back into its own domain before anything validates it against a document, so
# the missing step never shows up there.
#
# A tab that holds a foreign-domain document has no such decoder. The widget path
# **is** the document path, it reaches `_matched_selection`, and the missing step
# makes it fail: `[i]` stamps `::WidgetTabPage` on a node whose next step belongs
# to the document inside the page.
#
# So the step is added exactly for that case. This is deliberately narrow: writing
# it unconditionally is the correct path, and it would need the decoder changed
# in the same commit.
#
# A path of the whole page (a selection, or the part under the pointer) takes the
# step too, whatever the page holds. A
# bare `selector_element_pairs[i]` is what a click on the tab strip answers, and
# the page as a whole is a different thing: the document the tab holds.
function _tab_prefix(res, widget)
    res === nothing && return nothing
    op, idx = res
    _prefix_tab_operation(op, widget, idx)
end

_prefix_tab_operation(::Nothing, widget, idx::Int) = nothing
_prefix_tab_operation(op::CompoundOperation, widget, idx::Int) =
    CompoundOperation(Any[_prefix_tab_operation(o, widget, idx) for o in op.operations])
# A mouse target always takes the `.element` step: the chain write follows the path
# through the page into the document it holds, and the pane reads a path with and
# without the step.
function _prefix_tab_operation(op, widget, idx::Int)
    steps = (FieldReferenceStep("selector_element_pairs"), RangeReferenceStep(idx - 1, idx))
    whole_page = op isa ReplacePathOperation && get_operation_path(op) isa EmptyReference
    element = whole_page || op isa ReplaceMouseTargetOperation || _descends_into_page(widget, idx)
    reroot_operation(op, element ? (steps..., FieldReferenceStep("element")) : steps)
end

# The document tab `idx` shows, or `nothing`.
function _get_page_document(widget::WidgetTabbedPane, idx::Int)
    pairs = widget.selector_element_pairs
    (1 <= idx <= length(pairs)) || return nothing
    page = pairs[idx]
    page isa WidgetTabPage ? page.element : page
end

# Whether a page's document is selected as a whole. A control draws its own
# focus ring, so its page draws none.
_is_whole_selected_page(page) =
    page isa Document && hasproperty(page, :selection) && !is_focusable_document(page) &&
    page.selection isa EmptyReference

# True when tab `idx` holds a document that is not a widget — the case with no
# upstream decoder to compensate for the missing `.element` step.
function _descends_into_page(widget, idx::Int)
    widget isa WidgetTabbedPane || return false
    pairs = widget.selector_element_pairs
    (1 <= idx <= length(pairs)) || return false
    page = pairs[idx]
    page isa WidgetTabPage && !(page.element isa WidgetDocument)
end

# The viewport extent of a scroll pane on one axis. It is the offer when the pane
# has one — an authored size or the space the parent gave. It is the content's own
# extent when the pane has neither, because a pane with nothing to clip against
# must not clip.
function _pane_extent(offer, content_cell)
    offer !== nothing && return offer
    content_cell === nothing && return Cell(Int32(0))
    Cell(@computation Int32(max(0, Int(content_cell[]))))
end

# ── WidgetScrollPane ────────────────────────────────────────────────────────

# How far down a pane shows its content, in pixels. The printer draws the content
# at this offset and the reader routes a pointer event by it, so a press lands on
# what is drawn under it.
#
# A pane that follows the end shows the end, whatever `scroll_position` holds. A
# stored offset is clamped as it is read, because the content can shrink under a
# position that was valid when it was written. A list has no extent to clamp
# against along its axis: its offset is measured from the head of the list, in
# either direction, and following an end it does not have means staying where it
# is. The ends that a list does have stop it, once the walk from the head reaches
# them (`_clamp_to_list_ends`). A list that runs to the side has its extent down,
# and the pane clamps to it.
function _pane_scroll_y(w::WidgetScrollPane, content::GraphicsCanvas, view_h::Integer)
    y = Int((getfield(w, :scroll_position)[]::Point2D).y[])
    if is_infinite_canvas(content)
        _find_list_canvas(content, :y) === nothing &&
            return clamp(y, 0, max(0, Int(content.h) - Int(view_h)))
        return _clamp_to_list_ends(content, y, Int(view_h), :y)
    end
    room = max(0, Int(content.h) - Int(view_h))
    getfield(w, :follow_end)[] === true && return room
    clamp(y, 0, room)
end

# How far to the side a pane shows its content, in pixels. A content with an
# extent is clamped as it is scrolled, not as it is read. A list that runs to the
# side stops at its ends as it is read, as a list that runs down does.
function _pane_scroll_x(w::WidgetScrollPane, content::GraphicsCanvas, view_w::Integer)
    x = Int((getfield(w, :scroll_position)[]::Point2D).x[])
    (is_infinite_canvas(content) && _find_list_canvas(content, :x) !== nothing) || return x
    _clamp_to_list_ends(content, x, Int(view_w), :x)
end

# The canvas whose elements are a list that runs along `axis` (`:y` down, `:x`
# to the side), with its start on that axis in the coordinates of `content`. It
# is `content` itself, which the pane places at its own origin, or the first of
# its element canvases whose list runs that way. `nothing` when no list runs
# along `axis`.
function _find_list_canvas(content::GraphicsCanvas, axis::Symbol)
    layout = axis === :y ? layout_vertical : layout_horizontal
    start(canvas) = Int(axis === :y ? canvas.y : canvas.x)
    content.elements isa ListNode &&
        return content.layout == layout ? (content, start(content)) : nothing
    for element in content.elements
        (element isa GraphicsCanvas && element.elements isa ListNode && element.layout == layout) ||
            continue
        return (element, start(element))
    end
    nothing
end

# The start and the end of one element of a list along `axis`, in the
# coordinates of the list, or `nothing` for an element that has no extent of
# its own.
function _get_list_element_span(element, axis::Symbol)
    position, extent = axis === :y ? (:y, :h) : (:x, :w)
    (hasproperty(element, position) && hasproperty(element, extent)) || return nothing
    first_edge = Int(getproperty(element, position))
    (first_edge, first_edge + Int(getproperty(element, extent)))
end

# `offset` clamped to the ends of the list that `content` draws along `axis`,
# where a walk from the head reaches them. The last child does not come short of
# the far edge of the viewport, and the first child does not pass the near
# edge. The first child wins, so a list shorter than the viewport starts at its
# start. Each walk stops at an edge of the viewport, so it reads the children
# that a renderer reads to draw them.
function _clamp_to_list_ends(content::GraphicsCanvas, offset::Int, view::Int, axis::Symbol = :y)
    found = _find_list_canvas(content, axis)
    found === nothing && return offset
    list, start = found
    node = list.elements
    while true
        span = _get_list_element_span(node.value, axis)
        span === nothing && return offset
        far_edge = start + span[2]
        far_edge >= offset + view && break
        following = node.next
        if following === nothing
            offset = far_edge - view
            break
        end
        node = following
    end
    node = list.elements
    while true
        span = _get_list_element_span(node.value, axis)
        span === nothing && return offset
        near_edge = start + span[1]
        near_edge <= offset && break
        preceding = node.prev
        if preceding === nothing
            offset = near_edge
            break
        end
        node = preceding
    end
    offset
end

function print_document(p::WidgetScrollPaneToGraphicsCanvas, recursion, w::WidgetScrollPane, ctx)
    w.visible == false && return WidgetScrollPaneToGraphicsCanvasIoMap(p, w, _empty_canvas(), nothing)
    pos = w.position
    sz  = w.size
    px = pos isa Point2D ? _sc(Int(pos.x[])) : 0
    py = pos isa Point2D ? _sc(Int(pos.y[])) : 0
    # Viewport extent, by the one rule every widget follows: an authored size
    # wins, then the extent the parent offered, then the extent of the content.
    # The extent is held as a `Cell` so reads are deferred: the parent layout may
    # not have built its allocation cell yet when we recurse.
    #
    # An authored size wins because a caller that wrote one meant it. A card sets
    # its panes' size precisely so they do not grow with what they hold, and an
    # offer that overrode it would take that away.
    #
    # The size is read one axis at a time, and 0 on an axis authors nothing on
    # it (`layout-rules.md` §1). So a pane that authors its height and a width of
    # 0 has a fixed height and takes the width its parent offers.
    #
    # An axis with no authored size and no offer is not clipped at all. On that
    # axis the pane withholds the offer, lets the content size itself, and takes
    # the viewport extent from the content. This is what keeps a pane that clips
    # one axis — a collapsed card body, clipped to a fixed height — as wide as
    # its content on the other. The two cases cannot form a cycle: a clipped axis
    # offers a cell that the content reads, and an unclipped axis reads a cell
    # that the content produces.
    #
    # An authored extent is read inside the cell, so a pane whose size is a
    # computed cell — a tree pane that grows as its rows open — follows it after
    # the first print as well.
    tx, ty = _inset_total(p, w)
    avail_w = get_exact_width(ctx)
    avail_h = get_exact_height(ctx)
    function extent_cell(authored, avail, inset)
        (authored() > 0 || avail !== nothing) || return nothing
        Cell(@computation begin
            extent = authored()
            extent > 0 ? Int32(extent) :
                avail === nothing ? Int32(0) : Int32(max(0, Int(avail[]) - inset))
        end)
    end
    offer_w = extent_cell(() -> sz isa Point2D ? Int(sz.x[]) : 0, avail_w, tx)
    offer_h = extent_cell(() -> sz isa Point2D ? Int(sz.y[]) : 0, avail_h, ty)
    cox, coy = _content_offset(p, w)
    scroll_cell = getfield(w, :scroll_position)
    # Recurse into the content before the extent cells exist: on an unclipped axis
    # the viewport extent is the content's own, so the content must come first.
    content_iomap = nothing
    content = w.content
    inner_canvas = nothing
    if content isa Document
        # A clipped axis gives the content its extent exactly. An unclipped axis
        # passes the parent's range on, less the insets: an edge stays an edge,
        # so text in the pane wraps at it, and the pane takes the content's
        # extent there.
        content_ctx = with_inner_size(ctx; width = tx, height = ty)
        offer_w === nothing || (content_ctx = with_exact_size(content_ctx; width = offer_w))
        offer_h === nothing || (content_ctx = with_exact_size(content_ctx; height = offer_h))
        content_iomap = print_child(recursion, content, content_ctx)
        inner_canvas = content_iomap.output::GraphicsCanvas
    end
    # The content's extent cells and not their values: a value read here would
    # make the pane's own print depend on it, and a content that grows would
    # print the pane and everything in it again.
    vw_cell = _pane_extent(offer_w, inner_canvas === nothing ? nothing : getfield(inner_canvas, :w))
    vh_cell = _pane_extent(offer_h, inner_canvas === nothing ? nothing : getfield(inner_canvas, :h))
    # Horizontal offset of the content inside the viewport. A list that runs to
    # the side stops at its ends.
    inner_x = Cell(@computation Int32(-(inner_canvas === nothing ?
        Int((scroll_cell[]::Point2D).x[]) : _pane_scroll_x(w, inner_canvas, vw_cell[]))))
    elems = Any[]
    # The margin, the border and the padding follow the viewport extent; the
    # viewport is the content part. A transparent part draws no element.
    colors = _get_box_colors(p, w)
    _push_following_box_bands!(elems, _get_box_insets(p, w), colors, vw_cell, vh_cell)
    content_color = colors.content
    # Cell-backed rect so it tracks the viewport extent.
    is_color_transparent(content_color) ||
        push!(elems, GraphicsRect(Cell(Int32(cox)), Cell(Int32(coy)), vw_cell, vh_cell,
                              Cell(content_color),
                              Cell(Int32(0)), Cell(Int32(0)), Cell(Int32(0)), Cell(Int32(0)),
                              Cell(Int32(0)),
                              Cell(color_transparent),
                              Cell(nothing)))
    if inner_canvas !== nothing
        # A content whose elements are a collection is drawn element by element.
        # A content that holds its elements in a cell — a layout of a list — is
        # drawn as its canvas, so a new list in that cell reaches the viewport
        # and the pane reads no cell of its content as it prints.
        inner_elems_cv = getfield(inner_canvas, :elements)
        # Vertical offset of the content inside the viewport. With `follow_end`
        # the pane sticks to the bottom of its content, so newly appended content
        # (a streaming chat) stays in view as the content grows.
        inner_y = Cell(@computation Int32(-_pane_scroll_y(w, inner_canvas, vh_cell[])))
        held = inner_elems_cv isa CellVector ? inner_elems_cv : CellVector(Cell[Cell(inner_canvas)])
        push!(elems, GraphicsViewport(Cell(Int32(cox)), Cell(Int32(coy)),
                                      vw_cell, vh_cell,
                                      Cell(GraphicsCanvas(inner_x, inner_y, Int32(0), Int32(0),
                                                          held,
                                                          layout_none, true, Cell(nothing))),
                                      Cell(affine_identity),
                                      Cell(nothing)))
    end
    # Report the pane's own box as the outer canvas extent (viewport + insets)
    # rather than 0×0. A scroll pane occupies a fixed viewport, so a parent that
    # *measures* its child (e.g. WidgetCard sizing its body to the recursed
    # content) needs the real height — otherwise it under-sizes and the clipped
    # viewport draws past the parent's border. Split/tabbed parents allocate the
    # slot and ignore this size, so they are unaffected. `vw_cell`/`vh_cell` are
    # the inset-reduced viewport extents, so the full box adds the insets back.
    outer_w = Cell(@computation Int32(Int(vw_cell[]) + tx))
    outer_h = Cell(@computation Int32(Int(vh_cell[]) + ty))
    outer = GraphicsCanvas(Cell(Int32(px)), Cell(Int32(py)), outer_w, outer_h,
                           CellVector(Cell[Cell(e) for e in elems]),
                           layout_none, true, Cell(nothing))
    WidgetScrollPaneToGraphicsCanvasIoMap(p, w, outer, content_iomap)
end

# The viewport of a scroll pane or a transform pane shows the content in a canvas
# of the pane's own, moved by the scroll or the transform, that holds the
# elements of the content's canvas (or the content's canvas itself, when its
# elements are no vector). So `content` is the content of the pane's viewport,
# and the content's own answer goes on from there.
map_reference_forward(::WidgetScrollPaneToGraphicsCanvas, iomap, reference) =
    _map_viewport_content_forward(iomap, reference)

function _map_viewport_content_forward(iomap, reference)
    reference isa Reference || return nothing
    reference = strip_reference_types(reference)
    reference isa ConcreteReference || return _map_self_forward(reference)
    head = reference.head
    (head isa FieldReferenceStep && head.name == "content") || return nothing
    children = something(get_child_iomaps(iomap), Any[])
    isempty(children) && return nothing
    child = first(children)
    inner = map_reference_forward(get_iomap_projection(child), child, reference.tail)
    inner === nothing && return nothing
    elements = unwrap_cell(getfield(unwrap_cell(get_iomap_output(iomap)), :elements))
    k = findfirst(i -> unwrap_cell(elements[i]) isa GraphicsViewport, 1:length(elements))
    k === nothing && return nothing
    body = unwrap_cell(elements[k])
    held = find_node_reference(getfield(body, :content), unwrap_cell(get_iomap_output(child)); depth = 1)
    inner = held === nothing ? inner : concat_references(held, inner)
    ConcreteReference(FieldReferenceStep("elements"),
        ConcreteReference(RangeReferenceStep(k - 1, k),
            ConcreteReference(FieldReferenceStep("content"), inner)))
end

# The scroll pane wraps a single content document as its `.content` field.
# A path arriving from the content's reader is already in the content's
# input domain (the inner pipeline has already translated it); the scroll
# pane's contribution is just to prepend `.content` to re-root it in the
# scroll pane's own input domain.
function map_reference_backward(p::WidgetScrollPaneToGraphicsCanvas, iomap::WidgetScrollPaneToGraphicsCanvasIoMap, reference)
    reference === nothing && return nothing
    point = find_reference_point(reference)
    point === nothing && return ConcreteReference(FieldReferenceStep("content"), reference)
    _is_point_on_canvas(iomap.output, point) || return nothing
    content_iomap = iomap.content_iomap
    content_iomap === nothing && return nothing
    _map_point_into_content(iomap.input, content_iomap,
                            _find_scroll_pane_local_point(p, iomap, point.x, point.y))
end

# The point `(x, y)` of the pane in the frame of its content: past the content
# origin, and moved by the scroll offset that the printer drew with, so a pane
# that follows the end maps a point to what is drawn at the end, and a list stops
# at the ends that a walk from its head reaches.
function _find_scroll_pane_local_point(p::WidgetScrollPaneToGraphicsCanvas,
                                       iomap::WidgetScrollPaneToGraphicsCanvasIoMap, x::Int, y::Int)
    w = iomap.input
    cox, coy = _content_offset(p, w)
    tx, ty = _inset_total(p, w)
    content = iomap.content_iomap.output
    sx = _pane_scroll_x(w, content, Int(iomap.output.w) - tx)
    sy = _pane_scroll_y(w, content, Int(iomap.output.h) - ty)
    (x - cox + sx, y - coy + sy)
end

# Whether `point` lies on what a widget drew, judged as `_outside_widget` judges a
# pointer event: in the box of its canvas, and an unsized canvas leaves the
# decision to its container.
function _is_point_on_canvas(canvas, point)
    canvas isa GraphicsCanvas || return false
    (canvas.w <= 0 || canvas.h <= 0) && return true
    0 <= point.x < Int(canvas.w) && 0 <= point.y < Int(canvas.h)
end

# The part of a pane at `local_point` of its content: on into the content, whose
# own map names the part; a content that maps nothing there is itself the part.
function _map_point_into_content(input, content_iomap, local_point)
    answer = map_reference_backward(get_iomap_projection(content_iomap), content_iomap,
                                    PointReferenceStep(local_point...))
    annotate_reference_types(input, ConcreteReference(FieldReferenceStep("content"),
                                                      answer === nothing ? EmptyReference() : answer))
end

# A scroll-wheel turn advances `scroll_position` by a delta. Expressed as a write
# of the new (old+delta) value — the old value is read from the pane at read time,
# which equals its value at evaluate time (no intervening mutation in the loop).
# How far a pane can scroll on each axis: the content's extent past the viewport,
# and `0` on an axis where the content fits. `nothing` when there is no content to
# measure, which leaves the scroll unbounded. `nothing` for a list too, which has
# no extent; `_scroll_list_by` finds the ends of a list by a walk.
function _scroll_room(p, iomap)
    out = iomap.output
    cim = iomap.content_iomap
    (out isa GraphicsCanvas && cim !== nothing) || return nothing
    content = cim.output
    content isa GraphicsDocument || return nothing
    content isa GraphicsCanvas && is_infinite_canvas(content) && return nothing
    tx, ty = _inset_total(p, iomap.input)
    view_w = max(0, Int(out.w[]) - tx)
    view_h = max(0, Int(out.h[]) - ty)
    # The extent that the pane draws with (`_pane_scroll_y`): the size that a
    # canvas declares, or else what is drawn, with the measure of the pane.
    content_w, content_h = content isa GraphicsCanvas ? (Int(content.w), Int(content.h)) :
                           get_graphics_size(content, p.measure)
    (max(0, Int(content_w) - view_w), max(0, Int(content_h) - view_h))
end

# A scroll that would move nothing is not an operation. Without the clamp a pane
# scrolls its content clean out of its own viewport — a transcript that fits was
# pushed 60 px above the top by one wheel notch — and answering `nothing` at the
# end of the travel is also what lets an outer pane take over from an inner one.
#
# Every write of a scroll is view state, so a history never records it and
# `Ctrl+Z` takes back an edit, not a scroll.
function _scroll_by(sp, dx, dy, room = nothing)
    old = sp.scroll_position
    x = Int(old.x[]) + dx
    y = Int(old.y[]) + dy
    if room !== nothing
        x = clamp(x, 0, room[1])
        y = clamp(y, 0, room[2])
    end
    (x == Int(old.x[]) && y == Int(old.y[])) && return nothing
    _write_view_state(sp, "scroll_position", Point2D(x, y))
end

# Scroll this pane, if the wheel landed on it. Only reached once the content has
# declined the event, so the innermost pane under the pointer wins.
#
# `follow_end` is a mode, not a lock. A pane that follows the end draws at the
# end and ignores `scroll_position` — so a reader who scrolls back through a
# transcript must first take the pane off the pin, and the pin goes back on when
# they reach the end again. Without that the wheel wrote a cell nothing read, and
# the transcript could not be scrolled at all.
function _self_scroll(p, iomap, canvas, evt)
    evt isa MouseScroll || return nothing
    hit_element_at(canvas, evt.x, evt.y) === nothing && return nothing
    _, scroll_step = _text_size(p.measure, p.font, "M")
    dx, dy = (evt.dx != 0 && evt.dy == 0) ? (-evt.dx * scroll_step, 0) :
                                            (0, -evt.dy * scroll_step)
    w = iomap.input
    room = _scroll_room(p, iomap)
    following = getfield(w, :follow_end)[] === true
    if following
        room === nothing && return nothing          # nothing measurable to leave the end for
        dy >= 0 && return nothing                   # already at the end, and asked to go further
        # Release the pin, and start from where the reader is actually looking,
        # which is the end — not from whatever the unread cell happens to hold.
        x = clamp(Int(w.scroll_position.x[]) + dx, 0, room[1])
        y = clamp(room[2] + dy, 0, room[2])
        return CompoundOperation(Any[
            _write_view_state(w, "follow_end", false),
            _write_view_state(w, "scroll_position", Point2D(x, y))])
    end
    content = iomap.content_iomap === nothing ? nothing : iomap.content_iomap.output
    room === nothing && content isa GraphicsCanvas && is_infinite_canvas(content) &&
        return _scroll_list_by(p, iomap, content, dx, dy)
    op = _scroll_by(w, dx, dy, room)
    # Back at the end: follow again, so new turns stay in view.
    if op !== nothing && room !== nothing && room[2] > 0 &&
       Int(get_wrapped_operation(op).value.y[]) == room[2] && getfield(w, :follow_end)[] === false
        return CompoundOperation(Any[op,
            _write_view_state(w, "follow_end", true)])
    end
    op
end

# A wheel turn over a list. It starts from the offset that the pane draws with,
# and along the list it stops at the ends that a walk from the head reaches. So a
# turn past the last child moves nothing and answers `nothing`, and a turn back
# moves at once. Across the list the content has an extent, and a turn stops at
# its edge, as it does over any content.
function _scroll_list_by(p, iomap, content::GraphicsCanvas, dx::Int, dy::Int)
    w = iomap.input
    tx, ty = _inset_total(p, w)
    view_w = Int(iomap.output.w) - tx
    view_h = Int(iomap.output.h) - ty
    drawn_x = _pane_scroll_x(w, content, view_w)
    drawn_y = _pane_scroll_y(w, content, view_h)
    x = _find_list_canvas(content, :x) === nothing ?
        clamp(drawn_x + dx, 0, max(0, Int(content.w) - view_w)) :
        _clamp_to_list_ends(content, drawn_x + dx, view_w, :x)
    y = _find_list_canvas(content, :y) === nothing ?
        clamp(drawn_y + dy, 0, max(0, Int(content.h) - view_h)) :
        _clamp_to_list_ends(content, drawn_y + dy, view_h, :y)
    (x == drawn_x && y == drawn_y) && return nothing
    _write_view_state(w, "scroll_position", Point2D(x, y))
end

# Whether the point `(x, y)` of a scroll pane or a transform pane is in the view of
# its content, inside the insets. An unsized pane leaves the decision to the
# content.
function _is_point_in_pane_view(p, iomap, x::Int, y::Int)
    out = iomap.output
    out isa GraphicsCanvas || return false
    (Int(out.w) <= 0 || Int(out.h) <= 0) && return true
    w = iomap.input
    cox, coy = _content_offset(p, w)
    tx, ty = _inset_total(p, w)
    cox <= x < cox + Int(out.w) - tx && coy <= y < coy + Int(out.h) - ty
end

# A dwell on a scroll pane or a transform pane, whose content is at `.content`. A
# dwell on the content, in the view, goes to the content at `point`, the same point
# in the frame of the content, and `move_out` takes a position in the answer back
# into the frame of the pane, as for a click. The pane then reads its own stretch
# (`read_container_gesture`); a dwell anywhere else is on the pane itself.
function _read_pane_dwell(p, iomap, dwell::MouseDwell; point, move_out)
    content_iomap = iomap.content_iomap
    canvas = content_iomap === nothing ? nothing : content_iomap.output
    on_content = canvas isa GraphicsCanvas &&
                 hit_element_at(canvas, point...) !== nothing &&
                 _is_point_in_pane_view(p, iomap, dwell.x, dwell.y)
    on_content || return read_container_gesture(nothing, dwell, iomap.input)
    local_dwell = shift_event_position(dwell, point[1] - dwell.x, point[2] - dwell.y)
    answer = map_operation_position(read_child_event(content_iomap, local_dwell),
                                    move_out)
    steps = (FieldReferenceStep("content"),)
    read_container_gesture(reroot_operation(answer, steps), dwell, iomap.input; steps)
end

# A move of the pointer. A point on the content, in the view, goes to the
# content, which is the target unless it names a part. Any other point goes to the
# content only when the pane's own mouse target is in the content: for the content
# the move is the leave of the pointer.
function _read_scroll_pane_move(p::WidgetScrollPaneToGraphicsCanvas,
                                iomap::WidgetScrollPaneToGraphicsCanvasIoMap, evt::MouseMove)
    content_iomap = iomap.content_iomap
    content_iomap === nothing && return nothing
    lx, ly = _find_scroll_pane_local_point(p, iomap, evt.x, evt.y)
    canvas = content_iomap.output
    on_content = !_outside_widget(iomap, evt) && _is_point_in_pane_view(p, iomap, evt.x, evt.y) &&
                 canvas isa GraphicsCanvas && hit_element_at(canvas, lx, ly) !== nothing
    _retarget_op(p, iomap, _read_single_child_move(iomap.input, "content", content_iomap, evt,
                                                   evt.x - lx, evt.y - ly, on_content))
end

function read_intent(p::WidgetScrollPaneToGraphicsCanvas, iomap::WidgetScrollPaneToGraphicsCanvasIoMap, evt)
    evt isa MouseMove && return _read_scroll_pane_move(p, iomap, evt)
    _outside_widget(iomap, evt) && return nothing
    canvas = iomap.output
    # Forward other events (MouseClick, KeyDown, KeyPress) to the wrapped
    # content. Coords for MouseClick arrive relative to the scroll pane's
    # canvas origin (parent routing has already subtracted the pane's own
    # position); translate into the content's coordinate system by
    # subtracting the content origin (cox, coy) and adding the current
    # scroll offset. Any path-bearing op returned by the content's reader
    # is in the content's input domain; map it through this projection's
    # `map_reference_backward` to re-root it at `.content.<rest>` in the
    # scroll pane's input domain.
    content_iomap = iomap.content_iomap
    # No content: nothing can refuse the wheel, so fall through to scrolling
    # ourselves rather than dropping the event.
    content_iomap === nothing &&
        return read_container_gesture(_self_scroll(p, iomap, canvas, evt), evt,
                                      iomap.input)
    # Every coordinate-bearing pointer event needs the same translation, not just
    # the press. A move in the pane's own frame would light the row that would be
    # under the pointer if the list were not scrolled, while a click on the same
    # pixel selects the row that is there. The viewport variant of this projection
    # translates the whole set too.
    #
    # The vertical offset is the one the printer drew with, so a pane that
    # follows the end routes a press to what is drawn at the end.
    _local(x, y) = _find_scroll_pane_local_point(p, iomap, x, y)
    if evt isa MouseDwell
        point = _local(evt.x, evt.y)
        offset = (evt.x - point[1], evt.y - point[2])
        return _read_pane_dwell(p, iomap, evt; point,
                                move_out = (x, y) -> (x + offset[1], y + offset[2]))
    end
    op = @gesture_case evt begin
        # A popup the content opens goes back by the content origin and the
        # scroll offset, the difference between the two frames of the press.
        MouseClick(button, x, y) => begin
            lx, ly = _local(x, y)
            shift_operation_position(
                read_child_event(content_iomap, MouseClick(button, lx, ly, evt.count, evt.modifiers;
                                                           time = evt.time)),
                x - lx, y - ly)
        end
        MouseDown(button, x, y) => begin
            lx, ly = _local(x, y)
            read_child_event(content_iomap, MouseDown(button, lx, ly, evt.modifiers;
                                                      time = evt.time))
        end
        MouseUp(button, x, y) => begin
            lx, ly = _local(x, y)
            read_intent(content_iomap.projection, content_iomap,
                             MouseUp(button, lx, ly, evt.modifiers; time = evt.time))
        end
        MouseMove(x, y) => begin
            lx, ly = _local(x, y)
            read_intent(content_iomap.projection, content_iomap,
                             MouseMove(lx, ly, evt.buttons, evt.modifiers;
                                       time = evt.time))
        end
        # The wheel goes to the innermost pane under the pointer, so translate
        # it like a press and let the content refuse first; see the viewport
        # variant for why intercepting here would strand a nested pane.
        MouseScroll(dx, dy, x, y) => begin
            lx, ly = _local(x, y)
            read_intent(content_iomap.projection, content_iomap,
                             MouseScroll(dx, dy, lx, ly, evt.modifiers; time = evt.time))
        end
        _ => read_intent(content_iomap.projection, content_iomap, evt)
    end
    # A right click then reads the stretch of the pane (`read_container_gesture`).
    op === nothing ||
        return read_container_gesture(_retarget_op(p, iomap, op), evt, iomap.input;
                                      steps = (FieldReferenceStep("content"),))
    read_container_gesture(_self_scroll(p, iomap, canvas, evt), evt, iomap.input)
end

# ── WidgetTransformPane ───────────────────────────────────────────────────────
#
# A transform pane is the scroll pane's generalisation: instead of baking a
# translation into the inner canvas origin, it leaves the inner canvas at the
# origin and drives the viewport's `transform` (an AffineTransform). Today only
# the translate+scale subset is honoured by the backends; rotation/shear is
# future work. Ctrl+wheel zooms about the cursor, a plain wheel pans.

const _ZOOM_STEP = 1.1     # multiplicative zoom per wheel notch
const _ZOOM_MIN  = 0.25    # smallest total scale
const _ZOOM_MAX  = 4.0     # largest total scale

function print_document(p::WidgetTransformPaneToGraphicsCanvas, recursion, w::WidgetTransformPane, ctx)
    w.visible == false && return WidgetTransformPaneToGraphicsCanvasIoMap(p, w, _empty_canvas(), nothing)
    pos = w.position
    sz  = w.size
    px = pos isa Point2D ? _sc(Int(pos.x[])) : 0
    py = pos isa Point2D ? _sc(Int(pos.y[])) : 0
    # The same rule as the scroll pane's: an authored size wins over an offer.
    tx, ty = _inset_total(p, w)
    avail_w = get_exact_width(ctx)
    avail_h = get_exact_height(ctx)
    vw_cell = sz isa Point2D ? Cell(Int32(Int(sz.x[]))) :
              avail_w !== nothing ?
              Cell(@computation Int32(max(0, Int(avail_w[]) - tx))) :
              Cell(Int32(0))
    vh_cell = sz isa Point2D ? Cell(Int32(Int(sz.y[]))) :
              avail_h !== nothing ?
              Cell(@computation Int32(max(0, Int(avail_h[]) - ty))) :
              Cell(Int32(0))
    cox, coy = _content_offset(p, w)
    # The pane's affine transform, read through a Cell so a zoom/pan re-zooms
    # the viewport reactively.
    transform_cell = Cell(@computation getfield(w, :transform)[]::AffineTransform)
    elems = Any[]
    colors = _get_box_colors(p, w)
    _push_following_box_bands!(elems, _get_box_insets(p, w), colors, vw_cell, vh_cell)
    content_color = colors.content
    is_color_transparent(content_color) ||
        push!(elems, GraphicsRect(Cell(Int32(cox)), Cell(Int32(coy)), vw_cell, vh_cell,
                              Cell(content_color),
                              Cell(Int32(0)), Cell(Int32(0)), Cell(Int32(0)), Cell(Int32(0)),
                              Cell(Int32(0)),
                              Cell(color_transparent),
                              Cell(nothing)))
    # Recurse into the content at the viewport's (unscaled) logical extent — the
    # content lays out at 1× and the viewport's transform magnifies it.
    content_iomap = nothing
    content = w.content
    if content isa Document
        content_ctx = with_exact_size(ctx; width=vw_cell, height=vh_cell)
        content_iomap = print_child(recursion, content, content_ctx)
        inner_canvas = content_iomap.output::GraphicsCanvas
        inner_elems_cv = inner_canvas.elements
        # Inner canvas stays at the origin; the transform carries pan + zoom.
        push!(elems, GraphicsViewport(Cell(Int32(cox)), Cell(Int32(coy)),
                                      vw_cell, vh_cell,
                                      Cell(GraphicsCanvas(Cell(Int32(0)), Cell(Int32(0)), Int32(0), Int32(0),
                                                          inner_elems_cv isa CellVector ? inner_elems_cv : CellVector(Cell[Cell(inner_canvas)]),
                                                          layout_none, true, Cell(nothing))),
                                      transform_cell,
                                      Cell(nothing)))
    end
    outer_w = Cell(@computation Int32(Int(vw_cell[]) + tx))
    outer_h = Cell(@computation Int32(Int(vh_cell[]) + ty))
    outer = GraphicsCanvas(Cell(Int32(px)), Cell(Int32(py)), outer_w, outer_h,
                           CellVector(Cell[Cell(e) for e in elems]),
                           layout_none, true, Cell(nothing))
    WidgetTransformPaneToGraphicsCanvasIoMap(p, w, outer, content_iomap)
end

map_reference_forward(::WidgetTransformPaneToGraphicsCanvas, iomap, reference) =
    _map_viewport_content_forward(iomap, reference)

# Like the scroll pane: prepend `.content` to re-root a bubbled path in the
# transform pane's own input domain.
function map_reference_backward(p::WidgetTransformPaneToGraphicsCanvas, iomap::WidgetTransformPaneToGraphicsCanvasIoMap, reference)
    reference === nothing && return nothing
    point = find_reference_point(reference)
    point === nothing && return ConcreteReference(FieldReferenceStep("content"), reference)
    _is_point_on_canvas(iomap.output, point) || return nothing
    iomap.content_iomap === nothing && return nothing
    _map_point_into_content(iomap.input, iomap.content_iomap,
                            _find_transform_pane_local_point(p, iomap, point.x, point.y))
end

# A move of the pointer reaches the content through the inverse transform, as
# every pointer event does, and a position in the answer goes back through the
# transform itself. A point off the content reaches it only when the pane's own
# mouse target is in it.
function _read_transform_pane_move(p::WidgetTransformPaneToGraphicsCanvas,
                                   iomap::WidgetTransformPaneToGraphicsCanvasIoMap, evt::MouseMove)
    content_iomap = iomap.content_iomap
    content_iomap === nothing && return nothing
    w = iomap.input
    lx, ly = _find_transform_pane_local_point(p, iomap, evt.x, evt.y)
    canvas = content_iomap.output
    on_content = !_outside_widget(iomap, evt) && _is_point_in_pane_view(p, iomap, evt.x, evt.y) &&
                 canvas isa GraphicsCanvas && hit_element_at(canvas, lx, ly) !== nothing
    (on_content || _is_mouse_target_in_field(w, "content")) || return nothing
    answer = on_content ?
        read_child_move(content_iomap, MouseMove(lx, ly, evt.buttons, evt.modifiers; time = evt.time)) :
        read_child_leave(content_iomap, evt, 0, 0)
    M = getfield(w, :transform)[]::AffineTransform
    cox, coy = _content_offset(p, w)
    map_outer(x, y) = begin
        px, py = apply_affine_transform(M, Float64(x), Float64(y))
        (round(Int, px) + cox, round(Int, py) + coy)
    end
    _retarget_op(p, iomap, map_operation_position(answer, map_outer))
end

# The point `(x, y)` of the pane in the frame of its content: past the content
# origin, and through the inverse of the pane's transform.
function _find_transform_pane_local_point(p::WidgetTransformPaneToGraphicsCanvas,
                                          iomap::WidgetTransformPaneToGraphicsCanvasIoMap,
                                          x::Int, y::Int)
    w = iomap.input
    M = getfield(w, :transform)[]::AffineTransform
    cox, coy = _content_offset(p, w)
    Tuple(round.(Int, apply_affine_transform(compute_affine_inverse(M),
                                             Float64(x - cox), Float64(y - coy))))
end

# Zoom about a viewport-space point: scale by `factor` keeping `(ax, ay)` fixed,
# composed onto the existing matrix. `M' = T(a) ∘ S(f) ∘ T(-a) ∘ M`.
_zoom_about(M::AffineTransform, factor, ax, ay) =
    make_affine_translate(ax, ay) ∘ make_affine_scale(factor, factor) ∘ make_affine_translate(-ax, -ay) ∘ M

# Pan: prepend a screen-space translation. `M' = T(dx, dy) ∘ M`.
_pan_by(M::AffineTransform, dx, dy) = make_affine_translate(dx, dy) ∘ M

# One zoom step about `(ax, ay)`: `dir > 0` zooms in, `dir < 0` out. Returns the
# write of the transform, or `nothing` if the clamp leaves the scale unchanged
# (already at `_ZOOM_MIN`/`_ZOOM_MAX`). Shared by the wheel and keyboard readers.
# The transform is view state, so every write of it is one a history skips.
function _zoom_op(w, M::AffineTransform, dir, ax, ay)
    cur = M.a == 0.0 ? 1.0 : M.a
    f = dir > 0 ? _ZOOM_STEP : 1.0 / _ZOOM_STEP
    new_scale = clamp(cur * f, _ZOOM_MIN, _ZOOM_MAX)
    f = new_scale / cur
    f == 1.0 && return nothing
    _write_view_state(w, "transform", _zoom_about(M, f, ax, ay))
end

function read_intent(p::WidgetTransformPaneToGraphicsCanvas, iomap::WidgetTransformPaneToGraphicsCanvasIoMap, evt)
    evt isa MouseMove && return _read_transform_pane_move(p, iomap, evt)
    _outside_widget(iomap, evt) && return nothing
    canvas = iomap.output
    w = iomap.input
    M = getfield(w, :transform)[]::AffineTransform
    cox, coy = _content_offset(p, w)
    # MouseScroll is consumed here (zoom or pan); each matched branch `return`s.
    @gesture_case evt begin
        # Ctrl+wheel: zoom about the cursor.
        MouseScroll(dx, dy, x, y; ctrl) => begin
            hit_element_at(canvas, x, y) === nothing && return nothing
            return _zoom_op(w, M, dy >= 0 ? 1 : -1, Float64(x - cox), Float64(y - coy))
        end
        # Plain wheel: pan. Vertical by `dy`, horizontal by `dx`, step = line height.
        MouseScroll(dx, dy, x, y) => begin
            hit_element_at(canvas, x, y) === nothing && return nothing
            _, step = _text_size(p.measure, p.font, "M")
            return dx != 0 && dy == 0 ?
                _write_view_state(w, "transform", _pan_by(M, dx * step, 0)) :
                _write_view_state(w, "transform", _pan_by(M, 0, dy * step))
        end
    end
    # Forward other events to the content, then re-root the result. Every pointer
    # event reaches the content through the inverse transform (screen → content-local),
    # so a down focuses, and a drag moves, what is drawn under the pointer.
    content_iomap = iomap.content_iomap
    _local(x, y) = _find_transform_pane_local_point(p, iomap, x, y)
    # A position in the content's answer goes back through the transform itself,
    # so a popup opens where its widget is drawn; its size stays in screen pixels.
    _outer(x, y) = begin
        px, py = apply_affine_transform(M, Float64(x), Float64(y))
        (round(Int, px) + cox, round(Int, py) + coy)
    end
    evt isa MouseDwell &&
        return _read_pane_dwell(p, iomap, evt; point = _local(evt.x, evt.y),
                                move_out = _outer)
    op = content_iomap === nothing ? nothing : @gesture_case evt begin
        MouseClick(button, x, y) => begin
            lx, ly = _local(x, y)
            map_operation_position(
                read_child_event(content_iomap, MouseClick(button, lx, ly, evt.count, evt.modifiers;
                                                           time = evt.time)),
                _outer)
        end
        MouseDown(button, x, y) => begin
            lx, ly = _local(x, y)
            read_child_event(content_iomap, MouseDown(button, lx, ly, evt.modifiers;
                                                      time = evt.time))
        end
        MouseUp(button, x, y) => begin
            lx, ly = _local(x, y)
            read_intent(content_iomap.projection, content_iomap, MouseUp(button, lx, ly, evt.modifiers;
                                                                         time = evt.time))
        end
        MouseMove(x, y) => begin
            lx, ly = _local(x, y)
            read_intent(content_iomap.projection, content_iomap,
                        MouseMove(lx, ly, evt.buttons, evt.modifiers; time = evt.time))
        end
        _ => read_intent(content_iomap.projection, content_iomap, evt)
    end
    op = _retarget_op(p, iomap, op)
    # A right click then reads the stretch of the pane (`read_container_gesture`).
    op === nothing ||
        return read_container_gesture(op, evt, w;
                                      steps = (FieldReferenceStep("content"),))
    # Keyboard zoom — a *fallback* only when the content did not consume the key,
    # so a Ctrl+= / Ctrl+- bound inside the content (e.g. collection add/remove)
    # still wins. Ctrl+= / keypad-+ zooms in, Ctrl+- / keypad-- out, Ctrl+0
    # resets — all about the viewport centre (no cursor for keyboard).
    tx, ty = _inset_total(p, w)
    cw = Int(canvas.w); ch = Int(canvas.h)
    acx, acy = (cw - tx) / 2.0, (ch - ty) / 2.0
    @gesture_case evt begin
        KeyDown(:equals; ctrl) => return _zoom_op(w, M, 1, acx, acy)
        KeyDown(:minus; ctrl)  => return _zoom_op(w, M, -1, acx, acy)
        KeyDown(:zero; ctrl)   => return M === affine_identity ? nothing :
                                         _write_view_state(w, "transform", affine_identity)
    end
    read_container_gesture(nothing, evt, w)
end

# ── WidgetToolbar ───────────────────────────────────────────────────────────

function print_document(p::WidgetToolbarToGraphicsCanvas, recursion, w::WidgetToolbar, ctx)
    w.visible == false && return ChildrenIoMap(p, w, _empty_canvas(), Cell(Any[]))
    child_cells = make_reconciled_child_iomaps_cell(
        () -> Any[item for item in w.elements if item isa WidgetDocument],
        # A toolbar lays its items out at their own size, side by side, so it gives
        # no slot on the main axis: an item that took a slot would stretch to the
        # whole band. It gives its edge instead, as a bounded range, so an item
        # draws its content and a text in it wraps at the band's edge.
        (i, item) -> print_child(recursion, item, with_bounded_size(ctx; width = ctx.maximum_width)))
    build = Cell(@computation begin
        content_x, content_y = _content_offset(p, w)
        item_gap = p.item_gap
        _, item_h = _text_size(p.measure, p.font, "M")
        child_iomaps = Any[]
        items = Any[]
        x_cursor = 0
        # The row is as tall as its tallest item, and at least a line of the font.
        content_height = item_h
        for cim in child_cells[]
            push!(child_iomaps, (content_x + x_cursor, content_y, cim))
            push!(items, _make_canvas(content_x + x_cursor, content_y, Any[cim.output]))
            # Advance by the item's *rendered* width (includes a leading icon, Stage 5),
            # not just its text — otherwise an icon'd item overlaps the next one.
            iw = _menu_item_width(cim)
            iw <= 0 && (iw = first(compute_text_extent(p.measure, "    ", p.font)))
            x_cursor += iw + item_gap
            content_height = max(content_height, _menu_item_height(cim))
        end
        content_width = max(0, x_cursor - item_gap)
        elems = Any[]
        _push_box_parts!(elems, _get_box_insets(p, w), _get_box_colors(p, w), content_width, content_height)
        inset_width, inset_height = _inset_total(p, w)
        width, height = _compute_bar_extent(inset_width + content_width, inset_height + content_height,
                                            child_iomaps, _p_measure(p))
        append!(elems, items)
        (width = width, height = height, elements = elems, child_iomaps = child_iomaps)
    end)
    ChildrenIoMap(p, w, _reactive_canvas_cell(0, 0, build), Cell(@computation build[].child_iomaps))
end

map_reference_forward(::WidgetToolbarToGraphicsCanvas, iomap, reference) = _map_child_forward(iomap, reference)

map_reference_backward(::WidgetToolbarToGraphicsCanvas, iomap, reference) =
    _map_child_point(iomap, reference)

function read_intent(::WidgetToolbarToGraphicsCanvas, iomap::ChildrenIoMap, evt)
    evt isa MouseMove && return _read_children_move(iomap, evt)
    _outside_widget(iomap, evt) && return nothing
    entries = getfield(iomap, :child_iomaps)[]::Vector
    (evt isa MouseClick || evt isa MouseDwell || evt isa MouseDown || evt isa MouseUp) &&
        return _route_toolbar_gesture(iomap.input, entries, evt)
    evt isa MouseScroll || return nothing
    _route_scroll_to_children(entries, evt)
end

# A press, a down, an up or a dwell goes to the item under the pointer, and its
# answer is re-rooted into `elements[i]`, as a composite re-roots: an Alt+press then
# selects that item rather than the whole toolbar, and an action travels unchanged.
# An item answers a down with its pressed look, so the down leaves the focus where
# it is. The toolbar lays out only its widget elements, so a laid-out index is
# mapped back to the element it came from. For a dwell and a right click the
# toolbar then reads its own stretch (`read_container_gesture`).
function _route_toolbar_gesture(toolbar::WidgetToolbar, entries::Vector, gesture)
    found = _route_composite_event(entries, gesture.x, gesture.y,
                (x, y) -> shift_event_position(gesture, x - gesture.x, y - gesture.y))
    found === nothing && return read_container_gesture(nothing, gesture, toolbar)
    operation, laid_out = found
    widgets = findall(item -> item isa WidgetDocument, collect(toolbar.elements))
    index = widgets[laid_out]
    steps = (FieldReferenceStep("elements"), RangeReferenceStep(index - 1, index))
    read_container_gesture(reroot_operation(operation, steps), gesture, toolbar; steps)
end

# ── WidgetStatusBar (Stage 4) ─────────────────────────────────────────────────
# A non-interactive bottom band: stringified `segments` laid left-to-right on a
# muted surface, filling the available width when a parent seeded one.

@projection UntrackedCell struct WidgetStatusBarToGraphicsCanvas
    measure::TextMeasure
    margin::Inset
    border::Inset
    padding::Inset
    margin_color::StyleColor
    border_color::StyleColor
    padding_color::StyleColor
    content_color::StyleColor
    label_text::StyleText
    item_gap::Int
end

WidgetStatusBarToGraphicsCanvas(theme; measure,
                                margin = inset_default, border = inset_default,
                                padding = _themed(Inset, theme, t -> t.status_bar_padding),
                                margin_color = color_transparent, border_color = color_transparent,
                                padding_color = _themed(StyleColor, theme, t -> t.muted),
                                content_color = _themed(StyleColor, theme, t -> t.muted),
                                label_text = _themed(StyleText, theme, _get_caption_text),
                                item_gap = _themed(Int, theme, t -> t.item_gap)) =
    WidgetStatusBarToGraphicsCanvas(measure, margin, border, padding, margin_color, border_color,
                                    padding_color, content_color, label_text, item_gap)

function print_document(p::WidgetStatusBarToGraphicsCanvas, recursion, w::WidgetStatusBar, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    # A status bar is one line, so its height comes from the font of its labels
    # and from its insets, and not from its words. A segment that says something
    # else, as the selection does on each key, changes what the bar draws and not
    # the room the bands around it have.
    height = Cell(@computation begin
        _, inset_height = _inset_total(p, w)
        label = _get_part_text(w, :label_text, p.label_text)
        _resolve_height(ctx, 0, compute_line_box(p.measure, "", label.font).height + inset_height)
    end)
    build = Cell(@computation begin
        content_x, content_y = _content_offset(p, w)
        inset_width, inset_height = _inset_total(p, w)
        item_gap = p.item_gap
        label = _get_part_text(w, :label_text, p.label_text)
        labels = Any[]
        x = 0
        for (i, seg) in enumerate(w.elements)
            s = string(seg)
            tw, _ = _text_size(p.measure, label.font, s)
            i == 1 || (x += item_gap)
            _push_text!(labels, p.measure, label.font, s, content_x + x, content_y, label.color)
            x += tw
        end
        width = _resolve_width(ctx, 0, x + inset_width)
        elements = Any[]
        _push_box_parts!(elements, _get_box_insets(p, w), _get_box_colors(p, w),
                         width - inset_width, height[] - inset_height)
        append!(elements, labels)
        (width=width, elements=elements)
    end)
    SimpleIoMap(p, w, GraphicsCanvas(Int32(0), Int32(0),
                                     Cell(@computation Int32(build[].width)),
                                     Cell(@computation Int32(height[])),
                                     CellVector(@computation build[].elements),
                                     layout_none, true, Cell(nothing)))
end

map_reference_forward(::WidgetStatusBarToGraphicsCanvas, iomap, reference) = _map_child_forward(iomap, reference)
map_reference_backward(::WidgetStatusBarToGraphicsCanvas, iomap, reference) = nothing
read_intent(::WidgetStatusBarToGraphicsCanvas, iomap::SimpleIoMap, evt) = nothing

# ── WidgetScrollBar ─────────────────────────────────────────────────────────

# The extent of a scroll bar on one axis: its authored size, else the extent
# that its parent offers, else its thickness across and nothing along.
function _get_scroll_bar_extent(authored::Int, offered, along::Bool, thickness::Int)
    authored > 0 && return authored
    offered === nothing || return Int(offered[])
    along ? 0 : thickness
end

# The track of a scroll bar and its thumb inside it, as `(x, y, w, h)` in the
# canvas of the bar, from the extent of the bar and its value.
function _get_scroll_bar_thumb(p::WidgetScrollBarToGraphicsCanvas, w::WidgetScrollBar,
                               width::Int, height::Int)
    cox, coy = _content_offset(p, w)
    tx, ty = _inset_total(p, w)
    cw = max(1, width - tx)
    ch = max(1, height - ty)
    value = clamp(Float64(w.value), 0.0, 1.0)
    thumb_size = clamp(Float64(w.thumb_size), 0.05, 1.0)
    if w.orientation === :horizontal
        tw = min(cw, max(p.minimum_thumb_length, Int(round(thumb_size * cw))))
        ((cox, coy, cw, ch), (cox + Int(round(value * (cw - tw))), coy, tw, ch))
    else
        th = min(ch, max(p.minimum_thumb_length, Int(round(thumb_size * ch))))
        ((cox, coy, cw, ch), (cox, coy + Int(round(value * (ch - th))), cw, th))
    end
end

# A scroll bar is as long as its parent offers and as thick as its theme says,
# unless it authors a size. Its track and its thumb read the value in cells, so
# a scroll moves the thumb and prints nothing again.
function print_document(p::WidgetScrollBarToGraphicsCanvas, _, w::WidgetScrollBar, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    pos = w.position
    px = pos isa Point2D ? _sc(Int(pos.x[])) : 0
    py = pos isa Point2D ? _sc(Int(pos.y[])) : 0
    sz = w.size
    horizontal = w.orientation === :horizontal
    offered_w = ctx === nothing ? nothing : get_exact_width(ctx)
    offered_h = ctx === nothing ? nothing : get_exact_height(ctx)
    width = Cell(@computation Int32(_get_scroll_bar_extent(sz isa Point2D ? Int(sz.x[]) : 0,
                                                           offered_w, horizontal, p.thickness)))
    height = Cell(@computation Int32(_get_scroll_bar_extent(sz isa Point2D ? Int(sz.y[]) : 0,
                                                            offered_h, !horizontal, p.thickness)))
    parts = Cell(@computation _get_scroll_bar_thumb(p, w, Int(width[]), Int(height[])))
    track_color = _get_part_color(w, :track_color, p.track_color)
    thumb_color = _get_part_color(w, :thumb_color, p.thumb_color)
    function make_rect(part::Int, color)
        rect = GraphicsRect(0, 0, 0, 0; color)
        for (k, field) in enumerate((:x, :y, :w, :h))
            set_cell_computation!(getfield(rect, field), () -> Int32(parts[][part][k]))
        end
        for corner in (:radius_tl, :radius_tr, :radius_br, :radius_bl)
            set_cell_computation!(getfield(rect, corner),
                                  () -> Int32(min(parts[][part][3], parts[][part][4]) ÷ 2))
        end
        rect
    end
    elems = Any[]
    tx, ty = _inset_total(p, w)
    _push_following_box_bands!(elems, _get_box_insets(p, w), _get_box_colors(p, w),
                               Cell(@computation Int32(max(1, Int(width[]) - tx))),
                               Cell(@computation Int32(max(1, Int(height[]) - ty))))
    push!(elems, make_rect(1, track_color))
    push!(elems, make_rect(2, thumb_color))
    SimpleIoMap(p, w, GraphicsCanvas(Cell(Int32(px)), Cell(Int32(py)), width, height,
                                     CellVector(Cell[Cell(e) for e in elems]),
                                     layout_none, true, Cell(nothing)))
end

map_reference_forward(::WidgetScrollBarToGraphicsCanvas, iomap, reference) = _map_child_forward(iomap, reference)

function map_reference_backward(::WidgetScrollBarToGraphicsCanvas, iomap, reference)
    return nothing
end

# A press, a button down, or a move with the left button held puts the middle
# of the thumb under the pointer, and writes the value there.
function read_intent(p::WidgetScrollBarToGraphicsCanvas, iomap::SimpleIoMap, evt)
    _outside_widget(iomap, evt) && return nothing
    (evt isa MouseClick || evt isa MouseDown ||
     (evt isa MouseMove && evt.buttons.left)) || return nothing
    w = iomap.input
    w isa WidgetScrollBar || return nothing
    canvas = iomap.output
    track, thumb = _get_scroll_bar_thumb(p, w, Int(canvas.w), Int(canvas.h))
    new_value = if w.orientation === :horizontal
        clamp(Float64(evt.x - Int(canvas.x) - track[1] - thumb[3] ÷ 2) / max(1, track[3] - thumb[3]),
              0.0, 1.0)
    else
        clamp(Float64(evt.y - Int(canvas.y) - track[2] - thumb[4] ÷ 2) / max(1, track[4] - thumb[4]),
              0.0, 1.0)
    end
    new_value == Float64(w.value) && return nothing
    ReplaceReferencedValueOperation(w, "value", new_value)
end

# ════════════════════════════════════════════════════════════════════════════
# Extension widgets
# ════════════════════════════════════════════════════════════════════════════

# The reader trio of a widget that takes no input: a badge, a separator, a
# progress bar, an avatar, an alert, a highlight and a skeleton only show a value.
macro _printer_only(P)
    quote
        map_reference_forward(::$(esc(P)), iomap, reference) = nothing
        map_reference_backward(::$(esc(P)), iomap, reference) = nothing
        read_intent(::$(esc(P)), iomap, evt) = nothing
    end
end

# ── WidgetBadge ─────────────────────────────────────────────────────────────

@projection UntrackedCell struct WidgetBadgeToGraphicsCanvas
    measure::TextMeasure
    margin::Inset
    border::Inset
    padding::Inset
    margin_color::StyleColor
    border_color::StyleColor
    padding_color::StyleColor
    content_color::StyleColor
    label_text::StyleText
    secondary_padding_color::StyleColor
    secondary_content_color::StyleColor
    secondary_border_color::StyleColor
    secondary_label_text::StyleText
    destructive_padding_color::StyleColor
    destructive_content_color::StyleColor
    destructive_border_color::StyleColor
    destructive_label_text::StyleText
    outline_padding_color::StyleColor
    outline_content_color::StyleColor
    outline_border_color::StyleColor
    outline_label_text::StyleText
    success_surface_color::StyleColor
    success_label_text::StyleText
    warning_surface_color::StyleColor
    warning_label_text::StyleText
    error_surface_color::StyleColor
    error_label_text::StyleText
    info_surface_color::StyleColor
    info_label_text::StyleText
    accent_surface_color::StyleColor
    accent_label_text::StyleText
end

# The border inset is the theme's width in every variant, so a badge keeps its
# size when its variant changes; only the outline variant shows a visible
# border color. A role has a surface and a text of its own, and no border.
WidgetBadgeToGraphicsCanvas(theme; measure,
                            margin = inset_default,
                            border = _themed(Inset, theme, t -> _make_uniform_inset(t.border_width)),
                            padding = _themed(Inset, theme, t -> t.compact_padding),
                            margin_color = color_transparent, border_color = color_transparent,
                            padding_color = _themed(StyleColor, theme, t -> t.primary),
                            content_color = _themed(StyleColor, theme, t -> t.primary),
                            label_text = _themed(StyleText, theme, t -> StyleText(t.font_small, t.primary_foreground)),
                            secondary_padding_color = _themed(StyleColor, theme, t -> t.secondary),
                            secondary_content_color = _themed(StyleColor, theme, t -> t.secondary),
                            secondary_border_color = color_transparent,
                            secondary_label_text =
                                _themed(StyleText, theme, t -> StyleText(t.font_small, t.secondary_foreground)),
                            destructive_padding_color = _themed(StyleColor, theme, t -> t.destructive),
                            destructive_content_color = _themed(StyleColor, theme, t -> t.destructive),
                            destructive_border_color = color_transparent,
                            destructive_label_text =
                                _themed(StyleText, theme, t -> StyleText(t.font_small, t.destructive_foreground)),
                            outline_padding_color = _themed(StyleColor, theme, t -> t.background),
                            outline_content_color = _themed(StyleColor, theme, t -> t.background),
                            outline_border_color = _themed(StyleColor, theme, t -> t.border),
                            outline_label_text =
                                _themed(StyleText, theme, t -> StyleText(t.font_small, t.foreground)),
                            success_surface_color = _themed(StyleColor, theme, t -> t.success_surface),
                            success_label_text =
                                _themed(StyleText, theme, t -> StyleText(t.font_small, t.success_foreground)),
                            warning_surface_color = _themed(StyleColor, theme, t -> t.warning_surface),
                            warning_label_text =
                                _themed(StyleText, theme, t -> StyleText(t.font_small, t.warning_foreground)),
                            error_surface_color = _themed(StyleColor, theme, t -> t.error_surface),
                            error_label_text =
                                _themed(StyleText, theme, t -> StyleText(t.font_small, t.error_foreground)),
                            info_surface_color = _themed(StyleColor, theme, t -> t.info_surface),
                            info_label_text =
                                _themed(StyleText, theme, t -> StyleText(t.font_small, t.info_foreground)),
                            accent_surface_color = _themed(StyleColor, theme, t -> t.accent),
                            accent_label_text =
                                _themed(StyleText, theme, t -> StyleText(t.font_small, t.accent_foreground))) =
    WidgetBadgeToGraphicsCanvas(measure, margin, border, padding, margin_color, border_color, padding_color,
                                content_color, label_text,
                                secondary_padding_color, secondary_content_color, secondary_border_color,
                                secondary_label_text,
                                destructive_padding_color, destructive_content_color, destructive_border_color,
                                destructive_label_text,
                                outline_padding_color, outline_content_color, outline_border_color,
                                outline_label_text,
                                success_surface_color, success_label_text,
                                warning_surface_color, warning_label_text,
                                error_surface_color, error_label_text,
                                info_surface_color, info_label_text,
                                accent_surface_color, accent_label_text)

# The roles a badge takes, each with a surface and a text in the badge printer.
const _BADGE_ROLES = (:success, :warning, :error, :info, :accent)

# The colors of the four box parts of a badge and the style of its text: those of
# its role when it has one, else those of its variant.
function _get_badge_style(p::WidgetBadgeToGraphicsCanvas, w::WidgetBadge)
    role = w.role
    if role !== nothing
        role in _BADGE_ROLES ||
            throw(ArgumentError("a badge has no role $(repr(role)); the roles are $(_BADGE_ROLES)"))
        surface = getproperty(p, Symbol(role, "_surface_color"))
        return (colors = (margin = color_transparent, border = color_transparent,
                          padding = surface, content = surface),
                label = getproperty(p, Symbol(role, "_label_text")))
    end
    variant = w.variant === :default ? nothing : w.variant
    (colors = _get_box_colors(p, w; variant), label = _get_state_text(p, w, :label; variant))
end

# The size of badge `w` as `p` draws it: its text, its padding and its border. A
# widget that holds badges, such as the strip of a tabbed pane, measures each with
# the badge printer of its theme and draws it with `_build_badge_elements`, so a
# badge looks the same in every host.
function _measure_badge(p::WidgetBadgeToGraphicsCanvas, w::WidgetBadge)
    style = _get_badge_style(p, w)
    content_width, content_height = _text_size(p.measure, style.label.font, string(w.content))
    inset_width, inset_height = _inset_total(p, w)
    (content_width + inset_width, content_height + inset_height)
end

# The graphics of badge `w`, `width` by `height`, with its top left corner at the
# origin: the pill and its text.
function _build_badge_elements(p::WidgetBadgeToGraphicsCanvas, w::WidgetBadge, width::Int, height::Int)
    style = _get_badge_style(p, w)
    text = string(w.content)
    _, content_height = _text_size(p.measure, style.label.font, text)
    box = _get_box_insets(p, w)
    inset_width, inset_height = _inset_total(p, w)
    content_x, content_y = _content_offset(p, w)
    border_box_height = box.border[2] + box.padding[2] + content_height + box.padding[4] + box.border[4]
    elements = Any[]
    _push_box_parts!(elements, box, style.colors, width - inset_width, height - inset_height;
                     radius = border_box_height ÷ 2)
    _push_text!(elements, p.measure, style.label.font, text, content_x, content_y, style.label.color)
    elements
end

function print_document(p::WidgetBadgeToGraphicsCanvas, recursion, w::WidgetBadge, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    position = w.position::Point2D
    SimpleIoMap(p, w, _reactive_canvas(_origin(position)..., () -> begin
        natural_width, natural_height = _measure_badge(p, w)
        badge_width  = _resolve_width(ctx, 0, natural_width)
        badge_height = _resolve_height(ctx, 0, natural_height)
        (width = badge_width, height = badge_height,
         elements = _build_badge_elements(p, w, badge_width, badge_height))
    end))
end
@_printer_only WidgetBadgeToGraphicsCanvas

# ── WidgetSeparator ─────────────────────────────────────────────────────────

@projection UntrackedCell struct WidgetSeparatorToGraphicsCanvas
    margin::Inset
    border::Inset
    padding::Inset
    margin_color::StyleColor
    border_color::StyleColor
    padding_color::StyleColor
    content_color::StyleColor
    divider_stroke::StyleStroke    # color + width of the rule
end

WidgetSeparatorToGraphicsCanvas(theme;
                                margin = inset_default, border = inset_default, padding = inset_default,
                                margin_color = color_transparent, border_color = color_transparent,
                                padding_color = color_transparent, content_color = color_transparent,
                                divider_stroke =
                                    _themed(StyleStroke, theme, t -> StyleStroke(t.border, t.border_width))) =
    WidgetSeparatorToGraphicsCanvas(margin, border, padding, margin_color, border_color, padding_color,
                                    content_color, divider_stroke)

function print_document(p::WidgetSeparatorToGraphicsCanvas, recursion, w::WidgetSeparator, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    position = w.position::Point2D
    SimpleIoMap(p, w, _reactive_canvas(_origin(position)..., () -> begin
        rule_length = _sc(Int(w.length))
        divider_stroke = _get_state_stroke(p, w, :divider)
        thickness = max(1, Int(divider_stroke.width))
        box = _get_box_insets(p, w)
        colors = _get_box_colors(p, w)
        inset_width, inset_height = _inset_total(p, w)
        content_x, content_y = _content_offset(p, w)
        elements = Any[]
        if w.orientation === :vertical
            outer_height = _resolve_height(ctx, rule_length > 0 ? rule_length + inset_height : 0,
                                           rule_length + inset_height)
            line_length = outer_height - inset_height
            outer_width = thickness + inset_width
            _push_box_parts!(elements, box, colors, thickness, line_length)
            push!(elements, GraphicsLine(content_x, content_y, content_x, content_y + line_length;
                                         color = divider_stroke.color, width=thickness))
            (width=outer_width, height=outer_height, elements=elements)
        else
            outer_width = _resolve_width(ctx, rule_length > 0 ? rule_length + inset_width : 0,
                                         rule_length + inset_width)
            line_length = outer_width - inset_width
            outer_height = thickness + inset_height
            _push_box_parts!(elements, box, colors, line_length, thickness)
            push!(elements, GraphicsLine(content_x, content_y, content_x + line_length, content_y;
                                         color = divider_stroke.color, width=thickness))
            (width=outer_width, height=outer_height, elements=elements)
        end
    end))
end
@_printer_only WidgetSeparatorToGraphicsCanvas

# ── WidgetCard ──────────────────────────────────────────────────────────────

@projection UntrackedCell struct WidgetCardToGraphicsCanvas
    measure::TextMeasure
    margin::Inset
    border::Inset
    padding::Inset
    margin_color::StyleColor
    border_color::StyleColor
    padding_color::StyleColor          # card fill, in the :card variant
    content_color::StyleColor          # card fill, in the :card variant
    title_text::StyleText
    description_text::StyleText
    body_text::StyleText
    footer_text::StyleText
    header_color::StyleColor           # behind the title and the description
    body_color::StyleColor             # behind the content
    footer_color::StyleColor           # behind the footer
    tinted_border_color::StyleColor
    tinted_padding_color::StyleColor   # card fill, in the :tinted variant
    tinted_content_color::StyleColor   # card fill, in the :tinted variant
    muted_border_color::StyleColor
    muted_padding_color::StyleColor    # card fill, in the :muted variant
    muted_content_color::StyleColor    # card fill, in the :muted variant
    plain_border_color::StyleColor
    plain_padding_color::StyleColor
    plain_content_color::StyleColor
    chevron_color::StyleColor          # the fold mark of a collapsible card
    graphics_style::NamedTuple         # the ring over the slot selected as a whole
    corner_radius::Int
    title_gap::Int
    section_gap::Int
    chevron_size::Int                  # its half-size
    chevron_nudge::Int                 # the mark, one pixel under the header's middle line
end

# The padding of the projection is the theme's container padding on every side,
# unless the card names its own (`nothing` takes this default, by the rule of
# `_get_box_insets`).
WidgetCardToGraphicsCanvas(theme; graphics_theme = nothing, measure,
                           margin = inset_default,
                           border = _themed(Inset, theme, t -> _make_uniform_inset(t.border_width)),
                           padding = _themed(Inset, theme, t -> _make_uniform_inset(t.container_padding)),
                           margin_color = color_transparent,
                           border_color = _themed(StyleColor, theme, t -> t.border),
                           padding_color = _themed(StyleColor, theme, t -> t.card),
                           content_color = _themed(StyleColor, theme, t -> t.card),
                           title_text = _themed(StyleText, theme, _get_title_text),
                           description_text = _themed(StyleText, theme, _get_caption_text),
                           body_text = _themed(StyleText, theme, t -> StyleText(t.font, t.card_foreground)),
                           footer_text = _themed(StyleText, theme, _get_caption_text),
                           header_color = color_transparent, body_color = color_transparent,
                           footer_color = color_transparent,
                           # The tint is NEUTRAL, and it is a step of depth rather than a change
                           # of hue. Two quiet surfaces nest — a band holds a panel — so they have
                           # to be ordered, and a ladder only reads as one if every rung moves the
                           # same way. The accent-derived tint moved toward BLUE while `muted`
                           # moved toward grey, so against any other color on the page the band
                           # read as a cast on the background rather than as a surface, and beside
                           # a panel the two pulled apart instead of stacking.
                           #
                           # Neutral leaves the role to be said by the thing that says it well: the
                           # colored mark and word on the role line.
                           tinted_border_color = color_transparent,
                           tinted_padding_color =
                               _themed(StyleColor, theme, t -> color_interpolate(t.muted, t.background, 0.5)),
                           tinted_content_color =
                               _themed(StyleColor, theme, t -> color_interpolate(t.muted, t.background, 0.5)),
                           muted_border_color = color_transparent,
                           muted_padding_color = _themed(StyleColor, theme, t -> t.muted),
                           muted_content_color = _themed(StyleColor, theme, t -> t.muted),
                           plain_border_color = color_transparent,
                           plain_padding_color = color_transparent, plain_content_color = color_transparent,
                           chevron_color = _themed(StyleColor, theme, t -> t.muted_foreground),
                           graphics_style = _make_graphics_style(graphics_theme),
                           corner_radius = _themed(Int, theme, t -> t.radius),
                           title_gap = _themed(Int, theme, t -> t.title_gap),
                           section_gap = _themed(Int, theme, t -> t.section_gap),
                           chevron_size = _themed(Int, theme, t -> t.chevron),
                           chevron_nudge = _themed(Int, theme, t -> t.chevron_nudge)) =
    WidgetCardToGraphicsCanvas(measure, margin, border, padding, margin_color, border_color, padding_color,
                               content_color, title_text, description_text, body_text, footer_text,
                               header_color, body_color, footer_color,
                               tinted_border_color, tinted_padding_color, tinted_content_color,
                               muted_border_color, muted_padding_color, muted_content_color,
                               plain_border_color, plain_padding_color, plain_content_color,
                               chevron_color, graphics_style, corner_radius, title_gap, section_gap,
                               chevron_size, chevron_nudge)

# The column a collapsible card's chevron takes, left of everything else the
# card draws: two half-sizes of the mark and the title gap. Zero for a card that
# does not fold, or has no title to fold from.
_card_chevron_column(p, w::WidgetCard) =
    (w.collapsible === true && w.title !== nothing) ? 2 * p.chevron_size + p.title_gap : 0

# The box a card folds from, as `(x0, y0, x1, y1)`: the chevron's column, as tall
# as the header row. `nothing` for a card that does not fold from a click. Only
# a collapsible card with a Document title folds, and only from its chevron, so a
# click on the title is a click on the title.
function _card_fold_box(p, w::WidgetCard, header_h::Integer)
    (w.collapsible === true && w.title isa Document) || return nothing
    content_x, content_y = _content_offset(p, w)
    (content_x, content_y, content_x + _card_chevron_column(p, w), content_y + Int(header_h))
end

# Lay out the card body: stack title/description/content/footer top-to-bottom,
# size the card to them, and draw the box and the three region panels behind
# them. Reads the recursed title/content iomaps' reactive sizes (`inner.h[]`/
# `inner.w[]`), so the enclosing `build` cell re-runs when the content grows —
# that is what keeps the card's border, height, and child positions in step
# with reactive content.
function _card_build(p, w, ctx, tim, cim)
    variant = w.variant === :card ? nothing : w.variant
    box = _get_box_insets(p, w)
    colors = _get_box_colors(p, w; variant)
    content_x, content_y = _content_offset(p, w)
    inset_width, inset_height = _inset_total(p, w)
    header_elements = Any[]
    body_elements = Any[]
    footer_elements = Any[]
    child_iomaps = Any[]
    max_content_width = 0   # widest content row, to size the card to its content
    y = content_y
    # A collapsible card draws a chevron in a column of its own, and everything
    # else — the title, the description, the body, the footer — starts past
    # that column, so the body lines up under the title's word and not under
    # the mark. The mark is pushed once the header's height is known, so it sits
    # on the header's own middle line. Reading `collapsed` here is what flips it
    # without a re-print.
    column = _card_chevron_column(p, w)
    padding = content_x + column
    pad_x = inset_width + column
    # The width the card's own texts break to: the width it was told to be, else
    # the width it was offered, less the insets on both sides and the chevron
    # column. With neither there is no bound, and each text is the one line it
    # measures.
    edge_w = ctx === nothing ? nothing : ctx.maximum_width
    authored_width = _sc(Int(w.width))
    text_bound = authored_width > 0 ? max(0, authored_width - pad_x) :
                 edge_w !== nothing ? max(0, Int(edge_w[]) - pad_x) : 0
    header_top = y
    header_h = 0
    title_text = _get_state_text(p, w, :title)
    if tim !== nothing
        push!(child_iomaps, (padding, y, tim))
        push!(header_elements, _make_canvas(padding, y, Any[tim.output]))
        inner = tim.output
        if inner isa GraphicsCanvas
            header_h = Int(inner.h[])
            max_content_width = max(max_content_width, Int(inner.w[]))
            y += header_h + p.title_gap
        else
            y += p.title_gap
        end
    elseif w.title !== nothing
        title_width, title_height = _push_text_block!(header_elements, p.measure, title_text,
                                                      string(w.title), padding, y, text_bound)
        header_h = title_height
        max_content_width = max(max_content_width, title_width); y += title_height + p.title_gap
    end
    if column > 0
        chevron_size = p.chevron_size
        # The mark sits one pixel under the header's middle line: a word's ink
        # sits under the middle of its box, and the mark belongs beside the ink.
        _push_chevron!(header_elements, content_x + chevron_size, content_y + header_h ÷ 2 + p.chevron_nudge,
                       chevron_size, w.collapsed === true ? :right : :down,
                       _get_state_color(p, w, :chevron))
    end
    fold_box = _card_fold_box(p, w, header_h)
    if fold_box !== nothing
        # A container routes a press to the card only over something the card
        # drew, and the two strokes of the mark cover little of its column. A
        # transparent rectangle makes the whole column the target.
        x0, y0, x1, y1 = fold_box
        push!(header_elements, GraphicsRect(x0, y0, x1 - x0, y1 - y0; color = color_transparent, radius = 0))
    end
    description_text = _get_state_text(p, w, :description)
    if w.description !== nothing
        description_width, description_height =
            _push_text_block!(header_elements, p.measure, description_text,
                              string(w.description), padding, y, text_bound)
        max_content_width = max(max_content_width, description_width)
        y += description_height + p.section_gap
    end
    header_bottom = y
    body_top = y
    content = w.content
    # A collapsed card draws its header and nothing else. Reading `collapsed`
    # here is what lets a card whose body is a plain Document fold: such a body
    # cannot make itself empty the way a reactive `CellVector` content can (see
    # `_collapsible_card` in ObjectToWidget). The recursed `cim` stays alive
    # outside this cell, so unfolding places the child again without a re-print.
    collapsed = w.collapsed === true
    body_text = _get_state_text(p, w, :body)
    if collapsed
        nothing                        # the header is the whole card
    elseif cim !== nothing
        push!(child_iomaps, (padding, y, cim))
        inner = cim.output
        # The card offered its body an inner width, so the card clips that width
        # (§3b of layout-rules.md), and a body wider than the card does not draw
        # past its border. It is the same width the card's own texts break to, so
        # a card of a declared width holds everything it draws. Height is not
        # clipped: the card withholds that axis and takes its own height from
        # what the body drew.
        if inner isa GraphicsCanvas && text_bound > 0
            clip_w = text_bound
            push!(body_elements, GraphicsViewport(Cell(Int32(padding)), Cell(Int32(y)),
                                             Cell(Int32(clip_w)), Cell(Int32(Int(inner.h[]))),
                                             Cell(_make_canvas(0, 0, Any[inner])),
                                             Cell(affine_identity),
                                             Cell(nothing)))
            max_content_width = max(max_content_width, min(Int(inner.w[]), clip_w))
        else
            push!(body_elements, _make_canvas(padding, y, Any[inner]))
            inner isa GraphicsCanvas && (max_content_width = max(max_content_width, Int(inner.w[])))
        end
        y += inner isa GraphicsCanvas ? Int(inner.h[]) : 0
    elseif content isa AbstractString
        content_width, content_height = _push_text_block!(body_elements, p.measure, body_text,
                                                          content, padding, y, text_bound)
        max_content_width = max(max_content_width, content_width); y += content_height
    end
    body_bottom = y
    # The section gap separates the content from a footer. With no footer there
    # is nothing to separate, and the card ends at its padding.
    footer_top = y
    footer_text = _get_state_text(p, w, :footer)
    if w.footer !== nothing
        y += p.section_gap
        footer_top = y
        footer_width, footer_height = _push_text_block!(footer_elements, p.measure, footer_text,
                                                        string(w.footer), padding, y, text_bound)
        max_content_width = max(max_content_width, footer_width); y += footer_height
    end
    footer_bottom = y
    card_width = _resolve_width(ctx, authored_width, max_content_width + pad_x)
    # A fixed card is exactly its declared height; a content-tall one grows to fit.
    fixed_height = _sc(Int(w.height))
    bottom_inset = box.margin[4] + box.border[4] + box.padding[4]
    card_height = fixed_height > 0 ? fixed_height :
                  _resolve_height(ctx, 0, y + bottom_inset)
    region_width = card_width - inset_width
    # The box, drawn first (behind content). The variant says how loud its
    # surface is; the card keeps its shape and its insets in all four, so only
    # the colors change. `:plain` draws no panel at all: its three box colors
    # are transparent, and `_push_box_parts!` skips a transparent part.
    surface = Any[]
    _push_box_parts!(surface, box, colors, region_width, card_height - inset_height; radius = p.corner_radius)
    # The three regions, each a panel (transparent by default, so it costs
    # nothing) behind the elements that fill it.
    _push_panel!(surface, content_x, header_top, region_width, header_bottom - header_top;
                fill = _get_state_color(p, w, :header))
    append!(surface, header_elements)
    _push_panel!(surface, content_x, body_top, region_width, body_bottom - body_top;
                fill = _get_state_color(p, w, :body))
    append!(surface, body_elements)
    _push_panel!(surface, content_x, footer_top, region_width, footer_bottom - footer_top;
                fill = _get_state_color(p, w, :footer))
    append!(surface, footer_elements)
    (w = card_width, h = card_height, elements = surface, child_iomaps = child_iomaps)
end

# The body a card recurses into, and the context to print it with.
#
# A bare document is itself. A `LayoutConstraint` pinning a height becomes a
# viewport with **no size of its own**, printed with that height as its offer — a
# viewport takes the offer when it authored nothing, so one number says it and the
# width still comes from the card. Nothing here needs a `Point2D`, and nothing
# here needs to know the card's inner width.
function _card_body(content, inner_ctx)
    content isa LayoutConstraint || return (content, inner_ctx)
    pinned = content.preferred_height
    pinned === nothing && return (content.child, inner_ctx)
    (WidgetScrollPane(content.child; padding = inset_default),
     with_exact_size(inner_ctx; height = Cell(Int32(Int(pinned)))))
end

function print_document(p::WidgetCardToGraphicsCanvas, recursion, w::WidgetCard, ctx)
    w.visible == false && return ChildrenIoMap(p, w, _empty_canvas(), Cell(Any[]))
    position = w.position::Point2D
    ox, oy = _origin(position)
    # Recurse the Document title/content once (stable iomaps); the build cell only
    # reads their reactive sizes, so growing content repaints the card without
    # reprinting the projection.
    #
    # Seed the *interior* width for the recursed content: when a parent allocated
    # a width, the card fills it (see `_resolve_width` in `_card_build`), so its
    # content should fill that allocation minus the card's own padding — letting
    # a responsive body (chat-bubble text, nested cards) wrap to the card rather
    # than overrunning it. Strip the vertical axis: the card is content-tall, so
    # neither the header row nor the body should fill the parent's height.
    # The body is offered the card's OWN inner width. A card told a width draws
    # that width whatever it was offered, so a body sized from the offer would be
    # wider than the card that holds it.
    inset_width, _ = _inset_total(p, w)
    pad_x = inset_width + _card_chevron_column(p, w)
    # Without a width of its own, the card passes its range on, less its
    # padding, in the same state: a slot stays a slot and an edge stays an edge.
    authored_width = _sc(Int(w.width))
    inner_ctx = authored_width > 0 ? with_exact_size(ctx; width = Cell(Int32(max(0, authored_width - pad_x)))) :
                with_inner_size(ctx; width = pad_x)
    inner_ctx = with_free_axis(inner_ctx, :y)
    tim = w.title isa Document ? print_child(recursion, w.title, inner_ctx) : nothing
    # A `LayoutConstraint` around the content is how a caller pins the body's
    # height — a collapsed card showing one row of what it holds. The card does
    # the clipping rather than the caller, because the caller does not know the
    # card's inner width and would have to invent one; the card does know it.
    #
    # With no width to give — nothing offered — there is no viewport to build, so
    # the body draws in full. A clip is a promise about a width, and there is none.
    body, body_ctx = _card_body(w.content, inner_ctx)
    cim = body isa Document ? print_child(recursion, body, body_ctx) : nothing
    build = Cell(@computation _card_build(p, w, ctx, tim, cim))
    # The ring over the slot the card's selection names as a whole.
    ring = make_selection_ring(() -> begin
        for entry in build[].child_iomaps
            entry === nothing && continue
            (x, y, child) = entry
            name = _card_slot_name(w, child)
            (name !== nothing && is_whole_selected_field(w.selection, name)) || continue
            return _get_entry_box(x, y, child, _p_measure(p))
        end
        nothing
    end, p.graphics_style)
    outer = GraphicsCanvas(Cell(Int32(ox)), Cell(Int32(oy)),
                           Cell(@computation Int32(build[].w)),
                           Cell(@computation Int32(build[].h)),
                           CellVector(@computation vcat(build[].elements, Any[ring])),
                           layout_none, true, Cell(nothing))
    ChildrenIoMap(p, w, outer, Cell(@computation build[].child_iomaps))
end

# ── The card's two document slots ───────────────────────────────────────────
#
# A card owns a real reference step: its body hangs off `.content` and a Document
# header off `.title`. Both maps and the reader name the slot they travel
# through, the way `WidgetShellToGraphicsCanvas` names its four.

_card_slot_value(w::WidgetCard, name::AbstractString) =
    name == "content" ? w.content :
    name == "title"   ? w.title   : nothing

# The slot a recursed child sits in, or `nothing` for a child that is neither.
function _card_slot_name(w::WidgetCard, cim)
    cim === nothing && return nothing
    input = cim.input
    input === w.content && return "content"
    input === w.title   && return "title"
    nothing
end

# Prepend the slot a child answered from, so a path an inner reader produced
# arrives in the card's own input domain. An operation that carries its own root
# (a control's activation, a hover flag) passes through `reroot_operation`
# unchanged.
function _card_reroot(w::WidgetCard, cim, op)
    op === nothing && return nothing
    name = _card_slot_name(w, cim)
    name === nothing && return op
    reroot_operation(op, (FieldReferenceStep(name),))
end

# Route a coordinate-bearing event to the child under the pointer and re-root its
# answer by the slot that child sits in. `_route_to_children` cannot do this: it
# reports the operation without saying which child produced it, and a card's two
# slots need two different steps.
function _card_route(w::WidgetCard, entries::Vector, evt, make_evt)
    hit = _find_child_hit(entries, evt, make_evt)
    hit === nothing ? nothing : _card_reroot(w, hit[2], hit[1])
end

# The answer of the slot that `hit` names, `(answer, child_iomap)` or `nothing`,
# re-rooted by the step of that slot, and read over the stretch of the card for a
# dwell or a right click (`read_container_gesture`).
function _read_card_hit(w::WidgetCard, gesture, hit)
    hit === nothing && return read_container_gesture(nothing, gesture, w)
    (answer, cim) = hit
    name = _card_slot_name(w, cim)
    steps = name === nothing ? () : (FieldReferenceStep(name),)
    read_container_gesture(_card_reroot(w, cim, answer), gesture, w; steps)
end

# A move of the pointer: the slot that the card's own mouse target names (the
# pointer leaves it), then the slot under the point.
function _read_card_move(w::WidgetCard, entries::Vector, evt::MouseMove)
    hit = _find_child_hit(entries, evt,
        (x, y) -> MouseMove(x, y, evt.buttons, evt.modifiers; time = evt.time))
    new_answer = hit === nothing ? nothing : _card_reroot(w, hit[2], hit[1])
    target = get_mouse_target(w)
    target isa ConcreteReference && target.head isa FieldReferenceStep || return new_answer
    for entry in entries
        entry === nothing && continue
        cim = last(entry)
        _card_slot_name(w, cim) == target.head.name || continue
        hit !== nothing && hit[2] === cim && return new_answer
        old_answer = read_child_leave(cim, evt, get_child_frame_offset(entry)...)
        return join_move_answers(_card_reroot(w, cim, old_answer), new_answer)
    end
    new_answer
end

# A click on a collapsible card's chevron is a fold gesture → toggle the card.
# Every other click routes into the card: the title and the content each read
# their own. A Document title is the card's first child entry, and its
# height is the height of the chevron's column.
function read_intent(p::WidgetCardToGraphicsCanvas, iomap::ChildrenIoMap, evt::MouseClick)
    _outside_widget(iomap, evt) && return nothing
    w = iomap.input
    entries = getfield(iomap, :child_iomaps)[]
    if w.title isa Document && !isempty(entries)
        _, _, tim = entries[1]
        tcanvas = tim.output
        box = tcanvas isa GraphicsCanvas ? _card_fold_box(p, w, Int(tcanvas.h)) : nothing
        if box !== nothing
            x0, y0, x1, y1 = box
            (x0 <= evt.x < x1 && y0 <= evt.y < y1) && return ToggleCollapseOperation(w)
        end
    end
    _read_card_hit(w, evt, _find_child_hit(entries, evt,
        (x, y) -> MouseClick(evt.button, x, y, evt.count, evt.modifiers;
                             time = evt.time)))
end
# Pointer events route into the card's content by coordinate, so an interactive
# widget nested in a card (a button, a row of a list) still sees the pointer
# motion and the raw press-down/release that drive its light and its `pressed`
# feedback. A dwell goes to the slot under the point, as a click does, and folds
# nothing. The scroll wheel is still the card's own concern to decline (nothing).
#
# A coordless keyboard event has no coordinate to hit-test, so it routes into the
# card's CONTENT selection-directed: forwarded only when the card's `selection`
# actually points inside it, so a card onto which nothing projects (every card in
# a plain display, where `selection === nothing`) behaves exactly as it did before.
function read_intent(::WidgetCardToGraphicsCanvas, iomap::ChildrenIoMap, evt)
    # A move that is off the card still goes to the slot the pointer leaves.
    _outside_widget(iomap, evt) && !(evt isa MouseMove) && return nothing
    w = iomap.input
    entries = getfield(iomap, :child_iomaps)[]
    evt isa MouseMove && return _read_card_move(w, entries, evt)
    evt isa MouseDwell &&
        return _read_card_hit(w, evt, _find_child_hit(entries, evt,
            (x, y) -> shift_event_position(evt, x - evt.x, y - evt.y)))
    evt isa MouseMove &&
        return _card_route(w, entries, evt,
                           (x, y) -> MouseMove(x, y, evt.buttons, evt.modifiers;
                                               time = evt.time))
    (evt isa MouseDown || evt isa MouseUp) &&
        return _card_route(w, entries, evt,
                           (x, y) -> evt isa MouseDown ? MouseDown(evt.button, x, y, evt.modifiers;
                                                                   time = evt.time) :
                                                         MouseUp(evt.button, x, y, evt.modifiers;
                                                                 time = evt.time))
    evt isa MouseScroll && return nothing
    getfield(w, :selection)[] === nothing && return nothing
    for entry in entries
        entry === nothing && continue
        (_, _, cim) = entry::Tuple{Int,Int,Any}
        cim.input === w.content || continue
        return _card_reroot(w, cim, read_intent(cim.projection, cim, evt))
    end
    nothing
end

map_reference_forward(::WidgetCardToGraphicsCanvas, iomap::ChildrenIoMap, reference) = _map_child_forward(iomap, reference)
map_reference_forward(::WidgetCardToGraphicsCanvas, iomap, reference) = _map_child_forward(iomap, reference)

# The body slot, for a caller that re-roots a path out of the card without having
# routed the event itself. The reader does not come through here: it knows which
# of the two slots answered and prepends that one (`_card_reroot`).
map_reference_backward(::WidgetCardToGraphicsCanvas, iomap, reference) =
    reference === nothing ? nothing :
    find_reference_point(reference) !== nothing ? _map_child_point(iomap, reference) :
    ConcreteReference(FieldReferenceStep("content"), reference)

# ── WidgetSwitch ────────────────────────────────────────────────────────────

@projection UntrackedCell struct WidgetSwitchToGraphicsCanvas
    measure::TextMeasure
    margin::Inset
    border::Inset
    padding::Inset
    margin_color::StyleColor
    border_color::StyleColor
    padding_color::StyleColor
    content_color::StyleColor
    track_size::Point2D        # width × height of the track
    knob_padding::Int          # inset of the knob from the track edge
    track_color::StyleColor          # track fill when off
    track_checked_color::StyleColor  # track fill when on
    track_disabled_color::StyleColor # track fill when !enabled
    knob_color::StyleColor     # knob fill
    knob_stroke::StyleStroke   # knob outline (color + width)
    focus_ring_stroke::StyleStroke
    label_text::StyleText      # the label after the track
    label_disabled_text::StyleText
    label_gap::Int             # between the track and its label
end

WidgetSwitchToGraphicsCanvas(theme; measure,
                             margin = inset_default, border = inset_default, padding = inset_default,
                             margin_color = color_transparent, border_color = color_transparent,
                             padding_color = color_transparent, content_color = color_transparent,
                             track_size = _themed(Point2D, theme, t -> t.switch_track),
                             knob_padding = _themed(Int, theme, t -> t.switch_knob_padding),
                             track_color = _themed(StyleColor, theme, t -> t.track_off),
                             track_checked_color = _themed(StyleColor, theme, t -> t.primary),
                             track_disabled_color = _themed(StyleColor, theme, t -> t.muted),
                             knob_color = _themed(StyleColor, theme, t -> t.knob),
                             knob_stroke = _themed(StyleStroke, theme, t -> StyleStroke(t.border, t.border_width)),
                             focus_ring_stroke = _themed(StyleStroke, theme, t -> StyleStroke(t.ring, t.ring_width)),
                             label_text = _themed(StyleText, theme, _get_body_text),
                             label_disabled_text =
                                 _themed(StyleText, theme, t -> StyleText(t.font, t.muted_foreground)),
                             label_gap = _themed(Int, theme, t -> t.label_gap)) =
    WidgetSwitchToGraphicsCanvas(measure, margin, border, padding, margin_color, border_color,
                                 padding_color, content_color, track_size, knob_padding, track_color,
                                 track_checked_color, track_disabled_color, knob_color, knob_stroke,
                                 focus_ring_stroke, label_text, label_disabled_text, label_gap)

function print_document(p::WidgetSwitchToGraphicsCanvas, recursion, w::WidgetSwitch, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    position = w.position::Point2D
    SimpleIoMap(p, w, _reactive_canvas(_origin(position)..., () -> begin
        on  = w.checked === true
        enabled = !(w.enabled === false)
        state = !enabled ? :disabled : on ? :checked : nothing
        track_width  = Int(p.track_size.x[])
        track_height = Int(p.track_size.y[])
        box = _get_box_insets(p, w)
        colors = _get_box_colors(p, w; state)
        inset_width, inset_height = _inset_total(p, w)
        label_x, label_y = _content_offset(p, w)
        content = _get_mark_label_layout(p, w, track_width, track_height, enabled)
        content_x, content_y = label_x, label_y + content.mark_y
        elements = Any[]
        _push_box_parts!(elements, box, colors, content.width, content.height)
        _push_mark_label!(elements, p, content, label_x, label_y)
        track_color = _get_state_color(p, w, :track; state)
        push!(elements, GraphicsRect(content_x, content_y, track_width, track_height; color = track_color, radius = track_height ÷ 2))
        knob_padding = p.knob_padding
        knob_radius  = (track_height - 2knob_padding) ÷ 2
        left_x  = content_x + knob_padding + knob_radius
        right_x = content_x + track_width - knob_padding - knob_radius
        knob_color = _get_state_color(p, w, :knob; state)
        knob_stroke = _get_state_stroke(p, w, :knob; state)
        knob = GraphicsCircle(on ? right_x : left_x, content_y + track_height ÷ 2, knob_radius; color = knob_color,
                              border_width=max(1, Int(knob_stroke.width)), border_color=knob_stroke.color)
        # The knob snaps to its new position. A slide needs a start time on the
        # editor's clock, and the reader of the switch has no context that reaches it.
        push!(elements, knob)
        outer_width, outer_height = content.width + inset_width, content.height + inset_height
        _push_focus_ring!(elements, w, outer_width, outer_height, p.focus_ring_stroke, track_height ÷ 2)
        (width=outer_width, height=outer_height, elements=elements)
    end))
end

# A click, or Return or Space on the focused switch, toggles `checked`.
_switch_toggle(w::WidgetSwitch) =
    ReplaceReferencedValueOperation(w,
        ConcreteReference(FieldReferenceStep("checked"), EmptyReference()),
        !(w.checked === true))

function read_intent(::WidgetSwitchToGraphicsCanvas, iomap::SimpleIoMap, evt::MouseClick)
    _outside_widget(iomap, evt) && return nothing
    w = iomap.input
    w.enabled === false && return nothing   # a disabled switch swallows the click
    op = read_bound_gesture(w, evt); op === nothing || return op   # per-instance gestures win
    evt.button === :left || return nothing
    _switch_toggle(w)
end

function read_intent(::WidgetSwitchToGraphicsCanvas, iomap::SimpleIoMap, evt)
    _outside_widget(iomap, evt) && return nothing
    w = iomap.input
    w.enabled === false && return nothing
    op = read_bound_gesture(w, evt); op === nothing || return op   # per-instance gestures win
    _is_plain_key(evt, :return, :space) || return nothing
    _switch_toggle(w)
end

map_reference_forward(::WidgetSwitchToGraphicsCanvas, iomap, reference) = _map_child_forward(iomap, reference)
map_reference_backward(::WidgetSwitchToGraphicsCanvas, iomap, reference) = nothing

# ── WidgetProgressBar ───────────────────────────────────────────────────────

@projection UntrackedCell struct WidgetProgressBarToGraphicsCanvas
    margin::Inset
    border::Inset
    padding::Inset
    margin_color::StyleColor
    border_color::StyleColor
    padding_color::StyleColor
    content_color::StyleColor
    bar_height::Int
    track_color::StyleColor          # unfilled track
    indicator_color::StyleColor      # filled portion
    indeterminate_share::Float64     # the part of the track that moves while the value is not known
    indeterminate_period::Float64    # the seconds of one pass from the start to the end
end

WidgetProgressBarToGraphicsCanvas(theme;
                                  margin = inset_default, border = inset_default, padding = inset_default,
                                  margin_color = color_transparent, border_color = color_transparent,
                                  padding_color = color_transparent, content_color = color_transparent,
                                  bar_height = _themed(Int, theme, t -> t.progress_bar_height),
                                  track_color = _themed(StyleColor, theme, t -> t.muted),
                                  indicator_color = _themed(StyleColor, theme, t -> t.primary),
                                  indeterminate_share = 0.25, indeterminate_period = 1.0) =
    WidgetProgressBarToGraphicsCanvas(margin, border, padding, margin_color, border_color, padding_color,
                                      content_color, bar_height, track_color, indicator_color,
                                      indeterminate_share, indeterminate_period)

function print_document(p::WidgetProgressBarToGraphicsCanvas, recursion, w::WidgetProgressBar, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    position = w.position::Point2D
    clock = ctx === nothing ? nothing : ctx.clock
    SimpleIoMap(p, w, _reactive_canvas(_origin(position)..., () -> begin
        box = _get_box_insets(p, w)
        colors = _get_box_colors(p, w)
        inset_width, inset_height = _inset_total(p, w)
        content_x, content_y = _content_offset(p, w)
        bar_authored = _sc(Int(w.width))
        outer_width  = _resolve_width(ctx, bar_authored > 0 ? bar_authored + inset_width : 0, inset_width)
        # The thickness is `Fixed` and NOT the content, which is the one place
        # step 8's word does not survive the rule: a number passed as content
        # loses to an offer, and a progress bar 700 pixels thick is not a
        # progress bar. A widget that cannot measure its own extent has authored
        # the number it draws.
        outer_height = _resolve_height(ctx, p.bar_height + inset_height, inset_height)
        bar_width, bar_height = outer_width - inset_width, outer_height - inset_height
        elements = Any[]
        _push_box_parts!(elements, box, colors, bar_width, bar_height)
        track_color = _get_state_color(p, w, :track)
        indicator_color = _get_state_color(p, w, :indicator)
        push!(elements, GraphicsRect(content_x, content_y, bar_width, bar_height; color = track_color, radius = bar_height ÷ 2))
        # Two rectangles show the value for the life of the bar, and only their
        # places and widths read the value, as the arc of a ring does. A known
        # value fills the first from the start. While the value is not known, a
        # part of the track moves from the start to the end once a period: the
        # first rectangle is what is before the end, and the second what passed
        # the end and shows at the start. Only then do they read the clock.
        period = p.indeterminate_period
        segment_width = round(Int, p.indeterminate_share * bar_width)
        compute_offset() = round(Int, _get_clock_phase(clock, period) * bar_width)
        compute_head_x() = w.value === nothing ? compute_offset() : 0
        compute_head_width() = w.value === nothing ? min(segment_width, bar_width - compute_offset()) :
                                                     round(Int, clamp(Float64(w.value), 0.0, 1.0) * bar_width)
        compute_tail_width() = w.value === nothing ? max(0, compute_offset() + segment_width - bar_width) : 0
        push!(elements, GraphicsRect(() -> content_x + compute_head_x(), content_y, compute_head_width, bar_height;
                                     color = indicator_color, radius = bar_height ÷ 2))
        push!(elements, GraphicsRect(content_x, content_y, compute_tail_width, bar_height;
                                     color = indicator_color, radius = bar_height ÷ 2))
        (width=outer_width, height=outer_height, elements=elements)
    end))
end
@_printer_only WidgetProgressBarToGraphicsCanvas

# ── WidgetProgressRing ──────────────────────────────────────────────────────

@projection UntrackedCell struct WidgetProgressRingToGraphicsCanvas
    measure::TextMeasure
    margin::Inset
    border::Inset
    padding::Inset
    margin_color::StyleColor
    border_color::StyleColor
    padding_color::StyleColor
    content_color::StyleColor
    font::StyleFont                  # one line of it, times `ring_size`, is the diameter
    ring_size::Float64
    stroke_width::Int
    track_color::StyleColor          # the whole ring
    indicator_color::StyleColor      # the arc of the value
    indeterminate_share::Float64     # the part of the ring that turns while the value is not known
    indeterminate_period::Float64    # the seconds of one turn
end

WidgetProgressRingToGraphicsCanvas(theme; measure,
                                   margin = inset_default, border = inset_default, padding = inset_default,
                                   margin_color = color_transparent, border_color = color_transparent,
                                   padding_color = color_transparent, content_color = color_transparent,
                                   font = _themed(StyleFont, theme, t -> t.font),
                                   ring_size = _themed(Float64, theme, t -> t.progress_ring_size),
                                   stroke_width = _themed(Int, theme, t -> t.stroke),
                                   track_color = _themed(StyleColor, theme, t -> t.muted),
                                   indicator_color = _themed(StyleColor, theme, t -> t.primary),
                                   indeterminate_share = 0.25, indeterminate_period = 1.0) =
    WidgetProgressRingToGraphicsCanvas(measure, margin, border, padding, margin_color, border_color,
                                       padding_color, content_color, font, ring_size, stroke_width,
                                       track_color, indicator_color, indeterminate_share,
                                       indeterminate_period)

# The part of `period` seconds that `clock` has run since its last whole period,
# from 0 up to 1. A read subscribes the caller to the clock, so the caller runs
# again on each tick. With no clock the phase stays 0.
_get_clock_phase(clock, period::Real) =
    clock === nothing ? 0.0 : mod(get_reactive_clock_time(clock) / period, 1.0)

# The sweep of the arc of a ring, in degrees: the share of a known value, or the
# turning part `share` while the value is not known.
_compute_ring_sweep(value::Nothing, share::Real) = 360 * share
_compute_ring_sweep(value::Real, share::Real) = 360 * clamp(Float64(value), 0.0, 1.0)

function print_document(p::WidgetProgressRingToGraphicsCanvas, recursion, w::WidgetProgressRing, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    position = w.position::Point2D
    clock = ctx === nothing ? nothing : ctx.clock
    SimpleIoMap(p, w, _reactive_canvas(_origin(position)..., () -> begin
        inset_width, inset_height = _inset_total(p, w)
        content_x, content_y = _content_offset(p, w)
        line = compute_line_box(p.measure, "", p.font).height
        radius = max(1, round(Int, scale_length(line, p.ring_size) / 2))
        # The ring authors no size. An exact range stretches its box, and the ring
        # stays at the start of the box and in its vertical middle.
        outer_width  = _resolve_width(ctx, 0, 2radius + inset_width)
        outer_height = _resolve_height(ctx, 0, 2radius + inset_height)
        content_width, content_height = outer_width - inset_width, outer_height - inset_height
        elements = Any[]
        _push_box_parts!(elements, _get_box_insets(p, w), _get_box_colors(p, w), content_width, content_height)
        cx, cy = content_x + radius, content_y + content_height ÷ 2
        stroke = clamp(p.stroke_width, 1, radius)
        push!(elements, GraphicsCircle(cx, cy, radius; color = color_transparent, border_width = stroke,
                                       border_color = _get_state_color(p, w, :track)))
        # One arc shows the value for the life of the ring, and only its two angles
        # read the value. While the value is not known, the start reads the clock,
        # so a tick moves the arc and runs nothing else of the ring. A known value
        # computes the start again without the clock, and that drops the
        # subscription: a cell lets go of what it read only when it computes again.
        period, share = p.indeterminate_period, p.indeterminate_share
        push!(elements, GraphicsArc(cx, cy, radius; width = stroke,
                                    color = _get_state_color(p, w, :indicator),
                                    start_angle = () -> w.value === nothing ?
                                                        360 * _get_clock_phase(clock, period) : 0.0,
                                    sweep_angle = () -> _compute_ring_sweep(w.value, share)))
        (width=outer_width, height=outer_height, elements=elements)
    end))
end
@_printer_only WidgetProgressRingToGraphicsCanvas

# ── WidgetSlider ────────────────────────────────────────────────────────────

@projection UntrackedCell struct WidgetSliderToGraphicsCanvas
    margin::Inset
    border::Inset
    padding::Inset
    margin_color::StyleColor
    border_color::StyleColor
    padding_color::StyleColor
    content_color::StyleColor
    height::Int                 # control height
    track_thickness::Int
    knob_radius::Int
    track_color::StyleColor          # unfilled track
    track_disabled_color::StyleColor
    indicator_color::StyleColor      # filled portion
    indicator_disabled_color::StyleColor
    knob_color::StyleColor           # knob fill
    knob_disabled_color::StyleColor
    knob_stroke::StyleStroke         # knob outline (color + width)
    focus_ring_stroke::StyleStroke
end

WidgetSliderToGraphicsCanvas(theme;
                             margin = inset_default, border = inset_default, padding = inset_default,
                             margin_color = color_transparent, border_color = color_transparent,
                             padding_color = color_transparent, content_color = color_transparent,
                             height = _themed(Int, theme, t -> t.slider_height),
                             track_thickness = _themed(Int, theme, t -> t.slider_track),
                             knob_radius = _themed(Int, theme, t -> t.slider_knob),
                             track_color = _themed(StyleColor, theme, t -> t.muted),
                             track_disabled_color = _themed(StyleColor, theme, t -> t.muted),
                             indicator_color = _themed(StyleColor, theme, t -> t.primary),
                             indicator_disabled_color = _themed(StyleColor, theme, t -> t.muted),
                             knob_color = _themed(StyleColor, theme, t -> t.knob),
                             knob_disabled_color = _themed(StyleColor, theme, t -> t.muted),
                             knob_stroke = _themed(StyleStroke, theme, t -> StyleStroke(t.primary, t.stroke)),
                             focus_ring_stroke = _themed(StyleStroke, theme, t -> StyleStroke(t.ring, t.ring_width))) =
    WidgetSliderToGraphicsCanvas(margin, border, padding, margin_color, border_color, padding_color,
                                 content_color, height, track_thickness, knob_radius, track_color,
                                 track_disabled_color, indicator_color, indicator_disabled_color,
                                 knob_color, knob_disabled_color, knob_stroke, focus_ring_stroke)

function print_document(p::WidgetSliderToGraphicsCanvas, recursion, w::WidgetSlider, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    position = w.position::Point2D
    # Resolved once, here, and handed to both halves: the printer draws the track
    # at this width and the reader turns a press into a value with it. The
    # track_width the IoMap stores is the width of the track itself, inside the
    # box.
    inset_width_only, _ = _inset_total(p, w)
    track_authored = _sc(Int(w.width))
    track_outer_width = _resolve_width(ctx, track_authored > 0 ? track_authored + inset_width_only : 0, inset_width_only)
    track_width = track_outer_width - inset_width_only
    WidgetSliderToGraphicsCanvasIoMap(p, w, _reactive_canvas(_origin(position)..., () -> begin
        enabled = !(w.enabled === false)
        state = enabled ? nothing : :disabled
        value = clamp(Float64(w.value), 0.0, 1.0)
        box = _get_box_insets(p, w)
        colors = _get_box_colors(p, w; state)
        inset_width, inset_height = _inset_total(p, w)
        content_x, content_y = _content_offset(p, w)
        slider_width  = track_width
        slider_height = _resolve_height(ctx, p.height + inset_height, inset_height) - inset_height
        center_y = content_y + slider_height ÷ 2
        track_thickness = p.track_thickness
        filled_width = round(Int, value * slider_width)
        elements = Any[]
        _push_box_parts!(elements, box, colors, slider_width, slider_height)
        track_c = _get_state_color(p, w, :track; state)
        indicator_c = _get_state_color(p, w, :indicator; state)
        knob_c  = _get_state_color(p, w, :knob; state)
        knob_stroke = _get_state_stroke(p, w, :knob; state)
        push!(elements, GraphicsRect(content_x, center_y - track_thickness ÷ 2, slider_width, track_thickness; color = track_c, radius = track_thickness ÷ 2))
        filled_width > 0 && push!(elements, GraphicsRect(content_x, center_y - track_thickness ÷ 2, filled_width, track_thickness; color = indicator_c, radius = track_thickness ÷ 2))
        push!(elements, GraphicsCircle(content_x + filled_width, center_y, p.knob_radius; color = knob_c,
                                       border_width=max(1, Int(knob_stroke.width)), border_color=knob_stroke.color))
        outer_width, outer_height = slider_width + inset_width, slider_height + inset_height
        _push_focus_ring!(elements, w, outer_width, outer_height, p.focus_ring_stroke, slider_height ÷ 2)
        (width=outer_width, height=outer_height, elements=elements)
    end), track_width)
end

# The track width the printer drew with, so a press is turned into a value by the
# same geometry the screen has. A reader that resolved the width for itself would
# answer for a track the screen never had — the toggle group's segment widths are
# carried for the same reason.
@iomap struct WidgetSliderToGraphicsCanvasIoMap
    projection::Any
    input::Any
    output::Any
    track_width::Any
end

map_reference_forward(::WidgetSliderToGraphicsCanvas, iomap, reference) = _map_child_forward(iomap, reference)
map_reference_backward(::WidgetSliderToGraphicsCanvas, iomap, reference) = nothing

# Invisible slider (the printer returned a bare empty canvas): inert.
read_intent(::WidgetSliderToGraphicsCanvas, iomap::SimpleIoMap, evt) = nothing

# Where along the track `x` falls, as a fraction. Clamped, so a drag that leaves
# the control at either end pins rather than runs away — which is what a slider
# does everywhere and what a reader that only accepted inside-the-track presses
# would get wrong.
_slider_value(track_width::Int, x::Real) =
    track_width <= 0 ? 0.0 : clamp(Float64(x) / track_width, 0.0, 1.0)

# A press picks a value and takes the knob; a move keeps writing while it is
# held; a release lets go. Three events, because a slider is the one control here
# whose whole point is the drag — a press-only slider would answer a click on the
# track and ignore the gesture a person actually makes.
#
# The knob is taken on the raw `MouseDown`. The gesture recognizer makes a
# `MouseClick` only after the `MouseUp`, and only when the up is near the down,
# which a drag never is. A `MouseClick` sets the value and takes nothing: it is
# the click a script sends, and after a real click the knob already has its value.
#
# The value write names the slider's `target` when it has one, so a control that
# is *for* something says so in the operation itself.
function read_intent(p::WidgetSliderToGraphicsCanvas,
                     iomap::WidgetSliderToGraphicsCanvasIoMap, evt)
    w = iomap.input
    w.enabled === false && return nothing
    width  = Int(iomap.track_width)
    content_x, _ = _content_offset(p, w)
    resolve_write_at(x) = resolve_slider_write(w, _slider_value(width, x - content_x))
    @gesture_case evt begin
        MouseDown(button, x, y) => begin
            button === :left || return nothing
            _outside_widget(iomap, evt) && return nothing
            document, field, value = resolve_write_at(x)
            # Taking the knob is a second write, and it is on the slider itself
            # rather than on the target: what is held is a property of the
            # control, not of the value it stands for. The drag starts at the
            # press, so the knob follows the pointer from the first pixel, also
            # off the slider; the value at the press comes back on `DragCancel`.
            # The pointer keeps the arrow of the press while the drag is on, also
            # over a part that has a shape of its own.
            CompoundOperation(Any[_write_view_state(w, "dragging", true),
                                  _write_view_state(w, "press_value", Float64(w.value)),
                                  ReplaceReferencedValueOperation(document, field, value),
                                  StartDragOperation(EmptyReference(), nothing),
                                  make_screen_pointer_shape_operation(:arrow)])
        end
        MouseClick(button, x, y) => begin
            button === :left || return nothing
            _outside_widget(iomap, evt) && return nothing
            document, field, value = resolve_write_at(x)
            # A value the knob already has is not written again, so a real
            # click leaves one step in the history; the press is still taken.
            Float64(w.value) == value && return _write_view_state(w, "dragging", false)
            ReplaceReferencedValueOperation(document, field, value)
        end
        DragMove(x, y) => begin
            # A drag that wanders off the control still moves it, which is the
            # whole difference between a slider and a row of buttons: the drag
            # comes by the path of the slider, wherever the pointer is.
            w.dragging === true || return nothing
            document, field, value = resolve_write_at(x)
            Float64(w.value) == value && return nothing
            ReplaceReferencedValueOperation(document, field, value)
        end
        DragEnd => _end_slider_drag(w)
        DragCancel => begin
            ending = _end_slider_drag(w)
            ending === nothing && return nothing
            start = w.press_value
            (start isa Real && Float64(w.value) != Float64(start)) || return ending
            document, field, value = resolve_slider_write(w, Float64(start))
            CompoundOperation(Any[ending, ReplaceReferencedValueOperation(document, field, value)])
        end
        _ => nothing
    end
end

# The end of the drag of a slider: the knob is no longer held, and the pointer
# takes the shape of the part under it again.
function _end_slider_drag(w::WidgetSlider)
    w.dragging === true || return nothing
    CompoundOperation(Any[_write_view_state(w, "dragging", false),
                          _write_view_state(w, "press_value", nothing),
                          make_screen_pointer_shape_operation(nothing)])
end

# ── WidgetRadioGroup ────────────────────────────────────────────────────────

@projection UntrackedCell struct WidgetRadioGroupToGraphicsCanvas
    measure::TextMeasure
    margin::Inset
    border::Inset
    padding::Inset
    margin_color::StyleColor
    border_color::StyleColor
    padding_color::StyleColor
    content_color::StyleColor
    label_text::StyleText          # option labels
    label_disabled_text::StyleText
    indicator_color::StyleColor           # the circle
    indicator_stroke::StyleStroke         # the ring, unselected
    indicator_selected_stroke::StyleStroke # the ring, selected
    indicator_disabled_stroke::StyleStroke
    dot_color::StyleColor                 # selected inner dot
    dot_disabled_color::StyleColor
    focus_ring_stroke::StyleStroke
    button_size::Int               # outer circle diameter
    label_gap::Int                 # gap between button and label
    row_gap::Int
    dot_radius::Int                # selected inner dot
end

WidgetRadioGroupToGraphicsCanvas(theme; measure,
                                 margin = inset_default, border = inset_default, padding = inset_default,
                                 margin_color = color_transparent, border_color = color_transparent,
                                 padding_color = color_transparent, content_color = color_transparent,
                                 label_text = _themed(StyleText, theme, _get_body_text),
                                 label_disabled_text =
                                     _themed(StyleText, theme, t -> StyleText(t.font, t.muted_foreground)),
                                 indicator_color = _themed(StyleColor, theme, t -> t.background),
                                 indicator_stroke = _themed(StyleStroke, theme, t -> StyleStroke(t.input, t.stroke)),
                                 indicator_selected_stroke =
                                     _themed(StyleStroke, theme, t -> StyleStroke(t.primary, t.stroke)),
                                 indicator_disabled_stroke =
                                     _themed(StyleStroke, theme, t -> StyleStroke(t.muted_foreground, t.stroke)),
                                 dot_color = _themed(StyleColor, theme, t -> t.primary),
                                 dot_disabled_color = _themed(StyleColor, theme, t -> t.muted_foreground),
                                 focus_ring_stroke = _themed(StyleStroke, theme, t -> StyleStroke(t.ring, t.ring_width)),
                                 button_size = _themed(Int, theme, t -> t.indicator_size),
                                 label_gap = _themed(Int, theme, t -> t.label_gap),
                                 row_gap = _themed(Int, theme, t -> t.section_gap),
                                 dot_radius = _themed(Int, theme, t -> t.indicator_dot)) =
    WidgetRadioGroupToGraphicsCanvas(measure, margin, border, padding, margin_color, border_color,
                                     padding_color, content_color, label_text, label_disabled_text,
                                     indicator_color, indicator_stroke, indicator_selected_stroke,
                                     indicator_disabled_stroke, dot_color, dot_disabled_color,
                                     focus_ring_stroke, button_size, label_gap, row_gap, dot_radius)

# The rows of the options, so a press is answered by the row it landed in. The
# printer derives them in the build that draws the rows, and the reader reads
# them from here, so the two can not disagree. PAR-STABLE-IOMAP-IDENTITY.
@iomap struct WidgetRadioGroupToGraphicsCanvasIoMap
    projection::Any
    input::Any
    output::Any
    row_bounds::Any
end

function print_document(p::WidgetRadioGroupToGraphicsCanvas, recursion, w::WidgetRadioGroup, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    position = w.position::Point2D
    build = Cell(@computation begin
        enabled = !(w.enabled === false)
        selected = Int(w.selected)
        diameter = p.button_size
        label_gap = p.label_gap
        row_gap = p.row_gap
        box = _get_box_insets(p, w)
        colors = _get_box_colors(p, w)
        inset_width, inset_height = _inset_total(p, w)
        content_x, content_y = _content_offset(p, w)
        # Two passes: the rows are measured first, because a row can be wider
        # than its content when the offer fills more (the rule for a box whose
        # content can grow), and `_push_box_parts!` must see that final size.
        rows = Any[]
        y = 0
        max_width = 0
        for (i, opt) in enumerate(w.options)
            state = !enabled ? :disabled : i == selected ? :selected : nothing
            label = _get_state_text(p, w, :label; state)
            label_str = string(opt)
            label_width, label_height = _text_size(p.measure, label.font, label_str)
            row_height = max(diameter, label_height)
            push!(rows, (i, state, label, label_str, label_width, label_height, row_height, y))
            max_width = max(max_width, diameter + label_gap + label_width)
            y += row_height + row_gap
        end
        content_width  = max_width
        content_height = max(0, y - row_gap)
        group_width  = _resolve_width(ctx, 0, content_width + inset_width) - inset_width
        group_height = _resolve_height(ctx, 0, content_height + inset_height) - inset_height
        elements = Any[]
        row_bounds = Tuple{Int,Int}[]
        _push_box_parts!(elements, box, colors, group_width, group_height)
        for (i, state, label, label_str, label_width, label_height, row_height, row_y) in rows
            center_y = content_y + row_y + row_height ÷ 2
            cx = content_x + diameter ÷ 2
            indicator_color = _get_state_color(p, w, :indicator; state)
            indicator_stroke = _get_state_stroke(p, w, :indicator; state)
            push!(elements, GraphicsCircle(cx, center_y, diameter ÷ 2; color = indicator_color,
                                           border_width=max(1, Int(indicator_stroke.width)), border_color=indicator_stroke.color))
            if i == selected
                dot_color = _get_state_color(p, w, :dot; state)
                push!(elements, GraphicsCircle(cx, center_y, p.dot_radius; color = dot_color))
            end
            _push_text!(elements, p.measure, label.font, label_str, content_x + diameter + label_gap,
                       content_y + row_y + (row_height - label_height) ÷ 2, label.color)
            push!(row_bounds, (content_y + row_y, content_y + row_y + row_height))
        end
        outer_width, outer_height = group_width + inset_width, group_height + inset_height
        _push_focus_ring!(elements, w, outer_width, outer_height, p.focus_ring_stroke, 0)
        (width=outer_width, height=outer_height, elements=elements, row_bounds=row_bounds)
    end)
    WidgetRadioGroupToGraphicsCanvasIoMap(p, w, _reactive_canvas_cell(_origin(position)..., build),
                                          Cell(@computation build[].row_bounds))
end

map_reference_forward(::WidgetRadioGroupToGraphicsCanvas, iomap, reference) = _map_child_forward(iomap, reference)
map_reference_backward(::WidgetRadioGroupToGraphicsCanvas, iomap, reference) = nothing

# Invisible group (the printer returned a bare empty canvas): inert.
read_intent(::WidgetRadioGroupToGraphicsCanvas, iomap::SimpleIoMap, evt) = nothing

# The option an arrow key moves to: the next or the previous one, around the
# ends, and the first or the last one when no option is on.
function _step_radio_option(selected::Int, count::Int, step::Int)
    (1 <= selected <= count) || return step > 0 ? 1 : count
    mod1(selected + step, count)
end

# A left press on the row of an option selects it: its circle and its label are
# one target. While the group has the focus, the arrow keys select the next or the
# previous option, and Return and Space select the first one when no option is on.
# The option that is already on is not a change, so it answers nothing.
function read_intent(::WidgetRadioGroupToGraphicsCanvas,
                     iomap::WidgetRadioGroupToGraphicsCanvasIoMap, evt)
    _outside_widget(iomap, evt) && return nothing
    w = iomap.input
    w.enabled === false && return nothing
    count = length(w.options)
    count == 0 && return nothing
    selected = Int(w.selected)
    option = if evt isa MouseClick
        evt.button === :left || return nothing
        _find_row_index(iomap.row_bounds, evt.y)
    elseif _is_plain_key(evt, :down, :right)
        _step_radio_option(selected, count, 1)
    elseif _is_plain_key(evt, :up, :left)
        _step_radio_option(selected, count, -1)
    elseif _is_plain_key(evt, :return, :space)
        1 <= selected <= count ? nothing : 1
    else
        nothing
    end
    (option === nothing || option == selected) && return nothing
    ReplaceReferencedValueOperation(w, "selected", option)
end

# ── WidgetAvatar ────────────────────────────────────────────────────────────

@projection UntrackedCell struct WidgetAvatarToGraphicsCanvas
    measure::TextMeasure
    margin::Inset
    border::Inset
    padding::Inset
    margin_color::StyleColor
    border_color::StyleColor
    padding_color::StyleColor
    content_color::StyleColor      # circle fill
    label_text::StyleText          # font + color of the initials
end

WidgetAvatarToGraphicsCanvas(theme; measure,
                             margin = inset_default, border = inset_default, padding = inset_default,
                             margin_color = color_transparent, border_color = color_transparent,
                             padding_color = color_transparent,
                             content_color = _themed(StyleColor, theme, t -> t.muted),
                             label_text = _themed(StyleText, theme, t -> StyleText(t.font, t.muted_foreground))) =
    WidgetAvatarToGraphicsCanvas(measure, margin, border, padding, margin_color, border_color, padding_color,
                                 content_color, label_text)

# The margin, the border and the padding are rectangular bands; the content is a
# circle, so it is excluded from the box's own fill and drawn on top of it.
function print_document(p::WidgetAvatarToGraphicsCanvas, recursion, w::WidgetAvatar, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    position = w.position::Point2D
    SimpleIoMap(p, w, _reactive_canvas(_origin(position)..., () -> begin
        size = _sc(Int(w.size))
        radius = size ÷ 2
        box = _get_box_insets(p, w)
        colors = _get_box_colors(p, w)
        inset_width, inset_height = _inset_total(p, w)
        content_x, content_y = _content_offset(p, w)
        initials = string(w.initials)
        label = _get_state_text(p, w, :label)
        elements = Any[]
        _push_box_parts!(elements, box, merge(colors, (content = color_transparent,)), size, size; radius)
        push!(elements, GraphicsCircle(content_x + radius, content_y + radius, radius; color = colors.content))
        initials_width, initials_height = _text_size(p.measure, label.font, initials)
        _push_text!(elements, p.measure, label.font, initials, content_x + radius - initials_width ÷ 2,
                    content_y + radius - initials_height ÷ 2, label.color)
        (width=size + inset_width, height=size + inset_height, elements=elements)
    end))
end
@_printer_only WidgetAvatarToGraphicsCanvas

# ── WidgetAlert ─────────────────────────────────────────────────────────────

@projection UntrackedCell struct WidgetAlertToGraphicsCanvas
    measure::TextMeasure
    margin::Inset
    border::Inset
    padding::Inset
    margin_color::StyleColor
    border_color::StyleColor
    padding_color::StyleColor
    content_color::StyleColor
    title_text::StyleText
    description_text::StyleText        # muted description
    destructive_border_color::StyleColor
    destructive_title_text::StyleText
    title_gap::Int                     # gap between title and description
    corner_radius::Int
    label_gap::Int                     # gap between the icon and the title
    icon_size::Float64                # times the box of the icon, one line of the title
end

WidgetAlertToGraphicsCanvas(theme; measure,
                            margin = inset_default,
                            border = _themed(Inset, theme, t -> _make_uniform_inset(t.border_width)),
                            padding = _themed(Inset, theme, t -> _make_uniform_inset(t.container_padding)),
                            margin_color = color_transparent,
                            border_color = _themed(StyleColor, theme, t -> t.border),
                            padding_color = _themed(StyleColor, theme, t -> t.background),
                            content_color = _themed(StyleColor, theme, t -> t.background),
                            title_text = _themed(StyleText, theme, _get_title_text),
                            description_text = _themed(StyleText, theme, _get_caption_text),
                            destructive_border_color = _themed(StyleColor, theme, t -> t.destructive),
                            destructive_title_text =
                                _themed(StyleText, theme, t -> StyleText(t.font_bold, t.destructive)),
                            title_gap = _themed(Int, theme, t -> t.title_gap),
                            corner_radius = _themed(Int, theme, t -> t.radius),
                            label_gap = _themed(Int, theme, t -> t.label_gap),
                            icon_size = _themed(Float64, theme, t -> t.icon_size)) =
    WidgetAlertToGraphicsCanvas(measure, margin, border, padding, margin_color, border_color, padding_color,
                                content_color, title_text, description_text, destructive_border_color,
                                destructive_title_text, title_gap, corner_radius, label_gap,
                                icon_size)

function print_document(p::WidgetAlertToGraphicsCanvas, recursion, w::WidgetAlert, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    position = w.position::Point2D
    SimpleIoMap(p, w, _reactive_canvas(_origin(position)..., () -> begin
        variant = w.variant === :default ? nothing : w.variant
        box = _get_box_insets(p, w)
        colors = _get_box_colors(p, w; variant)
        inset_width, inset_height = _inset_total(p, w)
        content_x, content_y = _content_offset(p, w)
        title = _get_state_text(p, w, :title; variant)
        description = _get_state_text(p, w, :description; variant)
        elements = Any[]
        max_content_width = 0
        y = content_y
        title_string = string(w.title)
        title_width, title_height = _text_size(p.measure, title.font, title_string)
        # The icon stands before the title, in its color: a square of the height of
        # the title times `icon_size`. The row is as tall as the larger of the
        # icon and the title, and each is centred in it.
        icon_size = icon_width(w.icon, scale_length(title_height, p.icon_size))
        icon_gap = icon_size > 0 ? p.label_gap : 0
        row_height = max(icon_size, title_height)
        icon_size > 0 && _push_icon!(elements, w.icon, content_x, y + (row_height - icon_size) ÷ 2, icon_size,
                                     title.color)
        _push_text!(elements, p.measure, title.font, title_string, content_x + icon_size + icon_gap,
                    y + (row_height - title_height) ÷ 2, title.color)
        max_content_width = max(max_content_width, icon_size + icon_gap + title_width); y += row_height
        if w.description !== nothing
            y += p.title_gap
            description_string = string(w.description)
            description_width, description_height = _text_size(p.measure, description.font, description_string)
            _push_text!(elements, p.measure, description.font, description_string, content_x, y, description.color)
            max_content_width = max(max_content_width, description_width); y += description_height
        end
        alert_width = _resolve_width(ctx, _sc(Int(w.width)), max_content_width + inset_width)
        bottom_inset = box.margin[4] + box.border[4] + box.padding[4]
        alert_height = _resolve_height(ctx, 0, y + bottom_inset)
        surface = Any[]
        _push_box_parts!(surface, box, colors, alert_width - inset_width, alert_height - inset_height;
                         radius = p.corner_radius)
        append!(surface, elements)
        (width=alert_width, height=alert_height, elements=surface)
    end))
end
@_printer_only WidgetAlertToGraphicsCanvas

# ── WidgetSkeleton ──────────────────────────────────────────────────────────


# The drop-indicator surface: a translucent accent fill under a solid accent
# outline, so the called-out area reads over whatever it covers. It marks an
# area its caller sizes, so it keeps no insets (D11): a margin would move the
# mark away from that area.
@projection UntrackedCell struct WidgetHighlightToGraphicsCanvas
    content_color::StyleColor
    border_stroke::StyleStroke
    corner_radius::Int
end

WidgetHighlightToGraphicsCanvas(theme;
                                content_color = _themed(StyleColor, theme, t -> _with_alpha(t.primary, 0.25)),
                                border_stroke =
                                    _themed(StyleStroke, theme, t -> StyleStroke(t.primary, t.ring_width)),
                                corner_radius = _themed(Int, theme, t -> t.radius_small)) =
    WidgetHighlightToGraphicsCanvas(content_color, border_stroke, corner_radius)

# Everything here is read **inside** a cell, `position` and `visible` included: a
# highlight is moved and shown while it is already printed — that is its whole
# job — and a canvas whose origin was fixed at print time, or an IoMap returned
# early for an invisible widget, would never move or appear.
function print_document(p::WidgetHighlightToGraphicsCanvas, recursion, w::WidgetHighlight, ctx)
    position = getfield(w, :position)
    shown() = w.visible !== false
    x = Cell(@computation Int32(Int(position[].x[])))
    y = Cell(@computation Int32(Int(position[].y[])))
    width  = Cell(@computation Int32(shown() ? _resolve_width(ctx, max(0, _sc(Int(w.width)))) : 0))
    height = Cell(@computation Int32(shown() ? _resolve_height(ctx, max(0, _sc(Int(w.height)))) : 0))
    elements = CellVector(@computation begin
        cw, ch = Int(width[]), Int(height[])
        (cw <= 0 || ch <= 0) && return Any[]
        content_color = _get_state_color(p, w, :content)
        border_stroke = _get_state_stroke(p, w, :border)
        Any[GraphicsRect(0, 0, cw, ch; color = content_color, radius = p.corner_radius,
                         border_width = Int(border_stroke.width), border_color = border_stroke.color)]
    end)
    SimpleIoMap(p, w, GraphicsCanvas(x, y, width, height, elements,
                                     layout_none, true, Cell(nothing)))
end
@_printer_only WidgetHighlightToGraphicsCanvas

@projection UntrackedCell struct WidgetSkeletonToGraphicsCanvas
    margin::Inset
    border::Inset
    padding::Inset
    margin_color::StyleColor
    border_color::StyleColor
    padding_color::StyleColor
    content_color::StyleColor      # the block
    corner_radius::Int
end

WidgetSkeletonToGraphicsCanvas(theme;
                               margin = inset_default, border = inset_default, padding = inset_default,
                               margin_color = color_transparent, border_color = color_transparent,
                               # The padding and the content share the muted default (§4.4), so the
                               # block is one rounded surface, as it is with no padding inset drawn.
                               padding_color = _themed(StyleColor, theme, t -> t.muted),
                               content_color = _themed(StyleColor, theme, t -> t.muted),
                               corner_radius = _themed(Int, theme, t -> t.radius_small)) =
    WidgetSkeletonToGraphicsCanvas(margin, border, padding, margin_color, border_color, padding_color,
                                   content_color, corner_radius)

function print_document(p::WidgetSkeletonToGraphicsCanvas, recursion, w::WidgetSkeleton, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    position = w.position::Point2D
    SimpleIoMap(p, w, _reactive_canvas(_origin(position)..., () -> begin
        block_width  = _resolve_width(ctx, _sc(Int(w.width)))
        block_height = _resolve_height(ctx, _sc(Int(w.height)))
        box = _get_box_insets(p, w)
        colors = _get_box_colors(p, w)
        inset_width, inset_height = _inset_total(p, w)
        elements = Any[]
        _push_box_parts!(elements, box, colors, block_width, block_height; radius = p.corner_radius)
        (width=block_width + inset_width, height=block_height + inset_height, elements=elements)
    end))
end
@_printer_only WidgetSkeletonToGraphicsCanvas

# ── WidgetSwatch ────────────────────────────────────────────────────────────

# The square of a swatch: its color fills the padding and the content, inside a
# border of the theme, so a color near the background shows too.
@projection UntrackedCell struct WidgetSwatchToGraphicsCanvas
    margin::Inset
    border::Inset
    padding::Inset
    margin_color::StyleColor
    border_color::StyleColor
    swatch_size::Int
    corner_radius::Int
end

WidgetSwatchToGraphicsCanvas(theme;
                             margin = inset_default,
                             border = _themed(Inset, theme, t -> _make_uniform_inset(t.border_width)),
                             padding = inset_default,
                             margin_color = color_transparent,
                             border_color = _themed(StyleColor, theme, t -> t.border),
                             swatch_size = _themed(Int, theme, t -> t.swatch_size),
                             corner_radius = _themed(Int, theme, t -> t.radius_small)) =
    WidgetSwatchToGraphicsCanvas(margin, border, padding, margin_color, border_color, swatch_size,
                                 corner_radius)

function print_document(p::WidgetSwatchToGraphicsCanvas, recursion, w::WidgetSwatch, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    position = w.position::Point2D
    SimpleIoMap(p, w, _reactive_canvas(_origin(position)..., () -> begin
        side = w.size === nothing ? p.swatch_size : _sc(Int(w.size))
        box = _get_box_insets(p, w)
        colors = (margin = _get_state_color(p, w, :margin), border = _get_state_color(p, w, :border),
                  padding = w.color, content = w.color)
        inset_width, inset_height = _inset_total(p, w)
        elements = Any[]
        _push_box_parts!(elements, box, colors, side, side; radius = p.corner_radius)
        (width=side + inset_width, height=side + inset_height, elements=elements)
    end))
end
@_printer_only WidgetSwatchToGraphicsCanvas

# Push a small chevron centered at (cx, cy), `s` pixels from its center to its
# tips: the glyph of the icon font. `dir` ∈ :down :right.
function _push_chevron!(elems::Vector, cx::Int, cy::Int, s::Int, dir::Symbol, color::StyleColor)
    # The chevron glyph fills the middle half of its box, so a box of 4s puts its
    # tips `s` from the center, where a fold mark has them.
    _push_icon!(elems, dir === :right ? :chevron_right : :chevron_down, cx - 2s, cy - 2s, 4s, color)
    nothing
end

# A chevron at the same place, which points down while `is_open()` answers true
# and right otherwise. When both chevrons of the icon registry are one glyph each
# of one font file, the chevron is one text whose cell calls `is_open`, so a toggle
# changes the glyph and not the element list that holds it. Other icons are read
# here, in the computation of the caller.
function _push_open_chevron!(elems::Vector, cx::Int, cy::Int, s::Int, color::StyleColor,
                             is_open::Function)
    down, right = Any[], Any[]
    _push_chevron!(down, cx, cy, s, :down, color)
    _push_chevron!(right, cx, cy, s, :right, color)
    if length(down) == 1 && length(right) == 1 && only(down) isa GraphicsText &&
       only(right) isa GraphicsText && compute_font_path(only(down).font) == compute_font_path(only(right).font)
        # The two glyphs are read and dropped: the caller's computation must not
        # read the cell that reads `is_open`.
        down_text, right_text = only(down).text, only(right).text
        glyph = only(right)
        push!(elems, GraphicsText(() -> is_open() ? down_text : right_text, glyph.x, glyph.y;
                                  font = glyph.font, color = glyph.color))
    else
        append!(elems, is_open() ? down : right)
    end
    nothing
end

# ── Icons ─────────────────────────────────────────────────────────────────────
#
# An icon is a *named* value, not a `GraphicsImage`. A registry maps each name to a
# renderer with the uniform signature `(elems, x, y, size, color) -> nothing`; the
# widget printers ask the registry to draw an icon in a `size × size` box, tinted
# like text, and never branch on the backing.
#
# Every built-in icon is a glyph of the Lucide icon font (`asset/font/lucide.ttf`,
# ISC licence in `asset/font/Lucide-ISC.txt`), drawn through the text renderer. So
# an icon has the smooth edges of text on every backend, and all icons have one
# style. A raster picture drops in by name through `make_image_icon`.

const ICON_REGISTRY = Dict{Symbol,Function}()

"""
    register_icon!(name, renderer)

Register an icon `renderer(elems, x, y, size, color)` under `name`. The renderer
pushes graphics into `elems`, drawing within a `size × size` box at `(x, y)` and
tinting with `color`. Returns `name`.
"""
register_icon!(name::Symbol, renderer) = (ICON_REGISTRY[name] = renderer; name)

# Draw the named icon, if registered. `color` is the caller's foreground (already
# muted when the widget is disabled). Returns whether anything was drawn.
function _push_icon!(elems::Vector, name, x::Int, y::Int, size::Int, color::StyleColor)
    name === nothing && return false
    renderer = get(ICON_REGISTRY, name, nothing)
    renderer === nothing && return false
    renderer(elems, x, y, size, color)
    true
end

# Layout extent of an icon (square). Zero for `nothing` / unknown names so a widget
# without an icon is unchanged.
icon_width(name, size::Int) = (name !== nothing && haskey(ICON_REGISTRY, name)) ? size : 0

"""
    make_glyph_icon(font, codepoint)

An icon renderer that draws the character `codepoint` of the icon font `font`,
at the size of the icon box and in the caller's color. Only the file of `font`
counts: the glyph is drawn at the box size, whatever size `font` names. An icon
font whose ascent is its em, as Lucide's is, fills the box.
"""
make_glyph_icon(font::StyleFont, codepoint) =
    (elems, x, y, size, color) -> begin
        push!(elems, GraphicsText(string(Char(codepoint)), x, y; font = with_font_size(font, size), color))
    end

# A raster icon: blit an `ImageDocument`'s decoded pixels (NOT tinted — for art).
make_image_icon(image::ImageDocument) =
    (elems, x, y, size, color) -> begin
        data, _, _ = _image_payload(image)
        data === nothing || push!(elems, GraphicsImage(Int32(x), Int32(y), Int32(size), Int32(size), data))
    end

"""
    LUCIDE_ICON_GLYPHS

The built-in icons: each name and its code point in the Lucide icon font
(lucide-static 1.47.0). A name says what the picture shows, never which widget or
tool uses it, so a second use of a picture needs no second name. The Lucide name
is beside each code point.
"""
const LUCIDE_ICON_GLYPHS = (
    # Controls
    :chevron_down   => 0xe06d,  # chevron-down
    :arrow_left     => 0xe048,  # arrow-left
    :arrow_right    => 0xe049,  # arrow-right
    :arrow_up       => 0xe04a,  # arrow-up
    :arrow_down     => 0xe042,  # arrow-down
    :arrow_up_down  => 0xe37d,  # arrow-up-down
    :refresh        => 0xe145,  # refresh-cw
    :chevron_right  => 0xe06f,  # chevron-right
    :check          => 0xe06c,  # check
    :x              => 0xe1b2,  # x
    :close          => 0xe1b2,  # x
    :plus           => 0xe13d,  # plus
    :minus          => 0xe11c,  # minus
    :menu           => 0xe115,  # menu
    # Documents
    :file           => 0xe0c0,  # file
    :folder         => 0xe0d7,  # folder
    :save           => 0xe14d,  # save
    :pencil         => 0xe1f9,  # pencil
    :edit           => 0xe1f9,  # pencil
    :trash          => 0xe18e,  # trash-2
    :delete         => 0xe18e,  # trash-2
    :search         => 0xe151,  # search
    # A run
    :play           => 0xe13c,  # play
    :pause          => 0xe12e,  # pause
    :stop           => 0xe167,  # square
    :step_forward   => 0xe3ea,  # step-forward
    :step           => 0xe3ea,  # step-forward
    :finish         => 0xe0d1,  # flag
    :fast_forward   => 0xe0bd,  # fast-forward
    :chevrons_right => 0xe073,  # chevrons-right
    :skip_forward   => 0xe160,  # skip-forward
    :loader         => 0xe10a,  # loader-circle
    :circle_pause   => 0xe07f,  # circle-pause
    :circle_check   => 0xe226,  # circle-check
    :circle         => 0xe076,  # circle
    # The tools of a window
    :chat           => 0xe117,  # message-square
    :terminal       => 0xe20a,  # square-terminal
    :list           => 0xe5f4,  # logs
    :keyboard       => 0xe284,  # keyboard
    :warning        => 0xe193,  # triangle-alert
    :chart          => 0xe2a3,  # chart-column
    :chart_line     => 0xe2a5,  # chart-line
    :crosshair      => 0xe0ac,  # crosshair
    # Kinds of file
    :lambda         => 0xe780,  # lambda
    :braces         => 0xe36a,  # braces
    :pilcrow        => 0xe3a3,  # pilcrow
    :diamond        => 0xe2d2,  # diamond
    :hexagon        => 0xe0f3,  # hexagon
    :file_sliders   => 0xe5a0,  # file-sliders
    :palette        => 0xe1dd,  # palette
    :settings       => 0xe154,  # settings: a gear
    :sigma          => 0xe201,  # sigma
    # Who speaks
    :user           => 0xe19f,  # user
    :bot            => 0xe1bb,  # bot
    :dot            => 0xe44f,  # dot
)

for (name, codepoint) in LUCIDE_ICON_GLYPHS
    register_icon!(name, make_glyph_icon(StyleFont("Lucide", 20), codepoint))  # @style: the size that an icon glyph is registered at; the box of the icon scales it
end

"""
    find_icon_character(name) -> Char or nothing

The character of the built-in icon `name` in the Lucide font, or `nothing` for a
name the table does not hold. It is for a place that writes an icon as text in
`StyleFont("Lucide", 20)`, as a label does, rather than drawing it in a box.
"""
function find_icon_character(name::Symbol)
    for (known, codepoint) in LUCIDE_ICON_GLYPHS
        known === name && return Char(codepoint)
    end
    nothing
end

# ── WidgetToggle ────────────────────────────────────────────────────────────

@projection UntrackedCell struct WidgetToggleToGraphicsCanvas
    measure::TextMeasure
    margin::Inset
    border::Inset
    padding::Inset
    margin_color::StyleColor
    border_color::StyleColor
    padding_color::StyleColor
    content_color::StyleColor
    border_checked_color::StyleColor
    padding_checked_color::StyleColor
    content_checked_color::StyleColor
    padding_disabled_color::StyleColor
    content_disabled_color::StyleColor
    label_text::StyleText
    label_checked_text::StyleText
    label_disabled_text::StyleText
    focus_ring_stroke::StyleStroke
    corner_radius::Int
end

WidgetToggleToGraphicsCanvas(theme; measure,
                             margin = inset_default,
                             border = _themed(Inset, theme, t -> _make_uniform_inset(t.border_width)),
                             padding = _themed(Inset, theme, t -> t.control_padding),
                             margin_color = color_transparent,
                             border_color = _themed(StyleColor, theme, t -> t.border),
                             padding_color = _themed(StyleColor, theme, t -> t.background),
                             content_color = _themed(StyleColor, theme, t -> t.background),
                             border_checked_color = color_transparent,
                             padding_checked_color = _themed(StyleColor, theme, t -> t.accent),
                             content_checked_color = _themed(StyleColor, theme, t -> t.accent),
                             padding_disabled_color = _themed(StyleColor, theme, t -> t.muted),
                             content_disabled_color = _themed(StyleColor, theme, t -> t.muted),
                             label_text = _themed(StyleText, theme, _get_body_text),
                             label_checked_text =
                                 _themed(StyleText, theme, t -> StyleText(t.font, t.accent_foreground)),
                             label_disabled_text =
                                 _themed(StyleText, theme, t -> StyleText(t.font, t.muted_foreground)),
                             focus_ring_stroke = _themed(StyleStroke, theme, t -> StyleStroke(t.ring, t.ring_width)),
                             corner_radius = _themed(Int, theme, t -> t.radius)) =
    WidgetToggleToGraphicsCanvas(measure, margin, border, padding, margin_color, border_color,
                                 padding_color, content_color, border_checked_color, padding_checked_color,
                                 content_checked_color, padding_disabled_color, content_disabled_color,
                                 label_text, label_checked_text, label_disabled_text,
                                 focus_ring_stroke, corner_radius)

function print_document(p::WidgetToggleToGraphicsCanvas, recursion, w::WidgetToggle, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    position = w.position::Point2D
    SimpleIoMap(p, w, _reactive_canvas(_origin(position)..., () -> begin
        text = string(w.content)
        on  = w.pressed === true
        enabled = !(w.enabled === false)
        state = !enabled ? :disabled : on ? :checked : nothing
        label = _get_state_text(p, w, :label; state)
        text_width, text_height = _text_size(p.measure, label.font, text)
        box = _get_box_insets(p, w)
        colors = _get_box_colors(p, w; state)
        inset_width, inset_height = _inset_total(p, w)
        content_x, content_y = _content_offset(p, w)
        outer_width  = _resolve_width(ctx, 0, text_width + inset_width)
        outer_height = _resolve_height(ctx, 0, text_height + inset_height)
        content_width, content_height = outer_width - inset_width, outer_height - inset_height
        radius = p.corner_radius
        elements = Any[]
        _push_box_parts!(elements, box, colors, content_width, content_height; radius)
        _push_text!(elements, p.measure, label.font, text, content_x + (content_width - text_width) ÷ 2,
                    content_y + (content_height - text_height) ÷ 2, label.color)
        _push_focus_ring!(elements, w, outer_width, outer_height, p.focus_ring_stroke, radius)
        (width=outer_width, height=outer_height, elements=elements)
    end))
end

map_reference_forward(::WidgetToggleToGraphicsCanvas, iomap, reference) = _map_child_forward(iomap, reference)
map_reference_backward(::WidgetToggleToGraphicsCanvas, iomap, reference) = nothing

# A left press flips `pressed`, and so do Return and Space while the toggle has
# the focus: a container gives a key only to the child that its selection names.
function read_intent(::WidgetToggleToGraphicsCanvas, iomap::SimpleIoMap, evt)
    _outside_widget(iomap, evt) && return nothing
    w = iomap.input
    (w.visible === false || w.enabled === false) && return nothing
    activated = evt isa MouseClick ? evt.button === :left : _is_plain_key(evt, :return, :space)
    activated || return nothing
    ReplaceReferencedValueOperation(w, "pressed", !(w.pressed === true))
end

# ── WidgetToggleGroup ───────────────────────────────────────────────────────

@projection UntrackedCell struct WidgetToggleGroupToGraphicsCanvas
    measure::TextMeasure
    margin::Inset
    border::Inset
    padding::Inset
    margin_color::StyleColor
    border_color::StyleColor
    padding_color::StyleColor
    content_color::StyleColor
    padding_disabled_color::StyleColor
    content_disabled_color::StyleColor
    segment_color::StyleColor          # unselected segment fill
    segment_selected_color::StyleColor # raised segment fill
    segment_disabled_color::StyleColor
    label_text::StyleText
    label_selected_text::StyleText
    label_disabled_text::StyleText
    segment_padding::Inset             # a segment's own text padding
    focus_ring_stroke::StyleStroke
    corner_radius::Int
end

WidgetToggleGroupToGraphicsCanvas(theme; measure,
                                  margin = inset_default,
                                  border = _themed(Inset, theme, t -> _make_uniform_inset(t.border_width)),
                                  padding = _themed(Inset, theme, t -> _make_uniform_inset(t.toggle_group_padding)),
                                  margin_color = color_transparent,
                                  border_color = _themed(StyleColor, theme, t -> t.border),
                                  padding_color = _themed(StyleColor, theme, t -> t.muted),
                                  content_color = _themed(StyleColor, theme, t -> t.muted),
                                  padding_disabled_color = _themed(StyleColor, theme, t -> t.muted),
                                  content_disabled_color = _themed(StyleColor, theme, t -> t.muted),
                                  segment_color = color_transparent,
                                  segment_selected_color = _themed(StyleColor, theme, t -> t.background),
                                  segment_disabled_color = _themed(StyleColor, theme, t -> t.muted),
                                  label_text = _themed(StyleText, theme, t -> StyleText(t.font, t.muted_foreground)),
                                  label_selected_text = _themed(StyleText, theme, _get_body_text),
                                  label_disabled_text =
                                      _themed(StyleText, theme, t -> StyleText(t.font, t.muted_foreground)),
                                  segment_padding = _themed(Inset, theme, t -> t.control_padding),
                                  focus_ring_stroke = _themed(StyleStroke, theme, t -> StyleStroke(t.ring, t.ring_width)),
                                  corner_radius = _themed(Int, theme, t -> t.radius)) =
    WidgetToggleGroupToGraphicsCanvas(measure, margin, border, padding, margin_color, border_color,
                                      padding_color, content_color, padding_disabled_color, content_disabled_color,
                                      segment_color, segment_selected_color, segment_disabled_color,
                                      label_text, label_selected_text, label_disabled_text,
                                      segment_padding, focus_ring_stroke, corner_radius)

# The segment widths, so a press can be answered by the segment it landed in.
# They are derived from the same measurement the printer draws with, in the same
# build, rather than measured a second time in the reader — a reader that
# measured for itself would answer for a layout the screen never had.
# @iomap so the reader reads `iomap.segment_widths` transparently;
# PAR-STABLE-IOMAP-IDENTITY.
@iomap struct WidgetToggleGroupToGraphicsCanvasIoMap
    projection::Any
    input::Any
    output::Any
    segment_widths::Any
end

function print_document(p::WidgetToggleGroupToGraphicsCanvas, recursion, w::WidgetToggleGroup, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    position = w.position::Point2D
    build = Cell(@computation begin
        enabled = !(w.enabled === false)
        state = enabled ? nothing : :disabled
        selected = Int(w.selected)
        box = _get_box_insets(p, w)
        colors = _get_box_colors(p, w; state)
        inset_width, inset_height = _inset_total(p, w)
        content_x, content_y = _content_offset(p, w)
        segment_padding_x = Int(p.segment_padding.left[])
        segment_padding_y = Int(p.segment_padding.top[])
        labels = [string(o) for o in w.options]
        _, text_height = _text_size(p.measure, p.label_text.font, "M")
        # The segments divide what the control was given, and the control IS its
        # segments.
        #
        # Their labels are the floor — a segment never shrinks under its own text
        # — and every segment carries the same weight, so an offer is shared
        # equally. That is what makes filling safe here: the reader hit-tests a
        # press against these very widths, so segments that did not tile the
        # control would put the picture and the press in different places.
        #
        # With no offer the sum is the content and `allocate_axis` has nothing to
        # share, which is why every picture is unchanged.
        label_widths = Int[(_text_size(p.measure, p.label_text.font, l)[1] + 2segment_padding_x) for l in labels]
        segment_count = length(label_widths)
        offered_width = _resolve_width(ctx, 0, sum(label_widths; init=0) + inset_width) - inset_width
        segment_widths = segment_count == 0 ? label_widths :
            allocate_axis(offered_width; mins = copy(label_widths),
                          maxs = fill(typemax(Int), segment_count),
                          prefs = copy(label_widths), weights = fill(1.0, segment_count),
                          gap = 0, n = segment_count)
        content_height = _resolve_height(ctx, 0, text_height + 2segment_padding_y + inset_height) - inset_height
        content_width  = sum(segment_widths; init=0)
        corner_radius = p.corner_radius
        # The content radius, less the border and the padding that lie between
        # it and the rounded outline — the same rule `_push_box_parts!` applies
        # to its own content part.
        segment_radius = max(0, corner_radius - box.border[1] - box.padding[1])
        elements = Any[]
        _push_box_parts!(elements, box, colors, content_width, content_height; radius = corner_radius)
        x = content_x
        for i in eachindex(labels)
            segment_width = segment_widths[i]
            segment_state = i == selected ? (enabled ? :selected : :disabled) : nothing
            segment_color = _get_state_color(p, w, :segment; state = segment_state)
            _push_panel!(elements, x, content_y, segment_width, content_height;
                        fill = segment_color, radius = segment_radius)
            label_state = !enabled ? :disabled : i == selected ? :selected : nothing
            label = _get_state_text(p, w, :label; state = label_state)
            text_width, segment_text_height = _text_size(p.measure, label.font, labels[i])
            _push_text!(elements, p.measure, label.font, labels[i], x + (segment_width - text_width) ÷ 2,
                        content_y + (content_height - segment_text_height) ÷ 2, label.color)
            x += segment_width
        end
        outer_width, outer_height = content_width + inset_width, content_height + inset_height
        _push_focus_ring!(elements, w, outer_width, outer_height, p.focus_ring_stroke, corner_radius)
        (width=outer_width, height=outer_height, elements=elements,
         segment_widths=segment_widths)
    end)
    canvas = _reactive_canvas_cell(_origin(position)..., build)
    WidgetToggleGroupToGraphicsCanvasIoMap(p, w, canvas,
                                           Cell(@computation build[].segment_widths))
end

# A segmented control is a positioned leaf that nothing points into: it has one
# value, and that value is a field rather than a place in a document.
map_reference_forward(::WidgetToggleGroupToGraphicsCanvas, iomap, reference) = _map_child_forward(iomap, reference)
map_reference_backward(::WidgetToggleGroupToGraphicsCanvas, iomap, reference) = nothing

# Invisible group (the printer returned a bare empty canvas): inert.
read_intent(::WidgetToggleGroupToGraphicsCanvas, iomap::SimpleIoMap, evt) = nothing

# Which segment holds `x`, counting from the group's own left edge, or nothing
# when the widths do not reach it. The widths are the printer's own, so this
# lands where the reader can see a segment drawn.
function _toggle_group_segment(widths, x::Real)
    left = 0
    for i in eachindex(widths)
        right = left + widths[i]
        left <= x < right && return i
        left = right
    end
    nothing
end

# A left press picks the segment under it. The answer is a value write, the way
# `WidgetSelect` answers a picked option and `WidgetSpinBox` answers a stepper —
# a control states its own value. It is NOT a `ReplaceSelectionOperation`: that is
# what `WidgetList` answers with, because a list's selection is a place in a
# document and a segment is not.
#
# What the write names is the group's `target` when it has one, so a control that
# is *for* something says so in the operation itself. Nothing above has to work
# out which control was pressed — see `resolve_toggle_group_write`.
function read_intent(p::WidgetToggleGroupToGraphicsCanvas,
                     iomap::WidgetToggleGroupToGraphicsCanvasIoMap, evt)
    _outside_widget(iomap, evt) && return nothing
    w = iomap.input
    w.enabled === false && return nothing
    content_x, _ = _content_offset(p, w)
    @gesture_case evt begin
        MouseClick(button, x, y) => begin
            button === :left || return nothing
            # The border and the padding belong to the control: a press on them
            # picks the segment beside it, so the whole control answers.
            widths = iomap.segment_widths
            local_x = clamp(x - content_x, 0, max(0, sum(widths) - 1))
            segment = _toggle_group_segment(widths, local_x)
            # Pressing the segment that is already on is not a change. Answering
            # nothing rather than a write of the same value keeps an enclosing
            # projection from seeing an edit that edits nothing.
            segment === nothing && return nothing
            segment == Int(w.selected) && return nothing
            document, field, value = resolve_toggle_group_write(w, segment)
            ReplaceReferencedValueOperation(document, field, value)
        end
        _ => nothing
    end
end

# ── WidgetSelect ────────────────────────────────────────────────────────────

@projection UntrackedCell struct WidgetSelectToGraphicsCanvas
    measure::TextMeasure
    margin::Inset
    border::Inset
    padding::Inset
    margin_color::StyleColor
    border_color::StyleColor
    padding_color::StyleColor
    content_color::StyleColor
    padding_disabled_color::StyleColor
    content_disabled_color::StyleColor
    label_text::StyleText            # value font + color
    label_disabled_text::StyleText
    chevron_color::StyleColor          # the mark that opens the list
    focus_ring_stroke::StyleStroke     # focus ring when selected
    gap::Int                   # space between value and chevron
    chevron_size::Int
    corner_radius::Int
    popup_gap::Int              # below the box, where the dropdown opens
end

WidgetSelectToGraphicsCanvas(theme; measure,
                             margin = inset_default,
                             border = _themed(Inset, theme, t -> _make_uniform_inset(t.border_width)),
                             padding = _themed(Inset, theme, t -> t.control_padding),
                             margin_color = color_transparent,
                             border_color = _themed(StyleColor, theme, t -> t.input),
                             padding_color = _themed(StyleColor, theme, t -> t.background),
                             content_color = _themed(StyleColor, theme, t -> t.background),
                             padding_disabled_color = _themed(StyleColor, theme, t -> t.muted),
                             content_disabled_color = _themed(StyleColor, theme, t -> t.muted),
                             label_text = _themed(StyleText, theme, _get_body_text),
                             label_disabled_text =
                                 _themed(StyleText, theme, t -> StyleText(t.font, t.muted_foreground)),
                             chevron_color = _themed(StyleColor, theme, t -> t.muted_foreground),
                             focus_ring_stroke = _themed(StyleStroke, theme, t -> StyleStroke(t.ring, t.ring_width)),
                             gap = _themed(Int, theme, t -> t.item_gap),
                             chevron_size = _themed(Int, theme, t -> t.chevron),
                             corner_radius = _themed(Int, theme, t -> t.radius),
                             popup_gap = _themed(Int, theme, t -> t.item_gap)) =
    WidgetSelectToGraphicsCanvas(measure, margin, border, padding, margin_color, border_color, padding_color,
                                 content_color, padding_disabled_color, content_disabled_color, label_text,
                                 label_disabled_text, chevron_color, focus_ring_stroke, gap, chevron_size,
                                 corner_radius, popup_gap)

# Carries the rendered box size, so the reader can open the dropdown popup under
# the box, in its own frame. `control_width` fixes the popup width to the box;
# `control_height` places it just below.
# @iomap so the reader reads `iomap.control_width`/`control_height` transparently
# (the extent is a shared build-derived cell); PAR-STABLE-IOMAP-IDENTITY.
@iomap struct WidgetSelectToGraphicsCanvasIoMap
    projection::Any
    input::Any
    output::Any
    control_width::Any
    control_height::Any
end

function print_document(p::WidgetSelectToGraphicsCanvas, recursion, w::WidgetSelect, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    position = w.position::Point2D
    build = Cell(@computation begin
        text = string(w.value)
        enabled = !(w.enabled === false)
        state = enabled ? nothing : :disabled
        box = _get_box_insets(p, w)
        colors = _get_box_colors(p, w; state)
        inset_width, inset_height = _inset_total(p, w)
        content_x, content_y = _content_offset(p, w)
        label = _get_state_text(p, w, :label; state)
        text_width, text_height = _text_size(p.measure, label.font, text)
        chevron_size = p.chevron_size
        # Fit the value text, a gap and the trailing chevron; the box's own
        # padding is already in `inset_width`.
        content_min = text_width + p.gap + 2chevron_size
        outer_width = _resolve_width(ctx, _sc(Int(w.width)), content_min + inset_width)
        outer_height = _resolve_height(ctx, 0, text_height + inset_height)
        content_width, content_height = outer_width - inset_width, outer_height - inset_height
        radius = p.corner_radius
        chevron_color = _get_state_color(p, w, :chevron; state)
        elements = Any[]
        _push_box_parts!(elements, box, colors, content_width, content_height; radius)
        _push_text!(elements, p.measure, label.font, text, content_x, content_y + (content_height - text_height) ÷ 2, label.color)
        _push_chevron!(elements, content_x + content_width - chevron_size, content_y + content_height ÷ 2, chevron_size,
                       :down, chevron_color)
        _push_focus_ring!(elements, w, outer_width, outer_height, p.focus_ring_stroke, radius)
        (width=outer_width, height=outer_height, elements=elements)
    end)
    canvas = _reactive_canvas_cell(_origin(position)..., build)
    WidgetSelectToGraphicsCanvasIoMap(p, w, canvas,
                                      Cell(@computation build[].width), Cell(@computation build[].height))
end

map_reference_forward(::WidgetSelectToGraphicsCanvas, iomap::WidgetSelectToGraphicsCanvasIoMap, reference) = _map_child_forward(iomap, reference)
map_reference_forward(::WidgetSelectToGraphicsCanvas, iomap::SimpleIoMap, reference) = _map_child_forward(iomap, reference)
map_reference_backward(::WidgetSelectToGraphicsCanvas, iomap, reference) = nothing

# Invisible select (printer returned a bare empty canvas): inert.
read_intent(::WidgetSelectToGraphicsCanvas, iomap::SimpleIoMap, evt) = nothing

# A left click on the box opens the option list as a floating popup window just
# below the box. The reader answers that position in its own frame; each reader
# above moves it into its own frame, and the layer of the window turns it into an
# `OpenWindowOperation`. The deep reader never computes its own screen position.
function read_intent(p::WidgetSelectToGraphicsCanvas, iomap::WidgetSelectToGraphicsCanvasIoMap, evt)
    _outside_widget(iomap, evt) && return nothing
    w = iomap.input
    w.enabled === false && return nothing
    @gesture_case evt begin
        MouseClick(button, x, y) => button === :left ? _open_select_popup(p, w, iomap) : nothing
        _ => nothing
    end
end

# Build the dropdown: a vertical `WidgetMenu` of `WidgetOption`s (one per
# selectable value, each pointing back at this select for the value write), so it
# draws the popover of a menu, wrapped in an `OpenPopupOperation` under the box.
# No options ⇒ nothing to open.
function _open_select_popup(p::WidgetSelectToGraphicsCanvas, w::WidgetSelect,
                            iomap::WidgetSelectToGraphicsCanvasIoMap)
    opts = collect(w.options)
    isempty(opts) && return nothing
    items = Any[WidgetOption(w, opt; width=iomap.control_width) for opt in opts]
    ReplaceViewStateOperation(
        OpenPopupOperation(; id=:widget_popup, x=0, y=iomap.control_height + p.popup_gap,
                           auto_dismiss=true, content=WidgetMenu(items)))
end

# ── WidgetOption ──────────────────────────────────────────────────────────────
# One row of an open select dropdown. A plain label on a flat surface; a left
# click writes the value back to the target select and dismisses the popup.

@projection UntrackedCell struct WidgetOptionToGraphicsCanvas
    measure::TextMeasure
    margin::Inset
    border::Inset
    padding::Inset
    margin_color::StyleColor
    border_color::StyleColor
    padding_color::StyleColor
    content_color::StyleColor
    label_text::StyleText
    layer_hovered_color::StyleColor   # over the surface while the option is hovered
end

WidgetOptionToGraphicsCanvas(theme; measure,
                             margin = inset_default, border = inset_default,
                             padding = _themed(Inset, theme, t -> t.control_padding),
                             margin_color = color_transparent, border_color = color_transparent,
                             padding_color = _themed(StyleColor, theme, t -> t.background),
                             content_color = _themed(StyleColor, theme, t -> t.background),
                             label_text = _themed(StyleText, theme, _get_body_text),
                             layer_hovered_color = _themed(StyleColor, theme, _get_hover_layer)) =
    WidgetOptionToGraphicsCanvas(measure, margin, border, padding, margin_color, border_color,
                                 padding_color, content_color, label_text, layer_hovered_color)

function print_document(p::WidgetOptionToGraphicsCanvas, recursion, w::WidgetOption, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    position = w.position::Point2D
    SimpleIoMap(p, w, _reactive_canvas(_origin(position)..., () -> begin
        label_str = string(w.label)
        box = _get_box_insets(p, w)
        colors = _get_box_colors(p, w)
        inset_width, inset_height = _inset_total(p, w)
        content_x, content_y = _content_offset(p, w)
        label = _get_state_text(p, w, :label)
        text_width, text_height = _text_size(p.measure, label.font, label_str)
        outer_width = _resolve_width(ctx, _sc(Int(w.width)), text_width + inset_width)
        outer_height = _resolve_height(ctx, 0, text_height + inset_height)
        content_width, content_height = outer_width - inset_width, outer_height - inset_height
        elements = Any[]
        _push_box_parts!(elements, box, colors, content_width, content_height)
        _push_text!(elements, p.measure, label.font, label_str, content_x, content_y + (content_height - text_height) ÷ 2, label.color)
        (width=outer_width, height=outer_height, elements=elements)
    end))
end

map_reference_forward(::WidgetOptionToGraphicsCanvas, iomap, reference) = _map_child_forward(iomap, reference)
map_reference_backward(::WidgetOptionToGraphicsCanvas, iomap, reference) = nothing

# Pick: write `value` onto the target select (identity-rooted, so it round-trips
# unchanged to the real select in the default window) and close the popup. The
# WindowManager's CompoundOperation unpacking applies the close; the value write
# bubbles to `evaluate_operation`.
_pick_option(w::WidgetOption) = CompoundOperation(Any[
    ReplaceReferencedValueOperation(w.select, "value", w.value),
    CloseWindowOperation(w.popup_id),
])

function read_intent(::WidgetOptionToGraphicsCanvas, iomap::SimpleIoMap, evt)
    _outside_widget(iomap, evt) && return nothing
    w = iomap.input
    @gesture_case evt begin
        MouseClick(button, x, y) => button === :left ? _pick_option(w) : nothing
        _ => nothing
    end
end

# ── WidgetSpinBox (Stage 6) ───────────────────────────────────────────────────

_spin_clamp(v, lo, hi) = (lo !== nothing && v < lo) ? lo : ((hi !== nothing && v > hi) ? hi : v)

@projection UntrackedCell struct WidgetSpinBoxToGraphicsCanvas
    measure::TextMeasure
    margin::Inset
    border::Inset
    padding::Inset
    margin_color::StyleColor
    border_color::StyleColor
    padding_color::StyleColor
    content_color::StyleColor
    padding_disabled_color::StyleColor
    content_disabled_color::StyleColor
    label_text::StyleText
    label_disabled_text::StyleText
    stepper_color::StyleColor           # the + and − marks
    stepper_disabled_color::StyleColor
    divider_stroke::StyleStroke         # the line beside the steppers
    focus_ring_stroke::StyleStroke
    corner_radius::Int
    glyph_inset::Int                    # the + and − marks, in from the stepper column's edge
    glyph_minimum::Int                  # the + and − marks never shrink under this
end

WidgetSpinBoxToGraphicsCanvas(theme; measure,
                              margin = inset_default,
                              border = _themed(Inset, theme, t -> _make_uniform_inset(t.border_width)),
                              padding = _themed(Inset, theme,
                                  t -> Inset(t.control_padding.top[], t.control_padding.bottom[],
                                            t.control_padding.left[], 0)),
                              margin_color = color_transparent,
                              border_color = _themed(StyleColor, theme, t -> t.input),
                              padding_color = _themed(StyleColor, theme, t -> t.background),
                              content_color = _themed(StyleColor, theme, t -> t.background),
                              padding_disabled_color = _themed(StyleColor, theme, t -> t.muted),
                              content_disabled_color = _themed(StyleColor, theme, t -> t.muted),
                              label_text = _themed(StyleText, theme, _get_body_text),
                              label_disabled_text =
                                  _themed(StyleText, theme, t -> StyleText(t.font, t.muted_foreground)),
                              stepper_color = _themed(StyleColor, theme, t -> t.foreground),
                              stepper_disabled_color = _themed(StyleColor, theme, t -> t.muted_foreground),
                              divider_stroke = _themed(StyleStroke, theme, t -> StyleStroke(t.input, t.border_width)),
                              focus_ring_stroke = _themed(StyleStroke, theme, t -> StyleStroke(t.ring, t.ring_width)),
                              corner_radius = _themed(Int, theme, t -> t.radius),
                              glyph_inset = _themed(Int, theme, t -> t.stepper_glyph_inset),
                              glyph_minimum =
                                  _themed(Int, theme, t -> t.stepper_glyph_minimum)) =
    WidgetSpinBoxToGraphicsCanvas(measure, margin, border, padding, margin_color, border_color, padding_color,
                                  content_color, padding_disabled_color, content_disabled_color, label_text,
                                  label_disabled_text, stepper_color, stepper_disabled_color, divider_stroke,
                                  focus_ring_stroke, corner_radius, glyph_inset, glyph_minimum)

# @iomap so the reader reads control_width/control_height/stepper_w transparently
# (extent shared from the build cell); PAR-STABLE-IOMAP-IDENTITY.
@iomap struct WidgetSpinBoxToGraphicsCanvasIoMap
    projection::Any
    input::Any
    output::Any
    control_width::Any
    control_height::Any
    stepper_w::Any
end

function print_document(p::WidgetSpinBoxToGraphicsCanvas, recursion, w::WidgetSpinBox, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    position = w.position::Point2D
    build = Cell(@computation begin
        enabled = !(w.enabled === false)
        state = enabled ? nothing : :disabled
        text = string(w.value)
        box = _get_box_insets(p, w)
        colors = _get_box_colors(p, w; state)
        inset_width, inset_height = _inset_total(p, w)
        content_x, content_y = _content_offset(p, w)
        label = _get_state_text(p, w, :label; state)
        tw, th = _text_size(p.measure, label.font, text)
        outer_height = _resolve_height(ctx, 0, th + inset_height)
        content_height = outer_height - inset_height
        padding_top, padding_bottom = box.padding[2], box.padding[4]
        # The stepper column spans the padding above and below the text as well
        # as the text itself, and it ends at the right edge of the content. The
        # default padding has no right side, so the column reaches the border.
        # The gap before it is the left padding, the space before the text.
        stepper_w = padding_top + content_height + padding_bottom
        gap = box.padding[1]
        outer_width = _resolve_width(ctx, _sc(Int(w.width)), tw + gap + stepper_w + inset_width)
        content_width = outer_width - inset_width
        radius = p.corner_radius
        step_color = _get_state_color(p, w, :stepper; state)
        divider_stroke = _get_state_stroke(p, w, :divider; state)
        elements = Any[]
        _push_box_parts!(elements, box, colors, content_width, content_height; radius)
        _push_text!(elements, p.measure, label.font, text, content_x, content_y + (content_height - th) ÷ 2, label.color)
        sx = content_x + content_width - stepper_w
        sy = content_y - padding_top
        dw = max(1, Int(divider_stroke.width))
        push!(elements, GraphicsLine(sx, sy, sx, sy + stepper_w; color = divider_stroke.color, width=dw))
        isz = max(p.glyph_minimum, stepper_w ÷ 2 - p.glyph_inset)
        ix = sx + (stepper_w - isz) ÷ 2
        _push_icon!(elements, :plus,  ix, sy + (stepper_w ÷ 2 - isz) ÷ 2, isz, step_color)
        _push_icon!(elements, :minus, ix, sy + stepper_w ÷ 2 + (stepper_w ÷ 2 - isz) ÷ 2, isz, step_color)
        _push_focus_ring!(elements, w, outer_width, outer_height, p.focus_ring_stroke, radius)
        (width=outer_width, height=outer_height, stepper_w=stepper_w, elements=elements)
    end)
    canvas = _reactive_canvas_cell(_origin(position)..., build)
    WidgetSpinBoxToGraphicsCanvasIoMap(p, w, canvas,
        Cell(@computation build[].width), Cell(@computation build[].height), Cell(@computation build[].stepper_w))
end

map_reference_forward(::WidgetSpinBoxToGraphicsCanvas, iomap::WidgetSpinBoxToGraphicsCanvasIoMap, reference) = _map_child_forward(iomap, reference)
map_reference_forward(::WidgetSpinBoxToGraphicsCanvas, iomap, reference) = _map_child_forward(iomap, reference)
map_reference_backward(::WidgetSpinBoxToGraphicsCanvas, iomap, reference) = nothing

read_intent(::WidgetSpinBoxToGraphicsCanvas, iomap::SimpleIoMap, evt) = nothing
function read_intent(p::WidgetSpinBoxToGraphicsCanvas, iomap::WidgetSpinBoxToGraphicsCanvasIoMap, evt)
    _outside_widget(iomap, evt) && return nothing
    w = iomap.input
    (w.enabled === false) && return nothing
    content_x, content_y = _content_offset(p, w)
    box = _get_box_insets(p, w)
    inset_width, _ = _inset_total(p, w)
    content_width = Int(iomap.control_width) - inset_width
    stepper_w = Int(iomap.stepper_w)
    sy = content_y - box.padding[2]
    _step(delta) = ReplaceReferencedValueOperation(w, "value", _spin_clamp(w.value + delta, w.min, w.max))
    @gesture_case evt begin
        MouseClick(button, x, y) =>
            (button === :left && x - content_x >= content_width - stepper_w) ?
                (y - sy < stepper_w ÷ 2 ? _step(w.step) : _step(-w.step)) : nothing
        when(KeyDown(k), _is_plain_key(evt, :up))   => _step(w.step)
        when(KeyDown(k), _is_plain_key(evt, :down)) => _step(-w.step)
        _ => nothing
    end
end

# ── WidgetList (Stage 6) ──────────────────────────────────────────────────────

@projection UntrackedCell struct WidgetListToGraphicsCanvas
    measure::TextMeasure
    margin::Inset
    border::Inset
    padding::Inset
    margin_color::StyleColor
    border_color::StyleColor
    padding_color::StyleColor
    content_color::StyleColor
    label_text::StyleText
    row_selected_color::StyleColor      # the band of the selected row
    layer_hovered_color::StyleColor     # over a hovered row, behind the band
    row_padding::Inset                  # a row's own text padding
    corner_radius::Int
end

WidgetListToGraphicsCanvas(theme; graphics_theme = nothing, measure,
                           margin = inset_default,
                           border = _themed(Inset, theme, t -> _make_uniform_inset(t.border_width)),
                           padding = inset_default,
                           margin_color = color_transparent,
                           border_color = _themed(StyleColor, theme, t -> t.border),
                           padding_color = _themed(StyleColor, theme, t -> t.background),
                           content_color = _themed(StyleColor, theme, t -> t.background),
                           label_text = _themed(StyleText, theme, _get_body_text),
                           row_selected_color = _make_selected_row_color(graphics_theme),
                           layer_hovered_color = _themed(StyleColor, theme, _get_hover_layer),
                           row_padding = _themed(Inset, theme, t -> t.control_padding),
                           corner_radius = _themed(Int, theme, t -> t.radius)) =
    WidgetListToGraphicsCanvas(measure, margin, border, padding, margin_color, border_color, padding_color,
                               content_color, label_text, row_selected_color, layer_hovered_color,
                               row_padding, corner_radius)

# @iomap so the reader reads row_height/control_width transparently (extent shared
# from the build cell); PAR-STABLE-IOMAP-IDENTITY.
@iomap struct WidgetListToGraphicsCanvasIoMap
    projection::Any
    input::Any
    output::Any
    row_height::Any
    control_width::Any
    rows::Any
end

function print_document(p::WidgetListToGraphicsCanvas, recursion, w::WidgetList, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    position = w.position::Point2D
    build = Cell(@computation begin
        row_pad_x = Int(p.row_padding.left[]); row_pad_y = Int(p.row_padding.top[])
        items = collect(w.items)
        n = length(items)
        box = _get_box_insets(p, w)
        colors = _get_box_colors(p, w)
        inset_width, inset_height = _inset_total(p, w)
        content_x, content_y = _content_offset(p, w)
        label = _get_state_text(p, w, :label)
        _, th = _text_size(p.measure, label.font, "M")
        row_height = th + 2row_pad_y
        intrinsic = 0
        for it in items
            tw, _ = _text_size(p.measure, label.font, string(it))
            intrinsic = max(intrinsic, tw + 2row_pad_x)
        end
        outer_width = _resolve_width(ctx, _sc(Int(w.width)), intrinsic + inset_width)
        outer_height = _resolve_height(ctx, 0, max(row_height, n * row_height) + inset_height)
        content_width, content_height = outer_width - inset_width, outer_height - inset_height
        radius = p.corner_radius
        sel = get_widget_list_selected(w)
        enabled = !(w.enabled === false)
        lit_row = enabled ? _widget_element_selected(get_mouse_target(w), "items") : 0
        row_selected_color = _get_state_color(p, w, :row; state = :selected)
        elements = Any[]
        _push_box_parts!(elements, box, colors, content_width, content_height; radius)
        # Each row is a canvas of its own, which holds the row's tint, its band
        # and its text, so a row is a node that a reference reaches.
        rows = Any[]
        for (i, it) in enumerate(items)
            row = Any[]
            # The light of the row under the pointer sits UNDER the selection band,
            # so the pointer on the selected row does not repaint it — the same
            # tint that the tree and the table use.
            if i == lit_row && i != sel
                _push_state_layer!(row, p.layer_hovered_color, 0, 0, content_width, row_height)
            end
            if i == sel
                _push_panel!(row, 0, 0, content_width, row_height; fill = row_selected_color)
            end
            _push_text!(row, p.measure, label.font, string(it), row_pad_x, row_pad_y, label.color)
            push!(rows, GraphicsCanvas(row; x = content_x, y = content_y + (i - 1) * row_height,
                                       w = content_width, h = row_height))
        end
        append!(elements, rows)
        (width=outer_width, height=outer_height, row_height=row_height, elements=elements, rows=rows)
    end)
    canvas = _reactive_canvas_cell(_origin(position)..., build)
    WidgetListToGraphicsCanvasIoMap(p, w, canvas,
        Cell(@computation build[].row_height), Cell(@computation build[].width),
        Cell(@computation build[].rows))
end

# `items[k]` is the canvas of row `k`, found by identity among the list's
# elements, after the parts of the box.
function map_reference_forward(::WidgetListToGraphicsCanvas, iomap::WidgetListToGraphicsCanvasIoMap, reference)
    reference isa Reference || return nothing
    reference = strip_reference_types(reference)
    reference isa ConcreteReference || return _map_self_forward(reference)
    head = reference.head
    (head isa FieldReferenceStep && head.name == "items") || return nothing
    rest = reference.tail
    (rest isa ConcreteReference && rest.head isa RangeReferenceStep && rest.tail isa EmptyReference) ||
        return nothing
    rows = unwrap_cell(iomap.rows)
    k = rest.head.start + 1
    1 <= k <= length(rows) || return nothing
    find_node_reference(iomap.output, rows[k]; depth = 1)
end
map_reference_forward(::WidgetListToGraphicsCanvas, iomap, reference) = _map_child_forward(iomap, reference)
# A point on a row maps to that item, the reference that a click there selects.
function map_reference_backward(p::WidgetListToGraphicsCanvas, iomap, reference)
    point = find_reference_point(reference)
    (point === nothing || !(iomap isa WidgetListToGraphicsCanvasIoMap)) && return nothing
    _is_point_on_canvas(iomap.output, point) || return nothing
    row = _find_list_row_at(p, iomap, point.y)
    row == 0 ? nothing : make_widget_list_selection(row)
end

# The row of the list at `y` of its canvas, from the first row down; `0` when no
# row is there.
function _find_list_row_at(p::WidgetListToGraphicsCanvas, iomap::WidgetListToGraphicsCanvasIoMap,
                           y::Int)
    w = iomap.input
    n = length(collect(w.items))
    _, content_y = _content_offset(p, w)
    r = (y - content_y) ÷ iomap.row_height + 1
    (1 <= r <= n) ? r : 0
end

read_intent(::WidgetListToGraphicsCanvas, iomap::SimpleIoMap, evt) = nothing
function read_intent(p::WidgetListToGraphicsCanvas, iomap::WidgetListToGraphicsCanvasIoMap, evt)
    _outside_widget(iomap, evt) && return nothing
    w = iomap.input
    (w.enabled === false) && return nothing
    n = length(collect(w.items))
    n == 0 && return nothing
    sel = get_widget_list_selected(w)
    # Selection is a selection: like every other widget, the reader reports it as
    # a ReplaceSelectionOperation carrying a reference (`items[i-1:i]`), not as a
    # write to a private index field. That is what lets an enclosing projection
    # map the reference into its own domain (and map it back when printing).
    pick(r) = ReplaceSelectionOperation(make_widget_list_selection(r))
    row_at(yy) = _find_list_row_at(p, iomap, yy)
    click_row(yy) = (r = row_at(yy); r == 0 ? nothing : pick(r))
    @gesture_case evt begin
        MouseClick(button, x, y) => button === :left ? click_row(y) : nothing
        when(KeyDown(k), _is_plain_key(evt, :down)) => pick(sel == 0 ? 1 : min(sel + 1, n))
        when(KeyDown(k), _is_plain_key(evt, :up))   => pick(sel <= 1 ? 1 : sel - 1)
        _ => nothing
    end
end

# ── WidgetTextarea ──────────────────────────────────────────────────────────

@projection UntrackedCell struct WidgetTextareaToGraphicsCanvas
    measure::TextMeasure
    margin::Inset
    border::Inset
    padding::Inset
    margin_color::StyleColor
    border_color::StyleColor
    padding_color::StyleColor
    content_color::StyleColor
    padding_disabled_color::StyleColor
    content_disabled_color::StyleColor
    label_text::StyleText            # content font + color
    label_disabled_text::StyleText
    focus_ring_stroke::StyleStroke      # focus ring when selected
    corner_radius::Int
end

WidgetTextareaToGraphicsCanvas(theme; measure,
                               margin = inset_default,
                               border = _themed(Inset, theme, t -> _make_uniform_inset(t.border_width)),
                               padding = _themed(Inset, theme, t -> t.control_padding),
                               margin_color = color_transparent,
                               border_color = _themed(StyleColor, theme, t -> t.input),
                               padding_color = _themed(StyleColor, theme, t -> t.background),
                               content_color = _themed(StyleColor, theme, t -> t.background),
                               padding_disabled_color = _themed(StyleColor, theme, t -> t.muted),
                               content_disabled_color = _themed(StyleColor, theme, t -> t.muted),
                               label_text = _themed(StyleText, theme, _get_body_text),
                               label_disabled_text =
                                   _themed(StyleText, theme, t -> StyleText(t.font, t.muted_foreground)),
                               focus_ring_stroke = _themed(StyleStroke, theme, t -> StyleStroke(t.ring, t.ring_width)),
                               corner_radius = _themed(Int, theme, t -> t.radius)) =
    WidgetTextareaToGraphicsCanvas(measure, margin, border, padding, margin_color, border_color,
                                   padding_color, content_color, padding_disabled_color,
                                   content_disabled_color, label_text, label_disabled_text,
                                   focus_ring_stroke, corner_radius)

# IoMap for a WidgetTextarea. The text domain draws and edits the content, as it
# does for a `WidgetText`: a Document content, typically a `TextBlock`, is
# recursed through the chain, and a plain value is drawn through a text view of
# its string. PAR-STABLE-IOMAP-IDENTITY.
@iomap struct WidgetTextareaToGraphicsCanvasIoMap
    projection::Any
    input::Any
    output::Any
    content_iomap::Any
end

function print_document(p::WidgetTextareaToGraphicsCanvas, recursion, w::WidgetTextarea, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    position = w.position::Point2D
    state = w.enabled === false ? :disabled : nothing
    # A Document content is recursed through the outer projection chain, which
    # gives it to TextToGraphics; a plain value is drawn through a text view of
    # its string, in the muted color while the area is disabled. The box grows
    # with the text.
    content_ctx = _get_inner_content_context(p, w, ctx)
    content_iomap = if w.content isa Document
        make_reconciled_child_iomap_cell(() -> w.content, c -> print_child(recursion, c, content_ctx))
    else
        _print_plain_text_view(p, recursion, w, _get_state_text(p, w, :label; state), content_ctx)
    end
    build = Cell(@computation begin
        enabled = !(w.enabled === false)
        box = _get_box_insets(p, w)
        colors = _get_box_colors(p, w; state)
        inset_width, inset_height = _inset_total(p, w)
        content_x, content_y = _content_offset(p, w)
        label = _get_state_text(p, w, :label; state)
        inner = content_iomap[].output::GraphicsCanvas
        _, line_height = _text_size(p.measure, label.font, "M")
        text_height = max(Int(inner.h[]), line_height)
        authored_height = Int(w.rows) > 0 ?
            max(Int(w.rows) * line_height, text_height) + inset_height : 0
        outer_height = _resolve_height(ctx, authored_height, text_height + inset_height)
        outer_width = _resolve_width(ctx, _sc(Int(w.width)), Int(inner.w[]) + inset_width)
        radius = p.corner_radius
        elements = Any[]
        _push_box_parts!(elements, box, colors, outer_width - inset_width, outer_height - inset_height;
                         radius)
        # A press anywhere in the box of an area that takes edits puts the caret,
        # and a press on a disabled area does nothing, also over its text.
        enabled && push!(elements, GraphicsPointerShape(0, 0, outer_width, outer_height, :ibeam))
        push!(elements, _make_canvas(content_x, content_y, Any[inner]))
        enabled || push!(elements, GraphicsPointerShape(0, 0, outer_width, outer_height, :arrow))
        _push_focus_ring!(elements, w, outer_width, outer_height, p.focus_ring_stroke, radius)
        (width=outer_width, height=outer_height, elements=elements)
    end)
    WidgetTextareaToGraphicsCanvasIoMap(p, w, _reactive_canvas_cell(_origin(position)..., build),
                                        content_iomap)
end

map_reference_forward(::WidgetTextareaToGraphicsCanvas, iomap, reference) = _map_child_forward(iomap, reference)
map_reference_backward(::WidgetTextareaToGraphicsCanvas, iomap, reference) = nothing

# Re-root a reference of the Text domain under `.content`, as `WidgetText` does.
# A reference of the text view of a plain value is a range of `content` itself,
# and a point is on the content.
function map_reference_backward(::WidgetTextareaToGraphicsCanvas, iomap::WidgetTextareaToGraphicsCanvasIoMap, reference)
    reference === nothing && return nothing
    point = find_reference_point(reference)
    point === nothing || return _map_text_point(point)
    w = iomap.input
    w.content isa Document || return _map_plain_text_reference(w, reference)
    ConcreteReference(FieldReferenceStep("content"), reference)
end

# Invisible text area (the printer returned a bare empty canvas): inert.
read_intent(::WidgetTextareaToGraphicsCanvas, iomap::SimpleIoMap, evt) = nothing

# The Text domain edits the content, as it edits the content of a `WidgetText`.
# Return has no meaning there, so here it types a line break.
function read_intent(p::WidgetTextareaToGraphicsCanvas, iomap::WidgetTextareaToGraphicsCanvasIoMap, evt)
    _outside_widget(iomap, evt) && return nothing
    iomap.input.enabled === false && return nothing
    typed = _is_plain_key(evt, :return) ?
            KeyPress('\n', "\n", ModifierKeys(); time = evt.time) : evt
    _read_text_content_intent(p, iomap, typed, _content_offset(p, iomap.input)...)
end

# ── WidgetAccordion ─────────────────────────────────────────────────────────

@projection UntrackedCell struct WidgetAccordionToGraphicsCanvas
    measure::TextMeasure
    margin::Inset
    border::Inset
    padding::Inset
    margin_color::StyleColor
    border_color::StyleColor
    padding_color::StyleColor
    content_color::StyleColor
    title_text::StyleText        # bold title
    body_text::StyleText          # muted body
    divider_stroke::StyleStroke   # hairline between items
    chevron_color::StyleColor     # the mark that opens a section
    item_padding::Inset           # a row's own horizontal + vertical padding
    gap::Int                      # space before the trailing chevron
    body_gap::Int                 # gap above the expanded body
    chevron_size::Int
end

WidgetAccordionToGraphicsCanvas(theme; measure,
                                margin = inset_default, border = inset_default, padding = inset_default,
                                margin_color = color_transparent, border_color = color_transparent,
                                padding_color = color_transparent, content_color = color_transparent,
                                title_text = _themed(StyleText, theme, _get_title_text),
                                body_text = _themed(StyleText, theme, _get_caption_text),
                                divider_stroke = _themed(StyleStroke, theme, t -> StyleStroke(t.border, t.border_width)),
                                chevron_color = _themed(StyleColor, theme, t -> t.muted_foreground),
                                item_padding = _themed(Inset, theme, t -> t.control_padding),
                                gap = _themed(Int, theme, t -> t.item_gap),
                                body_gap = _themed(Int, theme, t -> t.accordion_body_gap),
                                chevron_size = _themed(Int, theme, t -> t.chevron)) =
    WidgetAccordionToGraphicsCanvas(measure, margin, border, padding, margin_color, border_color,
                                    padding_color, content_color, title_text, body_text, divider_stroke,
                                    chevron_color, item_padding, gap, body_gap, chevron_size)

# The header row of each item, so a press is answered by the header it landed in,
# and the place of the open body when it is a document, so a press on the body
# goes to it. The printer derives both in the build that draws the rows, and the
# reader reads them from here. PAR-STABLE-IOMAP-IDENTITY.
@iomap struct WidgetAccordionToGraphicsCanvasIoMap
    projection::Any
    input::Any
    output::Any
    header_bounds::Any
    body_entry::Any
    headers::Any
end

# What a route reaches through this container: see `_collect_child_iomaps`.
ProjectionModule.get_child_iomaps(iomap::WidgetAccordionToGraphicsCanvasIoMap) =
    _collect_child_iomaps(iomap.body_entry)

# The body of the open item, or `nothing` when no item is open.
function _get_open_accordion_body(w::WidgetAccordion)
    expanded = Int(w.expanded)
    items = w.items
    (1 <= expanded <= length(items)) ? items[expanded].body : nothing
end

# What the accordion offers a title or a body: the width inside its box and the
# padding of a row when it has a width, and no height, because the accordion is
# as tall as its rows.
function _get_accordion_item_context(p::WidgetAccordionToGraphicsCanvas, w::WidgetAccordion, ctx)
    ctx === nothing && return ctx
    inset_width, _ = _inset_total(p, w)
    padding = inset_width + 2 * Int(p.item_padding.left[])
    authored = _sc(Int(w.width))
    inner_ctx = authored > 0 ? with_exact_size(ctx; width = Cell(Int32(max(0, authored - padding)))) :
                with_inner_size(ctx; width = padding)
    with_free_axis(inner_ctx, :y)
end

function print_document(p::WidgetAccordionToGraphicsCanvas, recursion, w::WidgetAccordion, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    position = w.position::Point2D
    # A title or a body that is a document is drawn through the recursion, as a
    # card draws its content. Each title is printed once, and the body only
    # while its item is open.
    item_ctx = _get_accordion_item_context(p, w, ctx)
    title_iomaps = make_reconciled_child_iomaps_cell(
        () -> Any[item.title for item in w.items],
        (i, title) -> title isa Document ? print_child(recursion, title, item_ctx) : nothing)
    body_iomap = make_reconciled_child_iomap_cell(() -> _get_open_accordion_body(w),
        body -> body isa Document ? print_child(recursion, body, item_ctx) : nothing)
    build = Cell(@computation begin
        expanded = Int(w.expanded)
        box = _get_box_insets(p, w)
        colors = _get_box_colors(p, w)
        inset_width, inset_height = _inset_total(p, w)
        content_x, content_y = _content_offset(p, w)
        item_padding_x = Int(p.item_padding.left[])
        item_padding_y = Int(p.item_padding.top[])
        chevron_size = p.chevron_size
        title_style = _get_state_text(p, w, :title)
        body_style  = _get_state_text(p, w, :body)
        chevron_color = _get_state_color(p, w, :chevron)
        divider_stroke = _get_state_stroke(p, w, :divider)
        titles = title_iomaps[]
        body_document = body_iomap[]
        # The size of a title or a body: a document draws its own canvas, and a
        # plain value is drawn as its string.
        size_of(iomap, value, font) = iomap === nothing ?
            _text_size(p.measure, font, string(value)) :
            (Int(iomap.output.w[]), Int(iomap.output.h[]))
        # Size to content: widest title (leaving room for the trailing chevron) and
        # the widest visible (expanded) body. The authored width is the minimum.
        title_min = 0; body_min = 0
        for (i, item) in enumerate(w.items)
            title_min = max(title_min, size_of(titles[i], item.title, title_style.font)[1])
            if i == expanded && item.body !== nothing
                body_min = max(body_min, size_of(body_document, item.body, body_style.font)[1])
            end
        end
        item_content_min = max(2item_padding_x + title_min + p.gap + 2chevron_size,
                               2item_padding_x + body_min)
        outer_width = _resolve_width(ctx, _sc(Int(w.width)), item_content_min + inset_width)
        content_width = outer_width - inset_width
        # The rows are laid out first, because the box behind them is painted at
        # the resolved content height, and `_push_box_parts!` must see that final
        # size before the row elements that draw over it.
        row_elements = Any[]
        header_bounds = Tuple{Int,Int}[]
        # Each header is a canvas of its own, which holds the title and the
        # chevron of its item, so a header is a node that a reference reaches.
        headers = Any[]
        body_entry = nothing
        y = 0
        divider_width = max(1, Int(divider_stroke.width))
        for (i, item) in enumerate(w.items)
            _, title_height = size_of(titles[i], item.title, title_style.font)
            row_height = title_height + 2item_padding_y
            header_elements = Any[]
            if titles[i] === nothing
                _push_text!(header_elements, p.measure, title_style.font, string(item.title),
                           item_padding_x, item_padding_y, title_style.color)
            else
                push!(header_elements, _make_canvas(item_padding_x, item_padding_y, Any[titles[i].output]))
            end
            _push_chevron!(header_elements, content_width - item_padding_x - chevron_size,
                           row_height ÷ 2, chevron_size, i == expanded ? :down : :right, chevron_color)
            header = GraphicsCanvas(header_elements; x = content_x, y = content_y + y,
                                    w = content_width, h = row_height)
            push!(row_elements, header)
            push!(headers, header)
            push!(header_bounds, (content_y + y, content_y + y + row_height))
            y += row_height
            if i == expanded && body_document !== nothing
                body_x = content_x + item_padding_x
                body_y = content_y + y + p.body_gap
                push!(row_elements, _make_canvas(body_x, body_y, Any[body_document.output]))
                body_entry = (body_x, body_y, i, body_document)
                y += p.body_gap + Int(body_document.output.h[]) + item_padding_y
            elseif i == expanded && item.body !== nothing && !isempty(string(item.body))
                body = string(item.body)
                _, body_height = _text_size(p.measure, body_style.font, body)
                _push_text!(row_elements, p.measure, body_style.font, body, content_x + item_padding_x,
                           content_y + y + p.body_gap, body_style.color)
                y += body_height + item_padding_y
            end
            push!(row_elements, GraphicsLine(content_x, content_y + y, content_x + content_width,
                                             content_y + y; color = divider_stroke.color, width=divider_width))
        end
        outer_height = _resolve_height(ctx, 0, y + inset_height)
        elements = Any[]
        _push_box_parts!(elements, box, colors, content_width, outer_height - inset_height)
        append!(elements, row_elements)
        (width=outer_width, height=outer_height, elements=elements,
         header_bounds=header_bounds, body_entry=body_entry, headers=headers)
    end)
    WidgetAccordionToGraphicsCanvasIoMap(p, w, _reactive_canvas_cell(_origin(position)..., build),
                                         Cell(@computation build[].header_bounds),
                                         Cell(@computation build[].body_entry),
                                         Cell(@computation build[].headers))
end

# `items[i]` is the canvas of the header of item `i`, found by identity among the
# accordion's elements, after the parts of the box.
function map_reference_forward(::WidgetAccordionToGraphicsCanvas, iomap::WidgetAccordionToGraphicsCanvasIoMap,
                               reference)
    reference isa Reference || return nothing
    reference = strip_reference_types(reference)
    reference isa ConcreteReference || return _map_self_forward(reference)
    head = reference.head
    (head isa FieldReferenceStep && head.name == "items") || return nothing
    rest = reference.tail
    (rest isa ConcreteReference && rest.head isa RangeReferenceStep && rest.tail isa EmptyReference) ||
        return nothing
    headers = unwrap_cell(iomap.headers)
    i = rest.head.start + 1
    1 <= i <= length(headers) || return nothing
    find_node_reference(iomap.output, headers[i]; depth = 1)
end

map_reference_forward(::WidgetAccordionToGraphicsCanvas, iomap, reference) = _map_child_forward(iomap, reference)
# A point on a header maps to its item, and a point on the open body on into the
# body, `items[i].body`, with the point in the body's frame.
function map_reference_backward(::WidgetAccordionToGraphicsCanvas, iomap, reference)
    point = find_reference_point(reference)
    (point === nothing || !(iomap isa WidgetAccordionToGraphicsCanvasIoMap)) && return nothing
    _is_point_on_canvas(iomap.output, point) || return nothing
    item = _find_row_index(iomap.header_bounds, point.y)
    item === nothing ||
        return annotate_reference_types(iomap.input, ConcreteReference(FieldReferenceStep("items"),
                                        ConcreteReference(RangeReferenceStep(item - 1, item))))
    entry = iomap.body_entry
    entry === nothing && return nothing
    (_, _, index, body_iomap) = entry
    canvas = body_iomap.output
    canvas isa GraphicsCanvas || return nothing
    dx, dy = _get_accordion_body_offset(iomap, entry)
    lx, ly = point.x - dx, point.y - dy
    hit_element_at(canvas, lx, ly) === nothing && return nothing
    answer = map_reference_backward(get_iomap_projection(body_iomap), body_iomap,
                                    PointReferenceStep(lx, ly))
    annotate_reference_types(iomap.input,
        ConcreteReference(FieldReferenceStep("items"),
            ConcreteReference(RangeReferenceStep(index - 1, index),
                ConcreteReference(FieldReferenceStep("body"),
                                  answer === nothing ? EmptyReference() : answer))))
end

# How far the frame of the open body lies from the frame of the accordion.
function _get_accordion_body_offset(iomap::WidgetAccordionToGraphicsCanvasIoMap, entry)
    (x, y, _, body_iomap) = entry
    canvas = body_iomap.output
    (x + Int(canvas.x), y + Int(canvas.y))
end

# Invisible accordion (the printer returned a bare empty canvas): inert.
read_intent(::WidgetAccordionToGraphicsCanvas, iomap::SimpleIoMap, evt) = nothing

# A left press on the header of an item opens that item, or closes it when it is
# the open one. `expanded` holds one index, so the accordion shows one item at a
# time, and opening one item closes the item that was open. A pointer event on an
# open body that is a document goes to that body, and so does a key while the
# selection of the accordion is inside the body. The answer of the body is
# re-rooted under `items[i].body`. For a dwell and a right click the accordion then
# reads its own stretch (`read_container_gesture`).
function read_intent(::WidgetAccordionToGraphicsCanvas,
                     iomap::WidgetAccordionToGraphicsCanvasIoMap, evt)
    evt isa MouseMove && return _read_accordion_move(iomap, evt)
    _outside_widget(iomap, evt) && return nothing
    w = iomap.input
    # A click on a header opens or closes a section of the view. It is view state,
    # so a history does not record it.
    if evt isa MouseClick && evt.button === :left
        item = _find_row_index(iomap.header_bounds, evt.y)
        item === nothing ||
            return _write_view_state(w, "expanded", item == Int(w.expanded) ? 0 : item)
    end
    # A dwell or a right click on a header is read by its item and the documents
    # around it: the accordion draws the header itself, so the backward map of the
    # point names the item (`read_child_part_gesture`).
    is_outward_gesture(evt) && _find_row_index(iomap.header_bounds, evt.y) !== nothing &&
        return read_child_part_gesture(iomap, evt)
    found = _read_accordion_body(iomap, evt)
    found === nothing && return read_container_gesture(nothing, evt, w)
    steps = _get_accordion_body_steps(found[2])
    read_container_gesture(reroot_operation(found[1], steps), evt, w; steps)
end

# The answer of the open body to `evt`, in the frame of the accordion, and the index
# of its item; `nothing` when the event reaches no body.
function _read_accordion_body(iomap::WidgetAccordionToGraphicsCanvasIoMap, evt)
    entry = iomap.body_entry
    entry === nothing && return nothing
    (_, _, index, body_iomap) = entry
    answer = if _positioned_event(evt)
        canvas = body_iomap.output
        canvas isa GraphicsCanvas || return nothing
        dx, dy = _get_accordion_body_offset(iomap, entry)
        local_event = _translate_pointer_event(evt, dx, dy)
        hit_element_at(canvas, local_event.x, local_event.y) !== nothing || return nothing
        shift_operation_position(read_child_event(body_iomap, local_event), dx, dy)
    elseif _is_accordion_body_selected(iomap.input, index)
        read_intent(body_iomap.projection, body_iomap, evt)
    else
        nothing
    end
    (answer, index)
end

_get_accordion_body_steps(index::Int) =
    (FieldReferenceStep("items"), RangeReferenceStep(index - 1, index), FieldReferenceStep("body"))

# A move of the pointer. The open body gets it first when the accordion's own
# mouse target is inside the body and the point is not. Then the part at the point
# answers: a header is the item `items[i]`, and the open body reads the move itself.
function _read_accordion_move(iomap::WidgetAccordionToGraphicsCanvasIoMap, evt::MouseMove)
    w = iomap.input
    entry = iomap.body_entry
    new_answer = nothing
    on_body = false
    if !_outside_widget(iomap, evt)
        item = _find_row_index(iomap.header_bounds, evt.y)
        if item !== nothing
            new_answer = ReplaceMouseTargetOperation(annotate_reference_types(w,
                ConcreteReference(FieldReferenceStep("items"),
                                  ConcreteReference(RangeReferenceStep(item - 1, item)))))
        elseif entry !== nothing
            (_, _, index, body_iomap) = entry
            canvas = body_iomap.output
            dx, dy = canvas isa GraphicsCanvas ? _get_accordion_body_offset(iomap, entry) : (0, 0)
            local_event = _translate_pointer_event(evt, dx, dy)
            if canvas isa GraphicsCanvas &&
               hit_element_at(canvas, local_event.x, local_event.y) !== nothing
                on_body = true
                new_answer = reroot_operation(
                    shift_operation_position(read_child_move(body_iomap, local_event), dx, dy),
                    _get_accordion_body_steps(index))
            end
        end
    end
    (entry === nothing || on_body) && return new_answer
    (_, _, index, body_iomap) = entry
    _is_path_in_accordion_body(get_mouse_target(w), index) || return new_answer
    canvas = body_iomap.output
    dx, dy = canvas isa GraphicsCanvas ? _get_accordion_body_offset(iomap, entry) : (0, 0)
    old_answer = read_child_leave(body_iomap, evt, dx, dy)
    join_move_answers(reroot_operation(old_answer, _get_accordion_body_steps(index)), new_answer)
end

# Whether the selection of the accordion is inside the body of item `index`.
_is_accordion_body_selected(w::WidgetAccordion, index::Int) =
    _is_path_in_accordion_body(w.selection, index)

# Whether `path`, a path in an accordion, is inside the body of item `index`.
function _is_path_in_accordion_body(path, index::Int)
    path isa Reference || return false
    steps = get_reference_steps(strip_reference_types(path))
    length(steps) >= 3 &&
        steps[1] isa FieldReferenceStep && steps[1].name == "items" &&
        steps[2] isa RangeReferenceStep && steps[2].start == index - 1 &&
        steps[3] isa FieldReferenceStep && steps[3].name == "body"
end

# A pointer event moved by `(dx, dy)` into the frame of a child.
_translate_pointer_event(evt::MouseClick, dx, dy) =
    MouseClick(evt.button, evt.x - dx, evt.y - dy, evt.count, evt.modifiers;
               time = evt.time)
_translate_pointer_event(evt::MouseDown, dx, dy) = MouseDown(evt.button, evt.x - dx, evt.y - dy, evt.modifiers;
                                                             time = evt.time)
_translate_pointer_event(evt::MouseUp, dx, dy) = MouseUp(evt.button, evt.x - dx, evt.y - dy, evt.modifiers;
                                                         time = evt.time)
_translate_pointer_event(evt::MouseMove, dx, dy) = MouseMove(evt.x - dx, evt.y - dy, evt.buttons, evt.modifiers;
                                                             time = evt.time)
_translate_pointer_event(evt::MouseScroll, dx, dy) = MouseScroll(evt.dx, evt.dy, evt.x - dx, evt.y - dy;
                                                                 time = evt.time)
_translate_pointer_event(evt::MouseDwell, dx, dy) = shift_event_position(evt, -dx, -dy)

# ── WidgetTable ─────────────────────────────────────────────────────────────
#
# The single table abstraction. A table scrolls its own parts: the header row,
# the header column and the cells are each a `GridLayout` in a
# `WidgetScrollPane` of their own, and the corner between the two headers holds
# still. The table owns the one offset of the parts, `scroll_position`: the pane
# of the cells shares it, the pane of the header row reads its `x` and the pane
# of the header column its `y`. A table whose rows are a list is printed by
# `WidgetTableParts.jl`; this section prints a table whose rows are a vector.
#
# **The geometry.** The table keeps the geometry of its whole grid as if it were
# not scrolled, `WTGeometry`: the edge of every column and of every row, the
# header column and the header row first. Its readers work in these
# coordinates, and a point over a part that scrolls moves by the offset that
# the pane of the part draws with.
#
# **The graphics.** A layout positions and draws nothing, so the table draws the
# header bands, the bands of the hover and of the selection, and the rules,
# once, in the coordinates of the geometry. Every region shows them behind its
# pane, moved by its own offset and clipped to its box, so the band of a row
# runs across the header column and the cells, and the band of a column across
# the header row and the cells.
#
# **The widths and the heights.** The cells decide the width of every column
# and the height of every row. A column is at least as wide as its header, and
# a `Content` row at least as tall as its header, unless the header is offered
# the extent and wraps in it. The header row takes the widths as `Fixed`, and
# the header column the heights. A table with no rows has no cells to decide
# the widths, so its header row takes the policies of the columns.
#
# **Padding.** Every gap of a grid is "padding, rule, padding", and the pane of
# each part has the padding and the rule of its edges as its own padding. So
# the rules lie in the gaps and the paddings, and every cell is padded alike. By
# default every part of the box of the table is transparent and every inset is
# zero, so the box costs nothing.
#
# **Selection.** Field names `rows` / `columns` / `cells` / `column_headers` /
# `row_headers` are the public reference vocabulary: `rows[r]` a row,
# `columns[c]` a column, `cells[r][c]` a cell (`cells[c][r]` in a column-major
# table), and a header a part of its own. A whole-element selection
# is a path terminating at the element (`∅`); the table, the one place with the
# geometry, turns a 1-D handle into a 2-D band, and a header into its cell. An in-cell cursor (`cells[r][c].…`) descends into the
# cell's own sub-pipeline and is drawn there.

@projection UntrackedCell struct WidgetTableToGraphicsCanvas
    margin::Inset
    border::Inset
    padding::Inset
    margin_color::StyleColor
    border_color::StyleColor
    padding_color::StyleColor
    content_color::StyleColor
    divider_stroke::StyleStroke         # the outer frame and the grid lines
    header_row_color::StyleColor        # header strip background
    row_selected_color::StyleColor      # the band of the selected row, column or cell
    layer_hovered_color::StyleColor     # over a hovered row, column or cell, behind the band
    edge_hovered_stroke::StyleStroke    # over the right edge of a header that the pointer is on
    cell_mark_stroke::StyleStroke       # the frame of an open cell whose last commit failed
    cell_padding::Inset                 # inside a cell: top and bottom, left and right
    row_radius::Int                     # corner radius of the hover and the selection band
end

WidgetTableToGraphicsCanvas(theme; graphics_theme = nothing,
                            margin = inset_default, border = inset_default, padding = inset_default,
                            margin_color = color_transparent, border_color = color_transparent,
                            padding_color = color_transparent, content_color = color_transparent,
                            divider_stroke = _themed(StyleStroke, theme, t -> StyleStroke(t.border, t.border_width)),
                            header_row_color = _themed(StyleColor, theme, t -> t.muted),
                            row_selected_color = _make_selected_row_color(graphics_theme),
                            layer_hovered_color = _themed(StyleColor, theme, _get_hover_layer),
                            edge_hovered_stroke = _themed(StyleStroke, theme, t -> StyleStroke(t.ring, 3)),
                            cell_mark_stroke = _themed(StyleStroke, theme, t -> StyleStroke(t.destructive, 2)),
                            cell_padding = _themed(Inset, theme, t -> t.control_padding),
                            row_radius = _themed(Int, theme, t -> t.radius_small)) =
    WidgetTableToGraphicsCanvas(margin, border, padding, margin_color, border_color, padding_color,
                                content_color, divider_stroke, header_row_color, row_selected_color,
                                layer_hovered_color, edge_hovered_stroke, cell_mark_stroke, cell_padding,
                                row_radius)

# The geometry of a table as if it were not scrolled, in the coordinates of its
# content. `col_x` / `row_y` are the cumulative left/top edges, length
# grid_cols+1 / grid_rows+1, so that `col_x[gc+1]` is the right edge of grid
# column gc. Grid column 1 is the header column and grid row 1 the header row,
# when the table has them.
struct WTGeometry
    nrows::Int
    ncols::Int
    row_offset::Int          # 1 when a column-header strip occupies grid row 1
    col_offset::Int          # 1 when a row-header strip occupies grid column 1
    grid_rows::Int
    grid_cols::Int
    has_row_headers::Bool
    has_col_headers::Bool
    col_x::Vector{Int}
    row_y::Vector{Int}
    total_w::Int
    total_h::Int
    bw::Int                  # border / rule width
    pad_x::Int               # inner padding, left and right of a cell
    pad_y::Int               # inner padding, above and below a cell
    grid_off_x::Int          # from the rule left of a column to its cells (= bw + pad_x)
    grid_off_y::Int          # from the rule above a row to its cells (= bw + pad_y)
end

# IoMap: the panes of the parts, and the geometry that the readers work in (the
# table analog of TextToGraphics's char_to_coord).
@iomap struct WidgetTableToGraphicsCanvasIoMap
    projection::Any
    input::Any
    output::Any
    parts::Cell              # the panes of the parts and the regions that hold them
    geometry::Cell           # WTGeometry
end

_wt_has_col_headers(w::WidgetTable) = length(w.column_headers) > 0
_wt_has_row_headers(w::WidgetTable) = length(w.row_headers) > 0
_wt_empty_cell() = WidgetLabel("")

# The data of body column `c` of `w`, counted from the head column when the
# columns are a list, or `nothing` where the table holds none, so the defaults of
# the table hold.
function _get_table_column_data(w::WidgetTable, c::Int)
    columns = w.columns
    columns isa AbstractVector && return 1 <= c <= length(columns) ? columns[c] : nothing
    columns isa ListNode || return nothing
    node = _find_list_node(columns, c)
    node === nothing ? nothing : node.value
end

# The data of body row `r` of `w`, or `nothing` where the table holds none.
function _get_table_row_data(w::WidgetTable, r::Int)
    rows = w.rows
    (rows isa AbstractVector && 1 <= r <= length(rows)) ? rows[r] : nothing
end

# The cell policy of body column `c`: the column's own when it names one, else
# the table's.
function _wt_column_cell_policy(w::WidgetTable, c::Int)
    column = _get_table_column_data(w, c)
    policy = column === nothing ? nothing : column.cell_policy
    policy === nothing ? w.cell_policy : policy
end

# Where a cell sits in body column `c`: the column's own alignment, else the
# left.
function _wt_column_align(w::WidgetTable, c::Int)
    column = _get_table_column_data(w, c)
    align = column === nothing ? nothing : column.align
    align === nothing ? :left : Symbol(align)
end

# The policy of body row `r`: the row's own when it names one, else the table's.
function _wt_row_policy(w::WidgetTable, r::Int)
    row = _get_table_row_data(w, r)
    policy = row === nothing ? nothing : row.policy
    policy isa SizePolicy ? policy : w.row_policy
end

# Header `k` of a strip, or an empty cell where the strip has none.
function _wt_get_header(headers, k::Int)
    header = k <= length(headers) ? headers[k] : nothing
    header === nothing ? _wt_empty_cell() : header
end

# Whether the body of `w` holds columns of cells, `cells[c][r]`, and not rows.
_is_column_major(w::WidgetTable) = w.cell_order === :column_major

# Whether the body of `w` is a list in either direction, which the parts of a
# table draw one row at a time.
_is_listed_body(w::WidgetTable) =
    w.cells isa ListNode || (_is_column_major(w) && any(column -> column isa ListNode, w.cells))

# The cell in row `r` and column `c` of the body of `w`, in the order of the
# table, or an empty cell where the body has none.
function _wt_get_cell(w::WidgetTable, r::Int, c::Int)
    outer, inner = _is_column_major(w) ? (c, r) : (r, c)
    cells = w.cells
    line = outer <= length(cells) ? cells[outer] : nothing
    cell = (line !== nothing && inner <= length(line)) ? line[inner] : nothing
    cell === nothing ? _wt_empty_cell() : cell
end

# The count of the rows of a body that is a vector: its length, or in a
# column-major table the length of its longest column.
_count_body_rows(w::WidgetTable) =
    _is_column_major(w) ? maximum((length(column) for column in w.cells); init = 0) : length(w.cells)

# The height of what a part printed for one cell, or 0 for no cell.
_get_part_child_height(cim) =
    (cim !== nothing && cim.output isa GraphicsCanvas) ? Int(cim.output.h) : 0

# The policy of body row `r` of the cells: the table's, and at least as tall as
# the header of the row, `header`, when the row is its content.
function _wt_get_cells_row_policy(w::WidgetTable, r::Int, header)
    policy = _wt_row_policy(w, r)
    header === nothing && return policy
    (policy.min === nothing && policy.preferred === nothing &&
     (policy.weight === nothing || policy.weight == 0)) || return policy
    SizePolicy(_get_part_child_height(header), nothing, policy.max, policy.weight)
end

# ── The parts ────────────────────────────────────────────────────────────────

# The item of a part that sets the size of a column of the other part: the
# header of a column that is its content, which no width reaches.
_wt_is_content_column(policy::SizePolicy) =
    policy.preferred === nothing && (policy.weight === nothing || policy.weight == 0)

# Print the parts of a table whose rows are a vector: the header row, the header
# column and the cells, each a grid in a pane, and the regions that place the
# panes and show the graphics of the table behind them. `ctx` is the context of
# the content of the table.
function _print_eager_table_parts(p::WidgetTableToGraphicsCanvas, recursion, w::WidgetTable, ctx,
                                  graphics, pad_x::Int, pad_y::Int, bw::Int)
    n = something(get_widget_table_column_count(w), 0)
    m = _count_body_rows(w)
    hgap = 2 * pad_x + bw
    vgap = 2 * pad_y + bw
    content_x, content_y = _content_offset(p, w)
    aligns = Symbol[_wt_column_align(w, c) for c in 1:n]
    wraps = Bool[_wt_column_cell_policy(w, c) === :wrap for c in 1:n]
    offset = getfield(w, :scroll_position)
    # What the cells decide once they print: the width of every column, the
    # height of every row, and the widest cell of every column. And what the
    # headers decide once they print: the height of the header row and the
    # width of the header column.
    widths = Cell[Cell(0) for _ in 1:n]
    heights = Cell[Cell(0) for _ in 1:m]
    widest = Cell[Cell(0) for _ in 1:n]
    header_height = Cell(0)
    header_width = Cell(0)
    # The header row: `Fixed` widths from the cells, or the policies of the
    # columns when there are no cells. A header that is not offered its width
    # is measured, to be a floor for its column.
    column_header_pane = nothing
    if _wt_has_col_headers(w)
        master = m == 0
        policies = master ? Cell(Any[_get_table_column_policy(w, c) for c in 1:n]) :
                            Cell(@computation Any[Fixed(Int(widths[c][])) for c in 1:n])
        offers = Bool[wraps[c] && (master || !_wt_is_content_column(_get_table_column_policy(w, c)))
                      for c in 1:n]
        grid = GridLayout(CellVector(Cell[Cell(_wt_get_header(w.column_headers, c)) for c in 1:n]),
                          Cell(n), Cell(:left), Cell(:top), Cell(hgap), Cell(vgap), Cell(aligns),
                          Cell(master ? w.column_policy : Fixed(0)), Cell(Content), policies,
                          Cell(Any[]), Cell(offers), Cell(Bool[]), Cell(Any[]), Cell(nothing))
        pane = _make_part_pane(grid, Cell(@computation Point2D(Int((offset[]::Point2D).x[]), 0)),
                               Inset(bw + pad_y, pad_y, bw + pad_x, bw + pad_x))
        column_header_pane = print_child(recursion, pane,
                                         with_free_axis(
                                             with_inner_size(ctx; width = header_width),
                                             :y))
    end
    # The header column: `Fixed` heights from the cells. A header is never
    # offered its height, so it is measured, to be a floor for its row.
    row_header_pane = nothing
    if _wt_has_row_headers(w)
        grid = GridLayout(CellVector(Cell[Cell(_wt_get_header(w.row_headers, r)) for r in 1:m]),
                          Cell(1), Cell(:left), Cell(:top), Cell(hgap), Cell(vgap), Cell(Symbol[]),
                          Cell(Content), Cell(Fixed(0)), Cell(Any[]),
                          Cell(@computation Any[Fixed(Int(heights[r][])) for r in 1:m]),
                          Cell(Bool[]), Cell(fill(false, m)), Cell(Any[]), Cell(nothing))
        pane = _make_part_pane(grid, Cell(@computation Point2D(0, Int((offset[]::Point2D).y[]))),
                               Inset(bw + pad_y, bw + pad_y, bw + pad_x, pad_x))
        row_header_pane = print_child(recursion, pane,
                                      with_free_axis(
                                          with_inner_size(ctx; height = header_height),
                                          :x))
    end
    # The cells, which decide the widths and the heights.
    get_column_header(c) = column_header_pane === nothing ? nothing :
                           column_header_pane.content_iomap.child_iomaps[c][3]
    get_row_header(r) = row_header_pane === nothing ? nothing :
                        row_header_pane.content_iomap.child_iomaps[r][3]
    column_policies = Cell(@computation Any[
        _get_cells_column_policy(w, c, get_column_header(c), widest[c]) for c in 1:n])
    row_policies = Cell(@computation Any[_wt_get_cells_row_policy(w, r, get_row_header(r)) for r in 1:m])
    grid = GridLayout(CellVector(Cell[Cell(_wt_get_cell(w, r, c)) for r in 1:m for c in 1:n]),
                      Cell(max(1, n)), Cell(:left), Cell(:top), Cell(hgap), Cell(vgap), Cell(aligns),
                      Cell(w.column_policy), Cell(w.row_policy), column_policies, row_policies,
                      Cell(wraps), Cell(Bool[]), Cell(Any[]), Cell(nothing))
    cells_pane = print_child(recursion,
                             _make_part_pane(grid, offset, Inset(bw + pad_y, bw + pad_y, bw + pad_x, bw + pad_x)),
                             with_inner_size(ctx; width = header_width, height = header_height))
    cells = cells_pane.content_iomap
    if m > 0
        for c in 1:n
            set_cell_computation!(widths[c], () -> Int(cells.col_w[c][]))
            set_cell_computation!(widest[c], () -> maximum(
                _get_part_child_width(cells.child_iomaps[(r - 1) * n + c][3]) for r in 1:m))
        end
        for r in 1:m
            set_cell_computation!(heights[r], () -> Int(cells.row_h[r][]))
        end
    end
    column_header_pane === nothing ||
        set_cell_computation!(header_height, () -> Int(column_header_pane.output.h))
    row_header_pane === nothing ||
        set_cell_computation!(header_width, () -> Int(row_header_pane.output.w))

    # The regions, each at its place in the table, with the graphics of the
    # table moved by the place of the region.
    no_offset = Cell(0)
    regions = Any[]
    if column_header_pane !== nothing && row_header_pane !== nothing
        corner = GraphicsCanvas(Cell(Int32(0)), Cell(Int32(0)), Cell(Int32(0)), Cell(Int32(0)),
                                graphics, layout_none, true, Cell(nothing))
        size_w = Cell(@computation Int32(Int(header_width[])))
        size_h = Cell(@computation Int32(Int(header_height[])))
        viewport = GraphicsViewport(Cell(Int32(0)), Cell(Int32(0)), size_w, size_h, Cell(corner),
                                    Cell(affine_identity), Cell(nothing))
        push!(regions, GraphicsCanvas(Cell(Int32(content_x)), Cell(Int32(content_y)), size_w, size_h,
                                      CellVector(Cell[Cell(viewport)]), layout_none, true, Cell(nothing)))
    end
    get_place(start, offset_cell) = Cell(@computation Int32(start + Int(offset_cell[])))
    column_header_pane === nothing ||
        push!(regions, _make_part_region(column_header_pane, graphics; x = get_place(content_x, header_width),
                                         y = Cell(Int32(content_y)), origin_x = header_width,
                                         origin_y = no_offset, pad_x, pad_y, bw))
    row_header_pane === nothing ||
        push!(regions, _make_part_region(row_header_pane, graphics; x = Cell(Int32(content_x)),
                                         y = get_place(content_y, header_height), origin_x = no_offset,
                                         origin_y = header_height, pad_x, pad_y, bw))
    push!(regions, _make_part_region(cells_pane, graphics; x = get_place(content_x, header_width),
                                     y = get_place(content_y, header_height), origin_x = header_width,
                                     origin_y = header_height, pad_x, pad_y, bw))
    (; column_header_pane, row_header_pane, cells_pane, header_width, header_height, regions,
       rows = m, columns = n)
end

# The geometry of the parts as if they were not scrolled.
function _compute_eager_table_geometry(parts, pad_x::Int, pad_y::Int, bw::Int)
    m, n = parts.rows, parts.columns
    has_ch = parts.column_header_pane !== nothing
    has_rh = parts.row_header_pane !== nothing
    row_offset = has_ch ? 1 : 0
    col_offset = has_rh ? 1 : 0
    grid_rows = m + row_offset
    grid_cols = n + col_offset
    grid_cols == 0 && return _wt_geometry_empty(pad_x, pad_y, bw)
    cells = parts.cells_pane.content_iomap
    # The cells decide the widths; with no rows, the header row does.
    master = m == 0 ? (has_ch ? parts.column_header_pane.content_iomap : nothing) : cells
    col_w = Int[]
    has_rh && push!(col_w, Int(parts.row_header_pane.content_iomap.output.w))
    for c in 1:n
        push!(col_w, master === nothing ? 0 : Int(master.col_w[c][]))
    end
    row_h = Int[]
    has_ch && push!(row_h, Int(parts.column_header_pane.content_iomap.output.h))
    for r in 1:m
        push!(row_h, Int(cells.row_h[r][]))
    end
    col_x = compute_axis_offsets(col_w, 2 * pad_x + bw)
    row_y = compute_axis_offsets(row_h, 2 * pad_y + bw)
    WTGeometry(m, n, row_offset, col_offset, grid_rows, grid_cols, has_rh, has_ch, col_x, row_y,
               col_x[grid_cols + 1] + bw, row_y[grid_rows + 1] + bw, bw, pad_x, pad_y,
               bw + pad_x, bw + pad_y)
end

_wt_geometry_empty(pad_x::Int, pad_y::Int, bw::Int) =
    WTGeometry(0, 0, 0, 0, 0, 0, false, false, Int[bw], Int[bw], bw, bw, bw,
               pad_x, pad_y, bw + pad_x, bw + pad_y)


# ── Selection-shape recognition ───────────────────────────────────────────────
# `.<field>[index]∅` → (field_name, 1-based index), else nothing.
function _wt_field_element_terminal(sel)
    sel = sel
    sel isa ConcreteReference || return nothing
    h = sel.head
    h isa FieldReferenceStep || return nothing
    t = sel.tail
    t isa ConcreteReference || return nothing
    r = t.head
    (r isa RangeReferenceStep && is_element_reference_step(r)) || return nothing
    t.tail isa EmptyReference || return nothing
    (h.name, r.start + 1)
end

# (:table,_,_) | (:row,r,_) | (:col,c,_) | (:cell,r,c) | (:column_header,c,_) |
# (:row_header,r,_) | nothing. A header is a part of its own, apart from its
# column or its row.
function _wt_selection_shape(w::WidgetTable, sel, geom::WTGeometry)
    sel isa EmptyReference && return (:table, 0, 0)
    fe = _wt_field_element_terminal(sel)
    if fe !== nothing
        field, idx = fe
        if field == "rows"
            (1 <= idx <= geom.nrows) || return nothing
            return (:row, idx, 0)
        elseif field == "columns"
            (1 <= idx <= geom.ncols) || return nothing
            return (:col, idx, 0)
        elseif field == "column_headers"
            (geom.has_col_headers && 1 <= idx <= geom.ncols) || return nothing
            return (:column_header, idx, 0)
        elseif field == "row_headers"
            (geom.has_row_headers && 1 <= idx <= geom.nrows) || return nothing
            return (:row_header, idx, 0)
        end
        return nothing
    end
    # `cells[r][c]∅` → whole cell (r,c).
    rc = _wt_cell_terminal(w, sel)
    rc === nothing && return nothing
    r, c = rc
    (1 <= r <= geom.nrows && 1 <= c <= geom.ncols) || return nothing
    return (:cell, r, c)
end

# `cells[r][c]…` of `w`, or `cells[c][r]…` of a column-major `w` — the cell in row
# r and column c. Returns `(r, c, tail_after_cell)` for a path that begins with the
# two element steps under `cells`, else nothing. The tail lets a caller
# distinguish a whole cell (`tail` is `∅`) from an in-cell content cursor.
function _wt_cell_split(w::WidgetTable, sel)
    split = _wt_split_cell_path(sel)
    (split === nothing || !_is_column_major(w)) && return split
    (split[2], split[1], split[3])
end

# The two element steps under `cells` and the rest, `(outer, inner, rest)`, in
# the order of the path, or nothing.
function _wt_split_cell_path(sel)
    sel isa ConcreteReference || return nothing
    (sel.head isa FieldReferenceStep && sel.head.name == "cells") || return nothing
    t = sel.tail
    t isa ConcreteReference || return nothing
    (t.head isa RangeReferenceStep && is_element_reference_step(t.head)) || return nothing
    r = t.head.start + 1
    t2 = t.tail
    t2 isa ConcreteReference || return nothing
    (t2.head isa RangeReferenceStep && is_element_reference_step(t2.head)) || return nothing
    c = t2.head.start + 1
    (r, c, t2.tail)
end

# A whole cell, terminating, → (r, c), else nothing.
_wt_cell_terminal(w::WidgetTable, sel) =
    (s = _wt_cell_split(w, sel); s === nothing || !(s[3] isa EmptyReference) ? nothing : (s[1], s[2]))

# A whole cell OR an in-cell content cursor beneath it → (r, c), else nothing —
# unlike `_wt_cell_terminal` it does not require the path to terminate at the
# cell, so an in-cell cursor can be promoted to its enclosing cell.
_wt_cell_prefix(w::WidgetTable, sel) =
    (s = _wt_cell_split(w, sel); s === nothing ? nothing : (s[1], s[2]))

# (x, y, w, h) of the selection highlight band in outer-canvas coordinates, or
# (0, 0, 0, 0) when there is no valid selection — a 0-size rect the renderer skips.
# Drawn as a persistent overlay whose geometry reads the selection, so a caret
# move never rebuilds the table's content vector (printer-locality dimension A).
function _wt_highlight_bounds(w::WidgetTable, sel, geom::WTGeometry)
    shape = _wt_selection_shape(w, sel, geom)
    shape === nothing && return (0, 0, 0, 0)
    kind = shape[1]
    if kind === :table
        return (0, 0, geom.total_w, geom.total_h)
    elseif kind === :row
        gr = shape[2] + geom.row_offset
        return (0, geom.row_y[gr], geom.total_w, geom.row_y[gr + 1] - geom.row_y[gr])
    elseif kind === :col
        gc = shape[2] + geom.col_offset
        return (geom.col_x[gc], 0, geom.col_x[gc + 1] - geom.col_x[gc], geom.total_h)
    elseif kind === :cell
        gr = shape[2] + geom.row_offset
        gc = shape[3] + geom.col_offset
        return (geom.col_x[gc], geom.row_y[gr],
                geom.col_x[gc + 1] - geom.col_x[gc], geom.row_y[gr + 1] - geom.row_y[gr])
    elseif kind === :column_header
        gc = shape[2] + geom.col_offset
        return (geom.col_x[gc], geom.row_y[1], geom.col_x[gc + 1] - geom.col_x[gc], geom.row_y[2] - geom.row_y[1])
    elseif kind === :row_header
        gr = shape[2] + geom.row_offset
        return (geom.col_x[1], geom.row_y[gr], geom.col_x[2] - geom.col_x[1], geom.row_y[gr + 1] - geom.row_y[gr])
    end
    (0, 0, 0, 0)
end


function print_document(p::WidgetTableToGraphicsCanvas, recursion, w::WidgetTable, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    # A cell is one line of a row, so the text of every cell, header and corner
    # draws at single spacing, as the label of a row number does.
    ctx === nothing || (ctx = with_property(ctx, :line_spacing, SingleSpacing()))
    # The printer reads the type of `cells` and nothing else says which table
    # this is: a list in either direction draws the rows a viewport shows, a
    # vector draws them all.
    # A corner makes a table of a list, whose rows can be an empty vector at
    # first.
    (_is_listed_body(w) || w.corner !== nothing) && return _print_table_parts(p, recursion, w, ctx)
    position = w.position::Point2D
    # The cell padding is the projection's, from the theme: how a table is
    # drawn is not what a table is.
    pad_x = Int(p.cell_padding.left[])
    pad_y = Int(p.cell_padding.top[])
    bw  = max(1, _sc(Int(w.border_width)))
    box = _get_box_insets(p, w)
    colors = _get_box_colors(p, w)
    inset_width, inset_height = _inset_total(p, w)
    divider_stroke = _get_state_stroke(p, w, :divider)
    header_row_color = _get_state_color(p, w, :header_row)
    row_selected_color = _get_state_color(p, w, :row; state = :selected)
    # The parts are drawn inside the table's own box, so they get the table's
    # range less its insets, in the same state.
    inner = ctx === nothing ? ctx : with_inner_size(ctx; width = inset_width, height = inset_height)

    # The graphics of the table, in the coordinates of its geometry. The parts
    # read them, and they read the geometry of the parts, only when drawn.
    geometry = Cell(nothing)
    graphics = CellVector(@computation _wt_make_graphics(p, w, geometry[], header_row_color,
                                                         divider_stroke, row_selected_color))
    # The parts, built again when the table changes its shape: a row, a column
    # or a header added or removed.
    parts = Cell(@computation _print_eager_table_parts(p, recursion, w, inner, graphics,
                                                       pad_x, pad_y, bw))
    set_cell_computation!(geometry, () -> _compute_eager_table_geometry(parts[], pad_x, pad_y, bw))

    table_w = Cell(@computation Int32(Int(parts[].header_width[]) + Int(parts[].cells_pane.output.w) +
                                      inset_width))
    table_h = Cell(@computation Int32(Int(parts[].header_height[]) + Int(parts[].cells_pane.output.h) +
                                      inset_height))
    # Invisible whole-canvas hit target so a table nested in a container (which
    # gates routing on `hit_element_at`) is hoverable/clickable over the whole
    # box, not just over drawn glyphs/rules. Cf. the WidgetTree hit target.
    hit_target = GraphicsRect(0, 0, 0, 0; color = color_transparent, radius = 0)
    set_cell_computation!(getfield(hit_target, :w), () -> Int32(table_w[]))
    set_cell_computation!(getfield(hit_target, :h), () -> Int32(table_h[]))
    elements = CellVector(@computation begin
        result = Any[hit_target]
        # The box: margin, border, padding and content, from the outside in.
        # Transparent and zero-width by default, so it costs nothing.
        _push_box_parts!(result, box, colors, Int(table_w[]) - inset_width,
                         Int(table_h[]) - inset_height)
        append!(result, parts[].regions)
        result
    end)
    canvas = GraphicsCanvas(Cell(Int32(_origin(position)[1])), Cell(Int32(_origin(position)[2])),
                            table_w, table_h, elements, layout_none, true, Cell(nothing))
    WidgetTableToGraphicsCanvasIoMap(p, w, canvas, parts, geometry)
end

# The graphics of a table, in the coordinates of its geometry: the header bands,
# the bands of the light and of the selection, and the rules.
#
# The two bands are persistent rects whose bounds read the row or the column of
# the mouse target and the selected reference (collapsed to 0×0 when there is
# none — the renderer skips it), so a caret move changes only their geometry and
# not these elements (printer-locality dimension A). The band of the light is
# behind the selection band, so a selected row under the pointer still reads as
# selected.
function _wt_make_graphics(p::WidgetTableToGraphicsCanvas, w::WidgetTable, geom::WTGeometry,
                           header_row_color, divider_stroke, row_selected_color)
    result = Any[]
    geom.grid_cols == 0 && return result
    if geom.has_col_headers
        push!(result, GraphicsRect(0, 0, geom.total_w, geom.row_y[2]; color = header_row_color))
    end
    if geom.has_row_headers
        push!(result, GraphicsRect(0, 0, geom.col_x[2], geom.total_h; color = header_row_color))
    end
    push!(result, _wt_make_band(w, () -> _find_wt_lit_reference(w, get_mouse_target(w)), geom,
                                p.layer_hovered_color, p.row_radius))
    push!(result, _wt_make_band(w, () -> w.selection, geom, row_selected_color, p.row_radius))
    # The frame of each open cell whose last commit failed.
    marks = CellVector(@computation begin
        rects = Any[]
        for cell in something(w.open_cells, ())
            cell.reason === nothing && continue
            gr, gc = cell.row + geom.row_offset, cell.column + geom.col_offset
            (1 <= gr <= geom.grid_rows && 1 <= gc <= geom.grid_cols) || continue
            append!(rects, _make_cell_mark_rects(geom.col_x[gc] + geom.bw, geom.row_y[gr] + geom.bw,
                                                 geom.col_x[gc + 1] - geom.col_x[gc] - geom.bw,
                                                 geom.row_y[gr + 1] - geom.row_y[gr] - geom.bw,
                                                 p.cell_mark_stroke))
        end
        rects
    end)
    push!(result, GraphicsCanvas(Cell(Int32(0)), Cell(Int32(0)), Cell(Int32(geom.total_w)),
                                 Cell(Int32(geom.total_h)), marks, layout_none, true, Cell(nothing)))
    # Horizontal rules at row_y[gr] for gr in 1..grid_rows+1 (the top border,
    # the inner rules, the bottom border), and vertical rules likewise.
    for gr in 1:(geom.grid_rows + 1)
        push!(result, GraphicsRect(0, geom.row_y[gr], geom.total_w, geom.bw; color = divider_stroke.color))
    end
    for gc in 1:(geom.grid_cols + 1)
        push!(result, GraphicsRect(geom.col_x[gc], 0, geom.bw, geom.total_h; color = divider_stroke.color))
    end
    result
end

# A band over the row, the column, the cell or the table that `reference()`
# names, or a 0×0 rect when it names none.
function _wt_make_band(w::WidgetTable, reference, geom::WTGeometry, color, radius::Int)
    bounds = Cell(@computation _wt_highlight_bounds(w, reference(), geom))
    rect = GraphicsRect(0, 0, 0, 0; color, radius)
    set_cell_computation!(getfield(rect, :x), () -> Int32(bounds[][1]))
    set_cell_computation!(getfield(rect, :y), () -> Int32(bounds[][2]))
    set_cell_computation!(getfield(rect, :w), () -> Int32(bounds[][3]))
    set_cell_computation!(getfield(rect, :h), () -> Int32(bounds[][4]))
    rect
end

# ── The parts under a place ──────────────────────────────────────────────────

# The place of the region of a part in the content of the table, and the place
# of the grid of the part in the coordinates of the geometry.
function _wt_get_part_places(iomap::WidgetTableToGraphicsCanvasIoMap, pane)
    parts = iomap.parts
    geom = iomap.geometry
    region_x = pane === parts.row_header_pane ? 0 : Int(parts.header_width[])
    region_y = pane === parts.column_header_pane ? 0 : Int(parts.header_height[])
    ((region_x, region_y), (region_x + geom.grid_off_x, region_y + geom.grid_off_y))
end

# A point of the table in the coordinates of its geometry: the table as if it
# were not scrolled. A point over a part that scrolls moves by the offset that
# the pane of the cells draws with, which the headers share.
function _wt_get_unscrolled_point(p::WidgetTableToGraphicsCanvas, iomap::WidgetTableToGraphicsCanvasIoMap,
                                  x::Int, y::Int)
    parts = iomap.parts
    content_x, content_y = _content_offset(p, iomap.input)
    content = _get_part_content(parts.cells_pane)
    local_x = x - content_x
    local_y = y - content_y
    (local_x < Int(parts.header_width[]) ? local_x : local_x - Int(content.x),
     local_y < Int(parts.header_height[]) ? local_y : local_y - Int(content.y))
end

# The pane that holds the document a reference starts at, the index of that
# document in the grid of the pane, the steps from the table to the document,
# and the rest of the reference: `column_headers[c].…`, `row_headers[r].…` or
# `cells[r][c].…`. `nothing` for any other reference.
function _wt_find_part_entry(iomap::WidgetTableToGraphicsCanvasIoMap, reference)
    parts = iomap.parts
    reference isa ConcreteReference || return nothing
    head = reference.head
    head isa FieldReferenceStep || return nothing
    tail = reference.tail
    tail isa ConcreteReference || return nothing
    step = tail.head
    (step isa RangeReferenceStep && is_element_reference_step(step)) || return nothing
    k = step.start + 1
    if head.name == "column_headers"
        pane = parts.column_header_pane
        (pane === nothing || !(1 <= k <= parts.columns)) && return nothing
        return (pane, k, (FieldReferenceStep("column_headers"), RangeReferenceStep(k - 1, k)), tail.tail)
    elseif head.name == "row_headers"
        pane = parts.row_header_pane
        (pane === nothing || !(1 <= k <= parts.rows)) && return nothing
        return (pane, k, (FieldReferenceStep("row_headers"), RangeReferenceStep(k - 1, k)), tail.tail)
    elseif head.name == "cells"
        split = _wt_cell_split(iomap.input, reference)
        split === nothing && return nothing
        r, c, rest = split
        (1 <= r <= parts.rows && 1 <= c <= parts.columns) || return nothing
        return (parts.cells_pane, (r - 1) * parts.columns + c, _wt_get_cell_steps(iomap.input, r, c), rest)
    end
    nothing
end

# The IO map of the document in entry `i` of the grid of `pane`, and the place of
# its canvas in the coordinates of the geometry; `nothing` when it drew none.
function _wt_find_part_cell(iomap::WidgetTableToGraphicsCanvasIoMap, pane, i::Int)
    entries = pane.content_iomap.child_iomaps
    1 <= i <= length(entries) || return nothing
    (x_cell, y_cell, cim) = entries[i]
    cim === nothing && return nothing
    out = cim.output
    out isa GraphicsCanvas || return nothing
    _, (grid_x, grid_y) = _wt_get_part_places(iomap, pane)
    (cim, grid_x + Int(x_cell[]) + Int(out.x), grid_y + Int(y_cell[]) + Int(out.y))
end

# ── Reference mapping ────────────────────────────────────────────────────────
# Forward: a cell, a column header or a row header (`cells[r][c].…`,
# `column_headers[c].…`, `row_headers[r].…`) is a child of the grid of the part
# that holds it, and the pane of that part maps it; the steps from the table's
# canvas to the canvas of the pane are found by identity, after the parts of the
# box. The table itself is its own canvas. A whole row has no node of its own,
# because its band is drawn in place, so it has no image.
function map_reference_forward(p::WidgetTableToGraphicsCanvas, iomap::WidgetTableToGraphicsCanvasIoMap, reference)
    reference isa Reference || return nothing
    reference = strip_reference_types(reference)
    reference isa EmptyReference && return EmptyReference()
    found = _wt_find_part_entry(iomap, reference)
    found === nothing && return nothing
    pane, i, _, rest = found
    _map_part_forward(iomap, pane, ConcreteReference(RangeReferenceStep(i - 1, i), rest))
end

map_reference_forward(::WidgetTableToGraphicsCanvas, iomap, reference) = _map_child_forward(iomap, reference)

# Backward: a point maps to the part at it. A path into the canvas of a part
# names no document of the table by itself, so it maps to no path into the table.
function map_reference_backward(p::WidgetTableToGraphicsCanvas, iomap::WidgetTableToGraphicsCanvasIoMap, reference)
    point = find_reference_point(reference)
    point === nothing ? nothing : _map_wt_point(p, iomap, point)
end

# What the table holds at `(x, y)` of its canvas, as `_wt_hit_test` answers it in
# the coordinates of the geometry: a place on the margin, the border or the
# padding is clamped into the grid.
function _find_wt_hit(p::WidgetTableToGraphicsCanvas, iomap::WidgetTableToGraphicsCanvasIoMap,
                      x::Int, y::Int)
    geom = iomap.geometry
    ux, uy = _wt_get_unscrolled_point(p, iomap, x, y)
    _wt_hit_test(geom, clamp(ux, 0, max(0, geom.total_w - 1)),
                       clamp(uy, 0, max(0, geom.total_h - 1)))
end

# A point maps to the cell, the row header, the column header or the corner at
# it: the reference that an Alt+click there selects.
function _map_wt_point(p::WidgetTableToGraphicsCanvas, iomap::WidgetTableToGraphicsCanvasIoMap, point)
    _is_point_on_canvas(iomap.output, point) || return nothing
    hit = _find_wt_hit(p, iomap, point.x, point.y)
    kind = hit[1]
    kind === :corner && return EmptyReference()
    kind === :row && return ConcreteReference(FieldReferenceStep("row_headers"),
                                ConcreteReference(RangeReferenceStep(hit[2] - 1, hit[2])))
    kind === :col && return ConcreteReference(FieldReferenceStep("column_headers"),
                                ConcreteReference(RangeReferenceStep(hit[2] - 1, hit[2])))
    kind === :cell || return nothing
    _wt_cell_ref(iomap.input, hit[2], hit[3])
end

map_reference_backward(::WidgetTableToGraphicsCanvas, iomap, reference) = nothing

# The steps from the table to the body cell in row `r` and column `c`:
# `cells[r][c]`, or `cells[c][r]` in a column-major table.
_wt_get_cell_steps(w::WidgetTable, r::Int, c::Int) =
    _is_column_major(w) ?
        (FieldReferenceStep("cells"), RangeReferenceStep(c - 1, c), RangeReferenceStep(r - 1, r)) :
        (FieldReferenceStep("cells"), RangeReferenceStep(r - 1, r), RangeReferenceStep(c - 1, c))

# ── Reading (gestures) ───────────────────────────────────────────────────────
# Gesture-aware reader. Left clicks resolve here (header/corner → row/column/
# table; Alt+click promotes a data cell to a whole cell; a plain click routes
# into the cell content). Keyboard grid navigation
# (Alt+arrows, Ctrl+Alt+Home, Shift/Ctrl+Space, Enter) is resolved against the
# live table. A turn of the wheel scrolls the parts. Every other event goes to a
# cell (`_wt_route_event`). An operation from below finds no cell to go to.
function read_intent(p::WidgetTableToGraphicsCanvas, recursion, change::Intent, iomap::WidgetTableToGraphicsCanvasIoMap)
    g = change.gesture
    change.operation === nothing || return Intent(g, nothing)
    g isa MouseClick && g.button === :left && return Intent(g, _wt_mouse_select(p, iomap, g))
    # A pointer motion does not go into the cells: the part under the pointer is the
    # backward map of the point. A dwell goes to the cell under it.
    g isa MouseMove && return Intent(g, nothing)
    if g isa MouseScroll
        (region_x, region_y), _ = _wt_get_part_places(iomap, iomap.parts.cells_pane)
        content_x, content_y = _content_offset(p, iomap.input)
        return Intent(g, _read_cells_wheel(iomap.output, iomap.parts.cells_pane,
                                           content_x + region_x, content_y + region_y, g))
    end
    if g isa KeyDown
        op = _read_open_cell_key(iomap.input, g)
        op === nothing || return Intent(g, op)
        op = _wt_key_navigate(iomap, g, iomap.geometry)
        op === nothing || return Intent(g, op)
    end
    op = _wt_route_event(p, iomap, g)
    Intent(g, op isa Operation ? op : something(_read_whole_cell_key(iomap.input, g), Some(op)))
end

# Resolve a left click into a selection operation (or nothing). The margin,
# the border and the padding belong to the table, so a press there is clamped
# into the grid.
function _wt_mouse_select(p::WidgetTableToGraphicsCanvas, iomap::WidgetTableToGraphicsCanvasIoMap, g::MouseClick)
    geom = iomap.geometry
    x, y = _wt_get_unscrolled_point(p, iomap, g.x, g.y)
    x = clamp(x, 0, max(0, geom.total_w - 1))
    y = clamp(y, 0, max(0, geom.total_h - 1))
    hit = _wt_hit_test(geom, x, y)
    kind = hit[1]
    if kind === :corner
        return ReplaceSelectionOperation(EmptyReference())
    elseif kind === :row
        return ReplaceSelectionOperation(_wt_row_ref(hit[2]))
    elseif kind === :col
        g.modifiers.alt && return ReplaceSelectionOperation(_wt_column_header_ref(hit[2]))
        return _wt_route_header_click(iomap, hit[2], g, x, y)
    elseif kind === :cell
        r, c = hit[2], hit[3]
        g.modifiers.alt && return ReplaceSelectionOperation(_wt_cell_ref(iomap.input, r, c))
        return _wt_route_cell_click(iomap, r, c, g, x, y)
    end
    return nothing
end

# Route a plain click at `(x, y)`, in the coordinates of the geometry, into the
# content of the header of column `c`, and root what it answers under the
# header. A header that declines it — a label has nothing to say to one —
# selects its column, as the table of a list does.
function _wt_route_header_click(iomap::WidgetTableToGraphicsCanvasIoMap, c::Int, g::MouseClick,
                                x::Int, y::Int)
    column = ReplaceSelectionOperation(_wt_col_ref(c))
    found = _wt_find_part_entry(iomap, _wt_column_header_ref(c))
    found === nothing && return column
    pane, i, steps, _ = found
    cell = _wt_find_part_cell(iomap, pane, i)
    cell === nothing && return column
    cim, left, top = cell
    op = read_intent(cim.projection, cim, MouseClick(g.button, x - left, y - top, g.count, g.modifiers;
                                                     time = g.time))
    op === nothing ? column : reroot_operation(op, steps)
end

# Classify a click point: :corner | (:row,r) | (:col,c) | (:cell,r,c) | :outside.
function _wt_hit_test(geom::WTGeometry, x::Int, y::Int)
    (0 <= x < geom.total_w && 0 <= y < geom.total_h) || return (:outside, 0, 0)
    gc = something(find_axis_band(geom.col_x, x), 0)
    gr = something(find_axis_band(geom.row_y, y), 0)
    (gc == 0 || gr == 0) && return (:outside, 0, 0)
    header_col = geom.has_row_headers && gc == 1
    header_row = geom.has_col_headers && gr == 1
    if header_col && header_row
        return (:corner, 0, 0)
    elseif header_row
        return (:col, gc - geom.col_offset, 0)
    elseif header_col
        return (:row, gr - geom.row_offset, 0)
    else
        return (:cell, gr - geom.row_offset, gc - geom.col_offset)
    end
end

# ── The light (whole row) ────────────────────────────────────────────────────
# The light marks the *row* of a place in the table (a body cell or a row header →
# that row); a column header → its column, which a press there selects; the
# corner → none. The reference of the row or the column of the place that
# `target` names, or nothing.
function _find_wt_lit_reference(w::WidgetTable, target)
    cell = _wt_cell_prefix(w, target)
    cell === nothing || cell[1] < 1 || return _wt_row_ref(cell[1])
    # A whole row of a row-major body, `cells[r]`.
    row = _is_column_major(w) ? 0 : _widget_element_selected(target, "cells")
    row > 0 && return _wt_row_ref(row)
    row = _widget_element_selected(target, "rows")
    row > 0 && return _wt_row_ref(row)
    row = _widget_element_selected(target, "row_headers")
    row > 0 && return _wt_row_ref(row)
    column = _widget_element_selected(target, "column_headers")
    column > 0 && return _wt_col_ref(column)
    nothing
end

# Route a plain click at `(x, y)`, in the coordinates of the geometry, into the
# content of the cell in row `r` and column `c`, in the coordinates of the
# cell, and root what it answers under the cell.
function _wt_route_cell_click(iomap::WidgetTableToGraphicsCanvasIoMap, r::Int, c::Int, g::MouseClick,
                              x::Int, y::Int)
    parts = iomap.parts
    found = _wt_find_part_cell(iomap, parts.cells_pane, (r - 1) * parts.columns + c)
    # A cell that declines the click — a label has nothing to say to one —
    # leaves it to the row, and the row is selected: a table of text is a
    # table of rows. The answer of the cell is re-rooted under the cell; an
    # operation that names its own document, such as the toggle of a checkbox,
    # stays as it is.
    found === nothing && return ReplaceSelectionOperation(_wt_row_ref(r))
    cim, left, top = found
    op = read_intent(cim.projection, cim, MouseClick(g.button, x - left, y - top, g.count, g.modifiers;
                                                     time = g.time))
    op === nothing && return ReplaceSelectionOperation(_wt_row_ref(r))
    reroot_operation(op, _wt_get_cell_steps(iomap.input, r, c))
end

# Keyboard grid navigation, addressed via cells[r][c].
function _wt_key_navigate(iomap::WidgetTableToGraphicsCanvasIoMap, evt::KeyDown, geom::WTGeometry)
    nrows, ncols = geom.nrows, geom.ncols
    (nrows == 0 || ncols == 0) && return nothing
    sel = iomap.input.selection

    if evt.key === :home && evt.modifiers.ctrl && evt.modifiers.alt
        return ReplaceSelectionOperation(EmptyReference())
    end

    shape = _wt_selection_shape(iomap.input, sel, geom)
    cell_rc = _wt_cell_terminal(iomap.input, sel)

    if evt.key === :return
        if shape !== nothing && shape[1] === :row
            return ReplaceSelectionOperation(_wt_cell_ref(iomap.input, shape[2], 1))
        elseif shape !== nothing && shape[1] === :col
            return ReplaceSelectionOperation(_wt_cell_ref(iomap.input, 1, shape[2]))
        elseif cell_rc !== nothing
            return _wt_enter_cell_content(iomap, cell_rc[1], cell_rc[2])
        end
        return nothing
    end

    if evt.key === :space && (evt.modifiers.shift ⊻ evt.modifiers.ctrl)
        cell_rc === nothing && return nothing
        r, c = cell_rc
        if evt.modifiers.shift
            return ReplaceSelectionOperation(_wt_row_ref(r))
        else
            return ReplaceSelectionOperation(_wt_col_ref(c))
        end
    end

    if (evt.modifiers.alt || shape !== nothing) && evt.key in (:up, :down, :left, :right)
        if shape !== nothing && shape[1] === :row
            r = shape[2]
            if evt.key === :up
                return ReplaceSelectionOperation(_wt_row_ref(max(1, r - 1)))
            elseif evt.key === :down
                return ReplaceSelectionOperation(_wt_row_ref(min(nrows, r + 1)))
            elseif evt.key === :right
                return ReplaceSelectionOperation(_wt_cell_ref(iomap.input, r, 1))
            else
                return nothing
            end
        elseif shape !== nothing && shape[1] === :col
            c = shape[2]
            if evt.key === :left
                return ReplaceSelectionOperation(_wt_col_ref(max(1, c - 1)))
            elseif evt.key === :right
                return ReplaceSelectionOperation(_wt_col_ref(min(ncols, c + 1)))
            elseif evt.key === :down
                return ReplaceSelectionOperation(_wt_cell_ref(iomap.input, 1, c))
            else
                return nothing
            end
        else
            # A whole cell moves directly; an in-cell content cursor (`cells[r][c].…`,
            # so the terminating `cell_rc` is nothing) is first promoted to its whole
            # cell, then moved. A plain arrow never reaches this branch on an in-cell
            # cursor — `shape` is nothing and `alt` is unset, so the block above is
            # skipped and the arrow stays with the cell's own text editing; only
            # Alt+arrow promotes.
            rc = cell_rc === nothing ? _wt_cell_prefix(iomap.input, sel) : cell_rc
            rc === nothing && return nothing
            r, c = rc
            if evt.key === :up
                r = max(1, r - 1)
            elseif evt.key === :down
                r = min(nrows, r + 1)
            elseif evt.key === :left
                c = max(1, c - 1)
            elseif evt.key === :right
                c = min(ncols, c + 1)
            end
            return ReplaceSelectionOperation(_wt_cell_ref(iomap.input, r, c))
        end
    end
    return nothing
end

# ── The open cells ───────────────────────────────────────────────────────────

# The open cell in row `k` and column `c` of `w`, `(row, column, reason)`, or
# `nothing`.
function _find_open_cell(w::WidgetTable, k::Int, c::Int)
    for cell in something(w.open_cells, ())
        cell.row == k && cell.column == c && return cell
    end
    nothing
end

# Enter, Tab, Shift+Tab and Escape in the open cell that the selection is in,
# before the cell reads them: the commit or the drop of the cell, which the owner
# of the table converts; `nothing` for another key or another place.
function _read_open_cell_key(w::WidgetTable, g::KeyDown)
    g.key in (:return, :tab, :escape) || return nothing
    isempty(something(w.open_cells, ())) && return nothing
    prefix = _wt_cell_prefix(w, w.selection)
    prefix === nothing && return nothing
    k, c = prefix
    _find_open_cell(w, k, c) === nothing && return nothing
    g.key === :escape && return DropTableCellOperation(w, k, c)
    CommitTableCellOperation(w, k, c, g.key === :return ? :return : g.modifiers.shift ? :backtab : :tab)
end

# F2 or a typed character on the whole cell that the selection names, which the
# cell took no key for, and which is not open: the opening of the cell, which the
# owner of the table converts; `nothing` for another key or another place, and
# for a table that no owner opens.
function _read_whole_cell_key(w::WidgetTable, g)
    w.open_cells === nothing && return nothing
    if g isa KeyDown
        (g.key === :f2 && g.modifiers == ModifierKeys()) || return nothing
        text = nothing
    elseif g isa KeyPress
        (g.modifiers.ctrl || g.modifiers.alt || g.modifiers.meta || any(iscntrl, g.text)) && return nothing
        text = g.text
    else
        return nothing
    end
    cell = _wt_cell_terminal(w, w.selection)
    cell === nothing && return nothing
    k, c = cell
    _find_open_cell(w, k, c) === nothing || return nothing
    EditTableCellOperation(w, k, c, text)
end

# The frame of the mark of a cell: four bars of `stroke` inside the box at
# `(x, y)`, `width` by `height`.
function _make_cell_mark_rects(x::Int, y::Int, width::Int, height::Int, stroke::StyleStroke)
    t, color = Int(stroke.width), stroke.color
    Any[GraphicsRect(x, y, width, t; color), GraphicsRect(x, y + height - t, width, t; color),
        GraphicsRect(x, y, t, height; color), GraphicsRect(x + width - t, y, t, height; color)]
end

# The tooltip of the reason of the mark of a cell, for a rest of the pointer on
# it, rooted under the cell; `nothing` for a cell with no mark.
function _read_cell_mark_dwell(w::WidgetTable, k::Int, c::Int, g::MouseDwell)
    cell = _find_open_cell(w, k, c)
    (cell === nothing || cell.reason === nothing) && return nothing
    reroot_operation(make_tooltip_operation(w, PrimitiveString(cell.reason), g), _wt_get_cell_steps(w, k, c))
end

_wt_row_ref(r::Int) = ConcreteReference(FieldReferenceStep("rows"),
    ConcreteReference(RangeReferenceStep(r - 1, r), EmptyReference()))
_wt_col_ref(c::Int) = ConcreteReference(FieldReferenceStep("columns"),
    ConcreteReference(RangeReferenceStep(c - 1, c), EmptyReference()))
# The header of column `c` itself, a part apart from its column.
_wt_column_header_ref(c::Int) = ConcreteReference(FieldReferenceStep("column_headers"),
    ConcreteReference(RangeReferenceStep(c - 1, c), EmptyReference()))
_wt_cell_ref(w::WidgetTable, r::Int, c::Int) = extend_reference(EmptyReference(), _wt_get_cell_steps(w, r, c)...)

# Place a character cursor at the start of a cell's content.
function _wt_enter_cell_content(iomap::WidgetTableToGraphicsCanvasIoMap, r::Int, c::Int)
    parts = iomap.parts
    found = _wt_find_part_cell(iomap, parts.cells_pane, (r - 1) * parts.columns + c)
    found === nothing && return nothing
    cim = found[1]
    op = read_intent(cim.projection, cim, KeyDown(:home, ModifierKeys(ctrl=true);
                                                  time = time()))
    op isa ReplacePathOperation || return nothing
    reroot_operation(op, _wt_get_cell_steps(iomap.input, r, c))
end

# 3-arg form: a *parent* container (composite, grid, split pane) routes a raw
# event to this nested table. The table's own gesture logic (left-click
# selection, grid navigation, the wheel) must still run, so a gesture is lifted
# into an Intent and handled by the 4-arg reader. An operation finds no cell to
# go to, and every other event goes to a cell.
function read_intent(p::WidgetTableToGraphicsCanvas, iomap::WidgetTableToGraphicsCanvasIoMap, event)
    _outside_widget(iomap, event) && return nothing
    if event isa MouseClick || event isa KeyDown || event isa MouseScroll ||
       event isa MouseMove
        return read_intent(p, nothing, Intent(event, nothing), iomap).operation
    end
    event isa Operation && return nothing
    return _wt_route_event(p, iomap, event)
end

# An event that is not a gesture of the table's own goes to a cell. One with a
# position goes to the cell under it. One with no position, such as a key or a
# character, goes to the cell the selection is in.
function _wt_route_event(p::WidgetTableToGraphicsCanvas, iomap::WidgetTableToGraphicsCanvasIoMap, event)
    if event isa MouseDwell && !isempty(something(iomap.input.open_cells, ()))
        # A rest on an open cell whose last commit failed shows the reason of its mark.
        x, y = _wt_get_unscrolled_point(p, iomap, Int(event.x), Int(event.y))
        hit = _wt_hit_test(iomap.geometry, x, y)
        op = hit[1] === :cell ? _read_cell_mark_dwell(iomap.input, hit[2], hit[3], event) : nothing
        op === nothing || return op
    end
    _positioned_event(event) && return _wt_route_to_cell_under(p, iomap, event)
    _wt_route_to_selected_cell(iomap, event)
end

# A press of another button than the left, a button down, a button up or a dwell
# goes to the cell under it, a header as well as a body cell, in the coordinates of
# the cell, and its answer is re-rooted under the cell. For a dwell and a right
# click the table then reads its own stretch (`read_container_gesture`).
function _wt_route_to_cell_under(p::WidgetTableToGraphicsCanvas, iomap::WidgetTableToGraphicsCanvasIoMap, event)
    found = _wt_read_cell_under(p, iomap, event)
    found === nothing && return read_container_gesture(nothing, event, iomap.input)
    read_container_gesture(found[1], event, iomap.input; steps = found[2])
end

# The answer of the cell under `event`, re-rooted under the cell, and the steps to
# the cell; `nothing` when the event reaches no cell.
function _wt_read_cell_under(p::WidgetTableToGraphicsCanvas,
                             iomap::WidgetTableToGraphicsCanvasIoMap, event)
    geom = iomap.geometry
    x, y = _wt_get_unscrolled_point(p, iomap, Int(event.x), Int(event.y))
    hit = _wt_hit_test(geom, x, y)
    reference = hit[1] === :cell ? _wt_cell_ref(iomap.input, hit[2], hit[3]) :
                hit[1] === :col  ? _wt_column_header_ref(hit[2]) :
                (hit[1] === :row && geom.has_row_headers) ?
                    ConcreteReference(FieldReferenceStep("row_headers"),
                                      ConcreteReference(RangeReferenceStep(hit[2] - 1, hit[2]),
                                                        EmptyReference())) :
                nothing
    reference === nothing && return nothing
    found = _wt_find_part_entry(iomap, reference)
    found === nothing && return nothing
    pane, i, steps, _ = found
    cell = _wt_find_part_cell(iomap, pane, i)
    cell === nothing && return nothing
    cim, left, top = cell
    local_event = _wt_translate_event(event, x - left, y - top)
    local_event === nothing && return nothing
    (reroot_operation(_wt_read_cell_event(cim, event, local_event), steps), steps)
end

_wt_translate_event(evt::MouseClick, x::Int, y::Int) =
    MouseClick(evt.button, x, y, evt.count, evt.modifiers; time = evt.time)
_wt_translate_event(evt::MouseDown, x::Int, y::Int) =
    MouseDown(evt.button, x, y, evt.modifiers; time = evt.time)
_wt_translate_event(evt::MouseUp, x::Int, y::Int) =
    MouseUp(evt.button, x, y, evt.modifiers; time = evt.time)
_wt_translate_event(evt::MouseDwell, x::Int, y::Int) =
    shift_event_position(evt, x - evt.x, y - evt.y)
_wt_translate_event(evt, x::Int, y::Int) = nothing

# The answer of the cell `cim` to `event` of the table, which the cell reads as
# `local_event` in its own frame. A dwell goes to the cell as to a child at its point
# (`read_child_event`), and a position in its answer goes back into the frame of the
# table.
function _wt_read_cell_event(cim, event, local_event)
    event isa MouseDwell || return read_intent(cim.projection, cim, local_event)
    shift_operation_position(read_child_event(cim, local_event),
                             event.x - local_event.x, event.y - local_event.y)
end

# The cell the selection is in reads the event, whether the whole cell is
# selected or a caret is inside it, and its answer is re-rooted under the cell.
# A selected row, column or table is in no cell, and the event goes to none.
function _wt_route_to_selected_cell(iomap::WidgetTableToGraphicsCanvasIoMap, event)
    geom = iomap.geometry
    selection = iomap.input.selection
    shape = _wt_selection_shape(iomap.input, selection, geom)
    (shape === nothing || shape[1] === :cell) || return nothing
    found = _wt_find_part_entry(iomap, selection)
    found === nothing && return nothing
    pane, i, steps, _ = found
    entries = pane.content_iomap.child_iomaps
    1 <= i <= length(entries) || return nothing
    cim = entries[i][3]
    cim === nothing && return nothing
    reroot_operation(read_intent(cim.projection, cim, event), steps)
end

# ── WidgetTree ──────────────────────────────────────────────────────────────

@projection UntrackedCell struct WidgetTreeToGraphicsCanvas
    measure::TextMeasure
    margin::Inset
    border::Inset
    padding::Inset
    margin_color::StyleColor
    border_color::StyleColor
    padding_color::StyleColor
    content_color::StyleColor
    label_text::StyleText         # node labels
    icon_text::StyleText          # node icon glyphs (own column)
    chevron_color::StyleColor                    # the mark that expands a node
    row_selected_color::StyleColor               # the band of the selected row
    layer_hovered_color::StyleColor              # over a hovered row, behind the band
    indent::Int                   # per-depth horizontal step
    chevron_column::Int           # width reserved for the expand chevron
    icon_column::Int              # width reserved for the icon glyph
    row_padding::Int              # vertical padding per row
    chevron_size::Int
    row_radius::Int               # corner radius of the hover and the selection band
    label_gap::Int                # between an icon column widened for a glyph and its label
    icon_size::Float64           # times the box of a named icon, one line of the label
end

WidgetTreeToGraphicsCanvas(theme; graphics_theme = nothing, measure,
                           margin = inset_default, border = inset_default, padding = inset_default,
                           margin_color = color_transparent, border_color = color_transparent,
                           padding_color = color_transparent, content_color = color_transparent,
                           label_text = _themed(StyleText, theme, _get_body_text),
                           icon_text = _themed(StyleText, theme, t -> StyleText(t.font, t.muted_foreground)),
                           chevron_color = _themed(StyleColor, theme, t -> t.muted_foreground),
                           row_selected_color = _make_selected_row_color(graphics_theme),
                           layer_hovered_color = _themed(StyleColor, theme, _get_hover_layer),
                           indent = _themed(Int, theme, t -> t.indent),
                           chevron_column = _themed(Int, theme, t -> t.tree_chevron_column),
                           icon_column = _themed(Int, theme, t -> t.tree_icon_column),
                           row_padding = _themed(Int, theme, t -> t.item_gap),
                           chevron_size = _themed(Int, theme, t -> t.chevron),
                           row_radius = _themed(Int, theme, t -> t.radius_small),
                           label_gap = _themed(Int, theme, t -> t.label_gap),
                           icon_size = _themed(Float64, theme, t -> t.icon_size)) =
    WidgetTreeToGraphicsCanvas(measure, margin, border, padding, margin_color, border_color, padding_color,
                               content_color, label_text, icon_text, chevron_color, row_selected_color,
                               layer_hovered_color, indent, chevron_column, icon_column, row_padding, chevron_size,
                               row_radius, label_gap, icon_size)

# A node is a WidgetTreeNode (icon + label + children) or a leaf label (String).
# A leaf reports an empty icon.
_tree_icon(node)  = node isa WidgetTreeNode ? node.icon : ""
_tree_label(node) = node isa WidgetTreeNode ? string(node.label) : string(node)
# The children of a `WidgetTreeNode` are not read here: the caller reads them,
# and the tree reads them only for a drawn row and for an open node.
_tree_children(node) = node isa WidgetTreeNode ? node.children : nothing

# One row of the open tree, placed by arithmetic alone. `path` is the 1-based
# index chain from the roots down to the node (`[i]`, `[i, j]`, …), `depth` its
# level, and `y0`/`height` its band in content-local coordinates.
# `chevron_x0`/`chevron_x1` are the horizontal hit-box of its chevron, so the
# reader can tell a toggle from a select. A row holds no node: the node, and with
# it the label, the icon and whether the row has children, is read when the row
# is drawn.
struct WTreeRow
    path::Vector{Int}
    depth::Int
    chevron_x0::Int
    chevron_x1::Int
    y0::Int
    height::Int
end

# The rows of the open tree in order, the index of each path, the height of one
# row and of all of them. Every row is as high as the others, so the row under a
# point is arithmetic. Persisted on the iomap so the reader can hit-test clicks
# and resolve keyboard navigation.
struct WTreeGeometry
    rows::Vector{WTreeRow}
    index::Dict{Vector{Int},Int}
    row_height::Int
    total_h::Int
end

@iomap struct WidgetTreeToGraphicsCanvasIoMap
    projection::Any
    input::Any
    output::Any
    geometry::Cell
    width::Cell
end

# ── Node-path ⇄ WidgetTree reference ─────────────────────────────────────────
# A node at path `[i, j, k]` is addressed `roots[i].children[j].children[k]`
# (a `FieldReferenceStep` + element `RangeReferenceStep` per level), mirroring how the
# table addresses `cells[r][c]`. These are the single source of truth shared by
# the selection band, the click reader, and the FileSystemToWidget mappers.

function _wtree_path_ref(path::Vector{Int}, k::Int=1)
    isempty(path) && return EmptyReference()
    field = k == 1 ? "roots" : "children"
    idx = path[k]
    tail = k == length(path) ? EmptyReference() : _wtree_path_ref(path, k + 1)
    ConcreteReference(FieldReferenceStep(field),
        ConcreteReference(RangeReferenceStep(idx - 1, idx), tail))
end

function _wtree_ref_path(reference)
    cur = reference
    path = Int[]
    first = true
    while cur isa ConcreteReference
        h = cur.head
        (h isa FieldReferenceStep && h.name == (first ? "roots" : "children")) || return nothing
        t = cur.tail
        (t isa ConcreteReference && t.head isa RangeReferenceStep && is_element_reference_step(t.head)) || return nothing
        push!(path, t.head.start + 1)
        cur = t.tail
        cur isa EmptyReference && return path
        first = false
    end
    isempty(path) ? nothing : path
end

function print_document(p::WidgetTreeToGraphicsCanvas, recursion, w::WidgetTree, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    position = w.position::Point2D
    indent = p.indent
    chevron_column = p.chevron_column
    icon_column = p.icon_column
    chevron_size = p.chevron_size
    pad = p.row_padding
    box = _get_box_insets(p, w)
    colors = _get_box_colors(p, w)
    inset_width, inset_height = _inset_total(p, w)
    content_x, content_y = _content_offset(p, w)
    label_style = _get_state_text(p, w, :label)
    icon_style = _get_state_text(p, w, :icon)
    chevron_color = _get_state_color(p, w, :chevron)
    row_selected_color = _get_state_color(p, w, :row; state = :selected)
    _, line_height = _text_size(p.measure, label_style.font, "M")
    icon_size = scale_length(line_height, p.icon_size)
    avail_w = ctx === nothing ? nothing : get_exact_width(ctx)

    # A named icon is a square of one line times `icon_size`. A tree whose roots
    # show one reserves a column that holds it and a gap, and rows as tall as the
    # larger of the icon and a line; a tree of plain labels keeps the column of its
    # theme and rows of one line. The roots decide, because a row below them is read
    # only when it is drawn, and every row takes the same column and height.
    shows_icons = Cell(@computation any(node -> _tree_icon(node) isa Symbol, w.roots))
    column = Cell(@computation shows_icons[] ? max(icon_column, icon_size + p.label_gap) : icon_column)
    line_box = Cell(@computation shows_icons[] ? max(line_height, icon_size) : line_height)

    # The rows of the open tree. The walk reads the children of an open node and
    # nothing of a closed one: a closed row is a path, and its node is read when
    # the renderer draws the row. Reading `w.expanded` here ties the rows to the
    # open nodes, so a chevron toggle walks again. Rows stay content-local; the
    # content offset is added where they are drawn and where a reader turns a
    # position into a row.
    geometry = Cell(@computation begin
        expanded = w.expanded
        row_height = line_box[] + 2 * pad
        rows = WTreeRow[]
        index = Dict{Vector{Int},Int}()
        function visit(path, depth, node)
            x = depth * indent
            push!(rows, WTreeRow(path, depth, x, x + chevron_column, length(rows) * row_height, row_height))
            index[path] = length(rows)
            node === nothing && return
            kids = _tree_children(node)
            kids === nothing && return
            for i in 1:length(kids)
                child = vcat(path, i)
                visit(child, depth + 1, child in expanded ? kids[i] : nothing)
            end
        end
        roots = w.roots
        for i in 1:length(roots)
            visit([i], 0, [i] in expanded ? roots[i] : nothing)
        end
        WTreeGeometry(rows, index, row_height, length(rows) * row_height)
    end)

    # The tree takes the width that its parent offers, and what holds the tree
    # clips a longer label. With no offer the tree is as wide as its widest row,
    # which reads the node of every row of the open tree.
    width = Cell(@computation begin
        avail_w === nothing || return max(1, Int(avail_w[]) - inset_width)
        widest = 1
        for row in geometry[].rows
            label_width, _ = _text_size(p.measure, label_style.font,
                                        _tree_label(_wtree_node_at(w, row.path)))
            widest = max(widest, row.depth * indent + chevron_column + column[] + label_width)
        end
        widest
    end)

    # The band of a row: as wide as the tree, and as high as the row while `read`
    # answers the path of the row. A band reads the selection or the pointer in a
    # cell of its own, so a selection move redraws two bands and no label.
    function make_band(row::WTreeRow, color, read)
        band = GraphicsRect(0, 0, 0, 0; color = color, radius = p.row_radius)
        set_cell_computation!(getfield(band, :w), () -> Int32(width[]))
        set_cell_computation!(getfield(band, :h),
                              () -> Int32(_wtree_ref_path(read()) == row.path ? row.height : 0))
        band
    end

    # The top of the row of `path` in the open tree, or 0 once the path is not in it.
    function get_row_top(path)
        g = geometry[]
        i = get(g.index, path, nothing)
        i === nothing ? Int32(0) : Int32(g.rows[i].y0)
    end

    # The canvas of each row that was drawn, kept by the path of the row. A toggle
    # computes the rows again, and a row that stays keeps its canvas: the top of
    # the canvas reads where its path is now. So a partial repaint paints a row
    # that moved at its old and its new place, and no row that kept its place. The
    # rows of the open tree are the keys of the list, and a path that leaves the
    # open tree leaves the cache.
    kept_rows = Dict{Vector{Int},GraphicsCanvas}()
    make_row(row::WTreeRow) = get!(() -> make_row_canvas(row), kept_rows, row.path)
    function get_open_rows()
        g = geometry[]
        filter!(entry -> haskey(g.index, entry.first), kept_rows)
        g.rows
    end

    # One row: a canvas at the place of the row, whose content the renderer reads
    # only when it draws the row. The content reads the node, and whether the node
    # has children, which for a folder is one read of its listing. The chevron
    # reads whether the row is open in a cell of its own, so a toggle changes the
    # glyph of a chevron and not the content of a row.
    function make_row_canvas(row::WTreeRow)
        content = CellVector(Computation(function ()
            node = _wtree_node_at(w, row.path)
            result = Any[make_band(row, p.layer_hovered_color, () -> get_mouse_target(w)),
                         make_band(row, row_selected_color, () -> w.selection)]
            x = row.depth * indent
            if _wtree_has_children(node)
                _push_open_chevron!(result, x + chevron_column ÷ 2, row.height ÷ 2, chevron_size,
                                    chevron_color, () -> row.path in w.expanded)
            end
            icon = _tree_icon(node)
            text_y = pad + (line_box[] - line_height) ÷ 2
            if icon isa Symbol
                # A registered icon name: a glyph, tinted to the icon color.
                _push_icon!(result, icon, x + chevron_column, pad + (line_box[] - icon_size) ÷ 2, icon_size,
                            icon_style.color)
            elseif icon isa AbstractString && !isempty(icon)
                # A literal glyph string (e.g. an emoji), drawn as text.
                _push_text!(result, p.measure, icon_style.font, icon, x + chevron_column, text_y,
                            icon_style.color)
            end
            _push_text!(result, p.measure, label_style.font, _tree_label(node),
                        x + chevron_column + column[], text_y, label_style.color)
            result
        end))
        GraphicsCanvas(Cell(Int32(0)), Cell(@computation get_row_top(row.path)),
                       Cell(@computation Int32(width[])),
                       Cell(Int32(row.height)), content, layout_none, true, Cell(nothing))
    end

    # The rows lie along the vertical axis without overlap, so the renderer draws
    # the rows between the edges of its clip, and a query of the size takes the
    # declared box and reads no row. The canvas of a row is made at its first
    # read, so a toggle makes the rows that the renderer reaches and no others.
    rows_canvas = GraphicsCanvas(Cell(Int32(content_x)), Cell(Int32(content_y)),
                                 Cell(@computation Int32(width[])),
                                 Cell(@computation Int32(geometry[].total_h)),
                                 CellVector(@computation(get_open_rows()); element = make_row),
                                 layout_vertical, false, Cell(nothing))

    # Whole-canvas transparent hit target. The tree hit-tests by *row band* (a whole
    # row is clickable/hoverable, not just its glyphs), but a parent container gates
    # routing on `hit_element_at`, which only fires over an actual element — so a tree
    # nested in a layout/tab would ignore clicks/hover on the empty part of a row.
    # A full-size (invisible) rect makes the whole canvas a hit target, matching the
    # top-level tree.
    hit_target = GraphicsRect(0, 0, 0, 0; color = color_transparent, radius = 0)
    set_cell_computation!(getfield(hit_target, :w), () -> Int32(width[] + inset_width))
    set_cell_computation!(getfield(hit_target, :h), () -> Int32(geometry[].total_h + inset_height))

    elements = CellVector(@computation begin
        # The hit target behind everything, then the box: margin, border, padding
        # and content, from the outside in (transparent and zero-width by default),
        # then the rows.
        result = Any[hit_target]
        _push_box_parts!(result, box, colors, width[], geometry[].total_h)
        push!(result, rows_canvas)
        result
    end)

    canvas = GraphicsCanvas(Cell(Int32(_origin(position)[1])), Cell(Int32(_origin(position)[2])),
                            Cell(@computation Int32(width[] + inset_width)),
                            Cell(@computation Int32(geometry[].total_h + inset_height)),
                            elements, layout_none, true, Cell(nothing))
    WidgetTreeToGraphicsCanvasIoMap(p, w, canvas, geometry, width)
end

# A row of the tree is a canvas of its own in the canvas of the rows, the last of
# the tree's elements; a node maps to its row by its index in the open tree. A node
# under a closed one has no row, and so no image.
function map_reference_forward(::WidgetTreeToGraphicsCanvas, iomap::WidgetTreeToGraphicsCanvasIoMap, reference)
    reference isa Reference || return nothing
    reference = strip_reference_types(reference)
    reference isa ConcreteReference || return _map_self_forward(reference)
    path = _wtree_ref_path(reference)
    path === nothing && return nothing
    row = get(unwrap_cell(iomap.geometry).index, path, nothing)
    row === nothing && return nothing
    last = length(unwrap_cell(getfield(unwrap_cell(iomap.output), :elements)))
    ConcreteReference(FieldReferenceStep("elements"), ConcreteReference(RangeReferenceStep(last - 1, last),
        ConcreteReference(FieldReferenceStep("elements"),
            ConcreteReference(RangeReferenceStep(row - 1, row), EmptyReference()))))
end

map_reference_forward(::WidgetTreeToGraphicsCanvas, iomap, reference) = _map_child_forward(iomap, reference)
# A point on a row maps to its node, the reference that a click there selects.
function map_reference_backward(p::WidgetTreeToGraphicsCanvas, iomap, reference)
    point = find_reference_point(reference)
    (point === nothing || !(iomap isa WidgetTreeToGraphicsCanvasIoMap)) && return nothing
    _is_point_on_canvas(iomap.output, point) || return nothing
    row = _find_wtree_row_at(p, iomap, point.y)
    row === nothing ? nothing : _wtree_path_ref(row.path)
end

# The row of the tree at `y` of its canvas, or `nothing`.
_find_wtree_row_at(p::WidgetTreeToGraphicsCanvas, iomap::WidgetTreeToGraphicsCanvasIoMap, y::Int) =
    _wtree_row_at(iomap.geometry, y - _content_offset(p, iomap.input)[2])

# Gesture reader: a left click on a parent's chevron opens or closes it, otherwise
# selects the node under the cursor; ↑/↓ walk the flattened rows. Handled in the
# 3-arg form (like the other widgets) so a container routing an event into the tree via
# `read_intent(cim.projection, cim, evt)` reaches it — the default 4-arg
# `read_intent` bridges the editor's top-level `Intent` to this. Non-gestures
# return nothing: the tree is a leaf (no child ops bubble up to re-target).
#
# Per-instance gestures are consulted first — tree-level, then per-node — so a
# binding can add / override (shadow) / suppress; the built-in select / collapse /
# nav below is the fallback.
function read_intent(p::WidgetTreeToGraphicsCanvas, iomap::WidgetTreeToGraphicsCanvasIoMap, evt)
    _outside_widget(iomap, evt) && return nothing
    w = iomap.input
    op = read_bound_gesture(w, evt)
    op === nothing || return op
    nop = _wtree_node_gesture(p, iomap, evt)
    nop === nothing || return nop
    if evt isa MouseClick && evt.button === :left
        return _wtree_mouse_press(p, iomap, evt)
    elseif evt isa KeyDown
        return _wtree_key_navigate(iomap, evt)
    end
    return nothing
end

# Resolve the node at 1-based path `[i, j, …]`, mirroring the printer's flatten
# walk (`roots[i]`, then `children[j]`, …). Returns `nothing` for an out-of-range
# path or a leaf that has no such child level.
function _wtree_node_at(w::WidgetTree, path::Vector{Int})
    isempty(path) && return nothing
    coll = w.roots
    node = nothing
    for (level, i) in enumerate(path)
        (coll !== nothing && 1 <= i <= length(coll)) || return nothing
        node = coll[i]
        level < length(path) && (coll = _tree_children(node))
    end
    return node
end

# Whether `node` has children. For a node whose children are computed, this reads
# them: a folder reads its listing.
function _wtree_has_children(node)
    kids = _tree_children(node)
    kids !== nothing && !isempty(kids)
end

# The row under the content-local `y`, clamped into the rows, or `nothing` when
# the tree has no rows. Every row is as high as the others, so this is arithmetic.
function _wtree_row_at(geom::WTreeGeometry, y::Int)
    isempty(geom.rows) && return nothing
    geom.rows[clamp(fld(y, geom.row_height) + 1, 1, length(geom.rows))]
end

# Per-node gesture consult: find the node targeted by `g` — the row under the
# pointer for a `MouseClick` (any button/modifier; the binding's own pattern does
# the matching), or the currently selected node for a `KeyDown` — and fire its
# `get_instance_gesture_bindings` against the enclosing tree's selection. A node has no
# `selection` of its own, hence the explicit-selection `read_bound_gesture`. The
# margin, the border and the padding belong to the tree, so a press there is
# clamped into the rows.
function _wtree_node_gesture(p::WidgetTreeToGraphicsCanvas, iomap::WidgetTreeToGraphicsCanvasIoMap, g)
    w = iomap.input
    geom = iomap.geometry
    path = nothing
    if g isa MouseClick
        _, content_y = _content_offset(p, w)
        row = _wtree_row_at(geom, g.y - content_y)
        row === nothing || (path = row.path)
    elseif g isa KeyDown
        path = _wtree_ref_path(w.selection)
    end
    path === nothing && return nothing
    node = _wtree_node_at(w, path)
    node === nothing && return nothing
    return read_bound_gesture(node, g, w.selection)
end

# A left click on the chevron of a row with children opens or closes it; anywhere
# else on a row selects it. A press on the margin, the border or the padding is
# clamped into the rows.
function _wtree_mouse_press(p::WidgetTreeToGraphicsCanvas, iomap::WidgetTreeToGraphicsCanvasIoMap, g::MouseClick)
    w = iomap.input
    content_x, _ = _content_offset(p, w)
    row = _find_wtree_row_at(p, iomap, g.y)
    row === nothing && return nothing
    x = clamp(g.x - content_x, 0, max(0, iomap.width - 1))
    if row.chevron_x0 <= x < row.chevron_x1 && _wtree_has_children(_wtree_node_at(w, row.path))
        return _wtree_toggle_expanded(iomap, row.path)
    end
    ReplaceSelectionOperation(_wtree_path_ref(row.path))
end

# Toggle `path`'s membership in the tree's set of open nodes. Stores a *new* Set
# so the backing cell invalidates and the geometry thunk re-flattens. An open or
# a closed row is view state, so a history does not record it.
function _wtree_toggle_expanded(iomap::WidgetTreeToGraphicsCanvasIoMap, path::Vector{Int})
    w = iomap.input
    next = copy(w.expanded)
    path in next ? delete!(next, path) : push!(next, path)
    _write_view_state(w, "expanded", next)
end

function _wtree_key_navigate(iomap::WidgetTreeToGraphicsCanvasIoMap, g::KeyDown)
    g.key in (:up, :down) || return nothing
    geom = iomap.geometry
    isempty(geom.rows) && return nothing
    cur = _wtree_ref_path(iomap.input.selection)
    idx = cur === nothing ? 0 : get(geom.index, cur, 0)
    ni = g.key === :down ? (idx == 0 ? 1 : min(length(geom.rows), idx + 1)) :
                           (idx <= 1 ? 1 : idx - 1)
    ReplaceSelectionOperation(_wtree_path_ref(geom.rows[ni].path))
end

# ── Factory ────────────────────────────────────────────────────────────────


"""
    WidgetToGraphics(; measure, theme = WidgetTheme(), graphics_theme = nothing)
    WidgetToGraphics(font; measure, theme = make_widget_theme(font = font),
                     graphics_theme = nothing)

Build a recursive type-dispatching projection that maps any `WidgetDocument`
subtree to a `GraphicsCanvas`. `measure` ([`TextMeasure`](@ref)) is used for all
text sizing. `theme` is a [`WidgetTheme`](@ref) and `graphics_theme` a
[`GraphicsTheme`](@ref), each scaled or not; `nothing` takes the default graphics
theme. Every widget printer holds the styles that it reads from them, and none
holds a theme. A builder of an editor passes the scaled themes of its
`Appearance`, so every widget of the editor follows its scales; an interface with
no scales passes a theme as it is. A projection built on its own can name the
font of its default theme, the slate light preset.
"""
WidgetToGraphics(font::StyleFont; measure::TextMeasure,
                 theme = make_widget_theme(font = font), graphics_theme = nothing) =
    WidgetToGraphics(; measure, theme, graphics_theme)

function WidgetToGraphics(; measure::TextMeasure, theme = WidgetTheme(), graphics_theme = nothing)
    widgets = TypeDispatchingProjection(
        WidgetInsertion  => WidgetInsertionToGraphicsCanvas(theme; measure = measure),
        WidgetLabel      => WidgetLabelToGraphicsCanvas(theme; measure = measure),
        WidgetText       => WidgetTextToGraphicsCanvas(theme; graphics_theme, measure = measure),
        WidgetCheckbox   => WidgetCheckboxToGraphicsCanvas(theme; measure = measure),
        WidgetButton     => WidgetButtonToGraphicsCanvas(theme; measure = measure),
        WidgetTooltip    => WidgetTooltipToGraphicsCanvas(theme; measure = measure),
        WidgetContextMenu => WidgetContextMenuToGraphicsCanvas(theme; measure = measure),
        WidgetDialog     => WidgetDialogToGraphicsCanvas(theme; measure = measure),
        WidgetMenu       => WidgetMenuToGraphicsCanvas(theme; measure = measure),
        WidgetMenuItem   => WidgetMenuItemToGraphicsCanvas(theme; measure = measure),
        WidgetToolbarItem => WidgetToolbarItemToGraphicsCanvas(theme; measure = measure),
        WidgetComposite  => WidgetCompositeToGraphicsCanvas(theme; graphics_theme),
        WidgetShell      => WidgetShellToGraphicsCanvas(theme; measure = measure),
        WidgetTitlePane  => WidgetTitlePaneToGraphicsCanvas(theme; measure = measure),
        WidgetSplitPane  => WidgetSplitPaneToGraphicsCanvas(theme),
        WidgetTabbedPane => WidgetTabbedPaneToGraphicsCanvas(theme; graphics_theme, measure = measure),
        WidgetScrollPane => WidgetScrollPaneToGraphicsCanvas(theme; measure = measure),
        WidgetTransformPane => WidgetTransformPaneToGraphicsCanvas(theme; measure = measure),
        WidgetToolbar    => WidgetToolbarToGraphicsCanvas(theme; measure = measure),
        WidgetStatusBar  => WidgetStatusBarToGraphicsCanvas(theme; measure = measure),
        WidgetScrollBar  => WidgetScrollBarToGraphicsCanvas(theme),
        WidgetBadge      => WidgetBadgeToGraphicsCanvas(theme; measure = measure),
        WidgetSeparator  => WidgetSeparatorToGraphicsCanvas(theme),
        WidgetCard       => WidgetCardToGraphicsCanvas(theme; graphics_theme, measure = measure),
        WidgetSwitch     => WidgetSwitchToGraphicsCanvas(theme; measure = measure),
        WidgetProgressBar => WidgetProgressBarToGraphicsCanvas(theme),
        WidgetProgressRing => WidgetProgressRingToGraphicsCanvas(theme; measure = measure),
        WidgetSlider     => WidgetSliderToGraphicsCanvas(theme),
        WidgetRadioGroup => WidgetRadioGroupToGraphicsCanvas(theme; measure = measure),
        WidgetAvatar     => WidgetAvatarToGraphicsCanvas(theme; measure = measure),
        WidgetAlert      => WidgetAlertToGraphicsCanvas(theme; measure = measure),
        WidgetSkeleton   => WidgetSkeletonToGraphicsCanvas(theme),
        WidgetSwatch     => WidgetSwatchToGraphicsCanvas(theme),
        WidgetHighlight  => WidgetHighlightToGraphicsCanvas(theme),
        WidgetToggle      => WidgetToggleToGraphicsCanvas(theme; measure = measure),
        WidgetToggleGroup => WidgetToggleGroupToGraphicsCanvas(theme; measure = measure),
        WidgetSelect      => WidgetSelectToGraphicsCanvas(theme; measure = measure),
        WidgetSpinBox     => WidgetSpinBoxToGraphicsCanvas(theme; measure = measure),
        WidgetList        => WidgetListToGraphicsCanvas(theme; graphics_theme, measure = measure),
        WidgetOption      => WidgetOptionToGraphicsCanvas(theme; measure = measure),
        WidgetTextarea    => WidgetTextareaToGraphicsCanvas(theme; measure = measure),
        WidgetAccordion   => WidgetAccordionToGraphicsCanvas(theme; measure = measure),
        WidgetTable       => WidgetTableToGraphicsCanvas(theme; graphics_theme),
        WidgetTree        => WidgetTreeToGraphicsCanvas(theme; graphics_theme, measure = measure),
    )
    # Widgets embed layouts (a composite or a table holds a GridLayout), so the
    # recursion renders an embedded layout without an outer layout dispatcher.
    # A layout draws the ring around a child selected as a whole with the
    # graphics theme.
    TypeDispatchingProjection(vcat(widgets.dispatch,
        LayoutToGraphics(; theme = graphics_theme).dispatch))
end

# ── A route gives a child the point in its own frame ───────────────────────
#
# A container that a route passes moves the point of a pointer gesture into the
# frame of the child that the route reaches, and the positions of the answer
# back, as for a gesture that it gives to the child at the point. Most
# containers keep the place of each child in an `(x, y, child_iomap)` entry; a
# pane, a context menu and an accordion move the point as their own readers do.

const _PlacingWidgetProjection = Union{
    WidgetTooltipToGraphicsCanvas, WidgetMenuToGraphicsCanvas,
    WidgetCompositeToGraphicsCanvas, WidgetTitlePaneToGraphicsCanvas,
    WidgetSplitPaneToGraphicsCanvas, WidgetTabbedPaneToGraphicsCanvas,
    WidgetToolbarToGraphicsCanvas, WidgetCardToGraphicsCanvas,
    WidgetMenuItemToGraphicsCanvas}

ProjectionModule.read_child_by_route(::_PlacingWidgetProjection, recursion, change::Intent,
                                     iomap, child) =
    read_routed_entry_child(recursion, change, child;
                            entries = _get_route_entries(iomap.child_iomaps))

function ProjectionModule.read_child_by_route(::WidgetDialogToGraphicsCanvas, recursion,
                                              change::Intent,
                                              iomap::WidgetDialogToGraphicsCanvasIoMap, child)
    entries = Any[iomap.button_entries...]
    iomap.content_entry === nothing || pushfirst!(entries, iomap.content_entry)
    read_routed_entry_child(recursion, change, child; entries)
end

# The entries of a container, whether its IoMap holds them bare or in a cell.
_get_route_entries(entries::AbstractCell) = _get_route_entries(entries[])
_get_route_entries(entries) = entries

# A pane moves the point past its content origin and its scroll.
function ProjectionModule.read_child_by_route(p::WidgetScrollPaneToGraphicsCanvas, recursion,
                                              change::Intent,
                                              iomap::WidgetScrollPaneToGraphicsCanvasIoMap, child)
    child === iomap.content_iomap ||
        return read_routed_intent(get_iomap_projection(child), recursion, change, child)
    ox, oy = _find_scroll_pane_local_point(p, iomap, 0, 0)
    read_routed_child_in_frame(recursion, change, child;
                               move_in = (x, y) -> (x + ox, y + oy),
                               move_out = (x, y) -> (x - ox, y - oy))
end

# A transform pane moves the point through the inverse of its transform.
function ProjectionModule.read_child_by_route(p::WidgetTransformPaneToGraphicsCanvas, recursion,
                                              change::Intent,
                                              iomap::WidgetTransformPaneToGraphicsCanvasIoMap,
                                              child)
    child === iomap.content_iomap ||
        return read_routed_intent(get_iomap_projection(child), recursion, change, child)
    M = getfield(iomap.input, :transform)[]::AffineTransform
    cox, coy = _content_offset(p, iomap.input)
    move_out(x, y) = begin
        px, py = apply_affine_transform(M, Float64(x), Float64(y))
        (round(Int, px) + cox, round(Int, py) + coy)
    end
    read_routed_child_in_frame(recursion, change, child;
                               move_in = (x, y) -> _find_transform_pane_local_point(p, iomap, x, y),
                               move_out)
end

function ProjectionModule.read_child_by_route(p::WidgetContextMenuToGraphicsCanvas, recursion,
                                              change::Intent,
                                              iomap::WidgetContextMenuToGraphicsCanvasIoMap, child)
    child === iomap.child_iomap ||
        return read_routed_intent(get_iomap_projection(child), recursion, change, child)
    dx, dy = _get_context_menu_child_offset(p, iomap)
    read_routed_child_in_frame(recursion, change, child;
                               move_in = (x, y) -> (x - dx, y - dy),
                               move_out = (x, y) -> (x + dx, y + dy))
end

function ProjectionModule.read_child_by_route(::WidgetAccordionToGraphicsCanvas, recursion,
                                              change::Intent,
                                              iomap::WidgetAccordionToGraphicsCanvasIoMap, child)
    entry = iomap.body_entry
    (entry !== nothing && last(entry) === child) ||
        return read_routed_intent(get_iomap_projection(child), recursion, change, child)
    dx, dy = _get_accordion_body_offset(iomap, entry)
    read_routed_child_in_frame(recursion, change, child;
                               move_in = (x, y) -> (x - dx, y - dy),
                               move_out = (x, y) -> (x + dx, y + dy))
end
