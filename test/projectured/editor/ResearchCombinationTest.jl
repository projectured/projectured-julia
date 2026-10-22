# A study combines with the domains that exist: a Markdown report holds its items,
# a workflow card holds an item, an analysis holds a formula sheet, a result holds
# a pivot, and the assistant of an application window starts a study that the
# explorer and a tab show.

# An editor that shows `document` through the renderer of any document, with a font
# of fixed size, so the places of the parts are the same on every machine.
function _make_combination_editor(document)
    editor = make_editor(document, NaturalToGraphics(; measure = FixedMeasure(10, 18, 6, 0));
                         backend = HeadlessBackend())
    run_frame!(editor)
    editor
end

# Whether a click somewhere on the view of `editor` selects a place whose path, as
# a text, satisfies `accept`.
function _has_combination_click(editor, accept)
    for y in 0:6:1500, x in 0:6:1300
        operation = read_intent(editor.projection, editor.iomap, MouseClick(:left, x, y; time = 0.0))
        operation isa ReplaceSelectionOperation &&
            accept(string(strip_reference_types(operation.path))) && return true
    end
    false
end

"""
    test_research_combinations()

The items of a study in the documents of other domains, and a study that the
assistant of a window starts: each part saves, loads to the same object, and
draws through the view of its own domain.
"""
function test_research_combinations()
    @testset "ResearchCombination" begin
        @testset "a Markdown report holds an item, saves a pred-ref fence, and draws its card" begin
            directory = mktempdir()
            try
                study = make_research_study_document_example()
                add_study_section!(study, "The claim", "The study tests this claim."; editor = nothing)
                embed_in_study!(study, study.hypotheses[1]; editor = nothing)
                save_study_folder!(study, directory)
                @test occursin("```pred-ref", read(joinpath(directory, "study.md"), String))
                loaded = load_study_folder(directory)
                @test loaded.report.elements[end] === loaded.hypotheses[1]
                editor = _make_combination_editor(loaded.report)
                @test _has_combination_click(editor, path -> occursin("statement.value", path))
            finally
                rm(directory; recursive = true, force = true)
            end
        end

        @testset "a workflow card holds an experiment, and the project gives back the same object" begin
            directory = mktempdir()
            try
                study = make_research_study_document_example()
                experiment = study.experiments[1]
                workflow = WorkflowStep(title = PrimitiveString("Validate the model"),
                                        cards = [WorkflowCard(title = PrimitiveString("The sweep"),
                                                              content = experiment)])
                project = FileProject(directory, Any[PredFile("study.pred", study),
                                                     PredFile("work.pred", workflow)])
                @test save_project!(project)
                @test occursin("node(file(\"study.pred\"), \"experiments[1]\")",
                               read(joinpath(directory, "work.pred"), String))
                loaded = load_project(directory, ["study.pred", "work.pred"])
                study_back = get_file_content(loaded.files[1])
                workflow_back = get_file_content(loaded.files[2])
                @test workflow_back.cards[1].content === study_back.experiments[1]
                editor = _make_combination_editor(workflow_back)
                @test _has_combination_click(editor, path -> occursin("title.value", path))
            finally
                rm(directory; recursive = true, force = true)
            end
        end

        @testset "a study folder keeps an item that a workflow design holds in the study file" begin
            directory = mktempdir()
            try
                study = make_research_study_document_example()
                experiment = study.experiments[1]
                experiment.design = WorkflowStep(title = PrimitiveString("Run the sweep"),
                    cards = [WorkflowCard(title = PrimitiveString("The plan"), content = experiment)])
                save_study_folder!(study, directory)
                @test readdir(directory) == ["study.pred"]
                text = read(joinpath(directory, "study.pred"), String)
                @test count("ResearchExperiment(", text) == 1
                @test occursin("content = node(file(\"study.pred\"), \"experiments[1]\")", text)
                loaded = load_study_folder(directory)
                @test loaded.experiments[1].design.cards[1].content === loaded.experiments[1]
            finally
                rm(directory; recursive = true, force = true)
            end
        end

        @testset "a result holds a pivot in its pane, which its card draws" begin
            # A pivot scrolls its own rows, so a document holds it in a pane that
            # offers it a height, as the examples of the pivot domain do.
            study = make_research_study_document_example()
            result = make_research_item(study, ResearchResult; author = :assistant,
                                        time = "2026-10-22T09:00:00Z", title = "Sales by region",
                                        content = make_pivot_pane_document_example())
            evaluate_operation(nothing, make_add_research_item_operation(study, result))
            editor = _make_combination_editor(result)
            @test _has_combination_click(editor, path -> startswith(path, ".title.value"))
            @test study.analyses[1].method isa FormulaEnvironment
        end

        @testset "the assistant of a window starts a study that the explorer and a tab show" begin
            directory = mktempdir()
            try
                editor = _make_assistant_verbs_application(directory)
                answer = _run_assistant_code(editor, """
                    study_1 = start_study!("The buffer of the access router";
                                           question = "Which queue capacity is enough?")
                    add_hypothesis!(study_1, "Thirteen."; question = "Q1")
                    print(describe_study(study_1))
                    """)
                @test occursin("H1 [open] Thirteen. (addresses Q1", answer)
                run_frame!(editor)
                entries = find_explorer_content(; editor).entries
                studies = [get_document(entry) for entry in entries if get_document(entry) isa ResearchStudy]
                @test length(studies) == 1
                study = only(studies)
                @test [item.id for item in collect_study_items(study)] == ["Q1", "H1"]
                @test all(item.author === :assistant for item in collect_study_items(study))
                @test study.hypotheses[1].question === study.questions[1]
                @test find_pane("The buffer of the access router"; editor) !== nothing
            finally
                rm(directory; recursive = true, force = true)
            end
        end
    end
end
