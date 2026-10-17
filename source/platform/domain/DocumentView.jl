# Fragment of `DomainModule` — the view document of a document that shows as a
# page: the state of one view of it, apart from the document, which every view
# shares.

"""
    make_document_view(document) -> Any

The view document that shows `document` as a page: a new document that keeps the
state of this one view of it, such as the place of a long table and the rows in
view, and names `document` with `get_edited_field`. The default answers
`document` itself, so a document with no view of its own shows as itself. A
domain adds a method for a kind of document whose page keeps state that the
document must not keep. A view holds what it shows from its `acquire_document!`,
and something holds the view only while it shows. A method changes no state and
starts nothing: a reader calls it, also for an answer that it only describes, such
as the commands of a key, and the view of such an answer is dropped.

Use it where a page of a document opens, as a navigator does at each visit, and
pass the answer to [`follow_content_selection!`](@ref) when it is a view.

# Example

    view = make_document_view(document)
    view === document || follow_content_selection!(view)

See also `follow_content_selection!` and `get_edited_field`.
"""
function make_document_view end

make_document_view(document) = document

"""
    follow_content_selection!(view) -> view

Make the selection of `view` and its part under the pointer follow those of the
document that it shows, the field that `get_edited_field(view)` names: each is that
field, then the path that the document holds. A selection path then keeps going
through the document, and the view draws the selection of the document as its
own. A part that only the view draws has no path in the document, so a press there
leaves the selection where it is. It mutates the two cells of `view`, which is new
and is not on a selection path yet.

Use it on a view that [`make_document_view`](@ref) makes, before the view shows.

# Example

    follow_content_selection!(make_document_view(document))

See also `make_document_view`.
"""
function follow_content_selection! end

function follow_content_selection!(view)
    field = get_edited_field(view)
    field === nothing && throw(ArgumentError("follow_content_selection!: $(typeof(view)) names no edited field"))
    step = FieldReferenceStep(String(field))
    for name in (:selection, :mouse_target)
        hasfield(typeof(view), name) || continue
        set_cell_computation!(getfield(view, name),
                              () -> _prefix_content_path(view, step, getfield(getfield(view, field)[], name)[]))
    end
    view
end

# The path of the document, as a path of its view: the field of the view that holds
# the document, then the path. A selection that the document keeps while it is not
# live keeps its path the same way. A document that holds no path gives the view
# none.
_prefix_content_path(view, step, path::Reference) = ConcreteReference(get_reference_node_type(view), step, path)
_prefix_content_path(view, step, kept::SelectionDocument) =
    SelectionDocument(; primary = _prefix_content_path(view, step, kept.primary), live = kept.live)
_prefix_content_path(view, step, path) = path
