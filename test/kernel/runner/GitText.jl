# The answers of git that the runner and the supervisor read. Base only, so the
# supervisor of `tool/run-tests.jl` can include it.

# The output of `git -C folder arguments`, or "" when git fails.
_git_text(folder::AbstractString, arguments::Cmd) =
    try
        readchomp(pipeline(`git -C $folder $arguments`; stderr = devnull))
    catch
        ""
    end

"""
    repository_name(folder) -> String

The name of the git repository of `folder`: the last word of the address of its
remote `origin` without `.git`, which each worktree of it shares, or else the name
of the top folder of the checkout; "" outside git.
"""
function repository_name(folder::AbstractString)
    origin = _git_text(folder, `config --get remote.origin.url`)
    isempty(origin) || return replace(basename(rstrip(origin, '/')), r"\.git$" => "")
    top = _git_text(folder, `rev-parse --show-toplevel`)
    isempty(top) ? "" : basename(top)
end

"""
    fork_commits(folder, base) -> Vector{String}

The commits at and before the commit where `HEAD` of the repository of `folder` left
`base`, newest first: the last 200 commits of the first parents; none outside git.
"""
function fork_commits(folder::AbstractString, base::AbstractString)
    fork = _git_text(folder, `merge-base HEAD $base`)
    isempty(fork) && return String[]
    [String(commit) for commit in
     split(_git_text(folder, `rev-list --first-parent --max-count=200 $fork`), '\n')
     if length(commit) >= 12]
end
