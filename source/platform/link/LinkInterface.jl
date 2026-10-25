# Fragment of `LinkModule` — the functions of a link: the three that a link type
# answers, and the three that a view reads to give a link its face, with their
# defaults from the target.

"""
    is_link(x) -> Bool

Whether `x` is a link: a value that refers to a target and has a face, and that
answers `get_link_target` and `get_link_content`. `false` by default; a link type
answers `true`.

Use it to show a link of any domain the same way.

# Example

    is_link(Link(page))    # true
"""
function is_link end

is_link(x) = false

"""
    get_link_target(link) -> target

What `link` refers to: a document, or a place in a document as a
`DocumentLocator`. Each link type answers it.

Use it to open what a link names, or to read it.

# Example

    get_link_target(Link(page)) === page
"""
function get_link_target end

"""
    get_link_content(link) -> nothing, a string or a document

The face that `link` carries: `nothing` for a face that comes from the target, a
string such as an alias, or a document to draw. `nothing` by default.

Use it to draw a link as its author gave it.

# Example

    get_link_content(Link(page; content = "the list")) == "the list"
"""
function get_link_content end

get_link_content(link) = nothing

"""
    format_link_label(link) -> String

The text of the face of `link`: its content when it is a string, the name of its
content when it is a document, and else the name of its target as a tree shows
it. For a place, the name is that of the node that the place reaches now, and
`"?"` when it reaches no node.

Use it to say what a link names in a line of text.

# Example

    format_link_label(Link(page))    # "todo.txt"
"""
function format_link_label end

function format_link_label(link)
    content = get_link_content(link)
    content isa AbstractString && return String(content)
    content === nothing || return format_tree_node_label(content)
    _format_target_label(get_link_target(link))
end

_format_target_label(target) = format_tree_node_label(target)

function _format_target_label(target::DocumentLocator)
    found = find_referenced_document(target)
    found === nothing ? "?" : format_tree_node_label(get_document(found))
end

"""
    describe_link(link) -> String

The words that say where `link` leads, for its tooltip: the name of a document,
or the name of the node that a place reaches and the name of the document that
holds the place.

Use it to tell a person what a click on a link opens before the click.

# Example

    describe_link(Link(DocumentLocator(section, reference)))   # "beta in Inner"
"""
function describe_link end

describe_link(link) = _describe_target(get_link_target(link))

_describe_target(target) = format_tree_node_label(target)

function _describe_target(target::DocumentLocator)
    target.reference isa EmptyReference && return _describe_target(target.start)
    found = find_referenced_document(target)
    within = format_tree_node_label(target.start)
    found === nothing ? "Nothing at " * string(strip_reference_types(target.reference)) * " in " * within :
                        format_tree_node_label(get_document(found)) * " in " * within
end

"""
    is_link_broken(link) -> Bool

Whether the target of `link` is gone: a place that reaches no node now. `false`
for any other target.

Use it to draw a link that opens nothing as muted.

# Example

    is_link_broken(Link(DocumentLocator(section, @reference(section, entries[9]))))
"""
function is_link_broken end

is_link_broken(link) = _is_target_gone(get_link_target(link))

_is_target_gone(target) = false
_is_target_gone(target::DocumentLocator) = find_referenced_document(target) === nothing

# The icon of the target of a link: the icon of its decoration, of the node that a
# place reaches now; `nothing` for a place that reaches no node.
_get_target_icon(target) = get_document_decoration(target).icon

function _get_target_icon(target::DocumentLocator)
    found = find_referenced_document(target)
    found === nothing ? nothing : get_document_decoration(get_document(found)).icon
end
