"""
    ObjectToWidgetModule

Generic, reflection-driven projection from an arbitrary object to a widget
**form** that displays and edits the object's reactive parameters. It walks the
object's fields and, for each renderable one, emits a control:

    String / number  → WidgetText      (editable when backed by a `Cell`)
    Bool             → WidgetCheckbox
    struct (with `Cell` fields) → a 2-column `GridLayout` of its own fields,
                                  wrapped in a collapsible `WidgetCard`
    vector / tuple   → a `VerticalLayout` of its elements, wrapped in a
                       collapsible `WidgetCard`

The **root** object renders as a bare `WidgetComposite` wrapping a 2-column
(label | control) `GridLayout` — *no* surrounding card. Cards appear only for
*nested* composite values, so a flat object (only scalar fields) produces exactly
the historical output and the `ProjectionConfiguringProjection` control bar is
unaffected.

Fields it cannot render (a `Function`, a `StyleColor`, a plain struct without
`Cell` fields, …) are skipped — opaque forms stay non-editable.

**Collapse.** Each nested card is collapsible. Collapse is transient *view* state
stored on the output `WidgetCard.collapsed` cell (like `WidgetScrollPane`'s scroll
offset): the card's `title`/`content` are reactive `CellVector`s that read
`card.collapsed`, so a header click — which `WidgetCardToGraphicsCanvas` turns into
`ToggleCollapseOperation(card)`, flipped by the default operation handler —
re-renders the chevron and shows/hides the body.

**Editing.** Controls edit the *object's own* cells. A checkbox click or a text
edit is matched (by control identity, or by the top-level grid row) and converted
to `ReplaceReferencedValueOperation(root, path, value)` where `path` is the full reference
from the root to the edited field — so an edit at any nesting depth writes the
right cell. Caret navigation *into* the tree (real `map_reference_*`) and nested
text-caret editing are deferred to a later navigation stage.

Used by `ProjectionConfiguringProjection`, which projects an inner projection
*object* through this to build its parameter-control bar.
"""
module ObjectToWidgetModule

import ..ProjectionApiModule: print_document, read_intent,
                              map_reference_forward, map_reference_backward, Projection
import ..IoMapModule: IoMap, var"@iomap"
import ..CellModule: Cell, ComputedCell, set_cell_function!
import ..CollectionModule: CellVector, ComputedCellVector
import ..WidgetModule: WidgetDocument, WidgetLabel, WidgetText, WidgetCheckbox,
                       WidgetComposite, WidgetCard, Point2D
import ..LayoutModule: GridLayout, VerticalLayout, HorizontalLayout
import ..TextModule: TextBlock, TextString
import ..FontModule: StyleFont, font_ubuntu_monospace_regular_20
import ..ColorModule: StyleColor, color_default
import ..StyleTextModule: StyleText
import ..ReferenceModule: Reference, ConcreteReference, EmptyReference,
                          FieldReferenceStep, RangeReferenceStep, ElementReferenceStep,
                          extend_reference, evaluate_reference
import ..OperationModule: ReplaceReferencedValueOperation, ReplaceSelectionOperation
import ..PrimitiveModule: ReplaceStringRangeOperation

export ObjectToWidget, ObjectToWidgetIoMap

# ── IoMap ─────────────────────────────────────────────────────────────────

"""
    ObjectToWidgetIoMap(projection, input, output, controls)

`input` is the projected (root) object; `controls` is a `Vector` of
`(control_widget, path::Reference)` pairs — the map the reader uses to
redirect a control's edit back onto the object's field cell. `path` is the full
reference from the root object to the bound field (a single `FieldReferenceStep` for a
top-level field, a deeper path for a nested one).
"""
@iomap struct ObjectToWidgetIoMap
    projection::Any
    input::Any
    output::Any
    controls::Vector{Tuple{Any,Reference}}
end

# ── Projection ────────────────────────────────────────────────────────────

"""
    ObjectToWidget(; fields=nothing)

`fields=nothing` auto-detects every renderable field (in declaration order). Pass
an explicit `Vector{Symbol}` to restrict/order the controls of the **root** object.
"""
struct ObjectToWidget <: Projection
    fields::Union{Vector{Symbol},Nothing}
    style::StyleText
end

ObjectToWidget(; fields=nothing,
               style::StyleText=StyleText(font_ubuntu_monospace_regular_20, color_default)) = ObjectToWidget(fields, style)

# Inter-column / inter-row gaps for the parameter form. The label column width
# and row heights are content-driven by GridLayout; only these spacing tokens are
# fixed. Card chrome: header gap, default card width, fold markers.
const _COLUMN_GAP = 12
const _ROW_GAP = 6
const _HEADER_GAP = 4
const _CARD_WIDTH = 480
const _EXPANDED_MARKER = "▾"
const _COLLAPSED_MARKER = "▸"
# Recursion bound: stop descending into composite values past this depth and show
# them read-only, so a cyclic or pathologically deep object graph can't loop
# forever (the editor would otherwise hang printing it).
const _MAX_DEPTH = 16

# ── print_document ──────────────────────────────────────────────────────

function print_document(p::ObjectToWidget, recursion, obj, ctx)
    controls = Tuple{Any,Reference}[]
    # The root struct renders as a bare composite (no card), so a flat object is
    # byte-identical to the historical output and ProjectionConfiguring still gets
    # a WidgetComposite whose `visible` it can toggle.
    grid = _struct_grid(p, obj, EmptyReference(), controls, 0)
    output = WidgetComposite(Point2D(0, 0), Any[grid])
    ObjectToWidgetIoMap(p, obj, output, controls)
end

# Two-argument convenience entry mirroring the editor's bare-call form.
print_document(p::ObjectToWidget, obj) = print_document(p, nothing, obj, nothing)

# ── Reflection: which fields to show, and how to classify a value ───────────

# Field selection for a struct: explicit whitelist (root only), or every
# renderable field. `:selection` is the document's own cursor slot, never shown.
function _displayable_fields(p::ObjectToWidget, obj, basepath::Reference)
    if p.fields !== nothing && basepath isa EmptyReference
        return p.fields
    end
    Symbol[nm for nm in fieldnames(typeof(obj)) if _is_displayable_field(obj, nm)]
end

function _is_displayable_field(obj, nm::Symbol)
    nm === :selection && return false
    f = getfield(obj, nm)
    _value_kind(f isa Cell ? f[] : f) !== :opaque
end

# Classify a (cell-unwrapped) value into a render category.
_value_kind(::Bool) = :bool                       # before Real: a Bool is a checkbox
_value_kind(::AbstractString) = :string
_value_kind(::Real) = :real
_value_kind(::AbstractVector) = :vector
_value_kind(::Tuple) = :vector
function _value_kind(v)
    # Recurse only into "document-like" structs — those carrying reactive `Cell`
    # fields. Opaque value structs (StyleColor, Point2D, fonts, …) carry no cells
    # and are skipped, so we never explode into rendering primitives.
    isstructtype(typeof(v)) && _has_cell_fields(v) ? :struct : :opaque
end
_has_cell_fields(v) = any(f -> getfield(v, f) isa Cell, fieldnames(typeof(v)))

# ── Building the widget tree ────────────────────────────────────────────────

# A 2-column grid (label | value) of `obj`'s displayable fields. `basepath` is the
# reference from the root object to `obj`; each field extends it by one step.
# `depth` is the current nesting level (0 at the root), used to bound recursion.
function _struct_grid(p::ObjectToWidget, obj, basepath::Reference, controls, depth::Int)
    children = Any[]
    for nm in _displayable_fields(p, obj, basepath)
        f = getfield(obj, nm)
        value = f isa Cell ? f[] : f
        path = extend_reference(basepath, FieldReferenceStep(String(nm)))
        push!(children, WidgetLabel(Point2D(0, 0), String(nm)))
        push!(children, _print_value(p, value, f isa Cell ? f : nothing, path, controls, depth))
    end
    GridLayout(children, 2;
               horizontal_gap=_COLUMN_GAP, vertical_gap=_ROW_GAP,
               vertical_align=:center)
end

# Project one value into a widget. `cell` is the backing `Cell` (or `nothing` when
# the value is not individually cell-addressable, e.g. a vector element); a leaf is
# registered as an editable control only when it has a backing cell.
function _print_value(p::ObjectToWidget, value, cell, path::Reference, controls, depth::Int)
    kind = _value_kind(value)
    if kind === :bool
        control = WidgetCheckbox(Point2D(0, 0), value)
        cell isa Cell && push!(controls, (control, path))
        return control
    elseif kind === :string || kind === :real
        if cell isa Cell
            control = _editable_text_control(p, cell)
            push!(controls, (control, path))
            return control
        end
        return WidgetLabel(Point2D(0, 0), _as_string(value))   # read-only leaf
    elseif (kind === :vector || kind === :struct) && depth >= _MAX_DEPTH
        return WidgetLabel(Point2D(0, 0), _as_string(value))   # recursion bound
    elseif kind === :vector
        return _print_vector(p, value, path, controls, depth + 1)
    elseif kind === :struct
        return _print_struct_card(p, value, path, controls, depth + 1)
    end
    WidgetLabel(Point2D(0, 0), _as_string(value))
end

# A nested struct: its own 2-column grid inside a composite, in a collapsible card.
function _print_struct_card(p::ObjectToWidget, obj, path::Reference, controls, depth::Int)
    grid = _struct_grid(p, obj, path, controls, depth)
    body = WidgetComposite(Point2D(0, 0), Any[grid])
    _collapsible_card(p, _type_title(obj), body)
end

# A vector / tuple: its elements stacked vertically, in a collapsible card. Vector
# elements are not individually cell-addressable, so they render read-only (no
# controls registered) — element editing belongs to the later navigation stage.
function _print_vector(p::ObjectToWidget, vec, path::Reference, controls, depth::Int)
    items = Any[]
    for (i, element) in enumerate(vec)
        elpath = extend_reference(path, ElementReferenceStep(i))   # 1-based
        push!(items, _print_value(p, element, nothing, elpath, controls, depth))
    end
    body = VerticalLayout(items; horizontal_align=:left, gap=_ROW_GAP)
    _collapsible_card(p, _vector_title(vec), body)
end

# Wrap `body` in a collapsible card titled `title`. Collapse lives on the card's
# own `collapsed` cell: a header click → `ToggleCollapseOperation(card)` (emitted by
# WidgetCardToGraphicsCanvas) → default handler flips `card.collapsed`. The title
# (chevron) and content (body vs empty) are reactive `CellVector`s reading
# `card.collapsed`, so the toggle re-renders without reprinting the projection.
function _collapsible_card(p::ObjectToWidget, title::AbstractString, body)
    card = WidgetCard(Point2D(0, 0); width=_CARD_WIDTH)
    header = HorizontalLayout(ComputedCellVector(() -> Any[
        WidgetLabel(Point2D(0, 0),
                    (card.collapsed ? _COLLAPSED_MARKER : _EXPANDED_MARKER) * " " * title)
    ]), Cell(:top), Cell(_HEADER_GAP), Cell(nothing), Cell(nothing), Cell(nothing))
    content = VerticalLayout(ComputedCellVector(() -> card.collapsed ? Any[] : Any[body]),
                             Cell(:left), Cell(0), Cell(nothing), Cell(nothing),
                             Cell(nothing))
    card.title = header
    card.content = content
    card
end

_type_title(obj) = String(nameof(typeof(obj)))
_vector_title(vec) = string(length(vec)) * (length(vec) == 1 ? " item" : " items")

# An editable text control: a WidgetText whose TextBlock content is a read-only,
# reactive view of `cell` (so a change to the parameter re-renders it), with the
# caret pinned to the end of the text. WidgetText recurses a Document content
# through the Text domain, so caret navigation and editing originate in
# TextToGraphics; the edit operation is converted back to the parameter by the
# reader. Pinning the caret to the end keeps append/backspace correct without a
# persistent cursor stored in the (projection-output) control bar.
function _editable_text_control(p::ObjectToWidget, cell::Cell)
    ts = TextString("", p.style)
    set_cell_function!(getfield(ts, :content), () -> _as_string(cell[]))
    tt = TextBlock(ts)
    set_cell_function!(getfield(tt, :selection), () -> _end_cursor(length(_as_string(cell[]))))
    WidgetText(Point2D(0, 0), tt)
end

_as_string(v) = v isa AbstractString ? String(v) : (v === nothing ? "" : string(v))

# `elements[1].content{n}` — a zero-width caret at char offset n.
_end_cursor(n::Int) = ConcreteReference(FieldReferenceStep("elements"),
    ConcreteReference(RangeReferenceStep(0, 1),
        ConcreteReference(FieldReferenceStep("content"),
            ConcreteReference(RangeReferenceStep(n, n), EmptyReference()))))

# ── read_intent ───────────────────────────────────────────────────────
# Two control-edit shapes are converted to the input domain (a
# ReplaceReferencedValueOperation that sets the parameter cell):
#
# - A checkbox click arrives as ReplaceReferencedValueOperation rooted at the control
#   widget (identity); redirect it to the bound field at its full path — works at
#   any nesting depth.
# - A text edit arrives as a ReplaceStringRangeOperation whose reference is rooted
#   at this projection's output (`…children[row]…content…`); identify the
#   *top-level* field from the grid row, apply the character-range edit, and emit
#   the new whole value. Nested text-caret edits are deferred to the navigation
#   stage and pass through.

function read_intent(p::ObjectToWidget, iomap::ObjectToWidgetIoMap, op::ReplaceReferencedValueOperation)
    for (control, path) in iomap.controls
        op.document === control || continue
        current = evaluate_reference(iomap.input, path)
        value = _coerce(current, op.value)
        return ReplaceReferencedValueOperation(iomap.input, path, value)
    end
    op   # not one of ours — pass through
end

function read_intent(p::ObjectToWidget, iomap::ObjectToWidgetIoMap, op::ReplaceStringRangeOperation)
    parsed = _parse_control_edit(op.reference)
    parsed === nothing && return op
    row, cstart, cstop = parsed
    fields = _displayable_fields(p, iomap.input, EmptyReference())
    (1 <= row <= length(fields)) || return op
    nm = fields[row]
    f = getfield(iomap.input, nm)
    # Only a top-level, cell-backed string/number field is caret-editable here. If
    # the parsed row is a nested card / read-only column, leave the op untouched.
    (f isa Cell && _value_kind(f[]) in (:string, :real)) || return op
    path = ConcreteReference(FieldReferenceStep(String(nm)), EmptyReference())
    current = _as_string(f[])
    newval = _coerce(f[], _apply_range(current, cstart, cstop, op.replacement))
    ReplaceReferencedValueOperation(iomap.input, path, newval)
end

# A click on a control arrives as a ReplaceSelectionOperation rooted at the widget
# output. The control caret is a derived view (pinned to the text end), so there is
# no object-domain selection to set; consume it rather than letting it reach the
# object (which has no widget-shaped reference path).
read_intent(::ObjectToWidget, ::ObjectToWidgetIoMap, ::ReplaceSelectionOperation) = nothing

# Everything else (including ToggleCollapseOperation, whose target is the output
# card itself) passes straight through to the editor.
read_intent(::ObjectToWidget, ::ObjectToWidgetIoMap, op) = op

# Parse a control text-edit reference. The output is a WidgetComposite wrapping the
# root grid, so a renderer-produced reference looks like
# `elements[0].children[flat].content.elements[1].content[cstart:cstop]` — the grid
# child index follows the *first* `children` field. (A reference passed already
# rooted at the grid, with no composite `elements` prefix, also works.) The grid
# holds `[label, control]` per row, so the control for 1-based row r is child
# `2r-1` (0-based) → `row = (flat + 1) ÷ 2`. The terminal RangeReferenceStep is the
# character range.
function _parse_control_edit(ref)
    flat = nothing
    term = nothing
    after_children = false
    cur = ref
    while cur isa ConcreteReference
        h = cur.head
        if h isa FieldReferenceStep && h.name == "children"
            after_children = true
        elseif h isa RangeReferenceStep
            after_children && flat === nothing && (flat = h.start)
            term = h
        end
        cur = cur.tail
    end
    (flat === nothing || term === nothing) && return nothing
    row = (flat + 1) ÷ 2
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
# Caret/selection navigation into the object tree is deferred to a later stage; the
# control subtree does not map into the projected object's reference space (v1),
# mirroring ConversationToWidget.

map_reference_forward(::ObjectToWidget, ::ObjectToWidgetIoMap, reference) = nothing
map_reference_backward(::ObjectToWidget, ::ObjectToWidgetIoMap, reference) = nothing

end # module
