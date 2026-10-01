# Fragment of `TextModule`.
#
# PrimitiveDocument → TextBlock projection. Converts `PrimitiveBool`,
# `PrimitiveNumber`, and `PrimitiveString` directly into a single-span
# `TextBlock` without an intervening `SyntaxLeaf`. Used by widget labels,
# conversation cells, and other contexts that aggregate styled spans and
# want a primitive value to land in the text domain directly.
# Forward: .value[k] on the primitive → .elements[1].content[k] on the TextBlock.
# A range `.value{s:e}` is the flat range `{s:e}`: the block has one span, so a
# flat offset is a character offset of the value.
function _forward_value(reference)
    @reference_case reference begin
        value{s:e} => (s == e ?
            (@reference ::TextBlock.elements::CellVector[1]::TextString.content::String{s}::Position) :
            make_flat_range_reference(s, e))
    end
end

# The Text domain has two legal caret forms and `TextToGraphics` emits the
# CANONICAL one — a flat character offset on the block (`TextRangeReferenceStep`)
# — while the structural `.elements[1].content{k}` path is what the forward
# direction produces. Both have to map back, or a primitive nested in a widget
# renders and never accepts a caret: the printers compose, so the readers must
# too. On a single-span block the two forms denote the same position.
_flat_caret_offset(reference) =
    reference isa ConcreteReference && reference.head isa TextRangeReferenceStep &&
    reference.head.start == reference.head.stop ? reference.head.start : nothing

# The flat `(start, stop)` of a non-empty flat range, or `nothing`. On the
# single-span block it is the range `.value{start:stop}` of the primitive.
_flat_range_pair(reference) =
    reference isa ConcreteReference && reference.head isa TextRangeReferenceStep &&
    reference.head.start < reference.head.stop ?
        (reference.head.start, reference.head.stop) : nothing

# Backward: .elements[1].content[k] on the TextBlock → .value[k] on the primitive.
# Type-specific variants so the returned reference carries the leading document type.
# A caret is the s == e case; a Backspace/Delete arrives as a genuine RANGE edit
# (`ReplaceStringRangeOperation` over `content{s:e}`), and `evaluate_operation`
# splices `range_step.start..range_step.stop`. Collapsing the range to `{s}` made
# the deletion empty, so Backspace/Delete were silent no-ops. Keep the caret's
# typed form (the DSL needs a terminal `::Position`); build the deletion range
# directly — `.value{s:e}` — since a range over a scalar value has no evaluatable
# terminal type and the operation reader strips reference types anyway.
_value_range_ref(s::Int, e::Int) =
    ConcreteReference(FieldReferenceStep("value"),
                      ConcreteReference(RangeReferenceStep(s, e), EmptyReference()))

function _backward_bool(reference)
    pair = _flat_range_pair(reference)
    pair === nothing || return _value_range_ref(pair...)
    flat = _flat_caret_offset(reference)
    flat === nothing || return @reference ::PrimitiveBool.value::Bool{flat}::Position
    @reference_case reference begin
        ::TextBlock.elements[1].content{s:e} =>
            (s == e ? (@reference ::PrimitiveBool.value::Bool{s}::Position) : _value_range_ref(s, e))
    end
end

function _backward_number(reference)
    pair = _flat_range_pair(reference)
    pair === nothing || return _value_range_ref(pair...)
    flat = _flat_caret_offset(reference)
    flat === nothing || return @reference ::PrimitiveNumber.value::Number{flat}::Position
    @reference_case reference begin
        ::TextBlock.elements[1].content{s:e} =>
            (s == e ? (@reference ::PrimitiveNumber.value::Number{s}::Position) : _value_range_ref(s, e))
    end
end

function _backward_string(reference)
    pair = _flat_range_pair(reference)
    pair === nothing || return _value_range_ref(pair...)
    flat = _flat_caret_offset(reference)
    flat === nothing || return @reference ::PrimitiveString.value::String{flat}::Position
    @reference_case reference begin
        ::TextBlock.elements[1].content{s:e} =>
            (s == e ? (@reference ::PrimitiveString.value::String{s}::Position) : _value_range_ref(s, e))
    end
end

# ── PrimitiveBoolToText ──────────────────────────────────────────────────────

@projection UntrackedCell struct PrimitiveBoolToText
    style::StyleText
end

PrimitiveBoolToText(; theme = nothing,
                    style = _get_text_style(scale_theme(theme), StyleText, :bool_text)) =
    PrimitiveBoolToText(style)

map_reference_forward(::PrimitiveBoolToText, iomap::SimpleIoMap, reference) =
    _forward_value(reference)
map_reference_backward(::PrimitiveBoolToText, iomap::SimpleIoMap, reference) =
    _backward_bool(reference)

function print_document(p::PrimitiveBoolToText, recursion, b::PrimitiveBool, ctx)
    span = TextString(() -> string(b.value), p.style)
    paths = make_output_path_cells(b, _forward_value)
    out = TextBlock(CellVector(@computation TextDocument[span]),
                   paths.selection, paths.mouse_target)
    SimpleIoMap(p, b, out)
end

function read_intent(p::PrimitiveBoolToText, iomap::SimpleIoMap, op::ReplacePathOperation)
    input_path = _backward_bool(op.path)
    input_path === nothing && return nothing
    make_path_operation(op, input_path)
end

# ── PrimitiveNumberToText ────────────────────────────────────────────────────

@projection UntrackedCell struct PrimitiveNumberToText
    style::StyleText
end

PrimitiveNumberToText(; theme = nothing,
                      style = _get_text_style(scale_theme(theme), StyleText, :number_text)) =
    PrimitiveNumberToText(style)

map_reference_forward(::PrimitiveNumberToText, iomap::SimpleIoMap, reference) =
    _forward_value(reference)
map_reference_backward(::PrimitiveNumberToText, iomap::SimpleIoMap, reference) =
    _backward_number(reference)

function print_document(p::PrimitiveNumberToText, recursion, n::PrimitiveNumber, ctx)
    span = TextString(() -> string(something(n.value, "")), p.style)
    paths = make_output_path_cells(n, _forward_value)
    out = TextBlock(CellVector(@computation TextDocument[span]),
                   paths.selection, paths.mouse_target)
    SimpleIoMap(p, n, out)
end

function read_intent(p::PrimitiveNumberToText, iomap::SimpleIoMap, op::ReplacePathOperation)
    input_path = _backward_number(op.path)
    input_path === nothing && return nothing
    make_path_operation(op, input_path)
end

# ── PrimitiveStringToTextBlock ────────────────────────────────────────────────────

@projection UntrackedCell struct PrimitiveStringToTextBlock <: Projection
    style::StyleText
    # Hint shown when the value is empty. `placeholder == ""` disables it, so
    # the projection keeps its plain (placeholder-free) behavior by default.
    placeholder::String
    placeholder_style::StyleText
end
PrimitiveStringToTextBlock(; theme = nothing,
                            style = _get_text_style(scale_theme(theme), StyleText, :string_text),
                            placeholder = "", placeholder_style = style) =
    PrimitiveStringToTextBlock(style, placeholder, placeholder_style)

map_reference_forward(::PrimitiveStringToTextBlock, iomap::SimpleIoMap, reference) =
    _forward_value(reference)
map_reference_backward(::PrimitiveStringToTextBlock, iomap::SimpleIoMap, reference) =
    _backward_string(reference)

function print_document(p::PrimitiveStringToTextBlock, recursion, s::PrimitiveString, ctx)
    value_span = TextString(() -> something(s.value, ""), p.style)
    # When the value is empty and a placeholder is configured, show a muted hint
    # span instead. Both spans keep a stable identity; the CellVector thunk only
    # swaps which one is element 1 at the empty↔non-empty boundary, and the
    # selection (mapped to `elements[1].content`) tracks `s.value` either way.
    placeholder_span = TextString(p.placeholder, p.placeholder_style)
    show_placeholder() = !isempty(p.placeholder) && isempty(something(s.value, ""))
    paths = make_output_path_cells(s, _forward_value)
    out = TextBlock(CellVector(@computation TextDocument[show_placeholder() ? placeholder_span : value_span]),
                   paths.selection, paths.mouse_target)
    SimpleIoMap(p, s, out)
end

function read_intent(p::PrimitiveStringToTextBlock, iomap::SimpleIoMap, op::ReplacePathOperation)
    input_path = _backward_string(op.path)
    input_path === nothing && return nothing
    make_path_operation(op, input_path)
end

# Extract a `.value[range]` selection on a PrimitiveString as a RangeReferenceStep.
function _string_value_range(s::PrimitiveString)
    sel = getfield(s, :selection)[]
    sel = sel
    sel isa ConcreteReference || return nothing
    head = sel.head
    (head isa FieldReferenceStep && head.name == "value") || return nothing
    inner = sel.tail
    inner isa ConcreteReference || return nothing
    inner.head isa RangeReferenceStep || return nothing
    inner.head
end

_string_value_path(range::RangeReferenceStep) =
    ConcreteReference(PrimitiveString, FieldReferenceStep("value"),
        ConcreteReference(String, range, EmptyReference(String)))

# String editing is a *document-level* concern (it produces a
# `ReplaceStringRangeOperation` in the `PrimitiveString`'s own `value[range]`
# vocabulary), so it is reified once as `@gestures PrimitiveString` rather than
# duplicated in every primitive projection's reader. Both `PrimitiveStringToTextBlock`
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
        range.start > 0 ? RangeReferenceStep(range.start - 1, range.start) : nothing
    else  # :delete
        range.stop < n ? RangeReferenceStep(range.stop, range.stop + 1) : nothing
    end
    new_range === nothing && return nothing
    ReplaceStringRangeOperation(_string_value_path(new_range), "")
end

# ── PrimitiveToText (composite) ──────────────────────────────────────────────

"""
    PrimitiveToText(; theme = nothing, bool_kw=(), number_kw=(), string_kw=())

Composite projection that converts all `PrimitiveDocument` types directly
to single-span `TextBlock` documents. `theme`, a `TextTheme` or a scaled one,
gives the text of each kind; with none, the texts of the default theme.
"""
function PrimitiveToText(; theme = nothing, bool_kw=(), number_kw=(), string_kw=())
    theme = scale_theme(theme)
    TypeDispatchingProjection(
        PrimitiveBool   => PrimitiveBoolToText(; theme, bool_kw...),
        PrimitiveNumber => PrimitiveNumberToText(; theme, number_kw...),
        PrimitiveString => PrimitiveStringToTextBlock(; theme, string_kw...),
    )
end
