# Fragment of `FileSystemModule` — the file-system document types: the abstract
# `FileSystemDocument`, its insertion placeholder, and the file and directory
# nodes.

"""
    FileSystemDocument

The abstract supertype of the documents of files and folders on disk. Its main members are `FileSystemFile`, `FileSystemDirectory`, `FileSystemChooser`.

Use it to recognise the documents of files and folders on disk when you walk a document: a part is one of them when `part isa FileSystemDocument`.

# Example

    parts_1 = search_documents(get_edited_document(find_pane("files")), part -> part isa FileSystemDocument)
    found_1 = search_documents(get_edited_document(find_pane("files")), part -> part isa FileSystemFile)

See also `search_documents`, `find_pane`, `describe_document` and `FileSystemFile`.

For the assistant.
"""
abstract type FileSystemDocument <: Document end

# ── FileSystemInsertion ─────────────────────────────────────────────────

@document struct FileSystemInsertion <: FileSystemDocument
    value::Any = nothing
end

# ── File ──────────────────────────────────────────────────────────────────────

"""
    FileSystemFile(pathname)

A file on the disk, as the read of its folder found it. `document` is the file
document that its page shows, or `nothing` while no holder acquired it: the
acquire takes the file document that the editor holds open for the same path, else
the one that the file kept, else it reads the file, so a file is one document in an
editor, also when a tab shows it. A release keeps a file document with an unsaved
edit, and one that keeps a dormant selection, so the keys go back to where they
were on it.

`document_view` is the view of the file document that the page of the file shows
([`FileView`](@ref)), which keeps its own place in the file apart from a tab that
shows the same file document. It is view state: a save writes none of it, and a walk
does not enter it.
"""
@document struct FileSystemFile <: FileSystemDocument
    pathname::String
    document::Any = nothing
    document_view::Any = nothing
end

get_view_state_fields(::Type{<:FileSystemFile}) = (:document_view,)
is_field_walked(::FileSystemFile, name::Symbol) = name !== :document_view

# A file keeps the path of the file, and not the document that its page showed.
pred_arguments(file::FileSystemFile) = (file.pathname,), Pair{Symbol,Any}[]
make_pred_document(::Type{<:FileSystemFile}, positional, keywords) = FileSystemFile(only(positional))

# The acquire of a file gives it its document: the file document that the editor
# holds open for its path, else the one that the file kept, else a file document
# read from the disk, as the open of a file reads it. It runs in the evaluation of
# the operation that acquires, where a read of the disk is in its place. The file
# then holds the view of the file document, which holds the file document, so the
# file document watches its file.
function acquire_document!(editor, file::FileSystemFile)
    open = find_open_file_document(file.pathname; editor)
    if open !== nothing
        file.document = open
    elseif file.document === nothing
        file.document = _read_opened_file(editor, file.pathname)
    end
    # The view of the file document that the file kept stays, unless another holder
    # holds it, as the duplicate of a tab leaves it.
    view = _get_file_document_view(file)
    (view !== nothing && !is_document_held(editor, view)) ||
        set_cell_value!(getfield(file, :document_view), make_file_view(file.document))
    hold_documents!(editor, file, Any[something(_get_file_document_view(file), file.document)])
end

# The release lets the file document go. The file keeps a file document with an
# unsaved edit or a conflict, and one that keeps a dormant selection, which is where
# the keys were on it, with its view, and forgets any other.
function release_document!(editor, file::FileSystemFile)
    document = file.document
    document === nothing && return nothing
    release_held_documents!(editor, file, Any[something(_get_file_document_view(file), document)])
    (_has_file_edits(document) || _has_dormant_place(document)) ||
        (file.document = nothing; file.document_view = nothing)
    nothing
end

# The view of the file document of `file` that the file shows: the view that it
# keeps while that view shows its file document, and `nothing` otherwise.
function _get_file_document_view(file::FileSystemFile)
    view = file.document_view
    (view isa FileView && view.file === file.document) ? view : nothing
end

_has_file_edits(document) =
    any(condition -> condition.name in (:unsaved, :conflict), get_document_decoration(document).conditions)

_has_dormant_place(document) = get_stored_selection(document) !== nothing && !is_live_selection(document)

# The file document at `path`, with the history of the settings of `editor`.
_read_opened_file(editor, path::AbstractString) = _make_opened_file(editor, OpenFileOperation(path))


# ── Directory ─────────────────────────────────────────────────────────────────

"""
    FileSystemDirectory(pathname, elements; state = :read, failure = nothing, has_entries = nothing)

A folder on the disk, as the last read found it. `elements` holds its entries in
the order of their names, each a `FileSystemFile` or a `FileSystemDirectory`;
the entries are stored, so a print reads only what the folder holds, and never
the disk.

`state` is `:unread`, `:read`, or `:failed` with the exception in `failure`.
`has_entries` says whether the folder holds an entry, as the read of its parent
found it: `true`, `false`, or `nothing` while that is not known. A folder that is
read answers from its entries ([`has_folder_entries`](@ref)).

A folder made from the disk (`make_filesystem_pathname`) reads itself when a part
that shows its entries asks for them (`demand_tree_children`): the open node of a
tree, its page, a search. Its `listing` is a background cell of the path and of
`read_count`, which a task reads after the frame, together with the other folders
of the same tree that the frame asked for (`listing_source`); `reading` says that
the read runs. The answer is stored in the entries: a new read keeps the document
of each entry that stays, so an open folder stays open, and a new entry is one
insert. So a closed folder reads nothing.

A holder of the folder acquires it, such as an explorer whose folder is open: the
acquire watches the folder, and a change of an entry raises `read_count`, so the
part that shows the entries asks again. The release stops the watch and keeps the
entries. For a caller that runs outside an editor,
[`read_filesystem_folder!`](@ref) reads at once.
"""
@document struct FileSystemDirectory <: FileSystemDocument
    pathname::String
    elements::CellVector
    state::Symbol = :read
    failure::Any = nothing
    has_entries::Any = nothing
    read_count::Int = 0
    reading::Bool = false
    listing::Any = nothing            # a background cell of the listing, or nothing
    listing_source::Any = nothing     # the BackgroundSource of the folders of its tree
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
# the document type its extension owns, the tab shows the view of the file
# (`make_file_view`) or the part that the opener puts around it, and
# `get_pane_file_group` asks the pane tree where a file belongs. An editor with
# settings gives the file a history (`make_history_wrap`), around the content inside
# the file, whatever the opener puts around the file. This runs while the editor
# evaluates the open, so the new tab is posted, and the loop evaluates it at the top
# of the next frame.
function evaluate_operation(editor, op::OpenFileOperation)
    # A file that is open is one document: its tab takes the focus, or a tab opens
    # on that document.
    open = find_open_file_document(op.path; editor)
    if open !== nothing
        _focus_open_file!(editor, open) ||
            post_pane_operation!(editor, make_open_pane_operation(make_file_view(open);
                                                                  group = get_pane_file_group(; editor),
                                                                  focus = true, editor))
        return nothing
    end
    # A file opens as a person opens it: the new tab takes the focus.
    post_pane_operation!(editor, make_open_pane_operation(_make_opened_tab_content(editor, op);
                                                          group = get_pane_file_group(; editor),
                                                          focus = true, editor))
    nothing
end

# The file of `op`: read from disk, with each `file("…")` in it given the file
# document that the editor holds for that file, and a history around its content
# when the editor has settings. The splice runs before the history wraps the content,
# so the history gets no step.
function _make_opened_file(editor, op::OpenFileOperation)
    history = _make_editor_history_wrap(editor)
    base_dir = dirname(abspath(op.path))
    make_file_tab(op.path, document -> history(op.wrap(
        splice_held_files!(document, base_dir, path -> open_file_document!(editor, path)))))
end

# What wraps the content of a file that the editor opens: a history when the editor
# has settings, else nothing.
function _make_editor_history_wrap(editor)
    settings = find_editor_settings(; editor)
    settings === nothing ? identity : make_history_wrap(settings)
end

# The file document of a held file at `path` in `editor`: the one that the editor
# holds open, else a new one that reads nothing (`make_unread_file`), with the history
# of the settings of the editor around its content, and in the open files of the
# editor from this call on. It runs on the task of the editor. A new file document
# reads its file when a view of it is drawn, and a holder that holds it watches its
# file.
function open_file_document!(editor::Editor, path::AbstractString)
    run_on_editor_task!(editor; description = "open_file_document!") do
        open = find_open_file_document(path; editor)
        open === nothing || return open
        file = make_unread_file(path, _make_editor_history_wrap(editor))
        add_open_file!(editor, file)
        file
    end
end

# What a new tab shows of the file of `op`: the part that `file_wrap` puts around
# it, whose own views show the file, or else the view of the file.
function _make_opened_tab_content(editor, op::OpenFileOperation)
    file = _make_opened_file(editor, op)
    op.file_wrap === identity ? make_file_view(file) : op.file_wrap(file)
end

# Whether `tab` shows `file`: as its content, or through the layers that hold it,
# such as a view or a navigator.
function _is_document_in_tab(tab, file)
    node = tab.content
    for _ in 1:16
        node === file && return true
        field = get_edited_field(node)
        field === nothing && return false
        node = getproperty(node, field)
    end
    false
end

"""
    open_file!(path; editor = get_evaluation_editor()) -> ReferencedDocument

Open the file at `path` in a tab, where the window puts files, and answer the tab.
The tab shows the file as the extension of its name reads it, and keeps the
history of its edits, so Ctrl+Z undoes them. A file that is open already keeps
its tab, and the answer is that tab. The tab does not take the focus, and the
group shows it only when `show_pane!` shows it.

Use it to open a file of the disk, so that you can read it and change it as a
part of the window.

# Example

    notes_tab_1 = open_file!("notes.json")
    show_pane!(notes_tab_1)

See also `save_file_to_disk!`, `reload_file_from_disk!`, `show_pane!`.

For the assistant.
"""
function open_file! end

function open_file!(path::AbstractString; editor = get_evaluation_editor())
    run_on_editor_task!(editor; description = "open_file!") do
        open = find_open_file_document(path; editor)
        tab = open === nothing ? nothing : _find_open_file_tab(editor, open)
        tab === nothing || return tab
        open_pane!(open === nothing ? _make_opened_tab_content(editor, OpenFileOperation(path)) : make_file_view(open);
                   group = get_pane_file_group(; editor), editor)
    end
end

# The tab that shows `document`, as a part, or `nothing`.
function _find_open_file_tab(editor, document)
    reference = find_pane_tree_reference(; editor)
    reference === nothing && return nothing
    tree = evaluate_reference(editor.document, reference)
    for group in get_pane_groups(tree), (index, tab) in enumerate(group.tabs)
        _is_document_in_tab(tab, document) || continue
        return ReferencedDocument(tab, concat_references(reference, get_pane_tab_reference(tree, group, index)))
    end
    nothing
end


# Focus the tab that shows `document`, and answer whether one is.
function _focus_open_file!(editor, document)
    reference = find_pane_tree_reference(; editor)
    reference === nothing && return false
    tree = evaluate_reference(editor.document, reference)
    for group in get_pane_groups(tree), (index, tab) in enumerate(group.tabs)
        _is_document_in_tab(tab, document) || continue
        focus = read_rooted_operation(editor, reference, make_pane_focus_operation(tree, group, index);
                                      description = "Focus the tab of the file")
        focus === nothing || post_pane_operation!(editor, focus)
        return true
    end
    false
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
    isdir(p) ? _make_unread_folder(p) : FileSystemFile(p)
end

# The folder at `pathname`, not read yet, which reads itself when a part that shows
# its entries asks for them. `has_entries` is what the read of its parent found.
# `source` reads its listing: the one of the folder that holds it, or a new one for
# the root of a tree, so one task reads every folder of a tree that one frame asks
# for. It reads nothing of the disk.
function _make_unread_folder(pathname::AbstractString; has_entries = nothing, source = nothing)
    source === nothing && (source = _make_listing_source())
    path = Cell(String(pathname))
    read_count = Cell(0)
    reading = Cell(false)
    holder = Ref{Any}(nothing)
    listing = make_background_cell(source, () -> (path[], read_count[]); working = reading,
                                   apply = (inputs, answer) -> ApplyFolderListingOperation(holder[], last(inputs), answer))
    folder = FileSystemDirectory(path, CellVector(), Cell(:unread), Cell(nothing), Cell(has_entries), read_count,
                                 reading, listing, Cell(source))
    holder[] = folder
    folder
end

# The work that reads the listings of folders off the loop: one listing for each
# path, or the exception of a folder that can not be read, so one folder that
# fails fails no other.
_make_listing_source() =
    BackgroundSource(inputs -> Any[_read_folder_answer(path) for (path, _) in inputs];
                     description = "the listings of folders")

function _read_folder_answer(path::String)
    try
        _read_folder_listing(path)
    catch exception
        exception isa Base.IOError || rethrow()
        exception
    end
end

# A part that shows the entries of a folder asks for them: a read of its listing
# records a demand while the listing has no answer for its path and its count of
# changes. A folder made with its entries has no listing, and asks for nothing.
function demand_tree_children(folder::FileSystemDirectory)
    getfield(folder, :listing)[]
    nothing
end

"""
    read_filesystem_folder!(folder; depth = 1) -> folder

Read `folder` at once on the calling task, and its sub-folders down to `depth`
levels, for a script, an example or a test that shows a folder with no editor.
It never runs in a print. A folder that can not be read is `:failed`.

A folder made from the disk reads through its listing, which then holds what the
read found, so a part that shows its entries reads a final value and asks for no
read. A listing that holds an answer already reads again for a new count of
changes.
"""
function read_filesystem_folder!(folder::FileSystemDirectory; depth::Integer = 1)
    depth < 1 && return folder
    if folder.listing_source === nothing
        _apply_folder_listing!(nothing, folder, _read_folder_answer(folder.pathname))
    else
        listing = getfield(folder, :listing)
        is_cell_provisional(listing) || (folder.read_count += 1)
        wait_for_cell!(listing; editor = nothing)
    end
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
    _make_unread_folder(path; has_entries = listed.has_entries, source = folder.listing_source)
end

"""
    ApplyFolderListingOperation(folder, read_count, listing)

Write what a read of `folder` found, as the answer of its listing stores it:
`listing`, the entries in the order of their names, or the exception of the read.
A kept entry keeps its document, each run of new and gone entries is one splice
of `elements`, and a sub-folder that stays takes its new emptiness. The answer of
a read that a newer read follows is dropped: `read_count` names the read. A
watched folder watches each new sub-folder for its emptiness. It is a write of
view state, so undo records no read.
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
# sub-folders for their emptiness. It reads itself when a part asks for its
# entries. The release stops the watches and keeps the entries.
function acquire_document!(editor, folder::FileSystemDirectory)
    store = find_file_change_store(editor)
    if store !== nothing && watch_folder!(folder.pathname; store, receiver = folder)
        foreach(entry -> _watch_folder_entry!(store, folder, entry), folder.elements)
    end
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

# A change of the folder makes its listing out of date, so the part that shows its
# entries asks for them again; a change of one of its sub-folders checks whether
# that sub-folder holds an entry.
function receive_folder_change!(editor, folder::FileSystemDirectory, path)
    if path == _get_folder_key(folder.pathname)
        folder.read_count += 1
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
# with the failure in words. It reads no listing, so a row of it asks for nothing.
function get_document_decoration(folder::FileSystemDirectory)
    state = folder.state
    tooltip = () -> _make_folder_note(folder)
    folder.reading && return DocumentDecoration(; icon = :folder, conditions = [DocumentCondition(:running)], tooltip)
    state === :failed &&
        return DocumentDecoration(; icon = :folder, conditions = [DocumentCondition(:failed)],
                                  tooltip = () -> _make_folder_note(folder; text = sprint(showerror, folder.failure)))
    DocumentDecoration(; icon = :folder, tooltip)
end

# What a row of a folder says when the pointer rests on it: its path, and its
# entries once it is read, or that it is not.
function _make_folder_note(folder::FileSystemDirectory; text = nothing)
    path = String(folder.pathname)
    facts = Pair{String,Any}["Path" => replace(path, homedir() => "~")]
    folder.state === :read && push!(facts, "Entries" => string(length(folder.elements)))
    text === nothing && folder.state !== :read && (text = "Not read yet.")
    TooltipNote(; title = basename(rstrip(path, '/')), text, facts)
end

# A file says what its page says once it has one, and its kind before.
get_document_decoration(file::FileSystemFile) =
    file.document === nothing ?
        DocumentDecoration(; icon = get_file_icon(file.pathname), tooltip = () -> make_file_note(file.pathname)) :
        get_document_decoration(file.document)
