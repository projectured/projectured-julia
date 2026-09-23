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

- `TextNewline(; font, font_color="", fill_color=nothing, line_color=nothing, padding=nothing)`
  — the macro's keyword constructor; `font` is the one field without a default,
  and so the one required keyword.
"""
@document struct TextNewline <: TextDocument
    font::StyleFont
    font_color::StyleColor = ""
    fill_color::StyleColor = nothing
    line_color::StyleColor = nothing
    padding::Inset = nothing
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

- `TextSpacing(size::Number; unit=:pixel, font, font_color="", fill_color=nothing, line_color=nothing, padding=nothing)`
"""
@document struct TextSpacing <: TextDocument
    size::Number
    unit::Symbol
    font::StyleFont
    font_color::StyleColor
    fill_color::StyleColor
    line_color::StyleColor
    padding::Inset
end

TextSpacing(size::Number; unit=:pixel, font, font_color="", fill_color=nothing, line_color=nothing, padding=nothing) =
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

When a `TextBlock` selection path descends into a span, the sub-path
refers to the cursor within the span's `content` field:  `.content{k}`
"""
@document struct TextString <: TextDocument
    content::AbstractString
    font::ImmutableCell{StyleFont}
    font_color::ImmutableCell{StyleColor}
    fill_color::StyleColor
    line_color::StyleColor
    padding::Inset
end

# font / font_color are passed RAW so they land in their ImmutableCell default;
# content stays a reactive Cell. Passing a Cell for font/colour overrides the default.
TextString(content::AbstractString, font::StyleFont, font_color::StyleColor) =
    TextString(Cell(content), font, font_color, Cell(nothing), Cell(nothing), Cell(nothing), Cell(nothing))

TextString(content::AbstractString) =
    TextString(Cell(content), font_ubuntu_monospace_regular_20, color_default, Cell(nothing), Cell(nothing), Cell(nothing), Cell(nothing))

TextString(content::Function, font::StyleFont, font_color::StyleColor) =
    TextString(ComputedCell(content), font, font_color, Cell(nothing), Cell(nothing), Cell(nothing), Cell(nothing))

# StyleText bridge: a projection holding a merged (font, color) style value can
# build a run without unpacking it. The document model itself is unchanged —
# `style` is split into the existing `font` / `font_color` cells.
TextString(content::AbstractString, style::StyleText) = TextString(content, style.font, style.color)
TextString(content::Function,      style::StyleText) = TextString(content, style.font, style.color)

# A text span that shows a muted placeholder while the value is empty. Both text
# and colour are reactive, so the hint disappears the moment the user types.
function make_hinted_text(content_thunk; empty_thunk, placeholder::AbstractString,
                          style::StyleText)
    TextString(
        ComputedCell(() -> empty_thunk() ? placeholder : content_thunk()),
        style.font,                                                        # immutable (authored font)
        ComputedCell(() -> empty_thunk() ? color_solarized_gray : style.color),   # reactive (hint colour)
        Cell(nothing), Cell(nothing), Cell(nothing), Cell(nothing))
end

# ── TextGraphics ─────────────────────────────────────────────────────

"""
    TextGraphics

Embeds a graphics document (typically an `ImageDocument`) within text as an
inline image or icon. The image flows as a single unbreakable glyph: it
contributes its height to the line and occupies one atomic cursor position.

# Fields

- `content::Cell` — holds the embedded `Document` (e.g. `ImageFile`, `ImageMemory`)
- `width::Cell{Int32}` — display width in pixels
- `height::Cell{Int32}` — display height in pixels
- `font::Cell{StyleFont}` — font specification (unused for images, kept for uniformity)
- `font_color::Cell` — text color (unused for images)
- `fill_color::Cell` — background fill color
- `line_color::Cell` — border/line color
- `padding::Cell` — inset/padding value

# Constructors

- `TextGraphics(content, width, height; font, font_color, fill_color, line_color, padding)`
- `TextGraphics(content; font, font_color, fill_color, line_color, padding)` — zero size
"""
@document struct TextGraphics <: TextDocument
    content::Document
    width::Int32
    height::Int32
    font::StyleFont
    font_color::StyleColor
    fill_color::StyleColor
    line_color::StyleColor
    padding::Inset
end

TextGraphics(content, width::Integer, height::Integer; font=font_ubuntu_monospace_regular_20, font_color="", fill_color=nothing, line_color=nothing, padding=nothing) =
    TextGraphics(Cell(content), Cell(Int32(width)), Cell(Int32(height)), Cell(font), Cell(font_color), Cell(fill_color), Cell(line_color), Cell(padding), Cell(nothing))

TextGraphics(content; font, font_color="", fill_color=nothing, line_color=nothing, padding=nothing) =
    TextGraphics(Cell(content), Cell(Int32(0)), Cell(Int32(0)), Cell(font), Cell(font_color), Cell(fill_color), Cell(line_color), Cell(padding), Cell(nothing))

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

TextBlock(f::Function) = TextBlock(ComputedCellVector(f), Cell(nothing))

# ── TextLine ───────────────────────────────────────────────────────────

"""
    TextLine(spans...; indentation = 0)

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
"""
@document struct TextLine <: TextDocument
    elements::CollectionDocument = CellVector()
    indentation::Int = 0
end

TextLine(spans::Vector{<:TextDocument}; indentation::Integer = 0) =
    TextLine(CellVector(Cell[Cell(s) for s in spans]), Cell(Int(indentation)), Cell(nothing))

TextLine(spans::TextDocument...; indentation::Integer = 0) =
    TextLine(collect(TextDocument, spans); indentation)

TextLine(f::Function; indentation::Integer = 0) =
    TextLine(ComputedCellVector(f), Cell(Int(indentation)), Cell(nothing))

# A lone line is not a document — it is a part of a block. Both of its fields are
# defaulted, so unlike the span types (each has a required field, and so no
# zero-arg constructor) `TextLine` *is* zero-arg constructible and would become a
# completion candidate on its own: committable at a top-level insertion, where the
# committed document is the root and the text pipeline prints a `TextBlock`, not a
# line. It would also make `text` ambiguous — both `text block` and `text line`
# start with it. Opt out, as `@domain` does for its own placeholder.
DomainModule.insertable(::Type{<:TextLine}) = false

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
@insertion TextBlock = @with_selection TextBlock([TextString("")]) elements[1].content{0}


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

# Field value is a flat span sequence: the incoming `[s, e]` is a flat offset
# across the concatenated spans (spans inside a `TextLine` included, in document
# order). Locate the single `TextString` span the range falls inside and edit it;
# an empty sequence grows a fresh span. Ranges that straddle two spans are left
# for a later multi-span editing pass.
function splice_value!(owner, field::Symbol, text::TextBlock, s::Int, e::Int, replacement::AbstractString)
    pos = 0
    infos = _text_span_infos(text)
    for (path, len) in infos
        if s >= pos && e <= pos + len
            span = _span_at(text, path)
            span.content = splice_string(span.content::AbstractString, s - pos, e - pos, replacement)
            return text
        end
        pos += len
    end
    isempty(infos) && push!(text.elements, TextString(replacement))
    text
end

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
_push_flat_chars!(chars, ::TextDocument) = chars          # TextGraphics etc.: 0-width, matches get_flat_length
function _push_flat_chars!(chars, line::TextLine)
    for _ in 1:line.indentation
        push!(chars, ' ')
    end
    for span in line.elements
        _push_flat_chars!(chars, span)
    end
    chars
end

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
# caret falls in a break / indentation gap with no owning span. `get_flat_base`
# supplies the span's flat base, `_flat_to_span` the inverse.
get_flat_cursor_coordinate(text::TextBlock) = get_flat_cursor_coordinate(text, text.selection)
# The span and the character a flat offset lands on, in the shape of
# `get_flat_cursor_coordinate`, or `nothing` on a break or gap.
function _text_flat_span(text::TextBlock, flat::Int)
    loc = _flat_to_span(text, flat)
    loc === nothing ? nothing : (span = loc[1], char = loc[2])
end

function get_flat_cursor_coordinate(text::TextBlock, selection)
    sel = _text_flat_selection(text, selection)
    sel === nothing && return nothing
    sel[1] == sel[2] || return nothing            # a range has no single char cursor
    loc = _flat_to_span(text, sel[1])
    loc === nothing && return nothing
    (span = loc[1], char = loc[2])
end

# Standard editor word class: letters, digits, and underscore are "word" chars;
# everything else (including breaks and spacing) is a separator.
_is_word_char(c) = isletter(c) || isdigit(c) || c == '_'

# Ctrl+Right: from flat `f`, skip the current word run then the separator run →
# next word start. `chars` is the flat stream (`chars[f+1]` is the char right of
# caret `f`); `n == length(chars)`.
function _word_right_flat(chars, f::Int, n::Int)
    while f < n && _is_word_char(chars[f + 1]); f += 1; end
    while f < n && !_is_word_char(chars[f + 1]); f += 1; end
    f
end

# Ctrl+Left: skip the separator run then the word run (`chars[f]` is the char
# left of caret `f`).
function _word_left_flat(chars, f::Int)
    while f > 0 && !_is_word_char(chars[f]); f -= 1; end
    while f > 0 && _is_word_char(chars[f]); f -= 1; end
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
# else return nothing. Selections are canonical at rest; the TypeReferenceStep
# checkpoints are stripped (this parser extracts only integer span/char offsets)
# before the raw structural walk.
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
any selected range. `nothing` when the selection is not a character cursor/range
(or the range crosses a span boundary). The caret advances past the inserted text
automatically on evaluation. Used by the clipboard to paste text — the flat edit is
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

# ── set_cell_function! delegation ───────────────────────────────────────────────

set_cell_function!(s::TextString, f::Function) = (set_cell_function!(getfield(s, :content), f); s)
set_cell_function!(st::TextBlock, f::Function) = (set_cell_function!(getfield(st.elements, :elements), () -> Cell[Cell(x) for x in f()]); st)

# ── Selection → flat character range ───────────────────────────────
#
# Shared helper: resolve a TextBlock's selection to a flat half-open char range
# over the concatenated rendered stream. The console backend and the
# `SelectionInverting` projection both consume this single source of truth (the
# graphics pipeline computes its cursor rect from span-local offsets instead).

# The flat length a span contributes to the rendered character stream, matching
# how the selection's offsets are counted: TextString → its content length,
# TextNewline / TextSpacing → 1, anything else → 0.
#
# A `TextLine` contributes its indentation (which the renderers emit as leading
# spaces, so it occupies characters even though no span holds it) plus its spans'
# lengths — but *not* the break it implies: that sits between elements, so the
# container adds it (see `get_flat_offsets`) and a line-structured block gets
# `n-1` breaks for `n` lines rather than a phantom trailing one.
get_flat_length(span::TextString) = length(span.content::AbstractString)
get_flat_length(::TextNewline) = 1
get_flat_length(::TextSpacing) = 1
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
    # Selections are canonical at rest (carry TypeReferenceStep checkpoints); the
    # range parser peels them, but the rectangular shape is read raw.
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

The `TextString` element a flat offset lands in and the char offset within it. A
gap offset (on a break/spacing element) clamps to the nearest `TextString`
boundary; `nothing` only when the block has no `TextString`.
"""
function convert_flat_offset_to_element(block::TextBlock, flat::Int)
    loc = _flat_to_span(block, flat)
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
# when it lands on a break / spacing / indentation gap (no editable span) or out
# of range. Boundary offsets resolve to the earlier span's end.
function _flat_to_span(text::TextBlock, flat::Int)
    for (span_path, len) in _text_span_infos(text)
        base = get_flat_base(text, span_path)
        base === nothing && continue
        base <= flat <= base + len && return (span_path, flat - base)
    end
    nothing
end

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

reroot_operation(op::ReplaceTextRangeOperation, steps::Tuple) =
    ReplaceTextRangeOperation(reroot_reference(op.reference, steps), op.replacement)

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

function _lower_text_range(block::TextBlock, op::ReplaceTextRangeOperation)
    r = strip_reference_types(op.reference)
    (r isa ConcreteReference && r.head isa TextRangeReferenceStep && r.tail isa EmptyReference) || return nothing
    s, e = r.head.start, r.head.stop
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
