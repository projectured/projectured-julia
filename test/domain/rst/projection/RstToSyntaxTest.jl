# The rendered form of an RST image draws the file that the path names as an
# inline picture, sized from the head of the file.

"""
    test_rst_to_syntax()

The image span of the rendered RST form asks for the size of its file.
"""
function test_rst_to_syntax()
@testset "RstToSyntax" begin
    @testset "the image span asks for the size of its file" begin
        file = normpath(joinpath(@__DIR__, "..", "..", "..", "..", "asset", "image", "file.png"))
        projection = RecursiveProjection(RstToSyntax(; style = :rendered))
        ProjecturedPlatformTest.test_image_span_size_work(file) do
            print_document(projection, RstImage(file)).output.value
        end
    end
end
end # test_rst_to_syntax
