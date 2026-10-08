# The watch of a folder by the system comes from an adapter

## 1. The request

The owner, 2026-10-08: "FileWatching dependency should come from an adapter, no
new platform dependency". Commit 6dfd63695 gave `ProjecturedPlatform` the
standard library `FileWatching`, for the `FolderMonitor` of the slice
`filechange`. The owner approved the seam of §3 ("do it here").

## 2. What exists

- `source/platform/filechange/FileChangeStore.jl` starts a `FolderMonitor` for
  each folder that holds a watched file, and polls the folder when the monitor
  can not start. `unwatch_document_file!` closes the monitor.
- The poll keeps the time and the size of each file from its own first look. A
  change before that first look is lost.
- `test_file_change_store()` relies on the monitor in four of its five tests.
- No package uses the store on main. The `builds` branch of omnet-julia uses
  `make_file_change_feeds()` and `watch_document_file!`.

## 3. The design

- The platform polls by default, and has no `FileWatching`.
- `register_folder_watch!(watch)` in `FileChangeModule` takes a function
  `watch(folder, record)`. It starts to watch the folder, calls `record()` at
  each change, and answers a value that `close` stops, or `nothing` when the
  system gives no notification for the folder. The store then polls the folder.
- The adapter `ProjecturedFileWatching` (`source/adapter/filewatching/`,
  `FileWatchingModule`) depends on the platform and on `FileWatching`. It
  registers `start_folder_monitor!` when it loads. It declares the trigger
  `Projectured`, with the default `auto`, as the other adapters do.
- The poll compares with the time and the size that the store keeps for each
  watched file from the start of its watch, so no change is lost.

## 4. Steps

- [x] **Step 1.** The seam, the poll as the default, and the stamp of the watch
  in the platform. No `FileWatching` in `ProjecturedPlatform`; the tracked
  manifests are resolved. `test_filechange()` passes with the poll, 38 of 38,
  five times in one process.
  - The poll keeps no stamps of its own: `WatchedFile.stamp` holds the time and
    the size from the start of the watch, and each look of the poll updates it.
  - The test of the feed waited only for the mark of the change, and the wake
    comes after it. With the poll it failed once; it now waits for the wake too,
    with a limit of 10 s.
  - A new test checks the seam with a stand-in watcher, and a watch that
    answers `nothing`. It restores the registered watch at its end.
- [x] **Step 2.** The package `ProjecturedFileWatching` and its test package,
  `environment/all`, and the test of the monitor. `test_filewatching()` passes,
  12 of 12; in the same process `test_filechange()` passes with the monitor, 38
  of 38, three times.
  - The slice names the store bare (`using ..FileChangeModule`): the layering
    guard refuses an `import` of a name that the file does not extend, and a
    symbol list on a `using`.
  - The test of the monitor gives the store a poll of 60 s, so only the monitor
    can bring the change in the time of the test.
  - Like `ProjecturedOpenRouterTest`, the test package is in `environment/all`
    and not in the suite of `test_all`.
- [x] **Step 3.** The documents and the tables: the filechange document, the
  adapter document, the package index, the package rules, the auto-integration
  table, the summary of the builder; the guards of the packages.
  - The README table of the builder needs the entry: the release takes every
    package that is not an example, a test or an exclusion, so the adapter is
    released.
  - `test_packages_declare_triggers()` lists the adapter beside the model
    adapters.
  - The exports guard wants the definitions in a fragment, so the function is in
    `FolderMonitor.jl`, and the module file holds the registration.
  - The standalone guards (`test/suite/*.jl`) report nothing of this branch; the
    arguments, documentation and exports guards report findings of main.
