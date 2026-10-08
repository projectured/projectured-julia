# The notifications of the system for a change of a file

> **Kind:** design · **Status:** current · **Stands on:** [filechange.md](../../platform/filechange/filechange.md)

`ProjecturedFileWatching` gives the store of the watched files of the platform the notifications of the system. Without it, the store polls each folder that holds a watched file. With it, a change of a file reaches the store at once, and no task looks at the files each second. This document says what the package registers, and why it is a package of its own.

## How it is used

A program loads the package, and nothing more:

```julia
using ProjecturedFileWatching
watch_document_file!(tab)        # the folder of the file is watched by a FolderMonitor
```

The package declares the trigger `Projectured` with the default `auto`, so `using Projectured` loads it when it is installed ([autointegration.md](../../autointegration/autointegration.md)). A program that does not load `Projectured` names the package itself.

## How it works

The code is the slice `FileWatchingModule`, in `source/adapter/filewatching/`: `FileWatchingModule.jl` holds its imports, its export and the registration, and `FolderMonitor.jl` holds `start_folder_monitor!`. `ProjecturedFileWatching` includes the slice and exports the same name.

When the package loads, it calls `register_folder_watch!(start_folder_monitor!)` of the file-change slice. From then on, the store starts the watch of each new folder with `start_folder_monitor!(folder, record)`:

- It starts a `FolderMonitor` of the standard library `FileWatching`, which takes the notifications of the system (inotify on Linux).
- A task of its own waits for each event of the folder and calls `record()`. The store then marks every watched file of the folder as changed, and wakes each editor that drains it.
- It answers the monitor, and the store closes the monitor when the last watched file of the folder stops watching. The task ends when the monitor closes.
- When the system gives no notification for the folder, `FolderMonitor` throws an `IOError`, and the function answers `nothing`. The store then polls that folder.

A folder that the store watches already keeps its watcher, so a program loads the package before it watches its first file.

## Why it is a package of its own

The platform takes no new dependency, not even a standard library: a dependency comes from an adapter. The poll of the platform works on every file system, and needs nothing. The notifications of the system need `FileWatching`, so they come from this package, and a program loads it to get them.

## Tests

`test_filewatching()` runs the layering guard and `test_folder_monitor()`: the package registers its watch when it loads, and a change of a file reaches its document through the monitor, in a store whose poll of 60 s can not bring it in the time of the test. In the same process, `test_filechange()` of the platform runs its cases with the monitor.
