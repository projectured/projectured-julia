# Fragment of `OperationModule` — the operations, the splice helpers, the traversal seam.

"""
    DoNothingOperation()

An operation that does nothing when applied. Its purpose is to *consume* a
gesture without effecting a change: a reader (or a per-instance gesture binding)
returns `DoNothingOperation()` to say "this gesture is handled — stop looking",
distinct from returning `nothing`, which means "declined, keep looking / fall
through". The canonical way to **suppress** a default behavior is to map the
gesture pattern to a `DoNothingOperation()`.
"""
struct DoNothingOperation <: Operation end

evaluate_operation(editor, ::DoNothingOperation) = nothing

"""
    InvalidateProjectionOperation()

An operation that makes the editor print its view again from the start. Its
evaluation calls `invalidate_projection!(editor)`: the editor drops its IO map,
the frame reads no more events, and the next print builds the view anew.

A projection that reads a value with no dependency edge, such as a value of a
theme, adds it to each answer that changes that value, so the view follows the
change. It changes no document, so its inverse is `DoNothingOperation()`.
"""
struct InvalidateProjectionOperation <: Operation end

evaluate_operation(editor, ::InvalidateProjectionOperation) = invalidate_projection!(editor)

# ── Text-splice helpers ─────────────────────────────────────────────────────

"""
    splice_string(old, s, e, replacement) -> String

Replace the characters of `old` between 0-based boundaries `[s, e]` with
`replacement`. Character-aware, so multi-byte characters survive intact.
Boundaries are clamped: `s <= 0` keeps nothing on the left, `e >= length(old)`
keeps nothing on the right. This is the one canonical text splice — every
text-replace edit in every domain routes through it.
"""
function splice_string(old::AbstractString, s::Int, e::Int,
                       replacement::AbstractString)
    n = length(old)
    left  = s <= 0 ? "" : first(old, s)
    right = e >= n ? "" : last(old, n - e)
    String(left) * replacement * String(right)
end

"""
    splice_number(old_str, s, e, replacement) -> Union{Int, Float64, Nothing}

Splice the textual form of a number between 0-based boundaries `[s, e]`, then
parse the result back to a number. An integral result parses to `Int`; a result
with a fractional part or exponent parses to `Float64` — so editing `4` into `42`
stays the integer `42` rather than drifting to `42.0`. Returns `nothing` for an
empty result or unparseable input (the value cell tolerates `nothing` as the empty
sentinel).
"""
function splice_number(old_str::AbstractString, s::Int, e::Int,
                       replacement::AbstractString)
    new_str = splice_string(old_str, s, e, replacement)
    isempty(new_str) && return nothing
    something(tryparse(Int, new_str), tryparse(Float64, new_str), Some(nothing))
end

splice_value!(owner, field::Symbol, value::AbstractString, s::Int, e::Int,
              replacement::AbstractString) =
    setproperty!(owner, field, splice_string(value, s, e, replacement))

splice_value!(owner, field::Symbol, ::Nothing, s::Int, e::Int,
              replacement::AbstractString) =
    setproperty!(owner, field, splice_string("", s, e, replacement))

splice_value!(owner, field::Symbol, value::Number, s::Int, e::Int,
              replacement::AbstractString) =
    setproperty!(owner, field, splice_number(string(value), s, e, replacement))

"""
    QuitEditorException()

The exception that `evaluate_operation` throws for a `QuitEditorOperation`. It is
a request to stop the editor, not a fault: `is_passthrough_exception` answers
`true` for it, so no fault barrier catches it.
"""
struct QuitEditorException <: Exception end

# A request to quit is not a fault and no barrier may catch it: catching one
# turns a clean stop into a loop that will not end.
FaultModule.is_passthrough_exception(::QuitEditorException) = true

"""
    CompoundOperation(operations)

Apply a sequence of operations in order, as a single editor step. A reader
returns one `CompoundOperation` and `evaluate_operation` runs each member
operation against the same editor in turn — for an intent that is naturally
several writes at once (e.g. a cut that both saves the selected value and clears
the slot it came from).
"""
struct CompoundOperation <: Operation
    operations::Vector{Any}
end

CompoundOperation(operations...) = CompoundOperation(Vector{Any}(collect(operations)))
# One member: without this method the call reaches the field constructor, which
# converts the operation to a vector and fails.
CompoundOperation(operation::Operation) = CompoundOperation(Any[operation])

function evaluate_operation(editor, op::CompoundOperation)
    for member in op.operations
        evaluate_operation(editor, member)
    end
end

"""
    QuitEditorOperation()

Operation that asks the editor to stop. `evaluate_operation` throws a
`QuitEditorException`, and the code that runs the editor catches it and stops.
"""
struct QuitEditorOperation <: Operation end

function evaluate_operation(editor, op::QuitEditorOperation)
    throw(QuitEditorException())
end

"""
    SetTimerOperation(name::Symbol, time)

Set the timer `name` of the editor to `time`, in seconds on the clock of `time()`.
When that time comes, the loop of the editor reads a `TimerExpire(name, time)`.
A timer set again under the same name replaces the one before; a timer under
another name is another timer.

A reader answers it to find a pattern that ends when no event arrives: it sets
the timer on each event that starts the wait, and it checks its own state when
the `TimerExpire` comes. It edits no document, so a history does not record it,
and it names no reference, so every reader passes it up unchanged. The editor
evaluates it; an evaluator that is not an editor does nothing with it.
"""
struct SetTimerOperation <: Operation
    name::Symbol
    time::Float64
end


"""
    ReplaceSelectionOperation(path)

Operation that replaces the current selection with `path`.

Click-versus-keyboard disambiguation does **not** ride on this operation: a
reader that wants different behaviour on click keys it off the originating
gesture, not off a flag added here.
"""
struct ReplaceSelectionOperation <: ReplacePathOperation
    path::Reference
end

function evaluate_operation(editor, op::ReplaceSelectionOperation)
    replace_selection!(editor.document, op.path)
end

get_operation_path(operation::ReplacePathOperation) = operation.path
make_path_operation(::ReplaceSelectionOperation, path::Reference) = ReplaceSelectionOperation(path)

"""
    ReplaceMouseTargetOperation(path)

Operation that replaces the part under the pointer with `path`: the document at
the root holds `path`, and each document on it holds its own tail
([`replace_mouse_target!`](@ref)). A move of the pointer answers it as a press
answers `ReplaceSelectionOperation`. It is view state, so a history does not
record it.
"""
struct ReplaceMouseTargetOperation <: ReplacePathOperation
    path::Reference
end

make_path_operation(::ReplaceMouseTargetOperation, path::Reference) = ReplaceMouseTargetOperation(path)

evaluate_operation(editor, op::ReplaceMouseTargetOperation) =
    replace_mouse_target!(editor.document, op.path)

"""
    StartDragOperation(path, dragged)

Operation that starts a drag of the part at `path`. The code that tracks a drag
keeps the path, and while the drag is on, it sends that part each `DragMove`, the
`DragEnd` and a `DragCancel` by the path, wherever the pointer is. The part keeps
its own state of the drag. `dragged` is the thing that a global drag carries to
the part that takes it, and `nothing` for a local drag, such as the thumb of a
slider. A part answers it from its own place with the empty path; each container
puts its steps before the path, and each projection maps it backward, as for
`ReplaceMouseTargetOperation`. With no code that tracks a drag, it does nothing.
"""
struct StartDragOperation <: ReplacePathOperation
    path::Reference
    dragged::Any
end

make_path_operation(operation::StartDragOperation, path::Reference) =
    StartDragOperation(path, operation.dragged)

evaluate_operation(editor, ::StartDragOperation) = nothing

"""
    find_drop_zone(document, dragged, point) -> zone or nothing

Where `document` takes `dragged`, the thing that a global drag carries, with the
pointer at `point`: the zone of the drop, or `nothing` when `document` does not
take it. The part that keeps a global drag asks it at each move and at the
release, and draws its preview from the zone; `point` is the point of the pointer
as that part knows it. A document type that takes a dropped thing adds a method.
"""
find_drop_zone(document, dragged, point) = nothing

# Split a non-empty path into (everything-but-last-step, last-step). The prefix is
# rebuilt as a plain skeleton (callers pass an already type-stripped path).
function _split_terminal_step(path::ConcreteReference)
    steps = get_reference_steps(path)
    (Reference(steps[1:end-1]...), steps[end])
end

# Write `value` into the slot `step` selects on `parent`: a field step names a
# `Cell`-backed field; a range step selects and overwrites an element of a
# sequence container (an element collection). Each method takes both layouts of its
# step family. Terminal-kind dispatch is what lets `ReplaceReferencedValueOperation`
# write either a document or a scalar through one path.
function _write_slot!(parent, step::AFieldReferenceStep, value)
    f = getfield(parent, Symbol(step.name))
    f isa AbstractCell ||
        error("ReplaceReferencedValueOperation: field $(step.name) of " *
              "$(typeof(parent)) is not a Cell")
    f[] = value
end

# The value that the slot admits for `value`, made by the seam of the declared
# types (`convert_written_value`). A field takes the declared type of the field,
# and an element takes the element type of its collection. The domain of an
# element is the domain of the nearest document above the collection.
function _convert_slot_value(root, parent_path, parent, step::AFieldReferenceStep, value)
    parent isa Document || return value
    name = Symbol(step.name)
    declared_type = find_declared_field_type(typeof(parent), name)
    declared_type === nothing && return value
    convert_written_value(parent, declared_type, value; name)
end

function _convert_slot_value(root, parent_path, parent, step::ARangeReferenceStep, value)
    declared_type = find_declared_element_type(parent)
    declared_type === nothing && return value
    owner = _find_owner_document(root, parent_path)
    name = sprint(show, step)
    convert_one(item) = convert_written_value(owner, declared_type, item; name)
    # A vector of items is a splice, as in `_write_slot!`, and each item is one element.
    value isa AbstractVector ? map(convert_one, value) : convert_one(value)
end

# The nearest document at or above the end of `parent_path` that is not an element
# collection: the document whose domain owns an element of the collection there.
function _find_owner_document(root, parent_path)
    owner = root
    steps = parent_path isa EmptyReference ? () : get_reference_steps(parent_path)
    for i in eachindex(steps)
        node = evaluate_reference(root, Reference(steps[1:i]...))
        (node isa Document && !is_element_collection(node)) && (owner = node)
    end
    owner
end

# A field step on a dictionary names a key, and the operation writes no key.
_write_slot!(parent::AbstractDict, step::AFieldReferenceStep, value) =
    error("ReplaceReferencedValueOperation: $(step.name) is a key of a " *
          "$(typeof(parent)), and the operation writes no key")

# One value overwrites one element. A range of more than one element takes a
# vector of items, which is a splice.
function _write_slot!(parent, step::ARangeReferenceStep, value)
    step.stop - step.start > 1 &&
        error("ReplaceReferencedValueOperation: the range " *
              "[$(step.start), $(step.stop)) holds more than one element; " *
              "give a vector of items to replace it")
    parent[step.start + 1] = value
end

# A terminal `RangeReferenceStep` whose value is a *vector* of items is a SPLICE:
# replace the half-open element range `[start, stop)` of the sequence container
# with `items`. Each item goes in as it is, and the container keeps it in the form
# that it stores, in a cell of its own or as the value. Zero-width range ⇒ pure
# insert; empty items ⇒ pure delete; both ⇒ element replacement. A single
# (non-vector) value instead hits the element-overwrite method above.
function _write_slot!(parent, step::ARangeReferenceStep, items::AbstractVector)
    for _ in 1:(step.stop - step.start)
        deleteat!(parent, step.start + 1)
    end
    for (k, item) in enumerate(items)
        insert!(parent, step.start + k, item)
    end
end

# ── A slot of a plain value ───────────────────────────────────────────────
#
# A field of a struct that is no document holds its value with no cell. Such a
# slot is written from the nearest cell above it on the path. A mutable struct
# changes in place, and that cell is written again with what it holds, so each
# reader of it reads again. An immutable struct, or a tuple, is copied with the
# one slot changed, and the copy is written into the slot one level up, until a
# slot that a cell holds takes it. With no cell above a field, nothing can take
# the write or tell a reader of it, so the write throws. An element of a plain
# container, such as a `Vector`, changes in place, and the nearest cell above it,
# if any, is written again.

# A field of a struct that holds its value with no cell. A document and a
# dictionary keep the rules of `_write_slot!`.
function _is_plain_field_slot(parent, step)
    step isa AFieldReferenceStep || return false
    (parent isa Document || parent isa AbstractDict) && return false
    name = Symbol(step.name)
    isstructtype(typeof(parent)) && hasfield(typeof(parent), name) &&
        !(getfield(parent, name) isa AbstractCell)
end

# A container that is no document and has no rules of its own for its elements,
# such as a `Vector`. A collection that declares `is_element_collection` keeps its
# elements in its own way and is no plain container.
_is_plain_container(parent) = !(parent isa Document) && !is_element_collection(parent)

# A slot of a plain value: a plain field, an element of a tuple, or an element of a
# plain container.
_is_plain_slot(parent, step::AFieldReferenceStep) = _is_plain_field_slot(parent, step)
_is_plain_slot(parent, step::ARangeReferenceStep) =
    parent isa Tuple || _is_plain_container(parent)
_is_plain_slot(parent, step) = false

# A slot that can not change in place: a plain field of an immutable struct, or an
# element of a tuple.
_is_plain_immutable_slot(parent, step) =
    (_is_plain_field_slot(parent, step) && !ismutable(parent)) ||
    (parent isa Tuple && step isa ARangeReferenceStep)

_make_written_copy(parent, step::AFieldReferenceStep, value) =
    with_object_field(parent, Symbol(step.name), value)

function _make_written_copy(parent::Tuple, step::ARangeReferenceStep, value)
    step.stop - step.start == 1 ||
        error("ReplaceReferencedValueOperation: a tuple takes one element at a time")
    Base.setindex(parent, value, step.start + 1)
end

function _write_plain_field!(parent, step::AFieldReferenceStep, value)
    name = Symbol(step.name)
    setfield!(parent, name, convert(fieldtype(typeof(parent), name), value))
end

# The cell that `step` selects on `node`, or `nothing` when that slot holds no cell.
function _find_cell_slot(node, step::AFieldReferenceStep)
    node isa AbstractDict && return nothing
    name = Symbol(step.name)
    hasfield(typeof(node), name) || return nothing
    slot = getfield(node, name)
    slot isa AbstractCell ? slot : nothing
end

function _find_cell_slot(node, step::ARangeReferenceStep)
    is_position_reference_step(step) && return nothing
    slot = get_slot_at(node, step.start + 1)
    slot isa AbstractCell ? slot : nothing
end

_find_cell_slot(node, step) = nothing

# The nearest cell above the last step of `reference`, walked from `root`, or
# `nothing` when no cell is above it. `holder` is the node whose slot the cell is,
# or the cell itself when it is the root. `reference` is the path from `holder` to
# the slot of the last step, so an operation that carries `holder` reaches it.
function _find_cell_anchor(root, reference::ConcreteReference)
    steps = get_reference_steps(reference)
    anchor = root isa AbstractCell ? (holder = root, cell = root, first = 1) : nothing
    node = unwrap_cell(root)
    for k in 1:(length(steps) - 1)
        cell = _find_cell_slot(node, steps[k])
        cell === nothing || (anchor = (holder = node, cell = cell, first = k))
        node = evaluate_reference_step(steps[k], node)
    end
    anchor === nothing && return nothing
    (holder = anchor.holder, cell = anchor.cell,
     reference = Reference(steps[anchor.first:end]...))
end

# Write a cell with the value that it holds, so each reader of it reads again. A
# computed cell keeps its computation, which a write would end.
function _touch_cell!(cell)
    is_computed_cell(cell) && return nothing
    cell[] = cell[]
    nothing
end

_format_no_cell_message(parent) =
    "ReplaceReferencedValueOperation: the $(typeof(parent)) on this path is a " *
    "plain value, and no cell above it holds it, so nothing can take the write " *
    "or tell a reader of it. Hold the value in a Cell, and give the cell as the " *
    "root of the operation"

# Write `value` at the non-empty `reference` from `root`, which can be a cell that
# holds the value.
function _write_reference!(root, reference::ConcreteReference, value)
    parent_path, terminal = _split_terminal_step(reference)
    top = unwrap_cell(root)
    parent = parent_path isa EmptyReference ? top : evaluate_reference(top, parent_path)
    if _is_plain_immutable_slot(parent, terminal)
        copy = _make_written_copy(parent, terminal, value)
        parent_path isa EmptyReference || return _write_reference!(root, parent_path, copy)
        root isa AbstractCell || error(_format_no_cell_message(parent))
        root[] = copy
        return nothing
    end
    if _is_plain_field_slot(parent, terminal)
        anchor = _find_cell_anchor(root, reference)
        anchor === nothing && error(_format_no_cell_message(parent))
        _write_plain_field!(parent, terminal, value)
        _touch_cell!(anchor.cell)
        return nothing
    end
    value = _convert_slot_value(top, parent_path, parent, terminal, value)
    # The mouse target that passes through the slot follows the write.
    written = _find_written_chain(parent, terminal, value)
    _write_slot!(parent, terminal, value)
    written === nothing || _follow_written_chain!(parent, written; root = top, parent_path)
    # A plain container changed in place, so the cell above it tells its readers.
    if terminal isa ARangeReferenceStep && _is_plain_container(parent)
        anchor = _find_cell_anchor(root, reference)
        anchor === nothing || _touch_cell!(anchor.cell)
    end
    nothing
end

"""
    ReplaceReferencedValueOperation(document, reference, value)

Set the scalar `value` at `reference` (a `Reference`) resolved against a root
selected by the `document` field:

- **`document !== nothing`** — the root is the carried object, so this works on
  objects that do not live in the document tree (a widget, or a projection's own
  reactive parameter `Cell`s). The operation is *self-contained* and bubbles up
  the reader chain unchanged.
- **`document === nothing`** — the root is `editor.document` and `reference` is
  rooted there, so container/generic projections reroot the reference as the
  operation flows up (see `reroot_operation`). An empty `reference` then means a
  **whole-root swap**: rebind `editor.document` and drop the cached iomap.
- **`document` is a cell** — the cell holds the root: `reference` starts at the
  value that the cell holds, and an empty `reference` writes the cell.

A slot of a plain value, a field that a struct holds with no cell, is written
from the nearest cell above it on the path. A field of a mutable struct changes
in place, and that cell is written again with what it holds, so each reader of
it reads again. A field of an immutable struct, or an element of a tuple, is
written by a copy ([`with_object_field`](@ref)) that goes into the slot one level
up. With no cell above such a slot, the write throws. An element of a plain
vector changes in place, and the nearest cell above it, if any, is written
again in the same way.

The write keeps the mouse target right where it passes through the slot: the
document of the slot holds the path of the slot that its child holds after the
write, a splice moving a path into a later element, and a child that the write
takes from the slot holds no mouse target. So an edit, an undo and a redo leave
one part lit, and the move after the frame finds the part under the pointer. An
edit made in any other way, such as a write into a cell, keeps no such path.
"""
struct ReplaceReferencedValueOperation <: Operation
    document::Any
    reference::Reference
    value::Any
end

"""
    ReplaceViewStateOperation(operation)

`operation`, marked as a write of view state: what the pointer is over, what it
holds down, what a drag carries. Applying it applies `operation`.

**A history does not record it**, because a hover or a held button is not an edit:
Ctrl+Z after a hover must take back the edit before it. The reader that writes
the state marks it, because only that reader knows the field is the pointer's and
not the document's.
"""
struct ReplaceViewStateOperation <: WrappingOperation
    operation::Any
end

get_wrapped_operation(operation::ReplaceViewStateOperation) = operation.operation
rewrap_operation(::ReplaceViewStateOperation, inner) = ReplaceViewStateOperation(inner)
evaluate_operation(editor, operation::ReplaceViewStateOperation) =
    evaluate_operation(editor, operation.operation)

# Convenience for the common single-field write on a carried root:
# `ReplaceReferencedValueOperation(obj, "field", v)` writes `obj.field = v`. Dispatches by
# the second argument's type (`AbstractString` vs `Reference`), so it never
# collides with the field-by-field constructor above.
ReplaceReferencedValueOperation(document, field::AbstractString, value) =
    ReplaceReferencedValueOperation(document, Reference(FieldReferenceStep(field)), value)

function evaluate_operation(editor, op::ReplaceReferencedValueOperation)
    reference = strip_reference_types(op.reference)
    # `document === nothing` ⇒ the reference is rooted at `editor.document`;
    # otherwise the operation carries its own root object (a widget, a projection
    # parameter `Cell`, a cell that holds a plain value).
    root = op.document === nothing ? editor.document : op.document
    if reference isa EmptyReference
        # A carried cell holds its root, so the empty path names the cell itself.
        if op.document isa AbstractCell
            op.document[] = op.value
            return
        end
        # Whole-root swap: only meaningful when the root *is* `editor.document`
        # (there is no in-place "replace the object itself" for a carried root).
        # Rebind and ask the editor to drop its cached projection so the next print
        # rebuilds on the new root — a wholesale swap is not reactive (nested swaps
        # write into Cells). `invalidate_projection!` is the editor's own concern
        # (default no-op); this module does not know how the projection is cached.
        op.document === nothing ||
            error("ReplaceReferencedValueOperation: empty reference on a carried " *
                  "root has no slot to write")
        editor.document = op.value
        invalidate_projection!(editor)
        return
    end
    _write_reference!(root, reference, op.value)
end

"""
    make_replace_document_operation(path, document) -> CompoundOperation

Replace the document at `path` (rooted at `editor.document`) with `document`, then
move the editor selection to `path ⧺ document.selection` so the cursor lands inside
the freshly-created value. The structural analogue of the primitive replace-range
edits: a type-to-replace or paste gesture that swaps a whole sub-document produces
one. A value with no `selection` field, such as a step of a path, is selected
whole: the selection moves to `path`.

Builds a `ReplaceReferencedValueOperation(nothing, path, document)` write paired
with a trailing `ReplaceSelectionOperation`, bundled in a `CompoundOperation` so
re-rooting prepends the same steps to both as the operation bubbles up. An empty
`path` is a whole-root swap (the `ReplaceReferencedValueOperation` rebinds
`editor.document` and drops the iomap).
"""
function make_replace_document_operation(path::Reference, document)
    # Only a live selection moves with the document. A dormant one belongs to a
    # place the document was shown before, and the write starts it afresh.
    inner_sel = hasfield(typeof(document), :selection) ?
                unwrap_selection(getfield(document, :selection)[]) : nothing
    inner_sel === nothing && (inner_sel = EmptyReference())
    CompoundOperation(Any[
        ReplaceReferencedValueOperation(nothing, path, document),
        ReplaceSelectionOperation(
            concat_references(strip_reference_types(path), inner_sel)),
    ])
end

"""
    make_insert_elements_operation(path, index, items; selection=nothing, root=nothing)
        -> operation

Insert each of `items` into the sequence container at `path` (an element
collection), so that the first new element is the element at the 1-based `index`;
`length + 1` appends. Expressed as a splice — a `ReplaceReferencedValueOperation`
whose terminal step is the **zero-width** boundary `RangeReferenceStep(index - 1,
index - 1)` and whose value is the item vector. When `selection` is non-`nothing`, a
trailing `ReplaceSelectionOperation` is appended in a `CompoundOperation` to drop
the cursor into the new element (re-rooting prepends the same steps to both
members).

`root` defaults to `nothing` (rooted at `editor.document`); pass a carried object
for an identity-rooted splice against a document that is not in the tree.
"""
function make_insert_elements_operation(path::Reference, index::Integer, items;
                                        selection=nothing, root=nothing)
    boundary = index - 1
    write = ReplaceReferencedValueOperation(root,
        extend_reference(path, RangeReferenceStep(boundary, boundary)),
        Vector{Any}(items))
    selection === nothing ? write :
        CompoundOperation(Any[write, ReplaceSelectionOperation(selection)])
end

"""
    make_delete_elements_operation(path, index; count=1, root=nothing) -> operation

Remove `count` elements from the sequence container at `path`, starting at the
element at the 1-based `index`. Expressed as a splice — a
`ReplaceReferencedValueOperation` whose terminal step is the range
`RangeReferenceStep(index - 1, index - 1 + count)` and whose value is the empty
vector (replace the range with nothing). The inverse of
`make_insert_elements_operation`.
"""
make_delete_elements_operation(path::Reference, index::Integer; count::Integer=1,
                               root=nothing) =
    ReplaceReferencedValueOperation(root,
        extend_reference(path, RangeReferenceStep(index - 1, index - 1 + count)), Any[])

"""
    SelectNextInsertionOperation(predicate[, cursor])

Move the selection to the next hole (a Document for which `predicate` holds) after
the currently-selected node, in document pre-order, and place the cursor at that
hole's `cursor` suffix (default whole-element). Clamps at the last hole. A domain
gesture supplies `predicate` and `cursor`, keeping the operation domain-agnostic.

Carries no reference of its own, so it bubbles up the reader chain unchanged and
needs no `reroot_operation` method.
"""
struct SelectNextInsertionOperation <: Operation
    predicate::Any        # (node::Document) -> Bool ; true marks a hole to land on
    cursor::Reference # suffix appended to the found hole's path (e.g. value{0})
end

SelectNextInsertionOperation(predicate) =
    SelectNextInsertionOperation(predicate, EmptyReference())

function evaluate_operation(editor, op::SelectNextInsertionOperation)
    root = editor.document
    root isa Document || return
    nodes = Tuple{Reference,Any}[]
    _preorder_documents!(root, EmptyReference(), Base.IdSet{Any}(), nodes)
    owner = _selection_owner_node(root, getfield(root, :selection)[])
    cur = 0
    if owner !== nothing
        for (i, (_, nd)) in enumerate(nodes)
            nd === owner && (cur = i; break)
        end
    end
    for j in (cur + 1):length(nodes)
        if op.predicate(nodes[j][2])
            replace_selection!(root, concat_references(nodes[j][1], op.cursor))
            return
        end
    end
    return
end

function child_reference_steps(node)
    pairs = Tuple{Any, Any}[]
    for nm in fieldnames(typeof(node))
        is_view_state_field(nm) && continue
        val = unwrap_cell(getfield(node, nm))
        val isa Document || continue
        push!(pairs, (FieldReferenceStep(string(nm)), val))
    end
    pairs
end

# Pre-order Document walk building set_selection!-compatible paths. Skips
# `selection` and guards cycles/shared substructure by identity.
function _preorder_documents!(node, path::Reference, seen, out)
    node isa Document || return
    node in seen && return
    push!(seen, node)
    push!(out, (path, node))
    for (step, child) in child_reference_steps(node)
        _preorder_documents!(child, extend_reference(path, step), seen, out)
    end
    return
end

# The deepest Document a selection anchors at: strip type checkpoints, then drop
# trailing steps until the path resolves to a Document (a `value{k}` char cursor
# resolves to a String, so it is dropped to reach the owning leaf). Empty ⇒ root.
function _selection_owner_node(root, sel)
    sel === nothing && return nothing
    p = strip_reference_types(sel)
    while true
        v = try_evaluate_reference(root, p)
        v isa Document && return v
        p isa EmptyReference && return root
        (p, _) = _split_terminal_step(p)
    end
end

"""
    ToggleCollapseOperation([target])

Operation that flips the `collapsed` field of a single collapsible node.

`target` is the node whose `collapsed` cell should be toggled, or `nothing`.
A `nothing` target is resolved by whichever projection owns the collapse state to
the **innermost** collapsible node containing the current selection, before the
operation propagates back up — so `evaluate_operation` only ever sees a concrete
`target` (a click that already knows the node it hit supplies one directly).

The operation only affects *rendering*: the source document is untouched, so a
selection that pointed inside the just-collapsed subtree simply stops drawing a
cursor until the node is expanded again.
"""
struct ToggleCollapseOperation <: Operation
    target::Any
end

ToggleCollapseOperation() = ToggleCollapseOperation(nothing)

function evaluate_operation(editor, op::ToggleCollapseOperation)
    target = op.target
    target === nothing && return
    target.collapsed = !target.collapsed
end

# Window operations are not here: an operation whose vocabulary belongs to a
# single domain is declared with that domain's own document, and only
# cross-domain operations live in this layer.
