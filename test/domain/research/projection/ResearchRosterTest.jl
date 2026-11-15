"""
    test_research_roster()

The items of a study as the rows of a roster: one row for each item, the facets
`kind` and `text`, the time that sorts as a text, the rows of the assistant, a new
item that shows as a new row, and the items of a study found inside a collection,
each once.
"""
function test_research_roster()
    @testset "ResearchRoster" begin
        columns = ["time", "author", "id", "kind", "status", "text"]

        @testset "a row for each item, with its kind and its text" begin
            study = make_research_study_document_example()
            roster = Roster(StudyItems(study); columns, title = "Timeline")
            link_roster!(roster, study)
            rows = collect(roster.rows)
            @test [row.values[3] for row in rows] == ["Q1", "S1", "H1", "X1", "N1", "R1", "E1", "D1", "D2", "A1"]
            experiment = rows[4]
            @test experiment.values[4] == "experiment"
            @test experiment.values[6] == "Sweep K = 1 … 20, 5 replications"
            @test experiment.values[5] === :accepted
            @test rows[8].values[5] === nothing
        end

        @testset "the time sorts as a text, and the author keeps the rows of the assistant" begin
            study = make_research_study_document_example()
            roster = Roster(StudyItems(study); columns, title = "Timeline")
            link_roster!(roster, study)
            rows = collect(roster.rows)
            by_time = sort(rows; by = row -> row.values[1])
            @test [row.values[3] for row in by_time] == ["Q1", "S1", "H1", "X1", "D1", "N1", "R1", "E1", "D2", "A1"]
            @test [row.values[3] for row in rows if row.values[2] === :assistant] ==
                  ["S1", "H1", "X1", "N1", "R1", "E1"]
        end

        @testset "a new item shows as a new row" begin
            study = make_research_study_document_example()
            roster = Roster(StudyItems(study); columns, title = "Timeline")
            link_roster!(roster, study)
            @test length(roster.rows) == 10
            note = make_research_item(study, ResearchSource; author = :assistant,
                                      time = "2026-10-22T09:00:00Z", citation = "Gross and Harris, 1998")
            evaluate_operation(nothing, make_add_research_item_operation(study, note))
            @test length(roster.rows) == 11
            @test roster.rows[3].values[3] == "S2"
        end

        @testset "the items inside a collection of studies are each one row" begin
            study = make_research_study_document_example()
            roster = Roster(ItemsWithin(CollectionItems(CellVector(Any[study])), ResearchItem);
                            columns = ["id"], title = "Items")
            link_roster!(roster, study)
            ids = [row.values[1] for row in roster.rows]
            @test sort(ids) == sort(["Q1", "S1", "H1", "X1", "N1", "R1", "E1", "D1", "D2", "A1"])
        end
    end
end
