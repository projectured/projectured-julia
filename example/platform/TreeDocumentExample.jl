# The tree example: an outline of plain documents, shown as a `DocumentTree`. A
# document becomes a node through the generics of the tree slice and its icon
# through its decoration, so the example declares a document of its own and gives
# it those methods, as a slice does for its kind of node.

"""
    OutlineItem(title, items)

One item of an outline: its `title`, and the items under it, a `CellVector` of
`OutlineItem`. The tree slice draws it as a node whose children are its items.
"""
@document struct OutlineItem
    title::String
    items::CellVector
end

TreeModule.get_tree_children_steps(::OutlineItem) = ((FieldReferenceStep("items"),),)
TreeModule.format_tree_node_label(item::OutlineItem) = item.title
ProjecturedPlatform.DomainModule.get_document_decoration(item::OutlineItem) =
    ProjecturedPlatform.DomainModule.DocumentDecoration(; icon = isempty(item.items) ? :file : :folder)

_make_outline_item(title, items...) = OutlineItem(title, CellVector(Any[items...]))

# An outline of the concepts of the editor, three levels deep. The tree opens its
# root, so the first level shows and the deeper ones wait for a chevron.
make_document_tree_document_example() =
    DocumentTree(_make_outline_item("ProjecturEd",
        _make_outline_item("Documents",
            _make_outline_item("Cells"),
            _make_outline_item("References")),
        _make_outline_item("Projections",
            _make_outline_item("Printers"),
            _make_outline_item("Readers"),
            _make_outline_item("IO maps")),
        _make_outline_item("Editing")))
