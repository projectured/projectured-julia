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
        folder = read_filesystem_folder!(make_filesystem_pathname(dir); depth = typemax(Int))
        tree = print_document(RecursiveProjection(FileSystemToWidget()), folder).output
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

# The tree draws what the folders hold and reads no disk: a folder that is not
# read shows no rows, and a folder shows a chevron only when it is known to hold
# entries, so an empty folder looks empty the first time it appears.
@testset "FileSystemToWidget draws what the folders hold" begin
    mktempdir() do dir
        mkpath(joinpath(dir, "full", "inner"))
        write(joinpath(dir, "full", "a.jl"), "")
        mkpath(joinpath(dir, "none"))
        write(joinpath(dir, "top.jl"), "")
        folder = read_filesystem_folder!(make_filesystem_pathname(dir))
        tree = print_document(RecursiveProjection(FileSystemToWidget()), folder).output
        node(path) = ProjecturedPlatform.WidgetModule._wtree_node_at(tree, path)
        has_children(path) = ProjecturedPlatform.WidgetModule._wtree_has_children(node(path))
        @test [node([1, k]).label for k in 1:3] == ["full", "none", "top.jl"]
        @test has_children([1, 1]) && !has_children([1, 2]) && !has_children([1, 3])
        # The sub-folders are not read: a folder that holds nothing yet shows nothing.
        @test folder.elements[1].state === :unread && isempty(folder.elements[1].elements)
    end
end

# An explorer draws a root for each folder of its workspace, with its own open
# folders. A chevron opens a folder: the answer writes the open folders of the
# explorer and holds the folder, and the rows of the open folder ask for its
# entries, so it reads; a folder that is open stays open when a new entry comes
# before it.
@testset "an explorer draws its open folders, and a chevron opens and holds a folder" begin
    mktempdir() do dir
        mkpath(joinpath(dir, "full"))
        write(joinpath(dir, "full", "a.jl"), "")
        mkpath(joinpath(dir, "none"))
        write(joinpath(dir, "top.jl"), "")
        editor = _make_folder_editor()
        explorer = WorkspaceExplorer(Workspace([WorkspaceFolder("here", dir)]))
        project = explorer.workspace.folders[1].directory
        projection = FileSystemToWidget()
        iomap = print_document(projection, nothing, explorer, PrinterContext())
        tree = iomap.output
        node(path) = ProjecturedPlatform.WidgetModule._wtree_node_at(tree, path)
        has_children(path) = ProjecturedPlatform.WidgetModule._wtree_has_children(node(path))
        # Before a frame asks nothing is read: the root is open and shows that it reads.
        @test node([1]).label == "here" && tree.expanded == Set([[1]])
        @test node([1, 1]).label == "reading"
        evaluate_operation(editor, AcquireDocumentOperation(explorer))
        # The rows that the tree draws ask for the entries of the open folders.
        ask() = Any[node([1, k]).label for k in 1:length(node([1]).children)]
        @test _wait_for_folder(() -> project.state === :read, editor; ask)
        @test [node([1, k]).label for k in 1:3] == ["full", "none", "top.jl"]
        @test has_children([1, 1]) && !has_children([1, 2]) && !has_children([1, 3])
        full = project.elements[1]
        # A closed folder in view reads nothing: its row and its chevron ask for no
        # entry of it, in the frames that draw them.
        for _ in 1:5
            run_with_evaluation_editor(() -> Cell(@computation (ask(); has_children([1, 1])))[], editor)
            ProjecturedKernel.EditorModule.start_background_cell_work!(editor)
            drain_operations!(editor)
        end
        @test full.state === :unread && !full.reading && full.read_count == 0
        # The chevron of `full`: the widget writes its open nodes, and the explorer
        # turns that into its open folders and a hold of `full`, as view state.
        widget_write = ReplaceViewStateOperation(ReplaceReferencedValueOperation(tree, "expanded",
                                                                                 Set([[1], [1, 1]])))
        answer = read_intent(projection, nothing, Intent(nothing, widget_write, "", ""), iomap).operation
        @test answer isa ReplaceViewStateOperation
        (open_write, hold) = get_wrapped_operation(answer).operations
        @test open_write.document === explorer
        @test hold isa ChangeHeldDocumentsOperation && hold.acquired == Any[full] && isempty(hold.released)
        evaluate_operation(editor, answer)
        @test haskey(explorer.open, full)
        ask_full() = Any[node([1, 1, k]).label for k in 1:length(node([1, 1]).children)]
        @test _wait_for_folder(() -> full.state === :read, editor; ask = ask_full)
        @test node([1, 1, 1]).label == "a.jl" && tree.expanded == Set([[1], [1, 1]])
        # A new folder before `full` keeps `full` open, at its new place.
        mkpath(joinpath(dir, "aaa"))
        @test _wait_for_folder(() -> length(project.elements) == 4, editor; ask)
        @test tree.expanded == Set([[1], [1, 2]]) && node([1, 2]).label == "full"
        # The row of a folder is the path of its document in the explorer, both ways.
        row = @reference(tree, roots[1].children[2])
        path = map_reference_backward(projection, iomap, row)
        @test evaluate_reference(explorer, path) === full
        @test repr(strip_reference_types(map_reference_forward(projection, iomap, path))) == ".roots[1].children[2]"
        evaluate_operation(editor, ReleaseDocumentOperation(explorer))
        store = find_file_change_store(editor)
        @test !is_folder_watched(dir; store) && !is_folder_watched(full.pathname; store)
    end
end

# A drag of the thumb of the tree starts in the output of the tree that
# `FileSystemToWidgetTree` makes of an explorer. The start of the drag names the
# tree through the view, and each part of the drag goes back along that path to
# the tree, which scrolls.
@testset "a drag of the thumb of the tree comes back through the views" begin
    mktempdir() do dir
        for name in ("a", "b", "c", "d", "e", "f", "g", "h")
            write(joinpath(dir, name * ".jl"), "")
        end
        explorer = WorkspaceExplorer(Workspace([WorkspaceFolder("here", dir)]))
        read_filesystem_folder!(explorer.workspace.folders[1].directory)
        projection = ChainingProjection(RecursiveProjection(FileSystemToWidget()),
                                        NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0)))
        offer = with_exact_size(PrinterContext(); width = Cell(Int32(300)), height = Cell(Int32(60)))
        iomap = print_document(projection, nothing, explorer, offer)
        tree = iomap.step_iomaps[1][].output
        rows = get_content_iomap(iomap.step_iomaps[end][])
        bar = only(b for b in get_content_iomap(rows.pane).bars if b.field == "vertical_scroll_bar")
        @test Int(bar.place.w) > 0
        x = rows.place[1] + Int(bar.place.x) + 2
        y = rows.place[2] + Int(bar.place.y) + 2
        plain = ModifierKeys()
        read(gesture, route = nothing) =
            read_intent(projection, nothing, Intent(gesture, nothing, "", "", route), iomap).operation
        # Evaluate the writes of an answer that carry their document.
        function apply!(answer)
            for o in (answer isa CompoundOperation ? answer.operations : Any[answer])
                write = o isa ReplaceViewStateOperation ? get_wrapped_operation(o) : o
                write isa ReplaceReferencedValueOperation && write.document !== nothing &&
                    evaluate_operation(nothing, o)
            end
        end
        press = read(MouseDown(:left, x, y, plain; time = 0.0))
        @test press isa CompoundOperation
        start = only(o for o in press.operations if o isa StartDragOperation)
        # The path names the tree through the view, as a part that the view drew.
        @test start.path isa Reference
        apply!(press)
        @test bar.document.thumb_drag !== nothing
        apply!(read(DragMove(x, y + 30, plain; time = 0.0), start.path))
        @test Int(tree.scroll_position.y[]) > 0
        apply!(read(DragEnd(x, y + 30, plain; time = 0.0), start.path))
        @test bar.document.thumb_drag === nothing
    end
end
end
