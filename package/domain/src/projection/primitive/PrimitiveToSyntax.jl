"""
    PrimitiveToSyntaxModule

PrimitiveDocument → SyntaxLeaf projection. Converts `PrimitiveBool`,
`PrimitiveNumber`, and `PrimitiveString` into `SyntaxLeaf` nodes
with appropriate delimiters and colors.
"""
module PrimitiveToSyntaxModule

import ..ProjectionApiModule: projection_print, projection_read, map_reference_forward, map_reference_backward, Projection
import ..ProjectionModule: var"@projection"
import ..ReactiveModule: Cell
import ..PrimitiveModule: PrimitiveDocument, PrimitiveBool, PrimitiveNumber, PrimitiveString,
                          StringReplaceRangeOperation, NumberReplaceRangeOperation
import ..SyntaxModule: SyntaxLeaf
import ..TextModule: TextString
import ..FontModule: StyleFont, font_ubuntu_monospace_regular_24
import ..ColorModule: StyleColor, color_default, color_solarized_magenta, color_solarized_cyan, color_solarized_green, color_solarized_yellow
import ..StyleTextModule: StyleText
import ..IoMapModule: SimpleIoMap
import ..IoMapApiModule: IoMap
import ..ReferenceModule: ConcreteReferencePath, EmptyReferencePath, FieldReference, RangeReference, skip_type_checkpoints
import ..ReferenceBuilderModule: var"@reference"
import ..ReferenceCaseModule: var"@reference_case"
import ..OperationModule: ReplaceSelectionOperation
import ..KeyboardModule: KeyDown, KeyPress
import ..EventCaseModule: var"@event_case"
export PrimitiveBoolToSyntaxLeaf, PrimitiveNumberToSyntaxLeaf, PrimitiveStringToSyntaxLeaf,
       PrimitiveToSyntax

# ── PrimitiveBoolToSyntaxLeaf ────────────────────────────────────────────────

@projection struct PrimitiveBoolToSyntaxLeaf <: Projection
    style::StyleText = StyleText(font_ubuntu_monospace_regular_24, color_solarized_cyan)
end

function map_reference_forward(::PrimitiveBoolToSyntaxLeaf, iomap::SimpleIoMap, reference)
    @reference_case reference begin
        ::PrimitiveBool.value{k} => @reference ::SyntaxLeaf.value::TextString{k}
    end
end

function map_reference_backward(::PrimitiveBoolToSyntaxLeaf, iomap::SimpleIoMap, reference)
    @reference_case reference begin
        ::SyntaxLeaf.value{k} => @reference ::PrimitiveBool.value::Bool{k}
    end
end

function projection_print(p::PrimitiveBoolToSyntaxLeaf, recursion, b::PrimitiveBool, ctx)
    SimpleIoMap(p, b, SyntaxLeaf(TextString(() -> string(b.value), p.style); selection=getfield(b, :selection)))
end

function projection_read(::PrimitiveBoolToSyntaxLeaf, iomap::SimpleIoMap, op::ReplaceSelectionOperation)
    path = skip_type_checkpoints(op.path)
    path isa ConcreteReferencePath || return nothing
    h = path.head
    h isa FieldReference && h.name == "value" || return nothing
    return op
end

# ── PrimitiveNumberToSyntaxLeaf ──────────────────────────────────────────────

@projection struct PrimitiveNumberToSyntaxLeaf <: Projection
    style::StyleText = StyleText(font_ubuntu_monospace_regular_24, color_solarized_magenta)
end

function map_reference_forward(::PrimitiveNumberToSyntaxLeaf, iomap::SimpleIoMap, reference)
    @reference_case reference begin
        ::PrimitiveNumber.value{k} => @reference ::SyntaxLeaf.value::TextString{k}
    end
end

function map_reference_backward(::PrimitiveNumberToSyntaxLeaf, iomap::SimpleIoMap, reference)
    @reference_case reference begin
        ::SyntaxLeaf.value{k} => @reference ::PrimitiveNumber.value::Number{k}
    end
end

function projection_print(p::PrimitiveNumberToSyntaxLeaf, recursion, n::PrimitiveNumber, ctx)
    SimpleIoMap(p, n, SyntaxLeaf(TextString(() -> string(n.value), p.style); selection=getfield(n, :selection)))
end

function projection_read(::PrimitiveNumberToSyntaxLeaf, iomap::SimpleIoMap, op::ReplaceSelectionOperation)
    path = skip_type_checkpoints(op.path)
    path isa ConcreteReferencePath || return nothing
    h = path.head
    h isa FieldReference && h.name == "value" || return nothing
    return op
end

# ── PrimitiveStringToSyntaxLeaf ──────────────────────────────────────────────

@projection struct PrimitiveStringToSyntaxLeaf <: Projection
    quote_style::StyleText = StyleText(font_ubuntu_monospace_regular_24, color_solarized_yellow)
    value::StyleText       = StyleText(font_ubuntu_monospace_regular_24, color_solarized_green)
end

function map_reference_forward(::PrimitiveStringToSyntaxLeaf, iomap::SimpleIoMap, reference)
    @reference_case reference begin
        ::PrimitiveString.value{k} => @reference ::SyntaxLeaf.value::TextString{k}
    end
end

function map_reference_backward(::PrimitiveStringToSyntaxLeaf, iomap::SimpleIoMap, reference)
    @reference_case reference begin
        ::SyntaxLeaf.value{k} => @reference ::PrimitiveString.value::String{k}
    end
end

function projection_print(p::PrimitiveStringToSyntaxLeaf, recursion, s::PrimitiveString, ctx)
    SimpleIoMap(p, s, SyntaxLeaf(
        TextString(() -> something(s.value, ""), p.value);
        open=TextString("\"", p.quote_style),
        close=TextString("\"", p.quote_style),
        selection=getfield(s, :selection)))
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
    sel = skip_type_checkpoints(sel)
    sel isa ConcreteReferencePath || return nothing
    head = sel.head
    (head isa FieldReference && head.name == "value") || return nothing
    inner = skip_type_checkpoints(sel.tail)
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
