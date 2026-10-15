# Tests of the store of the watched files: the watcher reports a change of a file
# to the receiver of the file, and the receiver decides what it means. The page of
# a file in a tab is the receiver: a change reaches a page whose file has no edits,
# a save of the page is no change, and a page whose file has edits keeps them and
# shows its band. A file with no page keeps what it holds, and a file that a person
# does not edit is read again by the time and the size of its file. A file that a
# person edits keeps a history in its content, as the application keeps one, and
# the history tells its edits.

# A text file in a folder of its own, and its page, whose file keeps a history in
# its content.
function _make_watched_text_file(text::AbstractString; wrap = UndoBuffer)
    folder = mktempdir()
    path = joinpath(folder, "watched.txt")
    write(path, text)
    (path, make_file_tab_content(path, wrap))
end

# Watch the file of a page, with the page as the receiver, as the tab of a page does.
_watch_page!(page; store) = watch_document_file!(find_page_file(page); store, receiver = page)
_unwatch_page!(page; store) = unwatch_document_file!(find_page_file(page); store)

_get_watched_text(page::FilePage) = _get_watched_text(find_page_file(page))
_get_watched_text(file) = getfield(get_wrapped_document(get_file_content(file)), :value)[]

# An edit through the history, as the projection of the history records one. An
# entry is a value, so each edit takes its text as its label: two equal entries
# would be one step.
function _edit_watched_text!(page, text)
    buffer = get_file_content(find_page_file(page))
    set_cell_value!(getfield(get_wrapped_document(buffer), :value), text)
    push_undo_entry!(buffer, UndoEntry(text, DoNothingOperation(), nothing))
end

# The labels of the choices of the band of a page.
_get_band_labels(page) = String[first(choice) for choice in page.band.choices]
_find_band_choice(page, label) = last(only(c for c in page.band.choices if first(c) == label))

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
        @testset "a change of a file reaches a page whose file has no edits" begin
            store = FileChangeStore()
            (path, page) = _make_watched_text_file("one\n")
            @test page.file_hash == hash("one\n")
            _watch_page!(page; store)
            @test is_document_file_watched(find_page_file(page); store)
            write(path, "two\n")
            @test _wait_for_file_change(store)
            @test drain_file_changes!(; store) == 1
            @test _get_watched_text(page) == "two\n"
            @test page.file_hash == hash("two\n") && page.band === nothing
            # A file written at once, by a rename over it, is seen too.
            temporary = joinpath(dirname(path), "watched.tmp")
            write(temporary, "three\n")
            mv(temporary, path; force = true)
            @test _wait_for_file_change(store)
            @test drain_file_changes!(; store) == 1
            @test _get_watched_text(page) == "three\n"
            _unwatch_page!(page; store)
            @test !is_document_file_watched(find_page_file(page); store)
            @test isempty(store.watchers)
        end

        @testset "a save of the page is no change" begin
            store = FileChangeStore()
            (path, page) = _make_watched_text_file("one\n")
            _watch_page!(page; store)
            _edit_watched_text!(page, "saved\n")
            @test evaluate_operation(nothing, SaveFilePageOperation(page)) === true
            @test read(path, String) == "saved\n"
            @test page.file_hash == hash("saved\n")
            @test _wait_for_file_change(store)
            @test (@test_logs drain_file_changes!(; store)) == 0
            @test _get_watched_text(page) == "saved\n" && page.band === nothing
            # After the save, a change of another program reaches it again.
            write(path, "theirs\n")
            @test _wait_for_file_change(store)
            @test drain_file_changes!(; store) == 1
            @test _get_watched_text(page) == "theirs\n"
            _unwatch_page!(page; store)
        end

        @testset "a page whose file has edits keeps them, and its band offers the file" begin
            store = FileChangeStore()
            (path, page) = _make_watched_text_file("one\n")
            _watch_page!(page; store)
            _edit_watched_text!(page, "mine\n")
            write(path, "theirs\n")
            @test _wait_for_file_change(store)
            @test (@test_logs drain_file_changes!(; store)) == 0
            @test _get_watched_text(page) == "mine\n"
            @test page.band.message == "watched.txt changed on disk."
            @test _get_band_labels(page) == ["Load it", "Keep mine"]
            # The same change is told once.
            page.band = nothing
            lock(() -> push!(store.changed, abspath(path)), store.lock)
            @test drain_file_changes!(; store) == 0
            @test page.band === nothing
            # Keep mine: the page takes the file on disk as its own, so a save writes.
            write(path, "theirs again\n")
            @test _wait_for_file_change(store)
            @test drain_file_changes!(; store) == 0
            keep = _find_band_choice(page, "Keep mine")
            @test keep isa KeepFilePageEditsOperation
            evaluate_operation(nothing, keep)
            @test page.band === nothing && page.file_hash == hash("theirs again\n")
            @test evaluate_operation(nothing, SaveFilePageOperation(page)) === true
            @test read(path, String) == "mine\n"
            # Load it: the page takes the document that the watcher read.
            @test _wait_for_file_change(store)
            @test drain_file_changes!(; store) == 0
            _edit_watched_text!(page, "mine again\n")
            write(path, "last\n")
            @test _wait_for_file_change(store)
            @test drain_file_changes!(; store) == 0
            evaluate_operation(nothing, _find_band_choice(page, "Load it"))
            @test _get_watched_text(page) == "last\n"
            @test page.band === nothing && page.file_hash == hash("last\n")
            _unwatch_page!(page; store)
        end

        @testset "a page whose file keeps no history shows its band" begin
            store = FileChangeStore()
            (path, page) = _make_watched_text_file("one\n"; wrap = identity)
            _watch_page!(page; store)
            write(path, "theirs\n")
            @test _wait_for_file_change(store)
            @test drain_file_changes!(; store) == 0
            @test _get_watched_text(page) == "one\n"
            @test _get_band_labels(page) == ["Load it", "Keep mine"]
            _unwatch_page!(page; store)
        end

        @testset "a file with no page keeps what it shows, and the log says so" begin
            store = FileChangeStore()
            (path, page) = _make_watched_text_file("one\n")
            file = find_page_file(page)
            watch_document_file!(file; store)
            write(path, "theirs\n")
            @test _wait_for_file_change(store)
            @test (@test_logs (:warn, r"with no page") drain_file_changes!(; store)) == 0
            @test _get_watched_text(file) == "one\n"
            unwatch_document_file!(file; store)
        end

        @testset "the save of a page checks the disk first" begin
            (path, page) = _make_watched_text_file("one\n")
            _edit_watched_text!(page, "mine\n")
            write(path, "theirs\n")
            # A newer file on disk: the page shows its band and writes nothing.
            @test evaluate_operation(nothing, SaveFilePageOperation(page)) === false
            @test read(path, String) == "theirs\n"
            @test _get_band_labels(page) == ["Load it", "Keep mine"]
            # Keep mine writes over it.
            evaluate_operation(nothing, _find_band_choice(page, "Keep mine"))
            @test read(path, String) == "mine\n"
            @test page.band === nothing && page.file_hash == hash("mine\n")
            # Load it reads the file on disk now.
            write(path, "newer\n")
            @test evaluate_operation(nothing, SaveFilePageOperation(page)) === false
            evaluate_operation(nothing, _find_band_choice(page, "Load it"))
            @test _get_watched_text(page) == "newer\n"
            @test page.band === nothing && page.file_hash == hash("newer\n")
            # A history above the page adds no step for a save and a keep.
            @test make_inverse_operation(nothing, SaveFilePageOperation(page)) isa DoNothingOperation
            @test make_inverse_operation(nothing, KeepFilePageEditsOperation(page, hash(""))) isa DoNothingOperation
        end

        @testset "the feed drains the store, and a change wakes the editor" begin
            store = FileChangeStore()
            feed = FileChangeFeed(; store)
            woken = Threads.Atomic{Int}(0)
            attach_wake_callback!(feed, () -> Threads.atomic_add!(woken, 1))
            (path, page) = _make_watched_text_file("one\n")
            _watch_page!(page; store)
            write(path, "two\n")
            @test _wait_for_file_change(store)
            # The watcher wakes the editor after it marks the change.
            deadline = time() + 10.0
            while woken[] < 1 && time() < deadline
                sleep(0.01)
            end
            @test woken[] >= 1
            @test drain_changes!(feed, nothing) == 1
            @test _get_watched_text(page) == "two\n"
            @test drain_changes!(feed, nothing) == 0
            _unwatch_page!(page; store)
        end

        @testset "a file type that an opener chose reads its own text again" begin
            store = FileChangeStore()
            folder = mktempdir()
            path = joinpath(folder, "note.txt")
            write(path, "hello\n")
            file = _ShoutedFile(path, UndoBuffer(PrimitiveString("HELLO\n")))
            @test compute_file_text(file) == "hello\n"
            page = make_file_page(WidgetScrollPane(file))
            _watch_page!(page; store)
            write(path, "bye\n")
            @test _wait_for_file_change(store)
            @test drain_file_changes!(; store) == 1
            # Read by its own type, not by the text file that `.txt` names.
            @test get_wrapped_document(get_file_content(file)) isa PrimitiveString
            @test getfield(get_wrapped_document(get_file_content(file)), :value)[] == "BYE\n"
            _unwatch_page!(page; store)
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
            # Its page reads no text for a hash.
            @test make_file_page(WidgetScrollPane(file)).file_hash === nothing
            unwatch_document_file!(file; store)
        end

        @testset "a folder with no notification is polled" begin
            store = FileChangeStore(; poll_interval = 0.05)
            (path, page) = _make_watched_text_file("one\n")
            folder = dirname(path)
            # The folder is marked as polled before the watch, as a folder of a
            # file system with no notification is.
            lock(() -> store.watchers[folder] = :poll, store.lock)
            _watch_page!(page; store)
            errormonitor(Threads.@spawn FileChangeModule._poll_folder(store, folder))
            sleep(0.3)
            write(path, "a longer text\n")
            @test _wait_for_file_change(store)
            @test drain_file_changes!(; store) == 1
            @test _get_watched_text(page) == "a longer text\n"
            _unwatch_page!(page; store)
            @test isempty(store.watchers)
        end

        @testset "each editor watches in the store of its own feed, and no editor watches nothing" begin
            make_watching_editor() = Editor(PrimitiveString("x"), IdentityProjection(); backend = HeadlessBackend(),
                                            devices = Device[], feeds = Feed[FileChangeFeed()])
            first_editor, second_editor = make_watching_editor(), make_watching_editor()
            first_store = get_session_file_change_store(; editor = first_editor)
            @test first_store === only(first_editor.feeds[k] for k in eachindex(first_editor.feeds)
                                       if first_editor.feeds[k] isa FileChangeFeed).store
            @test get_session_file_change_store(; editor = second_editor) !== first_store
            # With no editor, a new store that nothing keeps.
            @test get_session_file_change_store(; editor = nothing) !== get_session_file_change_store(; editor = nothing)
            (path, page) = _make_watched_text_file("one\n")
            tab = find_page_file(page)
            # A watch with no editor of the evaluation does nothing.
            @test watch_document_file!(tab) === tab
            @test !is_document_file_watched(tab; store = first_store)
            # In the evaluation of an editor, the store of its feed.
            run_with_evaluation_editor(first_editor) do
                watch_document_file!(tab)
                @test is_document_file_watched(tab)
            end
            @test is_document_file_watched(tab; store = first_store)
            @test !is_document_file_watched(tab; store = get_session_file_change_store(; editor = second_editor))
            # The close of a store stops its watchers and forgets its files.
            close_file_change_store!(first_store)
            @test isempty(first_store.watchers) && !is_document_file_watched(tab; store = first_store)
        end

        @testset "a file that a tab shows watches its file while the tab is open" begin
            editor = Editor(PrimitiveString("x"), IdentityProjection(); backend = HeadlessBackend(),
                            devices = Device[], feeds = Feed[FileChangeFeed()])
            store = get_session_file_change_store(; editor)
            (path, page) = _make_watched_text_file("one\n")
            file = find_page_file(page)
            tab = PaneTab("watched.txt", WidgetScrollPane(file))
            evaluate_operation(editor, AcquireDocumentOperation(tab))
            @test is_document_file_watched(file; store)
            @test only(store.files).receiver === file
            evaluate_operation(editor, ReleaseDocumentOperation(tab))
            @test !is_document_file_watched(file; store)
            # The page of a file watches the file as its receiver.
            page_tab = PaneTab("watched.txt", page)
            evaluate_operation(editor, AcquireDocumentOperation(page_tab))
            @test only(store.files).receiver === page
            evaluate_operation(editor, ReleaseDocumentOperation(page_tab))
            @test !is_document_file_watched(file; store)
            # An editor with no file change feed watches nothing.
            plain = Editor(PrimitiveString("x"), IdentityProjection(); backend = HeadlessBackend(), devices = Device[])
            evaluate_operation(plain, AcquireDocumentOperation(tab))
            @test !is_document_file_watched(file; store)
        end

        @testset "the wrapper file_change adds a feed, and the end of the loop stops its watchers" begin
            editor = build_editor(PrimitiveString("x"), IdentityProjection(); backend = HeadlessBackend(),
                                  devices = Device[], window = false, tabs = false, appearance = false,
                                  settings = false, file_change = true)
            @test count(feed -> feed isa FileChangeFeed, editor.feeds) == 1
            store = get_session_file_change_store(; editor)
            (path, page) = _make_watched_text_file("one\n")
            file = find_page_file(page)
            evaluate_operation(editor, AcquireDocumentOperation(file))
            @test is_document_file_watched(file; store) && !isempty(store.watchers)
            foreach(step -> step(editor), editor.stop_steps)
            @test isempty(store.watchers) && !is_document_file_watched(file; store)
        end
    end
end
