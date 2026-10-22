# Fragment of `TreeModule` — the contract of the slice: the generics that say how
# a document is a node of a tree, with no body. A slice that owns a kind of node
# adds methods to them, and the tree slice names none of those slices. The
# fallback behaviours sit in `TreeDefaults.jl`.

"""
    get_tree_children_steps(document) -> Tuple

The paths from `document` to each collection of its children, in order, each a
tuple of `ReferenceStep`s: `((FieldReferenceStep("children"),),)` for a node with
one collection in its field `children`. The children of a node are the elements
of its collections, one collection after the other, so a node can show two kinds
of children, such as the parts that it holds and the work that it started.

It runs inside a computation of the tree, so it can read cells. A path that
reaches nothing gives no children. The default is `()`: a document is a leaf.
"""
function get_tree_children_steps end

"""
    format_tree_node_label(document) -> String

The text of the node of `document` in a tree, in one line: the node draws a line
break as a space. It runs inside the computation of the node, so it reads cells,
and the node draws again when what it reads changes, and no other node does. The
default is the title of the document, or the name of its type that a person
sees. A part that a verb answered has the label of its document.

Use it to name an entry of the explorer or a node of a tree as the person sees it.

# Example

    content_1 = find_explorer_content()
    [format_tree_node_label(entry) for entry in content_1.entries]

See also `find_explorer_content`, `show_document_tree!`.
"""
function format_tree_node_label end

"""
    has_tree_children(document) -> Bool or nothing

Whether the node of `document` in a tree has children, answered from what the
document holds: `true`, `false`, or `nothing` while that is not known. The node
draws a chevron only for `true`, so a node whose children are not known looks
empty, and a closed node reads no children. A document whose children come from
the disk or a process answers it from its stored state, such as a folder whose
emptiness the read of its parent found. It runs inside the computation of the
row, so it reads cells. The default reads the children: `true` when a collection
of the children has an element.
"""
function has_tree_children end

"""
    demand_tree_children(document) -> nothing

Ask for the children of the node of `document`, in a part that shows them: the
open node of a tree, the page of a folder, a search below a node. A kind whose
children a task reads, such as a folder whose listing is a background cell, reads
that cell here, so the read records a demand, and the children come in a later
frame. A part that only looks at what was read, such as the quick filter of an
explorer, and the chevron of a closed row, do not call it, so they read no disk.
The default asks for nothing.

Use it where a computation shows the children of a node.

# Example

    demand_tree_children(folder)

See also `get_tree_children_steps` and `has_tree_children`.
"""
function demand_tree_children end

"""
    is_explorer_entry_type(type) -> Bool

Whether a person adds a document of `type` as an entry of an explorer: the kinds
that the list of `+` and of Insert in an explorer shows, such as a folder, the
task list of the editor or a section. The document of a kind comes from its
insertion (`make_insertion_document`), and its name in the list from its first
insertion alias. A slice that owns a kind adds a method that answers `true`, so a
package that loads adds its kinds to the list at once. The default is `false`.
"""
function is_explorer_entry_type end

"""
    is_session_explorer_entry_type(type) -> Bool

Whether the first content of the explorer of a window holds the session document
of `type`: the document that `type()` makes, once for each editor, as
`get_session_document!(type, editor, type)` gives it. The first content puts it
after the lists of the session, such as the task list. A slice or a package that
owns such a kind adds a method for its type that answers `true`, so the packages
that are loaded give these entries, and no table names them. The session getter
of the kind makes the same call, so both give one document. The default is
`false`.
"""
function is_session_explorer_entry_type end
