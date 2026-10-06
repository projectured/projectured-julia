# Fragment of `NavigatorModule` — the keys of a navigator. A key reaches the table
# when the page does not answer it, so a key of the page always wins. Alt and an
# arrow walk the structure of a document, so the navigator takes Ctrl.

@gestures Navigator begin
    KeyDown(:left_bracket; ctrl) => "Go back" => make_navigator_back_operation(doc)
    KeyDown(:right_bracket; ctrl) => "Go forward" => make_navigator_forward_operation(doc)
    KeyDown(:up; ctrl) => "Go to the parent page" => make_navigator_parent_operation(doc)
    KeyDown(:return; ctrl) => "Open as a page" => _open_selected_page(doc)
end

function _open_selected_page(navigator::Navigator)
    address = find_navigator_selected_address(navigator)
    address === nothing ? nothing : make_navigator_open_operation(navigator, address)
end
