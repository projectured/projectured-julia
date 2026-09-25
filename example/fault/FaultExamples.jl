# Fragment of `ProjecturedFaultExample` — one runnable example per fault
# category, so a person can watch each barrier work. Run them from the REPL
# like any other example:
#
#     run_example(fault_print_example)     # one mark, siblings draw, one panel line
#     run_example(fault_read_example)      # press F8: the gesture dies, the editor lives
#     run_example(fault_evaluate_example)  # press F9: the operation throws, the editor repairs
#     run_example(fault_map_example)       # select the broken value: the mappers decline
#     run_fault_device_example()           # the backend breaks mid-run; the breaker degrades it
#     run_fault_tool_example()             # a tool throws; the same panel reports it
#
# The four constants stay OUT of the global example registry on purpose: each
# one throws by design, and a sweep that drives every registered example
# would drive into the throw. They run by value, exactly as
# `make_dvdrental_relationship_example()` does.

# The value the demos break on. Everything else in the document is healthy,
# which is what makes the containment visible.
const BROKEN_VALUE = "broken on purpose"

"""
    make_fault_demo_document_example() -> JsonObject

Three entries; the second holds [`BROKEN_VALUE`](@ref). A fault contained to
that one node leaves the first and third drawn.
"""
make_fault_demo_document_example() = JsonObject(
    "first"  => JsonString("a healthy value"),
    "second" => JsonString(BROKEN_VALUE),
    "third"  => JsonString("another healthy value"),
)

# ── The stage that breaks on purpose ─────────────────────────────────────────

"""
    BrokenStageProjection(inner, site)

A transparent wrapper over one pipeline stage that throws in exactly one
place, named by `site`:

- `:print`    — the printer throws for the node holding [`BROKEN_VALUE`](@ref).
- `:read`     — the reader throws on the F8 key.
- `:evaluate` — the reader answers a [`ThrowFromEvaluationOperation`](@ref)
                on the F9 key, and the throw happens when the editor applies it.
- `:map`      — both reference mappers throw for the broken node.
- `:none`     — nothing throws; the wrapper is a pass-through (the device and
                tool runners use it).

Wrap it in a `FaultCatchingProjection` with a `substitute`, per node, and the
fault stands as one mark while the siblings draw.
"""
struct BrokenStageProjection <: Projection
    inner::Projection
    site::Symbol
end

_is_broken_value(input) = input isa JsonString && input.value == BROKEN_VALUE

_is_key(gesture, key::Symbol) = gesture isa KeyDown && gesture.key === key

function ProjectionModule.print_document(p::BrokenStageProjection, recursion, input, context)
    p.site === :print && _is_broken_value(input) && error("broken on purpose (print)")
    print_document(p.inner, recursion, input, context)
end

function ProjectionModule.read_intent(p::BrokenStageProjection, recursion, change::Intent, iomap)
    p.site === :read && _is_key(change.gesture, :f8) && error("broken on purpose (read)")
    p.site === :evaluate && _is_key(change.gesture, :f9) &&
        return Intent(change.gesture, ThrowFromEvaluationOperation())
    read_intent(p.inner, recursion, change, iomap)
end

function ProjectionModule.map_reference_forward(p::BrokenStageProjection, iomap, reference)
    p.site === :map && _is_broken_value(get_iomap_input(iomap)) &&
        error("broken on purpose (map forward)")
    map_reference_forward(p.inner, iomap, reference)
end

function ProjectionModule.map_reference_backward(p::BrokenStageProjection, iomap, reference)
    p.site === :map && _is_broken_value(get_iomap_input(iomap)) &&
        error("broken on purpose (map backward)")
    map_reference_backward(p.inner, iomap, reference)
end

"""
    ThrowFromEvaluationOperation()

Thrown when the editor applies it, which is the `:evaluate` category: the
operation barrier catches, repairs the editor, and the log shows the line.
"""
struct ThrowFromEvaluationOperation <: Operation end

OperationModule.evaluate_operation(editor, ::ThrowFromEvaluationOperation) =
    error("broken on purpose (evaluate)")

"""
    make_fault_demo_projection_example(site; measure = FontFileMeasure())

The standard JSON pipeline with the broken stage at every node: the barrier
and its `FaultToSyntax` substitute wrap `BrokenStageProjection` over
`JsonToSyntax`, so a fault stands in one node's slot and the rest of the
tree draws.
"""
make_fault_demo_projection_example(site::Symbol; measure = FontFileMeasure()) =
    ChainingProjection(
        RecursiveProjection(FaultCatchingProjection(
            inner = BrokenStageProjection(JsonToSyntax(), site),
            substitute = FaultToSyntax())),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure = measure),
    )

const fault_print_example = Example("fault_print",
    make_fault_demo_document_example, () -> make_fault_demo_projection_example(:print))
const fault_read_example = Example("fault_read",
    make_fault_demo_document_example, () -> make_fault_demo_projection_example(:read))
const fault_evaluate_example = Example("fault_evaluate",
    make_fault_demo_document_example, () -> make_fault_demo_projection_example(:evaluate))
const fault_map_example = Example("fault_map",
    make_fault_demo_document_example, () -> make_fault_demo_projection_example(:map))

# ── The device category ──────────────────────────────────────────────────────

"""
    BrokenWriteBackend(inner)

Delegates every seam to `inner`; `write_to_devices` throws while `broken`
holds. The device barrier counts the consecutive failures and degrades the
seam at its limit — the screen freezes on the last good frame, and Escape
still quits because `read_from_devices` keeps running.
"""
mutable struct BrokenWriteBackend <: Backend
    inner::Backend
    broken::Bool
end

BrokenWriteBackend(inner::Backend) = BrokenWriteBackend(inner, false)

BackendModule.initialize_backend!(b::BrokenWriteBackend) = initialize_backend!(b.inner)
BackendModule.quit_backend!(b::BrokenWriteBackend) = quit_backend!(b.inner)
BackendModule.measure_text(b::BrokenWriteBackend, text, font) = measure_text(b.inner, text, font)
BackendModule.read_from_devices(b::BrokenWriteBackend, devices) = read_from_devices(b.inner, devices)
BackendModule.open_native_windows!(b::BrokenWriteBackend, document) = open_native_windows!(b.inner, document)
BackendModule.configure_devices!(b::BrokenWriteBackend, devices) = configure_devices!(b.inner, devices)
BackendModule.get_display_size(b::BrokenWriteBackend; display::Integer = 0) =
    get_display_size(b.inner; display = display)
BackendModule.get_pointer_position(b::BrokenWriteBackend) = get_pointer_position(b.inner)
BackendModule.wait_for_input(b::BrokenWriteBackend, devices, timeout_seconds) =
    wait_for_input(b.inner, devices, timeout_seconds)
BackendModule.wake_backend!(b::BrokenWriteBackend) = wake_backend!(b.inner)

BackendModule.write_to_devices(b::BrokenWriteBackend, devices, output) =
    b.broken ? error("broken on purpose (device)") :
               write_to_devices(b.inner, devices, output)

"""
    run_fault_device_example(; backend = nothing, break_after = 3.0)

Run the healthy demo document behind a [`BrokenWriteBackend`](@ref); after
`break_after` seconds every paint throws. Interact — move the pointer, press
keys — and after the limit of consecutive failures the device barrier
degrades the seam: the screen freezes for good, the console reports the
fault, and Escape still quits.
"""
function run_fault_device_example(; backend = nothing, break_after::Real = 3.0)
    broken_backend = BrokenWriteBackend(something(backend, default_backend()))
    editor = make_example_editor([make_fault_demo_document_example()],
                                 [make_fault_demo_projection_example(:none)],
                                 ["fault_device"];
                                 backend = broken_backend)
    Timer(_ -> (broken_backend.broken = true), break_after)
    run_editor!(editor)
end

# ── The tool category ────────────────────────────────────────────────────────

"""
    run_fault_tool_example(; backend = nothing)

Run the healthy demo document, and two seconds in, drive one scripted agent
turn that calls a registered tool that throws. The agent loop's tool barrier
catches it, answers the model an error text, and the fault reaches the same
log panel as every other category.
"""
function run_fault_tool_example(; backend = nothing)
    editor = make_example_editor([make_fault_demo_document_example()],
                                 [make_fault_demo_projection_example(:none)],
                                 ["fault_tool"];
                                 backend = something(backend, default_backend()))
    @async begin
        sleep(2.0)
        register_tool!(editor.tools,
            Tool("break_on_purpose", "throws, on purpose", NamedTuple[],
                 (target, arguments) -> error("broken on purpose (tool)")))
        # Two rounds: the call, then the round that reads the
        # error text back and ends the turn.
        llm = ScriptedLlm([
            make_scripted_turn(
                make_scripted_run(""; tool_name = "break_on_purpose");
                stop_reason = "tool_use"),
            make_scripted_turn(
                make_scripted_say("the tool broke, on purpose");
                stop_reason = "end_turn"),
        ])
        agent = Agent(llm, editor.tools)
        run_turn!(agent, editor; messages = () -> LlmMessage[],
                  on_event = _ -> nothing)
    end
    run_editor!(editor)
end
