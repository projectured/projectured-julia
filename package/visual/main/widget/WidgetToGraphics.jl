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

import ..CellModule: Cell, set_cell_function!
import ..ClockModule: get_time, get_reactive_time, get_wall_clock
import ..ProjectionApiModule: print_document, print_child, read_intent,
                               map_reference_forward, map_reference_backward, Projection
import ..IntentModule: Intent
import ..ProjectionModule: var"@projection"
import ..DocumentApiModule: Document
import ..ColorModule: StyleColor,
                      color_white, color_zinc_50, color_zinc_100, color_zinc_200,
                      color_zinc_300, color_zinc_400, color_zinc_500, color_zinc_600,
                      color_zinc_700, color_zinc_800, color_zinc_900, color_zinc_950,
                      color_slate_50, color_slate_100, color_slate_200, color_slate_300,
                      color_slate_400, color_slate_500, color_slate_700, color_slate_800,
                      color_slate_900, color_slate_950,
                      color_indigo_100, color_indigo_200, color_indigo_400, color_indigo_500,
                      color_indigo_600, color_indigo_700, color_indigo_950,
                      color_destructive, color_destructive_fg
import ..WidgetModule: WidgetDocument, WidgetInsertion, WidgetLabel, WidgetText, WidgetCheckbox,
                       WidgetButton, WidgetTooltip, WidgetContextMenu, WidgetDialog, WidgetMenu, WidgetMenuItem,
                       WidgetComposite, WidgetShell, WidgetTitlePane, WidgetSplitPane,
                       WidgetTabbedPane, WidgetTabPage, WidgetScrollPane, WidgetTransformPane, WidgetToolbar, WidgetStatusBar, WidgetScrollBar,
                       WidgetBadge, WidgetSeparator, WidgetCard, WidgetSwitch, WidgetProgress,
                       WidgetSlider, WidgetRadioGroup, WidgetAvatar, WidgetAlert, WidgetSkeleton,
                       WidgetToggle, WidgetToggleGroup, WidgetSelect, WidgetOption, WidgetTextarea, WidgetAccordion, WidgetAccordionItem,
                       WidgetSpinBox, WidgetList,
                       WidgetTable, WidgetTree, WidgetTreeNode,
                       Inset, Point2D, inset_default,
                       SelectTabOperation,
                       StartSplitterDragOperation, ResizeSplitPaneOperation, EndSplitterDragOperation,
                       InvokeWidgetActionOperation,
                       Action, InvokeActionOperation, action_shortcut_matches,
                       first_focusable_path, last_focusable_path, _next_focusable_in
import ..CollectionModule: CellVector, CollectionDocument
import ..ImageModule: ImageDocument
import ..GraphicsModule: GraphicsText, GraphicsRect, GraphicsLine, GraphicsCircle, GraphicsPolyline, GraphicsCanvas, GraphicsViewport, GraphicsImage, hit_element_at, layout_none
import ..GeometryModule: AffineTransform, affine_identity, affine_translate, affine_scale,
                         affine_apply, affine_inverse, affine_is_axis_aligned
import ..FontModule: StyleFont,
                     font_ubuntu_regular_18, font_ubuntu_regular_20, font_ubuntu_bold_20
import ..StyleTextModule: StyleText, DStyleText
import ..StyleStrokeModule: StyleStroke
import ..IoMapModule: SimpleIoMap, ChildrenIoMap
import ..IoMapApiModule: IoMap
import ..EventModule: MouseScroll, MousePress, MouseDown, MouseUp, MouseMove, MouseEnter, MouseLeave
import ..EventPatternModule: var"@event_case"
import ..OperationApiModule: Operation
import ..OperationModule: ReplaceSelectionOperation, ReplaceReferencedValueOperation, ToggleCollapseOperation, CompoundOperation
import ..ScreenDocumentModule: OpenPopupOperation, OpenWindowOperation, CloseWindowOperation
import ..PrimitiveModule: ReplaceStringRangeOperation, ReplaceNumberRangeOperation
import ..ReferenceModule: ReferencePath, ConcreteReferencePath, FieldReference, RangeReference,
                          ElementReference, EmptyReferencePath, is_element_reference
import ..PointReferenceModule: PointReference
import ..OperationRerootingModule: reroot_operation
import ..TypeDispatchingProjectionModule: TypeDispatchingProjection
import ..PrinterContextModule: make_child_context, with_available_size
import ..LayoutModule: LayoutDocument, LayoutConstraint, GridLayout, VerticalLayout, allocate_axis, layout_min, layout_max,
                       layout_preferred, layout_weight
import ..LayoutToGraphicsModule: GridLayoutToGraphicsCanvas, GridLayoutIoMap, _forward_descend, _shift_child_image
import ..EventModule: KeyDown
import ..EventModule: Modifiers
import ..GestureBindingModule: read_bound_gesture
export WidgetInsertionToGraphicsCanvas, WidgetLabelToGraphicsCanvas, WidgetTextToGraphicsCanvas,
       WidgetCheckboxToGraphicsCanvas, WidgetButtonToGraphicsCanvas,
       WidgetTooltipToGraphicsCanvas, WidgetContextMenuToGraphicsCanvas,
       WidgetContextMenuToGraphicsCanvasIoMap,
       WidgetDialogToGraphicsCanvas, WidgetDialogToGraphicsCanvasIoMap,
       WidgetMenuToGraphicsCanvas,
       WidgetMenuItemToGraphicsCanvas, WidgetCompositeToGraphicsCanvas,
       WidgetShellToGraphicsCanvas, WidgetTitlePaneToGraphicsCanvas,
       WidgetSplitPaneToGraphicsCanvas, WidgetTabbedPaneToGraphicsCanvas,
       WidgetScrollPaneToGraphicsCanvas, WidgetScrollPaneToGraphicsCanvasIoMap,
       WidgetTransformPaneToGraphicsCanvas, WidgetTransformPaneToGraphicsCanvasIoMap,
       WidgetToolbarToGraphicsCanvas, WidgetStatusBarToGraphicsCanvas, WidgetScrollBarToGraphicsCanvas,
       WidgetToGraphics, WidgetTheme, widget_theme_light, widget_theme_dark,
       widget_theme_slate_light, widget_theme_slate_dark,
       WidgetScrollPaneToGraphicsViewport, WidgetScrollPaneToGraphicsViewportIoMap,
       WidgetSelectToGraphicsCanvas, WidgetSelectToGraphicsCanvasIoMap,
       WidgetSpinBoxToGraphicsCanvas, WidgetSpinBoxToGraphicsCanvasIoMap,
       WidgetListToGraphicsCanvas, WidgetListToGraphicsCanvasIoMap,
       WidgetOptionToGraphicsCanvas,
       anchor_point,
       register_icon!, glyph_icon, image_icon

# ── Anchor resolution ──────────────────────────────────────────────
#
# Resolve a document-domain `reference` to the anchor's absolute top-left within
# the root output canvas, reusing `map_reference_forward` (no parallel generic —
# wrappers compose it for free). Returns `(x, y)` or `nothing`. The forward image
# of a positioned widget is a `PointReference` in the root output's frame; add the
# root canvas's own origin to land in window-content coordinates. The trigger
# bakes any size-relative offset (e.g. "below the box") into the open op itself.
function anchor_point(iomap, reference)
    img = map_reference_forward(iomap.projection, iomap, reference)
    img isa PointReference || return nothing
    out = iomap.output
    bx = out isa GraphicsCanvas ? Int(out.x[]) : 0
    by = out isa GraphicsCanvas ? Int(out.y[]) : 0
    (bx + Int(img.x[]), by + Int(img.y[]))
end

# ── Theme (design tokens) ─────────────────────────────────────────

"""
    WidgetTheme

The **small shared core** of design tokens — only the cross-cutting values read
by many widgets. Each widget projection owns its own style parameters (full
names, compound types) and the `WidgetToGraphics` factory supplies them, deriving
the shared ones from this theme and providing the widget-specific dimensions
(switch size, tree indent, card padding, …) as per-widget defaults at the call
site. So this theme is the *palette + scale*; a different look is a different
factory, not a bigger theme. The fields:

- **Palette** — `background … ring` plus `track_off` (the switch's off-track).
- **Type & base spacing** — `font*`, `radius`, `pad_x`, `pad_y`.
- **Shared layout** — `gap`, `border_width`, `stroke`, `chevron` (each read by
  several widgets; the source of fan-out).
- **Box model** — `inset`, the themed default margin/border/padding.
- **Text styles** — `body_text` / `title_text` / `caption_text` / `label_text`
  (`StyleText`, bundling font + color).

Spacing tokens are *logical* pixels scaled at render time via `_sc`. They are
palette-independent, so both presets share them via [`_widget_theme`](@ref);
only colors and fonts differ. See [`widget_theme_light`](@ref) /
[`widget_theme_dark`](@ref).
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
    # ── Shared layout tokens (each read by several widgets; the source of
    #    fan-out — widget-specific dimensions live on their projections,
    #    supplied as factory defaults, not here). ──
    gap::Int            # inter-item gap (toolbar items, shell bands, select, accordion)
    border_width::Int   # hairline: border / splitter / separator / table rules
    stroke::Int         # icon stroke (checkmark, chevron, radio ring, knob ring)
    chevron::Int        # chevron half-size (select, accordion, tree)
    # ── Box model ──
    inset::Inset        # themed default margin/border/padding
    # ── Semantic text styles (font + color) ──
    body_text::StyleText      # regular foreground text
    title_text::StyleText     # bold foreground heading
    caption_text::StyleText    # small muted text
    label_text::StyleText      # control labels (regular foreground)
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
        # type & base spacing: radius, fonts, pad_x, pad_y
        8, font, font_bold, font_small, 14, 9,
        # shared layout: gap border_width stroke chevron
        4, 1, 2, 4,
        # box model
        inset_default,
        # semantic text styles: body / title / caption / label
        StyleText(font, foreground),
        StyleText(font_bold, foreground),
        StyleText(font_small, muted_foreground),
        StyleText(font, foreground))
end

"""
    widget_theme_light(; font=font_ubuntu_regular_20) -> WidgetTheme

The neutral zinc light theme (a neutral zinc palette on a white background).
Kept as an alternative; the expressed slate/indigo theme is the default — see
[`widget_theme_slate_light`](@ref).
"""
function widget_theme_light(; font::StyleFont=font_ubuntu_regular_20)
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
        font=font, font_bold=font_ubuntu_bold_20, font_small=font_ubuntu_regular_18)
end

"""
    widget_theme_dark(; font=font_ubuntu_regular_20) -> WidgetTheme

The neutral zinc dark theme (zinc-950 surfaces). Ships alongside the light
default; the editor chrome can opt in. For the expressed slate/indigo variant
see [`widget_theme_slate_dark`](@ref).
"""
function widget_theme_dark(; font::StyleFont=font_ubuntu_regular_20)
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
        font=font, font_bold=font_ubuntu_bold_20, font_small=font_ubuntu_regular_18)
end

"""
    widget_theme_slate_light(; font=font_ubuntu_regular_20) -> WidgetTheme

The default light theme: a cool slate palette with an indigo accent, on tinted
(non-white) surfaces so the colors read as expressed rather than washed out.
"""
function widget_theme_slate_light(; font::StyleFont=font_ubuntu_regular_20)
    _widget_theme(
        background=color_slate_100,    foreground=color_slate_950,
        card=color_slate_50,           card_foreground=color_slate_950,
        popover=color_slate_50,        popover_foreground=color_slate_950,
        muted=color_slate_200,         muted_foreground=color_slate_500,
        primary=color_indigo_600,      primary_foreground=color_slate_50,
        secondary=color_slate_200,     secondary_foreground=color_slate_900,
        accent=color_indigo_100,       accent_foreground=color_indigo_700,
        destructive=color_destructive, destructive_foreground=color_destructive_fg,
        border=color_slate_300,        input=color_slate_300,   ring=color_indigo_500,
        track_off=color_slate_300,
        font=font, font_bold=font_ubuntu_bold_20, font_small=font_ubuntu_regular_18)
end

"""
    widget_theme_slate_dark(; font=font_ubuntu_regular_20) -> WidgetTheme

The expressed dark theme: deep slate surfaces with a bright indigo accent, the
dark counterpart to [`widget_theme_slate_light`](@ref).
"""
function widget_theme_slate_dark(; font::StyleFont=font_ubuntu_regular_20)
    _widget_theme(
        background=color_slate_950,    foreground=color_slate_50,
        card=color_slate_900,          card_foreground=color_slate_50,
        popover=color_slate_900,       popover_foreground=color_slate_50,
        muted=color_slate_800,         muted_foreground=color_slate_400,
        primary=color_indigo_500,      primary_foreground=color_slate_50,
        secondary=color_slate_800,     secondary_foreground=color_slate_50,
        accent=color_indigo_950,       accent_foreground=color_indigo_200,
        destructive=color_destructive, destructive_foreground=color_destructive_fg,
        border=color_slate_800,        input=color_slate_800,   ring=color_indigo_400,
        track_off=color_slate_700,
        font=font, font_bold=font_ubuntu_bold_20, font_small=font_ubuntu_regular_18)
end

# ── Styling helpers ─────────────────────────────────────────────────────────

# Fallback viewport / track extents used only when a widget carries no `size`
# *and* its parent allocated no `available_*` extent (isolated rendering). Named
# here so the value is stated once — the scroll bar's track size is read by
# both its printer and its hit-test reader, so a single source avoids a drift
# risk between the two.
const _SCROLL_FALLBACK_WIDTH  = 400   # WidgetScrollPane / ScrollViewport viewport
const _SCROLL_FALLBACK_HEIGHT = 300
const _SCROLLBAR_FALLBACK_LENGTH    = 200  # scroll bar track (long axis)
const _SCROLLBAR_FALLBACK_THICKNESS = 16   # scroll bar track (short axis)
const _SPLIT_SLOT_FALLBACK    = 200   # per-slot main-axis extent, no constraint/sizes

# All widget geometry — spacing, radii, insets, positions — is in logical
# pixels. The single global `_DISPLAY_SCALE` is applied uniformly at the SDL
# render boundary, so the projection layer never scales: `_sc`/`_origin` are
# identity markers that document "this number is a logical pixel measurement".
_sc(px::Integer) = Int(px)

# A widget's authored `position` is in logical pixels, like insets.
_origin(pos::Point2D) = (Int(pos.x[]), Int(pos.y[]))

# Push a themed rounded box (fill + optional outline) of size cw×ch at (x,y).
function _push_panel!(elems::Vector, x::Int, y::Int, cw::Int, ch::Int;
                      fill::StyleColor, border=nothing, border_w::Int=0, radius::Int=0)
    if border !== nothing && border_w > 0
        push!(elems, GraphicsRect(x, y, cw, ch, fill, radius;
                                  border_width=border_w, border_color=border))
    else
        push!(elems, GraphicsRect(x, y, cw, ch, fill, radius))
    end
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

# A focus ring around a focused widget (Stage 2). Focus is selection. The ring is
# a **persistent overlay** (always pushed) whose `w`/`h` read the selection — full
# control bounds when focused, 0 when not (a zero-size rect the renderer skips).
# Pushing it unconditionally keeps the selection read OUT of the elements-vector
# thunk, so a pure focus/caret move invalidates only the ring's own geometry cells
# (selection-overlay geometry), not the whole content `CellVector` — the widget
# analogue of the TextToGraphics cursor overlay, preserving selection isolation
# (dimension A; see plan/pending/printer-locality.md). Transparent fill so only the
# ring-coloured border shows.
function _push_focus_ring!(elems::Vector, w::WidgetDocument, cw::Int, ch::Int,
                           ring_color::StyleColor, radius::Int)
    ring = GraphicsRect(0, 0, 0, 0, StyleColor(0.0, 0.0, 0.0, 0.0), radius;
                        border_width=2, border_color=ring_color)
    set_cell_function!(getfield(ring, :w), () -> getfield(w, :selection)[] === nothing ? Int32(0) : Int32(cw))
    set_cell_function!(getfield(ring, :h), () -> getfield(w, :selection)[] === nothing ? Int32(0) : Int32(ch))
    push!(elems, ring)
end

# ── Hover feedback (Stage 6) ─────────────────────────────────────────────────
# The shared convention: an actionable widget carries a `hovered` cell, set by the
# WidgetHoverTrackingProjection via MouseEnter/MouseLeave, and renders a faint
# surface behind itself while hovered + enabled. A disabled widget never hovers.

# A widget's reader falls through to this for crossing events: it writes the
# `hovered` state, or `nothing` for any other event.
_hover_state_op(w, evt) =
    evt isa MouseEnter ? ReplaceReferencedValueOperation(w, "hovered", true) :
    evt isa MouseLeave ? ReplaceReferencedValueOperation(w, "hovered", false) : nothing

# Draw the hover surface behind a widget when its `hovered` cell is set and it is
# enabled. Pushed first so the content draws over it.
function _push_hover_surface!(elems::Vector, w, enabled::Bool, cw::Int, ch::Int,
                              color::StyleColor, radius::Int=0)
    (enabled && hasproperty(w, :hovered) && w.hovered === true) || return
    _push_panel!(elems, 0, 0, cw, ch; fill=color, radius=radius)
end

# ── Projection structs ─────────────────────────────────────────────────────

@projection struct WidgetLabelToGraphicsCanvas
    measure::Function
    text::ImmutableCell{DStyleText}        # font + color of the label
end

@projection struct WidgetTextToGraphicsCanvas
    measure::Function
    text::ImmutableCell{DStyleText}            # font + color of the non-editable form
    background_color::StyleColor
    border_color::StyleColor    # input outline
    corner_radius::Int
    ring_color::StyleColor      # focus ring when selected
end

@projection struct WidgetCheckboxToGraphicsCanvas
    box_size::Int
    corner_radius::Int
    checked_color::StyleColor      # filled box when checked
    check::StyleStroke             # the tick (color + width)
    background_color::StyleColor   # empty box fill
    outline::StyleStroke           # empty box outline (color + width)
    disabled_color::StyleColor     # box fill when !enabled
    disabled_foreground::StyleColor # tick / outline when !enabled
    ring_color::StyleColor         # focus ring when selected
end

# Style parameters owned by the button projection (hybrid model, §8 of the plan):
# fed from the theme by the `WidgetToGraphics` factory, full names + compound
# types, so the renderer reads `p.<field>` directly with no `p.theme.*`.
# `@projection` Cell-wraps every field (so each is live-editable via
# ObjectToWidget and linkable by sharing a Cell) while keeping `p.field`
# transparent; the factory may pass plain values or Cells.
@projection struct WidgetButtonToGraphicsCanvas
    measure::Function
    label::ImmutableCell{DStyleText}            # font + color of the button text
    background_color::StyleColor # resting surface
    hover_color::StyleColor      # surface while the pointer is inside
    active_color::StyleColor     # surface while pressed (held down)
    border::StyleStroke         # outline color + width
    padding::Inset              # content padding (was pad_x / pad_y)
    corner_radius::Int
    shadow_offset::Int
    disabled_color::StyleColor   # surface when !enabled
    disabled_foreground::StyleColor # label color when !enabled
    ring_color::StyleColor       # focus ring when selected
end

@projection struct WidgetTooltipToGraphicsCanvas
    measure::Function
    text::ImmutableCell{DStyleText}             # font + popover foreground
    surface_color::StyleColor    # popover fill
    border::StyleStroke
    corner_radius::Int
    default_padding::Inset       # fallback padding when the document specifies none
end

@projection struct WidgetMenuToGraphicsCanvas
    measure::Function
    font::StyleFont             # used to measure the per-item row height
end

@projection struct WidgetMenuItemToGraphicsCanvas
    measure::Function
    text::ImmutableCell{DStyleText}             # font + foreground
    disabled_foreground::StyleColor   # label color when disabled (item or bound command)
    hover_color::StyleColor           # hover surface behind the item (Stage 6)
end

struct WidgetCompositeToGraphicsCanvas <: Projection end

@projection struct WidgetShellToGraphicsCanvas
    measure::Function
    font::StyleFont             # measures the menu/toolbar band heights
    background_color::StyleColor
    band_gap::Int               # gap below the toolbar band
end

@projection struct WidgetTitlePaneToGraphicsCanvas
    measure::Function
    title_text::ImmutableCell{DStyleText}        # bold title
    content_text::ImmutableCell{DStyleText}      # string-content body
    title_gap::Int
end

@projection struct WidgetSplitPaneToGraphicsCanvas
    splitter::StyleStroke    # divider color + thickness
end

@projection struct WidgetTabbedPaneToGraphicsCanvas
    measure::Function
    font::StyleFont
    tab_padding::Int
    corner_radius::Int
    track_color::StyleColor          # muted tab strip
    active_color::StyleColor         # raised active-tab fill
    active_foreground::StyleColor
    inactive_foreground::StyleColor
end

@projection struct WidgetScrollPaneToGraphicsCanvas
    measure::Function
    font::StyleFont                  # measures the scroll step
    background_color::StyleColor      # default viewport fill
end

@projection struct WidgetTransformPaneToGraphicsCanvas
    measure::Function
    font::StyleFont                  # measures the pan step
    background_color::StyleColor      # default viewport fill
end

@projection struct WidgetToolbarToGraphicsCanvas
    measure::Function
    font::StyleFont          # measures each item's advance
    item_gap::Int
end

@projection struct WidgetScrollBarToGraphicsCanvas
    track_color::StyleColor       # rail fill
    thumb_color::StyleColor       # thumb fill
    minimum_thumb_length::Int
end

# ── IoMap for WidgetScrollPane ─────────────────────────────────────────────

struct WidgetScrollPaneToGraphicsCanvasIoMap <: IoMap
    projection::Any
    input::WidgetScrollPane
    output::GraphicsCanvas
    content_iomap::Any
end

# ── IoMap for WidgetTransformPane ──────────────────────────────────────────

struct WidgetTransformPaneToGraphicsCanvasIoMap <: IoMap
    projection::Any
    input::WidgetTransformPane
    output::GraphicsCanvas
    content_iomap::Any
end

# ── Color helpers ──────────────────────────────────────────────────────────


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
        total_w = ml + bl + pw + br + mr
        mt > 0 && push!(elems, GraphicsRect(bx,                      by, total_w, mt,  mc))
        mb > 0 && push!(elems, GraphicsRect(bx, by + mt + bt + ph + bb, total_w, mb,  mc))
        ml > 0 && push!(elems, GraphicsRect(bx,              by + mt,   ml, bt + ph + bb, mc))
        mr > 0 && push!(elems, GraphicsRect(bx + ml + bl + pw + br, by + mt, mr, bt + ph + bb, mc))
    end

    bc = w.border_color
    if bc isa StyleColor
        bx2, by2 = bx + ml, by + mt
        bt > 0 && push!(elems, GraphicsRect(bx2,              by2,         bl + pw + br, bt,  bc))
        bb > 0 && push!(elems, GraphicsRect(bx2, by2 + bt + ph,            bl + pw + br, bb,  bc))
        bl > 0 && push!(elems, GraphicsRect(bx2,         by2 + bt,         bl, ph,           bc))
        br > 0 && push!(elems, GraphicsRect(bx2 + bl + pw, by2 + bt,       br, ph,           bc))
    end

    pc = w.padding_color
    if pc isa StyleColor
        push!(elems, GraphicsRect(bx + ml + bl, by + mt + bt, pw, ph, pc))
    end
end

# ── Text helpers ───────────────────────────────────────────────────────────

function _push_text!(elems::Vector, font::StyleFont, text::AbstractString,
                     x::Int, y::Int, fg::StyleColor)
    push!(elems, GraphicsText(text, x, y, font, fg))
end

# A callable wrapper so the backend text-measure function can be stored as a
# plain *value* inside a `@projection` Cell — a bare `Function` would be taken as
# a thunk (computed cell) and invoked with zero args. Call it exactly like the
# underlying `measure(text, font)`.
struct TextMeasurer
    measure::Function
end
(measurer::TextMeasurer)(text, font) = measurer.measure(text, font)

function _text_size(measure, font::StyleFont, text::AbstractString)
    measure(text, font)
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
# becomes a GraphicsImage (a muted placeholder rect when not yet decoded);
# everything else is drawn as label text. `cw`/`ch` are the resolved content box.
function _push_content!(elems::Vector, measure, label::StyleText, content,
                        x::Int, y::Int, cw::Int, ch::Int)
    if content isa ImageDocument
        data, _, _ = _image_payload(content)
        if data === nothing
            # Not decoded yet — keep layout stable with a faint placeholder.
            push!(elems, GraphicsRect(x, y, cw, ch, StyleColor(0.0, 0.0, 0.0, 0x14 / 255)))
        else
            push!(elems, GraphicsImage(Int32(x), Int32(y), Int32(cw), Int32(ch), data))
        end
    else
        _push_text!(elems, label.font, string(content), x, y, label.color)
    end
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
        result = read_intent(cim.projection, cim, make_evt(lx, ly))
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

# Route a MouseEnter / MouseLeave crossing to the hit child (for hover feedback,
# Stage 6) — the child reader flips its `hovered` cell.
_route_crossing_to_children(child_entries::Vector, evt) =
    _route_to_children(child_entries, evt.x, evt.y,
        (x, y) -> evt isa MouseEnter ? MouseEnter(x, y, evt.buttons, evt.modifiers) :
                                       MouseLeave(x, y, evt.buttons, evt.modifiers))

# Route pointer motion to the hit child (coordinate-translated), so a hovered
# widget nested in a band container still sees MouseMove.
_route_move_to_children(child_entries::Vector, evt::MouseMove) =
    _route_to_children(child_entries, evt.x, evt.y,
        (x, y) -> MouseMove(x, y, evt.buttons, evt.modifiers))

# Translate a path-bearing op from `op`'s current domain (this projection's
# child's input domain — what the bubbled-up reader returned) into this
# projection's own input domain by running its reference through
# `map_reference_backward`. Identity-rooted / non-path-bearing ops (an
# identity-rooted `ReplaceReferencedValueOperation`, `SelectTabOperation`, …) pass through
# unchanged; `nothing` passes through.
# Returns `nothing` if the backward mapping rejects the reference.
function _retarget_op(p, iomap, op)
    op === nothing && return nothing
    if op isa ReplaceSelectionOperation
        new_ref = map_reference_backward(p, iomap, op.path)
        return new_ref === nothing ? nothing : ReplaceSelectionOperation(new_ref)
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
        return any(isnothing, mapped) ? nothing : CompoundOperation(mapped)
    else
        return op
    end
end

# Reference/operation re-rooting lives in `OperationRerootingModule`
# (`reroot_operation` / `reroot_reference`) — shared with the layout
# container readers so the prepend logic is defined once.

# ── WidgetLabel ─────────────────────────────────────────────────────────────

function print_document(p::WidgetLabelToGraphicsCanvas, recursion, w::WidgetLabel, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    position = w.position::Point2D
    content = w.content
    # A label may carry its own font+color (e.g. a chat card's title) that
    # overrides the theme's default label style.
    style = w.text_style === nothing ? p.text : w.text_style
    content_width, content_height = _content_size(p.measure, style.font, content)
    elements = Any[]
    _push_content!(elements, p.measure, style, content, 0, 0, content_width, content_height)
    SimpleIoMap(p, w, _make_canvas(_origin(position)..., content_width, content_height, elements))
end

function map_reference_forward(::WidgetLabelToGraphicsCanvas, iomap, reference)
    return nothing
end

function map_reference_backward(::WidgetLabelToGraphicsCanvas, iomap, reference)
    return nothing
end

function read_intent(::WidgetLabelToGraphicsCanvas, iomap::SimpleIoMap, evt)
    return nothing
end

# ── WidgetInsertion ──────────────────────────────────────────────────────────

# Renders the type-replace placeholder ("insert here") as a muted text canvas at
# the origin. WidgetInsertion carries no `position`/`content` value of its own,
# so there is nothing to map; like the sibling JsonInsertion handler it is a
# projection-introduced placeholder and its reference maps are no-ops.
@projection struct WidgetInsertionToGraphicsCanvas
    measure::Function
    text::ImmutableCell{DStyleText}
end

function print_document(p::WidgetInsertionToGraphicsCanvas, recursion, w::WidgetInsertion, ctx)
    content = "insert here"
    content_width, content_height = _text_size(p.measure, p.text.font, content)
    elements = Any[]
    _push_text!(elements, p.text.font, content, 0, 0, p.text.color)
    SimpleIoMap(p, w, _make_canvas(0, 0, content_width, content_height, elements))
end

map_reference_forward(::WidgetInsertionToGraphicsCanvas, iomap, reference) = nothing
map_reference_backward(::WidgetInsertionToGraphicsCanvas, iomap, reference) = nothing
read_intent(::WidgetInsertionToGraphicsCanvas, iomap::SimpleIoMap, evt) = nothing

# ── WidgetText ──────────────────────────────────────────────────────────────

# IoMap for an *editable* WidgetText: its `content` is a Document (typically a
# `TextBlock`) recursed through the Text domain, so all caret navigation and text
# editing is produced by `TextToGraphics`. The widget only re-roots the resulting
# operations by prepending `content` (see `map_reference_backward`).
struct WidgetTextToGraphicsCanvasIoMap <: IoMap
    projection::Any
    input::WidgetText
    output::GraphicsCanvas
    content_iomap::Any
end

function print_document(p::WidgetTextToGraphicsCanvas, recursion, w::WidgetText, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    pos = w.position::Point2D
    cox, coy = _content_offset(w)

    # Editable form: a Document content (e.g. a TextBlock) is recursed through the
    # outer projection chain (which routes it to TextToGraphics). Navigation and
    # editing operations then originate in the Text domain; this projection just
    # maps them backward. Mirrors WidgetScrollPane's content recursion.
    radius = _sc(p.corner_radius)
    content = w.content
    if content isa Document
        content_iomap = print_child(recursion, content, ctx)
        inner = content_iomap.output::GraphicsCanvas
        iw, ih = Int(inner.w[]), Int(inner.h[])
        elems = Any[]
        # Themed input surface: background fill + input outline + rounded corners.
        _push_box!(elems, w, iw, ih; fill=p.background_color, border=p.border_color, radius=radius)
        push!(elems, _make_canvas(cox, coy, Any[inner]))
        tx, ty = _inset_total(w)
        _push_focus_ring!(elems, w, iw + tx, ih + ty, p.ring_color, radius)
        canvas = _make_canvas(_origin(pos)..., iw + tx, ih + ty, elems)
        return WidgetTextToGraphicsCanvasIoMap(p, w, canvas, content_iomap)
    end

    # Non-editable form: a plain value is stringified (input-like).
    text = string(content)
    cw, ch = _text_size(p.measure, p.text.font, text)
    tx, ty = _inset_total(w)
    elems = Any[]
    _push_box!(elems, w, cw, ch; fill=p.background_color, border=p.border_color, radius=radius)
    _push_text!(elems, p.text.font, text, cox, coy, p.text.color)
    _push_focus_ring!(elems, w, cw + tx, ch + ty, p.ring_color, radius)
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

function read_intent(::WidgetTextToGraphicsCanvas, iomap::SimpleIoMap, evt)
    return nothing
end

# Delegate every event to the recursed content (Text domain), then re-root the
# returned path-bearing operation through `map_reference_backward`. MousePress is
# translated into the content's coordinate frame first.
function read_intent(p::WidgetTextToGraphicsCanvas, iomap::WidgetTextToGraphicsCanvasIoMap, evt)
    iomap.input.enabled === false && return nothing   # a disabled text widget accepts no edits
    content_iomap = iomap.content_iomap
    content_iomap === nothing && return nothing
    op = @event_case evt begin
        MousePress(button, x, y) => begin
            cox, coy = _content_offset(iomap.input)
            read_intent(content_iomap.projection, content_iomap,
                            MousePress(button, x - cox, y - coy, evt.modifiers))
        end
        _ => read_intent(content_iomap.projection, content_iomap, evt)
    end
    _validate_text_edit(iomap.input, _retarget_op(p, iomap, op))
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

function print_document(p::WidgetCheckboxToGraphicsCanvas, recursion, w::WidgetCheckbox, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    position = w.position::Point2D
    checked = w.content === true
    enabled = !(w.enabled === false)
    box_size = _sc(p.box_size)
    corner_radius = _sc(p.corner_radius)
    elements = Any[]
    # When disabled, the box uses the muted surface and the tick/outline render in
    # the muted foreground, keeping the checked/unchecked shape but signalling that
    # the control is inert (its reader also swallows clicks).
    checked_fill = enabled ? p.checked_color : p.disabled_color
    check_color  = enabled ? p.check.color   : p.disabled_foreground
    empty_fill   = enabled ? p.background_color : p.disabled_color
    outline_color = enabled ? p.outline.color : p.disabled_foreground
    if checked
        _push_panel!(elements, 0, 0, box_size, box_size; fill=checked_fill, radius=corner_radius)
        check_width = max(1, _sc(p.check.width))
        # Crisp two-stroke checkmark instead of a glyph.
        x1, y1 = round(Int, 0.22box_size), round(Int, 0.52box_size)
        x2, y2 = round(Int, 0.42box_size), round(Int, 0.70box_size)
        x3, y3 = round(Int, 0.78box_size), round(Int, 0.30box_size)
        push!(elements, GraphicsLine(x1, y1, x2, y2, check_color; width=check_width))
        push!(elements, GraphicsLine(x2, y2, x3, y3, check_color; width=check_width))
    else
        _push_panel!(elements, 0, 0, box_size, box_size; fill=empty_fill,
                     border=outline_color, border_w=max(1, _sc(p.outline.width)), radius=corner_radius)
    end
    _push_focus_ring!(elements, w, box_size, box_size, p.ring_color, corner_radius)
    SimpleIoMap(p, w, _make_canvas(_origin(position)..., box_size, box_size, elements))
end

function map_reference_forward(::WidgetCheckboxToGraphicsCanvas, iomap, reference)
    return nothing
end

function map_reference_backward(::WidgetCheckboxToGraphicsCanvas, iomap, reference)
    return nothing
end

# A click toggles the checkbox. By convention a leaf control reports an edit as
# `ReplaceReferencedValueOperation(self, content, new_value)`; a configuring projection
# (ObjectToWidget) intercepts it by control identity and redirects it onto the
# bound parameter cell. A bare click that does not reach here leaves the value
# unchanged.
_checkbox_toggle(w) = ReplaceReferencedValueOperation(w,
    ConcreteReferencePath(FieldReference("content"), EmptyReferencePath()), !(w.content === true))

function read_intent(::WidgetCheckboxToGraphicsCanvas, iomap::SimpleIoMap, evt::MousePress)
    w = iomap.input
    w.enabled === false && return nothing   # a disabled checkbox swallows the click
    op = read_bound_gesture(w, evt); op === nothing || return op   # per-instance gestures win
    _checkbox_toggle(w)
end

# Enter / Space toggle the focused checkbox (the keystroke reaches it via the
# selection-driven routing). Tab is left to fall through (nothing) so focus
# traversal can claim it.
function read_intent(::WidgetCheckboxToGraphicsCanvas, iomap::SimpleIoMap, evt)
    w = iomap.input
    w.enabled === false && return nothing
    op = read_bound_gesture(w, evt); op === nothing || return op   # per-instance gestures win
    (evt isa KeyDown && (evt.key === :return || evt.key === :space)) || return nothing
    _checkbox_toggle(w)
end

# ── WidgetButton ────────────────────────────────────────────────────────────

# A bound command (Stage 4) supplies the button's label, enabled-state, and
# callback, so a menu item / toolbar button / shortcut can share one `Action`.
_button_command(w::WidgetButton) = (c = w.command; c isa Action ? c : nothing)
_button_enabled(w::WidgetButton) =
    !(w.enabled === false) && !((c = _button_command(w)) !== nothing && c.enabled === false)
_button_label_content(w::WidgetButton) = (c = _button_command(w); c !== nothing ? string(c.label) : w.content)
# Icon (Stage 5): a bound command's icon wins, else the button's own.
_button_icon(w::WidgetButton) = (c = _button_command(w); (c !== nothing && c.icon !== nothing) ? c.icon : w.icon)

function print_document(p::WidgetButtonToGraphicsCanvas, recursion, w::WidgetButton, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    position = w.position::Point2D
    minimum_size = w.size::Point2D
    label_content = _button_label_content(w)
    content_width, content_height = _content_size(p.measure, p.label.font, label_content)
    padding_x = _sc(Int(p.padding.left[]))
    padding_y = _sc(Int(p.padding.top[]))
    # Optional leading icon (Stage 5): a square the size of the label text, with a
    # gap before the label. An unknown icon name contributes nothing.
    icon = _button_icon(w)
    icon_sz = content_height
    icon_w  = icon_width(icon, icon_sz)
    icon_gap = icon_w > 0 ? _sc(6) : 0
    full_w = icon_w + icon_gap + content_width
    button_width  = max(Int(minimum_size.x[]), full_w + 2padding_x)
    button_height = max(Int(minimum_size.y[]), content_height + 2padding_y)
    corner_radius = _sc(p.corner_radius)
    # State-driven surface: pressed > hover > resting. The reader keeps the
    # widget's transient `pressed`/`hovered` cells current; reading them here ties
    # the rendered fill to that state reactively. A disabled button (or one bound to
    # a disabled command) ignores that state entirely: flat muted surface, muted
    # label, no shadow (its reader also never sets pressed/hovered).
    enabled = _button_enabled(w)
    pressed = enabled && w.pressed === true
    hovered = enabled && w.hovered === true
    fill = !enabled ? p.disabled_color :
           pressed ? p.active_color : hovered ? p.hover_color : p.background_color
    label = enabled ? p.label : StyleText(p.label.font, p.disabled_foreground)
    elements = Any[]
    # Default button: light surface, subtle border, soft shadow, dark label —
    # matching the shadcn default button. A faint offset rect approximates the
    # shadow-sm drop shadow; it is dropped while pressed (so the button "sinks")
    # and while disabled (so it reads as inert/flat).
    if enabled && !pressed
        push!(elements, GraphicsRect(0, _sc(p.shadow_offset), button_width, button_height, StyleColor(0.0, 0.0, 0.0, 0x14 / 255), corner_radius))
    end
    _push_panel!(elements, 0, 0, button_width, button_height; fill=fill,
                 border=p.border.color, border_w=max(1, _sc(p.border.width)), radius=corner_radius)
    # Lay out icon + label as one centered group; the icon tints to the label color
    # (so it mutes with the button), the label sits to its right.
    start_x = (button_width - full_w) ÷ 2
    cy = (button_height - content_height) ÷ 2
    if icon_w > 0
        _push_icon!(elements, icon, start_x, (button_height - icon_sz) ÷ 2, icon_sz, label.color)
    end
    _push_content!(elements, p.measure, label, label_content, start_x + icon_w + icon_gap, cy, content_width, content_height)
    _push_focus_ring!(elements, w, button_width, button_height, p.ring_color, corner_radius)
    SimpleIoMap(p, w, _make_canvas(_origin(position)..., button_width, button_height, elements))
end

# Forward image of a positioned widget: the empty reference (the widget itself)
# maps to its top-left in its own output canvas frame — `PointReference(0, 0)`.
# Parent containers add their placement on the way up. A non-empty reference has
# no image (the leaf has no addressable interior here). See `map_reference_forward`.
_self_point(reference) =
    (reference === nothing || reference isa EmptyReferencePath) ?
        PointReference(0, 0) : nothing

map_reference_forward(::WidgetButtonToGraphicsCanvas, iomap, reference) =
    _self_point(reference)

function map_reference_backward(::WidgetButtonToGraphicsCanvas, iomap, reference)
    return nothing
end

# The button owns ALL of its own state transitions. The generic
# WidgetHoverTrackingProjection only decides *when* the pointer crosses this
# button's boundary and delivers a MouseEnter / MouseLeave; the button decides
# what that means for its state (hovered/pressed). A click invokes the action;
# press/release drive the held-down look. (The reader only runs when the parent
# hit-tested the pointer onto this button, so coordinate events are "inside".)
function read_intent(::WidgetButtonToGraphicsCanvas, iomap::SimpleIoMap, evt)
    w = iomap.input
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
    @event_case evt begin
        MousePress(button, x, y) => button === :left ? _button_primary_op(w) : nothing
        MouseDown(button, x, y)  => button === :left ? ReplaceReferencedValueOperation(w, "pressed", true) : nothing
        MouseUp(button, x, y)    => button === :left ? ReplaceReferencedValueOperation(w, "pressed", false) : nothing
        MouseEnter               => ReplaceReferencedValueOperation(w, "hovered", true)
        # Leaving clears hover *and* any in-progress press (the release may land
        # off the button when dragged away).
        MouseLeave               => CompoundOperation(Any[ReplaceReferencedValueOperation(w, "hovered", false),
                                                          ReplaceReferencedValueOperation(w, "pressed", false)])
        # Enter / Space activate the focused button (key reaches it via selection
        # routing). `:tab` is intentionally not matched, so it falls through to
        # `nothing` and focus traversal can claim it.
        when(KeyDown(k), k === :return || k === :space) => _button_primary_op(w)
        _ => nothing
    end
end

# The button's *primary* gesture (the built-in default that left-click / Enter /
# Space map to): invoke its bound `command` (Stage 4) if it has one; else open its
# `dialog` as a modal window (Step 5); else run its plain `action`. This is just
# the default primary op — it is not privileged; any gesture (double/right/shift-
# click, …) is expressed as its own per-instance binding. A modal dialog is
# centered, not anchored, so it opens directly as an `OpenWindowOperation` (no
# popup resolver). v1 uses a generous fixed window box; true screen-sizing /
# centering is deferred (see widget.md).
function _button_primary_op(w::WidgetButton)
    command = _button_command(w)
    command === nothing || return InvokeActionOperation(command)
    dlg = w.dialog
    dlg === nothing && return InvokeWidgetActionOperation(w)
    OpenWindowOperation(; id=dlg.popup_id, modal=true, style=:dialog,
                        x=80, y=60, width=480, height=320, content=dlg)
end

# ── WidgetTooltip ───────────────────────────────────────────────────────────

function print_document(p::WidgetTooltipToGraphicsCanvas, recursion, w::WidgetTooltip, ctx)
    w.visible == false && return ChildrenIoMap(p, w, _empty_canvas(), Cell(Any[]))
    pos = w.position::Point2D
    cox, coy = _content_offset(w)
    tx, ty = _inset_total(w)
    # Use sensible default padding when the document specifies none, so the box
    # never hugs the text.
    default_padding_x = _sc(Int(p.default_padding.left[]))
    default_padding_y = _sc(Int(p.default_padding.top[]))
    cox = max(cox, default_padding_x); coy = max(coy, default_padding_y)
    txp = max(tx, 2default_padding_x); typ = max(ty, 2default_padding_y)
    child_iomaps = Any[]
    content = w.content
    elems = Any[]
    # Size the box to its content (at least the requested size).
    cw, ch = 0, 0
    body = Any[]
    if content isa AbstractString
        cw, ch = _text_size(p.measure, p.text.font, content)
        _push_text!(body, p.text.font, content, cox, coy, p.text.color)
    elseif content isa WidgetDocument
        cim = print_child(recursion, content, ctx)
        inner = cim.output
        cw, ch = inner isa GraphicsCanvas ? (Int(inner.w[]), Int(inner.h[])) : (0, 0)
        push!(child_iomaps, (cox, coy, cim))
        push!(body, _make_canvas(cox, coy, Any[inner]))
    end
    vw = cw + txp
    vh = ch + typ
    _push_panel!(elems, 0, 0, vw, vh; fill=p.surface_color,
                 border=p.border.color, border_w=max(1, _sc(p.border.width)), radius=_sc(p.corner_radius))
    append!(elems, body)
    ChildrenIoMap(p, w, _make_canvas(_origin(pos)..., vw, vh, elems), Cell(child_iomaps))
end

function map_reference_forward(::WidgetTooltipToGraphicsCanvas, iomap, reference)
    return nothing
end

function map_reference_backward(::WidgetTooltipToGraphicsCanvas, iomap, reference)
    return nothing
end

function read_intent(::WidgetTooltipToGraphicsCanvas, iomap::ChildrenIoMap, evt)
    evt isa MouseScroll || return nothing
    child_iomaps = iomap.child_iomaps[]::Vector
    _route_scroll_to_children(child_iomaps, evt)
end

# ── WidgetContextMenu ─────────────────────────────────────────────────────────

@projection struct WidgetContextMenuToGraphicsCanvas
    measure::Function
    font::StyleFont    # measures the popup menu's row size
end

# Carries the recursed child's iomap (for event routing + re-rooting) and the
# wrapper's own document path (captured from `ctx.reference`) — the anchor a right
# click uses to place the context-menu popup at the pointer.
struct WidgetContextMenuToGraphicsCanvasIoMap <: IoMap
    projection::Any
    input::WidgetContextMenu
    output::GraphicsCanvas
    child_iomap::Any
    anchor::ReferencePath
end

function print_document(p::WidgetContextMenuToGraphicsCanvas, recursion, w::WidgetContextMenu, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    child = w.child
    child isa Document || return SimpleIoMap(p, w, _empty_canvas())
    cox, coy = _content_offset(w)
    child_iomap = print_child(recursion, child, ctx)
    inner = child_iomap.output::GraphicsCanvas
    iw, ih = Int(inner.w[]), Int(inner.h[])
    tx, ty = _inset_total(w)
    canvas = _make_canvas(0, 0, iw + tx, ih + ty, Any[_make_canvas(cox, coy, Any[inner])])
    WidgetContextMenuToGraphicsCanvasIoMap(p, w, canvas, child_iomap, ctx.reference)
end

# Forward image: the wrapper is a positioned leaf for anchoring — the empty
# reference maps to its own top-left, so a content-root resolver places the popup
# at `wrapper_top_left + (local click)`. (A `.child` descent for a trigger nested
# in the child is not needed here and stays unmapped.)
map_reference_forward(::WidgetContextMenuToGraphicsCanvas, iomap::WidgetContextMenuToGraphicsCanvasIoMap, reference) =
    _self_point(reference)
map_reference_forward(::WidgetContextMenuToGraphicsCanvas, iomap, reference) = nothing

# Child ops re-root by prepending `.child`.
map_reference_backward(::WidgetContextMenuToGraphicsCanvas, iomap::WidgetContextMenuToGraphicsCanvasIoMap, reference) =
    reference === nothing ? nothing : ConcreteReferencePath(FieldReference("child"), reference)
map_reference_backward(::WidgetContextMenuToGraphicsCanvas, iomap, reference) = nothing

read_intent(::WidgetContextMenuToGraphicsCanvas, iomap::SimpleIoMap, evt) = nothing

# A right click opens the context menu at the pointer (Step 4d): an anchor-relative
# `OpenPopupOperation` whose offset is the *local* click coordinates, so the
# resolver places the menu under the pointer. Every other event routes to the
# child (its returned op is re-rooted through `.child`).
function read_intent(p::WidgetContextMenuToGraphicsCanvas, iomap::WidgetContextMenuToGraphicsCanvasIoMap, evt)
    w = iomap.input
    if evt isa MousePress && evt.button === :right
        (w.enabled === false || w.menu === nothing) && return nothing
        return _open_context_menu(p, w.menu, iomap, evt.x, evt.y)
    end
    child_iomap = iomap.child_iomap
    child_iomap === nothing && return nothing
    cox, coy = _content_offset(w)
    op = @event_case evt begin
        MousePress(button, x, y) =>
            read_intent(child_iomap.projection, child_iomap, MousePress(button, x - cox, y - coy, evt.modifiers))
        MouseScroll(dx, dy, x, y) =>
            read_intent(child_iomap.projection, child_iomap, MouseScroll(dx, dy, x - cox, y - coy))
        _ => read_intent(child_iomap.projection, child_iomap, evt)
    end
    _retarget_op(p, iomap, op)
end

# Estimate the popup size from the menu's rows (it renders with the same font once
# the popup window opens). Precise sizing is the popup window's job (Step 6).
function _open_context_menu(p::WidgetContextMenuToGraphicsCanvas, menu, iomap, lx, ly)
    items = collect(menu.elements)
    _, row_h = p.measure("M", p.font)
    width = 0
    for it in items
        it isa WidgetMenuItem && !(it.content isa WidgetDocument) || continue
        tw, _ = _text_size(p.measure, p.font, string(it.content))
        width = max(width, tw)
    end
    OpenPopupOperation(; id=:widget_popup, anchor=iomap.anchor,
                       dx=lx, dy=ly, width=max(width, 1) + 16,
                       height=max(1, length(items)) * row_h,
                       auto_dismiss=true, content=menu)
end

# ── WidgetDialog ──────────────────────────────────────────────────────────────

@projection struct WidgetDialogToGraphicsCanvas
    measure::Function
    title::ImmutableCell{DStyleText}        # title font + color
    body::ImmutableCell{DStyleText}         # content/label fallback font + color
    card_color::StyleColor  # card fill
    border::StyleStroke      # card outline
    corner_radius::Int
    padding::Inset
    gap::Int                # vertical gap between title / content / buttons
end

# Carries the centered card's bounds (for the backdrop hit-test) plus the content
# and button child-iomaps (for routing + re-rooting), all in dialog-canvas coords.
struct WidgetDialogToGraphicsCanvasIoMap <: IoMap
    projection::Any
    input::WidgetDialog
    output::GraphicsCanvas
    card::NTuple{4,Int}      # (x, y, w, h)
    content_entry::Any       # (ox, oy, cim) | nothing
    button_entries::Cell     # Vector of (ox, oy, cim)
end

function print_document(p::WidgetDialogToGraphicsCanvas, recursion, w::WidgetDialog, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    pad_x = _sc(Int(p.padding.left[])); pad_y = _sc(Int(p.padding.top[]))
    gap = _sc(p.gap); radius = _sc(p.corner_radius)
    # The dialog fills its (modal) window; the scrim covers that whole area.
    aw = ctx === nothing ? nothing : ctx.available_width
    ah = ctx === nothing ? nothing : ctx.available_height
    avail_w = aw !== nothing ? max(0, Int(aw[])) : 480
    avail_h = ah !== nothing ? max(0, Int(ah[])) : 320

    title = string(w.title)
    title_w, title_h = _text_size(p.measure, p.title.font, title)

    # Content: a recursed child widget, a plain string, or nothing.
    content = w.content
    content_iomap = nothing; content_w = 0; content_h = 0
    if content isa Document
        content_iomap = print_child(recursion, content, ctx)
        cc = content_iomap.output
        content_w, content_h = cc isa GraphicsCanvas ? (Int(cc.w[]), Int(cc.h[])) : (0, 0)
    elseif content !== nothing
        content_w, content_h = _text_size(p.measure, p.body.font, string(content))
    end

    # Buttons laid out in a row.
    button_iomaps = Any[]
    btn_w = 0; btn_h = 0
    for b in w.buttons
        b isa WidgetDocument || continue
        bim = print_child(recursion, b, ctx)
        bc = bim.output
        bw, bh = bc isa GraphicsCanvas ? (Int(bc.w[]), Int(bc.h[])) : (0, 0)
        push!(button_iomaps, (bim, bw, bh))
        btn_w += bw; btn_h = max(btn_h, bh)
    end
    nbtn = length(button_iomaps)
    nbtn > 1 && (btn_w += (nbtn - 1) * gap)

    has_content = content_w > 0 || content_h > 0
    has_buttons = nbtn > 0
    inner_w = max(title_w, content_w, btn_w)
    inner_h = title_h
    has_content && (inner_h += gap + content_h)
    has_buttons && (inner_h += gap + btn_h)
    card_w = inner_w + 2pad_x; card_h = inner_h + 2pad_y
    card_x = max(0, (avail_w - card_w) ÷ 2); card_y = max(0, (avail_h - card_h) ÷ 2)

    elements = Any[]
    push!(elements, GraphicsRect(0, 0, avail_w, avail_h, StyleColor(0.0, 0.0, 0.0, 0x66 / 255)))  # scrim
    _push_panel!(elements, card_x, card_y, card_w, card_h; fill=p.card_color,
                 border=p.border.color, border_w=max(1, _sc(p.border.width)), radius=radius)
    tx = card_x + pad_x; ty = card_y + pad_y
    _push_text!(elements, p.title.font, title, tx, ty, p.title.color)
    cursor_y = ty + title_h

    content_entry = nothing
    if has_content
        cursor_y += gap
        if content_iomap !== nothing
            ox = card_x + pad_x; oy = cursor_y
            push!(elements, _make_canvas(ox, oy, Any[content_iomap.output]))
            content_entry = (ox, oy, content_iomap)
        else
            _push_text!(elements, p.body.font, string(content), card_x + pad_x, cursor_y, p.body.color)
        end
        cursor_y += content_h
    end

    button_entries = Any[]
    if has_buttons
        cursor_y += gap
        bx = card_x + pad_x + max(0, inner_w - btn_w)   # right-align the row
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

# A dialog is centered, not anchored, so it is never a popup anchor source.
map_reference_forward(::WidgetDialogToGraphicsCanvas, iomap, reference) = nothing
# Content ops (e.g. an editable WidgetText field) re-root by prepending `.content`.
map_reference_backward(::WidgetDialogToGraphicsCanvas, iomap::WidgetDialogToGraphicsCanvasIoMap, reference) =
    reference === nothing ? nothing : ConcreteReferencePath(FieldReference("content"), reference)
map_reference_backward(::WidgetDialogToGraphicsCanvas, iomap, reference) = nothing

read_intent(::WidgetDialogToGraphicsCanvas, iomap::SimpleIoMap, evt) = nothing

# Esc / a backdrop click (on the scrim, outside the card) dismiss; a button click
# runs its action AND closes (one CompoundOperation); a click inside the card on
# the content routes to it (re-rooted through `.content`).
function read_intent(p::WidgetDialogToGraphicsCanvas, iomap::WidgetDialogToGraphicsCanvasIoMap, evt)
    pid = iomap.input.popup_id
    if evt isa KeyDown
        return evt.key === :escape ? CloseWindowOperation(pid) : nothing
    end
    evt isa MousePress || return nothing
    evt.button === :left || return nothing
    (cx, cy, cw, ch) = iomap.card
    (cx <= evt.x < cx + cw && cy <= evt.y < cy + ch) || return CloseWindowOperation(pid)
    bop = _route_click_to_children(iomap.button_entries[]::Vector, evt)
    bop !== nothing && return CompoundOperation(Any[bop, CloseWindowOperation(pid)])
    ce = iomap.content_entry
    ce === nothing && return nothing
    (ox, oy, cim) = ce
    op = read_intent(cim.projection, cim, MousePress(evt.button, evt.x - ox, evt.y - oy, evt.modifiers))
    _retarget_op(p, iomap, op)
end

# ── WidgetMenuItem ──────────────────────────────────────────────────────────

# Carries the anchor (the item's own document path, captured from `ctx.reference`
# at print time) and the rendered item size, so a submenu-opener item can open its
# `submenu` as a popup anchored just below itself without re-deriving its position
# (Step 4b, mirroring `WidgetSelect`). `child_iomaps` keeps scroll routing into
# embedded widget content working.
struct WidgetMenuItemToGraphicsCanvasIoMap <: IoMap
    projection::Any
    input::WidgetMenuItem
    output::GraphicsCanvas
    child_iomaps::Cell
    anchor::ReferencePath
    control_width::Int
    control_height::Int
end

# A bound command (Stage 4) supplies the item's label, enabled-state, and callback,
# so a menu item / toolbar button / shortcut can share one `Action`.
_menu_item_command(w::WidgetMenuItem) = (c = w.command; c isa Action ? c : nothing)
_menu_item_enabled(w::WidgetMenuItem) =
    !(w.enabled === false) && !((c = _menu_item_command(w)) !== nothing && c.enabled === false)
_menu_item_icon(w::WidgetMenuItem) = (c = _menu_item_command(w); (c !== nothing && c.icon !== nothing) ? c.icon : w.icon)

function print_document(p::WidgetMenuItemToGraphicsCanvas, recursion, w::WidgetMenuItem, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    cox, coy = _content_offset(w)
    command = _menu_item_command(w)
    enabled = _menu_item_enabled(w)
    fg = enabled ? p.text.color : p.disabled_foreground
    # A bound command's label overrides the content; otherwise the content is the
    # label (text) or a recursed widget.
    content = command !== nothing ? string(command.label) : w.content
    child_iomaps = Any[]
    elems = Any[]
    cw, ch = 0, 0
    if content isa WidgetDocument
        cim = print_child(recursion, content, ctx)
        inner = cim.output
        cw, ch = inner isa GraphicsCanvas ? (Int(inner.w[]), Int(inner.h[])) : (0, 0)
        push!(child_iomaps, (cox, coy, cim))
        push!(elems, _make_canvas(cox, coy, Any[inner]))
    else
        text = string(content)
        cw, ch = _text_size(p.measure, p.text.font, text)
        # Optional leading icon (Stage 5), tinted to the item's foreground.
        icon = _menu_item_icon(w)
        icon_w = icon_width(icon, ch)
        gap = icon_w > 0 ? _sc(6) : 0
        icon_w > 0 && _push_icon!(elems, icon, cox, coy, ch, fg)
        _push_text!(elems, p.text.font, text, cox + icon_w + gap, coy, fg)
        cw += icon_w + gap
    end
    # Hover surface behind the content (Stage 6), only when hovered + enabled.
    control_w = cw + 2cox; control_h = ch + 2coy
    final = Any[]
    _push_hover_surface!(final, w, enabled, control_w, control_h, p.hover_color)
    append!(final, elems)
    # Bound the canvas to the item's own footprint so `hit_element_at` clips pointer
    # events to it. A `GraphicsText` has no right edge, so an auto-sized (w=h=0) item
    # canvas would claim hits anywhere to the right of its label — harmless in a
    # vertical menu (per-item y-bands differ) but in a *horizontal* toolbar / menu
    # bar the leftmost item then swallows every crossing, so hover always lit the
    # first button. See `hit_element_at` in document/Graphics.jl.
    WidgetMenuItemToGraphicsCanvasIoMap(p, w, _make_canvas(0, 0, control_w, control_h, final),
                                        Cell(child_iomaps), ctx.reference,
                                        control_w, control_h)
end

# Forward image (Step 2.0 leaf): the empty reference maps to the item's own
# top-left so a content-root resolver can anchor a submenu popup under it; parent
# containers shift it on the way up. Invisible item / non-empty ref: no image.
map_reference_forward(::WidgetMenuItemToGraphicsCanvas, iomap::WidgetMenuItemToGraphicsCanvasIoMap, reference) =
    _self_point(reference)
map_reference_forward(::WidgetMenuItemToGraphicsCanvas, iomap::SimpleIoMap, reference) = nothing
map_reference_backward(::WidgetMenuItemToGraphicsCanvas, iomap, reference) = nothing

# Invisible item (printer returned a bare empty canvas): inert.
read_intent(::WidgetMenuItemToGraphicsCanvas, ::SimpleIoMap, evt) = nothing

function read_intent(p::WidgetMenuItemToGraphicsCanvas, iomap::WidgetMenuItemToGraphicsCanvasIoMap, evt)
    w = iomap.input
    # Per-instance gestures win over the built-in click/submenu handling (an enabled
    # item only, matching the built-in gate). Hover crossings below are unaffected.
    if _menu_item_enabled(w)
        op = read_bound_gesture(w, evt)
        op === nothing || return op
    end
    if evt isa MousePress
        # A left click on an enabled item: open its submenu if it has one, else
        # invoke its bound command (Stage 4) or its plain action, and dismiss the
        # enclosing popup (a no-op when rendered inline). Disabled (item or bound
        # command) ⇒ inert.
        (evt.button === :left && _menu_item_enabled(w)) || return nothing
        submenu = w.submenu
        submenu === nothing || return _open_submenu_popup(p, submenu, iomap)
        command = _menu_item_command(w)
        invoke = command !== nothing ? InvokeActionOperation(command) :
                                       InvokeWidgetActionOperation(w)
        return CompoundOperation(Any[invoke, CloseWindowOperation(:widget_popup)])
    end
    (evt isa MouseEnter || evt isa MouseLeave) && return _hover_state_op(w, evt)
    evt isa MouseScroll || return nothing
    _route_scroll_to_children(iomap.child_iomaps[]::Vector, evt)
end

# Open the item's `submenu` as a floating popup anchored just below the item,
# reusing the WidgetSelect dropdown route (Step 3c): an anchor-relative
# `OpenPopupOperation` the content-root resolver turns into an absolute window.
# Size the popup to the submenu's rows (its items share this item's row metrics);
# placement beyond "below, clamped" is left to anchored-layout.md.
function _open_submenu_popup(p::WidgetMenuItemToGraphicsCanvas, submenu,
                             iomap::WidgetMenuItemToGraphicsCanvasIoMap)
    items = collect(submenu.elements)
    gap = 4
    row_h = iomap.control_height
    width = iomap.control_width
    for it in items
        it isa WidgetMenuItem && !(it.content isa WidgetDocument) || continue
        icox, _ = _content_offset(it)
        tw, _ = _text_size(p.measure, p.text.font, string(it.content))
        width = max(width, tw + 2icox)
    end
    OpenPopupOperation(; id=:widget_popup, anchor=iomap.anchor,
                       dx=0, dy=row_h + gap, width=width,
                       height=max(1, length(items)) * row_h,
                       auto_dismiss=true, content=submenu)
end

# ── WidgetMenu ──────────────────────────────────────────────────────────────

# A laid-out item's advance along the main axis. A `WidgetMenuItem` knows its own
# rendered width (its canvas is 0-sized — the size lives on the iomap); any other
# widget carries it on its output canvas.
_menu_item_width(cim) =
    cim isa WidgetMenuItemToGraphicsCanvasIoMap ? cim.control_width :
        (cim.output isa GraphicsCanvas ? Int(cim.output.w[]) : 0)

function print_document(p::WidgetMenuToGraphicsCanvas, recursion, w::WidgetMenu, ctx)
    w.visible == false && return ChildrenIoMap(p, w, _empty_canvas(), Cell(Any[]))
    cox, coy = _content_offset(w)
    horizontal = w.orientation === :horizontal
    child_iomaps = Any[]
    elems = Any[]
    x_cursor = cox
    y_cursor = coy
    _, item_h = p.measure("M", p.font)
    item_gap = horizontal ? 12 : 0
    for (i, item) in enumerate(w.elements)
        item isa WidgetDocument || continue
        # Extend the reference per item so a nested trigger (e.g. a submenu-opener)
        # captures `…elements[i]` as its anchor, which a content-root resolver can
        # forward-map back to graphics coordinates (Step 4c).
        cctx = make_child_context(ctx, FieldReference("elements"), RangeReference(i - 1, i))
        cim = print_child(recursion, item, cctx)
        push!(child_iomaps, (x_cursor, y_cursor, cim))
        push!(elems, _make_canvas(x_cursor, y_cursor, Any[cim.output]))
        if horizontal
            x_cursor += _menu_item_width(cim) + item_gap
        else
            y_cursor += item_h
        end
    end
    ChildrenIoMap(p, w, _make_canvas(0, 0, elems), Cell(child_iomaps))
end

# `elements[i]/…` routes to the i-th item's forward image, shifted by where this
# menu placed it (paths pass through). Orientation-agnostic: the per-item offset is
# stored on the entry regardless of layout direction.
map_reference_forward(::WidgetMenuToGraphicsCanvas, iomap::ChildrenIoMap, reference) =
    _forward_descend(iomap.child_iomaps[]::Vector, "elements", reference)

function map_reference_backward(::WidgetMenuToGraphicsCanvas, iomap, reference)
    return nothing
end

function read_intent(::WidgetMenuToGraphicsCanvas, iomap::ChildrenIoMap, evt)
    child_iomaps = iomap.child_iomaps[]::Vector
    evt isa MousePress && return _route_click_to_children(child_iomaps, evt)
    (evt isa MouseEnter || evt isa MouseLeave) && return _route_crossing_to_children(child_iomaps, evt)
    evt isa MouseScroll || return nothing
    _route_scroll_to_children(child_iomaps, evt)
end

# ── WidgetComposite ─────────────────────────────────────────────────────────

function print_document(p::WidgetCompositeToGraphicsCanvas, recursion, w::WidgetComposite, ctx)
    w.visible == false && return ChildrenIoMap(p, w, _empty_canvas(), Cell(Any[]))
    pos = w.position::Point2D
    cox, coy = _content_offset(w)
    child_iomaps = Any[]
    elems = Any[]
    for child in w.elements
        # A composite renders widget children and embedded layout children (e.g.
        # a GridLayout form from ObjectToWidget); both re-enter the recursion.
        (child isa WidgetDocument || child isa LayoutDocument) || continue
        cim = print_child(recursion, child, ctx)
        push!(child_iomaps, (cox, coy, cim))
        push!(elems, _make_canvas(cox, coy, Any[cim.output]))
    end
    ChildrenIoMap(p, w, _make_canvas(_origin(pos)..., elems), Cell(child_iomaps))
end

# A composite addresses children by `elements[i]`, each wrapped at the content
# offset; forward-mapping shifts a coordinate image by that placement (paths pass
# through). Same hop as a layout, just a different field name.
map_reference_forward(::WidgetCompositeToGraphicsCanvas, iomap::ChildrenIoMap, reference) =
    _forward_descend(iomap.child_iomaps[]::Vector, "elements", reference)

function map_reference_backward(::WidgetCompositeToGraphicsCanvas, iomap, reference)
    return nothing
end

# Route events to composite children and re-root the returned op. A MousePress
# is hit-tested against each child canvas; a coordless event (KeyPress/KeyDown)
# goes to the child the composite's selection points at, falling back to trying
# each child. The op a child returns is re-rooted by prepending `elements[i]` —
# the same scheme WidgetSplitPane uses. Identity-bearing ops (ReplaceReferencedValueOperation
# from a control) pass through `reroot_operation` unchanged.
function read_intent(p::WidgetCompositeToGraphicsCanvas, iomap::ChildrenIoMap, evt)
    child_iomaps = iomap.child_iomaps[]::Vector
    # Tab traversal (Stage 2): distributed focus advance. Handle before the generic
    # selection-only routing so a Tab the selected child declines can advance my
    # own selection to the next focusable sibling.
    if iomap.input isa WidgetComposite && evt isa KeyDown && evt.key === :tab
        return _composite_tab(iomap.input, child_iomaps, evt)
    end
    res = @event_case evt begin
        MouseScroll => _route_composite_event(child_iomaps, evt.x, evt.y,
            (x, y) -> MouseScroll(evt.dx, evt.dy, x, y))
        MousePress => _route_composite_event(child_iomaps, evt.x, evt.y,
            (x, y) -> MousePress(evt.button, x, y, evt.modifiers))
        MouseDown => _route_composite_event(child_iomaps, evt.x, evt.y,
            (x, y) -> MouseDown(evt.button, x, y, evt.modifiers))
        MouseUp => _route_composite_event(child_iomaps, evt.x, evt.y,
            (x, y) -> MouseUp(evt.button, x, y, evt.modifiers))
        MouseEnter => _route_composite_event(child_iomaps, evt.x, evt.y,
            (x, y) -> MouseEnter(x, y, evt.buttons, evt.modifiers))
        MouseLeave => _route_composite_event(child_iomaps, evt.x, evt.y,
            (x, y) -> MouseLeave(x, y, evt.buttons, evt.modifiers))
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
    res === nothing && return nothing
    op, slot_idx = res
    reroot_operation(op, (FieldReference("elements"), RangeReference(slot_idx - 1, slot_idx)))
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
        result = read_intent(cim.projection, cim, make_evt(lx, ly))
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
function _selected_composite_slot(w::WidgetComposite, n::Int)
    sel = getfield(w, :selection)[]
    sel = sel
    sel isa ConcreteReferencePath || return 0
    (sel.head isa FieldReference && sel.head.name == "elements") || return 0
    t = sel.tail
    (t isa ConcreteReferencePath && t.head isa RangeReference) || return 0
    slot = t.head.start + 1
    1 <= slot <= n ? slot : 0
end

# The focus-path helpers (`first_focusable_path`, `last_focusable_path`,
# `_next_focusable_in`, `_focusable_path`, `FocusableWidget`) live in `WidgetModule`
# (document layer) so the `LayoutToGraphics` reader — included *before* this module
# — can share them for Tab traversal. They are imported at the top of this file.

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
# non-local case and is NOT handled here — it needs a single top-level rule
# (a follow-up; see plan/pending/widget-focus-traversal.md). Until then Tab
# advances forward and stops at the last focusable.
function _composite_tab(w::WidgetComposite, child_iomaps::Vector, evt)
    n = length(child_iomaps)
    reverse = evt.modifiers.shift
    i = _selected_composite_slot(w, n)
    if i == 0
        # Selection is on me, not a child (∅), or I am the unselected root:
        # focus my first (last) leaf.
        sub = reverse ? last_focusable_path(w) : first_focusable_path(w)
        return sub === nothing ? nothing : ReplaceSelectionOperation(sub)
    end
    # Delegate to the selected child; an internal advance re-roots through me.
    deleg = _forward_composite_event_slot(child_iomaps, evt, i)
    if deleg !== nothing
        op, slot = deleg
        return reroot_operation(op, (FieldReference("elements"), RangeReference(slot - 1, slot)))
    end
    # Child declined: advance to my next focusable sibling, entering its first leaf.
    j = _next_focusable_in(w.elements, i, reverse)
    j == 0 && return nothing                      # no next sibling — I decline; parent advances.
    sub = reverse ? last_focusable_path(w.elements[j]) : first_focusable_path(w.elements[j])
    sub === nothing && return nothing
    ReplaceSelectionOperation(ConcreteReferencePath(FieldReference("elements"),
        ConcreteReferencePath(RangeReference(j - 1, j), sub)))
end

# ── WidgetShell ─────────────────────────────────────────────────────────────

function print_document(p::WidgetShellToGraphicsCanvas, recursion, w::WidgetShell, ctx)
    w.visible == false && return ChildrenIoMap(p, w, _empty_canvas(), Cell(Any[]))
    cox, coy = _content_offset(w)
    elems = Any[]
    child_iomaps = Any[]
    sz  = w.size
    if sz isa Point2D
        push!(elems, GraphicsRect(cox, coy, Int(sz.x[]), Int(sz.y[]), p.background_color))
    end
    content_y = coy
    mb = w.menu_bar
    if mb isa WidgetDocument
        # Extend the reference into `menu_bar` so a menu-bar entry's submenu anchor
        # (`menu_bar.elements[i]`) forward-maps back through the shell (Step 4c).
        mb_ctx = make_child_context(ctx, FieldReference("menu_bar"))
        cim = print_child(recursion, mb, mb_ctx)
        push!(child_iomaps, (cox, content_y, cim))
        push!(elems, _make_canvas(cox, content_y, Any[cim.output]))
        _, menu_h = p.measure("M", p.font)
        content_y += menu_h
    end
    tb = w.toolbar
    if tb isa WidgetDocument
        cim = print_child(recursion, tb, ctx)
        push!(child_iomaps, (cox, content_y, cim))
        push!(elems, _make_canvas(cox, content_y, Any[cim.output]))
        _, toolbar_h = p.measure("M", p.font)
        content_y += toolbar_h + p.band_gap
    end
    # Status bar (Stage 4): reserve a fixed-height bottom band so the content does
    # not draw under it; it is placed at the shell's bottom after the content.
    sb = w.status_bar
    _, status_h = sb isa WidgetDocument ? p.measure("M", p.font) : (0, 0)
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
        status_h_now = status_h
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
            max(0, Int(sz.y[]) - ty - (content_y_now - coy_now) - status_h_now)
        end)
        content_ctx = with_available_size(ctx; width=avail_w_cell, height=avail_h_cell)
        cim = print_child(recursion, content, content_ctx)
        push!(child_iomaps, (cox, content_y, cim))
        push!(elems, _make_canvas(cox, content_y, Any[cim.output]))
    end
    # Place the status bar along the shell's bottom edge (a fixed print-time y from
    # the size; live-resize repositioning is a v1 limitation, like the other bands).
    if sb isa WidgetDocument && sz isa Point2D
        cim = print_child(recursion, sb, ctx)
        _, ty = _inset_total(w)
        sb_y = coy + Int(sz.y[]) - ty - status_h
        push!(child_iomaps, (cox, sb_y, cim))
        push!(elems, _make_canvas(cox, sb_y, Any[cim.output]))
    end
    tt = w.tooltip
    if tt isa WidgetDocument
        cim = print_child(recursion, tt, ctx)
        push!(child_iomaps, (0, 0, cim))
        push!(elems, _make_canvas(0, 0, Any[cim.output]))
    end
    ChildrenIoMap(p, w, _make_canvas(0, 0, elems), Cell(child_iomaps))
end

# A shell renders several field-addressed children (`menu_bar`, `toolbar`,
# `content`, `tooltip`), each wrapped at its band offset. Descend the leading
# field step to the matching child (found by identity, since the bands are
# positional/conditional) and shift a coordinate image by that placement; paths
# and unknown fields pass through with no image. Step 4c completes the Step 2.0
# deferral for the menu-bar path so a menu-bar entry's submenu anchor resolves.
_shell_field(w, name) =
    name == "menu_bar" ? w.menu_bar :
    name == "toolbar"  ? w.toolbar  :
    name == "content"  ? w.content  :
    name == "tooltip"  ? w.tooltip  : nothing

function map_reference_forward(::WidgetShellToGraphicsCanvas, iomap::ChildrenIoMap, reference)
    reference isa ConcreteReferencePath || return nothing
    head = reference.head
    head isa FieldReference || return nothing
    target = _shell_field(iomap.input, head.name)
    target === nothing && return nothing
    for entry in iomap.child_iomaps[]::Vector
        entry === nothing && continue
        (ox, oy, cim) = entry
        cim.input === target || continue
        child = map_reference_forward(cim.projection, cim, reference.tail)
        return _shift_child_image(child, ox, oy, cim)
    end
    nothing
end

map_reference_forward(::WidgetShellToGraphicsCanvas, iomap, reference) = nothing

# The shell wraps a single child widget as its `.content` field. A path
# coming up from the child's reader lives at `.content.<rest>` in the
# shell's input domain.
function map_reference_backward(p::WidgetShellToGraphicsCanvas, iomap::ChildrenIoMap, reference)
    reference === nothing && return nothing
    ConcreteReferencePath(FieldReference("content"), reference)
end

# Collect the shared `Action`s that carry a keyboard shortcut, reachable from a
# shell's `menu_bar` + `toolbar` (recursing submenus). The menu *is* the shortcut
# registry, so there is no separate list to keep in sync (Stage 4).
function _collect_command_actions!(acc::Vector{Action}, w)
    if w isa WidgetMenuItem
        c = w.command; (c isa Action && c.shortcut !== nothing) && push!(acc, c)
        sm = w.submenu; sm isa WidgetMenu && _collect_command_actions!(acc, sm)
    elseif w isa WidgetButton
        c = w.command; (c isa Action && c.shortcut !== nothing) && push!(acc, c)
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
    # Stage 4 shortcuts: a `KeyDown` matching an (enabled) menu/toolbar command's
    # shortcut fires it globally — before the focused child sees the key — so e.g.
    # Ctrl+S works regardless of which widget is selected.
    if evt isa KeyDown
        for action in _shell_shortcut_actions(iomap.input)
            action_shortcut_matches(action, evt) && return InvokeActionOperation(action)
        end
    end
    child_iomaps = iomap.child_iomaps[]::Vector
    op = @event_case evt begin
        MouseScroll => _route_scroll_to_children(child_iomaps, evt)
        MousePress  => _route_click_to_children(child_iomaps, evt)
        # Pointer motion / crossings carry coordinates: route them to the band under
        # the pointer (coordinate-translated), so a hovered widget inside the content
        # band gets the MouseMove/MouseEnter/MouseLeave the hover tracker synthesises.
        MouseMove   => _route_move_to_children(child_iomaps, evt)
        MouseEnter  => _route_crossing_to_children(child_iomaps, evt)
        MouseLeave  => _route_crossing_to_children(child_iomaps, evt)
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
    cox, coy = _content_offset(w)
    elems = Any[]
    child_iomaps = Any[]
    title = string(w.title)
    tw, th = _text_size(p.measure, p.title_text.font, title)
    # Card-like: bold title, body in the content style.
    _push_text!(elems, p.title_text.font, title, cox, coy, p.title_text.color)
    content_y = coy + th + _sc(p.title_gap)
    content = w.content
    if content isa Document
        cim = print_child(recursion, content, ctx)
        push!(child_iomaps, (cox, content_y, cim))
        push!(elems, _make_canvas(cox, content_y, Any[cim.output]))
    elseif content isa AbstractString
        _push_text!(elems, p.content_text.font, content, cox, content_y, p.content_text.color)
    end
    ChildrenIoMap(p, w, _make_canvas(0, 0, elems), Cell(child_iomaps))
end

function map_reference_forward(::WidgetTitlePaneToGraphicsCanvas, iomap, reference)
    return nothing
end

function map_reference_backward(::WidgetTitlePaneToGraphicsCanvas, iomap, reference)
    return nothing
end

function read_intent(::WidgetTitlePaneToGraphicsCanvas, iomap::ChildrenIoMap, evt)
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
preferred when present, or fall back to the `sizes` vector, or to 200 px when
neither is set.
"""
function _split_intrinsic(elem, sizes, i::Int, axis::Symbol)
    intrinsic = (!isempty(sizes) && i <= length(sizes)) ? Int(sizes[i]) : _SPLIT_SLOT_FALLBACK
    layout_preferred(elem, axis, intrinsic)
end

function print_document(p::WidgetSplitPaneToGraphicsCanvas, recursion, w::WidgetSplitPane, ctx)
    w.visible == false && return ChildrenIoMap(p, w, _empty_canvas(), Cell(Any[]))
    cox, coy = _content_offset(w)
    orientation = w.orientation::Symbol
    main_axis = orientation === :horizontal ? :x : :y
    sizes = w.sizes
    splitter_thickness = max(1, _sc(p.splitter.width))
    splitter_color = p.splitter.color

    # Keep only Document children; a LayoutConstraint wrapper or a bare
    # document of any domain both work — the wrapper is transparent for
    # projection (we recurse into `elem.child`) and consulted for sizing policy.
    valid_elems = Any[]
    for i in 1:length(w.elements)
        elem = w.elements[i]
        (elem isa LayoutConstraint || elem isa Document) && push!(valid_elems, elem)
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
    # The allocation is a forward-declared *reactive* cell: slot cells read it now
    # (before it has a value) and the real allocation thunk is installed via
    # `set_cell_function!` once intrinsic sizes are readable (below). Reading it before then
    # yields `nothing` → a transient 0 slot; `set_cell_function!` invalidates the slot cells so
    # they recompute with the real allocation. (A plain `Ref` was not reactive, so
    # a slot forced early — e.g. by a follow-end scroll pane measuring its
    # word-wrapped content — both crashed and could cache a stale size.)
    alloc_cell = Cell(nothing)
    slot_main = Cell[]
    if avail_main !== nothing
        for i in 1:n
            push!(slot_main, Cell(() -> begin v = alloc_cell[]; v === nothing ? 0 : Int(v[i]) end))
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
        cim = print_child(recursion, inner, cctx)
        push!(inner_iomaps, cim)
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
        set_cell_function!(alloc_cell, function ()
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
                                           splitter_color))
                cursor += splitter_thickness
            end
        else
            cursor = coy
            for i in 1:(n-1)
                cursor += Int(slot_main[i][])
                push!(result, GraphicsRect(cox, cursor, cross_extent, splitter_thickness,
                                           splitter_color))
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

# Index `k` (1-based) of the splitter band under `(x, y)`, or 0 if none.
# Splitter `k` occupies the `thickness`-wide gap immediately before child `k+1`
# (see the print cursor), widened by `tol` on each side along the main axis.
function _splitter_band_hit(orientation::Symbol, child_iomaps::Vector,
                            thickness::Int, x::Int, y::Int, tol::Int)
    n = length(child_iomaps)
    coord = orientation === :horizontal ? x : y
    for k in 1:(n - 1)
        nxt = child_iomaps[k + 1]
        nxt === nothing && continue
        gap_end   = _split_child_main_pos(nxt, orientation)
        gap_start = gap_end - thickness
        (gap_start - tol <= coord <= gap_end + tol) && return k
    end
    0
end

# Currently measured main-axis extent of every slot. Inner slots are the
# distance between consecutive child positions minus the splitter; the last
# slot fills to the far edge of the pane (the outer canvas's main extent minus
# the last child's start and the near inset, assumed symmetric) — the child
# canvas itself can't be trusted as it may not expand to fill its slot. Used to
# seed `sizes` on the first drag so it starts from the on-screen layout.
function _split_measured_sizes(child_iomaps::Vector, orientation::Symbol,
                               thickness::Int, outer_main::Int)
    n = length(child_iomaps)
    sizes = Vector{Int}(undef, n)
    pos(i) = _split_child_main_pos(child_iomaps[i], orientation)
    for i in 1:(n - 1)
        sizes[i] = pos(i + 1) - pos(i) - thickness
    end
    sizes[n] = max(0, outer_main - pos(n) - pos(1))
    sizes
end

# Drag lifecycle for the splitter gaps. Returns an Operation when the event
# starts, continues, or ends a drag; `nothing` lets the event fall through to
# the normal child-routing path below. A `MouseDown` on a band starts a drag;
# `MouseMove` while a drag is active resizes the two adjacent slots relative to
# the grab origin (so rounding doesn't accumulate); `MouseUp` ends it.
function _split_drag_read(p::WidgetSplitPaneToGraphicsCanvas, iomap::ChildrenIoMap,
                          w::WidgetSplitPane, evt)
    child_iomaps = iomap.child_iomaps[]::Vector
    n = length(child_iomaps)
    n < 2 && return nothing
    orientation = w.orientation::Symbol
    thickness   = max(1, _sc(p.splitter.width))
    active      = w.active_splitter::Int

    if evt isa MouseDown && evt.button === :left && active == 0
        k = _splitter_band_hit(orientation, child_iomaps, thickness, evt.x, evt.y, _SPLITTER_GRAB_TOL)
        k == 0 && return nothing
        outer = iomap.output
        outer_main = outer isa GraphicsCanvas ?
                     (orientation === :horizontal ? Int(outer.w[]) : Int(outer.h[])) : 0
        slot_sizes = _split_measured_sizes(child_iomaps, orientation, thickness, outer_main)
        coord = orientation === :horizontal ? evt.x : evt.y
        return StartSplitterDragOperation(w, k, coord, slot_sizes)
    elseif evt isa MouseMove && active != 0
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
        return ResizeSplitPaneOperation(w, k, new_a, new_b)
    elseif evt isa MouseUp && evt.button === :left && active != 0
        return EndSplitterDragOperation(w)
    end
    nothing
end

function read_intent(p::WidgetSplitPaneToGraphicsCanvas, iomap::ChildrenIoMap, evt)
    w = iomap.input
    if w isa WidgetSplitPane
        drag = _split_drag_read(p, iomap, w, evt)
        drag !== nothing && return drag
    end
    child_iomaps = iomap.child_iomaps[]::Vector
    # Tab traversal (Stage 2): distributed focus advance, handled before the
    # selection-only coordless routing.
    if w isa WidgetSplitPane && evt isa KeyDown && evt.key === :tab
        return _split_tab(w, child_iomaps, evt)
    end
    res = @event_case evt begin
        MouseScroll => _route_split_event(child_iomaps, evt.x, evt.y,
            (x, y) -> MouseScroll(evt.dx, evt.dy, x, y))
        MousePress => _route_split_event(child_iomaps, evt.x, evt.y,
            (x, y) -> MousePress(evt.button, x, y, evt.modifiers))
        # Coordinate-bearing pointer events (a non-drag press/release, plain motion,
        # and the hover crossings) route to the slot *under the pointer*, exactly as
        # the composite does — a hover crossing must reach whatever the pointer is
        # over, not the selected slot (routing these to the selection left the
        # navigator, and any other unselected pane, unhoverable). A splitter drag was
        # already consumed above by `_split_drag_read`, so a `MouseDown`/`MouseMove`/
        # `MouseUp` reaching here is not part of a drag and belongs to a child.
        MouseDown => _route_split_event(child_iomaps, evt.x, evt.y,
            (x, y) -> MouseDown(evt.button, x, y, evt.modifiers))
        MouseUp => _route_split_event(child_iomaps, evt.x, evt.y,
            (x, y) -> MouseUp(evt.button, x, y, evt.modifiers))
        MouseMove => _route_split_event(child_iomaps, evt.x, evt.y,
            (x, y) -> MouseMove(x, y, evt.buttons, evt.modifiers))
        MouseEnter => _route_split_event(child_iomaps, evt.x, evt.y,
            (x, y) -> MouseEnter(x, y, evt.buttons, evt.modifiers))
        MouseLeave => _route_split_event(child_iomaps, evt.x, evt.y,
            (x, y) -> MouseLeave(x, y, evt.buttons, evt.modifiers))
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
    res === nothing && return nothing
    op, slot_idx = res
    # The slot at `iomap.input.elements[slot_idx]` may be wrapped in a
    # LayoutConstraint; if so, the projector descended into `.child`, and
    # the backward path must walk through it.
    elem = iomap.input.elements[slot_idx]
    steps = elem isa LayoutConstraint ?
            (FieldReference("elements"), RangeReference(slot_idx-1, slot_idx), FieldReference("child")) :
            (FieldReference("elements"), RangeReference(slot_idx-1, slot_idx))
    reroot_operation(op, steps)
end

# Tab traversal for a split pane (Stage 2), mirroring `_composite_tab` but with the
# split's slot shape: slots live under `elements[i]`, optionally wrapped in a
# `LayoutConstraint` (then the path walks through `.child`). `first_focusable_path`
# descends through the LayoutConstraint's `child` field generically, so the advance
# path is correct without special-casing; only the *delegate* re-rooting needs the
# `.child` step (as the reader above does).
function _split_tab(w::WidgetSplitPane, child_iomaps::Vector, evt)
    n = length(child_iomaps)
    reverse = evt.modifiers.shift
    i = _selected_split_slot(w, n)
    if i == 0
        sub = reverse ? last_focusable_path(w) : first_focusable_path(w)
        return sub === nothing ? nothing : ReplaceSelectionOperation(sub)
    end
    deleg = _forward_split_event_slot(child_iomaps, evt, i)
    if deleg !== nothing
        op, slot = deleg
        elem = w.elements[slot]
        steps = elem isa LayoutConstraint ?
                (FieldReference("elements"), RangeReference(slot-1, slot), FieldReference("child")) :
                (FieldReference("elements"), RangeReference(slot-1, slot))
        return reroot_operation(op, steps)
    end
    j = _next_focusable_in(w.elements, i, reverse)
    j == 0 && return nothing
    sub = reverse ? last_focusable_path(w.elements[j]) : first_focusable_path(w.elements[j])
    sub === nothing && return nothing
    ReplaceSelectionOperation(ConcreteReferencePath(FieldReference("elements"),
        ConcreteReferencePath(RangeReference(j - 1, j), sub)))
end

# The split slot the node's forward-projected selection points at. The
# projected selection has the shape `elements[slot].child.<rest>`, so the
# unit-range step right after the `elements` field names the slot. Returns 0
# when the split carries no such selection (route by fallback then).
function _selected_split_slot(w::WidgetSplitPane, n::Int)
    sel = getfield(w, :selection)[]
    sel = sel
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
    result = read_intent(cim.projection, cim, evt)
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
        result = read_intent(cim.projection, cim, make_evt(lx, ly))
        result !== nothing && return (result, i)
    end
    nothing
end

# ── WidgetTabbedPane ────────────────────────────────────────────────────────

# Shared tab-strip layout, so the printer's drawing and the reader's hit-testing /
# scroll-clamping agree exactly (including any per-tab icon width — measuring text
# only would shift the reader's tab boundaries left of where they are drawn). Returns
# the content offset, the tab padding, the strip height, the natural strip width, and
# one tuple per tab: `(label, icon, icon_w, gap, x, rw)` where `x`/`rw` are the tab's
# left edge and full width in strip coordinates.
function _tab_strip_geometry(p::WidgetTabbedPaneToGraphicsCanvas, w::WidgetTabbedPane)
    cox, coy = _content_offset(w)
    sel_pad = p.tab_padding
    tabs = Any[]   # (label, icon, icon_w, gap, x, rw)
    tab_h = 0
    x = cox
    for pair in w.selector_element_pairs
        label = string(pair.selector)
        icon  = pair.icon
        tw, th = _text_size(p.measure, p.font, label)
        iw  = icon_width(icon, th)
        gap = iw > 0 ? _sc(6) : 0
        rw  = tw + iw + gap + 2 * sel_pad
        push!(tabs, (label, icon, iw, gap, x, rw))
        x += rw
        tab_h = max(tab_h, th)
    end
    sel_h = tab_h + 2 * sel_pad
    strip_w = isempty(tabs) ? 0 : (tabs[end][5] + tabs[end][6] - cox)
    (cox, coy, sel_pad, sel_h, strip_w, tabs)
end

# Rendered horizontal scroll offset of the strip: the stored `tab_scroll` clamped to
# the strip's overflow past the viewport (0 when it fits). Shared by printer (draws
# at `-offset`) and reader (offsets hit-testing and the scroll delta base).
_tab_scroll_offset(w::WidgetTabbedPane, strip_w::Int, view_w::Int) =
    clamp(Int(getfield(w, :tab_scroll)[]), 0, max(0, strip_w - view_w))

function print_document(p::WidgetTabbedPaneToGraphicsCanvas, recursion, w::WidgetTabbedPane, ctx)
    w.visible == false && return ChildrenIoMap(p, w, _empty_canvas(), Cell(Any[]))
    pairs = w.selector_element_pairs
    child_iomaps = Any[]
    if isempty(pairs)
        return ChildrenIoMap(p, w, _empty_canvas(), Cell(child_iomaps))
    end

    cox, coy, sel_pad, sel_h, strip_w, tabs = _tab_strip_geometry(p, w)

    sel_cell = getfield(w, :selection)

    _active_idx(sel) = begin
        i = _tab_index_from_selection(sel, length(tabs))
        i == 0 ? 1 : i
    end

    selector_cv = CellVector(() -> begin
        active = _active_idx(sel_cell[])
        result = Any[]
        tab_radius = _sc(p.corner_radius)
        # Muted track behind the whole tab row.
        _push_panel!(result, cox, coy, strip_w, sel_h; fill=p.track_color, radius=tab_radius)
        for i in eachindex(tabs)
            label, icon, iw, gap, tx, rw = tabs[i]
            if i == active
                # Active tab: a raised background pill.
                _push_panel!(result, tx, coy, rw, sel_h; fill=p.active_color, radius=tab_radius)
            end
            fg = i == active ? p.active_foreground : p.inactive_foreground
            iw > 0 && _push_icon!(result, icon, tx + sel_pad, coy + sel_pad, iw, fg)
            _push_text!(result, p.font, label, tx + sel_pad + iw + gap, coy + sel_pad, fg)
        end
        result
    end)

    # Seed a reduced available extent for the tab content. The content lives
    # inside the pane's border (offset `cox`/`coy`) and below the tab strip,
    # so subtract the horizontal insets from the width and the tab strip plus
    # vertical insets from the height — otherwise the content is allocated the
    # full extent yet drawn at the inset, overhanging the pane (cf.
    # WidgetTitlePane above).
    avail_w = ctx.available_width
    avail_h = ctx.available_height
    # Distinct names: `tx` is reused below as a tab x-position inside the
    # selector builder loop, so capturing it here would alias that closure's
    # local and clobber the selector viewport width.
    inset_x, inset_y = _inset_total(w)
    sel_h_const = sel_h
    avail_w_inner = avail_w === nothing ? nothing :
        Cell(() -> max(0, Int(avail_w[]) - inset_x))
    avail_h_inner = avail_h === nothing ? nothing :
        Cell(() -> max(0, Int(avail_h[]) - sel_h_const - inset_y))
    content_ctx = (avail_w === nothing && avail_h === nothing) ? ctx :
        with_available_size(ctx; width=avail_w_inner, height=avail_h_inner)
    all_cims = Any[]
    for pair in pairs
        content = pair.element
        if content !== nothing
            cim = print_child(recursion, content, content_ctx)
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

    # Clip the selector row to the pane's own width so a tab strip wider than
    # the tabbed pane cannot overflow the widget. When the parent seeded an
    # available width, clip to the content box (allocation minus insets) using the
    # distinctly-named `inset_x` (computed above); otherwise there is no constraint,
    # so the viewport is as wide as the strip and clips nothing.
    sel_view_w = if avail_w === nothing
        Cell(Int32(strip_w))
    else
        Cell(() -> Int32(max(0, Int(avail_w[]) - inset_x)))
    end
    # Horizontal scroll: when the strip is wider than the viewport, shift its inner
    # canvas left by the clamped `tab_scroll` so overflow tabs scroll into view (a
    # wheel over the strip drives it — see read_intent). Reactive on both the
    # stored offset and the viewport width.
    scroll_x = Cell(() -> Int32(-cox - _tab_scroll_offset(w, strip_w, Int(sel_view_w[]))))
    # The viewport sits at the content origin; its inner canvas is shifted back
    # by that origin (minus any scroll) so the strip elements keep their original
    # coordinates at scroll 0.
    selector_viewport = GraphicsViewport(
        Cell(Int32(cox)), Cell(Int32(coy)), sel_view_w, Cell(Int32(sel_h)),
        Cell(GraphicsCanvas(scroll_x, Cell(Int32(-coy)), Int32(0), Int32(0),
                            selector_cv, layout_none, true, Cell(nothing))),
        Cell(affine_identity),
        Cell(nothing))

    canvas = _make_canvas(0, 0, Any[
        selector_viewport,
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

function read_intent(p::WidgetTabbedPaneToGraphicsCanvas, iomap::ChildrenIoMap, evt)
    child_iomaps = iomap.child_iomaps[]::Vector
    if evt isa MousePress
        w = iomap.input
        if !(w isa WidgetTabbedPane)
            res = _route_active_tab(iomap, child_iomaps, evt)
            return _tab_prefix(res)
        end
        cox, coy, sel_pad, sel_h, strip_w, tabs = _tab_strip_geometry(p, w)
        if !isempty(tabs) && evt.y >= coy && evt.y < coy + sel_h
            view_w = _tab_view_w(iomap, strip_w)
            # A click in the (clipped) strip maps to a tab through the scroll offset:
            # the tab drawn at screen x sits at strip coordinate `x + scroll`.
            if evt.x >= cox && evt.x < cox + view_w
                xx = evt.x + _tab_scroll_offset(w, strip_w, view_w)
                for (i, t) in enumerate(tabs)
                    tx, rw = t[5], t[6]
                    xx >= tx && xx < tx + rw && return SelectTabOperation(w, i)
                end
            end
        end
        return _tab_prefix(_route_active_tab(iomap, child_iomaps, evt))
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
                    return ReplaceReferencedValueOperation(w, "tab_scroll", new_s)
                end
            end
        end
        return _tab_prefix(_route_active_tab(iomap, child_iomaps, evt))
    end
    # Coordinate-bearing events (drags + hover crossings) target the *visible* tab
    # regardless of selection: a splitter drag inside the active tab must keep
    # receiving motion even when the pane carries no selection (the bootstrap case
    # the SplitPaneDrag tests cover), and a hover crossing must reach whatever the
    # pointer is over — routing to the *selected* tab (as coordless events do) left
    # a hovered widget inside a tab unlit. `_route_active_tab` translates coords into
    # the tab's frame (hit-gating the crossings so the tab strip is excluded).
    if evt isa MouseDown || evt isa MouseUp || evt isa MouseMove ||
       evt isa MouseEnter || evt isa MouseLeave
        return _tab_prefix(_route_active_tab(iomap, child_iomaps, evt))
    end
    # Coordless events (KeyDown, KeyPress, …): forward to the tab the selection
    # points at, or to nothing when the selection is not in this pane — selection
    # is authoritative, with no active-tab fallback for keyboard events (the
    # printer still falls back to tab 1 to *render* a tab). See widget.md.
    _tab_prefix(_route_selected_tab(iomap, child_iomaps, evt))
end

# Coordless routing: forward to the tab the selection points at, or nothing when
# the selection is not in this pane. Unlike `_route_active_tab` there is NO
# fallback to a default/visible tab — selection is authoritative for keyboard
# events. Coordless events need no coordinate translation, so `evt` is forwarded
# as-is. Returns (op, idx) with the 1-based tab number for `_tab_prefix`.
function _route_selected_tab(iomap::ChildrenIoMap, child_iomaps::Vector, evt)
    w = iomap.input
    w isa WidgetTabbedPane || return nothing
    idx = _tab_index_from_selection(getfield(w, :selection)[], length(child_iomaps))
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
    # forwarding. `MousePress`/`MouseScroll` also hit-test (a click/scroll
    # outside the content is dropped). The drag events `MouseDown`/`MouseUp`/
    # `MouseMove` are translated too but not hit-gated — a splitter drag inside
    # the active tab must keep receiving motion even when the cursor strays off
    # the content, and the translation is what lets the tab's own splitter band
    # line up with where it is drawn (otherwise the grab region is offset by the
    # tab strip's height). Coordless events (KeyDown, KeyPress, …) pass through.
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
        MouseDown(button, x, y) =>
            MouseDown(button, x - ox - Int(canvas.x), y - oy - Int(canvas.y), evt.modifiers)
        MouseUp(button, x, y) =>
            MouseUp(button, x - ox - Int(canvas.x), y - oy - Int(canvas.y), evt.modifiers)
        MouseMove(x, y) =>
            MouseMove(x - ox - Int(canvas.x), y - oy - Int(canvas.y), evt.buttons, evt.modifiers)
        # Hover crossings hit-test like a click (a MouseEnter over the tab strip,
        # not the content, must not fall into the active tab); MouseLeave clears the
        # child's hover so it is translated but forwarded even off-content.
        MouseEnter(x, y) => begin
            lx, ly = x - ox - Int(canvas.x), y - oy - Int(canvas.y)
            hit_element_at(canvas, lx, ly) === nothing && return nothing
            MouseEnter(lx, ly, evt.buttons, evt.modifiers)
        end
        MouseLeave(x, y) =>
            MouseLeave(x - ox - Int(canvas.x), y - oy - Int(canvas.y), evt.buttons, evt.modifiers)
        _ => evt
    end
    op = read_intent(cim.projection, cim, child_evt)
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
    reroot_operation(op,
        (FieldReference("selector_element_pairs"), RangeReference(idx-1, idx)))
end

# ── WidgetScrollPane ────────────────────────────────────────────────────────

function print_document(p::WidgetScrollPaneToGraphicsCanvas, recursion, w::WidgetScrollPane, ctx)
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
              Cell(Int32(sz isa Point2D ? Int(sz.x[]) : _SCROLL_FALLBACK_WIDTH))
    vh_cell = avail_h !== nothing ?
              Cell(() -> Int32(max(0, Int(avail_h[]) - ty))) :
              Cell(Int32(sz isa Point2D ? Int(sz.y[]) : _SCROLL_FALLBACK_HEIGHT))
    cox, coy = _content_offset(w)
    scroll_cell = getfield(w, :scroll_position)
    follow_cell = getfield(w, :follow_end)
    inner_x = Cell(() -> begin sp = scroll_cell[]::Point2D; Int32(-Int(sp.x[])) end)
    elems = Any[]
    cfc = w.content_fill_color
    bgc = cfc isa StyleColor ? cfc : p.background_color
    # Cell-backed rect so it tracks the viewport extent.
    push!(elems, GraphicsRect(Cell(Int32(cox)), Cell(Int32(coy)), vw_cell, vh_cell,
                              Cell(bgc),
                              Cell(Int32(0)), Cell(Int32(0)), Cell(Int32(0)), Cell(Int32(0)),
                              Cell(Int32(0)),
                              Cell(StyleColor(0.0, 0.0, 0.0, 0.0)),
                              Cell(nothing)))
    # Recurse into the content with the viewport extent on each axis — the
    # context cells are already deferred, so the recursion stays lazy.
    content_iomap = nothing
    content = w.content
    if content isa Document
        content_ctx = with_available_size(ctx; width=vw_cell, height=vh_cell)
        content_iomap = print_child(recursion, content, content_ctx)
        inner_canvas = content_iomap.output::GraphicsCanvas
        inner_elems_cv = inner_canvas.elements
        # Vertical offset of the content inside the viewport. Normally this is the
        # negated `scroll_position.y`; with `follow_end` the pane sticks to the
        # bottom of its content — offset by `viewport - content` (≤ 0), so newly
        # appended content (a streaming chat) stays in view as the content grows.
        content_h_cell = inner_canvas.h
        inner_y = Cell(() -> begin
            if follow_cell[]
                Int32(-max(0, Int(content_h_cell[]) - Int(vh_cell[])))
            else
                sp = scroll_cell[]::Point2D
                Int32(-Int(sp.y[]))
            end
        end)
        push!(elems, GraphicsViewport(Cell(Int32(cox)), Cell(Int32(coy)),
                                      vw_cell, vh_cell,
                                      Cell(GraphicsCanvas(inner_x, inner_y, Int32(0), Int32(0),
                                                          inner_elems_cv isa CellVector ? inner_elems_cv : CellVector(Cell[Cell(inner_canvas)]),
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
    outer_w = Cell(() -> Int32(Int(vw_cell[]) + tx))
    outer_h = Cell(() -> Int32(Int(vh_cell[]) + ty))
    outer = GraphicsCanvas(Cell(Int32(px)), Cell(Int32(py)), outer_w, outer_h,
                           CellVector(Cell[Cell(e) for e in elems]),
                           layout_none, true, Cell(nothing))
    WidgetScrollPaneToGraphicsCanvasIoMap(p, w, outer, content_iomap)
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

# A scroll-wheel turn advances `scroll_position` by a delta. Expressed as a write
# of the new (old+delta) value — the old value is read from the pane at read time,
# which equals its value at evaluate time (no intervening mutation in the loop).
_scroll_by(sp, dx, dy) = let old = sp.scroll_position
    ReplaceReferencedValueOperation(sp, "scroll_position", Point2D(old.x[] + dx, old.y[] + dy))
end

function read_intent(p::WidgetScrollPaneToGraphicsCanvas, iomap::WidgetScrollPaneToGraphicsCanvasIoMap, evt)
    canvas = iomap.output
    @event_case evt begin
        MouseScroll(dx, dy, x, y) => begin
            # evt coords are already relative to canvas origin (parent routing subtracted position)
            hit_element_at(canvas, x, y) === nothing && return nothing
            _, scroll_step = p.measure("M", p.font)
            return dx != 0 && dy == 0 ?
                _scroll_by(iomap.input, -dx * scroll_step, 0) :
                _scroll_by(iomap.input, 0, -dy * scroll_step)
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
            read_intent(content_iomap.projection, content_iomap,
                             MousePress(button, lx, ly, evt.modifiers))
        end
        _ => read_intent(content_iomap.projection, content_iomap, evt)
    end
    _retarget_op(p, iomap, op)
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
    tx, ty = _inset_total(w)
    avail_w = ctx.available_width
    avail_h = ctx.available_height
    vw_cell = avail_w !== nothing ?
              Cell(() -> Int32(max(0, Int(avail_w[]) - tx))) :
              Cell(Int32(sz isa Point2D ? Int(sz.x[]) : _SCROLL_FALLBACK_WIDTH))
    vh_cell = avail_h !== nothing ?
              Cell(() -> Int32(max(0, Int(avail_h[]) - ty))) :
              Cell(Int32(sz isa Point2D ? Int(sz.y[]) : _SCROLL_FALLBACK_HEIGHT))
    cox, coy = _content_offset(w)
    # The pane's affine transform, read through a Cell so a zoom/pan re-zooms
    # the viewport reactively.
    transform_cell = Cell(() -> getfield(w, :transform)[]::AffineTransform)
    elems = Any[]
    cfc = w.content_fill_color
    bgc = cfc isa StyleColor ? cfc : p.background_color
    push!(elems, GraphicsRect(Cell(Int32(cox)), Cell(Int32(coy)), vw_cell, vh_cell,
                              Cell(bgc),
                              Cell(Int32(0)), Cell(Int32(0)), Cell(Int32(0)), Cell(Int32(0)),
                              Cell(Int32(0)),
                              Cell(StyleColor(0.0, 0.0, 0.0, 0.0)),
                              Cell(nothing)))
    # Recurse into the content at the viewport's (unscaled) logical extent — the
    # content lays out at 1× and the viewport's transform magnifies it.
    content_iomap = nothing
    content = w.content
    if content isa Document
        content_ctx = with_available_size(ctx; width=vw_cell, height=vh_cell)
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
    outer_w = Cell(() -> Int32(Int(vw_cell[]) + tx))
    outer_h = Cell(() -> Int32(Int(vh_cell[]) + ty))
    outer = GraphicsCanvas(Cell(Int32(px)), Cell(Int32(py)), outer_w, outer_h,
                           CellVector(Cell[Cell(e) for e in elems]),
                           layout_none, true, Cell(nothing))
    WidgetTransformPaneToGraphicsCanvasIoMap(p, w, outer, content_iomap)
end

function map_reference_forward(::WidgetTransformPaneToGraphicsCanvas, iomap, reference)
    return nothing
end

# Like the scroll pane: prepend `.content` to re-root a bubbled path in the
# transform pane's own input domain.
function map_reference_backward(::WidgetTransformPaneToGraphicsCanvas, iomap::WidgetTransformPaneToGraphicsCanvasIoMap, reference)
    reference === nothing && return nothing
    ConcreteReferencePath(FieldReference("content"), reference)
end

# Zoom about a viewport-space point: scale by `factor` keeping `(ax, ay)` fixed,
# composed onto the existing matrix. `M' = T(a) ∘ S(f) ∘ T(-a) ∘ M`.
_zoom_about(M::AffineTransform, factor, ax, ay) =
    affine_translate(ax, ay) ∘ affine_scale(factor, factor) ∘ affine_translate(-ax, -ay) ∘ M

# Pan: prepend a screen-space translation. `M' = T(dx, dy) ∘ M`.
_pan_by(M::AffineTransform, dx, dy) = affine_translate(dx, dy) ∘ M

# One zoom step about `(ax, ay)`: `dir > 0` zooms in, `dir < 0` out. Returns the
# `ReplaceReferencedValueOperation`, or `nothing` if the clamp leaves the scale unchanged
# (already at `_ZOOM_MIN`/`_ZOOM_MAX`). Shared by the wheel and keyboard readers.
function _zoom_op(w, M::AffineTransform, dir, ax, ay)
    cur = M.a == 0.0 ? 1.0 : M.a
    f = dir > 0 ? _ZOOM_STEP : 1.0 / _ZOOM_STEP
    new_scale = clamp(cur * f, _ZOOM_MIN, _ZOOM_MAX)
    f = new_scale / cur
    f == 1.0 && return nothing
    ReplaceReferencedValueOperation(w, "transform", _zoom_about(M, f, ax, ay))
end

function read_intent(p::WidgetTransformPaneToGraphicsCanvas, iomap::WidgetTransformPaneToGraphicsCanvasIoMap, evt)
    canvas = iomap.output
    w = iomap.input
    M = getfield(w, :transform)[]::AffineTransform
    cox, coy = _content_offset(w)
    # MouseScroll is consumed here (zoom or pan); each matched branch `return`s.
    @event_case evt begin
        # Ctrl+wheel: zoom about the cursor.
        MouseScroll(dx, dy, x, y; ctrl) => begin
            hit_element_at(canvas, x, y) === nothing && return nothing
            return _zoom_op(w, M, dy >= 0 ? 1 : -1, Float64(x - cox), Float64(y - coy))
        end
        # Plain wheel: pan. Vertical by `dy`, horizontal by `dx`, step = line height.
        MouseScroll(dx, dy, x, y) => begin
            hit_element_at(canvas, x, y) === nothing && return nothing
            _, step = p.measure("M", p.font)
            return dx != 0 && dy == 0 ?
                ReplaceReferencedValueOperation(w, "transform", _pan_by(M, dx * step, 0)) :
                ReplaceReferencedValueOperation(w, "transform", _pan_by(M, 0, dy * step))
        end
    end
    # Forward other events to the content, mapping pointer coords through the
    # inverse transform (screen → content-local), then re-root the result.
    content_iomap = iomap.content_iomap
    op = content_iomap === nothing ? nothing : @event_case evt begin
        MousePress(button, x, y) => begin
            inv = affine_inverse(M)
            lxf, lyf = affine_apply(inv, Float64(x - cox), Float64(y - coy))
            read_intent(content_iomap.projection, content_iomap,
                             MousePress(button, round(Int, lxf), round(Int, lyf), evt.modifiers))
        end
        _ => read_intent(content_iomap.projection, content_iomap, evt)
    end
    op = _retarget_op(p, iomap, op)
    op === nothing || return op
    # Keyboard zoom — a *fallback* only when the content did not consume the key,
    # so a Ctrl+= / Ctrl+- bound inside the content (e.g. collection add/remove)
    # still wins. Ctrl+= / keypad-+ zooms in, Ctrl+- / keypad-- out, Ctrl+0
    # resets — all about the viewport centre (no cursor for keyboard).
    tx, ty = _inset_total(w)
    cw = Int(canvas.w); ch = Int(canvas.h)
    acx, acy = (cw - tx) / 2.0, (ch - ty) / 2.0
    @event_case evt begin
        KeyDown(:equals; ctrl) => return _zoom_op(w, M, 1, acx, acy)
        KeyDown(:minus; ctrl)  => return _zoom_op(w, M, -1, acx, acy)
        KeyDown(:zero; ctrl)   => return M === affine_identity ? nothing :
                                         ReplaceReferencedValueOperation(w, "transform", affine_identity)
    end
    nothing
end

# ── WidgetToolbar ───────────────────────────────────────────────────────────

function print_document(p::WidgetToolbarToGraphicsCanvas, recursion, w::WidgetToolbar, ctx)
    w.visible == false && return ChildrenIoMap(p, w, _empty_canvas(), Cell(Any[]))
    cox, coy = _content_offset(w)
    child_iomaps = Any[]
    elems = Any[]
    x_cursor = cox
    item_gap = p.item_gap
    for item in w.elements
        item isa WidgetDocument || continue
        cim = print_child(recursion, item, ctx)
        push!(child_iomaps, (x_cursor, coy, cim))
        push!(elems, _make_canvas(x_cursor, coy, Any[cim.output]))
        # Advance by the item's *rendered* width (includes a leading icon, Stage 5),
        # not just its text — otherwise an icon'd item overlaps the next one.
        iw = _menu_item_width(cim)
        iw <= 0 && ((iw, _) = p.measure("    ", p.font))
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

function read_intent(::WidgetToolbarToGraphicsCanvas, iomap::ChildrenIoMap, evt)
    entries = iomap.child_iomaps[]::Vector
    evt isa MousePress && return _route_click_to_children(entries, evt)
    (evt isa MouseEnter || evt isa MouseLeave) && return _route_crossing_to_children(entries, evt)
    evt isa MouseScroll || return nothing
    _route_scroll_to_children(entries, evt)
end

# ── WidgetStatusBar (Stage 4) ─────────────────────────────────────────────────
# A non-interactive bottom band: stringified `segments` laid left-to-right on a
# muted surface, filling the available width when a parent seeded one.

@projection struct WidgetStatusBarToGraphicsCanvas
    measure::Function
    text::ImmutableCell{DStyleText}
    background_color::StyleColor
    gap::Int
end

function print_document(p::WidgetStatusBarToGraphicsCanvas, recursion, w::WidgetStatusBar, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    cox, coy = _content_offset(w)
    gap = _sc(p.gap)
    labels = Any[]
    x = cox; text_h = 0
    for seg in w.elements
        s = string(seg)
        tw, th = _text_size(p.measure, p.text.font, s)
        _push_text!(labels, p.text.font, s, x, coy, p.text.color)
        x += tw + gap; text_h = max(text_h, th)
    end
    width  = _resolve_width(ctx, x, x)
    height = text_h + 2coy
    elements = Any[]
    _push_panel!(elements, 0, 0, width, height; fill=p.background_color)
    append!(elements, labels)
    SimpleIoMap(p, w, _make_canvas(0, 0, width, height, elements))
end

map_reference_forward(::WidgetStatusBarToGraphicsCanvas, iomap, reference) = nothing
map_reference_backward(::WidgetStatusBarToGraphicsCanvas, iomap, reference) = nothing
read_intent(::WidgetStatusBarToGraphicsCanvas, iomap::SimpleIoMap, evt) = nothing

# ── WidgetScrollBar ─────────────────────────────────────────────────────────

function print_document(p::WidgetScrollBarToGraphicsCanvas, _, w::WidgetScrollBar, _)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    pos = w.position
    sz  = w.size
    px = pos isa Point2D ? _sc(Int(pos.x[])) : 0
    py = pos isa Point2D ? _sc(Int(pos.y[])) : 0
    bw = sz  isa Point2D ? Int(sz.x[])  : _SCROLLBAR_FALLBACK_LENGTH
    bh = sz  isa Point2D ? Int(sz.y[])  : _SCROLLBAR_FALLBACK_THICKNESS
    cox, coy = _content_offset(w)
    tx, ty = _inset_total(w)
    cw = max(1, bw - tx)
    ch = max(1, bh - ty)
    elems = Any[]
    trad = min(cw, ch) ÷ 2
    push!(elems, GraphicsRect(cox, coy, cw, ch, p.track_color, trad))
    value    = clamp(Float64(w.value),     0.0, 1.0)
    thumb_sz = clamp(Float64(w.thumb_size), 0.05, 1.0)
    if w.orientation === :horizontal
        tw = max(p.minimum_thumb_length, Int(round(thumb_sz * cw)))
        tx_pos = cox + Int(round(value * (cw - tw)))
        push!(elems, GraphicsRect(tx_pos, coy, tw, ch, p.thumb_color, ch ÷ 2))
    else
        th = max(p.minimum_thumb_length, Int(round(thumb_sz * ch)))
        ty_pos = coy + Int(round(value * (ch - th)))
        push!(elems, GraphicsRect(cox, ty_pos, cw, th, p.thumb_color, cw ÷ 2))
    end
    SimpleIoMap(p, w, _make_canvas(px, py, elems))
end

function map_reference_forward(::WidgetScrollBarToGraphicsCanvas, iomap, reference)
    return nothing
end

function map_reference_backward(::WidgetScrollBarToGraphicsCanvas, iomap, reference)
    return nothing
end

function read_intent(p::WidgetScrollBarToGraphicsCanvas, iomap::SimpleIoMap, evt)
    evt isa MousePress || return nothing
    w = iomap.input
    w isa WidgetScrollBar || return nothing
    sz  = w.size
    bw = sz isa Point2D ? Int(sz.x[]) : _SCROLLBAR_FALLBACK_LENGTH
    bh = sz isa Point2D ? Int(sz.y[]) : _SCROLLBAR_FALLBACK_THICKNESS
    cox, coy = _content_offset(w)
    tx, ty = _inset_total(w)
    cw = max(1, bw - tx)
    ch = max(1, bh - ty)
    thumb_sz = clamp(Float64(w.thumb_size), 0.05, 1.0)
    if w.orientation === :horizontal
        tw = max(p.minimum_thumb_length, Int(round(thumb_sz * cw)))
        new_value = clamp(Float64(evt.x - cox - div(tw, 2)) / max(1, cw - tw), 0.0, 1.0)
    else
        th = max(p.minimum_thumb_length, Int(round(thumb_sz * ch)))
        new_value = clamp(Float64(evt.y - coy - div(th, 2)) / max(1, ch - th), 0.0, 1.0)
    end
    # new_value is already clamped to [0,1] above.
    ReplaceReferencedValueOperation(w, "value", new_value)
end

# ════════════════════════════════════════════════════════════════════════════
# Extension widgets — printer-only (no-op readers)
# ════════════════════════════════════════════════════════════════════════════

# A no-op reader trio shared by every extension widget (printer-only for now).
macro _printer_only(P)
    quote
        map_reference_forward(::$(esc(P)), iomap, reference) = nothing
        map_reference_backward(::$(esc(P)), iomap, reference) = nothing
        read_intent(::$(esc(P)), iomap, evt) = nothing
    end
end

# ── WidgetBadge ─────────────────────────────────────────────────────────────

@projection struct WidgetBadgeToGraphicsCanvas
    measure::Function
    font::StyleFont                # small pill font
    padding::Inset
    border_width::Int              # outline width (outline variant only)
    default_fill::StyleColor
    default_foreground::StyleColor
    secondary_fill::StyleColor
    secondary_foreground::StyleColor
    destructive_fill::StyleColor
    destructive_foreground::StyleColor
    outline_fill::StyleColor
    outline_foreground::StyleColor
    outline_border::StyleColor
end

function print_document(p::WidgetBadgeToGraphicsCanvas, recursion, w::WidgetBadge, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    position = w.position::Point2D
    text = string(w.content)
    fill, foreground, border = if w.variant === :secondary
        (p.secondary_fill, p.secondary_foreground, nothing)
    elseif w.variant === :destructive
        (p.destructive_fill, p.destructive_foreground, nothing)
    elseif w.variant === :outline
        (p.outline_fill, p.outline_foreground, p.outline_border)
    else
        (p.default_fill, p.default_foreground, nothing)
    end
    padding_x = _sc(Int(p.padding.left[]))
    padding_y = _sc(Int(p.padding.top[]))
    text_width, text_height = _text_size(p.measure, p.font, text)
    badge_width  = text_width + 2padding_x
    badge_height = text_height + 2padding_y
    border_width = border !== nothing ? max(1, _sc(p.border_width)) : 0
    elements = Any[]
    _push_panel!(elements, 0, 0, badge_width, badge_height; fill=fill, border=border, border_w=border_width, radius=badge_height ÷ 2)
    push!(elements, GraphicsText(text, padding_x, (badge_height - text_height) ÷ 2, p.font, foreground))
    SimpleIoMap(p, w, _make_canvas(_origin(position)..., badge_width, badge_height, elements))
end
@_printer_only WidgetBadgeToGraphicsCanvas

# ── WidgetSeparator ─────────────────────────────────────────────────────────

@projection struct WidgetSeparatorToGraphicsCanvas
    stroke::StyleStroke    # color + width of the rule
end

function print_document(p::WidgetSeparatorToGraphicsCanvas, recursion, w::WidgetSeparator, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    position = w.position::Point2D
    rule_length = _sc(Int(w.length))
    thickness = max(1, _sc(p.stroke.width))
    elements = Any[]
    if w.orientation === :vertical
        push!(elements, GraphicsLine(0, 0, 0, rule_length, p.stroke.color; width=thickness))
        SimpleIoMap(p, w, _make_canvas(_origin(position)..., thickness, rule_length, elements))
    else
        push!(elements, GraphicsLine(0, 0, rule_length, 0, p.stroke.color; width=thickness))
        SimpleIoMap(p, w, _make_canvas(_origin(position)..., rule_length, thickness, elements))
    end
end
@_printer_only WidgetSeparatorToGraphicsCanvas

# ── WidgetCard ──────────────────────────────────────────────────────────────

@projection struct WidgetCardToGraphicsCanvas
    measure::Function
    title_text::ImmutableCell{DStyleText}
    description_text::ImmutableCell{DStyleText}
    content_text::ImmutableCell{DStyleText}
    footer_text::ImmutableCell{DStyleText}
    surface_color::StyleColor      # card fill
    border::StyleStroke
    corner_radius::Int
    padding::Int                   # uniform card padding
    title_gap::Int
    section_gap::Int
end

# Lay out the card body: stack title/description/content/footer top-to-bottom,
# size the card to them, and draw the surface panel behind. Reads the recursed
# title/content iomaps' reactive sizes (`inner.h[]`/`inner.w[]`), so the enclosing
# `build` cell re-runs when the content grows — that is what keeps the card's
# border, height, and child positions in step with reactive content.
function _card_build(p, w, ctx, tim, cim)
    padding = _sc(p.padding)
    elements = Any[]
    child_iomaps = Any[]
    max_content_width = 0   # widest content row, to size the card to its content
    y = padding
    if tim !== nothing
        push!(child_iomaps, (padding, y, tim))
        push!(elements, _make_canvas(padding, y, Any[tim.output]))
        inner = tim.output
        if inner isa GraphicsCanvas
            max_content_width = max(max_content_width, Int(inner.w[]))
            y += Int(inner.h[]) + _sc(p.title_gap)
        else
            y += _sc(p.title_gap)
        end
    elseif w.title !== nothing
        title = string(w.title)
        title_width, title_height = _text_size(p.measure, p.title_text.font, title)
        _push_text!(elements, p.title_text.font, title, padding, y, p.title_text.color)
        max_content_width = max(max_content_width, title_width); y += title_height + _sc(p.title_gap)
    end
    if w.description !== nothing
        description = string(w.description)
        description_width, description_height = _text_size(p.measure, p.description_text.font, description)
        _push_text!(elements, p.description_text.font, description, padding, y, p.description_text.color)
        max_content_width = max(max_content_width, description_width); y += description_height + _sc(p.section_gap)
    end
    content = w.content
    if cim !== nothing
        push!(child_iomaps, (padding, y, cim))
        push!(elements, _make_canvas(padding, y, Any[cim.output]))
        inner = cim.output
        inner isa GraphicsCanvas && (max_content_width = max(max_content_width, Int(inner.w[])))
        y += inner isa GraphicsCanvas ? Int(inner.h[]) + _sc(p.section_gap) : _sc(p.section_gap)
    elseif content isa AbstractString
        content_width, content_height = _text_size(p.measure, p.content_text.font, content)
        _push_text!(elements, p.content_text.font, content, padding, y, p.content_text.color)
        max_content_width = max(max_content_width, content_width); y += content_height + _sc(p.section_gap)
    end
    if w.footer !== nothing
        footer = string(w.footer)
        footer_width, footer_height = _text_size(p.measure, p.footer_text.font, footer)
        _push_text!(elements, p.footer_text.font, footer, padding, y, p.footer_text.color)
        max_content_width = max(max_content_width, footer_width); y += footer_height
    end
    card_width = _resolve_width(ctx, _sc(Int(w.width)), max_content_width + 2padding)
    card_height = y + padding
    # Card surface drawn first (behind content).
    surface = Any[]
    _push_panel!(surface, 0, 0, card_width, card_height; fill=p.surface_color, border=p.border.color,
                 border_w=max(1, _sc(p.border.width)), radius=_sc(p.corner_radius))
    append!(surface, elements)
    (w = card_width, h = card_height, elements = surface, child_iomaps = child_iomaps)
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
    pad = _sc(p.padding)
    avail_w = ctx.available_width
    inner_w = avail_w === nothing ? nothing :
              Cell(() -> Int32(max(0, Int(avail_w[]) - 2pad)))
    inner_ctx = with_available_size(ctx; width=inner_w, height=nothing)
    tim = w.title isa Document ? print_child(recursion, w.title, inner_ctx) : nothing
    cim = w.content isa Document ? print_child(recursion, w.content, inner_ctx) : nothing
    build = Cell(() -> _card_build(p, w, ctx, tim, cim))
    outer = GraphicsCanvas(Cell(Int32(ox)), Cell(Int32(oy)),
                           Cell(() -> Int32(build[].w)),
                           Cell(() -> Int32(build[].h)),
                           CellVector(() -> build[].elements),
                           layout_none, true, Cell(nothing))
    ChildrenIoMap(p, w, outer, Cell(() -> build[].child_iomaps))
end

# A click on the card's header (a Document title — its first child entry) is a
# fold gesture → toggle the card. Clicks elsewhere route into the card content.
function read_intent(p::WidgetCardToGraphicsCanvas, iomap::ChildrenIoMap, evt::MousePress)
    w = iomap.input
    entries = iomap.child_iomaps[]
    if w.title isa Document && !isempty(entries)
        tx, ty, tim = entries[1]
        tcanvas = tim.output
        if tcanvas isa GraphicsCanvas
            tw = Int(tcanvas.w[]); th = Int(tcanvas.h[])
            (tx <= evt.x < tx + tw && ty <= evt.y < ty + th) && return ToggleCollapseOperation(w)
        end
    end
    _route_click_to_children(entries, evt)
end
read_intent(::WidgetCardToGraphicsCanvas, iomap::ChildrenIoMap, evt) = nothing
map_reference_forward(::WidgetCardToGraphicsCanvas, iomap, reference) = nothing
map_reference_backward(::WidgetCardToGraphicsCanvas, iomap, reference) = nothing

# ── WidgetSwitch ────────────────────────────────────────────────────────────

@projection struct WidgetSwitchToGraphicsCanvas
    track_size::Point2D        # width × height of the track
    knob_padding::Int          # inset of the knob from the track edge
    knob_color::StyleColor     # knob fill
    knob_border::StyleStroke   # knob outline (color + width)
    on_color::StyleColor       # track fill when checked
    off_color::StyleColor      # track fill when unchecked
    disabled_color::StyleColor # track fill when !enabled
    ring_color::StyleColor     # focus ring when selected
end

# Smoothstep easing on a normalised [0,1] progress.
_switch_ease(u::Real) = (u = clamp(u, 0.0, 1.0); u * u * (3 - 2u))

# The knob fraction (0 = off/left, 1 = on/right) the switch is *currently*
# displaying at time `now`. Untracked — used by the reader to capture `anim_from`.
# Mid-slide it returns the in-flight eased fraction (so interrupting a slide
# resumes from where the knob visually is, with no jump).
function _switch_fraction(w::WidgetSwitch, now::Float64)
    target = (w.checked === true) ? 1.0 : 0.0
    dur = w.duration
    t0  = w.anim_t0
    (dur <= 0 || isnan(t0)) && return target
    t1 = t0 + dur / 1000
    now >= t1 && return target
    from = w.anim_from
    from + (target - from) * _switch_ease((now - t0) / (t1 - t0))
end

function print_document(p::WidgetSwitchToGraphicsCanvas, recursion, w::WidgetSwitch, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    position = w.position::Point2D
    on  = w.checked === true
    enabled = !(w.enabled === false)
    track_width  = _sc(Int(p.track_size.x[]))
    track_height = _sc(Int(p.track_size.y[]))
    elements = Any[]
    track_color = !enabled ? p.disabled_color : on ? p.on_color : p.off_color
    push!(elements, GraphicsRect(0, 0, track_width, track_height, track_color, track_height ÷ 2))
    knob_padding = _sc(p.knob_padding)
    knob_radius  = (track_height - 2knob_padding) ÷ 2
    left_x  = knob_padding + knob_radius
    right_x = track_width - knob_padding - knob_radius
    knob = GraphicsCircle(on ? right_x : left_x, track_height ÷ 2, knob_radius, p.knob_color;
                          border_width=max(1, _sc(p.knob_border.width)), border_color=p.knob_border.color)
    # The knob's x is a computed cell. It reads `checked` (so it tracks the
    # logical state and snaps when there is no animation) and, while a slide is
    # in flight, `get_reactive_time(get_wall_clock())` (so it re-evaluates every
    # frame). Once the slide is over it only *samples* the time
    # (`get_time(get_wall_clock())`), drops the time subscription, and holds
    # the final position — settling with no registry. The wall clock is used
    # on both sides because the reader (below) sees no `PrinterContext` and
    # so can't reach the enclosing editor's private clock; a follow-up seam
    # would let a reader receive a per-editor clock too.
    clock = get_wall_clock()
    set_cell_function!(getfield(knob, :cx), () -> begin
        target_x = (w.checked === true) ? right_x : left_x
        dur = w.duration
        t0  = w.anim_t0
        (dur <= 0 || isnan(t0)) && return Int32(target_x)
        t1 = t0 + dur / 1000
        now = get_time(clock)                     # SAMPLE: decide done, no subscription
        now >= t1 && return Int32(target_x)       # settled → stops animating
        from_x = left_x + (right_x - left_x) * w.anim_from
        t = get_reactive_time(clock)              # SUBSCRIBE while sliding
        Int32(round(from_x + (target_x - from_x) * _switch_ease((t - t0) / (t1 - t0))))
    end)
    push!(elements, knob)
    _push_focus_ring!(elements, w, track_width, track_height, p.ring_color, track_height ÷ 2)
    SimpleIoMap(p, w, _make_canvas(_origin(position)..., track_width, track_height, elements))
end

# A click (or Return/Space on the focused switch) toggles `checked`. When the
# widget has a non-zero `duration`, the toggle is bundled into a
# `CompoundOperation` that first arms the slide — recording the knob fraction the
# switch is currently showing (`anim_from`) and the start time (`anim_t0`),
# sampled now — and then flips `checked`. The printer's knob-cx cell reads those
# fields, so the next frames animate. `anim_from`/`anim_t0` are written via
# ordinary `ReplaceReferencedValueOperation`s on the carried widget; no new operation type
# is needed because the time and current position are sampled here, in the reader.
function _switch_toggle(w::WidgetSwitch)
    new_checked = !(w.checked === true)
    toggle = ReplaceReferencedValueOperation(w,
        ConcreteReferencePath(FieldReference("checked"), EmptyReferencePath()), new_checked)
    w.duration <= 0 && return toggle
    now  = get_time(get_wall_clock())
    from = _switch_fraction(w, now)
    CompoundOperation(Any[
        ReplaceReferencedValueOperation(w, ConcreteReferencePath(FieldReference("anim_from"), EmptyReferencePath()), from),
        ReplaceReferencedValueOperation(w, ConcreteReferencePath(FieldReference("anim_t0"),   EmptyReferencePath()), now),
        toggle,
    ])
end

function read_intent(::WidgetSwitchToGraphicsCanvas, iomap::SimpleIoMap, evt::MousePress)
    w = iomap.input
    w.enabled === false && return nothing   # a disabled switch swallows the click
    op = read_bound_gesture(w, evt); op === nothing || return op   # per-instance gestures win
    _switch_toggle(w)
end

function read_intent(::WidgetSwitchToGraphicsCanvas, iomap::SimpleIoMap, evt)
    w = iomap.input
    w.enabled === false && return nothing
    op = read_bound_gesture(w, evt); op === nothing || return op   # per-instance gestures win
    (evt isa KeyDown && (evt.key === :return || evt.key === :space)) || return nothing
    _switch_toggle(w)
end

map_reference_forward(::WidgetSwitchToGraphicsCanvas, iomap, reference) = nothing
map_reference_backward(::WidgetSwitchToGraphicsCanvas, iomap, reference) = nothing

# ── WidgetProgress ──────────────────────────────────────────────────────────

@projection struct WidgetProgressToGraphicsCanvas
    bar_height::Int
    track_color::StyleColor    # unfilled track
    fill_color::StyleColor     # filled portion
end

function print_document(p::WidgetProgressToGraphicsCanvas, recursion, w::WidgetProgress, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    position = w.position::Point2D
    value = clamp(Float64(w.value), 0.0, 1.0)
    bar_width  = _resolve_width(ctx, _sc(Int(w.width)))
    bar_height = _sc(p.bar_height)
    elements = Any[]
    push!(elements, GraphicsRect(0, 0, bar_width, bar_height, p.track_color, bar_height ÷ 2))
    filled_width = round(Int, value * bar_width)
    if filled_width > 0
        push!(elements, GraphicsRect(0, 0, filled_width, bar_height, p.fill_color, bar_height ÷ 2))
    end
    SimpleIoMap(p, w, _make_canvas(_origin(position)..., bar_width, bar_height, elements))
end
@_printer_only WidgetProgressToGraphicsCanvas

# ── WidgetSlider ────────────────────────────────────────────────────────────

@projection struct WidgetSliderToGraphicsCanvas
    height::Int                 # control height
    track_thickness::Int
    knob_radius::Int
    knob_color::StyleColor      # knob fill
    knob_border::StyleStroke    # knob outline (color + width)
    track_color::StyleColor     # unfilled track
    fill_color::StyleColor      # filled portion
    disabled_color::StyleColor  # track / fill / knob when !enabled
    ring_color::StyleColor      # focus ring when selected
end

function print_document(p::WidgetSliderToGraphicsCanvas, recursion, w::WidgetSlider, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    position = w.position::Point2D
    enabled = !(w.enabled === false)
    value = clamp(Float64(w.value), 0.0, 1.0)
    slider_width  = _resolve_width(ctx, _sc(Int(w.width)))
    slider_height = _sc(p.height)
    center_y = slider_height ÷ 2
    track_thickness = _sc(p.track_thickness)
    filled_width = round(Int, value * slider_width)
    elements = Any[]
    track_c = enabled ? p.track_color : p.disabled_color
    fill_c  = enabled ? p.fill_color  : p.disabled_color
    knob_c  = enabled ? p.knob_color  : p.disabled_color
    push!(elements, GraphicsRect(0, center_y - track_thickness ÷ 2, slider_width, track_thickness, track_c, track_thickness ÷ 2))
    filled_width > 0 && push!(elements, GraphicsRect(0, center_y - track_thickness ÷ 2, filled_width, track_thickness, fill_c, track_thickness ÷ 2))
    push!(elements, GraphicsCircle(filled_width, center_y, _sc(p.knob_radius), knob_c;
                                   border_width=max(1, _sc(p.knob_border.width)), border_color=p.knob_border.color))
    _push_focus_ring!(elements, w, slider_width, slider_height, p.ring_color, slider_height ÷ 2)
    SimpleIoMap(p, w, _make_canvas(_origin(position)..., slider_width, slider_height, elements))
end
@_printer_only WidgetSliderToGraphicsCanvas

# ── WidgetRadioGroup ────────────────────────────────────────────────────────

@projection struct WidgetRadioGroupToGraphicsCanvas
    measure::Function
    label_text::ImmutableCell{DStyleText}          # option labels
    button_size::Int               # outer circle diameter
    label_gap::Int                 # gap between button and label
    row_gap::Int
    dot_radius::Int                # selected inner dot
    button_fill::StyleColor        # circle fill
    selected_ring::StyleStroke     # ring + inner-dot color when selected
    unselected_ring::StyleStroke   # ring when unselected
    selected_color::StyleColor     # inner dot fill
    disabled_foreground::StyleColor # rings / dot / labels when !enabled
    ring_color::StyleColor         # focus ring when selected
end

function print_document(p::WidgetRadioGroupToGraphicsCanvas, recursion, w::WidgetRadioGroup, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    position = w.position::Point2D
    enabled = !(w.enabled === false)
    selected = Int(w.selected)
    diameter = _sc(p.button_size)
    label_gap = _sc(p.label_gap)
    row_gap = _sc(p.row_gap)
    sel_ring   = enabled ? p.selected_ring.color   : p.disabled_foreground
    unsel_ring = enabled ? p.unselected_ring.color : p.disabled_foreground
    dot_color  = enabled ? p.selected_color        : p.disabled_foreground
    label_col  = enabled ? p.label_text.color      : p.disabled_foreground
    elements = Any[]
    y = 0
    max_width = 0
    for (i, opt) in enumerate(w.options)
        label = string(opt)
        label_width, label_height = _text_size(p.measure, p.label_text.font, label)
        row_height = max(diameter, label_height)
        center_y = y + row_height ÷ 2
        if i == selected
            push!(elements, GraphicsCircle(diameter ÷ 2, center_y, diameter ÷ 2, p.button_fill;
                                           border_width=max(1, _sc(p.selected_ring.width)), border_color=sel_ring))
            push!(elements, GraphicsCircle(diameter ÷ 2, center_y, _sc(p.dot_radius), dot_color))
        else
            push!(elements, GraphicsCircle(diameter ÷ 2, center_y, diameter ÷ 2, p.button_fill;
                                           border_width=max(1, _sc(p.unselected_ring.width)), border_color=unsel_ring))
        end
        _push_text!(elements, p.label_text.font, label, diameter + label_gap, y + (row_height - label_height) ÷ 2, label_col)
        max_width = max(max_width, diameter + label_gap + label_width)
        y += row_height + row_gap
    end
    _push_focus_ring!(elements, w, max_width, max(0, y - row_gap), p.ring_color, 0)
    SimpleIoMap(p, w, _make_canvas(_origin(position)..., max_width, max(0, y - row_gap), elements))
end
@_printer_only WidgetRadioGroupToGraphicsCanvas

# ── WidgetAvatar ────────────────────────────────────────────────────────────

@projection struct WidgetAvatarToGraphicsCanvas
    measure::Function
    initials::ImmutableCell{DStyleText}          # font + color of the initials
    background_color::StyleColor  # circle fill
end

function print_document(p::WidgetAvatarToGraphicsCanvas, recursion, w::WidgetAvatar, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    position = w.position::Point2D
    size = _sc(Int(w.size))
    radius = size ÷ 2
    initials = string(w.initials)
    elements = Any[]
    push!(elements, GraphicsCircle(radius, radius, radius, p.background_color))
    initials_width, initials_height = _text_size(p.measure, p.initials.font, initials)
    push!(elements, GraphicsText(initials, radius - initials_width ÷ 2, radius - initials_height ÷ 2, p.initials.font, p.initials.color))
    SimpleIoMap(p, w, _make_canvas(_origin(position)..., size, size, elements))
end
@_printer_only WidgetAvatarToGraphicsCanvas

# ── WidgetAlert ─────────────────────────────────────────────────────────────

@projection struct WidgetAlertToGraphicsCanvas
    measure::Function
    title_font::StyleFont
    description_text::ImmutableCell{DStyleText}        # muted description
    background_color::StyleColor
    padding::Int                       # uniform alert padding
    title_gap::Int                     # gap between title and description
    corner_radius::Int
    border_width::Int
    default_title_color::StyleColor
    default_border_color::StyleColor
    destructive_color::StyleColor      # title + border in the destructive variant
end

function print_document(p::WidgetAlertToGraphicsCanvas, recursion, w::WidgetAlert, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    position = w.position::Point2D
    destructive = w.variant === :destructive
    padding = _sc(p.padding)
    title_color  = destructive ? p.destructive_color : p.default_title_color
    border_color = destructive ? p.destructive_color : p.default_border_color
    elements = Any[]
    max_content_width = 0
    y = padding
    title = string(w.title)
    title_width, title_height = _text_size(p.measure, p.title_font, title)
    _push_text!(elements, p.title_font, title, padding, y, title_color)
    max_content_width = max(max_content_width, title_width); y += title_height
    if w.description !== nothing
        y += _sc(p.title_gap)
        description = string(w.description)
        description_width, description_height = _text_size(p.measure, p.description_text.font, description)
        _push_text!(elements, p.description_text.font, description, padding, y, p.description_text.color)
        max_content_width = max(max_content_width, description_width); y += description_height
    end
    alert_width = _resolve_width(ctx, _sc(Int(w.width)), max_content_width + 2padding)
    alert_height = y + padding
    surface = Any[]
    _push_panel!(surface, 0, 0, alert_width, alert_height; fill=p.background_color, border=border_color,
                 border_w=max(1, _sc(p.border_width)), radius=_sc(p.corner_radius))
    append!(surface, elements)
    SimpleIoMap(p, w, _make_canvas(_origin(position)..., alert_width, alert_height, surface))
end
@_printer_only WidgetAlertToGraphicsCanvas

# ── WidgetSkeleton ──────────────────────────────────────────────────────────

@projection struct WidgetSkeletonToGraphicsCanvas
    fill_color::StyleColor
    corner_radius::Int
end

function print_document(p::WidgetSkeletonToGraphicsCanvas, recursion, w::WidgetSkeleton, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    position = w.position::Point2D
    block_width  = _resolve_width(ctx, _sc(Int(w.width)))
    block_height = _sc(Int(w.height))
    elements = Any[GraphicsRect(0, 0, block_width, block_height, p.fill_color, _sc(p.corner_radius))]
    SimpleIoMap(p, w, _make_canvas(_origin(position)..., block_width, block_height, elements))
end
@_printer_only WidgetSkeletonToGraphicsCanvas

# Push a small chevron (two AA strokes) centered at (cx, cy). `dir` ∈ :down :right.
# `stroke` is the line width; callers pass the theme's icon stroke.
function _push_chevron!(elems::Vector, cx::Int, cy::Int, s::Int, dir::Symbol, color::StyleColor;
                        stroke::Int=max(1, _sc(2)))
    w = stroke
    if dir === :right
        push!(elems, GraphicsLine(cx - s ÷ 2, cy - s, cx + s ÷ 2, cy, color; width=w))
        push!(elems, GraphicsLine(cx + s ÷ 2, cy, cx - s ÷ 2, cy + s, color; width=w))
    else
        push!(elems, GraphicsLine(cx - s, cy - s ÷ 2, cx, cy + s ÷ 2, color; width=w))
        push!(elems, GraphicsLine(cx, cy + s ÷ 2, cx + s, cy - s ÷ 2, color; width=w))
    end
end

# ── Icons (Stage 5) ───────────────────────────────────────────────────────────
#
# An icon is a *named* value, not a `GraphicsImage`. A registry maps each name to a
# renderer with the uniform signature `(elems, x, y, size, color) -> nothing`; the
# widget printers ask the registry to draw an icon at the label's color + size
# (tinting like text), never branching on the backing. v1 ships a built-in vector
# set (tinted `GraphicsPolyline`/`Line`/`Circle`); a glyph-font or raster icon drops
# in by name via `glyph_icon` / `image_icon` with no widget-code change.

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

# A glyph-font icon: render a codepoint as text in an icon font (tintable, scales).
# (No icon font is bundled yet; use any `StyleFont` whose glyph the backend has.)
glyph_icon(font::StyleFont, codepoint) =
    (elems, x, y, size, color) -> begin
        push!(elems, GraphicsText(string(codepoint), x, y, font, color))
    end

# A raster icon: blit an `ImageDocument`'s decoded pixels (NOT tinted — for art).
image_icon(image::ImageDocument) =
    (elems, x, y, size, color) -> begin
        data, _, _ = _image_payload(image)
        data === nothing || push!(elems, GraphicsImage(Int32(x), Int32(y), Int32(size), Int32(size), data))
    end

# Push a vector glyph: each point is normalized to the unit box, scaled to `size`
# and offset to `(x, y)`. `closed` repeats the first point to close the outline.
function _icon_path!(elems::Vector, x::Int, y::Int, size::Int, color::StyleColor,
                     pts::Vector{<:Tuple}; closed::Bool=false, width::Int=0)
    w = width > 0 ? width : max(1, size ÷ 8)
    P = Tuple{Int,Int}[(x + round(Int, px * size), y + round(Int, py * size)) for (px, py) in pts]
    closed && length(P) > 1 && push!(P, P[1])
    push!(elems, GraphicsPolyline(P, color; width=w))
end

# ── Built-in vector icon set ────────────────────────────────────────────────
# Each draws inside a unit box (insets keep strokes off the very edge), tinted by
# the caller's color. Generalises the chevron / checkmark drawers.

_icon_chevron_down(e, x, y, s, c) = _icon_path!(e, x, y, s, c, [(0.25, 0.40), (0.50, 0.65), (0.75, 0.40)])
_icon_chevron_right(e, x, y, s, c) = _icon_path!(e, x, y, s, c, [(0.40, 0.25), (0.65, 0.50), (0.40, 0.75)])
_icon_check(e, x, y, s, c) = _icon_path!(e, x, y, s, c, [(0.20, 0.55), (0.42, 0.78), (0.80, 0.25)])
_icon_x(e, x, y, s, c) = (_icon_path!(e, x, y, s, c, [(0.25, 0.25), (0.75, 0.75)]);
                          _icon_path!(e, x, y, s, c, [(0.75, 0.25), (0.25, 0.75)]))
_icon_plus(e, x, y, s, c) = (_icon_path!(e, x, y, s, c, [(0.50, 0.20), (0.50, 0.80)]);
                             _icon_path!(e, x, y, s, c, [(0.20, 0.50), (0.80, 0.50)]))
_icon_minus(e, x, y, s, c) = _icon_path!(e, x, y, s, c, [(0.20, 0.50), (0.80, 0.50)])
_icon_menu(e, x, y, s, c) = (_icon_path!(e, x, y, s, c, [(0.18, 0.30), (0.82, 0.30)]);
                             _icon_path!(e, x, y, s, c, [(0.18, 0.50), (0.82, 0.50)]);
                             _icon_path!(e, x, y, s, c, [(0.18, 0.70), (0.82, 0.70)]))
_icon_file(e, x, y, s, c) = _icon_path!(e, x, y, s, c,
    [(0.28, 0.15), (0.62, 0.15), (0.74, 0.30), (0.74, 0.85), (0.28, 0.85)]; closed=true)
_icon_folder(e, x, y, s, c) = _icon_path!(e, x, y, s, c,
    [(0.15, 0.30), (0.42, 0.30), (0.50, 0.40), (0.85, 0.40), (0.85, 0.78), (0.15, 0.78)]; closed=true)
_icon_save(e, x, y, s, c) = (_icon_path!(e, x, y, s, c,
    [(0.20, 0.20), (0.66, 0.20), (0.80, 0.34), (0.80, 0.80), (0.20, 0.80)]; closed=true);
    _icon_path!(e, x, y, s, c, [(0.34, 0.20), (0.34, 0.42), (0.62, 0.42), (0.62, 0.20)]))
_icon_pencil(e, x, y, s, c) = (_icon_path!(e, x, y, s, c, [(0.62, 0.18), (0.82, 0.38), (0.34, 0.86), (0.16, 0.86), (0.16, 0.68)]; closed=true);
                               _icon_path!(e, x, y, s, c, [(0.55, 0.25), (0.75, 0.45)]))
_icon_trash(e, x, y, s, c) = (_icon_path!(e, x, y, s, c, [(0.20, 0.30), (0.80, 0.30)]);
                              _icon_path!(e, x, y, s, c, [(0.40, 0.30), (0.40, 0.20), (0.60, 0.20), (0.60, 0.30)]);
                              _icon_path!(e, x, y, s, c, [(0.27, 0.30), (0.31, 0.82), (0.69, 0.82), (0.73, 0.30)]))
_icon_search(e, x, y, s, c) = begin
    cx = x + round(Int, 0.42s); cy = y + round(Int, 0.42s); rad = max(2, round(Int, 0.22s))
    # Hollow ring (transparent fill, tinted outline) + a diagonal handle.
    push!(e, GraphicsCircle(cx, cy, rad, StyleColor(c.red, c.green, c.blue, 0.0); border_width=max(1, s ÷ 9), border_color=c))
    _icon_path!(e, x, y, s, c, [(0.60, 0.60), (0.84, 0.84)])
end

for (name, fn) in (:chevron_down => _icon_chevron_down, :chevron_right => _icon_chevron_right,
                   :check => _icon_check, :x => _icon_x, :close => _icon_x,
                   :plus => _icon_plus, :minus => _icon_minus, :menu => _icon_menu,
                   :file => _icon_file, :folder => _icon_folder, :save => _icon_save,
                   :pencil => _icon_pencil, :edit => _icon_pencil, :trash => _icon_trash,
                   :delete => _icon_trash, :search => _icon_search)
    register_icon!(name, fn)
end

# ── WidgetToggle ────────────────────────────────────────────────────────────

@projection struct WidgetToggleToGraphicsCanvas
    measure::Function
    font::StyleFont
    padding::Inset
    corner_radius::Int
    border::StyleStroke              # outline (drawn only when released)
    pressed_fill::StyleColor
    pressed_foreground::StyleColor
    released_fill::StyleColor
    released_foreground::StyleColor
    disabled_fill::StyleColor
    disabled_foreground::StyleColor
    ring_color::StyleColor
end

function print_document(p::WidgetToggleToGraphicsCanvas, recursion, w::WidgetToggle, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    position = w.position::Point2D
    text = string(w.content)
    on  = w.pressed === true
    enabled = !(w.enabled === false)
    padding_x = _sc(Int(p.padding.left[]))
    padding_y = _sc(Int(p.padding.top[]))
    text_width, text_height = _text_size(p.measure, p.font, text)
    control_width  = text_width + 2padding_x
    control_height = text_height + 2padding_y
    fill       = !enabled ? p.disabled_fill : on ? p.pressed_fill : p.released_fill
    foreground = !enabled ? p.disabled_foreground : on ? p.pressed_foreground : p.released_foreground
    # Disabled and released states both show the outline; pressed drops it.
    border_color = (on && enabled) ? nothing : p.border.color
    border_width = (on && enabled) ? 0 : max(1, _sc(p.border.width))
    elements = Any[]
    _push_panel!(elements, 0, 0, control_width, control_height; fill=fill, border=border_color,
                 border_w=border_width, radius=_sc(p.corner_radius))
    push!(elements, GraphicsText(text, (control_width - text_width) ÷ 2, (control_height - text_height) ÷ 2, p.font, foreground))
    _push_focus_ring!(elements, w, control_width, control_height, p.ring_color, _sc(p.corner_radius))
    SimpleIoMap(p, w, _make_canvas(_origin(position)..., control_width, control_height, elements))
end
@_printer_only WidgetToggleToGraphicsCanvas

# ── WidgetToggleGroup ───────────────────────────────────────────────────────

@projection struct WidgetToggleGroupToGraphicsCanvas
    measure::Function
    font::StyleFont
    padding::Inset
    corner_radius::Int
    segment_inset::Int
    border::StyleStroke
    track_color::StyleColor            # outer container fill
    selected_fill::StyleColor          # raised segment fill
    selected_foreground::StyleColor
    unselected_foreground::StyleColor
    disabled_color::StyleColor         # track / selected segment when !enabled
    disabled_foreground::StyleColor    # labels when !enabled
    ring_color::StyleColor             # focus ring when selected
end

function print_document(p::WidgetToggleGroupToGraphicsCanvas, recursion, w::WidgetToggleGroup, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    position = w.position::Point2D
    enabled = !(w.enabled === false)
    selected = Int(w.selected)
    padding_x = _sc(Int(p.padding.left[]))
    padding_y = _sc(Int(p.padding.top[]))
    labels = [string(o) for o in w.options]
    _, text_height = _text_size(p.measure, p.font, "M")
    segment_widths = [(_text_size(p.measure, p.font, l)[1] + 2padding_x) for l in labels]
    control_height = text_height + 2padding_y
    control_width  = sum(segment_widths; init=0)
    corner_radius = _sc(p.corner_radius)
    segment_inset = _sc(p.segment_inset)
    track_c    = enabled ? p.track_color    : p.disabled_color
    seg_fill   = enabled ? p.selected_fill  : p.disabled_color
    sel_fg     = enabled ? p.selected_foreground   : p.disabled_foreground
    unsel_fg   = enabled ? p.unselected_foreground : p.disabled_foreground
    elements = Any[]
    # Outer container (track + border).
    _push_panel!(elements, 0, 0, control_width, control_height; fill=track_c, border=p.border.color,
                 border_w=max(1, _sc(p.border.width)), radius=corner_radius)
    x = 0
    for i in eachindex(labels)
        segment_width = segment_widths[i]
        if i == selected
            _push_panel!(elements, x + segment_inset, segment_inset,
                         segment_width - 2segment_inset, control_height - 2segment_inset;
                         fill=seg_fill, radius=max(0, corner_radius - segment_inset))
        end
        text_width, segment_text_height = _text_size(p.measure, p.font, labels[i])
        foreground = i == selected ? sel_fg : unsel_fg
        push!(elements, GraphicsText(labels[i], x + (segment_width - text_width) ÷ 2, (control_height - segment_text_height) ÷ 2, p.font, foreground))
        x += segment_width
    end
    _push_focus_ring!(elements, w, control_width, control_height, p.ring_color, corner_radius)
    SimpleIoMap(p, w, _make_canvas(_origin(position)..., control_width, control_height, elements))
end
@_printer_only WidgetToggleGroupToGraphicsCanvas

# ── WidgetSelect ────────────────────────────────────────────────────────────

@projection struct WidgetSelectToGraphicsCanvas
    measure::Function
    text::ImmutableCell{DStyleText}            # value font + color
    background_color::StyleColor
    border::StyleStroke         # input outline
    padding::Inset
    corner_radius::Int
    gap::Int                   # space between value and chevron
    chevron::StyleStroke        # chevron color + width
    chevron_size::Int
    disabled_color::StyleColor  # box fill when !enabled
    disabled_foreground::StyleColor # value + chevron when !enabled
    ring_color::StyleColor      # focus ring when selected
end

# Carries the anchor (the select's own document path, captured from `ctx.reference`
# at print time) and the rendered box size, so the reader can open the dropdown
# popup anchored under the box without re-deriving its position. `control_width`
# fixes the popup width to the box; `control_height` places it just below.
struct WidgetSelectToGraphicsCanvasIoMap <: IoMap
    projection::Any
    input::WidgetSelect
    output::GraphicsCanvas
    anchor::ReferencePath
    control_width::Int
    control_height::Int
end

function print_document(p::WidgetSelectToGraphicsCanvas, recursion, w::WidgetSelect, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    position = w.position::Point2D
    text = string(w.value)
    enabled = !(w.enabled === false)
    padding_x = _sc(Int(p.padding.left[]))
    padding_y = _sc(Int(p.padding.top[]))
    text_width, text_height = _text_size(p.measure, p.text.font, text)
    chevron_size = _sc(p.chevron_size)
    # Fit the value text, a gap, the trailing chevron and both paddings.
    content_min = 2padding_x + text_width + _sc(p.gap) + 2chevron_size
    control_width = _resolve_width(ctx, _sc(Int(w.width)), content_min)
    control_height = text_height + 2padding_y
    box_fill   = enabled ? p.background_color : p.disabled_color
    text_color = enabled ? p.text.color : p.disabled_foreground
    chevron_color = enabled ? p.chevron.color : p.disabled_foreground
    elements = Any[]
    _push_panel!(elements, 0, 0, control_width, control_height; fill=box_fill, border=p.border.color,
                 border_w=max(1, _sc(p.border.width)), radius=_sc(p.corner_radius))
    push!(elements, GraphicsText(text, padding_x, (control_height - text_height) ÷ 2, p.text.font, text_color))
    _push_chevron!(elements, control_width - padding_x - chevron_size, control_height ÷ 2, chevron_size, :down,
                   chevron_color; stroke=max(1, _sc(p.chevron.width)))
    _push_focus_ring!(elements, w, control_width, control_height, p.ring_color, _sc(p.corner_radius))
    canvas = _make_canvas(_origin(position)..., control_width, control_height, elements)
    WidgetSelectToGraphicsCanvasIoMap(p, w, canvas, ctx.reference, control_width, control_height)
end

# Forward image (Step 2.0): the select is a positioned leaf, so the empty
# reference maps to its top-left in its own frame; parent containers shift it on
# the way up. A content-root resolver reads this to anchor the dropdown popup.
map_reference_forward(::WidgetSelectToGraphicsCanvas, iomap::WidgetSelectToGraphicsCanvasIoMap, reference) =
    _self_point(reference)
map_reference_forward(::WidgetSelectToGraphicsCanvas, iomap::SimpleIoMap, reference) = nothing
map_reference_backward(::WidgetSelectToGraphicsCanvas, iomap, reference) = nothing

# Invisible select (printer returned a bare empty canvas): inert.
read_intent(::WidgetSelectToGraphicsCanvas, iomap::SimpleIoMap, evt) = nothing

# A left click on the box opens the option list as a floating popup window,
# anchored just below the box. The reader carries only the anchor reference + a
# trigger-baked offset; a content-root resolver (`WidgetPopupResolver`) maps the
# anchor forward to absolute coordinates and turns this into an `OpenWindowOperation`.
# The deep reader never computes its own screen position.
function read_intent(p::WidgetSelectToGraphicsCanvas, iomap::WidgetSelectToGraphicsCanvasIoMap, evt)
    w = iomap.input
    w.enabled === false && return nothing
    @event_case evt begin
        MousePress(button, x, y) => button === :left ? _open_select_popup(w, iomap) : nothing
        _ => nothing
    end
end

# Build the dropdown: a `VerticalLayout` of `WidgetOption`s (one per selectable
# value, each pointing back at this select for the value write) wrapped in an
# `OpenPopupOperation` anchored under the box. No options ⇒ nothing to open.
function _open_select_popup(w::WidgetSelect, iomap::WidgetSelectToGraphicsCanvasIoMap)
    opts = collect(w.options)
    isempty(opts) && return nothing
    gap = 4
    items = Any[WidgetOption(Point2D(0, 0), w, opt; width=iomap.control_width) for opt in opts]
    OpenPopupOperation(; id=:widget_popup, anchor=iomap.anchor,
                       dx=0, dy=iomap.control_height + gap,
                       width=iomap.control_width, height=length(opts) * iomap.control_height,
                       auto_dismiss=true, content=VerticalLayout(items))
end

# ── WidgetOption ──────────────────────────────────────────────────────────────
# One row of an open select dropdown. A plain label on a flat surface; a left
# click writes the value back to the target select and dismisses the popup.

@projection struct WidgetOptionToGraphicsCanvas
    measure::Function
    text::ImmutableCell{DStyleText}
    background_color::StyleColor
    padding::Inset
end

function print_document(p::WidgetOptionToGraphicsCanvas, recursion, w::WidgetOption, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    position = w.position::Point2D
    label = string(w.label)
    padding_x = _sc(Int(p.padding.left[]))
    padding_y = _sc(Int(p.padding.top[]))
    text_width, text_height = _text_size(p.measure, p.text.font, label)
    row_width = _resolve_width(ctx, _sc(Int(w.width)), text_width + 2padding_x)
    row_height = text_height + 2padding_y
    elements = Any[]
    _push_panel!(elements, 0, 0, row_width, row_height; fill=p.background_color)
    push!(elements, GraphicsText(label, padding_x, (row_height - text_height) ÷ 2, p.text.font, p.text.color))
    SimpleIoMap(p, w, _make_canvas(_origin(position)..., row_width, row_height, elements))
end

map_reference_forward(::WidgetOptionToGraphicsCanvas, iomap, reference) = _self_point(reference)
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
    w = iomap.input
    @event_case evt begin
        MousePress(button, x, y) => button === :left ? _pick_option(w) : nothing
        _ => nothing
    end
end

# ── WidgetSpinBox (Stage 6) ───────────────────────────────────────────────────

_spin_clamp(v, lo, hi) = (lo !== nothing && v < lo) ? lo : ((hi !== nothing && v > hi) ? hi : v)

@projection struct WidgetSpinBoxToGraphicsCanvas
    measure::Function
    text::ImmutableCell{DStyleText}
    background_color::StyleColor
    border::StyleStroke
    padding::Inset
    corner_radius::Int
    disabled_color::StyleColor
    disabled_foreground::StyleColor
    stepper_color::StyleColor
    ring_color::StyleColor
end

struct WidgetSpinBoxToGraphicsCanvasIoMap <: IoMap
    projection::Any
    input::WidgetSpinBox
    output::GraphicsCanvas
    control_width::Int
    control_height::Int
    stepper_w::Int
end

function print_document(p::WidgetSpinBoxToGraphicsCanvas, recursion, w::WidgetSpinBox, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    position = w.position::Point2D
    enabled = !(w.enabled === false)
    text = string(w.value)
    pad_x = _sc(Int(p.padding.left[])); pad_y = _sc(Int(p.padding.top[]))
    tw, th = _text_size(p.measure, p.text.font, text)
    control_height = th + 2pad_y
    stepper_w = control_height
    content_min = 2pad_x + tw + stepper_w
    control_width = _resolve_width(ctx, _sc(Int(w.width)), content_min)
    box_fill   = enabled ? p.background_color : p.disabled_color
    text_color = enabled ? p.text.color : p.disabled_foreground
    step_color = enabled ? p.stepper_color : p.disabled_foreground
    bw = max(1, _sc(p.border.width))
    elements = Any[]
    _push_panel!(elements, 0, 0, control_width, control_height; fill=box_fill,
                 border=p.border.color, border_w=bw, radius=_sc(p.corner_radius))
    _push_text!(elements, p.text.font, text, pad_x, (control_height - th) ÷ 2, text_color)
    sx = control_width - stepper_w
    push!(elements, GraphicsLine(sx, 0, sx, control_height, p.border.color; width=bw))
    isz = max(8, control_height ÷ 2 - _sc(3))
    ix = sx + (stepper_w - isz) ÷ 2
    _push_icon!(elements, :plus,  ix, (control_height ÷ 2 - isz) ÷ 2, isz, step_color)
    _push_icon!(elements, :minus, ix, control_height ÷ 2 + (control_height ÷ 2 - isz) ÷ 2, isz, step_color)
    _push_focus_ring!(elements, w, control_width, control_height, p.ring_color, _sc(p.corner_radius))
    canvas = _make_canvas(_origin(position)..., control_width, control_height, elements)
    WidgetSpinBoxToGraphicsCanvasIoMap(p, w, canvas, control_width, control_height, stepper_w)
end

map_reference_forward(::WidgetSpinBoxToGraphicsCanvas, iomap::WidgetSpinBoxToGraphicsCanvasIoMap, reference) = _self_point(reference)
map_reference_forward(::WidgetSpinBoxToGraphicsCanvas, iomap, reference) = nothing
map_reference_backward(::WidgetSpinBoxToGraphicsCanvas, iomap, reference) = nothing

read_intent(::WidgetSpinBoxToGraphicsCanvas, iomap::SimpleIoMap, evt) = nothing
function read_intent(p::WidgetSpinBoxToGraphicsCanvas, iomap::WidgetSpinBoxToGraphicsCanvasIoMap, evt)
    w = iomap.input
    (w.enabled === false) && return nothing
    _step(delta) = ReplaceReferencedValueOperation(w, "value", _spin_clamp(w.value + delta, w.min, w.max))
    @event_case evt begin
        MousePress(button, x, y) =>
            (button === :left && x >= iomap.control_width - iomap.stepper_w) ?
                (y < iomap.control_height ÷ 2 ? _step(w.step) : _step(-w.step)) : nothing
        when(KeyDown(k), k === :up)   => _step(w.step)
        when(KeyDown(k), k === :down) => _step(-w.step)
        _ => nothing
    end
end

# ── WidgetList (Stage 6) ──────────────────────────────────────────────────────

@projection struct WidgetListToGraphicsCanvas
    measure::Function
    text::ImmutableCell{DStyleText}
    background_color::StyleColor
    border::StyleStroke
    selected_color::StyleColor
    selected_foreground::StyleColor
    padding::Inset
    corner_radius::Int
end

struct WidgetListToGraphicsCanvasIoMap <: IoMap
    projection::Any
    input::WidgetList
    output::GraphicsCanvas
    row_height::Int
    control_width::Int
end

function print_document(p::WidgetListToGraphicsCanvas, recursion, w::WidgetList, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    position = w.position::Point2D
    pad_x = _sc(Int(p.padding.left[])); pad_y = _sc(Int(p.padding.top[]))
    items = collect(w.items)
    n = length(items)
    _, th = _text_size(p.measure, p.text.font, "M")
    row_height = th + 2pad_y
    intrinsic = 0
    for it in items
        tw, _ = _text_size(p.measure, p.text.font, string(it))
        intrinsic = max(intrinsic, tw + 2pad_x)
    end
    control_width = _resolve_width(ctx, _sc(Int(w.width)), intrinsic)
    control_height = max(row_height, n * row_height)
    sel = Int(w.selected)
    elements = Any[]
    _push_panel!(elements, 0, 0, control_width, control_height; fill=p.background_color,
                 border=p.border.color, border_w=max(1, _sc(p.border.width)), radius=_sc(p.corner_radius))
    for (i, it) in enumerate(items)
        y = (i - 1) * row_height
        fg = p.text.color
        if i == sel
            _push_panel!(elements, 0, y, control_width, row_height; fill=p.selected_color)
            fg = p.selected_foreground
        end
        _push_text!(elements, p.text.font, string(it), pad_x, y + pad_y, fg)
    end
    canvas = _make_canvas(_origin(position)..., control_width, control_height, elements)
    WidgetListToGraphicsCanvasIoMap(p, w, canvas, row_height, control_width)
end

map_reference_forward(::WidgetListToGraphicsCanvas, iomap::WidgetListToGraphicsCanvasIoMap, reference) = _self_point(reference)
map_reference_forward(::WidgetListToGraphicsCanvas, iomap, reference) = nothing
map_reference_backward(::WidgetListToGraphicsCanvas, iomap, reference) = nothing

read_intent(::WidgetListToGraphicsCanvas, iomap::SimpleIoMap, evt) = nothing
function read_intent(p::WidgetListToGraphicsCanvas, iomap::WidgetListToGraphicsCanvasIoMap, evt)
    w = iomap.input
    (w.enabled === false) && return nothing
    n = length(collect(w.items))
    n == 0 && return nothing
    sel = Int(w.selected)
    click_row(yy) = (r = yy ÷ iomap.row_height + 1; (1 <= r <= n) ? ReplaceReferencedValueOperation(w, "selected", r) : nothing)
    @event_case evt begin
        MousePress(button, x, y) => button === :left ? click_row(y) : nothing
        when(KeyDown(k), k === :down) => ReplaceReferencedValueOperation(w, "selected", sel == 0 ? 1 : min(sel + 1, n))
        when(KeyDown(k), k === :up)   => ReplaceReferencedValueOperation(w, "selected", sel <= 1 ? 1 : sel - 1)
        _ => nothing
    end
end

# ── WidgetTextarea ──────────────────────────────────────────────────────────

@projection struct WidgetTextareaToGraphicsCanvas
    measure::Function
    text::ImmutableCell{DStyleText}            # content font + color
    background_color::StyleColor
    border::StyleStroke         # input outline
    padding::Inset
    corner_radius::Int
    disabled_color::StyleColor  # background when !enabled
    disabled_foreground::StyleColor # text when !enabled
    ring_color::StyleColor      # focus ring when selected
end

function print_document(p::WidgetTextareaToGraphicsCanvas, recursion, w::WidgetTextarea, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    position = w.position::Point2D
    enabled = !(w.enabled === false)
    padding_x = _sc(Int(p.padding.left[]))
    padding_y = _sc(Int(p.padding.top[]))
    lines = split(string(w.content), '\n')
    _, line_height = _text_size(p.measure, p.text.font, "M")
    row_count = max(Int(w.rows), length(lines))
    area_height = row_count * line_height + 2padding_y
    longest_line = isempty(lines) ? 0 : maximum(_text_size(p.measure, p.text.font, String(l))[1] for l in lines)
    area_width = _resolve_width(ctx, _sc(Int(w.width)), longest_line + 2padding_x)
    box_fill   = enabled ? p.background_color : p.disabled_color
    text_color = enabled ? p.text.color       : p.disabled_foreground
    elements = Any[]
    _push_panel!(elements, 0, 0, area_width, area_height; fill=box_fill, border=p.border.color,
                 border_w=max(1, _sc(p.border.width)), radius=_sc(p.corner_radius))
    for (i, line) in enumerate(lines)
        push!(elements, GraphicsText(String(line), padding_x, padding_y + (i - 1) * line_height, p.text.font, text_color))
    end
    _push_focus_ring!(elements, w, area_width, area_height, p.ring_color, _sc(p.corner_radius))
    SimpleIoMap(p, w, _make_canvas(_origin(position)..., area_width, area_height, elements))
end
@_printer_only WidgetTextareaToGraphicsCanvas

# ── WidgetAccordion ─────────────────────────────────────────────────────────

@projection struct WidgetAccordionToGraphicsCanvas
    measure::Function
    title_text::ImmutableCell{DStyleText}        # bold title
    body_text::ImmutableCell{DStyleText}          # muted body
    rule::StyleStroke             # hairline between items
    padding::Inset                # horizontal + vertical row padding
    gap::Int                      # space before the trailing chevron
    body_gap::Int                 # gap above the expanded body
    chevron::StyleStroke          # chevron color + width
    chevron_size::Int
end

function print_document(p::WidgetAccordionToGraphicsCanvas, recursion, w::WidgetAccordion, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    position = w.position::Point2D
    expanded = Int(w.expanded)
    padding_x = _sc(Int(p.padding.left[]))
    padding_y = _sc(Int(p.padding.top[]))
    chevron_size = _sc(p.chevron_size)
    # Size to content: widest title (leaving room for the trailing chevron) and
    # the widest visible (expanded) body. The authored width is the minimum.
    title_min = 0; body_min = 0
    for (i, item) in enumerate(w.items)
        title_min = max(title_min, _text_size(p.measure, p.title_text.font, string(item.title))[1])
        if i == expanded && item.body !== nothing
            body_min = max(body_min, _text_size(p.measure, p.body_text.font, string(item.body))[1])
        end
    end
    content_min = max(2padding_x + title_min + _sc(p.gap) + 2chevron_size, 2padding_x + body_min)
    accordion_width = _resolve_width(ctx, _sc(Int(w.width)), content_min)
    elements = Any[]
    y = 0
    rule_width = max(1, _sc(p.rule.width))
    for (i, item) in enumerate(w.items)
        title = string(item.title)
        body  = item.body === nothing ? "" : string(item.body)
        _, title_height = _text_size(p.measure, p.title_text.font, title)
        row_height = title_height + 2padding_y
        push!(elements, GraphicsText(title, padding_x, y + padding_y, p.title_text.font, p.title_text.color))
        _push_chevron!(elements, accordion_width - padding_x - chevron_size, y + row_height ÷ 2, chevron_size,
                       i == expanded ? :down : :right, p.chevron.color; stroke=max(1, _sc(p.chevron.width)))
        y += row_height
        if i == expanded && !isempty(body)
            _, body_height = _text_size(p.measure, p.body_text.font, body)
            push!(elements, GraphicsText(body, padding_x, y + _sc(p.body_gap), p.body_text.font, p.body_text.color))
            y += body_height + padding_y
        end
        push!(elements, GraphicsLine(0, y, accordion_width, y, p.rule.color; width=rule_width))
    end
    SimpleIoMap(p, w, _make_canvas(_origin(position)..., accordion_width, y, elements))
end
@_printer_only WidgetAccordionToGraphicsCanvas

# ── WidgetTable ─────────────────────────────────────────────────────────────
#
# The single table abstraction. The renderer delegates *all positioning* to a
# `GridLayout` (built from the recursed cell documents) and overlays the table
# decorations — borders, hairline rules, header styling, selection bands — using
# the grid geometry it reads off the `GridLayoutIoMap` ("layout is just layout").
#
# Layout / padding model. The grid's children are the bare cell documents; the
# grid uses `horizontal_gap = vertical_gap = 2*padding + border_width` so that
# every inter-cell gap is "padding-right + rule + padding-left", and the whole
# grid canvas is offset by `border_width + padding` inside the outer canvas so
# the first row/column is padded too. Rules are then drawn centred in the gaps
# (and on the outer edges) at edges computed from the grid geometry. This yields
# uniformly-padded cells while reusing GridLayout for the actual positioning.
#
# Selection. Field names `rows` / `column_headers` / `row_headers` are the public
# reference vocabulary. A whole-element selection is a path terminating at the element (`∅`);
# the renderer — the one place with the grid geometry — turns a 1-D handle into a
# 2-D highlight band. An in-cell cursor (`rows[r][c].…`) descends into the cell's
# own sub-pipeline and is drawn there.

@projection struct WidgetTableToGraphicsCanvas
    cell_text::ImmutableCell{DStyleText}          # (kept for theming parity; cells render via recursion)
    header_text::ImmutableCell{DStyleText}        # header strip text style
    rule::StyleStroke             # border / hairline rules
    header_fill::StyleColor       # header strip background
end

# Translucent selection accent (same blue the syntax-text / old table highlight used).
const _WT_HL_COLOR = StyleColor(0x88 / 255, 0xbb / 255, 0xee / 255, 0x40 / 255)
# Fainter still: the hover band drawn behind the row under the pointer (half the
# selection alpha, so a selected+hovered row still reads as selected).
const _WT_HOVER_COLOR = StyleColor(0x88 / 255, 0xbb / 255, 0xee / 255, 0x20 / 255)
const _WT_HL_RADIUS = 4
# Fully transparent fill for the tree's whole-canvas hit target (see the printer).
const _WT_HIT_COLOR = StyleColor(0.0, 0.0, 0.0, 0.0)

# Grid geometry snapshot for a WidgetTable, derived from the GridLayoutIoMap plus
# the table's own padding / border. `col_x` / `row_y` are cumulative left/top
# edges in *outer-canvas* coordinates, length grid_cols+1 / grid_rows+1 so that
# `col_x[gc+1]` is the right edge of grid column gc.
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
    pad::Int                 # inner padding
    grid_off::Int            # outer offset of the grid canvas (= bw + pad)
end

# IoMap: carries the grid iomap (for cell delegation) plus the persisted geometry
# (the table analog of TextToGraphics's char_to_coord).
struct WidgetTableToGraphicsCanvasIoMap <: IoMap
    projection::Any
    input::Any
    output::Any
    grid_iomap::Cell         # the GridLayoutIoMap
    geometry::Cell
end

# A WidgetTable carries `rows`, `column_headers`, `row_headers`. The grid is laid
# out row-major over `grid_rows × grid_cols` cells where the (optional) header
# strips occupy grid row/column 1. The corner and any short cells are filled with
# an empty placeholder so the grid sizes consistently.
_wt_has_col_headers(w::WidgetTable) = length(w.column_headers) > 0
_wt_has_row_headers(w::WidgetTable) = length(w.row_headers) > 0
_wt_empty_cell() = WidgetLabel(Point2D(0, 0), "")

# Build the flat row-major list of grid-child documents for the table.
function _wt_grid_children(w::WidgetTable)
    nrows = length(w.rows)
    ncols = Int(w.column_count)
    has_ch = _wt_has_col_headers(w)
    has_rh = _wt_has_row_headers(w)
    row_offset = has_ch ? 1 : 0
    col_offset = has_rh ? 1 : 0
    grid_rows = nrows + row_offset
    grid_cols = ncols + col_offset
    children = Any[]
    for gr in 1:grid_rows
        for gc in 1:grid_cols
            doc = _wt_cell_doc(w, gr, gc, row_offset, col_offset, ncols)
            push!(children, doc === nothing ? _wt_empty_cell() : doc)
        end
    end
    (children, grid_rows, grid_cols, row_offset, col_offset, nrows, ncols, has_ch, has_rh)
end

# The document occupying grid position (gr, gc), or nothing (→ placeholder).
function _wt_cell_doc(w::WidgetTable, gr::Int, gc::Int, row_offset::Int, col_offset::Int, ncols::Int)
    header_row = row_offset == 1 && gr == 1
    header_col = col_offset == 1 && gc == 1
    if header_row && header_col
        return nothing                       # corner
    elseif header_row
        c = gc - col_offset
        return (1 <= c <= length(w.column_headers)) ? w.column_headers[c] : nothing
    elseif header_col
        r = gr - row_offset
        return (1 <= r <= length(w.row_headers)) ? w.row_headers[r] : nothing
    else
        r = gr - row_offset
        c = gc - col_offset
        row = (1 <= r <= length(w.rows)) ? w.rows[r] : nothing
        row === nothing && return nothing
        return (1 <= c <= length(row)) ? row[c] : nothing
    end
end

# Map a (gr, gc) grid position to the flat grid-child index (1-based, row-major).
_wt_grid_index(gr::Int, gc::Int, grid_cols::Int) = (gr - 1) * grid_cols + gc

# Compute the outer geometry from the GridLayoutIoMap and the table padding/border.
function _wt_geometry(gim::GridLayoutIoMap, grid_rows::Int, grid_cols::Int,
                      row_offset::Int, col_offset::Int, nrows::Int, ncols::Int,
                      has_ch::Bool, has_rh::Bool, pad::Int, bw::Int)
    grid_off = bw + pad
    # Per-grid-column width and per-grid-row height from the layout geometry.
    col_w = Int[Int(gim.col_w[c][]) for c in 1:grid_cols]
    row_h = Int[Int(gim.row_h[r][]) for r in 1:grid_rows]
    # Cumulative edges. `col_x[gc]` is the position of the rule to the LEFT of grid
    # column gc (so col_x[1] = 0 is the left border, col_x[grid_cols+1] is the
    # right border). The content-left of column gc is col_x[gc] + bw + pad, which
    # matches the GridLayout child x (Σ prev (col_w+gap)) plus grid_off=bw+pad,
    # since each box advance is col_w + 2*pad + bw (= the layout gap plus col_w).
    col_x = Vector{Int}(undef, grid_cols + 1)
    col_x[1] = 0
    for gc in 1:grid_cols
        col_x[gc + 1] = col_x[gc] + col_w[gc] + 2 * pad + bw
    end
    row_y = Vector{Int}(undef, grid_rows + 1)
    row_y[1] = 0
    for gr in 1:grid_rows
        row_y[gr + 1] = row_y[gr] + row_h[gr] + 2 * pad + bw
    end
    total_w = col_x[grid_cols + 1] + bw   # + trailing right border
    total_h = row_y[grid_rows + 1] + bw
    WTGeometry(nrows, ncols, row_offset, col_offset, grid_rows, grid_cols,
               has_rh, has_ch, col_x, row_y, total_w, total_h, bw, pad, grid_off)
end

# ── Selection-shape recognition ───────────────────────────────────────────────
# `.<field>[index]∅` → (field_name, 1-based index), else nothing.
function _wt_field_element_terminal(sel)
    # Selections are canonical (carry TypeReference checkpoints); skip them
    # before each structural step so the shape match is modulo checkpoints.
    sel = sel
    sel isa ConcreteReferencePath || return nothing
    h = sel.head
    h isa FieldReference || return nothing
    t = sel.tail
    t isa ConcreteReferencePath || return nothing
    r = t.head
    (r isa RangeReference && is_element_reference(r)) || return nothing
    t.tail isa EmptyReferencePath || return nothing
    (h.name, r.start + 1)
end

# (:table,_,_) | (:row,r,_) | (:col,c,_) | (:cell,r,c) | nothing
function _wt_selection_shape(sel, geom::WTGeometry)
    sel isa EmptyReferencePath && return (:table, 0, 0)
    fe = _wt_field_element_terminal(sel)
    if fe !== nothing
        field, idx = fe
        if field == "rows"
            (1 <= idx <= geom.nrows) || return nothing
            return (:row, idx, 0)
        elseif field == "column_headers"
            (1 <= idx <= geom.ncols) || return nothing
            return (:col, idx, 0)
        elseif field == "row_headers"
            (1 <= idx <= geom.nrows) || return nothing
            return (:row, idx, 0)
        end
        return nothing
    end
    # `rows[r][c]∅` → whole cell (r,c).
    rc = _wt_cell_terminal(sel)
    rc === nothing && return nothing
    r, c = rc
    (1 <= r <= geom.nrows && 1 <= c <= geom.ncols) || return nothing
    return (:cell, r, c)
end

# `rows[r][c]∅` (element c of row r, terminating) → (r, c), else nothing.
function _wt_cell_terminal(sel)
    sel = sel
    sel isa ConcreteReferencePath || return nothing
    (sel.head isa FieldReference && sel.head.name == "rows") || return nothing
    t = sel.tail
    t isa ConcreteReferencePath || return nothing
    (t.head isa RangeReference && is_element_reference(t.head)) || return nothing
    r = t.head.start + 1
    t2 = t.tail
    t2 isa ConcreteReferencePath || return nothing
    (t2.head isa RangeReference && is_element_reference(t2.head)) || return nothing
    c = t2.head.start + 1
    t2.tail isa EmptyReferencePath || return nothing
    (r, c)
end

# (x, y, w, h) of the selection highlight band in outer-canvas coordinates, or
# (0, 0, 0, 0) when there is no valid selection — a 0-size rect the renderer skips.
# Drawn as a persistent overlay whose geometry reads the selection, so a caret
# move never rebuilds the table's content vector (printer-locality dimension A).
function _wt_highlight_bounds(sel, geom::WTGeometry)
    shape = _wt_selection_shape(sel, geom)
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
    end
    (0, 0, 0, 0)
end

function print_document(p::WidgetTableToGraphicsCanvas, recursion, w::WidgetTable, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    position = w.position::Point2D
    pad = _sc(Int(w.padding))
    bw  = max(1, _sc(Int(w.border_width)))
    grid_off = bw + pad

    layout_info = Cell(() -> _wt_grid_children(w))

    # Build a GridLayout whose children are the recursed cell documents and
    # project it through `recursion` (which dispatches GridLayout → its renderer
    # and each cell document → its own projection). Gaps carry the per-cell
    # padding + rule so positioning matches the decoration overlay.
    grid_iomap = Cell(() -> begin
        info = layout_info[]
        children, grid_rows, grid_cols = info[1], info[2], info[3]
        gap = 2 * pad + bw
        grid = GridLayout(children, grid_cols;
                          horizontal_gap=gap, vertical_gap=gap)
        # The grid is positioned at grid_off inside the outer canvas; extend the
        # context reference to the table's grid so child contexts are rooted here.
        print_child(recursion, grid, ctx)
    end)

    geometry = Cell(() -> begin
        info = layout_info[]
        _, grid_rows, grid_cols, row_offset, col_offset, nrows, ncols, has_ch, has_rh = info
        gim = grid_iomap[]
        gim isa GridLayoutIoMap || return _wt_geometry_empty(pad, bw)
        _wt_geometry(gim, grid_rows, grid_cols, row_offset, col_offset,
                     nrows, ncols, has_ch, has_rh, pad, bw)
    end)

    # Persistent selection-highlight overlay: one rect whose bounds read the
    # selection (collapsed to 0×0 when there is none — the renderer skips it).
    # Keeping the selection read OUT of the elements thunk means a caret move
    # invalidates only this rect's geometry, not the whole content vector
    # (printer-locality dimension A; the focus-ring / text-cursor overlay pattern).
    hl_bounds = Cell(() -> _wt_highlight_bounds(w.selection, geometry[]))
    highlight_rect = GraphicsRect(0, 0, 0, 0, _WT_HL_COLOR, _WT_HL_RADIUS)
    set_cell_function!(getfield(highlight_rect, :x), () -> Int32(hl_bounds[][1]))
    set_cell_function!(getfield(highlight_rect, :y), () -> Int32(hl_bounds[][2]))
    set_cell_function!(getfield(highlight_rect, :w), () -> Int32(hl_bounds[][3]))
    set_cell_function!(getfield(highlight_rect, :h), () -> Int32(hl_bounds[][4]))

    # Persistent hover-band overlay: same pattern as the selection band but reading
    # `w.hovered` (the row / column-header under the pointer) in the fainter hover
    # colour. Drawn behind the selection band so a selected+hovered row still reads
    # as selected.
    hov_bounds = Cell(() -> _wt_highlight_bounds(w.hovered, geometry[]))
    hover_rect = GraphicsRect(0, 0, 0, 0, _WT_HOVER_COLOR, _WT_HL_RADIUS)
    set_cell_function!(getfield(hover_rect, :x), () -> Int32(hov_bounds[][1]))
    set_cell_function!(getfield(hover_rect, :y), () -> Int32(hov_bounds[][2]))
    set_cell_function!(getfield(hover_rect, :w), () -> Int32(hov_bounds[][3]))
    set_cell_function!(getfield(hover_rect, :h), () -> Int32(hov_bounds[][4]))

    # Invisible whole-canvas hit target so a table nested in a container (which
    # gates routing on `hit_element_at`) is hoverable/clickable over empty cell
    # interiors, not just over drawn glyphs/rules. Cf. the WidgetTree hit target.
    hit_target = GraphicsRect(0, 0, 0, 0, _WT_HIT_COLOR, 0)
    set_cell_function!(getfield(hit_target, :w), () -> Int32(geometry[].total_w))
    set_cell_function!(getfield(hit_target, :h), () -> Int32(geometry[].total_h))

    elements = CellVector(() -> begin
        geom = geometry[]
        gim = grid_iomap[]
        result = Any[]
        geom.grid_cols == 0 && return result
        # 0. Whole-canvas hit target (behind everything).
        push!(result, hit_target)
        # 1. Header strip backgrounds (behind everything). The column-header strip
        #    occupies grid row 1; the row-header strip occupies grid column 1.
        if geom.has_col_headers
            push!(result, GraphicsRect(0, 0, geom.total_w, geom.row_y[2], p.header_fill))
        end
        if geom.has_row_headers
            push!(result, GraphicsRect(0, 0, geom.col_x[2], geom.total_h, p.header_fill))
        end
        # 2. Hover + selection highlight overlays (persistent; their geometry reads
        #    the hovered / selected node so this thunk does not), behind the grid
        #    content and rules. Hover is behind selection.
        push!(result, hover_rect)
        push!(result, highlight_rect)
        # 3. The positioned grid content (from GridLayout), offset by grid_off.
        if gim isa GridLayoutIoMap
            gcanvas = gim.output
            if gcanvas isa GraphicsCanvas
                push!(result, _make_canvas(geom.grid_off, geom.grid_off, Any[gcanvas]))
            end
        end
        # 4. Horizontal rules — at row_y[gr] for gr in 1..grid_rows+1 (top border,
        #    inner rules, bottom border).
        for gr in 1:(geom.grid_rows + 1)
            push!(result, GraphicsRect(0, geom.row_y[gr], geom.total_w, bw,
                                       p.rule.color))
        end
        # 5. Vertical rules — at col_x[gc] for gc in 1..grid_cols+1.
        for gc in 1:(geom.grid_cols + 1)
            push!(result, GraphicsRect(geom.col_x[gc], 0, bw, geom.total_h,
                                       p.rule.color))
        end
        result
    end)

    canvas = GraphicsCanvas(Cell(Int32(_origin(position)[1])), Cell(Int32(_origin(position)[2])),
                            Cell(() -> Int32(geometry[].total_w)),
                            Cell(() -> Int32(geometry[].total_h)),
                            elements, layout_none, true, Cell(nothing))
    WidgetTableToGraphicsCanvasIoMap(p, w, canvas, grid_iomap, geometry)
end

_wt_geometry_empty(pad::Int, bw::Int) =
    WTGeometry(0, 0, 0, 0, 0, 0, false, false, Int[bw], Int[bw], bw, bw, bw, pad, bw + pad)

# ── Reference mapping ────────────────────────────────────────────────────────
# Forward: a table-domain selection pointing into a cell's content
# (`rows[r][c].…` / `column_headers[c].…` / `row_headers[r].…`) is delegated to
# the corresponding GridLayout child so the in-cell cursor is forward-projected.
# Whole-element handles (`rows[r]∅`, `∅`, …) have no image on the canvas — the
# band is drawn in place during print — so they map to nothing.
function map_reference_forward(p::WidgetTableToGraphicsCanvas, iomap::WidgetTableToGraphicsCanvasIoMap, reference)
    geom = iomap.geometry[]
    gim = iomap.grid_iomap[]
    gim isa GridLayoutIoMap || return nothing
    target = _wt_ref_to_grid_index(reference, geom)
    target === nothing && return nothing
    gidx, tail = target
    # Delegate the tail through the grid's forward map, addressed as children[gidx].
    grid_ref = ConcreteReferencePath(FieldReference("children"),
                ConcreteReferencePath(RangeReference(gidx - 1, gidx), tail))
    map_reference_forward(gim.projection, gim, grid_ref)
end

map_reference_forward(::WidgetTableToGraphicsCanvas, iomap, reference) = nothing

# Backward: a grid-domain reference (`children[gidx].…`) maps back to the table
# domain (`rows[r][c].…` etc.).
function map_reference_backward(p::WidgetTableToGraphicsCanvas, iomap::WidgetTableToGraphicsCanvasIoMap, reference)
    geom = iomap.geometry[]
    _wt_grid_ref_to_table(reference, geom)
end

map_reference_backward(::WidgetTableToGraphicsCanvas, iomap, reference) = nothing

# Decode a table-domain reference into (grid_index, tail) or nothing.
function _wt_ref_to_grid_index(reference, geom::WTGeometry)
    reference isa ConcreteReferencePath || return nothing
    h = reference.head
    h isa FieldReference || return nothing
    t = reference.tail
    t isa ConcreteReferencePath || return nothing
    e = t.head
    (e isa RangeReference && is_element_reference(e)) || return nothing
    idx1 = e.start + 1
    if h.name == "column_headers"
        (1 <= idx1 <= geom.ncols) || return nothing
        gr = 1
        gc = idx1 + geom.col_offset
        return (_wt_grid_index(gr, gc, geom.grid_cols), t.tail)
    elseif h.name == "row_headers"
        (1 <= idx1 <= geom.nrows) || return nothing
        gr = idx1 + geom.row_offset
        gc = 1
        return (_wt_grid_index(gr, gc, geom.grid_cols), t.tail)
    elseif h.name == "rows"
        # rows[r][c].<tail>
        t2 = t.tail
        t2 isa ConcreteReferencePath || return nothing
        e2 = t2.head
        (e2 isa RangeReference && is_element_reference(e2)) || return nothing
        c = e2.start + 1
        r = idx1
        (1 <= r <= geom.nrows && 1 <= c <= geom.ncols) || return nothing
        gr = r + geom.row_offset
        gc = c + geom.col_offset
        return (_wt_grid_index(gr, gc, geom.grid_cols), t2.tail)
    end
    return nothing
end

# Decode a grid-domain reference (`children[gidx].<tail>`) into the table domain.
function _wt_grid_ref_to_table(reference, geom::WTGeometry)
    reference isa ConcreteReferencePath || return nothing
    (reference.head isa FieldReference && reference.head.name == "children") || return nothing
    t = reference.tail
    t isa ConcreteReferencePath || return nothing
    (t.head isa RangeReference && is_element_reference(t.head)) || return nothing
    gidx = t.head.start + 1
    tail = t.tail
    geom.grid_cols <= 0 && return nothing
    gr = div(gidx - 1, geom.grid_cols) + 1
    gc = mod(gidx - 1, geom.grid_cols) + 1
    header_row = geom.row_offset == 1 && gr == 1
    header_col = geom.col_offset == 1 && gc == 1
    if header_row && header_col
        return nothing
    elseif header_row
        c = gc - geom.col_offset
        return ConcreteReferencePath(FieldReference("column_headers"),
                ConcreteReferencePath(RangeReference(c - 1, c), tail))
    elseif header_col
        r = gr - geom.row_offset
        return ConcreteReferencePath(FieldReference("row_headers"),
                ConcreteReferencePath(RangeReference(r - 1, r), tail))
    else
        r = gr - geom.row_offset
        c = gc - geom.col_offset
        return ConcreteReferencePath(FieldReference("rows"),
                ConcreteReferencePath(RangeReference(r - 1, r),
                ConcreteReferencePath(RangeReference(c - 1, c), tail)))
    end
end

# ── Reading (gestures) ───────────────────────────────────────────────────────
# Gesture-aware reader. Left clicks resolve here (header/corner → row/column/
# table; Alt+click promotes a data cell to a whole cell; a plain click routes
# into the cell content). Keyboard grid navigation
# (Alt+arrows, Ctrl+Alt+Home, Shift/Ctrl+Space, Enter) is resolved against the
# live table. Everything else falls through to per-cell editing via the grid.
function read_intent(p::WidgetTableToGraphicsCanvas, recursion, change::Intent, iomap::WidgetTableToGraphicsCanvasIoMap)
    g = change.gesture
    if change.operation === nothing && g isa MousePress && g.button === :left
        return Intent(g, _wt_mouse_select(iomap, g))
    end
    # Pointer crossings (synthesised by WidgetHoverTrackingProjection) drive the
    # hover band: MouseEnter always re-writes (so the tracker keeps the table as its
    # hover target), MouseMove writes only when the hovered row changes, MouseLeave
    # clears.
    if change.operation === nothing && g isa MouseEnter
        return Intent(g, _wt_hover_set(iomap, g.x, g.y, true))
    end
    if change.operation === nothing && g isa MouseMove
        return Intent(g, _wt_hover_set(iomap, g.x, g.y, false))
    end
    if change.operation === nothing && g isa MouseLeave
        return Intent(g, _wt_hover_clear(iomap))
    end
    if change.operation === nothing && g isa KeyDown
        op = _wt_key_navigate(iomap, g, iomap.geometry[])
        op === nothing || return Intent(g, op)
    end
    # Fall through: plain editing keys route into the active cell via the grid; an
    # already-produced operation passes straight through. Use the grid passthrough
    # directly (not the 3-arg reader) to avoid re-entering this gesture logic.
    payload = change.operation === nothing ? g : change.operation
    return Intent(g, _wt_grid_passthrough(p, iomap, payload))
end

# Resolve a left click into a selection operation (or nothing).
function _wt_mouse_select(iomap::WidgetTableToGraphicsCanvasIoMap, g::MousePress)
    geom = iomap.geometry[]
    hit = _wt_hit_test(geom, g.x, g.y)
    kind = hit[1]
    if kind === :corner
        return ReplaceSelectionOperation(EmptyReferencePath())
    elseif kind === :row
        r = hit[2]
        return ReplaceSelectionOperation(
            ConcreteReferencePath(FieldReference("rows"),
                ConcreteReferencePath(RangeReference(r - 1, r), EmptyReferencePath())))
    elseif kind === :col
        c = hit[2]
        return ReplaceSelectionOperation(
            ConcreteReferencePath(FieldReference("column_headers"),
                ConcreteReferencePath(RangeReference(c - 1, c), EmptyReferencePath())))
    elseif kind === :cell
        r, c = hit[2], hit[3]
        if g.modifiers.alt
            return ReplaceSelectionOperation(
                ConcreteReferencePath(FieldReference("rows"),
                    ConcreteReferencePath(RangeReference(r - 1, r),
                    ConcreteReferencePath(RangeReference(c - 1, c), EmptyReferencePath()))))
        else
            return _wt_route_cell_click(iomap, geom, r, c, g)
        end
    end
    return nothing
end

# Classify a click point: :corner | (:row,r) | (:col,c) | (:cell,r,c) | :outside.
function _wt_hit_test(geom::WTGeometry, x::Int, y::Int)
    (0 <= x < geom.total_w && 0 <= y < geom.total_h) || return (:outside, 0, 0)
    gc = 0
    for c in 1:geom.grid_cols
        if geom.col_x[c] <= x < geom.col_x[c + 1]
            gc = c; break
        end
    end
    gr = 0
    for r in 1:geom.grid_rows
        if geom.row_y[r] <= y < geom.row_y[r + 1]
            gr = r; break
        end
    end
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

# ── Hover (whole-row) ────────────────────────────────────────────────────────
# The hover band highlights the *row* under the pointer (a body cell or a row
# header → that row); a column header → its column; the corner / outside → none.
# Returns the `hovered` reference for (x, y), or nothing.
function _wt_hover_ref(geom::WTGeometry, x::Int, y::Int)
    hit = _wt_hit_test(geom, x, y)
    kind = hit[1]
    (kind === :cell || kind === :row) && return _wt_row_ref(hit[2])
    kind === :col && return _wt_col_ref(hit[2])
    return nothing
end

# Set `hovered` to the row/column under (x, y). `force` (a MouseEnter, i.e. a
# boundary crossing) always re-emits so the hover tracker keeps the table as its
# target; a plain MouseMove emits only when the hovered region changes. Off the
# grid returns nothing (the tracker's MouseLeave clears it).
function _wt_hover_set(iomap::WidgetTableToGraphicsCanvasIoMap, x::Int, y::Int, force::Bool)
    w = iomap.input
    ref = _wt_hover_ref(iomap.geometry[], x, y)
    ref === nothing && return nothing
    (!force && w.hovered == ref) && return nothing
    ReplaceReferencedValueOperation(w, "hovered", ref)
end

function _wt_hover_clear(iomap::WidgetTableToGraphicsCanvasIoMap)
    w = iomap.input
    w.hovered === nothing && return nothing
    ReplaceReferencedValueOperation(w, "hovered", nothing)
end

# Route a plain click into a data cell's content sub-pipeline (via the grid
# child), translating the click into the cell's frame, then wrap the resulting
# operation back into the table domain.
function _wt_route_cell_click(iomap::WidgetTableToGraphicsCanvasIoMap, geom::WTGeometry,
                              r::Int, c::Int, g::MousePress)
    gim = iomap.grid_iomap[]
    gim isa GridLayoutIoMap || return nothing
    gr = r + geom.row_offset
    gc = c + geom.col_offset
    gidx = _wt_grid_index(gr, gc, geom.grid_cols)
    entries = gim.child_iomaps[]::Vector
    (1 <= gidx <= length(entries)) || return nothing
    entry = entries[gidx]
    entry === nothing && return nothing
    (ox_cell, oy_cell, cim) = entry::Tuple{Cell,Cell,Any}
    canvas = cim.output
    canvas isa GraphicsCanvas || return nothing
    # Child position = grid_off (grid canvas offset) + child wrapper offset + child canvas offset.
    cell_x = geom.grid_off + Int(ox_cell[]) + Int(canvas.x)
    cell_y = geom.grid_off + Int(oy_cell[]) + Int(canvas.y)
    local_evt = MousePress(g.button, g.x - cell_x, g.y - cell_y, g.modifiers)
    op = read_intent(cim.projection, cim, local_evt)
    op isa ReplaceSelectionOperation || return nothing
    table_ref = _wt_grid_ref_to_table(
        ConcreteReferencePath(FieldReference("children"),
            ConcreteReferencePath(RangeReference(gidx - 1, gidx), op.path)), geom)
    table_ref === nothing ? nothing : ReplaceSelectionOperation(table_ref)
end

# Keyboard grid navigation, addressed via rows[r][c].
function _wt_key_navigate(iomap::WidgetTableToGraphicsCanvasIoMap, evt::KeyDown, geom::WTGeometry)
    nrows, ncols = geom.nrows, geom.ncols
    (nrows == 0 || ncols == 0) && return nothing
    sel = iomap.input.selection

    if evt.key === :home && evt.modifiers.ctrl && evt.modifiers.alt
        return ReplaceSelectionOperation(EmptyReferencePath())
    end

    shape = _wt_selection_shape(sel, geom)
    cell_rc = _wt_cell_terminal(sel)

    if evt.key === :return
        if shape !== nothing && shape[1] === :row
            return ReplaceSelectionOperation(_wt_cell_ref(shape[2], 1))
        elseif shape !== nothing && shape[1] === :col
            return ReplaceSelectionOperation(_wt_cell_ref(1, shape[2]))
        elseif cell_rc !== nothing
            return _wt_enter_cell_content(iomap, geom, cell_rc[1], cell_rc[2])
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
                return ReplaceSelectionOperation(_wt_cell_ref(r, 1))
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
                return ReplaceSelectionOperation(_wt_cell_ref(1, c))
            else
                return nothing
            end
        else
            cell_rc === nothing && return nothing
            r, c = cell_rc
            if evt.key === :up
                r = max(1, r - 1)
            elseif evt.key === :down
                r = min(nrows, r + 1)
            elseif evt.key === :left
                c = max(1, c - 1)
            elseif evt.key === :right
                c = min(ncols, c + 1)
            end
            return ReplaceSelectionOperation(_wt_cell_ref(r, c))
        end
    end
    return nothing
end

_wt_row_ref(r::Int) = ConcreteReferencePath(FieldReference("rows"),
    ConcreteReferencePath(RangeReference(r - 1, r), EmptyReferencePath()))
_wt_col_ref(c::Int) = ConcreteReferencePath(FieldReference("column_headers"),
    ConcreteReferencePath(RangeReference(c - 1, c), EmptyReferencePath()))
_wt_cell_ref(r::Int, c::Int) = ConcreteReferencePath(FieldReference("rows"),
    ConcreteReferencePath(RangeReference(r - 1, r),
    ConcreteReferencePath(RangeReference(c - 1, c), EmptyReferencePath())))

# Place a character cursor at the start of a cell's content.
function _wt_enter_cell_content(iomap::WidgetTableToGraphicsCanvasIoMap, geom::WTGeometry, r::Int, c::Int)
    gim = iomap.grid_iomap[]
    gim isa GridLayoutIoMap || return nothing
    gr = r + geom.row_offset
    gc = c + geom.col_offset
    gidx = _wt_grid_index(gr, gc, geom.grid_cols)
    entries = gim.child_iomaps[]::Vector
    (1 <= gidx <= length(entries)) || return nothing
    entry = entries[gidx]
    entry === nothing && return nothing
    cim = entry[3]
    op = read_intent(cim.projection, cim, KeyDown(:home, Modifiers(ctrl=true)))
    op isa ReplaceSelectionOperation || return nothing
    table_ref = _wt_grid_ref_to_table(
        ConcreteReferencePath(FieldReference("children"),
            ConcreteReferencePath(RangeReference(gidx - 1, gidx), op.path)), geom)
    table_ref === nothing ? nothing : ReplaceSelectionOperation(table_ref)
end

# 3-arg fall-through form. Reached two ways: (a) the 4-arg gesture reader above
# delegates plain editing events here; (b) a *parent* container (composite, grid,
# split pane) routes a raw event to this nested table via the 3-arg call. For (b)
# we must still run the table's own gesture logic (left-click selection, grid
# navigation), so a bare MousePress/KeyDown is lifted into a Intent and handled by
# the 4-arg reader. Anything else dispatches to the grid and is re-rooted.
function read_intent(p::WidgetTableToGraphicsCanvas, iomap::WidgetTableToGraphicsCanvasIoMap, event)
    if event isa MousePress || event isa KeyDown ||
       event isa MouseEnter || event isa MouseMove || event isa MouseLeave
        return read_intent(p, nothing, Intent(event, nothing), iomap).operation
    end
    return _wt_grid_passthrough(p, iomap, event)
end

# Dispatch a non-gesture event to the grid; the active cell answers and the grid
# returns a `children[gidx].…` op, which we re-root into the table domain.
function _wt_grid_passthrough(p::WidgetTableToGraphicsCanvas, iomap::WidgetTableToGraphicsCanvasIoMap, event)
    gim = iomap.grid_iomap[]
    gim isa GridLayoutIoMap || return nothing
    geom = iomap.geometry[]
    op = read_intent(gim.projection, gim, event)
    op isa ReplaceSelectionOperation || return nothing
    table_ref = _wt_grid_ref_to_table(op.path, geom)
    table_ref === nothing ? nothing : ReplaceSelectionOperation(table_ref)
end

# ── WidgetTree ──────────────────────────────────────────────────────────────

@projection struct WidgetTreeToGraphicsCanvas
    measure::Function
    label_text::ImmutableCell{DStyleText}         # node labels
    icon_text::ImmutableCell{DStyleText}          # node icon glyphs (own column)
    indent::Int                   # per-depth horizontal step
    chevron_column::Int           # width reserved for the expand chevron
    icon_column::Int              # width reserved for the icon glyph
    row_padding::Int              # vertical padding per row
    chevron::StyleStroke          # chevron color + width
    chevron_size::Int
end

# A node is a WidgetTreeNode (icon + label + children), a leaf label (String), or
# a bare (label, children::Vector) tuple. Icon-less nodes report an empty icon.
_tree_icon(node)  = node isa WidgetTreeNode ? node.icon : ""
_tree_label(node) = node isa WidgetTreeNode ? string(node.label) :
                    (node isa Tuple ? string(node[1]) : string(node))
function _tree_children(node)
    if node isa WidgetTreeNode
        isempty(node.children) ? nothing : node.children
    elseif node isa Tuple && length(node) >= 2 && node[2] isa AbstractVector
        node[2]
    else
        nothing
    end
end

# One flattened, rendered row. `path` is the 1-based index chain from the roots
# down to this node (`[i]`, `[i, j]`, …); `y0`/`height` are its band in
# outer-canvas coordinates. `depth`, `icon`, `label`, `has_children` carry
# everything the element pass needs so it never re-walks the node tree.
# `collapsed` (true only for a parent whose children are hidden) drives the
# chevron direction; `chevron_x0`/`chevron_x1` are its horizontal click hit-box,
# so the reader can distinguish a chevron toggle from a row select.
struct WTreeRow
    path::Vector{Int}
    depth::Int
    icon::Any
    label::String
    has_children::Bool
    collapsed::Bool
    chevron_x0::Int
    chevron_x1::Int
    y0::Int
    height::Int
end

# Geometry snapshot: the flattened rows plus the canvas extent. Persisted on the
# iomap so the reader can hit-test clicks and resolve keyboard navigation (the
# tree analog of the table's `WTGeometry`).
struct WTreeGeometry
    rows::Vector{WTreeRow}
    total_w::Int
    total_h::Int
end

struct WidgetTreeToGraphicsCanvasIoMap <: IoMap
    projection::Any
    input::Any
    output::Any
    geometry::Cell
end

# ── Node-path ⇄ WidgetTree reference ─────────────────────────────────────────
# A node at path `[i, j, k]` is addressed `roots[i].children[j].children[k]`
# (a `FieldReference` + element `RangeReference` per level), mirroring how the
# table addresses `rows[r][c]`. These are the single source of truth shared by
# the selection band, the click reader, and the FileSystemToWidget mappers.

function _wtree_path_ref(path::Vector{Int}, k::Int=1)
    isempty(path) && return EmptyReferencePath()
    field = k == 1 ? "roots" : "children"
    idx = path[k]
    tail = k == length(path) ? EmptyReferencePath() : _wtree_path_ref(path, k + 1)
    ConcreteReferencePath(FieldReference(field),
        ConcreteReferencePath(RangeReference(idx - 1, idx), tail))
end

function _wtree_ref_path(reference)
    cur = reference
    path = Int[]
    first = true
    while cur isa ConcreteReferencePath
        h = cur.head
        (h isa FieldReference && h.name == (first ? "roots" : "children")) || return nothing
        t = cur.tail
        (t isa ConcreteReferencePath && t.head isa RangeReference && is_element_reference(t.head)) || return nothing
        push!(path, t.head.start + 1)
        cur = t.tail
        cur isa EmptyReferencePath && return path
        first = false
    end
    isempty(path) ? nothing : path
end

# (y0, height) of the selected row's highlight band, or (0, 0) when no node is
# selected — a 0-height rect the renderer skips. Drawn as a persistent overlay so
# a selection move never rebuilds the tree's content vector (dimension A).
function _wtree_highlight_band(sel, geom)
    sel_path = _wtree_ref_path(sel)
    sel_path === nothing && return (0, 0)
    for row in geom.rows
        row.path == sel_path && return (row.y0, row.height)
    end
    (0, 0)
end

function print_document(p::WidgetTreeToGraphicsCanvas, recursion, w::WidgetTree, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    position = w.position::Point2D
    indent = _sc(p.indent)
    chevron_column = _sc(p.chevron_column)
    icon_column = _sc(p.icon_column)
    chevron_size = _sc(p.chevron_size)
    pad = _sc(p.row_padding)
    _, line_height = _text_size(p.measure, p.label_text.font, "M")
    row_height = line_height + 2 * pad

    # Flatten the node tree into rows once; both the geometry (hit-testing) and the
    # element pass (drawing) read these rows, so they can never drift apart. Reading
    # `w.collapsed` here ties the flattened geometry to the collapse state, so a
    # chevron toggle re-runs the walk (hiding / revealing subtrees) reactively.
    geometry = Cell(() -> begin
        collapsed = w.collapsed
        rows = WTreeRow[]
        max_width = Ref(0)
        y = Ref(0)
        function walk(node, depth, path)
            x = depth * indent
            label = _tree_label(node)
            kids = _tree_children(node)
            has_kids = kids !== nothing && !isempty(kids)
            is_collapsed = has_kids && (path in collapsed)
            label_width, _ = _text_size(p.measure, p.label_text.font, label)
            push!(rows, WTreeRow(path, depth, _tree_icon(node), label,
                                 has_kids, is_collapsed, x, x + chevron_column, y[], row_height))
            max_width[] = max(max_width[], x + chevron_column + icon_column + label_width)
            y[] += row_height
            if has_kids && !is_collapsed
                for (i, c) in enumerate(kids)
                    walk(c, depth + 1, vcat(path, i))
                end
            end
        end
        for (i, n) in enumerate(w.roots)
            walk(n, 0, [i])
        end
        WTreeGeometry(rows, max_width[], y[])
    end)

    chevron_stroke = max(1, _sc(p.chevron.width))

    # Whole-canvas transparent hit target. The tree hit-tests by *row band* (a whole
    # row is clickable/hoverable, not just its glyphs), but a parent container gates
    # routing on `hit_element_at`, which only fires over an actual element — so a tree
    # nested in a layout/tab would ignore clicks/hover on the empty part of a row.
    # A full-size (invisible) rect makes the whole canvas a hit target, matching the
    # top-level tree. Its geometry reads `geometry[]` so it tracks size reactively.
    hit_target = GraphicsRect(0, 0, 0, 0, _WT_HIT_COLOR, 0)
    set_cell_function!(getfield(hit_target, :w), () -> Int32(geometry[].total_w))
    set_cell_function!(getfield(hit_target, :h), () -> Int32(geometry[].total_h))

    # Persistent selection-band overlay: one full-width rect whose y/height read
    # the selection (0 height when no node is selected → the renderer skips it).
    # Keeping the selection read OUT of the elements thunk means a node move
    # invalidates only this rect's geometry, not the content vector (dimension A;
    # the focus-ring / text-cursor overlay pattern).
    band_yh = Cell(() -> _wtree_highlight_band(w.selection, geometry[]))
    selection_band = GraphicsRect(0, 0, 0, 0, _WT_HL_COLOR, _WT_HL_RADIUS)
    set_cell_function!(getfield(selection_band, :y), () -> Int32(band_yh[][1]))
    set_cell_function!(getfield(selection_band, :h), () -> Int32(band_yh[][2]))
    set_cell_function!(getfield(selection_band, :w), () -> Int32(geometry[].total_w))

    # Persistent hover-band overlay, same pattern as the selection band but reading
    # `w.hovered` (the row under the pointer). Drawn behind the selection band so a
    # selected+hovered row still reads as selected.
    hover_yh = Cell(() -> _wtree_highlight_band(w.hovered, geometry[]))
    hover_band = GraphicsRect(0, 0, 0, 0, _WT_HOVER_COLOR, _WT_HL_RADIUS)
    set_cell_function!(getfield(hover_band, :y), () -> Int32(hover_yh[][1]))
    set_cell_function!(getfield(hover_band, :h), () -> Int32(hover_yh[][2]))
    set_cell_function!(getfield(hover_band, :w), () -> Int32(geometry[].total_w))

    elements = CellVector(() -> begin
        geom = geometry[]
        result = Any[]
        # 0. Invisible whole-canvas hit target (behind everything) so a nested tree
        #    is clickable/hoverable over the whole row, not just over its glyphs.
        push!(result, hit_target)
        # 1. Hover + selection band overlays (persistent; their geometry reads the
        #    hovered / selected node so this thunk does not), behind the row content.
        push!(result, hover_band)
        push!(result, selection_band)
        # 2. Per-row decoration: chevron (parents) + icon glyph + label.
        for row in geom.rows
            x = row.depth * indent
            if row.has_children
                _push_chevron!(result, x + chevron_column ÷ 2, row.y0 + row_height ÷ 2,
                               chevron_size, row.collapsed ? :right : :down, p.chevron.color;
                               stroke=chevron_stroke)
            end
            icon = row.icon
            if icon isa Symbol
                # A registered icon name (Stage 5): vector/glyph, tinted to the icon color.
                _push_icon!(result, icon, x + chevron_column, row.y0 + pad, line_height, p.icon_text.color)
            elseif icon isa AbstractString && !isempty(icon)
                # A literal glyph string (e.g. an emoji), drawn as text.
                push!(result, GraphicsText(icon, x + chevron_column, row.y0 + pad,
                                           p.icon_text.font, p.icon_text.color))
            end
            push!(result, GraphicsText(row.label, x + chevron_column + icon_column, row.y0 + pad,
                                       p.label_text.font, p.label_text.color))
        end
        result
    end)

    canvas = GraphicsCanvas(Cell(Int32(_origin(position)[1])), Cell(Int32(_origin(position)[2])),
                            Cell(() -> Int32(geometry[].total_w)),
                            Cell(() -> Int32(geometry[].total_h)),
                            elements, layout_none, true, Cell(nothing))
    WidgetTreeToGraphicsCanvasIoMap(p, w, canvas, geometry)
end

# Whole-node handles have no in-canvas cursor image (the band is drawn in place at
# print time), and nothing flows back from below the graphics layer — so both
# reference mappers are the empty map, exactly as the table's whole-element case.
map_reference_forward(::WidgetTreeToGraphicsCanvas, iomap, reference) = nothing
map_reference_backward(::WidgetTreeToGraphicsCanvas, iomap, reference) = nothing

# Gesture reader: a left click on a parent's chevron toggles collapse, otherwise
# selects the node under the cursor; pointer crossings (`MouseEnter`/`MouseMove`/
# `MouseLeave`, synthesised by `WidgetHoverTrackingProjection`) drive the hover
# band; ↑/↓ walk the flattened rows. Handled in the 3-arg form (like the other
# widgets) so a container routing an event into the tree via
# `read_intent(cim.projection, cim, evt)` reaches it — the default 4-arg
# `read_intent` bridges the editor's top-level `Intent` to this. Non-gestures
# return nothing: the tree is a leaf (no child ops bubble up to re-target).
#
# Per-instance gestures are consulted first — tree-level, then per-node — so a
# binding can add / override (shadow) / suppress; the built-in select / collapse /
# hover / nav below is the fallback.
function read_intent(p::WidgetTreeToGraphicsCanvas, iomap::WidgetTreeToGraphicsCanvasIoMap, evt)
    w = iomap.input
    op = read_bound_gesture(w, evt)
    op === nothing || return op
    nop = _wtree_node_gesture(iomap, evt)
    nop === nothing || return nop
    if evt isa MousePress && evt.button === :left
        return _wtree_mouse_press(iomap, evt)
    elseif evt isa MouseEnter
        return _wtree_hover_set(iomap, evt.x, evt.y, true)
    elseif evt isa MouseMove
        return _wtree_hover_set(iomap, evt.x, evt.y, false)
    elseif evt isa MouseLeave
        return _wtree_hover_clear(iomap)
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

# Per-node gesture consult: find the node targeted by `g` — the row under the
# pointer for a `MousePress` (any button/modifier; the binding's own pattern does
# the matching), or the currently selected node for a `KeyDown` — and fire its
# `get_instance_gesture_bindings` against the enclosing tree's selection. A node has no
# `selection` of its own, hence the explicit-selection `read_bound_gesture`.
function _wtree_node_gesture(iomap::WidgetTreeToGraphicsCanvasIoMap, g)
    w = iomap.input
    geom = iomap.geometry[]
    path = nothing
    if g isa MousePress
        (0 <= g.x < geom.total_w && 0 <= g.y < geom.total_h) || return nothing
        for row in geom.rows
            if row.y0 <= g.y < row.y0 + row.height
                path = row.path
                break
            end
        end
    elseif g isa KeyDown
        path = _wtree_ref_path(w.selection)
    end
    path === nothing && return nothing
    node = _wtree_node_at(w, path)
    node === nothing && return nothing
    return read_bound_gesture(node, g, w.selection)
end

# A left click on a parent row's chevron column toggles its collapse; anywhere
# else on a row selects it.
function _wtree_mouse_press(iomap::WidgetTreeToGraphicsCanvasIoMap, g::MousePress)
    geom = iomap.geometry[]
    (0 <= g.x < geom.total_w && 0 <= g.y < geom.total_h) || return nothing
    for row in geom.rows
        if row.y0 <= g.y < row.y0 + row.height
            if row.has_children && row.chevron_x0 <= g.x < row.chevron_x1
                return _wtree_toggle_collapse(iomap, row.path)
            end
            return ReplaceSelectionOperation(_wtree_path_ref(row.path))
        end
    end
    return nothing
end

# Toggle `path`'s membership in the tree's collapse set. Stores a *new* Set so the
# backing cell invalidates and the geometry thunk re-flattens.
function _wtree_toggle_collapse(iomap::WidgetTreeToGraphicsCanvasIoMap, path::Vector{Int})
    w = iomap.input
    next = copy(w.collapsed)
    path in next ? delete!(next, path) : push!(next, path)
    ReplaceReferencedValueOperation(w, "collapsed", next)
end

# Set the hovered row to the one under (x, y). `force` (a `MouseEnter`, i.e. a
# tree-boundary crossing) always re-emits the write so the hover tracker keeps the
# tree as its target; a plain `MouseMove` emits only when the row actually changes,
# and returns nothing outside every row (the tracker's MouseLeave clears it).
function _wtree_hover_set(iomap::WidgetTreeToGraphicsCanvasIoMap, x::Int, y::Int, force::Bool)
    geom = iomap.geometry[]
    w = iomap.input
    if 0 <= x < geom.total_w && 0 <= y < geom.total_h
        for row in geom.rows
            if row.y0 <= y < row.y0 + row.height
                (!force && _wtree_ref_path(w.hovered) == row.path) && return nothing
                return ReplaceReferencedValueOperation(w, "hovered", _wtree_path_ref(row.path))
            end
        end
    end
    return nothing
end

function _wtree_hover_clear(iomap::WidgetTreeToGraphicsCanvasIoMap)
    w = iomap.input
    w.hovered === nothing && return nothing
    ReplaceReferencedValueOperation(w, "hovered", nothing)
end

function _wtree_key_navigate(iomap::WidgetTreeToGraphicsCanvasIoMap, g::KeyDown)
    g.key in (:up, :down) || return nothing
    geom = iomap.geometry[]
    isempty(geom.rows) && return nothing
    cur = _wtree_ref_path(iomap.input.selection)
    idx = cur === nothing ? 0 : something(findfirst(r -> r.path == cur, geom.rows), 0)
    ni = g.key === :down ? (idx == 0 ? 1 : min(length(geom.rows), idx + 1)) :
                           (idx <= 1 ? 1 : idx - 1)
    ReplaceSelectionOperation(_wtree_path_ref(geom.rows[ni].path))
end

# ── Factory ────────────────────────────────────────────────────────────────

"""
    WidgetToGraphics(font; measure, theme=widget_theme_slate_light(font=font))

Build a recursive type-dispatching projection that maps any `WidgetDocument`
subtree to a `GraphicsCanvas`. `measure(text, font) -> (width, height)` is
used for all text sizing. The `theme` ([`WidgetTheme`](@ref)) is the single
source of truth for colors, radius, and spacing. Defaults to the expressed
slate/indigo light theme; the neutral zinc theme is `widget_theme_light`.
"""
function WidgetToGraphics(font::StyleFont; measure::Function,
                          theme::WidgetTheme=widget_theme_slate_light(font=font))
    # Wrapped measure for the `@projection`-based widget projections, which store
    # their fields in Cells (a bare Function would be read as a thunk).
    measurer = TextMeasurer(measure)
    TypeDispatchingProjection(
        WidgetInsertion  => WidgetInsertionToGraphicsCanvas(measurer, theme.body_text),
        WidgetLabel      => WidgetLabelToGraphicsCanvas(measurer, theme.body_text),
        WidgetText       => WidgetTextToGraphicsCanvas(measurer, theme.body_text, theme.background, theme.input, theme.radius, theme.ring),
        WidgetCheckbox   => WidgetCheckboxToGraphicsCanvas(
            18, theme.radius ÷ 2,
            theme.primary, StyleStroke(theme.primary_foreground, theme.stroke),
            theme.background, StyleStroke(theme.input, theme.stroke),
            theme.muted, theme.muted_foreground, theme.ring),
        WidgetButton     => WidgetButtonToGraphicsCanvas(
            measurer, theme.label_text, theme.background,
            theme.accent, theme.muted,
            StyleStroke(theme.border, theme.border_width),
            Inset(theme.pad_y, theme.pad_y, theme.pad_x, theme.pad_x),
            theme.radius, 2,
            theme.muted, theme.muted_foreground, theme.ring),
        WidgetTooltip    => WidgetTooltipToGraphicsCanvas(measurer, StyleText(theme.font, theme.popover_foreground),
            theme.popover, StyleStroke(theme.border, theme.border_width), theme.radius,
            Inset(theme.pad_y, theme.pad_y, theme.pad_x, theme.pad_x)),
        WidgetContextMenu => WidgetContextMenuToGraphicsCanvas(measurer, theme.font),
        WidgetDialog     => WidgetDialogToGraphicsCanvas(measurer, theme.title_text, theme.body_text,
            theme.card, StyleStroke(theme.border, theme.border_width), theme.radius,
            Inset(theme.pad_y, theme.pad_y, theme.pad_x, theme.pad_x), theme.gap),
        WidgetMenu       => WidgetMenuToGraphicsCanvas(measurer, theme.font),
        WidgetMenuItem   => WidgetMenuItemToGraphicsCanvas(measurer, theme.body_text, theme.muted_foreground, theme.accent),
        WidgetComposite  => WidgetCompositeToGraphicsCanvas(),
        # Widgets embed layouts (a composite/table holds a GridLayout); register
        # it so the recursion can render an embedded grid without an outer
        # layout dispatcher.
        GridLayout       => GridLayoutToGraphicsCanvas(),
        WidgetShell      => WidgetShellToGraphicsCanvas(measurer, theme.font, theme.background, theme.gap),
        WidgetTitlePane  => WidgetTitlePaneToGraphicsCanvas(measurer,
            StyleText(theme.font_bold, theme.foreground), StyleText(theme.font, theme.card_foreground), 6),
        WidgetSplitPane  => WidgetSplitPaneToGraphicsCanvas(StyleStroke(theme.border, theme.border_width)),
        WidgetTabbedPane => WidgetTabbedPaneToGraphicsCanvas(measurer, theme.font, 4, theme.radius,
            theme.muted, theme.background, theme.foreground, theme.muted_foreground),
        WidgetScrollPane => WidgetScrollPaneToGraphicsCanvas(measurer, theme.font, theme.background),
        WidgetTransformPane => WidgetTransformPaneToGraphicsCanvas(measurer, theme.font, theme.background),
        WidgetToolbar    => WidgetToolbarToGraphicsCanvas(measurer, theme.font, theme.gap),
        WidgetStatusBar  => WidgetStatusBarToGraphicsCanvas(measurer, theme.caption_text, theme.muted, theme.gap),
        WidgetScrollBar  => WidgetScrollBarToGraphicsCanvas(theme.muted, theme.border, 8),
        WidgetBadge      => WidgetBadgeToGraphicsCanvas(measurer, theme.font_small,
            Inset(3, 3, 10, 10), theme.border_width,
            theme.primary, theme.primary_foreground,
            theme.secondary, theme.secondary_foreground,
            theme.destructive, theme.destructive_foreground,
            theme.background, theme.foreground, theme.border),
        WidgetSeparator  => WidgetSeparatorToGraphicsCanvas(StyleStroke(theme.border, theme.border_width)),
        WidgetCard       => WidgetCardToGraphicsCanvas(measurer,
            StyleText(theme.font_bold, theme.foreground), StyleText(theme.font_small, theme.muted_foreground),
            StyleText(theme.font, theme.card_foreground), StyleText(theme.font_small, theme.muted_foreground),
            theme.card, StyleStroke(theme.border, theme.border_width), theme.radius,
            16, 4, 10),
        WidgetSwitch     => WidgetSwitchToGraphicsCanvas(
            Point2D(44, 24), 3,
            color_white, StyleStroke(theme.border, theme.border_width),
            theme.primary, theme.track_off, theme.muted, theme.ring),
        WidgetProgress   => WidgetProgressToGraphicsCanvas(8, theme.muted, theme.primary),
        WidgetSlider     => WidgetSliderToGraphicsCanvas(
            24, 4, 9,
            color_white, StyleStroke(theme.primary, theme.stroke),
            theme.muted, theme.primary, theme.muted, theme.ring),
        WidgetRadioGroup => WidgetRadioGroupToGraphicsCanvas(measurer, StyleText(theme.font, theme.foreground),
            18, 10, 12, 5,
            theme.background, StyleStroke(theme.primary, theme.stroke), StyleStroke(theme.input, theme.stroke),
            theme.primary, theme.muted_foreground, theme.ring),
        WidgetAvatar     => WidgetAvatarToGraphicsCanvas(measurer, StyleText(theme.font, theme.muted_foreground), theme.muted),
        WidgetAlert      => WidgetAlertToGraphicsCanvas(measurer, theme.font_bold,
            StyleText(theme.font_small, theme.muted_foreground), theme.background,
            14, 4, theme.radius, theme.border_width,
            theme.foreground, theme.border, theme.destructive),
        WidgetSkeleton   => WidgetSkeletonToGraphicsCanvas(theme.muted, 6),
        WidgetToggle      => WidgetToggleToGraphicsCanvas(measurer, theme.font,
            Inset(theme.pad_y, theme.pad_y, theme.pad_x, theme.pad_x), theme.radius,
            StyleStroke(theme.border, theme.border_width),
            theme.accent, theme.accent_foreground, theme.background, theme.foreground,
            theme.muted, theme.muted_foreground, theme.ring),
        WidgetToggleGroup => WidgetToggleGroupToGraphicsCanvas(measurer, theme.font,
            Inset(theme.pad_y, theme.pad_y, theme.pad_x, theme.pad_x), theme.radius, 2,
            StyleStroke(theme.border, theme.border_width),
            theme.muted, theme.background, theme.foreground, theme.muted_foreground,
            theme.muted, theme.muted_foreground, theme.ring),
        WidgetSelect      => WidgetSelectToGraphicsCanvas(measurer, theme.body_text, theme.background,
            StyleStroke(theme.input, theme.border_width),
            Inset(theme.pad_y, theme.pad_y, theme.pad_x, theme.pad_x), theme.radius,
            theme.gap, StyleStroke(theme.muted_foreground, theme.stroke), theme.chevron,
            theme.muted, theme.muted_foreground, theme.ring),
        WidgetSpinBox     => WidgetSpinBoxToGraphicsCanvas(measurer, theme.body_text, theme.background,
            StyleStroke(theme.input, theme.border_width),
            Inset(theme.pad_y, theme.pad_y, theme.pad_x, theme.pad_x), theme.radius,
            theme.muted, theme.muted_foreground, theme.foreground, theme.ring),
        WidgetList        => WidgetListToGraphicsCanvas(measurer, theme.body_text, theme.background,
            StyleStroke(theme.border, theme.border_width),
            theme.accent, theme.accent_foreground,
            Inset(theme.pad_y, theme.pad_y, theme.pad_x, theme.pad_x), theme.radius),
        WidgetOption      => WidgetOptionToGraphicsCanvas(measurer, theme.body_text, theme.background,
            Inset(theme.pad_y, theme.pad_y, theme.pad_x, theme.pad_x)),
        WidgetTextarea    => WidgetTextareaToGraphicsCanvas(measurer, theme.body_text, theme.background,
            StyleStroke(theme.input, theme.border_width),
            Inset(theme.pad_y, theme.pad_y, theme.pad_x, theme.pad_x), theme.radius,
            theme.muted, theme.muted_foreground, theme.ring),
        WidgetAccordion   => WidgetAccordionToGraphicsCanvas(measurer,
            StyleText(theme.font_bold, theme.foreground), StyleText(theme.font_small, theme.muted_foreground),
            StyleStroke(theme.border, theme.border_width),
            Inset(10, 10, theme.pad_x, theme.pad_x),
            theme.gap, 2, StyleStroke(theme.muted_foreground, theme.stroke), theme.chevron),
        WidgetTable       => WidgetTableToGraphicsCanvas(
            StyleText(theme.font, theme.foreground), StyleText(theme.font_small, theme.muted_foreground),
            StyleStroke(theme.border, theme.border_width),
            theme.muted),
        WidgetTree        => WidgetTreeToGraphicsCanvas(measurer,
            StyleText(theme.font, theme.foreground),
            StyleText(theme.font, theme.muted_foreground),
            22, 18, 20, 4,
            StyleStroke(theme.muted_foreground, theme.stroke), theme.chevron),
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

function print_document(p::WidgetScrollPaneToGraphicsViewport, recursion, w::WidgetScrollPane, ctx)
    content_iomap = print_child(recursion, w.content, ctx)
    content_output = content_iomap.output::GraphicsCanvas

    pos = w.position
    sz  = w.size
    bx = pos isa Point2D ? _sc(Int(pos.x[])) : 0
    by = pos isa Point2D ? _sc(Int(pos.y[])) : 0
    vw = sz isa Point2D ? Int(sz.x[]) : _SCROLL_FALLBACK_WIDTH
    vh = sz isa Point2D ? Int(sz.y[]) : _SCROLL_FALLBACK_HEIGHT
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

function read_intent(p::WidgetScrollPaneToGraphicsViewport, iomap::WidgetScrollPaneToGraphicsViewportIoMap, evt)
    if evt isa MouseScroll
        mx, my = evt.x, evt.y
        hit_element_at(iomap.output, mx, my) === nothing && return nothing
        _, scroll_step = p.measure("M", p.font)
        if evt.dx != 0 && evt.dy == 0
            return _scroll_by(iomap.input, -evt.dx * scroll_step, 0)
        else
            return _scroll_by(iomap.input, 0, -evt.dy * scroll_step)
        end
    end
    content_iomap = iomap.content_iomap
    content_iomap === nothing && return nothing
    # Translate pointer coordinates into the scrolled content's frame for any
    # event carrying coords. The viewport is drawn at (bx, by); the inner
    # canvas inside it is offset by (-scroll_x, -scroll_y), so an element at
    # content (cx, cy) renders at viewport (bx + cx - sx, by + cy - sy). To
    # invert: content_x = (evt.x - bx) + sx, content_y = (evt.y - by) + sy.
    # MouseScroll is intercepted above so the inner pipeline never sees it.
    w = iomap.input
    pos = w.position
    bx = pos isa Point2D ? _sc(Int(pos.x[])) : 0
    by = pos isa Point2D ? _sc(Int(pos.y[])) : 0
    sp = getfield(w, :scroll_position)[]::Point2D
    sx, sy = Int(sp.x[]), Int(sp.y[])
    translated = @event_case evt begin
        MousePress(button, x, y) => MousePress(button, x - bx + sx, y - by + sy, evt.count, evt.modifiers)
        MouseDown(button, x, y)  => MouseDown(button, x - bx + sx, y - by + sy, evt.modifiers)
        MouseUp(button, x, y)    => MouseUp(button, x - bx + sx, y - by + sy, evt.modifiers)
        MouseMove(x, y)          => MouseMove(x - bx + sx, y - by + sy, evt.buttons, evt.modifiers)
        _ => evt
    end
    op = read_intent(content_iomap.projection, content_iomap, translated)
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
