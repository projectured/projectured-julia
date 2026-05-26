const _ALL_KEY_SYMBOLS = [
    :left, :right, :up, :down, :home, :end,
    :escape, :return, :char, :comma, :period,
]

const _ALL_KEY_EVENTS = [KeyPress(key, ctrl)
                         for key  in _ALL_KEY_SYMBOLS
                         for ctrl in (false, true)]

const _MOUSE_SAMPLE_XY = [(0, 0), (1, 1), (100, 100), (400, 300), (800, 600)]

const _ALL_MOUSE_EVENTS = vcat(
    [MouseClick(btn, x, y)
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
