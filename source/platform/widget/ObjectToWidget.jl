# Fragment of `WidgetModule`.
#
# Generic, reflection-driven projection from an object to a widget **form** that
# shows and edits its fields. It makes the form that an author makes by hand: for
# each field, a `WidgetLabel` with its name and the widget that `make_widget`
# makes for `ObjectField(root, path)`, in a 2-column `GridLayout`:
#
#     String / number  → WidgetText(field)      (the defaults of
#     Bool             → WidgetCheckbox(field)   `make_object_field_widget`)
#     a record         → a 2-column grid of its own fields, in a collapsible
#                        `WidgetCard`
#     vector / tuple   → a `VerticalLayout` of its elements, in a collapsible
#                        `WidgetCard`
#
# A record is a value that `is_record` opens: by default `is_form_record`, a struct
# that holds a cell field, such as a `@document`. Any other struct, such as a
# `StyleColor`, is not shown.
#
# The **root** object renders as a bare `WidgetComposite` wrapping its grid — *no*
# surrounding card. Cards appear only for *nested* values.
#
# # The stage after it
#
# The output is a document of layouts and widgets whose value slots hold
# `ObjectField`s. A chain draws it with a recursion that holds the rows of
# `make_object_field_widget_dispatch`, as for a form an author makes:
#
#     ChainingProjection(ObjectToWidget(),
#         RecursiveProjection(TypeDispatchingProjection(vcat(
#             LayoutToGraphics().dispatch, make_object_field_widget_dispatch(w2g.dispatch)))))
#
# # Editing
#
# Each widget asks its field for the operation that stores a value, so an edit at
# any depth writes through the field and the write rules of the kernel: a field of
# a record, a nested text, an element of a vector, and a field of a plain value
# that a record holds. This projection reads no edit itself.
#
# # The caret
#
# A caret in the text of a field is a path in the object: the path of the field
# and a range, such as `window.title{3}`. The maps put it under the widget that
# shows the field, with the slot of the widget and the step `object` of the
# field before it (`make_object_field_range_reference`), and take them off on the
# way back. The selection of each document of the form follows the part of the
# path below it, as a key is routed by the selection.
#
# **Collapse.** Each nested card is collapsible. Collapse is view state on the
# output `WidgetCard.collapsed` cell: a click on the chevron answers
# `ToggleCollapseOperation(card)`. The form is made once for its input, so an edit
# of a value keeps the collapse of every card.

# ── IoMap ─────────────────────────────────────────────────────────────────

"""
    ObjectToWidgetIoMap(projection, input, output, controls)

`input` is the projected (root) object. `controls` holds one entry
`(widget, path, steps, slot)` for each field that the form shows with a widget:
the widget that the form made, the path from the root object to the field, the
steps from the output to the widget, and the slot of the widget that holds the
field, or `nothing`.
"""
@iomap struct ObjectToWidgetIoMap
    projection::Any
    input::Any
    output::Any
    controls::Vector{Tuple{Any,Reference,Tuple,Any}}
end

# ── Projection ────────────────────────────────────────────────────────────

"""
    is_form_record(value) -> Bool

Whether `ObjectToWidget` opens `value` into a card of its own fields when the
form passes no `is_record`. True for a struct that holds a cell field, such as a
`@document`; false for any other value, so a style value such as a `StyleColor`
does not open into numbers.

A type opts in with a method, and a plain value of it then edits through the
write rules of the kernel:

    is_form_record(::ServerSettings) = true
"""
is_form_record(value) = isstructtype(typeof(value)) && _has_cell_fields(value)

_has_cell_fields(v) = any(f -> getfield(v, f) isa Cell, fieldnames(typeof(v)))

"""
    ObjectToWidget(; fields = nothing, make_widget = make_object_field_widget,
                     is_record = is_form_record, theme = nothing, column_gap, row_gap)

The projection of an object to a form of its fields. `fields` restricts and orders
the fields of the **root** object; `nothing` shows every field that the form can
show, in the order of declaration.

`make_widget(field::ObjectField)` makes the widget of each field; it sees the
whole path, so a nested field can get a chosen widget too. `is_record(value)` says
whether a nested value opens into a card. The gaps come from `theme`, a
`WidgetTheme`, or the default values.

# Example

    ObjectToWidget(; make_widget = field ->
        get_object_field_name(field) == "draw_style" ?
            WidgetSelect(field; options = Any[:linear, :step, :bar]) :
            make_object_field_widget(field))
"""
struct ObjectToWidget <: Projection
    fields::Union{Vector{Symbol},Nothing}
    make_widget::Any
    is_record::Any
    column_gap::Int     # between the label column and the control column
    row_gap::Int        # between the rows of the form
end

ObjectToWidget(; fields=nothing, make_widget=make_object_field_widget, is_record=is_form_record,
               theme=nothing,
               column_gap::Integer=_get_theme_values(theme).form_column_gap,
               row_gap::Integer=_get_theme_values(theme).form_row_gap) =
    ObjectToWidget(fields, make_widget, is_record, Int(column_gap), Int(row_gap))

# Recursion bound: stop descending into composite values past this depth and show
# them as text, so a cyclic or pathologically deep object graph can't loop forever
# (the editor would otherwise hang printing it).
const _MAX_DEPTH = 16

const _FORM_GRID_STEPS = (FieldReferenceStep("elements"), RangeReferenceStep(0, 1))

# ── print_document ──────────────────────────────────────────────────────

function print_document(p::ObjectToWidget, recursion, obj, ctx)
    # The fields of a plain root share one cell, so an edit through one shows in
    # the others.
    root = obj isa Document ? obj : Cell(obj)
    controls = Tuple{Any,Reference,Tuple,Any}[]
    grid = _struct_grid(p, root, obj, EmptyReference(), _FORM_GRID_STEPS, controls, 0)
    output = WidgetComposite(Any[grid])
    iomap = ObjectToWidgetIoMap(p, obj, output, controls)
    set_output_path_computations!(output, obj, path -> map_reference_forward(p, iomap, path);
                                  dormant = false)
    set_output_tree_path_computations!(output)
    iomap
end

# Two-argument convenience entry mirroring the editor's bare-call form.
print_document(p::ObjectToWidget, obj) = print_document(p, nothing, obj, nothing)

# ── Reflection: which fields to show, and how to classify a value ───────────

# Field selection for a struct: explicit whitelist (root only), or every
# renderable field. A view state field, the document's own cursor slot and its
# mouse target, is never shown.
function _displayable_fields(p::ObjectToWidget, obj, basepath::Reference)
    if p.fields !== nothing && basepath isa EmptyReference
        return p.fields
    end
    Symbol[nm for nm in fieldnames(typeof(obj)) if _is_displayable_field(p, obj, nm)]
end

function _is_displayable_field(p::ObjectToWidget, obj, nm::Symbol)
    is_view_state_field(nm) && return false
    f = getfield(obj, nm)
    _value_kind(p, f isa Cell ? f[] : f) !== :opaque
end

# Classify a (cell-unwrapped) value into a render category.
_value_kind(p::ObjectToWidget, ::Bool) = :leaf
_value_kind(p::ObjectToWidget, ::AbstractString) = :leaf
_value_kind(p::ObjectToWidget, ::Real) = :leaf
_value_kind(p::ObjectToWidget, ::Union{AbstractVector,Tuple,CellVector}) = :vector
_value_kind(p::ObjectToWidget, v) = p.is_record(v) ? :record : :opaque

# ── Building the widget tree ────────────────────────────────────────────────

# A 2-column grid (label | widget) of `obj`'s displayable fields. `basepath` is the
# reference from the root object to `obj`; each field extends it by one step.
# `steps` are the steps from the output to the grid. `depth` is the current
# nesting level (0 at the root), used to bound recursion.
function _struct_grid(p::ObjectToWidget, root, obj, basepath::Reference, steps::Tuple, controls, depth::Int)
    children = Any[]
    for nm in _displayable_fields(p, obj, basepath)
        f = getfield(obj, nm)
        path = extend_reference(basepath, FieldReferenceStep(String(nm)))
        push!(children, WidgetLabel(String(nm)))
        index = length(children) + 1
        widget_steps = (steps..., FieldReferenceStep("children"), RangeReferenceStep(index - 1, index))
        push!(children, _print_value(p, root, f isa Cell ? f[] : f, path, widget_steps, controls, depth))
    end
    # The controls fill the width that the form is offered, so the cards of the
    # nested values line up; with no width offered they keep their own.
    GridLayout(children, 2;
               horizontal_gap=p.column_gap, vertical_gap=p.row_gap,
               vertical_align=:center, column_policies=Any[Content, Fill])
end

# The widget of one value at `path`, which the output reaches by `steps`.
function _print_value(p::ObjectToWidget, root, value, path::Reference, steps::Tuple, controls, depth::Int)
    kind = _value_kind(p, value)
    (kind === :vector || kind === :record) && depth >= _MAX_DEPTH &&
        return WidgetLabel(_as_string(value))   # recursion bound
    kind === :vector && return _print_vector(p, root, value, path, steps, controls, depth + 1)
    kind === :record && return _print_record_card(p, root, value, path, steps, controls, depth + 1)
    field = ObjectField(root, path)
    widget = p.make_widget(field)
    push!(controls, (widget, path, steps, _find_object_field_slot(widget, field)))
    widget
end

# A nested record: its own 2-column grid inside a composite, in a collapsible card.
function _print_record_card(p::ObjectToWidget, root, obj, path::Reference, steps::Tuple, controls, depth::Int)
    grid_steps = (steps..., FieldReferenceStep("content"), _FORM_GRID_STEPS...)
    grid = _struct_grid(p, root, obj, path, grid_steps, controls, depth)
    _collapsible_card(p, _type_title(obj), WidgetComposite(Any[grid]))
end

# A vector / tuple: its elements stacked vertically, in a collapsible card. Each
# element is a field of its own, at the path of the vector and its index.
function _print_vector(p::ObjectToWidget, root, vec, path::Reference, steps::Tuple, controls, depth::Int)
    items = Any[]
    for (i, element) in enumerate(vec)
        item_steps = (steps..., FieldReferenceStep("content"), FieldReferenceStep("children"),
                      RangeReferenceStep(i - 1, i))
        push!(items, _print_value(p, root, element, extend_reference(path, ElementReferenceStep(i)),
                                  item_steps, controls, depth))
    end
    body = VerticalLayout(items; horizontal_align=:left, gap=p.row_gap)
    _collapsible_card(p, _vector_title(vec), body)
end

# Wrap `body` in a collapsible card titled `title`. Collapse lives on the card's
# own `collapsed` cell: a click on the chevron → `ToggleCollapseOperation(card)`
# (emitted by WidgetCardToGraphicsCanvas) → the default handler flips
# `card.collapsed`. The card reads that cell as it draws: it turns the chevron and
# drops the body, so the toggle re-renders without reprinting the projection.
_collapsible_card(p::ObjectToWidget, title::AbstractString, body) =
    WidgetCard(; title = WidgetLabel(title),
               content = body, collapsible = true)

_type_title(obj) = String(nameof(typeof(obj)))
_vector_title(vec) = string(length(vec)) * (length(vec) == 1 ? " item" : " items")

_as_string(v) = v isa AbstractString ? String(v) : (v === nothing ? "" : string(v))

# Character-aware range replace (0-based [s, e] boundaries).
function _apply_range(s::AbstractString, cs::Int, ce::Int, repl::AbstractString)
    n = length(s)
    left  = cs <= 0 ? "" : first(s, cs)
    right = ce >= n ? "" : last(s, n - ce)
    String(left) * repl * String(right)
end

# Coerce an edited value to the field's current type (text controls deliver
# strings; numbers/bools are parsed; a slider delivers a `Float64`, which an
# integer field rounds). Unparseable input keeps the old value.
_coerce(::AbstractString, v) = String(v)
_coerce(::Bool, v) = v isa Bool ? v : (v == true || v == "true" || v == "1")
_coerce(cur::Integer, v) =
    v isa Integer ? v :
    v isa AbstractFloat ? round(Int, v) : something(tryparse(Int, String(v)), cur)
_coerce(cur::AbstractFloat, v) =
    v isa AbstractFloat ? v :
    v isa Real ? Float64(v) : something(tryparse(Float64, String(v)), cur)
_coerce(_, v) = v

# ── Reference mapping ─────────────────────────────────────────────────────
#
# `<path of a field><rest>` ↔ `<steps to its widget>.<slot>.object.<path><rest>`,
# where the rest is empty or a range in the text of the value. The whole field is
# the whole widget. A part of the form that the object has no path for, such as a
# label, is a path that this projection introduces, as the defaults of
# `Projection` map it.

function map_reference_forward(p::ObjectToWidget, iomap::ObjectToWidgetIoMap, reference)
    introduced = find_introduced_path(p, reference)
    introduced === nothing || return introduced
    reference isa EmptyReference && return EmptyReference(get_reference_node_type(iomap.output))
    steps = get_reference_steps(strip_reference_types(reference))
    for (_, path, widget_steps, slot) in iomap.controls
        field = get_reference_steps(strip_reference_types(path))
        _has_form_prefix(steps, field) || continue
        rest = steps[(length(field) + 1):end]
        isempty(rest) && return _annotate_form_path(iomap, widget_steps)
        (slot === nothing || length(rest) != 1 || !(rest[1] isa RangeReferenceStep)) && return nothing
        return _annotate_form_path(iomap, (widget_steps..., FieldReferenceStep(String(slot)),
                                           FieldReferenceStep("object"), steps...))
    end
    nothing
end

function map_reference_backward(p::ObjectToWidget, iomap::ObjectToWidgetIoMap, reference)
    if reference isa Reference
        steps = get_reference_steps(strip_reference_types(reference))
        for (_, path, widget_steps, slot) in iomap.controls
            _has_form_prefix(steps, widget_steps) || continue
            rest = steps[(length(widget_steps) + 1):end]
            isempty(rest) && return path
            slot === nothing && break
            inner = (FieldReferenceStep(String(slot)), FieldReferenceStep("object"))
            (_has_form_prefix(rest, inner) && !any(step -> step isa ProjectionReferenceStep, rest)) ||
                break
            return extend_reference(EmptyReference(), rest[(length(inner) + 1):end]...)
        end
    end
    invoke(map_reference_backward, Tuple{Projection, Any, Any}, p, iomap, reference)
end

_has_form_prefix(steps, prefix) =
    length(steps) >= length(prefix) && all(k -> steps[k] == prefix[k], eachindex(prefix))

_annotate_form_path(iomap::ObjectToWidgetIoMap, steps) =
    annotate_reference_types(iomap.output, extend_reference(EmptyReference(), steps...))
