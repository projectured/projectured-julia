# The file tree names a file's kind with a glyph, and the kinds a study folder
# holds — a `.pred` document, a NED network, an INI configuration, a `.math`
# formula — each have their own, so a person reads the folder at a glance.
function test_filesystem_to_widget()
@testset "FileSystemToWidget glyphs" begin
    icon(name) = ProjecturedFileSystem.FileSystemModule._fs_icon(FileSystemFile("/study/" * name))
    glyphs = Dict(name => icon(name) for name in
                  ("study.pred", "MM1K.ned", "omnetpp.ini", "closed.math",
                   "script.jl", "study.md", "data.json", "result.sca"))
    # Four kinds of the study folder, each its own.
    @test glyphs["study.pred"] == "◆"
    @test glyphs["MM1K.ned"] == "⬡"
    @test glyphs["omnetpp.ini"] == "≡"
    @test glyphs["closed.math"] == "∑"
    # The kinds that had one keep it, and a kind nobody named is a dot.
    @test glyphs["script.jl"] == "λ"
    @test glyphs["study.md"] == "¶"
    @test glyphs["result.sca"] == "·"
    # No two named kinds share a glyph, or the glyph says nothing.
    named = [glyphs[n] for n in ("study.pred", "MM1K.ned", "omnetpp.ini", "closed.math",
                                 "script.jl", "study.md", "data.json")]
    @test allunique(named)
    # The case of the extension does not matter.
    @test icon("NETWORK.NED") == "⬡"
end
end
