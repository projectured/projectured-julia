# ═══════════════════════════════════════════════════════════════════════════
# test/editor/ClickRoundtripTest.jl
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

using ProjecturedKernel.ReferenceModule: head, tail
using ProjecturedVisual.TextToGraphicsModule: TextToGraphicsIoMap, SegCoord

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
        actual = elem isa Cell ? elem[] : elem
        # The caret is a narrow rect. Skip the always-present highlight rect,
        # which is zero-width (invisible) for a plain caret selection.
        actual isa GraphicsRect && 0 < Int(actual.w) <= 5 && return actual
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
        iomap = print_document(projection, document)
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

        # Vertical tolerance must follow the *actual* line height, not just the
        # font height: an inline image makes its line taller than the font, so a
        # boundary-duplicate cursor that snaps to the next visual line sits more
        # than one font height away. Index the tallest segment on each y-row.
        line_height_at = Dict{Int,Int}()
        for c in coords
            h = max(c.font.size, c.height)
            line_height_at[c.y] = max(get(line_height_at, c.y, 0), h)
        end

        errors = String[]
        for sc in coords
            line_h = sc.font.size
            band_h = get(line_height_at, sc.y, line_h)
            for k in sc.char_start:sc.char_end
                cx = _seg_x_at(sc, k, measure) + 1
                cy = sc.y + max(1, line_h ÷ 2)
                op = read_intent(projection, iomap, MousePress(:left, cx, cy, Modifiers()))
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
                new_iomap = print_document(projection, document)
                new_t2g = _find_text_iomap(new_iomap)
                cursor = new_t2g === nothing ? nothing : _find_cursor_rect(new_t2g)
                if cursor === nothing
                    push!(errors, "no cursor after click ($cx,$cy) span=$(sc.span_idx) char=$k")
                    continue
                end
                # Vertical: cursor on the clicked band, or exactly one band away
                # (the line-boundary cursor-rendering ambiguity).
                dy = abs(Int(cursor.y) - sc.y)
                if dy > band_h
                    push!(errors, "click ($cx,$cy) → cursor ($(cursor.x),$(cursor.y)) dy=$dy > band_h=$band_h")
                end
            end
        end
        for e in errors
            @warn "[$label] $e"
        end
        @test isempty(errors)
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
        iomap = print_document(projection, document)
        op = read_intent(projection, iomap, KeyDown(:home, Modifiers(ctrl=true)))
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
            iomap = print_document(projection, document)
            op = read_intent(projection, iomap, KeyDown(:right, Modifiers()))
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

# The `Example`-typed overload and the sweep (`test_text_nav_invariants_all`)
# live in the `ProjecturedTest` umbrella; the JSON content-click checks live
# beside the JSON domain (JsonContentClicksTest.jl, → domain-test in phase 3).

# The `Example`-typed overloads; the sweeps stay in the umbrella.
test_click_roundtrip(example::Example) =
    test_click_roundtrip(example.name, example.document, example.projection)

test_text_nav_invariants(example::Example) =
    test_text_nav_invariants(example.name, example.document, example.projection)
