"""
    FileChangeModule

The changes of files, brought to the documents that the files hold.

A file document that watches its file ([`watch_document_file!`](@ref)) learns
of a change that another program makes: a tool in a terminal, a checkout of
git, a task that writes a store. A receiver that watches a folder
([`watch_folder!`](@ref)) learns that an entry of the folder came, went or
changed, and reads the folder itself. A watcher task for each folder takes the
notifications of the system, or polls the times of the files where no
notification works, and stores the paths that changed. The editor drains the
store on its own task ([`FileChangeFeed`](@ref)), and the drain reports each
change to the receiver of its file, which decides what the change means. The
watcher knows nothing of editing: the page of a file in a tab knows its own save
and the edits of its file.
"""
module FileChangeModule

using FileWatching: FolderMonitor

using ..EditorModule
using ..OperationModule
using ..SerializationModule
using ..ToolModule
using ..FileFormatModule
using ..FeedModule

# Imported to extend: the feed of this module answers each of them, and a file
# that enters or leaves the window starts or stops its watch.
import ..FeedModule: drain_changes!, attach_wake_callback!
import ..DomainModule: acquire_document!, release_document!
import ..EditorModule: wrap_editor!, get_wrapper_layers

export FOLDER_WATCH_LIMIT, FileChangeStore, get_session_file_change_store, find_file_change_store,
       watch_document_file!, unwatch_document_file!, is_document_file_watched,
       receive_folder_change!, watch_folder!, unwatch_folder!, is_folder_watched,
       close_file_change_store!, drain_file_changes!
export FileChangeFeed, make_file_change_feeds

include("FileChangeStore.jl")
include("FileChangeFeed.jl")

end # module
