# Fragment of `PrimitiveModule` — the primitive document types: the abstract
# `PrimitiveDocument`, the leaf documents that carry a single value, and the
# type-in that a person types a value into.

abstract type PrimitiveDocument <: Document end

# A primitive holds one value a person types, so its duplicate is a copy of it.
has_document_duplicate(::PrimitiveDocument) = true

# ── PrimitiveBool ─────────────────────────────────────────────────────────────

"""
    PrimitiveBool(value)

A primitive domain-independent boolean document with selection and identity.
`value` is a `Cell` holding a `Bool`.
"""
@document struct PrimitiveBool <: PrimitiveDocument
    value::Bool
end

# ── PrimitiveNumber ───────────────────────────────────────────────────────────

"""
    PrimitiveNumber(value)

A primitive domain-independent number document with selection and identity.
`value` is a `Cell` holding a `Number` or `nothing`.
"""
@document struct PrimitiveNumber <: PrimitiveDocument
    value::Union{Number, Nothing}
end

# ── PrimitiveString ───────────────────────────────────────────────────────────

"""
    PrimitiveString(value)

A primitive domain-independent string document with selection and identity.
`value` is a `Cell` holding a `String` or `nothing`.
"""
@document struct PrimitiveString <: PrimitiveDocument
    value::Union{String, Nothing}
end

# ── PrimitiveInsertion ──────────────────────────────────────────────────────

"""
    PrimitiveInsertion(; value = nothing,
                       allowed_types = (PrimitiveNumber, PrimitiveBool, PrimitiveString),
                       placeholder = nothing, selection = nothing)

The type-in of the primitive domain: the text that a person types before it is
a value, in `value`, which is `nothing` while nothing is typed. `allowed_types`
limits what the text can become, in the order of a try: a number that can not
show a key becomes a type-in limited to `PrimitiveNumber`, so its text can not
become a string where a number belongs. `placeholder` is what an empty type-in
shows, such as `missing` in a cell of a data frame, or `nothing` for the text of
[`get_type_in_placeholder`](@ref).
"""
@document struct PrimitiveInsertion <: PrimitiveDocument
    value::Any = nothing
    allowed_types::Tuple = (PrimitiveNumber, PrimitiveBool, PrimitiveString)
    placeholder::Union{Nothing, String} = nothing
end


# ── Operations ────────────────────────────────────────────────────────────────

"""
    ReplaceRangeOperation <: Operation

Category supertype for the "replace a referenced character range with a string"
operations. Every subtype carries exactly two fields — `reference::Reference`
(rooted at the editor's document, terminating in the step that names the range)
and `replacement::String`. This shared shape lets the generic transport methods
(`reroot_operation`, the projection-stage backward-map / passthrough readers) be
written once against `ReplaceRangeOperation`; the concrete subtypes differ only in
what their terminal step means and how the range is resolved and applied:

- `ReplaceStringRangeOperation` — a `RangeReferenceStep` over one string field's chars.
- `ReplaceTextRangeOperation` (text slice) — a `TextRangeReferenceStep` flat range over
  a whole `TextBlock`, possibly crossing spans/lines.

`ReplaceNumberRangeOperation` deliberately stays outside this hierarchy for now (it
forces number semantics regardless of the field value); it may join later.
"""
abstract type ReplaceRangeOperation <: Operation end

"""
    ReplaceNumberRangeOperation(reference, replacement)

Replace characters in the string representation of a `PrimitiveNumber`'s value.
`reference` is a `Reference` rooted at the editor's document whose terminal
step is a `RangeReferenceStep(s, e)` (0-based boundaries) and whose penultimate
step is `FieldReferenceStep("value")`. The path up to those two steps locates the
target `PrimitiveNumber`. After evaluation the target's `selection` is updated
to a zero-width cursor at `s + length(replacement)`.

An empty result sets the value to `nothing`, and so does a text that does not
parse, such as `1e` or `-` on the way to a number. A `replacement` with a
character that can not be part of a number changes nothing: the value, its text
and the selection stay as they are. See [`has_only_number_characters`](@ref).
"""
struct ReplaceNumberRangeOperation <: Operation
    reference::Reference
    replacement::String
end

"""
    has_only_number_characters(text) -> Bool

Whether every character of `text` can be part of the text of a number: a digit,
a sign, a decimal point or an exponent mark. The empty text, which a deletion
puts in, is one.

A number edit whose replacement fails this test is ignored, so a letter typed
into `42` leaves `42`. A text that passes it can still fail to parse, such as
`1e`, and that edit is kept, because the next key can make it a number.
"""
has_only_number_characters(text::AbstractString) =
    all(character -> isdigit(character) || character in ('+', '-', '.', 'e', 'E'), text)

"""
    ReplaceStringRangeOperation(reference, replacement)

Replace characters in a `PrimitiveString`'s value. `reference` is a
`Reference` rooted at the editor's document whose terminal step is a
`RangeReferenceStep(s, e)` (0-based boundaries) and whose penultimate step is
`FieldReferenceStep("value")`. The path up to those two steps locates the target
`PrimitiveString`. After evaluation the target's `selection` is updated to a
zero-width cursor at `s + length(replacement)`.

Inter-string boundary behaviour: when the cursor sits exactly on the boundary
between two adjacent `PrimitiveString` spans, the behaviour is undefined.
"""
struct ReplaceStringRangeOperation <: ReplaceRangeOperation
    reference::Reference
    replacement::String
end

# ── Operation evaluation ──────────────────────────────────────────────────────

# Split `op.reference` into (target_path, field_name, range_step). The
# penultimate step is the field-name carrying the text/number value; the
# terminal step is the RangeReferenceStep. The field name is data, not a
# precondition — `splice_value!` interprets the field's current value by its
# representation (string / number / span / span-sequence).
function _split_replace_reference(path::Reference)
    # Operate on the plain navigation path: drop selection-style type checkpoints
    # so the `.<field>[range]` suffix split sees only real steps.
    steps = get_reference_steps(strip_reference_types(path))
    # An un-splittable reference has no editable `.<field>[range]` slot — e.g. an
    # edit aimed at a projection-introduced span (a placeholder/insertion rendered
    # as `…[i].proj(p, .value[k])`, whose terminal is a `ProjectionReferenceStep` with
    # no input pre-image). Return `nothing` so the caller no-ops instead of
    # crashing the editor.
    length(steps) >= 2 || return nothing
    field_step = steps[end - 1]
    range_step = steps[end]
    field_step isa FieldReferenceStep || return nothing
    range_step isa RangeReferenceStep || return nothing
    (Reference(steps[1:end-2]...), field_step.name::AbstractString, range_step)
end

# Replace the terminal RangeReferenceStep of `path` with a zero-width
# RangeReferenceStep at `start + length(replacement)`, leaving the rest intact.
function _replace_terminal_with_cursor(path::Reference, replacement::AbstractString)
    # Plain navigation path only; the rebuilt path is re-canonicalized when it is
    # handed to `set_selection!`.
    steps = get_reference_steps(strip_reference_types(path))
    range_step = steps[end]::RangeReferenceStep
    new_pos = range_step.start + length(replacement)
    steps[end] = RangeReferenceStep(new_pos, new_pos)
    Reference(steps...)
end

# A number edit always has number semantics regardless of the field's current
# value (an empty/cleared field reparses from ""), so it does not go through the
# representation-dispatched `splice_value!` — it forces the number path here.
function evaluate_operation(editor, op::ReplaceNumberRangeOperation)
    has_only_number_characters(op.replacement) || return
    document = editor.document
    split = _split_replace_reference(op.reference)
    split === nothing && return            # no editable slot (e.g. projection-introduced span)
    target_path, field_name, range_step = split
    target = evaluate_reference(document, target_path)
    field = Symbol(field_name)
    old = getproperty(target, field)
    setproperty!(target, field,
                 splice_number(old === nothing ? "" : string(old),
                               range_step.start, range_step.stop, op.replacement))
    _replace_selection_with_cursor!(document, op)
end

function evaluate_operation(editor, op::ReplaceStringRangeOperation)
    document = editor.document
    split = _split_replace_reference(op.reference)
    split === nothing && return            # no editable slot (e.g. projection-introduced span)
    target_path, field_name, range_step = split
    target = evaluate_reference(document, target_path)
    field = Symbol(field_name)
    value = getproperty(target, field)
    # A text layer edits a number with a string edit, and the number ignores it
    # the way it ignores a number edit. A `Bool` is a `Number` to Julia and not
    # to a person, so its edit is not filtered here. A cleared number holds
    # `nothing`, and its declared type says that the edit makes a number.
    is_cleared_number = value === nothing && _is_number_field(target, field)
    (value isa Number && !(value isa Bool) || is_cleared_number) &&
        !has_only_number_characters(op.replacement) && return
    if is_cleared_number
        setproperty!(target, field,
                     splice_number("", range_step.start, range_step.stop, op.replacement))
    else
        splice_value!(target, field, value, range_step.start, range_step.stop, op.replacement)
    end
    _replace_selection_with_cursor!(document, op)
end

# Whether `field` of `target` is declared to hold a number and not a text, read
# from the native layout of its schema. A document with no native layout, such as
# a hand-written one, answers `false`.
function _is_number_field(target, field::Symbol)
    native = get_document_native_type(target)
    (native === nothing || !hasfield(native, field)) && return false
    declared = fieldtype(native, field)
    !(String <: declared) && Int <: declared
end

# Put a zero-width cursor selection at the post-edit position, so every node
# along the path (root, intermediates, target) holds the suffix relevant to its
# subtree. `replace_selection!` stores what a clear and a set would store, but it
# writes only the cells whose value changes: a caret that moves within the text
# it edits changes the terminal step alone, so no container on the path that
# reads its selection is computed again.
function _replace_selection_with_cursor!(document, op)
    new_path = _replace_terminal_with_cursor(op.reference, op.replacement)
    replace_selection!(document, new_path)
end

# Text/number edits to PrimitiveString / PrimitiveNumber are handled generically
# by `splice_value!` (string / number representations) — no per-type method
# needed; the value field is a plain `String`/`Number`.

# ── Sequence interface for PrimitiveString ────────────────────────────────────
# Indexing is by **character position** (1-based), consistent with `length` (a
# character count). The underlying `String` is byte-indexed, so every access goes
# through character-aware helpers (`collect`, `splice_string`) rather than raw
# `str[i]`, which would be a byte index and break on multibyte content.

Base.length(s::PrimitiveString) = length(something(s.value, ""))

Base.getindex(s::PrimitiveString, i::Integer) = collect(something(s.value, ""))[i]

function Base.getindex(s::PrimitiveString, r::UnitRange{Int})
    PrimitiveString(String(collect(something(s.value, ""))[r]))
end

Base.iterate(s::PrimitiveString, state...) = iterate(something(s.value, ""), state...)

Base.isempty(s::PrimitiveString) = isempty(something(s.value, ""))

Base.firstindex(::PrimitiveString) = 1
Base.lastindex(s::PrimitiveString) = length(s)

function Base.setindex!(s::PrimitiveString, ch::AbstractChar, i::Integer)
    # Replace the i-th character (multibyte-safe) via the canonical splice helper
    # on 0-based boundaries [i-1, i].
    s.value = splice_string(something(s.value, ""), i - 1, i, string(ch))
    return ch
end

# Primitive's own methods for the open reference-rewrite generics. Both
# operation types carry a reference field named `reference` (as
# opposed to `path` on ReplaceSelectionOperation), so their reroot forms
# prepend the container's steps onto that reference.

# `operation_reference` / `retarget_operation` registers these two operations: the
# catch-all `reroot_operation` of the kernel reroots their reference, and the
# default `read_intent` maps it back through a projection. The kernel cannot name
# them, and a `read_intent(::Projection, iomap, ::TheOp)` method here would be
# ambiguous with the catch-all reader of every concrete projection.
operation_reference(op::ReplaceStringRangeOperation) = op.reference
operation_reference(op::ReplaceNumberRangeOperation) = op.reference

retarget_operation(op::ReplaceStringRangeOperation, reference::Reference) =
    ReplaceStringRangeOperation(reference, op.replacement)
retarget_operation(op::ReplaceNumberRangeOperation, reference::Reference) =
    ReplaceNumberRangeOperation(reference, op.replacement)

# ── The way back ─────────────────────────────────────────────────────────────
#
# The way back from a range edit is the field it edited, as it was — a whole-field
# write, not another range edit.
#
# Two reasons. It CARRIES the object it writes into, so the entry survives the
# document moving in the tree, where a path from the editor's root would go stale.
# And it covers every representation a text field can hold — a string, a cleared
# field, a number, a styled span — because it puts the value itself back rather
# than splicing characters into whatever is there.

make_inverse_operation(document, op::ReplaceStringRangeOperation) =
    _make_range_inverse(document, op)
make_inverse_operation(document, op::ReplaceNumberRangeOperation) =
    _make_range_inverse(document, op)

function _make_range_inverse(document, op)
    split = _split_replace_reference(op.reference)
    # No editable slot — an edit aimed at a projection-introduced span. The write
    # does nothing, and there is nothing to take back.
    split === nothing && return DoNothingOperation()
    target_path, field_name, _ = split
    target = try_evaluate_reference(document, target_path)
    target === nothing && return nothing
    hasproperty(target, Symbol(field_name)) || return nothing
    ReplaceReferencedValueOperation(target, field_name,
                                    getproperty(target, Symbol(field_name)))
end

# ── The type-in ──────────────────────────────────────────────────────────────
#
# A number holds only a parsed number. A key whose text the number can not show,
# such as `-`, `1e` or `12.`, replaces the number with a `PrimitiveInsertion` of
# that text, limited to a number; the type-in becomes a number again at the key
# whose text a number shows exactly, and at its commit.

"""
    parse_primitive_document(type, text) -> Union{PrimitiveDocument, Nothing}

The document of `type` whose value `text` is the text of, or `nothing` when it
is none. A number is an `Int` when `text` is one and a `Float64` when it is one,
as a key in a number parses it, and an empty text is no number. A `Bool` is
`true` or `false`. A string is any text.
"""
function parse_primitive_document(::Type{PrimitiveNumber}, text::AbstractString)
    isempty(text) && return nothing
    value = something(tryparse(Int, text), tryparse(Float64, text), Some(nothing))
    value === nothing ? nothing : PrimitiveNumber(value)
end

parse_primitive_document(::Type{PrimitiveBool}, text::AbstractString) =
    text == "true" ? PrimitiveBool(true) : text == "false" ? PrimitiveBool(false) : nothing

parse_primitive_document(::Type{PrimitiveString}, text::AbstractString) = PrimitiveString(String(text))

"""
    get_primitive_text(document) -> String

The text that a primitive document shows: the print of its value, and the empty
text when it has no value.
"""
get_primitive_text(document::PrimitiveDocument) =
    document.value === nothing ? "" : string(document.value)

"""
    find_primitive_document(types, text) -> Union{PrimitiveDocument, Nothing}

The document of the first of `types` that `text` parses as, or `nothing`. The
commit of a type-in makes it: `1.50` becomes the number `1.5`.
"""
function find_primitive_document(types, text::AbstractString)
    for type in types
        document = parse_primitive_document(type, text)
        document === nothing || return document
    end
    nothing
end

"""
    find_exact_primitive_document(types, text) -> Union{PrimitiveDocument, Nothing}

The document of the first of `types` that shows `text` exactly, or `nothing`. A
type-in becomes it at the key that makes `text`, so the caret stays where the key
left it: `-5` is a number, and `12.` is none, because `12.0` shows another text.
"""
function find_exact_primitive_document(types, text::AbstractString)
    for type in types
        document = parse_primitive_document(type, text)
        document !== nothing && get_primitive_text(document) == text && return document
    end
    nothing
end

"""
    make_number_edit_operation(number, operation) -> Operation

The edit that `operation`, a range replace at `value{s:e}` of `number` itself,
makes of the number. When the number shows the new text exactly, it is
`operation`. When it can not, it replaces the number with a `PrimitiveInsertion`
of the new text, limited to a number, with the caret after the replacement. A
replacement with a character that no number has stays `operation`, which changes
nothing. A reader that turns a key into an edit of a number calls it.
"""
function make_number_edit_operation(number::PrimitiveNumber, operation::ReplaceRangeOperation)
    has_only_number_characters(operation.replacement) || return operation
    split = _split_replace_reference(operation.reference)
    split === nothing && return operation
    target_path, field_name, range_step = split
    (target_path isa EmptyReference && field_name == "value") || return operation
    text = splice_string(get_primitive_text(number), range_step.start, range_step.stop,
                         operation.replacement)
    find_exact_primitive_document((PrimitiveNumber,), text) === nothing || return operation
    insertion = PrimitiveInsertion(; value = text, allowed_types = (PrimitiveNumber,))
    make_replace_document_operation(EmptyReference(),
                     with_value_caret(insertion, range_step.start + length(operation.replacement)))
end

"""
    make_incomplete_number_document(number, text) -> Document or nothing

The document that takes the place of `number` while its text is `text`, a text
that the number can not show exactly, such as `-` or `1e`. A domain answers the
insertion of its domain with the text, so that the text stays while the person
types. The default, `nothing`, keeps the edit of the number, which drops a text
that does not parse.
"""
make_incomplete_number_document(number, text) = nothing

"""
    make_number_range_operation(input, reference, replacement) -> Operation

The edit that a key makes of a number below `input`: `reference` is the range
`value{s:e}` of the number, and `replacement` is the text of the key. It is a
`ReplaceNumberRangeOperation` when the number shows the new text exactly, or when
the new text is empty. Else it is a replace of the number with the document that
[`make_incomplete_number_document`](@ref) gives for the new text, with the caret
after the replacement, when the domain of the number gives one.
"""
function make_number_range_operation(input, reference::Reference, replacement::AbstractString)
    operation = ReplaceNumberRangeOperation(reference, replacement)
    split = _split_replace_reference(reference)
    split === nothing && return operation
    target_path, field_name, range_step = split
    number = try_evaluate_reference(input, target_path, missing)
    number isa Document || return operation
    old = getproperty(number, Symbol(field_name))
    text = splice_string(old === nothing ? "" : string(old), range_step.start, range_step.stop,
                         replacement)
    (isempty(text) || _is_exact_number_text(text)) && return operation
    document = make_incomplete_number_document(number, text)
    document === nothing && return operation
    make_replace_document_operation(target_path,
        with_value_caret(document, range_step.start + length(replacement)))
end

# A text that a number shows as it is: it parses, and the number prints it back.
function _is_exact_number_text(text::AbstractString)
    parsed = splice_number(text, 0, 0, "")
    parsed !== nothing && string(parsed) == text
end

"""
    with_value_caret(document, k) -> document

`document`, a document with a `value` field, with its caret at `k` in its value.
"""
with_value_caret(document::Document, k::Integer) =
    set_selection!(document, annotate_reference_types(document,
        ConcreteReference(FieldReferenceStep("value"),
                          ConcreteReference(RangeReferenceStep(k, k), EmptyReference()))))

"""
    get_type_in_placeholder(insertion) -> String

What an empty type-in shows: its own `placeholder`, or `enter a value`.
"""
get_type_in_placeholder(insertion::PrimitiveInsertion) = something(insertion.placeholder, "enter a value")

"""
    make_empty_primitive_document(type) -> PrimitiveDocument

A document of `type` with no value and its caret at the start, what Escape in a
type-in puts in its place. A Bool always has a value, so it is a whole `false`.
"""
make_empty_primitive_document(::Type{PrimitiveNumber}) = with_value_caret(PrimitiveNumber(nothing), 0)
make_empty_primitive_document(::Type{PrimitiveString}) = with_value_caret(PrimitiveString(""), 0)
make_empty_primitive_document(::Type{PrimitiveBool}) =
    (document = PrimitiveBool(false); set_selection!(document, annotate_reference_types(document, EmptyReference())))

"""
    find_value_range(document) -> Union{RangeReferenceStep, Nothing}

The range of the value of `document`, a primitive document, that its own
selection holds, `value{s:e}`, or `nothing` when it holds none.
"""
find_value_range(document::PrimitiveDocument) = find_value_range(getfield(document, :selection)[])

"""
    find_value_range(reference) -> Union{RangeReferenceStep, Nothing}

The range of `reference` when it is `value{s:e}`, the path of a range of the
value of a primitive document, typed or not; `nothing` for any other path.
"""
function find_value_range(reference)
    reference isa Reference || return nothing
    path = strip_reference_types(reference)
    (path isa ConcreteReference && path.head == FieldReferenceStep("value")) || return nothing
    tail = path.tail
    (tail isa ConcreteReference && tail.head isa RangeReferenceStep) ? tail.head : nothing
end

"""
    find_deletion_range(range, count, direction) -> Union{RangeReferenceStep, Nothing}

The range that Backspace (`:backspace`) or Delete (`:delete`) removes from a text
of `count` characters with the selection `range`: the selected range, or the
character before or after a caret; `nothing` at the edge of the text.
"""
function find_deletion_range(range::RangeReferenceStep, count::Integer, direction::Symbol)
    range.start != range.stop && return range
    direction === :backspace && return range.start > 0 ? RangeReferenceStep(range.start - 1, range.start) : nothing
    range.stop < count ? RangeReferenceStep(range.stop, range.stop + 1) : nothing
end

"""
    make_type_in_edit_operation(insertion, range, replacement) -> Operation

The edit of the text of `insertion` that puts `replacement` in `range`: a
replace of the type-in with the document of the first allowed type that shows the
new text exactly, with the caret after the replacement, or else the edit of the
text itself.
"""
function make_type_in_edit_operation(insertion::PrimitiveInsertion, range::RangeReferenceStep,
                                     replacement::AbstractString)
    text = splice_string(something(insertion.value, ""), range.start, range.stop, replacement)
    document = find_exact_primitive_document(insertion.allowed_types, text)
    document === nothing ||
        return make_replace_document_operation(EmptyReference(),
            with_value_caret(document, range.start + length(replacement)))
    ReplaceStringRangeOperation(ConcreteReference(FieldReferenceStep("value"),
                                                  ConcreteReference(range, EmptyReference())), replacement)
end

"""
    make_type_in_commit_operation(insertion) -> Union{Operation, Nothing}

The commit of a type-in, which Enter makes: a replace of it with the document of
the first allowed type that its text parses as, with the caret at its end, or
`nothing` when the text parses as none.
"""
function make_type_in_commit_operation(insertion::PrimitiveInsertion)
    document = find_primitive_document(insertion.allowed_types, something(insertion.value, ""))
    document === nothing && return nothing
    make_replace_document_operation(EmptyReference(),
        with_value_caret(document, length(get_primitive_text(document))))
end

"""
    make_type_in_cancel_operation(insertion) -> Operation

What Escape in a type-in makes: a replace of it with the first allowed type with
no value.
"""
make_type_in_cancel_operation(insertion::PrimitiveInsertion) =
    make_replace_document_operation(EmptyReference(),
        make_empty_primitive_document(first(insertion.allowed_types)))
