"""
    test_git_range()

The commits of a range in the example repository. With no editor: the hashes of a
range in the order of the log, of a range with a path and with a pathspec that
excludes, and the words of git for a bad revision. In an editor with a file change
feed: a range that a holder holds reads again when a remote ref moves, when the
refs are packed and the ref moves again, and when a commit lands on a branch of the
range; each commit that stays keeps its document, and the release stops the watch.
"""
function test_git_range()
    root_hash = "73521a28082f6c1bd1b6a4b02b109a6333cbe7a1"
    second_hash = "fd722438c537c96fe00dfb4d91a5517e8e266100"
    side_hash = "848b54ad4a57cf0dc5b19b737c979deb8a1d9fba"
    merge_hash = "74beec429b4b03b7313871671ada043aa0267e6e"
    get_hashes(range) = [commit.header.hash for commit in range.commits]
    read_hashes(range) = (wait_for_cell!(getfield(range, :commits); editor = nothing); get_hashes(range))

    @testset "git range" begin
        mktempdir() do folder
            repository = make_git_example_repository(joinpath(folder, "repository"))

            @testset "a range holds the commits of the log, in its order" begin
                range = GitCommitRange(repository, "main")
                @test read_hashes(range) == [merge_hash, side_hash, second_hash, root_hash]
                @test range.commits[3].header.subject == "second subject continues here"
                @test read_hashes(GitCommitRange(repository, "$root_hash..main")) == [merge_hash, side_hash, second_hash]
                @test read_hashes(GitCommitRange(repository, "main"; paths = ["b.txt"])) == [second_hash]
                @test read_hashes(GitCommitRange(repository, "main"; paths = [":(exclude)*.txt"])) ==
                      [second_hash, root_hash]
                # The table of its page: the short hash, then the columns of gitk.
                rows = range.table.document.rows
                @test [[row.values[k] for k in 1:4] for row in rows] ==
                      [[first(merge_hash, 7), "merge side", "Ann Author <ann@example.org>", "2026-01-05 06:07:08"],
                       [first(side_hash, 7), "side change", "Ann Author <ann@example.org>", "2026-01-04 05:06:07"],
                       [first(second_hash, 7), "second subject continues here", "Ann Author <ann@example.org>",
                        "2026-01-03 04:05:06"],
                       [first(root_hash, 7), "first", "Ann Author <ann@example.org>", "2026-01-02 03:04:05"]]
                @test [row.item for row in rows] == collect(range.commits)
                @test joinpath(repository, ".git") in range.folders
                @test joinpath(repository, ".git", "refs", "heads") in range.folders
                text = print_pred_text(GitCommitRange(repository, "main"; paths = ["b.txt"]))
                @test startswith(text, "GitCommitRange(") && occursin(repr(repository), text) && occursin("b.txt", text)
            end

            @testset "a bad revision gives the words of git" begin
                range = GitCommitRange(repository, "no-such-revision..main")
                failure = try
                    wait_for_cell!(getfield(range, :listing); editor = nothing)
                    nothing
                catch exception
                    exception
                end
                @test failure isa GitException
                @test occursin("no-such-revision", failure.message)
                @test isempty(range.commits)
            end

            @testset "a held range reads again when a ref moves" begin
                editor = Editor(PrimitiveString("x"), IdentityProjection(); backend = HeadlessBackend(),
                                devices = Device[], feeds = Feed[FileChangeFeed()])
                try
                    store = get_session_file_change_store(; editor)
                    remote_folder = joinpath(repository, ".git", "refs", "remotes", "origin")
                    _git_range_run!(repository, ["update-ref", "refs/remotes/origin/main", second_hash])
                    range = GitCommitRange(repository, "$root_hash..origin/main")
                    evaluate_operation(editor, AcquireDocumentOperation(range))
                    @test _git_range_read_until(editor, store, range, hashes -> hashes == [second_hash])
                    kept = range.commits[1]
                    @test remote_folder in range.folders
                    @test is_folder_watched(remote_folder; store, receiver = range)
                    # A fetch moves the remote ref.
                    _git_range_run!(repository, ["update-ref", "refs/remotes/origin/main", merge_hash])
                    @test _git_range_read_until(editor, store, range,
                                                hashes -> hashes == [merge_hash, side_hash, second_hash])
                    @test range.commits[3] === kept
                    # The refs are packed, and a later move writes the ref again.
                    _git_range_run!(repository, ["pack-refs", "--all"])
                    _git_range_run!(repository, ["update-ref", "refs/remotes/origin/main", second_hash])
                    @test _git_range_read_until(editor, store, range, hashes -> hashes == [second_hash])
                    @test range.commits[1] === kept
                    # A commit on the branch of a range.
                    branch = GitCommitRange(repository, "$root_hash..main")
                    evaluate_operation(editor, AcquireDocumentOperation(branch))
                    @test _git_range_read_until(editor, store, branch,
                                                hashes -> hashes == [merge_hash, side_hash, second_hash])
                    write(joinpath(repository, "new.txt"), "new\n")
                    _git_range_run!(repository, ["add", "new.txt"])
                    _git_range_run!(repository, ["commit", "-q", "-m", "new file"])
                    new_hash = strip(read(`git -C $repository rev-parse main`, String))
                    @test _git_range_read_until(editor, store, branch,
                                                hashes -> hashes == [new_hash, merge_hash, side_hash, second_hash])
                    # The release stops the watch and keeps the commits.
                    evaluate_operation(editor, ReleaseDocumentOperation(range))
                    @test !is_folder_watched(joinpath(repository, ".git"); store, receiver = range)
                    @test get_hashes(range) == [second_hash]
                finally
                    close_file_change_store!(get_session_file_change_store(; editor))
                end
            end
        end
    end
end

# Run `git` in `repository` with the fixed author and dates of the example.
function _git_range_run!(repository::String, arguments::Vector{String})
    date = "2026-01-08T09:10:11+00:00"
    run(addenv(`git -C $repository $arguments`, "GIT_CONFIG_GLOBAL" => "/dev/null", "GIT_CONFIG_NOSYSTEM" => "1",
               "GIT_AUTHOR_NAME" => "Ann Author", "GIT_AUTHOR_EMAIL" => "ann@example.org", "GIT_AUTHOR_DATE" => date,
               "GIT_COMMITTER_NAME" => "Ann Author", "GIT_COMMITTER_EMAIL" => "ann@example.org",
               "GIT_COMMITTER_DATE" => date))
    nothing
end

# Run frames of `editor` until the hashes of `range` hold for `done`: each turn
# drains the changes of the folders, reads the commits in the evaluation of the
# editor, as a part that shows them does, and runs a frame, which starts the read.
function _git_range_read_until(editor, store, range, done; seconds::Real = 30)
    deadline = time() + seconds
    while time() < deadline
        drain_file_changes!(; editor, store)
        run_with_evaluation_editor(() -> range.commits, editor)
        drain_operations!(editor)
        run_frame!(editor)
        done([commit.header.hash for commit in range.commits]) && return true
        sleep(0.05)
    end
    false
end
