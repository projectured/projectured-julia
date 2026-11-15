# A Markdown page holds the picture of each image: the open and each load of the page
# give the image the editor's one file document of the picture that its url names,
# against the folder of the page, and the picture is held while a tab or a card holds
# the page. So the editor watches each picture once, and the page draws each rewrite
# of it.

# The image of the paragraph `k` of the page of `file`.
_get_page_image(file, k) = get_edited_document(file).elements[k].content[1]

# The span that the rendered view draws for `image`.
_print_page_image_span(image) =
    print_document(MarkdownImageToStyledNode(), nothing, image, PrinterContext()).output.children[2].value

"""
    test_markdown_image_picture()

An image of a Markdown page in a tab and in a card holds the editor's one picture file
of its url, which is watched once; a web url and the path of a page name no picture;
a rewrite of the picture gives the span its new size; a rewrite of the page that names
a new picture holds it; and the close of the last holder stops each watch.
"""
function test_markdown_image_picture()
@testset "a markdown image holds the picture that it names" begin
    asset = joinpath(@__DIR__, "..", "..", "..", "asset", "image")
    folder = mktempdir()
    chart = joinpath(folder, "chart.png")
    cp(joinpath(asset, "file.png"), chart)
    write(joinpath(folder, "other.md"), "# Other\n")
    source = "![chart](chart.png)\n\n![web](https://example.org/a.png)\n\n![page](other.md)\n"
    tab_path = joinpath(folder, "tab.md")
    card_path = joinpath(folder, "card.md")
    write(tab_path, source)
    write(card_path, source)
    editor = build_editor(PrimitiveString("x"), NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0));
                          backend = HeadlessBackend(), devices = Device[], window = false, tabs = true,
                          appearance = false, settings = false, file_change = true)
    step!() = (drain_operations!(editor); run_frame!(editor); sleep(0.02))
    function wait_until(done; seconds = 30)
        deadline = time() + seconds
        while time() < deadline && !done()
            step!()
        end
        done()
    end
    span_size(span) = run_with_evaluation_editor(() -> (Int(span.width), Int(span.height)), editor)
    try
        step!()
        store = get_session_file_change_store(; editor)
        watches(file) = count(watch -> watch.receiver === file, store.files)

        tab = open_file!(tab_path; editor)
        step!()
        page = find_open_file_document(tab_path; editor)
        picture = find_open_file_document(chart; editor)
        @testset "the image of a page in a tab holds the picture of its url" begin
            @test picture isa ImageFile
            @test _get_page_image(page, 1).picture == ("chart.png" => picture)
            @test is_document_held(editor, picture) && watches(picture) == 1
            span = _print_page_image_span(_get_page_image(page, 1))
            @test span isa TextGraphics && span.content === picture
        end

        @testset "a web url and the path of a page name no picture" begin
            @test _get_page_image(page, 2).picture === nothing
            @test _get_page_image(page, 3).picture === nothing
            @test find_open_file_document(joinpath(folder, "other.md"); editor) === nothing
            @test _print_page_image_span(_get_page_image(page, 2)) isa TextString
        end

        card = open_file_document!(card_path; editor)
        card_view = make_file_view(card)
        evaluate_operation(editor, AcquireDocumentOperation(card_view))
        @testset "the image of a page in a card holds the same picture, watched once" begin
            run_with_evaluation_editor(() -> demand_file_text(card), editor)
            @test wait_until(() -> get_file_disk_state(card).loaded_count >= 0)
            @test _get_page_image(card, 1).picture == ("chart.png" => picture)
            @test watches(picture) == 1
        end

        @testset "a rewrite of the picture gives the span its new size" begin
            span = _print_page_image_span(_get_page_image(page, 1))
            @test wait_until(() -> span_size(span) == (16, 16))
            cp(joinpath(asset, "projectured.png"), chart; force = true)
            @test wait_until(() -> (drain_file_changes!(; store); span_size(span) == (640, 167)))
        end

        @testset "a rewrite of the page that names a new picture holds it" begin
            second = joinpath(folder, "second.png")
            cp(joinpath(asset, "directory.png"), second)
            write(tab_path, "![second](second.png)\n")
            # The view of the page asks for its read when it draws, as here.
            read_page() = (drain_file_changes!(; store); run_with_evaluation_editor(() -> demand_file_text(page), editor))
            @test wait_until(() -> (read_page(); _get_page_image(page, 1).url == "second.png"))
            held = find_open_file_document(second; editor)
            @test held isa ImageFile && _get_page_image(page, 1).picture == ("second.png" => held)
            @test is_document_held(editor, held) && watches(held) == 1
        end

        @testset "the close of the last holder stops each watch" begin
            close_pane!(tab; editor)
            evaluate_operation(editor, ReleaseDocumentOperation(card_view))
            step!()
            @test watches(picture) == 0
            @test find_open_file_document(chart; editor) === nothing
            @test find_open_file_document(joinpath(folder, "second.png"); editor) === nothing
        end
    finally
        foreach(step -> step(editor), editor.stop_steps)
    end
end
end # test_markdown_image_picture
