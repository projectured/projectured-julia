# Open and Save As: a chooser that names a path, and two commands that make
# something of one.

mutable struct _DialogEditor; document::Any; end

function test_file_dialog()
@testset "the file dialogs" begin

@testset "a chooser names a path" begin
    directory = mktempdir()
    write(joinpath(directory, "a.jl"), "x = 1\n")
    chooser = make_filesystem_chooser(directory)
    # Nothing typed is no file chosen, so it answers the directory itself.
    @test get_chosen_path(chooser) == directory
    chooser.name = "a.jl"
    @test get_chosen_path(chooser) == joinpath(directory, "a.jl")
    # A name that names nothing yet is still a path: that is Save As.
    chooser.name = "new.jl"
    @test get_chosen_path(chooser) == joinpath(directory, "new.jl")
    @test !isfile(get_chosen_path(chooser))
end

@testset "a row of the tree types its own name" begin
    directory = mktempdir()
    write(joinpath(directory, "a.jl"), "x = 1\n")
    chooser = make_filesystem_chooser(directory)
    operation = WriteChosenNameOperation(chooser, "a.jl")
    evaluate_operation(nothing, operation)
    @test chooser.name == "a.jl"
    @test get_chosen_path(chooser) == joinpath(directory, "a.jl")
end

@testset "Open takes a file that exists, and nothing else" begin
    directory = mktempdir()
    write(joinpath(directory, "a.jl"), "x = 1\n")
    dialog, chooser = make_file_dialog(directory, "Open", "Open")
    @test dialog isa WidgetDialog
    @test dialog.content === chooser
    @test length(collect(dialog.buttons)) == 2
end

@testset "the dialog opens as a window of its own" begin
    directory = mktempdir()
    scene = make_window_scene(WidgetLabel("content"), "W"; width = 400, height = 300)
    composed = make_window_scene_projection(make_widget_projection_example())
    document, projection = make_tracking_screen(scene, composed)
    editor = Editor(document, projection; backend = HeadlessBackend(),
                    devices = Device[Keyboard(), Mouse()])
    run_frame!(editor)
    open_file_dialog!(; directory, editor)
    @test length(scene.windows) == 2
    window = last(scene.windows)
    @test window.id === :file_dialog && window.style === :floating
    @test window.content isa WidgetDialog
end

@testset "Save As gives the file its name and then writes it" begin
    directory = mktempdir()
    source = joinpath(directory, "a.json")
    # The notation this test package declares. A format a test reaches for must
    # be a package the test package depends on, or the test passes only in a
    # wider environment.
    write_document_file(parse_natural_text(:json, "{\"x\": 1}"), source)
    file = make_file_tab(source)
    target = joinpath(directory, "b.json")

    # What the confirm button does, without the window: name it, then write it.
    file.filename = target
    evaluate_operation(_DialogEditor(file), SaveFileOperation(file))
    @test file.filename == target
    @test isfile(target)
end

end # @testset
end # function
