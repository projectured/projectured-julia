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

function explore_selections(document, projection, initial_selection=nothing; onstate=nothing)
    nav_keys = [
        KeyDown(:left,  Modifiers()),
        KeyDown(:right, Modifiers()),
        KeyDown(:up,    Modifiers()),
        KeyDown(:down,  Modifiers()),
        KeyDown(:home,  Modifiers()),
        KeyDown(:end,   Modifiers()),
        KeyDown(:home,  Modifiers(ctrl=true)),
        KeyDown(:end,   Modifiers(ctrl=true)),
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
            projection_read(projection, iomap, KeyDown(:home, Modifiers(ctrl=true)))
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
        errs_before = length(errors)

        clear_selection!(document)
        set_selection!(document, path)

        iomap = try
            projection_print(projection, document)
        catch e
            msg = "reprint at [$path_str] failed: $e"
            push!(errors, msg)
            onstate === nothing || onstate(path, false, msg)
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

        if onstate !== nothing
            if length(errors) > errs_before
                onstate(path, false, errors[errs_before + 1])
            else
                onstate(path, true, "")
            end
        end
    end

    (state_count=length(visited), errors=errors)
end

# One @test per reachable selection state.
function test_selection(label, document, projection, initial_selection=nothing)
    @testset "$label" begin
        result = explore_selections(document, projection, initial_selection;
            onstate = (p, ok, msg) -> begin
                ok || @warn "[$label] [$p] $msg"
                @test ok
            end)
        # Seed failures (Ctrl+Home / initial print) leave no states to assert;
        # surface their reasons and let the state-count check fail.
        if result.state_count == 0
            for e in result.errors
                @warn "[$label] $e"
            end
        end
        @test result.state_count > 0
    end
end

function test_selection(example::Example)
    test_selection(example.name, example.document, example.projection)
end

function test_selections()
    @testset "Selections" begin
        for example in examples
            # Skip widget / layout examples, workbench, and assistant — the
            # widget-to-graphics layer doesn't route keyboard events to its
            # children, so Ctrl+Home can't seed an initial selection.
            #
            # Skip the database-backed catalog / SQL examples too: their
            # projections are read-only (v1), so they map no references back and
            # Ctrl+Home can't seed a selection.
            example.name in ("widget", "widget_tabbed_pane", "layout", "workbench", "assistant",
                             "dbcatalog", "sql_syntax", "sql_table") && continue
            @testset "$(example.name)" begin
                test_selection(example)
            end
        end
    end
end
