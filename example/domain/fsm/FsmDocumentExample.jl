# ── Fsm domain examples ─────────────────────────────────────────────────────
#
# The showcase is the TCP connection state machine (RFC 793): twelve states,
# the three event families (application commands, segment-derived events,
# timeouts), guards over extended state, entry actions, guard-dependent targets
# and the `:ignore` unhandled policy — the machine INET builds by hand out of
# nested switches, expressed as a document. It needs no simulator: everything
# it references lives in its own `helpers`.
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
The TCP connection state machine of RFC 793, as INET implements it
(`TcpConnectionBase.cc`): twelve states, application commands, segment-derived
events and three FSM-visible timers.

The classifier that turns a raw segment into one of the `RCV_*` events is
deliberately *not* modeled as machine structure — it is `analyse_segment`
among the helpers, because it must stay ordinary Julia: stateful, able to
swallow input, and able to relabel one raw input as two different symbolic
events depending on extended state (`fin_ack_rcvd`).
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
    established  = FsmState("ESTABLISHED"; entry = parse_julia("connection_established!(ctx, m)"))
    close_wait   = FsmState("CLOSE_WAIT")
    last_ack     = FsmState("LAST_ACK")
    fin_wait_1   = FsmState("FIN_WAIT_1")
    fin_wait_2_s = FsmState("FIN_WAIT_2")
    closing      = FsmState("CLOSING")
    time_wait    = FsmState("TIME_WAIT"; entry = parse_julia("schedule_timer!(ctx, 2 * MSL, m.module_id, m.msl2_timer, expire_msl2)"))

    states = [init, closed, listen, syn_sent, syn_rcvd, established,
              close_wait, last_ack, fin_wait_1, fin_wait_2_s, closing, time_wait]

    tr(state; kwargs...) = push!(state.transitions, FsmTransition(; kwargs...))

    # INIT — the two OPEN commands.
    tr(init, trigger = open_active,
             action = parse_julia("select_initial_seq_num!(m); send_syn!(ctx, m); start_conn_estab_timer!(ctx, m)"),
             target = syn_sent)
    tr(init, trigger = open_passive, action = parse_julia("m.active = false"), target = listen)

    # LISTEN — a SYN opens the connection; a CLOSE just tears the socket down.
    tr(listen, trigger = rcv_syn,
               action = parse_julia("accept_syn!(ctx, m, payload); send_syn_ack!(ctx, m)"),
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
    tr(syn_rcvd, trigger = rcv_ack, guard = parse_julia("ack_acceptable(m, payload)"),
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
        FsmVariable("fin_ack_rcvd"; type = parse_julia("Bool"), default = parse_julia("false")),
    ]

    helpers = [
        parse_julia("const MSL = 120.0"),
        # The event-distillation seam: raw segment → symbolic event. Stateful
        # by nature — the same arriving FIN is RCV_FIN or RCV_FIN_ACK
        # depending on what has already been acknowledged.
        parse_julia("""
                   function analyse_segment(m, seg)
                       if seg.rst
                           return RCV_RST
                       end
                       if seg.syn && seg.ack
                           return RCV_SYN_ACK
                       end
                       if seg.syn
                           return RCV_SYN
                       end
                       if seg.fin && m.fin_ack_rcvd
                           return RCV_FIN_ACK
                       end
                       if seg.fin
                           return RCV_FIN
                       end
                       if seg.ack
                           return RCV_ACK
                       end
                       return IGNORE
                   end
                   """),
        parse_julia("ack_acceptable(m, seg) = m.snd_una <= seg.ack && seg.ack <= m.snd_nxt"),
    ]

    FsmComponent("TcpConnection";
        variables = variables, timers = timers, events = events,
        machines = [machine], helpers = helpers)
end

"The registered document example: the TCP connection machine."
make_fsm_document_example() = make_fsm_tcp_document_example()

"The diagram example document: the machine of the traffic light (a diagram shows one machine)."
make_fsm_diagram_document_example() = make_fsm_crossing_document_example().machines[1]
