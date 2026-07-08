# ═══════════════════════════════════════════════════════════════════════════
# test/editor/NavigationTest.jl
#
# Generic exhaustive navigation exploration: a BFS over every selection state
# reachable from a seed selection by firing a caller-supplied set of navigation
# gestures through `read_intent`. The driver is granularity- and
# domain-agnostic — the gesture set (`nav_keys`) and the seed (`seed_gesture`
# or an explicit `initial_selection`) parameterize it. The domain-flavored
# instantiations live in the tiers that own the gesture vocabularies
# (ProjecturedVisualTest: `test_position_navigation` over the character / word
# / line position gestures, `test_tree_navigation` over the Alt+arrow
# structural gestures); a later domain (e.g. vector collections) adds its own
# preset without touching this driver.
#
# explore_selections(document, projection; nav_keys, seed_gesture,
#                    initial_selection=nothing, onstate=nothing)
#   Performs a BFS over all selection states reachable from the seed using the
#   given navigation gestures. At each state every nav key is tried via
#   read_intent; any thrown exception is collected as an error. A new state is
#   only enqueued when its (checkpoint-stripped) path string has not been seen
#   before, ensuring each distinct selection is visited exactly once. If
#   initial_selection is omitted, seed_gesture is fired to find the first state.
#   Returns (state_count, errors, visited) — visited is the Set of path strings.
#
# test_navigation(label, document, projection; nav_keys, seed_gesture,
#                 initial_selection=nothing, check_reaches_all=false, collect=nothing)
#   Wraps explore_selections in a @testset and asserts no errors occurred.
#   With check_reaches_all=true it additionally asserts navigation reaches
#   every selection enumerated by `collect(document)` (subset: enumerated ⊆
#   reachable). The ground-truth enumerator is caller-supplied: enumerating
#   selections needs document vocabulary above the kernel (the generic walk
#   lives in ProjecturedBaseTest, projection-aware enumerators higher still).
# ═══════════════════════════════════════════════════════════════════════════

function explore_selections(document, projection;
                            nav_keys, seed_gesture=nothing,
                            initial_selection=nothing, onstate=nothing)
    visited = Set{String}()
    errors  = String[]

    clear_selection!(document)
    iomap = try
        print_document(projection, document)
    catch e
        return (state_count=0, errors=["print_document failed: $e"], visited=visited)
    end

    if initial_selection === nothing
        seed_gesture === nothing &&
            throw(ArgumentError("explore_selections needs a seed_gesture or an initial_selection"))
        op = try
            read_intent(projection, iomap, seed_gesture)
        catch e
            return (state_count=0, errors=["seed gesture $seed_gesture failed: $e"], visited=visited)
        end
        op isa ReplaceSelectionOperation ||
            return (state_count=0, errors=["seed gesture $seed_gesture returned $(op === nothing ? nothing : typeof(op)) instead of ReplaceSelectionOperation"], visited=visited)
        initial_selection = op.path
    end

    queue = Any[initial_selection]

    while !isempty(queue)
        path = popfirst!(queue)
        # Navigation selections are canonical (carry TypeReference checkpoints);
        # dedup and the completeness comparison are modulo checkpoints, so record
        # the stripped navigation skeleton (matching the ground-truth enumerators).
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
# additionally assert navigation reaches every selection enumerated directly
# from the document by `collect` (subset: collect(document) ⊆ reachable) — the
# coverage feature.
function test_navigation(label, document, projection;
                         nav_keys, seed_gesture=nothing, initial_selection=nothing,
                         check_reaches_all=false, collect=nothing)
    @testset "$label" begin
        result = explore_selections(document, projection;
            nav_keys=nav_keys, seed_gesture=seed_gesture,
            initial_selection=initial_selection,
            onstate = (p, ok, msg) -> begin
                ok || @warn "[$label] [$p] $msg"
                @test ok
            end)
        # Seed failures (seed gesture / initial print) leave no states to assert;
        # surface their reasons and let the state-count check fail.
        if result.state_count == 0
            for e in result.errors
                @warn "[$label] $e"
            end
        end
        @test result.state_count > 0
        if check_reaches_all
            collect === nothing &&
                throw(ArgumentError("check_reaches_all=true needs a `collect` ground-truth enumerator"))
            enumerated = collect(document)
            @test !isempty(enumerated)
            _assert_reaches_all(label, enumerated, result.visited)
        end
    end
end
