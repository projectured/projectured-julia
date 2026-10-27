# ── Fsm domain examples ─────────────────────────────────────────────────────
#
# Four components, from small to large:
#
# - the toggle: a lamp with a button and a timer;
# - the crossing: a traffic light with a button for the pedestrians, which is
#   also the diagram example;
# - the alternating bit protocol: two machines in one component;
# - the TCP connection state machine (RFC 793), the registered `fsm` example:
#   twelve states, the three event families (application commands,
#   segment-derived events, timeouts), guards over extended state, entry
#   actions, guard-dependent targets and the `:ignore` unhandled policy — the
#   machine INET builds by hand out of nested switches, expressed as a document.
#
# Each component runs as generated code with no simulator: its `helpers` define
# every function that its code calls, apart from the runtime that an embedder
# supplies (`Fsm`, `schedule_timer!`, `fsm_defer!` and the others of fsm.md).
#
# Embedded guards and actions are real Julia subtrees, written here as source
# and parsed once (`parse_julia`) rather than hand-assembled node by node.

# Atomic documents for the catalog.
make_fsm_variable_document_example()   = FsmVariable("num_retries"; default = parse_julia("0"))
make_fsm_timer_document_example()      = FsmTimer("tx_timer")
make_fsm_event_document_example()      = FsmEvent("UPPER_PACKET")
make_fsm_state_document_example()      = FsmState("IDLE")
make_fsm_transition_document_example() = FsmTransition()
make_fsm_insertion_document_example()  = FsmInsertion()

function make_fsm_machine_document_example()
    idle = make_fsm_state_document_example()
    on = FsmState("ON")
    push!(idle.transitions, FsmTransition(trigger = make_fsm_event_document_example(), target = on))
    FsmMachine("Toggle"; initial = idle, states = [idle, on])
end

make_fsm_component_document_example() =
    FsmComponent("Toggle";
        variables = [make_fsm_variable_document_example()],
        events    = [make_fsm_event_document_example()],
        machines  = [make_fsm_machine_document_example()])

"""
A lamp with a button: the smallest complete component. `PRESSED` turns the
lamp on and off, and the lamp turns itself off after `AUTO_OFF_TIME` seconds.
The entry of `ON` counts the switch-ons and starts the timer, and a press in
`ON` cancels it.
"""
function make_fsm_toggle_document_example()
    pressed = FsmEvent("PRESSED")
    off_timer = FsmTimer("off_timer")

    off = FsmState("OFF")
    on = FsmState("ON"; entry = parse_julia("""
        m.switch_ons = m.switch_ons + 1
        schedule_timer!(ctx, AUTO_OFF_TIME, m.module_id, m.off_timer, expire_off_timer!, m)
        """))

    push!(off.transitions, FsmTransition(trigger = pressed, target = on))
    push!(on.transitions, FsmTransition(trigger = pressed,
                                        action = parse_julia("cancel_timer!(ctx, m.off_timer)"),
                                        target = off))
    push!(on.transitions, FsmTransition(trigger = off_timer, target = off))

    machine = FsmMachine("Toggle"; initial = off, states = [off, on])

    FsmComponent("Toggle";
        variables = [FsmVariable("module_id"; type = parse_julia("Int"), default = parse_julia("0")),
                     FsmVariable("switch_ons"; type = parse_julia("Int"), default = parse_julia("0"))],
        timers = [off_timer],
        events = [pressed],
        machines = [machine],
        helpers = [parse_julia("const AUTO_OFF_TIME = 60.0")])
end

"""
A traffic light with a button for the pedestrians. The cars have green until a
pedestrian presses the button, and for at least `MIN_GREEN_TIME` seconds. Then
the light goes through yellow and all red to walk, flashes, and gives the cars
green again.

`min_green_timer` is no trigger: the condition-only transition of `CARS_GREEN`
reads it with `is_scheduled`, so the light changes at the press when the minimum
green is over, and at the end of the minimum green when a press came before.
Each other timer is the trigger of the timeout that ends its state.
"""
function make_fsm_crossing_document_example()
    button = FsmEvent("BUTTON")
    min_green_timer = FsmTimer("min_green_timer")
    yellow_timer = FsmTimer("yellow_timer")
    all_red_timer = FsmTimer("all_red_timer")
    walk_timer = FsmTimer("walk_timer")
    flashing_timer = FsmTimer("flashing_timer")

    start = FsmState("START")
    cars_green = FsmState("CARS_GREEN"; entry = parse_julia(
        "start_timer!(ctx, m, m.min_green_timer, MIN_GREEN_TIME, expire_min_green_timer!)"))
    cars_yellow = FsmState("CARS_YELLOW"; entry = parse_julia(
        "start_timer!(ctx, m, m.yellow_timer, YELLOW_TIME, expire_yellow_timer!)"))
    all_red = FsmState("ALL_RED"; entry = parse_julia(
        "start_timer!(ctx, m, m.all_red_timer, ALL_RED_TIME, expire_all_red_timer!)"))
    walk = FsmState("WALK"; entry = parse_julia("""
        m.requested = false
        start_timer!(ctx, m, m.walk_timer, WALK_TIME, expire_walk_timer!)
        """))
    walk_flashing = FsmState("WALK_FLASHING"; entry = parse_julia(
        "start_timer!(ctx, m, m.flashing_timer, FLASHING_TIME, expire_flashing_timer!)"))

    tr(state; kwargs...) = push!(state.transitions, FsmTransition(; kwargs...))

    # The entry of the initial state does not run at startup. The dispatch of
    # event 0 that starts the machine fires this transition, so the entry of
    # CARS_GREEN starts the minimum green.
    tr(start, target = cars_green)
    tr(cars_green, trigger = button, action = parse_julia("m.requested = true"))
    tr(cars_green, guard = parse_julia("m.requested && !is_scheduled(m.min_green_timer)"),
                   target = cars_yellow)
    tr(cars_yellow, trigger = yellow_timer, target = all_red)
    tr(all_red, trigger = all_red_timer, target = walk)
    tr(walk, trigger = walk_timer, target = walk_flashing)
    # A press while the walk signal flashes is for the next cycle.
    tr(walk_flashing, trigger = button, action = parse_julia("m.requested = true"))
    tr(walk_flashing, trigger = flashing_timer, target = cars_green)

    # A press in CARS_YELLOW, ALL_RED or WALK changes nothing.
    machine = FsmMachine("Light"; initial = start,
                         states = [start, cars_green, cars_yellow, all_red, walk, walk_flashing],
                         on_unhandled = :ignore)

    FsmComponent("Crossing";
        variables = [FsmVariable("module_id"; type = parse_julia("Int"), default = parse_julia("0")),
                     FsmVariable("requested"; type = parse_julia("Bool"), default = parse_julia("false"))],
        timers = [min_green_timer, yellow_timer, all_red_timer, walk_timer, flashing_timer],
        events = [button],
        machines = [machine],
        helpers = [
            parse_julia("const MIN_GREEN_TIME = 20.0"),
            parse_julia("const YELLOW_TIME = 3.0"),
            parse_julia("const ALL_RED_TIME = 2.0"),
            parse_julia("const WALK_TIME = 10.0"),
            parse_julia("const FLASHING_TIME = 5.0"),
            parse_julia("start_timer!(ctx, m, timer, delay, action) = schedule_timer!(ctx, delay, m.module_id, timer, action, m)"),
        ])
end

"""
The alternating bit protocol: a sender and a receiver, two machines of one
component. The sender gives each frame the bit 0 or 1, in turn, and sends it
again when `retransmit_timer` expires before the acknowledgement of that bit
comes. The receiver delivers a frame with the bit that it waits for, and
acknowledges each frame, so a copy of a frame gets its acknowledgement again.

`send_frame!` and `send_ack!` give the frame and the acknowledgement to the
other machine with `fsm_defer!`, so each dispatch ends before the other machine
starts. They lose one frame or one acknowledgement when `m.drop_next_frame` or
`m.drop_next_ack` is set. Both machines handle each event in each state: a
`SEND` while the sender waits for an acknowledgement is an error of the user of
the component.
"""
function make_fsm_alternating_bit_document_example()
    send = FsmEvent("SEND")
    frame = FsmEvent("FRAME")
    ack = FsmEvent("ACK")
    retransmit_timer = FsmTimer("retransmit_timer")

    tr(state; kwargs...) = push!(state.transitions, FsmTransition(; kwargs...))

    wait_send_0 = FsmState("WAIT_SEND_0")
    wait_ack_0 = FsmState("WAIT_ACK_0")
    wait_send_1 = FsmState("WAIT_SEND_1")
    wait_ack_1 = FsmState("WAIT_ACK_1")
    for (bit, wait_send, wait_ack, next) in ((0, wait_send_0, wait_ack_0, wait_send_1),
                                            (1, wait_send_1, wait_ack_1, wait_send_0))
        tr(wait_send, trigger = send,
                      action = parse_julia("m.buffer = payload; send_frame!(ctx, m, $bit)"),
                      target = wait_ack)
        # A late acknowledgement of the frame before.
        tr(wait_send, trigger = ack)
        tr(wait_ack, trigger = ack, guard = parse_julia("payload == $bit"),
                     action = parse_julia("cancel_timer!(ctx, m.retransmit_timer)"),
                     target = next)
        # An acknowledgement of the other bit is a copy.
        tr(wait_ack, trigger = ack)
        tr(wait_ack, trigger = retransmit_timer, action = parse_julia("send_frame!(ctx, m, $bit)"))
    end
    sender = FsmMachine("Sender"; initial = wait_send_0,
                        states = [wait_send_0, wait_ack_0, wait_send_1, wait_ack_1])

    wait_frame_0 = FsmState("WAIT_FRAME_0")
    wait_frame_1 = FsmState("WAIT_FRAME_1")
    for (bit, wait_frame, next) in ((0, wait_frame_0, wait_frame_1), (1, wait_frame_1, wait_frame_0))
        tr(wait_frame, trigger = frame, guard = parse_julia("payload.bit == $bit"),
                       action = parse_julia("deliver_data!(m, payload.data); send_ack!(ctx, m, $bit)"),
                       target = next)
        # A frame with the other bit is a copy: its acknowledgement got lost.
        tr(wait_frame, trigger = frame, action = parse_julia("send_ack!(ctx, m, $(1 - bit))"))
    end
    receiver = FsmMachine("Receiver"; initial = wait_frame_0, states = [wait_frame_0, wait_frame_1])

    FsmComponent("AlternatingBit";
        variables = [
            FsmVariable("module_id"; type = parse_julia("Int"), default = parse_julia("0")),
            FsmVariable("buffer"; default = parse_julia("nothing")),
            FsmVariable("delivered"; type = parse_julia("Vector{Any}"), default = parse_julia("Any[]")),
            FsmVariable("drop_next_frame"; type = parse_julia("Bool"), default = parse_julia("false")),
            FsmVariable("drop_next_ack"; type = parse_julia("Bool"), default = parse_julia("false")),
        ],
        timers = [retransmit_timer],
        events = [send, frame, ack],
        machines = [sender, receiver],
        helpers = [
            parse_julia("const RETRANSMIT_TIME = 1.0"),
            parse_julia("""
                struct Frame
                    bit::Int
                    data::Any
                end
                """),
            parse_julia("""
                function send_frame!(ctx, m, bit)
                    schedule_timer!(ctx, RETRANSMIT_TIME, m.module_id, m.retransmit_timer, expire_retransmit_timer!, m)
                    if m.drop_next_frame
                        m.drop_next_frame = false
                    else
                        frame = Frame(bit, m.buffer)
                        fsm_defer!(m.fsm_sender, () -> receiver_dispatch!(ctx, m, E_FRAME, frame))
                    end
                end
                """),
            parse_julia("""
                function send_ack!(ctx, m, bit)
                    if m.drop_next_ack
                        m.drop_next_ack = false
                    else
                        fsm_defer!(m.fsm_receiver, () -> sender_dispatch!(ctx, m, E_ACK, bit))
                    end
                end
                """),
            parse_julia("deliver_data!(m, data) = push!(m.delivered, data)"),
        ])
end

"""
The TCP connection state machine of RFC 793, as INET implements it
(`TcpConnectionBase.cc`): twelve states, application commands, segment-derived
events and three FSM-visible timers.

The classifier that turns a raw segment into one of the `RCV_*` events is
deliberately *not* modeled as machine structure — it is `analyse_segment`
among the helpers, because it must stay ordinary Julia: stateful, able to
swallow input, and able to relabel one raw input as two different symbolic
events depending on extended state (`fin_ack_rcvd`).

The helpers define every function that the code of the machine calls. A send
helper puts its `Segment` in `m.outbox`, and an indication to the application
goes into `m.indications`, so the machine runs with no network.
"""
function make_fsm_tcp_document_example()
    # ── events ───────────────────────────────────────────────────────────
    open_active  = FsmEvent("OPEN_ACTIVE")
    open_passive = FsmEvent("OPEN_PASSIVE")
    send         = FsmEvent("SEND")
    close        = FsmEvent("CLOSE")
    abort        = FsmEvent("ABORT")
    rcv_syn      = FsmEvent("RCV_SYN")
    rcv_syn_ack  = FsmEvent("RCV_SYN_ACK")
    rcv_ack      = FsmEvent("RCV_ACK")
    rcv_fin      = FsmEvent("RCV_FIN")
    rcv_fin_ack  = FsmEvent("RCV_FIN_ACK")
    rcv_rst      = FsmEvent("RCV_RST")
    events = [open_active, open_passive, send, close, abort,
              rcv_syn, rcv_syn_ack, rcv_ack, rcv_fin, rcv_fin_ack, rcv_rst]

    # ── timers ───────────────────────────────────────────────────────────
    conn_estab = FsmTimer("conn_estab_timer")
    fin_wait_2 = FsmTimer("fin_wait_2_timer")
    msl2       = FsmTimer("msl2_timer")
    timers = [conn_estab, fin_wait_2, msl2]

    # ── states ───────────────────────────────────────────────────────────
    init         = FsmState("INIT")
    closed       = FsmState("CLOSED"; entry = parse_julia("cancel_all_timers!(ctx, m)"))
    listen       = FsmState("LISTEN")
    syn_sent     = FsmState("SYN_SENT")
    syn_rcvd     = FsmState("SYN_RCVD")
    established  = FsmState("ESTABLISHED"; entry = parse_julia(
                       "cancel_timer!(ctx, m.conn_estab_timer); indicate_established!(ctx, m)"))
    close_wait   = FsmState("CLOSE_WAIT")
    last_ack     = FsmState("LAST_ACK")
    fin_wait_1   = FsmState("FIN_WAIT_1")
    fin_wait_2_s = FsmState("FIN_WAIT_2")
    closing      = FsmState("CLOSING")
    time_wait    = FsmState("TIME_WAIT"; entry = parse_julia(
                       "schedule_timer!(ctx, 2 * MSL, m.module_id, m.msl2_timer, expire_msl2_timer!, m)"))

    states = [init, closed, listen, syn_sent, syn_rcvd, established,
              close_wait, last_ack, fin_wait_1, fin_wait_2_s, closing, time_wait]

    tr(state; kwargs...) = push!(state.transitions, FsmTransition(; kwargs...))

    # INIT — the two OPEN commands.
    tr(init, trigger = open_active,
             action = parse_julia("select_initial_sequence_number!(m); send_syn!(ctx, m); start_conn_estab_timer!(ctx, m)"),
             target = syn_sent)
    tr(init, trigger = open_passive, action = parse_julia("m.active = false"), target = listen)

    # LISTEN — a SYN opens the connection; a CLOSE just tears the socket down.
    tr(listen, trigger = rcv_syn,
               action = parse_julia("accept_syn!(ctx, m, payload); select_initial_sequence_number!(m); send_syn_ack!(ctx, m)"),
               target = syn_rcvd)
    tr(listen, trigger = close, target = closed)

    # SYN_SENT — the two handshake outcomes plus the establishment timeout.
    tr(syn_sent, trigger = rcv_syn_ack,
                 action = parse_julia("accept_syn!(ctx, m, payload); send_ack!(ctx, m)"),
                 target = established)
    tr(syn_sent, trigger = rcv_syn,
                 action = parse_julia("accept_syn!(ctx, m, payload); send_syn_ack!(ctx, m)"),
                 target = syn_rcvd)
    tr(syn_sent, trigger = conn_estab,
                 action = parse_julia("indicate_timed_out!(ctx, m)"),
                 target = closed)
    tr(syn_sent, trigger = rcv_rst, target = closed)

    # SYN_RCVD — the acceptable-ACK guard, and the timeout whose *target*
    # depends on extended state: an active open closes, a passive one goes
    # back to listening.
    tr(syn_rcvd, trigger = rcv_ack, guard = parse_julia("is_ack_acceptable(m, payload)"),
                 target = established)
    tr(syn_rcvd, trigger = rcv_ack, action = parse_julia("send_rst!(ctx, m, payload)"))
    tr(syn_rcvd, trigger = conn_estab, guard = parse_julia("m.active"),
                 action = parse_julia("indicate_timed_out!(ctx, m)"), target = closed)
    tr(syn_rcvd, trigger = conn_estab, target = listen)
    tr(syn_rcvd, trigger = close,
                 action = parse_julia("send_fin!(ctx, m)"), target = fin_wait_1)

    # ESTABLISHED — data flows; only the two closes move the machine.
    tr(established, trigger = send, action = parse_julia("send_data!(ctx, m, payload)"))
    tr(established, trigger = rcv_fin,
                    action = parse_julia("m.rcv_nxt = m.rcv_nxt + 1; send_ack!(ctx, m)"),
                    target = close_wait)
    tr(established, trigger = close, action = parse_julia("send_fin!(ctx, m)"), target = fin_wait_1)
    tr(established, trigger = rcv_rst, action = parse_julia("indicate_reset!(ctx, m)"), target = closed)

    # Passive close.
    tr(close_wait, trigger = close, action = parse_julia("send_fin!(ctx, m)"), target = last_ack)
    tr(last_ack, trigger = rcv_ack, target = closed)

    # Active close — the three-way race of FIN_WAIT_1.
    tr(fin_wait_1, trigger = rcv_fin_ack,
                   action = parse_julia("m.rcv_nxt = m.rcv_nxt + 1; send_ack!(ctx, m)"),
                   target = time_wait)
    tr(fin_wait_1, trigger = rcv_fin,
                   action = parse_julia("m.rcv_nxt = m.rcv_nxt + 1; send_ack!(ctx, m)"),
                   target = closing)
    tr(fin_wait_1, trigger = rcv_ack,
                   action = parse_julia("start_fin_wait_2_timer!(ctx, m)"),
                   target = fin_wait_2_s)

    tr(fin_wait_2_s, trigger = rcv_fin,
                     action = parse_julia("m.rcv_nxt = m.rcv_nxt + 1; send_ack!(ctx, m)"),
                     target = time_wait)
    tr(fin_wait_2_s, trigger = fin_wait_2, target = closed)

    tr(closing, trigger = rcv_ack, target = time_wait)
    tr(time_wait, trigger = msl2, target = closed)

    # Every state answers ABORT.
    for s in states
        s === closed || tr(s, trigger = abort,
                              action = parse_julia("send_rst!(ctx, m, payload)"), target = closed)
    end

    # `:ignore` — RFC 793 leaves most (state, event) pairs unlisted, and INET's
    # per-state `switch` has an empty `default: break` for exactly that reason.
    machine = FsmMachine("Connection"; initial = init, states = states, on_unhandled = :ignore)

    variables = [
        FsmVariable("module_id"; type = parse_julia("Int"), default = parse_julia("0")),
        FsmVariable("active"; type = parse_julia("Bool"), default = parse_julia("true")),
        FsmVariable("snd_una"; type = parse_julia("Int"), default = parse_julia("0")),
        FsmVariable("snd_nxt"; type = parse_julia("Int"), default = parse_julia("0")),
        FsmVariable("rcv_nxt"; type = parse_julia("Int"), default = parse_julia("0")),
        FsmVariable("fin_sent"; type = parse_julia("Bool"), default = parse_julia("false")),
        FsmVariable("fin_ack_rcvd"; type = parse_julia("Bool"), default = parse_julia("false")),
        FsmVariable("outbox"; type = parse_julia("Vector{Any}"), default = parse_julia("Any[]")),
        FsmVariable("indications"; type = parse_julia("Vector{String}"), default = parse_julia("String[]")),
    ]

    helpers = [
        parse_julia("const MSL = 120.0"),
        parse_julia("const CONNECTION_ESTABLISHMENT_TIME = 75.0"),
        parse_julia("const FIN_WAIT_2_TIME = 600.0"),
        parse_julia("const INITIAL_SEQUENCE_NUMBER = 1000"),
        # A segment as the classifier and the send helpers see it: the four
        # flags and the two numbers of the header, and the data.
        parse_julia("""
                   struct Segment
                       syn::Bool
                       ack::Bool
                       fin::Bool
                       rst::Bool
                       sequence_number::Int
                       ack_number::Int
                       data::Any
                   end
                   """),
        parse_julia("""
                   make_segment(; syn = false, ack = false, fin = false, rst = false,
                                sequence_number = 0, ack_number = 0, data = nothing) =
                       Segment(syn, ack, fin, rst, sequence_number, ack_number, data)
                   """),
        # The event-distillation seam: raw segment → symbolic event. Stateful
        # by nature — it takes the acknowledgement of the segment first, so the
        # same arriving FIN is RCV_FIN_ACK when it acknowledges the FIN of this
        # side, and RCV_FIN when that FIN was acknowledged before or not sent.
        parse_julia("""
                   function analyse_segment(m, segment)
                       acks_fin = false
                       if segment.ack && m.snd_una < segment.ack_number && segment.ack_number <= m.snd_nxt
                           m.snd_una = segment.ack_number
                           if m.fin_sent && !m.fin_ack_rcvd && segment.ack_number == m.snd_nxt
                               m.fin_ack_rcvd = true
                               acks_fin = true
                           end
                       end
                       if segment.rst
                           return E_RCV_RST
                       end
                       if segment.syn && segment.ack
                           return E_RCV_SYN_ACK
                       end
                       if segment.syn
                           return E_RCV_SYN
                       end
                       if segment.fin && acks_fin
                           return E_RCV_FIN_ACK
                       end
                       if segment.fin
                           return E_RCV_FIN
                       end
                       if segment.ack
                           return E_RCV_ACK
                       end
                       return Int32(0)
                   end
                   """),
        parse_julia("is_ack_acceptable(m, segment) = m.snd_una <= segment.ack_number && segment.ack_number <= m.snd_nxt"),
        parse_julia("""
                   function select_initial_sequence_number!(m)
                       m.snd_una = INITIAL_SEQUENCE_NUMBER
                       m.snd_nxt = INITIAL_SEQUENCE_NUMBER
                   end
                   """),
        # A SYN takes one sequence number, the initial one. It stays
        # unacknowledged until the handshake ends, so the SYN of a simultaneous
        # open has the number of the first SYN.
        parse_julia("""
                   function send_syn!(ctx, m)
                       push!(m.outbox, make_segment(syn = true, sequence_number = m.snd_una))
                       m.snd_nxt = m.snd_una + 1
                   end
                   """),
        parse_julia("""
                   function send_syn_ack!(ctx, m)
                       push!(m.outbox, make_segment(syn = true, ack = true, sequence_number = m.snd_una,
                                                    ack_number = m.rcv_nxt))
                       m.snd_nxt = m.snd_una + 1
                   end
                   """),
        parse_julia("send_ack!(ctx, m) = push!(m.outbox, make_segment(ack = true, sequence_number = m.snd_nxt, ack_number = m.rcv_nxt))"),
        # A FIN takes one sequence number.
        parse_julia("""
                   function send_fin!(ctx, m)
                       push!(m.outbox, make_segment(fin = true, ack = true, sequence_number = m.snd_nxt,
                                                    ack_number = m.rcv_nxt))
                       m.snd_nxt = m.snd_nxt + 1
                       m.fin_sent = true
                   end
                   """),
        parse_julia("send_rst!(ctx, m, segment) = push!(m.outbox, make_segment(rst = true, sequence_number = m.snd_nxt))"),
        parse_julia("""
                   function send_data!(ctx, m, data)
                       push!(m.outbox, make_segment(ack = true, sequence_number = m.snd_nxt,
                                                    ack_number = m.rcv_nxt, data = data))
                       m.snd_nxt = m.snd_nxt + length(data)
                   end
                   """),
        parse_julia("""
                   function accept_syn!(ctx, m, segment)
                       m.rcv_nxt = segment.sequence_number + 1
                       if segment.ack
                           m.snd_una = segment.ack_number
                       end
                   end
                   """),
        parse_julia("start_conn_estab_timer!(ctx, m) = schedule_timer!(ctx, CONNECTION_ESTABLISHMENT_TIME, m.module_id, m.conn_estab_timer, expire_conn_estab_timer!, m)"),
        parse_julia("start_fin_wait_2_timer!(ctx, m) = schedule_timer!(ctx, FIN_WAIT_2_TIME, m.module_id, m.fin_wait_2_timer, expire_fin_wait_2_timer!, m)"),
        parse_julia("""
                   function cancel_all_timers!(ctx, m)
                       cancel_timer!(ctx, m.conn_estab_timer)
                       cancel_timer!(ctx, m.fin_wait_2_timer)
                       cancel_timer!(ctx, m.msl2_timer)
                   end
                   """),
        parse_julia("indicate_established!(ctx, m) = push!(m.indications, \"established\")"),
        parse_julia("indicate_timed_out!(ctx, m) = push!(m.indications, \"timed out\")"),
        parse_julia("indicate_reset!(ctx, m) = push!(m.indications, \"reset\")"),
    ]

    FsmComponent("TcpConnection";
        variables = variables, timers = timers, events = events,
        machines = [machine], helpers = helpers)
end

"The registered document example: the TCP connection machine."
make_fsm_document_example() = make_fsm_tcp_document_example()

"The diagram example document: the machine of the traffic light (a diagram shows one machine)."
make_fsm_diagram_document_example() = make_fsm_crossing_document_example().machines[1]

"The sender of the alternating bit protocol, as a diagram."
make_fsm_alternating_bit_diagram_document_example() = make_fsm_alternating_bit_document_example().machines[1]
