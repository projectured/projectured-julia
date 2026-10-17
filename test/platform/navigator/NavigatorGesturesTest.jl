# The gestures of a navigator on a page: the menu of a part on a right click,
# whose items open the part as a page or in a new tab, the menu of a part that
# has one of its own, and the keys of the navigator in the gesture help. The
# context menu window is not in these editors, so a test takes the menu from the
# answer of the click and lifts an item from its part, as the window does.

# The page of `_nav_make_linked_page`, with a part below the shelf that has a menu
# of its own.
function _nav_make_menu_page(shelf)
    page = _nav_make_linked_page(shelf)
    push!(page.children, WidgetContextMenu(WidgetLabel("Part"), WidgetMenu(Any[WidgetMenuItem("Own item")])))
    page
end

# The answer of a right click at the first drawn text `text`, after a move there.
function _nav_right_click(editor, backend, text)
    index = findlast(entry -> entry[1] == text, _nav_texts(backend))
    (_, x, y) = _nav_texts(backend)[index]
    _nav_press!(editor, backend, MouseMove(x + 2, y + 2; time = 0.0))
    click = MouseClick(:right, x + 2, y + 2, 1, ModifierKeys(); time = 0.0)
    answer = read_intent(editor.projection, nothing, Intent(click), editor.iomap).operation
    answer isa WrappingOperation ? get_wrapped_operation(answer) : answer
end

_nav_menu_items(menu) = WidgetMenuItem[item for item in menu.elements if item isa WidgetMenuItem]
_nav_item_labels(menu) = [item.action.label for item in _nav_menu_items(menu)]
_nav_find_item(menu, label) = only(filter(item -> item.action.label == label, _nav_menu_items(menu)))

# The choice of an item: the window lifts its operation from the part of the menu.
function _nav_choose!(editor, opened, item)
    evaluate_operation(editor, read_rooted_operation(editor, opened.source, item.operation))
    drain_operations!(editor)
    run_frame!(editor)
end

function test_navigator_gestures()
@testset "Navigator gestures" begin

    @testset "the menu of a part opens it as a page" begin
        shelf = _nav_make_shelf()
        navigator = Navigator(_nav_make_linked_page(shelf))
        editor, backend = _nav_editor(navigator)
        opened = _nav_right_click(editor, backend, "Shelf")
        @test opened isa OpenContextMenuOperation
        @test _nav_is(opened.source, @reference(navigator, content.children[2]))
        (title, menu) = only(opened.layers)
        @test title == "Shelf"
        @test _nav_item_labels(menu) == ["Open as a page", "Open in a new tab", "Add to explorer"]
        _nav_choose!(editor, opened, _nav_find_item(menu, "Open as a page"))
        @test get_navigator_page(navigator) === shelf
        @test length(navigator.back) == 1
    end

    @testset "the menu of a part adds it to the explorer of the editor" begin
        shelf = _nav_make_shelf()
        navigator = Navigator(_nav_make_linked_page(shelf))
        editor, backend = _nav_editor(navigator)
        opened = _nav_right_click(editor, backend, "Shelf")
        (_, menu) = only(opened.layers)
        _nav_choose!(editor, opened, _nav_find_item(menu, "Add to explorer"))
        @test last(get_session_explorer_content(; editor).entries) === shelf
        # The page stays where it was.
        @test navigator.address isa EmptyReference
    end

    @testset "the menu of a part opens it in a new tab" begin
        shelf = _nav_make_shelf()
        page = _nav_make_linked_page(shelf)
        navigator = Navigator(page)
        editor, backend = _nav_editor(navigator; tabs = true)
        opened = _nav_right_click(editor, backend, "Shelf")
        # The menu of the part is the nearest layer. The tab around the
        # navigator adds the layer of its own menu after it.
        (title, menu) = first(opened.layers)
        @test title == "Shelf"
        _nav_choose!(editor, opened, _nav_find_item(menu, "Open in a new tab"))
        tabs = _nav_tabs(editor)
        @test length(tabs) == 2
        @test tabs[2].content isa Navigator
        @test get_navigator_page(tabs[2].content) === shelf
        @test navigator.address isa EmptyReference
    end

    @testset "a part with a menu of its own: the navigator adds its menu after it" begin
        shelf = _nav_make_shelf()
        page = _nav_make_menu_page(shelf)
        navigator = Navigator(page)
        editor, backend = _nav_editor(navigator)
        opened = _nav_right_click(editor, backend, "Part")
        @test opened isa OpenContextMenuOperation
        @test length(opened.layers) == 2
        @test _nav_item_labels(opened.layers[1][2]) == ["Own item"]
        @test _nav_item_labels(opened.layers[2][2]) == ["Open as a page", "Open in a new tab"]
        # The item of the outer layer opens the part from the nearest part.
        _nav_choose!(editor, opened, _nav_find_item(opened.layers[2][2], "Open as a page"))
        @test get_navigator_page(navigator) === page.children[3].child
    end

    @testset "the gesture help lists the keys of the navigator inside a page" begin
        shelf = _nav_make_shelf()
        navigator = Navigator(_nav_make_linked_page(shelf))
        editor, backend = _nav_editor(navigator)
        evaluate_operation(editor, ReplaceSelectionOperation(@reference(navigator, content.children[2])))
        run_frame!(editor)
        collected = read_intent(editor.projection, nothing, Intent(CollectIntents()), editor.iomap).operation
        @test collected isa CollectedIntentsOperation
        descriptions = [intent.description for intent in collected.intents]
        for description in ("Go back", "Go forward", "Go to the parent page", "Open as a page")
            @test description in descriptions
        end
    end

    # A roster needs no link of its own: the menu that the navigator gives the part
    # under the pointer opens the item of a row.
    @testset "the menu of a row of a roster opens its item" begin
        chapters = _nav_vector([NavigatorTestChapter("C1", nothing), NavigatorTestChapter("C2", nothing)])
        roster = link_roster!(Roster(CollectionItems(chapters); columns = ["title"]), chapters)
        navigator = Navigator(roster)
        editor, backend = _nav_editor(navigator)
        opened = _nav_right_click(editor, backend, "C2")
        @test opened isa OpenContextMenuOperation
        menus = [menu for (title, menu) in opened.layers if "Open as a page" in _nav_item_labels(menu)]
        @test length(menus) == 1
        _nav_choose!(editor, opened, _nav_find_item(only(menus), "Open as a page"))
        @test get_navigator_page(navigator) === chapters[2]
    end
end
end
