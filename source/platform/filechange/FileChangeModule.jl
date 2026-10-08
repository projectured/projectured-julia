"""
    FileChangeModule

The changes of files, brought to the documents that the files hold.

A file document that watches its file ([`watch_document_file!`](@ref)) learns
of a change that another program makes: a tool in a terminal, a checkout of
git, a task that writes a store. A watcher task for each folder polls the
times and the sizes of the files, or takes the notifications of the system
through the watch that an adapter registers ([`register_folder_watch!`](@ref)),
and stores the paths that changed. The editor drains the
store on its own task ([`FileChangeFeed`](@ref)): a document that was not edited
since its last load or save reads its file again, and a document with edits
that are not saved keeps them, and the log says that its file changed on disk.
"""
module FileChangeModule

using ..OperationModule
using ..SerializationModule
using ..FileFormatModule
using ..FeedModule

# Imported to extend: the feed of this module answers each of them.
import ..FeedModule: drain_changes!, attach_wake_callback!

export FileChangeStore, get_session_file_change_store, watch_document_file!,
       unwatch_document_file!, is_document_file_watched, drain_file_changes!,
       register_folder_watch!
export FileChangeFeed, make_file_change_feeds

include("FileChangeStore.jl")
include("FileChangeFeed.jl")

end # module
