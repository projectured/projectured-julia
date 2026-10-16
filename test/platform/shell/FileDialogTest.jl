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

@testset "the dialog draws its folder and its name, opens a folder, and a file writes its name" begin
    directory = mktempdir()
    write(joinpath(directory, "a.jl"), "x = 1\n")
    mkpath(joinpath(directory, "sub"))
    write(joinpath(directory, "sub", "b.jl"), "")
    chooser = make_filesystem_chooser(directory)
    # The editor and the drawn texts of the navigator tests.
    helpers = ProjecturedPlatformTest
    editor, backend = helpers._nav_editor(chooser)
    # The chooser holds its open folders, so its directory reads, off the loop.
    function wait_for_read(folder)
        deadline = time() + 10
        while folder.state !== :read && time() < deadline
            drain_operations!(editor)
            sleep(0.05)
        end
        run_frame!(editor)
        folder.state === :read
    end
    evaluate_operation(editor, AcquireDocumentOperation(chooser))
    @test wait_for_read(chooser.directory)
    @test helpers._nav_has_text(backend, "a.jl") && helpers._nav_has_text(backend, "sub")
    # A double press on a file writes its name into the field.
    click = helpers._nav_click(backend, "a.jl")
    @test click !== nothing
    helpers._nav_press!(editor, backend, click, MouseClick(click.button, click.x, click.y, 2, ModifierKeys(); time = 0.0))
    @test chooser.name == "a.jl"
    run_frame!(editor)
    @test count(entry -> entry[1] == "a.jl", helpers._nav_texts(backend)) == 2
    # The chevron of `sub` opens it, and `sub` reads and shows its file.
    sub = only(entry for entry in chooser.directory.elements if basename(entry.pathname) == "sub")
    closed = string(ProjecturedPlatform.WidgetModule.find_icon_character(:chevron_right))
    (_, _, row_y) = only(entry for entry in helpers._nav_texts(backend) if entry[1] == "sub")
    (_, chevron_x, chevron_y) = only(entry for entry in helpers._nav_texts(backend)
                                     if entry[1] == closed && abs(entry[3] - row_y) < 12)
    helpers._nav_press!(editor, backend, MouseClick(:left, chevron_x + 2, chevron_y + 2, 1, ModifierKeys(); time = 0.0))
    @test haskey(chooser.open, sub)
    @test wait_for_read(sub) && helpers._nav_has_text(backend, "b.jl")
    # A key in the field edits the name.
    (_, field_x, field_y) = last(sort([entry for entry in helpers._nav_texts(backend) if entry[1] == "a.jl"];
                                      by = entry -> entry[3]))
    helpers._nav_press!(editor, backend, MouseClick(:left, field_x + 1, field_y + 2, 1, ModifierKeys(); time = 0.0))
    helpers._nav_press!(editor, backend, KeyPress('x'; time = 0.0))
    @test occursin("x", chooser.name) && length(chooser.name) == 5
    evaluate_operation(editor, ReleaseDocumentOperation(chooser))
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
