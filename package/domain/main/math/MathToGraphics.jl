"""
    MathToGraphicsModule

Math → `GraphicsCanvas`: the **two-dimensional** form of a formula. A fraction
gets a horizontal rule with the numerator centered above it, a sum gets its
limits above and below the sign, an exponent rises off the baseline, and a
delimiter grows with what it holds.

The slice typesets its own boxes. A formula is not a row of aligned widgets:
every part has a width, an ascent above the baseline and a descent below it, and
its parent places it from those three numbers. The generic layouts align by top,
center or bottom, which cannot put a fraction on the baseline of the row that
holds it, so this module places its children itself and wraps them in a
`GraphicsCanvas` — the way `LayoutToGraphics` does internally.

Every rule answers a [`MathIoMap`](@ref), which carries the three numbers as
reactive cells beside the usual projection/input/output. A parent reads its
children's cells to place them. `GridLayoutIoMap` is the precedent: an IO map
may publish geometry so that a parent can place and decorate its child.

The glyphs come from one family, DejaVu, which is the only vendored font that
carries the whole math set — the signs, the Greek letters, the arrows and the
delimiter extension pieces. A variable is set in the oblique face, everything
else in the upright one, all in one ink color, the way a formula is printed.
"""
module MathToGraphicsModule

import ..CellModule: Cell, ComputedCell
import ..CollectionModule: CellVector, ComputedCellVector
import ..DocumentApiModule: Document
import ..ProjectionApiModule: print_document, print_child, read_intent,
                              map_reference_forward, map_reference_backward, Projection
import ..IoMapModule: SimpleIoMap, IoMap, var"@iomap"
import ..GraphicsModule: GraphicsCanvas, GraphicsDocument, GraphicsText, GraphicsRect,
                         graphics_size, layout_none
import ..FontModule: StyleFont, make_style_font,
                     font_dejavu_sans_regular_20, font_dejavu_sans_italic_20
import ..TrueTypeModule: font_ascent, font_descent, font_line_height, font_x_height,
                         font_glyph_bounds, truetype_measure_text
import ..ColorModule: StyleColor, color_default, color_solarized_gray
import ..MathModule: MathDocument, MathInsertion, MathVariable, MathSymbol, MathText,
                     MathSpace, MathRow, MathBinaryOperation, MathUnaryOperation,
                     MathAssignment, MathParenthesized, MathFraction, MathScript,
                     MathRadical, MathBigOperator, MathDifferential, MathDerivative,
                     MathFunction, MathAccent, MathMatrix, MathCase, MathCases,
                     math_operator_glyph, math_operator_class, math_symbol_glyph,
                     math_big_operator_glyph, math_big_operator_is_text,
                     math_delimiter_strings, math_accent_is_wide
import ..PrimitiveModule: PrimitiveNumber, PrimitiveString
import ..TypeDispatchingProjectionModule: TypeDispatchingProjection
import ..PrinterContextModule: make_child_context, with_property, get_property
import ..ReferenceBuilderModule: var"@reference_step"

export MathIoMap, MathConfig, MathMetrics, math_metrics, MathToGraphics,
       MathVariableToGraphics, MathSymbolToGraphics, MathTextToGraphics,
       MathSpaceToGraphics, MathInsertionToGraphics, MathNumberToGraphics,
       MathRowToGraphics, MathBinaryOperationToGraphics,
       MathUnaryOperationToGraphics, MathAssignmentToGraphics,
       MathParenthesizedToGraphics, MathFractionToGraphics, MathScriptToGraphics,
       MathRadicalToGraphics, MathBigOperatorToGraphics,
       MathDifferentialToGraphics, MathDerivativeToGraphics,
       MathFunctionToGraphics, MathAccentToGraphics, MathMatrixToGraphics,
       MathCaseToGraphics, MathCasesToGraphics

# ════════════════════════════════════════════════════════════════════════════
# The box protocol
# ════════════════════════════════════════════════════════════════════════════

"""
    MathIoMap

The IO map every math rule answers. Beside the usual four fields it publishes
the box: `width`, `ascent` (top of the box down to the baseline) and `descent`
(baseline down to the bottom). A parent reads those three cells to place the
child, so a change in one leaf re-derives only the boxes above it.
"""
@iomap struct MathIoMap
    projection::Any
    input::Any
    output::Any
    child_iomaps::Cell
    width::Cell
    ascent::Cell
    descent::Cell
end

"""
    MathGlyphBox

A box the projection introduces rather than one a child document produces: an
operator sign, a delimiter, a fraction rule. It answers the same three metrics
as a `MathIoMap`, so a row can hold both kinds, but it is no child and carries
no reference.
"""
struct MathGlyphBox
    output::GraphicsDocument
    width::Cell
    ascent::Cell
    descent::Cell
end

# The three metrics of anything a parent can place. A foreign box (a document
# from another domain, rendered through the outer recursion) reports no
# baseline, so it centers on the axis — which is what an unknown box wants.
_box_width(b::Union{MathIoMap, MathGlyphBox}, m) = Int(b.width[])
_box_ascent(b::Union{MathIoMap, MathGlyphBox}, m) = Int(b.ascent[])
_box_descent(b::Union{MathIoMap, MathGlyphBox}, m) = Int(b.descent[])

_box_width(b, m) = _foreign_size(b)[1]
_box_ascent(b, m) = (h = _foreign_size(b)[2]; (h + 1) ÷ 2 + m.axis)
_box_descent(b, m) = (h = _foreign_size(b)[2]; max(0, h - _box_ascent(b, m)))

function _foreign_size(b)
    output = b.output
    output isa GraphicsCanvas && return (Int(output.w[]), Int(output.h[]))
    output isa GraphicsDocument && return graphics_size(output)
    (0, 0)
end

_box_output(b::MathGlyphBox) = b.output
_box_output(b) = b.output

# ════════════════════════════════════════════════════════════════════════════
# Configuration and metrics
# ════════════════════════════════════════════════════════════════════════════

"""
    MathConfig(; font, slanted, measure, ink, hint)

What every rule of one renderer shares: the two faces, the text measurer and the
two ink colors. One value is built by `MathToGraphics` and handed to each rule,
so a formula cannot end up half in one font and half in another.
"""
struct MathConfig
    font::StyleFont        # upright: numbers, operators, function names, symbols
    slanted::StyleFont     # oblique: variables
    measure::Function      # (text, font) -> (width, height)
    ink::StyleColor
    hint::StyleColor
end

MathConfig(; font::StyleFont = font_dejavu_sans_regular_20,
             slanted::StyleFont = font_dejavu_sans_italic_20,
             measure::Function = truetype_measure_text,
             ink::StyleColor = color_default,
             hint::StyleColor = color_solarized_gray) =
    MathConfig(font, slanted, measure, ink, hint)

"""
    MathMetrics

Every number the placement rules use, derived from one font at one style level.
Tune math here and nowhere else.

- `axis` — half the x height. A fraction rule, a large operator and a delimiter
  all center on it, which is what keeps `a/b + c` reading as one line.
- `rule` — the thickness of a fraction rule, a radical bar and an accent bar.
- `thin` / `medium` / `thick` — the space of the three operator classes.
"""
struct MathMetrics
    style::Symbol
    upright::StyleFont
    slanted::StyleFont
    size::Int
    ascent::Int
    descent::Int
    x_height::Int
    axis::Int
    rule::Int
    thin::Int
    medium::Int
    thick::Int
end

# TeX's four styles and the two size steps between them.
_script_factor(style::Symbol) =
    style === :script ? 0.7 : style === :scriptscript ? 0.5 : 1.0

# The style a script, a limit or an index is set in.
_script_style(style::Symbol) =
    style === :display || style === :text ? :script : :scriptscript

# The style a fraction sets its numerator and denominator in.
_fraction_style(style::Symbol) =
    style === :display ? :text : _script_style(style)

_scaled(font::StyleFont, size::Integer) =
    size == font.size ? font : make_style_font(font.filename, size)

"""
    math_metrics(config, style) -> MathMetrics

The numbers for one style level. Call it **inside** a computed cell: it reads
the font zoom, so a formula relayouts when the user zooms.
"""
function math_metrics(c::MathConfig, style::Symbol)
    size = max(6, round(Int, c.font.size * _script_factor(style)))
    upright = _scaled(c.font, size)
    slanted = _scaled(c.slanted, size)
    x_height = font_x_height(upright)
    MathMetrics(style, upright, slanted, size,
                font_ascent(upright), font_descent(upright), x_height,
                x_height ÷ 2,
                max(1, round(Int, size / 18)),
                max(1, size ÷ 6), max(1, size ÷ 4), max(1, size ÷ 3))
end

# How much space a gap asks for, in pixels. A gap is named either by the class
# of the operator that follows it (`:relation`, `:binary`, `:punctuation`) or by
# its own size (`:thin`, `:medium`, `:thick`); one table answers both, so a rule
# may say whichever it means.
function _class_space(gap::Symbol, m::MathMetrics)
    (gap === :relation || gap === :thick) && return m.thick
    (gap === :binary || gap === :medium) && return m.medium
    (gap === :punctuation || gap === :thin) && return m.thin
    gap === :quad && return m.size
    0
end

# ════════════════════════════════════════════════════════════════════════════
# Element and box builders
# ════════════════════════════════════════════════════════════════════════════

_int32(f) = ComputedCell(() -> Int32(f()))

# One run of text. `x`/`y` are the top-left of its box, relative to the canvas
# that holds it; a backend draws a glyph box from its top, so the baseline sits
# `font_ascent` below `y`.
_text_element(text, font, color::StyleColor, x = () -> 0, y = () -> 0) =
    GraphicsText(ComputedCell(text), _int32(x), _int32(y), ComputedCell(font),
                 Cell(color), Cell(nothing))

# A filled rule: a fraction bar, a radical bar, an accent bar, a caret.
_rule_element(x, y, w, h, color::StyleColor) =
    GraphicsRect(_int32(x), _int32(y), _int32(w), _int32(h), Cell(color),
                 Cell(Int32(0)), Cell(Int32(0)), Cell(Int32(0)), Cell(Int32(0)),
                 Cell(Int32(0)), Cell(StyleColor(0.0, 0.0, 0.0, 0.0)), Cell(nothing))

# An outlined rule: the placeholder box of an empty slot.
_outline_element(x, y, w, h, color::StyleColor) =
    GraphicsRect(_int32(x), _int32(y), _int32(w), _int32(h),
                 Cell(StyleColor(0.0, 0.0, 0.0, 0.0)),
                 Cell(Int32(2)), Cell(Int32(2)), Cell(Int32(2)), Cell(Int32(2)),
                 Cell(Int32(1)), Cell(color), Cell(nothing))

# Put one already-built graphic at `(x, y)` inside its parent. The wrapper is
# the same trick the layouts use: the child keeps its own coordinates at the
# origin and the wrapper carries the position.
_place(child::GraphicsDocument, x::Cell, y::Cell) =
    GraphicsCanvas(x, y, Cell(Int32(0)), Cell(Int32(0)),
                   CellVector(Cell[Cell(child)]), layout_none, true, Cell(nothing))

"""
    _glyph_box(config, text, font, color) -> MathGlyphBox

A box holding one run of introduced text. Its width comes from the measurer and
its ascent and descent from the font, so it sits on the same baseline as a leaf.
"""
function _glyph_box(c::MathConfig, text::Function, font::Function,
                    color::StyleColor = c.ink)
    MathGlyphBox(_text_element(text, font, color),
                 ComputedCell(() -> c.measure(text(), font())[1]),
                 ComputedCell(() -> font_ascent(font())),
                 ComputedCell(() -> font_descent(font())))
end

"""
    _build(elements, width, ascent, descent, children) -> NamedTuple

What every rule's build cell answers: the placed graphics, the three metric
cells, and the child IO maps in document order (for the reference maps).
"""
_build(elements, width, ascent, descent, children) =
    (elements = elements, width = width, ascent = ascent, descent = descent,
     children = children)

"""
    _math_iomap(p, doc, build) -> MathIoMap

Wrap a build cell in the canvas and the IO map. The canvas extent reads the
build's own metric cells, so a leaf that grows widens every box above it without
re-printing anything.
"""
function _math_iomap(p, doc, build::Cell)
    canvas = GraphicsCanvas(Cell(Int32(0)), Cell(Int32(0)),
                            _int32(() -> build[].width[]),
                            _int32(() -> build[].ascent[] + build[].descent[]),
                            ComputedCellVector(() -> build[].elements),
                            layout_none, true, Cell(nothing))
    MathIoMap(p, doc, canvas,
              ComputedCell(() -> build[].children),
              ComputedCell(() -> build[].width[]),
              ComputedCell(() -> build[].ascent[]),
              ComputedCell(() -> build[].descent[]))
end

"""
    _row(boxes, spaces, config, style) -> NamedTuple

Place `boxes` left to right on one baseline. `spaces` gives the gap before each
box as a class symbol (`:none`, `:thin`, `:medium`, `:thick`), resolved against
the metrics so a font zoom moves them.
"""
function _row(boxes::Vector, spaces::Vector{Symbol}, c::MathConfig, style::Symbol,
              children = Any[])
    ascent = ComputedCell(function ()
        m = math_metrics(c, style)
        a = 0
        for b in boxes
            a = max(a, _box_ascent(b, m))
        end
        a
    end)
    descent = ComputedCell(function ()
        m = math_metrics(c, style)
        d = 0
        for b in boxes
            d = max(d, _box_descent(b, m))
        end
        d
    end)
    width = ComputedCell(function ()
        m = math_metrics(c, style)
        w = 0
        for (i, b) in enumerate(boxes)
            w += _class_space(spaces[i], m) + _box_width(b, m)
        end
        w
    end)
    elements = Any[]
    for i in eachindex(boxes)
        x = ComputedCell(function ()
            m = math_metrics(c, style)
            at = 0
            for j in 1:i
                at += _class_space(spaces[j], m)
                j < i && (at += _box_width(boxes[j], m))
            end
            Int32(at)
        end)
        y = ComputedCell(function ()
            m = math_metrics(c, style)
            Int32(ascent[] - _box_ascent(boxes[i], m))
        end)
        push!(elements, _place(_box_output(boxes[i]), x, y))
    end
    _build(elements, width, ascent, descent, children)
end

# ── The style level ─────────────────────────────────────────────────────────
#
# A script is set smaller than its base, and a script inside a script smaller
# again. The recursion table is one table, so the level cannot live in the rule
# instance: it rides in the printer context, and a rule that changes it says so
# with `_with_style`. `p.style` is only the level a root print starts at.

_style_of(p, ctx) = get_property(ctx, :math_style, p.style)
_with_style(ctx, style::Symbol) = with_property(ctx, :math_style, style)

# Print one child document and answer its IO map. A child of another domain goes
# through the same recursion, so a formula may hold anything the outer renderer
# can draw.
_print_math_child(recursion, doc, ctx) =
    recursion === nothing ? SimpleIoMap(nothing, doc, doc) : print_child(recursion, doc, ctx)

# ════════════════════════════════════════════════════════════════════════════
# Leaves
# ════════════════════════════════════════════════════════════════════════════

# Each rule holds the shared configuration and the style level it prints at, so
# a script's children are the same rules at a smaller size.
struct MathVariableToGraphics <: Projection
    config::MathConfig
    style::Symbol
end
MathVariableToGraphics(c::MathConfig) = MathVariableToGraphics(c, :display)

# A leaf box: one run of text, the whole box.
function _leaf_iomap(p, doc, text::Function, font::Function, color::StyleColor,
                     c::MathConfig)
    build = ComputedCell(function ()
        element = _text_element(text, font, color)
        _build(Any[element],
               ComputedCell(() -> c.measure(text(), font())[1]),
               ComputedCell(() -> font_ascent(font())),
               ComputedCell(() -> font_descent(font())),
               Any[])
    end)
    _math_iomap(p, doc, build)
end

function print_document(p::MathVariableToGraphics, recursion, doc::MathVariable, ctx)
    style = _style_of(p, ctx)
    _leaf_iomap(p, doc, () -> doc.name,
                () -> math_metrics(p.config, style).slanted, p.config.ink, p.config)
end

struct MathSymbolToGraphics <: Projection
    config::MathConfig
    style::Symbol
end
MathSymbolToGraphics(c::MathConfig) = MathSymbolToGraphics(c, :display)

# A lowercase Greek letter is a variable in disguise and is set slanted; a sign,
# an arrow and a capital Greek letter stay upright — the convention every
# printed formula follows.
function _symbol_font(name::Symbol, m::MathMetrics)
    glyph = math_symbol_glyph(name)
    if length(glyph) == 1
        point = UInt32(first(glyph))
        0x3B1 <= point <= 0x3C9 && return m.slanted
    end
    m.upright
end

function print_document(p::MathSymbolToGraphics, recursion, doc::MathSymbol, ctx)
    style = _style_of(p, ctx)
    _leaf_iomap(p, doc, () -> math_symbol_glyph(doc.name),
                () -> _symbol_font(doc.name, math_metrics(p.config, style)),
                p.config.ink, p.config)
end

struct MathTextToGraphics <: Projection
    config::MathConfig
    style::Symbol
end
MathTextToGraphics(c::MathConfig) = MathTextToGraphics(c, :display)

function print_document(p::MathTextToGraphics, recursion, doc::MathText, ctx)
    style = _style_of(p, ctx)
    _leaf_iomap(p, doc, () -> doc.content,
                () -> math_metrics(p.config, style).upright, p.config.ink, p.config)
end

struct MathNumberToGraphics <: Projection
    config::MathConfig
    style::Symbol
end
MathNumberToGraphics(c::MathConfig) = MathNumberToGraphics(c, :display)

function print_document(p::MathNumberToGraphics, recursion, doc::PrimitiveNumber, ctx)
    style = _style_of(p, ctx)
    _leaf_iomap(p, doc, () -> string(doc.value),
                () -> math_metrics(p.config, style).upright, p.config.ink, p.config)
end

function print_document(p::MathNumberToGraphics, recursion, doc::PrimitiveString, ctx)
    style = _style_of(p, ctx)
    _leaf_iomap(p, doc, () -> string(doc.value),
                () -> math_metrics(p.config, style).upright, p.config.ink, p.config)
end

struct MathSpaceToGraphics <: Projection
    config::MathConfig
    style::Symbol
end
MathSpaceToGraphics(c::MathConfig) = MathSpaceToGraphics(c, :display)

function print_document(p::MathSpaceToGraphics, recursion, doc::MathSpace, ctx)
    style = _style_of(p, ctx)
    c = p.config
    build = ComputedCell(function ()
        width = ComputedCell(function ()
            m = math_metrics(c, style)
            doc.kind === :medium ? m.medium :
            doc.kind === :thick ? m.thick :
            doc.kind === :quad ? m.size : m.thin
        end)
        _build(Any[], width, Cell(0), Cell(0), Any[])
    end)
    _math_iomap(p, doc, build)
end

struct MathInsertionToGraphics <: Projection
    config::MathConfig
    style::Symbol
end
MathInsertionToGraphics(c::MathConfig) = MathInsertionToGraphics(c, :display)

# An empty slot is a box a reader can see and a mouse can hit — an invisible
# slot is a slot nobody can fill.
function print_document(p::MathInsertionToGraphics, recursion, doc::MathInsertion, ctx)
    style = _style_of(p, ctx)
    c = p.config
    build = ComputedCell(function ()
        width = ComputedCell(() -> max(4, math_metrics(c, style).x_height))
        ascent = ComputedCell(() -> math_metrics(c, style).x_height)
        element = _outline_element(() -> 0, () -> 0, () -> width[], () -> ascent[], c.hint)
        _build(Any[element], width, ascent, Cell(0), Any[])
    end)
    _math_iomap(p, doc, build)
end

# ════════════════════════════════════════════════════════════════════════════
# Sequences
# ════════════════════════════════════════════════════════════════════════════

struct MathRowToGraphics <: Projection
    config::MathConfig
    style::Symbol
end
MathRowToGraphics(c::MathConfig) = MathRowToGraphics(c, :display)

function print_document(p::MathRowToGraphics, recursion, doc::MathRow, ctx)
    style = _style_of(p, ctx)
    c = p.config
    build = ComputedCell(function ()
        children = Any[]
        for i in 1:length(doc.elements)
            cctx = make_child_context(ctx, doc, (@reference_step elements), (@reference_step [i]))
            push!(children, _print_math_child(recursion, doc.elements[i], cctx))
        end
        # Juxtaposition is not glue: `k T B` needs a hair of space, and the
        # first element needs none.
        spaces = Symbol[i == 1 ? :none : :thin for i in eachindex(children)]
        row = _row(children, spaces, c, style, children)
        row
    end)
    _math_iomap(p, doc, build)
end

struct MathBinaryOperationToGraphics <: Projection
    config::MathConfig
    style::Symbol
end
MathBinaryOperationToGraphics(c::MathConfig) = MathBinaryOperationToGraphics(c, :display)

function print_document(p::MathBinaryOperationToGraphics, recursion, doc::MathBinaryOperation, ctx)
    style = _style_of(p, ctx)
    c = p.config
    build = ComputedCell(function ()
        left_ctx = make_child_context(ctx, doc, @reference_step left)
        right_ctx = make_child_context(ctx, doc, @reference_step right)
        left = _print_math_child(recursion, doc.left, left_ctx)
        right = _print_math_child(recursion, doc.right, right_ctx)
        sign = _glyph_box(c, () -> math_operator_glyph(doc.operator),
                          () -> math_metrics(c, style).upright)
        space = math_operator_class(doc.operator)
        _row(Any[left, sign, right], Symbol[:none, space, space], c, style,
             Any[left, right])
    end)
    _math_iomap(p, doc, build)
end

struct MathUnaryOperationToGraphics <: Projection
    config::MathConfig
    style::Symbol
end
MathUnaryOperationToGraphics(c::MathConfig) = MathUnaryOperationToGraphics(c, :display)

function print_document(p::MathUnaryOperationToGraphics, recursion, doc::MathUnaryOperation, ctx)
    style = _style_of(p, ctx)
    c = p.config
    build = ComputedCell(function ()
        operand_ctx = make_child_context(ctx, doc, @reference_step operand)
        operand = _print_math_child(recursion, doc.operand, operand_ctx)
        sign = _glyph_box(c, () -> math_operator_glyph(doc.operator),
                          () -> math_metrics(c, style).upright)
        # A sign that binds to one operand takes no space: `−x`, `n!`.
        boxes = doc.postfix ? Any[operand, sign] : Any[sign, operand]
        _row(boxes, Symbol[:none, :none], c, style, Any[operand])
    end)
    _math_iomap(p, doc, build)
end

struct MathAssignmentToGraphics <: Projection
    config::MathConfig
    style::Symbol
end
MathAssignmentToGraphics(c::MathConfig) = MathAssignmentToGraphics(c, :display)

function print_document(p::MathAssignmentToGraphics, recursion, doc::MathAssignment, ctx)
    style = _style_of(p, ctx)
    c = p.config
    build = ComputedCell(function ()
        target_ctx = make_child_context(ctx, doc, @reference_step target)
        value_ctx = make_child_context(ctx, doc, @reference_step value)
        target = _print_math_child(recursion, doc.target, target_ctx)
        value = _print_math_child(recursion, doc.value, value_ctx)
        sign = _glyph_box(c, () -> "=", () -> math_metrics(c, style).upright)
        _row(Any[target, sign, value], Symbol[:none, :relation, :relation], c, style,
             Any[target, value])
    end)
    _math_iomap(p, doc, build)
end

# ════════════════════════════════════════════════════════════════════════════
# Delimiters
# ════════════════════════════════════════════════════════════════════════════

# The three pieces a tall delimiter is tiled from: top, extension, bottom, and
# for a brace the middle joint. The code points exist for exactly this purpose
# and DejaVu carries them all.
const _DELIMITER_PIECES = Dict{Tuple{Symbol, Symbol}, NTuple{4, Char}}(
    (:parenthesis, :open)  => ('⎛', '⎜', '⎝', '\0'),
    (:parenthesis, :close) => ('⎞', '⎟', '⎠', '\0'),
    (:bracket, :open)      => ('⎡', '⎢', '⎣', '\0'),
    (:bracket, :close)     => ('⎤', '⎥', '⎦', '\0'),
    (:brace, :open)        => ('⎧', '⎪', '⎩', '⎨'),
    (:brace, :close)       => ('⎫', '⎪', '⎭', '⎬'),
)

# Above this multiple of the base line height a scaled glyph turns fat, so the
# delimiter is tiled from its pieces instead.
const _DELIMITER_SCALE_LIMIT = 1.6

"""
    _delimiter_box(config, style, kind, side, half) -> MathGlyphBox

A delimiter that covers `2 * half` pixels, centered on the axis. Under the scale
limit it is one glyph at a larger size; above it, the Unicode pieces tiled by
their ink. `half` is a thunk, so the delimiter grows when its content does.
"""
function _delimiter_box(c::MathConfig, style::Symbol, kind::Symbol, side::Symbol,
                        half::Function)
    glyph = side === :open ? math_delimiter_strings(kind)[1] : math_delimiter_strings(kind)[2]
    pieces = get(_DELIMITER_PIECES, (kind, side), nothing)

    # The scale one glyph needs to cover the height, and the font it lands at.
    scale = () -> begin
        m = math_metrics(c, style)
        base = max(1, font_line_height(m.upright))
        max(1.0, 2 * half() / base)
    end
    scaled_font = () -> begin
        m = math_metrics(c, style)
        _scaled(m.upright, max(1, round(Int, m.size * scale())))
    end
    tiled = () -> pieces !== nothing && scale() > _DELIMITER_SCALE_LIMIT

    width = ComputedCell(function ()
        m = math_metrics(c, style)
        isempty(glyph) && return 0
        tiled() ? c.measure(string(pieces[1]), m.upright)[1] :
                  c.measure(glyph, scaled_font())[1]
    end)
    ascent = ComputedCell(() -> math_metrics(c, style).axis + half())
    descent = ComputedCell(() -> max(0, half() - math_metrics(c, style).axis))

    output = GraphicsCanvas(Cell(Int32(0)), Cell(Int32(0)),
                            _int32(() -> width[]),
                            _int32(() -> ascent[] + descent[]),
                            ComputedCellVector(function ()
                                isempty(glyph) && return Any[]
                                tiled() ? _tiled_delimiter(c, style, pieces, half) :
                                          Any[_text_element(() -> glyph, scaled_font, c.ink)]
                            end),
                            layout_none, true, Cell(nothing))
    MathGlyphBox(output, width, ascent, descent)
end

# Tile a delimiter out of its pieces. Each piece is placed by its *ink*: a
# backend draws a glyph box from its top, so a piece whose ink top must land at
# `top` is drawn at `top - ascent + ymax`.
function _tiled_delimiter(c::MathConfig, style::Symbol, pieces::NTuple{4, Char},
                          half::Function)
    m = math_metrics(c, style)
    font = m.upright
    ascent = font_ascent(font)
    height = 2 * half()

    top_piece, extension, bottom_piece, middle = pieces
    _ink(ch) = (b = font_glyph_bounds(font, ch); (b[2] - b[1], b[2]))

    top_h, top_max = _ink(top_piece)
    bottom_h, bottom_max = _ink(bottom_piece)
    ext_h, ext_max = _ink(extension)
    has_middle = middle != '\0'
    middle_h, middle_max = has_middle ? _ink(middle) : (0, 0)

    elements = Any[]
    _draw(ch, ink_top, ymax) =
        push!(elements, _text_element(() -> string(ch), () -> font, c.ink,
                                      () -> 0, () -> ink_top - ascent + ymax))

    _draw(top_piece, 0, top_max)
    _draw(bottom_piece, height - bottom_h, bottom_max)

    if has_middle
        middle_top = (height - middle_h) ÷ 2
        _draw(middle, middle_top, middle_max)
        _fill_extension(_draw, extension, ext_h, ext_max, top_h, middle_top)
        _fill_extension(_draw, extension, ext_h, ext_max, middle_top + middle_h,
                        height - bottom_h)
    else
        _fill_extension(_draw, extension, ext_h, ext_max, top_h, height - bottom_h)
    end
    elements
end

# Fill `[from, to)` with extension pieces. The pieces overlap rather than abut:
# a step shorter than the ink leaves no hairline between them.
function _fill_extension(draw::Function, extension::Char, ext_h::Int, ext_max::Int,
                         from::Int, to::Int)
    gap = to - from
    (gap <= 0 || ext_h <= 0) && return
    count = max(1, ceil(Int, gap / ext_h))
    step = gap / count
    for k in 0:(count - 1)
        draw(extension, from + round(Int, k * step), ext_max)
    end
end

struct MathParenthesizedToGraphics <: Projection
    config::MathConfig
    style::Symbol
end
MathParenthesizedToGraphics(c::MathConfig) = MathParenthesizedToGraphics(c, :display)

function print_document(p::MathParenthesizedToGraphics, recursion, doc::MathParenthesized, ctx)
    style = _style_of(p, ctx)
    c = p.config
    build = ComputedCell(function ()
        content_ctx = make_child_context(ctx, doc, @reference_step content)
        content = _print_math_child(recursion, doc.content, content_ctx)
        # A delimiter covers its content symmetrically about the axis, plus a
        # little air, so `(1)` and `(a/b)` both look deliberate.
        half = function ()
            m = math_metrics(c, style)
            reach = max(_box_ascent(content, m) - m.axis, _box_descent(content, m) + m.axis)
            reach + m.rule
        end
        open = _delimiter_box(c, style, doc.kind, :open, half)
        close = _delimiter_box(c, style, doc.kind, :close, half)
        _row(Any[open, content, close], Symbol[:none, :none, :none], c, style,
             Any[content])
    end)
    _math_iomap(p, doc, build)
end

# ════════════════════════════════════════════════════════════════════════════
# Fraction
# ════════════════════════════════════════════════════════════════════════════

struct MathFractionToGraphics <: Projection
    config::MathConfig
    style::Symbol
end
MathFractionToGraphics(c::MathConfig) = MathFractionToGraphics(c, :display)

function print_document(p::MathFractionToGraphics, recursion, doc::MathFraction, ctx)
    style = _style_of(p, ctx)
    c = p.config
    build = ComputedCell(function ()
        inner = _fraction_style(style)
        numerator_ctx = _with_style(make_child_context(ctx, doc, @reference_step numerator), inner)
        denominator_ctx = _with_style(make_child_context(ctx, doc, @reference_step denominator), inner)
        numerator = _print_math_child(recursion, doc.numerator, numerator_ctx)
        denominator = _print_math_child(recursion, doc.denominator, denominator_ctx)

        metrics = () -> math_metrics(c, inner)
        gap = () -> (m = metrics(); style === :display ? 3 * m.rule : m.rule)
        pad = () -> metrics().thin

        width = ComputedCell(function ()
            m = metrics()
            max(_box_width(numerator, m), _box_width(denominator, m)) + 2 * pad()
        end)
        # The rule sits on the axis; the box reaches from the top of the
        # numerator to the bottom of the denominator.
        ascent = ComputedCell(function ()
            m = math_metrics(c, style)
            im = metrics()
            m.axis + m.rule + gap() + _box_ascent(numerator, im) + _box_descent(numerator, im)
        end)
        descent = ComputedCell(function ()
            m = math_metrics(c, style)
            im = metrics()
            gap() - m.axis + _box_ascent(denominator, im) + _box_descent(denominator, im)
        end)

        rule_y = ComputedCell(() -> Int32(ascent[] - math_metrics(c, style).axis -
                                          math_metrics(c, style).rule))
        elements = Any[]
        for (box, above) in ((numerator, true), (denominator, false))
            x = ComputedCell(function ()
                m = metrics()
                Int32((width[] - _box_width(box, m)) ÷ 2)
            end)
            y = ComputedCell(function ()
                m = metrics()
                above ? Int32(rule_y[] - gap() - _box_ascent(box, m) - _box_descent(box, m)) :
                        Int32(rule_y[] + math_metrics(c, style).rule + gap())
            end)
            push!(elements, _place(_box_output(box), x, y))
        end
        push!(elements, _rule_element(() -> 0, () -> rule_y[], () -> width[],
                                      () -> math_metrics(c, style).rule, c.ink))
        _build(elements, width, ascent, descent, Any[numerator, denominator])
    end)
    _math_iomap(p, doc, build)
end

# ════════════════════════════════════════════════════════════════════════════
# Scripts
# ════════════════════════════════════════════════════════════════════════════

struct MathScriptToGraphics <: Projection
    config::MathConfig
    style::Symbol
end
MathScriptToGraphics(c::MathConfig) = MathScriptToGraphics(c, :display)

function print_document(p::MathScriptToGraphics, recursion, doc::MathScript, ctx)
    style = _style_of(p, ctx)
    c = p.config
    build = ComputedCell(function ()
        inner = _script_style(style)
        base_ctx = make_child_context(ctx, doc, @reference_step base)
        base = _print_math_child(recursion, doc.base, base_ctx)
        subscript = doc.subscript === nothing ? nothing :
            _print_math_child(recursion, doc.subscript,
                              _with_style(make_child_context(ctx, doc, @reference_step subscript), inner))
        superscript = doc.superscript === nothing ? nothing :
            _print_math_child(recursion, doc.superscript,
                              _with_style(make_child_context(ctx, doc, @reference_step superscript), inner))

        metrics = () -> math_metrics(c, style)
        inner_metrics = () -> math_metrics(c, inner)
        # How far each script's own baseline moves off the base's.
        up = ComputedCell(function ()
            superscript === nothing && return 0
            m = metrics()
            # The script's baseline rises by about a third of the em, and by
            # more when the base is tall enough to reach past that.
            max(round(Int, 0.36 * m.size), _box_ascent(base, m) - m.x_height)
        end)
        down = ComputedCell(function ()
            subscript === nothing && return 0
            m = metrics()
            # A shift of the script's *baseline*, not of its box: a fifth of the
            # em, and never less than the base's own descent.
            max(round(Int, 0.2 * m.size), _box_descent(base, m))
        end)
        # Two scripts must not collide: push them apart, equally, when they do.
        clearance = ComputedCell(function ()
            (subscript === nothing || superscript === nothing) && return 0
            m = metrics()
            im = inner_metrics()
            overlap = (_box_descent(superscript, im) + _box_ascent(subscript, im)) -
                      (up[] + down[]) + 4 * m.rule
            max(0, (overlap + 1) ÷ 2)
        end)

        script_width = ComputedCell(function ()
            im = inner_metrics()
            w = 0
            subscript === nothing || (w = max(w, _box_width(subscript, im)))
            superscript === nothing || (w = max(w, _box_width(superscript, im)))
            w
        end)
        width = ComputedCell(() -> _box_width(base, metrics()) + script_width[])
        ascent = ComputedCell(function ()
            m = metrics()
            im = inner_metrics()
            a = _box_ascent(base, m)
            superscript === nothing ? a :
                max(a, up[] + clearance[] + _box_ascent(superscript, im))
        end)
        descent = ComputedCell(function ()
            m = metrics()
            im = inner_metrics()
            d = _box_descent(base, m)
            subscript === nothing ? d :
                max(d, down[] + clearance[] + _box_descent(subscript, im))
        end)

        base_x = Cell(Int32(0))
        base_y = ComputedCell(() -> Int32(ascent[] - _box_ascent(base, metrics())))
        elements = Any[_place(_box_output(base), base_x, base_y)]
        script_x = ComputedCell(() -> Int32(_box_width(base, metrics())))
        if superscript !== nothing
            y = ComputedCell(function ()
                im = inner_metrics()
                Int32(ascent[] - up[] - clearance[] - _box_ascent(superscript, im))
            end)
            push!(elements, _place(_box_output(superscript), script_x, y))
        end
        if subscript !== nothing
            y = ComputedCell(function ()
                im = inner_metrics()
                Int32(ascent[] + down[] + clearance[] - _box_ascent(subscript, im))
            end)
            push!(elements, _place(_box_output(subscript), script_x, y))
        end
        children = Any[base]
        subscript === nothing || push!(children, subscript)
        superscript === nothing || push!(children, superscript)
        _build(elements, width, ascent, descent, children)
    end)
    _math_iomap(p, doc, build)
end

# ════════════════════════════════════════════════════════════════════════════
# Radical
# ════════════════════════════════════════════════════════════════════════════

struct MathRadicalToGraphics <: Projection
    config::MathConfig
    style::Symbol
end
MathRadicalToGraphics(c::MathConfig) = MathRadicalToGraphics(c, :display)

function print_document(p::MathRadicalToGraphics, recursion, doc::MathRadical, ctx)
    style = _style_of(p, ctx)
    c = p.config
    build = ComputedCell(function ()
        radicand_ctx = make_child_context(ctx, doc, @reference_step radicand)
        radicand = _print_math_child(recursion, doc.radicand, radicand_ctx)
        index = doc.index === nothing ? nothing :
            _print_math_child(recursion, doc.index,
                              _with_style(make_child_context(ctx, doc, @reference_step index), :scriptscript))

        metrics = () -> math_metrics(c, style)
        index_metrics = () -> math_metrics(c, :scriptscript)
        # The sign covers the radicand plus the bar and the air above it, so it
        # is scaled by its *ink*, not by its text box: a radical is one tall
        # stroke, and the box around it says little about where that stroke is.
        inner_height = () -> begin
            m = metrics()
            _box_ascent(radicand, m) + _box_descent(radicand, m) + 3 * m.rule
        end
        # The sign is scaled to reach, but only so far: this face has no
        # extensible radical, and a uniformly scaled one grows as wide as it is
        # tall. Past the cap the bar simply runs on above a sign that no longer
        # follows it — a real math font is the fix, not a wider glyph.
        sign_font = function ()
            m = metrics()
            low, high = font_glyph_bounds(m.upright, '√')
            ink = max(1, high - low)
            wanted = ceil(Int, m.size * inner_height() / ink)
            _scaled(m.upright, clamp(wanted, m.size, round(Int, 2.2 * m.size)))
        end
        sign_width = ComputedCell(() -> c.measure("√", sign_font())[1])
        index_width = ComputedCell(function ()
            index === nothing && return 0
            # The index sits over the sign's left arm, so only its overhang adds
            # to the width.
            max(0, _box_width(index, index_metrics()) - sign_width[] ÷ 2)
        end)

        ascent = ComputedCell(function ()
            m = metrics()
            a = _box_ascent(radicand, m) + 3 * m.rule
            index === nothing ? a :
                max(a, (_box_ascent(radicand, m) + _box_descent(radicand, m)) ÷ 2 +
                       _box_ascent(index, index_metrics()) +
                       _box_descent(index, index_metrics()))
        end)
        descent = ComputedCell(() -> _box_descent(radicand, metrics()))
        width = ComputedCell(() -> index_width[] + sign_width[] +
                                   _box_width(radicand, metrics()) + metrics().thin)

        # The bar runs from the top of the sign across the radicand.
        bar_y = ComputedCell(function ()
            m = metrics()
            Int32(ascent[] - _box_ascent(radicand, m) - 3 * m.rule)
        end)
        # A glyph is drawn from the top of its box, so a sign whose ink top must
        # land on the bar is drawn that far above it.
        sign_y = ComputedCell(function ()
            font = sign_font()
            Int32(bar_y[] - font_ascent(font) + font_glyph_bounds(font, '√')[2])
        end)
        elements = Any[]
        push!(elements, _text_element(() -> "√", sign_font, c.ink,
                                      () -> index_width[], () -> sign_y[]))
        push!(elements, _rule_element(() -> index_width[] + sign_width[] - metrics().rule,
                                      () -> bar_y[],
                                      () -> _box_width(radicand, metrics()) + metrics().thin +
                                            metrics().rule,
                                      () -> metrics().rule, c.ink))
        radicand_x = ComputedCell(() -> Int32(index_width[] + sign_width[]))
        radicand_y = ComputedCell(() -> Int32(ascent[] - _box_ascent(radicand, metrics())))
        push!(elements, _place(_box_output(radicand), radicand_x, radicand_y))
        children = Any[radicand]
        if index !== nothing
            index_y = ComputedCell(function ()
                im = index_metrics()
                Int32(max(0, ascent[] - (_box_ascent(radicand, metrics()) +
                                         _box_descent(radicand, metrics())) ÷ 2 -
                             _box_ascent(index, im) - _box_descent(index, im)))
            end)
            push!(elements, _place(_box_output(index), Cell(Int32(0)), index_y))
            push!(children, index)
        end
        _build(elements, width, ascent, descent, children)
    end)
    _math_iomap(p, doc, build)
end

# ════════════════════════════════════════════════════════════════════════════
# Large operators
# ════════════════════════════════════════════════════════════════════════════

struct MathBigOperatorToGraphics <: Projection
    config::MathConfig
    style::Symbol
end
MathBigOperatorToGraphics(c::MathConfig) = MathBigOperatorToGraphics(c, :display)

# Where the limits go. A sum in display style puts them above and below; an
# integral keeps them at its side, and so does everything in a script.
function _limit_placement(doc, style::Symbol)
    doc.limits === :under_over && return :under_over
    doc.limits === :side && return :side
    (style === :script || style === :scriptscript) && return :side
    operator = doc.operator
    (operator === :integral || operator === :double_integral ||
     operator === :triple_integral || operator === :contour_integral) && return :side
    style === :display ? :under_over : :side
end

function print_document(p::MathBigOperatorToGraphics, recursion, doc::MathBigOperator, ctx)
    style = _style_of(p, ctx)
    c = p.config
    build = ComputedCell(function ()
        inner = _script_style(style)
        body = _print_math_child(recursion, doc.body,
                                 make_child_context(ctx, doc, @reference_step body))
        lower = doc.lower === nothing ? nothing :
            _print_math_child(recursion, doc.lower,
                              _with_style(make_child_context(ctx, doc, @reference_step lower), inner))
        upper = doc.upper === nothing ? nothing :
            _print_math_child(recursion, doc.upper,
                              _with_style(make_child_context(ctx, doc, @reference_step upper), inner))

        metrics = () -> math_metrics(c, style)
        inner_metrics = () -> math_metrics(c, inner)
        placement = _limit_placement(doc, style)
        word = math_big_operator_is_text(doc.operator)
        glyph = math_big_operator_glyph(doc.operator)
        # A word operator (`lim`) keeps the text size; a sign is enlarged.
        sign_font = function ()
            m = metrics()
            word && return m.upright
            _scaled(m.upright, round(Int, m.size * (style === :display ? 1.8 : 1.2)))
        end
        sign_width = ComputedCell(() -> c.measure(glyph, sign_font())[1])
        # The sign centers on the axis, like every other tall thing — by its
        # *ink*, because a sign that is centered by its text box sits visibly
        # high. A word operator has no single ink to center, so it keeps its
        # own baseline.
        sign_ink = ComputedCell(function ()
            word && return (0, 0)
            font = sign_font()
            low, high = font_glyph_bounds(font, first(glyph))
            (low, high)
        end)
        sign_reach_up = ComputedCell(function ()
            m = metrics()
            word && return font_ascent(sign_font())
            low, high = sign_ink[]
            (high - low) ÷ 2 + m.axis
        end)
        sign_reach_down = ComputedCell(function ()
            word && return font_descent(sign_font())
            low, high = sign_ink[]
            (high - low) - sign_reach_up[]
        end)
        # Where to draw the sign so that its ink lands where the box says.
        sign_y = ComputedCell(function ()
            font = sign_font()
            word && return 0
            font_glyph_bounds(font, first(glyph))[2] - font_ascent(font)
        end)

        limit_width = ComputedCell(function ()
            im = inner_metrics()
            w = 0
            lower === nothing || (w = max(w, _box_width(lower, im)))
            upper === nothing || (w = max(w, _box_width(upper, im)))
            w
        end)
        limit_gap = () -> metrics().rule * 3

        if placement === :under_over
            head_width = ComputedCell(() -> max(sign_width[], limit_width[]))
            ascent = ComputedCell(function ()
                im = inner_metrics()
                a = sign_reach_up[]
                upper === nothing ? a :
                    a + limit_gap() + _box_ascent(upper, im) + _box_descent(upper, im)
            end)
            descent = ComputedCell(function ()
                im = inner_metrics()
                d = sign_reach_down[]
                lower === nothing ? d :
                    d + limit_gap() + _box_ascent(lower, im) + _box_descent(lower, im)
            end)
            width = ComputedCell(() -> head_width[] + metrics().thin +
                                       _box_width(body, metrics()))
            elements = Any[]
            push!(elements, _text_element(() -> glyph, sign_font, c.ink,
                                          () -> (head_width[] - sign_width[]) ÷ 2,
                                          () -> ascent[] - sign_reach_up[] + sign_y[]))
            if upper !== nothing
                x = ComputedCell(() -> Int32((head_width[] - _box_width(upper, inner_metrics())) ÷ 2))
                y = ComputedCell(function ()
                    im = inner_metrics()
                    Int32(ascent[] - sign_reach_up[] - limit_gap() -
                          _box_ascent(upper, im) - _box_descent(upper, im))
                end)
                push!(elements, _place(_box_output(upper), x, y))
            end
            if lower !== nothing
                x = ComputedCell(() -> Int32((head_width[] - _box_width(lower, inner_metrics())) ÷ 2))
                y = ComputedCell(() -> Int32(ascent[] + sign_reach_down[] + limit_gap()))
                push!(elements, _place(_box_output(lower), x, y))
            end
            body_x = ComputedCell(() -> Int32(head_width[] + metrics().thin))
            body_y = ComputedCell(() -> Int32(ascent[] - _box_ascent(body, metrics())))
            push!(elements, _place(_box_output(body), body_x, body_y))
        else
            # Side limits: a subscript and a superscript on the sign.
            ascent = ComputedCell(function ()
                im = inner_metrics()
                a = max(sign_reach_up[], _box_ascent(body, metrics()))
                upper === nothing ? a :
                    max(a, sign_reach_up[] - metrics().rule +
                           _box_ascent(upper, im) + _box_descent(upper, im))
            end)
            descent = ComputedCell(function ()
                im = inner_metrics()
                d = max(sign_reach_down[], _box_descent(body, metrics()))
                lower === nothing ? d :
                    max(d, sign_reach_down[] - metrics().rule +
                           _box_ascent(lower, im) + _box_descent(lower, im))
            end)
            width = ComputedCell(() -> sign_width[] + limit_width[] + metrics().thin +
                                       _box_width(body, metrics()))
            elements = Any[]
            push!(elements, _text_element(() -> glyph, sign_font, c.ink,
                                          () -> 0, () -> ascent[] - sign_reach_up[] + sign_y[]))
            if upper !== nothing
                y = ComputedCell(function ()
                    im = inner_metrics()
                    Int32(max(0, ascent[] - sign_reach_up[] + metrics().rule -
                                 _box_ascent(upper, im) - _box_descent(upper, im)))
                end)
                push!(elements, _place(_box_output(upper), ComputedCell(() -> Int32(sign_width[])), y))
            end
            if lower !== nothing
                y = ComputedCell(() -> Int32(ascent[] + sign_reach_down[] - metrics().rule))
                push!(elements, _place(_box_output(lower), ComputedCell(() -> Int32(sign_width[])), y))
            end
            body_x = ComputedCell(() -> Int32(sign_width[] + limit_width[] + metrics().thin))
            body_y = ComputedCell(() -> Int32(ascent[] - _box_ascent(body, metrics())))
            push!(elements, _place(_box_output(body), body_x, body_y))
        end

        children = Any[body]
        lower === nothing || push!(children, lower)
        upper === nothing || push!(children, upper)
        _build(elements, width, ascent, descent, children)
    end)
    _math_iomap(p, doc, build)
end

# ════════════════════════════════════════════════════════════════════════════
# Differential and derivative
# ════════════════════════════════════════════════════════════════════════════

struct MathDifferentialToGraphics <: Projection
    config::MathConfig
    style::Symbol
end
MathDifferentialToGraphics(c::MathConfig) = MathDifferentialToGraphics(c, :display)

_differential_glyph(kind::Symbol) = kind === :partial ? "∂" : "d"

function print_document(p::MathDifferentialToGraphics, recursion, doc::MathDifferential, ctx)
    style = _style_of(p, ctx)
    c = p.config
    build = ComputedCell(function ()
        variable = _print_math_child(recursion, doc.variable,
                                     make_child_context(ctx, doc, @reference_step variable))
        sign = _glyph_box(c, () -> _differential_glyph(doc.kind),
                          () -> math_metrics(c, style).upright)
        _row(Any[sign, variable], Symbol[:thin, :none], c, style, Any[variable])
    end)
    _math_iomap(p, doc, build)
end

struct MathDerivativeToGraphics <: Projection
    config::MathConfig
    style::Symbol
end
MathDerivativeToGraphics(c::MathConfig) = MathDerivativeToGraphics(c, :display)

# `dQ/dt` is a fraction whose parts the projection introduces, so it is built
# here rather than delegated: only `body` and `variable` are the document's.
function print_document(p::MathDerivativeToGraphics, recursion, doc::MathDerivative, ctx)
    style = _style_of(p, ctx)
    c = p.config
    build = ComputedCell(function ()
        inner = _fraction_style(style)
        body = _print_math_child(recursion, doc.body,
                                 _with_style(make_child_context(ctx, doc, @reference_step body), inner))
        variable = _print_math_child(recursion, doc.variable,
                                     _with_style(make_child_context(ctx, doc, @reference_step variable), inner))
        metrics = () -> math_metrics(c, style)
        inner_metrics = () -> math_metrics(c, inner)
        order_text = () -> doc.order == 1 ? "" : string(doc.order)
        sign = () -> _differential_glyph(doc.kind)

        sign_width = ComputedCell(() -> c.measure(sign(), inner_metrics().upright)[1])
        order_width = ComputedCell(function ()
            isempty(order_text()) && return 0
            c.measure(order_text(), math_metrics(c, :scriptscript).upright)[1]
        end)

        numerator_width = ComputedCell(() -> sign_width[] + order_width[] +
                                             _box_width(body, inner_metrics()))
        denominator_width = ComputedCell(() -> sign_width[] +
                                               _box_width(variable, inner_metrics()) +
                                               order_width[])
        pad = () -> metrics().thin
        width = ComputedCell(() -> max(numerator_width[], denominator_width[]) + 2 * pad())
        gap = () -> 3 * metrics().rule
        row_ascent(box) = _box_ascent(box, inner_metrics())
        row_height(box) = _box_ascent(box, inner_metrics()) + _box_descent(box, inner_metrics())
        line_height = () -> begin
            im = inner_metrics()
            font_ascent(im.upright) + font_descent(im.upright)
        end
        numerator_height = ComputedCell(() -> max(row_height(body), line_height()))
        denominator_height = ComputedCell(() -> max(row_height(variable), line_height()))
        ascent = ComputedCell(() -> metrics().axis + metrics().rule + gap() + numerator_height[])
        descent = ComputedCell(() -> gap() - metrics().axis + denominator_height[])
        rule_y = ComputedCell(() -> Int32(ascent[] - metrics().axis - metrics().rule))

        elements = Any[]
        numerator_x = ComputedCell(() -> Int32((width[] - numerator_width[]) ÷ 2))
        numerator_y = ComputedCell(() -> Int32(rule_y[] - gap() - numerator_height[]))
        denominator_x = ComputedCell(() -> Int32((width[] - denominator_width[]) ÷ 2))
        denominator_y = ComputedCell(() -> Int32(rule_y[] + metrics().rule + gap()))

        push!(elements, _text_element(sign, () -> inner_metrics().upright, c.ink,
                                      () -> numerator_x[],
                                      () -> numerator_y[] + numerator_height[] -
                                            font_ascent(inner_metrics().upright) -
                                            font_descent(inner_metrics().upright)))
        push!(elements, _text_element(sign, () -> inner_metrics().upright, c.ink,
                                      () -> denominator_x[],
                                      () -> denominator_y[]))
        if !isempty(order_text())
            small = () -> math_metrics(c, :scriptscript).upright
            push!(elements, _text_element(order_text, small, c.ink,
                                          () -> numerator_x[] + sign_width[],
                                          () -> numerator_y[]))
            push!(elements, _text_element(order_text, small, c.ink,
                                          () -> denominator_x[] + sign_width[] +
                                                _box_width(variable, inner_metrics()),
                                          () -> denominator_y[]))
        end
        push!(elements, _place(_box_output(body),
                               ComputedCell(() -> Int32(numerator_x[] + sign_width[] + order_width[])),
                               ComputedCell(() -> Int32(numerator_y[] + numerator_height[] -
                                                        row_height(body)))))
        push!(elements, _place(_box_output(variable),
                               ComputedCell(() -> Int32(denominator_x[] + sign_width[])),
                               ComputedCell(() -> Int32(denominator_y[]))))
        push!(elements, _rule_element(() -> 0, () -> rule_y[], () -> width[],
                                      () -> metrics().rule, c.ink))
        _build(elements, width, ascent, descent, Any[body, variable])
    end)
    _math_iomap(p, doc, build)
end

# ════════════════════════════════════════════════════════════════════════════
# Function application
# ════════════════════════════════════════════════════════════════════════════

struct MathFunctionToGraphics <: Projection
    config::MathConfig
    style::Symbol
end
MathFunctionToGraphics(c::MathConfig) = MathFunctionToGraphics(c, :display)

function print_document(p::MathFunctionToGraphics, recursion, doc::MathFunction, ctx)
    style = _style_of(p, ctx)
    c = p.config
    build = ComputedCell(function ()
        argument = _print_math_child(recursion, doc.argument,
                                     make_child_context(ctx, doc, @reference_step argument))
        base = doc.base === nothing ? nothing :
            _print_math_child(recursion, doc.base,
                              _with_style(make_child_context(ctx, doc, @reference_step base),
                                          _script_style(style)))
        metrics = () -> math_metrics(c, style)
        # The name is upright: `log`, not the product of l, o and g.
        name = _glyph_box(c, () -> doc.name, () -> metrics().upright)

        boxes = Any[name]
        spaces = Symbol[:none]
        children = Any[]
        if base !== nothing
            # The base rides under the name, so it is a script box of its own.
            inner = _script_style(style)
            # The base rides under the name by the same baseline shift a
            # subscript uses. The box reaches from the shifted baseline, so the
            # child sits at the top of it unless the shift is the deeper of the
            # two.
            down = () -> round(Int, 0.2 * metrics().size)
            base_box = MathGlyphBox(
                _place(_box_output(base),
                       Cell(Int32(0)),
                       ComputedCell(() -> Int32(max(0, down() -
                                                    _box_ascent(base, math_metrics(c, inner)))))),
                ComputedCell(() -> _box_width(base, math_metrics(c, inner))),
                ComputedCell(() -> max(0, _box_ascent(base, math_metrics(c, inner)) - down())),
                ComputedCell(() -> down() + _box_descent(base, math_metrics(c, inner))))
            push!(boxes, base_box)
            push!(spaces, :none)
            push!(children, base)
        end
        if doc.parenthesized
            half = function ()
                m = metrics()
                reach = max(_box_ascent(argument, m) - m.axis, _box_descent(argument, m) + m.axis)
                reach + m.rule
            end
            push!(boxes, _delimiter_box(c, style, :parenthesis, :open, half))
            push!(spaces, :none)
            push!(boxes, argument)
            push!(spaces, :none)
            push!(boxes, _delimiter_box(c, style, :parenthesis, :close, half))
            push!(spaces, :none)
        else
            push!(boxes, argument)
            push!(spaces, :thin)
        end
        push!(children, argument)
        _row(boxes, spaces, c, style, children)
    end)
    _math_iomap(p, doc, build)
end

# ════════════════════════════════════════════════════════════════════════════
# Accent
# ════════════════════════════════════════════════════════════════════════════

struct MathAccentToGraphics <: Projection
    config::MathConfig
    style::Symbol
end
MathAccentToGraphics(c::MathConfig) = MathAccentToGraphics(c, :display)

const _ACCENT_GLYPHS = Dict{Symbol, String}(
    :hat => "ˆ", :tilde => "˜", :dot => "˙", :ddot => "¨",
    :check => "ˇ", :breve => "˘", :acute => "´", :grave => "`",
    :vec => "→", :widehat => "ˆ", :widetilde => "˜",
)

function print_document(p::MathAccentToGraphics, recursion, doc::MathAccent, ctx)
    style = _style_of(p, ctx)
    c = p.config
    build = ComputedCell(function ()
        base = _print_math_child(recursion, doc.base,
                                 make_child_context(ctx, doc, @reference_step base))
        metrics = () -> math_metrics(c, style)
        gap = () -> metrics().rule
        wide = math_accent_is_wide(doc.accent)
        glyph = get(_ACCENT_GLYPHS, doc.accent, "")

        accent_height = ComputedCell(function ()
            m = metrics()
            wide && (doc.accent === :bar || doc.accent === :overline) && return m.rule
            m.x_height ÷ 2
        end)
        width = ComputedCell(() -> _box_width(base, metrics()))
        ascent = ComputedCell(() -> _box_ascent(base, metrics()) + gap() + accent_height[])
        descent = ComputedCell(() -> _box_descent(base, metrics()))

        elements = Any[_place(_box_output(base), Cell(Int32(0)),
                              ComputedCell(() -> Int32(gap() + accent_height[])))]
        if doc.accent === :bar || doc.accent === :overline
            # A bar is a rule, not a glyph: it must span the whole base.
            push!(elements, _rule_element(() -> 0, () -> 0, () -> width[],
                                          () -> accent_height[], c.ink))
        elseif !isempty(glyph)
            # A narrow accent centers over the base; an arrow is drawn at a size
            # that reaches across it.
            font = function ()
                m = metrics()
                wide || return m.upright
                base_width = max(1, c.measure(glyph, m.upright)[1])
                _scaled(m.upright, clamp(round(Int, m.size * width[] / base_width),
                                         m.size ÷ 2, 2 * m.size))
            end
            glyph_width = ComputedCell(() -> c.measure(glyph, font())[1])
            push!(elements, _text_element(() -> glyph, font, c.ink,
                                          () -> (width[] - glyph_width[]) ÷ 2,
                                          () -> -font_ascent(font()) +
                                                font_ascent(metrics().upright) ÷ 4))
        end
        _build(elements, width, ascent, descent, Any[base])
    end)
    _math_iomap(p, doc, build)
end

# ════════════════════════════════════════════════════════════════════════════
# Grids
# ════════════════════════════════════════════════════════════════════════════

"""
    _grid(boxes, columns, config, style) -> NamedTuple

Place `boxes` in a grid: a column is as wide as its widest cell, a row sits on
one baseline, and every cell centers in its column. The grid as a whole centers
on the axis, which is where a matrix belongs beside a `=`.
"""
function _grid(boxes::Vector, columns::Int, c::MathConfig, style::Symbol)
    n = length(boxes)
    columns = max(1, columns)
    rows = max(1, ceil(Int, n / columns))
    cell(r, k) = (i = (r - 1) * columns + k; i <= n ? boxes[i] : nothing)

    column_width = ComputedCell(function ()
        m = math_metrics(c, style)
        [maximum(r -> (b = cell(r, k); b === nothing ? 0 : _box_width(b, m)), 1:rows)
         for k in 1:columns]
    end)
    row_ascent = ComputedCell(function ()
        m = math_metrics(c, style)
        [maximum(k -> (b = cell(r, k); b === nothing ? 0 : _box_ascent(b, m)), 1:columns)
         for r in 1:rows]
    end)
    row_descent = ComputedCell(function ()
        m = math_metrics(c, style)
        [maximum(k -> (b = cell(r, k); b === nothing ? 0 : _box_descent(b, m)), 1:columns)
         for r in 1:rows]
    end)
    column_gap = () -> math_metrics(c, style).size ÷ 2
    row_gap = () -> math_metrics(c, style).size ÷ 4

    width = ComputedCell(() -> sum(column_width[]) + (columns - 1) * column_gap())
    height = ComputedCell(() -> sum(row_ascent[]) + sum(row_descent[]) + (rows - 1) * row_gap())
    ascent = ComputedCell(() -> (height[] + 1) ÷ 2 + math_metrics(c, style).axis)
    descent = ComputedCell(() -> height[] - ascent[])

    elements = Any[]
    for r in 1:rows, k in 1:columns
        box = cell(r, k)
        box === nothing && continue
        x = ComputedCell(function ()
            m = math_metrics(c, style)
            widths = column_width[]
            at = 0
            for j in 1:(k - 1)
                at += widths[j] + column_gap()
            end
            Int32(at + (widths[k] - _box_width(box, m)) ÷ 2)
        end)
        y = ComputedCell(function ()
            m = math_metrics(c, style)
            ascents = row_ascent[]
            descents = row_descent[]
            at = 0
            for j in 1:(r - 1)
                at += ascents[j] + descents[j] + row_gap()
            end
            Int32(at + ascents[r] - _box_ascent(box, m))
        end)
        push!(elements, _place(_box_output(box), x, y))
    end
    _build(elements, width, ascent, descent, boxes)
end

# Wrap a built grid in a delimiter pair that grows with it.
function _delimited(inner, kind::Symbol, c::MathConfig, style::Symbol, children)
    kind === :none && return _build(inner.elements, inner.width, inner.ascent,
                                    inner.descent, children)
    half = () -> begin
        m = math_metrics(c, style)
        max(inner.ascent[] - m.axis, inner.descent[] + m.axis) + m.rule
    end
    open = _delimiter_box(c, style, kind, :open, half)
    close = _delimiter_box(c, style, kind, :close, half)
    body = MathGlyphBox(
        GraphicsCanvas(Cell(Int32(0)), Cell(Int32(0)),
                       _int32(() -> inner.width[]),
                       _int32(() -> inner.ascent[] + inner.descent[]),
                       ComputedCellVector(() -> inner.elements),
                       layout_none, true, Cell(nothing)),
        inner.width, inner.ascent, inner.descent)
    row = _row(Any[open, body, close], Symbol[:none, :none, :none], c, style, children)
    row
end

struct MathMatrixToGraphics <: Projection
    config::MathConfig
    style::Symbol
end
MathMatrixToGraphics(c::MathConfig) = MathMatrixToGraphics(c, :display)

function print_document(p::MathMatrixToGraphics, recursion, doc::MathMatrix, ctx)
    style = _style_of(p, ctx)
    c = p.config
    build = ComputedCell(function ()
        children = Any[]
        for i in 1:length(doc.elements)
            cctx = make_child_context(ctx, doc, (@reference_step elements), (@reference_step [i]))
            push!(children, _print_math_child(recursion, doc.elements[i], cctx))
        end
        inner = _grid(children, doc.columns, c, style)
        _delimited(inner, doc.delimiter, c, style, children)
    end)
    _math_iomap(p, doc, build)
end

struct MathCaseToGraphics <: Projection
    config::MathConfig
    style::Symbol
end
MathCaseToGraphics(c::MathConfig) = MathCaseToGraphics(c, :display)

function print_document(p::MathCaseToGraphics, recursion, doc::MathCase, ctx)
    style = _style_of(p, ctx)
    c = p.config
    build = ComputedCell(function ()
        value = _print_math_child(recursion, doc.value,
                                  make_child_context(ctx, doc, @reference_step value))
        metrics = () -> math_metrics(c, style)
        if doc.condition === nothing
            word = _glyph_box(c, () -> "otherwise", () -> metrics().upright)
            return _row(Any[value, word], Symbol[:none, :thick], c, style, Any[value])
        end
        condition = _print_math_child(recursion, doc.condition,
                                      make_child_context(ctx, doc, @reference_step condition))
        word = _glyph_box(c, () -> "if", () -> metrics().upright)
        _row(Any[value, word, condition], Symbol[:none, :thick, :thick], c, style,
             Any[value, condition])
    end)
    _math_iomap(p, doc, build)
end

struct MathCasesToGraphics <: Projection
    config::MathConfig
    style::Symbol
end
MathCasesToGraphics(c::MathConfig) = MathCasesToGraphics(c, :display)

function print_document(p::MathCasesToGraphics, recursion, doc::MathCases, ctx)
    style = _style_of(p, ctx)
    c = p.config
    build = ComputedCell(function ()
        children = Any[]
        for i in 1:length(doc.cases)
            cctx = make_child_context(ctx, doc, (@reference_step cases), (@reference_step [i]))
            push!(children, _print_math_child(recursion, doc.cases[i], cctx))
        end
        # One case per row, left aligned — a case list is not a matrix.
        inner = _grid_left(children, c, style)
        _delimited(inner, :brace, c, style, children)
    end)
    _math_iomap(p, doc, build)
end

# A single left-aligned column: the shape a case list wants.
function _grid_left(boxes::Vector, c::MathConfig, style::Symbol)
    row_gap = () -> math_metrics(c, style).size ÷ 4
    width = ComputedCell(function ()
        m = math_metrics(c, style)
        w = 0
        for b in boxes
            w = max(w, _box_width(b, m))
        end
        w
    end)
    height = ComputedCell(function ()
        m = math_metrics(c, style)
        h = 0
        for (i, b) in enumerate(boxes)
            h += _box_ascent(b, m) + _box_descent(b, m)
            i < length(boxes) && (h += row_gap())
        end
        h
    end)
    ascent = ComputedCell(() -> (height[] + 1) ÷ 2 + math_metrics(c, style).axis)
    descent = ComputedCell(() -> height[] - ascent[])
    elements = Any[]
    for i in eachindex(boxes)
        y = ComputedCell(function ()
            m = math_metrics(c, style)
            at = 0
            for j in 1:(i - 1)
                at += _box_ascent(boxes[j], m) + _box_descent(boxes[j], m) + row_gap()
            end
            Int32(at)
        end)
        push!(elements, _place(_box_output(boxes[i]), Cell(Int32(0)), y))
    end
    _build(elements, width, ascent, descent, boxes)
end

# ════════════════════════════════════════════════════════════════════════════
# The composite
# ════════════════════════════════════════════════════════════════════════════

"""
    MathToGraphics(; measure, font, slanted, style, ink, hint) -> TypeDispatchingProjection

Every math rule, sharing one configuration. Splice `.dispatch` into a bigger
table the way `WidgetToGraphics(…).dispatch` is spliced, so a formula renders
the same wherever it appears.

`style` is the style level of the root: `:display` sets a formula on its own
line (limits above and below a sum, a taller fraction) and `:text` sets it in a
line of prose.
"""
function MathToGraphics(; measure::Function = truetype_measure_text,
                        font::StyleFont = font_dejavu_sans_regular_20,
                        slanted::StyleFont = font_dejavu_sans_italic_20,
                        style::Symbol = :display,
                        ink::StyleColor = color_default,
                        hint::StyleColor = color_solarized_gray)
    c = MathConfig(font = font, slanted = slanted, measure = measure, ink = ink, hint = hint)
    TypeDispatchingProjection(
        MathVariable        => MathVariableToGraphics(c, style),
        MathSymbol          => MathSymbolToGraphics(c, style),
        MathText            => MathTextToGraphics(c, style),
        MathSpace           => MathSpaceToGraphics(c, style),
        MathInsertion       => MathInsertionToGraphics(c, style),
        MathRow             => MathRowToGraphics(c, style),
        MathBinaryOperation => MathBinaryOperationToGraphics(c, style),
        MathUnaryOperation  => MathUnaryOperationToGraphics(c, style),
        MathAssignment      => MathAssignmentToGraphics(c, style),
        MathParenthesized   => MathParenthesizedToGraphics(c, style),
        MathFraction        => MathFractionToGraphics(c, style),
        MathScript          => MathScriptToGraphics(c, style),
        MathRadical         => MathRadicalToGraphics(c, style),
        MathBigOperator     => MathBigOperatorToGraphics(c, style),
        MathDifferential    => MathDifferentialToGraphics(c, style),
        MathDerivative      => MathDerivativeToGraphics(c, style),
        MathFunction        => MathFunctionToGraphics(c, style),
        MathAccent          => MathAccentToGraphics(c, style),
        MathMatrix          => MathMatrixToGraphics(c, style),
        MathCase            => MathCaseToGraphics(c, style),
        MathCases           => MathCasesToGraphics(c, style),
        PrimitiveNumber     => MathNumberToGraphics(c, style),
        PrimitiveString     => MathNumberToGraphics(c, style),
    )
end

end # module
