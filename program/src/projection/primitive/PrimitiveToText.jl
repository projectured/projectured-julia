"""
    PrimitiveToTextModule

PrimitiveDocument → TextText projection. Converts `PrimitiveBool`,
`PrimitiveNumber`, and `PrimitiveString` directly into a single-span
`TextText` without an intervening `SyntaxLeaf`. Used by widget labels,
conversation cells, and other contexts that aggregate styled spans and
want a primitive value to land in the text domain directly.
"""
module PrimitiveToTextModule

import ..ReactiveModule: Cell
import ..CollectionModule: CellVector
import ..ProjectionApiModule: projection_print, projection_read, map_reference_forward, map_reference_backward, Projection
import ..PrimitiveModule: PrimitiveDocument, PrimitiveBool, PrimitiveNumber, PrimitiveString,
                          StringReplaceRangeOperation
import ..TextModule: TextDocument, TextText, TextString
import ..FontModule: StyleFont, font_ubuntu_monospace_regular_24
import ..ColorModule: StyleColor, color_solarized_cyan, color_solarized_magenta, color_solarized_green
import ..IoMapModule: SimpleIoMap
import ..ReferenceModule: ConcreteReferencePath, EmptyReferencePath, FieldReference, RangeReference,
                          ElementReference, PositionReference, ReferencePath
import ..ReferenceCaseModule: var"@reference_case"
import ..ReferenceBuilderModule: var"@reference"
import ..OperationModule: ReplaceSelectionOperation
import ..KeyboardModule: KeyDown, KeyPress
import ..EventCaseModule: var"@event_case"
import ..TypeDispatchingModule: TypeDispatchingProjection
import ..PrinterContextModule: child_context
export PrimitiveBoolToText, PrimitiveNumberToText, PrimitiveStringToTextText, PrimitiveToText

# Forward: .value[k] on the primitive → .elements[1].content[k] on the TextText.
# Range selections collapse to a cursor at the range start.
function _forward_value(reference)
    @reference_case reference begin
        value{s:e} => @reference elements[1].content{s}
    end
end

# Backward: .elements[1].content[k] on the TextText → .value[k] on the primitive.
function _backward_value(reference)
    @reference_case reference begin
        elements[1].content{s:e} => @reference value{s}
    end
end

# Translates a PrimitiveDocument's `.value[k]` / `.value[range]` selection
# into the single-span TextText shape `.elements[1].content[k]`. Range
# selections collapse to a cursor at `range.start` (matching SyntaxLeafToText).
_value_selection_to_text(prim) = _forward_value(getfield(prim, :selection)[])

# ── PrimitiveBoolToText ──────────────────────────────────────────────────────

struct PrimitiveBoolToText <: Projection
    font::StyleFont
    color::StyleColor
end
PrimitiveBoolToText(; font=font_ubuntu_monospace_regular_24, color=color_solarized_cyan) =
    PrimitiveBoolToText(font, color)

map_reference_forward(::PrimitiveBoolToText, iomap::SimpleIoMap, reference) =
    _forward_value(reference)
map_reference_backward(::PrimitiveBoolToText, iomap::SimpleIoMap, reference) =
    _backward_value(reference)

function projection_print(p::PrimitiveBoolToText, recursion, b::PrimitiveBool, ctx)
    span = TextString(() -> string(b.value), p.font, p.color)
    out = TextText(CellVector(() -> TextDocument[span]),
                   Cell(() -> _value_selection_to_text(b)))
    SimpleIoMap(p, b, out)
end

function projection_read(p::PrimitiveBoolToText, iomap::SimpleIoMap, op::ReplaceSelectionOperation)
    input_path = _backward_value(op.path)
    input_path === nothing && return nothing
    ReplaceSelectionOperation(input_path)
end

# ── PrimitiveNumberToText ────────────────────────────────────────────────────

struct PrimitiveNumberToText <: Projection
    font::StyleFont
    color::StyleColor
end
PrimitiveNumberToText(; font=font_ubuntu_monospace_regular_24, color=color_solarized_magenta) =
    PrimitiveNumberToText(font, color)

map_reference_forward(::PrimitiveNumberToText, iomap::SimpleIoMap, reference) =
    _forward_value(reference)
map_reference_backward(::PrimitiveNumberToText, iomap::SimpleIoMap, reference) =
    _backward_value(reference)

function projection_print(p::PrimitiveNumberToText, recursion, n::PrimitiveNumber, ctx)
    span = TextString(() -> string(something(n.value, "")), p.font, p.color)
    out = TextText(CellVector(() -> TextDocument[span]),
                   Cell(() -> _value_selection_to_text(n)))
    SimpleIoMap(p, n, out)
end

function projection_read(p::PrimitiveNumberToText, iomap::SimpleIoMap, op::ReplaceSelectionOperation)
    input_path = _backward_value(op.path)
    input_path === nothing && return nothing
    ReplaceSelectionOperation(input_path)
end

# ── PrimitiveStringToTextText ────────────────────────────────────────────────────

struct PrimitiveStringToTextText <: Projection
    font::StyleFont
    color::StyleColor
    # Hint shown when the value is empty. `placeholder == ""` disables it, so
    # the projection keeps its plain (placeholder-free) behavior by default.
    placeholder::String
    placeholder_font::StyleFont
    placeholder_color::StyleColor
end
PrimitiveStringToTextText(; font=font_ubuntu_monospace_regular_24, color=color_solarized_green,
                            placeholder="", placeholder_font=font, placeholder_color=color) =
    PrimitiveStringToTextText(font, color, placeholder, placeholder_font, placeholder_color)

map_reference_forward(::PrimitiveStringToTextText, iomap::SimpleIoMap, reference) =
    _forward_value(reference)
map_reference_backward(::PrimitiveStringToTextText, iomap::SimpleIoMap, reference) =
    _backward_value(reference)

function projection_print(p::PrimitiveStringToTextText, recursion, s::PrimitiveString, ctx)
    value_span = TextString(() -> something(s.value, ""), p.font, p.color)
    # When the value is empty and a placeholder is configured, show a muted hint
    # span instead. Both spans keep a stable identity; the CellVector thunk only
    # swaps which one is element 1 at the empty↔non-empty boundary, and the
    # selection (mapped to `elements[1].content`) tracks `s.value` either way.
    placeholder_span = TextString(p.placeholder, p.placeholder_font, p.placeholder_color)
    show_placeholder() = !isempty(p.placeholder) && isempty(something(s.value, ""))
    out = TextText(CellVector(() -> TextDocument[show_placeholder() ? placeholder_span : value_span]),
                   Cell(() -> _value_selection_to_text(s)))
    SimpleIoMap(p, s, out)
end

function projection_read(p::PrimitiveStringToTextText, iomap::SimpleIoMap, op::ReplaceSelectionOperation)
    input_path = _backward_value(op.path)
    input_path === nothing && return nothing
    ReplaceSelectionOperation(input_path)
end

# Extract a `.value[range]` selection on a PrimitiveString as a RangeReference.
function _string_value_range(s::PrimitiveString)
    sel = getfield(s, :selection)[]
    sel isa ConcreteReferencePath || return nothing
    head = sel.head
    (head isa FieldReference && head.name == "value") || return nothing
    inner = sel.tail
    inner isa ConcreteReferencePath || return nothing
    inner.head isa RangeReference || return nothing
    inner.head
end

_string_value_path(range::RangeReference) = @reference value.^(range)

function projection_read(p::PrimitiveStringToTextText, iomap::SimpleIoMap, evt::KeyPress)
    evt.modifiers.ctrl && return nothing
    s = iomap.input
    range = _string_value_range(s)
    range === nothing && return nothing
    StringReplaceRangeOperation(_string_value_path(range), evt.text)
end

function projection_read(p::PrimitiveStringToTextText, iomap::SimpleIoMap, evt::KeyDown)
    s = iomap.input
    range = _string_value_range(s)
    range === nothing && return nothing
    text = something(s.value, "")
    n = length(text)
    new_range = @event_case evt begin
        KeyDown(:backspace) => begin
            if range.start != range.stop
                range
            elseif range.start > 0
                RangeReference(range.start - 1, range.start)
            else
                return nothing
            end
        end
        KeyDown(:delete) => begin
            if range.start != range.stop
                range
            elseif range.stop < n
                RangeReference(range.stop, range.stop + 1)
            else
                return nothing
            end
        end
    end
    new_range === nothing && return nothing
    StringReplaceRangeOperation(_string_value_path(new_range), "")
end

# ── PrimitiveToText (composite) ──────────────────────────────────────────────

"""
    PrimitiveToText(; bool_kw=(), number_kw=(), string_kw=())

Composite projection that converts all `PrimitiveDocument` types directly
to single-span `TextText` documents.
"""
function PrimitiveToText(; bool_kw=(), number_kw=(), string_kw=())
    TypeDispatchingProjection(
        PrimitiveBool   => PrimitiveBoolToText(; bool_kw...),
        PrimitiveNumber => PrimitiveNumberToText(; number_kw...),
        PrimitiveString => PrimitiveStringToTextText(; string_kw...),
    )
end

end # module
