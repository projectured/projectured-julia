"""
`Link`, the general link, and the functions of a link: its face comes from its
target and follows a rename, a place names the node that it reaches, a search
stops at a link, a link draws as a `WidgetLink` whose click opens its target, and a
save keeps the target of a link.
"""

_link_entries_place(k::Integer) =
    extend_reference(EmptyReference(), FieldReferenceStep("entries"), ElementReferenceStep(k))

function test_link()
@testset "Link" begin

@testset "a link names its target, with an alias or the name of the target that follows a rename" begin
    section = ExplorerSection("Inner", Any[])
    link = Link(section)
    @test is_link(link) && !is_link(section)
    @test get_link_target(link) === section && get_link_content(link) === nothing
    @test format_link_label(link) == "Inner"
    @test get_document_decoration(link).icon === get_document_decoration(section).icon
    @test format_tree_node_label(link) == "Inner"
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

end
end # test_link
