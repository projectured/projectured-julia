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
import ..ReferenceModule: ConcreteReferencePath, EmptyReferencePath, FieldReference, RangeReference
import ..ReferenceBuilderModule: var"@reference"
import ..ReferenceCaseModule: var"@reference_case"
import ..OperationModule: ReplaceSelectionOperation
export PrimitiveBoolToSyntaxLeaf, PrimitiveNumberToSyntaxLeaf, PrimitiveStringToSyntaxLeaf,
       PrimitiveToSyntax

# ── PrimitiveBoolToSyntaxLeaf ────────────────────────────────────────────────

@projection struct PrimitiveBoolToSyntaxLeaf
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
    path = op.path
    path isa ConcreteReferencePath || return nothing
    h = path.head
    h isa FieldReference && h.name == "value" || return nothing
    return op
end

# ── PrimitiveNumberToSyntaxLeaf ──────────────────────────────────────────────

@projection struct PrimitiveNumberToSyntaxLeaf
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
    path = op.path
    path isa ConcreteReferencePath || return nothing
    h = path.head
    h isa FieldReference && h.name == "value" || return nothing
    return op
end

# ── PrimitiveStringToSyntaxLeaf ──────────────────────────────────────────────

@projection struct PrimitiveStringToSyntaxLeaf
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

# String character-editing (insert / Backspace / Delete) is reified once as
# `@gestures PrimitiveString` in `PrimitiveToText.jl` (a document-level concern in
# the PrimitiveString's own `value[range]` vocabulary); this leaf reaches it
# through the generic `document_read` fallback, so no bespoke event reader lives
# here — only the structural `ReplaceSelectionOperation` mapping above.

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
