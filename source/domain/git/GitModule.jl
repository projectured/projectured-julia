"""
    GitModule

The git domain: a commit, the change of one file in a commit, a file at a revision
and the commits of a range, which the `git` program reads off the loop; their texts and their pages,
which the text domain draws; the address `git+file://<repository>#<revision>`
that a link names them by; and the values of the output of git with the functions
that read that output.
"""
module GitModule

using ..KernelModule
using ..PlatformModule

# Imported to extend: this module adds a method to each of these.
import ..SerializationModule: pred_arguments
import ..ProjectionModule: print_document, map_operation_backward, map_reference_forward, map_reference_backward,
                           get_projection_gesture_bindings, read_intent
import ..GestureBindingModule: read_gesture
import ..DocumentModule: get_document_title, is_field_walked
import ..WidgetModule: make_graphics_projection
import ..OperationModule: evaluate_operation
import ..DomainModule: acquire_document!, release_document!, get_document_decoration
import ..TreeModule: get_tree_children_steps, format_tree_node_label
import ..SelectionModule: has_dormant_selection
import ..FileChangeModule: receive_folder_change!
import ..RosterModule: get_item_facets, compute_item_facet
import ..LinkModule: find_url_document

export GitCommitHeader, GitFileSummary, GitDiffFile, GitDiffHunk, GitDiffLine
export parse_git_log_text, parse_git_commit_text, parse_git_diff_text
export GitException
export GitDocument, GitCommit, GitFileChange, GitFileRevision, GitChangedFolder
export GitText, GitTextLine, GitLinePlace, GitDiffText, GitFileText
export GitCommitRange, ApplyGitCommitRangeOperation
export read_git_document!
export GitTheme, ScaledGitTheme, GitTextToText, GitCommitToWidget, GitFileChangeToWidget, GitFileRevisionToWidget,
       GitCommitRangeToWidget

include("GitParse.jl")
include("GitRead.jl")
include("GitDocument.jl")
include("GitTree.jl")
include("GitText.jl")
include("GitRange.jl")
include("GitAddress.jl")
include("GitProgram.jl")
include("GitTheme.jl")
include("GitToWidget.jl")

# The sentence that the system text of a window says about the domain while the
# package is loaded; the mark on `GitDocument` and on `read_git_document!` offers
# the names.
function __init__()
    register_assistant_api!(Any[];
        description = "A git repository shows as documents: `GitCommitRange` holds the commits of a range, " *
                      "`GitCommit` a commit with its changed files and its diffs, and `GitFileRevision` a file " *
                      "at a revision; `read_git_document!` finishes their reads of git before code reads their fields.")
end

end # module GitModule
