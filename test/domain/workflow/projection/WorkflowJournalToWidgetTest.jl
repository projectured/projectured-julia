# The table of a journal view as the view prints it now: the second row of its
# layout. The output is a computed cell, so a read after an edit sees the edit.
_get_journal_table(iomap) = iomap.output.children[2]

# The text of each cell of a row of the table.
_get_journal_row_texts(table, r) = [cell.content for cell in table.cells[r]]

"""
    test_workflow_journal_to_widget()

The table of a journal: one row for each entry of the tree, the newest first,
and a pick of a kind that keeps only the entries of that kind, in the view that
an editor keeps.
"""
function test_workflow_journal_to_widget()
    @testset "WorkflowJournalToWidget" begin
        @testset "a row for each entry, the newest first" begin
            journal = make_workflow_journal_document_example()
            iomap = print_document(WorkflowJournalToWidget(), nothing, journal, nothing)
            table = _get_journal_table(iomap)
            @test length(table.cells) == 3
            @test _get_journal_row_texts(table, 1) ==
                  ["2026-10-09 14:02", "assistant", "decision", "How to store a workflow",
                   "Store a workflow as .pred with markers."]
            @test _get_journal_row_texts(table, 3)[4] == "Workflow domain"
        end

        @testset "a kind keeps only its entries, and a new entry shows at the top" begin
            journal = make_workflow_journal_document_example()
            iomap = print_document(WorkflowJournalToWidget(), nothing, journal, nothing)
            journal.kind = :comment
            @test length(_get_journal_table(iomap).cells) == 1
            journal.kind = :all
            evaluate_operation(nothing, make_add_workflow_entry_operation(journal.workflow.children[4],
                make_workflow_entry("Started the tools."; time = "2026-10-09T16:00:00")))
            table = _get_journal_table(iomap)
            @test length(table.cells) == 4
            @test _get_journal_row_texts(table, 1)[4] == "Assistant tools"
            @test _get_journal_row_texts(table, 1)[5] == "Started the tools."
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
