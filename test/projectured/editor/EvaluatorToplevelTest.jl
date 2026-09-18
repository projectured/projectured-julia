# The evaluator toplevel is a persistent REPL: a person types `repl` into an
# empty tab, types a Julia expression into the fresh form it opens with, and
# ALT+ENTER evaluates it in place — appending a fresh empty form and keeping
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

render(document) =
    drawn(get_iomap_output(print_document(NaturalToGraphics(measure = _stub), nothing, document,
                           PrinterContext(EmptyReference(), Cell(600), Cell(400), Dict{Symbol,Any}()))))

editor(t) = _EvaluatorToplevelMockEditor(t, ToolSet())
alt_enter() = KeyDown(:enter, ModifierKeys(alt = true))

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
end

@testset "ALT+ENTER evaluates the form the caret is in" begin
    toplevel = make_insertion_document(EvaluatorToplevel)
    toplevel.elements[1].form.value = "1 + 1"

    operation = read_gesture(toplevel, alt_enter())
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
end

@testset "state persists across forms, like a real REPL and not a sandbox" begin
    toplevel = make_insertion_document(EvaluatorToplevel)
    ed = editor(toplevel)

    toplevel.elements[1].form.value = "x = 41"
    evaluate_operation(ed, read_gesture(toplevel, alt_enter()))
    @test length(toplevel.elements) == 2

    toplevel.elements[2].form.value = "x + 1"
    evaluate_operation(ed, read_gesture(toplevel, alt_enter()))
    @test length(toplevel.elements) == 3
    @test occursin("42", _et_flatten(toplevel.elements[2].result))
end

@testset "an expression that throws marks the form is_error" begin
    toplevel = make_insertion_document(EvaluatorToplevel)
    toplevel.elements[1].form.value = "undefined_name_xyz123"
    evaluate_operation(editor(toplevel), read_gesture(toplevel, alt_enter()))
    @test toplevel.elements[1].is_error
end

@testset "declines when the source is blank" begin
    toplevel = make_insertion_document(EvaluatorToplevel)
    operation = read_gesture(toplevel, alt_enter())
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
