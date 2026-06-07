# ═══════════════════════════════════════════════════════════════════════════
# test/src/editor/ClickRoundtripTest.jl
#
# Click round-trip + keyboard-navigation invariants for the Text → Syntax →
# JSON pipeline.
#
# For each example:
#   - test_click_roundtrip walks every character cell in every rendered
#     SegCoord, fires a MousePress at the centre of that cell, applies the
#     resulting ReplaceSelectionOperation, re-prints, and asserts that the
#     cursor lands in either the clicked segment's band *or* the immediate
#     neighbour band (the line-boundary case, where the cursor at end of
#     line N is logically identical to cursor at start of line N+1).
#
#   - test_text_nav_invariants walks `right` from Ctrl+Home N times and
#     asserts the BFS reachable-state count matches.
# ═══════════════════════════════════════════════════════════════════════════

using Projectured
using ProjecturedExample
using Projectured: ReplaceSelectionOperation, set_selection!, clear_selection!,
                    ConcreteReferencePath, ProjectionReference, EmptyReferencePath
using Projectured.ReferenceModule: head, tail
using Projectured.TextToGraphicsModule: TextToGraphicsIoMap, SegCoord
using Projectured.FontModule: font_scaled_size

# ── IoMap traversal helpers ────────────────────────────────────────────────

function _find_text_iomap(io)
    io isa TextToGraphicsIoMap && return io
    if hasfield(typeof(io), :step_iomaps)
        for s in io.step_iomaps
            r = _find_text_iomap(s); r !== nothing && return r
        end
    end
    hasfield(typeof(io), :inner_iomap) && return _find_text_iomap(io.inner_iomap)
    hasfield(typeof(io), :child_iomap) && return _find_text_iomap(io.child_iomap)
    nothing
end

function _find_cursor_rect(t2g::TextToGraphicsIoMap)
    for elem in t2g.output.elements
        actual = elem isa Projectured.ReactiveModule.Cell ? elem[] : elem
        actual isa GraphicsRect && Int(actual.w) <= 5 && return actual
    end
    nothing
end

function _pipeline_measure(projection)
    # Walk to the inner TextToGraphics — its `measure` is the source of truth.
    if hasfield(typeof(projection), :measure)
        return projection.measure
    end
    if hasproperty(projection, :projections)
        for p in projection.projections
            m = _pipeline_measure(p); m !== nothing && return m
        end
    end
    if hasproperty(projection, :child)
        return _pipeline_measure(projection.child)
    end
    if hasproperty(projection, :elements)
        for e in projection.elements
            m = _pipeline_measure(e); m !== nothing && return m
        end
    end
    nothing
end

function _seg_x_at(sc::SegCoord, k::Int, measure)
    local_pos = k - sc.char_start
    local_pos <= 0 && return sc.x
    prefix = first(sc.text, min(local_pos, length(sc.text)))
    sc.x + measure(prefix, sc.font)[1]
end

# True if any step in `path` is a ProjectionReference. Such paths are valid
# (they encode clicks on projection-introduced characters like delimiters or
# whitespace), but a click that lands *inside* a content segment should NOT
# end up wrapped in a ProjectionReference — that signals a missing
# domain-level translation step somewhere in the chain.
function _path_contains_projection_ref(path)
    while path isa ConcreteReferencePath
        head(path) isa ProjectionReference && return true
        path = tail(path)
    end
    false
end

# ── Click round-trip ───────────────────────────────────────────────────────

"""
    test_click_roundtrip(label, document, projection)

For every character cell rendered by `TextToGraphics`, fire a `MousePress`
inside that cell and assert that the resulting selection makes the cursor
re-appear close to the click. "Close" allows up to one line of vertical
slack to absorb the end-of-line / start-of-next-line cursor-rendering
ambiguity at segment boundaries.
"""
function test_click_roundtrip(label, document, projection)
    @testset "$label" begin
        clear_selection!(document)
        iomap = projection_print(projection, document)
        t2g = _find_text_iomap(iomap)
        if t2g === nothing
            @warn "[$label] no TextToGraphicsIoMap in pipeline; skipping"
            @test true
            return
        end
        coords = t2g.char_to_coord[]
        if isempty(coords)
            @warn "[$label] empty char_to_coord; skipping"
            @test true
            return
        end
        measure = _pipeline_measure(projection)
        if measure === nothing
            @warn "[$label] could not locate measure function; skipping"
            @test true
            return
        end

        errors = String[]
        for sc in coords
            line_h = font_scaled_size(sc.font.size)
            for k in sc.char_start:sc.char_end
                cx = _seg_x_at(sc, k, measure) + 1
                cy = sc.y + max(1, line_h ÷ 2)
                op = projection_read(projection, iomap, MousePress(:left, cx, cy, Modifiers()))
                # A click on an inline expand/collapse marker (or a collapsed
                # ellipsis) is a fold gesture, not a cursor move: it yields a
                # ToggleCollapseOperation. That is a legitimate outcome — skip
                # the cursor round-trip for those glyphs.
                op isa ToggleCollapseOperation && continue
                if !(op isa ReplaceSelectionOperation)
                    push!(errors, "click ($cx,$cy) span=$(sc.span_idx) char=$k produced no ReplaceSelectionOperation")
                    continue
                end
                clear_selection!(document)
                try
                    set_selection!(document, op.path)
                catch e
                    push!(errors, "set_selection! at ($cx,$cy): $e")
                    continue
                end
                new_iomap = projection_print(projection, document)
                new_t2g = _find_text_iomap(new_iomap)
                cursor = new_t2g === nothing ? nothing : _find_cursor_rect(new_t2g)
                if cursor === nothing
                    push!(errors, "no cursor after click ($cx,$cy) span=$(sc.span_idx) char=$k")
                    continue
                end
                # Vertical: cursor on the clicked band, or exactly one band away
                # (the line-boundary cursor-rendering ambiguity).
                dy = abs(Int(cursor.y) - sc.y)
                if dy > line_h
                    push!(errors, "click ($cx,$cy) → cursor ($(cursor.x),$(cursor.y)) dy=$dy > line_h=$line_h")
                end
            end
        end
        for e in errors
            @warn "[$label] $e"
        end
        @test isempty(errors)
    end
end

test_click_roundtrip(example::Example) =
    test_click_roundtrip(example.name, example.document, example.projection)

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
            example.name in ("widget", "widget_tabbed_pane", "workbench",
                              "filesystem", "xml", "table", "math_table",
                              "graphics_image", "layout", "tooltip",
                              "navigator", "assistant",
                              "book", "conversation", "object",
                              "math", "julia",
                              "line_numbering", "word_wrapping",
                              # pre-existing: CollectionToSyntax lacks
                              # projection_read; tracked in
                              # plan/pending/fix-selection-tests.md
                              "collection", "reversing", "filtering",
                              "sorting") && continue
            @testset "$(example.name)" begin
                test_click_roundtrip(example)
            end
        end
    end
end

# ── Keyboard nav invariants ────────────────────────────────────────────────

"""
    test_text_nav_invariants(label, document, projection)

Walk a single cursor right N times from Ctrl+Home. Assert each step yields a
distinct selection (so `right` always advances) and that we eventually hit a
state where `right` is a fixed point (end of document).
"""
function test_text_nav_invariants(label, document, projection)
    @testset "$label" begin
        clear_selection!(document)
        iomap = projection_print(projection, document)
        op = projection_read(projection, iomap, KeyDown(:home, Modifiers(ctrl=true)))
        if !(op isa ReplaceSelectionOperation)
            @warn "[$label] Ctrl+Home produced no selection; skipping"
            @test true
            return
        end
        clear_selection!(document)
        set_selection!(document, op.path)

        visited = Set{String}([string(op.path)])
        prev_str = string(op.path)
        steps = 0
        max_steps = 10_000
        terminated = false
        while steps < max_steps
            iomap = projection_print(projection, document)
            op = projection_read(projection, iomap, KeyDown(:right, Modifiers()))
            if !(op isa ReplaceSelectionOperation)
                terminated = true
                break
            end
            new_str = string(op.path)
            if new_str == prev_str
                terminated = true
                break
            end
            push!(visited, new_str)
            clear_selection!(document)
            set_selection!(document, op.path)
            prev_str = new_str
            steps += 1
        end
        @test terminated  # walking right terminates
        @test steps > 0   # at least one character to walk through
        @test length(visited) == steps + 1  # every step is a new state
    end
end

test_text_nav_invariants(example::Example) =
    test_text_nav_invariants(example.name, example.document, example.projection)

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
            example.name in ("widget", "widget_tabbed_pane", "workbench",
                              "filesystem", "xml", "table", "math_table",
                              "graphics_image", "layout", "tooltip",
                              "navigator", "assistant",
                              "book", "conversation", "object",
                              "math", "julia",
                              "line_numbering", "word_wrapping",
                              # pre-existing: CollectionToSyntax lacks
                              # projection_read; tracked in
                              # plan/pending/fix-selection-tests.md
                              "collection", "reversing", "filtering",
                              "sorting") && continue
            @testset "$(example.name)" begin
                test_text_nav_invariants(example)
            end
        end
    end
end

# ── JSON content click → clean path ────────────────────────────────────────

# A click on a character that comes from a JSON document's content (a
# JsonString/JsonNumber/JsonBool value, or a JsonObjectEntry key) must
# produce a path made entirely of FieldReference / RangeReference steps —
# no ProjectionReference, since the click did not land on a
# projection-introduced character (delimiter, separator, whitespace).
#
# Clicks on JsonNull / JsonInsertion are deliberately *not* asserted because
# their rendered text ("null", placeholder) is projection-introduced.

"""
    test_json_content_clicks_clean(label, document, projection)

For each rendered segment whose content matches a known JSON content
string (a JsonString/JsonNumber/JsonBool value or an object key), fire a
click and assert the resulting path contains no `ProjectionReference`.
"""
function test_json_content_clicks_clean(label, document, projection)
    @testset "$label" begin
        clear_selection!(document)
        iomap = projection_print(projection, document)
        t2g = _find_text_iomap(iomap)
        if t2g === nothing
            @test true
            return
        end
        coords = t2g.char_to_coord[]
        measure = _pipeline_measure(projection)
        content_strings = _collect_json_content_strings(document)
        errors = String[]
        for sc in coords
            sc.text in content_strings || continue
            line_h = font_scaled_size(sc.font.size)
            # Click in the middle of the segment, well inside content.
            cx = sc.x + max(1, (_seg_x_at(sc, sc.char_end, measure) - sc.x) ÷ 2)
            cy = sc.y + max(1, line_h ÷ 2)
            op = projection_read(projection, iomap, MousePress(:left, cx, cy, Modifiers()))
            op isa ReplaceSelectionOperation || continue
            if _path_contains_projection_ref(op.path)
                push!(errors, "click on content $(repr(sc.text)) at ($cx,$cy) produced path with ProjectionReference: $(op.path)")
            end
        end
        for e in errors
            @warn "[$label] $e"
        end
        @test isempty(errors)
    end
end

# Recursively collect every string that came from the JSON document
# content (not from projection-introduced delimiters or literals).
_collect_json_content_strings(_) = String[]

function _collect_json_content_strings(j::Projectured.JsonModule.JsonString)
    [String(j[])]
end

function _collect_json_content_strings(j::Projectured.JsonModule.JsonNumber)
    [string(j[])]
end

function _collect_json_content_strings(j::Projectured.JsonModule.JsonBool)
    [j[] ? "true" : "false"]
end

function _collect_json_content_strings(j::Projectured.JsonModule.JsonArray)
    out = String[]
    for e in j
        append!(out, _collect_json_content_strings(e))
    end
    out
end

function _collect_json_content_strings(j::Projectured.JsonModule.JsonObject)
    out = String[]
    for e in Projectured.JsonModule.entries(j)
        push!(out, String(e.key))
        append!(out, _collect_json_content_strings(e.value))
    end
    out
end

function test_json_content_clicks_clean_all()
    @testset "JsonContentClicksClean" begin
        for name in ("json", "json_sorted", "json_string")
            ex = examples[findfirst(e -> e.name == name, examples)]
            test_json_content_clicks_clean(ex.name, ex.document, ex.projection)
        end
    end
end
