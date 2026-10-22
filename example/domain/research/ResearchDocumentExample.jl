# The documents of the research examples: one small document of each type, and
# the study of the buffer of a router, which holds an item of every kind.
#
# K is the capacity of the queue of an M/M/1/K router, which holds K packets
# besides the one in service, so its blocking is (1 - ρ) ρ^(K+1) / (1 - ρ^(K+2)).

_example_time(minute::Integer) = "2026-10-22T07:" * lpad(string(minute), 2, '0') * ":00Z"

"""
    make_research_question_document_example() -> ResearchQuestion

The question of the study of the buffer of a router.
"""
make_research_question_document_example() =
    ResearchQuestion(id = "Q1",
        statement = PrimitiveString("Which queue capacity is the smallest that keeps the drop rate under 1 % at a load of 0.8?"),
        criterion = PrimitiveString("the drop rate of each capacity, with a 95 % confidence interval"),
        purpose = PrimitiveString("the queue capacity that the router ships with"),
        author = :person, time = _example_time(12))

"""
    make_research_source_document_example() -> ResearchSource

A book that gives the blocking of M/M/1/K in closed form.
"""
make_research_source_document_example() =
    ResearchSource(id = "S1",
        citation = PrimitiveString("Kleinrock, Queueing Systems, Volume I, 1975, section 3.6"),
        link = "https://doi.org/10.1002/net.3230060210",
        summary = PrimitiveString("The blocking of M/M/1/K in closed form."),
        status = :accepted, author = :assistant, time = _example_time(20))

"""
    make_research_expectation_document_example() -> ResearchExpectation

A bound on the drop rate, under 1 %.
"""
make_research_expectation_document_example() =
    ResearchExpectation(result_selection = PrimitiveString("drop rate at K = 13"), upper = 0.01)

"""
    make_research_hypothesis_document_example(; question = make_research_question_document_example(),
                                              basis = Any[]) -> ResearchHypothesis

The claim that a queue capacity of 13 is enough, with a bound as its prediction.
"""
make_research_hypothesis_document_example(; question = make_research_question_document_example(),
                                          basis = Any[]) =
    ResearchHypothesis(id = "H1", question = question,
        statement = PrimitiveString("A queue capacity of 13 is enough."),
        prediction = make_research_expectation_document_example(), basis = basis,
        status = :accepted, author = :assistant, time = _example_time(31))

"""
    make_research_experiment_document_example(; tests = Any[]) -> ResearchExperiment

A sweep of the queue capacity.
"""
make_research_experiment_document_example(; tests = Any[]) =
    ResearchExperiment(id = "X1", title = PrimitiveString("Sweep K = 1 … 20, 5 replications"),
        design = PrimitiveString("K from 1 to 20, five replications of 1000 s each, a warm-up of 100 s"),
        tests = tests, status = :accepted, author = :assistant, time = _example_time(40))

"""
    make_research_analysis_document_example(; tests = Any[], uses = Any[]) -> ResearchAnalysis

The blocking of M/M/1/K in closed form, as a formula sheet.
"""
make_research_analysis_document_example(; tests = Any[], uses = Any[]) =
    ResearchAnalysis(id = "N1", title = PrimitiveString("Blocking in closed form"),
        method = FormulaEnvironment([
            FormulaFormula("rho", parse_julia("0.8")),
            FormulaFormula("K", parse_julia("13")),
            FormulaFormula("P_block", parse_julia("(1 - rho) * rho^(K + 1) / (1 - rho^(K + 2))")),
        ]),
        tests = tests, uses = uses, author = :assistant, time = _example_time(44))

"""
    make_research_result_document_example(; origin = nothing) -> ResearchResult

The drop rate of each queue capacity.
"""
make_research_result_document_example(; origin = nothing) =
    ResearchResult(id = "R1", title = PrimitiveString("Drop rate by K"),
        content = PrimitiveString("K = 12: 1.13 %, K = 13: 0.91 %, K = 14: 0.73 %"),
        origin = origin, author = :assistant, time = _example_time(46))

"""
    make_research_evidence_document_example(; basis = Any[], supports = Any[]) -> ResearchEvidence

The observed drop rate at a queue capacity of 13.
"""
make_research_evidence_document_example(; basis = Any[], supports = Any[]) =
    ResearchEvidence(id = "E1",
        statement = PrimitiveString("At K = 13 the drop rate is 0.91 % ± 0.05 %."),
        basis = basis, supports = supports,
        status = :accepted, author = :assistant, time = _example_time(52))

"""
    make_research_decision_document_example(; accepts = Any[], basis = Any[]) -> ResearchDecision

The decision of the person that the claim holds.
"""
make_research_decision_document_example(; accepts = Any[], basis = Any[]) =
    ResearchDecision(id = "D2", statement = PrimitiveString("A queue capacity of 13 is enough."),
        reason = PrimitiveString("The interval of E1 is under the bound."),
        accepts = accepts, basis = basis, author = :person, time = _example_time(58))

"""
    make_research_answer_document_example(; question = nothing, basis = Any[]) -> ResearchAnswer

The answer of the study.
"""
make_research_answer_document_example(; question = nothing, basis = Any[]) =
    ResearchAnswer(id = "A1", question = question, statement = PrimitiveString("A queue capacity of 13."),
        caveats = PrimitiveString("Poisson arrivals and exponential service only."),
        basis = basis, author = :person, time = "2026-10-22T08:05:00Z")

"""
    make_research_projection_example(; measure = FontFileMeasure()) -> Projection

The renderer that draws any document, which draws a study as its outline: the rows
that the research domain registers.
"""
make_research_projection_example(; measure = FontFileMeasure()) = NaturalToGraphics(; measure)

"""
    make_research_study_document_example() -> ResearchStudy

The study of the buffer of a router: an item of every kind, linked to each other.
The person asks the question, decides twice and answers; the assistant adds the
source, the hypothesis, the experiment, the analysis, the result and the evidence.
"""
function make_research_study_document_example()
    q1 = make_research_question_document_example()
    s1 = make_research_source_document_example()
    h1 = make_research_hypothesis_document_example(question = q1, basis = Any[s1])
    x1 = make_research_experiment_document_example(tests = Any[h1])
    n1 = make_research_analysis_document_example(tests = Any[h1], uses = Any[s1])
    r1 = make_research_result_document_example(origin = x1)
    e1 = make_research_evidence_document_example(basis = Any[r1], supports = Any[h1])
    d1 = ResearchDecision(id = "D1", statement = PrimitiveString("Run the sweep as designed."),
                          accepts = Any[x1], author = :person, time = _example_time(41))
    d2 = make_research_decision_document_example(accepts = Any[h1, e1, s1], basis = Any[e1])
    a1 = make_research_answer_document_example(question = q1, basis = Any[e1, d2])
    ResearchStudy(title = PrimitiveString("The buffer of the access router"),
        questions = Any[q1], sources = Any[s1], hypotheses = Any[h1], experiments = Any[x1],
        analyses = Any[n1], results = Any[r1], evidence = Any[e1], decisions = Any[d1, d2],
        answers = Any[a1], author = :person, time = _example_time(12))
end

"""
    make_research_map_document_example() -> ResearchMap

The map of the study of the buffer of a router: its items as the vertices of a
graph, and its links as the edges.
"""
make_research_map_document_example() = ResearchMap(study = make_research_study_document_example())
