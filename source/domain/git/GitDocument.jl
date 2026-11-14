# The documents of the git domain: a commit, the change of one file in a commit,
# and a file at a revision.

"""
    GitDocument

A document of the git domain: the commits of a range (`GitCommitRange`), a commit
(`GitCommit`), the change of one file in a commit (`GitFileChange`) and a file at
a revision (`GitFileRevision`). Each holds the absolute path of its repository,
and reads what it shows by the `git` program, off the loop: a print that reads a
field records a demand for the read, and a task runs `git` after the frame. The
cell of the field holds the answer. While the answer is still to come, the cell is
provisional (`is_cell_provisional`), and `reading` is `true` while git runs. A
read of the field of a read that failed throws a [`GitException`](@ref) with the
words of git. Code finishes the reads with `read_git_document!` before it reads
the fields. A link names a commit as `git+file://<repository>#<revision>`, and a
file at a revision as `git+file://<repository>#<revision>:<path>`.

Use it to show the commits of a range, a commit with its changed files and its
diffs, or a file at a revision as a page, and to read what git says about them.

# Example

    range_1 = GitCommitRange("/home/me/inet-cpp", "v4.6.0..v4.7.0")
    tab_1 = open_pane!(range_1)
    show_pane!(tab_1)
    open_pane!(GitCommit("/home/me/inet-cpp", "HEAD~2"))
    open_pane!(GitFileRevision("/home/me/inet-cpp", "v4.7.0", "src/inet/common/Units.h"; line = 120))

See also `read_git_document!`, `GitCommitRange`, `GitCommit`, `GitFileRevision`.

For the assistant.
"""
abstract type GitDocument <: Document end

"""
    GitCommit(repository, revision; header = nothing)

The commit that `revision` names in the repository in the folder `repository`. A
revision is a hash, a branch, a tag, or another name that git reads, such as
`HEAD~2`. The read gives the `header`, a [`GitCommitHeader`](@ref), and the
`changes`, a [`GitFileChange`](@ref) for each changed file against the first
parent. `table` is the arrangement of a roster of the changes, which its page draws
and a person filters and sorts, and `diff` is the text of the diffs of its page, a
[`GitDiffText`](@ref). A commit never changes, so its read runs one time. A `header` that a log gave already is the
header of the commit, and the read then gives only the changes.
"""
@document struct GitCommit <: GitDocument
    repository::String
    revision::String
    header::Any
    changes::Any
    table::Any
    diff::Any
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
    diff = _make_git_text(GitDiffText, () -> _make_commit_lines(header_cell, changes))
    commit = GitCommit(folder, name, header_cell, changes, Cell(nothing), diff, reading)
    roster = Roster(CollectionItems(extend_reference(EmptyReference(), FieldReferenceStep("changes")));
                    columns = _CHANGE_COLUMNS, title = "Changed files", shares = _CHANGE_SHARES)
    link_roster!(roster, commit)
    commit.table = ArrangementDocument(roster, ArrangementEntry[])
    commit
end

# The columns of the table of the changed files of a commit, and their shares of the
# width. The first column, the path, is a link to the page of the change.
const _CHANGE_COLUMNS = ["path", "change", "added", "removed"]
const _CHANGE_SHARES = [6, 1, 1, 1]

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
makes. It holds the facts of that read: the `kind` of the change, the old and the new
path, the counts of the added and the removed lines, and whether the file is
binary. `old_revision` is the first parent of the commit, or `nothing` for a root
commit, and `new_revision` is the hash of the commit. An added file has no old
path, and a deleted file has no new path. Its read gives the `hunks`, a vector of
[`GitDiffHunk`](@ref). `diff` is the text of its page, a [`GitDiffText`](@ref).
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
    diff::Any
    reading::Bool
end

# A walk of the documents does not read a diff or a text: the read runs git, and a
# diff can hold thousands of lines that no walk needs. A page reads them when it
# shows them.
is_field_walked(::GitCommit, name::Symbol) = !(name in (:table, :diff))
is_field_walked(::GitFileChange, name::Symbol) = !(name in (:hunks, :diff))

# The facets of a change, which the columns of the table of a commit show and a
# person filters and sorts by.
get_item_facets(::Type{GitFileChange}) = [
    "path" => "the path of the file; for a rename or a copy, the old and the new path",
    "change" => "the kind of the change in words, and binary for a binary file",
    "added" => "the count of the added lines",
    "removed" => "the count of the removed lines"]
compute_item_facet(change::GitFileChange, ::Val{:path}) =
    _format_change_path(change.kind, change.old_path, change.new_path)
compute_item_facet(change::GitFileChange, ::Val{:change}) =
    change.is_binary ? _format_change_kind(change.kind) * ", binary" : _format_change_kind(change.kind)
compute_item_facet(change::GitFileChange, ::Val{:added}) = change.added_count
compute_item_facet(change::GitFileChange, ::Val{:removed}) = change.removed_count

function _make_file_change(source::BackgroundSource, repository::String, hash::String, parent, file::GitFileSummary)
    reading = Cell(false)
    old_path = file.old_path
    new_path = file.new_path
    hunks = make_background_cell(source, () -> (:patch, repository, hash, old_path, new_path);
                                 default = GitDiffHunk[], working = reading)
    kind, added_count, removed_count, is_binary = file.kind, file.added_count, file.removed_count, file.is_binary
    diff = _make_git_text(GitDiffText, () -> _make_change_lines(repository, kind, old_path, new_path, added_count,
                                                                removed_count, is_binary, parent, hash, hunks))
    GitFileChange(repository, parent, hash, kind, old_path, new_path, added_count, removed_count, is_binary, hunks,
                  diff, reading)
end

"""
    GitFileRevision(repository, revision, path; line = nothing)

The file at `path` in the commit that `revision` names, in the repository in the
folder `repository`. `path` starts at the top folder of the repository. Its read
gives the `text`. `line` is the line to show, or `nothing`. `content` is the text of
its page, a [`GitFileText`](@ref).
"""
@document struct GitFileRevision <: GitDocument
    repository::String
    revision::String
    path::String
    line::Union{Int,Nothing}
    text::Any
    content::Any
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
    named = line === nothing ? nothing : Int(line)
    selection = named === nothing ? nothing :
                ConcreteReference(GitFileText, FieldReferenceStep("lines"),
                                  ConcreteReference(Vector{GitTextLine}, ElementReferenceStep(named),
                                                    EmptyReference(GitTextLine)))
    content = _make_git_text(GitFileText, () -> _make_file_lines(text, named); selection)
    GitFileRevision(folder, name, file_path, named, text, content, reading)
end

is_field_walked(::GitFileRevision, name::Symbol) = name !== :content

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
