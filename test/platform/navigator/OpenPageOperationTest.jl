# The open of a page: the operation that a link answers, the navigator that takes
# it from its page, and the tab that opens for one that no navigator takes. The
# content is the shelf of `NavigatorVisitsTest.jl`, and the editor is the one of
# `NavigatorToWidgetTest.jl`.

# A page with a link above the shelf: a press on "Open B" opens the second book,
# and Ctrl+press opens it in a new tab. The link names the book from the root of
# the page, which carries it.
function _nav_make_linked_page(shelf)
    page = Ref{Any}(nothing)
    path = Reference(FieldReferenceStep("children"), ElementReferenceStep(2),
                     FieldReferenceStep("books"), ElementReferenceStep(2))
    open(place) = (_, _) -> OpenPageOperation(page[], path, place)
    link = WidgetButton("Open B"; gestures = GestureBinding[
        GestureBinding(MouseClickPattern(:left; modifiers = Symbol[]), open(:here);
                       description = "Open", domain = "test"),
        GestureBinding(MouseClickPattern(:left; modifiers = [:ctrl]), open(:new_tab);
                       description = "Open in a new tab", domain = "test")])
    page[] = VerticalLayout(Any[link, shelf])
    page[]
end

_nav_ctrl_click(click) = MouseClick(click.button, click.x, click.y, 1, ModifierKeys(ctrl = true); time = 0.0)

_nav_tabs(editor) = editor.document.root.tabs

function test_open_page_operation()
@testset "OpenPageOperation" begin

    @testset "the path form goes up as a path, the other form as it is" begin
        shelf = _nav_make_shelf()
        steps = (FieldReferenceStep("content"),)
        path = OpenPageOperation(nothing, Reference(FieldReferenceStep("books"), ElementReferenceStep(2)))
        @test path.place === :here
        @test !is_self_contained_operation(path)
        rerooted = reroot_operation(path, steps)
        @test rerooted isa OpenPageOperation && rerooted.place === :here
        @test _nav_is(rerooted.reference,
                      Reference(FieldReferenceStep("content"), FieldReferenceStep("books"), ElementReferenceStep(2)))
        own = OpenPageOperation(shelf, @reference(shelf, books[2]), :new_tab)
        @test is_self_contained_operation(own)
        @test reroot_operation(own, steps) === own
    end

    @testset "an object on the address, or elsewhere" begin
        shelf = _nav_make_shelf()
        navigator = Navigator(shelf, @reference(shelf, books[1]))
        holder = _NavHolder(navigator)
        # A document on the address: the page is a path from the content.
        _nav_apply!(holder, make_navigator_open_operation(navigator, shelf.books[1],
                                                          @reference(shelf.books[1], chapters[2])))
        @test navigator.content === shelf
        @test _nav_is(navigator.address, @reference(shelf, books[1].chapters[2]))
        # Any other document becomes the content of the visit, and Back returns.
        other = NavigatorTestChapter("Elsewhere", nothing)
        _nav_apply!(holder, make_navigator_open_operation(navigator, other, EmptyReference()))
        @test navigator.content === other
        @test navigator.address isa EmptyReference
        @test find_navigator_parent_address(navigator) === nothing
        _nav_apply!(holder, make_navigator_back_operation(navigator))
        @test navigator.content === shelf
        @test _nav_is(navigator.address, @reference(shelf, books[1].chapters[2]))
        # A path that reaches no node opens nothing.
        @test make_navigator_open_operation(navigator, other, @reference(shelf, books[9])) === nothing
    end

    # An open that a part answers at its own place, as a verb of the assistant
    # does: the route ends at the shelf, which the layout of the page holds.
    @testset "a navigator takes an open from its page" begin
        shelf = _nav_make_shelf()
        page = _nav_make_linked_page(shelf)
        navigator = Navigator(page)
        editor, backend = _nav_editor(navigator)
        answer = read_rooted_operation(editor, @reference(navigator, content.children[2]),
                                       OpenPageOperation(nothing, EmptyReference()))
        @test !(answer isa OpenPageOperation)
        evaluate_operation(editor, answer)
        run_frame!(editor)
        @test get_navigator_page(navigator) === shelf
        @test _nav_is(navigator.selection, @reference(navigator, content.children[2]))
        @test _nav_has_texts(backend, "VerticalLayout", "›", "Shelf")
    end

    @testset "a press on a link opens its page, and Ctrl+press a new tab" begin
        shelf = _nav_make_shelf()
        page = _nav_make_linked_page(shelf)
        navigator = Navigator(page)
        editor, backend = _nav_editor(navigator; tabs = true)
        click = _nav_click(backend, "Open B")
        @test click !== nothing
        _nav_press!(editor, backend, _nav_ctrl_click(click))
        drain_operations!(editor)
        run_frame!(editor)
        tabs = _nav_tabs(editor)
        @test length(tabs) == 2
        opened = tabs[2].content
        @test opened isa Navigator
        @test opened.content === page
        @test get_navigator_page(opened) === shelf.books[2]
        @test navigator.address isa EmptyReference

        # The new tab took the focus. The press of the link in the first tab opens
        # the book there.
        evaluate_operation(editor, ReplaceSelectionOperation(@reference(editor.document, root.tabs[1])))
        run_frame!(editor)
        click = _nav_click(backend, "Open B")
        @test click !== nothing
        _nav_press!(editor, backend, click)
        @test get_navigator_page(navigator) === shelf.books[2]
        @test length(_nav_tabs(editor)) == 2
    end

    @testset "an open that no navigator takes opens a navigator tab" begin
        shelf = _nav_make_shelf()
        page = _nav_make_linked_page(shelf)
        editor, backend = _nav_editor(page; tabs = true)
        answer = read_rooted_operation(editor, @reference(editor.document, root.tabs[1].content.children[2]),
                                       OpenPageOperation(nothing, EmptyReference()))
        @test answer isa OpenPageOperation
        evaluate_operation(editor, answer)
        drain_operations!(editor)
        run_frame!(editor)
        tabs = _nav_tabs(editor)
        @test length(tabs) == 2
        opened = tabs[2].content
        @test opened isa Navigator
        # The content is the document of the tab, so Parent reaches the page.
        @test opened.content === page
        @test get_navigator_page(opened) === shelf
        @test _nav_is(find_navigator_parent_address(opened), EmptyReference())
        @test _nav_has_texts(backend, "VerticalLayout", "›", "Shelf")
    end
end
end
