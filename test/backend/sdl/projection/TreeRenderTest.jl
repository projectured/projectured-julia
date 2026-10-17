# The Explorer over a folder of a thousand entries, in a pane of about ten rows.
# The folder is read once, before the view, and the view reads no disk; the
# renderer draws the rows in the pane, and only those rows build their nodes. A
# folder among them shows its chevron from what the read of its parent found.
function test_tree_render()
@testset "a tree builds the nodes of the rows it draws" begin
    SDL = ProjecturedSDL.SdlModule
    mktempdir() do dir
        for k in 1:100
            folder = joinpath(dir, string("d", lpad(k, 4, '0')))
            mkpath(folder)
            write(joinpath(folder, "x.jl"), "")
        end
        for k in 1:900
            write(joinpath(dir, string("f", lpad(k, 4, '0'), ".jl")), "")
        end
        folder = read_filesystem_folder!(make_filesystem_pathname(dir))
        pane = print_document(RecursiveProjection(FileSystemToWidget()), folder).output
        widgets = RecursiveProjection(WidgetToGraphics(StyleFont("Ubuntu", 20);
                                                       measure = FixedMeasure(8, 12, 4, 0)))
        # The tree scrolls itself in the slot that its parent offers.
        projection_module = ProjecturedKernel.ProjectionModule
        offer = projection_module.with_exact_size(projection_module.PrinterContext();
                                                  width = ProjecturedKernel.CellModule.Cell(Int32(300)),
                                                  height = ProjecturedKernel.CellModule.Cell(Int32(240)))
        canvas = print_document(widgets, nothing, pane, offer).output
        nodes = getfield(pane.roots[1].children, :elements)[]
        built_nodes() = [k for k in eachindex(nodes) if is_cell_valid(nodes[k])]
        function render()
            off = SDL.open_offscreen_renderer(800, 600; supersample = 1)
            try
                SDL._render_canvas_offscreen!(off, canvas, 800, 600, (0xff, 0xff, 0xff, 0xff))
            finally
                SDL.close_offscreen_renderer(off)
            end
        end
        @test length(folder.elements) == 1000 && length(nodes) == 1000
        @test isempty(built_nodes())

        # A row is 20 pixels high, so the pane shows the root and about twelve entries.
        render()
        shown = built_nodes()
        @test first(shown) == 1 && shown == collect(1:length(shown))
        @test 10 <= length(shown) <= 13
        # A folder that it shows reads nothing: its chevron is what the read of
        # its parent found.
        @test all(k -> folder.elements[k].state === :unread, 1:100)
        @test ProjecturedPlatform.WidgetModule._wtree_has_children(nodes[1][])

        # Scrolled to row 501, the pane shows about entries 500 to 510, and the
        # nodes between were never built.
        pane.scroll_position = Point2D(0, 20 * 500)
        render()
        scrolled = setdiff(built_nodes(), shown)
        @test !isempty(scrolled) && all(k -> 499 <= k <= 512, scrolled)
        @test length(built_nodes()) < 30
    end
end

# A node whose children are a lazy list of ten million, open in a pane of about
# twelve rows: the renderer draws the rows in the pane, and only those rows make
# their children.
@testset "a tree makes the lazy children of the rows it draws" begin
    SDL = ProjecturedSDL.SdlModule
    widget_module = ProjecturedPlatform.WidgetModule
    made = Ref(0)
    runs = ProjecturedPlatform.CollectionModule.make_index_list(10_000_000, 1,
        k -> (made[] += 1; widget_module.WidgetTreeNode("", "Run $(k - 1)", Any[])))
    sweep = widget_module.WidgetTreeNode("", "Sweep", runs; has_children = () -> true)
    tree = widget_module.WidgetTree(Any[sweep]; expanded = Set([[1]]))
    widgets = RecursiveProjection(WidgetToGraphics(StyleFont("Ubuntu", 20); measure = FixedMeasure(8, 12, 4, 0)))
    projection_module = ProjecturedKernel.ProjectionModule
    offer = projection_module.with_exact_size(projection_module.PrinterContext();
                                              width = ProjecturedKernel.CellModule.Cell(Int32(300)),
                                              height = ProjecturedKernel.CellModule.Cell(Int32(240)))
    canvas = print_document(widgets, nothing, tree, offer).output
    off = SDL.open_offscreen_renderer(800, 600; supersample = 1)
    try
        SDL._render_canvas_offscreen!(off, canvas, 800, 600, (0xff, 0xff, 0xff, 0xff))
    finally
        SDL.close_offscreen_renderer(off)
    end
    # A row is 20 pixels high, so the pane shows the node and about eleven runs.
    @test 10 <= made[] <= 14
end
end
