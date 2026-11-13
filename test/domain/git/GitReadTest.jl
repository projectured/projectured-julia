"""
    test_git_reading()

The reads of the git documents in the example repository, with no editor: each
read runs `git` on the calling task, in `wait_for_cell!`.
"""
function test_git_reading()
    root_hash = "73521a28082f6c1bd1b6a4b02b109a6333cbe7a1"
    second_hash = "fd722438c537c96fe00dfb4d91a5517e8e266100"
    side_hash = "848b54ad4a57cf0dc5b19b737c979deb8a1d9fba"
    merge_hash = "74beec429b4b03b7313871671ada043aa0267e6e"
    quoted_name = "ta\tb\"q.txt"
    spaced_name = "sp ace é.txt"
    read_final(document, field) = wait_for_cell!(getfield(document, field); editor = nothing)
    change_facts(change) =
        (change.kind, change.old_path, change.new_path, change.added_count, change.removed_count, change.is_binary)
    # The text of a `.pred` file of a call: one argument on each line.
    pred_call(name, arguments...) = string(name, "(\n", join(("    " * repr(argument) * ",\n" for argument in arguments)), ")")
    read_failure(document, field) =
        try
            read_final(document, field)
            nothing
        catch exception
            exception
        end

    @testset "git reading" begin
        mktempdir() do folder
            repository = make_git_example_repository(joinpath(folder, "repository"))

            @testset "a tag names its commit, with its header and its changes" begin
                commit = GitCommit(repository, "v1")
                @test commit.repository == repository
                header = read_final(commit, :header)
                @test header.hash == second_hash
                @test header.parents == [root_hash]
                @test (header.author_name, header.author_email, header.author_date) ==
                      ("Ann Author", "ann@example.org", "2026-01-03T04:05:06-02:30")
                @test header.subject == "second subject continues here"
                @test header.message == "second subject\ncontinues here\n\nBody line one.\nBody line two."
                changes = collect(read_final(commit, :changes))
                @test map(change_facts, changes) ==
                      [(:renamed, "a.txt", "b.txt", 2, 2, false),
                       (:added, nothing, "bin.dat", 0, 0, true),
                       (:deleted, "gone.txt", nothing, 0, 1, false),
                       (:modified, "mode.sh", "mode.sh", 0, 0, false),
                       (:modified, spaced_name, spaced_name, 1, 1, false),
                       (:added, nothing, quoted_name, 1, 0, false)]
                @test all(change -> change.repository == repository && change.old_revision == root_hash &&
                                    change.new_revision == second_hash, changes)
                hunks = read_final(changes[1], :hunks)
                @test [(hunk.old_start, hunk.old_count, hunk.new_start, hunk.new_count) for hunk in hunks] ==
                      [(1, 5, 1, 5), (16, 5, 16, 5)]
                @test [(line.kind, line.text, line.old_number, line.new_number) for line in hunks[2].lines][4:5] ==
                      [(:removed, "line 19", 19, nothing), (:added, "LINE 19", nothing, 19)]
                @test isempty(read_final(changes[2], :hunks))
                @test [(line.kind, line.text) for line in only(read_final(changes[3], :hunks)).lines] ==
                      [(:removed, "bye")]
                @test [(line.kind, line.text, line.has_line_end) for line in only(read_final(changes[5], :hunks)).lines] ==
                      [(:kept, "x", true), (:removed, "y", false), (:added, "z", false)]
                @test [(line.kind, line.text) for line in only(read_final(changes[6], :hunks)).lines] == [(:added, "q")]
                # The read of a commit runs one time, so each change keeps its document.
                @test read_final(commit, :changes)[1] === changes[1]
                @test print_pred_text(commit) == pred_call("GitCommit", repository, second_hash)
            end

            @testset "a merge shows its change against its first parent" begin
                commit = GitCommit(repository, "main")
                header = read_final(commit, :header)
                @test header.hash == merge_hash
                @test header.parents == [second_hash, side_hash]
                @test header.subject == "merge side"
                changes = collect(read_final(commit, :changes))
                @test map(change_facts, changes) == [(:added, nothing, "side.txt", 1, 0, false)]
                @test only(changes).old_revision == second_hash
                @test [(line.kind, line.text, line.new_number) for line in only(read_final(only(changes), :hunks)).lines] ==
                      [(:added, "side", 1)]
            end

            @testset "a root commit adds each file" begin
                commit = GitCommit(repository, root_hash)
                @test read_final(commit, :header).parents == String[]
                changes = collect(read_final(commit, :changes))
                @test [(change.kind, change.old_path, change.new_path) for change in changes] ==
                      [(:added, nothing, "a.txt"), (:added, nothing, "gone.txt"), (:added, nothing, "mode.sh"),
                       (:added, nothing, spaced_name)]
                @test all(change -> change.old_revision === nothing, changes)
                @test [line.text for line in only(read_final(changes[1], :hunks)).lines] == ["line $n" for n in 1:20]
            end

            @testset "a commit with the header of a log reads only its changes" begin
                header = read_final(GitCommit(repository, "v1"), :header)
                commit = GitCommit(repository, header.hash; header)
                @test commit.header === header
                @test !is_cell_provisional(getfield(commit, :header))
                @test length(read_final(commit, :changes)) == 6
                @test print_pred_text(commit) == pred_call("GitCommit", repository, second_hash)
            end

            @testset "a file at a revision gives its text" begin
                file = GitFileRevision(repository, "v1", "b.txt"; line = 19)
                @test (file.repository, file.revision, file.path, file.line) == (repository, "v1", "b.txt", 19)
                @test read_final(file, :text) == join((n == 2 || n == 19 ? "LINE $n\n" : "line $n\n" for n in 1:20))
                @test read_final(GitFileRevision(repository, root_hash, spaced_name), :text) == "x\ny"
                @test read_final(GitFileRevision(repository, "v1", quoted_name), :text) == "q\n"
            end

            @testset "a failed read throws the words of git" begin
                unknown = read_failure(GitCommit(repository, "no-such-revision"), :header)
                @test unknown isa GitException
                @test occursin("bad revision 'no-such-revision", unknown.message)
                missing_file = read_failure(GitFileRevision(repository, "v1", "no-such-file.txt"), :text)
                @test missing_file isa GitException
                @test occursin("no-such-file.txt", missing_file.message)
                no_repository = read_failure(GitCommit(folder, "HEAD"), :header)
                @test no_repository isa GitException
                @test occursin("not a git repository", no_repository.message)
                # A commit with no hash from a read is named by its revision.
                @test print_pred_text(GitCommit(folder, "HEAD")) == pred_call("GitCommit", folder, "HEAD")
            end
        end
    end
end
