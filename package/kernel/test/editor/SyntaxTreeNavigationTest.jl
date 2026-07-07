# ═══════════════════════════════════════════════════════════════════════════
# test/editor/SyntaxTreeNavigationTest.jl
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
#     2. print_document re-renders (errors collected);
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
        print_document(projection, document)
    catch e
        return (state_count=0, errors=["print_document failed: $e"], visited=visited)
    end

    op = try
        read_intent(projection, iomap, KeyDown(:home, Modifiers(ctrl=true, alt=true)))
    catch e
        return (state_count=0, errors=["Ctrl+Alt+Home failed: $e"], visited=visited)
    end
    op isa ReplaceSelectionOperation || return (state_count=0, errors=["Ctrl+Alt+Home returned $(typeof(op)) instead of ReplaceSelectionOperation"], visited=visited)

    queue = Any[op.path]

    while !isempty(queue)
        path = popfirst!(queue)
        # Navigation selections are canonical (carry TypeReference checkpoints);
        # dedup and the completeness comparison are modulo checkpoints, so record
        # the stripped navigation skeleton (matching collect_tree_selections).
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

# Ground-truth whole-element enumeration — an open generic like
# `collect_text_selections`; the generic walk lives in ProjecturedBaseTest.
function collect_tree_selections end

# One @test per reachable whole-element state. When `check_reaches_all=true`,
# additionally assert navigation reaches every structural selection enumerated
# directly from the document (subset: collect_tree_selections(document; is_node) ⊆
# reachable).
# `collect` overrides how the ground-truth enumerated set is produced (default:
# `collect_tree_selections(document; is_node)`). Domains whose document is not a
# native syntax tree pass a domain enumerator instead (e.g. JSON passes
# `collect_json_tree_selections`, which mirrors JsonToSyntax's child decomposition).
function test_tree_navigation(label, document, projection; check_reaches_all=false, is_node=nothing, collect=nothing)
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
        if check_reaches_all
            enumerated = collect !== nothing ? collect(document) :
                is_node === nothing ? collect_tree_selections(document) :
                                      collect_tree_selections(document; is_node=is_node)
            @test !isempty(enumerated)
            _assert_reaches_all(label, enumerated, result.visited)
        end
    end
end

# The `Example`-typed overload (with its projection-aware default enumerator),
# the syntax-domain `_is_syntax_node` predicate, and the all-examples sweeps
# (`test_tree_navigations`, `test_tree_navigations_complete`) live in the
# `ProjecturedTest` umbrella, which owns the example registry.
