# The page about the program: what it draws, and what a host gives it.

# What a printer draws, as text.
function _draw_help_text(projection, document)
    text = ChainingProjection(projection,
                              RecursiveProjection(SyntaxToText()),
                              RecursiveProjection(TextToString()))
    output = print_document(text, document).output
    output isa Cell ? output[] : output
end

function test_about_page_to_syntax()
@testset "the page about the program" begin
    lines = split(_draw_help_text(AboutPageToSyntax(), AboutPage()), "\n")
    @test lines[1] == "ProjecturEd"
    @test startswith(lines[2], "A generic-purpose projectional editor")
    @test lines[3] == ""
    @test lines[4] == "Version " * string(pkgversion(ProjecturedPlatform))
    @test lines[5] == "Julia " * string(VERSION)
    @test lines[6] == "https://projectured.org"
    # A host gives its own page, and a field it leaves empty has no line.
    lines = split(_draw_help_text(AboutPageToSyntax(),
                                  AboutPage(; name = "Other", summary = "", version = "2.0",
                                              homepage = "")), "\n")
    @test lines == ["Other", "", "Version 2.0", "Julia " * string(VERSION)]
    @test get_document_title(AboutPage()) == "About"
end
end
