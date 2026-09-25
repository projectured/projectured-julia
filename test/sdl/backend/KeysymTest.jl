# The SDL keysym → key symbol table. A printable key that the table does not name
# falls back to `:char`, because its character arrives separately as
# SDL_TEXTINPUT. That fallback is right for typing and wrong for a chord: a
# binding on `KeyDown(:p; ctrl, shift)` can never fire if SDL reports `:char`.
#
# So every letter a projection binds under a modifier must be named here. This
# test is the guard: it fails when a binding names a key the backend cannot
# deliver. The mapping helpers are internal to the backend, so they are qualified.

function test_sdl_keysym()
@testset "SDL keysym mapping" begin

    # The letters bound under a modifier, with their ASCII keysyms.
    @testset "every letter a chord binds has its own symbol" begin
        @test ProjecturedSdl.sdl_keysym_to_symbol(Int32(99))  === :c   # Ctrl+C — copy
        @test ProjecturedSdl.sdl_keysym_to_symbol(Int32(110)) === :n   # Ctrl+N — note
        @test ProjecturedSdl.sdl_keysym_to_symbol(Int32(111)) === :o   # Ctrl+O — reload from disk
        @test ProjecturedSdl.sdl_keysym_to_symbol(Int32(112)) === :p   # Ctrl+Shift+P — command palette
        @test ProjecturedSdl.sdl_keysym_to_symbol(Int32(115)) === :s   # Ctrl+S — save
        @test ProjecturedSdl.sdl_keysym_to_symbol(Int32(116)) === :t   # Ctrl+T — open a pane tab
        @test ProjecturedSdl.sdl_keysym_to_symbol(Int32(118)) === :v   # Ctrl+V — paste
        @test ProjecturedSdl.sdl_keysym_to_symbol(Int32(119)) === :w   # Ctrl+W — close a pane tab
        @test ProjecturedSdl.sdl_keysym_to_symbol(Int32(120)) === :x   # Ctrl+X — cut
    end

    @testset "a letter no chord binds stays a character" begin
        @test ProjecturedSdl.sdl_keysym_to_symbol(Int32(113)) === :char   # 'q'
        @test ProjecturedSdl.sdl_keysym_to_symbol(Int32(122)) === :char   # 'z'
    end

    # The precompile recording presses keys by name. A name that no backend reports
    # matches no binding, so the code behind that key is not in the recording.
    @testset "every key the precompile recording presses is one SDL reports" begin
        reported = Set(ProjecturedSdl.sdl_keysym_to_symbol(Int32(keysym))
                       for keysym in Iterators.flatten((0:255, 1073741824:1073742106)))
        driver = joinpath(@__DIR__, "..", "..", "..", "source", "repl", "record", "driver.jl")
        pressed = [Symbol(m.captures[1])
                   for m in eachmatch(r"KeyDown\(:(\w+)", read(driver, String))]
        @test !isempty(pressed)
        for key in pressed
            @test key in reported
        end
    end

    # The whole point of naming a key: the reified pattern must match the event the
    # backend builds for that chord.
    @testset "the command palette pattern matches the event SDL builds" begin
        # SDL modifier bits: KMOD_LCTRL = 0x0040, KMOD_LSHIFT = 0x0001.
        event = ProjecturedSdl.sdl_to_keydown(Int32(112), UInt16(0x0040 | 0x0001), false;
                                                time = 0.0)
        @test event.key === :p
        @test is_command_palette_gesture(event)
    end

end
end

export test_sdl_keysym
