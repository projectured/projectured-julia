"""
    ProjecturedFileWatchingTest

The file watching tier of the test-package DAG: the suite for the watch of a
folder by the notifications of the system.

Everything is aggregated by `test_filewatching()`.
"""
module ProjecturedFileWatchingTest

using Test
using FileWatching: FolderMonitor
using ProjecturedKernelTest
using ProjecturedFileWatching
using ProjecturedPlatform.SerializationModule: get_file_content
using ProjecturedPlatform.FileFormatModule: make_file_tab
using ProjecturedPlatform.FileChangeModule

import ProjecturedPlatform.FileChangeModule

include("../../../test/adapter/filewatching/FolderMonitorTest.jl")
include("../../../test/adapter/filewatching/FileWatchingSuite.jl")

end # module ProjecturedFileWatchingTest
