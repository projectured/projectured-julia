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

import ..ReactiveModule: Cell, setfn!, setval!
import ..DocumentModule: Document, @document
import ..CollectionModule: CellVector, ListNode, CollectionDocument
import ..FontModule: StyleFont, font_ubuntu_monospace_regular_24
import ..ColorModule: StyleColor, color_default
import ..StyleTextModule: StyleText
import ..GeometryModule: Inset
import ..ReferenceModule: Reference, ConcreteReferencePath, EmptyReferencePath, RangeReference, FieldReference, TextRectangularReference, skip_type_checkpoints, strip_reference_types
import ..ReferenceCaseModule: var"@reference_case"
import ..ReferenceBuilderModule: var"@reference"
import ..OperationApiModule: splice_string, splice_value!
import ..DocumentApiModule: document_read
import ..OperationModule: ReplaceSelectionOperation, ToggleCollapseOperation
import ..PrimitiveModule: StringReplaceRangeOperation
import ..KeyboardModule: KeyDown, KeyPress
import ..EventCaseModule: var"@event_case"
export TextDocument, TextInsertion, TextNewline, TextSpacing, TextString, TextGraphics, TextText, setfn!,
       ITextInsertion, ITextNewline, ITextSpacing, ITextString, ITextGraphics, ITextText,
       text_flat_length, text_selection_flat

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
    value::Any
    selection::Reference
end
TextInsertion() = TextInsertion(Cell(nothing), Cell(nothing))

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
    TextString(Cell(content), Cell(font_ubuntu_monospace_regular_24), Cell(color_default), Cell(nothing), Cell(nothing), Cell(nothing), Cell(nothing))

TextString(content::Function, font::StyleFont, font_color::StyleColor) =
    TextString(Cell(content), Cell(font), Cell(font_color), Cell(nothing), Cell(nothing), Cell(nothing), Cell(nothing))

# StyleText bridge: a projection holding a merged (font, color) style value can
# build a run without unpacking it. The document model itself is unchanged —
# `style` is split into the existing `font` / `font_color` cells.
TextString(content::AbstractString, style::StyleText) = TextString(content, style.font, style.color)
TextString(content::Function,      style::StyleText) = TextString(content, style.font, style.color)

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

TextGraphics(content, width::Integer, height::Integer; font=font_ubuntu_monospace_regular_24, font_color="", fill_color=nothing, line_color=nothing, padding=nothing) =
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
    elements::CollectionDocument
    selection::Reference
end

TextText() = TextText(CellVector(), Cell(nothing))

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

# ── document_read: geometry-free gesture → operation mapping ─────────
#
# The projection-independent half of the Text domain's reader. It reads only the
# span structure (`text.elements`) and the flat-character `text.selection`; it
# never touches pixel geometry (no laid-out coordinate map, no measurement). Any
# projection whose input/output is a `TextText` (e.g. `TextToGraphics` for SDL,
# or the `SyntaxToText` output for the console) delegates here for character
# insert/delete and cross-span cursor movement.
#
# These methods were relocated verbatim from `TextToGraphics`'s reader (the
# geometry-INDEPENDENT arms). The geometry-DEPENDENT arms — visual up/down, plain
# (non-Ctrl) Home/End, and mouse click hit-testing — stay in `TextToGraphics`,
# which needs the laid-out coordinate map.
#
# Returns:
#   - an `Operation` for a handled gesture (char insert, delete, cursor move),
#   - `nothing` for a gesture this layer declines so an outer (syntax) layer can
#     own it — the "decline rules" (Alt+arrows, plain arrows while structural,
#     Tab) and for any unhandled gesture. The `nothing` both means "not handled"
#     and "deliberately declined"; both let the gesture propagate inward.

function document_read(text::TextText, evt)
    evt isa KeyPress && return _text_keypress_op(text, evt)
    evt isa KeyDown  || return nothing

    # Chords and tree-navigation gestures are recognised (or declined) before we
    # touch the character cursor.
    early = @event_case evt begin
        # Fold chord: Ctrl+. toggles collapse of the innermost node containing
        # the cursor. The empty-target operation is resolved upstream at the
        # syntax layer (where the tree and selection live); we only recognise it.
        KeyDown(:period; ctrl) => ToggleCollapseOperation()
        # Alt-modified navigation keys (arrows, Home) are tree-navigation
        # gestures. This layer handles only character/line cursor motion within
        # flat text, so decline them: returning nothing lets the gesture fall
        # through to the syntax layer, which owns the tree structure. Loose alt
        # (any extra modifiers) keeps every alt-arrow a tree gesture.
        when(KeyDown(k), evt.modifiers.alt && k in (:up, :down, :left, :right, :home)) => return nothing
        # In structural mode (a whole-element / rectangular selection) plain
        # arrows are tree navigation too — there is no character cursor to move,
        # so decline them and let the syntax layer step between nodes. Home keeps
        # its text meaning, so it is deliberately excluded here.
        when(KeyDown(k), k in (:up, :down, :left, :right) &&
                         _is_structural_selection(text.selection)) => return nothing
        # Tab has no character-cursor meaning at this layer. Decline it (return
        # nothing) so the Change-threaded reader chain keeps walking inward — the
        # JSON reader uses Tab for key→value navigation.
        KeyDown(:tab) => return nothing
    end
    early === nothing || return early

    del_op = _text_delete_op(text, evt)
    del_op === nothing || return del_op

    span_infos = [(elem_idx, length(span.content::AbstractString))
                  for (elem_idx, span) in enumerate(text.elements)
                  if span isa TextString]
    isempty(span_infos) && return nothing
    # Span-content lookup (elem_idx → content String) for word-class testing.
    span_text = Dict{Int,String}(elem_idx => String(span.content::AbstractString)
                  for (elem_idx, span) in enumerate(text.elements)
                  if span isa TextString)

    jump = @event_case evt begin
        KeyDown(:home; ctrl) => ReplaceSelectionOperation(_build_selection_path(span_infos[1][1], 0))
        KeyDown(:end; ctrl)  => ReplaceSelectionOperation(_build_selection_path(span_infos[end][1], span_infos[end][2]))
    end
    jump === nothing || return jump

    current = _cursor_position(text.selection)
    current === nothing && return nothing

    @event_case evt begin
        # Word-wise motion. Placed before the bare :left/:right rules so it wins
        # (first-match-wins); the bare rules match Left/Right with any modifiers.
        KeyDown(:left; ctrl) => begin
            s, c = _word_step_left(span_infos, span_text, current.span, current.char)
            return ReplaceSelectionOperation(_build_selection_path(s, c))
        end
        KeyDown(:right; ctrl) => begin
            s, c = _word_step_right(span_infos, span_text, current.span, current.char)
            return ReplaceSelectionOperation(_build_selection_path(s, c))
        end
        KeyDown(:left) => begin
            nxt = _step_left(span_infos, current.span, current.char)
            s, c = nxt === nothing ? (current.span, current.char) : nxt  # clamp in place
            return ReplaceSelectionOperation(_build_selection_path(s, c))
        end
        KeyDown(:right) => begin
            nxt = _step_right(span_infos, current.span, current.char)
            s, c = nxt === nothing ? (current.span, current.char) : nxt  # clamp in place
            return ReplaceSelectionOperation(_build_selection_path(s, c))
        end
    end
    return nothing
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

# KeyPress producer: emit a StringReplaceRangeOperation against the input
# TextText's `.elements[i].content[range]` shape. The selection must already
# carry the same shape (i.e. the cursor is positioned inside a TextString span);
# other shapes return `nothing`. Ctrl-modified key presses are not character
# insertions, so they are declined.
function _text_keypress_op(text::TextText, evt::KeyPress)
    evt.modifiers.ctrl && return nothing
    rng = _text_selection_range(text)
    rng === nothing && return nothing
    span_idx, char_start, char_stop = rng
    new_ref = _text_replace_path(span_idx, char_start, char_stop)
    StringReplaceRangeOperation(new_ref, evt.text)
end

# KeyDown handler for Backspace / Delete. Emits a `StringReplaceRangeOperation`
# against the TextText's `.elements[i].content[range]` shape; other keys return
# nothing so the caller can fall through to cursor navigation.
function _text_delete_op(text::TextText, evt::KeyDown)
    (evt.key == :backspace || evt.key == :delete) || return nothing
    rng = _text_selection_range(text)
    rng === nothing && return nothing
    span_idx, char_start, char_stop = rng
    content = _span_content(text, span_idx)
    content === nothing && return nothing
    n = length(content)
    new_range = @event_case evt begin
        KeyDown(:backspace) => begin
            if char_start != char_stop
                (char_start, char_stop)
            elseif char_start > 0
                (char_start - 1, char_start)
            else
                return nothing
            end
        end
        KeyDown(:delete) => begin
            if char_start != char_stop
                (char_start, char_stop)
            elseif char_stop < n
                (char_stop, char_stop + 1)
            else
                return nothing
            end
        end
    end
    new_range === nothing && return nothing
    new_ref = _text_replace_path(span_idx, new_range[1], new_range[2])
    StringReplaceRangeOperation(new_ref, "")
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
    sel = skip_type_checkpoints(sel)
    sel isa EmptyReferencePath ||
        (sel isa ConcreteReferencePath && sel.head isa TextRectangularReference)
end

_build_selection_path(span_idx::Int, char_idx::Int) =
    @reference elements[span_idx].content{char_idx}

# ── setfn! delegation ───────────────────────────────────────────────

setfn!(s::TextString, f::Function) = (setfn!(getfield(s, :content), f); s)
setfn!(st::TextText, f::Function) = (setfn!(getfield(st.elements, :elements), () -> Cell[Cell(x) for x in f()]); st)

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
    sel = skip_type_checkpoints(text.selection)
    sel isa ConcreteReferencePath || return nothing
    h = sel.head
    if h isa TextRectangularReference && skip_type_checkpoints(sel.tail) isa EmptyReferencePath
        return (h.start, h.stop, h.start == h.stop)
    end
    return _text_cursor_flat(text, sel)
end

function _text_cursor_flat(text::TextText, sel::ConcreteReferencePath)
    (sel.head isa FieldReference && sel.head.name == "elements") || return nothing
    # Skip TypeReference checkpoints between each navigation step.
    t1 = skip_type_checkpoints(sel.tail)
    t1 isa ConcreteReferencePath && t1.head isa RangeReference || return nothing
    span_idx = t1.head.start + 1   # 1-based span index
    t2 = skip_type_checkpoints(t1.tail)
    t2 isa ConcreteReferencePath && t2.head isa FieldReference && t2.head.name == "content" || return nothing
    t3 = skip_type_checkpoints(t2.tail)
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
