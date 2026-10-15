# Fragment of `FileChangeModule` — the store of the watched files: the file
# documents that watch their files, a watcher for each folder that holds one,
# and the paths that changed since the last drain. A watcher reads and parses a
# changed file on its own task and keeps the new document in the store; only a
# drain, on the editor task, reads the documents and swaps the new one in.

# One file document, the absolute path of its file, the file type that reads it,
# whether a person edits it, and what the last sync saw: the hash of the text of
# the file. For a file that a person does not edit, `file_hash` is the hash of the
# time and the size of the file at the last sync, and no text is read. `stamp` is
# the time and the size of the file at the last look of a poll, or at the start of
# the watch. The watcher alone writes `seen_hash`, the hash of the file at its
# last read, and `prepared` holds what it read since the last drain.
mutable struct WatchedFile
    file::FileDocument
    path::String
    type::Type
    is_editable::Bool
    file_hash::UInt64
    stamp::Any
    seen_hash::UInt64
    prepared::Any
end

# What a watcher read of a changed file: the hash of the file, and the new
# document, or the exception of its parse.
struct _PreparedFile
    file_hash::UInt64
    content::Any
    failure::Any
end

function WatchedFile(file::FileDocument, path::String)
    is_editable = is_editable_file_type(typeof(file))
    file_hash = is_editable ? _hash_file(path) : hash(_get_file_stamp(path))
    WatchedFile(file, path, Base.typename(typeof(file)).wrapper, is_editable, file_hash,
                _get_file_stamp(path), file_hash, nothing)
end

"""
    FileChangeStore(; poll_interval = 1.0)

The file documents that watch their files, and the paths that changed since the
last drain. A watcher task for each folder writes a change into it; a drain, on
the editor task, brings each change to its document
([`drain_file_changes!`](@ref)). A folder where the system gives no
notification is polled every `poll_interval` seconds.
"""
mutable struct FileChangeStore
    lock::ReentrantLock
    files::Vector{WatchedFile}
    changed::Set{String}
    watchers::Dict{String,Any}     # a folder, and its `FolderMonitor` or `:poll`
    wakes::Vector{Any}             # the wake functions of the editors that drain it
    poll_interval::Float64
end

FileChangeStore(; poll_interval::Real = 1.0) =
    FileChangeStore(ReentrantLock(), WatchedFile[], Set{String}(), Dict{String,Any}(), Any[],
                    Float64(poll_interval))

"""
    get_session_file_change_store(; editor = find_evaluation_editor()) -> FileChangeStore

The store of the file changes of `editor`: the store of its
[`FileChangeFeed`](@ref). Each editor that has the feed has its own store. With no
editor, or an editor that has no such feed, a new store that nothing keeps and
nothing drains.
"""
function get_session_file_change_store(; editor = find_evaluation_editor())
    store = _find_editor_file_change_store(editor)
    store === nothing ? FileChangeStore() : store
end

# The store of the `FileChangeFeed` of `editor`, or `nothing` when it has none.
function _find_editor_file_change_store(editor)
    editor isa Editor || return nothing
    index = findfirst(feed -> feed isa FileChangeFeed, editor.feeds)
    index === nothing ? nothing : editor.feeds[index].store
end

# The store that a watch takes by default: the store of the feed of the editor of
# the evaluation, or `nothing`, and then a watch does nothing, because no drain
# would bring its changes and its watcher would run forever.
_find_watch_store() = _find_editor_file_change_store(find_evaluation_editor())

"""
    watch_document_file!(file; store) -> file

Bring the changes of the file of `file` to it. When another program changes the
file, a drain of the store reads it again into `file`, as `ReloadFileOperation`
does, if the document was not edited since its last load or save; a document
with edits that are not saved keeps them, and the log says that its file
changed on disk. A save of the document is not a change. A file of a type that a
person does not edit (`is_editable_file_type`) is read again when the time or the
size of its file changes, and its text is never read to compare.

Call it on the task that reads the document. `store` is by default the store of
the [`FileChangeFeed`](@ref) of the editor of the evaluation; with no such
editor nothing is watched, because nothing would drain the changes. A file
document with no file name has nothing to watch. A document that watches already
is left as it is.

While Julia writes a precompile cache, nothing is watched. Such a process ends
after its workload, and Julia ends it only when every task of the workload has
ended, so the task of a watch would hold it forever.
"""
function watch_document_file!(file::FileDocument;
                              store::Union{FileChangeStore,Nothing} = _find_watch_store())
    (store === nothing || Base.generating_output()) && return file
    isempty(get_filename(file)) && return file
    path = abspath(get_filename(file))
    watched = WatchedFile(file, path)
    folder = dirname(path)
    lock(store.lock) do
        any(w -> w.file === file, store.files) && return
        push!(store.files, watched)
        haskey(store.watchers, folder) || _start_folder_watch!(store, folder)
    end
    file
end

"""
    unwatch_document_file!(file; store) -> file

Stop bringing the changes of its file to `file`. The watcher of its folder stops
when no watched file is left in the folder. `store` is by default the one that
[`watch_document_file!`](@ref) takes.
"""
function unwatch_document_file!(file::FileDocument;
                                store::Union{FileChangeStore,Nothing} = _find_watch_store())
    store === nothing && return file
    lock(store.lock) do
        index = findfirst(w -> w.file === file, store.files)
        index === nothing && return
        folder = dirname(store.files[index].path)
        deleteat!(store.files, index)
        any(w -> dirname(w.path) == folder, store.files) && return
        watcher = pop!(store.watchers, folder, nothing)
        watcher isa FolderMonitor && close(watcher)
    end
    file
end

"""Whether `file` watches its file in `store`, by default the one that [`watch_document_file!`](@ref) takes."""
is_document_file_watched(file::FileDocument; store::Union{FileChangeStore,Nothing} = _find_watch_store()) =
    store !== nothing && lock(() -> any(w -> w.file === file, store.files), store.lock)

# A file that enters the window watches its file in the store of the editor while
# a tab shows it, and the release of the tab stops the watch. An editor with no
# file change feed watches nothing.
acquire_document!(editor, file::FileDocument) =
    (watch_document_file!(file; store = _find_editor_file_change_store(editor)); nothing)

release_document!(editor, file::FileDocument) =
    (unwatch_document_file!(file; store = _find_editor_file_change_store(editor)); nothing)

"""
    close_file_change_store!(store) -> store

Stop every watcher of `store` and forget its files, as when the editor that
drains it ends. A poll of a folder stops at its next look.
"""
function close_file_change_store!(store::FileChangeStore)
    lock(store.lock) do
        for watcher in values(store.watchers)
            watcher isa FolderMonitor && close(watcher)
        end
        empty!(store.watchers)
        empty!(store.files)
        empty!(store.changed)
        empty!(store.wakes)
    end
    store
end

# ── The watchers ─────────────────────────────────────────────────────────────

# Start the watcher of `folder`, with the lock held: a monitor of the system, or
# a poll of the times of the files where the system gives no notification.
function _start_folder_watch!(store::FileChangeStore, folder::String)
    monitor = try
        FolderMonitor(folder)
    catch error
        error isa Base.IOError || rethrow()
        nothing
    end
    if monitor === nothing
        store.watchers[folder] = :poll
        errormonitor(Threads.@spawn _poll_folder(store, folder))
    else
        store.watchers[folder] = monitor
        errormonitor(Threads.@spawn _wait_folder(store, folder, monitor))
    end
    nothing
end

# Wait for each event of the folder until its monitor closes. An event marks
# every watched file of the folder, because a program that writes a file at
# once renames another file over it, and the event then names the other file.
function _wait_folder(store::FileChangeStore, folder::String, monitor::FolderMonitor)
    while true
        try
            wait(monitor)
        catch error
            error isa EOFError && return
            rethrow()
        end
        _prepare_folder_changes!(store, folder)
    end
end

# Poll the times and the sizes of the watched files of the folder while the
# folder is polled. A file is compared with what the last look saw, or with what
# the start of its watch saw, so a change before the first look counts too.
function _poll_folder(store::FileChangeStore, folder::String)
    while lock(() -> get(store.watchers, folder, nothing) === :poll, store.lock)
        _update_folder_stamps!(store, folder) && _prepare_folder_changes!(store, folder)
        sleep(store.poll_interval)
    end
end

# Take the stamp of each watched file of the folder, and answer whether one of
# them differs from the stamp before.
function _update_folder_stamps!(store::FileChangeStore, folder::String)
    lock(store.lock) do
        changed = false
        for watched in store.files
            dirname(watched.path) == folder || continue
            stamp = _get_file_stamp(watched.path)
            changed |= stamp != watched.stamp
            watched.stamp = stamp
        end
        changed
    end
end

# The time and the size of the file, or `nothing` when there is no file.
_get_file_stamp(path::String) = isfile(path) ? (mtime(path), filesize(path)) : nothing

# How long the time and the size of a file stay the same before a watcher reads
# it, and the longest wait for that, in seconds.
const FILE_SETTLE_SECONDS = 0.05
const FILE_SETTLE_LIMIT_SECONDS = 2.0

# Wait until the time and the size of the file at `path` stay the same for
# `FILE_SETTLE_SECONDS`, at most `FILE_SETTLE_LIMIT_SECONDS`.
function _wait_for_settled_file(path::String)
    deadline = time() + FILE_SETTLE_LIMIT_SECONDS
    stamp = _get_file_stamp(path)
    while time() < deadline
        sleep(FILE_SETTLE_SECONDS)
        next = _get_file_stamp(path)
        next == stamp && return nothing
        stamp = next
    end
    nothing
end

# Read each watched file of the folder that changed since the watcher read it
# last, parse it into a new document, keep that for the next drain, and wake each
# editor that drains the store. It runs on the task of the watcher of the folder,
# one change after the other, so a file that changes again during a parse is read
# again in its newest version, and that read replaces the one before.
function _prepare_folder_changes!(store::FileChangeStore, folder::String)
    watched_files = lock(() -> WatchedFile[w for w in store.files if dirname(w.path) == folder], store.lock)
    is_prepared = false
    for watched in watched_files
        prepared = _prepare_file_change(watched)
        prepared === nothing && continue
        lock(store.lock) do
            any(w -> w === watched, store.files) || return
            watched.prepared = prepared
            push!(store.changed, watched.path)
            is_prepared = true
        end
    end
    is_prepared || return nothing
    foreach(wake -> wake(), lock(() -> copy(store.wakes), store.lock))
    nothing
end

# What the watcher reads of a changed file, or `nothing` when the file is gone or
# did not change since its last read. A file that a person does not edit is read
# when its time or its size changed, and its text is never hashed. The watcher
# reads a file once it is whole: a program writes a file in more than one step,
# and each step is an event.
function _prepare_file_change(watched::WatchedFile)
    _wait_for_settled_file(watched.path)
    isfile(watched.path) || return nothing
    file_hash = watched.is_editable ? hash(read(watched.path, String)) : hash(_get_file_stamp(watched.path))
    file_hash == watched.seen_hash && return nothing
    watched.seen_hash = file_hash
    try
        _PreparedFile(file_hash, read_file_content_again(watched.type, watched.path), nothing)
    catch exception
        _PreparedFile(file_hash, nothing, CapturedException(exception, catch_backtrace()))
    end
end

# ── The drain ────────────────────────────────────────────────────────────────

"""
    drain_file_changes!(; editor = nothing, store = get_session_file_change_store(; editor)) -> Int

Bring each change that the watchers read and parsed to its document, and answer
how many documents took their file again. Run it on the task that reads the
documents. The drain reads no file: a watcher read it, off the loop.

A file that a person does not edit takes the new document. For a file that a
person edits, the history of its content tells: a file whose hash is the hash of
the text that the last save wrote holds that save, and nothing happens; a
document with no edits since its last load or save takes the new document; a
document with edits that are not saved keeps them, and the log says that its
file changed on disk. A content that keeps no history can not tell its edits, so
it keeps what it holds, and the log says so. A parse that failed is thrown after
the other changes, so the editor records it.
"""
function drain_file_changes!(; editor = nothing, store::FileChangeStore = get_session_file_change_store(; editor))
    changed = lock(store.lock) do
        isempty(store.changed) && return Tuple{WatchedFile,_PreparedFile}[]
        paths = copy(store.changed)
        empty!(store.changed)
        changed = Tuple{WatchedFile,_PreparedFile}[]
        for watched in store.files
            watched.path in paths && watched.prepared !== nothing || continue
            push!(changed, (watched, watched.prepared))
            watched.prepared = nothing
        end
        changed
    end
    taken = count(((watched, prepared),) -> _bring_file_change!(watched, prepared, editor), changed)
    for (_, prepared) in changed
        prepared.failure === nothing || throw(prepared.failure)
    end
    taken
end

function _bring_file_change!(watched::WatchedFile, prepared::_PreparedFile, editor)
    prepared.file_hash == watched.file_hash && return false
    watched.file_hash = prepared.file_hash
    prepared.failure === nothing || return false
    watched.is_editable || return _take_prepared_file!(watched, prepared, editor)
    content = get_file_content(watched.file)
    # The file holds what the last save of the document wrote.
    get_saved_text_hash(content) == prepared.file_hash && return false
    edits = has_unsaved_edits(content)
    edits === false && return _take_prepared_file!(watched, prepared, editor)
    @warn string(basename(watched.path), " changed on disk, and its tab keeps ",
                 edits === true ? "the edits that are not saved. Ctrl+O reads the file again; Ctrl+S writes the tab over it." :
                         "what it shows, because it keeps no history that says whether it has edits. " *
                         "Ctrl+O reads the file again.")
    false
end

# Swap the document that the watcher read into the file document.
function _take_prepared_file!(watched::WatchedFile, prepared::_PreparedFile, editor)
    evaluate_operation(editor, ReloadFileOperation(watched.file; content = prepared.content))
    true
end

_hash_file(path::String) = isfile(path) ? hash(read(path, String)) : hash(nothing)
