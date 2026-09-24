# Fragment of `WidgetModule`.
#
# Projects an [`ObjectField`](@ref) — one field of one object — to the **bare
# control** that displays and edits it.
#
# # Why a bare control and not a labelled row
#
# A `GridLayout` takes a flat child list, so a label and its control must be two
# separate children. A projection that emitted both could never place them in
# different columns. The caller writes the label:
#
#     GridLayout(Any[
#         WidgetLabel("Server name"), ObjectField(server, "name"),
#         WidgetLabel("Client name"), ObjectField(client, "name"),
#         WidgetLabel("Capacity"),    ObjectField(server, "capacity"),
#     ], 2)
#
# The two `name` fields come from **different objects**. `ObjectToWidget` can not
# do that: it takes one root and emits a fixed grid of that root's own fields.
#
# # The control
#
# The value type picks the control, through the same classification
# `ObjectToWidget` uses:
#
#     Bool             → WidgetCheckbox
#     String / number  → WidgetText
#     anything else    → WidgetLabel (read only)
#
# `controls` is a `Vector{Type}` mapping value type to projection, so a domain adds
# a row without a change here. The default table is the three above.
#
# The control is chosen **once**, from the value at print time, and its content is
# then bound reactively. A value that changes type after the first print keeps the
# old control. That is the same bound `ObjectToWidget` has, and it keeps the
# control identity — and with it the caret — stable across an ordinary edit.
#
# # Editing an element
#
# A vector element renders read-only under `ObjectToWidget`, because a `@document`
# field is a `Cell` but a vector's elements live inside one cell, and its printer
# registers a control only when it holds the backing cell. This projection needs no
# cell: it writes through the path. `ElementReferenceStep(i)` is
# `RangeReferenceStep(i-1, i)`, which `_write_slot!` writes as `parent[i] = value`.
#
# One trap comes with that. The kernel overloads the same terminal step with an
# `AbstractVector` value as a **splice**. An `ObjectField` whose value is itself a
# vector can not be written by a plain replace; the write would delete and
# re-insert.
# The value classification, the type coercion, the character-range edit and the
# end-caret path are `ObjectToWidget`'s and are used unchanged. One control looks
# and behaves the same whether a form or a reflected object produced it, so a
# second copy of these would be a second thing to keep in step.


"""
    ObjectFieldToWidgetIoMap(projection, input, output)

`input` is the `ObjectField`; `output` is the single control. The field carries
its own object and path, so the io map needs no control table — unlike
`ObjectToWidgetIoMap`, which holds one row per control because its input is a
whole object.
"""
@iomap struct ObjectFieldToWidgetIoMap
    projection::Any
    input::Any
    output::Any
end

"""
    ObjectFieldToWidget(; style, controls)

`style` is the text style of an editable control. `controls` is the value-type
table; pass your own to add a control for a domain type, for example
`Quantity => _spin_box`.
"""
struct ObjectFieldToWidget <: Projection
    style::StyleText
    controls::Vector{Pair{Type,Any}}
end

ObjectFieldToWidget(; style::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_default),
                      controls::Vector{Pair{Type,Any}} = Pair{Type,Any}[]) =
    ObjectFieldToWidget(style, controls)

# ── print_document ────────────────────────────────────────────────────────────

function print_document(p::ObjectFieldToWidget, recursion, field::ObjectField, ctx)
    ObjectFieldToWidgetIoMap(p, field, _control(p, field))
end

print_document(p::ObjectFieldToWidget, field::ObjectField) =
    print_document(p, nothing, field, nothing)

# The value is read once here to choose the control, then never again outside a
# cell: every control below binds its content to a thunk, so a write to the
# object repaints it (PAR-REACTIVE-PRINTER).
function _control(p::ObjectFieldToWidget, field::ObjectField)
    value = get_object_field_value(field)
    for (T, make) in p.controls
        value isa T && return make(p, field)
    end
    value isa Bool && return _checkbox(p, field)
    (value isa AbstractString || value isa Real) && return _text_control(p, field)
    _read_only_label(p, field)
end

function _checkbox(p::ObjectFieldToWidget, field::ObjectField)
    control = WidgetCheckbox(Point2D(0, 0), get_object_field_value(field))
    set_cell_computation!(getfield(control, :content),
                          () -> get_object_field_value(field))
    control
end

# A WidgetText whose TextBlock content is a reactive view of the field.
# `WidgetText` recurses a Document content through the Text domain, so caret
# navigation and editing originate in `TextToGraphics` and come back here as a
# `ReplaceStringRangeOperation`.
#
# **The caret follows the field's own selection.** A click sets it — through the
# default backward mapper, which roots the control path at the `ObjectField` —
# and this reads it back out, so the caret sits where the person clicked. With
# no selection the caret is at the end of the text, which is where a form that
# nobody has clicked wants it and what `ObjectToWidget` pins it to.
function _text_control(p::ObjectFieldToWidget, field::ObjectField)
    ts = TextString("", p.style)
    set_cell_computation!(getfield(ts, :content),
                          () -> _as_string(get_object_field_value(field)))
    tt = TextBlock(ts)
    set_cell_computation!(getfield(tt, :selection), () -> begin
        inside = _caret_in_content(getfield(field, :selection)[])
        inside === nothing ?
            _end_cursor(length(_as_string(get_object_field_value(field)))) : inside
    end)
    WidgetText(Point2D(0, 0), tt)
end

# The caret the field holds, as a path inside the control's own content.
#
# A click comes back through the default backward mapper as
# `proj(this projection, <path in the control>)`, and the control is a
# `WidgetText` whose content is the block. So the part below `.content` is the
# block's own selection, and everything else — a caret the field does not carry,
# or one that names something else — answers nothing.
function _caret_in_content(selection)
    selection isa ConcreteReference || return nothing
    step = selection.head
    hasproperty(step, :output_path) || return nothing
    inner = step.output_path
    inner isa ConcreteReference || return nothing
    (inner.head isa FieldReferenceStep && inner.head.name == "content") || return nothing
    inner.tail isa ConcreteReference ? inner.tail : nothing
end

function _read_only_label(p::ObjectFieldToWidget, field::ObjectField)
    control = WidgetLabel(Point2D(0, 0), _as_string(get_object_field_value(field)))
    set_cell_computation!(getfield(control, :content),
                       () -> _as_string(get_object_field_value(field)))
    control
end

# ── read_intent ───────────────────────────────────────────────────────────────
#
# Both control edits become one write on the field's own object and path, so an
# edit at any depth — a nested field, a vector element — lands in the right slot.
# The reader stays pure: it RETURNS the operation and writes nothing
# (PAR-READER-IS-PURE).

# A checkbox click arrives rooted at the control itself, by identity.
function read_intent(p::ObjectFieldToWidget, iomap::ObjectFieldToWidgetIoMap,
                     op::ReplaceReferencedValueOperation)
    op.document === iomap.output || return op
    field = iomap.input
    ReplaceReferencedValueOperation(field.object, field.path,
                                    _coerce(get_object_field_value(field), op.value))
end

# A text edit arrives as a character range rooted at this stage's output. The
# output IS the control, so the terminal RangeReferenceStep is the character
# range — there is no grid row to identify first, which is the whole reason this
# reader is short and `ObjectToWidget`'s is not.
function read_intent(p::ObjectFieldToWidget, iomap::ObjectFieldToWidgetIoMap,
                     op::ReplaceStringRangeOperation)
    iomap.output isa WidgetText || return op
    term = _terminal_range(op.reference)
    term === nothing && return op
    field = iomap.input
    current = get_object_field_value(field)
    edited = _apply_range(_as_string(current), term.start, term.stop, op.replacement)
    ReplaceReferencedValueOperation(field.object, field.path, _coerce(current, edited))
end

# A click on a control sets a caret in the control's own text, and that caret has
# no pre-image in the object: the object holds a value, not a position in a
# rendering of it. The default of `Projection` is what answers here — it roots
# the control path at the `ObjectField` as a projection-introduced path, which
# `_text_control` reads back so the caret sits where the click was. Consuming it,
# as this projection first did, leaves a form nobody can type into: with no
# selection anywhere, no container knows which control a key belongs to.

read_intent(::ObjectFieldToWidget, ::ObjectFieldToWidgetIoMap, op) = op

# The last RangeReferenceStep of a reference. In a control edit that is the
# character range; the earlier ones index the TextBlock's elements.
function _terminal_range(ref)
    term = nothing
    cur = ref
    while cur isa ConcreteReference
        cur.head isa RangeReferenceStep && (term = cur.head)
        cur = cur.tail
    end
    term
end

# ── Reference mapping ─────────────────────────────────────────────────────────
#
# Neither direction is written here, and that is the answer rather than a gap. A
# caret in the control names a position in a rendering, and the object has no
# such position to name; the defaults of `Projection` wrap it as a
# projection-introduced path on the way in and unwrap it on the way out, which is
# exactly the correspondence. Answering `nothing` from either would drop every
# click and every key that crosses this projection.
