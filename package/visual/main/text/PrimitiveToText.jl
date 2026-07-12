"""
    PrimitiveToTextModule

PrimitiveDocument → TextText projection. Converts `PrimitiveBool`,
`PrimitiveNumber`, and `PrimitiveString` directly into a single-span
`TextText` without an intervening `SyntaxLeaf`. Used by widget labels,
conversation cells, and other contexts that aggregate styled spans and
want a primitive value to land in the text domain directly.
"""
module PrimitiveToTextModule

import ..CellModule: Cell
import ..CollectionModule: CellVector
import ..ProjectionApiModule: print_document, read_intent, map_reference_forward, map_reference_backward, Projection
import ..ProjectionModule: var"@projection"
import ..PrimitiveModule: PrimitiveDocument, PrimitiveBool, PrimitiveNumber, PrimitiveString,
                          ReplaceStringRangeOperation
import ..TextModule: TextDocument, TextText, TextString
import ..FontModule: StyleFont, font_ubuntu_monospace_regular_20
import ..ColorModule: StyleColor, color_solarized_cyan, color_solarized_magenta, color_solarized_green
import ..StyleTextModule: StyleText
import ..IoMapModule: SimpleIoMap
import ..ReferenceModule: ConcreteReferencePath, EmptyReferencePath, FieldReference, RangeReference,
                          ElementReference, PositionReference, ReferencePath, Position
import ..ReferenceCaseModule: var"@reference_case"
import ..ReferenceBuilderModule: var"@reference"
import ..OperationModule: ReplaceSelectionOperation
import ..GestureBindingModule: var"@gestures"
import ..TypeDispatchingProjectionModule: TypeDispatchingProjection
import ..PrinterContextModule: make_child_context
export PrimitiveBoolToText, PrimitiveNumberToText, PrimitiveStringToTextText, PrimitiveToText

# Forward: .value[k] on the primitive → .elements[1].content[k] on the TextText.
# Range selections collapse to a cursor at the range start.
function _forward_value(reference)
    @reference_case reference begin
        value{s:e} => @reference ::TextText.elements::CellVector[1]::TextString.content::String{s}::Position
    end
end

# Backward: .elements[1].content[k] on the TextText → .value[k] on the primitive.
# Type-specific variants so the returned reference carries the leading document type.
function _backward_bool(reference)
    @reference_case reference begin
        ::TextText.elements[1].content{s:e} => @reference ::PrimitiveBool.value::Bool{s}::Position
    end
end

function _backward_number(reference)
    @reference_case reference begin
        ::TextText.elements[1].content{s:e} => @reference ::PrimitiveNumber.value::Number{s}::Position
    end
end

function _backward_string(reference)
    @reference_case reference begin
        ::TextText.elements[1].content{s:e} => @reference ::PrimitiveString.value::String{s}::Position
    end
end

# Translates a PrimitiveDocument's `.value[k]` / `.value[range]` selection
# into the single-span TextText shape `.elements[1].content[k]`. Range
# selections collapse to a cursor at `range.start` (matching SyntaxLeafToText).
_value_selection_to_text(prim) = _forward_value(getfield(prim, :selection)[])

# ── PrimitiveBoolToText ──────────────────────────────────────────────────────

@projection struct PrimitiveBoolToText
    style::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_cyan)
end

map_reference_forward(::PrimitiveBoolToText, iomap::SimpleIoMap, reference) =
    _forward_value(reference)
map_reference_backward(::PrimitiveBoolToText, iomap::SimpleIoMap, reference) =
    _backward_bool(reference)

function print_document(p::PrimitiveBoolToText, recursion, b::PrimitiveBool, ctx)
    span = TextString(() -> string(b.value), p.style)
    out = TextText(CellVector(() -> TextDocument[span]),
                   Cell(() -> _value_selection_to_text(b)))
    SimpleIoMap(p, b, out)
end

function read_intent(p::PrimitiveBoolToText, iomap::SimpleIoMap, op::ReplaceSelectionOperation)
    input_path = _backward_bool(op.path)
    input_path === nothing && return nothing
    ReplaceSelectionOperation(input_path)
end

# ── PrimitiveNumberToText ────────────────────────────────────────────────────

@projection struct PrimitiveNumberToText
    style::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_magenta)
end

map_reference_forward(::PrimitiveNumberToText, iomap::SimpleIoMap, reference) =
    _forward_value(reference)
map_reference_backward(::PrimitiveNumberToText, iomap::SimpleIoMap, reference) =
    _backward_number(reference)

function print_document(p::PrimitiveNumberToText, recursion, n::PrimitiveNumber, ctx)
    span = TextString(() -> string(something(n.value, "")), p.style)
    out = TextText(CellVector(() -> TextDocument[span]),
                   Cell(() -> _value_selection_to_text(n)))
    SimpleIoMap(p, n, out)
end

function read_intent(p::PrimitiveNumberToText, iomap::SimpleIoMap, op::ReplaceSelectionOperation)
    input_path = _backward_number(op.path)
    input_path === nothing && return nothing
    ReplaceSelectionOperation(input_path)
end

# ── PrimitiveStringToTextText ────────────────────────────────────────────────────

struct PrimitiveStringToTextText <: Projection
    style::StyleText
    # Hint shown when the value is empty. `placeholder == ""` disables it, so
    # the projection keeps its plain (placeholder-free) behavior by default.
    placeholder::String
    placeholder_style::StyleText
end
PrimitiveStringToTextText(; style=StyleText(font_ubuntu_monospace_regular_20, color_solarized_green),
                            placeholder="", placeholder_style=style) =
    PrimitiveStringToTextText(style, placeholder, placeholder_style)

map_reference_forward(::PrimitiveStringToTextText, iomap::SimpleIoMap, reference) =
    _forward_value(reference)
map_reference_backward(::PrimitiveStringToTextText, iomap::SimpleIoMap, reference) =
    _backward_string(reference)

function print_document(p::PrimitiveStringToTextText, recursion, s::PrimitiveString, ctx)
    value_span = TextString(() -> something(s.value, ""), p.style)
    # When the value is empty and a placeholder is configured, show a muted hint
    # span instead. Both spans keep a stable identity; the CellVector thunk only
    # swaps which one is element 1 at the empty↔non-empty boundary, and the
    # selection (mapped to `elements[1].content`) tracks `s.value` either way.
    placeholder_span = TextString(p.placeholder, p.placeholder_style)
    show_placeholder() = !isempty(p.placeholder) && isempty(something(s.value, ""))
    out = TextText(CellVector(() -> TextDocument[show_placeholder() ? placeholder_span : value_span]),
                   Cell(() -> _value_selection_to_text(s)))
    SimpleIoMap(p, s, out)
end

function read_intent(p::PrimitiveStringToTextText, iomap::SimpleIoMap, op::ReplaceSelectionOperation)
    input_path = _backward_string(op.path)
    input_path === nothing && return nothing
    ReplaceSelectionOperation(input_path)
end

# Extract a `.value[range]` selection on a PrimitiveString as a RangeReference.
function _string_value_range(s::PrimitiveString)
    sel = getfield(s, :selection)[]
    sel = sel
    sel isa ConcreteReferencePath || return nothing
    head = sel.head
    (head isa FieldReference && head.name == "value") || return nothing
    inner = sel.tail
    inner isa ConcreteReferencePath || return nothing
    inner.head isa RangeReference || return nothing
    inner.head
end

_string_value_path(range::RangeReference) =
    ConcreteReferencePath(PrimitiveString, FieldReference("value"),
        ConcreteReferencePath(String, range, EmptyReferencePath(String)))

# String editing is a *document-level* concern (it produces a
# `ReplaceStringRangeOperation` in the `PrimitiveString`'s own `value[range]`
# vocabulary), so it is reified once as `@gestures PrimitiveString` rather than
# duplicated in every primitive projection's reader. Both `PrimitiveStringToTextText`
# and `PrimitiveStringToSyntaxLeaf` reach it through the generic `read_gesture`
# fallback (a leaf projection with no bespoke event reader delegates raw input
# gestures to `read_gesture(iomap.input, …)`). The `when` precondition gates the
# whole table on there being a `value[range]` cursor — a non-editing selection
# (or none) declines, exactly as the old `range === nothing && return nothing`.
@gestures PrimitiveString begin
    when(_string_value_range(doc) !== nothing)
    KeyPress(_, t)       => "Insert character" =>
        ReplaceStringRangeOperation(_string_value_path(_string_value_range(doc)), t)
    KeyDown(:backspace;) => "Delete backward"  => _string_delete(doc, :backspace)
    KeyDown(:delete;)    => "Delete forward"   => _string_delete(doc, :delete)
end

# Compute the deletion range for Backspace/Delete and return the replace op, or
# nothing at the string boundary. A non-empty selection deletes the selected span;
# a collapsed cursor deletes the adjacent character.
function _string_delete(s::PrimitiveString, dir::Symbol)
    range = _string_value_range(s)
    range === nothing && return nothing
    n = length(something(s.value, ""))
    new_range = if range.start != range.stop
        range
    elseif dir === :backspace
        range.start > 0 ? RangeReference(range.start - 1, range.start) : nothing
    else  # :delete
        range.stop < n ? RangeReference(range.stop, range.stop + 1) : nothing
    end
    new_range === nothing && return nothing
    ReplaceStringRangeOperation(_string_value_path(new_range), "")
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
