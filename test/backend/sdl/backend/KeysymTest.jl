# The SDL keysym → key symbol table. Each letter key has the name of its
# lower-case letter, `:a` to `:z`. Another printable key that the table does not
# name falls back to `:char`, because its character arrives separately as
# SDL_TEXTINPUT. That fallback is right for typing and wrong for a chord: a
# binding on `KeyDown(:p; ctrl, shift)` can never fire if SDL reports `:char`.
#
# This test is the guard: it fails when a binding names a key the backend cannot
# deliver. The mapping helpers are internal to the backend, so they are qualified.

function test_sdl_keysym()
@testset "SDL keysym mapping" begin

    # The keysym of a letter key is the code of its lower-case letter.
    @testset "every letter key has the name of its letter" begin
        for (keysym, letter) in zip(97:122, 'a':'z')
            @test ProjecturedSdl.sdl_keysym_to_symbol(Int32(keysym)) === Symbol(letter)
        end
    end

    # The same table through the constructor of the event that the poll calls.
    @testset "sdl_to_keydown names every letter key by its letter" begin
        for (keysym, letter) in zip(97:122, 'a':'z')
            event = ProjecturedSdl.sdl_to_keydown(Int32(keysym), UInt16(0), false;
                                                  time = 0.0)
            @test event == KeyDown(Symbol(letter), ModifierKeys(); time = 0.0)
        end
    end

    # The precompile recording presses keys by name. A name that no backend reports
    # matches no binding, so the code behind that key is not in the recording.
    @testset "every key the precompile recording presses is one SDL reports" begin
        reported = Set(ProjecturedSdl.sdl_keysym_to_symbol(Int32(keysym))
                       for keysym in Iterators.flatten((0:255, 1073741824:1073742106)))
        driver = joinpath(@__DIR__, "..", "..", "..", "..", "source", "tool", "repl", "record",
                          "driver.jl")
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

    @testset "the undo pattern matches the event SDL builds for Ctrl+Z" begin
        # SDL modifier bit: KMOD_LCTRL = 0x0040.
        event = ProjecturedSdl.sdl_to_keydown(Int32(122), UInt16(0x0040), false;
                                              time = 0.0)
        @test event.key === :z
        projection = UndoBufferToAnyProjection()
        iomap = print_document(projection, IdentityProjection(),
                               UndoBuffer(make_json_document_example()), PrinterContext())
        bindings = get_projection_gesture_bindings(projection, iomap)
        undo = only(binding for binding in bindings if binding.name == "Undo")
        @test matches_gesture_pattern(undo.pattern, event)
    end

end
end

export test_sdl_keysym
