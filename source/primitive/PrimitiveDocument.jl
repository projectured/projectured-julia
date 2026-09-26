# Fragment of `PrimitiveModule` — the primitive document types: the abstract
# `PrimitiveDocument`, its insertion placeholder, and the leaf documents that
# carry a single value.

abstract type PrimitiveDocument <: Document end

# A primitive holds one value a person types, so its duplicate is a copy of it.
has_document_duplicate(::PrimitiveDocument) = true

# ── PrimitiveInsertion ──────────────────────────────────────────────────────

"""
    PrimitiveInsertion(; value=nothing, selection=nothing)

An empty primitive-domain slot — a "hole" awaiting a value, the primitive
counterpart of a domain's insertion placeholder. `value` holds whatever pending
content has been typed into it (or `nothing` while still empty); editing it is how
a concrete primitive value comes to replace the insertion.
"""
@document struct PrimitiveInsertion <: PrimitiveDocument
    value::Any = nothing
end

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

"""
    make_pred_document(::Type{PrimitiveString}, positional, keywords)

The string a call in a file builds: `PrimitiveString("hi")` or
`PrimitiveString(value = "hi")`. `value` has no field default, so the macro
gives the bare name no keyword constructor — [`pred_arguments`](@ref) always
writes a document's fields as keywords, so the file format needs this one.
"""
make_pred_document(::Type{PrimitiveString}, positional, keywords) =
    PrimitiveString(isempty(positional) ? only(keywords).second : positional[1])

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
# prepend the container's steps onto that reference. Every path-bearing
# operation type must add a method here; missing methods fall through to
# the catch-all in `operation/Rerooting.jl` and are returned unchanged.

reroot_operation(op::ReplaceStringRangeOperation, steps::Tuple) =
    ReplaceStringRangeOperation(reroot_reference(op.reference, steps), op.replacement)
reroot_operation(op::ReplaceNumberRangeOperation, steps::Tuple) =
    ReplaceNumberRangeOperation(reroot_reference(op.reference, steps), op.replacement)

# `operation_reference` / `retarget_operation` is what lets the default
# `read_intent` in the kernel map these two operations back through a projection.
# The kernel cannot name them, and a `read_intent(::Projection, iomap, ::TheOp)`
# method here would be ambiguous with the catch-all reader of every concrete
# projection.
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
