"""
    GitModule

The git domain: a commit, the change of one file in a commit, and a file at a
revision, which the `git` program reads off the loop, and the values of the output
of git with the functions that read that output.
"""
module GitModule

using ..KernelModule
using ..PlatformModule

# Imported to extend: this module adds a method to it.
import ..SerializationModule: pred_arguments

export GitCommitHeader, GitFileSummary, GitDiffFile, GitDiffHunk, GitDiffLine
export parse_git_log_text, parse_git_commit_text, parse_git_diff_text
export GitException
export GitDocument, GitCommit, GitFileChange, GitFileRevision

include("GitParse.jl")
include("GitRead.jl")
include("GitDocument.jl")

end # module GitModule
