# The terminal: the text that a program writes becomes lines, a prompt with no
# line end shows at once, a line that the person sends reaches the program, the
# exit status arrives, a stop ends the program, and in an editor a click on the
# input line, keys and Return send a line.

# Wait at most ten seconds for `condition`, and answer whether it holds.
_wait_for_terminal(condition) = timedwait(condition, 10.0; pollint = 0.02) === :ok

_terminal_texts(terminal) = [line.text for line in terminal.lines]

# Every text that `node` draws, with the point where it draws it.
function _collect_terminal_texts(node, x = 0, y = 0, found = Tuple{String,Int,Int}[])
    node = node isa AbstractCell ? node[] : node
    if node isa GraphicsCanvas
        x += Int(node.x)
        y += Int(node.y)
        foreach(element -> _collect_terminal_texts(element, x, y, found), node.elements)
    elseif node isa GraphicsViewport
        _collect_terminal_texts(node.content, x + Int(node.x) + round(Int, node.transform.e),
                                y + Int(node.y) + round(Int, node.transform.f), found)
    elseif node isa GraphicsText
        push!(found, (String(node.text), x + Int(node.x), y + Int(node.y)))
    end
    found
end

function test_terminal()
@testset "terminal" begin

@testset "the text of a program becomes lines" begin
    terminal = TerminalDocument(`true`)
    add_terminal_text!(terminal, :output, "one\ntw")
    @test _terminal_texts(terminal) == ["one", "tw"] && terminal.is_line_open
    add_terminal_text!(terminal, :output, "o\n")
    @test _terminal_texts(terminal) == ["one", "two"] && !terminal.is_line_open
    # A prompt stays open, and the standard error starts a line of its own.
    add_terminal_text!(terminal, :output, "Code > ")
    add_terminal_text!(terminal, :error, "warning\n")
    @test _terminal_texts(terminal)[3:4] == ["Code > ", "warning"]
    @test [line.kind for line in terminal.lines][3:4] == [:output, :error]
    # Colours go, a carriage return writes over its line, and a bare line end is
    # an empty line.
    add_terminal_text!(terminal, :output, "\e[1;32mgreen\e[0m\n10%\r50%\r\n\n")
    @test _terminal_texts(terminal)[5:7] == ["green", "50%", ""]
    # A whole line closes the open line.
    add_terminal_text!(terminal, :output, "Name > ")
    add_terminal_line!(terminal, :input, "Ada")
    add_terminal_text!(terminal, :output, "Hello")
    @test _terminal_texts(terminal)[8:10] == ["Name > ", "Ada", "Hello"]
    # The oldest lines go first.
    small = TerminalDocument(`true`; line_capacity = 2)
    add_terminal_text!(small, :output, "a\nb\nc\n")
    @test _terminal_texts(small) == ["b", "c"]
end

@testset "a carriage return and an escape sequence at the end of a read wait for the next" begin
    split = TerminalModule._split_unfinished_text
    @test split("abc\r") == ("abc", "\r")
    @test split("x\e[1;3") == ("x", "\e[1;3")
    @test split("\e[1;32mgreen") == ("\e[1;32mgreen", "")
    @test split("plain") == ("plain", "")
    # The pieces of two reads give what one read gives.
    terminal = TerminalDocument(`true`)
    text, held = split("abc\r")
    add_terminal_text!(terminal, :output, text)
    add_terminal_text!(terminal, :output, held * "\ndef\n")
    @test _terminal_texts(terminal) == ["abc", "def"]
    # A change of the character set is no text either.
    add_terminal_text!(terminal, :output, "\e(Bplain\n")
    @test last(_terminal_texts(terminal)) == "plain"
end

@testset "a character that a read cuts in two waits for its bytes" begin
    bytes = Vector{UInt8}("aé")
    head = bytes[1:2]
    @test TerminalModule._take_whole_characters!(head) == "a"
    @test head == bytes[2:2]
    append!(head, bytes[3:3])
    @test TerminalModule._take_whole_characters!(head) == "é" && isempty(head)
end

@testset "a program prints a prompt, reads a line, writes both streams and ends with its status" begin
    script = raw"""printf 'Code > '; read line; echo "got $line"; echo oops >&2; exit 3"""
    exits = Any[]
    terminal = TerminalDocument(`sh -c $script`; on_exit = (editor, status) -> push!(exits, (editor, status)))
    @test get_document_title(terminal) == "Terminal: sh -c " * script
    start_terminal!(:editor, terminal)
    @test terminal.status === :running && is_terminal_running(terminal)
    # The prompt shows before the program gets a line.
    @test _wait_for_terminal(() -> "Code > " in _terminal_texts(terminal))
    @test send_terminal_input!(terminal, "abc")
    @test _wait_for_terminal(() -> terminal.status === 3)
    @test !is_terminal_running(terminal)
    texts = _terminal_texts(terminal)
    @test texts[1:2] == ["Code > ", "abc"]
    @test "got abc" in texts && "oops" in texts
    @test last(texts) == "The program ended with the status 3."
    @test only(line.kind for line in terminal.lines if line.text == "oops") === :error
    @test exits == [(:editor, 3)]
    # No program runs, so nothing is sent.
    @test !send_terminal_input!(terminal, "late")
end

@testset "a child that the program leaves running does not hold the end" begin
    started = time()
    terminal = TerminalDocument(`sh -c "sleep 6 & echo started; sleep 0.3"`)
    start_terminal!(:editor, terminal)
    @test _wait_for_terminal(() -> terminal.status isa Int)
    @test terminal.status == 0
    @test time() - started < 5
    @test "started" in _terminal_texts(terminal)
    # The child ended with its group.
    @test ccall(:kill, Cint, (Cint, Cint), -terminal.control.group_id, 0) != 0
end

@testset "a stop sends SIGINT to the group, and a program that can not start says so" begin
    terminal = TerminalDocument(`sh -c "sleep 30"`)
    start_terminal!(:editor, terminal)
    stop_terminal!(terminal)
    @test _wait_for_terminal(() -> terminal.status isa Int)
    @test terminal.status == 128 + Int(Base.SIGINT)
    missing = TerminalDocument(`projectured-no-such-program-x`)
    start_terminal!(:editor, missing)
    @test missing.status === :failed
    @test startswith(only(_terminal_texts(missing)), "The program can not start: ")
end

@testset "an undo of a send gives the line back, and a bar beside the input line is no caret" begin
    terminal = TerminalDocument(`true`)
    terminal.input.value = "code"
    inverse = make_inverse_operation(nothing, SendTerminalInputOperation(terminal))
    @test inverse isa ReplaceReferencedValueOperation
    projection = TerminalToWidget()
    iomap = print_document(projection, nothing, terminal, PrinterContext())
    pane(steps...) = Reference(FieldReferenceStep("children"), RangeReferenceStep(2, 3), steps...)
    caret = Reference(FieldReferenceStep("input"), FieldReferenceStep("value"), RangeReferenceStep(4, 4))
    @test map_reference_backward(projection, iomap, pane()) == caret
    @test map_reference_backward(projection, iomap, pane(FieldReferenceStep("content"))) == caret
    @test map_reference_backward(projection, iomap,
                                 pane(FieldReferenceStep("content"), FieldReferenceStep("value"),
                                      RangeReferenceStep(1, 1))) ==
          Reference(FieldReferenceStep("input"), FieldReferenceStep("value"), RangeReferenceStep(1, 1))
    @test map_reference_backward(projection, iomap, pane(FieldReferenceStep("horizontal_scroll_bar"))) != caret
end

@testset "in an editor, a click on the input line, keys and Return send a line" begin
    script = raw"""printf 'Code > '; read line; echo "got $line"; read more"""
    terminal = TerminalDocument(`sh -c $script`)
    backend = HeadlessBackend()
    editor = build_editor(terminal, NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0));
                          backend, devices = ProjecturedKernel.DeviceModule.Device[Keyboard(), Mouse(), Display()],
                          window = false, appearance = false, settings = false, tabs = false,
                          focus_cycling = false)
    start_terminal!(editor, terminal)
    @test _wait_for_terminal(() -> (run_frame!(editor); "Code > " in _terminal_texts(terminal)))
    drawn = _collect_terminal_texts(last(rendered_output(backend)))
    @test any(entry -> entry[1] == "Code > ", drawn)
    @test any(entry -> occursin("running", entry[1]), drawn)
    # The input line is below the pane of the lines, whose first line is the
    # prompt: a press there puts the caret in it.
    _, x, y = only(entry for entry in drawn if entry[1] == "Code > ")
    input_y = y + TerminalToWidget().lines_height + 10
    push_event!(backend, MouseClick(:left, x + 2, input_y, 1, ModifierKeys(); time = 0.0))
    run_frame!(editor)
    for character in "xy"
        push_event!(backend, KeyPress(character, string(character), ModifierKeys(); time = 0.0))
        run_frame!(editor)
    end
    @test terminal.input.value == "xy"
    push_event!(backend, KeyDown(:return, ModifierKeys(); time = 0.0))
    run_frame!(editor)
    @test terminal.input.value == ""
    @test _wait_for_terminal(() -> (run_frame!(editor); "got xy" in _terminal_texts(terminal)))
    @test "xy" in _terminal_texts(terminal)
    # The caret stays in the input line, so the next line goes the same way.
    push_event!(backend, KeyPress('z', "z", ModifierKeys(); time = 0.0))
    run_frame!(editor)
    @test terminal.input.value == "z"
    stop_terminal!(terminal)
    @test _wait_for_terminal(() -> (run_frame!(editor); terminal.status isa Int))
end

end
end
