# Fragment of `FileChangeModule` — the feed that connects the store to the
# documents. A watcher wakes the editor when a file changes, and the editor
# drains the store on its own task, so no watcher task writes a cell.

"""
    FileChangeFeed(; store = get_session_file_change_store())

The feed of a window whose file documents watch their files: give it to the
editor in its `feeds`. A watcher of the store wakes the editor when a file
changes, and the drain brings each change to its document
([`drain_file_changes!`](@ref)). An idle feed asks for no frame.
"""
struct FileChangeFeed <: Feed
    store::FileChangeStore
end

FileChangeFeed(; store::FileChangeStore = get_session_file_change_store()) = FileChangeFeed(store)

drain_changes!(feed::FileChangeFeed, editor) = drain_file_changes!(; store = feed.store, editor)

function attach_wake_callback!(feed::FileChangeFeed, wake)
    lock(() -> push!(feed.store.wakes, wake), feed.store.lock)
    nothing
end

"""
    make_file_change_feeds() -> Vector{Feed}

The `feeds` of a window whose file documents watch their files: one
[`FileChangeFeed`](@ref) over the store of the session.
`build_editor(…; feeds = make_file_change_feeds())`.
"""
make_file_change_feeds() = Feed[FileChangeFeed()]
