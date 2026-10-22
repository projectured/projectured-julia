# The studies of the research examples at the stages of the work before the end:
# a study whose question is framed, one grounded in sources with competing
# hypotheses, one whose experiment is planned, and one whose evidence is
# contested. The study of the buffer of a router is the concluded stage. Each
# study is on another subject, and each could have been made in the editor: the
# ids are in order, a status comes from a decision, and the times follow the work.

_stage_time(day::Integer, hour::Integer, minute::Integer) =
    "2026-10-" * lpad(string(day), 2, '0') * "T" * lpad(string(hour), 2, '0') * ":" *
    lpad(string(minute), 2, '0') * ":00Z"

_stage_note(text::AbstractString) = parse_markdown(text * "\n").elements[1]

"""
    make_research_framed_study_document_example() -> ResearchStudy

A study at its first stage, the question framed: which channel plan the office
Wi-Fi gets. The person asks the question and a narrower one, with a note on the
floor as an attachment; the assistant adds a third question that the plan needs.
"""
function make_research_framed_study_document_example()
    q1 = ResearchQuestion(id = "Q1",
        statement = PrimitiveString("Which channel plan gives the office floor the fewest retransmissions in the 5 GHz band?"),
        criterion = PrimitiveString("the retransmission rate of each access point in the busy hour, one week for each plan"),
        purpose = PrimitiveString("the channel plan that the twelve access points get"),
        attachments = Any[_stage_note("The floor has **12** access points and about **180** clients in the busy hour, from 10:00 to 11:00.")],
        author = :person, time = _stage_time(5, 9, 10))
    q2 = ResearchQuestion(id = "Q2",
        statement = PrimitiveString("Is a channel width of 40 MHz better than 80 MHz on this floor?"),
        criterion = PrimitiveString("the median throughput of a client in the busy hour"),
        purpose = PrimitiveString("the channel width of the plan"),
        parent = q1, author = :person, time = _stage_time(5, 9, 18))
    q3 = ResearchQuestion(id = "Q3",
        statement = PrimitiveString("Which channels do the networks of the neighbours use in the busy hour?"),
        criterion = PrimitiveString("a scan of the band from three places on the floor"),
        purpose = PrimitiveString("the channels that the plan keeps away from"),
        parent = q1, author = :assistant, time = _stage_time(5, 9, 24))
    ResearchStudy(title = PrimitiveString("The channel plan of the office Wi-Fi"),
        questions = Any[q1, q2, q3], author = :person, time = _stage_time(5, 9, 10))
end

"""
    make_research_grounded_study_document_example() -> ResearchStudy

A study at its second stage, grounded in sources: why the battery of a soil
sensor lasts 9 days and not the 30 days of its data sheet. Three sources, three
competing hypotheses with the prediction that tells each from the others, and a
decision of the person that accepts the data sheet and the current log.
"""
function make_research_grounded_study_document_example()
    q1 = ResearchQuestion(id = "Q1",
        statement = PrimitiveString("Why does the battery of the soil sensor last 9 days and not the 30 days of its data sheet?"),
        criterion = PrimitiveString("the current of each part of the node over one cycle, measured and simulated"),
        purpose = PrimitiveString("the change that the next firmware release makes"),
        author = :person, time = _stage_time(14, 8, 30))
    s1 = ResearchSource(id = "S1",
        citation = PrimitiveString("Data sheet of the node, revision C, section 7, current consumption"),
        link = "docs/node-datasheet-revC.pdf",
        summary = PrimitiveString("Sleep 4 µA, receive 18 mA, transmit 24 mA: a mean of 0.3 mA at a duty cycle of 1 %, 30 days on a cell of 220 mAh."),
        status = :accepted, author = :person, time = _stage_time(14, 8, 41))
    s2 = ResearchSource(id = "S2",
        citation = PrimitiveString("Buettner, Yee, Anderson, Han: X-MAC, a short preamble MAC protocol for duty-cycled wireless sensor networks, SenSys 2006"),
        link = "https://doi.org/10.1145/1182807.1182838",
        summary = PrimitiveString("Idle listening takes most of the energy of a duty-cycled radio; a short preamble cuts it."),
        author = :assistant, time = _stage_time(14, 9, 2))
    s3 = ResearchSource(id = "S3",
        citation = PrimitiveString("Current log of node 17, 14 to 16 October"),
        link = "logs/node17-current.csv",
        summary = PrimitiveString("The current does not fall to the 4 µA of the data sheet between the wake-ups."),
        attachments = Any[_stage_note("Three days: a mean of **1.0 mA**, and **0.8 mA** between the wake-ups.")],
        status = :accepted, author = :person, time = _stage_time(16, 17, 5))
    h1 = ResearchHypothesis(id = "H1",
        statement = PrimitiveString("The radio listens between the wake-ups because the MAC does not turn it off."),
        question = q1, basis = Any[s2, s3],
        prediction = PrimitiveString("With the radio forced off between the wake-ups, the mean current falls to about 0.3 mA."),
        author = :assistant, time = _stage_time(16, 17, 20))
    h2 = ResearchHypothesis(id = "H2",
        statement = PrimitiveString("The soil sensor stays powered because its enable line floats."),
        question = q1, basis = Any[s3],
        prediction = PrimitiveString("With the enable line pulled low, the current between the wake-ups falls to 4 µA."),
        author = :person, time = _stage_time(16, 17, 34))
    h3 = ResearchHypothesis(id = "H3",
        statement = PrimitiveString("Retransmissions under interference keep the radio on longer than the data sheet assumes."),
        question = q1, basis = Any[s1],
        prediction = PrimitiveString("The log of the radio shows more than three transmissions for each reading."),
        author = :assistant, time = _stage_time(16, 17, 41))
    d1 = ResearchDecision(id = "D1",
        statement = PrimitiveString("The data sheet and the current log are the ground truth of this study."),
        reason = PrimitiveString("Both come from our own bench and our own node."),
        accepts = Any[s1, s3], author = :person, time = _stage_time(16, 17, 50))
    ResearchStudy(title = PrimitiveString("The battery of the soil sensor"),
        questions = Any[q1], sources = Any[s1, s2, s3], hypotheses = Any[h1, h2, h3],
        decisions = Any[d1], author = :person, time = _stage_time(14, 8, 30))
end

"""
    make_research_planned_study_document_example() -> ResearchStudy

A study at its third stage, the experiment planned: whether the time-aware shaper
of a plant network keeps the delay of the control traffic under 100 µs. Two
hypotheses with a bound that the runs check, a sweep with its design, an analysis
of the share of the link that is left to other traffic, and the decision of the
person that approves the sweep. Nothing has run yet.
"""
function make_research_planned_study_document_example()
    q1 = ResearchQuestion(id = "Q1",
        statement = PrimitiveString("Does the time-aware shaper keep the delay of the control traffic under 100 µs while best-effort traffic fills the link?"),
        criterion = PrimitiveString("the 99.9th percentile of the end-to-end delay of the control stream, over ten replications"),
        purpose = PrimitiveString("whether the plant network needs a link of its own for control"),
        attachments = Any[_stage_note("The control stream is **64 bytes every 500 µs**, from the controller to three drives through three switches of 1 Gb/s.")],
        author = :person, time = _stage_time(19, 10, 0))
    s1 = ResearchSource(id = "S1",
        citation = PrimitiveString("IEEE 802.1Qbv-2015, Enhancements for Scheduled Traffic"),
        summary = PrimitiveString("A gate control list opens a protected window for each traffic class in each cycle."),
        status = :accepted, author = :assistant, time = _stage_time(19, 10, 12))
    s2 = ResearchSource(id = "S2",
        citation = PrimitiveString("Craciunas, Oliver, Chmelík, Steiner: Scheduling real-time communication in IEEE 802.1Qbv time sensitive networks, RTNS 2016"),
        summary = PrimitiveString("With the windows of all switches aligned, the delay of scheduled traffic is bounded by the windows on its path."),
        author = :assistant, time = _stage_time(19, 10, 25))
    h1 = ResearchHypothesis(id = "H1",
        statement = PrimitiveString("A window of 50 µs in a cycle of 500 µs keeps the delay of the control traffic under 100 µs."),
        question = q1, basis = Any[s1, s2],
        prediction = ResearchExpectation(
            result_selection = PrimitiveString("99.9th percentile of the delay of the control stream, shaper on"),
            upper = 100.0e-6),
        author = :assistant, time = _stage_time(19, 10, 40))
    h2 = ResearchHypothesis(id = "H2",
        statement = PrimitiveString("Without the shaper, the delay of the control traffic is over 1 ms at full load."),
        question = q1,
        prediction = ResearchExpectation(
            result_selection = PrimitiveString("99.9th percentile of the delay of the control stream, shaper off, full load"),
            lower = 1.0e-3),
        author = :person, time = _stage_time(19, 10, 52))
    x1 = ResearchExperiment(id = "X1",
        title = PrimitiveString("Load sweep with the shaper on and off"),
        design = parse_markdown("- best-effort load of 10, 50, 90 and 100 % of the link\n" *
                                "- the shaper on and off\n" *
                                "- ten replications of 10 s each, after a warm-up of 1 s\n"),
        tests = Any[h1, h2], uses = Any[s1],
        status = :accepted, author = :assistant, time = _stage_time(19, 11, 5))
    n1 = ResearchAnalysis(id = "N1",
        title = PrimitiveString("Share of the link that is left to best-effort traffic"),
        method = FormulaEnvironment([
            FormulaFormula("cycle", parse_julia("500e-6")),
            FormulaFormula("window", parse_julia("50e-6")),
            FormulaFormula("guard", parse_julia("1538 * 8 / 1e9")),
            FormulaFormula("share", parse_julia("(cycle - window - guard) / cycle")),
        ]),
        uses = Any[s1], author = :assistant, time = _stage_time(19, 11, 14))
    d1 = ResearchDecision(id = "D1",
        statement = PrimitiveString("Run the sweep as designed, and use the standard as the reference."),
        reason = PrimitiveString("The sweep covers every load that the plant network sees."),
        accepts = Any[x1, s1], author = :person, time = _stage_time(20, 8, 45))
    ResearchStudy(title = PrimitiveString("Control traffic through the time-aware shaper"),
        questions = Any[q1], sources = Any[s1, s2], hypotheses = Any[h1, h2], experiments = Any[x1],
        analyses = Any[n1], decisions = Any[d1], author = :person, time = _stage_time(19, 10, 0))
end

"""
    make_research_contested_study_document_example() -> ResearchStudy

A study at its fourth stage, the evidence contested: whether a new congestion
control shares a bottleneck fairly with CUBIC. The runs give evidence for the
hypothesis at small buffers and against it at a deep buffer, a run by hand gives
evidence for it again, and the assistant states a new hypothesis that explains
both. No decision about them is made yet.
"""
function make_research_contested_study_document_example()
    q1 = ResearchQuestion(id = "Q1",
        statement = PrimitiveString("Does the new congestion control share a bottleneck fairly with CUBIC?"),
        criterion = PrimitiveString("Jain's fairness index of the two flows over 60 s, at buffers of 0.5, 1 and 2 bandwidth-delay products"),
        purpose = PrimitiveString("whether the new congestion control can be the default of the servers"),
        author = :person, time = _stage_time(9, 14, 0))
    s1 = ResearchSource(id = "S1",
        citation = PrimitiveString("Jain, Chiu, Hawe: A quantitative measure of fairness and discrimination for resource allocation in shared computer systems, DEC-TR-301, 1984"),
        link = "https://arxiv.org/abs/cs/9809099",
        summary = PrimitiveString("The fairness index (Σx)² / (n Σx²) is 1 for equal shares and 1/n when one flow takes everything."),
        status = :accepted, author = :assistant, time = _stage_time(9, 14, 10))
    s2 = ResearchSource(id = "S2",
        citation = PrimitiveString("Ha, Rhee, Xu: CUBIC, a new TCP-friendly high-speed TCP variant, ACM SIGOPS Operating Systems Review 42(5), 2008"),
        link = "https://doi.org/10.1145/1400097.1400105",
        summary = PrimitiveString("CUBIC grows its window as a cubic function of the time since the last loss."),
        author = :assistant, time = _stage_time(9, 14, 16))
    h1 = ResearchHypothesis(id = "H1",
        statement = PrimitiveString("The two flows share the bottleneck fairly: the fairness index is at least 0.9 at every buffer."),
        question = q1, basis = Any[s1],
        prediction = ResearchExpectation(result_selection = PrimitiveString("fairness index at each buffer"),
                                         lower = 0.9),
        author = :assistant, time = _stage_time(9, 14, 30))
    x1 = ResearchExperiment(id = "X1",
        title = PrimitiveString("Two flows through a bottleneck of 100 Mb/s with a round-trip time of 40 ms"),
        design = PrimitiveString("buffers of 0.5, 1 and 2 BDP; 60 s for each run; ten replications; the new flow starts 5 s after CUBIC"),
        tests = Any[h1], uses = Any[s2],
        status = :accepted, author = :assistant, time = _stage_time(9, 14, 45))
    d1 = ResearchDecision(id = "D1",
        statement = PrimitiveString("Measure with the fairness index of S1, and run X1."),
        reason = PrimitiveString("The index is the measure that the criterion names."),
        accepts = Any[s1, x1], author = :person, time = _stage_time(9, 15, 0))
    r1 = ResearchResult(id = "R1", title = PrimitiveString("Fairness index by buffer"),
        content = PrimitiveString("0.5 BDP: 0.97 ± 0.01, 1 BDP: 0.93 ± 0.02, 2 BDP: 0.72 ± 0.04"),
        origin = x1, author = :assistant, time = _stage_time(11, 9, 30))
    r2 = ResearchResult(id = "R2", title = PrimitiveString("Share of the link at 2 BDP"),
        content = PrimitiveString("new flow 81 %, CUBIC 19 %"),
        origin = x1, author = :assistant, time = _stage_time(11, 9, 32))
    e1 = ResearchEvidence(id = "E1",
        statement = PrimitiveString("At 0.5 and 1 BDP the fairness index is 0.97 and 0.93."),
        basis = Any[r1], supports = Any[h1], author = :assistant, time = _stage_time(11, 9, 40))
    e2 = ResearchEvidence(id = "E2",
        statement = PrimitiveString("At 2 BDP the fairness index is 0.72, and the new flow takes 81 % of the link."),
        basis = Any[r1, r2], opposes = Any[h1], author = :assistant, time = _stage_time(11, 9, 41))
    e3 = ResearchEvidence(id = "E3",
        statement = PrimitiveString("With CUBIC started 5 s after the new flow, three runs at 2 BDP give 0.91, 0.92 and 0.93."),
        supports = Any[h1],
        attachments = Any[_stage_note("Run by hand on the bench on 12 October; the order of the starts is the only change.")],
        author = :person, time = _stage_time(12, 16, 20))
    h2 = ResearchHypothesis(id = "H2",
        statement = PrimitiveString("In a deep buffer, the flow that starts second takes the larger share, whichever it is."),
        question = q1, basis = Any[e2, e3],
        prediction = PrimitiveString("At 4 BDP, the flow that starts second takes more than 80 % of the link."),
        author = :assistant, time = _stage_time(12, 16, 35))
    ResearchStudy(title = PrimitiveString("Fairness of the new congestion control against CUBIC"),
        questions = Any[q1], sources = Any[s1, s2], hypotheses = Any[h1, h2], experiments = Any[x1],
        results = Any[r1, r2], evidence = Any[e1, e2, e3], decisions = Any[d1],
        author = :person, time = _stage_time(9, 14, 0))
end
