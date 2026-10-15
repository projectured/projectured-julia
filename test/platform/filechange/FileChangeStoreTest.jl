# Tests of the store of the watched files: a change of a file reaches its
# document, a save is no change, an edit that is not saved stays, and the feed
# drains the store and is woken by a change. A file that a person does not edit
# is read again by the time and the size of its file. A file that a person edits
# keeps a history in its content, as the application keeps one, and the history
# tells its edits and its saves.

# A text file in a folder of its own, and its tab, whose content keeps a history.
function _make_watched_text_file(text::AbstractString; wrap = UndoBuffer)
    folder = mktempdir()
    path = joinpath(folder, "watched.txt")
    write(path, text)
    (path, make_file_tab(path, wrap))
end

_get_watched_text(tab) = getfield(get_wrapped_document(get_file_content(tab)), :value)[]

# An edit through the history, as the projection of the history records one.
function _edit_watched_text!(tab, text)
    buffer = get_file_content(tab)
    set_cell_value!(getfield(get_wrapped_document(buffer), :value), text)
    push_undo_entry!(buffer, UndoEntry("type", DoNothingOperation(), nothing))
end

# A file type that no extension names: an opener chooses it, as a store in a
# `.json` file is chosen. It holds its text in capitals and writes it in small
# letters.
@document struct _ShoutedFile <: FileDocument
    filename::String
    content::Any
end
SerializationModule.get_file_domain(::Type{<:_ShoutedFile}) = Document
SerializationModule.parse_file_content(::Type{<:_ShoutedFile}, text::AbstractString) =
    PrimitiveString(uppercase(String(text)))
SerializationModule.emit_text(file::_ShoutedFile) =
    lowercase(something(getfield(get_file_content(file), :value)[], ""))

# A file type that a person does not edit, as a result file of a run is: it reads
# its file itself and says only its size, and it notes the task of each read, so a
# test sees that the drain reads none of it.
@document struct _ReadOnlyProbeFile <: FileDocument
    filename::String
    content::Any
end
const _READ_ONLY_PROBE_READERS = Task[]
const _READ_ONLY_PROBE_LOCK = ReentrantLock()
SerializationModule.get_file_domain(::Type{<:_ReadOnlyProbeFile}) = Document
SerializationModule.is_editable_file_type(::Type{<:_ReadOnlyProbeFile}) = false
function SerializationModule.read_file_content(::Type{<:_ReadOnlyProbeFile}, path::AbstractString)
    lock(() -> push!(_READ_ONLY_PROBE_READERS, current_task()), _READ_ONLY_PROBE_LOCK)
    PrimitiveString(string(filesize(path), " bytes"))
end

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
            _edit_watched_text!(tab, "saved\n")
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
            _edit_watched_text!(tab, "mine\n")
            write(path, "theirs\n")
            @test _wait_for_file_change(store)
            @test (@test_logs (:warn, r"changed on disk") drain_file_changes!(; store)) == 0
            @test _get_watched_text(tab) == "mine\n"
            # The same change is told once.
            lock(() -> push!(store.changed, abspath(path)), store.lock)
            @test (@test_logs drain_file_changes!(; store)) == 0
            unwatch_document_file!(tab; store)
        end

        @testset "a content with no history keeps what it shows, and the log says so" begin
            store = FileChangeStore()
            (path, tab) = _make_watched_text_file("one\n"; wrap = identity)
            watch_document_file!(tab; store)
            write(path, "theirs\n")
            @test _wait_for_file_change(store)
            @test (@test_logs (:warn, r"keeps no history") drain_file_changes!(; store)) == 0
            @test _get_watched_text(tab) == "one\n"
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
            # The watcher wakes the editor after it marks the change.
            deadline = time() + 10.0
            while woken[] < 1 && time() < deadline
                sleep(0.01)
            end
            @test woken[] >= 1
            @test drain_changes!(feed, nothing) == 1
            @test _get_watched_text(tab) == "two\n"
            @test drain_changes!(feed, nothing) == 0
            unwatch_document_file!(tab; store)
        end

        @testset "a file type that an opener chose reads its own text again" begin
            store = FileChangeStore()
            folder = mktempdir()
            path = joinpath(folder, "note.txt")
            write(path, "hello\n")
            file = _ShoutedFile(path, UndoBuffer(PrimitiveString("HELLO\n")))
            @test compute_file_text(file) == "hello\n"
            watch_document_file!(file; store)
            write(path, "bye\n")
            @test _wait_for_file_change(store)
            @test drain_file_changes!(; store) == 1
            # Read by its own type, not by the text file that `.txt` names.
            @test get_wrapped_document(get_file_content(file)) isa PrimitiveString
            @test getfield(get_wrapped_document(get_file_content(file)), :value)[] == "BYE\n"
            unwatch_document_file!(file; store)
        end

        @testset "a file that a person does not edit is read again by its stamp" begin
            store = FileChangeStore()
            path = joinpath(mktempdir(), "results.vec")
            write(path, "12345")
            file = _ReadOnlyProbeFile(path, read_file_content(_ReadOnlyProbeFile, path))
            watch_document_file!(file; store)
            lock(() -> empty!(_READ_ONLY_PROBE_READERS), _READ_ONLY_PROBE_LOCK)
            write(path, "1234567890")
            @test _wait_for_file_change(store)
            @test drain_file_changes!(; store) == 1
            @test getfield(get_file_content(file), :value)[] == "10 bytes"
            # The watcher read it on its own task, and the drain read nothing.
            readers = lock(() -> copy(_READ_ONLY_PROBE_READERS), _READ_ONLY_PROBE_LOCK)
            @test !isempty(readers) && all(reader -> reader !== current_task(), readers)
            # A drain with no new change takes nothing.
            lock(() -> push!(store.changed, abspath(path)), store.lock)
            @test drain_file_changes!(; store) == 0
            # A save writes nothing of it.
            evaluate_operation(nothing, SaveFileOperation(file))
            @test read(path, String) == "1234567890"
            unwatch_document_file!(file; store)
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
