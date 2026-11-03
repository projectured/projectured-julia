# The command palette: the list of the commands that work here, and the decorator
# that opens it. The palette is the running twin of the gesture-help window — both
# read one collected set of bindings as GestureRows — and it opens in the context
# menu window, as a list that a person types into.

# Four rows covering every case the palette distinguishes: a row that can run and
# has a gesture, one that can run with no gesture, one from a deeper stage, and one
# that cannot run right now. A row carries the operation it would apply; `nothing`
# is the whole of "cannot run".
_op() = DoNothingOperation()
_palette_rows() = [
    GestureRow("Ctrl+C", "Copy the selection", "JsonObject",   _op()),
    GestureRow("",       "Sort the entries",   "JsonObject",   _op()),
    GestureRow("Left",   "Move left",          "TextDocument", _op()),
    GestureRow("n",      "Replace with null",  "JsonDocument", nothing),
]

_palette_labels(list, query) = [choice.label for choice in list.find(query)]

function test_command_palette()
@testset "the list of the command palette" begin
    list = make_command_palette_list(_palette_rows())

    @testset "an empty query lists every row that can run, in its order" begin
        @test _palette_labels(list, "") == ["Copy the selection", "Sort the entries", "Move left"]
    end

    @testset "a query matches by its letters in order, of any case" begin
        @test _palette_labels(list, "sort") == ["Sort the entries"]
        @test _palette_labels(list, "SORT") == ["Sort the entries"]
        @test _palette_labels(list, "srt") == ["Sort the entries"]
        @test _palette_labels(list, "mvlft") == ["Move left"]
        @test _palette_labels(list, "zzz") == []
    end

    @testset "a row that can not run now is not in the list" begin
        @test _palette_labels(list, "null") == []
    end

    @testset "the domain matches too, and a match in the description ranks first" begin
        @test Set(_palette_labels(list, "json")) == Set(["Copy the selection", "Sort the entries"])
        # "text" is the domain of one row and words of none.
        @test _palette_labels(list, "textdoc") == ["Move left"]
        # "e" starts "entries" in the description of one row, and only the domain
        # of the others.
        @test first(_palette_labels(list, "entr")) == "Sort the entries"
    end

    @testset "a row shows its key, and its choice answers its operation" begin
        copy = only(list.find("copy"))
        @test copy.note == "Ctrl+C"
        @test only(list.find("sort")).note === nothing
        @test list.choose(copy.value) === copy.value.operation
    end
end
end

# A minimal stand-in for the Editor that the operation evaluators mutate.
mutable struct _PaletteEditor
    document::Any
    iomap::Any
end

# The list that an answer opens, or `nothing`.
function _palette_list(answer)
    answer isa ReplaceViewStateOperation || return nothing
    opened = answer.operation
    opened isa OpenContextMenuOperation || return nothing
    only(opened.layers)[2]
end

function test_command_palette_decorator()
@testset "CommandPaletteDecoratorProjection" begin
    none    = ModifierKeys()
    summon  = KeyDown(:p, ModifierKeys(ctrl=true, shift=true); time = 0.0)
    enter   = KeyPress('\n'; time = 0.0)

    # The real JSON pipeline, down to graphics.
    mkarr() = (a = JsonArray([JsonNumber(1)]); set_selection!(a, EmptyReference()); a)
    mkpalette() = CommandPaletteDecoratorProjection(inner = make_json_projection_example())

    @testset "the summoning gesture opens the list at the top of the window" begin
        p = mkpalette()
        iomap = print_document(p, mkarr())
        answer = read_intent(p, iomap, summon)
        list = _palette_list(answer)
        @test list isa WidgetChoiceList
        @test list.prompt == "Command"
        @test answer.operation.placement === make_shell_top_placement
    end

    @testset "a ToggleCommandPaletteOperation with a route does what the key does" begin
        p = mkpalette()
        iomap = print_document(p, mkarr())
        # A command sends the operation to the first element, and it comes back up
        # to the decorator as the answer of the inner reader.
        route = extend_reference(EmptyReference(), FieldReferenceStep("elements"), ElementReferenceStep(1))
        answer = read_intent(p, nothing, Intent(nothing, ToggleCommandPaletteOperation(), "", "", route),
                             iomap).operation
        @test _palette_list(answer) isa WidgetChoiceList
    end

    @testset "the rows are the context, and they carry their operations" begin
        p = mkpalette()
        iomap = print_document(p, mkarr())
        list = _palette_list(read_intent(p, iomap, summon))
        rows = [choice.value for choice in list.find("")]
        # The whole chain contributes rows, so there are more than the array's own.
        @test any(row -> row.description == "Insert a new element", rows)
        @test length(unique(row.domain for row in rows)) > 1
        # Every row of the list can run: it carries a built operation.
        @test all(row -> row.operation isa Operation, rows)
        # A row that needs its keystroke to carry an argument is not in the list.
        @test !any(row -> row.description == "Replace with a number", rows)
    end

    @testset "every other gesture goes to the content, as without the palette" begin
        p = mkpalette()
        arr = mkarr()
        iomap = print_document(p, arr)
        key = KeyPress('1'; time = 0.0)
        @test typeof(read_intent(p, iomap, key)) == typeof(read_intent(p.inner, iomap.inner_iomap, key))
    end

    @testset "a reference maps as it maps in the content" begin
        p = mkpalette()
        arr = mkarr()
        iomap = print_document(p, arr)
        reference = @reference(arr, elements[1])
        @test map_reference_forward(p, iomap, reference) ==
              map_reference_forward(p.inner, iomap.inner_iomap, reference)
        @test get_iomap_output(iomap) === get_iomap_output(iomap.inner_iomap)
    end

    @testset "the help window sees exactly what it saw without the palette" begin
        p = mkpalette()
        iomap = print_document(p, mkarr())
        ask(proj, io) = begin
            answer = read_intent(proj, nothing, Intent(CollectIntents()), io)
            [(i.domain, i.description) for i in (answer isa Intent ? answer.operation : answer).intents]
        end
        mine  = ask(p, iomap)
        inner = ask(p.inner, iomap.inner_iomap)
        @test mine == inner
        @test !isempty(mine)
    end

    # Through the real gallery pipeline, with the context menu window around the
    # screen: the list opens in a window of its own, the keys go to it, and Return
    # runs the command where the decorator stands.
    @testset "a command runs through the real editor pipeline" begin
        arr = mkarr()
        editor = ProjecturedExample._make_window_scene_editor(
            Any[arr], Any[make_command_palette_decorator_projection(make_json_projection_example())],
            ["json"]; width = 600, height = 400, backend = HeadlessBackend(),
            compose = (projections, _) -> ProjecturedExample._multi_window_projection(projections))
        screen = get_wrapped_document(editor.document)
        send!(event) = (push_event!(editor.backend, WindowInput(:json, event)); run_frame!(editor))
        send!(summon)
        popups = [window for window in screen.windows if window.style === :popup]
        @test length(popups) == 1
        list = only(popups).content
        @test list isa WidgetChoiceList
        for c in "insert"
            send!(KeyPress(c; time = 0.0))
        end
        @test list.query == "insert"
        send!(enter)
        @test isempty([window for window in screen.windows if window.style === :popup])
        @test length(arr.elements) == 2
    end

    # A document wrapper puts the domain document one level down. Asking the
    # reader reaches through it, because the reader roots what it returns.
    @testset "a wrapped document's commands still run, from inside the wrapper" begin
        json = make_json_document_example()
        doc  = make_clipboard_document(json)
        inner_json = doc.content
        set_selection!(doc, EmptyReference())
        set_selection!(inner_json, EmptyReference())
        p = CommandPaletteDecoratorProjection(inner = make_clipboard_projection(make_json_projection_example()))
        iomap = print_document(p, doc)
        list = _palette_list(read_intent(p, iomap, summon))
        rows = [choice.value for choice in list.find("")]
        # Both the wrapper's own commands and the wrapped document's are offered.
        @test any(row -> row.domain == "clipboard", rows)
        @test any(row -> row.domain == "JsonObject", rows)
        row = first(list.find("insert a new entry")).value
        @test row.description == "Insert a new entry"
        @test row.domain == "JsonObject"
        before = length(inner_json.entries)
        operation = list.choose(row)
        @test operation isa Operation
        # The operation is rooted at the ClipboardSlice, so applying it there reaches
        # the JSON document inside.
        evaluate_operation(_PaletteEditor(doc, iomap), operation)
        @test length(inner_json.entries) == before + 1
    end

    @testset "a domain rule with no gesture is reached only by name" begin
        obj = JsonObject("a" => JsonNumber(1))
        bindings = collect_document_gesture_bindings(JsonObject)
        commands = [b for b in bindings if b.pattern === nothing]
        @test sort([b.name for b in commands]) ==
              ["Move from value to key", "Sort the entries by key"]

        # Tab moves the cursor from the key to the value; the command moves it back.
        set_selection!(obj, @reference(obj, entries[1].key{0}))
        forward = read_gesture(obj, KeyPress('\t'; time = 0.0))
        @test forward isa ReplaceSelectionOperation
        set_selection!(obj, forward.path)
        back = fire_named_gesture_binding(bindings, obj, "Move from value to key";
                                          selection = obj.selection)
        @test back isa ReplaceSelectionOperation
        @test occursin("key", string(back.path))

        # XML has the same gap, filled the same way.
        xml_command = only(b for b in collect_document_gesture_bindings(XmlElement)
                           if b.pattern === nothing)
        @test xml_command.name == "Move to attribute name"
    end

end
end

export test_command_palette, test_command_palette_decorator
