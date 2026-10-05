# The colour settings of the operating system in the SDL backend: the answers of
# `gsettings`, of the settings portal and of `defaults` become `SystemColors`, a
# command that does not end within its limit gives nothing, and a different answer
# waits as one `SystemColorsChange` for `take_from_devices!`.

const _SDL_MODULE = ProjecturedSDL.SdlModule

function test_sdl_system_colors()
@testset "the colour settings of the system" begin

    @testset "the answers of gsettings" begin
        @test _SDL_MODULE._convert_gsettings_answers("'prefer-dark'\n", "true\n", "'orange'\n") ==
              SystemColors(; mode = :dark, contrast = :high, accent = (0xf7, 0x6b, 0x15))
        @test _SDL_MODULE._convert_gsettings_answers("'default'\n", "false\n", nothing) == SystemColors()
        # Slate is a grey accent, which names no hue.
        @test _SDL_MODULE._convert_gsettings_answers("'prefer-light'\n", nothing, "'slate'\n") == SystemColors()
    end

    @testset "the answer of the settings portal" begin
        text = "({'org.freedesktop.appearance': {'color-scheme': <uint32 1>, " *
               "'accent-color': <(0.20784313725490197, 0.51764705882352946, 0.89411764705882357)>, " *
               "'contrast': <uint32 1>}},)\n"
        @test _SDL_MODULE._convert_portal_answer(text) ==
              SystemColors(; mode = :dark, contrast = :high, accent = (0x35, 0x84, 0xe4))
        # A number outside 0 to 1 means no accent, and an older portal has no contrast.
        text = "({'org.freedesktop.appearance': {'color-scheme': <uint32 0>, " *
               "'accent-color': <(-1.0, -1.0, -1.0)>}},)\n"
        @test _SDL_MODULE._convert_portal_answer(text) == SystemColors()
        @test _SDL_MODULE._convert_portal_answer("({},)\n") == SystemColors()
    end

    @testset "the answers of defaults on macOS" begin
        @test _SDL_MODULE._convert_macos_answers("Dark\n", "1\n", "5\n") ==
              SystemColors(; mode = :dark, contrast = :high, accent = (0x6e, 0x56, 0xcf))
        # No style is light, and no accent is the default blue.
        @test _SDL_MODULE._convert_macos_answers(nothing, nothing, nothing) ==
              SystemColors(; accent = (0x3e, 0x63, 0xdd))
        @test _SDL_MODULE._convert_macos_answers(nothing, nothing, "-1\n").accent === nothing
    end

    @testset "a command gives its output, and nothing when it fails or does not end in time" begin
        @test _SDL_MODULE._read_command_output(`echo prefer-dark`, 5.0) == "prefer-dark\n"
        @test _SDL_MODULE._read_command_output(`false`, 5.0) === nothing
        @test _SDL_MODULE._read_command_output(`no-such-command-of-projectured`, 5.0) === nothing
        elapsed = @elapsed (stopped = _SDL_MODULE._read_command_output(`sleep 10`, 0.2))
        @test stopped === nothing
        @test elapsed < 5.0
    end

    @testset "a different answer waits as one change for take_from_devices!" begin
        backend = SdlBackend()
        dark = SystemColors(; mode = :dark)
        _SDL_MODULE._report_system_colors!(backend, dark)
        change = take_from_devices!(backend, Device[])
        @test change isa WindowInput && change.window_id === :none
        @test change.event isa SystemColorsChange && change.event.colors == dark
        # The same answer again, and no answer, report nothing.
        _SDL_MODULE._report_system_colors!(backend, dark)
        _SDL_MODULE._report_system_colors!(backend, nothing)
        @test backend.system_colors_change === nothing
        @test backend.system_colors == dark
    end

end
end
