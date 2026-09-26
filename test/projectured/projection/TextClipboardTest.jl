# The clipboard puts the system clipboard's text at a text cursor and copies a
# range of characters, through the editor's own loop: a JSON string, whose syntax
# chain maps a caret, and a plain string, which also maps a range. The system
# clipboard is an in-memory stand-in. The window helpers are the ones of
# `TextRangeSelectionTest.jl`.

function test_text_clipboard()
@testset "the clipboard pastes and copies text where the selection is" begin
    measure = FontFileMeasure()
    font = font_ubuntu_monospace_regular_20
    none = ModifierKeys()
    ctrl = ModifierKeys(ctrl = true)
    buf = Ref("")
    set_os_clipboard_backend!(read = () -> buf[], write = t -> (buf[] = String(t); true))
    try
        @testset "a JSON string takes the text at its caret" begin
            json = make_json_document_example()
            (editor, backend) = _tr_editor(make_clipboard_document(json),
                                           make_clipboard_projection(make_json_projection_example()))
            texts = _tr_texts(_tr_window(backend))
            (x, y, _) = texts[findfirst(t -> t[3] == "Alice", texts)]
            _tr_press!(editor, backend, MouseClick(:left, x + first(compute_text_extent("Al", font)), y + 8, none; time = 0.0))
            buf[] = "ZZ"
            _tr_press!(editor, backend, KeyDown(:v, ctrl; time = 0.0))
            @test json.entries[1].value.value == "AlZZice"
            # A copy at a caret takes nothing.
            buf[] = "kept"
            _tr_press!(editor, backend, KeyDown(:c, ctrl; time = 0.0))
            @test buf[] == "kept"
            @test json.entries[1].value.value == "AlZZice"
        end

        @testset "a plain string copies a range, and a paste replaces it" begin
            s = PrimitiveString("hello world")
            projection = ChainingProjection(PrimitiveStringToTextBlock(),
                                            WordWrapping(measure = measure),
                                            TextToGraphics(measure = measure))
            (editor, backend) = _tr_editor(make_clipboard_document(s),
                                           make_clipboard_projection(projection))
            (x, y, _) = only(_tr_texts(_tr_window(backend)))
            _tr_press!(editor, backend,
                       MouseClick(:left, x + first(compute_text_extent("hello", font)), y + 8, none; time = 0.0))
            _tr_press!(editor, backend, KeyDown(:left, ModifierKeys(shift = true); time = 0.0))
            _tr_press!(editor, backend, KeyDown(:left, ModifierKeys(shift = true); time = 0.0))
            buf[] = ""
            _tr_press!(editor, backend, KeyDown(:c, ctrl; time = 0.0))
            @test buf[] == "lo"
            @test s.value == "hello world"
            @test _tr_range(s) == (3, 5)
            buf[] = "p!"
            _tr_press!(editor, backend, KeyDown(:v, ctrl; time = 0.0))
            @test s.value == "help! world"
            @test _tr_range(s) == (5, 5)
        end
    finally
        reset_os_clipboard_backend!()
    end
end
end

export test_text_clipboard
