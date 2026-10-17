# Fragment of `WidgetModule` — the widget parts of the decoration of a document:
# the icon with its tint and its corner marks, the pills of its counts, and the
# drawing of a decorated icon, which a row of a tree and a tab share, so the same
# state looks the same at each place.

"""
    make_decoration_icon(decoration; icon = decoration.icon) -> WidgetIcon, Symbol or nothing

The icon of `decoration` with its tint and its corner marks: the tint is the role
that [`find_decoration_tint`](@ref) answers, and each corner holds the condition
that [`collect_decoration_marks`](@ref) puts there, as its count when it has one,
else as its glyph. `icon` names the glyph, by default the icon of the decoration.
The plain name of the glyph when there is no tint and no mark, and `nothing`
when there is no glyph.

Use it to draw the state of a document on its icon, wherever the document is
named.

# Example

    make_decoration_icon(DocumentDecoration(; icon = :file, conditions = [DocumentCondition(:unsaved)]))

See also `make_decoration_badges` and `WidgetIcon`.
"""
function make_decoration_icon end

function make_decoration_icon(decoration::DocumentDecoration; icon = decoration.icon)
    icon isa Symbol || return nothing
    marks = collect_decoration_marks(decoration)
    tint = find_decoration_tint(decoration)
    tint === nothing && all(isnothing, (marks.top_left, marks.top_right, marks.bottom_left, marks.bottom_right)) &&
        return icon
    make_mark(corner) = corner === nothing ? nothing :
        WidgetIconMark(something(corner.count, corner.glyph); role = corner.role)
    WidgetIcon(icon; role = tint,
               top_left = make_mark(marks.top_left), top_right = make_mark(marks.top_right),
               bottom_left = make_mark(marks.bottom_left), bottom_right = make_mark(marks.bottom_right))
end

"""
    make_decoration_badges(decoration) -> Vector{Any}

What a place draws after the name of a document: a small `WidgetIcon` for each
fact of its kind that shows after the name, then a `WidgetBadge` pill for each of
its counts, in the role of the count, or quiet with no role.

Use it to give a row or a tab the counts of a document.

# Example

    make_decoration_badges(DocumentDecoration(; counts = [DocumentCount("2/4"; role = :accent)]))

See also `make_decoration_icon`.
"""
function make_decoration_badges end

function make_decoration_badges(decoration::DocumentDecoration)
    parts = Any[WidgetIcon(fact.glyph; role = fact.role) for fact in collect_decoration_marks(decoration).after_name]
    for count in decoration.counts
        push!(parts, WidgetBadge(count.text; role = count.role, variant = count.role === nothing ? :secondary : :default))
    end
    parts
end

# The width of an icon with its decoration: the width of its glyph. The marks
# stand half outside its box.
icon_width(icon::WidgetIcon, size::Int) = icon_width(icon.name, size)

# The text color of `role` in the badge printer `badge`, else `color`.
_get_role_text_color(badge, role, color) =
    role in _BADGE_ROLES ? getproperty(badge, Symbol(role, "_label_text")).color : color

# Draw `icon` at `x`, `y` in a box of `size`: a plain name as its glyph in `color`,
# and a `WidgetIcon` as its glyph in the text color of its role, with each corner
# mark. `background` is the color behind the icon, which the disc under a mark
# takes, so a mark stays readable over the glyph. Answers whether it drew a glyph.
function _push_decorated_icon!(elements::Vector, badge, icon, x::Int, y::Int, size::Int, color::StyleColor,
                               background::StyleColor)
    icon isa WidgetIcon || return _push_icon!(elements, icon, x, y, size, color)
    tint = icon.role === nothing ? color : _get_role_text_color(badge, icon.role, color)
    _push_icon!(elements, icon.name, x, y, size, tint) || return false
    for (corner, mark) in ((:top_left, icon.top_left), (:top_right, icon.top_right),
                           (:bottom_left, icon.bottom_left), (:bottom_right, icon.bottom_right))
        mark === nothing || _push_icon_mark!(elements, badge, mark, corner, x, y, size, tint, background)
    end
    true
end

# The share of the size of an icon that a corner mark takes, and the share that
# the text of a count takes.
const _ICON_MARK_SHARE = 0.5
const _ICON_COUNT_SHARE = 0.6

# One corner mark of an icon at `x`, `y` of `size`, centered on the corner of its
# box, so the middle of the glyph stays clear: a glyph on a disc of `background`,
# a count on a pill of the surface of its role, or, for `:dot`, a filled disc in
# the color of the mark, which reads at any size where the glyph of a dot does not.
function _push_icon_mark!(elements::Vector, badge, mark::WidgetIconMark, corner::Symbol, x::Int, y::Int,
                          size::Int, color::StyleColor, background::StyleColor)
    side = max(5, round(Int, size * _ICON_MARK_SHARE))
    center_x = corner in (:top_left, :bottom_left) ? x : x + size
    center_y = corner in (:top_left, :top_right) ? y : y + size
    role = mark.role
    mark_color = role === nothing ? color : _get_role_text_color(badge, role, color)
    content = mark.content
    if content isa Integer
        text = content > 99 ? "99+" : string(content)
        font = with_font_size(badge.label_text.font, max(8, round(Int, size * _ICON_COUNT_SHARE)))
        text_width, text_height = _text_size(badge.measure, font, text)
        height = text_height + 2
        width = max(height, text_width + 4)
        surface = role in _BADGE_ROLES ? getproperty(badge, Symbol(role, "_surface_color")) : background
        left, top = center_x - width ÷ 2, center_y - height ÷ 2
        push!(elements, GraphicsRect(left, top, width, height; color = surface, radius = height ÷ 2))
        _push_text!(elements, badge.measure, font, text, left + (width - text_width) ÷ 2, top + 1, mark_color)
    elseif content === :dot
        disc = max(4, round(Int, side * 0.7))
        push!(elements, GraphicsRect(center_x - (disc + 2) ÷ 2, center_y - (disc + 2) ÷ 2, disc + 2, disc + 2;
                                     color = background, radius = (disc + 2) ÷ 2))
        push!(elements, GraphicsRect(center_x - disc ÷ 2, center_y - disc ÷ 2, disc, disc;
                                     color = mark_color, radius = disc ÷ 2))
    else
        left, top = center_x - side ÷ 2, center_y - side ÷ 2
        push!(elements, GraphicsRect(left - 1, top - 1, side + 2, side + 2; color = background,
                                     radius = (side + 2) ÷ 2))
        _push_icon!(elements, content, left, top, side, mark_color)
    end
    nothing
end
