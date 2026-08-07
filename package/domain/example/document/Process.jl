# ── Process domain examples ─────────────────────────────────────────────────
#
# The showcase is a CSMA transmit procedure: a decision inside a loop, an
# informal step that has not been refined into code yet, jumps out of the loop
# and out of the process. Everything it references is ordinary Julia, so the
# realized function runs with nothing but its own arguments.
#
# Embedded actions and conditions are real Julia subtrees, written here as
# source and parsed once (`juliaparse`) rather than hand-assembled node by node.

# Atomic documents for the catalog.
make_process_step_document_example()     = ProcessStep("prepare"; action = juliaparse("x = encode(frame)"))
make_process_sequence_document_example() = ProcessSequence([make_process_step_document_example()])
make_process_decision_document_example() =
    ProcessDecision(juliaparse("carrier_free()");
                    then_branch = ProcessSequence([ProcessReturn(juliaparse(":sent"))]))
make_process_while_document_example() =
    ProcessWhile(juliaparse("attempts < max_attempts");
                 body = ProcessSequence([make_process_decision_document_example()]))
make_process_foreach_document_example() =
    ProcessForeach(juliaparse("item"), juliaparse("queue");
                   body = ProcessSequence([ProcessStep(""; action = juliaparse("send!(item)"))]))
make_process_return_document_example()   = ProcessReturn(juliaparse(":failed"))
make_process_insertion_document_example() = ProcessInsertion()

"""
A complete transmit procedure: every node type, an informal step, a decision
inside a loop, and both a `break` and a `return` leaving it.
"""
function make_process_transmit_document_example()
    prepare = ProcessStep("prepare"; action = juliaparse("frame = encode(payload)"))

    sense = ProcessDecision(juliaparse("carrier_free(medium)");
                            then_branch = ProcessSequence([
                                ProcessStep(""; action = juliaparse("transmit!(medium, frame)")),
                                ProcessReturn(juliaparse(":sent")),
                            ]))
    # Informal: what to do is named, how it is done has not been written yet.
    backoff = ProcessStep("wait a binary exponential backoff")
    count = ProcessStep(""; action = juliaparse("attempts = attempts + 1"))
    give_up = ProcessDecision(juliaparse("attempts >= max_attempts");
                              then_branch = ProcessSequence([ProcessBreak()]))

    attempt_loop = ProcessWhile(juliaparse("true");
                                body = ProcessSequence([sense, give_up, backoff, count]))

    ProcessModel("transmit";
                 parameters = [juliaparse("medium"), juliaparse("payload"),
                               juliaparse("max_attempts")],
                 body = ProcessSequence([
                     prepare,
                     ProcessStep(""; action = juliaparse("attempts = 0")),
                     attempt_loop,
                     ProcessReturn(juliaparse(":failed")),
                 ]))
end

"""
The smallest complete process: a loop over a collection with one step in it.
Everything is refined, so this one is executable as it stands.
"""
function make_process_drain_document_example()
    ProcessModel("drain";
                 parameters = [juliaparse("queue")],
                 body = ProcessSequence([
                     ProcessStep(""; action = juliaparse("sent = 0")),
                     ProcessForeach(juliaparse("item"), juliaparse("queue");
                                    body = ProcessSequence([
                                        ProcessDecision(juliaparse("item === nothing");
                                                        then_branch = ProcessSequence([ProcessContinue()])),
                                        ProcessStep("hand it to the medium";
                                                    action = juliaparse("send!(item)")),
                                        ProcessStep(""; action = juliaparse("sent = sent + 1")),
                                    ])),
                     ProcessReturn(juliaparse("sent")),
                 ]))
end

"The registered document example: the transmit procedure."
make_process_document_example() = make_process_transmit_document_example()

make_process_model_document_example() = make_process_transmit_document_example()

"The diagram example document: the drain procedure (small enough to read as a picture)."
make_process_diagram_document_example() = make_process_drain_document_example()
