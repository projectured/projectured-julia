# The evaluator toplevel is a persistent REPL: a person types `repl` into an
# empty tab, types a Julia expression into the fresh form it opens with, and
# ENTER evaluates it in place — appending a fresh empty form and keeping
# the interpreter's own state, so a variable one form binds is visible from the
# next. That persistence is what tells it apart from a one-shot sandbox.

using Test
using ProjecturedKernel.ToolModule: ToolSet

# `execute_julia_code` reads the `tools` field of an editor.
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

_stub(t, f) = (max(1, length(t)) * 10, 24)

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
enter() = KeyDown(:return, ModifierKeys())
shift_enter() = KeyDown(:return, ModifierKeys(shift = true))

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

@testset "it draws through NaturalToGraphics" begin
    toplevel = make_insertion_document(EvaluatorToplevel)
    text = render(toplevel)
    @test !occursin("no natural rendering", text)
    # The toplevel draws its one form and nothing more, and not a canvas drawn as
    # a tree of its fields. A fresh form draws its prompt, and no result.
    @test text == render(toplevel.elements[1])
    @test first(split(text)) == ">"
    @test !occursin("=", text)
end

@testset "the prompts stand in a column of their own, and the code and the result beside it" begin
    toplevel = make_insertion_document(EvaluatorToplevel)
    toplevel.elements[1].form.value = "1 + 1"
    evaluate_operation(editor(toplevel), read_gesture(toplevel, enter()))
    texts = placed(print_natural(toplevel))
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
    # The pane is as tall as the offer, and it shows the end: the prompt of the
    # fresh form is in view, and the prompt of the first form is above it.
    @test Int(canvas.h) == 120
    @test 0 <= last(prompts_y()) < 120
    @test first(prompts_y()) < 0
    # A wheel turn toward the start takes the view off the end, and moves the
    # forms down by one line, which is 24 pixels with this measure.
    at_end = last(prompts_y())
    change = read_intent(projection, nothing, Intent(MouseScroll(0, 1, 50, 50)), iomap)
    evaluate_operation(ed, change.operation)
    @test toplevel.follow_end == false
    @test last(prompts_y()) == at_end + 24
    # An evaluation brings the end back into view, where the next key goes.
    toplevel.elements[length(toplevel.elements)].form.value = "9"
    evaluate_operation(ed, read_gesture(toplevel, enter()))
    @test toplevel.follow_end == true
    @test 0 <= last(prompts_y()) < 120
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
    # word for word.
    @test text == "Evaluator " * render(toplevel.elements[1])
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
    @test read_gesture(toplevel, KeyDown(:return, ModifierKeys(alt = true))) === nothing
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
