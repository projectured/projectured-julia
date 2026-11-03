# The files of the folders of a workspace that a search by name lists: the rules
# of `.gitignore`, the folders that start with a dot, the limit, and the search.

# A folder with files, made under `root`: each path names a file, and a path that
# ends with `/` names a folder.
function _make_workspace_fixture(root, files::Pair...)
    for (path, text) in files
        full = joinpath(root, path)
        mkpath(dirname(full))
        write(full, text)
    end
    root
end

_workspace_relative(root, files::WorkspaceFiles) = [relpath(path, root) for path in files.paths]

function test_workspace_file_list()
@testset "the files of the folders of a workspace" begin

@testset "the rules of a .gitignore" begin
    rules = read_gitignore_rules("""
        # a comment, and a blank line

        *.log
        !keep.log
        build/
        /top.txt
        doc/*.md
        **/cache
        out/**
        \\#hash
        """)
    ignored(path, folder = false) = is_gitignored([("", rules)], path, folder)
    @test ignored("a.log") && ignored("deep/b.log")
    @test !ignored("keep.log")
    @test ignored("build", true) && !ignored("build")
    @test ignored("top.txt") && !ignored("sub/top.txt")
    @test ignored("doc/a.md") && !ignored("doc/sub/a.md")
    @test ignored("cache") && ignored("a/b/cache")
    @test ignored("out/a") && ignored("out/a/b")
    @test ignored("#hash")
    @test !ignored("source/main.jl")
    @test isempty(read_gitignore_rules("# only a comment\n\n"))
end

@testset "a rule of a deeper folder applies below that folder, and comes later" begin
    rules = [("", read_gitignore_rules("*.tmp\n")), ("sub", read_gitignore_rules("!x.tmp\n"))]
    @test is_gitignored(rules, "x.tmp", false)
    @test !is_gitignored(rules, "sub/x.tmp", false)
    @test is_gitignored(rules, "sub/y.tmp", false)
end

@testset "a read skips dot folders and what a .gitignore names, in path order" begin
    mktempdir() do root
        _make_workspace_fixture(root,
            ".gitignore" => "*.log\nbuild/\n",
            ".git/config" => "x",
            "a.jl" => "x", "b.log" => "x",
            "build/out.bin" => "x",
            "source/.hidden/x.jl" => "x",
            "source/main.jl" => "x",
            "source/.gitignore" => "!keep.log\n",
            "source/keep.log" => "x")
        files = ProjecturedPlatform.FileSystemModule._read_workspace_files([root])
        @test _workspace_relative(root, files) == ["a.jl", joinpath("source", "keep.log"), joinpath("source", "main.jl")]
        @test !files.is_cut
    end
end

@testset "a read stops at the limit, and says so" begin
    mktempdir() do root
        _make_workspace_fixture(root, ("f$(index).txt" => "x" for index in 1:5)...)
        files = ProjecturedPlatform.FileSystemModule._read_workspace_files([root]; limit = 3)
        @test length(files.paths) == 3
        @test files.is_cut
    end
end

@testset "the search ranks the name, and an empty query puts the open files first" begin
    mktempdir() do root
        _make_workspace_fixture(root,
            "source/platform/pane/PaneProgram.jl" => "x",
            "test/platform/pane/PaneProgramTest.jl" => "x",
            "notes.md" => "x")
        list = WorkspaceFileList()
        read_workspace_files_again!(list, [root])
        @test wait_for_cell!(list.files; editor = nothing) isa WorkspaceFiles
        open_file = joinpath(root, "notes.md")
        search = make_workspace_file_search(list; open_files = [open_file])
        @test [choice.label for choice in search.find("panprog")] == ["PaneProgram.jl", "PaneProgramTest.jl"]
        found = first(search.find("panprog"))
        @test found.note == "source/platform/pane"
        @test search.choose(found.value) isa OpenFileOperation
        @test search.choose(found.value).path == joinpath(root, "source", "platform", "pane", "PaneProgram.jl")
        @test first(search.find("")).value == open_file
        @test isempty(search.find("zzz"))
        # A query that grows scores only the matches before it, and ranks as a
        # search of every path does.
        narrowed = make_workspace_file_search(list)
        narrowed.find("p")
        narrowed.find("pa")
        @test [choice.value for choice in narrowed.find("panprog")] ==
              [choice.value for choice in make_workspace_file_search(list).find("panprog")]
    end
end

end
end # test_workspace_file_list
