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
#   projection_read; any thrown exception is collected as an error.  A new
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
        projection_print(projection, document)
    catch e
        return (state_count=0, errors=["projection_print failed: $e"], visited=visited)
    end

    if initial_selection === nothing
        op = try
            projection_read(projection, iomap, KeyDown(:home, Modifiers(ctrl=true)))
        catch e
            return (state_count=0, errors=["Ctrl+Home failed: $e"], visited=visited)
        end
        op isa ReplaceSelectionOperation || return (state_count=0, errors=["Ctrl+Home returned no selection"], visited=visited)
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

    (state_count=length(visited), errors=errors, visited=visited)
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

function test_text_navigation(example::Example; check_reaches_all=false)
    test_text_navigation(example.name, example.document, example.projection; check_reaches_all=check_reaches_all)
end

function test_text_navigations()
    @testset "TextNavigation" begin
        for example in examples
            # Skip widget / layout examples, workbench, and assistant — the
            # widget-to-graphics layer doesn't route keyboard events to its
            # children, so Ctrl+Home can't seed an initial selection.
            #
            # Skip the database-backed catalog / SQL examples too: their
            # projections are read-only (v1), so they map no references back and
            # Ctrl+Home can't seed a selection.
            # Skip every widget example except the editable widget_text, whose
            # content recurses through TextToGraphics and so seeds a selection.
            (startswith(example.name, "widget") && example.name != "widget_text") && continue
            # Widget-presentation pipelines (…ToWidget → Graphics), e.g.
            # `json_widget`, `xml_widget`, the `*_catalog_widget`s, and
            # `conversation_widget`: the widget/graphics layer doesn't route
            # keyboard events to its children, so Ctrl+Home can't seed an initial
            # selection (same reason the bare widget examples above are skipped).
            endswith(example.name, "_widget") && continue
            example.name in ("layout", "workbench", "assistant",
                             "dbcatalog", "sql_syntax", "sql_table") && continue
            @testset "$(example.name)" begin
                test_text_navigation(example)
            end
        end
    end
end

# ── Completeness: navigation reaches every enumerated caret ───────────────────

# Curated examples whose every input-domain text leaf is navigable content, so
# the subset assertion (enumerated ⊆ reachable) is meaningful.
#
# Excluded on purpose:
#   * projections that hide / reorder / wrap content (filtering, sorting,
#     word-wrapping, …);
#   * `syntax` — its *input domain* is a syntax tree carrying explicit delimiter
#     TextStrings (`.open` / `.close` / `.sep`). Plain text navigation only enters
#     `.value` content, not those decorative delimiters, so enumerating every
#     TextString over-reaches. (`json` / `text` don't hit this: their delimiters,
#     e.g. JSON quotes, are projection-added and absent from the input document.)
#     `syntax` is covered structurally by the tree-navigation completeness suite.
#   * `ned` — same rendered-vs-document divergence: NedToSyntax renders each leaf
#     entry as a single *computed* TextString (a param's `@unit`/value, a module's
#     heading) and most document string fields (`.filename`, `.version`, a module
#     `.name`, nested property keys/literals) never become an addressable text
#     leaf. Text navigation covers every visible character via flat
#     ProjectionReference offsets plus `.name`/`.import_spec` carets whose `{k}`
#     range spans the *rendered* string, so "every document-field caret reachable"
#     is the wrong invariant. The no-error sweep (`test_text_navigations()`)
#     covers NED; its whole-element selections are covered by the tree-navigation
#     completeness suite.
const _text_navigation_complete_examples = ["text", "json", "ini"]

function test_text_navigations_complete()
    @testset "TextNavigationComplete" begin
        for example in examples
            example.name in _text_navigation_complete_examples || continue
            test_text_navigation(example; check_reaches_all=true)
        end
    end
end
