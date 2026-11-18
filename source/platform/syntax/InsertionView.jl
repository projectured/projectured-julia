# Fragment of `SyntaxModule`.
#
# The views of the place of every domain: the place where a person types the name
# of a kind of document, and the empty place. A view keeps the caret of one view of
# such a place, so two views of one place keep two carets, and the place holds none.
# The keys that mean something to a place are rows of its view, as they are rows of
# its printer for a place with no view: the view at the end of the caret reads a key
# first, and its row answers for the node of that view, with the empty path.

"""
    DocumentInsertionView(viewed::DocumentInsertion)

A view of the place where a person types the name of a kind of document of any
domain. Its caret is a place in the typed text, such as `.value{2}`, or the whole
place. Return makes the document that the typed name names, Escape puts the empty
place back, and Tab takes the completion of the typed text. A viewing step of the
stage from any domain to syntax prints it as the `SyntaxDelimitationView` of the
wrapper of the place.
"""
@content_view DocumentInsertion struct DocumentInsertionView <: ContentView end

"""
    DocumentNothingView(viewed::DocumentNothing)

A view of the empty place of every domain, which holds no value. Its caret is the
whole place or a place on its label. Insert makes the place for a new value of it.
"""
@content_view DocumentNothing struct DocumentNothingView <: ContentView end

"""
    make_insertion_widen_operation(insertion) -> Operation

The operation that puts the place of every domain, a `DocumentInsertion`, in the
place of `insertion`, the place for a new value of one domain, with the same typed
text and the caret at its end. A person can then type the name of a document of
any domain there. The path of the operation is the empty path: the path of
`insertion`, or of a view of it.

It is what Insert does in the place for a new value of a domain, where that place
takes a document of any domain.
"""
function make_insertion_widen_operation(insertion)
    text = something(insertion.value, "")
    make_replace_document_operation(EmptyReference(),
                                    with_value_caret(DocumentInsertion(text), length(text)))
end

# Return in the place of every domain: the document that the typed name names, in the
# place of the node of the view; `nothing` when the text names none.
function _commit_through_view(view::DocumentInsertionView)
    document = default_factory(something(view.viewed.value, ""))
    document === nothing ? nothing : make_replace_document_operation(EmptyReference(), document)
end

@gestures DocumentInsertionView begin
    KeyPress('\n')   => "Commit insertion" => _commit_through_view(doc)
    KeyDown(:escape) => "Cancel insertion" =>
        make_replace_document_operation(EmptyReference(), get_nothing_document(DocumentInsertion)())
    KeyPress('\t')   => "Accept completion" => make_completion_operation(doc.viewed, get_selection(doc))
end

@gestures DocumentNothingView begin
    KeyDown(:insert) => "Insert a new document" => insert_document_operation(DocumentInsertion)
end
