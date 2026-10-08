"""
    FileWatchingModule

The watch of a folder by the notifications of the system, for the store of the
watched files of the platform (`FileChangeModule`). The notifications come from
the standard library `FileWatching`, and the platform depends on no such
package, so this adapter brings them. When it loads, it registers
[`start_folder_monitor!`](@ref) with `register_folder_watch!`: the store then
watches each folder with a `FolderMonitor`, and polls a folder only where the
system gives no notification.
"""
module FileWatchingModule

using FileWatching: FolderMonitor

using ..FileChangeModule

export start_folder_monitor!

include("FolderMonitor.jl")

# The store takes this watch from the load of the package on.
__init__() = register_folder_watch!(start_folder_monitor!)

end # module
