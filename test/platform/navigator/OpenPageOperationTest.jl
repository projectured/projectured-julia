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

# A content of two parts, a home page and the shelf, whose domain resolves the
# target `#title` of a link to the book of that title, and the name of a file in
# `folder` to the path of that file.
@document struct NavigatorTestSite
    home::Any
    shelf::Any
    folder::String = ""
end

function ProjecturedPlatform.NavigatorModule.find_navigator_target(site::NavigatorTestSite, target::AbstractString)
    file = joinpath(site.folder, target)
    !isempty(site.folder) && isfile(file) && return file
    startswith(target, "#") || return nothing
    index = findfirst(book -> book.title == target[2:end], collect(site.shelf.books))
    index === nothing ? nothing :
        Reference(FieldReferenceStep("shelf"), FieldReferenceStep("books"), RangeReferenceStep(index - 1, index))
end

_nav_make_site(shelf; folder = "") = NavigatorTestSite(_nav_make_linked_page(_nav_make_shelf()), shelf, folder, nothing)

# A file of the test domain around a document, as a file tab holds one.
@document struct NavigatorTestFile <: FileDocument
    filename::String
    content::Any
end

_nav_link(target; place = :here) = OpenPageOperation(nothing, EmptyReference(), place; target)

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
        @test _nav_has_texts(backend, "VerticalLayout", _NAV_CHOICES, "Shelf")
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
        @test _nav_has_texts(backend, "VerticalLayout", _NAV_CHOICES, "Shelf")
    end

    @testset "a link to a target: the domain of the content resolves it" begin
        @test find_navigator_target(_nav_make_shelf(), "#B") === nothing
        @test _nav_link("#B").target == "#B"
        @test retarget_operation(_nav_link("#B"), Reference(FieldReferenceStep("home"))).target == "#B"
        @test describe_operation(_nav_link("#B")) == "Follow the link to #B"
        shelf = _nav_make_shelf()
        site = _nav_make_site(shelf)
        navigator = Navigator(site, @reference(site, home))
        editor, backend = _nav_editor(navigator)
        place = @reference(navigator, content.home.children[2])
        evaluate_operation(editor, read_rooted_operation(editor, place, _nav_link("#B")))
        run_frame!(editor)
        @test get_navigator_page(navigator) === shelf.books[2]
        @test length(navigator.back) == 1
        # A target that names nothing here is answered, and opens nothing.
        _nav_apply!(_NavHolder(navigator), make_navigator_back_operation(navigator))
        answer = read_rooted_operation(editor, place, _nav_link("https://example.org"))
        @test answer !== nothing
        evaluate_operation(editor, answer)
        @test get_navigator_page(navigator) === site.home
    end

    @testset "a link to a target in a new tab, and with no navigator" begin
        shelf = _nav_make_shelf()
        site = _nav_make_site(shelf)
        navigator = Navigator(site, @reference(site, home))
        editor, backend = _nav_editor(navigator; tabs = true)
        place = @reference(editor.document, root.tabs[1].content.content.home.children[2])
        evaluate_operation(editor, read_rooted_operation(editor, place, _nav_link("#A"; place = :new_tab)))
        drain_operations!(editor)
        run_frame!(editor)
        tabs = _nav_tabs(editor)
        @test length(tabs) == 2
        @test tabs[2].content.content === site
        @test get_navigator_page(tabs[2].content) === shelf.books[1]
        @test get_navigator_page(navigator) === site.home
        # With no navigator, the editor resolves the target against the document of
        # the tab that holds the link.
        shelf = _nav_make_shelf()
        site = _nav_make_site(shelf)
        editor, backend = _nav_editor(site; tabs = true)
        link = OpenPageOperation(nothing, @reference(editor.document, root.tabs[1].content.home); target = "#B")
        evaluate_operation(editor, link)
        drain_operations!(editor)
        run_frame!(editor)
        tabs = _nav_tabs(editor)
        @test length(tabs) == 2
        @test tabs[2].content.content === site
        @test get_navigator_page(tabs[2].content) === shelf.books[2]
    end

    @testset "a target that names a file opens it with a navigator, in a history with settings" begin
        folder = mktempdir()
        path = joinpath(folder, "notes.txt")
        write(path, "hello")
        site = _nav_make_site(_nav_make_shelf(); folder)
        navigator = Navigator(site, @reference(site, home))
        editor, backend = _nav_editor(navigator)
        answer = read_rooted_operation(editor, @reference(navigator, content.home.children[2]), _nav_link("notes.txt"))
        @test answer isa OpenFileOperation && answer.path == path
        @test answer.file_wrap(PrimitiveString("x")) isa Navigator
        # The navigator holds the file, and an editor with settings puts a history
        # around the navigator, so it records the edits of every page.
        for (settings, has_history) in ((make_settings(), true), (false, false))
            editor = build_editor(_nav_make_shelf(), _nav_natural(); backend = HeadlessBackend(),
                                  devices = Device[Keyboard(), Mouse(), Display()], window = false, tabs = true,
                                  appearance = false, settings)
            run_frame!(editor)
            evaluate_operation(editor, answer)
            drain_operations!(editor)
            run_frame!(editor)
            found = only(search_documents(editor.document, node -> node isa Navigator && node.content isa TextFile))
            @test found.content.filename == path
            buffers = search_documents(editor.document, node -> node isa UndoBuffer && node.content === found)
            @test length(buffers) == (has_history ? 1 : 0)
        end
    end

    @testset "a navigator that an open makes from a file tab keeps the file as its content" begin
        shelf = _nav_make_shelf()
        file = NavigatorTestFile("shelf.txt", shelf, nothing)
        editor, backend = _nav_editor(file; tabs = true)
        open = OpenPageOperation(nothing, @reference(editor.document, root.tabs[1].content.content.books[2]))
        evaluate_operation(editor, open)
        drain_operations!(editor)
        run_frame!(editor)
        opened = _nav_tabs(editor)[2].content
        @test opened.content === file
        @test get_navigator_page(opened) === shelf.books[2]
    end
end
end
