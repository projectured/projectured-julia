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
import ..OperationModule: ReplaceSelectionOperation
import ..KeyboardModule: KeyDown, KeyPress
import ..TypeDispatchingModule: TypeDispatchingProjection
export PrimitiveBoolToText, PrimitiveNumberToText, PrimitiveStringToText, PrimitiveToText

# Forward: .value[k] on the primitive → .elements[1].content[k] on the TextText.
function _forward_value(reference)
    reference isa ConcreteReferencePath || return nothing
    h = reference.head
    h isa FieldReference && h.name == "value" || return nothing
    rest = reference.tail
    rest isa ConcreteReferencePath || return nothing
    inner = rest.head
    inner isa RangeReference || return nothing
    k = inner.start::Int
    ReferencePath(FieldReference("elements"), ElementReference(1),
                  FieldReference("content"), PositionReference(k))
end

# Backward: .elements[1].content[k] on the TextText → .value[k] on the primitive.
function _backward_value(reference)
    reference isa ConcreteReferencePath || return nothing
    h1 = reference.head
    h1 isa FieldReference && h1.name == "elements" || return nothing
    t1 = reference.tail
    t1 isa ConcreteReferencePath || return nothing
    h2 = t1.head
    h2 isa RangeReference || return nothing
    h2.start + 1 == 1 || return nothing
    t2 = t1.tail
    t2 isa ConcreteReferencePath || return nothing
    h3 = t2.head
    h3 isa FieldReference && h3.name == "content" || return nothing
    t3 = t2.tail
    t3 isa ConcreteReferencePath || return nothing
    h4 = t3.head
    h4 isa RangeReference || return nothing
    ConcreteReferencePath(FieldReference("value"),
        ConcreteReferencePath(PositionReference(h4.start::Int)))
end

# Translates a PrimitiveDocument's `.value[k]` / `.value[range]` selection
# into the single-span TextText shape `.elements[1].content[k]`. Range
# selections collapse to a cursor at `range.start` (matching SyntaxLeafToText).
function _value_selection_to_text(prim)
    sel = getfield(prim, :selection)[]
    sel isa ConcreteReferencePath || return nothing
    h = sel.head
    h isa FieldReference && h.name == "value" || return nothing
    rest = sel.tail
    rest isa ConcreteReferencePath || return nothing
    inner = rest.head
    inner isa RangeReference || return nothing
    k = inner.start::Int
    ReferencePath(FieldReference("elements"), ElementReference(1),
                  FieldReference("content"), PositionReference(k))
end

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

function projection_print(p::PrimitiveBoolToText, b::PrimitiveBool, recursion, reference)
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

function projection_print(p::PrimitiveNumberToText, n::PrimitiveNumber, recursion, reference)
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

# ── PrimitiveStringToText ────────────────────────────────────────────────────

struct PrimitiveStringToText <: Projection
    font::StyleFont
    color::StyleColor
end
PrimitiveStringToText(; font=font_ubuntu_monospace_regular_24, color=color_solarized_green) =
    PrimitiveStringToText(font, color)

map_reference_forward(::PrimitiveStringToText, iomap::SimpleIoMap, reference) =
    _forward_value(reference)
map_reference_backward(::PrimitiveStringToText, iomap::SimpleIoMap, reference) =
    _backward_value(reference)

function projection_print(p::PrimitiveStringToText, s::PrimitiveString, recursion, reference)
    span = TextString(() -> something(s.value, ""), p.font, p.color)
    out = TextText(CellVector(() -> TextDocument[span]),
                   Cell(() -> _value_selection_to_text(s)))
    SimpleIoMap(p, s, out)
end

function projection_read(p::PrimitiveStringToText, iomap::SimpleIoMap, op::ReplaceSelectionOperation)
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

function _string_value_path(range::RangeReference)
    ConcreteReferencePath(FieldReference("value"),
        ConcreteReferencePath(range, EmptyReferencePath()))
end

function projection_read(p::PrimitiveStringToText, iomap::SimpleIoMap, evt::KeyPress)
    evt.modifiers.ctrl && return nothing
    s = iomap.input
    range = _string_value_range(s)
    range === nothing && return nothing
    StringReplaceRangeOperation(_string_value_path(range), evt.text)
end

function projection_read(p::PrimitiveStringToText, iomap::SimpleIoMap, evt::KeyDown)
    s = iomap.input
    range = _string_value_range(s)
    range === nothing && return nothing
    text = something(s.value, "")
    n = length(text)
    new_range = if evt.key == :backspace
        if range.start != range.stop
            range
        elseif range.start > 0
            RangeReference(range.start - 1, range.start)
        else
            return nothing
        end
    elseif evt.key == :delete
        if range.start != range.stop
            range
        elseif range.stop < n
            RangeReference(range.stop, range.stop + 1)
        else
            return nothing
        end
    else
        return nothing
    end
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
        PrimitiveString => PrimitiveStringToText(; string_kw...),
    )
end

end # module
