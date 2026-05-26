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
    [KeyDown(key, Modifiers(ctrl=ctrl)) for key in _ALL_KEY_SYMBOLS for ctrl in (false, true)],
    # KeyDown with repeat flag
    [KeyDown(key, Modifiers(), true)    for key in (:left, :right, :backspace, :delete)],
    # KeyUp
    [KeyUp(key, Modifiers())            for key in _ALL_KEY_SYMBOLS],
    # KeyPress — printable characters
    [KeyPress(ch) for ch in ('a', 'Z', '0', ' ', ',', '.', '\n', 'é', '€')],
)

const _MOUSE_SAMPLE_XY = [(0, 0), (1, 1), (100, 100), (400, 300), (800, 600)]

const _ALL_MOUSE_EVENTS = vcat(
    [MouseDown(btn, x, y)
     for btn   in (:left, :middle, :right)
     for (x,y) in _MOUSE_SAMPLE_XY],
    [MouseUp(btn, x, y)
     for btn   in (:left, :middle, :right)
     for (x,y) in _MOUSE_SAMPLE_XY],
    [MousePress(btn, x, y)
     for btn   in (:left, :middle, :right)
     for (x,y) in _MOUSE_SAMPLE_XY],
    [MouseMove(x, y)   for (x,y) in _MOUSE_SAMPLE_XY],
    [MouseScroll(dx, dy, x, y)
     for dx    in (-1, 0, 1)
     for dy    in (-1, 0, 1)
     for (x,y) in _MOUSE_SAMPLE_XY],
)

const _ALL_READER_EVENTS = vcat(_ALL_KEY_EVENTS, _ALL_MOUSE_EVENTS)

"""
    walk_reader_events(document, projection) -> Vector{String}

Print `document` with `projection`, then call `projection_read` for every
event in `_ALL_READER_EVENTS`.  Collects and returns error strings for any
call that throws; a clean run returns an empty vector.
"""
function walk_reader_events(document, projection)
    errors = String[]
    clear_selection!(document)
    iomap = try
        projection_print(projection, document)
    catch e
        push!(errors, "projection_print threw: $e")
        return errors
    end
    for event in _ALL_READER_EVENTS
        try
            projection_read(projection, iomap, event)
        catch e
            push!(errors, "projection_read threw for $event: $e")
        end
    end
    errors
end

function test_reader(label, document, projection)
    @testset "$label" begin
        errors = walk_reader_events(document, projection)
        for e in errors
            @warn "[$label] $e"
        end
        @test isempty(errors)
    end
end

function test_reader(example::Example)
    test_reader(example.name, example.document, example.projection)
end

function test_readers()
    @testset "Readers" begin
        for example in examples
            @testset "$(example.name)" begin
                test_reader(example)
            end
        end
    end
end
