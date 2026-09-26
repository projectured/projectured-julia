# The Explorer over a folder of a thousand entries, in a pane of about ten rows.
# The renderer draws the rows in the pane, and only those rows read their entries
# from the disk; a folder among them reads its listing for its chevron.
function test_tree_render()
@testset "a tree reads the entries of the rows it draws" begin
    SDL = ProjecturedSdl
    mktempdir() do dir
        for k in 1:100
            folder = joinpath(dir, string("d", lpad(k, 4, '0')))
            mkpath(folder)
            write(joinpath(folder, "x.jl"), "")
        end
        for k in 1:900
            write(joinpath(dir, string("f", lpad(k, 4, '0'), ".jl")), "")
        end
        folder = make_filesystem_pathname(dir)
        pane = print_document(RecursiveProjection(FileSystemToWidget()), folder).output
        pane.size = Point2D(300, 240)
        widgets = RecursiveProjection(WidgetToGraphics(font_ubuntu_regular_20;
                                                       measure = FixedMeasure(8, 12, 4, 0)))
        canvas = print_document(widgets, pane).output
        entries = getfield(folder.elements, :elements)[]
        read_entries() = [k for k in eachindex(entries) if is_cell_up_to_date(entries[k])]
        is_listing_read(d) = is_cell_up_to_date(getfield(d.elements, :elements))
        function render()
            off = SDL._open_offscreen_renderer(800, 600; supersample = 1)
            try
                SDL._render_canvas_offscreen!(off, canvas, 800, 600, (0xff, 0xff, 0xff, 0xff))
            finally
                SDL._close_offscreen_renderer(off)
            end
        end
        @test length(entries) == 1000
        @test isempty(read_entries())

        # A row is 24 pixels high, so the pane shows the root and about ten entries.
        render()
        shown = read_entries()
        @test first(shown) == 1 && shown == collect(1:length(shown))
        @test 8 <= length(shown) <= 11
        # The folders it shows read their listings; a folder it does not show
        # reads none.
        @test all(k -> is_listing_read(folder.elements[k]), shown)
        @test !is_listing_read(folder.elements[50])

        # Scrolled to row 501, the pane shows about entries 500 to 510, and the
        # entries between were never read.
        pane.scroll_position = Point2D(0, 24 * 500)
        render()
        scrolled = setdiff(read_entries(), shown, [50])
        @test !isempty(scrolled) && all(k -> 499 <= k <= 512, scrolled)
        @test length(read_entries()) < 30
    end
end
end
