# Tests of the store of the watched files: the watcher reports a change of a file
# to the receiver of the file, and the receiver decides what it means. The file
# document is the receiver: a change reaches a file that has no edits, a save of the
# file is no change, and a file that has edits keeps them and shows its band. A file
# that a person does not edit is read again by the time and the size of its file. A
# file that a person edits keeps a history in its content, as the application keeps
# one, and the history tells its edits.

# A text file in a folder of its own, whose content keeps a history.
function _make_watched_text_file(text::AbstractString; wrap = UndoBuffer)
    folder = mktempdir()
    path = joinpath(folder, "watched.txt")
    write(path, text)
    (path, make_file_tab(path, wrap))
end

_get_watched_text(file) = getfield(get_wrapped_document(get_file_content(file)), :value)[]

# An edit through the history, as the projection of the history records one. An
# entry is a value, so each edit takes its text as its label: two equal entries
# would be one step.
function _edit_watched_text!(file, text)
    buffer = get_file_content(file)
    set_cell_value!(getfield(get_wrapped_document(buffer), :value), text)
    push_undo_entry!(buffer, UndoEntry(text, DoNothingOperation(), nothing))
end

# The labels of the choices of the band of a file.
_get_band_labels(file) = String[first(choice) for choice in get_file_disk_state(file).band.choices]
_find_band_choice(file, label) = last(only(c for c in get_file_disk_state(file).band.choices if first(c) == label))

# A file type that no extension names: an opener chooses it, as a store in a
# `.json` file is chosen. It holds its text in capitals and writes it in small
# letters.
@document struct _ShoutedFile <: FileDocument
    filename::String
    content::Any
    disk::FileDiskState = FileDiskState()
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
    disk::FileDiskState = FileDiskState()
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

# A receiver that watches folders, and notes each folder that a drain reports.
struct _FolderChangeProbe
    folders::Vector{String}
end
ProjecturedPlatform.FileChangeModule.receive_folder_change!(editor, probe::_FolderChangeProbe, folder) =
    (push!(probe.folders, folder); true)

# Wait until the store holds a change of a watched folder, for at most `seconds`.
function _wait_for_folder_change(store::FileChangeStore; seconds::Real = 10.0)
    deadline = time() + seconds
    while time() < deadline
        lock(() -> !isempty(store.changed_folders), store.lock) && return true
        sleep(0.05)
    end
    false
end

function test_file_change_store()
    @testset "file change store" begin
        @testset "a receiver that watches a folder learns that an entry came or went" begin
            store = FileChangeStore()
            folder = mktempdir()
            receiver = _FolderChangeProbe(String[])
            @test watch_folder!(folder; store, receiver)
            @test is_folder_watched(folder; store) && is_folder_watched(folder * "/"; store, receiver)
            write(joinpath(folder, "new.txt"), "x")
            @test _wait_for_folder_change(store)
            @test drain_file_changes!(; store) == 1
            @test receiver.folders == [folder]
            # A second receiver shares the watcher of the folder.
            other = _FolderChangeProbe(String[])
            @test watch_folder!(folder; store, receiver = other)
            @test length(store.watchers) == 1
            unwatch_folder!(folder; store, receiver)
            @test !is_folder_watched(folder; store, receiver) && is_folder_watched(folder; store)
            rm(joinpath(folder, "new.txt"))
            @test _wait_for_folder_change(store)
            @test drain_file_changes!(; store) == 1
            @test other.folders == [folder] && receiver.folders == [folder]
            # The watcher stops when nothing watches the folder.
            unwatch_folder!(folder; store, receiver = other)
            @test isempty(store.watchers)
        end

        @testset "a store starts no more watchers of folders than its limit" begin
            store = FileChangeStore(; watch_limit = 1)
            (first_folder, second_folder) = (mktempdir(), mktempdir())
            receiver = _FolderChangeProbe(String[])
            @test watch_folder!(first_folder; store, receiver)
            @test !watch_folder!(second_folder; store, receiver)
            # A folder that is watched already costs no new watcher.
            @test watch_folder!(first_folder; store, receiver = _FolderChangeProbe(String[]))
            @test !watch_folder!(joinpath(first_folder, "missing"); store, receiver)
            close_file_change_store!(store)
            @test isempty(store.watchers) && isempty(store.folders)
        end

        @testset "a change of a file reaches a file that has no edits" begin
            store = FileChangeStore()
            (path, file) = _make_watched_text_file("one\n")
            @test get_file_disk_state(file).file_hash == hash("one\n")
            watch_document_file!(file; store)
            @test is_document_file_watched(file; store)
            write(path, "two\n")
            @test _wait_for_file_change(store)
            @test drain_file_changes!(; store) == 1
            @test _get_watched_text(file) == "two\n"
            @test get_file_disk_state(file).file_hash == hash("two\n") && get_file_disk_state(file).band === nothing
            # A file written at once, by a rename over it, is seen too.
            temporary = joinpath(dirname(path), "watched.tmp")
            write(temporary, "three\n")
            mv(temporary, path; force = true)
            @test _wait_for_file_change(store)
            @test drain_file_changes!(; store) == 1
            @test _get_watched_text(file) == "three\n"
            unwatch_document_file!(file; store)
            @test !is_document_file_watched(file; store)
            @test isempty(store.watchers)
        end

        @testset "a save of the file is no change" begin
            store = FileChangeStore()
            (path, file) = _make_watched_text_file("one\n")
            watch_document_file!(file; store)
            _edit_watched_text!(file, "saved\n")
            @test evaluate_operation(nothing, SaveFileOperation(file)) === true
            @test read(path, String) == "saved\n"
            @test get_file_disk_state(file).file_hash == hash("saved\n")
            @test _wait_for_file_change(store)
            @test (@test_logs drain_file_changes!(; store)) == 0
            @test _get_watched_text(file) == "saved\n" && get_file_disk_state(file).band === nothing
            # After the save, a change of another program reaches it again.
            write(path, "theirs\n")
            @test _wait_for_file_change(store)
            @test drain_file_changes!(; store) == 1
            @test _get_watched_text(file) == "theirs\n"
            unwatch_document_file!(file; store)
        end

        @testset "a file that has edits keeps them, and its band offers the file" begin
            store = FileChangeStore()
            (path, file) = _make_watched_text_file("one\n")
            watch_document_file!(file; store)
            _edit_watched_text!(file, "mine\n")
            write(path, "theirs\n")
            @test _wait_for_file_change(store)
            @test (@test_logs drain_file_changes!(; store)) == 0
            @test _get_watched_text(file) == "mine\n"
            @test get_file_disk_state(file).band.message == "watched.txt changed on disk."
            @test _get_band_labels(file) == ["Load it", "Keep mine"]
            # The same change is told once.
            get_file_disk_state(file).band = nothing
            lock(() -> push!(store.changed, abspath(path)), store.lock)
            @test drain_file_changes!(; store) == 0
            @test get_file_disk_state(file).band === nothing
            # Keep mine: the file takes the file on disk as its own, so a save writes.
            write(path, "theirs again\n")
            @test _wait_for_file_change(store)
            @test drain_file_changes!(; store) == 0
            keep = _find_band_choice(file, "Keep mine")
            @test keep isa KeepFileEditsOperation
            evaluate_operation(nothing, keep)
            @test get_file_disk_state(file).band === nothing && get_file_disk_state(file).file_hash == hash("theirs again\n")
            @test evaluate_operation(nothing, SaveFileOperation(file)) === true
            @test read(path, String) == "mine\n"
            # Load it: the file takes the document that the watcher read.
            @test _wait_for_file_change(store)
            @test drain_file_changes!(; store) == 0
            _edit_watched_text!(file, "mine again\n")
            write(path, "last\n")
            @test _wait_for_file_change(store)
            @test drain_file_changes!(; store) == 0
            evaluate_operation(nothing, _find_band_choice(file, "Load it"))
            @test _get_watched_text(file) == "last\n"
            @test get_file_disk_state(file).band === nothing && get_file_disk_state(file).file_hash == hash("last\n")
            unwatch_document_file!(file; store)
        end

        @testset "a file that keeps no history shows its band" begin
            store = FileChangeStore()
            (path, file) = _make_watched_text_file("one\n"; wrap = identity)
            watch_document_file!(file; store)
            write(path, "theirs\n")
            @test _wait_for_file_change(store)
            @test drain_file_changes!(; store) == 0
            @test _get_watched_text(file) == "one\n"
            @test _get_band_labels(file) == ["Load it", "Keep mine"]
            unwatch_document_file!(file; store)
        end

        @testset "the file is the receiver of its own watch" begin
            store = FileChangeStore()
            (path, file) = _make_watched_text_file("one\n")
            watch_document_file!(file; store)
            @test only(store.files).receiver === file
            write(path, "theirs\n")
            @test _wait_for_file_change(store)
            @test drain_file_changes!(; store) == 1
            @test _get_watched_text(file) == "theirs\n"
            unwatch_document_file!(file; store)
        end

        @testset "the save of a file checks the disk first" begin
            (path, file) = _make_watched_text_file("one\n")
            _edit_watched_text!(file, "mine\n")
            write(path, "theirs\n")
            # A newer file on disk: the file shows its band and writes nothing.
            @test evaluate_operation(nothing, SaveFileOperation(file)) === false
            @test read(path, String) == "theirs\n"
            @test _get_band_labels(file) == ["Load it", "Keep mine"]
            # Keep mine writes over it.
            evaluate_operation(nothing, _find_band_choice(file, "Keep mine"))
            @test read(path, String) == "mine\n"
            @test get_file_disk_state(file).band === nothing && get_file_disk_state(file).file_hash == hash("mine\n")
            # Load it reads the file on disk now.
            write(path, "newer\n")
            @test evaluate_operation(nothing, SaveFileOperation(file)) === false
            evaluate_operation(nothing, _find_band_choice(file, "Load it"))
            @test _get_watched_text(file) == "newer\n"
            @test get_file_disk_state(file).band === nothing && get_file_disk_state(file).file_hash == hash("newer\n")
            # A history in the file adds no step for a save and a keep.
            @test make_inverse_operation(nothing, SaveFileOperation(file)) isa DoNothingOperation
            @test make_inverse_operation(nothing, KeepFileEditsOperation(file, hash(""))) isa DoNothingOperation
        end

        @testset "a save of a holder writes only the holder, and a held file keeps its hash, its band and its edits" begin
            (held_path, held) = _make_watched_text_file("one\n")
            _edit_watched_text!(held, "mine\n")
            held_state = get_file_disk_state(held)
            held_state.band = FileBand(message = "watched.txt changed on disk.")
            held_hash = held_state.file_hash
            folder = dirname(held_path)
            holder_path = joinpath(folder, "work.pred")
            @test save_file!(PredFile(holder_path, Dashboard("work")), folder)
            holder = make_file_tab(holder_path, UndoBuffer)
            dashboard = get_wrapped_document(get_file_content(holder))
            push!(dashboard.cards, DashboardCard("notes", held))
            @test evaluate_operation(nothing, SaveFileOperation(holder)) === true
            @test occursin("content = file(\"watched.txt\")", read(holder_path, String))
            @test sort(readdir(folder)) == ["watched.txt", "work.pred"]
            @test read(held_path, String) == "one\n"
            @test held_state.file_hash == held_hash && held_state.band !== nothing
            @test _get_watched_text(held) == "mine\n"
        end

        @testset "the feed drains the store, and a change wakes the editor" begin
            store = FileChangeStore()
            feed = FileChangeFeed(; store)
            woken = Threads.Atomic{Int}(0)
            attach_wake_callback!(feed, () -> Threads.atomic_add!(woken, 1))
            (path, file) = _make_watched_text_file("one\n")
            watch_document_file!(file; store)
            write(path, "two\n")
            @test _wait_for_file_change(store)
            # The watcher wakes the editor after it marks the change.
            deadline = time() + 10.0
            while woken[] < 1 && time() < deadline
                sleep(0.01)
            end
            @test woken[] >= 1
            @test drain_changes!(feed, nothing) == 1
            @test _get_watched_text(file) == "two\n"
            @test drain_changes!(feed, nothing) == 0
            unwatch_document_file!(file; store)
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
            # A new file of the type reads no text for a hash.
            @test get_file_disk_state(_ReadOnlyProbeFile(path, read_file_content(_ReadOnlyProbeFile, path))).file_hash === nothing
            unwatch_document_file!(file; store)
        end

        @testset "a folder with no notification is polled" begin
            store = FileChangeStore(; poll_interval = 0.05)
            (path, file) = _make_watched_text_file("one\n")
            folder = dirname(path)
            # The folder is marked as polled before the watch, as a folder of a
            # file system with no notification is.
            lock(() -> store.watchers[folder] = :poll, store.lock)
            watch_document_file!(file; store)
            errormonitor(Threads.@spawn FileChangeModule._poll_folder(store, folder))
            sleep(0.3)
            write(path, "a longer text\n")
            @test _wait_for_file_change(store)
            @test drain_file_changes!(; store) == 1
            @test _get_watched_text(file) == "a longer text\n"
            unwatch_document_file!(file; store)
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
            (path, file) = _make_watched_text_file("one\n")
            tab = file
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
            (path, file) = _make_watched_text_file("one\n")
            tab = PaneTab("watched.txt", WidgetScrollPane(file))
            evaluate_operation(editor, AcquireDocumentOperation(tab))
            @test is_document_file_watched(file; store)
            @test only(store.files).receiver === file
            evaluate_operation(editor, ReleaseDocumentOperation(tab))
            @test !is_document_file_watched(file; store)
            # The view of a file watches the file as its receiver.
            view_tab = PaneTab("watched.txt", make_file_view(file))
            evaluate_operation(editor, AcquireDocumentOperation(view_tab))
            @test only(store.files).receiver === file
            evaluate_operation(editor, ReleaseDocumentOperation(view_tab))
            @test !is_document_file_watched(file; store)
            # An editor with no file change feed watches nothing.
            plain = Editor(PrimitiveString("x"), IdentityProjection(); backend = HeadlessBackend(), devices = Device[])
            evaluate_operation(plain, AcquireDocumentOperation(tab))
            @test !is_document_file_watched(file; store)
        end

        @testset "a view holds the file that it shows, where nothing else acquires the file" begin
            editor = Editor(PrimitiveString("x"), IdentityProjection(); backend = HeadlessBackend(),
                            devices = Device[], feeds = Feed[FileChangeFeed()])
            store = get_session_file_change_store(; editor)
            (path, file) = _make_watched_text_file("one\n")
            # A holder of the view alone, as the navigator of an explorer is.
            view = make_file_view(file)
            evaluate_operation(editor, AcquireDocumentOperation(view))
            @test is_document_held(editor, file)
            @test only(store.files).receiver === file
            evaluate_operation(editor, ReleaseDocumentOperation(view))
            @test !is_document_held(editor, file)
            @test !is_document_file_watched(file; store)
        end

        @testset "a tab and a card show one file, each with a view of its own" begin
            folder = mktempdir()
            path = joinpath(folder, "shared.txt")
            write(path, "one\n")
            dashboard = Dashboard("Study")
            editor = build_editor(dashboard, NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0));
                                  backend = HeadlessBackend(), devices = Device[], window = false, tabs = true,
                                  appearance = false, settings = Settings(), file_change = true)
            run_frame!(editor)
            store = get_session_file_change_store(; editor)
            evaluate_operation(editor, AcquireDocumentOperation(dashboard))
            tab = open_file!(path; editor)
            run_frame!(editor)
            file = find_open_file_document(path; editor)
            tab_view = get_document(tab).content
            @test file isa FileDocument && tab_view isa FileView && tab_view.file === file
            cards = ReferencedDocument(dashboard.cards, annotate_reference_types(
                editor.document, extend_reference(strip_reference_types(find_document_path(editor.document, dashboard)),
                                                  FieldReferenceStep("cards"))))
            insert_elements!(cards, 1, Any[DashboardCard("Shared", file)]; editor)
            card_view = dashboard.cards[1].content_view.view
            @test card_view isa FileView && card_view !== tab_view && card_view.file === file
            # One file has one watch, and each place has a scroll pane of its own over
            # the one file.
            @test only(store.files).receiver === file
            @test card_view.scroll !== tab_view.scroll
            @test card_view.scroll.content === file && tab_view.scroll.content === file
            tab_view.scroll.scroll_position = Point2D(0, -40)
            @test tab_view.scroll.scroll_position.y[] == -40
            @test card_view.scroll.scroll_position.y[] == 0
            # An open of the file finds the tab that shows it through its view.
            @test get_document(open_file!(path; editor)) === get_document(tab)
            # A rewrite loads the file once, and both views show it.
            shown_children(view) = length(print_document(FileViewToWidget(), nothing, view, nothing).output.children)
            write(path, "two\n")
            @test _wait_for_file_change(store)
            @test drain_file_changes!(; store) == 1
            @test _get_watched_text(file) == "two\n" && get_file_disk_state(file).band === nothing
            @test shown_children(tab_view) == 1 && shown_children(card_view) == 1
            # After an edit the next rewrite shows the band above the file, in both views.
            _edit_watched_text!(file, "mine\n")
            write(path, "three\n")
            @test _wait_for_file_change(store)
            @test drain_file_changes!(; store) == 0
            @test get_file_disk_state(file).band isa FileBand && _get_watched_text(file) == "mine\n"
            @test shown_children(tab_view) == 2 && shown_children(card_view) == 2
        end

        @testset "a tab pane with no explorer shows a file that a program rewrites" begin
            folder = mktempdir()
            path = joinpath(folder, "rewritten.txt")
            write(path, "one\n")
            editor = build_editor(PrimitiveString("x"), NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0));
                                  backend = HeadlessBackend(), devices = Device[], window = false, tabs = true,
                                  appearance = false, settings = Settings(), file_change = true)
            run_frame!(editor)
            store = get_session_file_change_store(; editor)
            tab = open_file!(path; editor)
            run_frame!(editor)
            view = get_document(tab).content
            file = find_open_file_document(path; editor)
            @test view isa FileView && view.file === file
            # The file document is the receiver of the watch, and nothing else is.
            @test only(store.files).receiver === file
            @test get_file_disk_state(file).file_hash == hash("one\n")
            # A rewrite reaches the file, and the tab shows the new text with no band.
            write(path, "two\n")
            @test _wait_for_file_change(store)
            @test drain_file_changes!(; editor) == 1
            run_frame!(editor)
            @test _get_watched_text(file) == "two\n" && get_file_disk_state(file).band === nothing
            @test length(print_document(FileViewToWidget(), nothing, view, nothing).output.children) == 1
            # The person types a letter, and the next rewrite shows the band.
            _edit_watched_text!(file, "two x\n")
            @test has_unsaved_edits(get_file_content(file)) === true
            write(path, "three\n")
            @test _wait_for_file_change(store)
            @test drain_file_changes!(; editor) == 0
            run_frame!(editor)
            @test get_file_disk_state(file).band isa FileBand && _get_watched_text(file) == "two x\n"
            @test length(print_document(FileViewToWidget(), nothing, view, nothing).output.children) == 2
            @test any(condition -> condition.name === :conflict,
                    ProjecturedPlatform.DomainModule.get_document_decoration(file).conditions)
        end

        @testset "two new files get two states of their own" begin
            first_file, second_file = TextFile("first.txt", "a"), TextFile("second.txt", "b")
            @test get_file_disk_state(first_file) isa FileDiskState
            @test get_file_disk_state(first_file) !== get_file_disk_state(second_file)
            get_file_disk_state(first_file).file_hash = hash("a")
            @test get_file_disk_state(second_file).file_hash === nothing
            @test get_file_disk_state(TextFile("third.txt")) !== get_file_disk_state(first_file)
            # The state is view state: a walk does not enter it.
            @test is_view_state_field(typeof(first_file), :disk) && !is_field_walked(first_file, :disk)
        end

        @testset "the wrapper file_change adds a feed, and the end of the loop stops its watchers" begin
            editor = build_editor(PrimitiveString("x"), IdentityProjection(); backend = HeadlessBackend(),
                                  devices = Device[], window = false, tabs = false, appearance = false,
                                  settings = false, file_change = true)
            @test count(feed -> feed isa FileChangeFeed, editor.feeds) == 1
            store = get_session_file_change_store(; editor)
            (path, file) = _make_watched_text_file("one\n")
            evaluate_operation(editor, AcquireDocumentOperation(file))
            @test is_document_file_watched(file; store) && !isempty(store.watchers)
            foreach(step -> step(editor), editor.stop_steps)
            @test isempty(store.watchers) && !is_document_file_watched(file; store)
        end
    end
end
