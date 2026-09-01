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
# and parsed once (`juliaparse`) rather than hand-assembled node by node.

# Atomic documents for the catalog.
make_fsm_variable_document_example()   = FsmVariable("num_retries"; default = juliaparse("0"))
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
A two-state toggle: the smallest complete component — one variable, one timer,
one event, one machine with an entry action, a guard, a stay and a timeout.
"""
function make_fsm_toggle_document_example()
    pressed = FsmEvent("PRESSED")
    blink = FsmTimer("blink_timer")

    off = FsmState("OFF")
    on = FsmState("ON"; entry = juliaparse("m.blinks = m.blinks + 1"))

    push!(off.transitions, FsmTransition(trigger = pressed, target = on))
    # A stay: count the press without leaving the state.
    push!(on.transitions, FsmTransition(trigger = pressed,
                                        action = juliaparse("m.blinks = m.blinks + 1")))
    push!(on.transitions, FsmTransition(trigger = blink,
                                        guard = juliaparse("m.blinks > 3"),
                                        target = off))

    machine = FsmMachine("Toggle"; initial = off, states = [off, on])

    FsmComponent("Toggle";
        variables = [FsmVariable("blinks"; type = juliaparse("Int"), default = juliaparse("0"))],
        timers = [blink],
        events = [pressed],
        machines = [machine])
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
    closed       = FsmState("CLOSED"; entry = juliaparse("cancel_all_timers!(ctx, m)"))
    listen       = FsmState("LISTEN")
    syn_sent     = FsmState("SYN_SENT")
    syn_rcvd     = FsmState("SYN_RCVD")
    established  = FsmState("ESTABLISHED"; entry = juliaparse("connection_established!(ctx, m)"))
    close_wait   = FsmState("CLOSE_WAIT")
    last_ack     = FsmState("LAST_ACK")
    fin_wait_1   = FsmState("FIN_WAIT_1")
    fin_wait_2_s = FsmState("FIN_WAIT_2")
    closing      = FsmState("CLOSING")
    time_wait    = FsmState("TIME_WAIT"; entry = juliaparse("schedule_timer!(ctx, 2 * MSL, m.module_id, m.msl2_timer, expire_msl2)"))

    states = [init, closed, listen, syn_sent, syn_rcvd, established,
              close_wait, last_ack, fin_wait_1, fin_wait_2_s, closing, time_wait]

    tr(state; kwargs...) = push!(state.transitions, FsmTransition(; kwargs...))

    # INIT — the two OPEN commands.
    tr(init, trigger = open_active,
             action = juliaparse("select_initial_seq_num!(m); send_syn!(ctx, m); start_conn_estab_timer!(ctx, m)"),
             target = syn_sent)
    tr(init, trigger = open_passive, action = juliaparse("m.active = false"), target = listen)

    # LISTEN — a SYN opens the connection; a CLOSE just tears the socket down.
    tr(listen, trigger = rcv_syn,
               action = juliaparse("accept_syn!(ctx, m, payload); send_syn_ack!(ctx, m)"),
               target = syn_rcvd)
    tr(listen, trigger = close, target = closed)

    # SYN_SENT — the two handshake outcomes plus the establishment timeout.
    tr(syn_sent, trigger = rcv_syn_ack,
                 action = juliaparse("accept_syn!(ctx, m, payload); send_ack!(ctx, m)"),
                 target = established)
    tr(syn_sent, trigger = rcv_syn,
                 action = juliaparse("accept_syn!(ctx, m, payload); send_syn_ack!(ctx, m)"),
                 target = syn_rcvd)
    tr(syn_sent, trigger = conn_estab,
                 action = juliaparse("indicate_timed_out!(ctx, m)"),
                 target = closed)
    tr(syn_sent, trigger = rcv_rst, target = closed)

    # SYN_RCVD — the acceptable-ACK guard, and the timeout whose *target*
    # depends on extended state: an active open closes, a passive one goes
    # back to listening.
    tr(syn_rcvd, trigger = rcv_ack, guard = juliaparse("ack_acceptable(m, payload)"),
                 target = established)
    tr(syn_rcvd, trigger = rcv_ack, action = juliaparse("send_rst!(ctx, m, payload)"))
    tr(syn_rcvd, trigger = conn_estab, guard = juliaparse("m.active"),
                 action = juliaparse("indicate_timed_out!(ctx, m)"), target = closed)
    tr(syn_rcvd, trigger = conn_estab, target = listen)
    tr(syn_rcvd, trigger = close,
                 action = juliaparse("send_fin!(ctx, m)"), target = fin_wait_1)

    # ESTABLISHED — data flows; only the two closes move the machine.
    tr(established, trigger = send, action = juliaparse("send_data!(ctx, m, payload)"))
    tr(established, trigger = rcv_fin,
                    action = juliaparse("m.rcv_nxt = m.rcv_nxt + 1; send_ack!(ctx, m)"),
                    target = close_wait)
    tr(established, trigger = close, action = juliaparse("send_fin!(ctx, m)"), target = fin_wait_1)
    tr(established, trigger = rcv_rst, action = juliaparse("indicate_reset!(ctx, m)"), target = closed)

    # Passive close.
    tr(close_wait, trigger = close, action = juliaparse("send_fin!(ctx, m)"), target = last_ack)
    tr(last_ack, trigger = rcv_ack, target = closed)

    # Active close — the three-way race of FIN_WAIT_1.
    tr(fin_wait_1, trigger = rcv_fin_ack,
                   action = juliaparse("m.rcv_nxt = m.rcv_nxt + 1; send_ack!(ctx, m)"),
                   target = time_wait)
    tr(fin_wait_1, trigger = rcv_fin,
                   action = juliaparse("m.rcv_nxt = m.rcv_nxt + 1; send_ack!(ctx, m)"),
                   target = closing)
    tr(fin_wait_1, trigger = rcv_ack,
                   action = juliaparse("start_fin_wait_2_timer!(ctx, m)"),
                   target = fin_wait_2_s)

    tr(fin_wait_2_s, trigger = rcv_fin,
                     action = juliaparse("m.rcv_nxt = m.rcv_nxt + 1; send_ack!(ctx, m)"),
                     target = time_wait)
    tr(fin_wait_2_s, trigger = fin_wait_2, target = closed)

    tr(closing, trigger = rcv_ack, target = time_wait)
    tr(time_wait, trigger = msl2, target = closed)

    # Every state answers ABORT.
    for s in states
        s === closed || tr(s, trigger = abort,
                              action = juliaparse("send_rst!(ctx, m, payload)"), target = closed)
    end

    # `:ignore` — RFC 793 leaves most (state, event) pairs unlisted, and INET's
    # per-state `switch` has an empty `default: break` for exactly that reason.
    machine = FsmMachine("Connection"; initial = init, states = states, on_unhandled = :ignore)

    variables = [
        FsmVariable("module_id"; type = juliaparse("Int"), default = juliaparse("0")),
        FsmVariable("active"; type = juliaparse("Bool"), default = juliaparse("true")),
        FsmVariable("snd_una"; type = juliaparse("Int"), default = juliaparse("0")),
        FsmVariable("snd_nxt"; type = juliaparse("Int"), default = juliaparse("0")),
        FsmVariable("rcv_nxt"; type = juliaparse("Int"), default = juliaparse("0")),
        FsmVariable("fin_ack_rcvd"; type = juliaparse("Bool"), default = juliaparse("false")),
    ]

    helpers = [
        juliaparse("const MSL = 120.0"),
        # The event-distillation seam: raw segment → symbolic event. Stateful
        # by nature — the same arriving FIN is RCV_FIN or RCV_FIN_ACK
        # depending on what has already been acknowledged.
        juliaparse("""
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
        juliaparse("ack_acceptable(m, seg) = m.snd_una <= seg.ack && seg.ack <= m.snd_nxt"),
    ]

    FsmComponent("TcpConnection";
        variables = variables, timers = timers, events = events,
        machines = [machine], helpers = helpers)
end

"The registered document example: the TCP connection machine."
make_fsm_document_example() = make_fsm_tcp_document_example()

"The diagram example document: the toggle machine (a diagram shows one machine)."
make_fsm_diagram_document_example() = make_fsm_toggle_document_example().machines[1]
