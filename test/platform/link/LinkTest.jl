"""
`Link`, the general link, and the functions of a link: its face comes from its
target and follows a rename, a place names the node that it reaches, a search
stops at a link, a link draws as a `WidgetLink` whose click opens its target, and a
save keeps the target of a link.
"""

_link_entries_place(k::Integer) =
    extend_reference(EmptyReference(), FieldReferenceStep("entries"), ElementReferenceStep(k))

_url_pieces(url::Url) = (url.scheme, url.userinfo, url.host, url.port, url.path, url.query, url.fragment)

# Addresses and their pieces: scheme, userinfo, host, port, path, query, fragment.
const _URL_CASES = [
    "https://julialang.org" => ("https", nothing, "julialang.org", nothing, "", nothing, nothing),
    "http://u:p@[::1]:8080/a?b#c" => ("http", "u:p", "[::1]", "8080", "/a", "b", "c"),
    "mailto:someone@example.org" => ("mailto", nothing, nothing, nothing, "someone@example.org", nothing, nothing),
    "file:///tmp/a%20b.txt" => ("file", nothing, "", nothing, "/tmp/a%20b.txt", nothing, nothing),
    "#install" => (nothing, nothing, nothing, nothing, "", nothing, "install"),
    "guide.md?" => (nothing, nothing, nothing, nothing, "guide.md", "", nothing),
    "ug:cha:queueing" => ("ug", nothing, nothing, nothing, "cha:queueing", nothing, nothing),
    "1x:y" => (nothing, nothing, nothing, nothing, "1x:y", nothing, nothing),
    "" => (nothing, nothing, nothing, nothing, "", nothing, nothing),
    "//host/p" => (nothing, nothing, "host", nothing, "/p", nothing, nothing),
    "http://h:/" => ("http", nothing, "h", "", "/", nothing, nothing),
    "HTTP://Example.ORG:080/A%2fB?x=1&y=2#" => ("HTTP", nothing, "Example.ORG", "080", "/A%2fB", "x=1&y=2", ""),
    "../a?b#c?d#e" => (nothing, nothing, nothing, nothing, "../a", "b", "c?d#e"),
    "urn:isbn:0451450523" => ("urn", nothing, nothing, nothing, "isbn:0451450523", nothing, nothing),
    "http://a@b@c/" => ("http", "a@b", "c", nothing, "/", nothing, nothing),
    "line\nbreak#é" => (nothing, nothing, nothing, nothing, "line\nbreak", nothing, "é"),
]

function test_link()
@testset "Link" begin

@testset "a link names its target, with an alias or the name of the target that follows a rename" begin
    section = ExplorerSection("Inner", Any[])
    link = Link(section)
    @test is_link(link) && !is_link(section)
    @test get_link_target(link) === section && get_link_content(link) === nothing
    @test format_link_label(link) == "Inner"
    @test get_document_decoration(link).icon === get_document_decoration(section).icon
    @test format_tree_node_label(link) == "Inner" && get_document_title(link) == "Inner"
    evaluate_operation(nothing, ReplaceReferencedValueOperation(section, "title", "Outer"))
    @test format_link_label(link) == "Outer"
    @test format_link_label(Link(section; content = "my list")) == "my list"
    @test !is_link_broken(link)
end

@testset "a place names the node that it reaches, and a place that reaches nothing is broken" begin
    section = ExplorerSection("Inner", Any[ExplorerSection("beta", Any[])])
    reached = Link(DocumentLocator(section, _link_entries_place(1)))
    @test format_link_label(reached) == "beta"
    @test describe_link(reached) == "beta in Inner"
    @test !is_link_broken(reached)
    gone = Link(DocumentLocator(section, _link_entries_place(9)))
    @test is_link_broken(gone)
    @test format_link_label(gone) == "?"
    @test startswith(describe_link(gone), "Nothing at")
end

@testset "a search of a note finds the alias of its link and reads nothing of what the link names" begin
    rows = CellVector(Cell[Cell("row $k") for k in 1:20_000])
    note = ExplorerSection("Notes", Any[Link(rows; content = "the big list")])
    visited = Ref(0)
    search_documents(note, node -> (visited[] += 1; false))
    @test visited[] < 100
    @test !isempty(search_documents(note, "the big list"))
    @test isempty(search_documents(note, "row 7"))
end

@testset "a link draws as a WidgetLink: its face, a line under the pointer, and a click that opens its target" begin
    section = ExplorerSection("Inner", Any[])
    link = Link(section)
    natural = NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0))
    backend = HeadlessBackend()
    # A layout around the link gives the move of the pointer to the part at the point.
    editor = build_editor(VerticalLayout(Any[link]), natural; backend, devices = Device[Keyboard(), Mouse(), Display()],
                          window = false, tabs = false, appearance = false, settings = false)
    run_frame!(editor)
    drawing() = last(rendered_output(backend))
    @test "Inner" in _arrangement_texts(backend)
    (x, y) = _arrangement_place(backend, "Inner")
    _arrangement_press!(editor, backend, MouseMove(x, y; time = 0.0))
    @test is_link_text_underlined(drawing(), "Inner")
    click = MouseClick(:left, x, y, 1, ModifierKeys(); time = 0.1)
    answer = read_intent(editor.projection, nothing, Intent(click), editor.iomap).operation
    opened = answer isa WrappingOperation ? get_wrapped_operation(answer) : answer
    @test opened isa OpenPageOperation && opened.document === section && opened.place === :here
    # The face follows a rename of the target.
    evaluate_operation(editor, ReplaceReferencedValueOperation(section, "title", "Outer"))
    run_frame!(editor)
    @test "Outer" in _arrangement_texts(backend) && !("Inner" in _arrangement_texts(backend))
end

@testset "a save keeps a link to a node of the same file, of another file, and to a node that only the link holds" begin
    directory = mktempdir()
    # A file writes a node that it holds at two places once, and a marker at the link.
    node = ExplorerSection("Kept", Any[])
    file = PredFile("same.pred", ExplorerSection("Notes", Any[node, Link(node)]))
    @test occursin("node(file(\"same.pred\")", cut_file_text(file, directory))
    save_file!(file, directory)
    read = get_file_content(load_file(directory, "same.pred"))
    @test read.entries[2] isa Link && read.entries[2].target === read.entries[1]
    # A node that only the link holds is written under the link.
    save_file!(PredFile("alone.pred", ExplorerSection("Notes", Any[Link(ExplorerSection("Only", Any[]))])), directory)
    alone = get_file_content(load_file(directory, "alone.pred"))
    @test alone.entries[1].target isa ExplorerSection && String(alone.entries[1].target.title) == "Only"
    far = ExplorerSection("Far", Any[])
    project = FileProject(directory, Any[PredFile("a.pred", ExplorerSection("A", Any[far])),
                                         PredFile("b.pred", ExplorerSection("B", Any[Link(far)]))])
    @test save_project!(project)
    loaded = load_project(directory, ["a.pred", "b.pred"])
    files = Dict(file.filename => get_file_content(file) for file in loaded.files)
    @test files["b.pred"].entries[1].target === files["a.pred"].entries[1]
end

@testset "an address holds its pieces as written, and prints back the same text" begin
    for (text, pieces) in _URL_CASES
        url = Url(text)
        @test _url_pieces(url) == pieces
        @test format_url(url) == text
    end
    # Any text reads and prints back the same, an address or not.
    letters = collect(":/?#@[]a1.%")
    for _ in 1:2000
        text = String(rand(letters, rand(0:12)))
        @test format_url(Url(text)) == text
    end
    @test format_url(Url(; scheme = "https", host = "julialang.org", path = "/learning")) ==
          "https://julialang.org/learning"
    @test find_web_url("MAILTO:a@b") isa Url && find_web_url("https://x").host == "x"
    @test find_web_url("ug:cha:queueing") === nothing && find_web_url("guide.md") === nothing
    @test find_url_file_path(Url("FILE:///x")) == "/x" && find_url_file_path(Url("file:///a?b")) == "/a"
    @test find_url_file_path(Url("file:notes.txt")) === nothing
end

@testset "an edit of the text or of one piece writes the pieces that change, in the same Url" begin
    url = Url("https://julialang.org")
    link = Link(url)
    edit = make_url_text_operation(url, "https://julialang.org/learning?lang=en")
    @test edit isa CompoundOperation && length(edit.operations) == 2
    evaluate_operation(nothing, edit)
    @test url.path == "/learning" && url.query == "lang=en" && link.target === url
    @test make_url_text_operation(url, format_url(url)) === nothing
    # A delimiter in a piece moves its text into the next piece.
    evaluate_operation(nothing, make_url_piece_operation(url, :host, "julia.org/docs"))
    @test url.host == "julia.org" && url.path == "/docs/learning"
    evaluate_operation(nothing, make_url_piece_operation(url, :query, nothing))
    @test format_url(url) == "https://julia.org/docs/learning"
    # A port gives an address with no host the host "", and its path a "/".
    relative = Url("guide.md")
    evaluate_operation(nothing, make_url_piece_operation(relative, :port, "8080"))
    @test format_url(relative) == "//:8080/guide.md" && relative.host == ""
    @test_throws ArgumentError make_url_piece_operation(url, :address, "x")
end

@testset "a save keeps the pieces of an address" begin
    directory = mktempdir()
    save_file!(PredFile("url.pred", ExplorerSection("Links", Any[Url("http://u@h:1/p?q#f"), Url("#install")])),
               directory)
    read = get_file_content(load_file(directory, "url.pred"))
    @test format_url(read.entries[1]) == "http://u@h:1/p?q#f" && read.entries[1].port == "1"
    @test read.entries[2].host === nothing && read.entries[2].fragment == "install"
end

@testset "an address is a link to itself: a relative one opens through its page, an absolute one outside the editor" begin
    web = Url("https://julialang.org")
    @test is_link(web) && get_link_target(web) === web
    @test format_link_label(web) == "https://julialang.org" && describe_link(web) == "https://julialang.org"
    @test get_document_decoration(web).icon === :external_link
    @test is_absolute_url(web) && is_absolute_url(Url("mailto:someone@example.org")) && !is_absolute_url(Url("#install"))
    opened = make_target_open_operation(web, :here)
    @test opened isa OpenUrlOperation && opened.url === web
    relative = make_target_open_operation(Url("#install"), :new_tab)
    @test relative isa OpenPageOperation && relative.target == "#install" && relative.place === :new_tab
    @test find_url_file_path(Url("file:///tmp/a%20b.txt")) == "/tmp/a b.txt"
    @test find_url_file_path(Url("file://host/srv/x.md")) == "/srv/x.md" && find_url_file_path(web) === nothing
    # A widget keeps an address as a locator of it, and its click still opens it outside.
    @test make_target_open_operation(WidgetLink("Julia", web).target, :here) isa OpenUrlOperation
    @test format_link_label(Link(web; content = "Julia")) == "Julia" && format_link_label(Link(web)) == "https://julialang.org"
    @test !open_url!(nothing, "https://julialang.org")
    # Any content of a navigator resolves an address outside the editor, which needs
    # no page; a name stays for the domain of the content.
    @test find_navigator_target(ExplorerSection("Home", Any[]), "https://julialang.org") isa Url
    @test find_navigator_target(ExplorerSection("Home", Any[]), "#install") === nothing
end

@testset "an address draws as a link whose click opens it outside the editor, and its page offers its open" begin
    web = Url("https://julialang.org")
    natural = NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0))
    backend = HeadlessBackend()
    editor = build_editor(VerticalLayout(Any[web]), natural; backend, devices = Device[Keyboard(), Mouse(), Display()],
                          window = false, tabs = false, appearance = false, settings = false)
    run_frame!(editor)
    @test "https://julialang.org" in _arrangement_texts(backend)
    (x, y) = _arrangement_place(backend, "https://julialang.org")
    answer = read_intent(editor.projection, nothing, Intent(MouseClick(:left, x, y, 1, ModifierKeys(); time = 0.0)),
                         editor.iomap).operation
    @test (answer isa WrappingOperation ? get_wrapped_operation(answer) : answer) isa OpenUrlOperation
    # The page of the address, as "Open as a page" opens it: a visit makes the
    # view of the page, the address and the command that opens it.
    navigator = Navigator(ExplorerSection("Home", Any[web]))
    page_editor, page_backend = _nav_editor(navigator)
    evaluate_operation(page_editor, make_navigator_open_operation(navigator, web, EmptyReference()))
    run_frame!(page_editor)
    @test get_navigator_page_view(navigator) isa UrlView
    @test _nav_has_text(page_backend, "https://julialang.org") && _nav_has_text(page_backend, "Open in the browser")
    press = _nav_click(page_backend, "Open in the browser")
    pressed = read_intent(page_editor.projection, nothing, Intent(press), page_editor.iomap).operation
    @test (pressed isa WrappingOperation ? get_wrapped_operation(pressed) : pressed) isa OpenUrlOperation
end

@testset "the editor opens a file address in a tab, and a web address through its backend" begin
    path = joinpath(mktempdir(), "notes.txt")
    write(path, "hello\n")
    navigator = Navigator(ExplorerSection("Home", Any[]))
    editor, backend = _nav_editor(navigator; tabs = true)
    before = length(_nav_tabs(editor))
    evaluate_operation(editor, OpenUrlOperation(Url("file://" * path)))
    drain_operations!(editor)
    run_frame!(editor)
    @test length(_nav_tabs(editor)) == before + 1
    # A backend with no system to open it in opens nothing, and the editor says so.
    @test_logs (:warn, "No program of the system opened the address.") match_mode = :any evaluate_operation(
        editor, OpenUrlOperation(Url("https://julialang.org")))
end

end
end # test_link
