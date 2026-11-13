# The commits of a range: a document that reads its commits as a folder reads its
# entries, merges each new read by hash, and reads again when a ref of the range
# moves while a holder holds it.

"""
    GitCommitRange(repository, revisions; paths = String[])

The commits that `git log <revisions> -- <paths>` answers in the repository in the
folder `repository`, in the order of the log, with no limit. `revisions` holds the
revisions of the log, apart by spaces, such as `"9ccb5c8e59..origin/master"`.
`paths` go to git after `--` as they are, so the rules of a pathspec of git apply,
such as `":(exclude)*.rst"`.

`commits` holds a [`GitCommit`](@ref) for each commit, with the header of the log,
so a commit reads only its changes. `text` is the text of its page, a
[`GitLogText`](@ref). A part that reads `commits` records a demand for
the read.
The read of the field `listing` throws a [`GitException`](@ref) with the words of
git when the read failed, and `reading` is `true` while git runs. A new read keeps
the document of each commit that stays in the range, so a view keeps its marks and
its selection, and a new commit is one insert.

A holder of the range watches the folders that hold the refs of the range:
`folders`, which the last read found: the folder of each loose ref that the
revisions name, the common git folder for `packed-refs`, and the git folder of the
worktree for `HEAD`. A move of a ref, such as a commit or a `git fetch`, raises
`read_count`, so a part that shows the commits reads them again.
"""
@document struct GitCommitRange <: GitDocument
    repository::String
    revisions::String
    paths::Any
    commits::Any
    text::Any
    folders::Any
    read_count::Int
    reading::Bool
    listing::Any
end

function GitCommitRange(repository::AbstractString, revisions::AbstractString;
                        paths::AbstractVector{<:AbstractString} = String[])
    folder = abspath(repository)
    names = String(revisions)
    pathspecs = String[String(path) for path in paths]
    read_count = Cell(0)
    reading = Cell(false)
    stored = CellVector(Any[])
    holder = Ref{Any}(nothing)
    listing = make_background_cell(_make_git_source(), () -> (:range, folder, names, pathspecs, read_count[]);
                                   working = reading,
                                   apply = (inputs, answer) ->
                                       ApplyGitCommitRangeOperation(holder[], stored, last(inputs), answer))
    # A read of the commits records a demand for the read, and the commits stay what
    # the last read found while a new read runs or after a read failed.
    commits = Cell(@computation (_read_git_answer(listing); stored))
    text = _make_git_text(GitLogText, () -> _make_range_lines(names, pathspecs, listing, stored))
    range = GitCommitRange(folder, names, Cell(pathspecs), commits, text, Cell(String[]), read_count, reading, listing)
    holder[] = range
    range
end

# A walk of the documents does not read the commits: the read runs git, and a range
# can hold thousands of commits.
is_field_walked(::GitCommitRange, name::Symbol) = !(name in (:commits, :text, :listing))

pred_arguments(range::GitCommitRange) =
    ((range.repository, range.revisions), isempty(range.paths) ? Pair{Symbol,Any}[] : Pair{Symbol,Any}[:paths => range.paths])

# The commits of a range and the folders of its refs. A revision that starts with
# `-` is no option: the log reads it after `--end-of-options`, and `rev-parse`, which
# takes no such mark, does not get it.
function _read_git_range(repository::String, revisions::String, paths::Vector{String})
    names = String.(split(revisions))
    log_text = _run_git(repository, ["log", "-z", "--format=" * _HEADER_FORMAT, "--end-of-options", names..., "--",
                                paths...])
    git_folders = split(_run_git(repository, ["rev-parse", "--path-format=absolute", "--git-dir",
                                              "--git-common-dir"]), '\n'; keepempty = false)
    git_folder, common_folder = String(git_folders[1]), String(git_folders[2])
    refs = String[]
    shown = filter(name -> !startswith(name, "-"), names)
    if !isempty(shown)
        for line in split(_run_git(repository, ["rev-parse", "--symbolic-full-name", shown...]), '\n'; keepempty = false)
            ref = lstrip(line, '^')
            startswith(ref, "refs/") && push!(refs, String(ref))
        end
    end
    folders = String[git_folder, common_folder]
    for ref in refs
        # A ref of a worktree is in the git folder of the worktree, and every other
        # ref is in the common folder.
        root = startswith(ref, "refs/bisect/") || startswith(ref, "refs/worktree/") ? git_folder : common_folder
        push!(folders, _find_existing_folder(dirname(joinpath(root, ref)), root))
    end
    (headers = parse_git_log_text(log_text), folders = unique!(folders))
end

# `folder`, or the nearest folder above it, up to `root`, that exists: a ref that
# `packed-refs` holds has no folder of loose refs yet, and the folder above it sees
# the folder come.
function _find_existing_folder(folder::String, root::String)
    while !isdir(folder) && length(folder) > length(root)
        folder = dirname(folder)
    end
    folder
end

"""
    ApplyGitCommitRangeOperation(range, commits, read_count, answer)

Write what a read of `range` found into `commits`, the vector of its commits: a
commit that stays keeps its document, and the commits that come and go between the
commits that stay at the start and at the end are one splice. Store the folders of
the refs, and watch them while a holder holds the range. The answer of a read that
a newer read follows is dropped: `read_count` names the read. A read that failed
changes nothing; the read of `listing` throws its words. It is a write of view
state, so undo records no read.
"""
struct ApplyGitCommitRangeOperation <: Operation
    range::GitCommitRange
    commits::CellVector
    read_count::Int
    answer::Any
end

function evaluate_operation(editor, operation::ApplyGitCommitRangeOperation)
    range = operation.range
    operation.read_count == range.read_count || return nothing
    answer = operation.answer
    answer isa Exception && return nothing
    _merge_range_commits!(editor, range, operation.commits, answer.headers)
    _change_range_folders!(editor, range, answer.folders)
    nothing
end

# The commits of the log `headers` in `commits`: the document of each commit that
# stays, and a new commit with the header of the log for each other one, written as
# one splice between the commits that stay at the start and at the end.
function _merge_range_commits!(editor, range::GitCommitRange, commits::CellVector, headers)
    old = collect(commits)
    kept = Dict{String,Any}(commit.header.hash => commit for commit in old)
    new = Any[get(() -> GitCommit(range.repository, header.hash; header), kept, header.hash) for header in headers]
    head = 0
    while head < min(length(old), length(new)) && old[head + 1] === new[head + 1]
        head += 1
    end
    tail = 0
    while tail < min(length(old), length(new)) - head && old[end - tail] === new[end - tail]
        tail += 1
    end
    removed = length(old) - head - tail
    inserted = new[(head + 1):(length(new) - tail)]
    removed == 0 && isempty(inserted) && return nothing
    reference = extend_reference(EmptyReference(), RangeReferenceStep(head, head + removed))
    evaluate_operation(editor, ReplaceReferencedValueOperation(commits, reference, inserted))
    nothing
end

# Store the folders of the refs, and move the watch to them while a holder holds the
# range.
function _change_range_folders!(editor, range::GitCommitRange, folders::Vector{String})
    old = range.folders
    old == folders && return nothing
    store = editor === nothing ? nothing : find_file_change_store(editor)
    if store !== nothing && is_document_held(editor, range)
        foreach(folder -> folder in folders || unwatch_folder!(folder; store, receiver = range), old)
        foreach(folder -> folder in old || watch_folder!(folder; store, receiver = range), folders)
    end
    range.folders = folders
    nothing
end

# A holder watches the folders of the refs that the last read found; the first read
# of a held range starts the watch when it finds them. The release stops the watch
# and keeps the commits.
function acquire_document!(editor, range::GitCommitRange)
    store = find_file_change_store(editor)
    store === nothing && return nothing
    foreach(folder -> watch_folder!(folder; store, receiver = range), range.folders)
    nothing
end

function release_document!(editor, range::GitCommitRange)
    store = find_file_change_store(editor)
    store === nothing && return nothing
    foreach(folder -> unwatch_folder!(folder; store, receiver = range), range.folders)
    nothing
end

# A move of a ref makes the commits out of date, so a part that shows them reads
# them again.
function receive_folder_change!(editor, range::GitCommitRange, folder)
    range.read_count += 1
    true
end
