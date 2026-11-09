# A folder holds what its last read found, and reads only when a part asks for its
# entries (`demand_tree_children`): the read lists each name with its kind and
# whether each sub-folder holds an entry, a new read keeps the document of each
# entry that stays, a change that the watch of a holder sees makes the part ask
# again, and the release stops the watch and keeps the entries. An acquire alone
# reads nothing. A workspace shares one listing between its explorers, and each
# explorer holds its own open folders. A caller with no editor reads at once.

# An editor that drains the changes of its files and folders, and draws nothing.
_make_folder_editor() =
    Editor(PrimitiveString("x"), IdentityProjection(); backend = HeadlessBackend(), devices = Device[],
           feeds = Feed[FileChangeFeed()])

_get_entry_names(folder) = [basename(entry.pathname) for entry in folder.elements]

# Wait until `test()` holds, for at most ten seconds, draining the changes of the
# folders of `editor` meanwhile. `ask`, when given, is what a part that shows the
# entries reads in each frame: it runs in a computation of `editor`, so its reads
# ask for what they need, and the work of the frame starts.
function _wait_for_folder(test, editor; ask = nothing)
    deadline = time() + 10
    store = find_file_change_store(editor)
    while time() < deadline
        drain_file_changes!(; editor, store)
        drain_operations!(editor)
        test() && return true
        if ask !== nothing
            run_with_evaluation_editor(() -> Cell(@computation ask())[], editor)
            ProjecturedKernel.EditorModule.start_background_cell_work!(editor)
        end
        sleep(0.05)
    end
    false
end

function test_filesystem_document()
@testset "FileSystemDocument holds what its last read found" begin
    @testset "a name sorts with no regard to case, a run of digits by its value, and its character codes at a tie" begin
        is_name_before = ProjecturedPlatform.FileSystemModule._is_name_before
        invalid = String([0x61, 0xff, 0x62])
        for (a, b) in [("file9", "file10"), ("a.txt", "Makefile"), ("_build", "docs"), (".config", "0"),
                       ("0", "_"), ("file", "file1"), ("README.md", "readme.md"), ("file01", "file1"),
                       ("x2y", "x10y"), ("v1.2", "v1.10"), ("Zeta", "éclair"), ("000", "1"),
                       ("f" * "9"^30, "f1" * "0"^30), ("a", invalid), (invalid, "b")]
            @test is_name_before(a, b) && !is_name_before(b, a)
        end
        @test !is_name_before("same", "same")
    end

    @testset "a folder lists its folders first, then its files, and a new read keeps that order" begin
        mktempdir() do dir
            foreach(name -> mkpath(joinpath(dir, name)), (".config", "Zeta", "_build", "docs"))
            foreach(name -> write(joinpath(dir, name), ""),
                    (".gitignore", "Makefile", "README.md", "a.txt", "file10.txt", "file9.txt", "x"))
            root = read_filesystem_folder!(make_filesystem_pathname(dir))
            files = ["a.txt", "file9.txt", "file10.txt", "Makefile", "README.md"]
            @test _get_entry_names(root) == [".config", "_build", "docs", "Zeta", ".gitignore", files..., "x"]
            # A new file goes to its place, and each entry that stays keeps its document.
            kept = collect(root.elements)
            write(joinpath(dir, "file2.txt"), "")
            read_filesystem_folder!(root)
            @test _get_entry_names(root) ==
                  [".config", "_build", "docs", "Zeta", ".gitignore", "a.txt", "file2.txt", files[2:end]..., "x"]
            @test all(entry -> any(stored -> stored === entry, root.elements), kept)
            # A file that becomes a folder moves to the folders.
            rm(joinpath(dir, "x"))
            mkpath(joinpath(dir, "x"))
            read_filesystem_folder!(root)
            @test _get_entry_names(root) ==
                  [".config", "_build", "docs", "x", "Zeta", ".gitignore", "a.txt", "file2.txt", files[2:end]...]
            @test root.elements[4] isa FileSystemDirectory && root.elements[1] === kept[1]
        end
    end

    mktempdir() do dir
        write(joinpath(dir, "a.jl"), "")
        mkpath(joinpath(dir, "sub", "deep"))
        write(joinpath(dir, "sub", "deep", "b.jl"), "")
        mkpath(joinpath(dir, "empty"))

        @testset "a folder is made unread, and nothing reads it before a part asks for its entries" begin
            root = make_filesystem_pathname(dir)
            @test root isa FileSystemDirectory && root.state === :unread
            @test isempty(root.elements) && has_folder_entries(root) === nothing
            @test make_filesystem_pathname(joinpath(dir, "a.jl")) isa FileSystemFile
            # An acquire watches the folder and reads nothing, also after frames.
            editor = _make_folder_editor()
            try
                evaluate_operation(editor, AcquireDocumentOperation(root))
                for _ in 1:10
                    drain_operations!(editor)
                    ProjecturedKernel.EditorModule.start_background_cell_work!(editor)
                    sleep(0.05)
                end
                @test root.state === :unread && !root.reading && isempty(root.elements)
                evaluate_operation(editor, ReleaseDocumentOperation(root))
            finally
                close_file_change_store!(find_file_change_store(editor))
            end
        end

        @testset "a part that asks reads the names, their kinds and the emptiness of each sub-folder" begin
            editor = _make_folder_editor()
            try
                root = make_filesystem_pathname(dir)
                evaluate_operation(editor, AcquireDocumentOperation(root))
                ask() = demand_tree_children(root)
                @test _wait_for_folder(() -> root.state === :read, editor; ask)
                @test _get_entry_names(root) == ["empty", "sub", "a.jl"]
                (empty, sub, file) = collect(root.elements)
                @test file isa FileSystemFile && empty isa FileSystemDirectory && sub isa FileSystemDirectory
                @test sub.state === :unread && has_folder_entries(sub) === true
                @test has_folder_entries(empty) === false
                store = find_file_change_store(editor)
                @test is_folder_watched(dir; store, receiver = root)
                @test is_folder_watched(sub.pathname; store, receiver = root)

                # A new file is one entry more, and each entry that stays keeps its document.
                write(joinpath(dir, "c.jl"), "")
                @test _wait_for_folder(() -> length(root.elements) == 4, editor; ask)
                @test _get_entry_names(root) == ["empty", "sub", "a.jl", "c.jl"]
                @test root.elements[1] === empty && root.elements[2] === sub && root.elements[3] === file

                # A sub-folder that gets its first entry says so.
                write(joinpath(dir, "empty", "d.jl"), "")
                @test _wait_for_folder(() -> has_folder_entries(empty) === true, editor)

                # The release stops the watches and keeps the entries.
                evaluate_operation(editor, ReleaseDocumentOperation(root))
                @test !is_folder_watched(dir; store) && !is_folder_watched(sub.pathname; store)
                @test _get_entry_names(root) == ["empty", "sub", "a.jl", "c.jl"]
                rm(joinpath(dir, "c.jl"))
                rm(joinpath(dir, "empty", "d.jl"))
            finally
                close_file_change_store!(find_file_change_store(editor))
            end
        end

        @testset "a caller with no editor reads at once, down to a depth" begin
            root = read_filesystem_folder!(make_filesystem_pathname(dir); depth = 2)
            @test root.state === :read && _get_entry_names(root) == ["empty", "sub", "a.jl"]
            sub = root.elements[2]
            @test sub.state === :read && _get_entry_names(sub) == ["deep"]
            @test sub.elements[1].state === :unread
        end

        @testset "a workspace shares one listing, and each explorer holds its own open folders" begin
            editor = _make_folder_editor()
            try
                workspace = Workspace([WorkspaceFolder("project", dir)])
                project = workspace.folders[1].directory
                @test project isa FileSystemDirectory && project.state === :unread
                left = WorkspaceExplorer(workspace)
                right = WorkspaceExplorer(workspace)
                @test haskey(left.open, project) && haskey(right.open, project)
                evaluate_operation(editor, AcquireDocumentOperation(left))
                @test _wait_for_folder(() -> project.state === :read, editor; ask = () -> demand_tree_children(project))
                # The second explorer reads nothing again: an acquire reads nothing, and
                # the listing that the first read found belongs to the folder as it is.
                evaluate_operation(editor, AcquireDocumentOperation(right))
                @test !project.reading && project.read_count == 0
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
            finally
                close_file_change_store!(find_file_change_store(editor))
            end
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
            try
                folder = make_filesystem_pathname(large)
                evaluate_operation(editor, AcquireDocumentOperation(folder))
                @test _wait_for_folder(() -> folder.state === :read, editor; ask = () -> demand_tree_children(folder))
                @test length(folder.elements) == 5000 && folder.read_count == 0
                @test basename(folder.elements[1].pathname) == "file0001.txt"
                evaluate_operation(editor, ReleaseDocumentOperation(folder))
            finally
                close_file_change_store!(find_file_change_store(editor))
            end
        end
    end
end
end
