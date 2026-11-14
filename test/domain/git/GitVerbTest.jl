"""
    test_git_verbs()

The verb of the assistant, with no editor: `read_git_document!` of a range gives
its commits in the order of the log, with a path and a range of revisions; of a
commit its header, its changed files and the text of its diffs; of a change its
hunks; of a file at a revision its text; and of a revision that git does not know
the words of git. The mark on `GitDocument` and on the verb offers the documents and
the verb, and the domain gives the system text a sentence that names them.
"""
function test_git_verbs()
    root_hash = "73521a28082f6c1bd1b6a4b02b109a6333cbe7a1"
    second_hash = "fd722438c537c96fe00dfb4d91a5517e8e266100"
    side_hash = "848b54ad4a57cf0dc5b19b737c979deb8a1d9fba"
    merge_hash = "74beec429b4b03b7313871671ada043aa0267e6e"
    hashes(range) = [commit.header.hash for commit in range.commits]
    @testset "git verbs" begin
        mktempdir() do folder
            repository = make_git_example_repository(joinpath(folder, "repository"))

            @testset "a range reads its commits in the order of the log" begin
                range = GitCommitRange(repository, "main")
                @test read_git_document!(range) === range
                @test hashes(range) == [merge_hash, side_hash, second_hash, root_hash]
                @test hashes(read_git_document!(GitCommitRange(repository, "$root_hash..main"))) ==
                      [merge_hash, side_hash, second_hash]
                @test hashes(read_git_document!(GitCommitRange(repository, "main"; paths = ["b.txt"]))) ==
                      [second_hash]
            end

            @testset "a commit reads its header, its changed files and the text of its diffs" begin
                range = read_git_document!(GitCommitRange(repository, "main"))
                commit = range.commits[3]
                @test read_git_document!(commit) === commit
                @test commit.header.subject == "second subject continues here"
                @test [something(change.new_path, change.old_path) for change in commit.changes][1:3] ==
                      ["b.txt", "bin.dat", "gone.txt"]
                @test all(change -> !is_cell_provisional(getfield(change, :hunks)), commit.changes)
                text = commit.diff.text
                @test occursin("-line 19", text) && occursin("+LINE 19", text) && occursin("-bye", text)
                @test !occursin("Reading", text)
                # A commit that a revision names reads its header too.
                tagged = read_git_document!(GitCommit(repository, "v1"))
                @test tagged.header.hash == second_hash
                @test tagged.diff.text == text
            end

            @testset "a change reads its diff, and a file at a revision its text" begin
                change = first(read_git_document!(GitCommit(repository, "v1")).changes)
                @test read_git_document!(change) === change
                @test !isempty(change.hunks)
                @test occursin("+LINE 19", change.diff.text)
                file = GitFileRevision(repository, "v1", "b.txt")
                @test read_git_document!(file) === file
                @test occursin("line 3", file.content.text)
            end

            @testset "a revision that git does not know throws the words of git" begin
                failure(document) = try
                    read_git_document!(document)
                    nothing
                catch exception
                    exception
                end
                for document in (GitCommit(repository, "no-such-revision"),
                                 GitCommitRange(repository, "no-such-revision..main"),
                                 GitFileRevision(repository, "v1", "no-such-file.txt"))
                    exception = failure(document)
                    @test exception isa GitException
                    @test occursin("no-such", exception.message)
                end
            end
        end

        @testset "the mark offers the documents and the verb, and the domain says what they are" begin
            entry = only(entry for entry in ToolModule.collect_marked_api() if entry.module_ === ProjecturedGit.GitModule)
            names = ToolModule.get_api_entry_names(entry)
            @test all(name -> name in names, (:GitDocument, :GitCommitRange, :GitCommit, :GitFileChange,
                                               :GitFileRevision, :read_git_document!))
            sentence = AssistantModule.describe_registered_assistant_api()
            @test occursin("`read_git_document!`", sentence) && occursin("`GitCommitRange`", sentence)
        end
    end
end
