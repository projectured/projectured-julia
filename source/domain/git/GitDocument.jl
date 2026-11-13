# The documents of the git domain: a commit, the change of one file in a commit,
# and a file at a revision.

"""
    GitDocument

A document of the git domain. Each document holds the absolute path of its
repository, and reads what it shows by the `git` program, off the loop: a print
that reads a field asks for the read, and a task runs `git` after the frame. The
cell of the field holds the answer. While the answer is still to come, the cell is
provisional (`is_cell_provisional`), and `reading` is `true` while git runs. A read
of the field of a read that failed throws a [`GitException`](@ref) with the words
of git.
"""
abstract type GitDocument <: Document end

"""
    GitCommit(repository, revision; header = nothing)

The commit that `revision` names in the repository in the folder `repository`. A
revision is a hash, a branch, a tag, or another name that git reads, such as
`HEAD~2`. The read gives the `header`, a [`GitCommitHeader`](@ref), and the
`changes`, a [`GitFileChange`](@ref) for each changed file against the first
parent. A commit never changes, so its read runs one time. A `header` that a log
gave already is the header of the commit, and the read then gives only the changes.
"""
@document struct GitCommit <: GitDocument
    repository::String
    revision::String
    header::Any
    changes::Any
    reading::Bool
end

function GitCommit(repository::AbstractString, revision::AbstractString;
                   header::Union{GitCommitHeader,Nothing} = nothing)
    folder = abspath(repository)
    name = String(revision)
    source = _make_git_source()
    reading = Cell(false)
    read = make_background_cell(source, () -> (:commit, folder, name); working = reading)
    header_cell = header === nothing ? Cell(@computation _get_read_header(read[])) : Cell(header)
    changes = Cell(@computation _make_file_changes(source, folder, read[]))
    GitCommit(folder, name, header_cell, changes, reading)
end

_get_read_header(answer) = answer === nothing ? nothing : answer.header

# The change of each file that the read of a commit names. The answer of a commit is
# final, so this runs one time for it, and each change keeps its document.
function _make_file_changes(source::BackgroundSource, repository::String, answer)
    answer === nothing && return CellVector(Any[])
    header = answer.header
    parent = isempty(header.parents) ? nothing : first(header.parents)
    CellVector(Any[_make_file_change(source, repository, header.hash, parent, file) for file in answer.files])
end

"""
    GitFileChange

The change of one file in a commit, which the read of its [`GitCommit`](@ref)
makes. It holds what that read knew: the `kind` of the change, the old and the new
path, the counts of the added and the removed lines, and whether the file is
binary. `old_revision` is the first parent of the commit, or `nothing` for a root
commit, and `new_revision` is the hash of the commit. An added file has no old
path, and a deleted file has no new path. Its read gives the `hunks`, a vector of
[`GitDiffHunk`](@ref).
"""
@document struct GitFileChange <: GitDocument
    repository::String
    old_revision::Union{String,Nothing}
    new_revision::String
    kind::Symbol
    old_path::Union{String,Nothing}
    new_path::Union{String,Nothing}
    added_count::Int
    removed_count::Int
    is_binary::Bool
    hunks::Any
    reading::Bool
end

function _make_file_change(source::BackgroundSource, repository::String, hash::String, parent, file::GitFileSummary)
    reading = Cell(false)
    old_path = file.old_path
    new_path = file.new_path
    hunks = make_background_cell(source, () -> (:patch, repository, hash, old_path, new_path);
                                 default = GitDiffHunk[], working = reading)
    GitFileChange(repository, parent, hash, file.kind, old_path, new_path, file.added_count, file.removed_count,
                  file.is_binary, hunks, reading)
end

"""
    GitFileRevision(repository, revision, path; line = nothing)

The file at `path` in the commit that `revision` names, in the repository in the
folder `repository`. `path` starts at the top folder of the repository. Its read
gives the `text`. `line` is the line to show, or `nothing`.
"""
@document struct GitFileRevision <: GitDocument
    repository::String
    revision::String
    path::String
    line::Union{Int,Nothing}
    text::Any
    reading::Bool
end

function GitFileRevision(repository::AbstractString, revision::AbstractString, path::AbstractString;
                         line::Union{Integer,Nothing} = nothing)
    folder = abspath(repository)
    name = String(revision)
    file_path = String(path)
    reading = Cell(false)
    text = make_background_cell(_make_git_source(), () -> (:file, folder, name, file_path);
                                default = "", working = reading)
    GitFileRevision(folder, name, file_path, line === nothing ? nothing : Int(line), text, reading)
end

# A `.pred` file names a commit by its repository and its hash, once the read gave
# the hash, and else by the revision that it was made with.
pred_arguments(commit::GitCommit) = ((commit.repository, _get_commit_name(commit)), Pair{Symbol,Any}[])

function _get_commit_name(commit::GitCommit)
    cell = getfield(commit, :header)
    header = try
        cell[]
    catch exception
        exception isa GitException || rethrow()
        nothing
    end
    header isa GitCommitHeader && !is_cell_provisional(cell) ? header.hash : commit.revision
end

pred_arguments(file::GitFileRevision) =
    ((file.repository, file.revision, file.path),
     file.line === nothing ? Pair{Symbol,Any}[] : Pair{Symbol,Any}[:line => file.line])
