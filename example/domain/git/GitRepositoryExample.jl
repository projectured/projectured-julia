"""
    make_git_example_repository(folder) -> String

Make a git repository in the empty folder `folder` and answer its absolute path.
The names, the dates and the texts are fixed, so each hash is known. The history:

1. `first`, the root commit: `a.txt` with 20 lines, `sp ace é.txt` with no line end
   at its end, `gone.txt` and `mode.sh`.
2. `second subject`, which renames `a.txt` to `b.txt` and changes its lines 2 and
   19, adds the binary file `bin.dat`, deletes `gone.txt`, makes `mode.sh`
   executable, changes `sp ace é.txt`, and adds a file whose name holds a tab and a
   quote. The annotated tag `v1` names it.
3. `side change`, on the branch `side` from the root commit, adds `side.txt`.
4. `merge side` merges `side` into `main` with no conflict. `main` names it.

The global and the system configuration of git do not apply, so a hook or a
signature of the machine changes nothing. `git` must be on the path.
"""
function make_git_example_repository(folder::AbstractString)
    path = abspath(folder)
    mkpath(path)
    first_date = "2026-01-02T03:04:05+01:00"
    second_date = "2026-01-03T04:05:06-02:30"
    _run_example_git(path, first_date, ["init", "-q", "-b", "main"])
    write(joinpath(path, "a.txt"), join(("line $n\n" for n in 1:20)))
    write(joinpath(path, "sp ace é.txt"), "x\ny")
    write(joinpath(path, "gone.txt"), "bye\n")
    write(joinpath(path, "mode.sh"), "echo\n")
    _run_example_git(path, first_date, ["add", "-A"])
    _run_example_git(path, first_date, ["commit", "-q", "-m", "first"])
    write(joinpath(path, "a.txt"), join((n == 2 || n == 19 ? "LINE $n\n" : "line $n\n" for n in 1:20)))
    _run_example_git(path, second_date, ["mv", "a.txt", "b.txt"])
    write(joinpath(path, "bin.dat"), UInt8[0x00, 0x01, 0x02])
    write(joinpath(path, "sp ace é.txt"), "x\nz")
    _run_example_git(path, second_date, ["rm", "-q", "gone.txt"])
    write(joinpath(path, "ta\tb\"q.txt"), "q\n")
    chmod(joinpath(path, "mode.sh"), 0o755)
    _run_example_git(path, second_date, ["add", "-A"])
    _run_example_git(path, second_date,
                     ["commit", "-q", "-m", "second subject\ncontinues here\n\nBody line one.\nBody line two."])
    _run_example_git(path, second_date, ["tag", "-a", "v1", "-m", "version 1"])
    side_date = "2026-01-04T05:06:07+00:00"
    _run_example_git(path, side_date, ["checkout", "-q", "-b", "side", "HEAD~1"])
    write(joinpath(path, "side.txt"), "side\n")
    _run_example_git(path, side_date, ["add", "-A"])
    _run_example_git(path, side_date, ["commit", "-q", "-m", "side change"])
    merge_date = "2026-01-05T06:07:08+05:45"
    _run_example_git(path, merge_date, ["checkout", "-q", "main"])
    _run_example_git(path, merge_date, ["merge", "-q", "--no-ff", "-m", "merge side", "side"])
    path
end

# Run `git` in `path` with the fixed author and committer of the example, and the
# date `date` for both.
function _run_example_git(path::String, date::String, arguments::Vector{String})
    run(addenv(`git -C $path $arguments`,
               "GIT_CONFIG_GLOBAL" => "/dev/null", "GIT_CONFIG_NOSYSTEM" => "1", "LC_ALL" => "C",
               "GIT_AUTHOR_NAME" => "Ann Author", "GIT_AUTHOR_EMAIL" => "ann@example.org", "GIT_AUTHOR_DATE" => date,
               "GIT_COMMITTER_NAME" => "Ann Author", "GIT_COMMITTER_EMAIL" => "ann@example.org",
               "GIT_COMMITTER_DATE" => date))
    nothing
end
