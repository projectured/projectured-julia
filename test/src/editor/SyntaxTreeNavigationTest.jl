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
        return (state_count=0, errors=["projection_print failed: $e"], visited=visited)
    end

    op = try
        projection_read(projection, iomap, KeyDown(:home, Modifiers(ctrl=true, alt=true)))
    catch e
        return (state_count=0, errors=["Ctrl+Alt+Home failed: $e"], visited=visited)
    end
    op isa ReplaceSelectionOperation || return (state_count=0, errors=["Ctrl+Alt+Home returned $(typeof(op)) instead of ReplaceSelectionOperation"], visited=visited)

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

    (state_count=length(visited), errors=errors, visited=visited)
end

# One @test per reachable whole-element state. When `check_reaches_all=true`,
# additionally assert navigation reaches every structural selection enumerated
# directly from the document (subset: collect_tree_selections(document; is_node) ⊆
# reachable).
# `collect` overrides how the ground-truth enumerated set is produced (default:
# `collect_tree_selections(document; is_node)`). Domains whose document is not a
# native syntax tree pass a domain enumerator instead (e.g. NED passes
# `collect_ned_tree_selections`, which mirrors NedToSyntax's child decomposition).
function test_tree_navigation(label, document, projection; check_reaches_all=false, is_node=_is_syntax_node, collect=nothing)
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
            enumerated = collect === nothing ?
                collect_tree_selections(document; is_node=is_node) : collect(document)
            @test !isempty(enumerated)
            _assert_reaches_all(label, enumerated, result.visited)
        end
    end
end

# Pick the projection-aware enumerator for a document whose navigable tree is
# defined by its projection to syntax rather than by the raw input struct. Native
# syntax trees (and anything else) fall back to the `is_node` predicate by
# returning `nothing`. This lets `test_tree_navigation(json_example;
# check_reaches_all=true)` work without the caller naming the enumerator.
_default_tree_collector(::Any) = nothing
_default_tree_collector(::Projectured.JsonDocument) = collect_json_tree_selections
_default_tree_collector(::Projectured.NedFile) = collect_ned_tree_selections

function test_tree_navigation(example::Example; check_reaches_all=false, is_node=_is_syntax_node, collect=nothing)
    collect === nothing && (collect = _default_tree_collector(example.document))
    test_tree_navigation(example.name, example.document, example.projection; check_reaches_all=check_reaches_all, is_node=is_node, collect=collect)
end

function test_tree_navigations()
    # Only examples whose root projects to a SyntaxNode (not a lone leaf)
    # support tree navigation — Ctrl+Alt+Home must produce a result.
    @testset "TreeNavigation" begin
        for example in examples
            (startswith(example.name, "widget") && example.name != "widget_text") && continue
            example.name in ("layout",
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

# ── Completeness: navigation reaches every enumerated whole-element selection ──

# Examples whose every structural selection is enumerable as ground truth.
# `syntax` is a *native* SyntaxDocument tree, so the `is_node = SyntaxDocument`
# predicate reproduces the Alt+arrow-reachable set exactly. `json` and `ned` are
# projected *to* syntax, so they use a projection-aware enumerator instead
# (selected automatically by document type via `_default_tree_collector`).
# xml / math still expose no tree navigation in this harness (Ctrl+Alt+Home
# yields no selection).
const _tree_navigation_complete_examples = ["syntax", "json", "ned"]

# A structural tree node in the syntax domain is any SyntaxDocument — this
# excludes the CellVector child containers and the TextString delimiter / value
# holders, neither of which is an Alt+arrow tree-selection target.
_is_syntax_node(n) = n isa Projectured.SyntaxDocument

function test_tree_navigations_complete()
    @testset "TreeNavigationComplete" begin
        for example in examples
            example.name in _tree_navigation_complete_examples || continue
            # The enumerator is chosen by document type via _default_tree_collector
            # (native syntax → is_node predicate; json / ned → projection-aware).
            test_tree_navigation(example; check_reaches_all=true)
        end
    end
end
