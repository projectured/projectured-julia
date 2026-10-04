# Fragment of `MathModule`.
#
# Math → `GraphicsCanvas`: the **two-dimensional** form of a formula. A fraction
# gets a horizontal rule with the numerator centered above it, a sum gets its
# limits above and below the sign, an exponent rises off the baseline, and a
# delimiter grows with what it holds.
#
# The slice typesets its own boxes. A formula is not a row of aligned widgets:
# every part has a width, an ascent above the baseline and a descent below it, and
# its parent places it from those three numbers. The generic layouts align by top,
# center or bottom, which cannot put a fraction on the baseline of the row that
# holds it, so this module places its children itself and wraps them in a
# `GraphicsCanvas` — the way `LayoutToGraphics` does internally.
#
# Every rule answers a [`MathIoMap`](@ref), which carries the three numbers as
# reactive cells beside the usual projection/input/output. A parent reads its
# children's cells to place them. `GridLayoutIoMap` is the precedent: an IO map
# may publish geometry so that a parent can place and decorate its child.
#
# The glyphs come from one family, DejaVu, which is the only vendored font that
# carries the whole math set — the signs, the Greek letters, the arrows and the
# delimiter extension pieces. A variable is set in the oblique face, everything
# else in the upright one, all in one ink color, the way a formula is printed.
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
    MathProjection

The supertype of every rule in this module. All of them answer the same box
protocol, so the selection maps and the mouse routing are written once, against
the protocol, rather than once per rule.
"""
abstract type MathProjection <: Projection end

"""
    MathChild(steps, iomap, x, y)

One child document inside a parent's box: the reference steps that reach it, its
own IO map, and where the parent placed it. The placement is what lets a click
find it and a selection find its way back out.
"""
struct MathChild
    steps::Tuple
    iomap::Any
    x::Cell
    y::Cell
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
_box_descent(b, m) = (h = _foreign_size(b)[2]; max(0, h - _box_ascent(b, m)))

# A foreign box — a document of another domain, rendered through the outer
# recursion — reports no baseline of its own. When it draws text, the first run
# gives one: text is drawn from the top of its glyph box, so the baseline sits
# one font ascent below. That is what keeps a number rendered by the natural
# renderer on the same line as the variables beside it. A box that draws no text
# has no baseline to find and centers on the axis instead.
function _box_ascent(b, m)
    text = _first_text_baseline(_box_output(b))
    text === nothing || return text
    h = _foreign_size(b)[2]
    (h + 1) ÷ 2 + m.axis
end

function _first_text_baseline(doc)
    doc isa GraphicsText && return Int(doc.y[]) + compute_text_extent(String(doc.text), doc.font)[2]
    doc isa GraphicsCanvas || return nothing
    for i in 1:length(doc.elements)
        inner = _first_text_baseline(doc.elements[i])
        inner === nothing || return Int(doc.y[]) + inner
    end
    nothing
end

function _foreign_size(b)
    output = b.output
    output isa GraphicsCanvas && return (Int(output.w[]), Int(output.h[]))
    output isa GraphicsDocument && return get_graphics_size(output)
    (0, 0)
end

_box_output(b::MathGlyphBox) = b.output
_box_output(b) = b.output

# ════════════════════════════════════════════════════════════════════════════
# Configuration and metrics
# ════════════════════════════════════════════════════════════════════════════

"""
    MathConfig(; theme = nothing, measure, font, slanted, ink, hint)

What every rule of one renderer shares: the two faces, the text measurer and the
two ink colors. One value is built by `MathToGraphics` and handed to each rule,
so a formula cannot end up half in one font and half in another. `theme` is a
`MathTheme`, scaled or not, or `nothing` for the default values; a field given
explicitly overrides the theme's own.
"""
@cell_struct UntrackedCell struct MathConfig
    font::StyleFont        # upright: numbers, operators, function names, symbols
    slanted::StyleFont     # oblique: variables
    measure::TextMeasure
    ink::StyleColor
    hint::StyleColor
    selection_wash::StyleColor   # the wash a selected box paints over itself
end

MathConfig(; theme = nothing,
             measure::TextMeasure = FontFileMeasure(),
             font = get_math_style(theme, :font),
             slanted = get_math_style(theme, :slanted_font),
             ink = get_math_style(theme, :ink),
             hint = get_math_style(theme, :hint),
             selection_wash = get_math_style(theme, :selection_wash)) =
    MathConfig(font, slanted, measure, ink, hint, selection_wash)

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
    size == font.size ? font : with_font_size(font, size)

"""
    compute_math_metrics(config, style) -> MathMetrics

The numbers for one style level, from the font of `config` at the size of the
level.
"""
function compute_math_metrics(c::MathConfig, style::Symbol)
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

_int32(f) = Cell(@computation Int32(f()))

# One run of text. `x`/`y` are the top-left of its box, relative to the canvas
# that holds it; a backend draws the baseline the ascent of that box below `y`
# (`_get_text_ascent`).
_text_element(text, font, color::StyleColor, x = () -> 0, y = () -> 0) =
    GraphicsText(Cell(Computation(text)), _int32(x), _int32(y), Cell(Computation(font)),
                 Cell(color), Cell(nothing))

# A filled rule: a fraction bar, a radical bar, an accent bar, a caret.
_rule_element(x, y, w, h, color::StyleColor) =
    GraphicsRect(_int32(x), _int32(y), _int32(w), _int32(h), Cell(color),
                 Cell(Int32(0)), Cell(Int32(0)), Cell(Int32(0)), Cell(Int32(0)),
                 Cell(Int32(0)), Cell(color_transparent), Cell(nothing))

# An outlined rule: the placeholder box of an empty slot.
_outline_element(x, y, w, h, color::StyleColor) =
    GraphicsRect(_int32(x), _int32(y), _int32(w), _int32(h),
                 Cell(color_transparent),
                 Cell(Int32(2)), Cell(Int32(2)), Cell(Int32(2)), Cell(Int32(2)),
                 Cell(Int32(1)), Cell(color), Cell(nothing))

# The distance from the `y` of a run of `text` in `font` down to its baseline,
# where a backend draws it: the ascent of the box of the text. A fallback font
# that draws the text can make it larger than the ascent of `font`.
_get_text_ascent(c::MathConfig, text::AbstractString, font::StyleFont) =
    compute_text_extent(c.measure, text, font)[2]

# Put one already-built graphic at `(x, y)` inside its parent. The wrapper is
# the same trick the layouts use: the child keeps its own coordinates at the
# origin and the wrapper carries the position.
_place(child::GraphicsDocument, x::Cell, y::Cell) =
    GraphicsCanvas(x, y, Cell(Int32(0)), Cell(Int32(0)),
                   CellVector(Cell[Cell(child)]), layout_none, true, Cell(nothing))

"""
    _glyph_box(config, text, font, color) -> MathGlyphBox

A box holding one run of introduced text. Its width, ascent and descent are the
box of the text as the measure gives it, so it sits on the same baseline as a
leaf.
"""
function _glyph_box(c::MathConfig, text::Function, font::Function,
                    color::StyleColor = c.ink)
    MathGlyphBox(_text_element(text, font, color),
                 Cell(@computation compute_text_extent(c.measure, text(), font())[1]),
                 Cell(@computation compute_text_extent(c.measure, text(), font())[2]),
                 Cell(@computation compute_text_extent(c.measure, text(), font())[3]))
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
                            CellVector(Computation(function ()
                                # The selection wash goes in front of the
                                # content so a hit test finds the parts, and it
                                # paints nothing while nothing is selected.
                                elements = Any[_selection_element(p, doc, build)]
                                append!(elements, build[].elements)
                                elements
                            end)),
                            layout_none, true, Cell(nothing))
    MathIoMap(p, doc, canvas,
              Cell(@computation build[].children),
              Cell(@computation build[].width[]),
              Cell(@computation build[].ascent[]),
              Cell(@computation build[].descent[]))
end

"""
    _row(boxes, spaces, config, style) -> NamedTuple

Place `boxes` left to right on one baseline. `spaces` gives the gap before each
box as a class symbol (`:none`, `:thin`, `:medium`, `:thick`), resolved against
the metrics, so a larger font gives larger gaps.
"""
function _row(boxes::Vector, spaces::Vector{Symbol}, c::MathConfig, style::Symbol,
              steps::Vector = Any[nothing for _ in boxes])
    ascent = Cell(Computation(function ()
        m = compute_math_metrics(c, style)
        a = 0
        for b in boxes
            a = max(a, _box_ascent(b, m))
        end
        a
    end))
    descent = Cell(Computation(function ()
        m = compute_math_metrics(c, style)
        d = 0
        for b in boxes
            d = max(d, _box_descent(b, m))
        end
        d
    end))
    width = Cell(Computation(function ()
        m = compute_math_metrics(c, style)
        w = 0
        for (i, b) in enumerate(boxes)
            w += _class_space(spaces[i], m) + _box_width(b, m)
        end
        w
    end))
    elements = Any[]
    children = MathChild[]
    for i in eachindex(boxes)
        x = Cell(Computation(function ()
            m = compute_math_metrics(c, style)
            at = 0
            for j in 1:i
                at += _class_space(spaces[j], m)
                j < i && (at += _box_width(boxes[j], m))
            end
            Int32(at)
        end))
        y = Cell(Computation(function ()
            m = compute_math_metrics(c, style)
            Int32(ascent[] - _box_ascent(boxes[i], m))
        end))
        push!(elements, _place(_box_output(boxes[i]), x, y))
        steps[i] === nothing || push!(children, MathChild(steps[i], boxes[i], x, y))
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
struct MathVariableToGraphics <: MathProjection
    config::MathConfig
    style::Symbol
end
MathVariableToGraphics(c::MathConfig) = MathVariableToGraphics(c, :display)

# A leaf box: one run of text, the whole box.
function _leaf_iomap(p, doc, text::Function, font::Function, color::StyleColor,
                     c::MathConfig)
    build = Cell(Computation(function ()
        element = _text_element(text, font, color)
        _build(Any[element],
               Cell(@computation compute_text_extent(c.measure, text(), font())[1]),
               Cell(@computation compute_text_extent(c.measure, text(), font())[2]),
               Cell(@computation compute_text_extent(c.measure, text(), font())[3]),
               MathChild[])
    end))
    _math_iomap(p, doc, build)
end

function print_document(p::MathVariableToGraphics, recursion, doc::MathVariable, ctx)
    style = _style_of(p, ctx)
    _leaf_iomap(p, doc, () -> doc.name,
                () -> compute_math_metrics(p.config, style).slanted, p.config.ink, p.config)
end

struct MathSymbolToGraphics <: MathProjection
    config::MathConfig
    style::Symbol
end
MathSymbolToGraphics(c::MathConfig) = MathSymbolToGraphics(c, :display)

# A lowercase Greek letter is a variable in disguise and is set slanted; a sign,
# an arrow and a capital Greek letter stay upright — the convention every
# printed formula follows.
function _symbol_font(name::Symbol, m::MathMetrics)
    glyph = get_math_symbol_glyph(name)
    if length(glyph) == 1
        point = UInt32(first(glyph))
        0x3B1 <= point <= 0x3C9 && return m.slanted
    end
    m.upright
end

function print_document(p::MathSymbolToGraphics, recursion, doc::MathSymbol, ctx)
    style = _style_of(p, ctx)
    _leaf_iomap(p, doc, () -> get_math_symbol_glyph(doc.name),
                () -> _symbol_font(doc.name, compute_math_metrics(p.config, style)),
                p.config.ink, p.config)
end

struct MathTextToGraphics <: MathProjection
    config::MathConfig
    style::Symbol
end
MathTextToGraphics(c::MathConfig) = MathTextToGraphics(c, :display)

function print_document(p::MathTextToGraphics, recursion, doc::MathText, ctx)
    style = _style_of(p, ctx)
    _leaf_iomap(p, doc, () -> doc.content,
                () -> compute_math_metrics(p.config, style).upright, p.config.ink, p.config)
end

struct MathNumberToGraphics <: MathProjection
    config::MathConfig
    style::Symbol
end
MathNumberToGraphics(c::MathConfig) = MathNumberToGraphics(c, :display)

function print_document(p::MathNumberToGraphics, recursion, doc::PrimitiveNumber, ctx)
    style = _style_of(p, ctx)
    _leaf_iomap(p, doc, () -> string(doc.value),
                () -> compute_math_metrics(p.config, style).upright, p.config.ink, p.config)
end

function print_document(p::MathNumberToGraphics, recursion, doc::PrimitiveString, ctx)
    style = _style_of(p, ctx)
    _leaf_iomap(p, doc, () -> string(doc.value),
                () -> compute_math_metrics(p.config, style).upright, p.config.ink, p.config)
end

struct MathSpaceToGraphics <: MathProjection
    config::MathConfig
    style::Symbol
end
MathSpaceToGraphics(c::MathConfig) = MathSpaceToGraphics(c, :display)

function print_document(p::MathSpaceToGraphics, recursion, doc::MathSpace, ctx)
    style = _style_of(p, ctx)
    c = p.config
    build = Cell(Computation(function ()
        width = Cell(Computation(function ()
            m = compute_math_metrics(c, style)
            doc.kind === :medium ? m.medium :
            doc.kind === :thick ? m.thick :
            doc.kind === :quad ? m.size : m.thin
        end))
        _build(Any[], width, Cell(0), Cell(0), MathChild[])
    end))
    _math_iomap(p, doc, build)
end

struct MathInsertionToGraphics <: MathProjection
    config::MathConfig
    style::Symbol
end
MathInsertionToGraphics(c::MathConfig) = MathInsertionToGraphics(c, :display)

# An empty slot is a box a reader can see and a mouse can hit — an invisible
# slot is a slot nobody can fill.
function print_document(p::MathInsertionToGraphics, recursion, doc::MathInsertion, ctx)
    style = _style_of(p, ctx)
    c = p.config
    build = Cell(Computation(function ()
        width = Cell(@computation max(4, compute_math_metrics(c, style).x_height))
        ascent = Cell(@computation compute_math_metrics(c, style).x_height)
        element = _outline_element(() -> 0, () -> 0, () -> width[], () -> ascent[], c.hint)
        _build(Any[element], width, ascent, Cell(0), MathChild[])
    end))
    _math_iomap(p, doc, build)
end

# ════════════════════════════════════════════════════════════════════════════
# Sequences
# ════════════════════════════════════════════════════════════════════════════

struct MathRowToGraphics <: MathProjection
    config::MathConfig
    style::Symbol
end
MathRowToGraphics(c::MathConfig) = MathRowToGraphics(c, :display)

function print_document(p::MathRowToGraphics, recursion, doc::MathRow, ctx)
    style = _style_of(p, ctx)
    c = p.config
    build = Cell(Computation(function ()
        children = Any[]
        for i in 1:length(doc.elements)
            cctx = make_child_context(ctx, doc, (@reference_step elements), (@reference_step [i]))
            push!(children, _print_math_child(recursion, doc.elements[i], cctx))
        end
        # Juxtaposition is not glue: `k T B` needs a hair of space, and the
        # first element needs none.
        spaces = Symbol[i == 1 ? :none : :thin for i in eachindex(children)]
        steps = Any[(FieldReferenceStep("elements"), RangeReferenceStep(i - 1, i))
                    for i in eachindex(children)]
        _row(children, spaces, c, style, steps)
    end))
    _math_iomap(p, doc, build)
end

struct MathBinaryOperationToGraphics <: MathProjection
    config::MathConfig
    style::Symbol
end
MathBinaryOperationToGraphics(c::MathConfig) = MathBinaryOperationToGraphics(c, :display)

function print_document(p::MathBinaryOperationToGraphics, recursion, doc::MathBinaryOperation, ctx)
    style = _style_of(p, ctx)
    c = p.config
    build = Cell(Computation(function ()
        left_ctx = make_child_context(ctx, doc, @reference_step left)
        right_ctx = make_child_context(ctx, doc, @reference_step right)
        left = _print_math_child(recursion, doc.left, left_ctx)
        right = _print_math_child(recursion, doc.right, right_ctx)
        sign = _glyph_box(c, () -> get_math_operator_glyph(doc.operator),
                          () -> compute_math_metrics(c, style).upright)
        space = get_math_operator_class(doc.operator)
        _row(Any[left, sign, right], Symbol[:none, space, space], c, style,
             Any[(FieldReferenceStep("left"),), nothing, (FieldReferenceStep("right"),)])
    end))
    _math_iomap(p, doc, build)
end

struct MathUnaryOperationToGraphics <: MathProjection
    config::MathConfig
    style::Symbol
end
MathUnaryOperationToGraphics(c::MathConfig) = MathUnaryOperationToGraphics(c, :display)

function print_document(p::MathUnaryOperationToGraphics, recursion, doc::MathUnaryOperation, ctx)
    style = _style_of(p, ctx)
    c = p.config
    build = Cell(Computation(function ()
        operand_ctx = make_child_context(ctx, doc, @reference_step operand)
        operand = _print_math_child(recursion, doc.operand, operand_ctx)
        sign = _glyph_box(c, () -> get_math_operator_glyph(doc.operator),
                          () -> compute_math_metrics(c, style).upright)
        # A sign that binds to one operand takes no space: `−x`, `n!`.
        boxes = doc.postfix ? Any[operand, sign] : Any[sign, operand]
        step = (FieldReferenceStep("operand"),)
        steps = doc.postfix ? Any[step, nothing] : Any[nothing, step]
        _row(boxes, Symbol[:none, :none], c, style, steps)
    end))
    _math_iomap(p, doc, build)
end

struct MathAssignmentToGraphics <: MathProjection
    config::MathConfig
    style::Symbol
end
MathAssignmentToGraphics(c::MathConfig) = MathAssignmentToGraphics(c, :display)

function print_document(p::MathAssignmentToGraphics, recursion, doc::MathAssignment, ctx)
    style = _style_of(p, ctx)
    c = p.config
    build = Cell(Computation(function ()
        target_ctx = make_child_context(ctx, doc, @reference_step target)
        value_ctx = make_child_context(ctx, doc, @reference_step value)
        target = _print_math_child(recursion, doc.target, target_ctx)
        value = _print_math_child(recursion, doc.value, value_ctx)
        sign = _glyph_box(c, () -> "=", () -> compute_math_metrics(c, style).upright)
        _row(Any[target, sign, value], Symbol[:none, :relation, :relation], c, style,
             Any[(FieldReferenceStep("target"),), nothing, (FieldReferenceStep("value"),)])
    end))
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
    glyph = side === :open ? get_math_delimiter_strings(kind)[1] : get_math_delimiter_strings(kind)[2]
    pieces = get(_DELIMITER_PIECES, (kind, side), nothing)

    # The scale one glyph needs to cover the height, and the font it lands at.
    scale = () -> begin
        m = compute_math_metrics(c, style)
        base = max(1, font_line_height(m.upright))
        max(1.0, 2 * half() / base)
    end
    scaled_font = () -> begin
        m = compute_math_metrics(c, style)
        _scaled(m.upright, max(1, round(Int, m.size * scale())))
    end
    tiled = () -> pieces !== nothing && scale() > _DELIMITER_SCALE_LIMIT

    width = Cell(Computation(function ()
        m = compute_math_metrics(c, style)
        isempty(glyph) && return 0
        tiled() ? first(compute_text_extent(c.measure, string(pieces[1]), m.upright)) :
                  first(compute_text_extent(c.measure, glyph, scaled_font()))
    end))
    ascent = Cell(@computation compute_math_metrics(c, style).axis + half())
    descent = Cell(@computation max(0, half() - compute_math_metrics(c, style).axis))

    output = GraphicsCanvas(Cell(Int32(0)), Cell(Int32(0)),
                            _int32(() -> width[]),
                            _int32(() -> ascent[] + descent[]),
                            CellVector(Computation(function ()
                                isempty(glyph) && return Any[]
                                tiled() ? _tiled_delimiter(c, style, pieces, half) :
                                          Any[_text_element(() -> glyph, scaled_font, c.ink)]
                            end)),
                            layout_none, true, Cell(nothing))
    MathGlyphBox(output, width, ascent, descent)
end

# Tile a delimiter out of its pieces. Each piece is placed by its *ink*: a
# backend draws the baseline of a piece the ascent of its box below its `y`, so a
# piece whose ink top must land at `top` is drawn at `top - ascent + ymax`.
function _tiled_delimiter(c::MathConfig, style::Symbol, pieces::NTuple{4, Char},
                          half::Function)
    m = compute_math_metrics(c, style)
    font = m.upright
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
                                      () -> 0,
                                      () -> ink_top - _get_text_ascent(c, string(ch), font) + ymax))

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

struct MathParenthesizedToGraphics <: MathProjection
    config::MathConfig
    style::Symbol
end
MathParenthesizedToGraphics(c::MathConfig) = MathParenthesizedToGraphics(c, :display)

function print_document(p::MathParenthesizedToGraphics, recursion, doc::MathParenthesized, ctx)
    style = _style_of(p, ctx)
    c = p.config
    build = Cell(Computation(function ()
        content_ctx = make_child_context(ctx, doc, @reference_step content)
        content = _print_math_child(recursion, doc.content, content_ctx)
        # A delimiter covers its content symmetrically about the axis, plus a
        # little air, so `(1)` and `(a/b)` both look deliberate.
        half = function ()
            m = compute_math_metrics(c, style)
            reach = max(_box_ascent(content, m) - m.axis, _box_descent(content, m) + m.axis)
            reach + m.rule
        end
        open = _delimiter_box(c, style, doc.kind, :open, half)
        close = _delimiter_box(c, style, doc.kind, :close, half)
        _row(Any[open, content, close], Symbol[:none, :none, :none], c, style,
             Any[nothing, (FieldReferenceStep("content"),), nothing])
    end))
    _math_iomap(p, doc, build)
end

# ════════════════════════════════════════════════════════════════════════════
# Fraction
# ════════════════════════════════════════════════════════════════════════════

struct MathFractionToGraphics <: MathProjection
    config::MathConfig
    style::Symbol
end
MathFractionToGraphics(c::MathConfig) = MathFractionToGraphics(c, :display)

function print_document(p::MathFractionToGraphics, recursion, doc::MathFraction, ctx)
    style = _style_of(p, ctx)
    c = p.config
    build = Cell(Computation(function ()
        inner = _fraction_style(style)
        numerator_ctx = _with_style(make_child_context(ctx, doc, @reference_step numerator), inner)
        denominator_ctx = _with_style(make_child_context(ctx, doc, @reference_step denominator), inner)
        numerator = _print_math_child(recursion, doc.numerator, numerator_ctx)
        denominator = _print_math_child(recursion, doc.denominator, denominator_ctx)

        metrics = () -> compute_math_metrics(c, inner)
        gap = () -> (m = metrics(); style === :display ? 3 * m.rule : m.rule)
        pad = () -> metrics().thin

        width = Cell(Computation(function ()
            m = metrics()
            max(_box_width(numerator, m), _box_width(denominator, m)) + 2 * pad()
        end))
        # The rule sits on the axis; the box reaches from the top of the
        # numerator to the bottom of the denominator.
        ascent = Cell(Computation(function ()
            m = compute_math_metrics(c, style)
            im = metrics()
            m.axis + m.rule + gap() + _box_ascent(numerator, im) + _box_descent(numerator, im)
        end))
        descent = Cell(Computation(function ()
            m = compute_math_metrics(c, style)
            im = metrics()
            gap() - m.axis + _box_ascent(denominator, im) + _box_descent(denominator, im)
        end))

        rule_y = Cell(@computation(Int32(ascent[] -
                                         compute_math_metrics(c, style).axis -
                                         compute_math_metrics(c, style).rule)))
        elements = Any[]
        children = MathChild[]
        for (box, above, field) in ((numerator, true, "numerator"),
                                    (denominator, false, "denominator"))
            x = Cell(Computation(function ()
                m = metrics()
                Int32((width[] - _box_width(box, m)) ÷ 2)
            end))
            y = Cell(Computation(function ()
                m = metrics()
                above ? Int32(rule_y[] - gap() - _box_ascent(box, m) - _box_descent(box, m)) :
                        Int32(rule_y[] + compute_math_metrics(c, style).rule + gap())
            end))
            push!(elements, _place(_box_output(box), x, y))
            push!(children, MathChild((FieldReferenceStep(field),), box, x, y))
        end
        push!(elements, _rule_element(() -> 0, () -> rule_y[], () -> width[],
                                      () -> compute_math_metrics(c, style).rule, c.ink))
        _build(elements, width, ascent, descent, children)
    end))
    _math_iomap(p, doc, build)
end

# ════════════════════════════════════════════════════════════════════════════
# Scripts
# ════════════════════════════════════════════════════════════════════════════

struct MathScriptToGraphics <: MathProjection
    config::MathConfig
    style::Symbol
end
MathScriptToGraphics(c::MathConfig) = MathScriptToGraphics(c, :display)

function print_document(p::MathScriptToGraphics, recursion, doc::MathScript, ctx)
    style = _style_of(p, ctx)
    c = p.config
    build = Cell(Computation(function ()
        inner = _script_style(style)
        base_ctx = make_child_context(ctx, doc, @reference_step base)
        base = _print_math_child(recursion, doc.base, base_ctx)
        subscript = doc.subscript === nothing ? nothing :
            _print_math_child(recursion, doc.subscript,
                              _with_style(make_child_context(ctx, doc, @reference_step subscript), inner))
        superscript = doc.superscript === nothing ? nothing :
            _print_math_child(recursion, doc.superscript,
                              _with_style(make_child_context(ctx, doc, @reference_step superscript), inner))

        metrics = () -> compute_math_metrics(c, style)
        inner_metrics = () -> compute_math_metrics(c, inner)
        # How far each script's own baseline moves off the base's.
        up = Cell(Computation(function ()
            superscript === nothing && return 0
            m = metrics()
            # The script's baseline rises by about a third of the em, and by
            # more when the base is tall enough to reach past that.
            max(round(Int, 0.36 * m.size), _box_ascent(base, m) - m.x_height)
        end))
        down = Cell(Computation(function ()
            subscript === nothing && return 0
            m = metrics()
            # A shift of the script's *baseline*, not of its box: a fifth of the
            # em, and never less than the base's own descent.
            max(round(Int, 0.2 * m.size), _box_descent(base, m))
        end))
        # Two scripts must not collide: push them apart, equally, when they do.
        clearance = Cell(Computation(function ()
            (subscript === nothing || superscript === nothing) && return 0
            m = metrics()
            im = inner_metrics()
            overlap = (_box_descent(superscript, im) + _box_ascent(subscript, im)) -
                      (up[] + down[]) + 4 * m.rule
            max(0, (overlap + 1) ÷ 2)
        end))

        script_width = Cell(Computation(function ()
            im = inner_metrics()
            w = 0
            subscript === nothing || (w = max(w, _box_width(subscript, im)))
            superscript === nothing || (w = max(w, _box_width(superscript, im)))
            w
        end))
        width = Cell(@computation _box_width(base, metrics()) + script_width[])
        ascent = Cell(Computation(function ()
            m = metrics()
            im = inner_metrics()
            a = _box_ascent(base, m)
            superscript === nothing ? a :
                max(a, up[] + clearance[] + _box_ascent(superscript, im))
        end))
        descent = Cell(Computation(function ()
            m = metrics()
            im = inner_metrics()
            d = _box_descent(base, m)
            subscript === nothing ? d :
                max(d, down[] + clearance[] + _box_descent(subscript, im))
        end))

        base_x = Cell(Int32(0))
        base_y = Cell(@computation Int32(ascent[] - _box_ascent(base, metrics())))
        elements = Any[_place(_box_output(base), base_x, base_y)]
        children = MathChild[MathChild((FieldReferenceStep("base"),), base, base_x, base_y)]
        script_x = Cell(@computation Int32(_box_width(base, metrics())))
        if superscript !== nothing
            y = Cell(Computation(function ()
                im = inner_metrics()
                Int32(ascent[] - up[] - clearance[] - _box_ascent(superscript, im))
            end))
            push!(elements, _place(_box_output(superscript), script_x, y))
            push!(children, MathChild((FieldReferenceStep("superscript"),), superscript,
                                      script_x, y))
        end
        if subscript !== nothing
            y = Cell(Computation(function ()
                im = inner_metrics()
                Int32(ascent[] + down[] + clearance[] - _box_ascent(subscript, im))
            end))
            push!(elements, _place(_box_output(subscript), script_x, y))
            push!(children, MathChild((FieldReferenceStep("subscript"),), subscript,
                                      script_x, y))
        end
        _build(elements, width, ascent, descent, children)
    end))
    _math_iomap(p, doc, build)
end

# ════════════════════════════════════════════════════════════════════════════
# Radical
# ════════════════════════════════════════════════════════════════════════════

struct MathRadicalToGraphics <: MathProjection
    config::MathConfig
    style::Symbol
end
MathRadicalToGraphics(c::MathConfig) = MathRadicalToGraphics(c, :display)

function print_document(p::MathRadicalToGraphics, recursion, doc::MathRadical, ctx)
    style = _style_of(p, ctx)
    c = p.config
    build = Cell(Computation(function ()
        radicand_ctx = make_child_context(ctx, doc, @reference_step radicand)
        radicand = _print_math_child(recursion, doc.radicand, radicand_ctx)
        index = doc.index === nothing ? nothing :
            _print_math_child(recursion, doc.index,
                              _with_style(make_child_context(ctx, doc, @reference_step index), :scriptscript))

        metrics = () -> compute_math_metrics(c, style)
        index_metrics = () -> compute_math_metrics(c, :scriptscript)
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
        sign_width = Cell(@computation first(compute_text_extent(c.measure, "√", sign_font())))
        index_width = Cell(Computation(function ()
            index === nothing && return 0
            # The index sits over the sign's left arm, so only its overhang adds
            # to the width.
            max(0, _box_width(index, index_metrics()) - sign_width[] ÷ 2)
        end))

        ascent = Cell(Computation(function ()
            m = metrics()
            a = _box_ascent(radicand, m) + 3 * m.rule
            index === nothing ? a :
                max(a, (_box_ascent(radicand, m) + _box_descent(radicand, m)) ÷ 2 +
                       _box_ascent(index, index_metrics()) +
                       _box_descent(index, index_metrics()))
        end))
        descent = Cell(@computation _box_descent(radicand, metrics()))
        width = Cell(@computation(index_width[] + sign_width[] +
                                  _box_width(radicand, metrics()) + metrics().thin))

        # The bar runs from the top of the sign across the radicand.
        bar_y = Cell(Computation(function ()
            m = metrics()
            Int32(ascent[] - _box_ascent(radicand, m) - 3 * m.rule)
        end))
        # A glyph is drawn with its baseline the ascent of its box below its `y`,
        # so a sign whose ink top must land on the bar is drawn that far above it.
        sign_y = Cell(Computation(function ()
            font = sign_font()
            Int32(bar_y[] - _get_text_ascent(c, "√", font) + font_glyph_bounds(font, '√')[2])
        end))
        elements = Any[]
        push!(elements, _text_element(() -> "√", sign_font, c.ink,
                                      () -> index_width[], () -> sign_y[]))
        push!(elements, _rule_element(() -> index_width[] + sign_width[] - metrics().rule,
                                      () -> bar_y[],
                                      () -> _box_width(radicand, metrics()) + metrics().thin +
                                            metrics().rule,
                                      () -> metrics().rule, c.ink))
        radicand_x = Cell(@computation Int32(index_width[] + sign_width[]))
        radicand_y = Cell(@computation Int32(ascent[] - _box_ascent(radicand, metrics())))
        push!(elements, _place(_box_output(radicand), radicand_x, radicand_y))
        children = MathChild[MathChild((FieldReferenceStep("radicand"),), radicand,
                                       radicand_x, radicand_y)]
        if index !== nothing
            index_y = Cell(Computation(function ()
                im = index_metrics()
                Int32(max(0, ascent[] - (_box_ascent(radicand, metrics()) +
                                         _box_descent(radicand, metrics())) ÷ 2 -
                             _box_ascent(index, im) - _box_descent(index, im)))
            end))
            push!(elements, _place(_box_output(index), Cell(Int32(0)), index_y))
            push!(children, MathChild((FieldReferenceStep("index"),), index,
                                      Cell(Int32(0)), index_y))
        end
        _build(elements, width, ascent, descent, children)
    end))
    _math_iomap(p, doc, build)
end

# ════════════════════════════════════════════════════════════════════════════
# Large operators
# ════════════════════════════════════════════════════════════════════════════

struct MathBigOperatorToGraphics <: MathProjection
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
    build = Cell(Computation(function ()
        inner = _script_style(style)
        body = _print_math_child(recursion, doc.body,
                                 make_child_context(ctx, doc, @reference_step body))
        lower = doc.lower === nothing ? nothing :
            _print_math_child(recursion, doc.lower,
                              _with_style(make_child_context(ctx, doc, @reference_step lower), inner))
        upper = doc.upper === nothing ? nothing :
            _print_math_child(recursion, doc.upper,
                              _with_style(make_child_context(ctx, doc, @reference_step upper), inner))

        metrics = () -> compute_math_metrics(c, style)
        inner_metrics = () -> compute_math_metrics(c, inner)
        placement = _limit_placement(doc, style)
        word = is_math_big_operator_text(doc.operator)
        glyph = get_math_big_operator_glyph(doc.operator)
        # A word operator (`lim`) keeps the text size; a sign is enlarged.
        sign_font = function ()
            m = metrics()
            word && return m.upright
            _scaled(m.upright, round(Int, m.size * (style === :display ? 1.8 : 1.2)))
        end
        sign_width = Cell(@computation first(compute_text_extent(c.measure, glyph, sign_font())))
        # The sign centers on the axis, like every other tall thing — by its
        # *ink*, because a sign that is centered by its text box sits visibly
        # high. A word operator has no single ink to center, so it keeps its
        # own baseline.
        sign_ink = Cell(Computation(function ()
            word && return (0, 0)
            font = sign_font()
            low, high = font_glyph_bounds(font, first(glyph))
            (low, high)
        end))
        sign_reach_up = Cell(Computation(function ()
            m = metrics()
            word && return _get_text_ascent(c, glyph, sign_font())
            low, high = sign_ink[]
            (high - low) ÷ 2 + m.axis
        end))
        sign_reach_down = Cell(Computation(function ()
            word && return compute_text_extent(c.measure, glyph, sign_font())[3]
            low, high = sign_ink[]
            (high - low) - sign_reach_up[]
        end))
        # Where to draw the sign so that its ink lands where the box says.
        sign_y = Cell(Computation(function ()
            font = sign_font()
            word && return 0
            font_glyph_bounds(font, first(glyph))[2] - _get_text_ascent(c, glyph, font)
        end))

        limit_width = Cell(Computation(function ()
            im = inner_metrics()
            w = 0
            lower === nothing || (w = max(w, _box_width(lower, im)))
            upper === nothing || (w = max(w, _box_width(upper, im)))
            w
        end))
        limit_gap = () -> metrics().rule * 3

        if placement === :under_over
            head_width = Cell(@computation max(sign_width[], limit_width[]))
            ascent = Cell(Computation(function ()
                im = inner_metrics()
                a = sign_reach_up[]
                upper === nothing ? a :
                    a + limit_gap() + _box_ascent(upper, im) + _box_descent(upper, im)
            end))
            descent = Cell(Computation(function ()
                im = inner_metrics()
                d = sign_reach_down[]
                lower === nothing ? d :
                    d + limit_gap() + _box_ascent(lower, im) + _box_descent(lower, im)
            end))
            width = Cell(@computation(head_width[] + metrics().thin +
                                      _box_width(body, metrics())))
            elements = Any[]
            children = MathChild[]
            push!(elements, _text_element(() -> glyph, sign_font, c.ink,
                                          () -> (head_width[] - sign_width[]) ÷ 2,
                                          () -> ascent[] - sign_reach_up[] + sign_y[]))
            if upper !== nothing
                x = Cell(@computation Int32((head_width[] - _box_width(upper, inner_metrics())) ÷ 2))
                y = Cell(Computation(function ()
                    im = inner_metrics()
                    Int32(ascent[] - sign_reach_up[] - limit_gap() -
                          _box_ascent(upper, im) - _box_descent(upper, im))
                end))
                push!(elements, _place(_box_output(upper), x, y))
                push!(children, MathChild((FieldReferenceStep("upper"),), upper, x, y))
            end
            if lower !== nothing
                x = Cell(@computation Int32((head_width[] - _box_width(lower, inner_metrics())) ÷ 2))
                y = Cell(@computation(Int32(ascent[] + sign_reach_down[] +
                                            limit_gap())))
                push!(elements, _place(_box_output(lower), x, y))
                push!(children, MathChild((FieldReferenceStep("lower"),), lower, x, y))
            end
            body_x = Cell(@computation Int32(head_width[] + metrics().thin))
            body_y = Cell(@computation Int32(ascent[] - _box_ascent(body, metrics())))
            push!(elements, _place(_box_output(body), body_x, body_y))
            push!(children, MathChild((FieldReferenceStep("body"),), body, body_x, body_y))
        else
            # Side limits: a subscript and a superscript on the sign.
            ascent = Cell(Computation(function ()
                im = inner_metrics()
                a = max(sign_reach_up[], _box_ascent(body, metrics()))
                upper === nothing ? a :
                    max(a, sign_reach_up[] - metrics().rule +
                           _box_ascent(upper, im) + _box_descent(upper, im))
            end))
            descent = Cell(Computation(function ()
                im = inner_metrics()
                d = max(sign_reach_down[], _box_descent(body, metrics()))
                lower === nothing ? d :
                    max(d, sign_reach_down[] - metrics().rule +
                           _box_ascent(lower, im) + _box_descent(lower, im))
            end))
            width = Cell(@computation(sign_width[] + limit_width[] + metrics().thin +
                                      _box_width(body, metrics())))
            elements = Any[]
            children = MathChild[]
            push!(elements, _text_element(() -> glyph, sign_font, c.ink,
                                          () -> 0, () -> ascent[] - sign_reach_up[] + sign_y[]))
            if upper !== nothing
                y = Cell(Computation(function ()
                    im = inner_metrics()
                    Int32(max(0, ascent[] - sign_reach_up[] + metrics().rule -
                                 _box_ascent(upper, im) - _box_descent(upper, im)))
                end))
                limit_x = Cell(@computation Int32(sign_width[]))
                push!(elements, _place(_box_output(upper), limit_x, y))
                push!(children, MathChild((FieldReferenceStep("upper"),), upper, limit_x, y))
            end
            if lower !== nothing
                y = Cell(@computation Int32(ascent[] + sign_reach_down[] - metrics().rule))
                limit_x = Cell(@computation Int32(sign_width[]))
                push!(elements, _place(_box_output(lower), limit_x, y))
                push!(children, MathChild((FieldReferenceStep("lower"),), lower, limit_x, y))
            end
            body_x = Cell(@computation Int32(sign_width[] + limit_width[] + metrics().thin))
            body_y = Cell(@computation Int32(ascent[] - _box_ascent(body, metrics())))
            push!(elements, _place(_box_output(body), body_x, body_y))
            push!(children, MathChild((FieldReferenceStep("body"),), body, body_x, body_y))
        end

        _build(elements, width, ascent, descent, children)
    end))
    _math_iomap(p, doc, build)
end

# ════════════════════════════════════════════════════════════════════════════
# Differential and derivative
# ════════════════════════════════════════════════════════════════════════════

struct MathDifferentialToGraphics <: MathProjection
    config::MathConfig
    style::Symbol
end
MathDifferentialToGraphics(c::MathConfig) = MathDifferentialToGraphics(c, :display)

_differential_glyph(kind::Symbol) = kind === :partial ? "∂" : "d"

function print_document(p::MathDifferentialToGraphics, recursion, doc::MathDifferential, ctx)
    style = _style_of(p, ctx)
    c = p.config
    build = Cell(Computation(function ()
        variable = _print_math_child(recursion, doc.variable,
                                     make_child_context(ctx, doc, @reference_step variable))
        sign = _glyph_box(c, () -> _differential_glyph(doc.kind),
                          () -> compute_math_metrics(c, style).upright)
        _row(Any[sign, variable], Symbol[:thin, :none], c, style,
             Any[nothing, (FieldReferenceStep("variable"),)])
    end))
    _math_iomap(p, doc, build)
end

struct MathDerivativeToGraphics <: MathProjection
    config::MathConfig
    style::Symbol
end
MathDerivativeToGraphics(c::MathConfig) = MathDerivativeToGraphics(c, :display)

# `dQ/dt` is a fraction whose parts the projection introduces, so it is built
# here rather than delegated: only `body` and `variable` are the document's.
function print_document(p::MathDerivativeToGraphics, recursion, doc::MathDerivative, ctx)
    style = _style_of(p, ctx)
    c = p.config
    build = Cell(Computation(function ()
        inner = _fraction_style(style)
        body = _print_math_child(recursion, doc.body,
                                 _with_style(make_child_context(ctx, doc, @reference_step body), inner))
        variable = _print_math_child(recursion, doc.variable,
                                     _with_style(make_child_context(ctx, doc, @reference_step variable), inner))
        metrics = () -> compute_math_metrics(c, style)
        inner_metrics = () -> compute_math_metrics(c, inner)
        order_text = () -> doc.order == 1 ? "" : string(doc.order)
        sign = () -> _differential_glyph(doc.kind)

        sign_width = Cell(@computation first(compute_text_extent(c.measure, sign(), inner_metrics().upright)))
        order_width = Cell(Computation(function ()
            isempty(order_text()) && return 0
            first(compute_text_extent(c.measure, order_text(), compute_math_metrics(c, :scriptscript).upright))
        end))

        numerator_width = Cell(@computation(sign_width[] + order_width[] +
                                            _box_width(body, inner_metrics())))
        denominator_width = Cell(@computation(sign_width[] +
                                              _box_width(variable, inner_metrics()) +
                                              order_width[]))
        pad = () -> metrics().thin
        width = Cell(@computation max(numerator_width[], denominator_width[]) + 2 * pad())
        gap = () -> 3 * metrics().rule
        row_ascent(box) = _box_ascent(box, inner_metrics())
        row_height(box) = _box_ascent(box, inner_metrics()) + _box_descent(box, inner_metrics())
        line_height = () -> begin
            im = inner_metrics()
            font_ascent(im.upright) + font_descent(im.upright)
        end
        numerator_height = Cell(@computation max(row_height(body), line_height()))
        denominator_height =
            Cell(@computation max(row_height(variable), line_height()))
        ascent = Cell(@computation metrics().axis + metrics().rule + gap() + numerator_height[])
        descent = Cell(@computation gap() - metrics().axis + denominator_height[])
        rule_y = Cell(@computation Int32(ascent[] - metrics().axis - metrics().rule))

        elements = Any[]
        numerator_x = Cell(@computation Int32((width[] - numerator_width[]) ÷ 2))
        numerator_y = Cell(@computation Int32(rule_y[] - gap() - numerator_height[]))
        denominator_x = Cell(@computation Int32((width[] - denominator_width[]) ÷ 2))
        denominator_y = Cell(@computation Int32(rule_y[] + metrics().rule + gap()))

        push!(elements, _text_element(sign, () -> inner_metrics().upright, c.ink,
                                      () -> numerator_x[],
                                      () -> numerator_y[] + numerator_height[] -
                                            font_ascent(inner_metrics().upright) -
                                            font_descent(inner_metrics().upright)))
        push!(elements, _text_element(sign, () -> inner_metrics().upright, c.ink,
                                      () -> denominator_x[],
                                      () -> denominator_y[]))
        if !isempty(order_text())
            small = () -> compute_math_metrics(c, :scriptscript).upright
            push!(elements, _text_element(order_text, small, c.ink,
                                          () -> numerator_x[] + sign_width[],
                                          () -> numerator_y[]))
            push!(elements, _text_element(order_text, small, c.ink,
                                          () -> denominator_x[] + sign_width[] +
                                                _box_width(variable, inner_metrics()),
                                          () -> denominator_y[]))
        end
        body_x = Cell(@computation Int32(numerator_x[] + sign_width[] + order_width[]))
        body_y = Cell(@computation Int32(numerator_y[] + numerator_height[] - row_height(body)))
        variable_x = Cell(@computation Int32(denominator_x[] + sign_width[]))
        variable_y = Cell(@computation Int32(denominator_y[]))
        push!(elements, _place(_box_output(body), body_x, body_y))
        push!(elements, _place(_box_output(variable), variable_x, variable_y))
        push!(elements, _rule_element(() -> 0, () -> rule_y[], () -> width[],
                                      () -> metrics().rule, c.ink))
        _build(elements, width, ascent, descent,
               MathChild[MathChild((FieldReferenceStep("body"),), body, body_x, body_y),
                         MathChild((FieldReferenceStep("variable"),), variable,
                                   variable_x, variable_y)])
    end))
    _math_iomap(p, doc, build)
end

# ════════════════════════════════════════════════════════════════════════════
# Function application
# ════════════════════════════════════════════════════════════════════════════

struct MathFunctionToGraphics <: MathProjection
    config::MathConfig
    style::Symbol
end
MathFunctionToGraphics(c::MathConfig) = MathFunctionToGraphics(c, :display)

function print_document(p::MathFunctionToGraphics, recursion, doc::MathFunction, ctx)
    style = _style_of(p, ctx)
    c = p.config
    build = Cell(Computation(function ()
        argument = _print_math_child(recursion, doc.argument,
                                     make_child_context(ctx, doc, @reference_step argument))
        base = doc.base === nothing ? nothing :
            _print_math_child(recursion, doc.base,
                              _with_style(make_child_context(ctx, doc, @reference_step base),
                                          _script_style(style)))
        metrics = () -> compute_math_metrics(c, style)
        # The name is upright: `log`, not the product of l, o and g.
        name = _glyph_box(c, () -> doc.name, () -> metrics().upright)

        boxes = Any[name]
        spaces = Symbol[:none]
        steps = Any[nothing]
        base_index = 0
        base_offset = Cell(Int32(0))
        if base !== nothing
            # The base rides under the name, so it is a script box of its own.
            inner = _script_style(style)
            # The base rides under the name by the same baseline shift a
            # subscript uses. The box reaches from the shifted baseline, so the
            # child sits at the top of it unless the shift is the deeper of the
            # two.
            down = () -> round(Int, 0.2 * metrics().size)
            base_offset = Cell(@computation(Int32(max(0, down() -
                                                      _box_ascent(base, compute_math_metrics(c, inner))))))
            base_box = MathGlyphBox(
                _place(_box_output(base), Cell(Int32(0)), base_offset),
                Cell(@computation _box_width(base, compute_math_metrics(c, inner))),
                Cell(@computation max(0, _box_ascent(base, compute_math_metrics(c, inner)) - down())),
                Cell(@computation down() + _box_descent(base, compute_math_metrics(c, inner))))
            push!(boxes, base_box)
            push!(spaces, :none)
            # The box is a wrapper the projection introduced, not the base
            # itself, so it is marked and the real child is re-hung below with
            # both offsets added — the `_delimited` trick.
            push!(steps, ())
            base_index = length(boxes)
        end
        if doc.parenthesized
            half = function ()
                m = metrics()
                reach = max(_box_ascent(argument, m) - m.axis, _box_descent(argument, m) + m.axis)
                reach + m.rule
            end
            push!(boxes, _delimiter_box(c, style, :parenthesis, :open, half))
            push!(spaces, :none)
            push!(steps, nothing)
            push!(boxes, argument)
            push!(spaces, :none)
            push!(steps, (FieldReferenceStep("argument"),))
            push!(boxes, _delimiter_box(c, style, :parenthesis, :close, half))
            push!(spaces, :none)
            push!(steps, nothing)
        else
            push!(boxes, argument)
            push!(spaces, :thin)
            push!(steps, (FieldReferenceStep("argument"),))
        end
        row = _row(boxes, spaces, c, style, steps)
        base_index == 0 && return row
        # Re-hang the base: the row placed its wrapper, the wrapper placed the
        # base inside itself, and a click needs the sum of the two.
        placed = row.children[1]
        children = MathChild[MathChild((FieldReferenceStep("base"),), base, placed.x,
                                       Cell(@computation(Int32(Int(placed.y[]) +
                                                               Int(base_offset[])))))]
        for child in row.children
            child.steps === () || push!(children, child)
        end
        _build(row.elements, row.width, row.ascent, row.descent, children)
    end))
    _math_iomap(p, doc, build)
end

# ════════════════════════════════════════════════════════════════════════════
# Accent
# ════════════════════════════════════════════════════════════════════════════

struct MathAccentToGraphics <: MathProjection
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
    build = Cell(Computation(function ()
        base = _print_math_child(recursion, doc.base,
                                 make_child_context(ctx, doc, @reference_step base))
        metrics = () -> compute_math_metrics(c, style)
        gap = () -> metrics().rule
        wide = is_math_accent_wide(doc.accent)
        glyph = get(_ACCENT_GLYPHS, doc.accent, "")

        accent_height = Cell(Computation(function ()
            m = metrics()
            wide && (doc.accent === :bar || doc.accent === :overline) && return m.rule
            m.x_height ÷ 2
        end))
        width = Cell(@computation _box_width(base, metrics()))
        ascent = Cell(@computation _box_ascent(base, metrics()) + gap() + accent_height[])
        descent = Cell(@computation _box_descent(base, metrics()))

        base_y = Cell(@computation Int32(gap() + accent_height[]))
        elements = Any[_place(_box_output(base), Cell(Int32(0)), base_y)]
        children = MathChild[MathChild((FieldReferenceStep("base"),), base,
                                       Cell(Int32(0)), base_y)]
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
                base_width = max(1, first(compute_text_extent(c.measure, glyph, m.upright)))
                _scaled(m.upright, clamp(round(Int, m.size * width[] / base_width),
                                         m.size ÷ 2, 2 * m.size))
            end
            glyph_width = Cell(@computation first(compute_text_extent(c.measure, glyph, font())))
            push!(elements, _text_element(() -> glyph, font, c.ink,
                                          () -> (width[] - glyph_width[]) ÷ 2,
                                          () -> -_get_text_ascent(c, glyph, font()) +
                                                font_ascent(metrics().upright) ÷ 4))
        end
        _build(elements, width, ascent, descent, children)
    end))
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
function _grid(boxes::Vector, columns::Int, c::MathConfig, style::Symbol, field::String)
    n = length(boxes)
    columns = max(1, columns)
    rows = max(1, ceil(Int, n / columns))
    cell(r, k) = (i = (r - 1) * columns + k; i <= n ? boxes[i] : nothing)

    column_width = Cell(Computation(function ()
        m = compute_math_metrics(c, style)
        [maximum(r -> (b = cell(r, k); b === nothing ? 0 : _box_width(b, m)), 1:rows)
         for k in 1:columns]
    end))
    row_ascent = Cell(Computation(function ()
        m = compute_math_metrics(c, style)
        [maximum(k -> (b = cell(r, k); b === nothing ? 0 : _box_ascent(b, m)), 1:columns)
         for r in 1:rows]
    end))
    row_descent = Cell(Computation(function ()
        m = compute_math_metrics(c, style)
        [maximum(k -> (b = cell(r, k); b === nothing ? 0 : _box_descent(b, m)), 1:columns)
         for r in 1:rows]
    end))
    column_gap = () -> compute_math_metrics(c, style).size ÷ 2
    row_gap = () -> compute_math_metrics(c, style).size ÷ 4

    width = Cell(@computation sum(column_width[]) + (columns - 1) * column_gap())
    height = Cell(@computation sum(row_ascent[]) + sum(row_descent[]) + (rows - 1) * row_gap())
    ascent = Cell(@computation((height[] + 1) ÷ 2 +
                               compute_math_metrics(c, style).axis))
    descent = Cell(@computation height[] - ascent[])

    elements = Any[]
    children = MathChild[]
    for r in 1:rows, k in 1:columns
        box = cell(r, k)
        box === nothing && continue
        index = (r - 1) * columns + k
        x = Cell(Computation(function ()
            m = compute_math_metrics(c, style)
            widths = column_width[]
            at = 0
            for j in 1:(k - 1)
                at += widths[j] + column_gap()
            end
            Int32(at + (widths[k] - _box_width(box, m)) ÷ 2)
        end))
        y = Cell(Computation(function ()
            m = compute_math_metrics(c, style)
            ascents = row_ascent[]
            descents = row_descent[]
            at = 0
            for j in 1:(r - 1)
                at += ascents[j] + descents[j] + row_gap()
            end
            Int32(at + ascents[r] - _box_ascent(box, m))
        end))
        push!(elements, _place(_box_output(box), x, y))
        push!(children, MathChild((FieldReferenceStep(field),
                                   RangeReferenceStep(index - 1, index)), box, x, y))
    end
    _build(elements, width, ascent, descent, children)
end

# Wrap a built grid in a delimiter pair that grows with it.
function _delimited(inner, kind::Symbol, c::MathConfig, style::Symbol)
    kind === :none && return inner
    half = () -> begin
        m = compute_math_metrics(c, style)
        max(inner.ascent[] - m.axis, inner.descent[] + m.axis) + m.rule
    end
    open = _delimiter_box(c, style, kind, :open, half)
    close = _delimiter_box(c, style, kind, :close, half)
    body = MathGlyphBox(
        GraphicsCanvas(Cell(Int32(0)), Cell(Int32(0)),
                       _int32(() -> inner.width[]),
                       _int32(() -> inner.ascent[] + inner.descent[]),
                       CellVector(@computation inner.elements),
                       layout_none, true, Cell(nothing)),
        inner.width, inner.ascent, inner.descent)
    # The row places the whole grid as one box; its children are inside that
    # box, so each one's offset is the body's plus its own.
    row = _row(Any[open, body, close], Symbol[:none, :none, :none], c, style,
               Any[nothing, (), nothing])
    placed = row.children[1]
    shifted = MathChild[MathChild(child.steps, child.iomap,
                                  Cell(@computation Int32(Int(placed.x[]) + Int(child.x[]))),
                                  Cell(@computation Int32(Int(placed.y[]) + Int(child.y[]))))
                        for child in inner.children]
    _build(row.elements, row.width, row.ascent, row.descent, shifted)
end

struct MathMatrixToGraphics <: MathProjection
    config::MathConfig
    style::Symbol
end
MathMatrixToGraphics(c::MathConfig) = MathMatrixToGraphics(c, :display)

function print_document(p::MathMatrixToGraphics, recursion, doc::MathMatrix, ctx)
    style = _style_of(p, ctx)
    c = p.config
    build = Cell(Computation(function ()
        children = Any[]
        for i in 1:length(doc.elements)
            cctx = make_child_context(ctx, doc, (@reference_step elements), (@reference_step [i]))
            push!(children, _print_math_child(recursion, doc.elements[i], cctx))
        end
        inner = _grid(children, doc.columns, c, style, "elements")
        _delimited(inner, doc.delimiter, c, style)
    end))
    _math_iomap(p, doc, build)
end

struct MathCaseToGraphics <: MathProjection
    config::MathConfig
    style::Symbol
end
MathCaseToGraphics(c::MathConfig) = MathCaseToGraphics(c, :display)

function print_document(p::MathCaseToGraphics, recursion, doc::MathCase, ctx)
    style = _style_of(p, ctx)
    c = p.config
    build = Cell(Computation(function ()
        value = _print_math_child(recursion, doc.value,
                                  make_child_context(ctx, doc, @reference_step value))
        metrics = () -> compute_math_metrics(c, style)
        if doc.condition === nothing
            word = _glyph_box(c, () -> "otherwise", () -> metrics().upright)
            return _row(Any[value, word], Symbol[:none, :thick], c, style,
                        Any[(FieldReferenceStep("value"),), nothing])
        end
        condition = _print_math_child(recursion, doc.condition,
                                      make_child_context(ctx, doc, @reference_step condition))
        word = _glyph_box(c, () -> "if", () -> metrics().upright)
        _row(Any[value, word, condition], Symbol[:none, :thick, :thick], c, style,
             Any[(FieldReferenceStep("value"),), nothing, (FieldReferenceStep("condition"),)])
    end))
    _math_iomap(p, doc, build)
end

struct MathCasesToGraphics <: MathProjection
    config::MathConfig
    style::Symbol
end
MathCasesToGraphics(c::MathConfig) = MathCasesToGraphics(c, :display)

function print_document(p::MathCasesToGraphics, recursion, doc::MathCases, ctx)
    style = _style_of(p, ctx)
    c = p.config
    build = Cell(Computation(function ()
        children = Any[]
        for i in 1:length(doc.cases)
            cctx = make_child_context(ctx, doc, (@reference_step cases), (@reference_step [i]))
            push!(children, _print_math_child(recursion, doc.cases[i], cctx))
        end
        # One case per row, left aligned — a case list is not a matrix.
        inner = _grid_left(children, c, style, "cases")
        _delimited(inner, :brace, c, style)
    end))
    _math_iomap(p, doc, build)
end

# A single left-aligned column: the shape a case list wants.
function _grid_left(boxes::Vector, c::MathConfig, style::Symbol, field::String)
    row_gap = () -> compute_math_metrics(c, style).size ÷ 4
    width = Cell(Computation(function ()
        m = compute_math_metrics(c, style)
        w = 0
        for b in boxes
            w = max(w, _box_width(b, m))
        end
        w
    end))
    height = Cell(Computation(function ()
        m = compute_math_metrics(c, style)
        h = 0
        for (i, b) in enumerate(boxes)
            h += _box_ascent(b, m) + _box_descent(b, m)
            i < length(boxes) && (h += row_gap())
        end
        h
    end))
    ascent = Cell(@computation((height[] + 1) ÷ 2 +
                               compute_math_metrics(c, style).axis))
    descent = Cell(@computation height[] - ascent[])
    elements = Any[]
    children = MathChild[]
    for i in eachindex(boxes)
        y = Cell(Computation(function ()
            m = compute_math_metrics(c, style)
            at = 0
            for j in 1:(i - 1)
                at += _box_ascent(boxes[j], m) + _box_descent(boxes[j], m) + row_gap()
            end
            Int32(at)
        end))
        push!(elements, _place(_box_output(boxes[i]), Cell(Int32(0)), y))
        push!(children, MathChild((FieldReferenceStep(field), RangeReferenceStep(i - 1, i)),
                                  boxes[i], Cell(Int32(0)), y))
    end
    _build(elements, width, ascent, descent, children)
end

# ════════════════════════════════════════════════════════════════════════════
# Selection
# ════════════════════════════════════════════════════════════════════════════
#
# A selection in a formula names a whole sub-expression, not a character: a
# fraction, a limit, a variable. That is the tree-selection model — an
# `EmptyReference` on the node itself — and it is the one a two-dimensional
# formula can show, because there is no line of text to put a caret in.

# The wash a selected box paints over itself is the `selection_wash` of the
# config of the rule that draws it. The color cell reads the document's own
# selection, so selecting is a repaint and never a re-layout.

# A selection carries type checkpoints — a whole-element selection on a node is
# an empty path *plus* that node's type — so every comparison here strips them
# first. Comparing the raw path would answer no to a selection the editor made.
_bare(reference) = reference === nothing ? nothing : strip_reference_types(reference)

_is_selected(doc) = _bare(getfield(doc, :selection)[]) isa EmptyReference

function _selection_element(p, doc, build::Cell)
    GraphicsRect(Cell(Int32(0)), Cell(Int32(0)),
                 _int32(() -> build[].width[]),
                 _int32(() -> build[].ascent[] + build[].descent[]),
                 Cell(@computation _is_selected(doc) ? p.config.selection_wash : color_transparent),
                 Cell(Int32(2)), Cell(Int32(2)), Cell(Int32(2)), Cell(Int32(2)),
                 Cell(Int32(0)), Cell(color_transparent), Cell(nothing))
end

# The children of one box, in document order.
_math_children(iomap::MathIoMap) = iomap.child_iomaps::Vector{MathChild}

# Does `reference` start with this child's steps? Answers the tail if it does.
function _peel(child::MathChild, reference)
    rest = reference
    for step in child.steps
        rest isa ConcreteReference || return nothing
        head = rest.head
        if step isa FieldReferenceStep
            (head isa FieldReferenceStep && head.name == step.name) || return nothing
        elseif step isa RangeReferenceStep
            (head isa RangeReferenceStep && head.start == step.start) || return nothing
        else
            return nothing
        end
        rest = rest.tail
    end
    rest
end

"""
A reference to the box itself is its own canvas. A reference into a child is the
node of the child's canvas in this box's canvas, found by identity
(`find_node_reference`), followed by what the child maps the rest to.
"""
function map_reference_forward(p::MathProjection, iomap::MathIoMap, reference)
    reference = _bare(reference)
    reference === nothing && return nothing
    reference isa EmptyReference && return EmptyReference()
    for child in _math_children(iomap)
        rest = _peel(child, reference)
        rest === nothing && continue
        inner = map_reference_forward(child.iomap.projection, child.iomap, rest)
        inner === nothing && return nothing
        outer = find_node_reference(iomap.output, unwrap_cell(child.iomap.output))
        return outer === nothing ? nothing : concat_references(outer, inner)
    end
    nothing
end

"""
A point maps to the child whose placed box holds it, and to this box itself
when no child does — a click on a fraction's rule selects the fraction.
"""
function map_reference_backward(p::MathProjection, iomap::MathIoMap, reference)
    reference isa PointReferenceStep || return nothing
    child = _child_at(iomap, reference.x, reference.y)
    child === nothing && return EmptyReference()
    inner = map_reference_backward(child.iomap.projection, child.iomap,
                                   PointReferenceStep(reference.x - Int(child.x[]),
                                                      reference.y - Int(child.y[])))
    inner === nothing && return EmptyReference()
    annotate_reference_types(iomap.input, _prepend(child.steps, inner))
end

# Build `steps + tail` back into one reference.
function _prepend(steps::Tuple, tail)
    reference = tail
    for i in length(steps):-1:1
        reference = ConcreteReference(steps[i], reference)
    end
    reference
end

# The child whose placed box holds `(x, y)`, or nothing.
function _child_at(iomap::MathIoMap, x::Integer, y::Integer)
    for child in _math_children(iomap)
        box = child.iomap
        left, top = Int(child.x[]), Int(child.y[])
        width = _box_width(box, nothing)
        height = _box_ascent(box, nothing) + _box_descent(box, nothing)
        (left <= x < left + width && top <= y < top + height) && return child
    end
    nothing
end

# `_box_width` and friends take metrics only to place a foreign box on the
# axis; a hit test has no axis to place anything on.
_box_ascent(b::Union{MathIoMap, MathGlyphBox}, ::Nothing) = Int(b.ascent[])
_box_descent(b::Union{MathIoMap, MathGlyphBox}, ::Nothing) = Int(b.descent[])
_box_width(b::Union{MathIoMap, MathGlyphBox}, ::Nothing) = Int(b.width[])
_box_width(b, ::Nothing) = _foreign_size(b)[1]
_box_ascent(b, ::Nothing) = _foreign_size(b)[2]
_box_descent(b, ::Nothing) = 0

"""
A press selects the smallest box under it. The routing is the same descent the
backward map does, so a click and a selection always agree.

A key goes the other way: it is offered to the selected child first, and this
node acts only on what the child declined. That is what makes one small rule per
key add up to whole-tree navigation — a child that cannot go further left hands
the key back, and its parent moves to the previous sibling.
"""
function read_intent(p::MathProjection, iomap::MathIoMap, event)
    event isa MouseClick && event.button === :left &&
        return _select_at(iomap, Int(event.x), Int(event.y))
    (event isa KeyDown || event isa KeyPress) || return nothing
    _read_key(iomap, event)
end

function _select_at(iomap::MathIoMap, x::Integer, y::Integer)
    path = map_reference_backward(iomap.projection, iomap, PointReferenceStep(Int(x), Int(y)))
    path === nothing && return nothing
    ReplaceSelectionOperation(path)
end

# The path to the first (or last) part of a formula — what "the start of this
# content" means where there is no line of text to put a caret at the start of.
# A leaf answers with itself.
function _edge_path(iomap::MathIoMap, first::Bool)
    children = _math_children(iomap)
    isempty(children) && return EmptyReference()
    child = first ? children[1] : children[end]
    content = get_content_iomap(child.iomap)
    inner = content isa MathIoMap ? _edge_path(content, first) : EmptyReference()
    _prepend(child.steps, inner)
end

# The child this node's selection points into, and its position in the child
# list — or `(nothing, 0)` when the selection is this node itself or absent.
function _selected_child(iomap::MathIoMap)
    selection = _bare(getfield(iomap.input, :selection)[])
    selection isa ConcreteReference || return (nothing, 0)
    for (i, child) in enumerate(_math_children(iomap))
        _peel(child, selection) === nothing || return (child, i)
    end
    (nothing, 0)
end

_select_child(iomap::MathIoMap, child::MathChild) =
    ReplaceSelectionOperation(annotate_reference_types(iomap.input,
                                                       _prepend(child.steps, EmptyReference())))

function _read_key(iomap::MathIoMap, event)
    # Ctrl+Home / Ctrl+End mean "the start of this content", and the start of a
    # formula is the formula. The check comes before the descent so the outermost
    # box answers, which is what a container asking a cell to take a selection
    # wants — a table's Enter routes exactly this key into the cell.
    if event isa KeyDown && event.modifiers.ctrl &&
       (event.key === :home || event.key === :end)
        return ReplaceSelectionOperation(
            annotate_reference_types(iomap.input, _edge_path(iomap, event.key === :home)))
    end
    child, index = _selected_child(iomap)
    if child !== nothing
        # Offer it to the child first, and re-root what the child answers so the
        # path stays rooted here.
        answer = read_intent(child.iomap.projection, child.iomap, event)
        answer === nothing || return reroot_operation(answer, child.steps)
        return _move_from(iomap, index, event)
    end
    if !_is_selected(iomap.input)
        # Nothing here is selected: a parent is offering the box a selection —
        # a table cell asks its content to take one on Enter. Take the whole
        # formula, which is the only kind of selection this projection has.
        (event isa KeyDown && (event.key === :return || event.key === :down)) || return nothing
        return ReplaceSelectionOperation(EmptyReference())
    end
    _act_on_selection(iomap, event)
end

# The child declined: move to a sibling, or hand the key on to the parent.
function _move_from(iomap::MathIoMap, index::Int, event)
    children = _math_children(iomap)
    event isa KeyDown || return nothing
    if event.key === :left
        index > 1 && return _select_child(iomap, children[index - 1])
    elseif event.key === :right
        index < length(children) && return _select_child(iomap, children[index + 1])
    elseif event.key === :up || event.key === :escape
        # Out of the child and onto this node.
        return ReplaceSelectionOperation(EmptyReference())
    end
    nothing
end

# This node is the selection: go in, or build something around it.
function _act_on_selection(iomap::MathIoMap, event)
    doc = iomap.input
    children = _math_children(iomap)
    if event isa KeyDown
        (event.key === :down || event.key === :return) && !isempty(children) &&
            return _select_child(iomap, children[1])
        event.key === :backspace && !(doc isa MathInsertion) &&
            return make_replace_document_operation(EmptyReference(), MathInsertion())
        return nothing
    end
    _build_around(doc, event.text)
end

# The build gestures. Each one wraps what is selected and drops the selection
# into the hole it opened, so a formula is typed left to right without a mouse.
function _build_around(doc, text::AbstractString)
    isempty(text) && return nothing
    if doc isa MathInsertion
        # An empty slot takes the character as its content: a letter is a
        # variable, a digit a number.
        character = first(text)
        isletter(character) &&
            return make_replace_document_operation(EmptyReference(), MathVariable(text))
        isdigit(character) &&
            return make_replace_document_operation(EmptyReference(),
                                                    PrimitiveNumber(parse(Int, text)))
    end
    built = text == "/" ? _with_hole(MathFraction(doc, MathInsertion()), "denominator") :
            text == "^" ? _with_hole(MathScript(doc; superscript = MathInsertion()), "superscript") :
            text == "_" ? _with_hole(MathScript(doc; subscript = MathInsertion()), "subscript") :
            text == "(" ? _with_hole(MathParenthesized(doc), "content") :
            nothing
    built === nothing && return nothing
    # The reader does not touch the document: the trailing selection write of
    # `make_replace_document_operation` moves the selection into the new hole, and setting
    # a selection clears every other one in the tree.
    make_replace_document_operation(EmptyReference(), built)
end

# Point a freshly built node's own selection at the hole it opened, which is
# where `make_replace_document_operation` then leaves the editor's selection.
function _with_hole(document, field::AbstractString)
    getfield(document, :selection)[] =
        ConcreteReference(FieldReferenceStep(field), EmptyReference())
    document
end

# ════════════════════════════════════════════════════════════════════════════
# The composite
# ════════════════════════════════════════════════════════════════════════════

"""
    MathToGraphics(; measure, theme = nothing, style, font = nothing, slanted = nothing,
                    ink = nothing, hint = nothing) -> TypeDispatchingProjection

Every math rule, sharing one configuration. Splice `.dispatch` into a bigger
table the way `WidgetToGraphics(…).dispatch` is spliced, so a formula renders
the same wherever it appears.

`theme` is a `MathTheme`, scaled or not, or `nothing` for the default values.
`font`, `slanted`, `ink` and `hint` each give a fixed value when they are not
`nothing`, and the theme's own value otherwise.

`style` is the style level of the root: `:display` sets a formula on its own
line (limits above and below a sum, a taller fraction) and `:text` sets it in a
line of prose.
"""
function MathToGraphics(; measure::TextMeasure = FontFileMeasure(),
                        theme = nothing,
                        style::Symbol = :display,
                        font::Union{StyleFont,Nothing} = nothing,
                        slanted::Union{StyleFont,Nothing} = nothing,
                        ink::Union{StyleColor,Nothing} = nothing,
                        hint::Union{StyleColor,Nothing} = nothing)
    c = MathConfig(; theme, measure,
                     font = something(font, get_math_style(theme, :font)),
                     slanted = something(slanted, get_math_style(theme, :slanted_font)),
                     ink = something(ink, get_math_style(theme, :ink)),
                     hint = something(hint, get_math_style(theme, :hint)))
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

"""
    make_math_to_graphics_dispatch(; kwargs...) -> Vector{Pair{Type,Any}}

The math rules alone, for splicing into a bigger table. `MathToGraphics` also
claims `PrimitiveNumber` and `PrimitiveString`, which is right for a table that
holds nothing else and wrong for a renderer that already knows what a number is;
this drops those two entries and keeps the rest.

A number inside a formula then renders through the surrounding renderer and
lands on the formula's baseline anyway: a foreign box that draws text reports
that text's baseline.
"""
make_math_to_graphics_dispatch(; kwargs...) =
    Pair{Type,Any}[entry for entry in MathToGraphics(; kwargs...).dispatch
                   if first(entry) !== PrimitiveNumber && first(entry) !== PrimitiveString]

# ── Natural-projection registration ─────────────────────────────────────────
# A formula is set, not spelled: it goes to its own typesetter, which places
# real two-dimensional boxes. The rows are spliced one type at a time, so every
# child of a formula re-enters the natural renderer — which is what lets a
# formula hold an embedded document, and a number inside one render through the
# shared primitive path and still land on the formula's baseline.


