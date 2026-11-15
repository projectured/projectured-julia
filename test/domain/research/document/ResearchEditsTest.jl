# The object that an operation is evaluated against in these tests: a study that
# no view shows, inside a history.
mutable struct _ResearchTestEditor
    document::Any
end

const _RESEARCH_TEST_TIME = "2026-10-22T09:00:00Z"

# The study in a history, the projection of the history, and its IO map: an
# operation read through them is recorded as an edit of the person is.
function _make_research_history(study)
    buffer = UndoBuffer(study)
    projection = UndoBufferToAnyProjection()
    iomap = print_document(projection, IdentityProjection(), buffer, PrinterContext())
    (buffer, projection, iomap, _ResearchTestEditor(buffer))
end

"""
    test_research_edits()

The edits of a study: the id, the author and the time of a new item, a link given
by its id, the insert and the delete of an item, and a decision that writes the
statuses, each with its way back through a history.
"""
function test_research_edits()
    @testset "ResearchEdits" begin
        @testset "a new item takes the next id of its kind, its author and its time" begin
            study = make_research_study_document_example()
            @test make_research_id(study, ResearchHypothesis) == "H2"
            @test make_research_id(study, ResearchDecision) == "D3"
            @test make_research_id(ResearchStudy(), ResearchSource) == "S1"
            hypothesis = make_research_item(study, ResearchHypothesis; author = :assistant,
                                            time = _RESEARCH_TEST_TIME,
                                            statement = "A capacity of 12 is enough.", question = "Q1",
                                            basis = ["S1"])
            @test hypothesis.id == "H2"
            @test hypothesis.author === :assistant
            @test hypothesis.time == _RESEARCH_TEST_TIME
            @test hypothesis.statement.value == "A capacity of 12 is enough."
            @test hypothesis.question === study.questions[1]
            @test hypothesis.basis[1] === study.sources[1]
            @test_throws ArgumentError make_research_item(study, ResearchEvidence; supports = ["H9"])
            @test_throws ArgumentError make_research_item(study, ResearchEvidence; question = "Q1")
            @test_throws ArgumentError make_research_item(study, ResearchSource; author = :robot)
        end

        @testset "an item goes to the end of the list of its kind, and an undo takes it back" begin
            study = make_research_study_document_example()
            (buffer, projection, iomap, editor) = _make_research_history(study)
            evidence = make_research_item(study, ResearchEvidence; time = _RESEARCH_TEST_TIME,
                                          statement = "At K = 12 the drop rate is 1.13 %.",
                                          basis = ["R1"], opposes = ["H1"])
            evaluate_operation(editor, read_intent(projection, iomap,
                                                   make_add_research_item_operation(study, evidence)))
            @test length(study.evidence) == 2
            @test study.evidence[2] === evidence
            @test evidence.opposes[1] === study.hypotheses[1]
            evaluate_operation(editor, UndoOperation(buffer))
            @test length(study.evidence) == 1
        end

        @testset "an item that another item holds is not deleted" begin
            study = make_research_study_document_example()
            error = try
                make_delete_research_item_operation(study, study.hypotheses[1])
                nothing
            catch caught
                caught
            end
            @test error isa ArgumentError
            @test occursin("H1 is held by X1, N1, E1, D2", error.msg)
            answer = study.answers[1]
            evaluate_operation(nothing, make_delete_research_item_operation(study, answer))
            @test length(study.answers) == 0
        end

        @testset "a decision writes the statuses, and one undo takes both back" begin
            study = make_research_study_document_example()
            (buffer, projection, iomap, editor) = _make_research_history(study)
            answer, analysis = study.answers[1], study.analyses[1]
            @test answer.status === :open && analysis.status === :open
            decision = make_research_item(study, ResearchDecision; time = _RESEARCH_TEST_TIME,
                                          statement = "The answer stands; the closed form is not used.",
                                          accepts = ["A1"], rejects = ["N1"])
            evaluate_operation(editor, read_intent(projection, iomap,
                                                   make_record_decision_operation(study, decision)))
            @test study.decisions[3] === decision
            @test decision.id == "D3"
            @test answer.status === :accepted
            @test analysis.status === :rejected
            evaluate_operation(editor, UndoOperation(buffer))
            @test length(study.decisions) == 2
            @test answer.status === :open && analysis.status === :open
        end

        @testset "a later decision supersedes an earlier one" begin
            study = make_research_study_document_example()
            hypothesis = study.hypotheses[1]
            @test hypothesis.status === :accepted
            decision = make_research_item(study, ResearchDecision; author = :assistant,
                                          time = _RESEARCH_TEST_TIME,
                                          statement = "A second run refutes it.", rejects = ["H1"])
            evaluate_operation(nothing, make_record_decision_operation(study, decision))
            @test hypothesis.status === :rejected
            @test [item.id for item in study.decisions] == ["D1", "D2", "D3"]
        end

        @testset "a decision names items of the study with a status, once each" begin
            study = make_research_study_document_example()
            twice = make_research_item(study, ResearchDecision; accepts = ["H1"], rejects = ["H1"])
            @test_throws ArgumentError make_record_decision_operation(study, twice)
            about_a_decision = make_research_item(study, ResearchDecision; accepts = ["D1"])
            @test_throws ArgumentError make_record_decision_operation(study, about_a_decision)
            stranger = ResearchHypothesis(id = "H7")
            outside = make_research_item(study, ResearchDecision; accepts = [stranger])
            @test_throws ArgumentError make_record_decision_operation(study, outside)
        end

        @testset "an id and a status are not fields that a call gives" begin
            study = make_research_study_document_example()
            @test_throws ArgumentError make_research_item(study, ResearchHypothesis; status = :accepted)
            @test_throws ArgumentError make_research_item(study, ResearchHypothesis; id = "H1")
        end

        @testset "a holder is an item that holds the item anywhere, and the report only itself" begin
            study = make_research_study_document_example()
            study.experiments[1].design = study.results[1]
            error = try
                make_delete_research_item_operation(study, study.results[1]); nothing
            catch caught
                caught
            end
            @test error isa ArgumentError && occursin("R1 is held by X1", error.msg)
            embed_in_study!(study, study.evidence[1]; editor = nothing)
            holders = collect_research_item_holders(study, study.hypotheses[1])
            @test [holder.id for holder in holders] == ["X1", "N1", "E1", "D2"]
            @test collect_research_item_holders(study, study.evidence[1])[end] === study.report
        end

        @testset "a delete takes the id of the item out of the folded cards" begin
            study = make_research_study_document_example()
            study.folded = ["Q1", "A1"]
            evaluate_operation(nothing, make_delete_research_item_operation(study, study.answers[1]))
            @test study.folded == ["Q1"]
            @test length(study.answers) == 0
        end

        @testset "the links of an item, in the order of its fields" begin
            study = make_research_study_document_example()
            links = collect_research_links(study.decisions[2])
            @test [first(link) for link in links] == [:accepts, :accepts, :accepts, :basis]
            @test [last(link).id for link in links] == ["H1", "E1", "S1", "E1"]
            @test find_study_item(study, "R1") === study.results[1]
            @test find_study_item(study, "R9") === nothing
        end
    end
end
