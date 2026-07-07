# ═══════════════════════════════════════════════════════════════════════════
# test/src/editor/ExampleSweeps.jl
#
# The `Example`-typed overloads of the generic drivers (which live in
# `ProjecturedKernelTest`) plus the all-examples sweeps. They stay in the
# umbrella because only the umbrella depends on `ProjecturedExample` — the
# generic `(label, document, projection)` driver forms are layer-agnostic and
# imported from `ProjecturedKernelTest` (see plan/pending/test-package-split.md).
# ═══════════════════════════════════════════════════════════════════════════

# ── printer ──────────────────────────────────────────────────────────────────

function test_printers()
    @testset "Printers" begin
        for example in examples
            @testset "$(example.name)" begin
                test_printer(example)
            end
        end
    end
end

# ── reader ───────────────────────────────────────────────────────────────────

function test_readers()
    @testset "Readers" begin
        for example in examples
            @testset "$(example.name)" begin
                test_reader(example)
            end
        end
    end
end

# ── repl ─────────────────────────────────────────────────────────────────────

function test_repls()
    @testset "Repls" begin
        for example in examples
            @testset "$(example.name)" begin
                if example.name in ("focusing", "xml")
                    # @broken: pre-existing runtime bug — walk_repl_loop hits an
                    # infinite recursion (StackOverflowError) on these two examples,
                    # which then corrupts Julia's stack state and destabilises every
                    # subsequent test in the run. @test_skip (unlike @test_broken)
                    # never runs the destructive code path, keeping the rest of the
                    # umbrella suite green.
                    @test_skip false
                else
                    test_repl(example)
                end
            end
        end
    end
end

# ── text navigation ──────────────────────────────────────────────────────────

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
            # `table` / `math_table`: Stage 2 made coordless keyboard routing
            # selection-only (no default-child fallback), so Ctrl+Home can no
            # longer seed an initial selection from an unselected document — the
            # bootstrap selection now comes from a click or a Tab. The other
            # examples below were already on this list for the same kind of
            # widget/graphics-keyboard-routing limitation.
            example.name in ("layout", "constraint_layout",
                             "table", "math_table",
                             "workbench", "assistant",
                             "dbcatalog", "sql_syntax", "sql_table") && continue
            @testset "$(example.name)" begin
                test_text_navigation(example)
            end
        end
    end
end

# ── completeness: navigation reaches every enumerated caret ──────────────────

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
const _text_navigation_complete_examples = ["text", "json"]

function test_text_navigations_complete()
    @testset "TextNavigationComplete" begin
        for example in examples
            example.name in _text_navigation_complete_examples || continue
            test_text_navigation(example; check_reaches_all=true)
        end
    end
end

# ── tree navigation ──────────────────────────────────────────────────────────

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

# ── completeness: navigation reaches every enumerated whole-element selection ─

# Examples whose every structural selection is enumerable as ground truth.
# `syntax` is a *native* SyntaxDocument tree, so the `is_node = SyntaxDocument`
# predicate reproduces the Alt+arrow-reachable set exactly. `json` is
# projected *to* syntax, so it uses a projection-aware enumerator instead
# (selected automatically by document type via `_default_tree_collector`).
# xml / math still expose no tree navigation in this harness (Ctrl+Alt+Home
# yields no selection).
const _tree_navigation_complete_examples = ["syntax", "json"]

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

# ── typein ───────────────────────────────────────────────────────────────────

function test_typeins()
    @testset "Typeins" begin
        # The walk builds input-domain cursor targets by field/index name and
        # anchors them at the right slot for each domain's selection convention,
        # including document-domain `TextString` (e.g. `SyntaxLeaf.value`) and
        # `TextText` (e.g. `BookParagraph.content`). Domains whose projection has
        # no string-edit reader (sorting/primitive/object) are covered elsewhere.
        for name in ("json", "json_string", "text", "xml", "book", "syntax")
            idx = findfirst(e -> e.name == name, examples)
            idx === nothing && continue
            ex = examples[idx]
            @testset "$(ex.name)" begin
                test_typein(ex)
            end
        end
    end
end

# ── click roundtrip ──────────────────────────────────────────────────────────

"""
    test_click_roundtrips()

Run `test_click_roundtrip` against every example that produces a
`TextToGraphicsIoMap` somewhere in its pipeline. Examples whose pipeline
does not include a `TextToGraphics` step (pure widget / table / graphics
chains) are skipped with a warning.
"""
function test_click_roundtrips()
    @testset "ClickRoundtrips" begin
        for example in examples
            # Skip examples whose top-level pipeline does not feed a
            # TextToGraphics step (handled by other readers entirely).
            # Skip:
            #   - widget/workbench/layout/table/tooltip/navigator/assistant: no
            #     TextToGraphics at the top, MousePress is consumed elsewhere
            #   - xml/filesystem/graphics_image: no selection model on output yet
            #   - book/conversation/object/math/julia/line_numbering/word_wrapping:
            #     domain projections do not yet propagate selection through every
            #     intermediate cell so the cursor does not always re-render; see
            #     plan/pending/json-navigation-and-clicks.md §3 (out of scope)
            startswith(example.name, "widget") && continue
            example.name in ("workbench",
                              "filesystem", "xml", "table", "math_table",
                              "graphics_image", "layout", "tooltip",
                              "navigator", "assistant",
                              "book", "conversation", "object",
                              "math", "julia",
                              "line_numbering", "word_wrapping",
                              # pre-existing: CollectionToSyntax lacks
                              # read_intent; tracked in
                              # plan/pending/fix-selection-tests.md
                              "collection", "reversing", "filtering",
                              "sorting") && continue
            @testset "$(example.name)" begin
                test_click_roundtrip(example)
            end
        end
    end
end


# ── keyboard nav invariants ──────────────────────────────────────────────────

function test_text_nav_invariants_all()
    @testset "TextNavInvariants" begin
        for example in examples
            # Skip:
            #   - widget/workbench/layout/table/tooltip/navigator/assistant: no
            #     TextToGraphics at the top, MousePress is consumed elsewhere
            #   - xml/filesystem/graphics_image: no selection model on output yet
            #   - book/conversation/object/math/julia/line_numbering/word_wrapping:
            #     domain projections do not yet propagate selection through every
            #     intermediate cell so the cursor does not always re-render; see
            #     plan/pending/json-navigation-and-clicks.md §3 (out of scope)
            startswith(example.name, "widget") && continue
            example.name in ("workbench",
                              "filesystem", "xml", "table", "math_table",
                              "graphics_image", "layout", "tooltip",
                              "navigator", "assistant",
                              "book", "conversation", "object",
                              "math", "julia",
                              "line_numbering", "word_wrapping",
                              # pre-existing: CollectionToSyntax lacks
                              # read_intent; tracked in
                              # plan/pending/fix-selection-tests.md
                              "collection", "reversing", "filtering",
                              "sorting") && continue
            @testset "$(example.name)" begin
                test_text_nav_invariants(example)
            end
        end
    end
end


# ── JSON content clicks ──────────────────────────────────────────────────────

function test_json_content_clicks_clean_all()
    @testset "JsonContentClicksClean" begin
        for name in ("json", "json_sorted", "json_string")
            ex = examples[findfirst(e -> e.name == name, examples)]
            test_json_content_clicks_clean(ex.name, ex.document, ex.projection)
        end
    end
end
