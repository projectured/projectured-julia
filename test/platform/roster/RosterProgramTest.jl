# The verbs that code and a model use: a roster shown in a tab with the short form
# of its arrangement, the roster that prints how it shows, the verbs of the
# arrangement on its rows, an edit of every shown item as one step of undo, the words
# of the sources and of the keys, and the examples of the plan that the platform
# runs.

function test_roster_program()
@testset "the verbs of the assistant" begin
    make_runs() = CellVector(Cell[Cell(_RosterRun(1, "done", 0.31)), Cell(_RosterRun(2, "failed", 0.12)),
                                  Cell(_RosterRun(3, "done", 0.54))])
    function make_editor(document)
        natural = NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0))
        editor = build_editor(document, natural; backend = HeadlessBackend(),
                              devices = Device[Keyboard(), Mouse(), Display()],
                              window = false, tabs = true, appearance = false, settings = false, undo = true)
        run_frame!(editor)
        editor
    end
    frame!(editor) = (drain_operations!(editor); run_frame!(editor))

    @testset "a roster in a tab, how it shows, and the verbs of the arrangement" begin
        runs = make_runs()
        editor = make_editor(PrimitiveString("start"))
        rows = show_roster!(CollectionItems(runs); title = "Runs", columns = ["id", "status", "delay"],
                            filter = ["status" => ==("done")], sort = ["delay" => :descending], editor)
        frame!(editor)
        @test rows isa ReferencedDocument
        text = string(describe_roster(rows))
        @test startswith(text, "Runs: 2 of 3 items: status = \"done\", ↓ delay")
        @test occursin("id | status | delay\n3 | done | 0.54\n1 | done | 0.31", text)
        # The roster prints how it shows, and a roster with no window shows no row.
        @test startswith(repr(rows), "Runs: 2 of 3 items")
        loose = ReferencedDocument(Roster(CollectionItems(runs); columns = ["id"], title = "Loose"), EmptyReference())
        @test string(describe_roster(loose)) == "Loose: 0 items, all in their own order"
        @test string(limit_collection!(rows, 1; editor)) == "1 of 3 items: status = \"done\", ↓ delay, first 1"
        frame!(editor)
        # One edit of every item that the roster shows, which one undo takes back.
        before = length(editor.document.undo_entries)
        @test string(edit_shown_items!(rows, "status" => "checked"; editor)) == "Set status in 1 item to \"checked\"."
        frame!(editor)
        @test [run.status for run in runs] == ["done", "failed", "checked"]
        @test length(editor.document.undo_entries) == before + 1
        @test_throws ArgumentError edit_shown_items!(rows, "slow" => true; editor)
        @test string(limit_collection!(rows; editor)) == "1 of 3 items: status = \"done\", ↓ delay"
        frame!(editor)
        @test startswith(string(group_collection!(rows, "status"; editor)), "1 group of 3 items")
        frame!(editor)
        @test_throws ArgumentError edit_shown_items!(rows, "status" => "x"; editor)
    end

    @testset "the words of the sources and of the keys" begin
        sources = string(describe_roster_sources())
        @test all(call -> occursin(call, sources),
                  ["CollectionItems(collection)", "ItemsWithin(source, type)", "StoreRecords(name::Symbol)",
                   "TabDocuments(type)"])
        @test occursin("- :log: the lines of the message log of the session", sources)
        keys = string(describe_item_facets(TextFile))
        @test occursin("- has_edits: whether", keys) && occursin("filename, content", keys)
        @test occursin("- has_edits: whether", string(describe_item_facets(TabDocuments(FileDocument))))
    end

    @testset "the examples of the plan that the platform runs" begin
        editor = make_editor(TextFile("notes.txt", "x"))
        x1 = show_roster!(TabDocuments(FileDocument); title = "Files with edits",
                          columns = ["name", "folder", "has_edits"],
                          filter = ["has_edits" => ==(true), "folder" => contains("source/kernel")],
                          sort = ["name"], editor)
        frame!(editor)
        @test startswith(string(describe_roster(x1)), "Files with edits: 0 of 1 items")
        x2 = show_roster!(TabDocuments(Document); title = "Open documents",
                          columns = ["type"], group = ["type"], aggregates = [:count], editor)
        frame!(editor)
        text = string(describe_roster(x2))
        @test occursin("groups of", text) && occursin("type | count", text) && occursin("TextFile | 1", text)
        x3 = show_roster!(TabDocuments(Assistant); title = "Assistants",
                          columns = ["title", "turn", "tokens"], sort = ["tokens" => :descending], editor)
        frame!(editor)
        @test startswith(string(describe_roster(x3)), "Assistants: 0 of 0 items")
        x6 = show_roster!(StoreRecords(:log); title = "Errors", columns = ["level", "message"],
                          filter = ["level" => ==("Error")], first = 100, editor)
        frame!(editor)
        @test startswith(string(describe_roster(x6)), "Errors: ")
    end
end
end
