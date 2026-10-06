# A row of the Files pane is a place the projection introduces on a folder, so a
# selection of one goes into the root path as a step on the folder, and the tree
# reads the row back from there. No second selection is written anywhere.
function test_workspace_to_filesystem()
@testset "WorkspaceToFileSystem selection" begin
    mktempdir() do dir
        write(joinpath(dir, "a.jl"), "")
        write(joinpath(dir, "b.jl"), "")
        mkpath(joinpath(dir, "sub"))
        write(joinpath(dir, "sub", "c.jl"), "")
        workspace = Workspace([WorkspaceFolder("here", dir)])
        projection = ChainingProjection(RecursiveProjection(WorkspaceToFileSystem()),
                                        RecursiveProjection(FileSystemToWidget()))
        iomap = print_document(projection, workspace)
        pane = iomap.output
        tree = pane.content
        shown(path) = repr(strip_reference_types(path))
        read_back(path) = read_intent(projection, iomap, ReplaceSelectionOperation(path))

        # `sub/c.jl` is the first entry of the third entry of the root.
        operation = read_back(@reference(pane, content.roots[1].children[3].children[1]))
        @test operation isa ReplaceSelectionOperation
        steps = get_reference_steps(operation.path)
        @test shown(foldr(ConcreteReference, steps[1:2]; init = EmptyReference())) == ".folders[1]"
        @test last(steps) isa ProjectionReferenceStep
        @test shown(last(steps).output_path) == ".elements[3].elements[1]"
        replace_selection!(workspace, operation.path)
        @test shown(tree.selection) == ".roots[1].children[3].children[1]"

        # The root row is the folder as a whole, both ways.
        root = read_back(@reference(pane, content.roots[1]))
        @test shown(root.path) == ".folders[1]"
        replace_selection!(workspace, root.path)
        @test shown(tree.selection) == ".roots[1]"

        # The workspace as a whole is no row. The editor's writer clears the branch
        # the selection leaves, so the folder holds nothing either.
        replace_selection!(workspace, EmptyReference())
        @test tree.selection === nothing

        # The part under the pointer takes the same way: the pointer on the row of
        # `sub/c.jl` maps back to the folder, and the tree holds that row.
        row = @reference(pane, content.roots[1].children[3].children[1])
        target = read_intent(projection, iomap, ReplaceMouseTargetOperation(row))
        @test target isa ReplaceMouseTargetOperation
        @test shown(target.path) == shown(operation.path)
        replace_mouse_target!(workspace, target.path)
        @test shown(tree.mouse_target) == ".roots[1].children[3].children[1]"
        @test tree.selection === nothing
        replace_mouse_target!(workspace, EmptyReference())
        @test tree.mouse_target === nothing
    end
end
end
