"""
    test_research_document()

The documents of a study: what a new item holds, the links of the example study,
which hold the items themselves, the time of an item, and the save of a study,
alone and in a project with a Markdown file, which gives back the same graph.
"""
function test_research_document()
    @testset "ResearchDocument" begin
        @testset "a new item is open, made by the person, and links to nothing" begin
            hypothesis = ResearchHypothesis()
            @test hypothesis.statement isa PrimitiveString
            @test hypothesis.status === :open
            @test hypothesis.author === :person
            @test hypothesis.question === nothing
            @test length(hypothesis.basis) == 0
            @test !has_research_status(ResearchDecision())
            @test all(has_research_status(kind.type()) for kind in RESEARCH_KINDS
                      if kind.type !== ResearchDecision)
        end

        @testset "each kind has its field, its letter and its name" begin
            @test [kind.letter for kind in RESEARCH_KINDS] == ["Q", "S", "H", "X", "N", "R", "E", "D", "A"]
            @test get_research_kind(ResearchHypothesis).field === :hypotheses
            @test get_research_kind(ResearchAnalysis()).name == "analysis"
            @test all(hasproperty(ResearchStudy(), kind.field) for kind in RESEARCH_KINDS)
        end

        @testset "a link of the example holds the item itself" begin
            study = make_research_study_document_example()
            q1, s1, h1 = study.questions[1], study.sources[1], study.hypotheses[1]
            x1, n1, r1 = study.experiments[1], study.analyses[1], study.results[1]
            e1, d2, a1 = study.evidence[1], study.decisions[2], study.answers[1]
            @test [item.id for item in collect_study_items(study)] ==
                  ["Q1", "S1", "H1", "X1", "N1", "R1", "E1", "D1", "D2", "A1"]
            @test h1.question === q1 && h1.basis[1] === s1
            @test x1.tests[1] === h1 && n1.uses[1] === s1 && r1.origin === x1
            @test e1.basis[1] === r1 && e1.supports[1] === h1
            @test d2.accepts[1] === h1 && d2.basis[1] === e1
            @test a1.question === q1 && a1.basis[2] === d2
            @test h1.prediction isa ResearchExpectation
            @test n1.method isa FormulaEnvironment
            @test [item.author for item in (q1, s1, h1, e1, d2, a1)] ==
                  [:person, :assistant, :assistant, :assistant, :person, :person]
            @test get_document_title(study) == "The buffer of the access router"
            @test get_research_item_text(x1).value == "Sweep K = 1 … 20, 5 replications"
            @test get_research_item_text(s1) === s1.citation
        end

        @testset "the time of an item is a UTC text that reads back" begin
            text = format_research_time(Dates.DateTime(2026, 10, 22, 7, 12, 0))
            @test text == "2026-10-22T07:12:00Z"
            @test find_research_time(text) == Dates.DateTime(2026, 10, 22, 7, 12, 0)
            @test find_research_time("") === nothing
            @test find_research_time("not a time") === nothing
            @test endswith(get_research_time(), "Z")
            @test find_research_time(get_research_time()) isa Dates.DateTime
        end

        @testset "a study saved alone writes each item once, and loads to the same graph" begin
            directory = mktempdir()
            try
                @test save_file!(PredFile("buffer.pred", make_research_study_document_example()), directory)
                text = read(joinpath(directory, "buffer.pred"), String)
                @test count("ResearchHypothesis(", text) == 1
                @test occursin("node(file(\"buffer.pred\"), \"hypotheses[1]\")", text)
                study = get_file_content(load_file(directory, "buffer.pred"))
                @test study isa ResearchStudy
                h1, e1 = study.hypotheses[1], study.evidence[1]
                @test e1.supports[1] === h1
                @test h1.question === study.questions[1]
                @test study.results[1].origin === study.experiments[1]
                @test study.decisions[2].accepts[3] === study.sources[1]
                @test h1.prediction.upper == 0.01
                @test study.evidence[1].time == "2026-10-22T07:52:00Z"
                stamp = mtime(joinpath(directory, "buffer.pred"))
                sleep(0.01)
                @test save_file!(PredFile("buffer.pred", study), directory)
                @test mtime(joinpath(directory, "buffer.pred")) == stamp
            finally
                rm(directory; recursive = true, force = true)
            end
        end

        @testset "a study in a project writes a Markdown summary into its own file" begin
            directory = mktempdir()
            try
                study = make_research_study_document_example()
                page = parse_markdown("The blocking of M/M/1/K in closed form.\n")
                study.sources[1].summary = page.elements[1]
                project = FileProject(directory, Any[PredFile("buffer.pred", study),
                                                     MarkdownFile("summary.md", page)])
                @test save_project!(project)
                @test occursin("summary = node(file(\"summary.md\")",
                               read(joinpath(directory, "buffer.pred"), String))
                loaded = load_project(directory, ["buffer.pred", "summary.md"])
                study_back = get_file_content(loaded.files[1])
                page_back = get_file_content(loaded.files[2])
                @test study_back.sources[1].summary === page_back.elements[1]
                @test study_back.evidence[1].supports[1] === study_back.hypotheses[1]
            finally
                rm(directory; recursive = true, force = true)
            end
        end
    end
end
