# The history holds the edits a person makes, and nothing else: a gesture that
# only changes what the window shows adds no step. Two sweeps say so. The first
# presses such gestures in the application window and asks both histories, the
# window's and the file's. The second moves the pointer and turns the wheel over
# every example, and asks the history's own filter about each answer.

using Test

# What a history records of the answers to pointer moves over the whole of
# `example` and a wheel turned in two places: one line for each recorded answer.
# The answers are read and not applied, so each one answers the printed state.
function _history_recorded_answers(example)
    projection = example.projection
    iomap = print_document(projection, example.document)
    output = iomap.output
    output isa GraphicsDocument || return String[]
    width, height = Int.(get_graphics_size(output))
    width, height = clamp(width, 100, 1600), clamp(height, 100, 1200)
    events = Any[MouseMove(x, y; time = 0.0) for x in 5:max(20, width ÷ 20):width
                                  for y in 5:max(20, height ÷ 15):height]
    append!(events, [MouseScroll(0, turn, x, y; time = 0.0) for turn in (-1, 1)
                     for (x, y) in ((width ÷ 2, height ÷ 2), (width ÷ 4, height ÷ 4))])
    recorded = String[]
    for event in events
        change = read_intent(projection, nothing, Intent(event), iomap)
        operation = change isa Intent ? change.operation : change
        operation isa Operation && is_undo_step(event, operation) &&
            push!(recorded, string(nameof(typeof(event)), ": ", describe_operation(operation)))
    end
    recorded
end

function test_history_sweep()
    @testset "a gesture that changes no document adds no step" begin
        @testset "in the application window" begin
            mktempdir() do dir
                for folder in ("alpha", "beta"), k in 1:3
                    mkpath(joinpath(dir, folder))
                    write(joinpath(dir, folder, "f$k.jl"), "x = $k\n")
                end
                json = joinpath(dir, "a.json")
                write_document_file(parse_natural_text(:json, "{\"name\": \"Alice\", \"age\": 30}"), json)
                document, scene, composed, iomap =
                    _app_make_scene([json], dir; assistant = Assistant(; llm = FakeLlm("ok")))
                editor = _app_make_editor(scene, composed, iomap)
                buffers = search_documents(scene, node -> node isa UndoBuffer)
                window = only(buffer for buffer in buffers if buffer.content isa PaneTree)
                file = only(buffer for buffer in buffers if buffer !== window)
                steps() = (length(window.undo_entries), length(file.undo_entries))

                # Where a text is drawn now, within a band of the window: the
                # Files pane is left, the file in the middle, the assistant right.
                drawn() = _app_drawn_at(get_iomap_output(editor.iomap).windows[1].content)
                place(text, band) = first((x, y) for (t, x, y) in drawn() if t == text && x in band)
                none = ModifierKeys()
                alt = ModifierKeys(alt = true)
                click((x, y); modifiers = none) = [MouseDown(:left, x + 3, y + 3, modifiers; time = 0.0),
                                                   MouseUp(:left, x + 3, y + 3, modifiers; time = 0.0),
                                                   MouseClick(:left, x + 3, y + 3, 1, modifiers; time = 0.0)]
                key_downs(names...; modifiers = none) = [KeyDown(name, modifiers; time = 0.0) for name in names]
                left, middle, right = 0:300, 300:1090, 1090:1600

                # The chevron left of a folder's name: one click closes it, the next
                # opens it again.
                fold_twice() = let (x, y) = place("alpha", left)
                    [MouseClick(:left, x - 34, y + 5, 1, none; time = 0.0), MouseClick(:left, x - 34, y + 5, 1, none; time = 0.0)]
                end

                # Each gesture is made when its turn comes, because the one before
                # it can move what it points at.
                gestures = Pair{String,Function}[
                    "the pointer moves over the window" =>
                        () -> [MouseMove(x, y; time = 0.0) for x in 20:120:1580 for y in 20:120:980],
                    "a click on a row of the Files pane" => () -> click(place("alpha", left)),
                    "Down and Up in the Files pane" => () -> key_downs(:down, :up),
                    "Alt+click on a row" => () -> click(place("beta", left); modifiers = alt),
                    "a folder closes and opens" => fold_twice,
                    "the wheel over the Files pane" => () -> [MouseScroll(0, -1, 100, 300; time = 0.0), MouseScroll(0, 1, 100, 300; time = 0.0)],
                    "a click in the file" => () -> click(place("Alice", middle)),
                    "arrow keys in the file" => () -> key_downs(:right, :left, :end, :home),
                    "Shift+Right in the file" => () -> key_downs(:right; modifiers = ModifierKeys(shift = true)),
                    "Alt+Up and Alt+Down in the file" => () -> key_downs(:up, :down; modifiers = alt),
                    "Alt+click in the file" => () -> click(place("Alice", middle); modifiers = alt),
                    "the wheel over the file" => () -> [MouseScroll(0, -1, 700, 300; time = 0.0), MouseScroll(0, 1, 700, 300; time = 0.0)],
                    "a click on the tab title of the Files pane" => () -> click(place("Files", left)),
                    "a click on the tab title of the file" => () -> click(place("a.json", 290:1100)),
                    "a click on the tab title of the assistant" => () -> click(place("Assistant", right)),
                    "Ctrl+Alt+Right" => () -> key_downs(:right; modifiers = ModifierKeys(ctrl = true, alt = true)),
                    "a click in the draft" => () -> click(place("type here…", right)),
                    "Left and Right in the draft" => () -> key_downs(:left, :right),
                    "the wheel over the transcript" => () -> [MouseScroll(0, 1, 1500, 300; time = 0.0), MouseScroll(0, -1, 1500, 300; time = 0.0)],
                    "the File menu opens and Escape closes it" =>
                        () -> vcat(click(place("File", 0:60)), key_downs(:escape)),
                    "F1 twice" => () -> key_downs(:f1, :f1),
                    "the palette opens, takes a letter and closes" =>
                        () -> Any[KeyDown(:p, ModifierKeys(ctrl = true, shift = true); time = 0.0), KeyPress('s'; time = 0.0),
                                  KeyDown(:escape, none; time = 0.0)],
                    "the context menu opens and closes" =>
                        () -> Any[MouseClick(:right, 700, 300, 1, none; time = 0.0), KeyDown(:escape, none; time = 0.0)],
                    "Ctrl+C" => () -> key_downs(:c; modifiers = ModifierKeys(ctrl = true)),
                ]
                for (gesture, make) in gestures
                    before = steps()
                    for event in make()
                        operation = _app_fire(composed, editor.iomap, event)
                        operation isa Operation && _app_apply!(editor, operation)
                    end
                    @test (gesture, steps()) == (gesture, before)
                end
            end
        end

        @testset "over every example" begin
            for example in examples
                @test (example.name, _history_recorded_answers(example)) == (example.name, String[])
            end
        end

        # A run of typing is one step, in the file and in the window's copy of it,
        # so 150 characters leave the step made before them in the window history.
        @testset "a run of typing is one step" begin
            mktempdir() do dir
                json = joinpath(dir, "a.json")
                write_document_file(parse_natural_text(:json, "{\"name\": \"Alice\"}"), json)
                document, scene, composed, iomap =
                    _app_make_scene([json], dir; assistant = Assistant(; llm = FakeLlm("ok")))
                editor = _app_make_editor(scene, composed, iomap)
                buffers = search_documents(scene, node -> node isa UndoBuffer)
                window = only(buffer for buffer in buffers if buffer.content isa PaneTree)
                file = only(buffer for buffer in buffers if buffer !== window)
                steps() = (length(window.undo_entries), length(file.undo_entries))
                press!(event) = begin
                    operation = _app_fire(composed, editor.iomap, event)
                    operation isa Operation && _app_apply!(editor, operation)
                end
                drawn() = _app_drawn_at(get_iomap_output(editor.iomap).windows[1].content)
                click!(matches) = begin
                    (x, y) = first((x, y) for (text, x, y) in drawn() if matches(text, x))
                    press!(MouseClick(:left, x + 3, y + 3, 1, ModifierKeys(); time = 0.0))
                end
                text = first(repeat("typed text ", 14), 150)

                # One character first: the first key compiles, and a compile longer
                # than the pause would end the run.
                click!((t, x) -> occursin("Alice", t) && 300 <= x < 1090)
                press!(KeyPress('x'; time = 0.0))
                # A step of the window alone: a new tab in the Files pane's group.
                click!((t, x) -> t == "Files" && x < 300)
                press!(KeyDown(:t, ModifierKeys(ctrl = true); time = 0.0))
                opened = steps()
                tab = window.undo_entries[end].label

                click!((t, x) -> occursin("lice", t) && 300 <= x < 1090)
                foreach(character -> press!(KeyPress(character; time = 0.0)), text)
                @test steps() == opened .+ (1, 1)
                @test window.undo_entries[end - 1].label == tab

                click!((t, x) -> t == "type here…" && x >= 1090)
                foreach(character -> press!(KeyPress(character; time = 0.0)), text)
                @test steps() == opened .+ (2, 1)
            end
        end
    end
end
