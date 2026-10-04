# Fragment of `TextModule`.
#
# PrimitiveDocument → TextBlock projection. Converts `PrimitiveBool`,
# `PrimitiveNumber`, `PrimitiveString` and the type-in `PrimitiveInsertion`
# directly into a single-span `TextBlock` without an intervening `SyntaxLeaf`, so
# a string shows no quotes. The natural renderer draws every primitive that is no
# part of a syntax tree through it: a cell of a table, an element of a
# collection, a value in a tab.
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
                    style = get_text_style(theme, :bool_text)) =
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

# A key that would edit the text of a Bool does nothing: a Bool switches by the
# keys of `@gestures PrimitiveBool`, and a range edit of a Bool has no result.
read_intent(::PrimitiveBoolToText, iomap::SimpleIoMap, ::ReplaceRangeOperation) = nothing

# ── PrimitiveNumberToText ────────────────────────────────────────────────────

# With `allows_type_in`, a key whose text the number can not show, such as `-` or
# `12.`, replaces the number with a type-in of that text
# (`make_number_edit_operation`). Only a table that also prints a
# `PrimitiveInsertion` turns it on, as `PrimitiveToText` does.
@projection UntrackedCell struct PrimitiveNumberToText
    style::StyleText
    allows_type_in::Bool
end

PrimitiveNumberToText(; theme = nothing,
                      style = get_text_style(theme, :number_text),
                      allows_type_in::Bool = false) =
    PrimitiveNumberToText(style, allows_type_in)

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

# A key in the number is a range replace that the default reader maps back to
# `value{s:e}`; with `allows_type_in`, a text that the number can not show makes
# a type-in instead.
function read_intent(p::PrimitiveNumberToText, iomap::SimpleIoMap, op::ReplaceRangeOperation)
    mapped = invoke(read_intent, Tuple{Projection,Any,Any}, p, iomap, op)
    p.allows_type_in && mapped isa ReplaceRangeOperation ? make_number_edit_operation(iomap.input, mapped) : mapped
end

# ── PrimitiveInsertionToText ─────────────────────────────────────────────────
#
# The type-in: the typed text in the style of the first allowed type that it
# parses as, red while it parses as none, and the placeholder of the type-in
# while it is empty. Its keys are the gestures of `PrimitiveInsertion` below; a
# text edit that comes from a later stage takes the same rule.

@projection UntrackedCell struct PrimitiveInsertionToText
    bool_style::StyleText
    number_style::StyleText
    string_style::StyleText
    wrong_color::StyleColor
    placeholder_style::StyleText
end

function PrimitiveInsertionToText(; theme = nothing)
    PrimitiveInsertionToText(get_text_style(theme, :bool_text),
                             get_text_style(theme, :number_text),
                             get_text_style(theme, :string_text),
                             get_text_style(theme, :wrong_color),
                             get_text_style(theme, :placeholder_text))
end

# The style of the text of `ins`: the placeholder while it is empty, the style of
# the first allowed type that the text parses as, and red while it parses as none.
function _get_type_in_style(p::PrimitiveInsertionToText, ins::PrimitiveInsertion)
    text = something(ins.value, "")
    isempty(text) && return unwrap_cell(p.placeholder_style)
    document = find_primitive_document(ins.allowed_types, text)
    document isa PrimitiveNumber && return unwrap_cell(p.number_style)
    document isa PrimitiveBool && return unwrap_cell(p.bool_style)
    document isa PrimitiveString && return unwrap_cell(p.string_style)
    StyleText(unwrap_cell(p.number_style).font, unwrap_cell(p.wrong_color))
end

# Backward: as for a string, with every place of an empty type-in at its start,
# because the text that it shows then is its placeholder.
function _backward_insertion(reference, ins::PrimitiveInsertion)
    count = length(something(ins.value, ""))
    pair = _flat_range_pair(reference)
    pair === nothing || return _value_range_ref(min(pair[1], count), min(pair[2], count))
    flat = _flat_caret_offset(reference)
    if flat !== nothing
        k = min(flat, count)
        return @reference ::PrimitiveInsertion.value::String{k}::Position
    end
    @reference_case reference begin
        ::TextBlock.elements[1].content{s:e} =>
            (s == e ? (k = min(s, count); @reference ::PrimitiveInsertion.value::String{k}::Position) :
                      _value_range_ref(min(s, count), min(e, count)))
    end
end

map_reference_forward(::PrimitiveInsertionToText, iomap::SimpleIoMap, reference) =
    _forward_value(reference)
map_reference_backward(::PrimitiveInsertionToText, iomap::SimpleIoMap, reference) =
    _backward_insertion(reference, iomap.input)

function print_document(p::PrimitiveInsertionToText, recursion, ins::PrimitiveInsertion, ctx)
    style = Cell(@computation _get_type_in_style(p, ins))
    shown() = (text = something(ins.value, ""); isempty(text) ? get_type_in_placeholder(ins) : text)
    span = TextString(Cell(@computation shown()), Cell(@computation style[].font),
                      Cell(@computation style[].color), Cell(nothing), Cell(nothing), Cell(nothing),
                      Cell(nothing))
    paths = make_output_path_cells(ins, _forward_value)
    out = TextBlock(CellVector(@computation TextDocument[span]), paths.selection, paths.mouse_target)
    SimpleIoMap(p, ins, out)
end

function read_intent(p::PrimitiveInsertionToText, iomap::SimpleIoMap, op::ReplacePathOperation)
    input_path = _backward_insertion(op.path, iomap.input)
    input_path === nothing && return nothing
    make_path_operation(op, input_path)
end

function read_intent(p::PrimitiveInsertionToText, iomap::SimpleIoMap, op::ReplaceRangeOperation)
    mapped = invoke(read_intent, Tuple{Projection,Any,Any}, p, iomap, op)
    mapped isa ReplaceRangeOperation || return mapped
    range = find_value_range(mapped.reference)
    range === nothing ? mapped : make_type_in_edit_operation(iomap.input, range, mapped.replacement)
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
                            style = get_text_style(theme, :string_text),
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
    new_range = find_deletion_range(range, length(something(s.value, "")), dir)
    new_range === nothing && return nothing
    ReplaceStringRangeOperation(_string_value_path(new_range), "")
end

# The keys of a type-in, as `@gestures PrimitiveString` gives a string its keys:
# a key edits the text, or makes the value that the new text shows exactly;
# Enter makes the value that the text parses as, and Escape drops the text. The
# syntax leaf of a type-in reads the same keys in its own table first.
@gestures PrimitiveInsertion begin
    when(find_value_range(doc) !== nothing)
    KeyPress(_, t)        => "Insert character" => make_type_in_edit_operation(doc, find_value_range(doc), t)
    KeyDown(:backspace;)  => "Delete backward"  => _make_type_in_deletion(doc, :backspace)
    KeyDown(:delete;)     => "Delete forward"   => _make_type_in_deletion(doc, :delete)
    KeyDown(:return;)     => "Make the value"   => make_type_in_commit_operation(doc)
    KeyDown(:escape;)     => "Drop the text"    => make_type_in_cancel_operation(doc)
end

function _make_type_in_deletion(ins::PrimitiveInsertion, direction::Symbol)
    range = find_deletion_range(find_value_range(ins), length(something(ins.value, "")), direction)
    range === nothing ? nothing : make_type_in_edit_operation(ins, range, "")
end

# A Bool switches with one key: `t` makes it true and `f` false, as a JSON
# document takes them, and Space switches it.
@gestures PrimitiveBool begin
    KeyPress('t') => "Make it true"  => _make_bool_operation(doc, true)
    KeyPress('f') => "Make it false" => _make_bool_operation(doc, false)
    KeyPress(' ') => "Switch it"     => _make_bool_operation(doc, !doc.value)
end

# The write of `value` to a Bool, rooted at the Bool, or `nothing` when it holds
# that value already.
_make_bool_operation(b::PrimitiveBool, value::Bool) = b.value === value ? nothing :
    ReplaceReferencedValueOperation(nothing, ConcreteReference(FieldReferenceStep("value"), EmptyReference()), value)

# ── PrimitiveToText (composite) ──────────────────────────────────────────────

"""
    PrimitiveToText(; theme = nothing, bool_kw=(), number_kw=(), string_kw=())

Composite projection that converts all `PrimitiveDocument` types directly
to single-span `TextBlock` documents. `theme`, a `TextTheme` or a scaled one,
gives the text of each kind; with none, the texts of the default theme.
"""
function PrimitiveToText(; theme = nothing, bool_kw=(), number_kw=(), string_kw=())
    TypeDispatchingProjection(
        PrimitiveBool      => PrimitiveBoolToText(; theme, bool_kw...),
        PrimitiveNumber    => PrimitiveNumberToText(; theme, allows_type_in = true, number_kw...),
        PrimitiveString    => PrimitiveStringToTextBlock(; theme, string_kw...),
        PrimitiveInsertion => PrimitiveInsertionToText(; theme),
    )
end
