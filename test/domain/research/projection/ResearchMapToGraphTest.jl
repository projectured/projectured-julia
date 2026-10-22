"""
    test_research_map_to_graph()

The map of a study: a vertex for each item and a labelled edge for each link, an
edge that follows a new link, the path of a place of an item from the map to the
study and back, and a frame of an editor that draws the map.
"""
function test_research_map_to_graph()
    @testset "ResearchMapToGraph" begin
        @testset "a vertex for each item and a labelled edge for each link" begin
            study = make_research_study_document_example()
            projection = ResearchMapToGraph()
            iomap = print_document(projection, nothing, ResearchMap(study = study), nothing)
            graph = iomap.output
            @test graph isa GraphGraph
            @test [vertex.content.id for vertex in graph.vertices] ==
                  ["Q1", "S1", "H1", "X1", "N1", "R1", "E1", "D1", "D2", "A1"]
            @test length(graph.edges) == 15
            words = Dict{String, String}()
            for edge in graph.edges
                words[edge.source.content.id * ">" * edge.target.content.id] = edge.label.value
            end
            @test words["E1>H1"] == "supports"
            @test words["H1>Q1"] == "addresses"
            @test words["A1>Q1"] == "answers"
            @test words["R1>X1"] == "from"
            @test words["D2>S1"] == "accepts"
            @test words["D2>E1"] == "accepts, rests on"
            @test all(edge.directed for edge in graph.edges)
        end

        @testset "an edge follows a new link" begin
            study = make_research_study_document_example()
            projection = ResearchMapToGraph()
            iomap = print_document(projection, nothing, ResearchMap(study = study), nothing)
            evidence = make_research_item(study, ResearchEvidence; time = "2026-10-22T09:00:00Z",
                                          statement = "At K = 12 the drop rate is 1.13 %.",
                                          basis = ["R1"], opposes = ["H1"])
            evaluate_operation(nothing, make_add_research_item_operation(study, evidence))
            graph = iomap.output
            @test length(graph.vertices) == 11
            @test length(graph.edges) == 17
            @test any(edge -> edge.source.content === evidence && edge.label.value == "opposes", graph.edges)
        end

        @testset "a place of an item maps from the study to its vertex and back" begin
            study = make_research_study_document_example()
            projection = ResearchMapToGraph()
            research_map = ResearchMap(study = study)
            iomap = print_document(projection, nothing, research_map, nothing)
            forward = map_reference_forward(projection, iomap,
                Reference(FieldReferenceStep("study"), FieldReferenceStep("hypotheses"),
                          RangeReferenceStep(0, 1), FieldReferenceStep("statement")))
            @test string(strip_reference_types(forward)) == ".vertices[3].content.statement"
            backward = map_reference_backward(projection, iomap, forward)
            @test string(strip_reference_types(backward)) == ".study.hypotheses[1].statement"
        end

        @testset "the projection of the map draws the example to graphics" begin
            research_map = ResearchMap(study = make_research_study_document_example())
            projection = make_research_map_projection(; measure = FixedMeasure(10, 18, 6, 0))
            iomap = print_document(projection, nothing, research_map, PrinterContext())
            @test iomap.output isa GraphicsCanvas
        end

        @testset "an editor draws the map of the example" begin
            research_map = ResearchMap(study = make_research_study_document_example())
            editor = make_editor(research_map, NaturalToGraphics(; measure = FixedMeasure(10, 18, 6, 0));
                                 backend = HeadlessBackend())
            run_frame!(editor)
            @test editor.iomap !== nothing
            @test get_document_title(research_map) == "Map of The buffer of the access router"
        end
    end
end
