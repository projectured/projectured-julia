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

# The read that a draw of a file asks for when a change is counted, run to its end with
# no editor: the work reads and parses the file, and the answer is stored.
function _read_file_text!(file)
    ensure_file_text_cell!(file)
    state = get_file_disk_state(file)
    state.read_count > state.loaded_count && wait_for_cell!(state.text.cell; editor = nothing)
    file
end

# Run frames of `editor` until `done()` holds, at most `seconds`.
function _run_frames_until(editor, done; seconds::Real = 30)
    deadline = time() + seconds
    while time() < deadline
        drain_operations!(editor)
        run_frame!(editor)
        done() && return true
        sleep(0.02)
    end
    false
end

# Draw the view as the frame of a window draws it: the print of a view demands the text
# of its file, in the evaluation of the editor.
_draw_file_view(editor, view) =
    run_with_evaluation_editor(editor) do
        length(print_document(FileViewToWidget(), nothing, view, nothing).output.children)
    end

# Whether `file` holds the text of every change that was reported.
_is_file_read(file) = get_file_disk_state(file).loaded_count >= get_file_disk_state(file).read_count

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

# A picture file: a file that a person does not edit, whose text is the size of its
# file. Its read is the work of the background cell of its text, which a draw of the
# picture demands, and the path of each read is noted.
@document struct _ProbePictureFile <: FileDocument
    filename::String
    content::Any
    disk::FileDiskState = FileDiskState()
end
const _PICTURE_READS = String[]
const _PICTURE_READS_LOCK = ReentrantLock()
SerializationModule.get_file_domain(::Type{<:_ProbePictureFile}) = Document
SerializationModule.is_editable_file_type(::Type{<:_ProbePictureFile}) = false
function SerializationModule.read_file_content(::Type{<:_ProbePictureFile}, path::AbstractString)
    lock(() -> push!(_PICTURE_READS, basename(path)), _PICTURE_READS_LOCK)
    PrimitiveString(string(filesize(path), " bytes"))
end
_read_picture_names() = lock(() -> sort!(unique(_PICTURE_READS)), _PICTURE_READS_LOCK)

# A page that shows pictures: one path in each line of its file. A person edits it.
@document struct _ProbePage <: Document
    names::Any = String[]
end
@document struct _ProbePageFile <: FileDocument
    filename::String
    content::Any
    disk::FileDiskState = FileDiskState()
end
SerializationModule.get_file_domain(::Type{<:_ProbePageFile}) = Document
SerializationModule.parse_file_content(::Type{<:_ProbePageFile}, text::AbstractString) =
    _ProbePage(; names = String[line for line in split(text, '\n') if !isempty(line)])
SerializationModule.emit_text(file::_ProbePageFile) = join(get_wrapped_document(get_file_content(file)).names, "\n") * "\n"
FileFormatModule.collect_shown_file_paths(page::_ProbePage) = String[name for name in page.names]

# The page draws each picture as a line in a scroll pane of a fixed height, whose list of
# rows builds only the rows that show, as the grid of a dashboard does. The line of a
# picture asks the file of its path of the context, and demands the text of that file.
# The pane and the files that the lines found are kept for the test to look at.
struct _ProbePageToWidget <: Projection end
const _PROBE_PAGE_PANE = Ref{Any}(nothing)
const _PROBE_PAGE_FOUND = Dict{String,Any}()
const _PROBE_PAGE_HEIGHT = 48

function _make_probe_page_line(path::String, context)
    line = WidgetLabel("")
    set_cell_computation!(getfield(line, :content), () -> begin
        picture = find_shown_file(context, path)
        picture === nothing && return string(path, ": no file")
        _PROBE_PAGE_FOUND[path] = picture
        demand_file_text(picture)
        content = get_wrapped_document(get_file_content(picture))
        string(path, ": ", content isa PrimitiveString ? content.value : "not read")
    end)
    line
end

function _make_probe_page_rows(names, context)
    function make_node(k)
        node = ListNode(Any[_make_probe_page_line(String(names[k]), context)])
        set_cell_computation!(getfield(node, :next), () -> begin
            k < length(names) || return nothing
            following = make_node(k + 1)
            set_cell_value!(getfield(following, :prev), node)
            following
        end)
        node
    end
    make_node(1)
end

function ProjectionModule.print_document(p::_ProbePageToWidget, recursion, page::_ProbePage, context)
    grid = GridLayout(_make_probe_page_rows(page.names, context), 1; column_policies = Any[Fixed(240)])
    pane = WidgetScrollPane(grid; size = Point2D(240, _PROBE_PAGE_HEIGHT), grows = (width = false, height = false))
    _PROBE_PAGE_PANE[] = pane
    SimpleIoMap(p, page, VerticalLayout(Any[pane]))
end
ProjectionModule.map_reference_forward(::_ProbePageToWidget, iomap, reference) =
    reference isa EmptyReference ? reference : nothing
ProjectionModule.map_reference_backward(::_ProbePageToWidget, iomap, reference) =
    reference isa EmptyReference ? reference : nothing
WidgetModule.make_graphics_projection(::Type{_ProbePage}; measure, appearance) =
    ChainingProjection(_ProbePageToWidget(), VerticalLayoutToGraphicsCanvas())

# What a painter reads: the content of each graphic that the clip of the window shows. A
# canvas whose elements follow the vertical axis ends its walk at the first element past the
# bottom edge, and skips an element above the top edge, as the renderer of a backend does, so
# a row below the screen is never read. The texts that it reads are answered in order.
function _paint_texts!(found, canvas, ox::Int, oy::Int, top::Int, bottom::Int)
    x, y = ox + Int(canvas.x), oy + Int(canvas.y)
    follows_axis = canvas.layout == layout_vertical
    for element in canvas.elements
        element = element isa Cell ? element[] : element
        element isa ListNode && (element = element.value)
        element = element isa Cell ? element[] : element
        if element isa GraphicsText
            push!(found, String(element.text))
        elseif element isa GraphicsCanvas
            child_top = y + Int(element.y)
            follows_axis && child_top >= bottom && break
            follows_axis && Int(element.h) > 0 && child_top + Int(element.h) <= top && continue
            _paint_texts!(found, element, x, y, top, bottom)
        elseif element isa GraphicsViewport
            viewport_top, viewport_bottom = y + Int(element.y), y + Int(element.y) + Int(element.h)
            max(top, viewport_top) < min(bottom, viewport_bottom) || continue
            _paint_texts!(found, element.content, x + Int(element.x) + round(Int, element.transform.e),
                          viewport_top + round(Int, element.transform.f), max(top, viewport_top),
                          min(bottom, viewport_bottom))
        end
    end
    found
end

# A backend that paints only what the clip shows, as the window of an application does. The
# headless backend reads every part of a frame, so it can not tell the rows that show from the
# rows that do not.
mutable struct _ClippedBackend <: Backend
    rendered::Vector{Any}
    events::Vector{Any}
    _ClippedBackend() = new(Any[], Any[])
end
BackendModule.initialize_backend!(::_ClippedBackend) = nothing
BackendModule.quit_backend!(::_ClippedBackend) = nothing
BackendModule.write_to_devices!(backend::_ClippedBackend, devices, document) =
    (push!(backend.rendered, document);
     _paint_texts!(String[], document, 0, 0, typemin(Int) ÷ 2, typemax(Int) ÷ 2); nothing)
BackendModule.take_from_devices!(backend::_ClippedBackend, devices) =
    isempty(backend.events) ? nothing : popfirst!(backend.events)
BackendModule.find_system_colors(::_ClippedBackend) = nothing

# Wait until the store holds a change, for at most `seconds`.
# The watcher has taken the last stamp of each watched file, so a further event of the
# same write marks nothing.
function _wait_for_file_change(store::FileChangeStore; seconds::Real = 10.0)
    deadline = time() + seconds
    while time() < deadline
        if lock(() -> !isempty(store.changed) &&
                      all(w -> w.stamp == compute_file_stamp(w.path), store.files), store.lock)
            return true
        end
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
            # The watch read nothing: the file counts the change, and reads the file when a
            # view of it is drawn.
            @test get_file_disk_state(file).read_count == 1 && _get_watched_text(file) == "one\n"
            _read_file_text!(file)
            @test _get_watched_text(file) == "two\n"
            @test get_file_disk_state(file).file_hash == hash("two\n") && get_file_disk_state(file).band === nothing
            # A file written at once, by a rename over it, is seen too.
            temporary = joinpath(dirname(path), "watched.tmp")
            write(temporary, "three\n")
            mv(temporary, path; force = true)
            @test _wait_for_file_change(store)
            @test drain_file_changes!(; store) == 1
            _read_file_text!(file)
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
            # The write of the save counts as a change, and the read finds the hash of the
            # file: nothing changes and nothing is logged.
            @test (@test_logs drain_file_changes!(; store)) == 1
            @test (@test_logs _read_file_text!(file)) === file
            @test _get_watched_text(file) == "saved\n" && get_file_disk_state(file).band === nothing
            @test get_file_disk_state(file).file_hash == hash("saved\n") && _is_file_read(file)
            # After the save, a change of another program reaches it again.
            write(path, "theirs\n")
            @test _wait_for_file_change(store)
            @test drain_file_changes!(; store) == 1
            _read_file_text!(file)
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
            @test (@test_logs drain_file_changes!(; store)) == 1
            _read_file_text!(file)
            @test _get_watched_text(file) == "mine\n"
            @test get_file_disk_state(file).band.message == "watched.txt changed on disk."
            @test _get_band_labels(file) == ["Load it", "Keep mine"]
            # The same time and size is no change.
            get_file_disk_state(file).band = nothing
            FileChangeModule._mark_changed_files!(store, dirname(path))
            @test isempty(store.changed) && drain_file_changes!(; store) == 0
            @test get_file_disk_state(file).band === nothing
            # Keep mine: the file takes the file on disk as its own, so a save writes.
            write(path, "theirs again\n")
            @test _wait_for_file_change(store)
            @test drain_file_changes!(; store) == 1
            _read_file_text!(file)
            keep = _find_band_choice(file, "Keep mine")
            @test keep isa KeepFileEditsOperation
            evaluate_operation(nothing, keep)
            @test get_file_disk_state(file).band === nothing && get_file_disk_state(file).file_hash == hash("theirs again\n")
            # A report of text that the file knows already changes nothing and logs nothing.
            lock(() -> push!(store.changed, abspath(path)), store.lock)
            @test drain_file_changes!(; store) == 1
            @test (@test_logs _read_file_text!(file)) === file
            @test get_file_disk_state(file).band === nothing && _get_watched_text(file) == "mine\n"
            @test evaluate_operation(nothing, SaveFileOperation(file)) === true
            @test read(path, String) == "mine\n"
            # Load it: the file takes the document that the read found.
            @test _wait_for_file_change(store)
            @test drain_file_changes!(; store) == 1
            @test (@test_logs _read_file_text!(file)) === file
            @test get_file_disk_state(file).band === nothing
            _edit_watched_text!(file, "mine again\n")
            write(path, "last\n")
            @test _wait_for_file_change(store)
            @test drain_file_changes!(; store) == 1
            _read_file_text!(file)
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
            @test drain_file_changes!(; store) == 1
            _read_file_text!(file)
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
            _read_file_text!(file)
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
            _read_file_text!(file)
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
            _read_file_text!(file)
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
            # The watch and the drain read nothing; the file reads by its own type.
            @test isempty(lock(() -> copy(_READ_ONLY_PROBE_READERS), _READ_ONLY_PROBE_LOCK))
            @test getfield(get_file_content(file), :value)[] == "5 bytes"
            _read_file_text!(file)
            @test getfield(get_file_content(file), :value)[] == "10 bytes"
            @test !isempty(lock(() -> copy(_READ_ONLY_PROBE_READERS), _READ_ONLY_PROBE_LOCK))
            # The same time and size is no change.
            FileChangeModule._mark_changed_files!(store, dirname(path))
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
            _read_file_text!(file)
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
            @test _run_frames_until(editor, () -> _is_file_read(file))
            @test _get_watched_text(file) == "two\n" && get_file_disk_state(file).band === nothing
            @test shown_children(tab_view) == 1 && shown_children(card_view) == 1
            # After an edit the next rewrite shows the band above the file, in both views.
            _edit_watched_text!(file, "mine\n")
            write(path, "three\n")
            @test _wait_for_file_change(store)
            @test drain_file_changes!(; store) == 1
            @test _run_frames_until(editor, () -> _is_file_read(file))
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
            # A draw of the view demands the text, and a task reads the file after the frame.
            _draw_file_view(editor, view)
            @test _run_frames_until(editor, () -> _is_file_read(file))
            @test _get_watched_text(file) == "two\n" && get_file_disk_state(file).band === nothing
            @test length(print_document(FileViewToWidget(), nothing, view, nothing).output.children) == 1
            # The person types a letter, and the next rewrite shows the band.
            _edit_watched_text!(file, "two x\n")
            @test has_unsaved_edits(get_file_content(file)) === true
            write(path, "three\n")
            @test _wait_for_file_change(store)
            @test drain_file_changes!(; editor) == 1
            _draw_file_view(editor, view)
            @test _run_frames_until(editor, () -> _is_file_read(file))
            @test get_file_disk_state(file).band isa FileBand && _get_watched_text(file) == "two x\n"
            @test length(print_document(FileViewToWidget(), nothing, view, nothing).output.children) == 2
            @test any(condition -> condition.name === :conflict,
                    ProjecturedPlatform.DomainModule.get_document_decoration(file).conditions)
        end

        @testset "a file that is released and held again reads the change at its next draw" begin
            path = joinpath(mktempdir(), "shared.txt")
            write(path, "one\n")
            file = make_file_tab(path, UndoBuffer)
            view = make_file_view(file)
            editor = build_editor(view, NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0));
                                  backend = HeadlessBackend(), devices = Device[], window = false, tabs = false,
                                  appearance = false, settings = false, file_change = true)
            store = get_session_file_change_store(; editor)
            state = get_file_disk_state(file)
            run_frame!(editor)
            evaluate_operation(editor, AcquireDocumentOperation(view))
            # A file that was read when it was made asks for no read when it is drawn.
            _run_frames_until(editor, () -> false; seconds = 0.5)
            @test state.read_count == 0 && isempty(get_background_work_store(editor).records)
            evaluate_operation(editor, ReleaseDocumentOperation(view))
            @test !is_document_file_watched(file; store)
            write(path, "two\n")
            # The file changed while no one held it, so it counts the change when it is
            # held again, and reads it when it is drawn.
            evaluate_operation(editor, AcquireDocumentOperation(view))
            @test state.read_count == 1 && state.loaded_count == 0 && _get_watched_text(file) == "one\n"
            @test _run_frames_until(editor, () -> state.loaded_count == 1)
            @test _get_watched_text(file) == "two\n" && state.file_hash == hash("two\n")
            @test any(record -> record.description == "the text of a file", get_background_work_store(editor).records)
            evaluate_operation(editor, ReleaseDocumentOperation(view))
        end

        @testset "a file that a dashboard holds and nothing draws reads nothing until a view of it is drawn" begin
            folder = mktempdir()
            files = FileDocument[]
            for k in 1:40
                path = joinpath(folder, "page$k.txt")
                write(path, "one $k\n")
                push!(files, make_file_tab(path, UndoBuffer))
            end
            dashboard = Dashboard("Study", Any[DashboardCard("Page $k", files[k]) for k in 1:40])
            # The root of the editor shows no card, as the part of a dashboard below the
            # screen shows none: the cards are held and not drawn.
            editor = build_editor(PrimitiveString("x"), NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0));
                                  backend = HeadlessBackend(), devices = Device[], window = false, tabs = false,
                                  appearance = false, settings = false, file_change = true)
            store = get_session_file_change_store(; editor)
            run_frame!(editor)
            evaluate_operation(editor, AcquireDocumentOperation(dashboard))
            @test all(file -> is_document_file_watched(file; store), files)
            for k in 1:40
                write(joinpath(folder, "page$k.txt"), "two $k\n")
            end
            deadline = time() + 20.0
            taken = 0
            while taken < 40 && time() < deadline
                taken += drain_file_changes!(; editor, store)
                sleep(0.05)
            end
            @test all(file -> get_file_disk_state(file).read_count == 1, files)
            _run_frames_until(editor, () -> false; seconds = 1.0)
            @test isempty(get_background_work_store(editor).records)
            @test all(k -> _get_watched_text(files[k]) == "one $k\n", 1:40)
            # A draw of the views of two cards reads those two files, and no other.
            for k in (3, 17)
                _draw_file_view(editor, dashboard.cards[k].content_view.view)
            end
            @test _run_frames_until(editor, () -> _is_file_read(files[3]) && _is_file_read(files[17]))
            @test _get_watched_text(files[3]) == "two 3\n" && _get_watched_text(files[17]) == "two 17\n"
            @test count(_is_file_read, files) == 2
            @test all(k -> _get_watched_text(files[k]) == "one $k\n", setdiff(1:40, (3, 17)))
            evaluate_operation(editor, ReleaseDocumentOperation(dashboard))
        end

        @testset "a file that is not read yet refuses a save, and reads at its first draw" begin
            path = joinpath(mktempdir(), "later.txt")
            write(path, "on disk\n")
            file = make_unread_file(path, UndoBuffer)
            state = get_file_disk_state(file)
            @test state.loaded_count < 0 && state.file_hash === nothing && _get_watched_text(file) == ""
            @test evaluate_operation(nothing, SaveFileOperation(file)) === false
            @test read(path, String) == "on disk\n"
            view = make_file_view(file)
            editor = build_editor(view, NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0));
                                  backend = HeadlessBackend(), devices = Device[], window = false, tabs = false,
                                  appearance = false, settings = false, file_change = true)
            run_frame!(editor)
            evaluate_operation(editor, AcquireDocumentOperation(view))
            @test _run_frames_until(editor, () -> state.loaded_count >= 0)
            @test _get_watched_text(file) == "on disk\n" && state.file_hash == hash("on disk\n")
            _edit_watched_text!(file, "mine\n")
            @test evaluate_operation(nothing, SaveFileOperation(file)) === true
            @test read(path, String) == "mine\n"
            evaluate_operation(editor, ReleaseDocumentOperation(view))
        end

        @testset "a reload of a holder gives each file(…) the file document of the editor, and reads no held file" begin
            root = mktempdir()
            try
                paths = Dict(name => joinpath(root, name) for name in ("a.txt", "b.txt", "h.pred"))
                write(paths["a.txt"], "a on disk\n")
                write(paths["b.txt"], "b on disk\n")
                make_card(title, name) = DashboardCard(title, TextFile(name, "x"))
                @test save_file!(PredFile(paths["h.pred"], Dashboard("one", Any[make_card("A", "a.txt")])), root)
                holder = make_file_tab(paths["h.pred"], UndoBuffer)
                view = make_file_view(holder)
                editor = build_editor(view, NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0));
                                      backend = HeadlessBackend(), devices = Device[], window = false, tabs = false,
                                      appearance = false, settings = false, file_change = true)
                store = get_session_file_change_store(; editor)
                run_frame!(editor)
                get_dashboard() = get_wrapped_document(get_file_content(holder))
                is_leaf(node) = node isa SerializationModule.PredReference
                find_leaves() = search_documents(get_dashboard(), is_leaf)
                # The first load is an open of the editor.
                evaluate_operation(editor, ReloadFileOperation(holder))
                evaluate_operation(editor, AcquireDocumentOperation(view))
                a_file = get_dashboard().cards[1].content
                @test a_file isa TextFile && get_file_disk_state(a_file).loaded_count < 0 && isempty(find_leaves())
                @test find_open_file_document(paths["a.txt"]; editor) === a_file
                # Another program rewrites the holder: another title, the held path of before and a new one.
                @test save_file!(PredFile(paths["h.pred"], Dashboard("two", Any[make_card("A", "a.txt"),
                                                                              make_card("B", "b.txt")])), root)
                @test _wait_for_file_change(store)
                @test drain_file_changes!(; editor) == 1
                _draw_file_view(editor, view)
                @test _run_frames_until(editor, () -> _is_file_read(holder))
                @test get_dashboard().title == "two" && length(get_dashboard().cards) == 2
                @test get_dashboard().cards[1].content === a_file
                b_file = get_dashboard().cards[2].content
                @test b_file isa TextFile && get_filename(b_file) == paths["b.txt"]
                @test get_file_disk_state(b_file).loaded_count < 0 && isempty(find_leaves())
                @test find_open_file_document(paths["b.txt"]; editor) === b_file
                # The reload read no held file.
                @test isempty(filter(record -> occursin("b.txt", string(record)), get_background_work_store(editor).records))
                @test get_file_disk_state(b_file).read_count == 0
                # @broken: a load writes the content of a file with no hold, so no holder holds the new file document and its file is not watched; G4 open question 10
                @test_broken is_document_held(editor, b_file) && is_document_file_watched(b_file; store)
                # F5 gives the same.
                @test save_file!(PredFile(paths["h.pred"], Dashboard("three", Any[make_card("B", "b.txt"),
                                                                                make_card("A", "a.txt")])), root)
                evaluate_operation(editor, ReloadFileOperation(holder))
                @test get_dashboard().title == "three" && isempty(find_leaves())
                @test get_dashboard().cards[1].content === b_file && get_dashboard().cards[2].content === a_file
                evaluate_operation(editor, ReleaseDocumentOperation(view))
                # With no editor, a reload keeps each reference.
                alone = make_file_tab(paths["h.pred"], UndoBuffer)
                evaluate_operation(nothing, ReloadFileOperation(alone))
                @test all(card -> is_leaf(card.content), get_wrapped_document(get_file_content(alone)).cards)
            finally
                rm(root; recursive = true, force = true)
            end
        end

        @testset "two files that hold each other get each other's file document" begin
            root = mktempdir()
            try
                first_path, second_path = joinpath(root, "first.pred"), joinpath(root, "second.pred")
                first_dashboard, second_dashboard = Dashboard("first", Any[]), Dashboard("second", Any[])
                first_file, second_file = PredFile(first_path, first_dashboard), PredFile(second_path, second_dashboard)
                push!(first_dashboard.cards, DashboardCard("to second", second_file))
                push!(second_dashboard.cards, DashboardCard("to first", first_file))
                @test save_file!(first_file, root) && save_file!(second_file, root)
                tab_file = make_file_tab(first_path, UndoBuffer)
                view = make_file_view(tab_file)
                # The window shows neither file: a cycle of files that hold each other has no end to print.
                editor = build_editor(PrimitiveString("x"), NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0));
                                      backend = HeadlessBackend(), devices = Device[], window = false, tabs = false,
                                      appearance = false, settings = false, file_change = true)
                run_frame!(editor)
                evaluate_operation(editor, ReloadFileOperation(tab_file))
                evaluate_operation(editor, AcquireDocumentOperation(view))
                # The open of the first reads the first only.
                held_second = get_wrapped_document(get_file_content(tab_file)).cards[1].content
                @test held_second isa PredFile && get_file_disk_state(held_second).loaded_count < 0
                # A view draws the card of the second, and its read gives the slot of the first the tab.
                second_view = make_file_view(held_second)
                evaluate_operation(editor, AcquireDocumentOperation(second_view))
                _draw_file_view(editor, second_view)
                @test _run_frames_until(editor, () -> _is_file_read(held_second))
                @test get_wrapped_document(get_file_content(held_second)).cards[1].content === tab_file
                evaluate_operation(editor, ReleaseDocumentOperation(second_view))
                evaluate_operation(editor, ReleaseDocumentOperation(view))
            finally
                rm(root; recursive = true, force = true)
            end
        end

        @testset "a load keeps the selection where it can, and makes the editor no fault" begin
            folder = mktempdir()
            path = joinpath(folder, "work.pred")
            card(title) = DashboardCard(title, PrimitiveString(title))
            @test save_file!(PredFile(path, Dashboard("work", Any[card("one"), card("two"), card("three")])), folder)
            file = make_file_tab(path, UndoBuffer)
            view = make_file_view(file)
            editor = build_editor(view, NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0));
                                  backend = HeadlessBackend(), devices = Device[], window = false, tabs = false,
                                  appearance = false, settings = false, file_change = true)
            store = get_session_file_change_store(; editor)
            run_frame!(editor)
            evaluate_operation(editor, AcquireDocumentOperation(view))
            get_dashboard() = get_wrapped_document(get_file_content(file))
            # The caret is in the third card.
            caret = extend_reference(find_document_path(editor.document, get_dashboard().cards[3]),
                                     FieldReferenceStep("title"), PositionReferenceStep(2))
            replace_selection!(editor.document, annotate_reference_types(editor.document, caret))
            run_frame!(editor)
            before = length(get_session_fault_log(; editor).entries)
            length_before = length(get_reference_steps(strip_reference_types(get_selection(editor.document))))
            # The file loses two cards.
            @test save_file!(PredFile(path, Dashboard("work", Any[card("one")])), folder)
            deadline = time() + 10.0
            while get_file_disk_state(file).read_count == 0 && time() < deadline
                drain_file_changes!(; editor, store)
                sleep(0.05)
            end
            _draw_file_view(editor, view)
            @test _run_frames_until(editor, () -> _is_file_read(file))
            @test length(get_dashboard().cards) == 1
            selection = get_selection(editor.document)
            @test is_valid_reference(editor.document, selection)
            @test length(get_reference_steps(strip_reference_types(selection))) < length_before
            run_frame!(editor)
            @test length(get_session_fault_log(; editor).entries) == before
            # A selection that the new document still has stays where it is.
            keep = annotate_reference_types(editor.document, extend_reference(
                find_document_path(editor.document, get_dashboard().cards[1]),
                FieldReferenceStep("title"), PositionReferenceStep(1)))
            replace_selection!(editor.document, keep)
            evaluate_operation(editor, ReloadFileOperation(file))
            @test string(strip_reference_types(get_selection(editor.document))) == string(strip_reference_types(keep))
            evaluate_operation(editor, ReleaseDocumentOperation(view))
        end

        @testset "a page keeps the editor's one file document of each picture that it shows, and a picture is read where it is drawn" begin
            # The registry is a table of the running process, so the types register when the test runs.
            register_file_document_type!(".probepic", _ProbePictureFile)
            register_file_document_type!(".probepage", _ProbePageFile)
            folder = mktempdir()
            try
                picture_paths = [joinpath(folder, "p$k.probepic") for k in 1:60]
                for (k, path) in enumerate(picture_paths)
                    write(path, "x"^k)
                end
                page_path = joinpath(folder, "page.probepage")
                write(page_path, join(("p$k.probepic" for k in 1:60), "\n") * "\n")
                page = make_file_tab(page_path, UndoBuffer)
                view = make_file_view(page)
                editor = build_editor(view, NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0));
                                      backend = _ClippedBackend(), devices = Device[], window = false, tabs = false,
                                      appearance = false, settings = Settings(), file_change = true)
                store = get_session_file_change_store(; editor)
                state = get_file_disk_state(page)
                read_names() = _read_picture_names()
                # A tab shows the picture p30, which the page shows below its screen.
                tab_picture = open_file_document!(picture_paths[30]; editor)
                tab_view = make_file_view(tab_picture)
                evaluate_operation(editor, AcquireDocumentOperation(tab_view))
                # The first load of the page is an open of the editor.
                @test isempty(state.shown_files)
                evaluate_operation(editor, ReloadFileOperation(page))
                evaluate_operation(editor, AcquireDocumentOperation(view))
                @test length(state.shown_files) == 60
                @test state.shown_files["p30.probepic"] === tab_picture
                @test find_open_file_document(picture_paths[2]; editor) === state.shown_files["p2.probepic"]
                # The page holds the file of each picture, and each watches its file.
                @test all(picture -> is_document_held(editor, picture) && is_document_file_watched(picture; store),
                          values(state.shown_files))
                @test count(file -> file.receiver === tab_picture, store.files) == 1
                # A page of 60 pictures with 3 on the screen reads 3 pictures.
                lock(() -> empty!(_PICTURE_READS), _PICTURE_READS_LOCK)
                @test _run_frames_until(editor, () -> length(read_names()) >= 3)
                _run_frames_until(editor, () -> false; seconds = 1.0)
                @test read_names() == ["p1.probepic", "p2.probepic", "p3.probepic"]
                @test all(name -> _is_file_read(state.shown_files[name]), ("p1.probepic", "p2.probepic", "p3.probepic"))
                @test get_file_disk_state(state.shown_files["p4.probepic"]).loaded_count < 0
                # A rewrite of a picture on the screen reads that picture again, and no other.
                write(picture_paths[2], "y"^70)
                @test _wait_for_file_change(store)
                @test drain_file_changes!(; editor) == 1
                lock(() -> empty!(_PICTURE_READS), _PICTURE_READS_LOCK)
                @test _run_frames_until(editor, () -> !isempty(read_names()))
                _run_frames_until(editor, () -> false; seconds = 1.0)
                @test read_names() == ["p2.probepic"]
                @test get_wrapped_document(get_file_content(state.shown_files["p2.probepic"])).value == "70 bytes"
                # A rewrite of a picture below the screen counts a change and reads nothing.
                write(picture_paths[10], "y"^70)
                @test _wait_for_file_change(store)
                @test drain_file_changes!(; editor) == 1
                lock(() -> empty!(_PICTURE_READS), _PICTURE_READS_LOCK)
                _run_frames_until(editor, () -> false; seconds = 1.0)
                @test isempty(read_names()) && get_file_disk_state(state.shown_files["p10.probepic"]).read_count == 1
                # A scroll reads the pictures that come on the screen, and no others.
                _PROBE_PAGE_PANE[].scroll_position = Point2D(0, 16 * 20)
                @test _run_frames_until(editor, () -> "p23.probepic" in read_names())
                _run_frames_until(editor, () -> false; seconds = 1.0)
                # The pane reaches the offset along the rows that it has built, so the frames of the
                # scroll draw the rows between, and no row below the new screen.
                @test all(name -> name in read_names(), ("p21.probepic", "p22.probepic", "p23.probepic"))
                @test !any(k -> "p$k.probepic" in read_names(), 24:60)
                # A reload that changes the paths changes `shown_files` and the holds, and the print follows.
                write(joinpath(folder, "q1.probepic"), "q")
                before = copy(state.shown_files)
                write(page_path, "q1.probepic\np1.probepic\np2.probepic\n")
                @test _wait_for_file_change(store)
                @test drain_file_changes!(; editor) == 1
                @test _run_frames_until(editor, () -> length(state.shown_files) == 3)
                @test sort(collect(keys(state.shown_files))) == ["p1.probepic", "p2.probepic", "q1.probepic"]
                @test state.shown_files["p1.probepic"] === before["p1.probepic"]
                @test state.shown_files["p2.probepic"] === before["p2.probepic"]
                added = state.shown_files["q1.probepic"]
                @test is_document_held(editor, added) && is_document_file_watched(added; store)
                @test !is_document_held(editor, before["p3.probepic"]) && !is_document_file_watched(before["p3.probepic"]; store)
                # The picture p30 stays watched for the tab that shows it.
                @test is_document_file_watched(tab_picture; store)
                @test _run_frames_until(editor, () -> get(_PROBE_PAGE_FOUND, "q1.probepic", nothing) === added)
                @test _run_frames_until(editor, () -> "q1.probepic" in read_names())
                # The release of the page stops the watch of each picture that no other holder holds.
                evaluate_operation(editor, ReleaseDocumentOperation(view))
                @test !is_document_file_watched(added; store) && !is_document_file_watched(before["p1.probepic"]; store)
                @test is_document_file_watched(tab_picture; store)
                @test count(file -> file.receiver isa _ProbePictureFile, store.files) == 1
                evaluate_operation(editor, ReleaseDocumentOperation(tab_view))
                @test !is_document_file_watched(tab_picture; store)
            finally
                rm(folder; recursive = true, force = true)
            end
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
