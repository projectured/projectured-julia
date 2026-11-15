# The rendered form of an RST image draws the picture file that the image holds as an
# inline picture, sized from the head of the file, and the figures and the images of
# an RST file in a tab hold the editor's one picture file of their path.

"""
    test_rst_to_syntax()

The image span of the rendered RST form asks for the size of its file, and a figure
and an image of a file in a tab hold one picture file of their path, watched once.
"""
function test_rst_to_syntax()
@testset "RstToSyntax" begin
    asset = normpath(joinpath(@__DIR__, "..", "..", "..", "..", "asset", "image"))
    @testset "the image span asks for the size of its file" begin
        file = joinpath(asset, "file.png")
        held = ImageFile(file)
        projection = RecursiveProjection(RstToSyntax(; style = :rendered))
        ProjecturedPlatformTest.test_image_span_size_work(file) do
            image = RstImage(file)
            image.picture = file => held
            print_document(projection, image).output.value
        end
    end

    @testset "a figure and an image of a file in a tab hold one picture of their path" begin
        folder = mktempdir()
        chart = joinpath(folder, "chart.png")
        cp(joinpath(asset, "file.png"), chart)
        path = joinpath(folder, "guide.rst")
        write(path, ".. figure:: chart.png\n\n   The chart.\n\n.. image:: chart.png\n\n.. image:: https://example.org/a.png\n")
        editor = build_editor(PrimitiveString("x"), NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0));
                              backend = HeadlessBackend(), devices = Device[], window = false, tabs = true,
                              appearance = false, settings = false, file_change = true)
        try
            # The window holds its tabs before the file opens.
            drain_operations!(editor)
            run_frame!(editor)
            store = get_session_file_change_store(; editor)
            tab = open_file!(path; editor)
            drain_operations!(editor)
            run_frame!(editor)
            elements = get_edited_document(find_open_file_document(path; editor)).elements
            picture = find_open_file_document(chart; editor)
            @test picture isa ImageFile
            @test elements[1] isa RstFigure && elements[1].picture == ("chart.png" => picture)
            @test elements[2] isa RstImage && elements[2].picture == ("chart.png" => picture)
            @test elements[3].picture === nothing
            @test is_document_held(editor, picture) && count(watch -> watch.receiver === picture, store.files) == 1
            projection = RecursiveProjection(RstToSyntax(; style = :rendered))
            @test print_document(projection, elements[2]).output.value isa TextGraphics
            close_pane!(tab; editor)
            drain_operations!(editor)
            run_frame!(editor)
            @test find_open_file_document(chart; editor) === nothing
        finally
            foreach(step -> step(editor), editor.stop_steps)
        end
    end
end
end # test_rst_to_syntax
