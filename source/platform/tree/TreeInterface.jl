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
sees.
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
    is_explorer_entry_type(type) -> Bool

Whether a person adds a document of `type` as an entry of an explorer: the kinds
that the list of `+` and of Insert in an explorer shows, such as a folder, the
task list of the editor or a section. The document of a kind comes from its
insertion (`make_insertion_document`), and its name in the list from its first
insertion alias. A slice that owns a kind adds a method that answers `true`, so a
package that loads adds its kinds to the list at once. The default is `false`.
"""
function is_explorer_entry_type end
