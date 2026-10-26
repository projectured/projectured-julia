# The item of each vertex of the map of `study`: the vertices stand in the order of
# the items of the study.
_get_map_items(study, graph) =
    IdDict{Any, Any}(vertex => item for (vertex, item) in zip(graph.vertices, collect_study_items(study)))

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
            items = _get_map_items(study, graph)
            @test [items[vertex].id for vertex in graph.vertices] ==
                  ["Q1", "S1", "H1", "X1", "N1", "R1", "E1", "D1", "D2", "A1"]
            # The content of a vertex is the small row of its item.
            @test all(vertex -> vertex.content isa WidgetCard && vertex.content.variant === :row, graph.vertices)
            @test length(graph.edges) == 15
            words = Dict{String, String}()
            unlined = String[]
            for edge in graph.edges
                name = items[edge.source].id * ">" * items[edge.target].id
                edge.visible ? (words[name] = edge.label.children[1].content) : push!(unlined, name)
            end
            @test words["E1>H1"] == "supports"
            @test words["H1>Q1"] == "addresses"
            @test words["A1>Q1"] == "answers"
            @test words["R1>X1"] == "from"
            # What a decision settled joins it with no line; another link of the
            # same items keeps the line, with its own word.
            @test "D2>S1" in unlined
            @test words["D2>E1"] == "rests on"
            @test all(edge.directed for edge in graph.edges)
        end

        @testset "the vertex of the item under the pointer lights, with the items it joins" begin
            study = make_research_study_document_example()
            research_map = ResearchMap(study = study)
            projection = make_research_map_projection(; measure = FixedMeasure(10, 18, 6, 0))
            iomap = print_document(projection, nothing, research_map, PrinterContext())
            light = get_theme_defaults(GraphTheme).light
            # The map is in a scroll pane, whose viewport holds the drawing.
            lit_rings(canvas) = sum((element isa GraphicsRect && element.color == unwrap_cell(light) ? 1 :
                                     element isa GraphicsCanvas ? lit_rings(element) :
                                     element isa GraphicsViewport ? lit_rings(element.content) : 0
                                     for element in canvas.elements); init = 0)
            @test lit_rings(iomap.output) == 0
            decision = study.decisions[2]
            replace_mouse_target!(research_map, Reference(FieldReferenceStep("study"), FieldReferenceStep("decisions"),
                                                          RangeReferenceStep(1, 2)))
            # The decision, each item it accepts or rests on, through a line or not,
            # and each item that links to it.
            joined = Base.IdSet{Any}(linked for (_, linked) in collect_research_links(decision))
            for item in collect_study_items(study), (_, linked) in collect_research_links(item)
                linked === decision && push!(joined, item)
            end
            @test lit_rings(iomap.output) == length(joined) + 1
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
            items = _get_map_items(study, graph)
            @test any(edge -> items[edge.source] === evidence && edge.label.children[1].content == "opposes", graph.edges)
        end

        @testset "a place of an item maps from the study to its vertex and back" begin
            study = make_research_study_document_example()
            projection = ResearchMapToGraph()
            research_map = ResearchMap(study = study)
            iomap = print_document(projection, nothing, research_map, nothing)
            forward = map_reference_forward(projection, iomap,
                Reference(FieldReferenceStep("study"), FieldReferenceStep("hypotheses"),
                          RangeReferenceStep(0, 1), FieldReferenceStep("statement")))
            @test string(strip_reference_types(forward)) == ".vertices[3].content.content.children[2].child"
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
