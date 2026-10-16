# A folder holds what its last read found, and reads only when a holder acquires
# it: the read lists each name with its kind and whether each sub-folder holds an
# entry, a new read keeps the document of each entry that stays, the watch of the
# folder reads it again, and the release stops the watch and keeps the entries. A
# workspace shares one listing between its explorers, and each explorer holds its
# own open folders. A caller with no editor reads at once.

# An editor that drains the changes of its files and folders, and draws nothing.
_make_folder_editor() =
    Editor(PrimitiveString("x"), IdentityProjection(); backend = HeadlessBackend(), devices = Device[],
           feeds = Feed[FileChangeFeed()])

_get_entry_names(folder) = [basename(entry.pathname) for entry in folder.elements]

# Wait until `test()` holds, for at most ten seconds, draining the changes of the
# folders of `editor` meanwhile.
function _wait_for_folder(test, editor)
    deadline = time() + 10
    store = find_file_change_store(editor)
    while time() < deadline
        drain_file_changes!(; editor, store)
        drain_operations!(editor)
        test() && return true
        sleep(0.05)
    end
    false
end

function test_filesystem_document()
@testset "FileSystemDocument holds what its last read found" begin
    mktempdir() do dir
        write(joinpath(dir, "a.jl"), "")
        mkpath(joinpath(dir, "sub", "deep"))
        write(joinpath(dir, "sub", "deep", "b.jl"), "")
        mkpath(joinpath(dir, "empty"))

        @testset "a folder is made unread, and nothing reads it before an acquire" begin
            root = make_filesystem_pathname(dir)
            @test root isa FileSystemDirectory && root.state === :unread
            @test isempty(root.elements) && has_folder_entries(root) === nothing
            @test make_filesystem_pathname(joinpath(dir, "a.jl")) isa FileSystemFile
        end

        @testset "an acquire reads the names, their kinds and the emptiness of each sub-folder" begin
            editor = _make_folder_editor()
            root = make_filesystem_pathname(dir)
            evaluate_operation(editor, AcquireDocumentOperation(root))
            @test _wait_for_folder(() -> root.state === :read, editor)
            @test _get_entry_names(root) == ["a.jl", "empty", "sub"]
            (file, empty, sub) = collect(root.elements)
            @test file isa FileSystemFile && empty isa FileSystemDirectory && sub isa FileSystemDirectory
            @test sub.state === :unread && has_folder_entries(sub) === true
            @test has_folder_entries(empty) === false
            store = find_file_change_store(editor)
            @test is_folder_watched(dir; store, receiver = root)
            @test is_folder_watched(sub.pathname; store, receiver = root)

            # A new file is one entry more, and each entry that stays keeps its document.
            write(joinpath(dir, "c.jl"), "")
            @test _wait_for_folder(() -> length(root.elements) == 4, editor)
            @test _get_entry_names(root) == ["a.jl", "c.jl", "empty", "sub"]
            @test root.elements[1] === file && root.elements[3] === empty && root.elements[4] === sub

            # A sub-folder that gets its first entry says so.
            write(joinpath(dir, "empty", "d.jl"), "")
            @test _wait_for_folder(() -> has_folder_entries(empty) === true, editor)

            # The release stops the watches and keeps the entries.
            evaluate_operation(editor, ReleaseDocumentOperation(root))
            @test !is_folder_watched(dir; store) && !is_folder_watched(sub.pathname; store)
            @test _get_entry_names(root) == ["a.jl", "c.jl", "empty", "sub"]
            rm(joinpath(dir, "c.jl"))
            rm(joinpath(dir, "empty", "d.jl"))
        end

        @testset "a caller with no editor reads at once, down to a depth" begin
            root = read_filesystem_folder!(make_filesystem_pathname(dir); depth = 2)
            @test root.state === :read && _get_entry_names(root) == ["a.jl", "empty", "sub"]
            sub = root.elements[3]
            @test sub.state === :read && _get_entry_names(sub) == ["deep"]
            @test sub.elements[1].state === :unread
        end

        @testset "a workspace shares one listing, and each explorer holds its own open folders" begin
            editor = _make_folder_editor()
            workspace = Workspace([WorkspaceFolder("project", dir)])
            project = workspace.folders[1].directory
            @test project isa FileSystemDirectory && project.state === :unread
            left = WorkspaceExplorer(workspace)
            right = WorkspaceExplorer(workspace)
            @test haskey(left.open, project) && haskey(right.open, project)
            evaluate_operation(editor, AcquireDocumentOperation(left))
            @test _wait_for_folder(() -> project.state === :read, editor)
            # The second explorer reads nothing again: the folder has two holders.
            evaluate_operation(editor, AcquireDocumentOperation(right))
            @test project.read_count == 1
            store = find_file_change_store(editor)
            evaluate_operation(editor, ReleaseDocumentOperation(left))
            @test is_folder_watched(dir; store, receiver = project)
            evaluate_operation(editor, ReleaseDocumentOperation(right))
            @test !is_folder_watched(dir; store, receiver = project)
            # A duplicate shares the workspace and copies the open folders.
            duplicate = make_document_duplicate(left)
            @test duplicate isa WorkspaceExplorer && duplicate.workspace === workspace
            @test duplicate.open == left.open && duplicate.open !== left.open
            # A file of the workspace keeps the name and the place of each folder.
            @test ProjecturedPlatform.SerializationModule.pred_arguments(workspace.folders[1]) ==
                  ((), Pair{Symbol,Any}[:name => "project", :pathname => dir])
        end
    end

    @testset "a folder that can not be read fails, and a large folder is one read" begin
        mktempdir() do dir
            closed = joinpath(dir, "closed")
            mkpath(joinpath(closed, "inner"))
            chmod(closed, 0o000)
            try
                folder = read_filesystem_folder!(make_filesystem_pathname(closed))
                @test folder.state === :failed && folder.failure isa Base.IOError
                @test isempty(folder.elements)
            finally
                chmod(closed, 0o755)
            end
            large = joinpath(dir, "large")
            mkpath(large)
            foreach(k -> touch(joinpath(large, string("file", lpad(k, 4, '0'), ".txt"))), 1:5000)
            editor = _make_folder_editor()
            folder = make_filesystem_pathname(large)
            evaluate_operation(editor, AcquireDocumentOperation(folder))
            @test _wait_for_folder(() -> folder.state === :read, editor)
            @test length(folder.elements) == 5000 && folder.read_count == 1
            @test basename(folder.elements[1].pathname) == "file0001.txt"
            evaluate_operation(editor, ReleaseDocumentOperation(folder))
        end
    end
end
end
