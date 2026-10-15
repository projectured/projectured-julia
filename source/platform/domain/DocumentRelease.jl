# Fragment of `DomainModule` — the acquire of a document that enters the window,
# which starts what it needs, such as the computation of a sheet; and the release
# of a document that leaves the window: what it holds outside the document tree,
# such as a process or a server, ends.

"""
    acquire_document!(editor, document)

Start what `document` needs because it enters the window of `editor`: a tab
opens with it, or the window starts with it. The default starts nothing. A
document that needs something adds a method: a sheet of formulas computes the
values that it does not hold yet. A document that holds such a document passes
it on, as a pane tree acquires each layer of what each of its tabs shows. The
counterpart of [`release_document!`](@ref). It runs on the loop, as an operation
does.
"""
acquire_document!(editor, document) = nothing

"""
    AcquireDocumentOperation(document)

Acquire `document` with [`acquire_document!`](@ref). The open of a tab adds it
after the insert of the tab, and a window posts it for its documents when it
starts. It changes no document, so its inverse is `DoNothingOperation()`.
"""
struct AcquireDocumentOperation <: Operation
    document::Any
end

function evaluate_operation(editor, operation::AcquireDocumentOperation)
    acquire_document!(editor, operation.document)
    nothing
end

make_inverse_operation(document, operation::AcquireDocumentOperation) = DoNothingOperation()

describe_operation(operation::AcquireDocumentOperation) =
    "acquire the $(nameof(typeof(operation.document))) that enters the window"

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
