"""
    TextModule

The text domain bridges the structural (syntax tree) and visual (graphics) domains.
Text is stored as a flat sequence of spans, each with its own reactive style and color.
The selection is a flat character offset, making keyboard navigation straightforward
before the pixel-coordinate layout is applied.

The domain includes:
- **Span types**: `TextString` (text content), `TextNewline` (line break), `TextSpacing` (spacing), `TextGraphics` (embedded graphics)
- **Container type**: `TextText` (sequence of spans)
- **Base type**: `TextDocument` abstract type for all text documents

Selection semantics (`[i]` = 1-based item, `{k}` = 0-based cursor):
- Spans: `.content{k}` — cursor at boundary k within the span's content
- TextText: `.elements[i]` — the i-th span, then `.content{k}` for the cursor within it

Each span has reactive styling fields:
- `font` — font style (e.g., "bold", "italic", "monospace")
- `font_color` — text color (name, hex, or rgb)
- `fill_color` — background fill color
- `line_color` — border/line color
- `padding` — inset/padding value
"""
module TextModule

import ..ReactiveModule: Cell, set_function!, set_value!
import ..DocumentApiModule: Document
import ..DocumentModule: @document
import ..CollectionModule: CellVector, ListNode, CollectionDocument
import ..FontModule: StyleFont, font_ubuntu_monospace_regular_20
import ..ColorModule: StyleColor, color_default, color_solarized_gray
import ..StyleTextModule: StyleText
import ..GeometryModule: Inset
import ..ReferenceModule: Reference, ConcreteReferencePath, EmptyReferencePath, RangeReference, FieldReference, TextRectangularReference, strip_reference_types
import ..ReferenceCaseModule: var"@reference_case"
import ..ReferenceBuilderModule: var"@reference"
import ..OperationModule: ReplaceSelectionOperation, ToggleCollapseOperation, splice_string, splice_value!
import ..PrimitiveModule: ReplaceStringRangeOperation
import ..GestureBindingModule: var"@gestures"
export TextDocument, TextInsertion, TextNewline, TextSpacing, TextString, TextGraphics, TextText, set_function!,
       ITextInsertion, ITextNewline, ITextSpacing, ITextString, ITextGraphics, ITextText,
       text_flat_length, text_selection_flat, hinted_text,
       text_selection_substring, text_insert_op

# ── TextDocument (base) ───────────────────────────────────────────────────

"""
    TextDocument

Abstract base type for all text document types. Every concrete text type
subtypes `TextDocument` and must have a `selection::Reference` field as required
by the `Document` contract.
"""
abstract type TextDocument <: Document end

# ── TextInsertion ────────────────────────────────────────────────────

@document struct TextInsertion <: TextDocument
    value::Any = nothing
    selection::Reference = nothing
end

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
- `selection::Reference` — a `ReferencePath` or `nothing` (stored in a Cell)

# Constructor

- `TextNewline(; font, font_color="", fill_color=nothing, line_color=nothing, padding=nothing)`
"""
@document struct TextNewline <: TextDocument
    font::StyleFont
    font_color::StyleColor
    fill_color::StyleColor
    line_color::StyleColor
    padding::Inset
    selection::Reference
end

TextNewline(; font, font_color="", fill_color=nothing, line_color=nothing, padding=nothing) =
    TextNewline(Cell(font), Cell(font_color), Cell(fill_color), Cell(line_color), Cell(padding), Cell(nothing))

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
- `selection::Reference` — a `ReferencePath` or `nothing` (stored in a Cell)

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
    selection::Reference
end

TextSpacing(size::Number; unit=:pixel, font, font_color="", fill_color=nothing, line_color=nothing, padding=nothing) =
    TextSpacing(Cell(size), Cell(unit), Cell(font), Cell(font_color), Cell(fill_color), Cell(line_color), Cell(padding), Cell(nothing))

# ── TextString ─────────────────────────────────────────────────────

"""
    TextString(content, font, font_color)

A single text span. Each field is a reactive `Cell`.

- `content::Cell`    — holds `AbstractString`
- `font::Cell{StyleFont}` — font specification
- `font_color::Cell` — holds `StyleColor` (RGBA color with components in [0,1])
- `fill_color::Cell` — holds background fill color or `nothing`
- `line_color::Cell` — holds border/line color or `nothing`
- `padding::Cell`    — holds inset/padding value or `nothing`

When a `TextText` selection path descends into a span, the sub-path
refers to the cursor within the span's `content` field:  `.content{k}`
"""
@document struct TextString <: TextDocument
    content::AbstractString
    font::StyleFont
    font_color::StyleColor
    fill_color::StyleColor
    line_color::StyleColor
    padding::Inset
    selection::Reference
end

TextString(content::AbstractString, font::StyleFont, font_color::StyleColor) =
    TextString(Cell(content), Cell(font), Cell(font_color), Cell(nothing), Cell(nothing), Cell(nothing), Cell(nothing))

TextString(content::AbstractString) =
    TextString(Cell(content), Cell(font_ubuntu_monospace_regular_20), Cell(color_default), Cell(nothing), Cell(nothing), Cell(nothing), Cell(nothing))

TextString(content::Function, font::StyleFont, font_color::StyleColor) =
    TextString(Cell(content), Cell(font), Cell(font_color), Cell(nothing), Cell(nothing), Cell(nothing), Cell(nothing))

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
        Cell(style.font),
        Cell(() -> empty_thunk() ? color_solarized_gray : style.color),
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
- `selection::Reference` — a `ReferencePath` or `nothing` (stored in a Cell)

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
    selection::Reference
end

TextGraphics(content, width::Integer, height::Integer; font=font_ubuntu_monospace_regular_20, font_color="", fill_color=nothing, line_color=nothing, padding=nothing) =
    TextGraphics(Cell(content), Cell(Int32(width)), Cell(Int32(height)), Cell(font), Cell(font_color), Cell(fill_color), Cell(line_color), Cell(padding), Cell(nothing))

TextGraphics(content; font, font_color="", fill_color=nothing, line_color=nothing, padding=nothing) =
    TextGraphics(Cell(content), Cell(Int32(0)), Cell(Int32(0)), Cell(font), Cell(font_color), Cell(fill_color), Cell(line_color), Cell(padding), Cell(nothing))

# ── TextText ───────────────────────────────────────────────────────────

"""
    TextText(spans)

A sequence of `TextString` spans. The span list is a reactive `Cell`
holding `Vector{TextString}`, so structural changes (add/remove spans)
are tracked alongside per-span value changes.

The `selection` cell holds a path into the span sequence, or `nothing`:
  `.elements[i]`  — cursor within element i
"""
@document struct TextText <: TextDocument
    elements::CollectionDocument = CellVector()
    selection::Reference = nothing
end

TextText(spans::Vector{<:TextDocument}) =
    TextText(CellVector(Cell[Cell(s) for s in spans]), Cell(nothing))

TextText(spans::TextDocument...) =
    TextText(CellVector(Cell[Cell(s) for s in spans]), Cell(nothing))

TextText(f::Function) = TextText(CellVector(f), Cell(nothing))


# ── splice_value! methods for the text representations ──────────────
#
# These are the two non-string representations of `splice_value!` (declared in
# OperationApiModule). They fire when a replace reference resolves to a field
# whose *value* is a styled span or a flat span sequence — e.g. a SyntaxLeaf's
# `open`/`value`/`close` (each a TextString) or a BookParagraph's TextText
# content. When the target is itself a TextString edited by its `content` field,
# the value read from the field is a plain `String` and the generic
# AbstractString method handles it — no TextString-target method is needed.

# Field value is a styled span: splice its content in place (owner unchanged).
splice_value!(owner, field::Symbol, span::TextString, s::Int, e::Int, replacement::AbstractString) =
    (span.content = splice_string(span.content::AbstractString, s, e, replacement); span)

# Field value is a flat span sequence: the incoming `[s, e]` is a flat offset
# across the concatenated spans. Locate the single `TextString` span the range
# falls inside and edit it; an empty sequence grows a fresh span. Ranges that
# straddle two spans are left for a later multi-span editing pass.
function splice_value!(owner, field::Symbol, text::TextText, s::Int, e::Int, replacement::AbstractString)
    pos = 0
    have_span = false
    for span in text.elements
        span isa TextString || continue
        have_span = true
        len = length(span.content)
        if s >= pos && e <= pos + len
            span.content = splice_string(span.content::AbstractString, s - pos, e - pos, replacement)
            return text
        end
        pos += len
    end
    have_span || push!(text.elements, TextString(replacement))
    text
end

# ── document_read via reified @gestures: geometry-free text editing ───────
#
# The projection-independent half of the Text domain's reader, now a reified
# `@gestures` table on `TextText` (was a `document_read(::TextText)` method); the
# generic `read_document_gesture` interpreter fires it, so the table that fires is
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
@gestures TextText begin
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
# geometry-free, so they live on the Text domain alongside `document_read`.

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
# Each builds the Operation for one `@gestures TextText` rule from the document
# and its selection (the gesture's modifiers are matched in the pattern, so these
# take no event). They return `nothing` to decline — e.g. when the selection is
# not a character cursor — so the gesture keeps propagating inward.

# The (elem_idx, content-length) of each TextString span, in element order — the
# span layout the cursor/word helpers walk.
_text_span_infos(text::TextText) =
    [(elem_idx, length(span.content::AbstractString))
     for (elem_idx, span) in enumerate(text.elements) if span isa TextString]

# Span-content lookup (elem_idx → content String) for word-class testing.
_text_span_text(text::TextText) =
    Dict{Int,String}(elem_idx => String(span.content::AbstractString)
        for (elem_idx, span) in enumerate(text.elements) if span isa TextString)

# Insert (replace the selected range with) `str` at the text cursor. The selection
# must carry the `.elements[i].content[range]` shape; other shapes decline.
function _text_insert(text::TextText, str::AbstractString)
    rng = _text_selection_range(text)
    rng === nothing && return nothing
    span_idx, char_start, char_stop = rng
    ReplaceStringRangeOperation(_text_replace_path(span_idx, char_start, char_stop), str)
end

# Backspace / Delete: replace the appropriate character range with "".
function _text_delete(text::TextText, key::Symbol)
    rng = _text_selection_range(text)
    rng === nothing && return nothing
    span_idx, char_start, char_stop = rng
    content = _span_content(text, span_idx)
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
    ReplaceStringRangeOperation(_text_replace_path(span_idx, new_range[1], new_range[2]), "")
end

# Ctrl+Home / Ctrl+End: cursor to the very start / end of the text.
function _text_jump(text::TextText, where::Symbol)
    span_infos = _text_span_infos(text)
    isempty(span_infos) && return nothing
    where === :start ?
        ReplaceSelectionOperation(_build_selection_path(span_infos[1][1], 0)) :
        ReplaceSelectionOperation(_build_selection_path(span_infos[end][1], span_infos[end][2]))
end

# Ctrl+Left / Ctrl+Right: word-wise cursor motion.
function _text_word_motion(text::TextText, direction::Symbol)
    span_infos = _text_span_infos(text)
    isempty(span_infos) && return nothing
    current = _cursor_position(text.selection)
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
function _text_char_motion(text::TextText, direction::Symbol)
    _is_structural_selection(text.selection) && return nothing
    span_infos = _text_span_infos(text)
    isempty(span_infos) && return nothing
    current = _cursor_position(text.selection)
    current === nothing && return nothing
    nxt = direction === :left ?
        _step_left(span_infos, current.span, current.char) :
        _step_right(span_infos, current.span, current.char)
    s, c = nxt === nothing ? (current.span, current.char) : nxt  # clamp in place
    ReplaceSelectionOperation(_build_selection_path(s, c))
end

# Extract the i-th span's content when it's a TextString; nothing otherwise.
function _span_content(text::TextText, span_idx::Int)
    elements = text.elements
    (span_idx < 1 || span_idx > length(elements)) && return nothing
    span = elements[span_idx]
    span isa TextString || return nothing
    span.content::AbstractString
end

# Parse `text.selection[]` into (span_idx, char_start, char_stop) when it
# matches `.elements[i].content[s:e]`, else return nothing.
function _text_selection_range(text::TextText)
    # Selections are canonical at rest; strip the TypeReference checkpoints
    # (this parser only extracts integer span/char offsets) before the raw
    # structural walk over `.elements[i].content[s:e]`.
    sel = strip_reference_types(text.selection)
    sel isa ConcreteReferencePath || return nothing
    h1 = sel.head
    (h1 isa FieldReference && h1.name == "elements") || return nothing
    t1 = sel.tail
    t1 isa ConcreteReferencePath || return nothing
    h2 = t1.head
    h2 isa RangeReference || return nothing
    span_idx = h2.start + 1
    t2 = t1.tail
    t2 isa ConcreteReferencePath || return nothing
    h3 = t2.head
    (h3 isa FieldReference && h3.name == "content") || return nothing
    t3 = t2.tail
    t3 isa ConcreteReferencePath || return nothing
    h4 = t3.head
    h4 isa RangeReference || return nothing
    (span_idx, h4.start::Int, h4.stop::Int)
end

function _text_replace_path(span_idx::Int, char_start::Int, char_stop::Int)
    ConcreteReferencePath(FieldReference("elements"),
        ConcreteReferencePath(RangeReference(span_idx - 1, span_idx),
            ConcreteReferencePath(FieldReference("content"),
                ConcreteReferencePath(RangeReference(char_start, char_stop), EmptyReferencePath()))))
end

# ── Clipboard support ──────────────────────────────────────────────────────────
# Public helpers used by the clipboard projection's text branch
# (`ClipboardSliceToAnyProjection` in text mode); see
# `plan/done/clipboard-os-bridge-and-run-example-wrapper.md`.

"""
    text_selection_substring(text::TextText) -> Union{String,Nothing}

The substring currently selected within a single span, or `nothing` when the
selection is an empty caret, spans no characters, or is not a single-span character
range. Used by the clipboard to copy / cut text.
"""
function text_selection_substring(text::TextText)
    rng = _text_selection_range(text)
    rng === nothing && return nothing
    span_idx, a, b = rng
    a == b && return nothing                         # empty caret — nothing to copy
    content = _span_content(text, span_idx)
    content === nothing && return nothing
    chars = collect(content)
    (a < 0 || b > length(chars) || a > b) && return nothing
    String(chars[a + 1:b])
end

"""
    text_insert_op(text::TextText, str) -> Union{Operation,Nothing}

The `ReplaceStringRangeOperation` that inserts `str` at the text cursor, replacing
any selected range. `nothing` when the selection is not a character cursor/range.
The caret advances past the inserted text automatically on evaluation. Used by the
clipboard to paste text.
"""
text_insert_op(text::TextText, str::AbstractString) = _text_insert(text, str)

# Parse a flat-character cursor selection (`.elements[i].content{c}`) into a
# (span, char) NamedTuple, or nothing when the selection is not a character
# cursor.
function _cursor_position(sel)
    sel === nothing && return nothing
    @reference_case sel begin
        elements{s:_}.content{c:_} => (span=s + 1, char=c)
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
    @reference elements[span_idx].content{char_idx}

# ── set_function! delegation ───────────────────────────────────────────────

set_function!(s::TextString, f::Function) = (set_function!(getfield(s, :content), f); s)
set_function!(st::TextText, f::Function) = (set_function!(getfield(st.elements, :elements), () -> Cell[Cell(x) for x in f()]); st)

# ── Selection → flat character range ───────────────────────────────
#
# Shared helper: resolve a TextText's selection to a flat half-open char range
# over the concatenated rendered stream. The console backend and the
# `SelectionInverting` projection both consume this single source of truth (the
# graphics pipeline computes its cursor rect from span-local offsets instead).

# The flat length a span contributes to the rendered character stream, matching
# how the selection's offsets are counted: TextString → its content length,
# TextNewline / TextSpacing → 1, anything else → 0.
text_flat_length(span::TextString) = length(span.content::AbstractString)
text_flat_length(::TextNewline) = 1
text_flat_length(::TextSpacing) = 1
text_flat_length(::TextDocument) = 0

"""
    text_selection_flat(text::TextText) -> (start, stop, is_cursor) or nothing

Resolve `text`'s selection to a flat half-open char range `(start, stop)` over
the concatenated stream (0-based), plus an `is_cursor` flag (a zero-width caret).
Returns `nothing` when there is no renderable selection.

Two shapes occur, both with 0-based offsets:
  • whole-element: top-level `TextRectangularReference(a, b)`, an already-flat
    character range over the concatenated text;
  • text cursor: `.elements[i].content{a:b}` — add the i-th span's base offset.
"""
function text_selection_flat(text::TextText)
    # Selections are canonical at rest (carry TypeReference checkpoints); peel
    # leading ones so the structural checks below see the plain navigation steps.
    sel = text.selection
    sel isa ConcreteReferencePath || return nothing
    h = sel.head
    if h isa TextRectangularReference && sel.tail isa EmptyReferencePath
        return (h.start, h.stop, h.start == h.stop)
    end
    return _text_cursor_flat(text, sel)
end

function _text_cursor_flat(text::TextText, sel::ConcreteReferencePath)
    (sel.head isa FieldReference && sel.head.name == "elements") || return nothing
    # Skip TypeReference checkpoints between each navigation step.
    t1 = sel.tail
    t1 isa ConcreteReferencePath && t1.head isa RangeReference || return nothing
    span_idx = t1.head.start + 1   # 1-based span index
    t2 = t1.tail
    t2 isa ConcreteReferencePath && t2.head isa FieldReference && t2.head.name == "content" || return nothing
    t3 = t2.tail
    t3 isa ConcreteReferencePath && t3.head isa RangeReference || return nothing
    a, b = t3.head.start, t3.head.stop
    elements = text.elements
    (1 <= span_idx <= length(elements)) || return nothing
    base = 0
    for i in 1:(span_idx - 1)
        base += text_flat_length(elements[i])
    end
    return (base + a, base + b, a == b)
end

end # module
