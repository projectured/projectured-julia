# The keys of the clipboard in the window of the application, through the loop of
# an editor with the gesture tracker, as a person presses them: a click, Shift and
# an arrow, a drag, an Alt+click, Ctrl+C, Ctrl+X, Ctrl+V, Delete and Ctrl+Z. Each
# case reads what the window draws and what the file holds. The system clipboard
# is an in-memory stand-in.

const _CE_NONE = ModifierKeys()
const _CE_CTRL = ModifierKeys(ctrl = true)
const _CE_SHIFT = ModifierKeys(shift = true)
const _CE_ALT = ModifierKeys(alt = true)

# The time of the next press of the mouse: each one starts a second after the
# last, so two of them never make one double click.
const _CE_TIME = Ref(0.0)

_ce_value(v) = v isa Cell ? _ce_value(v[]) : v
_ce_graphic(v) = (v = _ce_value(v); v isa ListNode ? _ce_graphic(v.value) : v)

# Every text that the window draws, with its place.
function _ce_drawn(node, ox = 0, oy = 0, found = Tuple{String,Int,Int}[])
    node = _ce_graphic(node)
    node === nothing && return found
    x = hasproperty(node, :x) ? ox + Int(_ce_value(node.x)) : ox
    y = hasproperty(node, :y) ? oy + Int(_ce_value(node.y)) : oy
    if hasproperty(node, :text) && _ce_value(node.text) isa AbstractString
        push!(found, (String(_ce_value(node.text)), x, y))
    elseif hasproperty(node, :elements)
        foreach(element -> _ce_drawn(element, x, y, found), _ce_value(node.elements))
    elseif node isa GraphicsViewport
        _ce_drawn(node.content, x + round(Int, node.transform.e), y + round(Int, node.transform.f), found)
    elseif hasproperty(node, :content)
        _ce_drawn(node.content, x, y, found)
    end
    found
end

_ce_drawn(w::NamedTuple) = _ce_drawn(last(rendered_output(w.backend)).windows[1].content)
_ce_texts(w) = first.(_ce_drawn(w))

# The first drawn text for which `found` holds, with its place.
function _ce_find(w, found)
    drawn = _ce_drawn(w)
    i = findfirst(t -> found(t[1]), drawn)
    i === nothing && error("no drawn text matches; the window draws " * join(unique(first.(drawn)), " | "))
    drawn[i]
end

function _ce_press!(w, event)
    push_event!(w.backend, WindowInput(:W, event))
    run_frame!(w.editor)
    drain_operations!(w.editor)
    run_frame!(w.editor)
end

_ce_key!(w, key, modifiers = _CE_NONE) = _ce_press!(w, KeyDown(key, modifiers; time = 0.0))

function _ce_click!(w, (_, x, y); dx = 2, dy = 8, modifiers = _CE_NONE)
    time = (_CE_TIME[] += 1.0)
    _ce_press!(w, MouseDown(:left, x + dx, y + dy, modifiers; time))
    _ce_press!(w, MouseUp(:left, x + dx, y + dy, modifiers; time = time + 0.02))
end

# A press at `x`, a move with the button held to `x + width`, and the release.
function _ce_drag!(w, (_, x, y), width)
    time = (_CE_TIME[] += 1.0)
    _ce_press!(w, MouseDown(:left, x + 1, y + 8, _CE_NONE; time))
    for k in 1:4
        _ce_press!(w, MouseMove(x + 1 + width * k ÷ 4, y + 8, MouseButtons(:left), _CE_NONE;
                                time = time + 0.05k))
    end
    _ce_press!(w, MouseUp(:left, x + 1 + width, y + 8, _CE_NONE; time = time + 0.3))
end

# The window of the application over `paths`, in an editor with the gesture
# tracker, as the application has it.
function _ce_window(paths, root; assistant = nothing)
    document, projection = make_application_window(paths; root, assistant)
    scene = make_window_scene(document, "W"; width = 1400, height = 900)
    tracked, tracking = make_tracking_screen(scene, make_window_scene_projection(projection))
    backend = HeadlessBackend()
    editor = Editor(tracked, tracking; backend, devices = Device[Keyboard(), Mouse()])
    run_frame!(editor)
    (; editor, backend, scene)
end

# The window over the file `name` of `dir`, with the tab of the file in front.
function _ce_file_window(dir, name)
    w = _ce_window([joinpath(dir, name)], dir)
    _ce_click!(w, _ce_find(w, ==(name)); dx = 4, dy = 6)
    w
end

# The file that the tab shows: the selection up to its `file` step.
function _ce_file(w)
    steps = collect(get_reference_steps(strip_reference_types(get_selection(w.scene))))
    at = findlast(==(FieldReferenceStep("file")), steps)
    evaluate_reference(w.scene, extend_reference(EmptyReference(), steps[1:at]...))
end

_ce_text(file) = print_natural_text(file.content.content)

# A click before the start of the drawn text that holds `word`, and `count`
# Shift+Right, which select its first `count` characters.
function _ce_select!(w, word; count = 2)
    _ce_click!(w, _ce_find(w, text -> occursin(word, text)))
    foreach(_ -> _ce_key!(w, :right, _CE_SHIFT), 1:count)
end

_ce_select_whole!(w, found) = _ce_click!(w, _ce_find(w, found); dx = 3, dy = 6, modifiers = _CE_ALT)

function test_clipboard_edits()
@testset "the keys of the clipboard in the window of the application" begin
    buffer = Ref("")
    set_os_clipboard_backend!(read = () -> buffer[], write = text -> (buffer[] = String(text); true))
    dir = mktempdir()
    try
        write_document_file(parse_natural_text(:json, "{\"name\": \"Alice\", \"city\": \"Paris\", \"list\": [11, 22, 33]}"),
                            joinpath(dir, "a.json"))
        write_document_file(parse_natural_text(:yaml, "name: Alice\ncity: Paris\n"), joinpath(dir, "a.yaml"))
        write_document_file(parse_natural_text(:md, "# Title\n\nSome text here.\n"), joinpath(dir, "a.md"))
        write_document_file(PrimitiveString("one two three"), joinpath(dir, "notes.txt"))
        entry(w, k) = _ce_file(w).content.content.entries[k]

        @testset "a cut of a range takes it out, and Ctrl+Z puts it back" begin
            w = _ce_file_window(dir, "a.json")
            _ce_select!(w, "Alice")
            buffer[] = ""
            _ce_key!(w, :x, _CE_CTRL)
            @test "ice" in _ce_texts(w) && !("Alice" in _ce_texts(w))
            @test read_os_clipboard() == "Al"
            _ce_key!(w, :z, _CE_CTRL)
            @test "Alice" in _ce_texts(w)
        end

        @testset "a cut of a range made by a drag takes it out" begin
            w = _ce_file_window(dir, "a.json")
            alice = _ce_find(w, ==("Alice"))
            _ce_click!(w, alice)
            _ce_drag!(w, alice, 29)
            buffer[] = ""
            _ce_key!(w, :x, _CE_CTRL)
            cut = read_os_clipboard()
            @test !isempty(cut) && startswith("Alice", cut)
            @test "Alice"[(length(cut) + 1):end] in _ce_texts(w)
        end

        @testset "a paste of text at a caret is one step that Ctrl+Z takes back" begin
            w = _ce_file_window(dir, "a.json")
            _ce_click!(w, _ce_find(w, ==("Alice")))
            buffer[] = "ZZ"
            _ce_key!(w, :v, _CE_CTRL)
            @test "ZZAlice" in _ce_texts(w)
            _ce_key!(w, :z, _CE_CTRL)
            @test "Alice" in _ce_texts(w)
        end

        @testset "a cut of an element takes it out of its list, and Ctrl+Z puts it back" begin
            w = _ce_file_window(dir, "a.json")
            _ce_select_whole!(w, ==("22"))
            buffer[] = ""
            _ce_key!(w, :x, _CE_CTRL)
            @test !("22" in _ce_texts(w))
            @test length(entry(w, 3).value.elements) == 2
            @test read_os_clipboard() == "22"
            _ce_key!(w, :z, _CE_CTRL)
            @test "22" in _ce_texts(w)
        end

        @testset "Delete on an element takes it out, and copies nothing" begin
            w = _ce_file_window(dir, "a.json")
            _ce_select_whole!(w, ==("22"))
            buffer[] = "kept"
            _ce_key!(w, :delete)
            @test !("22" in _ce_texts(w))
            @test read_os_clipboard() == "kept"
            _ce_key!(w, :z, _CE_CTRL)
            @test "22" in _ce_texts(w)
        end

        @testset "a cut of a value leaves the empty document of its domain" begin
            for name in ("a.json", "a.yaml")
                w = _ce_file_window(dir, name)
                _ce_select_whole!(w, text -> occursin("Alice", text))
                _ce_key!(w, :x, _CE_CTRL)
                file = _ce_file(w)
                @test !occursin("Alice", _ce_text(file))
                _ce_key!(w, :z, _CE_CTRL)
                @test occursin("Alice", _ce_text(file))
            end
        end

        @testset "a text pasted into a hole becomes the insertion of its domain" begin
            w = _ce_file_window(dir, "a.json")
            _ce_select!(w, "Paris")
            _ce_key!(w, :c, _CE_CTRL)
            _ce_select_whole!(w, ==("Alice"))
            _ce_key!(w, :delete)
            _ce_key!(w, :v, _CE_CTRL)
            value = entry(w, 1).value
            @test nameof(typeof(value)) == :JsonInsertion
            @test value.value == "Pa"
        end

        @testset "a cut of a run of Markdown takes it out of its paragraph" begin
            w = _ce_file_window(dir, "a.md")
            _ce_select_whole!(w, ==("Some text here."))
            _ce_key!(w, :x, _CE_CTRL)
            @test !("Some text here." in _ce_texts(w))
            _ce_key!(w, :z, _CE_CTRL)
            @test "Some text here." in _ce_texts(w)
        end

        @testset "a copy of an object writes its text, and a paste at a caret types it" begin
            w = _ce_file_window(dir, "a.json")
            _ce_select_whole!(w, ==("Alice"))
            buffer[] = "older"
            _ce_key!(w, :c, _CE_CTRL)
            @test read_os_clipboard() == "\"Alice\""
            _ce_click!(w, _ce_find(w, ==("Paris")))
            _ce_key!(w, :v, _CE_CTRL)
            @test entry(w, 2).value.value == "\"Alice\"Paris"
        end

        @testset "a text pasted on a whole string is typed over its value" begin
            w = _ce_file_window(dir, "a.json")
            _ce_select!(w, "Alice")
            _ce_key!(w, :c, _CE_CTRL)
            _ce_select_whole!(w, ==("Paris"))
            _ce_key!(w, :v, _CE_CTRL)
            @test entry(w, 2).value.value == "Al"
            @test "Al" in _ce_texts(w)
            _ce_key!(w, :z, _CE_CTRL)
            @test "Paris" in _ce_texts(w)
            # A list has no value of its own, so it takes no text.
            _ce_select_whole!(w, ==("11"))
            _ce_key!(w, :up, _CE_ALT)
            _ce_key!(w, :v, _CE_CTRL)
            @test length(entry(w, 3).value.elements) == 3
        end

        @testset "a cut of a range in a plain text file takes it out" begin
            w = _ce_file_window(dir, "notes.txt")
            _ce_select!(w, "one two three")
            _ce_key!(w, :x, _CE_CTRL)
            @test "e two three" in _ce_texts(w)
            _ce_key!(w, :z, _CE_CTRL)
            @test "one two three" in _ce_texts(w)
        end

        @testset "a cut of a range in the draft of an assistant takes it out" begin
            assistant = Assistant(; llm = FakeLlm("ok"))
            w = _ce_window([joinpath(dir, "a.json")], dir; assistant)
            draft = assistant.draft
            where = first(search_references(w.editor.document, node -> node === draft;
                walk = DocumentWalk(; descend = (parent, child) -> !(parent isa UndoBuffer && child isa CellVector))))
            evaluate_operation(w.editor, ReplaceSelectionOperation(
                concat_references(where, make_draft_caret_reference(draft))))
            run_frame!(w.editor)
            foreach(c -> _ce_press!(w, KeyPress(c; time = 0.0)), "hello world")
            # With the keys.
            foreach(_ -> _ce_key!(w, :left, _CE_SHIFT), 1:5)
            buffer[] = ""
            _ce_key!(w, :x, _CE_CTRL)
            @test "hello " in _ce_texts(w)
            @test read_os_clipboard() == "world"
            # With a drag of the mouse from the start of "hello".
            hello = _ce_find(w, ==("hello "))
            _ce_drag!(w, hello, 29)
            buffer[] = ""
            _ce_key!(w, :x, _CE_CTRL)
            cut = read_os_clipboard()
            @test !isempty(cut) && startswith("hello", cut)
            @test "hello "[(length(cut) + 1):end] in _ce_texts(w)
        end
    finally
        reset_os_clipboard_backend!()
        rm(dir; recursive = true, force = true)
    end
end
end

export test_clipboard_edits
