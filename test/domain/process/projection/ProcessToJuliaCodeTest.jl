function test_process_to_julia_code()
@testset "ProcessToJuliaCode" begin

_binding(mod::Module, name::Symbol) = Base.invokelatest(getfield, mod, name)

# Realized code is loaded as source, not as a quoted expression, so what the
# test runs is exactly the text an export would have written. The prelude is
# whatever the process calls that is not part of it.
function _load_realized(model, name::Symbol, prelude::AbstractString = "")
    mod = Module(name)
    isempty(prelude) || Base.include_string(mod, prelude)
    Base.include_string(mod, realize_process_text(model))
    mod
end

# ── shape ────────────────────────────────────────────────────────────────
@testset "the realized function is complete and parses" begin
    text = realize_process_text(make_process_drain_document_example())

    @test occursin("function drain(queue)", text)
    @test occursin("for item in queue", text)
    @test occursin("continue", text)
    @test occursin("return sent", text)
    # The author's code is spliced verbatim, never stringified and rewritten.
    @test occursin("send!(item)", text)
    @test occursin("sent = sent + 1", text)
    # Prose does not survive: the julia domain has no comment node, so a
    # description lives in the notation and the diagram, not here.
    @test !occursin("hand it to the medium", text)

    @test (Meta.parseall(text); true)
end

# ── unrefined nodes ──────────────────────────────────────────────────────
# An informal box realizes to something that throws, not to nothing. A
# process that silently skipped its unwritten steps would lie about what it
# does.
@testset "an unrefined node realizes to an error" begin
    text = realize_process_text(make_process_transmit_document_example())
    @test occursin("error(\"unrefined step: wait a binary exponential backoff\")", text)
    @test (Meta.parseall(text); true)

    @test !is_executable(make_process_transmit_document_example())
    @test is_executable(make_process_drain_document_example())

    # A hole in a condition slot is an expression, so it still parses.
    holed = ProcessModel("holed";
                         body = ProcessSequence([ProcessDecision(nothing),
                                                 ProcessWhile(nothing),
                                                 ProcessForeach(nothing, nothing)]))
    holed_text = realize_process_text(holed)
    @test occursin("error(\"unrefined condition\")", holed_text)
    @test occursin("error(\"unrefined iterable\")", holed_text)
    @test (Meta.parseall(holed_text); true)
end

# ── it runs ──────────────────────────────────────────────────────────────
# The part a text assertion cannot check: the realized function is called and
# its result and side effects are what the process says they should be.
@testset "realized code runs" begin
    mod = _load_realized(make_process_drain_document_example(), :ProcessDrainProbe,
                         "const SENT = Any[]\nsend!(x) = push!(SENT, x)\n")
    drain = _binding(mod, :drain)

    @test Base.invokelatest(drain, Any[1, 2, nothing, 3]) == 3
    @test _binding(mod, :SENT) == Any[1, 2, 3]          # `continue` skipped the hole
    @test Base.invokelatest(drain, Any[]) == 0          # an empty queue sends nothing
    @test _binding(mod, :SENT) == Any[1, 2, 3]
end

@testset "loops, decisions and jumps run to the contract" begin
    # A while loop with a break, an else branch, and an early return — the control flow a
    # sequence of steps cannot express.
    classify = ProcessModel("classify";
        parameters = [parse_julia("n")],
        body = ProcessSequence([
            ProcessStep(""; action = parse_julia("seen = 0")),
            ProcessWhile(parse_julia("true");
                body = ProcessSequence([
                    ProcessDecision(parse_julia("seen >= n");
                        then_branch = ProcessSequence([ProcessBreak()]),
                        else_branch = ProcessSequence([
                            ProcessStep(""; action = parse_julia("seen = seen + 1"))])),
                    ProcessDecision(parse_julia("seen == 7");
                        then_branch = ProcessSequence([ProcessReturn(parse_julia(":lucky"))])),
                ])),
            ProcessReturn(parse_julia("seen")),
        ]))

    text = realize_process_text(classify)
    @test occursin("else", text)
    @test (Meta.parseall(text); true)

    mod = _load_realized(classify, :ProcessClassifyProbe)
    f = _binding(mod, :classify)
    @test Base.invokelatest(f, 0) == 0        # the loop breaks immediately
    @test Base.invokelatest(f, 3) == 3        # counts up, then breaks
    @test Base.invokelatest(f, 5) == 5        # never reaches the early return
    @test Base.invokelatest(f, 7) === :lucky  # the early return leaves the loop
    @test Base.invokelatest(f, 10) === :lucky # ...and it is reached on the way up

    # An unrefined step throws rather than passing silently.
    unrefined = ProcessModel("unrefined";
        body = ProcessSequence([ProcessStep("think about it"),
                                ProcessReturn(parse_julia(":done"))]))
    umod = _load_realized(unrefined, :ProcessUnrefinedProbe)
    @test_throws Exception Base.invokelatest(_binding(umod, :unrefined))
end

# ── it is a document, not a string ───────────────────────────────────────
@testset "realization is document to document" begin
    model = make_process_drain_document_example()
    realized = realize_process(model)
    @test realized isa JuliaFunction
    # The embedded action is the very same document object, not a copy: this
    # is what "spliced verbatim" means.
    action = model.body.steps[1].action
    @test realized.body.statements[1] === action
end

end # @testset "ProcessToJuliaCode"
end # test_process_to_julia_code
