# The evaluator toplevel is a persistent REPL: a person types `repl` into an
# empty tab, types a Julia expression into the fresh form it opens with, and
# ENTER evaluates it in place — appending a fresh empty form and keeping
# the interpreter's own state, so a variable one form binds is visible from the
# next. That persistence is what tells it apart from a one-shot sandbox.

using Test
using ProjecturedKernel.ToolModule: ToolSet

# `execute_julia_code!` reads the `tools` field of an editor.
mutable struct _EvaluatorToplevelMockEditor; document::Any; tools::ToolSet; end

# Flatten a result document (a `TextBlock`, or another document's own printed
# text) to a plain string.
function _et_flatten(t::TextBlock)
    io = IOBuffer()
    for span in t.elements
        hasproperty(span, :content) && print(io, span.content)
    end
    String(take!(io))
end
_et_flatten(d) = String(strip(print_natural_text(d)))

function test_evaluator_toplevel()
@testset "the evaluator toplevel is a persistent REPL" begin

_stub = FixedMeasure(10, 18, 6, 0)

# Every word the canvas draws, joined — the same walk `ToolViewTest.jl` uses.
function drawn(node, depth = 0)
    depth > 40 && return ""
    node isa GraphicsText && return String(node.text) * " "
    node isa GraphicsCanvas &&
        return join([drawn(node.elements[i], depth + 1) for i in 1:length(node.elements)])
    node isa GraphicsViewport && return drawn(node.content, depth + 1)
    ""
end

# Every text the canvas draws, at its place in the canvas.
function placed(node, ox = 0, oy = 0, found = Tuple{String,Int,Int}[], depth = 0)
    depth > 40 && return found
    if node isa GraphicsText
        push!(found, (String(node.text), ox + Int(node.x), oy + Int(node.y)))
    elseif node isa GraphicsCanvas
        for i in 1:length(node.elements)
            placed(node.elements[i], ox + Int(node.x), oy + Int(node.y), found, depth + 1)
        end
    elseif node isa GraphicsViewport
        placed(node.content, ox + Int(node.x), oy + Int(node.y), found, depth + 1)
    end
    found
end

print_natural(document) =
    get_iomap_output(print_document(NaturalToGraphics(measure = _stub), nothing, document,
                     PrinterContext(EmptyReference(), Cell(600), Cell(400), Dict{Symbol,Any}())))
render(document) = drawn(print_natural(document))

editor(t) = _EvaluatorToplevelMockEditor(t, ToolSet())
enter() = KeyDown(:return, ModifierKeys(); time = 0.0)
shift_enter() = KeyDown(:return, ModifierKeys(shift = true); time = 0.0)

@testset "a fresh loop holds one empty form, caret inside it" begin
    toplevel = make_insertion_document(EvaluatorToplevel)
    @test toplevel isa EvaluatorToplevel
    @test length(toplevel.elements) == 1
    @test toplevel.elements[1].form isa PrimitiveString
    @test toplevel.elements[1].form.value == ""

    sel = toplevel.selection
    @test sel isa Reference
    steps = get_reference_steps(strip_reference_types(sel))
    @test !isempty(steps)
    @test steps[1] == FieldReferenceStep("elements")
end

# The words of a drawn text, less the icons of the private use area.
is_icon(word) = all(c -> '\ue000' <= c <= '\uf8ff', word)
words(text) = [word for word in split(text) if !is_icon(word)]
OPTION_WORDS = ["Parse", "evaluated", "forms", "Structured", "forms"]

@testset "it draws through NaturalToGraphics" begin
    toplevel = make_insertion_document(EvaluatorToplevel)
    text = render(toplevel)
    @test !occursin("no natural rendering", text)
    # The toplevel draws its options and its one form, and not a canvas drawn as
    # a tree of its fields. A fresh form draws its prompt, and no result.
    @test words(text) == [OPTION_WORDS; words(render(toplevel.elements[1]))]
    @test first(split(render(toplevel.elements[1]))) == ">"
    @test !occursin("=", text)
end

@testset "the prompts stand in a column of their own, and the code and the result beside it" begin
    toplevel = make_insertion_document(EvaluatorToplevel)
    toplevel.elements[1].form.value = "1 + 1"
    evaluate_operation(editor(toplevel), read_gesture(toplevel, enter()))
    everything = placed(print_natural(toplevel))
    # The rows of the forms, below the row of options.
    texts = [(text, x, y) for (text, x, y) in everything
             if y >= minimum(y for (text, _, y) in everything if text == ">")]
    prompts = [(x, y) for (text, x, y) in texts if text in (">", "=")]
    others = [(text, x, y) for (text, x, y) in texts if !(text in (">", "="))]
    # The code of the first form, its result, and the code of the fresh form.
    @test [text for (text, _, _) in texts if text in (">", "=")] == [">", "=", ">"]
    @test length(unique(x for (x, _) in prompts)) == 1
    # Nothing else stands in the column of the prompts.
    @test all(x > prompts[1][1] for (_, x, _) in others)
    # The code and the result start at one x, right of their prompts.
    result_x = only(x for (text, x, _) in others if text == "2")
    @test result_x == minimum(x for (_, x, y) in others if y < prompts[2][2])
end

@testset "the forms scroll in the offered height, and the view follows the end" begin
    toplevel = make_insertion_document(EvaluatorToplevel)
    ed = editor(toplevel)
    for i in 1:8
        toplevel.elements[length(toplevel.elements)].form.value = string(i)
        evaluate_operation(ed, read_gesture(toplevel, enter()))
    end
    projection = NaturalToGraphics(measure = _stub)
    iomap = print_document(projection, nothing, toplevel,
                           PrinterContext(EmptyReference(), Cell(600), Cell(120), Dict{Symbol,Any}()))
    canvas = get_iomap_output(iomap)
    prompts_y() = [y for (text, _, y) in placed(canvas) if text == ">"]
    options_y() = [y for (text, _, y) in placed(canvas) if text == "Structured forms"]
    @test options_y() == [0]
    # The pane is as tall as the offer, and it shows the end: the prompt of the
    # fresh form is in view, and the prompt of the first form is above it.
    @test Int(canvas.h) == 120
    @test 0 <= last(prompts_y()) < 120
    @test first(prompts_y()) < 0
    # A wheel turn toward the start takes the view off the end, and moves the
    # forms down by one line, which is 24 pixels with this measure.
    at_end = last(prompts_y())
    change = read_intent(projection, nothing, Intent(MouseScroll(0, 1, 50, 50; time = 0.0)), iomap)
    evaluate_operation(ed, change.operation)
    @test toplevel.follow_end == false
    @test last(prompts_y()) == at_end + 24
    # The options stay where they are, and the forms move under them.
    @test options_y() == [0]
    # An evaluation brings the end back into view, where the next key goes.
    toplevel.elements[length(toplevel.elements)].form.value = "9"
    evaluate_operation(ed, read_gesture(toplevel, enter()))
    @test toplevel.follow_end == true
    @test 0 <= last(prompts_y()) < 120
end

# Every circle the canvas draws.
circles(node, depth = 0) =
    depth > 60 ? 0 :
    node isa GraphicsCircle ? 1 :
    node isa GraphicsCanvas ? sum((circles(node.elements[i], depth + 1) for i in 1:length(node.elements)); init = 0) :
    node isa GraphicsViewport ? circles(node.content, depth + 1) : 0

@testset "the evaluator is a REPL that no API limits, and the assistant keeps its API" begin
    # The tools of the editor declare one name, as a host declares its API.
    tools = ToolSet(; api = Any[parentmodule(PrimitiveString) => (:PrimitiveString,)])
    seen = Any[]
    observe_evaluations!(value -> push!(seen, value), tools)
    toplevel = make_insertion_document(EvaluatorToplevel)
    ed = _EvaluatorToplevelMockEditor(toplevel, tools)
    toplevel.elements[1].form.value = "GraphicsCircle(10, 10, 10)"
    evaluate_operation(ed, read_gesture(toplevel, enter()))
    @test !toplevel.elements[1].is_error
    @test toplevel.elements[1].result isa GraphicsCircle
    # The host still hears what an evaluation of the evaluator made.
    @test length(seen) == 1 && only(seen) isa GraphicsCircle
    # The code of the assistant runs in the tools of the editor, with its API.
    @test occursin("UndefVarError", execute_julia_code!(tools, ed, "GraphicsCircle(10, 10, 10)"))
end

@testset "a form runs with the editor of the evaluator as the editor of the evaluation" begin
    toplevel = make_insertion_document(EvaluatorToplevel)
    ed = _EvaluatorToplevelMockEditor(toplevel, ToolSet())
    toplevel.elements[1].form.value = "get_evaluation_editor() === editor"
    evaluate_operation(ed, read_gesture(toplevel, enter()))
    @test !toplevel.elements[1].is_error
    @test _et_flatten(toplevel.elements[1].result) == "true"
end

@testset "a graphics value draws as itself, not as a tree of its fields" begin
    circle = GraphicsCircle(10, 10, 10)
    @test print_natural(circle) === circle
    iomap = print_document(GraphicsToGraphics(), nothing, circle, nothing)
    @test read_intent(GraphicsToGraphics(), iomap, KeyPress('x'; time = 0.0)) === nothing
    toplevel = make_insertion_document(EvaluatorToplevel)
    toplevel.elements[1].form.value = "GraphicsCircle(10, 10, 10)"
    evaluate_operation(editor(toplevel), read_gesture(toplevel, enter()))
    @test circles(print_natural(toplevel)) == 1
    @test !occursin("radius", render(toplevel))
end

@testset "it draws in a pane tab" begin
    # A tab reads its content through `print_child`, which does not print an
    # output again until it is graphics, so the row itself must end in graphics.
    toplevel = make_insertion_document(EvaluatorToplevel)
    tree = PaneTree(PaneSplit(:vertical, Any[PaneGroup(PaneTab[PaneTab("Evaluator", toplevel)])];
                              weights = [1.0]))
    host = ChainingProjection(RecursiveProjection(PaneToWidget()), NaturalToGraphics(measure = _stub))
    text = drawn(get_iomap_output(print_document(host, nothing, tree,
                 PrinterContext(EmptyReference(), Cell(600), Cell(400), Dict{Symbol,Any}()))))
    # The page draws the title of the tab, then the one form of the evaluator,
    # word for word. The icons of the tab strip are glyphs of the private use
    # area, and they are not words.
    @test words(text) == ["Evaluator"; OPTION_WORDS; words(render(toplevel.elements[1]))]
end

@testset "ENTER evaluates the form the caret is in" begin
    toplevel = make_insertion_document(EvaluatorToplevel)
    toplevel.elements[1].form.value = "1 + 1"

    operation = read_gesture(toplevel, enter())
    @test operation isa EvaluateSelectedFormOperation

    evaluate_operation(editor(toplevel), operation)

    @test length(toplevel.elements) == 2
    @test !toplevel.elements[1].is_error
    @test occursin("2", _et_flatten(toplevel.elements[1].result))
    @test toplevel.elements[2].form isa PrimitiveString
    @test toplevel.elements[2].form.value == ""
    # The selection follows the fresh form, so the next keystroke lands in it.
    steps = get_reference_steps(strip_reference_types(toplevel.selection))
    @test steps[1] == FieldReferenceStep("elements")
    @test steps[2] == RangeReferenceStep(1, 2)
    # The form that was evaluated keeps no selection, so it draws no caret.
    @test toplevel.elements[1].selection === nothing
    @test toplevel.elements[1].form.selection === nothing
    @test toplevel.elements[2].form.selection !== nothing
    # Alt+Enter evaluates nothing: Enter alone does.
    @test read_gesture(toplevel, KeyDown(:return, ModifierKeys(alt = true); time = 0.0)) === nothing
end

# The form that evaluating `code` leaves behind, with the parse on or off.
function evaluated_form(code; parse = true)
    toplevel = make_insertion_document(EvaluatorToplevel)
    toplevel.parse_evaluated_forms = parse
    toplevel.elements[1].form.value = code
    evaluate_operation(editor(toplevel), read_gesture(toplevel, enter()))
    toplevel.elements[1]
end

@testset "an evaluated form becomes Julia when it prints back as the same tokens" begin
    form = evaluated_form("x = 1 + 2")
    @test form.form isa JuliaAssignment
    @test print_natural_text(form.form) == "x = 1 + 2"
    @test form.source == "x = 1 + 2"
    # The blank space around the code does not stop it, and `source` keeps it.
    form = evaluated_form("\nx = 1 + 2\n")
    @test form.form isa JuliaAssignment
    @test form.source == "\nx = 1 + 2\n"
    # Nor does the spacing between the tokens: the form shows the spacing of the
    # Julia notation, and `source` keeps the code as typed.
    form = evaluated_form("1+1")
    @test form.form isa JuliaBinaryOperation
    @test print_natural_text(form.form) == "1 + 1"
    @test form.source == "1+1"
    @test evaluated_form("max(1,2)").form isa JuliaCall
    @test evaluated_form("for i in 1:2\n    i\nend").form isa JuliaFor
    # With the parse off, the form keeps the string it was typed as.
    form = evaluated_form("x = 1 + 2"; parse = false)
    @test form.form isa PrimitiveString
    @test form.form.value == "x = 1 + 2"
    @test form.source == "x = 1 + 2"
end

@testset "a string form and a result wrap in the width that the tab offers" begin
    # Forty numbers are wider than the offer, as in a tab that a split made narrow.
    # A Julia form keeps the layout of its code and never wraps, so with the parse
    # on, only its result is checked.
    code = "y = (" * join(1:40, ", ") * ")"
    for parse in (true, false)
        toplevel = make_insertion_document(EvaluatorToplevel)
        toplevel.parse_evaluated_forms = parse
        toplevel.elements[1].form.value = code
        evaluate_operation(editor(toplevel), read_gesture(toplevel, enter()))
        # The application draws a string form and a Julia form as it draws a tab.
        renderer = NaturalToGraphics(measure = _stub,
                                     extra = make_application_content_projections(measure = _stub))
        canvas = get_iomap_output(print_document(renderer, nothing, toplevel,
                     PrinterContext(EmptyReference(), Cell(500), Cell(400), Dict{Symbol,Any}())))
        everything = placed(canvas)
        prompt_x = minimum(x for (text, x, _) in everything if text == ">")
        first_y = minimum(y for (text, x, y) in everything if text == (parse ? "=" : ">") && x == prompt_x)
        # `_stub` measures 10 pixels for each character.
        right_edges = [x + 10 * length(text) for (text, x, y) in everything if y >= first_y]
        @test maximum(right_edges) <= 500
    end
end

# The width of the smallest canvas under `canvas`, with a width of its own, that
# holds the text `label` directly, or `nothing`. A wrapper that is not a canvas
# (a viewport, a placed child) is followed through its content.
function _et_width_holding(canvas, label)
    widths = Int[]
    function walk(c)
        if c isa GraphicsCanvas
            width = Int(c.w[])
            width > 0 && any(e -> e isa GraphicsText && e.text == label, c.elements) && push!(widths, width)
            foreach(walk, c.elements)
        else
            for field in (:content, :child, :canvas)
                hasproperty(c, field) && walk(getproperty(c, field))
            end
        end
    end
    walk(canvas)
    isempty(widths) ? nothing : minimum(widths)
end

@testset "a widget result keeps its own width in the row" begin
    toplevel = make_insertion_document(EvaluatorToplevel)
    toplevel.elements[1].form.value = "WidgetButton(\"Press me\")"
    evaluate_operation(editor(toplevel), read_gesture(toplevel, enter()))
    renderer = NaturalToGraphics(measure = _stub,
                                 extra = make_application_content_projections(measure = _stub))
    canvas = get_iomap_output(print_document(renderer, nothing, toplevel,
                 PrinterContext(EmptyReference(), Cell(500), Cell(400), Dict{Symbol,Any}())))
    # `_stub` measures 10 pixels for each character: the label is 80 wide, and the
    # button is that and its padding, far from the 500 of the tab.
    width = _et_width_holding(canvas, "Press me")
    @test width !== nothing
    @test 80 <= width < 200
end

@testset "a form that answers nothing shows the nothing of Julia" begin
    # Nothing printed: the result is the Julia `nothing`, drawn by the Julia domain.
    form = evaluated_form("x_q = 3; nothing")
    @test nameof(typeof(form.result)) === :JuliaNothing
    # Something printed: the result is what was printed.
    form = evaluated_form("println(\"hi\"); nothing")
    @test _et_flatten(form.result) == "hi"
    # A function reads as the REPL shows it.
    form = evaluated_form("phase_q() = 1")
    @test _et_flatten(form.result) == "phase_q (generic function with 1 method)"
end

@testset "a long value shows the REPL header, not a note to the model" begin
    form = evaluated_form("collect(1:1000)")
    text = _et_flatten(form.result)
    @test occursin("1000-element Vector{Int64}:", text)
    @test occursin("⋮", text)
    @test !occursin("Print a part", text)
    @test !occursin("trimmed", text)
end

@testset "a form becomes Julia with its lambda, its keywords and its short definitions" begin
    for code in ("map(x -> x^2, [1, 2])", "sum([1, 2]; init = 0)", "twice_q(x) = 2 * x")
        @test !(evaluated_form(code).form isa PrimitiveString)
    end
end

@testset "a form whose parse would change more than spacing keeps its string" begin
    # A comment has no place in the Julia document, and the print writes a
    # juxtaposed product with `*`: both forms keep what was typed.
    for code in ("x = 1 + 2  # three", "y = 2x + 1")
        form = evaluated_form(code)
        @test form.form isa PrimitiveString
        @test form.form.value == code
    end
    # Code of several statements prints as an indented block with an empty first
    # and last line, so it keeps the lines it was typed on.
    form = evaluated_form("x = 1\nx + 1")
    @test form.form isa PrimitiveString
    @test form.form.value == "x = 1\nx + 1"
    # A space inside a string is part of the string, not spacing between tokens,
    # and a line break counts where a space does not.
    same_tokens = parentmodule(EvaluatorToplevel)._has_same_tokens
    @test same_tokens("1+1", "1 + 1")
    @test same_tokens("for i in 1:2\n    i\nend", "for i in 1:2\n  i\nend")
    @test !same_tokens("s = \"a  b\"", "s = \"a b\"")
    @test !same_tokens("x = 1  # one", "x = 1")
    @test !same_tokens("x = 1\nx + 1", "\n  x = 1\n  x + 1\n")
    @test !same_tokens("struct P\n    x::Int\nend", "struct P\n\n  x::Int\nend")
    # Code that does not parse keeps its string, and its error.
    form = evaluated_form("x = (")
    @test form.form isa PrimitiveString
    @test form.form.value == "x = ("
    @test form.is_error
end

@testset "a form becomes Julia with an infix operator and with its semicolons" begin
    for code in ("files = first(search_documents(editor.document, d -> d isa Workspace))",
                 "push!(toolbar.elements, WidgetToolbarItem(\"Hello\"));",
                 "k = :a => 1", "x = 1; y = 2")
        form = evaluated_form(code)
        @test !(form.form isa PrimitiveString)
        @test print_natural_text(form.form) == code
    end
end

@testset "a form that ends with a semicolon hides its value" begin
    no_result(form) = form.result isa TextBlock && isempty(form.result.elements)
    # The value is not shown, and the code ran: the name it bound holds the value.
    form = evaluated_form("xs = [1, 2, 3];")
    @test no_result(form)
    @test !form.is_error
    @test print_natural_text(form.form) == "xs = [1, 2, 3];"
    # A comment after the `;` does not show the value either, and a string form
    # hides it as a Julia document does.
    @test no_result(evaluated_form("xs = [1, 2, 3];  # three"))
    @test no_result(evaluated_form("xs = [1, 2, 3];"; parse = false))
    # A document is not drawn either.
    @test no_result(evaluated_form("TextBlock(TextString(\"hidden\"));"))
    # What the code prints still shows, and so does an error.
    @test _et_flatten(evaluated_form("println(\"shown\"); 42;").result) == "shown"
    form = evaluated_form("throw(ArgumentError(\"stop\"));")
    @test form.is_error
    @test occursin("stop", _et_flatten(form.result))
    # A `;` between two statements hides nothing.
    @test _et_flatten(evaluated_form("a = 1; a + 1").result) == "2"
end

@testset "the parse changes the form, never the result" begin
    # An error names the line of the test that made it in its stack trace, so an
    # error is compared by its first line.
    result_of(form) = form.is_error ? first(split(_et_flatten(form.result), '\n')) :
                                      _et_flatten(form.result)
    for code in ("x = 1 + 2", "x = 1 + 2  # three", "max(1,2)", "x = (")
        parsed = evaluated_form(code)
        plain = evaluated_form(code; parse = false)
        @test result_of(parsed) == result_of(plain)
        @test parsed.is_error == plain.is_error
    end
    @test occursin("3", _et_flatten(evaluated_form("x = 1 + 2").result))
    @test result_of(evaluated_form("x = (")) == "ParseError:"
end

@testset "SHIFT+ENTER puts a line break at the caret" begin
    toplevel = make_insertion_document(EvaluatorToplevel)
    operation = read_gesture(toplevel, shift_enter())
    @test operation isa ReplaceStringRangeOperation
    @test operation.replacement == "\n"
    # The edit replaces the caret of the first form, `elements[1].form.value{0}`.
    @test get_reference_steps(strip_reference_types(operation.reference)) ==
          get_reference_steps(strip_reference_types(toplevel.selection))
    evaluate_operation(editor(toplevel), operation)
    @test toplevel.elements[1].form.value == "\n"
    @test length(toplevel.elements) == 1
end

# A toplevel with the forms `codes` evaluated, as a person types and evaluates them,
# and the functions a test of the history needs.
function history_session(codes...; parse = true, structured = false)
    toplevel = make_insertion_document(EvaluatorToplevel)
    toplevel.parse_evaluated_forms = parse
    toplevel.type_structured_forms = structured
    ed = editor(toplevel)
    type!(text) = evaluate_operation(ed, ReplaceStringRangeOperation(toplevel.selection, text))
    press!(key; modifiers...) = (op = read_gesture(toplevel, KeyDown(key, ModifierKeys(; modifiers...); time = 0.0));
                   op === nothing || evaluate_operation(ed, op); op)
    shown() = toplevel.elements[length(toplevel.elements)].form.value
    caret() = last(get_reference_steps(strip_reference_types(toplevel.selection)))
    for code in codes
        type!(code)
        press!(:return)
    end
    (; toplevel, ed, type!, press!, shown, caret)
end

@testset "UP and DOWN in the bottom form walk the history, as a Julia REPL does" begin
    s = history_session("x = 1", "y = 2", "x + y")
    @test s.shown() == ""
    # Up goes back from the newest form, and the caret stands at the end.
    @test s.press!(:up) isa RecallEvaluatorFormOperation
    @test s.shown() == "x + y"
    @test s.caret() == RangeReferenceStep(5, 5)
    s.press!(:up); @test s.shown() == "y = 2"
    s.press!(:up); @test s.shown() == "x = 1"
    # Past the oldest form nothing changes.
    s.press!(:up); @test s.shown() == "x = 1"
    # Down comes forward, and past the newest form the draft comes back.
    s.press!(:down); @test s.shown() == "y = 2"
    s.press!(:down); @test s.shown() == "x + y"
    s.press!(:down); @test s.shown() == ""
    s.press!(:down); @test s.shown() == ""
    # Evaluated forms keep their code: a recall writes only the bottom form.
    @test [print_natural_text(s.toplevel.elements[i].form) for i in 1:3] == ["x = 1", "y = 2", "x + y"]
    # The walk above went over Julia documents, not strings.
    @test all(s.toplevel.elements[i].form isa JuliaDocument for i in 1:3)
end

@testset "the history holds string forms and Julia forms alike" begin
    # The comment keeps the first form a string, and the second becomes Julia.
    s = history_session("x = 1  # one", "y = 2")
    @test s.toplevel.elements[1].form isa PrimitiveString
    @test s.toplevel.elements[2].form isa JuliaAssignment
    s.press!(:up); @test s.shown() == "y = 2"
    # The string form comes back with its comment.
    s.press!(:up); @test s.shown() == "x = 1  # one"
    s.press!(:down); s.press!(:down); @test s.shown() == ""
    # The prefix finds both kinds.
    s.type!("x")
    s.press!(:up); @test s.shown() == "x = 1  # one"
    # A Julia form comes back as it prints, which is the code without the blank
    # space around it.
    s = history_session("\nz = 3\n")
    @test s.toplevel.elements[1].form isa JuliaAssignment
    s.press!(:up); @test s.shown() == "z = 3"
end

@testset "the text before the caret is a prefix, and the draft comes back" begin
    s = history_session("x = 1", "y = 2", "x + y")
    s.type!("x")
    s.press!(:up); @test s.shown() == "x + y"
    # "y = 2" does not start with "x".
    s.press!(:up); @test s.shown() == "x = 1"
    s.press!(:up); @test s.shown() == "x = 1"
    s.press!(:down); @test s.shown() == "x + y"
    s.press!(:down); @test s.shown() == "x"
    # Edited, a recalled code is a new draft: its text is the new prefix.
    s.press!(:up); s.type!(" + 1")
    @test s.shown() == "x + y + 1"
    s.press!(:up); @test s.shown() == "x + y + 1"
end

@testset "a failed form is in the history, and the text shown now is skipped" begin
    s = history_session("a = 1", "a = 1", "undefined_name_xyz123")
    @test s.toplevel.elements[3].is_error
    s.press!(:up); @test s.shown() == "undefined_name_xyz123"
    s.press!(:up); @test s.shown() == "a = 1"
    # The older "a = 1" is the text shown now, so Up stays.
    s.press!(:up); @test s.shown() == "a = 1"
    s.press!(:down); @test s.shown() == "undefined_name_xyz123"
end

@testset "UP and DOWN in a form above move the caret to its neighbors" begin
    s = history_session("1", "22", "333"; parse = false)
    form_caret(i, k) = ConcreteReference(FieldReferenceStep("elements"),
        ConcreteReference(RangeReferenceStep(i - 1, i), ConcreteReference(FieldReferenceStep("form"),
            ConcreteReference(FieldReferenceStep("value"), ConcreteReference(RangeReferenceStep(k, k), EmptyReference())))))
    steps(reference) = get_reference_steps(strip_reference_types(reference))
    set_selection!(s.toplevel, form_caret(2, 1))
    # Up goes to the end of the form above, and Down to the start of the form below.
    @test steps(s.press!(:up).path) == steps(form_caret(1, 1))
    @test steps(s.toplevel.selection) == steps(form_caret(1, 1))
    @test s.press!(:up) === nothing
    set_selection!(s.toplevel, form_caret(2, 1))
    @test steps(s.press!(:down).path) == steps(form_caret(3, 0))
    # A form above is never written.
    @test [s.toplevel.elements[i].form.value for i in 1:3] == ["1", "22", "333"]
end

# Every rectangle the canvas draws, at its place in the canvas.
function boxes(node, ox = 0, oy = 0, found = Tuple{Int,Int,Int,Int}[], depth = 0)
    depth > 40 && return found
    if node isa GraphicsRect
        push!(found, (ox + Int(node.x), oy + Int(node.y), Int(node.w), Int(node.h)))
    elseif node isa GraphicsCanvas
        for i in 1:length(node.elements)
            boxes(node.elements[i], ox + Int(node.x), oy + Int(node.y), found, depth + 1)
        end
    elseif node isa GraphicsViewport
        boxes(node.content, ox + Int(node.x), oy + Int(node.y), found, depth + 1)
    end
    found
end

@testset "UP and DOWN select a form above whole when it is a Julia document" begin
    s = history_session("1", "x = 2", "333")
    @test [nameof(typeof(s.toplevel.elements[i].form)) for i in 1:4] ==
          [:JuliaInteger, :JuliaAssignment, :JuliaInteger, :PrimitiveString]
    whole(i) = ConcreteReference(FieldReferenceStep("elements"),
        ConcreteReference(RangeReferenceStep(i - 1, i),
            ConcreteReference(FieldReferenceStep("form"), EmptyReference())))
    form_caret(i, k) = ConcreteReference(FieldReferenceStep("elements"),
        ConcreteReference(RangeReferenceStep(i - 1, i), ConcreteReference(FieldReferenceStep("form"),
            ConcreteReference(FieldReferenceStep("value"), ConcreteReference(RangeReferenceStep(k, k), EmptyReference())))))
    steps(reference) = get_reference_steps(strip_reference_types(reference))
    clear_selection!(s.toplevel)
    set_selection!(s.toplevel, whole(3))

    # Up selects the form above whole: the selection ends at that form.
    s.press!(:up)
    @test steps(s.toplevel.selection) == steps(whole(2))
    @test evaluate_reference(s.toplevel, strip_reference_types(s.toplevel.selection)) ===
          s.toplevel.elements[2].form
    # The highlight lies over the code of that form, and over nothing else of it.
    canvas = print_natural(s.toplevel)
    texts = placed(canvas)
    prompt_y = [y for (text, _, y) in texts if text == ">"][2]
    code = [(x, y) for (text, x, y) in texts if y == prompt_y && text != ">"]
    code_x = minimum(x for (x, _) in code)
    @test any(b -> b[1] == code_x && b[3] == 10 * length("x = 2") &&
                   b[2] <= prompt_y < b[2] + b[4], boxes(canvas))
    s.press!(:up)
    @test steps(s.toplevel.selection) == steps(whole(1))
    @test s.press!(:up) === nothing

    # Down walks back, and into the bottom form, which is a string, as a caret.
    s.press!(:down); @test steps(s.toplevel.selection) == steps(whole(2))
    s.press!(:down); @test steps(s.toplevel.selection) == steps(whole(3))
    s.press!(:down); @test steps(s.toplevel.selection) == steps(form_caret(4, 0))

    # Enter on a form selected whole evaluates it again, and the form keeps its
    # Julia document.
    clear_selection!(s.toplevel)
    set_selection!(s.toplevel, whole(2))
    @test s.press!(:return) isa EvaluateSelectedFormOperation
    @test length(s.toplevel.elements) == 5
    @test s.toplevel.elements[2].form isa JuliaAssignment
    @test s.toplevel.elements[2].source == "x = 2"
end

@testset "a structured toplevel opens each fresh form as a Julia hole" begin
    s = history_session("1"; structured = true)
    # The first form was made before the switch; the fresh one is a hole.
    @test s.toplevel.elements[1].form isa JuliaInteger
    @test s.toplevel.elements[2].form isa JuliaInsertion
    @test s.shown() == ""
    # The keys that edit a string form edit the hole the same way.
    s.type!("x = 1 + 2")
    @test s.shown() == "x = 1 + 2"
    @test s.press!(:return; shift = true) isa ReplaceStringRangeOperation
    @test s.shown() == "x = 1 + 2\n"
    @test s.caret() == RangeReferenceStep(10, 10)
end

@testset "Enter commits the hole of a structured form as part of its evaluation" begin
    # The hole commits even with the parse of string forms off.
    s = history_session("1"; structured = true, parse = false)
    s.type!("x = 1 + 2")
    @test s.press!(:return) isa EvaluateSelectedFormOperation
    form = s.toplevel.elements[2]
    @test form.form isa JuliaAssignment
    @test form.source == "x = 1 + 2"
    @test occursin("3", _et_flatten(form.result))
    @test s.toplevel.elements[3].form isa JuliaInsertion
    # A hole whose parse would lose a comment keeps its text, and still ran.
    s.type!("y = 2  # two")
    s.press!(:return)
    @test s.toplevel.elements[3].form isa JuliaInsertion
    @test s.toplevel.elements[3].form.value == "y = 2  # two"
    @test occursin("2", _et_flatten(s.toplevel.elements[3].result))
    # Up recalls both, the hole's text as it was typed.
    s.press!(:up); @test s.shown() == "y = 2  # two"
    s.press!(:up); @test s.shown() == "x = 1 + 2"
end

@testset "Enter evaluates only from the code of a form" begin
    s = history_session("1")
    result(i) = ConcreteReference(FieldReferenceStep("elements"),
        ConcreteReference(RangeReferenceStep(i - 1, i),
            ConcreteReference(FieldReferenceStep("result"), EmptyReference())))
    clear_selection!(s.toplevel)
    set_selection!(s.toplevel, result(1))
    @test read_gesture(s.toplevel, enter()) === nothing
end

@testset "Structured forms changes the bottom form, and keeps its text and caret" begin
    s = history_session("1")
    s.type!("x = 1")
    toggle!() = evaluate_operation(s.ed, ToggleEvaluatorOptionOperation(s.toplevel, :type_structured_forms))
    toggle!()
    @test s.toplevel.type_structured_forms
    @test s.toplevel.elements[2].form isa JuliaInsertion
    @test s.shown() == "x = 1"
    @test s.caret() == RangeReferenceStep(5, 5)
    # The evaluated form keeps its shape.
    @test s.toplevel.elements[1].form isa JuliaInteger
    toggle!()
    @test !s.toplevel.type_structured_forms
    @test s.toplevel.elements[2].form isa PrimitiveString
    @test s.shown() == "x = 1"
    @test s.caret() == RangeReferenceStep(5, 5)
    # A bottom form that is already a parsed tree becomes the string of its print,
    # with the caret at its end.
    whole(i) = ConcreteReference(FieldReferenceStep("elements"),
        ConcreteReference(RangeReferenceStep(i - 1, i),
            ConcreteReference(FieldReferenceStep("form"), EmptyReference())))
    s.toplevel.type_structured_forms = true
    clear_selection!(s.toplevel)
    set_selection!(s.toplevel, whole(2))
    s.toplevel.elements[2].form = parse_natural_text(:jl, "f(a, b)")
    toggle!()
    @test s.toplevel.elements[2].form isa PrimitiveString
    @test s.shown() == "f(a, b)"
    @test s.caret() == RangeReferenceStep(7, 7)
end

@testset "Parse evaluated forms changes only the evaluations after it" begin
    s = history_session("1 + 1")
    @test s.toplevel.elements[1].form isa JuliaBinaryOperation
    evaluate_operation(s.ed, ToggleEvaluatorOptionOperation(s.toplevel, :parse_evaluated_forms))
    @test !s.toplevel.parse_evaluated_forms
    @test s.toplevel.elements[1].form isa JuliaBinaryOperation
    s.type!("2 + 2")
    s.press!(:return)
    @test s.toplevel.elements[2].form isa PrimitiveString
end

@testset "the command palette runs both options by name" begin
    t = make_insertion_document(EvaluatorToplevel)
    bindings = collect_document_gesture_bindings(EvaluatorToplevel)
    for (name, option) in (("Parse evaluated forms", :parse_evaluated_forms),
                           ("Type structured forms", :type_structured_forms))
        operation = fire_named_gesture_binding(bindings, t, name; selection = t.selection)
        @test operation isa ToggleEvaluatorOptionOperation
        @test operation.option === option
    end
end

@testset "a press on a check box turns its option on and off" begin
    toplevel = make_insertion_document(EvaluatorToplevel)
    ed = editor(toplevel)
    projection = NaturalToGraphics(measure = _stub)
    iomap = print_document(projection, nothing, toplevel,
                           PrinterContext(EmptyReference(), Cell(600), Cell(400), Dict{Symbol,Any}()))
    canvas = get_iomap_output(iomap)
    label(text) = only((x, y) for (t, x, y) in placed(canvas) if t == text)
    checks() = [x for (t, x, _) in placed(canvas) if t == "\ue06c"]
    # A click as the editor gets it: the button down, the button up, and the press
    # that the gesture recognizer makes of the two. It answers what the press does.
    function press!(x, y)
        operation = nothing
        for event in (MouseDown(:left, x, y, ModifierKeys(); time = 0.0), MouseUp(:left, x, y, ModifierKeys(); time = 0.0),
                      MouseClick(:left, x, y, 1, ModifierKeys(); time = 0.0))
            change = read_intent(projection, nothing, Intent(event), iomap)
            operation = change isa Intent ? change.operation : change
            operation isa Operation && evaluate_operation(ed, operation)
        end
        operation
    end
    caret_steps() = get_reference_steps(strip_reference_types(toplevel.selection))
    # Each box stands left of its name by its own size and the label gap, and only
    # the parse box is checked.
    (px, py) = label("Parse evaluated forms")
    (sx, sy) = label("Structured forms")
    defaults = get_theme_defaults(WidgetTheme)
    offset = defaults.indicator_size + defaults.label_gap
    @test checks() == [px - offset]
    @test press!(px - 17, py + 12) isa ToggleEvaluatorOptionOperation
    @test !toplevel.parse_evaluated_forms
    # The press leaves the caret in the code, where the next key goes.
    @test caret_steps()[end] == RangeReferenceStep(0, 0) && caret_steps()[3] == FieldReferenceStep("form")
    @test press!(sx - 17, sy + 12) isa ToggleEvaluatorOptionOperation
    @test toplevel.type_structured_forms
    @test toplevel.elements[1].form isa JuliaInsertion
    @test caret_steps()[end] == RangeReferenceStep(0, 0) && caret_steps()[3] == FieldReferenceStep("form")
    # The boxes draw the new state.
    @test checks() == [sx - offset]
end

@testset "a form that holds an object runs with that very object" begin
    s = history_session("y = 1"; structured = true)
    # A circle has no notation in a line of code.
    object = GraphicsCircle(10, 10, 10)
    call = parse_natural_text(:jl, "setproperty!(x, :radius, 20)")
    call.arguments[1] = object
    whole(i) = ConcreteReference(FieldReferenceStep("elements"),
        ConcreteReference(RangeReferenceStep(i - 1, i),
            ConcreteReference(FieldReferenceStep("form"), EmptyReference())))
    clear_selection!(s.toplevel)
    s.toplevel.elements[2].form = call
    set_selection!(s.toplevel, whole(2))
    # The object prints as its label inside the code. The window draws the same
    # label (ApplicationTest.jl); a bare `NaturalToGraphics` draws a child of Julia
    # code through its shared syntax table instead, by the child's own type.
    @test print_natural_text(call) == "setproperty!(⟨GraphicsCircle⟩, :radius, 20)"
    @test s.press!(:return) isa EvaluateSelectedFormOperation
    # The call changed the object itself, not a copy.
    @test object.radius == 20
    form = s.toplevel.elements[2]
    @test !form.is_error
    @test form.form === call && call.arguments[1] === object
    # Its label is no code, so the form keeps no text and the history skips it.
    @test form.source == ""
    s.press!(:up); @test s.shown() == "y = 1"
end

@testset "a form that is an object answers that object" begin
    s = history_session("y = 1"; structured = true)
    object = GraphicsCircle(10, 10, 10)
    whole(i) = ConcreteReference(FieldReferenceStep("elements"),
        ConcreteReference(RangeReferenceStep(i - 1, i),
            ConcreteReference(FieldReferenceStep("form"), EmptyReference())))
    clear_selection!(s.toplevel)
    s.toplevel.elements[2].form = object
    set_selection!(s.toplevel, whole(2))
    # A switch of the kind of the bottom form leaves an object as it is.
    evaluate_operation(s.ed, ToggleEvaluatorOptionOperation(s.toplevel, :type_structured_forms))
    @test s.toplevel.elements[2].form === object
    @test s.press!(:return) isa EvaluateSelectedFormOperation
    @test s.toplevel.elements[2].result === object
end

@testset "state persists across forms, like a real REPL and not a sandbox" begin
    toplevel = make_insertion_document(EvaluatorToplevel)
    ed = editor(toplevel)

    toplevel.elements[1].form.value = "x = 41"
    evaluate_operation(ed, read_gesture(toplevel, enter()))
    @test length(toplevel.elements) == 2

    toplevel.elements[2].form.value = "x + 1"
    evaluate_operation(ed, read_gesture(toplevel, enter()))
    @test length(toplevel.elements) == 3
    @test occursin("42", _et_flatten(toplevel.elements[2].result))
end

@testset "an expression that throws marks the form is_error" begin
    toplevel = make_insertion_document(EvaluatorToplevel)
    toplevel.elements[1].form.value = "undefined_name_xyz123"
    evaluate_operation(editor(toplevel), read_gesture(toplevel, enter()))
    @test toplevel.elements[1].is_error
end

@testset "declines when the source is blank" begin
    toplevel = make_insertion_document(EvaluatorToplevel)
    operation = read_gesture(toplevel, enter())
    @test operation isa EvaluateSelectedFormOperation
    evaluate_operation(editor(toplevel), operation)
    # No code ran: the toplevel keeps its one empty form.
    @test length(toplevel.elements) == 1
end

@testset "opens by name" begin
    @test resolve_insertion(Document, "repl") === EvaluatorToplevel
    @test resolve_insertion(Document, "evaluator") === EvaluatorToplevel
    @test get_document_title(EvaluatorToplevel()) == "Evaluator"
end

end
end
