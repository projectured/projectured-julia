# Fragment of `FocusModule` — a place as a path through the content, and as a path
# through the views. A document that shows its content through views, such as the
# view of a file, has the content at one field and the views at another, so one
# place has two paths below it. A caret and the pointer are in the views. An
# operation, a reader of the content and an assistant name a place in the content.

"""
    get_content_path(view, path) -> Reference or nothing

A path of `view` as a path of the content that `view` shows: the path of the same
place, from that content. `nothing` when `path` names a place that only the view
has, such as its scroll pane.

A document that names what it shows with `get_edited_field` takes the step of that
field off. The whole document is no place of what it shows, so the empty path
answers `nothing`. A type of view adds a method when it shows its content through
views of its own.

Use it to name the part that a caret is in, as an operation of the content names it.

# Example

    get_content_path(view, get_selection(view))

See also `get_view_path` and `find_content_path`.
"""
function get_content_path end

function get_content_path(view, path)
    field = get_content_field(view)
    (field === nothing || !(path isa ConcreteReference)) && return nothing
    steps = get_reference_steps(strip_reference_types(path))
    first(steps) == FieldReferenceStep(String(field)) || return nothing
    length(steps) == 1 ? EmptyReference() : Reference(steps[2:end]...)
end

"""
    get_view_path(view, path) -> Reference

A path of the content that `view` shows, as a path of `view`: the path of the same
place, through what the view holds for it. It is the reverse of
[`get_content_path`](@ref).

A document that names what it shows with `get_edited_field` answers the step of
that field and then `path`. A type of view adds a method when it shows its content
through views of its own.

Use it to put a caret, or to send a change, at a place that is known in the content.

# Example

    get_view_path(view, @reference(content, .elements[2]))

See also `get_content_path` and `find_view_path`.
"""
function get_view_path end

function get_view_path(view, path)
    field = get_content_field(view)
    field === nothing && return path
    step = FieldReferenceStep(String(field))
    path isa ConcreteReference ? Reference(step, get_reference_steps(strip_reference_types(path))...) : Reference(step)
end

# The field at which `node` holds what it shows, when a path from a root can change
# there between the content and the views: the field that `get_edited_field` names.
# A type whose paths do not change there answers `nothing`.
get_content_field(node::Document) = get_edited_field(node)
get_content_field(node) = nothing

"""
    find_content_path(root, path) -> Reference

`path`, a path from `root`, as the path of the same place through the content. A
document on the way that shows its content through views has that content at one
field and the views at another. The answer goes through the field of the content
there, and then by the path of the content ([`get_content_path`](@ref)). A whole
document that shows its content through views names that content. A path that goes
through no such document is `path` itself, with no types.

Use it to name the part that a caret or the pointer is in, as an operation and a
reader of the content name it.

# Example

    find_content_path(editor.document, get_selection(editor.document))

See also `find_view_path`.
"""
function find_content_path end

function find_content_path(root, path)
    path isa ConcreteReference || return path
    steps = Any[get_reference_steps(strip_reference_types(path))...]
    walked = Any[]
    node = root
    while true
        field = get_content_field(node)
        if field !== nothing
            below = get_content_path(node, isempty(steps) ? EmptyReference() : Reference(steps...))
            if below !== nothing
                push!(walked, FieldReferenceStep(String(field)))
                node = getproperty(node, field)
                steps = below isa ConcreteReference ? Any[get_reference_steps(strip_reference_types(below))...] : Any[]
                continue
            end
        end
        isempty(steps) && break
        step = popfirst!(steps)
        push!(walked, step)
        node = try_evaluate_reference(node, Reference(step), nothing)
        node === nothing && (append!(walked, steps); break)
    end
    isempty(walked) ? EmptyReference() : Reference(walked...)
end

"""
    find_view_path(root, path) -> Reference

`path`, a path from `root` through the content, as the path of the same place
through the views. It is the reverse of [`find_content_path`](@ref): where a
document on the way shows its content through views, the answer goes through the
views ([`get_view_path`](@ref)). A path that goes through no such document is `path`
itself, with no types.

Use it before a write of the selection, and for the place of a change, when the
place is known in the content.

# Example

    find_view_path(editor.document, get_reference(part))

See also `find_content_path`.
"""
function find_view_path end

function find_view_path(root, path)
    path isa ConcreteReference || return path
    steps = Any[get_reference_steps(strip_reference_types(path))...]
    walked = Any[]
    node = root
    while !isempty(steps)
        step = popfirst!(steps)
        field = get_content_field(node)
        if field !== nothing && step == FieldReferenceStep(String(field))
            shown = get_view_path(node, isempty(steps) ? EmptyReference() : Reference(steps...))
            shown_steps = shown isa ConcreteReference ? Any[get_reference_steps(strip_reference_types(shown))...] : Any[]
            if isempty(shown_steps) || first(shown_steps) != step
                append!(walked, shown_steps)
                return isempty(walked) ? EmptyReference() : Reference(walked...)
            end
        end
        push!(walked, step)
        node = try_evaluate_reference(node, Reference(step), nothing)
        node === nothing && (append!(walked, steps); break)
    end
    isempty(walked) ? EmptyReference() : Reference(walked...)
end
