const _ALL_KEY_SYMBOLS = [
    :left, :right, :up, :down, :home, :end, :page_up, :page_down,
    :backspace, :delete, :return, :tab, :insert,
    :f1, :f2, :f3, :f4, :f5, :f6, :f7, :f8, :f9, :f10, :f11, :f12,
    :escape, :space, :caps_lock,
    :lctrl, :rctrl, :lshift, :rshift, :lalt, :ralt, :lmeta, :rmeta,
    :comma, :period, :char,
]

const _ALL_KEY_EVENTS = vcat(
    # KeyDown with each symbol, with and without ctrl
    [KeyDown(key, ModifierKeys(ctrl=ctrl); time = 0.0) for key in _ALL_KEY_SYMBOLS for ctrl in (false, true)],
    # KeyDown with repeat flag
    [KeyDown(key, ModifierKeys(); repeat = true, time = 0.0)    for key in (:left, :right, :backspace, :delete)],
    # KeyUp
    [KeyUp(key, ModifierKeys(); time = 0.0)            for key in _ALL_KEY_SYMBOLS],
    # KeyPress — printable characters
    [KeyPress(ch; time = 0.0) for ch in ('a', 'Z', '0', ' ', ',', '.', '\n', 'é', '€')],
)

const _MOUSE_SAMPLE_XY = [(0, 0), (1, 1), (100, 100), (400, 300), (800, 600)]

const _ALL_MOUSE_EVENTS = vcat(
    [MouseDown(btn, x, y; time = 0.0)
     for btn   in (:left, :middle, :right)
     for (x,y) in _MOUSE_SAMPLE_XY],
    [MouseUp(btn, x, y; time = 0.0)
     for btn   in (:left, :middle, :right)
     for (x,y) in _MOUSE_SAMPLE_XY],
    [MouseClick(btn, x, y; time = 0.0)
     for btn   in (:left, :middle, :right)
     for (x,y) in _MOUSE_SAMPLE_XY],
    [MouseMove(x, y; time = 0.0)   for (x,y) in _MOUSE_SAMPLE_XY],
    [MouseScroll(dx, dy, x, y; time = 0.0)
     for dx    in (-1, 0, 1)
     for dy    in (-1, 0, 1)
     for (x,y) in _MOUSE_SAMPLE_XY],
)

const _ALL_READER_EVENTS = vcat(_ALL_KEY_EVENTS, _ALL_MOUSE_EVENTS)

"""
    walk_reader_events(document, projection; onevent=nothing) -> Vector{String}

Print `document` with `projection`, then call `read_intent` for every
event in `_ALL_READER_EVENTS`.  Collects and returns error strings for any
call that throws; a clean run returns an empty vector.  If `onevent` is
supplied it is called once per event with `(event, ok::Bool, message::String)`,
letting a caller emit one assertion per event.
"""
function walk_reader_events(document, projection; onevent=nothing)
    errors = String[]
    clear_selection!(document)
    iomap = try
        print_document(projection, document)
    catch e
        msg = "print_document threw: $e"
        push!(errors, msg)
        onevent === nothing || onevent(nothing, false, msg)
        return errors
    end
    for event in _ALL_READER_EVENTS
        try
            read_intent(projection, iomap, event)
            onevent === nothing || onevent(event, true, "")
        catch e
            msg = "read_intent threw for $event: $e"
            push!(errors, msg)
            onevent === nothing || onevent(event, false, msg)
        end
    end
    errors
end

# One @test per reader event. `broken` is an optional `(event, message) -> Bool`
# predicate; when an event fails and `broken` recognises its error signature, it
# is recorded `@test_broken` instead of `@test`, so a *different* failure on the
# same example still surfaces as an unmarked `Fail` (a regression). The umbrella
# supplies the per-example registry (`reader_broken`); a bare call marks nothing.
function test_reader(label, document, projection; broken=nothing)
    @testset "$label" begin
        walk_reader_events(document, projection;
            onevent = (ev, ok, msg) -> begin
                if !ok && broken !== nothing && broken(ev, msg)
                    @test_broken ok
                else
                    ok || @warn "[$label] $msg"
                    @test ok
                end
            end)
    end
end


# The `Example`-typed overload; the all-examples sweep stays in the umbrella.
function test_reader(example::Example)
    test_reader(example.name, example.document, example.projection)
end
