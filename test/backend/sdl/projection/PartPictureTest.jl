# A picture of a part, of the selection and of the window, as the editor draws
# them, written with the SDL backend and no window: the window of the application
# with an assistant, a part that an Alt+double click selects, a tab, the button
# that puts a picture into the draft, and the code of a model whose value is a
# picture, which the code tool answers as the picture.

function test_part_picture()
    @testset "a picture of a part, of the selection and of the window" begin
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
        window = write_window_picture(; editor, filename = joinpath(directory, "window.png"))
        @test window isa ImageFile
        @test _read_png_size(window.filename) == (1600, 1000)
        # A tab is a part with its reference: its picture is the canvas of its group.
        tab = find_pane("notes.txt"; editor)
        tab_picture = write_part_picture(tab; editor, filename = joinpath(directory, "tab.png"))
        @test tab_picture isa ImageFile
        tab_width, tab_height = _read_png_size(tab_picture.filename)
        @test 0 < tab_width <= 1600 && 0 < tab_height < 1000
        @test _read_png_size(write_part_picture(get_reference(tab); editor,
                                                filename = joinpath(directory, "tab-reference.png")).filename) ==
              (tab_width, tab_height)
        # An Alt+double click on the assistant selects a part of its conversation as a whole.
        press = MouseClick(:left, 1300, 300, 2, ModifierKeys(alt = true); time = 0.0)
        change = read_intent(composed, nothing, Intent(WindowInput(:ProjecturEd, press)), editor.iomap)
        evaluate_operation(editor, change.operation)
        drain_operations!(editor)
        selection = get_selection(editor.document)
        @test is_whole_selection(editor.document, selection)
        part = write_selection_picture(; editor, filename = joinpath(directory, "part.png"))
        @test part isa ImageFile
        width, height = _read_png_size(part.filename)
        @test 0 < width < 600 && 0 < height < 1000
        @test _read_png_size(write_part_picture(selection; editor,
                                                filename = joinpath(directory, "selected.png")).filename) ==
              (width, height)
        # The button puts the picture of that part into the draft, before the text.
        withenv("XDG_CACHE_HOME" => directory) do
            evaluate_operation(editor, AddDraftPictureOperation(assistant))
        end
        parts = collect(assistant.draft.parts)
        @test length(parts) == 2
        @test parts[1].content isa ImageFile && parts[2].content isa PrimitiveString
        @test startswith(parts[1].content.filename, joinpath(directory, "projectured", "pictures"))
        @test _read_png_size(parts[1].content.filename) == (width, height)
        # The code of a model whose value is a picture answers the picture, which
        # the model sees: the same pictures, in the folder of pictures.
        register_default_tools!(declare_api!(editor.tools, make_editor_api()))
        run_code = code -> call_tool(editor.tools, "execute_julia_code"; args = Dict{String,Any}("code" => code),
                                     target = editor)
        withenv("XDG_CACHE_HOME" => directory) do
            window = run_code("write_window_picture()")
            @test window isa LlmImage && window.media_type == "image/png"
            @test _read_png_size(IOBuffer(window.data)) == (1600, 1000)
            part = run_code("write_selection_picture()")
            @test part isa LlmImage && _read_png_size(IOBuffer(part.data)) == (width, height)
            tab_part = run_code("write_part_picture(find_pane(\"notes.txt\"))")
            @test tab_part isa LlmImage && _read_png_size(IOBuffer(tab_part.data)) == (tab_width, tab_height)
        end
        # The tool of a picture is gone: the code tool answers the pictures.
        @test find_tool(editor.tools, "take_picture") === nothing
    end
end

# The width and the height of a PNG file, from its header.
function _read_png_size(file)
    bytes = read(file, 24)
    (Int(ntoh(reinterpret(UInt32, bytes[17:20])[1])), Int(ntoh(reinterpret(UInt32, bytes[21:24])[1])))
end
