function test_process()
@testset "ProcessDocuments" begin

# ── nodes ────────────────────────────────────────────────────────────────
step = ProcessStep("prepare"; action = juliaparse("x = encode(frame)"))
@test step.description == "prepare"
@test step.action !== nothing
step.description = "encode"
@test step.description == "encode"

# An informal box: description, no code yet.
informal = ProcessStep("binary exponential backoff")
@test informal.action === nothing

# A code-only step has an empty description rather than a missing one.
code_only = ProcessStep(""; action = juliaparse("attempts += 1"))
@test code_only.description == ""

@test ProcessBreak() isa ProcessDocument
@test ProcessContinue() isa ProcessDocument
@test ProcessReturn().value === nothing
@test ProcessReturn(juliaparse(":sent")).value !== nothing

# ── structure ────────────────────────────────────────────────────────────
sequence = ProcessSequence([step, informal])
@test length(sequence.steps) == 2
@test sequence.steps[1] === step
push!(sequence.steps, code_only)
@test length(sequence.steps) == 3

decision = ProcessDecision(juliaparse("carrier_free()");
                           then_branch = ProcessSequence([ProcessBreak()]))
@test decision.condition !== nothing
@test decision.else_branch === nothing            # no else branch at all

loop = ProcessWhile(juliaparse("attempts < 4"); body = ProcessSequence([decision]))
@test loop.condition !== nothing

foreach_node = ProcessForeach(juliaparse("item"), juliaparse("queue");
                              body = ProcessSequence([code_only]))
@test foreach_node.variable !== nothing
@test foreach_node.iterable !== nothing

model = ProcessModel("transmit"; parameters = [juliaparse("frame")],
                     body = ProcessSequence([sequence, loop]))
@test model.name == "transmit"
@test length(model.parameters) == 1

# ── the tree walk ────────────────────────────────────────────────────────
# Document order: a node before its children, children left to right.
nodes = process_nodes(model)
@test nodes[1] === model
@test nodes[2] === model.body
@test nodes[3] === sequence
@test nodes[4] === step
@test model in nodes && loop in nodes && decision in nodes

# Embedded Julia is opaque: a condition contributes no node.
@test !any(n -> n === decision.condition, nodes)
@test isempty(process_children(step))

# index ↔ node round-trip, by identity
for (index, node) in enumerate(nodes)
    @test node_index(model, node) == index
    @test node_at(model, index) === node
end
@test node_index(model, ProcessStep("stranger")) == 0
@test node_at(model, 0) === nothing
@test node_at(model, length(nodes) + 1) === nothing

# A placeholder is a node — dropping it would shift every later index.
placeholder = ProcessInsertion()
push!(sequence.steps, placeholder)
@test node_index(model, placeholder) > 0
@test length(process_nodes(model)) == length(nodes) + 1
pop!(sequence.steps)

# ── bodies ───────────────────────────────────────────────────────────────
@test isempty(body_steps(nothing))
@test length(body_steps(ProcessSequence([step]))) == 1
@test body_steps(step) == Any[step]                # a bare node is a one-node body

# ── executability ────────────────────────────────────────────────────────
@test !is_executable(model)                        # `informal` has no action
@test informal in unrefined_nodes(model)
informal.action = juliaparse("sleep(backoff())")
@test is_executable(model)

bare_decision = ProcessDecision(nothing)
@test bare_decision in unrefined_nodes(bare_decision)

# ── insertion kit ────────────────────────────────────────────────────────
@test ProcessNothing() isa ProcessDocument
@test ProcessInsertion("proc") isa ProcessDocument
@test make_insertion_document(ProcessStep) isa ProcessStep
@test make_insertion_document(ProcessModel).selection !== nothing
@test insertable(ProcessDecision)
@test !insertable(ProcessNothing)

end # testset
end # function
