"""
    WidgetToGraphicsModule

WidgetDocument → GraphicsCanvas projection. One projection struct per widget
document type, composed via `TypeDispatchingProjection(...)` through the
`WidgetToGraphics()` factory function. Wrap the result in `RecursiveProjection`
at the call site to enable recursive child dispatch.

Each widget projection produces a `GraphicsCanvas` as output. Leaf widgets
emit text and rect elements; container widgets recurse via the `recursion`
argument and nest child canvases. Event routing (e.g. MouseScroll) is
delegated through containers to the appropriate child via hit-testing.

Also contains `WidgetScrollPaneToGraphicsViewport`, a composable projection
that converts a single `WidgetScrollPane` into a `GraphicsViewport`, delegating
the content projection via the recursion argument.
"""
module WidgetToGraphicsModule

import ..ReactiveModule: Cell
import ..ProjectionApiModule: projection_print, projection_read,
                               map_reference_forward, map_reference_backward, Projection
import ..DocumentApiModule: Document
import ..ColorModule: StyleColor,
                      color_white, color_zinc_50, color_zinc_100, color_zinc_200,
                      color_zinc_300, color_zinc_400, color_zinc_500, color_zinc_600,
                      color_zinc_700, color_zinc_800, color_zinc_900, color_zinc_950,
                      color_destructive, color_destructive_fg
import ..WidgetModule: WidgetDocument, WidgetLabel, WidgetText, WidgetCheckbox,
                       WidgetButton, WidgetTooltip, WidgetMenu, WidgetMenuItem,
                       WidgetComposite, WidgetShell, WidgetTitlePane, WidgetSplitPane,
                       WidgetTabbedPane, WidgetScrollPane, WidgetToolbar, WidgetScrollBar,
                       WidgetBadge, WidgetSeparator, WidgetCard, WidgetSwitch, WidgetProgress,
                       WidgetSlider, WidgetRadioGroup, WidgetAvatar, WidgetAlert, WidgetSkeleton,
                       WidgetToggle, WidgetToggleGroup, WidgetSelect, WidgetTextarea, WidgetAccordion,
                       WidgetTable, WidgetTree,
                       Inset, Point2D, inset_default,
                       ScrollWidgetOperation, SelectTabOperation, SetScrollBarValueOperation
import ..CollectionModule: CellVector, CollectionDocument
import ..GraphicsModule: GraphicsText, GraphicsRect, GraphicsLine, GraphicsCircle, GraphicsCanvas, GraphicsViewport, hit_element_at, layout_none
import ..FontModule: StyleFont, font_scaled_size,
                     font_ubuntu_regular_18, font_ubuntu_regular_24, font_ubuntu_bold_24
import ..IoMapModule: SimpleIoMap, ChildrenIoMap
import ..IoMapApiModule: IoMap
import ..MouseModule: MouseScroll, MousePress
import ..EventCaseModule: var"@event_case"
import ..OperationApiModule: Operation
import ..OperationModule: ReplaceSelectionOperation, ReplaceReferencedValue
import ..PrimitiveModule: StringReplaceRangeOperation, NumberReplaceRangeOperation
import ..ReferenceModule: ReferencePath, ConcreteReferencePath, FieldReference, RangeReference, EmptyReferencePath
import ..TypeDispatchingModule: TypeDispatchingProjection
import ..PrinterContextModule: child_context, with_available_size
import ..LayoutModule: LayoutConstraint, allocate_axis, layout_min, layout_max,
                       layout_preferred, layout_weight
export WidgetLabelToGraphicsCanvas, WidgetTextToGraphicsCanvas,
       WidgetCheckboxToGraphicsCanvas, WidgetButtonToGraphicsCanvas,
       WidgetTooltipToGraphicsCanvas, WidgetMenuToGraphicsCanvas,
       WidgetMenuItemToGraphicsCanvas, WidgetCompositeToGraphicsCanvas,
       WidgetShellToGraphicsCanvas, WidgetTitlePaneToGraphicsCanvas,
       WidgetSplitPaneToGraphicsCanvas, WidgetTabbedPaneToGraphicsCanvas,
       WidgetScrollPaneToGraphicsCanvas, WidgetScrollPaneToGraphicsCanvasIoMap,
       WidgetToolbarToGraphicsCanvas, WidgetScrollBarToGraphicsCanvas,
       WidgetToGraphics, WidgetTheme, widget_theme_light, widget_theme_dark,
       WidgetScrollPaneToGraphicsViewport, WidgetScrollPaneToGraphicsViewportIoMap

# ── Theme (design tokens) ─────────────────────────────────────────

"""
    WidgetTheme

Design tokens shared by every widget renderer — the single source of truth for
widget look & feel. Colors are `StyleColor`s; every spacing / sizing token is a
*logical* pixel value scaled by the font scale at render time via `_sc`, so a
widget renderer should never carry its own literal dimension. The fields fall
into four groups:

- **Palette** — `background … ring` plus `track_off` (the switch's off-track).
- **Type & base spacing** — `font*`, `radius`, `pad_x`, `pad_y`.
- **Generic layout** — `gap`, `row_gap`, `title_gap`, `border_width`, `stroke`,
  `tab_pad`, `seg_inset`.
- **Control & component dimensions** — checkbox / switch / slider / progress /
  radio / scrollbar sizes and the per-component paddings, indents and radii.
- **Box model** — `inset`, the themed default margin/border/padding (zero by
  default, so `inset_default` can be replaced by a theme without per-widget
  overrides).

Spacing tokens are palette-independent, so both presets share them via
[`_widget_theme`](@ref); only colors and fonts differ. See
[`widget_theme_light`](@ref) / [`widget_theme_dark`](@ref).
"""
struct WidgetTheme
    # ── Palette ──
    background::StyleColor
    foreground::StyleColor
    card::StyleColor
    card_foreground::StyleColor
    popover::StyleColor
    popover_foreground::StyleColor
    muted::StyleColor
    muted_foreground::StyleColor
    primary::StyleColor
    primary_foreground::StyleColor
    secondary::StyleColor
    secondary_foreground::StyleColor
    accent::StyleColor
    accent_foreground::StyleColor
    destructive::StyleColor
    destructive_foreground::StyleColor
    border::StyleColor
    input::StyleColor
    ring::StyleColor
    track_off::StyleColor   # switch off-track fill
    # ── Type & base spacing ──
    radius::Int
    font::StyleFont
    font_bold::StyleFont
    font_small::StyleFont
    pad_x::Int
    pad_y::Int
    # ── Generic layout ──
    gap::Int            # inter-item gap (toolbar items, shell bands)
    row_gap::Int        # vertical gap between stacked rows
    title_gap::Int      # gap below a title/header
    border_width::Int   # hairline: border / splitter / separator / table rules
    stroke::Int         # icon stroke (checkmark, chevron, radio ring, knob ring)
    tab_pad::Int        # tab inner padding (printer + hit-test)
    seg_inset::Int      # selected-segment inset (toggle group)
    # ── Control & component dimensions ──
    checkbox_size::Int
    switch_w::Int
    switch_h::Int
    switch_pad::Int
    progress_h::Int
    slider_h::Int
    track::Int          # slider track thickness
    knob_radius::Int
    radio_size::Int
    radio_gap::Int      # dot → label gap
    radio_dot::Int      # selected inner dot radius
    thumb_min::Int      # minimum scroll-bar thumb extent
    badge_pad_x::Int
    badge_pad_y::Int
    card_pad::Int
    card_gap::Int       # gap between card sections
    card_title_gap::Int # gap below the card title
    alert_pad::Int
    alert_gap::Int      # gap below the alert title
    table_pad_x::Int
    table_pad_y::Int
    tree_indent::Int
    tree_chevron::Int   # tree chevron column width
    tree_row_pad::Int   # tree row vertical padding
    chevron::Int        # chevron half-size
    skeleton_radius::Int
    shadow_offset::Int  # button drop-shadow y-offset
    accordion_pad_y::Int
    accordion_body_gap::Int
    # ── Box model ──
    inset::Inset        # themed default margin/border/padding
end

"""
    _widget_theme(; <palette colors>, font, font_bold, font_small) -> WidgetTheme

Build a theme from a color palette and fonts, filling in the palette-independent
spacing / sizing tokens with their shared defaults. Both presets funnel through
here so the geometry is defined in exactly one place; preserve the values when
editing — they match the original per-widget literals so rendering is stable.
"""
function _widget_theme(; background, foreground, card, card_foreground, popover,
                         popover_foreground, muted, muted_foreground, primary,
                         primary_foreground, secondary, secondary_foreground,
                         accent, accent_foreground, destructive, destructive_foreground,
                         border, input, ring, track_off,
                         font, font_bold, font_small)
    WidgetTheme(
        background, foreground, card, card_foreground, popover, popover_foreground,
        muted, muted_foreground, primary, primary_foreground, secondary, secondary_foreground,
        accent, accent_foreground, destructive, destructive_foreground, border, input, ring, track_off,
        # type & base spacing
        8, font, font_bold, font_small, 14, 9,
        # generic layout: gap row_gap title_gap border_width stroke tab_pad seg_inset
        4, 12, 6, 1, 2, 4, 2,
        # control sizes: checkbox switch_w switch_h switch_pad progress_h slider_h track knob radio radio_gap radio_dot thumb_min
        18, 44, 24, 3, 8, 24, 4, 9, 18, 10, 5, 8,
        # components: badge_x badge_y card_pad card_gap card_title_gap alert_pad alert_gap table_x table_y tree_indent tree_chevron tree_row_pad chevron skeleton_radius shadow_offset accordion_pad_y accordion_body_gap
        10, 3, 16, 10, 4, 14, 4, 12, 8, 22, 18, 4, 4, 6, 2, 10, 2,
        # box model
        inset_default)
end

"""
    widget_theme_light(; font=font_ubuntu_regular_24) -> WidgetTheme

The default light theme (a neutral zinc palette on a white background).
"""
function widget_theme_light(; font::StyleFont=font_ubuntu_regular_24)
    _widget_theme(
        background=color_white,       foreground=color_zinc_950,
        card=color_white,             card_foreground=color_zinc_950,
        popover=color_white,          popover_foreground=color_zinc_950,
        muted=color_zinc_100,         muted_foreground=color_zinc_500,
        primary=color_zinc_900,       primary_foreground=color_zinc_50,
        secondary=color_zinc_100,     secondary_foreground=color_zinc_900,
        accent=color_zinc_100,        accent_foreground=color_zinc_900,
        destructive=color_destructive, destructive_foreground=color_destructive_fg,
        border=color_zinc_200,        input=color_zinc_200,    ring=color_zinc_400,
        track_off=color_zinc_300,
        font=font, font_bold=font_ubuntu_bold_24, font_small=font_ubuntu_regular_18)
end

"""
    widget_theme_dark(; font=font_ubuntu_regular_24) -> WidgetTheme

The dark theme (zinc-950 surfaces). Ships alongside the light default; the
editor chrome can opt in.
"""
function widget_theme_dark(; font::StyleFont=font_ubuntu_regular_24)
    _widget_theme(
        background=color_zinc_950,    foreground=color_zinc_50,
        card=color_zinc_900,          card_foreground=color_zinc_50,
        popover=color_zinc_900,       popover_foreground=color_zinc_50,
        muted=color_zinc_800,         muted_foreground=color_zinc_400,
        primary=color_zinc_50,        primary_foreground=color_zinc_900,
        secondary=color_zinc_800,     secondary_foreground=color_zinc_50,
        accent=color_zinc_800,        accent_foreground=color_zinc_50,
        destructive=color_destructive, destructive_foreground=color_destructive_fg,
        border=color_zinc_800,        input=color_zinc_800,    ring=color_zinc_600,
        track_off=color_zinc_700,
        font=font, font_bold=font_ubuntu_bold_24, font_small=font_ubuntu_regular_18)
end

# ── Styling helpers ─────────────────────────────────────────────────────────

# Scale a logical pixel measurement by the current font scale, so spacing /
# radius track the text size on hi-dpi displays.
_sc(px::Integer) = font_scaled_size(px)

# A widget's authored `position` is in logical pixels, like insets — scale it at
# render time (NOT at document-construction time, which happens during
# precompilation when the font scale is still 1.0) so stacked widgets keep their
# spacing on hi-dpi displays.
_origin(pos::Point2D) = (_sc(Int(pos.x[])), _sc(Int(pos.y[])))

# (r,g,b,a) tuple of integers for a StyleColor, for GraphicsRect/Circle kwargs.
_rgbai(c::StyleColor) = (Int(round(c.red * 255)), Int(round(c.green * 255)),
                         Int(round(c.blue * 255)), Int(round(c.alpha * 255)))

# Push a themed rounded box (fill + optional outline) of size cw×ch at (x,y).
function _push_panel!(elems::Vector, x::Int, y::Int, cw::Int, ch::Int;
                      fill::StyleColor, border=nothing, border_w::Int=0, radius::Int=0)
    r, g, b, a = _rgbai(fill)
    if border !== nothing && border_w > 0
        push!(elems, GraphicsRect(x, y, cw, ch, r, g, b, a, radius;
                                  border_width=border_w, border_color=_rgbai(border)))
    else
        push!(elems, GraphicsRect(x, y, cw, ch, r, g, b, a, radius))
    end
end

# A simple themed text control (label/button/input/badge): a rounded box sized to
# the text plus padding, with the text aligned :left or :center. Returns the
# GraphicsCanvas positioned at `pos`.
function _styled_text_control(p, pos::Point2D, text::AbstractString;
                              fill::StyleColor, fg::StyleColor,
                              border=nothing, border_w::Int=0, radius::Int=0,
                              pad_x::Int=_sc(p.theme.pad_x), pad_y::Int=_sc(p.theme.pad_y),
                              align::Symbol=:left, min_w::Int=0, min_h::Int=0,
                              font::StyleFont=p.font)
    tw, th = _text_size(p.measure, font, text)
    cw = max(min_w, tw + 2pad_x)
    ch = max(min_h, th + 2pad_y)
    tx = align === :center ? (cw - tw) ÷ 2 : pad_x
    ty = (ch - th) ÷ 2
    elems = Any[]
    _push_panel!(elems, 0, 0, cw, ch; fill=fill, border=border, border_w=border_w, radius=radius)
    fr, fg2, fb, fa = _rgbai(fg)
    push!(elems, GraphicsText(text, tx, ty, font, fr, fg2, fb, fa))
    _make_canvas(_origin(pos)..., cw, ch, elems)
end

# Draw a themed rounded surface (fill + optional outline) covering a widget's
# full box (content size `cw×ch` plus its box-model insets), reusing the widget's
# geometry so print and reader stay in sync. The outline width is the document's
# left border (font-scaled); `border=nothing` or zero border → no outline.
function _push_box!(elems::Vector, w::WidgetDocument, cw::Int, ch::Int;
                    fill::StyleColor, border=nothing, radius::Int=0)
    tx, ty = _inset_total(w)
    bl = Int(w.border.left[])
    bw = (border !== nothing && bl > 0) ? _sc(bl) : 0
    _push_panel!(elems, 0, 0, cw + tx, ch + ty;
                 fill=fill, border=(bw > 0 ? border : nothing), border_w=bw, radius=radius)
end

# ── Projection structs ─────────────────────────────────────────────────────

struct WidgetLabelToGraphicsCanvas <: Projection
    font::StyleFont
    measure::Function
    theme::WidgetTheme
end

struct WidgetTextToGraphicsCanvas <: Projection
    font::StyleFont
    measure::Function
    theme::WidgetTheme
end

struct WidgetCheckboxToGraphicsCanvas <: Projection
    font::StyleFont
    measure::Function
    theme::WidgetTheme
end

struct WidgetButtonToGraphicsCanvas <: Projection
    font::StyleFont
    measure::Function
    theme::WidgetTheme
end

struct WidgetTooltipToGraphicsCanvas <: Projection
    font::StyleFont
    measure::Function
    theme::WidgetTheme
end

struct WidgetMenuToGraphicsCanvas <: Projection
    font::StyleFont
    measure::Function
    theme::WidgetTheme
end

struct WidgetMenuItemToGraphicsCanvas <: Projection
    font::StyleFont
    measure::Function
    theme::WidgetTheme
end

struct WidgetCompositeToGraphicsCanvas <: Projection end

struct WidgetShellToGraphicsCanvas <: Projection
    font::StyleFont
    measure::Function
    theme::WidgetTheme
end

struct WidgetTitlePaneToGraphicsCanvas <: Projection
    font::StyleFont
    measure::Function
    theme::WidgetTheme
end

struct WidgetSplitPaneToGraphicsCanvas <: Projection
    theme::WidgetTheme
end

struct WidgetTabbedPaneToGraphicsCanvas <: Projection
    font::StyleFont
    measure::Function
    theme::WidgetTheme
end

struct WidgetScrollPaneToGraphicsCanvas <: Projection
    font::StyleFont
    measure::Function
    theme::WidgetTheme
end

struct WidgetToolbarToGraphicsCanvas <: Projection
    font::StyleFont
    measure::Function
    theme::WidgetTheme
end

struct WidgetScrollBarToGraphicsCanvas <: Projection
    theme::WidgetTheme
end

# ── IoMap for WidgetScrollPane ─────────────────────────────────────────────

struct WidgetScrollPaneToGraphicsCanvasIoMap <: IoMap
    projection::Any
    input::WidgetScrollPane
    output::GraphicsCanvas
    content_iomap::Any
end

# ── Color helpers ──────────────────────────────────────────────────────────

_rgba(c::StyleColor) = (UInt8(round(c.red * 255)), UInt8(round(c.green * 255)), UInt8(round(c.blue * 255)), UInt8(round(c.alpha * 255)))

# ── Box model helpers ──────────────────────────────────────────────────────

# Box-model insets are authored in logical pixels; scale them by the font scale
# so padding/border track the (also-scaled) text size on hi-dpi displays. The
# reader uses the same offsets, so click mapping stays in sync.
"""
Return the (x, y) content-area offset from the widget's outer top-left corner,
i.e. margin + border + padding on each axis (font-scaled).
"""
function _content_offset(w::WidgetDocument)
    m   = w.margin::Inset
    brd = w.border::Inset
    pad = w.padding::Inset
    ox = _sc(Int(m.left[]) + Int(brd.left[]) + Int(pad.left[]))
    oy = _sc(Int(m.top[])  + Int(brd.top[])  + Int(pad.top[]))
    (ox, oy)
end

"""
Return the total (horizontal, vertical) space consumed by all box-model layers
(font-scaled).
"""
function _inset_total(w::WidgetDocument)
    m   = w.margin::Inset
    brd = w.border::Inset
    pad = w.padding::Inset
    tx = _sc(Int(m.left[]) + Int(m.right[]) + Int(brd.left[]) + Int(brd.right[]) +
             Int(pad.left[]) + Int(pad.right[]))
    ty = _sc(Int(m.top[])  + Int(m.bottom[]) + Int(brd.top[])  + Int(brd.bottom[]) +
             Int(pad.top[])  + Int(pad.bottom[]))
    (tx, ty)
end

"""
Push colored rectangles for every non-transparent box-model layer of `w`.
`bx, by` is the widget's outer top-left (outermost edge of margin).
`cw, ch` is the content size (inside padding).
"""
function _push_box_rects!(elems::Vector, w::WidgetDocument,
                          bx::Int, by::Int, cw::Int, ch::Int)
    m   = w.margin::Inset
    brd = w.border::Inset
    pad = w.padding::Inset

    ml, mt, mr, mb = Int(m.left[]),   Int(m.top[]),   Int(m.right[]),  Int(m.bottom[])
    bl, bt, br, bb = Int(brd.left[]), Int(brd.top[]), Int(brd.right[]), Int(brd.bottom[])
    pl, pt, pr, pb = Int(pad.left[]), Int(pad.top[]), Int(pad.right[]), Int(pad.bottom[])

    pw = cw + pl + pr    # padded-content width  (inside border)
    ph = ch + pt + pb    # padded-content height

    mc = w.margin_color
    if mc isa StyleColor
        r, g, blu, a = _rgba(mc)
        total_w = ml + bl + pw + br + mr
        mt > 0 && push!(elems, GraphicsRect(bx,                      by, total_w, mt,  r, g, blu, a))
        mb > 0 && push!(elems, GraphicsRect(bx, by + mt + bt + ph + bb, total_w, mb,  r, g, blu, a))
        ml > 0 && push!(elems, GraphicsRect(bx,              by + mt,   ml, bt + ph + bb, r, g, blu, a))
        mr > 0 && push!(elems, GraphicsRect(bx + ml + bl + pw + br, by + mt, mr, bt + ph + bb, r, g, blu, a))
    end

    bc = w.border_color
    if bc isa StyleColor
        r, g, blu, a = _rgba(bc)
        bx2, by2 = bx + ml, by + mt
        bt > 0 && push!(elems, GraphicsRect(bx2,              by2,         bl + pw + br, bt,  r, g, blu, a))
        bb > 0 && push!(elems, GraphicsRect(bx2, by2 + bt + ph,            bl + pw + br, bb,  r, g, blu, a))
        bl > 0 && push!(elems, GraphicsRect(bx2,         by2 + bt,         bl, ph,           r, g, blu, a))
        br > 0 && push!(elems, GraphicsRect(bx2 + bl + pw, by2 + bt,       br, ph,           r, g, blu, a))
    end

    pc = w.padding_color
    if pc isa StyleColor
        r, g, blu, a = _rgba(pc)
        push!(elems, GraphicsRect(bx + ml + bl, by + mt + bt, pw, ph, r, g, blu, a))
    end
end

# ── Text helpers ───────────────────────────────────────────────────────────

function _push_text!(elems::Vector, font::StyleFont, text::AbstractString,
                     x::Int, y::Int, fg::NTuple{4,UInt8})
    r, g, b, a = fg
    push!(elems, GraphicsText(text, x, y, font, r, g, b, a))
end

function _text_size(measure::Function, font::StyleFont, text::AbstractString)
    measure(text, font)
end

# ── Width resolution (content-aware + layout-aware) ─────────────────────────

# Resolve the rendered width for a width-bearing widget. The authored `intrinsic`
# width (already font-scaled) is treated as a *minimum*, not a hard size:
#
#   - when a parent layout seeded `available_width` on the context, fill that
#     allocation (so the widget participates in automatic layout);
#   - otherwise fall back to the intrinsic minimum;
#   - in both cases never go narrower than `content_min` (the measured content
#     plus its padding), so text/content is never clipped.
#
# `content_min` defaults to 0 for widgets with no measurable content (progress,
# slider, skeleton), which then size purely from the allocation/intrinsic.
function _resolve_width(ctx, intrinsic::Int, content_min::Int=0)
    avail = ctx === nothing ? nothing : ctx.available_width
    base = avail !== nothing ? max(0, Int(avail[])) : intrinsic
    max(base, content_min)
end

# ── Canvas construction helper ─────────────────────────────────────────────

function _make_canvas(x::Int, y::Int, elems::Vector)
    GraphicsCanvas(Int32(x), Int32(y), Int32(0), Int32(0),
                   CellVector(Cell[Cell(e) for e in elems]),
                   layout_none, true, Cell(nothing))
end

function _make_canvas(x::Int, y::Int, w::Int, h::Int, elems::Vector)
    GraphicsCanvas(Int32(x), Int32(y), Int32(w), Int32(h),
                   CellVector(Cell[Cell(e) for e in elems]),
                   layout_none, true, Cell(nothing))
end

_empty_canvas() = GraphicsCanvas(Int32(0), Int32(0), Int32(0), Int32(0),
                                 CellVector(), layout_none, true, Cell(nothing))

# ── Event routing helper ──────────────────────────────────────────────────

function _route_to_children(child_entries::Vector, x::Int, y::Int, make_evt)
    for entry in child_entries
        entry === nothing && continue
        (ox, oy, cim) = entry::Tuple{Int,Int,Any}
        canvas = cim.output
        canvas isa GraphicsCanvas || continue
        lx, ly = x - ox - Int(canvas.x), y - oy - Int(canvas.y)
        hit_element_at(canvas, lx, ly) === nothing && continue
        result = projection_read(cim.projection, cim, make_evt(lx, ly))
        result !== nothing && return result
    end
    nothing
end

_route_scroll_to_children(child_entries::Vector, evt::MouseScroll) =
    _route_to_children(child_entries, evt.x, evt.y,
        (x, y) -> MouseScroll(evt.dx, evt.dy, x, y))

_route_click_to_children(child_entries::Vector, evt::MousePress) =
    _route_to_children(child_entries, evt.x, evt.y,
        (x, y) -> MousePress(evt.button, x, y, evt.modifiers))

# Translate a path-bearing op from `op`'s current domain (this projection's
# child's input domain — what the bubbled-up reader returned) into this
# projection's own input domain by running its reference through
# `map_reference_backward`. Non-path-bearing ops (ScrollWidgetOperation,
# SelectTabOperation, …) pass through unchanged; `nothing` passes through.
# Returns `nothing` if the backward mapping rejects the reference.
function _retarget_op(p, iomap, op)
    op === nothing && return nothing
    if op isa ReplaceSelectionOperation
        new_ref = map_reference_backward(p, iomap, op.path)
        return new_ref === nothing ? nothing : ReplaceSelectionOperation(new_ref)
    elseif op isa StringReplaceRangeOperation
        new_ref = map_reference_backward(p, iomap, op.reference)
        return new_ref === nothing ? nothing : StringReplaceRangeOperation(new_ref, op.replacement)
    elseif op isa NumberReplaceRangeOperation
        new_ref = map_reference_backward(p, iomap, op.reference)
        return new_ref === nothing ? nothing : NumberReplaceRangeOperation(new_ref, op.replacement)
    else
        return op
    end
end

# Prepend a tuple of reference steps to the reference inside a path-bearing
# operation. Used by readers that need to add several steps at once (e.g.
# split pane: `elements[i].child`).
function _prepend_steps_to_ref(ref::ReferencePath, steps::Tuple)
    result = ref
    for step in reverse(steps)
        result = ConcreteReferencePath(step, result)
    end
    result
end

function _prepend_steps_to_op(op, steps::Tuple)
    op === nothing && return nothing
    if op isa ReplaceSelectionOperation
        ReplaceSelectionOperation(_prepend_steps_to_ref(op.path, steps))
    elseif op isa StringReplaceRangeOperation
        StringReplaceRangeOperation(_prepend_steps_to_ref(op.reference, steps), op.replacement)
    elseif op isa NumberReplaceRangeOperation
        NumberReplaceRangeOperation(_prepend_steps_to_ref(op.reference, steps), op.replacement)
    else
        op
    end
end

# ── WidgetLabel ─────────────────────────────────────────────────────────────

function projection_print(p::WidgetLabelToGraphicsCanvas, recursion, w::WidgetLabel, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    pos = w.position::Point2D
    text = string(w.content)
    cw, ch = _text_size(p.measure, p.font, text)
    elems = Any[]
    _push_text!(elems, p.font, text, 0, 0, _rgba(p.theme.foreground))
    SimpleIoMap(p, w, _make_canvas(_origin(pos)..., cw, ch, elems))
end

function map_reference_forward(::WidgetLabelToGraphicsCanvas, iomap, reference)
    return nothing
end

function map_reference_backward(::WidgetLabelToGraphicsCanvas, iomap, reference)
    return nothing
end

function projection_read(::WidgetLabelToGraphicsCanvas, iomap::SimpleIoMap, evt)
    return nothing
end

# ── WidgetText ──────────────────────────────────────────────────────────────

# IoMap for an *editable* WidgetText: its `content` is a Document (typically a
# `TextText`) recursed through the Text domain, so all caret navigation and text
# editing is produced by `TextToGraphics`. The widget only re-roots the resulting
# operations by prepending `content` (see `map_reference_backward`).
struct WidgetTextToGraphicsCanvasIoMap <: IoMap
    projection::Any
    input::WidgetText
    output::GraphicsCanvas
    content_iomap::Any
end

function projection_print(p::WidgetTextToGraphicsCanvas, recursion, w::WidgetText, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    pos = w.position::Point2D
    cox, coy = _content_offset(w)

    # Editable form: a Document content (e.g. a TextText) is recursed through the
    # outer projection chain (which routes it to TextToGraphics). Navigation and
    # editing operations then originate in the Text domain; this projection just
    # maps them backward. Mirrors WidgetScrollPane's content recursion.
    radius = _sc(p.theme.radius)
    content = w.content
    if content isa Document
        content_iomap = projection_print(recursion, recursion, content, ctx)
        inner = content_iomap.output::GraphicsCanvas
        iw, ih = Int(inner.w[]), Int(inner.h[])
        elems = Any[]
        # Themed input surface: background fill + input outline + rounded corners.
        _push_box!(elems, w, iw, ih; fill=p.theme.background, border=p.theme.input, radius=radius)
        push!(elems, _make_canvas(cox, coy, Any[inner]))
        tx, ty = _inset_total(w)
        canvas = _make_canvas(_origin(pos)..., iw + tx, ih + ty, elems)
        return WidgetTextToGraphicsCanvasIoMap(p, w, canvas, content_iomap)
    end

    # Non-editable form: a plain value is stringified (input-like).
    text = string(content)
    cw, ch = _text_size(p.measure, p.font, text)
    tx, ty = _inset_total(w)
    elems = Any[]
    _push_box!(elems, w, cw, ch; fill=p.theme.background, border=p.theme.input, radius=radius)
    _push_text!(elems, p.font, text, cox, coy, _rgba(p.theme.foreground))
    SimpleIoMap(p, w, _make_canvas(_origin(pos)..., cw + tx, ch + ty, elems))
end

function map_reference_forward(::WidgetTextToGraphicsCanvas, iomap, reference)
    return nothing
end

function map_reference_backward(::WidgetTextToGraphicsCanvas, iomap, reference)
    return nothing
end

# Re-root a content-domain reference (already translated by the inner Text-domain
# reader) into this widget's domain by prepending `.content`. Same contribution
# WidgetScrollPane makes for its wrapped document.
function map_reference_backward(::WidgetTextToGraphicsCanvas, iomap::WidgetTextToGraphicsCanvasIoMap, reference)
    reference === nothing && return nothing
    ConcreteReferencePath(FieldReference("content"), reference)
end

function projection_read(::WidgetTextToGraphicsCanvas, iomap::SimpleIoMap, evt)
    return nothing
end

# Delegate every event to the recursed content (Text domain), then re-root the
# returned path-bearing operation through `map_reference_backward`. MousePress is
# translated into the content's coordinate frame first.
function projection_read(p::WidgetTextToGraphicsCanvas, iomap::WidgetTextToGraphicsCanvasIoMap, evt)
    content_iomap = iomap.content_iomap
    content_iomap === nothing && return nothing
    op = @event_case evt begin
        MousePress(button, x, y) => begin
            cox, coy = _content_offset(iomap.input)
            projection_read(content_iomap.projection, content_iomap,
                            MousePress(button, x - cox, y - coy, evt.modifiers))
        end
        _ => projection_read(content_iomap.projection, content_iomap, evt)
    end
    _retarget_op(p, iomap, op)
end

# ── WidgetCheckbox ──────────────────────────────────────────────────────────

function projection_print(p::WidgetCheckboxToGraphicsCanvas, recursion, w::WidgetCheckbox, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    pos = w.position::Point2D
    checked = w.content === true
    s   = _sc(p.theme.checkbox_size)   # box size
    rad = _sc(p.theme.radius ÷ 2)
    bw  = max(1, _sc(p.theme.stroke))  # outline / stroke width
    elems = Any[]
    if checked
        _push_panel!(elems, 0, 0, s, s; fill=p.theme.primary, radius=rad)
        fr, fg, fb, fa = _rgbai(p.theme.primary_foreground)
        # Crisp two-stroke checkmark instead of a glyph.
        x1, y1 = round(Int, 0.22s), round(Int, 0.52s)
        x2, y2 = round(Int, 0.42s), round(Int, 0.70s)
        x3, y3 = round(Int, 0.78s), round(Int, 0.30s)
        push!(elems, GraphicsLine(x1, y1, x2, y2, fr, fg, fb, fa; width=bw))
        push!(elems, GraphicsLine(x2, y2, x3, y3, fr, fg, fb, fa; width=bw))
    else
        _push_panel!(elems, 0, 0, s, s; fill=p.theme.background,
                     border=p.theme.input, border_w=bw, radius=rad)
    end
    SimpleIoMap(p, w, _make_canvas(_origin(pos)..., s, s, elems))
end

function map_reference_forward(::WidgetCheckboxToGraphicsCanvas, iomap, reference)
    return nothing
end

function map_reference_backward(::WidgetCheckboxToGraphicsCanvas, iomap, reference)
    return nothing
end

# A click toggles the checkbox. By convention a leaf control reports an edit as
# `ReplaceReferencedValue(self, content, new_value)`; a configuring projection
# (ObjectToWidget) intercepts it by control identity and redirects it onto the
# bound parameter cell. A bare click that does not reach here leaves the value
# unchanged.
function projection_read(::WidgetCheckboxToGraphicsCanvas, iomap::SimpleIoMap, evt::MousePress)
    w = iomap.input
    new_value = !(w.content === true)
    ReplaceReferencedValue(w, ConcreteReferencePath(FieldReference("content"), EmptyReferencePath()), new_value)
end

function projection_read(::WidgetCheckboxToGraphicsCanvas, iomap::SimpleIoMap, evt)
    return nothing
end

# ── WidgetButton ────────────────────────────────────────────────────────────

function projection_print(p::WidgetButtonToGraphicsCanvas, recursion, w::WidgetButton, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    pos = w.position::Point2D
    sz  = w.size::Point2D
    cox, coy = _content_offset(w)
    tx, ty = _inset_total(w)
    text = string(w.content)
    tw, th = _text_size(p.measure, p.font, text)
    pad_x, pad_y = _sc(p.theme.pad_x), _sc(p.theme.pad_y)
    bw = max(Int(sz.x[]), tw + 2pad_x)
    bh = max(Int(sz.y[]), th + 2pad_y)
    radius = _sc(p.theme.radius)
    elems = Any[]
    # Default button: light surface, subtle border, soft shadow, dark label —
    # matching the shadcn default button. A faint offset rect approximates the
    # shadow-sm drop shadow.
    push!(elems, GraphicsRect(0, _sc(p.theme.shadow_offset), bw, bh, 0x00, 0x00, 0x00, 0x14, radius))
    _push_panel!(elems, 0, 0, bw, bh; fill=p.theme.background,
                 border=p.theme.border, border_w=max(1, _sc(p.theme.border_width)), radius=radius)
    fr, fg, fb, fa = _rgbai(p.theme.foreground)
    push!(elems, GraphicsText(text, (bw - tw) ÷ 2, (bh - th) ÷ 2, p.font, fr, fg, fb, fa))
    SimpleIoMap(p, w, _make_canvas(_origin(pos)..., bw, bh, elems))
end

function map_reference_forward(::WidgetButtonToGraphicsCanvas, iomap, reference)
    return nothing
end

function map_reference_backward(::WidgetButtonToGraphicsCanvas, iomap, reference)
    return nothing
end

function projection_read(::WidgetButtonToGraphicsCanvas, iomap::SimpleIoMap, evt)
    return nothing
end

# ── WidgetTooltip ───────────────────────────────────────────────────────────

function projection_print(p::WidgetTooltipToGraphicsCanvas, recursion, w::WidgetTooltip, ctx)
    w.visible == false && return ChildrenIoMap(p, w, _empty_canvas(), Cell(Any[]))
    pos = w.position::Point2D
    cox, coy = _content_offset(w)
    tx, ty = _inset_total(w)
    # Use sensible default padding when the document specifies none, so the box
    # never hugs the text.
    cox = max(cox, _sc(p.theme.pad_x)); coy = max(coy, _sc(p.theme.pad_y))
    txp = max(tx, 2 * _sc(p.theme.pad_x)); typ = max(ty, 2 * _sc(p.theme.pad_y))
    child_iomaps = Any[]
    content = w.content
    elems = Any[]
    # Size the box to its content (at least the requested size).
    cw, ch = 0, 0
    body = Any[]
    if content isa AbstractString
        cw, ch = _text_size(p.measure, p.font, content)
        _push_text!(body, p.font, content, cox, coy, _rgba(p.theme.popover_foreground))
    elseif content isa WidgetDocument
        cim = projection_print(recursion, recursion, content, ctx)
        inner = cim.output
        cw, ch = inner isa GraphicsCanvas ? (Int(inner.w[]), Int(inner.h[])) : (0, 0)
        push!(child_iomaps, (cox, coy, cim))
        push!(body, _make_canvas(cox, coy, Any[inner]))
    end
    vw = cw + txp
    vh = ch + typ
    _push_panel!(elems, 0, 0, vw, vh; fill=p.theme.popover,
                 border=p.theme.border, border_w=max(1, _sc(p.theme.border_width)), radius=_sc(p.theme.radius))
    append!(elems, body)
    ChildrenIoMap(p, w, _make_canvas(_origin(pos)..., vw, vh, elems), Cell(child_iomaps))
end

function map_reference_forward(::WidgetTooltipToGraphicsCanvas, iomap, reference)
    return nothing
end

function map_reference_backward(::WidgetTooltipToGraphicsCanvas, iomap, reference)
    return nothing
end

function projection_read(::WidgetTooltipToGraphicsCanvas, iomap::ChildrenIoMap, evt)
    evt isa MouseScroll || return nothing
    child_iomaps = iomap.child_iomaps[]::Vector
    _route_scroll_to_children(child_iomaps, evt)
end

# ── WidgetMenuItem ──────────────────────────────────────────────────────────

function projection_print(p::WidgetMenuItemToGraphicsCanvas, recursion, w::WidgetMenuItem, ctx)
    w.visible == false && return ChildrenIoMap(p, w, _empty_canvas(), Cell(Any[]))
    cox, coy = _content_offset(w)
    content = w.content
    child_iomaps = Any[]
    elems = Any[]
    if content isa WidgetDocument
        cim = projection_print(recursion, recursion, content, ctx)
        push!(child_iomaps, (cox, coy, cim))
        push!(elems, _make_canvas(cox, coy, Any[cim.output]))
    else
        text = string(content)
        cw, ch = _text_size(p.measure, p.font, text)
        _push_text!(elems, p.font, text, cox, coy, _rgba(p.theme.foreground))
    end
    ChildrenIoMap(p, w, _make_canvas(0, 0, elems), Cell(child_iomaps))
end

function map_reference_forward(::WidgetMenuItemToGraphicsCanvas, iomap, reference)
    return nothing
end

function map_reference_backward(::WidgetMenuItemToGraphicsCanvas, iomap, reference)
    return nothing
end

function projection_read(::WidgetMenuItemToGraphicsCanvas, iomap::ChildrenIoMap, evt)
    evt isa MouseScroll || return nothing
    child_iomaps = iomap.child_iomaps[]::Vector
    _route_scroll_to_children(child_iomaps, evt)
end

# ── WidgetMenu ──────────────────────────────────────────────────────────────

function projection_print(p::WidgetMenuToGraphicsCanvas, recursion, w::WidgetMenu, ctx)
    w.visible == false && return ChildrenIoMap(p, w, _empty_canvas(), Cell(Any[]))
    cox, coy = _content_offset(w)
    child_iomaps = Any[]
    elems = Any[]
    y_cursor = coy
    _, item_h = p.measure("M", p.font)
    for item in w.elements
        item isa WidgetDocument || continue
        cim = projection_print(recursion, recursion, item, ctx)
        push!(child_iomaps, (cox, y_cursor, cim))
        push!(elems, _make_canvas(cox, y_cursor, Any[cim.output]))
        y_cursor += item_h
    end
    ChildrenIoMap(p, w, _make_canvas(0, 0, elems), Cell(child_iomaps))
end

function map_reference_forward(::WidgetMenuToGraphicsCanvas, iomap, reference)
    return nothing
end

function map_reference_backward(::WidgetMenuToGraphicsCanvas, iomap, reference)
    return nothing
end

function projection_read(::WidgetMenuToGraphicsCanvas, iomap::ChildrenIoMap, evt)
    evt isa MouseScroll || return nothing
    child_iomaps = iomap.child_iomaps[]::Vector
    _route_scroll_to_children(child_iomaps, evt)
end

# ── WidgetComposite ─────────────────────────────────────────────────────────

function projection_print(p::WidgetCompositeToGraphicsCanvas, recursion, w::WidgetComposite, ctx)
    w.visible == false && return ChildrenIoMap(p, w, _empty_canvas(), Cell(Any[]))
    pos = w.position::Point2D
    cox, coy = _content_offset(w)
    child_iomaps = Any[]
    elems = Any[]
    for child in w.elements
        child isa WidgetDocument || continue
        cim = projection_print(recursion, recursion, child, ctx)
        push!(child_iomaps, (cox, coy, cim))
        push!(elems, _make_canvas(cox, coy, Any[cim.output]))
    end
    ChildrenIoMap(p, w, _make_canvas(_origin(pos)..., elems), Cell(child_iomaps))
end

function map_reference_forward(::WidgetCompositeToGraphicsCanvas, iomap, reference)
    return nothing
end

function map_reference_backward(::WidgetCompositeToGraphicsCanvas, iomap, reference)
    return nothing
end

# Route events to composite children and re-root the returned op. A MousePress
# is hit-tested against each child canvas; a coordless event (KeyPress/KeyDown)
# goes to the child the composite's selection points at, falling back to trying
# each child. The op a child returns is re-rooted by prepending `elements[i]` —
# the same scheme WidgetSplitPane uses. Identity-bearing ops (ReplaceReferencedValue
# from a control) pass through `_prepend_steps_to_op` unchanged.
function projection_read(p::WidgetCompositeToGraphicsCanvas, iomap::ChildrenIoMap, evt)
    child_iomaps = iomap.child_iomaps[]::Vector
    res = @event_case evt begin
        MouseScroll => _route_composite_event(child_iomaps, evt.x, evt.y,
            (x, y) -> MouseScroll(evt.dx, evt.dy, x, y))
        MousePress => _route_composite_event(child_iomaps, evt.x, evt.y,
            (x, y) -> MousePress(evt.button, x, y, evt.modifiers))
        _ => begin
            slot = iomap.input isa WidgetComposite ?
                   _selected_composite_slot(iomap.input, length(child_iomaps)) : 0
            slot == 0 ? _forward_composite_event(child_iomaps, evt) :
                        _forward_composite_event_slot(child_iomaps, evt, slot)
        end
    end
    res === nothing && return nothing
    op, slot_idx = res
    _prepend_steps_to_op(op, (FieldReference("elements"), RangeReference(slot_idx - 1, slot_idx)))
end

# Hit-test a coordinate event against each child canvas; returns `(op, i)` for
# the first child that produced a non-nothing result.
function _route_composite_event(child_iomaps::Vector, x::Int, y::Int, make_evt)
    for (i, entry) in enumerate(child_iomaps)
        entry === nothing && continue
        (ox, oy, cim) = entry::Tuple{Int,Int,Any}
        canvas = cim.output
        canvas isa GraphicsCanvas || continue
        lx, ly = x - ox - Int(canvas.x), y - oy - Int(canvas.y)
        hit_element_at(canvas, lx, ly) === nothing && continue
        result = projection_read(cim.projection, cim, make_evt(lx, ly))
        result !== nothing && return (result, i)
    end
    nothing
end

# Forward a coordless event through children in order; `(op, i)` for the first
# that produced an Operation (a passthrough of the raw event doesn't count).
function _forward_composite_event(child_iomaps::Vector, evt)
    for (i, entry) in enumerate(child_iomaps)
        entry === nothing && continue
        (_, _, cim) = entry::Tuple{Int,Int,Any}
        result = projection_read(cim.projection, cim, evt)
        result isa Operation && return (result, i)
    end
    nothing
end

# Forward a coordless event to the single child the selection points at.
function _forward_composite_event_slot(child_iomaps::Vector, evt, slot::Int)
    (1 <= slot <= length(child_iomaps)) || return nothing
    entry = child_iomaps[slot]
    entry === nothing && return nothing
    (_, _, cim) = entry::Tuple{Int,Int,Any}
    result = projection_read(cim.projection, cim, evt)
    result isa Operation ? (result, slot) : nothing
end

# The child slot the composite's selection (`elements[slot].<rest>`) points at,
# or 0 when it carries no such selection.
function _selected_composite_slot(w::WidgetComposite, n::Int)
    sel = getfield(w, :selection)[]
    sel isa ConcreteReferencePath || return 0
    (sel.head isa FieldReference && sel.head.name == "elements") || return 0
    t = sel.tail
    (t isa ConcreteReferencePath && t.head isa RangeReference) || return 0
    slot = t.head.start + 1
    1 <= slot <= n ? slot : 0
end

# ── WidgetShell ─────────────────────────────────────────────────────────────

function projection_print(p::WidgetShellToGraphicsCanvas, recursion, w::WidgetShell, ctx)
    w.visible == false && return ChildrenIoMap(p, w, _empty_canvas(), Cell(Any[]))
    cox, coy = _content_offset(w)
    elems = Any[]
    child_iomaps = Any[]
    sz  = w.size
    if sz isa Point2D
        r, g, b, a = _rgba(p.theme.background)
        push!(elems, GraphicsRect(cox, coy, Int(sz.x[]), Int(sz.y[]), r, g, b, a))
    end
    content_y = coy
    mb = w.menu_bar
    if mb isa WidgetDocument
        cim = projection_print(recursion, recursion, mb, ctx)
        push!(child_iomaps, (cox, content_y, cim))
        push!(elems, _make_canvas(cox, content_y, Any[cim.output]))
        _, menu_h = p.measure("M", p.font)
        content_y += menu_h
    end
    tb = w.toolbar
    if tb isa WidgetDocument
        cim = projection_print(recursion, recursion, tb, ctx)
        push!(child_iomaps, (cox, content_y, cim))
        push!(elems, _make_canvas(cox, content_y, Any[cim.output]))
        _, toolbar_h = p.measure("M", p.font)
        content_y += toolbar_h + p.theme.gap
    end
    content = w.content
    if content isa WidgetDocument
        # Seed available size on the context so that any layout/split
        # descendant can allocate its slots within the shell's content
        # area. Computed reactively from the shell's own `size` cell and
        # box-model insets so a resize re-flows downstream automatically.
        size_cell = getfield(w, :size)
        margin_cell  = getfield(w, :margin)
        border_cell  = getfield(w, :border)
        padding_cell = getfield(w, :padding)
        content_y_now = content_y
        coy_now = coy
        avail_w_cell = Cell(function ()
            sz = size_cell[]
            sz isa Point2D || return 0
            tx, _ = _inset_total(w)
            max(0, Int(sz.x[]) - tx)
        end)
        avail_h_cell = Cell(function ()
            sz = size_cell[]
            sz isa Point2D || return 0
            _, ty = _inset_total(w)
            max(0, Int(sz.y[]) - ty - (content_y_now - coy_now))
        end)
        content_ctx = with_available_size(ctx; width=avail_w_cell, height=avail_h_cell)
        cim = projection_print(recursion, recursion, content, content_ctx)
        push!(child_iomaps, (cox, content_y, cim))
        push!(elems, _make_canvas(cox, content_y, Any[cim.output]))
    end
    tt = w.tooltip
    if tt isa WidgetDocument
        cim = projection_print(recursion, recursion, tt, ctx)
        push!(child_iomaps, (0, 0, cim))
        push!(elems, _make_canvas(0, 0, Any[cim.output]))
    end
    ChildrenIoMap(p, w, _make_canvas(0, 0, elems), Cell(child_iomaps))
end

function map_reference_forward(::WidgetShellToGraphicsCanvas, iomap, reference)
    return nothing
end

# The shell wraps a single child widget as its `.content` field. A path
# coming up from the child's reader lives at `.content.<rest>` in the
# shell's input domain.
function map_reference_backward(p::WidgetShellToGraphicsCanvas, iomap::ChildrenIoMap, reference)
    reference === nothing && return nothing
    ConcreteReferencePath(FieldReference("content"), reference)
end

function projection_read(p::WidgetShellToGraphicsCanvas, iomap::ChildrenIoMap, evt)
    child_iomaps = iomap.child_iomaps[]::Vector
    op = @event_case evt begin
        MouseScroll => _route_scroll_to_children(child_iomaps, evt)
        MousePress  => _route_click_to_children(child_iomaps, evt)
        # Forward keyboard (and other coordless) events to the wrapped
        # child. The reader at the focused leaf returns an op; others
        # return nothing.
        _           => _forward_to_children(child_iomaps, evt)
    end
    _retarget_op(p, iomap, op)
end

# Forward a coordless event to each child entry's reader, returning the
# first child that produced an `Operation`. Entries are `(x, y, cim)` tuples —
# coords are ignored here. A child has only *handled* the event if it returns
# an `Operation`; readers that pass the raw event back through (the common
# `projection_read(p, iomap, op) = op` passthrough) must not be mistaken for
# handlers, otherwise a non-focused pane would swallow the keystroke before a
# later, focused pane is reached.
function _forward_to_children(child_entries::Vector, evt)
    for entry in child_entries
        entry === nothing && continue
        (_, _, cim) = entry::Tuple{Int,Int,Any}
        result = projection_read(cim.projection, cim, evt)
        result isa Operation && return result
    end
    nothing
end

# ── WidgetTitlePane ─────────────────────────────────────────────────────────

function projection_print(p::WidgetTitlePaneToGraphicsCanvas, recursion, w::WidgetTitlePane, ctx)
    w.visible == false && return ChildrenIoMap(p, w, _empty_canvas(), Cell(Any[]))
    cox, coy = _content_offset(w)
    elems = Any[]
    child_iomaps = Any[]
    title_text = string(w.title)
    tw, th = _text_size(p.measure, p.theme.font_bold, title_text)
    # Card-like: bold title in foreground, body in card_foreground.
    _push_text!(elems, p.theme.font_bold, title_text, cox, coy, _rgba(p.theme.foreground))
    content_y = coy + th + _sc(p.theme.title_gap)
    content = w.content
    if content isa WidgetDocument
        cim = projection_print(recursion, recursion, content, ctx)
        push!(child_iomaps, (cox, content_y, cim))
        push!(elems, _make_canvas(cox, content_y, Any[cim.output]))
    elseif content isa AbstractString
        _push_text!(elems, p.font, content, cox, content_y, _rgba(p.theme.card_foreground))
    end
    ChildrenIoMap(p, w, _make_canvas(0, 0, elems), Cell(child_iomaps))
end

function map_reference_forward(::WidgetTitlePaneToGraphicsCanvas, iomap, reference)
    return nothing
end

function map_reference_backward(::WidgetTitlePaneToGraphicsCanvas, iomap, reference)
    return nothing
end

function projection_read(::WidgetTitlePaneToGraphicsCanvas, iomap::ChildrenIoMap, evt)
    evt isa MouseScroll || return nothing
    child_iomaps = iomap.child_iomaps[]::Vector
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
function _wrap_child_canvas(child::GraphicsCanvas, x_cell::Cell, y_cell::Cell)
    GraphicsCanvas(x_cell, y_cell,
                   Cell(Int32(0)), Cell(Int32(0)),
                   CellVector(Cell[Cell(child)]),
                   layout_none, true, Cell(nothing))
end

"""
Per-slot intrinsic main-axis extent: read from the `LayoutConstraint`'s
preferred when present, or fall back to the legacy `sizes` vector for
backward compatibility, or to 200 px when neither is set.
"""
function _split_intrinsic(elem, sizes, i::Int, axis::Symbol)
    intrinsic = (!isempty(sizes) && i <= length(sizes)) ? Int(sizes[i]) : 200
    layout_preferred(elem, axis, intrinsic)
end

function projection_print(p::WidgetSplitPaneToGraphicsCanvas, recursion, w::WidgetSplitPane, ctx)
    w.visible == false && return ChildrenIoMap(p, w, _empty_canvas(), Cell(Any[]))
    cox, coy = _content_offset(w)
    orientation = w.orientation::Symbol
    main_axis = orientation === :horizontal ? :x : :y
    sizes = w.sizes
    splitter_thickness = max(1, _sc(p.theme.border_width))
    splitter_rgba = _rgba(p.theme.border)

    # Keep only Document children; LayoutConstraint and bare widgets both
    # work — the wrapper is transparent for projection (we recurse into
    # `elem.child`) and consulted for sizing policy.
    valid_elems = Any[]
    for i in 1:length(w.elements)
        elem = w.elements[i]
        (elem isa LayoutConstraint || elem isa WidgetDocument) && push!(valid_elems, elem)
    end
    n = length(valid_elems)
    n == 0 && return ChildrenIoMap(p, w, _make_canvas(0, 0, Any[]), Cell(Any[]))

    avail_w = ctx.available_width
    avail_h = ctx.available_height
    avail_main = main_axis === :x ? avail_w : avail_h

    # Per-slot main-axis size (Cell). When the parent gave us an allocation
    # on the main axis, the slot is the per-child share of that allocation;
    # otherwise the slot falls back to each child's intrinsic preferred
    # extent. Built up-front so we can seed it into each child's available
    # size before recursion — without it the child (typically a scroll
    # pane) has no way to size its viewport to its slot.
    alloc_main_ref = Ref{Union{Nothing,Cell}}(nothing)
    slot_main = Cell[]
    if avail_main !== nothing
        for i in 1:n
            push!(slot_main, Cell(() -> (alloc_main_ref[])[][i]))
        end
    else
        for i in 1:n
            elem = valid_elems[i]
            push!(slot_main, Cell(() -> _split_intrinsic(elem, sizes, i, main_axis)))
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
        cctx  = main_axis === :x ?
                with_available_size(ctx; width=cell) :
                with_available_size(ctx; height=cell)
        cim = projection_print(recursion, recursion, inner, cctx)
        push!(inner_iomaps, cim)
    end

    # Build the main-axis allocation cell now that intrinsic widths are
    # readable via the inner canvases. Falls back to legacy `sizes` when
    # neither LayoutConstraint nor intrinsic preference is supplied.
    if avail_main !== nothing
        local_elems = valid_elems
        local_cims  = inner_iomaps
        axis        = main_axis
        n_local     = n
        sizes_local = sizes
        alloc_main_ref[] = Cell(function ()
            mins  = Vector{Int}(undef, n_local)
            maxs  = Vector{Int}(undef, n_local)
            prefs = Vector{Int}(undef, n_local)
            wts   = Vector{Float64}(undef, n_local)
            for i in 1:n_local
                elem      = local_elems[i]
                intrinsic = _split_intrinsic(elem, sizes_local, i, axis)
                mins[i]   = layout_min(elem, axis, intrinsic)
                maxs[i]   = layout_max(elem, axis, intrinsic)
                prefs[i]  = intrinsic
                wts[i]    = layout_weight(elem, axis)
            end
            allocate_axis(Int(avail_main[]), mins, maxs, prefs, wts,
                          splitter_thickness, n_local)
        end)
    end

    # Per-child top-left position cells (running cursor across the main axis).
    child_x = Cell[]
    child_y = Cell[]
    for i in 1:n
        if main_axis === :x
            push!(child_x, Cell(function ()
                x = cox
                for j in 1:(i-1)
                    x += Int(slot_main[j][]) + splitter_thickness
                end
                Int32(x)
            end))
            push!(child_y, Cell(Int32(coy)))
        else
            push!(child_x, Cell(Int32(cox)))
            push!(child_y, Cell(function ()
                y = coy
                for j in 1:(i-1)
                    y += Int(slot_main[j][]) + splitter_thickness
                end
                Int32(y)
            end))
        end
    end

    # Outer canvas size: sum of slot main extents (+ splitters) on the
    # main axis; max of child cross extents on the cross axis. If the
    # parent gave us an available cross extent we report that instead so
    # the slot fills the parent's allocation.
    outer_main = Cell(function ()
        total = 0
        for i in 1:n
            total += Int(slot_main[i][])
        end
        Int32(total + (n - 1) * splitter_thickness)
    end)
    outer_cross = if main_axis === :x
        avail_h === nothing ?
            Cell(function ()
                h = 0
                for cim in inner_iomaps
                    ch = cim.output isa GraphicsCanvas ? Int(cim.output.h[]) : 0
                    ch > h && (h = ch)
                end
                Int32(h)
            end) :
            Cell(() -> Int32(avail_h[]))
    else
        avail_w === nothing ?
            Cell(function ()
                wmax = 0
                for cim in inner_iomaps
                    cw = cim.output isa GraphicsCanvas ? Int(cim.output.w[]) : 0
                    cw > wmax && (wmax = cw)
                end
                Int32(wmax)
            end) :
            Cell(() -> Int32(avail_w[]))
    end
    outer_w_cell = main_axis === :x ? outer_main : outer_cross
    outer_h_cell = main_axis === :x ? outer_cross : outer_main

    # Build the outer canvas elements as a CellVector so splitter positions
    # and child wrappers re-flow reactively when slot sizes change. The
    # splitter's cross-axis extent tracks `outer_cross` so it spans exactly
    # the pane's cross dimension instead of overflowing on a fixed length.
    outer_elements = CellVector(function ()
        result = Any[]
        for i in 1:n
            cim = inner_iomaps[i]
            cim.output isa GraphicsCanvas || continue
            push!(result, _wrap_child_canvas(cim.output, child_x[i], child_y[i]))
        end
        cross_extent = Int(outer_cross[])
        if main_axis === :x
            cursor = cox
            for i in 1:(n-1)
                cursor += Int(slot_main[i][])
                push!(result, GraphicsRect(cursor, coy, splitter_thickness, cross_extent,
                                           splitter_rgba...))
                cursor += splitter_thickness
            end
        else
            cursor = coy
            for i in 1:(n-1)
                cursor += Int(slot_main[i][])
                push!(result, GraphicsRect(cox, cursor, cross_extent, splitter_thickness,
                                           splitter_rgba...))
                cursor += splitter_thickness
            end
        end
        result
    end)

    outer_canvas = GraphicsCanvas(Cell(Int32(0)), Cell(Int32(0)),
                                  outer_w_cell, outer_h_cell,
                                  outer_elements,
                                  layout_none, true, Cell(nothing))

    child_iomaps = Tuple{Cell,Cell,Any}[]
    for i in 1:n
        push!(child_iomaps, (child_x[i], child_y[i], inner_iomaps[i]))
    end
    ChildrenIoMap(p, w, outer_canvas, Cell(child_iomaps))
end

function map_reference_forward(::WidgetSplitPaneToGraphicsCanvas, iomap, reference)
    return nothing
end

# The split's input has `.elements[i]` (a CellVector). When the i-th slot
# wraps the child in a LayoutConstraint, the projector recurses into
# `.child` of the constraint; the backward map must account for that to
# re-root the inner path.
function map_reference_backward(p::WidgetSplitPaneToGraphicsCanvas, iomap::ChildrenIoMap, reference)
    reference === nothing && return nothing
    # Without a slot index this function can't disambiguate which child;
    # leave path-bearing translation to `projection_read` (which tracks the
    # slot it actually routed to). Cell-cursor mapping for the split's
    # selection is not currently used.
    return nothing
end

function projection_read(p::WidgetSplitPaneToGraphicsCanvas, iomap::ChildrenIoMap, evt)
    child_iomaps = iomap.child_iomaps[]::Vector
    res = @event_case evt begin
        MouseScroll => _route_split_event(child_iomaps, evt.x, evt.y,
            (x, y) -> MouseScroll(evt.dx, evt.dy, x, y))
        MousePress => _route_split_event(child_iomaps, evt.x, evt.y,
            (x, y) -> MousePress(evt.button, x, y, evt.modifiers))
        _ => begin
            # Forward keyboard (and other coordless) events to the child the
            # forward-projected selection points at, so the keystroke reaches the
            # focused descendant rather than whichever slot happens to answer
            # first. When the split carries no selection (e.g. a split built
            # outside the workbench, where nothing forward-projects onto it),
            # fall back to trying each slot in order.
            slot = iomap.input isa WidgetSplitPane ?
                   _selected_split_slot(iomap.input, length(child_iomaps)) : 0
            slot == 0 ? _forward_split_event(child_iomaps, evt) :
                        _forward_split_event_slot(child_iomaps, evt, slot)
        end
    end
    res === nothing && return nothing
    op, slot_idx = res
    # The slot at `iomap.input.elements[slot_idx]` may be wrapped in a
    # LayoutConstraint; if so, the projector descended into `.child`, and
    # the backward path must walk through it.
    elem = iomap.input.elements[slot_idx]
    steps = elem isa LayoutConstraint ?
            (FieldReference("elements"), RangeReference(slot_idx-1, slot_idx), FieldReference("child")) :
            (FieldReference("elements"), RangeReference(slot_idx-1, slot_idx))
    _prepend_steps_to_op(op, steps)
end

# Forward a coordless event through split-pane slots; entries are
# `(x_cell, y_cell, cim)` tuples — coords are ignored here. Returns
# `(op, slot_index)` for the first slot whose reader produced an `Operation`.
# A slot that only passes the raw event back through (see `_forward_to_children`)
# has not handled it, so the next slot still gets a chance.
function _forward_split_event(child_iomaps::Vector, evt)
    for (i, entry) in enumerate(child_iomaps)
        entry === nothing && continue
        (_, _, cim) = entry::Tuple{Cell,Cell,Any}
        result = projection_read(cim.projection, cim, evt)
        result isa Operation && return (result, i)
    end
    nothing
end

# The split slot the node's forward-projected selection points at. The
# projected selection has the shape `elements[slot].child.<rest>`, so the
# unit-range step right after the `elements` field names the slot. Returns 0
# when the split carries no such selection (route by fallback then).
function _selected_split_slot(w::WidgetSplitPane, n::Int)
    sel = getfield(w, :selection)[]
    sel isa ConcreteReferencePath || return 0
    (sel.head isa FieldReference && sel.head.name == "elements") || return 0
    t = sel.tail
    (t isa ConcreteReferencePath && t.head isa RangeReference) || return 0
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
    result = projection_read(cim.projection, cim, evt)
    result isa Operation ? (result, slot) : nothing
end

function _route_split_event(child_iomaps::Vector, x::Int, y::Int, make_evt)
    for (i, entry) in enumerate(child_iomaps)
        entry === nothing && continue
        (x_cell, y_cell, cim) = entry::Tuple{Cell,Cell,Any}
        canvas = cim.output
        canvas isa GraphicsCanvas || continue
        ox = Int(x_cell[])
        oy = Int(y_cell[])
        lx, ly = x - ox - Int(canvas.x), y - oy - Int(canvas.y)
        hit_element_at(canvas, lx, ly) === nothing && continue
        result = projection_read(cim.projection, cim, make_evt(lx, ly))
        result !== nothing && return (result, i)
    end
    nothing
end

# ── WidgetTabbedPane ────────────────────────────────────────────────────────

function projection_print(p::WidgetTabbedPaneToGraphicsCanvas, recursion, w::WidgetTabbedPane, ctx)
    w.visible == false && return ChildrenIoMap(p, w, _empty_canvas(), Cell(Any[]))
    cox, coy = _content_offset(w)
    pairs = w.selector_element_pairs
    child_iomaps = Any[]
    if isempty(pairs)
        return ChildrenIoMap(p, w, _empty_canvas(), Cell(child_iomaps))
    end

    sel_pad = p.theme.tab_pad
    tabs = Any[]
    for pair in pairs
        label = string(pair[1])
        tw, th = _text_size(p.measure, p.font, label)
        push!(tabs, (label, tw, th))
    end
    tab_h = maximum(t[3] for t in tabs)
    sel_h = tab_h + 2 * sel_pad

    tab_xs = Int[]
    tab_rws = Int[]
    x = cox
    for (_, tw, _) in tabs
        push!(tab_xs, x)
        push!(tab_rws, tw + 2 * sel_pad)
        x += tw + 2 * sel_pad
    end

    sel_cell = getfield(w, :selection)

    _active_idx(sel) = begin
        i = _tab_index_from_selection(sel, length(tabs))
        i == 0 ? 1 : i
    end

    selector_cv = CellVector(() -> begin
        active = _active_idx(sel_cell[])
        result = Any[]
        tab_radius = _sc(p.theme.radius)
        strip_w = isempty(tab_xs) ? 0 : (tab_xs[end] + tab_rws[end] - cox)
        # Muted track behind the whole tab row.
        _push_panel!(result, cox, coy, strip_w, sel_h; fill=p.theme.muted, radius=tab_radius)
        for i in eachindex(tabs)
            label, _, _ = tabs[i]
            tx, rw = tab_xs[i], tab_rws[i]
            if i == active
                # Active tab: a raised background pill.
                _push_panel!(result, tx, coy, rw, sel_h; fill=p.theme.background, radius=tab_radius)
            end
            fg = i == active ? p.theme.foreground : p.theme.muted_foreground
            _push_text!(result, p.font, label, tx + sel_pad, coy + sel_pad, _rgba(fg))
        end
        result
    end)

    # Seed a reduced available extent for the tab content: subtract the
    # tab strip height from the parent's available_height (if any) so the
    # content area knows it lives below the bar.
    avail_w = ctx.available_width
    avail_h = ctx.available_height
    content_ctx = if avail_h === nothing
        ctx
    else
        sel_h_const = sel_h
        avail_h_inner = Cell(() -> max(0, Int(avail_h[]) - sel_h_const))
        with_available_size(ctx; width=avail_w, height=avail_h_inner)
    end
    all_cims = Any[]
    for pair in pairs
        content = pair[2]
        if content !== nothing
            cim = projection_print(recursion, recursion, content, content_ctx)
            push!(child_iomaps, (cox, coy + sel_h, cim))
            push!(all_cims, cim)
        else
            push!(all_cims, nothing)
        end
    end

    content_cv = CellVector(() -> begin
        active = _active_idx(sel_cell[])
        idx = active == 0 ? 1 : active
        cim = all_cims[idx]
        cim === nothing ? Any[] : Any[_make_canvas(cox, coy + sel_h, Any[cim.output])]
    end)

    canvas = _make_canvas(0, 0, Any[
        GraphicsCanvas(selector_cv, layout_none, true),
        GraphicsCanvas(content_cv,  layout_none, true),
    ])
    ChildrenIoMap(p, w, canvas, Cell(child_iomaps))
end

function map_reference_forward(::WidgetTabbedPaneToGraphicsCanvas, iomap, reference)
    return nothing
end

# A tabbed pane's input has `.selector_element_pairs[i]` (a Pair whose
# second member is the i-th tab's content widget). The reader prepends
# `selector_element_pairs[i]` to bubbled paths so the active tab is
# encoded; upstream projections (e.g. `WorkbenchPageToWidgetTabbedPane`)
# decode it. Without a slot index this generic mapper has nothing to add.
function map_reference_backward(::WidgetTabbedPaneToGraphicsCanvas, iomap, reference)
    return nothing
end

function projection_read(p::WidgetTabbedPaneToGraphicsCanvas, iomap::ChildrenIoMap, evt)
    child_iomaps = iomap.child_iomaps[]::Vector
    if evt isa MousePress
        w = iomap.input
        if !(w isa WidgetTabbedPane)
            res = _route_active_tab(iomap, child_iomaps, evt)
            return _tab_prefix(res)
        end
        cox, coy = _content_offset(w)
        pairs = w.selector_element_pairs
        if !isempty(pairs)
            sel_pad = p.theme.tab_pad
            sizes = Tuple{Int,Int}[]
            tab_h = 0
            for pair in pairs
                tw, th = _text_size(p.measure, p.font, string(pair[1]))
                push!(sizes, (tw, th))
                tab_h = max(tab_h, th)
            end
            sel_h = tab_h + 2 * sel_pad
            tab_x = cox
            for (i, (tw, _)) in enumerate(sizes)
                rw = tw + 2 * sel_pad
                if evt.x >= tab_x && evt.x < tab_x + rw && evt.y >= coy && evt.y < coy + sel_h
                    return SelectTabOperation(w, i)
                end
                tab_x += rw
            end
        end
        return _tab_prefix(_route_active_tab(iomap, child_iomaps, evt))
    end
    if evt isa MouseScroll
        return _tab_prefix(_route_active_tab(iomap, child_iomaps, evt))
    end
    # Coordless events (KeyDown, KeyPress, …): forward to the active tab
    # only; the focused leaf produces an op, others return nothing.
    _tab_prefix(_route_active_tab(iomap, child_iomaps, evt))
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
    # Mouse events: translate coords into the tab's local frame and
    # hit-test before forwarding. Coordless events (KeyDown, KeyPress, …)
    # are forwarded as-is to the active tab's reader.
    child_evt = @event_case evt begin
        MousePress(button, x, y) => begin
            lx, ly = x - ox - Int(canvas.x), y - oy - Int(canvas.y)
            hit_element_at(canvas, lx, ly) === nothing && return nothing
            MousePress(button, lx, ly, evt.modifiers)
        end
        MouseScroll(dx, dy, x, y) => begin
            lx, ly = x - ox - Int(canvas.x), y - oy - Int(canvas.y)
            hit_element_at(canvas, lx, ly) === nothing && return nothing
            MouseScroll(dx, dy, lx, ly)
        end
        _ => evt
    end
    op = projection_read(cim.projection, cim, child_evt)
    op === nothing && return nothing
    (op, active_idx)
end

# The 1-based tab a tabbed pane's selection points at, or 0 when there is no
# tab selection. Accepts the forward-projected widget shape
# `selector_element_pairs[i].<rest>` (written by the printer when the document
# selection lands inside a tab) as well as the bare `[i]` shorthand a tab-strip
# click writes.
function _tab_index_from_selection(sel, n::Int)
    sel isa ConcreteReferencePath || return 0
    h = sel.head
    if h isa FieldReference && h.name == "selector_element_pairs"
        t = sel.tail
        (t isa ConcreteReferencePath && t.head isa RangeReference) || return 0
        i = t.head.start + 1
    elseif h isa RangeReference
        i = h.start + 1
    else
        return 0
    end
    1 <= i <= n ? i : 0
end

function _active_tab_index(w::WidgetTabbedPane, n::Int)
    n == 0 && return 0
    i = _tab_index_from_selection(getfield(w, :selection)[], n)
    i == 0 ? 1 : i
end

function _tab_prefix(res)
    res === nothing && return nothing
    op, idx = res
    _prepend_steps_to_op(op,
        (FieldReference("selector_element_pairs"), RangeReference(idx-1, idx)))
end

# Kept for back-compat with any external callers.
function _active_tab_children(iomap::ChildrenIoMap, child_iomaps::Vector)
    w = iomap.input
    w isa WidgetTabbedPane || return child_iomaps
    idx = _active_tab_index(w, length(child_iomaps))
    idx == 0 ? child_iomaps : child_iomaps[idx:idx]
end

# ── WidgetScrollPane ────────────────────────────────────────────────────────

function projection_print(p::WidgetScrollPaneToGraphicsCanvas, recursion, w::WidgetScrollPane, ctx)
    w.visible == false && return WidgetScrollPaneToGraphicsCanvasIoMap(p, w, _empty_canvas(), nothing)
    pos = w.position
    sz  = w.size
    px = pos isa Point2D ? _sc(Int(pos.x[])) : 0
    py = pos isa Point2D ? _sc(Int(pos.y[])) : 0
    # Viewport extent: prefer the parent-allocated extent on each axis
    # (from the context) so the pane fits its slot in a layout; fall back
    # to the widget's own `size` when the context didn't allocate. The
    # extent is held as a `Cell` so reads are deferred — the parent
    # layout may not have built its allocation cell yet when we recurse.
    tx, ty = _inset_total(w)
    avail_w = ctx.available_width
    avail_h = ctx.available_height
    vw_cell = avail_w !== nothing ?
              Cell(() -> Int32(max(0, Int(avail_w[]) - tx))) :
              Cell(Int32(sz isa Point2D ? Int(sz.x[]) : 400))
    vh_cell = avail_h !== nothing ?
              Cell(() -> Int32(max(0, Int(avail_h[]) - ty))) :
              Cell(Int32(sz isa Point2D ? Int(sz.y[]) : 300))
    cox, coy = _content_offset(w)
    scroll_cell = getfield(w, :scroll_position)
    inner_x = Cell(() -> begin sp = scroll_cell[]::Point2D; Int32(-Int(sp.x[])) end)
    inner_y = Cell(() -> begin sp = scroll_cell[]::Point2D; Int32(-Int(sp.y[])) end)
    elems = Any[]
    cfc = w.content_fill_color
    bgc = cfc isa StyleColor ? cfc : p.theme.background
    let (r, g, b, a) = _rgba(bgc)
        # Cell-backed rect so it tracks the viewport extent.
        push!(elems, GraphicsRect(Cell(Int32(cox)), Cell(Int32(coy)), vw_cell, vh_cell,
                                  Cell(UInt8(r)), Cell(UInt8(g)), Cell(UInt8(b)), Cell(UInt8(a)),
                                  Cell(Int32(0)), Cell(Int32(0)),
                                  Cell(Int32(0)), Cell(Int32(0)),
                                  Cell(Int32(0)),
                                  Cell(UInt8(0)), Cell(UInt8(0)), Cell(UInt8(0)), Cell(UInt8(0)),
                                  Cell(nothing)))
    end
    # Recurse into the content with the viewport extent on each axis — the
    # context cells are already deferred, so the recursion stays lazy.
    content_iomap = nothing
    content = w.content
    if content isa Document
        content_ctx = with_available_size(ctx; width=vw_cell, height=vh_cell)
        content_iomap = projection_print(recursion, recursion, content, content_ctx)
        inner_canvas = content_iomap.output::GraphicsCanvas
        inner_elems_cv = inner_canvas.elements
        push!(elems, GraphicsViewport(Cell(Int32(cox)), Cell(Int32(coy)),
                                      vw_cell, vh_cell,
                                      Cell(GraphicsCanvas(inner_x, inner_y, Int32(0), Int32(0),
                                                          inner_elems_cv isa CellVector ? inner_elems_cv : CellVector(Cell[Cell(inner_canvas)]),
                                                          layout_none, true, Cell(nothing))),
                                      Cell(nothing)))
    end
    WidgetScrollPaneToGraphicsCanvasIoMap(p, w, _make_canvas(px, py, elems), content_iomap)
end

function map_reference_forward(::WidgetScrollPaneToGraphicsCanvas, iomap, reference)
    return nothing
end

# The scroll pane wraps a single content document as its `.content` field.
# A path arriving from the content's reader is already in the content's
# input domain (the inner pipeline has already translated it); the scroll
# pane's contribution is just to prepend `.content` to re-root it in the
# scroll pane's own input domain.
function map_reference_backward(::WidgetScrollPaneToGraphicsCanvas, iomap::WidgetScrollPaneToGraphicsCanvasIoMap, reference)
    reference === nothing && return nothing
    ConcreteReferencePath(FieldReference("content"), reference)
end

function projection_read(p::WidgetScrollPaneToGraphicsCanvas, iomap::WidgetScrollPaneToGraphicsCanvasIoMap, evt)
    canvas = iomap.output
    @event_case evt begin
        MouseScroll(dx, dy, x, y) => begin
            # evt coords are already relative to canvas origin (parent routing subtracted position)
            hit_element_at(canvas, x, y) === nothing && return nothing
            _, scroll_step = p.measure("M", p.font)
            return dx != 0 && dy == 0 ?
                ScrollWidgetOperation(iomap.input, Point2D(-dx * scroll_step, 0)) :
                ScrollWidgetOperation(iomap.input, Point2D(0, -dy * scroll_step))
        end
    end
    # Forward other events (MousePress, KeyDown, KeyPress) to the wrapped
    # content. Coords for MousePress arrive relative to the scroll pane's
    # canvas origin (parent routing has already subtracted the pane's own
    # position); translate into the content's coordinate system by
    # subtracting the content origin (cox, coy) and adding the current
    # scroll offset. Any path-bearing op returned by the content's reader
    # is in the content's input domain; map it through this projection's
    # `map_reference_backward` to re-root it at `.content.<rest>` in the
    # scroll pane's input domain.
    content_iomap = iomap.content_iomap
    content_iomap === nothing && return nothing
    op = @event_case evt begin
        MousePress(button, x, y) => begin
            w = iomap.input
            cox, coy = _content_offset(w)
            sp = getfield(w, :scroll_position)[]::Point2D
            sx, sy = Int(sp.x[]), Int(sp.y[])
            lx, ly = x - cox + sx, y - coy + sy
            projection_read(content_iomap.projection, content_iomap,
                             MousePress(button, lx, ly, evt.modifiers))
        end
        _ => projection_read(content_iomap.projection, content_iomap, evt)
    end
    _retarget_op(p, iomap, op)
end

# ── WidgetToolbar ───────────────────────────────────────────────────────────

function projection_print(p::WidgetToolbarToGraphicsCanvas, recursion, w::WidgetToolbar, ctx)
    w.visible == false && return ChildrenIoMap(p, w, _empty_canvas(), Cell(Any[]))
    cox, coy = _content_offset(w)
    child_iomaps = Any[]
    elems = Any[]
    x_cursor = cox
    item_gap = p.theme.gap
    for item in w.elements
        item isa WidgetDocument || continue
        cim = projection_print(recursion, recursion, item, ctx)
        push!(child_iomaps, (x_cursor, coy, cim))
        push!(elems, _make_canvas(x_cursor, coy, Any[cim.output]))
        content = hasproperty(item, :content) ? item.content : nothing
        iw, _ = content !== nothing ? _text_size(p.measure, p.font, string(content)) :
                                      p.measure("    ", p.font)
        x_cursor += iw + item_gap
    end
    ChildrenIoMap(p, w, _make_canvas(0, 0, elems), Cell(child_iomaps))
end

function map_reference_forward(::WidgetToolbarToGraphicsCanvas, iomap, reference)
    return nothing
end

function map_reference_backward(::WidgetToolbarToGraphicsCanvas, iomap, reference)
    return nothing
end

function projection_read(::WidgetToolbarToGraphicsCanvas, iomap::ChildrenIoMap, evt)
    evt isa MouseScroll || return nothing
    _route_scroll_to_children(iomap.child_iomaps[]::Vector, evt)
end

# ── WidgetScrollBar ─────────────────────────────────────────────────────────

function projection_print(p::WidgetScrollBarToGraphicsCanvas, _, w::WidgetScrollBar, _)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    pos = w.position
    sz  = w.size
    px = pos isa Point2D ? _sc(Int(pos.x[])) : 0
    py = pos isa Point2D ? _sc(Int(pos.y[])) : 0
    bw = sz  isa Point2D ? Int(sz.x[])  : 200
    bh = sz  isa Point2D ? Int(sz.y[])  : 16
    cox, coy = _content_offset(w)
    tx, ty = _inset_total(w)
    cw = max(1, bw - tx)
    ch = max(1, bh - ty)
    elems = Any[]
    tr, tg, tb, ta = _rgba(p.theme.muted)
    trad = min(cw, ch) ÷ 2
    push!(elems, GraphicsRect(cox, coy, cw, ch, tr, tg, tb, ta, trad))
    value    = clamp(Float64(w.value),     0.0, 1.0)
    thumb_sz = clamp(Float64(w.thumb_size), 0.05, 1.0)
    hr, hg, hb, ha = _rgba(p.theme.border)
    if w.orientation === :horizontal
        tw = max(p.theme.thumb_min, Int(round(thumb_sz * cw)))
        tx_pos = cox + Int(round(value * (cw - tw)))
        push!(elems, GraphicsRect(tx_pos, coy, tw, ch, hr, hg, hb, ha, ch ÷ 2))
    else
        th = max(p.theme.thumb_min, Int(round(thumb_sz * ch)))
        ty_pos = coy + Int(round(value * (ch - th)))
        push!(elems, GraphicsRect(cox, ty_pos, cw, th, hr, hg, hb, ha, cw ÷ 2))
    end
    SimpleIoMap(p, w, _make_canvas(px, py, elems))
end

function map_reference_forward(::WidgetScrollBarToGraphicsCanvas, iomap, reference)
    return nothing
end

function map_reference_backward(::WidgetScrollBarToGraphicsCanvas, iomap, reference)
    return nothing
end

function projection_read(p::WidgetScrollBarToGraphicsCanvas, iomap::SimpleIoMap, evt)
    evt isa MousePress || return nothing
    w = iomap.input
    w isa WidgetScrollBar || return nothing
    sz  = w.size
    bw = sz isa Point2D ? Int(sz.x[]) : 200
    bh = sz isa Point2D ? Int(sz.y[]) : 16
    cox, coy = _content_offset(w)
    tx, ty = _inset_total(w)
    cw = max(1, bw - tx)
    ch = max(1, bh - ty)
    thumb_sz = clamp(Float64(w.thumb_size), 0.05, 1.0)
    if w.orientation === :horizontal
        tw = max(p.theme.thumb_min, Int(round(thumb_sz * cw)))
        new_value = clamp(Float64(evt.x - cox - div(tw, 2)) / max(1, cw - tw), 0.0, 1.0)
    else
        th = max(p.theme.thumb_min, Int(round(thumb_sz * ch)))
        new_value = clamp(Float64(evt.y - coy - div(th, 2)) / max(1, ch - th), 0.0, 1.0)
    end
    SetScrollBarValueOperation(w, new_value)
end

# ════════════════════════════════════════════════════════════════════════════
# Extension widgets — printer-only (no-op readers)
# ════════════════════════════════════════════════════════════════════════════

# A no-op reader trio shared by every extension widget (printer-only for now).
macro _printer_only(P)
    quote
        map_reference_forward(::$(esc(P)), iomap, reference) = nothing
        map_reference_backward(::$(esc(P)), iomap, reference) = nothing
        projection_read(::$(esc(P)), iomap, evt) = nothing
    end
end

# ── WidgetBadge ─────────────────────────────────────────────────────────────

struct WidgetBadgeToGraphicsCanvas <: Projection
    font::StyleFont
    measure::Function
    theme::WidgetTheme
end

function projection_print(p::WidgetBadgeToGraphicsCanvas, recursion, w::WidgetBadge, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    pos = w.position::Point2D
    th  = p.theme
    text = string(w.content)
    fill, fg, border = if w.variant === :secondary
        (th.secondary, th.secondary_foreground, nothing)
    elseif w.variant === :destructive
        (th.destructive, th.destructive_foreground, nothing)
    elseif w.variant === :outline
        (th.background, th.foreground, th.border)
    else
        (th.primary, th.primary_foreground, nothing)
    end
    pad_x, pad_y = _sc(th.badge_pad_x), _sc(th.badge_pad_y)
    tw, tht = _text_size(p.measure, th.font_small, text)
    cw, ch = tw + 2pad_x, tht + 2pad_y
    bw = border !== nothing ? max(1, _sc(th.border_width)) : 0
    elems = Any[]
    _push_panel!(elems, 0, 0, cw, ch; fill=fill, border=border, border_w=bw, radius=ch ÷ 2)
    fr, fg2, fb, fa = _rgbai(fg)
    push!(elems, GraphicsText(text, pad_x, (ch - tht) ÷ 2, th.font_small, fr, fg2, fb, fa))
    SimpleIoMap(p, w, _make_canvas(_origin(pos)..., cw, ch, elems))
end
@_printer_only WidgetBadgeToGraphicsCanvas

# ── WidgetSeparator ─────────────────────────────────────────────────────────

struct WidgetSeparatorToGraphicsCanvas <: Projection
    theme::WidgetTheme
end

function projection_print(p::WidgetSeparatorToGraphicsCanvas, recursion, w::WidgetSeparator, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    pos = w.position::Point2D
    L = _sc(Int(w.length))
    r, g, b, a = _rgba(p.theme.border)
    thick = max(1, _sc(p.theme.border_width))
    elems = Any[]
    if w.orientation === :vertical
        push!(elems, GraphicsLine(0, 0, 0, L, r, g, b, a; width=thick))
        SimpleIoMap(p, w, _make_canvas(_origin(pos)..., thick, L, elems))
    else
        push!(elems, GraphicsLine(0, 0, L, 0, r, g, b, a; width=thick))
        SimpleIoMap(p, w, _make_canvas(_origin(pos)..., L, thick, elems))
    end
end
@_printer_only WidgetSeparatorToGraphicsCanvas

# ── WidgetCard ──────────────────────────────────────────────────────────────

struct WidgetCardToGraphicsCanvas <: Projection
    font::StyleFont
    measure::Function
    theme::WidgetTheme
end

function projection_print(p::WidgetCardToGraphicsCanvas, recursion, w::WidgetCard, ctx)
    w.visible == false && return ChildrenIoMap(p, w, _empty_canvas(), Cell(Any[]))
    pos = w.position::Point2D
    th  = p.theme
    pad = _sc(th.card_pad)
    elems = Any[]
    child_iomaps = Any[]
    mw = 0   # widest content row, to size the card to its content
    y = pad
    if w.title !== nothing
        ttxt = string(w.title)
        tww, thh = _text_size(p.measure, th.font_bold, ttxt)
        _push_text!(elems, th.font_bold, ttxt, pad, y, _rgba(th.foreground))
        mw = max(mw, tww); y += thh + _sc(th.card_title_gap)
    end
    if w.description !== nothing
        dtxt = string(w.description)
        dww, dhh = _text_size(p.measure, th.font_small, dtxt)
        _push_text!(elems, th.font_small, dtxt, pad, y, _rgba(th.muted_foreground))
        mw = max(mw, dww); y += dhh + _sc(th.card_gap)
    end
    content = w.content
    if content isa WidgetDocument
        cim = projection_print(recursion, recursion, content, ctx)
        push!(child_iomaps, (pad, y, cim))
        push!(elems, _make_canvas(pad, y, Any[cim.output]))
        inner = cim.output
        inner isa GraphicsCanvas && (mw = max(mw, Int(inner.w[])))
        y += inner isa GraphicsCanvas ? Int(inner.h[]) + _sc(th.card_gap) : _sc(th.card_gap)
    elseif content isa AbstractString
        cww, chh = _text_size(p.measure, th.font, content)
        _push_text!(elems, th.font, content, pad, y, _rgba(th.card_foreground))
        mw = max(mw, cww); y += chh + _sc(th.card_gap)
    end
    if w.footer !== nothing
        ftxt = string(w.footer)
        fww, fhh = _text_size(p.measure, th.font_small, ftxt)
        _push_text!(elems, th.font_small, ftxt, pad, y, _rgba(th.muted_foreground))
        mw = max(mw, fww); y += fhh
    end
    cw = _resolve_width(ctx, _sc(Int(w.width)), mw + 2pad)
    ch = y + pad
    # Card surface drawn first (behind content).
    surface = Any[]
    _push_panel!(surface, 0, 0, cw, ch; fill=th.card, border=th.border,
                 border_w=max(1, _sc(th.border_width)), radius=_sc(th.radius))
    append!(surface, elems)
    ChildrenIoMap(p, w, _make_canvas(_origin(pos)..., cw, ch, surface), Cell(child_iomaps))
end
@_printer_only WidgetCardToGraphicsCanvas

# ── WidgetSwitch ────────────────────────────────────────────────────────────

struct WidgetSwitchToGraphicsCanvas <: Projection
    theme::WidgetTheme
end

function projection_print(p::WidgetSwitchToGraphicsCanvas, recursion, w::WidgetSwitch, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    pos = w.position::Point2D
    on  = w.checked === true
    h, wd = _sc(p.theme.switch_h), _sc(p.theme.switch_w)
    elems = Any[]
    track = on ? p.theme.primary : p.theme.track_off
    tr, tg, tb, ta = _rgba(track)
    push!(elems, GraphicsRect(0, 0, wd, h, tr, tg, tb, ta, h ÷ 2))
    pad = _sc(p.theme.switch_pad)
    kr  = (h - 2pad) ÷ 2
    kcx = on ? (wd - pad - kr) : (pad + kr)
    kr1, kg1, kb1, ka1 = _rgbai(color_white)
    push!(elems, GraphicsCircle(kcx, h ÷ 2, kr, kr1, kg1, kb1, ka1;
                                border_width=max(1, _sc(p.theme.border_width)), border_color=_rgbai(p.theme.border)))
    SimpleIoMap(p, w, _make_canvas(_origin(pos)..., wd, h, elems))
end
@_printer_only WidgetSwitchToGraphicsCanvas

# ── WidgetProgress ──────────────────────────────────────────────────────────

struct WidgetProgressToGraphicsCanvas <: Projection
    theme::WidgetTheme
end

function projection_print(p::WidgetProgressToGraphicsCanvas, recursion, w::WidgetProgress, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    pos = w.position::Point2D
    value = clamp(Float64(w.value), 0.0, 1.0)
    W, H = _resolve_width(ctx, _sc(Int(w.width))), _sc(p.theme.progress_h)
    elems = Any[]
    tr, tg, tb, ta = _rgba(p.theme.muted)
    push!(elems, GraphicsRect(0, 0, W, H, tr, tg, tb, ta, H ÷ 2))
    fw = round(Int, value * W)
    if fw > 0
        pr, pg, pb, pa = _rgba(p.theme.primary)
        push!(elems, GraphicsRect(0, 0, fw, H, pr, pg, pb, pa, H ÷ 2))
    end
    SimpleIoMap(p, w, _make_canvas(_origin(pos)..., W, H, elems))
end
@_printer_only WidgetProgressToGraphicsCanvas

# ── WidgetSlider ────────────────────────────────────────────────────────────

struct WidgetSliderToGraphicsCanvas <: Projection
    theme::WidgetTheme
end

function projection_print(p::WidgetSliderToGraphicsCanvas, recursion, w::WidgetSlider, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    pos = w.position::Point2D
    value = clamp(Float64(w.value), 0.0, 1.0)
    W, H = _resolve_width(ctx, _sc(Int(w.width))), _sc(p.theme.slider_h)
    cy = H ÷ 2
    tk = _sc(p.theme.track)
    fw = round(Int, value * W)
    elems = Any[]
    tr, tg, tb, ta = _rgba(p.theme.muted)
    push!(elems, GraphicsRect(0, cy - tk ÷ 2, W, tk, tr, tg, tb, ta, tk ÷ 2))
    pr, pg, pb, pa = _rgba(p.theme.primary)
    fw > 0 && push!(elems, GraphicsRect(0, cy - tk ÷ 2, fw, tk, pr, pg, pb, pa, tk ÷ 2))
    kr1, kg1, kb1, ka1 = _rgbai(color_white)
    push!(elems, GraphicsCircle(fw, cy, _sc(p.theme.knob_radius), kr1, kg1, kb1, ka1;
                                border_width=max(1, _sc(p.theme.stroke)), border_color=_rgbai(p.theme.primary)))
    SimpleIoMap(p, w, _make_canvas(_origin(pos)..., W, H, elems))
end
@_printer_only WidgetSliderToGraphicsCanvas

# ── WidgetRadioGroup ────────────────────────────────────────────────────────

struct WidgetRadioGroupToGraphicsCanvas <: Projection
    font::StyleFont
    measure::Function
    theme::WidgetTheme
end

function projection_print(p::WidgetRadioGroupToGraphicsCanvas, recursion, w::WidgetRadioGroup, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    pos = w.position::Point2D
    th  = p.theme
    selected = Int(w.selected)
    diam = _sc(th.radio_size)
    gap  = _sc(th.radio_gap)
    row_gap = _sc(th.row_gap)
    elems = Any[]
    y = 0
    max_w = 0
    for (i, opt) in enumerate(w.options)
        label = string(opt)
        lw, lh = _text_size(p.measure, th.font, label)
        rh = max(diam, lh)
        cyr = y + rh ÷ 2
        if i == selected
            push!(elems, GraphicsCircle(diam ÷ 2, cyr, diam ÷ 2, _rgbai(th.background)...;
                                        border_width=max(1, _sc(th.stroke)), border_color=_rgbai(th.primary)))
            push!(elems, GraphicsCircle(diam ÷ 2, cyr, _sc(th.radio_dot), _rgbai(th.primary)...))
        else
            push!(elems, GraphicsCircle(diam ÷ 2, cyr, diam ÷ 2, _rgbai(th.background)...;
                                        border_width=max(1, _sc(th.stroke)), border_color=_rgbai(th.input)))
        end
        _push_text!(elems, th.font, label, diam + gap, y + (rh - lh) ÷ 2, _rgba(th.foreground))
        max_w = max(max_w, diam + gap + lw)
        y += rh + row_gap
    end
    SimpleIoMap(p, w, _make_canvas(_origin(pos)..., max_w, max(0, y - row_gap), elems))
end
@_printer_only WidgetRadioGroupToGraphicsCanvas

# ── WidgetAvatar ────────────────────────────────────────────────────────────

struct WidgetAvatarToGraphicsCanvas <: Projection
    font::StyleFont
    measure::Function
    theme::WidgetTheme
end

function projection_print(p::WidgetAvatarToGraphicsCanvas, recursion, w::WidgetAvatar, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    pos = w.position::Point2D
    th  = p.theme
    sz  = _sc(Int(w.size))
    r   = sz ÷ 2
    initials = string(w.initials)
    elems = Any[]
    push!(elems, GraphicsCircle(r, r, r, _rgbai(th.muted)...))
    iw, ih = _text_size(p.measure, th.font, initials)
    fr, fg, fb, fa = _rgbai(th.muted_foreground)
    push!(elems, GraphicsText(initials, r - iw ÷ 2, r - ih ÷ 2, th.font, fr, fg, fb, fa))
    SimpleIoMap(p, w, _make_canvas(_origin(pos)..., sz, sz, elems))
end
@_printer_only WidgetAvatarToGraphicsCanvas

# ── WidgetAlert ─────────────────────────────────────────────────────────────

struct WidgetAlertToGraphicsCanvas <: Projection
    font::StyleFont
    measure::Function
    theme::WidgetTheme
end

function projection_print(p::WidgetAlertToGraphicsCanvas, recursion, w::WidgetAlert, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    pos = w.position::Point2D
    th  = p.theme
    destructive = w.variant === :destructive
    pad = _sc(th.alert_pad)
    title_fg = destructive ? th.destructive : th.foreground
    border   = destructive ? th.destructive : th.border
    elems = Any[]
    mw = 0
    y = pad
    ttxt = string(w.title)
    tww, thh = _text_size(p.measure, th.font_bold, ttxt)
    _push_text!(elems, th.font_bold, ttxt, pad, y, _rgba(title_fg))
    mw = max(mw, tww); y += thh
    if w.description !== nothing
        y += _sc(th.alert_gap)
        dtxt = string(w.description)
        dww, dhh = _text_size(p.measure, th.font_small, dtxt)
        _push_text!(elems, th.font_small, dtxt, pad, y, _rgba(th.muted_foreground))
        mw = max(mw, dww); y += dhh
    end
    W  = _resolve_width(ctx, _sc(Int(w.width)), mw + 2pad)
    ch = y + pad
    surface = Any[]
    _push_panel!(surface, 0, 0, W, ch; fill=th.background, border=border,
                 border_w=max(1, _sc(th.border_width)), radius=_sc(th.radius))
    append!(surface, elems)
    SimpleIoMap(p, w, _make_canvas(_origin(pos)..., W, ch, surface))
end
@_printer_only WidgetAlertToGraphicsCanvas

# ── WidgetSkeleton ──────────────────────────────────────────────────────────

struct WidgetSkeletonToGraphicsCanvas <: Projection
    theme::WidgetTheme
end

function projection_print(p::WidgetSkeletonToGraphicsCanvas, recursion, w::WidgetSkeleton, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    pos = w.position::Point2D
    W, H = _resolve_width(ctx, _sc(Int(w.width))), _sc(Int(w.height))
    r, g, b, a = _rgba(p.theme.muted)
    elems = Any[GraphicsRect(0, 0, W, H, r, g, b, a, _sc(p.theme.skeleton_radius))]
    SimpleIoMap(p, w, _make_canvas(_origin(pos)..., W, H, elems))
end
@_printer_only WidgetSkeletonToGraphicsCanvas

# Push a small chevron (two AA strokes) centered at (cx, cy). `dir` ∈ :down :right.
# `stroke` is the line width; callers pass the theme's icon stroke.
function _push_chevron!(elems::Vector, cx::Int, cy::Int, s::Int, dir::Symbol, color::StyleColor;
                        stroke::Int=max(1, _sc(2)))
    r, g, b, a = _rgba(color)
    w = stroke
    if dir === :right
        push!(elems, GraphicsLine(cx - s ÷ 2, cy - s, cx + s ÷ 2, cy, r, g, b, a; width=w))
        push!(elems, GraphicsLine(cx + s ÷ 2, cy, cx - s ÷ 2, cy + s, r, g, b, a; width=w))
    else
        push!(elems, GraphicsLine(cx - s, cy - s ÷ 2, cx, cy + s ÷ 2, r, g, b, a; width=w))
        push!(elems, GraphicsLine(cx, cy + s ÷ 2, cx + s, cy - s ÷ 2, r, g, b, a; width=w))
    end
end

# ── WidgetToggle ────────────────────────────────────────────────────────────

struct WidgetToggleToGraphicsCanvas <: Projection
    font::StyleFont
    measure::Function
    theme::WidgetTheme
end

function projection_print(p::WidgetToggleToGraphicsCanvas, recursion, w::WidgetToggle, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    pos = w.position::Point2D
    th  = p.theme
    text = string(w.content)
    on  = w.pressed === true
    pad_x, pad_y = _sc(th.pad_x), _sc(th.pad_y)
    tw, tht = _text_size(p.measure, p.font, text)
    cw, ch = tw + 2pad_x, tht + 2pad_y
    fill   = on ? th.accent : th.background
    fg     = on ? th.accent_foreground : th.foreground
    border = on ? nothing : th.border
    bw = border !== nothing ? max(1, _sc(th.border_width)) : 0
    elems = Any[]
    _push_panel!(elems, 0, 0, cw, ch; fill=fill, border=border, border_w=bw, radius=_sc(th.radius))
    fr, fg2, fb, fa = _rgbai(fg)
    push!(elems, GraphicsText(text, (cw - tw) ÷ 2, (ch - tht) ÷ 2, p.font, fr, fg2, fb, fa))
    SimpleIoMap(p, w, _make_canvas(_origin(pos)..., cw, ch, elems))
end
@_printer_only WidgetToggleToGraphicsCanvas

# ── WidgetToggleGroup ───────────────────────────────────────────────────────

struct WidgetToggleGroupToGraphicsCanvas <: Projection
    font::StyleFont
    measure::Function
    theme::WidgetTheme
end

function projection_print(p::WidgetToggleGroupToGraphicsCanvas, recursion, w::WidgetToggleGroup, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    pos = w.position::Point2D
    th  = p.theme
    selected = Int(w.selected)
    pad_x, pad_y = _sc(th.pad_x), _sc(th.pad_y)
    labels = [string(o) for o in w.options]
    _, mh = _text_size(p.measure, p.font, "M")
    seg_ws = [(_text_size(p.measure, p.font, l)[1] + 2pad_x) for l in labels]
    ch = mh + 2pad_y
    cw = sum(seg_ws; init=0)
    radius = _sc(th.radius)
    elems = Any[]
    # Outer container (muted track + border).
    _push_panel!(elems, 0, 0, cw, ch; fill=th.muted, border=th.border,
                 border_w=max(1, _sc(th.border_width)), radius=radius)
    x = 0
    for i in eachindex(labels)
        sw = seg_ws[i]
        if i == selected
            _push_panel!(elems, x + _sc(th.seg_inset), _sc(th.seg_inset),
                         sw - _sc(2 * th.seg_inset), ch - _sc(2 * th.seg_inset);
                         fill=th.background, radius=max(0, radius - _sc(th.seg_inset)))
        end
        tw, tht = _text_size(p.measure, p.font, labels[i])
        fg = i == selected ? th.foreground : th.muted_foreground
        fr, fg2, fb, fa = _rgbai(fg)
        push!(elems, GraphicsText(labels[i], x + (sw - tw) ÷ 2, (ch - tht) ÷ 2, p.font, fr, fg2, fb, fa))
        x += sw
    end
    SimpleIoMap(p, w, _make_canvas(_origin(pos)..., cw, ch, elems))
end
@_printer_only WidgetToggleGroupToGraphicsCanvas

# ── WidgetSelect ────────────────────────────────────────────────────────────

struct WidgetSelectToGraphicsCanvas <: Projection
    font::StyleFont
    measure::Function
    theme::WidgetTheme
end

function projection_print(p::WidgetSelectToGraphicsCanvas, recursion, w::WidgetSelect, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    pos = w.position::Point2D
    th  = p.theme
    text = string(w.value)
    pad_x, pad_y = _sc(th.pad_x), _sc(th.pad_y)
    tw, tht = _text_size(p.measure, p.font, text)
    # Fit the value text, a gap, the trailing chevron and both paddings.
    content_min = 2pad_x + tw + _sc(th.gap) + 2 * _sc(th.chevron)
    W = _resolve_width(ctx, _sc(Int(w.width)), content_min)
    ch = tht + 2pad_y
    elems = Any[]
    _push_panel!(elems, 0, 0, W, ch; fill=th.background, border=th.input,
                 border_w=max(1, _sc(th.border_width)), radius=_sc(th.radius))
    fr, fg, fb, fa = _rgbai(th.foreground)
    push!(elems, GraphicsText(text, pad_x, (ch - tht) ÷ 2, p.font, fr, fg, fb, fa))
    _push_chevron!(elems, W - pad_x - _sc(th.chevron), ch ÷ 2, _sc(th.chevron), :down,
                   th.muted_foreground; stroke=max(1, _sc(th.stroke)))
    SimpleIoMap(p, w, _make_canvas(_origin(pos)..., W, ch, elems))
end
@_printer_only WidgetSelectToGraphicsCanvas

# ── WidgetTextarea ──────────────────────────────────────────────────────────

struct WidgetTextareaToGraphicsCanvas <: Projection
    font::StyleFont
    measure::Function
    theme::WidgetTheme
end

function projection_print(p::WidgetTextareaToGraphicsCanvas, recursion, w::WidgetTextarea, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    pos = w.position::Point2D
    th  = p.theme
    pad_x, pad_y = _sc(th.pad_x), _sc(th.pad_y)
    lines = split(string(w.content), '\n')
    _, lh = _text_size(p.measure, p.font, "M")
    nrows = max(Int(w.rows), length(lines))
    H = nrows * lh + 2pad_y
    maxlw = isempty(lines) ? 0 : maximum(_text_size(p.measure, p.font, String(l))[1] for l in lines)
    W = _resolve_width(ctx, _sc(Int(w.width)), maxlw + 2pad_x)
    elems = Any[]
    _push_panel!(elems, 0, 0, W, H; fill=th.background, border=th.input,
                 border_w=max(1, _sc(th.border_width)), radius=_sc(th.radius))
    fr, fg, fb, fa = _rgbai(th.foreground)
    for (i, line) in enumerate(lines)
        push!(elems, GraphicsText(String(line), pad_x, pad_y + (i - 1) * lh, p.font, fr, fg, fb, fa))
    end
    SimpleIoMap(p, w, _make_canvas(_origin(pos)..., W, H, elems))
end
@_printer_only WidgetTextareaToGraphicsCanvas

# ── WidgetAccordion ─────────────────────────────────────────────────────────

struct WidgetAccordionToGraphicsCanvas <: Projection
    font::StyleFont
    measure::Function
    theme::WidgetTheme
end

function projection_print(p::WidgetAccordionToGraphicsCanvas, recursion, w::WidgetAccordion, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    pos = w.position::Point2D
    th  = p.theme
    expanded = Int(w.expanded)
    pad_x, pad_y = _sc(th.pad_x), _sc(th.accordion_pad_y)
    # Size to content: widest title (leaving room for the trailing chevron) and
    # the widest visible (expanded) body. The authored width is the minimum.
    title_min = 0; body_min = 0
    for (i, item) in enumerate(w.items)
        title_min = max(title_min, _text_size(p.measure, th.font_bold, string(item[1]))[1])
        if i == expanded && length(item) >= 2
            body_min = max(body_min, _text_size(p.measure, th.font_small, string(item[2]))[1])
        end
    end
    content_min = max(2pad_x + title_min + _sc(th.gap) + 2 * _sc(th.chevron),
                      2pad_x + body_min)
    W = _resolve_width(ctx, _sc(Int(w.width)), content_min)
    elems = Any[]
    y = 0
    brc = _rgba(th.border)
    for (i, item) in enumerate(w.items)
        title = string(item[1])
        body  = length(item) >= 2 ? string(item[2]) : ""
        _, hh = _text_size(p.measure, th.font_bold, title)
        row_h = hh + 2pad_y
        fr, fg, fb, fa = _rgbai(th.foreground)
        push!(elems, GraphicsText(title, pad_x, y + pad_y, th.font_bold, fr, fg, fb, fa))
        _push_chevron!(elems, W - pad_x - _sc(th.chevron), y + row_h ÷ 2, _sc(th.chevron),
                       i == expanded ? :down : :right, th.muted_foreground; stroke=max(1, _sc(th.stroke)))
        y += row_h
        if i == expanded && !isempty(body)
            _, bh = _text_size(p.measure, th.font_small, body)
            mr, mg, mb, ma = _rgbai(th.muted_foreground)
            push!(elems, GraphicsText(body, pad_x, y + _sc(th.accordion_body_gap), th.font_small, mr, mg, mb, ma))
            y += bh + pad_y
        end
        push!(elems, GraphicsLine(0, y, W, y, brc[1], brc[2], brc[3], brc[4]; width=max(1, _sc(th.border_width))))
    end
    SimpleIoMap(p, w, _make_canvas(_origin(pos)..., W, y, elems))
end
@_printer_only WidgetAccordionToGraphicsCanvas

# ── WidgetTable ─────────────────────────────────────────────────────────────

struct WidgetTableToGraphicsCanvas <: Projection
    font::StyleFont
    measure::Function
    theme::WidgetTheme
end

function projection_print(p::WidgetTableToGraphicsCanvas, recursion, w::WidgetTable, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    pos = w.position::Point2D
    th  = p.theme
    headers = [string(h) for h in w.headers]
    rows = [Any[c for c in r] for r in w.rows]
    ncol = length(headers)
    cpx, cpy = _sc(th.table_pad_x), _sc(th.table_pad_y)
    _, lh = _text_size(p.measure, p.font, "M")
    row_h = lh + 2cpy
    # Column widths from header + body content.
    colw = zeros(Int, ncol)
    for j in 1:ncol
        wj = _text_size(p.measure, th.font_small, headers[j])[1]
        for r in rows
            j <= length(r) && (wj = max(wj, _text_size(p.measure, p.font, string(r[j]))[1]))
        end
        colw[j] = wj + 2cpx
    end
    W = sum(colw; init=0)
    elems = Any[]
    brc = _rgba(th.border)
    # Header row (muted foreground) + underline.
    x = 0
    for j in 1:ncol
        mr, mg, mb, ma = _rgbai(th.muted_foreground)
        push!(elems, GraphicsText(headers[j], x + cpx, cpy, th.font_small, mr, mg, mb, ma))
        x += colw[j]
    end
    y = row_h
    push!(elems, GraphicsLine(0, y, W, y, brc[1], brc[2], brc[3], brc[4]; width=max(1, _sc(th.border_width))))
    # Body rows.
    fr, fg, fb, fa = _rgbai(th.foreground)
    for r in rows
        x = 0
        for j in 1:ncol
            cell = j <= length(r) ? string(r[j]) : ""
            push!(elems, GraphicsText(cell, x + cpx, y + cpy, p.font, fr, fg, fb, fa))
            x += colw[j]
        end
        y += row_h
        push!(elems, GraphicsLine(0, y, W, y, brc[1], brc[2], brc[3], brc[4]; width=max(1, _sc(th.border_width))))
    end
    SimpleIoMap(p, w, _make_canvas(_origin(pos)..., W, y, elems))
end
@_printer_only WidgetTableToGraphicsCanvas

# ── WidgetTree ──────────────────────────────────────────────────────────────

struct WidgetTreeToGraphicsCanvas <: Projection
    font::StyleFont
    measure::Function
    theme::WidgetTheme
end

# A node is either a leaf label (String) or a (label, children::Vector) tuple.
_tree_children(node) = (node isa Tuple && length(node) >= 2 && node[2] isa AbstractVector) ? node[2] : nothing
_tree_label(node)    = node isa Tuple ? string(node[1]) : string(node)

function projection_print(p::WidgetTreeToGraphicsCanvas, recursion, w::WidgetTree, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    pos = w.position::Point2D
    th  = p.theme
    indent, chev_w = _sc(th.tree_indent), _sc(th.tree_chevron)
    _, lh = _text_size(p.measure, p.font, "M")
    row_h = lh + 2 * _sc(th.tree_row_pad)
    elems = Any[]
    maxw = Ref(0)
    yref = Ref(0)
    fr, fg, fb, fa = _rgbai(th.foreground)
    function walk(node, depth)
        x = depth * indent
        kids = _tree_children(node)
        label = _tree_label(node)
        if kids !== nothing && !isempty(kids)
            _push_chevron!(elems, x + chev_w ÷ 2, yref[] + row_h ÷ 2, _sc(th.chevron), :down,
                           th.muted_foreground; stroke=max(1, _sc(th.stroke)))
        end
        lw, _ = _text_size(p.measure, p.font, label)
        push!(elems, GraphicsText(label, x + chev_w, yref[] + _sc(th.tree_row_pad), p.font, fr, fg, fb, fa))
        maxw[] = max(maxw[], x + chev_w + lw)
        yref[] += row_h
        if kids !== nothing
            for c in kids
                walk(c, depth + 1)
            end
        end
    end
    for n in w.roots
        walk(n, 0)
    end
    SimpleIoMap(p, w, _make_canvas(_origin(pos)..., maxw[], yref[], elems))
end
@_printer_only WidgetTreeToGraphicsCanvas

# ── Factory ────────────────────────────────────────────────────────────────

"""
    WidgetToGraphics(font; measure, theme=widget_theme_light(font=font))

Build a recursive type-dispatching projection that maps any `WidgetDocument`
subtree to a `GraphicsCanvas`. `measure(text, font) -> (width, height)` is
used for all text sizing. The `theme` ([`WidgetTheme`](@ref)) is the single
source of truth for colors, radius, and spacing. Defaults to the light theme.
"""
function WidgetToGraphics(font::StyleFont; measure::Function,
                          theme::WidgetTheme=widget_theme_light(font=font))
    TypeDispatchingProjection(
        WidgetLabel      => WidgetLabelToGraphicsCanvas(font, measure, theme),
        WidgetText       => WidgetTextToGraphicsCanvas(font, measure, theme),
        WidgetCheckbox   => WidgetCheckboxToGraphicsCanvas(font, measure, theme),
        WidgetButton     => WidgetButtonToGraphicsCanvas(font, measure, theme),
        WidgetTooltip    => WidgetTooltipToGraphicsCanvas(font, measure, theme),
        WidgetMenu       => WidgetMenuToGraphicsCanvas(font, measure, theme),
        WidgetMenuItem   => WidgetMenuItemToGraphicsCanvas(font, measure, theme),
        WidgetComposite  => WidgetCompositeToGraphicsCanvas(),
        WidgetShell      => WidgetShellToGraphicsCanvas(font, measure, theme),
        WidgetTitlePane  => WidgetTitlePaneToGraphicsCanvas(font, measure, theme),
        WidgetSplitPane  => WidgetSplitPaneToGraphicsCanvas(theme),
        WidgetTabbedPane => WidgetTabbedPaneToGraphicsCanvas(font, measure, theme),
        WidgetScrollPane => WidgetScrollPaneToGraphicsCanvas(font, measure, theme),
        WidgetToolbar    => WidgetToolbarToGraphicsCanvas(font, measure, theme),
        WidgetScrollBar  => WidgetScrollBarToGraphicsCanvas(theme),
        WidgetBadge      => WidgetBadgeToGraphicsCanvas(font, measure, theme),
        WidgetSeparator  => WidgetSeparatorToGraphicsCanvas(theme),
        WidgetCard       => WidgetCardToGraphicsCanvas(font, measure, theme),
        WidgetSwitch     => WidgetSwitchToGraphicsCanvas(theme),
        WidgetProgress   => WidgetProgressToGraphicsCanvas(theme),
        WidgetSlider     => WidgetSliderToGraphicsCanvas(theme),
        WidgetRadioGroup => WidgetRadioGroupToGraphicsCanvas(font, measure, theme),
        WidgetAvatar     => WidgetAvatarToGraphicsCanvas(font, measure, theme),
        WidgetAlert      => WidgetAlertToGraphicsCanvas(font, measure, theme),
        WidgetSkeleton   => WidgetSkeletonToGraphicsCanvas(theme),
        WidgetToggle      => WidgetToggleToGraphicsCanvas(font, measure, theme),
        WidgetToggleGroup => WidgetToggleGroupToGraphicsCanvas(font, measure, theme),
        WidgetSelect      => WidgetSelectToGraphicsCanvas(font, measure, theme),
        WidgetTextarea    => WidgetTextareaToGraphicsCanvas(font, measure, theme),
        WidgetAccordion   => WidgetAccordionToGraphicsCanvas(font, measure, theme),
        WidgetTable       => WidgetTableToGraphicsCanvas(font, measure, theme),
        WidgetTree        => WidgetTreeToGraphicsCanvas(font, measure, theme),
    )
end

# ── WidgetScrollPaneToGraphicsViewport ─────────────────────────────────────

struct WidgetScrollPaneToGraphicsViewportIoMap <: IoMap
    projection::Any
    input::WidgetScrollPane
    output::GraphicsCanvas
    content_iomap::Any
end

"""
    WidgetScrollPaneToGraphicsViewport(font, measure)

Projects a `WidgetScrollPane` to a `GraphicsViewport`. The content inside
the scroll pane is projected via the recursion argument. `measure` is
used to determine the scroll delta for mouse scroll events.
"""
struct WidgetScrollPaneToGraphicsViewport <: Projection
    font::StyleFont
    measure::Function
end

function projection_print(p::WidgetScrollPaneToGraphicsViewport, recursion, w::WidgetScrollPane, ctx)
    content_iomap = projection_print(recursion, recursion, w.content, ctx)
    content_output = content_iomap.output::GraphicsCanvas

    pos = w.position
    sz  = w.size
    bx = pos isa Point2D ? _sc(Int(pos.x[])) : 0
    by = pos isa Point2D ? _sc(Int(pos.y[])) : 0
    vw = sz isa Point2D ? Int(sz.x[]) : 400
    vh = sz isa Point2D ? Int(sz.y[]) : 300
    scroll_cell = getfield(w, :scroll_position)
    inner_x = Cell(() -> begin sp = scroll_cell[]::Point2D; Int32(-Int(sp.x[])) end)
    inner_y = Cell(() -> begin sp = scroll_cell[]::Point2D; Int32(-Int(sp.y[])) end)

    inner_canvas = GraphicsCanvas(inner_x, inner_y, Cell(Int32(0)), Cell(Int32(0)),
                                  content_output.elements,
                                  content_output.layout,
                                  content_output.overlapping_elements,
                                  Cell(nothing))
    viewport = GraphicsViewport(bx, by, vw, vh, inner_canvas)
    output = GraphicsCanvas([viewport])

    WidgetScrollPaneToGraphicsViewportIoMap(p, w, output, content_iomap)
end

function projection_read(p::WidgetScrollPaneToGraphicsViewport, iomap::WidgetScrollPaneToGraphicsViewportIoMap, evt)
    if evt isa MouseScroll
        mx, my = evt.x, evt.y
        hit_element_at(iomap.output, mx, my) === nothing && return nothing
        _, scroll_step = p.measure("M", p.font)
        if evt.dx != 0 && evt.dy == 0
            return ScrollWidgetOperation(iomap.input, Point2D(-evt.dx * scroll_step, 0))
        else
            return ScrollWidgetOperation(iomap.input, Point2D(0, -evt.dy * scroll_step))
        end
    end
    content_iomap = iomap.content_iomap
    content_iomap === nothing && return nothing
    op = projection_read(content_iomap.projection, content_iomap, evt)
    return _retarget_op(p, iomap, op)
end

function map_reference_forward(::WidgetScrollPaneToGraphicsViewport, iomap, reference)
    return nothing
end

function map_reference_backward(::WidgetScrollPaneToGraphicsViewport, iomap::WidgetScrollPaneToGraphicsViewportIoMap, reference)
    reference === nothing && return nothing
    ConcreteReferencePath(FieldReference("content"), reference)
end

function map_reference_backward(::WidgetScrollPaneToGraphicsViewport, iomap, reference)
    return nothing
end

end # module
