# Fragment of `FileWatchingModule` — the watch of a folder by a `FolderMonitor`.

"""
    start_folder_monitor!(folder, record) -> FolderMonitor or nothing

Watch `folder` with a `FolderMonitor`, and call `record()` on a task of its own
at each event, until the monitor closes. Answers `nothing` when the system gives
no notification for the folder, so the store polls it.

This is the watch that the package registers with `register_folder_watch!`.
"""
function start_folder_monitor!(folder::AbstractString, record)
    monitor = try
        FolderMonitor(folder)
    catch error
        error isa Base.IOError || rethrow()
        return nothing
    end
    errormonitor(Threads.@spawn _wait_folder_events(monitor, record))
    monitor
end

# Wait for each event of the folder until its monitor closes. An event names one
# file, and `record` marks every watched file of the folder, because a program
# that writes a file at once renames another file over it, and the event then
# names the other file.
function _wait_folder_events(monitor::FolderMonitor, record)
    while true
        try
            wait(monitor)
        catch error
            error isa EOFError && return
            rethrow()
        end
        record()
    end
end
