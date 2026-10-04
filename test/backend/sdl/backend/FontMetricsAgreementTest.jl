# The layout reads the metrics of a font from its tables, and SDL draws with
# FreeType. The two must read the same numbers, or a baseline the layout puts at
# one row is drawn at another, and a kerned pair moves away from its caret. At a
# size of one pixel per font unit, FreeType's metrics are the table values with
# no rounding, so the comparison is exact.
# SDL_ttf's kerning of two characters, in pixels at the size the font was
# opened at. The generated binding has only the 16-bit form of this call.
const _SDL_TTF_LIBRARY = ProjecturedSDL.SdlModule.SimpleDirectMediaLayer.LibSDL2.libsdl2_ttf
_get_sdl_kerning(handle, left, right) =
    ccall((:TTF_GetFontKerningSizeGlyphs32, _SDL_TTF_LIBRARY), Cint,
          (Ptr{ProjecturedSDL.SdlModule.TTF_Font}, UInt32, UInt32), handle, UInt32(left), UInt32(right))

function test_sdl_font_metrics_agree()
@testset "the font tables and FreeType agree" begin

    ProjecturedSDL.SdlModule.TTF_Init()
    directory = dirname(compute_font_path(StyleFont("Ubuntu", 20)))
    files = sort(filter(name -> endswith(name, ".ttf"), readdir(directory)))
    @test length(files) > 30

    for name in files
        path = joinpath(directory, name)
        font = load_truetype_font(path)
        handle = ProjecturedSDL.SdlModule.TTF_OpenFont(path, font.units_per_em)
        @testset "$name" begin
            @test handle != C_NULL
            handle == C_NULL && continue
            ascender, descender, line_gap = get_vertical_metrics(font)
            @test ProjecturedSDL.SdlModule.TTF_FontAscent(handle) == ascender
            @test ProjecturedSDL.SdlModule.TTF_FontDescent(handle) == descender
            @test ProjecturedSDL.SdlModule.TTF_FontLineSkip(handle) == ascender - descender + line_gap
            for (left, right) in (('A', 'V'), ('T', 'o'), ('T', 'y'), ('A', 'W'), ('W', 'A'),
                                  ('L', 'T'), ('W', 'W'), ('f', 'i'), ('r', ','), ('P', '.'))
                expected = get_kerning(font, get_glyph_id(font, left), get_glyph_id(font, right))
                @test _get_sdl_kerning(handle, left, right) == expected
            end
            ProjecturedSDL.SdlModule.TTF_CloseFont(handle)
        end
    end

end
end
