"""
    test_research_explorer()

A study in the explorer: its children are its items in the order of the kinds,
each named by its id and its text and decorated with its kind, its status and its
author; the `+` of a section offers a new study; and a section holds a study as
any other entry.
"""
function test_research_explorer()
    @testset "ResearchExplorer" begin
        @testset "the children of a study are its items, each with its id and its text" begin
            study = make_research_study_document_example()
            children = collect_tree_children(study; limit = 100)
            @test [last(child).id for child in children] ==
                  ["Q1", "S1", "H1", "X1", "N1", "R1", "E1", "D1", "D2", "A1"]
            @test string(strip_reference_types(first(children[3]))) == ".hypotheses[1]"
            @test format_tree_node_label(study) == "The buffer of the access router"
            @test format_tree_node_label(study.hypotheses[1]) == "H1 A queue capacity of 13 is enough."
            @test has_tree_children(study)
        end

        @testset "an item is decorated with its kind, its status and its author" begin
            study = make_research_study_document_example()
            hypothesis = get_document_decoration(study.hypotheses[1])
            @test hypothesis.icon === :diamond
            @test hypothesis.detail == "assistant"
            @test [count.text for count in hypothesis.counts] == ["accepted"]
            @test hypothesis.counts[1].role === :success
            analysis = get_document_decoration(study.analyses[1])
            @test analysis.icon === :sigma
            @test isempty(analysis.counts)
            @test get_document_decoration(study.decisions[1]).detail == "person"
            whole = get_document_decoration(study)
            @test whole.icon === :layers
            @test whole.counts[1].text == "10"
        end

        @testset "the + of a section offers a new study" begin
            @test is_explorer_entry_type(ResearchStudy)
            @test ResearchStudy in filter(is_explorer_entry_type, get_insertion_candidates(Document))
            study = make_insertion_document(ResearchStudy)
            @test study isa ResearchStudy
            @test format_tree_node_label(study) == "New study"
            @test "study" in get_insertion_aliases(ResearchStudy)
            @test isempty(collect_tree_children(study; limit = 10))
        end
    end
end
