"""
    test_research_assistant_api()

The research domain offers its documents and its verbs to the model of an
assistant. Code that a model writes, run as `execute_julia_code` runs it, adds
items and a decision as the assistant, and an undo of the history that holds the
study takes each back. The check of the predictions adds evidence, the verbs of
the report grow the report, a formula goes to the sheet of the closed form, and
`describe_study` says what the study holds.
"""
function test_research_assistant_api()
    @testset "ResearchAssistantApi" begin
        entries = [e for e in get_registered_assistant_api() if e isa Pair && first(e) === ResearchModule]

        @testset "the domain offers its documents and its verbs" begin
            @test length(entries) == 1
            offered = collect(last(only(entries)))
            @test Set(offered) == Set(RESEARCH_ASSISTANT_API)
            @test all(name -> isdefined(ResearchModule, name), offered)
            set = declare_api!(ToolSet(), entries)
            @test occursin("record_decision!", search_api(set, "record_decision!"))
            @test occursin("add_hypothesis!", search_api(set, "add_hypothesis!"))
        end

        @testset "code of a model adds items and a decision as the assistant, and undo takes them back" begin
            study = ResearchStudy(title = PrimitiveString("Buffer"), time = "2026-10-22T07:00:00Z")
            buffer = UndoBuffer(study)
            projection = NaturalToGraphics(; measure = FixedMeasure(10, 18, 6, 0),
                                           extra = Pair{Type,Any}[UndoBuffer => UndoBufferToAnyProjection()])
            editor = make_editor(buffer, projection; backend = HeadlessBackend())
            run_frame!(editor)
            set = declare_api!(ToolSet(), vcat(entries,
                Any[ReferenceModule => (:ReferencedDocument, :EmptyReference)]))
            answer = execute_julia_code!(set, editor, """
                study_1 = ReferencedDocument(editor.document, EmptyReference()).content
                add_question!(study_1, "Which queue capacity is enough?"; purpose = "the capacity that ships")
                hypothesis_1 = add_hypothesis!(study_1, "Thirteen."; question = "Q1")
                add_evidence!(study_1, "At K = 13 the drop rate is 0.91 %."; supports = [hypothesis_1])
                record_decision!(study_1, "Thirteen is enough."; accepts = ["H1", "E1"], basis = ["E1"])
                nothing
                """)
            @test answer == "Done."
            @test [item.id for item in collect_study_items(study)] == ["Q1", "H1", "E1", "D1"]
            @test all(item.author === :assistant for item in collect_study_items(study))
            @test study.evidence[1].supports[1] === study.hypotheses[1]
            @test study.hypotheses[1].status === :accepted
            @test length(buffer.undo_entries) == 4
            evaluate_operation(editor, UndoOperation(buffer))
            @test study.hypotheses[1].status === :open
            @test length(study.decisions) == 0
            evaluate_operation(editor, UndoOperation(buffer))
            @test length(study.evidence) == 0
        end

        @testset "a formula that the code of a model adds is an edit of the history" begin
            study = make_research_study_document_example()
            buffer = UndoBuffer(study)
            projection = NaturalToGraphics(; measure = FixedMeasure(10, 18, 6, 0),
                                           extra = Pair{Type,Any}[UndoBuffer => UndoBufferToAnyProjection()])
            editor = make_editor(buffer, projection; backend = HeadlessBackend())
            run_frame!(editor)
            set = declare_api!(ToolSet(), vcat(entries,
                Any[ReferenceModule => (:ReferencedDocument, :EmptyReference)]))
            sheet = study.analyses[1].method
            count = length(sheet.formulas)
            @test execute_julia_code!(set, editor, """
                add_study_formula!(ReferencedDocument(editor.document, EmptyReference()).content, "twice", "2 * rho")
                nothing
                """) == "Done."
            @test length(sheet.formulas) == count + 1
            evaluate_operation(editor, UndoOperation(buffer))
            @test length(sheet.formulas) == count
        end

        @testset "a check of the predictions adds evidence for and against" begin
            study = make_research_study_document_example()
            hypothesis = study.hypotheses[1]
            strict = make_research_item(study, ResearchHypothesis; time = "2026-10-22T09:00:00Z",
                statement = "A capacity of 13 keeps the drop rate under 0.1 %.",
                prediction = ResearchExpectation(result_selection = PrimitiveString("drop rate at K = 13"),
                                                 upper = 0.001))
            evaluate_operation(nothing, make_add_research_item_operation(study, strict))
            read(selection) = [0.009, 0.009]
            added = check_predictions!(study, read; editor = nothing)
            @test length(added) == 2
            @test added[1].supports[1] === hypothesis
            @test isempty(added[1].opposes)
            @test added[2].opposes[1] === strict
            @test added[1].author === :assistant
            @test occursin("read 2 values with the mean 0.009;", added[1].statement.value)
            again = check_predictions!(study, read; editor = nothing)
            @test [item.id for item in study.evidence] == ["E1", "E2", "E3", "E4", "E5"]
            @test isempty(check_predictions!(ResearchStudy(), read; editor = nothing))
            broken = make_research_item(study, ResearchHypothesis; statement = "No tolerance.",
                prediction = ResearchExpectation(result_selection = PrimitiveString("x"), reference = resolve(study.analyses[1].method, "rho")))
            evaluate_operation(nothing, make_add_research_item_operation(study, broken))
            before = length(study.evidence)
            @test_throws ArgumentError check_predictions!(study, read; editor = nothing)
            @test length(study.evidence) == before
        end

        @testset "the bounds of an expectation follow its reference" begin
            study = make_research_study_document_example()
            sheet = study.analyses[1].method
            p_block = resolve(sheet, "P_block")
            evaluate_operation(nothing, ComputeFormulasOperation(sheet, FormulaFormula[sheet.formulas...]))
            expectation = ResearchExpectation(reference = p_block, tolerance = 0.1)
            lower, upper = get_expectation_bounds(expectation)
            value = get_formula_value(p_block)
            @test value ≈ 0.2 * 0.8^14 / (1 - 0.8^15)
            @test lower ≈ 0.9 * value && upper ≈ 1.1 * value
            negative = FormulaEnvironment([FormulaFormula("m", parse_julia("-2"))])
            evaluate_operation(nothing, ComputeFormulasOperation(negative, FormulaFormula[negative.formulas...]))
            lower, upper = get_expectation_bounds(ResearchExpectation(reference = resolve(negative, "m"), tolerance = 0.1))
            @test lower ≈ -2.2 && upper ≈ -1.8
        end

        @testset "the verbs of the report grow the report, and an item in it is the item" begin
            study = make_research_study_document_example()
            heading = add_study_section!(study, "The model", "A source feeds a queue."; editor = nothing)
            @test study.report isa MarkdownRoot
            @test occursin("The model", print_natural_text(heading))
            add_study_prose!(study, "The load is 0.8."; editor = nothing)
            embed_in_study!(study, study.evidence[1]; editor = nothing)
            @test length(study.report.elements) == 4
            @test study.report.elements[4] === study.evidence[1]
        end

        @testset "a formula goes to the sheet of the closed form" begin
            study = make_research_study_document_example()
            formula = add_study_formula!(study, "twice", "2 * rho"; editor = nothing)
            @test study.analyses[1].method.formulas[end] === formula
            @test get_formula_value(formula) ≈ 1.6
            empty_study = ResearchStudy()
            add_study_formula!(empty_study, "one", "1"; editor = nothing)
            @test length(empty_study.analyses) == 1
            @test empty_study.analyses[1].title.value == "Closed form"
            @test empty_study.analyses[1].author === :assistant
        end

        @testset "describe_study says what the study holds" begin
            text = string(describe_study(make_research_study_document_example()))
            @test startswith(text, "The buffer of the access router\n")
            @test occursin("H1 [accepted] A queue capacity of 13 is enough. (addresses Q1", text)
            @test occursin("— assistant, 2026-10-22T07:31:00Z", text)
            @test occursin("\nD2 A queue capacity of 13 is enough. (accepts H1", text)
        end

        @testset "a study saves to a folder and loads to the same graph" begin
            directory = mktempdir()
            try
                study = make_research_study_document_example()
                add_study_section!(study, "The answer", "A queue capacity of 13."; editor = nothing)
                embed_in_study!(study, study.evidence[1]; editor = nothing)
                @test save_study_folder!(study, directory) == directory
                @test Set(readdir(directory)) == Set(["study.pred", "study.md"])
                loaded = load_study_folder(directory)
                @test loaded.evidence[1].supports[1] === loaded.hypotheses[1]
                @test loaded.report.elements[end] === loaded.evidence[1]
                @test loaded.analyses[1].method isa FormulaEnvironment
                stamps = Dict(name => mtime(joinpath(directory, name)) for name in readdir(directory))
                sleep(0.01)
                save_study_folder!(loaded, directory)
                @test all(mtime(joinpath(directory, name)) == stamp for (name, stamp) in stamps)
            finally
                rm(directory; recursive = true, force = true)
            end
        end

        @testset "a node of a text format goes into a file of its format" begin
            directory = mktempdir()
            try
                study = make_research_study_document_example()
                paragraph = parse_markdown("A *queue* of 12 is enough.\n").elements[1]
                hypothesis = make_research_item(study, ResearchHypothesis; statement = paragraph,
                                                prediction = parse_math("P_block(12) < 0.01"))
                evaluate_operation(nothing, make_add_research_item_operation(study, hypothesis))
                save_study_folder!(study, directory)
                @test Set(readdir(directory)) ==
                      Set(["study.pred", "h2-statement-1.md", "h2-prediction-2.math"])
                @test count("ResearchHypothesis(", read(joinpath(directory, "study.pred"), String)) == 2
                loaded = load_study_folder(directory)
                @test nameof(typeof(loaded.hypotheses[2].statement)) == nameof(typeof(paragraph))
                @test loaded.hypotheses[2].prediction isa MathDocument
            finally
                rm(directory; recursive = true, force = true)
            end
        end
    end
end
