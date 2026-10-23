# The rows of the entries of a journal view as the view prints it now, each as the
# text of the entry and the line under it, and the labels of its days. The output
# is a computed cell, so a read after an edit sees the edit.
function _get_journal_rows(iomap)
    rows = Any[]
    for part in iomap.output.children
        if part isa WidgetCard
            body = part.content.children[2].child
            push!(rows, (body.children[1].content, body.children[2].content))
        end
    end
    rows
end

_get_journal_days(iomap) = [part.content for part in iomap.output.children[2:end] if part isa WidgetLabel]

"""
    test_workflow_journal_to_widget()

The timeline of a journal: a group for each day and a row for each entry of the
tree, the newest first, and a pick of a kind that keeps only the entries of that
kind, in the view that an editor keeps.
"""
function test_workflow_journal_to_widget()
    @testset "WorkflowJournalToWidget" begin
        @testset "a row for each entry, the newest first, under the label of its day" begin
            journal = make_workflow_journal_document_example()
            iomap = print_document(WorkflowJournalToWidget(), nothing, journal, nothing)
            rows = _get_journal_rows(iomap)
            @test length(rows) == 3
            @test rows[1] == ("Store a workflow as .pred with markers.", "How to store a workflow · decision")
            @test endswith(rows[3][2], "· state") || startswith(rows[3][2], "Workflow domain")
            @test _get_journal_days(iomap) == ["9 OCT"]
        end

        @testset "a kind keeps only its entries, and a new entry shows at the top" begin
            journal = make_workflow_journal_document_example()
            iomap = print_document(WorkflowJournalToWidget(), nothing, journal, nothing)
            journal.kind = :comment
            @test length(_get_journal_rows(iomap)) == 1
            journal.kind = :all
            evaluate_operation(nothing, make_add_workflow_entry_operation(journal.workflow.children[4],
                make_workflow_entry("Started the tools."; time = "2026-10-09T16:00:00")))
            rows = _get_journal_rows(iomap)
            @test length(rows) == 4
            @test rows[1] == ("Started the tools.", "Assistant tools · comment")
        end

        @testset "a click on a choice picks the kind in the view of an editor" begin
            journal = make_workflow_journal_document_example()
            editor = _make_workflow_view_editor(journal)
            hit = _find_workflow_click(editor, operation -> _is_workflow_write(operation, journal, ".kind"))
            @test hit !== nothing
            # The choice that is picked writes nothing; each other one writes its kind.
            picks() = begin
                seen = Set{Symbol}()
                for y in 0:6:60, x in 0:6:600
                    operation = read_intent(editor.projection, editor.iomap, MouseClick(:left, x, y; time = 0.0))
                    _is_workflow_write(operation, journal, ".kind") && push!(seen, operation.value)
                end
                seen
            end
            @test picks() == Set([:decision, :comment, :state, :link])
            decision = _find_workflow_click(editor, operation ->
                _is_workflow_write(operation, journal, ".kind") && operation.value === :decision)
            _apply_workflow_operation!(editor, decision[3])
            @test journal.kind === :decision
            @test picks() == Set([:all, :comment, :state, :link])
        end
    end
end
