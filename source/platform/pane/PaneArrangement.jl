# Fragment of `PaneModule` — the first arrangement of the content of a tab: the
# menu of a value in a content that nobody arranged, the operation that arranges
# a collection in such a content, and the first find in it.

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
    # The edit that puts the arrangement in the place of the content, and then
    # the caret at a path in the arrangement.
    function wrap(arrangement, caret = nothing)
        edit = ReplaceReferencedValueOperation(tab, "content", arrangement)
        caret === nothing && return edit
        CompoundOperation(Any[edit, ReplaceSelectionOperation(ConcreteReference(FieldReferenceStep("content"), caret))])
    end
    edits = make_first_arrangement_edits(content, item, wrap)
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

# Ctrl+F in the content of the focused tab, which nobody arranged: the first
# arrangement of the content, with an empty find at the collection that holds the
# selection, and the caret in the field of the find. An arranged content answers
# the key in the table of its arrangement.
function _make_first_find(tree::PaneTree)
    focus = get_pane_focus(tree)
    focus === nothing && return nothing
    (group, index) = focus
    index == 0 && return nothing
    tab = group.tabs[index]
    content = tab.content
    content isa ArrangementDocument && return nothing
    selection = find_pane_content_selection(tree)
    selection isa Reference || return nothing
    item = find_arranged_item(content, selection)
    item === nothing && return nothing
    place = get_pane_tab_reference(tree, group, index)
    place === nothing && return nothing
    (arrangement, caret) = make_first_find(content, item.at)
    CompoundOperation(Any[ReplaceReferencedValueOperation(tab, "content", arrangement),
                          ReplaceSelectionOperation(concat_references(place,
                              ConcreteReference(FieldReferenceStep("content"), caret)))])
end

# An arranged document says what it holds, and then how each collection that it
# arranges shows, as the bar of the collection says it.
describe_document(arrangement::ArrangementDocument) =
    string(describe_document(arrangement.document), "; ", describe_arrangement(arrangement))
