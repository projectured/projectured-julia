# A marked text: the lines of a string, split at marks that colour ranges of it.
# The print, the places in both directions, and the edits through a whole chain
# in a headless editor, where a key, Enter, a join and an edit across two runs
# change the string.

const _MT_SOURCE = "int main() {\n    int count = 0;\n    return count;\n}"

# The marks that a language server gives for `_MT_SOURCE`: `main`, and `count` twice.
_mt_marks() = [TextMark(4, 8; text = ColorRole(:function_name)),
               TextMark(21, 26; text = ColorRole(:variable)),
               TextMark(43, 48; text = ColorRole(:variable))]

_mt_color(role) = resolve_theme_color(ColorRole(role), Appearance())

_mt_runs(line) = [(run.content, run.font_color) for run in line.elements]

_mt_print(document; projection = MarkedTextToText()) =
    print_document(projection, nothing, document, nothing)

function _mt_editor(document)
    chain = ChainingProjection(MarkedTextToText(), TextToGraphics(; measure = FontFileMeasure()))
    backend = HeadlessBackend()
    editor = build_editor(document, chain;
                          backend, devices = ProjecturedKernel.DeviceModule.Device[Keyboard(), Mouse(), Display()],
                          window = false, appearance = false, settings = false, tabs = false,
                          focus_cycling = false)
    run_frame!(editor)
    (editor, backend)
end

function _mt_select!(editor, start, stop = start)
    set_selection!(editor.document, annotate_reference_types(editor.document,
        Reference(FieldReferenceStep("text"), RangeReferenceStep(start, stop))))
    run_frame!(editor)
end

_mt_press!(editor, backend, event) = (push_event!(backend, event); run_frame!(editor))

function test_marked_text_to_text()
@testset "MarkedTextToText" begin

@testset "a line for each line of the string, split at the marks" begin
    out = _mt_print(MarkedText(text = _MT_SOURCE, marks = _mt_marks())).output
    plain = MarkedTextToText().style.color
    @test length(out.elements) == 4
    @test _mt_runs(out.elements[1]) == [("int ", plain), ("main", _mt_color(:function_name)), ("() {", plain)]
    @test [run.content for run in out.elements[2].elements] == ["    int ", "count", " = 0;"]
    @test out.elements[2].elements[2].font_color == _mt_color(:variable)
    @test _mt_runs(out.elements[4]) == [("}", plain)]
    @test get_flat_string(out) == _MT_SOURCE
end

@testset "the later mark wins, a mark is cut at the end, and an empty mark draws nothing" begin
    marks = [TextMark(0, 5; text = ColorRole(:keyword)),
             TextMark(2, 3; text = ColorRole(:number_literal)),
             TextMark(4, 4; text = ColorRole(:comment)),
             TextMark(6, 99; text = ColorRole(:string_literal))]
    out = _mt_print(MarkedText(text = "abcdefgh", marks = marks)).output
    @test [run.content for run in out.elements[1].elements] == ["ab", "c", "de", "f", "gh"]
    @test out.elements[1].elements[2].font_color == _mt_color(:number_literal)
    @test out.elements[1].elements[3].font_color == _mt_color(:keyword)
    @test out.elements[1].elements[5].font_color == _mt_color(:string_literal)
end

@testset "a mark across a break colours the end of one line and the start of the next" begin
    out = _mt_print(MarkedText(text = "ab\ncd", marks = [TextMark(1, 4; text = ColorRole(:comment))])).output
    @test [run.content for run in out.elements[1].elements] == ["a", "b"]
    @test [run.content for run in out.elements[2].elements] == ["c", "d"]
    @test out.elements[1].elements[2].font_color == _mt_color(:comment)
    @test out.elements[2].elements[1].font_color == _mt_color(:comment)
end

@testset "an empty line holds one empty run" begin
    out = _mt_print(MarkedText(text = "a\n\nb")).output
    @test [run.content for run in out.elements[2].elements] == [""]
end

@testset "a line whose text and pieces did not change keeps its object" begin
    document = MarkedText(text = _MT_SOURCE, marks = _mt_marks())
    out = _mt_print(document).output
    before = collect(out.elements)
    document.marks = [TextMark(4, 8; text = ColorRole(:keyword)), _mt_marks()[2:3]...]
    after = collect(out.elements)
    @test after[1] !== before[1]
    @test all(after[k] === before[k] for k in 2:4)
    # A key moves the marks after it, so the lines after the key keep their pieces.
    edited_text = replace(_MT_SOURCE, "int main" => "int  main")
    document.marks = compute_moved_text_marks(document.marks, _MT_SOURCE, edited_text)
    document.text = edited_text
    edited = collect(out.elements)
    @test edited[1] !== after[1]
    @test all(edited[k] === after[k] for k in 2:4)
end

@testset "a place maps to the string and back" begin
    iomap = _mt_print(MarkedText(text = _MT_SOURCE, marks = _mt_marks()))
    p = MarkedTextToText()
    caret = map_reference_forward(p, iomap, Reference(FieldReferenceStep("text"), RangeReferenceStep(6, 6)))
    @test get_flat_range(iomap.output, caret) == (6, 6)
    back = strip_reference_types(map_reference_backward(p, iomap, make_flat_range_reference(23, 23)))
    @test get_reference_steps(back) == [FieldReferenceStep("text"), RangeReferenceStep(23, 23)]
    back = strip_reference_types(map_reference_backward(p, iomap, make_flat_range_reference(2, 30)))
    @test get_reference_steps(back) == [FieldReferenceStep("text"), RangeReferenceStep(2, 30)]
end

@testset "an edit of lines is an edit of the string at the same offsets" begin
    iomap = _mt_print(MarkedText(text = _MT_SOURCE, marks = _mt_marks()))
    op = read_intent(MarkedTextToText(), iomap,
                     ReplaceTextRangeOperation(make_flat_range_reference(2, 30), "x\ny"))
    @test op isa ReplaceStringRangeOperation
    @test op.replacement == "x\ny"
    @test last(get_reference_steps(strip_reference_types(op.reference))) == RangeReferenceStep(2, 30)
end

@testset "a key, Enter, a join and an edit across two runs change the string" begin
    document = MarkedText(text = "int main() {\n    int count = 0;\n}", marks = _mt_marks()[1:2])
    editor, backend = _mt_editor(document)
    _mt_select!(editor, 8)
    _mt_press!(editor, backend, KeyPress('X'; time = 0.0))
    @test document.text == "int mainX() {\n    int count = 0;\n}"
    @test get_reference_steps(strip_reference_types(get_selection(editor.document))) ==
          [FieldReferenceStep("text"), RangeReferenceStep(9, 9)]
    _mt_press!(editor, backend, KeyPress('\n'; time = 0.0))
    @test document.text == "int mainX\n() {\n    int count = 0;\n}"
    _mt_press!(editor, backend, KeyDown(:backspace, ModifierKeys(); time = 0.0))
    @test document.text == "int mainX() {\n    int count = 0;\n}"
    # `t ma` crosses the run `int ` and the run `main`.
    _mt_select!(editor, 2, 6)
    _mt_press!(editor, backend, KeyDown(:delete, ModifierKeys(); time = 0.0))
    @test document.text == "ininX() {\n    int count = 0;\n}"
end

@testset "marks move from an old text to a new one" begin
    marks = _mt_marks()
    @test compute_moved_text_marks(marks, _MT_SOURCE, _MT_SOURCE) == marks
    # A key before a mark moves it, and the marks before the key stay.
    moved = compute_moved_text_marks(marks, _MT_SOURCE, replace(_MT_SOURCE, "= 0" => "= 10"))
    @test [(m.start, m.stop) for m in moved] == [(4, 8), (21, 26), (44, 49)]
    # A key inside a mark drops that mark only.
    moved = compute_moved_text_marks(marks, _MT_SOURCE, replace(_MT_SOURCE, "main" => "maXin"))
    @test [(m.start, m.stop) for m in moved] == [(22, 27), (44, 49)]
    # A deletion before a mark moves it back.
    moved = compute_moved_text_marks(marks, _MT_SOURCE, replace(_MT_SOURCE, "int main" => "main"))
    @test [(m.start, m.stop) for m in moved] == [(0, 4), (17, 22), (39, 44)]
    # Characters count, not bytes.
    moved = compute_moved_text_marks([TextMark(3, 4; text = ColorRole(:keyword))], "αβ x", "αβγ x")
    @test [(m.start, m.stop) for m in moved] == [(4, 5)]
end

end # @testset
end
