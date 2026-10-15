# The facets of the first examples: the type of a document, a field that wins over
# a facet of a supertype, the name, the folder and the edits of a file, the facets
# of an assistant, and in an editor a key press that makes the row of its file show
# the edits, and a save that clears them. And the name and the status of a task,
# with the kind of its group, through the records of the tasks of the session.

# A record whose own field has the name of a facet that every document has.
@document struct _RosterTyped
    type::String
end

# A kind of task that a roster of tasks lists by its line.
struct _RosterFacetTask <: ProjecturedPlatform.TaskModule.AbstractTask
    name::String
end
ProjecturedPlatform.TaskModule.format_task_parameters(task::_RosterFacetTask) = task.name
ProjecturedPlatform.TaskModule.get_result_codes(::_RosterFacetTask) = ProjecturedPlatform.TaskModule.RUN_RESULT_CODES

function test_roster_facets()
@testset "the facets of the first examples" begin
    @testset "the type of a document, and a field that wins over a facet" begin
        documents = CellVector(Cell[Cell(PrimitiveString("a")), Cell(PrimitiveNumber(1)), Cell(_RosterTyped("own"))])
        roster = link_roster!(Roster(CollectionItems(documents); columns = ["type"]), documents)
        @test [row.values[1] for row in roster.rows] == ["PrimitiveString", "PrimitiveNumber", "own"]
        @test !any(facet -> first(facet) == "type", collect_item_facets(_RosterTyped))
        @test first.(collect_item_facets(PrimitiveString)) == ["type"]
        @test first.(collect_item_facets(Assistant)) ==
              ["title", "turn", "tokens", "plan", "subagents", "background_tasks", "type"]
        @test first.(collect_item_facets(TextFile)) == ["name", "folder", "has_edits", "type"]
    end

    @testset "the name, the folder and the edits of a file" begin
        folder = mktempdir()
        buffer = UndoBuffer(PrimitiveString("text"))
        file = TextFile(joinpath(folder, "notes.txt"), buffer)
        files = CellVector(Cell[Cell(file)])
        roster = link_roster!(Roster(CollectionItems(files); columns = ["name", "folder", "has_edits"]), files)
        row = roster.rows[1]
        @test row.values[1] == "notes.txt" && row.values[2] == folder
        @test row.values[3] == false
        push_undo_entry!(buffer, UndoEntry("an edit", nothing, nothing))
        @test row.values[3] == true
        evaluate_operation(nothing, SaveFileOperation(file))
        @test read(joinpath(folder, "notes.txt"), String) == "text"
        @test row.values[3] == false
        push_undo_entry!(buffer, UndoEntry("another edit", nothing, nothing))
        @test row.values[3] == true
        clear_undo_history!(buffer)
        @test row.values[3] == false
        # A file that keeps no history can not say.
        plain = CellVector(Cell[Cell(TextFile("plain.txt", "x"))])
        @test link_roster!(Roster(CollectionItems(plain); columns = ["has_edits"]), plain).rows[1].values[1] === nothing
    end

    @testset "in an editor, a key press shows the edits of its file, and a save clears them" begin
        folder = mktempdir()
        file = TextFile(joinpath(folder, "typed.txt"), UndoBuffer(PrimitiveString("text")))
        natural = NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0),
                                    extra = Pair{Type,Any}[UndoBuffer => UndoBufferToAnyProjection()])
        backend = HeadlessBackend()
        editor = build_editor(file, natural; backend, devices = Device[Keyboard(), Mouse(), Display()],
                              window = false, tabs = true, appearance = false, settings = false)
        run_frame!(editor)
        frame!() = (drain_operations!(editor); run_frame!(editor))
        roster = link_roster!(Roster(TabDocuments(FileDocument); columns = ["name", "has_edits"]), editor.document)
        @test [(row.values[1], row.values[2]) for row in roster.rows] == [("typed.txt", false)]
        (x, y) = _arrangement_place(backend, "text")
        _arrangement_press!(editor, backend, MouseMove(x, y; time = 0.0),
                            MouseClick(:left, x, y, 1, ModifierKeys(); time = 0.0))
        frame!()
        _arrangement_press!(editor, backend, KeyPress('x'; time = 0.0))
        frame!()
        @test occursin("x", get_wrapped_document(file.content).value)
        @test roster.rows[1].values[2] == true
        evaluate_operation(editor, SaveFileOperation(file))
        @test roster.rows[1].values[2] == false
    end

    @testset "the name and the status of a task, and the kind of its group" begin
        TaskModule = ProjecturedPlatform.TaskModule
        fingerprint = TaskModule.wrap_task_group_document(
            TaskModule.TaskGroup([_RosterFacetTask("run one"), _RosterFacetTask("run two")]; name = "fingerprint test");
            title = "queue study")
        smoke = TaskModule.wrap_task_group_document(TaskModule.TaskGroup([_RosterFacetTask("run three")]; name = "smoke test"))
        list = TaskModule.get_session_task_group_list()
        TaskModule.add_task_group!(list, fingerprint)
        TaskModule.add_task_group!(list, smoke)
        try
            roster = link_roster!(Roster(StoreRecords(:tasks); columns = ["name", "status", "within.title", "within.kind"]),
                                  list)
            mine = [Tuple(row.values[k] for k in 1:4) for row in roster.rows
                    if row.values[4] in ("fingerprint test", "smoke test")]
            @test sort(mine) == sort([("run one", :pending, "queue study", "fingerprint test"),
                                      ("run two", :pending, "queue study", "fingerprint test"),
                                      ("run three", :pending, "smoke test", "smoke test")])
            @test first.(collect_item_facets(TaskModule.TaskDocument))[1:2] == ["name", "status"]
            @test first.(collect_item_facets(TaskModule.TaskGroupDocument))[1] == "kind"
        finally
            TaskModule.remove_task_group!(list, fingerprint)
            TaskModule.remove_task_group!(list, smoke)
        end
    end
end
end
