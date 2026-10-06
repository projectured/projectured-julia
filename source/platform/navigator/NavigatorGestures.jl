# Fragment of `NavigatorModule` — the keys of a navigator. A key reaches the table
# when the page does not answer it, so a key of the page always wins. Alt and an
# arrow walk the structure of a document, so the navigator takes Ctrl.

# The menu of a part on a page, on a right click: open the part as a page, or in
# a new tab. The part is the one under the pointer, or the selected one for a
# command with no pointer. The menu belongs to that part, so the context menu
# window lifts an item from the part through the reader of the navigator. Each
# item names the content of the navigator as its root, so it opens the same page
# also from the menu of a part inside the page, which F2 shows.
const _NAVIGATOR_MENU_BINDINGS = GestureBinding[
    GestureBinding(MouseClickPattern(:right),
                   (navigator, gesture) -> _make_part_menu_operation(navigator, gesture);
                   description = "Show the menu of the part as a page", domain = "context menu",
                   name = "Show the menu of the part as a page")]

@gestures Navigator begin
    KeyDown(:left_bracket; ctrl) => "Go back" => make_navigator_back_operation(doc)
    KeyDown(:right_bracket; ctrl) => "Go forward" => make_navigator_forward_operation(doc)
    KeyDown(:up; ctrl) => "Go to the parent page" => make_navigator_parent_operation(doc)
    KeyDown(:return; ctrl) => "Open as a page" => _open_selected_page(doc)
    splice(_NAVIGATOR_MENU_BINDINGS)
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
