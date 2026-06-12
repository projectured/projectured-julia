"""
    PrimitiveToSyntaxModule

PrimitiveDocument → SyntaxLeaf projection. Converts `PrimitiveBool`,
`PrimitiveNumber`, and `PrimitiveString` into `SyntaxLeaf` nodes
with appropriate delimiters and colors.
"""
module PrimitiveToSyntaxModule

import ..ProjectionApiModule: projection_print, projection_read, map_reference_forward, map_reference_backward, Projection
import ..PrimitiveModule: PrimitiveDocument, PrimitiveBool, PrimitiveNumber, PrimitiveString,
                          StringReplaceRangeOperation, NumberReplaceRangeOperation
import ..SyntaxModule: SyntaxLeaf
import ..TextModule: TextString
import ..FontModule: StyleFont, font_ubuntu_monospace_regular_24
import ..ColorModule: StyleColor, color_default, color_solarized_magenta, color_solarized_cyan, color_solarized_green, color_solarized_yellow
import ..IoMapModule: SimpleIoMap
import ..IoMapApiModule: IoMap
import ..ReferenceModule: ConcreteReferencePath, EmptyReferencePath, FieldReference, RangeReference
import ..ReferenceBuilderModule: var"@reference"
import ..ReferenceCaseModule: var"@reference_case"
import ..OperationModule: ReplaceSelectionOperation
import ..KeyboardModule: KeyDown, KeyPress
import ..EventCaseModule: var"@event_case"
export PrimitiveBoolToSyntaxLeaf, PrimitiveNumberToSyntaxLeaf, PrimitiveStringToSyntaxLeaf,
       PrimitiveToSyntax

# ── PrimitiveBoolToSyntaxLeaf ────────────────────────────────────────────────

struct PrimitiveBoolToSyntaxLeaf <: Projection
    font::StyleFont
    color::StyleColor
end
PrimitiveBoolToSyntaxLeaf(; font=font_ubuntu_monospace_regular_24, color=color_solarized_cyan) =
    PrimitiveBoolToSyntaxLeaf(font, color)

function map_reference_forward(::PrimitiveBoolToSyntaxLeaf, iomap::SimpleIoMap, reference)
    @reference_case reference begin
        value{k} => @reference value{k}
    end
end

function map_reference_backward(::PrimitiveBoolToSyntaxLeaf, iomap::SimpleIoMap, reference)
    @reference_case reference begin
        value{k} => @reference value{k}
    end
end

function projection_print(p::PrimitiveBoolToSyntaxLeaf, recursion, b::PrimitiveBool, ctx)
    SimpleIoMap(p, b, SyntaxLeaf(TextString("", p.font, color_default), TextString("", p.font, color_default),
                                  TextString(() -> string(b.value), p.font, p.color), getfield(b, :selection)))
end

function projection_read(::PrimitiveBoolToSyntaxLeaf, iomap::SimpleIoMap, op::ReplaceSelectionOperation)
    path = op.path
    path isa ConcreteReferencePath || return nothing
    h = path.head
    h isa FieldReference && h.name == "value" || return nothing
    return op
end

# ── PrimitiveNumberToSyntaxLeaf ──────────────────────────────────────────────

struct PrimitiveNumberToSyntaxLeaf <: Projection
    font::StyleFont
    color::StyleColor
end
PrimitiveNumberToSyntaxLeaf(; font=font_ubuntu_monospace_regular_24, color=color_solarized_magenta) =
    PrimitiveNumberToSyntaxLeaf(font, color)

function map_reference_forward(::PrimitiveNumberToSyntaxLeaf, iomap::SimpleIoMap, reference)
    @reference_case reference begin
        value{k} => @reference value{k}
    end
end

function map_reference_backward(::PrimitiveNumberToSyntaxLeaf, iomap::SimpleIoMap, reference)
    @reference_case reference begin
        value{k} => @reference value{k}
    end
end

function projection_print(p::PrimitiveNumberToSyntaxLeaf, recursion, n::PrimitiveNumber, ctx)
    SimpleIoMap(p, n, SyntaxLeaf(TextString("", p.font, color_default), TextString("", p.font, color_default),
                                  TextString(() -> string(n.value), p.font, p.color), getfield(n, :selection)))
end

function projection_read(::PrimitiveNumberToSyntaxLeaf, iomap::SimpleIoMap, op::ReplaceSelectionOperation)
    path = op.path
    path isa ConcreteReferencePath || return nothing
    h = path.head
    h isa FieldReference && h.name == "value" || return nothing
    return op
end

# ── PrimitiveStringToSyntaxLeaf ──────────────────────────────────────────────

struct PrimitiveStringToSyntaxLeaf <: Projection
    quote_font::StyleFont
    quote_color::StyleColor
    value_font::StyleFont
    value_color::StyleColor
end
PrimitiveStringToSyntaxLeaf(; quote_font=font_ubuntu_monospace_regular_24, quote_color=color_solarized_yellow,
                               value_font=font_ubuntu_monospace_regular_24, value_color=color_solarized_green) =
    PrimitiveStringToSyntaxLeaf(quote_font, quote_color, value_font, value_color)

function map_reference_forward(::PrimitiveStringToSyntaxLeaf, iomap::SimpleIoMap, reference)
    @reference_case reference begin
        value{k} => @reference value{k}
    end
end

function map_reference_backward(::PrimitiveStringToSyntaxLeaf, iomap::SimpleIoMap, reference)
    @reference_case reference begin
        value{k} => @reference value{k}
    end
end

function projection_print(p::PrimitiveStringToSyntaxLeaf, recursion, s::PrimitiveString, ctx)
    SimpleIoMap(p, s, SyntaxLeaf(
        TextString("\"", p.quote_font, p.quote_color),
        TextString("\"", p.quote_font, p.quote_color),
        TextString(() -> something(s.value, ""), p.value_font, p.value_color),
        getfield(s, :selection)))
end

function projection_read(p::PrimitiveStringToSyntaxLeaf, iomap::SimpleIoMap, op::ReplaceSelectionOperation)
    path = op.path
    path isa ConcreteReferencePath || return nothing
    h = path.head
    h isa FieldReference || return nothing
    if h.name == "value"
        return op
    else
        return ReplaceSelectionOperation(ConcreteReferencePath(ProjectionReference(p, path)))
    end
end

# Extract the `.value[range]` selection on a PrimitiveString as a
# RangeReference, or return nothing if the selection is in a different shape.
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

# Build a `.value[range]` reference path local to the PrimitiveString. The
# caller is responsible for prepending any outer steps; for a single
# PrimitiveString root, this path is already the full reference.
function _string_value_path(range::RangeReference)
    ConcreteReferencePath(FieldReference("value"),
        ConcreteReferencePath(range, EmptyReferencePath()))
end

# KeyPress producer: printable character insertion / range replacement.
# The reference is local to the PrimitiveString (no outer steps); translating
# through enclosing projections for nested PrimitiveStrings is a follow-up.
function projection_read(p::PrimitiveStringToSyntaxLeaf, iomap::SimpleIoMap, evt::KeyPress)
    evt.modifiers.ctrl && return nothing
    s = iomap.input
    range = _string_value_range(s)
    range === nothing && return nothing
    StringReplaceRangeOperation(_string_value_path(range), evt.text)
end

# KeyDown producer: Backspace / Delete.
function projection_read(p::PrimitiveStringToSyntaxLeaf, iomap::SimpleIoMap, evt::KeyDown)
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

# ── PrimitiveToSyntax (composite) ────────────────────────────────────────────

import ..TypeDispatchingModule: TypeDispatchingProjection
import ..ReferenceModule: ProjectionReference
import ..PrinterContextModule: child_context

"""
    PrimitiveToSyntax()

Composite projection that converts all `PrimitiveDocument` types to
`SyntaxLeaf` nodes. Wrap the result in `RecursiveProjection` at the call
site if recursive child dispatch is needed.
"""
function PrimitiveToSyntax(; bool_kw=(), number_kw=(), string_kw=())
    TypeDispatchingProjection(
        PrimitiveBool   => PrimitiveBoolToSyntaxLeaf(; bool_kw...),
        PrimitiveNumber => PrimitiveNumberToSyntaxLeaf(; number_kw...),
        PrimitiveString => PrimitiveStringToSyntaxLeaf(; string_kw...),
    )
end

end # module
