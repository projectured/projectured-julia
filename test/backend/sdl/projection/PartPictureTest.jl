# A picture of a part and of the window, as the editor draws them, written with
# the SDL backend and no window: the window of the application with an
# assistant, a part that an Alt+click selects, and the button that puts a picture
# into the draft.

function test_part_picture()
    @testset "a picture of a part and of the window" begin
        directory = mktempdir()
        path = joinpath(directory, "notes.txt")
        write(path, "one\ntwo\nthree\n")
        assistant = make_application_assistant(:ollama; model = "small")
        document, projection = make_application_window([path]; root = directory, assistant)
        scene = make_window_scene(document, "ProjecturEd"; width = 1600, height = 1000)
        composed = make_window_scene_projection(projection;
            opened_window_projections = make_opened_window_projections())
        editor = Editor(scene, composed; backend = SdlBackend())
        editor.iomap = print_document(composed, scene)
        window = write_window_picture(editor, nothing, joinpath(directory, "window.png"))
        @test window isa ImageFile
        @test _read_png_size(window.filename) == (1600, 1000)
        # An Alt+click on the assistant selects a part of its conversation as a whole.
        press = MouseClick(:left, 1300, 300, 1, ModifierKeys(alt = true); time = 0.0)
        change = read_intent(composed, nothing, Intent(WindowInput(:ProjecturEd, press)), editor.iomap)
        evaluate_operation(editor, change.operation)
        drain_operations!(editor)
        selection = get_selection(editor.document)
        @test is_whole_selection(editor.document, selection)
        part = write_part_picture(editor, selection, joinpath(directory, "part.png"))
        @test part isa ImageFile
        width, height = _read_png_size(part.filename)
        @test 0 < width < 600 && 0 < height < 1000
        # The button puts the picture of that part into the draft, before the text.
        withenv("XDG_CACHE_HOME" => directory) do
            evaluate_operation(editor, AddDraftPictureOperation(assistant))
        end
        parts = collect(assistant.draft.parts)
        @test length(parts) == 2
        @test parts[1].content isa ImageFile && parts[2].content isa PrimitiveString
        @test startswith(parts[1].content.filename, joinpath(directory, "projectured", "pictures"))
        @test _read_png_size(parts[1].content.filename) == (width, height)
        # The tool of an agent takes the same pictures.
        register_picture_tools!(editor.tools)
        withenv("XDG_CACHE_HOME" => directory) do
            window = call_tool(editor.tools, "take_picture"; args = Dict{String,Any}(), target = editor)
            @test window isa LlmImage && window.media_type == "image/png"
            @test _read_png_size(IOBuffer(window.data)) == (1600, 1000)
            part = call_tool(editor.tools, "take_picture"; args = Dict{String,Any}("part" => "selection"),
                             target = editor)
            @test _read_png_size(IOBuffer(part.data)) == (width, height)
            @test occursin("not", call_tool(editor.tools, "take_picture";
                                            args = Dict{String,Any}("part" => "tab"), target = editor))
        end
    end
end

# The width and the height of a PNG file, from its header.
function _read_png_size(file)
    bytes = read(file, 24)
    (Int(ntoh(reinterpret(UInt32, bytes[17:20])[1])), Int(ntoh(reinterpret(UInt32, bytes[21:24])[1])))
end
