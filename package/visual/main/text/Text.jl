"""
    TextModule

The text domain bridges the structural (syntax tree) and visual (graphics) domains.
Text is stored as a flat sequence of spans, each with its own reactive style and color.
The selection is a flat character offset, making keyboard navigation straightforward
before the pixel-coordinate layout is applied.

The domain includes:
- **Span types**: `TextString` (text content), `TextNewline` (line break), `TextSpacing` (spacing), `TextGraphics` (embedded graphics)
- **Container type**: `TextBlock` (sequence of spans)
- **Base type**: `TextDocument` abstract type for all text documents
- **Insertion kit** (`@domain Text`): `TextNothing` (the empty-text placeholder) and
  `TextInsertion` (the typed-name buffer Insert opens on it)

Selection semantics (`[i]` = 1-based item, `{k}` = 0-based cursor):
- Spans: `.content{k}` — cursor at boundary k within the span's content
- TextBlock: `.elements[i]` — the i-th span, then `.content{k}` for the cursor within it

Each span has reactive styling fields:
- `font` — font style (e.g., "bold", "italic", "monospace")
- `font_color` — text color (name, hex, or rgb)
- `fill_color` — background fill color
- `line_color` — border/line color
- `padding` — inset/padding value
"""
module TextModule

import ..CellModule: Cell, set_function!, set_value!
import ..DocumentApiModule: Document
import ..DocumentModule: @document
import ..DomainModule
import ..DomainModule: @domain, @insertion
import ..SelectionModule: @with_selection
import ..CollectionModule: CellVector, ListNode, CollectionDocument
import ..FontModule: StyleFont, DStyleFont, font_ubuntu_monospace_regular_20
import ..ColorModule: StyleColor, DStyleColor, color_default, color_solarized_gray
import ..StyleTextModule: StyleText
import ..GeometryModule: Inset
import ..ReferenceModule: Reference, ConcreteReferencePath, EmptyReferencePath, RangeReference, FieldReference, strip_reference_types, Position
import ..TextRectangularReferenceModule: TextRectangularReference
import ..ReferenceCaseModule: var"@reference_case"
import ..ReferenceBuilderModule: var"@reference"
import ..OperationModule: ReplaceSelectionOperation, ToggleCollapseOperation, splice_string, splice_value!
import ..PrimitiveModule: ReplaceStringRangeOperation
import ..GestureBindingModule: var"@gestures"
export set_function!, text_flat_length, text_flat_offsets, text_selection_flat, hinted_text,
       text_selection_substring, text_insert_op

# ── The Text domain kit ───────────────────────────────────────────────────
#
# `TextDocument` (the exported abstract root every concrete text type subtypes;
# `@document` injects the `selection::Reference` field the `Document` contract
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
- `font::ImmutableCell{DStyleFont}`        — font specification (immutable by default)
- `font_color::ImmutableCell{DStyleColor}` — text colour (immutable by default)
- `fill_color::Cell` — holds background fill color or `nothing`
- `line_color::Cell` — holds border/line color or `nothing`
- `padding::Cell`    — holds inset/padding value or `nothing`

When a `TextBlock` selection path descends into a span, the sub-path
refers to the cursor within the span's `content` field:  `.content{k}`
"""
@document struct TextString <: TextDocument
    content::AbstractString
    font::ImmutableCell{DStyleFont}
    font_color::ImmutableCell{DStyleColor}
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
    TextString(Cell(content), font, font_color, Cell(nothing), Cell(nothing), Cell(nothing), Cell(nothing))

# StyleText bridge: a projection holding a merged (font, color) style value can
# build a run without unpacking it. The document model itself is unchanged —
# `style` is split into the existing `font` / `font_color` cells.
TextString(content::AbstractString, style::StyleText) = TextString(content, style.font, style.color)
TextString(content::Function,      style::StyleText) = TextString(content, style.font, style.color)

# A text span that shows a muted placeholder while the value is empty. Both text
# and colour are reactive, so the hint disappears the moment the user types.
function hinted_text(content_thunk, empty_thunk, placeholder::AbstractString, style::StyleText)
    TextString(
        Cell(() -> empty_thunk() ? placeholder : content_thunk()),
        style.font,                                                        # immutable (authored font)
        Cell(() -> empty_thunk() ? color_solarized_gray : style.color),   # reactive (hint colour)
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

TextBlock(f::Function) = TextBlock(CellVector(f), Cell(nothing))

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
    TextLine(CellVector(f), Cell(Int(indentation)), Cell(nothing))

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
# `TextToGraphics`, which keys its coordinate table (`SegCoord.span_path`) by them.
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
# OperationApiModule). They fire when a replace reference resolves to a field
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
end

# ── Character-cursor step helpers ─────────────────────────────────────────
#
# `_step_left` / `_step_right` return the next canonical caret `(span, char)`
# one character away from `(span_idx, char_idx)`, or `nothing` when motion is
# clamped at a document end, including the boundary-duplicate skip (so each
# visual caret has one canonical path). Word motion iterates them so every
# intermediate/final caret is one the per-char path already produces. These are
# geometry-free, so they live on the Text domain alongside `read_gesture`.

function _step_left(span_infos, span_idx, char_idx)
    if char_idx > 0
        return (span_idx, char_idx - 1)
    else
        pos = findfirst(si -> si[1] == span_idx, span_infos)
        (pos === nothing || pos == 1) && return nothing  # clamp at document start
        prev = span_infos[pos - 1]
        # Use prev[2]-1 to skip the boundary duplicate (prev[2] == current (span,0) visually)
        return (prev[1], max(0, prev[2] - 1))
    end
end

function _step_right(span_infos, span_idx, char_idx)
    pos = findfirst(si -> si[1] == span_idx, span_infos)
    pos === nothing && return nothing  # clamp
    span_len = span_infos[pos][2]
    if char_idx < span_len
        return (span_idx, char_idx + 1)
    else
        pos == length(span_infos) && return nothing  # clamp at document end
        next = span_infos[pos + 1]
        # Use char 1 to skip the boundary duplicate (char 0 == current (span,span_len) visually)
        return (next[1], next[2] > 0 ? 1 : 0)
    end
end

# Standard editor word class: letters, digits, and underscore are "word" chars;
# everything else is a separator.
_is_word_char(c) = isletter(c) || isdigit(c) || c == '_'

# The character a single step would cross. `char_idx` is the 0-based caret
# offset; span strings are 1-based, so `_char_right` reads index `char_idx+1`
# and `_char_left` reads index `char_idx`. Returns `nothing` at the span ends
# (a step there crosses a span boundary, not a character within this span).
function _char_right(span_text, span_idx, char_idx)
    txt = get(span_text, span_idx, nothing)
    txt === nothing && return nothing
    idx = char_idx + 1
    (idx < 1 || idx > length(txt)) && return nothing
    txt[nextind(txt, 0, idx)]   # idx is a character position; map to a byte index
end

function _char_left(span_text, span_idx, char_idx)
    txt = get(span_text, span_idx, nothing)
    txt === nothing && return nothing
    (char_idx < 1 || char_idx > length(txt)) && return nothing
    txt[nextind(txt, 0, char_idx)]   # char_idx is a character position
end

# Ctrl+Right: skip the current word run, then the separator run → next word start.
function _word_step_right(span_infos, span_text, span_idx, char_idx)
    s, c = span_idx, char_idx
    while (ch = _char_right(span_text, s, c)) !== nothing && _is_word_char(ch)
        nxt = _step_right(span_infos, s, c); nxt === nothing && return (s, c); (s, c) = nxt
    end
    while (ch = _char_right(span_text, s, c)) !== nothing && !_is_word_char(ch)
        nxt = _step_right(span_infos, s, c); nxt === nothing && return (s, c); (s, c) = nxt
    end
    (s, c)
end

# Ctrl+Left: skip the separator run, then the word run → current/previous word start.
function _word_step_left(span_infos, span_text, span_idx, char_idx)
    s, c = span_idx, char_idx
    while (ch = _char_left(span_text, s, c)) !== nothing && !_is_word_char(ch)
        nxt = _step_left(span_infos, s, c); nxt === nothing && return (s, c); (s, c) = nxt
    end
    while (ch = _char_left(span_text, s, c)) !== nothing && _is_word_char(ch)
        nxt = _step_left(span_infos, s, c); nxt === nothing && return (s, c); (s, c) = nxt
    end
    (s, c)
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

# Span-content lookup (path → content String) for word-class testing.
_text_span_text(text::TextBlock) =
    Dict{SpanPath,String}(path => String(_span_content(text, path)::AbstractString)
                          for (path, _) in _text_span_infos(text))

# Insert (replace the selected range with) `str` at the text cursor. The selection
# must carry the `.elements[i].content[range]` shape (or its in-line
# `.elements[i].elements[j].content[range]` form); other shapes decline.
function _text_insert(text::TextBlock, str::AbstractString)
    rng = _text_selection_range(text)
    rng === nothing && return nothing
    path, char_start, char_stop = rng
    ReplaceStringRangeOperation(_text_replace_path(path, char_start, char_stop), str)
end

# Backspace / Delete: replace the appropriate character range with "".
function _text_delete(text::TextBlock, key::Symbol)
    rng = _text_selection_range(text)
    rng === nothing && return nothing
    path, char_start, char_stop = rng
    content = _span_content(text, path)
    content === nothing && return nothing
    n = length(content)
    if key === :backspace
        if char_start != char_stop
            new_range = (char_start, char_stop)
        elseif char_start > 0
            new_range = (char_start - 1, char_start)
        else
            return nothing
        end
    else  # :delete
        if char_start != char_stop
            new_range = (char_start, char_stop)
        elseif char_stop < n
            new_range = (char_stop, char_stop + 1)
        else
            return nothing
        end
    end
    ReplaceStringRangeOperation(_text_replace_path(path, new_range[1], new_range[2]), "")
end

# Ctrl+Home / Ctrl+End: cursor to the very start / end of the text.
function _text_jump(text::TextBlock, where::Symbol)
    span_infos = _text_span_infos(text)
    isempty(span_infos) && return nothing
    where === :start ?
        ReplaceSelectionOperation(_build_selection_path(span_infos[1][1], 0)) :
        ReplaceSelectionOperation(_build_selection_path(span_infos[end][1], span_infos[end][2]))
end

# Ctrl+Left / Ctrl+Right: word-wise cursor motion.
function _text_word_motion(text::TextBlock, direction::Symbol)
    span_infos = _text_span_infos(text)
    isempty(span_infos) && return nothing
    current = _cursor_coord(text.selection)
    current === nothing && return nothing
    span_text = _text_span_text(text)
    s, c = direction === :left ?
        _word_step_left(span_infos, span_text, current.span, current.char) :
        _word_step_right(span_infos, span_text, current.span, current.char)
    ReplaceSelectionOperation(_build_selection_path(s, c))
end

# Left / Right: per-character cursor motion. Declines when a whole element is
# selected (no character cursor to move) so the syntax layer can tree-navigate;
# clamps in place at a document end.
function _text_char_motion(text::TextBlock, direction::Symbol)
    _is_structural_selection(text.selection) && return nothing
    span_infos = _text_span_infos(text)
    isempty(span_infos) && return nothing
    current = _cursor_coord(text.selection)
    current === nothing && return nothing
    nxt = direction === :left ?
        _step_left(span_infos, current.span, current.char) :
        _step_right(span_infos, current.span, current.char)
    s, c = nxt === nothing ? (current.span, current.char) : nxt  # clamp in place
    ReplaceSelectionOperation(_build_selection_path(s, c))
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
# else return nothing.
function _text_selection_range(text::TextBlock)
    # Selections are canonical at rest; strip the TypeReference checkpoints
    # (this parser only extracts integer span/char offsets) before the raw
    # structural walk.
    sel = strip_reference_types(text.selection)
    sel isa ConcreteReferencePath || return nothing
    h1 = sel.head
    (h1 isa FieldReference && h1.name == "elements") || return nothing
    t1 = sel.tail
    t1 isa ConcreteReferencePath || return nothing
    h2 = t1.head
    h2 isa RangeReference || return nothing
    path = Int[h2.start + 1]
    rest = t1.tail
    rest isa ConcreteReferencePath || return nothing
    # One optional hop into a TextLine: `.elements[j]` again before `.content`.
    if rest.head isa FieldReference && rest.head.name == "elements"
        inner = rest.tail
        inner isa ConcreteReferencePath || return nothing
        inner.head isa RangeReference || return nothing
        push!(path, inner.head.start + 1)
        rest = inner.tail
        rest isa ConcreteReferencePath || return nothing
    end
    (rest.head isa FieldReference && rest.head.name == "content") || return nothing
    t3 = rest.tail
    t3 isa ConcreteReferencePath || return nothing
    h4 = t3.head
    h4 isa RangeReference || return nothing
    (path, h4.start::Int, h4.stop::Int)
end

_text_replace_path(path::SpanPath, char_start::Int, char_stop::Int) =
    _elements_prefix(path,
        ConcreteReferencePath(FieldReference("content"),
            ConcreteReferencePath(RangeReference(char_start, char_stop), EmptyReferencePath())))

# `.elements[i]` (— `.elements[j]`) in front of `tail`, one `elements` hop per
# index in `path`.
function _elements_prefix(path::SpanPath, tail)
    ref = tail
    for i in reverse(path)
        ref = ConcreteReferencePath(FieldReference("elements"),
                  ConcreteReferencePath(RangeReference(i - 1, i), ref))
    end
    ref
end

# ── Clipboard support ──────────────────────────────────────────────────────────
# Public helpers used by the clipboard projection's text branch
# (`ClipboardSliceToAnyProjection` in text mode); see
# `plan/done/clipboard-os-bridge-and-run-example-wrapper.md`.

"""
    text_selection_substring(text::TextBlock) -> Union{String,Nothing}

The substring currently selected within a single span, or `nothing` when the
selection is an empty caret, spans no characters, or is not a single-span character
range. Used by the clipboard to copy / cut text.
"""
function text_selection_substring(text::TextBlock)
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
    text_insert_op(text::TextBlock, str) -> Union{Operation,Nothing}

The `ReplaceStringRangeOperation` that inserts `str` at the text cursor, replacing
any selected range. `nothing` when the selection is not a character cursor/range.
The caret advances past the inserted text automatically on evaluation. Used by the
clipboard to paste text.
"""
text_insert_op(text::TextBlock, str::AbstractString) = _text_insert(text, str)

# Parse a character-cursor selection into a `(span::SpanPath, char)` NamedTuple, or
# nothing when the selection is not a character cursor. A caret inside a `TextLine`
# reads as `[i, j]`, one at block level as `[i]`.
function _cursor_coord(sel)
    sel === nothing && return nothing
    @reference_case sel begin
        ::TextBlock.elements{i:_}.elements{j:_}.content{c:_} => (span=Int[i + 1, j + 1], char=c)
        ::TextBlock.elements{i:_}.content{c:_}               => (span=Int[i + 1], char=c)
    end
end

# A whole-element selection projects to either `∅` (the root element) or a
# `TextRectangularReference` box; both mean "structural mode" at this layer.
function _is_structural_selection(sel)
    sel = sel
    sel isa EmptyReferencePath ||
        (sel isa ConcreteReferencePath && sel.head isa TextRectangularReference)
end

_build_selection_path(span_idx::Int, char_idx::Int) =
    _build_selection_path(Int[span_idx], char_idx)

# The caret at `char_idx` in the span at `path`: one `elements` hop per index, so a
# span inside a `TextLine` gets the deeper path. Only the two depths a block can
# actually hold exist, so the checkpointed `@reference` form is written out for
# each rather than assembled step by step.
function _build_selection_path(path::SpanPath, char_idx::Int)
    if length(path) == 1
        i = path[1]
        return @reference ::TextBlock.elements::CellVector[i]::TextString.content::String{char_idx}::Position
    end
    i, j = path[1], path[2]
    @reference ::TextBlock.elements::CellVector[i]::TextLine.elements::CellVector[j]::TextString.content::String{char_idx}::Position
end

# ── set_function! delegation ───────────────────────────────────────────────

set_function!(s::TextString, f::Function) = (set_function!(getfield(s, :content), f); s)
set_function!(st::TextBlock, f::Function) = (set_function!(getfield(st.elements, :elements), () -> Cell[Cell(x) for x in f()]); st)

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
# container adds it (see `text_flat_offsets`) and a line-structured block gets
# `n-1` breaks for `n` lines rather than a phantom trailing one.
text_flat_length(span::TextString) = length(span.content::AbstractString)
text_flat_length(::TextNewline) = 1
text_flat_length(::TextSpacing) = 1
text_flat_length(line::TextLine) =
    line.indentation + sum(text_flat_length(s) for s in line.elements; init = 0)
text_flat_length(::TextDocument) = 0

"""
    text_flat_offsets(text::TextBlock) -> Vector{Int}

The flat character offset each element starts at (0-based), and — as the vector's
`end + 1` entry would be — the block's total flat length. Every `TextLine` but a
leading one is preceded by its implicit break, which is where the `+1` enters;
for a block of plain spans this is just the running sum of `text_flat_length`.

The one place the implicit break is materialized. Anything mapping the flat
character stream back to elements (the console backend, `SelectionInverting`)
must count offsets through this rather than summing `text_flat_length` itself.
"""
function text_flat_offsets(text::TextBlock)
    offsets = Int[]
    pos = 0
    for (k, element) in enumerate(text.elements)
        (element isa TextLine && k > 1) && (pos += 1)   # the break before this line
        push!(offsets, pos)
        pos += text_flat_length(element)
    end
    offsets
end

"""
    text_selection_flat(text::TextBlock) -> (start, stop, is_cursor) or nothing

Resolve `text`'s selection to a flat half-open char range `(start, stop)` over
the concatenated stream (0-based), plus an `is_cursor` flag (a zero-width caret).
Returns `nothing` when there is no renderable selection.

Two shapes occur, both with 0-based offsets:
  • whole-element: top-level `TextRectangularReference(a, b)`, an already-flat
    character range over the concatenated text;
  • text cursor: `.elements[i].content{a:b}`, or `.elements[i].elements[j].content{a:b}`
    inside a line — add the span's base offset.
"""
function text_selection_flat(text::TextBlock)
    # Selections are canonical at rest (carry TypeReference checkpoints); the
    # range parser peels them, but the rectangular shape is read raw.
    sel = text.selection
    sel isa ConcreteReferencePath || return nothing
    h = sel.head
    if h isa TextRectangularReference && sel.tail isa EmptyReferencePath
        return (h.start, h.stop, h.start == h.stop)
    end
    rng = _text_selection_range(text)
    rng === nothing && return nothing
    path, a, b = rng
    base = _flat_base(text, path)
    base === nothing && return nothing
    (base + a, base + b, a == b)
end

# The flat offset the span at `path` starts at, or nothing when the path does not
# land on a span.
function _flat_base(text::TextBlock, path::SpanPath)
    offsets = text_flat_offsets(text)
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
        base += text_flat_length(spans[k])
    end
    base
end

end # module
