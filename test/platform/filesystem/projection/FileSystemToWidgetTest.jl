# The file tree names a file's kind with an icon, and the kinds a study folder
# holds — a `.pred` document, a NED network, an INI configuration, a `.math`
# formula — each have their own, so a person reads the folder at a glance.
function test_filesystem_to_widget()
@testset "FileSystemToWidget glyphs" begin
    icon(name) = ProjecturedPlatform.FileSystemModule._fs_icon(FileSystemFile("/study/" * name))
    glyphs = Dict(name => icon(name) for name in
                  ("study.pred", "MM1K.ned", "omnetpp.ini", "closed.math",
                   "script.jl", "study.md", "data.json", "result.sca"))
    # Four kinds of the study folder, each its own.
    @test glyphs["study.pred"] === :diamond
    @test glyphs["MM1K.ned"] === :hexagon
    @test glyphs["omnetpp.ini"] === :file_sliders
    @test glyphs["closed.math"] === :sigma
    # The kinds that had one keep it, and a kind nobody named is a plain file.
    @test glyphs["script.jl"] === :lambda
    @test glyphs["study.md"] === :pilcrow
    @test glyphs["result.sca"] === :file
    # No two named kinds share a glyph, or the glyph says nothing.
    named = [glyphs[n] for n in ("study.pred", "MM1K.ned", "omnetpp.ini", "closed.math",
                                 "script.jl", "study.md", "data.json")]
    @test allunique(named)
    # Every kind is an icon the widget layer draws.
    @test all(name -> ProjecturedPlatform.WidgetModule.find_icon_character(name) !== nothing,
              values(glyphs))
    # The case of the extension does not matter.
    @test icon("NETWORK.NED") === :hexagon
end

# The tree opens its root and shows each entry under it closed. A click on the
# chevron of a folder opens it, and a second click closes it.
@testset "FileSystemToWidget opens the first level" begin
    mktempdir() do dir
        mkpath(joinpath(dir, "full", "inner"))
        write(joinpath(dir, "full", "a.jl"), "")
        write(joinpath(dir, "top.jl"), "")
        tree = print_document(RecursiveProjection(FileSystemToWidget()), make_filesystem_pathname(dir)).output
        @test tree.expanded == Set([[1]])
        widgets = WidgetToGraphics(StyleFont("Ubuntu", 20); measure = FixedMeasure(8, 12, 4, 0))
        tree_projection = only(pr for (T, pr) in widgets.dispatch if T === WidgetTree)
        iomap = print_document(tree_projection, tree)
        @test [r.path for r in iomap.geometry.rows] == [[1], [1, 1], [1, 2]]

        function click_chevron!(row)
            press = MouseClick(:left, (row.chevron_x0 + row.chevron_x1) ÷ 2, row.y0 + 2,
                               ModifierKeys(); time = 0.0)
            operation = read_intent(tree_projection, iomap, press)
            operation isa ReplaceViewStateOperation && (operation = get_wrapped_operation(operation))
            getfield(tree, :expanded)[] = operation.value
        end
        click_chevron!(iomap.geometry.rows[2])
        @test [1, 1] in tree.expanded
        @test [r.path for r in iomap.geometry.rows] == [[1], [1, 1], [1, 1, 1], [1, 1, 2], [1, 2]]
        click_chevron!(iomap.geometry.rows[2])
        @test [r.path for r in iomap.geometry.rows] == [[1], [1, 1], [1, 2]]
    end
end

# The tree opens its root, and shows each entry under it closed. It reads the
# listing of the root, and of each folder it shows, to know if the folder has a
# chevron; it reads nothing below them.
@testset "FileSystemToWidget reads the folders it shows" begin
    mktempdir() do dir
        mkpath(joinpath(dir, "full", "inner"))
        write(joinpath(dir, "full", "a.jl"), "")
        mkpath(joinpath(dir, "none"))
        write(joinpath(dir, "top.jl"), "")
        folder = make_filesystem_pathname(dir)
        tree = print_document(RecursiveProjection(FileSystemToWidget()), folder).output
        widgets = WidgetToGraphics(StyleFont("Ubuntu", 20); measure = FixedMeasure(8, 12, 4, 0))
        tree_projection = only(pr for (T, pr) in widgets.dispatch if T === WidgetTree)
        iomap = print_document(tree_projection, tree)
        is_listing_read(d) = is_cell_up_to_date(getfield(d.elements, :elements))

        # The rows are made from the listing of the root, and read no entry.
        @test [r.path for r in iomap.geometry.rows] == [[1], [1, 1], [1, 2], [1, 3]]
        @test is_listing_read(folder)
        @test !any(is_cell_up_to_date, getfield(folder.elements, :elements)[])

        # Draw the rows, as the renderer does: a row reads its node, and a folder
        # row reads the listing of its folder to know if it has a chevron.
        rows_canvas = only(el for el in iomap.output.elements
                           if el isa GraphicsCanvas && el.layout == layout_vertical)
        foreach(row -> collect(row.elements), rows_canvas.elements)
        full = folder.elements[1]
        @test is_listing_read(full) && is_listing_read(folder.elements[2])
        @test !is_listing_read(full.elements[2])            # `inner`, not shown

        node(path) = ProjecturedPlatform.WidgetModule._wtree_node_at(tree, path)
        has_children(path) = ProjecturedPlatform.WidgetModule._wtree_has_children(node(path))
        @test [node([1, k]).label for k in 1:3] == ["full", "none", "top.jl"]
        @test [1] in tree.expanded && !([1, 1] in tree.expanded)
        # A folder with entries has a chevron, and an empty folder has none.
        @test has_children([1, 1]) && !has_children([1, 2]) && !has_children([1, 3])
    end
end
end
