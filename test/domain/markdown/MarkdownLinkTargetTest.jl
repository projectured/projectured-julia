# What the target of a markdown link names, for a navigator: a heading by its
# slug, a file beside the file of the page, and nothing for a URL.

function test_markdown_link_target()
@testset "markdown link targets" begin
    source = "# Projectured\n\nIntro.\n\n## Install the editor\n\nSteps.\n\n## Use it_now!\n"
    root = parse_markdown(source)
    headings = [element for element in root.elements if element isa MarkdownHeading]
    @test compute_markdown_heading_slug(headings[2]) == "install-the-editor"
    @test compute_markdown_heading_slug(headings[3]) == "use-it_now"
    found = find_navigator_target(root, "#install-the-editor")
    @test evaluate_reference(root, found) === headings[2]
    @test find_navigator_target(root, "#nothing-here") === nothing
    @test find_navigator_target(root, "guide.md") === nothing
    # A file names its headings, and a file beside it that exists.
    folder = mktempdir()
    write(joinpath(folder, "guide.md"), "# Guide\n")
    file = MarkdownFile(joinpath(folder, "readme.md"), root)
    @test evaluate_reference(file, find_navigator_target(file, "#use-it_now")) === headings[3]
    @test find_navigator_target(file, "guide.md") == joinpath(folder, "guide.md")
    @test find_navigator_target(file, "guide.md#guide") == joinpath(folder, "guide.md")
    @test find_navigator_target(file, "missing.md") === nothing
    @test find_navigator_target(file, "https://example.org/guide.md") === nothing
    @test find_navigator_target(file, "mailto:someone@example.org") === nothing
end
end
