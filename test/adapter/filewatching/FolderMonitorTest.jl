# The watch of the system: the package registers it when it loads, a store then
# watches a folder with a `FolderMonitor`, and a change of a file reaches its
# document.

"""
    test_folder_monitor()

The package registers `start_folder_monitor!` when it loads, and a store with a
poll too slow for the test sees a change of a file through the monitor.
"""
function test_folder_monitor()
    @testset "folder monitor" begin
        @testset "the package registers its watch when it loads" begin
            @test FileChangeModule._FOLDER_WATCH[] === start_folder_monitor!
        end

        @testset "a change of a file reaches its document through the monitor" begin
            # A poll of a minute does not see the change in the time of the test.
            store = FileChangeStore(; poll_interval = 60.0)
            folder = mktempdir()
            path = joinpath(folder, "watched.txt")
            write(path, "one\n")
            tab = make_file_tab(path)
            watch_document_file!(tab; store)
            @test store.watchers[folder] isa FolderMonitor
            write(path, "two\n")
            deadline = time() + 10.0
            while lock(() -> isempty(store.changed), store.lock) && time() < deadline
                sleep(0.05)
            end
            @test drain_file_changes!(; store) == 1
            @test getfield(get_file_content(tab), :value)[] == "two\n"
            unwatch_document_file!(tab; store)
            @test isempty(store.watchers)
        end
    end
end
