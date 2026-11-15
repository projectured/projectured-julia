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

@testset "the traffic light waits for the minimum green" begin
    light = _load_example(make_fsm_crossing_document_example(), :CrossingRun)
    state() = _get_state_name(light, "Light")
    @test state() == "START"

    # The dispatch of event 0 starts the machine, and the entry of CARS_GREEN
    # starts the minimum green.
    _dispatch!(light, "Light", 0)
    @test state() == "CARS_GREEN"
    @test _is_timer_scheduled(light, :min_green_timer)

    # A press during the minimum green waits for its end.
    _dispatch!(light, "Light", :E_BUTTON)
    @test state() == "CARS_GREEN"
    @test light.host.requested
    _fire_timer!(light, :min_green_timer)
    @test state() == "CARS_YELLOW"

    # A press in CARS_YELLOW changes nothing.
    _dispatch!(light, "Light", :E_BUTTON)
    @test state() == "CARS_YELLOW"
    _fire_timer!(light, :yellow_timer)
    @test state() == "ALL_RED"
    _fire_timer!(light, :all_red_timer)
    @test state() == "WALK"
    @test !light.host.requested
    _fire_timer!(light, :walk_timer)
    @test state() == "WALK_FLASHING"

    # A press while the walk signal flashes is for the next cycle.
    _dispatch!(light, "Light", :E_BUTTON)
    @test state() == "WALK_FLASHING"
    _fire_timer!(light, :flashing_timer)
    @test state() == "CARS_GREEN"
    @test light.host.requested
    _fire_timer!(light, :min_green_timer)
    @test state() == "CARS_YELLOW"

    # With no press, the cars keep green after the minimum green, and a press
    # then changes the light at once.
    for timer in (:yellow_timer, :all_red_timer, :walk_timer, :flashing_timer)
        _fire_timer!(light, timer)
    end
    @test state() == "CARS_GREEN"
    _fire_timer!(light, :min_green_timer)
    @test state() == "CARS_GREEN"
    _dispatch!(light, "Light", :E_BUTTON)
    @test state() == "CARS_YELLOW"
end

@testset "the alternating bit protocol delivers each item once" begin
    link = _load_example(make_fsm_alternating_bit_document_example(), :AlternatingBitRun)
    sender() = _get_state_name(link, "Sender")
    receiver() = _get_state_name(link, "Receiver")
    send!(data) = _dispatch!(link, "Sender", :E_SEND, data)

    # One SEND runs both machines: the frame goes to the receiver and its
    # acknowledgement comes back, each in the drain of the machine before.
    send!("a")
    @test sender() == "WAIT_SEND_1"
    @test receiver() == "WAIT_FRAME_1"
    @test link.host.delivered == ["a"]
    @test !_is_timer_scheduled(link, :retransmit_timer)

    # A lost frame: the sender waits, and its timer sends the frame again.
    link.host.drop_next_frame = true
    send!("b")
    @test sender() == "WAIT_ACK_1"
    @test link.host.delivered == ["a"]
    # A SEND before the acknowledgement is an error of the user of the component.
    @test_throws ErrorException send!("c")
    _fire_timer!(link, :retransmit_timer)
    @test sender() == "WAIT_SEND_0"
    @test receiver() == "WAIT_FRAME_0"
    @test link.host.delivered == ["a", "b"]

    # A lost acknowledgement: the receiver gets a copy of the frame, does not
    # deliver it again, and sends the acknowledgement again.
    link.host.drop_next_ack = true
    send!("c")
    @test sender() == "WAIT_ACK_0"
    @test receiver() == "WAIT_FRAME_1"
    @test link.host.delivered == ["a", "b", "c"]
    _fire_timer!(link, :retransmit_timer)
    @test sender() == "WAIT_SEND_1"
    @test receiver() == "WAIT_FRAME_1"
    @test link.host.delivered == ["a", "b", "c"]

    # A late acknowledgement changes nothing.
    _dispatch!(link, "Sender", :E_ACK, 0)
    @test sender() == "WAIT_SEND_1"
end

@testset "a TCP connection opens and closes" begin
    # A segment arrives as the embedder gives it: the classifier names its
    # event, and the dispatch gets the segment as its payload.
    function arrive!(tcp, segment)
        event = Base.invokelatest(_binding(tcp.mod, :analyse_segment), tcp.host, segment)
        _dispatch!(tcp, "Connection", event, segment)
    end
    make_segment(tcp; kwargs...) = Base.invokelatest(_binding(tcp.mod, :make_segment); kwargs...)
    timers = (:conn_estab_timer, :fin_wait_2_timer, :msl2_timer)

    # The active open and the active close.
    tcp = _load_example(make_fsm_tcp_document_example(), :TcpActiveRun)
    state() = _get_state_name(tcp, "Connection")
    sent() = tcp.host.outbox[end]
    _dispatch!(tcp, "Connection", :E_OPEN_ACTIVE)
    @test state() == "SYN_SENT"
    @test sent().syn && !sent().ack
    @test _is_timer_scheduled(tcp, :conn_estab_timer)
    arrive!(tcp, make_segment(tcp; syn = true, ack = true, sequence_number = 5000,
                              ack_number = sent().sequence_number + 1))
    @test state() == "ESTABLISHED"
    @test tcp.host.indications == ["established"]
    @test !_is_timer_scheduled(tcp, :conn_estab_timer)
    @test sent().ack && sent().ack_number == 5001
    _dispatch!(tcp, "Connection", :E_SEND, "hello")
    @test sent().data == "hello"

    _dispatch!(tcp, "Connection", :E_CLOSE)
    @test state() == "FIN_WAIT_1"
    @test sent().fin
    arrive!(tcp, make_segment(tcp; ack = true, sequence_number = 5001, ack_number = tcp.host.snd_nxt))
    @test state() == "FIN_WAIT_2"
    @test _is_timer_scheduled(tcp, :fin_wait_2_timer)
    # The FIN of the other side comes after the acknowledgement of this FIN.
    arrive!(tcp, make_segment(tcp; fin = true, ack = true, sequence_number = 5001,
                              ack_number = tcp.host.snd_nxt))
    @test state() == "TIME_WAIT"
    @test sent().ack && sent().ack_number == 5002
    _fire_timer!(tcp, :msl2_timer)
    @test state() == "CLOSED"
    @test !any(timer -> _is_timer_scheduled(tcp, timer), timers)

    # A FIN that also acknowledges this FIN: the two sides close at once.
    tcp = _load_example(make_fsm_tcp_document_example(), :TcpBothCloseRun)
    _dispatch!(tcp, "Connection", :E_OPEN_ACTIVE)
    arrive!(tcp, make_segment(tcp; syn = true, ack = true, sequence_number = 5000,
                              ack_number = sent().sequence_number + 1))
    _dispatch!(tcp, "Connection", :E_CLOSE)
    arrive!(tcp, make_segment(tcp; fin = true, ack = true, sequence_number = 5001,
                              ack_number = tcp.host.snd_nxt))
    @test state() == "TIME_WAIT"

    # The passive open and the passive close.
    tcp = _load_example(make_fsm_tcp_document_example(), :TcpPassiveRun)
    _dispatch!(tcp, "Connection", :E_OPEN_PASSIVE)
    @test state() == "LISTEN"
    arrive!(tcp, make_segment(tcp; syn = true, sequence_number = 7000))
    @test state() == "SYN_RCVD"
    @test sent().syn && sent().ack && sent().ack_number == 7001
    # An ACK of a number that this side did not send gets a reset, and the
    # state stays.
    arrive!(tcp, make_segment(tcp; ack = true, sequence_number = 7001, ack_number = tcp.host.snd_nxt + 10))
    @test state() == "SYN_RCVD"
    @test sent().rst
    arrive!(tcp, make_segment(tcp; ack = true, sequence_number = 7001, ack_number = tcp.host.snd_nxt))
    @test state() == "ESTABLISHED"
    arrive!(tcp, make_segment(tcp; fin = true, ack = true, sequence_number = 7001,
                              ack_number = tcp.host.snd_nxt))
    @test state() == "CLOSE_WAIT"
    @test sent().ack && sent().ack_number == 7002
    _dispatch!(tcp, "Connection", :E_CLOSE)
    @test state() == "LAST_ACK"
    @test sent().fin
    arrive!(tcp, make_segment(tcp; ack = true, sequence_number = 7002, ack_number = tcp.host.snd_nxt))
    @test state() == "CLOSED"
    @test !any(timer -> _is_timer_scheduled(tcp, timer), timers)
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
