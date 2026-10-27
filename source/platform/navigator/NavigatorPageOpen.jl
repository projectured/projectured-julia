# Fragment of `NavigatorModule` — the open of a page that no navigator takes, which
# opens a tab with a navigator of its own, the open of an address outside the
# editor, what the target of a link names, and where a content holds a document.

"""
    find_navigator_target(root, target) -> Reference, String, Url or nothing

What the target of a link names, for a navigator whose content is `root`:
`target` is the text of the target as the domain of the link writes it, such as
`#install`, `guide.md` or the name of an rst target. The answer is a `Reference`
to a part of `root`, the absolute path of a file, a `Url` for an address outside
the editor, such as a web address, which opens in the program of the system for
it, or `nothing` for a target that names nothing. An address outside the editor
needs no page to resolve it, so the default answers a `Url` for an address of the
web or of mail (`find_web_url`) and `nothing` for any other target; a domain adds
a method for its root and its file document.
"""
find_navigator_target(root, target::AbstractString) = find_web_url(target)

"""
    find_navigator_address(root, document) -> Reference or nothing

The path of `document` in `root`, for a navigator whose content is `root`, so a
link that names `document` opens it at its place, with the address, the parent
and the siblings that it has there. The default answers `nothing`, and the link
then makes `document` the content of a new visit. A domain adds a method for its
root, and answers from what it keeps, such as an index of its parts: the
navigator never searches a content, which can hold ten million rows.
"""
find_navigator_address(root, document) = nothing

# An open that no navigator took: a new tab with a navigator on the page. This
# runs while the editor evaluates the open, so the new tab is posted, and the loop
# evaluates it at the top of the next frame, as the open of a file does. A target
# that names a file opens that file in a new tab with a navigator. For the path
# form, the content of the navigator is the document of the tab that holds the
# part, past a history, and a file stays: so Parent reaches the rest of it, and a
# target is resolved against it.
function evaluate_operation(editor, operation::OpenPageOperation)
    content, address = _find_opened_content(editor.document, operation)
    content === nothing && return nothing
    if operation.target !== nothing
        address = find_navigator_target(content, operation.target)
        address isa AbstractString && return evaluate_operation(editor, OpenFileOperation(address; file_wrap = Navigator))
        address isa Url && return evaluate_operation(editor, OpenUrlOperation(address, operation.place))
        address isa Reference || return nothing
        address = annotate_reference_types(content, strip_reference_types(address))
    end
    # A page opens as a person opens it: the new tab takes the focus.
    post_pane_operation!(editor, make_open_pane_operation(Navigator(content, address);
                                                          group = get_pane_file_group(; editor),
                                                          focus = true, editor))
    nothing
end

"""
    open_page!(part; editor = get_evaluation_editor()) -> Text

Open `part` as a page in a new tab with a navigator, as the "Open as a page"
command does: the page shows the part alone, its address names its place in the
document of its tab, and Back, Forward and Parent move from it. The tab opens at
the next frame of the window. `part` is a `ReferencedDocument` that a verb
answered, such as a record read from `get_edited_document(tab)`.

Use it to show the person one part of a large document on a page of its own,
such as one record of a table or one section of a file.

# Example

    people_1 = get_edited_document(find_pane("people.json"))
    open_page!(people_1[2])

See also `open_pane!`, `select_part!`.
"""
function open_page! end

function open_page!(part::ReferencedDocument; editor = get_evaluation_editor())
    run_on_editor_task!(editor; description = "open_page!") do
        evaluate_operation(editor, OpenPageOperation(nothing, get_reference(part)))
    end
    Text("The page of " * describe_document(part) * " opens in a new tab.")
end

# The navigators of the window of `root`: the content of a tab that is one, and a
# navigator that the content of a tab holds in a field, such as the navigator of
# an explorer beside its tree.
function _collect_window_navigators(root)
    tree = try
        get_window_tree(root)
    catch
        nothing
    end
    tree isa PaneTree || return Navigator[]
    found = Navigator[]
    for group in get_pane_groups(tree), tab in group.tabs
        content = tab.content
        if content isa Navigator
            push!(found, content)
        elseif content isa Document
            for name in fieldnames(typeof(content))
                value = getproperty(content, name)
                value isa Navigator && push!(found, value)
            end
        end
    end
    found
end

# The content of a navigator of the window that holds `document`
# (`find_navigator_address`), and the path of `document` in it; `nothing` when no
# navigator of the window holds it.
function _find_holding_content(root, document)
    for navigator in _collect_window_navigators(root)
        content = navigator.content
        held = find_navigator_address(content, document)
        held === nothing || return (content, strip_reference_types(held))
    end
    nothing
end

# The content and the address of the navigator of an open that no navigator took.
# An operation with its own root opens a navigator on the content of a navigator of
# the window that holds that root, at its full address there, so a page of a part
# keeps its breadcrumb and its parent; else on that root. A path from the
# root of the editor opens a navigator on the document of the tab that holds the
# part, past the layers around that document, such as a history, up to a file,
# whose name a link is relative to; with no tab on the path, on the part itself.
function _find_opened_content(root, operation::OpenPageOperation)
    reference = strip_reference_types(operation.reference)
    if operation.document !== nothing
        holding = _find_holding_content(root, operation.document)
        if holding !== nothing
            (content, held) = holding
            path = concat_references(held, reference)
            try_evaluate_reference(content, path, _NOT_REACHED) === _NOT_REACHED ||
                return (content, annotate_reference_types(content, path))
        end
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

# An address outside the editor: a file opens in a new tab with a navigator, as a
# link to a file does, and any other address in the program of the system for it,
# through the backend of the editor. A backend that opens nothing says so in the
# log.
function evaluate_operation(editor, operation::OpenUrlOperation)
    path = find_url_file_path(operation.url)
    path === nothing || return evaluate_operation(editor, OpenFileOperation(path; file_wrap = Navigator))
    address = format_url(operation.url)
    open_url!(editor.backend, address) || @warn("No program of the system opened the address.", address)
    nothing
end
