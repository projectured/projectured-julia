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
    clipboard = true | (; gestures, collection, to_text)

The wrapper of `build_editor` that gives a window the clipboard and the walk of
its objects. Alt and an arrow walk the objects of the window, an Alt+double click
selects one, and the clipboard copies, cuts and pastes the object that is
selected. `gestures` says which of [`CLIPBOARD_GESTURES`](@ref) the window
offers, all of them by default; a window whose documents must not be cut leaves
`:cut` out. `collection = true` keeps a collection of copies instead of one, in an
editor with no window.
`to_text` is the text that a copy of an object writes to the system clipboard,
a `Document -> String`; with none, a copy of an object leaves it as it is.
It is off by default. The walk acts in each window, around the chrome of the
`shell` wrapper and the cycle of the focus, so it reaches into the bands too. The
clipboard is one for all windows: when the editor has a window, it goes around the
screen, inside the trackers, so a copy in one window pastes in another, and it
offers no `:toggle`, because it would show the stored slice in place of the
screen. With no window, it goes around the root.
"""
function wrap_editor!(::Val{:clipboard}, layer::Symbol, argument, parts::EditorParts)
    options = argument === true ? (;) : argument
    collection = get(options, :collection, false)
    to_text = get(options, :to_text, nothing)
    gestures = get(options, :gestures, CLIPBOARD_GESTURES)
    window = is_window_made(parts)
    if layer === :container
        # The walk of the objects is the work of each window.
        walk = SelectionWalkingProjection(inner = parts.projection)
        if window
            parts.projection = walk
            return parts
        end
        # With no window, the clipboard goes around the root, with the walk inside it.
        parts.projection = make_clipboard_projection(walk; collection, to_text,
                                                     offered_gestures = gestures)
        parts.document = make_clipboard_document(parts.document; collection)
        return parts
    end
    window || return parts
    collection && throw(ArgumentError(
        "clipboard: the clipboard of a window keeps one copy, so `collection = true` needs `window = false`."))
    # One clipboard for every window of the screen: it goes around the screen,
    # inside the trackers, so a copy in one window pastes in another. It shows no
    # stored slice in place of what it wraps, because it wraps the screen.
    shared = Tuple(gesture for gesture in gestures if gesture !== :toggle)
    push!(parts.window_wrappers, (document, projection) ->
        (make_clipboard_document(document; collection),
         make_clipboard_projection(projection; collection, to_text, offered_gestures = shared)))
    parts
end

get_wrapper_layers(::Val{:clipboard}) = (:container => 30, :window => -30)
