"""
    ObjectToWidgetModule

Generic, reflection-driven projection from an arbitrary object to a widget
**form** that edits the object's reactive parameters. It walks the object's
`Cell`-typed fields and, for each one whose value is a renderable scalar, emits
a labelled control row:

    String / number  → WidgetText
    Bool             → WidgetCheckbox

Fields it cannot render as a simple control (a `Function`, a `StyleColor`, a
non-`Cell` field, …) are skipped — so a projection becomes configurable simply
by exposing its parameters as renderable scalar `Cell`s, while opaque forms stay
as non-editable escape hatches.

The controls edit the *object's own* cells. By convention an edited leaf control
emits `ReplaceReferencedValue(itself, content, new_value)` (the widget-layer
half wired separately); this projection's reader matches that operation **by
control identity** and redirects it to the bound parameter field on the object —
`ReplaceReferencedValue(object, FieldReference(name), value)` — which the editor
evaluates by writing the cell. No reference plumbing: the control→field map is
the whole story.

Used by `ProjectionConfiguringProjection`, which projects an inner projection
*object* through this to build its parameter-control bar.
"""
module ObjectToWidgetModule

import ..ProjectionApiModule: projection_print, projection_read,
                              map_reference_forward, map_reference_backward, Projection
import ..IoMapApiModule: IoMap
import ..ReactiveModule: Cell, setfn!
import ..WidgetModule: WidgetDocument, WidgetLabel, WidgetText, WidgetCheckbox,
                       WidgetComposite, Point2D
import ..TextModule: TextText, TextString
import ..FontModule: StyleFont, font_ubuntu_monospace_regular_24
import ..ColorModule: StyleColor, color_default
import ..ReferenceModule: ReferencePath, ConcreteReferencePath, EmptyReferencePath,
                          FieldReference, RangeReference
import ..OperationModule: ReplaceReferencedValue
import ..PrimitiveModule: StringReplaceRangeOperation

export ObjectToWidget, ObjectToWidgetIoMap

# ── IoMap ─────────────────────────────────────────────────────────────────

"""
    ObjectToWidgetIoMap(projection, input, output, controls)

`input` is the projected object; `controls` is a `Vector` of
`(control_widget, field_name::String)` pairs — the map the reader uses to
redirect a control's edit back onto the object's field cell.
"""
struct ObjectToWidgetIoMap <: IoMap
    projection::Any
    input::Any
    output::Any
    controls::Vector{Tuple{Any,String}}
end

# ── Projection ────────────────────────────────────────────────────────────

"""
    ObjectToWidget(; fields=nothing)

`fields=nothing` auto-detects every renderable scalar `Cell` field (in
declaration order). Pass an explicit `Vector{Symbol}` to restrict/order the
controls.
"""
struct ObjectToWidget <: Projection
    fields::Union{Vector{Symbol},Nothing}
    font::StyleFont
    color::StyleColor
end

ObjectToWidget(; fields=nothing,
               font::StyleFont=font_ubuntu_monospace_regular_24,
               color::StyleColor=color_default) = ObjectToWidget(fields, font, color)

# Vertical pitch of one control row and the x where the control sits after its
# label. Approximate — the widget→graphics layer does the real measuring.
const _ROW_H = 28
const _CONTROL_X = 160

# ── projection_print ──────────────────────────────────────────────────────

function projection_print(p::ObjectToWidget, recursion, obj, ctx)
    rows = Any[]
    controls = Tuple{Any,String}[]
    y = 0
    for nm in _control_fields(p, obj)
        cell = getfield(obj, nm)
        control = _make_control(p, cell, cell[])
        push!(controls, (control, String(nm)))
        label = WidgetLabel(Point2D(0, 0), String(nm))
        push!(rows, WidgetComposite(Point2D(0, y), Any[label, control]))
        y += _ROW_H
    end
    output = WidgetComposite(Point2D(0, 0), rows)
    ObjectToWidgetIoMap(p, obj, output, controls)
end

# Two-argument convenience entry mirroring the editor's bare-call form.
projection_print(p::ObjectToWidget, obj) = projection_print(p, nothing, obj, nothing)

# Field selection: explicit whitelist, or every renderable scalar Cell field.
function _control_fields(p::ObjectToWidget, obj)
    p.fields !== nothing && return p.fields
    Symbol[nm for nm in fieldnames(typeof(obj)) if _is_renderable_field(obj, nm)]
end

function _is_renderable_field(obj, nm::Symbol)
    nm === :selection && return false
    f = getfield(obj, nm)
    f isa Cell || return false
    _is_renderable_value(f[])
end

_is_renderable_value(::Bool) = true
_is_renderable_value(::AbstractString) = true
_is_renderable_value(::Real) = true
_is_renderable_value(_) = false

# Bool is more specific than Real, so the checkbox wins for booleans.
_make_control(::ObjectToWidget, ::Cell, value::Bool) = WidgetCheckbox(Point2D(_CONTROL_X, 0), value)
_make_control(p::ObjectToWidget, cell::Cell, ::AbstractString) = _editable_text_control(p, cell)
_make_control(p::ObjectToWidget, cell::Cell, ::Real) = _editable_text_control(p, cell)

# An editable text control: a WidgetText whose TextText content is a read-only,
# reactive view of `cell` (so a change to the parameter re-renders it), with the
# caret pinned to the end of the text. WidgetText recurses a Document content
# through the Text domain, so caret navigation and editing originate in
# TextToGraphics; the edit operation is converted back to the parameter by the
# reader. Pinning the caret to the end keeps append/backspace correct without a
# persistent cursor stored in the (projection-output) control bar.
function _editable_text_control(p::ObjectToWidget, cell::Cell)
    ts = TextString("", p.font, p.color)
    setfn!(getfield(ts, :content), () -> _as_string(cell[]))
    tt = TextText(ts)
    setfn!(getfield(tt, :selection), () -> _end_cursor(length(_as_string(cell[]))))
    WidgetText(Point2D(_CONTROL_X, 0), tt)
end

_as_string(v) = v isa AbstractString ? String(v) : (v === nothing ? "" : string(v))

# `elements[1].content{n}` — a zero-width caret at char offset n.
_end_cursor(n::Int) = ConcreteReferencePath(FieldReference("elements"),
    ConcreteReferencePath(RangeReference(0, 1),
        ConcreteReferencePath(FieldReference("content"),
            ConcreteReferencePath(RangeReference(n, n), EmptyReferencePath()))))

# ── projection_read ───────────────────────────────────────────────────────
# Two control-edit shapes are converted to the input domain (a
# ReplaceReferencedValue that sets the parameter cell):
#
# - A checkbox click arrives as ReplaceReferencedValue rooted at the control
#   widget (identity); redirect it to the bound field.
# - A text edit arrives as a StringReplaceRangeOperation whose reference is
#   rooted at this projection's output (`elements[row].elements[2].content…`);
#   identify the field from the row, apply the character-range edit to the
#   field's current value, and emit the new whole value.

function projection_read(p::ObjectToWidget, iomap::ObjectToWidgetIoMap, op::ReplaceReferencedValue)
    for (control, nm) in iomap.controls
        op.document === control || continue
        current = getfield(iomap.input, Symbol(nm))[]
        value = _coerce(current, op.value)
        return ReplaceReferencedValue(iomap.input,
                   ConcreteReferencePath(FieldReference(nm), EmptyReferencePath()), value)
    end
    op   # not one of ours — pass through
end

function projection_read(p::ObjectToWidget, iomap::ObjectToWidgetIoMap, op::StringReplaceRangeOperation)
    parsed = _parse_control_edit(op.reference)
    parsed === nothing && return op
    row, cstart, cstop = parsed
    (1 <= row <= length(iomap.controls)) || return op
    nm = iomap.controls[row][2]
    current = _as_string(getfield(iomap.input, Symbol(nm))[])
    newval = _coerce(getfield(iomap.input, Symbol(nm))[], _apply_range(current, cstart, cstop, op.replacement))
    ReplaceReferencedValue(iomap.input,
        ConcreteReferencePath(FieldReference(nm), EmptyReferencePath()), newval)
end

projection_read(::ObjectToWidget, ::ObjectToWidgetIoMap, op) = op

# Parse a control text-edit reference `elements[row].elements[2].content.
# elements[1].content[cstart:cstop]`: the first RangeReference gives the 1-based
# row, the terminal RangeReference gives the character range.
function _parse_control_edit(ref)
    ranges = RangeReference[]
    cur = ref
    while cur isa ConcreteReferencePath
        cur.head isa RangeReference && push!(ranges, cur.head)
        cur = cur.tail
    end
    length(ranges) >= 2 || return nothing
    row = ranges[1].start + 1
    term = ranges[end]
    (row, term.start, term.stop)
end

# Character-aware range replace (0-based [s, e] boundaries).
function _apply_range(s::AbstractString, cs::Int, ce::Int, repl::AbstractString)
    n = length(s)
    left  = cs <= 0 ? "" : first(s, cs)
    right = ce >= n ? "" : last(s, n - ce)
    String(left) * repl * String(right)
end

# Coerce an edited value to the field's current type (text controls deliver
# strings; numbers/bools are parsed). Unparseable input keeps the old value.
_coerce(::AbstractString, v) = String(v)
_coerce(::Bool, v) = v isa Bool ? v : (v == true || v == "true" || v == "1")
_coerce(cur::Integer, v) = v isa Integer ? v : something(tryparse(Int, String(v)), cur)
_coerce(cur::AbstractFloat, v) = v isa AbstractFloat ? v : something(tryparse(Float64, String(v)), cur)
_coerce(_, v) = v

# ── Reference mapping ─────────────────────────────────────────────────────
# The control subtree does not map into the projected object's reference space
# (v1), mirroring ConversationToWidget.

map_reference_forward(::ObjectToWidget, ::ObjectToWidgetIoMap, reference) = nothing
map_reference_backward(::ObjectToWidget, ::ObjectToWidgetIoMap, reference) = nothing

end # module
