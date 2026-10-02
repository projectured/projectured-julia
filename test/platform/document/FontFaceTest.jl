# The registry of the bundled font faces: each face is what its file declares,
# and the lookup follows the font matching of CSS.
function test_font_face()
@testset "FontFace" begin

    faces = StyleModule._FONT_FACES

    @testset "each face is what its file declares" begin
        for face in faces
            path = get_font_face_path(face)
            @test isfile(path)
            font = load_truetype_font(path)
            @test font.weight_class == face.weight
            @test font.is_italic == face.italic
        end
    end

    @testset "each font file has a face" begin
        files = [f for f in readdir(_FONT_DIR) if endswith(f, ".ttf") || endswith(f, ".otf")]
        @test sort(files) == sort([face.file for face in faces])
    end

    @testset "the face that a family, a weight and a slant name" begin
        @test find_font_face("Ubuntu", 400, false).file == "Ubuntu-R.ttf"
        @test find_font_face("Ubuntu", 700, true).file == "Ubuntu-BI.ttf"
        @test find_font_face("Ubuntu Mono", 700, false).file == "UbuntuMono-B.ttf"
        @test find_font_face("DejaVu Sans", 400, true).file == "DejaVuSans-Oblique.ttf"
    end

    @testset "the family matches with no regard to case" begin
        @test find_font_face("ubuntu mono", 400, false).file == "UbuntuMono-R.ttf"
        @test find_font_face("lucide", 400, false).file == "lucide.ttf"
        @test find_font_face("Ubuntu Monospace", 400, false) === nothing
        @test find_font_face("Helvetica", 400, false) === nothing
    end

    @testset "the slant wins over the weight" begin
        # DejaVu Sans has no bold italic face, so its italic face wins over its bold.
        @test find_font_face("DejaVu Sans", 700, true).file == "DejaVuSans-Oblique.ttf"
        # A family with no italic face draws italic text upright.
        @test find_font_face("Inconsolata", 400, true).file == "Inconsolata.otf"
        @test find_font_face("Ubuntu Condensed", 400, true).file == "Ubuntu-C.ttf"
    end

    @testset "the weight follows the rule of CSS" begin
        # From 400 to 500: the nearest heavier weight up to 500, then lighter.
        @test find_font_face("Inconsolata", 400, false).file == "Inconsolata.otf"
        @test find_font_face("Ubuntu", 450, false).file == "Ubuntu-M.ttf"
        @test find_font_face("DejaVu Sans", 450, false).file == "DejaVuSans.ttf"
        # Below 400: the nearest lighter weight, then the nearest heavier one.
        @test find_font_face("Ubuntu", 350, false).file == "Ubuntu-L.ttf"
        @test find_font_face("Ubuntu", 200, false).file == "Ubuntu-L.ttf"
        @test find_font_face("DejaVu Sans", 300, false).file == "DejaVuSans.ttf"
        # Above 500: the nearest heavier weight, then the nearest lighter one.
        @test find_font_face("Ubuntu", 600, false).file == "Ubuntu-B.ttf"
        @test find_font_face("Ubuntu", 900, false).file == "Ubuntu-B.ttf"
        @test find_font_face("DejaVu Sans", 600, false).file == "DejaVuSans-Bold.ttf"
        @test find_font_face("Ubuntu Condensed", 700, false).file == "Ubuntu-C.ttf"
    end

    @testset "a lookup that reads the file allocates nothing" begin
        # A caller that keeps the whole face boxes it, because the result can be
        # `nothing`; a caller that reads a field does not.
        read_face_file() = find_font_face("Ubuntu Mono", 700, true).file
        read_face_file()
        @test (@allocated read_face_file()) == 0
    end

end
end
