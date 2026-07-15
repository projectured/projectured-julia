# ═══════════════════════════════════════════════════════════════════════════
# test/editor/ExampleSweeps.jl
#
# The all-examples sweeps over the generic drivers (`ProjecturedKernelTest`)
# and the navigation presets (`ProjecturedVisualTest`). They stay in the
# umbrella because only the umbrella depends on `ProjecturedExample` — the
# generic `(label, document, projection)` driver forms are layer-agnostic and
# imported from the lower test packages (see plan/done/test-package-split.md).
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

# @broken registry for the reader sweep. `reader_broken(name)` returns a
# `(event, message) -> Bool` predicate (or `nothing`) that recognises the KNOWN
# reader failures of `name` by their root-cause error signature — so those events
# land in the `Broken` column while any *other* error stays an unmarked `Fail`.
# Update these as the underlying projections are fixed (a `@test_broken` that
# starts passing becomes an "Unexpected Pass" error, flagging the stale marker).
function reader_broken(name)
    # @broken: xml's selection reader still `::SyntaxNode`-asserts the container,
    # but block content is now a SyntaxConcatenation; every seed/click trips it.
    # plan/pending/simplest-syntax-document.md
    name == "xml" && return (ev, msg) -> occursin("SyntaxConcatenation", msg)
    # @broken: a caret on a projection-introduced token yields an under-typed
    # ProjectionReference path the graph/workbench selection maps cannot wrap.
    name in ("graph", "workbench") && return (ev, msg) -> occursin("under-typed @reference", msg)
    nothing
end

function test_readers()
    @testset "Readers" begin
        for example in examples
            @testset "$(example.name)" begin
                test_reader(example.name, example.document, example.projection;
                            broken=reader_broken(example.name))
            end
        end
    end
end

# ── repl ─────────────────────────────────────────────────────────────────────

# @broken registry for the repl sweep — same shape as `reader_broken`. A failing
# read-eval-print cycle whose error signature is recognised here lands in the
# `Broken` column; any other error stays an unmarked `Fail`.
function repl_broken(name)
    # @broken: clicking maps to a selection that fails to re-apply on these
    # domains (SelectionMismatch) — a whole class the introduced-token / phantom-
    # caret work resolves. plan/pending/simplest-syntax-document.md
    name in ("conversation", "conversation_widget", "filesystem", "navigator",
             "widget", "widget_tree") && return (ev, msg) -> occursin("SelectionMismatch", msg)
    # @broken: caret on a projection-introduced token → under-typed
    # ProjectionReference path the graph/workbench maps cannot wrap.
    name in ("graph", "workbench") && return (ev, msg) -> occursin("under-typed @reference", msg)
    # @broken: sql_update selection cell throws when re-projecting after a
    # backspace/whole-cell edit (a stale iomap `.output` and a missing
    # read_intent method); two distinct signatures.
    name == "sql_update_syntax" && return (ev, msg) ->
        occursin("FieldError(Nothing, :output)", msg) ||
        (occursin("MethodError", msg) && occursin("read_intent", msg))
    nothing
end

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
                    test_repl(example.name, example.document, example.projection;
                              broken=repl_broken(example.name))
                end
            end
        end
    end
end

# ── text navigation ──────────────────────────────────────────────────────────

function test_position_navigations()
    @testset "PositionNavigation" begin
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
                test_position_navigation(example)
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
const _position_navigation_complete_examples = ["text", "json"]

function test_position_navigations_complete()
    @testset "PositionNavigationComplete" begin
        for example in examples
            example.name in _position_navigation_complete_examples || continue
            test_position_navigation(example; check_reaches_all=true)
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
                   occursin("seed gesture", result.errors[1])
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
        # `TextBlock` (e.g. `BookParagraph.content`). Domains whose projection has
        # no string-edit reader (sorting/primitive/object) are covered elsewhere.
        #
        # Every character boundary of every string is typed at (`positions=:all`,
        # the default): ~2200 cursor positions over these six examples, half a
        # minute. `test_typein(ex; positions=:ends)` buys the time back if that
        # ever stops being worth it.
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
                              "sorting",
                              # pre-existing: on the multi-line nested SELECT a
                              # click lands one-to-two lines off the rendered
                              # caret (dy exceeds the one-band slack); a click-to-
                              # position accuracy gap in the nested layout, tracked
                              # separately from the selection-map typing.
                              "sql_nested_syntax") && continue
            @testset "$(example.name)" begin
                test_click_roundtrip(example)
            end
        end
    end
end


# ── keyboard nav invariants ──────────────────────────────────────────────────

# @broken: the leftward walk stalls partway and so neither retraces the rightward
# walk nor reaches the start. `left` clamps in place on a caret that sits in a
# zero-length span, because the step lands on the same visual caret it started
# from and the selection never changes.
#
# Optional delimiters removed most of those spans — an undelimited leaf or node no
# longer materializes an empty `open`/`close`/`sep` — which is why sql_insert_syntax
# now walks symmetrically and markdown / sql_update_syntax now reach the end. What
# remains is the width-0 *indent* slot that SyntaxToText emits before each close
# delimiter (it needs the slot to widen, and element counts must not depend on
# depth), and that still swallows a leftward step.
#
# Diagnosed in plan/pending/left-motion-stalls-on-introduced-text.md; the fix is
# deferred to the text-selection work (see plan/pending/simplest-syntax-document.md).
const NAV_LEFT_WALK_STALLS = ("json", "json_sorted", "json_insertion", "syntax",
                              "mixed", "focusing", "formula", "sql_syntax", "dragging",
                              "yaml")

# @broken: on formula and yaml the *rightward* walk also ends somewhere other than
# where Ctrl+End lands — a second, narrower asymmetry in the same forward map. On
# yaml the block-sequence indentation makes the leftward walk stall hard (it visits
# a fraction of the carets the rightward walk does).
const NAV_RIGHT_WALK_MISSES_END = ("formula", "yaml")

# @broken: these examples cannot complete a walk at all — the seed gesture or a
# reader throws partway through. Pre-existing and unrelated to navigation
# direction (they surface as uncaught errors before the walk can proceed).
const NAV_WALK_THROWS = Dict(
    # When the caret lands on a projection-introduced token (e.g. a JsonObject
    # vertex's `{` delimiter), the vertex content reader returns a
    # ProjectionReference-headed path that is under-typed, so the graph selection
    # map cannot wrap it — the seed throws before any walk starts.
    "graph"             => (:walk_right, :walk_left),
    # SelectionMismatch in set_selection! on a CollectionToSyntax leaf: an
    # undelimited PrimitiveString still offers a phantom `.open{…}` caret.
    "searching"         => (:walk_right,),
)

# The invariants a given example is known to fail, for `test_text_nav_invariants`.
# A bare `test_text_nav_invariants(example)` runs unannotated and will report the
# known failures above as plain `Fail`s; pass `broken=nav_broken(example.name)`
# to see it the way the sweep does.
function nav_broken(name)
    broken = Symbol[]
    append!(broken, get(NAV_WALK_THROWS, name, ()))
    name in NAV_LEFT_WALK_STALLS && append!(broken, (:same_length, :left_reaches_start))
    name in NAV_RIGHT_WALK_MISSES_END && push!(broken, :right_reaches_end)
    broken
end

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
                              "sorting",
                              # pre-existing: the rightward walk revisits a
                              # projection-introduced (`ProjectionReference`)
                              # caret, so it is not a chain — an unmarkable
                              # `result.cycle === nothing` failure, not a walk
                              # error. Tracked with the introduced-token-caret work.
                              "sql_nested_syntax") && continue
            @testset "$(example.name)" begin
                test_text_nav_invariants(example; broken=nav_broken(example.name))
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
