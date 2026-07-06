# ═══════════════════════════════════════════════════════════════════════════
# test/src/editor/TextNavigationTest.jl
#
# Exhaustive text-caret selection-state exploration via BFS, plus a coverage
# check against the ground-truth set of caret selections enumerated directly
# from the document (collect_text_selections).
#
# explore_text_selections(document, projection[, initial_selection])
#   Performs a BFS over all selection states reachable from initial_selection
#   using navigation key presses.  At each state every nav key is tried via
#   read_intent; any thrown exception is collected as an error.  A new
#   state is only enqueued when its path string has not been seen before,
#   ensuring each distinct selection is visited exactly once.
#   If initial_selection is omitted, Ctrl+Home is used to find the first state.
#   Returns (state_count, errors, visited) — visited is the Set of path strings.
#
# test_text_navigation(label, document, projection[, initial_selection]; check_reaches_all=false)
#   Wraps explore_text_selections in a @testset and asserts no errors occurred.
#   With check_reaches_all=true it additionally asserts navigation reaches every
#   caret in collect_text_selections(document) (subset: enumerated ⊆ reachable) —
#   the coverage feature. test_text_navigations_complete() runs it over a curated
#   subset of examples.
# ═══════════════════════════════════════════════════════════════════════════

function explore_text_selections(document, projection, initial_selection=nothing; onstate=nothing)
    nav_keys = [
        KeyDown(:left,  Modifiers()),
        KeyDown(:right, Modifiers()),
        KeyDown(:up,    Modifiers()),
        KeyDown(:down,  Modifiers()),
        KeyDown(:home,  Modifiers()),
        KeyDown(:end,   Modifiers()),
        KeyDown(:home,  Modifiers(ctrl=true)),
        KeyDown(:end,   Modifiers(ctrl=true)),
        KeyDown(:left,  Modifiers(ctrl=true)),
        KeyDown(:right, Modifiers(ctrl=true)),
    ]

    visited = Set{String}()
    errors  = String[]

    clear_selection!(document)
    iomap = try
        print_document(projection, document)
    catch e
        return (state_count=0, errors=["print_document failed: $e"], visited=visited)
    end

    if initial_selection === nothing
        op = try
            read_intent(projection, iomap, KeyDown(:home, Modifiers(ctrl=true)))
        catch e
            return (state_count=0, errors=["Ctrl+Home failed: $e"], visited=visited)
        end
        op isa ReplaceSelectionOperation || return (state_count=0, errors=["Ctrl+Home returned no selection"], visited=visited)
        initial_selection = op.path
    end

    queue = Any[initial_selection]

    while !isempty(queue)
        path = popfirst!(queue)
        # Navigation selections are canonical (carry TypeReference checkpoints);
        # dedup and the completeness comparison are modulo checkpoints, so record
        # the stripped navigation skeleton (matching collect_text_selections).
        path_str = string(strip_reference_types(path))
        path_str in visited && continue
        push!(visited, path_str)
        errs_before = length(errors)

        clear_selection!(document)
        set_selection!(document, path)

        iomap = try
            print_document(projection, document)
        catch e
            msg = "reprint at [$path_str] failed: $e"
            push!(errors, msg)
            onstate === nothing || onstate(path, false, msg)
            continue
        end
        _walk!(iomap, Set{UInt64}(), errors)

        for key in nav_keys
            op = try
                read_intent(projection, iomap, key)
            catch e
                push!(errors, "reader error at [$path_str] with $key: $e")
                nothing
            end
            op isa ReplaceSelectionOperation || continue
            new_str = string(strip_reference_types(op.path))
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

    (state_count=length(visited), errors=errors, visited=visited)
end

# Ground-truth caret enumeration — an open generic. The implementation needs
# document vocabulary above the kernel (CellVector containers, TextString
# leaves), so the base method lives in ProjecturedBaseTest and higher test
# packages extend it; only the generic function is declared here so the driver
# can call it when `check_reaches_all=true`.
function collect_text_selections end

# Subset assertion: every enumerated selection must be among the reachable ones.
# One `@test` per enumerated selection so a failure pinpoints exactly which
# selection navigation cannot reach (rather than a single bulk assertion).
function _assert_reaches_all(label, enumerated, visited::Set{String})
    for p in enumerated
        s = string(p)
        reached = s in visited
        reached || @warn "[$label] enumerated selection unreached by navigation: $s"
        @test reached
    end
end

# One @test per reachable selection state. When `check_reaches_all=true`,
# additionally assert navigation reaches every caret enumerated directly from the
# document (subset: collect_text_selections(document) ⊆ reachable) — the coverage
# feature.
function test_text_navigation(label, document, projection, initial_selection=nothing; check_reaches_all=false)
    @testset "$label" begin
        result = explore_text_selections(document, projection, initial_selection;
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
        if check_reaches_all
            enumerated = collect_text_selections(document)
            @test !isempty(enumerated)
            _assert_reaches_all(label, enumerated, result.visited)
        end
    end
end


# The `Example`-typed overload; the sweeps stay in the umbrella.
function test_text_navigation(example::Example; check_reaches_all=false)
    test_text_navigation(example.name, example.document, example.projection; check_reaches_all=check_reaches_all)
end
