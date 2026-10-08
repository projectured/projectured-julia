# Fragment of `DomainModule` — the release of a document that leaves the window:
# what it holds outside the document tree, such as a process or a server, ends.

"""
    release_document!(editor, document)

Free what `document` holds outside the document tree, such as a process or a
server, because the document leaves the window. The default frees nothing. A
document that holds such a thing adds a method: the assistant stops its
external agent.
"""
release_document!(editor, document) = nothing

"""
    ReleaseDocumentOperation(document)

Release `document` with [`release_document!`](@ref). The close of a tab adds it
after the delete of the tab. It changes no document, so its inverse is
`DoNothingOperation()`: an undo of the close brings the document back, and the
document starts again what it needs when it needs it.
"""
struct ReleaseDocumentOperation <: Operation
    document::Any
end

function evaluate_operation(editor, operation::ReleaseDocumentOperation)
    release_document!(editor, operation.document)
    nothing
end

make_inverse_operation(document, operation::ReleaseDocumentOperation) = DoNothingOperation()

describe_operation(operation::ReleaseDocumentOperation) =
    "release the $(nameof(typeof(operation.document))) that leaves the window"
