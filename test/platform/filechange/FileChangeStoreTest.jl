# Tests of the store of the watched files: a change of a file reaches its
# document, a save is no change, an edit that is not saved stays, and the feed
# drains the store and is woken by a change.

# A text file in a folder of its own, and its tab.
function _make_watched_text_file(text::AbstractString)
    folder = mktempdir()
    path = joinpath(folder, "watched.txt")
    write(path, text)
    (path, make_file_tab(path))
end

_get_watched_text(tab) = getfield(get_file_content(tab), :value)[]
_set_watched_text!(tab, text) = set_cell_value!(getfield(get_file_content(tab), :value), text)

# Wait until the store holds a change, for at most `seconds`.
function _wait_for_file_change(store::FileChangeStore; seconds::Real = 10.0)
    deadline = time() + seconds
    while time() < deadline
        lock(() -> !isempty(store.changed), store.lock) && return true
        sleep(0.05)
    end
    false
end

function test_file_change_store()
    @testset "file change store" begin
        @testset "a change of a file reaches a document that was not edited" begin
            store = FileChangeStore()
            (path, tab) = _make_watched_text_file("one\n")
            watch_document_file!(tab; store)
            @test is_document_file_watched(tab; store)
            write(path, "two\n")
            @test _wait_for_file_change(store)
            @test drain_file_changes!(; store) == 1
            @test _get_watched_text(tab) == "two\n"
            # A file written at once, by a rename over it, is seen too.
            temporary = joinpath(dirname(path), "watched.tmp")
            write(temporary, "three\n")
            mv(temporary, path; force = true)
            @test _wait_for_file_change(store)
            @test drain_file_changes!(; store) == 1
            @test _get_watched_text(tab) == "three\n"
            unwatch_document_file!(tab; store)
            @test !is_document_file_watched(tab; store)
            @test isempty(store.watchers)
        end

        @testset "a save of the document is no change" begin
            store = FileChangeStore()
            (path, tab) = _make_watched_text_file("one\n")
            watch_document_file!(tab; store)
            _set_watched_text!(tab, "saved\n")
            evaluate_operation(nothing, SaveFileOperation(tab))
            @test read(path, String) == "saved\n"
            @test _wait_for_file_change(store)
            @test (@test_logs drain_file_changes!(; store)) == 0
            @test _get_watched_text(tab) == "saved\n"
            # After the save, a change of another program reaches it again.
            write(path, "theirs\n")
            @test _wait_for_file_change(store)
            @test drain_file_changes!(; store) == 1
            @test _get_watched_text(tab) == "theirs\n"
            unwatch_document_file!(tab; store)
        end

        @testset "a document with edits that are not saved keeps them" begin
            store = FileChangeStore()
            (path, tab) = _make_watched_text_file("one\n")
            watch_document_file!(tab; store)
            _set_watched_text!(tab, "mine\n")
            write(path, "theirs\n")
            @test _wait_for_file_change(store)
            @test (@test_logs (:warn, r"changed on disk") drain_file_changes!(; store)) == 0
            @test _get_watched_text(tab) == "mine\n"
            # The same change is told once.
            lock(() -> push!(store.changed, abspath(path)), store.lock)
            @test (@test_logs drain_file_changes!(; store)) == 0
            unwatch_document_file!(tab; store)
        end

        @testset "the feed drains the store, and a change wakes the editor" begin
            store = FileChangeStore()
            feed = FileChangeFeed(; store)
            woken = Threads.Atomic{Int}(0)
            attach_wake_callback!(feed, () -> Threads.atomic_add!(woken, 1))
            (path, tab) = _make_watched_text_file("one\n")
            watch_document_file!(tab; store)
            write(path, "two\n")
            @test _wait_for_file_change(store)
            @test woken[] >= 1
            @test drain_changes!(feed, nothing) == 1
            @test _get_watched_text(tab) == "two\n"
            @test drain_changes!(feed, nothing) == 0
            unwatch_document_file!(tab; store)
        end

        @testset "a folder with no notification is polled" begin
            store = FileChangeStore(; poll_interval = 0.05)
            (path, tab) = _make_watched_text_file("one\n")
            folder = dirname(path)
            # The folder is marked as polled before the watch, as a folder of a
            # file system with no notification is.
            lock(() -> store.watchers[folder] = :poll, store.lock)
            watch_document_file!(tab; store)
            errormonitor(Threads.@spawn FileChangeModule._poll_folder(store, folder))
            sleep(0.3)
            write(path, "a longer text\n")
            @test _wait_for_file_change(store)
            @test drain_file_changes!(; store) == 1
            @test _get_watched_text(tab) == "a longer text\n"
            unwatch_document_file!(tab; store)
            @test isempty(store.watchers)
        end
    end
end
