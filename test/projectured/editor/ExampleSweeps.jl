# ═══════════════════════════════════════════════════════════════════════════
# test/editor/ExampleSweeps.jl
#
# The all-examples sweeps over the generic drivers (`ProjecturedKernelTest`)
# and the navigation presets (`ProjecturedPlatformTest`). They stay in the
# umbrella because only the umbrella depends on `ProjecturedExample` — the
# generic `(label, document, projection)` driver forms are layer-agnostic and
# imported from the lower test packages (see plan/done/test-package-split.md).
# ═══════════════════════════════════════════════════════════════════════════

# ── @broken bookkeeping ───────────────────────────────────────────────────────
#
# Several sweeps carry pre-existing failures that are not yet fixed. Rather than
# leave them as unmarked `Fail`s — which would drown the one signal that matters,
# "a NEW failure = a regression" — each is recorded `@test_broken` keyed on its
# root-cause error signature. The rule the whole suite relies on: **an unmarked
# `Fail`/`Error` is always a regression.** `grep -rn "@broken:"` enumerates them.
#
# Signature-keying (not blanket per-example marking) keeps that rule honest two
# ways: a *different* error on a known-broken example is unrecognised and stays a
# `Fail`; and when the bug is fixed the `@test_broken` flips to an "Unexpected
# Pass" error, forcing the stale marker to be removed. `_all_known` is for the
# sweeps whose whole example is one `@test isempty(errors)` assertion: mark it
# broken only when EVERY collected error is a recognised signature.
_all_known(errors, sigs) =
    !isempty(errors) && all(e -> any(s -> occursin(s, e), sigs), errors)

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
    # ProjectionReferenceStep path the graph selection map cannot wrap.
    name == "graph" && return (ev, msg) -> occursin("under-typed @reference", msg)
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
    # domains (SelectionMismatchException) — a whole class the introduced-token / phantom-
    # caret work resolves. plan/pending/simplest-syntax-document.md
    name in ("conversation_widget", "filesystem", "files",
             "widget", "widget_tree") && return (ev, msg) -> occursin("SelectionMismatchException", msg)
    # @broken: caret on a projection-introduced token → under-typed
    # ProjectionReferenceStep path the graph map cannot wrap.
    name == "graph" && return (ev, msg) -> occursin("under-typed @reference", msg)
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

# @broken registry for the position-nav sweep. These examples are NOT skipped
# (they are text pipelines that ought to seed), but Ctrl+Home yields no initial
# selection today — either the seed reader throws or it returns nothing / a raw
# gesture. `posnav_seed_broken(name)` returns the seed-error signatures so the
# `state_count > 0` assertion is recorded @test_broken; if the seed later starts
# working the marker flips to an Unexpected Pass and must be removed.
function posnav_seed_broken(name)
    # @broken: seed reader throws — xml `::SyntaxNode` type-asserts a
    # SyntaxConcatenation; graph builds an under-typed ProjectionReferenceStep path.
    name == "xml"   && return ("SyntaxConcatenation",)
    name == "graph" && return ("under-typed @reference",)
    # @broken: seed produces no selection — Ctrl+Home returns nothing (these
    # domains have no whole-document caret seed yet) or a raw gesture.
    name in ("conversation_editor", "natural", "sequencechart_inspector", "sequencechart_pair") &&
        return ("returned nothing",)
    name == "rotating_vector" &&
        return ("returned nothing", "KeyDown instead of ReplaceSelectionOperation")
    nothing
end

function test_position_navigations()
    @testset "PositionNavigation" begin
        for example in examples
            # Skip widget / layout examples and assistant — the
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
                             # `chart` is a WidgetTable of charts and
                             # `chart_inspector` a WidgetSplitPane, so both are
                             # here for the widget-container reason, not a chart
                             # one — the four standalone chart examples navigate.
                             "table", "math_table", "chart", "chart_inspector",
                             # `pivot` is a bar of widgets above a WidgetTable,
                             # here for the widget-container reason as well.
                             "pivot",
                             # `workflow` is a card of widgets for each node, here
                             # for the widget-container reason as well.
                             "workflow",
                             "assistant",
                             # `fsm` is the twelve-state TCP machine. It
                             # navigates correctly — it is simply far too big
                             # for an exhaustive caret walk (tens of minutes,
                             # where every other example is seconds).
                             # `fsm_toggle` exercises the same notation on a
                             # small machine and stays in the sweep.
                             # `fsm_diagram` is a graph pipeline, here for the
                             # widget/graphics keyboard-routing reason above.
                             "fsm", "fsm_diagram",
                             # The pane trees print through `PaneToWidget`, so
                             # they are here for the widget-container reason
                             # above: the strip and the split pane hold the
                             # content, and Ctrl+Home reaches no caret in it.
                             "pane", "empty_pane", "pane_json",
                             "dbcatalog", "sql_syntax", "sql_table") && continue
            @testset "$(example.name)" begin
                sigs = posnav_seed_broken(example.name)
                test_position_navigation(example.name, example.document, example.projection;
                    seed_broken = sigs === nothing ? nothing : (errs -> _all_known(errs, sigs)))
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

# Every enumerated position/tree selection is reachable for `json` (including its
# placeholder insertion slot). `text` is the one exception: its default
# projection routes the block's content through `WordWrapping` — the same
# wrap/reorder the exclusion note above already flags — and the BFS never
# canonicalizes a reached state to the ground truth's raw `.elements[1].content{…}`
# path, so every position enumerated in that field comes back unreached. Cause
# not investigated further.
_complete_unreached_broken(name) =
    name == "text" ? (s -> startswith(s, ".elements[1].content{")) : nothing

function test_position_navigations_complete()
    @testset "PositionNavigationComplete" begin
        for example in examples
            example.name in _position_navigation_complete_examples || continue
            test_position_navigation(example.name, example.document, example.projection;
                check_reaches_all=true,
                unreached_broken=_complete_unreached_broken(example.name))
        end
    end
end

# ── tree navigation ──────────────────────────────────────────────────────────

# @broken registry for the tree-nav sweep: name -> the error signatures its walk
# is known to produce. `nothing` means "expected clean".
function tree_broken(name)
    # @broken: the tree-nav walk re-projects into a stale iomap whose `.output`
    # is nothing on these syntax-tree domains. plan/pending/simplest-syntax-document.md
    name in ("focusing", "formula", "julia", "markdown", "markdown_rendered") &&
        return ("FieldError(Nothing, :output)",)
    # @broken: xml tree selections route through an XmlElementToSyntaxNode
    # ProjectionReferenceStep the reader cannot resolve, and the block container's
    # `::SyntaxNode` type-assert trips on the SyntaxConcatenation.
    name == "xml" && return ("ProjectionReferenceStep", "SyntaxConcatenation")
    nothing
end

function test_tree_navigations()
    # Only examples whose root projects to a SyntaxNode (not a lone leaf)
    # support tree navigation — Ctrl+Alt+Home must produce a result.
    @testset "TreeNavigation" begin
        for example in examples
            (startswith(example.name, "widget") && example.name != "widget_text") && continue
            example.name in ("layout",
                             "assistant",
                             "text", "text_with_image", "graphics_image",
                             "lazy", "lazy_bidirectional") && continue
            @testset "$(example.name)" begin
                result = explore_tree_selections(example.document, example.projection)
                known = tree_broken(example.name)
                if result.state_count == 0 && !isempty(result.errors) &&
                   occursin("seed gesture", result.errors[1])
                    @info "[$(example.name)] skipped — no tree navigation support"
                elseif known !== nothing && _all_known(result.errors, known)
                    # @broken: see tree_broken above for the root cause per example.
                    @test_broken isempty(result.errors)
                    # xml errors on every state, so it reaches none — mark the
                    # count broken too; the others still explore some states.
                    if result.state_count == 0
                        @test_broken result.state_count > 0
                    else
                        @test result.state_count > 0
                    end
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
            test_tree_navigation(example; check_reaches_all=true,
                unreached_broken=_complete_unreached_broken(example.name))
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
        for name in ("json", "text", "xml", "book", "syntax")
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

# @broken registry for the click-roundtrip sweep: name -> the error signatures
# its clicks are known to produce (passed to `test_click_roundtrip`'s `broken`).
function click_broken(name)
    # @broken: clicking inside the formula grid produces no ReplaceSelection
    # operation (the grid cell has no text-cursor reader yet).
    name == "formula" && return ("produced no ReplaceSelectionOperation",)
    nothing
end

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
            #   - widget/layout/table/tooltip/files/assistant: no
            #     TextToGraphics at the top, MouseClick is consumed elsewhere
            #   - xml/filesystem/graphics_image: no selection model on output yet
            #   - book/conversation/object/math/julia/line_numbering/word_wrapping:
            #     domain projections do not yet propagate selection through every
            #     intermediate cell so the cursor does not always re-render; see
            #     plan/pending/json-navigation-and-clicks.md §3 (out of scope)
            startswith(example.name, "widget") && continue
            example.name in ("filesystem", "xml", "table", "math_table", "pivot",
                              "graphics_image", "layout", "tooltip",
                              "files", "assistant",
                              "book", "object",
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
                              "sql_nested_syntax",
                              # the FSM notation prints thousands of characters,
                              # and a click reads the whole text (about a
                              # second), so a click per character takes hours;
                              # its navigation sweeps cover the carets.
                              "fsm", "fsm_toggle") && continue
            @testset "$(example.name)" begin
                test_click_roundtrip(example.name, example.document, example.projection;
                                     broken=click_broken(example.name))
            end
        end
    end
end


# ── keyboard nav invariants ──────────────────────────────────────────────────

# @broken: the leftward walk visits fewer carets than the rightward one
# (`:same_length`) and does not arrive back at the start (`:left_reaches_start`).
# Each remaining member fails for its own reason, none of them the shared
# widened-indent round-trip (that one is handled in `_backward_zone`):
#   * text / text_with_image — a left/right asymmetry in the plain Text pipeline,
#     with no projection involved.
const NAV_LEFT_WALK_STALLS = ("text", "text_with_image")

# @broken: the rightward walk ends somewhere other than where Ctrl+End lands
# (`:right_reaches_end`). No example is known to.
const NAV_RIGHT_WALK_MISSES_END = ()

# @broken: right and left visit a different number of carets (`:same_length`)
# and the rightward walk does not end where Ctrl+End lands
# (`:right_reaches_end`); the leftward walk still lands correctly where
# Ctrl+Home does (`:left_reaches_start` passes). Cause not investigated.
const NAV_LENGTH_AND_RIGHT_END_MISMATCH = ("json", "json_sorted")

# @broken: neither direction moves past its seed caret — both walks have a
# single path entry, so the per-direction `length(result.paths) > 1` check
# fails for `:moved_right` and `:moved_left`. Cause not investigated.
const NAV_STUCK_AT_SEED = ("json_insertion",)

# @broken: these examples cannot complete a walk at all — the seed gesture or a
# reader throws partway through. Pre-existing and unrelated to navigation
# direction (they surface as uncaught errors before the walk can proceed). No
# example is known to throw.
const NAV_WALK_THROWS = Dict{String, Tuple{Vararg{Symbol}}}()

# The invariants a given example is known to fail, for `test_text_navigation_invariants`.
# A bare `test_text_navigation_invariants(example)` runs unannotated and will report the
# known failures above as plain `Fail`s; pass `broken=get_navigation_broken(example.name)`
# to see it the way the sweep does.
function get_navigation_broken(name)
    broken = Symbol[]
    append!(broken, get(NAV_WALK_THROWS, name, ()))
    name in NAV_LEFT_WALK_STALLS && append!(broken, (:same_length, :left_reaches_start))
    name in NAV_RIGHT_WALK_MISSES_END && push!(broken, :right_reaches_end)
    name in NAV_LENGTH_AND_RIGHT_END_MISMATCH && append!(broken, (:same_length, :right_reaches_end))
    name in NAV_STUCK_AT_SEED && append!(broken, (:moved_right, :moved_left))
    broken
end

function test_text_navigation_invariants_all()
    @testset "TextNavInvariants" begin
        for example in examples
            # Skip:
            #   - widget/layout/table/tooltip/files/assistant: no
            #     TextToGraphics at the top, MouseClick is consumed elsewhere
            #   - xml/filesystem/graphics_image: no selection model on output yet
            #   - book/conversation/object/math/julia/line_numbering/word_wrapping:
            #     domain projections do not yet propagate selection through every
            #     intermediate cell so the cursor does not always re-render; see
            #     plan/pending/json-navigation-and-clicks.md §3 (out of scope)
            startswith(example.name, "widget") && continue
            example.name in ("filesystem", "xml", "table", "math_table", "pivot",
                              "graphics_image", "layout", "tooltip",
                              "files", "assistant",
                              "book", "object",
                              "math", "julia",
                              "line_numbering", "word_wrapping",
                              # pre-existing: CollectionToSyntax lacks
                              # read_intent; tracked in
                              # plan/pending/fix-selection-tests.md
                              "collection", "reversing", "filtering",
                              "sorting",
                              # pre-existing: the rightward walk revisits a
                              # projection-introduced (`ProjectionReferenceStep`)
                              # caret, so it is not a chain — an unmarkable
                              # `result.cycle === nothing` failure, not a walk
                              # error. Tracked with the introduced-token-caret work.
                              "sql_nested_syntax",
                              # the FSM example prints 4432 characters, and a walk
                              # prints the whole text again for each of them (half
                              # an hour); fsm_toggle walks the same notation.
                              "fsm") && continue
            @testset "$(example.name)" begin
                # Walk a FRESH document, not the cached `example.document`: the
                # repl sweep mutates the shared instance in place, and a mutated
                # doc changes the caret walk enough to flip a `@test_broken`
                # left/right-stall marker into an Unexpected Pass. A fresh build
                # matches the isolated behaviour the markers were calibrated on.
                test_text_navigation_invariants(example.name, example.make_document(),
                                         example.make_projection(); broken=get_navigation_broken(example.name))
            end
        end
    end
end


# ── JSON content clicks ──────────────────────────────────────────────────────

function test_json_content_clicks_clean_all()
    @testset "JsonContentClicksClean" begin
        for name in ("json", "json_sorted")
            ex = examples[findfirst(e -> e.name == name, examples)]
            test_json_content_clicks_clean(ex.name, ex.document, ex.projection)
        end
    end
end
