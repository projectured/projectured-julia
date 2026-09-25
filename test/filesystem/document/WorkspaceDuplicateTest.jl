# The duplicate of a workspace is a copy of the folders it names, so a person
# can duplicate the explorer tab and change one explorer without the other.

using Test

# A pane edit reads the document of the editor that evaluates it.
mutable struct _WorkspaceDuplicateMockEditor
    document::Any
end

function test_workspace_duplicate()
@testset "the duplicate of a workspace is a copy of its folders" begin

    _make_workspace() = Workspace([WorkspaceFolder("one", "/work/one"),
                                   WorkspaceFolder("two", "/work/two")])

    @testset "a workspace and a folder each have a duplicate" begin
        workspace = _make_workspace()
        @test has_document_duplicate(workspace)
        @test has_document_duplicate(workspace.folders[1])
        @test has_document_duplicate(make_insertion_document(Workspace))
    end

    @testset "the duplicate names the same folders, in nodes of its own" begin
        workspace = _make_workspace()
        duplicate = make_document_duplicate(workspace)
        @test duplicate isa Workspace
        @test duplicate !== workspace
        @test [folder.name for folder in duplicate.folders] == ["one", "two"]
        @test [folder.pathname for folder in duplicate.folders] == ["/work/one", "/work/two"]
        @test getfield(duplicate, :folders) !== getfield(workspace, :folders)
        @test all(i -> duplicate.folders[i] !== workspace.folders[i], 1:2)
    end

    @testset "a change of the duplicate leaves the original" begin
        workspace = _make_workspace()
        duplicate = make_document_duplicate(workspace)
        duplicate.folders[1].pathname = "/elsewhere"
        push!(duplicate.folders, WorkspaceFolder("three", "/work/three"))
        @test workspace.folders[1].pathname == "/work/one"
        @test length(workspace.folders) == 2
        @test length(duplicate.folders) == 3
    end

    @testset "the explorer tab duplicates into the next tab" begin
        tab = PaneTab("Explorer", _make_workspace())
        group = PaneGroup(PaneTab[tab])
        tree = PaneTree(group)
        operation = make_pane_duplicate_tab_operation(tree, group, 1)
        @test operation !== nothing
        evaluate_operation(_WorkspaceDuplicateMockEditor(tree), operation)
        @test length(group.tabs) == 2
        @test get_pane_tab_title_string(group.tabs[2]) == "Explorer (2)"
        @test group.tabs[2].content isa Workspace
        @test group.tabs[2].content !== tab.content
        @test get_pane_focus(tree) == (group, 2)
    end

end
end
