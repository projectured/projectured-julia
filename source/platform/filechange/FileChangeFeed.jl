# Fragment of `FileChangeModule` — the feed that connects the store to the
# documents. A watcher wakes the editor when a file changes, and the editor
# drains the store on its own task, so no watcher task writes a cell.

"""
    FileChangeFeed(; store = FileChangeStore())

The feed of a window whose file documents watch their files: give it to the
editor in its `feeds`. It owns its store, so each editor watches its own files
([`get_session_file_change_store`](@ref)). A watcher of the store wakes the
editor when a file changes, and the drain reports each change to the receiver of its file
([`drain_file_changes!`](@ref)). An idle feed asks for no frame.
"""
struct FileChangeFeed <: Feed
    store::FileChangeStore
end

FileChangeFeed(; store::FileChangeStore = FileChangeStore()) = FileChangeFeed(store)

drain_changes!(feed::FileChangeFeed, editor) = drain_file_changes!(; store = feed.store, editor)

function attach_wake_callback!(feed::FileChangeFeed, wake)
    lock(() -> push!(feed.store.wakes, wake), feed.store.lock)
    nothing
end

"""
    file_change = true

The wrapper of `build_editor` that watches the files that the tabs of the window
show: it adds a [`FileChangeFeed`](@ref), so a file document that enters the
window watches its file in the store of the feed, and its stop step stops every
watcher of that store when the loop ends. It is off by default.
"""
function wrap_editor!(::Val{:file_change}, layer::Symbol, argument, parts::EditorParts)
    feed = FileChangeFeed()
    push!(parts.feeds, feed)
    push!(parts.stop_steps, _ -> (close_file_change_store!(feed.store); nothing))
    parts
end

get_wrapper_layers(::Val{:file_change}) = (:screen => 10,)

"""
    make_file_change_feeds() -> Vector{Feed}

The `feeds` of a window whose file documents watch their files: one
[`FileChangeFeed`](@ref), with a store of its own. No stop step comes with it, so
the caller stops the watchers of the store with `close_file_change_store!` when
its loop ends. The wrapper `file_change = true` of `build_editor` adds the feed
and that stop step both.
"""
make_file_change_feeds() = Feed[FileChangeFeed()]
