# Fragment of `NavigatorModule` — the keys of a navigator. Each key of the table is
# an `override`: it claims its chord also after the page answered it, as Back in a
# browser works on every page. A table of rows answers Return with any modifier,
# for one. No other table of the repository binds these five chords. Alt and an
# arrow walk the structure of a document, so the navigator takes Ctrl.

# The menu of a part on a page, on a right click: open the part as a page, or in
# a new tab. The part is the one under the pointer, or the selected one for a
# command with no pointer. The menu belongs to that part, so the context menu
# window lifts an item from the part through the reader of the navigator. Each
# item names the content of the navigator as its root, so it opens the same page
# also from the menu of a part inside the page, which F2 shows.
#
# The side buttons of the mouse go back and forward, wherever the pointer is on
# the navigator, as in a browser.
const _NAVIGATOR_POINTER_BINDINGS = GestureBinding[
    GestureBinding(MouseClickPattern(:right),
                   (navigator, gesture) -> _make_part_menu_operation(navigator, gesture);
                   description = "Show the menu of the part as a page", domain = "context menu",
                   name = "Show the menu of the part as a page"),
    GestureBinding(MouseClickPattern(:back), (navigator, gesture) -> make_navigator_back_operation(navigator);
                   description = "Go back", domain = "navigator"),
    GestureBinding(MouseClickPattern(:forward), (navigator, gesture) -> make_navigator_forward_operation(navigator);
                   description = "Go forward", domain = "navigator")]

@gestures Navigator begin
    override(KeyDown(:left_bracket; ctrl)) => "Go back" => make_navigator_back_operation(doc)
    override(KeyDown(:right_bracket; ctrl)) => "Go forward" => make_navigator_forward_operation(doc)
    override(KeyDown(:up; ctrl)) => "Go to the parent page" => make_navigator_parent_operation(doc)
    override(KeyDown(:return; ctrl)) => "Open as a page" => _open_selected_page(doc)
    override(KeyDown(:l; ctrl)) => "Edit the address" => make_navigator_address_edit_operation(doc)
    splice(_NAVIGATOR_POINTER_BINDINGS)
end

function _open_selected_page(navigator::Navigator)
    address = find_navigator_selected_address(navigator)
    address === nothing ? nothing : make_navigator_open_operation(navigator, address)
end

function _make_part_menu_operation(navigator::Navigator, gesture)
    path = gesture isa MouseClick ? get_mouse_target(navigator) : navigator.selection
    address = _find_part_address(navigator, path)
    address === nothing && return nothing
    content = navigator.content
    menu = WidgetMenu(Any[
        WidgetMenuItem("Open as a page"; operation = OpenPageOperation(content, address)),
        WidgetMenuItem("Open in a new tab"; operation = OpenPageOperation(content, address, :new_tab))])
    part = evaluate_reference(content, address)
    # The part of the menu is the part under the pointer, with the types of its
    # nodes, as a place that a reader can follow down.
    source = annotate_reference_types(navigator, ConcreteReference(_CONTENT_STEP, address))
    opened = make_context_menu_operation(part, menu, gesture)
    rewrap_operation(opened, retarget_operation(get_wrapped_operation(opened), source))
end
