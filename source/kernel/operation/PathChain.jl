# Fragment of `OperationModule` — the chain of a kind of path: the path written at
# the root of a document, and each document on it holding its own tail.

"""
    replace_path_chain!(document, field::Symbol, path) -> document

Write `path` into the field `field` of `document`, and its tail into each
document on it: the document at the end holds the empty path, and a document
that was on the old path and is not on the new one holds `nothing`. `nothing`
clears the chain. A cell is written only when its value changes, so writing the
path that is there writes no cell, and a reader of a document whose part of the
path stays the same is not woken. The path is kept without its types: a kind of
path other than the selection is compared, not replayed.

The selection keeps its own chain (`replace_selection!`), with its dormant
state; this is the chain of every other kind, such as the mouse target.
"""
function replace_path_chain!(document, field::Symbol, path)
    hasfield(typeof(document), field) || return document
    path = path === nothing ? nothing : strip_reference_types(path)
    cell = getfield(document, field)
    old = cell[]
    old == path || (cell[] = path)
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
