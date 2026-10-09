# A folder with three workflow files, a `.pred` file of another document and a
# text file: the catalog lists the three workflows and nothing else.
function _make_workflow_folder()
    folder = mktempdir()
    older = WorkflowStep(title = PrimitiveString("Older"),
                         journal = [WorkflowEntry(time = "2026-10-01T10:00:00")])
    question = WorkflowStep(title = PrimitiveString("Open question"),
                            children = [make_workflow_decision("Which one", ["x", "y"])])
    write(joinpath(folder, "a.pred"), print_pred_text(older))
    write(joinpath(folder, "b.pred"), print_pred_text(make_workflow_document_example()))
    write(joinpath(folder, "c.pred"), print_pred_text(question))
    write(joinpath(folder, "other.pred"), print_pred_text(PrimitiveString("not a workflow")))
    write(joinpath(folder, "note.txt"), "a note")
    folder
end

_get_catalog_table(iomap) = iomap.output.children[2]

"""
    test_workflow_catalog_to_widget()

The catalog of the workflows of a folder: one row for each workflow file, the
last worked on first, with its state, its active steps, its last entry and its
open decisions; a press on a goal opens its file, and "Read again" reads a file
that came after the view was built.
"""
function test_workflow_catalog_to_widget()
    @testset "WorkflowCatalogToWidget" begin
        @testset "a row for each workflow file, the last worked on first" begin
            folder = _make_workflow_folder()
            @test [basename(first(pair)) for pair in collect_workflow_files(folder)] == ["b.pred", "a.pred", "c.pred"]
            catalog = WorkflowCatalog(folder = folder)
            @test get_document_title(catalog) == "Workflows in " * basename(folder)
            table = _get_catalog_table(print_document(WorkflowCatalogToWidget(), nothing, catalog, nothing))
            @test length(table.cells) == 3
            row = table.cells[1]
            @test row[1].action.label == "Workflow domain"
            @test [cell.content for cell in row[2:6]] ==
                  ["active", "Workflow domain, Outline view", "2026-10-09 14:02", "0", "b.pred"]
            @test table.cells[3][1].action.label == "Open question"
            @test table.cells[3][5].content == "1"
            @test isempty(collect_workflow_files(joinpath(folder, "missing")))
        end

        @testset "a press on a goal opens its file, and Read again reads a new file" begin
            folder = _make_workflow_folder()
            catalog = WorkflowCatalog(folder = folder)
            editor = _make_workflow_view_editor(catalog)
            opens(name) = operation -> operation isa OpenFileOperation && basename(operation.path) == name
            @test _find_workflow_click(editor, opens("b.pred")) !== nothing
            @test _find_workflow_click(editor, opens("d.pred")) === nothing
            write(joinpath(folder, "d.pred"), print_pred_text(WorkflowStep(title = PrimitiveString("New"))))
            again = _find_workflow_click(editor, operation -> _is_workflow_write(operation, catalog, ".version"))
            @test again !== nothing
            _apply_workflow_operation!(editor, again[3])
            @test catalog.version == 1
            @test _find_workflow_click(editor, opens("d.pred")) !== nothing
        end
    end
end
