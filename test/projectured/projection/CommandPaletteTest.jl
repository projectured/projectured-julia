# The command palette: the match, the selection, and the rendering. The palette is
# the running twin of the gesture-help window — both read one collected set of
# bindings and display it as GestureRows.

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

_palette(query = "") = CommandPalette(query, _palette_rows(), nothing)

function test_command_palette()
@testset "CommandPalette" begin

    @testset "an empty query matches every row, the runnable ones first" begin
        p = _palette()
        @test get_command_palette_matches(p) == [1, 2, 3, 4]
    end

    @testset "every word of the query must appear, contiguously" begin
        @test get_command_palette_matches(_palette("sort")) == [2]
        @test get_command_palette_matches(_palette("SORT")) == [2]
        # Words may arrive in any order, and need not be adjacent in the text — so a
        # user types the two words they remember, not the sentence between them.
        @test get_command_palette_matches(_palette("entries sort")) == [2]
        @test get_command_palette_matches(_palette("copy")) == [1]
        # Letters with gaps do NOT match. A subsequence rule made "sort" find
        # "Select the root node" and most of the JSON replace commands, which is a
        # ranking, not a filter.
        @test get_command_palette_matches(_palette("srt")) == []
        @test get_command_palette_matches(_palette("zzz")) == []
        # The domain is searchable too, so a group can be narrowed to by name. The
        # order inside is by where the match falls, which is a detail; that all three
        # JSON rows survive and the text row does not is the point.
        @test Set(get_command_palette_matches(_palette("json"))) == Set([1, 2, 4])
    end

    @testset "the selection names a row, and survives a narrower query" begin
        p = _palette()
        p.selection = build_command_palette_selection(2)
        @test get_command_palette_selected(p) == 2
        @test get_command_palette_row(p).description == "Sort the entries"
        # A query the chosen row still matches keeps it.
        p.query = "sort"
        @test get_command_palette_settled_selection(p) == build_command_palette_selection(2)
        # A query it does not match moves to the first match.
        p.query = "copy"
        @test get_command_palette_settled_selection(p) == build_command_palette_selection(1)
        # No match at all leaves nothing selected.
        p.query = "zzz"
        @test get_command_palette_settled_selection(p) === nothing
    end

    @testset "no selection reads as row 0" begin
        p = _palette()
        @test get_command_palette_selected(p) == 0
        @test get_command_palette_row(p) === nothing
        @test build_command_palette_selection(0) === nothing
    end

    @testset "a step walks the matching subset and stops at both ends" begin
        p = _palette()
        # Nothing selected: forward lands on the first match, backward on the last.
        @test compute_command_palette_step(p, 1) == build_command_palette_selection(1)
        @test compute_command_palette_step(p, -1) == build_command_palette_selection(4)
        p.selection = build_command_palette_selection(1)
        @test compute_command_palette_step(p, 1) == build_command_palette_selection(2)
        @test compute_command_palette_step(p, -1) == build_command_palette_selection(1)   # clamped
        p.selection = build_command_palette_selection(4)                          # the last match
        @test compute_command_palette_step(p, 1) == build_command_palette_selection(4)    # clamped
        p.query = "zzz"
        @test compute_command_palette_step(p, 1) === nothing
    end

    @testset "matches are grouped by domain, best group first" begin
        p = _palette()
        # Rows of one domain sit together: the domain of each row, in match order,
        # never returns to a domain it has left.
        domains = [p.rows[i].domain for i in get_command_palette_matches(p)]
        @test length(unique(domains)) == length([d for (k, d) in enumerate(domains)
                                                 if k == 1 || d != domains[k-1]])
        # A group sits where its own best row would have sat, so the row that would
        # have led a flat list still leads. The match runs over "<domain>
        # <description>", so pick domains that contribute no letters: "alpha" starts
        # later in Zz's text than in Ww's, and Ww's group leads even though Zz's row
        # is collected first.
        two = CommandPalette("alpha", [
            GestureRow("", "qq alpha", "Zz", _op()),
            GestureRow("", "alpha",    "Ww", _op())], nothing)
        @test [two.rows[i].domain for i in get_command_palette_matches(two)] == ["Ww", "Zz"]
    end

    @testset "the rendering heads each group with its domain" begin
        p = _palette()
        p.selection = build_command_palette_selection(2)
        text = render(print_document(CommandPaletteToSyntax(), p).output)
        # One heading per domain, above its rows.
        @test occursin("  JsonObject\n", text)
        @test occursin("  TextDocument\n", text)
        @test occursin("  JsonDocument\n", text)
        # A heading appears once, not per row.
        @test count(l -> l == "  JsonObject", split(text, "\n")) == 1
        # The rows themselves no longer repeat the domain.
        @test !occursin("JsonObject Copy", text)
    end

    @testset "the palette renders the query, the marker, and the gesture" begin
        p = _palette()
        p.selection = build_command_palette_selection(2)
        text = render(print_document(CommandPaletteToSyntax(), p).output)
        @test occursin("> ▏", text)                              # the type-in line
        @test occursin("▸ Sort the entries", text)               # the chosen row
        @test occursin("  Copy the selection   [Ctrl+C]", text)  # its key, for learning it
        @test occursin("(not now)", text)                        # the row that cannot run
        @test !occursin("Sort the entries   [", text)            # no gesture, no brackets
    end

    @testset "the rendering re-derives as the user types" begin
        p = _palette()
        output = print_document(CommandPaletteToSyntax(), p).output
        @test occursin("Copy the selection", render(output))
        # The same output tree, after a keystroke: a captured list would freeze here.
        p.query = "sort"
        text = render(output)
        @test occursin("> sort▏", text)
        @test occursin("Sort the entries", text)
        @test !occursin("Copy the selection", text)
        p.query = "zzz"
        @test occursin("no command matches", render(output))
    end

end
end

# A minimal stand-in for the Editor that the operation evaluators mutate.
mutable struct _PaletteEditor
    document::Any
    iomap::Any
end

function test_command_palette_decorator()
@testset "CommandPaletteDecoratorProjection" begin
    none    = ModifierKeys()
    summon  = KeyDown(:p, ModifierKeys(ctrl=true, shift=true))
    enter   = KeyDown(:return, none)
    escape  = KeyDown(:escape, none)

    # The real JSON pipeline, down to graphics — the decorator draws over graphics.
    mkarr() = (a = JsonArray([JsonNumber(1)]); set_selection!(a, EmptyReference()); a)
    mkpalette(state) = CommandPaletteDecoratorProjection(inner = make_json_projection_example(),
                                                measure = truetype_measure_text, state = state)

    @testset "the summoning gesture opens the palette and toggles it shut" begin
        state = CommandPaletteState()
        p = mkpalette(state)
        iomap = print_document(p, mkarr())
        @test !state.open[]
        @test read_intent(p, iomap, summon) isa DoNothingOperation
        @test state.open[]
        # The same key dismisses it, as F1 dismisses the help window.
        @test read_intent(p, iomap, summon) isa DoNothingOperation
        @test !state.open[]
    end

    @testset "the rows are the context, and they carry their operations" begin
        state = CommandPaletteState()
        p = mkpalette(state)
        iomap = print_document(p, mkarr())
        read_intent(p, iomap, summon)
        rows = state.palette.rows
        # The whole chain contributes rows, so there are more than the array's nine.
        @test length(rows) > 9
        @test any(r -> r.description == "Insert a new element", rows)
        # Rows come from every stage, not only the document the decorator wraps.
        @test length(unique(r.domain for r in rows)) > 1
        # A row that can run carries a built operation — that is the whole of being
        # runnable, and it holds for a deeper stage's row as much as the document's.
        insert = only(r for r in rows if r.description == "Insert a new element")
        @test insert.operation isa Operation
        # A row that needs its keystroke to carry an argument cannot be run.
        number = only(r for r in rows if r.description == "Replace with a number")
        @test number.operation === nothing
    end

    @testset "keys build the query and never reach the content" begin
        state = CommandPaletteState()
        p = mkpalette(state)
        arr = mkarr()
        iomap = print_document(p, arr)
        read_intent(p, iomap, summon)
        for c in "insert"
            @test read_intent(p, iomap, KeyPress(c)) isa DoNothingOperation
        end
        @test state.palette.query == "insert"
        @test get_command_palette_row(state.palette).description == "Insert a new element"
        # A comma inserts an element in JSON. While the palette is open it is a
        # character of the query, and the array is untouched.
        @test read_intent(p, iomap, KeyPress(',')) isa DoNothingOperation
        @test length(arr.elements) == 1
        @test state.palette.query == "insert,"
    end

    @testset "Backspace and the arrows move inside the palette" begin
        state = CommandPaletteState()
        p = mkpalette(state)
        iomap = print_document(p, mkarr())
        read_intent(p, iomap, summon)
        for c in "insert"; read_intent(p, iomap, KeyPress(c)); end
        read_intent(p, iomap, KeyDown(:backspace, none))
        @test state.palette.query == "inser"
        # Back to an empty query, so more than one row matches and a step can move.
        for _ in 1:5; read_intent(p, iomap, KeyDown(:backspace, none)); end
        @test state.palette.query == ""
        # Compare the selection, not the row: two rows can hold equal values.
        first_at = get_command_palette_selected(state.palette)
        read_intent(p, iomap, KeyDown(:down, none))
        @test get_command_palette_selected(state.palette) != first_at
        read_intent(p, iomap, KeyDown(:up, none))
        @test get_command_palette_selected(state.palette) == first_at
    end

    @testset "Enter runs the command against the document and closes" begin
        state = CommandPaletteState()
        p = mkpalette(state)
        arr = mkarr()
        iomap = print_document(p, arr)
        read_intent(p, iomap, summon)
        for c in "insert"; read_intent(p, iomap, KeyPress(c)); end
        operation = read_intent(p, iomap, enter)
        @test operation isa Operation
        @test !(operation isa DoNothingOperation)
        @test !state.open[]
        # The operation is expressed against the array, so it applies to it.
        evaluate_operation(_PaletteEditor(arr, nothing), operation)
        @test length(arr.elements) == 2
    end

    @testset "Escape closes the palette and runs nothing" begin
        state = CommandPaletteState()
        p = mkpalette(state)
        arr = mkarr()
        iomap = print_document(p, arr)
        read_intent(p, iomap, summon)
        for c in "insert"; read_intent(p, iomap, KeyPress(c)); end
        @test read_intent(p, iomap, escape) isa DoNothingOperation
        @test !state.open[]
        @test length(arr.elements) == 1
    end

    @testset "a closed palette lets every gesture through" begin
        state = CommandPaletteState()
        p = mkpalette(state)
        arr = mkarr()
        iomap = print_document(p, arr)
        # A comma reaches JSON and inserts an element, as it does without the palette.
        operation = read_intent(p, iomap, KeyPress(','))
        @test operation isa Operation
        @test !state.open[]
    end

    @testset "the wrapper is there open or closed, with the content first" begin
        state = CommandPaletteState()
        p = mkpalette(state)
        iomap = print_document(p, mkarr())
        @test iomap.output isa GraphicsCanvas
        @test length(iomap.output.elements) == 1
        @test iomap.output.elements[1] === iomap.inner_iomap.output
        read_intent(p, iomap, summon)
        # The same output tree now carries the palette as a second element.
        @test length(iomap.output.elements) == 2
        @test iomap.output.elements[1] === iomap.inner_iomap.output
        read_intent(p, iomap, escape)
        @test length(iomap.output.elements) == 1
    end

    # The palette draws OVER the document, so without a panel behind it neither can
    # be read. Nothing else here would notice: the element count is the same either
    # way, and only the pixels tell.
    @testset "the open palette sits on a panel, sized to its text" begin
        state = CommandPaletteState()
        p = mkpalette(state)
        iomap = print_document(p, mkarr())
        read_intent(p, iomap, summon)
        panel = iomap.output.elements[2].elements[1]
        content = iomap.palette_iomap.output
        @test panel isa GraphicsRect
        @test panel.w == content.w + 2 * PALETTE_PADDING
        @test panel.h == content.h + 2 * PALETTE_PADDING
        @test panel.w > 0 && panel.h > 0        # the text measured for real
        tall = panel.h
        # The panel follows the list: a query that narrows it makes the panel shorter.
        for c in "insert"; read_intent(p, iomap, KeyPress(c)); end
        @test iomap.output.elements[2].elements[1].h < tall
    end

    @testset "a mapped reference gains, and gives up, the wrapper step" begin
        state = CommandPaletteState()
        p = mkpalette(state)
        arr = mkarr()
        iomap = print_document(p, arr)
        forward = map_reference_forward(p, iomap, arr.selection)
        inner = map_reference_forward(p.inner, iomap.inner_iomap, arr.selection)
        if inner !== nothing
            @test forward.head == FieldReferenceStep("elements")
            @test forward.tail.head == ElementReferenceStep(1)
            @test forward.tail.tail == inner
            @test map_reference_backward(p, iomap, forward) ==
                  map_reference_backward(p.inner, iomap.inner_iomap, inner)
        end
        # A reference that does not name the content maps back to nothing.
        @test map_reference_backward(p, iomap, EmptyReference()) === nothing
    end

    @testset "the help window sees exactly what it saw without the palette" begin
        state = CommandPaletteState()
        p = mkpalette(state)
        iomap = print_document(p, mkarr())
        ask(proj, io) = begin
            answer = read_intent(proj, nothing, Intent(CollectIntents()), io)
            [(i.domain, i.description) for i in (answer isa Intent ? answer.operation : answer).intents]
        end
        # A closed palette claims nothing, so a collection passes straight through.
        mine  = ask(p, iomap)
        inner = ask(p.inner, iomap.inner_iomap)
        @test mine == inner
        @test !isempty(mine)
    end

    # Through the real editor pipeline (`_multi_window_projection`), so the operation
    # travels the whole reader chain and `ScreenToScreen` reroots it to the screen
    # root. This is what a palette window could not do.
    @testset "a command runs through the real editor pipeline" begin
        arr = mkarr()
        # Wrapped exactly as `run_example(...; command_palette=true)` wraps it.
        composed = ProjecturedExample._multi_window_projection(
            [make_command_palette_decorator_projection(make_json_projection_example())])
        screen = ScreenDocument([WindowDocument(; id = :json, content = arr)])
        iomap = print_document(composed, screen)

        @test read_intent(composed, iomap, WindowInput(:json, summon)) isa DoNothingOperation
        for c in "insert"
            read_intent(composed, iomap, WindowInput(:json, KeyPress(c)))
        end
        operation = read_intent(composed, iomap, WindowInput(:json, enter))
        @test operation isa Operation
        # The path is rooted at the screen, so applying it reaches the array inside
        # the window.
        evaluate_operation(_PaletteEditor(screen, iomap), operation)
        @test length(arr.elements) == 2
    end

    # The case that forced this design. A document wrapper (clipboard, workbench,
    # shell, scrolling, dragging) puts the domain document one level down. Reaching
    # into a flat binding list could not run anything through it; asking the reader
    # can, because the reader roots what it returns.
    @testset "a wrapped document's commands still run, from inside the wrapper" begin
        json = make_json_document_example()
        doc  = make_clipboard_document(json)
        inner_json = doc.content
        set_selection!(doc, EmptyReference())
        set_selection!(inner_json, EmptyReference())
        p = CommandPaletteDecoratorProjection(inner = make_clipboard_projection(make_json_projection_example()),
                                     measure = truetype_measure_text)
        iomap = print_document(p, doc)
        read_intent(p, iomap, summon)
        rows = p.state.palette.rows
        # Both the wrapper's own commands and the wrapped document's are offered.
        @test any(r -> r.domain == "clipboard", rows)
        @test any(r -> r.domain == "JsonObject", rows)
        @test count(r -> r.operation !== nothing, rows) > 0

        for c in "insert a new entry"
            read_intent(p, iomap, KeyPress(c))
        end
        row = get_command_palette_row(p.state.palette)
        @test row.description == "Insert a new entry"
        @test row.domain == "JsonObject"
        before = length(inner_json.entries)
        operation = read_intent(p, iomap, enter)
        @test operation isa Operation
        # The operation is rooted at the ClipboardSlice, so applying it there reaches
        # the JSON document inside.
        evaluate_operation(_PaletteEditor(doc, iomap), operation)
        @test length(inner_json.entries) == before + 1
    end

    @testset "a domain rule with no gesture is reached only by name" begin
        obj = JsonObject("a" => JsonNumber(1))
        bindings = get_document_gesture_bindings(JsonObject)
        commands = [b for b in bindings if b.pattern === nothing]
        @test sort([b.name for b in commands]) ==
              ["Move from value to key", "Sort the entries by key"]

        # Tab moves the cursor from the key to the value; the command moves it back.
        set_selection!(obj, @reference(obj, entries[1].key{0}))
        forward = read_gesture(obj, KeyDown(:tab, none))
        @test forward isa ReplaceSelectionOperation
        set_selection!(obj, forward.path)
        back = fire_named_gesture_binding(bindings, obj, obj.selection, "Move from value to key")
        @test back isa ReplaceSelectionOperation
        @test occursin("key", string(back.path))

        # XML has the same gap, filled the same way.
        xml_command = only(b for b in get_document_gesture_bindings(XmlElement) if b.pattern === nothing)
        @test xml_command.name == "Move to attribute name"
    end

end
end

export test_command_palette, test_command_palette_decorator
