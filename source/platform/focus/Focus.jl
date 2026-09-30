# Fragment of `FocusModule` — the walk that finds what a document can focus:
# which nodes are focusable, the child steps that reach them in document order,
# and the selection that a left button down on a focusable node makes.

is_focusable_document(node) = false

# `(steps::Tuple, child)` pairs for each child Document of `node`, in document
# order — a CellVector field yields one pair per element (`field[i]`), a single
# sub-document field yields one pair (`field`). `selection` and scalar/leaf fields
# are skipped.
function _child_document_refs(node)
    refs = Tuple{Tuple,Any}[]
    if node isa CellVector
        for i in 1:length(node)
            push!(refs, ((RangeReferenceStep(i - 1, i),), node[i]))
        end
        return refs
    end
    T = typeof(node)
    isstructtype(T) || return refs
    for fname in fieldnames(T)
        is_view_state_field(fname) && continue
        fv = getfield(node, fname)
        v = fv isa Cell ? fv[] : fv
        v === nothing && continue
        if v isa CellVector
            for i in 1:length(v)
                push!(refs, ((FieldReferenceStep(string(fname)), RangeReferenceStep(i - 1, i)), v[i]))
            end
        elseif v isa Document
            push!(refs, ((FieldReferenceStep(string(fname)),), v))
        end
    end
    refs
end

# Prepend `steps` (outermost-first tuple) onto `path`.
function _prepend_steps(steps::Tuple, path::Reference)
    for s in Base.reverse(steps)
        path = ConcreteReference(s, path)
    end
    path
end

# Relative ∅-path to the first (last, when `reverse`) focusable leaf in
# `node`'s subtree, or `nothing` if it holds no focusable document. `visited` guards
# against cycles in the document graph: an embedded `ListNode` is a doubly-linked
# list (`prev`/`next` both point at Documents), so a naive walk recurses
# `next → prev → next …` forever (this is what makes Tab stack-overflow on a
# file tab/assistant, which embed ListNode-backed text/syntax). Acyclic trees (the
# widget examples) visit each node once regardless, so their focus order is unchanged.
function _focusable_path(node, reverse::Bool, visited::Set{UInt}=Set{UInt}())
    node === nothing && return nothing
    is_focusable_document(node) && return EmptyReference()
    id = objectid(node)
    id in visited && return nothing
    push!(visited, id)
    refs = _child_document_refs(node)
    for (steps, child) in (reverse ? Base.reverse(refs) : refs)
        sub = _focusable_path(child, reverse, visited)
        sub === nothing || return _prepend_steps(steps, sub)
    end
    nothing
end

"""
    get_first_focusable_path(node) -> Reference
    get_last_focusable_path(node)  -> Reference

The relative whole-element (∅) selection path to the first / last focusable
document in `node`'s subtree, or `nothing` if there is none. A disabled widget
is not focusable, so the walk skips it.
"""
get_first_focusable_path(node) = _focusable_path(node, false)
get_last_focusable_path(node)  = _focusable_path(node, true)

"""
    get_next_focusable_index(children, after::Int, reverse::Bool) -> Int

The next slot after `after` (in `reverse` direction) among `children` whose
subtree contains a focusable document; 0 if there is none. `children` is any
1-indexed collection of child documents (a CellVector or Vector).
"""
function get_next_focusable_index(children, after::Int, reverse::Bool)
    n = length(children)
    if reverse
        for j in (after - 1):-1:1
            _focusable_path(children[j], true) === nothing || return j
        end
    else
        for j in (after + 1):n
            _focusable_path(children[j], false) === nothing || return j
        end
    end
    0
end

"""
    is_focusing_press(event) -> Bool

Whether `event` gives the focus to the control under the pointer: a left button
down with no modifier. The focus moves on the down and the control acts on the
press that follows the up, so the move of the focus is an operation of its own.
A projection that can not map the selection drops the move, and the press still
acts.
"""
is_focusing_press(event) =
    event isa MouseDown && event.button === :left && event.modifiers == ModifierKeys()

"""
    convert_to_focus_selection(operation, child) -> operation | nothing

The answer a container gives for a focusing press that hit `child`, where
`operation` is what `child` answered. A focusable `child` that answered nothing
and holds no selection is selected as a whole, which is the selection that Tab
gives it. Every other answer is kept. So a control that answers the down itself,
such as a button that draws itself pressed, keeps its answer and the focus stays
where it is.
"""
function convert_to_focus_selection(operation, child)
    operation === nothing || return operation
    is_focusable_document(child) || return nothing
    hasproperty(child, :selection) && getproperty(child, :selection) !== nothing && return nothing
    ReplaceSelectionOperation(EmptyReference())
end
