# Fragment of `TextModule`.
#
# The text domain bridges the structural (syntax tree) and visual (graphics) domains.
# Text is stored as a flat sequence of spans, each with its own reactive style and color.
# The selection is a flat character offset, making keyboard navigation straightforward
# before the pixel-coordinate layout is applied.
#
# The domain includes:
# - **Span types**: `TextString` (text content), `TextNewline` (line break), `TextSpacing` (spacing), `TextGraphics` (embedded graphics)
# - **Container type**: `TextBlock` (sequence of spans)
# - **Base type**: `TextDocument` abstract type for all text documents
# - **Insertion kit** (`@domain Text`): `TextNothing` (the empty-text placeholder) and
#   `TextInsertion` (the typed-name buffer Insert opens on it)
#
# Selection semantics (`[i]` = 1-based item, `{k}` = 0-based cursor):
# - Spans: `.content{k}` — cursor at boundary k within the span's content
# - TextBlock: `.elements[i]` — the i-th span, then `.content{k}` for the cursor within it
#
# Each span has reactive styling fields:
# - `font` — font style (e.g., "bold", "italic", "monospace")
# - `font_color` — text color (name, hex, or rgb)
# - `fill_color` — background fill color
# - `line_color` — border/line color
# - `padding` — inset/padding value
# the flat-offset seam a projection over text reads

# ── The Text domain kit ───────────────────────────────────────────────────
#
# `TextDocument` (the exported abstract root every concrete text type subtypes;
# `@document` injects the `selection::Union{Nothing, Reference}` field the `Document` contract
# requires), `TextNothing` (the empty-text placeholder), `TextInsertion` (the
# typed-name buffer completing over the Text candidates), the Insert-key gesture
# turning one into the other, and the traits wiring them together.

@domain Text

# ── TextNewline ─────────────────────────────────────────────────────

"""
    TextNewline

Represents a line break in text. All styling fields are reactive cells for
incremental updates.

# Fields

- `font::Cell{StyleFont}` — font specification
- `font_color::Cell` — text color
- `fill_color::Cell` — background fill color
- `line_color::Cell` — border/line color
- `padding::Cell` — inset/padding value

# Constructor

- `TextNewline(; font, font_color=nothing, fill_color=nothing, line_color=nothing, padding=nothing)`
  — the macro's keyword constructor; `font` is the one field without a default,
  and so the one required keyword.
"""
@document struct TextNewline <: TextDocument
    font::StyleFont
    font_color::Union{StyleColor, Nothing} = nothing
    fill_color::Union{StyleColor, Nothing} = nothing
    line_color::Union{StyleColor, Nothing} = nothing
    padding::Union{Inset, Nothing} = nothing
end

# ── TextSpacing ─────────────────────────────────────────────────────

"""
    TextSpacing

Represents horizontal or vertical spacing in text. The size can be specified
in pixels or character spaces.

# Fields

- `size::Cell` — holds the spacing size as `Number`
- `unit::Cell` — holds the unit as `Symbol` (`:pixel` or `:space`)
- `font::Cell{StyleFont}` — font specification
- `font_color::Cell` — text color
- `fill_color::Cell` — background fill color
- `line_color::Cell` — border/line color
- `padding::Cell` — inset/padding value

# Constructor

- `TextSpacing(size::Number; unit=:pixel, font, font_color=nothing, fill_color=nothing, line_color=nothing, padding=nothing)`
"""
@document struct TextSpacing <: TextDocument
    size::Number
    unit::Symbol
    font::StyleFont
    font_color::Union{StyleColor, Nothing}
    fill_color::Union{StyleColor, Nothing}
    line_color::Union{StyleColor, Nothing}
    padding::Union{Inset, Nothing}
end

TextSpacing(size::Number; unit=:pixel, font, font_color=nothing, fill_color=nothing, line_color=nothing, padding=nothing) =
    TextSpacing(Cell(size), Cell(unit), Cell(font), Cell(font_color), Cell(fill_color), Cell(line_color), Cell(padding), Cell(nothing))

# ── TextString ─────────────────────────────────────────────────────

"""
    TextString(content, font, font_color)

A single text span. `content` is a reactive `Cell` (it is edited in place — you
type into it). `font` and `font_color` default to an **`ImmutableCell`**: a span's
typography is authored, not edited through the cell, so it needs no dependent edge
(a shared font/colour is read by every downstream glyph, which is where the
reactive version's fanout came from). Pass an explicit `Cell` for either to make it
reactive — as the conversation editor does for a live commit colour. The remaining
style fields stay reactive (highlighting writes `fill_color`).

- `content::Cell`                         — holds `AbstractString`
- `font::ImmutableCell{StyleFont}`        — font specification (immutable by default)
- `font_color::ImmutableCell{StyleColor}` — text colour (immutable by default)
- `fill_color::Cell` — holds background fill color or `nothing`
- `line_color::Cell` — holds border/line color or `nothing`
- `padding::Cell`    — holds inset/padding value or `nothing`
- `pointer_shape::Cell` — holds the shape of the pointer over the span, one of
  `POINTER_SHAPES`, such as `:pointing_hand` over a link, or `nothing` for the
  I-beam of the text around it

When a `TextBlock` selection path descends into a span, the sub-path
refers to the cursor within the span's `content` field:  `.content{k}`
"""
@document struct TextString <: TextDocument
    content::AbstractString
    font::ImmutableCell{StyleFont}
    font_color::ImmutableCell{StyleColor}
    fill_color::Union{StyleColor, Nothing}
    line_color::Union{StyleColor, Nothing}
    padding::Union{Inset, Nothing}
    pointer_shape::Any
end

"""
    UNSTYLED_TEXT_FONT

The font of a text that names none: a run that a document makes with no font,
and the line of a block with no run. It is a default of the text document, the
content that an author leaves out, and not a style of a projection.
"""
const UNSTYLED_TEXT_FONT = StyleFont("Ubuntu Mono", 14)  # @style: content of the document

# font / font_color are passed RAW so they land in their ImmutableCell default;
# content stays a reactive Cell. Passing a Cell for font/colour overrides the default.
TextString(content::AbstractString, font::StyleFont, font_color::StyleColor) =
    TextString(Cell(content), font, font_color, Cell(nothing), Cell(nothing), Cell(nothing), Cell(nothing))

# A space, a newline or an empty text between two parts draws no ink, so it names
# only its font, which sets its width and its line; its color is the default
# color of a text.
TextString(content::AbstractString, font::StyleFont) = TextString(content, font, color_default)

TextString(content::AbstractString) =
    TextString(Cell(content), UNSTYLED_TEXT_FONT, color_default, Cell(nothing), Cell(nothing), Cell(nothing), Cell(nothing))

TextString(content::Function, font::StyleFont, font_color::StyleColor) =
    TextString(Cell(Computation(content)), font, font_color, Cell(nothing), Cell(nothing), Cell(nothing), Cell(nothing))

# StyleText bridge: a projection holding a merged (font, color) style value can
# build a run without unpacking it. The document model itself is unchanged —
# `style` is split into the existing `font` / `font_color` cells.
TextString(content::AbstractString, style::StyleText) = TextString(content, style.font, style.color)
TextString(content::Function,      style::StyleText) = TextString(content, style.font, style.color)

# A run in a style, with the shape of the pointer over it, or `nothing`.
TextString(content::AbstractString, style::StyleText, pointer_shape::Union{Nothing,Symbol}) =
    TextString(Cell(content), style.font, style.color, Cell(nothing), Cell(nothing), Cell(nothing),
               Cell(pointer_shape), Cell(nothing))
TextString(content::Function, style::StyleText, pointer_shape::Union{Nothing,Symbol}) =
    TextString(Cell(Computation(content)), style.font, style.color, Cell(nothing), Cell(nothing), Cell(nothing),
               Cell(pointer_shape), Cell(nothing))

# A text span that shows a muted placeholder while the value is empty. Both text
# and colour are reactive, so the hint disappears the moment the user types.
function make_hinted_text(content_thunk; empty_thunk, placeholder::AbstractString,
                          style::StyleText, pointer_shape::Union{Nothing,Symbol} = nothing)
    TextString(
        Cell(@computation empty_thunk() ? placeholder : content_thunk()),
        style.font,                                                        # immutable (authored font)
        Cell(@computation empty_thunk() ? color_solarized_gray : style.color),   # reactive (hint colour); @style: content of the document
        Cell(nothing), Cell(nothing), Cell(nothing), Cell(pointer_shape), Cell(nothing))
end

# ── TextGraphics ─────────────────────────────────────────────────────

"""
    TextGraphics

Embeds a graphics document (typically an `ImageDocument`) within text as an
inline image or icon. The image flows as a single unbreakable glyph: it
contributes its height to the line and occupies one position of the flat caret
space, so a caret stands before it and after it.

An image has no font and no colour. A caret beside it, and a run typed beside
it, take the style of the nearest text run of its line.

# Fields

- `content::Cell` — holds the embedded `Document` (e.g. `ImageFile`, `ImageMemory`)
- `width::Cell{Int32}` — display width in pixels
- `height::Cell{Int32}` — display height in pixels
- `fill_color::Cell` — background fill color
- `line_color::Cell` — border/line color
- `padding::Cell` — inset/padding value

# Constructors

- `TextGraphics(content, width, height; fill_color, line_color, padding)`
- `TextGraphics(content; fill_color, line_color, padding)` — zero size
"""
@document struct TextGraphics <: TextDocument
    content::Document
    width::Int32
    height::Int32
    fill_color::Union{StyleColor, Nothing}
    line_color::Union{StyleColor, Nothing}
    padding::Union{Inset, Nothing}
end

TextGraphics(content, width::Integer, height::Integer; fill_color=nothing, line_color=nothing, padding=nothing) =
    TextGraphics(Cell(content), Cell(Int32(width)), Cell(Int32(height)), Cell(fill_color), Cell(line_color), Cell(padding), Cell(nothing))

TextGraphics(content; fill_color=nothing, line_color=nothing, padding=nothing) =
    TextGraphics(Cell(content), Cell(Int32(0)), Cell(Int32(0)), Cell(fill_color), Cell(line_color), Cell(padding), Cell(nothing))

# The character that stands for an inline image in the flat characters and in the
# string of a text: U+FFFC OBJECT REPLACEMENT CHARACTER, the Unicode character for
# an object in text.
const OBJECT_REPLACEMENT_CHARACTER = '\uFFFC'

# ── TextBlock ───────────────────────────────────────────────────────────

"""
    TextBlock(spans)

A sequence of `TextString` spans. The span list is a reactive `Cell`
holding `Vector{TextString}`, so structural changes (add/remove spans)
are tracked alongside per-span value changes.

The `selection` cell holds a path into the span sequence, or `nothing`:
  `.elements[i]`  — cursor within element i
"""
@document struct TextBlock <: TextDocument
    elements::CollectionDocument = CellVector()
end

TextBlock(spans::Vector{<:TextDocument}) =
    TextBlock(CellVector(Cell[Cell(s) for s in spans]), Cell(nothing))

TextBlock(spans::TextDocument...) =
    TextBlock(CellVector(Cell[Cell(s) for s in spans]), Cell(nothing))

TextBlock(f::Function) = TextBlock(CellVector(Computation(f)), Cell(nothing))

# ── TextLine ───────────────────────────────────────────────────────────

"""
    TextLine(spans...; indentation = 0, gutter = nothing, fold = nothing)

One line of a `TextBlock`: a sequence of spans that **contains no line break** and
**implies one before itself**. A block of `n` lines therefore renders with `n-1`
breaks — the break is a *separator*, so a line-structured block has no phantom
trailing blank line.

`indentation` is the line's leading indent in spaces. It is a **property of the
line, not a span**: no caret can land inside it, and a projection that indents
does not have to emit (and later re-find) a whitespace `TextString`.

The invariant — no `TextNewline` element, and no `TextString` whose content embeds
a `'\\n'` — is a producer-side convention; nothing enforces it yet, since a span's
content is a reactive cell that can grow a newline after construction.

A block's elements are meant to be *either* spans *or* lines, not a mix. Mixing
degrades gracefully rather than erroring (a line still breaks before itself), but
the flat character offsets get hard to reason about, and no projection produces
such a block.

`gutter` is what the gutter shows beside the line: any document that the
recursion prints to graphics, such as a [`TextGutter`](@ref), or `nothing`. It is
a property of the line too: it is not in the caret space and not in the flat
string, and it stays with the line when lines are added above it.
`TextBlockToScrollLayout` draws it at the height of the line.

`fold` is the [`TextFold`](@ref) that starts at this line, or `nothing`: a region
of this line and the lines after it, which `TextFolding` hides but this one when
it is closed.

`soft_breaks` are the places where the line wraps: each is a character offset in
the text of its spans, where an image counts one, and a new row of the line
starts before that character. `WordWrapping` computes them for the width of the
view, and `TextToGraphics` starts a row at each, at the indentation of the line.
A soft break is no character: it is not in the caret space and not in the flat
string, so a wrap moves no offset. The field names its kind, so it holds the vector
of offsets as one value that a computation gives whole, not as a list.
"""
@document struct TextLine <: TextDocument
    elements::CollectionDocument = CellVector()
    indentation::Int = 0
    gutter::Union{Document, Nothing} = nothing
    fold::Union{Document, Nothing} = nothing
    soft_breaks::ReactiveCell{Vector{Int}} = Int[]
end

TextLine(spans::Vector{<:TextDocument}; indentation::Integer = 0, gutter = nothing, fold = nothing) =
    TextLine(CellVector(Cell[Cell(s) for s in spans]), Cell(Int(indentation)), Cell(gutter),
             Cell(fold), Cell(Int[]), Cell(nothing))

TextLine(spans::TextDocument...; indentation::Integer = 0, gutter = nothing, fold = nothing) =
    TextLine(collect(TextDocument, spans); indentation, gutter, fold)

TextLine(f::Function; indentation::Integer = 0, gutter = nothing, fold = nothing) =
    TextLine(CellVector(Computation(f)), Cell(Int(indentation)), Cell(gutter), Cell(fold),
             Cell(Int[]), Cell(nothing))

# A lone line is not a document — it is a part of a block. Both of its fields are
# defaulted, so unlike the span types (each has a required field, and so no
# zero-arg constructor) `TextLine` *is* zero-arg constructible and would become a
# completion candidate on its own: committable at a top-level insertion, where the
# committed document is the root and the text pipeline prints a `TextBlock`, not a
# line. It would also make `text` ambiguous — both `text block` and `text line`
# start with it. Opt out, as `@domain` does for its own placeholder.
DomainModule.insertable(::Type{<:TextLine}) = false

# ── TextGutter ─────────────────────────────────────────────────────────

"""
    TextGutter(; marker = nothing, number = nothing, fold = nothing)

The gutter of a line of code: a lane for a marker, such as a breakpoint or a
diagnostic, a lane for the number of the line, and a lane for the triangle of a
fold. Each field holds a mark, any document that the recursion prints to graphics,
or `nothing`. A stage fills its field by name, and `TextGutterToGraphics` lays the
lanes out. A view that wants other lanes brings a gutter type of its own and a
projection for it.
"""
@document struct TextGutter <: TextDocument
    marker::Union{Document, Nothing} = nothing
    number::Union{Document, Nothing} = nothing
    fold::Union{Document, Nothing} = nothing
end

# A gutter is a part of a line, not a document to insert on its own; like a line,
# it has only defaulted fields and would be a candidate of the insertion.
DomainModule.insertable(::Type{<:TextGutter}) = false

# ── TextFold ───────────────────────────────────────────────────────────

"""
    TextFold(; line_count = 0, collapsed = false, placeholder = nothing)

A region of lines that can fold: the line whose `fold` it is and the
`line_count` lines after it. While it is `collapsed`, `TextFolding` hides all its
lines but the first one, and puts `placeholder` at the end of the first one, or
`…` when it is `nothing`. The lines stay in the text, so a number counts them.
A projection that makes the region can give it the `collapsed` cell of the part
it shows, so the state stays in the document. `ToggleCollapseOperation` flips it.
"""
@document struct TextFold <: TextDocument
    line_count::Int = 0
    collapsed::Bool = false
    placeholder::Union{Document, Nothing} = nothing
end

# A fold is a part of a line, not a document to insert on its own.
DomainModule.insertable(::Type{<:TextFold}) = false

# ── Span coordinates ──────────────────────────────────────────────────────
#
# A span's coordinate within a block is an *index path*, not a single index:
# `[i]` is the i-th element of the block, `[i, j]` the j-th span of the
# `TextLine` at element i. The cursor, word-motion and editing helpers all walk
# these, so a block of lines and a flat block of spans are the same code — as does
# `TextToGraphics`, which keys its coordinate table (`SegmentCoordinate.span_path`) by them.
const SpanPath = Vector{Int}

# The document a committed `text` insertion becomes. Without this the generic
# `make_insertion_document` fallback builds a bare `TextBlock()` — no spans, no
# selection — and the `@gestures TextBlock` character rules all decline for want of
# a `.elements[i].content{k}` caret, so the freshly inserted text takes no
# keystrokes. One empty span with the caret in it is the smallest typeable text.
#
# The span types (`TextString`, `TextNewline`, `TextSpacing`, `TextGraphics`) get
# no factory on purpose: each has a required field, so none is zero-arg
# constructible, and none is therefore a completion candidate. A factory would
# make them committable at a *top-level* insertion, where a lone span is the root
# document — and the text pipeline prints a `TextBlock`, not a bare span. Making
# spans insertable belongs with a caret-level "insert a span here" gesture.
@insertion TextBlock = @selected TextBlock([TextString("")]) elements[1].content{0}


# ── splice_value! methods for the text representations ──────────────
#
# These are the two non-string representations of `splice_value!` (declared in
# OperationModule). They fire when a replace reference resolves to a field
# whose *value* is a styled span or a flat span sequence — e.g. a SyntaxLeaf's
# `open`/`value`/`close` (each a TextString) or a BookParagraph's TextBlock
# content. When the target is itself a TextString edited by its `content` field,
# the value read from the field is a plain `String` and the generic
# AbstractString method handles it — no TextString-target method is needed.

# Field value is a styled span: splice its content in place (owner unchanged).
splice_value!(owner, field::Symbol, span::TextString, s::Int, e::Int, replacement::AbstractString) =
    (span.content = splice_string(span.content::AbstractString, s, e, replacement); span)

# Field value is a flat span sequence: the incoming `[s, e]` is a range of the
# flat caret space (`get_flat_offsets`), the space of `get_flat_string`. Locate
# the single `TextString` span the range falls inside and edit it; at the seam of
# two spans, the earlier one. Beside an inline image, the edit of
# `_make_image_edit` is made in place: a new run where no span holds an insertion,
# and a range of only images removed, or replaced by one run. An empty sequence
# grows a fresh span. Ranges that straddle two spans are left for a later
# multi-span editing pass.
function splice_value!(owner, field::Symbol, text::TextBlock, s::Int, e::Int, replacement::AbstractString)
    infos = _text_span_infos(text)
    for (path, len) in infos
        base = get_flat_base(text, path)
        if s >= base && e <= base + len
            span = _span_at(text, path)
            span.content = splice_string(span.content::AbstractString, s - base, e - base, replacement)
            return text
        end
    end
    _splice_beside_image!(text, s, e, replacement) && return text
    isempty(infos) && push!(text.elements, TextString(replacement))
    text
end

# The in-place form of `_make_image_edit`. Answers whether the edit was one beside
# an image.
function _splice_beside_image!(text::TextBlock, s::Int, e::Int, replacement::AbstractString)
    if s == e
        isempty(replacement) && return false
        place = _find_flat_image_place(text, s)
        place === nothing && return false
        path, char = place
        insert!(_get_container(text, path), path[end] + char,
                _make_styled_run(replacement, _find_style_span(text, path)))
        return true
    end
    paths = _find_image_range(text, s, e)
    paths === nothing && return false
    container = _get_container(text, paths[1])
    run = isempty(replacement) ? nothing : _make_styled_run(replacement, _find_style_span(text, paths[1]))
    for _ in paths
        deleteat!(container, paths[1][end])
    end
    run === nothing || insert!(container, paths[1][end], run)
    true
end

# The element list that holds the span at `path`.
_get_container(text::TextBlock, path::SpanPath) =
    length(path) == 1 ? text.elements : text.elements[path[1]].elements

# The span document at `path` (the caller has already established it is one).
_span_at(text::TextBlock, path::SpanPath) =
    length(path) == 1 ? text.elements[path[1]] : text.elements[path[1]].elements[path[2]]

# ── read_gesture via reified @gestures: geometry-free text editing ───────
#
# The projection-independent half of the Text domain's reader, now a reified
# `@gestures` table on `TextBlock` (was a `read_gesture(::TextBlock)` method); the
# generic `read_bound_gesture` interpreter fires it, so the table that fires is
# the one gesture-help enumerates. It reads only the span structure
# (`text.elements`) and the flat-character `text.selection` — never pixel geometry.
# The geometry-DEPENDENT gestures (visual up/down, plain Home/End, mouse clicks)
# stay in `TextToGraphics`, which needs the laid-out coordinate map.
#
# Gestures match modifiers *exactly* (`KeyDown(:left;)` — note the `;`: no
# modifiers — is the plain-Left gesture; `Ctrl+Left` and `Alt+Left` are distinct).
# This is why the old reader's explicit "decline" arms vanish: `Alt+arrow` (a tree
# gesture) and `Tab` simply have no binding here and so propagate inward; a plain
# arrow while a *whole element* is selected is declined inside the char-motion
# operation (which reads `text.selection`). The old reader matched these arrows
# loosely and filtered the declines out by hand; exact matching is equivalent for
# every tested/real input and lets the absence of a binding be the decline.
@gestures TextBlock begin
    KeyPress(_, t)         => "Insert character"     => _text_insert(doc, t)
    KeyDown(:period; ctrl) => "Toggle collapse"      => ToggleCollapseOperation()
    KeyDown(:backspace;)   => "Delete backward"      => _text_delete(doc, :backspace)
    KeyDown(:delete;)      => "Delete forward"       => _text_delete(doc, :delete)
    KeyDown(:home; ctrl)   => "Cursor to text start" => _text_jump(doc, :start)
    KeyDown(:end; ctrl)    => "Cursor to text end"   => _text_jump(doc, :end)
    KeyDown(:left; ctrl)   => "Word left"            => _text_word_motion(doc, :left)
    KeyDown(:right; ctrl)  => "Word right"           => _text_word_motion(doc, :right)
    KeyDown(:left;)        => "Cursor left"          => _text_char_motion(doc, :left)
    KeyDown(:right;)       => "Cursor right"         => _text_char_motion(doc, :right)
    KeyDown(:left; shift)        => "Extend the selection left"         => _text_extend(doc, :left)
    KeyDown(:right; shift)       => "Extend the selection right"        => _text_extend(doc, :right)
    KeyDown(:left; ctrl, shift)  => "Extend the selection a word left"  => _text_extend(doc, :word_left)
    KeyDown(:right; ctrl, shift) => "Extend the selection a word right" => _text_extend(doc, :word_right)
    KeyDown(:home; ctrl, shift)  => "Extend the selection to the start" => _text_extend(doc, :start)
    KeyDown(:end; ctrl, shift)   => "Extend the selection to the end"   => _text_extend(doc, :end)
end

# ── Flat character-cursor helpers ─────────────────────────────────────────
#
# The text cursor is a single flat offset into the block's concatenated rendered
# stream (the `get_flat_offsets` / `get_flat_length` space, which counts
# TextNewline / TextSpacing / TextLine indentation and the implicit inter-line
# break). Every offset `0 … total` is a valid caret rest, so character motion is
# `± 1` clamped — no span bookkeeping and no boundary-duplicate skip: the *same*
# visual caret has exactly one representation regardless of travel direction, and
# a within-line span boundary collapses to a single offset while a line boundary
# stays a distinct pair separated by the break. These are geometry-free, so they
# live on the Text domain alongside `read_gesture`.

# Total flat length of the block — mirrors `get_flat_offsets`' accounting (the
# `+1` before every TextLine but the first is the implicit break).
function _text_flat_total(text::TextBlock)
    total = 0
    for (k, el) in enumerate(text.elements)
        (el isa TextLine && k > 1) && (total += 1)   # implicit inter-line break
        total += get_flat_length(el)
    end
    total
end

# The rendered character stream as a `Vector{Char}`, one entry per flat position
# (so `length` equals `_text_flat_total`). Used by word motion and edit
# classification; must stay in lockstep with `get_flat_length` / `_text_flat_total`.
function _flat_chars(text::TextBlock)
    chars = Char[]
    for (k, el) in enumerate(text.elements)
        (el isa TextLine && k > 1) && push!(chars, '\n')   # implicit inter-line break
        _push_flat_chars!(chars, el)
    end
    chars
end
_push_flat_chars!(chars, s::TextString) = append!(chars, collect(s.content::AbstractString))
_push_flat_chars!(chars, ::TextNewline)  = push!(chars, '\n')
_push_flat_chars!(chars, ::TextSpacing)  = push!(chars, ' ')
_push_flat_chars!(chars, ::TextGraphics) = push!(chars, OBJECT_REPLACEMENT_CHARACTER)
_push_flat_chars!(chars, ::TextDocument) = chars          # no position, as in get_flat_length
function _push_flat_chars!(chars, line::TextLine)
    for _ in 1:line.indentation
        push!(chars, ' ')
    end
    for span in line.elements
        _push_flat_chars!(chars, span)
    end
    chars
end

"""
    get_flat_string(text::TextBlock) -> String

The text as one string, one character for each position of the flat caret space
(`get_flat_offsets`): a break for a `TextNewline` and for the break before a
`TextLine`, a space for a `TextSpacing` and for each column of indentation, and
U+FFFC for an inline image. An offset into the string is a flat offset.
"""
get_flat_string(text::TextBlock) = String(_flat_chars(text))

# The flat text selection `(start, stop)` — from a flat `TextRangeReferenceStep` head,
# or a structural `.content{a:b}` caret canonicalised to its flat offsets — else
# `nothing` (no caret, or a whole-element `∅` / `TextSpanReferenceStep`).
# The path defaults to the block's own live selection. A caller that has to read a
# **dormant** one — the pale caret of a pane that does not have the focus — hands
# the stored path in, because the property answers `nothing` for a dormant
# selection by design.
_text_flat_selection(text::TextBlock) = _text_flat_selection(text, text.selection)
function _text_flat_selection(text::TextBlock, selection)
    sel = strip_reference_types(selection)
    if sel isa ConcreteReference && sel.head isa TextRangeReferenceStep && sel.tail isa EmptyReference
        return (sel.head.start, sel.head.stop)
    end
    # A structural `.elements[i].content{a:b}` caret — e.g. the one a value edit's
    # `evaluate_operation` leaves behind, before a re-projection re-flattens it —
    # denotes a flat range too. Canonicalise it so the flat readers (motion, edit)
    # can act on it and re-emit the caret in the canonical flat form. Whole-element
    # `∅` / `TextSpanReferenceStep` selections are not `.content` ranges, so they still
    # return nothing here and keep declining (the syntax layer tree-navigates them).
    rng = _text_selection_range(text, selection)
    rng === nothing && return nothing
    path, a, b = rng
    base = get_flat_base(text, path)
    base === nothing ? nothing : (base + a, base + b)
end

# The selection reference for a flat caret / range, rooted at the TextBlock.
# Emitted plain; `set_selection!` canonicalises (adds the folded checkpoints).
make_flat_caret_reference(pos::Int) =
    ConcreteReference(TextRangeReferenceStep(pos, pos), EmptyReference())

"""
    make_flat_range_reference(start, stop) -> Reference

The selection reference for the flat character range `start..stop` of a
`TextBlock`, with `start <= stop`. `start == stop` is the caret of
[`make_flat_caret_reference`](@ref).
"""
make_flat_range_reference(start::Int, stop::Int) =
    ConcreteReference(TextRangeReferenceStep(start, stop), EmptyReference())

"""
    get_flat_caret(block, ref) -> Int | nothing

The flat caret offset a selection reference denotes over `block`, resolved from
**either** representation a text caret takes: the flat `TextRangeReferenceStep{k}` form
(the domain's canonical caret) or the structural `.elements[i].content{k}` form (the
caret a *lowered* `ReplaceStringRangeOperation` leaves behind after a character edit).
`nothing` for a range, a whole-element `∅` / `TextSpanReferenceStep` selection, or any
non-caret shape.

The text→text decorators (`WordWrapping`, `LineNumbering`, `TextFiltering`,
`TextHighlighting`, `SelectionInverting`) forward-map the cursor through this, so the
caret renders no matter which representation the last operation left on the block —
without it, a structural caret maps to nothing and the cursor disappears after an edit.
"""
function get_flat_caret(block::TextBlock, ref)
    sel = strip_reference_types(ref)
    if sel isa ConcreteReference && sel.head isa TextRangeReferenceStep && sel.tail isa EmptyReference
        return sel.head.start == sel.head.stop ? sel.head.start::Int : nothing
    end
    rng = _parse_selection_range(sel)
    rng === nothing && return nothing
    path, a, b = rng
    a == b || return nothing                       # a range has no single caret offset
    base = get_flat_base(block, path)
    base === nothing ? nothing : base + a
end

# The flat caret resolved to a `(span, char)` pair for the renderer / line-motion
# geometry, or `nothing` when there is no caret, the selection is a range, or the
# caret falls in a break / indentation gap with no owning span. The span is a text
# run, or an inline image with char 0 before it and char 1 after it
# (`_find_flat_place`). `get_flat_base` supplies the span's flat base.
get_flat_cursor_coordinate(text::TextBlock) = get_flat_cursor_coordinate(text, text.selection)
# The span and the character a flat offset lands on, in the shape of
# `get_flat_cursor_coordinate`, or `nothing` on a break or gap.
function _text_flat_span(text::TextBlock, flat::Int)
    loc = _find_flat_place(text, flat)
    loc === nothing ? nothing : (span = loc[1], char = loc[2])
end

function get_flat_cursor_coordinate(text::TextBlock, selection)
    sel = _text_flat_selection(text, selection)
    sel === nothing && return nothing
    sel[1] == sel[2] || return nothing            # a range has no single char cursor
    _text_flat_span(text, sel[1])
end

# Standard editor word class: letters, digits, and underscore are "word" chars;
# an inline image is a word of its own; everything else (including breaks and
# spacing) is a separator.
_is_word_char(c) = isletter(c) || isdigit(c) || c == '_'
_is_image_char(c) = c == OBJECT_REPLACEMENT_CHARACTER
_is_separator_char(c) = !_is_word_char(c) && !_is_image_char(c)

# Ctrl+Right: from flat `f`, skip the current word run (or the one image) then the
# separator run → next word start. `chars` is the flat stream (`chars[f+1]` is
# the char right of caret `f`); `n == length(chars)`.
function _word_right_flat(chars, f::Int, n::Int)
    if f < n && _is_image_char(chars[f + 1])
        f += 1
    else
        while f < n && _is_word_char(chars[f + 1]); f += 1; end
    end
    while f < n && _is_separator_char(chars[f + 1]); f += 1; end
    f
end

# Ctrl+Left: skip the separator run then the word run, or the one image
# (`chars[f]` is the char left of caret `f`).
function _word_left_flat(chars, f::Int)
    while f > 0 && _is_separator_char(chars[f]); f -= 1; end
    if f > 0 && _is_image_char(chars[f])
        f -= 1
    else
        while f > 0 && _is_word_char(chars[f]); f -= 1; end
    end
    f
end

# ── Reified-gesture operations ────────────────────────────────────────────
#
# Each builds the Operation for one `@gestures TextBlock` rule from the document
# and its selection (the gesture's modifiers are matched in the pattern, so these
# take no event). They return `nothing` to decline — e.g. when the selection is
# not a character cursor — so the gesture keeps propagating inward.

# The (path, content-length) of every TextString span, in document order — the
# span layout the cursor/word helpers walk.
function _text_span_infos(text::TextBlock)
    infos = Tuple{SpanPath,Int}[]
    for (i, el) in enumerate(text.elements)
        if el isa TextString
            push!(infos, ([i], length(el.content::AbstractString)))
        elseif el isa TextLine
            for (j, span) in enumerate(el.elements)
                span isa TextString || continue
                push!(infos, ([i, j], length(span.content::AbstractString)))
            end
        end
    end
    infos
end

# The path of every inline image, in document order, at either depth.
function _collect_image_paths(text::TextBlock)
    paths = SpanPath[]
    for (i, el) in enumerate(text.elements)
        if el isa TextGraphics
            push!(paths, Int[i])
        elseif el isa TextLine
            for (j, span) in enumerate(el.elements)
                span isa TextGraphics && push!(paths, Int[i, j])
            end
        end
    end
    paths
end

# Insert (replace the selected flat range with) `str` at the text cursor. Produces
# a `ReplaceTextRangeOperation` in the flat coordinate; it is lowered to a
# span/domain edit as it threads up the projection chain.
function _text_insert(text::TextBlock, str::AbstractString)
    sel = _text_flat_selection(text)
    sel === nothing && return nothing
    ReplaceTextRangeOperation(make_flat_range_reference(sel[1], sel[2]), str)
end

# Backspace / Delete: the flat range to remove. A non-empty selection is deleted;
# a caret removes the char before it (backspace) / after it (delete), clamped at
# the ends. Whether a range that crosses a span/break boundary actually applies is
# decided when the op is lowered (v1: a cross-span range declines).
function _text_delete(text::TextBlock, key::Symbol)
    sel = _text_flat_selection(text)
    sel === nothing && return nothing
    s, e = sel
    if s != e
        rng = (s, e)
    elseif key === :backspace
        s > 0 || return nothing
        rng = (s - 1, s)
    else  # :delete
        n = _text_flat_total(text)
        s < n || return nothing
        rng = (s, s + 1)
    end
    ReplaceTextRangeOperation(make_flat_range_reference(rng[1], rng[2]), "")
end

# Ctrl+Home / Ctrl+End: caret to flat offset 0 / the total flat length.
function _text_jump(text::TextBlock, where::Symbol)
    ReplaceSelectionOperation(make_flat_caret_reference(where === :start ? 0 : _text_flat_total(text)))
end

# Ctrl+Left / Ctrl+Right: word-wise cursor motion over the flat stream. Acts on
# the near end of the selection (left end for :left, right end for :right).
function _text_word_motion(text::TextBlock, direction::Symbol)
    sel = _text_flat_selection(text)
    sel === nothing && return nothing
    chars = _flat_chars(text)
    newf = direction === :left ?
        _word_left_flat(chars, sel[1]) :
        _word_right_flat(chars, sel[2], length(chars))
    ReplaceSelectionOperation(make_flat_caret_reference(newf))
end

# Left / Right: per-character cursor motion, `± 1` clamped in the flat stream. A
# range collapses to its near end. Declines when a whole element is selected (no
# character cursor to move) so the syntax layer can tree-navigate.
function _text_char_motion(text::TextBlock, direction::Symbol)
    is_structural_selection(text.selection) && return nothing
    sel = _text_flat_selection(text)
    sel === nothing && return nothing
    s, e = sel
    newf = if s == e
        direction === :left ? max(0, s - 1) : min(_text_flat_total(text), s + 1)
    else
        direction === :left ? s : e     # collapse the range to its near end
    end
    ReplaceSelectionOperation(make_flat_caret_reference(newf))
end

# Shift and a motion key: move one end of the selection and keep the other. A
# range stays ordered, so a key moves the end that lies in its direction: the
# left, word-left and start keys move the start, and the others move the stop.
# From a caret, the key's direction makes the range. Declines when a whole
# element is selected, as the plain motion does.
function _text_extend(text::TextBlock, direction::Symbol)
    is_structural_selection(text.selection) && return nothing
    sel = _text_flat_selection(text)
    sel === nothing && return nothing
    s, e = sel
    total = _text_flat_total(text)
    if direction === :left
        s = max(0, s - 1)
    elseif direction === :right
        e = min(total, e + 1)
    elseif direction === :word_left
        s = _word_left_flat(_flat_chars(text), s)
    elseif direction === :word_right
        e = _word_right_flat(_flat_chars(text), e, total)
    elseif direction === :start
        s = 0
    else  # :end
        e = total
    end
    ReplaceSelectionOperation(make_flat_range_reference(s, e))
end

# The span at `path`'s content when it is a TextString; nothing otherwise.
function _span_content(text::TextBlock, path::SpanPath)
    elements = text.elements
    i = path[1]
    (i < 1 || i > length(elements)) && return nothing
    el = elements[i]
    if length(path) == 1
        el isa TextString || return nothing
        return el.content::AbstractString
    end
    el isa TextLine || return nothing
    spans = el.elements
    j = path[2]
    (j < 1 || j > length(spans)) && return nothing
    span = spans[j]
    span isa TextString || return nothing
    span.content::AbstractString
end

# Parse `text.selection[]` into (path, char_start, char_stop) when it matches
# `.elements[i].content[s:e]` or the in-line `.elements[i].elements[j].content[s:e]`,
# else return nothing. Selections are canonical at rest; the node types are
# stripped (this parser extracts only integer span/char offsets) before the raw
# structural walk.
_text_selection_range(text::TextBlock) = _text_selection_range(text, text.selection)
_text_selection_range(::TextBlock, selection) = _parse_selection_range(strip_reference_types(selection))

# The structural-caret parser, over an already-stripped reference. `get_flat_caret`
# reuses it so a decorator can resolve either caret form from a raw reference, not just
# from a block's own `.selection`.
function _parse_selection_range(sel)
    sel isa ConcreteReference || return nothing
    h1 = sel.head
    (h1 isa FieldReferenceStep && h1.name == "elements") || return nothing
    t1 = sel.tail
    t1 isa ConcreteReference || return nothing
    h2 = t1.head
    h2 isa RangeReferenceStep || return nothing
    path = Int[h2.start + 1]
    rest = t1.tail
    rest isa ConcreteReference || return nothing
    # One optional hop into a TextLine: `.elements[j]` again before `.content`.
    if rest.head isa FieldReferenceStep && rest.head.name == "elements"
        inner = rest.tail
        inner isa ConcreteReference || return nothing
        inner.head isa RangeReferenceStep || return nothing
        push!(path, inner.head.start + 1)
        rest = inner.tail
        rest isa ConcreteReference || return nothing
    end
    (rest.head isa FieldReferenceStep && rest.head.name == "content") || return nothing
    t3 = rest.tail
    t3 isa ConcreteReference || return nothing
    h4 = t3.head
    h4 isa RangeReferenceStep || return nothing
    (path, h4.start::Int, h4.stop::Int)
end

_text_replace_path(path::SpanPath, char_start::Int, char_stop::Int) =
    _elements_prefix(path,
        ConcreteReference(FieldReferenceStep("content"),
            ConcreteReference(RangeReferenceStep(char_start, char_stop), EmptyReference())))

# `.elements[i]` (— `.elements[j]`) in front of `tail`, one `elements` hop per
# index in `path`.
function _elements_prefix(path::SpanPath, tail)
    ref = tail
    for i in reverse(path)
        ref = ConcreteReference(FieldReferenceStep("elements"),
                  ConcreteReference(RangeReferenceStep(i - 1, i), ref))
    end
    ref
end

# ── Decorators of a block of lines ────────────────────────────────────────────
#
# A decorator that splits or restyles the spans of a line, and inserts no
# character, keeps every flat offset. It records, for each line that it splits, the
# segments of the spans of that line, whose indices count in the line; a line that
# it does not split is the same object.

# A line with every field of `line` but the spans, which are `spans`.
_make_line_with_spans(line::TextLine, spans::Vector) =
    TextLine(CellVector(Cell[Cell(span) for span in spans]), getfield(line, :indentation),
             getfield(line, :gutter), getfield(line, :fold), getfield(line, :soft_breaks),
             getfield(line, :selection), getfield(line, :mouse_target))

# A path on a block of lines, mapped through the segments of its line: forward from
# the input to the output, or backward. A caret, a range, a box and `∅` keep their
# flat offsets, and a path into a line that is not split is the same in both.
function _map_line_path(segs, reference, forward::Bool)
    parsed = _parse_line_span_path(reference)
    parsed === nothing && return reference
    i, j, tail = parsed
    k = findfirst(entry -> first(entry) == i, segs)
    k === nothing && return reference
    char = tail === nothing ? nothing : tail[1]
    for seg in last(segs[k])
        index, start = forward ? (seg.in_span, seg.in_char_start) : (seg.out_index, 0)
        index == j || continue
        if forward
            char === nothing || start <= char <= start + seg.length || continue
            return _make_line_span_path(i, seg.out_index, char === nothing ? nothing : char - start, tail)
        end
        return _make_line_span_path(i, seg.in_span, char === nothing ? nothing : char + seg.in_char_start, tail)
    end
    nothing
end

# `.elements[i].elements[j]` followed by nothing, or by `.content{a:b}`: `(i, j,
# nothing)` or `(i, j, (a, b))`; `nothing` for any other path.
function _parse_line_span_path(reference)
    r = strip_reference_types(reference)
    steps = r isa ConcreteReference ? collect(get_reference_steps(r)) : Any[]
    (length(steps) in (4, 6) && steps[1] isa FieldReferenceStep && steps[1].name == "elements" &&
     steps[2] isa RangeReferenceStep && steps[3] isa FieldReferenceStep &&
     steps[3].name == "elements" && steps[4] isa RangeReferenceStep) || return nothing
    i, j = steps[2].stop, steps[4].stop
    length(steps) == 4 && return (i, j, nothing)
    (steps[5] isa FieldReferenceStep && steps[5].name == "content" && steps[6] isa RangeReferenceStep) ||
        return nothing
    (i, j, (steps[6].start::Int, steps[6].stop::Int))
end

# The path of span `j` of line `i`, with the characters `a:b` of `tail` moved by
# `char - a` when `char` is given.
function _make_line_span_path(i::Int, j::Int, char, tail)
    tail === nothing && return _elements_prefix(Int[i, j], EmptyReference())
    a, b = tail
    _text_replace_path(Int[i, j], char, char + b - a)
end


# ── Clipboard support ──────────────────────────────────────────────────────────
# Public helpers used by the clipboard projection's text branch
# (`ClipboardSliceToAnyProjection` in text mode); see
# `plan/done/clipboard-os-bridge-and-run-example-wrapper.md`.

"""
    get_selection_substring(text::TextBlock) -> Union{String,Nothing}

The substring currently selected within a single span, or `nothing` when the
selection is an empty caret, spans no characters, or is not a single-span character
range. Used by the clipboard to copy / cut text.
"""
function get_selection_substring(text::TextBlock)
    rng = _text_selection_range(text)
    rng === nothing && return nothing
    path, a, b = rng
    a == b && return nothing                         # empty caret — nothing to copy
    content = _span_content(text, path)
    content === nothing && return nothing
    chars = collect(content)
    (a < 0 || b > length(chars) || a > b) && return nothing
    String(chars[a + 1:b])
end

"""
    make_text_insert_operation(text::TextBlock, str) -> Union{Operation,Nothing}

The `ReplaceStringRangeOperation` that inserts `str` at the text cursor, replacing
any selected range. Beside an inline image, where no text run holds the caret, it
is the element write that starts a new run there, with the caret after it. `nothing`
when the selection is not a character cursor/range (or the range crosses a span
boundary). The caret advances past the inserted text automatically on evaluation. Used by the clipboard to paste text — the flat edit is
lowered to the structural single-span form here so the clipboard stays unchanged.
"""
function make_text_insert_operation(text::TextBlock, str::AbstractString)
    op = _text_insert(text, str)
    op === nothing ? nothing : _lower_text_range(text, op)
end

# A whole-element selection projects to `∅` (the root element), a
# `TextSpanReferenceStep` bounding box, or a `TextColumnReferenceStep` column box; all
# three mean "structural mode" at this layer — a character cursor they are not,
# so char motion declines and the syntax layer tree-navigates / block-edits them.
function is_structural_selection(sel)
    sel = sel
    sel isa EmptyReference ||
        (sel isa ConcreteReference &&
         (sel.head isa TextSpanReferenceStep || sel.head isa TextColumnReferenceStep))
end

# ── set_cell_computation! delegation ────────────────────────────────────────────

set_cell_computation!(s::TextString, f::Function) = (set_cell_computation!(getfield(s, :content), f); s)
set_cell_computation!(st::TextBlock, f::Function) = (set_cell_computation!(getfield(st.elements, :elements), () -> Cell[Cell(x) for x in f()]); st)

# ── Selection → flat character range ───────────────────────────────
#
# Shared helper: resolve a TextBlock's selection to a flat half-open char range
# over the concatenated rendered stream. The console backend and the
# `SelectionInverting` projection both consume this single source of truth (the
# graphics pipeline computes its cursor rect from span-local offsets instead).

# The flat length a span contributes to the rendered character stream, matching
# how the selection's offsets are counted: TextString → its content length,
# TextNewline / TextSpacing / TextGraphics → 1, anything else → 0. An inline image
# is one position, so the caret before it and the caret after it differ.
#
# A `TextLine` contributes its indentation (which the renderers emit as leading
# spaces, so it occupies characters even though no span holds it) plus its spans'
# lengths — but *not* the break it implies: that sits between elements, so the
# container adds it (see `get_flat_offsets`) and a line-structured block gets
# `n-1` breaks for `n` lines rather than a phantom trailing one.
get_flat_length(span::TextString) = length(span.content::AbstractString)
get_flat_length(::TextNewline) = 1
get_flat_length(::TextSpacing) = 1
get_flat_length(::TextGraphics) = 1
get_flat_length(line::TextLine) =
    line.indentation + sum(get_flat_length(s) for s in line.elements; init = 0)
get_flat_length(::TextDocument) = 0

"""
    get_flat_offsets(text::TextBlock) -> Vector{Int}

The flat character offset each element starts at (0-based), and — as the vector's
`end + 1` entry would be — the block's total flat length. Every `TextLine` but a
leading one is preceded by its implicit break, which is where the `+1` enters;
for a block of plain spans this is just the running sum of `get_flat_length`.

The one place the implicit break is materialized. Anything mapping the flat
character stream back to elements (the console backend, `SelectionInverting`)
must count offsets through this rather than summing `get_flat_length` itself.
"""
function get_flat_offsets(text::TextBlock)
    offsets = Int[]
    pos = 0
    for (k, element) in enumerate(text.elements)
        (element isa TextLine && k > 1) && (pos += 1)   # the break before this line
        push!(offsets, pos)
        pos += get_flat_length(element)
    end
    offsets
end

"""
    get_flat_selection(text::TextBlock) -> (start, stop, is_cursor) or nothing

Resolve `text`'s selection to a flat half-open char range `(start, stop)` over
the concatenated stream (0-based), plus an `is_cursor` flag (a zero-width caret).
Returns `nothing` when there is no renderable selection.

Two shapes occur, both with 0-based offsets:
  • whole-element: top-level `TextSpanReferenceStep(a, b)`, an already-flat
    character range over the concatenated text;
  • text cursor: `.elements[i].content{a:b}`, or `.elements[i].elements[j].content{a:b}`
    inside a line — add the span's base offset.
"""
function get_flat_selection(text::TextBlock)
    # Selections are canonical at rest: each node records its type. The range
    # parser strips the types, and the rectangular shape is read raw.
    sel = text.selection
    sel isa ConcreteReference || return nothing
    h = sel.head
    if h isa TextRangeReferenceStep && sel.tail isa EmptyReference
        return (h.start, h.stop, h.start == h.stop)
    end
    if h isa TextSpanReferenceStep && sel.tail isa EmptyReference
        return (h.start, h.stop, h.start == h.stop)
    end
    rng = _text_selection_range(text)
    rng === nothing && return nothing
    path, a, b = rng
    base = get_flat_base(text, path)
    base === nothing && return nothing
    (base + a, base + b, a == b)
end

# ── Decorator flat↔element helpers ─────────────────────────────────────────
# The text→text decorators (WordWrapping, LineNumbering, TextFiltering,
# TextHighlighting, SelectionInverting) remap the flat cursor between their input
# and output blocks through a per-span seg table keyed on element index + char.
# These bridge a flat offset (the break/indentation-aware caret space) and the
# `(element_index, char)` the seg tables use. The decorator blocks are flat
# sequences (TextString / TextNewline / TextSpacing — no nested TextLines), so an
# element index is a single `[i]` path.

"""
    convert_flat_offset_to_element(block, flat) -> (element_index, char) | nothing

The `TextString` element a flat offset lands in and the char offset within it, or
the inline image beside it where no `TextString` holds the offset (char 0 before
the image, char 1 after it). A gap offset (on a break/spacing element) clamps to
the nearest `TextString` boundary; `nothing` only when the block has no
`TextString`.
"""
function convert_flat_offset_to_element(block::TextBlock, flat::Int)
    loc = _find_flat_place(block, flat)
    loc !== nothing && length(loc[1]) == 1 && return (loc[1][1], loc[2])
    best = nothing
    bestd = typemax(Int)
    for (path, len) in _text_span_infos(block)
        length(path) == 1 || continue
        base = get_flat_base(block, path)
        base === nothing && continue
        d = flat < base ? base - flat : (flat > base + len ? flat - (base + len) : 0)
        if d < bestd
            bestd = d
            best = (path[1], clamp(flat - base, 0, len))
        end
    end
    best
end

"""
    convert_element_to_flat_offset(block, element_index, char) -> flat | nothing

The flat offset of `char` within the `TextString` at `element_index`.
"""
function convert_element_to_flat_offset(block::TextBlock, elem::Int, char::Int)
    base = get_flat_base(block, Int[elem])
    base === nothing ? nothing : base + char
end

# The flat offset the span at `path` starts at, or nothing when the path does not
# land on a span.
function get_flat_base(text::TextBlock, path::SpanPath)
    offsets = get_flat_offsets(text)
    i = path[1]
    (1 <= i <= length(offsets)) || return nothing
    base = offsets[i]
    length(path) == 1 && return base
    line = text.elements[i]
    line isa TextLine || return nothing
    spans = line.elements
    j = path[2]
    (1 <= j <= length(spans)) || return nothing
    base += line.indentation      # the leading spaces the renderers emit
    for k in 1:(j - 1)
        base += get_flat_length(spans[k])
    end
    base
end

# A decorator that adds or drops whole elements moves the flat offsets after the
# change. Its table is then a list of runs `(from, to, length)`, in the order of
# both blocks: the offsets `from … from + length` of one block are the offsets
# `to … to + length` of the other. An added element lies between two runs, and a
# dropped one is in no run.

# The runs that carry the offsets of `from_block` to `to_block`, one for each
# entry `(from_element, from_char, to_element, length)`: the run starts at
# `from_char` of the one element and at the start of the other. An element that
# the flat stream counts as zero is a run of length zero.
function _make_flat_runs(from_block::TextBlock, to_block::TextBlock, entries)
    from_offsets = get_flat_offsets(from_block)
    to_offsets = get_flat_offsets(to_block)
    [(from = from_offsets[i] + char, to = to_offsets[j], length = len)
     for (i, char, j, len) in entries]
end

# The same runs, read the other way.
_reverse_flat_runs(runs) = [(from = r.to, to = r.from, length = r.length) for r in runs]

# The flat offset `flat` carried over `runs`. Where one run stops and the next
# starts, the offset goes to the start of the next when `opens`, and to the stop
# of the one before otherwise. An offset in no run goes to the start of the next
# run when `opens`, and to the stop of the run before otherwise; `nothing` when no
# run is on that side.
function _map_flat_over_runs(runs, flat::Int, opens::Bool)
    touching = nothing    # a run that starts or stops at `flat`
    before = nothing      # the last run that stops before `flat`
    for r in runs
        stop = r.from + r.length
        inside = opens ? r.from <= flat < stop : r.from < flat <= stop
        inside && return r.to + flat - r.from
        if r.from > flat
            touching === nothing || return touching.to + flat - touching.from
            opens && return r.to
            return before === nothing ? nothing : before.to + before.length
        end
        (flat == r.from || flat == stop) && (opens || touching === nothing) && (touching = r)
        stop < flat && (before = r)
    end
    touching === nothing || return touching.to + flat - touching.from
    (opens || before === nothing) && return nothing
    before.to + before.length
end

# The whole-element box of `reference`, or `nothing` when it is not one.
function _get_text_box(reference)
    r = strip_reference_types(reference)
    r isa ConcreteReference && r.head isa TextSpanReferenceStep && r.tail isa EmptyReference ||
        return nothing
    r.head
end

# A whole-element box carried over `runs`. Its start opens a run and its stop
# closes one, so a box that ends at a soft break stays on its line. `nothing`
# when no part of the box has an image.
function _map_text_box(runs, box::TextSpanReferenceStep)
    start = _map_flat_over_runs(runs, box.start, true)
    start === nothing && return nothing
    box.stop == box.start && return ConcreteReference(TextSpanReferenceStep(start, start), EmptyReference())
    stop = _map_flat_over_runs(runs, box.stop, false)
    (stop === nothing || stop <= start) && return nothing
    ConcreteReference(TextSpanReferenceStep(start, stop), EmptyReference())
end

# A selection of `block` carried over `runs`: a caret or a range in either caret
# form, which comes out flat, or a whole-element box. `∅` passes through.
function _map_selection_over_runs(runs, block::TextBlock, selection)
    selection isa EmptyReference && return selection
    box = _get_text_box(selection)
    box === nothing || return _map_text_box(runs, box)
    pair = _text_flat_selection(block, selection)
    pair === nothing && return nothing
    start = _map_flat_over_runs(runs, pair[1], true)
    start === nothing && return nothing
    pair[1] == pair[2] && return make_flat_caret_reference(start)
    stop = _map_flat_over_runs(runs, pair[2], false)
    (stop === nothing || stop < start) && return nothing
    make_flat_range_reference(start, stop)
end

# ── ReplaceTextRangeOperation — the flat text edit ─────────────────────────
#
# The text-domain edit expressed in the canonical flat coordinate (the
# `get_flat_offsets` / `get_flat_base` space that counts breaks, spacing and
# indentation — the same space `get_flat_selection` and the renderer use). Its
# `reference` is rooted at the editor's document and terminates in a
# `TextRangeReferenceStep(start, stop)`; unlike a `ReplaceStringRangeOperation` its
# range may cross spans/lines. It re-roots through the projection stack like the
# string op (same `(reference, replacement)` shape) and, for a projected document,
# is lowered to input-domain ops at the syntax↔text seam. It reaches
# `evaluate_operation` only when a `TextBlock` is (reachable in) the editor's own
# document.

"""
    ReplaceTextRangeOperation(reference, replacement)

Replace a flat character range of a `TextBlock` with `replacement`. `reference` is
rooted at the editor's document and terminates in a `TextRangeReferenceStep(s, e)`
(0-based flat offsets over the block's concatenated stream). After evaluation the
selection becomes a zero-width caret at `s + length(replacement)`.
"""
struct ReplaceTextRangeOperation <: ReplaceRangeOperation
    reference::Reference
    replacement::String
end

# Split a text-range reference into (prefix-to-block, start, stop). The terminal
# step must be a `TextRangeReferenceStep`; returns `nothing` otherwise. Type
# checkpoints are stripped first so the terminal is read from the plain skeleton.
function _split_text_range_reference(path)
    steps = get_reference_steps(strip_reference_types(path))
    isempty(steps) && return nothing
    term = steps[end]
    term isa TextRangeReferenceStep || return nothing
    (Reference(steps[1:end-1]...), term.start, term.stop)
end

# Resolve a flat offset (canonical break/indentation-aware space) to the
# `(span_path, local_char)` of the `TextString` span it falls in, or `nothing`
# when it lands on a break / spacing / indentation gap (no editable span), beside
# an inline image with no text run on that side, or out of range. Boundary offsets
# resolve to the earlier span's end.
function _flat_to_span(text::TextBlock, flat::Int)
    for (span_path, len) in _text_span_infos(text)
        base = get_flat_base(text, span_path)
        base === nothing && continue
        base <= flat <= base + len && return (span_path, flat - base)
    end
    nothing
end

# The inline image that a flat offset touches, as `(span_path, char)`: char 0 is
# the caret before the image and char 1 the caret after it. Between two images,
# the caret after the earlier one. `nothing` when no image touches the offset.
function _find_flat_image_place(text::TextBlock, flat::Int)
    for path in _collect_image_paths(text)
        base = get_flat_base(text, path)
        base === nothing && continue
        base <= flat <= base + 1 && return (path, flat - base)
    end
    nothing
end

# The place of a flat offset, as `(span_path, char)`: the text run that holds it
# (`_flat_to_span`), else the inline image beside it (`_find_flat_image_place`).
# `nothing` on a break or a gap that no run and no image touches.
_find_flat_place(text::TextBlock, flat::Int) =
    something(_flat_to_span(text, flat), _find_flat_image_place(text, flat), Some(nothing))

# Standalone-TextBlock application. For a projected document the op is lowered
# upstream and never arrives here. v1 handles the in-span case (caret or range
# within one span); a cross-span range or an offset on a break/indentation gap
# declines (leaves the document unchanged) — break-joins and multi-span edits are
# a later pass.
function evaluate_operation(editor, op::ReplaceTextRangeOperation)
    document = editor.document
    split = _split_text_range_reference(op.reference)
    split === nothing && return
    block_path, start, stop = split
    block = try
        evaluate_reference(document, block_path)
    catch
        return
    end
    block isa TextBlock || return
    image_edit = _make_image_edit(block, start, stop, op.replacement)
    if image_edit !== nothing
        evaluate_operation(editor, reroot_operation(image_edit, Tuple(get_reference_steps(block_path))))
        return
    end
    a = _flat_to_span(block, start)
    b = _flat_to_span(block, stop)
    (a === nothing || b === nothing || a[1] != b[1]) && return   # off-span / cross-span: v1 decline
    span = _span_at(block, a[1])
    span.content = splice_string(span.content::AbstractString, a[2], b[2], op.replacement)
    newpos = start + length(op.replacement)
    steps = get_reference_steps(strip_reference_types(op.reference))
    newref = Reference(steps[1:end-1]..., TextRangeReferenceStep(newpos, newpos))
    clear_selection!(document)
    set_selection!(document, newref)
end

# The pair registers the flat edit: the kernel reroots its reference and maps it
# back through a projection.
operation_reference(op::ReplaceTextRangeOperation) = op.reference
retarget_operation(op::ReplaceTextRangeOperation, reference::Reference) =
    ReplaceTextRangeOperation(reference, op.replacement)

# Lower a flat `ReplaceTextRangeOperation` to the structural single-span
# `ReplaceStringRangeOperation` (`.elements[i].content[s:e]`) over `block`, so the
# existing per-stage `ReplaceStringRangeOperation` readers carry it the rest of the
# way up the chain. Applied at the text→graphics boundary against that stage's
# input block (== the outermost text stage's output). Returns `nothing` when the
# range crosses a span/break boundary (v1 declines cross-span edits) or is not a
# flat range.
# The `TextString` span a non-empty range's START opens, as its full span path
# (`[i]` for a top-level span, `[i, j]` for one inside a `TextLine`): a boundary
# offset (equal to a span's end) belongs to the NEXT span it enters, not the one it
# just left — so a range whose start sits on the open-delimiter|value seam stays inside
# the value rather than straddling it. `nothing` when the offset falls in a break/gap.
function _flat_span_range_start(block::TextBlock, flat::Int)
    for (path, len) in _text_span_infos(block)
        base = get_flat_base(block, path)
        base === nothing && continue
        base <= flat < base + len && return (path, flat - base)
    end
    nothing
end

# The `TextString` span a non-empty range's END closes, as its full span path: a
# boundary offset (equal to a span's start) belongs to the PREVIOUS span it ends, so a
# range ending on the value|close-delimiter seam stays inside the value. `nothing` in a gap.
function _flat_span_range_end(block::TextBlock, flat::Int)
    for (path, len) in _text_span_infos(block)
        base = get_flat_base(block, path)
        base === nothing && continue
        base < flat <= base + len && return (path, flat - base)
    end
    nothing
end

# The `(span_path, char)` a flat offset resolves to, clamping a break/gap offset to the
# nearest `TextString` span. Path-returning (so it locates a span inside a `TextLine`,
# `[i, j]`), unlike `convert_flat_offset_to_element` which yields only a top-level index and so
# returns nothing for a line-structured block.
function _flat_to_span_nearest(block::TextBlock, flat::Int)
    exact = _flat_to_span(block, flat)
    exact === nothing || return exact
    best = nothing
    bestd = typemax(Int)
    for (path, len) in _text_span_infos(block)
        base = get_flat_base(block, path)
        base === nothing && continue
        d = flat < base ? base - flat : (flat > base + len ? flat - (base + len) : 0)
        if d < bestd
            bestd = d
            best = (path, clamp(flat - base, 0, len))
        end
    end
    best
end

# A key read with the gesture table of `block`, a flat edit lowered to the
# operation `_lower_text_range` makes of it. A text stage that gets a key reads it
# against its input this way, so the edit reaches the document as an operation that
# the stages before it carry and undo can take back.
#
# A block whose elements are a list has no flat caret stream: the list can be
# endless, so it has no end to go to, and a flat offset would walk it. Such a
# block reads no key.
function _read_lowered_gesture(block::TextBlock, evt)
    block.elements isa ListNode && return nothing
    op = read_gesture(block, evt)
    op isa ReplaceTextRangeOperation ? _lower_text_range(block, op) : op
end

function _lower_text_range(block::TextBlock, op::ReplaceTextRangeOperation)
    r = strip_reference_types(op.reference)
    (r isa ConcreteReference && r.head isa TextRangeReferenceStep && r.tail isa EmptyReference) || return nothing
    s, e = r.head.start, r.head.stop
    image_edit = _make_image_edit(block, s, e, op.replacement)
    image_edit === nothing || return image_edit
    if s == e
        # Zero-width (an insertion): keep the plain resolution — a caret on a delimiter|value
        # seam lands on the delimiter's end, which the domain's `read_intent` (SyntaxToText's
        # prefer-content redirect) steers into the value. Range-snapping the two ends apart
        # here would instead split them across spans and decline.
        a = _flat_to_span_nearest(block, s); b = a
    else
        # A real range snaps each end toward the interior of the span it touches, so a
        # delete/replace that brushes a delimiter seam stays within one span instead of
        # declining as cross-span. A genuinely multi-span range still resolves to two
        # different spans and declines (v1 leaves multi-span edits to a later pass).
        a = something(_flat_span_range_start(block, s), _flat_to_span_nearest(block, s), Some(nothing))
        b = something(_flat_span_range_end(block, e),   _flat_to_span_nearest(block, e), Some(nothing))
    end
    # `a[1]` / `b[1]` are now full span paths (`[i]` or `[i, j]`); a range that stays
    # within one span has equal paths. `_text_replace_path` builds the nested
    # `.elements[i](.elements[j]).content[s:e]` reference for either depth.
    (a === nothing || b === nothing || a[1] != b[1]) && return nothing   # cross-span: v1 decline
    # A non-empty flat range that collapses to an empty span range fell entirely in a
    # break / spacing / indentation gap — there is no editable content to remove (e.g.
    # Backspace at the start of an indented `TextLine`, whose range covers only the
    # leading indent). Decline rather than emit a no-op edit.
    (s != e && a[2] == b[2]) && return nothing
    ReplaceStringRangeOperation(_text_replace_path(a[1], a[2], b[2]), op.replacement)
end

# ── The edit beside an inline image ────────────────────────────────────────
#
# An inline image is one position of the flat caret space, but it holds no
# character, so some edits beside it are not a splice of one run. They write the
# element list of the block instead:
#   • a character typed beside an image, where no text run holds the caret,
#     starts a new run there (`make_insert_elements_operation`);
#   • a range that covers only images deletes them (`make_delete_elements_operation`), and
#     a replacement puts a new run in their place.
# Each leaves the flat caret after it. A new run takes the style of the nearest
# text run (`_find_style_span`). Every other edit is a splice of one run.

# The element write for the flat edit `s..e ← replacement` of `text`, rooted at
# `text`, or `nothing` when the edit is not one beside an image.
function _make_image_edit(text::TextBlock, s::Int, e::Int, replacement::AbstractString)
    caret = make_flat_caret_reference(s + length(replacement))
    if s == e
        isempty(replacement) && return nothing
        _flat_to_span(text, s) === nothing || return nothing
        place = _find_flat_image_place(text, s)
        place === nothing && return nothing
        path, char = place
        run = _make_styled_run(replacement, _find_style_span(text, path))
        return make_insert_elements_operation(_get_container_reference(path),
                                              path[end] + char,
                                              Any[run]; selection = caret)
    end
    paths = _find_image_range(text, s, e)
    paths === nothing && return nothing
    container = _get_container_reference(paths[1])
    element = paths[1][end]
    write = if isempty(replacement)
        make_delete_elements_operation(container, element; count = length(paths))
    else
        run = _make_styled_run(replacement, _find_style_span(text, paths[1]))
        boundary = element - 1
        ReplaceReferencedValueOperation(nothing,
            extend_reference(container,
                             RangeReferenceStep(boundary, boundary + length(paths))),
            Any[run])
    end
    CompoundOperation(Any[write, ReplaceSelectionOperation(caret)])
end

# The images that fill the flat range `s..e` exactly, as the paths of consecutive
# siblings of one container; `nothing` when anything else is in the range.
function _find_image_range(text::TextBlock, s::Int, e::Int)
    paths = SpanPath[]
    for path in _collect_image_paths(text)
        base = get_flat_base(text, path)
        (base !== nothing && s <= base < e) && push!(paths, path)
    end
    length(paths) == e - s || return nothing
    for (k, path) in enumerate(paths)
        (path[1:end-1] == paths[1][1:end-1] && path[end] == paths[1][end] + k - 1) || return nothing
    end
    paths
end

# The element list that holds the span at `path`: `.elements` of the block, or
# `.elements[i].elements` of a line.
_get_container_reference(path::SpanPath) =
    _elements_prefix(path[1:end-1], ConcreteReference(FieldReferenceStep("elements"), EmptyReference()))

# The span whose style a new run beside the image at `path` takes: the nearest
# text run of the image's line, the run before the image first; on a line with no
# text run, the first `TextString` or `TextNewline` of the block in document order,
# where `TextToGraphics` finds the prevailing font of a block; `nothing` when the
# block has neither.
function _find_style_span(text::TextBlock, path::SpanPath)
    siblings = length(path) == 1 ? text.elements : text.elements[path[1]].elements
    k = path[end]
    for i in (k - 1):-1:1
        el = siblings[i]
        el isa TextString && return el
        el isa Union{TextNewline, TextLine} && break
    end
    for i in (k + 1):length(siblings)
        el = siblings[i]
        el isa TextString && return el
        el isa Union{TextNewline, TextLine} && break
    end
    for el in text.elements
        el isa Union{TextString, TextNewline} && return el
        el isa TextLine || continue
        for span in el.elements
            span isa TextString && return span
        end
    end
    nothing
end

# A new run of `content` in the style of `span` (a `TextString` or a
# `TextNewline`), or in the default style when there is none.
_make_styled_run(content::AbstractString, ::Nothing) = TextString(content)
_make_styled_run(content::AbstractString, span::Union{TextString, TextNewline}) =
    TextString(Cell(content), span.font, span.font_color, Cell(span.fill_color),
               Cell(span.line_color), Cell(span.padding), Cell(nothing))

"""
    is_text_element_write(op) -> Bool

Whether `op` writes the element list of a text block, as the edit beside an
inline image does: a document-rooted `ReplaceReferencedValueOperation` under
`.elements`, alone or in a `CompoundOperation` with its caret. A stage whose output
is a text block with other element indices than its input declines such a write;
the chain then reads the gesture again against the input of that stage.
"""
is_text_element_write(op) = false
is_text_element_write(op::ReplaceReferencedValueOperation) =
    op.document === nothing && _starts_with_elements(strip_reference_types(op.reference))
is_text_element_write(op::CompoundOperation) = any(is_text_element_write, op.operations)
_starts_with_elements(reference) =
    reference isa ConcreteReference && reference.head isa FieldReferenceStep &&
    reference.head.name == "elements"
