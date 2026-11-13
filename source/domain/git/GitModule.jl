"""
    GitModule

The git domain: a commit, the change of one file in a commit, a file at a revision
and the commits of a range, which the `git` program reads off the loop; their texts and their pages,
which the text domain draws; and the values of the output of git with the
functions that read that output.
"""
module GitModule

using ..KernelModule
using ..PlatformModule

# Imported to extend: this module adds a method to each of these.
import ..SerializationModule: pred_arguments
import ..ProjectionModule: print_document, read_intent, map_reference_forward, map_reference_backward
import ..DocumentModule: get_document_title, is_field_walked
import ..WidgetModule: make_graphics_projection
import ..OperationModule: evaluate_operation
import ..DomainModule: acquire_document!, release_document!
import ..FileChangeModule: receive_folder_change!
import ..RosterModule: get_item_facets, compute_item_facet

export GitCommitHeader, GitFileSummary, GitDiffFile, GitDiffHunk, GitDiffLine
export parse_git_log_text, parse_git_commit_text, parse_git_diff_text
export GitException
export GitDocument, GitCommit, GitFileChange, GitFileRevision
export GitText, GitTextLine, GitDiffText, GitFileText
export GitCommitRange, ApplyGitCommitRangeOperation
export GitTheme, ScaledGitTheme, GitTextToText, GitCommitToWidget, GitFileChangeToWidget, GitFileRevisionToWidget,
       GitCommitRangeToWidget

include("GitParse.jl")
include("GitRead.jl")
include("GitDocument.jl")
include("GitText.jl")
include("GitRange.jl")
include("GitTheme.jl")
include("GitToWidget.jl")

end # module GitModule
