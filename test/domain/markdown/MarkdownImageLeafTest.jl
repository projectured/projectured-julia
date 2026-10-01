# A Markdown image whose url names a file on disk renders an inline image in the
# rendered view: one position of the flat caret space of `SyntaxToText`. Every
# walk over it runs without an error, and an edit of the image through its syntax
# declines, so the image stays in the document.

"""
    test_markdown_image_leaf()

The walks over a Markdown image leaf with a real image file, in the plain and the
rendered view, and Backspace and Delete at each caret of the rendered view.
"""
function test_markdown_image_leaf()
@testset "a markdown image with a real image file" begin
    image = joinpath(@__DIR__, "..", "..", "..", "asset", "image", "file.png")
    make_document() = MarkdownRoot([MarkdownParagraph([MarkdownText("see "), MarkdownImage("logo", image),
                                                       MarkdownText(" the end.")])])
    measure = FixedMeasure(10, 12, 4, 0)
    projections = (plain = () -> make_markdown_projection_example(measure = measure),
                   rendered = () -> make_markdown_rendered_projection_example(measure = measure))
    for (name, make_projection) in pairs(projections)
        @testset "$name" begin
            @test isempty(walk_printer_output(make_document(), make_projection())[1])
            @test isempty(walk_repl_loop(make_document(), make_projection()))
            @test isempty(explore_position_selections(make_document(), make_projection())[2])
            test_text_navigation_invariants("markdown image $name", make_document(), make_projection())
        end
    end

    # The rendered view shows the image. At every caret of a walk to the right,
    # Backspace and Delete make no element write, and the image stays.
    @testset "an edit of the image declines" begin
        walk = ProjecturedPlatformTest._walk_cursor(make_document(), projections.rendered(),
                                                     ProjecturedPlatformTest.TEXT_WALK_RIGHT)
        @test walk.error === nothing
        for place in walk.paths, key in (:backspace, :delete)
            document = make_document()
            projection = projections.rendered()
            clear_selection!(document)
            set_selection!(document, place)
            op = read_intent(projection, print_document(projection, document),
                             KeyDown(key, ModifierKeys(); time = 0.0))
            @test !is_text_element_write(op)
            op isa ReplaceReferencedValueOperation && continue
            op === nothing || evaluate_operation(_MarkdownImageEditor(document), op)
            @test document.elements[1].content[2] isa MarkdownImage
        end
    end
end
end # test_markdown_image_leaf

# The editor an operation is applied against: the document, and no view.
mutable struct _MarkdownImageEditor
    document::Any
end
