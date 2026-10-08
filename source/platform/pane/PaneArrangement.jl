# Fragment of `PaneModule` — the first arrangement of the content of a tab: the
# menu of a value in a content that nobody arranged, and the operation that
# arranges a collection in such a content.

# The menu of the value under the pointer in a tab whose content nobody
# arranged: the edits that filter or sort the collection that holds the value,
# each of which puts the first `ArrangementDocument` around the content of the
# tab. An arranged content has the menu of its own arrangement instead.
get_document_gesture_bindings_own(::Type{<:PaneTab}) =
    GestureBinding[make_context_menu_binding(_make_first_arrangement_menu;
                                             description = "Show the arrangement menu")]

function _make_first_arrangement_menu(tab::PaneTab)
    content = tab.content
    content isa ArrangementDocument && return nothing
    path = get_mouse_target(tab)
    path isa Reference || return nothing
    rest = @reference_case strip_reference_types(path) begin
        content.rest... => rest
        __ => nothing
    end
    rest === nothing && return nothing
    item = find_arranged_item(content, rest)
    item === nothing && return nothing
    edits = make_first_arrangement_edits(content, item,
        arrangement -> ReplaceReferencedValueOperation(tab, "content", arrangement))
    WidgetMenu(Any[WidgetMenuItem(label; operation) for (label, operation) in edits])
end

# A collection in the content of a tab that nobody arranged: the first
# arrangement of the content goes in its place. The reader of an arranged content
# answers the operation itself, so it comes here only from a content that nobody
# arranged.
function read_intent(p::PaneTreeToWidget, iomap::PaneTreeToWidgetIoMap, operation::ArrangeCollectionOperation)
    path = map_reference_backward(p, iomap, operation.at)
    path isa Reference || return nothing
    path = strip_reference_types(path)
    (steps, tab) = _walk_pane_path(iomap.input, path)
    (tab === nothing || tab.content isa ArrangementDocument) && return nothing
    at = extend_reference(EmptyReference(), collect(get_reference_steps(path))[length(steps) + 1:end]...)
    arrangement = make_first_arrangement(tab.content, ArrangeCollectionOperation(at, operation.description))
    arrangement === nothing ? nothing : ReplaceReferencedValueOperation(tab, "content", arrangement)
end
