"""
    GitModule

The git domain: the values that the output of the `git` program gives, and the
functions that read that output. A function here reads a text and runs no program.
"""
module GitModule

export GitCommitHeader, GitFileSummary, GitDiffFile, GitDiffHunk, GitDiffLine
export parse_git_log_text, parse_git_commit_text, parse_git_diff_text

include("GitParse.jl")

end # module GitModule
