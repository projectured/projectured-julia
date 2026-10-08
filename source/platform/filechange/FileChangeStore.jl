# Fragment of `FileChangeModule` — the store of the watched files: the file
# documents that watch their files, a watcher for each folder that holds one,
# and the paths that changed since the last drain. A watcher writes the store
# from its own task; only a drain, on the editor task, reads the documents.

# One file document, the absolute path of its file, and what the last sync saw:
# the hash of the text of the file, and the hash of the text that the document
# writes. `stamp` is the time and the size of the file at the last look of a
# poll, or at the start of the watch.
mutable struct WatchedFile
    file::FileDocument
    path::String
    file_hash::UInt64
    text_hash::UInt64
    stamp::Any
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

"""The store of the session: every file document that watches its file is here."""
const SESSION_FILE_CHANGE_STORE = FileChangeStore()

"""The store of the session, [`SESSION_FILE_CHANGE_STORE`](@ref)."""
get_session_file_change_store() = SESSION_FILE_CHANGE_STORE

"""
    watch_document_file!(file; store = get_session_file_change_store()) -> file

Bring the changes of the file of `file` to it. When another program changes the
file, a drain of the store reads it again into `file`, as `ReloadFileOperation`
does, if the document was not edited since its last load or save; a document
with edits that are not saved keeps them, and the log says that its file
changed on disk. A save of the document is not a change.

Call it on the task that reads the document. A file document with no file name
has nothing to watch. A document that watches already is left as it is.
"""
function watch_document_file!(file::FileDocument; store::FileChangeStore = get_session_file_change_store())
    isempty(get_filename(file)) && return file
    path = abspath(get_filename(file))
    watched = WatchedFile(file, path, _hash_file(path), _hash_document_text(file),
                          _get_file_stamp(path))
    folder = dirname(path)
    lock(store.lock) do
        any(w -> w.file === file, store.files) && return
        push!(store.files, watched)
        haskey(store.watchers, folder) || _start_folder_watch!(store, folder)
    end
    file
end

"""
    unwatch_document_file!(file; store = get_session_file_change_store()) -> file

Stop bringing the changes of its file to `file`. The watcher of its folder stops
when no watched file is left in the folder.
"""
function unwatch_document_file!(file::FileDocument; store::FileChangeStore = get_session_file_change_store())
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

"""Whether `file` watches its file in `store`."""
is_document_file_watched(file::FileDocument; store::FileChangeStore = get_session_file_change_store()) =
    lock(() -> any(w -> w.file === file, store.files), store.lock)

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
        _record_folder_change!(store, folder)
    end
end

# Poll the times and the sizes of the watched files of the folder while the
# folder is polled. A file is compared with what the last look saw, or with what
# the start of its watch saw, so a change before the first look counts too.
function _poll_folder(store::FileChangeStore, folder::String)
    while lock(() -> get(store.watchers, folder, nothing) === :poll, store.lock)
        _update_folder_stamps!(store, folder) && _record_folder_change!(store, folder)
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

# Mark every watched file of the folder as changed, and wake each editor that
# drains the store.
function _record_folder_change!(store::FileChangeStore, folder::String)
    wakes = lock(store.lock) do
        for watched in store.files
            dirname(watched.path) == folder && push!(store.changed, watched.path)
        end
        copy(store.wakes)
    end
    foreach(wake -> wake(), wakes)
    nothing
end

# ── The drain ────────────────────────────────────────────────────────────────

"""
    drain_file_changes!(; store = get_session_file_change_store(), editor = nothing) -> Int

Bring each change that the watchers stored to its document, and answer how many
documents read their file again. Run it on the task that reads the documents.

For each watched file whose text changed: a file that holds what its document
writes was written by a save, and nothing happens; a document that was not
edited since its last load or save reads its file again; a document with edits
that are not saved keeps them, and the log says that its file changed on disk.
"""
function drain_file_changes!(; store::FileChangeStore = get_session_file_change_store(), editor = nothing)
    changed = lock(store.lock) do
        isempty(store.changed) && return WatchedFile[]
        paths = copy(store.changed)
        empty!(store.changed)
        WatchedFile[w for w in store.files if w.path in paths]
    end
    count(watched -> _bring_file_change!(watched, editor), changed)
end

function _bring_file_change!(watched::WatchedFile, editor)
    isfile(watched.path) || return false
    on_disk = read(watched.path, String)
    hash(on_disk) == watched.file_hash && return false
    watched.file_hash = hash(on_disk)
    text = _find_document_text(watched.file)
    if text == on_disk
        # The file holds what the document writes: a save wrote it.
        watched.text_hash = hash(text)
        return false
    end
    if text !== nothing && hash(text) == watched.text_hash
        evaluate_operation(editor, ReloadFileOperation(watched.file))
        watched.text_hash = _hash_document_text(watched.file)
        return true
    end
    @warn string(basename(watched.path), " changed on disk, and its tab keeps the edits that ",
                 "are not saved. Ctrl+O reads the file again; Ctrl+S writes the tab over it.")
    false
end

_hash_file(path::String) = isfile(path) ? hash(read(path, String)) : hash(nothing)

_hash_document_text(file::FileDocument) = hash(_find_document_text(file))

# The text that a save of the document writes, or `nothing` when the save would
# refuse.
function _find_document_text(file::FileDocument)
    try
        compute_file_text(file)
    catch error
        error isa FileCutException || rethrow()
        nothing
    end
end
