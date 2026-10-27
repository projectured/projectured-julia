# The examples run. Each example component is generated, loaded on the
# stand-in runtime of `FsmToJuliaCodeTest.jl`, and played with a short list of
# events and timer expiries. The test reads the state and the variables after
# each step, so an example that only prints well fails here.

function test_fsm_example_run()
@testset "the examples run" begin

@testset "the toggle turns the lamp on and off" begin
    lamp = _load_example(make_fsm_toggle_document_example(), :ToggleRun)
    @test _get_state_name(lamp, "Toggle") == "OFF"

    _dispatch!(lamp, "Toggle", :E_PRESSED)
    @test _get_state_name(lamp, "Toggle") == "ON"
    @test lamp.host.switch_ons == 1
    @test _is_timer_scheduled(lamp, :off_timer)

    # A press turns the lamp off and cancels the timer.
    _dispatch!(lamp, "Toggle", :E_PRESSED)
    @test _get_state_name(lamp, "Toggle") == "OFF"
    @test !_is_timer_scheduled(lamp, :off_timer)

    # When nobody presses, the timer turns the lamp off.
    _dispatch!(lamp, "Toggle", :E_PRESSED)
    @test lamp.host.switch_ons == 2
    _fire_timer!(lamp, :off_timer)
    @test _get_state_name(lamp, "Toggle") == "OFF"
    @test lamp.host.switch_ons == 2
end

end # @testset "the examples run"
end # test_fsm_example_run

# ── the harness ──────────────────────────────────────────────────────────────

# A generated example, loaded on the stand-in runtime, with one host.
struct _LoadedExample
    mod::Module
    host::Any
end

function _load_example(component, name::Symbol)
    # An embedder names its runtime in the `usings`, as the probe component does.
    push!(component.usings, JuliaUsing(:using, "..ProbeRuntime"))
    mod = _load_generated(component, name)
    _LoadedExample(mod, Base.invokelatest(_binding(mod, Symbol(component.name, "State"))))
end

# Dispatch `event` to `machine`: the name of an event constant, such as
# `:E_PRESSED`, or `0` for a dispatch with no event.
function _dispatch!(loaded::_LoadedExample, machine::AbstractString, event, payload = nothing)
    code = event isa Symbol ? _binding(loaded.mod, event) : Int32(event)
    Base.invokelatest(_binding(loaded.mod, Symbol(lowercase(machine), "_dispatch!")),
                      nothing, loaded.host, code, payload)
end

# The name of the current state of `machine`.
function _get_state_name(loaded::_LoadedExample, machine::AbstractString)
    names = _binding(loaded.mod, Symbol(uppercase(machine), "_STATE_NAMES"))
    names[Int(getfield(loaded.host, Symbol("fsm_", lowercase(machine))).state) + 1]
end

_is_timer_scheduled(loaded::_LoadedExample, timer::Symbol) = getfield(loaded.host, timer).active

# Fire a scheduled timer as the event loop of the real runtime does: clear the
# timer, then call its action with its argument.
function _fire_timer!(loaded::_LoadedExample, timer::Symbol)
    handle = getfield(loaded.host, timer)
    handle.active || error("the timer $timer is not scheduled")
    handle.active = false
    Base.invokelatest(handle.action, nothing, handle.argument)
end
