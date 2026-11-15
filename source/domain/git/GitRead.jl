# The runs of the git program: the run of one command in a repository, and the work
# that the background cells of the git documents do off the loop.

"""
    GitException(message)

A run of `git` that failed. `message` holds what git wrote to its error output, or
why the program did not start. A read of the cell of a git document whose read
failed throws it.
"""
struct GitException <: Exception
    message::String
end

Base.showerror(io::IO, exception::GitException) = print(io, "git: ", exception.message)

# The settings that each run of git takes, so that the output is the same with
# any configuration of a person: no pager, no colors, no signature in the log, and
# a path outside ASCII with no quotes.
const _GIT_SETTINGS = ["--no-pager", "-c", "core.quotePath=false", "-c", "color.ui=false",
                       "-c", "log.showSignature=false"]

# The output of `git` with `arguments` in the folder `repository`, or a
# `GitException` with the words of git. The C locale gives the words of git in
# English. A read takes no optional lock, so it runs while another program writes
# in the repository, and git shows no prompt for a password.
function _run_git(repository::AbstractString, arguments::Vector{String})
    command = addenv(`git -C $repository $_GIT_SETTINGS $arguments`,
                     "LC_ALL" => "C", "GIT_OPTIONAL_LOCKS" => "0", "GIT_TERMINAL_PROMPT" => "0")
    output = IOBuffer()
    errors = IOBuffer()
    process = try
        run(pipeline(ignorestatus(command); stdin = devnull, stdout = output, stderr = errors))
    catch exception
        exception isa Base.IOError || rethrow()
        throw(GitException("the program does not start: " * sprint(showerror, exception)))
    end
    success(process) || throw(GitException(String(strip(String(take!(errors))))))
    String(take!(output))
end

# The source of the reads of one document, and of the documents that it makes: one
# task reads each input that one frame demanded. An input is a tuple whose first
# element names the read.
_make_git_source() =
    BackgroundSource(inputs -> Any[_read_git_input(input) for input in inputs]; description = "the reads of git")

function _read_git_input(input::Tuple)
    read = first(input)
    read === :commit && return _read_git_commit(input[2], input[3])
    read === :patch && return _read_git_patch(input[2], input[3], input[4], input[5])
    read === :file && return _read_git_file(input[2], input[3], input[4])
    read === :range && return _read_git_range(input[2], input[3], input[4])
    throw(ArgumentError("a git document demands the read $read, which does not exist"))
end

# The header and the changed files of the commit that `revision` names, against
# its first parent. `^{commit}` takes the commit of an annotated tag.
function _read_git_commit(repository::String, revision::String)
    text = _run_git(repository, ["show", "-z", "--format=" * _HEADER_FORMAT, "--raw", "--numstat", "-M",
                                 "--diff-merges=first-parent", "--no-ext-diff", "--end-of-options",
                                 revision * "^{commit}", "--"])
    parse_git_commit_text(text)
end

# The hunks of the change of one file in the commit `hash`, against its first
# parent. The paths are literal, so a path that starts with `:` names a file.
function _read_git_patch(repository::String, hash::String, old_path, new_path)
    paths = unique(String[path for path in (old_path, new_path) if path !== nothing])
    text = _run_git(repository, ["--literal-pathspecs", "show", "--format=", "--patch", "-M", "--no-ext-diff",
                                 "--no-textconv", "--diff-merges=first-parent", "--src-prefix=a/",
                                 "--dst-prefix=b/", "--end-of-options", hash, "--", paths...])
    # A change of the type of a file is two files of the patch: the old one goes,
    # and the new one comes.
    GitDiffHunk[hunk for file in parse_git_diff_text(text) for hunk in file.hunks]
end

# The text of the file at `path` in the commit that `revision` names.
_read_git_file(repository::String, revision::String, path::String) =
    _run_git(repository, ["cat-file", "blob", "--end-of-options", revision * ":" * path])
