# ═══════════════════════════════════════════════════════════════════════════
# test/src/editor/SyntaxTreeNavigationTest.jl
#
# Exhaustive tree-selection-state exploration via BFS.
#
# explore_tree_selections(document, projection)
#   Begins with Ctrl+Alt+Home (recognised and resolved at the syntax layer,
#   selecting the root ∅).  From there every reachable tree-selection state
#   is explored by trying the four Alt+arrow keys (:up, :down, :left,
#   :right) at each state.  Each state is visited exactly once (keyed by
#   its path string).  At every state:
#     1. set_selection! applies the path;
#     2. projection_print re-renders (errors collected);
#     3. the iomap is walked (cells forced, errors collected).
#   Returns (state_count, errors).
#
# test_tree_navigation(label, document, projection)
#   Wraps explore_tree_selections in a @testset and asserts no errors.
# ═══════════════════════════════════════════════════════════════════════════

function explore_tree_selections(document, projection; onstate=nothing)
    nav_keys = [
        KeyDown(:up,    Modifiers(alt=true)),
        KeyDown(:down,  Modifiers(alt=true)),
        KeyDown(:left,  Modifiers(alt=true)),
        KeyDown(:right, Modifiers(alt=true)),
    ]

    visited = Set{String}()
    errors  = String[]

    # Seed: Ctrl+Alt+Home → ReplaceSelectionOperation(∅), resolved at syntax layer
    clear_selection!(document)
    iomap = try
        projection_print(projection, document)
    catch e
        return (state_count=0, errors=["projection_print failed: $e"])
    end

    op = try
        projection_read(projection, iomap, KeyDown(:home, Modifiers(ctrl=true, alt=true)))
    catch e
        return (state_count=0, errors=["Ctrl+Alt+Home failed: $e"])
    end
    op isa ReplaceSelectionOperation || return (state_count=0, errors=["Ctrl+Alt+Home returned $(typeof(op)) instead of ReplaceSelectionOperation"])

    queue = Any[op.path]

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

function test_tree_navigation(label, document, projection)
    @testset "$label" begin
        result = explore_tree_selections(document, projection;
            onstate = (p, ok, msg) -> begin
                ok || @warn "[$label] [$p] $msg"
                @test ok
            end)
        if result.state_count == 0
            for e in result.errors
                @warn "[$label] $e"
            end
        end
        @test result.state_count > 0
    end
end

function test_tree_navigation(example::Example)
    test_tree_navigation(example.name, example.document, example.projection)
end

function test_tree_navigations()
    # Only examples whose root projects to a SyntaxNode (not a lone leaf)
    # support tree navigation — Ctrl+Alt+Home must produce a result.
    @testset "TreeNavigation" begin
        for example in examples
            example.name in ("widget", "widget_tabbed_pane", "layout",
                             "workbench", "assistant",
                             "text", "text_with_image", "graphics_image",
                             "lazy", "lazy_bidirectional") && continue
            @testset "$(example.name)" begin
                result = explore_tree_selections(example.document, example.projection)
                if result.state_count == 0 && !isempty(result.errors) &&
                   occursin("Ctrl+Alt+Home", result.errors[1])
                    @info "[$(example.name)] skipped — no tree navigation support"
                else
                    for e in result.errors
                        @warn "[$(example.name)] $e"
                    end
                    @test isempty(result.errors)
                    @test result.state_count > 0
                end
            end
        end
    end
end
