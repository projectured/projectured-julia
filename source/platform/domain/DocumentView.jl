# Fragment of `DomainModule` — the view document of a document that shows as a
# page: the state of one view of it, apart from the document, which every view
# shares; and the following copy, which shows documents of one type one after
# the other in one place.

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
as the commands of a key, and the view of such an answer is dropped. A view draws
its whole page with one projection, so a part that it introduces, such as a link or
a button, is a part of the view: its path names no part of the document.

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
own. A path that the view introduced, such as the part under the pointer on a
link of the page, is a path of the view itself, and takes no field. A field that
only the view keeps has no path in the document, so a press there leaves the
selection where it is. It mutates the two cells of `view`, which is new
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
# the document, then the path. A path that the view introduced is already a path
# of the view. A selection that the document keeps while it is not live keeps its
# path the same way. A document that holds no path gives the view none.
_prefix_content_path(view, step, path::Reference) =
    is_introduced_reference(path) ? path : ConcreteReference(get_reference_node_type(view), step, path)
_prefix_content_path(view, step, kept::SelectionDocument) =
    SelectionDocument(; primary = _prefix_content_path(view, step, kept.primary), live = kept.live)
_prefix_content_path(view, step, path) = path

"""
    make_following_document(source) -> Document

A document that stays one object while the document that it shows changes: a new
document of the type of `source()`, whose every field computes the same field of
the document that `source()` answers now. `source` takes no argument, and it
answers a document of the same `@document` type at each call. A value of the copy
is the value of that document, so a change inside it, such as a sort of a table
that it holds, is a change of the document of the source. The selection and the
part under the pointer follow too, so the copy draws the selection of the
document that it shows.

Use it where one place shows documents of one type one after the other, such as
the detail of the selected row of a table. A projection then prints the copy one
time, and the state of that print, such as a folded card, stays when the source
answers another document.

A write of a whole field of the copy ends the following of that field, so write
the document of the source. Each field must be a `ReactiveCell`
([`is_followable_document`](@ref)); another kind of field throws an
`ArgumentError`.

# Example

    selected = Cell(1)
    shown = make_following_document(() -> pages[selected[]])
    selected[] = 2      # `shown` is the same object, and its fields are those of `pages[2]`

See also `make_document_view` and `follow_content_selection!`.
"""
function make_following_document end

function make_following_document(source)
    document = source()
    type = typeof(document)
    # The bare name of the schema takes cells; the concrete type of a cell layout
    # carries a parameter for each field and does not.
    make = Base.typename(type).wrapper
    make(map(name -> _make_following_cell(source, type, name, getfield(document, name)), fieldnames(type))...)
end

"""
    is_followable_document(document) -> Bool

Whether [`make_following_document`](@ref) can make a following copy of a document
of the type of `document`: each field of it is a `ReactiveCell`, as each field of a
`@document` with no field of another kind is.
"""
is_followable_document(document) =
    !isempty(fieldnames(typeof(document))) && all(name -> getfield(document, name) isa ReactiveCell, fieldnames(typeof(document)))

# The cell of the field `name` of a following copy: the same field of `source()`.
_make_following_cell(source, type, name, ::ReactiveCell{T}) where {T} =
    ReactiveCell{T}(Computation(() -> getfield(source(), name)[]))
_make_following_cell(source, type, name, cell) =
    throw(ArgumentError("make_following_document: the field `$name` of $type is a $(typeof(cell)), not a ReactiveCell"))
