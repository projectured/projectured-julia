# Fragment of `NavigatorModule` — the request of a link: open this part as a page.
# A part answers it, the nearest navigator around the part takes it, and one that
# no navigator takes opens a tab with a navigator of its own.

"""
    OpenPageOperation(document, reference[, place]; target = nothing)

The request of a link: show a part as a page. A part that a person presses
answers it, and the nearest navigator around the part takes it; see
[`Navigator`](@ref).

- With `document === nothing`, `reference` is a path from the part that
  answers. Every reader on the way up maps it, as any path, so this form opens
  the part itself or a part under it: a row of a table, a field of a form.
- With a `document`, the operation carries its own root, and `reference` is a
  path from it. It goes up unchanged, so this form opens any object: a node of
  another document, or an object of the program.
- With a `target`, the path form names the link, and `target` is the text of
  what the link names, as its domain writes it: `#install`, `guide.md`, the name
  of an rst target. The domain of the content resolves it
  ([`find_navigator_target`](@ref)), and the open shows what the target names.
- `place` is `:here`, the default: the nearest navigator shows the page. With
  `:new_tab`, a new tab shows it in a navigator of its own, as Ctrl+click on a
  link does in a browser.

An open that no navigator takes opens a new tab with a navigator on the page,
when the editor evaluates it. A target that names a file opens that file in a new
tab with a navigator, as the open of a file does. For the path form, the content of that navigator
is the document of the tab that holds the part, past a history, and a file
stays: so Parent reaches the rest of it, and a target is resolved against it.

# Example

    OpenPageOperation(nothing, EmptyReference())                 # the part itself
    OpenPageOperation(customers, @reference(customers, rows[7]), :new_tab)
    OpenPageOperation(nothing, EmptyReference(); target = "#install")
"""
struct OpenPageOperation <: Operation
    document::Any
    reference::Reference
    place::Symbol
    target::Union{Nothing,String}
end

# @optional: where the page opens follows what it opens, as a command names it, and
# most pages open here.
OpenPageOperation(document, reference::Reference, place::Symbol = :here;
                  target::Union{Nothing,AbstractString} = nothing) =
    OpenPageOperation(document, reference, place, target === nothing ? nothing : String(target))

OperationModule.operation_reference(operation::OpenPageOperation) =
    operation.document === nothing ? operation.reference : nothing
OperationModule.retarget_operation(operation::OpenPageOperation, reference::Reference) =
    OpenPageOperation(nothing, reference, operation.place, operation.target)
OperationModule.is_self_contained_operation(operation::OpenPageOperation) =
    operation.document !== nothing

function OperationModule.describe_operation(operation::OpenPageOperation)
    target = operation.target
    target === nothing && return operation.place === :new_tab ? "Open in a new tab" : "Open as a page"
    operation.place === :new_tab ? "Open $(target) in a new tab" : "Follow the link to $(target)"
end

"""
    find_navigator_target(root, target) -> Reference, String or nothing

What the target of a link names, for a navigator whose content is `root`:
`target` is the text of the target as the domain of the link writes it, such as
`#install`, `guide.md` or the name of an rst target. The answer is a `Reference`
to a part of `root`, the absolute path of a file, or `nothing` for a target that
names nothing here, such as a web URL. The default answers `nothing`; a domain
adds a method for its root and its file document.
"""
find_navigator_target(root, target::AbstractString) = nothing

# An open that no navigator took: a new tab with a navigator on the page. This
# runs while the editor evaluates the open, so the new tab is posted, and the loop
# evaluates it at the top of the next frame, as the open of a file does.
function evaluate_operation(editor, operation::OpenPageOperation)
    content, address = _find_opened_content(editor.document, operation)
    content === nothing && return nothing
    if operation.target !== nothing
        address = find_navigator_target(content, operation.target)
        address isa AbstractString && return evaluate_operation(editor, OpenFileOperation(address; file_wrap = Navigator))
        address isa Reference || return nothing
        address = annotate_reference_types(content, strip_reference_types(address))
    end
    post_pane_operation!(editor, make_open_pane_operation(Navigator(content, address);
                                                          group = get_pane_file_group(; editor), editor))
    nothing
end

# The content and the address of the navigator of an open that no navigator took.
# An operation with its own root opens a navigator on that root. A path from the
# root of the editor opens a navigator on the document of the tab that holds the
# part, past the layers around that document, such as a history, up to a file,
# whose name a link is relative to; with no tab on the path, on the part itself.
function _find_opened_content(root, operation::OpenPageOperation)
    reference = strip_reference_types(operation.reference)
    if operation.document !== nothing
        content = operation.document
        try_evaluate_reference(content, reference, _NOT_REACHED) === _NOT_REACHED && return (nothing, nothing)
        return (content, annotate_reference_types(content, reference))
    end
    steps = get_reference_steps(reference)
    nodes = Any[root]
    for step in steps
        node = try_evaluate_reference(nodes[end], extend_reference(EmptyReference(), step), _NOT_REACHED)
        node === _NOT_REACHED && return (nothing, nothing)
        push!(nodes, node)
    end
    # `steps[k]` leads from `nodes[k]` to `nodes[k + 1]`.
    start = findlast(k -> nodes[k] isa PaneTab && steps[k] == _CONTENT_STEP, eachindex(steps))
    start === nothing && return (nodes[end], EmptyReference())
    index = start + 1
    while index <= length(steps) && !(nodes[index] isa FileDocument)
        field = get_edited_field(nodes[index])
        (field !== nothing && steps[index] == FieldReferenceStep(String(field))) || break
        index += 1
    end
    content = nodes[index]
    (content, annotate_reference_types(content, extend_reference(EmptyReference(), steps[index:end]...)))
end
