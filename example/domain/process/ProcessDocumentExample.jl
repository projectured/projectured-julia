# ── Process domain examples ─────────────────────────────────────────────────
#
# The showcase is a CSMA transmit procedure: a decision inside a loop, an
# informal step that has not been refined into code yet, jumps out of the loop
# and out of the process. Everything it references is ordinary Julia, so the
# realized function runs with nothing but its own arguments.
#
# Embedded actions and conditions are real Julia subtrees, written here as
# source and parsed once (`parse_julia`) rather than hand-assembled node by node.

# Atomic documents for the catalog.
make_process_step_document_example()     = ProcessStep("prepare"; action = parse_julia("x = encode(frame)"))
make_process_sequence_document_example() = ProcessSequence([make_process_step_document_example()])
make_process_decision_document_example() =
    ProcessDecision(parse_julia("carrier_free()");
                    then_branch = ProcessSequence([ProcessReturn(parse_julia(":sent"))]))
make_process_while_document_example() =
    ProcessWhile(parse_julia("attempts < max_attempts");
                 body = ProcessSequence([make_process_decision_document_example()]))
make_process_foreach_document_example() =
    ProcessForeach(parse_julia("item"), parse_julia("queue");
                   body = ProcessSequence([ProcessStep(""; action = parse_julia("send!(item)"))]))
make_process_return_document_example()   = ProcessReturn(parse_julia(":failed"))
make_process_insertion_document_example() = ProcessInsertion()
make_process_break_document_example()    = ProcessBreak()
make_process_continue_document_example() = ProcessContinue()
# The diagram stage synthesizes a terminal and an edge label, and the catalog
# prints one of each on its own.
make_process_terminal_document_example()   = ProcessTerminal(:start)
make_process_edge_label_document_example() = ProcessEdgeLabel("yes")

"""
A complete transmit procedure: every node type, an informal step, a decision
inside a loop, and both a `break` and a `return` leaving it.
"""
function make_process_transmit_document_example()
    prepare = ProcessStep("prepare"; action = parse_julia("frame = encode(payload)"))

    sense = ProcessDecision(parse_julia("carrier_free(medium)");
                            then_branch = ProcessSequence([
                                ProcessStep(""; action = parse_julia("transmit!(medium, frame)")),
                                ProcessReturn(parse_julia(":sent")),
                            ]))
    # Informal: what to do is named, how it is done has not been written yet.
    backoff = ProcessStep("wait a binary exponential backoff")
    count = ProcessStep(""; action = parse_julia("attempts = attempts + 1"))
    give_up = ProcessDecision(parse_julia("attempts >= max_attempts");
                              then_branch = ProcessSequence([ProcessBreak()]))

    attempt_loop = ProcessWhile(parse_julia("true");
                                body = ProcessSequence([sense, give_up, backoff, count]))

    ProcessModel("transmit";
                 parameters = [parse_julia("medium"), parse_julia("payload"),
                               parse_julia("max_attempts")],
                 body = ProcessSequence([
                     prepare,
                     ProcessStep(""; action = parse_julia("attempts = 0")),
                     attempt_loop,
                     ProcessReturn(parse_julia(":failed")),
                 ]))
end

"""
The smallest complete process: a loop over a collection with one step in it.
Everything is refined, so this one is executable as it stands.
"""
function make_process_drain_document_example()
    ProcessModel("drain";
                 parameters = [parse_julia("queue")],
                 body = ProcessSequence([
                     ProcessStep(""; action = parse_julia("sent = 0")),
                     ProcessForeach(parse_julia("item"), parse_julia("queue");
                                    body = ProcessSequence([
                                        ProcessDecision(parse_julia("item === nothing");
                                                        then_branch = ProcessSequence([ProcessContinue()])),
                                        ProcessStep("hand it to the medium";
                                                    action = parse_julia("send!(item)")),
                                        ProcessStep(""; action = parse_julia("sent = sent + 1")),
                                    ])),
                     ProcessReturn(parse_julia("sent")),
                 ]))
end

"The registered document example: the transmit procedure."
make_process_document_example() = make_process_transmit_document_example()

make_process_model_document_example() = make_process_transmit_document_example()

"The diagram example document: the drain procedure (small enough to read as a picture)."
make_process_diagram_document_example() = make_process_drain_document_example()
