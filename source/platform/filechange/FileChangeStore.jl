# Fragment of `FileChangeModule` — the store of the watched files and folders: the
# file documents that watch their files, the receivers that watch a folder, a
# watcher for each folder that holds one of them, and what changed since the last
# drain. A watcher reads and parses a changed file on its own task and keeps the
# new document in the store; of a watched folder it notes only that the folder
# changed. Only a drain, on the editor task, reports a change to its receiver.

# One file document, the absolute path of its file, the file type that reads it,
# whether its text is read, the receiver that a change is reported to, and what
# the last report saw: the hash of the text of the file. The text of a file that
# a person does not edit is not read: its `file_hash` is the hash of the time and
# the size of the file. `stamp` is the time and the size of the file at the last
# look of a poll, or at the start of the watch. The watcher alone writes
# `seen_hash`, the hash of the file at its last read, and `prepared` holds what
# it read since the last drain.
mutable struct WatchedFile
    file::FileDocument
    path::String
    type::Type
    is_editable::Bool
    receiver::Any
    file_hash::UInt64
    stamp::Any
    seen_hash::UInt64
    prepared::Any
end

# A receiver that watches a folder, the absolute path of the folder, and the time
# of the folder at the last look of a poll, or at the start of the watch.
mutable struct WatchedFolder
    path::String
    receiver::Any
    stamp::Any
end

# What a watcher read of a changed file: the hash of the file, and the new
# document, or the exception of its parse.
struct _PreparedFile
    file_hash::UInt64
    content::Any
    failure::Any
end

function WatchedFile(file::FileDocument, path::String, receiver)
    is_editable = is_editable_file_type(typeof(file))
    file_hash = is_editable ? compute_file_text_hash(path) : hash(_get_file_stamp(path))
    WatchedFile(file, path, Base.typename(typeof(file)).wrapper, is_editable, receiver, file_hash,
                _get_file_stamp(path), file_hash, nothing)
end

"""
    FOLDER_WATCH_LIMIT

How many folders a store watches at most for receivers of folders
([`watch_folder!`](@ref)): the system limits the watches of each person, and the
editor shares them with every other program. A file that a tab shows is watched
past the limit.
"""
const FOLDER_WATCH_LIMIT = 1000

"""
    FileChangeStore(; poll_interval = 1.0, watch_limit = FOLDER_WATCH_LIMIT)

The file documents that watch their files, the receivers that watch a folder,
and what changed since the last drain. A watcher task for each folder writes a
change into it; a drain, on the editor task, reports each change to its receiver
([`drain_file_changes!`](@ref)). A folder where the system gives no
notification is polled every `poll_interval` seconds. A watch of a folder for a
receiver starts no new watcher once the store has `watch_limit` of them.
"""
mutable struct FileChangeStore
    lock::ReentrantLock
    files::Vector{WatchedFile}
    changed::Set{String}
    folders::Vector{WatchedFolder}
    changed_folders::Set{String}
    watchers::Dict{String,Any}     # a folder, and its `FolderMonitor` or `:poll`
    wakes::Vector{Any}             # the wake functions of the editors that drain it
    poll_interval::Float64
    watch_limit::Int
end

FileChangeStore(; poll_interval::Real = 1.0, watch_limit::Integer = FOLDER_WATCH_LIMIT) =
    FileChangeStore(ReentrantLock(), WatchedFile[], Set{String}(), WatchedFolder[], Set{String}(),
                    Dict{String,Any}(), Any[], Float64(poll_interval), Int(watch_limit))

"""
    get_session_file_change_store(; editor = find_evaluation_editor()) -> FileChangeStore

The store of the file changes of `editor`: the store of its
[`FileChangeFeed`](@ref). Each editor that has the feed has its own store. With no
editor, or an editor that has no such feed, a new store that nothing keeps and
nothing drains.
"""
function get_session_file_change_store(; editor = find_evaluation_editor())
    store = find_file_change_store(editor)
    store === nothing ? FileChangeStore() : store
end

"""
    find_file_change_store(editor) -> FileChangeStore or nothing

The store of the [`FileChangeFeed`](@ref) of `editor`, or `nothing` when it has
none, so a caller watches only in a store that a drain empties.
"""
function find_file_change_store(editor)
    editor isa Editor || return nothing
    index = findfirst(feed -> feed isa FileChangeFeed, editor.feeds)
    index === nothing ? nothing : editor.feeds[index].store
end

# The store that a watch takes by default: the store of the feed of the editor of
# the evaluation, or `nothing`, and then a watch does nothing, because no drain
# would bring its changes and its watcher would run forever.
_find_watch_store() = find_file_change_store(find_evaluation_editor())

"""
    watch_document_file!(file; store, receiver = file) -> file

Report each change of the file of `file` to `receiver`: when the file changed on
disk, a drain of the store calls `receive_file_change!` with the hash of the file
and the document that a watcher parsed, and the receiver decides what the change
means. A [`FilePage`](@ref) that shows the file is the receiver of a file in a
tab. A file of a type that a person does not edit (`is_editable_file_type`) is
read again when the time or the size of its file changes, and its text is never
read.

Call it on the task that reads the document. `store` is by default the store of
the [`FileChangeFeed`](@ref) of the editor of the evaluation; with no such
editor nothing is watched, because nothing would drain the changes. A file
document with no file name has nothing to watch. A document that watches already
is left as it is, with its receiver.

While Julia writes a precompile cache, nothing is watched. Such a process ends
after its workload, and Julia ends it only when every task of the workload has
ended, so the task of a watch would hold it forever.
"""
function watch_document_file!(file::FileDocument;
                              store::Union{FileChangeStore,Nothing} = _find_watch_store(),
                              receiver = file)
    (store === nothing || Base.generating_output()) && return file
    isempty(get_filename(file)) && return file
    path = abspath(get_filename(file))
    watched = WatchedFile(file, path, receiver)
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
        _stop_unused_folder_watch!(store, folder)
    end
    file
end

# Stop the watcher of `folder`, with the lock held, when no watched file is in
# the folder and no receiver watches it.
function _stop_unused_folder_watch!(store::FileChangeStore, folder::String)
    any(w -> dirname(w.path) == folder, store.files) && return nothing
    any(w -> w.path == folder, store.folders) && return nothing
    watcher = pop!(store.watchers, folder, nothing)
    watcher isa FolderMonitor && close(watcher)
    nothing
end

"""Whether `file` watches its file in `store`, by default the one that [`watch_document_file!`](@ref) takes."""
is_document_file_watched(file::FileDocument; store::Union{FileChangeStore,Nothing} = _find_watch_store()) =
    store !== nothing && lock(() -> any(w -> w.file === file, store.files), store.lock)

# ── The watches of folders ───────────────────────────────────────────────────

"""
    receive_folder_change!(editor, receiver, folder) -> Bool

Tell `receiver` that an entry of `folder` came, went or changed: a drain of the
store calls it on the editor task for each receiver that watches the folder
([`watch_folder!`](@ref)). The watcher read nothing of the folder, so the
receiver reads it, off the loop, such as with `start_document_read!`. It answers
whether the receiver took the change. The default takes none.
"""
receive_folder_change!(editor, receiver, folder) = false

# The absolute path of a folder, with no separator at its end.
function _normalize_folder_path(path::AbstractString)
    folder = normpath(abspath(path))
    length(folder) > 1 && endswith(folder, '/') ? folder[1:(end - 1)] : folder
end

"""
    watch_folder!(path; store, receiver) -> Bool

Report each change of the entries of the folder at `path` to `receiver`: a drain
of the store calls [`receive_folder_change!`](@ref). The watcher of the folder
notes only that the folder changed, and reads nothing of it. A folder that a file
or another receiver watches shares its watcher. A new watcher starts only while
the store has fewer than its `watch_limit`, so the answer is whether the folder
is watched: `false` past the limit, for a folder that does not exist, and with no
store. A receiver that watches the folder already is left as it is.

Call it on the task that reads the documents, such as from an acquire. `store` is
by default the store of the [`FileChangeFeed`](@ref) of the editor of the
evaluation; with no such editor nothing is watched. While Julia writes a
precompile cache, nothing is watched.
"""
function watch_folder!(path::AbstractString; store::Union{FileChangeStore,Nothing} = _find_watch_store(),
                       receiver)
    (store === nothing || Base.generating_output()) && return false
    folder = _normalize_folder_path(path)
    lock(store.lock) do
        any(w -> w.path == folder && w.receiver === receiver, store.folders) && return true
        isdir(folder) || return false
        if !haskey(store.watchers, folder)
            length(store.watchers) >= store.watch_limit && return false
            _start_folder_watch!(store, folder)
        end
        push!(store.folders, WatchedFolder(folder, receiver, _get_folder_stamp(folder)))
        true
    end
end

"""
    unwatch_folder!(path; store, receiver) -> nothing

Stop reporting the changes of the folder at `path` to `receiver`. The watcher of
the folder stops when nothing else watches the folder. `store` is by default the
one that [`watch_folder!`](@ref) takes.
"""
function unwatch_folder!(path::AbstractString; store::Union{FileChangeStore,Nothing} = _find_watch_store(),
                         receiver)
    store === nothing && return nothing
    folder = _normalize_folder_path(path)
    lock(store.lock) do
        index = findfirst(w -> w.path == folder && w.receiver === receiver, store.folders)
        index === nothing && return
        deleteat!(store.folders, index)
        _stop_unused_folder_watch!(store, folder)
    end
    nothing
end

"""
    is_folder_watched(path; store, receiver = nothing) -> Bool

Whether a receiver watches the folder at `path` in `store`: `receiver`, or any
receiver when it is `nothing`. `store` is by default the one that
[`watch_folder!`](@ref) takes.
"""
function is_folder_watched(path::AbstractString; store::Union{FileChangeStore,Nothing} = _find_watch_store(),
                           receiver = nothing)
    store === nothing && return false
    folder = _normalize_folder_path(path)
    lock(() -> any(w -> w.path == folder && (receiver === nothing || w.receiver === receiver), store.folders),
         store.lock)
end

# A file that enters the window watches its file in the store of the editor while
# a tab shows it, and the release of the tab stops the watch. An editor with no
# file change feed watches nothing. A tab acquires its outer layer first, so the
# page of a file watches the file as its receiver, and the file itself, which comes
# next, watches already. The open files of the editor list the page, or the file
# that no page holds, while it is held.
function acquire_document!(editor, file::FileDocument)
    watch_document_file!(file; store = find_file_change_store(editor))
    add_open_file!(editor, file)
    nothing
end

function release_document!(editor, file::FileDocument)
    unwatch_document_file!(file; store = find_file_change_store(editor))
    remove_open_file!(editor, file)
    nothing
end

# A page holds the file that it shows, so the file is acquired wherever the page
# is: in a tab, which acquires every layer of its content, and in the navigator of
# an explorer, which holds only the page.
function acquire_document!(editor, page::FilePage)
    file = find_page_file(page)
    file === nothing ||
        watch_document_file!(file; store = find_file_change_store(editor), receiver = page)
    add_open_file!(editor, page)
    file === nothing || hold_documents!(editor, page, Any[file])
    nothing
end

function release_document!(editor, page::FilePage)
    file = find_page_file(page)
    file === nothing || unwatch_document_file!(file; store = find_file_change_store(editor))
    remove_open_file!(editor, page)
    file === nothing || release_held_documents!(editor, page, Any[file])
    nothing
end

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
        empty!(store.folders)
        empty!(store.changed_folders)
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
        _mark_watched_folder!(store, folder)
    end
end

# Poll the times and the sizes of the watched files of the folder while the
# folder is polled. A file is compared with what the last look saw, or with what
# the start of its watch saw, so a change before the first look counts too.
function _poll_folder(store::FileChangeStore, folder::String)
    while lock(() -> get(store.watchers, folder, nothing) === :poll, store.lock)
        _update_folder_stamps!(store, folder) && _prepare_folder_changes!(store, folder)
        _update_watched_folder_stamps!(store, folder) && _mark_watched_folder!(store, folder)
        sleep(store.poll_interval)
    end
end

# Take the time of the folder for each receiver that watches it, and answer
# whether it differs from the time before: an entry that comes or goes changes it.
function _update_watched_folder_stamps!(store::FileChangeStore, folder::String)
    lock(store.lock) do
        changed = false
        for watched in store.folders
            watched.path == folder || continue
            stamp = _get_folder_stamp(folder)
            changed |= stamp != watched.stamp
            watched.stamp = stamp
        end
        changed
    end
end

# The time of the folder, or `nothing` when there is no folder.
_get_folder_stamp(folder::String) = isdir(folder) ? mtime(folder) : nothing

# Note that `folder` changed for its receivers, and wake each editor that drains
# the store. The watcher reads nothing of the folder: the receiver reads it.
function _mark_watched_folder!(store::FileChangeStore, folder::String)
    is_marked = lock(store.lock) do
        any(w -> w.path == folder, store.folders) || return false
        push!(store.changed_folders, folder)
        true
    end
    is_marked && foreach(wake -> wake(), lock(() -> copy(store.wakes), store.lock))
    nothing
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
    file_hash = watched.is_editable ? compute_file_text_hash(watched.path) : hash(_get_file_stamp(watched.path))
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

Report each change that the watchers read and parsed to the receiver of its file
(`receive_file_change!`), and each folder that changed to each receiver that
watches it ([`receive_folder_change!`](@ref)), and answer how many receivers took
their change.
Run it on the task that reads the documents. The drain reads no file: a watcher
read it, off the loop. What a change means is the choice of the receiver: a
[`FilePage`](@ref) knows its own save and the edits of its file, and the drain
knows neither. A change is reported once. A parse that failed is thrown after the
other changes, so the editor records it.
"""
function drain_file_changes!(; editor = nothing, store::FileChangeStore = get_session_file_change_store(; editor))
    folders = lock(store.lock) do
        isempty(store.changed_folders) && return WatchedFolder[]
        paths = copy(store.changed_folders)
        empty!(store.changed_folders)
        WatchedFolder[watched for watched in store.folders if watched.path in paths]
    end
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
    taken += count(watched -> receive_folder_change!(editor, watched.receiver, watched.path) === true, folders)
    for (_, prepared) in changed
        prepared.failure === nothing || throw(prepared.failure)
    end
    taken
end

function _bring_file_change!(watched::WatchedFile, prepared::_PreparedFile, editor)
    prepared.file_hash == watched.file_hash && return false
    watched.file_hash = prepared.file_hash
    prepared.failure === nothing || return false
    receive_file_change!(editor, watched.receiver, prepared.file_hash, prepared.content)
end
