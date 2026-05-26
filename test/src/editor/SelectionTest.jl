# ═══════════════════════════════════════════════════════════════════════════
# test/src/editor/SelectionTest.jl
#
# Exhaustive selection-state exploration via BFS.
#
# explore_selections(document, projection[, initial_selection])
#   Performs a BFS over all selection states reachable from initial_selection
#   using navigation key presses.  At each state every nav key is tried via
#   projection_read; any thrown exception is collected as an error.  A new
#   state is only enqueued when its path string has not been seen before,
#   ensuring each distinct selection is visited exactly once.
#   If initial_selection is omitted, Ctrl+Home is used to find the first state.
#   Returns (state_count, errors).
#
# test_selection(label, document, projection[, initial_selection])
#   Wraps explore_selections in a @testset and asserts no errors occurred.
# ═══════════════════════════════════════════════════════════════════════════

function explore_selections(document, projection, initial_selection=nothing)
    nav_keys = [
        KeyPress(:left,  false),
        KeyPress(:right, false),
        KeyPress(:up,    false),
        KeyPress(:down,  false),
        KeyPress(:home,  false),
        KeyPress(:end,   false),
        KeyPress(:home,  true),
        KeyPress(:end,   true),
    ]

    visited = Set{String}()
    errors  = String[]

    clear_selection!(document)
    iomap = try
        projection_print(projection, document)
    catch e
        return (state_count=0, errors=["projection_print failed: $e"])
    end

    if initial_selection === nothing
        op = try
            projection_read(projection, iomap, KeyPress(:home, true))
        catch e
            return (state_count=0, errors=["Ctrl+Home failed: $e"])
        end
        op isa ReplaceSelectionOperation || return (state_count=0, errors=["Ctrl+Home returned no selection"])
        initial_selection = op.path
    end

    queue = Any[initial_selection]

    while !isempty(queue)
        path = popfirst!(queue)
        path_str = string(path)
        path_str in visited && continue
        push!(visited, path_str)

        clear_selection!(document)
        set_selection!(document, path)

        iomap = try
            projection_print(projection, document)
        catch e
            push!(errors, "reprint at [$path_str] failed: $e")
            continue
        end
        _walk!(iomap, Set{UInt64}(), errors)

        for key in nav_keys
            op = try
                projection_read(projection, iomap, key)
            catch e
                push!(errors, "reader error at [$path_str] with $key: $e")
                nothing
            end
            op isa ReplaceSelectionOperation || continue
            new_str = string(op.path)
            new_str in visited && continue
            push!(queue, op.path)
        end
    end

    (state_count=length(visited), errors=errors)
end

function test_selection(label, document, projection, initial_selection=nothing)
    @testset "$label" begin
        result = explore_selections(document, projection, initial_selection)
        for e in result.errors
            @warn "[$label] $e"
        end
        @test isempty(result.errors)
        @test result.state_count > 0
    end
end

function test_selection(example::Example)
    test_selection(example.name, example.document, example.projection)
end

function test_selections()
    @testset "Selections" begin
        for example in examples
            # Skip widget and workbench as they don't support selection navigation
            example.name in ("widget", "workbench") && continue
            @testset "$(example.name)" begin
                test_selection(example)
            end
        end
    end
end
