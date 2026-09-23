# Fragment of `ClipboardModule` — the wrapper a host puts around its content to
# get copy, cut, note and paste: the clipboard document and the projection that
# goes with it.
using ProjecturedProjection.ProjectionAlgebraModule: ChainingProjection, IdentityProjection,
                                                     NestingProjection, RecursiveProjection,
                                                     TypeDispatchingProjection

"""
    make_clipboard_document(document; collection = false) -> ClipboardDocument

Wrap `document` in a clipboard: a `ClipboardSlice`, or a `ClipboardCollection`
when `collection` is set. The clipboard is the new root, so it holds the
selection that `document` holds, rooted at the clipboard.
"""
function make_clipboard_document(document; collection::Bool = false)
    clipboard = collection ? ClipboardCollection(document) : ClipboardSlice(document)
    inner = get_selection(document)
    inner === nothing || replace_selection!(clipboard,
        concat_references(ConcreteReference(FieldReferenceStep("content"), EmptyReference()),
                          strip_reference_types(inner)))
    clipboard
end

"""
    make_clipboard_projection(projection; collection = false, to_text = nothing,
                              from_text = nothing, text = false,
                              offered_gestures = CLIPBOARD_GESTURES) -> Projection

The projection half of the same wrapper, as two stages.

The first stage is the clipboard. It exposes the document on display (the
wrapped content, or the stored slice once toggled) unchanged. The second stage
is `projection`, which draws that document. The clipboard can not be the last
stage: its output is a cell, so that a toggle propagates, and a chain hands the
last stage's output on as it is.

`to_text` and `from_text` are the optional converters to and from the text of
the host's clipboard; with both `nothing` the host's clipboard is not used,
because a text does not convert into an arbitrary domain safely. `text` makes
copy, cut and paste work on character ranges of a text content. A collection
view shows the stored elements, which only a projection that draws a vector can
render. `offered_gestures` goes to [`ClipboardSliceToAnyProjection`](@ref).
"""
function make_clipboard_projection(projection; collection::Bool = false,
                                   to_text = nothing, from_text = nothing, text::Bool = false,
                                   offered_gestures::Tuple = CLIPBOARD_GESTURES)
    clipboard = collection ?
        ClipboardCollectionToAnyProjection() :
        ClipboardSliceToAnyProjection(; to_text = to_text, from_text = from_text, text = text,
                                      offered_gestures = offered_gestures)
    ChainingProjection(
        RecursiveProjection(TypeDispatchingProjection(Pair{Type,Any}[
            (collection ? ClipboardCollection : ClipboardSlice) => clipboard,
            Any => IdentityProjection(),
        ])),
        NestingProjection(projection; recursion = IdentityProjection()),
    )
end
