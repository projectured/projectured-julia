# Fragment of `DomainModule` — the acquire of a document that enters the window,
# which starts what it needs, such as the computation of a sheet; the release of a
# document that leaves the window: what it holds outside the document tree, such
# as a process or a server, ends; and the count of the holders of each document,
# so a document that two holders show is acquired once and released once.

"""
    acquire_document!(editor, document)

Start what `document` needs because it enters the window of `editor`: a tab
opens with it, or the window starts with it. The default starts nothing. A
document that needs something adds a method: a sheet of formulas computes the
values that it does not hold yet. A document that shows other documents passes
the acquire on with [`hold_documents!`](@ref), as a tab holds each layer of what
it shows. It runs at the first holder of the document
([`add_document_holder!`](@ref)). The counterpart of
[`release_document!`](@ref). It runs on the loop, as an operation does.
"""
acquire_document!(editor, document) = nothing

"""
    AcquireDocumentOperation(document)

Add a holder of `document` with [`add_document_holder!`](@ref), which acquires
the document at its first holder. The open of a tab adds it after the insert of
the tab, and a window posts it for its documents when it starts. Its inverse
releases the document, so an undo of the open of a tab ends what the tab started,
such as the watch of a file.
"""
struct AcquireDocumentOperation <: Operation
    document::Any
end

function evaluate_operation(editor, operation::AcquireDocumentOperation)
    add_document_holder!(editor, operation.document)
    nothing
end

make_inverse_operation(document, operation::AcquireDocumentOperation) =
    ReleaseDocumentOperation(operation.document)

describe_operation(operation::AcquireDocumentOperation) =
    "acquire the $(nameof(typeof(operation.document))) that enters the window"

"""
    release_document!(editor, document)

Free what `document` holds outside the document tree, such as a process or a
server, because the document leaves the window. The default frees nothing. A
document that holds such a thing adds a method: the assistant stops its
external agent. A document that holds other documents passes the release on
with [`release_held_documents!`](@ref). It runs at the last holder of the
document ([`remove_document_holder!`](@ref)).
"""
release_document!(editor, document) = nothing

"""
    ReleaseDocumentOperation(document)

Remove a holder of `document` with [`remove_document_holder!`](@ref), which
releases the document at its last holder. The close of a tab adds it after the
delete of the tab. Its inverse acquires the document, so an undo of the close
starts again what the tab needs, such as the watch of a file.
"""
struct ReleaseDocumentOperation <: Operation
    document::Any
end

function evaluate_operation(editor, operation::ReleaseDocumentOperation)
    remove_document_holder!(editor, operation.document)
    nothing
end

make_inverse_operation(document, operation::ReleaseDocumentOperation) =
    AcquireDocumentOperation(operation.document)

describe_operation(operation::ReleaseDocumentOperation) =
    "release the $(nameof(typeof(operation.document))) that leaves the window"

# ── The holders ──────────────────────────────────────────────────────────────

# The holders of the documents of the window of an editor: how many holders each
# document has, and what each holder holds. A session document of the editor.
struct DocumentHolders
    counts::IdDict{Any,Int}
    held::IdDict{Any,IdDict{Any,Nothing}}
end

# The holders of `editor`; `nothing` for an editor that is not an `Editor`, such
# as the stand-in of a test, which counts nothing.
_find_document_holders(editor::Editor) =
    get_session_document!(() -> DocumentHolders(IdDict{Any,Int}(), IdDict{Any,IdDict{Any,Nothing}}()),
                          editor, DocumentHolders)
_find_document_holders(editor) = nothing

"""
    add_document_holder!(editor, document) -> nothing

Count one more holder of `document` in the window of `editor`, such as a tab that
shows it, an open node of a tree or the page of a navigator. The first holder
acquires the document with [`acquire_document!`](@ref), so a document that two
holders show starts what it needs once. An editor that is not an `Editor`, such
as the stand-in of a test, counts nothing and acquires the document at each call.
The counterpart of [`remove_document_holder!`](@ref).
"""
function add_document_holder!(editor, document)
    holders = _find_document_holders(editor)
    if holders !== nothing
        count = get(holders.counts, document, 0)
        holders.counts[document] = count + 1
        count == 0 || return nothing
    end
    acquire_document!(editor, document)
    nothing
end

"""
    remove_document_holder!(editor, document) -> nothing

Count one holder less of `document`. The last holder releases the document with
[`release_document!`](@ref), and a document with no holder is not released
again. An editor that is not an `Editor` releases the document at each call.
"""
function remove_document_holder!(editor, document)
    holders = _find_document_holders(editor)
    if holders !== nothing
        count = get(holders.counts, document, 0)
        count == 0 && return nothing
        if count > 1
            holders.counts[document] = count - 1
            return nothing
        end
        delete!(holders.counts, document)
    end
    release_document!(editor, document)
    nothing
end

"""
    hold_documents!(editor, holder, documents) -> nothing

Make `holder` a holder of each of `documents`, the documents that it shows: the
layers of a tab, the open nodes of a tree, the page of a navigator. A holder calls
it from its own [`acquire_document!`](@ref). The editor keeps what each holder
holds, so [`release_held_documents!`](@ref) releases the same documents, also
after the holder shows others, and a [`ChangeHeldDocumentsOperation`](@ref)
changes them while the holder is held.
"""
function hold_documents!(editor, holder, documents)
    holders = _find_document_holders(editor)
    held = holders === nothing ? nothing : get!(() -> IdDict{Any,Nothing}(), holders.held, holder)
    for document in documents
        if held !== nothing
            haskey(held, document) && continue
            held[document] = nothing
        end
        add_document_holder!(editor, document)
    end
    nothing
end

"""
    release_held_documents!(editor, holder, documents) -> nothing

Remove `holder` as a holder of what it holds. A holder calls it from its own
[`release_document!`](@ref). An `Editor` releases what it recorded for `holder`,
and `documents` is not read. An editor that is not an `Editor` records nothing,
so it releases `documents`, the documents that the holder shows.
"""
function release_held_documents!(editor, holder, documents)
    holders = _find_document_holders(editor)
    held = holders === nothing ? documents : collect(keys(pop!(holders.held, holder, IdDict{Any,Nothing}())))
    foreach(document -> remove_document_holder!(editor, document), held)
    nothing
end

"""
    ChangeHeldDocumentsOperation(holder, released, acquired)

`holder` holds each of `acquired`, and no longer each of `released`: a node of a
tree opens or closes, or a navigator visits another page. While `holder` is held,
the evaluation adds a holder of each of `acquired` that it does not hold yet, and
then removes one of each of `released` that it holds. A holder that is not held,
such as a tree that no tab shows, passes nothing on. Its inverse swaps the two
lists.
"""
struct ChangeHeldDocumentsOperation <: Operation
    holder::Any
    released::Vector{Any}
    acquired::Vector{Any}
end

function evaluate_operation(editor, operation::ChangeHeldDocumentsOperation)
    holders = _find_document_holders(editor)
    holders === nothing && return nothing
    held = get(holders.held, operation.holder, nothing)
    held === nothing && return nothing
    for document in operation.acquired
        haskey(held, document) && continue
        held[document] = nothing
        add_document_holder!(editor, document)
    end
    for document in operation.released
        haskey(held, document) || continue
        delete!(held, document)
        remove_document_holder!(editor, document)
    end
    nothing
end

make_inverse_operation(document, operation::ChangeHeldDocumentsOperation) =
    ChangeHeldDocumentsOperation(operation.holder, operation.acquired, operation.released)

describe_operation(operation::ChangeHeldDocumentsOperation) =
    "change what the $(nameof(typeof(operation.holder))) shows"

# The acquire, the release and the change of what a holder holds name their
# subject and no place, so each goes up the readers as it is: a tree whose node
# opens answers one through the views around it.
is_self_contained_operation(::Union{AcquireDocumentOperation, ReleaseDocumentOperation,
                                    ChangeHeldDocumentsOperation}) = true
