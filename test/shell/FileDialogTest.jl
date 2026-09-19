# Open and Save As: a chooser that names a path, and two commands that make
# something of one.

mutable struct _DialogEditor; document::Any; end

function test_file_dialog()
@testset "the file dialogs" begin

@testset "a chooser names a path" begin
    directory = mktempdir()
    write(joinpath(directory, "a.json"), "{}")
    chooser = make_filesystem_chooser(directory)
    # Nothing typed is no file chosen, so it answers the directory itself.
    @test get_chosen_path(chooser) == directory
    chooser.name = "a.json"
    @test get_chosen_path(chooser) == joinpath(directory, "a.json")
    # A name that names nothing yet is still a path: that is Save As.
    chooser.name = "new.json"
    @test get_chosen_path(chooser) == joinpath(directory, "new.json")
    @test !isfile(get_chosen_path(chooser))
end

@testset "a row of the tree types its own name" begin
    directory = mktempdir()
    write(joinpath(directory, "a.json"), "{}")
    chooser = make_filesystem_chooser(directory)
    operation = WriteChosenNameOperation(chooser, "a.json")
    evaluate_operation(nothing, operation)
    @test chooser.name == "a.json"
    @test get_chosen_path(chooser) == joinpath(directory, "a.json")
end

@testset "Open takes a file that exists, and nothing else" begin
    directory = mktempdir()
    write(joinpath(directory, "a.json"), "{}")
    dialog, chooser = make_file_dialog(directory, "Open", "Open")
    @test dialog isa WidgetDialog
    @test dialog.content === chooser
    @test length(collect(dialog.buttons)) == 2
end

@testset "Save As gives the file its name and then writes it" begin
    directory = mktempdir()
    source = joinpath(directory, "a.json")
    write_document_file(parse_natural_text(:json, "{\"a\": 1}"), source)
    file = make_file_tab(source)
    target = joinpath(directory, "b.json")

    # What the confirm button does, without the window: name it, then write it.
    file.filename = target
    evaluate_operation(_DialogEditor(file), SaveFileOperation(file))
    @test file.filename == target
end

end # @testset
end # function
