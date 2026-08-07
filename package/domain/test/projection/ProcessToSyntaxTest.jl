function test_process_to_syntax()
@testset "ProcessToSyntax" begin

_render(doc) = print_document(
    ChainingProjection(RecursiveProjection(ProcessToSyntax()),
                       RecursiveProjection(SyntaxToText()),
                       RecursiveProjection(TextToString())),
    doc).output

# ── the notation ─────────────────────────────────────────────────────────
@testset "notation" begin
    text = _render(make_process_transmit_document_example())

    # Header: name and the embedded parameter list.
    @test occursin("process transmit(medium, payload, max_attempts)", text)

    # A described step keeps its prose; a code-only step drops the quotes
    # entirely rather than rendering an empty pair.
    @test occursin("step \"prepare\" / frame = encode(payload)", text)
    @test occursin("step / attempts = 0", text)
    @test !occursin("step \"\"", text)

    # An informal step is description-only — no separator, no action.
    @test occursin("step \"wait a binary exponential backoff\"", text)
    @test !occursin("wait a binary exponential backoff\" /", text)

    # Control flow reads as Julia does, minus the `end`s: the body is an
    # indented run of lines.
    @test occursin("while true", text)
    @test occursin("if carrier_free(medium)", text)
    @test !occursin("end", text)
    @test occursin("\n  step \"prepare\"", text)          # body of the process
    @test occursin("\n    if carrier_free(medium)", text) # body of the loop
    @test occursin("\n      return :sent", text)          # body of the decision

    # Jumps.
    @test occursin("break", text)
    @test occursin("return :sent", text)
    @test occursin("return :failed", text)

    drain = _render(make_process_drain_document_example())
    @test occursin("process drain(queue)", drain)
    @test occursin("for item in queue", drain)
    @test occursin("continue", drain)
    @test occursin("step \"hand it to the medium\" / send!(item)", drain)
    @test occursin("return sent", drain)
end

# ── else branches ────────────────────────────────────────────────────────
@testset "else" begin
    # No else branch at all: the keyword does not appear.
    without = _render(ProcessDecision(juliaparse("ready");
                                      then_branch = ProcessSequence([ProcessBreak()])))
    @test occursin("if ready", without)
    @test !occursin("else", without)

    # With one, `else` sits on its own line between the two indented bodies.
    with = _render(ProcessDecision(juliaparse("ready");
                                   then_branch = ProcessSequence([ProcessBreak()]),
                                   else_branch = ProcessSequence([ProcessContinue()])))
    @test occursin("\nelse", with)
    @test occursin("  break", with)
    @test occursin("  continue", with)
end

# ── unrefined holes ──────────────────────────────────────────────────────
# A hole renders a muted marker rather than nothing at all: an empty line
# would leave the author no idea what is missing, and no caret to fix it.
@testset "unrefined" begin
    @test occursin("if <condition>", _render(ProcessDecision(nothing)))
    @test occursin("while <condition>", _render(ProcessWhile(nothing)))

    empty_foreach = _render(ProcessForeach(nothing, nothing))
    @test occursin("for <variable> in <iterable>", empty_foreach)

    # A fresh step has neither description nor action, so it renders the
    # description leaf with its hint — somewhere to start typing.
    @test occursin("describe this step", _render(ProcessStep("")))
end

# ── typing into the notation's own leaves ────────────────────────────────
# Deliberately julia-free: `test_typein(process_example)` inherits the julia
# domain's name-leaf caret gap (`test_typein(julia_example)` is 0 of 84 on a
# clean tree), which would drown out this domain's own result. What is checked
# here is that every caret the *process* notation introduces accepts a
# keystroke.
@testset "typein" begin
    document = ProcessModel("transmit";
                            body = ProcessSequence([ProcessStep("prepare"),
                                                    ProcessStep("send it"),
                                                    ProcessBreak()]))
    test_typein("process_notation", document, make_process_projection_example())
end

# ── reactivity ───────────────────────────────────────────────────────────
# The printer reads document cells inside cells, so an edit shows up in a
# re-render of the same projection rather than needing a fresh one.
@testset "reactive" begin
    step = ProcessStep("first"; action = juliaparse("f()"))
    model = ProcessModel("m"; body = ProcessSequence([step]))
    projection = ChainingProjection(RecursiveProjection(ProcessToSyntax()),
                                    RecursiveProjection(SyntaxToText()),
                                    RecursiveProjection(TextToString()))
    @test occursin("step \"first\"", print_document(projection, model).output)
    step.description = "second"
    @test occursin("step \"second\"", print_document(projection, model).output)
    model.name = "renamed"
    @test occursin("process renamed(", print_document(projection, model).output)
end

end # testset
end # function
