# The file tree names a file's kind with an icon, and the kinds a study folder
# holds — a `.pred` document, a NED network, an INI configuration, a `.math`
# formula — each have their own, so a person reads the folder at a glance.
function test_filesystem_to_widget()
@testset "FileSystemToWidget glyphs" begin
    icon(name) = ProjecturedFileSystem.FileSystemModule._fs_icon(FileSystemFile("/study/" * name))
    glyphs = Dict(name => icon(name) for name in
                  ("study.pred", "MM1K.ned", "omnetpp.ini", "closed.math",
                   "script.jl", "study.md", "data.json", "result.sca"))
    # Four kinds of the study folder, each its own.
    @test glyphs["study.pred"] === :diamond
    @test glyphs["MM1K.ned"] === :hexagon
    @test glyphs["omnetpp.ini"] === :file_sliders
    @test glyphs["closed.math"] === :sigma
    # The kinds that had one keep it, and a kind nobody named is a plain file.
    @test glyphs["script.jl"] === :lambda
    @test glyphs["study.md"] === :pilcrow
    @test glyphs["result.sca"] === :file
    # No two named kinds share a glyph, or the glyph says nothing.
    named = [glyphs[n] for n in ("study.pred", "MM1K.ned", "omnetpp.ini", "closed.math",
                                 "script.jl", "study.md", "data.json")]
    @test allunique(named)
    # Every kind is an icon the widget layer draws.
    @test all(name -> ProjecturedFileSystem.WidgetModule.find_icon_character(name) !== nothing,
              values(glyphs))
    # The case of the extension does not matter.
    @test icon("NETWORK.NED") === :hexagon
end
end
