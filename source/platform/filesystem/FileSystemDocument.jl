# Fragment of `FileSystemModule` — the file-system document types: the abstract
# `FileSystemDocument`, its insertion placeholder, and the file and directory
# nodes.

abstract type FileSystemDocument <: Document end

# ── FileSystemInsertion ─────────────────────────────────────────────────

@document struct FileSystemInsertion <: FileSystemDocument
    value::Any = nothing
end

# ── File ──────────────────────────────────────────────────────────────────────

@document struct FileSystemFile <: FileSystemDocument
    pathname::String
end


# ── Directory ─────────────────────────────────────────────────────────────────

"""
    FileSystemDirectory(pathname, elements; state = :read, failure = nothing, has_entries = nothing)

A folder on the disk, as the last read found it. `elements` holds its entries in
the order of their names, each a `FileSystemFile` or a `FileSystemDirectory`;
the entries are stored, so a print reads only what the folder holds, and never
the disk.

`state` is `:unread`, `:reading`, `:read`, or `:failed` with the exception in
`failure`. `has_entries` says whether the folder holds an entry, as the read of
its parent found it: `true`, `false`, or `nothing` while that is not known. A
folder that is read answers from its entries ([`has_folder_entries`](@ref)).

A holder of the folder acquires it, such as an explorer whose folder is open: the
acquire reads the folder off the loop and watches it, and the watch reads it
again when an entry comes, goes or changes. A new read keeps the document of each
entry that stays, so an open folder stays open, and a new entry is one insert.
The release stops the watch and keeps the entries. For a caller that runs
outside an editor, [`read_filesystem_folder!`](@ref) reads at once.
"""
@document struct FileSystemDirectory <: FileSystemDocument
    pathname::String
    elements::CellVector
    state::Symbol = :read
    failure::Any = nothing
    has_entries::Any = nothing
    read_count::Int = 0
end

"""
    has_folder_entries(folder) -> Bool or nothing

Whether `folder` holds an entry: from its entries when it is read, else as the
read of its parent found it, and `nothing` while that is not known.
"""
has_folder_entries(folder::FileSystemDirectory) =
    folder.state === :read ? !isempty(folder.elements) : folder.has_entries


# ── Choose a path ─────────────────────────────────────────────────────────────

"""
A place to choose a path: a `directory` to look in, and a `name` a person types.

It is the document behind Open and Save As. It **chooses a path and does nothing
with one**: a path that does not exist yet is a name typed into a directory,
which is what Save As is for, and a path that does exist is a row of the tree,
which is what Open is for. What happens to the chosen path belongs to whoever
opened the chooser.

`name` is the whole of what a person types, and a file row of the tree writes its
own name there. The directory and the name together always say one path, and
[`get_chosen_path`](@ref) is that path.

`open` holds the open folders of the chooser, by their documents, as an explorer
holds its own ([`WorkspaceExplorer`](@ref)); the directory is open at the start.
It is view state. The chooser holds its open folders, so each one reads and
watches itself while the chooser is shown.
"""
@document struct FileSystemChooser <: FileSystemDocument
    directory::Document
    open::IdDict{Any,Nothing}
    name::AbstractString = ""
end

FileSystemChooser(directory::Document) = FileSystemChooser(directory, IdDict{Any,Nothing}(directory => nothing))

acquire_document!(editor, chooser::FileSystemChooser) = hold_documents!(editor, chooser, collect(keys(chooser.open)))

release_document!(editor, chooser::FileSystemChooser) =
    release_held_documents!(editor, chooser, collect(keys(chooser.open)))

"""
    get_chosen_path(chooser) -> String

The path `chooser` names: its directory and the name typed in it. An empty name
answers the directory itself, because a person who has typed nothing has chosen
no file.
"""
get_chosen_path(chooser::FileSystemChooser) =
    isempty(chooser.name) ? chooser.directory.pathname :
                            joinpath(chooser.directory.pathname, chooser.name)

"""
    make_filesystem_chooser(directory) -> FileSystemChooser

A chooser over the directory at `directory`, read from disk.
"""
make_filesystem_chooser(directory::AbstractString) =
    FileSystemChooser(make_filesystem_pathname(abspath(directory)))

# ── Open a file ───────────────────────────────────────────────────────────────

# The destination is a pane tree, in a new tab: `make_file_tab` reads the file into
# the document type its extension owns, in a scroll pane, and `get_pane_file_group`
# asks the pane tree where a file belongs. An editor with settings gives the file a
# history (`make_history_wrap`), around the part that the opener puts around the
# file, or around the content. This runs while the editor evaluates the open, so
# the new tab is posted, and the loop evaluates it at the top of the next frame.
function evaluate_operation(editor, op::OpenFileOperation)
    settings = find_editor_settings(; editor)
    history = settings === nothing ? identity : make_history_wrap(settings)
    tab = op.file_wrap === identity ?
          make_file_tab_content(op.path, document -> history(op.wrap(document))) :
          make_file_page(WidgetScrollPane(history(op.file_wrap(make_file_tab(op.path, op.wrap)))))
    post_pane_operation!(editor, make_open_pane_operation(tab; group = get_pane_file_group(; editor), editor))
    nothing
end


# ── API ───────────────────────────────────────────────────────────────────────

"""
    make_filesystem_pathname(pathname) -> FileSystemDocument

The file or the folder at `pathname`. A folder is made unread: its entries come
with its first acquire, or with [`read_filesystem_folder!`](@ref). It costs one
`isdir` of `pathname`, in the code of the caller and never in a print.
"""
function make_filesystem_pathname(pathname::AbstractString)
    p = String(pathname)
    isdir(p) ? FileSystemDirectory(p, CellVector(), :unread) : FileSystemFile(p)
end

"""
    read_filesystem_folder!(folder; depth = 1) -> folder

Read `folder` at once on the calling task, and its sub-folders down to `depth`
levels, for a script, an example or a test that shows a folder with no editor.
It never runs in a print. A folder that can not be read is `:failed`.
"""
function read_filesystem_folder!(folder::FileSystemDirectory; depth::Integer = 1)
    depth < 1 && return folder
    listing = try
        _read_folder_listing(folder.pathname)
    catch exception
        exception isa Base.IOError || rethrow()
        exception
    end
    _apply_folder_listing!(nothing, folder, listing)
    for entry in folder.elements
        entry isa FileSystemDirectory && read_filesystem_folder!(entry; depth = depth - 1)
    end
    folder
end

# ── The read of a folder ──────────────────────────────────────────────────────

# The entries of the folder at `path`, in the order of their names: the name of
# each, whether it is a folder, and for a folder whether it holds an entry. One
# call gives each name with its kind, so no entry costs a `stat`.
function _read_folder_listing(path::String)
    entries = isdefined(Base.Filesystem, :_readdirx) ?
        [(entry.name, isdir(entry)) for entry in Base.Filesystem._readdirx(path)] :
        [(name, isdir(joinpath(path, name))) for name in readdir(path)]
    [(name = name, is_folder = is_folder,
      has_entries = is_folder ? _read_folder_emptiness(joinpath(path, name)) : false)
     for (name, is_folder) in entries]
end

# Whether the folder at `path` holds an entry; `nothing` when it can not be read.
function _read_folder_emptiness(path::String)
    try
        !isempty(readdir(path; sort = false))
    catch exception
        exception isa Base.IOError || rethrow()
        nothing
    end
end

# The key of the folder at `path`, as the watch of a folder names it: the absolute
# path with no separator at its end.
function _get_folder_key(path::AbstractString)
    folder = normpath(abspath(path))
    length(folder) > 1 && endswith(folder, '/') ? folder[1:(end - 1)] : folder
end

_get_entry_name(entry::FileSystemDocument) = basename(_get_folder_key(entry.pathname))

_is_same_entry_kind(entry::FileSystemDirectory, listed) = listed.is_folder
_is_same_entry_kind(entry::FileSystemDocument, listed) = !listed.is_folder

function _make_listed_entry(folder::FileSystemDirectory, listed)
    path = joinpath(folder.pathname, listed.name)
    listed.is_folder || return FileSystemFile(path)
    FileSystemDirectory(path, CellVector(), :unread, nothing, listed.has_entries, 0)
end

"""
    ApplyFolderListingOperation(folder, read_count, listing)

Write what a read of `folder` found: `listing`, the entries in the order of their
names, or the exception of the read. A kept entry keeps its document, each run of
new and gone entries is one splice of `elements`, and a sub-folder that stays
takes its new emptiness. The answer of a read that a newer read follows is
dropped: `read_count` names the read. A watched folder watches each new
sub-folder for its emptiness. It is a write of view state, so undo records no
read.
"""
struct ApplyFolderListingOperation <: Operation
    folder::FileSystemDirectory
    read_count::Int
    listing::Any
end

function evaluate_operation(editor, operation::ApplyFolderListingOperation)
    operation.read_count == operation.folder.read_count || return nothing
    _apply_folder_listing!(editor, operation.folder, operation.listing)
end

"""
    ApplyFolderEmptinessOperation(folder, has_entries)

Write whether the sub-folder `folder` holds an entry, as a check of its own found
it after its watch reported a change. A write of view state.
"""
struct ApplyFolderEmptinessOperation <: Operation
    folder::FileSystemDirectory
    has_entries::Any
end

function evaluate_operation(editor, operation::ApplyFolderEmptinessOperation)
    folder = operation.folder
    folder.has_entries == operation.has_entries || (folder.has_entries = operation.has_entries)
    nothing
end

# Write a listing into `folder`: walk the stored entries and the listing by name,
# keep each entry that stays, and replace each run of gone and new entries with one
# splice, so a new file is one insert and the entries after it keep their prints.
function _apply_folder_listing!(editor, folder::FileSystemDirectory, listing)
    if listing isa Exception
        folder.state = :failed
        folder.failure = listing
        return nothing
    end
    elements = folder.elements
    store = _find_watching_store(editor, folder)
    position = 1
    start = 0
    removed = Any[]
    inserted = Any[]
    function flush!()
        start == 0 && return nothing
        reference = extend_reference(EmptyReference(), FieldReferenceStep("elements"),
                                     RangeReferenceStep(start - 1, start - 1 + length(removed)))
        evaluate_operation(editor, ReplaceReferencedValueOperation(folder, reference, copy(inserted)))
        foreach(entry -> _unwatch_folder_entry!(store, folder, entry), removed)
        foreach(entry -> _watch_folder_entry!(store, folder, entry), inserted)
        position = start + length(inserted)
        start = 0
        empty!(removed)
        empty!(inserted)
        nothing
    end
    old = collect(elements)
    i = 1
    for listed in listing
        while i <= length(old) && _get_entry_name(old[i]) < listed.name
            start == 0 && (start = position)
            push!(removed, old[i])
            i += 1
        end
        if i <= length(old) && _get_entry_name(old[i]) == listed.name && _is_same_entry_kind(old[i], listed)
            flush!()
            kept = old[i]
            kept isa FileSystemDirectory && kept.has_entries != listed.has_entries &&
                (kept.has_entries = listed.has_entries)
            position += 1
            i += 1
            continue
        end
        start == 0 && (start = position)
        if i <= length(old) && _get_entry_name(old[i]) == listed.name
            push!(removed, old[i])
            i += 1
        end
        push!(inserted, _make_listed_entry(folder, listed))
    end
    if i <= length(old)
        start == 0 && (start = position)
        append!(removed, old[i:end])
    end
    flush!()
    folder.state === :read || (folder.state = :read)
    folder.failure === nothing || (folder.failure = nothing)
    nothing
end

# ── The acquire of a folder ──────────────────────────────────────────────────

# A folder that enters the window watches itself and each of its sub-folders, the
# sub-folders for their emptiness, and reads itself. The release stops the
# watches and keeps the entries.
function acquire_document!(editor, folder::FileSystemDirectory)
    store = find_file_change_store(editor)
    if store !== nothing && watch_folder!(folder.pathname; store, receiver = folder)
        foreach(entry -> _watch_folder_entry!(store, folder, entry), folder.elements)
    end
    _start_folder_read!(editor, folder)
    nothing
end

function release_document!(editor, folder::FileSystemDirectory)
    store = find_file_change_store(editor)
    store === nothing && return nothing
    unwatch_folder!(folder.pathname; store, receiver = folder)
    foreach(entry -> _unwatch_folder_entry!(store, folder, entry), folder.elements)
    nothing
end

# The store in which `folder` watches itself, or `nothing`: a folder that does not
# watch itself watches none of its sub-folders either.
function _find_watching_store(editor, folder::FileSystemDirectory)
    store = find_file_change_store(editor)
    store !== nothing && is_folder_watched(folder.pathname; store, receiver = folder) ? store : nothing
end

# A sub-folder is watched for its emptiness with its parent as the receiver; past
# the limit of the store it is not watched, and its next read of its parent says it.
_watch_folder_entry!(store, folder, entry) =
    store !== nothing && entry isa FileSystemDirectory && watch_folder!(entry.pathname; store, receiver = folder)

_unwatch_folder_entry!(store, folder, entry) =
    store !== nothing && entry isa FileSystemDirectory && unwatch_folder!(entry.pathname; store, receiver = folder)

# Read `folder` off the loop. A folder that holds a listing shows it during the
# read; one that holds none shows that it reads.
function _start_folder_read!(editor, folder::FileSystemDirectory)
    folder.read_count += 1
    read_count = folder.read_count
    folder.state === :read || (folder.state = :reading)
    path = folder.pathname
    start_document_read!(editor, () -> _read_folder_listing(path),
                         answer -> ReplaceViewStateOperation(ApplyFolderListingOperation(folder, read_count, answer)))
    nothing
end

# A change of the folder reads it again; a change of one of its sub-folders checks
# whether that sub-folder holds an entry.
function receive_folder_change!(editor, folder::FileSystemDirectory, path)
    if path == _get_folder_key(folder.pathname)
        _start_folder_read!(editor, folder)
        return true
    end
    index = findfirst(entry -> entry isa FileSystemDirectory && _get_folder_key(entry.pathname) == path,
                      collect(folder.elements))
    index === nothing && return false
    child = folder.elements[index]
    start_document_read!(editor, () -> _read_folder_emptiness(path),
                         answer -> ReplaceViewStateOperation(ApplyFolderEmptinessOperation(child, answer)))
    true
end

# A folder reads while its read runs on its task, and failed when the read did,
# with the failure in words.
function get_document_decoration(folder::FileSystemDirectory)
    state = folder.state
    state === :reading && return DocumentDecoration(; icon = :folder, conditions = [DocumentCondition(:running)])
    state === :failed &&
        return DocumentDecoration(; icon = :folder, conditions = [DocumentCondition(:failed)],
                                  tooltip = sprint(showerror, folder.failure))
    DocumentDecoration(; icon = :folder)
end

get_document_decoration(file::FileSystemFile) = DocumentDecoration(; icon = get_file_icon(file.pathname))
