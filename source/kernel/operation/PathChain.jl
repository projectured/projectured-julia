# Fragment of `OperationModule` — the chain of a kind of path: the path written at
# the root of a document, and each document on it holding its own tail.

"""
    replace_path_chain!(document, field::Symbol, path) -> document

Write `path` into the field `field` of `document`, and its tail into each
document on it: the document at the end holds the empty path, and a document
that was on the old path and is not on the new one holds `nothing`. `nothing`
clears the chain. A cell is written only when its value changes, so writing the
path that is there writes no cell, and a reader of a document whose part of the
path stays the same is not woken. Each document holds its path with the types
that the document gives it (`annotate_reference_types`), because a forward map
builds a typed `@reference` from it; two paths are compared without their types.

The selection keeps its own chain (`replace_selection!`), with its dormant
state; this is the chain of every other kind, such as the mouse target.
"""
function replace_path_chain!(document, field::Symbol, path)
    hasfield(typeof(document), field) || return document
    path = strip_reference_types(path)
    cell = getfield(document, field)
    old = strip_reference_types(cell[])
    old == path || (cell[] = path === nothing ? nothing : annotate_reference_types(document, path))
    old_child = _find_path_child(document, old)
    new_child = _find_path_child(document, path)
    old_child === nothing || old_child === new_child || _clear_path_chain!(old_child, field)
    new_child === nothing || replace_path_chain!(new_child, field, get_reference_tail(path))
    document
end

"""
    replace_mouse_target!(document, path) -> document

Write the path of the part under the pointer into `document` and each document
on it, as [`replace_path_chain!`](@ref) writes a kind of path. It is what
`ReplaceMouseTargetOperation` does at the root of the editor.
"""
replace_mouse_target!(document, path) = replace_path_chain!(document, :mouse_target, path)

"""
    get_mouse_target(document) -> Reference or nothing

The mouse target of `document` without its types: the path of the part under the
pointer, which a container reads to find the child that the pointer leaves.
`nothing` when the pointer is not in the document, or the document has no mouse
target.
"""
function get_mouse_target(document)
    hasfield(typeof(document), :mouse_target) || return nothing
    target = getfield(document, :mouse_target)[]
    target isa Reference ? strip_reference_types(target) : nothing
end

"""
    add_mouse_target(answer, path = EmptyReference()) -> operation

`answer`, joined with `ReplaceMouseTargetOperation(path)` when it names no part
under the pointer. `path` is the part of the document that gave `answer` to a move
with no button held; the empty path is that document itself.
"""
add_mouse_target(answer, path::Reference = EmptyReference()) =
    has_mouse_target(answer) ? answer : join_move_answers(answer, ReplaceMouseTargetOperation(path))

"""
    has_mouse_target(answer) -> Bool

Whether `answer`, the answer to a move, names the part under the pointer: it is or
holds a `ReplaceMouseTargetOperation`.
"""
has_mouse_target(::Any) = false
has_mouse_target(::ReplaceMouseTargetOperation) = true
has_mouse_target(operation::CompoundOperation) = any(has_mouse_target, operation.operations)
has_mouse_target(operation::WrappingOperation) = has_mouse_target(get_wrapped_operation(operation))

"""
    join_move_answers(answers...) -> operation or nothing

The answers of the parts that a move reached, in order, as one operation: the part
that the pointer leaves first, then the part that it is on. `nothing` when no part
answered.
"""
function join_move_answers(answers...)
    kept = Any[answer for answer in answers if answer !== nothing]
    isempty(kept) ? nothing : length(kept) == 1 ? kept[1] : CompoundOperation(kept)
end

# The document that the first step of `path` reaches from `document`, or `nothing`
# when it reaches none: a step into a field or an element of a collection that
# holds a document.
function _find_path_child(document, path)
    path isa ConcreteReference || return nothing
    child = try
        unwrap_cell(evaluate_reference_step(get_reference_head(path), document))
    catch
        return nothing
    end
    child isa Document ? child : nothing
end

# Clear the path of `document` and of each document on it.
function _clear_path_chain!(document, field::Symbol)
    hasfield(typeof(document), field) || return
    cell = getfield(document, field)
    old = cell[]
    old === nothing && return
    cell[] = nothing
    child = _find_path_child(document, old)
    child === nothing || _clear_path_chain!(child, field)
end

# ── A write under a chain ────────────────────────────────────────────────────
# A write that replaces the slot of a document, or that splices a range of its
# elements, changes what a path through that document names. So the write keeps
# the chain right where it passes: the document holds the path of the slot that
# its child holds after the write, a slot after a splice moving with it, and a
# child that the write takes from the slot holds no path. That child can still be
# shown at another place, and the move that follows the frame finds it there.

# The chain of `field` through `parent` as a write of `value` at its slot
# `terminal` meets it: the path that `parent` holds, that path after the write,
# and the document that the path reaches before the write; `nothing` when the
# path does not pass through the slot. A splice moves each element after it, so
# a range meets every path into an element.
function _find_written_chain(parent, terminal, value; field::Symbol = :mouse_target)
    (parent isa Document && hasfield(typeof(parent), field)) || return nothing
    cell = getfield(parent, field)
    cell isa AbstractCell || return nothing
    path = strip_reference_types(cell[])
    path isa ConcreteReference || return nothing
    _is_written_step(get_reference_head(path), terminal) || return nothing
    (field = field, path = path, moved = _move_spliced_path(path, terminal, value),
     child = _find_path_child(parent, path))
end

_is_written_step(step, terminal::AFieldReferenceStep) =
    step isa AFieldReferenceStep && step.name == terminal.name
_is_written_step(step, ::ARangeReferenceStep) =
    step isa ARangeReferenceStep && is_element_reference_step(step)
_is_written_step(step, terminal) = false

# The path into an element after a splice of `items` over the range `terminal`:
# an element after the range moves by the change in length.
function _move_spliced_path(path, terminal::ARangeReferenceStep, items::AbstractVector)
    k = get_reference_head(path).start + 1
    k > terminal.stop || return path
    k += length(items) - (terminal.stop - terminal.start)
    ConcreteReference(RangeReferenceStep(k - 1, k), get_reference_tail(path))
end
_move_spliced_path(path, terminal, value) = path

# Keep the chain that `_find_written_chain` met right after the write: `parent`
# and each document above it on `parent_path` from `root` hold the path after the
# write, the empty path in `parent` when its slot is gone, and the child that the
# write took from the slot holds none.
function _follow_written_chain!(parent, written; root, parent_path::Reference)
    path = _reaches_path_head(parent, written.moved) ? written.moved : EmptyReference()
    if path != written.path
        getfield(parent, written.field)[] = annotate_reference_types(parent, path)
        for (document, steps) in _find_documents_above(root, parent_path)
            hasfield(typeof(document), written.field) || continue
            cell = getfield(document, written.field)
            cell isa AbstractCell || continue
            above = Reference(steps...)
            strip_reference_types(cell[]) == concat_references(above, written.path) &&
                (cell[] = annotate_reference_types(document, concat_references(above, path)))
        end
    end
    child = _find_path_child(parent, path)
    written.child === nothing || written.child === child ||
        _clear_path_chain!(written.child, written.field)
    nothing
end

# Whether the first step of `path` reaches a value of `document`.
function _reaches_path_head(document, path)
    path isa ConcreteReference || return true
    try
        evaluate_reference_step(get_reference_head(path), document)
        true
    catch
        false
    end
end

# Each document on `path` from `root` before its end, with the steps from it to
# the end, for a document that holds a chain.
function _find_documents_above(root, path::Reference)
    steps = collect(get_reference_steps(path))
    found = Tuple{Any,Vector{Any}}[]
    node = root
    for (index, step) in enumerate(steps)
        node isa Document && push!(found, (node, steps[index:end]))
        node = try
            unwrap_cell(evaluate_reference_step(step, node))
        catch
            return found
        end
    end
    found
end
