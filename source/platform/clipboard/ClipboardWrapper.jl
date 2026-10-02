# Fragment of `ClipboardModule` — the wrapper a host puts around its content to
# get copy, cut, note and paste: the clipboard document and the projection that
# goes with it.
using ProjecturedPlatform.ProjectionAlgebraModule: IdentityProjection, NestingProjection,
                                                     RecursiveProjection, TypeDispatchingProjection

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

The projection half of the same wrapper: an arm of a recursive type dispatch.

The clipboard prints the document on display (the wrapped content, or the
stored slice once toggled) through the dispatch, whose other arm is
`projection`, and its output is the output of that document. A reference the
content is printed with starts with the `content` step of the clipboard, and
the clipboard reads its own keys before the content reads a key. The output is a
computed cell, so a toggle switches it with no new print of the content.

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
    RecursiveProjection(TypeDispatchingProjection(Pair{Type,Any}[
        (collection ? ClipboardCollection : ClipboardSlice) => clipboard,
        Any => NestingProjection(projection; recursion = IdentityProjection()),
    ]))
end

"""
    clipboard = true | (; gestures, collection)

The wrapper of `build_editor` that gives a window the clipboard and the walk of
its objects. Alt and an arrow walk the objects of the window, an Alt+click
selects one, and the clipboard copies, cuts and pastes the object that is
selected. `gestures` says which of [`CLIPBOARD_GESTURES`](@ref) the window
offers, all of them by default; a window whose documents must not be cut leaves
`:cut` out. `collection = true` keeps a collection of copies instead of one.
It is off by default. It acts around the chrome of the `shell` wrapper and the
cycle of the focus, so the walk and the clipboard reach into the bands too.
"""
# @positional: the arity of the wrapper seam of the kernel.
function wrap_editor!(::Val{:clipboard}, layer::Symbol, argument, parts::EditorParts)
    options = argument === true ? (;) : argument
    collection = get(options, :collection, false)
    parts.projection = make_clipboard_projection(SelectionWalkingProjection(inner = parts.projection);
                                                 collection,
                                                 offered_gestures = get(options, :gestures,
                                                                        CLIPBOARD_GESTURES))
    parts.document = make_clipboard_document(parts.document; collection)
    parts
end

get_wrapper_layers(::Val{:clipboard}) = (:container => 30,)
